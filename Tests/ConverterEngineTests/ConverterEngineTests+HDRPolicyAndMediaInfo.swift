// ============================================================================
// MeedyaConverter — ConverterEngine unit tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Split from ConverterEngineTests.swift (re #452) to keep the test file
// under a manageable size. This file extends `ConverterEngineTests`
// (declared in ConverterEngineTests.swift) with a cohesive group of test
// methods. No test body, name, or assertion was changed during the split.
// ============================================================================

import XCTest
import ConverterEngine

extension ConverterEngineTests {
    // MARK: - Phase 3: HDR Policy Engine Tests

    // MARK: HDRFormat

    /// Verifies HDR format properties.
    func test_hdrFormat_properties() {
        XCTAssertTrue(HDRFormat.hdr10.isHDR)
        XCTAssertTrue(HDRFormat.hdr10.isPQ)
        XCTAssertFalse(HDRFormat.hdr10.isHLG)
        XCTAssertFalse(HDRFormat.hdr10.hasDynamicMetadata)

        XCTAssertTrue(HDRFormat.hlg.isHDR)
        XCTAssertTrue(HDRFormat.hlg.isHLG)
        XCTAssertFalse(HDRFormat.hlg.isPQ)

        XCTAssertTrue(HDRFormat.dolbyVision.hasDynamicMetadata)
        XCTAssertTrue(HDRFormat.hdr10Plus.hasDynamicMetadata)

        XCTAssertFalse(HDRFormat.sdr.isHDR)
    }

    /// Verifies HDR format display names.
    func test_hdrFormat_displayNames() {
        XCTAssertEqual(HDRFormat.hdr10.displayName, "HDR10")
        XCTAssertEqual(HDRFormat.dolbyVision.displayName, "Dolby Vision")
        XCTAssertEqual(HDRFormat.hlg.displayName, "HLG")
    }

    // MARK: - Phase 5: Matrix Encoding Tests

    // MARK: MatrixEncodingFormat

    /// Verifies matrix encoding properties.
    func test_matrixEncoding_properties() {
        XCTAssertTrue(MatrixEncodingFormat.dolbyProLogicII.isDecodable)
        XCTAssertEqual(MatrixEncodingFormat.dolbyProLogicII.maxDecodeChannels, 6)
        XCTAssertEqual(MatrixEncodingFormat.dolbyProLogicIIx.maxDecodeChannels, 8)
        XCTAssertFalse(MatrixEncodingFormat.none.isDecodable)
        XCTAssertEqual(MatrixEncodingFormat.none.maxDecodeChannels, 2)
    }

    /// Verifies matrix encoding display names.
    func test_matrixEncoding_displayNames() {
        XCTAssertEqual(MatrixEncodingFormat.dolbyProLogicII.displayName, "Dolby Pro Logic II")
        XCTAssertEqual(MatrixEncodingFormat.dtsNeo6.displayName, "DTS Neo:6")
        XCTAssertEqual(MatrixEncodingFormat.none.displayName, "None")
    }

    // MARK: MatrixEncodingPreserver

    /// Verifies matrix encoding detection from metadata.
    func test_matrixEncodingPreserver_detect() {
        XCTAssertEqual(
            MatrixEncodingPreserver.detectFromMetadata("Dolby Pro Logic II Movie"),
            .dolbyProLogicII
        )
        XCTAssertEqual(
            MatrixEncodingPreserver.detectFromMetadata("DTS Neo:6"),
            .dtsNeo6
        )
        XCTAssertEqual(
            MatrixEncodingPreserver.detectFromMetadata("Dolby Surround"),
            .dolbySurround
        )
        XCTAssertEqual(
            MatrixEncodingPreserver.detectFromMetadata(nil),
            .none
        )
    }

    /// Verifies matrix encoding detection arguments.
    func test_matrixEncodingPreserver_detectionArgs() {
        let args = MatrixEncodingPreserver.buildDetectionArguments(
            inputPath: "/tmp/audio.m4a",
            streamIndex: 1,
            duration: 15
        )
        XCTAssertTrue(args.contains("-af"))
        XCTAssertTrue(args.contains("astats=metadata=1:reset=1"))
        XCTAssertTrue(args.contains("0:a:1"))
    }

