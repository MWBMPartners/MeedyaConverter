// ============================================================================
// MeedyaConverter — MediaStream
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - StreamType

/// The type of media content carried by a stream.
public enum StreamType: String, Codable, Sendable {
    /// A video stream (moving images).
    case video

    /// An audio stream (sound).
    case audio

    /// A subtitle or closed caption stream.
    case subtitle

    /// A data stream (chapters, metadata, attachments, etc.).
    case data

    /// An attachment stream (fonts, images embedded in container).
    case attachment

    /// Stream type is unknown or not recognised.
    case unknown
}

// MARK: - HDRFormat

/// The HDR (High Dynamic Range) format detected in a video stream.
public enum HDRFormat: String, Codable, Sendable {
    /// HDR10 — static metadata (SMPTE ST 2086 mastering display + MaxCLL/MaxFALL).
    case hdr10

    /// HDR10+ — dynamic metadata (scene-by-scene tone mapping).
    /// Samsung/Amazon standard using SMPTE ST 2094-40.
    case hdr10Plus = "hdr10+"

    /// Dolby Vision — proprietary dynamic HDR with RPU metadata layer.
    /// Profiles: 5 (MEL), 7 (FEL), 8.1-8.4 (various base layers).
    case dolbyVision = "dolby_vision"

    /// HLG (Hybrid Log-Gamma) — BBC/NHK standard for broadcast HDR.
    /// Backward-compatible with SDR displays.
    case hlg

    /// PQ (Perceptual Quantizer) — SMPTE ST 2084 transfer function.
    /// The transfer curve used by HDR10, HDR10+, and Dolby Vision.
    case pq
}

// MARK: - ColourProperties

/// Colour space and transfer function properties of a video stream.
public struct ColourProperties: Codable, Sendable, Equatable {
    /// Colour primaries (e.g., BT.709, BT.2020, DCI-P3).
    public var primaries: String?

    /// Transfer characteristics (e.g., BT.709, PQ/ST2084, HLG/ARIB-STD-B67).
    public var transferCharacteristics: String?

    /// Colour matrix coefficients (e.g., BT.709, BT.2020 NCL).
    public var matrixCoefficients: String?

    /// Bit depth (8, 10, 12, etc.).
    public var bitDepth: Int?

    /// Chroma subsampling format (e.g., "4:2:0", "4:2:2", "4:4:4").
    public var chromaSubsampling: String?

    /// Maximum Content Light Level in nits (cd/m²).
    public var maxCLL: Int?

    /// Maximum Frame-Average Light Level in nits (cd/m²).
    public var maxFALL: Int?

    /// Mastering display maximum luminance in nits.
    public var masteringDisplayMaxLuminance: Int?

    /// Mastering display minimum luminance in nits × 10000 (e.g., 500 = 0.05 nits).
    public var masteringDisplayMinLuminance: Int?

    /// Whether the colour space is wide gamut (BT.2020 or wider).
    public var isWideGamut: Bool {
        return primaries?.contains("2020") == true || primaries?.contains("P3") == true
    }

    /// Whether the transfer function indicates HDR content.
    public var isHDRTransfer: Bool {
        guard let tc = transferCharacteristics?.lowercased() else { return false }
        return tc.contains("2084") || tc.contains("pq") ||
               tc.contains("b67") || tc.contains("hlg") ||
               tc.contains("arib")
    }

    public init(
        primaries: String? = nil,
        transferCharacteristics: String? = nil,
        matrixCoefficients: String? = nil,
        bitDepth: Int? = nil,
        chromaSubsampling: String? = nil,
        maxCLL: Int? = nil,
        maxFALL: Int? = nil,
        masteringDisplayMaxLuminance: Int? = nil,
        masteringDisplayMinLuminance: Int? = nil
    ) {
        self.primaries = primaries
        self.transferCharacteristics = transferCharacteristics
        self.matrixCoefficients = matrixCoefficients
        self.bitDepth = bitDepth
        self.chromaSubsampling = chromaSubsampling
        self.maxCLL = maxCLL
        self.maxFALL = maxFALL
        self.masteringDisplayMaxLuminance = masteringDisplayMaxLuminance
        self.masteringDisplayMinLuminance = masteringDisplayMinLuminance
    }
}

// MARK: - ChannelLayout

/// Audio channel layout information.
public struct ChannelLayout: Codable, Sendable, Equatable {
    /// Number of audio channels (1=mono, 2=stereo, 6=5.1, 8=7.1, etc.).
    public var channelCount: Int

