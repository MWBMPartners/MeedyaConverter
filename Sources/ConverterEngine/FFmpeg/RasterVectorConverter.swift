// ============================================================================
// MeedyaConverter — RasterVectorConverter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Bidirectional raster ↔ vector conversion pipeline. Raster images are traced
// to editable SVG via potrace (outline/monochrome) or vtracer (colour
// quantisation/photorealistic); both are executed by `RasterVectorExecutor`
// (Direct builds bundle both — potrace is GPL-2.0-or-later, Direct-only;
// vtracer is MIT, ships everywhere). SVG → raster is a separate direction:
// `buildRsvgConvertArguments` below remains an argument builder with NO
// executor — vector→raster is out of scope for #473, and `rsvg-convert` is
// not bundled. There is no autotrace or Inkscape dependency anywhere in this
// pipeline; earlier prose claiming otherwise was aspirational, not real.
//
// GitHub Issue #376 — Raster ↔ Vector image conversion with transparency &
// metadata support. GitHub Issue #473 — potrace/vtracer executor.
// ============================================================================

import Foundation

// MARK: - RasterVectorError

public enum RasterVectorError: LocalizedError, Sendable {
    case unsupportedRasterFormat(String)
    case unsupportedVectorFormat(String)
    case tracingToolNotFound(String)
    case invalidConfiguration(String)
    case operationFailed(String)
    /// A tracer or the ffmpeg pre-pass exited non-zero.
    case toolFailed(tool: String, exitCode: Int32, stderr: String)
    /// The tool reported success but produced no output file.
    case outputMissing(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedRasterFormat(let ext):
            return "Unsupported raster format: \(ext)"
        case .unsupportedVectorFormat(let ext):
            return "Unsupported vector format: \(ext)"
        case .tracingToolNotFound(let tool):
            return "The '\(tool)' tracing tool was not found. The Direct build bundles it in "
                + "Contents/Helpers; otherwise set its path in Settings › Paths."
        case .invalidConfiguration(let detail):
            return "Invalid raster↔vector configuration: \(detail)"
        case .operationFailed(let detail):
            return "Raster↔vector conversion failed: \(detail)"
        case .toolFailed(let tool, let exitCode, let stderr):
            return "\(tool) exited with code \(exitCode): \(stderr.prefix(500))"
        case .outputMissing(let path):
            return "Expected output was not produced: \(path)"
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
///
/// What `RasterVectorExecutor` actually does for each case (no clip-path
/// synthesis is performed — that was an earlier, unimplemented promise):
public enum AlphaStrategy: String, Codable, Sendable, CaseIterable {
    /// Keep the alpha channel: the pre-pass emits RGBA and vtracer traces it
    /// natively (its own colour-cluster handling of the alpha plane); for
    /// potrace (which has no alpha concept) this is composited on white
    /// exactly like `.flatten`, because potrace cannot represent alpha.
    case clipPathWithOpacity = "clip_path_with_opacity"
    /// Composite onto a solid white background before tracing — used when
    /// the target renderer cannot honour transparency, or when the tool
    /// (potrace) has no alpha channel of its own.
    case flatten
    /// Drop the alpha channel entirely (pre-pass emits opaque RGB/greyscale).
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
    /// Reserved for raster inputs — `RasterVectorExecutor` traces the first
    /// frame only; animated raster → animated SVG is not implemented
    /// (#376 follow-up). Kept for JSON/AppStorage compatibility.
    public var animation: AnimationMethod
    /// Reserved — **not applied** by `RasterVectorExecutor`; no bundled tool
    /// implements EXIF/IPTC/XMP preservation. Kept for JSON/AppStorage
    /// compatibility.
    public var preserveMetadata: Bool
    /// Reserved — **not applied** by `RasterVectorExecutor`; no bundled tool
    /// implements OCR. Kept for JSON/AppStorage compatibility.
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
    ///
    /// Targets vtracer **1.0.0-alpha.4**'s kebab-case CLI
    /// (`crates/vtracer-cli/src/main.rs`, clap 4 `rename_all = "kebab-case"`).
    /// The mirror's `--help` build tripwire and `test_vtracerArguments_*`
    /// pin this exact flag set — earlier revisions of this builder emitted
    /// `--colormode`/`--filter_speckle`/`--segment_length`/`--no-alpha`/
    /// `--flatten`/`--preserve-metadata`, none of which exist in ANY released
    /// vtracer version; every run would have exited with a clap usage error.
    /// Alpha handling is done by the ffmpeg pre-pass (`buildPrePassArguments`),
    /// not here — vtracer 1.0's CLI has no alpha flag of its own.
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
            "--mode", vtracerCurveMode(for: config.tracingMode),
            "--filter-speckle", String(min(128, max(0, Int(config.curveSimplification.rounded())))),
            "--color-precision", "8",
            "--gradient-step", "10",
        ]
        switch config.tracingMode {
        case .monochrome, .outline:
            args += ["--clustering", "bw"]
        case .colorQuantization, .photorealistic:
            args += ["--clustering", "color-cluster", "--max-colors", String(config.colorCount)]
        }
        return args
    }

