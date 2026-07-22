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
    // MARK: - Phase 7.12: Quality Metrics
    // -----------------------------------------------------------------

    /// Verifies QualityMetricType CaseIterable conformance.
    func test_qualityMetricType_allCases() {
        XCTAssertEqual(QualityMetricType.allCases.count, 3)
        XCTAssertTrue(QualityMetricType.allCases.contains(.vmaf))
        XCTAssertTrue(QualityMetricType.allCases.contains(.ssim))
        XCTAssertTrue(QualityMetricType.allCases.contains(.psnr))
    }

    /// Verifies VMAF model raw values.
    func test_vmafModel_rawValues() {
        XCTAssertEqual(VMAFModel.standard.rawValue, "vmaf_v0.6.1")
        XCTAssertEqual(VMAFModel.uhd4K.rawValue, "vmaf_4k_v0.6.1")
        XCTAssertEqual(VMAFModel.phone.rawValue, "vmaf_v0.6.1neg")
    }

    /// Verifies VMAF argument construction.
    func test_qualityMetrics_vmafArguments() {
        let args = QualityMetricsBuilder.buildVMAFArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/encoded.mp4"))
        XCTAssertTrue(args.contains("/tmp/source.mp4"))
        let lavfi = args.first { $0.contains("libvmaf") }
        XCTAssertNotNil(lavfi)
        XCTAssertTrue(lavfi?.contains("vmaf_v0.6.1") ?? false)
    }

    /// Verifies VMAF with 4K model and log path.
    func test_qualityMetrics_vmaf4KWithLog() {
        let args = QualityMetricsBuilder.buildVMAFArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4",
            model: .uhd4K,
            logPath: "/tmp/vmaf.json"
        )
        let lavfi = args.first { $0.contains("libvmaf") }
        XCTAssertNotNil(lavfi)
        XCTAssertTrue(lavfi?.contains("vmaf_4k_v0.6.1") ?? false)
        XCTAssertTrue(lavfi?.contains("log_path") ?? false)
        XCTAssertTrue(lavfi?.contains("log_fmt=json") ?? false)
    }

    /// Verifies SSIM argument construction.
    func test_qualityMetrics_ssimArguments() {
        let args = QualityMetricsBuilder.buildSSIMArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4",
            logPath: "/tmp/ssim.log"
        )
        XCTAssertTrue(args.contains("-lavfi"))
        let filter = args.first { $0.contains("ssim") }
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter?.contains("stats_file") ?? false)
    }

    /// Verifies PSNR argument construction.
    func test_qualityMetrics_psnrArguments() {
        let args = QualityMetricsBuilder.buildPSNRArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4"
        )
        XCTAssertTrue(args.contains("-lavfi"))
        let filter = args.first { $0.contains("psnr") }
        XCTAssertNotNil(filter)
    }

    /// Verifies VMAF score parsing from FFmpeg output.
    func test_qualityMetrics_parseVMAF() {
        let output = """
        [libvmaf @ 0x12345] VMAF score: 95.123456
        """
        let score = QualityMetricsBuilder.parseVMAFScore(from: output)
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 95.123456, accuracy: 0.001)
    }

    /// Verifies SSIM score parsing from FFmpeg output.
    func test_qualityMetrics_parseSSIM() {
        let output = """
        [Parsed_ssim_0 @ 0x12345] SSIM Y:0.987654 U:0.993210 V:0.991234 All:0.990699 (20.41)
        """
        let score = QualityMetricsBuilder.parseSSIMScore(from: output)
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 0.990699, accuracy: 0.0001)
    }

    /// Verifies PSNR score parsing from FFmpeg output.
    func test_qualityMetrics_parsePSNR() {
        let output = """
        [Parsed_psnr_0 @ 0x12345] PSNR y:45.123456 u:47.234567 v:46.345678 average:45.901234 min:32.123456 max:inf
        """
        let result = QualityMetricsBuilder.parsePSNRScore(from: output)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.average, 45.901234, accuracy: 0.001)
        XCTAssertEqual(result!.min, 32.123456, accuracy: 0.001)
    }

    /// Verifies QualityScore summary text.
    func test_qualityScore_summary() {
        let vmaf = QualityScore(metric: .vmaf, mean: 95.5, min: 82.0, max: 99.0)
        XCTAssertTrue(vmaf.summary.contains("Excellent"))
        XCTAssertTrue(vmaf.summary.contains("95.50"))

        let ssim = QualityScore(metric: .ssim, mean: 0.85, min: 0.72, max: 0.99)
        XCTAssertTrue(ssim.summary.contains("Fair"))

        let psnr = QualityScore(metric: .psnr, mean: 42.5, min: 30.0, max: 50.0)
        XCTAssertTrue(psnr.summary.contains("Excellent"))
    }

    /// Verifies QualityReport threshold checking.
    func test_qualityReport_meetsThresholds() {
        let good = QualityReport(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4",
            scores: [
                QualityScore(metric: .vmaf, mean: 93, min: 80, max: 99),
                QualityScore(metric: .ssim, mean: 0.97, min: 0.92, max: 1.0),
            ]
        )
        XCTAssertTrue(good.meetsQualityThresholds)

        let bad = QualityReport(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4",
            scores: [
                QualityScore(metric: .vmaf, mean: 70, min: 50, max: 85),
            ]
        )
        XCTAssertFalse(bad.meetsQualityThresholds)
    }

    /// Verifies QualityReport score lookup.
    func test_qualityReport_scoreLookup() {
        let report = QualityReport(
            referencePath: "/tmp/a.mp4",
            distortedPath: "/tmp/b.mp4",
            scores: [
                QualityScore(metric: .vmaf, mean: 90, min: 80, max: 99),
                QualityScore(metric: .psnr, mean: 42, min: 35, max: 50),
            ]
        )
        XCTAssertNotNil(report.score(for: .vmaf))
        XCTAssertNotNil(report.score(for: .psnr))
        XCTAssertNil(report.score(for: .ssim))
    }

    // -----------------------------------------------------------------
    // MARK: - Issue #434: QualityMetrics (Utility) — real analysis wiring
    // -----------------------------------------------------------------
    // `QualityMetrics` (Sources/ConverterEngine/Utilities/QualityMetricsUtility.swift)
    // is the builder/parser actually invoked by QualityMetricsView's real
    // FFmpeg execution (distinct from `QualityMetricsBuilder` above, which
    // predates it and is already covered). These are pure argument-string
    // and text-parsing tests — no FFmpeg process is spawned.

    /// Verifies VMAF argument construction places distorted before
    /// reference (libvmaf convention) and threads the log path through.
    func test_qualityMetricsUtility_vmafArguments() {
        let args = QualityMetrics.buildVMAFArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4",
            logPath: "/tmp/vmaf_log.json"
        )
        XCTAssertEqual(args.first, "-i")
        XCTAssertEqual(args[1], "/tmp/encoded.mp4")
        XCTAssertEqual(args[3], "/tmp/source.mp4")
        let filter = args.first { $0.contains("libvmaf") }
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter?.contains("log_path=/tmp/vmaf_log.json") ?? false)
        XCTAssertTrue(filter?.contains("log_fmt=json") ?? false)
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("null"))
    }

    /// Verifies SSIM argument construction (no log-path parameter on this builder).
    func test_qualityMetricsUtility_ssimArguments() {
        let args = QualityMetrics.buildSSIMArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4"
        )
        XCTAssertEqual(args[1], "/tmp/encoded.mp4")
        XCTAssertEqual(args[3], "/tmp/source.mp4")
        let filter = args.first { $0.contains("ssim") }
        XCTAssertNotNil(filter)
    }

    /// Verifies PSNR argument construction (no log-path parameter on this builder).
    func test_qualityMetricsUtility_psnrArguments() {
        let args = QualityMetrics.buildPSNRArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4"
        )
        XCTAssertEqual(args[1], "/tmp/encoded.mp4")
        XCTAssertEqual(args[3], "/tmp/source.mp4")
        let filter = args.first { $0.contains("psnr") }
        XCTAssertNotNil(filter)
    }

    /// Verifies SSIM stderr parsing against a real captured FFmpeg 8.1.2 line
    /// (Homebrew ffmpeg-full, libvmaf-enabled, `crf 10` vs `crf 40` testsrc clips).
    func test_qualityMetricsUtility_parseSSIMOutput_realCapture() {
        let output = """
        [Parsed_ssim_0 @ 0x78ac57300] SSIM Y:0.962410 (14.249277) U:0.978104 (16.596446) V:0.984309 (18.043619) All:0.974941 (16.010416)
        [out#0/null @ 0x78ac54540] video:8KiB audio:0KiB subtitle:0KiB other streams:0KiB global headers:0KiB muxing overhead: unknown
        """
        let score = QualityMetrics.parseSSIMOutput(output)
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 0.974941, accuracy: 0.0001)
    }

    /// Verifies SSIM parsing returns nil when the expected line is absent.
    func test_qualityMetricsUtility_parseSSIMOutput_missing() {
        XCTAssertNil(QualityMetrics.parseSSIMOutput("no ssim data here"))
    }

    /// Verifies PSNR stderr parsing against a real captured FFmpeg 8.1.2 line.
    func test_qualityMetricsUtility_parsePSNROutput_realCapture() {
        let output = """
        [Parsed_psnr_0 @ 0xb4cc4b300] PSNR y:34.625483 u:38.473346 v:38.500011 average:36.791028 min:36.352569 max:37.126845
        """
        let score = QualityMetrics.parsePSNROutput(output)
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 36.791028, accuracy: 0.001)
    }

    /// Verifies PSNR parsing returns nil when the expected line is absent.
    func test_qualityMetricsUtility_parsePSNROutput_missing() {
        XCTAssertNil(QualityMetrics.parsePSNROutput("no psnr data here"))
    }

    /// Verifies `parseVMAFLog` against a real FFmpeg libvmaf JSON log
    /// structure (captured from FFmpeg 8.1.2 / libvmaf 3.2.0 on a `crf 10`
    /// vs `crf 40` testsrc comparison), including the per-frame series used
    /// to populate the per-frame chart.
    func test_qualityMetricsUtility_parseVMAFLog_realShapedJSON() throws {
        let json = """
        {
          "version": "3.2.0",
          "fps": 404.15,
          "frames": [
            { "frameNum": 0, "metrics": { "integer_adm2": 0.981790, "vmaf": 85.117645 } },
            { "frameNum": 1, "metrics": { "integer_adm2": 0.980102, "vmaf": 86.191820 } },
            { "frameNum": 2, "metrics": { "integer_adm2": 0.978485, "vmaf": 86.500000 } }
          ],
          "pooled_metrics": {
            "vmaf": { "min": 85.063801, "max": 87.378263, "mean": 86.122041, "harmonic_mean": 86.118494 }
          },
          "aggregate_metrics": {}
        }
        """
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vmaf_log_test_\(UUID().uuidString).json")
        try json.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = QualityMetrics.parseVMAFLog(tempURL.path)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.vmaf ?? 0, 86.122041, accuracy: 0.0001)
        XCTAssertEqual(result?.perFrameScores?.count, 3)
        XCTAssertEqual(result?.perFrameScores?[0] ?? 0, 85.117645, accuracy: 0.0001)
        XCTAssertEqual(result?.perFrameScores?[2] ?? 0, 86.5, accuracy: 0.0001)
    }

    /// Verifies `parseVMAFLog` returns nil for a non-existent log path
    /// (e.g. the process failed before FFmpeg could write the log).
    func test_qualityMetricsUtility_parseVMAFLog_missingFile() {
        let result = QualityMetrics.parseVMAFLog("/tmp/does-not-exist-\(UUID().uuidString).json")
        XCTAssertNil(result)
    }

    /// Verifies `QualityScoreResult.qualityGrade` prioritises VMAF over
    /// SSIM/PSNR when multiple metrics are present, matching the "All"
    /// metric-selection path in QualityMetricsView.
    func test_qualityScoreResult_qualityGrade_prioritisesVMAF() {
        let result = QualityScoreResult(vmaf: 95, ssim: 0.80, psnr: 20)
        XCTAssertEqual(result.qualityGrade, "Excellent")
        XCTAssertFalse(result.meetsRecommendedThresholds) // ssim/psnr below threshold
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.13: Scene Detection & Chaptering
    // -----------------------------------------------------------------

    /// Verifies scene detection argument construction.
    func test_sceneDetector_detectionArguments() {
        let args = SceneDetector.buildDetectionArguments(
            inputPath: "/tmp/video.mp4",
            threshold: 0.4
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        let vf = args.first { $0.contains("scene") }
        XCTAssertNotNil(vf)
        XCTAssertTrue(vf?.contains("0.40") ?? false)
    }

    /// Verifies scene change parsing from FFmpeg output.
    func test_sceneDetector_parseSceneChanges() {
        let output = """
        [Parsed_showinfo_1 @ 0x12345] n:  42 pts:  512000 pts_time:5.333 pos:123456 fmt:yuv420p sar:1/1
        [Parsed_showinfo_1 @ 0x12345] n: 120 pts: 1440000 pts_time:15.000 pos:234567 fmt:yuv420p sar:1/1
        [Parsed_showinfo_1 @ 0x12345] n: 250 pts: 3000000 pts_time:31.250 pos:345678 fmt:yuv420p sar:1/1
        """
        let changes = SceneDetector.parseSceneChanges(from: output)
        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(changes[0].timestamp, 5.333, accuracy: 0.001)
        XCTAssertEqual(changes[1].timestamp, 15.0, accuracy: 0.001)
        XCTAssertEqual(changes[2].timestamp, 31.25, accuracy: 0.001)
        XCTAssertEqual(changes[0].frameNumber, 42)
    }

    /// Verifies chapter generation from scene changes (every scene strategy).
    func test_sceneDetector_generateChaptersEveryScene() {
        let scenes = [
            SceneChange(timestamp: 60.0, score: 0.5),
            SceneChange(timestamp: 120.0, score: 0.4),
            SceneChange(timestamp: 180.0, score: 0.6),
        ]
        let chapters = SceneDetector.generateChapters(
            from: scenes,
            duration: 240.0,
            strategy: .everyScene,
            minimumDuration: 30.0
        )
        // Chapter 1 at 0, plus 3 scene chapters
        XCTAssertEqual(chapters.count, 4)
        XCTAssertEqual(chapters[0].startTime, 0)
        XCTAssertEqual(chapters[0].title, "Chapter 1")
        XCTAssertEqual(chapters[1].startTime, 60.0)
        XCTAssertEqual(chapters[3].startTime, 180.0)
    }

    /// Verifies micro-chapter filtering with minimum duration.
    func test_sceneDetector_minimumDurationFilter() {
        let scenes = [
            SceneChange(timestamp: 5.0, score: 0.5),  // Too close to start
            SceneChange(timestamp: 60.0, score: 0.4),
            SceneChange(timestamp: 65.0, score: 0.3),  // Too close to previous
        ]
        let chapters = SceneDetector.generateChapters(
            from: scenes,
            duration: 120.0,
            strategy: .everyScene,
            minimumDuration: 30.0
        )
        // Should get: Chapter 1 at 0, Chapter 2 at 60 (5s too close to 0, 65s too close to 60)
        XCTAssertEqual(chapters.count, 2)
    }

    /// Verifies fixed-interval chapter generation.
    func test_sceneDetector_fixedIntervalChapters() {
        let chapters = SceneDetector.generateChapters(
            from: [],
            duration: 900.0,
            strategy: .fixedInterval,
            fixedInterval: 300.0
        )
        // 0, 300, 600 (3 chapters at 5-minute intervals for 15-min video)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].startTime, 0)
        XCTAssertEqual(chapters[1].startTime, 300.0)
        XCTAssertEqual(chapters[2].startTime, 600.0)
    }

    /// Verifies FFmetadata chapter output format.
    func test_sceneDetector_ffmetadataOutput() {
        let chapters = [
            SceneChapter(title: "Intro", startTime: 0, endTime: 60),
            SceneChapter(title: "Main", startTime: 60, endTime: 180),
        ]
        let metadata = SceneDetector.generateFFmetadata(chapters: chapters, duration: 180)
        XCTAssertTrue(metadata.contains(";FFMETADATA1"))
        XCTAssertTrue(metadata.contains("[CHAPTER]"))
        XCTAssertTrue(metadata.contains("TIMEBASE=1/1000"))
        XCTAssertTrue(metadata.contains("START=0"))
        XCTAssertTrue(metadata.contains("END=60000"))
        XCTAssertTrue(metadata.contains("title=Intro"))
        XCTAssertTrue(metadata.contains("START=60000"))
        XCTAssertTrue(metadata.contains("title=Main"))
    }

    /// Verifies OGG chapter format output.
    func test_sceneDetector_oggChapterOutput() {
        let chapters = [
            SceneChapter(title: "Scene 1", startTime: 0),
            SceneChapter(title: "Scene 2", startTime: 65.5),
        ]
        let ogg = SceneDetector.generateOGGChapters(chapters: chapters)
        XCTAssertTrue(ogg.contains("CHAPTER01=00:00:00.000"))
        XCTAssertTrue(ogg.contains("CHAPTER01NAME=Scene 1"))
        XCTAssertTrue(ogg.contains("CHAPTER02=00:01:05.000"))
        XCTAssertTrue(ogg.contains("CHAPTER02NAME=Scene 2"))
    }

    /// Verifies SceneChange formatted timestamp.
    func test_sceneChange_formattedTimestamp() {
        let change = SceneChange(timestamp: 3723.456, score: 0.9)
        XCTAssertEqual(change.formattedTimestamp, "01:02:03.456")
    }

    /// Verifies auto-chaptering is skipped when source already has chapters.
    func test_sceneDetector_shouldAutoChapter() {
        XCTAssertTrue(SceneDetector.shouldAutoChapter(existingChapterCount: 0))
        XCTAssertFalse(SceneDetector.shouldAutoChapter(existingChapterCount: 1))
        XCTAssertFalse(SceneDetector.shouldAutoChapter(existingChapterCount: 5))
    }

    /// Verifies ChapterGenerationStrategy raw values.
    func test_chapterStrategy_rawValues() {
        XCTAssertEqual(ChapterGenerationStrategy.everyScene.rawValue, "every_scene")
        XCTAssertEqual(ChapterGenerationStrategy.fixedInterval.rawValue, "fixed_interval")
        XCTAssertEqual(ChapterGenerationStrategy.keyScenes.rawValue, "key_scenes")
        XCTAssertEqual(ChapterGenerationStrategy.combined.rawValue, "combined")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.2: Forensic Watermarking
    // -----------------------------------------------------------------

    /// Verifies WatermarkStrength CaseIterable conformance and values.
    func test_watermarkStrength_allCases() {
        XCTAssertEqual(WatermarkStrength.allCases.count, 3)
        XCTAssertTrue(WatermarkStrength.light.opacity < WatermarkStrength.standard.opacity)
        XCTAssertTrue(WatermarkStrength.standard.opacity < WatermarkStrength.strong.opacity)
        XCTAssertTrue(WatermarkStrength.light.blendFactor < WatermarkStrength.strong.blendFactor)
    }

    /// Verifies WatermarkPayload encoding.
    func test_watermarkPayload_encodedString() {
        let payload = WatermarkPayload(
            identifier: "user-123",
            metadata: "license-abc"
        )
        XCTAssertTrue(payload.encodedString.contains("user-123"))
        XCTAssertTrue(payload.encodedString.contains("license-abc"))
        XCTAssertFalse(payload.payloadHash.isEmpty)
        XCTAssertEqual(payload.payloadHash.count, 16) // 16 hex chars
    }

    /// Verifies embed filter construction.
    func test_forensicWatermark_embedFilter() {
        let payload = WatermarkPayload(identifier: "test-user")
        let filter = ForensicWatermark.buildEmbedFilter(
            payload: payload,
            strength: .standard
        )
        XCTAssertTrue(filter.contains("drawtext"))
        XCTAssertTrue(filter.contains(payload.payloadHash))
        XCTAssertTrue(filter.contains("fontcolor=white@"))
    }

    /// Verifies multiple drawtext positions for redundancy.
    func test_forensicWatermark_multiplePositions() {
        let payload = WatermarkPayload(identifier: "test")
        let filter = ForensicWatermark.buildEmbedFilter(payload: payload)
        // Should have 5 drawtext filters chained
        let drawTextCount = filter.components(separatedBy: "drawtext").count - 1
        XCTAssertEqual(drawTextCount, 5)
    }

    /// Verifies noise watermark filter construction.
    func test_forensicWatermark_noiseFilter() {
        let payload = WatermarkPayload(identifier: "test")
        let filter = ForensicWatermark.buildNoiseWatermarkFilter(
            payload: payload,
            strength: .standard
        )
        XCTAssertTrue(filter.contains("noise="))
        XCTAssertTrue(filter.contains("amount="))
    }

    /// Verifies metadata arguments for container embedding.
    func test_forensicWatermark_metadataArguments() {
        let payload = WatermarkPayload(identifier: "user-456")
        let args = ForensicWatermark.buildMetadataArguments(payload: payload)
        XCTAssertTrue(args.contains("-metadata"))
        XCTAssertTrue(args.contains("encoded_by=MeedyaConverter"))
        let wmArg = args.first { $0.contains("watermark_id=") }
        XCTAssertNotNil(wmArg)
    }

    /// Verifies complete watermark arguments when enabled.
    func test_forensicWatermark_enabledConfig() {
        let config = WatermarkConfig(
            enabled: true,
            payload: WatermarkPayload(identifier: "test"),
            strength: .strong
        )
        let (filter, args) = ForensicWatermark.buildWatermarkArguments(config: config)
        XCTAssertFalse(filter.isEmpty)
        XCTAssertFalse(args.isEmpty)
        XCTAssertTrue(filter.contains("drawtext"))
    }

    /// Verifies watermark arguments when disabled.
    func test_forensicWatermark_disabledConfig() {
        let config = WatermarkConfig(
            enabled: false,
            payload: WatermarkPayload(identifier: "test")
        )
        let (filter, args) = ForensicWatermark.buildWatermarkArguments(config: config)
        XCTAssertTrue(filter.isEmpty)
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies detection argument construction.
    func test_forensicWatermark_detectionArguments() {
        let args = ForensicWatermark.buildDetectionArguments(
            inputPath: "/tmp/video.mp4",
            outputPath: "/tmp/analysis.png",
            seekTo: 30.0
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        XCTAssertTrue(args.contains("/tmp/analysis.png"))
        let vf = args.first { $0.contains("contrast") }
        XCTAssertNotNil(vf)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.14: Crop Detection (existing CropDetector)
    // -----------------------------------------------------------------

    /// Verifies CropRect filter string generation.
    func test_cropRect_filterString() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        XCTAssertEqual(crop.filterString, "crop=1920:800:0:140")
    }

    /// Verifies CropRect display string.
    func test_cropRect_displayString() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        XCTAssertEqual(crop.displayString, "1920x800+0+140")
    }

    /// Verifies CropRect aspect ratio calculation.
    func test_cropRect_aspectRatio() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        XCTAssertEqual(crop.aspectRatio, 2.4, accuracy: 0.01)
    }

    /// Verifies CropRect cropping detection.
    func test_cropRect_isCropping() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        XCTAssertTrue(crop.isCropping(sourceWidth: 1920, sourceHeight: 1080))
        XCTAssertFalse(crop.isCropping(sourceWidth: 1920, sourceHeight: 800))
    }

    /// Verifies cropdetect output parsing.
    func test_cropDetector_parseCropOutput() {
        let output = """
        [Parsed_cropdetect_0 @ 0x12345] x1:0 x2:1919 y1:140 y2:939 w:1920 h:800 x:0 y:140 pts:12345
        [Parsed_cropdetect_0 @ 0x12345] x1:0 x2:1919 y1:140 y2:939 w:1920 h:800 x:0 y:140 pts:23456
        """
        let crops = CropDetector.parseCropDetectOutput(output)
        XCTAssertEqual(crops.count, 2)
        XCTAssertEqual(crops[0].width, 1920)
        XCTAssertEqual(crops[0].height, 800)
        XCTAssertEqual(crops[0].x, 0)
        XCTAssertEqual(crops[0].y, 140)
    }

    /// Verifies CropDetectionResult summary.
    func test_cropDetectionResult_summary() {
        let result = CropDetectionResult(
            recommendedCrop: CropRect(width: 1920, height: 800, x: 0, y: 140),
            detectedCrops: [],
            confidence: 0.95,
            sourceWidth: 1920,
            sourceHeight: 1080
        )
        XCTAssertTrue(result.willCrop)
        XCTAssertTrue(result.cropPercentage > 0)
        XCTAssertTrue(result.summary.contains("removes"))
    }

    /// Verifies no-crop result.
    func test_cropDetectionResult_noCrop() {
        let result = CropDetectionResult(
            recommendedCrop: CropRect(width: 1920, height: 1080, x: 0, y: 0),
            detectedCrops: [],
            confidence: 1.0,
            sourceWidth: 1920,
            sourceHeight: 1080
        )
        XCTAssertFalse(result.willCrop)
        XCTAssertEqual(result.cropPercentage, 0, accuracy: 0.01)
        XCTAssertTrue(result.summary.contains("No black bars"))
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.3: Encoding Reports
    // -----------------------------------------------------------------

    /// Verifies EncodingReport compression ratio calculation.
    func test_encodingReport_compressionRatio() {
        let report = EncodingReport(
            inputPath: "/tmp/source.mkv",
            inputFileSize: 1_000_000_000, // 1 GB
            inputDuration: 3600,
            outputPath: "/tmp/output.mp4",
            outputFileSize: 250_000_000 // 250 MB
        )
        XCTAssertEqual(report.compressionRatio, 4.0, accuracy: 0.01)
        XCTAssertEqual(report.sizeReductionPercent, 75.0, accuracy: 0.01)
    }

    /// Verifies EncodingReport plain text output.
    func test_encodingReport_plainText() {
        let report = EncodingReport(
            inputPath: "/tmp/source.mkv",
            inputFileSize: 500_000_000,
            inputDuration: 1800,
            inputFormat: "matroska",
            inputStreams: [
                StreamReport(type: "video", codec: "h265", bitrate: 5_000_000, resolution: "1920x1080"),
                StreamReport(type: "audio", codec: "aac", bitrate: 160_000, channels: 2),
            ],
            outputPath: "/tmp/output.mp4",
            outputFileSize: 200_000_000,
            outputFormat: "mp4",
            profileName: "webStandard"
        )
        let text = report.toPlainText()
        XCTAssertTrue(text.contains("ENCODING REPORT"))
        XCTAssertTrue(text.contains("source.mkv"))
        XCTAssertTrue(text.contains("output.mp4"))
        XCTAssertTrue(text.contains("COMPRESSION"))
        XCTAssertTrue(text.contains("webStandard"))
    }

    /// Verifies EncodingReport Markdown output.
    func test_encodingReport_markdown() {
        let report = EncodingReport(
            inputPath: "/tmp/source.mkv",
            inputFileSize: 500_000_000,
            inputDuration: 1800,
            outputPath: "/tmp/output.mp4",
            outputFileSize: 200_000_000
        )
        let md = report.toMarkdown()
        XCTAssertTrue(md.contains("# Encoding Report"))
        XCTAssertTrue(md.contains("| Property | Value |"))
        XCTAssertTrue(md.contains("Compression"))
    }

    /// Verifies EncodingReport JSON serialization.
    func test_encodingReport_json() throws {
        let report = EncodingReport(
            inputPath: "/tmp/source.mkv",
            inputFileSize: 100_000,
            inputDuration: 60,
            outputPath: "/tmp/output.mp4",
            outputFileSize: 50_000
        )
        let data = try report.toJSON()
        XCTAssertFalse(data.isEmpty)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("inputPath"))
        XCTAssertTrue(str.contains("outputFileSize"))
    }

    /// Verifies EncodingPerformance formatted time.
    func test_encodingPerformance_formattedTime() {
        let short = EncodingPerformance(totalTime: 45)
        XCTAssertEqual(short.formattedTime, "45s")

        let medium = EncodingPerformance(totalTime: 185)
        XCTAssertEqual(medium.formattedTime, "3m 5s")

        let long = EncodingPerformance(totalTime: 7325)
        XCTAssertEqual(long.formattedTime, "2h 2m 5s")
    }

    /// Verifies StreamReport construction.
    func test_streamReport_construction() {
        let stream = StreamReport(
            type: "video",
            codec: "h265",
            bitrate: 5_000_000,
            resolution: "3840x2160",
            frameRate: 23.976
        )
        XCTAssertEqual(stream.type, "video")
        XCTAssertEqual(stream.codec, "h265")
        XCTAssertEqual(stream.bitrate, 5_000_000)
        XCTAssertEqual(stream.resolution, "3840x2160")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.16: Content-Aware Encoding
    // -----------------------------------------------------------------

    /// Verifies content complexity CRF adjustments.
    func test_contentComplexity_crfAdjustment() {
        XCTAssertGreaterThan(ContentComplexity.veryLow.crfAdjustment, 0) // Less quality needed
        XCTAssertEqual(ContentComplexity.medium.crfAdjustment, 0) // Baseline
        XCTAssertLessThan(ContentComplexity.veryHigh.crfAdjustment, 0) // More quality needed
    }

    /// Verifies content complexity bitrate multipliers.
    func test_contentComplexity_bitrateMultiplier() {
        XCTAssertLessThan(ContentComplexity.veryLow.bitrateMultiplier, 1.0)
        XCTAssertEqual(ContentComplexity.medium.bitrateMultiplier, 1.0)
        XCTAssertGreaterThan(ContentComplexity.veryHigh.bitrateMultiplier, 1.0)
    }

    /// Verifies complexity classification from scores.
    func test_contentAnalyzer_classifyComplexity() {
        XCTAssertEqual(
            ContentAnalyzer.classifyComplexity(temporalComplexity: 0.05, spatialComplexity: 0.05),
            .veryLow
        )
        XCTAssertEqual(
            ContentAnalyzer.classifyComplexity(temporalComplexity: 0.5, spatialComplexity: 0.5),
            .medium
        )
        XCTAssertEqual(
            ContentAnalyzer.classifyComplexity(temporalComplexity: 0.9, spatialComplexity: 0.9),
            .veryHigh
        )
    }

    /// Verifies CRF adjustment clamping.
    func test_contentAnalyzer_adjustedCRF() {
        let config = ContentAwareConfig(minCRF: 16, maxCRF: 32, baselineCRF: 22)

        let simple = ContentAnalyzer.adjustedCRF(config: config, complexity: .veryLow)
        XCTAssertEqual(simple, 26) // 22 + 4

        let complex = ContentAnalyzer.adjustedCRF(config: config, complexity: .veryHigh)
        XCTAssertEqual(complex, 18) // 22 - 4

        // Test clamping
        let extreme = ContentAwareConfig(minCRF: 20, maxCRF: 24, baselineCRF: 22)
        XCTAssertEqual(ContentAnalyzer.adjustedCRF(config: extreme, complexity: .veryLow), 24)
        XCTAssertEqual(ContentAnalyzer.adjustedCRF(config: extreme, complexity: .veryHigh), 20)
    }

    /// Verifies content-aware encoder arguments for H.265.
    func test_contentAnalyzer_h265Arguments() {
        let config = ContentAwareConfig()
        let analysis = ContentAnalysisResult(
            overallComplexity: .high,
            contentType: .film
        )
        let args = ContentAnalyzer.buildEncoderArguments(
            config: config, analysis: analysis, codec: .h265
        )
        XCTAssertTrue(args.contains("-crf"))
        XCTAssertTrue(args.contains("-tune"))
        XCTAssertTrue(args.contains("film"))
    }

    /// Verifies content-aware encoder arguments for AV1 with film grain.
    func test_contentAnalyzer_av1FilmGrain() {
        let config = ContentAwareConfig(filmGrainSynthesis: true)
        let analysis = ContentAnalysisResult(
            segments: [
                SegmentAnalysis(startTime: 0, endTime: 10,
                    temporalComplexity: 0.5, spatialComplexity: 0.5, hasFilmGrain: true)
            ],
            overallComplexity: .medium
        )
        let args = ContentAnalyzer.buildEncoderArguments(
            config: config, analysis: analysis, codec: .av1
        )
        XCTAssertTrue(args.contains("-film-grain-denoise"))
    }

    /// Verifies disabled content-aware produces empty arguments.
    func test_contentAnalyzer_disabled() {
        let config = ContentAwareConfig(enabled: false)
        let analysis = ContentAnalysisResult()
        let args = ContentAnalyzer.buildEncoderArguments(
            config: config, analysis: analysis, codec: .h265
        )
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies ContentType encoder tunes.
    func test_contentType_encoderTune() {
        XCTAssertEqual(ContentType.film.encoderTune, "film")
        XCTAssertEqual(ContentType.animation.encoderTune, "animation")
        XCTAssertEqual(ContentType.screenContent.encoderTune, "stillimage")
        XCTAssertNil(ContentType.documentary.encoderTune)
    }

    /// Verifies ContentAnalysisResult computed properties.
    func test_contentAnalysisResult_averages() {
        let result = ContentAnalysisResult(
            segments: [
                SegmentAnalysis(startTime: 0, endTime: 5,
                    temporalComplexity: 0.2, spatialComplexity: 0.3),
                SegmentAnalysis(startTime: 5, endTime: 10,
                    temporalComplexity: 0.8, spatialComplexity: 0.7),
            ],
            overallComplexity: .medium
        )
        XCTAssertEqual(result.averageTemporalComplexity, 0.5, accuracy: 0.01)
        XCTAssertEqual(result.averageSpatialComplexity, 0.5, accuracy: 0.01)
    }

    /// Verifies analysis arguments construction.
    func test_contentAnalyzer_analysisArguments() {
        let args = ContentAnalyzer.buildAnalysisArguments(inputPath: "/tmp/video.mp4")
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        let vf = args.first { $0.contains("signalstats") }
        XCTAssertNotNil(vf)
    }

}
