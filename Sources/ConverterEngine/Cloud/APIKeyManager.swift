// ============================================================================
// MeedyaConverter — APIKeyManager
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// On Apple platforms the Security framework provides the Keychain APIs we
// use to keep raw secrets out of the on-disk JSON. On non-Apple builds we
// fall back to in-memory secrets only — see `KeychainStore` below.
#if canImport(Security)
import Security
#endif

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

    // Media servers
    /// Plex, Jellyfin or Emby — whichever one `MediaServerSettingsView`
    /// has selected. There is only one media-server connection at a time
    /// today, so this single case covers all three; the server TYPE is a
    /// separate setting (`MediaServerType`, not this enum). Added for
    /// #506 commit 1 to move `MediaServerSettingsView`'s API key/token out
    /// of the plain-text settings file (SECURITY.md F-013) and into the
    /// Keychain, via `MediaServerCredentialStore`.
    case mediaServer = "media_server"

    // Internal MWBM services
    /// MWBM `intAppsAPI` — remote feature flags + update channels
    /// (roadmap #4/#5). Field mapping onto `StoredAPIKey` is documented
    /// on `IntAppsAPICredentialLoader.loadFromKeychain(apiKeyManager:)`
    /// in `Services/IntAppsAPIClient.swift`: `apiKey` → `X-API-Key`,
    /// `secretKey` → `X-App-ID`, `label` → `app_slug`, `refreshToken` →
    /// `User-Agent` prefix. There is no dedicated Keychain-entry UI for
    /// this provider yet (unlike `CloudStorageView`'s "add key" flow) —
    /// a maintainer provisions it via `APIKeyManager.storeKey(_:)`
    /// directly, or via the `MEEDYACONVERTER_INTAPPSAPI_*` environment
    /// variables for local development.
    case intAppsAPI = "int_apps_api"

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
        case .mediaServer: return "Media server (Plex, Jellyfin, Emby)"
        case .intAppsAPI: return "MWBM intAppsAPI"
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
        case .mediaServer:
            return .mediaServers
        case .intAppsAPI:
            return .internalServices
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
    /// Plex, Jellyfin and Emby credentials (#506 commit 1). Its own
    /// category rather than folding into `metadata` — a media server
    /// isn't a metadata *provider*, it's the thing being told to rescan.
    case mediaServers = "media_servers"
    /// Internal MWBM Partners services (e.g. intAppsAPI) — not a
    /// user-facing cloud/metadata provider, so kept as its own category
    /// rather than overloading `cloudStorage`/`metadata`.
    case internalServices = "internal_services"

    /// Display name.
    public var displayName: String {
        switch self {
        case .cloudStorage: return "Cloud Storage & Delivery"
        case .metadata: return "Metadata Providers"
        case .mediaServers: return "Media Servers"
        case .internalServices: return "Internal Services"
        }
    }
}

// MARK: - StoredAPIKey

/// An API key entry, as seen by callers.
///
/// Secret fields (`apiKey`, `secretKey`, `accessToken`, `refreshToken`) are
/// only kept in memory while the manager is alive — on disk only the
/// metadata fields are persisted, and the secrets live in the system
/// Keychain. The public shape of this struct is unchanged from previous
/// releases so existing callers do not need to be touched.
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
        case .intAppsAPI:
            // `secretKey` carries the app's `X-App-ID` UUID and `label`
            // carries the `app_slug` — both required for a usable
            // credential set. See `IntAppsAPICredentialLoader`.
            return secretKey != nil && !(secretKey?.isEmpty ?? true)
                && label != nil && !(label?.isEmpty ?? true)
        default:
            return true
        }
    }
}

// MARK: - APIKeyManager

/// Manages API keys for cloud and metadata providers.
///
/// **Persistence layout (audit follow-up for #380):**
///
/// Raw secrets — `apiKey`, `secretKey`, `accessToken`, `refreshToken` —
/// are written to the system Keychain as one `kSecClassGenericPassword`
/// item per `(provider, label)` pair. The on-disk JSON now contains only
/// non-sensitive metadata plus a stable Keychain account string. This
/// replaces the previous behaviour of writing the full struct (including
/// secrets) to `api_keys.json` in plaintext.
///
/// **Migration:** the first time this version of the manager runs against
/// an `api_keys.json` written by the old code, it auto-detects the legacy
/// shape, copies each entry's secrets into the Keychain, and rewrites the
/// file in the new metadata-only envelope. The legacy load path is also
/// retained so that downgrading does not silently lose keys (the legacy
/// build will still find readable metadata in the file, just without
/// secrets — the user re-enters them).
///
/// On non-Apple platforms (`!canImport(Security)`) the Keychain is not
/// available; the manager refuses to persist secrets to disk and keeps
/// them in memory only, with a warning. Adding Linux support requires
/// wiring up libsecret or an equivalent.
///
/// Phase 12.15 — see issue #380 for the security audit that drove the
/// Keychain migration.
public final class APIKeyManager: @unchecked Sendable {

