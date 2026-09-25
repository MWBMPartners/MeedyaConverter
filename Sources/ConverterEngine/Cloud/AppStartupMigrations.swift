// ============================================================================
// MeedyaConverter — AppStartupMigrations (Issue #506 commit 1)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

/// One-shot, once-per-launch migrations that move something out of a
/// place it should never have been in the first place, called from a
/// single line in `AppViewModel.init`.
///
/// Kept as ONE entry point — rather than scattering individual
/// `migrateXIfNeeded()` calls through `init` — so every migration this
/// build knows about runs in one place, in one order, and its outcomes
/// are visible to whoever calls it (today: `AppViewModel` logs a plain-
/// English Activity Log line when one fails). A future migration (the
/// #506 plan's follow-up on `webhookURL`/`webhookCustomHeaders`,
/// SECURITY.md F-013) adds a case to `Outcome` and a call inside `run`,
/// not a new call site in `AppViewModel`.
public enum AppStartupMigrations {

    /// One migration's result, tagged with which migration produced it —
    /// so a caller logging failures knows which one to name.
    public enum Outcome: Sendable {
        case mediaServerKey(MediaServerCredentialStore.MigrationOutcome)
    }

    /// Run every startup migration this build knows about, once. Safe to
    /// call on every launch — each migration is its own fast no-op once
    /// it has nothing left to do (see
    /// `MediaServerCredentialStore.migrateLegacyKeyIfNeeded`, which this
    /// currently wraps).
    ///
    /// - Parameters:
    ///   - defaults: Where legacy plaintext values might still live.
    ///     Production callers pass `.standard`; tests pass an isolated
    ///     suite.
    ///   - keyManager: Where a migrated secret is written. Production
    ///     callers pass a real `APIKeyManager()`; tests can pass a fake
    ///     conforming to `MediaServerKeyStoring`.
    /// - Returns: Every migration's outcome, in the order they ran.
    @discardableResult
    public static func run(
        defaults: UserDefaults,
        keyManager: MediaServerKeyStoring
    ) -> [Outcome] {
        let mediaServerOutcome = MediaServerCredentialStore.migrateLegacyKeyIfNeeded(
            defaults: defaults,
            store: keyManager
        )
        return [.mediaServerKey(mediaServerOutcome)]
    }
}
