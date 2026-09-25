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

    // An ordinary single-session audio CD — the common case, where the music-only
    // and whole-disc IDs are identical.
    private func audioTOC() -> DiscTableOfContents {
        DiscTableOfContents(
            tracks: [
                DiscTrack(number: 1, startSector: 0),
                DiscTrack(number: 2, startSector: 20_000),
            ],
            leadOutSector: 250_000
        )
    }

    // An Enhanced CD: the same music plus a data track in a second session. Here the
    // two IDs differ, and both are contributed.
    private func enhancedCD() -> DiscTableOfContents {
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
    private let expectedMusicOnlyDiscID = "CPTueITWo5NCOrtwPU8RgeVxyrA-"

    // MARK: - Audio CD

    func test_audioCD_discCarriesDiscIDTOCAndTrackCount() {
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: audioTOC())

        XCTAssertEqual(inputs.disc.discType, "audio_cd")
        XCTAssertEqual(inputs.disc.musicBrainzDiscId, expectedDiscID)
        XCTAssertEqual(inputs.disc.tocFingerprint, "1+2+250150+150+20150")
        XCTAssertEqual(inputs.disc.trackCount, 2)
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
            ],
            matchKind: .exact
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
            ],
            matchKind: .exact
        )
        XCTAssertEqual(inputs.candidates.count, 2)
        XCTAssertEqual(inputs.candidates[0].confidence, 0.5)
        XCTAssertEqual(inputs.candidates[1].confidence, 0.5)
        XCTAssertEqual(inputs.candidates[1].identifiers.first?.idValue, "mbid-2")
    }

    // MARK: - F6 / D1: a fuzzy match never becomes a candidate

    func test_audioCD_fuzzyMatchSendsNoCandidates() {
        // Same matches as the single-match exact test above, but flagged as a
        // fuzzy guess. The disc's own Disc ID and TOC fingerprint are still
        // sent (measured, not guessed) — only the candidate is withheld.
        let inputs = MeedyaDBSubmissionBuilder.audioCD(
            toc: audioTOC(),
            matches: [
                MusicBrainzDiscMatch(id: "mbid-release-1", title: "Greatest Hits", artist: "The Band")
            ],
            matchKind: .fuzzy
        )
        XCTAssertTrue(inputs.candidates.isEmpty,
                      "MeedyaDB has no notion of confidence, so a guess must never be sent as a candidate")
        XCTAssertEqual(inputs.disc.musicBrainzDiscId, expectedDiscID, "the disc's own measured id is still sent")
        XCTAssertTrue(inputs.hasUsableIdentity, "the Disc ID identifier alone is still a usable identity")
    }

    func test_audioCD_noMatchKindGivenIsTreatedAsFuzzy() {
        // Fail safe: a caller that doesn't say how sure the lookup was must
        // never have its matches trusted as exact by default.
        let inputs = MeedyaDBSubmissionBuilder.audioCD(
            toc: audioTOC(),
            matches: [MusicBrainzDiscMatch(id: "mbid-release-1", title: "Greatest Hits")]
        )
        XCTAssertTrue(inputs.candidates.isEmpty)
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
        XCTAssertFalse(
            inputs.hasUsableIdentity,
            "a bare disc type and nothing else is an unmergeable row — callers should skip it"
        )
    }

    func test_audioCD_hasUsableIdentityWhenItCarriesADiscID() {
        XCTAssertTrue(MeedyaDBSubmissionBuilder.audioCD(toc: audioTOC()).hasUsableIdentity)
    }

    // MARK: - Enhanced CD: both IDs contributed

    func test_enhancedCD_submitsMusicOnlyAsTheKeyAndWholeDiscAsAnExtraIdentifier() {
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: enhancedCD())

        // The matching key is the music-only ID — the one MusicBrainz recognises.
        XCTAssertEqual(inputs.disc.musicBrainzDiscId, expectedMusicOnlyDiscID)
        XCTAssertEqual(inputs.disc.tocFingerprint, "1+2+88750+150+20150")
        XCTAssertEqual(inputs.disc.trackCount, 2, "the data track must not be counted")

        // Both IDs go up: music-only for matching, whole-disc as the finer key.
        XCTAssertEqual(inputs.identifiers.count, 2)
        XCTAssertEqual(inputs.identifiers[0].idType, "musicbrainz-discid")
        XCTAssertEqual(inputs.identifiers[0].idValue, expectedMusicOnlyDiscID)
        XCTAssertEqual(inputs.identifiers[1].idType, "fulldisc-discid")
        XCTAssertEqual(inputs.identifiers[1].idValue, expectedDiscID)
        XCTAssertEqual(inputs.identifiers[1].source, "meedyaconverter",
                       "the whole-disc ID is ours, not MusicBrainz's")
    }

    func test_plainAudioCD_doesNotDuplicateTheSameIDTwice() {
        // On an ordinary CD the two IDs are identical, so the whole-disc identifier
        // would add nothing and is skipped.
        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: audioTOC())
        XCTAssertEqual(inputs.identifiers.count, 1)
        XCTAssertEqual(inputs.identifiers[0].idType, "musicbrainz-discid")
        XCTAssertEqual(inputs.disc.musicBrainzDiscId, expectedDiscID)
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
        XCTAssertEqual(inputs.disc.labelText, "BIG_MOVIE_DISC", "falls back to the volume name")
        XCTAssertTrue(inputs.identifiers.isEmpty)
    }

    func test_videoDisc_carriesAStructuralFingerprintSoItCanBeDeduplicated() {
        // Title durations, longest first — no personal data, so it is safe to send
        // even in anonymous mode, and it gives MeedyaDB something to match on.
        let inputs = MeedyaDBSubmissionBuilder.videoDisc(info: videoInfo(), discType: .bluray)
        XCTAssertEqual(inputs.disc.tocFingerprint, "mkv:2:7041,252")
        XCTAssertTrue(inputs.hasUsableIdentity)

        // It must survive the anonymous scrub that strips the label.
        let anonymous = MeedyaDBPublisher.buildSubmission(
            disc: inputs.disc, identifiers: inputs.identifiers,
            candidates: inputs.candidates, mode: .anonymous
        )
        XCTAssertNil(anonymous.disc.labelText)
        XCTAssertEqual(anonymous.disc.tocFingerprint, "mkv:2:7041,252")
    }

    func test_videoDisc_blankVolumeNameFallsThroughToDiscName() {
        // MakeMKV can report an empty volume name; a plain ?? chain would send "".
        let info = MakeMKVBackend.parseInfo("""
        CINFO:2,0,"The Disc Name"
        CINFO:32,0,""
        TINFO:0,9,0,"1:00:00"
        """)
        let inputs = MeedyaDBSubmissionBuilder.videoDisc(info: info, discType: .dvdVideo)
        XCTAssertEqual(inputs.disc.labelText, "The Disc Name")
    }

    func test_videoDisc_titlesWithoutDurationsYieldNoFingerprint() {
        let info = MakeMKVBackend.parseInfo(#"TINFO:0,2,0,"Untimed""#)
        let inputs = MeedyaDBSubmissionBuilder.videoDisc(info: info, discType: .dvdVideo)
        XCTAssertNil(inputs.disc.tocFingerprint)
        XCTAssertFalse(inputs.hasUsableIdentity, "nothing to match on — the caller should skip it")
    }

    func test_videoDisc_onlyIdentityProvidersBecomeIdentifiers() {
        func ranked(_ source: MetadataSource, _ externalId: String) -> ScoredDiscMatch {
            ScoredDiscMatch(
                candidate: MetadataResult(source: source, externalId: externalId, title: "X"),
                score: DiscIdentityScore(confidence: 0.5)
            )
        }
        let inputs = MeedyaDBSubmissionBuilder.videoDisc(
            info: videoInfo(), discType: .bluray,
            ranked: [ranked(.omdb, "tt0137523"), ranked(.fanArtTV, "art-1"), ranked(.tvdb, "81189")]
        )
        XCTAssertEqual(inputs.candidates.count, 3)
        // OMDb's external id IS an IMDb id, so it is recorded as one.
        XCTAssertEqual(inputs.candidates[0].identifiers.first?.idType, "imdb")
        XCTAssertEqual(inputs.candidates[0].identifiers.first?.source, "omdb")
        // Artwork is not identity.
        XCTAssertTrue(inputs.candidates[1].identifiers.isEmpty)
        XCTAssertEqual(inputs.candidates[2].identifiers.first?.idType, "tvdb")
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

    // MARK: - A stored disc ID must not fake a data session

    func test_audioCD_storedDiscIDDoesNotAttachAFullDiscIdentifierToAPlainCD() {
        // A TOC can arrive carrying a MusicBrainz ID already (a drive-supplied
        // value, a MUSICBRAINZ_DISCID tag in a .toc file, a future libdiscid
        // path). That stored value is preferred as the disc's ID, but it must
        // NOT be what decides whether a whole-disc identifier is attached:
        // comparing a stored value against a computed one makes an ordinary
        // single-session CD look like it has a data session riding along, and
        // sends MeedyaDB a "whole disc" identifier for a disc that has none.
        var toc = audioTOC()
        toc.musicBrainzDiscId = "aStoredDiscID.From-TheDrive-"

        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: toc)

        XCTAssertEqual(inputs.disc.musicBrainzDiscId, "aStoredDiscID.From-TheDrive-",
                       "the stored ID is still preferred as the disc's own ID")
        XCTAssertTrue(
            inputs.identifiers.allSatisfy { $0.idType != MeedyaDBSubmissionBuilder.fullDiscIDType },
            "a plain audio CD has no data session, so no whole-disc identifier belongs on it"
        )
    }

    func test_audioCD_enhancedCDStillGetsItsFullDiscIdentifierWithAStoredID() {
        // The mirror of the above: a real Enhanced CD must keep its whole-disc
        // identifier even when the TOC carries a stored music ID.
        var toc = enhancedCD()
        toc.musicBrainzDiscId = "aStoredDiscID.From-TheDrive-"

        let inputs = MeedyaDBSubmissionBuilder.audioCD(toc: toc)

        XCTAssertEqual(inputs.disc.musicBrainzDiscId, "aStoredDiscID.From-TheDrive-")
        XCTAssertTrue(
            inputs.identifiers.contains { $0.idType == MeedyaDBSubmissionBuilder.fullDiscIDType },
            "a disc with a data session still needs its whole-disc identifier"
        )
    }
}
