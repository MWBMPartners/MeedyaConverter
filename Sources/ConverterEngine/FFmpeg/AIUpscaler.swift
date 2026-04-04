// ============================================================================
// MeedyaConverter — AIUpscaler
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - UpscaleModel

/// Available AI upscaling models.
public enum UpscaleModel: String, Codable, Sendable, CaseIterable {
    /// Real-ESRGAN general-purpose model (x4).
    case realESRGAN = "realesrgan-x4plus"

    /// Real-ESRGAN anime/animation optimised model (x4).
    case realESRGANAnime = "realesrgan-x4plus-anime"

    /// Real-ESRGAN video model (x4, temporal consistency).
    case realESRGANVideo = "realesrgan-x4-v3"

    /// Waifu2x for anime and illustration upscaling.
    case waifu2x = "waifu2x"

    /// Display name.
    public var displayName: String {
        switch self {
        case .realESRGAN: return "Real-ESRGAN (General)"
        case .realESRGANAnime: return "Real-ESRGAN (Anime)"
        case .realESRGANVideo: return "Real-ESRGAN (Video)"
        case .waifu2x: return "Waifu2x"
        }
    }

    /// Default scale factor for this model.
    public var defaultScaleFactor: Int {
        switch self {
        case .waifu2x: return 2
        default: return 4
        }
    }

    /// Supported scale factors for this model.
    public var supportedScaleFactors: [Int] {
        switch self {
        case .waifu2x: return [2]
        default: return [2, 3, 4]
        }
    }
}

// MARK: - UpscaleBackend

/// The computation backend for AI upscaling.
public enum UpscaleBackend: String, Codable, Sendable {
    /// Metal Performance Shaders (macOS, Apple Silicon / AMD).
    case metal = "metal"

    /// NVIDIA CUDA (Windows, Linux).
    case cuda = "cuda"

    /// Vulkan compute (cross-platform).
    case vulkan = "vulkan"

    /// CPU-only (slow fallback).
    case cpu = "cpu"
}

// MARK: - UpscaleConfig

/// Configuration for AI video upscaling.
public struct UpscaleConfig: Codable, Sendable {
    /// Whether AI upscaling is enabled.
    public var enabled: Bool

    /// The model to use for upscaling.
    public var model: UpscaleModel

    /// The scale factor (2x, 3x, 4x).
    public var scaleFactor: Int

    /// Target output resolution (alternative to scaleFactor).
    /// If set, scaleFactor is calculated automatically.
    public var targetWidth: Int?
    public var targetHeight: Int?

    /// Tile size for processing (smaller = less VRAM, slower).
    /// 0 means auto-select based on available VRAM.
    public var tileSize: Int

    /// Denoise strength (0.0 = no denoising, 1.0 = maximum).
    /// Only supported by some models.
    public var denoiseStrength: Double

    /// Preferred computation backend.
    public var backend: UpscaleBackend?

    /// GPU device index for multi-GPU systems.
    public var gpuDevice: Int

    public init(
        enabled: Bool = true,
        model: UpscaleModel = .realESRGAN,
        scaleFactor: Int = 4,
        targetWidth: Int? = nil,
        targetHeight: Int? = nil,
        tileSize: Int = 0,
        denoiseStrength: Double = 0.0,
        backend: UpscaleBackend? = nil,
        gpuDevice: Int = 0
    ) {
        self.enabled = enabled
        self.model = model
        self.scaleFactor = scaleFactor
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        self.tileSize = tileSize
        self.denoiseStrength = denoiseStrength
        self.backend = backend
        self.gpuDevice = gpuDevice
    }
}

// MARK: - AIUpscaler

/// Builds command-line arguments for AI video upscaling using
/// external neural network tools (Real-ESRGAN, Waifu2x).
///
/// The upscaler works as a pre-processing step: frames are extracted,
/// upscaled via the AI model, then fed back into the encoding pipeline.
///
/// Phase 7.15
public struct AIUpscaler: Sendable {

