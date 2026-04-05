// ============================================================================
// MeedyaConverter — PreviewGenerator (Issue #270)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - PreviewGenerator

/// Generates short preview clips for A/B quality comparison before full encoding.
///
/// Builds FFmpeg arguments identical to a full encode but with `-ss` (start time)
/// and `-t` (duration) flags so only a short segment (typically 5–10 seconds) is
/// encoded. This lets users evaluate quality settings quickly before committing
/// to a potentially long encode.
///
/// Usage:
/// ```swift
/// let args = PreviewGenerator.buildPreviewArguments(
///     inputPath: "/path/to/source.mkv",
///     outputPath: PreviewGenerator.previewOutputPath(for: sourceURL).path,
///     profile: selectedProfile,
///     startTime: 30.0,
///     duration: 8.0
/// )
/// // Execute args with FFmpegProcessController...
/// ```
///
/// Phase 7 / Issue #270
public struct PreviewGenerator: Sendable {

    // MARK: - Constants

    /// Default preview clip duration in seconds.
    public static let defaultDuration: TimeInterval = 8.0

    /// Minimum preview clip duration in seconds.
    public static let minimumDuration: TimeInterval = 2.0

    /// Maximum preview clip duration in seconds.
    public static let maximumDuration: TimeInterval = 30.0

    /// Subdirectory name within the system temp directory for preview files.
    private static let previewSubdirectory = "meedya-preview"

    // MARK: - Argument Building

    /// Build FFmpeg arguments for encoding a short preview segment.
    ///
    /// The resulting arguments mirror what a full encode would produce from the
    /// given `EncodingProfile`, but with `-ss` and `-t` flags prepended so only
    /// a short segment is encoded. This ensures the preview accurately reflects
    /// the quality the user will get from a full encode.
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source media file.
    ///   - outputPath: Absolute path where the preview clip should be written.
    ///   - profile: The encoding profile whose settings should be applied.
    ///   - startTime: Start time (in seconds) within the source to begin the preview.
    ///   - duration: Duration (in seconds) of the preview segment.
    /// - Returns: An array of FFmpeg CLI arguments (not including the binary path).
    public static func buildPreviewArguments(
        inputPath: String,
        outputPath: String,
        profile: EncodingProfile,
        startTime: TimeInterval,
        duration: TimeInterval
    ) -> [String] {
        // Clamp duration to allowed range.
        let clampedDuration = min(max(duration, minimumDuration), maximumDuration)

        // Use the profile's own argument builder to get a faithful representation
        // of the full encode, then inject seek/duration flags.
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)
        let builder = profile.toArgumentBuilder(inputURL: inputURL, outputURL: outputURL)

        // Inject seek-before-input and duration flags into the extra arguments.
        // FFmpeg processes -ss before -i for fast input seeking and -t limits output duration.
        var args: [String] = []

        // Global options
        args.append("-y")          // Overwrite output without asking.
        args.append("-nostdin")    // Suppress interactive prompts.

        // Seek to start time (before input for fast seek).
        args.append("-ss")
        args.append(formatTimestamp(startTime))

        // Input file
        args.append("-i")
        args.append(inputPath)

        // Limit output duration.
        args.append("-t")
        args.append(formatTimestamp(clampedDuration))

        // Strip the standard global / input arguments from the builder output,
        // then append only the codec/filter/output portion.
        let builderArgs = builder.build()
        let filteredArgs = extractCodecAndOutputArguments(from: builderArgs, inputPath: inputPath)
        args.append(contentsOf: filteredArgs)

        // Ensure the output path is the last argument.
        // Remove any trailing output path from filtered args (the builder may have appended it)
        // and append the explicit output path.
        if let lastArg = args.last, lastArg == outputURL.path {
            // Already correct; nothing to do.
        } else if !args.contains(outputPath) {
            args.append(outputPath)
        }

        return args
    }

    // MARK: - Output Path

    /// Compute a temporary output path for a preview file based on the source URL.
    ///
    /// The preview file is placed in a dedicated subdirectory of the system temp
    /// directory so it does not pollute the user's filesystem. The filename includes
    /// a UUID to avoid collisions when generating multiple previews.
    ///
    /// - Parameter inputURL: The source media file URL.
    /// - Returns: A URL in the temp directory suitable for the preview clip output.
    public static func previewOutputPath(for inputURL: URL) -> URL {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(previewSubdirectory, isDirectory: true)

        // Ensure the preview directory exists.
        try? FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)

        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let uniqueID = UUID().uuidString.prefix(8)
        let fileName = "\(baseName)-preview-\(uniqueID).mp4"

        return tempBase.appendingPathComponent(fileName)
    }

    // MARK: - Cleanup

    /// Remove a preview file from disk.
    ///
    /// Safe to call even if the file does not exist (no error is thrown).
    ///
    /// - Parameter url: The URL of the preview file to delete.
    public static func cleanupPreview(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Remove all preview files from the preview temp directory.
    ///
    /// Useful during app termination or when the user navigates away from
    /// the preview interface.
    public static func cleanupAllPreviews() {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(previewSubdirectory, isDirectory: true)
        try? FileManager.default.removeItem(at: tempBase)
    }

    // MARK: - Private Helpers

    /// Format a `TimeInterval` as an FFmpeg-compatible timestamp string (HH:MM:SS.mmm).
    ///
    /// - Parameter time: The time interval in seconds.
    /// - Returns: A formatted timestamp string.
    private static func formatTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1.0)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    /// Extract codec, filter, and output arguments from a full builder argument list.
    ///
    /// Strips the leading global flags (`-y`, `-nostdin`), input arguments (`-i`),
    /// and any seek/duration flags that the caller will provide separately.
    ///
    /// - Parameters:
    ///   - args: The full argument array from `FFmpegArgumentBuilder.build()`.
    ///   - inputPath: The input file path to filter out.
    /// - Returns: A filtered argument array containing only codec/filter/output arguments.
    private static func extractCodecAndOutputArguments(
        from args: [String],
        inputPath: String
    ) -> [String] {
        var filtered: [String] = []
        var skipNext = false
        let globalFlags: Set<String> = ["-y", "-nostdin"]
        let pairedFlags: Set<String> = ["-i", "-ss", "-t", "-to"]

        for (_, arg) in args.enumerated() {
            if skipNext {
                skipNext = false
                continue
            }

            if globalFlags.contains(arg) {
                continue
            }

            if pairedFlags.contains(arg) {
                skipNext = true
                continue
            }

            // Skip the input path if it appears bare (without a flag).
            if arg == inputPath {
                continue
            }

            filtered.append(arg)
        }

        return filtered
    }
}
