// ============================================================================
// MeedyaConverter — SettingsKeyEntry and friends (Issue #506 commit 4)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// The shapes used by `SettingsKeyRegistry` to record ONE deliberate decision
// for every setting MeedyaConverter stores in its settings file
// (`UserDefaults`), and for every file it keeps in Application Support.
//
// Every stored setting gets exactly one of three decisions:
//
//   .allowed(group, rules)   exported and imported, in that group, when the
//                            person ticks the group;
//   .thisMac(rules, reason)  describes this particular Mac; exported only when
//                            "This Mac only" is ticked, which is off by default;
//   .never(kind, reason)     never written to a settings file and never read
//                            from one, whatever the file says.
//
// Why an allow-list and not a deny-list: with an allow-list, a setting nobody
// thought about is simply left out, which is the safe mistake. With a
// deny-list, a new setting nobody thought about (say, a new API key added in
// a hurry) would be exported by default, which is the dangerous mistake.
// The "never" entries are still written down, with reasons, so that the
// tripwire test (`SettingsKeyCoverageTests`) can tell "decided: never" apart
// from "nobody decided", and so the app can list what is never included.
//
// What this file does NOT do: it only records rules. Nothing here reads a
// setting, writes one, or checks a value against its rules. The exporter and
// importer that apply these rules are a later commit of #506 (commit 5 in
// `.claude/plans/settings-export-import-plan.md`).
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsKeyEntry

/// One stored setting and the decision made about it.
public struct SettingsKeyEntry: Sendable, Equatable {

    /// The exact name the setting is stored under in `UserDefaults`.
    public let key: String

    /// What the setting is, in plain English. Also used later as the
    /// description in the settings file's JSON Schema.
    public let label: String

    /// Where a person sees or changes it, e.g. "Settings › Email", or a note
    /// that no screen shows it.
    public let location: String

    /// Exported, This Mac only, or never.
    public let decision: SettingsKeyDecision

    public init(key: String, label: String, location: String, decision: SettingsKeyDecision) {
        self.key = key
        self.label = label
        self.location = location
        self.decision = decision
    }

    // MARK: Convenience readers

    /// The group this setting is exported in: its group for `.allowed`,
    /// `.thisMac` for `.thisMac`, and `nil` for `.never`.
    public var category: SettingsCategory? {
        switch decision {
        case .allowed(let category, _): return category
        case .thisMac:                  return .thisMac
        case .never:                    return nil
        }
    }

    /// The value rules, for any setting that can be exported (`nil` for
    /// `.never`, which has no rules because it never travels).
    public var rules: SettingsValueRules? {
        switch decision {
        case .allowed(_, let rules):    return rules
        case .thisMac(let rules, _):    return rules
        case .never:                    return nil
        }
    }

    /// Why this setting is never exported, or `nil` if it can be.
    public var neverKind: SettingsNeverKind? {
        if case .never(let kind, _) = decision { return kind }
        return nil
    }

    /// `true` for `.allowed` and `.thisMac`; `false` for `.never`.
    public var canBeExported: Bool { rules != nil }
}

// MARK: - SettingsKeyDecision

/// The one decision recorded for a stored setting.
public enum SettingsKeyDecision: Sendable, Equatable {

    /// Exported and imported in `category`, when the person ticks it.
    ///
    /// `category` is one of `.general`, `.encoding` or `.connections`.
    /// Not `.thisMac` (use the `.thisMac` decision, which also records why)
    /// and not `.encodingProfiles` (that group is a file, not settings keys).
    /// `SettingsKeyRegistrySentinelTests` enforces both.
    case allowed(SettingsCategory, SettingsValueRules)

    /// Describes the Mac the setting was made on. Exported only when "This
    /// Mac only" is ticked (off by default). `reason` says why it is tied to
    /// this Mac.
    case thisMac(SettingsValueRules, reason: String)

    /// Never exported and never imported. `kind` groups the reason (a
    /// credential, a consent, …); `reason` explains it in plain English.
    case never(SettingsNeverKind, reason: String)
}

// MARK: - SettingsNeverKind

/// The broad reason a setting is never exported. The plain-English `reason`
/// on each `.never` entry gives the specific one.
public enum SettingsNeverKind: String, Sendable, CaseIterable {

    /// A password, key or token, or an address that works like one (a Slack
    /// or Discord webhook address lets anyone who has it post to the channel).
    case credential

    /// Where an older version kept a credential. The credential itself has
    /// moved (for example into the Keychain); the name stays decided as
    /// "never" so a settings file can never put a credential back there.
    case legacyCredential

