// ============================================================================
// MeedyaConverter — ConverterEngine unit tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Tests for the pure-logic BIN/CUE disc imaging core added under issue #495
// (part of #492): the DiscTrack/DiscTableOfContents/CDTextInfo model
// extensions, and the Disc/Imaging serializer types (SubchannelCodec,
// CueSheetWriter, CueSheetParser, BinCueImageWriter). No device I/O or
// process execution is exercised here — everything under test is bytes/text
// in, bytes/text out.
// ============================================================================

import XCTest
import ConverterEngine

extension ConverterEngineTests {

    // =========================================================================
    // MARK: - TrackMode / DiscTrack extensions
    // =========================================================================

    /// Verifies `trackMode` defaults are derived from `isData` when not
    /// explicitly given, preserving old call sites that only ever set
    /// `isData`.
    func test_discTrack_trackModeDefaultDerivation() {
        let dataTrack = DiscTrack(number: 1, isData: true)
        XCTAssertEqual(dataTrack.trackMode, .mode1)

        let audioTrack = DiscTrack(number: 2, isData: false)
        XCTAssertEqual(audioTrack.trackMode, .audio)

        let defaultTrack = DiscTrack(number: 3)
        XCTAssertEqual(defaultTrack.trackMode, .audio)
    }

    /// Verifies an explicit `trackMode` overrides the `isData`-derived default.
    func test_discTrack_trackModeExplicitOverride() {
        let track = DiscTrack(number: 1, isData: true, trackMode: .mode2Form2)
        XCTAssertEqual(track.trackMode, .mode2Form2)
        // isData is independent of the explicit mode override.
        XCTAssertTrue(track.isData)
    }

    /// Verifies the new `isrc` / `sessionNumber` fields default sensibly.
    func test_discTrack_newFieldDefaults() {
        let track = DiscTrack(number: 1)
        XCTAssertNil(track.isrc)
        XCTAssertEqual(track.sessionNumber, 1)
    }

    /// Verifies `TrackMode` is a complete, CUE-relevant case set.
    func test_trackMode_allCases() {
        XCTAssertEqual(TrackMode.allCases.count, 5)
        XCTAssertTrue(TrackMode.allCases.contains(.audio))
        XCTAssertTrue(TrackMode.allCases.contains(.mode1))
        XCTAssertTrue(TrackMode.allCases.contains(.mode2Form1))
        XCTAssertTrue(TrackMode.allCases.contains(.mode2Form2))
        XCTAssertTrue(TrackMode.allCases.contains(.mode2Raw))
    }

    // =========================================================================
    // MARK: - DiscSession / DiscTableOfContents extensions
    // =========================================================================

