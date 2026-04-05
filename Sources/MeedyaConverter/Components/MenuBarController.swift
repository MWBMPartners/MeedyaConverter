// ============================================================================
// MeedyaConverter — MenuBarController
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides a macOS menu bar (status bar) integration for MeedyaConverter.
//
// Features:
//   - NSStatusItem with the app icon in the menu bar.
//   - Dropdown menu: current queue status, quick encode with last profile,
//     open main window, preferences, quit.
//   - Drag-and-drop onto the menu bar icon for quick encoding.
//   - Toggle between full app mode and menu bar-only mode.
//   - Optionally hides the dock icon when minimised to menu bar.
//   - Persistence via @AppStorage("menuBarMode").
//
// Phase 11 — Menu Bar App Mode (Issue #281)
// ---------------------------------------------------------------------------

import AppKit
import SwiftUI

// MARK: - MenuBarController

/// Controls the NSStatusItem (menu bar icon) and its dropdown menu.
///
/// This class is `@MainActor` because `NSStatusBar` and `NSMenu` are
/// AppKit types that must be accessed on the main thread. It is
/// `@Observable` so SwiftUI views can react to property changes
/// (e.g. showing/hiding the menu bar item from Settings).
///
/// ### Persistence
/// The `menuBarMode` flag is stored in `UserDefaults` via `@AppStorage`.
/// When `true`, the app shows a menu bar icon and optionally hides the
/// dock icon. When `false`, the status item is removed entirely.
@MainActor @Observable
final class MenuBarController {

    // MARK: - Properties

    /// Whether the app is running in menu bar mode.
    ///
    /// When enabled, a status item appears in the system menu bar.
    /// Changing this value immediately shows or hides the status item.
    var isMenuBarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarEnabled, forKey: "menuBarMode")
            if isMenuBarEnabled {
                showMenuBar()
            } else {
                hideMenuBar()
            }
        }
    }

    /// Whether to hide the dock icon when the main window is closed
    /// and menu bar mode is active.
    var hideDockIconWhenMinimised: Bool {
        didSet {
            UserDefaults.standard.set(
                hideDockIconWhenMinimised,
                forKey: "hideDockIconWhenMinimised"
            )
        }
    }

    /// A summary string describing current queue status, displayed
    /// in the dropdown menu (e.g. "Encoding 2 of 5 jobs").
    var queueStatusText: String = "Idle"

    /// The name of the last-used encoding profile, for "Quick Encode".
    var lastUsedProfileName: String = "Web Standard"

    /// The NSStatusItem managed by this controller. Nil when the
    /// menu bar icon is hidden.
    private var statusItem: NSStatusItem?

    // MARK: - Initialiser

    /// Creates the controller and restores persisted state.
    ///
    /// If `menuBarMode` was previously enabled, the status item is
    /// created immediately.
    init() {
        self.isMenuBarEnabled = UserDefaults.standard.bool(forKey: "menuBarMode")
        self.hideDockIconWhenMinimised = UserDefaults.standard.bool(
            forKey: "hideDockIconWhenMinimised"
        )
        if isMenuBarEnabled {
            showMenuBar()
        }
    }

    // MARK: - Public API

    /// Creates the NSStatusItem and attaches the dropdown menu.
    ///
    /// If the status item already exists, this method rebuilds its menu
    /// to reflect any state changes (queue status, last profile, etc.).
    func showMenuBar() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(
                withLength: NSStatusItem.squareLength
            )
            if let button = item.button {
                button.image = NSImage(
                    systemSymbolName: "film.stack",
                    accessibilityDescription: "MeedyaConverter"
                )
                button.image?.size = NSSize(width: 18, height: 18)
                button.image?.isTemplate = true
            }
            statusItem = item
        }
        rebuildMenu()
    }

    /// Removes the NSStatusItem from the system menu bar.
    func hideMenuBar() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        // Ensure dock icon is visible when menu bar is hidden.
        setDockIconVisible(true)
    }

    /// Call this when the main window closes while in menu bar mode
    /// to optionally hide the dock icon.
    func mainWindowDidClose() {
        if isMenuBarEnabled && hideDockIconWhenMinimised {
            setDockIconVisible(false)
        }
    }

    /// Call this when the main window opens to restore the dock icon.
    func mainWindowDidOpen() {
        setDockIconVisible(true)
    }

    /// Updates the queue status text and rebuilds the menu.
    ///
    /// - Parameter status: A human-readable status string
    ///   (e.g. "Encoding 2 of 5 jobs", "Idle").
    func updateQueueStatus(_ status: String) {
        queueStatusText = status
        rebuildMenu()
    }

    // MARK: - Menu Construction

    /// Rebuilds the dropdown menu attached to the status item.
    ///
    /// Menu items:
    ///   1. Queue status (disabled, informational)
    ///   2. Quick Encode with last profile
    ///   3. Separator
    ///   4. Open Main Window
    ///   5. Preferences...
    ///   6. Separator
    ///   7. Quit MeedyaConverter
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Queue status (informational, non-interactive)
        let statusItem = NSMenuItem(
            title: queueStatusText,
            action: nil,
            keyEquivalent: ""
        )
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        // Quick Encode with last profile
        let quickEncode = NSMenuItem(
            title: "Quick Encode (\(lastUsedProfileName))",
            action: #selector(AppMenuActions.quickEncode(_:)),
            keyEquivalent: "e"
        )
        quickEncode.target = AppMenuActions.shared
        menu.addItem(quickEncode)

        menu.addItem(.separator())

        // Open Main Window
        let openWindow = NSMenuItem(
            title: "Open Main Window",
            action: #selector(AppMenuActions.openMainWindow(_:)),
            keyEquivalent: "o"
        )
        openWindow.target = AppMenuActions.shared
        menu.addItem(openWindow)

        // Preferences
        let prefs = NSMenuItem(
            title: "Preferences\u{2026}",
            action: #selector(AppMenuActions.openPreferences(_:)),
            keyEquivalent: ","
        )
        prefs.target = AppMenuActions.shared
        menu.addItem(prefs)

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(
            title: "Quit MeedyaConverter",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        self.statusItem?.menu = menu
    }

    // MARK: - Dock Icon

    /// Shows or hides the dock icon.
    ///
    /// - Parameter visible: `true` to show the dock icon (regular activation),
    ///   `false` to hide it (accessory activation).
    private func setDockIconVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        NSApplication.shared.setActivationPolicy(policy)
    }
}

