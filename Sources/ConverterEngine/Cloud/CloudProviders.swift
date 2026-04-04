// ============================================================================
// MeedyaConverter — CloudProviders
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - GoogleDriveUploader

/// Builds Google Drive API upload requests.
///
/// Supports simple upload, resumable upload for large files,
/// and folder targeting.
///
/// Phase 12.6
public struct GoogleDriveUploader: Sendable {

    /// Google Drive API base URL.
    public static let apiBaseURL = "https://www.googleapis.com/upload/drive/v3/files"

    /// Google Drive metadata API base URL.
    public static let metadataBaseURL = "https://www.googleapis.com/drive/v3/files"

    /// Build upload URL for simple (small file) upload.
    ///
    /// - Parameter accessToken: OAuth 2.0 access token.
    /// - Returns: Upload URL with query parameters.
    public static func buildSimpleUploadURL(accessToken: String) -> String {
        return "\(apiBaseURL)?uploadType=media"
    }

    /// Build upload URL for resumable (large file) upload.
    ///
    /// - Returns: Resumable upload initiation URL.
    public static func buildResumableUploadURL() -> String {
        return "\(apiBaseURL)?uploadType=resumable"
    }

    /// Build HTTP headers for Google Drive upload.
    ///
    /// - Parameters:
    ///   - accessToken: OAuth 2.0 access token.
    ///   - contentType: MIME type of the file.
    ///   - contentLength: File size in bytes.
    /// - Returns: Header dictionary.
    public static func buildUploadHeaders(
        accessToken: String,
        contentType: String,
        contentLength: Int64? = nil
    ) -> [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": contentType,
        ]
        if let length = contentLength {
            headers["Content-Length"] = "\(length)"
        }
        return headers
    }

    /// Build resumable upload metadata JSON.
    ///
    /// - Parameters:
    ///   - filename: File name.
    ///   - mimeType: MIME type.
    ///   - folderId: Target folder ID (nil = root).
    /// - Returns: JSON metadata string.
    public static func buildUploadMetadata(
        filename: String,
        mimeType: String,
        folderId: String? = nil
    ) -> String {
        var json = "{\"name\":\"\(filename)\",\"mimeType\":\"\(mimeType)\""
        if let folder = folderId {
            json += ",\"parents\":[\"\(folder)\"]"
        }
        json += "}"
        return json
    }

    /// Build folder creation request body.
    ///
    /// - Parameters:
    ///   - folderName: Name of the folder to create.
    ///   - parentId: Parent folder ID (nil = root).
    /// - Returns: JSON body string.
    public static func buildCreateFolderBody(
        folderName: String,
        parentId: String? = nil
    ) -> String {
        var json = "{\"name\":\"\(folderName)\",\"mimeType\":\"application/vnd.google-apps.folder\""
        if let parent = parentId {
            json += ",\"parents\":[\"\(parent)\"]"
        }
        json += "}"
        return json
    }

    /// Maximum file size for simple upload (5 MB).
    public static let simpleUploadMaxBytes: Int64 = 5 * 1024 * 1024

    /// Recommended chunk size for resumable upload (256 KB multiples, 5 MB default).
    public static let resumableChunkSize: Int64 = 5 * 1024 * 1024
}

// MARK: - DropboxUploader

/// Builds Dropbox API upload requests.
///
/// Phase 12.7
public struct DropboxUploader: Sendable {

    /// Dropbox content upload API URL.
    public static let uploadURL = "https://content.dropboxapi.com/2/files/upload"

    /// Dropbox upload session start URL (for large files).
    public static let sessionStartURL = "https://content.dropboxapi.com/2/files/upload_session/start"

    /// Dropbox upload session append URL.
    public static let sessionAppendURL = "https://content.dropboxapi.com/2/files/upload_session/append_v2"

    /// Dropbox upload session finish URL.
    public static let sessionFinishURL = "https://content.dropboxapi.com/2/files/upload_session/finish"

