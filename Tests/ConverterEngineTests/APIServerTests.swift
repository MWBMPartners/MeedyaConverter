// ============================================================================
// MeedyaConverter — APIServerTests (Issue #355)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import XCTest

// Per this repo's test policy (see the header comment in
// `ConverterEngineTests.swift`): `APIServer`'s five endpoint handlers and
// `routeRequest` were `private` (unreachable from any test) and are now
// `internal` — deliberately not `public`, since none of this is meant to be
// called from outside `ConverterEngine` — specifically so this file can
// reach them with `@testable import`, mirroring the existing precedent in
// `APIKeyManagerKeychainTests.swift` and `PostEncodeActionsTests.swift`'s
// `actionExecutor` seam.
@testable import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - APIServerTests
// ---------------------------------------------------------------------------
/// Tests for `APIServer`'s request-handling logic (Issue #355 — see the
/// "Make `APIServer` honest" roadmap item).
///
/// These call the handler methods (`handleProfiles`, `handleStatus`,
/// `handleQueue`, `handleEncode`, `handleProbe`, `routeRequest`) directly
/// rather than opening a real TCP socket — `APIServer` has no seam to inject
/// a mock `NWConnection`, and a live-socket integration test would be
/// slower/flakier in CI for no extra coverage of what these tests actually
/// care about: the response-JSON shape, and whether it reflects the real
/// injected `EncodingEngine` rather than the old hardcoded/fabricated
/// values. `handleConnection` / `parseHTTPRequest` / `buildHTTPResponse`
/// (raw HTTP framing) stay `private` and untested here — this task didn't
/// touch them.
///
/// `EncodingEngine()`'s default `profileStore` reads/writes
/// `~/Library/Application Support/MeedyaConverter/Profiles/` on whatever
/// machine runs the tests (there's no injection point for a temp directory
/// — `EncodingEngine` builds its own `EncodingProfileStore()` internally).
/// So nothing here calls `profileStore.addProfile`/`deleteProfile`, which
/// would persist a write to the real user's file — only read-only
/// assertions against the always-present built-in profiles. `engine.queue`,
/// by contrast, is a fresh in-memory `EncodingQueue()` per `EncodingEngine()`
/// instance with no persistence, so the queue/encode tests freely add jobs.
final class APIServerTests: XCTestCase {

    // MARK: - Helpers

    private func jsonBody(_ dict: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    }

