// ============================================================================
// MeedyaConverter — TMDB candidates for a video disc (Issues #205, #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The missing supply of candidates for `VideoDiscIdentifier`. The disc
// identification chain has run end to end since #502, but nothing fed it
// anything to rank, so a DVD could only ever be recorded as "a disc of this
// shape exists". This turns what the disc says about itself into a TMDB
// search.
//
// FILMS ONLY, deliberately. The strongest signal `DiscIdentifier.rank` has is
// running time, and TMDB reports a single running time for a film but an
// array of typical episode lengths for a series — which is not the same
// quantity and would rank against a disc's main feature wrongly. Searching
// series as well would widen coverage while making the ranking less
// trustworthy, and a confident wrong answer is worse here than no answer.
// Television is a follow-up that needs its own comparison rule.
//
// ⚠️ SEARCH RESULTS HAVE NO RUNNING TIME — TMDB only returns it from the
// details endpoint. So this enriches the top few results before handing them
// back; without that step every candidate scores alike on the one signal
// that actually discriminates.
//
// ⚠️ CODEX REVIEW ROUND 1, FINDING 8 (#205) — the cleaner used to delete real
// title numbers. It stripped every trailing all-digit WORD, repeatedly, until
// one word was left: "APOLLO_13" became "APOLLO", "DISTRICT_9" became
// "DISTRICT", "TOY_STORY_3" became "TOY STORY", "SUMMER_OF_84" became
// "SUMMER OF". That rule ("strip all trailing numbers") is REJECTED: it could
// not tell a disc's own numbering ("_DISC_1") from a number that IS the film's
// title, because it never looked at what preceded the number. Short titles
// are exactly where this mattered most — TMDB returns one page of results and
// only the first few (`maxDetailFetches`) get a running-time lookup, so
// searching for the wrong text pushes the real film out of that page
// entirely, and the ranker never gets a chance to consider it.
//
// The replacement keeps a number UNLESS something specific marks it as disc
// numbering rather than title: a word fused with its number ("D5", "DISC2",
// "CD1"), a disc word immediately followed by a separate number ("DISC 1"),
// or a plausible release year (which is reported separately, not just
// deleted). Anything else — "PART 8", "VOL 1", a bare "9" — is kept. See
// `clean(_:currentYear:)` below for the exact rule order.
// ============================================================================

import Foundation

// MARK: - TMDBDiscCandidates

/// Builds a `VideoDiscIdentifier` candidate provider backed by TMDB.
public enum TMDBDiscCandidates {

    /// Tokens that appear in disc volume labels but never in a film's title.
    /// Stripped from the end of a label before searching, because
    /// "BIG_MOVIE_DISC_1" finds nothing while "big movie" finds the film.
    /// ⚠️ EVERY ENTRY HERE IS A WORD THAT CAN NEVER BE A FILM TITLE ON ITS
    /// OWN. That bar is deliberately high, because stripping a word that IS
    /// part of a title searches for the wrong thing — and the ranker may then
    /// confidently mis-rank the result, which is worse than finding nothing.
    ///
    /// Words removed after review, with the films that proved them unsafe:
    /// "ray" (Ray, 2004), "side" (The Blind Side), "a"/"b" (Plan B, Side B).
    /// "ray" is still handled, but only as the pair "blu ray" — see below.
    ///
    /// The fixed, narrow "disc1".."disc4" / "d1".."d4" / "dvd5" / "dvd9"
    /// entries that used to live here are GONE (Codex r1 F8): each matched
    /// only a handful of numbers, so "D5" or "DISC5" quietly survived as if
    /// part of the title. A single word that fuses a disc marker with ANY
    /// 1-2 digit number is now caught generally by
    /// `isFusedDiscNumberToken(_:)` instead, which runs first in
    /// `clean(_:currentYear:)` — so a numbered variant of any word below
    /// never actually reaches this set.
    static let discNoiseTokens: Set<String> = [
        "disc", "disk",
        "dvd", "bluray", "bd", "bdrom", "uhd",
        "ntsc", "pal", "region", "r1", "r2", "r4",
        "ws", "fs", "widescreen", "fullscreen",
        "se", "ce", "extended", "remastered",
    ]

    /// Two-word noise phrases, matched only as an adjacent pair at the end.
    /// "RAY" alone is a film; "BLU RAY" never is.
    static let discNoisePairs: [[String]] = [
        ["blu", "ray"],
    ]