    /// Maximum file size for single upload (150 MB).
    public static let singleUploadMaxBytes: Int64 = 150 * 1024 * 1024

    /// Chunk size for session uploads (8 MB).
    public static let sessionChunkSize: Int64 = 8 * 1024 * 1024

    /// Build HTTP headers for Dropbox upload.
    ///
    /// - Parameters:
    ///   - accessToken: OAuth 2.0 access token.
    ///   - dropboxPath: Destination path in Dropbox (e.g., "/Videos/movie.mp4").
    ///   - overwrite: Whether to overwrite existing file.
    /// - Returns: Header dictionary.
    public static func buildUploadHeaders(
        accessToken: String,
        dropboxPath: String,
        overwrite: Bool = false
    ) -> [String: String] {
        let mode = overwrite ? "overwrite" : "add"
        let apiArg = "{\"path\":\"\(dropboxPath)\",\"mode\":\"\(mode)\",\"autorename\":true}"
        return [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/octet-stream",
            "Dropbox-API-Arg": apiArg,
        ]
    }

    /// Build session start headers.
    ///
    /// - Parameter accessToken: OAuth 2.0 access token.
    /// - Returns: Header dictionary.
    public static func buildSessionStartHeaders(accessToken: String) -> [String: String] {
        return [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/octet-stream",
        ]
    }

    /// Build session finish headers.
    ///
    /// - Parameters:
    ///   - accessToken: OAuth 2.0 access token.
    ///   - sessionId: Upload session ID.
    ///   - offset: Final byte offset.
    ///   - dropboxPath: Destination path.
    /// - Returns: Header dictionary.
    public static func buildSessionFinishHeaders(
        accessToken: String,
        sessionId: String,
        offset: Int64,
        dropboxPath: String
    ) -> [String: String] {
        let apiArg = "{\"cursor\":{\"session_id\":\"\(sessionId)\",\"offset\":\(offset)},\"commit\":{\"path\":\"\(dropboxPath)\",\"mode\":\"add\",\"autorename\":true}}"
        return [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/octet-stream",
            "Dropbox-API-Arg": apiArg,
        ]
    }
}

// MARK: - AzureBlobUploader

/// Builds Azure Blob Storage upload requests.
///
/// Phase 12.4
public struct AzureBlobUploader: Sendable {

    /// Build the Azure Blob Storage upload URL.
    ///
    /// - Parameters:
    ///   - accountName: Storage account name.
    ///   - containerName: Blob container name.
    ///   - blobName: Blob (file) name.
    /// - Returns: Full blob URL.
    public static func buildBlobURL(
        accountName: String,
        containerName: String,
        blobName: String
    ) -> String {
        return "https://\(accountName).blob.core.windows.net/\(containerName)/\(blobName)"
    }

    /// Build HTTP headers for Azure Blob upload.
    ///
    /// - Parameters:
    ///   - sasToken: Shared Access Signature token.
    ///   - contentType: MIME type.
    ///   - contentLength: File size in bytes.
    /// - Returns: Header dictionary.
    public static func buildUploadHeaders(
        sasToken: String,
        contentType: String,
        contentLength: Int64
    ) -> [String: String] {
        return [
            "x-ms-blob-type": "BlockBlob",
            "Content-Type": contentType,
            "Content-Length": "\(contentLength)",
            "x-ms-version": "2023-11-03",
        ]
    }

    /// Build URL with SAS token appended.
    ///
    /// - Parameters:
    ///   - blobURL: Base blob URL.
    ///   - sasToken: SAS token string.
    /// - Returns: Full URL with SAS authentication.
    public static func buildAuthenticatedURL(
        blobURL: String,
        sasToken: String
    ) -> String {
        return "\(blobURL)?\(sasToken)"
    }

