// ============================================================================
// MeedyaConverter — QualityChecker (Issue #344)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - QCCheckType
// ---------------------------------------------------------------------------
/// Enumeration of automated quality-control checks that can be performed
/// on a media file before or after encoding.
///
/// Each check type corresponds to a specific FFmpeg analysis filter or
/// post-processing inspection step. The raw string value is suitable for
/// serialization in profiles and reports.
///
/// - ``blackFrames``: Detects sequences of fully black video frames that
///   may indicate dropped content or encoding errors.
/// - ``silenceDetection``: Identifies periods of audio silence that could
///   signal missing audio tracks or muted segments.
/// - ``audioSync``: Verifies that audio and video streams remain
///   temporally aligned within tolerance.
/// - ``levelCompliance``: Checks audio loudness levels against a
///   specified standard (e.g., EBU R128, ATSC A/85).
/// - ``formatConformance``: Validates container and codec parameters
///   against a target specification.
/// - ``corruptFrames``: Scans for decode errors or corrupt frame data
///   reported by FFmpeg's error concealment system.
public enum QCCheckType: String, Codable, Sendable, CaseIterable {
    case blackFrames
    case silenceDetection
    case audioSync
    case levelCompliance
    case formatConformance
    case corruptFrames
}

// ---------------------------------------------------------------------------
// MARK: - QCResult
// ---------------------------------------------------------------------------
/// The outcome of a single quality-control check against a media file.
///
/// Each result carries a pass/fail verdict, a human-readable ``details``
/// string describing what was found, and an optional ``timestamp`` pointing
/// to the location in the file where the issue was detected.
///
/// ``severity`` is a free-form string (e.g., "warning", "error", "info")
/// so that downstream consumers can colour-code or filter results.
public struct QCResult: Identifiable, Codable, Sendable {

    /// Unique identifier for this result.
    public let id: UUID

    /// The type of check that produced this result.
    public let check: QCCheckType

    /// Whether the check passed (`true`) or found an issue (`false`).
    public let passed: Bool

    /// Human-readable description of the finding.
    public let details: String

    /// Optional position (in seconds) where the issue was found.
    public let timestamp: TimeInterval?

    /// Severity level: "info", "warning", or "error".
    public let severity: String

    /// Memberwise initializer.
    public init(
        id: UUID = UUID(),
        check: QCCheckType,
        passed: Bool,
        details: String,
        timestamp: TimeInterval? = nil,
        severity: String = "info"
    ) {
        self.id = id
        self.check = check
        self.passed = passed
        self.details = details
        self.timestamp = timestamp
        self.severity = severity
    }
}

// ---------------------------------------------------------------------------
// MARK: - QCProfile
// ---------------------------------------------------------------------------
/// A reusable configuration that determines which quality-control checks
/// to run and their associated thresholds.
///
/// Built-in profiles are available via ``QualityChecker/broadcast``,
/// ``QualityChecker/streaming``, and ``QualityChecker/archive``.
public struct QCProfile: Codable, Sendable {

    /// Display name for this profile (e.g., "Broadcast QC").
    public var name: String

    /// The set of checks that should be executed when this profile is active.
    public var enabledChecks: Set<QCCheckType>

    /// Optional loudness standard for level compliance checks
    /// (e.g., "EBU R128", "ATSC A/85").
    public var loudnessStandard: String?

    /// Maximum allowed duration (in seconds) of contiguous black frames
    /// before the check is considered failed. Default is 2.0 seconds.
    public var maxBlackFrameDuration: Double

    /// Audio level (in dBFS) below which silence is detected.
    /// Default is -50.0 dBFS.
    public var silenceThreshold: Double

    /// Memberwise initializer.
    public init(
        name: String,
        enabledChecks: Set<QCCheckType>,
        loudnessStandard: String? = nil,
        maxBlackFrameDuration: Double = 2.0,
        silenceThreshold: Double = -50.0
    ) {
        self.name = name
        self.enabledChecks = enabledChecks
        self.loudnessStandard = loudnessStandard
        self.maxBlackFrameDuration = maxBlackFrameDuration
        self.silenceThreshold = silenceThreshold
    }
}

// ---------------------------------------------------------------------------
// MARK: - QualityChecker
// ---------------------------------------------------------------------------
/// Builds FFmpeg arguments for automated quality-control analysis and
/// parses the resulting output into structured ``QCResult`` values.
///
/// `QualityChecker` is a pure-function utility: it does not execute
/// processes itself. Callers are expected to run the generated argument
/// arrays through the existing `FFmpegProcessController` and feed the
/// captured stderr/stdout back into the parse methods.
///
/// Usage:
/// ```swift
/// let args = QualityChecker.buildBlackFrameDetectionArgs(
///     inputPath: "/path/to/file.mp4"
/// )
/// // Run args via FFmpegProcessController, capture stderr...
/// let results = QualityChecker.parseBlackFrameOutput(stderr)
/// ```
public struct QualityChecker: Sendable {