    // MARK: - Notification Names

    /// Posted after `storeKey(_:)` or `removeKey(provider:label:)` finish
    /// writing, so any screen showing "is a key saved?" can refresh
    /// without polling. Deliberately NOT posted by `markUsed(provider:)` —
    /// bumping a last-used timestamp is bookkeeping, not something any UI
    /// needs to redraw for, and posting on every lookup-adjacent write
    /// would make the notification noisy enough that nobody could tell a
    /// real change from housekeeping.
    ///
    /// Posted via `NotificationCenter.default` with `object: self`, and —
    /// this is the part that matters — only AFTER this instance's `lock`
    /// has been released. `NSLock` is not re-entrant: the whole point of
    /// this notification is that a settings screen can react by calling
    /// straight back into the SAME manager (e.g. re-reading `key(for:)`
    /// to refresh a "key saved" label), and if we posted while still
    /// holding `lock`, that call would deadlock against itself. See the
    /// bottom of `storeKey(_:)`/`removeKey(provider:label:)` for where the
    /// unlock happens relative to the post.
    ///
    /// WHAT THIS DOES NOT SOLVE (finding 10 covers the notification gap;
    /// this is the boundary of the fix): it only reaches observers inside
    /// THIS PROCESS. Two separate processes — the app and, in the future,
    /// a command-line tool — sharing the same `api_keys.json` are not
    /// coordinated by this notification any more than they are by the
    /// in-process `lock` documented on `reloadLocked()`. Today that gap is
    /// theoretical: no CLI target constructs an `APIKeyManager` yet. It is
    /// written down here as a known limit for whenever one does, not as a
    /// guarantee that cross-process observation already works.
    public static let didChangeNotification = Notification.Name(
        "com.mwbm.meedyaconverter.apiKeyManagerDidChange"
    )

    // MARK: - Persistence model

    /// The Keychain service (`kSecAttrService`) every production
    /// `APIKeyManager` uses. Named here, once, because two things need it:
    /// `init`'s default, and `hasStoredKey(for:label:storageDirectory:
    /// keychainService:)`'s default — which runs WITHOUT an instance, so
    /// it cannot borrow an instance's value. Stable across releases:
    /// changing it would orphan every saved key.
    public static let productionKeychainService = "Ltd.MWBMpartners.MeedyaConverter.APIKeys"

    /// File name of the saved-keys list (the metadata index) inside the
    /// storage directory. One name, shared by `init` and `hasStoredKey`, so
    /// the two can never look at different files.
    private static let indexFileName = "api_keys.json"

