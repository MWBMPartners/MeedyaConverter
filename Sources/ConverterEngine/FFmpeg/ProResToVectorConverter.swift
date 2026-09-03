// ============================================================================
// MeedyaConverter — ProResToVectorConverter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Converts Apple ProRes 4444 / 4444 XQ video (with alpha channel) to an
// animated, editable vector SVG. The pipeline is:
//
//   ProRes 4444 → frame extraction (FFmpeg, preserving alpha) →
//   per-frame raster tracing (potrace/vtracer via RasterVectorConverter) →
//   animated SVG assembly (SMIL or CSS)
//
// Static ProRes 422 variants (without alpha) are out of scope — the standard
// video pipeline handles those. This converter exists specifically for the
// motion-graphics / VFX case where an animated asset with alpha needs to be
// re-expressed as a scalable vector asset for web/editor reuse.
//
// This file lands the deterministic configuration + argument builders.
// Execution lives in `ProResVectorExecutor` (#473).
//
// GitHub Issue #377 — ProRes with alpha → animated vector SVG conversion.
// ============================================================================

import Foundation

// MARK: - ProResVariant

/// ProRes variants that carry an alpha channel. Standard 4:2:2 variants
/// (422, 422 HQ, 422 LT, 422 Proxy) are intentionally omitted — they have
/// no alpha and are handled by the main video pipeline.
public enum ProResVariant: String, Codable, Sendable, CaseIterable {
    /// ProRes 4444 — 4:4:4:4 with full alpha (8 bpc per channel).
    case proRes4444 = "prores_4444"
    /// ProRes 4444 XQ — highest quality with alpha (12 bpc per channel).
    case proRes4444XQ = "prores_4444_xq"
    /// ProRes 4444 HDR — HDR variant with alpha; requires tone-mapping
    /// before tracing.
    case proRes4444HDR = "prores_4444_hdr"

    public var displayName: String {
        switch self {
        case .proRes4444: return "ProRes 4444"
        case .proRes4444XQ: return "ProRes 4444 XQ"
        case .proRes4444HDR: return "ProRes 4444 (HDR)"
        }
    }

    /// FFmpeg `profile` value used in the `-c:v prores_ks -profile:v N` form.
    public var ffmpegProfileIndex: Int {
        switch self {
        case .proRes4444: return 4
        case .proRes4444XQ: return 5
        case .proRes4444HDR: return 5
        }
    }

    public var bitsPerChannel: Int {
        switch self {
        case .proRes4444: return 8
        case .proRes4444XQ, .proRes4444HDR: return 12
        }
    }

    public var requiresTonemapping: Bool {
        self == .proRes4444HDR
    }
}

// MARK: - ProResFrameRate

/// Common ProRes frame rates. The converter preserves the source frame rate
/// unless the user explicitly overrides it (e.g. for thinning a 60 fps
/// source down to 30 fps before tracing).
public enum ProResFrameRate: String, Codable, Sendable, CaseIterable {
    case fps23_976 = "23.976"
    case fps24 = "24"
    case fps25 = "25"
    case fps29_97 = "29.97"
    case fps30 = "30"
    case fps50 = "50"
    case fps59_94 = "59.94"
    case fps60 = "60"

    public var doubleValue: Double {
        switch self {
        case .fps23_976: return 24000.0 / 1001.0
        case .fps24: return 24.0
        case .fps25: return 25.0
        case .fps29_97: return 30000.0 / 1001.0
        case .fps30: return 30.0
        case .fps50: return 50.0
        case .fps59_94: return 60000.0 / 1001.0
        case .fps60: return 60.0
        }
    }
}

// MARK: - ProResAlphaHandling

/// How the pre-multiplied alpha in ProRes 4444 should be represented in
/// the traced SVG.
public enum ProResAlphaHandling: String, Codable, Sendable, CaseIterable {
    /// Convert pre-multiplied → straight alpha and emit per-frame clip-paths.
    case preservePerFrame = "preserve_per_frame"
    /// Extract the alpha matte as a monochrome animated SVG (useful for
    /// compositing workflows).
    case alphaMatteOnly = "alpha_matte_only"
    /// Flatten against a background colour — drops alpha information.
    case flatten
}

// MARK: - ProResToVectorConfig

/// Full configuration for a ProRes → animated SVG conversion.
public struct ProResToVectorConfig: Codable, Sendable {
    public var sourceVariant: ProResVariant
    public var frameRate: ProResFrameRate
    /// Start timecode in seconds.
    public var startTimeSeconds: Double?
    /// End timecode in seconds (nil = end of clip).
    public var endTimeSeconds: Double?
    /// Sample every Nth frame (1 = every frame). Useful for long clips.
    public var frameStride: Int
    /// Alpha handling strategy.
    public var alphaHandling: ProResAlphaHandling
    /// Raster → vector tracing config for each extracted frame.
    public var tracing: RasterToVectorConfig
    /// Animation method for the assembled SVG.
    public var animation: AnimationMethod
    /// Enable shape-identity tracking across frames (consistent `id`
    /// attributes for animated elements).
    public var shapePersistence: Bool
    /// Enable keyframe extraction (only re-trace significant visual
    /// changes; `<animate>` between keyframes).
    public var keyframeExtraction: Bool

