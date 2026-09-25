// ============================================================================
// MeedyaConverter — SettingsImporter (Issue #506 commit 5)
// Sources/ConverterEngine/Settings/SettingsImporter.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Reads a settings file in three separate steps, so nothing is ever written
// that has not been checked and shown first:
//
//   1. `prepare` checks the WHOLE file and writes nothing. It needs nothing
//      from this Mac, so it is static: the exporter also runs its own output
//      through it before saving (it can never write a file it would refuse).
//      One bad value refuses the whole file.
//   2. `preview` compares the file with this Mac, group by group: what is
//      new, what differs, what "Replace" would remove, warnings (such as
//      "Delete source after successful encode: ON"), and cross-checks (such
//      as a default profile that won't exist here). It writes nothing.
//   3. `apply` writes, only the ticked groups, in merge or replace mode.
//
// How `apply` stays all-or-nothing. It works out EVERY change first, from a
// snapshot, before writing anything; anything that can go wrong there (this
// Mac's list can't be read, a safety check) throws with nothing written.
// Then it writes in a fixed order:
//   a. the profiles file, the ONLY write that can fail (a full disk, a
//      permissions problem). `EncodingProfileStore` writes it atomically and
//      updates its memory only after the write succeeded, and throws on
//      failure; if it throws, nothing else has been written yet.
//   b. the settings (`UserDefaults.set` / `removeObject`), which cannot fail.
// Doing b before a would leave the settings changed and the profiles not
// whenever the profile write failed: exactly the half-applied import this
// order prevents. A test makes the profile write fail and checks that the
// settings did not change.
//
// What `apply` never writes, whatever the file says: a setting the registry
// does not allow (unknown, or "never"), a setting outside the ticked groups,
// a password, key or token. Unknown and "never" settings were already set
// aside by `prepare` (reported, never written); `apply` checks again,
// against the registry, before its first write.
//
// Merge and replace:
//   - Merge: only settings in the file change. Lists (SFTP servers, cloud
//     destinations, render-farm agents, conditional rules, saved pipelines)
//     are merged by each item's `id`: the file's items are added or update
//     the matching item, and this Mac's other items stay. (Merging "only the
//     keys present" would REPLACE a whole list and delete this Mac's other
//     items.) Profiles are merged by `id` the same way.
//   - Replace, within the ticked groups only: settings the file doesn't have
//     go back to their defaults (they are removed, never written as a
//     "default" value, so a setting whose missing value means "on", such as
//     `useHardwareAcceleration`, keeps meaning "on"); list items and
//     profiles the file doesn't have are removed.
//   - Neither ever touches a "never" setting, a Keychain item, or a group
//     that was not ticked. A removed SFTP server's Keychain password is left
//     where it is (removing Keychain items is not this code's business).
//
// Honest limits:
//   - It does not coordinate with another program writing the same settings
//     at the same moment. The app keeps some settings in memory and writes
//     them back later (plan section 5), which is why several are marked
//     "takes effect next launch" and why the command-line tool will refuse to
//     import while the app is open (plan commit 7).
//   - Profiles are written through the `EncodingProfileStore` passed in. The
//     app must pass its LIVE store, never a new one: a second store would not
//     see the other's changes (plan section 5).
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsImportPlan

/// A checked settings file, ready to preview and apply. Made only by
/// `SettingsImporter.prepare`, so everything in it has passed every check.
public struct SettingsImportPlan: Sendable {

    /// The file's format version.
    public let formatVersion: Int
    /// When the file was made, if it says.
    public let exportedAt: Date?
    /// The version of MeedyaConverter that made it, if it says.
    public let appVersion: String?
    /// The groups in the file that this version knows, in the usual order.
    public let categoriesInFile: [SettingsCategory]
    /// Everything in the file that will not be imported, and why.
    public let ignored: [SettingsIgnoredItem]
    /// Things set up on the other Mac that are never copied (names only).
    public let leftOut: [SettingsLeftOutItem]

    /// The checked contents of each known group.
    let sections: [SettingsCategory: SettingsValidatedSection]

    /// The groups to tick at first: every group in the file except "This Mac
    /// only", which is off by default (owner decision 3).
    public var defaultSelection: Set<SettingsCategory> {
        Set(categoriesInFile.filter(\.includedByDefault))
    }

    /// How many settings (or profiles) the file has for `category`.
    public func itemCount(in category: SettingsCategory) -> Int {
        switch sections[category]?.content {
        case .settings(let values)?: return values.count
        case .profiles(let profiles)?: return profiles.count
        case nil: return 0
        }
    }

