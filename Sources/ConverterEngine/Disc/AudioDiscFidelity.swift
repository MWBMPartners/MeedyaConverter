// ============================================================================
// MeedyaConverter — AudioDiscFidelity
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - TrackIndex

/// A sub-track index point within a CD track.
///
/// CD-DA tracks can contain multiple index points (INDEX 00 = pre-gap,
/// INDEX 01 = track start, INDEX 02+ = sub-divisions within the track).
public struct TrackIndex: Codable, Sendable {
    /// Track number (1-based).
    public var trackNumber: Int

    /// Index number within the track (0 = pre-gap, 1 = start, 2+ = sub-divisions).
    public var indexNumber: Int

    /// Absolute sector position (LBA).
    public var sector: Int

    /// Time offset from the start of the track in seconds.
    public var offsetInTrack: TimeInterval

    /// Absolute time position on the disc.
    public var absoluteTime: TimeInterval

    public init(
        trackNumber: Int,
        indexNumber: Int,
        sector: Int,
        offsetInTrack: TimeInterval = 0,
        absoluteTime: TimeInterval = 0
    ) {
        self.trackNumber = trackNumber
        self.indexNumber = indexNumber
        self.sector = sector
        self.offsetInTrack = offsetInTrack
        self.absoluteTime = absoluteTime
    }

    /// MSF (minutes:seconds:frames) string for this index.
    public var msfString: String {
        let totalFrames = sector
        let minutes = totalFrames / (75 * 60)
        let seconds = (totalFrames / 75) % 60
        let frames = totalFrames % 75
        return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }
}

// MARK: - DiscTableOfContents

/// Complete table of contents for an audio disc.
///
/// Stores track layout, index points, and disc identification data
/// for embedding into ripped audio files.
public struct DiscTableOfContents: Codable, Sendable {
    /// Disc type.
    public var discType: String

    /// Track list.
    public var tracks: [DiscTrack]

    /// Sub-track index points (INDEX 02+ within tracks).
    public var indexes: [TrackIndex]

    /// Lead-out sector offset.
    public var leadOutSector: Int

    /// First track number (usually 1).
    public var firstTrackNumber: Int

    /// Last track number.
    public var lastTrackNumber: Int

    /// CDDB disc ID.
    public var cddbDiscId: String?

    /// MusicBrainz disc ID.
    public var musicBrainzDiscId: String?

    /// Media Catalog Number (MCN/UPC/EAN).
    public var catalogNumber: String?

    /// CD-TEXT metadata.
    public var cdText: CDTextInfo?

    public init(
        discType: String = "Audio CD",
        tracks: [DiscTrack] = [],
        indexes: [TrackIndex] = [],
        leadOutSector: Int = 0,
        firstTrackNumber: Int = 1,
        lastTrackNumber: Int = 0,
        cddbDiscId: String? = nil,
        musicBrainzDiscId: String? = nil,
        catalogNumber: String? = nil,
        cdText: CDTextInfo? = nil
    ) {
        self.discType = discType
        self.tracks = tracks
        self.indexes = indexes
        self.leadOutSector = leadOutSector
        self.firstTrackNumber = firstTrackNumber
        self.lastTrackNumber = lastTrackNumber == 0 ? tracks.count : lastTrackNumber
        self.cddbDiscId = cddbDiscId
        self.musicBrainzDiscId = musicBrainzDiscId
        self.catalogNumber = catalogNumber
        self.cdText = cdText
    }

    /// Total disc duration in seconds.
    public var totalDuration: TimeInterval {
        Double(leadOutSector) / Double(DiscTrack.sectorsPerSecond)
    }

    /// Track offsets as sector positions.
    public var trackOffsets: [Int] {
        tracks.map(\.startSector)
    }

    /// Indexes that are sub-track divisions (INDEX 02+), suitable for chapter marks.
    public var chapterIndexes: [TrackIndex] {
        indexes.filter { $0.indexNumber >= 2 }
    }

    /// Whether this disc has sub-track index points.
    public var hasSubTrackIndexes: Bool {
        !chapterIndexes.isEmpty
    }
}

// MARK: - ChapterMark

/// A chapter mark for embedding in audio files.
public struct ChapterMark: Codable, Sendable {
    /// Chapter title.
    public var title: String

    /// Start time in seconds.
    public var startTime: TimeInterval

    /// End time in seconds (nil = until next chapter or end of file).
    public var endTime: TimeInterval?

