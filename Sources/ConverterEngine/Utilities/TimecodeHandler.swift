// ============================================================================
// MeedyaConverter — TimecodeHandler (Issue #338)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - Timecode
// ---------------------------------------------------------------------------
/// SMPTE timecode representation supporting both drop-frame and
/// non-drop-frame formats.
///
/// Timecodes are expressed as `HH:MM:SS:FF` (non-drop-frame) or
/// `HH:MM:SS;FF` (drop-frame). Drop-frame timecode is used with
/// 29.97 fps and 59.94 fps material to keep timecode aligned with
/// wall-clock time.
///
/// The struct supports round-trip conversion between `TimeInterval`
/// (seconds) and frame-based timecode at any frame rate.
///
/// Phase 14 — SMPTE Timecode Support (Issue #338)
public struct Timecode: Codable, Sendable, CustomStringConvertible {

    // MARK: - Properties

    /// Hours component (0–23).
    public var hours: Int

    /// Minutes component (0–59).
    public var minutes: Int

    /// Seconds component (0–59).
    public var seconds: Int

    /// Frames component (0 to `fps - 1`).
    public var frames: Int

    /// Whether this timecode uses drop-frame notation.
    ///
    /// Drop-frame is applicable to 29.97 fps and 59.94 fps material.
    /// In drop-frame mode, frame numbers 0 and 1 (or 0–3 for 59.94)
    /// are skipped at the start of each minute except every tenth minute.
    public var dropFrame: Bool

    /// The frame rate for this timecode (e.g., 23.976, 24, 25, 29.97, 30, 59.94, 60).
    public var fps: Double

    // MARK: - Computed Properties

    /// Human-readable SMPTE timecode string.
    ///
    /// Uses `:` as the frame separator for non-drop-frame and `;` for
    /// drop-frame notation, per SMPTE ST 12-1.
    ///
    /// Examples:
    /// - Non-drop-frame: `"01:23:45:12"`
    /// - Drop-frame:     `"01:23:45;12"`
    public var description: String {
        let separator = dropFrame ? ";" : ":"
        return String(
            format: "%02d:%02d:%02d%@%02d",
            hours, minutes, seconds, separator, frames
        )
    }

    /// Total number of frames represented by this timecode.
    ///
    /// For drop-frame timecodes, the calculation accounts for the
    /// skipped frame numbers so that the total frame count maps
    /// correctly back to wall-clock time.
    public var totalFrames: Int {
        let nominalFPS = Int(fps.rounded())

        if dropFrame {
            // Drop-frame frame count formula (SMPTE ST 12-1).
            // Frames are "dropped" (skipped) to compensate for the
            // fractional frame rate (29.97 = 30000/1001).
            let dropCount = nominalFPS == 60 ? 4 : 2
            let totalMinutes = hours * 60 + minutes
            let tenMinuteBlocks = totalMinutes / 10
            let remainingMinutes = totalMinutes % 10

            let baseFrames = (hours * 3600 + minutes * 60 + seconds) * nominalFPS + frames
            let droppedFrames = dropCount * (totalMinutes - tenMinuteBlocks)
            _ = remainingMinutes // Silence unused variable warning
            return baseFrames - droppedFrames
        } else {
            return (hours * 3600 + minutes * 60 + seconds) * nominalFPS + frames
        }
    }

    /// The wall-clock time (in seconds) corresponding to this timecode.
    ///
    /// Converts the frame-based timecode to a `TimeInterval` using the
    /// configured frame rate. For drop-frame timecodes this yields a
    /// value very close to real elapsed time.
    public var timestamp: TimeInterval {
        Double(totalFrames) / fps
    }

    // MARK: - Initializers

