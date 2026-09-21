// ============================================================================
// MeedyaConverter — TMDBLookupServiceTests (Issue #205)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The first keyed provider that actually executes. Covered against a mock
// `MetadataHTTPClient` — no network in CI.
//
// Two areas get the most attention, because both are easy to get wrong in a
// way that only shows up in production:
//
//   1. THE API KEY. TMDB issues two different credentials and people paste
//      whichever they find, so both forms must work. And a v3 key travels in
//      the URL, so no error may ever carry one — tests assert the key appears
//      in NO error message, not merely in the ones we remembered to check.
//   2. RUNNING TIME. Search results carry none; only the details endpoint
//      does. Running time is the strongest signal disc identification has, so
//      a result set that silently lacks it ranks everything alike.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// Uniquely named so it never collides with the other stubs in this module.
private final class TMDBStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {
    enum Outcome {
        case success(Data, Int)
        case failure(any Error)
    }

    private let lock = NSLock()
    private let outcomes: [Outcome]
    private var requests: [URLRequest] = []

    /// One outcome per expected call, in order; the last repeats.
    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }
    convenience init(_ outcome: Outcome) { self.init([outcome]) }

    var callCount: Int { lock.withLock { requests.count } }
    var calls: [URLRequest] { lock.withLock { requests } }
    var lastRequest: URLRequest? { lock.withLock { requests.last } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let outcome: Outcome = lock.withLock {
            let index = min(requests.count, outcomes.count - 1)
            requests.append(request)
            return outcomes[index]
        }
        switch outcome {
        case .failure(let error):
            throw error
        case .success(let data, let code):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.themoviedb.org")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }
    }
}

