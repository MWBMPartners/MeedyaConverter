// ============================================================================
// MeedyaConverter — macOS SwiftUI application entry point
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// This file defines the `@main` entry point for the MeedyaConverter macOS
// application. It sets up the SwiftUI `App` lifecycle, declares the primary
// window group, Settings window, and Help window, and configures:
//
//   - The main encoding-queue window (ContentView)
//   - The Settings/Preferences window (Cmd+Comma)
//   - The Help window (Help menu)
//   - App-level state injection via @Environment and @Observable
//   - Appearance mode override (system/light/dark)
//   - macOS notification authorisation
//
// ### Architecture
// The app follows the MVVM pattern:
//   - **Models** live in `ConverterEngine` (the SPM library target).
//   - **ViewModels** live in `Sources/MeedyaConverter/ViewModels/`.
//   - **Views** live in `Sources/MeedyaConverter/Views/`.
//   - **Components** (reusable UI pieces) live in
//     `Sources/MeedyaConverter/Components/`.
//
// ### Minimum Deployment Target
// macOS 15.0 (Sequoia) is required for:
//   - Swift 6 runtime (strict concurrency, typed throws)
//   - SwiftUI `Inspector` modifier for side-panel metadata views
//   - `@Observable` macro (Observation framework)
//   - `ContainerRelativeFrame` for adaptive layout
// ---------------------------------------------------------------------------

import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - MeedyaConverterApp
// ---------------------------------------------------------------------------
// The app lives in the `MeedyaConverterCore` LIBRARY target so its internals are
// unit-testable via `@testable import MeedyaConverterCore` (an executable target
// cannot be imported). The `@main` entry point is a one-line `MeedyaConverterApp.main()`
// in the thin `MeedyaConverter` executable target instead — see
// `Sources/MeedyaConverterMain/main.swift`. The struct is therefore `public`
// (so the executable can reach `main()`); its state stays private.
public struct MeedyaConverterApp: App {

    /// Entry point invoked from the thin executable target's `main.swift`.
    public init() {}


    // -----------------------------------------------------------------
    // MARK: - Application State
    // -----------------------------------------------------------------

    /// The shared application view model.
    @State private var appViewModel = AppViewModel()

    /// Parses and validates `meedyaconverter://` URLs that aren't profile
    /// share links (see `handleSchemeURL(_:)`). Held as `@State` — like
    /// `appViewModel` above — so it survives across `body` re-evaluations
    /// rather than being recreated on every one (Issue #356).
    @State private var urlSchemeHandler = URLSchemeHandler()

    /// Controls the menu bar (status item) presence and its dropdown menu.
    /// Held as `@State` for the same reason as `urlSchemeHandler`: an
    /// `NSStatusItem` deallocates and vanishes the moment nothing retains
    /// its owner, so this must live exactly as long as the app does
    /// (Issue #281).
    @State private var menuBarController = MenuBarController()

    /// The single, app-wide colour theme (Issue #336). One shared instance so
    /// that a change made in Settings is observed everywhere: it is injected
    /// into every scene's environment AND applied as the root `.tint`. Before
    /// this, `ThemeSettingsView` owned a private `ThemeManager`, so its accent
    /// colour was persisted to `UserDefaults` and then read by nothing — no
    /// `.tint` existed at the app root, so choosing a theme changed nothing.
    @State private var themeManager = ThemeManager()

    /// Routes notification action-button taps (Issue #361). Held for the app's
    /// lifetime because `UNUserNotificationCenter.delegate` is `weak` — if
    /// nothing retained this, the Start Next / View Log / Retry / Open Output
    /// actions would silently stop working the moment it deallocated.
    @State private var notificationActionHandler = NotificationActionHandler()

    /// Opens app windows (e.g. the Help window) via SwiftUI's native
    /// window-opening action. Replaces a dead `meedyaconverter://help`
    /// URL-scheme round-trip that had no `onOpenURL` handler to catch it
    /// (Issue #481).
    @Environment(\.openWindow) private var openWindow

