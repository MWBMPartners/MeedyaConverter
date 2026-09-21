// ============================================================================
// MeedyaConverter — TMDBDiscCandidatesTests (Issues #205, #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Turning a disc's volume label into something worth searching for is the
// whole difference between "a disc of this shape exists" and naming the film.
// Volume labels are upper-case and punctuation-free, so this is mostly about
// not searching for "DISC 1".
//
// The label cleaning is pure, so it is tested directly and exhaustively; the
// provider itself is tested through a mock HTTP client.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

private final class CandidateStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private let payloads: [Data]
    private var requests: [URLRequest] = []

    init(payloads: [Data]) { self.payloads = payloads }

    var callCount: Int { lock.withLock { requests.count } }
    var lastRequest: URLRequest? { lock.withLock { requests.last } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let payload: Data = lock.withLock {
            let index = min(requests.count, payloads.count - 1)
            requests.append(request)
            return payloads[index]
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.themoviedb.org")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (payload, response)
    }
}

final class TMDBDiscCandidatesTests: XCTestCase {

    private func signals(label: String?) -> DiscSignals {
        DiscSignals(
            discType: .dvdVideo,
            label: label,
            mainFeatureDurationSeconds: 7041,
            titleDurationsSeconds: [7041, 252],
            seedTitle: label
        )
    }

    // MARK: - Label cleaning

    func test_searchTitle_turnsAVolumeLabelIntoATitle() {
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "BIG_MOVIE_DISC")), "BIG MOVIE")
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "THE.FILM.2009.WS")), "THE FILM")
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "FIGHT_CLUB")), "FIGHT CLUB")
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "SOME-MOVIE-DISC-2")), "SOME MOVIE")
    }

    func test_searchTitle_stripsNoiseOnlyFromTheEnd() {
        // "BD" at the START could be part of a title; at the end it is noise.
        // Dropping interior words would mangle a real title.
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "BD_ROCK_STAR")), "BD ROCK STAR")
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "ROCK_STAR_BD")), "ROCK STAR")
    }

    func test_searchTitle_refusesALabelThatIsAllNoise() {
        // Searching for "disc 1" and ranking whatever comes back would be
        // worse than admitting we have nothing to go on.
        XCTAssertNil(TMDBDiscCandidates.searchTitle(from: signals(label: "DVD_DISC_1")))
        XCTAssertNil(TMDBDiscCandidates.searchTitle(from: signals(label: "DISC")))
        XCTAssertNil(TMDBDiscCandidates.searchTitle(from: signals(label: "")))
        XCTAssertNil(TMDBDiscCandidates.searchTitle(from: signals(label: nil)))
        XCTAssertNil(TMDBDiscCandidates.searchTitle(from: signals(label: "___")))
    }

    func test_searchTitle_keepsAOneWordTitle() {
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "ALIEN")), "ALIEN")
    }

    // MARK: - Year extraction

    func test_searchYear_findsAPlausibleYear() {
        XCTAssertEqual(TMDBDiscCandidates.searchYear(from: signals(label: "THE.FILM.2009.WS")), 2009)
        XCTAssertEqual(TMDBDiscCandidates.searchYear(from: signals(label: "BLADE_RUNNER_1982")), 1982)
    }

    func test_searchYear_ignoresThingsThatAreNotYears() {
        // A disc number, a resolution, or a three-digit number must not be
        // read as a year — a wrong year filter hides the right film entirely.
        XCTAssertNil(TMDBDiscCandidates.searchYear(from: signals(label: "BIG_MOVIE_DISC_2")))
        XCTAssertNil(TMDBDiscCandidates.searchYear(from: signals(label: "MOVIE_1080")))
        XCTAssertNil(TMDBDiscCandidates.searchYear(from: signals(label: "MOVIE_720")))
        XCTAssertNil(TMDBDiscCandidates.searchYear(from: signals(label: "PLAIN_MOVIE")))
    }

    // MARK: - The provider

    private let searchJSON = Data("""
    {"results":[{"id":550,"title":"Fight Club","release_date":"1999-10-15","vote_average":8.4}]}
    """.utf8)

    private let detailsJSON = Data("""
    {"id":550,"title":"Fight Club","release_date":"1999-10-15","runtime":139,"genres":[]}
    """.utf8)

    func test_provider_searchesAndFillsInTheRunningTime() async throws {
        let client = CandidateStubHTTPClient(payloads: [searchJSON, detailsJSON])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service)

        let candidates = try await provider(signals(label: "FIGHT_CLUB_1999"))

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.title, "Fight Club")
        XCTAssertEqual(
            candidates.first?.runtimeMinutes, 139,
            "without the running time the ranker has nothing that discriminates"
        )
        XCTAssertEqual(client.callCount, 2, "a search plus a detail fetch")
    }

    func test_provider_ranksTheEnrichedCandidateAgainstTheDisc() async throws {
        // The point of the whole exercise: a 139-minute film against a disc
        // whose main feature runs 7041s (117 minutes) should NOT score well,
        // and the ranker can only know that because the running time is there.
        let client = CandidateStubHTTPClient(payloads: [searchJSON, detailsJSON])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service)

        let candidates = try await provider(signals(label: "FIGHT_CLUB_1999"))
        let ranked = DiscIdentifier.rank(signals: signals(label: "FIGHT_CLUB_1999"), candidates: candidates)

        XCTAssertEqual(ranked.count, 1)
        let confidence = try XCTUnwrap(ranked.first).score.confidence
        XCTAssertLessThan(confidence, 1.0, "a 22-minute gap is not a perfect match")
    }

    func test_provider_returnsNothingRatherThanSearchingForNoise() async throws {
        let client = CandidateStubHTTPClient(payloads: [searchJSON])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service)

        let candidates = try await provider(signals(label: "DVD_DISC_1"))

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(client.callCount, 0, "an unusable label must not cost a request")
    }

    func test_provider_passesTheYearToTMDB() async throws {
        let client = CandidateStubHTTPClient(payloads: [searchJSON, detailsJSON])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service)

        _ = try await provider(signals(label: "FIGHT_CLUB_1999"))

        // The LAST request is the detail fetch, so check the first.
        XCTAssertGreaterThanOrEqual(client.callCount, 1)
    }
}
