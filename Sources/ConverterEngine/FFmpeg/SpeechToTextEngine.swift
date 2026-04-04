// ============================================================================
// MeedyaConverter — SpeechToTextEngine
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - SpeechToTextProvider

/// Supported speech-to-text backend providers.
public enum SpeechToTextProvider: String, Codable, Sendable, CaseIterable {
    /// OpenAI Whisper (local, via whisper.cpp or Python whisper).
    case whisperLocal = "whisper_local"

    /// OpenAI Whisper API (cloud).
    case whisperAPI = "whisper_api"

    /// Apple Speech Recognition (macOS built-in).
    case appleSpeech = "apple_speech"

    /// Display name.
    public var displayName: String {
        switch self {
        case .whisperLocal: return "Whisper (Local)"
        case .whisperAPI: return "Whisper API (Cloud)"
        case .appleSpeech: return "Apple Speech (macOS)"
        }
    }

    /// Whether this provider requires an API key.
    public var requiresAPIKey: Bool {
        self == .whisperAPI
    }

    /// Whether this provider runs locally.
    public var isLocal: Bool {
        self != .whisperAPI
    }
}

// MARK: - WhisperModel

/// Available Whisper model sizes.
public enum WhisperModel: String, Codable, Sendable, CaseIterable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case large = "large"
    case largeV3 = "large-v3"
    case turbo = "turbo"

    /// Display name.
    public var displayName: String {
        switch self {
        case .tiny: return "Tiny (fastest, least accurate)"
        case .base: return "Base (fast)"
        case .small: return "Small (balanced)"
        case .medium: return "Medium (good quality)"
        case .large: return "Large (best quality)"
        case .largeV3: return "Large v3 (best quality)"
        case .turbo: return "Turbo (fast + good quality)"
        }
    }

    /// Approximate model size in MB.
    public var approximateSizeMB: Int {
        switch self {
        case .tiny: return 75
        case .base: return 142
        case .small: return 466
        case .medium: return 1500
        case .large: return 2900
        case .largeV3: return 2900
        case .turbo: return 800
        }
    }
}

// MARK: - TranscriptionConfig

/// Configuration for speech-to-text transcription.
public struct TranscriptionConfig: Codable, Sendable {
    /// Speech-to-text provider.
    public var provider: SpeechToTextProvider

    /// Whisper model size (for local whisper).
    public var model: WhisperModel

    /// Source language (ISO 639-1 code, e.g., "en", "fr"). Nil = auto-detect.
    public var sourceLanguage: String?

    /// Whether to translate to English (Whisper translate mode).
    public var translateToEnglish: Bool

    /// Output subtitle format.
    public var outputFormat: SubtitleOutputFormat

    /// Maximum segment duration in seconds.
    public var maxSegmentDuration: TimeInterval

    /// Whether to include word-level timestamps.
    public var wordTimestamps: Bool

    /// Number of processing threads (0 = auto).
    public var threads: Int

    /// Whether to detect and label music/singing segments.
    public var detectMusic: Bool

    /// API key for cloud providers.
    public var apiKey: String?

    /// Custom whisper.cpp binary path.
    public var whisperBinaryPath: String?

    /// Custom model file path.
    public var modelPath: String?

    public init(
        provider: SpeechToTextProvider = .whisperLocal,
        model: WhisperModel = .medium,
        sourceLanguage: String? = nil,
        translateToEnglish: Bool = false,
        outputFormat: SubtitleOutputFormat = .srt,
        maxSegmentDuration: TimeInterval = 10.0,
        wordTimestamps: Bool = false,
        threads: Int = 0,
        detectMusic: Bool = true,
        apiKey: String? = nil,
        whisperBinaryPath: String? = nil,
        modelPath: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.sourceLanguage = sourceLanguage
        self.translateToEnglish = translateToEnglish
        self.outputFormat = outputFormat
        self.maxSegmentDuration = maxSegmentDuration
        self.wordTimestamps = wordTimestamps
        self.threads = threads
        self.detectMusic = detectMusic
        self.apiKey = apiKey
        self.whisperBinaryPath = whisperBinaryPath
        self.modelPath = modelPath
    }
}

// MARK: - SubtitleOutputFormat

/// Output format for generated subtitles.
public enum SubtitleOutputFormat: String, Codable, Sendable, CaseIterable {
    case srt = "srt"
    case vtt = "vtt"
    case ass = "ass"
    case json = "json"
    case txt = "txt"

    /// File extension.
    public var fileExtension: String { rawValue }

    /// Display name.
    public var displayName: String {
        switch self {
        case .srt: return "SubRip (SRT)"
        case .vtt: return "WebVTT"
        case .ass: return "Advanced SubStation Alpha (ASS)"
        case .json: return "JSON (structured)"
        case .txt: return "Plain Text"
        }
    }
}

// MARK: - TranscriptionSegment

