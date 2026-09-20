// ============================================================================
// MeedyaConverter — MeedyaDBSubmissionBuilderTests (Issues #502 / #503)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Covers turning an identified disc — music OR video — into a MeedyaDB
// submission: disc facts, identifiers, and candidate identities. Pure; no disc,
// drive, network or subprocess. Public API only.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class MeedyaDBSubmissionBuilderTests: XCTestCase {

    // Enhanced CD: two audio tracks + a data track that must be excluded.
    private func audioTOC() -> DiscTableOfContents {
        DiscTableOfContents(
            tracks: [
                DiscTrack(number: 1, startSector: 0),
                DiscTrack(number: 2, startSector: 20_000),
                DiscTrack(number: 3, startSector: 100_000, isData: true),
            ],
            leadOutSector: 250_000
        )
    }

    private let expectedDiscID = "gxp6QVA8pvq._RJLsqjz8ptjZXk-"

    // MARK: - Audio CD

    func test_audioCD_discCarriesDiscIDTOCAndTrackCount() {
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: audioTOC())

        XCTAssertEqual(inputs.disc.discType, "audio_cd")
        XCTAssertEqual(inputs.disc.musicBrainzDiscId, expectedDiscID)
        XCTAssertEqual(inputs.disc.tocFingerprint, "1+2+250150+150+20150")
        XCTAssertEqual(inputs.disc.trackCount, 2, "the data track must not be counted")
        XCTAssertNil(inputs.disc.labelText, "no label supplied")
    }

    func test_audioCD_submitsTheDiscIDAsAnIdentifier() {
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: audioTOC())
        XCTAssertEqual(inputs.identifiers.count, 1)
        XCTAssertEqual(inputs.identifiers.first?.idType, "musicbrainz-discid")
        XCTAssertEqual(inputs.identifiers.first?.idValue, expectedDiscID)
        XCTAssertEqual(inputs.identifiers.first?.source, "musicbrainz")
    }

    func test_audioCD_noMatchesStillSubmitsTheDisc() {
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: audioTOC(), matches: [])
        XCTAssertTrue(inputs.candidates.isEmpty)
        // The disc itself is still worth contributing — it carries its Disc ID.
        XCTAssertEqual(inputs.identifiers.count, 1)
    }

    func test_audioCD_singleMatchIsFullConfidence() {
        let inputs = MeedyaDBSubmissionBuilder.audioCD(
            toc: audioTOC(),
            matches: [
                MusicBrainzDiscMatch(
                    id: "mbid-release-1", title: "Greatest Hits",
                    artist: "The Band", date: "1994-05-02"
                )
            ]
        )
        XCTAssertEqual(inputs.candidates.count, 1)
        let candidate = inputs.candidates[0]
        XCTAssertEqual(candidate.title, "Greatest Hits")
        XCTAssertEqual(candidate.artist, "The Band")
        XCTAssertEqual(candidate.year, 1994)
        XCTAssertEqual(candidate.confidence, 1.0)
        XCTAssertEqual(candidate.identifiers.first?.idType, "musicbrainz-release")
        XCTAssertEqual(candidate.identifiers.first?.idValue, "mbid-release-1")
    }

    func test_audioCD_multiplePressingsSplitConfidence() {
        let inputs = MeedyaDBSubmissionBuilder.audioCD(
            toc: audioTOC(),
            matches: [
                MusicBrainzDiscMatch(id: "mbid-1", title: "Album", date: "1994"),
                MusicBrainzDiscMatch(id: "mbid-2", title: "Album (UK pressing)", date: "1994"),
            ]
        )
        XCTAssertEqual(inputs.candidates.count, 2)
        XCTAssertEqual(inputs.candidates[0].confidence, 0.5)
        XCTAssertEqual(inputs.candidates[1].confidence, 0.5)
        XCTAssertEqual(inputs.candidates[1].identifiers.first?.idValue, "mbid-2")
    }

    func test_audioCD_prefersADiscIDAlreadyOnTheTOC() {
        var toc = audioTOC()
        toc.musicBrainzDiscId = "SuppliedByTheDrive-"
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: toc)
        XCTAssertEqual(inputs.disc.musicBrainzDiscId, "SuppliedByTheDrive-")
        XCTAssertEqual(inputs.identifiers.first?.idValue, "SuppliedByTheDrive-")
    }

    func test_audioCD_blankStoredDiscIDFallsBackToComputing() {
        var toc = audioTOC()
        toc.musicBrainzDiscId = "   "
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: toc)
        XCTAssertEqual(inputs.disc.musicBrainzDiscId, expectedDiscID)
    }

    func test_audioCD_labelTextIsCarriedForOptInFullMode() {
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: audioTOC(), labelText: "My Mix CD")
        XCTAssertEqual(inputs.disc.labelText, "My Mix CD")

        // The publisher still drops it unless the user opted into full submission.
        let anonymous = MeedyaDBPublisher.buildSubmission(
            disc: inputs.disc, identifiers: inputs.identifiers,
            candidates: inputs.candidates, mode: .anonymous
        )
        XCTAssertNil(anonymous.disc.labelText)
        XCTAssertEqual(anonymous.disc.musicBrainzDiscId, expectedDiscID, "the ID still goes up")
    }

    func test_audioCD_dataOnlyDiscHasNoDiscIDOrIdentifiers() {
        let toc = DiscTableOfContents(
            tracks: [DiscTrack(number: 1, startSector: 0, isData: true)],
            leadOutSector: 1000
        )
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: toc)
        XCTAssertNil(inputs.disc.musicBrainzDiscId)
        XCTAssertNil(inputs.disc.trackCount)
        XCTAssertTrue(inputs.identifiers.isEmpty)
    }

    // MARK: - Video disc

    private func videoInfo() -> MakeMKVDiscInfo {
        MakeMKVBackend.parseInfo("""
        CINFO:32,0,"BIG_MOVIE_DISC"
        TINFO:0,9,0,"1:57:21"
        TINFO:1,9,0,"0:04:12"
        """)
    }

    func test_videoDisc_discFactsAndLabelFallback() {
        let inputs = MeedyaDBSubmissionBuilder.videoDisc(info: videoInfo(), discType: .bluray)
        XCTAssertEqual(inputs.disc.discType, "bluray")
        XCTAssertEqual(inputs.disc.trackCount, 2)
        XCTAssertNil(inputs.disc.musicBrainzDiscId, "video discs have no audio TOC")
        XCTAssertNil(inputs.disc.tocFingerprint)
        XCTAssertEqual(inputs.disc.labelText, "BIG_MOVIE_DISC", "falls back to the volume name")
        XCTAssertTrue(inputs.identifiers.isEmpty)
    }

    func test_videoDisc_rankedCandidatesCarryProviderIDAndConfidence() {
        let ranked = [
            ScoredDiscMatch(
                candidate: MetadataResult(
                    source: .tmdb, externalId: "550", title: "Big Movie", year: 1999
                ),
                score: DiscIdentityScore(confidence: 0.82, reason: "Running time matches closely")
            )
        ]
        let inputs = MeedyaDBSubmissionBuilder.videoDisc(
            info: videoInfo(), discType: .dvdVideo, ranked: ranked, labelText: "Explicit Label"
        )
        XCTAssertEqual(inputs.disc.discType, "dvd_video")
        XCTAssertEqual(inputs.disc.labelText, "Explicit Label", "an explicit label wins")
        XCTAssertEqual(inputs.candidates.count, 1)
        let candidate = inputs.candidates[0]
        XCTAssertEqual(candidate.title, "Big Movie")
        XCTAssertEqual(candidate.year, 1999)
        XCTAssertEqual(candidate.confidence, 0.82)
        XCTAssertEqual(candidate.identifiers.first?.idType, "tmdb")
        XCTAssertEqual(candidate.identifiers.first?.idValue, "550")
        XCTAssertEqual(candidate.identifiers.first?.source, "tmdb")
    }
}