    /// Verifies matrix preservation arguments.
    func test_matrixEncodingPreserver_preservation() {
        let args = MatrixEncodingPreserver.buildPreservationArguments(
            encoding: .dolbyProLogicII,
            streamIndex: 0
        )
        XCTAssertTrue(args.contains("ENCODING=Dolby Pro Logic II"))
        XCTAssertTrue(args.contains("DOWNMIX_TYPE=Dolby Pro Logic II"))
    }

    /// Verifies no preservation for .none encoding.
    func test_matrixEncodingPreserver_preservation_none() {
        let args = MatrixEncodingPreserver.buildPreservationArguments(encoding: .none)
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies Pro Logic II decode filter.
    func test_matrixEncodingPreserver_decodeFilter_plII() {
        let filter = MatrixEncodingPreserver.buildDecodeFilter(encoding: .dolbyProLogicII)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("pan=5.1"))
    }

    /// Verifies Dolby Surround decode filter.
    func test_matrixEncodingPreserver_decodeFilter_surround() {
        let filter = MatrixEncodingPreserver.buildDecodeFilter(encoding: .dolbySurround)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("pan=5.1"))
    }

    /// Verifies non-decodable encoding returns nil filter.
    func test_matrixEncodingPreserver_decodeFilter_none() {
        let filter = MatrixEncodingPreserver.buildDecodeFilter(encoding: .none)
        XCTAssertNil(filter)
    }

    /// Verifies full transcode arguments with decode.
    func test_matrixEncodingPreserver_transcodeArgs() {
        let args = MatrixEncodingPreserver.buildTranscodeArguments(
            encoding: .dolbyProLogicII,
            decode: true,
            targetChannels: 6
        )
        XCTAssertTrue(args.contains("-af"))
        XCTAssertTrue(args.contains("-ac"))
        XCTAssertTrue(args.contains("6"))
        XCTAssertTrue(args.contains { $0.contains("ENCODING") })
    }

    // MARK: - Phase 5: Teletext Tests

    // MARK: TeletextExtractor

    /// Verifies teletext extraction arguments.
    func test_teletextExtractor_extractArguments() {
        let args = TeletextExtractor.buildExtractArguments(
            inputPath: "/tmp/broadcast.ts",
            outputPath: "/tmp/subs.srt",
            page: 888
        )
        XCTAssertTrue(args.contains("-txt_page"))
        XCTAssertTrue(args.contains("888"))
        XCTAssertTrue(args.contains("-c:s"))
        XCTAssertTrue(args.contains("srt"))
    }

    /// Verifies teletext detect arguments.
    func test_teletextExtractor_detectArguments() {
        let args = TeletextExtractor.buildDetectArguments(inputPath: "/tmp/broadcast.ts")
        XCTAssertTrue(args.contains("-select_streams"))
        XCTAssertTrue(args.contains("s"))
        XCTAssertTrue(args.contains("-show_entries"))
    }

    /// Verifies teletext to DVB conversion.
    func test_teletextExtractor_convertToDVB() {
        let args = TeletextExtractor.buildConvertToDVBArguments(
            inputPath: "/tmp/teletext.ts",
            outputPath: "/tmp/dvb.ts"
        )
        XCTAssertTrue(args.contains("-c:s"))
        XCTAssertTrue(args.contains("dvbsub"))
    }

    /// Verifies country page lookup.
    func test_teletextExtractor_pageForCountry() {
        XCTAssertEqual(TeletextExtractor.pageForCountry("uk"), 888)
        XCTAssertEqual(TeletextExtractor.pageForCountry("de"), 150)
        XCTAssertEqual(TeletextExtractor.pageForCountry("it"), 777)
        XCTAssertEqual(TeletextExtractor.pageForCountry("unknown"), 888)
    }

    /// Verifies subtitle page dictionary completeness.
    func test_teletextExtractor_subtitlePages() {
        XCTAssertFalse(TeletextExtractor.subtitlePages.isEmpty)
        XCTAssertNotNil(TeletextExtractor.subtitlePages["default"])
    }

    /// Verifies teletext codec names.
    func test_teletextExtractor_codecNames() {
        XCTAssertTrue(TeletextExtractor.teletextCodecNames.contains("dvb_teletext"))
    }

}
