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
    // MARK: - ManifestGenerator Tests
    // -----------------------------------------------------------------

    /// Verifies default variant ladder has expected entries.
    func test_manifestGenerator_defaultLadder() {
        let ladder = StreamingVariant.defaultLadder
        XCTAssertEqual(ladder.count, 4)
        XCTAssertEqual(ladder[0].label, "1080p")
        XCTAssertEqual(ladder[0].width, 1920)
        XCTAssertEqual(ladder[0].height, 1080)
        XCTAssertEqual(ladder[3].label, "360p")
    }

    /// Verifies 4K UHD ladder.
    func test_manifestGenerator_uhdLadder() {
        let ladder = StreamingVariant.uhdrLadder
        XCTAssertEqual(ladder[0].label, "2160p")
        XCTAssertEqual(ladder[0].width, 3840)
        XCTAssertGreaterThan(ladder[0].videoBitrate, ladder[1].videoBitrate)
    }

    /// Verifies HLS variant arguments are generated correctly.
    func test_manifestGenerator_hlsVariantArguments() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")
        let config = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/"),
            format: .hls
        )
        let args = generator.buildVariantArguments(config: config, variant: StreamingVariant.defaultLadder[0], variantIndex: 0)
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-f hls"))
        XCTAssertTrue(argStr.contains("-hls_time"))
        XCTAssertTrue(argStr.contains("-s 1920x1080"))
        XCTAssertTrue(argStr.contains("libx264"))
    }

    /// Verifies DASH variant arguments.
    func test_manifestGenerator_dashVariantArguments() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")
        let config = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/"),
            format: .dash
        )
        let args = generator.buildVariantArguments(config: config, variant: StreamingVariant.defaultLadder[0], variantIndex: 0)
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-f dash"))
        XCTAssertTrue(argStr.contains("-seg_duration"))
    }

    /// Verifies master HLS playlist generation.
    func test_manifestGenerator_masterPlaylist() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")
        let config = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/")
        )
        let playlist = generator.buildMasterPlaylist(config: config)

        XCTAssertTrue(playlist.contains("#EXTM3U"))
        XCTAssertTrue(playlist.contains("#EXT-X-STREAM-INF"))
        XCTAssertTrue(playlist.contains("RESOLUTION=1920x1080"))
        XCTAssertTrue(playlist.contains("RESOLUTION=1280x720"))
        XCTAssertTrue(playlist.contains("v0_1080p/playlist.m3u8"))
    }

    /// Verifies DASH MPD manifest generation.
    func test_manifestGenerator_dashManifest() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")
        let config = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/"),
            format: .dash
        )
        let mpd = generator.buildDASHManifest(config: config)

        XCTAssertTrue(mpd.contains("<?xml"))
        XCTAssertTrue(mpd.contains("<MPD"))
        XCTAssertTrue(mpd.contains("Representation"))
        XCTAssertTrue(mpd.contains("width=\"1920\""))
    }

    /// Verifies manifest config validation.
    func test_manifestGenerator_validation() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")

        // Valid config
        let validConfig = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/")
        )
        let validIssues = generator.validate(config: validConfig)
        XCTAssertTrue(validIssues.isEmpty, "Default config should be valid")

        // Empty variants
        let emptyConfig = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/"),
            variants: []
        )
        let emptyIssues = generator.validate(config: emptyConfig)
        XCTAssertTrue(emptyIssues.contains { $0.contains("No variants") })
    }

    // -----------------------------------------------------------------
    // MARK: - EncodingProfile New Properties Tests
    // -----------------------------------------------------------------

    /// Verifies new tone mapping parameters exist and round-trip.
    func test_profile_toneMapParameters() throws {
        var profile = EncodingProfile(name: "Test TM")
        profile.toneMapToSDR = true
        profile.toneMapAlgorithm = "hable"
        profile.toneMapPeakNits = 1000.0
        profile.toneMapDesaturation = 0.5

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: data)

        XCTAssertEqual(decoded.toneMapPeakNits, 1000.0)
        XCTAssertEqual(decoded.toneMapDesaturation, 0.5)
    }

    /// Verifies displayAspectRatio round-trips.
    func test_profile_displayAspectRatio() throws {
        var profile = EncodingProfile(name: "Test DAR")
        profile.displayAspectRatio = "16:9"

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: data)

        XCTAssertEqual(decoded.displayAspectRatio, "16:9")
    }

    /// Verifies tone mapping params wire through toArgumentBuilder.
    func test_profile_toneMapParamsWiring() {
        var profile = EncodingProfile(name: "Test Wiring")
        profile.toneMapToSDR = true
        profile.toneMapAlgorithm = "mobius"
        profile.toneMapPeakNits = 4000.0
        profile.toneMapDesaturation = 0.8

        let inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        let builder = profile.toArgumentBuilder(inputURL: inputURL, outputURL: outputURL)

        XCTAssertTrue(builder.toneMap)
        XCTAssertEqual(builder.toneMapAlgorithm, .mobius)
        XCTAssertEqual(builder.toneMapPeakNits, 4000.0)
        XCTAssertEqual(builder.toneMapDesaturation, 0.8)
    }

    /// Verifies displayAspectRatio wires through toArgumentBuilder.
    func test_profile_displayAspectRatioWiring() {
        var profile = EncodingProfile(name: "Test DAR Wiring")
        profile.displayAspectRatio = "2.35:1"

        let inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        let builder = profile.toArgumentBuilder(inputURL: inputURL, outputURL: outputURL)

        XCTAssertEqual(builder.displayAspectRatio, "2.35:1")
    }

    // -----------------------------------------------------------------
    // MARK: - AudioProcessor Tests (Phase 5)
    // -----------------------------------------------------------------

    /// Verifies EBU R128 loudnorm filter generation.
    func test_audioProcessor_ebuR128Filter() {
        let filter = AudioProcessor.buildLoudnormFilter(standard: .ebuR128)
        XCTAssertTrue(filter.contains("loudnorm"))
        XCTAssertTrue(filter.contains("I=-23"))
        XCTAssertTrue(filter.contains("TP=-1"))
        XCTAssertTrue(filter.contains("LRA=20"))
        XCTAssertTrue(filter.contains("linear=true"))
    }

    /// Verifies streaming loudness standard.
    func test_audioProcessor_streamingFilter() {
        let filter = AudioProcessor.buildLoudnormFilter(standard: .streaming)
        XCTAssertTrue(filter.contains("I=-14"))
    }

    /// Verifies podcast loudness standard.
    func test_audioProcessor_podcastFilter() {
        let filter = AudioProcessor.buildLoudnormFilter(standard: .podcast)
        XCTAssertTrue(filter.contains("I=-16"))
    }

    /// Verifies two-pass measurement injection.
    func test_audioProcessor_twoPassMeasurement() {
        let measurement = LoudnessMeasurement(
            integratedLUFS: -25.0,
            truePeakDBTP: -0.5,
            loudnessRangeLU: 15.0
        )
        let filter = AudioProcessor.buildLoudnormFilter(
            standard: .ebuR128,
            measurement: measurement
        )
        XCTAssertTrue(filter.contains("measured_I=-25"))
        XCTAssertTrue(filter.contains("measured_TP=-0.5"))
        XCTAssertTrue(filter.contains("measured_LRA=15"))
    }

    /// Verifies analysis pass arguments.
    func test_audioProcessor_analysisPass() {
        let args = AudioProcessor.buildAnalysisPassArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv")
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-af loudnorm"))
        XCTAssertTrue(argStr.contains("-f null"))
        XCTAssertTrue(argStr.contains("/dev/null"))
    }

    /// Verifies ReplayGain analysis arguments.
    func test_audioProcessor_replayGainAnalysis() {
        let args = AudioProcessor.buildReplayGainAnalysisArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.flac")
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-af replaygain"))
        XCTAssertTrue(argStr.contains("-f null"))
    }

    /// Verifies ReplayGain volume filter.
    func test_audioProcessor_replayGainApply() {
        let filter = AudioProcessor.buildReplayGainApplyFilter(gainDB: -3.5)
        XCTAssertTrue(filter.contains("volume=-3.5dB"))
        XCTAssertTrue(filter.contains("alimiter"), "Should include peak limiter")
    }

    /// Verifies peak limiter filter.
    func test_audioProcessor_peakLimiter() {
        let filter = AudioProcessor.buildPeakLimiterFilter(limitDBTP: -1.0)
        XCTAssertTrue(filter.contains("alimiter"))
        XCTAssertTrue(filter.contains("limit="))
    }

    /// Verifies combined processing chain.
    func test_audioProcessor_combinedChain() {
        let chain = AudioProcessor.buildProcessingChain(
            normalize: true,
            standard: .ebuR128,
            limit: true
        )
        XCTAssertNotNil(chain)
        XCTAssertTrue(chain!.contains("loudnorm"))
    }

    /// Verifies LoudnessStandard properties.
    func test_loudnessStandard_properties() {
        XCTAssertEqual(LoudnessStandard.ebuR128.targetLUFS, -23.0)
        XCTAssertEqual(LoudnessStandard.atscA85.targetLUFS, -24.0)
        XCTAssertEqual(LoudnessStandard.streaming.targetLUFS, -14.0)
        XCTAssertEqual(LoudnessStandard.podcast.targetLUFS, -16.0)
        XCTAssertEqual(LoudnessStandard.ebuR128.targetTruePeak, -1.0)
        XCTAssertEqual(LoudnessStandard.atscA85.targetTruePeak, -2.0)
    }

    // -----------------------------------------------------------------
    // MARK: - SubtitleConverter Tests (Phase 5)
    // -----------------------------------------------------------------

    /// Verifies text subtitle conversion arguments.
    func test_subtitleConverter_textConversion() {
        let args = SubtitleConverter.buildTextConversionArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.srt"),
            inputFormat: .ssa,
            outputFormat: .srt
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-c:s srt"))
        XCTAssertTrue(argStr.contains("-map 0:s:0"))
    }

    /// Verifies subtitle extraction arguments.
    func test_subtitleConverter_extraction() {
        let args = SubtitleConverter.buildExtractionArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/subs.vtt"),
            streamIndex: 2,
            outputFormat: .webVTT
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-map 0:s:2"))
        XCTAssertTrue(argStr.contains("-c:s webvtt"))
        XCTAssertTrue(argStr.contains("-vn"))
        XCTAssertTrue(argStr.contains("-an"))
    }

    /// Verifies burn-in filter generation.
    func test_subtitleConverter_burnIn() {
        let filter = SubtitleConverter.buildBurnInFilter(
            subtitlePath: "/tmp/subs.srt",
            fontSize: 24,
            fontName: "Arial"
        )
        XCTAssertTrue(filter.contains("subtitles="))
        XCTAssertTrue(filter.contains("FontSize=24"))
        XCTAssertTrue(filter.contains("FontName=Arial"))
    }

    /// Verifies conversion matrix.
    func test_subtitleConverter_conversionMatrix() {
        XCTAssertTrue(SubtitleConverter.canConvert(from: .srt, to: .webVTT))
        XCTAssertTrue(SubtitleConverter.canConvert(from: .ssa, to: .srt))
        XCTAssertTrue(SubtitleConverter.canConvert(from: .pgs, to: .srt)) // OCR
        XCTAssertFalse(SubtitleConverter.canConvert(from: .srt, to: .pgs)) // Can't create bitmap
    }

    /// Verifies OCR requirement detection.
    func test_subtitleConverter_ocrRequired() {
        XCTAssertTrue(SubtitleConverter.requiresOCR(from: .pgs, to: .srt))
        XCTAssertTrue(SubtitleConverter.requiresOCR(from: .vobSub, to: .webVTT))
        XCTAssertFalse(SubtitleConverter.requiresOCR(from: .srt, to: .webVTT))
    }

    /// Verifies FFmpeg codec mapping.
    func test_subtitleConverter_codecMapping() {
        XCTAssertEqual(SubtitleConverter.ffmpegSubtitleCodec(for: .srt), "srt")
        XCTAssertEqual(SubtitleConverter.ffmpegSubtitleCodec(for: .webVTT), "webvtt")
        XCTAssertEqual(SubtitleConverter.ffmpegSubtitleCodec(for: .ssa), "ass")
        XCTAssertEqual(SubtitleConverter.ffmpegSubtitleCodec(for: .pgs), "hdmv_pgs_subtitle")
    }

    // -----------------------------------------------------------------
    // MARK: - Streaming Enhancements Tests (Phase 6)
    // -----------------------------------------------------------------

    /// Verifies HLS encryption key generation.
    func test_hlsEncryption_keyGeneration() {
        let (hex, bytes) = HLSEncryption.generateKey()
        XCTAssertEqual(hex.count, 32, "Hex key should be 32 characters (16 bytes)")
        XCTAssertEqual(bytes.count, 16, "Key should be 16 bytes")
    }

    /// Verifies Data hex string initializer.
    func test_data_hexInit() {
        let data = Data(hexString: "48656c6c6f")
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 5)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")

        let invalid = Data(hexString: "xyz")
        XCTAssertNil(invalid)
    }

    /// Verifies thumbnail extraction arguments.
    func test_thumbnailSprite_extractionArgs() {
        let config = ThumbnailSpriteGenerator.Config(intervalSeconds: 10.0)
        let args = ThumbnailSpriteGenerator.buildExtractionArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputPattern: "/tmp/thumb_%04d.jpg",
            config: config
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-vf"))
        XCTAssertTrue(argStr.contains("fps="))
        XCTAssertTrue(argStr.contains("scale=160:90"))
        XCTAssertTrue(argStr.contains("-an"))
    }

    /// Verifies sprite sheet arguments.
    func test_thumbnailSprite_spriteSheetArgs() {
        let args = ThumbnailSpriteGenerator.buildSpriteSheetArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputPath: "/tmp/sprites.jpg"
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("tile="))
        XCTAssertTrue(argStr.contains("-frames:v 1"))
    }

    /// Verifies WebVTT thumbnail map generation.
    func test_thumbnailSprite_webVTT() {
        let config = ThumbnailSpriteGenerator.Config(
            intervalSeconds: 10.0,
            thumbnailWidth: 160,
            thumbnailHeight: 90,
            columns: 10
        )
        let vtt = ThumbnailSpriteGenerator.buildWebVTT(
            spriteURL: "sprites.jpg",
            config: config,
            totalDuration: 30.0
        )
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
        XCTAssertTrue(vtt.contains("sprites.jpg#xywh="))
        XCTAssertTrue(vtt.contains("00:00:00.000"))
    }

    /// Verifies streaming presets exist and have valid settings.
    func test_streamingPresets_exist() {
        let presets = StreamingPreset.builtInPresets
        XCTAssertEqual(presets.count, 5)

        for preset in presets {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertFalse(preset.variants.isEmpty)
            XCTAssertGreaterThan(preset.segmentDuration, 0)
            XCTAssertGreaterThan(preset.keyframeInterval, 0)
        }
    }

    /// Verifies Apple HLS preset settings.
    func test_streamingPresets_appleHLS() {
        let preset = StreamingPreset.appleHLS
        XCTAssertEqual(preset.format, .hls)
        XCTAssertEqual(preset.videoCodec, .h264)
        XCTAssertEqual(preset.audioCodec, .aacLC)
        XCTAssertEqual(preset.segmentDuration, 6.0)
    }

    /// Verifies YouTube-like preset uses AV1.
    func test_streamingPresets_youtube() {
        let preset = StreamingPreset.youtubeLike
        XCTAssertEqual(preset.videoCodec, .av1)
        XCTAssertEqual(preset.audioCodec, .opus)
    }

    /// Verifies Netflix-like preset has HDR settings.
    func test_streamingPresets_netflix() {
        let preset = StreamingPreset.netflixLike
        XCTAssertEqual(preset.videoCodec, .h265)
        XCTAssertEqual(preset.pixelFormat, "yuv420p10le")
        XCTAssertEqual(preset.format, .cmaf)
    }

    /// Verifies preset to ManifestConfig conversion.
    func test_streamingPreset_toManifestConfig() {
        let config = StreamingPreset.appleHLS.toManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/")
        )
        XCTAssertEqual(config.format, .hls)
        XCTAssertEqual(config.videoCodec, .h264)
        XCTAssertEqual(config.segmentDuration, 6.0)
        XCTAssertEqual(config.variants.count, StreamingVariant.defaultLadder.count)
    }

    /// Verifies loudness normalization wires into EncodingProfile.
    func test_profile_loudnessNormalization() {
        var profile = EncodingProfile(name: "Test Loudness")
        profile.loudnessNormalization = "ebu_r128"
        profile.applyPeakLimiter = true

        let builder = profile.toArgumentBuilder(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4")
        )

        XCTAssertNotNil(builder.audioFilterChain)
        XCTAssertTrue(builder.audioFilterChain?.contains("loudnorm") ?? false)
    }

}
