// ============================================================================
// MeedyaConverter — ConvertMediaIntent (Issue #282)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import AppIntents
import Foundation
import ConverterEngine

// MARK: - ConvertMediaIntent

/// Siri Shortcuts / Shortcuts.app intent for converting a media file.
///
/// Accepts an input file, an encoding profile name, and an optional output format
/// override. Runs the encode using ConverterEngine and returns the path to the
/// converted output file.
///
/// Usage in Shortcuts:
///   - "Convert this video to MP4 with MeedyaConverter"
///   - Drag the "Convert Media File" action into a shortcut workflow
///
/// Phase 10 / Issue #282
@available(macOS 15.0, *)
struct ConvertMediaIntent: AppIntent {

    // MARK: - Metadata

    /// The user-facing title shown in Shortcuts.app.
    nonisolated static let title: LocalizedStringResource = "Convert Media File"

    /// Detailed description shown in the Shortcuts editor.
    nonisolated static let description: IntentDescription = IntentDescription(
        "Convert a media file using a MeedyaConverter encoding profile.",
        categoryName: "Media"
    )

    // MARK: - Parameters

    /// The media file to convert.
    @Parameter(title: "Input File", description: "The media file to convert.")
    var inputFile: IntentFile

    /// The name of the encoding profile to use (e.g., "Web Standard", "4K HDR Master").
    @Parameter(title: "Profile Name", description: "The encoding profile to use for conversion.")
    var profileName: String

    /// Optional output format override (e.g., "mp4", "mkv", "webm").
    /// When nil, the profile's default container format is used.
    @Parameter(
        title: "Output Format",
        description: "Override the output container format (e.g., mp4, mkv). Leave empty to use the profile default.",
        default: nil
    )
    var outputFormat: String?

    // MARK: - Perform

    /// Execute the media conversion.
    ///
    /// - Returns: A result containing the path to the converted file.
    /// - Throws: If the profile is not found, the input file cannot be read,
    ///   or the encoding fails.
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Resolve the input file to a local URL.
        let inputData = inputFile.data

        // Write the intent file data to a temporary location if needed.
        let tempInputURL: URL
        if let fileURL = inputFile.fileURL {
            tempInputURL = fileURL
        } else {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("meedya-intent-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileName = inputFile.filename
            tempInputURL = tempDir.appendingPathComponent(fileName)
            try inputData.write(to: tempInputURL)
        }

        // Look up the encoding profile by name.
        let allProfiles = ConvertMediaIntent.loadAvailableProfiles()
        guard let profile = allProfiles.first(where: {
            $0.name.localizedCaseInsensitiveCompare(profileName) == .orderedSame
        }) else {
            throw ConvertMediaIntentError.profileNotFound(name: profileName)
        }

        // Determine the output URL.
        let outputExtension: String
        if let format = outputFormat, !format.isEmpty {
            outputExtension = format.lowercased().trimmingCharacters(in: .punctuationCharacters)
        } else {
            outputExtension = profile.preferredExtension
        }

        let outputDir = tempInputURL.deletingLastPathComponent()
        let baseName = tempInputURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName)-converted.\(outputExtension)")

        // Build FFmpeg arguments from the profile.
        let builder = profile.toArgumentBuilder(inputURL: tempInputURL, outputURL: outputURL)
        let arguments = builder.build()

        // Locate the FFmpeg binary and execute the encode.
        let bundleManager = FFmpegBundleManager()
        let ffmpegInfo = try bundleManager.locateFFmpeg()
        let controller = FFmpegProcessController(binaryPath: ffmpegInfo.path)

        let progressStream = try controller.startEncoding(arguments: arguments)
        // Consume the progress stream to keep the process alive until completion.
        for await _ in progressStream {}

        // Verify the output file exists.
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ConvertMediaIntentError.encodingFailed(details: "Output file was not created.")
        }

        return .result(value: outputURL.path)
    }

    // MARK: - Profile Loading

    /// Load all available encoding profiles (built-in + user-created).
    ///
    /// This is a simplified loader for the Shortcuts context. The full app
    /// maintains profiles through AppViewModel, but intents run headless.
    private static func loadAvailableProfiles() -> [EncodingProfile] {
        // Return built-in profiles. User-created profiles would need to be
        // loaded from the shared app container in a full implementation.
        return EncodingProfile.builtInProfiles
    }
}

// MARK: - ProbeMediaIntent

/// Siri Shortcuts / Shortcuts.app intent for analysing a media file.
///
/// Accepts a media file and returns a human-readable summary of its
/// streams, codecs, resolution, duration, and other metadata.
///
/// Usage in Shortcuts:
///   - "Analyze media file with MeedyaConverter"
///   - Returns text output with stream details
///
/// Phase 10 / Issue #282
@available(macOS 15.0, *)
struct ProbeMediaIntent: AppIntent {

    // MARK: - Metadata

