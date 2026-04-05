// ============================================================================
// MeedyaConverter — FilenameTemplate (Issue #272)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FilenameTemplate

/// A configurable output filename template with variable substitution.
///
/// Supports placeholders like `{title}`, `{resolution}`, `{codec}`, `{date}`,
/// and custom date formats via `{date:yyyyMMdd}`. Automatically handles
/// filename collision by appending `_1`, `_2`, etc.
public struct FilenameTemplate: Codable, Sendable, Hashable {

    // MARK: - Properties

    /// The template string with `{variable}` placeholders.
    public var template: String

    // MARK: - Defaults

    /// The default filename template: source title with "_converted" suffix.
    public static let defaultTemplate = FilenameTemplate(template: "{title}_converted")

    // MARK: - Initialiser

    public init(template: String) {
        self.template = template
    }

    /// Backward-compatible initialiser accepting a `pattern` string.
    ///
    /// Maps legacy `{name}` and `{ext}` placeholders to the new `{title}` variable.
    /// - Parameter pattern: The legacy template pattern string.
    public init(pattern: String) {
        // Map legacy placeholders to new ones
        self.template = pattern
            .replacingOccurrences(of: "{name}", with: "{title}")
            .replacingOccurrences(of: "{ext}", with: "{container}")
    }

    /// The template pattern string (backward-compatible alias for `template`).
    public var pattern: String { template }

    // MARK: - Available Variables

    /// Returns the list of supported template variables with descriptions.
    ///
    /// - Returns: An array of `(name, description)` tuples for UI display.
    public static func availableVariables() -> [(name: String, description: String)] {
        return [
            ("{title}", "Source filename without extension"),
            ("{resolution}", "Output resolution (e.g., 1920x1080)"),
            ("{codec}", "Video codec name (e.g., H.265)"),
            ("{container}", "Output container format (e.g., mkv)"),
            ("{profile}", "Encoding profile name"),
            ("{date}", "Current date (yyyy-MM-dd)"),
            ("{date:FORMAT}", "Current date with custom format (e.g., {date:yyyyMMdd})"),
            ("{width}", "Output video width in pixels"),
            ("{height}", "Output video height in pixels"),
            ("{fps}", "Output frame rate"),
            ("{channels}", "Audio channel count"),
        ]
    }

    // MARK: - Resolution

    /// Resolve the template into a concrete filename string.
    ///
    /// Replaces all `{variable}` placeholders with values derived from
    /// the source file, encoding profile, and current date.
    ///
    /// - Parameters:
    ///   - sourceFile: The source media file for metadata extraction.
    ///   - profile: The encoding profile for codec/container info.
    ///   - date: The date to use for `{date}` variables (defaults to now).
    /// - Returns: A sanitised filename string (without extension).
    public func resolve(
        sourceFile: MediaFile,
        profile: EncodingProfile,
        date: Date = Date()
    ) -> String {
        var result = template

        // {title} — source filename without extension
        let title = sourceFile.fileURL.deletingPathExtension().lastPathComponent
        result = result.replacingOccurrences(of: "{title}", with: title)

        // {resolution} — from source primary video stream or profile output dimensions
        let width = profile.outputWidth ?? sourceFile.primaryVideoStream?.width ?? 0
        let height = profile.outputHeight ?? sourceFile.primaryVideoStream?.height ?? 0
        let resolution = width > 0 && height > 0 ? "\(width)x\(height)" : "unknown"
        result = result.replacingOccurrences(of: "{resolution}", with: resolution)

        // {codec} — video codec display name
        let codecName: String
        if profile.videoPassthrough {
            codecName = sourceFile.primaryVideoStream?.videoCodec?.displayName
                ?? sourceFile.primaryVideoStream?.codecName
                ?? "copy"
        } else {
            codecName = profile.videoCodec?.displayName ?? "none"
        }
        result = result.replacingOccurrences(of: "{codec}", with: codecName)

        // {container} — output container format raw value
        result = result.replacingOccurrences(of: "{container}", with: profile.containerFormat.rawValue)

        // {profile} — encoding profile name
        result = result.replacingOccurrences(of: "{profile}", with: profile.name)

        // {width} / {height}
        result = result.replacingOccurrences(of: "{width}", with: "\(width)")
        result = result.replacingOccurrences(of: "{height}", with: "\(height)")

        // {fps} — frame rate
        let fps = profile.outputFrameRate ?? sourceFile.primaryVideoStream?.frameRate ?? 0
        let fpsString = fps.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(fps))"
            : String(format: "%.2f", fps)
        result = result.replacingOccurrences(of: "{fps}", with: fpsString)

        // {channels} — audio channel count
        let channels = profile.audioChannels
            ?? sourceFile.primaryAudioStream?.channelLayout?.channelCount
            ?? 2
        result = result.replacingOccurrences(of: "{channels}", with: "\(channels)")

        // {date:FORMAT} — custom date format (must be processed before plain {date})
        let customDatePattern = /\{date:([^}]+)\}/
        while let match = result.firstMatch(of: customDatePattern) {
            let format = String(match.1)
            let formatter = DateFormatter()
            formatter.dateFormat = format
            let dateString = formatter.string(from: date)
            result = result.replacingCharacters(in: match.range, with: dateString)
        }

        // {date} — default ISO date format
        let defaultFormatter = DateFormatter()
        defaultFormatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{date}", with: defaultFormatter.string(from: date))

        // Sanitise: remove characters not allowed in filenames
        return sanitiseFilename(result)
    }

    // MARK: - Collision Handling

    /// Resolve the template and handle filename collisions by appending a numeric suffix.
    ///
    /// Checks if the resolved filename already exists in the output directory
    /// and appends `_1`, `_2`, etc. until a unique name is found.
    ///
    /// - Parameters:
    ///   - sourceFile: The source media file.
    ///   - profile: The encoding profile.
    ///   - outputDirectory: The output directory to check for collisions.
    ///   - fileExtension: The file extension to append.
    ///   - date: The date to use for template resolution.
    /// - Returns: A full output URL with unique filename.
    public func resolveWithCollisionHandling(
        sourceFile: MediaFile,
        profile: EncodingProfile,
        outputDirectory: URL,
        fileExtension: String,
        date: Date = Date()
    ) -> URL {
        let baseName = resolve(sourceFile: sourceFile, profile: profile, date: date)
        var candidate = outputDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension(fileExtension)

        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = outputDirectory
                .appendingPathComponent("\(baseName)_\(counter)")
                .appendingPathExtension(fileExtension)
            counter += 1
        }

        return candidate
    }

    // MARK: - Helpers

    /// Remove characters that are invalid in macOS/APFS filenames.
    private func sanitiseFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        return name.unicodeScalars
            .filter { !invalidCharacters.contains($0) }
            .reduce(into: "") { $0.append(Character($1)) }
    }

    // MARK: - Backward Compatibility

    /// Resolve the template for a given input file URL only (legacy API).
    ///
    /// Replaces `{title}`/`{name}` with the base filename (no extension),
    /// `{container}`/`{ext}` with the original extension, and `{date}` with today's date.
    ///
    /// - Parameter inputURL: The source file URL to derive values from.
    /// - Returns: The resolved filename string.
    public func resolve(for inputURL: URL) -> String {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())

        return sanitiseFilename(
            template
                .replacingOccurrences(of: "{title}", with: baseName)
                .replacingOccurrences(of: "{name}", with: baseName)
                .replacingOccurrences(of: "{container}", with: ext)
                .replacingOccurrences(of: "{ext}", with: ext)
                .replacingOccurrences(of: "{date}", with: dateString)
        )
    }
}
