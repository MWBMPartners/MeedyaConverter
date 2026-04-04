// ============================================================================
// MeedyaConverter — ExtendedContainer
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ExtendedContainerFormat

/// Additional container formats beyond the core set (MP4/MKV/MOV/WebM).
public enum ExtendedContainerFormat: String, Codable, Sendable, CaseIterable {

    /// MXF (Material eXchange Format) — professional broadcast.
    case mxf

    /// AVI (Audio Video Interleave) — legacy Microsoft.
    case avi

    /// FLV (Flash Video) — legacy web streaming.
    case flv

    /// MPEG-TS (Transport Stream) — broadcast.
    case mpegTS = "mpegts"

    /// MPEG-PS (Program Stream) — DVD.
    case mpegPS = "mpeg"

    /// 3GP — mobile multimedia.
    case threeGP = "3gp"

    /// OGG — open container.
    case ogg

    /// OGM — OGG Media (legacy).
    case ogm

    /// WMV / ASF — Windows Media.
    case asf

    /// NUT — FFmpeg's native container.
    case nut

    /// File extension.
    public var fileExtension: String {
        switch self {
        case .mxf: return "mxf"
        case .avi: return "avi"
        case .flv: return "flv"
        case .mpegTS: return "ts"
        case .mpegPS: return "mpg"
        case .threeGP: return "3gp"
        case .ogg: return "ogg"
        case .ogm: return "ogm"
        case .asf: return "wmv"
        case .nut: return "nut"
        }
    }

    /// FFmpeg muxer name.
    public var ffmpegMuxer: String {
        switch self {
        case .mxf: return "mxf"
        case .avi: return "avi"
        case .flv: return "flv"
        case .mpegTS: return "mpegts"
        case .mpegPS: return "mpeg"
        case .threeGP: return "3gp"
        case .ogg: return "ogg"
        case .ogm: return "ogg"
        case .asf: return "asf"
        case .nut: return "nut"
        }
    }

    /// FFmpeg demuxer name.
    public var ffmpegDemuxer: String {
        switch self {
        case .mxf: return "mxf"
        case .avi: return "avi"
        case .flv: return "flv"
        case .mpegTS: return "mpegts"
        case .mpegPS: return "mpeg"
        case .threeGP: return "mov" // 3GP uses the MOV demuxer
        case .ogg: return "ogg"
        case .ogm: return "ogg"
        case .asf: return "asf"
        case .nut: return "nut"
        }
    }

    /// Display name.
    public var displayName: String {
        switch self {
        case .mxf: return "MXF (Material eXchange Format)"
        case .avi: return "AVI (Audio Video Interleave)"
        case .flv: return "FLV (Flash Video)"
        case .mpegTS: return "MPEG-TS (Transport Stream)"
        case .mpegPS: return "MPEG-PS (Program Stream)"
        case .threeGP: return "3GP (Mobile Video)"
        case .ogg: return "OGG (Open Container)"
        case .ogm: return "OGM (OGG Media)"
        case .asf: return "WMV/ASF (Windows Media)"
        case .nut: return "NUT (FFmpeg Native)"
        }
    }

    /// Compatible video codecs.
    public var compatibleVideoCodecs: [String] {
        switch self {
        case .mxf: return ["mpeg2video", "h264", "hevc", "jpeg2000", "dnxhd", "prores"]
        case .avi: return ["mpeg4", "h264", "msmpeg4v3", "ffv1", "cfhd", "rawvideo"]
        case .flv: return ["h264", "vp6f", "flv1"]
        case .mpegTS: return ["mpeg2video", "h264", "hevc", "av1"]
        case .mpegPS: return ["mpeg1video", "mpeg2video"]
        case .threeGP: return ["h264", "h263", "mpeg4"]
        case .ogg: return ["theora", "vp8"]
        case .ogm: return ["theora", "vp8"]
        case .asf: return ["wmv1", "wmv2", "wmv3", "vc1"]
        case .nut: return ["any"] // NUT supports virtually any codec
        }
    }

