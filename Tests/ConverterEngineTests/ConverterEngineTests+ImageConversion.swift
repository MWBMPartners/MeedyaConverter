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
    // MARK: - Phase 17: Image Conversion
    // -----------------------------------------------------------------

    /// Verifies ImageFormat CaseIterable.
    func test_imageFormat_allCases() {
        XCTAssertEqual(ImageFormat.allCases.count, 12)
    }

    /// Verifies ImageFormat file extensions.
    func test_imageFormat_fileExtensions() {
        XCTAssertEqual(ImageFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ImageFormat.png.fileExtension, "png")
        XCTAssertEqual(ImageFormat.webp.fileExtension, "webp")
        XCTAssertEqual(ImageFormat.avif.fileExtension, "avif")
        XCTAssertEqual(ImageFormat.jpegXL.fileExtension, "jxl")
    }

    /// Verifies ImageFormat display names.
    func test_imageFormat_displayNames() {
        XCTAssertEqual(ImageFormat.jpeg.displayName, "JPEG")
        XCTAssertEqual(ImageFormat.heif.displayName, "HEIF/HEIC")
        XCTAssertEqual(ImageFormat.exr.displayName, "OpenEXR")
        XCTAssertEqual(ImageFormat.jpegXL.displayName, "JPEG XL")
    }

    /// Verifies ImageFormat FFmpeg encoder names.
    func test_imageFormat_encoders() {
        XCTAssertEqual(ImageFormat.jpeg.ffmpegEncoder, "mjpeg")
        XCTAssertEqual(ImageFormat.png.ffmpegEncoder, "png")
        XCTAssertEqual(ImageFormat.webp.ffmpegEncoder, "libwebp")
        XCTAssertEqual(ImageFormat.avif.ffmpegEncoder, "libaom-av1")
        XCTAssertNil(ImageFormat.heif.ffmpegEncoder) // Requires external tool
    }

    /// Verifies ImageFormat capability flags.
    func test_imageFormat_capabilities() {
        // Lossless
        XCTAssertTrue(ImageFormat.png.supportsLossless)
        XCTAssertTrue(ImageFormat.webp.supportsLossless)
        XCTAssertFalse(ImageFormat.jpeg.supportsLossless)

        // Alpha
        XCTAssertTrue(ImageFormat.png.supportsAlpha)
        XCTAssertTrue(ImageFormat.webp.supportsAlpha)
        XCTAssertFalse(ImageFormat.jpeg.supportsAlpha)

        // HDR
        XCTAssertTrue(ImageFormat.avif.supportsHDR)
        XCTAssertTrue(ImageFormat.exr.supportsHDR)
        XCTAssertFalse(ImageFormat.jpeg.supportsHDR)

        // Animation
        XCTAssertTrue(ImageFormat.gif.supportsAnimation)
        XCTAssertTrue(ImageFormat.webp.supportsAnimation)
        XCTAssertFalse(ImageFormat.jpeg.supportsAnimation)
    }

    /// Verifies format detection from file extension.
    func test_imageFormat_fromExtension() {
        XCTAssertEqual(ImageFormat.from(extension: "jpg"), .jpeg)
        XCTAssertEqual(ImageFormat.from(extension: "JPEG"), .jpeg)
        XCTAssertEqual(ImageFormat.from(extension: "png"), .png)
        XCTAssertEqual(ImageFormat.from(extension: "webp"), .webp)
        XCTAssertEqual(ImageFormat.from(extension: "heic"), .heif)
        XCTAssertEqual(ImageFormat.from(extension: "tif"), .tiff)
        XCTAssertNil(ImageFormat.from(extension: "mp4"))
    }

    /// Verifies ImageQuality presets.
    func test_imageQuality_presets() {
        XCTAssertEqual(ImageQuality.low.quality, 50)
        XCTAssertEqual(ImageQuality.medium.quality, 75)
        XCTAssertEqual(ImageQuality.high.quality, 90)
        XCTAssertEqual(ImageQuality.maximum.quality, 100)
        XCTAssertTrue(ImageQuality.losslessPreset.lossless)
    }

    /// Verifies ImageQuality clamping.
    func test_imageQuality_clamping() {
        let clamped = ImageQuality(quality: 200, effort: -5)
        XCTAssertEqual(clamped.quality, 100)
        XCTAssertEqual(clamped.effort, 0)
    }

    /// Verifies basic image conversion arguments.
    func test_imageConverter_basicConversion() {
        let config = ImageConvertConfig(outputFormat: .webp)
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/photo.jpg",
            outputPath: "/tmp/photo.webp",
            config: config
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/photo.jpg"))
        XCTAssertTrue(args.contains("-c:v"))
        XCTAssertTrue(args.contains("libwebp"))
        XCTAssertTrue(args.contains("/tmp/photo.webp"))
    }

    /// Verifies image resize with fit mode.
    func test_imageConverter_resizeFit() {
        let config = ImageConvertConfig(
            outputFormat: .jpeg,
            width: 800,
            height: 600,
            resizeMode: .fit
        )
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/big.png",
            outputPath: "/tmp/small.jpg",
            config: config
        )
        let vf = args.first { $0.contains("scale=") }
        XCTAssertNotNil(vf)
        XCTAssertTrue(vf?.contains("force_original_aspect_ratio=decrease") ?? false)
    }

    /// Verifies image resize with fill mode.
    func test_imageConverter_resizeFill() {
        let config = ImageConvertConfig(
            outputFormat: .jpeg,
            width: 800,
            height: 600,
            resizeMode: .fill
        )
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/big.png",
            outputPath: "/tmp/small.jpg",
            config: config
        )
        let vf = args.first { $0.contains("scale=") }
        XCTAssertNotNil(vf)
        XCTAssertTrue(vf?.contains("crop=800:600") ?? false)
    }

    /// Verifies metadata stripping.
    func test_imageConverter_stripMetadata() {
        let config = ImageConvertConfig(outputFormat: .jpeg, stripMetadata: true)
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/photo.jpg",
            outputPath: "/tmp/clean.jpg",
            config: config
        )
        XCTAssertTrue(args.contains("-map_metadata"))
        XCTAssertTrue(args.contains("-1"))
    }

    /// Verifies lossless WebP arguments.
    func test_imageConverter_losslessWebP() {
        let config = ImageConvertConfig(
            outputFormat: .webp,
            quality: .losslessPreset
        )
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/photo.png",
            outputPath: "/tmp/photo.webp",
            config: config
        )
        XCTAssertTrue(args.contains("-lossless"))
        XCTAssertTrue(args.contains("1"))
    }

    /// Verifies thumbnail extraction arguments.
    func test_imageConverter_thumbnail() {
        let args = ImageConverter.buildThumbnailArguments(
            inputPath: "/tmp/video.mp4",
            outputPath: "/tmp/thumb.jpg",
            timestamp: 30.0,
            width: 320
        )
        XCTAssertTrue(args.contains("-ss"))
        XCTAssertTrue(args.contains("30.00"))
        XCTAssertTrue(args.contains("-frames:v"))
        XCTAssertTrue(args.contains("1"))
        let vf = args.first { $0.contains("scale=") }
        XCTAssertTrue(vf?.contains("320") ?? false)
    }

    /// Verifies image file detection.
    func test_imageConverter_isImageFile() {
        XCTAssertTrue(ImageConverter.isImageFile("photo.jpg"))
        XCTAssertTrue(ImageConverter.isImageFile("image.PNG"))
        XCTAssertTrue(ImageConverter.isImageFile("art.webp"))
        XCTAssertFalse(ImageConverter.isImageFile("video.mp4"))
        XCTAssertFalse(ImageConverter.isImageFile("document.pdf"))
    }

    /// Verifies format recommendation.
    func test_imageConverter_recommendFormat() {
        XCTAssertEqual(
            ImageConverter.recommendFormat(needsAlpha: false, preferSmallSize: false),
            .jpeg
        )
        XCTAssertEqual(
            ImageConverter.recommendFormat(needsAlpha: true, preferSmallSize: true),
            .webp
        )
        XCTAssertEqual(
            ImageConverter.recommendFormat(needsHDR: true),
            .avif
        )
        XCTAssertEqual(
            ImageConverter.recommendFormat(needsAnimation: true, preferSmallSize: true),
            .webp
        )
    }

    /// Verifies AVIF quality arguments.
    func test_imageConverter_avifQuality() {
        let config = ImageConvertConfig(
            outputFormat: .avif,
            quality: ImageQuality(quality: 80)
        )
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/photo.jpg",
            outputPath: "/tmp/photo.avif",
            config: config
        )
        XCTAssertTrue(args.contains("-crf"))
        XCTAssertTrue(args.contains("-still-picture"))
        XCTAssertTrue(args.contains("libaom-av1"))
    }

}
