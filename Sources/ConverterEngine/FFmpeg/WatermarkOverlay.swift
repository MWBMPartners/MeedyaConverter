// ============================================================================
// MeedyaConverter — WatermarkOverlay (Issue #298)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - WatermarkType

/// The type of watermark to apply to media.
public enum WatermarkType: String, Codable, Sendable {

    /// A text string rendered over the media.
    case text

    /// An image file overlaid on the media.
    case image
}

// MARK: - WatermarkPosition

/// The position of a watermark within the video/image frame.
///
/// Positions map to FFmpeg overlay coordinates calculated relative to
/// the output dimensions. A configurable margin offsets the watermark
/// from the edge.
public enum WatermarkPosition: String, Codable, Sendable, CaseIterable {

    /// Top-left corner of the frame.
    case topLeft

    /// Top-right corner of the frame.
    case topRight

    /// Bottom-left corner of the frame.
    case bottomLeft

    /// Bottom-right corner of the frame.
    case bottomRight

    /// Centred in the frame.
    case center
}

// MARK: - WatermarkConfig

/// Configuration for a watermark overlay on video or image output.
///
/// Supports both text and image watermarks with configurable position,
/// opacity, scale, and margin. Text watermarks also accept font size
/// and colour parameters via the FFmpeg `drawtext` filter.
public struct OverlayWatermarkConfig: Codable, Sendable {

    /// Whether this is a text or image watermark.
    public var type: WatermarkType

    /// The text string to render (only used when `type` is `.text`).
    public var text: String?

    /// The path to the watermark image file (only used when `type` is `.image`).
    public var imagePath: String?

    /// The position of the watermark in the frame.
    public var position: WatermarkPosition

    /// Opacity of the watermark, from 0.0 (invisible) to 1.0 (fully opaque).
    public var opacity: Double

    /// Scale factor for the watermark image, where 1.0 is original size.
    public var scale: Double

    /// Margin in pixels from the nearest edge.
    public var margin: Int

    /// Creates a new watermark configuration.
    ///
    /// - Parameters:
    ///   - type: The watermark type (text or image).
    ///   - text: The text string (for text watermarks).
    ///   - imagePath: The image file path (for image watermarks).
    ///   - position: The position in the frame.
    ///   - opacity: Opacity from 0.0 to 1.0.
    ///   - scale: Scale factor for image watermarks.
    ///   - margin: Pixel margin from the edge.
    /// Creates a new overlay watermark configuration.
    ///
    /// - Parameters:
    ///   - type: The watermark type (text or image).
    ///   - text: The text string (for text watermarks).
    ///   - imagePath: The image file path (for image watermarks).
    ///   - position: The position in the frame.
    ///   - opacity: Opacity from 0.0 to 1.0.
    ///   - scale: Scale factor for image watermarks.
    ///   - margin: Pixel margin from the edge.
    public init(
        type: WatermarkType,
        text: String? = nil,
        imagePath: String? = nil,
        position: WatermarkPosition = .bottomRight,
        opacity: Double = 0.5,
        scale: Double = 1.0,
        margin: Int = 10
    ) {
        self.type = type
        self.text = text
        self.imagePath = imagePath
        self.position = position
        self.opacity = opacity
        self.scale = scale
        self.margin = margin
    }
}

// MARK: - WatermarkOverlay

/// Builds FFmpeg filter strings and command-line arguments for watermark overlays.
///
/// Supports both text-based watermarks (using the `drawtext` filter) and
/// image-based watermarks (using the `overlay` filter with optional scaling).
/// Coordinates are calculated from the ``WatermarkPosition`` and margin values.
///
/// Phase 10.2 — Watermark Overlay for Batch Images (Issue #298)
public struct WatermarkOverlay: Sendable {

    // MARK: - Text Watermark

    /// Build an FFmpeg `drawtext` filter string for a text watermark.
    ///
    /// The filter renders the configured text at the specified position
    /// with the given opacity. Font size defaults to 24 and colour to
    /// white with alpha derived from `config.opacity`.
    ///
    /// Example output:
    /// ```
    /// drawtext=text='Copyright':fontsize=24:fontcolor=white@0.5:x=10:y=10
    /// ```
    ///
    /// - Parameter config: The watermark configuration.
    /// - Returns: An FFmpeg `drawtext` filter string.
    public static func buildTextWatermarkFilter(config: OverlayWatermarkConfig) -> String {
        let watermarkText = config.text ?? "Watermark"
        // Escape single quotes for FFmpeg filter syntax.
        let escapedText = watermarkText
            .replacingOccurrences(of: "'", with: "'\\''")
            .replacingOccurrences(of: ":", with: "\\:")

        let (xExpr, yExpr) = textPositionExpressions(
            position: config.position,
            margin: config.margin
        )

        let alphaValue = String(format: "%.2f", config.opacity)

        return "drawtext=text='\(escapedText)'"
            + ":fontsize=24"
            + ":fontcolor=white@\(alphaValue)"
            + ":x=\(xExpr)"
            + ":y=\(yExpr)"
    }

    // MARK: - Image Watermark

