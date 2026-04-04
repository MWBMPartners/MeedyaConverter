// ============================================================================
// MeedyaConverter — DiscAuthor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DiscImageFormat

/// Supported disc image output formats.
public enum DiscImageFormat: String, Codable, Sendable, CaseIterable {
    case iso = "iso"
    case bin = "bin"
    case img = "img"
    case mdf = "mdf"
    case nrg = "nrg"

    /// File extension.
    public var fileExtension: String { rawValue }

    /// Display name.
    public var displayName: String {
        switch self {
        case .iso: return "ISO 9660"
        case .bin: return "BIN/CUE"
        case .img: return "IMG"
        case .mdf: return "MDF/MDS"
        case .nrg: return "Nero Image"
        }
    }
}

// MARK: - DiscAuthorFormat

/// Target authoring format for disc creation.
public enum DiscAuthorFormat: String, Codable, Sendable, CaseIterable {
    case audioCd = "audio_cd"
    case dvdVideo = "dvd_video"
    case bluray = "bluray"
    case dataDisc = "data"
    case vcd = "vcd"
    case svcd = "svcd"

    /// Display name.
    public var displayName: String {
        switch self {
        case .audioCd: return "Audio CD"
        case .dvdVideo: return "DVD-Video"
        case .bluray: return "Blu-ray"
        case .dataDisc: return "Data Disc"
        case .vcd: return "Video CD"
        case .svcd: return "Super Video CD"
        }
    }

    /// Default disc capacity in bytes for this format.
    public var defaultCapacityBytes: Int64 {
        switch self {
        case .audioCd: return 737_280_000          // CD (80 min)
        case .dvdVideo: return 4_707_319_808       // DVD-5 (single layer)
        case .bluray: return 25_025_314_816        // BD-25 (single layer)
        case .dataDisc: return 4_707_319_808       // DVD-5
        case .vcd: return 737_280_000
        case .svcd: return 737_280_000
        }
    }
}

// MARK: - DiscCapacity

/// Physical disc capacity options.
public enum DiscCapacity: String, Codable, Sendable, CaseIterable {
    case cd700 = "cd_700"
    case dvd5 = "dvd_5"
    case dvd9 = "dvd_9"
    case bd25 = "bd_25"
    case bd50 = "bd_50"
    case bd100 = "bd_100"

    /// Display name.
    public var displayName: String {
        switch self {
        case .cd700: return "CD (700 MB)"
        case .dvd5: return "DVD-5 (4.7 GB)"
        case .dvd9: return "DVD-9 (8.5 GB)"
        case .bd25: return "BD-25 (25 GB)"
        case .bd50: return "BD-50 (50 GB)"
        case .bd100: return "BD-100 (100 GB)"
        }
    }

    /// Capacity in bytes.
    public var capacityBytes: Int64 {
        switch self {
        case .cd700: return 737_280_000
        case .dvd5: return 4_707_319_808
        case .dvd9: return 8_543_666_176
        case .bd25: return 25_025_314_816
        case .bd50: return 50_050_629_632
        case .bd100: return 100_000_000_000
        }
    }
}

// MARK: - AuthoringConfig

/// Configuration for a disc authoring operation.
public struct AuthoringConfig: Codable, Sendable {
    /// Target authoring format.
    public var format: DiscAuthorFormat

    /// Disc label / volume ID.
    public var volumeLabel: String

    /// Target disc capacity.
    public var capacity: DiscCapacity

    /// Source files to include.
    public var sourceFiles: [String]

    /// Output image format.
    public var imageFormat: DiscImageFormat

    /// Output directory.
    public var outputDirectory: String

    /// Whether to create a menu structure (DVD/Blu-ray).
    public var createMenu: Bool

    /// DVD video standard.
    public var videoStandard: DVDVideoStandard

    /// Whether to pad to fill the disc (for compatibility).
    public var padDisc: Bool

    public init(
        format: DiscAuthorFormat = .dvdVideo,
        volumeLabel: String = "DISC",
        capacity: DiscCapacity = .dvd5,
        sourceFiles: [String] = [],
        imageFormat: DiscImageFormat = .iso,
        outputDirectory: String = "",
        createMenu: Bool = false,
        videoStandard: DVDVideoStandard = .ntsc,
        padDisc: Bool = false
    ) {
        self.format = format
        self.volumeLabel = volumeLabel
        self.capacity = capacity
        self.sourceFiles = sourceFiles
        self.imageFormat = imageFormat
        self.outputDirectory = outputDirectory
        self.createMenu = createMenu
        self.videoStandard = videoStandard
        self.padDisc = padDisc
    }
}

// MARK: - DVDVideoStandard

/// DVD video broadcast standard.
public enum DVDVideoStandard: String, Codable, Sendable {
    case ntsc = "ntsc"
    case pal = "pal"

    /// Frame rate for this standard.
    public var frameRate: Double {
        switch self {
        case .ntsc: return 29.97
        case .pal: return 25.0
        }
    }

    /// Resolution for this standard.
    public var resolution: (width: Int, height: Int) {
        switch self {
        case .ntsc: return (720, 480)
        case .pal: return (720, 576)
        }
    }
}

