// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / PresentationLanguageOrder
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Job "the presentation comparison (Part B)" of policy §9: the order of a
// list or menu a PERSON picks a language from.
//
// Unlike stored order (CanonicalLanguageOrder.swift) this depends on the
// person: their language preferences come first (UI-020), then the
// original (UI-030), then everything else alphabetically by name in the
// INTERFACE language, sorted by that language's rules (UI-040); special
// codes and malformed values last. Because it differs per person it MUST
// NEVER be written back into stored content — and the two orders MUST NOT
// share a comparison function (policy §1). They share only the small
// building blocks (group keys, specificity) that both rules define.
//
// The interface language's names and sorting rules are passed in as a
// `LanguageGroupCollation`, so the conformance cases can supply their own
// names and a plain sorting rule, and real code can use the platform's
// locale data (UI-010: never a hand-typed list).
// ============================================================================

import Foundation

// MARK: - Collation

/// How the interface language orders language GROUPS by their localised
/// names (UI-040). `compare` receives two primary language subtags (`de`,
/// `ja`) and says which name sorts first; a tie falls back to the subtag.
public struct LanguageGroupCollation: Sendable {

    /// Compares two ordinary primary language subtags by localised name.
    public let compare: @Sendable (String, String) -> ComparisonResult

    public init(compare: @escaping @Sendable (String, String) -> ComparisonResult) {
        self.compare = compare
    }

    /// Real use: each language's name in `interfaceLocale` (UI-010), compared
    /// with that locale's own sorting rules (so `éwé` sorts with the `e`s in
    /// French). A language the platform has no name for sorts by its subtag.
    public static func localizedNames(in interfaceLocale: Locale) -> LanguageGroupCollation {
        LanguageGroupCollation { a, b in
            let nameA = LanguageNames.localizedName(of: a, in: interfaceLocale) ?? a
            let nameB = LanguageNames.localizedName(of: b, in: interfaceLocale) ?? b
            return nameA.compare(nameB, options: [.caseInsensitive], range: nil, locale: interfaceLocale)
        }
    }

    /// For the conformance cases: sort by the supplied keys compared as
    /// plain strings (policy §8.1). A missing key sorts as an empty string;
    /// the test harness checks every key is present before relying on this.
    public static func plainKeys(_ keys: [String: String]) -> LanguageGroupCollation {
        LanguageGroupCollation { a, b in
            let keyA = keys[a] ?? "", keyB = keys[b] ?? ""
            if keyA == keyB { return .orderedSame }
            return PlainText.less(keyA, keyB) ? .orderedAscending : .orderedDescending
        }
    }
}

// MARK: - Items and preferences

/// One entry of a menu or list to be ordered.
public struct PresentationItem: Sendable, Hashable {
    /// The raw language value.
    public var tag: String
    /// Track type, for role order and accessibility (`nil`: a plain
    /// language item with no roles).
    public var type: TrackType?
    /// Roles (TRACK-010).
    public var roles: [TrackRole]
    /// Structured original-language marker.
    public var isOriginal: Bool

    public init(tag: String, type: TrackType? = nil, roles: [TrackRole] = [], isOriginal: Bool = false) {
        self.tag = tag
        self.type = type
        self.roles = roles
        self.isOriginal = isOriginal
    }
}

/// The user's accessibility preferences (AUTO-040, UI-045).
public struct AccessibilityPreferences: Sendable, Hashable {
    /// The user has asked for audio description.
    public var audioDescription: Bool
    /// The user has asked for SDH / captions.
    public var captions: Bool

    public init(audioDescription: Bool = false, captions: Bool = false) {
        self.audioDescription = audioDescription
        self.captions = captions
    }
}

/// One entry of a subtitle menu (UI-060): "Off" first, then the tracks.
public enum SubtitleMenuEntry: Sendable, Hashable {
    case off
    /// A track, by its index in the list that was ordered.
    case track(Int)
}

// MARK: - PresentationLanguageOrder

/// Menu and list order — Part B of the policy.
public struct PresentationLanguageOrder: Sendable {

    /// The canonicaliser tags and preferences are read with.
    public let canonicaliser: LanguageTagCanonicaliser

    public init(canonicaliser: LanguageTagCanonicaliser) {
        self.canonicaliser = canonicaliser
    }