    /// Build block list XML for committing multipart upload.
    ///
    /// - Parameter blockIds: Array of base64-encoded block IDs.
    /// - Returns: Block list XML string.
    public static func buildBlockListXML(blockIds: [String]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<BlockList>\n"
        for id in blockIds {
            xml += "  <Latest>\(id)</Latest>\n"
        }
        xml += "</BlockList>"
        return xml
    }

    /// Maximum block size (100 MB for newer API versions).
    public static let maxBlockSize: Int64 = 100 * 1024 * 1024

    /// Default block size (4 MB).
    public static let defaultBlockSize: Int64 = 4 * 1024 * 1024
}

// MARK: - OneDriveUploader

/// Builds OneDrive / OneDrive for Business upload requests.
///
/// Phase 12.8
public struct OneDriveUploader: Sendable {

    /// Microsoft Graph API base URL.
    public static let graphBaseURL = "https://graph.microsoft.com/v1.0"

    /// Build simple upload URL (< 4 MB).
    ///
    /// - Parameters:
    ///   - drivePath: Path in OneDrive (e.g., "/Videos/movie.mp4").
    /// - Returns: Upload URL.
    public static func buildSimpleUploadURL(drivePath: String) -> String {
        return "\(graphBaseURL)/me/drive/root:\(drivePath):/content"
    }

    /// Build resumable upload session creation URL.
    ///
    /// - Parameter drivePath: Path in OneDrive.
    /// - Returns: Create upload session URL.
    public static func buildCreateSessionURL(drivePath: String) -> String {
        return "\(graphBaseURL)/me/drive/root:\(drivePath):/createUploadSession"
    }

    /// Build HTTP headers for OneDrive upload.
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

    /// Build upload session request body.
    ///
    /// - Parameter conflictBehavior: "rename", "replace", or "fail".
    /// - Returns: JSON body string.
    public static func buildSessionBody(conflictBehavior: String = "rename") -> String {
        return "{\"item\":{\"@microsoft.graph.conflictBehavior\":\"\(conflictBehavior)\"}}"
    }

    /// Maximum file size for simple upload (4 MB).
    public static let simpleUploadMaxBytes: Int64 = 4 * 1024 * 1024

    /// Upload fragment size for resumable upload (10 MB, must be multiple of 320 KB).
    public static let fragmentSize: Int64 = 10 * 1024 * 1024
}

// MARK: - CloudflareStreamUploader

/// Builds Cloudflare Stream upload requests.
///
/// Phase 12.5
public struct CloudflareStreamUploader: Sendable {

    /// Cloudflare API base URL.
    public static let apiBaseURL = "https://api.cloudflare.com/client/v4"

    /// Build direct upload URL.
    ///
    /// - Parameter accountId: Cloudflare account ID.
    /// - Returns: Direct upload creation URL.
    public static func buildDirectUploadURL(accountId: String) -> String {
        return "\(apiBaseURL)/accounts/\(accountId)/stream/direct_upload"
    }

    /// Build TUS upload URL for resumable uploads.
    ///
    /// - Parameter accountId: Cloudflare account ID.
    /// - Returns: TUS upload URL.
    public static func buildTUSUploadURL(accountId: String) -> String {
        return "\(apiBaseURL)/accounts/\(accountId)/stream"
    }

    /// Build HTTP headers for Cloudflare Stream upload.
    ///
    /// - Parameters:
    ///   - apiToken: Cloudflare API token.
    ///   - contentLength: File size in bytes.
    /// - Returns: Header dictionary.
    public static func buildUploadHeaders(
        apiToken: String,
        contentLength: Int64
    ) -> [String: String] {
        return [
            "Authorization": "Bearer \(apiToken)",
            "Content-Length": "\(contentLength)",
            "Tus-Resumable": "1.0.0",
            "Upload-Length": "\(contentLength)",
        ]
    }