/// A single transcription segment with timing.
public struct TranscriptionSegment: Codable, Sendable, Identifiable {
    public let id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String
    public var confidence: Double?
    public var language: String?
    public var isMusic: Bool
    public var speaker: String?

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        confidence: Double? = nil,
        language: String? = nil,
        isMusic: Bool = false,
        speaker: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
        self.language = language
        self.isMusic = isMusic
        self.speaker = speaker
    }

    /// Duration of this segment.
    public var duration: TimeInterval { endTime - startTime }

    /// Formatted start time for SRT (HH:MM:SS,mmm).
    public var formattedStartTime: String {
        formatSRTTimestamp(startTime)
    }

    /// Formatted end time for SRT (HH:MM:SS,mmm).
    public var formattedEndTime: String {
        formatSRTTimestamp(endTime)
    }

    private func formatSRTTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let millis = Int((time.truncatingRemainder(dividingBy: 1.0)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }
}

// MARK: - TranscriptionResult

/// Complete transcription result.
public struct TranscriptionResult: Codable, Sendable {
    public var segments: [TranscriptionSegment]
    public var detectedLanguage: String?
    public var duration: TimeInterval
    public var provider: SpeechToTextProvider
    public var model: String?

    public init(
        segments: [TranscriptionSegment],
        detectedLanguage: String? = nil,
        duration: TimeInterval,
        provider: SpeechToTextProvider,
        model: String? = nil
    ) {
        self.segments = segments
        self.detectedLanguage = detectedLanguage
        self.duration = duration
        self.provider = provider
        self.model = model
    }

    /// Total number of segments.
    public var segmentCount: Int { segments.count }

    /// Full text concatenation.
    public var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }

    /// Music segments only.
    public var musicSegments: [TranscriptionSegment] {
        segments.filter(\.isMusic)
    }

    /// Speech segments only.
    public var speechSegments: [TranscriptionSegment] {
        segments.filter { !$0.isMusic }
    }
}

// MARK: - SpeechToTextEngine

/// Builds command-line arguments for speech-to-text transcription using
/// Whisper and other backends.
///
/// Handles audio extraction from video, transcription invocation, and
/// subtitle file generation with support for music/singing detection.
///
/// Phase 18.1
public struct SpeechToTextEngine: Sendable {

    // MARK: - Audio Extraction

    /// Build FFmpeg arguments to extract audio for transcription.
    ///
    /// Whisper expects 16kHz mono WAV input for optimal performance.
    ///
    /// - Parameters:
    ///   - inputPath: Source media file.
    ///   - outputPath: Output WAV file path.
    ///   - streamIndex: Audio stream index (default 0).
    /// - Returns: FFmpeg argument array.
    public static func buildAudioExtractionArguments(
        inputPath: String,
        outputPath: String,
        streamIndex: Int = 0
    ) -> [String] {
        return [
            "-i", inputPath,
            "-map", "0:a:\(streamIndex)",
            "-ac", "1",           // Mono
            "-ar", "16000",       // 16kHz
            "-acodec", "pcm_s16le",
            "-f", "wav",
            "-y",
            outputPath,
        ]
    }

    // MARK: - Whisper.cpp Arguments

    /// Build whisper.cpp CLI arguments for transcription.
    ///
    /// - Parameters:
    ///   - config: Transcription configuration.
    ///   - audioPath: Path to the extracted WAV audio.
    ///   - outputPath: Base output path (without extension).
    /// - Returns: Argument array for the whisper binary.
    public static func buildWhisperArguments(
        config: TranscriptionConfig,
        audioPath: String,
        outputPath: String
    ) -> [String] {
        var args: [String] = []

        // Model
        if let modelPath = config.modelPath {
            args += ["-m", modelPath]
        } else {
            args += ["-m", "models/ggml-\(config.model.rawValue).bin"]
        }

        // Input audio
        args += ["-f", audioPath]

        // Output format
        switch config.outputFormat {
        case .srt:
            args += ["--output-srt"]
        case .vtt:
            args += ["--output-vtt"]
        case .json:
            args += ["--output-json"]
        case .txt:
            args += ["--output-txt"]
        case .ass:
            args += ["--output-srt"] // Convert SRT to ASS post-process
        }

        // Output file
        args += ["-of", outputPath]

        // Language
        if let lang = config.sourceLanguage {
            args += ["-l", lang]
        }

        // Translate to English
        if config.translateToEnglish {
            args.append("--translate")
        }

        // Word timestamps
        if config.wordTimestamps {
            args.append("--word-timestamps")
        }

        // Threads
        if config.threads > 0 {
            args += ["-t", "\(config.threads)"]
        }

        // Max segment length
        args += ["--max-len", "\(Int(config.maxSegmentDuration))"]

        return args
    }

    // MARK: - Whisper API Arguments

