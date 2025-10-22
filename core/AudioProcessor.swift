// File: adaptix/core/AudioProcessor.swift
// Purpose: Handles audio processing including multi-track encoding, normalization, language detection, and channel mapping.
// Role: Processes audio streams separately from video, supports multiple codecs and normalization standards.
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

// MARK: - Audio Configuration

/// Configuration for audio encoding
struct AudioEncodingConfig: Codable {
    let codec: AudioCodec
    let bitrate: Int // in kbps
    let sampleRate: Int // in Hz (48000, 44100, etc.)
    let channels: Int // 1, 2, 6, 8
    let channelLayout: String? // stereo, 5.1, 7.1, etc.
    let language: String? // ISO 639 code
    let normalization: NormalizationConfig?
    let outputPath: String

    enum AudioCodec: String, Codable, CaseIterable {
        case aac = "aac"
        case heaac = "libfdk_aac" // HE-AAC
        case mp3 = "libmp3lame"
        case opus = "libopus"
        case vorbis = "libvorbis"
        case ac3 = "ac3"
        case eac3 = "eac3"
        case ac4 = "ac4"
        case flac = "flac"

        var defaultBitrate: Int {
            switch self {
            case .aac, .heaac: return 128
            case .mp3: return 192
            case .opus: return 128
            case .vorbis: return 128
            case .ac3: return 384
            case .eac3: return 384
            case .ac4: return 256
            case .flac: return 0 // Lossless
            }
        }

        var fileExtension: String {
            switch self {
            case .aac, .heaac: return "m4a"
            case .mp3: return "mp3"
            case .opus: return "opus"
            case .vorbis: return "ogg"
            case .ac3: return "ac3"
            case .eac3: return "ec3"
            case .ac4: return "ac4"
            case .flac: return "flac"
            }
        }
    }
}

/// Audio normalization configuration
struct NormalizationConfig: Codable {
    let enabled: Bool
    let standard: NormalizationStandard
    let targetLevel: Double? // in dB or LUFS
    let truePeak: Double? // max true peak in dBTP

    enum NormalizationStandard: String, Codable {
        case ebu128 = "EBU R128" // -23 LUFS
        case atsc85 = "ATSC A/85" // -24 LKFS
        case replaygain = "ReplayGain"
        case peak = "Peak"

        var defaultTarget: Double {
            switch self {
            case .ebu128: return -23.0
            case .atsc85: return -24.0
            case .replaygain: return 89.0 // dB SPL
            case .peak: return -1.0 // dBFS
            }
        }
    }
}

// MARK: - Audio Processor

class AudioProcessor {

    private let mediaProber: MediaProber

    init(mediaProber: MediaProber) {
        self.mediaProber = mediaProber
    }

    // MARK: - Multi-Track Processing

    /// Extracts and processes all audio tracks from a media file
    /// - Parameters:
    ///   - inputPath: Path to input media file
    ///   - outputDirectory: Directory to save processed audio tracks
    ///   - configs: Array of audio encoding configurations (one per output)
    /// - Returns: Array of output file paths
    /// - Throws: Processing errors
    func processAllAudioTracks(inputPath: String,
                              outputDirectory: String,
                              configs: [AudioEncodingConfig]) throws -> [String] {
        // Probe input file
        let mediaInfo = try mediaProber.probe(inputPath)

        guard !mediaInfo.audioStreams.isEmpty else {
            throw AudioProcessingError.noAudioStreams
        }

        var outputPaths: [String] = []

        // Process each audio stream
        for (index, audioStream) in mediaInfo.audioStreams.enumerated() {
            for config in configs {
                let language = audioStream.language ?? "und"
                let outputFileName = generateOutputFileName(
                    index: index,
                    language: language,
                    codec: config.codec,
                    bitrate: config.bitrate
                )
                let outputPath = "\(outputDirectory)/\(outputFileName)"

                let arguments = buildFFmpegArguments(
                    inputPath: inputPath,
                    streamIndex: audioStream.index,
                    config: config,
                    outputPath: outputPath
                )

                // Note: This returns arguments for FFmpegController to execute
                outputPaths.append(outputPath)
            }
        }

        return outputPaths
    }

