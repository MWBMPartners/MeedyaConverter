// ============================================================================
// MeedyaConverter — FFmpegArgumentBuilder
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FFmpegArgumentBuilder

/// Builds FFmpeg command-line arguments from encoding configuration.
///
/// The argument builder translates high-level encoding settings (codec,
/// quality, container, stream selection) into the specific FFmpeg CLI
/// arguments needed to execute the encode.
///
/// Usage:
/// ```swift
/// var builder = FFmpegArgumentBuilder()
/// builder.inputURL = sourceFile
/// builder.outputURL = outputFile
/// builder.videoCodec = .h265
/// builder.videoCRF = 22
/// builder.audioCodec = .aacLC
/// builder.audioBitrate = 160_000
/// let args = builder.build()
/// // ["-i", "/path/source.mkv", "-c:v", "libx265", "-crf", "22",
/// //  "-c:a", "aac", "-b:a", "160k", "/path/output.mp4"]
/// ```
public struct FFmpegArgumentBuilder: Sendable {

    // MARK: - Input/Output

    /// The input file URL.
    public var inputURL: URL?

    /// The output file URL.
    public var outputURL: URL?

    /// Additional input files (for multi-input operations).
    public var additionalInputs: [URL] = []

    // MARK: - Video Settings

    /// The video codec to use for encoding. Nil means copy (passthrough).
    public var videoCodec: VideoCodec?

    /// Whether to passthrough (copy) the video stream without re-encoding.
    public var videoPassthrough: Bool = false

    /// Constant Rate Factor for quality-based VBR encoding.
    /// Lower values = higher quality. Typical range: 18-28 for H.265.
    public var videoCRF: Int?

    /// Quantization Parameter for hardware encoders.
    public var videoQP: Int?

    /// Target video bitrate in bits per second (for CBR/CVBR modes).
    public var videoBitrate: Int?

    /// Maximum video bitrate in bits per second (for CVBR/VBV buffering).
    public var videoMaxBitrate: Int?

    /// VBV buffer size in bits (for CVBR mode, typically 2x maxBitrate).
    public var videoBufferSize: Int?

    /// Output video width in pixels. Nil means match source.
    public var videoWidth: Int?

    /// Output video height in pixels. Nil means match source.
    public var videoHeight: Int?

    /// Output frame rate. Nil means match source.
    public var videoFrameRate: Double?

    /// Pixel format (e.g., "yuv420p", "yuv420p10le").
    public var pixelFormat: String?

    /// Video encoder preset (e.g., "medium", "slow", "veryslow" for x265).
    public var videoPreset: String?

    /// Video encoder tune parameter (e.g., "film", "animation", "grain").
    public var videoTune: String?

    /// Video encoder profile (e.g., "main", "main10", "high").
    public var videoProfile: String?

    /// Video encoder level (e.g., "4.1", "5.1").
    public var videoLevel: String?

    /// Whether to use hardware encoding (VideoToolbox on macOS).
    public var useHardwareEncoding: Bool = false

    /// Keyframe interval in seconds (for adaptive streaming GOP alignment).
    public var keyframeInterval: Double?

    /// Number of encoding passes (1 or 2).
    public var encodingPasses: Int = 1

    /// Path to the multipass log file (for two-pass encoding).
    public var multipassLogPath: String?

    /// Current pass number (1 or 2) when doing multi-pass encoding.
    public var currentPass: Int?

    // MARK: - Audio Settings

    /// The audio codec to use for encoding. Nil means copy (passthrough).
    public var audioCodec: AudioCodec?

    /// Whether to passthrough (copy) the audio stream without re-encoding.
    public var audioPassthrough: Bool = false

    /// Audio bitrate in bits per second.
    public var audioBitrate: Int?

    /// Audio sample rate in Hz (e.g., 44100, 48000). Nil means match source.
    public var audioSampleRate: Int?

    /// Number of audio channels. Nil means match source.
    public var audioChannels: Int?

    /// Audio channel layout string (e.g., "stereo", "5.1").
    public var audioChannelLayout: String?

