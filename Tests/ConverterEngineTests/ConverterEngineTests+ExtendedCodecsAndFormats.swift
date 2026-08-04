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
    // =========================================================================
    // MARK: - Phase 3.26: Color Space Conversion & HDR Tone Mapping
    // =========================================================================

    /// Verifies ColorPrimaries properties.
    func test_colorPrimaries_properties() {
        XCTAssertEqual(ColorPrimaries.bt709.displayName, "BT.709 (HD)")
        XCTAssertEqual(ColorPrimaries.bt2020.displayName, "BT.2020 (UHD)")
        XCTAssertTrue(ColorPrimaries.bt2020.isWideGamut)
        XCTAssertTrue(ColorPrimaries.dciP3.isWideGamut)
        XCTAssertFalse(ColorPrimaries.bt709.isWideGamut)
        XCTAssertFalse(ColorPrimaries.bt601NTSC.isWideGamut)
    }

    /// Verifies TransferFunction properties.
    func test_transferFunction_properties() {
        XCTAssertTrue(TransferFunction.pq.isHDR)
        XCTAssertTrue(TransferFunction.hlg.isHDR)
        XCTAssertFalse(TransferFunction.bt709.isHDR)
        XCTAssertFalse(TransferFunction.srgb.isHDR)
        XCTAssertEqual(TransferFunction.pq.displayName, "PQ / ST 2084 (HDR10)")
    }

    /// Verifies ToneMapAlgorithm enum.
    func test_toneMapAlgorithm() {
        XCTAssertEqual(ToneMapAlgorithm.hable.rawValue, "hable")
        XCTAssertEqual(ToneMapAlgorithm.reinhard.rawValue, "reinhard")
        XCTAssertFalse(ToneMapAlgorithm.hable.description.isEmpty)
    }

    /// Verifies HDR to SDR tone map filter.
    func test_colorSpaceConverter_toneMapFilter() {
        let config = ToneMapConfig(algorithm: .hable, peakBrightness: 1000, desaturation: 0.0)
        let filter = ColorSpaceConverter.buildToneMapFilter(config: config)
        XCTAssertTrue(filter.contains("zscale=t=linear"))
        XCTAssertTrue(filter.contains("gbrpf32le"))
        XCTAssertTrue(filter.contains("tonemap=hable"))
        XCTAssertTrue(filter.contains("bt709"))
        XCTAssertTrue(filter.contains("yuv420p"))
    }

    /// Verifies 10-bit SDR output option.
    func test_colorSpaceConverter_10bitSDR() {
        let config = ToneMapConfig(algorithm: .mobius, use10BitSDR: true)
        let filter = ColorSpaceConverter.buildToneMapFilter(config: config)
        XCTAssertTrue(filter.contains("yuv420p10le"))
    }

    /// Verifies HDR to SDR FFmpeg arguments.
    func test_colorSpaceConverter_hdrToSDRArguments() {
        let args = ColorSpaceConverter.buildHDRtoSDRArguments(
            inputPath: "/tmp/hdr.mkv",
            outputPath: "/tmp/sdr.mkv"
        )
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("-color_primaries"))
        XCTAssertTrue(args.contains("bt709"))
    }

    /// Verifies general color space conversion filter.
    func test_colorSpaceConverter_colorSpaceFilter() {
        let config = ColorSpaceConfig(
            targetPrimaries: .bt709,
            targetTransfer: .bt709,
            targetMatrix: .bt709
        )
        let filter = ColorSpaceConverter.buildColorSpaceFilter(config: config)
        XCTAssertTrue(filter.contains("zscale="))
        XCTAssertTrue(filter.contains("p=709"))
        XCTAssertTrue(filter.contains("t=709"))
    }

    /// Verifies HLG to SDR filter.
    func test_colorSpaceConverter_hlgToSDR() {
        let filter = ColorSpaceConverter.buildHLGtoSDRFilter()
        XCTAssertTrue(filter.contains("zscale=t=linear"))
        XCTAssertTrue(filter.contains("tonemap="))
        XCTAssertTrue(filter.contains("bt709"))
    }

    /// Verifies HDR metadata arguments.
    func test_colorSpaceConverter_hdrMetadata() {
        var metadata = HDRMetadata(maxCLL: 1000, maxFALL: 400)
        metadata.masteringDisplayMaxLuminance = 1000.0
        metadata.masteringDisplayMinLuminance = 0.005
        let args = ColorSpaceConverter.buildHDRMetadataArguments(metadata: metadata)
        XCTAssertTrue(args.contains("-max_cll"))
        XCTAssertTrue(args.contains("1000,400"))
        XCTAssertTrue(args.contains("-master_display"))
    }

    /// Verifies strip HDR metadata arguments.
    func test_colorSpaceConverter_stripHDR() {
        let args = ColorSpaceConverter.buildStripHDRMetadataArguments()
        XCTAssertTrue(args.contains("bt709"))
        XCTAssertEqual(args.count, 6)
    }

    /// Verifies DoVi to HDR10 arguments.
    func test_colorSpaceConverter_doviToHDR10() {
        let args = ColorSpaceConverter.buildDoViToHDR10Arguments(
            inputPath: "/tmp/dv.hevc",
            outputPath: "/tmp/hdr10.hevc"
        )
        XCTAssertTrue(args.contains("remove"))
        XCTAssertTrue(args.contains("-i"))
    }

    /// Verifies conversion detection helpers.
    func test_colorSpaceConverter_needsConversion() {
        XCTAssertTrue(ColorSpaceConverter.needsConversion(
            sourcePrimaries: .bt2020, targetPrimaries: .bt709,
            sourceTransfer: .pq, targetTransfer: .bt709
        ))
        XCTAssertFalse(ColorSpaceConverter.needsConversion(
            sourcePrimaries: .bt709, targetPrimaries: .bt709,
            sourceTransfer: .bt709, targetTransfer: .bt709
        ))
    }

    /// Verifies tone mapping detection.
    func test_colorSpaceConverter_needsToneMapping() {
        XCTAssertTrue(ColorSpaceConverter.needsToneMapping(
            sourceTransfer: .pq, targetTransfer: .bt709
        ))
        XCTAssertTrue(ColorSpaceConverter.needsToneMapping(
            sourceTransfer: .hlg, targetTransfer: .bt709
        ))
        XCTAssertFalse(ColorSpaceConverter.needsToneMapping(
            sourceTransfer: .bt709, targetTransfer: .bt709
        ))
    }

    /// Verifies recommended primaries by resolution.
    func test_colorSpaceConverter_recommendedPrimaries() {
        XCTAssertEqual(ColorSpaceConverter.recommendedPrimaries(forHeight: 2160), .bt2020)
        XCTAssertEqual(ColorSpaceConverter.recommendedPrimaries(forHeight: 1080), .bt709)
        XCTAssertEqual(ColorSpaceConverter.recommendedPrimaries(forHeight: 480), .bt601NTSC)
    }

    /// Verifies HDRMetadata peak brightness defaults.
    func test_hdrMetadata_peakBrightness() {
        let empty = HDRMetadata()
        XCTAssertEqual(empty.peakBrightness, 1000)

        let withCLL = HDRMetadata(maxCLL: 4000)
        XCTAssertEqual(withCLL.peakBrightness, 4000)
    }

    // MARK: - Phase 7: Stereo 3D Conversion
    // =========================================================================

    /// Verifies Stereo3DLayout properties.
    func test_stereo3DLayout_properties() {
        XCTAssertEqual(Stereo3DLayout.sideBySide.displayName, "Side-by-Side (Full)")
        XCTAssertTrue(Stereo3DLayout.sideBySideHalf.isHalfResolution)
        XCTAssertTrue(Stereo3DLayout.topBottomHalf.isHalfResolution)
        XCTAssertFalse(Stereo3DLayout.sideBySide.isHalfResolution)
    }

    /// Verifies Stereo3DOutput properties.
    func test_stereo3DOutput_properties() {
        XCTAssertEqual(Stereo3DOutput.mvHevc.displayName, "MV-HEVC (Spatial Video)")
        XCTAssertFalse(Stereo3DOutput.mvHevc.compatiblePlatforms.isEmpty)
        XCTAssertTrue(Stereo3DOutput.mvHevc.compatiblePlatforms.contains("Apple Vision Pro"))
    }

    /// Verifies left eye crop filter for SBS.
    func test_stereo3DConverter_leftEyeCropSBS() {
        let crop = Stereo3DConverter.buildLeftEyeCropFilter(
            frameWidth: 3840, frameHeight: 1080, layout: .sideBySide
        )
        XCTAssertTrue(crop.contains("crop=1920:1080:0:0"))
    }

    /// Verifies right eye crop filter for SBS.
    func test_stereo3DConverter_rightEyeCropSBS() {
        let crop = Stereo3DConverter.buildRightEyeCropFilter(
            frameWidth: 3840, frameHeight: 1080, layout: .sideBySide
        )
        XCTAssertTrue(crop.contains("crop=1920:1080:1920:0"))
    }

    /// Verifies left eye crop filter for TB.
    func test_stereo3DConverter_leftEyeCropTB() {
        let crop = Stereo3DConverter.buildLeftEyeCropFilter(
            frameWidth: 1920, frameHeight: 2160, layout: .topBottom
        )
        XCTAssertTrue(crop.contains("crop=1920:1080:0:0"))
    }

    /// Verifies right eye crop filter for TB.
    func test_stereo3DConverter_rightEyeCropTB() {
        let crop = Stereo3DConverter.buildRightEyeCropFilter(
            frameWidth: 1920, frameHeight: 2160, layout: .topBottom
        )
        XCTAssertTrue(crop.contains("crop=1920:1080:0:1080"))
    }

    /// Verifies MV-HEVC conversion arguments.
    func test_stereo3DConverter_mvHevcArguments() {
        let config = Stereo3DConfig(
            inputLayout: .sideBySide,
            outputFormat: .mvHevc
        )
        let args = Stereo3DConverter.buildMVHEVCArguments(
            inputPath: "/tmp/sbs.mkv",
            outputPath: "/tmp/spatial.mov",
            config: config,
            frameWidth: 3840,
            frameHeight: 1080
        )
        XCTAssertTrue(args.contains("hevc_videotoolbox"))
        XCTAssertTrue(args.contains("-filter_complex"))
        XCTAssertTrue(args.contains("[left]"))
        XCTAssertTrue(args.contains("[right]"))
        XCTAssertTrue(args.contains("hvc1"))
    }

    /// Verifies stereo 3D format conversion arguments.
    func test_stereo3DConverter_formatConversion() {
        let config = Stereo3DConfig(
            inputLayout: .sideBySide,
            outputFormat: .topBottom
        )
        let args = Stereo3DConverter.buildStereo3DConvertArguments(
            inputPath: "/tmp/sbs.mkv",
            outputPath: "/tmp/tb.mkv",
            config: config
        )
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains { $0.contains("stereo3d=") })
    }

    /// Verifies eye extraction arguments.
    func test_stereo3DConverter_eyeExtraction() {
        let args = Stereo3DConverter.buildEyeExtractionArguments(
            inputPath: "/tmp/sbs.mkv",
            outputPath: "/tmp/left.mkv",
            layout: .sideBySide,
            eye: "left",
            frameWidth: 3840,
            frameHeight: 1080
        )
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains { $0.contains("crop=") })
    }

    /// Verifies per-eye resolution calculation.
    func test_stereo3DConverter_perEyeResolution() {
        let sbsRes = Stereo3DConverter.perEyeResolution(
            frameWidth: 3840, frameHeight: 1080, layout: .sideBySide
        )
        XCTAssertEqual(sbsRes.width, 1920)
        XCTAssertEqual(sbsRes.height, 1080)

        let tbRes = Stereo3DConverter.perEyeResolution(
            frameWidth: 1920, frameHeight: 2160, layout: .topBottom
        )
        XCTAssertEqual(tbRes.width, 1920)
        XCTAssertEqual(tbRes.height, 1080)
    }

    /// Verifies stereo layout detection from dimensions.
    func test_stereo3DConverter_detectLayout() {
        // Very wide (ratio > 3.5) = SBS full
        let sbs = Stereo3DConverter.detectStereoLayout(frameWidth: 3840, frameHeight: 1080)
        XCTAssertEqual(sbs, .sideBySide)

        // Very tall (ratio < 0.7) = TB full
        let tb = Stereo3DConverter.detectStereoLayout(frameWidth: 1920, frameHeight: 2880)
        XCTAssertEqual(tb, .topBottom)

        // Normal aspect ratio = nil (2D)
        let normal = Stereo3DConverter.detectStereoLayout(frameWidth: 1920, frameHeight: 1080)
        XCTAssertNil(normal)
    }

    /// Verifies Stereo3DConfig defaults.
    func test_stereo3DConfig_defaults() {
        let config = Stereo3DConfig()
        XCTAssertEqual(config.inputLayout, .sideBySide)
        XCTAssertEqual(config.outputFormat, .mvHevc)
        XCTAssertFalse(config.swapEyes)
        XCTAssertTrue(config.preserveHDR)
    }

    // =========================================================================
    // MARK: - Phase 5: Surround Upmixing
    // =========================================================================

    /// Verifies UpmixAlgorithm properties.
    func test_upmixAlgorithm_properties() {
        XCTAssertTrue(UpmixAlgorithm.proLogicII.isMatrixDecode)
        XCTAssertTrue(UpmixAlgorithm.dtsNeo6.isMatrixDecode)
        XCTAssertFalse(UpmixAlgorithm.virtualSurround.isMatrixDecode)
        XCTAssertEqual(UpmixAlgorithm.proLogicII.displayName, "Dolby Pro Logic II Decode")
    }

    /// Verifies UpmixTarget properties.
    func test_upmixTarget_properties() {
        XCTAssertEqual(UpmixTarget.surround51.channelCount, 6)
        XCTAssertEqual(UpmixTarget.surround71.channelCount, 8)
        XCTAssertEqual(UpmixTarget.surround51.ffmpegLayout, "5.1")
    }

    /// Verifies virtual surround 5.1 filter.
    func test_surroundUpmixer_virtual51() {
        let filter = SurroundUpmixer.buildVirtualSurround51Filter()
        XCTAssertTrue(filter.contains("pan=5.1"))
        XCTAssertTrue(filter.contains("FL="))
        XCTAssertTrue(filter.contains("LFE="))
        XCTAssertTrue(filter.contains("lowpass"))
    }

    /// Verifies virtual surround 7.1 filter.
    func test_surroundUpmixer_virtual71() {
        let filter = SurroundUpmixer.buildVirtualSurround71Filter()
        XCTAssertTrue(filter.contains("pan=7.1"))
        XCTAssertTrue(filter.contains("SL="))
        XCTAssertTrue(filter.contains("SR="))
    }

    /// Verifies Pro Logic II decode filter.
    func test_surroundUpmixer_proLogicII() {
        let filter = SurroundUpmixer.buildProLogicIIDecodeFilter()
        XCTAssertTrue(filter.contains("pan=5.1"))
        XCTAssertTrue(filter.contains("0.707"))
        XCTAssertTrue(filter.contains("lowpass"))
    }

    /// Verifies DTS Neo:6 decode filter.
    func test_surroundUpmixer_dtsNeo6() {
        let filter = SurroundUpmixer.buildDTSNeo6DecodeFilter()
        XCTAssertTrue(filter.contains("pan=5.1"))
        XCTAssertTrue(filter.contains("lowpass"))
    }

    /// Verifies upmix arguments.
    func test_surroundUpmixer_arguments() {
        let config = UpmixConfig(algorithm: .virtualSurround, target: .surround51)
        let args = SurroundUpmixer.buildUpmixArguments(
            inputPath: "/tmp/stereo.flac",
            outputPath: "/tmp/surround.m4a",
            config: config,
            audioCodec: "aac",
            bitrate: 384
        )
        XCTAssertTrue(args.contains("-af"))
        XCTAssertTrue(args.contains("aac"))
        XCTAssertTrue(args.contains("384k"))
    }

    /// Verifies downmix filter.
    func test_surroundUpmixer_downmix() {
        let filter = SurroundUpmixer.buildDownmixFilter(sourceLayout: "5.1")
        XCTAssertTrue(filter.contains("pan=stereo"))
        XCTAssertTrue(filter.contains("FC"))
    }

    /// Verifies downmix arguments.
    func test_surroundUpmixer_downmixArguments() {
        let args = SurroundUpmixer.buildDownmixArguments(
            inputPath: "/tmp/surround.mkv",
            outputPath: "/tmp/stereo.mkv"
        )
        XCTAssertTrue(args.contains("-ac"))
        XCTAssertTrue(args.contains("2"))
    }

    /// Verifies UpmixConfig defaults.
    func test_upmixConfig_defaults() {
        let config = UpmixConfig()
        XCTAssertEqual(config.algorithm, .virtualSurround)
        XCTAssertEqual(config.target, .surround51)
        XCTAssertEqual(config.lfeCrossover, 120)
        XCTAssertEqual(config.surroundDelayMs, 20)
    }

}