    /// Creates a timecode from individual components.
    ///
    /// - Parameters:
    ///   - hours: Hours component (0–23).
    ///   - minutes: Minutes component (0–59).
    ///   - seconds: Seconds component (0–59).
    ///   - frames: Frames component (0 to fps-1).
    ///   - dropFrame: Whether to use drop-frame notation.
    ///   - fps: The frame rate.
    public init(
        hours: Int = 0,
        minutes: Int = 0,
        seconds: Int = 0,
        frames: Int = 0,
        dropFrame: Bool = false,
        fps: Double = 24.0
    ) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.dropFrame = dropFrame
        self.fps = fps
    }

    /// Creates a timecode from a wall-clock timestamp.
    ///
    /// Converts a `TimeInterval` (seconds) into SMPTE timecode at the
    /// given frame rate. For drop-frame timecodes the conversion accounts
    /// for skipped frame numbers.
    ///
    /// - Parameters:
    ///   - fromTimestamp: The time in seconds.
    ///   - fps: The frame rate (e.g., 29.97 for NTSC).
    ///   - dropFrame: Whether to produce drop-frame timecode.
    public init(fromTimestamp: TimeInterval, fps: Double, dropFrame: Bool = false) {
        self.fps = fps
        self.dropFrame = dropFrame

        let nominalFPS = Int(fps.rounded())
        var totalFrameCount = Int((fromTimestamp * fps).rounded())

        if dropFrame {
            // Reverse the drop-frame formula to recover HH:MM:SS:FF.
            let dropCount = nominalFPS == 60 ? 4 : 2
            let framesPerMinute = nominalFPS * 60 - dropCount
            let framesPer10Min = framesPerMinute * 10 + dropCount

            let tenMinBlocks = totalFrameCount / framesPer10Min
            let remainder = totalFrameCount % framesPer10Min

            // Adjust for the first minute in a 10-minute block (no drop).
            let additionalMinutes: Int
            if remainder < nominalFPS * 60 {
                additionalMinutes = 0
            } else {
                additionalMinutes = (remainder - nominalFPS * 60) / framesPerMinute + 1
            }

            let totalMinutes = tenMinBlocks * 10 + additionalMinutes
            // Re-add dropped frames for the final H:M:S:F calculation.
            totalFrameCount += dropCount * (totalMinutes - totalMinutes / 10)
        }

        self.frames = totalFrameCount % nominalFPS
        totalFrameCount /= nominalFPS
        self.seconds = totalFrameCount % 60
        totalFrameCount /= 60
        self.minutes = totalFrameCount % 60
        self.hours = totalFrameCount / 60
    }
}

// ---------------------------------------------------------------------------
// MARK: - TimecodeHandler
// ---------------------------------------------------------------------------
/// Utility for building FFmpeg timecode-related arguments and parsing
/// timecode strings.
///
/// Provides static helpers used by the encoding pipeline to:
/// - Preserve existing timecode metadata during re-encoding.
/// - Set a specific starting timecode on the output file.
/// - Parse user-entered timecode strings into `Timecode` values.
///
/// Phase 14 — SMPTE Timecode Support (Issue #338)
public struct TimecodeHandler: Sendable {

    // MARK: - FFmpeg Argument Builders

    /// Builds FFmpeg arguments to preserve the source file's timecode metadata
    /// in the output.
    ///
    /// Adds `-map_metadata 0` and `-movflags use_metadata_tags` so that
    /// any timecode track or metadata present in the source is carried
    /// through to the destination container.
    ///
    /// - Returns: An array of FFmpeg command-line argument strings.
    public static func buildPreserveTimecodeArgs() -> [String] {
        [
            "-map_metadata", "0",
            "-movflags", "use_metadata_tags",
            "-metadata:s:d:0", "handler_name=timecode",
        ]
    }

    /// Builds FFmpeg arguments to set a specific starting timecode on the
    /// output file.
    ///
    /// Applies the timecode via the `-timecode` option and also embeds it
    /// as a global metadata tag for containers that support it (MOV, MP4).
    ///
    /// - Parameter timecode: The SMPTE timecode to embed.
    /// - Returns: An array of FFmpeg command-line argument strings.
    public static func buildSetTimecodeArgs(timecode: Timecode) -> [String] {
        let tcString = timecode.description
        return [
            "-timecode", tcString,
            "-metadata", "timecode=\(tcString)",
        ]
    }

    // MARK: - Parsing

    /// Parses a SMPTE timecode string into a `Timecode` value.
    ///
    /// Accepts both `:` (non-drop-frame) and `;` (drop-frame) as the
    /// frame separator. The string must have exactly four numeric
    /// components: `HH:MM:SS:FF` or `HH:MM:SS;FF`.
    ///
    /// - Parameters:
    ///   - str: The timecode string to parse.
    ///   - fps: The frame rate to assign to the resulting `Timecode`.
    /// - Returns: A `Timecode` value, or `nil` if the string is malformed.
    public static func parseTimecodeString(_ str: String, fps: Double) -> Timecode? {
        // Determine drop-frame from the separator character.
        let isDropFrame = str.contains(";")

        // Normalise separators to `:` for uniform splitting.
        let normalised = str.replacingOccurrences(of: ";", with: ":")
        let components = normalised.split(separator: ":").compactMap { Int($0) }

        guard components.count == 4 else { return nil }

        let hours = components[0]
        let minutes = components[1]
        let seconds = components[2]
        let frames = components[3]

        // Basic range validation.
        let nominalFPS = Int(fps.rounded())
        guard hours >= 0, hours < 24,
              minutes >= 0, minutes < 60,
              seconds >= 0, seconds < 60,
              frames >= 0, frames < nominalFPS else {
            return nil
        }

        return Timecode(
            hours: hours,
            minutes: minutes,
            seconds: seconds,
            frames: frames,
            dropFrame: isDropFrame,
            fps: fps
        )
    }
}
