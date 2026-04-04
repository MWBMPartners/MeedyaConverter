// ============================================================================
// MeedyaConverter — SmartCropIntegration
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CropMode

/// Crop detection and application modes.
public enum CropMode: String, Codable, Sendable, CaseIterable {
    /// No cropping.
    case none = "none"

    /// Auto-detect and apply crop (default threshold).
    case auto = "auto"

    /// Auto-detect with aggressive threshold (lower = stricter).
    case aggressive = "aggressive"

    /// Auto-detect with conservative threshold (tolerates noisy blacks).
    case conservative = "conservative"

    /// Manual crop values.
    case manual = "manual"

    /// Display name.
    public var displayName: String {
        switch self {
        case .none: return "No Crop"
        case .auto: return "Auto Detect"
        case .aggressive: return "Aggressive (Strict)"
        case .conservative: return "Conservative (Lenient)"
        case .manual: return "Manual"
        }
    }

    /// Cropdetect threshold (0-255) for this mode.
    public var threshold: Int {
        switch self {
        case .none: return 0
        case .auto: return 24
        case .aggressive: return 16
        case .conservative: return 40
        case .manual: return 0
        }
    }
}

// MARK: - LetterboxType

/// Detected letterbox type based on crop geometry.
public enum LetterboxType: String, Codable, Sendable {
    /// Horizontal black bars (top and bottom) — widescreen in 16:9 frame.
    case letterbox = "letterbox"

    /// Vertical black bars (left and right) — 4:3 in 16:9 frame.
    case pillarbox = "pillarbox"

    /// Black bars on all four sides — small content in larger frame.
    case windowbox = "windowbox"

    /// No black bars detected.
    case none = "none"

    /// Display name.
    public var displayName: String {
        switch self {
        case .letterbox: return "Letterbox (horizontal bars)"
        case .pillarbox: return "Pillarbox (vertical bars)"
        case .windowbox: return "Windowbox (all sides)"
        case .none: return "None"
        }
    }
}

// MARK: - CommonAspectRatio

/// Standard aspect ratios for crop target matching.
public enum CommonAspectRatio: String, Codable, Sendable, CaseIterable {
    case ratio_4_3 = "4:3"
    case ratio_16_9 = "16:9"
    case ratio_21_9 = "21:9"
    case ratio_1_85_1 = "1.85:1"
    case ratio_2_35_1 = "2.35:1"
    case ratio_2_39_1 = "2.39:1"
    case ratio_2_40_1 = "2.40:1"
    case ratio_1_33_1 = "1.33:1"
    case ratio_1_78_1 = "1.78:1"
    case ratio_1_66_1 = "1.66:1"

    /// Numeric aspect ratio value.
    public var numericValue: Double {
        switch self {
        case .ratio_4_3, .ratio_1_33_1: return 4.0 / 3.0
        case .ratio_16_9, .ratio_1_78_1: return 16.0 / 9.0
        case .ratio_21_9: return 21.0 / 9.0
        case .ratio_1_85_1: return 1.85
        case .ratio_2_35_1: return 2.35
        case .ratio_2_39_1: return 2.39
        case .ratio_2_40_1: return 2.40
        case .ratio_1_66_1: return 1.66
        }
    }

    /// Display name.
    public var displayName: String {
        rawValue
    }
}

// MARK: - SmartCropConfig

/// Configuration for smart crop integration with the encoding pipeline.
public struct SmartCropConfig: Codable, Sendable {
    /// Crop mode.
    public var mode: CropMode

    /// Manual crop rectangle (used when mode is .manual).
    public var manualCrop: CropRect?

    /// Minimum confidence to auto-apply crop (0.0-1.0).
    public var minimumConfidence: Double

    /// Whether to snap crop to the nearest standard aspect ratio.
    public var snapToAspectRatio: Bool

    /// Number of sample points for detection.
    public var sampleCount: Int

    /// Whether to preview the crop before applying.
    public var requirePreview: Bool

    /// Maximum percentage of pixels to remove (safety limit).
    public var maxCropPercentage: Double

