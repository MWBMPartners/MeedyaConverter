// ============================================================================
// MeedyaConverter — CloudUploadExecutor (Issue #459)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CloudUploadExecutor

/// Executes cloud-storage upload `URLRequest`s built by
/// `CloudStorageUploader` (Dropbox / Google Drive / OneDrive) and reports
/// the real, verified outcome.
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
///   for whole-file transfers, or sequential `PUT` requests with
///   `Content-Range` headers for provider "upload session" large-file
///   transfers (`uploadInSessionChunks`).
/// - Only a genuine `2xx` HTTP status is treated as success.
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

        let ids = parseSuccess?(data, http) ?? (nil, nil)
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
            var chunkRequest = URLRequest(url: uploadURL)
            chunkRequest.httpMethod = "PUT"
            chunkRequest.setValue("\(chunk.count)", forHTTPHeaderField: "Content-Length")
            chunkRequest.setValue(
                "bytes \(offset)-\(rangeEnd)/\(totalBytes)",
                forHTTPHeaderField: "Content-Range"
            )

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
    private func executeWithRetry(
        _ attempt: @Sendable () async throws -> (Data, URLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
        var lastErrorMessage = "Unknown error"

        for attemptNumber in 1...retryPolicy.maxAttempts {
            do {
                let (data, response) = try await attempt()
                guard let http = response as? HTTPURLResponse else {
                    throw UploadError.invalidResponse
                }
                if (200..<300).contains(http.statusCode) {
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
}

// MARK: - CloudUploadExecutor + provider routing

extension CloudUploadExecutor {

    /// Uploads `fileURL` to the destination described by `config`,
    /// automatically choosing the right provider request-builder and —
    /// for OneDrive — the small-file `/content` PUT vs. the chunked
    /// upload-session path based on the real on-disk file size.
    ///
    /// Shared by `CloudStorageView.performUpload()` (Issue #459) and
    /// `PostEncodeActionChain.uploadViaCloud(action:outputURL:)` (Issue
    /// #450) so the "which request builder, which OneDrive path" logic
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
    /// - Throws: `UploadError` if the request could not be built or the
    ///   real transfer failed.
    public func uploadToCloudStorage(
        fileURL: URL,
        config: CloudStorageConfig,
        progress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> UploadResult {
        let fileName = fileURL.lastPathComponent

        switch config.provider {
        case .dropbox:
            guard let request = CloudStorageUploader.buildDropboxUploadRequest(
                filePath: fileName,
                config: config
            ) else {
                throw UploadError.transport("Could not build the Dropbox upload request.")
            }
            return try await upload(fileURL: fileURL, request: request, progress: progress)

        case .googleDrive:
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
        }
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
