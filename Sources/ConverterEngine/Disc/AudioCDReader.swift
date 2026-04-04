// ============================================================================
// MeedyaConverter — AudioCDReader
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CDTextInfo

/// CD-TEXT metadata embedded on the disc.
public struct CDTextInfo: Codable, Sendable {
    /// Album title.
    public var albumTitle: String?

    /// Album artist/performer.
    public var albumArtist: String?

    /// Track titles (indexed by track number, 1-based).
    public var trackTitles: [Int: String]

    /// Track artists (indexed by track number, 1-based).
    public var trackArtists: [Int: String]

    /// Genre.
    public var genre: String?

    /// Disc ID / UPC.
    public var discId: String?

    public init(
        albumTitle: String? = nil,
        albumArtist: String? = nil,
        trackTitles: [Int: String] = [:],
        trackArtists: [Int: String] = [:],
        genre: String? = nil,
        discId: String? = nil
    ) {
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.trackTitles = trackTitles
        self.trackArtists = trackArtists
        self.genre = genre
        self.discId = discId
    }
}

// MARK: - CDDAFormat

/// Output format options for CD audio ripping.
public enum CDDAFormat: String, Codable, Sendable, CaseIterable {
    case wav = "wav"
    case flac = "flac"
    case alac = "alac"
    case aiff = "aiff"
    case mp3 = "mp3"
    case aacLC = "aac"
    case oggVorbis = "ogg"
    case opus = "opus"

    /// File extension for this format.
    public var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .flac: return "flac"
        case .alac: return "m4a"
        case .aiff: return "aiff"
        case .mp3: return "mp3"
        case .aacLC: return "m4a"
        case .oggVorbis: return "ogg"
        case .opus: return "opus"
        }
    }

    /// Whether this format is lossless.
    public var isLossless: Bool {
        switch self {
        case .wav, .flac, .alac, .aiff:
            return true
        case .mp3, .aacLC, .oggVorbis, .opus:
            return false
        }
    }

    /// FFmpeg codec name.
    public var ffmpegCodec: String {
        switch self {
        case .wav: return "pcm_s16le"
        case .flac: return "flac"
        case .alac: return "alac"
        case .aiff: return "pcm_s16be"
        case .mp3: return "libmp3lame"
        case .aacLC: return "aac"
        case .oggVorbis: return "libvorbis"
        case .opus: return "libopus"
        }
    }
}

// MARK: - CDParanoiaMode

/// Paranoia read correction level for cdparanoia.
public enum CDParanoiaMode: Int, Codable, Sendable {
    /// No error correction (fastest, least accurate).
    case disabled = 0

    /// Overlap checking only.
    case overlapOnly = 1

    /// Full paranoia without scratch repair.
    case noScratchRepair = 2

    /// Full paranoia (slowest, most accurate).
    case full = 3

    /// cdparanoia flag string.
    public var paranoiaFlags: String {
        switch self {
        case .disabled: return "--disable-paranoia"
        case .overlapOnly: return "--force-overread"
        case .noScratchRepair: return "--never-skip=20"
        case .full: return "--never-skip=40"
        }
    }
}

// MARK: - AudioCDReader

/// Builds command-line arguments for audio CD ripping using cdparanoia
/// and libcdio, with CDDB/MusicBrainz metadata lookup support.
///
/// Supports:
/// - Red Book Audio CD standard (44.1kHz, 16-bit, stereo)
/// - cdparanoia error correction with configurable paranoia levels
/// - CDDB disc ID calculation for metadata lookup
/// - AccurateRip verification checksums
/// - CD-TEXT reading via libcdio
///
/// Phase 8.2
public struct AudioCDReader: Sendable {

    // MARK: - cdparanoia Arguments

    /// Build cdparanoia arguments to rip a single track.
    ///
    /// - Parameters:
    ///   - devicePath: Optical drive device path (e.g., "/dev/sr0").
    ///   - trackNumber: Track number (1-based).
    ///   - outputPath: Output WAV file path.
    ///   - paranoia: Error correction level.
    ///   - readSpeed: Max read speed (nil = auto).
    /// - Returns: Argument array for cdparanoia.
    public static func buildRipTrackArguments(
        devicePath: String,
        trackNumber: Int,
        outputPath: String,
        paranoia: CDParanoiaMode = .full,
        readSpeed: Int? = nil
    ) -> [String] {
        var args: [String] = []

        args += ["-d", devicePath]
        args.append(paranoia.paranoiaFlags)

        if let speed = readSpeed {
            args += ["-S", "\(speed)"]
        }

        // Track selection
        args.append("\(trackNumber)")

        // Output
        args.append(outputPath)

        return args
    }

