// ============================================================================
// MeedyaConverter — MusicBrainzLookupServiceTests (Issue #205, follows #493)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Coverage for the #205 slice: MusicBrainz recording search actually
// executes (native Swift, keyless) and feeds auto-tagging.
//
// Layers:
//   1. Pure JSON decode (`MusicBrainzLookupService.parseRecordingSearch`)
//      against real-shaped MusicBrainz `/recording` search bodies.
//   2. `MusicBrainzRecordingMatch.bestRelease`/`.metadataResult` — pure
//      mapping, no I/O.
//   3. `MusicBrainzLookupService.searchRecordings` sequencing/error-mapping
//      against a `MusicBrainzMockHTTPClient` (a mock `MetadataHTTPClient`
//      conformer) — no real network I/O.
//   4. `MusicBrainzRequestThrottle` timing.
//   5. `MusicBrainzTagMapping` (seed/rank/apply) — pure, no I/O.
//
// No `@testable import`: every symbol under test is `public`.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// MARK: - MusicBrainzMockHTTPClient

/// A `MetadataHTTPClient` conformer backed by a FIFO queue of canned
/// responses, so `MusicBrainzLookupService` can be exercised without any
/// real network I/O. Records every request (and its start time, for the
/// throttle tests) under a lock.
final class MusicBrainzMockHTTPClient: MetadataHTTPClient, @unchecked Sendable {
    /// Thrown by `data(for:)` when no responder was enqueued for a call.
    struct Underscripted: Error {}

    private let lock = NSLock()
    private var responders: [(URLRequest) throws -> (Data, HTTPURLResponse)] = []
    private var _requests: [URLRequest] = []
    private var _requestStartTimes: [ContinuousClock.Instant] = []
    private var _delay: Duration = .zero

    /// Every request `data(for:)` was called with, in call order.
    var requests: [URLRequest] { lock.withLock { _requests } }

    /// `ContinuousClock.now` recorded at the start of each `data(for:)` call.
    var requestStartTimes: [ContinuousClock.Instant] { lock.withLock { _requestStartTimes } }

    /// Artificial delay applied before popping the next responder. Lets the
    /// cancellation test observe an in-flight request.
    var delay: Duration {
        get { lock.withLock { _delay } }
        set { lock.withLock { _delay = newValue } }
    }

    /// Enqueue a canned HTTP response.
    func enqueue(status: Int, body: String, contentType: String = "application/json") {
        let data = Data(body.utf8)
        lock.withLock {
            responders.append { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": contentType]
                )!
                return (data, response)
            }
        }
    }

    /// Enqueue a transport-level failure (e.g. a `URLError`).
    func enqueueFailure(_ error: Error) {
        lock.withLock {
            responders.append { _ in throw error }
        }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            _requests.append(request)
            _requestStartTimes.append(.now)
        }
        let effectiveDelay = delay
        if effectiveDelay > .zero {
            try await Task.sleep(for: effectiveDelay)
        }
        let responder: (URLRequest) throws -> (Data, HTTPURLResponse) = try lock.withLock {
            guard !responders.isEmpty else { throw Underscripted() }
            return responders.removeFirst()
        }
        return try responder(request)
    }
}

// MARK: - MusicBrainzFixtures

/// Real-shaped MusicBrainz `/ws/2/recording?...&fmt=json` bodies and error
/// bodies, used across the decode and service tests below.
enum MusicBrainzFixtures {

