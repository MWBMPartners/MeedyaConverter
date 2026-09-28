// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / AutomaticTrackSelection
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Job "automatic selection" of policy §9 (AUTO-010 to AUTO-040): which audio
// and subtitle track should play when nobody has picked one.
//
// This is a separate decision from menu order (AUTO-010): never "whatever is
// first in the menu", and the same answer whatever order the tracks arrive
// in. Where every rule leaves two tracks level, the TRACK IDENTIFIER decides
// — in one fixed order (`TrackIdentifierOrder`) — never list position. Two
// tracks with the same identifier are refused with an error, not guessed at.
//
// MeedyaConverter does not play media, so nothing in the app calls this yet.
// It is here so the Swift implementation of the policy is complete for the
// future MeedyaPlayer / MeedyaSubtitler (policy §9), and it is held to every
// conformance case like the rest.
//
// A NOTE ON "canonical order" AS A TIE-BREAK
// ------------------------------------------
// The rules below end with "canonical order (TRACK-050), identifier".
// Canonical order means the position each track would have in STORED order
// among ALL tracks of its type (AUTO-020, as settled in core revision 6) —
// including tracks that can never be chosen, so an original commentary track
// still brings its language group forward, as it does in stored order. This
// file used to rank only the tracks still in the running, which put the
// English default before the Japanese one in case audio-22. Positions use
// each track's REAL role rank (TRACK-050), as the policy text says.
// ============================================================================

import Foundation

// MARK: - Inputs

/// A track automatic selection can choose.
public struct SelectableTrack: Sendable, Hashable {
    /// The identifier the file gives the track — the final tie-break.
    public var id: String
    /// Raw language value.
    public var tag: String
    /// Roles (TRACK-010).
    public var roles: [TrackRole]
    /// Default flag.
    public var isDefault: Bool
    /// Original-language flag.
    public var isOriginal: Bool

    public init(id: String, tag: String, roles: [TrackRole] = [], isDefault: Bool = false, isOriginal: Bool = false) {
        self.id = id
        self.tag = tag
        self.roles = roles
        self.isDefault = isDefault
        self.isOriginal = isOriginal
    }
}

/// The user's subtitle mode (AUTO-030).
public enum SubtitleMode: String, Sendable, Hashable, CaseIterable {
    /// Never show subtitles.
    case off
    /// Only a forced track matching the audio's language.
    case forcedOnly = "forced_only"
    /// Always show the best full (or SDH) track for the preferences.
    case always
    /// The usual default: forced-only when the audio is understood,
    /// otherwise always.
    case automatic
}

/// Why a selection was refused.
public enum TrackSelectionError: Error, Sendable, Equatable {
    /// Two tracks share this identifier, so the final tie-break would have
    /// to guess (AUTO-010).
    case duplicateIdentifier(String)
}

// MARK: - Identifier order (AUTO-010)

/// The one fixed order of track identifiers (AUTO-010, revision 3):
/// identifiers made only of ASCII digits come first, ordered as numbers
/// (`9` before `10`) and, when equal as numbers, as plain text (`01` before
/// `1`); every other identifier comes after, in plain-text order.
///
/// (Comparing a digits-only pair as numbers but a mixed pair as text would
/// not be a consistent order — `2` < `10` < `1a` < `2` — so the digits-only
/// identifiers are kept together.)
public enum TrackIdentifierOrder {

    /// Whether `lhs` comes before `rhs`.
    public static func less(_ lhs: String, _ rhs: String) -> Bool {
        let lhsDigits = LanguageTagCanonicaliser.isAllDigits(lhs)
        let rhsDigits = LanguageTagCanonicaliser.isAllDigits(rhs)
        if lhsDigits != rhsDigits { return lhsDigits }
        if lhsDigits {
            // Compare as numbers without converting (identifiers can be longer
            // than any integer type): drop leading zeros, then the shorter is
            // smaller, then digit by digit.
            let a = lhs.drop(while: { $0 == "0" }), b = rhs.drop(while: { $0 == "0" })
            if a.utf8.count != b.utf8.count { return a.utf8.count < b.utf8.count }
            if a != b { return PlainText.less(String(a), String(b)) }
        }
        return PlainText.less(lhs, rhs)
    }
}

// MARK: - AutomaticTrackSelector

/// Chooses audio and subtitle tracks automatically (AUTO-010 to AUTO-040).
public struct AutomaticTrackSelector: Sendable {

    /// Canonical order, used as a tie-break.
    public let canonicalOrder: CanonicalLanguageOrder
    /// Preference matching.
    public let matcher: LanguageMatcher

    public init(canonicaliser: LanguageTagCanonicaliser) {
        canonicalOrder = CanonicalLanguageOrder(canonicaliser: canonicaliser)
        matcher = LanguageMatcher(canonicaliser: canonicaliser)
    }

    // MARK: Audio (AUTO-020)