    /// Build cdparanoia arguments to rip all tracks.
    ///
    /// - Parameters:
    ///   - devicePath: Optical drive device path.
    ///   - outputDir: Output directory.
    ///   - paranoia: Error correction level.
    ///   - readSpeed: Max read speed.
    /// - Returns: Argument array for cdparanoia (batch mode).
    public static func buildRipAllArguments(
        devicePath: String,
        outputDir: String,
        paranoia: CDParanoiaMode = .full,
        readSpeed: Int? = nil
    ) -> [String] {
        var args: [String] = []

        args += ["-d", devicePath]
        args.append(paranoia.paranoiaFlags)

        if let speed = readSpeed {
            args += ["-S", "\(speed)"]
        }

        // Batch mode: rip all tracks
        args += ["-B"]

        // Output directory prefix
        args += ["-O", outputDir]

        return args
    }

    // MARK: - FFmpeg Encoding Arguments

    /// Build FFmpeg arguments to encode a ripped WAV to a target format.
    ///
    /// - Parameters:
    ///   - inputPath: WAV file from cdparanoia.
    ///   - outputPath: Encoded output file.
    ///   - format: Target format.
    ///   - bitrate: Bitrate in kbps (for lossy formats).
    ///   - metadata: Metadata tags to embed.
    /// - Returns: FFmpeg argument array.
    public static func buildEncodeArguments(
        inputPath: String,
        outputPath: String,
        format: CDDAFormat,
        bitrate: Int? = nil,
        metadata: [String: String] = [:]
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        args += ["-c:a", format.ffmpegCodec]

        // Bitrate for lossy codecs
        if let br = bitrate, !format.isLossless {
            args += ["-b:a", "\(br)k"]
        }

        // FLAC compression level
        if format == .flac {
            args += ["-compression_level", "8"]
        }

        // Metadata
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            args += ["-metadata", "\(key)=\(value)"]
        }

        args += ["-y", outputPath]