    // MARK: - Subtitle Settings

    /// Whether to passthrough (copy) subtitle streams.
    public var subtitlePassthrough: Bool = false

    /// Whether to disable all subtitle streams in output.
    public var disableSubtitles: Bool = false

    // MARK: - Stream Selection

    /// Specific video stream index to use from source. Nil means default.
    public var videoStreamIndex: Int?

    /// Specific audio stream index to use from source. Nil means default.
    public var audioStreamIndex: Int?

    /// Specific subtitle stream index to use. Nil means default.
    public var subtitleStreamIndex: Int?

    /// Whether to map all streams from source (not just default).
    public var mapAllStreams: Bool = false

    // MARK: - Container / Output

    /// Output container format. Inferred from output extension if nil.
    public var containerFormat: ContainerFormat?

    /// Whether to overwrite existing output file without prompting.
    /// Always true in MeedyaConverter (we handle confirmation in the UI).
    public var overwriteOutput: Bool = true

    /// Whether to copy all metadata from the source file to the output.
    /// Enabled by default so passthrough preserves track names, language tags,
    /// and all other stream/container metadata unless overridden in the UI.
    public var copySourceMetadata: Bool = true

    // MARK: - Metadata

    /// Metadata key-value pairs to write to the output file.
    public var metadata: [String: String] = [:]

    /// Per-stream metadata (keyed by stream specifier like "s:a:0").
    public var streamMetadata: [String: [String: String]] = [:]

    // MARK: - Filters

    /// Video filter chain string (e.g., "scale=1920:1080,tonemap=hable").
    public var videoFilterChain: String?

    /// Audio filter chain string (e.g., "loudnorm=I=-14").
    public var audioFilterChain: String?

    // MARK: - Codec Metadata Preservation (Phase 3.16a)

    /// Preserve codec-specific metadata when re-encoding within the same codec family.
    /// When true and the source/output audio codecs match, dialog normalization,
    /// dynamic range, surround mode flags, etc. are carried through.
    public var preserveCodecMetadata: Bool = true

    // MARK: - Aspect Ratio (Phase 3.16b)

    /// Display Aspect Ratio override (e.g., "16:9", "2.35:1").
    /// When set, applies -aspect to the output. When nil, aspect is copied from source.
    public var displayAspectRatio: String?

    // MARK: - Additional Arguments

    /// Extra FFmpeg arguments to append (for advanced use cases).
    public var extraArguments: [String] = []

    // MARK: - Initialiser

    public init() {}

    // MARK: - Build

    /// Build the complete FFmpeg argument array.
    ///
    /// Returns the arguments to pass to FFmpeg (not including the binary path itself).
    /// Arguments are ordered: global options → inputs → codec/quality → filters → output.
    public func build() -> [String] {
        var args: [String] = []

        // --- Global options ---
        if overwriteOutput {
            args.append("-y")
        }

        // Suppress interactive prompts
        args.append("-nostdin")

        // --- Input files ---
        if let input = inputURL {
            args.append(contentsOf: ["-i", input.path])
        }

        for additionalInput in additionalInputs {
            args.append(contentsOf: ["-i", additionalInput.path])
        }

        // --- Stream mapping ---
        args.append(contentsOf: buildStreamMapping())

        // --- Source metadata passthrough ---
        // Copy all metadata (track names, language, title, etc.) and chapters
        // from the source file by default. Per-stream overrides from the UI
        // are applied separately via buildMetadataArguments().
        if copySourceMetadata {
            args.append(contentsOf: ["-map_metadata", "0"])
            args.append(contentsOf: ["-map_chapters", "0"])
        }

        // --- Video codec and quality ---
        args.append(contentsOf: buildVideoArguments())

        // --- Audio codec and quality ---
        args.append(contentsOf: buildAudioArguments())

        // --- Subtitle handling ---
        args.append(contentsOf: buildSubtitleArguments())

        // --- Video filters ---
        if let vf = videoFilterChain, !vf.isEmpty {
            args.append(contentsOf: ["-vf", vf])
        }

        // --- Audio filters ---
        if let af = audioFilterChain, !af.isEmpty {
            args.append(contentsOf: ["-af", af])
        }

        // --- Display aspect ratio override ---
        if let dar = displayAspectRatio, !dar.isEmpty {
            args.append(contentsOf: ["-aspect", dar])
        }

        // --- Metadata ---
        args.append(contentsOf: buildMetadataArguments())

        // --- Container format override ---
        if let format = containerFormat {
            args.append(contentsOf: ["-f", ffmpegFormatName(for: format)])
        }

        // --- Extra arguments ---
        args.append(contentsOf: extraArguments)

        // --- Output file ---
        if let output = outputURL {
            // For two-pass first pass, output to /dev/null
            if encodingPasses == 2 && currentPass == 1 {
                args.append("/dev/null")
            } else {
                args.append(output.path)
            }
        }

        return args
    }

