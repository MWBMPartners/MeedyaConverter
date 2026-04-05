// ============================================================================
// MeedyaConverter — AppShortcuts (Issue #282)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import AppIntents

// MARK: - MeedyaConverterShortcuts

/// Registers MeedyaConverter's App Shortcuts with the system.
///
/// These shortcuts appear automatically in Shortcuts.app, Spotlight, and Siri
/// without the user needing to manually build them. Each shortcut maps to an
/// `AppIntent` with predefined parameter bindings and trigger phrases.
///
/// Phase 10 / Issue #282
@available(macOS 15.0, *)
struct MeedyaConverterShortcuts: AppShortcutsProvider {

    // MARK: - Shortcuts

    /// The set of shortcuts this app provides to the system.
    ///
    /// Each `AppShortcut` defines:
    /// - The intent to execute (with default parameter values where appropriate).
    /// - One or more natural-language phrases users can say or type to trigger it.
    /// - A short title for display in Shortcuts.app and Spotlight.
    static var appShortcuts: [AppShortcut] {
        // "Convert video to MP4" shortcut.
        //
        // Prompts the user for an input file and converts it using the
        // "Web Standard" profile with MP4 output by default.
        AppShortcut(
            intent: ConvertMediaIntent(),
            phrases: [
                "Convert this video with \(.applicationName)",
                "Convert video to MP4 with \(.applicationName)",
                "Transcode media with \(.applicationName)"
            ],
            shortTitle: "Convert Media File",
            systemImageName: "film"
        )

        // "Analyze media file" shortcut.
        //
        // Probes the file and returns a text summary of streams, codecs,
        // resolution, duration, and HDR status.
        AppShortcut(
            intent: ProbeMediaIntent(),
            phrases: [
                "Analyze media file with \(.applicationName)",
                "Get media info with \(.applicationName)",
                "Probe video with \(.applicationName)"
            ],
            shortTitle: "Analyze Media File",
            systemImageName: "magnifyingglass"
        )
    }
}
