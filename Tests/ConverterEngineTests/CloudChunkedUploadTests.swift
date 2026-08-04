// ============================================================================
// MeedyaConverter — CloudChunkedUploadTests (roadmap item #2 / Issue #459)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Pure, CI-runnable tests for the Dropbox upload-session
// (`CloudUploadExecutor.uploadInDropboxSessionChunks`) and Google Drive
// resumable-upload (`uploadInGoogleDriveResumableChunks`) chunked-upload
// paths added for roadmap item #2 — no real network I/O.
//
// Reuses `MockURLProtocol` from `CloudUploadExecutorTests.swift`
// (target-internal, same test module — no import needed). Every test in
// this file lives in ONE class because `MockURLProtocol`'s responder queue
// and request log are static, shared process-wide state.
//
// Large-file (>150 MB) scenarios use a SPARSE file — `FileManager
// .createFile` followed by `FileHandle.truncate(atOffset:)` — which claims
// the logical size instantly without writing 150 MB of real bytes. This is
// safe here specifically because the large-file scenarios below only need
// `FileManager.attributesOfItem(atPath:)[.size]` (the size-threshold guard)
// to see a large logical size; none of them reach the `FileHandle.read`
// chunk loop (the mocked session-start response fails before any chunk is
// read).
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`
// and `CloudUploadExecutorTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class CloudChunkedUploadTests: XCTestCase {

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
            .appendingPathComponent("cloud-chunked-upload-tests-\(UUID().uuidString).bin")
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

    /// Creates a file that instantly claims `size` bytes of *logical* size
    /// (what `FileManager.attributesOfItem(atPath:)[.size]` and the
    /// executor's size-threshold guard both read) without writing that
    /// many real bytes — `FileHandle.truncate(atOffset:)` on APFS creates a
    /// sparse file. Only safe to use in a scenario that never reaches the
    /// `FileHandle.read` chunk loop (i.e. fails before the first chunk is
    /// read), since the "hole" bytes are logically zero, not real content.
    private func makeSparseFile(size: Int64) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-chunked-upload-tests-sparse-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        return url
    }

    private func dropboxAPIArg(from request: URLRequest) throws -> [String: Any] {
        let apiArgString = try XCTUnwrap(request.value(forHTTPHeaderField: "Dropbox-API-Arg"))
        let apiArgData = try XCTUnwrap(apiArgString.data(using: .utf8))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: apiArgData) as? [String: Any])
    }

    /// The body of a request as `URLProtocol` actually sees it.
    ///
    /// A `URLRequest` built with `.httpBody = someData` keeps that value
    /// on the object the *caller* holds, but the URL loading system moves
    /// the bytes into `.httpBodyStream` before handing the request to a
    /// custom `URLProtocol` for delivery — this is true even for
    /// `URLSession.data(for:)`, not just upload tasks. So the request a
    /// `MockURLProtocol` responder receives has `httpBody == nil` and the
    /// real bytes only reachable via `httpBodyStream`. Drains whichever
    /// of the two is actually populated.
    private func requestBodyData(from request: URLRequest) throws -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }
        let stream = try XCTUnwrap(
            request.httpBodyStream,
            "request has neither httpBody nor httpBodyStream"
        )
        stream.open()
        defer { stream.close() }
        var collected = Data()
        let bufferSize = 8192
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            guard bytesRead > 0 else { break }
            collected.append(buffer, count: bytesRead)
        }
        return collected
    }

    // MARK: - (1) Dropbox small file → simple upload path

    func test_dropboxSmallFile_usesSimpleUploadPath_exactlyOneRequest() async throws {
        MockURLProtocol.enqueue { [self] request in
            XCTAssertEqual(request.url?.absoluteString, DropboxUploader.uploadURL)
            XCTAssertEqual(request.httpMethod, "POST")
            // Decode the JSON rather than substring-matching the raw
            // header — `JSONSerialization` escapes "/" as "\/", so a
            // literal `.contains(...)` check would be broken by valid,
            // semantically-identical output.
            let apiArg = try dropboxAPIArg(from: request)
            XCTAssertEqual(apiArg["path"] as? String, "/Videos/\(tempFileURL.lastPathComponent)")
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"path_display\":\"/Videos/x\",\"id\":\"dbx0\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .dropbox,
            accessToken: "dbx_tok",
            remotePath: "/Videos",
            label: "Work Dropbox"
        )

        _ = try await executor.uploadToCloudStorage(fileURL: tempFileURL, config: config)

        XCTAssertEqual(MockURLProtocol.requestLog.count, 1, "A small file must use the single-request path, not a session")
    }

    // MARK: - (2) Dropbox large file → session path; start-failure fails fast

    func test_dropboxLargeFile_routesToSessionPath_startFailureFailsFast() async throws {
        let bigFileURL = try makeSparseFile(size: DropboxUploader.singleUploadMaxBytes + 1024)
        defer { try? FileManager.default.removeItem(at: bigFileURL) }

        MockURLProtocol.enqueue { [self] request in
            XCTAssertEqual(request.url?.absoluteString, DropboxUploader.sessionStartURL)
            let response = try makeResponse(for: request, statusCode: 403)
            return (response, Data("{\"error\":\"invalid_access_token\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .dropbox,
            accessToken: "dbx_tok",
            remotePath: "/Videos",
            label: "Work Dropbox"
        )

        do {
            _ = try await executor.uploadToCloudStorage(fileURL: bigFileURL, config: config)
            XCTFail("Expected the upload to throw on a 403 from session-start")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .httpError(let statusCode, _) = error else {
                XCTFail("Expected .httpError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 403)
            XCTAssertEqual(
                MockURLProtocol.requestLog.count, 1,
                "A session-start failure must fail fast with no chunk appends and no finish request"
            )
        }
    }

    // MARK: - (3) uploadInDropboxSessionChunks: offsets/cursor correctness

    func test_uploadInDropboxSessionChunks_appendOffsetsAndFinishCursorAreCorrect() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-chunked-upload-tests-100kb-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let totalSize = 100 * 1024
        try Data(repeating: 0x41, count: totalSize).write(to: fileURL)

        // 1: session start.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"session_id\":\"sess1\"}".utf8))
        }
        // 2-4: three appends (100 KB / 40 KB chunks = 40960 + 40960 + 20480)
        // all succeed with an empty body.
        for _ in 0..<3 {
            MockURLProtocol.enqueue { [self] request in
                let response = try makeResponse(for: request, statusCode: 200)
                return (response, Data())
            }
        }
        // 5: finish.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"path_display\":\"/Videos/x.bin\",\"id\":\"dbx1\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .dropbox,
            accessToken: "dbx_tok",
            remotePath: "/Videos",
            label: "Work Dropbox"
        )

        let result = try await executor.uploadInDropboxSessionChunks(
            fileURL: fileURL,
            config: config,
            chunkSize: 40 * 1024
        )

        // Inspect the real requests actually sent, in order, rather than
        // mutating captured state from inside the mock's responder
        // closures — every assertion below is against what
        // `MockURLProtocol` genuinely logged.
        let requests = MockURLProtocol.requestLog
        XCTAssertEqual(requests.count, 5, "start + 3 appends + finish")
        XCTAssertEqual(requests[0].url?.absoluteString, DropboxUploader.sessionStartURL)
        XCTAssertEqual(requests[1].url?.absoluteString, DropboxUploader.sessionAppendURL)
        XCTAssertEqual(requests[2].url?.absoluteString, DropboxUploader.sessionAppendURL)
        XCTAssertEqual(requests[3].url?.absoluteString, DropboxUploader.sessionAppendURL)
        XCTAssertEqual(requests[4].url?.absoluteString, DropboxUploader.sessionFinishURL)

        let appendOffsets = try requests[1...3].map { request -> Int64 in
            let apiArg = try dropboxAPIArg(from: request)
            let cursor = try XCTUnwrap(apiArg["cursor"] as? [String: Any])
            return try XCTUnwrap(cursor["offset"] as? Int64)
        }
        XCTAssertEqual(appendOffsets, [0, 40960, 81920])

        let finishArg = try dropboxAPIArg(from: requests[4])
        let finishCursor = try XCTUnwrap(finishArg["cursor"] as? [String: Any])
        XCTAssertEqual(finishCursor["offset"] as? Int64, Int64(totalSize))
        let commit = try XCTUnwrap(finishArg["commit"] as? [String: Any])
        XCTAssertEqual(commit["mode"] as? String, "overwrite")

        XCTAssertEqual(result.remoteURL, "/Videos/x.bin")
        XCTAssertEqual(result.fileId, "dbx1")
        XCTAssertEqual(result.fileSize, Int64(totalSize))
    }

    // MARK: - (4) Mid-chunk transient failure retries the SAME cursor offset

    func test_uploadInDropboxSessionChunks_midChunkRetry_reusesSameCursorOffset() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-chunked-upload-tests-retry-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let totalSize = 100 * 1024
        try Data(repeating: 0x42, count: totalSize).write(to: fileURL)

        // 1: session start.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"session_id\":\"sess1\"}".utf8))
        }
        // 2: append #1 (offset 0) succeeds.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data())
        }
        // 3: append #2 (offset 40960) — first attempt: transient 429.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 429)
            return (response, Data())
        }
        // 4: append #2 — retry attempt: succeeds.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data())
        }
        // 5: append #3 (offset 81920) succeeds.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data())
        }
        // 6: finish.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"path_display\":\"/Videos/x.bin\",\"id\":\"dbx1\"}".utf8))
        }

        let executor = CloudUploadExecutor(
            session: session,
            retryPolicy: .init(maxAttempts: 2, initialDelay: 0.01, maxDelay: 0.02)
        )
        let config = CloudStorageConfig(
            provider: .dropbox,
            accessToken: "dbx_tok",
            remotePath: "/Videos",
            label: "Work Dropbox"
        )

        _ = try await executor.uploadInDropboxSessionChunks(
            fileURL: fileURL,
            config: config,
            chunkSize: 40 * 1024
        )

        let requests = MockURLProtocol.requestLog
        XCTAssertEqual(requests.count, 6, "start + append1 + (append2 x2 attempts) + append3 + finish")

        // requests[2] and requests[3] are append #2's two attempts (429
        // then 200) — both must carry the identical cursor offset, since
        // the append request is built once (before `offset` advances) and
        // reused verbatim for the retry.
        let firstAttemptArg = try dropboxAPIArg(from: requests[2])
        let secondAttemptArg = try dropboxAPIArg(from: requests[3])
        let firstOffset = try XCTUnwrap((firstAttemptArg["cursor"] as? [String: Any])?["offset"] as? Int64)
        let secondOffset = try XCTUnwrap((secondAttemptArg["cursor"] as? [String: Any])?["offset"] as? Int64)
        XCTAssertEqual(firstOffset, 40960)
        XCTAssertEqual(secondOffset, 40960)
        XCTAssertEqual(firstOffset, secondOffset)
    }

    // MARK: - (5) Start response missing session_id

    func test_uploadInDropboxSessionChunks_missingSessionID_throwsHonestError() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .dropbox,
            accessToken: "dbx_tok",
            remotePath: "/Videos",
            label: "Work Dropbox"
        )

        do {
            _ = try await executor.uploadInDropboxSessionChunks(fileURL: tempFileURL, config: config)
            XCTFail("Expected a thrown error for a session-start response missing session_id")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .transport(let message) = error else {
                XCTFail("Expected .transport, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("session_id"))
            XCTAssertEqual(MockURLProtocol.requestLog.count, 1, "No append/finish requests after a malformed start response")
        }
    }

    // MARK: - (6) Google Drive small file → simple upload path

    func test_googleDriveSmallFile_usesSimpleUploadPath_exactlyOneRequestWithUploadTypeMedia() async throws {
        MockURLProtocol.enqueue { [self] request in
            let urlString = try XCTUnwrap(request.url?.absoluteString)
            XCTAssertTrue(urlString.contains("uploadType=media"))
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"id\":\"gd0\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .googleDrive,
            accessToken: "ya29.tok",
            remotePath: "/",
            label: "Personal Drive"
        )

        _ = try await executor.uploadToCloudStorage(fileURL: tempFileURL, config: config)

        XCTAssertEqual(MockURLProtocol.requestLog.count, 1, "A small file must use the single-request path, not resumable")
    }

    // MARK: - (7) Google Drive large file → resumable chunks, 308 then 200

    func test_googleDriveLargeFile_resumableChunks_nonFinal308ThenFinal200() async throws {
        let bigFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-chunked-upload-tests-gdrive-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: bigFileURL) }
        let bigSize = Int(GoogleDriveUploader.simpleUploadMaxBytes) + 1024
        try Data(repeating: 0x5A, count: bigSize).write(to: bigFileURL)

        let sessionURLString = "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=fake-session-1"

        // 1: initiate.
        MockURLProtocol.enqueue { [self] request in
            let urlString = try XCTUnwrap(request.url?.absoluteString)
            XCTAssertTrue(urlString.contains("uploadType=resumable"))
            let bodyData = try self.requestBodyData(from: request)
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(body["name"] as? String, bigFileURL.lastPathComponent)
            let response = try makeResponse(
                for: request,
                statusCode: 200,
                headers: ["Location": sessionURLString]
            )
            return (response, Data())
        }
        // 2: chunk #1 (non-final, exactly resumableChunkSize bytes) → 308.
        MockURLProtocol.enqueue { [self] request in
            XCTAssertEqual(request.url?.absoluteString, sessionURLString)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Range"),
                "bytes 0-\(bigSize - 1024 - 1)/\(bigSize)"
            )
            let response = try makeResponse(for: request, statusCode: 308)
            return (response, Data())
        }
        // 3: chunk #2 (final, the remaining 1024 bytes) → 200.
        MockURLProtocol.enqueue { [self] request in
            XCTAssertEqual(request.url?.absoluteString, sessionURLString)
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Range"),
                "bytes \(bigSize - 1024)-\(bigSize - 1)/\(bigSize)"
            )
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data("{\"id\":\"gd1\"}".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .googleDrive,
            accessToken: "ya29.tok",
            remotePath: "/",
            label: "Personal Drive"
        )

        let result = try await executor.uploadToCloudStorage(fileURL: bigFileURL, config: config)

        XCTAssertEqual(MockURLProtocol.requestLog.count, 3, "initiate + 2 chunk PUTs")
        XCTAssertEqual(result.fileId, "gd1")
        XCTAssertEqual(result.fileSize, Int64(bigSize))
    }

    // MARK: - (8) Initiate without Location header

    func test_uploadInGoogleDriveResumableChunks_missingLocationHeader_throwsHonestError() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data())
        }

        let config = CloudStorageConfig(
            provider: .googleDrive,
            accessToken: "ya29.tok",
            remotePath: "/",
            label: "Personal Drive"
        )
        let initiateRequest = try XCTUnwrap(
            CloudStorageUploader.buildGoogleDriveResumableInitRequest(
                filePath: tempFileURL.lastPathComponent,
                fileSize: Int64(payload.utf8.count),
                config: config
            )
        )

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))

        do {
            _ = try await executor.uploadInGoogleDriveResumableChunks(
                fileURL: tempFileURL,
                initiateRequest: initiateRequest
            )
            XCTFail("Expected a thrown error for an initiate response missing a Location header")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .transport(let message) = error else {
                XCTFail("Expected .transport, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Location"))
            XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
        }
    }

    // MARK: - (9) Single-chunk file whose only (final) PUT returns 308

    func test_uploadInGoogleDriveResumableChunks_finalChunk308_throwsHTTPErrorNeverFabricatesSuccess() async throws {
        // 1: initiate.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(
                for: request,
                statusCode: 200,
                headers: ["Location": "https://example.com/session/1"]
            )
            return (response, Data())
        }
        // 2: the only (final, since the whole file fits in one chunk) PUT
        // answers 308 — this must NOT be accepted as success for a final
        // chunk, unlike the non-final case.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 308)
            return (response, Data())
        }

        let config = CloudStorageConfig(
            provider: .googleDrive,
            accessToken: "ya29.tok",
            remotePath: "/",
            label: "Personal Drive"
        )
        let initiateRequest = try XCTUnwrap(
            CloudStorageUploader.buildGoogleDriveResumableInitRequest(
                filePath: tempFileURL.lastPathComponent,
                fileSize: Int64(payload.utf8.count),
                config: config
            )
        )

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))

        do {
            _ = try await executor.uploadInGoogleDriveResumableChunks(
                fileURL: tempFileURL,
                initiateRequest: initiateRequest
            )
            XCTFail("Expected the upload to throw when the final chunk returns 308")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .httpError(let statusCode, _) = error else {
                XCTFail("Expected .httpError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 308)
            XCTAssertEqual(MockURLProtocol.requestLog.count, 2, "initiate + the one (final) chunk PUT — never retried as success")
        }
    }
}