    /// Compatible audio codecs.
    public var compatibleAudioCodecs: [String] {
        switch self {
        case .mxf: return ["pcm_s16le", "pcm_s24le", "aac", "mp2"]
        case .avi: return ["mp3", "pcm_s16le", "ac3", "aac"]
        case .flv: return ["aac", "mp3", "speex"]
        case .mpegTS: return ["aac", "ac3", "eac3", "mp2", "mp3", "dts", "opus"]
        case .mpegPS: return ["mp2", "ac3", "lpcm"]
        case .threeGP: return ["aac", "amr_nb", "amr_wb"]
        case .ogg: return ["vorbis", "opus", "flac"]
        case .ogm: return ["vorbis", "mp3"]
        case .asf: return ["wmav1", "wmav2", "wmavoice", "wmapro"]
        case .nut: return ["any"]
        }
    }

    /// Maximum file size limitation (bytes, nil = unlimited).
    public var maxFileSize: Int64? {
        switch self {
        case .avi: return 4_294_967_296 // 4 GB (2 GB in older implementations)
        case .flv: return nil
        case .threeGP: return nil
        default: return nil
        }
    }

    /// Whether this format supports chapters.
    public var supportsChapters: Bool {
        switch self {
        case .ogg, .ogm, .nut: return true
        default: return false
        }
    }

    /// Whether this format supports subtitles.
    public var supportsSubtitles: Bool {
        switch self {
        case .mxf, .mpegTS, .nut, .avi: return true
        case .ogg: return true // Kate subtitles
        default: return false
        }
    }

    /// Primary use case.
    public var useCase: String {
        switch self {
        case .mxf: return "Professional broadcast / DCP"
        case .avi: return "Legacy media libraries"
        case .flv: return "Legacy web video"
        case .mpegTS: return "Broadcast / IPTV / streaming"
        case .mpegPS: return "DVD ripping"
        case .threeGP: return "Mobile device compatibility"
        case .ogg: return "Open-source media"
        case .ogm: return "Legacy open-source media"
        case .asf: return "Windows Media compatibility"
        case .nut: return "Lossless intermediate / testing"
        }
    }
}

// MARK: - ExtendedContainerBuilder

/// Builds FFmpeg arguments for extended container format operations.
///
/// Phase 3.24
public struct ExtendedContainerBuilder: Sendable {

    // MARK: - Muxing

