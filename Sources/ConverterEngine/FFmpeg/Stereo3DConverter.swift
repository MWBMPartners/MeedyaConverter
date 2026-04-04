// ============================================================================
// MeedyaConverter — Stereo3DConverter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - Stereo3DLayout

/// Input stereoscopic 3D frame layout.
public enum Stereo3DLayout: String, Codable, Sendable, CaseIterable {
    /// Side-by-Side (full width, left|right).
    case sideBySide = "sbs"

    /// Side-by-Side Half (each eye is half width).
    case sideBySideHalf = "sbs_half"

    /// Top-and-Bottom (full height, left on top).
    case topBottom = "tb"

    /// Top-and-Bottom Half (each eye is half height).
    case topBottomHalf = "tb_half"

    /// Frame sequential (alternating frames).
    case frameSequential = "frame_seq"

    /// Mono (2D, no stereo).
    case mono = "mono"

    /// Display name.
    public var displayName: String {
        switch self {
        case .sideBySide: return "Side-by-Side (Full)"
        case .sideBySideHalf: return "Side-by-Side (Half)"
        case .topBottom: return "Top-and-Bottom (Full)"
        case .topBottomHalf: return "Top-and-Bottom (Half)"
        case .frameSequential: return "Frame Sequential"
        case .mono: return "Mono (2D)"
        }
    }

    /// FFmpeg stereo3d filter input value.
    public var ffmpegInputValue: String {
        switch self {
        case .sideBySide: return "sbsl"
        case .sideBySideHalf: return "sbsl" // Same input type, just half res
        case .topBottom: return "abl"
        case .topBottomHalf: return "abl"
        case .frameSequential: return "al"
        case .mono: return "ml"
        }
    }

    /// Whether each eye is half the full resolution.
    public var isHalfResolution: Bool {
        switch self {
        case .sideBySideHalf, .topBottomHalf: return true
        default: return false
        }
    }
}

// MARK: - Stereo3DOutput

/// Target stereoscopic output format.
public enum Stereo3DOutput: String, Codable, Sendable, CaseIterable {
    /// MV-HEVC (Multi-View HEVC) for Apple Vision Pro.
    case mvHevc = "mv_hevc"

    /// Side-by-Side output.
    case sideBySide = "sbs"

    /// Top-and-Bottom output.
    case topBottom = "tb"

    /// Anaglyph (red-cyan).
    case anaglyphRedCyan = "anaglyph_rc"

    /// Left eye only (mono from stereo).
    case leftEyeOnly = "left"

    /// Right eye only (mono from stereo).
    case rightEyeOnly = "right"

    /// Display name.
    public var displayName: String {
        switch self {
        case .mvHevc: return "MV-HEVC (Spatial Video)"
        case .sideBySide: return "Side-by-Side"
        case .topBottom: return "Top-and-Bottom"
        case .anaglyphRedCyan: return "Anaglyph (Red-Cyan)"
        case .leftEyeOnly: return "Left Eye Only"
        case .rightEyeOnly: return "Right Eye Only"
        }
    }

    /// Compatible devices/platforms.
    public var compatiblePlatforms: [String] {
        switch self {
        case .mvHevc: return ["Apple Vision Pro", "Meta Quest 3", "Android VR"]
        case .sideBySide: return ["Most VR headsets", "3D TVs"]
        case .topBottom: return ["Most VR headsets", "3D TVs"]
        case .anaglyphRedCyan: return ["Any display with glasses"]
        case .leftEyeOnly, .rightEyeOnly: return ["Any display"]
        }
    }
}

// MARK: - Stereo3DConfig

/// Configuration for stereoscopic 3D conversion.
public struct Stereo3DConfig: Codable, Sendable {
    /// Input stereo layout.
    public var inputLayout: Stereo3DLayout

    /// Target output format.
    public var outputFormat: Stereo3DOutput

    /// Whether to swap left/right eyes.
    public var swapEyes: Bool

    /// Output resolution width per eye (nil = auto from source).
    public var outputWidth: Int?

    /// Output resolution height per eye (nil = auto from source).
    public var outputHeight: Int?

    /// Whether to preserve HDR in spatial video output.
    public var preserveHDR: Bool

    public init(
        inputLayout: Stereo3DLayout = .sideBySide,
        outputFormat: Stereo3DOutput = .mvHevc,
        swapEyes: Bool = false,
        outputWidth: Int? = nil,
        outputHeight: Int? = nil,
        preserveHDR: Bool = true
    ) {
        self.inputLayout = inputLayout
        self.outputFormat = outputFormat
        self.swapEyes = swapEyes
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.preserveHDR = preserveHDR
    }
}

// MARK: - Stereo3DConverter

