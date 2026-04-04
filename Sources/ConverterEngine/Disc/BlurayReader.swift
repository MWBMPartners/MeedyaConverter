// ============================================================================
// MeedyaConverter — BlurayReader
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - BlurayPlaylist

/// A playlist (MPLS) on a Blu-ray disc.
public struct BlurayPlaylist: Codable, Sendable {
    /// Playlist number.
    public var number: Int

    /// Playlist filename (e.g., "00800.mpls").
    public var filename: String

    /// Duration in seconds.
    public var duration: TimeInterval

    /// Number of chapters / play items.
    public var chapterCount: Int

    /// Chapter marks.
    public var chapters: [DiscChapter]

    /// Number of clip files referenced.
    public var clipCount: Int

    /// Clip filenames (e.g., ["00001.m2ts", "00002.m2ts"]).
    public var clipFiles: [String]

    /// Video streams.
    public var videoStreams: [BlurayVideoStream]

    /// Audio streams.
    public var audioStreams: [DiscAudioStream]

    /// Subtitle streams (PGS).
    public var subtitleStreams: [DiscSubtitleStream]

    /// Total estimated size in bytes.
    public var sizeBytes: Int64

    /// Whether this appears to be the main feature playlist.
    public var isMainFeature: Bool

    public init(
        number: Int,
        filename: String = "",
        duration: TimeInterval = 0,
        chapterCount: Int = 0,
        chapters: [DiscChapter] = [],
        clipCount: Int = 0,
        clipFiles: [String] = [],
        videoStreams: [BlurayVideoStream] = [],
        audioStreams: [DiscAudioStream] = [],
        subtitleStreams: [DiscSubtitleStream] = [],
        sizeBytes: Int64 = 0,
        isMainFeature: Bool = false
    ) {
        self.number = number
        self.filename = filename
        self.duration = duration
        self.chapterCount = chapterCount
        self.chapters = chapters
        self.clipCount = clipCount
        self.clipFiles = clipFiles
        self.videoStreams = videoStreams
        self.audioStreams = audioStreams
        self.subtitleStreams = subtitleStreams
        self.sizeBytes = sizeBytes
        self.isMainFeature = isMainFeature
    }
}

// MARK: - BlurayVideoStream

/// A video stream on a Blu-ray disc.
public struct BlurayVideoStream: Codable, Sendable {
    /// Stream index.
    public var index: Int

    /// Codec (e.g., "H.264", "H.265", "VC-1", "MPEG-2").
    public var codec: String

    /// Resolution width.
    public var width: Int

    /// Resolution height.
    public var height: Int

    /// Frame rate (e.g., 23.976, 24.0, 29.97, 59.94).
    public var frameRate: Double

    /// Whether this is interlaced.
    public var isInterlaced: Bool

    /// Whether this is HDR (for UHD Blu-ray).
    public var isHDR: Bool

    /// HDR format (e.g., "HDR10", "Dolby Vision", "HDR10+").
    public var hdrFormat: String?

    /// Color bit depth (8, 10, 12).
    public var bitDepth: Int

    public init(
        index: Int = 0,
        codec: String = "H.264",
        width: Int = 1920,
        height: Int = 1080,
        frameRate: Double = 23.976,
        isInterlaced: Bool = false,
        isHDR: Bool = false,
        hdrFormat: String? = nil,
        bitDepth: Int = 8
    ) {
        self.index = index
        self.codec = codec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.isInterlaced = isInterlaced
        self.isHDR = isHDR
        self.hdrFormat = hdrFormat
        self.bitDepth = bitDepth
    }

    /// Whether this is a 4K UHD stream.
    public var isUHD: Bool {
        width >= 3840 || height >= 2160
    }
}

// MARK: - BlurayProtection

/// Blu-ray copy protection information.
public struct BlurayProtection: Codable, Sendable {
    /// Whether AACS encryption is present.
    public var hasAACS: Bool

    /// Whether BD+ protection is present.
    public var hasBDPlus: Bool

    /// Whether UHD AACS 2.0 is present.
    public var hasAACS2: Bool

    /// AACS MKB version.
    public var aacsMKBVersion: Int?

    /// Whether Bus Encryption (HDCP) is required.
    public var requiresHDCP: Bool

    /// Whether a valid AACS key file was found.
    public var hasKeyFile: Bool

    public init(
        hasAACS: Bool = false,
        hasBDPlus: Bool = false,
        hasAACS2: Bool = false,
        aacsMKBVersion: Int? = nil,
        requiresHDCP: Bool = false,
        hasKeyFile: Bool = false
    ) {
        self.hasAACS = hasAACS
        self.hasBDPlus = hasBDPlus
        self.hasAACS2 = hasAACS2
        self.aacsMKBVersion = aacsMKBVersion
        self.requiresHDCP = requiresHDCP
        self.hasKeyFile = hasKeyFile
    }

