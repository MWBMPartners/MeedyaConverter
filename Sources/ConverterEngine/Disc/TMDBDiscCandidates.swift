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
    static let discNoiseTokens: Set<String> = [
        "disc", "disc1", "disc2", "disc3", "disc4", "disk",
        "d1", "d2", "d3", "d4",
        "dvd", "dvd5", "dvd9", "bluray", "blu", "ray", "bd", "bdrom", "uhd",
        "ntsc", "pal", "region", "r1", "r2", "r4",
        "ws", "fs", "widescreen", "fullscreen",
        "se", "ce", "extended", "remastered",
        "side", "a", "b",
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
        while let last = tokens.last,
              discNoiseTokens.contains(last.lowercased()) || isDiscNumber(last) {
            tokens.removeLast()
        }

        // A label that was ONLY noise leaves nothing to search for.
        guard !tokens.isEmpty else { return nil }

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
            let results = try await service.searchMovies(
                title: title,
                year: searchYear(from: signals)
            )
            // Running time is the signal that actually discriminates, so it
            // is worth the extra requests to have it before ranking.
            return try await service.withRuntimes(results, limit: maxDetailFetches)
        }
    }
}
