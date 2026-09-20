// ============================================================================
// MeedyaConverter — MusicBrainzDiscIDTests (Issues #502 / #503)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pins the MusicBrainz Disc ID computation. The intermediate hash-input string is
// asserted directly because it is fully derivable from the published spec (so a
// reviewer can check it by hand); the Disc ID value itself was cross-checked
// against an independent implementation of the same algorithm. Pure — no disc,
// drive or network. Public API only.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class MusicBrainzDiscIDTests: XCTestCase {

    // first=1, last=2, lead-out 250150, track offsets 150 and 20150 (pregap applied).
    private let expectedDiscID = "gxp6QVA8pvq._RJLsqjz8ptjZXk-"

    // "0102"      first track 1, last track 2
    // "0003D126"  lead-out 250150
    // "00000096"  track 1 at 150
    // "00004EB6"  track 2 at 20150
    private let expectedPrefix = "01020003D1260000009600004EB6"

    // MARK: - Hash input (spec-derivable)

    func test_hashInput_layoutMatchesSpec() throws {
        let input = try XCTUnwrap(MusicBrainzDiscID.hashInput(
            firstTrack: 1, lastTrack: 2, leadOutOffset: 250_150, trackOffsets: [150, 20_150]
        ))
        // 2 + 2 hex digits for the track numbers, then 100 slots of 8 hex digits.
        XCTAssertEqual(input.count, 804)
        XCTAssertTrue(input.hasPrefix(expectedPrefix), "got prefix \(input.prefix(28))")

        // Everything after the lead-out and the two real tracks must be zero-filled.
        let tail = String(input.dropFirst(expectedPrefix.count))
        XCTAssertEqual(tail.count, 804 - expectedPrefix.count)
        XCTAssertTrue(tail.allSatisfy { $0 == "0" }, "unused slots must be zero-filled")
    }

    func test_hashInput_rejectsInvalidParts() {
        // Offset count must match the track span.
        XCTAssertNil(MusicBrainzDiscID.hashInput(
            firstTrack: 1, lastTrack: 3, leadOutOffset: 250_150, trackOffsets: [150, 20_150]))
        // Track numbers out of range.
        XCTAssertNil(MusicBrainzDiscID.hashInput(
            firstTrack: 0, lastTrack: 2, leadOutOffset: 1000, trackOffsets: [150, 200, 300]))
        XCTAssertNil(MusicBrainzDiscID.hashInput(
            firstTrack: 1, lastTrack: 100, leadOutOffset: 1000, trackOffsets: []))
        // last before first.
        XCTAssertNil(MusicBrainzDiscID.hashInput(
            firstTrack: 5, lastTrack: 2, leadOutOffset: 1000, trackOffsets: []))
        // Negative offsets.
        XCTAssertNil(MusicBrainzDiscID.hashInput(
            firstTrack: 1, lastTrack: 1, leadOutOffset: 1000, trackOffsets: [-1]))
    }

    // MARK: - Disc ID

    func test_compute_fromParts() {
        let id = MusicBrainzDiscID.compute(
            firstTrack: 1, lastTrack: 2, leadOutOffset: 250_150, trackOffsets: [150, 20_150]
        )
        XCTAssertEqual(id, expectedDiscID)
    }

    func test_compute_producesWellFormedID() throws {
        let id = try XCTUnwrap(MusicBrainzDiscID.compute(
            firstTrack: 1, lastTrack: 2, leadOutOffset: 250_150, trackOffsets: [150, 20_150]
        ))
        XCTAssertEqual(id.count, 28)
        // Base64 characters must have been substituted for the URL-safe set.
        XCTAssertFalse(id.contains("+"))
        XCTAssertFalse(id.contains("/"))
        XCTAssertFalse(id.contains("="))
    }

    // MARK: - From a table of contents

    func test_compute_fromTOC_excludesDataTrackAndAppliesPregap() {
        // Two audio tracks plus a data track that must be ignored.
        // Lead-out 250000 + 150 = 250150; offsets 0+150 and 20000+150.
        //
        // This pins data-track exclusion, the pregap, and that the Disc ID and the
        // lookup string always describe the SAME tracks. It does NOT claim the ID
        // matches MusicBrainz for a real multi-session CD-Extra — for those,
        // MusicBrainz uses the first session's lead-out, not the disc's physical
        // one. See the LIMITATION note in MusicBrainzDiscID.swift.
        let toc = DiscTableOfContents(
            tracks: [
                DiscTrack(number: 1, startSector: 0),
                DiscTrack(number: 2, startSector: 20_000),
                DiscTrack(number: 3, startSector: 100_000, isData: true),
            ],
            leadOutSector: 250_000
        )
        XCTAssertEqual(MusicBrainzDiscID.compute(for: toc), expectedDiscID)
        // The Disc ID and the lookup string must describe the same tracks.
        XCTAssertEqual(MusicBrainzDiscLookupService.musicBrainzTOCString(for: toc), "1+2+250150+150+20150")
    }

    func test_compute_fromTOC_nilWhenNoAudioTracks() {
        let toc = DiscTableOfContents(
            tracks: [DiscTrack(number: 1, startSector: 0, isData: true)],
            leadOutSector: 1000
        )
        XCTAssertNil(MusicBrainzDiscID.compute(for: toc))
    }

    func test_hashInput_rejectsLeadOutBeforeLastTrack() {
        // A default-constructed TOC (lead-out 0) would otherwise yield a
        // confident-looking but meaningless ID.
        XCTAssertNil(MusicBrainzDiscID.hashInput(
            firstTrack: 1, lastTrack: 2, leadOutOffset: 150, trackOffsets: [150, 20_150]))
        XCTAssertNil(MusicBrainzDiscID.compute(
            firstTrack: 1, lastTrack: 1, leadOutOffset: 150, trackOffsets: [150]))
        let emptyTOC = DiscTableOfContents(
            tracks: [DiscTrack(number: 1, startSector: 0)], leadOutSector: 0
        )
        XCTAssertNil(MusicBrainzDiscID.compute(for: emptyTOC))
    }

    func test_compute_isDeterministicAndOffsetSensitive() {
        let a = MusicBrainzDiscID.compute(
            firstTrack: 1, lastTrack: 2, leadOutOffset: 250_150, trackOffsets: [150, 20_150])
        let again = MusicBrainzDiscID.compute(
            firstTrack: 1, lastTrack: 2, leadOutOffset: 250_150, trackOffsets: [150, 20_150])
        let different = MusicBrainzDiscID.compute(
            firstTrack: 1, lastTrack: 2, leadOutOffset: 250_151, trackOffsets: [150, 20_150])

        XCTAssertEqual(a, again, "same TOC must always give the same ID")
        XCTAssertNotNil(different)
        XCTAssertNotEqual(a, different, "a one-sector difference must change the ID")
    }
}
