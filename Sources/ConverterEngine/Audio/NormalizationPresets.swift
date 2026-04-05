// ============================================================================
// MeedyaConverter — NormalizationPresets (Issue #292)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - NormalizationStandard

/// Audio loudness normalization standards used in broadcast, streaming,
/// podcast, and cinema production.
///
/// Each standard defines a target integrated loudness (LUFS/LKFS) and
/// a true-peak ceiling (dBTP). The ``custom`` case allows user-defined
/// targets that do not correspond to any published specification.
///
/// References:
/// - EBU R128: https://tech.ebu.ch/docs/r/r128.pdf
/// - ITU-R BS.1770: https://www.itu.int/rec/R-REC-BS.1770
/// - ATSC A/85: https://www.atsc.org/standard/a85-2013/
public enum NormalizationStandard: String, Codable, Sendable, CaseIterable {

    /// EBU R128 — European broadcast standard.
    /// Target: -23 LUFS, True Peak: -1 dBTP, recommended LRA <= 18 LU.
    case ebur128

    /// ITU-R BS.1770 — International measurement algorithm.
    /// Target: -24 LKFS, True Peak: -2 dBTP.
    case ituBS1770

    /// ATSC A/85 — United States broadcast standard (FCC mandate).
    /// Target: -24 LKFS, True Peak: -2 dBTP.
    case atscA85

    /// Podcast standard — conversational audio.
    /// Target: -16 LUFS, True Peak: -1 dBTP.
    case podcast

    /// Streaming platforms (Spotify, YouTube, Apple Music style).
    /// Target: -14 LUFS, True Peak: -1 dBTP.
    case streaming

    /// Cinema reference level.
    /// Target: -27 LUFS, True Peak: -1 dBTP.
    case cinema

    /// User-defined targets that do not conform to a published standard.
    case custom

    /// Human-readable display name for the normalization standard.
    public var displayName: String {
        switch self {
        case .ebur128:   return "EBU R128 (Broadcast)"
        case .ituBS1770: return "ITU-R BS.1770"
        case .atscA85:   return "ATSC A/85 (US Broadcast)"
        case .podcast:   return "Podcast (-16 LUFS)"
        case .streaming: return "Streaming (-14 LUFS)"
        case .cinema:    return "Cinema (-27 LUFS)"
        case .custom:    return "Custom"
        }
    }

    /// Brief description of the standard and its typical use case.
    public var descriptionText: String {
        switch self {
        case .ebur128:
            return "European broadcast standard. Target -23 LUFS with -1 dBTP true peak limit."
        case .ituBS1770:
            return "International loudness measurement algorithm. Target -24 LKFS with -2 dBTP."
        case .atscA85:
            return "US broadcast standard mandated by FCC. Target -24 LKFS with -2 dBTP."
        case .podcast:
            return "Optimized for conversational audio. Target -16 LUFS with -1 dBTP."
        case .streaming:
            return "Matches Spotify, YouTube, and Apple Music loudness targets. -14 LUFS, -1 dBTP."
        case .cinema:
            return "Cinema reference level for theatrical exhibition. Target -27 LUFS, -1 dBTP."
        case .custom:
            return "User-defined LUFS target and true peak limit."
        }
    }
}

// MARK: - NormalizationConfig

/// Configuration for an audio loudness normalization pass.
///
/// Encapsulates the target loudness, true peak ceiling, and whether
/// to perform measurement-only (first pass) or apply correction.
public struct NormalizationConfig: Codable, Sendable {

    /// The normalization standard to apply.
    public var standard: NormalizationStandard

    /// Target integrated loudness in LUFS (Loudness Units Full Scale).
    /// Typical range: -40 to -5.
    public var targetLUFS: Double

    /// Maximum permitted true peak level in dBTP (decibels True Peak).
    /// Typical range: -6 to 0.
    public var truePeakLimit: Double

    /// When `true`, measure loudness without applying normalization.
    /// Useful for previewing levels before committing to a full encode.
    public var measureOnly: Bool

    /// Memberwise initializer.
    public init(
        standard: NormalizationStandard,
        targetLUFS: Double,
        truePeakLimit: Double,
        measureOnly: Bool = false
    ) {
        self.standard = standard
        self.targetLUFS = targetLUFS
        self.truePeakLimit = truePeakLimit
        self.measureOnly = measureOnly
    }
}

// MARK: - NormalizationPresets

/// Factory and argument builder for audio loudness normalization.
///
/// Provides preset configurations for common normalization standards
/// and generates FFmpeg `loudnorm` filter strings for both measurement
/// (first pass) and correction (second pass) workflows.
///
/// Phase 10 — Audio Normalization Presets (Issue #292)
public struct NormalizationPresets: Sendable {

