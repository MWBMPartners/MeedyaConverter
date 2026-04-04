// ============================================================================
// MeedyaConverter — ExtendedCloudProviders
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CloudFrontDistribution

/// Builds AWS CloudFront invalidation and signed URL components.
///
/// Phase 12.3
public struct CloudFrontDistribution: Sendable {

    /// CloudFront API base URL.
    public static let apiBaseURL = "https://cloudfront.amazonaws.com/2020-05-31"

    /// Build a CloudFront invalidation request path.
    ///
    /// - Parameters:
    ///   - distributionId: CloudFront distribution ID.
    /// - Returns: Invalidation API URL.
    public static func buildInvalidationURL(distributionId: String) -> String {
        return "\(apiBaseURL)/distribution/\(distributionId)/invalidation"
    }

    /// Build invalidation request XML body.
    ///
    /// - Parameters:
    ///   - paths: Array of paths to invalidate (e.g., ["/videos/*"]).
    ///   - callerReference: Unique reference for this invalidation.
    /// - Returns: XML body string.
    public static func buildInvalidationBody(
        paths: [String],
        callerReference: String
    ) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<InvalidationBatch xmlns=\"http://cloudfront.amazonaws.com/doc/2020-05-31/\">\n"
        xml += "  <Paths>\n"
        xml += "    <Quantity>\(paths.count)</Quantity>\n"
        xml += "    <Items>\n"
        for path in paths {
            xml += "      <Path>\(path)</Path>\n"
        }
        xml += "    </Items>\n"
        xml += "  </Paths>\n"
        xml += "  <CallerReference>\(callerReference)</CallerReference>\n"
        xml += "</InvalidationBatch>"
        return xml
    }

    /// Build a CloudFront origin URL from S3 bucket.
    ///
    /// - Parameters:
    ///   - distributionDomain: CloudFront distribution domain name.
    ///   - objectKey: S3 object key.
    /// - Returns: Full CloudFront URL.
    public static func buildDistributionURL(
        distributionDomain: String,
        objectKey: String
    ) -> String {
        return "https://\(distributionDomain)/\(objectKey)"
    }
}

// MARK: - SharePointUploader

/// Builds SharePoint / OneDrive for Business upload requests via Microsoft Graph API.
///
/// Phase 12.9
public struct SharePointUploader: Sendable {

    /// Microsoft Graph API base URL.
    public static let graphBaseURL = "https://graph.microsoft.com/v1.0"

    /// Build upload URL for a SharePoint document library.
    ///
    /// - Parameters:
    ///   - siteId: SharePoint site ID.
    ///   - driveId: Document library drive ID.
    ///   - itemPath: Path within the library (e.g., "/Videos/movie.mp4").
    /// - Returns: Upload URL.
    public static func buildUploadURL(
        siteId: String,
        driveId: String,
        itemPath: String
    ) -> String {
        return "\(graphBaseURL)/sites/\(siteId)/drives/\(driveId)/root:\(itemPath):/content"
    }

    /// Build upload session URL for large files (> 4 MB).
    ///
    /// - Parameters:
    ///   - siteId: SharePoint site ID.
    ///   - driveId: Document library drive ID.
    ///   - itemPath: Path within the library.
    /// - Returns: Create upload session URL.
    public static func buildCreateSessionURL(
        siteId: String,
        driveId: String,
        itemPath: String
    ) -> String {
        return "\(graphBaseURL)/sites/\(siteId)/drives/\(driveId)/root:\(itemPath):/createUploadSession"
    }

    /// Build list drives URL for a SharePoint site.
    ///
    /// - Parameter siteId: SharePoint site ID.
    /// - Returns: URL to list drives.
    public static func buildListDrivesURL(siteId: String) -> String {
        return "\(graphBaseURL)/sites/\(siteId)/drives"
    }

    /// Build HTTP headers for SharePoint upload.
    ///
    /// - Parameters:
    ///   - accessToken: OAuth 2.0 access token.
    ///   - contentType: MIME type.
    /// - Returns: Header dictionary.
    public static func buildUploadHeaders(
        accessToken: String,
        contentType: String
    ) -> [String: String] {
        return [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": contentType,
        ]
    }

    /// Maximum file size for simple upload (4 MB).
    public static let simpleUploadMaxBytes: Int64 = 4 * 1024 * 1024

