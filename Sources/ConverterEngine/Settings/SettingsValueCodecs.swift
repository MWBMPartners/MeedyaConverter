// ============================================================================
// MeedyaConverter — Settings value codecs (Issue #506 commit 5)
// Sources/ConverterEngine/Settings/SettingsValueCodecs.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Turns ONE stored setting into the value written in a settings file
// ("export"), and one value from a settings file into the value stored
// ("import"), applying the rules `SettingsKeyRegistry` records for it.
//
// This is where secrets are kept out of the file. In order of importance:
//   1. Only settings the registry allows ever reach this file (the section
//      handlers ask the registry first; see `SettingsSectionHandlers.swift`).
//   2. Lists that can still hold a secret are decoded into their real Swift
//      type and the secret FIELDS are blanked, field by field, whatever the
//      stored list contains:
//        - SFTP servers: a password is always written as "" (an old,
//          never-migrated list can still hold one in plain text, because the
//          only code that moves it to the Keychain runs when the SFTP screen
//          is opened);
//        - cloud destinations: the access token (for S3, the access key ID)
//          is written as "", and the refresh token and S3 secret key are left
//          out.
//   3. Addresses are refused if they carry a user name or password, or a
//      query string (see `SettingsAddressCheck`): `https://<token>@github.com`
//      is a common way of putting a GitHub token in a git address, and Plex
//      addresses are often copied with `?X-Plex-Token=…` on the end.
//   4. The importer refuses a file whose lists carry any of those secrets, so
//      the same checks run in both directions, and the exporter runs its own
//      output through the importer before writing it.
//
// Why decode into the real type rather than editing raw JSON: a typed model
// has exactly the fields its type declares. Redacting "the password field"
// on raw JSON would miss a field spelled differently, or an extra field; a
// typed round trip drops anything the type doesn't have, and the compiler
// knows every field that exists.
//
// Stored values of the wrong type are LEFT OUT of an export, with a note,
// never converted. Foundation will happily read a stored 1 as `true`, or the
// text "5" as the number 5; a settings file built from such guesses could
// change what the person actually had. So booleans and numbers are told
// apart by their underlying stored type (`CFBooleanGetTypeID`), and a whole
// number stored as a decimal is not accepted as a whole number.
//
// What this file cannot see: a secret typed into an ordinary text setting
// (a password pasted into "SMTP user name", say). The registry marks which
// settings are addresses and checks those; free text is written as it is.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - Results

/// What happens to one stored setting on export.
enum SettingsExportOutcome {
    /// Written to the file as `value`. `notes` say what was removed from it
    /// on the way (for example "1 SFTP password left out").
    case include(JSONValue, notes: [String])
    /// Left out of the file, for `reason` (plain English, never the value).
    case leaveOut(reason: String)
}

/// A value from a settings file that has passed every check.
enum SettingsValidatedValue: Sendable, Equatable {
    /// Stored exactly as it is (a single value, or a list or object that is
    /// always replaced whole).
    case whole(SettingsWritableValue)
    /// A list merged with the one on this Mac by each item's `id` (see
    /// `SettingsListCodec.combine`).
    case list(SettingsValidatedList)
}

/// A checked list from a settings file, waiting to be combined with the
/// list on this Mac.
struct SettingsValidatedList: Sendable, Equatable {
    /// Which list this is.
    let blob: SettingsJSONBlob
    /// The checked items, encoded with their real Swift type. Anything the
    /// file had that the type does not declare is already gone.
    let encodedItems: Data
    /// Each item's `id` and name, for previews and reports.
    let items: [SettingsListItemSummary]
}

/// One item in a list setting, named the way a person would recognise it.
public struct SettingsListItemSummary: Sendable, Equatable {
    /// The item's `id`, which is how lists are merged.
    public let id: UUID
    /// Its label or name (an SFTP server's label, a rule's name, …).
    public let name: String
}

/// How one list setting would change on import.
public struct SettingsListChanges: Sendable, Equatable {
    /// Items the file adds.
    public var added: [String] = []
    /// Items the file replaces (same `id` as one on this Mac).
    public var updated: [String] = []
    /// Items a "Replace" import removes (on this Mac, not in the file).
    public var removed: [String] = []

    /// True when nothing changes.
    public var isEmpty: Bool { added.isEmpty && updated.isEmpty && removed.isEmpty }
}

// MARK: - How each JSON blob is merged

extension SettingsJSONBlob {

    /// How an imported value is combined with this Mac's in "merge" mode.
    enum MergeRule: Sendable, Equatable {
        /// The file's value replaces this Mac's whole (a theme, the set of
        /// keyboard shortcuts, the list of email recipients).
        case wholeValue
        /// Items are matched by `id`: the file's items are added or update
        /// the matching item, and this Mac's other items are kept. Replacing
        /// the whole list instead would silently delete servers, rules or
        /// pipelines the other Mac never had.
        case byItemID
    }

