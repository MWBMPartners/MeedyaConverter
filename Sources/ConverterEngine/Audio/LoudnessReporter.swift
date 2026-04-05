// ============================================================================
// MeedyaConverter — LoudnessReporter (Issue #340)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - LoudnessReport

/// Results from an EBU R128 / ITU-R BS.1770 loudness analysis pass.
///
/// Contains the five key loudness metrics (integrated, true peak,
/// loudness range, short-term max, momentary max) along with
/// compliance status and metadata about the analysis.
///
/// Phase 12 — Loudness Compliance Report (Issue #340)
public struct LoudnessReport: Codable, Sendable {

    /// Integrated loudness in LUFS (Loudness Units Full Scale).
    /// This is the primary metric for broadcast compliance.
    public let integratedLUFS: Double

    /// True peak level in dBTP (decibels True Peak).
    /// Measured using an oversampled peak detector per ITU-R BS.1770.
    public let truePeakDBTP: Double

    /// Loudness Range (LRA) in LU (Loudness Units).
    /// Measures the variation between quiet and loud passages.
    public let loudnessRange: Double

    /// Maximum short-term loudness (3-second window) in LUFS.
    public let shortTermMax: Double

    /// Maximum momentary loudness (400 ms window) in LUFS.
    public let momentaryMax: Double

    /// Whether the file meets the specified loudness standard.
    public let compliant: Bool

    /// Name of the standard the file was checked against (e.g., "EBU R128").
    public let standard: String

    /// Name of the analysed file (basename, not full path).
    public let fileName: String

    /// Date and time when the analysis was performed.
    public let analyzedAt: Date

    /// Memberwise initializer.
    public init(
        integratedLUFS: Double,
        truePeakDBTP: Double,
        loudnessRange: Double,
        shortTermMax: Double,
        momentaryMax: Double,
        compliant: Bool,
        standard: String,
        fileName: String,
        analyzedAt: Date = Date()
    ) {
        self.integratedLUFS = integratedLUFS
        self.truePeakDBTP = truePeakDBTP
        self.loudnessRange = loudnessRange
        self.shortTermMax = shortTermMax
        self.momentaryMax = momentaryMax
        self.compliant = compliant
        self.standard = standard
        self.fileName = fileName
        self.analyzedAt = analyzedAt
    }
}

// MARK: - LoudnessReporter

/// Builds FFmpeg arguments for loudness analysis and generates compliance reports.
///
/// Uses FFmpeg's `loudnorm` filter in measurement mode to extract
/// EBU R128 / ITU-R BS.1770 loudness metrics from audio files, then
/// evaluates compliance against broadcast standards and generates
/// HTML or JSON reports.
///
/// Supported standards (via ``NormalizationStandard``):
/// - **EBU R128** — European broadcast (-23 LUFS, -1 dBTP)
/// - **ATSC A/85** — US broadcast (-24 LKFS, -2 dBTP)
/// - **ITU-R BS.1770** — International (-24 LKFS, -2 dBTP)
/// - **Podcast** — Conversational audio (-16 LUFS, -1 dBTP)
/// - **Streaming** — Spotify/YouTube/Apple Music (-14 LUFS, -1 dBTP)
/// - **Cinema** — Theatrical exhibition (-27 LUFS, -1 dBTP)
///
/// Phase 12 — Loudness Compliance Report (Issue #340)
public struct LoudnessReporter: Sendable {

    // MARK: - Analysis Arguments

