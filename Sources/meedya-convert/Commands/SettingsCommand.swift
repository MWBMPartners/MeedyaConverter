// ============================================================================
// MeedyaConverter — CLI Settings Command (Issue #506 commit 7)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `meedya-convert settings export` and `meedya-convert settings import`:
// thin argument plumbing over the engine's `SettingsExporter` /
// `SettingsImporter` (Sources/ConverterEngine/Settings/…, #506 commits 4-6),
// following `DiscCommand`'s conventions (a parent command with subcommands,
// `AsyncParsableCommand`, `ExitCode`, `printStderr`, `--format text|json`).
// All the real logic — what is allowed to travel, redaction, validation,
// merge/replace, "what still needs entering" — lives in the engine. This
// file only: parses flags, picks WHICH settings file to read/write, and
// prints what the engine hands back.
//
// THE DOMAIN THIS COMMAND TARGETS, AND WHY IT IS NEVER `.standard`.
// `meedya-convert` is a separate program from the MeedyaConverter app.
// `UserDefaults.standard` inside a command-line tool is that TOOL's own,
// empty, settings — not the app's. (Two different programs each have their
// own "current user's defaults"; the name is shared, the storage is not.)
// So this command must name the app's settings domain explicitly, exactly
// as `SettingsDomain`'s own file overview says to. The app's bundle
// identifier for the Direct build is `AppInfo.Application.directBundleId`
// ("Ltd.MWBMpartners.MeedyaConverter"), found in
// `Sources/ConverterEngine/AppInfo.swift` — the plan (§6) names this exact
// constant, and it is also what `Sources/MeedyaConverter/Resources
// /Info.plist` ships as `CFBundleIdentifier` for that build, so it is the
// same settings file the Direct app itself reads and writes
// (`~/Library/Preferences/Ltd.MWBMpartners.MeedyaConverter.plist`).
//
// THE APP STORE LIMIT. The App Store build's bundle id
// (`AppInfo.Application.appStoreBundleId`, "…MeedyaConverter.Lite") runs
// inside a sandbox container, so its settings and its saved-key index live
// somewhere this unsandboxed command-line tool cannot reach at all (macOS's
// sandbox is what stops it, not a choice made here). This command therefore
// only ever works with the Direct build's settings. Said plainly in both
// subcommands' `--help` text, and in the "still needed" wording (a
// still-needed item is never told apart from "not saved anywhere" — see
// `SettingsCredentialNeeds.swift`'s file overview for why that is honest
// rather than a gap).
//
// KEYCHAIN: ATTRIBUTES ONLY, NEVER A SECRET. This command asks the Keychain
// only "does an item exist for this account?" (`SystemSettingsCredentialPresence`,
// which calls `APIKeyManager.hasStoredKey` — a STATIC method that never
// constructs an `APIKeyManager` and so never reads a saved secret out of the
// Keychain). It never requests `kSecReturnData`. Both subcommands' `--help`
// say this plainly, because the honest phrasing matters: someone reading
// "TMDB key: still needed" must not conclude this command looked at their
// key and found it wanting — it never looked at the key at all.
//
// TWO KINDS OF HIDDEN OPTIONS, FOR TESTS ONLY (`--help-hidden` to see them):
//   - `--defaults-suite` / `--profiles-dir`: point the settings domain and
//     the profiles folder at a throwaway location instead of the app's own,
//     exactly as the plan's §6 asks for. When either is set, the
//     "MeedyaConverter is open" guard below is skipped, because a test
//     writing to its own private domain has nothing to race with the real
//     app.
//   - `--api-keys-dir` / `--keychain-service`: redirect the "is an API key
//     saved?" check away from the REAL Keychain service
//     (`APIKeyManager.productionKeychainService`) and the real
//     `api_keys.json`. Without these, "is a TMDB key saved?" would ask the
//     real Keychain even when `--defaults-suite` points everything ELSE at
//     a test suite — the settings domain and the Keychain are two separate
//     systems, and only overriding one would leave a test quietly reading
//     the owner's actual Keychain. There is no equivalent override for the
//     SMTP password check (`SMTPPasswordKeychain`): its service name is a
//     fixed constant with no public seam to redirect it from outside the
//     engine module (see that type's own doc comment). Tests avoid this by
//     never selecting the "Connections" group where that check would run
//     with an unredirected service name; see `SettingsCommandProcessTests`.
// ---------------------------------------------------------------------------