    public init(
        sourceVariant: ProResVariant = .proRes4444,
        frameRate: ProResFrameRate = .fps24,
        startTimeSeconds: Double? = nil,
        endTimeSeconds: Double? = nil,
        frameStride: Int = 1,
        alphaHandling: ProResAlphaHandling = .preservePerFrame,
        tracing: RasterToVectorConfig = RasterToVectorConfig(
            inputFormat: .png,
            preset: .illustration
        ),
        animation: AnimationMethod = .smil,
        shapePersistence: Bool = true,
        keyframeExtraction: Bool = true
    ) {
        self.sourceVariant = sourceVariant
        self.frameRate = frameRate
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.frameStride = frameStride
        self.alphaHandling = alphaHandling
        self.tracing = tracing
        self.animation = animation
        self.shapePersistence = shapePersistence
        self.keyframeExtraction = keyframeExtraction
    }

    /// Estimated number of frames the trace pipeline will process, given
    /// a source duration. The caller can use this to surface a warning when
    /// output size would be large (see issue acceptance criteria).
    public func estimatedFrameCount(sourceDurationSeconds: Double) -> Int {
        let start = startTimeSeconds ?? 0
        let end = endTimeSeconds ?? sourceDurationSeconds
        let duration = max(0, end - start)
        let frames = duration * frameRate.doubleValue
        let strided = Int(frames.rounded()) / max(1, frameStride)
        return max(0, strided)
    }
}

// MARK: - ProResToVectorConverter

public enum ProResToVectorConverter: Sendable {

    /// Builds the FFmpeg argument list for extracting PNG frames from a
    /// ProRes 4444 source. The frames are the input to the tracing stage.
    ///
    /// Emits exactly ONE `-vf` chain — an earlier revision emitted two
    /// `-vf` flags when `frameStride > 1`, and ffmpeg keeps only the LAST
    /// one, silently dropping the `format=rgba` / HDR tonemap chain on every
    /// strided extraction. `select=` runs before the tonemap so dropped
    /// frames are never wastefully tonemapped, and stride uses `-fps_mode
    /// vfr` (the modern spelling of `-vsync vfr`) instead of `-r <fps>` —
    /// combining `-r` with `select=` made ffmpeg duplicate kept frames to
    /// hold the output rate, defeating the stride entirely.
    public static func buildFrameExtractionArguments(
        inputPath: String,
        framePatternPath: String,
        config: ProResToVectorConfig
    ) -> [String] {
        var args: [String] = ["-y"]
        if let start = config.startTimeSeconds {
            args.append(contentsOf: ["-ss", String(format: "%.3f", start)])
        }
        args.append(contentsOf: ["-i", inputPath])
        if let end = config.endTimeSeconds, let start = config.startTimeSeconds {
            args.append(contentsOf: ["-t", String(format: "%.3f", end - start)])
        } else if let end = config.endTimeSeconds {
            args.append(contentsOf: ["-t", String(format: "%.3f", end)])
        }

        var prefixFilters: [String] = []
        if config.frameStride > 1 {
            prefixFilters.append("select=not(mod(n\\,\(config.frameStride)))")
        }
        if config.sourceVariant.requiresTonemapping {
            prefixFilters.append("zscale=t=linear:npl=100,tonemap=hable,zscale=t=bt709:m=bt709:r=tv")
        }

        // `.flatten` needs the two-input white-composite overlay
        // (`RasterVectorConverter.whiteCompositeGraph`), which has labelled
        // pads a plain `-vf` chain cannot express — that requires
        // `-filter_complex` + `-map "[out]"`, exactly as the raster pre-pass
        // does for the same graph. Every other alpha handling is a plain
        // single-input/single-output filter and fits a `-vf` chain. Either
        // way this emits exactly ONE filter flag, chaining `select=`/tonemap
        // ahead of it — never a second `-vf` silently clobbering the first
        // (the historical bug this rewrite fixes).
        if config.alphaHandling == .flatten {
            let prefix = prefixFilters.isEmpty ? "" : prefixFilters.joined(separator: ",") + ","
            let graph = "[0:v]" + prefix + alphaFilter(for: .flatten) + "[out]"
            args.append(contentsOf: ["-filter_complex", graph, "-map", "[out]"])
        } else {
            let filters = prefixFilters + [alphaFilter(for: config.alphaHandling)]
            args.append(contentsOf: ["-vf", filters.joined(separator: ",")])
        }

        if config.frameStride > 1 {
            args.append(contentsOf: ["-fps_mode", "vfr"])   // keep only the selected frames
        } else {
            args.append(contentsOf: ["-r", String(format: "%.6f", config.frameRate.doubleValue)])
        }
        args.append(contentsOf: [
            "-vcodec", "png",
            "-pix_fmt", config.alphaHandling == .preservePerFrame ? "rgba" : "rgb24",
            framePatternPath,
        ])
        return args
    }

