// ============================================================================
// MeedyaConverter — MusicDiscIdentificationTests (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Covers the identify-and-contribute run end to end against MOCK HTTP seams
// — no network, no disc, no MeedyaDB in CI. The emphasis is on the FAILURE
// POSTURE documented in MusicDiscIdentification.swift, because that is the
// part a reader is most likely to "tidy up" into something wrong:
//
//   * a MusicBrainz outage must NOT abandon the run or lose the disc IDs;
//   * MeedyaDB being off or unconfigured is NOT a failure;
//   * a data-only disc must cost ZERO network requests;
//   * cancellation must stay cancellation, never turn into `.failed`.
//
// Stubs carry per-instance NSLock-guarded state and every test builds its own,
// so this file is safe under `swift test --parallel`. The lookup service is
// always given a zero-interval throttle so nothing sleeps.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// Uniquely named so it never collides with the other stubs in this module.
private final class IdentifyStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {
    enum Outcome {
        case success(Data, Int)
        case failure(any Error)
    }

    private let lock = NSLock()
    private let outcome: Outcome
    private var requests: [URLRequest] = []

    init(_ outcome: Outcome) { self.outcome = outcome }

    var callCount: Int { lock.withLock { requests.count } }
    var lastBody: Data? { lock.withLock { requests.last?.httpBody } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests.append(request) }
        switch outcome {
        case .failure(let error):
            throw error
        case .success(let data, let code):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }
    }
}

final class MusicDiscIdentificationTests: XCTestCase {

    // MARK: - Fixtures

    /// A plain single-session audio CD: three tracks, no data, lead-out past
    /// the last track's start so the ID calculation has something valid.
    private func plainAudioCD() -> DiscTableOfContents {
        let tracks = [
            DiscTrack(number: 1, startSector: 0, sectorCount: 18_000, isData: false),
            DiscTrack(number: 2, startSector: 18_000, sectorCount: 21_000, isData: false),
            DiscTrack(number: 3, startSector: 39_000, sectorCount: 16_500, isData: false),
        ]
        return DiscTableOfContents(
            discType: "Audio CD",
            tracks: tracks,
            leadOutSector: 55_500,
            firstTrackNumber: 1,
            lastTrackNumber: 3
        )
    }

    /// An Enhanced CD (CD-Extra): the same music, then a data track parked a
    /// full session gap later. The whole-disc ID must differ from the
    /// music-only one, and the music lead-out must be DERIVED, not the
    /// physical lead-out.
    private func enhancedCD() -> DiscTableOfContents {
        var tracks = plainAudioCD().tracks
        let dataStart = 55_500 + MusicBrainzDiscID.sessionGapSectors
        tracks.append(
            DiscTrack(number: 4, startSector: dataStart, sectorCount: 30_000, isData: true, sessionNumber: 2)
        )
        return DiscTableOfContents(
            discType: "CD-Extra",
            tracks: tracks,
            leadOutSector: dataStart + 30_000,
            firstTrackNumber: 1,
            lastTrackNumber: 4
        )
    }

    /// A disc with nothing but data — no music to identify at all.
    private func dataOnlyDisc() -> DiscTableOfContents {
        DiscTableOfContents(
            discType: "CD-ROM",
            tracks: [DiscTrack(number: 1, startSector: 0, sectorCount: 300_000, isData: true)],
            leadOutSector: 300_000,
            firstTrackNumber: 1,
            lastTrackNumber: 1
        )
    }

    private let releasesJSON = Data("""
    {"releases":[
      {"id":"rel-1","title":"Greatest Hits","date":"1994-08-15","country":"GB",
       "artist-credit":[{"name":"Queen","joinphrase":""}],
       "media":[{"track-count":3}]}
    ]}
    """.utf8)

