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
    // -----------------------------------------------------------------
    // MARK: - Phase 7: Spatial Audio Codecs
    // -----------------------------------------------------------------

    /// Verifies new spatial audio codecs exist and have correct display names.
    func test_spatialAudioCodecs_displayNames() {
        XCTAssertEqual(AudioCodec.dolbyMAT.displayName, "Dolby MAT (Atmos)")
        XCTAssertEqual(AudioCodec.iamf.displayName, "IAMF (Eclipsa Audio)")
        XCTAssertEqual(AudioCodec.mpegH3D.displayName, "MPEG-H 3D Audio")
        XCTAssertEqual(AudioCodec.sonyRA.displayName, "360 Reality Audio")
        XCTAssertEqual(AudioCodec.ambisonics.displayName, "Ambisonics (FOA/HOA)")
        XCTAssertEqual(AudioCodec.auro3D.displayName, "Auro-3D")
        XCTAssertEqual(AudioCodec.nhk222.displayName, "NHK 22.2")
        XCTAssertEqual(AudioCodec.ac4AJOC.displayName, "Dolby AC-4 A-JOC")
        XCTAssertEqual(AudioCodec.mp3Surround.displayName, "MP3 Surround")
        XCTAssertEqual(AudioCodec.imaxEnhanced.displayName, "IMAX Enhanced (DTS:X)")
    }

    /// Verifies spatial audio codecs are passthrough-only (no FFmpeg encoder).
    func test_spatialAudioCodecs_passthroughOnly() {
        let spatialCodecs: [AudioCodec] = [
            .dolbyMAT, .iamf, .mpegH3D, .sonyRA, .asaf,
            .ambisonics, .auro3D, .nhk222, .ac4AJOC, .mp3Surround, .imaxEnhanced
        ]
        for codec in spatialCodecs {
            XCTAssertNil(codec.ffmpegEncoder, "\(codec.rawValue) should be passthrough-only")
        }
    }

    /// Verifies the isSpatial computed property.
    func test_spatialAudioCodecs_isSpatialProperty() {
        XCTAssertTrue(AudioCodec.dolbyMAT.isSpatial)
        XCTAssertTrue(AudioCodec.iamf.isSpatial)
        XCTAssertTrue(AudioCodec.ambisonics.isSpatial)
        XCTAssertTrue(AudioCodec.nhk222.isSpatial)
        XCTAssertFalse(AudioCodec.aacLC.isSpatial)
        XCTAssertFalse(AudioCodec.flac.isSpatial)
    }

    /// Verifies the isObjectBased computed property.
    func test_spatialAudioCodecs_isObjectBasedProperty() {
        XCTAssertTrue(AudioCodec.dolbyMAT.isObjectBased)
        XCTAssertTrue(AudioCodec.iamf.isObjectBased)
        XCTAssertTrue(AudioCodec.mpegH3D.isObjectBased)
        XCTAssertTrue(AudioCodec.ac4AJOC.isObjectBased)
        XCTAssertFalse(AudioCodec.ambisonics.isObjectBased)
        XCTAssertFalse(AudioCodec.nhk222.isObjectBased)
        XCTAssertFalse(AudioCodec.aacLC.isObjectBased)
    }

    /// Verifies maxChannels for spatial codecs.
    func test_spatialAudioCodecs_maxChannels() {
        XCTAssertEqual(AudioCodec.nhk222.maxChannels, 24)
        XCTAssertEqual(AudioCodec.ambisonics.maxChannels, 64)
        XCTAssertEqual(AudioCodec.auro3D.maxChannels, 14)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: SpatialAudioFormat
    // -----------------------------------------------------------------

    /// Verifies SpatialAudioFormat raw values.
    func test_spatialAudioFormat_rawValues() {
        XCTAssertEqual(SpatialAudioFormat.channelBased.rawValue, "channel")
        XCTAssertEqual(SpatialAudioFormat.objectBased.rawValue, "object")
        XCTAssertEqual(SpatialAudioFormat.sceneBased.rawValue, "scene")
        XCTAssertEqual(SpatialAudioFormat.hybrid.rawValue, "hybrid")
    }

    /// Verifies SpatialAudioFormat CaseIterable conformance.
    func test_spatialAudioFormat_allCases() {
        XCTAssertEqual(SpatialAudioFormat.allCases.count, 4)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: AmbisonicsOrder
    // -----------------------------------------------------------------

    /// Verifies Ambisonics channel count formula: (order+1)².
    func test_ambisonicsOrder_channelCount() {
        XCTAssertEqual(AmbisonicsOrder.first.channelCount, 4)    // (1+1)² = 4
        XCTAssertEqual(AmbisonicsOrder.second.channelCount, 9)   // (2+1)² = 9
        XCTAssertEqual(AmbisonicsOrder.third.channelCount, 16)   // (3+1)² = 16
        XCTAssertEqual(AmbisonicsOrder.fourth.channelCount, 25)  // (4+1)² = 25
        XCTAssertEqual(AmbisonicsOrder.fifth.channelCount, 36)   // (5+1)² = 36
        XCTAssertEqual(AmbisonicsOrder.seventh.channelCount, 64) // (7+1)² = 64
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: StereoMode3D
    // -----------------------------------------------------------------

    /// Verifies StereoMode3D display names.
    func test_stereoMode3D_displayNames() {
        XCTAssertEqual(StereoMode3D.mono.displayName, "2D (Mono)")
        XCTAssertEqual(StereoMode3D.sideBySide.displayName, "Side-by-Side")
        XCTAssertEqual(StereoMode3D.topBottom.displayName, "Top-and-Bottom")
        XCTAssertEqual(StereoMode3D.multiview.displayName, "Multiview (MV-HEVC/MVC)")
        XCTAssertEqual(StereoMode3D.anaglyph.displayName, "Anaglyph")
    }

    /// Verifies isMultiStream is true only for multiview.
    func test_stereoMode3D_isMultiStream() {
        XCTAssertTrue(StereoMode3D.multiview.isMultiStream)
        XCTAssertFalse(StereoMode3D.sideBySide.isMultiStream)
        XCTAssertFalse(StereoMode3D.topBottom.isMultiStream)
        XCTAssertFalse(StereoMode3D.mono.isMultiStream)
    }

    /// Verifies StereoMode3D CaseIterable conformance.
    func test_stereoMode3D_allCases() {
        XCTAssertEqual(StereoMode3D.allCases.count, 9)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: Video3DMetadata
    // -----------------------------------------------------------------

    /// Verifies Video3DMetadata default initialization.
    func test_video3DMetadata_defaults() {
        let meta = Video3DMetadata()
        XCTAssertEqual(meta.stereoMode, .mono)
        XCTAssertNil(meta.viewIndex)
        XCTAssertNil(meta.viewCount)
        XCTAssertFalse(meta.viewsSwapped)
        XCTAssertNil(meta.baselineDistance)
    }

    /// Verifies Video3DMetadata custom initialization.
    func test_video3DMetadata_customInit() {
        let meta = Video3DMetadata(
            stereoMode: .sideBySide,
            viewIndex: 0,
            viewCount: 2,
            viewsSwapped: true,
            baselineDistance: 63.5
        )
        XCTAssertEqual(meta.stereoMode, .sideBySide)
        XCTAssertEqual(meta.viewIndex, 0)
        XCTAssertEqual(meta.viewCount, 2)
        XCTAssertTrue(meta.viewsSwapped)
        XCTAssertEqual(meta.baselineDistance, 63.5)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: SpatialAudioMetadata
    // -----------------------------------------------------------------

    /// Verifies SpatialAudioMetadata default initialization.
    func test_spatialAudioMetadata_defaults() {
        let meta = SpatialAudioMetadata()
        XCTAssertEqual(meta.format, .channelBased)
        XCTAssertNil(meta.ambisonicsOrder)
        XCTAssertNil(meta.ambisonicsNorm)
        XCTAssertNil(meta.objectCount)
        XCTAssertNil(meta.bedChannels)
        XCTAssertFalse(meta.hasHeightChannels)
        XCTAssertFalse(meta.binauralRendering)
    }

    /// Verifies SpatialAudioMetadata scene-based initialization.
    func test_spatialAudioMetadata_sceneBased() {
        let meta = SpatialAudioMetadata(
            format: .sceneBased,
            ambisonicsOrder: .third,
            ambisonicsNorm: .sn3d
        )
        XCTAssertEqual(meta.format, .sceneBased)
        XCTAssertEqual(meta.ambisonicsOrder, .third)
        XCTAssertEqual(meta.ambisonicsNorm, .sn3d)
    }

    /// Verifies SpatialAudioMetadata hybrid initialization.
    func test_spatialAudioMetadata_hybrid() {
        let meta = SpatialAudioMetadata(
            format: .hybrid,
            objectCount: 118,
            bedChannels: 12,
            hasHeightChannels: true,
            binauralRendering: true
        )
        XCTAssertEqual(meta.format, .hybrid)
        XCTAssertEqual(meta.objectCount, 118)
        XCTAssertEqual(meta.bedChannels, 12)
        XCTAssertTrue(meta.hasHeightChannels)
        XCTAssertTrue(meta.binauralRendering)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: SpatialAudioConverter
    // -----------------------------------------------------------------

    /// Verifies Ambisonics encode filter output.
    func test_spatialAudioConverter_ambisonicsEncodeFilter() {
        let filter = SpatialAudioConverter.buildAmbisonicsEncodeFilter(
            order: .first, normalization: .sn3d
        )
        XCTAssertTrue(filter.contains("pan=4c"))
    }

    /// Verifies Ambisonics encode filter with third order (16 channels).
    func test_spatialAudioConverter_ambisonicsEncodeThirdOrder() {
        let filter = SpatialAudioConverter.buildAmbisonicsEncodeFilter(
            order: .third, normalization: .n3d
        )
        XCTAssertTrue(filter.contains("pan=16c"))
    }

    /// Verifies binaural downmix filter uses sofalizer.
    func test_spatialAudioConverter_binauralDownmix() {
        let filter = SpatialAudioConverter.buildBinauralDownmixFilter()
        XCTAssertTrue(filter.contains("sofalizer"))
        XCTAssertTrue(filter.contains("hrtf.sofa"))
    }

    /// Verifies Dolby MAT passthrough arguments.
    func test_spatialAudioConverter_matPassthrough() {
        let args = SpatialAudioConverter.buildMATPassthroughArguments()
        XCTAssertTrue(args.contains("-c:a"))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies channel layout conversion downmix.
    func test_spatialAudioConverter_channelLayoutDownmix() {
        let filter = SpatialAudioConverter.buildChannelLayoutConversion(from: 8, to: 2)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("pan=2c"))
    }

    /// Verifies channel layout conversion upmix.
    func test_spatialAudioConverter_channelLayoutUpmix() {
        let filter = SpatialAudioConverter.buildChannelLayoutConversion(from: 2, to: 6)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("5.1"))
    }

    /// Verifies no conversion when channel counts match.
    func test_spatialAudioConverter_noConversionNeeded() {
        let filter = SpatialAudioConverter.buildChannelLayoutConversion(from: 6, to: 6)
        XCTAssertNil(filter)
    }

    /// Verifies channel layout strings for standard configurations.
    func test_spatialAudioConverter_channelLayoutStrings() {
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 1), "mono")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 2), "stereo")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 6), "5.1")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 8), "7.1")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 12), "7.1.4")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 24), "22.2")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 3), "3c")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: Video3DConverter
    // -----------------------------------------------------------------

    /// Verifies SBS to TB conversion filter.
    func test_video3DConverter_sbsToTB() {
        let filter = Video3DConverter.buildConversionFilter(from: .sideBySide, to: .topBottom)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("stereo3d=sbsl:abl"))
    }

    /// Verifies TB to SBS conversion filter.
    func test_video3DConverter_tbToSBS() {
        let filter = Video3DConverter.buildConversionFilter(from: .topBottom, to: .sideBySide)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("stereo3d=abl:sbsl"))
    }

    /// Verifies 3D to mono (left view extraction).
    func test_video3DConverter_3dToMono() {
        let filter = Video3DConverter.buildConversionFilter(from: .sideBySide, to: .mono)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("stereo3d="))
        XCTAssertTrue(filter!.contains(":ml"))
    }

    /// Verifies SBS to anaglyph conversion.
    func test_video3DConverter_sbsToAnaglyph() {
        let filter = Video3DConverter.buildConversionFilter(from: .sideBySide, to: .anaglyph)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("arcg"))
    }

    /// Verifies no conversion when modes match.
    func test_video3DConverter_noConversionNeeded() {
        let filter = Video3DConverter.buildConversionFilter(from: .sideBySide, to: .sideBySide)
        XCTAssertNil(filter)
    }

    /// Verifies 3D metadata arguments for SBS.
    func test_video3DConverter_metadataArgsSBS() {
        let meta = Video3DMetadata(stereoMode: .sideBySide)
        let args = Video3DConverter.buildMetadataArguments(metadata: meta)
        XCTAssertTrue(args.contains("-metadata:s:v:0"))
        XCTAssertTrue(args.contains("stereo_mode=side_by_side"))
    }

    /// Verifies 3D metadata arguments for top-bottom.
    func test_video3DConverter_metadataArgsTB() {
        let meta = Video3DMetadata(stereoMode: .topBottom)
        let args = Video3DConverter.buildMetadataArguments(metadata: meta)
        XCTAssertTrue(args.contains("stereo_mode=top_bottom"))
    }

    /// Verifies no metadata for mono mode.
    func test_video3DConverter_metadataArgsMono() {
        let meta = Video3DMetadata(stereoMode: .mono)
        let args = Video3DConverter.buildMetadataArguments(metadata: meta)
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies AmbisonicsNormalization raw values.
    func test_ambisonicsNormalization_rawValues() {
        XCTAssertEqual(AmbisonicsNormalization.sn3d.rawValue, "sn3d")
        XCTAssertEqual(AmbisonicsNormalization.n3d.rawValue, "n3d")
        XCTAssertEqual(AmbisonicsNormalization.fuma.rawValue, "fuma")
    }

}