    /// FFmpeg channel layout string (e.g., "stereo", "5.1", "7.1", "5.1(side)").
    public var layoutName: String?

    /// Human-readable description of the channel layout.
    public var displayName: String {
        switch channelCount {
        case 1: return "Mono (1.0)"
        case 2: return "Stereo (2.0)"
        case 3: return "3.0"
        case 4: return "Quad (4.0)"
        case 6: return "5.1 Surround"
        case 7: return "6.1 Surround"
        case 8: return "7.1 Surround"
        case 12: return "7.1.4 (Atmos bed)"
        case 24: return "22.2 (NHK)"
        default: return "\(channelCount) channels"
        }
    }

    /// Whether this is a surround layout (more than 2 channels).
    public var isSurround: Bool {
        return channelCount > 2
    }

    /// Whether upmixing from this layout is meaningful.
    /// Mono sources should not be offered upmix options.
    public var canUpmix: Bool {
        return channelCount >= 2
    }

    public init(channelCount: Int, layoutName: String? = nil) {
        self.channelCount = channelCount
        self.layoutName = layoutName
    }
}

// MARK: - MatrixEncoding

/// Detected matrix encoding metadata in an audio stream.
/// When present, indicates that surround information is encoded in the stereo signal.
public enum MatrixEncoding: String, Codable, Sendable {
    /// Dolby Surround — original passive matrix (L/R/S).
    case dolbySurround = "dolby_surround"

    /// Dolby Pro Logic II — active matrix decode (L/R/C/LS/RS).
    case proLogicII = "prologic_ii"

    /// Dolby Pro Logic IIx — extends to 6.1/7.1.
    case proLogicIIx = "prologic_iix"

    /// Dolby Digital EX — rear center matrix encoded in 5.1 surround channels.
    case dolbyEX = "dolby_ex"

    /// Dolby Surround Upmixer — modern Atmos-era replacement.
    case dolbySurroundUpmixer = "dolby_surround_upmixer"

    /// DTS ES Matrix — 6.1 rear center in DTS 5.1 core.
    case dtsES = "dts_es"

    /// DTS Neo:6 — DTS upmix to 5.1/6.1.
    case dtsNeo6 = "dts_neo6"

    /// DTS Neural:X — modern DTS immersive upmixer.
    case dtsNeuralX = "dts_neural_x"

    /// Circle Surround (SRS) — third-party matrix encoding.
    case circleSurround = "circle_surround"

    /// MPEG Surround — SBR/PS extension data in AAC/MP3.
    case mpegSurround = "mpeg_surround"
}

// MARK: - MediaStream

/// Represents a single stream (video, audio, subtitle, or data) within a media file.
///
/// Populated by media probing (ffprobe + MediaInfo). Contains all metadata
/// needed for encoding decisions, UI display, and stream selection.
public struct MediaStream: Identifiable, Codable, Sendable {
    /// Unique identifier for this stream instance.
    public let id: UUID

    /// The index of this stream within the source file (0-based).
    public var streamIndex: Int

    /// The type of content this stream carries (video, audio, subtitle, data).
    public var streamType: StreamType

    // MARK: - Common Properties

    /// The codec used to encode this stream (as reported by the container/probe).
    public var codecName: String?

    /// The long/descriptive codec name (e.g., "H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10").
    public var codecLongName: String?

    /// The stream's bitrate in bits per second. Nil if unknown or VBR without average.
    public var bitrate: Int?

    /// Duration of the stream in seconds. May differ from file duration for some streams.
    public var duration: TimeInterval?

    /// BCP 47 language code for this stream (e.g., "en", "en-GB", "fr-FR").
    public var language: String?

    /// User-facing title/label for this stream (e.g., "Director's Commentary").
    public var title: String?

    /// Whether this is the default stream for its type in the container.
    public var isDefault: Bool

    /// Whether this stream is forced (should be displayed regardless of user preference).
    public var isForced: Bool

    /// Whether this stream is enabled (some containers support disabled streams).
    public var isEnabled: Bool

    // MARK: - Video-Specific Properties

    /// Video width in pixels.
    public var width: Int?

    /// Video height in pixels.
    public var height: Int?

    /// Frame rate as a floating-point value (e.g., 23.976, 29.97, 60.0).
    public var frameRate: Double?

    /// Pixel aspect ratio (e.g., "1:1" for square pixels).
    public var pixelAspectRatio: String?

