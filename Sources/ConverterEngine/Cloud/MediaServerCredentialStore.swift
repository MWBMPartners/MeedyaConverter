// ============================================================================
// MeedyaConverter — MediaServerCredentialStore (Issue #506 commit 1)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// SECURITY.md F-013: `MediaServerSettingsView` stored the Plex/Jellyfin/Emby
// API key or token in `@AppStorage("mediaServerAPIKey")` — a plain-text
// setting inside `~/Library/Preferences/…plist`. That file is not encrypted,
// is included in Time Machine and (for Desktop+Documents users) iCloud
// backups, and can be read by any process the user runs
// (`defaults read com.mwbm.MeedyaConverter mediaServerAPIKey`). Anyone with
// this key can talk to the user's Plex/Jellyfin/Emby server as if they were
// the user.
//
// This file is the one place that:
//   1. Moves a legacy plaintext value into the Keychain, once, the first
//      time it finds one (`migrateLegacyKeyIfNeeded`).
//   2. Answers "what's the key right now?" for every caller
//      (`currentKey`) — the Keychain if it has one, the legacy value only
//      while migration keeps failing.
//   3. Is the only place that writes or removes the key going forward
//      (`saveKey`/`removeKey`) — both go straight to the Keychain, so a
//      plaintext value can never be reintroduced by a future edit.
//
// `MediaServerKeyStoring` exists so `MediaServerCredentialStoreTests` can
// substitute a fake whose `storeKey` silently fails to persist — the one
// migration path that matters most (what happens when the Keychain refuses
// the write) cannot be forced against the REAL Keychain on demand.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - MediaServerKeyStoring

/// A narrow view of `APIKeyManager`, covering only what the media-server
/// migration and lookups need. Lets tests substitute a fake — in
/// particular one whose `storeKey` accepts the call but never actually
/// makes the key readable afterwards, to exercise
/// `MigrationOutcome.failedKeptLegacyValue` deterministically.
public protocol MediaServerKeyStoring {
    /// Mirrors `APIKeyManager.key(for:)`: the active key for `provider`,
    /// re-reading the on-disk index and the Keychain first.
    func key(for provider: APIKeyProvider) -> StoredAPIKey?

    /// Mirrors `APIKeyManager.storeKey(_:)`.
    func storeKey(_ key: StoredAPIKey)

    /// Mirrors `APIKeyManager.removeKey(provider:label:)`.
    func removeKey(provider: APIKeyProvider, label: String?)
}

/// `APIKeyManager` already implements every method above with matching
/// signatures (the default argument on its own `removeKey` is simply not
/// reachable through this narrower protocol type — callers going through
/// `MediaServerKeyStoring` always pass `label` explicitly).
extension APIKeyManager: MediaServerKeyStoring {}

// MARK: - MediaServerCredentialStore

/// Moves the media server's API key/token out of the plain-text settings
/// file and into the Keychain, and is the single place every reader and
/// writer of that key should go through afterwards.
public enum MediaServerCredentialStore {

    /// The `UserDefaults` key pre-#506 builds wrote the key to, in plain
    /// text, via `MediaServerSettingsView`'s
    /// `@AppStorage("mediaServerAPIKey")`. Never written by this build —
    /// only ever read, to migrate it away, and removed once that succeeds.
    public static let legacyDefaultsKey = "mediaServerAPIKey"

    /// Label attached to the Keychain-stored record. Mirrors
    /// `MetadataSettingsTab`'s `"TMDB"` label for the same reason: it
    /// reads sensibly in the Settings screen's "Replace"/"Remove" copy,
    /// and gives the migration something specific to write under rather
    /// than an unlabelled record.
    public static let keyLabel = "Media Server"

    // -----------------------------------------------------------------
    // MARK: - Migration outcome
    // -----------------------------------------------------------------

    /// What happened the last time `migrateLegacyKeyIfNeeded` ran.
    public enum MigrationOutcome: Equatable, Sendable {
        /// No legacy value was present in `defaults` — either it was
        /// already migrated on an earlier launch, or this install never
        /// had one.
        case nothingToMigrate
        /// A legacy value was present but blank (or whitespace-only), so
        /// there was nothing worth protecting. It was removed and nothing
        /// was written to the Keychain.
        case removedEmptyLegacyValue
        /// The legacy value was written to the Keychain, read back to
        /// confirm it landed, and then removed from `defaults`.
        case migrated
        /// The legacy value could not be confirmed in the Keychain after
        /// the write, so it was LEFT in `defaults` untouched. `reason` is
        /// plain English, suitable for an Activity Log line.
        case failedKeptLegacyValue(reason: String)
    }

    // -----------------------------------------------------------------
    // MARK: - Migration
    // -----------------------------------------------------------------

