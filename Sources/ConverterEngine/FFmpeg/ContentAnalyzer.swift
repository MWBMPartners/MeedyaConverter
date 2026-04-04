// ============================================================================
// MeedyaConverter — ContentAnalyzer
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ContentComplexity

/// Classification of video content complexity.
public enum ContentComplexity: String, Codable, Sendable, CaseIterable {
    /// Static content: slides, talking heads, surveillance. Low bitrate sufficient.
    case veryLow = "very_low"

    /// Low motion: interviews, dialogue scenes, slow pans.
    case low = "low"

    /// Medium motion: standard drama, moderate action, documentaries.
    case medium = "medium"

    /// High motion: sports, fast action, quick cuts.
    case high = "high"

    /// Very high motion: extreme sports, fast-paced gaming, chaotic scenes.
    case veryHigh = "very_high"

    /// Recommended CRF adjustment relative to baseline.
    /// Negative = higher quality (more bits), positive = lower quality (fewer bits).
    public var crfAdjustment: Int {
        switch self {
        case .veryLow: return 4
        case .low: return 2
        case .medium: return 0
        case .high: return -2
        case .veryHigh: return -4
        }
    }

    /// Recommended bitrate multiplier relative to baseline.
    public var bitrateMultiplier: Double {
        switch self {
        case .veryLow: return 0.5
        case .low: return 0.75
        case .medium: return 1.0
        case .high: return 1.5
        case .veryHigh: return 2.0
        }
    }
}

// MARK: - ContentType

/// High-level content type classification.
public enum ContentType: String, Codable, Sendable {
    /// Film/drama — typical cinematic content with moderate motion.
    case film = "film"

    /// Animation — sharp edges, flat colours, typically compresses well.
    case animation = "animation"

    /// Sports/action — fast motion, high temporal complexity.
    case sports = "sports"

    /// Talking head — mostly static with occasional motion.
    case talkingHead = "talking_head"

    /// Screen content — text, UI, desktop recordings.
    case screenContent = "screen_content"

    /// Music video — varied, often high complexity.
    case musicVideo = "music_video"

    /// Documentary — mixed complexity, often nature/landscape.
    case documentary = "documentary"

    /// Gaming — screen capture of gameplay, variable complexity.
    case gaming = "gaming"

    /// Recommended encoder tuning for this content type.
    public var encoderTune: String? {
        switch self {
        case .film: return "film"
        case .animation: return "animation"
        case .screenContent: return "stillimage"
        case .sports: return "fastdecode"
        default: return nil
        }
    }
}

// MARK: - SegmentAnalysis

/// Analysis result for a single video segment.
public struct SegmentAnalysis: Codable, Sendable {
    /// Start timestamp in seconds.
    public var startTime: TimeInterval

    /// End timestamp in seconds.
    public var endTime: TimeInterval

    /// Temporal complexity score (0.0–1.0). Based on motion estimation.
    public var temporalComplexity: Double

    /// Spatial complexity score (0.0–1.0). Based on texture/detail.
    public var spatialComplexity: Double

    /// Overall complexity classification.
    public var complexity: ContentComplexity

    /// Whether this segment contains a scene change.
    public var hasSceneChange: Bool

    /// Average brightness (0.0–1.0).
    public var averageBrightness: Double?

    /// Whether film grain is detected.
    public var hasFilmGrain: Bool

    public init(
        startTime: TimeInterval,
        endTime: TimeInterval,
        temporalComplexity: Double,
        spatialComplexity: Double,
        complexity: ContentComplexity = .medium,
        hasSceneChange: Bool = false,
        averageBrightness: Double? = nil,
        hasFilmGrain: Bool = false
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.temporalComplexity = temporalComplexity
        self.spatialComplexity = spatialComplexity
        self.complexity = complexity
        self.hasSceneChange = hasSceneChange
        self.averageBrightness = averageBrightness
        self.hasFilmGrain = hasFilmGrain
    }

    /// Duration of this segment in seconds.
    public var duration: TimeInterval { endTime - startTime }
}

// MARK: - ContentAnalysisResult

