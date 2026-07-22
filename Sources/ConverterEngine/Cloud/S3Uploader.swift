// ============================================================================
// MeedyaConverter — S3Uploader
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
// NOTE: AWS Signature V4 signing (the reason this file used to import
// CommonCrypto directly) now lives in `AWSV4Signer.swift`, which does
// the actual CommonCrypto-based hashing/HMAC work — see
// `buildSignedUploadRequest` below, which calls into it. No direct
// CommonCrypto usage remains in this file.

// MARK: - S3Uploader

/// Builds AWS S3 (and S3-compatible) upload requests.
///
/// `buildSignedUploadRequest` produces a genuinely AWS Signature
/// Version 4-signed `PUT` request (via `AWSV4Signer`, Issue #459 Bundle
/// 1b) ready to hand to `CloudUploadExecutor` — or use the
/// `CloudUploadExecutor.uploadToS3(fileURL:credential:objectKey:...)`
/// convenience below to build-and-execute in one call. Also works with
/// S3-compatible providers like Backblaze B2, DigitalOcean Spaces,
/// MinIO, and Cloudflare R2 that support virtual-hosted-style
/// requests, via `CloudCredential.endpoint`.
///
/// Multipart upload (required by S3 for objects over 5 GiB) is not yet
/// wired end-to-end — `buildInitiateMultipartURL`/`buildUploadPartURL`/
/// `calculatePartCount`/`shouldUseMultipart` below exist for that but
/// nothing drives them through a full initiate → parts → complete flow
/// yet. See `// TODO(#459)` on `buildSignedUploadRequest`.
///
/// Phase 12.2
public struct S3Uploader: Sendable {

    /// Build the S3 endpoint URL for a given credential and object key.
    ///
    /// - Parameters:
    ///   - credential: AWS/S3 credential.
    ///   - objectKey: The S3 object key (remote path).
    /// - Returns: The full endpoint URL string.
    public static func buildEndpointURL(
        credential: CloudCredential,
        objectKey: String
    ) -> String {
        let endpoint = credential.endpoint ?? "https://s3.\(credential.region ?? "us-east-1").amazonaws.com"
        let bucket = credential.bucket ?? ""
        return "\(endpoint)/\(bucket)/\(objectKey)"
    }

    /// Build HTTP headers for an S3 PUT request — content headers only,
    /// deliberately WITHOUT authentication.
    ///
    /// This does not include `Authorization`, `x-amz-date`, or
    /// `x-amz-content-sha256` — a real upload needs AWS Signature V4
    /// signing, which `buildSignedUploadRequest` (below) now provides.
    /// This function is kept for callers that only need the
    /// content-description headers (e.g. to preview what will be sent,
    /// or for a pre-signed-URL flow where signing happens out of band)
    /// and for backward compatibility with existing callers/tests.
    ///
    /// - Parameters:
    ///   - contentType: MIME type of the file.
    ///   - contentLength: File size in bytes.
    ///   - metadata: Custom metadata key-value pairs.
    /// - Returns: Dictionary of HTTP headers.
    public static func buildUploadHeaders(
        contentType: String,
        contentLength: Int64,
        metadata: [String: String] = [:]
    ) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": contentType,
            "Content-Length": "\(contentLength)",
        ]

        // Custom metadata as x-amz-meta-* headers
        for (key, value) in metadata {
            headers["x-amz-meta-\(key)"] = value
        }

        return headers
    }

    /// Build the initiate multipart upload URL.
    ///
    /// - Parameters:
    ///   - credential: AWS/S3 credential.
    ///   - objectKey: The S3 object key.
    /// - Returns: URL string for initiating multipart upload.
    public static func buildInitiateMultipartURL(
        credential: CloudCredential,
        objectKey: String
    ) -> String {
        return "\(buildEndpointURL(credential: credential, objectKey: objectKey))?uploads"
    }

    /// Build the upload part URL for a multipart upload.
    ///
    /// - Parameters:
    ///   - credential: AWS/S3 credential.
    ///   - objectKey: The S3 object key.
    ///   - uploadId: The multipart upload ID.
    ///   - partNumber: The part number (1-based).
    /// - Returns: URL string for uploading a part.
    public static func buildUploadPartURL(
        credential: CloudCredential,
        objectKey: String,
        uploadId: String,
        partNumber: Int
    ) -> String {
        let base = buildEndpointURL(credential: credential, objectKey: objectKey)
        return "\(base)?partNumber=\(partNumber)&uploadId=\(uploadId)"
    }

    /// Calculate the number of parts needed for a multipart upload.
    ///
    /// - Parameters:
    ///   - fileSize: Total file size in bytes.
    ///   - partSize: Size of each part in bytes.
    /// - Returns: Number of parts.
    public static func calculatePartCount(fileSize: Int64, partSize: Int) -> Int {
        guard partSize > 0 else { return 1 }
        return Int((fileSize + Int64(partSize) - 1) / Int64(partSize))
    }

    /// Determine if multipart upload should be used.
    ///
    /// S3 recommends multipart for files > 100 MB and requires it for > 5 GB.
    ///
    /// - Parameter fileSize: File size in bytes.
    /// - Returns: `true` if multipart upload should be used.
    public static func shouldUseMultipart(fileSize: Int64) -> Bool {
        return fileSize > 100 * 1024 * 1024 // 100 MB
    }

    /// Validate an S3 credential for upload readiness.
    ///
    /// - Parameter credential: The credential to validate.
    /// - Returns: Array of error messages. Empty means valid.
    public static func validate(credential: CloudCredential) -> [String] {
        var errors: [String] = []

        if credential.apiKey == nil || credential.apiKey?.isEmpty == true {
            errors.append("AWS Access Key ID is required")
        }
        if credential.secret == nil || credential.secret?.isEmpty == true {
            errors.append("AWS Secret Access Key is required")
        }
        if credential.bucket == nil || credential.bucket?.isEmpty == true {
            errors.append("S3 bucket name is required")
        }

        return errors
    }
}

