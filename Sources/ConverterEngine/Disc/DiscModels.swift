// ============================================================================
// MeedyaConverter — DiscModels
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DiscType

/// Supported physical disc and disc image types.
public enum DiscType: String, Codable, Sendable, CaseIterable {
    case audioCd = "audio_cd"
    case dvdVideo = "dvd_video"
    case dvdAudio = "dvd_audio"
    case bluray = "bluray"
    case uhdBluray = "uhd_bluray"
    case hdDvd = "hd_dvd"
    case sacd = "sacd"
    case vcd = "vcd"
    case svcd = "svcd"
    case dataDisc = "data"

    /// Display name.
    public var displayName: String {
        switch self {
        case .audioCd: return "Audio CD"
        case .dvdVideo: return "DVD-Video"
        case .dvdAudio: return "DVD-Audio"
        case .bluray: return "Blu-ray"
        case .uhdBluray: return "UHD Blu-ray"
        case .hdDvd: return "HD DVD"
        case .sacd: return "Super Audio CD"
        case .vcd: return "Video CD"
        case .svcd: return "Super Video CD"
        case .dataDisc: return "Data Disc"
        }
    }

    /// Maximum storage capacity in bytes.
    public var maxCapacityBytes: Int64 {
        switch self {
        case .audioCd: return 737_280_000        // 700 MB (80 min)
        case .dvdVideo: return 8_543_666_176     // DVD-9 (dual layer)
        case .dvdAudio: return 8_543_666_176
        case .bluray: return 50_050_629_632      // BD-50 (dual layer)
        case .uhdBluray: return 100_000_000_000  // BD-100 (triple layer)
        case .hdDvd: return 30_000_000_000       // HD DVD-DL
        case .sacd: return 7_950_000_000         // SACD dual layer
        case .vcd: return 737_280_000
        case .svcd: return 737_280_000
        case .dataDisc: return 8_543_666_176     // DVD-9 default
        }
    }

    /// Whether this disc type carries video content.
    public var hasVideo: Bool {
        switch self {
        case .dvdVideo, .bluray, .uhdBluray, .hdDvd, .vcd, .svcd:
            return true
        default:
            return false
        }
    }

    /// Whether this disc type carries audio content (primary purpose).
    public var hasAudio: Bool {
        switch self {
        case .audioCd, .dvdAudio, .sacd:
            return true
        default:
            return false
        }
    }
}

// MARK: - DiscInfo

/// Information about a disc (physical or image).
public struct DiscInfo: Codable, Sendable {
    /// The disc type.
    public var discType: DiscType

    /// Disc label / volume ID.
    public var label: String?

    /// Total number of titles (for video discs).
    public var titleCount: Int

    /// Total number of tracks (for audio CDs).
    public var trackCount: Int

    /// Total duration in seconds.
    public var totalDuration: TimeInterval

    /// Total disc size in bytes.
    public var totalSizeBytes: Int64

    /// Whether the disc has copy protection.
    public var isProtected: Bool

    /// Protection type description (e.g., "CSS", "AACS", "HDCP").
    public var protectionType: String?

    /// Region code (for DVD/Blu-ray).
    public var regionCode: Int?

    /// Source path (device path or image file path).
    public var sourcePath: String

    public init(
        discType: DiscType,
        label: String? = nil,
        titleCount: Int = 0,
        trackCount: Int = 0,
        totalDuration: TimeInterval = 0,
        totalSizeBytes: Int64 = 0,
        isProtected: Bool = false,
        protectionType: String? = nil,
        regionCode: Int? = nil,
        sourcePath: String = ""
    ) {
        self.discType = discType
        self.label = label
        self.titleCount = titleCount
        self.trackCount = trackCount
        self.totalDuration = totalDuration
        self.totalSizeBytes = totalSizeBytes
        self.isProtected = isProtected
        self.protectionType = protectionType
        self.regionCode = regionCode
        self.sourcePath = sourcePath
    }
}

// MARK: - TrackMode