    /// Build a curl command for the Whisper API transcription.
    ///
    /// - Parameters:
    ///   - config: Transcription configuration.
    ///   - audioPath: Path to the audio file.
    /// - Returns: curl argument array.
    public static func buildWhisperAPIArguments(
        config: TranscriptionConfig,
        audioPath: String
    ) -> [String] {
        var args = [
            "-X", "POST",
            "https://api.openai.com/v1/audio/transcriptions",
            "-H", "Authorization: Bearer \(config.apiKey ?? "")",
            "-F", "file=@\(audioPath)",
            "-F", "model=whisper-1",
        ]

        if let lang = config.sourceLanguage {
            args += ["-F", "language=\(lang)"]
        }

        let responseFormat: String
        switch config.outputFormat {
        case .srt: responseFormat = "srt"
        case .vtt: responseFormat = "vtt"
        case .json: responseFormat = "verbose_json"
        case .txt: responseFormat = "text"
        case .ass: responseFormat = "srt"
        }
        args += ["-F", "response_format=\(responseFormat)"]

        if config.wordTimestamps && config.outputFormat == .json {
            args += ["-F", "timestamp_granularities[]=word"]
        }

        return args
    }

    // MARK: - SRT Generation

    /// Generate an SRT subtitle file from transcription segments.
    ///
    /// - Parameter segments: Transcription segments.
    /// - Returns: SRT-formatted string.
    public static func generateSRT(from segments: [TranscriptionSegment]) -> String {
        var output = ""
        for (index, segment) in segments.enumerated() {
            output += "\(index + 1)\n"
            output += "\(segment.formattedStartTime) --> \(segment.formattedEndTime)\n"
            if segment.isMusic {
                output += "\u{266B} \(segment.text) \u{266B}\n"
            } else {
                output += "\(segment.text)\n"
            }
            output += "\n"
        }
        return output
    }

    /// Generate a WebVTT subtitle file from transcription segments.
    ///
    /// - Parameter segments: Transcription segments.
    /// - Returns: WebVTT-formatted string.
    public static func generateVTT(from segments: [TranscriptionSegment]) -> String {
        var output = "WEBVTT\n\n"
        for (index, segment) in segments.enumerated() {
            output += "\(index + 1)\n"
            let start = segment.formattedStartTime.replacingOccurrences(of: ",", with: ".")
            let end = segment.formattedEndTime.replacingOccurrences(of: ",", with: ".")
            output += "\(start) --> \(end)\n"
            if segment.isMusic {
                output += "\u{266B} \(segment.text) \u{266B}\n"
            } else {
                output += "\(segment.text)\n"
            }
            output += "\n"
        }
        return output
    }

    // MARK: - Whisper Output Parsing

    /// Parse whisper.cpp JSON output into transcription segments.
    ///
    /// - Parameter jsonData: JSON output from whisper.
    /// - Returns: Array of transcription segments.
    public static func parseWhisperJSON(_ jsonData: Data) -> [TranscriptionSegment]? {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let transcription = json["transcription"] as? [[String: Any]] else {
            return nil
        }

        return transcription.compactMap { entry -> TranscriptionSegment? in
            guard let offsetsObj = entry["offsets"] as? [String: Any],
                  let fromMs = offsetsObj["from"] as? Int,
                  let toMs = offsetsObj["to"] as? Int,
                  let text = entry["text"] as? String else {
                return nil
            }

            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let isMusic = trimmed.hasPrefix("[") && trimmed.hasSuffix("]") &&
                          (trimmed.lowercased().contains("music") ||
                           trimmed.lowercased().contains("singing"))

            return TranscriptionSegment(
                startTime: Double(fromMs) / 1000.0,
                endTime: Double(toMs) / 1000.0,
                text: trimmed,
                isMusic: isMusic
            )
        }
    }

    /// Parse an SRT file into transcription segments.
    ///
    /// - Parameter srtContent: SRT file content.
    /// - Returns: Array of transcription segments.
    public static func parseSRT(_ srtContent: String) -> [TranscriptionSegment] {
        var segments: [TranscriptionSegment] = []
        let blocks = srtContent.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count >= 3 else { continue }

            // Parse timestamp line (e.g., "00:00:01,000 --> 00:00:05,000")
            let timeLine = String(lines[1])
            let timeParts = timeLine.split(separator: " --> ")
            guard timeParts.count == 2 else { continue }

            guard let start = parseSRTTimestamp(String(timeParts[0])),
                  let end = parseSRTTimestamp(String(timeParts[1])) else { continue }

            let text = lines[2...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let isMusic = text.contains("\u{266B}") ||
                          (text.hasPrefix("[") && text.hasSuffix("]"))

            segments.append(TranscriptionSegment(
                startTime: start,
                endTime: end,
                text: text,
                isMusic: isMusic
            ))
        }

        return segments
    }

    /// Parse an SRT timestamp string to seconds.
    private static func parseSRTTimestamp(_ str: String) -> TimeInterval? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 3 else { return nil }

        guard let hours = Double(parts[0]) else { return nil }
        guard let minutes = Double(parts[1]) else { return nil }

        let secParts = parts[2].replacingOccurrences(of: ",", with: ".").split(separator: ".")
        guard secParts.count >= 1, let seconds = Double(secParts[0]) else { return nil }
        let millis = secParts.count > 1 ? (Double(secParts[1]) ?? 0) / 1000.0 : 0

        return hours * 3600 + minutes * 60 + seconds + millis
    }
}