// MARK: - S3Uploader + AWS Signature V4

extension S3Uploader {

    /// Builds the virtual-hosted-style S3 host for a bucket:
    /// `<bucket>.s3.<region>.amazonaws.com`, or `<bucket>.<endpointHost>`
    /// when `credential.endpoint` points at an S3-compatible provider
    /// (Backblaze B2, DigitalOcean Spaces, MinIO, Cloudflare R2, ...).
    private static func signingHost(credential: CloudCredential, bucket: String) -> String {
        if let endpoint = credential.endpoint,
           let endpointURL = URL(string: endpoint),
           let endpointHost = endpointURL.host {
            return "\(bucket).\(endpointHost)"
        }
        let region = credential.region ?? "us-east-1"
        return "\(bucket).s3.\(region).amazonaws.com"
    }

    /// Build a fully AWS Signature Version 4-signed `PUT` request to
    /// upload an object to S3 (or an S3-compatible endpoint) at
    /// `https://<bucket>.s3.<region>.amazonaws.com/<objectKey>`.
    ///
    /// Single-`PUT` only — this matches S3's own 5 GiB single-request
    /// limit.
    /// // TODO(#459): multipart upload for files > 5 GiB — initiate →
    /// per-part signed PUTs → complete, using
    /// `calculatePartCount`/`shouldUseMultipart` (above) to decide
    /// when to switch over. `buildInitiateMultipartURL`/
    /// `buildUploadPartURL` (above) already build the right URLs; they
    /// just are not yet driven through a full signed multipart flow.
    ///
    /// Uses `AWSV4Signer.unsignedPayload` (`"UNSIGNED-PAYLOAD"`) for
    /// `x-amz-content-sha256` rather than hashing the file up front:
    /// AWS explicitly documents this token for exactly this case — a
    /// streamed body whose bytes should not have to be read twice.
    /// `CloudUploadExecutor.upload` streams the file straight from
    /// disk via `URLSession.upload(for:fromFile:)`; hashing first
    /// would mean reading every multi-gigabyte output file twice
    /// (once to hash, once to stream) for no security benefit S3
    /// itself asks for on this path.
    ///
    /// Only `Host`, `x-amz-date`, and `x-amz-content-sha256` are
    /// included in `SignedHeaders` — not `Content-Type`/
    /// `Content-Length`/`x-amz-meta-*`. Those headers are still sent,
    /// just not signed: `Content-Length` in particular is the one
    /// `URLSession` recomputes itself from the file's real on-disk
    /// size when streaming via `upload(for:fromFile:)` rather than
    /// necessarily honouring whatever numeric value this function
    /// wrote into the request ahead of time, so signing it would risk
    /// a spurious `SignatureDoesNotMatch` if the two ever disagreed by
    /// even one byte. The three headers that ARE signed are exactly
    /// the three this function fully controls end-to-end.
    ///
    /// The exact same path string is used both to build the request's
    /// `URL` and (inside `AWSV4Signer.sign`) to compute the signature —
    /// both derive it via `AWSV4Signer.canonicalURI(path:)`, so the
    /// bytes actually sent on the wire and the bytes that were signed
    /// can never diverge (a manual "percent-encode for the URL, then
    /// separately percent-encode again for signing" implementation
    /// would risk exactly that kind of double-encoding mismatch).
    ///
    /// - Parameters:
    ///   - credential: AWS/S3 credential — `apiKey` is the access key
    ///     ID, `secret` is the secret access key. See
    ///     `loadCredential(apiKeyManager:bucket:region:endpoint:)` for
    ///     the Keychain-backed path that supplies these in production;
    ///     this function itself never reads a key from anywhere — it
    ///     only signs with whatever `credential` already carries, and
    ///     never logs either field.
    ///   - objectKey: The S3 object key (remote path), e.g.
    ///     `"videos/movie.mp4"`. Not pre-percent-encoded.
    ///   - contentType: MIME type of the file being uploaded.
    ///   - contentLength: File size in bytes, sent as `Content-Length`
    ///     (see the "not signed" note above).
    ///   - metadata: Custom metadata, sent as `x-amz-meta-*` headers
    ///     (also not signed — see above).
    ///   - date: Request timestamp. Defaults to `Date()` — this is the
    ///     one call site allowed to do that; the underlying
    ///     `AWSV4Signer.sign(...)` core never defaults it internally,
    ///     which is what keeps `AWSV4SignerTests` deterministic.
    /// - Returns: A fully signed `URLRequest`, ready for
    ///   `CloudUploadExecutor.upload(fileURL:request:)` (or use
    ///   `CloudUploadExecutor.uploadToS3` below to skip this call
    ///   entirely). `nil` if the credential is missing the access key,
    ///   secret key, or bucket, `objectKey` is empty, or a valid `URL`
    ///   could not be constructed.
    public static func buildSignedUploadRequest(
        credential: CloudCredential,
        objectKey: String,
        contentType: String,
        contentLength: Int64,
        metadata: [String: String] = [:],
        date: Date = Date()
    ) -> URLRequest? {
        guard let accessKeyID = credential.apiKey, !accessKeyID.isEmpty,
              let secretAccessKey = credential.secret, !secretAccessKey.isEmpty,
              let bucket = credential.bucket, !bucket.isEmpty,
              !objectKey.isEmpty else {
            return nil
        }

        let host = signingHost(credential: credential, bucket: bucket)
        let rawPath = objectKey.hasPrefix("/") ? objectKey : "/\(objectKey)"
        // The single source of truth for path percent-encoding: used
        // here to build the actual `URL`, and again (recomputed
        // identically, since it is a pure function of `rawPath`)
        // inside `AWSV4Signer.sign` below to compute the signature.
        let encodedPath = AWSV4Signer.canonicalURI(path: rawPath)
        guard let url = URL(string: "https://\(host)\(encodedPath)") else { return nil }

        let region = credential.region ?? "us-east-1"
        let amzDate = AWSV4Signer.amzDate(from: date)
        let payloadHash = AWSV4Signer.unsignedPayload

        let signedHeaderSet: [String: String] = [
            "host": host,
            "x-amz-date": amzDate,
            "x-amz-content-sha256": payloadHash,
        ]

        let result = AWSV4Signer.sign(
            method: "PUT",
            path: rawPath,
            headers: signedHeaderSet,
            payloadHash: payloadHash,
            date: date,
            region: region,
            service: "s3",
            credentials: AWSV4Signer.Credentials(accessKeyID: accessKeyID, secretAccessKey: secretAccessKey)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        // `URLSession` derives the `Host` it actually sends from the
        // request's `URL` (it is one of the headers Foundation
        // restricts callers from overriding), which already equals
        // `host` by construction above — this explicit `setValue` is
        // belt-and-braces documentation of intent, not load-bearing.
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(result.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(contentLength)", forHTTPHeaderField: "Content-Length")
        for (key, value) in metadata {
            request.setValue(value, forHTTPHeaderField: "x-amz-meta-\(key)")
        }

        return request
    }

    /// Loads AWS S3 access key ID + secret access key from the system
    /// Keychain via `APIKeyManager` (provider `.awsS3`) and combines
    /// them with the given bucket/region/endpoint into a
    /// `CloudCredential` ready for `buildSignedUploadRequest`.
    ///
    /// Mirrors `CloudStorageProfileStore.loadProfiles(apiKeyManager:)`,
    /// which does the equivalent job for the OAuth-token providers: the
    /// access key ID and secret access key NEVER live in
    /// `PostEncodeAction.config`, a plain settings file, argv, or a log
    /// line — only in the system Keychain, reached exclusively through
    /// `APIKeyManager` → `KeychainStore` (`SecItem*`; see
    /// `APIKeyManager.swift`).
    ///
    /// - Parameters:
    ///   - apiKeyManager: The manager to read the stored key from.
    ///     Defaults to a fresh `APIKeyManager()` against the standard
    ///     on-disk metadata location (only non-sensitive metadata lives
    ///     there — the secrets themselves are Keychain-only; see
    ///     `APIKeyManager`'s doc comment).
    ///   - bucket: The target S3 bucket name.
    ///   - region: AWS region. Defaults to `"us-east-1"` if omitted.
    ///   - endpoint: Optional S3-compatible custom endpoint (Backblaze
    ///     B2, DigitalOcean Spaces, MinIO, Cloudflare R2, ...).
    /// - Returns: A populated `CloudCredential`, or `nil` if no AWS S3
    ///   key is currently stored in the Keychain.
    public static func loadCredential(
        apiKeyManager: APIKeyManager = APIKeyManager(),
        bucket: String,
        region: String? = nil,
        endpoint: String? = nil
    ) -> CloudCredential? {
        guard let stored = apiKeyManager.key(for: .awsS3),
              !stored.apiKey.isEmpty,
              let secretKey = stored.secretKey, !secretKey.isEmpty else {
            return nil
        }
        return CloudCredential(
            provider: .awsS3,
            apiKey: stored.apiKey,
            secret: secretKey,
            endpoint: endpoint,
            region: region,
            bucket: bucket
        )
    }
}

// MARK: - CloudUploadExecutor + S3

extension CloudUploadExecutor {

    /// Uploads `fileURL` to S3 (or an S3-compatible endpoint) via a
    /// single AWS Signature V4-signed `PUT`, executed for real through
    /// `upload(fileURL:request:progress:)` — the same 2xx-only success
    /// contract, retry/backoff, and byte-level progress every other
    /// provider this type drives already gets (Issue #459 Bundle 1b —
    /// S3 was the one provider still building a request nobody ever
    /// sent; see `S3Uploader`'s previous doc comment, replaced by this
    /// change, which said exactly that).
    ///
    /// - Parameters:
    ///   - fileURL: The local file to upload.
    ///   - credential: AWS/S3 credential (access key, secret, bucket,
    ///     region, optional custom endpoint). See
    ///     `S3Uploader.loadCredential` for the Keychain-backed path
    ///     that supplies this without ever touching argv or a log.
    ///   - objectKey: The S3 object key (remote path).
    ///   - contentType: MIME type override. Defaults to
    ///     `UploadConfig.contentType(for:)`, based on the file's
    ///     extension, when omitted.
    ///   - metadata: Custom `x-amz-meta-*` metadata.
    ///   - progress: Optional byte-level progress callback — see
    ///     `upload(fileURL:request:progress:parseSuccess:)`'s doc
    ///     comment for its threading contract.
    /// - Returns: The real `UploadResult`.
    /// - Throws: `UploadError.transport` if the local file's size
    ///   could not be read or the signed request could not be built
    ///   (missing credential fields), or the real `UploadError` from
    ///   the executed transfer otherwise.
    public func uploadToS3(
        fileURL: URL,
        credential: CloudCredential,
        objectKey: String,
        contentType: String? = nil,
        metadata: [String: String] = [:],
        progress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> UploadResult {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int64 else {
            throw UploadError.transport("Could not determine the size of \(fileURL.lastPathComponent).")
        }

        let resolvedContentType = contentType ?? UploadConfig.contentType(for: fileURL.lastPathComponent)

        guard let request = S3Uploader.buildSignedUploadRequest(
            credential: credential,
            objectKey: objectKey,
            contentType: resolvedContentType,
            contentLength: fileSize,
            metadata: metadata
        ) else {
            throw UploadError.transport(
                "Could not build a signed S3 upload request — check that the access key, "
                    + "secret key, bucket, and object key are all configured."
            )
        }

        return try await upload(fileURL: fileURL, request: request, progress: progress)
    }
}

// NOTE: SFTPUploader has been moved to SFTPUploader.swift (Issue #312)
// with expanded SFTP/FTP/rsync support and dedicated config types.