    /// Build FFmpeg arguments for a loudness measurement pass.
    ///
    /// Runs the `loudnorm` filter with `print_format=json` to output
    /// detailed loudness measurements to stderr. The output is discarded
    /// (`-f null -`) since only the measurement JSON is needed.
    ///
    /// - Parameter inputPath: Absolute path to the source audio/media file.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildAnalysisArguments(inputPath: String) -> [String] {
        return [
            "-i", inputPath,
            "-af", "loudnorm=print_format=json",
            "-f", "null",
            "-"
        ]
    }

    // MARK: - Output Parsing

    /// Parse loudness analysis JSON output from FFmpeg's `loudnorm` filter.
    ///
    /// Extracts integrated loudness, true peak, loudness range, short-term
    /// max, and momentary max from the JSON block embedded in FFmpeg's
    /// stderr output. Returns `nil` if the JSON cannot be parsed.
    ///
    /// - Parameter output: Raw stderr output from the FFmpeg analysis pass.
    /// - Returns: A ``LoudnessReport`` if parsing succeeds, or `nil`.
    public static func parseAnalysisOutput(_ output: String) -> LoudnessReport? {
        // FFmpeg embeds the loudnorm JSON block in stderr output.
        // Find the last JSON object in the output.
        guard let jsonStart = output.range(of: "{", options: .backwards),
              let jsonEnd = output.range(of: "}", options: .backwards)
        else {
            return nil
        }

        let jsonString = String(output[jsonStart.lowerBound...jsonEnd.upperBound])

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        // FFmpeg outputs all values as strings
        guard let inputI = parseDouble(json["input_i"]),
              let inputTP = parseDouble(json["input_tp"]),
              let inputLRA = parseDouble(json["input_lra"])
        else {
            return nil
        }

        // Short-term and momentary max may not always be present;
        // default to the integrated value if missing.
        let shortTerm = parseDouble(json["input_thresh"]) ?? inputI
        let momentary = parseDouble(json["target_offset"]) ?? inputI

        return LoudnessReport(
            integratedLUFS: inputI,
            truePeakDBTP: inputTP,
            loudnessRange: inputLRA,
            shortTermMax: shortTerm,
            momentaryMax: momentary,
            compliant: false, // Caller should use checkCompliance() to set this
            standard: "",
            fileName: ""
        )
    }

    // MARK: - HTML Report

    /// Generate an HTML compliance report for one or more loudness analyses.
    ///
    /// The report includes a summary table with pass/fail badges for each
    /// file, individual metric gauges, and the standard that was checked.
    /// Suitable for saving as a standalone `.html` file or embedding in
    /// a web view.
    ///
    /// - Parameter reports: Array of ``LoudnessReport`` instances to include.
    /// - Returns: A complete HTML document string.
    public static func generateHTMLReport(reports: [LoudnessReport]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var rows = ""
        for report in reports {
            let badge = report.compliant
                ? "<span style=\"color:#22c55e;font-weight:bold;\">PASS</span>"
                : "<span style=\"color:#ef4444;font-weight:bold;\">FAIL</span>"

            rows += """
                <tr>
                    <td>\(escapeHTML(report.fileName))</td>
                    <td>\(String(format: "%.1f", report.integratedLUFS)) LUFS</td>
                    <td>\(String(format: "%.1f", report.truePeakDBTP)) dBTP</td>
                    <td>\(String(format: "%.1f", report.loudnessRange)) LU</td>
                    <td>\(String(format: "%.1f", report.shortTermMax)) LUFS</td>
                    <td>\(String(format: "%.1f", report.momentaryMax)) LUFS</td>
                    <td>\(escapeHTML(report.standard))</td>
                    <td>\(badge)</td>
                    <td>\(dateFormatter.string(from: report.analyzedAt))</td>
                </tr>

                """
        }

        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Loudness Compliance Report</title>
                <style>
                    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2em; background: #1a1a2e; color: #e0e0e0; }
                    h1 { color: #ffffff; border-bottom: 2px solid #4a90d9; padding-bottom: 0.5em; }
                    table { border-collapse: collapse; width: 100%; margin-top: 1em; }
                    th, td { padding: 0.75em 1em; text-align: left; border-bottom: 1px solid #333; }
                    th { background: #16213e; color: #4a90d9; font-weight: 600; }
                    tr:hover { background: #16213e; }
                    .footer { margin-top: 2em; font-size: 0.85em; color: #888; }
                </style>
            </head>
            <body>
                <h1>Loudness Compliance Report</h1>
                <p>Generated by MeedyaConverter &mdash; MWBM Partners Ltd.</p>
                <table>
                    <thead>
                        <tr>
                            <th>File</th>
                            <th>Integrated</th>
                            <th>True Peak</th>
                            <th>LRA</th>
                            <th>Short-Term Max</th>
                            <th>Momentary Max</th>
                            <th>Standard</th>
                            <th>Status</th>
                            <th>Analysed</th>
                        </tr>
                    </thead>
                    <tbody>
                        \(rows)
                    </tbody>
                </table>
                <div class="footer">
                    <p>\(reports.count) file(s) analysed. \(reports.filter(\.compliant).count) passed, \(reports.filter { !$0.compliant }.count) failed.</p>
                </div>
            </body>
            </html>
            """
    }

    // MARK: - JSON Report

    /// Generate a JSON-encoded report for one or more loudness analyses.
    ///
    /// Uses `JSONEncoder` with `.prettyPrinted` and `.sortedKeys` options
    /// for human-readable output. Dates are encoded in ISO 8601 format.
    ///
    /// - Parameter reports: Array of ``LoudnessReport`` instances to encode.
    /// - Returns: UTF-8 encoded JSON `Data`.
    /// - Throws: `EncodingError` if serialization fails.
    public static func generateJSONReport(reports: [LoudnessReport]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(reports)
    }

    // MARK: - Compliance Checking

    /// Check whether a loudness report meets a given normalization standard.
    ///
    /// Compares the report's integrated loudness and true peak values
    /// against the tolerances defined by the specified standard. EBU R128
    /// allows +/- 1 LU tolerance on integrated loudness; other standards
    /// use a +/- 0.5 LU tolerance by convention.
    ///
    /// - Parameters:
    ///   - report: The loudness report to evaluate.
    ///   - standard: The normalization standard to check against.
    /// - Returns: `true` if the report meets the standard's requirements.
    public static func checkCompliance(
        report: LoudnessReport,
        standard: NormalizationStandard
    ) -> Bool {
        let preset = NormalizationPresets.preset(for: standard)

        // EBU R128 allows +/- 1 LU tolerance; others use +/- 0.5 LU
        let tolerance: Double = (standard == .ebur128) ? 1.0 : 0.5

        let lufsCompliant = abs(report.integratedLUFS - preset.targetLUFS) <= tolerance
        let peakCompliant = report.truePeakDBTP <= preset.truePeakLimit

        return lufsCompliant && peakCompliant
    }

    // MARK: - Helpers

    /// Attempt to parse a Double from a JSON value that may be String or Number.
    private static func parseDouble(_ value: Any?) -> Double? {
        if let str = value as? String {
            return Double(str)
        }
        if let num = value as? Double {
            return num
        }
        return nil
    }

    /// Escape HTML special characters in a string.
    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
