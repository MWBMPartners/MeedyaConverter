// ============================================================================
// MeedyaConverter — StageManagerOptimizer (Issue #358)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import AppKit
import SwiftUI

// MARK: - StageManagerOptimizer

/// Detects and optimises window behaviour for macOS Stage Manager.
///
/// Stage Manager groups application windows into "sets" on the left side
/// of the screen. This class detects whether Stage Manager is active,
/// adjusts window sizing constraints, and configures collection behaviour
/// so that auxiliary panels (mini player, progress HUD) group correctly
/// with the main window rather than appearing as separate stage entries.
///
/// Phase 11 — Stage Manager Window Optimization (Issue #358)
@MainActor @Observable
final class StageManagerOptimizer {

    // MARK: - Properties

    /// Whether Stage Manager is currently enabled in System Settings.
    ///
    /// This value is read from `com.apple.WindowManager` user defaults
    /// and refreshed each time `detectStageManager()` is called.
    private(set) var isStageManagerActive: Bool = false

    /// The preferred minimum window size under Stage Manager.
    ///
    /// Stage Manager constrains window placement, so slightly smaller
    /// minimums help the system lay out windows without clipping.
    private let stageManagerMinSize = NSSize(width: 720, height: 480)

    /// The standard minimum window size when Stage Manager is off.
    private let standardMinSize = NSSize(width: 900, height: 600)

    // MARK: - Initialisation

    /// Creates the optimiser and performs an initial Stage Manager check.
    init() {
        detectStageManager()
    }

    // MARK: - Detection

    /// Reads the `com.apple.WindowManager` defaults domain to determine
    /// whether Stage Manager is enabled.
    ///
    /// The `GloballyEnabled` key is `true` when the user has turned on
    /// Stage Manager in System Settings > Desktop & Dock.
    func detectStageManager() {
        let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        isStageManagerActive = defaults?.bool(forKey: "GloballyEnabled") ?? false
    }

    // MARK: - Window Optimisation

    /// Adjusts the given window's style mask, size constraints, and
    /// collection behaviour for optimal Stage Manager compatibility.
    ///
    /// When Stage Manager is active:
    /// - The minimum window size is reduced so the system can tile
    ///   windows comfortably in the available stage area.
    /// - Full-size content view is enabled for a more immersive look.
    /// - The window is marked as `.primary` to anchor the stage group.
    ///
    /// When Stage Manager is inactive, standard sizing is restored.
    ///
    /// - Parameter window: The `NSWindow` to optimise.
    func optimizeWindowBehavior(for window: NSWindow? = nil) {
        detectStageManager()

        guard let window = window ?? NSApplication.shared.mainWindow else {
            return
        }

        if isStageManagerActive {
            // Reduce minimum size for Stage Manager tiling
            window.minSize = stageManagerMinSize

            // Enable full-size content for edge-to-edge appearance
            window.styleMask.insert(.fullSizeContentView)

            // Mark as primary so auxiliary windows group with this one
            window.collectionBehavior.insert(.primary)
            window.collectionBehavior.remove(.auxiliary)
            window.collectionBehavior.remove(.transient)
        } else {
            // Restore standard sizing
            window.minSize = standardMinSize

            // Standard collection behaviour
            window.collectionBehavior.remove(.primary)
        }
    }

    /// Configures an auxiliary panel (e.g. mini player, progress overlay)
    /// to group with the main application window in Stage Manager.
    ///
    /// Auxiliary windows appear alongside the main window in the same
    /// stage group rather than creating a separate stage entry.
    ///
    /// - Parameter window: The auxiliary `NSWindow` to configure.
    func configureAuxiliaryWindow(_ window: NSWindow) {
        detectStageManager()

        if isStageManagerActive {
            window.collectionBehavior.insert(.auxiliary)
            window.collectionBehavior.remove(.primary)
            window.collectionBehavior.remove(.transient)
        }
    }

    /// Configures a floating panel (e.g. progress HUD, inspector) with
    /// the appropriate window level and Stage Manager behaviour.
    ///
    /// Floating panels stay above the main window and group with it
    /// in Stage Manager. They use the `.floating` window level so
    /// they remain visible when the main window is focused.
    ///
    /// - Parameters:
    ///   - window: The floating `NSWindow` to configure.
    ///   - level: The desired window level (default `.floating`).
    func configureFloatingPanel(
        _ window: NSWindow,
        level: NSWindow.Level = .floating
    ) {
        window.level = level
        window.styleMask.insert(.fullSizeContentView)

        if isStageManagerActive {
            // Group with the main window in Stage Manager
            window.collectionBehavior.insert(.auxiliary)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.collectionBehavior.remove(.primary)
            window.collectionBehavior.remove(.transient)
        } else {
            // Standard floating behaviour
            window.collectionBehavior.insert(.transient)
        }
    }
}