    var mergeRule: MergeRule {
        switch self {
        case .customTheme, .keyboardShortcuts, .emailRecipients:
            return .wholeValue
        case .conditionalRules, .encodingPipelines, .renderFarmAgents, .sftpProfiles,
             .cloudStorageProfiles:
            return .byItemID
        }
    }
}

// MARK: - SettingsAddressCheck

/// The rule for addresses: never a user name or password inside one, and no
/// query string.
///
/// Refused:
///   - any address with a password: `scheme://user:password@host`, or the
///     scheme-less `user:password@host…`;
///   - a web address (`http`/`https`) with ANYTHING before an `@` in its
///     host part, even with no password: `https://<token>@github.com/…` puts
///     the token where the user name goes;
///   - any address with a query (`…?…`): tokens are often passed that way
///     (`?access_token=…`, Plex's `?X-Plex-Token=…`), and none of the
///     settings checked here needs one;
///   - control characters (line breaks and the like), which no real address
///     contains.
/// Allowed: a user name with no password for other schemes
/// (`ssh://git@github.com/…`) and the scp-like git form
/// (`git@github.com:org/repo.git`), because the user name there is not a
/// secret and git needs it.
///
/// What it cannot catch: a token placed in the PATH of an address
/// (`https://host/<token>/…`). Nothing distinguishes that from an ordinary
/// path, so it is not attempted; the settings checked here are a git remote,
/// a server address and host names, where that form is not used.
enum SettingsAddressCheck {

    /// `nil` when `address` is safe to carry in a settings file; otherwise
    /// the reason, in plain English, without the address itself.
    static func problem(in address: String) -> String? {
        if address.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "it contains a line break or other control character"
        }
        if let schemeEnd = address.range(of: "://") {
            let scheme = address[address.startIndex..<schemeEnd.lowerBound].lowercased()
            let rest = address[schemeEnd.upperBound...]
            // The host part ends at the first "/", "?" or "#".
            let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
            let authority = rest[rest.startIndex..<authorityEnd]
            if let at = authority.lastIndex(of: "@") {
                let userInfo = authority[authority.startIndex..<at]
                if userInfo.contains(":") {
                    return "it contains a password (the part before “@”)"
                }
                if scheme == "http" || scheme == "https" {
                    return "it contains a user name or token before “@”"
                }
            }
            let afterAuthority = rest[authorityEnd...]
            let pathAndQuery = afterAuthority.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first ?? ""
            if pathAndQuery.contains("?") {
                return "it contains a query (“?…”), which is sometimes used to carry a token"
            }
            return nil
        }
        // No scheme: a plain host name, or the scp-like `user@host:path`.
        if let at = address.firstIndex(of: "@") {
            if address[address.startIndex..<at].contains(":") {
                return "it contains a password (the part before “@”)"
            }
        }
        if address.contains("?") {
            return "it contains a query (“?…”), which is sometimes used to carry a token"
        }
        return nil
    }
}

// MARK: - Reading stored values by their real type

/// Reads a value from the settings snapshot WITHOUT Foundation's
/// conversions. See the file overview for why.
enum SettingsStoredValue {

    /// True/false, only if it is stored as one.
    static func bool(_ stored: Any) -> Bool? {
        let object = stored as AnyObject
        guard CFGetTypeID(object) == CFBooleanGetTypeID(), let number = object as? NSNumber else {
            return nil
        }
        return number.boolValue
    }

    /// A number that is not true/false.
    static func number(_ stored: Any) -> NSNumber? {
        let object = stored as AnyObject
        guard CFGetTypeID(object) != CFBooleanGetTypeID(), let number = object as? NSNumber else {
            return nil
        }
        return number
    }

    /// A whole number, only if it is stored as one (a stored 3.0 is a
    /// decimal, and is not accepted here).
    static func int(_ stored: Any) -> Int? {
        guard let number = number(stored), !CFNumberIsFloatType(number as CFNumber) else { return nil }
        return number.intValue
    }

    /// Any number that is not true/false, as a decimal. A whole number
    /// stored for a decimal setting is accepted: nothing is lost by reading
    /// 30 as 30.0.
    static func double(_ stored: Any) -> Double? {
        number(stored)?.doubleValue
    }
}

// MARK: - SettingsValueCodec (one setting, either direction)

/// Exports and imports ONE setting's value according to its registry rules.
enum SettingsValueCodec {

    /// Hard ceiling on items in any one list, far above any real use. Stops a
    /// hostile file making the app build an enormous list; the 10 MB file
    /// limit is the outer bound.
    static let maximumListItems = 10_000

    // MARK: Export