    /// Generates FFmpeg arguments for audio encoding
    /// - Parameters:
    ///   - inputPath: Input file path
    ///   - streamIndex: Audio stream index to process
    ///   - config: Audio encoding configuration
    ///   - outputPath: Output file path
    /// - Returns: FFmpeg arguments array
    func buildFFmpegArguments(inputPath: String,
                            streamIndex: Int,
                            config: AudioEncodingConfig,
                            outputPath: String) -> [String] {
        var args: [String] = []

        // Input file
        args += ["-i", inputPath]

        // Select specific audio stream
        args += ["-map", "0:a:\(streamIndex)"]

        // Audio codec
        args += ["-c:a", config.codec.rawValue]

        // Bitrate (skip for lossless)
        if config.codec != .flac {
            args += ["-b:a", "\(config.bitrate)k"]
        }

        // Sample rate
        args += ["-ar", "\(config.sampleRate)"]

        // Channels
        args += ["-ac", "\(config.channels)"]

        // Channel layout
        if let layout = config.channelLayout {
            args += ["-channel_layout", layout]
        }

        // Normalization filter
        if let norm = config.normalization, norm.enabled {
            let filterArgs = buildNormalizationFilter(norm)
            args += ["-af", filterArgs]
        }

        // Metadata
        if let language = config.language {
            args += ["-metadata:s:a:0", "language=\(language)"]
        }

        // Codec-specific options
        args += codecSpecificOptions(for: config.codec)

        // Output
        args += [outputPath]

        return args
    }

    // MARK: - Normalization

    /// Builds FFmpeg audio filter for normalization
    private func buildNormalizationFilter(_ config: NormalizationConfig) -> String {
        switch config.standard {
        case .ebu128, .atsc85:
            let target = config.targetLevel ?? config.standard.defaultTarget
            let truePeak = config.truePeak ?? -2.0
            return "loudnorm=I=\(target):TP=\(truePeak):LRA=7"

        case .replaygain:
            return "replaygain"

        case .peak:
            let target = config.targetLevel ?? config.standard.defaultTarget
            return "volume=\(target)dB"
        }
    }

    /// Analyzes audio for normalization (two-pass)
    /// - Parameters:
    ///   - inputPath: Input file path
    ///   - streamIndex: Audio stream index
    ///   - standard: Normalization standard to use
    /// - Returns: Normalization parameters
    func analyzeForNormalization(inputPath: String,
                                streamIndex: Int,
                                standard: NormalizationConfig.NormalizationStandard) throws -> String {
        // First pass: analyze
        var args = [
            "-i", inputPath,
            "-map", "0:a:\(streamIndex)",
            "-af", "loudnorm=I=\(standard.defaultTarget):print_format=json",
            "-f", "null",
            "-"
        ]

        // Execute and parse output
        // This would be executed by FFmpegController
        // Returns JSON with measured_I, measured_LRA, measured_TP, measured_thresh
        return args.joined(separator: " ")
    }

    // MARK: - Codec-Specific Options

    private func codecSpecificOptions(for codec: AudioEncodingConfig.AudioCodec) -> [String] {
        switch codec {
        case .aac:
            return ["-profile:a", "aac_low"]

        case .heaac:
            return ["-profile:a", "aac_he_v2", "-vbr", "5"]

        case .mp3:
            return ["-q:a", "2"] // VBR quality 2 (high quality)

        case .opus:
            return ["-vbr", "on", "-compression_level", "10"]

        case .vorbis:
            return ["-q:a", "6"] // Quality 6 (~192kbps)

        case .ac3:
            return ["-dialnorm", "-31"]

        case .eac3:
            return ["-dialnorm", "-31", "-per_frame_metadata", "1"]

        case .ac4:
            return [] // Depends on specific implementation

        case .flac:
            return ["-compression_level", "8"]
        }
    }