    /// "Made by MeedyaConverter 0.1.0 on 25 Sep 2026", with whatever the
    /// file says.
    public var sourceDescription: String {
        var text = "Made by MeedyaConverter"
        if let appVersion { text += " \(appVersion)" }
        if let exportedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            text += " on \(formatter.string(from: exportedAt))"
        }
        return text
    }
}

// MARK: - Preview types

/// One setting in a preview.
public struct SettingsItemPreview: Sendable, Equatable {

    public enum Change: String, Sendable {
        /// Not set on this Mac; the file sets it.
        case added
        /// Set here to something else.
        case changed
        /// Already the same here.
        case unchanged
        /// "Replace" removes it (back to its default).
        case removed
    }

    public let key: String
    public let label: String
    /// The file's value, for showing (nil when removed). Never a secret: the
    /// file cannot hold one.
    public let fileValue: String?
    /// This Mac's value, for showing (nil when not set). An address holding
    /// a user name, password or token is shown as hidden, never as itself.
    public let currentValue: String?
    public let change: Change
    public let takesEffect: SettingsTakesEffect
}

/// One group in a preview.
public struct SettingsGroupPreview: Sendable, Equatable {
    public let category: SettingsCategory
    /// Whether it is in the selection this preview was made for.
    public let isSelected: Bool
    /// How many settings or profiles the file has for this group.
    public let countInFile: Int
    /// Settings groups: each setting the file has, plus any "Replace" would
    /// remove. Empty for the profiles group.
    public let items: [SettingsItemPreview]
    /// Settings groups: how each list setting would change, by key.
    public let listChanges: [String: SettingsListChanges]
    /// The profiles group: which profiles are added, updated or removed.
    public let profileChanges: SettingsListChanges?
    /// Set when this group can't be applied as chosen (for example this
    /// Mac's list can't be read for a merge). Applying it would throw this.
    public let problem: String?

    /// How many items would actually change.
    public var changeCount: Int {
        if let profileChanges {
            return profileChanges.added.count + profileChanges.updated.count + profileChanges.removed.count
        }
        return items.filter { $0.change != .unchanged }.count
    }

    /// "14 settings, 5 differ from yours" or "3 profiles: 2 new, 1 updates one you have".
    public var summary: String {
        if let problem { return problem }
        if let profileChanges {
            var parts: [String] = []
            if !profileChanges.added.isEmpty { parts.append("\(profileChanges.added.count) new") }
            if !profileChanges.updated.isEmpty {
                parts.append(profileChanges.updated.count == 1
                    ? "1 updates one you have"
                    : "\(profileChanges.updated.count) update ones you have")
            }
            if !profileChanges.removed.isEmpty { parts.append("\(profileChanges.removed.count) of yours removed") }
            let head = SettingsImportReport.count(countInFile, "profile")
            return parts.isEmpty ? "\(head), all the same as yours" : "\(head): \(parts.joined(separator: ", "))"
        }
        let differing = items.filter { $0.change == .added || $0.change == .changed }.count
        let removed = items.filter { $0.change == .removed }.count
        var text = "\(SettingsImportReport.count(countInFile, "setting")), \(differing) differ from yours"
        if removed > 0 {
            text += removed == 1 ? ", 1 of yours goes back to its default" : ", \(removed) of yours go back to their defaults"
        }
        return text
    }
}

/// What an import would do, before anything is written.
public struct SettingsImportPreview: Sendable, Equatable {
    public let mode: SettingsImportMode
    public let selection: Set<SettingsCategory>
    /// Every known group in the file, selected or not.
    public let groups: [SettingsGroupPreview]
    /// Cautions for the selected groups ("Delete source after successful
    /// encode: ON…", the This Mac warning).
    public let warnings: [String]
    /// Things that won't work as the other Mac had them, for the selected
    /// groups ("Default profile ‘My HEVC’ isn't on this Mac…").
    public let crossChecks: [String]
    /// For "Replace": what it removes, in one sentence ("This removes 2
    /// profiles and 1 SFTP server."). Nil for merge, or when it removes
    /// nothing.
    public let replaceConfirmation: String?
    /// Selected settings that only take effect next launch, by label.
    public let takesEffectNextLaunch: [String]
    /// What in the file won't be imported, and why.
    public let ignored: [SettingsIgnoredItem]
}

// MARK: - SettingsImportResult