    /// Opens the Settings window/scene. Used both by the View-menu
    /// navigation commands and by `meedyaconverter://open?view=settings`
    /// — Settings has no `NavigationItem` case of its own, so it can't be
    /// reached by setting `selectedNavItem` the way every other
    /// destination is (Issues #356, #331).
    @Environment(\.openSettings) private var openSettings

    /// User's preferred appearance mode (persisted).
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue

    /// Whether the user has completed the first-launch onboarding wizard.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Mirrors `SettingsView`'s "Show status in menu bar" toggle
    /// (`GeneralSettingsTab.showMenuBarStatus`) — same `UserDefaults` key,
    /// read here so the menu bar item can actually be shown or hidden in
    /// response to it (Issue #281). `@AppStorage` bindings on the same key
    /// stay in sync across scenes automatically, exactly like
    /// `appearanceMode` above already does between this file and
    /// `SettingsView`.
    @AppStorage("showMenuBarStatus") private var showMenuBarStatus = true

    // -----------------------------------------------------------------
    // MARK: - Scene Declaration
    // -----------------------------------------------------------------
    public var body: some Scene {
        // Primary Window Group
        //
        // Given an explicit `id` (Issue #281) so `AppMenuActions.onOpenMainWindow`
        // can reopen it via `openWindow(id:)` after it has been closed
        // outright — `OpenWindowAction` has no zero-argument form that could
        // target the implicit default window group, only `id`/`value`
        // overloads, so a group with no id at all is unreachable once every
        // instance of it is closed.
        WindowGroup(id: "main") {
            ContentView()
                .environment(appViewModel)
                .environment(appViewModel.storeManager)
                .environment(appViewModel.shortcutManager)
                .environment(themeManager)
                .tint(themeManager.accentColor)
                .preferredColorScheme(currentColorScheme)
                .onAppear {
                    requestNotificationPermission()
                    appViewModel.storeManager.listenForTransactions()
                    Task {
                        await appViewModel.storeManager.loadProducts()
                    }
                    // Roadmap #5 — remote feature flags (e.g. `video-upload`).
                    // No-op when intAppsAPI isn't configured; never surfaces
                    // an error to the UI on failure. See
                    // `AppViewModel.refreshRemoteFeatureFlags()`.
                    Task {
                        await appViewModel.refreshRemoteFeatureFlags()
                    }
                    // Menu bar mode (Issue #281): assign the dropdown menu's
                    // action closures once. Visibility itself is driven by
                    // the `.onChange` below, not here, so it reacts live to
                    // the Settings toggle without needing this `onAppear` to
                    // fire again.
                    wireMenuBarActions()
                }
                .sheet(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { if !$0 { hasCompletedOnboarding = true } }
                )) {
                    OnboardingView()
                        .environment(appViewModel)
                        .interactiveDismissDisabled()
                }
                .onOpenURL { url in
                    guard url.scheme?.lowercased() == URLSchemeHandler.scheme else { return }

                    if url.host?.lowercased() == "profile" {
                        handleProfileShareURL(url)
                    } else {
                        handleSchemeURL(url)
                    }
                }
                // Menu bar mode (Issue #281): show/hide the status item in
                // lockstep with the Settings toggle, live — `initial: true`
                // also performs the very first sync, since the controller's
                // own persisted `isMenuBarEnabled` (keyed on "menuBarMode")
                // is a separate, older key that predates this toggle and
                // must not be trusted as the source of truth.
                .onChange(of: showMenuBarStatus, initial: true) { _, isEnabled in
                    menuBarController.isMenuBarEnabled = isEnabled
                }
                // Drive the dropdown from real state (Issue #281): its
                // updateQueueStatus / lastUsedProfileName were never updated,
                // so it showed a static "Idle" / "Web Standard". These push the
                // live queue status and the current profile name.
                .onChange(of: appViewModel.menuBarStatusText, initial: true) { _, status in
                    menuBarController.updateQueueStatus(status)
                }
                .onChange(of: appViewModel.selectedProfile.name, initial: true) { _, name in
                    menuBarController.lastUsedProfileName = name
                }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            // File menu — Import
            CommandGroup(after: .newItem) {
                // Resolve through the shortcut manager like every other
                // command (Issue #331). This was previously hard-coded, so
                // rebinding "Import File" in Settings changed the toolbar
                // button but silently left the File menu on ⌘O — the menu
                // then advertised a shortcut the app no longer honoured
                // there, which is the drift this issue exists to remove.
                // Title kept literal rather than taken from the binding's
                // label: macOS convention wants the trailing ellipsis to
                // signal that a dialog follows, which the editor's short
                // label ("Import File") does not carry. Only the shortcut is
                // resolved from the manager.
                Button("Import Media Files...") {
                    openFilePicker()
                }
                .keyboardShortcut(
                    appViewModel.shortcutManager.binding(for: "file.import")
                        ?? KeyboardShortcut("o", modifiers: .command)
                )
            }

            // App menu — Check for Updates (Phase 9 / Issue #94)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appViewModel.updateChecker.checkForUpdates()
                }
                .disabled(!appViewModel.updateChecker.canCheckForUpdates)
            }

            // View menu — Mini player toggle (Issue #280)
            CommandGroup(after: .toolbar) {
                Button(appViewModel.miniPlayer.isVisible
                       ? "Hide Mini Player"
                       : "Show Mini Player") {
                    appViewModel.miniPlayer.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
            }

            // View menu — Sidebar navigation shortcuts (Issue #331)
            //
            // KeyboardShortcutManager ships five "navigate.*" default
            // bindings (⌘1–⌘5), each rendered as an editable row in
            // Settings → Keyboard Shortcuts, but until now nothing in the
            // app actually triggered them — the rows were decorative.
            // Each item below reads its live binding via
            // `shortcutManager.binding(for:)` (the same source of truth
            // ContentView's toolbar already uses for
            // "file.import"/"encode.start"), falling back to the factory
            // default only when the user's stored binding is unusable,
            // and takes its title from the manager's own label
            // (`shortcutLabel(for:fallback:)`) so a rebound action's menu
            // entry never drifts from the Settings editor.
            //
            // "navigate.settings" has no `NavigationItem` case — Settings
            // is the standard macOS Settings scene declared below, not a
            // sidebar destination — so it opens via the `openSettings`
            // environment action instead of setting `selectedNavItem`.
            CommandGroup(after: .sidebar) {
                Button(shortcutLabel(for: "navigate.source", fallback: "Source File")) {
                    appViewModel.selectedNavItem = .source
                }
                .keyboardShortcut(
                    appViewModel.shortcutManager.binding(for: "navigate.source")
                        ?? KeyboardShortcut("1", modifiers: .command)
                )

                Button(shortcutLabel(for: "navigate.output", fallback: "Output Settings")) {
                    appViewModel.selectedNavItem = .output
                }
                .keyboardShortcut(
                    appViewModel.shortcutManager.binding(for: "navigate.output")
                        ?? KeyboardShortcut("2", modifiers: .command)
                )

                Button(shortcutLabel(for: "navigate.queue", fallback: "Job Queue")) {
                    appViewModel.selectedNavItem = .queue
                }
                .keyboardShortcut(
                    appViewModel.shortcutManager.binding(for: "navigate.queue")
                        ?? KeyboardShortcut("3", modifiers: .command)
                )

                Button(shortcutLabel(for: "navigate.dashboard", fallback: "Dashboard")) {
                    appViewModel.selectedNavItem = .dashboard
                }
                .keyboardShortcut(
                    appViewModel.shortcutManager.binding(for: "navigate.dashboard")
                        ?? KeyboardShortcut("4", modifiers: .command)
                )

                Button(shortcutLabel(for: "navigate.settings", fallback: "Settings")) {
                    openSettings()
                }
                .keyboardShortcut(
                    appViewModel.shortcutManager.binding(for: "navigate.settings")
                        ?? KeyboardShortcut("5", modifiers: .command)
                )
            }

            // Help menu — In-app help
            CommandGroup(replacing: .help) {
                Button("MeedyaConverter Help") {
                    openHelpWindow()
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        // Settings Window (Cmd+Comma)
        Settings {
            SettingsView()
                .environment(appViewModel)
                .environment(appViewModel.storeManager)
                .environment(appViewModel.shortcutManager)
                .environment(themeManager)
                .tint(themeManager.accentColor)
                .preferredColorScheme(currentColorScheme)
                // The same sync as the main window's (Issue #281). It has to
                // exist in BOTH scenes: the main window's `.onChange` only
                // fires while that window exists, so in menu-bar-only use —
                // the very scenario this feature is for — toggling the setting
                // with the main window closed would do nothing. Turning it OFF
                // would leave the status item visible; turning it ON would
                // leave it hidden, with no menu-bar route back to reopen the
                // main window. `initial:` is deliberately omitted here so
                // merely opening Settings does not re-assert the value.
                .onChange(of: showMenuBarStatus) { _, isEnabled in
                    menuBarController.isMenuBarEnabled = isEnabled
                }
        }

        // Help Window
        Window("Help", id: "help") {
            HelpView()
                .environment(themeManager)
                .tint(themeManager.accentColor)
                .preferredColorScheme(currentColorScheme)
        }
        .defaultSize(width: 750, height: 500)
    }

    // -----------------------------------------------------------------
    // MARK: - Appearance
    // -----------------------------------------------------------------

    /// The current colour scheme based on user preference.
    private var currentColorScheme: ColorScheme? {
        AppearanceMode(rawValue: appearanceMode)?.colorScheme
    }

    // -----------------------------------------------------------------
    // MARK: - File Picker
    // -----------------------------------------------------------------

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Import Media Files"
        panel.message = "Select one or more media files to convert."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2Video
        ]

        guard panel.runModal() == .OK else { return }

        Task {
            await appViewModel.importFiles(panel.urls)
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Help Window
    // -----------------------------------------------------------------

    private func openHelpWindow() {
        openWindow(id: "help")
    }

    // -----------------------------------------------------------------
    // MARK: - Profile Share Links
    // -----------------------------------------------------------------

    /// Handles `meedyaconverter://profile/<base64url>` links opened via
    /// the OS (Finder/Mail/Messages, or `open meedyaconverter://...` from
    /// Terminal).
    ///
    /// Decodes with `ProfileSharing.importFromShareLink(_:)` — the exact
    /// counterpart to `ProfileSharing.generateShareLink(_:)`, which mints
    /// these links from `ProfileManagementView`'s "Copy Share Link" action
    /// — so the producer and consumer stay in lockstep. The decoded
    /// profile is added to the shared `EncodingProfileStore` the same way
    /// a JSON file import is (`ProfileManagementView.importProfile`),
    /// reusing the store's own persistence rather than writing a second
    /// import path.
    ///
    /// `onOpenURL` only calls this for URLs whose host is already
    /// "profile" (see the `body` scene's `.onOpenURL` above) — every
    /// other `meedyaconverter://` action (`encode`, `probe`, `open`, and
    /// anything unrecognised) is routed to `handleSchemeURL(_:)` instead
    /// (Issue #356), which surfaces its own errors rather than staying
    /// silent. The scheme/host guard below is kept anyway so this method
    /// stays correct if ever called directly. A profile link that fails
    /// to decode (corrupt/truncated/foreign payload) logs a warning
    /// instead of crashing — profiles are plain encoding configs with no
    /// executable content, but the URL itself is untrusted input, so it
    /// is never imported without a successful decode.
    private func handleProfileShareURL(_ url: URL) {
        guard url.scheme?.lowercased() == "meedyaconverter",
              url.host?.lowercased() == "profile" else {
            return
        }

        guard let profile = ProfileSharing.importFromShareLink(url.absoluteString) else {
            appViewModel.appendLog(.warning, "Could not import profile: the share link is invalid or corrupted.")
            return
        }

        appViewModel.engine.profileStore.addProfile(profile)
        appViewModel.appendLog(.info, "Imported profile from share link: \(profile.name)")
    }

    // -----------------------------------------------------------------
    // MARK: - URL Scheme Actions (Issue #356)
    // -----------------------------------------------------------------

    /// Handles every `meedyaconverter://` URL that isn't a profile-share
    /// link — `encode`, `probe`, `open`, and anything unrecognised.
    ///
    /// `URLSchemeHandler` owns parsing and validation only (see its own
    /// doc comment); this is where the resulting `URLSchemeAction` is
    /// actually carried out against the live `AppViewModel`, following
    /// the same shape as `handleProfileShareURL` above: decode via a
    /// dedicated type, apply the result to the shared view model, and log
    /// a warning — never stay silent — on failure.
    ///
    /// - Parameter url: The incoming `meedyaconverter://` URL.
    private func handleSchemeURL(_ url: URL) {
        guard urlSchemeHandler.handleURL(url) else {
            let message = urlSchemeHandler.lastError?.localizedDescription
                ?? "Could not process link: \(url.absoluteString)"
            appViewModel.appendLog(.warning, message)
            return
        }

        guard let action = urlSchemeHandler.lastAction else { return }
        performURLSchemeAction(action)
    }

    /// Carries out a parsed `URLSchemeAction` against the shared `AppViewModel`.
    ///
    /// - Parameter action: The action decoded by `URLSchemeHandler.handleURL(_:)`.
    private func performURLSchemeAction(_ action: URLSchemeAction) {
        switch action {
        case .encode(let filePath, let profileName):
            let fileURL = URL(fileURLWithPath: filePath)
            Task {
                await appViewModel.importFiles([fileURL])

                // `importFiles` only auto-selects the newly imported file
                // when nothing was already selected (see its own doc
                // comment) — a file the user already has open in the app
                // must not silently steal this encode request, so the
                // just-imported file is selected explicitly here instead
                // of relying on that fallback.
                guard let imported = appViewModel.sourceFiles.last(where: { $0.fileURL == fileURL }) else {
                    // `importFiles` already logged the underlying probe
                    // failure (bad/unsupported media, unreadable file, etc).
                    return
                }
                appViewModel.selectedFile = imported

                if let profileName {
                    if let resolved = appViewModel.engine.profileStore.profile(named: profileName) {
                        appViewModel.selectedProfile = resolved
                    } else {
                        appViewModel.appendLog(.warning, "meedyaconverter://encode: profile \"\(profileName)\" not found — using the current profile.")
                    }
                }

                appViewModel.enqueueSelectedFile()
                await appViewModel.startQueue()
            }

        case .probe(let filePath):
            let fileURL = URL(fileURLWithPath: filePath)
            Task {
                await appViewModel.importFiles([fileURL])
                if let imported = appViewModel.sourceFiles.last(where: { $0.fileURL == fileURL }) {
                    appViewModel.selectedFile = imported
                }
                appViewModel.selectedNavItem = .source
            }

        case .open(let viewName):
            openRequestedView(viewName)
        }
    }

    /// Navigates to the sidebar section named by a
    /// `meedyaconverter://open?view=...` URL, or opens the Settings
    /// window when `viewName` is "settings" — Settings has no
    /// `NavigationItem` case of its own (see the View-menu commands in
    /// `body` above, which resolve the same way).
    ///
    /// - Parameter viewName: The raw `view` query parameter value.
    private func openRequestedView(_ viewName: String) {
        if viewName.lowercased() == "settings" {
            openSettings()
            return
        }

        guard let target = NavigationItem.allCases.first(where: {
            $0.rawValue.lowercased() == viewName.lowercased()
        }) else {
            appViewModel.appendLog(.warning, "meedyaconverter://open: unrecognised view \"\(viewName)\".")
            return
        }

        appViewModel.selectedNavItem = target
    }

    // -----------------------------------------------------------------
    // MARK: - Menu Bar Mode (Issue #281)
    // -----------------------------------------------------------------

    /// Wires `MenuBarController`'s dropdown menu actions to the real
    /// `AppViewModel` instead of leaving them as no-ops.
    ///
    /// `AppMenuActions.shared` is the `@objc` target every `NSMenuItem`
    /// in `MenuBarController`'s menu is bound to (AppKit menu actions
    /// require an `@objc` selector target, which a SwiftUI closure can't
    /// be directly) — assigning these closures is how a menu bar click
    /// reaches the same queue and window every other part of the app
    /// uses, not a disconnected copy of it. Called once from the primary
    /// window's `onAppear`; menu bar *visibility* itself is handled
    /// separately by the `.onChange(of: showMenuBarStatus)` modifier in
    /// `body`, so it can react live without re-running this wiring.
    private func wireMenuBarActions() {
        AppMenuActions.shared.onQuickEncode = {
            guard appViewModel.selectedFile != nil else {
                appViewModel.appendLog(.warning, "Quick Encode: no source file selected — import a file first.")
                return
            }
            if let profile = appViewModel.engine.profileStore.profile(named: menuBarController.lastUsedProfileName) {
                appViewModel.selectedProfile = profile
            }
            appViewModel.enqueueSelectedFile()
            Task { await appViewModel.startQueue() }
        }

        AppMenuActions.shared.onOpenMainWindow = {
            // `AppMenuActions.openMainWindow(_:)` already activates the
            // app and brings any existing window forward, which is
            // enough when the window is merely backgrounded or
            // miniaturised (AppKit keeps a miniaturised window in
            // `NSApp.windows` with `isVisible == true`). It only falls
            // short when the window was closed outright, leaving no
            // titled window behind at all — that's the one case that
            // needs `openWindow` to recreate it.
            // Match the MAIN window specifically. A bare "any visible titled
            // window" test also matches the Settings and Help windows, so a
            // user who closed the main window and then opened Settings from
            // the status menu would find "Open Main Window" merely activating
            // the app and never recreating the window — a partial recurrence
            // of the dead-menu-item bug this issue is about. SwiftUI stamps a
            // `WindowGroup`'s id into `NSWindow.identifier`, so match on that.
            let hasMainWindow = NSApp.windows.contains { window in
                window.isVisible && (window.identifier?.rawValue.hasPrefix("main") ?? false)
            }
            if !hasMainWindow {
                openWindow(id: "main")
            }
        }
    }

    /// The manager's live label for a shortcut action (e.g. "Source File"
    /// for "navigate.source"), used to title the View-menu navigation
    /// commands so they never drift from what Settings → Keyboard
    /// Shortcuts shows for the same action.
    ///
    /// - Parameters:
    ///   - action: The action identifier (e.g. "navigate.source").
    ///   - fallback: Used only if no binding at all exists for `action` —
    ///     normally unreachable, since `KeyboardShortcutManager.defaultBindings`
    ///     always seeds one, but `bindings` is decoded from `UserDefaults`
    ///     JSON and a hand-edited or corrupted store could in principle
    ///     drop an entry.
    private func shortcutLabel(for action: String, fallback: String) -> String {
        appViewModel.shortcutManager.bindings.first(where: { $0.action == action })?.label ?? fallback
    }

    // -----------------------------------------------------------------
    // MARK: - Notifications
    // -----------------------------------------------------------------

    /// Request permission for macOS notifications on first launch.
    private func requestNotificationPermission() {
        let viewModel = appViewModel

        // Wire the action handler (Issue #361): make it the notification-centre
        // delegate and register the categories whose action buttons the
        // encode/queue notifications now stamp. Done here (main actor, at
        // launch) before any notification is posted, as registerCategories'
        // own doc requires.
        UNUserNotificationCenter.current().delegate = notificationActionHandler
        notificationActionHandler.registerCategories()

        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                Task { @MainActor in
                    viewModel.appendLog(.warning, "Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
}
