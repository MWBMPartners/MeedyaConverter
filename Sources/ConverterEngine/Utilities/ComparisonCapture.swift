// ============================================================================
// MeedyaConverter — ComparisonCapture (Issue #329)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ComparisonEntry

/// A persisted record of a captured comparison frame, linking a source file
/// and encoding profile to a PNG frame extraction on disk.
///
/// Entries are stored as JSON in the comparison library directory and
/// displayed in the `ComparisonLibraryView` for side-by-side quality review.
public struct ComparisonEntry: Identifiable, Codable, Sendable, Hashable {

    /// Unique identifier for this comparison entry.
    public let id: UUID

    /// The source media file path that was encoded.
    public let sourceFile: String

    /// The timestamp (in seconds) at which the frame was extracted.
    public let timestamp: TimeInterval

    /// The encoding profile name used for this encode.
    public let profileName: String

    /// The video codec used (e.g., "h265", "av1").
    public let codec: String

    /// The CRF value used, if quality-based encoding was selected.
    public let crf: Int?

    /// The target bitrate in bits per second, if bitrate-based encoding was used.
    public let bitrate: Int?

    /// The file system path to the extracted PNG frame.
    public let framePath: String

    /// The encoded output file size in bytes.
    public let fileSize: Int64

    /// The date and time when this comparison frame was captured.
    public let capturedAt: Date

    /// Optional VMAF score if quality analysis was performed.
    public let vmafScore: Double?

    public init(
        id: UUID = UUID(),
        sourceFile: String,
        timestamp: TimeInterval,
        profileName: String,
        codec: String,
        crf: Int? = nil,
        bitrate: Int? = nil,
        framePath: String,
        fileSize: Int64,
        capturedAt: Date = Date(),
        vmafScore: Double? = nil
    ) {
        self.id = id
        self.sourceFile = sourceFile
        self.timestamp = timestamp
        self.profileName = profileName
        self.codec = codec
        self.crf = crf
        self.bitrate = bitrate
        self.framePath = framePath
        self.fileSize = fileSize
        self.capturedAt = capturedAt
        self.vmafScore = vmafScore
    }

    /// The source file name without path components.
    public var sourceFileName: String {
        URL(fileURLWithPath: sourceFile).lastPathComponent
    }