    /// Round crop values to this multiple (for codec compatibility).
    public var round: Int

    public init(
        mode: CropMode = .auto,
        manualCrop: CropRect? = nil,
        minimumConfidence: Double = 0.7,
        snapToAspectRatio: Bool = true,
        sampleCount: Int = 10,
        requirePreview: Bool = false,
        maxCropPercentage: Double = 40.0,
        round: Int = 2
    ) {
        self.mode = mode
        self.manualCrop = manualCrop
        self.minimumConfidence = minimumConfidence
        self.snapToAspectRatio = snapToAspectRatio
        self.sampleCount = sampleCount
        self.requirePreview = requirePreview
        self.maxCropPercentage = maxCropPercentage
        self.round = round
    }
}

// MARK: - SmartCropIntegration

/// Integrates crop detection with the encoding pipeline, providing
/// intelligent crop analysis, aspect ratio matching, and FFmpeg filter
/// generation.
///
/// Key features:
/// - Detects letterbox/pillarbox/windowbox patterns
/// - Snaps crop to nearest standard aspect ratio
/// - Safety checks against excessive cropping
/// - Generates combined filter chains (crop + scale)
/// - Multi-segment analysis for variable-letterbox content
///
/// Phase 7 / Issues #198, #240
public struct SmartCropIntegration: Sendable {

    // MARK: - Letterbox Detection

    /// Detect the type of letterboxing from a crop rectangle.
    ///
    /// - Parameters:
    ///   - crop: Detected crop rectangle.
    ///   - sourceWidth: Source video width.
    ///   - sourceHeight: Source video height.
    /// - Returns: Detected letterbox type.
    public static func detectLetterboxType(
        crop: CropRect,
        sourceWidth: Int,
        sourceHeight: Int
    ) -> LetterboxType {
        let horizontalCrop = sourceWidth - crop.width
        let verticalCrop = sourceHeight - crop.height

        let horizontalSignificant = horizontalCrop > 10
        let verticalSignificant = verticalCrop > 10

        if horizontalSignificant && verticalSignificant {
            return .windowbox
        } else if verticalSignificant {
            return .letterbox
        } else if horizontalSignificant {
            return .pillarbox
        }
        return .none
    }

    // MARK: - Aspect Ratio Matching

    /// Find the nearest standard aspect ratio to a crop.
    ///
    /// - Parameters:
    ///   - crop: Detected crop rectangle.
    ///   - tolerance: Maximum deviation to consider a match (default 0.03).
    /// - Returns: Matching aspect ratio, or nil if none close enough.
    public static func matchAspectRatio(
        crop: CropRect,
        tolerance: Double = 0.03
    ) -> CommonAspectRatio? {
        let cropRatio = crop.aspectRatio
        guard cropRatio > 0 else { return nil }

        var bestMatch: CommonAspectRatio?
        var bestDiff = Double.greatestFiniteMagnitude

        for ratio in CommonAspectRatio.allCases {
            let diff = abs(cropRatio - ratio.numericValue)
            if diff < bestDiff {
                bestDiff = diff
                bestMatch = ratio
            }
        }

        if bestDiff <= tolerance {
            return bestMatch
        }
        return nil
    }

    /// Snap a crop rectangle to match a standard aspect ratio.
    ///
    /// Adjusts the crop dimensions to exactly match the target ratio
    /// while staying within the source dimensions. Prefers reducing
    /// the wider dimension to avoid increasing the crop area.
    ///
    /// - Parameters:
    ///   - crop: Original crop rectangle.
    ///   - ratio: Target aspect ratio.
    ///   - sourceWidth: Source video width.
    ///   - sourceHeight: Source video height.
    ///   - round: Round to this multiple.
    /// - Returns: Adjusted crop rectangle.
    public static func snapToRatio(
        crop: CropRect,
        ratio: CommonAspectRatio,
        sourceWidth: Int,
        sourceHeight: Int,
        round: Int = 2
    ) -> CropRect {
        let targetRatio = ratio.numericValue
        let currentRatio = crop.aspectRatio

        var newWidth = crop.width
        var newHeight = crop.height

        if currentRatio > targetRatio {
            // Current is wider — reduce width
            newWidth = Int(Double(crop.height) * targetRatio)
        } else {
            // Current is taller — reduce height
            newHeight = Int(Double(crop.width) / targetRatio)
        }

        // Round to multiple
        if round > 1 {
            newWidth = (newWidth / round) * round
            newHeight = (newHeight / round) * round
        }

        // Clamp
        newWidth = min(newWidth, sourceWidth)
        newHeight = min(newHeight, sourceHeight)

        // Center the crop
        let newX = max(0, (sourceWidth - newWidth) / 2)
        let newY = max(0, (sourceHeight - newHeight) / 2)

        return CropRect(width: newWidth, height: newHeight, x: newX, y: newY)
    }

