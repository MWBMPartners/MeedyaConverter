// ============================================================================
// MeedyaConverter — CloudUploadExecutor (Issue #459)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CloudUploadExecutor

/// Executes cloud-storage upload `URLRequest`s built by
/// `CloudStorageUploader` (Dropbox / Google Drive / OneDrive) and
/// `S3Uploader` (S3 — roadmap #7, re #459/#162) and reports the real,
/// verified outcome.
///
/// Before this type existed, every "upload" in this codebase stopped at
/// building a `URLRequest` — nothing in `ConverterEngine` actually sent
/// the bytes or inspected the server's response (see the doc comment
/// this replaced on `PostEncodeActionType.uploadCloud`, and the
/// `CloudStorageView.validateConfig()` method it also replaced — both
/// only confirmed a request *could be built*, never that anything was
/// *uploaded*). `CloudUploadExecutor` closes that gap using the same
/// `URLSession` pattern already proven at
/// `MediaServerNotifier.sendLibraryScan(config:)` and
/// `WebhookSender.performRequest(bodyData:config:)`:
///
/// - The request is actually sent — `URLSession.upload(for:fromFile:)`
///   for whole-file transfers, or sequential chunked requests for
///   provider "upload session" large-file transfers:
///   `Content-Range`-addressed `PUT`s for OneDrive (`uploadInSessionChunks`)
///   and Google Drive (`uploadInGoogleDriveResumableChunks`), or
///   cursor-addressed `POST`s for Dropbox's upload-session protocol
///   (`uploadInDropboxSessionChunks`) — required (not optional) once a
///   file exceeds `DropboxUploader.singleUploadMaxBytes` (150 MB) or
///   `GoogleDriveUploader.simpleUploadMaxBytes` (5 MB), same as it
///   already was for OneDrive's 4 MB simple-upload limit. S3 gets its own
///   real multipart protocol (`uploadS3Multipart`) — AWS's
///   `CreateMultipartUpload`/`UploadPart`/`CompleteMultipartUpload`/
///   `AbortMultipartUpload`, not a `Content-Range`/cursor scheme —
///   required above `S3Uploader.shouldUseMultipart(fileSize:)`'s 100 MB
///   threshold.
/// - Only a genuine `2xx` HTTP status is treated as success — except
///   Google Drive's resumable-upload chunks, where a non-final chunk's
///   documented, real success response is `308 Resume Incomplete`
///   rather than `2xx` (see `executeWithRetry(additionalSuccessStatusCodes:)`
///   and `uploadInGoogleDriveResumableChunks`'s doc comment for how that
///   stays scoped to non-final chunks only, never fabricating success
///   on a `308` that means bytes are actually missing).
/// - Any other status — or a transport-level failure (DNS, TLS, timeout,
///   connection reset, a filesystem error reading the local file) —
///   surfaces as a thrown `UploadError` carrying the real status code
///   and a snippet of the real response body. Nothing is ever
///   fabricated.
/// - Transient failures (429 Too Many Requests, 5xx) are retried with
///   bounded exponential backoff — the same shape as
///   `WebhookSender.send(payload:config:)`'s retry loop, generalised to
///   branch on HTTP status as well as thrown errors. Non-transient
///   failures (401/403/404/409/...) fail fast on the first response —
///   retrying an invalid token or a permissions error can never
///   succeed, so there is no reason to make the caller wait through the
///   whole backoff schedule to find that out.
///
/// **Honesty contract**: this type NEVER returns a successful
/// `UploadResult` unless the server actually accepted the request with
/// a `2xx` status. Every failure path throws `UploadError`, carrying
/// the real cause — see `CloudUploadExecutorTests` for the tests that
/// pin this down against a `URLProtocol` mock (no real network I/O).
///
/// A plain struct rather than an actor or class: every stored property
/// is an immutable `let`, set once at `init` and never mutated again, so
/// there is no actor isolation needed to protect mutable state — the
/// struct is trivially safe to share across concurrency domains and
/// cheap to construct per call, exactly like `WebhookSender` and
/// `MediaServerNotifier` elsewhere in this file's neighbourhood.
/// `@unchecked Sendable` rather than plain `Sendable`: `URLSession` is
/// itself thread-safe by design (it is documented as safe to share and
/// use concurrently from multiple threads), but this file does not rely
/// on the compiler having that exact `Sendable` audit recorded for the
/// SDK's `URLSession` — the `let`-only, write-once-at-init shape here is
/// what actually makes sharing this type safe, so `@unchecked` states
/// that reasoning explicitly rather than depending on an SDK annotation
/// this file can't independently verify.
public struct CloudUploadExecutor: @unchecked Sendable {

    // MARK: - RetryPolicy

    /// Bounded exponential-backoff retry configuration.
    public struct RetryPolicy: Sendable {
        /// Total attempts, including the first. `1` disables retrying
        /// (still exhausts one attempt, so a transient failure with
        /// `maxAttempts == 1` still surfaces as `.allRetriesFailed`,
        /// never fabricated success).
        public var maxAttempts: Int

        /// Delay before the first retry, in seconds. Doubles on each
        /// subsequent retry (`initialDelay * 2^(attempt - 1)`), capped
        /// at `maxDelay`.
        public var initialDelay: TimeInterval

        /// Upper bound on the backoff delay, in seconds.
        public var maxDelay: TimeInterval

        /// HTTP status codes considered transient and worth retrying.
        /// Anything outside this set (e.g. 401, 403, 404, 409) fails
        /// immediately on the first non-2xx response.
        public var retryableStatusCodes: Set<Int>

        public init(
            maxAttempts: Int = 4,
            initialDelay: TimeInterval = 1.0,
            maxDelay: TimeInterval = 20.0,
            retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]
        ) {
            self.maxAttempts = max(1, maxAttempts)
            self.initialDelay = initialDelay
            self.maxDelay = maxDelay
            self.retryableStatusCodes = retryableStatusCodes
        }

