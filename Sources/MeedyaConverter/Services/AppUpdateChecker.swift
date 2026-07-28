// ============================================================================
// MeedyaConverter — AppUpdateChecker
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import SwiftUI
import ConverterEngine

#if canImport(Sparkle)
import Sparkle
#endif

// MARK: - UpdateMechanism

/// Which update mechanism the running build is using. Determined at
/// runtime by inspecting the bundle identifier (Direct vs Lite) and
/// whether Sparkle is linked into the binary.
///
/// * `.sparkle` — full Sparkle 2 auto-update via EdDSA-signed appcast
///   (Direct build with Sparkle framework bundled — Sparkle Option B,
///   scheduled for v0.2.0 once issue #416's Cloudflare Worker is up).
/// * `.githubReleases` — Direct build polling
///   `api.github.com/repos/MWBMPartners/MeedyaConverter/releases/latest`
///   to surface a "new version available" banner; downloads happen via
///   the user's browser. Sparkle Option A, the v0.1.0 ship path.
/// * `.appStore` — App Store Lite build; updates are handled natively by
///   the Mac App Store. The in-app UI links the user to the App Store
///   updates page.
enum UpdateMechanism: String, Sendable {
    case sparkle
    case githubReleases
    case appStore
}

// MARK: - AppUpdateChecker

/// Dispatches update checking to the right mechanism for the running build
/// (Sparkle / GitHub Releases poller / App Store) and exposes a unified
/// observable surface for the Settings → Updates tab to render.
///
/// Phase 9 — Update Checker (Issue #94)
/// Phase 16 release prep — Sparkle Option A wired in re #428.
@MainActor
@Observable
final class AppUpdateChecker {

    // MARK: - Mechanism detection

    /// The active update mechanism for the running build. Resolved once
    /// at init.
    let mechanism: UpdateMechanism