    /// The value to write for a stored setting, or why it is left out.
    static func export(stored: Any, rules: SettingsValueRules) -> SettingsExportOutcome {
        switch rules.kind {
        case .bool:
            guard let value = SettingsStoredValue.bool(stored) else {
                return .leaveOut(reason: "it is stored as something other than on/off")
            }
            return .include(.bool(value), notes: [])

        case .int(let range):
            guard let value = SettingsStoredValue.int(stored) else {
                return .leaveOut(reason: "it is stored as something other than a whole number")
            }
            if let range, !range.contains(value) {
                return .leaveOut(reason: "its stored value is outside the accepted range "
                    + "(\(range.lowerBound) to \(range.upperBound))")
            }
            return .include(.number(Double(value)), notes: [])

        case .double(let range):
            guard let value = SettingsStoredValue.double(stored), value.isFinite else {
                return .leaveOut(reason: "it is stored as something other than a number")
            }
            if let range, !range.contains(value) {
                return .leaveOut(reason: "its stored value is outside the accepted range "
                    + "(\(range.lowerBound) to \(range.upperBound))")
            }
            return .include(.number(value), notes: [])

        case .string, .address, .filePath, .hexColour:
            guard let text = stored as? String else {
                return .leaveOut(reason: "it is stored as something other than text")
            }
            if let problem = textProblem(text, kind: rules.kind) {
                return .leaveOut(reason: problem)
            }
            return .include(.string(text), notes: [])

        case .json(let blob):
            return SettingsBlobCodec.export(stored: stored, blob: blob)
        }
    }

    // MARK: Import

    /// Checks one value from a settings file. Throws `invalidValue` (naming
    /// the setting, never quoting the value) when it is not acceptable.
    static func validate(
        _ value: JSONValue,
        key: String,
        rules: SettingsValueRules,
        category: SettingsCategory
    ) throws -> SettingsValidatedValue {
        func refuse(_ reason: String) -> SettingsImportError {
            .invalidValue(category: category, key: key, reason: reason)
        }

        switch rules.kind {
        case .bool:
            guard case .bool(let flag) = value else { throw refuse("it should be true or false") }
            return .whole(.bool(flag))

        case .int(let range):
            guard case .number(let number) = value, let whole = wholeNumber(number) else {
                throw refuse("it should be a whole number")
            }
            if let range, !range.contains(whole) {
                throw refuse("it should be between \(range.lowerBound) and \(range.upperBound)")
            }
            return .whole(.int(whole))

        case .double(let range):
            guard case .number(let number) = value, number.isFinite else {
                throw refuse("it should be a number")
            }
            if let range, !range.contains(number) {
                throw refuse("it should be between \(range.lowerBound) and \(range.upperBound)")
            }
            return .whole(.double(number))

        case .string, .address, .filePath, .hexColour:
            guard case .string(let text) = value else { throw refuse("it should be text") }
            if let problem = textProblem(text, kind: rules.kind) { throw refuse(problem) }
            return .whole(.string(text))

        case .json(let blob):
            return try SettingsBlobCodec.validate(value, blob: blob, key: key, category: category)
        }
    }

    // MARK: Shared checks

    /// The rule for every text-like kind, or `nil` when `text` is fine.
    /// The same function decides export and import, so the two cannot drift.
    static func textProblem(_ text: String, kind: SettingsValueKind) -> String? {
        switch kind {
        case .string(let allowed, let maxLength):
            if text.count > maxLength { return "it is longer than \(maxLength) characters" }
            if let allowed, !allowed.contains(text) {
                return "it isn't one of the accepted values (\(allowed.joined(separator: ", ")))"
            }
            return nil
        case .address:
            if text.count > SettingsValueKind.defaultMaxStringLength {
                return "it is longer than \(SettingsValueKind.defaultMaxStringLength) characters"
            }
            return SettingsAddressCheck.problem(in: text)
        case .filePath:
            return filePathProblem(text)
        case .hexColour:
            return isHexColour(text) ? nil : "it should be a colour written as #RRGGBB"
        case .bool, .int, .double, .json:
            return "it should not be text"
        }
    }

    /// Empty (meaning "find it automatically"), or a full path starting with
    /// "/" or "~". A relative path would mean something different on every
    /// Mac, so it is refused rather than guessed at.
    static func filePathProblem(_ text: String) -> String? {
        if text.isEmpty { return nil }
        if text.count > SettingsValueKind.defaultMaxStringLength {
            return "it is longer than \(SettingsValueKind.defaultMaxStringLength) characters"
        }
        if text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "it contains a line break or other control character"
        }
        guard text.hasPrefix("/") || text.hasPrefix("~") else {
            return "it should be a full path starting with “/”"
        }
        return nil
    }

    /// `#RRGGBB`, the form `ThemeManager` stores (it writes capitals; either
    /// case is accepted).
    static func isHexColour(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count == 7, scalars[0] == "#" else { return false }
        return scalars.dropFirst().allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    /// A JSON number as an `Int`, only when it is a whole number that fits
    /// exactly. JSON has one number type, so `2` and `2.0` look the same
    /// here; `2.5` is refused.
    static func wholeNumber(_ number: Double) -> Int? {
        guard number.isFinite, number == number.rounded(.towardZero),
              abs(number) <= 9_007_199_254_740_992 else { return nil }   // 2^53: every Int up to here is exact
        return Int(number)
    }
}

// MARK: - SettingsBlobCodec (settings stored as JSON)

