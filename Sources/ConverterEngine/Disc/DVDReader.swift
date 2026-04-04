// ============================================================================
// MeedyaConverter — DVDReader
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DVDStructure

/// Parsed structure of a DVD-Video disc.
public struct DVDStructure: Codable, Sendable {
    /// Volume identifier.
    public var volumeId: String?

    /// Total disc size in bytes.
    public var totalSizeBytes: Int64

    /// Number of video title sets (VTS).
    public var titleSetCount: Int

    /// Titles found on the disc.
    public var titles: [DiscTitle]

    /// Whether the disc uses CSS encryption.
    public var isCSSEncrypted: Bool

    /// Region mask (bitmask, 0xFF = region-free).
    public var regionMask: UInt8

    /// List of VOB files found.
    public var vobFiles: [String]

    /// Path to the VIDEO_TS directory.
    public var videoTSPath: String?

    public init(
        volumeId: String? = nil,
        totalSizeBytes: Int64 = 0,
        titleSetCount: Int = 0,
        titles: [DiscTitle] = [],
        isCSSEncrypted: Bool = false,
        regionMask: UInt8 = 0xFF,
        vobFiles: [String] = [],
        videoTSPath: String? = nil
    ) {
        self.volumeId = volumeId
        self.totalSizeBytes = totalSizeBytes
        self.titleSetCount = titleSetCount
        self.titles = titles
        self.isCSSEncrypted = isCSSEncrypted
        self.regionMask = regionMask
        self.vobFiles = vobFiles
        self.videoTSPath = videoTSPath
    }

    /// Regions this disc is locked to (empty = region-free).
    public var regions: [Int] {
        var result: [Int] = []
        for i in 0..<8 {
            // Inverted mask: bit 0 = region blocked
            if regionMask & (1 << i) == 0 {
                result.append(i + 1)
            }
        }
        return result
    }

    /// The title with the longest duration (likely the main feature).
    public var mainFeatureTitle: DiscTitle? {
        titles.max(by: { $0.duration < $1.duration })
    }
}

// MARK: - DVDReader

/// Builds command-line arguments for DVD-Video ripping using
/// libdvdread, libdvdnav, and FFmpeg.
///
/// Supports:
/// - VIDEO_TS structure parsing and title enumeration
/// - CSS decryption via libdvdcss
/// - VOB demuxing and concatenation
/// - Chapter extraction
/// - Multi-angle support
/// - Region code detection
///
/// Phase 8.7
public struct DVDReader: Sendable {

    // MARK: - FFmpeg DVD Arguments

    /// Build FFmpeg arguments to rip a DVD title directly.
    ///
    /// Uses the dvdnav protocol for decrypted reading.
    ///
    /// - Parameters:
    ///   - devicePath: DVD device or ISO image path.
    ///   - titleNumber: Title to rip (1-based).
    ///   - outputPath: Output file path (e.g., .mkv).
    ///   - audioStreams: Audio stream indices to include (nil = all).
    ///   - subtitleStreams: Subtitle stream indices to include (nil = all).
    ///   - angle: Video angle (1-based, nil = default).
    /// - Returns: FFmpeg argument array.
    public static func buildRipArguments(
        devicePath: String,
        titleNumber: Int,
        outputPath: String,
        audioStreams: [Int]? = nil,
        subtitleStreams: [Int]? = nil,
        angle: Int? = nil
    ) -> [String] {
        var args: [String] = []

        // Input: use dvdnav protocol for navigation-aware reading
        var inputURL = "dvd://\(titleNumber)"
        args += ["-dvd-device", devicePath]

        if let a = angle {
            inputURL += "#\(a)"
        }

        args += ["-i", inputURL]

        // Stream mapping
        args += ["-map", "0:v:0"] // Primary video

        if let audioIndices = audioStreams {
            for idx in audioIndices {
                args += ["-map", "0:a:\(idx)"]
            }
        } else {
            args += ["-map", "0:a"] // All audio
        }

        if let subIndices = subtitleStreams {
            for idx in subIndices {
                args += ["-map", "0:s:\(idx)"]
            }
        } else {
            args += ["-map", "0:s?"] // All subtitles (optional)
        }

        // Copy streams without re-encoding
        args += ["-c", "copy"]

        args += ["-y", outputPath]

        return args
    }