    /// `true` when this build's bundle identifier matches the Direct
    /// distribution (vs the App Store Lite variant). Used to decide
    /// whether to fall back to the GitHub poller when Sparkle isn't
    /// bundled, or to defer to the App Store updates UI.
    static var isDirectBuild: Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        // The App Store Lite variant carries the `.Lite` suffix per
        // `feedback_apple_requirements` memory. Anything else is treated
        // as the Direct build. CLI tests (where Bundle.main is the
        // xctest harness) get `true` here — harmless because the
        // mechanism is exercised only inside the GUI.
        return !bundleID.hasSuffix(".Lite")
    }

    // MARK: - Mechanism-specific state

    /// Active when `mechanism == .githubReleases`. Read-only to consumers.
    let githubChecker: GitHubReleaseChecker

    #if canImport(Sparkle)
    private var sparkleUpdater: SPUUpdater?
    private var sparkleDelegate: SparkleDelegate?
    #endif

    // MARK: - intAppsAPI (Roadmap #4 — alpha/beta update channel)

    /// intAppsAPI client for the `.beta`/`.alpha` channel path. `nil`
    /// when intAppsAPI credentials are not configured (Keychain +
    /// environment both empty) — dormant; `performGitHubReleasesCheck`
    /// then always falls back to the GitHub poller regardless of the
    /// selected channel, exactly as if this integration didn't exist.
    private let intAppsClient: IntAppsAPIClient?

    /// Whether intAppsAPI is configured. The Settings UI uses this to
    /// explain which backend a non-stable channel selection will
    /// actually use (intAppsAPI vs the GitHub-releases-list fallback).
    var isIntAppsAPIConfigured: Bool { intAppsClient != nil }

    /// Result of the most recent intAppsAPI update check. `nil` until a
    /// check using that path completes, or whenever the GitHub path was
    /// used instead (`.stable` channel, or intAppsAPI not configured).
    private(set) var intAppsUpdateResult: UpdateCheckResult?

    /// Real error from the most recent intAppsAPI check, if any — mirrors
    /// `GitHubReleaseChecker.lastError`'s "never fabricate, always
    /// surface the honest failure" contract.
    private(set) var intAppsError: String?

    /// Whether an intAppsAPI check is currently in flight.
    private var intAppsIsChecking: Bool = false

    /// When the most recent intAppsAPI check completed (success or
    /// failure). Mirrors `GitHubReleaseChecker.lastCheckedAt`.
    private var intAppsLastCheckedAt: Date?

    /// The user's selected update channel. Read fresh from
    /// `UserDefaults.standard` on every access rather than cached,
    /// mirroring the pattern `MetadataSettingsTab` documents for
    /// `metadataBackend` — this type isn't a `View`, so it can't hold an
    /// `@AppStorage` binding itself, but reads the same key the
    /// `UpdateSettingsTab` Picker writes to (`"updateChannel"`).
    var selectedChannel: UpdateChannel {
        UpdateChannel(rawValue: UserDefaults.standard.string(forKey: "updateChannel") ?? "") ?? .stable
    }

    // MARK: - Unified observable surface

    /// Whether a manual "check for updates" call can be issued.
    var canCheckForUpdates: Bool {
        switch mechanism {
        case .sparkle:
            #if canImport(Sparkle)
            return sparkleUpdater?.canCheckForUpdates ?? false
            #else
            return false
            #endif
        case .githubReleases:
            return !isCheckingForUpdates
        case .appStore:
            return false  // App Store handles updates natively
        }
    }

    /// Whether a check is currently in flight.
    var isCheckingForUpdates: Bool {
        switch mechanism {
        case .sparkle:
            return sparkleIsCheckingForUpdates
        case .githubReleases:
            if selectedChannel != .stable, isIntAppsAPIConfigured {
                return intAppsIsChecking
            }
            return githubChecker.isChecking
        case .appStore:
            return false
        }
    }

    /// Status line for display.
    var statusMessage: String {
        switch mechanism {
        case .sparkle:
            return sparkleStatusMessage
        case .githubReleases:
            // Roadmap #4: once the user opts into a pre-release channel
            // AND intAppsAPI is configured, that path's status replaces
            // the GitHub poller's — the two are never both "the current
            // answer" at once (see `performGitHubReleasesCheck`, which
            // only ever uses one of them per check).
            if selectedChannel != .stable, isIntAppsAPIConfigured {
                return intAppsStatusMessage
            }
            return githubChecker.statusMessage
        case .appStore:
            return "Updates are managed by the Mac App Store"
        }
    }

    /// Status line for the intAppsAPI update-channel path. Mirrors the
    /// shape of `GitHubReleaseChecker.statusMessage` ("Checking...",
    /// "Couldn't check: ...", "Not yet checked", "Update available: ...",
    /// "Up to date...") so the Settings UI doesn't need to branch on
    /// which backend produced the message.
    private var intAppsStatusMessage: String {
        if intAppsIsChecking { return "Checking for updates…" }
        if let intAppsError { return "Couldn't check: \(intAppsError)" }
        guard let result = intAppsUpdateResult else { return "Not yet checked" }
        if result.updateAvailable {
            return "Update available on the \(selectedChannel.displayName) channel"
                + (result.currentVersion.map { ": \($0)" } ?? "")
        }
        return "Up to date on the \(selectedChannel.displayName) channel"
    }

    /// When the most recent check completed (or `nil` if never checked).
    var lastUpdateCheckDate: Date? {
        switch mechanism {
        case .sparkle:
            #if canImport(Sparkle)
            return sparkleUpdater?.lastUpdateCheckDate
            #else
            return nil
            #endif
        case .githubReleases:
            if selectedChannel != .stable, isIntAppsAPIConfigured {
                return intAppsLastCheckedAt
            }
            return githubChecker.lastCheckedAt
        case .appStore:
            return nil
        }
    }

    /// Whether automatic update checking is enabled (Sparkle only — the
    /// GitHub poller and App Store paths do not expose this toggle in
    /// v0.1.0).
    var automaticallyChecksForUpdates: Bool {
        get {
            #if canImport(Sparkle)
            return sparkleUpdater?.automaticallyChecksForUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            sparkleUpdater?.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    // MARK: - Sparkle-specific state

    private var sparkleIsCheckingForUpdates: Bool = false
    private var sparkleStatusMessage: String = "Not checked"

    // MARK: - Init

    init(session: URLSession = .shared) {
        // GitHub checker is constructed unconditionally — cheap, and
        // makes the property non-optional which simplifies consumers.
        self.githubChecker = GitHubReleaseChecker(session: session)

        // Roadmap #4: resolves to `nil` when intAppsAPI isn't configured
        // for this app (Keychain + environment both empty) — the single
        // dormancy gate every intAppsAPI consumer in this codebase uses.
        // A `nil` client here means `performGitHubReleasesCheck` always
        // falls back to the GitHub poller, for every channel.
        self.intAppsClient = IntAppsAPIClient.configured(session: session)

        // Decide mechanism. The Sparkle-vs-GitHub-poller split is a
        // compile-time choice (Sparkle is bundled or not), while the
        // Direct-vs-App-Store split is a runtime bundle-id check. The
        // dispatch below keeps the compiler happy in either configuration
        // — without it the GitHub-poller branch shows as "will never be
        // executed" in Sparkle-bundled builds (and vice versa).
        if !Self.isDirectBuild {
            self.mechanism = .appStore
        } else {
            #if canImport(Sparkle)
            self.mechanism = .sparkle
            #else
            self.mechanism = .githubReleases
            #endif
        }

        // Mechanism-specific setup
        switch mechanism {
        case .sparkle:
            #if canImport(Sparkle)
            setupSparkle()
            #endif
        case .githubReleases:
            // Kick off a non-blocking initial check so the Settings UI
            // shows useful state the first time the user opens it.
            Task { @MainActor [weak self] in
                await self?.performGitHubReleasesCheck(force: false)
            }
        case .appStore:
            break
        }
    }

    // MARK: - Public API

    /// User-initiated "check for updates now" action. Dispatches to the
    /// active mechanism.
    func checkForUpdates() {
        switch mechanism {
        case .sparkle:
            #if canImport(Sparkle)
            guard let sparkleUpdater else {
                sparkleStatusMessage = "Sparkle not configured"
                return
            }
            sparkleIsCheckingForUpdates = true
            sparkleStatusMessage = "Checking for updates..."
            sparkleUpdater.checkForUpdates()
            #endif
        case .githubReleases:
            Task { @MainActor [weak self] in
                await self?.performGitHubReleasesCheck(force: true)
            }
        case .appStore:
            // No-op — the SettingsView surfaces a "Open App Store"
            // button when this mechanism is active.
            break
        }
    }

    // MARK: - Roadmap #4: channel-aware "Direct" check dispatch

    /// Runs the v0.1.0 "Direct" update check for whichever channel is
    /// currently selected. Dispatches to intAppsAPI when the user has
    /// opted into a pre-release channel AND intAppsAPI is configured;
    /// falls back to the GitHub Releases poller otherwise —
    /// UNCONDITIONALLY for the `.stable` channel, so users who never
    /// touch the channel setting get byte-for-byte the same
    /// `githubChecker.check(force:)` call this method always made.
    private func performGitHubReleasesCheck(force: Bool) async {
        let channel = selectedChannel
        if channel != .stable, let intAppsClient {
            await checkViaIntAppsAPI(client: intAppsClient, channel: channel, force: force)
        } else {
            // Either .stable, or a pre-release channel with intAppsAPI
            // unconfigured — either way, the GitHub poller (with
            // pre-release filtering controlled by `channel` per #4) is
            // the answer. Clear any stale intAppsAPI result so the UI
            // doesn't show a leftover verdict from a previous channel.
            intAppsUpdateResult = nil
            intAppsError = nil
            await githubChecker.check(force: force, channel: channel)
        }
    }

    /// Checks for an update via intAppsAPI for the given non-stable
    /// channel. Never throws to its caller — every failure is caught and
    /// surfaced honestly via `intAppsError`, matching
    /// `GitHubReleaseChecker.check`'s "report, don't fabricate" contract.
    private func checkViaIntAppsAPI(client: IntAppsAPIClient, channel: UpdateChannel, force: Bool) async {
        // intAppsAPI is MWBM's own low-traffic internal service (unlike
        // the public GitHub API's 60 req/hour anonymous rate limit), so
        // this only needs a trivial "don't re-check if we already have a
        // result and the caller didn't force it" guard, not a full TTL.
        guard force || intAppsUpdateResult == nil else { return }

        intAppsIsChecking = true
        intAppsError = nil
        defer {
            intAppsIsChecking = false
            intAppsLastCheckedAt = Date()
        }

        do {
            let result = try await client.checkForUpdate(
                appSlug: client.credentials.appSlug,
                channel: channel.rawValue,
                currentVersion: GitHubReleaseChecker.currentBundleVersion
            )
            intAppsUpdateResult = result
        } catch {
            // Never fabricate a result — keep whatever `intAppsUpdateResult`
            // already held (or `nil`, if this is the first attempt) and
            // surface the real failure.
            intAppsError = String(describing: error)
        }
    }

    // MARK: - Sparkle Setup

    #if canImport(Sparkle)
    private func setupSparkle() {
        let delegate = SparkleDelegate(checker: self)
        self.sparkleDelegate = delegate

        do {
            let updater = try SPUUpdater(
                hostBundle: Bundle.main,
                applicationBundle: Bundle.main,
                userDriverDelegate: delegate,
                delegate: delegate
            )
            self.sparkleUpdater = updater
            try updater.start()
            sparkleStatusMessage = "Ready"
        } catch {
            sparkleStatusMessage = "Sparkle setup failed: \(error.localizedDescription)"
        }
    }

    /// Allow the SparkleDelegate to update private status while keeping
    /// the property private to AppUpdateChecker.
    fileprivate func setSparkleStatus(_ message: String, checking: Bool) {
        self.sparkleStatusMessage = message
        self.sparkleIsCheckingForUpdates = checking
    }
    #endif
}

// MARK: - SparkleDelegate

#if canImport(Sparkle)
/// Delegate handling Sparkle update lifecycle events. Bridges Sparkle's
/// nonisolated callbacks into the @MainActor AppUpdateChecker.
@MainActor
final class SparkleDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    weak var checker: AppUpdateChecker?

    init(checker: AppUpdateChecker) {
        self.checker = checker
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        Task { @MainActor in
            checker?.setSparkleStatus("Appcast loaded", checking: false)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let displayVersion = item.displayVersionString
        Task { @MainActor in
            checker?.setSparkleStatus("Update available: \(displayVersion)", checking: false)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            checker?.setSparkleStatus("Up to date", checking: false)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Task { @MainActor in
            checker?.setSparkleStatus("Update check failed", checking: false)
        }
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
#endif
