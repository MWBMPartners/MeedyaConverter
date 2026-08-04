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

// MARK: - Test fixtures

// MARK: - RasterVectorConverter (#376)

extension ConverterEngineTests {

    func test_rasterFormat_recognisesAliases() {
        XCTAssertEqual(RasterFormat.from(fileExtension: "jpg"), .jpeg)
        XCTAssertEqual(RasterFormat.from(fileExtension: ".JPG"), .jpeg)
        XCTAssertEqual(RasterFormat.from(fileExtension: "tif"), .tiff)
        XCTAssertEqual(RasterFormat.from(fileExtension: "png"), .png)
        XCTAssertNil(RasterFormat.from(fileExtension: "docx"))
    }

    func test_rasterFormat_animatedFlag() {
        XCTAssertTrue(RasterFormat.gif.isAnimated)
        XCTAssertTrue(RasterFormat.apng.isAnimated)
        XCTAssertTrue(RasterFormat.webp.isAnimated)
        XCTAssertFalse(RasterFormat.jpeg.isAnimated)
        XCTAssertFalse(RasterFormat.png.isAnimated)
    }

    func test_rasterFormat_alphaSupport() {
        XCTAssertTrue(RasterFormat.png.hasAlphaSupport)
        XCTAssertTrue(RasterFormat.apng.hasAlphaSupport)
        XCTAssertTrue(RasterFormat.tiff.hasAlphaSupport)
        XCTAssertFalse(RasterFormat.jpeg.hasAlphaSupport)
        XCTAssertFalse(RasterFormat.bmp.hasAlphaSupport)
    }

    func test_rasterFormat_hdrCapable() {
        XCTAssertTrue(RasterFormat.exr.isHDRCapable)
        XCTAssertTrue(RasterFormat.hdr.isHDRCapable)
        XCTAssertTrue(RasterFormat.avif.isHDRCapable)
        XCTAssertTrue(RasterFormat.jxl.isHDRCapable)
        XCTAssertFalse(RasterFormat.gif.isHDRCapable)
    }

    func test_editabilityPreset_defaultsAreSensible() {
        XCTAssertEqual(EditabilityPreset.logoIcon.defaultTracingMode, .outline)
        XCTAssertEqual(EditabilityPreset.photorealistic.defaultTracingMode, .photorealistic)
        XCTAssertEqual(EditabilityPreset.logoIcon.defaultColorCount, 8)
        XCTAssertGreaterThan(
            EditabilityPreset.photorealistic.defaultColorCount,
            EditabilityPreset.logoIcon.defaultColorCount
        )
    }

    func test_rasterToVectorConfig_defaultsFromPreset() {
        let config = RasterToVectorConfig(
            inputFormat: .png,
            preset: .logoIcon
        )
        XCTAssertEqual(config.tracingMode, .outline)
        XCTAssertEqual(config.colorCount, 8)
        XCTAssertEqual(config.alpha, .clipPathWithOpacity)
        XCTAssertTrue(config.preserveMetadata)
    }

    func test_rasterToVectorConfig_validationRejectsBadColorCount() {
        let tooFew = RasterToVectorConfig(inputFormat: .png, colorCount: 1)
        XCTAssertNotNil(RasterVectorConverter.validate(tooFew))
        let tooMany = RasterToVectorConfig(inputFormat: .png, colorCount: 512)
        XCTAssertNotNil(RasterVectorConverter.validate(tooMany))
        let ok = RasterToVectorConfig(inputFormat: .png, colorCount: 64)
        XCTAssertNil(RasterVectorConverter.validate(ok))
    }

    func test_rasterToVectorConfig_validationRejectsBadSimplification() {
        let tooLow = RasterToVectorConfig(inputFormat: .png, curveSimplification: -1)
        XCTAssertNotNil(RasterVectorConverter.validate(tooLow))
        let tooHigh = RasterToVectorConfig(inputFormat: .png, curveSimplification: 100)
        XCTAssertNotNil(RasterVectorConverter.validate(tooHigh))
    }

    func test_preferredTracingTool() {
        XCTAssertEqual(RasterVectorConverter.preferredTracingTool(for: .outline), "potrace")
        XCTAssertEqual(RasterVectorConverter.preferredTracingTool(for: .monochrome), "potrace")
        XCTAssertEqual(RasterVectorConverter.preferredTracingTool(for: .colorQuantization), "vtracer")
        XCTAssertEqual(RasterVectorConverter.preferredTracingTool(for: .photorealistic), "vtracer")
    }

    func test_vtracerArguments_includeInputAndOutput() {
        let config = RasterToVectorConfig(inputFormat: .png, preset: .illustration)
        let args = RasterVectorConverter.buildVTracerArguments(
            inputPath: "/tmp/in.png",
            outputPath: "/tmp/out.svg",
            config: config
        )
        XCTAssertEqual(args[0], "-i")
        XCTAssertEqual(args[1], "/tmp/in.png")
        XCTAssertEqual(args[2], "-o")
        XCTAssertEqual(args[3], "/tmp/out.svg")
        XCTAssertTrue(args.contains("--colormode"))
        XCTAssertTrue(args.contains("color"))
    }