    // MARK: - Preset Factory

    /// Return the default ``NormalizationConfig`` for a given standard.
    ///
    /// For the ``NormalizationStandard/custom`` case, returns a neutral
    /// config at -16 LUFS / -1 dBTP that the user can adjust.
    ///
    /// - Parameter standard: The normalization standard to configure.
    /// - Returns: A ``NormalizationConfig`` with the standard's default values.
    public static func preset(for standard: NormalizationStandard) -> NormalizationConfig {
        switch standard {
        case .ebur128:
            return NormalizationConfig(standard: .ebur128, targetLUFS: -23, truePeakLimit: -1)
        case .ituBS1770:
            return NormalizationConfig(standard: .ituBS1770, targetLUFS: -24, truePeakLimit: -2)
        case .atscA85:
            return NormalizationConfig(standard: .atscA85, targetLUFS: -24, truePeakLimit: -2)
        case .podcast:
            return NormalizationConfig(standard: .podcast, targetLUFS: -16, truePeakLimit: -1)
        case .streaming:
            return NormalizationConfig(standard: .streaming, targetLUFS: -14, truePeakLimit: -1)
        case .cinema:
            return NormalizationConfig(standard: .cinema, targetLUFS: -27, truePeakLimit: -1)
        case .custom:
            return NormalizationConfig(standard: .custom, targetLUFS: -16, truePeakLimit: -1)
        }
    }

    // MARK: - FFmpeg Filter Generation

    /// Generate an FFmpeg `loudnorm` audio filter string for the given config.
    ///
    /// The filter performs EBU R128 loudness normalization with the specified
    /// integrated loudness target and true peak limit. The loudness range (LRA)
    /// defaults to 11 LU, which is suitable for most broadcast content.
    ///
    /// Example output: `loudnorm=I=-16:TP=-1:LRA=11`
    ///
    /// - Parameter config: The normalization configuration.
    /// - Returns: An FFmpeg audio filter string.
    public static func buildLoudnormFilter(config: NormalizationConfig) -> String {
        let i = String(format: "%.1f", config.targetLUFS)
        let tp = String(format: "%.1f", config.truePeakLimit)
        return "loudnorm=I=\(i):TP=\(tp):LRA=11"
    }

    // MARK: - Measurement Pass

    /// Build FFmpeg arguments for a measurement-only first pass.
    ///
    /// Runs the `loudnorm` filter in analysis mode, outputting JSON-formatted
    /// loudness measurements to stderr. The caller should capture stderr and
    /// parse the JSON block containing `input_i`, `input_tp`, `input_lra`,
    /// `input_thresh`, `target_offset`, etc.
    ///
    /// - Parameter inputPath: Absolute path to the source audio/media file.
    /// - Returns: An array of command-line arguments for FFmpeg.
    public static func buildMeasureArguments(inputPath: String) -> [String] {
        return [
            "-i", inputPath,
            "-af", "loudnorm=print_format=json",
            "-f", "null",
            "-"
        ]
    }

    // MARK: - Measurement Result Parsing

    /// Parse the JSON loudness measurement output from an FFmpeg first-pass.
    ///
    /// Extracts the `input_i` (integrated loudness), `input_tp` (true peak),
    /// and `input_lra` (loudness range) values from the JSON block emitted
    /// by FFmpeg's `loudnorm` filter.
    ///
    /// - Parameter output: Raw stderr output from the FFmpeg measurement pass.
    /// - Returns: A tuple of (integratedLUFS, truePeakDBTP, loudnessRangeLU),
    ///            or `nil` if parsing fails.
    public static func parseMeasurementOutput(
        _ output: String
    ) -> (integratedLUFS: Double, truePeakDBTP: Double, loudnessRangeLU: Double)? {
        // The loudnorm JSON block is embedded in FFmpeg's stderr output.
        // Look for the opening brace after "Parsed_loudnorm" or standalone JSON.
        guard let jsonStart = output.range(of: "{", options: .backwards),
              let jsonEnd = output.range(of: "}", options: .backwards) else {
            return nil
        }

        let jsonString = String(output[jsonStart.lowerBound...jsonEnd.upperBound])

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Extract values (FFmpeg outputs them as strings)
        guard let inputIStr = json["input_i"] as? String,
              let inputTPStr = json["input_tp"] as? String,
              let inputLRAStr = json["input_lra"] as? String,
              let inputI = Double(inputIStr),
              let inputTP = Double(inputTPStr),
              let inputLRA = Double(inputLRAStr) else {
            return nil
        }

        return (integratedLUFS: inputI, truePeakDBTP: inputTP, loudnessRangeLU: inputLRA)
    }
}