    /// Build arguments for the realesrgan-ncnn-vulkan CLI tool.
    ///
    /// - Parameters:
    ///   - config: Upscale configuration.
    ///   - inputPath: Input video/image path.
    ///   - outputPath: Output path for upscaled result.
    /// - Returns: Command-line argument array.
    public static func buildRealESRGANArguments(
        config: UpscaleConfig,
        inputPath: String,
        outputPath: String
    ) -> [String] {
        var args: [String] = []

        args += ["-i", inputPath]
        args += ["-o", outputPath]
        args += ["-n", config.model.rawValue]
        args += ["-s", "\(config.scaleFactor)"]

        if config.tileSize > 0 {
            args += ["-t", "\(config.tileSize)"]
        }

        args += ["-g", "\(config.gpuDevice)"]

        // Format selection
        args += ["-f", "png"]

        return args
    }

    /// Build FFmpeg arguments to extract frames for AI upscaling.
    ///
    /// - Parameters:
    ///   - inputPath: Source video path.
    ///   - outputPattern: Output frame pattern (e.g., "/tmp/frames/%06d.png").
    ///   - pixelFormat: Pixel format for extracted frames.
    /// - Returns: FFmpeg argument array.
    public static func buildFrameExtractionArguments(
        inputPath: String,
        outputPattern: String,
        pixelFormat: String = "rgb24"
    ) -> [String] {
        return [
            "-i", inputPath,
            "-pix_fmt", pixelFormat,
            outputPattern
        ]
    }

    /// Build FFmpeg arguments to reassemble upscaled frames into video.
    ///
    /// - Parameters:
    ///   - framePattern: Input frame pattern (e.g., "/tmp/upscaled/%06d.png").
    ///   - frameRate: Source video frame rate.
    ///   - outputPath: Output video path.
    ///   - codec: Video codec for encoding.
    /// - Returns: FFmpeg argument array.
    public static func buildReassemblyArguments(
        framePattern: String,
        frameRate: Double,
        outputPath: String,
        codec: VideoCodec = .h265
    ) -> [String] {
        var args: [String] = []

        args += ["-framerate", String(format: "%.3f", frameRate)]
        args += ["-i", framePattern]

        if let encoder = codec.ffmpegEncoder {
            args += ["-c:v", encoder]
        }

        args += ["-pix_fmt", "yuv420p"]
        args += [outputPath]

        return args
    }

    /// Build an FFmpeg filter for traditional (non-AI) upscaling as fallback.
    ///
    /// Uses lanczos scaling which is the highest quality non-AI option.
    ///
    /// - Parameters:
    ///   - targetWidth: Target width in pixels.
    ///   - targetHeight: Target height in pixels.
    /// - Returns: FFmpeg video filter string.
    public static func buildTraditionalUpscaleFilter(
        targetWidth: Int,
        targetHeight: Int
    ) -> String {
        return "scale=\(targetWidth):\(targetHeight):flags=lanczos"
    }

    /// Calculate the output resolution for a given scale factor.
    ///
    /// - Parameters:
    ///   - sourceWidth: Source width in pixels.
    ///   - sourceHeight: Source height in pixels.
    ///   - scaleFactor: Upscale factor (2, 3, or 4).
    /// - Returns: Tuple of (width, height) rounded to even numbers.
    public static func calculateOutputResolution(
        sourceWidth: Int,
        sourceHeight: Int,
        scaleFactor: Int
    ) -> (width: Int, height: Int) {
        let w = sourceWidth * scaleFactor
        let h = sourceHeight * scaleFactor
        // Round to even numbers for codec compatibility
        return (width: w & ~1, height: h & ~1)
    }

    /// Estimate VRAM usage for a given configuration.
    ///
    /// - Parameters:
    ///   - width: Input frame width.
    ///   - height: Input frame height.
    ///   - scaleFactor: Upscale factor.
    ///   - tileSize: Tile size (0 = full frame).
    /// - Returns: Estimated VRAM usage in megabytes.
    public static func estimateVRAM(
        width: Int,
        height: Int,
        scaleFactor: Int,
        tileSize: Int = 0
    ) -> Int {
        let effectiveTile = tileSize > 0 ? tileSize : max(width, height)
        // Rough estimate: ~4 bytes per pixel * tile^2 * scaleFactor^2 * model overhead (~10x)
        let pixels = effectiveTile * effectiveTile
        let outputPixels = pixels * scaleFactor * scaleFactor
        let bytesEstimate = (pixels + outputPixels) * 4 * 10
        return bytesEstimate / (1024 * 1024)
    }
}
