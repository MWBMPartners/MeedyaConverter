// ============================================================================
// MeedyaConverter — EncodingReport
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - StreamReport

/// Summary of a single stream in an encoding report.
public struct StreamReport: Codable, Sendable {
    /// Stream type ("video", "audio", "subtitle").
    public var type: String

    /// Codec used.
    public var codec: String

    /// Bitrate in bits per second (nil if unavailable).
    public var bitrate: Int?

    /// Resolution string for video (e.g., "1920x1080").
    public var resolution: String?

    /// Frame rate for video.
    public var frameRate: Double?

    /// Channel count for audio.
    public var channels: Int?

    /// Sample rate for audio.
    public var sampleRate: Int?

    /// Language tag.
    public var language: String?

    public init(
        type: String,
        codec: String,
        bitrate: Int? = nil,
        resolution: String? = nil,
        frameRate: Double? = nil,
        channels: Int? = nil,
        sampleRate: Int? = nil,
        language: String? = nil
    ) {
        self.type = type
        self.codec = codec
        self.bitrate = bitrate
        self.resolution = resolution
        self.frameRate = frameRate
        self.channels = channels
        self.sampleRate = sampleRate
        self.language = language
    }
}

// MARK: - EncodingPerformance

/// Encoding performance statistics.
public struct EncodingPerformance: Codable, Sendable {
    /// Total wall-clock encoding time in seconds.
    public var totalTime: TimeInterval

    /// Encoding speed (e.g., 2.5 means 2.5x realtime).
    public var encodingSpeed: Double?

    /// Number of encoding passes performed.
    public var passCount: Int

    /// Average CPU usage percentage (0–100).
    public var averageCPU: Double?

    /// Peak memory usage in bytes.
    public var peakMemory: Int?

    public init(
        totalTime: TimeInterval,
        encodingSpeed: Double? = nil,
        passCount: Int = 1,
        averageCPU: Double? = nil,
        peakMemory: Int? = nil
    ) {
        self.totalTime = totalTime
        self.encodingSpeed = encodingSpeed
        self.passCount = passCount
        self.averageCPU = averageCPU
        self.peakMemory = peakMemory
    }

    /// Human-readable encoding time.
    public var formattedTime: String {
        let hours = Int(totalTime) / 3600
        let minutes = (Int(totalTime) % 3600) / 60
        let seconds = Int(totalTime) % 60
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        }
        return String(format: "%ds", seconds)
    }
}

// MARK: - EncodingReport

/// Comprehensive post-encoding report summarising the encoding job.
///
/// Contains input/output file summaries, per-stream details, encoding
/// performance, compression statistics, and optionally quality metrics.
///
/// Phase 7.3
public struct EncodingReport: Codable, Sendable {

    // MARK: Input Summary

    /// Input file path.
    public var inputPath: String

    /// Input file size in bytes.
    public var inputFileSize: Int64

    /// Input duration in seconds.
    public var inputDuration: TimeInterval

    /// Input container format.
    public var inputFormat: String?

    /// Input stream summaries.
    public var inputStreams: [StreamReport]

    // MARK: Output Summary

    /// Output file path.
    public var outputPath: String

    /// Output file size in bytes.
    public var outputFileSize: Int64

    /// Output container format.
    public var outputFormat: String?

    /// Output stream summaries.
    public var outputStreams: [StreamReport]

    // MARK: Statistics

    /// Compression ratio (input size / output size).
    public var compressionRatio: Double {
        guard outputFileSize > 0 else { return 0 }
        return Double(inputFileSize) / Double(outputFileSize)
    }

    /// File size reduction percentage (negative means output is larger).
    public var sizeReductionPercent: Double {
        guard inputFileSize > 0 else { return 0 }
        return (1.0 - Double(outputFileSize) / Double(inputFileSize)) * 100
    }

    /// Encoding performance statistics.
    public var performance: EncodingPerformance?

    /// Encoding profile name used.
    public var profileName: String?

    /// FFmpeg command used (for reproducibility).
    public var ffmpegCommand: String?

    /// Quality metric scores (if quality analysis was run).
    public var qualityScores: [QualityScore]?

    /// Timestamp when the encoding completed.
    public var completedAt: Date

    /// Any warnings generated during encoding.
    public var warnings: [String]