/// The physical sector encoding of a CD track, per the Red Book (CD-DA) and
/// Yellow Book (CD-ROM) specifications, and as named by the CUE sheet
/// `TRACK NN <mode>` directive (see `CueSheetWriter`/`CueSheetParser` in
/// `Disc/Imaging/`).
///
/// - `audio`: Red Book CD-DA — 2352-byte sector, 16-bit stereo PCM at
///   44.1kHz. No error correction beyond the audio codec's own CIRC.
/// - `mode1`: Yellow Book Mode 1 — a 2352-byte raw sector containing a
///   12-byte sync pattern, 4-byte header, 2048 bytes of user data, and
///   288 bytes of EDC/ECC. This is the standard encoding for ISO 9660 data
///   discs, and is what `MODE1/2352` in a CUE sheet refers to.
/// - `mode2Form1`: Yellow Book Mode 2 Form 1 — a 2336-byte sub-header +
///   user-data region (2048 bytes of user data + its own EDC/ECC) within
///   the same 2352-byte raw sector, used for CD-ROM XA data with error
///   correction.
/// - `mode2Form2`: Yellow Book Mode 2 Form 2 — like Form 1, but trades the
///   EDC/ECC for 2324 bytes of user data with no error correction; used for
///   streaming content such as Video CD (VCD) and CD-i.
/// - `mode2Raw`: A Mode 2 sector whose Form 1/Form 2 designation is not
///   known or not distinguished (e.g. a raw XA dump where the sub-header
///   form byte has not been inspected). CUE sheets cannot distinguish any
///   of the three Mode 2 variants in their raw `MODE2/2352` sector form, so
///   `CueSheetParser` maps `MODE2/2352` back to this case by default.
public enum TrackMode: String, Codable, Sendable, CaseIterable {
    case audio
    case mode1
    case mode2Form1
    case mode2Form2
    case mode2Raw
}

// MARK: - DiscTrack

/// A track on an audio CD.
public struct DiscTrack: Codable, Sendable {
    /// Track number (1-based).
    public var number: Int

    /// Track title (from CDDB/MusicBrainz).
    public var title: String?

    /// Artist name (from CDDB/MusicBrainz).
    public var artist: String?

    /// Duration in seconds.
    public var duration: TimeInterval

    /// Start sector (LBA).
    public var startSector: Int

    /// Sector count.
    public var sectorCount: Int

    /// Whether this is a data track.
    public var isData: Bool

    /// Pre-emphasis flag.
    public var hasPreEmphasis: Bool

    /// International Standard Recording Code for this track, if known.
    /// A 12-character alphanumeric code (e.g. "USRC17607839"); dashes, when
    /// present in source metadata, are preserved as given rather than
    /// normalized here.
    public var isrc: String?

    /// The CD session this track belongs to. Single-session discs (the
    /// overwhelming majority) use `1`. Multi-session discs (CD-Extra,
    /// Mixed Mode, PhotoCD, etc.) number sessions sequentially from `1`;
    /// see `DiscTableOfContents.sessions`.
    public var sessionNumber: Int

    /// The physical sector encoding used for this track — Red Book audio,
    /// or one of the Yellow Book Mode 1/Mode 2 data encodings.
    public var trackMode: TrackMode

    public init(
        number: Int,
        title: String? = nil,
        artist: String? = nil,
        duration: TimeInterval = 0,
        startSector: Int = 0,
        sectorCount: Int = 0,
        isData: Bool = false,
        hasPreEmphasis: Bool = false,
        isrc: String? = nil,
        sessionNumber: Int = 1,
        trackMode: TrackMode? = nil
    ) {
        self.number = number
        self.title = title
        self.artist = artist
        self.duration = duration
        self.startSector = startSector
        self.sectorCount = sectorCount
        self.isData = isData
        self.hasPreEmphasis = hasPreEmphasis
        self.isrc = isrc
        self.sessionNumber = sessionNumber
        // Existing call sites only ever specified `isData`, so when no
        // explicit mode is given we derive a sensible default from it
        // rather than requiring every caller to be updated.
        self.trackMode = trackMode ?? (isData ? .mode1 : .audio)
    }

    /// Sector size for audio CD (2352 bytes per sector).
    public static let sectorSize = 2352

    /// Sectors per second for audio CD (75 sectors/sec).
    public static let sectorsPerSecond = 75
}

// MARK: - DiscTitle

/// A title on a video disc (DVD, Blu-ray, etc.).
public struct DiscTitle: Codable, Sendable {
    /// Title number (1-based).
    public var number: Int

    /// Title name or description.
    public var name: String?

    /// Duration in seconds.
    public var duration: TimeInterval

    /// Number of chapters.
    public var chapterCount: Int

    /// Chapter information.
    public var chapters: [DiscChapter]

    /// Number of video angles.
    public var angleCount: Int

    /// Audio stream descriptions.
    public var audioStreams: [DiscAudioStream]

    /// Subtitle stream descriptions.
    public var subtitleStreams: [DiscSubtitleStream]

    /// Video resolution width.
    public var videoWidth: Int?

    /// Video resolution height.
    public var videoHeight: Int?

    /// Whether this appears to be the main feature title.
    public var isMainFeature: Bool

    /// Size in bytes (estimated).
    public var sizeBytes: Int64

