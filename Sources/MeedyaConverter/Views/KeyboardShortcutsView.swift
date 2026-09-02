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

    /// Local key-event monitor, live only while a row is recording (#331).
    @State private var keyMonitor: Any?

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
        // Install a key monitor only while a row is actively recording (#331):
        // the recorder was previously decorative ("Press a key..." with no
        // capture), so a custom shortcut could never be assigned.
        .onChange(of: recordingBindingID) { _, newValue in
            if newValue != nil { installKeyMonitor() } else { removeKeyMonitor() }
        }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Key Recording (#331)

    /// Begin capturing the next key-down and write it into the recording
    /// binding. Escape (no modifiers) cancels; an unusable keystroke is
    /// ignored and left to propagate.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let id = recordingBindingID else { return event }

            let flags = event.modifierFlags
            // Escape with no modifiers cancels recording (keyCode 53).
            if event.keyCode == 53,
               !flags.contains(.command), !flags.contains(.shift),
               !flags.contains(.option), !flags.contains(.control) {
                recordingBindingID = nil
                return nil
            }

            guard let captured = ShortcutBinding.captureBinding(
                characters: event.charactersIgnoringModifiers,
                command: flags.contains(.command),
                shift: flags.contains(.shift),
                option: flags.contains(.option),
                control: flags.contains(.control)
            ), let index = shortcutManager.bindings.firstIndex(where: { $0.id == id }) else {
                // Not a usable shortcut (no modifier / unmapped key) — let it pass.
                return event
            }

            // Mutating a binding triggers the manager's didSet → save().
            shortcutManager.bindings[index].key = captured.key
            shortcutManager.bindings[index].modifiers = captured.modifiers
            recordingBindingID = nil
            return nil   // swallow the captured event
        }
    }

    /// Remove the key monitor if one is installed.
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Helpers

    /// Builds a human-readable display string for a shortcut binding.
    ///
    /// Delegates to `ShortcutBinding.displayString`, which shares its key
    /// table with `ShortcutBinding.keyEquivalent`. This used to be a private
    /// copy of the same switch statement, which meant the symbol shown here
    /// and the key actually bound at runtime were maintained separately and
    /// could drift.
    ///
    /// - Parameter binding: The shortcut binding to display.
    /// - Returns: A formatted shortcut string such as `⌘1` or `⌘⇧O`.
    private func shortcutDisplayString(for binding: ShortcutBinding) -> String {
        binding.displayString
    }
}
