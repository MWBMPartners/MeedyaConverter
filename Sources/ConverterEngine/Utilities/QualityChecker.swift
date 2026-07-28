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
// MARK: - QCStatus
// ---------------------------------------------------------------------------
/// The verdict of a single quality-control check.
///
/// Distinguishes a genuinely-executed check's pass/fail outcome from a
/// check that has no real detector behind it yet. Introduced by Issue #445
/// so that unimplemented checks (``QualityChecker/runAllChecks(inputPath:profile:)``'s
/// former `audioSync`/`levelCompliance`/`corruptFrames`/`formatConformance`
/// stubs) can never be reported as a fabricated ``passed`` result.
public enum QCStatus: String, Codable, Sendable {
    /// The check actually ran and found no issue.
    case passed
    /// The check actually ran and found an issue.
    case failed
    /// The check has no real detector implemented yet and did not run.
    case notImplemented
}

// ---------------------------------------------------------------------------
// MARK: - QCResult
// ---------------------------------------------------------------------------
/// The outcome of a single quality-control check against a media file.
///
/// Each result carries a ``status`` verdict, a human-readable ``details``
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

    /// The verdict for this check: ``QCStatus/passed``, ``QCStatus/failed``,
    /// or ``QCStatus/notImplemented`` when no real detector ran.
    public let status: QCStatus

    /// Human-readable description of the finding.
    public let details: String

    /// Optional position (in seconds) where the issue was found.
    public let timestamp: TimeInterval?

    /// Severity level: "info", "warning", or "error".
    public let severity: String

    /// Convenience accessor: `true` only when the check actually ran and
    /// passed. `false` for both a genuine failure and a not-implemented
    /// check — callers that need to distinguish the two should switch on
    /// ``status`` directly rather than relying on this shortcut.
    public var passed: Bool { status == .passed }

    /// Memberwise initializer.
    public init(
        id: UUID = UUID(),
        check: QCCheckType,
        status: QCStatus,
        details: String,
        timestamp: TimeInterval? = nil,
        severity: String = "info"
    ) {
        self.id = id
        self.check = check
        self.status = status
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

    /// Builds FFmpeg arguments for a corrupt-frame / decode-error scan
    /// (roadmap #8, Issue #445).
    ///
    /// Runs FFmpeg with `-v error` so stderr carries only genuine
    /// decode-error-or-worse log lines (FFmpeg suppresses info/warning
    /// noise at this verbosity), decoding every frame to a null muxer via
    /// `-f null -` — the same null-sink pattern
    /// ``buildBlackFrameDetectionArgs(inputPath:)`` uses — without
    /// re-encoding or writing any output file.
    ///
    /// - Parameter inputPath: Absolute path to the media file to analyse.
    /// - Returns: Array of arguments suitable for `Process.arguments`.
    public static func buildCorruptFrameDetectionArgs(inputPath: String) -> [String] {
        return [
            "-v", "error",
            "-i", inputPath,
            "-f", "null",
            "-"
        ]
    }

    /// Builds FFmpeg arguments for a loudness-compliance measurement pass
    /// (roadmap #8, Issue #445).
    ///
    /// Delegates to ``LoudnessReporter/buildAnalysisArguments(inputPath:)``
    /// — the identical `loudnorm=print_format=json` measurement command
    /// already proven by `LoudnessReportView` — so `levelCompliance`
    /// reuses the exact same, tested FFmpeg invocation rather than
    /// inventing a second one.
    ///
    /// - Parameter inputPath: Absolute path to the media file to analyse.
    /// - Returns: Array of arguments suitable for `Process.arguments`.
    public static func buildLevelComplianceArgs(inputPath: String) -> [String] {
        LoudnessReporter.buildAnalysisArguments(inputPath: inputPath)
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
                status: .passed,
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
                status: .failed,
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
                status: .passed,
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
                status: .passed,
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
                status: .failed,
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
                status: .passed,
                details: "No silence detected.",
                severity: "info"
            ))
        }

        return results
    }

    /// Parses FFmpeg `-v error` stderr output from
    /// ``buildCorruptFrameDetectionArgs(inputPath:)`` into structured
    /// ``QCResult`` values (roadmap #8, Issue #445).
    ///
    /// At `-v error` verbosity FFmpeg only emits lines for genuine decode
    /// errors and worse (info/warning-level chatter like filter setup or
    /// stream mapping is suppressed), so every non-blank line in `output`
    /// is treated as one real decode-error report — mirroring
    /// ``parseBlackFrameOutput(_:)``'s one-``QCResult``-per-detected-issue
    /// shape. An empty (or whitespace-only) `output` means FFmpeg decoded
    /// the whole file without reporting a single error, so a single
    /// passing result is returned.
    ///
    /// - Parameter output: The raw stderr text from the `-v error` FFmpeg run.
    /// - Returns: One ``QCResult`` per reported decode error, or a single
    ///   passing result if none were reported.
    public static func parseCorruptFrameOutput(_ output: String) -> [QCResult] {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return [QCResult(
                check: .corruptFrames,
                status: .passed,
                details: "No decode errors detected.",
                severity: "info"
            )]
        }

        return lines.map { line in
            QCResult(
                check: .corruptFrames,
                status: .failed,
                details: line,
                severity: "error"
            )
        }
    }

    /// Best-effort mapping from a ``QCProfile/loudnessStandard`` free-form
    /// label (e.g. `"EBU R128"`, set by the built-in ``broadcast``
    /// profile) to the ``NormalizationStandard`` case
    /// ``LoudnessReporter/checkCompliance(report:standard:)`` needs.
    ///
    /// Falls back to ``NormalizationStandard/ebur128`` — the most common
    /// broadcast target, and the same default `LoudnessReportView` uses —
    /// when the profile leaves the field `nil` or sets it to an
    /// unrecognised string, so `levelCompliance` always evaluates against
    /// *some* real standard rather than silently no-opping.
    ///
    /// - Parameter label: The profile's `loudnessStandard` string, or `nil`.
    /// - Returns: The best-matching ``NormalizationStandard``.
    public static func normalizationStandard(forLoudnessStandard label: String?) -> NormalizationStandard {
        guard let label else { return .ebur128 }
        let lowered = label.lowercased()
        if lowered.contains("ebu") { return .ebur128 }
        if lowered.contains("atsc") { return .atscA85 }
        if lowered.contains("itu") { return .ituBS1770 }
        if lowered.contains("podcast") { return .podcast }
        if lowered.contains("stream") { return .streaming }
        if lowered.contains("cinema") { return .cinema }
        return .ebur128
    }

    /// Parses the `loudnorm` measurement stderr from
    /// ``buildLevelComplianceArgs(inputPath:)`` and evaluates it against
    /// `standard` (roadmap #8, Issue #445).
    ///
    /// Reuses ``LoudnessReporter/parseAnalysisOutput(_:)`` for the JSON
    /// extraction and ``LoudnessReporter/checkCompliance(report:standard:)``
    /// for the pass/fail verdict — the identical, tested EBU R128 logic
    /// `LoudnessReportView` already relies on — so this is a thin adapter
    /// from a `LoudnessReport` to a QC ``QCResult``, not a second
    /// implementation of loudness math.
    ///
    /// - Parameters:
    ///   - output: Raw stderr from the FFmpeg measurement pass.
    ///   - standard: The loudness standard to check compliance against —
    ///     see ``normalizationStandard(forLoudnessStandard:)`` to derive
    ///     one from a ``QCProfile/loudnessStandard`` label.
    /// - Returns: A single-element array with the real pass/fail verdict,
    ///   or a `.failed` result (never `.passed`, and never
    ///   `.notImplemented` — the check genuinely ran) if the measurement
    ///   output could not be parsed.
    public static func parseLevelComplianceOutput(
        _ output: String,
        standard: NormalizationStandard
    ) -> [QCResult] {
        guard let report = LoudnessReporter.parseAnalysisOutput(output) else {
            return [QCResult(
                check: .levelCompliance,
                status: .failed,
                details: "Could not parse loudness measurement output from FFmpeg.",
                severity: "error"
            )]
        }

        let compliant = LoudnessReporter.checkCompliance(report: report, standard: standard)
        let preset = NormalizationPresets.preset(for: standard)
        let details = String(
            format: "Integrated loudness %.1f LUFS (target %.1f LUFS), true peak %.1f dBTP (limit %.1f dBTP) against %@.",
            report.integratedLUFS, preset.targetLUFS, report.truePeakDBTP, preset.truePeakLimit,
            standard.displayName
        )

        return [QCResult(
            check: .levelCompliance,
            status: compliant ? .passed : .failed,
            details: details,
            severity: compliant ? "info" : "warning"
        )]
    }

    // MARK: - Batch Runner

    /// Resolves every enabled check from the given profile that does
    /// **not** require executing an FFmpeg process, and returns their
    /// honest results (Issue #445).
    ///
    /// `blackFrames`, `silenceDetection`, `corruptFrames`, and
    /// `levelCompliance` are deliberately **not** included in this
    /// method's output: all four now have real detectors
    /// (``buildBlackFrameDetectionArgs(inputPath:)`` /
    /// ``parseBlackFrameOutput(_:)``,
    /// ``buildSilenceDetectionArgs(inputPath:threshold:)`` /
    /// ``parseSilenceOutput(_:)``,
    /// ``buildCorruptFrameDetectionArgs(inputPath:)`` /
    /// ``parseCorruptFrameOutput(_:)``, and
    /// ``buildLevelComplianceArgs(inputPath:)`` /
    /// ``parseLevelComplianceOutput(_:standard:)``, added for roadmap #8 /
    /// Issue #445), but running them means executing FFmpeg — something
    /// this pure-function utility does not do (see the type-level
    /// documentation). Callers that enable those checks must run the
    /// FFmpeg commands themselves via `FFmpegProcessController`, parse the
    /// output with the corresponding `parse...Output(_:)` function, and
    /// merge those results with this method's output — see
    /// `QualityCheckView.runQualityChecks()` for the reference
    /// implementation.
    ///
    /// The remaining checks — `audioSync` and `formatConformance` — have
    /// no real detector implemented yet (`audioSync` is gated on #421/
    /// #422). Previously this method reported a fabricated `passed: true`
    /// for every unimplemented check (and `formatConformance` conflated
    /// mere file existence with genuine conformance validation); it now
    /// reports ``QCStatus/notImplemented`` for both so a stub can never be
    /// rendered or exported as a passing check.
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the media file.
    ///   - profile: The ``QCProfile`` controlling which checks to run.
    /// - Returns: Array of ``QCResult`` values for the enabled checks this
    ///   method can resolve without running FFmpeg.
    public static func runAllChecks(
        inputPath: String,
        profile: QCProfile
    ) -> [QCResult] {
        var results: [QCResult] = []

        for check in profile.enabledChecks.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch check {
            case .blackFrames, .silenceDetection, .corruptFrames, .levelCompliance:
                // Requires running FFmpeg — resolved by the caller (e.g.
                // QualityCheckView), not here. Intentionally not appended.
                continue

            case .audioSync:
                results.append(QCResult(
                    check: .audioSync,
                    status: .notImplemented,
                    details: "Audio sync verification has no detector implemented yet.",
                    severity: "info"
                ))

            case .formatConformance:
                // A real conformance check would validate container/codec
                // parameters against a target spec; only file existence can
                // currently be verified, which is not the same claim, so
                // this is reported as not-implemented rather than a pass —
                // the existence check is still surfaced in `details` since
                // a missing file is useful, unambiguous information.
                let exists = FileManager.default.fileExists(atPath: inputPath)
                results.append(QCResult(
                    check: .formatConformance,
                    status: .notImplemented,
                    details: exists
                        ? "Format conformance validation has no detector implemented yet "
                          + "(file exists and is accessible)."
                        : "Format conformance validation has no detector implemented yet, "
                          + "and the file was not found at path: \(inputPath).",
                    severity: exists ? "info" : "error"
                ))
            }
        }

        return results
    }
}