/// Export and import for each `SettingsJSONBlob`. One typed codec per blob,
/// chosen by a `switch`, so adding a blob without deciding how it is handled
/// is a compile error.
enum SettingsBlobCodec {

    // MARK: Export

    static func export(stored: Any, blob: SettingsJSONBlob) -> SettingsExportOutcome {
        // First, the stored form: binary JSON for most, text for the email
        // recipients (see `SettingsJSONBlob.storage`).
        let data: Data
        switch blob.storage {
        case .data:
            guard let stored = stored as? Data else {
                return .leaveOut(reason: "it is stored in an unexpected form")
            }
            data = stored
        case .jsonString:
            guard let text = stored as? String else {
                return .leaveOut(reason: "it is stored in an unexpected form")
            }
            data = Data(text.utf8)
        }

        switch blob {
        case .customTheme:
            return exportWhole(SettingsThemeShape.self, from: data)
        case .keyboardShortcuts:
            return exportWhole([SettingsShortcutShape].self, from: data)
        case .emailRecipients:
            return exportWhole(SettingsEmailRecipients.self, from: data)
        case .conditionalRules:
            return exportList(ConditionalRule.self, from: data)
        case .encodingPipelines:
            return exportList(EncodingPipeline.self, from: data)
        case .renderFarmAgents:
            return exportList(RenderFarmAgentInfo.self, from: data)
        case .sftpProfiles:
            return exportList(SFTPServerConfig.self, from: data)
        case .cloudStorageProfiles:
            return exportList(CloudStorageConfig.self, from: data)
        }
    }

    private static func exportWhole<T: SettingsWholeBlob>(_ type: T.Type, from data: Data) -> SettingsExportOutcome {
        // An empty stored value ("" or an empty `Data()`) is treated as
        // "nothing saved" by the app, so it is left out.
        guard !data.isEmpty else { return .leaveOut(reason: "nothing is saved in it") }
        guard let model = try? JSONDecoder().decode(T.self, from: data) else {
            return .leaveOut(reason: "its stored value couldn't be read")
        }
        if let problem = model.settingsProblem() {
            return .leaveOut(reason: problem)
        }
        guard let value = try? SettingsJSON.value(from: model) else {
            return .leaveOut(reason: "its stored value couldn't be converted")
        }
        return .include(value, notes: [])
    }

    private static func exportList<T: SettingsListItem>(_ type: T.Type, from data: Data) -> SettingsExportOutcome {
        guard !data.isEmpty else { return .leaveOut(reason: "nothing is saved in it") }
        guard let items = try? JSONDecoder().decode([T].self, from: data) else {
            return .leaveOut(reason: "its stored value couldn't be read")
        }
        var kept: [T] = []
        var notes: [String] = []
        var seen = Set<UUID>()
        for item in items {
            switch item.exportForm() {
            case .safe(let safe, let removed):
                // Two stored items with one `id` would make a file the importer
                // refuses; keep the first, say so.
                guard seen.insert(safe.settingsItemID).inserted else {
                    notes.append("“\(safe.settingsItemName)” was left out: another item has the same ID")
                    continue
                }
                kept.append(safe)
                notes.append(contentsOf: removed)
            case .unsafe(let reason):
                notes.append("“\(item.settingsItemName)” was left out: \(reason)")
            }
        }
        guard let value = try? SettingsJSON.value(from: kept) else {
            return .leaveOut(reason: "its stored value couldn't be converted")
        }
        return .include(value, notes: notes)
    }

    // MARK: Import

    static func validate(
        _ value: JSONValue,
        blob: SettingsJSONBlob,
        key: String,
        category: SettingsCategory
    ) throws -> SettingsValidatedValue {
        switch blob {
        case .customTheme:
            let theme = try validateWhole(SettingsThemeShape.self, value, key: key, category: category)
            return .whole(.data(try SettingsJSON.encode(theme)))
        case .keyboardShortcuts:
            let shortcuts = try validateWhole([SettingsShortcutShape].self, value, key: key, category: category)
            return .whole(.data(try SettingsJSON.encode(shortcuts)))
        case .emailRecipients:
            let recipients = try validateWhole(SettingsEmailRecipients.self, value, key: key, category: category)
            // Stored as TEXT holding a JSON list, exactly as `EmailSettingsView`
            // writes it (a plain `JSONEncoder`, then UTF-8 text).
            return .whole(.string(try recipients.storedText()))
        case .conditionalRules:
            return .list(try validateList(ConditionalRule.self, value, blob: blob, key: key, category: category))
        case .encodingPipelines:
            return .list(try validateList(EncodingPipeline.self, value, blob: blob, key: key, category: category))
        case .renderFarmAgents:
            return .list(try validateList(RenderFarmAgentInfo.self, value, blob: blob, key: key, category: category))
        case .sftpProfiles:
            return .list(try validateList(SFTPServerConfig.self, value, blob: blob, key: key, category: category))
        case .cloudStorageProfiles:
            return .list(try validateList(CloudStorageConfig.self, value, blob: blob, key: key, category: category))
        }
    }