    /// Words that mean "disc" when immediately followed by a SEPARATE 1-2
    /// digit number ("DISC 1", "CD 2"). Deliberately excludes the bare
    /// single-letter "D" here — "D 2" as two separate words is far too
    /// close to plausible title text to strip on sight; "D2" fused into one
    /// word is unambiguous and is handled by `isFusedDiscNumberToken(_:)`.
    private static let discPairMarkerWords: Set<String> = ["disc", "disk", "dvd", "cd", "bd"]

    /// Prefixes that make a single FUSED token ("D5", "DISC2", "CD1", "DVD9")
    /// read as disc numbering rather than a title word, when followed by 1-2
    /// ASCII digits and nothing else. Matches
    /// `^(disc|disk|dvd|cd|bd|d)\d{1,2}$` case-insensitively — checked by
    /// prefix-and-suffix here rather than with `NSRegularExpression`, since
    /// the whole match is one bounded string comparison either way.
    private static let discNumberMarkerPrefixes = ["disc", "disk", "dvd", "cd", "bd", "d"]

    /// True when `token` is ENTIRELY that many-or-fewer ASCII digits `0`-`9`.
    ///
    /// Deliberately NOT `Character.isNumber`: that also accepts other
    /// scripts' digit characters (Arabic-Indic, full-width, Devanagari, …),
    /// which a disc volume label — an old, ASCII-only filesystem convention
    /// — can never legitimately contain, and checking it would make this
    /// function's behaviour depend on Unicode data a label was never
    /// actually written in.
    static func isASCIIDigitToken(_ token: String, maxDigits: Int = Int.max) -> Bool {
        guard !token.isEmpty, token.count <= maxDigits else { return false }
        return token.utf8.allSatisfy { (0x30...0x39).contains($0) }
    }

    /// True for a single word that fuses a disc marker with its number
    /// ("D5", "DISC2", "CD1", "DVD9") — see `discNumberMarkerPrefixes`.
    static func isFusedDiscNumberToken(_ token: String) -> Bool {
        let lower = token.lowercased()
        for prefix in discNumberMarkerPrefixes where lower.hasPrefix(prefix) {
            let digits = String(lower.dropFirst(prefix.count))
            if isASCIIDigitToken(digits, maxDigits: 2) { return true }
        }
        return false
    }

    /// The cleaned title tokens plus any release year found (and removed)
    /// while cleaning. A single struct, not two independent scans, so
    /// `searchTitle` and `searchYear` can never disagree about what was
    /// actually stripped from the same label.
    private struct CleanedLabel {
        var tokens: [String]
        var year: Int?
    }