    /// Build FFmpeg arguments to mux into an extended container format.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output file.
    ///   - format: Target container format.
    ///   - videoCodec: Video codec (nil = copy).
    ///   - audioCodec: Audio codec (nil = copy).
    /// - Returns: FFmpeg argument array.
    public static func buildMuxArguments(
        inputPath: String,
        outputPath: String,
        format: ExtendedContainerFormat,
        videoCodec: String? = nil,
        audioCodec: String? = nil
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        // Format-specific options
        switch format {
        case .mpegTS:
            args += ["-mpegts_flags", "resend_headers"]
        case .flv:
            args += ["-flvflags", "add_keyframe_index"]
        case .mxf:
            break // MXF may need specific operational pattern
        default:
            break
        }

        // Codec handling
        if let vc = videoCodec {
            args += ["-c:v", vc]
        } else {
            args += ["-c:v", "copy"]
        }

        if let ac = audioCodec {
            args += ["-c:a", ac]
        } else {
            args += ["-c:a", "copy"]
        }

        // Force format
        args += ["-f", format.ffmpegMuxer]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - MPEG-TS

    /// Build FFmpeg arguments for MPEG-TS output with broadcast settings.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output .ts file.
    ///   - constantBitrate: Whether to use CBR muxing.
    ///   - muxRate: Mux rate in bits/second (for CBR).
    ///   - serviceName: Service name for TS metadata.
    /// - Returns: FFmpeg argument array.
    public static func buildMPEGTSArguments(
        inputPath: String,
        outputPath: String,
        constantBitrate: Bool = false,
        muxRate: Int? = nil,
        serviceName: String? = nil
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        args += ["-c", "copy"]
        args += ["-f", "mpegts"]

        if constantBitrate, let rate = muxRate {
            args += ["-muxrate", "\(rate)"]
        }

        if let name = serviceName {
            args += ["-metadata", "service_name=\(name)"]
        }

        // Resend headers periodically for stream robustness
        args += ["-mpegts_flags", "resend_headers"]

        // PAT/PMT period (packets)
        args += ["-pat_period", "0.1"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - MXF

    /// Build FFmpeg arguments for MXF output (broadcast/professional).
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output .mxf file.
    ///   - videoCodec: Video codec for MXF.
    ///   - audioCodec: Audio codec for MXF (typically PCM).
    /// - Returns: FFmpeg argument array.
    public static func buildMXFArguments(
        inputPath: String,
        outputPath: String,
        videoCodec: String = "mpeg2video",
        audioCodec: String = "pcm_s16le"
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        args += ["-c:v", videoCodec]
        args += ["-c:a", audioCodec]
        args += ["-ar", "48000"] // Standard broadcast audio rate
        args += ["-f", "mxf"]
        args += ["-y", outputPath]

        return args
    }

    // MARK: - AVI

    /// Build FFmpeg arguments for AVI output.
    ///
    /// Handles the 4 GB file size limitation with OpenDML extensions.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output .avi file.
    ///   - videoCodec: Video codec for AVI.
    /// - Returns: FFmpeg argument array.
    public static func buildAVIArguments(
        inputPath: String,
        outputPath: String,
        videoCodec: String = "mpeg4"
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:v", videoCodec,
            "-c:a", "mp3",
            "-f", "avi",
            "-y", outputPath,
        ]
    }

    // MARK: - 3GP

    /// Build FFmpeg arguments for 3GP mobile output.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output .3gp file.
    ///   - width: Output width (default 320).
    ///   - height: Output height (default 240).
    /// - Returns: FFmpeg argument array.
    public static func build3GPArguments(
        inputPath: String,
        outputPath: String,
        width: Int = 320,
        height: Int = 240
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:v", "h264",
            "-vf", "scale=\(width):\(height)",
            "-c:a", "aac",
            "-ar", "22050",
            "-ac", "1",
            "-b:a", "32k",
            "-f", "3gp",
            "-y", outputPath,
        ]
    }

    // MARK: - OGG

    /// Build FFmpeg arguments for OGG container output.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output .ogg file.
    ///   - videoCodec: Video codec (theora or vp8).
    ///   - audioCodec: Audio codec (vorbis or opus).
    /// - Returns: FFmpeg argument array.
    public static func buildOGGArguments(
        inputPath: String,
        outputPath: String,
        videoCodec: String = "libtheora",
        audioCodec: String = "libvorbis"
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:v", videoCodec,
            "-c:a", audioCodec,
            "-f", "ogg",
            "-y", outputPath,
        ]
    }

    // MARK: - Validation

    /// Check if a codec is compatible with a container format.
    ///
    /// - Parameters:
    ///   - videoCodec: FFmpeg video codec name.
    ///   - container: Target container format.
    /// - Returns: `true` if the codec can be muxed into the container.
    public static func isVideoCodecCompatible(
        _ videoCodec: String,
        with container: ExtendedContainerFormat
    ) -> Bool {
        let compatible = container.compatibleVideoCodecs
        if compatible.contains("any") { return true }
        return compatible.contains(videoCodec)
    }

    /// Check if an audio codec is compatible with a container format.
    ///
    /// - Parameters:
    ///   - audioCodec: FFmpeg audio codec name.
    ///   - container: Target container format.
    /// - Returns: `true` if the codec can be muxed into the container.
    public static func isAudioCodecCompatible(
        _ audioCodec: String,
        with container: ExtendedContainerFormat
    ) -> Bool {
        let compatible = container.compatibleAudioCodecs
        if compatible.contains("any") { return true }
        return compatible.contains(audioCodec)
    }

    /// Recommend a compatible audio codec for a given container.
    ///
    /// - Parameter container: Target container format.
    /// - Returns: Recommended audio codec name.
    public static func recommendAudioCodec(
        for container: ExtendedContainerFormat
    ) -> String {
        switch container {
        case .mxf: return "pcm_s16le"
        case .avi: return "mp3"
        case .flv: return "aac"
        case .mpegTS: return "aac"
        case .mpegPS: return "mp2"
        case .threeGP: return "aac"
        case .ogg: return "libvorbis"
        case .ogm: return "libvorbis"
        case .asf: return "wmav2"
        case .nut: return "flac"
        }
    }
}