    private static func validateWhole<T: SettingsWholeBlob>(
        _ type: T.Type,
        _ value: JSONValue,
        key: String,
        category: SettingsCategory
    ) throws -> T {
        let model: T
        do {
            model = try SettingsJSON.decode(T.self, from: value)
        } catch {
            throw SettingsImportError.invalidValue(
                category: category, key: key, reason: SettingsJSON.describe(error)
            )
        }
        if let problem = model.settingsProblem() {
            throw SettingsImportError.invalidValue(category: category, key: key, reason: problem)
        }
        return model
    }

    private static func validateList<T: SettingsListItem>(
        _ type: T.Type,
        _ value: JSONValue,
        blob: SettingsJSONBlob,
        key: String,
        category: SettingsCategory
    ) throws -> SettingsValidatedList {
        func refuse(_ reason: String) -> SettingsImportError {
            .invalidValue(category: category, key: key, reason: reason)
        }
        guard case .array(let elements) = value else { throw refuse("it should be a list") }
        guard elements.count <= SettingsValueCodec.maximumListItems else {
            throw refuse("it has more than \(SettingsValueCodec.maximumListItems) items")
        }

        var items: [T] = []
        var seen = Set<UUID>()
        for (index, element) in elements.enumerated() {
            // Every item must carry its own `id`. Lists are merged by it, and
            // `SFTPServerConfig`'s decoder would otherwise invent a new random
            // one, making the item a duplicate on every import.
            guard case .object(let fields) = element, case .string? = fields["id"] else {
                throw refuse("item \(index + 1) has no “id”")
            }
            let item: T
            do {
                item = try SettingsJSON.decode(T.self, from: element)
            } catch {
                throw refuse("item \(index + 1): \(SettingsJSON.describe(error))")
            }
            if let problem = item.importProblem() {
                throw refuse("“\(item.settingsItemName)”: \(problem)")
            }
            guard seen.insert(item.settingsItemID).inserted else {
                throw refuse("two items share the ID \(item.settingsItemID.uuidString)")
            }
            items.append(item)
        }

        return SettingsValidatedList(
            blob: blob,
            encodedItems: try SettingsJSON.encode(items),
            items: items.map { SettingsListItemSummary(id: $0.settingsItemID, name: $0.settingsItemName) }
        )
    }
}

// MARK: - SettingsListCodec (combining a file's list with this Mac's)

/// Import mode: add to what is here, or make the ticked groups match the file.
public enum SettingsImportMode: String, Sendable, CaseIterable, Codable {
    /// Only what the file contains changes; list items are added or updated
    /// by `id`; nothing is removed.
    case merge
    /// Within the ticked groups only: settings the file doesn't have go back
    /// to their defaults, and list items and profiles the file doesn't have
    /// are removed. Passwords and keys are never touched.
    case replace
}

enum SettingsListCodec {

    /// Combines the file's list with this Mac's (`local`, straight from the
    /// settings snapshot) and returns what to store, plus what changed.
    ///
    /// Merge: this Mac's items stay in their order; a file item with the
    /// same `id` replaces it in place; new file items go on the end.
    /// Replace: the result is the file's items, in the file's order.
    ///
    /// Either way, when a file item replaces one of this Mac's with the same
    /// `id`, any secret this Mac's item still holds is KEPT
    /// (`keepingSecrets(of:)`). The file never has one, so without this an
    /// import would wipe an SFTP password that was never moved into the
    /// Keychain. Passwords that are in the Keychain are not touched at all:
    /// they are filed under the item's `id`, which does not change.
    static func combine(
        _ list: SettingsValidatedList,
        local: Any?,
        mode: SettingsImportMode,
        key: String,
        category: SettingsCategory
    ) throws -> (stored: Data, changes: SettingsListChanges) {
        switch list.blob {
        case .conditionalRules:
            return try combine(ConditionalRule.self, list, local: local, mode: mode, key: key, category: category)
        case .encodingPipelines:
            return try combine(EncodingPipeline.self, list, local: local, mode: mode, key: key, category: category)
        case .renderFarmAgents:
            return try combine(RenderFarmAgentInfo.self, list, local: local, mode: mode, key: key, category: category)
        case .sftpProfiles:
            return try combine(SFTPServerConfig.self, list, local: local, mode: mode, key: key, category: category)
        case .cloudStorageProfiles:
            return try combine(CloudStorageConfig.self, list, local: local, mode: mode, key: key, category: category)
        case .customTheme, .keyboardShortcuts, .emailRecipients:
            // These are validated as whole values and can never reach here.
            throw SettingsImportError.internalSafetyCheckFailed(detail: "\(key) is not a list")
        }
    }

