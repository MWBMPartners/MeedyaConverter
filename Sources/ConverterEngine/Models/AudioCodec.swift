// ============================================================================
// MeedyaConverter — AudioCodec
// Copyright © 2026–2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// MARK: - AudioCodec

/// Represents all supported audio codecs for encoding, decoding, and passthrough.
///
/// Each codec has properties describing its capabilities: maximum channel count,
/// lossless support, FFmpeg encoder/decoder names, and VBR support.
public enum AudioCodec: String, Codable, Sendable, CaseIterable, Identifiable {

    // MARK: - AAC Family

    /// AAC Low Complexity — the most widely compatible lossy audio codec.
    /// Supports up to 7.1 channels. Used in MP4, M4A, HLS, DASH.
    case aacLC = "aac"

    /// High Efficiency AAC (HE-AAC v1) — uses SBR for better quality at low bitrates.
    /// Ideal for streaming at 48-96 kbps stereo.
    case heAAC = "he_aac"

    /// High Efficiency AAC v2 — adds Parametric Stereo to HE-AAC.
    /// Best quality at very low bitrates (32-48 kbps). Stereo only.
    case heAACv2 = "he_aac_v2"

    /// Extended HE-AAC (MPEG-D USAC) — best quality at extremely low bitrates.
    /// Growing adoption in streaming (Apple Music, Android).
    case xheAAC = "xhe_aac"

    // MARK: - Dolby Family

    /// Dolby Digital (AC-3) — standard DVD and broadcast surround codec.
    /// Maximum 5.1 channels. CBR only. Maximum total bitrate: 640 kbps.
    case ac3

    /// Dolby Digital Plus (E-AC-3) — enhanced AC-3 for streaming and Blu-ray.
    /// Supports up to 7.1 channels. Used by Netflix, Disney+, etc.
    case eac3

    /// Dolby TrueHD — lossless audio codec for Blu-ray.
    /// Supports up to 7.1 channels. FFmpeg can encode (without Atmos objects).
    case trueHD = "truehd"

    /// Dolby AC-4 — next-generation Dolby codec for broadcast and streaming.
    /// FFmpeg can decode but NOT encode. Passthrough only for encoding.
    case ac4

    // MARK: - DTS Family

    /// DTS Core — standard DTS surround codec for DVD and Blu-ray.
    /// Maximum 5.1 channels. CBR only.
    case dts

    /// DTS-HD Master Audio — lossless extension of DTS for Blu-ray.
    /// Up to 7.1 channels. FFmpeg decode/passthrough only (no encoding).
    case dtsHD = "dts_hd"

    /// DTS:X — object-based immersive audio from DTS.
    /// Decode/passthrough only. Encoding requires proprietary tools.
    case dtsX = "dts_x"

    // MARK: - Open / Standard Codecs

    /// PCM (Pulse Code Modulation) — uncompressed audio.
    /// Supports any channel count and bit depth. No quality loss.
    case pcm

    /// MP3 (MPEG-1 Audio Layer III) — ubiquitous lossy codec.
    /// Stereo only. VBR supported via LAME.
    case mp3

    /// MP2 (MPEG-1 Audio Layer II) — broadcast and DVD audio codec.
    /// Used in DVB, DAB, and some DVD-Video.
    case mp2

    /// FLAC (Free Lossless Audio Codec) — open-source lossless compression.
    /// Supports up to 7.1 channels. Typical compression ratio ~50-60%.
    case flac

    /// ALAC (Apple Lossless Audio Codec) — Apple's lossless audio format.
    /// Supports up to 7.1 channels. Used in iTunes, Apple Music.
    case alac

    /// Opus — modern open-source codec with excellent quality at all bitrates.
    /// Supports up to 7.1 channels. Used in WebM, WebRTC, Discord.
    case opus

    /// Vorbis — Xiph.org's open-source lossy codec.
    /// Used in OGG and WebM containers.
    case vorbis

    /// Speex — open-source codec optimised for speech.
    /// Largely superseded by Opus. Low bitrate voice encoding.
    case speex

    // MARK: - High-Resolution / Audiophile

    /// DSD (Direct Stream Digital) — 1-bit delta-sigma modulation.
    /// Used in SACD. Stored as DFF or DSF files. FFmpeg can decode.
    case dsd

    /// WavPack — open-source lossless/hybrid audio codec.
    /// Supports lossless and lossy+correction hybrid modes.
    case wavpack

    /// MQA (Master Quality Authenticated) — Meridian's high-res codec.
    /// Proprietary encoding. FFmpeg can decode/unfold first layer.
    case mqa

    /// Musepack (MPC) — high-quality lossy codec favoured by audiophiles.
    /// FFmpeg can decode. Encoding via external tools.
    case musepack

    /// APE (Monkey's Audio) — lossless audio compression.
    /// Higher compression ratio than FLAC but slower. FFmpeg can decode.
    case ape

    /// TTA (True Audio) — lossless audio codec with real-time compression.
    case tta

    // MARK: - Legacy / Platform-Specific

    /// WMA (Windows Media Audio) — Microsoft's audio codec family.
    /// Includes WMA Standard and WMA Pro (multichannel).
    /// FFmpeg can decode but has limited encoding support.
    case wma

    /// ATRAC — Sony's codec family (ATRAC3, ATRAC3plus, ATRAC9, ATRAC AAL).
    /// Used in MiniDisc, PlayStation, and Walkman. Decode only.
    case atrac

