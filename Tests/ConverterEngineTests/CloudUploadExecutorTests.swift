// ============================================================================
// MeedyaConverter — CloudUploadExecutorTests (Issue #459)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Pure, CI-runnable tests for `CloudUploadExecutor` — no real network I/O.
// A minimal `MockURLProtocol` (no `URLProtocol` mock precedent existed
// anywhere in this repo — grepped for one per the #459 task brief before
// writing this) intercepts every request `URLSession` makes and hands back
// scripted responses, so the executor's retry/backoff, status-code
// validation, and error-surfacing logic can be exercised deterministically
// and fast (retry delays are configured in hundredths of a second for these
// tests — see `RetryPolicy(initialDelay:maxDelay:)` below).
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`.
//
// Decode-only / no-media: every "upload" here is a small temp file written
// with `Data(repeating:count:)` or a short UTF-8 string — never a real
// media file or codec.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

// MARK: - MockURLProtocol

/// A minimal `URLProtocol` mock. Tests `enqueue(_:)` one responder per
/// expected request (consumed FIFO), then register `MockURLProtocol` on a
/// session's `URLSessionConfiguration.protocolClasses` so every request
/// made through that session is intercepted instead of hitting the network.
///
/// `nonisolated(unsafe)` on the static queue/log: `lock` is the actual
/// synchronization — every access happens under it — so these globals are
/// safe despite opting out of the compiler's automatic static-state check,
/// the same reasoning `SFTPUploadIOState` / `ProbeIOState` document for
/// their `@unchecked Sendable` instance state elsewhere in this codebase.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseQueue: [(URLRequest) throws -> (HTTPURLResponse, Data)] = []
    nonisolated(unsafe) private static var requestLogStorage: [URLRequest] = []

    /// Every request actually routed through this protocol, in order.
    static var requestLog: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requestLogStorage
    }

    /// Registers one responder for the next intercepted request. Consumed
    /// in FIFO order, so a test scripting "429 then 200" enqueues both
    /// responders up front and the executor's two real attempts consume
    /// them in sequence.
    static func enqueue(_ responder: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        responseQueue.append(responder)
        lock.unlock()
    }

    /// Clears both the responder queue and the request log. Called from
    /// `setUp`/`tearDown` so tests never see another test's leftover state.
    static func reset() {
        lock.lock()
        responseQueue.removeAll()
        requestLogStorage.removeAll()
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requestLogStorage.append(request)
        let responder = Self.responseQueue.isEmpty ? nil : Self.responseQueue.removeFirst()
        Self.lock.unlock()

        guard let responder else {
            // A test under-enqueued responders relative to the real
            // number of attempts the executor made — fail loudly rather
            // than hang, so a retry-count bug in either the test or the
            // executor surfaces immediately.
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No cleanup needed — `startLoading()` completes synchronously.
    }
}

// MARK: - CloudUploadExecutorTests

final class CloudUploadExecutorTests: XCTestCase {

    // MARK: - Fixtures

    private var session: URLSession!
    private var tempFileURL: URL!
    private let payload = "test upload payload"

    override func setUpWithError() throws {
        try super.setUpWithError()
        MockURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)

        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-upload-executor-tests-\(UUID().uuidString).bin")
        try Data(payload.utf8).write(to: tempFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    private func makeResponse(
        for request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:]
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

    private func makeUploadRequest(url: String = "https://example.com/upload", method: String = "POST") -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        return request
    }

    // MARK: - (a) Success only on 2xx

    func test_upload_succeedsOn200_returnsRealUploadResult() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"id\":\"abc\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let result = try await executor.upload(fileURL: tempFileURL, request: makeUploadRequest())

        XCTAssertEqual(result.fileSize, Int64(payload.utf8.count))
        XCTAssertGreaterThanOrEqual(result.uploadDuration, 0)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
    }

    func test_upload_succeedsOn201_returnsRealUploadResult() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 201)
            return (response, Data("{\"id\":\"created\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let result = try await executor.upload(fileURL: tempFileURL, request: makeUploadRequest())

        XCTAssertEqual(result.fileSize, Int64(payload.utf8.count))
    }

    func test_upload_parseSuccess_extractsRealIdentifiersFromResponseBody() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"path_display\":\"/Videos/movie.mp4\",\"id\":\"dbx_id_1\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let result = try await executor.upload(
            fileURL: tempFileURL,
            request: makeUploadRequest(),
            parseSuccess: { data, _ in
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (json?["path_display"] as? String, json?["id"] as? String)
            }
        )

        XCTAssertEqual(result.remoteURL, "/Videos/movie.mp4")
        XCTAssertEqual(result.fileId, "dbx_id_1")
    }

    // MARK: - (b) Real failure with status + body on 4xx/5xx

    func test_upload_throwsHTTPErrorWithRealStatusAndBody_on404() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 404)
            return (response, Data("{\"error\":\"path_not_found\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))

        do {
            _ = try await executor.upload(fileURL: tempFileURL, request: makeUploadRequest())
            XCTFail("Expected the upload to throw on a 404")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .httpError(let statusCode, let bodySnippet) = error else {
                XCTFail("Expected .httpError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 404)
            XCTAssertTrue(bodySnippet.contains("path_not_found"), "Body snippet must carry the real server error: \(bodySnippet)")
        }
    }

    func test_upload_nonTransient403_failsImmediatelyWithoutRetrying() async throws {
        // Only ONE responder is enqueued. If the executor retried a 403,
        // the second attempt would find an empty queue and fail with
        // .unknown instead of the real 403 — the assertion below on the
        // request count is what actually proves no retry happened.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 403)
            return (response, Data("{\"error\":\"invalid_access_token\"}".utf8))
        }

        let executor = CloudUploadExecutor(
            session: session,
            retryPolicy: .init(maxAttempts: 4, initialDelay: 0.01, maxDelay: 0.02)
        )

        do {
            _ = try await executor.upload(fileURL: tempFileURL, request: makeUploadRequest())
            XCTFail("Expected the upload to throw on a 403")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .httpError(let statusCode, _) = error else {
                XCTFail("Expected .httpError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 403)
            XCTAssertEqual(MockURLProtocol.requestLog.count, 1, "A non-transient 403 must not be retried")
        }
    }

    func test_upload_transportFailure_neverFabricatesSuccess() async throws {
        MockURLProtocol.enqueue { _ in
            throw URLError(.notConnectedToInternet)
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))

        do {
            _ = try await executor.upload(fileURL: tempFileURL, request: makeUploadRequest())
            XCTFail("Expected the upload to throw on a transport failure")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .allRetriesFailed(let lastError) = error else {
                XCTFail("Expected .allRetriesFailed, got \(error)")
                return
            }
            XCTAssertFalse(lastError.isEmpty)
        }
    }

    // MARK: - (c) Retries on 429/503 then succeeds

    func test_upload_retriesOn429ThenSucceeds() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 429)
            return (response, Data())
        }
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"id\":\"ok\"}".utf8))
        }

        let executor = CloudUploadExecutor(
            session: session,
            retryPolicy: .init(maxAttempts: 3, initialDelay: 0.01, maxDelay: 0.02)
        )
        let result = try await executor.upload(fileURL: tempFileURL, request: makeUploadRequest())

        XCTAssertEqual(MockURLProtocol.requestLog.count, 2, "Exactly one retry after the 429")
        XCTAssertEqual(result.fileSize, Int64(payload.utf8.count))
    }

    func test_upload_retriesOn503ThenSucceeds() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 503)
            return (response, Data("{\"error\":\"unavailable\"}".utf8))
        }
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"id\":\"ok\"}".utf8))
        }

        let executor = CloudUploadExecutor(
            session: session,
            retryPolicy: .init(maxAttempts: 3, initialDelay: 0.01, maxDelay: 0.02)
        )
        let result = try await executor.upload(fileURL: tempFileURL, request: makeUploadRequest())

        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
        XCTAssertEqual(result.fileSize, Int64(payload.utf8.count))
    }

    func test_upload_allRetriesExhausted_throwsRealLastErrorNeverFabricatesSuccess() async throws {
        // Three 503s in a row, matching maxAttempts: 3 — every attempt
        // genuinely fails, so the executor must throw, never fabricate
        // a success from an empty response queue.
        for _ in 0..<3 {
            MockURLProtocol.enqueue { [self] request in
                let response = try makeResponse(for: request, statusCode: 503)
                return (response, Data("{\"error\":\"unavailable\"}".utf8))
            }
        }

        let executor = CloudUploadExecutor(
            session: session,
            retryPolicy: .init(maxAttempts: 3, initialDelay: 0.01, maxDelay: 0.02)
        )

        do {
            _ = try await executor.upload(fileURL: tempFileURL, request: makeUploadRequest())
            XCTFail("Expected the upload to throw once retries are exhausted")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .allRetriesFailed(let lastError) = error else {
                XCTFail("Expected .allRetriesFailed, got \(error)")
                return
            }
            XCTAssertTrue(lastError.contains("503"), "The real last HTTP status must be in the message: \(lastError)")
            XCTAssertEqual(MockURLProtocol.requestLog.count, 3, "All 3 attempts must have been made")
        }
    }

    // MARK: - (d) Provider request-builder correctness

    func test_dropboxRequestBuilder_methodURLHeaders() throws {
        let config = CloudStorageConfig(
            provider: .dropbox,
            accessToken: "dbx_tok",
            remotePath: "/Videos",
            label: "Work Dropbox"
        )
        let request = try XCTUnwrap(
            CloudStorageUploader.buildDropboxUploadRequest(filePath: "movie.mp4", config: config)
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://content.dropboxapi.com/2/files/upload")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dbx_tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        let apiArgString = try XCTUnwrap(request.value(forHTTPHeaderField: "Dropbox-API-Arg"))
        // Decode as JSON rather than substring-matching the raw header:
        // Foundation's JSONSerialization escapes "/" as "\/" by default, so
        // a literal `.contains("/Videos/movie.mp4")` check is broken by
        // valid, semantically-identical output (JSON unescapes "\/" to "/"
        // on any conformant parse). Checking the decoded "path" value tests
        // what actually matters — the destination path Dropbox receives.
        let apiArgData = try XCTUnwrap(apiArgString.data(using: .utf8))
        let apiArg = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: apiArgData) as? [String: Any]
        )
        XCTAssertEqual(apiArg["path"] as? String, "/Videos/movie.mp4")
    }

    func test_googleDriveRequestBuilder_methodURLHeaders() throws {
        let config = CloudStorageConfig(
            provider: .googleDrive,
            accessToken: "ya29.tok",
            remotePath: "/",
            label: "Personal Drive"
        )
        let request = try XCTUnwrap(
            CloudStorageUploader.buildGoogleDriveUploadRequest(filePath: "movie.mp4", config: config)
        )

        XCTAssertEqual(request.httpMethod, "POST")
        let urlString = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(urlString.contains("googleapis.com/upload/drive/v3/files"))
        XCTAssertTrue(urlString.contains("uploadType=media"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ya29.tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
    }

    func test_oneDriveSimpleUploadRequestBuilder_methodURLHeaders() throws {
        let config = CloudStorageConfig(
            provider: .onedrive,
            accessToken: "msft_tok",
            remotePath: "/Videos",
            label: "OneDrive"
        )
        let request = try XCTUnwrap(
            CloudStorageUploader.buildOneDriveUploadRequest(filePath: "movie.mp4", config: config)
        )

        XCTAssertEqual(request.httpMethod, "PUT")
        let urlString = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(urlString.contains("graph.microsoft.com/v1.0"))
        XCTAssertTrue(urlString.contains(":/content"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer msft_tok")
    }

    func test_oneDriveCreateSessionRequestBuilder_methodURLBody() throws {
        let config = CloudStorageConfig(
            provider: .onedrive,
            accessToken: "msft_tok",
            remotePath: "/Videos",
            label: "OneDrive"
        )
        let request = try XCTUnwrap(
            CloudStorageUploader.buildOneDriveCreateSessionRequest(filePath: "big-movie.mkv", config: config)
        )

        XCTAssertEqual(request.httpMethod, "POST")
        let urlString = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(urlString.contains("/createUploadSession"))
        XCTAssertTrue(urlString.contains("Videos"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer msft_tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let bodyData = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        XCTAssertTrue(bodyString.contains("conflictBehavior"))
    }

    // MARK: - uploadToCloudStorage: OneDrive size-based routing

    func test_uploadToCloudStorage_oneDrive_smallFile_usesSimpleContentUpload() async throws {
        MockURLProtocol.enqueue { [self] request in
            XCTAssertTrue(request.url?.absoluteString.contains(":/content") == true)
            XCTAssertEqual(request.httpMethod, "PUT")
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"id\":\"small-item\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .onedrive,
            accessToken: "tok",
            remotePath: "/Videos",
            label: "OneDrive"
        )

        let result = try await executor.uploadToCloudStorage(fileURL: tempFileURL, config: config)

        XCTAssertEqual(MockURLProtocol.requestLog.count, 1, "A small file must use the single-PUT path, not a session")
        XCTAssertEqual(result.fileSize, Int64(payload.utf8.count))
    }

    func test_uploadToCloudStorage_oneDrive_largeFile_usesUploadSession() async throws {
        // A file just over OneDriveUploader.simpleUploadMaxBytes (4 MB)
        // must route through the create-session + chunked-PUT path —
        // required for OneDrive per the #459 task brief, since the
        // simple /content endpoint rejects anything this large.
        let bigFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-upload-executor-tests-large-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: bigFileURL) }
        let bigSize = Int(OneDriveUploader.simpleUploadMaxBytes) + 1024
        try Data(repeating: 0x42, count: bigSize).write(to: bigFileURL)

        // 1: create-session response carries the real uploadUrl.
        MockURLProtocol.enqueue { [self] request in
            XCTAssertTrue(request.url?.absoluteString.contains("/createUploadSession") == true)
            XCTAssertEqual(request.httpMethod, "POST")
            let body = "{\"uploadUrl\":\"https://graph.microsoft.com/fake-session/1\"}"
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data(body.utf8))
        }
        // 2: the file fits in a single chunk (default fragmentSize is
        // 10 MB, well over ~4 MB), so exactly one chunk PUT follows.
        MockURLProtocol.enqueue { [self] request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.absoluteString, "https://graph.microsoft.com/fake-session/1")
            let contentRange = request.value(forHTTPHeaderField: "Content-Range")
            XCTAssertEqual(contentRange, "bytes 0-\(bigSize - 1)/\(bigSize)")
            let body = "{\"id\":\"large-item\",\"webUrl\":\"https://onedrive.example/large-item\"}"
            let response = try makeResponse(for: request, statusCode: 201)
            return (response, Data(body.utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .onedrive,
            accessToken: "tok",
            remotePath: "/Videos",
            label: "OneDrive"
        )

        let result = try await executor.uploadToCloudStorage(fileURL: bigFileURL, config: config)

        XCTAssertEqual(MockURLProtocol.requestLog.count, 2, "create-session + exactly one chunk PUT")
        XCTAssertEqual(result.remoteURL, "https://onedrive.example/large-item")
        XCTAssertEqual(result.fileId, "large-item")
        XCTAssertEqual(result.fileSize, Int64(bigSize))
    }

    func test_uploadToCloudStorage_oneDrive_sessionMissingUploadURL_throwsHonestError() async throws {
        MockURLProtocol.enqueue { [self] request in
            // Malformed session response — no "uploadUrl" field.
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{}".utf8))
        }

        let bigFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-upload-executor-tests-large-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: bigFileURL) }
        let bigSize = Int(OneDriveUploader.simpleUploadMaxBytes) + 1024
        try Data(repeating: 0x00, count: bigSize).write(to: bigFileURL)

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .onedrive,
            accessToken: "tok",
            remotePath: "/Videos",
            label: "OneDrive"
        )

        do {
            _ = try await executor.uploadToCloudStorage(fileURL: bigFileURL, config: config)
            XCTFail("Expected a thrown error for a session response missing uploadUrl")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .transport(let message) = error else {
                XCTFail("Expected .transport, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("uploadUrl"))
            // Only the create-session request should have gone out — no
            // fabricated chunk PUT after a malformed session response.
            XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
        }
    }
}