    /// `~/Library/Application Support/MeedyaConverter/Keys` for THIS
    /// process. Shared by `init` and `hasStoredKey` for the same reason as
    /// `indexFileName`.
    ///
    /// Note what "for this process" means: a sandboxed build (the App Store
    /// build has `com.apple.security.app-sandbox`) gets its own private
    /// Application Support folder inside its container, while the
    /// command-line tool is not sandboxed. The two therefore read DIFFERENT
    /// saved-keys lists. Nothing here can bridge that; it is recorded so
    /// nobody assumes the command-line tool sees the App Store app's keys.
    private static func defaultStorageDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MeedyaConverter")
            .appendingPathComponent("Keys")
    }

    /// Storage-format version. Increment when the on-disk shape changes
    /// in a non-backward-compatible way.
    ///
    /// * v2: metadata-only envelope, secrets in Keychain (current).
    /// * v1: legacy `[StoredAPIKey]` array with embedded secrets (read
    ///   on load to support migration; never written).
    private static let currentStorageVersion = 2

    /// The on-disk envelope. Only metadata; no secret material.
    private struct StorageEnvelope: Codable {
        let version: Int
        let records: [MetadataRecord]
    }

    /// A single key entry as persisted to disk. Mirrors `StoredAPIKey`
    /// minus the four secret fields, plus the Keychain account string
    /// used to look those secrets up.
    private struct MetadataRecord: Codable {
        let provider: APIKeyProvider
        let label: String?
        let tokenExpiry: Date?
        let addedDate: Date
        let lastUsedDate: Date?
        let isActive: Bool
        /// Stable identity used as `kSecAttrAccount` in the Keychain.
        /// Derived from `(provider, label)` so the disk record can find
        /// its matching secrets after a restart.
        let keychainAccount: String
    }

    /// The four secret fields, bundled into a single Keychain item so we
    /// can write all of them atomically.
    private struct Secrets: Codable {
        let apiKey: String
        let secretKey: String?
        let accessToken: String?
        let refreshToken: String?

        /// Whether this secrets blob holds any non-empty material. Empty
        /// blobs are not written to the Keychain — there is nothing to
        /// protect, and it lets the migration code skip records that
        /// happen to have only metadata.
        var hasAnySecret: Bool {
            !apiKey.isEmpty
                || (secretKey?.isEmpty == false)
                || (accessToken?.isEmpty == false)
                || (refreshToken?.isEmpty == false)
        }
    }

    // MARK: - Properties

    /// All stored API keys (with secrets hydrated from the Keychain).
    public private(set) var keys: [StoredAPIKey]

    /// Storage file URL (metadata envelope only).
    private let storageURL: URL

    /// `kSecAttrService` used for every Keychain item this manager owns.
    /// Defaulting to a bundle-identifier-style string keeps the items
    /// neatly grouped in Keychain Access and makes test isolation easy
    /// (tests can pass their own service string).
    private let keychainService: String

    /// Lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Initialiser

    /// Create an API key manager.
    ///
    /// - Parameters:
    ///   - storageDirectory: Directory for the metadata JSON. Defaults
    ///     to `~/Library/Application Support/MeedyaConverter/Keys`.
    ///   - keychainService: `kSecAttrService` value for the Keychain
    ///     items this manager owns. The default is shared across all
    ///     production app instances; tests should pass a UUID-based
    ///     service to keep their secrets isolated from the user's real
    ///     Keychain entries.
    public init(
        storageDirectory: URL? = nil,
        keychainService: String = APIKeyManager.productionKeychainService
    ) {
        let dir = storageDirectory ?? Self.defaultStorageDirectory()
        self.storageURL = dir.appendingPathComponent(Self.indexFileName)
        self.keychainService = keychainService
        self.keys = []

        // No explicit `lock.lock()` here even though `reloadLocked()`
        // documents itself as requiring the lock held: at this point in
        // `init`, `self` has not yet been handed to any caller, so there
        // is no other thread that could possibly be racing this first
        // read. Every reload after this one — from `storeKey`,
        // `removeKey`, `markUsed`, or any of the lookup methods — does
        // take the lock first. See `reloadLocked()` for the shared logic
        // and why a reload (not just a one-time load) is needed at all.
        reloadLocked()
    }

    // MARK: - CRUD

    /// Add or update an API key.
    ///
    /// Secrets are written to the Keychain immediately; metadata is
    /// flushed to disk.
    ///
    /// **Why this reloads first (Codex catch-up review, finding 2):**
    /// several long-lived `APIKeyManager` instances exist at once —
    /// `MetadataSettingsTab`, `MeedyaDBSettingsTab` and `CloudStorageView`
    /// each keep their own in a `@State` var for the life of the screen,
    /// on top of the fresh ones the disc pipeline view models,
    /// `TMDBLookupSheet` and the uploaders create per call. `saveKeys()`
    /// rewrites the WHOLE index file from THIS instance's `keys` array.
    /// Without a reload immediately before that rewrite, whichever
    /// instance calls `storeKey`/`removeKey` LAST would silently discard
    /// every record any other instance had saved in the meantime — a
    /// classic lost-update race, not a crash, so it went unnoticed until
    /// the audit: the secret really is in the Keychain, but nothing on
    /// disk points back to it, so the app behaves as if the key does not
    /// exist. `reloadLocked()` re-reads the file (and re-hydrates from
    /// the Keychain) while `lock` is STILL held, so nothing else in this
    /// process can write in the gap between "find out what's on disk"
    /// and "decide what to write" below.
    ///
    /// - Parameter key: The API key to store.
    public func storeKey(_ key: StoredAPIKey) {
        lock.lock()

        // Read-modify-write against the file as it stands RIGHT NOW —
        // see the doc comment above and `reloadLocked()` for why this
        // must happen before the upsert, under the same lock hold.
        reloadLocked()

        // Upsert in the in-memory array using the existing (provider,
        // label) identity so callers see the latest version.
        if let index = keys.firstIndex(where: { $0.provider == key.provider && $0.label == key.label }) {
            keys[index] = key
        } else {
            keys.append(key)
        }

        // Write the secrets to the Keychain first. If that fails we still
        // want to persist the metadata so the user can re-enter the key,
        // but we log the failure rather than swallow it silently.
        let account = Self.keychainAccount(provider: key.provider, label: key.label)
        let secrets = Secrets(
            apiKey: key.apiKey,
            secretKey: key.secretKey,
            accessToken: key.accessToken,
            refreshToken: key.refreshToken
        )
        if secrets.hasAnySecret {
            do {
                try KeychainStore.write(
                    service: keychainService,
                    account: account,
                    value: try JSONEncoder().encode(secrets)
                )
            } catch {
                print("Warning: Could not write API key to Keychain: \(error.localizedDescription)")
            }
        } else {
            // Metadata-only update — make sure any stale secrets are gone.
            try? KeychainStore.delete(service: keychainService, account: account)
        }

        saveKeys()

        // Unlock BEFORE posting — see `didChangeNotification`'s doc
        // comment for why posting while still holding `lock` would risk
        // a deadlock against an observer that reads this same manager.
        lock.unlock()

        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Remove an API key.
    ///
    /// Deletes both the metadata record and the matching Keychain item.
    ///
    /// Reloads from disk first, under the same lock hold, for the same
    /// lost-update reason documented on `storeKey(_:)` — otherwise
    /// removing a key in one long-lived `APIKeyManager` instance could
    /// resurrect a key some OTHER instance had already removed (or never
    /// see one another instance just added), because the rewrite at the
    /// bottom is of the WHOLE file, from this instance's in-memory array.
    ///
    /// - Parameters:
    ///   - provider: The provider to remove the key for.
    ///   - label: Optional label to identify which key (if multiple per provider).
    public func removeKey(provider: APIKeyProvider, label: String? = nil) {
        lock.lock()

        reloadLocked()

        // Capture the labels we are about to remove so we can delete the
        // corresponding Keychain items afterwards.
        let removed = keys.filter { key in
            key.provider == provider && (label == nil || key.label == label)
        }
        keys.removeAll { key in
            key.provider == provider && (label == nil || key.label == label)
        }
        for key in removed {
            let account = Self.keychainAccount(provider: key.provider, label: key.label)
            try? KeychainStore.delete(service: keychainService, account: account)
        }
        saveKeys()

        // Unlock BEFORE posting — see `didChangeNotification`'s doc
        // comment; posting while still holding `lock` risks a deadlock
        // against an observer that reads this same manager.
        lock.unlock()

        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Get the active API key for a provider.
    ///
    /// Reloads from disk first (see `reloadLocked()`) so a long-lived
    /// instance — e.g. `MetadataSettingsTab`'s `@State` manager, which
    /// stays alive for as long as the Settings window is open — tells the
    /// truth even when some OTHER `APIKeyManager` instance saved or
    /// removed a key after this one was created.
    ///
    /// - Parameter provider: The provider.
    /// - Returns: The active key, or nil.
    public func key(for provider: APIKeyProvider) -> StoredAPIKey? {
        lock.lock()
        defer { lock.unlock() }

        reloadLocked()
        return keys.first { $0.provider == provider && $0.isActive }
    }

    /// Get all keys for a provider.
    ///
    /// Reloads from disk first — see `key(for:)` above.
    ///
    /// - Parameter provider: The provider.
    /// - Returns: All keys for the provider.
    public func keys(for provider: APIKeyProvider) -> [StoredAPIKey] {
        lock.lock()
        defer { lock.unlock() }

        reloadLocked()
        return keys.filter { $0.provider == provider }
    }

    /// Get all keys in a category.
    ///
    /// Reloads from disk first — see `key(for:)` above.
    ///
    /// - Parameter category: The category.
    /// - Returns: All keys in the category.
    public func keys(in category: APIKeyCategory) -> [StoredAPIKey] {
        lock.lock()
        defer { lock.unlock() }

        reloadLocked()
        return keys.filter { $0.provider.category == category }
    }

    /// Mark a key's last used date.
    ///
    /// Reloads from disk first for the same lost-update reason as
    /// `storeKey(_:)`/`removeKey(provider:label:)` — a full-file rewrite
    /// of a stale in-memory copy would silently undo another instance's
    /// concurrent change. Unlike those two, this does NOT post
    /// `didChangeNotification`: a last-used timestamp is bookkeeping that
    /// no UI redraws for, not a change to whether a key is saved.
    ///
    /// - Parameter provider: The provider whose key was used.
    public func markUsed(provider: APIKeyProvider) {
        lock.lock()
        defer { lock.unlock() }

        reloadLocked()

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
    /// Reloads from disk first — see `key(for:)` above.
    ///
    /// - Returns: Set of providers with active keys.
    public func configuredProviders() -> Set<APIKeyProvider> {
        lock.lock()
        defer { lock.unlock() }

        reloadLocked()
        return Set(keys.filter { $0.isActive }.map { $0.provider })
    }

    // MARK: - Presence check (never reads a secret)

    /// Whether a key is saved for `provider`, found WITHOUT reading the key.
    ///
    /// It reads the saved-keys list (`api_keys.json`, which holds no
    /// secrets), finds the matching entry, then asks the Keychain only
    /// whether that entry's item EXISTS — see `KeyPresence.swift` for why
    /// the Keychain is asked about existence and nothing more (in short: the
    /// command-line tool is a different program from the app, and reading
    /// secret data the app saved would probably make macOS prompt, or
    /// refuse).
    ///
    /// **Why this is `static`, not an instance method.** Creating an
    /// `APIKeyManager` is itself a secret read: `init` calls
    /// `reloadLocked()`, which calls `hydrate(record:)`, which reads the
    /// secret DATA of every saved key from the Keychain. So an instance
    /// method would already have done the very thing this check exists to
    /// avoid before it ran a single line. As a static, it can be called with
    /// no instance at all — which is how the command-line tool must call it.
    /// Written as `APIKeyManager.hasStoredKey(for: .tmdb)`, it reads exactly
    /// like the #506 plan's `hasStoredKey(for:label:)`.
    ///
    /// **Why it does not touch `reloadLocked()` or `lock`.** It shares no
    /// state with any instance: it reads the file into a local value, looks
    /// up one entry, and asks the Keychain one question. `lock` protects an
    /// instance's `keys` array, which this never reads or writes. And the
    /// file is always replaced whole — `saveKeys()` writes with `.atomic` —
    /// so a read here sees either the complete old file or the complete new
    /// one, never half of each. (Neither `lock` nor anything else
    /// coordinates separate processes; that gap is documented on
    /// `didChangeNotification` and applies here too.)
    ///
    /// **Which entry counts.** With `label` nil it uses the FIRST ACTIVE
    /// entry for `provider`, whatever its label — exactly the entry
    /// `key(for:)` would return — so "present" means "the entry the app's
    /// own lookup would use has a Keychain item behind it", not merely
    /// "some key for this service exists somewhere". With a label, it uses the first active entry with that
    /// exact label (the same exact-match rule `storeKey` uses to decide
    /// what to replace). An inactive entry never counts, because
    /// `key(for:)` skips it too.
    ///
    /// **The three answers**, matching `reloadLocked()`'s two traps:
    /// - no saved-keys file at all → `.missing` (TRAP 1: a missing file
    ///   means no keys);
    /// - a file that exists but can't be read → `.couldNotCheck(
    ///   .indexUnreadable)`, and one that is read but isn't in the current
    ///   format (damaged, the pre-Keychain format, or written by a newer
    ///   version) → `.couldNotCheck(.indexNotRecognised)` (TRAP 2: never
    ///   "missing" — that would tell someone to re-type a key that may be
    ///   perfectly safe);
    /// - otherwise: no matching active entry → `.missing`; an entry whose
    ///   Keychain item has gone → `.missing` (the Keychain gave a definite
    ///   "not found", and the app itself could not use such an entry: it
    ///   would hydrate it with an empty key); an entry whose item exists →
    ///   `.present`; a Keychain error → `.couldNotCheck(.keychainRefused)`.
    ///
    /// **What it never does:** decode a secret field, read a secret from the
    /// Keychain, migrate a pre-Keychain file, or write anything. The legacy
    /// migration lives only in `reloadLocked()`; a check that migrated as a
    /// side effect would write to the Keychain from the command-line tool.
    ///
    /// **What it cannot prove:** that the key is correct, still accepted by
    /// the service, or readable by the program that will use it — only that
    /// the list names it and a Keychain item with the right name exists. A
    /// Keychain item with no list entry pointing at it (left behind by the
    /// lost-update bug described on `reloadLocked()`) counts as missing,
    /// because the app cannot find it either.
    ///
    /// - Parameters:
    ///   - provider: The service to ask about.
    ///   - label: Which saved key, when a service has several; nil means
    ///     "whichever `key(for:)` would use".
    ///   - storageDirectory: The folder holding `api_keys.json`. nil means
    ///     this process's default — see `defaultStorageDirectory()` for why
    ///     a sandboxed app and the command-line tool resolve that to
    ///     different folders.
    ///   - keychainService: The Keychain service the keys were saved under.
    ///     Tests pass a unique one.
    /// - Returns: `.present`, `.missing` or `.couldNotCheck(reason)`. It
    ///   never contains the key, because the key is never read.
    public static func hasStoredKey(
        for provider: APIKeyProvider,
        label: String? = nil,
        storageDirectory: URL? = nil,
        keychainService: String = APIKeyManager.productionKeychainService
    ) -> KeyPresence {
        let indexURL = (storageDirectory ?? defaultStorageDirectory())
            .appendingPathComponent(indexFileName)

        let data: Data
        switch readIndexFile(at: indexURL) {
        case .missing:
            // TRAP 1, as in `reloadLocked()`: no file means no keys.
            return .missing
        case .unreadable:
            // TRAP 2, as in `reloadLocked()`: the file is there but can't be
            // read — unknown, not empty. The error itself isn't passed on;
            // it could only describe the FILE, and the reason code says
            // enough.
            return .couldNotCheck(.indexUnreadable)
        case .contents(let contents):
            data = contents
        }

        // Only the current (v2) shape is accepted. `StorageEnvelope` and
        // `MetadataRecord` have no secret fields, so a successful decode
        // never yields a secret. The pre-Keychain (v1) shape is deliberately
        // NOT decoded here, even though `reloadLocked()` accepts it: that
        // shape HOLDS the secrets in plain text, and accepting it would mean
        // either decoding them or migrating them — the second writes to the
        // Keychain. Both are out of bounds for a check. (If the file IS an
        // old v1 one, its plain-text bytes have been read from disk into
        // `data` by this point — a file read, not a Keychain read — and they
        // are dropped when this function returns; nothing keeps or passes
        // them on.)
        guard let envelope = try? makeIndexDecoder().decode(StorageEnvelope.self, from: data) else {
            // TRAP 2 (continued): read, but not understood.
            return .couldNotCheck(.indexNotRecognised)
        }

        guard let record = envelope.records.first(where: { record in
            record.provider == provider
                && record.isActive
                && (label == nil || record.label == label)
        }) else {
            return .missing
        }

        // The account string comes from the saved record, exactly as
        // `hydrate(record:)` uses it — not recomputed — so this asks about
        // the very item the app would read.
        return KeychainStore.exists(service: keychainService, account: record.keychainAccount)
    }

    // MARK: - Persistence

    /// Stable Keychain account identity for a key.
    ///
    /// We avoid embedding raw user input (the optional `label`) directly,
    /// because trimming/casing differences between sessions would cause
    /// the secret lookup to silently miss. The label is normalised by
    /// substituting an empty marker when absent.
    private static func keychainAccount(
        provider: APIKeyProvider,
        label: String?
    ) -> String {
        let labelComponent = label?.isEmpty == false ? label! : "default"
        return "\(provider.rawValue):\(labelComponent)"
    }

    /// What was found at the saved-keys list's path, before any decoding.
    ///
    /// Shared by `reloadLocked()` and `hasStoredKey(for:label:…)` so the
    /// two can never disagree about which of the "missing" / "can't read"
    /// cases a file falls into — they are the two traps documented on
    /// `reloadLocked()`, and they must mean the same thing in both places.
    private enum IndexFileRead {
        /// Nothing at the path (TRAP 1: no keys).
        case missing
        /// Something is at the path but reading it failed (TRAP 2).
        case unreadable(Error)
        /// The raw bytes, not yet decoded.
        case contents(Data)
    }

    /// Reads the saved-keys list's raw bytes, sorting the result into the
    /// three `IndexFileRead` cases. Static and stateless, so the presence
    /// check can use it without an instance or `lock`.
    private static func readIndexFile(at url: URL) -> IndexFileRead {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        do {
            return .contents(try Data(contentsOf: url))
        } catch {
            return .unreadable(error)
        }
    }

    /// The decoder for the saved-keys list. One definition, so the date
    /// format (ISO 8601, matching `saveKeys()`'s encoder) is set in one
    /// place for both readers.
    private static func makeIndexDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Reads the metadata envelope from disk and hydrates each record's
    /// secrets from the Keychain, REPLACING whatever `keys` currently
    /// holds. Falls back to legacy migration if the file contains an
    /// old-shape `[StoredAPIKey]` array.
    ///
    /// **Why every read AND every write reloads (Codex catch-up review,
    /// finding 2):** several long-lived `APIKeyManager` instances exist
    /// side by side — `MetadataSettingsTab`, `MeedyaDBSettingsTab` and
    /// `CloudStorageView` each hold their own for as long as their screen
    /// is open, and disc-pipeline view models / `TMDBLookupSheet` /
    /// the cloud uploaders each create a fresh one per call. Each
    /// instance's `keys` array is only as current as its last reload.
    /// `saveKeys()` then rewrites the WHOLE file from that array. Put
    /// those two facts together and you get a lost-update race: instance
    /// A stores a TMDB key, instance B (created earlier, still holding
    /// its now-stale copy) then stores an unrelated MeedyaDB key and
    /// overwrites A's record out of existence — not because B did
    /// anything wrong on its own, but because it never found out A's
    /// write had happened. The secret itself survives in the Keychain
    /// (nothing deletes it), but nothing on disk points back to it any
    /// more, so every FRESH `APIKeyManager()` — which is what the disc
    /// view models, `TMDBLookupSheet` and the uploaders create — reports
    /// the key as missing.
    ///
    /// The fix is not to cache less; it is to always act on the CURRENT
    /// file. `storeKey`, `removeKey` and `markUsed` all call this at the
    /// very start of their read-modify-write sequence, and the lookup
    /// methods (`key(for:)`, `keys(for:)`, `keys(in:)`,
    /// `configuredProviders()`) call it before answering, so a long-lived
    /// instance tells the truth even between its own writes. `init` calls
    /// it too — see its call site for why no separate one-time "load"
    /// path is needed.
    ///
    /// MUST be called with `lock` already held. It does not take the lock
    /// itself, precisely so `init` and the methods above can share it
    /// without a second, nested `lock.lock()` — `NSLock` is not
    /// re-entrant, so that would deadlock the very first time any of them
    /// ran.
    ///
    /// - TRAP 1 — a MISSING file means "no keys, start empty": `keys` is
    ///   cleared. This is a deliberate change from this method's previous
    ///   form (`loadKeys()`, before this fix), which returned early WITHOUT
    ///   touching `keys` when the file didn't exist. That was harmless
    ///   for a one-time load at `init` (there was nothing to clear —
    ///   `keys` was freshly set to `[]` two lines above), but it would be
    ///   wrong for a RELOAD: if the file has since been deleted (or this
    ///   is a fresh install another instance hasn't written to yet), an
    ///   instance still holding old in-memory records must drop them,
    ///   not keep insisting they exist.
    /// - TRAP 2 — a file that EXISTS but can't be READ or DECODED is
    ///   treated as "unknown", not "empty": `keys` is left as it was.
    ///   Clearing it here would make a transient disk error (or a file
    ///   another process is mid-write on) look identical to the user
    ///   having removed every key, which is worse than doing nothing.
    ///   This matches this method's behaviour before this fix for this case
    ///   — only the missing-file case (TRAP 1) changed.
    private func reloadLocked() {
        // The file read is shared with `hasStoredKey(for:label:…)` (see
        // `readIndexFile(at:)`), so both sort a file into the same two
        // traps below.
        let data: Data
        switch Self.readIndexFile(at: storageURL) {
        case .missing:
            // TRAP 1: a missing file is authoritative — it means no keys,
            // not "keep trusting whatever this instance last saw".
            keys = []
            return
        case .unreadable(let error):
            // TRAP 2: unreadable — keep the in-memory copy rather than
            // wiping it. No worse than the behaviour before this fix.
            print("Warning: Could not load API keys: \(error.localizedDescription)")
            return
        case .contents(let contents):
            data = contents
        }

        let decoder = Self.makeIndexDecoder()

        // -----------------------------------------------------------------
        // Preferred path: new-shape envelope, secrets in Keychain.
        // -----------------------------------------------------------------
        if let envelope = try? decoder.decode(StorageEnvelope.self, from: data) {
            keys = envelope.records.map { hydrate(record: $0) }
            return
        }

        // -----------------------------------------------------------------
        // Legacy path: pre-#380 array of full `StoredAPIKey` records with
        // secrets on disk. Migrate them into the Keychain and rewrite the
        // file in the new envelope shape. This runs at most once per
        // install — after the next `saveKeys()` the file is in v2 form.
        // -----------------------------------------------------------------
        if let legacy = try? decoder.decode([StoredAPIKey].self, from: data) {
            print("Migrating \(legacy.count) API key(s) from plaintext "
                  + "storage to the Keychain (issue #380).")
            keys = legacy
            // Write each one's secrets into the Keychain. We use the same
            // shape as `storeKey`'s Keychain write, but without taking
            // `lock` ourselves — this method is documented as requiring
            // the lock ALREADY held by its caller (`init`, or one of
            // `storeKey`/`removeKey`/`markUsed`/the lookup methods), so
            // locking again here would be a nested acquisition against a
            // non-re-entrant `NSLock` and would deadlock.
            for key in legacy {
                let account = Self.keychainAccount(
                    provider: key.provider,
                    label: key.label
                )
                let secrets = Secrets(
                    apiKey: key.apiKey,
                    secretKey: key.secretKey,
                    accessToken: key.accessToken,
                    refreshToken: key.refreshToken
                )
                guard secrets.hasAnySecret else { continue }
                do {
                    try KeychainStore.write(
                        service: keychainService,
                        account: account,
                        value: try JSONEncoder().encode(secrets)
                    )
                } catch {
                    print("Warning: Could not migrate API key for "
                          + "\(key.provider.rawValue) to the Keychain: "
                          + "\(error.localizedDescription)")
                }
            }
            // Overwrite the file in v2 shape so a second run takes the
            // preferred path and the plaintext secrets disappear.
            saveKeys()
            return
        }

        // TRAP 2 (continued): neither shape decoded. As with the
        // unreadable-file case above, this is treated as "unknown", not
        // "empty" — `keys` is left exactly as it was (which, at `init`,
        // is still the freshly-set `[]` two lines up in the initialiser,
        // so this reads as "starting empty" there; on a later reload, it
        // means keeping whatever this instance already had rather than
        // wiping it because the file briefly looked wrong).
        print("Warning: API key store at \(storageURL.path) could not be "
              + "decoded in either v1 or v2 format; keeping the keys "
              + "already in memory.")
    }

    /// Combines a metadata record with its Keychain-resident secrets into
    /// a fully-formed `StoredAPIKey` for use by callers.
    private func hydrate(record: MetadataRecord) -> StoredAPIKey {
        let secrets: Secrets?
        do {
            if let blob = try KeychainStore.read(
                service: keychainService,
                account: record.keychainAccount
            ) {
                secrets = try? JSONDecoder().decode(Secrets.self, from: blob)
            } else {
                secrets = nil
            }
        } catch {
            print("Warning: Could not read Keychain item "
                  + "\(record.keychainAccount): \(error.localizedDescription)")
            secrets = nil
        }
        return StoredAPIKey(
            provider: record.provider,
            apiKey: secrets?.apiKey ?? "",
            secretKey: secrets?.secretKey,
            accessToken: secrets?.accessToken,
            refreshToken: secrets?.refreshToken,
            tokenExpiry: record.tokenExpiry,
            label: record.label,
            addedDate: record.addedDate,
            lastUsedDate: record.lastUsedDate,
            isActive: record.isActive
        )
    }

    /// Writes the current in-memory key set to disk as a v2 envelope.
    /// Secrets are NOT written here — `storeKey` already pushed them to
    /// the Keychain. This method only persists the metadata index.
    private func saveKeys() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let records = keys.map { key -> MetadataRecord in
                MetadataRecord(
                    provider: key.provider,
                    label: key.label,
                    tokenExpiry: key.tokenExpiry,
                    addedDate: key.addedDate,
                    lastUsedDate: key.lastUsedDate,
                    isActive: key.isActive,
                    keychainAccount: Self.keychainAccount(
                        provider: key.provider,
                        label: key.label
                    )
                )
            }
            let envelope = StorageEnvelope(
                version: Self.currentStorageVersion,
                records: records
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(envelope)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Warning: Could not save API keys: \(error.localizedDescription)")
        }
    }
}

// MARK: - KeychainStore

/// Minimal wrapper around `SecItem*` for storing per-account secret blobs
/// scoped to a single `kSecAttrService`.
///
/// On platforms without the Security framework (currently any non-Apple
/// build), every operation throws `KeychainError.unsupportedPlatform`.
/// The manager catches that and prints a warning rather than crashing —
/// so a future Linux build will not corrupt user data, just lose any
/// secrets that were not on disk to begin with.
private enum KeychainStore {

    enum KeychainError: Error, CustomStringConvertible {
        case unsupportedPlatform
        case osStatus(OSStatus)

        var description: String {
            switch self {
            case .unsupportedPlatform:
                return "Keychain operations are not available on this platform."
            case .osStatus(let status):
                #if canImport(Security)
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return "Keychain error \(status): \(message)"
                }
                #endif
                return "Keychain error \(status)"
            }
        }
    }

    /// Write (insert-or-replace) a blob into the Keychain for the given
    /// `(service, account)` pair.
    static func write(service: String, account: String, value: Data) throws {
        #if canImport(Security)
        // We always delete-then-add rather than trying `SecItemUpdate`
        // first because the update query needs to omit `kSecValueData`
        // and use a separate attributes dictionary, which is awkward
        // for a single-blob payload. Delete-then-add is idempotent and
        // keeps the implementation simple at the cost of an extra IPC
        // round-trip on overwrite.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: value,
            // `WhenUnlockedThisDeviceOnly` is two protections:
            // (1) accessibility is gated on the device being currently
            //     unlocked (not merely first-unlocked-since-boot), so a
            //     stolen+locked device cannot have these keys read by a
            //     background process; and
            // (2) the `ThisDeviceOnly` qualifier suppresses iCloud
            //     Keychain sync AND excludes the item from Keychain
            //     backups — so an exfiltrated Time Machine archive
            //     cannot leak the user's cloud API tokens, and a
            //     different Mac signed into the same Apple ID does
            //     not inherit them. Per SECURITY.md F-004.
            // Prior to Cycle 16 this was `AfterFirstUnlock`, whose
            // comment claimed iCloud isolation — that claim was wrong;
            // only `ThisDeviceOnly` provides it.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.osStatus(status)
        }
        #else
        throw KeychainError.unsupportedPlatform
        #endif
    }

    /// Read the blob stored at `(service, account)`, or `nil` if no such
    /// item exists.
    static func read(service: String, account: String) throws -> Data? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
        #else
        throw KeychainError.unsupportedPlatform
        #endif
    }

    /// Whether an item exists at `(service, account)`, asked with
    /// ATTRIBUTES ONLY — unlike `read` above, this never requests
    /// `kSecReturnData`, so it never asks for, or receives, the secret.
    ///
    /// Used only by `APIKeyManager.hasStoredKey(for:label:…)`. It hands
    /// straight to `KeychainItemExistence.check` (in `KeyPresence.swift`)
    /// rather than building its own query, so the SFTP, SMTP and API-key
    /// checks all share one attributes-only query, and the one test that
    /// inspects that query covers all three. Returns rather than throws,
    /// because "couldn't check" is an ordinary answer here, not a failure.
    static func exists(service: String, account: String) -> KeyPresence {
        KeychainItemExistence.check(service: service, account: account)
    }

    /// Delete the Keychain item at `(service, account)`. Silently no-ops
    /// if the item does not exist.
    static func delete(service: String, account: String) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
        #else
        throw KeychainError.unsupportedPlatform
        #endif
    }

    /// Remove every item under the given service. Used by tests to clean
    /// up between runs without disturbing other Keychain entries.
    static func deleteAll(service: String) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
        #else
        throw KeychainError.unsupportedPlatform
        #endif
    }
}

// MARK: - Internal test hooks

/// Test-only accessor for clearing all Keychain items owned by a given
/// service. Marked `internal` and surfaced via `@testable import` so
/// tests can set up and tear down a per-test service without polluting
/// the user's real Keychain.
internal enum APIKeyManagerTestSupport {
    /// Remove every Keychain item under `service`. Safe to call when no
    /// items exist.
    static func clearKeychain(service: String) {
        try? KeychainStore.deleteAll(service: service)
    }
}
