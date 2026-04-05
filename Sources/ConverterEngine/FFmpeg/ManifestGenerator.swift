// ============================================================================
// MeedyaConverter — ManifestGenerator
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ManifestGeneratorError

/// Errors from manifest generation operations.
public enum ManifestGeneratorError: LocalizedError, Sendable {
    /// FFmpeg is not available.
    case ffmpegUnavailable
    /// The input file was not found.
    case inputNotFound(String)
    /// The output directory is not writable.
    case outputDirectoryInvalid(String)
    /// Manifest generation failed.
    case generationFailed(String)
    /// Invalid variant ladder configuration.
    case invalidVariantLadder(String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable: return "FFmpeg is not available"
        case .inputNotFound(let p): return "Input not found: \(p)"
        case .outputDirectoryInvalid(let p): return "Output directory invalid: \(p)"
        case .generationFailed(let msg): return "Manifest generation failed: \(msg)"
        case .invalidVariantLadder(let msg): return "Invalid variant ladder: \(msg)"
        }
    }
}

// MARK: - StreamingVariant

/// A single rendition in an adaptive streaming variant ladder.
///
/// Each variant represents a specific quality level with defined resolution,
/// bitrate, and codec settings. The manifest generator encodes each variant
/// and stitches them into a multi-bitrate manifest.
public struct StreamingVariant: Codable, Sendable {
    /// Human-readable label (e.g., "1080p", "720p", "480p").
    public var label: String

    /// Output video width.
    public var width: Int

    /// Output video height.
    public var height: Int

    /// Target video bitrate in bits per second.
    public var videoBitrate: Int

    /// Maximum video bitrate (for CVBR).
    public var videoMaxBitrate: Int

    /// VBV buffer size in bits.
    public var videoBufferSize: Int

    /// Target audio bitrate in bits per second.
    public var audioBitrate: Int

    /// Audio channel count.
    public var audioChannels: Int

    public init(
        label: String,
        width: Int,
        height: Int,
        videoBitrate: Int,
        videoMaxBitrate: Int,
        videoBufferSize: Int,
        audioBitrate: Int = 128_000,
        audioChannels: Int = 2
    ) {
        self.label = label
        self.width = width
        self.height = height
        self.videoBitrate = videoBitrate
        self.videoMaxBitrate = videoMaxBitrate
        self.videoBufferSize = videoBufferSize
        self.audioBitrate = audioBitrate
        self.audioChannels = audioChannels
    }
}

// MARK: - ManifestFormat

/// The adaptive streaming format to generate.
public enum ManifestFormat: String, Codable, Sendable, CaseIterable {
    /// Apple HTTP Live Streaming (HLS) with M3U8 manifests.
    case hls
    /// MPEG-DASH with MPD manifests.
    case dash
    /// Both HLS and DASH from the same segments (CMAF).
    case cmaf
}

// MARK: - ManifestConfig

/// Complete configuration for generating an adaptive streaming manifest.
public struct ManifestConfig: Codable, Sendable {
    /// Source media file URL.
    public var inputURL: URL

    /// Output directory for manifest and segments.
    public var outputDirectory: URL

    /// Manifest format to generate.
    public var format: ManifestFormat

    /// Video codec for all variants.
    public var videoCodec: VideoCodec

    /// Audio codec for all variants.
    public var audioCodec: AudioCodec

    /// Encoder preset.
    public var preset: String

    /// Keyframe interval in seconds (GOP size).
    public var keyframeInterval: Double

    /// Segment duration in seconds.
    public var segmentDuration: Double

    /// The variant ladder (quality levels).
    public var variants: [StreamingVariant]

    /// Whether to preserve HDR in the output.
    public var preserveHDR: Bool

    /// Pixel format (e.g., "yuv420p", "yuv420p10le").
    public var pixelFormat: String?

    /// Whether to use hardware encoding.
    public var useHardwareEncoding: Bool

