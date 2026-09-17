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
        // first=1, last=2, leadOut+150=250150, offsets +150 = 150, 20150.
        XCTAssertEqual(MusicBrainzDiscLookupService.musicBrainzTOCString(for: t), "1+2+250150+150+20150")
    }

    func test_tocString_nilWhenNoAudioTracks() {
        let t = toc(tracks: [DiscTrack(number: 1, startSector: 0, isData: true)], leadOut: 1000)
        XCTAssertNil(MusicBrainzDiscLookupService.musicBrainzTOCString(for: t))
    }

    // MARK: - Request

    func test_buildLookupRequest_urlAndHeaders() throws {
        let request = try XCTUnwrap(MusicBrainzDiscLookupService.buildLookupRequest(tocString: "1+2+250150+150+20150"))
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains("/discid/-?toc=1+2+250150+150+20150"))
        XCTAssertTrue(url.contains("inc=artist-credits"))
        XCTAssertTrue(url.contains("fmt=json"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), MusicBrainzClient.userAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    // MARK: - Parse

    private let cannedReleasesJSON = Data("""
    {"releases":[
      {"id":"rel-1","title":"Greatest Hits","date":"1994-08-15","country":"GB",
       "artist-credit":[{"name":"Queen","joinphrase":""}],
       "media":[{"track-count":17}]},
      {"id":"rel-2","title":"Platinum Collection","date":"2000",
       "artist-credit":[{"name":"Queen","joinphrase":" & ","artist":{"id":"mbid-x"}},{"name":"Friends","joinphrase":""}],
       "media":[{"track-count":17},{"track-count":16}]}
    ]}
    """.utf8)

    func test_parse_mapsReleases() throws {
        let matches = try MusicBrainzDiscLookupService.parseDiscLookup(cannedReleasesJSON)
        XCTAssertEqual(matches.count, 2)

        let first = matches[0]
        XCTAssertEqual(first.id, "rel-1")
        XCTAssertEqual(first.title, "Greatest Hits")
        XCTAssertEqual(first.artist, "Queen")
        XCTAssertEqual(first.date, "1994-08-15")
        XCTAssertEqual(first.year, 1994)
        XCTAssertEqual(first.trackCount, 17)
        XCTAssertEqual(first.mediumCount, 1)

        let second = matches[1]
        XCTAssertEqual(second.artist, "Queen & Friends") // join phrase " & " preserved
        XCTAssertEqual(second.trackCount, 33)             // 17 + 16 across two media
        XCTAssertEqual(second.mediumCount, 2)
        XCTAssertEqual(second.year, 2000)
    }

    func test_parse_malformedThrows() {
        XCTAssertThrowsError(try MusicBrainzDiscLookupService.parseDiscLookup(Data("not json".utf8))) { error in
            guard case MusicBrainzLookupError.malformedResponse = error else {
                return XCTFail("expected .malformedResponse, got \(error)")
            }
        }
    }

    func test_metadataResult_bridge() throws {
        let matches = try MusicBrainzDiscLookupService.parseDiscLookup(cannedReleasesJSON)
        let result = matches[0].metadataResult
        XCTAssertEqual(result.source, .musicBrainz)
        XCTAssertEqual(result.externalId, "rel-1")
        XCTAssertEqual(result.title, "Greatest Hits")
        XCTAssertEqual(result.album, "Greatest Hits")
        XCTAssertEqual(result.year, 1994)
    }

    // MARK: - Service status mapping

    func test_lookup_success() async throws {
        let service = immediateService(.success(cannedReleasesJSON, 200))
        let matches = try await service.lookup(tocString: "1+2+250150+150+20150")
        XCTAssertEqual(matches.map(\.id), ["rel-1", "rel-2"])
    }

    func test_lookup_404IsEmptyNotError() async throws {
        let service = immediateService(.success(Data("{}".utf8), 404))
        let matches = try await service.lookup(tocString: "1+1+1000+150")
        XCTAssertTrue(matches.isEmpty)
    }

    func test_lookup_503RateLimited() async {
        let service = immediateService(.success(Data("{\"error\":\"slow down\"}".utf8), 503))
        do {
            _ = try await service.lookup(tocString: "1+1+1000+150")
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
            _ = try await service.lookup(tocString: "1+1+1000+150")
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
            _ = try await service.lookup(tocString: "1+1+1000+150")
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
            _ = try await service.lookup(disc: dataOnly)
            XCTFail("expected .emptyQuery")
        } catch let error as MusicBrainzLookupError {
            guard case .emptyQuery = error else { return XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