    /// Verifies `DiscSession` equality compares all fields.
    func test_discSession_equatable() {
        let a = DiscSession(number: 1, firstTrack: 1, lastTrack: 10, leadOutSector: 200_000)
        let b = DiscSession(number: 1, firstTrack: 1, lastTrack: 10, leadOutSector: 200_000)
        let c = DiscSession(number: 2, firstTrack: 11, lastTrack: 14, leadOutSector: 350_000)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    /// Verifies `sessions` / `hasSubchannel` default to empty/false, so
    /// existing single-session callers are unaffected.
    func test_discTableOfContents_sessionAndSubchannelDefaults() {
        let toc = DiscTableOfContents()
        XCTAssertTrue(toc.sessions.isEmpty)
        XCTAssertFalse(toc.hasSubchannel)
    }

    /// Verifies a multi-session TOC can be constructed with the new fields.
    func test_discTableOfContents_multiSessionConstruction() {
        let sessions = [
            DiscSession(number: 1, firstTrack: 1, lastTrack: 10, leadOutSector: 200_000),
            DiscSession(number: 2, firstTrack: 11, lastTrack: 14, leadOutSector: 350_000),
        ]
        let toc = DiscTableOfContents(sessions: sessions, hasSubchannel: true)
        XCTAssertEqual(toc.sessions.count, 2)
        XCTAssertEqual(toc.sessions[1].firstTrack, 11)
        XCTAssertTrue(toc.hasSubchannel)
    }

    // =========================================================================
    // MARK: - CDTextInfo extensions
    // =========================================================================

    /// Verifies the new CD-TEXT pack fields default to nil.
    func test_cdTextInfo_newFieldDefaults() {
        let info = CDTextInfo(albumTitle: "T")
        XCTAssertNil(info.songwriter)
        XCTAssertNil(info.composer)
        XCTAssertNil(info.message)
    }

    /// Verifies the new CD-TEXT pack fields are settable and retained.
    func test_cdTextInfo_newFieldsSettable() {
        let info = CDTextInfo(
            albumTitle: "T",
            songwriter: "SW",
            composer: "CMP",
            message: "Hello"
        )
        XCTAssertEqual(info.songwriter, "SW")
        XCTAssertEqual(info.composer, "CMP")
        XCTAssertEqual(info.message, "Hello")
    }

    // =========================================================================
    // MARK: - SubchannelCodec
    // =========================================================================

    /// Builds `sectorCount` synthetic 2448-byte raw sectors, each with its
    /// main-channel region filled with `mainByte` and its subchannel region
    /// filled with `subByte`.
    private func makeRawSectorsWithSubchannel(
        sectorCount: Int, mainByte: UInt8, subByte: UInt8
    ) -> Data {
        var data = Data()
        for _ in 0..<sectorCount {
            data.append(Data(repeating: mainByte, count: SubchannelCodec.mainSectorSize))
            data.append(Data(repeating: subByte, count: SubchannelCodec.subchannelSize))
        }
        return data
    }

    /// Verifies the sector size constants match the Red Book / raw+subchannel
    /// layout this type is documented to implement.
    func test_subchannelCodec_constants() {
        XCTAssertEqual(SubchannelCodec.mainSectorSize, 2352)
        XCTAssertEqual(SubchannelCodec.subchannelSize, 96)
        XCTAssertEqual(SubchannelCodec.rawSectorWithSubSize, 2448)
    }

    /// Verifies a byte-correct split: main and subchannel streams have the
    /// expected lengths, and every byte in each stream matches the fill
    /// value placed in the corresponding region of the synthetic input.
    func test_subchannelCodec_splitRawSectors_byteCorrect() throws {
        let sectorCount = 4
        let data = makeRawSectorsWithSubchannel(sectorCount: sectorCount, mainByte: 0xAA, subByte: 0x55)

        let result = try SubchannelCodec.splitRawSectors(data, hasSubchannel: true)

        XCTAssertEqual(result.main.count, sectorCount * SubchannelCodec.mainSectorSize)
        XCTAssertEqual(result.subchannel?.count, sectorCount * SubchannelCodec.subchannelSize)
        XCTAssertTrue(result.main.allSatisfy { $0 == 0xAA })
        XCTAssertTrue((result.subchannel ?? Data()).allSatisfy { $0 == 0x55 })
    }

    /// Verifies that with `hasSubchannel: false`, the input passes straight
    /// through as the main channel with no subchannel stream produced.
    func test_subchannelCodec_noSubchannelPassthrough() throws {
        let data = Data(repeating: 0x7F, count: SubchannelCodec.mainSectorSize * 3)
        let result = try SubchannelCodec.splitRawSectors(data, hasSubchannel: false)
        XCTAssertEqual(result.main, data)
        XCTAssertNil(result.subchannel)
    }

    /// Verifies a non-multiple-of-sector-size buffer throws for both the
    /// subchannel and no-subchannel code paths, with a descriptive error.
    func test_subchannelCodec_nonMultipleLengthThrows() {
        let badData = Data(repeating: 0, count: 100)

        XCTAssertThrowsError(
            try SubchannelCodec.splitRawSectors(badData, hasSubchannel: true)
        ) { error in
            guard case ImagingError.invalidSectorDataLength(let byteCount, let sectorSize) = error else {
                XCTFail("Expected invalidSectorDataLength, got \(error)")
                return
            }
            XCTAssertEqual(byteCount, 100)
            XCTAssertEqual(sectorSize, SubchannelCodec.rawSectorWithSubSize)
        }

        XCTAssertThrowsError(
            try SubchannelCodec.splitRawSectors(badData, hasSubchannel: false)
        ) { error in
            guard case ImagingError.invalidSectorDataLength(let byteCount, let sectorSize) = error else {
                XCTFail("Expected invalidSectorDataLength, got \(error)")
                return
            }
            XCTAssertEqual(byteCount, 100)
            XCTAssertEqual(sectorSize, SubchannelCodec.mainSectorSize)
        }
    }

    // =========================================================================
    // MARK: - CueSheetWriter / CueSheetParser — golden round trip
    // =========================================================================

    /// Builds a 3-track TOC exercising every directive `CueSheetWriter` can
    /// emit: a MODE1 data track plus two audio tracks, a media catalog
    /// number, disc-level CD-TEXT (title/performer/songwriter), per-track
    /// CD-TEXT + ISRC, pre-emphasis on one track, and both a real (INDEX 00)
    /// and virtual (PREGAP) pregap representation on one track.
    private func makeGoldenTOC() -> (toc: DiscTableOfContents, cdText: CDTextInfo) {
        let tracks: [DiscTrack] = [
            DiscTrack(
                number: 1,
                title: "Data Track",
                startSector: 0,
                sectorCount: 20000,
                isData: true,
                trackMode: .mode1
            ),
            DiscTrack(
                number: 2,
                title: "Song One",
                artist: "Artist One",
                startSector: 20300,
                sectorCount: 20000,
                hasPreEmphasis: true,
                isrc: "USRC17607839",
                trackMode: .audio
            ),
            DiscTrack(
                number: 3,
                title: "Song Two",
                artist: "Artist Two",
                startSector: 40450,
                sectorCount: 18000,
                trackMode: .audio
            ),
        ]

        // Track 2 has a real (in-file) 2-second pregap: INDEX 00 at sector
        // 20150, INDEX 01 (the track's official start) at sector 20300.
        // Track 3 has only its INDEX 01. Track 1 has no explicit indexes at
        // all, exercising the writer's "INDEX 01 from start sector" fallback.
        let indexes: [TrackIndex] = [
            TrackIndex(trackNumber: 2, indexNumber: 0, sector: 20150),
            TrackIndex(trackNumber: 2, indexNumber: 1, sector: 20300),
            TrackIndex(trackNumber: 3, indexNumber: 1, sector: 40450),
        ]

        let cdText = CDTextInfo(
            albumTitle: "Test Disc",
            albumArtist: "Various Artists",
            trackTitles: [1: "Data Track", 2: "Song One", 3: "Song Two"],
            trackArtists: [2: "Artist One", 3: "Artist Two"],
            songwriter: "Test Songwriter"
        )

        let toc = DiscTableOfContents(
            tracks: tracks,
            indexes: indexes,
            leadOutSector: 58450,
            firstTrackNumber: 1,
            lastTrackNumber: 3,
            catalogNumber: "0123456789012",
            cdText: cdText
        )

        return (toc, cdText)
    }

    /// Verifies the emitted CUE text contains every directive the golden
    /// TOC should produce, with correctly computed MSF values.
    func test_cueSheetWriter_directives() {
        let (toc, _) = makeGoldenTOC()
        let cue = CueSheetWriter.write(toc: toc, binaryFileName: "image.bin")

        XCTAssertTrue(cue.contains("CATALOG 0123456789012"))
        XCTAssertTrue(cue.contains("TITLE \"Test Disc\""))
        XCTAssertTrue(cue.contains("PERFORMER \"Various Artists\""))
        XCTAssertTrue(cue.contains("SONGWRITER \"Test Songwriter\""))
        XCTAssertTrue(cue.contains("FILE \"image.bin\" BINARY"))

        XCTAssertTrue(cue.contains("TRACK 01 MODE1/2352"))
        XCTAssertTrue(cue.contains("TRACK 02 AUDIO"))
        XCTAssertTrue(cue.contains("TRACK 03 AUDIO"))

        XCTAssertTrue(cue.contains("FLAGS PRE"))
        XCTAssertTrue(cue.contains("ISRC USRC17607839"))

        XCTAssertTrue(cue.contains("TITLE \"Song One\""))
        XCTAssertTrue(cue.contains("PERFORMER \"Artist One\""))

        // Track 2's pregap: PREGAP is the duration (20300 - 20150 = 150
        // frames = 2 seconds); INDEX 00/01 are absolute positions.
        XCTAssertTrue(cue.contains("PREGAP 00:02:00"))
        XCTAssertTrue(cue.contains("INDEX 00 04:28:50"))
        XCTAssertTrue(cue.contains("INDEX 01 04:30:50"))

        // Track 1's fallback INDEX 01 (no explicit indexes given).
        XCTAssertTrue(cue.contains("INDEX 01 00:00:00"))
        // Track 3's explicit INDEX 01.
        XCTAssertTrue(cue.contains("INDEX 01 08:59:25"))
    }

    /// Verifies the full golden TOC survives a write → parse round trip for
    /// every field `CueSheetWriter` is documented to emit.
    func test_cueSheetRoundTrip_golden() throws {
        let (toc, cdText) = makeGoldenTOC()
        let cue = CueSheetWriter.write(toc: toc, binaryFileName: "image.bin")

        let parsed = try CueSheetParser.parse(cue)

        XCTAssertEqual(parsed.tracks.count, 3)
        XCTAssertEqual(parsed.catalogNumber, "0123456789012")
        XCTAssertEqual(parsed.firstTrackNumber, 1)
        XCTAssertEqual(parsed.lastTrackNumber, 3)

        XCTAssertEqual(parsed.cdText?.albumTitle, "Test Disc")
        XCTAssertEqual(parsed.cdText?.albumArtist, "Various Artists")
        XCTAssertEqual(parsed.cdText?.songwriter, "Test Songwriter")
        XCTAssertEqual(parsed.cdText?.trackTitles, cdText.trackTitles)
        XCTAssertEqual(parsed.cdText?.trackArtists, cdText.trackArtists)

        let byNumber = Dictionary(uniqueKeysWithValues: parsed.tracks.map { ($0.number, $0) })

        let t1 = try XCTUnwrap(byNumber[1])
        XCTAssertEqual(t1.trackMode, .mode1)
        XCTAssertTrue(t1.isData)
        XCTAssertFalse(t1.hasPreEmphasis)
        XCTAssertNil(t1.isrc)
        XCTAssertEqual(t1.startSector, 0)
        XCTAssertEqual(t1.title, "Data Track")

        let t2 = try XCTUnwrap(byNumber[2])
        XCTAssertEqual(t2.trackMode, .audio)
        XCTAssertFalse(t2.isData)
        XCTAssertTrue(t2.hasPreEmphasis)
        XCTAssertEqual(t2.isrc, "USRC17607839")
        XCTAssertEqual(t2.startSector, 20300)
        XCTAssertEqual(t2.title, "Song One")
        XCTAssertEqual(t2.artist, "Artist One")

        let t3 = try XCTUnwrap(byNumber[3])
        XCTAssertEqual(t3.trackMode, .audio)
        XCTAssertFalse(t3.hasPreEmphasis)
        XCTAssertNil(t3.isrc)
        XCTAssertEqual(t3.startSector, 40450)
        XCTAssertEqual(t3.title, "Song Two")
        XCTAssertEqual(t3.artist, "Artist Two")

        // Indexes: the two explicit indexes on track 2, track 3's explicit
        // INDEX 01, and a synthesized INDEX 01 for track 1 (which had no
        // explicit index list, so the writer emitted the start-sector
        // fallback and the parser recovered it as a literal INDEX 01 line).
        func sector(trackNumber: Int, indexNumber: Int) -> Int? {
            parsed.indexes.first {
                $0.trackNumber == trackNumber && $0.indexNumber == indexNumber
            }?.sector
        }
        XCTAssertEqual(parsed.indexes.count, 4)
        XCTAssertEqual(sector(trackNumber: 1, indexNumber: 1), 0)
        XCTAssertEqual(sector(trackNumber: 2, indexNumber: 0), 20150)
        XCTAssertEqual(sector(trackNumber: 2, indexNumber: 1), 20300)
        XCTAssertEqual(sector(trackNumber: 3, indexNumber: 1), 40450)
    }

    // =========================================================================
    // MARK: - CueSheetParser — robustness / malformed input
    // =========================================================================

    /// Verifies unknown directives (REM comments, etc.) are silently
    /// ignored rather than causing a parse failure.
    func test_cueSheetParser_ignoresUnknownDirectives() throws {
        let cue = """
        REM GENRE Rock
        REM COMMENT ExactAudioCopy v1.0
        CATALOG 1234567890123
          TRACK 01 AUDIO
            INDEX 01 00:00:00
        """
        let toc = try CueSheetParser.parse(cue)
        XCTAssertEqual(toc.catalogNumber, "1234567890123")
        XCTAssertEqual(toc.tracks.count, 1)
    }

    /// Verifies a track with no INDEX points at all is rejected.
    func test_cueSheetParser_missingIndexThrows() {
        let cue = "FILE \"x.bin\" BINARY\n  TRACK 01 AUDIO\n  TRACK 02 AUDIO\n    INDEX 01 00:00:00\n"
        XCTAssertThrowsError(try CueSheetParser.parse(cue)) { error in
            guard case ImagingError.malformedCueSheet(let reason) = error else {
                XCTFail("Expected malformedCueSheet, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("TRACK 1"))
        }
    }

    /// Verifies a TRACK line with no mode token is rejected.
    func test_cueSheetParser_missingModeThrows() {
        XCTAssertThrowsError(try CueSheetParser.parse("  TRACK 01\n"))
    }

    /// Verifies an unsupported track mode token is rejected.
    func test_cueSheetParser_unsupportedModeThrows() {
        XCTAssertThrowsError(try CueSheetParser.parse("  TRACK 01 CDG\n")) { error in
            guard case ImagingError.malformedCueSheet = error else {
                XCTFail("Expected malformedCueSheet, got \(error)")
                return
            }
        }
    }

    /// Verifies a malformed MM:SS:FF value is rejected.
    func test_cueSheetParser_badMSFThrows() {
        let cue = "  TRACK 01 AUDIO\n    INDEX 01 not-a-time\n"
        XCTAssertThrowsError(try CueSheetParser.parse(cue))
    }

    /// Verifies the various raw-sector MODE2 CUE tokens all collapse to
    /// `.mode2Raw` (the CUE format cannot distinguish Form 1/Form 2 in the
    /// `MODE2/2352` raw form — see `TrackMode`).
    func test_cueSheetParser_mode2TokensCollapseToRaw() throws {
        let cue = "  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n"
        let toc = try CueSheetParser.parse(cue)
        XCTAssertEqual(toc.tracks.first?.trackMode, .mode2Raw)
    }

    // =========================================================================
    // MARK: - BinCueImageWriter
    // =========================================================================

    /// Verifies `.bin` bytes for a subchannel-free image are an exact
    /// pass-through of the raw sectors.
    func test_binCueImageWriter_makeBin_noSubchannel() throws {
        let sectorCount = 5
        var raw = Data()
        for i in 0..<sectorCount {
            raw.append(Data(repeating: UInt8(i), count: SubchannelCodec.mainSectorSize))
        }

        let result = try BinCueImageWriter.makeBin(fromRawSectors: raw, hasSubchannel: false)

        XCTAssertEqual(result.bin.count, sectorCount * SubchannelCodec.mainSectorSize)
        XCTAssertEqual(result.bin, raw)
        XCTAssertNil(result.subchannel)
    }

    /// Verifies `.bin` bytes for a subchannel-carrying image contain only
    /// the main-channel region, byte-correct against the synthetic input.
    func test_binCueImageWriter_makeBin_withSubchannel() throws {
        let sectorCount = 3
        var raw = Data()
        for _ in 0..<sectorCount {
            raw.append(Data(repeating: 0x11, count: SubchannelCodec.mainSectorSize))
            raw.append(Data(repeating: 0x22, count: SubchannelCodec.subchannelSize))
        }

        let result = try BinCueImageWriter.makeBin(fromRawSectors: raw, hasSubchannel: true)

        XCTAssertEqual(result.bin.count, sectorCount * SubchannelCodec.mainSectorSize)
        XCTAssertTrue(result.bin.allSatisfy { $0 == 0x11 })
        XCTAssertEqual(result.subchannel?.count, sectorCount * SubchannelCodec.subchannelSize)
        XCTAssertTrue((result.subchannel ?? Data()).allSatisfy { $0 == 0x22 })
    }

    /// Verifies malformed raw sector data propagates the underlying
    /// `SubchannelCodec` error.
    func test_binCueImageWriter_makeBin_invalidLengthThrows() {
        let bad = Data(repeating: 0, count: 10)
        XCTAssertThrowsError(try BinCueImageWriter.makeBin(fromRawSectors: bad, hasSubchannel: false))
    }

    /// Verifies `.cue` file name derivation from a `.bin` path.
    func test_binCueImageWriter_cueFileName() {
        XCTAssertEqual(BinCueImageWriter.cueFileName(forBin: "/path/to/image.bin"), "image.cue")
        XCTAssertEqual(BinCueImageWriter.cueFileName(forBin: "image"), "image.cue")
    }

    /// Verifies paired `.bin`/`.cue` file name derivation from a base name.
    func test_binCueImageWriter_pairedFileNames() {
        let pair = BinCueImageWriter.pairedFileNames(baseName: "My Album")
        XCTAssertEqual(pair.bin, "My Album.bin")
        XCTAssertEqual(pair.cue, "My Album.cue")

        let pairFromPath = BinCueImageWriter.pairedFileNames(baseName: "/out/My Album.iso")
        XCTAssertEqual(pairFromPath.bin, "My Album.bin")
        XCTAssertEqual(pairFromPath.cue, "My Album.cue")
    }

    /// Verifies the CUE-sheet convenience wrapper matches `CueSheetWriter`
    /// directly.
    func test_binCueImageWriter_makeCueSheet() {
        let toc = DiscTableOfContents(
            tracks: [DiscTrack(number: 1, startSector: 0, trackMode: .audio)],
            indexes: []
        )
        let cue = BinCueImageWriter.makeCueSheet(toc: toc, binaryFileName: "disc.bin")
        XCTAssertTrue(cue.contains("FILE \"disc.bin\" BINARY"))
        XCTAssertTrue(cue.contains("TRACK 01 AUDIO"))
    }
}