    // MARK: - Safety Checks

    /// Validate that a crop is safe to apply.
    ///
    /// - Parameters:
    ///   - crop: Proposed crop rectangle.
    ///   - sourceWidth: Source video width.
    ///   - sourceHeight: Source video height.
    ///   - config: Smart crop configuration.
    /// - Returns: Array of warnings. Empty means safe.
    public static func validateCrop(
        crop: CropRect,
        sourceWidth: Int,
        sourceHeight: Int,
        config: SmartCropConfig = SmartCropConfig()
    ) -> [String] {
        var warnings: [String] = []

        // Check minimum dimensions
        if crop.width < 64 || crop.height < 64 {
            warnings.append("Cropped dimensions too small (\(crop.width)x\(crop.height)) — minimum 64x64")
        }

        // Check excessive crop
        let sourcePixels = Double(sourceWidth * sourceHeight)
        let croppedPixels = Double(crop.width * crop.height)
        let cropPercentage = (1.0 - croppedPixels / sourcePixels) * 100

        if cropPercentage > config.maxCropPercentage {
            warnings.append("Crop removes \(String(format: "%.1f", cropPercentage))% of pixels — exceeds \(String(format: "%.0f", config.maxCropPercentage))% safety limit")
        }

        // Check alignment
        if crop.width % 2 != 0 || crop.height % 2 != 0 {
            warnings.append("Crop dimensions not even — may cause encoding issues")
        }

        // Check bounds
        if crop.x + crop.width > sourceWidth || crop.y + crop.height > sourceHeight {
            warnings.append("Crop extends beyond source dimensions")
        }

        return warnings
    }

    // MARK: - FFmpeg Filter Generation

    /// Build FFmpeg crop filter arguments.
    ///
    /// - Parameters:
    ///   - crop: Crop rectangle to apply.
    ///   - config: Smart crop configuration.
    /// - Returns: FFmpeg video filter string.
    public static func buildCropFilter(crop: CropRect) -> String {
        return crop.filterString
    }

    /// Build combined crop + scale filter chain.
    ///
    /// When cropping changes the aspect ratio, optionally scale to a
    /// target resolution to maintain clean dimensions.
    ///
    /// - Parameters:
    ///   - crop: Crop rectangle.
    ///   - targetWidth: Optional target width after crop (nil = no scale).
    ///   - targetHeight: Optional target height after crop (nil = no scale).
    /// - Returns: FFmpeg video filter string.
    public static func buildCropAndScaleFilter(
        crop: CropRect,
        targetWidth: Int? = nil,
        targetHeight: Int? = nil
    ) -> String {
        var filters: [String] = [crop.filterString]

        if let w = targetWidth, let h = targetHeight {
            filters.append("scale=\(w):\(h):flags=lanczos")
        } else if let w = targetWidth {
            filters.append("scale=\(w):-2:flags=lanczos")
        } else if let h = targetHeight {
            filters.append("scale=-2:\(h):flags=lanczos")
        }

        return filters.joined(separator: ",")
    }

    /// Build FFmpeg arguments for encoding with smart crop applied.
    ///
    /// - Parameters:
    ///   - inputPath: Source video.
    ///   - outputPath: Output video.
    ///   - crop: Crop rectangle to apply.
    ///   - existingFilters: Additional video filters to chain.
    /// - Returns: FFmpeg argument array (partial — video filter portion).
    public static func buildCropArguments(
        crop: CropRect,
        existingFilters: [String] = []
    ) -> [String] {
        var filters = [crop.filterString] + existingFilters
        return ["-vf", filters.joined(separator: ",")]
    }