    /// An agreement or opt-in the person using that Mac has to give on that
    /// Mac: accepting MakeMKV's terms, allowing unencrypted connections to the
    /// render farm, agreeing to share usage data.
    case consent

    /// Could make MeedyaConverter run a program, send data somewhere, or
    /// delete files. Hooks can do all three.
    case runsCommands

    /// A cached answer about the licence. Importing one could unlock paid
    /// features on a Mac that has not paid for them.
    case licenceCache

    /// Identifies this particular installation (the anonymous analytics ID).
    /// A copy would make two Macs look like one.
    case installationIdentity

    /// Describes the last file worked on, not a preference (for example the
    /// last clip's trim points). Meaningless for a different file.
    case lastFileOnly

    /// Something the app keeps for itself: a record that a one-time screen
    /// was seen, or an older copy of another setting that the app rewrites
    /// from that setting.
    case appBookkeeping

    /// Nothing a person can see or change in the app sets it: the screen was
    /// removed or hidden, or nothing calls the code that sets it. The rule
    /// used by the plan: a setting is exported only if a person can see and
    /// change it in the app.
    case noScreenChangesIt

    /// A one-line summary, used when listing what is never included.
    public var summary: String {
        switch self {
        case .credential:           return "It is a password, key or token, or works like one."
        case .legacyCredential:     return "An older version kept a password or key here."
        case .consent:              return "It has to be agreed to on each Mac."
        case .runsCommands:         return "It could run a program, send data, or delete files."
        case .licenceCache:         return "It could unlock paid features."
        case .installationIdentity: return "It identifies this particular installation."
        case .lastFileOnly:         return "It describes the last file you worked on."
        case .appBookkeeping:       return "The app keeps it for itself."
        case .noScreenChangesIt:    return "Nothing in the app lets you change it."
        }
    }
}

// MARK: - SettingsValueRules

/// What an exportable setting's value may be, whether importing it deserves
/// a warning, and when a newly imported value takes effect.
public struct SettingsValueRules: Sendable, Equatable {

    /// The type of value, with any limits.
    public let kind: SettingsValueKind

    /// A caution to show when the imported value is a risky one, or `nil`.
    public let importWarning: SettingsImportWarning?

    /// Whether the running app notices a new value straight away, or only
    /// the next time it opens.
    public let takesEffect: SettingsTakesEffect

    public init(
        kind: SettingsValueKind,
        importWarning: SettingsImportWarning? = nil,
        takesEffect: SettingsTakesEffect = .immediately
    ) {
        self.kind = kind
        self.importWarning = importWarning
        self.takesEffect = takesEffect
    }
}

// MARK: - SettingsValueKind

/// The type of value a setting holds, with any limits the importer must
/// apply before writing it.
public enum SettingsValueKind: Sendable, Equatable {

    /// true or false.
    case bool

    /// A whole number, optionally limited to a range.
    case int(ClosedRange<Int>?)

    /// A decimal number, optionally limited to a range.
    case double(ClosedRange<Double>?)

    /// Text. When `allowed` is not `nil`, only those exact values are
    /// accepted (for example the three appearance modes). `maxLength` is a
    /// sanity limit on anything longer than a real value could be.
    case string(allowed: [String]?, maxLength: Int)

    /// A web or git address. Rule: it must never carry a user name or
    /// password inside it (`https://user:password@host/…`, or
    /// `https://<token>@github.com/…`, a common way of embedding a GitHub
    /// token). Such an address is never exported, and is refused on import.
    case address

    /// The full path to a program on this Mac, or empty for "find it
    /// automatically". Only used by This Mac settings.
    case filePath

    /// A colour written as `#RRGGBB`, the form `ThemeManager` stores.
    case hexColour

    /// A list or object stored as JSON (see `SettingsJSONBlob`).
    case json(SettingsJSONBlob)

    /// The sanity limit used for ordinary text settings.
    public static let defaultMaxStringLength = 4096

    /// Plain text with no fixed list of values and the usual length limit.
    public static let text: SettingsValueKind = .string(allowed: nil, maxLength: defaultMaxStringLength)

    /// Text that must be one of `values`.
    public static func oneOf(_ values: [String]) -> SettingsValueKind {
        .string(allowed: values, maxLength: defaultMaxStringLength)
    }
}

// MARK: - SettingsJSONBlob

/// A setting whose value is a JSON document (a list of servers, rules, …)
/// rather than a single value. Each one is exported by decoding it into its
/// real Swift type, so checks and redaction work on typed fields rather than
/// raw bytes. The decoders ("codecs") are a later commit of #506; this enum
/// only names each blob and records the facts that matter for safety.
public enum SettingsJSONBlob: String, Sendable, CaseIterable {

