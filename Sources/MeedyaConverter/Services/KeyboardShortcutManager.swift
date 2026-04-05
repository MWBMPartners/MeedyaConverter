// ============================================================================
// MeedyaConverter — KeyboardShortcutManager (Issue #331)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI

// ---------------------------------------------------------------------------
// MARK: - ShortcutBinding
// ---------------------------------------------------------------------------
/// A user-configurable mapping from a named action to a keyboard shortcut.
///
/// Bindings are persisted to `UserDefaults` as JSON so that custom
/// shortcuts survive application restarts. Each binding records the
/// action identifier, the key equivalent string, and the modifier keys.
///
/// Phase 14 — User-Assignable Keyboard Shortcuts (Issue #331)
struct ShortcutBinding: Identifiable, Codable, Sendable, Equatable {

    /// Unique identifier for this binding.
    var id: UUID

    /// The action this shortcut triggers (e.g., "navigate.source",
    /// "encode.start", "file.import").
    var action: String

    /// Human-readable label for the action.
    var label: String

    /// The key equivalent string (e.g., "1", "o", "return").
    var key: String

    /// Modifier key names (e.g., ["command"], ["command", "shift"]).
    var modifiers: [String]

    /// Memberwise initializer.
    init(
        id: UUID = UUID(),
        action: String,
        label: String,
        key: String,
        modifiers: [String] = ["command"]
    ) {
        self.id = id
        self.action = action
        self.label = label
        self.key = key
        self.modifiers = modifiers
    }
}

// ---------------------------------------------------------------------------
// MARK: - ShortcutConflict
// ---------------------------------------------------------------------------
/// Describes a conflict between two shortcut bindings that share the
/// same key combination.
///
/// Phase 14 — User-Assignable Keyboard Shortcuts (Issue #331)
struct ShortcutConflict: Identifiable, Sendable {

    /// Unique identifier for this conflict report.
    let id = UUID()

    /// The first conflicting binding.
    let binding1: ShortcutBinding

    /// The second conflicting binding.
    let binding2: ShortcutBinding

    /// Human-readable description of the conflict.
    var description: String {
        "\"\(binding1.label)\" and \"\(binding2.label)\" share the same shortcut"
    }
}

// ---------------------------------------------------------------------------
// MARK: - KeyboardShortcutManager
// ---------------------------------------------------------------------------
/// Manages user-assignable keyboard shortcuts with persistence,
/// conflict detection, and SwiftUI `KeyboardShortcut` conversion.
///
/// Default shortcuts:
/// - Cmd+1 through Cmd+5: Navigate to sidebar items.
/// - Cmd+Return: Start encoding.
/// - Cmd+O: Import file.
///
/// Shortcuts are persisted as JSON in `UserDefaults` under the key
/// `"keyboard_shortcuts"`. Users can reassign shortcuts, and the
/// manager detects conflicts where two actions share the same
/// key combination.
///
/// Phase 14 — User-Assignable Keyboard Shortcuts (Issue #331)
@MainActor
@Observable
final class KeyboardShortcutManager {

    // MARK: - Constants

    /// UserDefaults key for persisted shortcut bindings.
    private static let storageKey = "keyboard_shortcuts"

    // MARK: - Properties

    /// The current set of shortcut bindings.
    ///
    /// Modifying this array automatically persists the changes to
    /// UserDefaults.
    var bindings: [ShortcutBinding] {
        didSet { save() }
    }

    // MARK: - Initialization

