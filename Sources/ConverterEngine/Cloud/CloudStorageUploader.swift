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

    /// Stable identifier for this configuration, generated fresh by the
    /// default init and preserved across load/save cycles so
    /// `CloudStorageProfileStore` (Issue #459) — and
    /// `PostEncodeActionChain.uploadViaCloud`, which resolves a saved
    /// configuration by this id — stay addressable across app
    /// launches. Added alongside the #459 execution layer; no prior
    /// on-disk `CloudStorageConfig` data exists to migrate (before
    /// #459 `CloudStorageView` never persisted `savedConfigs` at all —
    /// see `CloudStorageProfileStore`'s doc comment).
    public var id: UUID

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
    ///   - id: Stable identifier (defaults to a fresh `UUID()`).
    ///   - provider: The cloud storage provider.
    ///   - accessToken: The OAuth 2.0 access token.
    ///   - refreshToken: An optional refresh token.
    ///   - remotePath: The remote folder path for uploads.
    ///   - label: A user-facing label for this configuration.
    public init(
        id: UUID = UUID(),
        provider: CloudStorageProvider,
        accessToken: String,
        refreshToken: String? = nil,
        remotePath: String,
        label: String
    ) {
        self.id = id
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

    /// Build a Microsoft Graph API "create upload session" request for
    /// OneDrive large-file uploads (Issue #459).
    ///
    /// The simple `/content` PUT endpoint (`buildOneDriveUploadRequest`)
    /// rejects anything over 4 MB
    /// (`OneDriveUploader.simpleUploadMaxBytes`) — media output files
    /// routinely exceed that, so this REQUIRED companion request starts
    /// a resumable upload session at
    /// `/me/drive/root:/<path>:/createUploadSession`. The JSON response
    /// carries an `uploadUrl` that the caller (`CloudUploadExecutor
    /// .uploadInSessionChunks`) then `PUT`s the file to in
    /// `Content-Range`-addressed chunks.
    ///
    /// - Parameters:
    ///   - filePath: The local file name to include in the remote path.
    ///   - config: The OneDrive cloud storage configuration.
    /// - Returns: A configured `URLRequest`, or `nil` if the URL is invalid.
    public static func buildOneDriveCreateSessionRequest(
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

        let urlString = "https://graph.microsoft.com/v1.0/me/drive/root:\(encodedPath):/createUploadSession"
        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "item": [
                "@microsoft.graph.conflictBehavior": "rename",
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

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

// MARK: - CloudStorageProfileStore

/// Read-only access to the cloud storage configurations saved by
/// `CloudStorageView` (Issue #347 / #459), for consumers outside the
/// app's SwiftUI layer — e.g. `PostEncodeActionChain.uploadViaCloud`
/// (Issue #450), which runs inside `ConverterEngine` and has no view to
/// bind form state to.
///
/// Mirrors `SFTPProfileStore`, which does the equivalent job for SFTP
/// profiles: this does not duplicate storage. It reads the exact same
/// `UserDefaults` blob `CloudStorageView` writes (provider / remotePath
/// / label metadata, with the access/refresh token fields always
/// redacted to empty/`nil`) and restores the real tokens from the
/// Keychain via `APIKeyManager` — the same #380-audited secrets split
/// every other provider in this codebase already uses.
///
/// Before Issue #459, `CloudStorageView` held `savedConfigs` purely in
/// `@State` — it was never written to `UserDefaults` at all, so there
/// was nothing for a non-UI consumer like `PostEncodeActionChain` to
/// read. This store (and the matching persistence added to
/// `CloudStorageView`) is what makes a saved cloud destination durable
/// across app launches and referenceable by id from a post-encode
/// action.
public enum CloudStorageProfileStore {

    /// `UserDefaults` key under which the redacted profile array lives.
    /// Shared with `CloudStorageView` so the storage key cannot drift
    /// between the write side (settings UI) and this read side.
    public static let userDefaultsKey = "cloudStorageProfiles"

    /// Loads every saved cloud storage configuration, restoring each
    /// one's access/refresh token from the Keychain.
    ///
    /// - Parameter apiKeyManager: The manager to hydrate secrets from.
    ///   Defaults to a fresh `APIKeyManager()` against the standard
    ///   on-disk location (the same default `CloudStorageView` uses),
    ///   so callers that don't already own an instance don't need to
    ///   construct one.
    /// - Returns: The saved configurations, or an empty array if none
    ///   are saved or the stored JSON cannot be decoded.
    public static func loadProfiles(
        apiKeyManager: APIKeyManager = APIKeyManager()
    ) -> [CloudStorageConfig] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let profiles = try? JSONDecoder().decode([CloudStorageConfig].self, from: data) else {
            return []
        }

        return profiles.map { profile in
            guard profile.accessToken.isEmpty else { return profile }

            let candidates = apiKeyManager.keys(for: apiKeyProvider(for: profile.provider))
            guard let stored = candidates.first(where: { ($0.label ?? "") == profile.label }) ?? candidates.first,
                  let token = stored.accessToken, !token.isEmpty else {
                // No matching Keychain entry (deleted out of band, or
                // never saved) — return the profile as-is. Callers
                // should treat an empty accessToken as "credential
                // unavailable" rather than assume it will authenticate,
                // exactly as `SFTPProfileStore.loadProfiles()` treats an
                // unrecoverable password.
                return profile
            }

            var copy = profile
            copy.accessToken = token
            copy.refreshToken = stored.refreshToken
            return copy
        }
    }

    /// Looks up a single saved configuration by its stable `id`.
    ///
    /// - Parameters:
    ///   - id: The configuration's `CloudStorageConfig.id`.
    ///   - apiKeyManager: The manager to hydrate secrets from.
    /// - Returns: The matching configuration (with its token restored
    ///   from the Keychain when available), or `nil` if no
    ///   configuration with that id is currently saved.
    public static func profile(
        withID id: UUID,
        apiKeyManager: APIKeyManager = APIKeyManager()
    ) -> CloudStorageConfig? {
        loadProfiles(apiKeyManager: apiKeyManager).first { $0.id == id }
    }

    /// Maps the request-builder-side provider enum (`CloudStorageProvider`,
    /// Issue #347) to the Keychain-side one (`APIKeyProvider`, Issue
    /// #380). The two exist for historically separate features and use
    /// slightly different case spellings (`onedrive` vs `oneDrive`) for
    /// the same service.
    public static func apiKeyProvider(for provider: CloudStorageProvider) -> APIKeyProvider {
        switch provider {
        case .dropbox: return .dropbox
        case .onedrive: return .oneDrive
        case .googleDrive: return .googleDrive
        }
    }
}