import ArgumentParser
import AppKit
import Foundation
import ConverterEngine

// MARK: - Output format

/// Text or JSON output selector for the `settings` subcommands. Named
/// distinctly from `DiscOutputFormat` (same convention that file's own
/// comment describes) to avoid collisions between command families.
enum SettingsOutputFormat: String, ExpressibleByArgument, CaseIterable {
    case text
    case json
}

/// The one optional, off-by-default group `--include` can add. A named enum
/// (rather than a bare `--this-mac` flag) so a later group that is also off
/// by default has somewhere to go without a new flag name.
enum SettingsIncludeOption: String, ExpressibleByArgument, CaseIterable {
    case thisMac = "this-mac"
}

/// A CLI-local mirror of the engine's `SettingsImportMode`
/// (`Sources/ConverterEngine/Settings/SettingsValueCodecs.swift`), which has
/// no `ExpressibleByArgument` conformance of its own. `DiscCommand.swift`'s
/// `DiscSubmissionModeArgument` sets the precedent this follows: Swift 6
/// warns on adding a retroactive conformance to a type this module does not
/// own, so a small CLI-local enum with the same cases stands in for it at
/// the argument-parsing boundary, and is mapped to the engine type once.
enum SettingsImportModeArgument: String, ExpressibleByArgument, CaseIterable {
    case merge
    case replace

    var engineMode: SettingsImportMode {
        switch self {
        case .merge:   return .merge
        case .replace: return .replace
        }
    }
}

// MARK: - settings (parent)

/// `meedya-convert settings` — export and import MeedyaConverter's settings.
struct SettingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Export or import MeedyaConverter's settings.",
        discussion: """
            Moves your preferences, connection details and your own encoding \
            profiles between installations. Never writes a password, API \
            key, token or webhook address to the file — see \
            "settings export --help" and "settings import --help" for what \
            that means in practice, and for the Mac App Store limit.
            """,
        subcommands: [
            SettingsExportCommand.self,
            SettingsImportCommand.self,
        ]
    )
}

// MARK: - Shared support

/// Logic shared by `settings export` and `settings import`: which groups
/// were chosen, which settings file to use, and how an engine error maps to
/// an exit code. Free of any argument-parser type, so it is easy to test by
/// hand if it ever needs its own tests.
enum SettingsCommandSupport {

    /// A `--categories` list that named something this version doesn't
    /// know, or was empty.
    struct SelectionError: Error {
        let message: String
    }

    static var validCategoryNames: String {
        SettingsCategory.allCases.map(\.rawValue).joined(separator: ", ")
    }

    /// Works out which groups to act on: `--categories` (if given) is the
    /// WHOLE selection; otherwise the default is every group except "This
    /// Mac only" (`SettingsExporter.defaultCategories` — the plan's owner
    /// decision 3, applied identically here and in the engine). `--include
    /// this-mac` then adds "This Mac only" on top, either way, so someone
    /// who forgot to list it explicitly in `--categories` still gets it by
    /// asking with `--include`.
    static func resolveSelection(categories: String?, include: SettingsIncludeOption?) throws -> Set<SettingsCategory> {
        var selection: Set<SettingsCategory>
        if let categories {
            let names = categories.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !names.isEmpty else {
                throw SelectionError(message: "--categories needs at least one group: \(validCategoryNames).")
            }
            var parsed: Set<SettingsCategory> = []
            for name in names {
                guard let category = SettingsCategory(rawValue: name) else {
                    throw SelectionError(
                        message: "Unknown group “\(name)” for --categories. Choose from: \(validCategoryNames)."
                    )
                }
                parsed.insert(category)
            }
            selection = parsed
        } else {
            selection = SettingsExporter.defaultCategories
        }
        if include == .thisMac {
            selection.insert(.thisMac)
        }
        return selection
    }

