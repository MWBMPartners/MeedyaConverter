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

    // =========================================================================
    // MARK: - Phase 3.23: Extended Video Codecs
    // =========================================================================

    /// Verifies ExtendedVideoCodecType properties.
    func test_extendedVideoCodec_properties() {
        XCTAssertTrue(ExtendedVideoCodecType.ffv1.canEncode)
        XCTAssertTrue(ExtendedVideoCodecType.ffv1.isLossless)
        XCTAssertTrue(ExtendedVideoCodecType.cineform.canEncode)
        XCTAssertFalse(ExtendedVideoCodecType.vc1.canEncode)
        XCTAssertFalse(ExtendedVideoCodecType.wmv9.canEncode)
        XCTAssertTrue(ExtendedVideoCodecType.jpeg2000.canEncode)
    }

    /// Verifies extended codec display names.
    func test_extendedVideoCodec_displayNames() {
        XCTAssertEqual(ExtendedVideoCodecType.ffv1.displayName, "FFV1 (Archival Lossless)")
        XCTAssertEqual(ExtendedVideoCodecType.cineform.displayName, "GoPro CineForm")
        XCTAssertEqual(ExtendedVideoCodecType.jpeg2000.displayName, "JPEG 2000")
    }

    /// Verifies FFmpeg encoder/decoder names.
    func test_extendedVideoCodec_ffmpegNames() {
        XCTAssertEqual(ExtendedVideoCodecType.ffv1.ffmpegEncoder, "ffv1")
        XCTAssertEqual(ExtendedVideoCodecType.cineform.ffmpegEncoder, "cfhd")
        XCTAssertNil(ExtendedVideoCodecType.vc1.ffmpegEncoder)
        XCTAssertEqual(ExtendedVideoCodecType.vc1.ffmpegDecoder, "vc1")
    }

    /// Verifies compatible containers.
    func test_extendedVideoCodec_containers() {
        XCTAssertTrue(ExtendedVideoCodecType.ffv1.compatibleContainers.contains("mkv"))
        XCTAssertTrue(ExtendedVideoCodecType.jpeg2000.compatibleContainers.contains("mxf"))
        XCTAssertTrue(ExtendedVideoCodecType.cineform.compatibleContainers.contains("avi"))
    }

    /// Verifies FFV1 encoding arguments.
    func test_extendedVideoCodecBuilder_ffv1() {
        let config = FFV1Config(version: 3, sliceCount: 8, sliceCRC: true)
        let args = ExtendedVideoCodecBuilder.buildFFV1EncodeArguments(
            inputPath: "/tmp/source.mkv",
            outputPath: "/tmp/archive.mkv",
            config: config
        )
        XCTAssertTrue(args.contains("ffv1"))
        XCTAssertTrue(args.contains("-level"))
        XCTAssertTrue(args.contains("3"))
        XCTAssertTrue(args.contains("-slices"))
        XCTAssertTrue(args.contains("8"))
        XCTAssertTrue(args.contains("-slicecrc"))
    }

    /// Verifies CineForm encoding arguments.
    func test_extendedVideoCodecBuilder_cineform() {
        let args = ExtendedVideoCodecBuilder.buildCineFormEncodeArguments(
            inputPath: "/tmp/source.mov",
            outputPath: "/tmp/edit.avi",
            quality: 8
        )
        XCTAssertTrue(args.contains("cfhd"))
        XCTAssertTrue(args.contains("-quality"))
        XCTAssertTrue(args.contains("8"))
    }

    /// Verifies JPEG 2000 encoding arguments.
    func test_extendedVideoCodecBuilder_jpeg2000() {
        let config = JPEG2000Config(cinemaProfile: .cinema2K)
        let args = ExtendedVideoCodecBuilder.buildJPEG2000EncodeArguments(
            inputPath: "/tmp/source.mkv",
            outputPath: "/tmp/dcp.mxf",
            config: config
        )
        XCTAssertTrue(args.contains("libopenjpeg"))
        XCTAssertTrue(args.contains("-cinema_mode"))
        XCTAssertTrue(args.contains("cinema2k"))
    }

    /// Verifies JPEG2000CinemaProfile properties.
    func test_jpeg2000CinemaProfile() {
        XCTAssertEqual(JPEG2000CinemaProfile.cinema2K.maxBitrateMbps, 250)
        XCTAssertEqual(JPEG2000CinemaProfile.cinema4K.maxBitrateMbps, 500)

        let res2K = JPEG2000CinemaProfile.cinema2K.resolution
        XCTAssertEqual(res2K.width, 2048)
        XCTAssertEqual(res2K.height, 1080)
    }

    /// Verifies passthrough arguments.
    func test_extendedVideoCodecBuilder_passthrough() {
        let args = ExtendedVideoCodecBuilder.buildPassthroughArguments(
            inputPath: "/tmp/source.mkv",
            outputPath: "/tmp/output.mkv"
        )
        XCTAssertTrue(args.contains("copy"))
    }

    // =========================================================================
    // MARK: - Phase 3.24: Extended Containers
    // =========================================================================

    /// Verifies ExtendedContainerFormat properties.
    func test_extendedContainer_properties() {
        XCTAssertEqual(ExtendedContainerFormat.mxf.fileExtension, "mxf")
        XCTAssertEqual(ExtendedContainerFormat.avi.fileExtension, "avi")
        XCTAssertEqual(ExtendedContainerFormat.mpegTS.fileExtension, "ts")
        XCTAssertEqual(ExtendedContainerFormat.threeGP.fileExtension, "3gp")
    }

    /// Verifies container display names.
    func test_extendedContainer_displayNames() {
        XCTAssertTrue(ExtendedContainerFormat.mxf.displayName.contains("MXF"))
        XCTAssertTrue(ExtendedContainerFormat.avi.displayName.contains("AVI"))
        XCTAssertTrue(ExtendedContainerFormat.flv.displayName.contains("FLV"))
    }

    /// Verifies FFmpeg muxer/demuxer names.
    func test_extendedContainer_ffmpegNames() {
        XCTAssertEqual(ExtendedContainerFormat.mpegTS.ffmpegMuxer, "mpegts")
        XCTAssertEqual(ExtendedContainerFormat.avi.ffmpegMuxer, "avi")
        XCTAssertEqual(ExtendedContainerFormat.ogg.ffmpegMuxer, "ogg")
    }

    /// Verifies container codec compatibility.
    func test_extendedContainer_codecCompatibility() {
        XCTAssertTrue(ExtendedContainerBuilder.isVideoCodecCompatible("h264", with: .mpegTS))
        XCTAssertTrue(ExtendedContainerBuilder.isVideoCodecCompatible("h264", with: .flv))
        XCTAssertFalse(ExtendedContainerBuilder.isVideoCodecCompatible("hevc", with: .avi))
        XCTAssertTrue(ExtendedContainerBuilder.isVideoCodecCompatible("anything", with: .nut))
    }

    /// Verifies audio codec compatibility.
    func test_extendedContainer_audioCompatibility() {
        XCTAssertTrue(ExtendedContainerBuilder.isAudioCodecCompatible("aac", with: .mpegTS))
        XCTAssertTrue(ExtendedContainerBuilder.isAudioCodecCompatible("vorbis", with: .ogg))
        XCTAssertFalse(ExtendedContainerBuilder.isAudioCodecCompatible("flac", with: .flv))
    }

    /// Verifies MPEG-TS arguments.
    func test_extendedContainerBuilder_mpegTS() {
        let args = ExtendedContainerBuilder.buildMPEGTSArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/output.ts",
            serviceName: "MeedyaConverter"
        )
        XCTAssertTrue(args.contains("mpegts"))
        XCTAssertTrue(args.contains("resend_headers"))
        XCTAssertTrue(args.contains { $0.contains("MeedyaConverter") })
    }

    /// Verifies MXF arguments.
    func test_extendedContainerBuilder_mxf() {
        let args = ExtendedContainerBuilder.buildMXFArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/output.mxf"
        )
        XCTAssertTrue(args.contains("mpeg2video"))
        XCTAssertTrue(args.contains("pcm_s16le"))
        XCTAssertTrue(args.contains("mxf"))
    }

    /// Verifies 3GP arguments.
    func test_extendedContainerBuilder_3gp() {
        let args = ExtendedContainerBuilder.build3GPArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/output.3gp"
        )
        XCTAssertTrue(args.contains("3gp"))
        XCTAssertTrue(args.contains("h264"))
        XCTAssertTrue(args.contains("aac"))
    }

    /// Verifies recommended audio codec.
    func test_extendedContainerBuilder_recommendAudioCodec() {
        XCTAssertEqual(ExtendedContainerBuilder.recommendAudioCodec(for: .mxf), "pcm_s16le")
        XCTAssertEqual(ExtendedContainerBuilder.recommendAudioCodec(for: .ogg), "libvorbis")
        XCTAssertEqual(ExtendedContainerBuilder.recommendAudioCodec(for: .flv), "aac")
    }

    /// Verifies container feature flags.
    func test_extendedContainer_features() {
        XCTAssertTrue(ExtendedContainerFormat.ogg.supportsChapters)
        XCTAssertFalse(ExtendedContainerFormat.flv.supportsChapters)
        XCTAssertTrue(ExtendedContainerFormat.mpegTS.supportsSubtitles)
        XCTAssertNotNil(ExtendedContainerFormat.avi.maxFileSize)
    }

    // =========================================================================
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

    // =========================================================================
    // MARK: - Phase 3.25: Extended Subtitle Formats
    // =========================================================================

    /// Verifies ExtendedSubtitleFormat properties.
    func test_extendedSubtitle_properties() {
        XCTAssertEqual(ExtendedSubtitleFormat.ebuSTL.fileExtension, "stl")
        XCTAssertEqual(ExtendedSubtitleFormat.scc.fileExtension, "scc")
        XCTAssertEqual(ExtendedSubtitleFormat.pgs.fileExtension, "sup")
        XCTAssertTrue(ExtendedSubtitleFormat.pgs.isBitmap)
        XCTAssertTrue(ExtendedSubtitleFormat.vobsub.isBitmap)
        XCTAssertTrue(ExtendedSubtitleFormat.ebuSTL.isText)
        XCTAssertTrue(ExtendedSubtitleFormat.scc.isText)
    }

    /// Verifies subtitle display names.
    func test_extendedSubtitle_displayNames() {
        XCTAssertTrue(ExtendedSubtitleFormat.ebuSTL.displayName.contains("EBU"))
        XCTAssertTrue(ExtendedSubtitleFormat.scc.displayName.contains("SCC"))
        XCTAssertTrue(ExtendedSubtitleFormat.ttml.displayName.contains("TTML"))
    }

    /// Verifies subtitle conversion paths.
    func test_subtitleConversionPath_canConvert() {
        // Text-to-text: yes
        XCTAssertTrue(SubtitleConversionPath.canConvert(from: .ebuSTL, to: .scc))
        XCTAssertTrue(SubtitleConversionPath.canConvert(from: .scc, to: .ttml))

        // Bitmap-to-text: no (needs OCR)
        XCTAssertFalse(SubtitleConversionPath.canConvert(from: .pgs, to: .scc))
        XCTAssertTrue(SubtitleConversionPath.needsOCR(from: .pgs, to: .scc))

        // Text-to-bitmap: no
        XCTAssertFalse(SubtitleConversionPath.canConvert(from: .scc, to: .pgs))
    }

    /// Verifies subtitle extraction arguments.
    func test_extendedSubtitleBuilder_extract() {
        let args = ExtendedSubtitleBuilder.buildExtractArguments(
            inputPath: "/tmp/movie.mkv",
            outputPath: "/tmp/subs.srt",
            streamIndex: 1
        )
        XCTAssertTrue(args.contains("0:s:1"))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies SCC embed arguments.
    func test_extendedSubtitleBuilder_sccEmbed() {
        let args = ExtendedSubtitleBuilder.buildSCCEmbedArguments(
            inputPath: "/tmp/movie.mp4",
            sccPath: "/tmp/captions.scc",
            outputPath: "/tmp/output.mp4"
        )
        XCTAssertTrue(args.contains("/tmp/captions.scc"))
        XCTAssertTrue(args.contains("mov_text"))
    }

    /// Verifies teletext extraction arguments.
    func test_extendedSubtitleBuilder_teletext() {
        let args = ExtendedSubtitleBuilder.buildTeletextExtractArguments(
            inputPath: "/tmp/broadcast.ts",
            outputPath: "/tmp/subs.srt",
            teletextPage: 888
        )
        XCTAssertTrue(args.contains("-txt_page"))
        XCTAssertTrue(args.contains("888"))
        XCTAssertTrue(args.contains("srt"))
    }

    /// Verifies burn-in filter.
    func test_extendedSubtitleBuilder_burnIn() {
        let filter = ExtendedSubtitleBuilder.buildBurnInFilter(streamIndex: 0)
        XCTAssertTrue(filter.contains("subtitles"))
    }

    /// Verifies bitmap overlay filter.
    func test_extendedSubtitleBuilder_bitmapOverlay() {
        let filter = ExtendedSubtitleBuilder.buildBitmapOverlayFilter(streamIndex: 1)
        XCTAssertTrue(filter.contains("overlay"))
        XCTAssertTrue(filter.contains("[0:s:1]"))
    }

    // =========================================================================
    // MARK: - Phase 3.21-22: Extended Audio Codecs
    // =========================================================================

    /// Verifies ExtendedAudioCodecType properties.
    func test_extendedAudioCodec_properties() {
        XCTAssertTrue(ExtendedAudioCodecType.dtsxIMAX.isImmersive)
        XCTAssertTrue(ExtendedAudioCodecType.iamf.isImmersive)
        XCTAssertTrue(ExtendedAudioCodecType.mp3surround.isImmersive)
        XCTAssertFalse(ExtendedAudioCodecType.amrNB.isImmersive)
        XCTAssertTrue(ExtendedAudioCodecType.wmaLossless.isLossless)
        XCTAssertTrue(ExtendedAudioCodecType.mp3hd.isLossless)
    }

    /// Verifies encode/decode capabilities.
    func test_extendedAudioCodec_capabilities() {
        XCTAssertTrue(ExtendedAudioCodecType.amrNB.canEncode)
        XCTAssertTrue(ExtendedAudioCodecType.amrNB.canDecode)
        XCTAssertTrue(ExtendedAudioCodecType.speex.canEncode)
        XCTAssertFalse(ExtendedAudioCodecType.dtsxIMAX.canEncode)
        XCTAssertTrue(ExtendedAudioCodecType.dtsxIMAX.canDecode)
        XCTAssertFalse(ExtendedAudioCodecType.iamf.canDecode)
    }

    /// Verifies channel counts.
    func test_extendedAudioCodec_channels() {
        XCTAssertEqual(ExtendedAudioCodecType.amrNB.maxChannels, 1)
        XCTAssertEqual(ExtendedAudioCodecType.mp3surround.maxChannels, 6)
        XCTAssertEqual(ExtendedAudioCodecType.dtsxIMAX.maxChannels, 32)
    }

    /// Verifies AMR-NB encoding arguments.
    func test_extendedAudioCodecBuilder_amrNB() {
        let args = ExtendedAudioCodecBuilder.buildAMRNBEncodeArguments(
            inputPath: "/tmp/voice.wav",
            outputPath: "/tmp/voice.amr"
        )
        XCTAssertTrue(args.contains("libopencore_amrnb"))
        XCTAssertTrue(args.contains("8000"))
        XCTAssertTrue(args.contains("1"))
    }

    /// Verifies AMR-WB encoding arguments.
    func test_extendedAudioCodecBuilder_amrWB() {
        let args = ExtendedAudioCodecBuilder.buildAMRWBEncodeArguments(
            inputPath: "/tmp/voice.wav",
            outputPath: "/tmp/voice.3gp"
        )
        XCTAssertTrue(args.contains("libvo_amrwbenc"))
        XCTAssertTrue(args.contains("16000"))
    }

    /// Verifies Speex encoding arguments.
    func test_extendedAudioCodecBuilder_speex() {
        let args = ExtendedAudioCodecBuilder.buildSpeexEncodeArguments(
            inputPath: "/tmp/voice.wav",
            outputPath: "/tmp/voice.ogg"
        )
        XCTAssertTrue(args.contains("libspeex"))
        XCTAssertTrue(args.contains("16000"))
    }

    /// Verifies DTS:X passthrough arguments.
    func test_extendedAudioCodecBuilder_dtsxPassthrough() {
        let args = ExtendedAudioCodecBuilder.buildDTSXPassthroughArguments(
            inputPath: "/tmp/imax.mkv",
            outputPath: "/tmp/output.mkv"
        )
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies extended codec detection.
    func test_extendedAudioCodecBuilder_detect() {
        XCTAssertEqual(ExtendedAudioCodecBuilder.detectExtendedCodec("wmapro"), .wmaPro)
        XCTAssertEqual(ExtendedAudioCodecBuilder.detectExtendedCodec("amrnb"), .amrNB)
        XCTAssertEqual(ExtendedAudioCodecBuilder.detectExtendedCodec("speex"), .speex)
        XCTAssertNil(ExtendedAudioCodecBuilder.detectExtendedCodec("aac"))
    }

    /// Verifies transcode arguments.
    func test_extendedAudioCodecBuilder_transcode() {
        let args = ExtendedAudioCodecBuilder.buildTranscodeArguments(
            inputPath: "/tmp/wma.wmv",
            outputPath: "/tmp/output.m4a",
            targetCodec: "aac",
            bitrate: 256,
            channels: 2
        )
        XCTAssertTrue(args.contains("aac"))
        XCTAssertTrue(args.contains("256k"))
        XCTAssertTrue(args.contains("-ac"))
        XCTAssertTrue(args.contains("2"))
    }

}