    /// Two "Bohemian Rhapsody" / Queen recordings, both live performances
    /// (score 100). Shape mirrors the real MusicBrainz recording-search
    /// envelope: `artist-credit`, `releases[].release-group`,
    /// `releases[].media[].track[]`, with only the matching medium/track
    /// present per release, as MusicBrainz itself returns.
    static let recordingSearchBohemian = """
    {
        "created": "2026-09-01T00:00:00.000Z",
        "count": 2,
        "offset": 0,
        "recordings": [
            {
                "id": "46fe768c-7b38-4147-9f02-815b9f0759e2",
                "score": 100,
                "title": "Bohemian Rhapsody",
                "length": 354000,
                "video": null,
                "artist-credit": [
                    {
                        "name": "Queen",
                        "artist": {
                            "id": "0383dadf-2a4e-4d10-a46a-e9e041da8eb3",
                            "name": "Queen",
                            "sort-name": "Queen"
                        }
                    }
                ],
                "first-release-date": "1992",
                "releases": [
                    {
                        "id": "11111111-0000-4000-8000-000000000001",
                        "title": "The Freddie Mercury Tribute Concert",
                        "date": "1992",
                        "country": "GB",
                        "release-group": {
                            "id": "22222222-0000-4000-8000-000000000002",
                            "title": "The Freddie Mercury Tribute Concert",
                            "primary-type": "Album",
                            "secondary-types": ["Live"]
                        },
                        "track-count": 20,
                        "media": [
                            {
                                "position": 1,
                                "format": "CD",
                                "track": [
                                    {
                                        "id": "33333333-0000-4000-8000-000000000003",
                                        "number": "5",
                                        "title": "Bohemian Rhapsody",
                                        "length": 354000
                                    }
                                ],
                                "track-count": 20
                            }
                        ]
                    }
                ]
            },
            {
                "id": "b1a9c0e9-d987-4042-ae91-78d6a3267d69",
                "score": 100,
                "title": "Bohemian Rhapsody",
                "length": 354000,
                "disambiguation": "live, bootleg",
                "video": null,
                "artist-credit": [
                    {
                        "name": "Queen",
                        "artist": {
                            "id": "0383dadf-2a4e-4d10-a46a-e9e041da8eb3",
                            "name": "Queen",
                            "sort-name": "Queen"
                        }
                    }
                ],
                "first-release-date": "1992",
                "releases": [
                    {
                        "id": "44444444-0000-4000-8000-000000000004",
                        "title": "Opera Omnia",
                        "status": "Bootleg",
                        "date": "1992",
                        "country": "IT",
                        "artist-credit": [
                            {
                                "name": "Queen",
                                "artist": {
                                    "id": "0383dadf-2a4e-4d10-a46a-e9e041da8eb3",
                                    "name": "Queen",
                                    "sort-name": "Queen"
                                }
                            }
                        ],
                        "release-group": {
                            "id": "22655e64-0000-4000-8000-000000000005",
                            "title": "Opera Omnia",
                            "primary-type": "Album",
                            "secondary-types": []
                        },
                        "track-count": 21,
                        "media": [
                            {
                                "position": 2,
                                "format": "CD",
                                "track": [
                                    {
                                        "id": "55555555-0000-4000-8000-000000000006",
                                        "number": "1",
                                        "title": "Bohemian Rhapsody",
                                        "length": 354000
                                    }
                                ],
                                "track-count": 21
                            }
                        ]
                    }
                ]
            }
        ]
    }
    """

    /// Synthetic, shape-conformant: a two-artist-credit recording ("Queen &
    /// David Bowie") with two releases — `Hot Space` (the studio album,
    /// Official/Album/no secondary types, medium format "Vinyl", non-numeric
    /// track number "B5") and `Greatest Hits II` (a compilation, no
    /// `artist-credit` at all, numeric track number "4").
    static let recordingSearchUnderPressure = """
    {
        "recordings": [
            {
                "id": "66666666-0000-4000-8000-000000000007",
                "score": 93,
                "title": "Under Pressure",
                "length": 248000,
                "artist-credit": [
                    {
                        "name": "Queen",
                        "joinphrase": " & ",
                        "artist": {
                            "id": "0383dadf-2a4e-4d10-a46a-e9e041da8eb3",
                            "name": "Queen"
                        }
                    },
                    {
                        "name": "David Bowie",
                        "artist": {
                            "id": "5441c29d-3602-4898-b1a1-b77fa23b8e50",
                            "name": "David Bowie"
                        }
                    }
                ],
                "first-release-date": "1981-10-26",
                "releases": [
                    {
                        "id": "77777777-0000-4000-8000-000000000008",
                        "title": "Hot Space",
                        "status": "Official",
                        "date": "1982-05-21",
                        "artist-credit": [
                            {
                                "name": "Queen",
                                "joinphrase": " & ",
                                "artist": {
                                    "id": "0383dadf-2a4e-4d10-a46a-e9e041da8eb3",
                                    "name": "Queen"
                                }
                            },
                            {
                                "name": "David Bowie",
                                "artist": {
                                    "id": "5441c29d-3602-4898-b1a1-b77fa23b8e50",
                                    "name": "David Bowie"
                                }
                            }
                        ],
                        "release-group": {
                            "id": "88888888-0000-4000-8000-000000000009",
                            "title": "Hot Space",
                            "primary-type": "Album",
                            "secondary-types": []
                        },
                        "track-count": 8,
                        "media": [
                            {
                                "position": 1,
                                "format": "Vinyl",
                                "track": [
                                    {
                                        "id": "9999999a-0000-4000-8000-00000000000a",
                                        "number": "B5",
                                        "title": "Under Pressure",
                                        "length": 248000
                                    }
                                ],
                                "track-count": 8
                            }
                        ]
                    },
                    {
                        "id": "aaaaaaab-1111-4000-8000-00000000000b",
                        "title": "Greatest Hits II",
                        "status": "Official",
                        "date": "1991-10-28",
                        "release-group": {
                            "id": "bbbbbbbc-1111-4000-8000-00000000000c",
                            "title": "Greatest Hits II",
                            "primary-type": "Album",
                            "secondary-types": ["Compilation"]
                        },
                        "track-count": 17,
                        "media": [
                            {
                                "position": 1,
                                "track": [
                                    {
                                        "id": "ccccccce-1111-4000-8000-00000000000e",
                                        "number": "4",
                                        "title": "Under Pressure",
                                        "length": 248000
                                    }
                                ],
                                "track-count": 17
                            }
                        ]
                    }
                ]
            }
        ]
    }
    """