/// What an import did.
public struct SettingsImportResult: Sendable, Equatable {
    public let mode: SettingsImportMode
    public let appliedCategories: [SettingsCategory]
    /// Settings written (by key).
    public let settingsWritten: [String]
    /// Settings removed, back to their defaults (by key; "Replace" only).
    public let settingsRemoved: [String]
    /// Profiles added, updated and removed (by name).
    public let profileChanges: SettingsListChanges
    /// How each list setting changed, by key.
    public let listChanges: [String: SettingsListChanges]
    /// What in the file was not imported, and why.
    public let ignored: [SettingsIgnoredItem]
    /// What still has to be set up on this Mac.
    public let stillNeeded: [SettingsCredentialNeed]
    /// Imported settings that only take effect next launch, by label.
    public let takesEffectNextLaunch: [String]

    /// The import report, in plain English, one line each. It says what was
    /// done and what is still needed. It never claims the setup was
    /// "restored" or is "secure".
    public var reportLines: [String] { SettingsImportReport.lines(for: self) }
}

// MARK: - SettingsImporter

/// Checks, previews and applies settings files. See the file overview.
public struct SettingsImporter: Sendable {

    /// The settings file to compare with and write to.
    public let domain: SettingsDomain
    /// The LIVE profile store (never a second one; see the file overview).
    public let profileStore: EncodingProfileStore
    /// Answers "is this secret saved here?" without reading it.
    public let presence: any SettingsCredentialPresence

    public init(
        domain: SettingsDomain,
        profileStore: EncodingProfileStore,
        presence: any SettingsCredentialPresence
    ) {
        self.domain = domain
        self.profileStore = profileStore
        self.presence = presence
    }

    // MARK: 1. Prepare

    /// Checks a whole settings file and writes nothing. Throws a
    /// `SettingsImportError` for the first problem; see that type for the
    /// cases. Unknown groups, unknown settings, "never" settings, settings
    /// in the wrong group and unknown `notIncluded` names are NOT errors:
    /// they are listed in `ignored`, and never written.
    public static func prepare(_ data: Data) throws -> SettingsImportPlan {
        let envelope = try SettingsDocument.readEnvelope(from: data)

        var ignored = envelope.unknownFields.map {
            SettingsIgnoredItem(group: nil, name: $0, reason: .unknownField)
        }
        var sections: [SettingsCategory: SettingsValidatedSection] = [:]
        // Sorted, so the same bad file always reports the same first problem.
        for name in envelope.categories.keys.sorted() {
            guard let payload = envelope.categories[name] else { continue }
            guard let category = SettingsCategory(rawValue: name) else {
                ignored.append(SettingsIgnoredItem(group: nil, name: name, reason: .unknownGroup))
                continue
            }
            let section = try SettingsSectionHandlers.handler(for: category).validate(payload)
            sections[category] = section
            ignored += section.ignored
        }

        var leftOut: [SettingsLeftOutItem] = []
        for name in envelope.notIncluded {
            if let item = SettingsLeftOutItem(rawValue: name) {
                if !leftOut.contains(item) { leftOut.append(item) }
            } else {
                ignored.append(SettingsIgnoredItem(group: nil, name: name, reason: .unknownLeftOutName))
            }
        }

        return SettingsImportPlan(
            formatVersion: envelope.version,
            exportedAt: envelope.exportedAt,
            appVersion: envelope.appVersion,
            categoriesInFile: SettingsCategory.allCases.filter { sections[$0] != nil },
            ignored: ignored,
            leftOut: leftOut,
            sections: sections
        )
    }

    /// `prepare(_:)` for a file on disk. Checks the size BEFORE reading, so
    /// a huge file is refused without being loaded into memory.
    public static func prepare(contentsOf url: URL) throws -> SettingsImportPlan {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = (attributes[.size] as? NSNumber)?.intValue,
           size > SettingsDocument.maximumFileSize {
            throw SettingsImportError.fileTooLarge(bytes: size, limit: SettingsDocument.maximumFileSize)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SettingsImportError.fileUnreadable(reason: error.localizedDescription)
        }
        return try prepare(data)
    }

    // MARK: 2. Preview