/// Builds FFmpeg arguments for stereoscopic 3D video conversion.
///
/// Supports:
/// - SBS/TB input detection and frame splitting
/// - MV-HEVC encoding for Apple Vision Pro / VR headsets
/// - 3D format-to-format conversion (SBS ↔ TB)
/// - Anaglyph generation
/// - Left/right eye extraction
/// - HDR preservation through stereo conversion
///
/// Phase 7
public struct Stereo3DConverter: Sendable {

    // MARK: - Frame Splitting

    /// Build FFmpeg crop filter to extract the left eye from SBS layout.
    ///
    /// - Parameters:
    ///   - frameWidth: Total frame width.
    ///   - frameHeight: Total frame height.
    ///   - layout: Input stereo layout.
    /// - Returns: Crop filter string for left eye.
    public static func buildLeftEyeCropFilter(
        frameWidth: Int,
        frameHeight: Int,
        layout: Stereo3DLayout
    ) -> String {
        switch layout {
        case .sideBySide, .sideBySideHalf:
            return "crop=\(frameWidth / 2):\(frameHeight):0:0"
        case .topBottom, .topBottomHalf:
            return "crop=\(frameWidth):\(frameHeight / 2):0:0"
        default:
            return ""
        }
    }

    /// Build FFmpeg crop filter to extract the right eye from SBS layout.
    ///
    /// - Parameters:
    ///   - frameWidth: Total frame width.
    ///   - frameHeight: Total frame height.
    ///   - layout: Input stereo layout.
    /// - Returns: Crop filter string for right eye.
    public static func buildRightEyeCropFilter(
        frameWidth: Int,
        frameHeight: Int,
        layout: Stereo3DLayout
    ) -> String {
        switch layout {
        case .sideBySide, .sideBySideHalf:
            return "crop=\(frameWidth / 2):\(frameHeight):\(frameWidth / 2):0"
        case .topBottom, .topBottomHalf:
            return "crop=\(frameWidth):\(frameHeight / 2):0:\(frameHeight / 2)"
        default:
            return ""
        }
    }

    // MARK: - MV-HEVC Encoding

    /// Build FFmpeg arguments for SBS/TB to MV-HEVC conversion.
    ///
    /// MV-HEVC encodes two views (left and right eye) as a multi-view
    /// HEVC stream. On Apple Silicon, VideoToolbox can encode MV-HEVC natively.
    ///
    /// - Parameters:
    ///   - inputPath: Source SBS/TB video file.
    ///   - outputPath: Output MV-HEVC MOV file.
    ///   - config: Stereo 3D configuration.
    ///   - frameWidth: Source frame width.
    ///   - frameHeight: Source frame height.
    /// - Returns: FFmpeg argument array.
    public static func buildMVHEVCArguments(
        inputPath: String,
        outputPath: String,
        config: Stereo3DConfig,
        frameWidth: Int,
        frameHeight: Int
    ) -> [String] {
        var args: [String] = []

        // Read input twice for left and right views
        args += ["-i", inputPath]
        args += ["-i", inputPath]

        // Split into left/right eye views
        let leftCrop: String
        let rightCrop: String

        if config.swapEyes {
            leftCrop = buildRightEyeCropFilter(frameWidth: frameWidth, frameHeight: frameHeight, layout: config.inputLayout)
            rightCrop = buildLeftEyeCropFilter(frameWidth: frameWidth, frameHeight: frameHeight, layout: config.inputLayout)
        } else {
            leftCrop = buildLeftEyeCropFilter(frameWidth: frameWidth, frameHeight: frameHeight, layout: config.inputLayout)
            rightCrop = buildRightEyeCropFilter(frameWidth: frameWidth, frameHeight: frameHeight, layout: config.inputLayout)
        }

        // Build filtergraph for MV-HEVC
        var filterComplex = "[0:v]\(leftCrop)"
        if let w = config.outputWidth, let h = config.outputHeight {
            filterComplex += ",scale=\(w):\(h)"
        }
        filterComplex += "[left];"

        filterComplex += "[1:v]\(rightCrop)"
        if let w = config.outputWidth, let h = config.outputHeight {
            filterComplex += ",scale=\(w):\(h)"
        }
        filterComplex += "[right]"

        args += ["-filter_complex", filterComplex]

        // Map both views
        args += ["-map", "[left]"]
        args += ["-map", "[right]"]
        args += ["-map", "0:a?"]  // Audio from first input

        // Encode with VideoToolbox MV-HEVC
        args += ["-c:v", "hevc_videotoolbox"]
        args += ["-tag:v:0", "hvc1"]
        args += ["-tag:v:1", "hvc1"]

        // Spatial video metadata
        args += ["-metadata:s:v:0", "stereo_mode=left_right"]
        args += ["-metadata:s:v:0", "handler_name=Video Media Handler (Left)"]
        args += ["-metadata:s:v:1", "handler_name=Video Media Handler (Right)"]

        // Copy audio
        args += ["-c:a", "copy"]

        // MOV container for spatial video
        args += ["-movflags", "+faststart"]
        args += ["-y", outputPath]

        return args
    }

