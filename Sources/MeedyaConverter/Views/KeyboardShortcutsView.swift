// ============================================================================
// MeedyaConverter — KeyboardShortcutsView (Issue #331)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI

// ---------------------------------------------------------------------------
// MARK: - KeyboardShortcutsView
// ---------------------------------------------------------------------------
/// Settings view for viewing and customising keyboard shortcuts.
///
/// Displays a table of all registered actions with their current key
/// bindings. Users can:
/// - Click a shortcut cell to enter "recording" mode and press a new
///   key combination.
/// - See conflict warnings when two actions share the same shortcut.
/// - Reset all shortcuts to factory defaults.
///
/// Phase 14 — User-Assignable Keyboard Shortcuts (Issue #331)
struct KeyboardShortcutsView: View {

    // MARK: - Environment

    @Environment(KeyboardShortcutManager.self) private var shortcutManager

    // MARK: - State

    /// The ID of the binding currently being recorded (awaiting a new
    /// key press from the user). `nil` when not recording.
    @State private var recordingBindingID: UUID?

    /// Whether the reset confirmation alert is showing.
    @State private var showResetConfirmation: Bool = false

    // MARK: - Body

    var body: some View {
        @Bindable var manager = shortcutManager

        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Keyboard Shortcuts")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Click a shortcut to record a new key combination.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // -----------------------------------------------------------------
            // Conflict Warnings
            // -----------------------------------------------------------------
            let conflicts = shortcutManager.detectConflicts()
            if !conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Shortcut Conflicts", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.headline)

                    ForEach(conflicts) { conflict in
                        Text(conflict.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // -----------------------------------------------------------------
            // Shortcut List
            // -----------------------------------------------------------------
            List {
                ForEach(Array(manager.bindings.enumerated()), id: \.element.id) { index, binding in
                    HStack {
                        // Action label.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.label)
                                .fontWeight(.medium)
                            Text(binding.action)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        // Shortcut display / recording button.
                        Button(action: {
                            if recordingBindingID == binding.id {
                                recordingBindingID = nil
                            } else {
                                recordingBindingID = binding.id
                            }
                        }) {
                            if recordingBindingID == binding.id {
                                Text("Press a key...")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.orange.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Text(shortcutDisplayString(for: binding))
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.quaternary)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)

            // -----------------------------------------------------------------
            // Footer Actions
            // -----------------------------------------------------------------
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    showResetConfirmation = true
                }
                .alert(
                    "Reset Keyboard Shortcuts",
                    isPresented: $showResetConfirmation
                ) {
                    Button("Reset", role: .destructive) {
                        shortcutManager.resetToDefaults()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will restore all keyboard shortcuts to their default values.")
                }
            }
        }
        .padding()
    }

    // MARK: - Helpers

    /// Builds a human-readable display string for a shortcut binding.
    ///
    /// Combines modifier symbols (Cmd, Shift, Opt, Ctrl) with the key
    /// name into a compact representation like "⌘1" or "⌘⇧O".
    ///
    /// - Parameter binding: The shortcut binding to display.
    /// - Returns: A formatted shortcut string.
    private func shortcutDisplayString(for binding: ShortcutBinding) -> String {
        var symbols: [String] = []

        for mod in binding.modifiers {
            switch mod.lowercased() {
            case "command", "cmd":
                symbols.append("\u{2318}")   // ⌘
            case "shift":
                symbols.append("\u{21E7}")   // ⇧
            case "option", "alt":
                symbols.append("\u{2325}")   // ⌥
            case "control", "ctrl":
                symbols.append("\u{2303}")   // ⌃
            default:
                break
            }
        }

        let keyDisplay: String
        switch binding.key.lowercased() {
        case "return", "enter":
            keyDisplay = "\u{21A9}"  // ↩
        case "delete", "backspace":
            keyDisplay = "\u{232B}"  // ⌫
        case "tab":
            keyDisplay = "\u{21E5}"  // ⇥
        case "escape":
            keyDisplay = "\u{238B}"  // ⎋
        case "space":
            keyDisplay = "\u{2423}"  // ␣
        case "up":
            keyDisplay = "\u{2191}"  // ↑
        case "down":
            keyDisplay = "\u{2193}"  // ↓
        case "left":
            keyDisplay = "\u{2190}"  // ←
        case "right":
            keyDisplay = "\u{2192}"  // →
        default:
            keyDisplay = binding.key.uppercased()
        }

        return symbols.joined() + keyDisplay
    }
}
