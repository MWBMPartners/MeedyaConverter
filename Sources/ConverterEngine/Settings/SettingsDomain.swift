// ============================================================================
// MeedyaConverter — SettingsDomain (Issue #506 commit 5)
// Sources/ConverterEngine/Settings/SettingsDomain.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Names the settings file ("UserDefaults domain") that a settings export
// reads from or a settings import writes to, and is the ONLY place the
// settings export/import engine writes to UserDefaults.
//
// Why the caller must always say which domain (never `.standard` by
// default). The app and the command-line tool are different programs, and
// `UserDefaults.standard` means a different settings file in each:
//   - in the app, it is the app's own settings;
//   - in `meedya-convert`, it is the command-line tool's own, EMPTY,
//     settings. An export from there would quietly contain nothing, and an
//     import would write settings the app never reads.
// So the command-line tool must name the app's domain explicitly (the #506
// plan, section 6, uses `AppInfo.Application.directBundleId`), and tests
// pass a throwaway suite. Neither the exporter nor the importer has a
// default for this on purpose.
//
// Why reads come from `persistentDomain(forName:)`. That returns only what
// is stored in this one settings file. Reading through `defaults.object(
// forKey:)` instead would also see macOS-wide settings (the global domain),
// command-line arguments and registered defaults, and any of those could
// leak into an exported file as if the person had chosen them.
//
// Why all writes go through `write` and `remove` below. The settings-key
// tripwire (`SettingsKeyCoverageTests`) reads the source code for every
// `forKey:` and demands to know which setting each one is. The engine
// writes keys it takes from `SettingsKeyRegistry` at run time, so its call
// sites name a variable, not a setting. Keeping those call sites in this one
// file means the tripwire map needs exactly one entry for them
// (`SettingsKeyScanMap`, "SettingsDomain.swift|key"), which says so.
//
// What this cannot do: it does not coordinate with another program writing
// the same settings file at the same moment. The app keeps some settings in
// memory and writes them back later (the plan, section 5), which is why the
// later command-line commit refuses to import while the app is open.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsDomain

/// The settings file (a `UserDefaults` domain) an export reads or an import
/// writes.
///
/// `@unchecked Sendable`: `UserDefaults` is not marked `Sendable` in this
/// SDK, but Apple documents it as safe to use from any thread, and this type
/// adds no state of its own. The two stored properties never change.
public struct SettingsDomain: @unchecked Sendable {

    /// The object used to write. Its domain must be `name`.
    public let defaults: UserDefaults

    /// The domain's name: the app's bundle identifier for the app's own
    /// settings, or a suite name. Used to read a snapshot of exactly this
    /// domain (see the file overview for why).
    public let name: String

    /// - Parameters:
    ///   - defaults: Where writes go. For the app, `.standard`; for the
    ///     command-line tool, `UserDefaults(suiteName:)` with the app's
    ///     bundle identifier; for tests, a throwaway suite.
    ///   - name: The name of the domain `defaults` writes to. It must match,
    ///     or the engine would compare the file with one settings file and
    ///     write to another. Nothing here can check that they match.
    public init(defaults: UserDefaults, name: String) {
        self.defaults = defaults
        self.name = name
    }

    // MARK: Reading

    /// Everything stored in this domain itself, and nothing from the global
    /// domain, arguments or registered defaults. Empty when nothing is
    /// stored.
    func snapshot() -> [String: Any] {
        defaults.persistentDomain(forName: name) ?? [:]
    }

    // MARK: Writing (the only two write paths in the settings engine)

    /// Stores `value` under `key`. `UserDefaults.set` cannot fail or throw,
    /// which is why the importer does every write that CAN fail (the profile
    /// file) first. See `SettingsImporter.apply`.
    func write(_ value: SettingsWritableValue, key: String) {
        defaults.set(value.propertyListValue, forKey: key)
    }

    /// Removes `key`, so the app goes back to that setting's default. Used
    /// only by "Replace" imports, inside the groups the person ticked.
    func remove(key: String) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - SettingsWritableValue

/// A checked value ready to be stored, in one of the five property-list
/// shapes the settings file uses. Only values that have passed the
/// importer's checks are ever turned into one of these.
enum SettingsWritableValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)

    /// The value in the form `UserDefaults.set(_:forKey:)` stores with the
    /// right type (a Swift `Bool` becomes a true/false entry, an `Int` a
    /// whole number, and so on).
    var propertyListValue: Any {
        switch self {
        case .bool(let value):   return value
        case .int(let value):    return value
        case .double(let value): return value
        case .string(let value): return value
        case .data(let value):   return value
        }
    }
}
