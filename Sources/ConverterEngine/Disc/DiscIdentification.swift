// ============================================================================
// MeedyaConverter — DiscIdentification (Issue #502, slice 1)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Content-based disc identification — work out what a video disc most likely IS
// from its own content instead of trusting a fuzzy title/year guess. `DiscSignals`
// (below) carries the disc's running time, chapter count, and subtitle/audio
// languages, but `DiscIdentifier.rank`'s scoring today only actually compares
// running time and title/label text against a candidate; chapter count and the
// languages are read and carried for a future comparison rule, not used by one
// yet. This is the core idea we are borrowing from the MIT-licensed MakeMKV
// Claude skill `threadgill-dev/dvd-autorip-skill` (issue #502).
//
// SCOPE (deliberately narrow, and safe):
//   * This file is PURE, deterministic logic: given a `DiscSignals` fingerprint
//     and a list of candidate matches (`MetadataResult`), it RANKS the
//     candidates. There is no network access, no optical-drive access, no
//     decryption, and no live-model dependency here.
//   * It unlocks NOTHING. MeedyaConverter deliberately refuses copy-protected
//     discs (see `DiscImagingController`'s DRM gate + `DiscProtectionDetector`,
//     #492); adopting a decrypting ripper such as MakeMKV is a separate,
//     user-gated decision and is NOT part of this file.
//   * Fetching real candidates (a MusicBrainz disc lookup for audio CDs; the
//     keyed video providers) and wiring this into `AutoTagger`/the readers
//     (#205, #476) are later slices. This slice is the ranking "brain" they
//     will feed. See `.claude/plans/disc-identification-plan.md`.
//
// It reuses the existing metadata types rather than inventing new ones:
//   * `MetadataResult`      — the candidate identity (title/year/runtimeMinutes…).
//   * `MetadataSearchQuery` — the query shape used by the lookup providers.
//   * `DiscInfo` / `DiscTitle` — the disc description the readers produce.
// The running-time-proximity idea mirrors `MusicBrainzTagMapping.ranked(...)`.
// ============================================================================

import Foundation

// MARK: - DiscSignals

/// The content "fingerprint" used to identify a disc: the handful of facts about
/// what is actually on it that we can compare against a candidate match.
///
/// Every field is optional/empty-tolerant because different disc types (and
/// different stages of a rip) can supply different amounts of information. The
/// ranking in `DiscIdentifier.rank(signals:candidates:)` simply skips any signal
/// the disc does not provide.
public struct DiscSignals: Sendable, Equatable {

    /// The kind of disc (DVD-Video, Blu-ray, Audio CD, …).
    public var discType: DiscType

    /// The disc's volume label, if any (often a rough title hint).
    public var label: String?

    /// A hint at what sort of thing this is (movie / TV / music). When `nil`,
    /// `buildQuery(from:)` infers one from the disc type — but nothing in the
    /// app or CLI calls `buildQuery(from:)` today (the real TMDB lookup,
    /// `TMDBDiscCandidates.provider`, always searches for a film — see that
    /// file's header), so a TV hint set here currently has no effect on what
    /// gets searched.
    public var mediaTypeHint: MediaLookupType?

    /// The running time of the main feature, in seconds, when known.
    public var mainFeatureDurationSeconds: TimeInterval?

    /// Running times of every title/track on the disc, in seconds. Useful as a
    /// structure hint (for example, many similar-length titles suggest a TV set).
    public var titleDurationsSeconds: [TimeInterval]

    /// The number of chapters in the main feature, when known. Carried
    /// through for a future comparison rule; `DiscIdentifier.rank` does not
    /// compare it against a candidate yet.
    public var chapterCount: Int?

    /// Subtitle languages present on the main feature (ISO codes as given).
    /// Carried through for a future comparison rule; `DiscIdentifier.rank`
    /// does not compare these against a candidate yet.
    public var subtitleLanguages: [String]

    /// Audio languages present on the main feature (ISO codes as given).
    /// Carried through for a future comparison rule; `DiscIdentifier.rank`
    /// does not compare these against a candidate yet.
    public var audioLanguages: [String]

    /// A best-guess title to seed a lookup query (from the label or a filename).
    public var seedTitle: String?

    /// A best-guess release year to seed a lookup query, when known.
    public var seedYear: Int?