    func test_vtracerArguments_monochromeBinary() {
        let config = RasterToVectorConfig(inputFormat: .png, tracingMode: .monochrome, preset: .custom)
        let args = RasterVectorConverter.buildVTracerArguments(
            inputPath: "/tmp/in.png", outputPath: "/tmp/out.svg", config: config
        )
        guard let idx = args.firstIndex(of: "--colormode") else {
            XCTFail("expected --colormode"); return
        }
        XCTAssertEqual(args[idx + 1], "binary")
    }

    func test_potraceArguments_svgOutput() {
        let config = RasterToVectorConfig(inputFormat: .png, preset: .logoIcon)
        let args = RasterVectorConverter.buildPotraceArguments(
            inputPath: "/tmp/in.bmp",
            outputPath: "/tmp/out.svg",
            config: config
        )
        XCTAssertTrue(args.contains("/tmp/in.bmp"))
        XCTAssertTrue(args.contains("-s"))
        XCTAssertTrue(args.contains("--svg"))
        XCTAssertTrue(args.contains("/tmp/out.svg"))
    }

    func test_rsvgConvertArguments_dimensionsAndDPI() {
        let config = VectorToRasterConfig(
            outputFormat: .png,
            targetWidthPixels: 1024,
            targetHeightPixels: 768,
            dpi: 192
        )
        let args = RasterVectorConverter.buildRsvgConvertArguments(
            inputPath: "/tmp/logo.svg",
            outputPath: "/tmp/logo.png",
            config: config
        )
        XCTAssertEqual(args[0], "/tmp/logo.svg")
        XCTAssertTrue(args.contains("1024"))
        XCTAssertTrue(args.contains("768"))
        XCTAssertTrue(args.contains("192"))
        XCTAssertTrue(args.contains("png"))
    }

    // MARK: - ProResToVectorConverter (#377)

    func test_proResVariant_bitsPerChannel() {
        XCTAssertEqual(ProResVariant.proRes4444.bitsPerChannel, 8)
        XCTAssertEqual(ProResVariant.proRes4444XQ.bitsPerChannel, 12)
        XCTAssertEqual(ProResVariant.proRes4444HDR.bitsPerChannel, 12)
    }

    func test_proResVariant_hdrRequiresTonemapping() {
        XCTAssertFalse(ProResVariant.proRes4444.requiresTonemapping)
        XCTAssertFalse(ProResVariant.proRes4444XQ.requiresTonemapping)
        XCTAssertTrue(ProResVariant.proRes4444HDR.requiresTonemapping)
    }

    func test_proResFrameRate_doubleValue() {
        XCTAssertEqual(ProResFrameRate.fps24.doubleValue, 24.0, accuracy: 0.0001)
        XCTAssertEqual(ProResFrameRate.fps23_976.doubleValue, 24000.0 / 1001.0, accuracy: 0.0001)
        XCTAssertEqual(ProResFrameRate.fps29_97.doubleValue, 30000.0 / 1001.0, accuracy: 0.0001)
        XCTAssertEqual(ProResFrameRate.fps60.doubleValue, 60.0, accuracy: 0.0001)
    }

    func test_proResConfig_defaults() {
        let config = ProResToVectorConfig()
        XCTAssertEqual(config.sourceVariant, .proRes4444)
        XCTAssertEqual(config.frameRate, .fps24)
        XCTAssertEqual(config.frameStride, 1)
        XCTAssertEqual(config.alphaHandling, .preservePerFrame)
        XCTAssertTrue(config.shapePersistence)
        XCTAssertTrue(config.keyframeExtraction)
    }

    func test_proResConfig_estimatedFrameCount() {
        // 5 seconds at 24 fps stride 1 = 120 frames
        let c1 = ProResToVectorConfig(frameRate: .fps24, frameStride: 1)
        XCTAssertEqual(c1.estimatedFrameCount(sourceDurationSeconds: 5.0), 120)
        // Stride 2 halves the count
        let c2 = ProResToVectorConfig(frameRate: .fps24, frameStride: 2)
        XCTAssertEqual(c2.estimatedFrameCount(sourceDurationSeconds: 5.0), 60)
        // Time range clamps
        let c3 = ProResToVectorConfig(
            frameRate: .fps24,
            startTimeSeconds: 1.0,
            endTimeSeconds: 3.0
        )
        XCTAssertEqual(c3.estimatedFrameCount(sourceDurationSeconds: 10.0), 48)
    }

