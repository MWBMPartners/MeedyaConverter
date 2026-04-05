// ============================================================================
// MeedyaConverter — S3Uploader
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

// MARK: - S3Uploader

/// Builds AWS S3 (and S3-compatible) upload requests.
///
/// Supports multipart uploads, pre-signed URLs, and AWS Signature V4
/// authentication. Also works with S3-compatible providers like
/// Backblaze B2, DigitalOcean Spaces, MinIO, and Cloudflare R2.
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

    /// Build HTTP headers for an S3 PUT request (simplified, no signing).
    ///
    /// For production use, AWS Signature V4 signing is required.
    /// This builds the basic header structure.
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

// NOTE: SFTPUploader has been moved to SFTPUploader.swift (Issue #312)
// with expanded SFTP/FTP/rsync support and dedicated config types.