    public init(
        discType: DiscType,
        label: String? = nil,
        mediaTypeHint: MediaLookupType? = nil,
        mainFeatureDurationSeconds: TimeInterval? = nil,
        titleDurationsSeconds: [TimeInterval] = [],
        chapterCount: Int? = nil,
        subtitleLanguages: [String] = [],
        audioLanguages: [String] = [],
        seedTitle: String? = nil,
        seedYear: Int? = nil
    ) {
        self.discType = discType
        self.label = label
        self.mediaTypeHint = mediaTypeHint
        self.mainFeatureDurationSeconds = mainFeatureDurationSeconds
        self.titleDurationsSeconds = titleDurationsSeconds
        self.chapterCount = chapterCount
        self.subtitleLanguages = subtitleLanguages
        self.audioLanguages = audioLanguages
        self.seedTitle = seedTitle
        self.seedYear = seedYear
    }

    /// Build a `DiscSignals` fingerprint from a disc description and its titles.
    ///
    /// The "main feature" is the title flagged `isMainFeature`, or, failing that,
    /// the longest title. Title/year seeds are taken from a supplied filename
    /// (parsed with `FilenameParser`) when available, otherwise from a cleaned-up
    /// disc label.
    ///
    /// This is pure — it reads the passed-in values and returns a value; it does
    /// not touch any disc, drive, or network.
    ///
    /// - Parameters:
    ///   - discInfo: The disc description (type, label, total duration).
    ///   - titles: The disc's video titles (empty for audio CDs in this slice).
    ///   - seedFilename: An optional filename to mine for a title/year hint.
    public static func from(
        discInfo: DiscInfo,
        titles: [DiscTitle] = [],
        seedFilename: String? = nil
    ) -> DiscSignals {
        // Pick the main feature: the flagged one, else the longest title.
        let mainFeature = titles.first(where: { $0.isMainFeature })
            ?? titles.max(by: { $0.duration < $1.duration })

        // Running time of the main feature, falling back to the disc total.
        let mainDuration: TimeInterval?
        if let feature = mainFeature, feature.duration > 0 {
            mainDuration = feature.duration
        } else if discInfo.totalDuration > 0 {
            mainDuration = discInfo.totalDuration
        } else {
            mainDuration = nil
        }

        let chapters = (mainFeature?.chapterCount).flatMap { $0 > 0 ? $0 : nil }
        let subtitleLanguages = dedupePreservingOrder(
            (mainFeature?.subtitleStreams ?? []).compactMap { $0.language }
        )
        let audioLanguages = dedupePreservingOrder(
            (mainFeature?.audioStreams ?? []).compactMap { $0.language }
        )

        // Media-type hint: audio discs are music; for video, a filename may tell
        // us movie vs TV, otherwise we leave it for the query builder to decide.
        var hint: MediaLookupType? = discInfo.discType.hasAudio ? .music : nil

        // Seed title/year: prefer a parsed filename, fall back to the label.
        var seedTitle: String?
        var seedYear: Int?
        if let filename = seedFilename,
           !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = FilenameParser.parse(filename: filename)
            if !parsed.title.isEmpty { seedTitle = parsed.title }
            seedYear = parsed.year
            if !discInfo.discType.hasAudio {
                switch parsed.mediaType {
                case .tvShow, .tvEpisode: hint = .tvShow
                case .movie: hint = .movie
                default: break
                }
            }
        }
        if seedTitle == nil, let cleaned = cleanedLabel(discInfo.label) {
            seedTitle = cleaned
        }

        return DiscSignals(
            discType: discInfo.discType,
            label: discInfo.label,
            mediaTypeHint: hint,
            mainFeatureDurationSeconds: mainDuration,
            titleDurationsSeconds: titles.map { $0.duration },
            chapterCount: chapters,
            subtitleLanguages: subtitleLanguages,
            audioLanguages: audioLanguages,
            seedTitle: seedTitle,
            seedYear: seedYear
        )
    }

    /// Turn a raw disc label into a readable title hint, or `nil` if it is blank.
    /// Replaces the underscores and dots common in volume labels with spaces and
    /// collapses the result.
    static func cleanedLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let replaced = label
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        let collapsed = replaced
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Remove duplicates while keeping first-seen order (case-insensitive).
    static func dedupePreservingOrder(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let key = item.lowercased()
            if seen.insert(key).inserted {
                result.append(item)
            }
        }
        return result
    }
}

// MARK: - DiscIdentityScore

/// A transparent breakdown of why a candidate scored the way it did. Each
/// component is `nil` when the disc did not supply that signal (so it was not
/// compared for any candidate), otherwise a value in `0...1`.
public struct DiscIdentityScore: Sendable, Equatable {

