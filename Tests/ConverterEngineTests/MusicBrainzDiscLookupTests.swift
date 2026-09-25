// ============================================================================
// MeedyaConverter — MusicBrainzDiscLookupTests (Issue #502, slice 2)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Coverage for the keyless Audio CD identification path: building the MusicBrainz
// TOC string (with the +150 pre-gap), the lookup request, parsing the disc/TOC
// response, and the service's status→error mapping — all against a mock
// `MetadataHTTPClient` (no network in CI). Everything under test is `public`;
// no `@testable import`.
//
// F6 (Codex round-1 review): the request must name the disc's real Disc ID and
// `cdstubs=no`, never `/discid/-`, and the parser must tell an EXACT MusicBrainz
// hit apart from a FUZZY best guess — fail safe, so an unrecognised shape reads
// as fuzzy rather than exact. The fixtures below are trimmed from the two real
// response shapes MusicBrainz documents, cross-checked live against its own
// Nevermind example on 2026-09-24:
//   * EXACT — top-level `id, offset-count, offsets, sectors, releases`.
//   * FUZZY — top-level `release-count, release-offset, releases` — no `id`,
//     no `offsets` at all.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// A tiny stubbed HTTP client — uniquely named so it never collides with the
// mock in MusicBrainzLookupServiceTests within the same test module.
private final class DiscLookupStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {
    enum Outcome {
        case success(Data, Int)
        case failure(Error)
    }
    private let outcome: Outcome
    init(_ outcome: Outcome) { self.outcome = outcome }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch outcome {
        case .failure(let error):
            throw error
        case .success(let data, let code):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://musicbrainz.org")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }
    }
}

final class MusicBrainzDiscLookupTests: XCTestCase {

    // A throttle that never sleeps, so the async tests stay fast.
    private func immediateService(_ outcome: DiscLookupStubHTTPClient.Outcome) -> MusicBrainzDiscLookupService {
        MusicBrainzDiscLookupService(
            httpClient: DiscLookupStubHTTPClient(outcome),
            throttle: MusicBrainzRequestThrottle(minimumInterval: .zero)
        )
    }

    private func toc(tracks: [DiscTrack], leadOut: Int) -> DiscTableOfContents {
        DiscTableOfContents(tracks: tracks, leadOutSector: leadOut)
    }

    // MARK: - TOC string

    func test_tocString_appliesPregapAndExcludesDataTrack() {
        let t = toc(
            tracks: [
                DiscTrack(number: 1, startSector: 0),
                DiscTrack(number: 2, startSector: 20000),
                DiscTrack(number: 3, startSector: 100000, isData: true), // Enhanced-CD data track: excluded
            ],
            leadOut: 250000
        )
        // first=1, last=2, offsets +150 = 150, 20150.
        //
        // The lead-out is measured to the end of the MUSIC session, not the physical
        // end of the disc: this is an Enhanced CD, so the music session ends where
        // the data track starts, less the standard 11,400-sector session gap —
        // 100000 - 11400 = 88600, +150 = 88750. That is what MusicBrainz matches on,
        // and it must agree with MusicBrainzDiscID.compute(for:).
        XCTAssertEqual(MusicBrainzDiscLookupService.musicBrainzTOCString(for: t), "1+2+88750+150+20150")
    }

    func test_tocString_nilWhenNoAudioTracks() {
        let t = toc(tracks: [DiscTrack(number: 1, startSector: 0, isData: true)], leadOut: 1000)
        XCTAssertNil(MusicBrainzDiscLookupService.musicBrainzTOCString(for: t))
    }

    // MARK: - Request

