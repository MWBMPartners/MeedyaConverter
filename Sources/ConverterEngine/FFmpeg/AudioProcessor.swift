// ============================================================================
// MeedyaConverter — AudioProcessor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - LoudnessStandard

/// Target loudness standards for audio normalization.
public enum LoudnessStandard: String, Codable, Sendable, CaseIterable {
    /// EBU R128 — European broadcast standard.
    /// Target: -23 LUFS integrated, -1 dBTP true peak.
    case ebuR128 = "ebu_r128"

    /// ATSC A/85 — US broadcast standard (similar to EBU R128).
    /// Target: -24 LKFS integrated, -2 dBTP true peak.
    case atscA85 = "atsc_a85"

    /// AES streaming — optimized for music streaming platforms.
    /// Target: -14 LUFS integrated, -1 dBTP true peak.
    case streaming = "streaming"

    /// Podcast — standard for spoken word content.
    /// Target: -16 LUFS integrated, -1 dBTP true peak.
    case podcast = "podcast"

    /// Custom — user-defined target values.
    case custom = "custom"

    /// The target integrated loudness in LUFS.
    public var targetLUFS: Double {
        switch self {
        case .ebuR128: return -23.0
        case .atscA85: return -24.0
        case .streaming: return -14.0
        case .podcast: return -16.0
        case .custom: return -23.0
        }
    }

    /// The target true peak in dBTP.
    public var targetTruePeak: Double {
        switch self {
        case .ebuR128: return -1.0
        case .atscA85: return -2.0
        case .streaming: return -1.0
        case .podcast: return -1.0
        case .custom: return -1.0
        }
    }

    /// The loudness range target (LRA) in LU.
    public var targetLRA: Double {
        switch self {
        case .ebuR128: return 20.0
        case .atscA85: return 20.0
        case .streaming: return 15.0
        case .podcast: return 10.0
        case .custom: return 20.0
        }
    }
}

// MARK: - LoudnessMeasurement

/// Results of a loudness analysis pass.
public struct LoudnessMeasurement: Codable, Sendable {
    /// Integrated loudness in LUFS (whole-programme).
    public var integratedLUFS: Double

    /// True peak level in dBTP.
    public var truePeakDBTP: Double

    /// Loudness Range in LU (dynamic range of loudness).
    public var loudnessRangeLU: Double

    /// Short-term loudness maximum in LUFS.
    public var shortTermMax: Double?

    /// Momentary loudness maximum in LUFS.
    public var momentaryMax: Double?

    public init(
        integratedLUFS: Double,
        truePeakDBTP: Double,
        loudnessRangeLU: Double,
        shortTermMax: Double? = nil,
        momentaryMax: Double? = nil
    ) {
        self.integratedLUFS = integratedLUFS
        self.truePeakDBTP = truePeakDBTP
        self.loudnessRangeLU = loudnessRangeLU
        self.shortTermMax = shortTermMax
        self.momentaryMax = momentaryMax
    }
}

// MARK: - ReplayGainResult

/// ReplayGain analysis results for a single track or album.
public struct ReplayGainResult: Codable, Sendable {
    /// The recommended gain adjustment in dB.
    public var gainDB: Double

    /// The peak sample value (0.0 to 1.0).
    public var peak: Double

    /// Whether this is album-mode (true) or track-mode (false) gain.
    public var isAlbumMode: Bool

    /// The reference loudness level in LUFS (typically -18 LUFS for ReplayGain 2.0).
    public static let referenceLUFS: Double = -18.0

    public init(gainDB: Double, peak: Double, isAlbumMode: Bool) {
        self.gainDB = gainDB
        self.peak = peak
        self.isAlbumMode = isAlbumMode
    }
}

// MARK: - AudioProcessor

/// Builds FFmpeg filter chains for audio processing operations.
///
/// Provides loudness normalization (EBU R128), ReplayGain analysis,
/// peak limiting, and other audio processing filters used in encoding
/// and audio extraction workflows.
///
/// Phase 5.1-5.3
public struct AudioProcessor: Sendable {

    // MARK: - EBU R128 Loudness Normalization

