// ============================================================================
// MeedyaConverter — ProfileSuggester (Issue #271)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ProfileSuggestion

/// A single profile recommendation with its associated reasoning and confidence.
///
/// Suggestions are returned ranked by relevance so the UI can present the top 3–5
/// options as cards or badges. The `reason` field provides human-readable text
/// explaining *why* this profile suits the source material.
public struct ProfileSuggestion: Sendable, Identifiable {

    /// Unique identifier for this suggestion.
    public let id: UUID

    /// The recommended encoding profile.
    public let profile: EncodingProfile

    /// Human-readable explanation of why this profile was suggested.
    public let reason: String

    /// Confidence score from 0.0 (low) to 1.0 (high) indicating how well
    /// this profile matches the source material.
    public let confidence: Double

    /// Category label for UI grouping (e.g., "Best Quality", "Smallest Size", "Fastest").
    public let category: String

    public init(
        id: UUID = UUID(),
        profile: EncodingProfile,
        reason: String,
        confidence: Double,
        category: String
    ) {
        self.id = id
        self.profile = profile
        self.reason = reason
        self.confidence = confidence.clamped(to: 0.0...1.0)
        self.category = category
    }
}

// MARK: - ProfileSuggester

/// Analyses source media files and recommends the most appropriate encoding profiles.
///
/// The suggester evaluates properties of the source `MediaFile` — resolution, HDR
/// format, audio channel layout, file size, duration, and subtitle presence — then
/// scores each available profile against those characteristics. The top-ranked
/// suggestions are returned with confidence scores and explanations.
///
/// Usage:
/// ```swift
/// let suggestions = ProfileSuggester.suggest(for: mediaFile, profiles: allProfiles)
/// // suggestions[0].profile.name  → "4K HDR Master"
/// // suggestions[0].confidence    → 0.95
/// // suggestions[0].reason        → "Source is 4K HDR10 — this profile preserves HDR metadata"
/// ```
///
/// Phase 7 / Issue #271
public struct ProfileSuggester: Sendable {

    // MARK: - Constants

    /// Maximum number of suggestions to return.
    private static let maxSuggestions = 5

    /// File size threshold (in bytes) above which the file is considered "very large" (5 GB).
    private static let veryLargeFileThreshold: UInt64 = 5_000_000_000

    /// Duration threshold (in seconds) below which the file is a "short clip" (60 seconds).
    private static let shortClipThreshold: TimeInterval = 60.0

    // MARK: - Public API

    /// Analyse a media file and return ranked profile suggestions.
    ///
    /// - Parameters:
    ///   - file: The probed source media file to analyse.
    ///   - profiles: All available encoding profiles (built-in + user-created).
    /// - Returns: Up to 5 `ProfileSuggestion` values sorted by descending confidence.
    public static func suggest(
        for file: MediaFile,
        profiles: [EncodingProfile]
    ) -> [ProfileSuggestion] {
        // Gather source characteristics once for efficiency.
        let characteristics = SourceCharacteristics(from: file)

        // Score each profile and collect suggestions.
        var suggestions: [ProfileSuggestion] = profiles.compactMap { profile in
            scoreProfile(profile, for: characteristics)
        }

        // Sort by confidence (descending), then by category priority.
        suggestions.sort { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return categoryPriority(lhs.category) < categoryPriority(rhs.category)
        }

        // Return the top N suggestions.
        return Array(suggestions.prefix(maxSuggestions))
    }

    // MARK: - Source Characteristics

    /// Extracted properties of the source file used for scoring.
    private struct SourceCharacteristics {
        let hasVideo: Bool
        let hasAudio: Bool
        let isAudioOnly: Bool
        let width: Int
        let height: Int
        let is4K: Bool
        let is1080p: Bool
        let is720p: Bool
        let isHDR: Bool
        let hdrFormats: [HDRFormat]
        let hasSubtitles: Bool
        let hasSurroundAudio: Bool
        let audioChannelCount: Int
        let fileSize: UInt64
        let isVeryLargeFile: Bool
        let duration: TimeInterval
        let isShortClip: Bool

        init(from file: MediaFile) {
            let primaryVideo = file.primaryVideoStream
            let primaryAudio = file.primaryAudioStream

            hasVideo = file.hasVideo
            hasAudio = file.hasAudio
            isAudioOnly = !file.hasVideo && file.hasAudio

            width = primaryVideo?.width ?? 0
            height = primaryVideo?.height ?? 0
            is4K = height >= 2160 || width >= 3840
            is1080p = (height >= 1080 && height < 2160) || (width >= 1920 && width < 3840)
            is720p = (height >= 720 && height < 1080) || (width >= 1280 && width < 1920)

            isHDR = file.hasHDR
            hdrFormats = primaryVideo?.hdrFormats ?? []

            hasSubtitles = !file.subtitleStreams.isEmpty

            let channelCount = primaryAudio?.channelLayout?.channelCount ?? 0
            audioChannelCount = channelCount
            hasSurroundAudio = channelCount > 2

            fileSize = file.fileSize ?? 0
            isVeryLargeFile = fileSize > ProfileSuggester.veryLargeFileThreshold

            duration = file.duration ?? 0
            isShortClip = duration > 0 && duration <= ProfileSuggester.shortClipThreshold
        }
    }

    // MARK: - Scoring

