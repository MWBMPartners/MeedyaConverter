// ============================================================================
// MeedyaConverter — MetadataTagger
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - StreamTagSuggestion

/// A suggested metadata tag for a media stream.
public struct StreamTagSuggestion: Sendable {
    /// The stream index.
    public var streamIndex: Int

    /// The stream type ("audio", "video", "subtitle").
    public var streamType: String

    /// Suggested title for the stream.
    public var suggestedTitle: String?

    /// Suggested language code (ISO 639-2).
    public var suggestedLanguage: String?

    /// Whether this should be the default stream of its type.
    public var isDefault: Bool

    /// Whether this is a forced subtitle stream.
    public var isForced: Bool

    /// Whether this is a hearing-impaired (SDH) subtitle.
    public var isSDH: Bool

    /// Confidence score (0.0–1.0) for the suggestion.
    public var confidence: Double

    public init(
        streamIndex: Int,
        streamType: String,
        suggestedTitle: String? = nil,
        suggestedLanguage: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isSDH: Bool = false,
        confidence: Double = 0.5
    ) {
        self.streamIndex = streamIndex
        self.streamType = streamType
        self.suggestedTitle = suggestedTitle
        self.suggestedLanguage = suggestedLanguage
        self.isDefault = isDefault
        self.isForced = isForced
        self.isSDH = isSDH
        self.confidence = confidence
    }
}

// MARK: - MetadataTagger

/// Generates automatic metadata suggestions for media streams.
///
/// Analyses stream properties (codec, channels, duration) to suggest
/// titles, detect forced subtitles, identify SDH tracks, and set
/// default stream designations.
///
/// Phase 7.6
public struct MetadataTagger: Sendable {

    /// Generate a human-readable stream title from codec and channel information.
    ///
    /// - Parameters:
    ///   - codec: Audio codec name.
    ///   - channels: Channel count.
    ///   - language: Language name (e.g., "English").
    /// - Returns: Suggested title (e.g., "English 5.1 AAC").
    public static func generateAudioTitle(
        codec: String,
        channels: Int,
        language: String? = nil
    ) -> String {
        let channelDesc = channelDescription(for: channels)
        let codecName = codecDisplayName(for: codec)
        var title = ""
        if let lang = language { title += "\(lang) " }
        title += "\(channelDesc) \(codecName)"
        return title.trimmingCharacters(in: .whitespaces)
    }

    /// Generate a subtitle stream title.
    ///
    /// - Parameters:
    ///   - language: Language name.
    ///   - isForced: Whether the subtitle is forced.
    ///   - isSDH: Whether the subtitle is SDH/CC.
    /// - Returns: Suggested title (e.g., "English (Forced)", "English SDH").
    public static func generateSubtitleTitle(
        language: String? = nil,
        isForced: Bool = false,
        isSDH: Bool = false
    ) -> String {
        var title = language ?? "Unknown"
        if isForced { title += " (Forced)" }
        if isSDH { title += " SDH" }
        return title
    }

    /// Detect whether a subtitle stream is likely forced (foreign parts only).
    ///
    /// A subtitle track is considered "forced" if its total duration is
    /// significantly shorter than the video duration, indicating it only
    /// covers foreign language segments.
    ///
    /// - Parameters:
    ///   - subtitleDuration: Total duration of subtitle content in seconds.
    ///   - videoDuration: Total video duration in seconds.
    ///   - threshold: Maximum ratio for forced detection (default 0.5 = 50%).
    /// - Returns: `true` if the subtitle is likely forced.
    public static func isLikelyForced(
        subtitleDuration: TimeInterval,
        videoDuration: TimeInterval,
        threshold: Double = 0.5
    ) -> Bool {
        guard videoDuration > 0 else { return false }
        let ratio = subtitleDuration / videoDuration
        return ratio > 0 && ratio < threshold
    }

    /// Detect whether a subtitle stream is likely SDH (Subtitles for the Deaf/HoH).
    ///
    /// SDH subtitles typically contain sound descriptions in square brackets
    /// or parentheses (e.g., "[door slams]", "(laughing)").
    ///
    /// - Parameter sampleText: A sample of subtitle text to analyse.
    /// - Returns: `true` if the text contains SDH indicators.
    public static func isLikelySDH(sampleText: String) -> Bool {
        // Check for bracketed sound descriptions
        let bracketPattern = "\\[.+?\\]"
        let parenPattern = "\\(.+?\\)"

        let bracketCount = sampleText.matches(of: try! Regex(bracketPattern)).count
        let parenDescCount = sampleText.matches(of: try! Regex(parenPattern)).count

        // SDH indicators: multiple bracketed descriptions
        let descriptionCount = bracketCount + parenDescCount

        // Also check for common SDH keywords
        let sdhKeywords = ["♪", "♫", "music playing", "door closes",
                           "phone rings", "footsteps", "sighs",
                           "laughing", "crying", "screaming"]
        let lowered = sampleText.lowercased()
        let keywordCount = sdhKeywords.filter { lowered.contains($0) }.count

        return descriptionCount >= 3 || keywordCount >= 2
    }

    /// Build FFmpeg metadata arguments for stream tags.
    ///
    /// - Parameter suggestions: Array of stream tag suggestions.
    /// - Returns: FFmpeg argument array for metadata injection.
    public static func buildMetadataArguments(
        suggestions: [StreamTagSuggestion]
    ) -> [String] {
        var args: [String] = []

        for suggestion in suggestions {
            let prefix: String
            switch suggestion.streamType {
            case "audio":
                prefix = "-metadata:s:a:\(suggestion.streamIndex)"
            case "subtitle":
                prefix = "-metadata:s:s:\(suggestion.streamIndex)"
            case "video":
                prefix = "-metadata:s:v:\(suggestion.streamIndex)"
            default:
                continue
            }

            if let title = suggestion.suggestedTitle {
                args += [prefix, "title=\(title)"]
            }

            if let lang = suggestion.suggestedLanguage {
                args += [prefix, "language=\(lang)"]
            }
        }

        // Set disposition flags
        for suggestion in suggestions {
            if suggestion.isDefault || suggestion.isForced {
                let streamSpec: String
                switch suggestion.streamType {
                case "audio": streamSpec = "a:\(suggestion.streamIndex)"
                case "subtitle": streamSpec = "s:\(suggestion.streamIndex)"
                default: continue
                }

                var flags: [String] = []
                if suggestion.isDefault { flags.append("default") }
                if suggestion.isForced { flags.append("forced") }
                if suggestion.isSDH { flags.append("hearing_impaired") }

                args += ["-disposition:\(streamSpec)", flags.joined(separator: "+")]
            }
        }

        return args
    }

    // MARK: - Private

    private static func channelDescription(for channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        case 12: return "7.1.4"
        case 24: return "22.2"
        default: return "\(channels)ch"
        }
    }

    private static func codecDisplayName(for codec: String) -> String {
        switch codec.lowercased() {
        case "aac", "aac_lc": return "AAC"
        case "ac3", "ac-3": return "AC-3"
        case "eac3", "e-ac-3": return "E-AC-3"
        case "truehd": return "TrueHD"
        case "dts": return "DTS"
        case "dts-hd", "dts_hd_ma": return "DTS-HD MA"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        case "mp3": return "MP3"
        case "pcm", "pcm_s16le", "pcm_s24le": return "PCM"
        case "vorbis": return "Vorbis"
        default: return codec.uppercased()
        }
    }
}
