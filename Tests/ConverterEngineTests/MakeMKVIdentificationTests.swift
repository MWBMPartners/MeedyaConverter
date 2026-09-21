// ============================================================================
// MeedyaConverter — MakeMKVIdentificationTests (Issue #503, slice 4a)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Covers the MakeMKV → disc-identification (#502) bridge: mapping a parsed
// MakeMKVDiscInfo into DiscSignals (main feature = longest title, durations,
// chapters, audio/subtitle languages, label, seed title, media-type hint).
// Pure; public API only.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class MakeMKVIdentificationTests: XCTestCase {

    private let videoTranscript = """
    TCOUNT:2
    CINFO:2,0,"Big Movie"
    CINFO:32,0,"BIG_MOVIE_DISC"
    TINFO:0,2,0,"Big Movie"
    TINFO:0,8,0,"12"
    TINFO:0,9,0,"1:57:21"
    SINFO:0,0,1,6201,"Video"
    SINFO:0,1,1,6202,"Audio"
    SINFO:0,1,3,0,"eng"
    SINFO:0,2,1,6203,"Subtitles"
    SINFO:0,2,3,0,"fra"
    TINFO:1,9,0,"0:04:12"
    """

    func test_discSignals_videoDisc() {
        let info = MakeMKVBackend.parseInfo(videoTranscript)
        let signals = MakeMKVIdentification.discSignals(from: info, discType: .bluray)

        XCTAssertEqual(signals.discType, .bluray)
        XCTAssertEqual(signals.mainFeatureDurationSeconds, 7041) // longest title (1:57:21)
        XCTAssertEqual(signals.titleDurationsSeconds, [7041, 252])
        XCTAssertEqual(signals.chapterCount, 12)
        XCTAssertEqual(signals.audioLanguages, ["eng"])
        XCTAssertEqual(signals.subtitleLanguages, ["fra"])
        XCTAssertEqual(signals.label, "BIG_MOVIE_DISC") // volume name preferred
        XCTAssertEqual(signals.seedTitle, "Big Movie")
        XCTAssertNil(signals.mediaTypeHint) // video → left for the query builder
        XCTAssertNil(signals.seedYear)
    }

    func test_discSignals_audioDiscHintsMusic() {
        let info = MakeMKVBackend.parseInfo(#"CINFO:2,0,"Some Album""#)
        let signals = MakeMKVIdentification.discSignals(from: info, discType: .audioCd)
        XCTAssertEqual(signals.mediaTypeHint, .music)
        XCTAssertEqual(signals.seedTitle, "Some Album")
    }

    func test_discSignals_seedTitleOverrideWins() {
        let info = MakeMKVBackend.parseInfo(videoTranscript)
        let signals = MakeMKVIdentification.discSignals(from: info, discType: .bluray, seedTitle: "Custom Seed")
        XCTAssertEqual(signals.seedTitle, "Custom Seed")
    }

    func test_discSignals_noDurations_stillSeedsFromTitleName() {
        let info = MakeMKVBackend.parseInfo(#"TINFO:0,2,0,"Untimed Title""#)
        let signals = MakeMKVIdentification.discSignals(from: info, discType: .dvdVideo)
        XCTAssertNil(signals.mainFeatureDurationSeconds)
        XCTAssertTrue(signals.titleDurationsSeconds.isEmpty)
        XCTAssertNil(signals.chapterCount)
        XCTAssertTrue(signals.audioLanguages.isEmpty)
        XCTAssertEqual(signals.seedTitle, "Untimed Title") // falls back to the first title's name
    }

    // MARK: - suggestedDiscType

    /// Build an info whose only disc attribute is MakeMKV's type string.
    private func info(type: String) -> MakeMKVDiscInfo {
        MakeMKVBackend.parseInfo("CINFO:1,0,\"\(type)\"")
    }

    func test_suggestedDiscType_readsTheOrdinaryStrings() {
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "DVD disc")), .dvdVideo)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "Blu-ray disc")), .bluray)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "UHD Blu-ray disc")), .uhdBluray)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "HD DVD disc")), .hdDvd)
    }

    /// ⚠️ THE POINT OF THIS TEST. Every one of these strings matches MORE THAN
    /// ONE of the patterns, so each pins the ORDER of the checks rather than
    /// the checks themselves. Reordering `suggestedDiscType` downgrades a disc
    /// silently — a UHD Blu-ray filed as an ordinary Blu-ray, an HD DVD filed
    /// as a DVD — and only these assertions would notice.
    func test_suggestedDiscType_theMoreSpecificFormatWinsOverItsSubstring() {
        // "UHD Blu-ray disc" also contains "blu-ray".
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "UHD Blu-ray disc")), .uhdBluray)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "Blu-ray UHD")), .uhdBluray)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "4K Blu-ray disc")), .uhdBluray)
        // "HD DVD disc" also contains "dvd".
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "HD DVD disc")), .hdDvd)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "HD-DVD")), .hdDvd)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "HDDVD disc")), .hdDvd)
    }

    func test_suggestedDiscType_spellingAndCaseDoNotMatter() {
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "BLURAY DISC")), .bluray)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "blu ray disc")), .bluray)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "dvd")), .dvdVideo)
    }

    /// The surrounding words are what a localised MakeMKV translates; the
    /// format names are proper nouns and survive. Substring matching is what
    /// buys this, so it is worth an assertion.
    func test_suggestedDiscType_survivesALocalisedTypeString() {
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "Disque Blu-ray")), .bluray)
        XCTAssertEqual(MakeMKVIdentification.suggestedDiscType(from: info(type: "Disco DVD")), .dvdVideo)
    }

    /// An unrecognised, absent or blank type must produce NO suggestion rather
    /// than a guess — the caller asks the user instead. A wrong disc type goes
    /// into a shared database and cannot be walked back.
    func test_suggestedDiscType_isNilRatherThanAGuess() {
        XCTAssertNil(MakeMKVIdentification.suggestedDiscType(from: info(type: "Something else entirely")))
        XCTAssertNil(MakeMKVIdentification.suggestedDiscType(from: info(type: "")))
        XCTAssertNil(MakeMKVIdentification.suggestedDiscType(from: info(type: "   ")))
        XCTAssertNil(MakeMKVIdentification.suggestedDiscType(from: MakeMKVDiscInfo()))
        // A scan that found a NAME but no type must not fall back to the name.
        XCTAssertNil(MakeMKVIdentification.suggestedDiscType(from: MakeMKVBackend.parseInfo(#"CINFO:2,0,"BLURAY_MOVIE""#)))
    }
}