    private let emptyReleasesJSON = Data(#"{"releases":[]}"#.utf8)

    private let ingestJSON = Data("""
    {"discPublicId":"disc_abc123","matched":true,"releasePublicId":"rel_xyz789"}
    """.utf8)

    // MARK: - Builders

    private func lookup(_ outcome: IdentifyStubHTTPClient.Outcome) -> MusicBrainzDiscLookupService {
        MusicBrainzDiscLookupService(
            httpClient: IdentifyStubHTTPClient(outcome),
            throttle: MusicBrainzRequestThrottle(minimumInterval: .zero)
        )
    }

    private func publisher(
        _ client: IdentifyStubHTTPClient,
        enabled: Bool = true
    ) -> MeedyaDBPublisher {
        MeedyaDBPublisher(
            config: MeedyaDBPublisherConfig(
                baseURL: "https://db.example",
                apiKey: "mdk_live_test",
                enabled: enabled
            ),
            httpClient: client
        )
    }

    /// The JSON body that actually reached the stub, decoded.
    private func sentPayload(_ client: IdentifyStubHTTPClient) throws -> [String: Any] {
        let body = try XCTUnwrap(client.lastBody, "expected a request body")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    /// The same body as raw text, for "this string appears nowhere" checks.
    private func rawSentBody(_ client: IdentifyStubHTTPClient) throws -> String {
        let body = try XCTUnwrap(client.lastBody, "expected a request body")
        return try XCTUnwrap(String(data: body, encoding: .utf8))
    }

    // MARK: - Identity only (offline, pure)

    func test_identity_plainAudioCD_musicAndWholeDiscIDsAgree() {
        let identity = MusicDiscIdentifier.identity(for: plainAudioCD())

        XCTAssertNotNil(identity.musicDiscID)
        XCTAssertEqual(identity.musicDiscID, identity.wholeDiscID,
                       "an ordinary CD has no data session, so both IDs describe the same thing")
        XCTAssertFalse(identity.isEnhancedCD)
        XCTAssertEqual(identity.leadOutSource, .singleSession)
        XCTAssertEqual(identity.audioTrackCount, 3)
        XCTAssertNotNil(identity.tocFingerprint)
        XCTAssertTrue(identity.isUsable)
    }

    func test_identity_enhancedCD_separatesTheMusicFromTheWholeDisc() {
        let identity = MusicDiscIdentifier.identity(for: enhancedCD())

        XCTAssertNotNil(identity.musicDiscID)
        XCTAssertNotNil(identity.wholeDiscID)
        XCTAssertNotEqual(identity.musicDiscID, identity.wholeDiscID,
                          "the data session must change the whole-disc ID but not the music one")
        XCTAssertTrue(identity.isEnhancedCD)
        XCTAssertEqual(identity.leadOutSource, .derivedFromDataTrack)
        XCTAssertEqual(identity.audioTrackCount, 3, "the data track is not an audio track")
    }

    func test_identity_enhancedCD_musicIDMatchesThePlainCDWithTheSameMusic() {
        // The whole point of the music-only ID: the same three tracks must
        // give the same MusicBrainz ID whether or not a data session rides
        // along — otherwise an Enhanced CD could never match a plain one.
        let plain = MusicDiscIdentifier.identity(for: plainAudioCD())
        let enhanced = MusicDiscIdentifier.identity(for: enhancedCD())
        XCTAssertEqual(plain.musicDiscID, enhanced.musicDiscID)
    }

    func test_identity_dataOnlyDisc_hasNothingToIdentify() {
        let identity = MusicDiscIdentifier.identity(for: dataOnlyDisc())

        XCTAssertNil(identity.musicDiscID)
        XCTAssertEqual(identity.audioTrackCount, 0)
        XCTAssertFalse(identity.isUsable)
        XCTAssertFalse(identity.isEnhancedCD, "no music ID means we cannot claim it is an Enhanced CD")
    }

    func test_identity_prefersAnIDTheTOCAlreadyCarries() {
        var toc = plainAudioCD()
        toc.musicBrainzDiscId = "aStoredDiscID.From-TheDrive-"

        let identity = MusicDiscIdentifier.identity(for: toc)

        XCTAssertEqual(identity.musicDiscID, "aStoredDiscID.From-TheDrive-")
        XCTAssertFalse(identity.isEnhancedCD,
                       "a stored ID differing from the computed whole-disc ID must NOT look like a data session")
        XCTAssertEqual(identity.leadOutSource, .singleSession)
    }

    func test_identity_blankStoredIDFallsBackToComputing() {
        var toc = plainAudioCD()
        toc.musicBrainzDiscId = "   "

        let identity = MusicDiscIdentifier.identity(for: toc)

        XCTAssertEqual(identity.musicDiscID, MusicDiscIdentifier.identity(for: plainAudioCD()).musicDiscID)
    }

    func test_identity_andSubmissionNeverDisagreeOnTheDiscID() async throws {
        // The user is shown `identity.musicDiscID` and MeedyaDB is sent
        // `submission.disc.musicBrainzDiscId`. If those two ever diverge we
        // would be showing one thing and recording another.
        var toc = plainAudioCD()
        toc.musicBrainzDiscId = "aStoredDiscID.From-TheDrive-"

        let identifier = MusicDiscIdentifier(lookupService: lookup(.success(emptyReleasesJSON, 200)))
        let result = try await identifier.identify(toc: toc, contribute: false)
        let submission = try XCTUnwrap(result.submission)

        XCTAssertEqual(result.identity.musicDiscID, submission.disc.musicBrainzDiscId)
    }

    // MARK: - A damaged TOC is not the same as a disc with no music

    func test_identity_audioTracksButUnmeasurableTOC_isReportedAsDamagedNotEmpty() {
        // Audio tracks present, but the lead-out sits before the last track
        // starts — the ID calculation cannot produce anything from this.
        let toc = DiscTableOfContents(
            discType: "Audio CD",
            tracks: [
                DiscTrack(number: 1, startSector: 0, sectorCount: 18_000, isData: false),
                DiscTrack(number: 2, startSector: 18_000, sectorCount: 21_000, isData: false),
            ],
            leadOutSector: 10,
            firstTrackNumber: 1,
            lastTrackNumber: 2
        )

        let identity = MusicDiscIdentifier.identity(for: toc)

        XCTAssertNil(identity.musicDiscID)
        XCTAssertEqual(identity.audioTrackCount, 2)
        XCTAssertFalse(identity.isUsable)
        XCTAssertTrue(identity.hasUnreadableTableOfContents,
                      "saying 'no audio tracks' under a line reading 'Audio tracks: 2' is a contradiction")
    }

    func test_identify_damagedTOC_usesTheDamagedWordingNotTheNoAudioWording() async throws {
        let toc = DiscTableOfContents(
            discType: "Audio CD",
            tracks: [DiscTrack(number: 1, startSector: 5_000, sectorCount: 18_000, isData: false)],
            leadOutSector: 10,
            firstTrackNumber: 1,
            lastTrackNumber: 1
        )
        let identifier = MusicDiscIdentifier(lookupService: lookup(.success(releasesJSON, 200)))

        let result = try await identifier.identify(toc: toc, contribute: false)

        XCTAssertEqual(result.contribution, .notAttempted(reason: MusicDiscIdentifier.unreadableTOCReason))
        XCTAssertEqual(result.summary, "This disc's table of contents is incomplete, so it can't be identified.")
    }

    // MARK: - A data-only disc costs nothing

    func test_identify_dataOnlyDisc_makesZeroRequestsAndIsNotAFailure() async throws {
        let mbClient = IdentifyStubHTTPClient(.success(releasesJSON, 200))
        let dbClient = IdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = MusicDiscIdentifier(
            lookupService: MusicBrainzDiscLookupService(
                httpClient: mbClient,
                throttle: MusicBrainzRequestThrottle(minimumInterval: .zero)
            ),
            publisher: publisher(dbClient)
        )

        let result = try await identifier.identify(toc: dataOnlyDisc())

        XCTAssertEqual(mbClient.callCount, 0, "a disc with no music must not cost a MusicBrainz request")
        XCTAssertEqual(dbClient.callCount, 0, "and must not be submitted anywhere")
        XCTAssertFalse(result.isIdentified)
        XCTAssertNil(result.submission)
        XCTAssertEqual(result.contribution, .notAttempted(reason: MusicDiscIdentifier.noAudioReason))
        XCTAssertNil(result.lookupFailure, "nothing was attempted, so nothing failed")
    }

    // MARK: - The happy path

    func test_identify_successfulLookupAndSubmission() async throws {
        let dbClient = IdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(releasesJSON, 200)),
            publisher: publisher(dbClient)
        )

        let result = try await identifier.identify(toc: plainAudioCD())

        XCTAssertTrue(result.isIdentified)
        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.matches.first?.title, "Greatest Hits")
        XCTAssertEqual(result.matches.first?.artist, "Queen")
        XCTAssertNil(result.lookupFailure)
        XCTAssertEqual(dbClient.callCount, 1)
        XCTAssertEqual(
            result.contribution,
            .succeeded(MeedyaDBIngestResult(discPublicId: "disc_abc123", matched: true, releasePublicId: "rel_xyz789"))
        )
        XCTAssertTrue(result.contribution.didSubmit)
        XCTAssertNil(result.contribution.reason)
    }

    func test_identify_submissionCarriesTheComputedDiscID() async throws {
        let dbClient = IdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(releasesJSON, 200)),
            publisher: publisher(dbClient)
        )

        let result = try await identifier.identify(toc: plainAudioCD())
        let submission = try XCTUnwrap(result.submission)

        XCTAssertEqual(submission.disc.musicBrainzDiscId, result.identity.musicDiscID)
        XCTAssertEqual(submission.disc.tocFingerprint, result.identity.tocFingerprint)
        XCTAssertEqual(submission.disc.trackCount, 3)
        XCTAssertTrue(submission.hasUsableIdentity)
    }

    // MARK: - MusicBrainz failing must NOT abandon the run

    func test_identify_lookupFailure_stillContributesTheDiscIDs() async throws {
        let dbClient = IdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.failure(URLError(.notConnectedToInternet))),
            publisher: publisher(dbClient)
        )

        let result = try await identifier.identify(toc: plainAudioCD())

        XCTAssertNotNil(result.lookupFailure, "the outage must be reported, not hidden")
        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertNotNil(result.identity.musicDiscID, "the locally computed ID survives an outage")
        XCTAssertEqual(dbClient.callCount, 1,
                       "a disc MusicBrainz cannot tell us about is exactly the one MeedyaDB wants")
        XCTAssertTrue(result.contribution.didSubmit)
    }

    func test_identify_lookupFindsNothing_isNotAFailure() async throws {
        let dbClient = IdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(emptyReleasesJSON, 200)),
            publisher: publisher(dbClient)
        )

        let result = try await identifier.identify(toc: plainAudioCD())

        XCTAssertFalse(result.isIdentified)
        XCTAssertNil(result.lookupFailure, "an honest 'we don't know this disc' is not a failure")
        XCTAssertTrue(result.contribution.didSubmit)
    }

    // MARK: - MeedyaDB off / unconfigured is NOT a failure

    func test_identify_meedyaDBDisabled_isNotAttemptedNotFailed() async throws {
        let dbClient = IdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(releasesJSON, 200)),
            publisher: publisher(dbClient, enabled: false)
        )

        let result = try await identifier.identify(toc: plainAudioCD())

        XCTAssertTrue(result.isIdentified, "identification still works with publishing off")
        XCTAssertEqual(dbClient.callCount, 0, "a disabled publisher must not touch the network")
        XCTAssertFalse(result.contribution.didSubmit)
        if case .failed = result.contribution {
            XCTFail("publishing being switched off must never be reported as a failure")
        }
        XCTAssertNotNil(result.contribution.reason)
    }

    func test_identify_defaultPublisher_isUsableAndQuietlySkipsTheUpload() async throws {
        // `MusicDiscIdentifier()` must be a sensible production object today,
        // while MeedyaDB has not been deployed yet.
        let identifier = MusicDiscIdentifier(lookupService: lookup(.success(releasesJSON, 200)))

        let result = try await identifier.identify(toc: plainAudioCD())

        XCTAssertTrue(result.isIdentified)
        XCTAssertFalse(result.contribution.didSubmit)
        if case .failed = result.contribution {
            XCTFail("an unconfigured MeedyaDB must never be reported as a failure")
        }
    }

    func test_identify_contributeFalse_neverTouchesThePublisher() async throws {
        let dbClient = IdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(releasesJSON, 200)),
            publisher: publisher(dbClient)
        )

        let result = try await identifier.identify(toc: plainAudioCD(), contribute: false)

        XCTAssertEqual(dbClient.callCount, 0)
        XCTAssertEqual(result.contribution, .notAttempted(reason: MusicDiscIdentifier.notRequestedReason))
        XCTAssertNotNil(result.submission, "what WOULD have been sent is still worth showing the user")
    }

    // MARK: - Privacy: the label and the mode must reach the wire correctly
    //
    // The scrub itself is covered by MeedyaDBPublisherTests. These tests
    // cover the WIRING one level up — that `identify` actually hands its
    // `mode:` and `labelText:` to the publisher. Without them, hardcoding
    // `mode: .full` in `contributeIfPossible` would leave every other test
    // passing while anonymous users quietly started sending disc labels.

    func test_identify_anonymousMode_neverPutsTheLabelOnTheWire() async throws {
        let dbClient = IdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(releasesJSON, 200)),
            publisher: publisher(dbClient)
        )

        let result = try await identifier.identify(
            toc: plainAudioCD(),
            labelText: "Private Home Label",
            mode: .anonymous
        )

        XCTAssertTrue(result.contribution.didSubmit)
        let sent = try sentPayload(dbClient)
        XCTAssertEqual(sent["submission"] as? String, "anonymous",
                       "the mode must reach the payload, not be assumed by the publisher's default")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertNil(disc["labelText"],
                     "the label must never leave the machine in anonymous mode")
        XCTAssertFalse(try rawSentBody(dbClient).contains("Private Home Label"),
                       "and must not survive anywhere else in the payload either")
    }

    func test_identify_fullMode_doesSendTheLabel() async throws {
        let dbClient = IdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(releasesJSON, 200)),
            publisher: publisher(dbClient)
        )

        let result = try await identifier.identify(
            toc: plainAudioCD(),
            labelText: "Private Home Label",
            mode: .full
        )

        XCTAssertTrue(result.contribution.didSubmit)
        let sent = try sentPayload(dbClient)
        XCTAssertEqual(sent["submission"] as? String, "full")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertEqual(disc["labelText"] as? String, "Private Home Label",
                       "full mode is an explicit opt-in, so the label is expected here")
    }

    // MARK: - A real MeedyaDB failure IS a failure

    func test_identify_meedyaDBRejectsTheKey_isReportedAsFailedNotThrown() async throws {
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(releasesJSON, 200)),
            publisher: publisher(IdentifyStubHTTPClient(.success(Data(), 401)))
        )

        // Must NOT throw: the identification succeeded, only the upload failed.
        let result = try await identifier.identify(toc: plainAudioCD())

        XCTAssertTrue(result.isIdentified, "the identification result survives an upload failure")
        guard case .failed(let reason) = result.contribution else {
            return XCTFail("a rejected API key is a real failure, not a quiet skip")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func test_identify_meedyaDBServerError_isReportedAsFailed() async throws {
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(releasesJSON, 200)),
            publisher: publisher(IdentifyStubHTTPClient(.success(Data("boom".utf8), 500)))
        )

        let result = try await identifier.identify(toc: plainAudioCD())

        guard case .failed = result.contribution else {
            return XCTFail("HTTP 500 must be reported as a failure")
        }
    }

    // MARK: - Cancellation stays cancellation

    func test_identify_cancellationDuringSubmit_propagatesAndIsNotAFailure() async {
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.success(releasesJSON, 200)),
            publisher: publisher(IdentifyStubHTTPClient(.failure(CancellationError())))
        )

        do {
            _ = try await identifier.identify(toc: plainAudioCD())
            XCTFail("cancellation must propagate, not be folded into a result")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func test_identify_cancellationDuringLookup_propagates() async {
        let identifier = MusicDiscIdentifier(
            lookupService: lookup(.failure(CancellationError())),
            publisher: publisher(IdentifyStubHTTPClient(.success(ingestJSON, 200)))
        )

        do {
            _ = try await identifier.identify(toc: plainAudioCD())
            XCTFail("a cancelled lookup must stop the run, not be treated as an outage")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // MARK: - Plain-English summary wording

    func test_summary_namesTheReleaseWhenIdentified() async throws {
        let identifier = MusicDiscIdentifier(lookupService: lookup(.success(releasesJSON, 200)))
        let result = try await identifier.identify(toc: plainAudioCD(), contribute: false)
        XCTAssertEqual(result.summary, "Identified as Queen — Greatest Hits.")
    }

    func test_summary_saysSoWhenMusicBrainzHasNeverSeenTheDisc() async throws {
        let identifier = MusicDiscIdentifier(lookupService: lookup(.success(emptyReleasesJSON, 200)))
        let result = try await identifier.identify(toc: plainAudioCD(), contribute: false)
        XCTAssertEqual(result.summary, "MusicBrainz doesn't know this disc yet.")
    }

    func test_summary_distinguishesAnOutageFromAnUnknownDisc() async throws {
        let identifier = MusicDiscIdentifier(lookupService: lookup(.failure(URLError(.timedOut))))
        let result = try await identifier.identify(toc: plainAudioCD(), contribute: false)
        XCTAssertTrue(result.summary.hasPrefix("Couldn't check with MusicBrainz:"),
                      "an outage must read differently from 'this disc is unknown'")
    }

    func test_summary_saysThereIsNothingToIdentifyForADataDisc() async throws {
        let identifier = MusicDiscIdentifier(lookupService: lookup(.success(releasesJSON, 200)))
        let result = try await identifier.identify(toc: dataOnlyDisc(), contribute: false)
        XCTAssertEqual(result.summary, "This disc has no audio tracks, so there is nothing to identify.")
    }
}
