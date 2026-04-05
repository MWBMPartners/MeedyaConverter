// ============================================================================
// MeedyaConverter — FrameComparisonExtractor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ComparisonFrame

/// A pair of frames extracted from source and encoded files at the same timestamp.
public struct ComparisonFrame: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: TimeInterval
    public let sourceImagePath: String
    public let encodedImagePath: String

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        sourceImagePath: String,
        encodedImagePath: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceImagePath = sourceImagePath
        self.encodedImagePath = encodedImagePath
    }

    /// Formatted timestamp string (MM:SS.s).
    public var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        let tenths = Int((timestamp.truncatingRemainder(dividingBy: 1.0)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, tenths)
    }
}

// MARK: - ComparisonMode

/// Display mode for the A/B comparison viewer.
public enum ComparisonMode: String, Codable, Sendable, CaseIterable {
    /// Side-by-side horizontal split.
    case sideBySide = "side_by_side"

    /// Vertical slider wipe between source and encoded.
    case slider = "slider"

    /// Toggle between source and encoded on click/tap.
    case toggle = "toggle"

    /// Difference visualization (pixel diff).
    case difference = "difference"

    /// Display name.
    public var displayName: String {
        switch self {
        case .sideBySide: return "Side by Side"
        case .slider: return "Slider"
        case .toggle: return "Toggle"
        case .difference: return "Difference"
        }
    }
}

// MARK: - FrameComparisonExtractor

/// Extracts matching frames from source and encoded videos for A/B comparison.
///
/// Uses FFmpeg to extract PNG frames at specified timestamps from both the
/// original source and the encoded output, enabling visual quality comparison.
///
/// Phase 7.11
public struct FrameComparisonExtractor: Sendable {

    /// Build FFmpeg arguments to extract a single frame at a given timestamp.
    ///
    /// - Parameters:
    ///   - inputPath: Video file path.
    ///   - outputPath: Output image path (PNG recommended for lossless comparison).
    ///   - timestamp: Timestamp in seconds to extract.
    ///   - width: Optional resize width (maintains aspect ratio if height is nil).
    ///   - height: Optional resize height.
    /// - Returns: FFmpeg argument array.
    public static func buildFrameExtractionArguments(
        inputPath: String,
        outputPath: String,
        timestamp: TimeInterval,
        width: Int? = nil,
        height: Int? = nil
    ) -> [String] {
        var args = [
            "-ss", String(format: "%.3f", timestamp),
            "-i", inputPath,
            "-frames:v", "1",
        ]

        if let w = width, let h = height {
            args += ["-vf", "scale=\(w):\(h)"]
        } else if let w = width {
            args += ["-vf", "scale=\(w):-1"]
        }

        args += [
            "-update", "1",
            "-y",
            outputPath,
        ]
        return args
    }

    /// Build FFmpeg arguments to generate a pixel-difference image between two frames.
    ///
    /// Uses the blend filter to highlight differences between source and encoded.
    ///
    /// - Parameters:
    ///   - sourcePath: Source frame image path.
    ///   - encodedPath: Encoded frame image path.
    ///   - outputPath: Output difference image path.
    ///   - amplify: Amplification factor for differences (1-10). Higher = more visible.
    /// - Returns: FFmpeg argument array.
    public static func buildDifferenceArguments(
        sourcePath: String,
        encodedPath: String,
        outputPath: String,
        amplify: Int = 5
    ) -> [String] {
        _ = max(1, min(10, amplify))
        return [
            "-i", sourcePath,
            "-i", encodedPath,
            "-filter_complex",
            "[0:v][1:v]blend=all_mode=difference,curves=all='0/0 0.1/1'[diff]",
            "-map", "[diff]",
            "-frames:v", "1",
            "-y",
            outputPath,
        ]
    }

    /// Calculate evenly-spaced timestamps for frame extraction.
    ///
    /// - Parameters:
    ///   - duration: Total video duration in seconds.
    ///   - count: Number of frames to extract.
    ///   - excludeEdges: Seconds to exclude from start/end (avoids black frames).
    /// - Returns: Array of timestamps in seconds.
    public static func calculateTimestamps(
        duration: TimeInterval,
        count: Int = 10,
        excludeEdges: TimeInterval = 2.0
    ) -> [TimeInterval] {
        let clampedCount = max(1, count)
        let effectiveStart = min(excludeEdges, duration * 0.1)
        let effectiveEnd = max(duration - excludeEdges, duration * 0.9)
        let effectiveDuration = effectiveEnd - effectiveStart

        guard effectiveDuration > 0 else {
            return [duration / 2]
        }

        if clampedCount == 1 {
            return [effectiveStart + effectiveDuration / 2]
        }

        let interval = effectiveDuration / Double(clampedCount - 1)
        return (0..<clampedCount).map { i in
            effectiveStart + Double(i) * interval
        }
    }