    // MARK: - File Naming

    /// Generates output file name with language code and codec info
    private func generateOutputFileName(index: Int,
                                       language: String,
                                       codec: AudioEncodingConfig.AudioCodec,
                                       bitrate: Int) -> String {
        let codecStr = codec.rawValue.replacingOccurrences(of: "lib", with: "")
        return "audio_\(index)_\(language)_\(codecStr)_\(bitrate)k.\(codec.fileExtension)"
    }

    // MARK: - Language Detection

    /// Attempts to detect language from audio stream metadata
    func detectLanguage(from stream: AudioStreamInfo) -> String? {
        return stream.language ?? stream.tags["language"]
    }

    /// Validates ISO 639 language code
    func validateLanguageCode(_ code: String) -> Bool {
        let validCodes = [
            "en", "en-US", "en-GB", "es", "es-ES", "es-MX", "fr", "fr-FR",
            "de", "it", "pt", "pt-BR", "ru", "ja", "ko", "zh", "zh-CN",
            "ar", "hi", "nl", "pl", "tr", "vi", "th", "und"
        ]
        return validCodes.contains(code)
    }

    // MARK: - Channel Configuration

    /// Suggests optimal channel layout for given channel count
    func suggestChannelLayout(for channels: Int) -> String {
        switch channels {
        case 1: return "mono"
        case 2: return "stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "stereo"
        }
    }

    /// Downmixes multi-channel audio to stereo
    func buildDownmixFilter(from channels: Int) -> String {
        switch channels {
        case 6: // 5.1 to stereo
            return "pan=stereo|FL=FC+0.30*FL+0.30*BL|FR=FC+0.30*FR+0.30*BR"
        case 8: // 7.1 to stereo
            return "pan=stereo|FL=FC+0.30*FL+0.30*BL+0.30*SL|FR=FC+0.30*FR+0.30*BR+0.30*SR"
        default:
            return "aresample"
        }
    }

    // MARK: - Audio Stream Generation for ABR

    /// Generates multiple bitrate versions of an audio track
    /// - Parameters:
    ///   - inputPath: Input file path
    ///   - streamIndex: Audio stream index
    ///   - codec: Target audio codec
    ///   - bitrates: Array of target bitrates in kbps
    ///   - outputDirectory: Output directory
    /// - Returns: Array of encoding configurations
    func generateABRLadder(inputPath: String,
                          streamIndex: Int,
                          codec: AudioEncodingConfig.AudioCodec,
                          bitrates: [Int],
                          language: String?,
                          outputDirectory: String) -> [AudioEncodingConfig] {
        bitrates.map { bitrate in
            let outputFileName = generateOutputFileName(
                index: streamIndex,
                language: language ?? "und",
                codec: codec,
                bitrate: bitrate
            )

            return AudioEncodingConfig(
                codec: codec,
                bitrate: bitrate,
                sampleRate: 48000,
                channels: 2,
                channelLayout: "stereo",
                language: language,
                normalization: nil,
                outputPath: "\(outputDirectory)/\(outputFileName)"
            )
        }
    }

    // MARK: - Validation

    /// Validates audio encoding configuration
    func validateConfig(_ config: AudioEncodingConfig) throws {
        // Check bitrate ranges
        switch config.codec {
        case .opus:
            if config.bitrate < 32 || config.bitrate > 512 {
                throw AudioProcessingError.invalidBitrate("Opus: 32-512 kbps")
            }
        case .aac, .heaac:
            if config.bitrate < 32 || config.bitrate > 320 {
                throw AudioProcessingError.invalidBitrate("AAC: 32-320 kbps")
            }
        case .mp3:
            if config.bitrate < 64 || config.bitrate > 320 {
                throw AudioProcessingError.invalidBitrate("MP3: 64-320 kbps")
            }
        default:
            break
        }

        // Validate sample rate
        let validSampleRates = [8000, 11025, 16000, 22050, 32000, 44100, 48000, 96000]
        if !validSampleRates.contains(config.sampleRate) {
            throw AudioProcessingError.invalidSampleRate
        }

        // Validate channels
        if config.channels < 1 || config.channels > 8 {
            throw AudioProcessingError.invalidChannelCount
        }
    }

