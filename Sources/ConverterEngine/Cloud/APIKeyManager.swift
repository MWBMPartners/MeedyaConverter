// ============================================================================
// MeedyaConverter — APIKeyManager
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - APIKeyProvider

/// Services that require API key management.
public enum APIKeyProvider: String, Codable, Sendable, CaseIterable {
    // Cloud storage
    case awsS3 = "aws_s3"
    case azureBlob = "azure_blob"
    case googleDrive = "google_drive"
    case dropbox = "dropbox"
    case oneDrive = "onedrive"
    case backblazeB2 = "backblaze_b2"
    case cloudflareStream = "cloudflare_stream"
    case mux = "mux"
    case mega = "mega"
    case akamaiNetStorage = "akamai_netstorage"

    // Metadata providers
    case tmdb = "tmdb"
    case tvdb = "tvdb"
    case omdb = "omdb"
    case discogs = "discogs"
    case fanArtTV = "fanart_tv"
    case openSubtitles = "opensubtitles"
    case acoustID = "acoustid"
    case meedyaDB = "meedya_db"

    /// Display name.
    public var displayName: String {
        switch self {
        case .awsS3: return "Amazon S3"
        case .azureBlob: return "Azure Blob Storage"
        case .googleDrive: return "Google Drive"
        case .dropbox: return "Dropbox"
        case .oneDrive: return "OneDrive"
        case .backblazeB2: return "Backblaze B2"
        case .cloudflareStream: return "Cloudflare Stream"
        case .mux: return "Mux"
        case .mega: return "Mega.nz"
        case .akamaiNetStorage: return "Akamai NetStorage"
        case .tmdb: return "TMDB"
        case .tvdb: return "TheTVDB"
        case .omdb: return "OMDb (IMDB)"
        case .discogs: return "Discogs"
        case .fanArtTV: return "FanArt.tv"
        case .openSubtitles: return "OpenSubtitles"
        case .acoustID: return "AcoustID"
        case .meedyaDB: return "MeedyaDB"
        }
    }

    /// Category for UI grouping.
    public var category: APIKeyCategory {
        switch self {
        case .awsS3, .azureBlob, .googleDrive, .dropbox, .oneDrive,
             .backblazeB2, .cloudflareStream, .mux, .mega, .akamaiNetStorage:
            return .cloudStorage
        case .tmdb, .tvdb, .omdb, .discogs, .fanArtTV,
             .openSubtitles, .acoustID, .meedyaDB:
            return .metadata
        }
    }

    /// Whether this provider uses OAuth (as opposed to API key).
    public var usesOAuth: Bool {
        switch self {
        case .googleDrive, .dropbox, .oneDrive: return true
        default: return false
        }
    }

    /// Registration URL where users can obtain an API key.
    public var registrationURL: String? {
        switch self {
        case .tmdb: return "https://www.themoviedb.org/settings/api"
        case .tvdb: return "https://thetvdb.com/dashboard/account/apikey"
        case .omdb: return "https://www.omdbapi.com/apikey.aspx"
        case .discogs: return "https://www.discogs.com/settings/developers"
        case .fanArtTV: return "https://fanart.tv/get-an-api-key/"
        case .openSubtitles: return "https://www.opensubtitles.com/consumers"
        case .acoustID: return "https://acoustid.org/new-application"
        case .awsS3: return "https://aws.amazon.com/iam/"
        case .backblazeB2: return "https://www.backblaze.com/b2/docs/application_keys.html"
        case .cloudflareStream: return "https://dash.cloudflare.com/profile/api-tokens"
        case .mux: return "https://dashboard.mux.com/settings/access-tokens"
        default: return nil
        }
    }
}

// MARK: - APIKeyCategory

/// Categories for grouping API key providers in the UI.
public enum APIKeyCategory: String, Codable, Sendable, CaseIterable {
    case cloudStorage = "cloud_storage"
    case metadata = "metadata"

    /// Display name.
    public var displayName: String {
        switch self {
        case .cloudStorage: return "Cloud Storage & Delivery"
        case .metadata: return "Metadata Providers"
        }
    }
}

// MARK: - StoredAPIKey

/// An API key stored in the secure keychain.
public struct StoredAPIKey: Codable, Sendable {
    /// The provider this key belongs to.
    public var provider: APIKeyProvider

    /// The API key / access key ID.
    public var apiKey: String

    /// Secondary secret (e.g., AWS secret key, API secret).
    public var secretKey: String?

    /// OAuth access token (for OAuth providers).
    public var accessToken: String?

    /// OAuth refresh token.
    public var refreshToken: String?

    /// Token expiry date.
    public var tokenExpiry: Date?

    /// Optional label/description for this key.
    public var label: String?

    /// Date the key was added.
    public var addedDate: Date

    /// Date the key was last used.
    public var lastUsedDate: Date?

    /// Whether the key is currently active.
    public var isActive: Bool