/// Complete content analysis result for a video.
public struct ContentAnalysisResult: Codable, Sendable {
    /// Per-segment analysis results.
    public var segments: [SegmentAnalysis]

    /// Overall content complexity.
    public var overallComplexity: ContentComplexity

    /// Detected content type.
    public var contentType: ContentType?

    /// Average temporal complexity across all segments.
    public var averageTemporalComplexity: Double {
        guard !segments.isEmpty else { return 0 }
        return segments.map(\.temporalComplexity).reduce(0, +) / Double(segments.count)
    }

    /// Average spatial complexity across all segments.
    public var averageSpatialComplexity: Double {
        guard !segments.isEmpty else { return 0 }
        return segments.map(\.spatialComplexity).reduce(0, +) / Double(segments.count)
    }

    /// Whether film grain was detected in any segment.
    public var hasFilmGrain: Bool {
        segments.contains { $0.hasFilmGrain }
    }

    public init(
        segments: [SegmentAnalysis] = [],
        overallComplexity: ContentComplexity = .medium,
        contentType: ContentType? = nil
    ) {
        self.segments = segments
        self.overallComplexity = overallComplexity
        self.contentType = contentType
    }
}

// MARK: - ContentAwareConfig

/// Configuration for content-aware encoding.
public struct ContentAwareConfig: Codable, Sendable {
    /// Whether content-aware encoding is enabled.
    public var enabled: Bool

    /// Minimum CRF (highest quality) for complex scenes.
    public var minCRF: Int

    /// Maximum CRF (lowest quality) for simple scenes.
    public var maxCRF: Int

    /// Baseline CRF for medium-complexity content.
    public var baselineCRF: Int

    /// Whether to enable film grain synthesis (AV1) for grainy content.
    public var filmGrainSynthesis: Bool

    /// Whether to enable macroblock-tree rate control (x264/x265).
    public var mbtreeEnabled: Bool

    /// AQ (Adaptive Quantisation) mode for x265.
    /// 0 = off, 1 = enabled, 2 = auto-variance, 3 = auto-variance with bias.
    public var aqMode: Int

    public init(
        enabled: Bool = true,
        minCRF: Int = 16,
        maxCRF: Int = 32,
        baselineCRF: Int = 22,
        filmGrainSynthesis: Bool = true,
        mbtreeEnabled: Bool = true,
        aqMode: Int = 2
    ) {
        self.enabled = enabled
        self.minCRF = minCRF
        self.maxCRF = maxCRF
        self.baselineCRF = baselineCRF
        self.filmGrainSynthesis = filmGrainSynthesis
        self.mbtreeEnabled = mbtreeEnabled
        self.aqMode = aqMode
    }
}

// MARK: - ContentAnalyzer

/// Builds FFmpeg filter chains for content complexity analysis and
/// generates content-aware encoding parameters.
///
/// Analyses temporal and spatial complexity to classify content and
/// adjust encoding parameters for optimal quality/size tradeoff.
///
/// Phase 7.16
public struct ContentAnalyzer: Sendable {

    /// Build FFmpeg arguments for temporal/spatial complexity analysis.
    ///
    /// Uses the `signalstats` filter to measure spatial information (SI)
    /// and temporal information (TI) per ITU-T P.910.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the video file.
    ///   - sampleInterval: Analyse every Nth second (for performance).
    /// - Returns: FFmpeg argument array.
    public static func buildAnalysisArguments(
        inputPath: String,
        sampleInterval: Int = 2
    ) -> [String] {
        return [
            "-i", inputPath,
            "-vf", "select='not(mod(n\\,\(sampleInterval * 30)))',signalstats,metadata=print:file=-",
            "-vsync", "vfr",
            "-f", "null",
            "-hide_banner",
            "-"
        ]
    }