    // MARK: - Cropdetect Arguments

    /// Build FFmpeg cropdetect arguments with mode-specific threshold.
    ///
    /// - Parameters:
    ///   - inputPath: Source video.
    ///   - config: Smart crop configuration.
    ///   - seekTo: Timestamp to seek to.
    ///   - frames: Number of frames to analyse.
    /// - Returns: FFmpeg argument array.
    public static func buildCropDetectArguments(
        inputPath: String,
        config: SmartCropConfig = SmartCropConfig(),
        seekTo: Double = 60.0,
        frames: Int = 5
    ) -> [String] {
        return [
            "-ss", String(format: "%.2f", seekTo),
            "-i", inputPath,
            "-vframes", "\(frames)",
            "-vf", "cropdetect=limit=\(config.mode.threshold):round=\(config.round):reset=1",
            "-f", "null",
            "-hide_banner",
            "-",
        ]
    }

    // MARK: - Multi-Segment Analysis

    /// Build FFmpeg arguments for multi-segment crop analysis.
    ///
    /// Analyses crop at multiple points throughout the video to handle
    /// content with variable letterboxing (e.g., IMAX sequences in
    /// otherwise scope-ratio films).
    ///
    /// - Parameters:
    ///   - inputPath: Source video.
    ///   - duration: Video duration in seconds.
    ///   - segments: Number of analysis segments.
    ///   - config: Smart crop configuration.
    /// - Returns: Array of (timestamp, FFmpeg arguments) pairs.
    public static func buildMultiSegmentAnalysisArguments(
        inputPath: String,
        duration: Double,
        segments: Int = 10,
        config: SmartCropConfig = SmartCropConfig()
    ) -> [(timestamp: Double, arguments: [String])] {
        guard duration > 0, segments > 0 else { return [] }

        let start = duration * 0.05
        let end = duration * 0.95
        let step = (end - start) / Double(segments)

        return (0..<segments).map { i in
            let timestamp = start + Double(i) * step
            let args = buildCropDetectArguments(
                inputPath: inputPath,
                config: config,
                seekTo: timestamp
            )
            return (timestamp: timestamp, arguments: args)
        }
    }

    /// Determine if content has variable letterboxing from multi-segment results.
    ///
    /// - Parameter crops: Array of detected crop rectangles from different segments.
    /// - Returns: `true` if multiple distinct crop geometries were detected.
    public static func hasVariableLetterboxing(crops: [CropRect]) -> Bool {
        guard crops.count > 1 else { return false }
        let uniqueCrops = Set(crops.map { "\($0.width)x\($0.height)" })
        return uniqueCrops.count > 1
    }

    /// Select the best crop from variable-letterbox results.
    ///
    /// For variable letterboxing, use the most common crop (mode).
    /// Returns nil if no dominant crop is found.
    ///
    /// - Parameters:
    ///   - crops: All detected crop rectangles.
    ///   - minimumFrequency: Minimum frequency (0.0-1.0) for a crop to be selected.
    /// - Returns: Most common crop, or nil.
    public static func selectBestCrop(
        crops: [CropRect],
        minimumFrequency: Double = 0.5
    ) -> CropRect? {
        guard !crops.isEmpty else { return nil }

        // Group by geometry
        var counts: [String: (count: Int, crop: CropRect)] = [:]
        for crop in crops {
            let key = "\(crop.width)x\(crop.height)"
            if let existing = counts[key] {
                counts[key] = (count: existing.count + 1, crop: crop)
            } else {
                counts[key] = (count: 1, crop: crop)
            }
        }

        // Find most common
        let best = counts.values.max(by: { $0.count < $1.count })
        guard let best = best else { return nil }

        let frequency = Double(best.count) / Double(crops.count)
        if frequency >= minimumFrequency {
            return best.crop
        }

        return nil
    }
}
