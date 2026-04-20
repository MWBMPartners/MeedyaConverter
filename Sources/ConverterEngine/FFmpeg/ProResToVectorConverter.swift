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
// Execution glue (frame dump → trace-each → SVG assembly) is a follow-up.
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

    /// Builds the FFmpeg argument list for extracting RGBA PNG frames from
    /// a ProRes 4444 source. The frames are the input to the tracing stage.
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

        // Tone-map HDR sources to SDR before tracing.
        if config.sourceVariant.requiresTonemapping {
            args.append(contentsOf: [
                "-vf",
                "zscale=t=linear:npl=100,tonemap=hable,zscale=t=bt709:m=bt709:r=tv,format=rgba"
            ])
        } else {
            args.append(contentsOf: ["-vf", "format=rgba"])
        }

        if config.frameStride > 1 {
            args.append(contentsOf: ["-vf", "select=not(mod(n\\,\(config.frameStride)))"])
        }
        args.append(contentsOf: [
            "-r", String(format: "%.6f", config.frameRate.doubleValue),
            "-vcodec", "png",
            "-pix_fmt", "rgba",
            framePatternPath,
        ])
        return args
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
    public static func buildSMILFrameWrapper(
        frameIndex: Int,
        frameCount: Int,
        frameRate: Double
    ) -> String {
        let begin = Double(frameIndex) / frameRate
        let durPerFrame = 1.0 / frameRate
        return """
        <g id="frame-\(frameIndex)" opacity="0">
            <animate attributeName="opacity" \
            from="0" to="1" \
            begin="\(String(format: "%.6f", begin))s" \
            dur="\(String(format: "%.6f", durPerFrame))s" \
            fill="freeze"/>
        """
    }

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