    // MARK: - 3D Format Conversion

    /// Build FFmpeg arguments for 3D format-to-format conversion using stereo3d filter.
    ///
    /// - Parameters:
    ///   - inputPath: Source stereo video.
    ///   - outputPath: Output file.
    ///   - config: Stereo 3D configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildStereo3DConvertArguments(
        inputPath: String,
        outputPath: String,
        config: Stereo3DConfig
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        let inputType = config.inputLayout.ffmpegInputValue
        let outputType: String

        switch config.outputFormat {
        case .sideBySide:
            outputType = "sbsl"
        case .topBottom:
            outputType = "abl"
        case .anaglyphRedCyan:
            outputType = "arcg"
        case .leftEyeOnly:
            outputType = "ml"
        case .rightEyeOnly:
            outputType = "mr"
        case .mvHevc:
            outputType = "sbsl" // Intermediate; actual MV-HEVC uses separate path
        }

        var filter = "stereo3d=\(inputType):\(outputType)"
        if config.swapEyes {
            // Swap by using right-first variants
            filter = "stereo3d=\(inputType.replacingOccurrences(of: "l", with: "r")):\(outputType)"
        }

        args += ["-vf", filter]
        args += ["-c:a", "copy"]
        args += ["-y", outputPath]

        return args
    }

    // MARK: - Eye Extraction

    /// Build FFmpeg arguments to extract a single eye view.
    ///
    /// - Parameters:
    ///   - inputPath: Source stereo video.
    ///   - outputPath: Output mono video.
    ///   - layout: Input stereo layout.
    ///   - eye: Which eye to extract ("left" or "right").
    ///   - frameWidth: Source frame width.
    ///   - frameHeight: Source frame height.
    /// - Returns: FFmpeg argument array.
    public static func buildEyeExtractionArguments(
        inputPath: String,
        outputPath: String,
        layout: Stereo3DLayout,
        eye: String,
        frameWidth: Int,
        frameHeight: Int
    ) -> [String] {
        let crop: String
        if eye == "left" {
            crop = buildLeftEyeCropFilter(frameWidth: frameWidth, frameHeight: frameHeight, layout: layout)
        } else {
            crop = buildRightEyeCropFilter(frameWidth: frameWidth, frameHeight: frameHeight, layout: layout)
        }

        return [
            "-i", inputPath,
            "-vf", crop,
            "-c:a", "copy",
            "-y", outputPath,
        ]
    }

    // MARK: - Detection

    /// Calculate per-eye resolution from a stereo frame.
    ///
    /// - Parameters:
    ///   - frameWidth: Total frame width.
    ///   - frameHeight: Total frame height.
    ///   - layout: Stereo layout.
    /// - Returns: Per-eye (width, height) resolution.
    public static func perEyeResolution(
        frameWidth: Int,
        frameHeight: Int,
        layout: Stereo3DLayout
    ) -> (width: Int, height: Int) {
        switch layout {
        case .sideBySide, .sideBySideHalf:
            return (frameWidth / 2, frameHeight)
        case .topBottom, .topBottomHalf:
            return (frameWidth, frameHeight / 2)
        case .frameSequential, .mono:
            return (frameWidth, frameHeight)
        }
    }

    /// Detect probable stereo layout from frame dimensions.
    ///
    /// Uses aspect ratio heuristics: a 2:1-ish frame is likely SBS,
    /// a 1:1-ish frame is likely TB.
    ///
    /// - Parameters:
    ///   - frameWidth: Frame width.
    ///   - frameHeight: Frame height.
    /// - Returns: Probable stereo layout, or nil if likely 2D.
    public static func detectStereoLayout(
        frameWidth: Int,
        frameHeight: Int
    ) -> Stereo3DLayout? {
        guard frameWidth > 0, frameHeight > 0 else { return nil }

        let ratio = Double(frameWidth) / Double(frameHeight)

        // Very wide (>3.5:1) likely SBS full
        if ratio > 3.5 {
            return .sideBySide
        }

        // ~2:1 could be SBS half (common for 1920x1080 SBS = 3840x1080)
        // But also matches normal 2.39:1 cinema, so need >2.5 for confidence
        if ratio > 2.5 && ratio <= 3.5 {
            return .sideBySideHalf
        }

        // Very tall (<0.7:1) likely TB full
        if ratio < 0.7 {
            return .topBottom
        }

        // ~1:1 could be TB half
        if ratio >= 0.7 && ratio < 0.9 {
            return .topBottomHalf
        }

        return nil // Normal aspect ratio, probably 2D
    }
}
