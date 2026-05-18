// ============================================================================
// MeedyaConverter — RasterVectorConverter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Bidirectional raster ↔ vector conversion pipeline. Raster images are traced
// to editable SVG via potrace / autotrace / vtracer (selected by mode); SVG
// input is rasterised back via librsvg or Inkscape. Alpha, metadata, and —
// for animated inputs (GIF/APNG/WebP) — per-frame animation are preserved.
//
// The public surface here is intentionally "pure plumbing": configuration
// value types, argument builders for each external tool, and enums covering
// the supported formats and tracing modes. Execution glue lives in
// `ImageConverter` (the FFmpeg-backed entry point) and is called by the CLI
// and SwiftUI app when the user requests an SVG output.
//
// GitHub Issue #376 — Raster ↔ Vector image conversion with transparency &
// metadata support.
// ============================================================================

import Foundation

// MARK: - RasterVectorError

public enum RasterVectorError: LocalizedError, Sendable {
    case unsupportedRasterFormat(String)
    case unsupportedVectorFormat(String)
    case tracingToolNotFound(String)
    case invalidConfiguration(String)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedRasterFormat(let ext):
            return "Unsupported raster format: \(ext)"
        case .unsupportedVectorFormat(let ext):
            return "Unsupported vector format: \(ext)"
        case .tracingToolNotFound(let tool):
            return "Tracing tool '\(tool)' not found. Install via Homebrew."
        case .invalidConfiguration(let detail):
            return "Invalid raster↔vector configuration: \(detail)"
        case .operationFailed(let detail):
            return "Raster↔vector conversion failed: \(detail)"
        }
    }
}

// MARK: - RasterFormat (input formats for raster→vector)

/// Raster image formats accepted as inputs. Mirrors the Phase 15 image
/// converter's supported-format table; the tracing pipeline only adds
/// SVG output, it does not change what rasters can be read.
public enum RasterFormat: String, Codable, Sendable, CaseIterable {
    // Common
    case bmp, jpeg, gif, png, tiff, webp, avif, heic, heif
    // Modern
    case jxl                // JPEG XL
    case jp2                // JPEG 2000
    case apng               // Animated PNG
    // Professional
    case psd, exr, hdr, dng, cr2, cr3, nef, arw, raf, orf, rw2, pef
    // Legacy
    case tga, pcx, ico, dds
    case pbm, pgm, ppm, pam // Netpbm

    public var isAnimated: Bool {
        switch self {
        case .gif, .apng, .webp: return true
        default: return false
        }
    }

    public var hasAlphaSupport: Bool {
        switch self {
        case .png, .apng, .tiff, .webp, .avif, .heic, .heif, .jxl, .psd, .exr, .tga, .ico, .dds, .pam:
            return true
        default:
            return false
        }
    }

    public var isHDRCapable: Bool {
        switch self {
        case .exr, .hdr, .avif, .jxl, .heic, .heif, .tiff:
            return true
        default:
            return false
        }
    }

    public static func from(fileExtension: String) -> RasterFormat? {
        let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return Self(rawValue: ext)
            ?? (ext == "jpg" ? .jpeg : nil)
            ?? (ext == "tif" ? .tiff : nil)
    }
}

// MARK: - VectorFormat

/// Vector formats supported as inputs (vector→raster) and outputs
/// (raster→vector). SVG is the primary vector interchange format.
public enum VectorFormat: String, Codable, Sendable, CaseIterable {
    case svg11 = "svg_1.1"
    case svg2  = "svg_2.0"

    public var fileExtension: String { "svg" }
}

// MARK: - TracingMode

/// Tracing strategy for raster→vector conversion. Matches the documented
/// options in the issue acceptance criteria.
public enum TracingMode: String, Codable, Sendable, CaseIterable {
    /// Single outline curve per region — best for logos/icons.
    case outline
    /// Quantise to N colours and trace each plane — best for illustrations.
    case colorQuantization = "color_quantization"
    /// Single-channel B/W trace — best for line art.
    case monochrome
    /// Colour raster stippling approximating photographs — large files.
    case photorealistic
}

// MARK: - EditabilityPreset

/// Presets that pre-fill tracing options so the resulting SVG is editable
/// in a vector app without additional cleanup.
public enum EditabilityPreset: String, Codable, Sendable, CaseIterable {
    case logoIcon = "logo_icon"
    case illustration
    case photorealistic
    case technicalDiagram = "technical_diagram"
    case handDrawnSketch = "hand_drawn_sketch"
    case custom