    /// How close the candidate's running time is to the disc's (1 = exact).
    public var runtimeScore: Double?

    /// How well the candidate's title matches the seed title (1 = same).
    public var titleScore: Double?

    /// Whether the candidate's year matches the seed year (1 = yes, 0 = no).
    public var yearScore: Double?

    /// Overall confidence in `0...1` — the weighted sum of the components that
    /// were compared. More corroborating signals means a higher ceiling.
    public var confidence: Double

    /// A short plain-English explanation of the match.
    public var reason: String

    public init(
        runtimeScore: Double? = nil,
        titleScore: Double? = nil,
        yearScore: Double? = nil,
        confidence: Double = 0,
        reason: String = ""
    ) {
        self.runtimeScore = runtimeScore
        self.titleScore = titleScore
        self.yearScore = yearScore
        self.confidence = confidence
        self.reason = reason
    }
}

// MARK: - ScoredDiscMatch

/// A candidate identity paired with the score the ranker gave it.
public struct ScoredDiscMatch: Sendable {

    /// The candidate identity being scored.
    public var candidate: MetadataResult

    /// The score and its breakdown.
    public var score: DiscIdentityScore

    public init(candidate: MetadataResult, score: DiscIdentityScore) {
        self.candidate = candidate
        self.score = score
    }
}

// MARK: - DiscIdentifier

/// Pure, deterministic disc-identity ranking. Given a disc's content fingerprint
/// and a list of candidate matches, it scores and orders the candidates so the
/// most likely one comes first.
///
/// The scoring weighs three signals, strongest first:
///   * **Running time** (weight 0.5) — the single most reliable clue for a film.
///   * **Title text** (weight 0.35) — token overlap, ignoring the / a / an.
///   * **Year** (weight 0.15) — a match or a mismatch.
///
/// Only the signals the DISC provides are compared. On a compared signal a
/// candidate that is missing the matching field (for example, a database entry
/// with no running time) scores 0 for that signal, because we could not
/// corroborate it. A perfect match on all three compared signals scores 1.0.
public enum DiscIdentifier {

    /// The relative importance of each signal. They sum to 1.0 so a perfect
    /// all-round match reaches a confidence of 1.0.
    private static let runtimeWeight = 0.50
    private static let titleWeight = 0.35
    private static let yearWeight = 0.15

    // MARK: Ranking

    /// Score and rank `candidates` against the disc's `signals`, best first.
    ///
    /// Ordering: highest confidence first; ties broken by the smaller running-time
    /// gap (candidates with a known gap ahead of those without); remaining ties
    /// keep the candidates' original order (a stable sort).
    ///
    /// - Returns: One `ScoredDiscMatch` per candidate, ordered best-first. An
    ///   empty input gives an empty result.
    public static func rank(
        signals: DiscSignals,
        candidates: [MetadataResult]
    ) -> [ScoredDiscMatch] {
        // Score each candidate, remembering its original position and its
        // running-time gap (for a stable, explainable tie-break).
        let scored = candidates.enumerated().map { entry -> (index: Int, gap: Double?, match: ScoredDiscMatch) in
            let (score, gap) = scoreCandidate(signals: signals, candidate: entry.element)
            return (index: entry.offset, gap: gap, match: ScoredDiscMatch(candidate: entry.element, score: score))
        }

        let ordered = scored.sorted { lhs, rhs in
            if lhs.match.score.confidence != rhs.match.score.confidence {
                return lhs.match.score.confidence > rhs.match.score.confidence
            }
            // Smaller running-time gap wins; a known gap beats an unknown one.
            let lhsGap = lhs.gap ?? Double.greatestFiniteMagnitude
            let rhsGap = rhs.gap ?? Double.greatestFiniteMagnitude
            if lhsGap != rhsGap {
                return lhsGap < rhsGap
            }
            // Otherwise keep the original order.
            return lhs.index < rhs.index
        }

        return ordered.map { $0.match }
    }

    // MARK: Query building

    /// Build a metadata search query from the disc signals, for whatever lookup
    /// provider is used later. Audio discs become a music query; video discs
    /// default to a movie query unless a hint says otherwise. Carries the seed
    /// year through when known.
    public static func buildQuery(from signals: DiscSignals) -> MetadataSearchQuery {
        let mediaType = signals.mediaTypeHint ?? (signals.discType.hasAudio ? .music : .movie)
        let title = signals.seedTitle
            ?? DiscSignals.cleanedLabel(signals.label)
            ?? ""
        return MetadataSearchQuery(
            mediaType: mediaType,
            title: title,
            year: signals.seedYear
        )
    }