final class TMDBLookupServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// A v3 API key: 32 hex characters, no dots.
    private let v3Key = "0123456789abcdef0123456789abcdef"
    /// A v4 read access token: a JWT — three dot-separated segments.
    private let v4Token = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ0ZXN0In0.c2lnbmF0dXJl"

    private let movieSearchJSON = Data("""
    {"page":1,"results":[
      {"id":550,"title":"Fight Club","original_title":"Fight Club",
       "overview":"A ticking-time-bomb insomniac.","poster_path":"/poster.jpg",
       "backdrop_path":"/backdrop.jpg","release_date":"1999-10-15","vote_average":8.4},
      {"id":551,"title":"Another Film","release_date":"2003-01-02","vote_average":6.1},
      {"id":552,"release_date":"2010-01-01"}
    ],"total_results":3}
    """.utf8)

    private let tvSearchJSON = Data("""
    {"page":1,"results":[
      {"id":1399,"name":"Game of Thrones","original_name":"Game of Thrones",
       "first_air_date":"2011-04-17","vote_average":8.4}
    ]}
    """.utf8)

    private func detailsJSON(id: Int, runtime: Int?) -> Data {
        let runtimeField = runtime.map { "\($0)" } ?? "null"
        return Data("""
        {"id":\(id),"title":"Fight Club","original_title":"Fight Club",
         "overview":"Prose.","release_date":"1999-10-15","vote_average":8.4,
         "runtime":\(runtimeField),"genres":[{"name":"Drama"},{"name":"Thriller"}]}
        """.utf8)
    }

    // MARK: - Credential detection (pure)

    func test_usesBearerToken_tellsTheTwoCredentialFormsApart() {
        XCTAssertTrue(TMDBLookupService.usesBearerToken(v4Token), "a JWT is a v4 read access token")
        XCTAssertFalse(TMDBLookupService.usesBearerToken(v3Key), "32 hex characters is a v3 API key")
        XCTAssertFalse(TMDBLookupService.usesBearerToken(""))
        XCTAssertFalse(TMDBLookupService.usesBearerToken("eyJonly.two"), "a JWT has three segments")
        XCTAssertTrue(TMDBLookupService.usesBearerToken("  \(v4Token)  "), "padding must not change the verdict")
    }

    // MARK: - The key must travel in the right place

    func test_v4Token_goesInTheHeaderAndNeverInTheURL() throws {
        let request = try XCTUnwrap(TMDBLookupService.buildRequest(
            path: "/search/movie",
            queryItems: [URLQueryItem(name: "query", value: "Fight Club")],
            apiKey: v4Token
        ))

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(v4Token)")
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertFalse(url.contains(v4Token), "a token in the URL ends up in logs and proxies")
        XCTAssertFalse(url.contains("api_key"))
    }

    func test_v3Key_goesInTheQueryBecauseThatIsAllV3Accepts() throws {
        let request = try XCTUnwrap(TMDBLookupService.buildRequest(
            path: "/search/movie",
            queryItems: [URLQueryItem(name: "query", value: "Fight Club")],
            apiKey: v3Key
        ))

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains("api_key=\(v3Key)"))
    }

    func test_buildRequest_percentEncodesAwkwardTitles() throws {
        let request = try XCTUnwrap(TMDBLookupService.buildRequest(
            path: "/search/movie",
            queryItems: [URLQueryItem(name: "query", value: "Tom & Jerry: O'Hara's Day")],
            apiKey: v3Key
        ))
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertFalse(url.contains("Tom & Jerry"), "a raw ampersand would truncate the query")
        XCTAssertTrue(url.contains("Tom%20%26%20Jerry") || url.contains("Tom+%26+Jerry"))
    }

    // MARK: - Searching

    func test_searchMovies_parsesResultsAndDropsUntitledRows() async throws {
        let client = TMDBStubHTTPClient(.success(movieSearchJSON, 200))
        let service = TMDBLookupService(apiKey: v3Key, httpClient: client)

        let results = try await service.searchMovies(title: "Fight Club", year: 1999)

        XCTAssertEqual(results.count, 2, "the row with no title is not something a user could choose")
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.source, .tmdb)
        XCTAssertEqual(first.externalId, "550")
        XCTAssertEqual(first.title, "Fight Club")
        XCTAssertEqual(first.year, 1999)
        XCTAssertEqual(first.score, 8.4)
        XCTAssertEqual(first.releaseDate, "1999-10-15")
        XCTAssertNotNil(first.posterURL)
        XCTAssertNil(first.runtimeMinutes, "search results carry no running time — by design, and documented")
    }

    func test_searchMovies_sendsTheYearFilter() async throws {
        let client = TMDBStubHTTPClient(.success(movieSearchJSON, 200))
        let service = TMDBLookupService(apiKey: v3Key, httpClient: client)

        _ = try await service.searchMovies(title: "Fight Club", year: 1999)

        let url = try XCTUnwrap(client.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.contains("year=1999"))
        XCTAssertTrue(url.contains("/search/movie"))
    }

    func test_searchTVShows_readsTheSeriesFieldNames() async throws {
        let client = TMDBStubHTTPClient(.success(tvSearchJSON, 200))
        let service = TMDBLookupService(apiKey: v3Key, httpClient: client)

        let results = try await service.searchTVShows(title: "Game of Thrones", year: 2011)

        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.title, "Game of Thrones", "series use `name`, not `title`")
        XCTAssertEqual(first.year, 2011, "series use `first_air_date`")
        let url = try XCTUnwrap(client.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.contains("first_air_date_year=2011"), "the year filter is spelled differently for series")
    }

    func test_searchMovies_emptyTitleNeverReachesTheNetwork() async {
        let client = TMDBStubHTTPClient(.success(movieSearchJSON, 200))
        let service = TMDBLookupService(apiKey: v3Key, httpClient: client)

        do {
            _ = try await service.searchMovies(title: "   ")
            XCTFail("an empty search should be refused locally")
        } catch let error as TMDBLookupError {
            XCTAssertEqual(error, .emptyQuery)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(client.callCount, 0, "a pointless request must not be sent")
    }

    func test_noAPIKey_isDistinctFromBeingRejected() async {
        let client = TMDBStubHTTPClient(.success(movieSearchJSON, 200))
        let service = TMDBLookupService(apiKey: "  ", httpClient: client)

        do {
            _ = try await service.searchMovies(title: "Fight Club")
            XCTFail("expected a missing-key error")
        } catch let error as TMDBLookupError {
            XCTAssertEqual(error, .missingAPIKey, "'no key set' and 'key rejected' need different advice")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(client.callCount, 0)
    }

    // MARK: - Running time comes only from the details endpoint

    func test_movieDetails_carriesTheRunningTimeAndGenres() async throws {
        let client = TMDBStubHTTPClient(.success(detailsJSON(id: 550, runtime: 139), 200))
        let service = TMDBLookupService(apiKey: v3Key, httpClient: client)

        let result = try await service.movieDetails(id: 550)

        XCTAssertEqual(result.runtimeMinutes, 139)
        XCTAssertEqual(result.genres, ["Drama", "Thriller"])
        XCTAssertEqual(result.externalId, "550")
    }

    func test_movieDetails_treatsAZeroRuntimeAsUnknown() async throws {
        // TMDB reports 0 for "we don't know", which would otherwise read as a
        // zero-length film and score terribly against a real disc.
        let client = TMDBStubHTTPClient(.success(detailsJSON(id: 550, runtime: 0), 200))
        let service = TMDBLookupService(apiKey: v3Key, httpClient: client)

        let result = try await service.movieDetails(id: 550)

        XCTAssertNil(result.runtimeMinutes, "0 minutes is missing data, not a fact about the film")
    }

    func test_withRuntimes_fillsThemInUpToTheCap() async throws {
        let client = TMDBStubHTTPClient([
            .success(movieSearchJSON, 200),
            .success(detailsJSON(id: 550, runtime: 139), 200),
        ])
        let service = TMDBLookupService(apiKey: v3Key, httpClient: client)

        let results = try await service.searchMovies(title: "Fight Club")
        let enriched = try await service.withRuntimes(results, limit: 1)

        XCTAssertEqual(enriched.count, results.count, "nothing may be dropped")
        XCTAssertEqual(enriched.first?.runtimeMinutes, 139)
        XCTAssertNil(enriched.last?.runtimeMinutes, "beyond the cap, results come back unchanged")
        XCTAssertEqual(client.callCount, 2, "one search plus one detail fetch")
    }

    func test_withRuntimes_oneFailedDetailDoesNotAbandonTheSearch() async throws {
        let client = TMDBStubHTTPClient([
            .success(movieSearchJSON, 200),
            .success(Data(), 500),
        ])
        let service = TMDBLookupService(apiKey: v3Key, httpClient: client)

        let results = try await service.searchMovies(title: "Fight Club")
        let enriched = try await service.withRuntimes(results, limit: 1)

        XCTAssertEqual(enriched.count, results.count)
        XCTAssertNil(enriched.first?.runtimeMinutes)
        XCTAssertEqual(enriched.first?.title, "Fight Club", "losing a running time must not lose the result")
    }

    // MARK: - Status mapping

    func test_statusCodesMapToActionableErrors() async throws {
        let cases: [(Int, TMDBLookupError)] = [
            (401, .unauthorized),
            (404, .notFound),
            (429, .rateLimited),
        ]
        for (code, expected) in cases {
            let client = TMDBStubHTTPClient(.success(Data(), code))
            let service = TMDBLookupService(apiKey: v3Key, httpClient: client)
            do {
                _ = try await service.searchMovies(title: "Fight Club")
                XCTFail("HTTP \(code) should throw")
            } catch let error as TMDBLookupError {
                XCTAssertEqual(error, expected)
            } catch {
                XCTFail("unexpected error for HTTP \(code): \(error)")
            }
        }
    }

    func test_cancellationPropagates() async {
        let client = TMDBStubHTTPClient(.failure(CancellationError()))
        let service = TMDBLookupService(apiKey: v3Key, httpClient: client)

        do {
            _ = try await service.searchMovies(title: "Fight Club")
            XCTFail("cancellation must propagate")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // MARK: - The key must not appear in ANY error the user could see

    func test_theAPIKeyNeverAppearsInAnErrorMessage() async {
        // Swept rather than spot-checked: a future error case that forgot to
        // redact would slip past a test that only looked at the ones we
        // remembered. A v3 key travels in the URL, so this is the real risk.
        let bodyEchoingTheKey = Data(#"{"status_message":"Invalid key: 0123456789abcdef0123456789abcdef"}"#.utf8)
        let outcomes: [TMDBStubHTTPClient.Outcome] = [
            .success(bodyEchoingTheKey, 500),
            .success(Data(), 401),
            .success(Data(), 429),
            .success(Data("not json".utf8), 200),
            .failure(URLError(.notConnectedToInternet)),
        ]

        for outcome in outcomes {
            let client = TMDBStubHTTPClient(outcome)
            let service = TMDBLookupService(apiKey: v3Key, httpClient: client)
            do {
                _ = try await service.searchMovies(title: "Fight Club")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                XCTAssertFalse(
                    message.contains(v3Key),
                    "the API key leaked into an error message: \(message)"
                )
            }
        }
    }
}