    public init(
        number: Int,
        name: String? = nil,
        duration: TimeInterval = 0,
        chapterCount: Int = 0,
        chapters: [DiscChapter] = [],
        angleCount: Int = 1,
        audioStreams: [DiscAudioStream] = [],
        subtitleStreams: [DiscSubtitleStream] = [],
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        isMainFeature: Bool = false,
        sizeBytes: Int64 = 0
    ) {
        self.number = number
        self.name = name
        self.duration = duration
        self.chapterCount = chapterCount
        self.chapters = chapters
        self.angleCount = angleCount
        self.audioStreams = audioStreams
        self.subtitleStreams = subtitleStreams
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.isMainFeature = isMainFeature
        self.sizeBytes = sizeBytes
    }
}

// MARK: - DiscChapter

/// A chapter within a disc title.
public struct DiscChapter: Codable, Sendable {
    /// Chapter number (1-based).
    public var number: Int

    /// Chapter title.
    public var title: String?

    /// Start time in seconds.
    public var startTime: TimeInterval

    /// Duration in seconds.
    public var duration: TimeInterval

    public init(
        number: Int,
        title: String? = nil,
        startTime: TimeInterval = 0,
        duration: TimeInterval = 0
    ) {
        self.number = number
        self.title = title
        self.startTime = startTime
        self.duration = duration
    }
}

// MARK: - DiscAudioStream

/// An audio stream on a video disc.
public struct DiscAudioStream: Codable, Sendable {
    /// Stream index.
    public var index: Int

    /// Language code (ISO 639-2).
    public var language: String?

    /// Codec name (e.g., "AC-3", "DTS-HD MA", "TrueHD").
    public var codec: String

    /// Channel count.
    public var channels: Int

    /// Sample rate in Hz.
    public var sampleRate: Int

    /// Bit depth.
    public var bitDepth: Int?

    /// Whether this is the default stream.
    public var isDefault: Bool

    public init(
        index: Int,
        language: String? = nil,
        codec: String = "",
        channels: Int = 2,
        sampleRate: Int = 48000,
        bitDepth: Int? = nil,
        isDefault: Bool = false
    ) {
        self.index = index
        self.language = language
        self.codec = codec
        self.channels = channels
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.isDefault = isDefault
    }
}

// MARK: - DiscSubtitleStream

/// A subtitle stream on a video disc.
public struct DiscSubtitleStream: Codable, Sendable {
    /// Stream index.
    public var index: Int

    /// Language code (ISO 639-2).
    public var language: String?

    /// Subtitle type (e.g., "vobsub", "pgs", "text").
    public var format: String

    /// Whether this is a forced subtitle track.
    public var isForced: Bool

    /// Whether this is the default stream.
    public var isDefault: Bool

    public init(
        index: Int,
        language: String? = nil,
        format: String = "",
        isForced: Bool = false,
        isDefault: Bool = false
    ) {
        self.index = index
        self.language = language
        self.format = format
        self.isForced = isForced
        self.isDefault = isDefault
    }
}

// MARK: - DriveCapability

/// Capabilities of an optical disc drive.
public struct DriveCapability: Codable, Sendable {
    /// Device path (e.g., "/dev/sr0", "/dev/disk2").
    public var devicePath: String

    /// Drive model name.
    public var model: String?

    /// Whether the drive can read CDs.
    public var canReadCD: Bool

    /// Whether the drive can read DVDs.
    public var canReadDVD: Bool

    /// Whether the drive can read Blu-rays.
    public var canReadBluray: Bool

    /// Whether the drive can read UHD Blu-rays.
    public var canReadUHDBluray: Bool

    /// Whether the drive can write CDs.
    public var canWriteCD: Bool

    /// Whether the drive can write DVDs.
    public var canWriteDVD: Bool

    /// Whether the drive can write Blu-rays.
    public var canWriteBluray: Bool

    /// Maximum read speed multiplier.
    public var maxReadSpeed: Int?

    /// Maximum write speed multiplier.
    public var maxWriteSpeed: Int?

    public init(
        devicePath: String,
        model: String? = nil,
        canReadCD: Bool = true,
        canReadDVD: Bool = true,
        canReadBluray: Bool = false,
        canReadUHDBluray: Bool = false,
        canWriteCD: Bool = false,
        canWriteDVD: Bool = false,
        canWriteBluray: Bool = false,
        maxReadSpeed: Int? = nil,
        maxWriteSpeed: Int? = nil
    ) {
        self.devicePath = devicePath
        self.model = model
        self.canReadCD = canReadCD
        self.canReadDVD = canReadDVD
        self.canReadBluray = canReadBluray
        self.canReadUHDBluray = canReadUHDBluray
        self.canWriteCD = canWriteCD
        self.canWriteDVD = canWriteDVD
        self.canWriteBluray = canWriteBluray
        self.maxReadSpeed = maxReadSpeed
        self.maxWriteSpeed = maxWriteSpeed
    }