    private static func combine<T: SettingsListItem>(
        _ type: T.Type,
        _ list: SettingsValidatedList,
        local: Any?,
        mode: SettingsImportMode,
        key: String,
        category: SettingsCategory
    ) throws -> (stored: Data, changes: SettingsListChanges) {
        let incoming = try JSONDecoder().decode([T].self, from: list.encodedItems)

        // This Mac's list. Absent or empty means none. Unreadable matters
        // only for merge, which has to keep this Mac's items: it refuses
        // rather than guess. Replace doesn't need them.
        let localItems: [T]
        if let data = local as? Data, !data.isEmpty {
            if let decoded = try? JSONDecoder().decode([T].self, from: data) {
                localItems = decoded
            } else if mode == .replace {
                localItems = []
            } else {
                throw SettingsImportError.localValueUnreadable(category: category, key: key)
            }
        } else if local == nil || (local as? Data)?.isEmpty == true {
            localItems = []
        } else if mode == .replace {
            localItems = []
        } else {
            throw SettingsImportError.localValueUnreadable(category: category, key: key)
        }

        var localByID: [UUID: T] = [:]
        for item in localItems where localByID[item.settingsItemID] == nil {
            localByID[item.settingsItemID] = item
        }
        let incomingIDs = Set(incoming.map(\.settingsItemID))

        var changes = SettingsListChanges()
        var result: [T]
        switch mode {
        case .merge:
            var incomingByID: [UUID: T] = [:]
            for item in incoming { incomingByID[item.settingsItemID] = item }
            result = localItems.map { localItem in
                guard let replacement = incomingByID[localItem.settingsItemID] else { return localItem }
                return replacement.keepingSecrets(of: localItem)
            }
            let localIDs = Set(localItems.map(\.settingsItemID))
            for item in incoming where !localIDs.contains(item.settingsItemID) {
                result.append(item)
            }
        case .replace:
            result = incoming.map { item in
                guard let localItem = localByID[item.settingsItemID] else { return item }
                return item.keepingSecrets(of: localItem)
            }
            changes.removed = localItems
                .filter { !incomingIDs.contains($0.settingsItemID) }
                .map(\.settingsItemName)
        }

        for item in incoming {
            if let localItem = localByID[item.settingsItemID] {
                // Only count it as updated if something the file carries is
                // different; the kept secret doesn't count.
                let merged = item.keepingSecrets(of: localItem)
                if (try? SettingsJSON.canonical(merged)) != (try? SettingsJSON.canonical(localItem)) {
                    changes.updated.append(item.settingsItemName)
                }
            } else {
                changes.added.append(item.settingsItemName)
            }
        }

        return (try SettingsJSON.encode(result), changes)
    }
}

// MARK: - Typed models the codecs use

/// A setting stored as one JSON document that is always replaced whole.
protocol SettingsWholeBlob: Codable, Sendable {
    /// Why this value may not be written to or read from a settings file,
    /// or `nil` when it is fine.
    func settingsProblem() -> String?
}

/// What exporting one list item produced.
enum SettingsItemExportForm<Item> {
    /// Safe to write. `removed` says what was taken out (for the report).
    case safe(Item, removed: [String])
    /// Cannot be made safe, so it is left out, for `reason`.
    case unsafe(reason: String)
}

/// An item in a list setting that is merged by `id`.
protocol SettingsListItem: Codable, Sendable {
    /// The `id` lists are merged by.
    var settingsItemID: UUID { get }
    /// A name a person would recognise.
    var settingsItemName: String { get }
    /// The item as it may appear in a settings file: every secret blanked,
    /// or `.unsafe` when it cannot be made safe (for example an address with
    /// a password in it, which can't be blanked without changing where it
    /// points).
    func exportForm() -> SettingsItemExportForm<Self>
    /// Why this item, read from a settings file, must be refused, or `nil`.
    func importProblem() -> String?
    /// This (incoming) item, with any secret fields that `local` (the item
    /// on this Mac with the same `id`) holds and this one doesn't.
    func keepingSecrets(of local: Self) -> Self
}

extension SettingsListItem {
    // Lists with no secret fields: nothing to blank, nothing to keep.
    func exportForm() -> SettingsItemExportForm<Self> {
        if let problem = importProblem() { return .unsafe(reason: problem) }
        return .safe(self, removed: [])
    }
    func keepingSecrets(of local: Self) -> Self { self }
}

/// Checks shared by the item types below.
private enum SettingsItemCheck {
    static let portRange: ClosedRange<Int> = 1...65_535

    /// Text no longer than a real value could be.
    static func tooLong(_ text: String, limit: Int = SettingsValueKind.defaultMaxStringLength) -> Bool {
        text.count > limit
    }
}

// MARK: SFTP servers (secrets: the password)

extension SFTPServerConfig: SettingsListItem {
    var settingsItemID: UUID { id }
    var settingsItemName: String { label.isEmpty ? host : label }

    /// The password is ALWAYS blanked; a key file path and "use the SSH
    /// agent" are kept (a path is not a secret, and the key file itself never
    /// leaves the Mac).
    func exportForm() -> SettingsItemExportForm<SFTPServerConfig> {
        var copy = self
        var removed: [String] = []
        if case .password(let password) = authMethod {
            copy.authMethod = .password("")
            if !password.isEmpty {
                removed.append("the password saved in the settings file for SFTP server "
                    + "“\(settingsItemName)” was left out")
            }
        }
        if let problem = copy.importProblem() { return .unsafe(reason: problem) }
        return .safe(copy, removed: removed)
    }

