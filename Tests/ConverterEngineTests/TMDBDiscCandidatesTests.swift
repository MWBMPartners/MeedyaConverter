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
    var calls: [URLRequest] { lock.withLock { requests } }
    var firstRequest: URLRequest? { lock.withLock { requests.first } }
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

    func test_searchTitle_doesNotDestroyRealTitlesThatLookLikeNoise() {
        // Each of these was silently broken by the first version of the
        // stripping rules. A word that IS part of a title must never be
        // treated as disc noise: the search then finds the wrong film, and
        // the ranker may rank it confidently.
        let realTitles = [
            "RAY": "RAY",                       // Ray (2004)
            "1917": "1917",                     // a title that is only a number
            "300": "300",
            "1984": "1984",
            "THE_BLIND_SIDE": "THE BLIND SIDE", // "side" is not noise
            "PLAN_B": "PLAN B",                 // nor is a bare letter
            "SIDE_B": "SIDE B",
        ]
        for (label, expected) in realTitles {
            XCTAssertEqual(
                TMDBDiscCandidates.searchTitle(from: signals(label: label)),
                expected,
                "\(label) is a real film title, not disc noise"
            )
        }
    }

    func test_searchTitle_stillStripsBluRayAsAPair() {
        // "RAY" alone is a film; "BLU RAY" never is. Handling it as a pair is
        // what lets both be true.
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "ROCK_STAR_BLU_RAY")), "ROCK STAR")
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "THE_FILM_BLURAY")), "THE FILM")
    }

    func test_searchTitle_neverStripsTheLastRemainingToken() {
        // A label of one word is that word, whatever it looks like.
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "2012")), "2012")
    }

    // MARK: - Codex r1 F8: numbers that are part of the title must survive

    func test_searchTitle_keepsANumberThatIsPartOfTheTitle() {
        // Every one of these was destroyed by the REJECTED earlier rule
        // ("strip every trailing all-digit word, repeatedly, until one word
        // is left"): that rule could not tell a disc's own numbering from a
        // number that IS the film's title, because it never looked at what
        // came before the number.
        let currentYear = 2026
        let cases: [String: String] = [
            "APOLLO_13": "APOLLO 13",
            "FRIDAY_THE_13TH_PART_8": "FRIDAY THE 13TH PART 8",
            "KILL_BILL_VOL_1": "KILL BILL VOL 1",
            "DISTRICT_9": "DISTRICT 9",
            "SUMMER_OF_84": "SUMMER OF 84",
        ]
        for (label, expected) in cases {
            XCTAssertEqual(
                TMDBDiscCandidates.searchTitle(from: signals(label: label), currentYear: currentYear),
                expected,
                "\(label) should keep its number"
            )
        }
    }

    func test_searchTitle_stripsAYearButKeepsANumberThatIsPartOfTheTitle() {
        let currentYear = 2026
        XCTAssertEqual(
            TMDBDiscCandidates.searchTitle(from: signals(label: "THE_MATRIX_1999"), currentYear: currentYear),
            "THE MATRIX"
        )
        XCTAssertEqual(
            TMDBDiscCandidates.searchYear(from: signals(label: "THE_MATRIX_1999"), currentYear: currentYear),
            1999
        )

        // The "3" is the film's own number (Back to the Future Part 3); the
        // "1990" is the disc's release year. Both must be told apart
        // correctly, from the SAME label, in one pass.
        XCTAssertEqual(
            TMDBDiscCandidates.searchTitle(from: signals(label: "BACK_TO_THE_FUTURE_3_1990"), currentYear: currentYear),
            "BACK TO THE FUTURE 3"
        )
        XCTAssertEqual(
            TMDBDiscCandidates.searchYear(from: signals(label: "BACK_TO_THE_FUTURE_3_1990"), currentYear: currentYear),
            1990
        )
    }

    func test_searchTitle_treatsANumberBeyondThePlausibleYearRangeAsPartOfTheTitle() {
        // "2049" is not a plausible release year when today is 2026 -- it
        // must stay part of the searched title text rather than vanish as a
        // bogus filter that then matches nothing.
        XCTAssertEqual(
            TMDBDiscCandidates.searchTitle(from: signals(label: "BLADE_RUNNER_2049"), currentYear: 2026),
            "BLADE RUNNER 2049"
        )
        XCTAssertNil(TMDBDiscCandidates.searchYear(from: signals(label: "BLADE_RUNNER_2049"), currentYear: 2026))
    }

    func test_searchTitle_stripsASingleFusedDiscNumberToken() {
        // Replaces the old fixed "d1".."d4" / "disc1".."disc4" lists, which
        // matched only four numbers each and let a fifth survive untouched.
        let currentYear = 2026
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "GLADIATOR_D2"), currentYear: currentYear), "GLADIATOR")
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "GLADIATOR_DISC2"), currentYear: currentYear), "GLADIATOR")
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "GLADIATOR_CD1"), currentYear: currentYear), "GLADIATOR")
        XCTAssertEqual(
            TMDBDiscCandidates.searchTitle(from: signals(label: "LOTR_D5"), currentYear: currentYear),
            "LOTR",
            "the old fixed list only went up to d4, so D5 used to survive as if it were part of the title"
        )
    }

    func test_searchTitle_stripsADiscWordFollowedBySeparateNumber() {
        let currentYear = 2026
        XCTAssertEqual(TMDBDiscCandidates.searchTitle(from: signals(label: "BIG_MOVIE_DISC_1"), currentYear: currentYear), "BIG MOVIE")
    }

    func test_searchTitle_neverStripsTheLastTokenEvenAcrossADiscNumberPair() {
        // "1917_DISC_1" strips "DISC" and "1" together as one disc-numbering
        // pair, which would otherwise leave "1917" -- and "1917" the FILM
        // TITLE must still survive, because it is the last remaining token.
        XCTAssertEqual(
            TMDBDiscCandidates.searchTitle(from: signals(label: "1917_DISC_1"), currentYear: 2026),
            "1917"
        )
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
        let best = try XCTUnwrap(ranked.first)
        XCTAssertEqual(
            best.candidate.runtimeMinutes, 139,
            "the ranking is only meaningful because the running time was fetched"
        )
        XCTAssertLessThan(best.score.confidence, 1.0, "a 22-minute gap is not a perfect match")
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

        // The FIRST request is the search; the last is the detail fetch.
        let searchURL = try XCTUnwrap(client.firstRequest?.url?.absoluteString)
        XCTAssertTrue(searchURL.contains("year=1999"), "the label's year should narrow the search")
    }

    func test_provider_sendsNoYearWhenTheLabelHasNone() async throws {
        let client = CandidateStubHTTPClient(payloads: [searchJSON, detailsJSON])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service)

        _ = try await provider(signals(label: "FIGHT_CLUB"))

        let searchURL = try XCTUnwrap(client.firstRequest?.url?.absoluteString)
        XCTAssertFalse(searchURL.contains("year="), "inventing a year would hide the right film")
    }

    /// The value of one query-string parameter on a request's URL, decoded
    /// (not a raw substring match) so a test cannot pass by accident on a
    /// coincidental overlap between two different parameter values.
    private func queryValue(_ request: URLRequest?, name: String) -> String? {
        guard let url = request?.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    // MARK: - The provider's fallback chain (Codex r1 F8)

    func test_provider_putsTheYearBackIntoTheTitleWhenTheFilteredSearchFindsNothing() async throws {
        // Step (2) of the fallback: a year-filtered search that finds
        // nothing is retried with the year folded back into the title text
        // instead of being dropped outright -- TMDB's own fuzzy matching
        // sometimes finds a film that a strict `year=` filter misses (a
        // regional release date, a re-release, a disc pressed a year late).
        let empty = Data(#"{"results":[]}"#.utf8)
        let client = CandidateStubHTTPClient(payloads: [empty, searchJSON, detailsJSON])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service, currentYear: 2026)

        let candidates = try await provider(signals(label: "THE_MATRIX_1999"))

        XCTAssertEqual(candidates.count, 1, "the second attempt should have found the film")
        XCTAssertEqual(client.calls.count, 3, "a filtered search, a year-folded-in retry, then one detail fetch")
        XCTAssertEqual(queryValue(client.calls[0], name: "query"), "THE MATRIX")
        XCTAssertEqual(queryValue(client.calls[0], name: "year"), "1999")
        XCTAssertEqual(queryValue(client.calls[1], name: "query"), "THE MATRIX 1999")
        XCTAssertNil(queryValue(client.calls[1], name: "year"), "the second attempt must not repeat the year filter")
    }

    func test_provider_keepsAnOutOfRangeNumberInTheTitleAndSearchesOnlyOnce() async throws {
        // "2049" is not a plausible release year in 2026 (Codex r1 F8), so it
        // stays part of the title text and there is only ONE distinct
        // request to make. The old code always retried once more without a
        // year filter -- which here would just repeat the identical request.
        let client = CandidateStubHTTPClient(payloads: [searchJSON, detailsJSON])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service, currentYear: 2026)

        _ = try await provider(signals(label: "BLADE_RUNNER_2049"))

        XCTAssertEqual(client.calls.count, 2, "one search plus one detail fetch -- no duplicate retry")
        XCTAssertEqual(queryValue(client.calls[0], name: "query"), "BLADE RUNNER 2049")
        XCTAssertNil(queryValue(client.calls[0], name: "year"))
    }

    func test_provider_doesNotRepeatAnIdenticalRequestWhenThereIsNoYear() async throws {
        // With no year at all, "the filtered search" (there is nothing to
        // filter on) and "the final no-filter retry" are the SAME request
        // text, and it must be sent only once.
        let empty = Data(#"{"results":[]}"#.utf8)
        let client = CandidateStubHTTPClient(payloads: [empty])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service, currentYear: 2026)

        let candidates = try await provider(signals(label: "FIGHT_CLUB"))

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(client.callCount, 1, "the de-duplicated fallback chain has only one distinct request to make")
    }

    func test_provider_dropsATrailingNumberOnlyAsALastResort() async throws {
        // Exercises all four search fallback steps IN THE FALLBACK-REVIEW-R2
        // FINDING 1 ORDER (1, 2, 4, 3 in the old numbering — see the comment
        // above the attempt chain): the year-filtered search, the
        // year-folded-into-the-title retry, the PLAIN title with no filter,
        // and only then dropping the trailing "3" (kept during cleaning
        // because it is the film's own number) in case it was disc numbering
        // after all. Each one runs ONLY because the step before it found
        // nothing — and the plain title runs BEFORE the number is dropped,
        // because it is strictly narrower and can never rank a wrong film in
        // the franchise confidently the way the number-dropped search can.
        let empty = Data(#"{"results":[]}"#.utf8)
        let client = CandidateStubHTTPClient(payloads: [empty, empty, empty, searchJSON, detailsJSON])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service, currentYear: 2026)

        let candidates = try await provider(signals(label: "BACK_TO_THE_FUTURE_3_1990"))

        XCTAssertEqual(candidates.count, 1, "the fourth attempt should have found the film")
        XCTAssertEqual(client.calls.count, 5, "four search fallbacks then one detail fetch")
        XCTAssertEqual(queryValue(client.calls[0], name: "query"), "BACK TO THE FUTURE 3")
        XCTAssertEqual(queryValue(client.calls[0], name: "year"), "1990")
        XCTAssertEqual(queryValue(client.calls[1], name: "query"), "BACK TO THE FUTURE 3 1990")
        XCTAssertNil(queryValue(client.calls[1], name: "year"))
        XCTAssertEqual(
            queryValue(client.calls[2], name: "query"), "BACK TO THE FUTURE 3",
            "the plain title with no filter must run before the number is dropped"
        )
        XCTAssertNil(queryValue(client.calls[2], name: "year"))
        XCTAssertEqual(
            queryValue(client.calls[3], name: "query"), "BACK TO THE FUTURE",
            "dropping the number is the true last resort, tried only once the plain title has also failed"
        )
        XCTAssertNil(queryValue(client.calls[3], name: "year"))
    }

    func test_provider_triesThePlainTitleBeforeDroppingItsNumber_halloween5() async throws {
        // The regression scenario from fallback review r2, finding 1: the
        // film is "Halloween 5" (1989), but the disc's label carries its DVD
        // release year, 1990, so steps 1-2 (the year-filtered search and the
        // year-folded-into-the-title retry) both find nothing. The FIX under
        // test is that step 3 — "HALLOWEEN 5" with NO filter — must run and
        // succeed before the trailing "5" is ever dropped. Before this fix,
        // dropping the number ran first and searched for "HALLOWEEN" alone,
        // which returns the whole franchise; only the first few results get a
        // running-time lookup, and "Halloween 5" could fall outside them and
        // never be found at all. So no request for the bare franchise name
        // must ever be sent once the plain title has already succeeded.
        let empty = Data(#"{"results":[]}"#.utf8)
        let client = CandidateStubHTTPClient(payloads: [empty, empty, searchJSON, detailsJSON])
        let service = TMDBLookupService(apiKey: "0123456789abcdef0123456789abcdef", httpClient: client)
        let provider = TMDBDiscCandidates.provider(service: service, currentYear: 2026)

        let candidates = try await provider(signals(label: "HALLOWEEN_5_1990"))

        XCTAssertEqual(candidates.count, 1, "the plain title with no filter should have found the film")
        XCTAssertEqual(client.calls.count, 4, "two filtered/text attempts, the plain-title success, then one detail fetch")
        XCTAssertEqual(queryValue(client.calls[0], name: "query"), "HALLOWEEN 5")
        XCTAssertEqual(queryValue(client.calls[0], name: "year"), "1990")
        XCTAssertEqual(queryValue(client.calls[1], name: "query"), "HALLOWEEN 5 1990")
        XCTAssertNil(queryValue(client.calls[1], name: "year"))
        XCTAssertEqual(
            queryValue(client.calls[2], name: "query"), "HALLOWEEN 5",
            "the plain title (still \"HALLOWEEN 5\") must succeed before the number is dropped"
        )
        XCTAssertNil(queryValue(client.calls[2], name: "year"))
        for call in client.calls {
            XCTAssertNotEqual(
                queryValue(call, name: "query"), "HALLOWEEN",
                "the broad, number-dropped search must never be sent once the plain title has already succeeded"
            )
        }
    }
}
