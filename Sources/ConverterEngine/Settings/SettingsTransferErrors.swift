// ============================================================================
// MeedyaConverter — Settings export/import errors (Issue #506 commit 5)
// Sources/ConverterEngine/Settings/SettingsTransferErrors.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Everything that can stop a settings export or import, each with a message
// a person can act on.
//
// The rule every import error follows: when one is thrown, NOTHING has been
// changed. The importer checks the whole file before it writes anything
// (`SettingsImporter.prepare`), and when it does write, it does the one step
// that can fail (saving the profiles file) before the steps that cannot
// (`UserDefaults.set`). So every import message ends "Nothing was changed.",
// and that sentence is true. See `SettingsImporter.apply` for the order.
//
// What a message never contains: a setting's VALUE. A message names the
// setting and says what is wrong with it ("contains a password"), because a
// value that is wrong in the way that matters most here would itself be a
// password or token, and error text ends up in logs and screenshots.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsImportError

/// Why a settings file was refused. In every case nothing was changed.
public enum SettingsImportError: LocalizedError, Equatable, Sendable {

    /// The file is bigger than any real settings file could be.
    case fileTooLarge(bytes: Int, limit: Int)

    /// The file could not be read from disk at all (missing, no permission).
    /// `reason` is the system's own description.
    case fileUnreadable(reason: String)

    /// The file is not JSON.
    case notJSON

    /// The file is JSON but not a MeedyaConverter settings file: its
    /// `format` marker is missing or different.
    case notASettingsFile

    /// A newer version of MeedyaConverter wrote the file, in a format this
    /// version cannot read safely.
    case newerFormat(found: Int, supported: Int)

    /// The format version is below 1, which no version ever wrote.
    case unsupportedFormat(found: Int)

    /// The file's outer shape is wrong. `path` says where, for example
    /// `categories.general.settings`.
    case malformed(path: String, reason: String)

    /// A setting this version knows has a value it will not accept: the
    /// wrong type, out of range, not one of the allowed values, an address
    /// with a user name or password in it, a profile claiming to be
    /// built-in, a password where none is allowed, or duplicated IDs.
    /// One bad value refuses the WHOLE file, so a file is never half-imported.
    case invalidValue(category: SettingsCategory, key: String, reason: String)

    /// A "merge" needs to combine the file's list with the one on this Mac,
    /// but this Mac's list could not be read, so the two cannot be combined
    /// without guessing. (A "replace" of that group does not need to read
    /// it.)
    case localValueUnreadable(category: SettingsCategory, key: String)

    /// Saving the profiles file failed when the import was applied. Nothing
    /// else had been written yet, so nothing changed.
    case profileStoreWriteFailed(reason: String)

    /// A check inside the importer found it was about to do something the
    /// registry does not allow (write a setting that is not allowed, or one
    /// outside the ticked groups). This should be impossible; it is checked
    /// anyway, before anything is written, so a bug elsewhere refuses the
    /// import instead of writing the wrong thing.
    case internalSafetyCheckFailed(detail: String)

    public var errorDescription: String? {
        let nothingChanged = " Nothing was changed."
        switch self {
        case let .fileTooLarge(bytes, limit):
            return "This file is too large to be a settings file (\(Self.megabytes(bytes)); the "
                + "largest accepted is \(Self.megabytes(limit)))." + nothingChanged
        case let .fileUnreadable(reason):
            return "The file could not be read: \(reason)." + nothingChanged
        case .notJSON:
            return "This file is not a MeedyaConverter settings file: it is not in JSON format."
                + nothingChanged
        case .notASettingsFile:
            return "This file is not a MeedyaConverter settings file." + nothingChanged
        case let .newerFormat(found, supported):
            // The exact wording from the #506 plan, section 2.
            return "This file was made by a newer version of MeedyaConverter (format \(found)). "
                + "This version reads format \(supported). Update MeedyaConverter, then import again."
                + nothingChanged
        case let .unsupportedFormat(found):
            return "This settings file says it is format \(found), which no version of "
                + "MeedyaConverter writes." + nothingChanged
        case let .malformed(path, reason):
            let place = path.isEmpty ? "the file" : "“\(path)”"
            return "This settings file is damaged: \(place) \(reason)." + nothingChanged
        case let .invalidValue(category, key, reason):
            // A setting is named by its label, with its stored name for
            // anyone matching it against the file; a profile by its name.
            let name = SettingsKeyRegistry.entry(for: key).map { "“\($0.label)” (\(key))" } ?? "“\(key)”"
            return "\(name) in “\(category.displayName)” can't be imported: \(reason). "
                + "Because one value is wrong, the whole file was refused." + nothingChanged
        case let .localValueUnreadable(category, key):
            let label = SettingsKeyRegistry.entry(for: key)?.label ?? key
            return "“\(label)” on this Mac couldn't be read, so the file's entries can't be added "
                + "to it. Choose “Replace” for “\(category.displayName)” to overwrite it instead."
                + nothingChanged
        case let .profileStoreWriteFailed(reason):
            return "Your encoding profiles couldn't be saved: \(reason)." + nothingChanged
        case let .internalSafetyCheckFailed(detail):
            return "The import stopped because of an internal safety check (\(detail)). "
                + "Please report this." + nothingChanged
        }
    }

    /// "10 MB", "1.5 MB" — for the size message only.
    private static func megabytes(_ bytes: Int) -> String {
        let value = Double(bytes) / 1_048_576
        return value == value.rounded()
            ? "\(Int(value)) MB"
            : String(format: "%.1f MB", value)
    }
}

// MARK: - SettingsExportError

/// Why a settings export stopped. When one is thrown, no file was written
/// (the file is written in one atomic step, only after every check passed).
public enum SettingsExportError: LocalizedError, Equatable, Sendable {

    /// No group was ticked, so there is nothing to export.
    case noGroupsChosen

    /// The exporter checks its own output with the importer before writing
    /// it, so it can never produce a file it would itself refuse. This means
    /// that check failed. `reason` is the importer's message.
    case selfCheckFailed(reason: String)

    /// Turning the settings into JSON failed.
    case encodingFailed(reason: String)

    /// Writing the file to disk failed. `reason` is the system's own
    /// description.
    case writeFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .noGroupsChosen:
            return "Choose at least one group of settings to export."
        case let .selfCheckFailed(reason):
            return "The settings file wasn't saved, because MeedyaConverter could not read it back "
                + "safely: \(reason) Please report this."
        case let .encodingFailed(reason):
            return "The settings file couldn't be created: \(reason)."
        case let .writeFailed(reason):
            return "The settings file couldn't be saved: \(reason)."
        }
    }
}