    /// The user-facing title shown in Shortcuts.app.
    nonisolated static let title: LocalizedStringResource = "Analyze Media File"

    /// Detailed description shown in the Shortcuts editor.
    nonisolated static let description: IntentDescription = IntentDescription(
        "Analyze a media file and return detailed stream information.",
        categoryName: "Media"
    )

    // MARK: - Parameters

    /// The media file to analyse.
    @Parameter(title: "Input File", description: "The media file to analyze.")
    var inputFile: IntentFile

    // MARK: - Perform

    /// Execute the media analysis.
    ///
    /// - Returns: A text summary of the file's media streams and metadata.
    /// - Throws: If the file cannot be read or probing fails.
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Resolve the input file to a local URL.
        guard let fileURL = inputFile.fileURL else {
            throw ConvertMediaIntentError.inputFileUnreadable
        }

        // Probe the file using FFmpegProbe.
        let bundleManager = FFmpegBundleManager()
        let ffprobeInfo = try bundleManager.locateFFprobe()
        let probe = FFmpegProbe(ffprobePath: ffprobeInfo.path)
        let mediaFile = try await probe.analyze(url: fileURL)

        // Build a human-readable summary.
        var summary = "Media File Analysis\n"
        summary += "==================\n\n"
        summary += "File: \(mediaFile.fileName)\n"

        if let size = mediaFile.fileSize {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            summary += "Size: \(formatter.string(fromByteCount: Int64(size)))\n"
        }

        if let duration = mediaFile.duration {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            summary += "Duration: \(minutes)m \(seconds)s\n"
        }

        if let bitrate = mediaFile.overallBitrate {
            summary += "Overall Bitrate: \(bitrate / 1000) kbps\n"
        }

        summary += "\n"

        // Video streams
        let videoStreams = mediaFile.videoStreams
        if !videoStreams.isEmpty {
            summary += "Video Streams (\(videoStreams.count)):\n"
            for stream in videoStreams {
                var line = "  - "
                if let codec = stream.codecName { line += codec.uppercased() }
                if let w = stream.width, let h = stream.height {
                    line += " \(w)x\(h)"
                }
                if let fps = stream.frameRate {
                    line += " @ \(String(format: "%.3f", fps)) fps"
                }
                if !stream.hdrFormats.isEmpty {
                    let hdrNames = stream.hdrFormats.map(\.displayName).joined(separator: ", ")
                    line += " [\(hdrNames)]"
                }
                if let bitrate = stream.bitrate {
                    line += " (\(bitrate / 1000) kbps)"
                }
                summary += line + "\n"
            }
            summary += "\n"
        }

        // Audio streams
        let audioStreams = mediaFile.audioStreams
        if !audioStreams.isEmpty {
            summary += "Audio Streams (\(audioStreams.count)):\n"
            for stream in audioStreams {
                var line = "  - "
                if let codec = stream.codecName { line += codec.uppercased() }
                if let layout = stream.channelLayout {
                    line += " \(layout.displayName)"
                }
                if let rate = stream.sampleRate {
                    line += " \(rate) Hz"
                }
                if let lang = stream.language {
                    line += " [\(lang)]"
                }
                if let bitrate = stream.bitrate {
                    line += " (\(bitrate / 1000) kbps)"
                }
                summary += line + "\n"
            }
            summary += "\n"
        }

        // Subtitle streams
        let subtitleStreams = mediaFile.subtitleStreams
        if !subtitleStreams.isEmpty {
            summary += "Subtitle Streams (\(subtitleStreams.count)):\n"
            for stream in subtitleStreams {
                var line = "  - "
                if let codec = stream.codecName { line += codec }
                if let lang = stream.language { line += " [\(lang)]" }
                if let title = stream.title { line += " \"\(title)\"" }
                summary += line + "\n"
            }
            summary += "\n"
        }

        // Chapters
        if !mediaFile.chapters.isEmpty {
            summary += "Chapters: \(mediaFile.chapters.count)\n"
        }

        // HDR status
        if mediaFile.hasHDR {
            summary += "HDR: Yes"
            if mediaFile.hasDolbyVision { summary += " (Dolby Vision)" }
            if mediaFile.hasHDR10Plus { summary += " (HDR10+)" }
            summary += "\n"
        }

        return .result(value: summary)
    }
}

// MARK: - ConvertMediaIntentError

/// Errors specific to the media conversion and probing intents.
@available(macOS 15.0, *)
enum ConvertMediaIntentError: LocalizedError {

    /// The input file data could not be read.
    case inputFileUnreadable

    /// The named encoding profile was not found.
    case profileNotFound(name: String)

    /// The encoding process failed.
    case encodingFailed(details: String)

    var errorDescription: String? {
        switch self {
        case .inputFileUnreadable:
            return "The input file could not be read."
        case .profileNotFound(let name):
            return "Encoding profile '\(name)' was not found. Check available profile names."
        case .encodingFailed(let details):
            return "Encoding failed: \(details)"
        }
    }
}
