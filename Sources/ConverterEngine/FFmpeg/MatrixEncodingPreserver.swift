// ============================================================================
// MeedyaConverter — MatrixEncodingPreserver
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MatrixEncoding

/// Recognised surround sound matrix encoding formats embedded in stereo tracks.
public enum MatrixEncoding: String, Codable, Sendable, CaseIterable {
    /// Dolby Surround (passive matrix, 1982).
    case dolbySurround = "dolby_surround"

    /// Dolby Pro Logic (enhanced decoder, 1987).
    case dolbyProLogic = "dolby_prologic"

    /// Dolby Pro Logic II (high-fidelity 5.1 from stereo, 2000).
    case dolbyProLogicII = "dolby_prologic_ii"

    /// Dolby Pro Logic IIx (7.1 from stereo/5.1, 2003).
    case dolbyProLogicIIx = "dolby_prologic_iix"

    /// Dolby Pro Logic IIz (height channels, 2009).
    case dolbyProLogicIIz = "dolby_prologic_iiz"

    /// DTS Neo:6 (5.1/7.1 from stereo, 2001).
    case dtsNeo6 = "dts_neo6"

    /// DTS Neo:X (11.1 from stereo/5.1/7.1, 2012).
    case dtsNeoX = "dts_neox"

    /// DTS Virtual:X (virtualised immersive from stereo, 2017).
    case dtsVirtualX = "dts_virtualx"

    /// Circle Surround (SRS Labs, 1998).
    case circleSurround = "circle_surround"

    /// Auro-Matic (height upmix, 2012).
    case auroMatic = "auro_matic"

    /// None / no matrix encoding detected.
    case none = "none"

    /// Display name.
    public var displayName: String {
        switch self {
        case .dolbySurround: return "Dolby Surround"
        case .dolbyProLogic: return "Dolby Pro Logic"
        case .dolbyProLogicII: return "Dolby Pro Logic II"
        case .dolbyProLogicIIx: return "Dolby Pro Logic IIx"
        case .dolbyProLogicIIz: return "Dolby Pro Logic IIz"
        case .dtsNeo6: return "DTS Neo:6"
        case .dtsNeoX: return "DTS Neo:X"
        case .dtsVirtualX: return "DTS Virtual:X"
        case .circleSurround: return "Circle Surround"
        case .auroMatic: return "Auro-Matic"
        case .none: return "None"
        }
    }

    /// Whether this encoding can be decoded to discrete surround.
    public var isDecodable: Bool {
        switch self {
        case .dolbySurround, .dolbyProLogic, .dolbyProLogicII,
             .dolbyProLogicIIx, .dtsNeo6:
            return true
        default:
            return false
        }
    }

    /// Number of surround channels this encoding can decode to.
    public var maxDecodeChannels: Int {
        switch self {
        case .dolbySurround: return 4 // L, C, R, S
        case .dolbyProLogic: return 5 // L, C, R, LS, RS (shared back)
        case .dolbyProLogicII: return 6 // 5.1
        case .dolbyProLogicIIx: return 8 // 7.1
        case .dolbyProLogicIIz: return 10 // 7.1 + height
        case .dtsNeo6: return 7 // 6.1
        case .dtsNeoX: return 12 // 11.1
        case .dtsVirtualX: return 8 // virtual 7.1
        case .circleSurround: return 7 // 6.1
        case .auroMatic: return 14 // 13.1
        case .none: return 2
        }
    }
}

// MARK: - MatrixEncodingPreserver

/// Preserves and manages matrix-encoded surround information during transcoding.
///
/// When transcoding stereo audio that contains matrix-encoded surround (e.g.,
/// Dolby Pro Logic II in a stereo AAC track from a DVD rip), this struct
/// ensures the matrix encoding metadata is preserved in the output.
///
/// Phase 5.14
public struct MatrixEncodingPreserver: Sendable {

    // MARK: - Detection

    /// Build FFmpeg/FFprobe arguments to detect matrix encoding.
    ///
    /// Uses the astats filter to analyze channel correlation patterns
    /// that indicate matrix encoding.
    ///
    /// - Parameters:
    ///   - inputPath: Source audio file.
    ///   - streamIndex: Audio stream index.
    ///   - duration: Duration to analyse in seconds.
    /// - Returns: FFmpeg argument array.
    public static func buildDetectionArguments(
        inputPath: String,
        streamIndex: Int = 0,
        duration: Double = 30
    ) -> [String] {
        return [
            "-i", inputPath,
            "-map", "0:a:\(streamIndex)",
            "-t", "\(duration)",
            "-af", "astats=metadata=1:reset=1",
            "-f", "null",
            "-",
        ]
    }