    func importProblem() -> String? {
        if case .password(let password) = authMethod, !password.isEmpty {
            return "it carries a password, and settings files never carry passwords"
        }
        if !SettingsItemCheck.portRange.contains(port) { return "its port should be between 1 and 65535" }
        if let problem = SettingsAddressCheck.problem(in: host) { return "its host is refused: \(problem)" }
        if SettingsItemCheck.tooLong(host) || SettingsItemCheck.tooLong(username)
            || SettingsItemCheck.tooLong(remotePath) || SettingsItemCheck.tooLong(label) {
            return "a field is longer than any real value could be"
        }
        if case .keyFile(let path) = authMethod, let problem = SettingsValueCodec.filePathProblem(path) {
            return "its key file path is refused: \(problem)"
        }
        return nil
    }

    /// Keeps a password this Mac still holds in the settings file itself
    /// (never moved to the Keychain), when the file's copy of the same
    /// server has the blank one every file has.
    func keepingSecrets(of local: SFTPServerConfig) -> SFTPServerConfig {
        guard case .password(let incoming) = authMethod, incoming.isEmpty,
              case .password(let localPassword) = local.authMethod, !localPassword.isEmpty else {
            return self
        }
        var copy = self
        copy.authMethod = .password(localPassword)
        return copy
    }
}

// MARK: Cloud destinations (secrets: access token / access key ID, refresh token, S3 secret key)

extension CloudStorageConfig: SettingsListItem {
    var settingsItemID: UUID { id }
    var settingsItemName: String { label.isEmpty ? provider.rawValue : label }

    /// All three secret fields are blanked, whatever the stored list holds
    /// (`CloudStorageView.persistConfigs` already blanks them before saving,
    /// but the export does not rely on that).
    func exportForm() -> SettingsItemExportForm<CloudStorageConfig> {
        var copy = self
        var removed: [String] = []
        if !accessToken.isEmpty || refreshToken?.isEmpty == false || secretAccessKey?.isEmpty == false {
            removed.append("the keys or tokens saved in the settings file for cloud destination "
                + "“\(settingsItemName)” were left out")
        }
        copy.accessToken = ""
        copy.refreshToken = nil
        copy.secretAccessKey = nil
        if let problem = copy.importProblem() { return .unsafe(reason: problem) }
        return .safe(copy, removed: removed)
    }

    func importProblem() -> String? {
        if !accessToken.isEmpty || refreshToken?.isEmpty == false || secretAccessKey?.isEmpty == false {
            return "it carries a key or token, and settings files never carry them"
        }
        if let endpoint, let problem = SettingsAddressCheck.problem(in: endpoint) {
            return "its endpoint address is refused: \(problem)"
        }
        if SettingsItemCheck.tooLong(remotePath) || SettingsItemCheck.tooLong(label)
            || SettingsItemCheck.tooLong(bucket ?? "") || SettingsItemCheck.tooLong(region ?? "")
            || SettingsItemCheck.tooLong(endpoint ?? "") {
            return "a field is longer than any real value could be"
        }
        return nil
    }

    /// Keeps this Mac's secret fields when the file's copy has none, and
    /// only for the same kind of service (a token for one service is no use
    /// to another).
    func keepingSecrets(of local: CloudStorageConfig) -> CloudStorageConfig {
        guard accessToken.isEmpty, provider == local.provider,
              !local.accessToken.isEmpty || local.refreshToken?.isEmpty == false
                || local.secretAccessKey?.isEmpty == false else {
            return self
        }
        var copy = self
        copy.accessToken = local.accessToken
        copy.refreshToken = local.refreshToken
        copy.secretAccessKey = local.secretAccessKey
        return copy
    }
}

// MARK: Render-farm agents (no secret fields: name, host, port, SSH user name)

extension RenderFarmAgentInfo: SettingsListItem {
    var settingsItemID: UUID { id }
    var settingsItemName: String { displayName.isEmpty ? host : displayName }

    func importProblem() -> String? {
        if !SettingsItemCheck.portRange.contains(port) { return "its port should be between 1 and 65535" }
        if let problem = SettingsAddressCheck.problem(in: host) { return "its host is refused: \(problem)" }
        if SettingsItemCheck.tooLong(displayName) || SettingsItemCheck.tooLong(host)
            || SettingsItemCheck.tooLong(sshUsername ?? "") {
            return "a field is longer than any real value could be"
        }
        return nil
    }
}

// MARK: Conditional rules (no secret fields)

extension ConditionalRule: SettingsListItem {
    var settingsItemID: UUID { id }
    var settingsItemName: String { name }

    func importProblem() -> String? {
        SettingsItemCheck.tooLong(name) ? "its name is longer than any real name could be" : nil
    }
}

// MARK: Saved pipelines (no secret fields)