        /// The default policy: 4 attempts, 1s/2s/4s backoff capped at 20s.
        public static let `default` = RetryPolicy()
    }

    // MARK: - UploadError

    /// A real upload failure. Never fabricated — every case carries
    /// information the server or `URLSession` actually reported.
    public enum UploadError: LocalizedError, Sendable {
        /// The response was not an `HTTPURLResponse` (should not happen
        /// for `http(s)://` requests, but `URLSession` does not
        /// statically guarantee it).
        case invalidResponse

        /// The server responded with a non-`2xx` status that is not in
        /// `RetryPolicy.retryableStatusCodes` (or the last retry
        /// attempt for a status that is). `bodySnippet` is the real
        /// response body (truncated for readability), so the caller can
        /// surface the provider's actual error message.
        case httpError(statusCode: Int, bodySnippet: String)

        /// A transport-level failure with no HTTP response at all — DNS,
        /// TLS, timeout, connection reset, or a filesystem error reading
        /// the local file (e.g. an unreadable upload-session response).
        case transport(String)

        /// Every retry attempt failed (each attempt either hit a
        /// retryable HTTP status or a transport error). Carries the
        /// most recent attempt's real error description.
        case allRetriesFailed(lastError: String)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The server returned a response that was not a valid HTTP response."
            case .httpError(let statusCode, let bodySnippet):
                return "Upload failed with HTTP \(statusCode): \(bodySnippet)"
            case .transport(let message):
                return "Upload failed: \(message)"
            case .allRetriesFailed(let lastError):
                return "Upload failed after all retry attempts. Last error: \(lastError)"
            }
        }
    }

    // MARK: - Properties

    private let session: URLSession
    private let retryPolicy: RetryPolicy

    // MARK: - Initialiser

    /// - Parameters:
    ///   - session: The `URLSession` to execute requests on. Defaults to
    ///     `.shared`; tests inject a session configured with a
    ///     `URLProtocol` mock (see `CloudUploadExecutorTests`) so no
    ///     real network I/O ever occurs.
    ///   - retryPolicy: Retry/backoff configuration. Defaults to
    ///     `.default` (4 attempts, 1s/2s/4s backoff).
    public init(session: URLSession = .shared, retryPolicy: RetryPolicy = .default) {
        self.session = session
        self.retryPolicy = retryPolicy
    }

    // MARK: - Whole-file upload

    /// Uploads `fileURL`'s bytes as the body of `request` and returns the
    /// real outcome.
    ///
    /// Streams the file directly from disk via
    /// `URLSession.upload(for:fromFile:)` — the file is never fully
    /// loaded into memory, which matters for the multi-gigabyte media
    /// files this app produces. `request` should already carry the
    /// provider's method, URL, and headers (built by
    /// `CloudStorageUploader` or an equivalent provider builder); this
    /// method only adds transport, retry, and progress.
    ///
    /// - Parameters:
    ///   - fileURL: The local file to upload.
    ///   - request: The provider-specific upload request (method, URL,
    ///     headers already set; the file supplies the body).
    ///   - progress: Optional callback invoked with byte-level progress
    ///     as the upload proceeds, via a `URLSessionTaskDelegate`
    ///     (`UploadProgressObserver`, below). Called on whatever thread
    ///     `URLSession`'s delegate queue uses — NOT guaranteed to be the
    ///     main actor. Callers updating UI state must hop back
    ///     themselves — see `CloudStorageView.performUpload()`'s
    ///     `AsyncStream` bridge for the pattern this codebase uses.
    ///   - parseSuccess: Optional callback that inspects the real 2xx
    ///     response body/headers and extracts provider-specific
    ///     identifiers (e.g. Dropbox's `path_display`/`id`, Google
    ///     Drive's `id`/`webViewLink`). When omitted, `remoteURL`/
    ///     `fileId` on the returned `UploadResult` are `nil` — never
    ///     guessed.
    /// - Returns: An `UploadResult` — only ever returned after a real
    ///   `2xx` response.
    /// - Throws: `UploadError` describing the real failure.
    public func upload(
        fileURL: URL,
        request: URLRequest,
        progress: (@Sendable (UploadProgress) -> Void)? = nil,
        parseSuccess: (@Sendable (Data, HTTPURLResponse) -> (remoteURL: String?, fileId: String?))? = nil
    ) async throws -> UploadResult {
        let start = Date()
        let totalBytes = Self.fileSize(at: fileURL) ?? 0

        let (data, http) = try await executeWithRetry {
            if let progress {
                let observer = UploadProgressObserver { sent, expected in
                    let total = expected > 0 ? expected : totalBytes
                    progress(UploadProgress(bytesUploaded: sent, totalBytes: total))
                }
                return try await self.session.upload(for: request, fromFile: fileURL, delegate: observer)
            } else {
                return try await self.session.upload(for: request, fromFile: fileURL)
            }
        }

        let ids: (remoteURL: String?, fileId: String?) = parseSuccess?(data, http) ?? (nil, nil)
        return UploadResult(
            remoteURL: ids.remoteURL,
            fileId: ids.fileId,
            fileSize: totalBytes,
            uploadDuration: Date().timeIntervalSince(start),
            verified: false
        )
    }

    // MARK: - Chunked (upload-session) upload

    /// Uploads a file too large for a single request via a provider
    /// "upload session": one request to create the session (which
    /// returns an `uploadUrl`), followed by sequential `PUT` requests
    /// with `Content-Range` headers streaming the file in
    /// `chunkSize`-byte windows.
    ///
    /// This is the Microsoft Graph (OneDrive/SharePoint) resumable
    /// upload protocol — `createSessionRequest` should be built by
    /// `CloudStorageUploader.buildOneDriveCreateSessionRequest(filePath:
    /// config:)`. It is REQUIRED (not optional) for OneDrive because the
    /// simple `/content` PUT endpoint rejects anything over 4 MB
    /// (`OneDriveUploader.simpleUploadMaxBytes`), and the media files
    /// this app produces routinely exceed that.
    ///
    /// - Parameters:
    ///   - fileURL: The local file to upload.
    ///   - createSessionRequest: The provider's "create upload session"
    ///     request (method/URL/headers/body already set).
    ///   - chunkSize: Bytes per `PUT`. Defaults to
    ///     `OneDriveUploader.fragmentSize` (10 MB), which is already a
    ///     multiple of the 320 KiB Microsoft Graph requires.
    ///   - progress: Optional callback invoked after each chunk
    ///     completes. Coarser than the byte-level callback on
    ///     `upload(fileURL:request:progress:parseSuccess:)` since each
    ///     chunk is sent as an in-memory `Data` blob rather than a
    ///     streamed file and does not expose sub-chunk delegate
    ///     callbacks; still real, server-acknowledged progress — never
    ///     a fabricated estimate.
    /// - Returns: An `UploadResult` built from the final chunk's real
    ///   response (Microsoft Graph documents this as the created
    ///   `DriveItem`, containing `id`/`webUrl`).
    /// - Throws: `UploadError` describing the real failure — including
    ///   `.transport` if the session-creation response has no
    ///   `uploadUrl` (a malformed session request, or the provider
    ///   changing its response shape) or if the local file cannot be
    ///   read.
    public func uploadInSessionChunks(
        fileURL: URL,
        createSessionRequest: URLRequest,
        chunkSize: Int64 = OneDriveUploader.fragmentSize,
        progress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> UploadResult {
        let start = Date()
        guard let totalBytes = Self.fileSize(at: fileURL), totalBytes > 0 else {
            throw UploadError.transport("Could not determine the size of \(fileURL.lastPathComponent).")
        }

        let (sessionData, _) = try await executeWithRetry {
            try await self.session.data(for: createSessionRequest)
        }
        guard let uploadURLString = Self.extractUploadURL(from: sessionData),
              let uploadURL = URL(string: uploadURLString) else {
            throw UploadError.transport(
                "The upload-session response did not include an 'uploadUrl' field."
            )
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw UploadError.transport("Could not open \(fileURL.lastPathComponent) for reading: \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        var offset: Int64 = 0
        var finalChunkData = Data()

        while offset < totalBytes {
            let thisChunkSize = Int(min(chunkSize, totalBytes - offset))
            let chunk: Data
            do {
                guard let read = try handle.read(upToCount: thisChunkSize), !read.isEmpty else {
                    throw UploadError.transport(
                        "Unexpected end of file while reading the upload chunk at offset \(offset)."
                    )
                }
                chunk = read
            } catch let err as UploadError {
                throw err
            } catch {
                throw UploadError.transport("Could not read the upload chunk at offset \(offset): \(error.localizedDescription)")
            }

            let rangeEnd = offset + Int64(chunk.count) - 1
            var mutableChunkRequest = URLRequest(url: uploadURL)
            mutableChunkRequest.httpMethod = "PUT"
            mutableChunkRequest.setValue("\(chunk.count)", forHTTPHeaderField: "Content-Length")
            mutableChunkRequest.setValue(
                "bytes \(offset)-\(rangeEnd)/\(totalBytes)",
                forHTTPHeaderField: "Content-Range"
            )
            // Captured below inside a `@Sendable` closure: Swift 6 strict
            // concurrency rejects capturing a mutable `var` in
            // concurrently-executing code (even though nothing mutates it
            // after this point), so it is finalised into an immutable
            // `let` first — the same "build mutable, hand off immutable"
            // shape as `chunk` above.
            let chunkRequest = mutableChunkRequest

            let (data, _) = try await executeWithRetry {
                try await self.session.upload(for: chunkRequest, from: chunk)
            }

            offset += Int64(chunk.count)
            finalChunkData = data
            progress?(UploadProgress(bytesUploaded: offset, totalBytes: totalBytes))
        }

        let ids = Self.parseGraphIdentifiers(from: finalChunkData)
        return UploadResult(
            remoteURL: ids.remoteURL,
            fileId: ids.fileId,
            fileSize: totalBytes,
            uploadDuration: Date().timeIntervalSince(start),
            verified: false
        )
    }

    // MARK: - Dropbox upload-session (chunked) upload

    /// Uploads a file too large for Dropbox's single-request
    /// `/2/files/upload` endpoint (`DropboxUploader.singleUploadMaxBytes`,
    /// 150 MB) via Dropbox's upload-session protocol: one
    /// `upload_session/start` request, sequential
    /// `upload_session/append_v2` `POST`s (one per `chunkSize`-byte
    /// window), then one `upload_session/finish` request that commits
    /// the assembled bytes to the destination path.
    ///
    /// Structurally mirrors `uploadInSessionChunks` (the OneDrive/Graph
    /// equivalent): file-size guard → create/start request →
    /// `FileHandle` chunk loop with per-chunk `executeWithRetry` →
    /// final-response parse.
    ///
    /// **Known limitation** (shared with `uploadInSessionChunks`): a
    /// chunk-level retry re-sends the *same* request — same cursor
    /// offset — because the append request is built once, before the
    /// offset advances, and reused for every retry attempt of that
    /// chunk. This is correct when the original attempt genuinely
    /// failed (nothing was applied server-side). But if the original
    /// request actually succeeded and only its *response* was lost
    /// (e.g. a dropped connection after the server processed it), the
    /// retried append arrives at an offset the server has already
    /// moved past — Dropbox then answers `409 incorrect_offset`, which
    /// this method surfaces honestly as `.httpError(409, …)` rather
    /// than silently absorbing it or fabricating success. A caller
    /// hitting that must restart the whole upload. This is the exact
    /// same offset-replay semantics already accepted for the OneDrive
    /// session path above.
    ///
    /// - Parameters:
    ///   - fileURL: The local file to upload.
    ///   - config: The Dropbox cloud storage configuration.
    ///   - chunkSize: Bytes per `append_v2` request. Defaults to
    ///     `DropboxUploader.sessionChunkSize` (8 MB).
    ///   - progress: Optional callback invoked after each chunk
    ///     completes, with real, server-acknowledged progress.
    /// - Returns: An `UploadResult` built from the finish response's
    ///   real `path_display`/`id` fields.
    /// - Throws: `UploadError` describing the real failure — including
    ///   `.transport` if the session-start response has no
    ///   `session_id`, or if the local file cannot be read.
    public func uploadInDropboxSessionChunks(
        fileURL: URL,
        config: CloudStorageConfig,
        chunkSize: Int64 = DropboxUploader.sessionChunkSize,
        progress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> UploadResult {
        let start = Date()
        guard let totalBytes = Self.fileSize(at: fileURL), totalBytes > 0 else {
            throw UploadError.transport("Could not determine the size of \(fileURL.lastPathComponent).")
        }

        guard let startRequest = CloudStorageUploader.buildDropboxSessionStartRequest(config: config) else {
            throw UploadError.transport("Could not build the Dropbox upload-session start request.")
        }

        let (startData, _) = try await executeWithRetry {
            try await self.session.data(for: startRequest)
        }
        guard let sessionId = Self.extractDropboxSessionID(from: startData) else {
            throw UploadError.transport(
                "The Dropbox upload-session response did not include a 'session_id' field."
            )
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw UploadError.transport("Could not open \(fileURL.lastPathComponent) for reading: \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        var offset: Int64 = 0

        while offset < totalBytes {
            let thisChunkSize = Int(min(chunkSize, totalBytes - offset))
            let chunk: Data
            do {
                guard let read = try handle.read(upToCount: thisChunkSize), !read.isEmpty else {
                    throw UploadError.transport(
                        "Unexpected end of file while reading the upload chunk at offset \(offset)."
                    )
                }
                chunk = read
            } catch let err as UploadError {
                throw err
            } catch {
                throw UploadError.transport("Could not read the upload chunk at offset \(offset): \(error.localizedDescription)")
            }

            // The append request is built with the cursor offset BEFORE
            // `offset` advances — the offset a Dropbox cursor carries is
            // "how many bytes the server already has", i.e. where this
            // chunk starts, not where it ends.
            guard let appendRequest = CloudStorageUploader.buildDropboxSessionAppendRequest(
                sessionId: sessionId,
                offset: offset,
                config: config
            ) else {
                throw UploadError.transport("Could not build the Dropbox upload-session append request.")
            }

            _ = try await executeWithRetry {
                try await self.session.upload(for: appendRequest, from: chunk)
            }

            offset += Int64(chunk.count)
            progress?(UploadProgress(bytesUploaded: offset, totalBytes: totalBytes))
        }

        guard let finishRequest = CloudStorageUploader.buildDropboxSessionFinishRequest(
            sessionId: sessionId,
            offset: totalBytes,
            filePath: fileURL.lastPathComponent,
            config: config
        ) else {
            throw UploadError.transport("Could not build the Dropbox upload-session finish request.")
        }

        let (finishData, _) = try await executeWithRetry {
            try await self.session.data(for: finishRequest)
        }

        let ids = Self.parseDropboxIdentifiers(from: finishData)
        return UploadResult(
            remoteURL: ids.remoteURL,
            fileId: ids.fileId,
            fileSize: totalBytes,
            uploadDuration: Date().timeIntervalSince(start),
            verified: false
        )
    }

    // MARK: - Google Drive resumable (chunked) upload

    /// Uploads a file too large for Google Drive's simple
    /// `uploadType=media` endpoint (`GoogleDriveUploader
    /// .simpleUploadMaxBytes`, 5 MB) via Drive's resumable-upload
    /// protocol: one `POST …uploadType=resumable` request to obtain a
    /// session URI (returned in the initiate response's `Location`
    /// header, per Google's resumable-upload spec), followed by
    /// sequential `PUT` requests to that URI with `Content-Range`
    /// headers.
    ///
    /// Google's protocol answers **`308 Resume Incomplete`** for every
    /// chunk that was accepted but is not yet the file's last byte —
    /// the expected, successful outcome for a non-final chunk, not a
    /// failure. Non-final chunks therefore call
    /// `executeWithRetry(additionalSuccessStatusCodes: [308])`. The
    /// FINAL chunk uses the plain default instead (no additional
    /// success codes): a `308` there means the server is still missing
    /// bytes it should have received by now, and MUST surface as a
    /// genuine `.httpError(308, …)` — accepting it would fabricate a
    /// success the server never actually reported.
    ///
    /// - Parameters:
    ///   - fileURL: The local file to upload.
    ///   - initiateRequest: The resumable-upload "initiate" request
    ///     (built by `CloudStorageUploader
    ///     .buildGoogleDriveResumableInitRequest(filePath:fileSize:
    ///     config:)`).
    ///   - chunkSize: Bytes per `PUT`. Defaults to
    ///     `GoogleDriveUploader.resumableChunkSize` (5 MB).
    ///   - progress: Optional callback invoked after each chunk
    ///     completes, with real, server-acknowledged progress.
    /// - Returns: An `UploadResult` built from the final chunk's real
    ///   response (`id` / `webViewLink` — the latter is often absent
    ///   from Drive's response and is never guessed when so).
    /// - Throws: `UploadError` describing the real failure — including
    ///   `.transport` if the initiate response has no `Location`
    ///   header, or if the local file cannot be read.
    public func uploadInGoogleDriveResumableChunks(
        fileURL: URL,
        initiateRequest: URLRequest,
        chunkSize: Int64 = GoogleDriveUploader.resumableChunkSize,
        progress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> UploadResult {
        let start = Date()
        guard let totalBytes = Self.fileSize(at: fileURL), totalBytes > 0 else {
            throw UploadError.transport("Could not determine the size of \(fileURL.lastPathComponent).")
        }

        let (_, initiateResponse) = try await executeWithRetry {
            try await self.session.data(for: initiateRequest)
        }
        guard let sessionURLString = initiateResponse.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: sessionURLString) else {
            throw UploadError.transport(
                "The Google Drive resumable-upload initiate response did not include a 'Location' header."
            )
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw UploadError.transport("Could not open \(fileURL.lastPathComponent) for reading: \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        var offset: Int64 = 0
        var finalChunkData = Data()

        while offset < totalBytes {
            let thisChunkSize = Int(min(chunkSize, totalBytes - offset))
            let chunk: Data
            do {
                guard let read = try handle.read(upToCount: thisChunkSize), !read.isEmpty else {
                    throw UploadError.transport(
                        "Unexpected end of file while reading the upload chunk at offset \(offset)."
                    )
                }
                chunk = read
            } catch let err as UploadError {
                throw err
            } catch {
                throw UploadError.transport("Could not read the upload chunk at offset \(offset): \(error.localizedDescription)")
            }

            let rangeEnd = offset + Int64(chunk.count) - 1
            let isFinalChunk = offset + Int64(chunk.count) >= totalBytes

            var mutableChunkRequest = URLRequest(url: sessionURL)
            mutableChunkRequest.httpMethod = "PUT"
            mutableChunkRequest.setValue("\(chunk.count)", forHTTPHeaderField: "Content-Length")
            mutableChunkRequest.setValue(
                "bytes \(offset)-\(rangeEnd)/\(totalBytes)",
                forHTTPHeaderField: "Content-Range"
            )
            // Finalised to `let` before capture inside the `@Sendable`
            // closure below — same "build mutable, hand off immutable"
            // shape as `uploadInSessionChunks` above.
            let chunkRequest = mutableChunkRequest

            let data: Data
            if isFinalChunk {
                (data, _) = try await executeWithRetry {
                    try await self.session.upload(for: chunkRequest, from: chunk)
                }
            } else {
                (data, _) = try await executeWithRetry(additionalSuccessStatusCodes: [308]) {
                    try await self.session.upload(for: chunkRequest, from: chunk)
                }
            }

            offset += Int64(chunk.count)
            finalChunkData = data
            progress?(UploadProgress(bytesUploaded: offset, totalBytes: totalBytes))
        }

        let ids = Self.parseGoogleDriveIdentifiers(from: finalChunkData)
        return UploadResult(
            remoteURL: ids.remoteURL,
            fileId: ids.fileId,
            fileSize: totalBytes,
            uploadDuration: Date().timeIntervalSince(start),
            verified: false
        )
    }

    // MARK: - S3 multipart upload (roadmap #7, re #459/#162)

    /// Uploads a file too large (or simply too risky) for `uploadToS3`'s
    /// single signed `PUT` via AWS's real multipart upload API:
    /// `CreateMultipartUpload` → sequential per-part signed `UploadPart`
    /// `PUT`s (each independently signed via `AWSV4Signer`, through
    /// `S3Uploader.buildUploadPartRequest`) → `CompleteMultipartUpload`
    /// with an XML body listing every part's `PartNumber`+`ETag`
    /// (`S3Uploader.buildCompleteMultipartXML`). Structurally mirrors
    /// `uploadInDropboxSessionChunks`/`uploadInGoogleDriveResumableChunks`
    /// above: file-size guard → create/initiate request → `FileHandle`
    /// chunk loop with per-chunk `executeWithRetry` → final-response
    /// parse — the AWS-specific difference is that each part's `ETag` (a
    /// real, server-issued response HEADER, not a body field) has to be
    /// collected across the whole loop to build the `Complete` request's
    /// body at the end, rather than only the loop's last response
    /// mattering.
    ///
    /// This is the multipart flow `S3Uploader.swift`'s previous
    /// `// TODO(#459)` on `buildSignedUploadRequest` referred to as "not
    /// yet wired end-to-end" — `uploadToCloudStorage`'s `.s3` branch now
    /// routes here whenever `S3Uploader.shouldUseMultipart(fileSize:)`
    /// says so (real on-disk size > 100 MB), which also covers S3's
    /// mandatory case (`uploadToS3`'s single-`PUT` 5 GiB hard limit) since
    /// 5 GiB is always > 100 MB.
    ///
    /// **Cleanup on failure**: once `CreateMultipartUpload` has genuinely
    /// succeeded (a real `UploadId` exists server-side), ANY subsequent
    /// failure — a part that exhausts its retries, an unreadable file
    /// chunk, or `CompleteMultipartUpload` itself failing — triggers a
    /// best-effort `AbortMultipartUpload` before the original error is
    /// re-thrown. The abort's own outcome is deliberately never allowed to
    /// mask the real failure: this method does not inspect the abort
    /// call's response or retry it — if the abort itself also fails
    /// (network down, expired credentials, whatever), that failure is
    /// silently discarded and the caller still sees the ORIGINAL error
    /// that triggered the abort, never a fabricated one about the
    /// cleanup step. A failed abort can still leave an incomplete upload
    /// accumulating storage charges on the bucket — AWS's own recommended
    /// mitigation for that residual risk is a bucket lifecycle rule that
    /// expires incomplete multipart uploads after N days, which is a
    /// bucket-configuration concern outside this client's control.
    ///
    /// - Parameters:
    ///   - fileURL: The local file to upload.
    ///   - credential: AWS/S3 credential (access key, secret, bucket,
    ///     region, optional custom endpoint).
    ///   - objectKey: The S3 object key (remote path).
    ///   - contentType: MIME type override. Defaults to
    ///     `UploadConfig.contentType(for:)` when omitted.
    ///   - metadata: Custom `x-amz-meta-*` metadata, attached to the
    ///     `CreateMultipartUpload` request — S3 applies object metadata at
    ///     initiate time, not per-part.
    ///   - partSize: Bytes per part. Defaults to
    ///     `S3Uploader.defaultMultipartPartSize` (8 MiB); clamped up to
    ///     `S3Uploader.minimumMultipartPartSize` (5 MiB) if given smaller,
    ///     since S3 rejects any non-final part below that (a caller could
    ///     otherwise pass e.g. `0` and get an S3-side rejection instead of
    ///     an obviously-wrong local value).
    ///   - progress: Optional callback invoked after each part completes,
    ///     with real, server-acknowledged progress (each part's ETag is a
    ///     genuine S3 response header, never guessed).
    /// - Returns: An `UploadResult` built from `CompleteMultipartUpload`'s
    ///   real response (`Location`/`ETag`).
    /// - Throws: `UploadError` describing the real failure — including
    ///   `.transport` if `CreateMultipartUpload`'s response has no
    ///   `UploadId`, a part response has no `ETag`, or the local file
    ///   cannot be read.
    public func uploadS3Multipart(
        fileURL: URL,
        credential: CloudCredential,
        objectKey: String,
        contentType: String? = nil,
        metadata: [String: String] = [:],
        partSize: Int64 = S3Uploader.defaultMultipartPartSize,
        progress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> UploadResult {
        let start = Date()
        guard let totalBytes = Self.fileSize(at: fileURL), totalBytes > 0 else {
            throw UploadError.transport("Could not determine the size of \(fileURL.lastPathComponent).")
        }

        let effectivePartSize = max(partSize, S3Uploader.minimumMultipartPartSize)
        let resolvedContentType = contentType ?? UploadConfig.contentType(for: fileURL.lastPathComponent)

        guard let initiateRequest = S3Uploader.buildInitiateMultipartRequest(
            credential: credential,
            objectKey: objectKey,
            contentType: resolvedContentType,
            metadata: metadata
        ) else {
            throw UploadError.transport(
                "Could not build the S3 CreateMultipartUpload request — check that the access key, "
                    + "secret key, bucket, and object key are all configured."
            )
        }

        let (initiateData, _) = try await executeWithRetry {
            try await self.session.data(for: initiateRequest)
        }
        guard let uploadId = S3Uploader.parseUploadId(from: initiateData) else {
            throw UploadError.transport(
                "The S3 CreateMultipartUpload response did not include an 'UploadId'."
            )
        }

        // From here on, a real UploadId exists server-side — any failure
        // below must abort it (best-effort) before re-throwing. See this
        // method's doc comment for why the abort's own outcome never masks
        // the original error.
        do {
            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: fileURL)
            } catch {
                throw UploadError.transport("Could not open \(fileURL.lastPathComponent) for reading: \(error.localizedDescription)")
            }
            defer { try? handle.close() }

            var offset: Int64 = 0
            var partNumber = 1
            var parts: [S3Uploader.MultipartPart] = []

            while offset < totalBytes {
                let thisChunkSize = Int(min(effectivePartSize, totalBytes - offset))
                let chunk: Data
                do {
                    guard let read = try handle.read(upToCount: thisChunkSize), !read.isEmpty else {
                        throw UploadError.transport(
                            "Unexpected end of file while reading part \(partNumber) at offset \(offset)."
                        )
                    }
                    chunk = read
                } catch let err as UploadError {
                    throw err
                } catch {
                    throw UploadError.transport("Could not read part \(partNumber) at offset \(offset): \(error.localizedDescription)")
                }

                guard let partRequest = S3Uploader.buildUploadPartRequest(
                    credential: credential,
                    objectKey: objectKey,
                    uploadId: uploadId,
                    partNumber: partNumber,
                    contentLength: Int64(chunk.count)
                ) else {
                    throw UploadError.transport("Could not build the S3 UploadPart request for part \(partNumber).")
                }

                let (_, partResponse) = try await executeWithRetry {
                    try await self.session.upload(for: partRequest, from: chunk)
                }
                guard let eTag = partResponse.value(forHTTPHeaderField: "ETag"), !eTag.isEmpty else {
                    throw UploadError.transport("S3 did not return an ETag header for part \(partNumber).")
                }

                parts.append(S3Uploader.MultipartPart(partNumber: partNumber, eTag: eTag))
                offset += Int64(chunk.count)
                partNumber += 1
                progress?(UploadProgress(bytesUploaded: offset, totalBytes: totalBytes))
            }

            guard let completeRequest = S3Uploader.buildCompleteMultipartRequest(
                credential: credential,
                objectKey: objectKey,
                uploadId: uploadId,
                parts: parts
            ) else {
                throw UploadError.transport("Could not build the S3 CompleteMultipartUpload request.")
            }

            let (completeData, _) = try await executeWithRetry {
                try await self.session.data(for: completeRequest)
            }

            let ids = S3Uploader.parseCompleteMultipartResult(from: completeData)
            return UploadResult(
                remoteURL: ids.remoteURL,
                fileId: ids.fileId,
                fileSize: totalBytes,
                uploadDuration: Date().timeIntervalSince(start),
                verified: false
            )
        } catch {
            if let abortRequest = S3Uploader.buildAbortMultipartRequest(
                credential: credential,
                objectKey: objectKey,
                uploadId: uploadId
            ) {
                _ = try? await self.session.data(for: abortRequest)
            }
            throw error
        }
    }

    // MARK: - Retry core

    /// Runs `attempt` up to `retryPolicy.maxAttempts` times, retrying on
    /// transient HTTP statuses (`retryPolicy.retryableStatusCodes`) or
    /// thrown transport errors, with exponential backoff between
    /// attempts.
    ///
    /// A non-retryable HTTP status (outside `retryableStatusCodes`)
    /// throws `.httpError` immediately, without waiting through the
    /// remaining backoff schedule — retrying a 401/403/404/409 can
    /// never succeed. A retryable status or a thrown transport error
    /// that survives every attempt instead falls through to
    /// `.allRetriesFailed(lastError:)` once the loop is exhausted,
    /// mirroring `WebhookSender.send(payload:config:)`'s retry shape.
    ///
    /// - Parameter additionalSuccessStatusCodes: Extra status codes
    ///   treated as success alongside the `2xx` range, without being
    ///   retried. Required for Google Drive's resumable-upload
    ///   protocol, which answers **`308 Resume Incomplete`** for every
    ///   chunk that was accepted but is not yet the file's final byte —
    ///   a real, documented success for a non-final chunk, not a
    ///   transient failure worth retrying. Defaults to empty, so every
    ///   existing call site (whole-file upload, OneDrive/Dropbox session
    ///   chunks) is unaffected and still requires a genuine `2xx`.
    private func executeWithRetry(
        additionalSuccessStatusCodes: Set<Int> = [],
        _ attempt: @Sendable () async throws -> (Data, URLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
        var lastErrorMessage = "Unknown error"

        for attemptNumber in 1...retryPolicy.maxAttempts {
            do {
                let (data, response) = try await attempt()
                guard let http = response as? HTTPURLResponse else {
                    throw UploadError.invalidResponse
                }
                if (200..<300).contains(http.statusCode) || additionalSuccessStatusCodes.contains(http.statusCode) {
                    return (data, http)
                }

                let httpErr = UploadError.httpError(
                    statusCode: http.statusCode,
                    bodySnippet: Self.snippet(from: data)
                )
                guard retryPolicy.retryableStatusCodes.contains(http.statusCode) else {
                    throw httpErr
                }
                lastErrorMessage = httpErr.errorDescription ?? "HTTP \(http.statusCode)"
            } catch let err as UploadError {
                throw err
            } catch {
                lastErrorMessage = error.localizedDescription
            }

            if attemptNumber < retryPolicy.maxAttempts {
                try await Task.sleep(for: .seconds(Self.backoffDelay(attempt: attemptNumber, policy: retryPolicy)))
            }
        }

        throw UploadError.allRetriesFailed(lastError: lastErrorMessage)
    }

    // MARK: - Helpers

    private static func backoffDelay(attempt: Int, policy: RetryPolicy) -> Double {
        let raw = policy.initialDelay * pow(2.0, Double(attempt - 1))
        return min(raw, policy.maxDelay)
    }

    private static func snippet(from data: Data, limit: Int = 500) -> String {
        guard !data.isEmpty else { return "<empty body>" }
        guard let text = String(data: data, encoding: .utf8) else {
            return "<\(data.count) bytes, non-UTF8 body>"
        }
        if text.count > limit {
            return String(text.prefix(limit)) + "…"
        }
        return text
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attrs[.size] as? Int64
    }

    private static func extractUploadURL(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["uploadUrl"] as? String
    }

    private static func parseGraphIdentifiers(from data: Data) -> (remoteURL: String?, fileId: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        return (json["webUrl"] as? String, json["id"] as? String)
    }

    private static func extractDropboxSessionID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["session_id"] as? String
    }

    private static func parseDropboxIdentifiers(from data: Data) -> (remoteURL: String?, fileId: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        return (json["path_display"] as? String, json["id"] as? String)
    }

    private static func parseGoogleDriveIdentifiers(from data: Data) -> (remoteURL: String?, fileId: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        return (json["webViewLink"] as? String, json["id"] as? String)
    }
}

// MARK: - CloudUploadExecutor + provider routing

extension CloudUploadExecutor {

    /// Uploads `fileURL` to the destination described by `config`,
    /// automatically choosing the right provider request-builder and —
    /// for Dropbox, Google Drive, OneDrive, and S3 — the small-file
    /// single-request path vs. the chunked/multipart path based on the
    /// real on-disk file size:
    /// - Dropbox: chunked above `DropboxUploader.singleUploadMaxBytes`
    ///   (150 MB) — the `/2/files/upload` endpoint's real hard limit.
    /// - Google Drive: chunked above `GoogleDriveUploader
    ///   .simpleUploadMaxBytes` (5 MB) — `uploadType=media` is
    ///   documented for small files only.
    /// - OneDrive: chunked above `OneDriveUploader.simpleUploadMaxBytes`
    ///   (4 MB) — unchanged from before roadmap item #2.
    /// - S3: multipart (`uploadS3Multipart`) above
    ///   `S3Uploader.shouldUseMultipart(fileSize:)`'s 100 MB threshold —
    ///   S3's single-`PUT` endpoint (`uploadToS3`) has a hard 5 GiB limit,
    ///   so anything that could plausibly approach it needs to already be
    ///   on the multipart path well before then (roadmap #7, re #459).
    ///
    /// Shared by `CloudStorageView.performUpload()` (Issue #459) and
    /// `PostEncodeActionChain.uploadViaCloud(action:outputURL:)` (Issue
    /// #450) so the "which request builder, which chunked path" logic
    /// lives in exactly one place rather than being duplicated between
    /// the SwiftUI settings view and the post-encode action chain.
    ///
    /// - Parameters:
    ///   - fileURL: The local file to upload.
    ///   - config: The destination provider, credentials, and remote
    ///     path (built by `CloudStorageView` or loaded from
    ///     `CloudStorageProfileStore`).
    ///   - progress: Optional progress callback — see
    ///     `upload(fileURL:request:progress:parseSuccess:)` for its
    ///     threading contract.
    /// - Returns: The real `UploadResult`.
    /// - Throws: `UploadError` if the request could not be built (for
    ///   `.s3`, this includes a missing access key ID, secret access key,
    ///   or bucket) or the real transfer failed.
    public func uploadToCloudStorage(
        fileURL: URL,
        config: CloudStorageConfig,
        progress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> UploadResult {
        let fileName = fileURL.lastPathComponent

        switch config.provider {
        case .dropbox:
            let fileSize = Self.fileSize(at: fileURL)

            if let fileSize, fileSize > DropboxUploader.singleUploadMaxBytes {
                return try await uploadInDropboxSessionChunks(
                    fileURL: fileURL,
                    config: config,
                    progress: progress
                )
            }

            guard let request = CloudStorageUploader.buildDropboxUploadRequest(
                filePath: fileName,
                config: config
            ) else {
                throw UploadError.transport("Could not build the Dropbox upload request.")
            }
            return try await upload(fileURL: fileURL, request: request, progress: progress)

        case .googleDrive:
            let fileSize = Self.fileSize(at: fileURL)

            if let fileSize, fileSize > GoogleDriveUploader.simpleUploadMaxBytes {
                guard let initiateRequest = CloudStorageUploader.buildGoogleDriveResumableInitRequest(
                    filePath: fileName,
                    fileSize: fileSize,
                    config: config
                ) else {
                    throw UploadError.transport("Could not build the Google Drive resumable-upload initiate request.")
                }
                return try await uploadInGoogleDriveResumableChunks(
                    fileURL: fileURL,
                    initiateRequest: initiateRequest,
                    progress: progress
                )
            }

            guard let request = CloudStorageUploader.buildGoogleDriveUploadRequest(
                filePath: fileName,
                config: config
            ) else {
                throw UploadError.transport("Could not build the Google Drive upload request.")
            }
            return try await upload(fileURL: fileURL, request: request, progress: progress)

        case .onedrive:
            let fileSize = Self.fileSize(at: fileURL)

            if let fileSize, fileSize > OneDriveUploader.simpleUploadMaxBytes {
                guard let sessionRequest = CloudStorageUploader.buildOneDriveCreateSessionRequest(
                    filePath: fileName,
                    config: config
                ) else {
                    throw UploadError.transport("Could not build the OneDrive upload-session request.")
                }
                return try await uploadInSessionChunks(
                    fileURL: fileURL,
                    createSessionRequest: sessionRequest,
                    progress: progress
                )
            }

            guard let request = CloudStorageUploader.buildOneDriveUploadRequest(
                filePath: fileName,
                config: config
            ) else {
                throw UploadError.transport("Could not build the OneDrive upload request.")
            }
            return try await upload(fileURL: fileURL, request: request, progress: progress)

        case .s3:
            guard !config.accessToken.isEmpty,
                  let secretAccessKey = config.secretAccessKey, !secretAccessKey.isEmpty,
                  let bucket = config.bucket, !bucket.isEmpty else {
                throw UploadError.transport(
                    "S3 upload requires an access key ID, secret access key, and bucket — "
                        + "configure these in Cloud Storage settings."
                )
            }

            let credential = CloudCredential(
                provider: .awsS3,
                apiKey: config.accessToken,
                secret: secretAccessKey,
                endpoint: config.endpoint,
                region: config.region,
                bucket: bucket
            )
            let objectKey = Self.s3ObjectKey(remotePath: config.remotePath, fileName: fileName)
            let fileSize = Self.fileSize(at: fileURL)

            if let fileSize, S3Uploader.shouldUseMultipart(fileSize: fileSize) {
                return try await uploadS3Multipart(
                    fileURL: fileURL,
                    credential: credential,
                    objectKey: objectKey,
                    progress: progress
                )
            }

            return try await uploadToS3(
                fileURL: fileURL,
                credential: credential,
                objectKey: objectKey,
                progress: progress
            )
        }
    }

    /// Joins an S3 key prefix (`CloudStorageConfig.remotePath`) with a file
    /// name into an S3 object key, stripping any leading/trailing `/` from
    /// the prefix first — S3 object keys conventionally have no leading
    /// slash (unlike the folder paths `buildDropboxUploadRequest` etc.
    /// join the same way), and `S3Uploader.buildSignedUploadRequest` adds
    /// the one leading slash the request's URL path needs on its own.
    ///
    /// - Parameters:
    ///   - remotePath: The configured prefix, e.g. `"videos"`, `"/videos/"`,
    ///     or `""` (root).
    ///   - fileName: The local file's last path component.
    /// - Returns: The object key, e.g. `"videos/movie.mp4"` (or just
    ///   `"movie.mp4"` for an empty/root prefix).
    private static func s3ObjectKey(remotePath: String, fileName: String) -> String {
        let trimmedPrefix = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmedPrefix.isEmpty ? fileName : "\(trimmedPrefix)/\(fileName)"
    }
}

// MARK: - UploadProgressObserver

/// Bridges `URLSessionTaskDelegate`'s `didSendBodyData` callback (fired
/// on whatever queue `URLSession` uses internally, not necessarily the
/// caller's) into a plain `@Sendable` closure.
///
/// `@unchecked Sendable`: the only Swift-visible stored property is an
/// immutable (`let`) `@Sendable` closure captured at `init`. `NSObject`'s
/// own internal state is opaque to Swift's Sendable checker but is never
/// touched by this subclass, so there is nothing here for a data race to
/// reach.
private final class UploadProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(totalBytesSent, totalBytesExpectedToSend)
    }
}
