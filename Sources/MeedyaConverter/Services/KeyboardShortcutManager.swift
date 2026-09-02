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

    // MARK: - Key Parsing

    /// The named keys this binding understands, mapped to the SwiftUI
    /// `KeyEquivalent` and the symbol used to display them.
    ///
    /// Kept as one table so the runtime shortcut (`keyEquivalent`) and the
    /// string the user is shown (`displayString`) can never drift apart —
    /// previously the two switch statements lived in different files and had
    /// to be maintained in lockstep by hand.
    private static let namedKeys: [String: (equivalent: KeyEquivalent, symbol: String)] = [
        "return":    (.return,     "\u{21A9}"),   // ↩
        "enter":     (.return,     "\u{21A9}"),
        "delete":    (.delete,     "\u{232B}"),   // ⌫
        "backspace": (.delete,     "\u{232B}"),
        "tab":       (.tab,        "\u{21E5}"),   // ⇥
        "escape":    (.escape,     "\u{238B}"),   // ⎋
        "space":     (.space,      "\u{2423}"),   // ␣
        "up":        (.upArrow,    "\u{2191}"),   // ↑
        "down":      (.downArrow,  "\u{2193}"),   // ↓
        "left":      (.leftArrow,  "\u{2190}"),   // ←
        "right":     (.rightArrow, "\u{2192}"),   // →
    ]

    /// The SwiftUI key for this binding, or `nil` if `key` cannot represent
    /// one.
    ///
    /// **Why this is failable.** `key` is decoded from JSON in `UserDefaults`,
    /// so it is not guaranteed to be a single character — a corrupted or
    /// hand-edited defaults entry can supply `""` or `"ctrl+k"`. The previous
    /// implementation built `KeyEquivalent(Character(binding.key))`
    /// unconditionally, and `Character.init` **traps** on an empty string or
    /// one holding more than a single grapheme cluster. That is a crash on
    /// launch-time shortcut resolution, from data the app itself persisted.
    /// Returning `nil` degrades to the caller's fallback instead.
    var keyEquivalent: KeyEquivalent? {
        if let named = Self.namedKeys[key.lowercased()] {
            return named.equivalent
        }
        guard key.count == 1, let character = key.first else {
            return nil
        }
        return KeyEquivalent(character)
    }

    /// The modifier set for this binding. Unrecognised modifier names are
    /// ignored rather than failing the whole binding.
    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "command", "cmd": result.insert(.command)
            case "shift":          result.insert(.shift)
            case "option", "alt":  result.insert(.option)
            case "control", "ctrl": result.insert(.control)
            default:               break
            }
        }
        return result
    }

    /// Translate a captured key event into a `(key, modifiers)` pair for a new
    /// binding (Issue #331). Pure and AppKit-free — the recorder view decodes
    /// the `NSEvent` into these primitives and passes them here — so the
    /// translation is unit-testable without synthesising real key events.
    ///
    /// Returns `nil` for a keystroke that is not a usable shortcut: no modifier
    /// held (a bare letter would hijack plain typing), or a non-printable,
    /// unmapped key. Modifiers are returned in the canonical
    /// command→shift→option→control order the rest of this type expects.
    ///
    /// - Parameters:
    ///   - characters: `event.charactersIgnoringModifiers`.
    ///   - command/shift/option/control: whether each modifier was held.
    /// - Returns: The `key`/`modifiers` for the binding, or `nil` if unusable.
    static func captureBinding(
        characters: String?,
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool
    ) -> (key: String, modifiers: [String])? {
        guard let first = characters?.first else { return nil }

        let key: String
        switch first {
        case "\r", "\u{3}":       key = "return"
        case "\t":                 key = "tab"
        case " ":                   key = "space"
        case "\u{1b}":             key = "escape"
        case "\u{7f}", "\u{8}":   key = "delete"
        default:
            guard first.isLetter || first.isNumber
                    || first.isPunctuation || first.isSymbol else {
                return nil
            }
            key = String(first).lowercased()
        }

        var modifiers: [String] = []
        if command { modifiers.append("command") }
        if shift   { modifiers.append("shift") }
        if option  { modifiers.append("option") }
        if control { modifiers.append("control") }

        // A modifier-less shortcut would swallow ordinary typing — require one.
        guard !modifiers.isEmpty else { return nil }

        return (key, modifiers)
    }

    /// A human-readable rendering such as `⌘1` or `⌘⇧O`, suitable for menu
    /// titles, help tooltips and the shortcut editor.
    ///
    /// Derived from the same `namedKeys` table as `keyEquivalent`, so what the
    /// user is shown always matches what the app actually binds.
    var displayString: String {
        var symbols: [String] = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "command", "cmd":  symbols.append("\u{2318}")   // ⌘
            case "shift":           symbols.append("\u{21E7}")   // ⇧
            case "option", "alt":   symbols.append("\u{2325}")   // ⌥
            case "control", "ctrl": symbols.append("\u{2303}")   // ⌃
            default:                break
            }
        }
        let keyDisplay = Self.namedKeys[key.lowercased()]?.symbol ?? key.uppercased()
        return symbols.joined() + keyDisplay
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

    /// Returns the human-readable rendering (e.g. `⌘O`) of the shortcut
    /// currently bound to `action`, or `nil` if no usable binding matches.
    ///
    /// Use this for help tooltips and menu titles instead of hard-coding a
    /// key combination in prose — otherwise a user who rebinds an action is
    /// shown a shortcut that no longer works.
    ///
    /// **Returns `nil` for an unusable binding, not a partial rendering.**
    /// A binding whose `key` cannot produce a `KeyEquivalent` (an empty or
    /// multi-character string from hand-edited or corrupted `UserDefaults`)
    /// is rejected by `binding(for:)`, so the caller falls back to its
    /// factory shortcut. If this method still rendered that binding, it would
    /// return something like a bare `⌘` and the tooltip would advertise a
    /// combination the app has not bound — reintroducing exactly the drift
    /// between displayed and bound shortcuts that this API exists to remove.
    /// The two methods must agree on which bindings are usable.
    func displayString(for action: String) -> String? {
        guard let binding = bindings.first(where: { $0.action == action }),
              binding.keyEquivalent != nil else {
            return nil
        }
        return binding.displayString
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
    /// - Returns: A SwiftUI `KeyboardShortcut`, or `nil` when `binding.key`
    ///   cannot represent one (see `ShortcutBinding.keyEquivalent` for why a
    ///   persisted binding may be unusable).
    private func makeKeyboardShortcut(from binding: ShortcutBinding) -> KeyboardShortcut? {
        guard let keyEquivalent = binding.keyEquivalent else {
            return nil
        }
        return KeyboardShortcut(keyEquivalent, modifiers: binding.eventModifiers)
    }
}