    /// Build FFprobe arguments to read matrix encoding metadata.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - streamIndex: Audio stream index.
    /// - Returns: FFprobe argument array.
    public static func buildProbeArguments(
        inputPath: String,
        streamIndex: Int = 0
    ) -> [String] {
        return [
            "-v", "quiet",
            "-select_streams", "a:\(streamIndex)",
            "-show_entries", "stream_tags=ENCODER,encoder,ENCODING,encoding",
            "-show_entries", "stream_side_data=downmix_matrix",
            "-print_format", "json",
            inputPath,
        ]
    }

    /// Detect matrix encoding from audio metadata strings.
    ///
    /// - Parameter metadataString: Audio encoding metadata.
    /// - Returns: Detected matrix encoding.
    public static func detectFromMetadata(_ metadataString: String?) -> MatrixEncoding {
        guard let meta = metadataString?.lowercased() else { return .none }

        if meta.contains("pro logic ii") || meta.contains("prologic ii") || meta.contains("plii") {
            if meta.contains("iix") || meta.contains("2x") {
                return .dolbyProLogicIIx
            }
            if meta.contains("iiz") || meta.contains("2z") {
                return .dolbyProLogicIIz
            }
            return .dolbyProLogicII
        }

        if meta.contains("pro logic") || meta.contains("prologic") {
            return .dolbyProLogic
        }

        if meta.contains("dolby surround") || meta.contains("dolby sr") {
            return .dolbySurround
        }

        if meta.contains("neo:6") || meta.contains("neo6") {
            return .dtsNeo6
        }

        if meta.contains("neo:x") || meta.contains("neox") {
            return .dtsNeoX
        }

        if meta.contains("virtual:x") || meta.contains("virtualx") {
            return .dtsVirtualX
        }

        if meta.contains("circle surround") {
            return .circleSurround
        }

        return .none
    }

    // MARK: - Preservation

    /// Build FFmpeg arguments to preserve matrix encoding metadata during transcode.
    ///
    /// - Parameters:
    ///   - encoding: Detected matrix encoding.
    ///   - streamIndex: Audio stream index in output.
    /// - Returns: FFmpeg argument array.
    public static func buildPreservationArguments(
        encoding: MatrixEncoding,
        streamIndex: Int = 0
    ) -> [String] {
        guard encoding != .none else { return [] }

        var args: [String] = []

        // Set the encoding_mode metadata
        args += ["-metadata:s:a:\(streamIndex)", "ENCODING=\(encoding.displayName)"]

        // For Dolby Surround/Pro Logic, set the downmix mode
        switch encoding {
        case .dolbySurround, .dolbyProLogic:
            args += ["-metadata:s:a:\(streamIndex)", "DOWNMIX_TYPE=Lt/Rt"]
        case .dolbyProLogicII, .dolbyProLogicIIx, .dolbyProLogicIIz:
            args += ["-metadata:s:a:\(streamIndex)", "DOWNMIX_TYPE=Dolby Pro Logic II"]
        case .dtsNeo6, .dtsNeoX:
            args += ["-metadata:s:a:\(streamIndex)", "DOWNMIX_TYPE=DTS Matrix"]
        default:
            break
        }

        return args
    }

    /// Build FFmpeg filter arguments for matrix decode (stereo → surround).
    ///
    /// - Parameters:
    ///   - encoding: Matrix encoding to decode.
    ///   - targetChannels: Target channel count (6 for 5.1, 8 for 7.1).
    /// - Returns: FFmpeg audio filter string (or nil if not decodable).
    public static func buildDecodeFilter(
        encoding: MatrixEncoding,
        targetChannels: Int = 6
    ) -> String? {
        switch encoding {
        case .dolbyProLogicII:
            // Pro Logic II decode using pan filter coefficients
            if targetChannels >= 6 {
                return "pan=5.1|FL=FL+0.707*FC-0.707*BL|FR=FR+0.707*FC+0.707*BR|FC=0.707*FL+0.707*FR|LFE=0|BL=0.707*FL-0.707*FR|BR=-0.707*FL+0.707*FR"
            }
            return nil

        case .dolbySurround, .dolbyProLogic:
            // Basic Dolby Surround decode (L, C, R, S)
            return "pan=5.1|FL=FL|FR=FR|FC=0.707*FL+0.707*FR|LFE=0|BL=0.5*FL-0.5*FR|BR=0.5*FL-0.5*FR"

        case .dtsNeo6:
            // DTS Neo:6 approximation
            if targetChannels >= 6 {
                return "pan=5.1|FL=FL|FR=FR|FC=0.707*FL+0.707*FR|LFE=0|BL=0.866*FL-0.5*FR|BR=-0.5*FL+0.866*FR"
            }
            return nil

        default:
            return nil
        }
    }

