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
    // MARK: - Media Server Notifier Tests (Phase 7.19)

    /// Verifies media server type properties.
    func test_mediaServerType_properties() {
        XCTAssertEqual(MediaServerType.plex.displayName, "Plex")
        XCTAssertEqual(MediaServerType.jellyfin.displayName, "Jellyfin")
        XCTAssertEqual(MediaServerType.emby.displayName, "Emby")
        XCTAssertEqual(MediaServerType.plex.defaultPort, 32400)
        XCTAssertEqual(MediaServerType.jellyfin.defaultPort, 8096)
        XCTAssertEqual(MediaServerType.emby.defaultPort, 8096)
    }

    /// Verifies media server config base URL generation.
    func test_mediaServerConfig_baseURL() {
        let config = MediaServerConfig(
            serverType: .plex,
            displayName: "My Plex",
            host: "192.168.1.100",
            apiKey: "test-token"
        )
        XCTAssertEqual(config.baseURL, "http://192.168.1.100:32400")

        let tlsConfig = MediaServerConfig(
            serverType: .jellyfin,
            displayName: "My Jellyfin",
            host: "media.example.com",
            port: 8920,
            apiKey: "test-key",
            useTLS: true
        )
        XCTAssertEqual(tlsConfig.baseURL, "https://media.example.com:8920")
    }

    /// Verifies Plex scan URL building.
    func test_mediaServerNotifier_plexScanURL() {
        let config = MediaServerConfig(
            serverType: .plex,
            displayName: "Plex",
            host: "localhost",
            apiKey: "abc123"
        )
        let (url, method, headers) = MediaServerNotifier.buildPlexScanURL(config: config)
        XCTAssertEqual(url, "http://localhost:32400/library/sections/all/refresh")
        XCTAssertEqual(method, "GET")
        XCTAssertEqual(headers["X-Plex-Token"], "abc123")

        // With specific library section
        let (url2, _, _) = MediaServerNotifier.buildPlexScanURL(
            config: config, librarySection: "3"
        )
        XCTAssertEqual(url2, "http://localhost:32400/library/sections/3/refresh")
    }

    /// Verifies Jellyfin scan URL building.
    func test_mediaServerNotifier_jellyfinScanURL() {
        let config = MediaServerConfig(
            serverType: .jellyfin,
            displayName: "Jellyfin",
            host: "localhost",
            apiKey: "key123"
        )
        let (url, method, headers) = MediaServerNotifier.buildJellyfinScanURL(config: config)
        XCTAssertEqual(url, "http://localhost:8096/Library/Refresh")
        XCTAssertEqual(method, "POST")
        XCTAssertEqual(headers["X-Emby-Token"], "key123")
    }

    /// Verifies Emby scan URL building.
    func test_mediaServerNotifier_embyScanURL() {
        let config = MediaServerConfig(
            serverType: .emby,
            displayName: "Emby",
            host: "localhost",
            apiKey: "emby-key"
        )
        let (url, method, headers) = MediaServerNotifier.buildEmbyScanURL(config: config)
        XCTAssertEqual(url, "http://localhost:8096/Library/Refresh")
        XCTAssertEqual(method, "POST")
        XCTAssertEqual(headers["X-Emby-Token"], "emby-key")
    }

    /// Verifies scan request building.
    func test_mediaServerNotifier_buildScanRequest() {
        let config = MediaServerConfig(
            serverType: .plex,
            displayName: "Plex",
            host: "192.168.1.50",
            apiKey: "token"
        )
        let request = MediaServerNotifier.buildScanRequest(config: config)
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Plex-Token"), "token")
    }

    /// Verifies webhook payload building.
    func test_mediaServerNotifier_webhookPayload() {
        let payload = MediaServerNotifier.buildWebhookPayload(
            event: .encodingCompleted,
            jobName: "Test Job",
            inputFile: "/input/video.mkv",
            outputFile: "/output/video.mp4",
            duration: 120.5,
            fileSize: 1_500_000
        )
        XCTAssertNotNil(payload)

        // Verify it's valid JSON with expected keys
        let json = try! JSONSerialization.jsonObject(with: payload!, options: []) as! [String: Any]
        XCTAssertEqual(json["event"] as? String, "encoding_completed")
        XCTAssertEqual(json["job_name"] as? String, "Test Job")
        XCTAssertEqual(json["input_file"] as? String, "/input/video.mkv")
        XCTAssertEqual(json["output_file"] as? String, "/output/video.mp4")
        XCTAssertEqual(json["encoding_duration_seconds"] as? Double, 120.5)
        XCTAssertEqual(json["output_file_size_bytes"] as? Int64, 1_500_000)
    }

    /// Verifies disabled server returns failure result.
    func test_mediaServerNotifier_disabledServer() async {
        let config = MediaServerConfig(
            serverType: .plex,
            displayName: "Disabled Plex",
            host: "localhost",
            apiKey: "token",
            enabled: false
        )
        let result = await MediaServerNotifier.sendLibraryScan(config: config)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorMessage, "Server is disabled")
    }

    // MARK: - Frame Comparison Extractor Tests (Phase 7.11)

    /// Verifies frame extraction argument building.
    func test_frameComparison_extractionArguments() {
        let args = FrameComparisonExtractor.buildFrameExtractionArguments(
            inputPath: "/video.mkv",
            outputPath: "/frame.png",
            timestamp: 30.5
        )
        XCTAssertTrue(args.contains("-ss"))
        XCTAssertTrue(args.contains("30.500"))
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/video.mkv"))
        XCTAssertTrue(args.contains("-frames:v"))
        XCTAssertTrue(args.contains("1"))
        XCTAssertTrue(args.contains("/frame.png"))
    }

    /// Verifies frame extraction with resize.
    func test_frameComparison_extractionWithResize() {
        let args = FrameComparisonExtractor.buildFrameExtractionArguments(
            inputPath: "/video.mkv",
            outputPath: "/frame.png",
            timestamp: 10.0,
            width: 1920,
            height: 1080
        )
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("scale=1920:1080"))
    }

    /// Verifies timestamp calculation for comparison frames.
    func test_frameComparison_calculateTimestamps() {
        let timestamps = FrameComparisonExtractor.calculateTimestamps(
            duration: 120.0,
            count: 5,
            excludeEdges: 2.0
        )
        XCTAssertEqual(timestamps.count, 5)
        // First should be near 2s, last near 118s
        XCTAssertEqual(timestamps.first!, 2.0, accuracy: 0.01)
        XCTAssertEqual(timestamps.last!, 118.0, accuracy: 0.01)
    }

    /// Verifies single timestamp calculation.
    func test_frameComparison_singleTimestamp() {
        let timestamps = FrameComparisonExtractor.calculateTimestamps(
            duration: 60.0,
            count: 1
        )
        XCTAssertEqual(timestamps.count, 1)
        // Should be in the middle
        XCTAssertEqual(timestamps[0], 30.0, accuracy: 1.0)
    }

    /// Verifies batch extraction argument building.
    func test_frameComparison_batchExtraction() {
        let batch = FrameComparisonExtractor.buildBatchExtractionArguments(
            sourcePath: "/source.mkv",
            encodedPath: "/encoded.mp4",
            timestamps: [10.0, 30.0, 60.0],
            outputDirectory: "/tmp/job"
        )
        XCTAssertEqual(batch.count, 3)
        XCTAssertTrue(batch[0].sourceArgs.contains("/source.mkv"))
        XCTAssertTrue(batch[0].encodedArgs.contains("/encoded.mp4"))
        XCTAssertEqual(batch[1].timestamp, 30.0)
    }

    /// Verifies SSIM argument building.
    func test_frameComparison_ssimArguments() {
        let args = FrameComparisonExtractor.buildSSIMArguments(
            sourcePath: "/source.mkv",
            encodedPath: "/encoded.mp4"
        )
        XCTAssertTrue(args.contains("-lavfi"))
        XCTAssertTrue(args.contains("ssim"))
    }

    /// Verifies PSNR argument building.
    func test_frameComparison_psnrArguments() {
        let args = FrameComparisonExtractor.buildPSNRArguments(
            sourcePath: "/source.mkv",
            encodedPath: "/encoded.mp4"
        )
        XCTAssertTrue(args.contains("-lavfi"))
        XCTAssertTrue(args.contains("psnr"))
    }

    /// Verifies SSIM parsing from FFmpeg output.
    func test_frameComparison_parseSSIM() {
        let output = """
        [Parsed_ssim_0 @ 0x7f9] SSIM Y:0.984532 U:0.991234 V:0.990123 All:0.982145 (17.493721)
        """
        let ssim = FrameComparisonExtractor.parseSSIM(from: output)
        XCTAssertNotNil(ssim)
        XCTAssertEqual(ssim!, 0.982145, accuracy: 0.000001)
    }

    /// Verifies PSNR parsing from FFmpeg output.
    func test_frameComparison_parsePSNR() {
        let output = """
        [Parsed_psnr_0 @ 0x7f9] PSNR y:43.56 u:48.12 v:47.89 average:42.123456 min:35.12 max:inf
        """
        let psnr = FrameComparisonExtractor.parsePSNR(from: output)
        XCTAssertNotNil(psnr)
        XCTAssertEqual(psnr!, 42.123456, accuracy: 0.000001)
    }

    /// Verifies comparison mode properties.
    func test_comparisonMode_displayNames() {
        XCTAssertEqual(ComparisonMode.sideBySide.displayName, "Side by Side")
        XCTAssertEqual(ComparisonMode.slider.displayName, "Slider")
        XCTAssertEqual(ComparisonMode.toggle.displayName, "Toggle")
        XCTAssertEqual(ComparisonMode.difference.displayName, "Difference")
    }

    // MARK: - Encoding Statistics Tests (Phase 7.4)

    /// Verifies encoding data point creation.
    func test_encodingStatistics_dataPoint() {
        let point = EncodingDataPoint(
            elapsedSeconds: 10.0,
            encodedSeconds: 25.0,
            fps: 120.5,
            bitrate: 5000.0,
            quantizer: 22.5,
            frameNumber: 750,
            speedFactor: 2.5
        )
        XCTAssertEqual(point.fps, 120.5)
        XCTAssertEqual(point.bitrate, 5000.0)
        XCTAssertEqual(point.speedFactor, 2.5)
    }

    /// Verifies statistics computation.
    func test_encodingStatistics_computedStats() {
        var stats = EncodingStatistics(
            jobID: UUID(),
            jobName: "Test Job"
        )
        stats.inputFileSize = 1_000_000_000 // 1 GB
        stats.outputFileSize = 500_000_000   // 500 MB
        stats.inputDuration = 3600.0          // 1 hour

        // Add some data points
        for i in 0..<10 {
            stats.addDataPoint(EncodingDataPoint(
                elapsedSeconds: Double(i) * 10,
                encodedSeconds: Double(i) * 36,
                fps: Double(100 + i * 5),
                bitrate: 4000.0 + Double(i) * 100,
                quantizer: 22.0,
                frameNumber: i * 900
            ))
        }

        XCTAssertEqual(stats.averageFPS, 122.5, accuracy: 0.1)
        XCTAssertEqual(stats.peakFPS, 145.0)
        XCTAssertEqual(stats.minimumFPS, 100.0)
        XCTAssertEqual(stats.compressionRatio!, 2.0, accuracy: 0.01)
        XCTAssertEqual(stats.spaceSavingsPercent!, 50.0, accuracy: 0.01)
        XCTAssertNotNil(stats.averageBitrate)
        XCTAssertNotNil(stats.averageQuantizer)
    }

    /// Verifies FPS time series extraction.
    func test_encodingStatistics_timeSeries() {
        var stats = EncodingStatistics(
            jobID: UUID(),
            jobName: "Test"
        )
        stats.addDataPoint(EncodingDataPoint(
            elapsedSeconds: 1.0, encodedSeconds: 2.0, fps: 100.0
        ))
        stats.addDataPoint(EncodingDataPoint(
            elapsedSeconds: 2.0, encodedSeconds: 4.0, fps: 120.0
        ))

        let series = stats.fpsTimeSeries
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].elapsed, 1.0)
        XCTAssertEqual(series[0].value, 100.0)
        XCTAssertEqual(series[1].value, 120.0)
    }

    /// Verifies statistics collector thread safety and sampling.
    func test_encodingStatisticsCollector_basic() {
        let collector = EncodingStatisticsCollector(
            jobID: UUID(),
            jobName: "Test",
            sampleInterval: 0.0 // No throttling for test
        )
        collector.setInputMetadata(
            fileSize: 100_000,
            duration: 60.0,
            videoCodec: "h265",
            resolution: "1920x1080"
        )

        collector.recordProgress(fps: 120.0, encodedSeconds: 10.0)
        collector.recordProgress(fps: 130.0, encodedSeconds: 20.0)
        collector.markComplete()

        let stats = collector.currentStatistics
        XCTAssertEqual(stats.dataPoints.count, 2)
        XCTAssertEqual(stats.inputDuration, 60.0)
        XCTAssertEqual(stats.videoCodec, "h265")
        XCTAssertNotNil(stats.endTime)
    }

    // MARK: - Stream Metadata Editor Tests (Phase 3.6)

    /// Verifies stream disposition FFmpeg value building.
    func test_streamDisposition_ffmpegValue() {
        let disp = StreamDisposition(isDefault: true, isForced: true)
        XCTAssertEqual(disp.ffmpegValue, "default+forced")

        let empty = StreamDisposition()
        XCTAssertEqual(empty.ffmpegValue, "0")

        let complex = StreamDisposition(
            isDefault: true,
            isOriginal: true,
            isHearingImpaired: true
        )
        XCTAssertTrue(complex.ffmpegValue.contains("default"))
        XCTAssertTrue(complex.ffmpegValue.contains("original"))
        XCTAssertTrue(complex.ffmpegValue.contains("hearing_impaired"))
    }

    /// Verifies disposition parsing.
    func test_streamDisposition_parse() {
        let disp = StreamDisposition.parse("default+forced+hearing_impaired")
        XCTAssertTrue(disp.isDefault)
        XCTAssertTrue(disp.isForced)
        XCTAssertTrue(disp.isHearingImpaired)
        XCTAssertFalse(disp.isDub)
        XCTAssertFalse(disp.isOriginal)
    }

    /// Verifies metadata edit argument building.
    func test_streamMetadataEditor_buildArguments() {
        var editSet = StreamMetadataEditSet()
        editSet.globalEdits["title"] = "My Movie"
        editSet.streamEdits.append(StreamMetadataEdit(
            streamIndex: 1,
            key: "language",
            value: "eng"
        ))
        editSet.streamEdits.append(StreamMetadataEdit(
            streamIndex: 2,
            key: "title",
            value: "Director Commentary"
        ))
        editSet.dispositionEdits.append(DispositionEdit(
            streamIndex: 1,
            disposition: StreamDisposition(isDefault: true)
        ))

        let args = StreamMetadataEditor.buildArguments(from: editSet)
        XCTAssertTrue(args.contains("-metadata"))
        XCTAssertTrue(args.contains("title=My Movie"))
        XCTAssertTrue(args.contains("-metadata:s:1"))
        XCTAssertTrue(args.contains("language=eng"))
        XCTAssertTrue(args.contains("-metadata:s:2"))
        XCTAssertTrue(args.contains("title=Director Commentary"))
        XCTAssertTrue(args.contains("-disposition:1"))
        XCTAssertTrue(args.contains("default"))
    }

    /// Verifies set title argument building.
    func test_streamMetadataEditor_setTitle() {
        let args = StreamMetadataEditor.buildSetTitle(streamIndex: 0, title: "Main Video")
        XCTAssertEqual(args, ["-metadata:s:0", "title=Main Video"])
    }

    /// Verifies set language argument building.
    func test_streamMetadataEditor_setLanguage() {
        let args = StreamMetadataEditor.buildSetLanguage(streamIndex: 1, language: "fra")
        XCTAssertEqual(args, ["-metadata:s:1", "language=fra"])
    }

    /// Verifies remux edit argument building.
    func test_streamMetadataEditor_remuxEdit() {
        var editSet = StreamMetadataEditSet()
        editSet.globalEdits["title"] = "Edited Title"

        let args = StreamMetadataEditor.buildRemuxEditArguments(
            inputPath: "/input.mkv",
            outputPath: "/output.mkv",
            editSet: editSet
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/input.mkv"))
        XCTAssertTrue(args.contains("-c"))
        XCTAssertTrue(args.contains("copy"))
        XCTAssertTrue(args.contains("title=Edited Title"))
        XCTAssertTrue(args.contains("/output.mkv"))
    }

    /// Verifies language code validation.
    func test_streamMetadataEditor_languageValidation() {
        XCTAssertTrue(StreamMetadataEditor.isValidLanguageCode("eng"))
        XCTAssertTrue(StreamMetadataEditor.isValidLanguageCode("en"))
        XCTAssertTrue(StreamMetadataEditor.isValidLanguageCode("fra"))
        XCTAssertFalse(StreamMetadataEditor.isValidLanguageCode(""))
        XCTAssertFalse(StreamMetadataEditor.isValidLanguageCode("1234"))
        XCTAssertFalse(StreamMetadataEditor.isValidLanguageCode("toolong"))
    }

    /// Verifies edit set has edits detection.
    func test_streamMetadataEditSet_hasEdits() {
        var empty = StreamMetadataEditSet()
        XCTAssertFalse(empty.hasEdits)

        empty.globalEdits["title"] = "Test"
        XCTAssertTrue(empty.hasEdits)
    }

    // MARK: - Disc Imager Tests (Phase 11.26)

    /// Verifies imaging method properties.
    func test_imagingMethod_properties() {
        XCTAssertEqual(ImagingMethod.dd.toolName, "dd")
        XCTAssertEqual(ImagingMethod.ddrescue.toolName, "ddrescue")
        XCTAssertEqual(ImagingMethod.readom.toolName, "readom")
        XCTAssertEqual(ImagingMethod.hdiutil.toolName, "hdiutil")
        XCTAssertEqual(ImagingMethod.dd.displayName, "dd (Raw Copy)")
    }

    /// Verifies dd argument building.
    func test_discImager_ddArguments() {
        let config = ImagingConfig(
            sourcePath: "/dev/sr0",
            outputPath: "/output/disc.iso",
            method: .dd
        )
        let args = DiscImager.buildDdArguments(config: config)
        XCTAssertTrue(args.contains("if=/dev/sr0"))
        XCTAssertTrue(args.contains("of=/output/disc.iso"))
        XCTAssertTrue(args.contains("bs=2048"))
        XCTAssertTrue(args.contains("status=progress"))
        XCTAssertTrue(args.contains("conv=noerror,sync"))
    }

    /// Verifies ddrescue argument building.
    func test_discImager_ddrescueArguments() {
        let config = ImagingConfig(
            sourcePath: "/dev/sr0",
            outputPath: "/output/disc.iso",
            method: .ddrescue,
            retryCount: 5,
            mapFilePath: "/output/disc.map"
        )
        let args = DiscImager.buildDdrescueArguments(config: config)
        XCTAssertTrue(args.contains("-b"))
        XCTAssertTrue(args.contains("2048"))
        XCTAssertTrue(args.contains("-r"))
        XCTAssertTrue(args.contains("5"))
        XCTAssertTrue(args.contains("-d"))
        XCTAssertTrue(args.contains("/dev/sr0"))
        XCTAssertTrue(args.contains("/output/disc.iso"))
        XCTAssertTrue(args.contains("/output/disc.map"))
    }

    /// Verifies hdiutil argument building.
    func test_discImager_hdiutilArguments() {
        let config = ImagingConfig(
            sourcePath: "/dev/disk2",
            outputPath: "/output/disc.cdr",
            method: .hdiutil
        )
        let args = DiscImager.buildHdiutilArguments(config: config)
        XCTAssertTrue(args.contains("create"))
        XCTAssertTrue(args.contains("-srcdevice"))
        XCTAssertTrue(args.contains("/dev/disk2"))
    }

    /// Verifies unified argument builder.
    func test_discImager_unifiedBuilder() {
        let config = ImagingConfig(
            sourcePath: "/dev/sr0",
            outputPath: "/disc.iso",
            method: .dd
        )
        let (tool, args) = DiscImager.buildArguments(config: config)
        XCTAssertEqual(tool, "dd")
        XCTAssertFalse(args.isEmpty)
    }

    /// Verifies checksum argument building.
    func test_discImager_checksumArguments() {
        let (tool, args) = DiscImager.buildChecksumArguments(filePath: "/disc.iso")
        XCTAssertEqual(tool, "sha256sum")
        XCTAssertTrue(args.contains("/disc.iso"))

        let (md5tool, _) = DiscImager.buildChecksumArguments(
            filePath: "/disc.iso", algorithm: "md5"
        )
        XCTAssertEqual(md5tool, "md5sum")
    }

    /// Verifies imaging progress formatting.
    func test_imagingProgress_formattedSpeed() {
        var progress = ImagingProgress(bytesPerSecond: 12_500_000)
        XCTAssertEqual(progress.formattedSpeed, "12.5 MB/s")

        progress.bytesPerSecond = 500_000
        XCTAssertEqual(progress.formattedSpeed, "500 KB/s")

        progress.bytesPerSecond = 100
        XCTAssertEqual(progress.formattedSpeed, "100 B/s")
    }

    /// Verifies imaging progress fraction complete.
    func test_imagingProgress_fractionComplete() {
        let progress = ImagingProgress(
            bytesCopied: 500_000,
            totalBytes: 1_000_000
        )
        XCTAssertEqual(progress.fractionComplete!, 0.5, accuracy: 0.001)
    }

    // MARK: - Speech-to-Text Engine Tests (Phase 18.1)

    /// Verifies speech-to-text provider properties.
    func test_sttProvider_properties() {
        XCTAssertFalse(SpeechToTextProvider.whisperLocal.requiresAPIKey)
        XCTAssertTrue(SpeechToTextProvider.whisperAPI.requiresAPIKey)
        XCTAssertTrue(SpeechToTextProvider.whisperLocal.isLocal)
        XCTAssertFalse(SpeechToTextProvider.whisperAPI.isLocal)
    }

    /// Verifies Whisper model properties.
    func test_whisperModel_sizes() {
        XCTAssertEqual(WhisperModel.tiny.approximateSizeMB, 75)
        XCTAssertEqual(WhisperModel.large.approximateSizeMB, 2900)
        XCTAssertEqual(WhisperModel.turbo.approximateSizeMB, 800)
    }

    /// Verifies audio extraction argument building.
    func test_stt_audioExtractionArguments() {
        let args = SpeechToTextEngine.buildAudioExtractionArguments(
            inputPath: "/video.mkv",
            outputPath: "/audio.wav"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/video.mkv"))
        XCTAssertTrue(args.contains("-ac"))
        XCTAssertTrue(args.contains("1"))
        XCTAssertTrue(args.contains("-ar"))
        XCTAssertTrue(args.contains("16000"))
        XCTAssertTrue(args.contains("pcm_s16le"))
        XCTAssertTrue(args.contains("/audio.wav"))
    }

    /// Verifies whisper.cpp argument building.
    func test_stt_whisperArguments() {
        let config = TranscriptionConfig(
            provider: .whisperLocal,
            model: .medium,
            sourceLanguage: "en",
            translateToEnglish: false,
            outputFormat: .srt,
            threads: 4
        )
        let args = SpeechToTextEngine.buildWhisperArguments(
            config: config,
            audioPath: "/audio.wav",
            outputPath: "/output"
        )
        XCTAssertTrue(args.contains("-m"))
        XCTAssertTrue(args.contains("models/ggml-medium.bin"))
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("/audio.wav"))
        XCTAssertTrue(args.contains("--output-srt"))
        XCTAssertTrue(args.contains("-l"))
        XCTAssertTrue(args.contains("en"))
        XCTAssertTrue(args.contains("-t"))
        XCTAssertTrue(args.contains("4"))
    }

    /// Verifies whisper translate mode argument.
    func test_stt_whisperTranslateMode() {
        let config = TranscriptionConfig(
            translateToEnglish: true
        )
        let args = SpeechToTextEngine.buildWhisperArguments(
            config: config,
            audioPath: "/audio.wav",
            outputPath: "/output"
        )
        XCTAssertTrue(args.contains("--translate"))
    }

    /// Verifies SRT generation from segments.
    func test_stt_generateSRT() {
        let segments = [
            TranscriptionSegment(
                startTime: 1.0,
                endTime: 5.0,
                text: "Hello world"
            ),
            TranscriptionSegment(
                startTime: 6.0,
                endTime: 10.5,
                text: "Background music",
                isMusic: true
            ),
        ]
        let srt = SpeechToTextEngine.generateSRT(from: segments)
        XCTAssertTrue(srt.contains("1\n"))
        XCTAssertTrue(srt.contains("00:00:01,000 --> 00:00:05,000"))
        XCTAssertTrue(srt.contains("Hello world"))
        XCTAssertTrue(srt.contains("2\n"))
        XCTAssertTrue(srt.contains("\u{266B}"))
    }

    /// Verifies WebVTT generation.
    func test_stt_generateVTT() {
        let segments = [
            TranscriptionSegment(
                startTime: 0.0,
                endTime: 3.0,
                text: "Test subtitle"
            ),
        ]
        let vtt = SpeechToTextEngine.generateVTT(from: segments)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
        XCTAssertTrue(vtt.contains("00:00:00.000 --> 00:00:03.000"))
        XCTAssertTrue(vtt.contains("Test subtitle"))
    }

    /// Verifies SRT parsing.
    func test_stt_parseSRT() {
        let srt = """
        1
        00:00:01,000 --> 00:00:05,000
        Hello world

        2
        00:00:06,500 --> 00:00:10,000
        Second line

        """
        let segments = SpeechToTextEngine.parseSRT(srt)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].startTime, 1.0, accuracy: 0.01)
        XCTAssertEqual(segments[0].endTime, 5.0, accuracy: 0.01)
        XCTAssertEqual(segments[0].text, "Hello world")
        XCTAssertEqual(segments[1].startTime, 6.5, accuracy: 0.01)
    }

    /// Verifies transcription segment formatting.
    func test_transcriptionSegment_formatting() {
        let segment = TranscriptionSegment(
            startTime: 3661.5, // 1:01:01.500
            endTime: 3665.0,
            text: "Test"
        )
        XCTAssertEqual(segment.formattedStartTime, "01:01:01,500")
        XCTAssertEqual(segment.duration, 3.5, accuracy: 0.001)
    }

    /// Verifies transcription result properties.
    func test_transcriptionResult_properties() {
        let result = TranscriptionResult(
            segments: [
                TranscriptionSegment(startTime: 0, endTime: 5, text: "Hello"),
                TranscriptionSegment(startTime: 5, endTime: 10, text: "World"),
                TranscriptionSegment(startTime: 10, endTime: 15, text: "Music", isMusic: true),
            ],
            detectedLanguage: "en",
            duration: 15.0,
            provider: .whisperLocal
        )
        XCTAssertEqual(result.segmentCount, 3)
        XCTAssertEqual(result.fullText, "Hello World Music")
        XCTAssertEqual(result.musicSegments.count, 1)
        XCTAssertEqual(result.speechSegments.count, 2)
    }

    /// Verifies subtitle output format properties.
    func test_subtitleOutputFormat_properties() {
        XCTAssertEqual(SubtitleOutputFormat.srt.fileExtension, "srt")
        XCTAssertEqual(SubtitleOutputFormat.vtt.displayName, "WebVTT")
        XCTAssertEqual(SubtitleOutputFormat.json.fileExtension, "json")
    }

    // MARK: - Multi-Stream Selector Tests (Phase 3.4)

    /// Verifies stream selection properties.
    func test_streamSelection_properties() {
        let empty = StreamSelection()
        XCTAssertFalse(empty.hasSelection)
        XCTAssertEqual(empty.totalSelectedStreams, 0)

        let selection = StreamSelection(
            videoStreamIndices: [0],
            audioStreamIndices: [0, 1, 2]
        )
        XCTAssertTrue(selection.hasSelection)
        XCTAssertEqual(selection.totalSelectedStreams, 4)
    }

    /// Verifies container compatibility lookup.
    func test_multiStream_containerCompat() {
        let mkv = MultiStreamSelector.compatibility(for: "mkv")
        XCTAssertEqual(mkv.maxVideoStreams, 99)
        XCTAssertTrue(mkv.supportsAttachments)
        XCTAssertTrue(mkv.supportsChapters)

        let mp4 = MultiStreamSelector.compatibility(for: "mp4")
        XCTAssertEqual(mp4.maxVideoStreams, 1)
        XCTAssertFalse(mp4.supportsAttachments)

        let webm = MultiStreamSelector.compatibility(for: "webm")
        XCTAssertEqual(webm.maxVideoStreams, 1)
        XCTAssertEqual(webm.maxAudioStreams, 1)
    }

    /// Verifies validation catches too many video streams.
    func test_multiStream_validation_tooManyVideo() {
        let selection = StreamSelection(
            videoStreamIndices: [0, 1]
        )
        let errors = MultiStreamSelector.validate(
            selection: selection,
            container: "mp4",
            sourceStreamCount: 5
        )
        XCTAssertFalse(errors.isEmpty)
        if case .tooManyVideoStreams(let sel, let max) = errors[0] {
            XCTAssertEqual(sel, 2)
            XCTAssertEqual(max, 1)
        } else {
            XCTFail("Expected tooManyVideoStreams error")
        }
    }

    /// Verifies validation passes for MKV with multiple streams.
    func test_multiStream_validation_mkvMultiple() {
        let selection = StreamSelection(
            videoStreamIndices: [0, 1, 2],
            audioStreamIndices: [0, 1]
        )
        let errors = MultiStreamSelector.validate(
            selection: selection,
            container: "mkv",
            sourceStreamCount: 10
        )
        XCTAssertTrue(errors.isEmpty)
    }

    /// Verifies mapAll bypasses validation.
    func test_multiStream_validation_mapAll() {
        let selection = StreamSelection(mapAll: true)
        let errors = MultiStreamSelector.validate(
            selection: selection,
            container: "webm",
            sourceStreamCount: 5
        )
        XCTAssertTrue(errors.isEmpty)
    }

    /// Verifies map argument building for multiple streams.
    func test_multiStream_buildMapArguments() {
        let selection = StreamSelection(
            videoStreamIndices: [0],
            audioStreamIndices: [0, 2],
            subtitleStreamIndices: [1]
        )
        let args = MultiStreamSelector.buildMapArguments(selection: selection)
        XCTAssertTrue(args.contains("-map"))
        XCTAssertTrue(args.contains("0:v:0"))
        XCTAssertTrue(args.contains("0:a:0"))
        XCTAssertTrue(args.contains("0:a:2"))
        XCTAssertTrue(args.contains("0:s:1"))
    }

    /// Verifies mapAll argument building.
    func test_multiStream_buildMapArguments_mapAll() {
        let selection = StreamSelection(mapAll: true)
        let args = MultiStreamSelector.buildMapArguments(selection: selection)
        XCTAssertEqual(args, ["-map", "0"])
    }

    /// Verifies default selection with no selection produces auto defaults.
    func test_multiStream_emptySelection_defaults() {
        let selection = StreamSelection()
        let args = MultiStreamSelector.buildMapArguments(selection: selection)
        XCTAssertTrue(args.contains("0:v:0?"))
        XCTAssertTrue(args.contains("0:a:0?"))
    }

    /// Verifies per-stream codec argument building.
    func test_multiStream_perStreamCodecs() {
        let args = MultiStreamSelector.buildPerStreamCodecArguments(
            audioCodecs: [0: "aac", 1: "ac3"],
            subtitleCodecs: [0: "srt"]
        )
        XCTAssertTrue(args.contains("-c:a:0"))
        XCTAssertTrue(args.contains("aac"))
        XCTAssertTrue(args.contains("-c:a:1"))
        XCTAssertTrue(args.contains("ac3"))
        XCTAssertTrue(args.contains("-c:s:0"))
        XCTAssertTrue(args.contains("srt"))
    }

    /// Verifies disposition argument building.
    func test_multiStream_dispositionArguments() {
        let args = MultiStreamSelector.buildDispositionArguments(
            defaultAudioIndex: 1,
            defaultSubtitleIndex: 0
        )
        XCTAssertTrue(args.contains("-disposition:a:1"))
        XCTAssertTrue(args.contains("-disposition:s:0"))
    }

    /// Verifies stream filtering by type.
    func test_multiStream_filterStreams() {
        let streams = [
            MediaStream(streamIndex: 0, streamType: .video),
            MediaStream(streamIndex: 1, streamType: .audio),
            MediaStream(streamIndex: 2, streamType: .audio),
            MediaStream(streamIndex: 3, streamType: .subtitle),
        ]
        let audio = MultiStreamSelector.filterStreams(streams, type: .audio)
        XCTAssertEqual(audio.count, 2)
        XCTAssertEqual(audio[0].streamIndex, 1)
        XCTAssertEqual(audio[1].streamIndex, 2)
    }

    /// Verifies default selection from streams.
    func test_multiStream_defaultSelection() {
        let streams = [
            MediaStream(streamIndex: 0, streamType: .video),
            MediaStream(streamIndex: 1, streamType: .audio),
            MediaStream(streamIndex: 2, streamType: .audio),
            MediaStream(streamIndex: 3, streamType: .subtitle),
            MediaStream(streamIndex: 4, streamType: .subtitle),
        ]
        let selection = MultiStreamSelector.defaultSelection(from: streams)
        XCTAssertEqual(selection.videoStreamIndices, [0])
        XCTAssertEqual(selection.audioStreamIndices, [0, 1])
        XCTAssertEqual(selection.subtitleStreamIndices, [0, 1])
    }

    /// Verifies invalid stream index detection.
    func test_multiStream_validation_invalidIndex() {
        let selection = StreamSelection(
            videoStreamIndices: [99]
        )
        let errors = MultiStreamSelector.validate(
            selection: selection,
            container: "mkv",
            sourceStreamCount: 5
        )
        XCTAssertFalse(errors.isEmpty)
        if case .invalidStreamIndex(let idx) = errors[0] {
            XCTAssertEqual(idx, 99)
        }
    }

}