    // MARK: - Private Builders

    /// Build stream mapping arguments (-map).
    private func buildStreamMapping() -> [String] {
        var args: [String] = []

        if mapAllStreams {
            // Map all streams from first input
            args.append(contentsOf: ["-map", "0"])
        } else {
            // Map specific streams
            if let vi = videoStreamIndex {
                args.append(contentsOf: ["-map", "0:v:\(vi)"])
            } else if !disableSubtitles {
                // Default: map first video and first audio
                args.append(contentsOf: ["-map", "0:v?"])
            }

            if let ai = audioStreamIndex {
                args.append(contentsOf: ["-map", "0:a:\(ai)"])
            } else {
                args.append(contentsOf: ["-map", "0:a?"])
            }

            if subtitlePassthrough {
                if let si = subtitleStreamIndex {
                    args.append(contentsOf: ["-map", "0:s:\(si)"])
                } else {
                    args.append(contentsOf: ["-map", "0:s?"])
                }
            }
        }

        return args
    }

    /// Build video codec and quality arguments.
    private func buildVideoArguments() -> [String] {
        var args: [String] = []

        if videoPassthrough {
            // Passthrough — copy video without re-encoding
            args.append(contentsOf: ["-c:v", "copy"])
            return args
        }

        guard let codec = videoCodec else {
            // No video codec specified and not passthrough — disable video
            args.append("-vn")
            return args
        }

        // Select encoder
        let encoderName: String
        if useHardwareEncoding && codec.supportsVideoToolbox {
            // Use VideoToolbox hardware encoder
            switch codec {
            case .h264: encoderName = "h264_videotoolbox"
            case .h265: encoderName = "hevc_videotoolbox"
            case .prores: encoderName = "prores_videotoolbox"
            case .av1: encoderName = "av1_videotoolbox"
            default: encoderName = codec.ffmpegEncoder ?? "libx264"
            }
        } else {
            encoderName = codec.ffmpegEncoder ?? "libx264"
        }

        args.append(contentsOf: ["-c:v", encoderName])

        // Quality settings
        if let crf = videoCRF, !useHardwareEncoding {
            // CRF mode (software encoders)
            args.append(contentsOf: ["-crf", "\(crf)"])
        } else if let qp = videoQP ?? videoCRF, useHardwareEncoding {
            // QP mode (hardware encoders)
            args.append(contentsOf: ["-q:v", "\(qp)"])
        }

        if let bitrate = videoBitrate {
            args.append(contentsOf: ["-b:v", formatBitrate(bitrate)])
        }

        if let maxBr = videoMaxBitrate {
            args.append(contentsOf: ["-maxrate", formatBitrate(maxBr)])
        }

        if let bufSize = videoBufferSize {
            args.append(contentsOf: ["-bufsize", formatBitrate(bufSize)])
        }

        // Resolution
        if let w = videoWidth, let h = videoHeight {
            args.append(contentsOf: ["-s", "\(w)x\(h)"])
        }

        // Frame rate
        if let fps = videoFrameRate {
            args.append(contentsOf: ["-r", String(format: "%.3f", fps)])
        }

        // Pixel format
        if let pf = pixelFormat {
            args.append(contentsOf: ["-pix_fmt", pf])
        }

        // Encoder preset
        if let preset = videoPreset {
            args.append(contentsOf: ["-preset", preset])
        }

        // Encoder tune
        if let tune = videoTune {
            args.append(contentsOf: ["-tune", tune])
        }

        // Encoder profile
        if let profile = videoProfile {
            args.append(contentsOf: ["-profile:v", profile])
        }

        // Encoder level
        if let level = videoLevel {
            args.append(contentsOf: ["-level", level])
        }

        // Keyframe interval (GOP size for adaptive streaming)
        if let kfInterval = keyframeInterval, let fps = videoFrameRate {
            let gopSize = Int(kfInterval * fps)
            args.append(contentsOf: ["-g", "\(gopSize)"])
            args.append(contentsOf: ["-keyint_min", "\(gopSize)"])
        }

        // Two-pass encoding
        if encodingPasses == 2 {
            args.append(contentsOf: ["-pass", "\(currentPass ?? 1)"])
            if let logPath = multipassLogPath {
                args.append(contentsOf: ["-passlogfile", logPath])
            }
            // First pass: disable audio, use fast analysis
            if currentPass == 1 {
                args.append("-an")
            }
        }

        return args
    }