    /// Creates a keyboard shortcut manager, loading saved bindings
    /// from UserDefaults or falling back to defaults.
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([ShortcutBinding].self, from: data) {
            self.bindings = saved
        } else {
            self.bindings = Self.defaultBindings
        }
    }

    // MARK: - Default Bindings

    /// The factory-default shortcut bindings.
    static let defaultBindings: [ShortcutBinding] = [
        ShortcutBinding(
            action: "navigate.source",
            label: "Source File",
            key: "1",
            modifiers: ["command"]
        ),
        ShortcutBinding(
            action: "navigate.output",
            label: "Output Settings",
            key: "2",
            modifiers: ["command"]
        ),
        ShortcutBinding(
            action: "navigate.queue",
            label: "Job Queue",
            key: "3",
            modifiers: ["command"]
        ),
        ShortcutBinding(
            action: "navigate.dashboard",
            label: "Dashboard",
            key: "4",
            modifiers: ["command"]
        ),
        ShortcutBinding(
            action: "navigate.settings",
            label: "Settings",
            key: "5",
            modifiers: ["command"]
        ),
        ShortcutBinding(
            action: "encode.start",
            label: "Start Encoding",
            key: "return",
            modifiers: ["command"]
        ),
        ShortcutBinding(
            action: "file.import",
            label: "Import File",
            key: "o",
            modifiers: ["command"]
        ),
    ]

    // MARK: - Lookup

    /// Returns the SwiftUI `KeyboardShortcut` for the given action, if
    /// a binding exists.
    ///
    /// Converts the string-based key and modifier representation into a
    /// SwiftUI `KeyboardShortcut` suitable for use with the `.keyboardShortcut()`
    /// modifier.
    ///
    /// - Parameter action: The action identifier (e.g., "encode.start").
    /// - Returns: A `KeyboardShortcut`, or `nil` if no binding matches.
    func binding(for action: String) -> KeyboardShortcut? {
        guard let shortcut = bindings.first(where: { $0.action == action }) else {
            return nil
        }
        return makeKeyboardShortcut(from: shortcut)
    }

    // MARK: - Conflict Detection

    /// Detects conflicting shortcut bindings where two or more actions
    /// share the same key combination.
    ///
    /// - Returns: An array of `ShortcutConflict` describing each conflict.
    func detectConflicts() -> [ShortcutConflict] {
        var conflicts: [ShortcutConflict] = []
        let count = bindings.count

        for i in 0..<count {
            for j in (i + 1)..<count {
                let a = bindings[i]
                let b = bindings[j]

                if a.key.lowercased() == b.key.lowercased()
                    && Set(a.modifiers) == Set(b.modifiers) {
                    conflicts.append(ShortcutConflict(binding1: a, binding2: b))
                }
            }
        }

        return conflicts
    }

    // MARK: - Reset

    /// Resets all bindings to their factory defaults.
    func resetToDefaults() {
        bindings = Self.defaultBindings
    }

    // MARK: - Persistence

    /// Saves the current bindings to UserDefaults.
    private func save() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Conversion Helpers

    /// Converts a `ShortcutBinding` into a SwiftUI `KeyboardShortcut`.
    ///
    /// Maps string-based key names ("return", "delete", letter keys) to
    /// `KeyEquivalent` values and modifier name strings to
    /// `EventModifiers`.
    ///
    /// - Parameter binding: The binding to convert.
    /// - Returns: A SwiftUI `KeyboardShortcut`.
    private func makeKeyboardShortcut(from binding: ShortcutBinding) -> KeyboardShortcut {
        let keyEquivalent: KeyEquivalent
        switch binding.key.lowercased() {
        case "return", "enter":
            keyEquivalent = .return
        case "delete", "backspace":
            keyEquivalent = .delete
        case "tab":
            keyEquivalent = .tab
        case "escape":
            keyEquivalent = .escape
        case "space":
            keyEquivalent = .space
        case "up":
            keyEquivalent = .upArrow
        case "down":
            keyEquivalent = .downArrow
        case "left":
            keyEquivalent = .leftArrow
        case "right":
            keyEquivalent = .rightArrow
        default:
            keyEquivalent = KeyEquivalent(Character(binding.key))
        }

        var eventModifiers: EventModifiers = []
        for mod in binding.modifiers {
            switch mod.lowercased() {
            case "command", "cmd":
                eventModifiers.insert(.command)
            case "shift":
                eventModifiers.insert(.shift)
            case "option", "alt":
                eventModifiers.insert(.option)
            case "control", "ctrl":
                eventModifiers.insert(.control)
            default:
                break
            }
        }

        return KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }
}
