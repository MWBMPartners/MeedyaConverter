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
    // MARK: - RenderFarm settings + agent registry (#346 / #381 / #406)

    /// `RenderFarmTransport` rawValues are persisted as part of the
    /// agent JSON blob. A rename on the engine side would silently
    /// invalidate every user's persisted agent list — pin them.
    func test_renderFarmTransport_rawValuesAreStableForAppStorage() {
        XCTAssertEqual(RenderFarmTransport.ssh.rawValue, "ssh")
        XCTAssertEqual(RenderFarmTransport.tls.rawValue, "tls")
        XCTAssertEqual(RenderFarmTransport.plainHTTP.rawValue, "plainHTTP")
    }

    /// The `RenderFarmSettingsTab` agent list is stored as JSON-encoded
    /// `[RenderFarmAgentInfo]` in an `@AppStorage` `Data` blob. Verify
    /// the round-trip preserves every field — including the `id` and
    /// `discovered` flags that drive UI behaviour (deletable vs not,
    /// "Discovered"/"Manual" badge).
    func test_renderFarmAgentInfo_jsonRoundTripPreservesAllFields() throws {
        let original = RenderFarmAgentInfo(
            displayName: "studio-tower",
            host: "192.168.1.42",
            port: 2229,
            sshUsername: "render",
            discovered: false,
            architecture: "arm64",
            hardwareEncoders: ["videotoolbox", "nvenc"]
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder()
            .decode([RenderFarmAgentInfo].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, original.id)
        XCTAssertEqual(decoded[0].displayName, "studio-tower")
        XCTAssertEqual(decoded[0].host, "192.168.1.42")
        XCTAssertEqual(decoded[0].port, 2229)
        XCTAssertEqual(decoded[0].sshUsername, "render")
        XCTAssertFalse(decoded[0].discovered)
        XCTAssertEqual(decoded[0].architecture, "arm64")
        XCTAssertEqual(decoded[0].hardwareEncoders, ["videotoolbox", "nvenc"])
    }

    /// The UI persists chunk size as user-facing MiB (1/4/16/64) and
    /// converts to bytes when the consumer constructs the engine
    /// Configuration. Verify the conversion + that the engine's
    /// `defaultChunkSizeBytes` matches the UI default of 4 MiB so
    /// the two sides agree out of the box.
    func test_renderFarm_chunkSizeMiBToBytesConversion() {
        XCTAssertEqual(UInt64(4) * 1024 * 1024,
                       RenderFarmProtocol.defaultChunkSizeBytes,
                       "UI default of 4 MiB must equal the engine's "
                       + "RenderFarmProtocol.defaultChunkSizeBytes "
                       + "so engine consumers reading the AppStorage "
                       + "value behave identically when the user has "
                       + "never touched the setting.")
    }

    /// Verifies the UI's "empty data → empty agent list" behaviour
    /// against the actual JSON decoder. An empty `@AppStorage("renderFarm.agentsJSON")`
    /// value is the user's initial state (no key written yet); the UI
    /// surfaces this as the "No agents configured" empty state.
    func test_renderFarmAgentInfo_emptyDataDecodesToEmptyList() {
        let empty = Data()
        let decoded = try? JSONDecoder()
            .decode([RenderFarmAgentInfo].self, from: empty)
        XCTAssertNil(decoded,
                     "Empty Data should fail to decode as a JSON array; "
                     + "the UI binding catches the failure and surfaces "
                     + "an empty list.")
    }

    // MARK: - ProResToVectorConfig + ProResVectorView (#377 / #381 / #404)

    /// `ProResVectorView` persists its enum fields as their rawValue
    /// `String`s via `@AppStorage`. Pin the rawValues so a rename on
    /// the engine side doesn't silently invalidate every user's
    /// persisted preference.
    func test_proResEnums_rawValuesAreStableForAppStorage() {
        XCTAssertEqual(ProResVariant.proRes4444.rawValue, "prores_4444")
        XCTAssertEqual(ProResVariant.proRes4444XQ.rawValue, "prores_4444_xq")
        XCTAssertEqual(ProResVariant.proRes4444HDR.rawValue, "prores_4444_hdr")

        XCTAssertEqual(ProResFrameRate.fps23_976.rawValue, "23.976")
        XCTAssertEqual(ProResFrameRate.fps24.rawValue, "24")
        XCTAssertEqual(ProResFrameRate.fps29_97.rawValue, "29.97")
        XCTAssertEqual(ProResFrameRate.fps59_94.rawValue, "59.94")

        XCTAssertEqual(ProResAlphaHandling.preservePerFrame.rawValue, "preserve_per_frame")
        XCTAssertEqual(ProResAlphaHandling.alphaMatteOnly.rawValue, "alpha_matte_only")
        XCTAssertEqual(ProResAlphaHandling.flatten.rawValue, "flatten")
    }

    /// Pins the engine's `ProResToVectorConfig` default-init against the
    /// AppStorage defaults baked into `ProResVectorView`. Drift would
    /// mean a user who never opens the view gets a different config
    /// than an engine consumer using the type's defaults.
    func test_proResToVectorConfig_defaultsMatchUIAppStorage() {
        let defaults = ProResToVectorConfig()
        XCTAssertEqual(defaults.sourceVariant, .proRes4444)
        XCTAssertEqual(defaults.frameRate, .fps24)
        XCTAssertNil(defaults.startTimeSeconds,
                     "UI sentinel of 0 maps to engine nil (clip start)")
        XCTAssertNil(defaults.endTimeSeconds,
                     "UI sentinel of -1 maps to engine nil (until end of clip)")
        XCTAssertEqual(defaults.frameStride, 1)
        XCTAssertEqual(defaults.alphaHandling, .preservePerFrame)
        XCTAssertEqual(defaults.animation, .smil)
        XCTAssertTrue(defaults.shapePersistence)
        XCTAssertTrue(defaults.keyframeExtraction)
    }

    /// `ProResVectorView`'s warning callout uses the engine's
    /// `shouldWarnAboutOutputSize(...)` helper. Verify the helper fires
    /// when settings select photorealistic tracing regardless of length,
    /// AND when the projected effective duration exceeds the engine's
    /// recommended cap.
    func test_proResToVector_outputSizeWarning_firesAsExpected() {
        let cap = ProResToVectorConverter.recommendedMaxDurationSeconds

        // Case A — photorealistic tracing always fires the warning.
        var configA = ProResToVectorConfig()
        configA.tracing.tracingMode = .photorealistic
        XCTAssertTrue(
            ProResToVectorConverter.shouldWarnAboutOutputSize(
                config: configA,
                sourceDurationSeconds: 1.0
            ),
            "Photorealistic tracing must fire the warning regardless "
            + "of source duration."
        )

        // Case B — non-photorealistic tracing on a short clip does NOT fire.
        var configB = ProResToVectorConfig()
        configB.tracing.tracingMode = .outline
        XCTAssertFalse(
            ProResToVectorConverter.shouldWarnAboutOutputSize(
                config: configB,
                sourceDurationSeconds: cap / 2
            ),
            "Outline tracing on a sub-cap clip must not fire the warning."
        )

        // Case C — non-photorealistic tracing on a long clip fires.
        XCTAssertTrue(
            ProResToVectorConverter.shouldWarnAboutOutputSize(
                config: configB,
                sourceDurationSeconds: cap * 3
            ),
            "Effective duration past the recommended cap must fire the "
            + "warning even for cheap tracing modes."
        )
    }

    // MARK: - RasterToVectorConfig + VectorConversionView (#376 / #381 / #402)

    /// Pins the per-preset auto-drive table that `VectorConversionView`'s
    /// `applyPreset(_:)` relies on. If the engine adds, removes, or
    /// re-labels a preset, this test fails immediately rather than
    /// leaving the UI silently broken.
    func test_editabilityPreset_defaultTracingModeAndColorCount() {
        XCTAssertEqual(EditabilityPreset.logoIcon.defaultTracingMode, .outline)
        XCTAssertEqual(EditabilityPreset.logoIcon.defaultColorCount, 8)

        XCTAssertEqual(EditabilityPreset.illustration.defaultTracingMode, .colorQuantization)
        XCTAssertEqual(EditabilityPreset.illustration.defaultColorCount, 32)

        XCTAssertEqual(EditabilityPreset.photorealistic.defaultTracingMode, .photorealistic)
        XCTAssertEqual(EditabilityPreset.photorealistic.defaultColorCount, 256)

        XCTAssertEqual(EditabilityPreset.technicalDiagram.defaultTracingMode, .outline)
        XCTAssertEqual(EditabilityPreset.technicalDiagram.defaultColorCount, 4)

        XCTAssertEqual(EditabilityPreset.handDrawnSketch.defaultTracingMode, .colorQuantization)
        XCTAssertEqual(EditabilityPreset.handDrawnSketch.defaultColorCount, 16)
    }

    /// Verifies every enum the UI reads from has stable rawValues for
    /// `@AppStorage` persistence. A rename in the engine would otherwise
    /// silently invalidate every user's persisted preference.
    func test_rasterToVectorEnums_rawValuesAreStableForAppStorage() {
        // Pinned values match the UI AppStorage default strings in
        // VectorConversionView.swift.
        XCTAssertEqual(RasterFormat.png.rawValue, "png")
        XCTAssertEqual(EditabilityPreset.illustration.rawValue, "illustration")
        XCTAssertEqual(TracingMode.colorQuantization.rawValue, "color_quantization")
        XCTAssertEqual(AlphaStrategy.clipPathWithOpacity.rawValue, "clip_path_with_opacity")
        XCTAssertEqual(AnimationMethod.smil.rawValue, "smil")
    }

    /// Verifies the engine's `RasterToVectorConfig` default-init agrees
    /// with the AppStorage defaults the UI installs on first launch.
    /// Drift between the two would mean a user who never opens the view
    /// gets a different config than an engine consumer using the
    /// type's defaults.
    func test_rasterToVectorConfig_defaultsMatchUIAppStorage() {
        let defaults = RasterToVectorConfig(inputFormat: .png)
        XCTAssertEqual(defaults.preset, .illustration)
        XCTAssertEqual(defaults.tracingMode, .colorQuantization)
        XCTAssertEqual(defaults.colorCount, 32,
                       "illustration preset.defaultColorCount is 32")
        XCTAssertEqual(defaults.alpha, .clipPathWithOpacity)
        XCTAssertEqual(defaults.animation, .smil)
        XCTAssertTrue(defaults.preserveMetadata)
        XCTAssertFalse(defaults.ocrTextRegions)
        XCTAssertEqual(defaults.curveSimplification, 2.0)
    }

    /// `RasterFormat.isAnimated` drives whether the UI shows the
    /// Animation section. Pin the animated set so a future addition
    /// of e.g. `.heicSequence` doesn't sneak past the static-only path.
    func test_rasterFormat_isAnimatedMatchesUIExpectations() {
        XCTAssertTrue(RasterFormat.gif.isAnimated)
        XCTAssertTrue(RasterFormat.apng.isAnimated)
        XCTAssertTrue(RasterFormat.webp.isAnimated)
        // Common single-frame formats must NOT be flagged animated —
        // otherwise the UI would show a meaningless animation picker.
        XCTAssertFalse(RasterFormat.png.isAnimated)
        XCTAssertFalse(RasterFormat.jpeg.isAnimated)
        XCTAssertFalse(RasterFormat.tiff.isAnimated)
    }

    // MARK: - AccurateRip SubmissionConfig (#381 / #400)

    /// Pins the `AccurateRipVerifier.SubmissionConfig` default-initialised
    /// values against the AppStorage defaults baked into
    /// `AccurateRipSettingsTab`. The UI assumes that constructing a
    /// `SubmissionConfig()` with no arguments produces the same values
    /// the AppStorage keys default to — drift between the two would mean
    /// a user who has never opened the settings tab gets a config that
    /// silently differs from what an engine consumer using the type's
    /// default-init would produce.
    func test_accurateRipSubmissionConfig_defaultsMatchUIAppStorage() {
        let defaults = AccurateRipVerifier.SubmissionConfig()
        XCTAssertFalse(defaults.enabled,
                       "UI master toggle defaults to off — opt-in only")
        XCTAssertEqual(defaults.driveModel, "",
                       "UI driveModel TextField defaults to empty")
        XCTAssertEqual(defaults.driveOffset, 0,
                       "UI driveOffset Stepper defaults to 0")
        XCTAssertEqual(defaults.softwareId, "MeedyaConverter",
                       "UI softwareId TextField defaults to 'MeedyaConverter'")
    }

    /// Verifies the SubmissionConfig round-trips through JSON. The four
    /// AppStorage keys persist the individual fields separately, but a
    /// future migration that stores the assembled struct as a single
    /// JSON blob (or pushes it to a remote profile sync) needs this to
    /// keep working. Pin it now.
    func test_accurateRipSubmissionConfig_codableRoundTrip() throws {
        let original = AccurateRipVerifier.SubmissionConfig(
            enabled: true,
            driveModel: "PIONEER BD-RW BDR-XS07",
            driveOffset: 102,
            softwareId: "MeedyaConverter"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder()
            .decode(AccurateRipVerifier.SubmissionConfig.self, from: data)
        XCTAssertEqual(decoded.enabled, true)
        XCTAssertEqual(decoded.driveModel, "PIONEER BD-RW BDR-XS07")
        XCTAssertEqual(decoded.driveOffset, 102)
        XCTAssertEqual(decoded.softwareId, "MeedyaConverter")
    }

    // MARK: - SuiteCoreMetadataBackend (#371 / #381 / #398)

    /// `SuiteCoreMetadataBackend` is persisted as its rawValue String via
    /// `@AppStorage("metadataBackend")` in the SettingsView. Pin the three
    /// expected rawValues so a rename in the engine doesn't silently
    /// invalidate every user's persisted preference at next launch.
    func test_suiteCoreMetadataBackend_rawValuesAreStableForAppStorage() {
        XCTAssertEqual(SuiteCoreMetadataBackend.automatic.rawValue, "automatic")
        XCTAssertEqual(SuiteCoreMetadataBackend.suiteCore.rawValue, "suiteCore")
        XCTAssertEqual(SuiteCoreMetadataBackend.inlineOnly.rawValue, "inlineOnly")
    }

    /// Verifies that all three cases round-trip through their rawValue,
    /// which is what the UI's AppStorage binding relies on. If a future
    /// case is added without a stable rawValue, this test catches it.
    func test_suiteCoreMetadataBackend_allCasesRoundTripThroughRawValue() {
        for backend in SuiteCoreMetadataBackend.allCases {
            let raw = backend.rawValue
            let recovered = SuiteCoreMetadataBackend(rawValue: raw)
            XCTAssertEqual(recovered, backend,
                           "Backend \(backend) does not round-trip via "
                           + "rawValue '\(raw)'")
        }
    }

    /// The UI falls back to `.automatic` when AppStorage contains an
    /// unrecognised rawValue (e.g. a value written by a future build that
    /// added a case this one doesn't know). Verify the parsing behaviour
    /// this fallback depends on.
    func test_suiteCoreMetadataBackend_unknownRawValueReturnsNil() {
        XCTAssertNil(SuiteCoreMetadataBackend(rawValue: "futureBackendName"))
        XCTAssertNil(SuiteCoreMetadataBackend(rawValue: ""))
    }

    // MARK: - SubtitleTonemapPipeline (#369 follow-up)

    /// Codec → extension mapping is the entry-point of the whole
    /// pipeline; pin the supported codecs explicitly so a future
    /// engine-side change can't silently break the call site.
    func test_subtitleTonemapPipeline_codecToExtensionMapping() {
        // Supported codecs.
        XCTAssertEqual(
            SubtitleTonemapPipeline.subtitleFileExtension(forCodec: "hdmv_pgs_subtitle"),
            "sup"
        )
        XCTAssertEqual(
            SubtitleTonemapPipeline.subtitleFileExtension(forCodec: "pgs"),
            "sup"
        )
        XCTAssertEqual(
            SubtitleTonemapPipeline.subtitleFileExtension(forCodec: "ass"),
            "ass"
        )
        XCTAssertEqual(
            SubtitleTonemapPipeline.subtitleFileExtension(forCodec: "ssa"),
            "ass"
        )
        // Case-insensitive lookup.
        XCTAssertEqual(
            SubtitleTonemapPipeline.subtitleFileExtension(forCodec: "HDMV_PGS_SUBTITLE"),
            "sup"
        )
        // Deferred / unsupported codecs return nil so the pipeline
        // skips them rather than producing garbage output.
        XCTAssertNil(SubtitleTonemapPipeline.subtitleFileExtension(forCodec: "dvd_subtitle"))
        XCTAssertNil(SubtitleTonemapPipeline.subtitleFileExtension(forCodec: "vobsub"))
        XCTAssertNil(SubtitleTonemapPipeline.subtitleFileExtension(forCodec: "dvb_subtitle"))
        XCTAssertNil(SubtitleTonemapPipeline.subtitleFileExtension(forCodec: "srt"))
    }

    /// Candidate selection: each short-circuit must produce an empty
    /// list. These are the four early-return cases that protect SDR
    /// encodes from accidentally invoking a binary they don't need.
    func test_subtitleTonemapPipeline_candidateStreams_shortCircuits() {
        let url = URL(fileURLWithPath: "/tmp/test.mkv")
        let pgsSub = MediaStream(
            streamIndex: 2,
            streamType: .subtitle,
            codecName: "hdmv_pgs_subtitle"
        )
        let hdrVideo = MediaStream(
            streamIndex: 0,
            streamType: .video,
            hdrFormats: [.hdr10]
        )
        let file = MediaFile(
            fileURL: url,
            streams: [hdrVideo, pgsSub]
        )
        let cfg = SubtitleTonemapConfig()

        // 1. nil config → user has not opted in.
        XCTAssertEqual(
            SubtitleTonemapPipeline.candidateStreams(
                in: file, config: nil, wrapperAvailable: true
            ).count,
            0
        )

        // 2. SDR source → nothing to tone-map against.
        let sdrVideo = MediaStream(streamIndex: 0, streamType: .video)
        let sdrFile = MediaFile(fileURL: url, streams: [sdrVideo, pgsSub])
        XCTAssertEqual(
            SubtitleTonemapPipeline.candidateStreams(
                in: sdrFile, config: cfg, wrapperAvailable: true
            ).count,
            0
        )

        // 3. Wrapper binary unavailable → skip rather than fail.
        XCTAssertEqual(
            SubtitleTonemapPipeline.candidateStreams(
                in: file, config: cfg, wrapperAvailable: false
            ).count,
            0
        )

        // 4. All preconditions met → returns the candidate.
        let candidates = SubtitleTonemapPipeline.candidateStreams(
            in: file, config: cfg, wrapperAvailable: true
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.streamIndex, 2)
    }

    /// Codec filtering: a file with a mix of supported and unsupported
    /// subtitle codecs should yield only the supported ones, preserving
    /// source order. Protects the assumption that the pipeline emits a
    /// 1:1 correspondence with the actually-tonemappable streams.
    func test_subtitleTonemapPipeline_candidateStreams_filtersByCodec() {
        let url = URL(fileURLWithPath: "/tmp/test.mkv")
        let hdrVideo = MediaStream(
            streamIndex: 0,
            streamType: .video,
            hdrFormats: [.hdr10]
        )
        let streams: [MediaStream] = [
            hdrVideo,
            MediaStream(streamIndex: 1, streamType: .subtitle, codecName: "srt"),       // unsupported (text)
            MediaStream(streamIndex: 2, streamType: .subtitle, codecName: "hdmv_pgs_subtitle"), // supported
            MediaStream(streamIndex: 3, streamType: .subtitle, codecName: "dvd_subtitle"),       // deferred
            MediaStream(streamIndex: 4, streamType: .subtitle, codecName: "ass"),                // supported
        ]
        let file = MediaFile(fileURL: url, streams: streams)
        let cfg = SubtitleTonemapConfig()

        let candidates = SubtitleTonemapPipeline.candidateStreams(
            in: file, config: cfg, wrapperAvailable: true
        )
        XCTAssertEqual(candidates.map(\.streamIndex), [2, 4],
                       "Only supported codecs should pass, in source order")
    }

    /// FFmpeg extraction args: the pipeline must emit the exact six-
    /// argument form that pairs with `subtitle_tonemap`'s expected
    /// input layout. A drift here would produce malformed extraction
    /// commands that fail at runtime.
    func test_subtitleTonemapPipeline_extractionArgumentsAreStable() {
        let args = SubtitleTonemapPipeline.ffmpegExtractionArguments(
            inputPath: "/tmp/source.mkv",
            outputPath: "/tmp/extracted.sup",
            streamIndex: 2,
            outputFormat: "sup"
        )
        XCTAssertEqual(args, [
            "-y",
            "-i", "/tmp/source.mkv",
            "-map", "0:2",
            "-c:s", "copy",
            "-f", "sup",
            "/tmp/extracted.sup",
        ])
    }

    // MARK: - SubtitleTonemapWrapper (#369)

    /// Pins the SubtitleTonemapConfig default-initialised values against
    /// the explicit defaults baked into the UI in
    /// `OutputSettingsView.subtitleTonemapControls` (#381 / #396). If the
    /// engine defaults drift, the UI's master-toggle-installs-a-default
    /// behaviour would silently produce different settings than a user
    /// constructing the config explicitly — surface that as a test
    /// failure rather than a runtime surprise.
    func test_subtitleTonemapConfig_defaultsMatchEngineAndUI() {
        let defaults = SubtitleTonemapConfig()
        XCTAssertEqual(defaults.sourceProfile, .hdr10,
                       "UI Picker first selection assumes .hdr10 default")
        XCTAssertEqual(defaults.targetLuminanceNits, 100.0,
                       "UI Stepper default value is 100 nits")
        XCTAssertTrue(defaults.preserveAlpha,
                      "UI Toggle default is on (alpha preserved)")
    }

    /// `EncodingProfile.subtitleTonemap` defaults to `nil` so existing
    /// profile JSON on disk decodes cleanly under the auto-synthesised
    /// `Decodable`. The UI relies on this: turning the master toggle
    /// OFF must clear the optional, not leave a stale default behind.
    func test_encodingProfile_subtitleTonemapDefaultIsNil() {
        let profile = EncodingProfile(name: "test")
        XCTAssertNil(profile.subtitleTonemap)
    }

    /// Round-trips an `EncodingProfile` with a non-nil tonemap config
    /// through `JSONEncoder`/`JSONDecoder` to verify on-disk profile
    /// persistence preserves the new field. Without this, a UI that
    /// stores tonemap settings would lose them on the next launch.
    func test_encodingProfile_subtitleTonemap_codableRoundTrip() throws {
        var profile = EncodingProfile(name: "tonemap-test")
        profile.subtitleTonemap = SubtitleTonemapConfig(
            sourceProfile: .dolbyVision,
            targetLuminanceNits: 150,
            preserveAlpha: false
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: data)
        XCTAssertEqual(decoded.subtitleTonemap?.sourceProfile, .dolbyVision)
        XCTAssertEqual(decoded.subtitleTonemap?.targetLuminanceNits, 150)
        XCTAssertEqual(decoded.subtitleTonemap?.preserveAlpha, false)
    }

    /// Verifies supported subtitle formats.
    func test_subtitleTonemap_supportedFormats() {
        XCTAssertTrue(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "sup"))
        XCTAssertTrue(SubtitleTonemapWrapper.isFormatSupported(fileExtension: ".sup"))
        XCTAssertTrue(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "SUP"))
        XCTAssertTrue(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "sub"))
        XCTAssertTrue(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "idx"))
        XCTAssertTrue(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "ass"))
        XCTAssertTrue(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "ssa"))
    }

    /// Plain-text formats without colour tags are rejected.
    func test_subtitleTonemap_rejectsPlainTextFormats() {
        XCTAssertFalse(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "srt"))
        XCTAssertFalse(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "vtt"))
        XCTAssertFalse(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "ttml"))
        XCTAssertFalse(SubtitleTonemapWrapper.isFormatSupported(fileExtension: "txt"))
    }

    /// Argument builder produces the expected CLI invocation.
    func test_subtitleTonemap_argumentsForHDR10() {
        let config = SubtitleTonemapConfig(
            sourceProfile: .hdr10,
            targetLuminanceNits: 100,
            preserveAlpha: true
        )
        let args = SubtitleTonemapWrapper.buildArguments(
            inputPath: "/tmp/in.sup",
            outputPath: "/tmp/out.sup",
            config: config
        )
        XCTAssertEqual(args[0], "-i")
        XCTAssertEqual(args[1], "/tmp/in.sup")
        XCTAssertEqual(args[2], "-o")
        XCTAssertEqual(args[3], "/tmp/out.sup")
        XCTAssertTrue(args.contains("--hdr10"))
        XCTAssertTrue(args.contains("--target-nits"))
        XCTAssertTrue(args.contains("100"))
        XCTAssertTrue(args.contains("--preserve-alpha"))
    }

    /// `--preserve-alpha` is omitted when disabled.
    func test_subtitleTonemap_argumentsWithoutAlpha() {
        let config = SubtitleTonemapConfig(
            sourceProfile: .dolbyVision,
            targetLuminanceNits: 203,
            preserveAlpha: false
        )
        let args = SubtitleTonemapWrapper.buildArguments(
            inputPath: "/tmp/in.sup",
            outputPath: "/tmp/out.sup",
            config: config
        )
        XCTAssertTrue(args.contains("--dolby-vision"))
        XCTAssertTrue(args.contains("203"))
        XCTAssertFalse(args.contains("--preserve-alpha"))
    }

    /// Each HDR profile maps to the correct CLI flag.
    func test_subtitleTonemap_hdrProfileFlags() {
        XCTAssertEqual(SubtitleHDRSourceProfile.hdr10.cliFlag, "--hdr10")
        XCTAssertEqual(SubtitleHDRSourceProfile.hdr10Plus.cliFlag, "--hdr10plus")
        XCTAssertEqual(SubtitleHDRSourceProfile.dolbyVision.cliFlag, "--dolby-vision")
        XCTAssertEqual(SubtitleHDRSourceProfile.hlg.cliFlag, "--hlg")
    }

    /// Default config uses HDR10 with 100-nit SDR target.
    func test_subtitleTonemap_defaultConfig() {
        let config = SubtitleTonemapConfig()
        XCTAssertEqual(config.sourceProfile, .hdr10)
        XCTAssertEqual(config.targetLuminanceNits, 100.0)
        XCTAssertTrue(config.preserveAlpha)
    }

    /// Config Codable round-trips.
    func test_subtitleTonemap_configCodableRoundTrip() throws {
        let original = SubtitleTonemapConfig(
            sourceProfile: .hlg,
            targetLuminanceNits: 203.5,
            preserveAlpha: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SubtitleTonemapConfig.self, from: data)
        XCTAssertEqual(decoded.sourceProfile, .hlg)
        XCTAssertEqual(decoded.targetLuminanceNits, 203.5, accuracy: 0.01)
        XCTAssertFalse(decoded.preserveAlpha)
    }

    // MARK: - RenderFarm (#346)

    /// Default chunk size and port are the published constants.
    func test_renderFarm_protocolDefaults() {
        XCTAssertEqual(RenderFarmProtocol.defaultChunkSizeBytes, 4 * 1024 * 1024)
        XCTAssertEqual(RenderFarmProtocol.defaultAgentPort, 2229)
        XCTAssertEqual(RenderFarmProtocol.bonjourServiceType, "_meedyaconverter-agent._tcp")
    }

    /// Exact-multiple file sizes produce exact chunk counts.
    func test_renderFarm_chunkCountExactMultiple() {
        XCTAssertEqual(
            RenderFarmProtocol.chunkCount(forSourceSizeBytes: 0, chunkSizeBytes: 1024),
            0
        )
        XCTAssertEqual(
            RenderFarmProtocol.chunkCount(forSourceSizeBytes: 4096, chunkSizeBytes: 1024),
            4
        )
    }

    /// Non-exact file sizes round up to include the remainder chunk.
    func test_renderFarm_chunkCountRoundUp() {
        XCTAssertEqual(
            RenderFarmProtocol.chunkCount(forSourceSizeBytes: 4097, chunkSizeBytes: 1024),
            5
        )
        XCTAssertEqual(
            RenderFarmProtocol.chunkCount(forSourceSizeBytes: 1, chunkSizeBytes: 1024),
            1
        )
    }

    /// Checksum validation accepts matching strings (case-insensitive).
    func test_renderFarm_checksumValidateMatches() throws {
        try RenderFarmProtocol.validateAssembledChecksum(
            expected: "ABCDEF01",
            observed: "abcdef01"
        )
    }

    /// Checksum validation rejects mismatches.
    func test_renderFarm_checksumValidateMismatches() {
        XCTAssertThrowsError(
            try RenderFarmProtocol.validateAssembledChecksum(
                expected: "abcdef01",
                observed: "ffffffff"
            )
        ) { error in
            guard case RenderFarmError.transferIntegrityFailed = error else {
                XCTFail("Expected transferIntegrityFailed, got \(error)")
                return
            }
        }
    }

    /// REST paths are versioned and use the lowercased UUID.
    func test_renderFarm_restPaths() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        XCTAssertEqual(
            RenderFarmProtocol.submitPath(jobId: id),
            "/v1/jobs/12345678-1234-1234-1234-123456789abc"
        )
        XCTAssertEqual(
            RenderFarmProtocol.chunkPath(jobId: id, index: 7),
            "/v1/jobs/12345678-1234-1234-1234-123456789abc/chunks/7"
        )
        XCTAssertEqual(
            RenderFarmProtocol.statusPath(jobId: id),
            "/v1/jobs/12345678-1234-1234-1234-123456789abc/status"
        )
        XCTAssertEqual(
            RenderFarmProtocol.downloadPath(jobId: id),
            "/v1/jobs/12345678-1234-1234-1234-123456789abc/output"
        )
        XCTAssertEqual(
            RenderFarmProtocol.cancelPath(jobId: id),
            "/v1/jobs/12345678-1234-1234-1234-123456789abc/cancel"
        )
    }

    /// Terminal states stop the progress stream.
    func test_renderFarm_terminalStates() {
        XCTAssertTrue(RenderFarmClient.isTerminal(state: .completed))
        XCTAssertTrue(RenderFarmClient.isTerminal(state: .failed))
        XCTAssertTrue(RenderFarmClient.isTerminal(state: .cancelled))
        XCTAssertFalse(RenderFarmClient.isTerminal(state: .queued))
        XCTAssertFalse(RenderFarmClient.isTerminal(state: .transferring))
        XCTAssertFalse(RenderFarmClient.isTerminal(state: .encoding))
        XCTAssertFalse(RenderFarmClient.isTerminal(state: .finalising))
    }

    /// Agent info endpoint formatting.
    func test_renderFarm_agentEndpointString() {
        let agent = RenderFarmAgentInfo(
            displayName: "studio-tower",
            host: "192.168.1.42",
            port: 2229
        )
        XCTAssertEqual(agent.endpoint, "192.168.1.42:2229")
    }

    /// Agent registry add/remove works as expected.
    func test_renderFarm_clientRegistry() {
        let client = RenderFarmClient(transport: FakeRenderFarmTransport())
        let a = RenderFarmAgentInfo(displayName: "alpha", host: "10.0.0.1")
        let b = RenderFarmAgentInfo(displayName: "bravo", host: "10.0.0.2")
        client.register(agent: a)
        client.register(agent: b)
        let all = client.allAgents()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].displayName, "alpha")  // sorted
        XCTAssertEqual(all[1].displayName, "bravo")
        client.unregister(agentID: a.id)
        XCTAssertEqual(client.allAgents().count, 1)
        XCTAssertNil(client.agent(id: a.id))
        XCTAssertNotNil(client.agent(id: b.id))
    }

    /// Insecure transports must be explicitly allowed by configuration.
    func test_renderFarm_insecureTransportRejectedByDefault() {
        let client = RenderFarmClient(transport: FakeRenderFarmTransport())
        let submission = RenderFarmJobSubmission(
            agentId: UUID(),
            profileIdentifier: "test",
            sourceFilename: "a.mov",
            sourceSHA256: "deadbeef",
            sourceSizeBytes: 10,
            transport: .plainHTTP
        )
        XCTAssertThrowsError(try client.validate(submission: submission))
    }

    /// Insecure transports are accepted when an explicit
    /// `InsecureTransportOverride` token is supplied.
    func test_renderFarm_insecureTransportAllowedWhenConfigured() {
        let client = RenderFarmClient(
            transport: FakeRenderFarmTransport(),
            configuration: RenderFarmClient.Configuration(
                insecureTransportOverride: .developmentOnly(
                    acknowledgement: "loopback test"
                )
            )
        )
        let submission = RenderFarmJobSubmission(
            agentId: UUID(),
            profileIdentifier: "test",
            sourceFilename: "a.mov",
            sourceSHA256: "deadbeef",
            sourceSizeBytes: 10,
            transport: .plainHTTP
        )
        XCTAssertNoThrow(try client.validate(submission: submission))
    }

    // -----------------------------------------------------------------
    // MARK: - Issue #380: InsecureTransportOverride required for plainHTTP
    // -----------------------------------------------------------------
    //
    // The audit asked for the .plainHTTP path to be gated by an explicit
    // capability token rather than a bare boolean flag. The tests below
    // pin two of the resulting invariants in place so a future refactor
    // can't quietly bring the old "allowInsecureTransports: true" idiom
    // back.

    /// Verifies the default configuration provides no override token —
    /// the only safe default the type system can encode for this enum.
    func test_renderFarm_defaultConfiguration_hasNoInsecureOverride() {
        let config = RenderFarmClient.Configuration()
        XCTAssertNil(config.insecureTransportOverride)
        XCTAssertFalse(config.allowsInsecureTransports)
    }

    /// Verifies an override token carries its acknowledgement string and
    /// flips `allowsInsecureTransports` on. This is the convenience
    /// surface the UI uses to render a warning banner without needing to
    /// peek at the token directly.
    func test_renderFarm_developmentOnlyOverride_recordsAcknowledgement() {
        let token = InsecureTransportOverride.developmentOnly(
            acknowledgement: "local loopback, no real credentials"
        )
        let config = RenderFarmClient.Configuration(
            insecureTransportOverride: token
        )
        XCTAssertTrue(config.allowsInsecureTransports)
        XCTAssertEqual(
            config.insecureTransportOverride?.acknowledgement,
            "local loopback, no real credentials"
        )
    }
}

/// Trivial transport adapter used to exercise the client without a live agent.
private struct FakeRenderFarmTransport: RenderFarmTransportAdapter, Sendable {
    func submit(
        agent: RenderFarmAgentInfo,
        submission: RenderFarmJobSubmission
    ) async throws -> RenderFarmJobStatus {
        RenderFarmJobStatus(jobId: submission.jobId, state: .queued, progress: 0)
    }
    func uploadChunk(agent: RenderFarmAgentInfo, chunk: RenderFarmChunk) async throws { }
    func status(
        agent: RenderFarmAgentInfo,
        jobId: UUID
    ) async throws -> RenderFarmJobStatus {
        RenderFarmJobStatus(jobId: jobId, state: .completed, progress: 1.0)
    }
    func download(
        agent: RenderFarmAgentInfo,
        jobId: UUID,
        destination: URL
    ) async throws -> URL { destination }
    func cancel(agent: RenderFarmAgentInfo, jobId: UUID) async throws { }
}