    /// The audio track to play, by identifier (`nil` only when there are no
    /// tracks).
    ///
    /// - Throws: `TrackSelectionError.duplicateIdentifier` if two tracks share
    ///   an identifier.
    public func selectAudio(
        _ tracks: [SelectableTrack],
        preferences: [String],
        accessibility: AccessibilityPreferences = AccessibilityPreferences()
    ) throws -> String? {
        try refuseDuplicateIdentifiers(tracks)
        guard !tracks.isEmpty else { return nil }
        let preferences = usablePreferences(preferences)

        // Step 1: tracks PLACED as commentary or other (an unrecognised role
        // counts as other) are never chosen unless every track is one.
        let special = TrackRoleOrder.rank(of: .commentary, for: .audio)
        var eligible = tracks.filter { TrackRoleOrder.placingRank(of: $0.roles, for: .audio) < special }
        if eligible.isEmpty { eligible = tracks }

        // Canonical order among ALL audio tracks, not just the eligible ones
        // (see the file header).
        let position = canonicalPositions(tracks, type: .audio)
        // Role rank by the placing role: main, alternate, audio description —
        // or, when the user asked for audio description, AD, main, alternate.
        // Commentary and other (chosen only when every track is one) keep
        // TRACK-050's order in both cases: commentary before other. With
        // audio description asked for, both used to rank the same, so the
        // default flag or identifier picked "other" (case audio-23).
        func roleRank(_ track: SelectableTrack) -> Int {
            let placing = TrackRoleOrder.placingRank(of: track.roles, for: .audio)
            guard accessibility.audioDescription else { return placing }
            switch placing {
            case TrackRoleOrder.rank(of: .audioDescription, for: .audio): return 0
            case 0: return 1
            case TrackRoleOrder.rank(of: .alternate, for: .audio): return 2
            case TrackRoleOrder.rank(of: .commentary, for: .audio): return 3
            default: return 4
            }
        }

        // Step 2: the first preference any track matches (related or better).
        for preference in preferences {
            let candidates = eligible.compactMap { track -> (SelectableTrack, LanguageMatch)? in
                let result = matcher.match(preference: preference, candidate: track.tag)
                return result.level.isMatch ? (track, result) : nil
            }
            if let best = candidates.min(by: { x, y in
                let (a, matchA) = x, (b, matchB) = y
                if roleRank(a) != roleRank(b) { return roleRank(a) < roleRank(b) }
                if matchA != matchB { return matchA < matchB }
                if a.isDefault != b.isDefault { return a.isDefault }
                if a.isOriginal != b.isOriginal { return a.isOriginal }
                return precedes(a, b, position)
            }) {
                return best.0.id
            }
        }

        // Steps 3 and 4: the original track(s), else the default track(s).
        for flagged in [eligible.filter(\.isOriginal), eligible.filter(\.isDefault)] where !flagged.isEmpty {
            return flagged.min { a, b in
                if roleRank(a) != roleRank(b) { return roleRank(a) < roleRank(b) }
                if a.isDefault != b.isDefault { return a.isDefault }
                return precedes(a, b, position)
            }?.id
        }

        // Step 5: best by role, then canonical order, then identifier — so a
        // main-programme track still wins over audio description nobody asked for.
        return eligible.min { a, b in
            if roleRank(a) != roleRank(b) { return roleRank(a) < roleRank(b) }
            return precedes(a, b, position)
        }?.id
    }

    // MARK: Subtitles (AUTO-030)