    /// Classify content complexity from temporal and spatial scores.
    ///
    /// - Parameters:
    ///   - temporalComplexity: Temporal complexity score (0.0–1.0).
    ///   - spatialComplexity: Spatial complexity score (0.0–1.0).
    /// - Returns: Content complexity classification.
    public static func classifyComplexity(
        temporalComplexity: Double,
        spatialComplexity: Double
    ) -> ContentComplexity {
        let combined = (temporalComplexity * 0.6) + (spatialComplexity * 0.4)

        switch combined {
        case ..<0.15: return .veryLow
        case 0.15..<0.35: return .low
        case 0.35..<0.60: return .medium
        case 0.60..<0.80: return .high
        default: return .veryHigh
        }
    }

    /// Calculate the adjusted CRF for a segment based on its complexity.
    ///
    /// - Parameters:
    ///   - config: Content-aware configuration.
    ///   - complexity: The segment's complexity classification.
    /// - Returns: Adjusted CRF value, clamped to the configured range.
    public static func adjustedCRF(
        config: ContentAwareConfig,
        complexity: ContentComplexity
    ) -> Int {
        let adjusted = config.baselineCRF + complexity.crfAdjustment
        return max(config.minCRF, min(config.maxCRF, adjusted))
    }

    /// Build FFmpeg extra arguments for content-aware encoding.
    ///
    /// - Parameters:
    ///   - config: Content-aware configuration.
    ///   - analysis: The content analysis result.
    ///   - codec: The target video codec.
    /// - Returns: Additional FFmpeg arguments.
    public static func buildEncoderArguments(
        config: ContentAwareConfig,
        analysis: ContentAnalysisResult,
        codec: VideoCodec
    ) -> [String] {
        guard config.enabled else { return [] }

        var args: [String] = []

        // Adjust CRF based on overall complexity
        let crf = adjustedCRF(config: config, complexity: analysis.overallComplexity)

        switch codec {
        case .h265:
            args += ["-crf", "\(crf)"]
            if config.mbtreeEnabled {
                args += ["-x265-params", "rc-lookahead=40:aq-mode=\(config.aqMode)"]
            }
            // Tune for content type
            if let tune = analysis.contentType?.encoderTune {
                args += ["-tune", tune]
            }

        case .h264:
            args += ["-crf", "\(crf)"]
            if config.mbtreeEnabled {
                args += ["-mbtree", "1"]
            }
            if config.aqMode > 0 {
                args += ["-aq-mode", "\(min(config.aqMode, 3))"]
            }
            if let tune = analysis.contentType?.encoderTune {
                args += ["-tune", tune]
            }

        case .av1:
            args += ["-crf", "\(crf)"]
            // Enable AV1 quality features
            args += ["-enable-qm", "1"]
            if analysis.hasFilmGrain && config.filmGrainSynthesis {
                args += ["-film-grain-denoise", "1"]
            }

        case .vp9:
            args += ["-crf", "\(crf)", "-b:v", "0"]
            args += ["-aq-mode", "\(min(config.aqMode, 3))"]

        default:
            args += ["-crf", "\(crf)"]
        }

        return args
    }

    /// Parse signalstats output to extract SI/TI values.
    ///
    /// - Parameter output: FFmpeg stderr output containing signalstats metadata.
    /// - Returns: Array of (SI, TI) pairs.
    public static func parseSignalStats(from output: String) -> [(si: Double, ti: Double)] {
        var results: [(si: Double, ti: Double)] = []

        let lines = output.split(separator: "\n")
        var currentSI: Double?

        for line in lines {
            let str = String(line)

            if str.contains("lavfi.signalstats.SATAVG") || str.contains("lavfi.signalstats.HUEAVG") {
                // These are spatial indicators
                if let range = str.range(of: "=") {
                    let valueStr = str[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    if let val = Double(valueStr) {
                        currentSI = val / 255.0 // Normalize to 0-1
                    }
                }
            }

            if str.contains("lavfi.signalstats.YDIF") {
                if let range = str.range(of: "=") {
                    let valueStr = str[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    if let ti = Double(valueStr) {
                        let si = currentSI ?? 0.5
                        results.append((si: si, ti: min(ti / 30.0, 1.0))) // Normalize TI
                        currentSI = nil
                    }
                }
            }
        }

        return results
    }
}
