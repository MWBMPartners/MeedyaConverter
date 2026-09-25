// ============================================================================
// MeedyaConverter — Settings section handlers (Issue #506 commit 5)
// Sources/ConverterEngine/Settings/SettingsSectionHandlers.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// One handler per group ("category") of a settings file. A handler builds
// its group's part of the file on export, and checks that part on import.
// Two kinds exist today:
//   - `SettingsDefaultsSectionHandler`: General, Encoding, Connections and
//     This Mac only. Payload `{ "settings": { key: value, … } }`, built from
//     and checked against `SettingsKeyRegistry`.
//   - `SettingsProfilesSectionHandler`: Your encoding profiles. Payload
//     `{ "profiles": [ …EncodingProfile… ] }`, from the profiles file.
// #505 (the MeedyaDB submission queue) will add a third, for a new
// `SettingsCategory` case; `SettingsSectionHandlers.handler(for:)` switches
// over every category, so a new category without a handler will not compile.
//
// Writing is NOT done here. Handlers only build and check. The importer does
// all the writing, in one fixed order across every group (the profiles file
// first, then the settings), because the order is what makes an import
// all-or-nothing, and it cannot be guaranteed if each handler wrote its own
// group. See `SettingsImporter.apply`.
//
// What a settings handler never does, whatever the file says:
//   - write a setting the registry has no entry for (reported as unknown);
//   - write a setting the registry marks "never" (reported with the kind of
//     reason: a password, a consent, hooks, …);
//   - write a setting sitting in the wrong group (reported, so that ticking
//     "General" can never change a Connections setting).
// ---------------------------------------------------------------------------

import Foundation

// MARK: - Reported, never written

/// Something in a settings file that was not imported, and why. Never fatal:
/// the rest of the file still imports.
public struct SettingsIgnoredItem: Sendable, Equatable {

    /// Why it was ignored.
    public enum Reason: Sendable, Equatable {
        /// A group this version does not know (perhaps from a newer version).
        case unknownGroup
        /// A setting this version does not know.
        case unknownSetting
        /// A setting that is never imported, for this broad reason.
        case neverImported(SettingsNeverKind)
        /// A known setting sitting in the wrong group. It belongs in the
        /// named group, and is only ever imported from there.
        case wrongGroup(belongsIn: SettingsCategory)
        /// A name in `notIncluded` this version does not know.
        case unknownLeftOutName
        /// A field of the file's structure this version does not know.
        case unknownField
    }

    /// The group it was found in, as written in the file (nil for the
    /// file's top level).
    public let group: String?

    /// The setting's or field's name, as written in the file.
    public let name: String

    /// Why it was ignored.
    public let reason: Reason

    /// One plain sentence saying what was ignored and why.
    public var explanation: String {
        switch reason {
        case .unknownGroup:
            return "The group “\(name)” isn't known to this version of MeedyaConverter, so it was ignored."
        case .unknownSetting:
            return "The setting “\(name)” isn't known to this version of MeedyaConverter, so it was ignored."
        case .neverImported(let kind):
            let label = SettingsKeyRegistry.entry(for: name)?.label ?? name
            return "“\(label)” is never imported. \(kind.summary)"
        case .wrongGroup(let belongsIn):
            let label = SettingsKeyRegistry.entry(for: name)?.label ?? name
            return "“\(label)” was in the wrong group, so it was ignored. It belongs in "
                + "“\(belongsIn.displayName)”."
        case .unknownLeftOutName:
            return "The file mentions “\(name)” as not included, which this version doesn't know."
        case .unknownField:
            return "The file has a field “\(name)” this version doesn't know, so it was ignored."
        }
    }
}

// MARK: - Export notes

/// Something the exporter left out or removed, for the export report. Never
/// contains a value.
public struct SettingsExportNote: Sendable, Equatable {
    /// The group the setting belongs to.
    public let category: SettingsCategory
    /// The setting's stored name.
    public let key: String
    /// What happened, in plain English (it names the setting by its label).
    public let message: String
}

// MARK: - What a handler produces

/// One group's part of a file, built on export.
struct SettingsExportedSection {
    /// The group's payload, ready to place under `categories`.
    let payload: JSONValue
    /// How many settings (or profiles) it holds.
    let itemCount: Int
    /// What was left out or removed.
    let notes: [SettingsExportNote]
}