    /// The settings file this command reads or writes: the app's own domain
    /// by default (see the file overview for why never `.standard`), or a
    /// throwaway suite when `suiteOverride` is given (tests only).
    static func domain(suiteOverride: String?) -> SettingsDomain {
        let name = suiteOverride ?? AppInfo.Application.directBundleId
        guard let defaults = UserDefaults(suiteName: name) else {
            // `UserDefaults(suiteName:)` only returns nil for an empty
            // name, which can't happen here: `name` is either a fixed,
            // non-empty constant or a caller-supplied suite name that
            // `ArgumentParser` has already required to be non-empty.
            fatalError("UserDefaults(suiteName:) refused “\(name)”.")
        }
        return SettingsDomain(defaults: defaults, name: name)
    }

    /// Plain English for any thrown error, preferring the engine's own
    /// `LocalizedError` message (which always ends "Nothing was changed."
    /// for an import failure) over Swift's generic description.
    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// Maps an import failure to this command's documented exit code. See
    /// the "Exit codes" table in this file's header comment on
    /// `SettingsImportCommand`.
    static func exitCode(for error: SettingsImportError) -> ExitCodes {
        switch error {
        case .fileTooLarge, .fileUnreadable:
            // The file couldn't be obtained at all — grouped with "not
            // found" rather than "invalid contents", since nothing about
            // its CONTENTS was ever examined.
            return .inputNotFound
        case .notJSON, .notASettingsFile, .newerFormat, .unsupportedFormat,
             .malformed, .invalidValue, .localValueUnreadable:
            return .validationFailed
        case .profileStoreWriteFailed, .internalSafetyCheckFailed:
            // Both are apply-time surprises outside the file's own contents
            // (a full disk; an internal consistency check firing, which
            // "should never happen" per its own doc comment) — the general
            // bucket, not "the file is bad".
            return .generalError
        }
    }

    /// Whether the Direct build of MeedyaConverter is currently running.
    /// Used only to refuse `--apply` (see `SettingsImportCommand.run()`):
    /// the app keeps some settings in memory and would silently overwrite
    /// an import the next time it saves one of them (the plan's §5 "reload"
    /// notes list exactly which). Checking the Direct bundle id only is
    /// correct because this command only ever touches the Direct build's
    /// settings domain (see the file overview) — the sandboxed App Store
    /// build, even if running, cannot see or race with a write there.
    static func isAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.Application.directBundleId).isEmpty
    }
}

// MARK: - settings export