// MARK: - DiscAuthor

/// Builds command-line arguments for disc authoring and image creation.
///
/// Supports:
/// - Audio CD authoring (Red Book)
/// - DVD-Video authoring (dvdauthor)
/// - Blu-ray authoring (tsMuxeR)
/// - ISO 9660 / UDF image creation (genisoimage/mkisofs)
/// - Capacity validation
///
/// Phase 9.1
public struct DiscAuthor: Sendable {

    // MARK: - DVD Authoring

    /// Build dvdauthor arguments for DVD-Video authoring.
    ///
    /// - Parameters:
    ///   - xmlConfigPath: Path to dvdauthor XML configuration file.
    ///   - outputDir: Output directory for the DVD structure.
    /// - Returns: Argument array for dvdauthor.
    public static func buildDVDAuthorArguments(
        xmlConfigPath: String,
        outputDir: String
    ) -> [String] {
        return ["-o", outputDir, "-x", xmlConfigPath]
    }

    /// Generate dvdauthor XML configuration.
    ///
    /// - Parameters:
    ///   - config: Authoring configuration.
    ///   - vobFiles: MPEG-2 VOB files to include.
    /// - Returns: XML configuration string.
    public static func generateDVDAuthorXML(
        config: AuthoringConfig,
        vobFiles: [String]
    ) -> String {
        var xml = "<dvdauthor dest=\"\(config.outputDirectory)\">\n"
        xml += "  <vmgm />\n"
        xml += "  <titleset>\n"
        xml += "    <titles>\n"
        xml += "      <video format=\"\(config.videoStandard.rawValue)\" />\n"
        xml += "      <pgc>\n"

        for vob in vobFiles {
            xml += "        <vob file=\"\(vob)\" />\n"
        }

        xml += "      </pgc>\n"
        xml += "    </titles>\n"
        xml += "  </titleset>\n"
        xml += "</dvdauthor>\n"

        return xml
    }

    /// Build FFmpeg arguments to prepare video for DVD authoring.
    ///
    /// DVD-Video requires MPEG-2 video with specific constraints.
    ///
    /// - Parameters:
    ///   - inputPath: Source video file.
    ///   - outputPath: Output MPEG-2 file (.mpg).
    ///   - standard: NTSC or PAL.
    ///   - bitrate: Video bitrate in kbps (default: 6000).
    /// - Returns: FFmpeg argument array.
    public static func buildDVDEncodeArguments(
        inputPath: String,
        outputPath: String,
        standard: DVDVideoStandard = .ntsc,
        bitrate: Int = 6000
    ) -> [String] {
        let res = standard.resolution
        var args: [String] = ["-i", inputPath]

        // Video: MPEG-2 for DVD
        args += ["-c:v", "mpeg2video"]
        args += ["-b:v", "\(bitrate)k"]
        args += ["-maxrate", "\(bitrate + 1500)k"]
        args += ["-bufsize", "1835k"]
        args += ["-vf", "scale=\(res.width):\(res.height),setsar=1"]

        // Frame rate
        if standard == .ntsc {
            args += ["-r", "29.97"]
        } else {
            args += ["-r", "25"]
        }

        // Audio: AC-3 for DVD
        args += ["-c:a", "ac3"]
        args += ["-b:a", "192k"]
        args += ["-ar", "48000"]

        // DVD MPEG-PS format
        args += ["-f", "dvd"]
        args += ["-muxrate", "10080000"]
        args += ["-packetsize", "2048"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - Audio CD Authoring

    /// Build FFmpeg arguments to prepare audio for CD burning.
    ///
    /// Red Book Audio CD requires 44.1kHz, 16-bit, stereo PCM.
    ///
    /// - Parameters:
    ///   - inputPath: Source audio file.
    ///   - outputPath: Output WAV file.
    /// - Returns: FFmpeg argument array.
    public static func buildAudioCDPrepareArguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:a", "pcm_s16le",
            "-ar", "44100",
            "-ac", "2",
            "-y", outputPath,
        ]
    }

    // MARK: - Blu-ray Authoring

    /// Build tsMuxeR meta file content for Blu-ray authoring.
    ///
    /// tsMuxeR creates compliant Blu-ray BDMV structures from
    /// H.264/H.265 video and supported audio streams.
    ///
    /// - Parameters:
    ///   - videoPath: Source H.264/H.265 video file.
    ///   - audioPaths: Source audio file paths.
    ///   - subtitlePaths: Source subtitle file paths (PGS/SUP).
    ///   - outputDir: Output BDMV directory.
    /// - Returns: tsMuxeR meta file content.
    public static func generateTsMuxeRMeta(
        videoPath: String,
        audioPaths: [String] = [],
        subtitlePaths: [String] = [],
        outputDir: String
    ) -> String {
        var meta = "MUXOPT --no-pcr-on-video-pid --new-audio-pes\n"

        // Video track
        meta += "V_MPEG4/ISO/AVC, \"\(videoPath)\", fps=23.976, insertSEI, contSPS\n"

        // Audio tracks
        for audioPath in audioPaths {
            let ext = (audioPath as NSString).pathExtension.lowercased()
            let codec: String
            switch ext {
            case "ac3": codec = "A_AC3"
            case "dts": codec = "A_DTS"
            case "eac3": codec = "A_EAC3"
            case "thd", "truehd": codec = "A_TRUEHD"
            case "flac": codec = "A_FLAC"
            default: codec = "A_LPCM"
            }
            meta += "\(codec), \"\(audioPath)\"\n"
        }

        // Subtitle tracks
        for subPath in subtitlePaths {
            meta += "S_HDMV/PGS, \"\(subPath)\"\n"
        }

        return meta
    }