    public init(
        inputURL: URL,
        outputDirectory: URL,
        format: ManifestFormat = .hls,
        videoCodec: VideoCodec = .h264,
        audioCodec: AudioCodec = .aacLC,
        preset: String = "medium",
        keyframeInterval: Double = 2.0,
        segmentDuration: Double = 6.0,
        variants: [StreamingVariant] = StreamingVariant.defaultLadder,
        preserveHDR: Bool = false,
        pixelFormat: String? = nil,
        useHardwareEncoding: Bool = false
    ) {
        self.inputURL = inputURL
        self.outputDirectory = outputDirectory
        self.format = format
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.preset = preset
        self.keyframeInterval = keyframeInterval
        self.segmentDuration = segmentDuration
        self.variants = variants
        self.preserveHDR = preserveHDR
        self.pixelFormat = pixelFormat
        self.useHardwareEncoding = useHardwareEncoding
    }
}

// MARK: - Default Variant Ladders

extension StreamingVariant {
    /// Standard ABR ladder for H.264 streaming (Apple HLS recommended).
    public static let defaultLadder: [StreamingVariant] = [
        StreamingVariant(label: "1080p", width: 1920, height: 1080,
                        videoBitrate: 5_000_000, videoMaxBitrate: 7_500_000,
                        videoBufferSize: 10_000_000, audioBitrate: 192_000, audioChannels: 2),
        StreamingVariant(label: "720p", width: 1280, height: 720,
                        videoBitrate: 2_500_000, videoMaxBitrate: 3_750_000,
                        videoBufferSize: 5_000_000, audioBitrate: 128_000, audioChannels: 2),
        StreamingVariant(label: "480p", width: 854, height: 480,
                        videoBitrate: 1_200_000, videoMaxBitrate: 1_800_000,
                        videoBufferSize: 2_400_000, audioBitrate: 96_000, audioChannels: 2),
        StreamingVariant(label: "360p", width: 640, height: 360,
                        videoBitrate: 600_000, videoMaxBitrate: 900_000,
                        videoBufferSize: 1_200_000, audioBitrate: 64_000, audioChannels: 2),
    ]

    /// 4K HDR ladder for H.265 streaming.
    public static let uhdrLadder: [StreamingVariant] = [
        StreamingVariant(label: "2160p", width: 3840, height: 2160,
                        videoBitrate: 14_000_000, videoMaxBitrate: 21_000_000,
                        videoBufferSize: 28_000_000, audioBitrate: 256_000, audioChannels: 6),
        StreamingVariant(label: "1080p", width: 1920, height: 1080,
                        videoBitrate: 6_000_000, videoMaxBitrate: 9_000_000,
                        videoBufferSize: 12_000_000, audioBitrate: 192_000, audioChannels: 2),
        StreamingVariant(label: "720p", width: 1280, height: 720,
                        videoBitrate: 3_000_000, videoMaxBitrate: 4_500_000,
                        videoBufferSize: 6_000_000, audioBitrate: 128_000, audioChannels: 2),
        StreamingVariant(label: "480p", width: 854, height: 480,
                        videoBitrate: 1_500_000, videoMaxBitrate: 2_250_000,
                        videoBufferSize: 3_000_000, audioBitrate: 96_000, audioChannels: 2),
    ]
}

// MARK: - ManifestGenerator

/// Generates adaptive streaming manifests (HLS/DASH) from source media.
///
/// The generator creates multi-bitrate renditions using FFmpeg and assembles
/// them into standard manifest files for adaptive streaming delivery.
///
/// Workflow:
/// 1. Validate inputs and create output directory structure
/// 2. Encode each variant with aligned keyframes and CVBR bitrate control
/// 3. Generate the manifest file(s) (M3U8 for HLS, MPD for DASH)
///
/// Phase 4.5 / Issue #71
public final class ManifestGenerator: @unchecked Sendable {

    /// The path to the FFmpeg binary.
    private let ffmpegPath: String

    /// Lock for thread safety.
    private let lock = NSLock()

    public init(ffmpegPath: String) {
        self.ffmpegPath = ffmpegPath
    }