    /// Display aspect ratio (e.g., "16:9", "2.35:1").
    public var displayAspectRatio: String?

    /// Detected HDR formats present in this video stream.
    public var hdrFormats: [HDRFormat]

    /// Colour space and transfer function properties.
    public var colourProperties: ColourProperties?

    /// Dolby Vision configuration string (e.g., "dvhe.08.06" for Profile 8, Level 6).
    public var dolbyVisionProfile: String?

    /// Whether this video stream contains 3D/stereoscopic content.
    public var isStereo3D: Bool

    /// The video codec enum value, if recognised.
    public var videoCodec: VideoCodec?

    // MARK: - Audio-Specific Properties

    /// Audio sample rate in Hz (e.g., 44100, 48000, 96000).
    public var sampleRate: Int?

    /// Audio channel layout information.
    public var channelLayout: ChannelLayout?

    /// Audio bit depth (e.g., 16, 24, 32). Nil for lossy codecs.
    public var audioBitDepth: Int?

    /// Detected matrix encoding metadata (Pro Logic II, DTS ES, etc.).
    /// Nil if no matrix encoding is detected.
    public var matrixEncoding: MatrixEncoding?

    /// The audio codec enum value, if recognised.
    public var audioCodec: AudioCodec?

    // MARK: - Subtitle-Specific Properties

    /// The subtitle format enum value, if recognised.
    public var subtitleFormat: SubtitleFormat?

    // MARK: - Initialiser

    public init(
        id: UUID = UUID(),
        streamIndex: Int,
        streamType: StreamType,
        codecName: String? = nil,
        codecLongName: String? = nil,
        bitrate: Int? = nil,
        duration: TimeInterval? = nil,
        language: String? = nil,
        title: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isEnabled: Bool = true,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil,
        pixelAspectRatio: String? = nil,
        displayAspectRatio: String? = nil,
        hdrFormats: [HDRFormat] = [],
        colourProperties: ColourProperties? = nil,
        dolbyVisionProfile: String? = nil,
        isStereo3D: Bool = false,
        videoCodec: VideoCodec? = nil,
        sampleRate: Int? = nil,
        channelLayout: ChannelLayout? = nil,
        audioBitDepth: Int? = nil,
        matrixEncoding: MatrixEncoding? = nil,
        audioCodec: AudioCodec? = nil,
        subtitleFormat: SubtitleFormat? = nil
    ) {
        self.id = id
        self.streamIndex = streamIndex
        self.streamType = streamType
        self.codecName = codecName
        self.codecLongName = codecLongName
        self.bitrate = bitrate
        self.duration = duration
        self.language = language
        self.title = title
        self.isDefault = isDefault
        self.isForced = isForced
        self.isEnabled = isEnabled
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.pixelAspectRatio = pixelAspectRatio
        self.displayAspectRatio = displayAspectRatio
        self.hdrFormats = hdrFormats
        self.colourProperties = colourProperties
        self.dolbyVisionProfile = dolbyVisionProfile
        self.isStereo3D = isStereo3D
        self.videoCodec = videoCodec
        self.sampleRate = sampleRate
        self.channelLayout = channelLayout
        self.audioBitDepth = audioBitDepth
        self.matrixEncoding = matrixEncoding
        self.audioCodec = audioCodec
        self.subtitleFormat = subtitleFormat
    }

    // MARK: - Convenience Properties

    /// A formatted resolution string (e.g., "1920×1080").
    public var resolutionString: String? {
        guard let w = width, let h = height else { return nil }
        return "\(w)×\(h)"
    }

    /// A formatted display string combining key properties for UI display.
    public var summaryString: String {
        switch streamType {
        case .video:
            let res = resolutionString ?? "unknown"
            let codec = videoCodec?.displayName ?? codecName ?? "unknown"
            let hdr = hdrFormats.isEmpty ? "" : " HDR"
            return "\(codec) \(res)\(hdr)"
        case .audio:
            let codec = audioCodec?.displayName ?? codecName ?? "unknown"
            let channels = channelLayout?.displayName ?? "\(channelLayout?.channelCount ?? 0)ch"
            let lang = language ?? ""
            return "\(codec) \(channels) \(lang)".trimmingCharacters(in: .whitespaces)
        case .subtitle:
            let format = subtitleFormat?.displayName ?? codecName ?? "unknown"
            let lang = language ?? ""
            return "\(format) \(lang)".trimmingCharacters(in: .whitespaces)
        default:
            return codecName ?? streamType.rawValue
        }
    }
}