    /// Build metadata header for Cloudflare Stream.
    ///
    /// - Parameters:
    ///   - name: Video name/title.
    ///   - requireSignedURLs: Whether playback requires signed URLs.
    /// - Returns: Upload-Metadata header value.
    public static func buildUploadMetadata(
        name: String,
        requireSignedURLs: Bool = false
    ) -> String {
        // TUS metadata is base64-encoded key-value pairs
        let nameEncoded = Data(name.utf8).base64EncodedString()
        var metadata = "name \(nameEncoded)"
        if requireSignedURLs {
            let flagEncoded = Data("true".utf8).base64EncodedString()
            metadata += ",requiresignedurls \(flagEncoded)"
        }
        return metadata
    }
}

// MARK: - FTPUploader

/// Builds FTP/FTPS upload arguments.
///
/// Phase 12.14 (extension of existing SFTP)
public struct FTPUploader: Sendable {

    /// Build curl arguments for FTP upload.
    ///
    /// - Parameters:
    ///   - localPath: Local file path.
    ///   - ftpURL: FTP server URL (e.g., "ftp://server.com/path/file.mp4").
    ///   - username: FTP username.
    ///   - password: FTP password.
    ///   - useFTPS: Whether to use FTPS (TLS).
    /// - Returns: Argument array for curl.
    public static func buildCurlUploadArguments(
        localPath: String,
        ftpURL: String,
        username: String,
        password: String,
        useFTPS: Bool = true
    ) -> [String] {
        var args: [String] = []

        args += ["-T", localPath]
        args += ["-u", "\(username):\(password)"]

        if useFTPS {
            args += ["--ssl-reqd"]
        }

        // Progress meter
        args += ["--progress-bar"]

        // Create directories if needed
        args += ["--ftp-create-dirs"]

        args.append(ftpURL)

        return args
    }

    /// Build lftp arguments for FTP upload with resume support.
    ///
    /// - Parameters:
    ///   - localPath: Local file path.
    ///   - remotePath: Remote path on FTP server.
    ///   - host: FTP server hostname.
    ///   - username: FTP username.
    ///   - password: FTP password.
    ///   - useFTPS: Whether to use FTPS.
    /// - Returns: lftp command string.
    public static func buildLftpCommand(
        localPath: String,
        remotePath: String,
        host: String,
        username: String,
        password: String,
        useFTPS: Bool = true
    ) -> String {
        let protocol_ = useFTPS ? "ftps" : "ftp"
        return "open \(protocol_)://\(username):\(password)@\(host) && put \(localPath) -o \(remotePath) && bye"
    }
}

// MARK: - APIKeyConfig

/// Configuration for managing API keys across cloud providers.
///
/// Phase 12.15
public struct APIKeyConfig: Codable, Sendable {
    /// Provider identifier.
    public var provider: CloudProvider

    /// API key or access token.
    public var apiKey: String

    /// Secret key (for providers that use key pairs like AWS).
    public var secretKey: String?

    /// OAuth refresh token (for OAuth-based providers).
    public var refreshToken: String?

    /// OAuth token expiry date.
    public var tokenExpiresAt: Date?

    /// Region (for cloud storage providers).
    public var region: String?

    /// Custom endpoint URL (for S3-compatible providers).
    public var customEndpoint: String?

    /// Human-readable label for this credential.
    public var label: String?

    public init(
        provider: CloudProvider,
        apiKey: String,
        secretKey: String? = nil,
        refreshToken: String? = nil,
        tokenExpiresAt: Date? = nil,
        region: String? = nil,
        customEndpoint: String? = nil,
        label: String? = nil
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.refreshToken = refreshToken
        self.tokenExpiresAt = tokenExpiresAt
        self.region = region
        self.customEndpoint = customEndpoint
        self.label = label
    }

    /// Whether the OAuth token has expired.
    public var isTokenExpired: Bool {
        guard let expiry = tokenExpiresAt else { return false }
        return Date() >= expiry
    }

    /// Whether this credential has the minimum required fields.
    public var isValid: Bool {
        !apiKey.isEmpty
    }
}