    /// Build FFmpeg arguments for a single HLS variant encode.
    ///
    /// Each variant is encoded as a separate stream with aligned keyframes,
    /// CVBR bitrate control, and correct segment naming.
    public func buildVariantArguments(
        config: ManifestConfig,
        variant: StreamingVariant,
        variantIndex: Int
    ) -> [String] {
        var args: [String] = ["-y", "-nostdin"]

        // Input
        args += ["-i", config.inputURL.path]

        // Stream mapping
        args += ["-map", "0:v:0", "-map", "0:a:0"]

        // Video codec
        let encoderName: String
        if config.useHardwareEncoding, let codec = config.videoCodec.ffmpegEncoder {
            switch config.videoCodec {
            case .h264: encoderName = "h264_videotoolbox"
            case .h265: encoderName = "hevc_videotoolbox"
            default: encoderName = codec
            }
        } else {
            encoderName = config.videoCodec.ffmpegEncoder ?? "libx264"
        }
        args += ["-c:v", encoderName]

        // CVBR bitrate control
        args += ["-b:v", formatBitrate(variant.videoBitrate)]
        args += ["-maxrate", formatBitrate(variant.videoMaxBitrate)]
        args += ["-bufsize", formatBitrate(variant.videoBufferSize)]

        // Resolution
        args += ["-s", "\(variant.width)x\(variant.height)"]

        // Preset
        args += ["-preset", config.preset]

        // Pixel format
        if let pf = config.pixelFormat {
            args += ["-pix_fmt", pf]
        }

        // Keyframe alignment (critical for ABR switching)
        let gopSize = Int(config.keyframeInterval * 30) // Assume 30fps, FFmpeg adjusts
        args += ["-g", "\(gopSize)", "-keyint_min", "\(gopSize)"]
        args += ["-sc_threshold", "0"] // Disable scene-change keyframes

        // Audio codec
        if let audioEncoder = config.audioCodec.ffmpegEncoder {
            args += ["-c:a", audioEncoder]
        }
        args += ["-b:a", formatBitrate(variant.audioBitrate)]
        args += ["-ac", "\(variant.audioChannels)"]

        // Format-specific output
        let variantDir = config.outputDirectory
            .appendingPathComponent("v\(variantIndex)_\(variant.label)")

        switch config.format {
        case .hls:
            args += ["-f", "hls"]
            args += ["-hls_time", "\(Int(config.segmentDuration))"]
            args += ["-hls_list_size", "0"] // Include all segments
            args += ["-hls_segment_filename", variantDir.appendingPathComponent("seg_%03d.ts").path]
            args += ["-hls_flags", "independent_segments"]
            args += [variantDir.appendingPathComponent("playlist.m3u8").path]

        case .dash:
            args += ["-f", "dash"]
            args += ["-seg_duration", "\(Int(config.segmentDuration))"]
            args += ["-use_template", "1"]
            args += ["-use_timeline", "1"]
            args += ["-init_seg_name", "init_$RepresentationID$.m4s"]
            args += ["-media_seg_name", "seg_$RepresentationID$_$Number$.m4s"]
            args += [variantDir.appendingPathComponent("manifest.mpd").path]

        case .cmaf:
            // CMAF uses fMP4 segments compatible with both HLS and DASH
            args += ["-f", "hls"]
            args += ["-hls_time", "\(Int(config.segmentDuration))"]
            args += ["-hls_list_size", "0"]
            args += ["-hls_segment_type", "fmp4"]
            args += ["-hls_fmp4_init_filename", "init.mp4"]
            args += ["-hls_segment_filename", variantDir.appendingPathComponent("seg_%03d.m4s").path]
            args += ["-hls_flags", "independent_segments"]
            args += [variantDir.appendingPathComponent("playlist.m3u8").path]
        }

        return args
    }

    /// Build the master HLS playlist that references all variant playlists.
    public func buildMasterPlaylist(config: ManifestConfig) -> String {
        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-VERSION:6",
        ]