    /// Upload fragment size for resumable upload (10 MB, must be multiple of 320 KB).
    public static let fragmentSize: Int64 = 10 * 1024 * 1024
}

// MARK: - ICloudDriveUploader

/// Builds iCloud Drive file coordination arguments for macOS.
///
/// iCloud Drive uses NSFileCoordinator / CloudKit on macOS.
/// This struct provides path helpers and validation.
///
/// Phase 12.10
public struct ICloudDriveUploader: Sendable {

    /// Build the iCloud Drive container path for the app.
    ///
    /// - Parameter containerId: iCloud container identifier (e.g., "iCloud.com.mwbm.MeedyaConverter").
    /// - Returns: Expected container path on macOS.
    public static func buildContainerPath(containerId: String) -> String {
        let home = NSHomeDirectory()
        return "\(home)/Library/Mobile Documents/\(containerId)/Documents"
    }

    /// Build the ubiquity container URL path component.
    ///
    /// - Parameters:
    ///   - containerId: iCloud container identifier.
    ///   - relativePath: Path within the container.
    /// - Returns: Full path string.
    public static func buildDocumentPath(
        containerId: String,
        relativePath: String
    ) -> String {
        return "\(buildContainerPath(containerId: containerId))/\(relativePath)"
    }

    /// Default iCloud container identifier for MeedyaConverter.
    public static let defaultContainerId = "iCloud.com.mwbm.MeedyaConverter"

