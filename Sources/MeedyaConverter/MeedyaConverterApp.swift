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
// window group, and configures:
//
//   - The main encoding-queue window (ContentView)
//   - App-level state injection via @Environment and @Observable
//   - Window sizing and default configuration
//
// ### Architecture
// The app follows the MVVM pattern:
//   - **Models** live in `ConverterEngine` (the SPM library target).
//   - **ViewModels** live in `Sources/MeedyaConverter/ViewModels/`.
//   - **Views** live in `Sources/MeedyaConverter/Views/`.
//   - **Components** (reusable UI pieces) live in
//     `Sources/MeedyaConverter/Components/`.
//
// The `App` struct itself is intentionally lightweight — it owns the
// top-level scene declaration and delegates all business logic to the
// engine and view-model layers.
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
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - MeedyaConverterApp
// ---------------------------------------------------------------------------
/// The application-level entry point for MeedyaConverter.
///
/// `MeedyaConverterApp` conforms to the SwiftUI `App` protocol, providing
/// the macOS application lifecycle. The `@main` attribute generates the
/// `main()` entry point that boots the run loop.
///
/// ### Scenes
/// - **`WindowGroup`** — The primary window showing the encoding workflow
///   with sidebar navigation, source import, stream inspection, output
///   settings, job queue, and activity log.
///
/// ### State Management
/// The `AppViewModel` (@Observable) is injected into the environment
/// so all child views can access the shared encoding engine, source
/// files, queue, and UI state.
// ---------------------------------------------------------------------------
@main
struct MeedyaConverterApp: App {

    // -----------------------------------------------------------------
    // MARK: - Application State
    // -----------------------------------------------------------------
    /// The shared application view model, injected into the environment.
    /// Contains the encoding engine, source files, queue, and UI state.
    @State private var appViewModel = AppViewModel()

    // -----------------------------------------------------------------
    // MARK: - Scene Declaration
    // -----------------------------------------------------------------
    var body: some Scene {
        // Primary Window Group
        WindowGroup {
            ContentView()
                .environment(appViewModel)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            // File menu customisation
            CommandGroup(after: .newItem) {
                Button("Import Media Files...") {
                    openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    // -----------------------------------------------------------------
    // MARK: - File Picker
    // -----------------------------------------------------------------
    /// Open a file picker from the menu bar command.
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
}
