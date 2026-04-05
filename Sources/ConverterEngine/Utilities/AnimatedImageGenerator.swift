// ============================================================================
// MeedyaConverter — AnimatedImageGenerator (Issue #321)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - AnimatedImageFormat
// ---------------------------------------------------------------------------
/// Supported animated image output formats.
///
/// Each format has distinct trade-offs:
/// - **GIF**: Universal compatibility, limited to 256 colours per frame,
///   large file sizes, no alpha transparency gradient (1-bit alpha only).
/// - **APNG**: Full 24-bit colour with 8-bit alpha, smaller files than
///   GIF for photographic content, supported in all modern browsers.
///
/// Phase 12 — GIF/APNG Creation from Video (Issue #321)
public enum AnimatedImageFormat: String, Sendable, CaseIterable, Codable {

    /// CompuServe GIF format (256-colour palette, 1-bit alpha).
    case gif

    /// Animated PNG format (full colour, 8-bit alpha).
    case apng
}

// ---------------------------------------------------------------------------
// MARK: - AnimatedImageConfig
// ---------------------------------------------------------------------------
/// Configuration for generating an animated image from a video source.
///
/// Controls the time range, spatial dimensions, frame rate, colour
/// palette size, and dithering behaviour of the output.
///
/// Phase 12 — GIF/APNG Creation from Video (Issue #321)
public struct AnimatedImageConfig: Codable, Sendable {

    /// The output format (GIF or APNG).
    public var format: AnimatedImageFormat

    /// Start time in the source video, in seconds.
    public var startTime: TimeInterval

    /// Duration of the clip to extract, in seconds.
    public var duration: TimeInterval

    /// Output width in pixels. When `nil`, the source width is preserved.
    /// Height is auto-calculated to maintain the aspect ratio.
    public var width: Int?

    /// Output frame rate (frames per second).
    ///
    /// Lower values produce smaller files. Typical GIF frame rates
    /// range from 10 to 20 fps.
    public var fps: Int

    /// Maximum number of colours in the palette (GIF only).
    ///
    /// Valid range is 2–256. Higher values improve colour accuracy
    /// at the cost of file size. Ignored for APNG output.
    public var maxColors: Int

    /// Whether to apply dithering when reducing the colour palette (GIF only).
    ///
    /// Dithering simulates missing colours via dot patterns, which
    /// improves perceived quality but increases file size. Ignored for APNG.
    public var dithering: Bool

    /// Number of times the animation loops. `0` means infinite looping.
    public var loopCount: Int

    /// Memberwise initializer with sensible defaults.
    ///
    /// - Parameters:
    ///   - format: Output format (default `.gif`).
    ///   - startTime: Clip start in seconds (default `0`).
    ///   - duration: Clip duration in seconds (default `5`).
    ///   - width: Output width in pixels (default `nil` — source width).
    ///   - fps: Frame rate (default `15`).
    ///   - maxColors: Palette size for GIF (default `256`).
    ///   - dithering: Enable dithering (default `true`).
    ///   - loopCount: Loop count, 0 = infinite (default `0`).
    public init(
        format: AnimatedImageFormat = .gif,
        startTime: TimeInterval = 0,
        duration: TimeInterval = 5,
        width: Int? = nil,
        fps: Int = 15,
        maxColors: Int = 256,
        dithering: Bool = true,
        loopCount: Int = 0
    ) {
        self.format = format
        self.startTime = startTime
        self.duration = duration
        self.width = width
        self.fps = fps
        self.maxColors = maxColors
        self.dithering = dithering
        self.loopCount = loopCount
    }
}