    /// Build a loudnorm filter for EBU R128 loudness normalization.
    ///
    /// The loudnorm filter performs two-pass loudness normalization:
    /// - Pass 1: Analyse the source to measure integrated loudness, LRA, and true peak
    /// - Pass 2: Apply linear gain + dynamic limiting to hit the target
    ///
    /// For single-pass (live/streaming), use `linear: false` which applies
    /// dynamic range compression when needed.
    ///
    /// - Parameters:
    ///   - standard: The target loudness standard.
    ///   - targetLUFS: Custom target LUFS (overrides standard if non-nil).
    ///   - targetTP: Custom target true peak dBTP (overrides standard if non-nil).
    ///   - targetLRA: Custom target LRA in LU (overrides standard if non-nil).
    ///   - linear: Whether to use linear normalization (true = no dynamic compression).
    ///   - measurement: Optional first-pass measurement for two-pass mode.
    /// - Returns: The FFmpeg loudnorm filter string.
    public static func buildLoudnormFilter(
        standard: LoudnessStandard = .ebuR128,
        targetLUFS: Double? = nil,
        targetTP: Double? = nil,
        targetLRA: Double? = nil,
        linear: Bool = true,
        measurement: LoudnessMeasurement? = nil
    ) -> String {
        let lufs = targetLUFS ?? standard.targetLUFS
        let tp = targetTP ?? standard.targetTruePeak
        let lra = targetLRA ?? standard.targetLRA

        var filter = "loudnorm=I=\(lufs):TP=\(tp):LRA=\(lra)"

        if linear {
            filter += ":linear=true"
        }

        // Two-pass mode: inject first-pass measurements
        if let m = measurement {
            filter += ":measured_I=\(m.integratedLUFS)"
            filter += ":measured_TP=\(m.truePeakDBTP)"
            filter += ":measured_LRA=\(m.loudnessRangeLU)"
        }

        // Request JSON stats output for first-pass analysis
        filter += ":print_format=json"

        return filter
    }

    /// Build FFmpeg arguments for a loudness analysis pass (first pass of two-pass).
    ///
    /// Runs the loudnorm filter in analysis mode, outputting to /dev/null.
    /// Parse the JSON output from stderr to get the LoudnessMeasurement.
    public static func buildAnalysisPassArguments(
        inputURL: URL,
        standard: LoudnessStandard = .ebuR128
    ) -> [String] {
        let filter = buildLoudnormFilter(standard: standard, linear: true)
        return [
            "-y", "-nostdin",
            "-i", inputURL.path,
            "-af", filter,
            "-f", "null",
            "/dev/null"
        ]
    }

    // MARK: - ReplayGain

    /// Build FFmpeg arguments for ReplayGain analysis.
    ///
    /// Uses the replaygain filter to calculate the recommended gain
    /// adjustment. The result is output to stderr as a log line.
    public static func buildReplayGainAnalysisArguments(inputURL: URL) -> [String] {
        return [
            "-y", "-nostdin",
            "-i", inputURL.path,
            "-af", "replaygain",
            "-f", "null",
            "/dev/null"
        ]
    }

    /// Build a volume filter to apply ReplayGain adjustment.
    ///
    /// - Parameters:
    ///   - gainDB: The gain adjustment in dB from ReplayGain analysis.
    ///   - preventClipping: Whether to limit gain to prevent clipping.
    /// - Returns: The FFmpeg volume filter string.
    public static func buildReplayGainApplyFilter(
        gainDB: Double,
        preventClipping: Bool = true
    ) -> String {
        if preventClipping {
            // Apply gain with a limiter to prevent clipping
            return "volume=\(String(format: "%.1f", gainDB))dB,alimiter=limit=1.0:attack=5:release=50"
        }
        return "volume=\(String(format: "%.1f", gainDB))dB"
    }

    // MARK: - Peak Limiting

    /// Build a peak limiter filter chain.
    ///
    /// Applies a brickwall limiter to ensure the output never exceeds
    /// the specified true peak level. Essential for broadcast compliance.
    ///
    /// - Parameters:
    ///   - limitDBTP: Maximum true peak in dBTP (e.g., -1.0 for EBU R128).
    ///   - attack: Attack time in milliseconds (1-100).
    ///   - release: Release time in milliseconds (10-2000).
    /// - Returns: The FFmpeg alimiter filter string.
    public static func buildPeakLimiterFilter(
        limitDBTP: Double = -1.0,
        attack: Double = 5.0,
        release: Double = 50.0
    ) -> String {
        // Convert dBTP to linear level
        let linearLimit = pow(10.0, limitDBTP / 20.0)
        return "alimiter=limit=\(String(format: "%.6f", linearLimit)):attack=\(String(format: "%.0f", attack)):release=\(String(format: "%.0f", release)):level=false"
    }

    // MARK: - Combined Chains

    /// Build a complete audio processing chain combining normalization and limiting.
    ///
    /// - Parameters:
    ///   - normalize: Whether to apply loudness normalization.
    ///   - standard: The normalization standard.
    ///   - limit: Whether to apply peak limiting.
    ///   - limitDBTP: Peak limit level.
    ///   - measurement: Optional first-pass measurement for two-pass normalization.
    /// - Returns: The combined filter chain string, or nil if no processing.
    public static func buildProcessingChain(
        normalize: Bool = true,
        standard: LoudnessStandard = .ebuR128,
        limit: Bool = true,
        limitDBTP: Double = -1.0,
        measurement: LoudnessMeasurement? = nil
    ) -> String? {
        var filters: [String] = []

        if normalize {
            filters.append(buildLoudnormFilter(
                standard: standard,
                linear: measurement != nil, // Linear only in two-pass
                measurement: measurement
            ))
        }

        if limit && !normalize {
            // Only add separate limiter if not normalizing
            // (loudnorm already includes peak control)
            filters.append(buildPeakLimiterFilter(limitDBTP: limitDBTP))
        }

        return filters.isEmpty ? nil : filters.joined(separator: ",")
    }
}