    /// The tracing mode that best matches this preset.
    public var defaultTracingMode: TracingMode {
        switch self {
        case .logoIcon: return .outline
        case .illustration: return .colorQuantization
        case .photorealistic: return .photorealistic
        case .technicalDiagram: return .outline
        case .handDrawnSketch: return .colorQuantization
        case .custom: return .outline
        }
    }

    /// Recommended colour count for colour-quantisation tracing.
    public var defaultColorCount: Int {
        switch self {
        case .logoIcon: return 8
        case .illustration: return 32
        case .photorealistic: return 256
        case .technicalDiagram: return 4
        case .handDrawnSketch: return 16
        case .custom: return 16
        }
    }
}

// MARK: - AlphaStrategy

/// How the alpha channel is represented in the traced SVG.
public enum AlphaStrategy: String, Codable, Sendable, CaseIterable {
    /// Emit SVG `clip-path` elements for fully-transparent regions and
    /// `fill-opacity` for semi-transparent regions.
    case clipPathWithOpacity = "clip_path_with_opacity"
    /// Flatten against a background colour — useful when target rendering
    /// context cannot honour transparency.
    case flatten
    /// Drop the alpha channel entirely.
    case discard
}

// MARK: - AnimationMethod

/// Animation technique used when the source is an animated raster (GIF,
/// APNG, WebP) and the output is SVG.
public enum AnimationMethod: String, Codable, Sendable, CaseIterable {
    /// SVG SMIL — `<animate>`, `<animateTransform>`, `<animateMotion>`.
    case smil
    /// CSS `@keyframes` + `animation-delay`.
    case cssKeyframes = "css_keyframes"
    /// SMIL path morphing + CSS timing.
    case hybrid
    /// Export per-frame PNG + frame list (no animation).
    case staticFrameSequence = "static_frame_sequence"
}

// MARK: - RasterToVectorConfig

/// Full configuration for a raster→vector conversion.
public struct RasterToVectorConfig: Codable, Sendable {
    public var inputFormat: RasterFormat
    public var outputFormat: VectorFormat
    public var tracingMode: TracingMode
    public var preset: EditabilityPreset
    public var colorCount: Int
    public var alpha: AlphaStrategy
    public var animation: AnimationMethod
    /// Preserve EXIF/IPTC/XMP metadata in SVG `<metadata>` blocks.
    public var preserveMetadata: Bool
    /// Optical character recognition on detected text regions. When on,
    /// text is emitted as `<text>` elements rather than traced paths.
    public var ocrTextRegions: Bool
    /// Tolerance for curve simplification (0.0 = none, 10.0 = very aggressive).
    public var curveSimplification: Double

    public init(
        inputFormat: RasterFormat,
        outputFormat: VectorFormat = .svg2,
        tracingMode: TracingMode? = nil,
        preset: EditabilityPreset = .illustration,
        colorCount: Int? = nil,
        alpha: AlphaStrategy = .clipPathWithOpacity,
        animation: AnimationMethod = .smil,
        preserveMetadata: Bool = true,
        ocrTextRegions: Bool = false,
        curveSimplification: Double = 2.0
    ) {
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.tracingMode = tracingMode ?? preset.defaultTracingMode
        self.preset = preset
        self.colorCount = colorCount ?? preset.defaultColorCount
        self.alpha = alpha
        self.animation = animation
        self.preserveMetadata = preserveMetadata
        self.ocrTextRegions = ocrTextRegions
        self.curveSimplification = curveSimplification
    }
}

// MARK: - VectorToRasterConfig

/// Full configuration for a vector→raster conversion (e.g. SVG → PNG).
public struct VectorToRasterConfig: Codable, Sendable {
    public var inputFormat: VectorFormat
    public var outputFormat: RasterFormat
    /// Desired width in pixels at rasterisation time.
    public var targetWidthPixels: Int
    /// Desired height in pixels at rasterisation time.
    public var targetHeightPixels: Int
    /// Pixel-density factor applied to SVG user-units.
    public var dpi: Int
    public var alpha: AlphaStrategy
    public var preserveMetadata: Bool

    public init(
        inputFormat: VectorFormat = .svg2,
        outputFormat: RasterFormat,
        targetWidthPixels: Int,
        targetHeightPixels: Int,
        dpi: Int = 96,
        alpha: AlphaStrategy = .clipPathWithOpacity,
        preserveMetadata: Bool = true
    ) {
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.targetWidthPixels = targetWidthPixels
        self.targetHeightPixels = targetHeightPixels
        self.dpi = dpi
        self.alpha = alpha
        self.preserveMetadata = preserveMetadata
    }
}