    /// Validate iCloud availability (checks if Mobile Documents directory exists).
    ///
    /// - Returns: `true` if the iCloud container path exists.
    public static func isICloudAvailable() -> Bool {
        let path = buildContainerPath(containerId: defaultContainerId)
        return FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - MegaUploader

/// Builds Mega.nz API upload request components.
///
/// Mega uses a custom encrypted upload protocol with AES-128-CTR.
/// This struct provides URL builders for the REST API.
///
/// Phase 12.11
public struct MegaUploader: Sendable {

    /// Mega API base URL.
    public static let apiBaseURL = "https://g.api.mega.co.nz"

    /// Mega API CS (command server) URL.
    public static let commandURL = "https://g.api.mega.co.nz/cs"

    /// Build a Mega API command URL with sequence number.
    ///
    /// - Parameter sequenceNumber: Request sequence number.
    /// - Returns: Command URL with ID parameter.
    public static func buildCommandURL(sequenceNumber: Int) -> String {
        return "\(commandURL)?id=\(sequenceNumber)"
    }

    /// Build a login command JSON.
    ///
    /// - Parameters:
    ///   - email: Mega account email.
    ///   - passwordHash: Pre-computed password hash (AES-ECB encrypted).
    /// - Returns: JSON command string.
    public static func buildLoginCommand(
        email: String,
        passwordHash: String
    ) -> String {
        return "[{\"a\":\"us\",\"user\":\"\(email)\",\"uh\":\"\(passwordHash)\"}]"
    }

    /// Build an upload request command JSON.
    ///
    /// - Parameter fileSize: File size in bytes.
    /// - Returns: JSON command string for requesting an upload URL.
    public static func buildUploadRequestCommand(fileSize: Int64) -> String {
        return "[{\"a\":\"u\",\"s\":\(fileSize)}]"
    }

    /// Build file attribute creation command JSON.
    ///
    /// - Parameters:
    ///   - uploadHandle: Handle returned from upload completion.
    ///   - encryptedAttributes: Encrypted file attributes (name, etc.).
    ///   - fileKey: Encrypted file key.
    ///   - parentNode: Parent folder node handle.
    /// - Returns: JSON command string.
    public static func buildCompleteUploadCommand(
        uploadHandle: String,
        encryptedAttributes: String,
        fileKey: String,
        parentNode: String
    ) -> String {
        return "[{\"a\":\"p\",\"t\":\"\(parentNode)\",\"n\":[{\"h\":\"\(uploadHandle)\",\"t\":0,\"a\":\"\(encryptedAttributes)\",\"k\":\"\(fileKey)\"}]}]"
    }

    /// Maximum chunk sizes for Mega upload (increases per chunk).
    /// Starts at 128KB, doubles each chunk up to 1MB, then stays at 1MB.
    public static func chunkSize(forChunkIndex index: Int) -> Int {
        let base = 128 * 1024 // 128 KB
        let maxChunk = 1024 * 1024 // 1 MB
        if index < 4 {
            return base * (1 << index) // 128KB, 256KB, 512KB, 1MB
        }
        return maxChunk
    }
}

// MARK: - MuxUploader

/// Builds Mux video API upload requests.
///
/// Mux is a video infrastructure platform for streaming,
/// providing encoding, storage, and delivery.
///
/// Phase 12.12
public struct MuxUploader: Sendable {

    /// Mux API base URL.
    public static let apiBaseURL = "https://api.mux.com"

    /// Build direct upload creation URL.
    ///
    /// - Returns: Direct upload creation endpoint.
    public static func buildCreateDirectUploadURL() -> String {
        return "\(apiBaseURL)/video/v1/uploads"
    }

    /// Build asset creation URL.
    ///
    /// - Returns: Asset creation endpoint.
    public static func buildCreateAssetURL() -> String {
        return "\(apiBaseURL)/video/v1/assets"
    }

    /// Build asset details URL.
    ///
    /// - Parameter assetId: Mux asset ID.
    /// - Returns: Asset details endpoint.
    public static func buildAssetURL(assetId: String) -> String {
        return "\(apiBaseURL)/video/v1/assets/\(assetId)"
    }

    /// Build HTTP headers for Mux API.
    ///
    /// - Parameters:
    ///   - tokenId: Mux access token ID.
    ///   - tokenSecret: Mux access token secret.
    /// - Returns: Header dictionary with Basic auth.
    public static func buildHeaders(
        tokenId: String,
        tokenSecret: String
    ) -> [String: String] {
        let credentials = "\(tokenId):\(tokenSecret)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return [
            "Authorization": "Basic \(encoded)",
            "Content-Type": "application/json",
        ]
    }

    /// Build direct upload creation request body.
    ///
    /// - Parameters:
    ///   - corsOrigin: Allowed CORS origin (e.g., "https://example.com").
    ///   - newAssetSettings: JSON settings for the new asset.
    /// - Returns: JSON body string.
    public static func buildDirectUploadBody(
        corsOrigin: String = "*",
        playbackPolicy: String = "public",
        mp4Support: Bool = false
    ) -> String {
        var json = "{\"cors_origin\":\"\(corsOrigin)\""
        json += ",\"new_asset_settings\":{"
        json += "\"playback_policy\":[\"\(playbackPolicy)\"]"
        if mp4Support {
            json += ",\"mp4_support\":\"standard\""
        }
        json += "}}"
        return json
    }

    /// Build playback URL for a Mux asset.
    ///
    /// - Parameter playbackId: Mux playback ID.
    /// - Returns: HLS playback URL.
    public static func buildPlaybackURL(playbackId: String) -> String {
        return "https://stream.mux.com/\(playbackId).m3u8"
    }

    /// Build thumbnail URL for a Mux asset.
    ///
    /// - Parameters:
    ///   - playbackId: Mux playback ID.
    ///   - width: Thumbnail width.
    ///   - time: Time offset in seconds.
    /// - Returns: Thumbnail URL.
    public static func buildThumbnailURL(
        playbackId: String,
        width: Int = 640,
        time: Double = 0
    ) -> String {
        return "https://image.mux.com/\(playbackId)/thumbnail.jpg?width=\(width)&time=\(time)"
    }
}

// MARK: - AkamaiNetStorageUploader

/// Builds Akamai NetStorage upload requests.
///
/// Akamai NetStorage uses HTTP API with HMAC-SHA256 authentication.
///
/// Phase 12.13
public struct AkamaiNetStorageUploader: Sendable {

    /// Build the NetStorage upload URL.
    ///
    /// - Parameters:
    ///   - hostname: NetStorage hostname (e.g., "example-nsu.akamaihd.net").
    ///   - cpCode: Content Provider code.
    ///   - remotePath: Remote path for the file.
    /// - Returns: Upload URL.
    public static func buildUploadURL(
        hostname: String,
        cpCode: String,
        remotePath: String
    ) -> String {
        return "https://\(hostname)/\(cpCode)/\(remotePath)"
    }