    // MARK: - Batch Processing

    /// Creates encoding jobs for all audio tracks
    /// - Parameters:
    ///   - inputPath: Input media file
    ///   - outputConfigs: Array of desired output configurations
    ///   - outputDirectory: Where to save processed audio
    /// - Returns: Array of EncodingJob objects
    func createBatchJobs(inputPath: String,
                        outputConfigs: [AudioEncodingConfig],
                        outputDirectory: String) throws -> [EncodingJob] {
        let mediaInfo = try mediaProber.probe(inputPath)
        var jobs: [EncodingJob] = []

        for (streamIndex, audioStream) in mediaInfo.audioStreams.enumerated() {
            for config in outputConfigs {
                var updatedConfig = config
                updatedConfig.language = audioStream.language ?? config.language

                let arguments = buildFFmpegArguments(
                    inputPath: inputPath,
                    streamIndex: audioStream.index,
                    config: updatedConfig,
                    outputPath: config.outputPath
                )

                let job = EncodingJob(
                    inputPath: inputPath,
                    outputPath: config.outputPath,
                    arguments: arguments
                )

                jobs.append(job)
            }
        }

        return jobs
    }
}

// MARK: - Errors

enum AudioProcessingError: Error, LocalizedError {
    case noAudioStreams
    case invalidBitrate(String)
    case invalidSampleRate
    case invalidChannelCount
    case normalizationFailed
    case codecNotSupported

    var errorDescription: String? {
        switch self {
        case .noAudioStreams:
            return "No audio streams found in input file"
        case .invalidBitrate(let range):
            return "Invalid bitrate. Valid range: \(range)"
        case .invalidSampleRate:
            return "Invalid sample rate. Use: 8000, 11025, 16000, 22050, 32000, 44100, 48000, or 96000 Hz"
        case .invalidChannelCount:
            return "Invalid channel count. Must be between 1 and 8"
        case .normalizationFailed:
            return "Audio normalization failed"
        case .codecNotSupported:
            return "Audio codec not supported by installed FFmpeg"
        }
    }
}

// MARK: - Preset Configurations

extension AudioProcessor {

    /// Creates standard audio configurations for HLS/DASH streaming
    static func createStreamingPresets(language: String?, outputDirectory: String) -> [AudioEncodingConfig] {
        return [
            // High quality AAC
            AudioEncodingConfig(
                codec: .aac,
                bitrate: 192,
                sampleRate: 48000,
                channels: 2,
                channelLayout: "stereo",
                language: language,
                normalization: NormalizationConfig(
                    enabled: true,
                    standard: .ebu128,
                    targetLevel: -23.0,
                    truePeak: -2.0
                ),
                outputPath: "\(outputDirectory)/audio_high.m4a"
            ),
            // Medium quality AAC
            AudioEncodingConfig(
                codec: .aac,
                bitrate: 128,
                sampleRate: 48000,
                channels: 2,
                channelLayout: "stereo",
                language: language,
                normalization: NormalizationConfig(
                    enabled: true,
                    standard: .ebu128,
                    targetLevel: -23.0,
                    truePeak: -2.0
                ),
                outputPath: "\(outputDirectory)/audio_medium.m4a"
            ),
            // Low quality AAC
            AudioEncodingConfig(
                codec: .aac,
                bitrate: 64,
                sampleRate: 44100,
                channels: 2,
                channelLayout: "stereo",
                language: language,
                normalization: NormalizationConfig(
                    enabled: true,
                    standard: .ebu128,
                    targetLevel: -23.0,
                    truePeak: -2.0
                ),
                outputPath: "\(outputDirectory)/audio_low.m4a"
            )
        ]
    }
}
