// ============================================================================
// MeedyaConverter — S3MultipartUploadTests (roadmap #7, re #459/#162)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Pure, CI-runnable tests for S3 as a real `CloudUploadExecutor.uploadToCloudStorage`
// destination (`.s3`) and for the multipart flow
// (`CloudUploadExecutor.uploadS3Multipart` + the `S3Uploader`
// `CreateMultipartUpload`/`UploadPart`/`CompleteMultipartUpload`/
// `AbortMultipartUpload` request builders + XML helpers) — no real network I/O.
//
// Reuses `MockURLProtocol` from `CloudUploadExecutorTests.swift` (target-internal,
// same test module — no import needed), following the exact structure
// `CloudChunkedUploadTests.swift` established for the Dropbox/Google Drive
// chunked-upload tests: one class per file, `MockURLProtocol.reset()` in
// `setUp`/`tearDown` (its responder queue and request log are static, shared
// process-wide state).
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`
// and `CloudUploadExecutorTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class S3MultipartUploadTests: XCTestCase {

    // MARK: - Fixtures

    private var session: URLSession!
    private var tempFileURL: URL!
    private let payload = "test s3 upload payload"
    private let fixedDate = Date(timeIntervalSince1970: 1_440_938_160) // 2015-08-30T12:36:00Z

    override func setUpWithError() throws {
        try super.setUpWithError()
        MockURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)

        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("s3-multipart-tests-\(UUID().uuidString).bin")
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
    /// without writing that many real bytes — see `CloudChunkedUploadTests
    /// .makeSparseFile(size:)`, which this mirrors exactly. Only safe for a
    /// scenario that fails before the first real chunk read (the routing
    /// test below fails at `CreateMultipartUpload`, before any part is read).
    private func makeSparseFile(size: Int64) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("s3-multipart-tests-sparse-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        return url
    }

    /// The body of a request as `URLProtocol` actually sees it — see
    /// `CloudChunkedUploadTests.requestBodyData(from:)`'s doc comment for why
    /// this drains `httpBodyStream` rather than trusting `.httpBody`.
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

    private func queryItems(of request: URLRequest) throws -> [URLQueryItem] {
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return components.queryItems ?? []
    }

    private func sampleCredential() -> CloudCredential {
        CloudCredential(
            provider: .awsS3,
            apiKey: "AKIDEXAMPLE",
            secret: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            bucket: "my-bucket"
        )
    }

    // MARK: - (1) Small file → single signed PUT

    func test_uploadToCloudStorage_s3SmallFile_usesSingleSignedPUT_exactlyOneRequest() async throws {
        MockURLProtocol.enqueue { [self] request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.host, "my-bucket.s3.us-east-1.amazonaws.com")
            XCTAssertEqual(request.url?.path, "/videos/\(tempFileURL.lastPathComponent)")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = try makeResponse(for: request, statusCode: 200)
            return (response, Data())
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .s3,
            accessToken: "AKIDEXAMPLE",
            remotePath: "videos",
            label: "My Bucket",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG",
            bucket: "my-bucket",
            region: "us-east-1"
        )

        _ = try await executor.uploadToCloudStorage(fileURL: tempFileURL, config: config)

        XCTAssertEqual(MockURLProtocol.requestLog.count, 1, "A small S3 file must use the single signed PUT path, not multipart")
    }

    /// Missing S3 credential fields (secret access key / bucket) must fail
    /// honestly before any request is sent — never silently upload with a
    /// blank secret.
    func test_uploadToCloudStorage_s3MissingCredentialFields_throwsWithoutSendingAnyRequest() async throws {
        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .s3,
            accessToken: "AKIDEXAMPLE",
            remotePath: "videos",
            label: "My Bucket"
            // secretAccessKey / bucket intentionally omitted.
        )

        do {
            _ = try await executor.uploadToCloudStorage(fileURL: tempFileURL, config: config)
            XCTFail("Expected the upload to throw for a missing secret access key / bucket")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .transport = error else {
                XCTFail("Expected .transport, got \(error)")
                return
            }
            XCTAssertEqual(MockURLProtocol.requestLog.count, 0, "No request should ever be sent with incomplete S3 credentials")
        }
    }

    // MARK: - (2) Large file → routes to multipart; CreateMultipartUpload failure fails fast

    func test_uploadToCloudStorage_s3LargeFile_routesToMultipart_createFailureFailsFast() async throws {
        let bigFileURL = try makeSparseFile(size: 101 * 1024 * 1024) // > 100 MB threshold
        defer { try? FileManager.default.removeItem(at: bigFileURL) }

        MockURLProtocol.enqueue { [self] request in
            let items = try queryItems(of: request)
            XCTAssertTrue(items.contains(where: { $0.name == "uploads" }), "a large S3 file must route to CreateMultipartUpload, not a single PUT")
            XCTAssertEqual(request.httpMethod, "POST")
            let response = try makeResponse(for: request, statusCode: 403)
            return (response, Data("<Error><Code>InvalidAccessKeyId</Code></Error>".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))
        let config = CloudStorageConfig(
            provider: .s3,
            accessToken: "AKIDEXAMPLE",
            remotePath: "videos",
            label: "My Bucket",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG",
            bucket: "my-bucket",
            region: "us-east-1"
        )

        do {
            _ = try await executor.uploadToCloudStorage(fileURL: bigFileURL, config: config)
            XCTFail("Expected the upload to throw on a 403 from CreateMultipartUpload")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .httpError(let statusCode, _) = error else {
                XCTFail("Expected .httpError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 403)
            XCTAssertEqual(
                MockURLProtocol.requestLog.count, 1,
                "A CreateMultipartUpload failure must fail fast — no part uploads, no complete/abort"
            )
        }
    }

    // MARK: - (3) uploadS3Multipart: part sequencing + real ETags → correct completion XML

    func test_uploadS3Multipart_partsInOrder_andCompletesWithRealETags() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("s3-multipart-tests-12-5mib-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        // `uploadS3Multipart` clamps any requested `partSize` up to
        // `S3Uploader.minimumMultipartPartSize` (S3's real 5 MiB-per-part
        // floor, except the last part) — a fixture smaller than that limit
        // would silently collapse to a single whole-file part instead of
        // the 3 parts this test exercises. Use the real minimum as the
        // part size so the requested value is honoured verbatim.
        let partSize = S3Uploader.minimumMultipartPartSize // 5 MiB
        let totalSize = Int(partSize) * 2 + Int(partSize) / 2 // 2 full parts + 1 half-size last part
        try Data(repeating: 0x41, count: totalSize).write(to: fileURL)

        // 1: CreateMultipartUpload.
        MockURLProtocol.enqueue { [self] request in
            XCTAssertEqual(request.httpMethod, "POST")
            let items = try queryItems(of: request)
            XCTAssertTrue(items.contains(where: { $0.name == "uploads" }))
            let response = try makeResponse(for: request, statusCode: 200)
            return (
                response,
                Data(
                    (
                        "<InitiateMultipartUploadResult><Bucket>my-bucket</Bucket>"
                            + "<Key>videos/x.bin</Key><UploadId>upload-123</UploadId>"
                            + "</InitiateMultipartUploadResult>"
                    ).utf8
                )
            )
        }
        // 2-4: three UploadPart PUTs (12.5 MiB / 5 MiB chunks = 5,242,880 +
        // 5,242,880 + 2,621,440), each returning a distinct real ETag header.
        for partNumber in 1...3 {
            MockURLProtocol.enqueue { [self] request in
                XCTAssertEqual(request.httpMethod, "PUT")
                let response = try makeResponse(
                    for: request,
                    statusCode: 200,
                    headers: ["ETag": "\"etag-part-\(partNumber)\""]
                )
                return (response, Data())
            }
        }
        // 5: CompleteMultipartUpload.
        MockURLProtocol.enqueue { [self] request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = try makeResponse(for: request, statusCode: 200)
            return (
                response,
                Data(
                    (
                        "<CompleteMultipartUploadResult>"
                            + "<Location>https://my-bucket.s3.amazonaws.com/videos/x.bin</Location>"
                            + "<Bucket>my-bucket</Bucket><Key>videos/x.bin</Key>"
                            + "<ETag>\"final-etag\"</ETag></CompleteMultipartUploadResult>"
                    ).utf8
                )
            )
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))

        let result = try await executor.uploadS3Multipart(
            fileURL: fileURL,
            credential: sampleCredential(),
            objectKey: "videos/x.bin",
            partSize: partSize
        )

        let requests = MockURLProtocol.requestLog
        XCTAssertEqual(requests.count, 5, "create + 3 parts + complete")

        // Requests 1-3: sequential partNumber (1, 2, 3), same uploadId,
        // mirroring the OneDrive/Dropbox chunked tests' offset-correctness
        // assertions — this is multipart's "Content-Range-equivalent
        // semantics" (partNumber + uploadId together address the byte range
        // instead of a literal Content-Range header).
        for (index, request) in requests[1...3].enumerated() {
            let items = try queryItems(of: request)
            let partNumber = items.first(where: { $0.name == "partNumber" })?.value
            let uploadId = items.first(where: { $0.name == "uploadId" })?.value
            XCTAssertEqual(partNumber, "\(index + 1)")
            XCTAssertEqual(uploadId, "upload-123")
        }

        // Request 4: the completion XML lists every part, in order, with the
        // REAL ETags the mocked UploadPart responses returned — never
        // fabricated.
        let completeBody = try requestBodyData(from: requests[4])
        let bodyString = try XCTUnwrap(String(data: completeBody, encoding: .utf8))
        XCTAssertEqual(
            bodyString,
            "<CompleteMultipartUpload>"
                + "<Part><PartNumber>1</PartNumber><ETag>\"etag-part-1\"</ETag></Part>"
                + "<Part><PartNumber>2</PartNumber><ETag>\"etag-part-2\"</ETag></Part>"
                + "<Part><PartNumber>3</PartNumber><ETag>\"etag-part-3\"</ETag></Part>"
                + "</CompleteMultipartUpload>"
        )

        XCTAssertEqual(result.remoteURL, "https://my-bucket.s3.amazonaws.com/videos/x.bin")
        XCTAssertEqual(result.fileId, "\"final-etag\"")
        XCTAssertEqual(result.fileSize, Int64(totalSize))
    }

    // MARK: - (4) Failure mid-part → AbortMultipartUpload is called, original error preserved

    func test_uploadS3Multipart_midPartFailure_callsAbort_andNeverMasksTheOriginalError() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("s3-multipart-tests-abort-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        // See `test_uploadS3Multipart_partsInOrder_andCompletesWithRealETags`:
        // `partSize` must meet `S3Uploader.minimumMultipartPartSize` or
        // `uploadS3Multipart` clamps it up and reads the whole file as one
        // part, so "part 1 succeeds, part 2 fails" below would never
        // actually happen — the file must span more than one real part.
        let partSize = S3Uploader.minimumMultipartPartSize // 5 MiB
        let totalSize = Int(partSize) + Int(partSize) / 2 // 1 full part + 1 half-size second part
        try Data(repeating: 0x42, count: totalSize).write(to: fileURL)

        // 1: CreateMultipartUpload succeeds.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200)
            return (
                response,
                Data("<InitiateMultipartUploadResult><UploadId>upload-456</UploadId></InitiateMultipartUploadResult>".utf8)
            )
        }
        // 2: part 1 succeeds.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 200, headers: ["ETag": "\"etag-1\""])
            return (response, Data())
        }
        // 3: part 2 fails with a non-retryable status — surfaces immediately
        // as `.httpError`, without exhausting a retry schedule first.
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 403)
            return (response, Data("<Error><Code>SignatureDoesNotMatch</Code></Error>".utf8))
        }
        // 4: AbortMultipartUpload — best-effort cleanup, fired after the
        // part failure above.
        MockURLProtocol.enqueue { [self] request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            let items = try queryItems(of: request)
            XCTAssertEqual(items.first(where: { $0.name == "uploadId" })?.value, "upload-456")
            let response = try makeResponse(for: request, statusCode: 204)
            return (response, Data())
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))

        do {
            _ = try await executor.uploadS3Multipart(
                fileURL: fileURL,
                credential: sampleCredential(),
                objectKey: "videos/x.bin",
                partSize: partSize
            )
            XCTFail("Expected the upload to throw when a part upload fails")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .httpError(let statusCode, _) = error else {
                XCTFail("Expected .httpError, got \(error)")
                return
            }
            // The ORIGINAL part-upload failure, never masked by the abort
            // call that follows it.
            XCTAssertEqual(statusCode, 403)
        }

        let requests = MockURLProtocol.requestLog
        XCTAssertEqual(requests.count, 4, "create + part1 + failing part2 + abort")
        XCTAssertEqual(requests[3].httpMethod, "DELETE")
    }

    /// A `CreateMultipartUpload` failure must NOT trigger an abort — there
    /// is no real `UploadId` yet to abort, so attempting one would either
    /// no-op against a nonexistent upload or (worse) build a request with an
    /// empty `uploadId` and send it anyway.
    func test_uploadS3Multipart_createFailure_doesNotCallAbort() async throws {
        MockURLProtocol.enqueue { [self] request in
            let response = try makeResponse(for: request, statusCode: 403)
            return (response, Data("<Error><Code>InvalidAccessKeyId</Code></Error>".utf8))
        }

        let executor = CloudUploadExecutor(session: session, retryPolicy: .init(maxAttempts: 1))

        do {
            _ = try await executor.uploadS3Multipart(
                fileURL: tempFileURL,
                credential: sampleCredential(),
                objectKey: "videos/x.bin"
            )
            XCTFail("Expected the upload to throw on a CreateMultipartUpload failure")
        } catch let error as CloudUploadExecutor.UploadError {
            guard case .httpError(let statusCode, _) = error else {
                XCTFail("Expected .httpError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 403)
        }

        XCTAssertEqual(MockURLProtocol.requestLog.count, 1, "No abort request when CreateMultipartUpload itself never returned an UploadId")
    }

    // MARK: - (5) Completion XML / response parsing

    func test_buildCompleteMultipartXML_sortsPartsByNumber_andEmitsRealETagsVerbatim() {
        let parts = [
            S3Uploader.MultipartPart(partNumber: 2, eTag: "\"etag-two\""),
            S3Uploader.MultipartPart(partNumber: 1, eTag: "\"etag-one\""),
            S3Uploader.MultipartPart(partNumber: 3, eTag: "\"etag-three\""),
        ]
        let xml = S3Uploader.buildCompleteMultipartXML(parts: parts)
        let xmlString = String(data: xml, encoding: .utf8)

        XCTAssertEqual(
            xmlString,
            "<CompleteMultipartUpload>"
                + "<Part><PartNumber>1</PartNumber><ETag>\"etag-one\"</ETag></Part>"
                + "<Part><PartNumber>2</PartNumber><ETag>\"etag-two\"</ETag></Part>"
                + "<Part><PartNumber>3</PartNumber><ETag>\"etag-three\"</ETag></Part>"
                + "</CompleteMultipartUpload>"
        )
    }

    func test_parseUploadId_extractsRealValueFromInitiateResponseXML() {
        let xml = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                <Bucket>example-bucket</Bucket>
                <Key>example-object</Key>
                <UploadId>EXAMPLEJZ6e0YupT2h66iePQCc9IEbYbDUy4RTpMeoSMLPRp8Z5o1u8feSRonpvnWsKKG35tI2LB9VDPiCgTy.Gq2VxQLYjrue4Nq</UploadId>
            </InitiateMultipartUploadResult>
            """.utf8
        )

        XCTAssertEqual(
            S3Uploader.parseUploadId(from: xml),
            "EXAMPLEJZ6e0YupT2h66iePQCc9IEbYbDUy4RTpMeoSMLPRp8Z5o1u8feSRonpvnWsKKG35tI2LB9VDPiCgTy.Gq2VxQLYjrue4Nq"
        )
    }

    func test_parseUploadId_returnsNilForMalformedXML() {
        XCTAssertNil(S3Uploader.parseUploadId(from: Data("not xml at all".utf8)))
    }

    func test_parseUploadId_returnsNilWhenElementMissing() {
        let xml = Data("<InitiateMultipartUploadResult><Bucket>b</Bucket></InitiateMultipartUploadResult>".utf8)
        XCTAssertNil(S3Uploader.parseUploadId(from: xml))
    }

    /// Fixture ETag value matches AWS's own published
    /// `CompleteMultipartUpload` response example — quotes are part of the
    /// element's real text content, not added/stripped by this parser.
    func test_parseCompleteMultipartResult_extractsLocationAndETag() {
        let xml = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                <Location>https://example-bucket.s3.us-east-1.amazonaws.com/example-object</Location>
                <Bucket>example-bucket</Bucket>
                <Key>example-object</Key>
                <ETag>"3858f62230ac3c915f300c664312c11f-9"</ETag>
            </CompleteMultipartUploadResult>
            """.utf8
        )

        let result = S3Uploader.parseCompleteMultipartResult(from: xml)
        XCTAssertEqual(result.remoteURL, "https://example-bucket.s3.us-east-1.amazonaws.com/example-object")
        XCTAssertEqual(result.fileId, "\"3858f62230ac3c915f300c664312c11f-9\"")
    }

    // MARK: - (6) Request builder correctness

    func test_buildInitiateMultipartRequest_methodURLQueryHeaders() throws {
        let request = try XCTUnwrap(
            S3Uploader.buildInitiateMultipartRequest(
                credential: sampleCredential(),
                objectKey: "videos/output.mp4",
                contentType: "video/mp4",
                date: fixedDate
            )
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "my-bucket.s3.us-east-1.amazonaws.com")
        XCTAssertEqual(request.url?.path, "/videos/output.mp4")
        XCTAssertEqual(request.url?.query, "uploads=")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "video/mp4")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNotEqual(request.value(forHTTPHeaderField: "x-amz-content-sha256"), AWSV4Signer.unsignedPayload)
    }

    func test_buildInitiateMultipartRequest_returnsNilForIncompleteCredential() {
        let missingBucket = CloudCredential(provider: .awsS3, apiKey: "AKID", secret: "secret")
        XCTAssertNil(
            S3Uploader.buildInitiateMultipartRequest(
                credential: missingBucket,
                objectKey: "key.mp4",
                contentType: "video/mp4",
                date: fixedDate
            )
        )
    }

    func test_buildUploadPartRequest_methodURLQueryHeaders() throws {
        let request = try XCTUnwrap(
            S3Uploader.buildUploadPartRequest(
                credential: sampleCredential(),
                objectKey: "videos/output.mp4",
                uploadId: "upload-abc",
                partNumber: 3,
                contentLength: 1024,
                date: fixedDate
            )
        )
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.query, "partNumber=3&uploadId=upload-abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "1024")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-content-sha256"), AWSV4Signer.unsignedPayload)
    }

    func test_buildUploadPartRequest_returnsNilForNonPositivePartNumber() {
        XCTAssertNil(
            S3Uploader.buildUploadPartRequest(
                credential: sampleCredential(),
                objectKey: "key.mp4",
                uploadId: "upload-abc",
                partNumber: 0,
                contentLength: 1,
                date: fixedDate
            )
        )
    }

    func test_buildUploadPartRequest_returnsNilForEmptyUploadId() {
        XCTAssertNil(
            S3Uploader.buildUploadPartRequest(
                credential: sampleCredential(),
                objectKey: "key.mp4",
                uploadId: "",
                partNumber: 1,
                contentLength: 1,
                date: fixedDate
            )
        )
    }

    func test_buildCompleteMultipartRequest_methodURLBody() throws {
        let parts = [S3Uploader.MultipartPart(partNumber: 1, eTag: "\"etag1\"")]
        let request = try XCTUnwrap(
            S3Uploader.buildCompleteMultipartRequest(
                credential: sampleCredential(),
                objectKey: "videos/output.mp4",
                uploadId: "upload-abc",
                parts: parts,
                date: fixedDate
            )
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.query, "uploadId=upload-abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/xml")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(
            String(data: body, encoding: .utf8),
            "<CompleteMultipartUpload><Part><PartNumber>1</PartNumber><ETag>\"etag1\"</ETag></Part></CompleteMultipartUpload>"
        )
    }

    func test_buildCompleteMultipartRequest_returnsNilForEmptyParts() {
        XCTAssertNil(
            S3Uploader.buildCompleteMultipartRequest(
                credential: sampleCredential(),
                objectKey: "key.mp4",
                uploadId: "upload-abc",
                parts: [],
                date: fixedDate
            )
        )
    }

    func test_buildAbortMultipartRequest_methodURL() throws {
        let request = try XCTUnwrap(
            S3Uploader.buildAbortMultipartRequest(
                credential: sampleCredential(),
                objectKey: "videos/output.mp4",
                uploadId: "upload-abc",
                date: fixedDate
            )
        )
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.host, "my-bucket.s3.us-east-1.amazonaws.com")
        XCTAssertEqual(request.url?.query, "uploadId=upload-abc")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func test_buildAbortMultipartRequest_returnsNilForEmptyUploadId() {
        XCTAssertNil(
            S3Uploader.buildAbortMultipartRequest(
                credential: sampleCredential(),
                objectKey: "key.mp4",
                uploadId: "",
                date: fixedDate
            )
        )
    }
}