    /// The chosen colour theme. App type `CustomTheme`
    /// (`Sources/MeedyaConverter/Components/ThemeManager.swift`).
    case customTheme

    /// Keyboard shortcuts. App type `[ShortcutBinding]`
    /// (`Sources/MeedyaConverter/Services/KeyboardShortcutManager.swift`).
    case keyboardShortcuts

    /// Conditional rules. Engine type `[ConditionalRule]`.
    case conditionalRules

    /// Saved encoding pipelines. Engine type `[EncodingPipeline]`.
    case encodingPipelines

    /// Render-farm agents the person added. Engine type
    /// `[RenderFarmAgentInfo]`: name, host, port and SSH user name. It has
    /// no password or key field.
    case renderFarmAgents

    /// SFTP servers. Engine type `[SFTPServerConfig]`. Can still contain a
    /// plaintext password: the only code that moves an old plaintext
    /// password into the Keychain runs when the SFTP screen is opened, so a
    /// person who upgraded and never opened it still has one here.
    case sftpProfiles

    /// Cloud storage destinations. Engine type `[CloudStorageConfig]`.
    /// Has `accessToken`, `refreshToken` and `secretAccessKey` fields.
    /// `CloudStorageView` already blanks them before saving, but the export
    /// must not rely on that.
    case cloudStorageProfiles

    /// Email recipients: a JSON list of addresses stored as TEXT (not as
    /// binary data like the others).
    case emailRecipients

    /// How the blob sits in the settings file.
    public enum Storage: String, Sendable {
        /// Stored as binary `Data` holding UTF-8 JSON.
        case data
        /// Stored as a `String` holding JSON.
        case jsonString
    }

    /// How the blob sits in the settings file.
    public var storage: Storage {
        switch self {
        case .emailRecipients:
            return .jsonString
        case .customTheme, .keyboardShortcuts, .conditionalRules, .encodingPipelines,
             .renderFarmAgents, .sftpProfiles, .cloudStorageProfiles:
            return .data
        }
    }

    /// `true` when the stored blob can contain a secret that the exporter
    /// must remove itself, field by field, before anything is written, and
    /// that the importer must refuse if a file carries one.
    ///
    /// This is a requirement on the later exporter, recorded here so it is
    /// pinned by a test now (`SettingsKeyRegistrySentinelTests`) rather than
    /// remembered.
    public var mustRemoveSecretsOnExport: Bool {
        switch self {
        case .sftpProfiles, .cloudStorageProfiles:
            return true
        case .customTheme, .keyboardShortcuts, .conditionalRules, .encodingPipelines,
             .renderFarmAgents, .emailRecipients:
            return false
        }
    }
}

// MARK: - SettingsImportWarning

/// A caution shown before importing a value that changes something risky.
public enum SettingsImportWarning: Sendable, Equatable {

    /// Shown when a true/false setting is being set to true.
    case whenTrue(String)

    /// Shown when a text setting is being set to exactly `value`.
    case whenValue(String, message: String)
}

// MARK: - SettingsTakesEffect

/// When the running app notices an imported value.
public enum SettingsTakesEffect: String, Sendable {

    /// Read fresh whenever it is used, so an import applies straight away.
    case immediately

    /// Read once when the app opens (and in some cases written back whole
    /// later), so an import only applies the next time MeedyaConverter
    /// opens. The later import screen lists these.
    case nextLaunch
}

// MARK: - File stores

/// One file or folder MeedyaConverter keeps in
/// `~/Library/Application Support/MeedyaConverter/`, and the decision about
/// it.
public struct SettingsFileStoreEntry: Sendable, Equatable {

    /// The path inside `~/Library/Application Support/MeedyaConverter/`.
    /// A trailing `/` means a folder.
    public let path: String

    /// The name of the source file that builds this path. The tripwire test
    /// uses it to check that every file asking macOS for the Application
    /// Support folder has a decision here.
    public let sourceFile: String

    /// What the file holds, in plain English.
    public let label: String

    /// Exported in a group, or never exported.
    public let decision: SettingsFileStoreDecision

    public init(path: String, sourceFile: String, label: String, decision: SettingsFileStoreDecision) {
        self.path = path
        self.sourceFile = sourceFile
        self.label = label
        self.decision = decision
    }
}

/// The decision about one Application Support file or folder.
public enum SettingsFileStoreDecision: Sendable, Equatable {
    /// Exported and imported as part of `category`.
    case allowed(SettingsCategory)
    /// Never exported, for `reason`.
    case never(reason: String)
}