/// `meedya-convert settings export <file>` — save this Mac's settings to a
/// file, in the groups chosen (default: every group except "This Mac
/// only").
struct SettingsExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Save this Mac's settings to a file.",
        discussion: """
            Writes your preferences, connection details and your own \
            encoding profiles to a JSON file you can bring to another Mac \
            with "meedya-convert settings import". By default this leaves \
            out "This Mac only" settings (where FFmpeg and other tools are \
            installed, and your CD drive's model and read offset) — add \
            --include this-mac to include them, but only if the other Mac \
            has the same tools in the same places and the same CD drive.

            A password, API key, token, webhook address or hook is NEVER \
            written to this file — not because this command reads the \
            Keychain and leaves those out, but because it never reads the \
            Keychain's secret data at all (it only checks, with the \
            Keychain's own attributes-only lookup, whether something is \
            saved, so the other Mac can be told what still needs entering).

            This reads the Direct build's own settings only. If you use \
            MeedyaConverter from the Mac App Store, its settings live inside \
            its own sandbox, invisible to this command-line tool — export \
            from Settings \u{203A} Import & Export inside that app instead.
            """
    )

    @Argument(help: "Where to write the settings file.")
    var file: String

    @Option(
        name: .customLong("categories"),
        help: "Comma-separated groups to export: general, encoding, encodingProfiles, connections, thisMac. Default: every group except thisMac."
    )
    var categories: String?

    @Option(name: .customLong("include"), help: "Also include a group that's off by default: this-mac.")
    var include: SettingsIncludeOption?

    @Option(name: .customLong("format"), help: "Output format: text (default) or json.")
    var outputFormat: SettingsOutputFormat = .text

    @Option(name: .customLong("defaults-suite"), help: .hidden)
    var defaultsSuite: String?

    @Option(name: .customLong("profiles-dir"), help: .hidden)
    var profilesDir: String?

    @Option(name: .customLong("api-keys-dir"), help: .hidden)
    var apiKeysDir: String?

    @Option(name: .customLong("keychain-service"), help: .hidden)
    var keychainService: String?

    func run() async throws {
        let selection: Set<SettingsCategory>
        do {
            selection = try SettingsCommandSupport.resolveSelection(categories: categories, include: include)
        } catch let error as SettingsCommandSupport.SelectionError {
            printStderr(error.message)
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        if selection.contains(.thisMac), let warning = SettingsCategory.thisMac.warning {
            printStderr("Warning: \(warning)")
        }

        let domain = SettingsCommandSupport.domain(suiteOverride: defaultsSuite)
        let profileStore = EncodingProfileStore(storageDirectory: profilesDir.map(URL.init(fileURLWithPath:)))
        let presence = SystemSettingsCredentialPresence(
            apiKeyStorageDirectory: apiKeysDir.map(URL.init(fileURLWithPath:)),
            apiKeyKeychainService: keychainService ?? APIKeyManager.productionKeychainService
        )
        let now = Date()
        let exporter = SettingsExporter(domain: domain, profileStore: profileStore, presence: presence, now: { now })

        let export: SettingsExport
        do {
            export = try exporter.write(to: URL(fileURLWithPath: file), categories: selection)
        } catch SettingsExportError.noGroupsChosen {
            printStderr(SettingsCommandSupport.describe(SettingsExportError.noGroupsChosen))
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        } catch {
            printStderr(SettingsCommandSupport.describe(error))
            throw ExitCode(ExitCodes.outputWriteError.rawValue)
        }

        switch outputFormat {
        case .text:
            print("Wrote \(file).")
            for line in export.reportLines { print(line) }
        case .json:
            let report = SettingsCLIReport.forExport(
                export, appVersion: ConverterEngine.version, generatedAt: now, file: file
            )
            emitJSON(report)
        }
    }
}

// MARK: - settings import

