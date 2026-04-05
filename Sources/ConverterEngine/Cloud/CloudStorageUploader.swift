// ============================================================================
// MeedyaConverter — CloudStorageUploader (Issue #347)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CloudStorageProvider

/// Supported third-party cloud storage providers for file upload.
///
/// Each provider uses a different REST API for file uploads. The
/// ``CloudStorageUploader`` builds provider-specific `URLRequest`
/// instances that the caller can execute via `URLSession`.
public enum CloudStorageProvider: String, Codable, Sendable, CaseIterable {

    /// Dropbox — uses the Dropbox API v2 content upload endpoint.
    case dropbox

    /// Microsoft OneDrive — uses the Microsoft Graph API.
    case onedrive

    /// Google Drive — uses the Google Drive API v3 upload endpoint.
    case googleDrive
}

// MARK: - CloudStorageConfig

/// Configuration for a cloud storage upload destination.
///
/// Stores the provider type, OAuth tokens, and the remote folder path
/// where files should be uploaded. Configurations are saved per-provider
/// so the user can have multiple upload targets.
public struct CloudStorageConfig: Codable, Sendable {

    /// The cloud storage provider.
    public var provider: CloudStorageProvider

    /// The OAuth 2.0 access token for API requests.
    public var accessToken: String

    /// The OAuth 2.0 refresh token for obtaining new access tokens.
    public var refreshToken: String?

    /// The remote folder path where files will be uploaded.
    public var remotePath: String

    /// A user-facing label for this configuration (e.g., "Work Dropbox").
    public var label: String

    /// Creates a new cloud storage configuration.
    ///
    /// - Parameters:
    ///   - provider: The cloud storage provider.
    ///   - accessToken: The OAuth 2.0 access token.
    ///   - refreshToken: An optional refresh token.
    ///   - remotePath: The remote folder path for uploads.
    ///   - label: A user-facing label for this configuration.
    public init(
        provider: CloudStorageProvider,
        accessToken: String,
        refreshToken: String? = nil,
        remotePath: String,
        label: String
    ) {
        self.provider = provider
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.remotePath = remotePath
        self.label = label
    }
}

// MARK: - CloudStorageUploader

/// Builds upload requests for Dropbox, OneDrive, and Google Drive.
///
/// Each static method constructs a `URLRequest` with the appropriate
/// headers, endpoint URL, and authentication for the target provider.
/// The caller is responsible for attaching the file data as the HTTP
/// body (for streaming uploads) and executing the request via
/// `URLSession`.
///
/// Phase 12.4 — Dropbox/OneDrive/Google Drive Upload (Issue #347)
public struct CloudStorageUploader: Sendable {

    // MARK: - Dropbox

    /// Build a Dropbox API v2 content upload request.
    ///
    /// Uses the `/2/files/upload` endpoint with `Dropbox-API-Arg` header
    /// for specifying the destination path and write mode.
    ///
    /// - Parameters:
    ///   - filePath: The local file name to include in the remote path.
    ///   - config: The Dropbox cloud storage configuration.
    /// - Returns: A configured `URLRequest`, or `nil` if the URL is invalid.
    public static func buildDropboxUploadRequest(
        filePath: String,
        config: CloudStorageConfig
    ) -> URLRequest? {
        guard let url = URL(string: "https://content.dropboxapi.com/2/files/upload") else {
            return nil
        }

        let fileName = (filePath as NSString).lastPathComponent
        let remoteDest = config.remotePath.hasSuffix("/")
            ? config.remotePath + fileName
            : config.remotePath + "/" + fileName

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        // Dropbox API arg header specifying destination path and write mode.
        let apiArg: [String: Any] = [
            "path": remoteDest,
            "mode": "overwrite",
            "autorename": true,
            "mute": false,
            "strict_conflict": false
        ]
        if let argData = try? JSONSerialization.data(withJSONObject: apiArg),
           let argString = String(data: argData, encoding: .utf8) {
            request.setValue(argString, forHTTPHeaderField: "Dropbox-API-Arg")
        }

        return request
    }

