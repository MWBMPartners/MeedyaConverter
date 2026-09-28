// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / CanonicalLanguageOrder
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Job "the canonical comparison (Part A)" of policy §9: the order of what is
// STORED — tracks written into a file, translations saved in a database.
//
// It depends only on the language tags (and the structured "original" and
// role markers), so it is the same on every machine, in every interface
// language, for every user. It never uses a language's name, the operating
// system's sorting rules or the interface language (LANG-020) — that is the
// PRESENTATION order's job (PresentationLanguageOrder.swift), and the two
// MUST NOT share a comparison function (policy §1).
//
// The order, outermost first:
//   1. the language groups of items marked original (LANG-010);
//   2. other ordinary language groups by primary subtag, plain ASCII (LANG-020);
//   3. special codes: mul, mis, qaa–qtz, und, zxx, grandfathered, private
//      use (LANG-025) — each its own group;
//   4. malformed values last, in the order found (LANG-026).
// Within a group: items marked original first (when the group was promoted),
// then role (TRACK-050, tracks only), then specificity (LANG-021 to LANG-023),
// then the order they came in (LANG-027 — every sort here is stable).
// ============================================================================

import Foundation

// MARK: - Sort keys shared with presentation order

/// Where a tag's group sits among the special codes (LANG-025). 0 is an
/// ordinary language.
enum LanguageBucket: Int, Comparable {
    case ordinary = 0, multiple = 1, uncoded = 2, localUse = 3, undetermined = 4
    case noLinguisticContent = 5, grandfathered = 6, privateUse = 7, malformed = 8

    static func < (lhs: LanguageBucket, rhs: LanguageBucket) -> Bool { lhs.rawValue < rhs.rawValue }

    init(_ tag: LanguageTag) {
        switch tag.kind {
        case .malformed: self = .malformed
        case .privateUse: self = .privateUse
        case .grandfathered: self = .grandfathered
        case .ordinary:
            let language = tag.language ?? ""
            switch language {
            case "mul": self = .multiple
            case "mis": self = .uncoded
            case "und": self = .undetermined
            case "zxx": self = .noLinguisticContent
            default:
                let isLocalUse = language.utf8.count == 3 && language >= "qaa" && language <= "qtz"
                self = isLocalUse ? .localUse : .ordinary
            }
        }
    }
}

/// A language group (policy §3): every tag sharing one primary language, or —
/// for grandfathered and private-use tags — each whole tag on its own
/// (LANG-025, revision 2). All malformed values form one final group.
struct LanguageGroupKey: Hashable, Comparable {
    let bucket: LanguageBucket
    /// The primary language subtag, or the whole lower-case tag for
    /// grandfathered / private use, or "" for malformed.
    let name: String

    init(_ tag: LanguageTag) {
        bucket = LanguageBucket(tag)
        switch bucket {
        case .grandfathered, .privateUse: name = tag.text.lowercased()
        case .malformed: name = ""
        default: name = tag.language ?? ""
        }
    }

    static func < (lhs: LanguageGroupKey, rhs: LanguageGroupKey) -> Bool {
        if lhs.bucket != rhs.bucket { return lhs.bucket < rhs.bucket }
        return PlainText.less(lhs.name, rhs.name)
    }
}

/// Specificity within a group (LANG-021 to LANG-023): bare language, then
/// + script, then + region, then + script + region; anything carrying an
/// unregistered extlang, variants, extensions or private use after all of
/// those, ordered among themselves the same way and then by the rest of the
/// tag as plain ASCII. Scripts compare as ASCII; two-letter regions come
/// before three-digit areas (`es-ES` before `es-419`).
struct SpecificityKey: Comparable {
    let hasExtra: Int
    let level: Int
    let script: String
    let regionKind: Int
    let region: String
    let rest: String

    init(_ tag: LanguageTag) {
        guard tag.kind == .ordinary else {
            // Grandfathered, private-use and malformed tags have no
            // specificity: each is its own group (or keeps found order).
            hasExtra = 0; level = 0; script = ""; regionKind = 0; region = ""; rest = ""
            return
        }
        let extra = tag.extlang != nil || !tag.variants.isEmpty || !tag.extensions.isEmpty || !tag.privateUse.isEmpty
        hasExtra = extra ? 1 : 0
        level = 1 + (tag.script != nil ? 1 : 0) + (tag.region != nil ? 2 : 0)
        script = tag.script ?? ""
        if let region = tag.region {
            regionKind = LanguageTagCanonicaliser.isAllLetters(region) ? 1 : 2
        } else {
            regionKind = 0
        }
        region = tag.region ?? ""
        var restParts: [String] = []
        if let extlang = tag.extlang { restParts.append(extlang) }
        restParts += tag.variants
        restParts += tag.extensions.map { $0.joined(separator: "-") }
        if !tag.privateUse.isEmpty { restParts += ["x"] + tag.privateUse }
        rest = restParts.joined(separator: "-")
    }