    /// What applying `plan` with `selection` and `mode` would do. Writes
    /// nothing. Groups the file has but `selection` leaves out are still
    /// described (with `isSelected` false), so a screen can show them.
    public func preview(
        _ plan: SettingsImportPlan,
        selection: Set<SettingsCategory>,
        mode: SettingsImportMode
    ) -> SettingsImportPreview {
        let snapshot = domain.snapshot()
        let localUserProfiles = profileStore.allProfiles().filter { !$0.isBuiltIn }

        var groups: [SettingsGroupPreview] = []
        var warnings: [String] = []
        var nextLaunch: [String] = []
        var removedSettings = 0
        var removedListItems: [(count: Int, noun: String)] = []
        var removedProfiles = 0

        for category in plan.categoriesInFile {
            let isSelected = selection.contains(category)
            do {
                let changes = try Self.changes(
                    for: category, plan: plan, mode: mode, snapshot: snapshot,
                    localUserProfiles: localUserProfiles
                )
                groups.append(SettingsGroupPreview(
                    category: category, isSelected: isSelected, countInFile: plan.itemCount(in: category),
                    items: changes.items, listChanges: changes.listChanges,
                    profileChanges: changes.profileChanges, problem: nil
                ))
                guard isSelected else { continue }
                warnings += changes.warnings
                nextLaunch += changes.items
                    .filter { $0.takesEffect == .nextLaunch && $0.change != .unchanged }
                    .map(\.label)
                // A list removed whole is counted by its items below, not
                // again as a setting.
                removedSettings += changes.removals.filter { changes.listChanges[$0] == nil }.count
                removedProfiles += changes.profileChanges?.removed.count ?? 0
                for (key, list) in changes.listChanges.sorted(by: { $0.key < $1.key }) where !list.removed.isEmpty {
                    removedListItems.append((list.removed.count, Self.itemNoun(for: key)))
                }
            } catch {
                groups.append(SettingsGroupPreview(
                    category: category, isSelected: isSelected, countInFile: plan.itemCount(in: category),
                    items: [], listChanges: [:], profileChanges: nil,
                    problem: (error as? LocalizedError)?.errorDescription ?? "This group can't be imported."
                ))
            }
        }

        if selection.contains(.thisMac), plan.categoriesInFile.contains(.thisMac),
           let warning = SettingsCategory.thisMac.warning {
            warnings.append(warning)
        }

        var confirmation: String?
        if mode == .replace {
            var parts: [String] = []
            if removedProfiles > 0 { parts.append(SettingsImportReport.count(removedProfiles, "profile")) }
            for entry in removedListItems { parts.append(SettingsImportReport.count(entry.count, entry.noun)) }
            var sentence = parts.isEmpty ? "" : "This removes \(SettingsImportReport.joined(parts))"
            if removedSettings > 0 {
                let settings = SettingsImportReport.backToDefaults(removedSettings)
                sentence += sentence.isEmpty ? "This returns \(settings)" : ", and returns \(settings)"
            }
            confirmation = sentence.isEmpty ? nil : sentence + ". Passwords and keys are never touched."
        }

        return SettingsImportPreview(
            mode: mode,
            selection: selection,
            groups: groups,
            warnings: warnings,
            crossChecks: Self.crossChecks(
                plan: plan, selection: selection, mode: mode, localProfiles: profileStore.allProfiles()
            ),
            replaceConfirmation: confirmation,
            takesEffectNextLaunch: nextLaunch,
            ignored: plan.ignored
        )
    }

    // MARK: 3. Apply