    // MARK: - OneDrive

    /// Build a Microsoft Graph API upload request for OneDrive.
    ///
    /// Uses the `/me/drive/root:/<path>:/content` endpoint for simple
    /// file uploads (up to 4 MB). For larger files the caller should
    /// implement a resumable upload session.
    ///
    /// - Parameters:
    ///   - filePath: The local file name to include in the remote path.
    ///   - config: The OneDrive cloud storage configuration.
    /// - Returns: A configured `URLRequest`, or `nil` if the URL is invalid.
    public static func buildOneDriveUploadRequest(
        filePath: String,
        config: CloudStorageConfig
    ) -> URLRequest? {
        let fileName = (filePath as NSString).lastPathComponent
        let remoteDest = config.remotePath.hasSuffix("/")
            ? config.remotePath + fileName
            : config.remotePath + "/" + fileName

        let encodedPath = remoteDest.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? remoteDest

        let urlString = "https://graph.microsoft.com/v1.0/me/drive/root:\(encodedPath):/content"
        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(config.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        return request
    }

    // MARK: - Google Drive

    /// Build a Google Drive API v3 upload request.
    ///
    /// Uses the simple media upload endpoint at
    /// `/upload/drive/v3/files?uploadType=media`. For uploads with
    /// metadata, the caller should use multipart upload instead.
    ///
    /// - Parameters:
    ///   - filePath: The local file name (used to set the file name metadata).
    ///   - config: The Google Drive cloud storage configuration.
    /// - Returns: A configured `URLRequest`, or `nil` if the URL is invalid.
    public static func buildGoogleDriveUploadRequest(
        filePath: String,
        config: CloudStorageConfig
    ) -> URLRequest? {
        let fileName = (filePath as NSString).lastPathComponent
        let encodedName = fileName.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? fileName

        let urlString = "https://www.googleapis.com/upload/drive/v3/files?uploadType=media&name=\(encodedName)"
        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        return request
    }

    // MARK: - OAuth

    /// Build the OAuth 2.0 authorisation URL for a given provider.
    ///
    /// Opens the provider's consent screen where the user grants access
    /// to their files. The `clientId` is the OAuth application ID
    /// registered with each provider.
    ///
    /// - Parameters:
    ///   - provider: The cloud storage provider.
    ///   - clientId: The OAuth 2.0 client/application ID.
    /// - Returns: The authorisation URL to open in the browser.
    public static func authURL(
        provider: CloudStorageProvider,
        clientId: String
    ) -> URL {
        let redirectURI = "meedyaconverter://oauth/callback"
        let encodedRedirect = redirectURI.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? redirectURI
        let encodedClientId = clientId.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? clientId

        let urlString: String
        switch provider {
        case .dropbox:
            urlString = "https://www.dropbox.com/oauth2/authorize"
                + "?client_id=\(encodedClientId)"
                + "&response_type=code"
                + "&redirect_uri=\(encodedRedirect)"
                + "&token_access_type=offline"

        case .onedrive:
            urlString = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
                + "?client_id=\(encodedClientId)"
                + "&response_type=code"
                + "&redirect_uri=\(encodedRedirect)"
                + "&scope=Files.ReadWrite.All+offline_access"

        case .googleDrive:
            urlString = "https://accounts.google.com/o/oauth2/v2/auth"
                + "?client_id=\(encodedClientId)"
                + "&response_type=code"
                + "&redirect_uri=\(encodedRedirect)"
                + "&scope=https://www.googleapis.com/auth/drive.file"
                + "&access_type=offline"
        }

        // Force-unwrap is safe because the URL strings above are well-formed.
        // swiftlint:disable:next force_unwrapping
        return URL(string: urlString)!
    }
}