    /// Whether this drive can read a given disc type.
    public func canRead(_ discType: DiscType) -> Bool {
        switch discType {
        case .audioCd, .vcd, .svcd:
            return canReadCD
        case .dvdVideo, .dvdAudio, .dataDisc:
            return canReadDVD
        case .bluray, .sacd:
            return canReadBluray
        case .uhdBluray:
            return canReadUHDBluray
        case .hdDvd:
            return canReadDVD // Most HD DVD drives are DVD-compatible
        }
    }

    /// Whether this drive can write a given disc type.
    public func canWrite(_ discType: DiscType) -> Bool {
        switch discType {
        case .audioCd, .vcd, .svcd:
            return canWriteCD
        case .dvdVideo, .dvdAudio, .dataDisc:
            return canWriteDVD
        case .bluray:
            return canWriteBluray
        case .uhdBluray, .hdDvd, .sacd:
            return false // Writing not supported
        }
    }
}

// MARK: - DiscRipConfig

/// Configuration for a disc ripping operation.
public struct DiscRipConfig: Codable, Sendable {
    /// Source device or image path.
    public var sourcePath: String

    /// Output directory.
    public var outputDirectory: String

    /// Disc type (auto-detected if nil).
    public var discType: DiscType?

    /// Titles to rip (nil = all titles / main feature).
    public var selectedTitles: [Int]?

    /// Tracks to rip for audio CDs (nil = all tracks).
    public var selectedTracks: [Int]?

    /// Audio streams to include (nil = all).
    public var selectedAudioStreams: [Int]?

    /// Subtitle streams to include (nil = all).
    public var selectedSubtitleStreams: [Int]?

    /// Whether to attempt to bypass copy protection.
    public var decryptIfNeeded: Bool

    /// Maximum read speed (nil = auto).
    public var readSpeed: Int?

    /// Number of read retries for damaged sectors.
    public var retryCount: Int

    /// Whether to use paranoia mode for audio CDs (error correction).
    public var paranoiaMode: Bool

    /// Whether to rip only the main feature title.
    public var mainFeatureOnly: Bool

    public init(
        sourcePath: String,
        outputDirectory: String,
        discType: DiscType? = nil,
        selectedTitles: [Int]? = nil,
        selectedTracks: [Int]? = nil,
        selectedAudioStreams: [Int]? = nil,
        selectedSubtitleStreams: [Int]? = nil,
        decryptIfNeeded: Bool = true,
        readSpeed: Int? = nil,
        retryCount: Int = 20,
        paranoiaMode: Bool = true,
        mainFeatureOnly: Bool = true
    ) {
        self.sourcePath = sourcePath
        self.outputDirectory = outputDirectory
        self.discType = discType
        self.selectedTitles = selectedTitles
        self.selectedTracks = selectedTracks
        self.selectedAudioStreams = selectedAudioStreams
        self.selectedSubtitleStreams = selectedSubtitleStreams
        self.decryptIfNeeded = decryptIfNeeded
        self.readSpeed = readSpeed
        self.retryCount = retryCount
        self.paranoiaMode = paranoiaMode
        self.mainFeatureOnly = mainFeatureOnly
    }
}

// MARK: - RipProgress

/// Progress information for a disc ripping operation.
public struct RipProgress: Sendable {
    /// Current track or title being ripped.
    public var currentItem: Int

    /// Total items to rip.
    public var totalItems: Int

    /// Bytes read so far.
    public var bytesRead: Int64

    /// Total bytes to read.
    public var totalBytes: Int64

    /// Current read speed in bytes/second.
    public var readSpeed: Double?

    /// Number of read errors encountered.
    public var errorCount: Int

    /// Current sector being read.
    public var currentSector: Int?

    /// Overall progress fraction (0.0–1.0).
    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesRead) / Double(totalBytes)
    }

    /// Progress percentage (0–100).
    public var percentage: Int {
        Int(fraction * 100)
    }

    public init(
        currentItem: Int = 1,
        totalItems: Int = 1,
        bytesRead: Int64 = 0,
        totalBytes: Int64 = 0,
        readSpeed: Double? = nil,
        errorCount: Int = 0,
        currentSector: Int? = nil
    ) {
        self.currentItem = currentItem
        self.totalItems = totalItems
        self.bytesRead = bytesRead
        self.totalBytes = totalBytes
        self.readSpeed = readSpeed
        self.errorCount = errorCount
        self.currentSector = currentSector
    }
}