    // MARK: - Scoring internals

    /// Score one candidate. Returns the score breakdown and the running-time gap
    /// in seconds (used only for tie-breaking; `nil` when it could not be
    /// measured).
    private static func scoreCandidate(
        signals: DiscSignals,
        candidate: MetadataResult
    ) -> (DiscIdentityScore, gap: Double?) {
        var components: [(weight: Double, value: Double)] = []
        var runtimeScore: Double?
        var titleScore: Double?
        var yearScore: Double?
        var runtimeGap: Double?

        // Running time.
        if let discDuration = signals.mainFeatureDurationSeconds, discDuration > 0 {
            if let minutes = candidate.runtimeMinutes, minutes > 0 {
                let candidateSeconds = Double(minutes) * 60.0
                let gap = abs(candidateSeconds - discDuration)
                runtimeGap = gap
                // Tolerance grows with the film's length: a two-hour film can be
                // several minutes out between sources; the floor keeps short
                // items sane.
                let tolerance = max(300.0, discDuration * 0.20)
                runtimeScore = max(0.0, 1.0 - gap / tolerance)
            } else {
                // Disc has a running time but the candidate does not — cannot
                // corroborate.
                runtimeScore = 0.0
            }
            components.append((runtimeWeight, runtimeScore ?? 0.0))
        }

        // Title text.
        if let seed = signals.seedTitle,
           !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            titleScore = tokenSimilarity(seed, candidate.title)
            components.append((titleWeight, titleScore ?? 0.0))
        }

        // Year.
        if let seedYear = signals.seedYear {
            if let year = candidate.year {
                yearScore = (year == seedYear) ? 1.0 : 0.0
            } else {
                yearScore = 0.0
            }
            components.append((yearWeight, yearScore ?? 0.0))
        }

        let confidence = components.reduce(0.0) { $0 + $1.weight * $1.value }
        let reason = buildReason(
            runtimeScore: runtimeScore,
            titleScore: titleScore,
            yearScore: yearScore
        )

        let score = DiscIdentityScore(
            runtimeScore: runtimeScore,
            titleScore: titleScore,
            yearScore: yearScore,
            confidence: confidence,
            reason: reason
        )
        return (score, runtimeGap)
    }

    /// Produce a short, plain-English explanation from the component scores.
    private static func buildReason(
        runtimeScore: Double?,
        titleScore: Double?,
        yearScore: Double?
    ) -> String {
        var phrases: [String] = []
        if let runtimeScore {
            if runtimeScore >= 0.8 {
                phrases.append("running time matches closely")
            } else if runtimeScore >= 0.4 {
                phrases.append("running time is roughly similar")
            } else {
                phrases.append("running time differs")
            }
        }
        if let titleScore {
            if titleScore >= 0.8 {
                phrases.append("title matches")
            } else if titleScore >= 0.4 {
                phrases.append("title partly matches")
            } else {
                phrases.append("title differs")
            }
        }
        if let yearScore {
            phrases.append(yearScore >= 1.0 ? "year matches" : "year differs")
        }
        guard let first = phrases.first else {
            return "No comparable signals were available."
        }
        // Capitalise the first phrase, join the rest with semicolons.
        let capitalised = first.prefix(1).uppercased() + String(first.dropFirst())
        let rest = Array(phrases.dropFirst())
        return ([capitalised] + rest).joined(separator: "; ") + "."
    }

    // MARK: Text similarity

    /// A 0...1 similarity between two titles, based on how many words they share
    /// (Jaccard overlap), after lowercasing, stripping punctuation, and dropping
    /// the leading articles the / a / an so "The Matrix" matches "Matrix".
    public static func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = tokenSet(lhs)
        let b = tokenSet(rhs)
        if a.isEmpty && b.isEmpty { return 0.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return union == 0 ? 0.0 : Double(intersection) / Double(union)
    }

    /// The set of significant words in a title (lowercased, punctuation removed,
    /// articles dropped).
    private static let articles: Set<String> = ["the", "a", "an"]

    private static func tokenSet(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let cleaned = String(lowered.map { char -> Character in
            (char.isLetter || char.isNumber) ? char : " "
        })
        let tokens = cleaned
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
            .filter { !articles.contains($0) }
        return Set(tokens)
    }
}