    /// Build an FFmpeg `overlay` filter string for an image watermark.
    ///
    /// The filter places a scaled watermark image at the specified position
    /// using overlay coordinates. The watermark input is assumed to be the
    /// second input stream (`[1:v]`), optionally scaled.
    ///
    /// Example output:
    /// ```
    /// [1:v]scale=iw*0.5:ih*0.5,format=rgba,colorchannelmixer=aa=0.5[wm];[0:v][wm]overlay=x=10:y=10
    /// ```
    ///
    /// - Parameter config: The watermark configuration.
    /// - Returns: An FFmpeg filter_complex string for the image overlay.
    public static func buildImageWatermarkFilter(config: OverlayWatermarkConfig) -> String {
        let scaleStr = String(format: "%.2f", config.scale)
        let alphaStr = String(format: "%.2f", config.opacity)

        let (xExpr, yExpr) = overlayPositionExpressions(
            position: config.position,
            margin: config.margin
        )

        return "[1:v]scale=iw*\(scaleStr):ih*\(scaleStr),format=rgba,"
            + "colorchannelmixer=aa=\(alphaStr)[wm];"
            + "[0:v][wm]overlay=x=\(xExpr):y=\(yExpr)"
    }

    // MARK: - Video Arguments

    /// Build complete FFmpeg arguments for watermarking a video file.
    ///
    /// For text watermarks, uses `-vf drawtext=...`. For image watermarks,
    /// uses `-filter_complex` with the watermark image as a second input.
    ///
    /// - Parameters:
    ///   - inputPath: The source video file path.
    ///   - outputPath: The destination video file path.
    ///   - config: The watermark configuration.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildVideoWatermarkArguments(
        inputPath: String,
        outputPath: String,
        config: OverlayWatermarkConfig
    ) -> [String] {
        var args: [String] = ["-y", "-i", inputPath]

        switch config.type {
        case .text:
            let filter = buildTextWatermarkFilter(config: config)
            args += ["-vf", filter]
            args += ["-c:a", "copy"]
            args.append(outputPath)

        case .image:
            guard let imagePath = config.imagePath else {
                // Fall back to no-op copy if no image path is set.
                args += ["-c", "copy"]
                args.append(outputPath)
                return args
            }
            args += ["-i", imagePath]
            let filter = buildImageWatermarkFilter(config: config)
            args += ["-filter_complex", filter]
            args += ["-c:a", "copy"]
            args.append(outputPath)
        }

        return args
    }

    // MARK: - Image Arguments

    /// Build complete FFmpeg arguments for watermarking a still image.
    ///
    /// Uses the same filter logic as video watermarks but without audio
    /// stream handling. Suitable for batch image processing.
    ///
    /// - Parameters:
    ///   - inputPath: The source image file path.
    ///   - outputPath: The destination image file path.
    ///   - config: The watermark configuration.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildImageWatermarkArguments(
        inputPath: String,
        outputPath: String,
        config: OverlayWatermarkConfig
    ) -> [String] {
        var args: [String] = ["-y", "-i", inputPath]

        switch config.type {
        case .text:
            let filter = buildTextWatermarkFilter(config: config)
            args += ["-vf", filter]
            args.append(outputPath)

        case .image:
            guard let imagePath = config.imagePath else {
                args.append(outputPath)
                return args
            }
            args += ["-i", imagePath]
            let filter = buildImageWatermarkFilter(config: config)
            args += ["-filter_complex", filter]
            args.append(outputPath)
        }

        return args
    }

    // MARK: - Private Helpers

    /// Calculate FFmpeg `drawtext` position expressions for the given position.
    ///
    /// - Parameters:
    ///   - position: The watermark position.
    ///   - margin: The pixel margin from the edge.
    /// - Returns: A tuple of `(x, y)` FFmpeg expressions.
    private static func textPositionExpressions(
        position: WatermarkPosition,
        margin: Int
    ) -> (String, String) {
        let m = "\(margin)"
        switch position {
        case .topLeft:
            return (m, m)
        case .topRight:
            return ("w-tw-\(m)", m)
        case .bottomLeft:
            return (m, "h-th-\(m)")
        case .bottomRight:
            return ("w-tw-\(m)", "h-th-\(m)")
        case .center:
            return ("(w-tw)/2", "(h-th)/2")
        }
    }

    /// Calculate FFmpeg `overlay` position expressions for the given position.
    ///
    /// Uses `main_w`/`main_h` for the base video and `overlay_w`/`overlay_h`
    /// for the watermark dimensions.
    ///
    /// - Parameters:
    ///   - position: The watermark position.
    ///   - margin: The pixel margin from the edge.
    /// - Returns: A tuple of `(x, y)` FFmpeg overlay expressions.
    private static func overlayPositionExpressions(
        position: WatermarkPosition,
        margin: Int
    ) -> (String, String) {
        let m = "\(margin)"
        switch position {
        case .topLeft:
            return (m, m)
        case .topRight:
            return ("main_w-overlay_w-\(m)", m)
        case .bottomLeft:
            return (m, "main_h-overlay_h-\(m)")
        case .bottomRight:
            return ("main_w-overlay_w-\(m)", "main_h-overlay_h-\(m)")
        case .center:
            return ("(main_w-overlay_w)/2", "(main_h-overlay_h)/2")
        }
    }
}
