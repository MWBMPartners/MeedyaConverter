// ============================================================================
// MeedyaConverter — SettingsUndoManager (Issue #330)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - SettingsChange
// ---------------------------------------------------------------------------
/// A type-erased record of a single settings change, used for display
/// in the undo/redo history and for logging purposes.
///
/// Phase 14 — Undo/Redo for Settings (Issue #330)
struct SettingsChange: Identifiable, Sendable {

    /// Unique identifier for this change record.
    let id: UUID

    /// Human-readable description of what changed.
    let description: String

    /// Timestamp when the change was registered.
    let timestamp: Date

    /// Memberwise initializer.
    init(
        id: UUID = UUID(),
        description: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.description = description
        self.timestamp = timestamp
    }
}

// ---------------------------------------------------------------------------
// MARK: - SettingsUndoManager
// ---------------------------------------------------------------------------
/// Wraps `UndoManager` to provide undo/redo support for profile and
/// settings changes in `AppViewModel`.
///
/// Tracks changes to:
/// - Profile selection.
/// - Stream selection and per-stream settings.
/// - Output directory.
/// - Any other `AppViewModel` property registered via `registerUndo`.
///
/// Each change is recorded with a human-readable description and can
/// be undone or redone using the standard Cmd+Z / Cmd+Shift+Z shortcuts,
/// or via the exposed `undo()` and `redo()` methods.
///
/// Usage:
/// ```swift
/// settingsUndoManager.registerUndo(
///     for: \.selectedProfile,
///     on: viewModel,
///     oldValue: oldProfile,
///     newValue: newProfile,
///     description: "Change profile to \(newProfile.name)"
/// )
/// ```
///
/// Phase 14 — Undo/Redo for Settings (Issue #330)
@MainActor
@Observable
final class SettingsUndoManager {

    // MARK: - Properties

    /// The underlying Foundation `UndoManager` that handles the undo stack.
    private let undoManager = UndoManager()

    /// A log of registered changes for display in the UI.
    var changeHistory: [SettingsChange] = []

    // MARK: - Computed Properties

    /// Whether there are actions available to undo.
    var canUndo: Bool {
        undoManager.canUndo
    }

    /// Whether there are actions available to redo.
    var canRedo: Bool {
        undoManager.canRedo
    }

    /// The menu title for the next undo action, if available.
    var undoActionName: String? {
        canUndo ? undoManager.undoActionName : nil
    }

    /// The menu title for the next redo action, if available.
    var redoActionName: String? {
        canRedo ? undoManager.redoActionName : nil
    }

    // MARK: - Registration

    /// Registers an undoable change for a writable key path on `AppViewModel`.
    ///
    /// When the user triggers undo, the `oldValue` is written back to the
    /// key path. A corresponding redo action is registered automatically
    /// to restore the `newValue`.
    ///
    /// - Parameters:
    ///   - keyPath: The key path on `AppViewModel` that was changed.
    ///   - target: The `AppViewModel` instance to modify on undo/redo.
    ///   - oldValue: The value before the change.
    ///   - newValue: The value after the change.
    ///   - description: A human-readable description of the change for
    ///     display in the Edit menu and change history.
    func registerUndo<T>(
        for keyPath: ReferenceWritableKeyPath<AppViewModel, T>,
        on target: AppViewModel,
        oldValue: T,
        newValue: T,
        description: String = "Settings Change"
    ) {
        // Use ReferenceWritableKeyPath so we can mutate the class instance
        // directly without needing a `var` binding.
        //
        // Capture `undoManager` locally to avoid referencing the
        // @MainActor-isolated property from within a @Sendable closure.
        let manager = undoManager
        manager.registerUndo(withTarget: self) { handler in
            // Apply the old value via the reference-writable key path.
            MainActor.assumeIsolated {
                target[keyPath: keyPath] = oldValue

                // Register the redo action (restores the new value).
                manager.registerUndo(withTarget: handler) { _ in
                    MainActor.assumeIsolated {
                        target[keyPath: keyPath] = newValue
                    }
                }
                manager.setActionName(description)
            }
        }

        undoManager.setActionName(description)

        // Record in change history.
        changeHistory.append(
            SettingsChange(description: description)
        )
    }

    // MARK: - Actions

    /// Undoes the most recent settings change.
    ///
    /// Restores the previous value for the last registered change.
    /// This method is safe to call even when `canUndo` is `false`
    /// (it will be a no-op).
    func undo() {
        guard canUndo else { return }
        undoManager.undo()
    }

    /// Redoes the most recently undone settings change.
    ///
    /// Re-applies the value that was removed by the last undo operation.
    /// This method is safe to call even when `canRedo` is `false`
    /// (it will be a no-op).
    func redo() {
        guard canRedo else { return }
        undoManager.redo()
    }

    // MARK: - Reset

    /// Removes all undo and redo actions from the stack.
    ///
    /// Also clears the change history log. Use this when loading a new
    /// project or resetting the application state.
    func removeAllActions() {
        undoManager.removeAllActions()
        changeHistory.removeAll()
    }

    /// Returns the number of items in the change history log.
    var changeCount: Int {
        changeHistory.count
    }
}