/// `meedya-convert settings import <file>` — preview, or (with `--apply`)
/// actually write, a settings file made by `settings export`.
///
/// **Exit codes** (`CLIUtilities.swift`'s `ExitCodes`; see
/// `SettingsCommandSupport.exitCode(for:)` for the exact mapping):
///   - `0`: previewed, or applied, successfully.
///   - `1`: MeedyaConverter is open (`--apply` only), or an unexpected
///     apply-time failure (a full disk saving profiles; an internal safety
///     check — see that error's own doc comment).
///   - `2`: bad arguments (an unknown `--categories` name, or none given).
///   - `3`: the file couldn't be obtained at all (missing, unreadable, or
///     over the 10 MB size limit) — nothing about its contents was read.
///   - `6`: the file's CONTENTS were refused (not JSON, not a settings
///     file, a newer format, or a bad value) — the whole file, always;
///     nothing is ever half-imported.
struct SettingsImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Preview, or apply, a settings file made by \"settings export\".",
        discussion: """
            Without --apply, this only shows what WOULD change — it writes \
            NOTHING. Add --apply once you're happy with the preview.

            --mode merge (the default) only changes what the file mentions; \
            anything the file doesn't mention stays exactly as it is on \
            this Mac. --mode replace makes the ticked groups match the file \
            exactly: settings, profiles, SFTP servers, cloud destinations \
            and other list items in those groups that the file doesn't \
            have are REMOVED. Either way, a password or key already saved \
            on this Mac is never touched, and a "never" setting (a \
            password, a hook, a consent) can never be planted by the file, \
            whatever it contains.

            This command never reads a password, key or token from the \
            Keychain — it only asks whether one exists (an attributes-only \
            check), so it can say what still needs entering on this Mac \
            without ever seeing a secret.

            This reads and writes the Direct build's own settings only. Run \
            against a Mac that uses the Mac App Store version of \
            MeedyaConverter, this command cannot see that app's settings or \
            saved keys, and will list them as still needed even when the \
            app already has them.
            """
    )

    @Argument(help: "The settings file to read.")
    var file: String

    @Flag(name: .customLong("apply"), help: "Write the change. Without this, only a preview is shown and nothing is written.")
    var apply = false

    @Option(
        name: .customLong("mode"),
        help: "merge (default): only add or update what the file has. replace: within the chosen groups, also remove what the file doesn't have."
    )
    var mode: SettingsImportModeArgument = .merge

    @Option(
        name: .customLong("categories"),
        help: "Comma-separated groups to import: general, encoding, encodingProfiles, connections, thisMac. Default: every group in the file except thisMac."
    )
    var categories: String?

    @Option(name: .customLong("include"), help: "Also include a group that's off by default: this-mac.")
    var include: SettingsIncludeOption?

    @Option(name: .customLong("format"), help: "Output format: text (default) or json.")
    var outputFormat: SettingsOutputFormat = .text

    @Option(name: .customLong("defaults-suite"), help: .hidden)
    var defaultsSuite: String?

    @Option(name: .customLong("profiles-dir"), help: .hidden)
    var profilesDir: String?

    @Option(name: .customLong("api-keys-dir"), help: .hidden)
    var apiKeysDir: String?

    @Option(name: .customLong("keychain-service"), help: .hidden)
    var keychainService: String?

    func run() async throws {
        let selection: Set<SettingsCategory>
        do {
            selection = try SettingsCommandSupport.resolveSelection(categories: categories, include: include)
        } catch let error as SettingsCommandSupport.SelectionError {
            printStderr(error.message)
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        if selection.contains(.thisMac), let warning = SettingsCategory.thisMac.warning {
            printStderr("Warning: \(warning)")
        }

        // The hidden test options point every part of this run at a
        // throwaway world, so there is nothing real for the running app to
        // race with — see the file overview.
        let usingTestOverrides = defaultsSuite != nil || profilesDir != nil
            || apiKeysDir != nil || keychainService != nil
        if apply, !usingTestOverrides, SettingsCommandSupport.isAppRunning() {
            printStderr(
                "MeedyaConverter is open. Quit it first: it keeps some settings in memory and would "
                    + "overwrite what you import the next time it saves."
            )
            throw ExitCode(ExitCodes.generalError.rawValue)
        }

        let url = URL(fileURLWithPath: file)
        let plan: SettingsImportPlan
        do {
            plan = try SettingsImporter.prepare(contentsOf: url)
        } catch let error as SettingsImportError {
            printStderr(SettingsCommandSupport.describe(error))
            throw ExitCode(SettingsCommandSupport.exitCode(for: error).rawValue)
        }

        let domain = SettingsCommandSupport.domain(suiteOverride: defaultsSuite)
        let profileStore = EncodingProfileStore(storageDirectory: profilesDir.map(URL.init(fileURLWithPath:)))
        let presence = SystemSettingsCredentialPresence(
            apiKeyStorageDirectory: apiKeysDir.map(URL.init(fileURLWithPath:)),
            apiKeyKeychainService: keychainService ?? APIKeyManager.productionKeychainService
        )
        let importer = SettingsImporter(domain: domain, profileStore: profileStore, presence: presence)
        let preview = importer.preview(plan, selection: selection, mode: mode.engineMode)
        let generatedAt = Date()

        guard apply else {
            switch outputFormat {
            case .text:
                printPreviewText(plan: plan, preview: preview)
            case .json:
                emitJSON(SettingsCLIReport.forImportPreview(
                    preview, appVersion: ConverterEngine.version, generatedAt: generatedAt, file: file
                ))
            }
            return
        }

        // Replace mode: the removal counts are shown as part of the SAME
        // report --apply prints (the block above already put
        // `replaceConfirmation` into `preview`), so they are always in the
        // command's output before the "Imported …" lines that follow — the
        // plan's "prints the removal counts first". No separate --yes gate:
        // the plan designed --apply itself as the one deliberate step
        // ("without an interactive prompt" — owner decision 5), and
        // `--mode replace --apply` is already two explicit flags naming
        // exactly what is wanted; adding a second gate on top would be the
        // interactive confirmation the plan chose not to have.
        let result: SettingsImportResult
        do {
            result = try importer.apply(plan, selection: selection, mode: mode.engineMode)
        } catch let error as SettingsImportError {
            printStderr(SettingsCommandSupport.describe(error))
            throw ExitCode(SettingsCommandSupport.exitCode(for: error).rawValue)
        }

        switch outputFormat {
        case .text:
            printAppliedText(plan: plan, preview: preview, result: result)
        case .json:
            emitJSON(SettingsCLIReport.forImportResult(
                result, preview: preview, appVersion: ConverterEngine.version, generatedAt: generatedAt, file: file
            ))
        }
    }

    // MARK: Text output

    /// Everything a preview shows: the source, the mode, one row per group,
    /// warnings, cross-checks, the replace confirmation, and — because
    /// nothing further happens — the ignored items and the closing
    /// sentence. `ignored` is printed HERE ONLY (never again for `--apply`,
    /// where `result.reportLines` prints it instead), so it is never shown
    /// twice.
    private func printPreviewText(plan: SettingsImportPlan, preview: SettingsImportPreview) {
        printCommonPreview(plan: plan, preview: preview)
        print("")
        if !preview.ignored.isEmpty {
            print("Not imported (\(preview.ignored.count)):")
            for item in preview.ignored { print("  - \(item.explanation)") }
            print("")
        }
        print("Nothing has been changed. Run again with --apply to import.")
    }

    /// The same header as a preview, followed by the result's own report
    /// lines (imported/removed counts, "still needed", "next launch", and —
    /// the one and only place it is printed for an applied import — the
    /// ignored items).
    private func printAppliedText(plan: SettingsImportPlan, preview: SettingsImportPreview, result: SettingsImportResult) {
        printCommonPreview(plan: plan, preview: preview)
        print("")
        for line in result.reportLines { print(line) }
    }

    private func printCommonPreview(plan: SettingsImportPlan, preview: SettingsImportPreview) {
        print(plan.sourceDescription)
        print("Mode: \(preview.mode.rawValue)")
        print("")
        for group in preview.groups {
            let mark = group.isSelected ? "[x]" : "[ ]"
            print("\(mark) \(group.category.displayName): \(group.summary)")
        }
        if !preview.warnings.isEmpty {
            print("")
            print("Warnings:")
            for warning in preview.warnings { print("  - \(warning)") }
        }
        if !preview.crossChecks.isEmpty {
            print("")
            for line in preview.crossChecks { print(line) }
        }
        if let confirmation = preview.replaceConfirmation {
            print("")
            print(confirmation)
        }
    }
}

// MARK: - Shared JSON emission

/// Prints a `JSONValue` report to stdout via `SettingsCLIReport.encode`.
/// Both subcommands share this so a future change to the encoding (say,
/// `ISO8601` precision) only needs one call site.
private func emitJSON(_ report: JSONValue) {
    if let data = try? SettingsCLIReport.encode(report), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}