    /// Whether decryption keys are available for this disc.
    public var canDecrypt: Bool {
        if hasAACS2 { return false } // AACS 2.0 not crackable
        if hasAACS && !hasKeyFile { return false }
        return true
    }
}

// MARK: - BlurayReader

/// Builds command-line arguments for Blu-ray disc ripping using
/// libbluray and FFmpeg.
///
/// Supports:
/// - BDMV structure parsing and playlist enumeration
/// - Main feature detection via duration heuristic
/// - AACS/BD+ decryption awareness
/// - M2TS stream remuxing
/// - TrueHD, DTS-HD MA, Atmos, DTS:X passthrough
/// - HDR10/Dolby Vision metadata preservation
/// - UHD Blu-ray (4K) support
///
/// Phase 8.9
public struct BlurayReader: Sendable {

    // MARK: - FFmpeg Blu-ray Arguments

    /// Build FFmpeg arguments to rip a Blu-ray playlist.
    ///
    /// Uses the bluray protocol with libbluray for decrypted reading.
    ///
    /// - Parameters:
    ///   - devicePath: Blu-ray device, mount, or disc image path.
    ///   - playlistNumber: Playlist to rip (e.g., 800 for 00800.mpls).
    ///   - outputPath: Output file path (e.g., .mkv).
    ///   - audioStreams: Audio stream indices to include (nil = all).
    ///   - subtitleStreams: Subtitle stream indices to include (nil = all).
    /// - Returns: FFmpeg argument array.
    public static func buildRipArguments(
        devicePath: String,
        playlistNumber: Int,
        outputPath: String,
        audioStreams: [Int]? = nil,
        subtitleStreams: [Int]? = nil
    ) -> [String] {
        var args: [String] = []

        // Input: use bluray protocol
        args += ["-playlist", "\(playlistNumber)"]
        args += ["-i", "bluray:\(devicePath)"]

        // Map video
        args += ["-map", "0:v"]

        // Map audio
        if let audioIndices = audioStreams {
            for idx in audioIndices {
                args += ["-map", "0:a:\(idx)"]
            }
        } else {
            args += ["-map", "0:a"]
        }

        // Map subtitles (PGS)
        if let subIndices = subtitleStreams {
            for idx in subIndices {
                args += ["-map", "0:s:\(idx)"]
            }
        } else {
            args += ["-map", "0:s?"]
        }

        // Copy all streams
        args += ["-c", "copy"]

        args += ["-y", outputPath]

        return args
    }