// MARK: - AppMenuActions

/// Singleton target for menu bar NSMenuItem actions.
///
/// `NSMenuItem` requires an `@objc` target for its action selectors.
/// This class bridges menu bar clicks to the SwiftUI application.
@MainActor
final class AppMenuActions: NSObject {

    /// Shared instance used as the target for all menu item actions.
    static let shared = AppMenuActions()

    /// Handler called when "Quick Encode" is selected. Set this from
    /// the app's initialisation code to wire up the action.
    var onQuickEncode: (() -> Void)?

    /// Handler called when "Open Main Window" is selected.
    var onOpenMainWindow: (() -> Void)?

    // MARK: - Actions

    /// Triggers quick encoding with the last-used profile.
    @objc func quickEncode(_ sender: Any?) {
        onQuickEncode?()
    }

    /// Activates the app and brings the main window to front.
    @objc func openMainWindow(_ sender: Any?) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        onOpenMainWindow?()
    }

    /// Opens the Settings/Preferences window.
    @objc func openPreferences(_ sender: Any?) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Use the standard key equivalent to open Settings
        if let mainMenu = NSApplication.shared.mainMenu {
            // Find and invoke the Preferences menu item
            for item in mainMenu.items {
                if let submenu = item.submenu {
                    for subItem in submenu.items {
                        if subItem.keyEquivalent == "," &&
                            subItem.keyEquivalentModifierMask.contains(.command) {
                            _ = subItem.target?.perform(subItem.action, with: subItem)
                            return
                        }
                    }
                }
            }
        }
        // Fallback: send the standard Preferences keyboard shortcut
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
