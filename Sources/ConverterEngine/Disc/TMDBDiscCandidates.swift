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
    static let discNoiseTokens: Set<String> = [
        "disc", "disc1", "disc2", "disc3", "disc4", "disk",
        "d1", "d2", "d3", "d4",
        "dvd", "dvd5", "dvd9", "bluray", "bd", "bdrom", "uhd",
        "ntsc", "pal", "region", "r1", "r2", "r4",
        "ws", "fs", "widescreen", "fullscreen",
        "se", "ce", "extended", "remastered",
    ]

    /// Two-word noise phrases, matched only as an adjacent pair at the end.
    /// "RAY" alone is a film; "BLU RAY" never is.
    static let discNoisePairs: [[String]] = [
        ["blu", "ray"],
    ]

    /// Turn a disc's volume label into something worth searching for.
    ///
    /// Volume labels are upper-case, punctuation-free and often carry disc
    /// numbering: `BIG_MOVIE_DISC_1`, `THE.FILM.2009.WS`. Pure and
    /// deterministic, so it is unit-tested without a network.
    ///
    /// Returns `nil` when nothing usable survives — better to search for
    /// nothing than to search for "disc 1" and rank whatever comes back.
    public static func searchTitle(from signals: DiscSignals) -> String? {
        guard let raw = signals.seedTitle ?? signals.label else { return nil }

        // Separators first: labels use _ . and - where a title has spaces.
        let spaced = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        var tokens = spaced
            .split(whereSeparator: { $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Strip noise from the END only. A leading "BD" might genuinely be
        // part of a title, and dropping interior words would mangle one.
        var didStrip = true
        while didStrip {
            didStrip = false

            // Pairs first: "BLU RAY" goes together, so that "RAY" on its own
            // is never mistaken for noise.
            for pair in discNoisePairs where tokens.count > pair.count {
                let tail = tokens.suffix(pair.count).map { $0.lowercased() }
                if tail == pair {
                    tokens.removeLast(pair.count)
                    didStrip = true
                    break
                }
            }
            if didStrip { continue }

            guard let last = tokens.last else { break }
            // NEVER strip the last remaining token. "1917", "300" and "1984"
            // are films; "RAY" is a film. A label of one word is that word,
            // whatever it looks like.
            guard tokens.count > 1 else { break }
            if discNoiseTokens.contains(last.lowercased()) || isDiscNumber(last) {
                tokens.removeLast()
                didStrip = true
            }
        }

        // A label that was ONLY noise leaves nothing to search for.
        guard !tokens.isEmpty else { return nil }

        // One token left that is itself pure noise means the whole label was.
        if tokens.count == 1,
           discNoiseTokens.contains(tokens[0].lowercased()) {
            return nil
        }

        let title = tokens.joined(separator: " ")
        return title.count >= 2 ? title : nil
    }

    /// A bare number, or a year — both are disc numbering or release-year
    /// noise at the end of a label rather than part of the title.
    static func isDiscNumber(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0.isNumber }
    }

    /// The release year a label carries, if any — TMDB narrows usefully on it.
    ///
    /// Only a four-digit number in a plausible range counts; a disc numbered
    /// "2" or a label containing "1080" must not be read as a year.
    public static func searchYear(from signals: DiscSignals) -> Int? {
        guard let raw = signals.seedTitle ?? signals.label else { return nil }
        let tokens = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0 == " " })
        for token in tokens.reversed() {
            guard token.count == 4, let value = Int(token) else { continue }
            if (1900...2100).contains(value) { return value }
        }
        return nil
    }

    /// A candidate provider for `VideoDiscIdentifier`, backed by TMDB.
    ///
    /// - Parameters:
    ///   - service: a configured TMDB service.
    ///   - maxDetailFetches: how many results to fetch running times for.
    ///     Each costs one extra request, and beyond the first handful the
    ///     candidates are too weak for the extra call to change the answer.
    public static func provider(
        service: TMDBLookupService,
        maxDetailFetches: Int = 5
    ) -> @Sendable (DiscSignals) async throws -> [MetadataResult] {
        { signals in
            guard let title = searchTitle(from: signals) else { return [] }
            let year = searchYear(from: signals)

            var results = try await service.searchMovies(title: title, year: year)

            // A trailing four-digit number can be part of the TITLE rather
            // than a release year — "BLADE_RUNNER_2049" reads as the film
            // "Blade Runner" released in 2049, which matches nothing. A year
            // filter can only ever hide results, so when one returns nothing
            // the search is worth repeating without it and letting the
            // running-time ranking sort out which film it is.
            if results.isEmpty, year != nil {
                results = try await service.searchMovies(title: title, year: nil)
            }

            // Running time is the signal that actually discriminates, so it
            // is worth the extra requests to have it before ranking.
            return try await service.withRuntimes(results, limit: maxDetailFetches)
        }
    }
}