    /// The filter fragment for a given alpha-handling strategy (without any
    /// input/output pad labels — the caller adds those). `.preservePerFrame`
    /// and `.alphaMatteOnly` are single-input/single-output and fit directly
    /// into a `-vf` chain; `.flatten`'s two-input overlay graph is only ever
    /// used via the `-filter_complex` branch in `buildFrameExtractionArguments`.
    private static func alphaFilter(for handling: ProResAlphaHandling) -> String {
        switch handling {
        case .preservePerFrame:
            return "format=rgba"
        case .flatten:
            return RasterVectorConverter.whiteCompositeGraph + ",format=rgb24"
        case .alphaMatteOnly:
            return "alphaextract,format=gray"
        }
    }

    /// Build the XML root element for an animated SVG container. Accepts the
    /// source dimensions, frame count, and frame rate. The per-frame
    /// `<g id="frameN">` elements are filled in by the assembly stage.
    public static func buildSVGAnimationRoot(
        widthPixels: Int,
        heightPixels: Int,
        frameCount: Int,
        frameRate: Double,
        method: AnimationMethod
    ) -> String {
        let duration = Double(frameCount) / frameRate
        switch method {
        case .smil:
            return """
            <svg xmlns="http://www.w3.org/2000/svg" \
            viewBox="0 0 \(widthPixels) \(heightPixels)" \
            width="\(widthPixels)" height="\(heightPixels)" \
            data-frame-count="\(frameCount)" \
            data-frame-rate="\(String(format: "%.6f", frameRate))" \
            data-duration="\(String(format: "%.6f", duration))" \
            data-animation-method="smil">
            """
        case .cssKeyframes:
            return """
            <svg xmlns="http://www.w3.org/2000/svg" \
            viewBox="0 0 \(widthPixels) \(heightPixels)" \
            width="\(widthPixels)" height="\(heightPixels)" \
            data-frame-count="\(frameCount)" \
            data-animation-method="css-keyframes">
            <style>@keyframes framecycle { from { opacity: 0; } to { opacity: 1; } }</style>
            """
        case .hybrid:
            return """
            <svg xmlns="http://www.w3.org/2000/svg" \
            viewBox="0 0 \(widthPixels) \(heightPixels)" \
            width="\(widthPixels)" height="\(heightPixels)" \
            data-frame-count="\(frameCount)" \
            data-animation-method="hybrid">
            """
        case .staticFrameSequence:
            return """
            <svg xmlns="http://www.w3.org/2000/svg" \
            viewBox="0 0 \(widthPixels) \(heightPixels)" \
            width="\(widthPixels)" height="\(heightPixels)" \
            data-frame-count="\(frameCount)" \
            data-animation-method="frame-sequence">
            """
        }
    }

    /// Build a per-frame `<g>` wrapper with SMIL timing, assuming the
    /// frame SVG fragment is inserted inside it by the caller.
    ///
    /// Uses `<set>` rather than `<animate … fill="freeze">`: `freeze` leaves
    /// every EARLIER frame's opacity at 1 once its animation completes, so
    /// alpha frames stacked visibly instead of showing one at a time.
    /// `<set … fill="remove">` is visible only during its own `[begin, begin
    /// + dur)` slot, which is what a frame-by-frame flip-book needs.
    public static func buildSMILFrameWrapper(
        frameIndex: Int,
        frameCount: Int,
        frameRate: Double
    ) -> String {
        let begin = Double(frameIndex) / frameRate
        let durPerFrame = 1.0 / frameRate
        return """
        <g id="frame-\(frameIndex)" opacity="0">
            <set attributeName="opacity" \
            to="1" \
            begin="\(String(format: "%.6f", begin))s" \
            dur="\(String(format: "%.6f", durPerFrame))s" \
            fill="remove"/>
        """
    }

    /// Closing tags for the per-frame `<g>` wrapper and the outer `<svg>`
    /// root, shared with `ProResVectorExecutor`'s assembly so the templates
    /// live in one file.
    public static let svgClosingTag = "</svg>"
    public static let frameClosingTag = "</g>"

    /// Recommended warning threshold for output-size. Beyond ~10 seconds at
    /// 24 fps of colour-quantised tracing, animated SVG file sizes become
    /// impractical.
    public static let recommendedMaxDurationSeconds: Double = 10.0

    /// Returns true when the estimated output is projected to be very large
    /// and the UI should warn the user.
    public static func shouldWarnAboutOutputSize(
        config: ProResToVectorConfig,
        sourceDurationSeconds: Double
    ) -> Bool {
        let frames = config.estimatedFrameCount(
            sourceDurationSeconds: sourceDurationSeconds
        )
        let effectiveDuration = Double(frames) / config.frameRate.doubleValue
        return effectiveDuration > recommendedMaxDurationSeconds
            || config.tracing.tracingMode == .photorealistic
    }
}
