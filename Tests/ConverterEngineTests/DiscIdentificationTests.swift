// ============================================================================
// MeedyaConverter — DiscIdentificationTests (Issue #502, slice 1)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Coverage for the #502 slice-1 disc-identification "brain": the pure,
// deterministic ranking of candidate matches against a disc's own content
// signals (running time, title text, year), plus the `DiscSignals.from(...)`
// factory and the `buildQuery(...)` helper.
//
// Everything under test is `public`; no `@testable import` (matching the
// repo convention). No network, no hardware, no decryption — pure logic.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class DiscIdentificationTests: XCTestCase {

    // Helper: a candidate identity with just the fields the ranker reads.
    private func candidate(
        id: String,
        title: String,
        year: Int? = nil,
        runtimeMinutes: Int? = nil
    ) -> MetadataResult {
        MetadataResult(
            source: .tmdb,
            externalId: id,
            title: title,
            year: year,
            runtimeMinutes: runtimeMinutes
        )
    }

    // MARK: - Ranking

    /// The exact running-time + title + year match should come first, and score 1.0.
    func test_rank_exactMatchWinsAndScoresOne() {
        let signals = DiscSignals(
            discType: .dvdVideo,
            mainFeatureDurationSeconds: 136 * 60, // 8160s
            seedTitle: "The Matrix",
            seedYear: 1999
        )
        let candidates = [
            candidate(id: "reloaded", title: "The Matrix Reloaded", year: 2003, runtimeMinutes: 138),
            candidate(id: "matrix", title: "The Matrix", year: 1999, runtimeMinutes: 136),
        ]

        let ranked = DiscIdentifier.rank(signals: signals, candidates: candidates)

        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked.first?.candidate.externalId, "matrix")
        XCTAssertEqual(ranked.first?.score.confidence ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertTrue(ranked.first?.score.reason.contains("Running time matches closely") ?? false)
        // The wrong film is still scored but ranked lower.
        XCTAssertEqual(ranked.last?.candidate.externalId, "reloaded")
        XCTAssertLessThan(ranked.last?.score.confidence ?? 1, 1.0)
    }

    /// A wrong running time should sink a candidate even if its title matches.
    func test_rank_wrongRuntimeSinksTitleMatch() {
        let signals = DiscSignals(
            discType: .dvdVideo,
            mainFeatureDurationSeconds: 90 * 60,
            seedTitle: "Some Film"
        )
        let candidates = [
            candidate(id: "wrongLength", title: "Some Film", runtimeMinutes: 300),
            candidate(id: "rightLength", title: "Some Film", runtimeMinutes: 90),
        ]

        let ranked = DiscIdentifier.rank(signals: signals, candidates: candidates)
        XCTAssertEqual(ranked.first?.candidate.externalId, "rightLength")
    }

    /// When running time and title match equally, a matching year raises the
    /// candidate's confidence and ranks it first.
    func test_rank_matchingYearRanksHigher() {
        let signals = DiscSignals(
            discType: .dvdVideo,
            mainFeatureDurationSeconds: 120 * 60,
            seedTitle: "Twin",
            seedYear: 2010
        )
        let candidates = [
            candidate(id: "wrongYear", title: "Twin", year: 1980, runtimeMinutes: 120),
            candidate(id: "rightYear", title: "Twin", year: 2010, runtimeMinutes: 120),
        ]

        let ranked = DiscIdentifier.rank(signals: signals, candidates: candidates)
        XCTAssertEqual(ranked.first?.candidate.externalId, "rightYear")
        XCTAssertEqual(ranked.first?.score.yearScore, 1.0)
        XCTAssertEqual(ranked.last?.score.yearScore, 0.0)
    }

    /// With equal (zero) confidence, the smaller running-time gap wins the tie-break.
    func test_rank_tieBreakBySmallerRuntimeGap() {
        let signals = DiscSignals(
            discType: .dvdVideo,
            mainFeatureDurationSeconds: 60 * 60 // tolerance = max(300, 720) = 720s
        )
        let candidates = [
            candidate(id: "farther", title: "X", runtimeMinutes: 300), // gap 14400 → score 0
            candidate(id: "closer", title: "Y", runtimeMinutes: 200),  // gap  8400 → score 0
        ]

        let ranked = DiscIdentifier.rank(signals: signals, candidates: candidates)
        // Both score 0 confidence (no title/year signals given); closer gap first.
        XCTAssertEqual(ranked.first?.candidate.externalId, "closer")
        XCTAssertEqual(ranked.first?.score.confidence ?? 1, 0.0, accuracy: 0.0001)
    }

    /// No comparable signals → confidence 0 for all, original order preserved.
    func test_rank_noSignals_isStableAndZero() {
        let signals = DiscSignals(discType: .dvdVideo) // nothing to compare
        let candidates = [
            candidate(id: "a", title: "Alpha", year: 2001, runtimeMinutes: 100),
            candidate(id: "b", title: "Beta", year: 2002, runtimeMinutes: 110),
            candidate(id: "c", title: "Gamma", year: 2003, runtimeMinutes: 120),
        ]

        let ranked = DiscIdentifier.rank(signals: signals, candidates: candidates)
        XCTAssertEqual(ranked.map { $0.candidate.externalId }, ["a", "b", "c"])
        XCTAssertTrue(ranked.allSatisfy { $0.score.confidence == 0.0 })
        XCTAssertEqual(ranked.first?.score.reason, "No comparable signals were available.")
    }

    /// An empty candidate list gives an empty result.
    func test_rank_emptyCandidates() {
        let signals = DiscSignals(discType: .dvdVideo, seedTitle: "Anything")
        XCTAssertTrue(DiscIdentifier.rank(signals: signals, candidates: []).isEmpty)
    }

    /// A disc signal the candidate cannot corroborate (missing runtime) scores 0
    /// on that axis but is not disqualified.
    func test_rank_candidateMissingRuntimeScoresZeroThere() {
        let signals = DiscSignals(
            discType: .dvdVideo,
            mainFeatureDurationSeconds: 100 * 60,
            seedTitle: "Film"
        )
        let ranked = DiscIdentifier.rank(
            signals: signals,
            candidates: [candidate(id: "noRuntime", title: "Film")] // no runtimeMinutes
        )
        XCTAssertEqual(ranked.first?.score.runtimeScore, 0.0)
        XCTAssertEqual(ranked.first?.score.titleScore ?? 0, 1.0, accuracy: 0.0001)
        // confidence = titleWeight(0.35) * 1.0 only.
        XCTAssertEqual(ranked.first?.score.confidence ?? 0, 0.35, accuracy: 0.0001)
    }

    // MARK: - Title similarity

    func test_tokenSimilarity_ignoresLeadingArticle() {
        XCTAssertEqual(DiscIdentifier.tokenSimilarity("The Matrix", "Matrix"), 1.0, accuracy: 0.0001)
    }

    func test_tokenSimilarity_exactMatch() {
        XCTAssertEqual(DiscIdentifier.tokenSimilarity("Blade Runner", "blade runner"), 1.0, accuracy: 0.0001)
    }

    func test_tokenSimilarity_unrelatedIsZero() {
        XCTAssertEqual(DiscIdentifier.tokenSimilarity("The Matrix", "Inception"), 0.0, accuracy: 0.0001)
    }

    // MARK: - DiscSignals.from(...)

    func test_from_picksMainFeatureAndStreams() {
        let info = DiscInfo(discType: .dvdVideo, label: "THE_MATRIX", totalDuration: 0)
        let titles = [
            DiscTitle(number: 1, duration: 600, chapterCount: 2, isMainFeature: false),
            DiscTitle(
                number: 2,
                duration: 8160,
                chapterCount: 32,
                audioStreams: [DiscAudioStream(index: 0, language: "eng")],
                subtitleStreams: [
                    DiscSubtitleStream(index: 0, language: "eng"),
                    DiscSubtitleStream(index: 1, language: "fra"),
                ],
                isMainFeature: true
            ),
        ]

        let signals = DiscSignals.from(discInfo: info, titles: titles)

        XCTAssertEqual(signals.mainFeatureDurationSeconds, 8160)
        XCTAssertEqual(signals.chapterCount, 32)
        XCTAssertEqual(signals.subtitleLanguages, ["eng", "fra"])
        XCTAssertEqual(signals.audioLanguages, ["eng"])
        XCTAssertEqual(signals.titleDurationsSeconds, [600, 8160])
        XCTAssertEqual(signals.seedTitle, "THE MATRIX") // label cleaned of underscores
        XCTAssertNil(signals.seedYear)
        XCTAssertNil(signals.mediaTypeHint) // video with no filename hint
    }

    func test_from_longestTitleWhenNoMainFeatureFlag() {
        let info = DiscInfo(discType: .bluray)
        let titles = [
            DiscTitle(number: 1, duration: 300),
            DiscTitle(number: 2, duration: 7200),
            DiscTitle(number: 3, duration: 1200),
        ]
        let signals = DiscSignals.from(discInfo: info, titles: titles)
        XCTAssertEqual(signals.mainFeatureDurationSeconds, 7200)
    }

    func test_from_seedsTitleAndYearFromFilename() {
        let info = DiscInfo(discType: .dvdVideo, label: "DVD_VOLUME")
        let signals = DiscSignals.from(
            discInfo: info,
            titles: [DiscTitle(number: 1, duration: 5000, isMainFeature: true)],
            seedFilename: "The Matrix (1999).mkv"
        )
        XCTAssertEqual(signals.seedTitle, "The Matrix")
        XCTAssertEqual(signals.seedYear, 1999)
        XCTAssertEqual(signals.mediaTypeHint, .movie)
    }

    // MARK: - buildQuery(...)

    func test_buildQuery_audioDiscIsMusic() {
        let signals = DiscSignals(discType: .audioCd, seedTitle: "Some Album")
        let query = DiscIdentifier.buildQuery(from: signals)
        XCTAssertEqual(query.mediaType, .music)
        XCTAssertEqual(query.title, "Some Album")
    }

    func test_buildQuery_videoDiscDefaultsToMovieAndCarriesYear() {
        let signals = DiscSignals(discType: .dvdVideo, seedTitle: "The Matrix", seedYear: 1999)
        let query = DiscIdentifier.buildQuery(from: signals)
        XCTAssertEqual(query.mediaType, .movie)
        XCTAssertEqual(query.title, "The Matrix")
        XCTAssertEqual(query.year, 1999)
    }

    func test_buildQuery_honoursTVHint() {
        let signals = DiscSignals(discType: .dvdVideo, mediaTypeHint: .tvShow, seedTitle: "Some Show")
        XCTAssertEqual(DiscIdentifier.buildQuery(from: signals).mediaType, .tvShow)
    }

    func test_buildQuery_fallsBackToCleanedLabelForTitle() {
        let signals = DiscSignals(discType: .dvdVideo, label: "MY_MOVIE_DISC")
        XCTAssertEqual(DiscIdentifier.buildQuery(from: signals).title, "MY MOVIE DISC")
    }
}