    /// Build FFmpeg arguments to concatenate VOB files into a single stream.
    ///
    /// - Parameters:
    ///   - vobFiles: Ordered list of VOB file paths.
    ///   - outputPath: Output file path.
    /// - Returns: FFmpeg argument array using concat protocol.
    public static func buildVOBConcatArguments(
        vobFiles: [String],
        outputPath: String
    ) -> [String] {
        guard !vobFiles.isEmpty else { return [] }

        var args: [String] = []

        // Use concat protocol
        let concatInput = "concat:" + vobFiles.joined(separator: "|")
        args += ["-i", concatInput]

        // Copy all streams
        args += ["-map", "0"]
        args += ["-c", "copy"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - lsdvd Arguments

    /// Build lsdvd arguments for disc structure enumeration.
    ///
    /// lsdvd reads the IFO files to enumerate titles, chapters,
    /// audio tracks, and subtitles.
    ///
    /// - Parameters:
    ///   - devicePath: DVD device or mount path.
    ///   - outputFormat: Output format ("json" or "xml").
    /// - Returns: Argument array for lsdvd.
    public static func buildLsdvdArguments(
        devicePath: String,
        outputFormat: String = "json"
    ) -> [String] {
        var args: [String] = []

        // All information
        args += ["-a", "-s", "-c"]

        // Output format
        if outputFormat == "json" {
            args += ["-Oj"]
        } else if outputFormat == "xml" {
            args += ["-Ox"]
        }

        args.append(devicePath)

        return args
    }

    // MARK: - dvdbackup Arguments

    /// Build dvdbackup arguments for full disc backup.
    ///
    /// - Parameters:
    ///   - devicePath: DVD device path.
    ///   - outputDir: Output directory.
    ///   - titleNumber: Specific title to backup (nil = full disc).
    /// - Returns: Argument array for dvdbackup.
    public static func buildDVDBackupArguments(
        devicePath: String,
        outputDir: String,
        titleNumber: Int? = nil
    ) -> [String] {
        var args: [String] = []

        args += ["-i", devicePath]
        args += ["-o", outputDir]

        if let title = titleNumber {
            args += ["-t", "\(title)"]
        } else {
            args += ["-M"] // Mirror (full disc backup)
        }

        return args
    }

    // MARK: - VIDEO_TS Structure

    /// Expected VOB file naming pattern for a given title set.
    ///
    /// DVD VOB files follow the pattern VTS_XX_Y.VOB where
    /// XX is the title set number and Y is the part number.
    ///
    /// - Parameters:
    ///   - titleSetNumber: Title set number (1-based).
    ///   - partCount: Expected number of parts.
    /// - Returns: Array of expected VOB filenames.
    public static func expectedVOBFiles(
        titleSetNumber: Int,
        partCount: Int
    ) -> [String] {
        var files: [String] = []
        for part in 1...max(1, partCount) {
            files.append(String(format: "VTS_%02d_%d.VOB", titleSetNumber, part))
        }
        return files
    }

    /// Build the VIDEO_TS directory path from a mount/device path.
    ///
    /// - Parameter basePath: Mount point or image extraction path.
    /// - Returns: Path to the VIDEO_TS directory.
    public static func videoTSPath(from basePath: String) -> String {
        return (basePath as NSString).appendingPathComponent("VIDEO_TS")
    }

    /// Build the IFO file path for a given title set.
    ///
    /// - Parameters:
    ///   - videoTSDir: VIDEO_TS directory path.
    ///   - titleSetNumber: Title set number (0 = VMG, 1+ = VTS).
    /// - Returns: Path to the IFO file.
    public static func ifoFilePath(
        videoTSDir: String,
        titleSetNumber: Int
    ) -> String {
        let filename: String
        if titleSetNumber == 0 {
            filename = "VIDEO_TS.IFO"
        } else {
            filename = String(format: "VTS_%02d_0.IFO", titleSetNumber)
        }
        return (videoTSDir as NSString).appendingPathComponent(filename)
    }

    // MARK: - Region Codes

    /// DVD region code descriptions.
    public static let regionDescriptions: [Int: String] = [
        1: "United States, Canada",
        2: "Europe, Japan, Middle East, South Africa",
        3: "Southeast Asia, South Korea",
        4: "Australia, New Zealand, Latin America",
        5: "Africa, India, Russia, Former USSR",
        6: "China",
        7: "Reserved",
        8: "International (airlines, cruise ships)",
    ]

    /// Check if a DVD region mask allows playback in a given region.
    ///
    /// - Parameters:
    ///   - regionMask: DVD region mask byte.
    ///   - region: Target region (1-8).
    /// - Returns: `true` if playback is allowed.
    public static func isRegionAllowed(regionMask: UInt8, region: Int) -> Bool {
        guard region >= 1, region <= 8 else { return false }
        // In DVD region coding, a 0 bit means the region is ALLOWED
        return regionMask & (1 << (region - 1)) == 0
    }

    // MARK: - Main Feature Detection

    /// Heuristic to identify the main feature title.
    ///
    /// The main feature is typically the longest title that:
    /// - Has chapters
    /// - Is longer than 60 minutes
    /// - Has multiple audio streams
    ///
    /// - Parameter titles: Array of disc titles.
    /// - Returns: The main feature title, or nil if no good candidate.
    public static func detectMainFeature(titles: [DiscTitle]) -> DiscTitle? {
        let candidates = titles.filter { $0.duration > 3600 } // > 1 hour

        if let best = candidates.max(by: { $0.duration < $1.duration }) {
            return best
        }

        // Fallback: longest title regardless of duration
        return titles.max(by: { $0.duration < $1.duration })
    }
}
