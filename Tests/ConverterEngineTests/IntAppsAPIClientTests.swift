// ============================================================================
// MeedyaConverter — IntAppsAPIClientTests
// (C) 2026–present MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Pure, CI-runnable tests for `IntAppsAPIClient` and `RemoteFeatureGateProvider`
// — no real network I/O. Reuses `MockURLProtocol` (defined in
// `CloudUploadExecutorTests.swift`, same test target, internal visibility —
// see that file's header comment for why it exists rather than a
// third-party HTTP-mocking dependency) to intercept every request a
// `URLSession` makes and hand back scripted responses.
//
// Coverage, matching the roadmap #4/#5 task brief:
//   * Successful decode of a feature flag list and a single flag.
//   * `success: false` and non-2xx responses throw a typed
//     `IntAppsAPIError` — never a fabricated `FeatureFlag`.
//   * Update-check decoding, including `update_available`.
//   * `X-App-ID` / `X-API-Key` / `User-Agent` headers are present and
//     correct on every request.
//   * Dormant behaviour when credentials are absent — no request is ever
//     attempted.
//   * `RemoteFeatureGateProvider`'s fail-safe fallback when the client
//     throws (transport failure) — the compiled-in default survives.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class IntAppsAPIClientTests: XCTestCase {

    // MARK: - Fixtures

    private var session: URLSession!
    private var tempDirectory: URL!

    private let testCredentials = IntAppsAPICredentials(
        appSlug: "meedyaconverter",
        appID: "11111111-1111-1111-1111-111111111111",
        apiKey: "test-api-key-abc123",
        userAgentPrefix: "MeedyaConverter"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        MockURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("intappsapi-client-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempDirectory)
        session = nil
        tempDirectory = nil
        super.tearDown()
    }

    /// A per-test-isolated `APIKeyManager` with no stored keys and its own
    /// Keychain service — used for the dormancy test so it never touches
    /// the real user Keychain, and (since no `api_keys.json` file exists
    /// in `tempDirectory`) never touches the Keychain AT ALL, so this
    /// needs no `XCTSkip` probe unlike the write-path Keychain tests in
    /// `APIKeyManagerKeychainTests`.
    private func makeIsolatedAPIKeyManager() -> APIKeyManager {
        APIKeyManager(
            storageDirectory: tempDirectory.appendingPathComponent("keys-\(UUID().uuidString)"),
            keychainService: "Ltd.MWBMpartners.MeedyaConverter.Tests.IntAppsAPI.\(UUID().uuidString)"
        )
    }

    private func makeResponse(
        for request: URLRequest,
        statusCode: Int,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) throws -> HTTPURLResponse {
        try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        )
    }

    // MARK: - (a) Successful decode: feature flag list

    func test_fetchFeatureFlags_decodesListSuccessfully() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            let body = """
            {
              "success": true,
              "data": {
                "app_slug": "meedyaconverter",
                "features": [
                  {
                    "feature_key": "video-upload",
                    "label": "Video Upload",
                    "enabled": true,
                    "enabled_at": "2026-06-01T00:00:00Z",
                    "disabled_at": null,
                    "metadata": { "note": "enabled for testers" }
                  },
                  {
                    "feature_key": "watch-folders-v2",
                    "label": null,
                    "enabled": false,
                    "enabled_at": null,
                    "disabled_at": null,
                    "metadata": null
                  }
                ],
                "count": 2
              }
            }
            """
            return (response, Data(body.utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)
        let flags = try await client.fetchFeatureFlags(appSlug: "meedyaconverter")

        XCTAssertEqual(flags.count, 2)
        let videoUpload = try XCTUnwrap(flags.first { $0.featureKey == "video-upload" })
        XCTAssertTrue(videoUpload.enabled)
        XCTAssertEqual(videoUpload.label, "Video Upload")
        XCTAssertNotNil(videoUpload.enabledAt)
        let metadata = try XCTUnwrap(videoUpload.metadata)
        XCTAssertEqual(metadata["note"], .string("enabled for testers"))

        let watchFolders = try XCTUnwrap(flags.first { $0.featureKey == "watch-folders-v2" })
        XCTAssertFalse(watchFolders.enabled)
        XCTAssertNil(watchFolders.label)
    }

    // MARK: - (b) Successful decode: single feature flag

    func test_fetchFeatureFlag_decodesSingleFlagSuccessfully() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            let body = """
            {
              "success": true,
              "data": {
                "feature_key": "video-upload",
                "label": "Video Upload",
                "enabled": false,
                "enabled_at": null,
                "disabled_at": null,
                "metadata": null
              }
            }
            """
            return (response, Data(body.utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)
        let flag = try await client.fetchFeatureFlag(appSlug: "meedyaconverter", key: "video-upload")

        XCTAssertEqual(flag.featureKey, "video-upload")
        XCTAssertFalse(flag.enabled)
    }

    // MARK: - (c) success: false → typed error, never a fabricated flag

    func test_fetchFeatureFlags_successFalse_throwsApiFailure_neverFabricatesFlags() async throws {
        MockURLProtocol.enqueue { [self] request in
            // A 200 status carrying `success: false` is a real (if
            // unusual) shape the server could return — the client must
            // honour `success`, not just the HTTP status code.
            let response = try makeResponse(for: request, statusCode: 200)
            let body = """
            { "success": false, "error": { "code": "internal_error", "message": "feature store unavailable" } }
            """
            return (response, Data(body.utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)

        do {
            let flags = try await client.fetchFeatureFlags(appSlug: "meedyaconverter")
            XCTFail("Expected a thrown error, got a fabricated flag list: \(flags)")
        } catch let error as IntAppsAPIError {
            guard case .apiFailure(let message) = error else {
                XCTFail("Expected .apiFailure, got \(error)")
                return
            }
            XCTAssertEqual(message, "feature store unavailable")
        }
    }

    // MARK: - (d) non-2xx → typed error, never a fabricated flag

    func test_fetchFeatureFlag_404_throwsHttpError_neverFabricatesFlag() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 404)
            let body = """
            { "success": false, "error": { "code": "not_found", "message": "unknown feature key" } }
            """
            return (response, Data(body.utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)

        do {
            let flag = try await client.fetchFeatureFlag(appSlug: "meedyaconverter", key: "does-not-exist")
            XCTFail("Expected a thrown error, got a fabricated flag: \(flag)")
        } catch let error as IntAppsAPIError {
            guard case .httpError(let statusCode, let message) = error else {
                XCTFail("Expected .httpError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 404)
            XCTAssertEqual(message, "unknown feature key")
        }
    }

    func test_fetchFeatureFlags_403_forbidden_throwsHttpErrorWithRealStatus() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 403)
            return (response, Data("{\"success\":false,\"error\":{\"message\":\"access denied\"}}".utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)

        do {
            _ = try await client.fetchFeatureFlags(appSlug: "meedyaconverter")
            XCTFail("Expected a thrown error on a 403")
        } catch let error as IntAppsAPIError {
            guard case .httpError(let statusCode, _) = error else {
                XCTFail("Expected .httpError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 403)
        }
    }

    // MARK: - (e) Update-check decoding, including update_available

    func test_checkForUpdate_decodesUpdateAvailableTrue() async throws {
        MockURLProtocol.enqueue { [self] request in
            // The `version` query parameter must carry the caller's
            // current version.
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let versionItem = components.queryItems?.first { $0.name == "version" }
            XCTAssertEqual(versionItem?.value, "0.1.0")

            let response = try makeResponse(for: request, statusCode: 200)
            let body = """
            {
              "success": true,
              "data": {
                "channel": "alpha",
                "current_version": "0.2.0-alpha.3",
                "update_url": "https://mwmail.me/downloads/MeedyaConverter-0.2.0-alpha.3.dmg",
                "updated_at": "2026-07-20T12:00:00Z",
                "update_available": true,
                "client_version": "0.1.0"
              }
            }
            """
            return (response, Data(body.utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)
        let result = try await client.checkForUpdate(
            appSlug: "meedyaconverter",
            channel: "alpha",
            currentVersion: "0.1.0"
        )

        XCTAssertEqual(result.channel, "alpha")
        XCTAssertEqual(result.currentVersion, "0.2.0-alpha.3")
        XCTAssertTrue(result.updateAvailable)
        XCTAssertEqual(result.clientVersion, "0.1.0")
        XCTAssertEqual(result.updateURL.absoluteString, "https://mwmail.me/downloads/MeedyaConverter-0.2.0-alpha.3.dmg")
    }

    func test_checkForUpdate_decodesUpdateAvailableFalse() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            let body = """
            {
              "success": true,
              "data": {
                "channel": "stable",
                "current_version": "0.1.0",
                "update_url": "https://mwmail.me/downloads/MeedyaConverter-0.1.0.dmg",
                "updated_at": null,
                "update_available": false,
                "client_version": "0.1.0"
              }
            }
            """
            return (response, Data(body.utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)
        let result = try await client.checkForUpdate(
            appSlug: "meedyaconverter",
            channel: "stable",
            currentVersion: "0.1.0"
        )

        XCTAssertFalse(result.updateAvailable)
        XCTAssertNil(result.updatedAt)
    }

    // MARK: - (f) Required headers present on every request

    func test_everyRequest_carriesRequiredAuthHeaders() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            let body = """
            { "success": true, "data": { "app_slug": "meedyaconverter", "features": [], "count": 0 } }
            """
            return (response, Data(body.utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)
        _ = try await client.fetchFeatureFlags(appSlug: "meedyaconverter")

        let sentRequest = try XCTUnwrap(MockURLProtocol.requestLog.last)
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "X-App-ID"), testCredentials.appID)
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "X-API-Key"), testCredentials.apiKey)

        let userAgent = try XCTUnwrap(sentRequest.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertTrue(
            userAgent.hasPrefix(testCredentials.userAgentPrefix),
            "User-Agent '\(userAgent)' must start with the registered prefix '\(testCredentials.userAgentPrefix)' — intAppsAPI's AuthMiddleware checks str_starts_with()."
        )

        // GET requests never carry HMAC signing headers — only
        // POST/PATCH/DELETE require them per the intAppsAPI contract, and
        // this client only ever issues GETs.
        XCTAssertNil(sentRequest.value(forHTTPHeaderField: "X-Signature"))
        XCTAssertNil(sentRequest.value(forHTTPHeaderField: "X-Timestamp"))
        XCTAssertEqual(sentRequest.httpMethod, "GET")
    }

    // MARK: - (g) Dormant behaviour when credentials are missing

    func test_credentialLoader_noKeychainNoEnvironment_returnsNil() {
        let isolatedManager = makeIsolatedAPIKeyManager()
        let credentials = IntAppsAPICredentialLoader.load(apiKeyManager: isolatedManager, environment: [:])
        XCTAssertNil(credentials, "With no Keychain entry and no environment variables, credentials must be nil")
    }

    func test_configuredClient_noCredentials_isNilAndNeverConstructsAClient() {
        let isolatedManager = makeIsolatedAPIKeyManager()
        let client = IntAppsAPIClient.configured(
            apiKeyManager: isolatedManager,
            environment: [:],
            session: session
        )
        XCTAssertNil(client, "configured() must return nil — the single dormancy gate every caller relies on")
    }

    func test_remoteFeatureGateProvider_dormantWhenUnconfigured_neverMakesARequest() async throws {
        // `client: nil` mirrors exactly what `IntAppsAPIClient.configured()`
        // returns when intAppsAPI isn't provisioned for this app — the
        // real-world "unconfigured" state.
        let provider = RemoteFeatureGateProvider(
            client: nil,
            defaultFlags: ["video-upload": false],
            cacheDirectory: tempDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
        )

        let refreshed = await provider.refreshFlags()

        XCTAssertFalse(refreshed, "A dormant provider's refresh must report it did nothing")
        XCTAssertTrue(MockURLProtocol.requestLog.isEmpty, "A dormant provider must never attempt a network request")
        XCTAssertFalse(provider.isVideoUploadEnabled, "Falls back to the compiled-in default when dormant")
        XCTAssertFalse(provider.isEnabled("some-other-unknown-flag"), "Unknown keys with no default resolve to false, never true")
    }

    // MARK: - (h) RemoteFeatureGateProvider fail-safe fallback

    func test_remoteFeatureGateProvider_failSafe_whenClientThrows_keepsCompiledInDefault() async throws {
        MockURLProtocol.enqueue { _ in
            throw URLError(.notConnectedToInternet)
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)
        let provider = RemoteFeatureGateProvider(
            client: client,
            defaultFlags: ["video-upload": false],
            cacheDirectory: tempDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
        )

        // Before any refresh, and after a failed one, the answer must be
        // identical: the compiled-in default. The API being dead must
        // never crash, hang, or silently flip the flag on.
        XCTAssertFalse(provider.isVideoUploadEnabled)

        let refreshed = await provider.refreshFlags()

        XCTAssertFalse(refreshed, "A failed fetch must report failure, not a fabricated success")
        XCTAssertFalse(provider.isVideoUploadEnabled, "Fail-safe: the compiled-in default survives a dead API")
        XCTAssertEqual(MockURLProtocol.requestLog.count, 1, "One real attempt was made — this is not the dormant path")
    }

    func test_remoteFeatureGateProvider_failSafe_serverError_keepsCompiledInDefault() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 500)
            return (response, Data("{\"success\":false,\"error\":{\"message\":\"internal error\"}}".utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)
        let provider = RemoteFeatureGateProvider(
            client: client,
            defaultFlags: ["video-upload": true],
            cacheDirectory: tempDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
        )

        let refreshed = await provider.refreshFlags()

        XCTAssertFalse(refreshed)
        XCTAssertTrue(provider.isVideoUploadEnabled, "A 500 from intAppsAPI must not override the compiled-in default")
    }

    func test_remoteFeatureGateProvider_successfulRefresh_overridesCompiledInDefault() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            let body = """
            {
              "success": true,
              "data": {
                "app_slug": "meedyaconverter",
                "features": [
                  { "feature_key": "video-upload", "label": null, "enabled": true, "enabled_at": null, "disabled_at": null, "metadata": null }
                ],
                "count": 1
              }
            }
            """
            return (response, Data(body.utf8))
        }

        let client = IntAppsAPIClient(credentials: testCredentials, session: session)
        let provider = RemoteFeatureGateProvider(
            client: client,
            defaultFlags: ["video-upload": false],
            cacheDirectory: tempDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
        )

        XCTAssertFalse(provider.isVideoUploadEnabled, "Before any refresh, the compiled-in default applies")

        let refreshed = await provider.refreshFlags()

        XCTAssertTrue(refreshed)
        XCTAssertTrue(provider.isVideoUploadEnabled, "A real, honest 'enabled: true' from the server must flip the gate")
    }
}