    /// Imports the ticked groups of `plan` (`selection`; groups the file
    /// does not have are ignored). All-or-nothing: see the file overview for
    /// the order and why. On any thrown error nothing was changed.
    public func apply(
        _ plan: SettingsImportPlan,
        selection: Set<SettingsCategory>,
        mode: SettingsImportMode
    ) throws -> SettingsImportResult {
        let applied = plan.categoriesInFile.filter { selection.contains($0) }
        let snapshot = domain.snapshot()
        let localUserProfiles = profileStore.allProfiles().filter { !$0.isBuiltIn }

        // PHASE 1 — work out every change. Nothing is written in this phase;
        // anything that throws here leaves everything as it was.
        var allChanges: [CategoryChanges] = []
        for category in applied {
            allChanges.append(try Self.changes(
                for: category, plan: plan, mode: mode, snapshot: snapshot,
                localUserProfiles: localUserProfiles
            ))
        }
        let writes = allChanges.flatMap(\.writes)
        let removals = allChanges.flatMap(\.removals)

        // The same rule `prepare` already applied, checked again against the
        // registry right before the first write: only allowed settings, only
        // in ticked groups. Should never fire; if it does, nothing is written.
        let appliedSet = Set(applied)
        for key in writes.map(\.key) + removals {
            guard let entry = SettingsKeyRegistry.entry(for: key), entry.canBeExported,
                  let category = entry.category, appliedSet.contains(category) else {
                throw SettingsImportError.internalSafetyCheckFailed(
                    detail: "“\(key)” is not an allowed setting in the chosen groups"
                )
            }
        }

        // PHASE 2 — the profiles file: the only write that can fail, so it
        // goes first. If it throws, no setting has been touched.
        let profileOperation = allChanges.compactMap(\.profileOperation).first
        do {
            switch profileOperation {
            case .upsert(let profiles)?:
                try profileStore.upsertUserProfiles(profiles)
            case .replace(let profiles)?:
                try profileStore.replaceUserProfiles(with: profiles)
            case nil:
                break
            }
        } catch let error as EncodingProfileBulkImportError {
            switch error {
            case .writeFailed(let reason):
                throw SettingsImportError.profileStoreWriteFailed(reason: reason)
            case .builtInProfileRejected, .duplicateID:
                // `prepare` refuses both, so these can't happen; mapped
                // rather than crashed, with nothing else written.
                throw SettingsImportError.invalidValue(
                    category: .encodingProfiles, key: "profiles",
                    reason: error.errorDescription ?? "a profile was refused"
                )
            }
        }

        // PHASE 3 — settings. `UserDefaults` writes cannot fail.
        for write in writes {
            domain.write(write.value, key: write.key)
        }
        for key in removals {
            domain.remove(key: key)
        }

        // PHASE 4 — what still has to be set up here. Asked after writing,
        // because some of it reads the settings just imported.
        let sftpKey = SFTPProfileStore.userDefaultsKey
        let cloudKey = CloudStorageProfileStore.userDefaultsKey
        let importedSFTP = Self.importedItems(SFTPServerConfig.self, key: sftpKey, plan: plan,
                                              category: .connections, applied: appliedSet, writes: writes)
        let importedCloud = Self.importedItems(CloudStorageConfig.self, key: cloudKey, plan: plan,
                                               category: .connections, applied: appliedSet, writes: writes)
        let stillNeeded = SettingsCredentialNeeds.compute(
            leftOut: plan.leftOut,
            appliedCategories: appliedSet,
            sftpServers: importedSFTP,
            cloudDestinations: importedCloud,
            domain: domain,
            presence: presence
        )

        var listChanges: [String: SettingsListChanges] = [:]
        for changes in allChanges { listChanges.merge(changes.listChanges) { first, _ in first } }

        return SettingsImportResult(
            mode: mode,
            appliedCategories: applied,
            settingsWritten: writes.map(\.key),
            settingsRemoved: removals,
            profileChanges: allChanges.compactMap(\.profileChanges).first ?? SettingsListChanges(),
            listChanges: listChanges,
            ignored: plan.ignored,
            stillNeeded: stillNeeded,
            takesEffectNextLaunch: allChanges.flatMap(\.items)
                .filter { $0.takesEffect == .nextLaunch && $0.change != .unchanged }
                .map(\.label)
        )
    }

    // MARK: - Working out the changes (shared by preview and apply)

    /// A pending settings write.
    struct PendingWrite {
        let key: String
        let value: SettingsWritableValue
    }

    /// What to do to the profiles file.
    enum ProfileOperation {
        case upsert([EncodingProfile])
        case replace([EncodingProfile])
    }

    /// Everything one group would change. Preview and apply both use this,
    /// so what is shown is what is done.
    struct CategoryChanges {
        var writes: [PendingWrite] = []
        var removals: [String] = []
        var items: [SettingsItemPreview] = []
        var listChanges: [String: SettingsListChanges] = [:]
        var warnings: [String] = []
        var profileOperation: ProfileOperation?
        var profileChanges: SettingsListChanges?
    }