    /// Build tsMuxeR arguments for Blu-ray structure creation.
    ///
    /// - Parameters:
    ///   - metaFilePath: Path to the tsMuxeR meta file.
    ///   - outputDir: Output BDMV directory.
    /// - Returns: Argument array for tsMuxeR.
    public static func buildTsMuxeRArguments(
        metaFilePath: String,
        outputDir: String
    ) -> [String] {
        return [metaFilePath, outputDir]
    }

    // MARK: - ISO Image Creation

    /// Build genisoimage/mkisofs arguments for ISO creation.
    ///
    /// - Parameters:
    ///   - config: Authoring configuration.
    ///   - sourceDir: Source directory to image.
    ///   - outputPath: Output ISO file path.
    /// - Returns: Argument array for genisoimage.
    public static func buildGenisoimageArguments(
        config: AuthoringConfig,
        sourceDir: String,
        outputPath: String
    ) -> [String] {
        var args: [String] = []

        // Volume label
        args += ["-V", config.volumeLabel]

        // Format-specific options
        switch config.format {
        case .dvdVideo:
            args += ["-dvd-video"]
            args += ["-udf"]
        case .bluray:
            args += ["-udf"]
            args += ["-allow-limited-size"]
        case .audioCd:
            // Audio CDs don't use ISO format
            break
        default:
            args += ["-J"]  // Joliet extensions
            args += ["-R"]  // Rock Ridge extensions
        }

        args += ["-o", outputPath]
        args.append(sourceDir)

        return args
    }

    /// Build growisofs arguments for direct DVD burning.
    ///
    /// - Parameters:
    ///   - devicePath: DVD writer device path.
    ///   - isoPath: ISO image to burn.
    ///   - speed: Write speed (nil = auto).
    /// - Returns: Argument array for growisofs.
    public static func buildGrowisofsArguments(
        devicePath: String,
        isoPath: String,
        speed: Int? = nil
    ) -> [String] {
        var args: [String] = []

        if let s = speed {
            args += ["-speed=\(s)"]
        }

        args += ["-dvd-compat"]
        args += ["-Z", "\(devicePath)=\(isoPath)"]

        return args
    }

    // MARK: - Capacity Validation

    /// Validate that source content fits on the target disc.
    ///
    /// - Parameters:
    ///   - totalSizeBytes: Total size of content in bytes.
    ///   - capacity: Target disc capacity.
    /// - Returns: Validation result with details.
    public static func validateCapacity(
        totalSizeBytes: Int64,
        capacity: DiscCapacity
    ) -> CapacityValidation {
        let available = capacity.capacityBytes
        let usedPercent = Double(totalSizeBytes) / Double(available) * 100.0
        let fits = totalSizeBytes <= available
        let remainingBytes = available - totalSizeBytes

        return CapacityValidation(
            fits: fits,
            totalSizeBytes: totalSizeBytes,
            capacityBytes: available,
            usedPercent: usedPercent,
            remainingBytes: remainingBytes
        )
    }
}

// MARK: - CapacityValidation

/// Result of disc capacity validation.
public struct CapacityValidation: Codable, Sendable {
    /// Whether the content fits on the disc.
    public var fits: Bool

    /// Total content size in bytes.
    public var totalSizeBytes: Int64

    /// Disc capacity in bytes.
    public var capacityBytes: Int64

    /// Percentage of disc used.
    public var usedPercent: Double

    /// Remaining bytes (negative if doesn't fit).
    public var remainingBytes: Int64

    public init(
        fits: Bool,
        totalSizeBytes: Int64,
        capacityBytes: Int64,
        usedPercent: Double,
        remainingBytes: Int64
    ) {
        self.fits = fits
        self.totalSizeBytes = totalSizeBytes
        self.capacityBytes = capacityBytes
        self.usedPercent = usedPercent
        self.remainingBytes = remainingBytes
    }

    /// Human-readable summary.
    public var summary: String {
        let usedMB = totalSizeBytes / (1024 * 1024)
        let totalMB = capacityBytes / (1024 * 1024)
        if fits {
            return "Content (\(usedMB) MB) fits on disc (\(totalMB) MB) — \(String(format: "%.1f", usedPercent))% used"
        } else {
            let overMB = abs(remainingBytes) / (1024 * 1024)
            return "Content (\(usedMB) MB) exceeds disc capacity (\(totalMB) MB) by \(overMB) MB"
        }
    }
}