    /// Builds `potrace` arguments for outline/monochrome tracing.
    ///
    /// `inputPath` MUST be BMP/PNM — potrace cannot read PNG (or any other
    /// compressed raster); see `buildPrePassArguments`, which every trace
    /// goes through first.
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
        // 1 px = 1 SVG user unit (potrace's default is 72 dpi already, but
        // pin it explicitly — the ProRes assembly's pixel viewBox depends on
        // this so per-frame potrace output lands in the right place).
        args.append(contentsOf: ["-r", "72"])
        return args
    }

    /// The ffmpeg filter-graph fragment shared by the raster pre-pass
    /// (`buildPrePassArguments`, `.flatten`/potrace's alpha handling) and
    /// `ProResToVectorConverter`'s frame-extraction `.flatten` handling:
    /// composite the RGBA input onto an opaque white background. Kept in one
    /// place so both call sites stay byte-identical. Deliberately WITHOUT the
    /// leading `[0:v]` input-pad label — callers own the input label (and,
    /// for ProRes, may need to prepend `select=`/tonemap filters ahead of it
    /// in the same graph) and append their own final `format=`/`[out]`.
    static let whiteCompositeGraph =
        "format=rgba,split=2[fg][bg];[bg]drawbox=color=white:t=fill[w];[w][fg]overlay=format=auto"

    /// ffmpeg arguments that normalise ANY supported raster (first frame
    /// only) into the one format the chosen tracer can read, applying
    /// `config.alpha`:
    ///   - potrace → 8-bit greyscale BMP (potrace thresholds it; it cannot
    ///     read PNG or any other compressed raster)
    ///   - vtracer → PNG, RGBA when alpha is kept, RGB24 when
    ///     discarded/flattened
    ///
    /// The filter graphs below are deterministic strings; their behaviour on
    /// real ffmpeg is verified only on the manual matrix — CI never runs
    /// ffmpeg on an actual image, so these are string-shape tests only.
    public static func buildPrePassArguments(
        inputPath: String, intermediatePath: String, config: RasterToVectorConfig, tool: String
    ) -> [String] {
        var args = ["-y", "-i", inputPath, "-frames:v", "1"]
        switch (tool, config.alpha) {
        case ("potrace", .discard):
            args += ["-vf", "format=gray"]
        case ("potrace", _):
            args += ["-filter_complex", "[0:v]" + whiteCompositeGraph + ",format=gray[out]", "-map", "[out]"]
        case (_, .flatten):
            args += ["-filter_complex", "[0:v]" + whiteCompositeGraph + ",format=rgb24[out]", "-map", "[out]"]
        case (_, .discard):
            args += ["-vf", "format=rgb24"]
        case (_, .clipPathWithOpacity):
            args += ["-vf", "format=rgba"]
        }
        args += tool == "potrace" ? ["-c:v", "bmp"] : ["-c:v", "png"]
        args.append(intermediatePath)
        return args
    }

    /// Builds `rsvg-convert` arguments for vector→raster.
    ///
    /// Pure argument builder with **no executor** — vector→raster is out of
    /// scope for #473, and `rsvg-convert` is not a bundled tool. Kept for a
    /// future SVG-preview/rasterisation feature.
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