    /// Build the output directory structure for comparison frames.
    ///
    /// - Parameter baseDirectory: Base temporary directory for the job.
    /// - Returns: Paths for source frames, encoded frames, and difference images.
    public static func buildOutputPaths(
        baseDirectory: String
    ) -> (sourceDir: String, encodedDir: String, diffDir: String) {
        return (
            sourceDir: "\(baseDirectory)/comparison/source",
            encodedDir: "\(baseDirectory)/comparison/encoded",
            diffDir: "\(baseDirectory)/comparison/diff"
        )
    }

    /// Build a batch of frame extraction argument sets for both source and encoded files.
    ///
    /// - Parameters:
    ///   - sourcePath: Source video file path.
    ///   - encodedPath: Encoded video file path.
    ///   - timestamps: Timestamps at which to extract frames.
    ///   - outputDirectory: Base directory for output frames.
    ///   - width: Optional frame width for resizing.
    /// - Returns: Array of (sourceArgs, encodedArgs, timestamp) tuples.
    public static func buildBatchExtractionArguments(
        sourcePath: String,
        encodedPath: String,
        timestamps: [TimeInterval],
        outputDirectory: String,
        width: Int? = nil
    ) -> [(sourceArgs: [String], encodedArgs: [String], timestamp: TimeInterval)] {
        let paths = buildOutputPaths(baseDirectory: outputDirectory)

        return timestamps.enumerated().map { index, timestamp in
            let sourceOutput = "\(paths.sourceDir)/frame_\(String(format: "%04d", index)).png"
            let encodedOutput = "\(paths.encodedDir)/frame_\(String(format: "%04d", index)).png"

            let sourceArgs = buildFrameExtractionArguments(
                inputPath: sourcePath,
                outputPath: sourceOutput,
                timestamp: timestamp,
                width: width
            )
            let encodedArgs = buildFrameExtractionArguments(
                inputPath: encodedPath,
                outputPath: encodedOutput,
                timestamp: timestamp,
                width: width
            )

            return (sourceArgs, encodedArgs, timestamp)
        }
    }

    // MARK: - Quality Metrics Integration

    /// Build FFmpeg arguments for SSIM comparison between source and encoded.
    ///
    /// - Parameters:
    ///   - sourcePath: Source video file path.
    ///   - encodedPath: Encoded video file path.
    /// - Returns: FFmpeg argument array.
    public static func buildSSIMArguments(
        sourcePath: String,
        encodedPath: String
    ) -> [String] {
        return [
            "-i", sourcePath,
            "-i", encodedPath,
            "-lavfi", "ssim",
            "-f", "null",
            "-",
        ]
    }

    /// Build FFmpeg arguments for PSNR comparison between source and encoded.
    ///
    /// - Parameters:
    ///   - sourcePath: Source video file path.
    ///   - encodedPath: Encoded video file path.
    /// - Returns: FFmpeg argument array.
    public static func buildPSNRArguments(
        sourcePath: String,
        encodedPath: String
    ) -> [String] {
        return [
            "-i", sourcePath,
            "-i", encodedPath,
            "-lavfi", "psnr",
            "-f", "null",
            "-",
        ]
    }

    /// Parse SSIM value from FFmpeg output.
    ///
    /// FFmpeg outputs: `[Parsed_ssim_0 @ 0x...] SSIM Y:0.984532 ...  All:0.982145 (17.493721)`
    ///
    /// - Parameter output: FFmpeg stderr output.
    /// - Returns: Overall SSIM value (0.0-1.0), or nil if not found.
    public static func parseSSIM(from output: String) -> Double? {
        let lines = output.split(separator: "\n")
        for line in lines {
            guard line.contains("SSIM") && line.contains("All:") else { continue }
            let str = String(line)
            guard let allRange = str.range(of: "All:") else { continue }
            let afterAll = str[allRange.upperBound...]
            let valueStr = afterAll.prefix(while: { $0.isNumber || $0 == "." })
            return Double(valueStr)
        }
        return nil
    }

    /// Parse PSNR value from FFmpeg output.
    ///
    /// FFmpeg outputs: `[Parsed_psnr_0 @ 0x...] ... average:42.123456 ...`
    ///
    /// - Parameter output: FFmpeg stderr output.
    /// - Returns: Average PSNR in dB, or nil if not found.
    public static func parsePSNR(from output: String) -> Double? {
        let lines = output.split(separator: "\n")
        for line in lines {
            guard line.contains("PSNR") && line.contains("average:") else { continue }
            let str = String(line)
            guard let avgRange = str.range(of: "average:") else { continue }
            let afterAvg = str[avgRange.upperBound...]
            let valueStr = afterAvg.prefix(while: { $0.isNumber || $0 == "." })
            return Double(valueStr)
        }
        return nil
    }
}