    public init(
        inputPath: String,
        inputFileSize: Int64,
        inputDuration: TimeInterval,
        inputFormat: String? = nil,
        inputStreams: [StreamReport] = [],
        outputPath: String,
        outputFileSize: Int64,
        outputFormat: String? = nil,
        outputStreams: [StreamReport] = [],
        performance: EncodingPerformance? = nil,
        profileName: String? = nil,
        ffmpegCommand: String? = nil,
        qualityScores: [QualityScore]? = nil,
        completedAt: Date = Date(),
        warnings: [String] = []
    ) {
        self.inputPath = inputPath
        self.inputFileSize = inputFileSize
        self.inputDuration = inputDuration
        self.inputFormat = inputFormat
        self.inputStreams = inputStreams
        self.outputPath = outputPath
        self.outputFileSize = outputFileSize
        self.outputFormat = outputFormat
        self.outputStreams = outputStreams
        self.performance = performance
        self.profileName = profileName
        self.ffmpegCommand = ffmpegCommand
        self.qualityScores = qualityScores
        self.completedAt = completedAt
        self.warnings = warnings
    }

    // MARK: - Output Formats

    /// Generate a JSON representation of the report.
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Generate a plain-text summary.
    public func toPlainText() -> String {
        var lines: [String] = []

        lines.append("═══════════════════════════════════════════════════")
        lines.append("  ENCODING REPORT")
        lines.append("═══════════════════════════════════════════════════")
        lines.append("")

        // Input
        lines.append("INPUT:")
        lines.append("  File: \(inputPath)")
        lines.append("  Size: \(formattedSize(inputFileSize))")
        lines.append("  Duration: \(formattedDuration(inputDuration))")
        if let fmt = inputFormat { lines.append("  Format: \(fmt)") }
        for stream in inputStreams {
            lines.append("  Stream: \(stream.type) — \(stream.codec)\(streamDetail(stream))")
        }

        lines.append("")

        // Output
        lines.append("OUTPUT:")
        lines.append("  File: \(outputPath)")
        lines.append("  Size: \(formattedSize(outputFileSize))")
        if let fmt = outputFormat { lines.append("  Format: \(fmt)") }
        for stream in outputStreams {
            lines.append("  Stream: \(stream.type) — \(stream.codec)\(streamDetail(stream))")
        }

        lines.append("")

        // Compression
        lines.append("COMPRESSION:")
        lines.append("  Ratio: \(String(format: "%.2f", compressionRatio))x")
        lines.append("  Size change: \(String(format: "%+.1f", -sizeReductionPercent))%")

        // Performance
        if let perf = performance {
            lines.append("")
            lines.append("PERFORMANCE:")
            lines.append("  Time: \(perf.formattedTime)")
            if let speed = perf.encodingSpeed {
                lines.append("  Speed: \(String(format: "%.2f", speed))x realtime")
            }
            lines.append("  Passes: \(perf.passCount)")
        }

        // Quality
        if let scores = qualityScores, !scores.isEmpty {
            lines.append("")
            lines.append("QUALITY:")
            for score in scores {
                lines.append("  \(score.summary)")
            }
        }

        // Warnings
        if !warnings.isEmpty {
            lines.append("")
            lines.append("WARNINGS:")
            for w in warnings {
                lines.append("  ⚠ \(w)")
            }
        }

        if let profile = profileName {
            lines.append("")
            lines.append("Profile: \(profile)")
        }

        lines.append("")
        lines.append("═══════════════════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    /// Generate a Markdown report.
    public func toMarkdown() -> String {
        var md: [String] = []

        md.append("# Encoding Report")
        md.append("")

        md.append("## Input")
        md.append("| Property | Value |")
        md.append("|----------|-------|")
        md.append("| File | `\(inputPath)` |")
        md.append("| Size | \(formattedSize(inputFileSize)) |")
        md.append("| Duration | \(formattedDuration(inputDuration)) |")
        if let fmt = inputFormat { md.append("| Format | \(fmt) |") }
        md.append("")

        md.append("## Output")
        md.append("| Property | Value |")
        md.append("|----------|-------|")
        md.append("| File | `\(outputPath)` |")
        md.append("| Size | \(formattedSize(outputFileSize)) |")
        if let fmt = outputFormat { md.append("| Format | \(fmt) |") }
        md.append("| Compression | \(String(format: "%.2f", compressionRatio))x |")
        md.append("| Size change | \(String(format: "%+.1f", -sizeReductionPercent))% |")
        md.append("")

        if let perf = performance {
            md.append("## Performance")
            md.append("| Metric | Value |")
            md.append("|--------|-------|")
            md.append("| Time | \(perf.formattedTime) |")
            if let speed = perf.encodingSpeed {
                md.append("| Speed | \(String(format: "%.2f", speed))x realtime |")
            }
            md.append("| Passes | \(perf.passCount) |")
            md.append("")
        }

        return md.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func formattedSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f %@", size, units[unitIndex])
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func streamDetail(_ stream: StreamReport) -> String {
        var parts: [String] = []
        if let res = stream.resolution { parts.append(res) }
        if let br = stream.bitrate { parts.append("\(br / 1000)k") }
        if let ch = stream.channels { parts.append("\(ch)ch") }
        if let lang = stream.language { parts.append(lang) }
        return parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
    }
}