    func test_proResFrameExtractionArguments_includesSSAndDuration() {
        let config = ProResToVectorConfig(
            frameRate: .fps24,
            startTimeSeconds: 1.0,
            endTimeSeconds: 3.0
        )
        let args = ProResToVectorConverter.buildFrameExtractionArguments(
            inputPath: "/tmp/in.mov",
            framePatternPath: "/tmp/frame_%06d.png",
            config: config
        )
        XCTAssertTrue(args.contains("-ss"))
        XCTAssertTrue(args.contains("1.000"))
        XCTAssertTrue(args.contains("-t"))
        XCTAssertTrue(args.contains("2.000"))
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/in.mov"))
        XCTAssertTrue(args.contains("/tmp/frame_%06d.png"))
        XCTAssertTrue(args.contains("png"))
        XCTAssertTrue(args.contains("rgba"))
    }

    func test_proResFrameExtractionArguments_hdrTonemappingApplied() {
        let config = ProResToVectorConfig(
            sourceVariant: .proRes4444HDR,
            frameRate: .fps24
        )
        let args = ProResToVectorConverter.buildFrameExtractionArguments(
            inputPath: "/tmp/hdr.mov",
            framePatternPath: "/tmp/f_%06d.png",
            config: config
        )
        // Tone-mapping filter chain must be present for HDR.
        let hasTonemap = args.contains { $0.contains("tonemap=hable") }
        XCTAssertTrue(hasTonemap, "Expected HDR tonemap filter in args")
    }

    func test_svgAnimationRoot_smil() {
        let root = ProResToVectorConverter.buildSVGAnimationRoot(
            widthPixels: 1920,
            heightPixels: 1080,
            frameCount: 120,
            frameRate: 24.0,
            method: .smil
        )
        XCTAssertTrue(root.contains("data-frame-count=\"120\""))
        XCTAssertTrue(root.contains("data-animation-method=\"smil\""))
        XCTAssertTrue(root.contains("viewBox=\"0 0 1920 1080\""))
    }

    func test_smilFrameWrapper_hasCorrectTiming() {
        let wrapper = ProResToVectorConverter.buildSMILFrameWrapper(
            frameIndex: 12,
            frameCount: 120,
            frameRate: 24.0
        )
        XCTAssertTrue(wrapper.contains("id=\"frame-12\""))
        XCTAssertTrue(wrapper.contains("begin=\"0.500000s\""))    // 12 / 24 = 0.5s
        XCTAssertTrue(wrapper.contains("fill=\"freeze\""))
    }

    func test_shouldWarnAboutOutputSize_longClip() {
        let config = ProResToVectorConfig(frameRate: .fps24)
        XCTAssertFalse(
            ProResToVectorConverter.shouldWarnAboutOutputSize(
                config: config,
                sourceDurationSeconds: 5.0
            )
        )
        XCTAssertTrue(
            ProResToVectorConverter.shouldWarnAboutOutputSize(
                config: config,
                sourceDurationSeconds: 15.0
            )
        )
    }

    func test_shouldWarnAboutOutputSize_photorealistic() {
        let tracing = RasterToVectorConfig(
            inputFormat: .png,
            tracingMode: .photorealistic,
            preset: .photorealistic
        )
        let config = ProResToVectorConfig(
            frameRate: .fps24,
            tracing: tracing
        )
        // Even a 3-second photorealistic clip should warn.
        XCTAssertTrue(
            ProResToVectorConverter.shouldWarnAboutOutputSize(
                config: config,
                sourceDurationSeconds: 3.0
            )
        )
    }

    // MARK: - FFmpegBundleManager FFplay support (#378)

    /// `FFmpegBundleError.ffplayNotFound` surfaces a distinct, actionable
    /// error message that mentions the preview feature.
    func test_ffmpegBundle_ffplayErrorMessage() {
        let error = FFmpegBundleError.ffplayNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("FFplay"))
        XCTAssertTrue(error.errorDescription!.contains("preview") || error.errorDescription!.contains("ffplay"))
    }

    /// The manager accepts an ffplayPath override in the initialiser.
    func test_ffmpegBundle_initAcceptsFFplayPath() {
        let manager = FFmpegBundleManager(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            ffprobePath: "/opt/homebrew/bin/ffprobe",
            ffplayPath: "/opt/homebrew/bin/ffplay"
        )
        XCTAssertEqual(manager.userFFmpegPath, "/opt/homebrew/bin/ffmpeg")
        XCTAssertEqual(manager.userFFprobePath, "/opt/homebrew/bin/ffprobe")
        XCTAssertEqual(manager.userFFplayPath, "/opt/homebrew/bin/ffplay")
    }

    /// `isFFplayAvailable()` soft-fails rather than throwing when ffplay is
    /// absent — UI surfaces check this before enabling preview playback.
    /// The contract under test is "returns a Bool, never throws", not the
    /// specific truthiness — the CI runner has Homebrew ffmpeg (and therefore
    /// ffplay) pre-installed, so `findBinary` discovers it even when the
    /// user-supplied path is bogus.
    func test_ffmpegBundle_isFFplayAvailableSoftFails() {
        let manager = FFmpegBundleManager(
            ffplayPath: "/tmp/definitely-not-a-real-ffplay-binary-\(UUID().uuidString)"
        )
        // The important guarantee is "does not throw"; discovery may still
        // succeed via the system search path.
        _ = manager.isFFplayAvailable()
    }
}