    /// Score a single profile against the source characteristics.
    ///
    /// Returns `nil` if the profile scores below the minimum threshold.
    private static func scoreProfile(
        _ profile: EncodingProfile,
        for source: SourceCharacteristics
    ) -> ProfileSuggestion? {
        var score: Double = 0.0
        var reasons: [String] = []
        var category = "General"

        // --- Audio-only source ---
        if source.isAudioOnly {
            if profile.videoPassthrough || profile.videoCodec == nil {
                score += 0.5
                reasons.append("Audio-only source — no video re-encoding needed")
                category = "Best Match"
            } else {
                // Video encoding profiles are poor matches for audio-only sources.
                return nil
            }

            if profile.containerFormat == .m4a || profile.containerFormat == .ogg ||
               profile.containerFormat == .mka {
                score += 0.3
                reasons.append("Audio container format matches audio-only source")
            }
        }

        // --- 4K HDR source ---
        if source.is4K && source.isHDR {
            if profile.preserveHDR && !profile.toneMapToSDR {
                score += 0.4
                reasons.append("Preserves HDR metadata for 4K HDR source")
                category = "Best Quality"
            }

            if (profile.outputWidth == nil || profile.outputWidth ?? 0 >= 3840) &&
               (profile.outputHeight == nil || profile.outputHeight ?? 0 >= 2160) {
                score += 0.3
                reasons.append("Maintains native 4K resolution")
            } else if profile.outputHeight != nil && (profile.outputHeight ?? 0) < 2160 {
                // Downscaling 4K — lower score but can be useful for size reduction.
                score += 0.1
                reasons.append("Downscales 4K source for smaller output")
                category = "Smallest Size"
            }

            if profile.pixelFormat == "yuv420p10le" {
                score += 0.1
                reasons.append("10-bit colour depth preserves HDR gradients")
            }
        }

        // --- 1080p SDR source ---
        if source.is1080p && !source.isHDR {
            if (profile.outputWidth == nil || profile.outputWidth == 1920) &&
               (profile.outputHeight == nil || profile.outputHeight == 1080) {
                score += 0.3
                reasons.append("Matches source 1080p resolution")
            }

            if !profile.preserveHDR || !profile.toneMapToSDR {
                score += 0.1
                reasons.append("SDR workflow suitable for SDR source")
            }

            if profile.videoCodec == .h265 || profile.videoCodec == .h264 {
                score += 0.2
                reasons.append("Widely compatible codec for web/streaming delivery")
                category = "Best Match"
            }
        }

        // --- Very large file ---
        if source.isVeryLargeFile {
            if profile.useHardwareEncoding {
                score += 0.25
                reasons.append("Hardware encoding for faster processing of large file")
                category = "Fastest"
            }

            if profile.videoCodec == .h265 || profile.videoCodec == .av1 {
                score += 0.15
                reasons.append("Efficient codec reduces output size significantly")
                if category == "General" { category = "Smallest Size" }
            }
        }

        // --- Short clip ---
        if source.isShortClip {
            if profile.videoPreset == "fast" || profile.videoPreset == "veryfast" ||
               profile.videoPreset == "ultrafast" || profile.useHardwareEncoding {
                score += 0.2
                reasons.append("Fast preset ideal for short clips")
                category = "Fastest"
            }

            // Even slow presets are acceptable for short clips since total time is small.
            score += 0.05
        }

        // --- Subtitle presence ---
        if source.hasSubtitles {
            if profile.containerFormat == .mkv || profile.containerFormat == .mka {
                score += 0.15
                reasons.append("MKV container supports full subtitle passthrough")
            }

            if profile.subtitlePassthrough {
                score += 0.1
                reasons.append("Preserves existing subtitle tracks")
            }
        }

        // --- Surround audio ---
        if source.hasSurroundAudio {
            if profile.audioPassthrough {
                score += 0.2
                reasons.append("Passes through surround audio without re-encoding")
                if category == "General" { category = "Best Quality" }
            } else if let channels = profile.audioChannels, channels >= source.audioChannelCount {
                score += 0.15
                reasons.append("Preserves multi-channel audio layout")
            } else if profile.audioChannels == nil {
                // No channel restriction — will match source.
                score += 0.1
                reasons.append("Audio channel count follows source")
            }

            if profile.containerFormat == .mkv || profile.containerFormat == .mka {
                score += 0.05
                reasons.append("Container supports advanced audio codecs")
            }
        }

        // --- Codec efficiency bonus ---
        if profile.videoCodec == .h265 {
            score += 0.05
        } else if profile.videoCodec == .av1 {
            score += 0.08
        }

        // --- Minimum threshold ---
        guard score >= 0.15 else { return nil }

        // Normalise score to 0–1 range (max possible is approximately 1.5).
        let normalisedConfidence = min(score / 1.2, 1.0)

        let combinedReason = reasons.isEmpty
            ? "General-purpose profile"
            : reasons.joined(separator: ". ") + "."

        return ProfileSuggestion(
            profile: profile,
            reason: combinedReason,
            confidence: normalisedConfidence,
            category: category
        )
    }

    // MARK: - Category Priority

    /// Assign a sort priority to suggestion categories for stable ordering.
    private static func categoryPriority(_ category: String) -> Int {
        switch category {
        case "Best Quality": return 0
        case "Best Match": return 1
        case "Smallest Size": return 2
        case "Fastest": return 3
        default: return 4
        }
    }
}

// MARK: - Double Clamping Extension

private extension Double {
    /// Clamp this value to the given closed range.
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
