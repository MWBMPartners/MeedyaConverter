// ============================================================================
// MeedyaConverter — RenderFarmConfigurationLoaderTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Tests for `RenderFarmConfigurationLoader` — the #346 consumer that
// turns `RenderFarmSettingsTab`'s persisted `@AppStorage` values into a
// `RenderFarmClient.Configuration` + initial agent registry.
//
// All tests target the public API surface only (no `@testable import`,
// matching `ConverterEngineTests.swift`'s own convention) and use an
// isolated, uniquely-named `UserDefaults(suiteName:)` store per test so
// nothing here ever touches — or is polluted by — the real, shared
// `UserDefaults.standard`.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class RenderFarmConfigurationLoaderTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Unique per-test suite so re-runs (and parallel test execution)
        // can never see another test's leftover values.
        suiteName = "com.mwbm.MeedyaConverter.renderFarmConfigLoader.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // -----------------------------------------------------------------
    // MARK: - Defaults match the tab's @AppStorage defaults
    // -----------------------------------------------------------------

    /// A fresh suite with no keys ever written must behave exactly like
    /// `RenderFarmSettingsTab`'s `@AppStorage` defaults: insecure
    /// transports refused, 30s discovery interval, 4 MiB chunk size, and
    /// an empty agent registry.
    func test_load_withNoStoredKeys_matchesTabDefaults() {
        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        let result = loader.load()

        XCTAssertNil(result.configuration.insecureTransportOverride)
        XCTAssertFalse(result.configuration.allowsInsecureTransports)
        XCTAssertEqual(result.configuration.discoveryIntervalSeconds, 30.0)
        XCTAssertEqual(result.configuration.chunkSizeBytes, RenderFarmProtocol.defaultChunkSizeBytes)
        XCTAssertTrue(result.agents.isEmpty)
    }

    // -----------------------------------------------------------------
    // MARK: - (a) Known settings round-trip into Configuration + registry
    // -----------------------------------------------------------------

    func test_load_withStoredSettings_producesMatchingConfigurationAndAgents() throws {
        defaults.set(true, forKey: RenderFarmConfigurationLoader.Keys.allowInsecureTransports)
        defaults.set(
            "local loopback, no real credentials",
            forKey: RenderFarmConfigurationLoader.Keys.insecureAcknowledgement
        )
        defaults.set(45.0, forKey: RenderFarmConfigurationLoader.Keys.discoveryIntervalSeconds)
        defaults.set(16, forKey: RenderFarmConfigurationLoader.Keys.chunkSizeMiB)

        let agent = RenderFarmAgentInfo(
            displayName: "studio-tower",
            host: "192.168.1.42",
            port: 2229,
            sshUsername: "render",
            discovered: false,
            architecture: "arm64",
            hardwareEncoders: ["videotoolbox", "nvenc"]
        )
        let agentsData = try JSONEncoder().encode([agent])
        defaults.set(agentsData, forKey: RenderFarmConfigurationLoader.Keys.agentsJSON)

        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        let result = loader.load()

        XCTAssertTrue(result.configuration.allowsInsecureTransports)
        XCTAssertEqual(
            result.configuration.insecureTransportOverride?.acknowledgement,
            "local loopback, no real credentials"
        )
        XCTAssertEqual(result.configuration.discoveryIntervalSeconds, 45.0)
        XCTAssertEqual(result.configuration.chunkSizeBytes, 16 * 1024 * 1024)

        XCTAssertEqual(result.agents.count, 1)
        XCTAssertEqual(result.agents[0].id, agent.id)
        XCTAssertEqual(result.agents[0].displayName, "studio-tower")
        XCTAssertEqual(result.agents[0].host, "192.168.1.42")
        XCTAssertEqual(result.agents[0].sshUsername, "render")
        XCTAssertEqual(result.agents[0].architecture, "arm64")
        XCTAssertEqual(result.agents[0].hardwareEncoders, ["videotoolbox", "nvenc"])
    }

    // -----------------------------------------------------------------
    // MARK: - (b) Empty agentsJSON Data() -> empty registry, no crash
    // -----------------------------------------------------------------

    func test_loadAgents_withEmptyData_returnsEmptyRegistry() {
        defaults.set(Data(), forKey: RenderFarmConfigurationLoader.Keys.agentsJSON)
        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        XCTAssertEqual(loader.loadAgents(), [])
    }

    // -----------------------------------------------------------------
    // MARK: - (c) Malformed agentsJSON -> empty registry, no crash
    // -----------------------------------------------------------------

    func test_loadAgents_withMalformedJSON_returnsEmptyRegistryWithoutCrashing() {
        let garbage = Data("{ this is not valid JSON at all".utf8)
        defaults.set(garbage, forKey: RenderFarmConfigurationLoader.Keys.agentsJSON)
        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        XCTAssertEqual(loader.loadAgents(), [])
    }

    /// A well-formed JSON value that nonetheless doesn't match
    /// `[RenderFarmAgentInfo]`'s shape (e.g. a future/incompatible
    /// schema) must also fail closed to an empty registry rather than
    /// throwing.
    func test_loadAgents_withValidJSONWrongShape_returnsEmptyRegistry() {
        let wrongShape = Data(#"{"totally": "not an agent array"}"#.utf8)
        defaults.set(wrongShape, forKey: RenderFarmConfigurationLoader.Keys.agentsJSON)
        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        XCTAssertEqual(loader.loadAgents(), [])
    }

    // -----------------------------------------------------------------
    // MARK: - (d) Allow-insecure but empty acknowledgement -> NOT enabled
    // -----------------------------------------------------------------

    func test_loadConfiguration_allowInsecureWithEmptyAcknowledgement_doesNotEnableInsecureTransport() {
        defaults.set(true, forKey: RenderFarmConfigurationLoader.Keys.allowInsecureTransports)
        defaults.set("", forKey: RenderFarmConfigurationLoader.Keys.insecureAcknowledgement)

        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        let configuration = loader.loadConfiguration()

        XCTAssertNil(configuration.insecureTransportOverride)
        XCTAssertFalse(configuration.allowsInsecureTransports)
    }

    /// The acknowledgement key was never written at all (e.g. the user
    /// flipped the toggle but the text field binding hasn't fired yet).
    func test_loadConfiguration_allowInsecureWithMissingAcknowledgement_doesNotEnableInsecureTransport() {
        defaults.set(true, forKey: RenderFarmConfigurationLoader.Keys.allowInsecureTransports)

        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        let configuration = loader.loadConfiguration()

        XCTAssertNil(configuration.insecureTransportOverride)
    }

    /// A whitespace-only acknowledgement is not a real acknowledgement.
    func test_loadConfiguration_allowInsecureWithWhitespaceOnlyAcknowledgement_doesNotEnableInsecureTransport() {
        defaults.set(true, forKey: RenderFarmConfigurationLoader.Keys.allowInsecureTransports)
        defaults.set("   \n\t  ", forKey: RenderFarmConfigurationLoader.Keys.insecureAcknowledgement)

        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        let configuration = loader.loadConfiguration()

        XCTAssertNil(configuration.insecureTransportOverride)
    }

    // -----------------------------------------------------------------
    // MARK: - (e) Allow-insecure + non-empty acknowledgement -> enabled
    // -----------------------------------------------------------------

    func test_loadConfiguration_allowInsecureWithAcknowledgement_enablesInsecureTransport() {
        defaults.set(true, forKey: RenderFarmConfigurationLoader.Keys.allowInsecureTransports)
        defaults.set(
            "local dev loopback, no real credentials",
            forKey: RenderFarmConfigurationLoader.Keys.insecureAcknowledgement
        )

        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        let configuration = loader.loadConfiguration()

        XCTAssertNotNil(configuration.insecureTransportOverride)
        XCTAssertTrue(configuration.allowsInsecureTransports)
        XCTAssertEqual(
            configuration.insecureTransportOverride?.acknowledgement,
            "local dev loopback, no real credentials"
        )
    }

    /// End-to-end sanity check against the real `RenderFarmClient`: a
    /// loader-produced `Configuration` with no acknowledgement must
    /// still cause `.plainHTTP` submissions to be rejected, exactly like
    /// `test_renderFarm_insecureTransportRejectedByDefault` pins for the
    /// default `Configuration`.
    func test_loadedConfiguration_stillRejectsPlainHTTPWhenAcknowledgementMissing() {
        defaults.set(true, forKey: RenderFarmConfigurationLoader.Keys.allowInsecureTransports)
        // insecureAcknowledgement intentionally left unset.

        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        let client = RenderFarmClient(
            transport: NoOpRenderFarmTransport(),
            configuration: loader.loadConfiguration()
        )
        let submission = RenderFarmJobSubmission(
            agentId: UUID(),
            profileIdentifier: "test",
            sourceFilename: "a.mov",
            sourceSHA256: "deadbeef",
            sourceSizeBytes: 10,
            transport: .plainHTTP
        )

        XCTAssertThrowsError(try client.validate(submission: submission))
    }

    /// Mirror of the above, but with a genuine acknowledgement present —
    /// the loader-produced `Configuration` must permit the submission.
    func test_loadedConfiguration_allowsPlainHTTPWhenAcknowledgementPresent() {
        defaults.set(true, forKey: RenderFarmConfigurationLoader.Keys.allowInsecureTransports)
        defaults.set("loopback test", forKey: RenderFarmConfigurationLoader.Keys.insecureAcknowledgement)

        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        let client = RenderFarmClient(
            transport: NoOpRenderFarmTransport(),
            configuration: loader.loadConfiguration()
        )
        let submission = RenderFarmJobSubmission(
            agentId: UUID(),
            profileIdentifier: "test",
            sourceFilename: "a.mov",
            sourceSHA256: "deadbeef",
            sourceSizeBytes: 10,
            transport: .plainHTTP
        )

        XCTAssertNoThrow(try client.validate(submission: submission))
    }

    // -----------------------------------------------------------------
    // MARK: - Numeric clamping
    // -----------------------------------------------------------------

    func test_loadConfiguration_clampsDiscoveryIntervalBelowMinimum() {
        defaults.set(1.0, forKey: RenderFarmConfigurationLoader.Keys.discoveryIntervalSeconds)
        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        XCTAssertEqual(loader.loadConfiguration().discoveryIntervalSeconds, 5.0)
    }

    func test_loadConfiguration_clampsDiscoveryIntervalAboveMaximum() {
        defaults.set(10_000.0, forKey: RenderFarmConfigurationLoader.Keys.discoveryIntervalSeconds)
        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        XCTAssertEqual(loader.loadConfiguration().discoveryIntervalSeconds, 300.0)
    }

    func test_loadConfiguration_clampsChunkSizeMiBBelowMinimum() {
        defaults.set(0, forKey: RenderFarmConfigurationLoader.Keys.chunkSizeMiB)
        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        XCTAssertEqual(loader.loadConfiguration().chunkSizeBytes, UInt64(1) * 1024 * 1024)
    }

    func test_loadConfiguration_clampsChunkSizeMiBAboveMaximum() {
        defaults.set(999_999, forKey: RenderFarmConfigurationLoader.Keys.chunkSizeMiB)
        let loader = RenderFarmConfigurationLoader(defaults: defaults)
        XCTAssertEqual(loader.loadConfiguration().chunkSizeBytes, UInt64(1024) * 1024 * 1024)
    }

    /// The tab's picker only ever writes one of `[1, 4, 16, 64]` MiB —
    /// verify each converts to the expected byte count with no clamping
    /// interference.
    func test_loadConfiguration_chunkSizeMiBChoices_convertExactlyToBytes() {
        for miB in [1, 4, 16, 64] {
            defaults.set(miB, forKey: RenderFarmConfigurationLoader.Keys.chunkSizeMiB)
            let loader = RenderFarmConfigurationLoader(defaults: defaults)
            XCTAssertEqual(
                loader.loadConfiguration().chunkSizeBytes,
                UInt64(miB) * 1024 * 1024,
                "\(miB) MiB should convert exactly to bytes with no clamping."
            )
        }
    }
}

// MARK: - Test fixtures

/// A transport adapter that never actually does anything. Sufficient
/// for exercising `RenderFarmClient.validate(submission:)`, which never
/// reaches the transport for a rejected submission and only reaches it
/// for the "allowed" happy-path tests above, where the returned status
/// is not itself under test.
private struct NoOpRenderFarmTransport: RenderFarmTransportAdapter, Sendable {
    func submit(
        agent: RenderFarmAgentInfo,
        submission: RenderFarmJobSubmission
    ) async throws -> RenderFarmJobStatus {
        RenderFarmJobStatus(jobId: submission.jobId, state: .queued, progress: 0)
    }

    func uploadChunk(agent: RenderFarmAgentInfo, chunk: RenderFarmChunk) async throws {}

    func status(agent: RenderFarmAgentInfo, jobId: UUID) async throws -> RenderFarmJobStatus {
        RenderFarmJobStatus(jobId: jobId, state: .completed, progress: 1.0)
    }

    func download(agent: RenderFarmAgentInfo, jobId: UUID, destination: URL) async throws -> URL {
        destination
    }

    func cancel(agent: RenderFarmAgentInfo, jobId: UUID) async throws {}
}