    static func changes(
        for category: SettingsCategory,
        plan: SettingsImportPlan,
        mode: SettingsImportMode,
        snapshot: [String: Any],
        localUserProfiles: [EncodingProfile]
    ) throws -> CategoryChanges {
        var result = CategoryChanges()
        guard let section = plan.sections[category] else { return result }

        switch section.content {
        case .profiles(let incoming):
            result.profileOperation = mode == .merge ? .upsert(incoming) : .replace(incoming)
            var changes = SettingsListChanges()
            let localByID = Dictionary(localUserProfiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for profile in incoming {
                if let local = localByID[profile.id] {
                    if local != profile { changes.updated.append(profile.name) }
                } else {
                    changes.added.append(profile.name)
                }
            }
            if mode == .replace {
                let incomingIDs = Set(incoming.map(\.id))
                changes.removed = localUserProfiles.filter { !incomingIDs.contains($0.id) }.map(\.name)
            }
            result.profileChanges = changes

        case .settings(let values):
            for key in values.keys.sorted() {
                guard let value = values[key], let entry = SettingsKeyRegistry.entry(for: key),
                      let rules = entry.rules else { continue }
                let stored = snapshot[key]
                let change: SettingsItemPreview.Change
                switch value {
                case .whole(let writable):
                    result.writes.append(PendingWrite(key: key, value: writable))
                    if stored == nil {
                        change = .added
                    } else {
                        change = SettingsValueDisplay.isSame(writable, as: stored, rules: rules) ? .unchanged : .changed
                    }
                case .list(let list):
                    let combined = try SettingsListCodec.combine(
                        list, local: stored, mode: mode, key: key, category: category
                    )
                    result.writes.append(PendingWrite(key: key, value: .data(combined.stored)))
                    result.listChanges[key] = combined.changes
                    change = stored == nil ? .added : (combined.changes.isEmpty ? .unchanged : .changed)
                }
                result.items.append(SettingsItemPreview(
                    key: key, label: entry.label,
                    fileValue: SettingsValueDisplay.describe(value, rules: rules),
                    currentValue: stored.map { SettingsValueDisplay.describe(stored: $0, rules: rules) },
                    change: change, takesEffect: rules.takesEffect
                ))
                if let warning = importWarning(for: value, rules: rules) {
                    result.warnings.append(warning)
                }
            }

            if mode == .replace {
                // Only this group's allowed settings, and only ones that are
                // actually set here. Removing (not writing a default) keeps
                // "missing" meaning whatever the app's default is.
                for entry in SettingsKeyRegistry.entries(in: category).sorted(by: { $0.key < $1.key })
                where values[entry.key] == nil {
                    guard let stored = snapshot[entry.key], let rules = entry.rules else { continue }
                    result.removals.append(entry.key)
                    if case .json(let blob) = rules.kind, blob.mergeRule == .byItemID {
                        result.listChanges[entry.key] = SettingsListChanges(
                            removed: SettingsValueDisplay.itemNames(stored: stored, blob: blob)
                        )
                    }
                    result.items.append(SettingsItemPreview(
                        key: entry.key, label: entry.label, fileValue: nil,
                        currentValue: SettingsValueDisplay.describe(stored: stored, rules: rules),
                        change: .removed, takesEffect: rules.takesEffect
                    ))
                }
            }
        }
        return result
    }

    /// The registry's caution for an imported value, when it applies.
    static func importWarning(for value: SettingsValidatedValue, rules: SettingsValueRules) -> String? {
        switch (rules.importWarning, value) {
        case (.whenTrue(let message)?, .whole(.bool(true))):
            return message
        case (.whenValue(let trigger, let message)?, .whole(.string(let text))) where text == trigger:
            return message
        default:
            return nil
        }
    }

    /// Things that won't work as the other Mac had them. Only for the
    /// selected groups.
    static func crossChecks(
        plan: SettingsImportPlan,
        selection: Set<SettingsCategory>,
        mode: SettingsImportMode,
        localProfiles: [EncodingProfile]
    ) -> [String] {
        guard selection.contains(.encoding),
              case .settings(let values)? = plan.sections[.encoding]?.content else { return [] }

        // The profiles this Mac will have afterwards. The built-ins are taken
        // from the live store, not `EncodingProfile.builtInProfiles`, so their
        // IDs are the ones this running app actually uses (#510: they are
        // made afresh at every launch).
        let builtIns = localProfiles.filter(\.isBuiltIn)
        let localUserProfiles = localProfiles.filter { !$0.isBuiltIn }
        var profilesAfter = builtIns + localUserProfiles
        if selection.contains(.encodingProfiles),
           case .profiles(let incoming)? = plan.sections[.encodingProfiles]?.content {
            switch mode {
            case .merge:
                let incomingIDs = Set(incoming.map(\.id))
                profilesAfter = builtIns + localUserProfiles.filter { !incomingIDs.contains($0.id) } + incoming
            case .replace:
                profilesAfter = builtIns + incoming
            }
        }

        var checks: [String] = []

        // The default profile is looked up by name, ignoring case, falling
        // back to Web Standard (`AppViewModel.init`).
        if case .whole(.string(let name))? = values["defaultProfileName"], !name.isEmpty,
           !profilesAfter.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            checks.append("Default profile ‘\(name)’ isn't on this Mac and isn't being imported, so "
                + "‘\(EncodingProfile.webStandard.name)’ will be used.")
        }

        // Conditional rules find their profile by `id` (`RuleEngine`).
        if case .list(let list)? = values["conditionalRules"],
           let rules = try? JSONDecoder().decode([ConditionalRule].self, from: list.encodedItems) {
            let ids = Set(profilesAfter.map(\.id))
            let orphaned = rules.filter { !ids.contains($0.profileId) }.map(\.name)
            if !orphaned.isEmpty {
                let names = orphaned.prefix(5).map { "‘\($0)’" }.joined(separator: ", ")
                    + (orphaned.count > 5 ? " and \(orphaned.count - 5) more" : "")
                checks.append("\(SettingsImportReport.count(orphaned.count, "conditional rule")) "
                    + "\(orphaned.count == 1 ? "points" : "point") at a profile that isn't on this Mac and "
                    + "isn't being imported (\(names)). "
                    + "\(orphaned.count == 1 ? "It won't match" : "They won't match") until you choose a "
                    + "profile for \(orphaned.count == 1 ? "it" : "them").")
            }
        }
        return checks
    }