        return args
    }

    // MARK: - CDDB Disc ID

    /// Calculate a CDDB disc ID from a table of contents.
    ///
    /// The CDDB disc ID is calculated from track offsets and total disc length.
    ///
    /// - Parameters:
    ///   - tracks: Array of tracks with start sectors.
    ///   - leadOutSector: Lead-out sector (total disc sectors).
    /// - Returns: CDDB disc ID as a hex string.
    public static func calculateCDDBDiscId(
        tracks: [DiscTrack],
        leadOutSector: Int
    ) -> String {
        guard !tracks.isEmpty else { return "00000000" }

        // Sum digit sum of frame offsets in seconds
        var n: Int = 0
        for track in tracks {
            var offset = (track.startSector + 150) / 75 // Convert to seconds (150 offset for 2-sec lead-in)
            while offset > 0 {
                n += offset % 10
                offset /= 10
            }
        }

        let totalLength = (leadOutSector + 150) / 75 - (tracks[0].startSector + 150) / 75
        let trackCount = tracks.count

        let discId = ((n % 0xFF) << 24) | (totalLength << 8) | trackCount
        return String(format: "%08x", discId)
    }

    /// Build a CDDB query string for FreeDB/GNUDB lookup.
    ///
    /// - Parameters:
    ///   - discId: CDDB disc ID.
    ///   - tracks: Track list.
    ///   - leadOutSector: Lead-out sector.
    /// - Returns: CDDB query string.
    public static func buildCDDBQuery(
        discId: String,
        tracks: [DiscTrack],
        leadOutSector: Int
    ) -> String {
        var query = "cddb query \(discId) \(tracks.count)"
        for track in tracks {
            query += " \(track.startSector + 150)" // Add 150 for 2-sec lead-in
        }
        let totalSeconds = (leadOutSector + 150) / 75
        query += " \(totalSeconds)"
        return query
    }

    // MARK: - MusicBrainz Disc ID

    /// Calculate a MusicBrainz disc ID from table of contents.
    ///
    /// MusicBrainz uses a Base64-encoded SHA-1 hash of the TOC.
    ///
    /// - Parameters:
    ///   - firstTrack: First track number (usually 1).
    ///   - lastTrack: Last track number.
    ///   - leadOutOffset: Lead-out offset in sectors.
    ///   - trackOffsets: Array of track start offsets in sectors.
    /// - Returns: The TOC string for MusicBrainz lookup URL construction.
    public static func buildMusicBrainzTOC(
        firstTrack: Int,
        lastTrack: Int,
        leadOutOffset: Int,
        trackOffsets: [Int]
    ) -> String {
        var parts = ["\(firstTrack)", "\(lastTrack)", "\(leadOutOffset)"]
        parts += trackOffsets.map { "\($0)" }
        return parts.joined(separator: "+")
    }

    /// Build a MusicBrainz disc lookup URL.
    ///
    /// - Parameter toc: TOC string from `buildMusicBrainzTOC`.
    /// - Returns: MusicBrainz lookup URL.
    public static func buildMusicBrainzLookupURL(toc: String) -> String {
        return "https://musicbrainz.org/ws/2/discid/-?toc=\(toc)&fmt=json"
    }

    // MARK: - AccurateRip

    /// Build an AccurateRip verification URL.
    ///
    /// AccurateRip uses a disc ID derived from track offsets to look up
    /// known-good checksums.
    ///
    /// - Parameters:
    ///   - trackCount: Number of tracks on the disc.
    ///   - discId1: AccurateRip disc ID 1.
    ///   - discId2: AccurateRip disc ID 2.
    ///   - cddbDiscId: CDDB disc ID.
    /// - Returns: AccurateRip verification URL.
    public static func buildAccurateRipURL(
        trackCount: Int,
        discId1: UInt32,
        discId2: UInt32,
        cddbDiscId: String
    ) -> String {
        let d1 = String(format: "%08x", discId1)
        let d2 = String(format: "%08x", discId2)
        return "http://www.accuraterip.com/accuraterip/\(String(d1.suffix(1)))/\(String(d1.suffix(2).prefix(1)))/\(String(d1.suffix(3).prefix(1)))/dBAR-\(String(format: "%03d", trackCount))-\(d1)-\(d2)-\(cddbDiscId).bin"
    }

    /// Calculate AccurateRip disc IDs from track offsets.
    ///
    /// - Parameters:
    ///   - trackOffsets: Start offsets of each track in sectors.
    ///   - leadOutOffset: Lead-out sector offset.
    /// - Returns: Tuple of (discId1, discId2).
    public static func calculateAccurateRipDiscIds(
        trackOffsets: [Int],
        leadOutOffset: Int
    ) -> (discId1: UInt32, discId2: UInt32) {
        var id1: UInt32 = 0
        var id2: UInt32 = 0

        let allOffsets = trackOffsets + [leadOutOffset]

        for (index, offset) in allOffsets.enumerated() {
            let trackNum = index // 0-based for calculation
            id1 += UInt32(offset)
            id2 += UInt32(max(offset, 1)) * UInt32(trackNum + 1)
        }

        return (id1, id2)
    }

    // MARK: - libcdio Arguments

    /// Build cd-info arguments to read disc TOC.
    ///
    /// - Parameter devicePath: Optical drive device path.
    /// - Returns: Argument array for cd-info.
    public static func buildCDInfoArguments(devicePath: String) -> [String] {
        return ["--no-header", "--no-analyze", "-C", devicePath]
    }

    /// Build cd-read arguments to extract CD-TEXT.
    ///
    /// - Parameter devicePath: Optical drive device path.
    /// - Returns: Argument array for cd-read.
    public static func buildCDTextArguments(devicePath: String) -> [String] {
        return ["--mode=cdtext", "-C", devicePath]
    }

    // MARK: - Track Duration

    /// Calculate track duration from sector information.
    ///
    /// - Parameters:
    ///   - startSector: Track start sector.
    ///   - nextStartSector: Next track's start sector (or lead-out).
    /// - Returns: Duration in seconds.
    public static func trackDuration(
        startSector: Int,
        nextStartSector: Int
    ) -> TimeInterval {
        let sectors = nextStartSector - startSector
        return TimeInterval(sectors) / TimeInterval(DiscTrack.sectorsPerSecond)
    }

    /// Build output filename for a ripped track.
    ///
    /// - Parameters:
    ///   - trackNumber: Track number.
    ///   - title: Track title (optional).
    ///   - artist: Artist name (optional).
    ///   - format: Output format.
    /// - Returns: Sanitized filename.
    public static func buildOutputFilename(
        trackNumber: Int,
        title: String? = nil,
        artist: String? = nil,
        format: CDDAFormat
    ) -> String {
        let trackStr = String(format: "%02d", trackNumber)
        var name = trackStr

        if let t = title {
            let sanitized = t.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            if let a = artist {
                let sanitizedArtist = a.replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                name = "\(trackStr) - \(sanitizedArtist) - \(sanitized)"
            } else {
                name = "\(trackStr) - \(sanitized)"
            }
        }

        return "\(name).\(format.fileExtension)"
    }
}