/// One group's part of a file, checked on import.
struct SettingsValidatedSection: Sendable {

    enum Content: Sendable {
        /// Checked settings by key. Every key is allowed in this group.
        case settings([String: SettingsValidatedValue])
        /// Checked user profiles. None claims to be built in; no two share
        /// an `id`.
        case profiles([EncodingProfile])
    }

    let category: SettingsCategory
    let content: Content
    let ignored: [SettingsIgnoredItem]
}

/// What an export reads from.
struct SettingsExportSource {
    /// A snapshot of the settings domain (`SettingsDomain.snapshot()`).
    let snapshot: [String: Any]
    /// The live profile store.
    let profileStore: EncodingProfileStore
}

// MARK: - SettingsSectionHandler

/// Builds and checks one group of a settings file.
protocol SettingsSectionHandler: Sendable {
    var category: SettingsCategory { get }
    /// This group's part of the file.
    func export(from source: SettingsExportSource) throws -> SettingsExportedSection
    /// Checks this group's part of a file, throwing `SettingsImportError`
    /// on the first value it will not accept.
    func validate(_ payload: JSONValue) throws -> SettingsValidatedSection
}

enum SettingsSectionHandlers {

    /// The handler for `category`. A `switch` over every category, so a new
    /// category cannot be added without deciding its handler.
    static func handler(for category: SettingsCategory) -> any SettingsSectionHandler {
        switch category {
        case .general, .encoding, .connections, .thisMac:
            return SettingsDefaultsSectionHandler(category: category)
        case .encodingProfiles:
            return SettingsProfilesSectionHandler()
        }
    }
}

// MARK: - SettingsDefaultsSectionHandler

/// General, Encoding, Connections and This Mac only: settings stored in
/// `UserDefaults`, exactly as `SettingsKeyRegistry` allows them.
struct SettingsDefaultsSectionHandler: SettingsSectionHandler {

    /// The name of the payload's one field.
    static let settingsField = "settings"

    let category: SettingsCategory

    func export(from source: SettingsExportSource) throws -> SettingsExportedSection {
        var settings: [String: JSONValue] = [:]
        var notes: [SettingsExportNote] = []

        // Only the registry's entries for this group are even looked at, so a
        // setting with no decision, or a "never" one, cannot get in here.
        for entry in SettingsKeyRegistry.entries(in: category).sorted(by: { $0.key < $1.key }) {
            guard let rules = entry.rules, let stored = source.snapshot[entry.key] else { continue }
            switch SettingsValueCodec.export(stored: stored, rules: rules) {
            case .include(let value, let removed):
                settings[entry.key] = value
                notes += removed.map {
                    SettingsExportNote(category: category, key: entry.key, message: "\(entry.label): \($0).")
                }
            case .leaveOut(let reason):
                notes.append(SettingsExportNote(
                    category: category, key: entry.key,
                    message: "“\(entry.label)” was left out: \(reason)."
                ))
            }
        }

        return SettingsExportedSection(
            payload: .object([Self.settingsField: .object(settings)]),
            itemCount: settings.count,
            notes: notes
        )
    }

    func validate(_ payload: JSONValue) throws -> SettingsValidatedSection {
        let path = "\(SettingsDocument.Field.categories).\(category.rawValue)"
        guard case .object(let section) = payload else {
            throw SettingsImportError.malformed(path: path, reason: "should be an object")
        }
        guard let settingsValue = section[Self.settingsField] else {
            throw SettingsImportError.malformed(path: "\(path).\(Self.settingsField)", reason: "is missing")
        }
        guard case .object(let settings) = settingsValue else {
            throw SettingsImportError.malformed(path: "\(path).\(Self.settingsField)", reason: "should be an object")
        }

        var ignored = section.keys
            .filter { $0 != Self.settingsField }
            .sorted()
            .map { SettingsIgnoredItem(group: category.rawValue, name: $0, reason: .unknownField) }

        var validated: [String: SettingsValidatedValue] = [:]
        // Sorted, so the same bad file always reports the same first problem.
        for key in settings.keys.sorted() {
            guard let value = settings[key] else { continue }
            guard let entry = SettingsKeyRegistry.entry(for: key) else {
                ignored.append(SettingsIgnoredItem(group: category.rawValue, name: key, reason: .unknownSetting))
                continue
            }
            if let neverKind = entry.neverKind {
                ignored.append(SettingsIgnoredItem(
                    group: category.rawValue, name: key, reason: .neverImported(neverKind)
                ))
                continue
            }
            guard let belongsIn = entry.category, let rules = entry.rules else { continue }
            guard belongsIn == category else {
                ignored.append(SettingsIgnoredItem(
                    group: category.rawValue, name: key, reason: .wrongGroup(belongsIn: belongsIn)
                ))
                continue
            }
            validated[key] = try SettingsValueCodec.validate(value, key: key, rules: rules, category: category)
        }

        return SettingsValidatedSection(category: category, content: .settings(validated), ignored: ignored)
    }
}

