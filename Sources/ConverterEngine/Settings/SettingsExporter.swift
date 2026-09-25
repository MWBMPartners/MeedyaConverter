// ============================================================================
// MeedyaConverter — SettingsExporter (Issue #506 commit 5)
// Sources/ConverterEngine/Settings/SettingsExporter.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Writes a settings file from the ticked groups. The app and the
// command-line tool both call `write(to:categories:)`, so there is one path.
//
// What is NEVER in the file, and why (the registry's "never" decisions, all
// enforced by only ever looking at the registry's allowed entries):
//   - passwords, API keys, tokens: they live in the Keychain and are never
//     read here; SFTP and cloud lists have their secret fields blanked field
//     by field (see `SettingsValueCodecs.swift`);
//   - the webhook address and custom headers: for Slack and Discord the
//     address works like a password, and people put tokens in the headers;
//   - hooks (`postEncodeActionChain`): they can run a shell script, call a
//     web address or move the source to the Trash after every encode (owner
//     decision: left out of this version entirely);
//   - consents (MakeMKV terms, the render-farm unencrypted opt-in, sharing
//     usage data): they have to be given on each Mac;
//   - the cached licence level (could unlock paid features) and the
//     anonymous analytics ID (identifies one installation);
//   - addresses carrying a user name, password or query string;
//   - settings written by frameworks (Sparkle, window positions, the last
//     folder a file panel showed): the code never names them, so the
//     allow-list never includes them.
//
// What IS in it: only the allowed settings that are actually stored in this
// settings file (a setting still at its default is not written, so the
// importing Mac keeps its own default), the person's own encoding profiles
// (never the built-in ones), and the names of left-out things that were set
// up here (`notIncluded`), so the other Mac can say what still needs
// entering. "This Mac only" is included only when ticked; it is off by
// default (owner decision 3).
//
// Before returning, the exporter reads its own output back through
// `SettingsImporter.prepare`. If the importer would refuse it, nothing is
// written and `selfCheckFailed` is thrown. So it can never save a file it
// would itself refuse, and the importer's checks (no password in an SFTP
// server, no token in a cloud destination, no credential in an address)
// run a second time over everything written.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsExport

/// A finished export: the file's bytes, and what went into them.
public struct SettingsExport: Sendable, Equatable {
    /// The file, ready to save.
    public let data: Data
    /// The groups written, in the usual order.
    public let categories: [SettingsCategory]
    /// How many settings (or profiles) each group holds.
    public let itemCounts: [SettingsCategory: Int]
    /// What was left out or removed on the way, in plain English.
    public let notes: [SettingsExportNote]
    /// Left-out things that were set up here, named in the file.
    public let leftOut: [SettingsLeftOutItem]

    /// The export report, one line each.
    public var reportLines: [String] {
        var lines = categories.map { category -> String in
            let noun = category == .encodingProfiles ? "profile" : "setting"
            return "\(category.displayName): \(SettingsImportReport.count(itemCounts[category] ?? 0, noun))"
        }
        lines.append("Passwords and API keys are never included: you enter those again on the other Mac.")
        if !notes.isEmpty {
            lines.append("Left out or removed:")
            lines += notes.map { "  - \($0.message)" }
        }
        return lines
    }
}

// MARK: - SettingsExporter

/// Builds and saves settings files. See the file overview.
public struct SettingsExporter: Sendable {

    /// Every group except "This Mac only" (owner decision 3: off by default
    /// on export as well as import).
    public static let defaultCategories: Set<SettingsCategory> =
        Set(SettingsCategory.allCases.filter(\.includedByDefault))

    let domain: SettingsDomain
    let profileStore: EncodingProfileStore
    let presence: any SettingsCredentialPresence
    let appVersion: String
    let now: @Sendable () -> Date

    /// - Parameters:
    ///   - domain: The settings file to read. There is deliberately no
    ///     default: see `SettingsDomain` for why `.standard` would be wrong
    ///     in the command-line tool.
    ///   - profileStore: Where the person's profiles come from.
    ///   - presence: Used only to fill `notIncluded` (which left-out things
    ///     are set up here). Answers without reading any secret.
    ///   - appVersion: Written into the file for the importing Mac to show.
    ///   - now: The clock, so tests get a fixed date.
    public init(
        domain: SettingsDomain,
        profileStore: EncodingProfileStore,
        presence: any SettingsCredentialPresence,
        appVersion: String = AppInfo.Version.number,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.domain = domain
        self.profileStore = profileStore
        self.presence = presence
        self.appVersion = appVersion
        self.now = now
    }

    /// Builds the file for `categories`, checked by the importer, without
    /// saving it.
    public func makeExport(categories: Set<SettingsCategory>) throws -> SettingsExport {
        guard !categories.isEmpty else { throw SettingsExportError.noGroupsChosen }

        // One snapshot of this domain only (never macOS-wide or registered
        // defaults; see `SettingsDomain.snapshot`).
        let source = SettingsExportSource(snapshot: domain.snapshot(), profileStore: profileStore)

        let chosen = SettingsCategory.allCases.filter { categories.contains($0) }
        var payloads: [String: JSONValue] = [:]
        var counts: [SettingsCategory: Int] = [:]
        var notes: [SettingsExportNote] = []
        for category in chosen {
            let section: SettingsExportedSection
            do {
                section = try SettingsSectionHandlers.handler(for: category).export(from: source)
            } catch {
                throw SettingsExportError.encodingFailed(reason: "“\(category.displayName)”: \(error.localizedDescription)")
            }
            payloads[category.rawValue] = section.payload
            counts[category] = section.itemCount
            notes += section.notes
        }

        let leftOut = SettingsLocalSetup.itemsSetUp(domain: domain, presence: presence, categories: categories)

        let data: Data
        do {
            data = try SettingsDocument.makeData(
                exportedAt: now(),
                appVersion: appVersion,
                categories: payloads,
                notIncluded: leftOut.map(\.rawValue)
            )
        } catch {
            throw SettingsExportError.encodingFailed(reason: error.localizedDescription)
        }

        // The self-check: the importer must accept every byte of it.
        do {
            _ = try SettingsImporter.prepare(data)
        } catch {
            throw SettingsExportError.selfCheckFailed(
                reason: (error as? LocalizedError)?.errorDescription ?? String(describing: type(of: error))
            )
        }

        return SettingsExport(data: data, categories: chosen, itemCounts: counts, notes: notes, leftOut: leftOut)
    }

    /// The file's bytes for `categories` (see `makeExport`).
    public func makeData(categories: Set<SettingsCategory>) throws -> Data {
        try makeExport(categories: categories).data
    }

    /// Builds the file and saves it to `url` in one atomic step: either the
    /// whole file is there afterwards, or nothing changed at `url`.
    @discardableResult
    public func write(to url: URL, categories: Set<SettingsCategory>) throws -> SettingsExport {
        let export = try makeExport(categories: categories)
        do {
            try export.data.write(to: url, options: .atomic)
        } catch {
            throw SettingsExportError.writeFailed(reason: error.localizedDescription)
        }
        return export
    }
}