    /// The positions of `items` in menu order: element `k` of the result is
    /// the index (into `items`) of the item shown `k`-th.
    ///
    /// There is deliberately no "selected item" input: selecting something
    /// never moves it (UI-050).
    ///
    /// - Parameters:
    ///   - preferences: The user's languages, highest priority first (raw
    ///     tags; malformed ones are ignored — UI-020).
    ///   - accessibility: Asked-for accessibility roles (UI-045 / AUTO-040).
    ///   - collation: The interface language's names and sorting (UI-040).
    public func order(
        _ items: [PresentationItem],
        preferences: [String],
        accessibility: AccessibilityPreferences = AccessibilityPreferences(),
        collation: LanguageGroupCollation
    ) -> [Int] {
        let tags = items.map { canonicaliser.canonicalise($0.tag) }
        let preferenceTags = preferences.map { canonicaliser.canonicalise($0) }.filter { !$0.isMalformed }

        // The groups present, and their members in the order found.
        var members: [LanguageGroupKey: [Int]] = [:]
        var groupsInFoundOrder: [LanguageGroupKey] = []
        for (index, tag) in tags.enumerated() {
            let key = LanguageGroupKey(tag)
            if members[key] == nil { groupsInFoundOrder.append(key) }
            members[key, default: []].append(index)
        }

        // Orders ordinary groups by localised name, then subtag (UI-040).
        func byName(_ a: LanguageGroupKey, _ b: LanguageGroupKey) -> Bool {
            switch collation.compare(a.name, b.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return PlainText.less(a.name, b.name)
            }
        }

        var groupOrder: [LanguageGroupKey] = []
        var placed = Set<LanguageGroupKey>()
        func place(_ key: LanguageGroupKey) {
            if placed.insert(key).inserted { groupOrder.append(key) }
        }

        // UI-020: the groups of the user's preferences, in priority order. A
        // preference's group is its primary language — or, for private-use
        // and grandfathered tags, that exact tag.
        for preference in preferenceTags {
            let key = LanguageGroupKey(preference)
            if key.bucket != .malformed, members[key] != nil { place(key) }
        }

        // UI-030: then the original groups (special codes included) — the
        // ordinary ones by name, then special codes in LANG-025 order.
        var originals = Set<LanguageGroupKey>()
        for (item, tag) in zip(items, tags) where item.isOriginal && !tag.isMalformed {
            originals.insert(LanguageGroupKey(tag))
        }
        let ordinaryOriginals = originals.filter { $0.bucket == .ordinary }.sorted(by: byName)
        let specialOriginals = originals.filter { $0.bucket != .ordinary }.sorted()
        (ordinaryOriginals + specialOriginals).forEach(place)

        // UI-040: every other ordinary group, alphabetically by name.
        groupsInFoundOrder.filter { $0.bucket == .ordinary && !placed.contains($0) }.sorted(by: byName).forEach(place)
        // Then the special codes in LANG-025 order, and malformed values last.
        groupsInFoundOrder.filter { $0.bucket != .malformed && !placed.contains($0) }.sorted().forEach(place)
        groupsInFoundOrder.filter { $0.bucket == .malformed }.forEach(place)

        // UI-045: order within each group.
        let exactPreferences = preferenceTags.map(\.text)
        var result: [Int] = []
        for key in groupOrder {
            let indices = members[key] ?? []
            if key.bucket == .malformed {
                // LANG-026: malformed entries keep their found order — roles,
                // original flags and preferences do not reorder them.
                result += indices
                continue
            }
            result += indices.sorted { a, b in
                // 1. Role (TRACK-050's placing role); an asked-for
                //    accessibility role moves ahead of the main tracks.
                let roleA = presentationRoleRank(items[a], accessibility)
                let roleB = presentationRoleRank(items[b], accessibility)
                if roleA != roleB { return roleA < roleB }
                // 2. An EXACT preference match, in preference order.
                let prefA = exactPreferences.firstIndex(of: tags[a].text) ?? exactPreferences.count
                let prefB = exactPreferences.firstIndex(of: tags[b].text) ?? exactPreferences.count
                if prefA != prefB { return prefA < prefB }
                // 3. Items marked original.
                if items[a].isOriginal != items[b].isOriginal { return items[a].isOriginal }
                // 4. Specificity (LANG-021 to LANG-023).
                let specA = SpecificityKey(tags[a]), specB = SpecificityKey(tags[b])
                if specA != specB { return specA < specB }
                // 5. Stability (LANG-027).
                return a < b
            }
        }
        return result
    }

    /// A subtitle menu (UI-060): "Off" first — not a language, not sorted
    /// with them — then the tracks in menu order.
    public func subtitleMenu(
        _ items: [PresentationItem],
        preferences: [String],
        accessibility: AccessibilityPreferences = AccessibilityPreferences(),
        collation: LanguageGroupCollation
    ) -> [SubtitleMenuEntry] {
        [.off] + order(items, preferences: preferences, accessibility: accessibility, collation: collation)
            .map { .track($0) }
    }

    /// UI-045 point 1: the placing role's rank, with a track PLACED by an
    /// accessibility role the user asked for moved ahead (-1). A forced SDH
    /// track is placed as forced, so a captions preference does not move it.
    private func presentationRoleRank(_ item: PresentationItem, _ accessibility: AccessibilityPreferences) -> Int {
        let rank = TrackRoleOrder.placingRank(of: item.roles, for: item.type)
        if accessibility.audioDescription, item.type == .audio,
           rank == TrackRoleOrder.rank(of: .audioDescription, for: .audio) {
            return -1
        }
        if accessibility.captions, item.type == .subtitle,
           rank == TrackRoleOrder.rank(of: .sdh, for: .subtitle) {
            return -1
        }
        return rank
    }
}

// MARK: - Labels (UI-070)

/// Menu labels built from structured data (UI-070):
/// `English (United Kingdom) — Audio Description — 5.1`.
public enum TrackMenuLabel {

    /// The label for one track.
    ///
    /// - Parameters:
    ///   - languageName: The language's name, already localised (UI-010).
    ///   - roles: The track's roles, in any order; listed in TRACK-050 order.
    ///   - type: The track type (decides which role order applies).
    ///   - roleNames: The localised word for each role.
    ///   - channels: Channel layout text for audio (`5.1`), or `nil`.
    /// - Returns: The parts joined with " — " (space, em dash, space). Each
    ///   role appears once (a role given twice is named once — core revision
    ///   6, case label-05), and an empty part — no name, an empty role name,
    ///   an empty channel layout — is left out with its separator. An
    ///   embedded track title is never used here.
    public static func label(
        languageName: String,
        roles: [TrackRole],
        type: TrackType?,
        roleNames: [TrackRole: String],
        channels: String?
    ) -> String {
        var seen = Set<TrackRole>()
        let distinct = roles.filter { seen.insert($0).inserted }
        var parts = [languageName]
        parts += TrackRoleOrder.sorted(distinct, for: type).compactMap { roleNames[$0] }
        if let channels { parts.append(channels) }
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{2014} ")
    }
}