    /// Build complete FFmpeg arguments for matrix-aware transcode.
    ///
    /// If matrix encoding is detected, preserves the metadata. Optionally
    /// decodes to discrete surround channels.
    ///
    /// - Parameters:
    ///   - encoding: Detected matrix encoding.
    ///   - decode: Whether to decode to discrete surround.
    ///   - targetChannels: Target channel count for decode.
    ///   - streamIndex: Audio stream index.
    /// - Returns: FFmpeg argument array.
    public static func buildTranscodeArguments(
        encoding: MatrixEncoding,
        decode: Bool = false,
        targetChannels: Int = 6,
        streamIndex: Int = 0
    ) -> [String] {
        var args: [String] = []

        if decode, let filter = buildDecodeFilter(encoding: encoding, targetChannels: targetChannels) {
            args += ["-af", filter]
            args += ["-ac", "\(targetChannels)"]
        }

        // Always preserve metadata even when decoding
        args += buildPreservationArguments(encoding: encoding, streamIndex: streamIndex)

        return args
    }
}

// MARK: - TeletextExtractor

/// Builds FFmpeg arguments for DVB Teletext subtitle extraction and conversion.
///
/// Teletext is a broadcast data service embedded in the VBI (Vertical Blanking
/// Interval) of analog PAL/SECAM broadcasts, and in DVB-T/C/S digital streams.
/// Page 888 is the conventional subtitles page in most European regions.
///
/// Phase 5.5a
public struct TeletextExtractor: Sendable {

    /// Standard teletext subtitle page numbers by region.
    public static let subtitlePages: [String: Int] = [
        "uk": 888,
        "de": 150,
        "fr": 888,
        "it": 777,
        "es": 888,
        "nl": 888,
        "se": 199,
        "no": 777,
        "fi": 333,
        "dk": 398,
        "default": 888,
    ]

    /// Build FFmpeg arguments to extract teletext subtitles.
    ///
    /// - Parameters:
    ///   - inputPath: Source file with teletext stream.
    ///   - outputPath: Output subtitle file (e.g., .srt).
    ///   - page: Teletext page number (default 888).
    ///   - streamIndex: Teletext stream index.
    /// - Returns: FFmpeg argument array.
    public static func buildExtractArguments(
        inputPath: String,
        outputPath: String,
        page: Int = 888,
        streamIndex: Int = 0
    ) -> [String] {
        return [
            "-txt_page", "\(page)",
            "-i", inputPath,
            "-map", "0:s:\(streamIndex)",
            "-c:s", "srt",
            outputPath,
        ]
    }

    /// Build FFmpeg arguments to extract all teletext pages as separate files.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputDirectory: Directory for output files.
    ///   - pages: Pages to extract.
    /// - Returns: FFmpeg argument array.
    public static func buildMultiPageExtractArguments(
        inputPath: String,
        outputDirectory: String,
        pages: [Int]
    ) -> [String] {
        var args: [String] = ["-i", inputPath]
        for (index, page) in pages.enumerated() {
            args += ["-map", "0:s:0"]
            args += ["-c:s:\(index)", "srt"]
            args += ["-txt_page:\(index)", "\(page)"]
        }
        // Output paths
        for page in pages {
            args.append("\(outputDirectory)/teletext_page_\(page).srt")
        }
        return args
    }

    /// Build FFmpeg arguments to convert teletext to DVB subtitles.
    ///
    /// - Parameters:
    ///   - inputPath: Source file with teletext.
    ///   - outputPath: Output file with DVB subtitles.
    ///   - page: Teletext page.
    /// - Returns: FFmpeg argument array.
    public static func buildConvertToDVBArguments(
        inputPath: String,
        outputPath: String,
        page: Int = 888
    ) -> [String] {
        return [
            "-txt_page", "\(page)",
            "-i", inputPath,
            "-map", "0:v", "-map", "0:a", "-map", "0:s",
            "-c:v", "copy", "-c:a", "copy",
            "-c:s", "dvbsub",
            outputPath,
        ]
    }

    /// Build FFmpeg arguments to detect teletext streams in a file.
    ///
    /// - Parameter inputPath: Source file.
    /// - Returns: FFprobe argument array.
    public static func buildDetectArguments(inputPath: String) -> [String] {
        return [
            "-v", "quiet",
            "-select_streams", "s",
            "-show_entries", "stream=index,codec_name,codec_long_name",
            "-show_entries", "stream_tags=language",
            "-print_format", "json",
            inputPath,
        ]
    }

    /// Determine the likely subtitle page for a given country code.
    ///
    /// - Parameter countryCode: ISO 3166-1 alpha-2 country code (lowercase).
    /// - Returns: Teletext page number.
    public static func pageForCountry(_ countryCode: String) -> Int {
        return subtitlePages[countryCode.lowercased()] ?? subtitlePages["default"]!
    }

    /// Known teletext codec names in FFmpeg.
    public static let teletextCodecNames = [
        "dvb_teletext",
        "eia_608",     // US closed captions (similar concept)
        "teletext",
    ]
}
