// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / LanguageMatcher
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Job "preference matching" of policy §9 (MATCH-010 to MATCH-040): how well
// a track or translation tag suits one language preference.
//
// Strength, best first: exact → general (the track is a shorter form of the
// preference) → specific (a longer form) → related (same primary language,
// no script conflict) → none. Matching never changes either tag and never
// infers subtags (LANG-024): `zh-TW` and `zh-Hans` are "related", because
// nothing in the tags says `zh-TW` is Traditional. Tags whose primary
// language is und, mul, mis or zxx — with or without more subtags — and
// private-use or grandfathered tags only ever match themselves exactly.
// ============================================================================

import Foundation

// MARK: - Match results

/// How strongly a candidate suits a preference, best first.
public enum LanguageMatchLevel: Int, Sendable, Comparable, CaseIterable {
    case exact = 0
    case general = 1
    case specific = 2
    case related = 3
    case none = 4

    public static func < (lhs: LanguageMatchLevel, rhs: LanguageMatchLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The word the conformance cases use.
    public var word: String {
        switch self {
        case .exact: return "exact"
        case .general: return "general"
        case .specific: return "specific"
        case .related: return "related"
        case .none: return "none"
        }
    }

    /// Whether this counts as a match at all (related or better).
    public var isMatch: Bool { self != .none }
}

/// The outcome of matching one preference against one candidate.
public struct LanguageMatch: Sendable, Hashable, Comparable {
    /// The strength.
    public let level: LanguageMatchLevel
    /// For general and specific matches: how many hyphen-separated parts were
    /// removed or added (single-letter parts count). 0 otherwise.
    public let distance: Int

    public init(level: LanguageMatchLevel, distance: Int) {
        self.level = level
        self.distance = distance
    }

    /// Better matches sort first: stronger level, then fewer parts changed.
    public static func < (lhs: LanguageMatch, rhs: LanguageMatch) -> Bool {
        if lhs.level != rhs.level { return lhs.level < rhs.level }
        return lhs.distance < rhs.distance
    }

    static let none = LanguageMatch(level: .none, distance: 0)
}

// MARK: - LanguageMatcher

/// Matches preferences against tags (MATCH-010 to MATCH-040).
public struct LanguageMatcher: Sendable {

    /// The canonicaliser both tags are read with.
    public let canonicaliser: LanguageTagCanonicaliser

    public init(canonicaliser: LanguageTagCanonicaliser) {
        self.canonicaliser = canonicaliser
    }

    /// The special codes that only ever match themselves exactly.
    private static let exactOnlyLanguages: Set<String> = ["und", "mul", "mis", "zxx"]

    /// How well `candidate` suits `preference` (both raw; canonicalised here).
    public func match(preference: String, candidate: String) -> LanguageMatch {
        match(canonicaliser.canonicalise(preference), canonicaliser.canonicalise(candidate))
    }

    /// The same, for tags already canonicalised.
    public func match(_ preference: LanguageTag, _ candidate: LanguageTag) -> LanguageMatch {
        // A malformed value matches nothing, not even itself.
        if preference.isMalformed || candidate.isMalformed { return .none }
        // MATCH-010: identical canonical tags.
        if preference.text.lowercased() == candidate.text.lowercased() {
            return LanguageMatch(level: .exact, distance: 0)
        }
        // Private-use-only and grandfathered-without-replacement tags only
        // ever match exactly.
        guard preference.kind == .ordinary, candidate.kind == .ordinary,
              let preferred = preference.language, let offered = candidate.language else {
            return .none
        }
        // und/mul/mis/zxx (with or without more subtags) only match exactly.
        if Self.exactOnlyLanguages.contains(preferred) || Self.exactOnlyLanguages.contains(offered) {
            return .none
        }
        // Different primary languages never match.
        guard preferred == offered else { return .none }
        // MATCH-040's exception: both state a script and they differ.
        if let a = preference.script, let b = candidate.script, a != b {
            return .none
        }
        let preferenceParts = preference.lowerCasedParts
        let candidateParts = candidate.lowerCasedParts
        // MATCH-020: the candidate is the preference with parts removed from the end.
        if candidateParts.count < preferenceParts.count,
           Array(preferenceParts.prefix(candidateParts.count)) == candidateParts {
            return LanguageMatch(level: .general, distance: preferenceParts.count - candidateParts.count)
        }
        // MATCH-030: the preference is the candidate with parts removed.
        if preferenceParts.count < candidateParts.count,
           Array(candidateParts.prefix(preferenceParts.count)) == preferenceParts {
            return LanguageMatch(level: .specific, distance: candidateParts.count - preferenceParts.count)
        }
        // MATCH-040: same language, no script conflict.
        return LanguageMatch(level: .related, distance: 0)
    }
}
