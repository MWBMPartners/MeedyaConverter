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
    // MARK: - Phase 7.10: Watch Folder
    // -----------------------------------------------------------------

    /// Verifies WatchFolderConfig default initialization.
    func test_watchFolderConfig_defaults() {
        let config = WatchFolderConfig(name: "Test", watchPath: "/tmp/watch")
        XCTAssertEqual(config.name, "Test")
        XCTAssertEqual(config.watchPath, "/tmp/watch")
        XCTAssertNil(config.outputPath)
        XCTAssertEqual(config.profileName, "webStandard")
        XCTAssertTrue(config.fileExtensions.isEmpty)
        XCTAssertFalse(config.recursive)
        XCTAssertEqual(config.postAction, .leaveInPlace)
        XCTAssertEqual(config.concurrencyLimit, 1)
        XCTAssertTrue(config.isActive)
    }

    /// Verifies effective output path defaults to sibling "output" folder.
    func test_watchFolderConfig_effectiveOutputPath() {
        let config = WatchFolderConfig(name: "Test", watchPath: "/tmp/watch")
        XCTAssertTrue(config.effectiveOutputPath.contains("output"))

        let custom = WatchFolderConfig(
            name: "Test", watchPath: "/tmp/watch", outputPath: "/tmp/encoded"
        )
        XCTAssertEqual(custom.effectiveOutputPath, "/tmp/encoded")
    }

    /// Verifies file extension filtering.
    func test_watchFolderConfig_shouldProcess() {
        let config = WatchFolderConfig(name: "Test", watchPath: "/tmp/watch")

        // Default extensions — accepts common media files
        XCTAssertTrue(config.shouldProcess(filename: "movie.mkv"))
        XCTAssertTrue(config.shouldProcess(filename: "audio.flac"))
        XCTAssertTrue(config.shouldProcess(filename: "video.mp4"))
        XCTAssertFalse(config.shouldProcess(filename: "readme.txt"))
        XCTAssertFalse(config.shouldProcess(filename: "image.png"))

        // Hidden files rejected
        XCTAssertFalse(config.shouldProcess(filename: ".DS_Store"))
        XCTAssertFalse(config.shouldProcess(filename: ".hidden.mp4"))

        // System files rejected
        XCTAssertFalse(config.shouldProcess(filename: "Thumbs.db"))
        XCTAssertFalse(config.shouldProcess(filename: "desktop.ini"))
    }

    /// Verifies custom extension filtering.
    func test_watchFolderConfig_customExtensions() {
        let config = WatchFolderConfig(
            name: "Test", watchPath: "/tmp/watch",
            fileExtensions: ["mkv", "avi"]
        )
        XCTAssertTrue(config.shouldProcess(filename: "movie.mkv"))
        XCTAssertTrue(config.shouldProcess(filename: "movie.avi"))
        XCTAssertFalse(config.shouldProcess(filename: "movie.mp4"))
    }

    /// Verifies PostProcessingAction raw values.
    func test_postProcessingAction_rawValues() {
        XCTAssertEqual(PostProcessingAction.leaveInPlace.rawValue, "leave")
        XCTAssertEqual(PostProcessingAction.moveToCompleted.rawValue, "move")
        XCTAssertEqual(PostProcessingAction.deleteSource.rawValue, "delete")
    }

    /// Verifies output path generation.
    func test_fileStabilityChecker_outputPath() {
        let config = WatchFolderConfig(
            name: "Test",
            watchPath: "/tmp/watch",
            outputPath: "/tmp/output"
        )
        let path = FileStabilityChecker.outputPath(
            for: "/tmp/watch/movie.mkv",
            config: config,
            outputExtension: "mp4"
        )
        XCTAssertTrue(path.contains("movie.mp4"))
        XCTAssertTrue(path.contains("/tmp/output"))
    }

    /// Verifies WatchFolderConfig JSON round-trip.
    func test_watchFolderStore_roundTrip() throws {
        let configs = [
            WatchFolderConfig(name: "Folder 1", watchPath: "/tmp/w1"),
            WatchFolderConfig(name: "Folder 2", watchPath: "/tmp/w2", recursive: true),
        ]
        let data = try WatchFolderStore.encode(configs: configs)
        let decoded = try WatchFolderStore.decode(from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "Folder 1")
        XCTAssertEqual(decoded[1].recursive, true)
    }

    /// Verifies WatchFolderStatus construction.
    func test_watchFolderStatus_construction() {
        let status = WatchFolderStatus(
            configId: "abc",
            isMonitoring: true,
            filesProcessed: 5,
            filesQueued: 2,
            filesFailed: 1
        )
        XCTAssertEqual(status.configId, "abc")
        XCTAssertTrue(status.isMonitoring)
        XCTAssertEqual(status.filesProcessed, 5)
        XCTAssertEqual(status.filesQueued, 2)
        XCTAssertEqual(status.filesFailed, 1)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.15: AI Upscaling
    // -----------------------------------------------------------------

    /// Verifies UpscaleModel display names and scale factors.
    func test_upscaleModel_properties() {
        XCTAssertEqual(UpscaleModel.realESRGAN.displayName, "Real-ESRGAN (General)")
        XCTAssertEqual(UpscaleModel.realESRGANAnime.displayName, "Real-ESRGAN (Anime)")
        XCTAssertEqual(UpscaleModel.realESRGAN.defaultScaleFactor, 4)
        XCTAssertEqual(UpscaleModel.waifu2x.defaultScaleFactor, 2)
        XCTAssertTrue(UpscaleModel.realESRGAN.supportedScaleFactors.contains(4))
    }

    /// Verifies UpscaleModel CaseIterable.
    func test_upscaleModel_allCases() {
        XCTAssertEqual(UpscaleModel.allCases.count, 4)
    }

    /// Verifies Real-ESRGAN argument construction.
    func test_aiUpscaler_realESRGANArguments() {
        let config = UpscaleConfig(model: .realESRGAN, scaleFactor: 4, tileSize: 256)
        let args = AIUpscaler.buildRealESRGANArguments(
            config: config,
            inputPath: "/tmp/input.png",
            outputPath: "/tmp/output.png"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/input.png"))
        XCTAssertTrue(args.contains("-n"))
        XCTAssertTrue(args.contains("realesrgan-x4plus"))
        XCTAssertTrue(args.contains("-s"))
        XCTAssertTrue(args.contains("4"))
        XCTAssertTrue(args.contains("-t"))
        XCTAssertTrue(args.contains("256"))
    }

    /// Verifies output resolution calculation.
    func test_aiUpscaler_calculateOutputResolution() {
        let res = AIUpscaler.calculateOutputResolution(
            sourceWidth: 960, sourceHeight: 540, scaleFactor: 4
        )
        XCTAssertEqual(res.width, 3840)
        XCTAssertEqual(res.height, 2160)
    }

    /// Verifies resolution rounding to even numbers.
    func test_aiUpscaler_resolutionRounding() {
        let res = AIUpscaler.calculateOutputResolution(
            sourceWidth: 481, sourceHeight: 271, scaleFactor: 2
        )
        XCTAssertEqual(res.width % 2, 0)
        XCTAssertEqual(res.height % 2, 0)
    }

    /// Verifies traditional upscale filter fallback.
    func test_aiUpscaler_traditionalFilter() {
        let filter = AIUpscaler.buildTraditionalUpscaleFilter(
            targetWidth: 3840, targetHeight: 2160
        )
        XCTAssertTrue(filter.contains("scale=3840:2160"))
        XCTAssertTrue(filter.contains("lanczos"))
    }

    /// Verifies VRAM estimation.
    func test_aiUpscaler_estimateVRAM() {
        let vram = AIUpscaler.estimateVRAM(width: 1920, height: 1080, scaleFactor: 4)
        XCTAssertGreaterThan(vram, 0)

        // Smaller tile = less VRAM
        let vramTiled = AIUpscaler.estimateVRAM(
            width: 1920, height: 1080, scaleFactor: 4, tileSize: 256
        )
        XCTAssertLessThan(vramTiled, vram)
    }

    /// Verifies frame extraction arguments.
    func test_aiUpscaler_frameExtraction() {
        let args = AIUpscaler.buildFrameExtractionArguments(
            inputPath: "/tmp/video.mp4",
            outputPattern: "/tmp/frames/%06d.png"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        XCTAssertTrue(args.contains("-pix_fmt"))
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.17: DCP Creation
    // -----------------------------------------------------------------

    /// Verifies DCP resolution dimensions.
    func test_dcpResolution_dimensions() {
        XCTAssertEqual(DCPResolution.dci2K.width, 2048)
        XCTAssertEqual(DCPResolution.dci2K.height, 1080)
        XCTAssertEqual(DCPResolution.dci4K.width, 4096)
        XCTAssertEqual(DCPResolution.dci4K.height, 2160)
    }

    /// Verifies DCP aspect ratio dimensions.
    func test_dcpAspectRatio_dimensions() {
        let flat2K = DCPAspectRatio.flat.activeDimensions(for: .dci2K)
        XCTAssertEqual(flat2K.width, 1998)
        XCTAssertEqual(flat2K.height, 1080)

        let scope2K = DCPAspectRatio.scope.activeDimensions(for: .dci2K)
        XCTAssertEqual(scope2K.width, 2048)
        XCTAssertEqual(scope2K.height, 858)

        let flat4K = DCPAspectRatio.flat.activeDimensions(for: .dci4K)
        XCTAssertEqual(flat4K.width, 3996)
        XCTAssertEqual(flat4K.height, 2160)
    }

    /// Verifies DCP video encode arguments.
    func test_dcpGenerator_videoEncodeArguments() {
        let config = DCPConfig(title: "Test Film", outputDirectory: "/tmp/dcp")
        let args = DCPGenerator.buildVideoEncodeArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/dcp/video.mxf",
            config: config
        )
        XCTAssertTrue(args.contains("-c:v"))
        XCTAssertTrue(args.contains("libopenjpeg"))
        XCTAssertTrue(args.contains("-pix_fmt"))
        XCTAssertTrue(args.contains("xyz12le"))
        XCTAssertTrue(args.contains("-an"))
    }

    /// Verifies DCP audio encode arguments.
    func test_dcpGenerator_audioEncodeArguments() {
        let config = DCPConfig(title: "Test", audioChannels: 6, outputDirectory: "/tmp/dcp")
        let args = DCPGenerator.buildAudioEncodeArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/dcp/audio.mxf",
            config: config
        )
        XCTAssertTrue(args.contains("pcm_s24le"))
        XCTAssertTrue(args.contains("48000"))
        XCTAssertTrue(args.contains("6"))
        XCTAssertTrue(args.contains("-vn"))
    }

    /// Verifies DCP ASSETMAP generation.
    func test_dcpGenerator_assetMap() {
        let xml = DCPGenerator.generateAssetMap(
            dcpId: "dcp-uuid",
            cplId: "cpl-uuid",
            pklId: "pkl-uuid",
            videoFile: "video.mxf",
            audioFile: "audio.mxf"
        )
        XCTAssertTrue(xml.contains("AssetMap"))
        XCTAssertTrue(xml.contains("urn:uuid:dcp-uuid"))
        XCTAssertTrue(xml.contains("urn:uuid:cpl-uuid"))
        XCTAssertTrue(xml.contains("video.mxf"))
        XCTAssertTrue(xml.contains("audio.mxf"))
        XCTAssertTrue(xml.contains("MeedyaConverter"))
    }

    /// Verifies DCP CPL generation.
    func test_dcpGenerator_cpl() {
        let config = DCPConfig(
            title: "My Film",
            contentKind: .feature,
            outputDirectory: "/tmp/dcp"
        )
        let xml = DCPGenerator.generateCPL(
            config: config,
            cplId: "cpl-uuid",
            videoId: "vid-uuid",
            audioId: "aud-uuid",
            durationFrames: 172800
        )
        XCTAssertTrue(xml.contains("CompositionPlaylist"))
        XCTAssertTrue(xml.contains("My Film"))
        XCTAssertTrue(xml.contains("feature"))
        XCTAssertTrue(xml.contains("172800"))
    }

    /// Verifies DCP validation.
    func test_dcpGenerator_validation() {
        let good = DCPConfig(title: "Film", frameRate: 24, outputDirectory: "/tmp")
        XCTAssertTrue(DCPGenerator.validate(config: good).isEmpty)

        let badFps = DCPConfig(title: "Film", frameRate: 30, outputDirectory: "/tmp")
        XCTAssertFalse(DCPGenerator.validate(config: badFps).isEmpty)

        let noTitle = DCPConfig(title: "", outputDirectory: "/tmp")
        XCTAssertFalse(DCPGenerator.validate(config: noTitle).isEmpty)

        let encrypted = DCPConfig(title: "Film", encrypted: true, outputDirectory: "/tmp")
        XCTAssertFalse(DCPGenerator.validate(config: encrypted).isEmpty)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.18: Audio Fingerprinting
    // -----------------------------------------------------------------

    /// Verifies fingerprint argument construction.
    func test_audioFingerprinter_arguments() {
        let args = AudioFingerprinter.buildFingerprintArguments(
            inputPath: "/tmp/audio.flac",
            duration: 120
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/audio.flac"))
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("chromaprint"))
        XCTAssertTrue(args.contains("-t"))
    }

    /// Verifies fingerprint argument with stream selection.
    func test_audioFingerprinter_streamSelection() {
        let args = AudioFingerprinter.buildFingerprintArguments(
            inputPath: "/tmp/video.mkv",
            streamIndex: 2
        )
        XCTAssertTrue(args.contains("-map"))
        XCTAssertTrue(args.contains("0:a:2"))
    }

    /// Verifies AcoustID URL construction.
    func test_audioFingerprinter_acoustIDURL() {
        let url = AudioFingerprinter.buildAcoustIDLookupURL(
            fingerprint: "AQAA",
            duration: 180,
            apiKey: "test-key"
        )
        XCTAssertTrue(url.contains("api.acoustid.org"))
        XCTAssertTrue(url.contains("client=test-key"))
        XCTAssertTrue(url.contains("duration=180"))
        XCTAssertTrue(url.contains("fingerprint=AQAA"))
    }

    /// Verifies fingerprint comparison.
    func test_audioFingerprinter_compareIdentical() {
        let fp: [UInt32] = [0xAABBCCDD, 0x11223344, 0x55667788]
        let result = AudioFingerprinter.compareFingerprints(fp, fp)
        XCTAssertEqual(result.similarity, 1.0, accuracy: 0.001)
        XCTAssertTrue(result.isDefiniteMatch)
    }

    /// Verifies fingerprint comparison with different data.
    func test_audioFingerprinter_compareDifferent() {
        let fp1: [UInt32] = [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]
        let fp2: [UInt32] = [0x00000000, 0x00000000, 0x00000000]
        let result = AudioFingerprinter.compareFingerprints(fp1, fp2)
        XCTAssertEqual(result.similarity, 0.0, accuracy: 0.001)
        XCTAssertFalse(result.isLikelyMatch)
    }

    /// Verifies FingerprintMatch confidence levels.
    func test_fingerprintMatch_confidence() {
        let high = FingerprintMatch(confidence: 0.95, title: "Song")
        XCTAssertTrue(high.isHighConfidence)

        let low = FingerprintMatch(confidence: 0.3)
        XCTAssertFalse(low.isHighConfidence)
    }

    /// Verifies fingerprint parsing from output.
    func test_audioFingerprinter_parseFingerprint() {
        let output = "FINGERPRINT=AQADtNQYhYkYnYmR"
        let fp = AudioFingerprinter.parseFingerprint(from: output)
        XCTAssertEqual(fp, "AQADtNQYhYkYnYmR")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.6: Auto Metadata Tagging
    // -----------------------------------------------------------------

    /// Verifies audio title generation.
    func test_metadataTagger_audioTitle() {
        let title = MetadataTagger.generateAudioTitle(
            codec: "aac", channels: 2, language: "English"
        )
        XCTAssertEqual(title, "English Stereo AAC")

        let surround = MetadataTagger.generateAudioTitle(
            codec: "truehd", channels: 8, language: "English"
        )
        XCTAssertEqual(surround, "English 7.1 TrueHD")
    }

    /// Verifies subtitle title generation.
    func test_metadataTagger_subtitleTitle() {
        let normal = MetadataTagger.generateSubtitleTitle(language: "English")
        XCTAssertEqual(normal, "English")

        let forced = MetadataTagger.generateSubtitleTitle(language: "French", isForced: true)
        XCTAssertEqual(forced, "French (Forced)")

        let sdh = MetadataTagger.generateSubtitleTitle(language: "English", isSDH: true)
        XCTAssertEqual(sdh, "English SDH")
    }

    /// Verifies forced subtitle detection.
    func test_metadataTagger_forcedDetection() {
        // 10% of video duration = likely forced
        XCTAssertTrue(MetadataTagger.isLikelyForced(
            subtitleDuration: 180, videoDuration: 5400
        ))
        // 80% of video duration = full subtitles, not forced
        XCTAssertFalse(MetadataTagger.isLikelyForced(
            subtitleDuration: 4320, videoDuration: 5400
        ))
        // 0 duration = not forced
        XCTAssertFalse(MetadataTagger.isLikelyForced(
            subtitleDuration: 0, videoDuration: 5400
        ))
    }

    /// Verifies SDH subtitle detection.
    func test_metadataTagger_sdhDetection() {
        let sdhText = """
        [door slams]
        What are you doing here?
        [dramatic music]
        I came to say goodbye.
        [footsteps approaching]
        """
        XCTAssertTrue(MetadataTagger.isLikelySDH(sampleText: sdhText))

        let normalText = """
        What are you doing here?
        I came to say goodbye.
        We should talk about this.
        """
        XCTAssertFalse(MetadataTagger.isLikelySDH(sampleText: normalText))
    }

    /// Verifies metadata arguments generation.
    func test_metadataTagger_buildArguments() {
        let suggestions = [
            StreamTagSuggestion(
                streamIndex: 0,
                streamType: "audio",
                suggestedTitle: "English 5.1 AAC",
                suggestedLanguage: "eng",
                isDefault: true
            ),
            StreamTagSuggestion(
                streamIndex: 0,
                streamType: "subtitle",
                suggestedTitle: "English (Forced)",
                isForced: true
            ),
        ]
        let args = MetadataTagger.buildMetadataArguments(suggestions: suggestions)
        XCTAssertTrue(args.contains("title=English 5.1 AAC"))
        XCTAssertTrue(args.contains("language=eng"))
        let dispArg = args.first { $0.contains("default") }
        XCTAssertNotNil(dispArg)
    }

}