    public init(
        provider: APIKeyProvider,
        apiKey: String,
        secretKey: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        tokenExpiry: Date? = nil,
        label: String? = nil,
        addedDate: Date = Date(),
        lastUsedDate: Date? = nil,
        isActive: Bool = true
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = tokenExpiry
        self.label = label
        self.addedDate = addedDate
        self.lastUsedDate = lastUsedDate
        self.isActive = isActive
    }

    /// Whether the OAuth token is expired and needs refresh.
    public var isTokenExpired: Bool {
        guard let expiry = tokenExpiry else { return false }
        return Date() >= expiry
    }

    /// Whether the key has all required fields for its provider.
    public var isValid: Bool {
        guard !apiKey.isEmpty else { return false }

        switch provider {
        case .awsS3, .backblazeB2:
            return secretKey != nil && !(secretKey?.isEmpty ?? true)
        case .mux, .cloudflareStream, .akamaiNetStorage:
            return secretKey != nil && !(secretKey?.isEmpty ?? true)
        case .googleDrive, .dropbox, .oneDrive:
            return accessToken != nil && !(accessToken?.isEmpty ?? true)
        default:
            return true
        }
    }
}

// MARK: - APIKeyManager

/// Manages API keys for cloud and metadata providers.
///
/// Keys are stored as JSON in the app's secure storage directory.
/// On macOS, sensitive values should be stored in Keychain (handled
/// by the UI layer). This engine-level manager handles the key registry
/// and validation.
///
/// Phase 12.15
public final class APIKeyManager: @unchecked Sendable {

    // MARK: - Properties

    /// All stored API keys.
    public private(set) var keys: [StoredAPIKey]

    /// Storage file URL.
    private let storageURL: URL

    /// Lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Initialiser

    /// Create an API key manager.
    ///
    /// - Parameter storageDirectory: Directory for key storage.
    public init(storageDirectory: URL? = nil) {
        let defaultDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MeedyaConverter")
            .appendingPathComponent("Keys")

        let dir = storageDirectory ?? defaultDir
        self.storageURL = dir.appendingPathComponent("api_keys.json")
        self.keys = []

        loadKeys()
    }

    // MARK: - CRUD

    /// Add or update an API key.
    ///
    /// - Parameter key: The API key to store.
    public func storeKey(_ key: StoredAPIKey) {
        lock.lock()
        defer { lock.unlock() }

        if let index = keys.firstIndex(where: { $0.provider == key.provider && $0.label == key.label }) {
            keys[index] = key
        } else {
            keys.append(key)
        }
        saveKeys()
    }

    /// Remove an API key.
    ///
    /// - Parameters:
    ///   - provider: The provider to remove the key for.
    ///   - label: Optional label to identify which key (if multiple per provider).
    public func removeKey(provider: APIKeyProvider, label: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        keys.removeAll { key in
            key.provider == provider && (label == nil || key.label == label)
        }
        saveKeys()
    }

    /// Get the active API key for a provider.
    ///
    /// - Parameter provider: The provider.
    /// - Returns: The active key, or nil.
    public func key(for provider: APIKeyProvider) -> StoredAPIKey? {
        lock.lock()
        defer { lock.unlock() }

        return keys.first { $0.provider == provider && $0.isActive }
    }

    /// Get all keys for a provider.
    ///
    /// - Parameter provider: The provider.
    /// - Returns: All keys for the provider.
    public func keys(for provider: APIKeyProvider) -> [StoredAPIKey] {
        lock.lock()
        defer { lock.unlock() }

        return keys.filter { $0.provider == provider }
    }

    /// Get all keys in a category.
    ///
    /// - Parameter category: The category.
    /// - Returns: All keys in the category.
    public func keys(in category: APIKeyCategory) -> [StoredAPIKey] {
        lock.lock()
        defer { lock.unlock() }

        return keys.filter { $0.provider.category == category }
    }

    /// Mark a key's last used date.
    ///
    /// - Parameter provider: The provider whose key was used.
    public func markUsed(provider: APIKeyProvider) {
        lock.lock()
        defer { lock.unlock() }

        if let index = keys.firstIndex(where: { $0.provider == provider && $0.isActive }) {
            keys[index].lastUsedDate = Date()
            saveKeys()
        }
    }

    /// Check if a provider has a configured key.
    ///
    /// - Parameter provider: The provider to check.
    /// - Returns: `true` if an active key exists.
    public func hasKey(for provider: APIKeyProvider) -> Bool {
        key(for: provider) != nil
    }

    /// Get all providers that have configured keys.
    ///
    /// - Returns: Set of providers with active keys.
    public func configuredProviders() -> Set<APIKeyProvider> {
        lock.lock()
        defer { lock.unlock() }

        return Set(keys.filter { $0.isActive }.map { $0.provider })
    }

    // MARK: - Persistence

    private func loadKeys() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            keys = try decoder.decode([StoredAPIKey].self, from: data)
        } catch {
            print("Warning: Could not load API keys: \(error.localizedDescription)")
        }
    }

    private func saveKeys() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(keys)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Warning: Could not save API keys: \(error.localizedDescription)")
        }
    }
}