    /// Two recordings with only the required `id` field present, plus one
    /// with a `score` and no `title` at all — that one must be dropped.
    static let recordingSearchMinimal =
        #"{"recordings":[{"id":"aaaaaaaa-0000-4000-8000-000000000001","title":"Solo"},{"id":"aaaaaaaa-0000-4000-8000-000000000002","score":50}]}"#

    /// One release on a multi-disc set: medium position 2, track number "3".
    static let recordingSearchMultiDisc = """
    {
        "recordings": [
            {
                "id": "77777777-1111-4000-8000-000000000007",
                "score": 90,
                "title": "Some Track",
                "artist-credit": [
                    {
                        "name": "Some Artist",
                        "artist": {
                            "id": "88888888-1111-4000-8000-000000000008",
                            "name": "Some Artist"
                        }
                    }
                ],
                "releases": [
                    {
                        "id": "99999999-1111-4000-8000-000000000009",
                        "title": "Some Double Album",
                        "status": "Official",
                        "date": "2001-01-01",
                        "release-group": {
                            "id": "aaaaaaaa-2222-4000-8000-000000000010",
                            "title": "Some Double Album",
                            "primary-type": "Album",
                            "secondary-types": []
                        },
                        "media": [
                            {
                                "position": 2,
                                "format": "CD",
                                "track": [
                                    {
                                        "id": "bbbbbbbb-2222-4000-8000-000000000011",
                                        "number": "3",
                                        "title": "Some Track",
                                        "length": 200000
                                    }
                                ],
                                "track-count": 12
                            }
                        ]
                    }
                ]
            }
        ]
    }
    """

    static let recordingSearchEmpty = #"{"created":"2026-09-01T00:00:00.000Z","count":0,"offset":0,"recordings":[]}"#

    /// Captured MusicBrainz HTTP 400 body (empty `query=`).
    static let errorBody400 =
        #"{"help":"For usage, please see: https://musicbrainz.org/development/mmd","error":"The given parameters do not match any available query type for the recording resource."}"#

    /// MusicBrainz HTTP 503 body — same `{error, help}` envelope as the 400.
    static let errorBody503 =
        #"{"error":"Your requests are exceeding the allowable rate limit. Please see https://musicbrainz.org/doc/XML_Web_Service/Rate_Limiting for more information.","help":"For usage, please see: https://musicbrainz.org/development/mmd"}"#

    static let notJSON = "<html><body>Service Unavailable</body></html>"
}

// MARK: - MusicBrainzLookupServiceTests

final class MusicBrainzLookupServiceTests: XCTestCase {

    // MARK: Helpers

    /// A service wired to `client` with a non-blocking throttle. Tests must
    /// never use `MusicBrainzRequestThrottle.shared` — a process-wide actor
    /// would serialise unrelated tests under `swift test --parallel`.
    private func makeService(client: MusicBrainzMockHTTPClient) -> MusicBrainzLookupService {
        MusicBrainzLookupService(httpClient: client, throttle: MusicBrainzRequestThrottle(minimumInterval: .zero))
    }