    /// The items of an imported list as they were STORED, limited to the
    /// file's items; nil when that list wasn't imported.
    private static func importedItems<T: SettingsListItem>(
        _ type: T.Type,
        key: String,
        plan: SettingsImportPlan,
        category: SettingsCategory,
        applied: Set<SettingsCategory>,
        writes: [PendingWrite]
    ) -> [T]? {
        guard applied.contains(category),
              case .settings(let values)? = plan.sections[category]?.content,
              case .list(let list)? = values[key],
              case .data(let stored)? = writes.last(where: { $0.key == key })?.value,
              let items = try? JSONDecoder().decode([T].self, from: stored) else { return nil }
        let fileIDs = Set(list.items.map(\.id))
        return items.filter { fileIDs.contains($0.settingsItemID) }
    }

    /// A plural noun for a list setting's items, for the replace sentence.
    static func itemNoun(for key: String) -> String {
        switch key {
        case SFTPProfileStore.userDefaultsKey:           return "SFTP server"
        case CloudStorageProfileStore.userDefaultsKey:   return "cloud destination"
        case RenderFarmConfigurationLoader.Keys.agentsJSON: return "render-farm agent"
        case "conditionalRules":                         return "conditional rule"
        case "savedPipelines":                           return "saved pipeline"
        default:                                         return "item"
        }
    }
}

// MARK: - SettingsValueDisplay

/// Short descriptions of values for previews. Never shows a secret: file
/// values have passed every check, and this Mac's addresses are hidden when
/// they hold a user name, password or token. Lists show counts, not contents.
enum SettingsValueDisplay {

    static func describe(_ value: SettingsValidatedValue, rules: SettingsValueRules) -> String {
        switch value {
        case .whole(let writable):
            return describe(writable, rules: rules)
        case .list(let list):
            return SettingsImportReport.count(list.items.count, "item")
        }
    }

    static func describe(_ value: SettingsWritableValue, rules: SettingsValueRules) -> String {
        switch value {
        case .bool(let flag):     return flag ? "On" : "Off"
        case .int(let number):    return String(number)
        case .double(let number):
            // `Int(_:)` traps outside Int's range, and a STORED value here has
            // not been range-checked, so only small whole numbers drop ".0".
            return number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case .string(let text):
            if case .json(.emailRecipients) = rules.kind,
               let list = try? JSONDecoder().decode([String].self, from: Data(text.utf8)) {
                return SettingsImportReport.count(list.count, "recipient")
            }
            return quoted(text, rules: rules)
        case .data(let data):
            return describeBlob(data, rules: rules)
        }
    }

    static func describe(stored: Any, rules: SettingsValueRules) -> String {
        switch rules.kind {
        case .bool:
            return SettingsStoredValue.bool(stored).map { $0 ? "On" : "Off" } ?? "(can't be read)"
        case .int:
            return SettingsStoredValue.int(stored).map(String.init) ?? "(can't be read)"
        case .double:
            return SettingsStoredValue.double(stored).map { describe(.double($0), rules: rules) } ?? "(can't be read)"
        case .string, .address, .filePath, .hexColour:
            return (stored as? String).map { quoted($0, rules: rules) } ?? "(can't be read)"
        case .json(let blob):
            if blob.mergeRule == .byItemID {
                let names = itemNames(stored: stored, blob: blob)
                return SettingsImportReport.count(names.count, "item")
            }
            if blob.storage == .jsonString, let text = stored as? String {
                return describe(.string(text), rules: rules)
            }
            if let data = stored as? Data { return describeBlob(data, rules: rules) }
            return "(can't be read)"
        }
    }

    /// Whether storing `value` would change nothing.
    static func isSame(_ value: SettingsWritableValue, as stored: Any?, rules: SettingsValueRules) -> Bool {
        guard let stored else { return false }
        switch value {
        case .bool(let flag):     return SettingsStoredValue.bool(stored) == flag
        case .int(let number):    return SettingsStoredValue.int(stored) == number
        case .double(let number): return SettingsStoredValue.double(stored) == number
        case .string(let text):
            guard let current = stored as? String else { return false }
            if case .json(.emailRecipients) = rules.kind {
                return (try? JSONDecoder().decode([String].self, from: Data(text.utf8)))
                    == (try? JSONDecoder().decode([String].self, from: Data(current.utf8)))
            }
            return current == text
        case .data(let data):
            guard let current = stored as? Data else { return false }
            return canonical(data) != nil && canonical(data) == canonical(current)
        }
    }

