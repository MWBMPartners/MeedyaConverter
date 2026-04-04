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
@main
struct MeedyaConverterApp: App {

    // -----------------------------------------------------------------
    // MARK: - Application State
    // -----------------------------------------------------------------

    /// The shared application view model.
    @State private var appViewModel = AppViewModel()

    /// User's preferred appearance mode (persisted).
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue

    // -----------------------------------------------------------------
    // MARK: - Scene Declaration
    // -----------------------------------------------------------------
    var body: some Scene {
        // Primary Window Group
        WindowGroup {
            ContentView()
                .environment(appViewModel)
                .preferredColorScheme(currentColorScheme)
                .onAppear {
                    requestNotificationPermission()
                }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            // File menu — Import
            CommandGroup(after: .newItem) {
                Button("Import Media Files...") {
                    openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
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
                .preferredColorScheme(currentColorScheme)
        }

        // Help Window
        Window("Help", id: "help") {
            HelpView()
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
        if let url = URL(string: "meedyaconverter://help") {
            NSWorkspace.shared.open(url)
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Notifications
    // -----------------------------------------------------------------

    /// Request permission for macOS notifications on first launch.
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                appViewModel.appendLog(.warning, "Notification permission error: \(error.localizedDescription)")
            }
        }
    }
}