// ---------------------------------------------------------------------------
// MARK: - AnimatedImageGenerator
// ---------------------------------------------------------------------------
/// Builds FFmpeg command-line arguments for creating animated GIF and APNG
/// images from video sources.
///
/// GIF generation uses FFmpeg's two-pass palette workflow:
/// 1. **Pass 1 (palettegen)**: Analyse the input to generate an optimal
///    256-colour palette.
/// 2. **Pass 2 (paletteuse)**: Re-read the input and quantise each frame
///    against the generated palette with optional dithering.
///
/// APNG generation is simpler — FFmpeg writes APNG directly from the
/// filtered video frames without a separate palette pass.
///
/// Phase 12 — GIF/APNG Creation from Video (Issue #321)
public struct AnimatedImageGenerator: Sendable {

    // MARK: - GIF Arguments

    /// Builds FFmpeg arguments for two-pass high-quality GIF generation.
    ///
    /// The returned arguments represent the **second pass** command. The
    /// caller is responsible for running the first pass (palette generation)
    /// before invoking the second pass. Both sets of arguments are returned
    /// as a tuple-style pair via the two static methods.
    ///
    /// Workflow:
    /// ```
    /// // Pass 1: generate palette
    /// ffmpeg <palettegen args>
    /// // Pass 2: create GIF using palette
    /// ffmpeg <paletteuse args>
    /// ```
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source video file.
    ///   - outputPath: Absolute path for the output `.gif` file.
    ///   - config: The animated image configuration.
    /// - Returns: An array of arrays — element 0 is the palettegen pass,
    ///   element 1 is the paletteuse pass.
    public static func buildGIFArguments(
        inputPath: String,
        outputPath: String,
        config: AnimatedImageConfig
    ) -> [[String]] {
        // Derive the palette file path from the output path.
        let paletteDir = (outputPath as NSString).deletingLastPathComponent
        let palettePath = (paletteDir as NSString)
            .appendingPathComponent("palette_tmp.png")

        // Build the filter graph components.
        var filters: [String] = ["fps=\(config.fps)"]
        if let width = config.width {
            filters.append("scale=\(width):-1:flags=lanczos")
        }
        let filterBase = filters.joined(separator: ",")

        // --- Pass 1: palettegen ---
        var pass1: [String] = [
            "-ss", String(format: "%.3f", config.startTime),
            "-t", String(format: "%.3f", config.duration),
            "-i", inputPath,
            "-vf", "\(filterBase),palettegen=max_colors=\(config.maxColors)",
            "-y", palettePath,
        ]
        _ = pass1.count // Suppress mutation warning

        // --- Pass 2: paletteuse ---
        let ditherMode = config.dithering ? "sierra2_4a" : "none"
        var pass2: [String] = [
            "-ss", String(format: "%.3f", config.startTime),
            "-t", String(format: "%.3f", config.duration),
            "-i", inputPath,
            "-i", palettePath,
            "-lavfi", "\(filterBase) [x]; [x][1:v] paletteuse=dither=\(ditherMode)",
            "-loop", String(config.loopCount),
            "-y", outputPath,
        ]
        _ = pass2.count // Suppress mutation warning

        return [pass1, pass2]
    }

    // MARK: - APNG Arguments

    /// Builds FFmpeg arguments for APNG (Animated PNG) generation.
    ///
    /// APNG retains full 24-bit colour and 8-bit alpha, so no palette
    /// generation pass is required. The output uses the `apng` muxer.
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source video file.
    ///   - outputPath: Absolute path for the output `.apng` file.
    ///   - config: The animated image configuration.
    /// - Returns: An array of FFmpeg command-line argument strings.
    public static func buildAPNGArguments(
        inputPath: String,
        outputPath: String,
        config: AnimatedImageConfig
    ) -> [String] {
        var filters: [String] = ["fps=\(config.fps)"]
        if let width = config.width {
            filters.append("scale=\(width):-1:flags=lanczos")
        }
        let filterChain = filters.joined(separator: ",")

        return [
            "-ss", String(format: "%.3f", config.startTime),
            "-t", String(format: "%.3f", config.duration),
            "-i", inputPath,
            "-vf", filterChain,
            "-plays", String(config.loopCount),
            "-f", "apng",
            "-y", outputPath,
        ]
    }
}
