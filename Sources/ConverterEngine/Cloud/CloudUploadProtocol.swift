// ============================================================================
// MeedyaConverter — CloudUploadProtocol
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - UploadProgress

/// Progress information for a cloud upload.
public struct UploadProgress: Sendable {
    /// Bytes uploaded so far.
    public var bytesUploaded: Int64

    /// Total file size in bytes.
    public var totalBytes: Int64

    /// Upload speed in bytes per second.
    public var bytesPerSecond: Double?

    /// Estimated time remaining in seconds.
    public var estimatedTimeRemaining: TimeInterval? {
        guard let speed = bytesPerSecond, speed > 0 else { return nil }
        let remaining = Double(totalBytes - bytesUploaded)
        return remaining / speed
    }

    /// Progress fraction (0.0–1.0).
    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesUploaded) / Double(totalBytes)
    }

    /// Progress percentage (0–100).
    public var percentage: Int {
        Int(fraction * 100)
    }

    public init(
        bytesUploaded: Int64,
        totalBytes: Int64,
        bytesPerSecond: Double? = nil
    ) {
        self.bytesUploaded = bytesUploaded
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
    }
}

// MARK: - UploadResult

/// The result of a completed upload.
public struct UploadResult: Codable, Sendable {
    /// The remote URL where the file is accessible (if applicable).
    public var remoteURL: String?

    /// Provider-specific identifier for the uploaded file.
    public var fileId: String?

    /// The file size in bytes.
    public var fileSize: Int64

    /// Upload duration in seconds.
    public var uploadDuration: TimeInterval

    /// Whether the upload was verified (checksum match).
    public var verified: Bool

    public init(
        remoteURL: String? = nil,
        fileId: String? = nil,
        fileSize: Int64,
        uploadDuration: TimeInterval,
        verified: Bool = false
    ) {
        self.remoteURL = remoteURL
        self.fileId = fileId
        self.fileSize = fileSize
        self.uploadDuration = uploadDuration
        self.verified = verified
    }
}

// MARK: - CloudProvider

/// Supported cloud storage/upload providers.
public enum CloudProvider: String, Codable, Sendable, CaseIterable {
    case awsS3 = "aws_s3"
    case azureBlob = "azure_blob"
    case googleDrive = "google_drive"
    case dropbox = "dropbox"
    case oneDrive = "onedrive"
    case iCloudDrive = "icloud"
    case cloudflareStream = "cloudflare_stream"
    case mux = "mux"
    case backblazeB2 = "backblaze_b2"
    case sftp = "sftp"
    case ftp = "ftp"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .awsS3: return "Amazon S3"
        case .azureBlob: return "Azure Blob Storage"
        case .googleDrive: return "Google Drive"
        case .dropbox: return "Dropbox"
        case .oneDrive: return "OneDrive"
        case .iCloudDrive: return "iCloud Drive"
        case .cloudflareStream: return "Cloudflare Stream"
        case .mux: return "Mux"
        case .backblazeB2: return "Backblaze B2"
        case .sftp: return "SFTP"
        case .ftp: return "FTP"
        }
    }

    /// Whether this provider supports streaming video delivery.
    public var supportsStreaming: Bool {
        switch self {
        case .cloudflareStream, .mux: return true
        default: return false
        }
    }

    /// Whether this provider uses OAuth for authentication.
    public var usesOAuth: Bool {
        switch self {
        case .googleDrive, .dropbox, .oneDrive: return true
        default: return false
        }
    }
}

// MARK: - CloudCredential

/// Authentication credentials for a cloud provider.
public struct CloudCredential: Codable, Sendable {
    /// The cloud provider this credential is for.
    public var provider: CloudProvider

    /// API key or access key ID.
    public var apiKey: String?

    /// Secret key or API secret.
    public var secret: String?

    /// OAuth access token.
    public var accessToken: String?

    /// OAuth refresh token.
    public var refreshToken: String?

    /// Token expiry date.
    public var tokenExpiry: Date?

    /// Endpoint URL (for S3-compatible, SFTP, etc.).
    public var endpoint: String?

    /// Region (for AWS, Azure, etc.).
    public var region: String?

    /// Bucket or container name.
    public var bucket: String?

    /// Username (for SFTP/FTP).
    public var username: String?

    /// Port number (for SFTP/FTP).
    public var port: Int?

    public init(
        provider: CloudProvider,
        apiKey: String? = nil,
        secret: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        tokenExpiry: Date? = nil,
        endpoint: String? = nil,
        region: String? = nil,
        bucket: String? = nil,
        username: String? = nil,
        port: Int? = nil
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.secret = secret
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = tokenExpiry
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.username = username
        self.port = port
    }

    /// Whether the OAuth token is expired and needs refresh.
    public var isTokenExpired: Bool {
        guard let expiry = tokenExpiry else { return false }
        return Date() >= expiry
    }

    /// Whether minimum required fields are populated.
    public var isConfigured: Bool {
        switch provider {
        case .awsS3, .backblazeB2:
            return apiKey != nil && secret != nil && bucket != nil
        case .azureBlob:
            return apiKey != nil && bucket != nil
        case .googleDrive, .dropbox, .oneDrive:
            return accessToken != nil
        case .cloudflareStream, .mux:
            return apiKey != nil && secret != nil
        case .sftp:
            return endpoint != nil && username != nil
        case .ftp:
            return endpoint != nil
        case .iCloudDrive:
            return true // Uses system credentials
        }
    }
}

// MARK: - UploadConfig

/// Configuration for a cloud upload operation.
public struct UploadConfig: Codable, Sendable {
    /// The cloud provider to upload to.
    public var provider: CloudProvider

    /// Remote path/prefix for the uploaded file.
    public var remotePath: String?

    /// Whether to make the file publicly accessible.
    public var publicAccess: Bool

    /// Content type override (auto-detected if nil).
    public var contentType: String?

    /// Maximum upload chunk size in bytes (for multipart uploads).
    public var chunkSize: Int

    /// Number of concurrent upload parts.
    public var concurrency: Int

    /// Whether to verify the upload with a checksum.
    public var verifyUpload: Bool

    /// Custom metadata tags to apply to the uploaded file.
    public var metadata: [String: String]

    public init(
        provider: CloudProvider,
        remotePath: String? = nil,
        publicAccess: Bool = false,
        contentType: String? = nil,
        chunkSize: Int = 8 * 1024 * 1024, // 8 MB
        concurrency: Int = 4,
        verifyUpload: Bool = true,
        metadata: [String: String] = [:]
    ) {
        self.provider = provider
        self.remotePath = remotePath
        self.publicAccess = publicAccess
        self.contentType = contentType
        self.chunkSize = chunkSize
        self.concurrency = concurrency
        self.verifyUpload = verifyUpload
        self.metadata = metadata
    }

    /// Default content type based on file extension.
    public static func contentType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v": return "video/mp4"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "ts", "m2ts": return "video/mp2t"
        case "mp3": return "audio/mpeg"
        case "aac", "m4a": return "audio/mp4"
        case "flac": return "audio/flac"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        case "srt": return "text/plain"
        case "vtt": return "text/vtt"
        default: return "application/octet-stream"
        }
    }
}
