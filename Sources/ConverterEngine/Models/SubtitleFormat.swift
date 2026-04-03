// ============================================================================
// MeedyaConverter — SubtitleFormat
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// MARK: - SubtitleFormat

/// Represents all supported subtitle and closed caption formats.
///
/// Subtitle formats fall into two categories:
/// - **Text-based**: SRT, TTML, WebVTT, SSA/ASS, etc. — easily editable and convertible.
/// - **Bitmap-based**: PGS, VobSub, DVB-SUB — image overlays that require OCR for text conversion.
public enum SubtitleFormat: String, Codable, Sendable, CaseIterable, Identifiable {

    // MARK: - Text-Based Formats

    /// SubRip Text — the most common text subtitle format.
    /// Simple timestamp + text format. Supports basic HTML formatting.
    case srt

    /// Timed Text Markup Language — XML-based subtitle format.
    /// Used in DASH streaming and broadcast (EBU-TT, IMSC).
    case ttml

    /// Web Video Text Tracks — W3C standard for web video subtitles.
    /// Used in HLS streaming. Supports CSS-like styling.
    case webVTT = "vtt"

    /// SubStation Alpha / Advanced SubStation Alpha — feature-rich subtitle format.
    /// Supports fonts, colours, positioning, animation, karaoke effects.
    case ssa

    /// Synchronized Accessible Media Interchange — Microsoft subtitle format.
    /// HTML-based, supports styling. Used in older Windows Media content.
    case sami

    /// LRC (Lyrics) — synchronised lyrics format for music.
    /// Supports Enhanced LRC (per-word timing) and Walaoke LRC.
    case lrc

    // MARK: - Closed Caption Formats

    /// CEA-608 (CC608) — legacy NTSC closed caption standard.
    /// Two-channel, limited character set. Still common in US broadcast.
    case cc608

    /// CEA-708 (EIA-708) — current US digital TV closed caption standard.
    /// Supports multiple languages, fonts, positioning, and styling.
    /// Previously known as EIA-708 before CEA standardisation.
    case cc708

    // MARK: - Bitmap-Based Formats

    /// DVB Subtitles — bitmap subtitle format used in European digital TV (DVB).
    /// Requires OCR for conversion to text-based formats.
    case dvbSub = "dvb_sub"

    /// Presentation Graphic Stream — Blu-ray bitmap subtitle format.
    /// High quality image-based subtitles. Requires OCR for text conversion.
    case pgs

    /// VobSub — DVD bitmap subtitle format stored as .sub/.idx file pairs.
    /// Requires OCR for conversion to text-based formats.
    case vobSub = "vob_sub"

    // MARK: - Broadcast / Professional Formats

    /// EBU Subtitling Data Exchange Format — European broadcast standard.
    /// Used in European TV production and distribution.
    case ebuSTL = "ebu_stl"

    /// Scenarist Closed Caption — professional caption format.
    /// Used in post-production for CEA-608/708 caption authoring.
    case scc

    /// MacCaption — professional caption format for macOS-based workflows.
    case mcc

    /// EBU Teletext / DVB Teletext — European broadcast text information system.
    /// Multiple pages carrying subtitles, news, weather, etc.
    /// Common in MPEG-TS recordings from European DVB broadcasts.
    case teletext

    // MARK: - Computed Properties

    /// A stable identifier for use with `Identifiable` conformance.
    public var id: String { rawValue }

    /// Whether this is a bitmap-based (image) subtitle format.
    /// Bitmap subtitles require OCR (e.g., Tesseract) to convert to text.
    public var isBitmap: Bool {
        switch self {
        case .dvbSub, .pgs, .vobSub:
            return true
        default:
            return false
        }
    }

    /// Whether this is a text-based subtitle format that can be directly edited.
    public var isText: Bool {
        return !isBitmap
    }

    /// Whether this format supports rich formatting (colours, fonts, positioning).
    public var supportsFormatting: Bool {
        switch self {
        case .ssa, .ttml, .webVTT, .sami, .cc708:
            return true
        case .pgs, .dvbSub, .vobSub:
            return true // Bitmap subs inherently support any visual styling
        default:
            return false
        }
    }

    /// A human-readable display name for this format.
    public var displayName: String {
        switch self {
        case .srt: return "SRT (SubRip)"
        case .ttml: return "TTML (Timed Text)"
        case .webVTT: return "WebVTT"
        case .ssa: return "SSA / ASS"
        case .sami: return "SAMI"
        case .lrc: return "LRC (Lyrics)"
        case .cc608: return "CC608 (CEA-608)"
        case .cc708: return "CEA-708 (EIA-708)"
        case .dvbSub: return "DVB-SUB"
        case .pgs: return "PGS (Blu-ray)"
        case .vobSub: return "VobSub (DVD)"
        case .ebuSTL: return "EBU STL"
        case .scc: return "SCC (Scenarist)"
        case .mcc: return "MCC (MacCaption)"
        case .teletext: return "Teletext (EBU/DVB)"
        }
    }

    /// The common file extension for standalone subtitle files of this format.
    public var fileExtension: String {
        switch self {
        case .srt: return "srt"
        case .ttml: return "ttml"
        case .webVTT: return "vtt"
        case .ssa: return "ass"
        case .sami: return "smi"
        case .lrc: return "lrc"
        case .cc608: return "scc"
        case .cc708: return "scc"
        case .dvbSub: return "sub"
        case .pgs: return "sup"
        case .vobSub: return "sub"
        case .ebuSTL: return "stl"
        case .scc: return "scc"
        case .mcc: return "mcc"
        case .teletext: return "txt"
        }
    }
}