    /// Build FFmpeg arguments to rip a specific M2TS clip.
    ///
    /// - Parameters:
    ///   - m2tsPath: Direct path to the .m2ts file.
    ///   - outputPath: Output file path.
    /// - Returns: FFmpeg argument array.
    public static func buildM2TSRipArguments(
        m2tsPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", m2tsPath,
            "-map", "0",
            "-c", "copy",
            "-y", outputPath,
        ]
    }

    // MARK: - BDMV Structure

    /// Expected BDMV directory structure paths.
    ///
    /// - Parameter basePath: Blu-ray root path.
    /// - Returns: Dictionary of expected directories.
    public static func bdmvPaths(from basePath: String) -> [String: String] {
        let bdmv = (basePath as NSString).appendingPathComponent("BDMV")
        return [
            "bdmv": bdmv,
            "stream": (bdmv as NSString).appendingPathComponent("STREAM"),
            "playlist": (bdmv as NSString).appendingPathComponent("PLAYLIST"),
            "clipinf": (bdmv as NSString).appendingPathComponent("CLIPINF"),
            "backup": (bdmv as NSString).appendingPathComponent("BACKUP"),
            "index": (bdmv as NSString).appendingPathComponent("index.bdmv"),
            "movieObject": (bdmv as NSString).appendingPathComponent("MovieObject.bdmv"),
        ]
    }

    /// Build the MPLS (playlist) file path.
    ///
    /// - Parameters:
    ///   - basePath: Blu-ray root path.
    ///   - playlistNumber: Playlist number.
    /// - Returns: Path to the MPLS file.
    public static func mplsFilePath(
        basePath: String,
        playlistNumber: Int
    ) -> String {
        let filename = String(format: "%05d.mpls", playlistNumber)
        let bdmv = (basePath as NSString).appendingPathComponent("BDMV")
        let playlist = (bdmv as NSString).appendingPathComponent("PLAYLIST")
        return (playlist as NSString).appendingPathComponent(filename)
    }

    /// Build the M2TS (stream) file path.
    ///
    /// - Parameters:
    ///   - basePath: Blu-ray root path.
    ///   - clipNumber: Clip number.
    /// - Returns: Path to the M2TS file.
    public static func m2tsFilePath(
        basePath: String,
        clipNumber: Int
    ) -> String {
        let filename = String(format: "%05d.m2ts", clipNumber)
        let bdmv = (basePath as NSString).appendingPathComponent("BDMV")
        let stream = (bdmv as NSString).appendingPathComponent("STREAM")
        return (stream as NSString).appendingPathComponent(filename)
    }

    // MARK: - Main Feature Detection

    /// Detect the main feature playlist from a list of playlists.
    ///
    /// Uses duration-based heuristic: the main feature is typically
    /// the longest playlist that is > 60 minutes.
    ///
    /// - Parameter playlists: Array of Blu-ray playlists.
    /// - Returns: The main feature playlist, or nil.
    public static func detectMainFeature(
        playlists: [BlurayPlaylist]
    ) -> BlurayPlaylist? {
        let candidates = playlists.filter { $0.duration > 3600 } // > 1 hour

        if let best = candidates.max(by: { $0.duration < $1.duration }) {
            return best
        }

        return playlists.max(by: { $0.duration < $1.duration })
    }

    // MARK: - HDR Metadata

    /// Build FFmpeg arguments to preserve HDR10 metadata during remux.
    ///
    /// - Returns: Additional FFmpeg arguments for HDR preservation.
    public static func buildHDR10PreservationArguments() -> [String] {
        return [
            "-color_primaries", "bt2020",
            "-color_trc", "smpte2084",
            "-colorspace", "bt2020nc",
        ]
    }

    /// Build FFmpeg arguments to extract Dolby Vision RPU data.
    ///
    /// Dolby Vision metadata is stored as a separate enhancement layer
    /// that must be preserved during remuxing.
    ///
    /// - Parameters:
    ///   - inputPath: Input file with DV metadata.
    ///   - rpuOutputPath: Output path for extracted RPU data.
    /// - Returns: FFmpeg argument array.
    public static func buildDolbyVisionExtractArguments(
        inputPath: String,
        rpuOutputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:v", "copy",
            "-vbsf", "hevc_mp4toannexb",
            "-f", "hevc",
            "-y", rpuOutputPath,
        ]
    }

    // MARK: - AACS Key File

    /// Expected AACS key file locations.
    public static let aacsKeyFilePaths: [String] = [
        "~/.config/aacs/KEYDB.cfg",
        "~/KEYDB.cfg",
        "/etc/aacs/KEYDB.cfg",
    ]

    /// Expected libaacs library paths (macOS).
    public static let libaacsPathsMacOS: [String] = [
        "/usr/local/lib/libaacs.dylib",
        "/opt/homebrew/lib/libaacs.dylib",
    ]

    /// Expected libaacs library paths (Linux).
    public static let libaacsPathsLinux: [String] = [
        "/usr/lib/libaacs.so",
        "/usr/lib/x86_64-linux-gnu/libaacs.so",
        "/usr/lib/aarch64-linux-gnu/libaacs.so",
    ]

    // MARK: - Disc Type Detection

    /// Determine if a Blu-ray is a UHD (4K) disc based on video streams.
    ///
    /// - Parameter videoStreams: Video streams from the main playlist.
    /// - Returns: `true` if any stream is 4K UHD.
    public static func isUHDDisc(videoStreams: [BlurayVideoStream]) -> Bool {
        return videoStreams.contains { $0.isUHD }
    }

    /// Determine if a Blu-ray has HDR content.
    ///
    /// - Parameter videoStreams: Video streams from the main playlist.
    /// - Returns: `true` if any stream is HDR.
    public static func hasHDRContent(videoStreams: [BlurayVideoStream]) -> Bool {
        return videoStreams.contains { $0.isHDR }
    }

    /// Common Blu-ray audio codec identifiers and their display names.
    public static let audioCodecNames: [String: String] = [
        "A_TRUEHD": "Dolby TrueHD",
        "A_DTS-HD.MA": "DTS-HD Master Audio",
        "A_DTS-HD.HRA": "DTS-HD High Resolution Audio",
        "A_DTS": "DTS",
        "A_AC3": "Dolby Digital (AC-3)",
        "A_EAC3": "Dolby Digital Plus (E-AC-3)",
        "A_LPCM": "LPCM",
    ]
}