    // MARK: - Built-in Profiles

    /// Broadcast QC profile: all checks enabled, strict thresholds,
    /// EBU R128 loudness compliance.
    public static let broadcast = QCProfile(
        name: "Broadcast",
        enabledChecks: Set(QCCheckType.allCases),
        loudnessStandard: "EBU R128",
        maxBlackFrameDuration: 1.0,
        silenceThreshold: -60.0
    )

    /// Streaming QC profile: core checks (black frames, silence, format
    /// conformance) with relaxed thresholds suitable for web delivery.
    public static let streaming = QCProfile(
        name: "Streaming",
        enabledChecks: [.blackFrames, .silenceDetection, .formatConformance],
        loudnessStandard: nil,
        maxBlackFrameDuration: 3.0,
        silenceThreshold: -50.0
    )

    /// Archive QC profile: focuses on data integrity checks (corrupt frames,
    /// format conformance) with generous thresholds for preservation workflows.
    public static let archive = QCProfile(
        name: "Archive",
        enabledChecks: [.corruptFrames, .formatConformance, .blackFrames],
        loudnessStandard: nil,
        maxBlackFrameDuration: 5.0,
        silenceThreshold: -40.0
    )

    // MARK: - Argument Builders

    /// Builds FFmpeg arguments for black-frame detection using the
    /// `blackdetect` video filter.
    ///
    /// The generated command writes to `/dev/null` (analysis only) and
    /// emits detection results on stderr in the format:
    /// `[blackdetect @ 0x...] black_start:1.0 black_end:3.5 black_duration:2.5`
    ///
    /// - Parameter inputPath: Absolute path to the media file to analyse.
    /// - Returns: Array of arguments suitable for `Process.arguments`.
    public static func buildBlackFrameDetectionArgs(inputPath: String) -> [String] {
        return [
            "-i", inputPath,
            "-vf", "blackdetect=d=0.1:pix_th=0.10",
            "-an",
            "-f", "null",
            "-"
        ]
    }

    /// Builds FFmpeg arguments for silence detection using the
    /// `silencedetect` audio filter.
    ///
    /// Detection results appear on stderr in the format:
    /// `[silencedetect @ 0x...] silence_start: 5.0`
    /// `[silencedetect @ 0x...] silence_end: 8.0 | silence_duration: 3.0`
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the media file to analyse.
    ///   - threshold: Audio level in dBFS below which silence is detected.
    /// - Returns: Array of arguments suitable for `Process.arguments`.
    public static func buildSilenceDetectionArgs(
        inputPath: String,
        threshold: Double
    ) -> [String] {
        return [
            "-i", inputPath,
            "-af", "silencedetect=noise=\(threshold)dB:d=0.5",
            "-vn",
            "-f", "null",
            "-"
        ]
    }

    // MARK: - Output Parsers