    /// The subtitle track to show, by identifier, or `nil` for none.
    ///
    /// - Parameters:
    ///   - audioTag: The language of the audio track already chosen, or `nil`
    ///     when none was (a silent video): its language counts as unknown.
    /// - Throws: `TrackSelectionError.duplicateIdentifier` if two tracks share
    ///   an identifier.
    public func selectSubtitle(
        _ tracks: [SelectableTrack],
        audioTag: String?,
        preferences: [String],
        mode: SubtitleMode,
        accessibility: AccessibilityPreferences = AccessibilityPreferences()
    ) throws -> String? {
        try refuseDuplicateIdentifiers(tracks)
        let preferences = usablePreferences(preferences)
        let position = canonicalPositions(tracks, type: .subtitle)
        let forcedRank = TrackRoleOrder.rank(of: .forced, for: .subtitle)
        let sdhRank = TrackRoleOrder.rank(of: .sdh, for: .subtitle)

        // Forced only: the forced track best matching the AUDIO's language.
        func forcedOnly() -> String? {
            guard let audioTag else { return nil }
            let audio = matcher.canonicaliser.canonicalise(audioTag)
            switch audio.kind {
            case .malformed:
                return nil
            case .ordinary:
                // Nothing to match against when the audio's language is
                // unknown, several, or none (with or without more subtags).
                guard let language = audio.language, !["und", "mul", "zxx"].contains(language) else { return nil }
            case .privateUse, .grandfathered:
                // A private-use (`x-foo`) or grandfathered (`i-default`)
                // audio tag DOES have something to match: a forced track with
                // exactly that tag (AUTO-030, MATCH-040; core revision 6,
                // cases subs-22 and -23). The matcher gives such tags an
                // exact match only. They used to be treated as "not known".
                break
            }
            let candidates = tracks.compactMap { track -> (SelectableTrack, LanguageMatch)? in
                guard TrackRoleOrder.placingRank(of: track.roles, for: .subtitle) == forcedRank else { return nil }
                let result = matcher.match(audio, matcher.canonicaliser.canonicalise(track.tag))
                return result.level.isMatch ? (track, result) : nil
            }
            return candidates.min { x, y in
                let (a, matchA) = x, (b, matchB) = y
                if matchA != matchB { return matchA < matchB }
                if a.isDefault != b.isDefault { return a.isDefault }
                return precedes(a, b, position)
            }?.0.id
        }

        // Always: the best full (or SDH) track for the preferences; else the
        // default one of those; else nothing. Never a forced track.
        func always() -> String? {
            let usable = tracks.filter {
                let placing = TrackRoleOrder.placingRank(of: $0.roles, for: .subtitle)
                return placing == 0 || placing == sdhRank
            }
            func roleRank(_ track: SelectableTrack) -> Int {
                let isSDH = TrackRoleOrder.placingRank(of: track.roles, for: .subtitle) == sdhRank
                return accessibility.captions ? (isSDH ? 0 : 1) : (isSDH ? 1 : 0)
            }
            for preference in preferences {
                let candidates = usable.compactMap { track -> (SelectableTrack, LanguageMatch)? in
                    let result = matcher.match(preference: preference, candidate: track.tag)
                    return result.level.isMatch ? (track, result) : nil
                }
                if let best = candidates.min(by: { x, y in
                    let (a, matchA) = x, (b, matchB) = y
                    if roleRank(a) != roleRank(b) { return roleRank(a) < roleRank(b) }
                    if matchA != matchB { return matchA < matchB }
                    if a.isDefault != b.isDefault { return a.isDefault }
                    return precedes(a, b, position)
                }) {
                    return best.0.id
                }
            }
            return usable.filter(\.isDefault).min { precedes($0, $1, position) }?.id
        }

        switch mode {
        case .off:
            return nil
        case .forcedOnly:
            return forcedOnly()
        case .always:
            return always()
        case .automatic:
            // Forced only when the audio is understood (it matches a
            // preference) or the user has no preferences; otherwise always.
            if preferences.isEmpty { return forcedOnly() }
            if let audioTag,
               preferences.contains(where: { matcher.match(preference: $0, candidate: audioTag).level.isMatch }) {
                return forcedOnly()
            }
            return always()
        }
    }

    // MARK: Helpers

    /// Refuses two tracks with one identifier (AUTO-010, revision 3).
    private func refuseDuplicateIdentifiers(_ tracks: [SelectableTrack]) throws {
        var seen = Set<String>()
        for track in tracks where !seen.insert(track.id).inserted {
            throw TrackSelectionError.duplicateIdentifier(track.id)
        }
    }

    /// Preferences without the malformed ones, which are ignored (UI-020,
    /// AUTO-010). A malformed preference matches nothing (MATCH-010), and a
    /// user whose preferences are ALL malformed counts as having none — so
    /// the automatic subtitle mode acts as forced only for them. This file
    /// did this before the policy said so; core revision 6 made it the rule
    /// (cases audio-21 and subs-21).
    private func usablePreferences(_ preferences: [String]) -> [String] {
        preferences.filter { !matcher.canonicaliser.canonicalise($0).isMalformed }
    }

    /// Each track's position in canonical order (TRACK-050 for `type`). The
    /// tracks are put in identifier order FIRST, so a tie canonical order
    /// would leave to list position (equal tags, malformed values) is broken
    /// by the identifier instead (AUTO-010).
    private func canonicalPositions(_ tracks: [SelectableTrack], type: TrackType) -> [String: Int] {
        let byIdentifier = tracks.sorted { TrackIdentifierOrder.less($0.id, $1.id) }
        let items = byIdentifier.map {
            CanonicalOrderItem(tag: $0.tag, isOriginal: $0.isOriginal, type: type, roles: $0.roles)
        }
        var positions: [String: Int] = [:]
        for (rank, index) in canonicalOrder.order(items).enumerated() {
            positions[byIdentifier[index].id] = rank
        }
        return positions
    }

    /// Canonical position, then identifier.
    private func precedes(_ a: SelectableTrack, _ b: SelectableTrack, _ position: [String: Int]) -> Bool {
        let positionA = position[a.id] ?? Int.max, positionB = position[b.id] ?? Int.max
        if positionA != positionB { return positionA < positionB }
        return TrackIdentifierOrder.less(a.id, b.id)
    }
}