    /// The names of a stored list's items (for "Replace removes …").
    static func itemNames(stored: Any, blob: SettingsJSONBlob) -> [String] {
        guard let data = stored as? Data, !data.isEmpty else { return [] }
        func names<T: SettingsListItem>(_ type: T.Type) -> [String] {
            ((try? JSONDecoder().decode([T].self, from: data)) ?? []).map(\.settingsItemName)
        }
        switch blob {
        case .conditionalRules:     return names(ConditionalRule.self)
        case .encodingPipelines:    return names(EncodingPipeline.self)
        case .renderFarmAgents:     return names(RenderFarmAgentInfo.self)
        case .sftpProfiles:         return names(SFTPServerConfig.self)
        case .cloudStorageProfiles: return names(CloudStorageConfig.self)
        case .customTheme, .keyboardShortcuts, .emailRecipients: return []
        }
    }

    private static func describeBlob(_ data: Data, rules: SettingsValueRules) -> String {
        guard case .json(let blob) = rules.kind else { return "(data)" }
        switch blob {
        case .customTheme:
            if let theme = try? JSONDecoder().decode(SettingsThemeShape.self, from: data) {
                return "Theme “\(theme.name)”"
            }
        case .keyboardShortcuts:
            if let list = try? JSONDecoder().decode([SettingsShortcutShape].self, from: data) {
                return SettingsImportReport.count(list.count, "shortcut")
            }
        case .conditionalRules, .encodingPipelines, .renderFarmAgents, .sftpProfiles,
             .cloudStorageProfiles, .emailRecipients:
            break
        }
        return "(can't be read)"
    }

    private static func quoted(_ text: String, rules: SettingsValueRules) -> String {
        if case .address = rules.kind, SettingsAddressCheck.problem(in: text) != nil {
            return "(hidden: it contains a user name, password or token)"
        }
        let shortened = text.count > 80 ? String(text.prefix(77)) + "…" : text
        return "“\(shortened)”"
    }

    private static func canonical(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }
}

// MARK: - SettingsImportReport (plain-English lines)

/// The import report and small wording helpers shared by the preview.
enum SettingsImportReport {

    static func lines(for result: SettingsImportResult) -> [String] {
        var lines: [String] = []

        let profiles = result.profileChanges.added.count + result.profileChanges.updated.count
        var imported = "Imported \(count(result.settingsWritten.count, "setting"))"
        if profiles > 0 || result.appliedCategories.contains(.encodingProfiles) {
            imported += " and \(count(profiles, "profile"))"
        }
        lines.append(imported + ".")
        // A list removed whole is reported by its items below, not again here.
        let settingsReturned = result.settingsRemoved.filter { result.listChanges[$0] == nil }.count
        if settingsReturned > 0 {
            lines.append("Returned \(backToDefaults(settingsReturned)).")
        }
        if !result.profileChanges.removed.isEmpty {
            lines.append("Removed \(count(result.profileChanges.removed.count, "profile")).")
        }
        for (key, changes) in result.listChanges.sorted(by: { $0.key < $1.key }) where !changes.removed.isEmpty {
            lines.append("Removed \(count(changes.removed.count, SettingsImporter.itemNoun(for: key))).")
        }

        if result.stillNeeded.isEmpty {
            lines.append("Nothing else needs setting up on this Mac for the imported groups.")
        } else {
            lines.append("Still needed on this Mac:")
            lines += result.stillNeeded.map { "  - \($0.line)" }
        }

        if !result.takesEffectNextLaunch.isEmpty {
            lines.append("These take effect next time you open MeedyaConverter: "
                + result.takesEffectNextLaunch.joined(separator: ", ") + ".")
        }

        if !result.ignored.isEmpty {
            lines.append("Not imported (\(result.ignored.count)):")
            lines += result.ignored.map { "  - \($0.explanation)" }
        }
        return lines
    }

    /// "1 setting to its default", "3 settings to their defaults".
    static func backToDefaults(_ number: Int) -> String {
        number == 1 ? "1 setting to its default" : "\(number) settings to their defaults"
    }

    /// "1 setting", "3 settings".
    static func count(_ number: Int, _ noun: String) -> String {
        number == 1 ? "1 \(noun)" : "\(number) \(noun)s"
    }

    /// "a", "a and b", "a, b and c".
    static func joined(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }
}