    private func tag(_ key: String, _ value: String) -> MediaTag {
        MediaTag(key: key, value: value)
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    // MARK: - parseRecordingSearch

    func test_parseRecordingSearch_decodesIDTitleScoreAndDisambiguation() throws {
        let matches = try MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchBohemian))
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].id, "46fe768c-7b38-4147-9f02-815b9f0759e2")
        XCTAssertEqual(matches[0].score, 100)
        XCTAssertNil(matches[0].disambiguation)
        XCTAssertEqual(matches[1].id, "b1a9c0e9-d987-4042-ae91-78d6a3267d69")
        XCTAssertEqual(matches[1].score, 100)
        XCTAssertEqual(matches[1].disambiguation, "live, bootleg")
    }

    func test_parseRecordingSearch_joinsArtistCreditsWithJoinPhrase() throws {
        let matches = try MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchUnderPressure))
        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(match.artist, "Queen & David Bowie")
        XCTAssertEqual(match.artistIDs.count, 2)
    }

    func test_parseRecordingSearch_extractsReleaseAlbumDateTrackAndMBIDs() throws {
        let matches = try MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchBohemian))
        let release = try XCTUnwrap(matches[1].releases.first)
        XCTAssertEqual(release.title, "Opera Omnia")
        XCTAssertEqual(release.status, "Bootleg")
        XCTAssertEqual(release.date, "1992")
        XCTAssertEqual(release.country, "IT")
        XCTAssertEqual(release.releaseGroupID, "22655e64-0000-4000-8000-000000000005")
        XCTAssertEqual(release.trackNumber, "1")
        XCTAssertEqual(release.mediumPosition, 2)
        XCTAssertEqual(release.mediumFormat, "CD")
        XCTAssertEqual(release.mediumTrackCount, 21)
        XCTAssertEqual(release.albumArtist, "Queen")
    }

    func test_parseRecordingSearch_nonNumericTrackNumberHasNilValue() throws {
        let matches = try MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchUnderPressure))
        let hotSpace = try XCTUnwrap(matches.first?.releases.first(where: { $0.title == "Hot Space" }))
        XCTAssertEqual(hotSpace.trackNumber, "B5")
        XCTAssertNil(hotSpace.trackNumberValue)
    }

    func test_parseRecordingSearch_missingOptionalFieldsDecodeAndTitlelessRecordingIsDropped() throws {
        let matches = try MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchMinimal))
        XCTAssertEqual(matches.count, 1)
        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(match.title, "Solo")
        XCTAssertEqual(match.artist, "")
        XCTAssertNil(match.lengthMilliseconds)
        XCTAssertEqual(match.releases, [])
        XCTAssertEqual(match.score, 0)
    }

    func test_parseRecordingSearch_emptyRecordingsReturnsEmpty() throws {
        let matches = try MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchEmpty))
        XCTAssertEqual(matches, [])
    }

    func test_parseRecordingSearch_notJSONThrowsMalformedResponse() {
        XCTAssertThrowsError(try MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.notJSON))) { error in
            guard let lookupError = error as? MusicBrainzLookupError, case .malformedResponse = lookupError else {
                XCTFail("Expected .malformedResponse, got \(error)")
                return
            }
        }
    }

    func test_parseRecordingSearch_preservesServerOrder() throws {
        let matches = try MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchBohemian))
        XCTAssertEqual(matches.map(\.id), [
            "46fe768c-7b38-4147-9f02-815b9f0759e2",
            "b1a9c0e9-d987-4042-ae91-78d6a3267d69",
        ])
    }

    func test_parseRecordingSearch_lengthSecondsFromMilliseconds() throws {
        let json = #"{"recordings":[{"id":"dddddddd-0000-4000-8000-000000000001","title":"Timed","length":130400}]}"#
        let matches = try MusicBrainzLookupService.parseRecordingSearch(data(json))
        XCTAssertEqual(try XCTUnwrap(matches.first?.lengthSeconds), 130.4, accuracy: 0.0001)
    }

    func test_parseRecordingSearch_sanitisesControlCharacters() throws {
        // Built from plain ASCII text: the JSON below spells out the
        // six-character JSON unicode escapes (backslash, u, four hex
        // digits) — a RAW control character is not legal inside a JSON
        // string (RFC 8259), so this is the only well-formed way to get
        // one into a decoded value. Once decoded, `title` contains the
        // real NUL and RLO (bidi override) codepoints, which
        // `sanitizeSingleLine` must then strip.
        let backslash = "\\"
        let json = "{\"recordings\":[{\"id\":\"eeeeeeee-0000-4000-8000-000000000001\","
            + "\"title\":\"Bad" + backslash + "u0000Title" + backslash + "u202eHere\"}]}"
        let matches = try MusicBrainzLookupService.parseRecordingSearch(data(json))
        let title = try XCTUnwrap(matches.first).title
        XCTAssertFalse(title.unicodeScalars.contains { $0.value == 0 })
        XCTAssertFalse(title.unicodeScalars.contains { $0.value == 0x202E })
        XCTAssertTrue(title.contains("Bad"))
        XCTAssertTrue(title.contains("Title"))
        XCTAssertTrue(title.contains("Here"))
    }

    // MARK: - bestRelease

    func test_bestRelease_prefersAlbumTitleMatchThenOfficialPlainAlbumThenFirst() throws {
        let underPressure = try XCTUnwrap(
            MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchUnderPressure)).first
        )
        XCTAssertEqual(underPressure.bestRelease(preferringAlbumTitled: "greatest hits ii")?.title, "Greatest Hits II")
        XCTAssertEqual(underPressure.bestRelease(preferringAlbumTitled: nil)?.title, "Hot Space")

        let bohemian = try MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchBohemian))
        XCTAssertEqual(bohemian[0].bestRelease(preferringAlbumTitled: nil)?.title, "The Freddie Mercury Tribute Concert")
    }

    // MARK: - metadataResult bridge

    func test_metadataResultBridge_mapsFieldsAndConfidence() throws {
        let underPressure = try XCTUnwrap(
            MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchUnderPressure)).first
        )
        let result = underPressure.metadataResult
        XCTAssertEqual(result.source, .musicBrainz)
        XCTAssertEqual(result.externalId, underPressure.id)
        XCTAssertEqual(result.year, 1982)
        XCTAssertEqual(result.album, "Hot Space")
        XCTAssertNil(result.trackNumber)
        XCTAssertEqual(result.confidence, 0.93, accuracy: 0.001)
    }

    // MARK: - buildRecordingSearchRequest

    func test_buildRecordingSearchRequest_setsHeadersTimeoutAndURL() throws {
        let request = try XCTUnwrap(MusicBrainzClient.buildRecordingSearchRequest(title: "Bohemian Rhapsody", artist: "Queen"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), MusicBrainzClient.userAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(request.url?.absoluteString, MusicBrainzClient.buildRecordingSearchURL(title: "Bohemian Rhapsody", artist: "Queen"))
    }

    // MARK: - searchRecordings

    func test_searchRecordings_sendsExactlyOneRequestWithBuiltURLAndHeaders() async throws {
        let client = MusicBrainzMockHTTPClient()
        client.enqueue(status: 200, body: MusicBrainzFixtures.recordingSearchBohemian)
        let service = makeService(client: client)

        _ = try await service.searchRecordings(title: "Bohemian Rhapsody", artist: "Queen")

        XCTAssertEqual(client.requests.count, 1)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.absoluteString, MusicBrainzClient.buildRecordingSearchURL(title: "Bohemian Rhapsody", artist: "Queen"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), MusicBrainzClient.userAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_searchRecordings_200ReturnsParsedMatches() async throws {
        let client = MusicBrainzMockHTTPClient()
        client.enqueue(status: 200, body: MusicBrainzFixtures.recordingSearchBohemian)
        let service = makeService(client: client)

        let matches = try await service.searchRecordings(title: "Bohemian Rhapsody", artist: "Queen")
        XCTAssertEqual(matches.count, 2)
    }

    func test_searchRecordings_503ThrowsRateLimitedWithServerMessage() async {
        let client = MusicBrainzMockHTTPClient()
        client.enqueue(status: 503, body: MusicBrainzFixtures.errorBody503)
        let service = makeService(client: client)

        do {
            _ = try await service.searchRecordings(title: "x", artist: nil)
            XCTFail("Expected .rateLimited")
        } catch let error as MusicBrainzLookupError {
            XCTAssertEqual(
                error,
                .rateLimited(serverMessage: "Your requests are exceeding the allowable rate limit. Please see https://musicbrainz.org/doc/XML_Web_Service/Rate_Limiting for more information.")
            )
        } catch {
            XCTFail("Expected MusicBrainzLookupError, got \(error)")
        }
    }

    func test_searchRecordings_400ThrowsBadRequestWithServerMessage() async {
        let client = MusicBrainzMockHTTPClient()
        client.enqueue(status: 400, body: MusicBrainzFixtures.errorBody400)
        let service = makeService(client: client)

        do {
            _ = try await service.searchRecordings(title: "x", artist: nil)
            XCTFail("Expected .badRequest")
        } catch let error as MusicBrainzLookupError {
            XCTAssertEqual(
                error,
                .badRequest(serverMessage: "The given parameters do not match any available query type for the recording resource.")
            )
        } catch {
            XCTFail("Expected MusicBrainzLookupError, got \(error)")
        }
    }

    func test_searchRecordings_otherStatusThrowsHTTPStatusWithSnippet() async {
        let client = MusicBrainzMockHTTPClient()
        client.enqueue(status: 500, body: MusicBrainzFixtures.notJSON)
        let service = makeService(client: client)

        do {
            _ = try await service.searchRecordings(title: "x", artist: nil)
            XCTFail("Expected .httpStatus")
        } catch let error as MusicBrainzLookupError {
            guard case .httpStatus(let statusCode, let bodySnippet) = error else {
                XCTFail("Expected .httpStatus, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 500)
            XCTAssertFalse(bodySnippet.isEmpty)
            XCTAssertFalse(bodySnippet.contains("\n"))
        } catch {
            XCTFail("Expected MusicBrainzLookupError, got \(error)")
        }
    }

    func test_searchRecordings_transportErrorThrowsTransport() async {
        let client = MusicBrainzMockHTTPClient()
        client.enqueueFailure(URLError(.notConnectedToInternet))
        let service = makeService(client: client)

        do {
            _ = try await service.searchRecordings(title: "x", artist: nil)
            XCTFail("Expected .transport")
        } catch let error as MusicBrainzLookupError {
            guard case .transport(let message) = error else {
                XCTFail("Expected .transport, got \(error)")
                return
            }
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Expected MusicBrainzLookupError, got \(error)")
        }
    }

    func test_searchRecordings_malformedBodyThrowsMalformedResponse() async {
        let client = MusicBrainzMockHTTPClient()
        client.enqueue(status: 200, body: MusicBrainzFixtures.notJSON)
        let service = makeService(client: client)

        do {
            _ = try await service.searchRecordings(title: "x", artist: nil)
            XCTFail("Expected .malformedResponse")
        } catch let error as MusicBrainzLookupError {
            guard case .malformedResponse = error else {
                XCTFail("Expected .malformedResponse, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected MusicBrainzLookupError, got \(error)")
        }
    }

    func test_searchRecordings_blankTitleThrowsEmptyQueryWithoutRequest() async {
        let client = MusicBrainzMockHTTPClient()
        let service = makeService(client: client)

        do {
            _ = try await service.searchRecordings(title: "   ", artist: nil)
            XCTFail("Expected .emptyQuery")
        } catch let error as MusicBrainzLookupError {
            XCTAssertEqual(error, .emptyQuery)
        } catch {
            XCTFail("Expected MusicBrainzLookupError, got \(error)")
        }
        XCTAssertTrue(client.requests.isEmpty)
    }

    func test_searchRecordings_trimsTitleAndDropsBlankArtistClause() async throws {
        let client = MusicBrainzMockHTTPClient()
        client.enqueue(status: 200, body: MusicBrainzFixtures.recordingSearchEmpty)
        let service = makeService(client: client)

        _ = try await service.searchRecordings(title: "  Bohemian Rhapsody ", artist: " ")

        let request = try XCTUnwrap(client.requests.first)
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertFalse(url.contains("artist%3A"))
        XCTAssertEqual(url, MusicBrainzClient.buildRecordingSearchURL(title: "Bohemian Rhapsody", artist: nil))
    }

    func test_searchRecordings_cancellationPropagatesAsCancellationError() async throws {
        let client = MusicBrainzMockHTTPClient()
        client.delay = .seconds(5)
        client.enqueue(status: 200, body: MusicBrainzFixtures.recordingSearchEmpty)
        let service = makeService(client: client)

        let task = Task {
            try await service.searchRecordings(title: "Bohemian Rhapsody", artist: nil)
        }

        let deadline = ContinuousClock.now + .seconds(2)
        while client.requests.isEmpty && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.requests.count, 1)

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - MusicBrainzRequestThrottle

    func test_throttle_spacesSequentialRequestsByMinimumInterval() async throws {
        let client = MusicBrainzMockHTTPClient()
        client.enqueue(status: 200, body: MusicBrainzFixtures.recordingSearchEmpty)
        client.enqueue(status: 200, body: MusicBrainzFixtures.recordingSearchEmpty)
        client.enqueue(status: 200, body: MusicBrainzFixtures.recordingSearchEmpty)
        let throttle = MusicBrainzRequestThrottle(minimumInterval: .milliseconds(150))
        let service = MusicBrainzLookupService(httpClient: client, throttle: throttle)

        _ = try await service.searchRecordings(title: "a", artist: nil)
        _ = try await service.searchRecordings(title: "b", artist: nil)
        _ = try await service.searchRecordings(title: "c", artist: nil)

        let times = client.requestStartTimes
        XCTAssertEqual(times.count, 3)
        XCTAssertGreaterThanOrEqual(times[0].duration(to: times[2]), .milliseconds(300))
    }

    func test_throttle_spacesConcurrentRequestsSharingOneThrottle() async throws {
        // Local, function-scoped recorder (never a top-level type, so it
        // needs no module-unique name): collects the instant each concurrent
        // caller was actually released, under a lock.
        final class InstantBox: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [ContinuousClock.Instant] = []
            func record(_ instant: ContinuousClock.Instant) {
                lock.withLock { values.append(instant) }
            }
            var recorded: [ContinuousClock.Instant] { lock.withLock { values } }
        }

        let throttle = MusicBrainzRequestThrottle(minimumInterval: .milliseconds(150))
        let box = InstantBox()

        @Sendable func waitAndRecord() async throws {
            try await throttle.waitForTurn()
            box.record(.now)
        }

        async let first: Void = waitAndRecord()
        async let second: Void = waitAndRecord()
        _ = try await (first, second)

        let times = box.recorded.sorted()
        XCTAssertEqual(times.count, 2)
        XCTAssertGreaterThanOrEqual(times[0].duration(to: times[1]), .milliseconds(150))
    }

    func test_throttle_zeroIntervalDoesNotDelay() async throws {
        let throttle = MusicBrainzRequestThrottle(minimumInterval: .zero)
        try await throttle.waitForTurn()
        try await throttle.waitForTurn()
    }

    // MARK: - MusicBrainzTagMapping.seedQuery

    func test_seedQuery_prefersExistingTagsCaseInsensitively() {
        let tags = [tag("TITLE", "Bohemian Rhapsody"), tag("ARTIST", "Queen"), tag("ALBUM", "A Night at the Opera")]
        let query = MusicBrainzTagMapping.seedQuery(tags: tags, filename: "Queen - Bohemian Rhapsody.flac")
        XCTAssertEqual(query.title, "Bohemian Rhapsody")
        XCTAssertEqual(query.artist, "Queen")
        XCTAssertEqual(query.album, "A Night at the Opera")
    }

    func test_seedQuery_fallsBackToFilenameParserMusicPattern() {
        let query = MusicBrainzTagMapping.seedQuery(tags: [], filename: "Queen - Bohemian Rhapsody.flac")
        XCTAssertEqual(query.title, "Bohemian Rhapsody")
        XCTAssertEqual(query.artist, "Queen")
    }

    func test_seedQuery_fallsBackToCleanedFilenameTitleWithoutArtist() {
        let query = MusicBrainzTagMapping.seedQuery(tags: [], filename: "bohemian_rhapsody.flac")
        XCTAssertEqual(query.title, "bohemian rhapsody")
        XCTAssertNil(query.artist)
    }

    // MARK: - MusicBrainzTagMapping.ranked

    func test_ranked_ordersByScoreThenClosenessToFileDuration() {
        let a = MusicBrainzRecordingMatch(
            id: "a", title: "A", score: 100, artistCredits: [],
            lengthMilliseconds: 130_400, disambiguation: nil, firstReleaseDate: nil, releases: []
        )
        let b = MusicBrainzRecordingMatch(
            id: "b", title: "B", score: 100, artistCredits: [],
            lengthMilliseconds: 338_300, disambiguation: nil, firstReleaseDate: nil, releases: []
        )
        let c = MusicBrainzRecordingMatch(
            id: "c", title: "C", score: 95, artistCredits: [],
            lengthMilliseconds: 354_000, disambiguation: nil, firstReleaseDate: nil, releases: []
        )
        let ranked = MusicBrainzTagMapping.ranked([a, b, c], fileDurationSeconds: 355)
        XCTAssertEqual(ranked.map(\.id), ["b", "a", "c"])
    }

    func test_ranked_isIdentityWithoutDuration() {
        let a = MusicBrainzRecordingMatch(
            id: "a", title: "A", score: 100, artistCredits: [],
            lengthMilliseconds: nil, disambiguation: nil, firstReleaseDate: nil, releases: []
        )
        let b = MusicBrainzRecordingMatch(
            id: "b", title: "B", score: 50, artistCredits: [],
            lengthMilliseconds: nil, disambiguation: nil, firstReleaseDate: nil, releases: []
        )
        XCTAssertEqual(MusicBrainzTagMapping.ranked([a, b], fileDurationSeconds: nil).map(\.id), ["a", "b"])
        XCTAssertEqual(MusicBrainzTagMapping.ranked([a, b], fileDurationSeconds: 0).map(\.id), ["a", "b"])
    }

    // MARK: - MusicBrainzTagMapping.applying

    private func underPressureMatch() throws -> MusicBrainzRecordingMatch {
        try XCTUnwrap(
            MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchUnderPressure)).first
        )
    }

    func test_applying_replacesExistingKeysInPlacePreservingSpellingAndID() throws {
        let match = try underPressureMatch()
        let release = match.bestRelease(preferringAlbumTitled: nil)
        let titleTag = tag("TITLE", "old title")
        let artistTag = tag("ARTIST", "old artist")
        let result = MusicBrainzTagMapping.applying(match, release: release, to: [titleTag, artistTag], includeIdentifiers: false)

        let updatedTitle = try XCTUnwrap(result.first { $0.id == titleTag.id })
        XCTAssertEqual(updatedTitle.key, "TITLE")
        XCTAssertEqual(updatedTitle.value, "Under Pressure")

        let updatedArtist = try XCTUnwrap(result.first { $0.id == artistTag.id })
        XCTAssertEqual(updatedArtist.key, "ARTIST")
        XCTAssertEqual(updatedArtist.value, "Queen & David Bowie")
    }

    func test_applying_appendsMissingCanonicalKeysInOrder() throws {
        let match = try underPressureMatch()
        let release = match.bestRelease(preferringAlbumTitled: nil)
        let result = MusicBrainzTagMapping.applying(match, release: release, to: [], includeIdentifiers: false)
        // Non-numeric "B5" track number means "track" is never applied/appended.
        XCTAssertEqual(result.map(\.key), ["title", "artist", "album", "album_artist", "date"])
    }

    func test_applying_matchesTracknumberAliasAndSkipsNonNumericTrack() throws {
        // Skips: Hot Space's track number "B5" is non-numeric.
        let underPressure = try underPressureMatch()
        let hotSpace = underPressure.bestRelease(preferringAlbumTitled: nil)
        let noTrackResult = MusicBrainzTagMapping.applying(underPressure, release: hotSpace, to: [tag("tracknumber", "9")], includeIdentifiers: false)
        let untouchedTrack = try XCTUnwrap(noTrackResult.first { $0.key == "tracknumber" })
        XCTAssertEqual(untouchedTrack.value, "9")

        // Matches alias: MultiDisc's numeric track "3" replaces an existing "tracknumber" tag.
        let multiDisc = try XCTUnwrap(
            MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchMultiDisc)).first
        )
        let multiDiscRelease = multiDisc.bestRelease(preferringAlbumTitled: nil)
        let trackTag = tag("tracknumber", "9")
        let result = MusicBrainzTagMapping.applying(multiDisc, release: multiDiscRelease, to: [trackTag], includeIdentifiers: false)
        let updated = try XCTUnwrap(result.first { $0.id == trackTag.id })
        XCTAssertEqual(updated.key, "tracknumber")
        XCTAssertEqual(updated.value, "3")
    }

    func test_applying_identifiersToggle() throws {
        let match = try underPressureMatch()
        let release = match.bestRelease(preferringAlbumTitled: nil)

        let withIdentifiers = MusicBrainzTagMapping.applying(match, release: release, to: [], includeIdentifiers: true)
        XCTAssertEqual(MusicBrainzTagMapping.value(forKey: "musicbrainz_trackid", in: withIdentifiers), match.id)
        XCTAssertEqual(MusicBrainzTagMapping.value(forKey: "musicbrainz_albumid", in: withIdentifiers), release?.id)
        XCTAssertEqual(MusicBrainzTagMapping.value(forKey: "musicbrainz_releasegroupid", in: withIdentifiers), release?.releaseGroupID)
        XCTAssertEqual(
            MusicBrainzTagMapping.value(forKey: "musicbrainz_artistid", in: withIdentifiers),
            match.artistIDs.joined(separator: "; ")
        )

        let withoutIdentifiers = MusicBrainzTagMapping.applying(match, release: release, to: [], includeIdentifiers: false)
        XCTAssertNil(MusicBrainzTagMapping.value(forKey: "musicbrainz_trackid", in: withoutIdentifiers))
        XCTAssertNil(MusicBrainzTagMapping.value(forKey: "musicbrainz_albumid", in: withoutIdentifiers))
        XCTAssertNil(MusicBrainzTagMapping.value(forKey: "musicbrainz_releasegroupid", in: withoutIdentifiers))
        XCTAssertNil(MusicBrainzTagMapping.value(forKey: "musicbrainz_artistid", in: withoutIdentifiers))
    }

    func test_applying_writesDiscOnlyForMediumPositionAboveOne() throws {
        let multiDisc = try XCTUnwrap(
            MusicBrainzLookupService.parseRecordingSearch(data(MusicBrainzFixtures.recordingSearchMultiDisc)).first
        )
        let multiDiscRelease = multiDisc.bestRelease(preferringAlbumTitled: nil)
        let multiDiscResult = MusicBrainzTagMapping.applying(multiDisc, release: multiDiscRelease, to: [], includeIdentifiers: false)
        XCTAssertEqual(MusicBrainzTagMapping.value(forKey: "disc", in: multiDiscResult), "2")

        let underPressure = try underPressureMatch()
        let hotSpace = underPressure.bestRelease(preferringAlbumTitled: nil)
        let hotSpaceResult = MusicBrainzTagMapping.applying(underPressure, release: hotSpace, to: [], includeIdentifiers: false)
        XCTAssertNil(MusicBrainzTagMapping.value(forKey: "disc", in: hotSpaceResult))
    }

    func test_applying_leavesUnrelatedTagsUntouched_thenBuildWriteArgumentsEmitsPairs() throws {
        let match = try underPressureMatch()
        let release = match.bestRelease(preferringAlbumTitled: nil)
        let commentTag = tag("comment", "Ripped from vinyl")
        let encoderTag = tag("encoder", "LAME 3.100")

        let result = MusicBrainzTagMapping.applying(match, release: release, to: [commentTag, encoderTag], includeIdentifiers: false)
        XCTAssertTrue(result.contains { $0.id == commentTag.id && $0.value == "Ripped from vinyl" })
        XCTAssertTrue(result.contains { $0.id == encoderTag.id && $0.value == "LAME 3.100" })

        let args = MetadataTagEditor.buildWriteArguments(tags: result, artworkPath: nil)
        XCTAssertTrue(args.contains("title=Under Pressure"))
        XCTAssertTrue(args.contains("artist=Queen & David Bowie"))
    }
}