    static func < (lhs: SpecificityKey, rhs: SpecificityKey) -> Bool {
        if lhs.hasExtra != rhs.hasExtra { return lhs.hasExtra < rhs.hasExtra }
        if lhs.level != rhs.level { return lhs.level < rhs.level }
        if lhs.script != rhs.script { return PlainText.less(lhs.script, rhs.script) }
        if lhs.regionKind != rhs.regionKind { return lhs.regionKind < rhs.regionKind }
        if lhs.region != rhs.region { return PlainText.less(lhs.region, rhs.region) }
        return PlainText.less(lhs.rest, rhs.rest)
    }
}

/// "Plain text" comparison as the policy uses the phrase: byte by byte on
/// UTF-8, which is code-point order. (Swift's own `<` on `String` compares
/// Unicode canonical forms, which is not the same thing for every string.)
enum PlainText {
    static func less(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}

// MARK: - Items

/// One item to put in stored order: a language-tagged record with an
/// optional "original" marker, and — for tracks — a type and roles.
public struct CanonicalOrderItem: Sendable, Hashable {
    /// The raw language value (canonicalised for ordering, never rewritten).
    public var tag: String
    /// Structured "original language" marker (LANG-010).
    public var isOriginal: Bool
    /// Track type, for role order (TRACK-050). `nil` for plain language items.
    public var type: TrackType?
    /// Roles (TRACK-010).
    public var roles: [TrackRole]

    public init(tag: String, isOriginal: Bool = false, type: TrackType? = nil, roles: [TrackRole] = []) {
        self.tag = tag
        self.isOriginal = isOriginal
        self.type = type
        self.roles = roles
    }
}

// MARK: - CanonicalLanguageOrder

/// Stored (canonical) order — Part A of the policy.
public struct CanonicalLanguageOrder: Sendable {

    /// The canonicaliser the tags are read with.
    public let canonicaliser: LanguageTagCanonicaliser

    public init(canonicaliser: LanguageTagCanonicaliser) {
        self.canonicaliser = canonicaliser
    }

    /// The positions of `items` in stored order: element `k` of the result is
    /// the index (into `items`) of the item that comes `k`-th (LANG-010 to
    /// LANG-027, plus TRACK-050 roles when items carry a type).
    public func order(_ items: [CanonicalOrderItem]) -> [Int] {
        let tags = items.map { canonicaliser.canonicalise($0.tag) }

        // LANG-010: the groups of items marked original are promoted. Each
        // list is ordered from its own markers; a malformed value is never
        // promoted.
        var promoted = Set<LanguageGroupKey>()
        for (item, tag) in zip(items, tags) where item.isOriginal && !tag.isMalformed {
            promoted.insert(LanguageGroupKey(tag))
        }

        return Array(items.indices).sorted { a, b in
            let tagA = tags[a], tagB = tags[b]
            // LANG-026: malformed values after everything, in found order.
            if tagA.isMalformed || tagB.isMalformed {
                if tagA.isMalformed != tagB.isMalformed { return tagB.isMalformed }
                return a < b
            }
            let groupA = LanguageGroupKey(tagA), groupB = LanguageGroupKey(tagB)
            let promotedA = promoted.contains(groupA), promotedB = promoted.contains(groupB)
            if promotedA != promotedB { return promotedA }
            if groupA != groupB { return groupA < groupB }
            // Within a promoted group, the items marked original come first.
            if promotedA {
                let originalA = items[a].isOriginal, originalB = items[b].isOriginal
                if originalA != originalB { return originalA }
            }
            let roleA = TrackRoleOrder.placingRank(of: items[a].roles, for: items[a].type)
            let roleB = TrackRoleOrder.placingRank(of: items[b].roles, for: items[b].type)
            if roleA != roleB { return roleA < roleB }
            let specA = SpecificityKey(tagA), specB = SpecificityKey(tagB)
            if specA != specB { return specA < specB }
            // LANG-027: ties keep their order (this makes the sort stable).
            return a < b
        }
    }

    /// `items` rearranged into stored order.
    public func sorted(_ items: [CanonicalOrderItem]) -> [CanonicalOrderItem] {
        order(items).map { items[$0] }
    }

    /// The positions of `tracks` in stored track order (TRACK-060): video,
    /// then audio, then subtitles, then anything else — each type ordered on
    /// its own (an original audio track does not promote subtitles).
    /// `tracks` must each carry a `type`; a missing type counts as `.other`.
    public func trackOrder(_ tracks: [CanonicalOrderItem]) -> [Int] {
        var result: [Int] = []
        for type in TrackType.allCases.sorted(by: { $0.storedOrder < $1.storedOrder }) {
            let indices = tracks.indices.filter { (tracks[$0].type ?? .other) == type }
            let subset = indices.map { tracks[$0] }
            result += order(subset).map { indices[$0] }
        }
        return result
    }
}