    /// Build NetStorage API action header for upload.
    ///
    /// - Parameters:
    ///   - action: API action (e.g., "upload", "dir", "delete").
    ///   - version: API version.
    /// - Returns: X-Akamai-ACS-Action header value.
    public static func buildActionHeader(
        action: String = "upload",
        version: Int = 1
    ) -> String {
        return "version=\(version)&action=\(action)"
    }

    /// Build NetStorage authentication headers.
    ///
    /// - Parameters:
    ///   - keyName: Upload account key name.
    ///   - uniqueId: Unique request identifier.
    ///   - timestamp: Unix timestamp.
    ///   - nonce: Random nonce string.
    /// - Returns: X-Akamai-ACS-Auth-Data header value.
    public static func buildAuthDataHeader(
        keyName: String,
        uniqueId: String,
        timestamp: Int,
        nonce: String
    ) -> String {
        return "5, 0.0.0.0, 0.0.0.0, \(timestamp), \(nonce), \(keyName)"
    }

    /// Build full HTTP headers for NetStorage upload.
    ///
    /// - Parameters:
    ///   - authData: Auth data header value.
    ///   - authSign: HMAC-SHA256 signature.
    ///   - action: Action header value.
    ///   - contentType: MIME type.
    /// - Returns: Header dictionary.
    public static func buildUploadHeaders(
        authData: String,
        authSign: String,
        action: String,
        contentType: String
    ) -> [String: String] {
        return [
            "X-Akamai-ACS-Auth-Data": authData,
            "X-Akamai-ACS-Auth-Sign": authSign,
            "X-Akamai-ACS-Action": action,
            "Content-Type": contentType,
        ]
    }
}

// MARK: - BackblazeB2Uploader

/// Builds Backblaze B2 API upload requests.
///
/// Backblaze B2 is an S3-compatible storage service with its own native API.
///
/// Phase 12.2 (extension)
public struct BackblazeB2Uploader: Sendable {

    /// B2 API authorize account URL.
    public static let authorizeURL = "https://api.backblazeb2.com/b2api/v2/b2_authorize_account"

    /// Build B2 get upload URL endpoint.
    ///
    /// - Parameters:
    ///   - apiURL: Authorized API URL (from authorize response).
    ///   - bucketId: B2 bucket ID.
    /// - Returns: Get upload URL endpoint.
    public static func buildGetUploadURL(apiURL: String, bucketId: String) -> String {
        return "\(apiURL)/b2api/v2/b2_get_upload_url?bucketId=\(bucketId)"
    }

    /// Build authorization header for B2 API.
    ///
    /// - Parameters:
    ///   - keyId: Application key ID.
    ///   - applicationKey: Application key.
    /// - Returns: Basic auth header value.
    public static func buildAuthorizationHeader(
        keyId: String,
        applicationKey: String
    ) -> String {
        let credentials = "\(keyId):\(applicationKey)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    /// Build HTTP headers for B2 file upload.
    ///
    /// - Parameters:
    ///   - authorizationToken: Upload authorization token.
    ///   - filename: Remote filename.
    ///   - contentType: MIME type.
    ///   - sha1: SHA-1 hash of file content.
    /// - Returns: Header dictionary.
    public static func buildUploadHeaders(
        authorizationToken: String,
        filename: String,
        contentType: String,
        sha1: String
    ) -> [String: String] {
        return [
            "Authorization": authorizationToken,
            "X-Bz-File-Name": filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename,
            "Content-Type": contentType,
            "X-Bz-Content-Sha1": sha1,
        ]
    }

    /// Build large file start request body.
    ///
    /// - Parameters:
    ///   - bucketId: B2 bucket ID.
    ///   - filename: Remote filename.
    ///   - contentType: MIME type.
    /// - Returns: JSON body string.
    public static func buildStartLargeFileBody(
        bucketId: String,
        filename: String,
        contentType: String
    ) -> String {
        return "{\"bucketId\":\"\(bucketId)\",\"fileName\":\"\(filename)\",\"contentType\":\"\(contentType)\"}"
    }

    /// Minimum part size for large file upload (5 MB, except last part).
    public static let minimumPartSize: Int64 = 5 * 1024 * 1024

    /// Recommended part size (100 MB).
    public static let recommendedPartSize: Int64 = 100 * 1024 * 1024
}