    /// Human-readable formatted file size (e.g., "12.5 MB").
    public var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// A summary label for the encoding settings used.
    public var settingsSummary: String {
        var parts = [codec.uppercased()]
        if let crf {
            parts.append("CRF \(crf)")
        }
        if let bitrate {
            let mbps = Double(bitrate) / 1_000_000.0
            parts.append(String(format: "%.1f Mbps", mbps))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - ComparisonCapture

/// Generates FFmpeg argument lists for extracting comparison frames from
/// encoded media at specific timestamps.
///
/// This utility builds the FFmpeg command-line arguments needed to extract
/// a single PNG frame from a video file. It does not execute FFmpeg itself —
/// the caller is responsible for running the process (typically via
/// `FFmpegProcessController`).
///
/// All methods are pure functions with no side effects.
public struct ComparisonCapture: Sendable {

    // MARK: - Single Frame Capture

    /// Build FFmpeg arguments to extract a single PNG frame from a video file.
    ///
    /// The generated command seeks to the specified timestamp, extracts one
    /// frame, and writes it as a PNG image to `outputPath`. An optional width
    /// parameter scales the output while preserving aspect ratio.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source or encoded video file.
    ///   - outputPath: Path where the extracted PNG frame will be written.
    ///   - timestamp: The time position (in seconds) to extract the frame from.
    ///   - width: Optional output width in pixels. When set, the frame is
    ///     scaled to this width with aspect ratio preserved. When `nil`, the
    ///     frame is extracted at native resolution.
    /// - Returns: An array of FFmpeg command-line arguments (excluding the
    ///   `ffmpeg` binary path itself).
    public static func captureFrame(
        inputPath: String,
        outputPath: String,
        timestamp: TimeInterval,
        width: Int? = nil
    ) -> [String] {
        var args: [String] = []

        // Seek to timestamp before input for fast seeking.
        args.append(contentsOf: ["-ss", formatTimestamp(timestamp)])

        // Input file.
        args.append(contentsOf: ["-i", inputPath])

        // Extract exactly one frame.
        args.append(contentsOf: ["-frames:v", "1"])

        // Apply scaling if a target width is specified.
        if let width {
            // Scale to target width, auto-calculate height preserving aspect ratio.
            // Use -2 to ensure height is divisible by 2.
            args.append(contentsOf: ["-vf", "scale=\(width):-2"])
        }

        // Output as PNG for lossless quality comparison.
        args.append(contentsOf: ["-f", "image2"])
        args.append(contentsOf: ["-c:v", "png"])

        // Overwrite output file if it exists.
        args.append("-y")

        // Output path.
        args.append(outputPath)

        return args
    }

    // MARK: - Multi-Profile Capture

    /// Build FFmpeg argument sets for extracting the same frame from multiple
    /// encoding profiles, enabling side-by-side quality comparison.
    ///
    /// For each profile, generates the FFmpeg arguments and a deterministic
    /// output path within the specified output directory. The caller should
    /// first encode the source with each profile, then use the returned
    /// arguments to extract frames from each encoded output.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the original source media file.
    ///   - timestamp: The time position (in seconds) to extract frames from.
    ///   - profiles: The encoding profiles to compare.
    ///   - outputDir: Directory where extracted PNG frames will be written.
    /// - Returns: An array of tuples, each containing the profile, FFmpeg
    ///   arguments, and the output PNG path for that profile's frame.
    public static func captureFromMultipleProfiles(
        inputPath: String,
        timestamp: TimeInterval,
        profiles: [EncodingProfile],
        outputDir: String
    ) -> [(profile: EncodingProfile, arguments: [String], outputPath: String)] {
        let sourceFileName = URL(fileURLWithPath: inputPath)
            .deletingPathExtension()
            .lastPathComponent

        return profiles.map { profile in
            // Build a deterministic output filename.
            let sanitisedProfileName = profile.name
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "/", with: "-")
            let outputFileName = "\(sourceFileName)_\(sanitisedProfileName)_\(Int(timestamp))s.png"
            let outputPath = (outputDir as NSString).appendingPathComponent(outputFileName)

            let arguments = captureFrame(
                inputPath: inputPath,
                outputPath: outputPath,
                timestamp: timestamp
            )

            return (profile: profile, arguments: arguments, outputPath: outputPath)
        }
    }

    // MARK: - VMAF Comparison Arguments

    /// Build FFmpeg arguments for computing VMAF quality score between a
    /// reference (source) and a distorted (encoded) video.
    ///
    /// - Parameters:
    ///   - referencePath: Path to the original source video.
    ///   - distortedPath: Path to the encoded video to evaluate.
    ///   - modelPath: Optional path to a custom VMAF model file. When `nil`,
    ///     FFmpeg's default bundled model is used.
    /// - Returns: FFmpeg arguments for VMAF calculation (output to stderr).
    public static func vmafArguments(
        referencePath: String,
        distortedPath: String,
        modelPath: String? = nil
    ) -> [String] {
        var args: [String] = []

        // Two inputs: distorted first, reference second (FFmpeg libvmaf convention).
        args.append(contentsOf: ["-i", distortedPath])
        args.append(contentsOf: ["-i", referencePath])

        // Build the VMAF filter.
        var vmafFilter = "libvmaf"
        if let modelPath {
            vmafFilter += "=model=path=\(modelPath)"
        }

        args.append(contentsOf: [
            "-lavfi", vmafFilter,
            "-f", "null", "-",
        ])

        return args
    }

    // MARK: - Helpers

    /// Format a timestamp in seconds to FFmpeg's `HH:MM:SS.mmm` format.
    private static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%02d:%06.3f", hours, minutes, secs)
    }
}