// MARK: - RasterVectorConverter

public enum RasterVectorConverter: Sendable {

    // MARK: Arg builders

    /// Builds the `vtracer` command-line arguments for colour tracing.
    /// Exposed as a pure function so tests can validate the invocation
    /// without requiring vtracer to be installed.
    public static func buildVTracerArguments(
        inputPath: String,
        outputPath: String,
        config: RasterToVectorConfig
    ) -> [String] {
        var args: [String] = [
            "-i", inputPath,
            "-o", outputPath,
            "--colormode", config.tracingMode == .monochrome ? "binary" : "color",
            "--filter_speckle", String(Int(config.curveSimplification.rounded())),
            "--color_precision", "8",
            "--gradient_step", "10",
            "--segment_length", "\(config.colorCount)",
            "--mode", vtracerCurveMode(for: config.tracingMode),
        ]
        switch config.alpha {
        case .discard: args.append("--no-alpha")
        case .flatten: args.append(contentsOf: ["--flatten", "white"])
        case .clipPathWithOpacity: break
        }
        if config.preserveMetadata {
            args.append("--preserve-metadata")
        }
        return args
    }

    /// Builds `potrace` arguments for outline/monochrome tracing.
    public static func buildPotraceArguments(
        inputPath: String,
        outputPath: String,
        config: RasterToVectorConfig
    ) -> [String] {
        var args: [String] = [
            inputPath,
            "-s",                    // SVG output
            "-o", outputPath,
        ]
        // Turdsize: remove speckles below this pixel count.
        args.append(contentsOf: ["-t", String(Int((config.curveSimplification * 4).rounded()))])
        // Alphamax: curve smoothness, mapped from the 0..10 simplification
        // knob onto potrace's 0.0..1.3 range.
        let alphamax = min(1.3, max(0.0, config.curveSimplification * 0.13))
        args.append(contentsOf: ["-a", String(format: "%.2f", alphamax)])
        switch config.outputFormat {
        case .svg2: args.append(contentsOf: ["--svg", "--opttolerance", "0.2"])
        case .svg11: args.append("--svg")
        }
        return args
    }

    /// Builds `librsvg-convert` (rsvg-convert) arguments for vector→raster.
    public static func buildRsvgConvertArguments(
        inputPath: String,
        outputPath: String,
        config: VectorToRasterConfig
    ) -> [String] {
        var args: [String] = [
            inputPath,
            "-o", outputPath,
            "-w", String(config.targetWidthPixels),
            "-h", String(config.targetHeightPixels),
            "-d", String(config.dpi),
            "-p", String(config.dpi),
            "-f", rsvgOutputFormat(for: config.outputFormat),
        ]
        if config.alpha == .discard {
            args.append(contentsOf: ["--background-color", "white"])
        }
        return args
    }

    // MARK: Tool selection

    /// Which external tool handles a given tracing mode.
    public static func preferredTracingTool(
        for mode: TracingMode
    ) -> String {
        switch mode {
        case .outline, .monochrome: return "potrace"
        case .colorQuantization, .photorealistic: return "vtracer"
        }
    }

    // MARK: Validation

    /// Validates a raster→vector config for obvious user errors. Returns
    /// nil if valid; otherwise the specific validation failure.
    public static func validate(_ config: RasterToVectorConfig) -> RasterVectorError? {
        if config.colorCount < 2 || config.colorCount > 256 {
            return .invalidConfiguration("colorCount must be between 2 and 256, got \(config.colorCount)")
        }
        if config.curveSimplification < 0 || config.curveSimplification > 10 {
            return .invalidConfiguration("curveSimplification must be 0..10, got \(config.curveSimplification)")
        }
        if config.animation != .staticFrameSequence && !config.inputFormat.isAnimated {
            // Non-animated sources can still specify an animation method,
            // but it'll just be ignored — warn rather than error.
        }
        if config.inputFormat.isAnimated && config.animation == .staticFrameSequence && config.outputFormat != .svg2 {
            return .invalidConfiguration("Frame-sequence animation requires SVG 2.0 output")
        }
        return nil
    }

    // MARK: Helpers

    private static func vtracerCurveMode(for mode: TracingMode) -> String {
        switch mode {
        case .outline, .monochrome: return "spline"
        case .colorQuantization: return "spline"
        case .photorealistic: return "polygon"
        }
    }

    private static func rsvgOutputFormat(for raster: RasterFormat) -> String {
        switch raster {
        case .png: return "png"
        case .jpeg: return "jpeg"
        default: return "png"
        }
    }
}