// A pipeline step's `config` values become FFmpeg ARGUMENTS
// (`PipelineExecutor.buildStepArguments`), passed as a list, never through a
// shell, so they cannot run a command. That is why pipelines may travel while
// hooks (which can run a shell script) never do.
extension EncodingPipeline: SettingsListItem {
    var settingsItemID: UUID { id }
    var settingsItemName: String { name }

    func importProblem() -> String? {
        SettingsItemCheck.tooLong(name) ? "its name is longer than any real name could be" : nil
    }
}

// MARK: Whole-value blobs owned by the app (shape only)

/// The shape of the app's `CustomTheme` (`ThemeManager.swift`). The engine
/// cannot see app types, so it carries the same four fields. If the app's
/// type gains a field, this shape drops it on export; that loses the new
/// field, never leaks anything, and the app's own test of these shapes is
/// the place to catch it (plan commit 8).
struct SettingsThemeShape: SettingsWholeBlob, Equatable {
    let id: UUID
    let name: String
    let accentHex: String
    let sidebarTintHex: String?

    func settingsProblem() -> String? {
        if name.count > 256 { return "its name is longer than any real name could be" }
        if !SettingsValueCodec.isHexColour(accentHex) { return "its accent colour should be written as #RRGGBB" }
        if let tint = sidebarTintHex, !SettingsValueCodec.isHexColour(tint) {
            return "its sidebar tint should be written as #RRGGBB"
        }
        return nil
    }
}

/// The shape of one of the app's `ShortcutBinding`s
/// (`KeyboardShortcutManager.swift`). Same reasoning as the theme.
struct SettingsShortcutShape: Codable, Sendable, Equatable {
    let id: UUID
    let action: String
    let label: String
    let key: String
    let modifiers: [String]
}

extension Array: SettingsWholeBlob where Element == SettingsShortcutShape {
    func settingsProblem() -> String? {
        if count > 1_000 { return "it has more shortcuts than the app could have" }
        var seen = Set<UUID>()
        for binding in self {
            if !seen.insert(binding.id).inserted { return "two shortcuts share one ID" }
            if binding.action.count > 256 || binding.label.count > 256 || binding.key.count > 32
                || binding.modifiers.count > 8 || binding.modifiers.contains(where: { $0.count > 32 }) {
                return "a shortcut has a field longer than any real value could be"
            }
        }
        return nil
    }
}

/// The email recipients: a list of addresses, stored by the app as TEXT
/// holding a JSON list (`EmailSettingsView.saveRecipients`), and written to
/// a settings file as a real JSON list.
struct SettingsEmailRecipients: SettingsWholeBlob, Equatable {
    let addresses: [String]

    init(addresses: [String]) { self.addresses = addresses }

    init(from decoder: Decoder) throws {
        addresses = try decoder.singleValueContainer().decode([String].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(addresses)
    }

    func settingsProblem() -> String? {
        if addresses.count > 1_000 { return "it has more recipients than any real list could have" }
        for address in addresses {
            if address.count > 320 { return "an address is longer than an email address can be" }
            if address.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                return "an address contains a line break or other control character"
            }
        }
        return nil
    }

    /// The text the app stores: `JSONEncoder().encode([String])` as UTF-8,
    /// the same encoder `EmailSettingsView` uses, so a value that went
    /// through an export and import is stored in exactly the app's own form.
    func storedText() throws -> String {
        String(decoding: try JSONEncoder().encode(addresses), as: UTF8.self)
    }
}

// MARK: - SettingsJSON (small helpers)

/// Conversions between typed models, `JSONValue` and bytes.
enum SettingsJSON {

    /// A typed model as a `JSONValue`, for placing inside a settings file.
    static func value<T: Encodable>(from model: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(model))
    }

    /// A `JSONValue` from a settings file, decoded into its real type. Any
    /// field the type does not declare is dropped here.
    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    /// The stored form of a checked model.
    static func encode<T: Encodable>(_ model: T) throws -> Data {
        try JSONEncoder().encode(model)
    }

    /// Bytes that are equal whenever two models hold the same data (keys
    /// sorted), for "does this differ from what is here?".
    static func canonical<T: Encodable>(_ model: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(model)
    }

    /// A decoding failure in plain English. Uses only the coding PATH, never
    /// the decoder's own description, which can quote the offending value.
    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return "it isn't in the expected form"
        }
        func place(_ path: [CodingKey]) -> String {
            let parts = path.map { key -> String in
                if let index = key.intValue { return "item \(index + 1)" }
                return "“\(key.stringValue)”"
            }
            return parts.isEmpty ? "the value" : parts.joined(separator: ", ")
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "\(place(context.codingPath + [key])) is missing"
        case .typeMismatch(_, let context):
            return "\(place(context.codingPath)) has the wrong type"
        case .valueNotFound(_, let context):
            return "\(place(context.codingPath)) is empty"
        case .dataCorrupted(let context):
            return "\(place(context.codingPath)) isn't one of the accepted values"
        @unknown default:
            return "it isn't in the expected form"
        }
    }
}