        for (i, variant) in config.variants.enumerated() {
            let bandwidth = variant.videoMaxBitrate + variant.audioBitrate
            let avgBandwidth = variant.videoBitrate + variant.audioBitrate
            let codecs = hlsCodecString(videoCodec: config.videoCodec, audioCodec: config.audioCodec)

            lines.append("#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth),AVERAGE-BANDWIDTH=\(avgBandwidth),RESOLUTION=\(variant.width)x\(variant.height),CODECS=\"\(codecs)\",NAME=\"\(variant.label)\"")
            lines.append("v\(i)_\(variant.label)/playlist.m3u8")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Build a DASH MPD manifest that references all variant streams.
    public func buildDASHManifest(config: ManifestConfig) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
             type="static"
             minBufferTime="PT\(Int(config.segmentDuration))S"
             profiles="urn:mpeg:dash:profile:isoff-on-demand:2011">
          <Period>
            <AdaptationSet mimeType="video/mp4" segmentAlignment="true" startWithSAP="1">
        """

        for (i, variant) in config.variants.enumerated() {
            xml += """

                  <Representation id="v\(i)" bandwidth="\(variant.videoBitrate)" width="\(variant.width)" height="\(variant.height)">
                    <BaseURL>v\(i)_\(variant.label)/</BaseURL>
                    <SegmentTemplate media="seg_$Number$.m4s" initialization="init.m4s" startNumber="1" duration="\(Int(config.segmentDuration * 1000))" timescale="1000"/>
                  </Representation>
            """
        }

        xml += """

            </AdaptationSet>
            <AdaptationSet mimeType="audio/mp4" segmentAlignment="true" startWithSAP="1">
              <Representation id="audio" bandwidth="\(config.variants.first?.audioBitrate ?? 128000)">
                <BaseURL>v0_\(config.variants.first?.label ?? "1080p")/</BaseURL>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

        return xml
    }

    /// Validate a manifest configuration before generation.
    ///
    /// Returns a list of validation warnings/errors.
    public func validate(config: ManifestConfig) -> [String] {
        var issues: [String] = []

        if config.variants.isEmpty {
            issues.append("No variants defined in the ladder")
        }

        for variant in config.variants {
            if variant.width <= 0 || variant.height <= 0 {
                issues.append("\(variant.label): invalid resolution \(variant.width)x\(variant.height)")
            }
            if variant.videoBitrate <= 0 {
                issues.append("\(variant.label): video bitrate must be positive")
            }
            if variant.videoMaxBitrate < variant.videoBitrate {
                issues.append("\(variant.label): max bitrate (\(variant.videoMaxBitrate)) < target bitrate (\(variant.videoBitrate))")
            }
        }

        if !config.inputURL.isFileURL {
            issues.append("Input must be a local file URL")
        }

        if config.keyframeInterval <= 0 {
            issues.append("Keyframe interval must be positive")
        }

        if config.segmentDuration <= 0 {
            issues.append("Segment duration must be positive")
        }

        // Check codec-format compatibility
        switch config.format {
        case .hls:
            if config.videoCodec != .h264 && config.videoCodec != .h265 {
                issues.append("HLS typically requires H.264 or H.265 video codec")
            }
        case .dash:
            break // DASH supports most codecs
        case .cmaf:
            if config.videoCodec == .vp8 || config.videoCodec == .vp9 {
                issues.append("CMAF fMP4 segments are not compatible with VP8/VP9")
            }
        }

        return issues
    }

    // MARK: - Helpers

    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 { return "\(bps / 1_000_000)M" }
        if bps >= 1000 { return "\(bps / 1000)k" }
        return "\(bps)"
    }

    private func hlsCodecString(videoCodec: VideoCodec, audioCodec: AudioCodec) -> String {
        let video: String
        switch videoCodec {
        case .h264: video = "avc1.640028" // High Profile, Level 4.0
        case .h265: video = "hvc1.1.6.L120.90" // Main 10, Level 4.0
        case .av1: video = "av01.0.08M.08"
        default: video = "avc1.640028"
        }

        let audio: String
        switch audioCodec {
        case .aacLC: audio = "mp4a.40.2"
        case .heAAC: audio = "mp4a.40.5"
        case .ac3: audio = "ac-3"
        case .eac3: audio = "ec-3"
        default: audio = "mp4a.40.2"
        }

        return "\(video),\(audio)"
    }
}