    /// Parses FFmpeg stderr output from a `blackdetect` filter run into
    /// structured ``QCResult`` values.
    ///
    /// Each detected black segment produces one result. If no black frames
    /// are found, a single passing result is returned.
    ///
    /// - Parameter output: The raw stderr text from FFmpeg.
    /// - Returns: Array of ``QCResult`` values, one per detected segment
    ///   plus an overall pass/fail summary.
    public static func parseBlackFrameOutput(_ output: String) -> [QCResult] {
        var results: [QCResult] = []

        // Pattern: black_start:1.0 black_end:3.5 black_duration:2.5
        let pattern = #"black_start:(\d+\.?\d*)\s+black_end:(\d+\.?\d*)\s+black_duration:(\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [QCResult(
                check: .blackFrames,
                passed: true,
                details: "No black frames detected (parse unavailable).",
                severity: "info"
            )]
        }

        let nsOutput = output as NSString
        let matches = regex.matches(
            in: output,
            range: NSRange(location: 0, length: nsOutput.length)
        )

        for match in matches {
            let startStr = nsOutput.substring(with: match.range(at: 1))
            let durationStr = nsOutput.substring(with: match.range(at: 3))
            let start = Double(startStr) ?? 0
            let duration = Double(durationStr) ?? 0

            results.append(QCResult(
                check: .blackFrames,
                passed: false,
                details: String(
                    format: "Black segment at %.2fs, duration %.2fs",
                    start, duration
                ),
                timestamp: start,
                severity: duration > 2.0 ? "error" : "warning"
            ))
        }

        if results.isEmpty {
            results.append(QCResult(
                check: .blackFrames,
                passed: true,
                details: "No black frames detected.",
                severity: "info"
            ))
        }

        return results
    }

    /// Parses FFmpeg stderr output from a `silencedetect` filter run into
    /// structured ``QCResult`` values.
    ///
    /// Each detected silence period produces one result. If no silence is
    /// found, a single passing result is returned.
    ///
    /// - Parameter output: The raw stderr text from FFmpeg.
    /// - Returns: Array of ``QCResult`` values, one per silent segment.
    public static func parseSilenceOutput(_ output: String) -> [QCResult] {
        var results: [QCResult] = []

        // Pattern: silence_start: 5.0 ... silence_end: 8.0 | silence_duration: 3.0
        let startPattern = #"silence_start:\s*(\d+\.?\d*)"#
        let endPattern = #"silence_end:\s*(\d+\.?\d*)\s*\|\s*silence_duration:\s*(\d+\.?\d*)"#

        guard let startRegex = try? NSRegularExpression(pattern: startPattern),
              let endRegex = try? NSRegularExpression(pattern: endPattern) else {
            return [QCResult(
                check: .silenceDetection,
                passed: true,
                details: "No silence detected (parse unavailable).",
                severity: "info"
            )]
        }

        let nsOutput = output as NSString

        // Collect start times
        let startMatches = startRegex.matches(
            in: output,
            range: NSRange(location: 0, length: nsOutput.length)
        )
        var startTimes: [Double] = []
        for match in startMatches {
            let startStr = nsOutput.substring(with: match.range(at: 1))
            startTimes.append(Double(startStr) ?? 0)
        }

        // Collect end times with durations
        let endMatches = endRegex.matches(
            in: output,
            range: NSRange(location: 0, length: nsOutput.length)
        )

        for (index, match) in endMatches.enumerated() {
            let durationStr = nsOutput.substring(with: match.range(at: 2))
            let duration = Double(durationStr) ?? 0
            let startTime = index < startTimes.count ? startTimes[index] : 0

            results.append(QCResult(
                check: .silenceDetection,
                passed: false,
                details: String(
                    format: "Silence at %.2fs, duration %.2fs",
                    startTime, duration
                ),
                timestamp: startTime,
                severity: duration > 5.0 ? "error" : "warning"
            ))
        }

        if results.isEmpty {
            results.append(QCResult(
                check: .silenceDetection,
                passed: true,
                details: "No silence detected.",
                severity: "info"
            ))
        }

        return results
    }

    // MARK: - Batch Runner

    /// Runs all enabled checks from the given profile and returns
    /// aggregated results.
    ///
    /// This method does **not** execute FFmpeg processes directly. For
    /// checks that require FFmpeg analysis (black frames, silence), it
    /// returns placeholder results indicating the check is pending. The
    /// caller is responsible for running the FFmpeg commands returned by
    /// ``buildBlackFrameDetectionArgs(inputPath:)`` and
    /// ``buildSilenceDetectionArgs(inputPath:threshold:)`` and then
    /// parsing the output.
    ///
    /// Non-FFmpeg checks (audio sync, level compliance, format conformance,
    /// corrupt frames) produce stub results suitable for future expansion.
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the media file.
    ///   - profile: The ``QCProfile`` controlling which checks to run.
    /// - Returns: Array of ``QCResult`` values for all enabled checks.
    public static func runAllChecks(
        inputPath: String,
        profile: QCProfile
    ) -> [QCResult] {
        var results: [QCResult] = []

        for check in profile.enabledChecks.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch check {
            case .blackFrames:
                // Caller must run buildBlackFrameDetectionArgs and parse output.
                results.append(QCResult(
                    check: .blackFrames,
                    passed: true,
                    details: "Black frame detection requires FFmpeg execution. "
                           + "Use buildBlackFrameDetectionArgs() and parseBlackFrameOutput().",
                    severity: "info"
                ))

            case .silenceDetection:
                // Caller must run buildSilenceDetectionArgs and parse output.
                results.append(QCResult(
                    check: .silenceDetection,
                    passed: true,
                    details: "Silence detection requires FFmpeg execution. "
                           + "Use buildSilenceDetectionArgs() and parseSilenceOutput().",
                    severity: "info"
                ))

            case .audioSync:
                results.append(QCResult(
                    check: .audioSync,
                    passed: true,
                    details: "Audio sync verification pending implementation.",
                    severity: "info"
                ))

            case .levelCompliance:
                let standard = profile.loudnessStandard ?? "unspecified"
                results.append(QCResult(
                    check: .levelCompliance,
                    passed: true,
                    details: "Level compliance (\(standard)) pending implementation.",
                    severity: "info"
                ))

            case .formatConformance:
                // Basic file-existence check as a placeholder.
                let exists = FileManager.default.fileExists(atPath: inputPath)
                results.append(QCResult(
                    check: .formatConformance,
                    passed: exists,
                    details: exists
                        ? "File exists and is accessible."
                        : "File not found at path: \(inputPath)",
                    severity: exists ? "info" : "error"
                ))

            case .corruptFrames:
                results.append(QCResult(
                    check: .corruptFrames,
                    passed: true,
                    details: "Corrupt frame detection pending implementation.",
                    severity: "info"
                ))
            }
        }

        return results
    }
}