    private func decode(_ response: APIResponse) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]) ?? [:]
    }

    private func authedRequest(
        method: HTTPMethod,
        path: String,
        apiKey: String,
        body: Data? = nil
    ) -> APIRequest {
        APIRequest(
            method: method,
            path: path,
            headers: ["authorization": "Bearer \(apiKey)"],
            body: body
        )
    }

    /// Creates an empty file in the temp directory and returns its path,
    /// for tests that need `FileManager.fileExists` to succeed without
    /// depending on any fixture in the repo.
    private func makeTempFile() -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apiservertest-\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url.path
    }

    // MARK: - GET /profiles

    func test_handleProfiles_returnsRealBuiltInProfiles_notTheOldFakeFour() {
        let engine = EncodingEngine()
        let server = APIServer(apiKey: "k", engine: engine)

        let response = server.handleProfiles(APIRequest(method: .get, path: "/profiles"))
        XCTAssertEqual(response.statusCode, 200)

        let json = decode(response)
        guard let profiles = json["profiles"] as? [[String: Any]],
              let count = json["count"] as? Int else {
            return XCTFail("Expected profiles/count in response JSON")
        }

        // Real data — at least the ~24 real built-ins, never the four
        // hardcoded "default"/"broadcast-h264"/"hevc-hdr"/"prores-422"
        // placeholders the endpoint used to return regardless of the engine.
        XCTAssertGreaterThanOrEqual(count, EncodingProfile.builtInProfiles.count)
        XCTAssertEqual(profiles.count, count)

        let names = Set(profiles.compactMap { $0["name"] as? String })
        XCTAssertTrue(names.contains("Web Standard"))
        XCTAssertFalse(names.contains("default"))
        XCTAssertFalse(names.contains("broadcast-h264"))
        XCTAssertFalse(names.contains("hevc-hdr"))
        XCTAssertFalse(names.contains("prores-422"))

        guard let webStandard = profiles.first(where: { $0["name"] as? String == "Web Standard" }) else {
            return XCTFail("Web Standard profile missing from response")
        }
        XCTAssertEqual(webStandard["isBuiltIn"] as? Bool, true)
        XCTAssertEqual(webStandard["videoCodec"] as? String, "h264")
        XCTAssertEqual(webStandard["audioCodec"] as? String, "aac")
        XCTAssertEqual(webStandard["containerFormat"] as? String, "mp4")
        XCTAssertNotNil(webStandard["id"] as? String)
        XCTAssertNotNil(webStandard["description"] as? String)
        XCTAssertNotNil(webStandard["category"] as? String)
    }

    func test_handleProfiles_countMatchesProfileStoreExactly() {
        let engine = EncodingEngine()
        let server = APIServer(apiKey: "k", engine: engine)
        let response = server.handleProfiles(APIRequest(method: .get, path: "/profiles"))
        let json = decode(response)
        XCTAssertEqual(json["count"] as? Int, engine.profileStore.allProfiles().count)
    }

    // MARK: - GET /status

    func test_handleStatus_reportsRealVersion_notTheOldHardcodedLiteral() {
        let server = APIServer(apiKey: "k")
        let response = server.handleStatus(APIRequest(method: .get, path: "/status"))
        XCTAssertEqual(response.statusCode, 200)

        let json = decode(response)
        XCTAssertEqual(json["version"] as? String, AppInfo.Version.displayString)
        XCTAssertNotEqual(json["version"] as? String, "1.0.0", "the old hardcoded literal must be gone")
    }

    func test_handleStatus_beforeStart_reportsZeroUptime() {
        let server = APIServer(apiKey: "k")
        let response = server.handleStatus(APIRequest(method: .get, path: "/status"))
        let json = decode(response)
        XCTAssertEqual(json["uptimeSeconds"] as? Double, 0)
    }

    func test_handleStatus_afterStart_reportsRealPositiveUptime() throws {
        let server = APIServer(port: 58_484, apiKey: "k")
        try server.start()
        defer { server.stop() }

        Thread.sleep(forTimeInterval: 0.05)

        let json = decode(server.handleStatus(APIRequest(method: .get, path: "/status")))
        XCTAssertEqual(json["port"] as? Int, 58_484)
        guard let uptime = json["uptimeSeconds"] as? Double else {
            return XCTFail("Expected numeric uptimeSeconds")
        }
        XCTAssertGreaterThan(uptime, 0, "uptime must be computed from a real start timestamp, not a literal")
    }

    // MARK: - GET /queue

    func test_handleQueue_emptyByDefault() {
        let engine = EncodingEngine()
        let server = APIServer(apiKey: "k", engine: engine)
        let response = server.handleQueue(APIRequest(method: .get, path: "/queue"))
        XCTAssertEqual(response.statusCode, 200)

        let json = decode(response)
        XCTAssertEqual(json["totalJobs"] as? Int, 0)
        XCTAssertEqual(json["activeJobs"] as? Int, 0)
        XCTAssertEqual(json["pendingJobs"] as? Int, 0)
        XCTAssertEqual((json["jobs"] as? [[String: Any]])?.count, 0)
    }

    func test_handleQueue_reflectsRealAddedJob_notAlwaysEmpty() {
        let engine = EncodingEngine()
        let server = APIServer(apiKey: "k", engine: engine)
        let config = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/apiservertest-in.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/apiservertest-out.mp4"),
            profile: .webStandard
        )
        let jobState = engine.queue.addJob(config)

        let json = decode(server.handleQueue(APIRequest(method: .get, path: "/queue")))
        XCTAssertEqual(json["totalJobs"] as? Int, 1)
        XCTAssertEqual(json["pendingJobs"] as? Int, 1)
        XCTAssertEqual(json["activeJobs"] as? Int, 0)

        guard let jobs = json["jobs"] as? [[String: Any]], let job = jobs.first else {
            return XCTFail("Expected one job in queue JSON")
        }
        XCTAssertEqual(job["jobId"] as? String, jobState.config.id.uuidString)
        XCTAssertEqual(job["status"] as? String, "queued")
        XCTAssertEqual(job["profile"] as? String, "Web Standard")
    }

    // MARK: - POST /encode

    func test_handleEncode_missingFields_returns400() {
        let server = APIServer(apiKey: "k")
        let response = server.handleEncode(
            APIRequest(method: .post, path: "/encode", body: jsonBody(["input": "/tmp/a.mov"]))
        )
        XCTAssertEqual(response.statusCode, 400)
    }

    func test_handleEncode_missingInputFile_returns400_neverFabricatesQueued() {
        let engine = EncodingEngine()
        let server = APIServer(apiKey: "k", engine: engine)
        let response = server.handleEncode(
            APIRequest(
                method: .post,
                path: "/encode",
                body: jsonBody([
                    "input": "/nonexistent/\(UUID().uuidString).mov",
                    "output": "/tmp/apiservertest-out.mp4",
                ])
            )
        )
        XCTAssertEqual(response.statusCode, 400)
        XCTAssertEqual(engine.queue.totalCount, 0, "a rejected job must never reach the queue")
    }

    func test_handleEncode_unknownProfile_returns400() {
        let engine = EncodingEngine()
        let server = APIServer(apiKey: "k", engine: engine)
        let inputPath = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: inputPath) }

        let response = server.handleEncode(
            APIRequest(
                method: .post,
                path: "/encode",
                body: jsonBody([
                    "input": inputPath,
                    "output": "/tmp/apiservertest-out.mp4",
                    "profile": "Not A Real Profile",
                ])
            )
        )
        XCTAssertEqual(response.statusCode, 400)
        XCTAssertEqual(engine.queue.totalCount, 0)
    }

    func test_handleEncode_validRequest_addsRealJobToQueue_returnsRealJobId() {
        let engine = EncodingEngine()
        let server = APIServer(apiKey: "k", engine: engine)
        let inputPath = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: inputPath) }

        XCTAssertEqual(engine.queue.totalCount, 0)

        let response = server.handleEncode(
            APIRequest(
                method: .post,
                path: "/encode",
                body: jsonBody([
                    "input": inputPath,
                    "output": "/tmp/apiservertest-out.mp4",
                ])
            )
        )
        XCTAssertEqual(response.statusCode, 202)
        XCTAssertEqual(engine.queue.totalCount, 1, "the job must be genuinely enqueued, not just described in the response")

        let json = decode(response)
        guard let jobId = json["jobId"] as? String else {
            return XCTFail("Expected jobId in response")
        }
        XCTAssertEqual(
            engine.queue.jobsSnapshot().first?.config.id.uuidString,
            jobId,
            "jobId must be the real queued job's ID, not an invented UUID"
        )
        XCTAssertEqual(json["profile"] as? String, "Web Standard", "falls back to the real default profile")
        XCTAssertNotNil(json["note"] as? String, "must honestly disclose the queue-runner caveat")
    }

    func test_handleEncode_explicitKnownProfile_isUsed() {
        let engine = EncodingEngine()
        let server = APIServer(apiKey: "k", engine: engine)
        let inputPath = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: inputPath) }

        let response = server.handleEncode(
            APIRequest(
                method: .post,
                path: "/encode",
                body: jsonBody([
                    "input": inputPath,
                    "output": "/tmp/apiservertest-out.mkv",
                    "profile": "ProRes HQ",
                ])
            )
        )
        XCTAssertEqual(response.statusCode, 202)
        XCTAssertEqual(engine.queue.jobsSnapshot().first?.config.profile.name, "ProRes HQ")
    }

    // MARK: - POST /probe (only the branches that don't require a real ffprobe binary)

    func test_handleProbe_missingPath_returns400() async {
        let server = APIServer(apiKey: "k")
        let response = await server.handleProbe(
            APIRequest(method: .post, path: "/probe", body: jsonBody([:]))
        )
        XCTAssertEqual(response.statusCode, 400)
    }

    func test_handleProbe_fileNotFound_returns404_neverFabricatesReady() async {
        let server = APIServer(apiKey: "k")
        let missingPath = "/nonexistent/\(UUID().uuidString).mov"
        let response = await server.handleProbe(
            APIRequest(method: .post, path: "/probe", body: jsonBody(["path": missingPath]))
        )
        XCTAssertEqual(response.statusCode, 404)

        let json = decode(response)
        XCTAssertEqual(json["exists"] as? Bool, false)
        XCTAssertEqual(json["status"] as? String, "file_not_found")
    }

    func test_handleProbe_unconfiguredEngine_reportsHonestFailure_neverFabricatesReady() async {
        // This engine never had `configure()` called, so `ffprobeInfo` is
        // nil and `engine.probe(url:)` throws — `handleProbe` must surface
        // that honestly rather than pretending the probe succeeded.
        let engine = EncodingEngine()
        let server = APIServer(apiKey: "k", engine: engine)
        let inputPath = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: inputPath) }

        let response = await server.handleProbe(
            APIRequest(method: .post, path: "/probe", body: jsonBody(["path": inputPath]))
        )
        XCTAssertNotEqual(response.statusCode, 200)
        let json = decode(response)
        XCTAssertNotEqual(json["status"] as? String, "ready")
    }

    // MARK: - Routing / auth (routeRequest)

    func test_routeRequest_missingBearerToken_returns401() async {
        let server = APIServer(apiKey: "secret")
        let response = await server.routeRequest(APIRequest(method: .get, path: "/status"))
        XCTAssertEqual(response.statusCode, 401)
    }

    func test_routeRequest_wrongBearerToken_returns401() async {
        let server = APIServer(apiKey: "secret")
        let response = await server.routeRequest(
            APIRequest(method: .get, path: "/status", headers: ["authorization": "Bearer wrong"])
        )
        XCTAssertEqual(response.statusCode, 401)
    }

    func test_routeRequest_correctBearerToken_routesToRealHandler() async {
        let server = APIServer(apiKey: "secret")
        let response = await server.routeRequest(authedRequest(method: .get, path: "/status", apiKey: "secret"))
        XCTAssertEqual(response.statusCode, 200)
    }

    func test_routeRequest_unknownPath_returns404() async {
        let server = APIServer(apiKey: "secret")
        let response = await server.routeRequest(authedRequest(method: .get, path: "/nope", apiKey: "secret"))
        XCTAssertEqual(response.statusCode, 404)
    }

    func test_routeRequest_optionsPreflight_returns204WithoutAuth() async {
        let server = APIServer(apiKey: "secret")
        let response = await server.routeRequest(APIRequest(method: .options, path: "/encode"))
        XCTAssertEqual(response.statusCode, 204)
    }
}
