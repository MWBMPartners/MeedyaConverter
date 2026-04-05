// ============================================================================
// MeedyaConverter — FrameNavigator (Issue #341)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FrameNavigator

/// Frame-accurate navigation and trimming utilities for video media.
///
/// Provides conversions between frame numbers and timestamps, frame
/// extraction as still images, and GOP-aware (Group of Pictures) trim
/// argument generation for frame-accurate cutting.
///
/// GOP alignment is important because most video codecs (H.264, H.265)
/// use inter-frame compression where only keyframes (I-frames) can serve
/// as clean cut points without re-encoding. When ``keyframeAlign`` is
/// enabled, trim boundaries are snapped to the nearest keyframe for
/// lossless stream copy. When disabled, FFmpeg decodes and re-encodes
/// the partial GOPs at the cut boundaries for sample-accurate output.
///
/// Phase 12 — Frame-Accurate Trimming (Issue #341)
public struct FrameNavigator: Sendable {

    // MARK: - Frame Extraction

    /// Build FFmpeg arguments to extract a specific frame as a still image.
    ///
    /// Uses `-vf "select=eq(n\\,FRAME)"` to select the exact frame and
    /// outputs a single PNG image.
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source video file.
    ///   - outputPath: Absolute path for the output image (e.g., `.png`).
    ///   - frameNumber: Zero-based frame number to extract.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildFrameExtractArguments(
        inputPath: String,
        outputPath: String,
        frameNumber: Int
    ) -> [String] {
        return [
            "-i", inputPath,
            "-vf", "select=eq(n\\,\(frameNumber))",
            "-frames:v", "1",
            "-vsync", "vfr",
            "-y", outputPath
        ]
    }

    // MARK: - Frame / Timestamp Conversion

    /// Convert a zero-based frame number to a timestamp in seconds.
    ///
    /// - Parameters:
    ///   - frame: Zero-based frame number.
    ///   - fps: Frames per second of the video stream.
    /// - Returns: Timestamp in seconds corresponding to the given frame.
    public static func timestampForFrame(_ frame: Int, fps: Double) -> TimeInterval {
        guard fps > 0 else { return 0 }
        return Double(frame) / fps
    }

    /// Convert a timestamp in seconds to a zero-based frame number.
    ///
    /// - Parameters:
    ///   - time: Timestamp in seconds.
    ///   - fps: Frames per second of the video stream.
    /// - Returns: Zero-based frame number closest to the given timestamp.
    public static func frameForTimestamp(_ time: TimeInterval, fps: Double) -> Int {
        guard fps > 0 else { return 0 }
        return Int((time * fps).rounded(.down))
    }

    // MARK: - GOP-Aligned Trimming

    /// Build FFmpeg arguments for GOP-aware frame-accurate trimming.
    ///
    /// When ``keyframeAlign`` is `true`, the start and end times are used
    /// with `-c copy` for lossless cutting (snapped to nearest keyframe).
    /// When `false`, FFmpeg decodes and re-encodes to achieve exact frame
    /// boundaries, which is slower but sample-accurate.
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source video file.
    ///   - outputPath: Absolute path for the trimmed output file.
    ///   - startFrame: Zero-based start frame number.
    ///   - endFrame: Zero-based end frame number (exclusive).
    ///   - fps: Frames per second of the video stream.
    ///   - keyframeAlign: When `true`, snap to nearest keyframe for lossless
    ///     copy. When `false`, re-encode for frame-accurate boundaries.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildGOPAlignedTrimArguments(
        inputPath: String,
        outputPath: String,
        startFrame: Int,
        endFrame: Int,
        fps: Double,
        keyframeAlign: Bool
    ) -> [String] {
        let startTime = timestampForFrame(startFrame, fps: fps)
        let endTime = timestampForFrame(endFrame, fps: fps)

        var args: [String] = []

        if keyframeAlign {
            // Lossless: seek before input, copy streams.
            // FFmpeg will snap to the nearest keyframe before startTime.
            args += [
                "-ss", formatTimestamp(startTime),
                "-i", inputPath,
                "-to", formatTimestamp(endTime - startTime),
                "-c", "copy",
                "-avoid_negative_ts", "make_zero",
                "-y", outputPath
            ]
        } else {
            // Frame-accurate: decode and re-encode partial GOPs.
            // Place -ss after -i so FFmpeg decodes from the previous
            // keyframe and discards frames before startTime.
            args += [
                "-i", inputPath,
                "-ss", formatTimestamp(startTime),
                "-to", formatTimestamp(endTime),
                "-y", outputPath
            ]
        }

        return args
    }

    // MARK: - Helpers

    /// Format a time interval as an FFmpeg-compatible timestamp string.
    ///
    /// Produces `HH:MM:SS.mmm` format suitable for `-ss` and `-to` arguments.
    ///
    /// - Parameter time: Time in seconds.
    /// - Returns: Formatted timestamp string.
    private static func formatTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = time.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%02d:%06.3f", hours, minutes, seconds)
    }
}