// MARK: - SettingsProfilesSectionHandler

/// Your encoding profiles: the profiles file, not settings keys. Built-in
/// profiles are never exported (every copy of the app has them) and a file
/// that claims one is refused whole (#506 plan section 2; commit 3's
/// `EncodingProfileStore` refuses them too).
struct SettingsProfilesSectionHandler: SettingsSectionHandler {

    /// The name of the payload's one field.
    static let profilesField = "profiles"

    var category: SettingsCategory { .encodingProfiles }

    func export(from source: SettingsExportSource) throws -> SettingsExportedSection {
        let userProfiles = source.profileStore.allProfiles().filter { !$0.isBuiltIn }
        return SettingsExportedSection(
            payload: .object([Self.profilesField: try SettingsJSON.value(from: userProfiles)]),
            itemCount: userProfiles.count,
            notes: []
        )
    }

    func validate(_ payload: JSONValue) throws -> SettingsValidatedSection {
        let path = "\(SettingsDocument.Field.categories).\(category.rawValue)"
        guard case .object(let section) = payload else {
            throw SettingsImportError.malformed(path: path, reason: "should be an object")
        }
        guard let listValue = section[Self.profilesField] else {
            throw SettingsImportError.malformed(path: "\(path).\(Self.profilesField)", reason: "is missing")
        }
        guard case .array(let elements) = listValue else {
            throw SettingsImportError.malformed(path: "\(path).\(Self.profilesField)", reason: "should be a list")
        }
        guard elements.count <= SettingsValueCodec.maximumListItems else {
            throw SettingsImportError.invalidValue(
                category: category, key: Self.profilesField,
                reason: "there are more than \(SettingsValueCodec.maximumListItems) profiles"
            )
        }

        let ignored = section.keys
            .filter { $0 != Self.profilesField }
            .sorted()
            .map { SettingsIgnoredItem(group: category.rawValue, name: $0, reason: .unknownField) }

        var profiles: [EncodingProfile] = []
        var seen = Set<UUID>()
        for (index, element) in elements.enumerated() {
            let itemName = "profile \(index + 1)"
            guard case .object(let fields) = element, case .string? = fields["id"] else {
                throw SettingsImportError.invalidValue(category: category, key: itemName, reason: "it has no “id”")
            }
            let profile: EncodingProfile
            do {
                profile = try SettingsJSON.decode(EncodingProfile.self, from: element)
            } catch {
                throw SettingsImportError.invalidValue(
                    category: category, key: itemName, reason: SettingsJSON.describe(error)
                )
            }
            // A file claiming a built-in profile is refused WHOLE (a settings
            // file must never be able to plant a profile the app treats as
            // its own, undeletable one). `EncodingProfileStore` refuses it
            // too; refusing here means it is caught before anything is
            // written, with a message naming the profile.
            if profile.isBuiltIn {
                throw SettingsImportError.invalidValue(
                    category: category, key: profile.name,
                    reason: "it claims to be one of the built-in profiles, which come with the app "
                        + "and are never imported"
                )
            }
            if profile.name.count > SettingsValueKind.defaultMaxStringLength
                || profile.description.count > SettingsValueKind.defaultMaxStringLength {
                throw SettingsImportError.invalidValue(
                    category: category, key: itemName, reason: "its name or description is far too long"
                )
            }
            guard seen.insert(profile.id).inserted else {
                throw SettingsImportError.invalidValue(
                    category: category, key: profile.name,
                    reason: "two profiles share the ID \(profile.id.uuidString)"
                )
            }
            profiles.append(profile)
        }

        return SettingsValidatedSection(category: category, content: .profiles(profiles), ignored: ignored)
    }
}