    /// Move a legacy plaintext key from `defaults` into the Keychain via
    /// `store`, if one is still present. Safe to call on every launch:
    /// once the legacy value is gone this is a single fast
    /// `UserDefaults` read and nothing else.
    ///
    /// **The five steps below are load-bearing and must not be
    /// reordered** (they follow the #506 plan's §4 exactly):
    ///
    /// 1. Read the old value once. Absent → `.nothingToMigrate`.
    /// 2. Blank (including whitespace-only) → remove it from `defaults`,
    ///    `.removedEmptyLegacyValue`. There is nothing to protect and
    ///    nothing to verify.
    /// 3. Otherwise, store it under `.mediaServer` — **the old value
    ///    always wins**, overwriting whatever the Keychain already holds
    ///    for this provider. That is deliberate, not an oversight: this
    ///    build never WRITES `mediaServerAPIKey` any more (only reads it,
    ///    here, to migrate it away), so a legacy value can only still
    ///    exist because either the app quit between steps 3 and 5 on a
    ///    previous launch, or an older build wrote it more recently than
    ///    whatever the Keychain currently holds.
    /// 4. **Verify by reading the key back out through `store`.** This
    ///    does NOT trust that step 3 "succeeded" — `APIKeyManager
    ///    .storeKey` does not report Keychain failures to its caller at
    ///    all (see that method's doc comment); it only logs a warning.
    ///    A read-back match is the only proof the value actually landed.
    /// 5. Match → remove the legacy value from `defaults`, `.migrated`.
    ///    Mismatch → **leave the legacy value exactly as it was** and
    ///    return `.failedKeptLegacyValue`. Removing it here on a failed
    ///    write would be a silent data loss: the key would then exist
    ///    NOWHERE — not in the Keychain, not in the settings file.
    ///
    /// - Parameters:
    ///   - defaults: Where a legacy plaintext value might still live.
    ///     Production callers pass `.standard`; tests pass an isolated,
    ///     UUID-named suite.
    ///   - store: Where the migrated secret is written and verified.
    ///     Production callers pass a real `APIKeyManager()`; tests can
    ///     pass a fake that fails on demand.
    /// - Returns: What happened, for the caller to log if it failed.
    @discardableResult
    public static func migrateLegacyKeyIfNeeded(
        defaults: UserDefaults,
        store: MediaServerKeyStoring
    ) -> MigrationOutcome {
        // Step 1.
        guard let legacyValue = defaults.string(forKey: legacyDefaultsKey) else {
            return .nothingToMigrate
        }

        // Step 2. Trimming here only decides "is this blank?" — the
        // UNTRIMMED `legacyValue` is what gets stored in step 3, so a real
        // credential's exact bytes are never silently altered.
        let trimmed = legacyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            defaults.removeObject(forKey: legacyDefaultsKey)
            return .removedEmptyLegacyValue
        }

        // Step 3.
        store.storeKey(
            StoredAPIKey(provider: .mediaServer, apiKey: legacyValue, label: keyLabel)
        )

        // Step 4 — the read-back verification. See the doc comment above
        // for why this cannot be skipped or replaced with "assume it
        // worked because storeKey didn't throw" (it never throws).
        guard store.key(for: .mediaServer)?.apiKey == legacyValue else {
            return .failedKeptLegacyValue(
                reason: "The Keychain did not accept the media server key."
            )
        }

        // Step 5 — only reached after a confirmed match.
        defaults.removeObject(forKey: legacyDefaultsKey)
        return .migrated
    }

    // -----------------------------------------------------------------
    // MARK: - Lookup
    // -----------------------------------------------------------------

    /// The key to use right now: the Keychain's, if it has one, otherwise
    /// the legacy settings-file value **only while that value still
    /// exists** — i.e. only while migration keeps failing. A successful
    /// migration removes the legacy value, so from that point on this
    /// always answers from the Keychain alone.
    ///
    /// This is what every reader of the old key (auto-scan, the
    /// connection-test/fetch/scan buttons, `loadMediaServerConfig`)
    /// should call, so the fallback logic lives in exactly one place.
    ///
    /// - Parameters:
    ///   - defaults: Where the legacy fallback value might still live.
    ///   - store: Where the Keychain-held key is read from.
    /// - Returns: The key to use, or `nil` if neither source has one.
    public static func currentKey(
        defaults: UserDefaults,
        store: MediaServerKeyStoring
    ) -> String? {
        if let key = store.key(for: .mediaServer)?.apiKey, !key.isEmpty {
            return key
        }
        return defaults.string(forKey: legacyDefaultsKey)
    }

    // -----------------------------------------------------------------
    // MARK: - Writing
    // -----------------------------------------------------------------

    /// Save a new key. Always goes to the Keychain, and ONLY the
    /// Keychain — this is the one write path the Media Server settings
    /// screen (and any future caller) should use, so a plaintext legacy
    /// value can never be reintroduced.
    ///
    /// - Parameters:
    ///   - apiKey: The key or token to save, exactly as the user typed
    ///     it (already trimmed by the caller — this function does not
    ///     re-trim, so it cannot silently change what gets saved).
    ///   - store: Where to write it.
    public static func saveKey(_ apiKey: String, store: MediaServerKeyStoring) {
        store.storeKey(
            StoredAPIKey(provider: .mediaServer, apiKey: apiKey, label: keyLabel)
        )
    }

    /// Remove the saved key. Removes both the labelled entry this store
    /// writes under, and — defensively — any unlabelled entry, mirroring
    /// `MetadataSettingsTab.removeTMDBKey()`'s reasoning:
    /// `APIKeyManager.key(for:)` returns the FIRST active match for a
    /// provider regardless of label, so a stray unlabelled record (from
    /// some future caller, or a hand-edited index file) would otherwise
    /// keep shadowing a user's "Remove Key" tap.
    ///
    /// - Parameter store: Where to remove it from.
    public static func removeKey(store: MediaServerKeyStoring) {
        store.removeKey(provider: .mediaServer, label: keyLabel)
        store.removeKey(provider: .mediaServer, label: nil)
    }
}