    /// Split a disc label into tokens the way a volume label actually
    /// separates words: labels are upper-case and punctuation-free, using
    /// `_` `.` and `-` where a real title has spaces.
    private static func tokenize(_ raw: String) -> [String] {
        let spaced = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return spaced
            .split(whereSeparator: { $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Strip trailing noise from `rawTokens`, one recognisable piece at a
    /// time, from the END only, and NEVER touching the last remaining token
    /// — a label of one word is that word, whatever it looks like ("1917",
    /// "300", "1984", "RAY" are all real film titles).
    ///
    /// Checked in this order, each iteration re-examining the (now shorter)
    /// end of the token list:
    ///   1. "BLU RAY" as an adjacent two-word pair — guarded to leave at
    ///      least one token behind, exactly like the disc+number pair below.
    ///   2. A disc word plus a SEPARATE 1-2 digit number ("DISC 1", "CD 2") —
    ///      guarded to `tokens.count > 2`, not just `> 1`, because removing
    ///      TWO tokens at once must still leave at least one behind.
    ///   3. A plausible release year: 1900 up to `currentYear + 1` (a disc
    ///      pressed just ahead of release, or during awards-season
    ///      screeners, still carries a real year). Recorded on the result so
    ///      it can be reported as the search year even though it no longer
    ///      appears in the title text.
    ///   4. A single fused disc-marker-with-number word ("D5", "DISC2").
    ///   5. The existing exact noise words (`discNoiseTokens`).
    /// Anything else — a bare number after PART / VOL / VOLUME / SEASON, or
    /// any other number at all — is left exactly where it is.
    private static func clean(_ rawTokens: [String], currentYear: Int) -> CleanedLabel {
        var tokens = rawTokens
        var year: Int?

        strippingLoop: while tokens.count > 1 {
            // 1. Two-word noise phrases ("BLU RAY").
            for pair in discNoisePairs where tokens.count > pair.count {
                let tail = tokens.suffix(pair.count).map { $0.lowercased() }
                if tail == pair {
                    tokens.removeLast(pair.count)
                    continue strippingLoop
                }
            }

            // 2. A disc word plus a separate 1-2 digit number ("DISC 1").
            if tokens.count > 2 {
                let last = tokens[tokens.count - 1]
                let secondLast = tokens[tokens.count - 2].lowercased()
                if isASCIIDigitToken(last, maxDigits: 2), discPairMarkerWords.contains(secondLast) {
                    tokens.removeLast(2)
                    continue strippingLoop
                }
            }

            let last = tokens[tokens.count - 1]

            // 3. A plausible release year.
            if last.count == 4, isASCIIDigitToken(last), let value = Int(last),
               (1900...(currentYear + 1)).contains(value) {
                year = value
                tokens.removeLast()
                continue strippingLoop
            }

            // 4. A single fused disc-marker-with-number word.
            if isFusedDiscNumberToken(last) {
                tokens.removeLast()
                continue strippingLoop
            }

            // 5. The existing exact noise words.
            if discNoiseTokens.contains(last.lowercased()) {
                tokens.removeLast()
                continue strippingLoop
            }

            break
        }

        return CleanedLabel(tokens: tokens, year: year)
    }

    /// Turn a disc's volume label into something worth searching for.
    ///
    /// Volume labels are upper-case, punctuation-free and often carry disc
    /// numbering: `BIG_MOVIE_DISC_1`, `THE.FILM.2009.WS`. Pure and
    /// deterministic, so it is unit-tested without a network.
    ///
    /// - Parameter currentYear: the ceiling for "is this token a plausible
    ///   release year" is `currentYear + 1`. Defaults to today's real
    ///   calendar year; tests pass an explicit value so they stay
    ///   deterministic across the calendar (a plain Foundation call, so it
    ///   stays a `public` API's default value without a helper symbol).
    ///
    /// Returns `nil` when nothing usable survives — better to search for
    /// nothing than to search for "disc 1" and rank whatever comes back.
    public static func searchTitle(
        from signals: DiscSignals,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) -> String? {
        guard let raw = signals.seedTitle ?? signals.label else { return nil }
        let tokens = tokenize(raw)
        guard !tokens.isEmpty else { return nil }

        let cleaned = clean(tokens, currentYear: currentYear)
        guard !cleaned.tokens.isEmpty else { return nil }

        // One token left that is itself pure noise means the whole label was.
        if cleaned.tokens.count == 1, discNoiseTokens.contains(cleaned.tokens[0].lowercased()) {
            return nil
        }

        let title = cleaned.tokens.joined(separator: " ")
        return title.count >= 2 ? title : nil
    }

    /// The release year a label carries, if any — TMDB narrows usefully on
    /// it. Uses exactly the same cleaning pass (and so the same year range)
    /// as `searchTitle`, so the two can never disagree about what a label's
    /// trailing year token was.
    ///
    /// Only a four-digit number in a plausible range counts; a disc numbered
    /// "2" or a label containing "1080" must not be read as a year. A label
    /// that is a single token is never touched at all — "1917" the film
    /// title is not "1917" the release year filter.
    public static func searchYear(
        from signals: DiscSignals,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) -> Int? {
        guard let raw = signals.seedTitle ?? signals.label else { return nil }
        let tokens = tokenize(raw)
        guard !tokens.isEmpty else { return nil }
        return clean(tokens, currentYear: currentYear).year
    }

    /// Drops a bare trailing 1-2 digit number from an ALREADY-CLEANED title —
    /// used only as a last-resort search fallback, for labels where "_2"
    /// turns out to have meant "disc 2 of this one film" rather than part of
    /// its actual name.
    ///
    /// This is deliberately NOT applied during cleaning itself: more real
    /// titles need the number kept ("Apollo 13", "District 9", "Ocean's 11")
    /// than lose it, so cleaning always keeps it, and only the search
    /// fallback below tries dropping it — and only once every more specific
    /// search has already failed.
    static func droppingTrailingBareNumber(from title: String) -> String? {
        let tokens = title.split(separator: " ").map(String.init)
        guard let last = tokens.last, isASCIIDigitToken(last, maxDigits: 2) else { return nil }
        let remaining = tokens.dropLast()
        guard !remaining.isEmpty else { return nil } // never strip the last remaining word
        return remaining.joined(separator: " ")
    }

    /// A candidate provider for `VideoDiscIdentifier`, backed by TMDB.
    ///
    /// - Parameters:
    ///   - service: a configured TMDB service.
    ///   - maxDetailFetches: how many results to fetch running times for.
    ///     Each costs one extra request, and beyond the first handful the
    ///     candidates are too weak for the extra call to change the answer.
    ///   - currentYear: passed straight through to `searchTitle`/
    ///     `searchYear`; see their documentation.
    public static func provider(
        service: TMDBLookupService,
        maxDetailFetches: Int = 5,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) -> @Sendable (DiscSignals) async throws -> [MetadataResult] {
        { signals in
            guard let title = searchTitle(from: signals, currentYear: currentYear) else { return [] }
            let year = searchYear(from: signals, currentYear: currentYear)

            // A progressively looser chain of searches. Each step below
            // runs ONLY because the step before it came back with nothing —
            // a year filter and a fully-cleaned title can each only ever
            // HIDE the right film, never rank the wrong one confidently, so
            // relaxing them one at a time is always safe. `seenRequestKeys`
            // stops an identical (title, year) request being sent twice,
            // which matters whenever the label had no year at all: step 1
            // and step 3 below are then the exact same request.
            //
            // ⚠️ FALLBACK REVIEW ROUND 2, FINDING 1 (#205) — the number-dropped
            // search (now step 4) used to run BEFORE the plain title with no
            // filter (now step 3). For a label like "HALLOWEEN_5_1990" that
            // put a search for the bare franchise name ("HALLOWEEN") ahead of
            // the film's own title ("HALLOWEEN 5"): TMDB returned the whole
            // franchise, only the first few results get a running-time
            // lookup (`maxDetailFetches`), and "Halloween 5" fell outside
            // them — never even considered by the ranker. The plain title is
            // strictly NARROWER than the number-dropped one (dropping the
            // number can only ever return the same films or more), so it can
            // only find more of the right film, never less. It now runs
            // first, and dropping the number is truly the last resort.
            var attempts: [(title: String, year: Int?)] = []
            var seenRequestKeys = Set<String>()

            func addAttempt(_ attemptTitle: String, year attemptYear: Int?) {
                let key = "\(attemptTitle.lowercased())#\(attemptYear.map(String.init) ?? "")"
                guard seenRequestKeys.insert(key).inserted else { return }
                attempts.append((attemptTitle, attemptYear))
            }

            // (1) The cleaned title, filtered to the label's year if it has
            // one — the most specific, and usually correct, search.
            addAttempt(title, year: year)

            if let year {
                // (2) The year folded back INTO the title text, with no
                // filter. TMDB's search matches loosely enough that this
                // sometimes finds a film a strict `year=` filter misses
                // outright — a regional release date, a re-release, or a
                // disc pressed the year after the film came out.
                addAttempt("\(title) \(year)", year: nil)
            }

            // (3) The plain cleaned title with no filter at all. Broader than
            // (1) and (2) but never narrower than (4) below, so it can only
            // ever find MORE of the right film — never rank a wrong one
            // confidently — and must run before the number is ever dropped.
            addAttempt(title, year: nil)

            // (4) A trailing 1-2 digit number that cleaning deliberately
            // KEPT ("Apollo 13", "District 9") might still have been disc
            // numbering after all ("MOVIE_2" meaning disc 2 of one film).
            // The TRUE last resort: it widens the search past even the plain
            // title (see the finding above — it can confidently rank the
            // wrong film in a franchise), so it only runs once everything
            // else has failed.
            if let numberless = droppingTrailingBareNumber(from: title) {
                addAttempt(numberless, year: nil)
            }

            var results: [MetadataResult] = []
            for attempt in attempts {
                results = try await service.searchMovies(title: attempt.title, year: attempt.year)
                if !results.isEmpty { break }
            }

            // Running time is the signal that actually discriminates, so it
            // is worth the extra requests to have it before ranking.
            return try await service.withRuntimes(results, limit: maxDetailFetches)
        }
    }
}
