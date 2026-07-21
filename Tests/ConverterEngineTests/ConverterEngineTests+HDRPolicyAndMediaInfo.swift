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

    // MARK: HDRCompatibility

    /// Verifies H.265 HDR compatibility.
    func test_hdrPolicyEngine_compatibility_h265() {
        let compat = HDRPolicyEngine.compatibility(videoCodec: "libx265", container: "mkv")
        XCTAssertTrue(compat.supportsHDR10)
        XCTAssertTrue(compat.supportsHLG)
        XCTAssertTrue(compat.supportsDolbyVision)
        XCTAssertTrue(compat.supportsHDR10Plus)
        XCTAssertTrue(compat.supports10Bit)
    }

    /// Verifies H.264 does not support HDR.
    func test_hdrPolicyEngine_compatibility_h264() {
        let compat = HDRPolicyEngine.compatibility(videoCodec: "libx264", container: "mp4")
        XCTAssertFalse(compat.supportsHDR10)
        XCTAssertFalse(compat.supportsHLG)
        XCTAssertFalse(compat.supportsDolbyVision)
        XCTAssertFalse(compat.supportsAnyHDR)
    }

    /// Verifies AV1 HDR compatibility.
    func test_hdrPolicyEngine_compatibility_av1() {
        let compat = HDRPolicyEngine.compatibility(videoCodec: "libsvtav1", container: "webm")
        XCTAssertTrue(compat.supportsHDR10)
        XCTAssertTrue(compat.supportsHLG)
        XCTAssertFalse(compat.supportsDolbyVision)
    }

    // MARK: HDRPolicyEngine Actions

    /// Verifies SDR source gets passthrough action.
    func test_hdrPolicyEngine_sdrSource_passthrough() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .sdr,
            videoCodec: "libx264",
            container: "mp4"
        )
        XCTAssertEqual(action, .passthrough)
    }

    /// Verifies HDR10 → H.264 triggers tone map.
    func test_hdrPolicyEngine_hdr10ToH264_toneMap() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .hdr10,
            videoCodec: "libx264",
            container: "mp4"
        )
        XCTAssertEqual(action, .toneMapToSDR)
    }

    /// Verifies HDR10 → H.265 preserves.
    func test_hdrPolicyEngine_hdr10ToH265_preserve() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .hdr10,
            videoCodec: "libx265",
            container: "mkv"
        )
        XCTAssertEqual(action, .preserve)
    }

    /// Verifies DV → VP9 strips dynamic metadata.
    func test_hdrPolicyEngine_dvToVP9_stripDynamic() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .dolbyVision,
            videoCodec: "libvpx-vp9",
            container: "mkv"
        )
        // VP9 supports HDR10 but not DV
        XCTAssertEqual(action, .stripDynamicMetadata)
    }

    /// Verifies user preference overrides auto-detection.
    func test_hdrPolicyEngine_userPreference() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .hdr10,
            videoCodec: "libx265",
            container: "mkv",
            userPreference: .toneMapToSDR
        )
        XCTAssertEqual(action, .toneMapToSDR)
    }

    /// Verifies preserve arguments for HLG.
    func test_hdrPolicyEngine_preserveArguments_hlg() {
        let args = HDRPolicyEngine.buildPreserveArguments(sourceFormat: .hlg)
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("arib-std-b67"))
        XCTAssertTrue(args.contains("bt2020"))
    }

    /// Verifies preserve arguments for HDR10.
    func test_hdrPolicyEngine_preserveArguments_hdr10() {
        let args = HDRPolicyEngine.buildPreserveArguments(sourceFormat: .hdr10)
        XCTAssertTrue(args.contains("smpte2084"))
    }

    /// Verifies tone map arguments include filter.
    func test_hdrPolicyEngine_buildArguments_toneMap() {
        let args = HDRPolicyEngine.buildArguments(action: .toneMapToSDR, sourceFormat: .hdr10)
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("-color_primaries"))
        XCTAssertTrue(args.contains("bt709"))
    }

    /// Verifies passthrough returns empty arguments.
    func test_hdrPolicyEngine_buildArguments_passthrough() {
        let args = HDRPolicyEngine.buildArguments(action: .passthrough, sourceFormat: .sdr)
        XCTAssertTrue(args.isEmpty)
    }

    // MARK: HDR Detection

    /// Verifies HDR format detection from stream metadata.
    func test_hdrPolicyEngine_detectFormat_pq() {
        let fmt = HDRPolicyEngine.detectFormat(
            colorTransfer: "smpte2084",
            colorPrimaries: "bt2020"
        )
        XCTAssertEqual(fmt, .hdr10)
    }

    /// Verifies HLG detection.
    func test_hdrPolicyEngine_detectFormat_hlg() {
        let fmt = HDRPolicyEngine.detectFormat(
            colorTransfer: "arib-std-b67",
            colorPrimaries: "bt2020"
        )
        XCTAssertEqual(fmt, .hlg)
    }

    /// Verifies Dolby Vision detection from side data.
    func test_hdrPolicyEngine_detectFormat_dv() {
        let fmt = HDRPolicyEngine.detectFormat(
            colorTransfer: "smpte2084",
            colorPrimaries: "bt2020",
            sideDataList: ["Dolby Vision configuration"]
        )
        XCTAssertEqual(fmt, .dolbyVisionHDR10)
    }

    /// Verifies SDR detection.
    func test_hdrPolicyEngine_detectFormat_sdr() {
        let fmt = HDRPolicyEngine.detectFormat(
            colorTransfer: "bt709",
            colorPrimaries: "bt709"
        )
        XCTAssertEqual(fmt, .sdr)
    }

    /// Verifies recommended pixel format for HDR.
    func test_hdrPolicyEngine_recommendedPixelFormat() {
        let fmt = HDRPolicyEngine.recommendedPixelFormat(action: .preserve, currentPixelFormat: "yuv420p")
        XCTAssertEqual(fmt, "yuv420p10le")

        let noChange = HDRPolicyEngine.recommendedPixelFormat(action: .preserve, currentPixelFormat: "yuv420p10le")
        XCTAssertNil(noChange)

        let sdr = HDRPolicyEngine.recommendedPixelFormat(action: .toneMapToSDR, currentPixelFormat: nil)
        XCTAssertEqual(sdr, "yuv420p")
    }

    // MARK: HLGMetadataPreserver

    /// Verifies HLG preservation arguments.
    func test_hlgMetadataPreserver_preservationArguments() {
        let args = HLGMetadataPreserver.buildPreservationArguments()
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("arib-std-b67"))
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("-color_range"))
        XCTAssertTrue(args.contains("tv"))
    }

    /// Verifies HLG preservation with CLL/FALL.
    func test_hlgMetadataPreserver_withCLL() {
        let args = HLGMetadataPreserver.buildPreservationArguments(maxCLL: 1000, maxFALL: 400)
        XCTAssertTrue(args.contains("-max_cll"))
        XCTAssertTrue(args.contains("1000,400"))
    }

    /// Verifies HLG pixel format upgrade.
    func test_hlgMetadataPreserver_pixelFormat() {
        let upgrade = HLGMetadataPreserver.buildPixelFormatArguments(sourcePixelFormat: "yuv420p")
        XCTAssertTrue(upgrade.contains("yuv420p10le"))

        let keep = HLGMetadataPreserver.buildPixelFormatArguments(sourcePixelFormat: "yuv420p10le")
        XCTAssertTrue(keep.contains("yuv420p10le"))
    }

    /// Verifies HLG encoder capability check.
    func test_hlgMetadataPreserver_encoderCapable() {
        XCTAssertTrue(HLGMetadataPreserver.isEncoderHLGCapable(encoder: "libx265"))
        XCTAssertTrue(HLGMetadataPreserver.isEncoderHLGCapable(encoder: "hevc_videotoolbox"))
        XCTAssertFalse(HLGMetadataPreserver.isEncoderHLGCapable(encoder: "libx264"))
        XCTAssertFalse(HLGMetadataPreserver.isEncoderHLGCapable(encoder: "mpeg2video"))
    }

    // MARK: - Phase 1: MediaInfo Tests

    /// Verifies MediaInfo full report arguments.
    func test_mediaInfoBuilder_fullReport() {
        let args = MediaInfoBuilder.buildFullReportArguments(inputPath: "/tmp/video.mkv")
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("/tmp/video.mkv"))
    }

    /// Verifies MediaInfo JSON output arguments.
    func test_mediaInfoBuilder_jsonOutput() {
        let args = MediaInfoBuilder.buildFormattedArguments(
            inputPath: "/tmp/video.mkv",
            format: .json
        )
        XCTAssertTrue(args.contains("--Output=JSON"))
    }

    /// Verifies MediaInfo XML output arguments.
    func test_mediaInfoBuilder_xmlOutput() {
        let args = MediaInfoBuilder.buildFormattedArguments(
            inputPath: "/tmp/video.mkv",
            format: .xml
        )
        XCTAssertTrue(args.contains("--Output=XML"))
    }

    /// Verifies MediaInfo PBCore output arguments.
    func test_mediaInfoBuilder_pbcoreOutput() {
        let args = MediaInfoBuilder.buildFormattedArguments(
            inputPath: "/tmp/video.mkv",
            format: .pbcore
        )
        XCTAssertTrue(args.contains("--Output=PBCore2"))
    }

    /// Verifies MediaInfo field query arguments.
    func test_mediaInfoBuilder_fieldQuery() {
        let args = MediaInfoBuilder.buildFieldQueryArguments(
            inputPath: "/tmp/video.mkv",
            section: .video,
            field: "HDR_Format"
        )
        XCTAssertTrue(args.first?.contains("Video") ?? false)
        XCTAssertTrue(args.first?.contains("HDR_Format") ?? false)
    }

    /// Verifies MediaInfo HDR analysis arguments.
    func test_mediaInfoBuilder_hdrAnalysis() {
        let args = MediaInfoBuilder.buildHDRAnalysisArguments(inputPath: "/tmp/hdr.mkv")
        XCTAssertTrue(args.first?.contains("HDR_Format") ?? false)
        XCTAssertTrue(args.first?.contains("MaxCLL") ?? false)
        XCTAssertTrue(args.first?.contains("MasteringDisplay_Luminance") ?? false)
    }

    /// Verifies MediaInfo dual analysis arguments.
    func test_mediaInfoBuilder_dualAnalysis() {
        let (ffprobe, mediaInfo) = MediaInfoBuilder.buildDualAnalysisArguments(
            inputPath: "/tmp/video.mkv"
        )
        XCTAssertTrue(ffprobe.contains("-show_streams"))
        XCTAssertTrue(mediaInfo.contains("--Output=JSON"))
    }

    /// Verifies MediaInfo HDR format parsing.
    func test_mediaInfoBuilder_parseHDRFormat() {
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat("Dolby Vision, Version 1.0, Profile 8.1"),
            .dolbyVision
        )
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat("SMPTE ST 2086, HDR10 compatible"),
            .hdr10
        )
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat("SMPTE ST 2094 App 4, HDR10+ Profile A"),
            .hdr10Plus
        )
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat("HLG"),
            .hlg
        )
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat(nil),
            .sdr
        )
    }

    /// Verifies DV profile parsing.
    func test_mediaInfoBuilder_parseDVProfile() {
        XCTAssertEqual(MediaInfoBuilder.parseDolbyVisionProfile("Profile 8.1"), 8)
        XCTAssertNil(MediaInfoBuilder.parseDolbyVisionProfile(nil))
    }

    /// Verifies MediaInfo search paths exist.
    func test_mediaInfoBuilder_searchPaths() {
        let paths = MediaInfoBuilder.searchPaths()
        XCTAssertFalse(paths.isEmpty)
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
