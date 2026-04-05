// ============================================================================
// MeedyaConverter — AppUpdateChecker (Sparkle 2 Integration)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI

#if canImport(Sparkle)
import Sparkle
#endif

// MARK: - AppUpdateChecker

/// Manages application update checking via Sparkle 2 (direct distribution builds)
/// or provides a no-op fallback for App Store builds where Apple handles updates.
///
/// Sparkle 2 is conditionally imported:
/// - **DIRECT builds**: Full Sparkle integration with auto-check, manual check,
///   appcast feed, EdDSA signature verification, and update installation.
/// - **APP_STORE builds**: No Sparkle references — Apple handles updates natively.
///
/// Phase 9 — Update Checker (Issue #94)
@MainActor
@Observable
final class AppUpdateChecker {

    // MARK: - Properties

    /// Whether Sparkle is available in this build.
    var isSparkleAvailable: Bool {
        #if canImport(Sparkle)
        return true
        #else
        return false
        #endif
    }

    /// Whether automatic update checking is enabled.
    var automaticallyChecksForUpdates: Bool {
        get {
            #if canImport(Sparkle)
            return updater?.automaticallyChecksForUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            updater?.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    /// Whether the updater is currently checking for updates.
    var isCheckingForUpdates: Bool = false

    /// The last date updates were checked.
    var lastUpdateCheckDate: Date? {
        #if canImport(Sparkle)
        return updater?.lastUpdateCheckDate
        #else
        return nil
        #endif
    }

    /// Status message for display.
    var statusMessage: String = "Not checked"

    // MARK: - Private

    #if canImport(Sparkle)
    private var updater: SPUUpdater?
    private var delegate: SparkleDelegate?
    #endif

    // MARK: - Initialiser

    init() {
        #if canImport(Sparkle)
        setupSparkle()
        #endif
    }

    // MARK: - Public Methods

    /// Check for updates manually (user-initiated).
    func checkForUpdates() {
        #if canImport(Sparkle)
        guard let updater else {
            statusMessage = "Sparkle not configured"
            return
        }
        isCheckingForUpdates = true
        statusMessage = "Checking for updates..."
        updater.checkForUpdates()
        #else
        statusMessage = "Updates are managed by the Mac App Store"
        #endif
    }

    /// Whether the "Check for Updates" action can be performed.
    var canCheckForUpdates: Bool {
        #if canImport(Sparkle)
        return updater?.canCheckForUpdates ?? false
        #else
        return false
        #endif
    }

    // MARK: - Sparkle Setup

    #if canImport(Sparkle)
    private func setupSparkle() {
        let delegate = SparkleDelegate(checker: self)
        self.delegate = delegate

        do {
            let updater = try SPUUpdater(
                hostBundle: Bundle.main,
                applicationBundle: Bundle.main,
                userDriverDelegate: delegate,
                delegate: delegate
            )
            self.updater = updater
            try updater.start()
            statusMessage = "Ready"
        } catch {
            statusMessage = "Sparkle setup failed: \(error.localizedDescription)"
        }
    }
    #endif
}

// MARK: - SparkleDelegate

#if canImport(Sparkle)
/// Delegate handling Sparkle update lifecycle events.
@MainActor
final class SparkleDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    weak var checker: AppUpdateChecker?

    init(checker: AppUpdateChecker) {
        self.checker = checker
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        Task { @MainActor in
            checker?.statusMessage = "Appcast loaded"
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            checker?.statusMessage = "Update available: \(item.displayVersionString)"
            checker?.isCheckingForUpdates = false
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            checker?.statusMessage = "Up to date"
            checker?.isCheckingForUpdates = false
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Task { @MainActor in
            checker?.statusMessage = "Update check failed"
            checker?.isCheckingForUpdates = false
        }
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
#endif
