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
// window group, and will eventually configure:
//
//   - The main encoding-queue window (ContentView)
//   - A Settings window (Preferences, profile management)
//   - A media inspector panel (metadata, stream details, HDR info)
//   - Menu bar commands (File > Open, Encode > Start, Window > Inspector)
//   - App-level state injection via @Environment and @Observable
//   - Sparkle auto-update integration (DIRECT builds only)
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
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - MeedyaConverterApp
// ---------------------------------------------------------------------------
/// The application-level entry point for MeedyaConverter.
///
/// `MeedyaConverterApp` conforms to the SwiftUI `App` protocol, which
/// provides the cross-platform (well, macOS-only in our case) application
/// lifecycle. The `@main` attribute tells the Swift compiler to generate
/// the `main()` entry point that boots the run loop and initialises the
/// app delegate shim behind the scenes.
///
/// ### Scenes
/// SwiftUI apps declare their window hierarchy via the `body` property,
/// which returns one or more `Scene` values:
///
///   - **`WindowGroup`** — The primary window showing the encoding queue
///     and file-drop zone. Multiple windows can be opened (Cmd+N) to
///     manage separate encoding sessions.
///
///   - **`Settings`** (planned) — The Preferences window, accessible via
///     Cmd+Comma. Will host profile management, FFmpeg path configuration,
///     cloud credentials, and update settings.
///
///   - **`Window`** (planned) — A singleton inspector panel toggled from
///     the Window menu, showing detailed metadata for the selected media
///     file.
///
/// ### State Management
/// Top-level application state (the encoding queue, global preferences,
/// the active encoding backend) will be injected into the environment
/// using `@Observable` model objects and the `.environment()` modifier.
/// This keeps the `App` struct itself stateless and testable.
// ---------------------------------------------------------------------------
@main
struct MeedyaConverterApp: App {

    // ---------------------------------------------------------------------
    // MARK: - Scene Declaration
    // ---------------------------------------------------------------------
    /// The application's scene hierarchy.
    ///
    /// Currently declares a single `WindowGroup` with a placeholder
    /// `ContentView`. As the UI is built out, additional scenes will be
    /// added:
    ///
    /// ```swift
    /// var body: some Scene {
    ///     WindowGroup {
    ///         ContentView()
    ///             .environment(encodingQueue)
    ///             .environment(preferencesStore)
    ///     }
    ///
    ///     Settings {
    ///         PreferencesView()
    ///     }
    ///
    ///     Window("Media Inspector", id: "inspector") {
    ///         MediaInspectorView()
    ///     }
    /// }
    /// ```
    // ---------------------------------------------------------------------
    var body: some Scene {
        // -----------------------------------------------------------------
        // Primary Window Group
        // -----------------------------------------------------------------
        // `WindowGroup` creates a multi-window scene. Each window instance
        // gets its own copy of the view hierarchy (and, by extension, its
        // own SwiftUI state graph). The `title` is shown in the title bar
        // and in the Window menu.
        //
        // The trailing closure contains the root view. `ContentView` will
        // be defined in `Sources/MeedyaConverter/Views/ContentView.swift`
        // once the UI scaffolding is in place. For now, a placeholder
        // VStack displays the engine version to confirm that the app
        // launches and the ConverterEngine module links correctly.
        // -----------------------------------------------------------------
        WindowGroup {
            // -------------------------------------------------------------
            // Placeholder Root View
            // -------------------------------------------------------------
            // This inline view will be replaced by a dedicated
            // `ContentView` struct. It serves as a build-verification
            // smoke test: if this text appears in the window, the app
            // launched, SwiftUI rendered, and ConverterEngine linked.
            // -------------------------------------------------------------
            VStack(spacing: 16) {
                // App icon placeholder — will be replaced by the branded
                // asset from Resources/Assets.xcassets.
                Image(systemName: "film.stack")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)

                // App name — uses the large title style for visual
                // hierarchy and accessibility.
                Text("MeedyaConverter")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Engine version — confirms the ConverterEngine module
                // is linked and its version constant is accessible.
                Text("Engine \(ConverterEngine.version)")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                // Build identifier — the full "ConverterEngine/0.1.0"
                // string, useful for diagnostic screenshots.
                Text(ConverterEngine.buildIdentifier)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.quaternary)
            }
            .padding(40)
            .frame(minWidth: 600, minHeight: 400)
        }
    }
}