    /// Build audio codec and quality arguments.
    private func buildAudioArguments() -> [String] {
        var args: [String] = []

        // Skip audio in first pass of two-pass encoding
        if encodingPasses == 2 && currentPass == 1 {
            return ["-an"]
        }

        if audioPassthrough {
            args.append(contentsOf: ["-c:a", "copy"])
            return args
        }

        guard let codec = audioCodec else {
            // No audio codec specified — disable audio
            args.append("-an")
            return args
        }

        // Select encoder
        guard let encoderName = codec.ffmpegEncoder else {
            // Codec cannot be encoded by FFmpeg — fall back to passthrough
            args.append(contentsOf: ["-c:a", "copy"])
            return args
        }

        args.append(contentsOf: ["-c:a", encoderName])

        // Bitrate
        if let br = audioBitrate {
            args.append(contentsOf: ["-b:a", formatBitrate(br)])
        }

        // Sample rate
        if let sr = audioSampleRate {
            args.append(contentsOf: ["-ar", "\(sr)"])
        }

        // Channel count
        if let ch = audioChannels {
            args.append(contentsOf: ["-ac", "\(ch)"])
        }

        // Channel layout
        if let layout = audioChannelLayout {
            args.append(contentsOf: ["-channel_layout", layout])
        }

        return args
    }

    /// Build subtitle handling arguments.
    private func buildSubtitleArguments() -> [String] {
        if disableSubtitles {
            return ["-sn"]
        }

        if subtitlePassthrough {
            return ["-c:s", "copy"]
        }

        // Default: no subtitle processing (subtitles from mapping will be copied if compatible)
        return []
    }

    /// Build metadata arguments.
    private func buildMetadataArguments() -> [String] {
        var args: [String] = []

        // File-level metadata
        for (key, value) in metadata {
            args.append(contentsOf: ["-metadata", "\(key)=\(value)"])
        }

        // Per-stream metadata
        for (streamSpec, tags) in streamMetadata {
            for (key, value) in tags {
                args.append(contentsOf: ["-metadata:\(streamSpec)", "\(key)=\(value)"])
            }
        }

        return args
    }

    // MARK: - Helpers

    /// Format a bitrate integer into FFmpeg's string format (e.g., 160000 → "160k").
    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return "\(bps / 1_000_000)M"
        } else if bps >= 1000 {
            return "\(bps / 1000)k"
        }
        return "\(bps)"
    }

    /// Get the FFmpeg format name for a container format.
    /// Delegates to ContainerFormat.ffmpegFormatName to avoid duplication.
    private func ffmpegFormatName(for container: ContainerFormat) -> String {
        container.ffmpegFormatName
    }
}