    // MARK: - Computed Properties

    /// A stable identifier for use with `Identifiable` conformance.
    public var id: String { rawValue }

    /// The FFmpeg encoder name for this codec.
    /// Returns nil if FFmpeg cannot encode this codec.
    public var ffmpegEncoder: String? {
        switch self {
        case .aacLC: return "aac"
        case .heAAC: return "libfdk_aac" // Requires libfdk-aac; fallback: "aac" with profile
        case .heAACv2: return "libfdk_aac" // With -profile:a aac_he_v2
        case .xheAAC: return nil // Limited FFmpeg support
        case .ac3: return "ac3"
        case .eac3: return "eac3"
        case .trueHD: return "truehd"
        case .ac4: return nil // Dolby proprietary encoder
        case .dts: return "dca"
        case .dtsHD: return nil // Proprietary encoder
        case .dtsX: return nil // Proprietary encoder
        case .pcm: return "pcm_s16le" // Default; actual format varies
        case .mp3: return "libmp3lame"
        case .mp2: return "mp2"
        case .flac: return "flac"
        case .alac: return "alac"
        case .opus: return "libopus"
        case .vorbis: return "libvorbis"
        case .speex: return "libspeex"
        case .dsd: return nil // No PCM→DSD encoder in FFmpeg
        case .wavpack: return "wavpack"
        case .mqa: return nil // Proprietary encoder
        case .musepack: return nil // External encoder
        case .ape: return nil // External encoder
        case .tta: return "tta"
        case .wma: return "wmav2"
        case .atrac: return nil // Proprietary encoder
        }
    }

    /// The FFmpeg decoder name for this codec.
    public var ffmpegDecoder: String {
        switch self {
        case .aacLC: return "aac"
        case .heAAC: return "aac"
        case .heAACv2: return "aac"
        case .xheAAC: return "aac"
        case .ac3: return "ac3"
        case .eac3: return "eac3"
        case .trueHD: return "truehd"
        case .ac4: return "ac4"
        case .dts: return "dca"
        case .dtsHD: return "dca"
        case .dtsX: return "dca"
        case .pcm: return "pcm_s16le"
        case .mp3: return "mp3"
        case .mp2: return "mp2"
        case .flac: return "flac"
        case .alac: return "alac"
        case .opus: return "opus"
        case .vorbis: return "vorbis"
        case .speex: return "speex"
        case .dsd: return "dsd_lsbf"
        case .wavpack: return "wavpack"
        case .mqa: return "flac" // MQA decoded via FLAC container
        case .musepack: return "musepack7"
        case .ape: return "ape"
        case .tta: return "tta"
        case .wma: return "wmav2"
        case .atrac: return "atrac3p"
        }
    }

    /// A human-readable display name for this codec.
    public var displayName: String {
        switch self {
        case .aacLC: return "AAC-LC"
        case .heAAC: return "HE-AAC (AACplus)"
        case .heAACv2: return "HE-AACv2"
        case .xheAAC: return "xHE-AAC (USAC)"
        case .ac3: return "Dolby Digital (AC-3)"
        case .eac3: return "Dolby Digital Plus (E-AC-3)"
        case .trueHD: return "Dolby TrueHD"
        case .ac4: return "Dolby AC-4"
        case .dts: return "DTS"
        case .dtsHD: return "DTS-HD Master Audio"
        case .dtsX: return "DTS:X"
        case .pcm: return "PCM (Uncompressed)"
        case .mp3: return "MP3"
        case .mp2: return "MP2"
        case .flac: return "FLAC"
        case .alac: return "ALAC (Apple Lossless)"
        case .opus: return "Opus"
        case .vorbis: return "Vorbis"
        case .speex: return "Speex"
        case .dsd: return "DSD"
        case .wavpack: return "WavPack"
        case .mqa: return "MQA"
        case .musepack: return "Musepack"
        case .ape: return "APE (Monkey's Audio)"
        case .tta: return "TTA (True Audio)"
        case .wma: return "WMA"
        case .atrac: return "ATRAC"
        }
    }

    /// Whether this codec is lossless.
    public var isLossless: Bool {
        switch self {
        case .pcm, .flac, .alac, .dsd, .wavpack, .ape, .tta, .trueHD, .dtsHD:
            return true
        default:
            return false
        }
    }

    /// Maximum channel count supported by this codec.
    public var maxChannels: Int {
        switch self {
        case .mp3, .heAACv2, .speex:
            return 2 // Stereo only
        case .ac3:
            return 6 // 5.1
        case .dts:
            return 6 // 5.1
        case .aacLC, .heAAC, .xheAAC, .eac3, .flac, .alac, .opus, .vorbis, .trueHD, .dtsHD, .dtsX, .wavpack:
            return 8 // Up to 7.1
        case .pcm, .dsd:
            return 64 // Practically unlimited
        default:
            return 2
        }
    }

    /// Whether this codec supports Variable Bitrate encoding.
    public var supportsVBR: Bool {
        switch self {
        case .aacLC, .heAAC, .heAACv2, .xheAAC, .mp3, .vorbis, .opus, .wavpack:
            return true
        case .ac3, .eac3, .dts:
            return false // CBR only
        default:
            return false
        }
    }

    /// Whether FFmpeg can encode this codec.
    public var canEncode: Bool {
        return ffmpegEncoder != nil
    }
}
