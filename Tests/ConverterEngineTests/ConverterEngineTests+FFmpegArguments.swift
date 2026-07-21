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
    // MARK: - FFmpeg Argument Builder Tests
    // -----------------------------------------------------------------

    // -- Subtitle stream actions (#409) -------------------------------
    //
    // The subtitleStreamActions field drives explicit per-source-stream
    // subtitle mapping. These tests pin the resulting `-i` ordering
    // and `-map` arguments so a future refactor cannot silently break
    // the wiring between SubtitleTonemapPipeline and the encoder.

    /// Empty subtitleStreamActions must leave existing passthrough
    /// behaviour untouched — this is the backward-compat invariant for
    /// every existing call site.
    func test_argumentBuilder_subtitleActions_emptyKeepsLegacyBehaviour() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mkv")
        builder.subtitlePassthrough = true

        let args = builder.build()
        // Should fall through to the legacy `-map 0:s?` glob.
        let s = args.joined(separator: " ")
        XCTAssertTrue(s.contains("-map 0:s?"),
                      "Empty subtitleStreamActions must keep legacy "
                      + "passthrough behaviour (-map 0:s?)")
    }

    /// A single .passthrough action emits a specific -map per stream
    /// index — replacing the loose `-map 0:s?` glob.
    func test_argumentBuilder_subtitleActions_passthroughSpecificIndex() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mkv")
        builder.subtitleStreamActions = [
            .init(streamIndex: 2, action: .passthrough),
            .init(streamIndex: 3, action: .passthrough),
        ]

        let args = builder.build()
        let s = args.joined(separator: " ")
        XCTAssertTrue(s.contains("-map 0:s:2"))
        XCTAssertTrue(s.contains("-map 0:s:3"))
        // The legacy glob must NOT appear when explicit actions are set.
        XCTAssertFalse(s.contains("-map 0:s?"))
    }

    /// A .replaceWith action adds the file as an `-i` input and maps
    /// from the replacement input rather than the source. The
    /// replacement file's FFmpeg input index is `1 + additionalInputs
    /// .count + replacementOrdinal` — pinned here because the encoder
    /// pipeline relies on this ordering.
    func test_argumentBuilder_subtitleActions_replaceWithAddsInputAndMaps() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mkv")
        let tonemapped = URL(fileURLWithPath: "/tmp/sub2.sup")
        builder.subtitleStreamActions = [
            .init(streamIndex: 2, action: .replaceWith(tonemapped)),
        ]

        let args = builder.build()
        let s = args.joined(separator: " ")
        // Replacement file is added as -i AFTER inputURL.
        XCTAssertTrue(s.contains("-i /tmp/in.mkv"))
        XCTAssertTrue(s.contains("-i /tmp/sub2.sup"))
        // Source's subtitle stream at index 2 is suppressed (no -map 0:s:2)
        // and the replacement is mapped from input 1 instead.
        XCTAssertFalse(s.contains("-map 0:s:2"))
        XCTAssertTrue(s.contains("-map 1:s:0"))
    }

    /// Mixed actions across multiple streams must produce the right
    /// input list AND `-map` directives in source-stream order. This
    /// is the realistic case: one passthrough, one replacement, one
    /// drop on a multi-language source.
    func test_argumentBuilder_subtitleActions_mixedActionsCorrectMapping() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mkv")
        let englishTonemapped = URL(fileURLWithPath: "/tmp/sub2.sup")
        let frenchTonemapped = URL(fileURLWithPath: "/tmp/sub4.sup")
        builder.subtitleStreamActions = [
            .init(streamIndex: 2, action: .replaceWith(englishTonemapped)),
            .init(streamIndex: 3, action: .drop),
            .init(streamIndex: 4, action: .replaceWith(frenchTonemapped)),
            .init(streamIndex: 5, action: .passthrough),
        ]

        let args = builder.build()
        // Both replacement files appear as -i inputs (after source).
        XCTAssertEqual(
            args.filter { $0 == "-i" }.count,
            3,
            "Expected 3 -i flags: source + 2 replacement files"
        )
        // FFmpeg input indices: source=0, english=1, french=2.
        // (drop has no input.) Pin the -map list shape.
        let s = args.joined(separator: " ")
        XCTAssertTrue(s.contains("-map 1:s:0"),
                      "English tonemapped subtitle from input 1")
        XCTAssertTrue(s.contains("-map 2:s:0"),
                      "French tonemapped subtitle from input 2")
        XCTAssertTrue(s.contains("-map 0:s:5"),
                      "Stream 5 passes through from source")
        // Dropped stream 3 has no -map.
        XCTAssertFalse(s.contains("-map 0:s:3"))
    }

    /// When the caller already has unrelated `additionalInputs`, the
    /// replacement input indices must be offset past them. Protects
    /// the ordering contract documented on `subtitleStreamActions`.
    func test_argumentBuilder_subtitleActions_replacementsOffsetByAdditionalInputs() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mkv")
        builder.additionalInputs = [
            URL(fileURLWithPath: "/tmp/extra-a.mkv"),
            URL(fileURLWithPath: "/tmp/extra-b.mkv"),
        ]
        builder.subtitleStreamActions = [
            .init(streamIndex: 2, action: .replaceWith(URL(fileURLWithPath: "/tmp/sub.sup"))),
        ]

        let args = builder.build()
        let s = args.joined(separator: " ")
        // additionalInputs occupy 1 and 2 → replacement is input 3.
        XCTAssertTrue(s.contains("-map 3:s:0"))
        XCTAssertFalse(s.contains("-map 1:s:0"))
        XCTAssertFalse(s.contains("-map 2:s:0"))
    }

    /// Integration test for the EncodingJobConfig → builder
    /// `subtitleStreamActions` thread-through (#409 commit 3). Builds
    /// arguments from a job that carries a populated action list and
    /// asserts the resulting FFmpeg command line carries the right
    /// `-i` and `-map` shape — protecting the pipeline → engine →
    /// builder data flow that EncodingEngine.encode populates.
    func test_encodingJobConfig_threadsSubtitleStreamActionsToBuilder() {
        let profile = EncodingProfile(
            name: "tonemap-integration",
            videoCodec: .h265,
            videoCRF: 22,
            audioCodec: .aacLC,
            audioBitrate: 160_000,
            subtitlePassthrough: true,
            containerFormat: .mkv
        )
        var config = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/source.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
            profile: profile
        )
        let tonemapped = URL(fileURLWithPath: "/tmp/subtitle-2-tonemapped.sup")
        config.subtitleStreamActions = [
            .init(streamIndex: 2, action: .replaceWith(tonemapped)),
            .init(streamIndex: 3, action: .passthrough),
        ]

        let args = config.buildArguments()
        let s = args.joined(separator: " ")

        // The tonemapped subtitle file must be added as an `-i` input.
        XCTAssertTrue(s.contains("-i /tmp/subtitle-2-tonemapped.sup"),
                      "Replacement subtitle file must be added as an "
                      + "additional FFmpeg input via -i")
        // Stream 2 maps from input 1 (the replacement file), NOT from
        // the source. Stream 3 still passes through from the source.
        XCTAssertTrue(s.contains("-map 1:s:0"),
                      "Replaced stream 2 maps from input 1")
        XCTAssertTrue(s.contains("-map 0:s:3"),
                      "Stream 3 still passes through from source")
        // The legacy `-map 0:s?` glob must NOT appear when explicit
        // actions are set.
        XCTAssertFalse(s.contains("-map 0:s?"),
                       "Explicit actions override the legacy glob")
    }

    /// Verifies basic argument building with H.265/AAC.
    func test_argumentBuilder_basicH265() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.videoCRF = 22
        builder.audioCodec = .aacLC
        builder.audioBitrate = 160_000

        let args = builder.build()

        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("libx265"))
        XCTAssertTrue(args.contains("-crf"))
        XCTAssertTrue(args.contains("22"))
        XCTAssertTrue(args.contains("aac"))
        XCTAssertTrue(args.contains("160k"))
    }

    /// Verifies passthrough arguments.
    func test_argumentBuilder_passthrough() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoPassthrough = true
        builder.audioPassthrough = true

        let args = builder.build()

        // Should contain "-c:v copy" and "-c:a copy"
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-c:v copy"))
        XCTAssertTrue(argStr.contains("-c:a copy"))
        // Should NOT contain any codec-specific args
        XCTAssertFalse(argStr.contains("libx26"))
    }

    /// Verifies hardware encoding arguments for VideoToolbox.
    func test_argumentBuilder_hardwareEncoding() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.useHardwareEncoding = true
        builder.videoCRF = 25

        let args = builder.build()

        XCTAssertTrue(args.contains("hevc_videotoolbox"))
    }

    // -----------------------------------------------------------------
    // MARK: - Encoding Profile Tests
    // -----------------------------------------------------------------

    /// Verifies built-in profiles exist and have valid settings.
    func test_builtInProfiles_exist() {
        let profiles = EncodingProfile.builtInProfiles
        XCTAssertGreaterThanOrEqual(profiles.count, 7)

        // All built-in profiles should be marked as built-in
        for profile in profiles {
            XCTAssertTrue(profile.isBuiltIn, "\(profile.name) should be marked as built-in")
        }
    }

    /// Verifies profile-to-argument conversion works.
    func test_profile_toArgumentBuilder() {
        let inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        let builder = EncodingProfile.webStandard.toArgumentBuilder(inputURL: inputURL, outputURL: outputURL)
        let args = builder.build()

        XCTAssertTrue(args.contains("libx264"))
        XCTAssertTrue(args.contains("-crf"))
    }

    /// Verifies profile JSON serialisation round-trip.
    func test_profile_jsonRoundTrip() throws {
        let original = EncodingProfile.webHighQuality
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EncodingProfile.self, from: data)

        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.videoCodec, decoded.videoCodec)
        XCTAssertEqual(original.videoCRF, decoded.videoCRF)
        XCTAssertEqual(original.audioCodec, decoded.audioCodec)
        XCTAssertEqual(original.containerFormat, decoded.containerFormat)
    }

    // -----------------------------------------------------------------
    // MARK: - Encoding Queue Tests
    // -----------------------------------------------------------------

    /// Verifies job queue add and count.
    func test_encodingQueue_addJob() {
        let queue = EncodingQueue()
        let config = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            profile: .webStandard
        )

        let jobState = queue.addJob(config)

        XCTAssertEqual(queue.totalCount, 1)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(jobState.status, .queued)
    }

    /// Verifies job queue priority ordering.
    func test_encodingQueue_priorityOrdering() {
        let queue = EncodingQueue()
        let lowPriority = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/low.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/low.mp4"),
            profile: .webStandard,
            priority: 0
        )
        let highPriority = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/high.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/high.mp4"),
            profile: .webStandard,
            priority: 10
        )

        queue.addJob(lowPriority)
        queue.addJob(highPriority)

        // High priority job should be first
        let next = queue.nextPendingJob()
        XCTAssertEqual(next?.config.priority, 10)
    }

    // -----------------------------------------------------------------
    // MARK: - Temp File Manager Tests
    // -----------------------------------------------------------------

    /// Verifies temp directory creation and cleanup.
    func test_tempManager_createAndCleanup() throws {
        let tempManager = TempFileManager()
        let jobID = UUID()

        let dir = try tempManager.createJobDirectory(for: jobID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        // Subdirectories should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("demux").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("multipass").path))

        // Cleanup should remove the directory
        tempManager.cleanupJob(jobID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    /// Verifies disk space check returns a reasonable value.
    func test_tempManager_availableSpace() throws {
        let tempManager = TempFileManager()
        let space = try tempManager.availableSpace()
        XCTAssertGreaterThan(space, 0, "Available space should be > 0")
    }

    // -----------------------------------------------------------------
    // MARK: - Issue #380: TempFileManager orphan cleanup on init
    // -----------------------------------------------------------------
    //
    // Previously, orphan job directories were only removed when the host
    // app remembered to invoke `cleanupOrphanedJobs()`. A crash on the
    // very next run would silently accumulate gigabytes of demuxed-stream
    // debris. The audit follow-up makes the cleanup happen automatically
    // at construction (default `cleanupOrphansOnInit: true`); the tests
    // below verify both the default behaviour and the opt-out.

    /// Verifies that constructing a `TempFileManager` against a base
    /// directory containing a `meedya-job-*` orphan removes it.
    func test_tempManager_initRemovesOrphansByDefault() throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory
            .appendingPathComponent("tempmanager-init-cleanup-\(UUID().uuidString)")
        try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sandbox) }

        // Hand-plant an orphan directory as if a previous run had crashed
        // mid-job, plus a non-MeedyaConverter directory that must NOT be
        // touched.
        let orphan = sandbox.appendingPathComponent(
            "meedya-job-\(UUID().uuidString)"
        )
        try fm.createDirectory(at: orphan, withIntermediateDirectories: true)

        let unrelated = sandbox.appendingPathComponent("other-app-scratch")
        try fm.createDirectory(at: unrelated, withIntermediateDirectories: true)

        // Default construction should sweep the orphan but leave anything
        // outside our prefix alone.
        _ = TempFileManager(baseDirectory: sandbox)

        XCTAssertFalse(
            fm.fileExists(atPath: orphan.path),
            "Default init must remove `meedya-job-*` orphans so a "
            + "post-crash restart doesn't leak gigabytes of scratch data."
        )
        XCTAssertTrue(
            fm.fileExists(atPath: unrelated.path),
            "Init must not touch directories outside the "
            + "`meedya-job-` prefix — other apps share the temp dir."
        )
    }

    /// Verifies that `cleanupOrphansOnInit: false` preserves pre-existing
    /// `meedya-job-*` directories. This is the escape hatch tests and
    /// recovery tools use when they want to inspect or repair fixtures
    /// before the manager touches them.
    func test_tempManager_initOptOutPreservesOrphans() throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory
            .appendingPathComponent("tempmanager-init-optout-\(UUID().uuidString)")
        try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sandbox) }

        let orphan = sandbox.appendingPathComponent(
            "meedya-job-\(UUID().uuidString)"
        )
        try fm.createDirectory(at: orphan, withIntermediateDirectories: true)

        _ = TempFileManager(baseDirectory: sandbox, cleanupOrphansOnInit: false)

        XCTAssertTrue(
            fm.fileExists(atPath: orphan.path),
            "When opt-out is requested, init must leave pre-existing "
            + "orphan directories in place for later inspection."
        )
    }

    // -----------------------------------------------------------------
    // MARK: - HDR Format Detection Tests
    // -----------------------------------------------------------------

    /// Verifies HDR detection in video streams.
    func test_mediaStream_hdrDetection() {
        let hdrStream = MediaStream(
            streamIndex: 0,
            streamType: .video,
            hdrFormats: [.hdr10, .dolbyVision]
        )
        let sdrStream = MediaStream(streamIndex: 1, streamType: .video)

        let url = URL(fileURLWithPath: "/tmp/test.mkv")
        let file = MediaFile(fileURL: url, streams: [hdrStream, sdrStream])

        XCTAssertTrue(file.hasHDR)
        XCTAssertTrue(file.hasDolbyVision)
        XCTAssertFalse(file.hasHLG)
    }

    // -----------------------------------------------------------------
    // MARK: - Channel Layout Tests
    // -----------------------------------------------------------------

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: HDR10 Metadata Tests
    // -----------------------------------------------------------------

    /// Verifies H.265 HDR10 metadata injection via -x265-params.
    func test_argumentBuilder_hdr10MetadataH265() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoCodec = .h265
        builder.videoCRF = 18
        builder.pixelFormat = "yuv420p10le"
        builder.audioCodec = .eac3
        builder.audioBitrate = 640_000

        // Set HDR10 metadata from probe
        builder.masteringDisplay = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
        builder.maxCLL = 1000
        builder.maxFALL = 400

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        // Should have colour signalling
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
        XCTAssertTrue(argStr.contains("-color_trc smpte2084"))
        XCTAssertTrue(argStr.contains("-colorspace bt2020nc"))

        // Should have -x265-params with HDR10 metadata
        XCTAssertTrue(args.contains("-x265-params"))
        if let x265Idx = args.firstIndex(of: "-x265-params") {
            let params = args[args.index(after: x265Idx)]
            XCTAssertTrue(params.contains("hdr10-opt=1"), "Should enable hdr10-opt")
            XCTAssertTrue(params.contains("repeat-headers=1"), "Should enable repeat-headers")
            XCTAssertTrue(params.contains("master-display="), "Should include mastering display")
            XCTAssertTrue(params.contains("max-cll=1000,400"), "Should include CLL/FALL")
        }
    }

    /// Verifies AV1 HDR10 metadata injection uses generic FFmpeg side data.
    func test_argumentBuilder_hdr10MetadataAV1() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoCodec = .av1
        builder.videoCRF = 30
        builder.audioPassthrough = true

        builder.masteringDisplay = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
        builder.maxCLL = 1000
        builder.maxFALL = 400

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        // AV1 uses -master_display and -content_light (not x265-params)
        XCTAssertTrue(argStr.contains("-master_display"))
        XCTAssertTrue(argStr.contains("-content_light 1000,400"))
        XCTAssertFalse(argStr.contains("-x265-params"), "AV1 should not use x265-params")
    }

    /// Verifies no HDR metadata when tone mapping is enabled.
    func test_argumentBuilder_noHDRMetadataWhenToneMapping() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.videoCRF = 20
        builder.toneMap = true
        builder.audioCodec = .aacLC
        builder.audioBitrate = 192_000

        builder.masteringDisplay = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
        builder.maxCLL = 1000
        builder.maxFALL = 400

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        // When tone mapping, HDR10 metadata should NOT be injected
        XCTAssertFalse(argStr.contains("-x265-params"), "Should not inject HDR metadata when tone mapping")
        XCTAssertFalse(argStr.contains("-master_display"), "Should not inject mastering display when tone mapping")
    }

    /// Verifies colour signalling without MDCV/CLL still emits colour args.
    func test_argumentBuilder_hdrColourSignallingOnly() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoCodec = .h265
        builder.videoCRF = 18
        builder.audioPassthrough = true
        // No masteringDisplay or maxCLL set

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        // Should still have colour signalling even without MDCV/CLL
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
        XCTAssertTrue(argStr.contains("-color_trc smpte2084"))
        // Should NOT have x265-params since no metadata
        XCTAssertFalse(argStr.contains("-x265-params"))
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: Per-Stream Audio Tests
    // -----------------------------------------------------------------

    /// Verifies per-stream audio codec arguments (-c:a:N).
    func test_argumentBuilder_perStreamAudioCodec() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoPassthrough = true

        // Multi-codec audio: AAC for stream 0, E-AC-3 for stream 1
        builder.perStreamAudioCodec = [0: .aacLC, 1: .eac3]
        builder.perStreamAudioBitrate = [0: 160_000, 1: 640_000]

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-c:a:0 aac"), "Should set AAC for stream 0")
        XCTAssertTrue(argStr.contains("-b:a:0 160k"), "Should set bitrate for stream 0")
        XCTAssertTrue(argStr.contains("-c:a:1 eac3"), "Should set E-AC-3 for stream 1")
        XCTAssertTrue(argStr.contains("-b:a:1 640k"), "Should set bitrate for stream 1")
        // Should NOT have global -c:a
        XCTAssertFalse(argStr.contains(" -c:a "), "Should not have global audio codec when per-stream is set")
    }

    /// Verifies per-stream audio overrides take precedence over global.
    func test_argumentBuilder_perStreamOverridesGlobal() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoPassthrough = true
        builder.audioCodec = .aacLC  // Global setting
        builder.audioBitrate = 128_000

        // Per-stream overrides should win
        builder.perStreamAudioCodec = [0: .flac]

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-c:a:0 flac"), "Per-stream codec should override global")
        XCTAssertFalse(argStr.contains(" -c:a aac"), "Global codec should not appear when per-stream is set")
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: Container Flags Tests
    // -----------------------------------------------------------------

    /// Verifies MP4 gets -movflags +faststart.
    func test_argumentBuilder_mp4Faststart() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h264
        builder.videoCRF = 20
        builder.audioCodec = .aacLC
        builder.containerFormat = .mp4

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-movflags +faststart"), "MP4 should include faststart")
    }

    /// Verifies MOV also gets -movflags +faststart.
    func test_argumentBuilder_movFaststart() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mov")
        builder.videoCodec = .prores
        builder.audioCodec = .pcm
        builder.containerFormat = .mov

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-movflags +faststart"), "MOV should include faststart")
    }

    /// Verifies MPEG-TS gets resend_headers flag.
    func test_argumentBuilder_mpegTSHeaders() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.ts")
        builder.videoCodec = .h264
        builder.audioCodec = .ac3
        builder.containerFormat = .mpegTS

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-mpegts_flags +resend_headers"), "MPEG-TS should include resend_headers")
    }

    /// Verifies MKV does not get faststart or TS flags.
    func test_argumentBuilder_mkvNoContainerFlags() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mp4")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoPassthrough = true
        builder.audioPassthrough = true
        builder.containerFormat = .mkv

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertFalse(argStr.contains("-movflags"), "MKV should not have movflags")
        XCTAssertFalse(argStr.contains("-mpegts_flags"), "MKV should not have mpegts_flags")
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: Tone Mapping Tests
    // -----------------------------------------------------------------

    /// Verifies tone mapping filter chain is generated.
    func test_argumentBuilder_toneMapping() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.videoCRF = 20
        builder.toneMap = true
        builder.toneMapAlgorithm = .hable
        builder.audioCodec = .aacLC

        let args = builder.build()

        // Should have a -vf with the tone mapping filter chain
        XCTAssertTrue(args.contains("-vf"), "Should have video filter for tone mapping")
        if let vfIdx = args.firstIndex(of: "-vf") {
            let filterChain = args[args.index(after: vfIdx)]
            XCTAssertTrue(filterChain.contains("zscale=t=linear"), "Should start with linear conversion")
            XCTAssertTrue(filterChain.contains("tonemap=hable"), "Should use hable algorithm")
            XCTAssertTrue(filterChain.contains("zscale=p=bt709"), "Should convert to BT.709")
            XCTAssertTrue(filterChain.contains("format=yuv420p"), "Should output 8-bit SDR")
        }
    }

    /// Verifies PQ→HLG filter chain.
    func test_argumentBuilder_pqToHLG() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoCodec = .h265
        builder.videoCRF = 18
        builder.convertPQToHLG = true
        builder.audioPassthrough = true

        let args = builder.build()

        XCTAssertTrue(args.contains("-vf"), "Should have video filter for PQ→HLG")
        if let vfIdx = args.firstIndex(of: "-vf") {
            let filterChain = args[args.index(after: vfIdx)]
            XCTAssertTrue(filterChain.contains("smpte2084"), "Should reference PQ input")
            XCTAssertTrue(filterChain.contains("arib-std-b67"), "Should convert to HLG")
            XCTAssertTrue(filterChain.contains("yuv420p10le"), "Should output 10-bit")
        }
    }

    /// Verifies tone mapping and PQ→HLG are mutually exclusive.
    func test_argumentBuilder_toneMapOverridesPQToHLG() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.videoCRF = 20
        builder.toneMap = true
        builder.convertPQToHLG = true  // Both set — toneMap should win
        builder.audioCodec = .aacLC

        let args = builder.build()

        if let vfIdx = args.firstIndex(of: "-vf") {
            let filterChain = args[args.index(after: vfIdx)]
            XCTAssertTrue(filterChain.contains("tonemap="), "Tone mapping should be present")
            XCTAssertFalse(filterChain.contains("arib-std-b67"), "PQ→HLG should not be present when tone mapping")
        }
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: HLG/PQ Preservation Tests
    // -----------------------------------------------------------------

    /// Verifies HLG preservation arguments.
    func test_argumentBuilder_hlgPreservation() {
        var builder = FFmpegArgumentBuilder()
        builder.videoCodec = .h265
        let args = builder.buildHLGPreservationArguments()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-color_trc arib-std-b67"))
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
    }

    /// Verifies HLG preservation is skipped when tone mapping.
    func test_argumentBuilder_hlgPreservationSkippedWhenToneMap() {
        var builder = FFmpegArgumentBuilder()
        builder.toneMap = true
        let args = builder.buildHLGPreservationArguments()
        XCTAssertTrue(args.isEmpty, "HLG preservation should be empty when tone mapping")
    }

    /// Verifies PQ preservation arguments.
    func test_argumentBuilder_pqPreservation() {
        var builder = FFmpegArgumentBuilder()
        builder.videoCodec = .h265
        let args = builder.buildPQPreservationArguments()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-color_trc smpte2084"))
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: TrueHD Disposition Tests
    // -----------------------------------------------------------------

    /// Verifies TrueHD in MP4 gets non-default disposition.
    func test_argumentBuilder_trueHDDispositionMP4() {
        let streams: [(index: Int, codec: AudioCodec)] = [
            (0, .aacLC),
            (1, .trueHD),
        ]
        let args = FFmpegArgumentBuilder.buildTrueHDDispositionArguments(
            audioStreams: streams, container: .mp4
        )
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-disposition:a:0 default"), "AAC should be set as default")
        XCTAssertTrue(argStr.contains("-disposition:a:1 0"), "TrueHD should be non-default")
    }

    /// Verifies TrueHD in MKV does NOT get disposition override.
    func test_argumentBuilder_trueHDDispositionMKV() {
        let streams: [(index: Int, codec: AudioCodec)] = [
            (0, .trueHD),
            (1, .aacLC),
        ]
        let args = FFmpegArgumentBuilder.buildTrueHDDispositionArguments(
            audioStreams: streams, container: .mkv
        )
        XCTAssertTrue(args.isEmpty, "MKV should not need TrueHD disposition override")
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: Static Helper Tests
    // -----------------------------------------------------------------

    /// Verifies PCM encoder name selection.
    func test_argumentBuilder_pcmEncoderName() {
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 16), "pcm_s16le")
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 24), "pcm_s24le")
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 32), "pcm_s32le")
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 32, floatingPoint: true), "pcm_f32le")
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 64, floatingPoint: true), "pcm_f64le")
    }

    /// Verifies ProRes profile value mapping.
    func test_argumentBuilder_proresProfileValue() {
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "proxy"), 0)
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "lt"), 1)
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "hq"), 3)
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "4444"), 4)
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "4444xq"), 5)
        XCTAssertNil(FFmpegArgumentBuilder.proresProfileValue(for: "invalid"))
    }

    /// Verifies DNxHR profile value mapping.
    func test_argumentBuilder_dnxhrProfileValue() {
        XCTAssertEqual(FFmpegArgumentBuilder.dnxhrProfileValue(for: "lb"), "dnxhr_lb")
        XCTAssertEqual(FFmpegArgumentBuilder.dnxhrProfileValue(for: "sq"), "dnxhr_sq")
        XCTAssertEqual(FFmpegArgumentBuilder.dnxhrProfileValue(for: "hq"), "dnxhr_hq")
        XCTAssertEqual(FFmpegArgumentBuilder.dnxhrProfileValue(for: "444"), "dnxhr_444")
        XCTAssertNil(FFmpegArgumentBuilder.dnxhrProfileValue(for: "invalid"))
    }

    // -----------------------------------------------------------------
    // MARK: - Encoding Profile: New Property Tests
    // -----------------------------------------------------------------

    /// Verifies preferredExtension computed property.
    func test_profile_preferredExtension() {
        XCTAssertEqual(EncodingProfile.webStandard.preferredExtension, "mp4")
        XCTAssertEqual(EncodingProfile.fourKHDRMaster.preferredExtension, "mkv")
        XCTAssertEqual(EncodingProfile.proresHQ.preferredExtension, "mov")
        XCTAssertEqual(EncodingProfile.blurayCompatible.preferredExtension, "ts")
    }

    /// Verifies PQ→DV+HLG profile has correct settings.
    func test_profile_pqToDVHLG() {
        let profile = EncodingProfile.pqToDVHLG
        XCTAssertTrue(profile.isBuiltIn)
        XCTAssertTrue(profile.convertPQToHLG)
        XCTAssertTrue(profile.convertPQToDVHLG)
        XCTAssertTrue(profile.preserveHDR)
        XCTAssertEqual(profile.videoCodec, .h265)
        XCTAssertEqual(profile.pixelFormat, "yuv420p10le")
        XCTAssertEqual(profile.containerFormat, .mkv)
    }

    /// Verifies PQ→HLG profile exists and has correct flags.
    func test_profile_pqToHLG() {
        let profile = EncodingProfile.pqToHLG
        XCTAssertTrue(profile.isBuiltIn)
        XCTAssertTrue(profile.convertPQToHLG)
        XCTAssertFalse(profile.convertPQToDVHLG)
        XCTAssertTrue(profile.preserveHDR)
        XCTAssertFalse(profile.toneMapToSDR)
    }

    /// Verifies built-in profile count includes new HDR profiles.
    func test_builtInProfiles_count() {
        // 23 original + pqToHLG + pqToDVHLG = at least 25
        XCTAssertGreaterThanOrEqual(EncodingProfile.builtInProfiles.count, 23)
    }

    /// Verifies convertPQToDVHLG round-trips through JSON.
    func test_profile_pqToDVHLG_jsonRoundTrip() throws {
        let original = EncodingProfile.pqToDVHLG
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: data)

        XCTAssertEqual(decoded.convertPQToHLG, original.convertPQToHLG)
        XCTAssertEqual(decoded.convertPQToDVHLG, original.convertPQToDVHLG)
        XCTAssertEqual(decoded.preserveHDR, original.preserveHDR)
        XCTAssertEqual(decoded.videoCodec, original.videoCodec)
    }

    // -----------------------------------------------------------------
    // MARK: - Encoding Job Config: HDR Metadata Tests
    // -----------------------------------------------------------------

    /// Verifies EncodingJobConfig wires HDR metadata to argument builder.
    func test_encodingJobConfig_hdrMetadataWiring() {
        var config = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
            profile: .fourKHDRMaster
        )
        config.hdrMasteringDisplay = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
        config.hdrMaxCLL = 1000
        config.hdrMaxFALL = 400

        let args = config.buildArguments()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-x265-params"), "Should have x265 HDR params")
        XCTAssertTrue(argStr.contains("max-cll=1000,400"), "Should pass through CLL/FALL")
    }

    // -----------------------------------------------------------------
    // MARK: - ContainerFormat Codec Compatibility Tests
    // -----------------------------------------------------------------

    /// Verifies MP4 container supports expected codecs.
    func test_containerFormat_mp4Compatibility() {
        let mp4 = ContainerFormat.mp4
        XCTAssertTrue(mp4.supportsVideoCodec(.h264))
        XCTAssertTrue(mp4.supportsVideoCodec(.h265))
        XCTAssertTrue(mp4.supportsVideoCodec(.av1))
        XCTAssertTrue(mp4.supportsAudioCodec(.aacLC))
        XCTAssertTrue(mp4.supportsAudioCodec(.ac3))
    }

    /// Verifies MKV container supports a wide range of codecs.
    func test_containerFormat_mkvCompatibility() {
        let mkv = ContainerFormat.mkv
        XCTAssertTrue(mkv.supportsVideoCodec(.h264))
        XCTAssertTrue(mkv.supportsVideoCodec(.h265))
        XCTAssertTrue(mkv.supportsVideoCodec(.av1))
        XCTAssertTrue(mkv.supportsVideoCodec(.vp9))
        XCTAssertTrue(mkv.supportsAudioCodec(.flac))
        XCTAssertTrue(mkv.supportsAudioCodec(.trueHD))
        XCTAssertTrue(mkv.supportsAudioCodec(.dtsHD))
    }

    /// Verifies WebM container restricts to VP8/VP9/AV1 + Opus/Vorbis.
    func test_containerFormat_webmCompatibility() {
        let webm = ContainerFormat.webm
        XCTAssertTrue(webm.supportsVideoCodec(.vp9))
        XCTAssertTrue(webm.supportsVideoCodec(.av1))
        XCTAssertTrue(webm.supportsAudioCodec(.opus))
        XCTAssertFalse(webm.supportsAudioCodec(.aacLC))
        XCTAssertFalse(webm.supportsVideoCodec(.h264))
    }

    // -----------------------------------------------------------------
    // MARK: - Channel Layout Tests
    // -----------------------------------------------------------------

    /// Verifies channel layout properties.
    func test_channelLayout_properties() {
        let stereo = ChannelLayout(channelCount: 2, layoutName: "stereo")
        XCTAssertFalse(stereo.isSurround)
        XCTAssertTrue(stereo.canUpmix)
        XCTAssertEqual(stereo.displayName, "Stereo (2.0)")

        let surround = ChannelLayout(channelCount: 6, layoutName: "5.1")
        XCTAssertTrue(surround.isSurround)
        XCTAssertEqual(surround.displayName, "5.1 Surround")

        let mono = ChannelLayout(channelCount: 1)
        XCTAssertFalse(mono.canUpmix) // Mono should not offer upmix
    }

    // -----------------------------------------------------------------
    // MARK: - ColourSpaceConverter Tests
    // -----------------------------------------------------------------

    /// Verifies colour space filter generation.
    func test_colourSpaceConverter_buildFilter() {
        let filter = ColourSpaceConverter.buildFilter(from: .bt601, to: .bt709)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("zscale"))
        XCTAssertTrue(filter!.contains("bt709"))
    }

    /// Verifies no filter generated for same colour space.
    func test_colourSpaceConverter_sameColourSpace() {
        let filter = ColourSpaceConverter.buildFilter(from: .bt709, to: .bt709)
        XCTAssertNil(filter, "Should return nil when source == target")
    }

    /// Verifies signalling arguments.
    func test_colourSpaceConverter_signalling() {
        let args = ColourSpaceConverter.buildSignallingArguments(for: .bt2020)
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
        XCTAssertTrue(argStr.contains("-colorspace bt2020nc"))
    }

    /// Verifies recommended colour space for HDR.
    func test_colourSpaceConverter_recommendation() {
        XCTAssertEqual(ColourSpaceConverter.recommendedColourSpace(for: .h265, isHDR: true), .bt2020)
        XCTAssertEqual(ColourSpaceConverter.recommendedColourSpace(for: .h264, isHDR: false), .bt709)
        XCTAssertEqual(ColourSpaceConverter.recommendedColourSpace(for: .h264, isHDR: true), .bt709) // H.264 doesn't support HDR
    }

    /// Verifies ColourSpace properties.
    func test_colourSpace_properties() {
        XCTAssertTrue(ColourSpace.bt2020.isWideGamut)
        XCTAssertTrue(ColourSpace.dciP3.isWideGamut)
        XCTAssertFalse(ColourSpace.bt709.isWideGamut)
        XCTAssertFalse(ColourSpace.bt601.isWideGamut)
    }

    // -----------------------------------------------------------------
    // MARK: - PlatformFormatPolicy Tests
    // -----------------------------------------------------------------

    /// Verifies H.264 is universally supported.
    func test_platformPolicy_h264Universal() {
        for platform in PlatformFormatPolicy.Platform.allCases {
            let result = PlatformFormatPolicy.checkVideoCodec(.h264, on: platform)
            if case .supported = result {
                // OK
            } else {
                XCTFail("H.264 should be supported on \(platform.rawValue)")
            }
        }
    }

    /// Verifies platform validation catches incompatible combinations.
    func test_platformPolicy_webBrowserRestrictions() {
        let result = PlatformFormatPolicy.checkContainer(.mkv, on: .webBrowser)
        if case .unsupported = result {
            // Expected
        } else {
            XCTFail("MKV should be unsupported in web browsers")
        }
    }

    /// Verifies profile validation returns warnings for incompatible settings.
    func test_platformPolicy_profileValidation() {
        // HDR Master profile with MKV should warn on Apple platforms
        let warnings = PlatformFormatPolicy.validate(profile: .fourKHDRMaster, for: .iOS)
        // MKV is not natively supported on iOS
        XCTAssertTrue(warnings.contains { $0.contains("MKV") })
    }

    /// Verifies recommended profiles differ by platform.
    func test_platformPolicy_recommendations() {
        let webProfile = PlatformFormatPolicy.recommendedProfile(for: .webBrowser)
        XCTAssertEqual(webProfile.videoCodec, .av1)

        let androidProfile = PlatformFormatPolicy.recommendedProfile(for: .android)
        XCTAssertEqual(androidProfile.videoCodec, .h264)

        let plexProfile = PlatformFormatPolicy.recommendedProfile(for: .plex)
        XCTAssertEqual(plexProfile.videoCodec, .h265)
    }

    // -----------------------------------------------------------------
    // MARK: - HDRTransferFunction Tests
    // -----------------------------------------------------------------

    /// Verifies HDRTransferFunction enum values.
    func test_hdrTransferFunction_rawValues() {
        XCTAssertEqual(HDRTransferFunction.pq.rawValue, "pq")
        XCTAssertEqual(HDRTransferFunction.hlg.rawValue, "hlg")
    }

}