    public init(title: String, startTime: TimeInterval, endTime: TimeInterval? = nil) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Start time as HH:MM:SS.mmm for FFmpeg.
    public var ffmpegTimestamp: String {
        let hours = Int(startTime) / 3600
        let minutes = (Int(startTime) % 3600) / 60
        let seconds = Int(startTime) % 60
        let millis = Int((startTime.truncatingRemainder(dividingBy: 1.0)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }
}

// MARK: - CuesheetFormat

/// Format capabilities for cuesheet embedding.
public enum CuesheetEmbedMethod: String, Sendable {
    /// FLAC native CUESHEET metadata block.
    case flacNative = "flac_native"

    /// Vorbis comment tag (CUESHEET= key).
    case vorbisComment = "vorbis_comment"

    /// ID3v2 TXXX frame.
    case id3v2 = "id3v2"

    /// iTunes/MP4 metadata tag.
    case mp4Tag = "mp4_tag"

    /// WMA extended content description.
    case wmaTag = "wma_tag"

    /// APEv2 tag.
    case apeTag = "ape_tag"
}

// MARK: - AudioDiscFidelity

/// Builds FFmpeg arguments and metadata for high-fidelity audio disc ripping.
///
/// Provides complete disc-to-file fidelity including:
/// - CDTOC embedding in all supported audio formats
/// - Cuesheet embedding (lossy and lossless)
/// - Track index points as chapter marks
/// - Whole-disc single-file ripping
///
/// The goal is an as-accurate representation of the original audio disc
/// as possible in the output files.
public struct AudioDiscFidelity: Sendable {

    // MARK: - CDTOC Embedding

    /// Formats that support CDTOC metadata embedding.
    public static let cdtocSupportedFormats: [(format: CDDAFormat, method: String)] = [
        (.flac, "CDTOC Vorbis comment"),
        (.oggVorbis, "CDTOC Vorbis comment"),
        (.opus, "CDTOC Vorbis comment"),
        (.alac, "CDTOC MP4/iTunes tag"),
        (.aacLC, "CDTOC MP4/iTunes tag"),
        (.mp3, "CDTOC ID3v2 TXXX frame"),
        (.wav, "CDTOC INFO chunk (limited)"),
        (.aiff, "CDTOC ID3v2 chunk"),
    ]

    /// Build a CDTOC metadata string from a disc table of contents.
    ///
    /// Format: `firstTrack lastTrack leadOut offset1 offset2 ...`
    /// where all values are in sectors (LBA).
    ///
    /// - Parameter toc: Disc table of contents.
    /// - Returns: CDTOC metadata string.
    public static func buildCDTOCString(toc: DiscTableOfContents) -> String {
        var parts: [String] = []
        parts.append("\(toc.firstTrackNumber)")
        parts.append("\(toc.lastTrackNumber)")
        parts.append("\(toc.leadOutSector)")
        for track in toc.tracks {
            parts.append("\(track.startSector)")
        }
        return parts.joined(separator: " ")
    }

    /// Build FFmpeg metadata arguments to embed CDTOC in the output file.
    ///
    /// Works with ALL audio formats that support metadata tags.
    ///
    /// - Parameters:
    ///   - toc: Disc table of contents.
    ///   - format: Target audio format.
    /// - Returns: FFmpeg argument array for CDTOC embedding.
    public static func buildCDTOCArguments(
        toc: DiscTableOfContents,
        format: CDDAFormat
    ) -> [String] {
        let tocString = buildCDTOCString(toc: toc)
        var args: [String] = []

        // CDTOC as metadata tag — works across all format containers
        args += ["-metadata", "CDTOC=\(tocString)"]

        // MusicBrainz disc ID if available
        if let mbId = toc.musicBrainzDiscId {
            args += ["-metadata", "MUSICBRAINZ_DISCID=\(mbId)"]
        }

        // CDDB disc ID if available
        if let cddbId = toc.cddbDiscId {
            args += ["-metadata", "CDDB_DISCID=\(cddbId)"]
        }

        // Media catalog number (UPC/EAN)
        if let mcn = toc.catalogNumber {
            args += ["-metadata", "MCN=\(mcn)"]
            args += ["-metadata", "UPC=\(mcn)"]
        }

        // Disc type
        args += ["-metadata", "DISCTYPE=\(toc.discType)"]

        // Track count
        args += ["-metadata", "TOTALTRACKS=\(toc.tracks.count)"]

        return args
    }

    // MARK: - Cuesheet Embedding

    /// Generate a CUE sheet string from a disc table of contents.
    ///
    /// - Parameters:
    ///   - toc: Disc table of contents.
    ///   - audioFileName: The audio file name to reference in the CUE sheet.
    /// - Returns: Complete CUE sheet string.
    public static func generateCuesheet(
        toc: DiscTableOfContents,
        audioFileName: String
    ) -> String {
        var cue = ""

        // Header
        if let catalog = toc.catalogNumber {
            cue += "CATALOG \(catalog)\n"
        }
        if let cdText = toc.cdText {
            if let title = cdText.albumTitle {
                cue += "TITLE \"\(title)\"\n"
            }
            if let artist = cdText.albumArtist {
                cue += "PERFORMER \"\(artist)\"\n"
            }
        }
        if let cddbId = toc.cddbDiscId {
            cue += "REM DISCID \(cddbId)\n"
        }

        cue += "FILE \"\(audioFileName)\" WAVE\n"

        for track in toc.tracks {
            let trackNum = String(format: "%02d", track.number)
            let trackType = track.isData ? "MODE1/2352" : "AUDIO"
            cue += "  TRACK \(trackNum) \(trackType)\n"

            if let cdText = toc.cdText {
                if let title = cdText.trackTitles[track.number] {
                    cue += "    TITLE \"\(title)\"\n"
                }
                if let artist = cdText.trackArtists[track.number] {
                    cue += "    PERFORMER \"\(artist)\"\n"
                }
            } else {
                if let title = track.title {
                    cue += "    TITLE \"\(title)\"\n"
                }
                if let artist = track.artist {
                    cue += "    PERFORMER \"\(artist)\"\n"
                }
            }

            if track.hasPreEmphasis {
                cue += "    FLAGS PRE\n"
            }

            // Write index points
            let trackIndexes = toc.indexes.filter { $0.trackNumber == track.number }
                .sorted { $0.indexNumber < $1.indexNumber }

            if trackIndexes.isEmpty {
                // No explicit indexes — write INDEX 01 from track start sector
                cue += "    INDEX 01 \(sectorToMSF(track.startSector))\n"
            } else {
                for index in trackIndexes {
                    let indexNum = String(format: "%02d", index.indexNumber)
                    cue += "    INDEX \(indexNum) \(sectorToMSF(index.sector))\n"
                }
            }
        }

        return cue
    }

    /// Build FFmpeg metadata arguments to embed a cuesheet.
    ///
    /// Embeds in ALL formats that support metadata tags — both lossy and lossless.
    ///
    /// - Parameters:
    ///   - toc: Disc table of contents.
    ///   - audioFileName: Audio file name for the CUE FILE directive.
    ///   - format: Target audio format.
    /// - Returns: FFmpeg argument array.
    public static func buildCuesheetArguments(
        toc: DiscTableOfContents,
        audioFileName: String,
        format: CDDAFormat
    ) -> [String] {
        let cuesheet = generateCuesheet(toc: toc, audioFileName: audioFileName)

        var args: [String] = []

        // Embed cuesheet as metadata tag — works across all format containers
        // FLAC/Ogg: Vorbis comment CUESHEET tag
        // MP3: ID3v2 TXXX:CUESHEET
        // MP4/M4A: iTunes ©cue or CUESHEET tag
        args += ["-metadata", "CUESHEET=\(cuesheet)"]

        return args
    }

    /// Build the path for an external .cue sidecar file.
    ///
    /// - Parameter audioFilePath: Path to the audio file.
    /// - Returns: Corresponding .cue file path.
    public static func buildCueSidecarPath(audioFilePath: String) -> String {
        let url = URL(fileURLWithPath: audioFilePath)
        return url.deletingPathExtension().appendingPathExtension("cue").path
    }

    // MARK: - Track Indexes as Chapter Marks

    /// Formats that support chapter marks in audio files.
    public static let chapterSupportedFormats: [CDDAFormat] = [
        .mp3,      // ID3v2 CTOC/CHAP frames
        .aacLC,    // MP4 chapter atoms (nero/QuickTime)
        .alac,     // MP4 chapter atoms
        .oggVorbis, // Ogg chapter extension (CHAPTER01= tags)
        .opus,     // Ogg chapter extension
        .flac,     // Vorbis comment chapter tags
    ]

    /// Convert disc track boundaries and index points into chapter marks.
    ///
    /// When ripping individual tracks, sub-track indexes (INDEX 02+) become chapters.
    /// When ripping the whole disc as one file, each track becomes a chapter,
    /// and sub-track indexes become sub-chapters.
    ///
    /// - Parameters:
    ///   - toc: Disc table of contents.
    ///   - wholeDiscMode: If true, each track is a chapter. If false, only
    ///     sub-track indexes within a single track produce chapters.
    ///   - trackNumber: Track number (only used when wholeDiscMode is false).
    ///   - includeIndexes: Whether to include INDEX 02+ as additional chapters.
    /// - Returns: Array of chapter marks.
    public static func buildChapterMarks(
        toc: DiscTableOfContents,
        wholeDiscMode: Bool,
        trackNumber: Int? = nil,
        includeIndexes: Bool = true
    ) -> [ChapterMark] {
        var chapters: [ChapterMark] = []

        if wholeDiscMode {
            // Each track is a chapter
            for (i, track) in toc.tracks.enumerated() {
                let startTime = Double(track.startSector) / Double(DiscTrack.sectorsPerSecond)
                let endTime: TimeInterval?
                if i + 1 < toc.tracks.count {
                    endTime = Double(toc.tracks[i + 1].startSector) / Double(DiscTrack.sectorsPerSecond)
                } else {
                    endTime = Double(toc.leadOutSector) / Double(DiscTrack.sectorsPerSecond)
                }

                let title = track.title ?? "Track \(track.number)"
                chapters.append(ChapterMark(
                    title: title,
                    startTime: startTime,
                    endTime: endTime
                ))

                // Add sub-track indexes as additional chapters
                if includeIndexes {
                    let subIndexes = toc.indexes.filter {
                        $0.trackNumber == track.number && $0.indexNumber >= 2
                    }.sorted { $0.indexNumber < $1.indexNumber }

                    for idx in subIndexes {
                        let idxTitle = "\(title) (Index \(idx.indexNumber))"
                        chapters.append(ChapterMark(
                            title: idxTitle,
                            startTime: idx.absoluteTime
                        ))
                    }
                }
            }
        } else if let trackNum = trackNumber {
            // Sub-track indexes within a single track
            let subIndexes = toc.indexes.filter {
                $0.trackNumber == trackNum && $0.indexNumber >= 2
            }.sorted { $0.indexNumber < $1.indexNumber }

            for idx in subIndexes {
                chapters.append(ChapterMark(
                    title: "Index \(idx.indexNumber)",
                    startTime: idx.offsetInTrack
                ))
            }
        }

        return chapters.sorted { $0.startTime < $1.startTime }
    }

    /// Build an FFmpeg metadata file (FFMETADATA) for chapter marks.
    ///
    /// FFmpeg reads chapter marks from a metadata file in FFMETADATA format.
    ///
    /// - Parameter chapters: Chapter marks to include.
    /// - Returns: FFMETADATA file content string.
    public static func buildFFmetadataChapterFile(
        chapters: [ChapterMark]
    ) -> String {
        var content = ";FFMETADATA1\n"

        for (i, chapter) in chapters.enumerated() {
            let startMs = Int(chapter.startTime * 1000)
            let endMs: Int
            if let end = chapter.endTime {
                endMs = Int(end * 1000)
            } else if i + 1 < chapters.count {
                endMs = Int(chapters[i + 1].startTime * 1000)
            } else {
                endMs = startMs + 1000 // Fallback: 1 second
            }

            content += "\n[CHAPTER]\n"
            content += "TIMEBASE=1/1000\n"
            content += "START=\(startMs)\n"
            content += "END=\(endMs)\n"
            content += "title=\(chapter.title)\n"
        }

        return content
    }

    /// Build FFmpeg arguments to embed chapters from a metadata file.
    ///
    /// - Parameter metadataFilePath: Path to the FFMETADATA file.
    /// - Returns: FFmpeg argument array.
    public static func buildChapterEmbedArguments(
        metadataFilePath: String
    ) -> [String] {
        return [
            "-i", metadataFilePath,
            "-map_metadata", "1",
            "-map_chapters", "1",
        ]
    }

    /// Build Vorbis comment chapter tags for Ogg/FLAC formats.
    ///
    /// Ogg/FLAC use CHAPTER01=timestamp and CHAPTER01NAME=title tags.
    ///
    /// - Parameter chapters: Chapter marks.
    /// - Returns: FFmpeg metadata argument array.
    public static func buildVorbisChapterArguments(
        chapters: [ChapterMark]
    ) -> [String] {
        var args: [String] = []
        for (i, chapter) in chapters.enumerated() {
            let num = String(format: "%02d", i + 1)
            let timestamp = chapter.ffmpegTimestamp
            args += ["-metadata", "CHAPTER\(num)=\(timestamp)"]
            args += ["-metadata", "CHAPTER\(num)NAME=\(chapter.title)"]
        }
        return args
    }

    // MARK: - Whole-Disc Ripping

    /// Build cdparanoia arguments for ripping the entire disc as one file.
    ///
    /// Uses the sector range "0-" to rip from start to end without
    /// splitting into individual tracks.
    ///
    /// - Parameters:
    ///   - devicePath: Optical drive device path.
    ///   - outputPath: Output WAV file path.
    ///   - paranoia: Error correction level.
    ///   - readSpeed: Max read speed.
    /// - Returns: Argument array for cdparanoia.
    public static func buildWholeDiscRipArguments(
        devicePath: String,
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

        // Rip entire disc (first track through last)
        args.append("[.0]-")

        args.append(outputPath)

        return args
    }

    /// Build the complete FFmpeg encoding arguments for a whole-disc rip.
    ///
    /// Combines audio encoding, CDTOC embedding, cuesheet embedding,
    /// and chapter marks from track boundaries and index points.
    ///
    /// - Parameters:
    ///   - inputWavPath: Ripped WAV file (whole disc).
    ///   - outputPath: Encoded output file path.
    ///   - format: Target audio format.
    ///   - toc: Disc table of contents.
    ///   - bitrate: Bitrate in kbps (for lossy formats).
    ///   - embedCuesheet: Whether to embed a cuesheet.
    ///   - embedCDTOC: Whether to embed CDTOC.
    ///   - embedChapters: Whether to embed track/index chapters.
    ///   - metadata: Additional metadata tags.
    ///   - chapterMetadataPath: Path to write FFMETADATA chapter file (for MP4/etc.).
    /// - Returns: FFmpeg argument array.
    public static func buildWholeDiscEncodeArguments(
        inputWavPath: String,
        outputPath: String,
        format: CDDAFormat,
        toc: DiscTableOfContents,
        bitrate: Int? = nil,
        embedCuesheet: Bool = true,
        embedCDTOC: Bool = true,
        embedChapters: Bool = true,
        metadata: [String: String] = [:],
        chapterMetadataPath: String? = nil
    ) -> [String] {
        var args: [String] = ["-i", inputWavPath]

        // Chapter metadata file input
        if embedChapters, let chapterPath = chapterMetadataPath {
            args += ["-i", chapterPath]
            args += ["-map", "0:a"]
            args += ["-map_metadata", "1"]
            args += ["-map_chapters", "1"]
        }

        // Audio codec
        args += ["-c:a", format.ffmpegCodec]

        // Bitrate for lossy codecs
        if let br = bitrate, !format.isLossless {
            args += ["-b:a", "\(br)k"]
        }

        // FLAC compression
        if format == .flac {
            args += ["-compression_level", "8"]
        }

        // CDTOC embedding
        if embedCDTOC {
            args += buildCDTOCArguments(toc: toc, format: format)
        }

        // Cuesheet embedding
        if embedCuesheet {
            let audioFileName = URL(fileURLWithPath: outputPath).lastPathComponent
            args += buildCuesheetArguments(toc: toc, audioFileName: audioFileName, format: format)
        }

        // Vorbis chapter tags for Ogg/FLAC
        if embedChapters && [.flac, .oggVorbis, .opus].contains(format) {
            let chapters = buildChapterMarks(toc: toc, wholeDiscMode: true)
            args += buildVorbisChapterArguments(chapters: chapters)
        }

        // User metadata
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            args += ["-metadata", "\(key)=\(value)"]
        }

        args += ["-y", outputPath]

        return args
    }

    // MARK: - Helpers

    /// Convert a sector position to MSF (MM:SS:FF) string for CUE sheets.
    private static func sectorToMSF(_ sector: Int) -> String {
        let minutes = sector / (75 * 60)
        let seconds = (sector / 75) % 60
        let frames = sector % 75
        return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }

    /// Whether a given format supports embedded chapters.
    public static func supportsChapters(_ format: CDDAFormat) -> Bool {
        chapterSupportedFormats.contains(format)
    }

    /// Whether a given format supports cuesheet embedding.
    public static func supportsCuesheet(_ format: CDDAFormat) -> Bool {
        // All formats support CUESHEET as a metadata tag
        true
    }

    /// Whether a given format supports CDTOC embedding.
    public static func supportsCDTOC(_ format: CDDAFormat) -> Bool {
        // All formats support CDTOC as a metadata tag
        true
    }

    /// Build the output filename for a whole-disc rip.
    ///
    /// - Parameters:
    ///   - cdText: CD-TEXT metadata (optional).
    ///   - format: Target format.
    /// - Returns: Generated filename.
    public static func buildWholeDiscFilename(
        cdText: CDTextInfo?,
        format: CDDAFormat
    ) -> String {
        var name: String
        if let artist = cdText?.albumArtist, let title = cdText?.albumTitle {
            name = "\(artist) - \(title)"
        } else if let title = cdText?.albumTitle {
            name = title
        } else {
            name = "Full Disc"
        }

        // Sanitize filename
        name = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        return "\(name).\(format.fileExtension)"
    }
}