    /// The heart of F6: the request must name the disc's REAL Disc ID, must
    /// carry `cdstubs=no`, and must NEVER fall back to the old `/discid/-`
    /// fuzzy-only form — that form is what silently threw the computed Disc ID
    /// away and is exactly the bug this fixes.
    func test_buildLookupRequest_usesTheRealDiscIdAndCdstubsNo_neverTheDashForm() throws {
        let request = try XCTUnwrap(
            MusicBrainzDiscLookupService.buildLookupRequest(
                discID: "gxp6QVA8pvq._RJLsqjz8ptjZXk-",
                tocString: "1+2+250150+150+20150"
            )
        )
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains("/discid/gxp6QVA8pvq._RJLsqjz8ptjZXk-?toc=1+2+250150+150+20150"),
                      "got: \(url)")
        XCTAssertTrue(url.contains("cdstubs=no"), "a CD stub must not be allowed to block the fuzzy fallback")
        XCTAssertFalse(url.contains("/discid/-"), "this is the exact bug F6 fixes: '-' tells MusicBrainz to ignore the id")
        XCTAssertTrue(url.contains("inc=artist-credits"))
        XCTAssertTrue(url.contains("fmt=json"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), MusicBrainzClient.userAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_buildLookupRequest_emptyDiscIdIsRefused() {
        XCTAssertNil(MusicBrainzDiscLookupService.buildLookupRequest(discID: "", tocString: "1+2+250150+150+20150"))
    }

    // MARK: - Parse

    /// The id this app is pretending to have asked MusicBrainz about, shared
    /// by every fixture below — `parseDiscLookup` must compare the body's own
    /// `id` against exactly this value.
    private let requestedDiscID = "gxp6QVA8pvq._RJLsqjz8ptjZXk-"

    /// EXACT shape, trimmed from MusicBrainz's own documented response for a
    /// disc it holds (cross-checked live against its Nevermind example,
    /// 2026-09-24): top-level `id, offset-count, offsets, sectors, releases`.
    private var exactReleasesJSON: Data {
        Data("""
        {"id":"\(requestedDiscID)","offset-count":2,"offsets":[150,20150],"sectors":20300,"releases":[
          {"id":"rel-1","title":"Greatest Hits","date":"1994-08-15","country":"GB",
           "artist-credit":[{"name":"Queen","joinphrase":""}],
           "media":[{"track-count":17}]},
          {"id":"rel-2","title":"Platinum Collection","date":"2000",
           "artist-credit":[{"name":"Queen","joinphrase":" & ","artist":{"id":"mbid-x"}},{"name":"Friends","joinphrase":""}],
           "media":[{"track-count":17},{"track-count":16}]}
        ]}
        """.utf8)
    }

    /// FUZZY shape, trimmed the same way: top-level `release-count,
    /// release-offset, releases` — no top-level `id` or `offsets` at all. Same
    /// releases as the exact fixture, so a test can prove parsing behaves
    /// identically for the releases themselves and differs only in `matchKind`.
    private let fuzzyReleasesJSON = Data("""
    {"release-count":2,"release-offset":0,"releases":[
      {"id":"rel-1","title":"Greatest Hits","date":"1994-08-15","country":"GB",
       "artist-credit":[{"name":"Queen","joinphrase":""}],
       "media":[{"track-count":17}]},
      {"id":"rel-2","title":"Platinum Collection","date":"2000",
       "artist-credit":[{"name":"Queen","joinphrase":" & ","artist":{"id":"mbid-x"}},{"name":"Friends","joinphrase":""}],
       "media":[{"track-count":17},{"track-count":16}]}
    ]}
    """.utf8)

    func test_parse_exactShape_isExactAndMapsReleases() throws {
        let result = try MusicBrainzDiscLookupService.parseDiscLookup(exactReleasesJSON, requestedDiscID: requestedDiscID)
        XCTAssertEqual(result.matchKind, .exact)
        XCTAssertEqual(result.matches.count, 2)

        let first = result.matches[0]
        XCTAssertEqual(first.id, "rel-1")
        XCTAssertEqual(first.title, "Greatest Hits")
        XCTAssertEqual(first.artist, "Queen")
        XCTAssertEqual(first.date, "1994-08-15")
        XCTAssertEqual(first.year, 1994)
        XCTAssertEqual(first.trackCount, 17)
        XCTAssertEqual(first.mediumCount, 1)

        let second = result.matches[1]
        XCTAssertEqual(second.artist, "Queen & Friends") // join phrase " & " preserved
        XCTAssertEqual(second.trackCount, 33)             // 17 + 16 across two media
        XCTAssertEqual(second.mediumCount, 2)
        XCTAssertEqual(second.year, 2000)
    }

    func test_parse_fuzzyShape_isFuzzy() throws {
        let result = try MusicBrainzDiscLookupService.parseDiscLookup(fuzzyReleasesJSON, requestedDiscID: requestedDiscID)
        XCTAssertEqual(result.matchKind, .fuzzy)
        XCTAssertEqual(result.matches.count, 2, "a fuzzy answer still carries its best guesses")
    }

    /// Fail safe: a shape this app has never seen — including, deliberately,
    /// the OLD bare `{"releases":[...]}` shape this file used to assume was
    /// the only one — must never be read as exact.
    func test_parse_unrecognisedShape_isFuzzy() throws {
        let body = Data(#"{"releases":[{"id":"rel-1","title":"Mystery Album"}]}"#.utf8)
        let result = try MusicBrainzDiscLookupService.parseDiscLookup(body, requestedDiscID: requestedDiscID)
        XCTAssertEqual(result.matchKind, .fuzzy)
        XCTAssertEqual(result.matches.map(\.title), ["Mystery Album"])
    }

    /// MusicBrainz can fall back to a fuzzy answer WITHOUT changing the URL,
    /// so an "exact-shaped" body naming a DIFFERENT disc must not be trusted
    /// just because the shape looks right — only checking the shape, and not
    /// the id, was exactly the kind of mistake this fix exists to close off.
    func test_parse_exactShapeWithADifferentId_isFuzzy() throws {
        let body = Data("""
        {"id":"some-other-disc-entirely","offset-count":1,"offsets":[150],"sectors":1000,
         "releases":[{"id":"rel-9","title":"Wrong Disc"}]}
        """.utf8)
        let result = try MusicBrainzDiscLookupService.parseDiscLookup(body, requestedDiscID: requestedDiscID)
        XCTAssertEqual(result.matchKind, .fuzzy)
    }

    func test_parse_emptyReleases_isNoMatch() throws {
        let body = Data(#"{"release-count":0,"release-offset":0,"releases":[]}"#.utf8)
        let result = try MusicBrainzDiscLookupService.parseDiscLookup(body, requestedDiscID: requestedDiscID)
        XCTAssertTrue(result.matches.isEmpty)
    }

    func test_parse_malformedThrows() {
        XCTAssertThrowsError(
            try MusicBrainzDiscLookupService.parseDiscLookup(Data("not json".utf8), requestedDiscID: requestedDiscID)
        ) { error in
            guard case MusicBrainzLookupError.malformedResponse = error else {
                return XCTFail("expected .malformedResponse, got \(error)")
            }
        }
    }

    func test_metadataResult_bridge() throws {
        let result = try MusicBrainzDiscLookupService.parseDiscLookup(exactReleasesJSON, requestedDiscID: requestedDiscID)
        let bridge = result.matches[0].metadataResult
        XCTAssertEqual(bridge.source, .musicBrainz)
        XCTAssertEqual(bridge.externalId, "rel-1")
        XCTAssertEqual(bridge.title, "Greatest Hits")
        XCTAssertEqual(bridge.album, "Greatest Hits")
        XCTAssertEqual(bridge.year, 1994)
    }

    // MARK: - Service status mapping

    func test_lookup_success() async throws {
        let service = immediateService(.success(exactReleasesJSON, 200))
        let result = try await service.lookup(discID: requestedDiscID, tocString: "1+2+250150+150+20150")
        XCTAssertEqual(result.matchKind, .exact)
        XCTAssertEqual(result.matches.map(\.id), ["rel-1", "rel-2"])
    }

    func test_lookup_fuzzyBody_isFuzzy() async throws {
        let service = immediateService(.success(fuzzyReleasesJSON, 200))
        let result = try await service.lookup(discID: requestedDiscID, tocString: "1+2+250150+150+20150")
        XCTAssertEqual(result.matchKind, .fuzzy)
        XCTAssertEqual(result.matches.count, 2)
    }

    func test_lookup_404IsEmptyNotError() async throws {
        let service = immediateService(.success(Data("{}".utf8), 404))
        let result = try await service.lookup(discID: requestedDiscID, tocString: "1+1+1000+150")
        XCTAssertTrue(result.matches.isEmpty)
    }

    func test_lookup_503RateLimited() async {
        let service = immediateService(.success(Data("{\"error\":\"slow down\"}".utf8), 503))
        do {
            _ = try await service.lookup(discID: requestedDiscID, tocString: "1+1+1000+150")
            XCTFail("expected an error")
        } catch let error as MusicBrainzLookupError {
            guard case .rateLimited = error else { return XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_lookup_transportError() async {
        let service = immediateService(.failure(URLError(.timedOut)))
        do {
            _ = try await service.lookup(discID: requestedDiscID, tocString: "1+1+1000+150")
            XCTFail("expected an error")
        } catch let error as MusicBrainzLookupError {
            guard case .transport = error else { return XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_lookup_cancellationRethrows() async {
        let service = immediateService(.failure(CancellationError()))
        do {
            _ = try await service.lookup(discID: requestedDiscID, tocString: "1+1+1000+150")
            XCTFail("expected an error")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func test_lookupDisc_emptyTOCThrows() async {
        let service = immediateService(.success(Data("{}".utf8), 200))
        let dataOnly = toc(tracks: [DiscTrack(number: 1, startSector: 0, isData: true)], leadOut: 1000)
        do {
            _ = try await service.lookup(disc: dataOnly, discID: requestedDiscID)
            XCTFail("expected .emptyQuery")
        } catch let error as MusicBrainzLookupError {
            guard case .emptyQuery = error else { return XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
