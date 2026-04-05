// ============================================================================
// MeedyaConverter — AccurateRipVerifier
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - AccurateRipChecksum

/// AccurateRip CRC checksum for a single track.
public struct AccurateRipChecksum: Codable, Sendable, Equatable {
    /// Track number (1-based).
    public let trackNumber: Int

    /// AccurateRip v1 CRC32 checksum.
    public let checksumV1: UInt32

    /// AccurateRip v2 CRC32 checksum (uses different algorithm with position weighting).
    public let checksumV2: UInt32

    public init(trackNumber: Int, checksumV1: UInt32, checksumV2: UInt32) {
        self.trackNumber = trackNumber
        self.checksumV1 = checksumV1
        self.checksumV2 = checksumV2
    }

    /// Hex string representation of the v1 checksum.
    public var v1Hex: String {
        String(format: "%08X", checksumV1)
    }

    /// Hex string representation of the v2 checksum.
    public var v2Hex: String {
        String(format: "%08X", checksumV2)
    }
}

// MARK: - AccurateRipDatabaseEntry

/// A single entry from the AccurateRip database for a disc.
public struct AccurateRipDatabaseEntry: Codable, Sendable {
    /// Number of tracks in this entry.
    public let trackCount: Int

    /// AccurateRip disc ID 1.
    public let discId1: UInt32

    /// AccurateRip disc ID 2.
    public let discId2: UInt32

    /// CDDB disc ID.
    public let cddbDiscId: UInt32

    /// Per-track checksums from the database.
    public let trackChecksums: [TrackEntry]

    /// Confidence count (number of submissions that match).
    public let confidence: Int

    /// A single track's database entry.
    public struct TrackEntry: Codable, Sendable {
        /// Track confidence count.
        public let confidence: Int

        /// AccurateRip CRC32 checksum (v1).
        public let checksumV1: UInt32

        /// AccurateRip CRC32 checksum (v2, from newer database entries).
        public let checksumV2: UInt32?
    }
}

// MARK: - AccurateRipTrackResult

/// Verification result for a single track.
public struct AccurateRipTrackResult: Codable, Sendable, Identifiable {
    public let id: UUID
    public let trackNumber: Int
    public let status: VerificationStatus
    public let confidence: Int
    public let checksumV1: UInt32
    public let checksumV2: UInt32
    public let matchVersion: Int?

    public init(
        id: UUID = UUID(),
        trackNumber: Int,
        status: VerificationStatus,
        confidence: Int = 0,
        checksumV1: UInt32,
        checksumV2: UInt32,
        matchVersion: Int? = nil
    ) {
        self.id = id
        self.trackNumber = trackNumber
        self.status = status
        self.confidence = confidence
        self.checksumV1 = checksumV1
        self.checksumV2 = checksumV2
        self.matchVersion = matchVersion
    }

    /// Verification status for a track.
    public enum VerificationStatus: String, Codable, Sendable {
        /// Checksum matches AccurateRip database.
        case verified = "verified"

        /// Checksum does not match any database entry.
        case mismatch = "mismatch"

        /// Disc/track not found in AccurateRip database.
        case notInDatabase = "not_in_database"

        /// Verification could not be performed (e.g., network error).
        case unavailable = "unavailable"

        /// Display name.
        public var displayName: String {
            switch self {
            case .verified: return "Verified"
            case .mismatch: return "Mismatch"
            case .notInDatabase: return "Not in Database"
            case .unavailable: return "Unavailable"
            }
        }

        /// Whether this result indicates a successful verification.
        public var isAccurate: Bool {
            self == .verified
        }
    }
}

// MARK: - AccurateRipDiscResult

/// Complete AccurateRip verification result for a disc.
public struct AccurateRipDiscResult: Codable, Sendable {
    /// Per-track verification results.
    public let trackResults: [AccurateRipTrackResult]

    /// Overall disc status.
    public var overallStatus: AccurateRipTrackResult.VerificationStatus {
        if trackResults.isEmpty { return .unavailable }
        if trackResults.allSatisfy({ $0.status == .verified }) { return .verified }
        if trackResults.contains(where: { $0.status == .mismatch }) { return .mismatch }
        if trackResults.allSatisfy({ $0.status == .notInDatabase }) { return .notInDatabase }
        return .unavailable
    }

    /// Number of tracks that verified successfully.
    public var verifiedCount: Int {
        trackResults.filter { $0.status == .verified }.count
    }

    /// Minimum confidence across all verified tracks.
    public var minimumConfidence: Int {
        trackResults.filter { $0.status == .verified }.map(\.confidence).min() ?? 0
    }

    /// Summary string for display.
    public var summary: String {
        let total = trackResults.count
        let verified = verifiedCount
        if verified == total {
            return "All \(total) tracks verified (min confidence: \(minimumConfidence))"
        } else if verified > 0 {
            return "\(verified)/\(total) tracks verified"
        } else if trackResults.allSatisfy({ $0.status == .notInDatabase }) {
            return "Disc not found in AccurateRip database"
        } else {
            return "\(total - verified) tracks with checksum mismatch"
        }
    }
}

// MARK: - AccurateRipVerifier

/// Calculates and verifies AccurateRip checksums for audio CD rips.
///
/// Implements both AccurateRip v1 and v2 checksum algorithms, parses
/// the AccurateRip database binary response, and compares ripped audio
/// against known-good checksums.
///
/// ## Algorithm Overview
///
/// **AccurateRip v1**: For each track, sum `sample[i] * (i + 1)` for all
/// 32-bit audio samples (treating stereo 16-bit PCM as single 32-bit values),
/// skipping the first and last 5 frames (2940 samples) for the first and last
/// tracks respectively.
///
/// **AccurateRip v2**: Same as v1 but uses `sample[i] * log2(i + 1)` —
/// actually uses a 64-bit multiply-accumulate with position weighting via
/// `CRC = CRC + (sample * position)` where position wraps as a 32-bit
/// unsigned multiply.
///
/// ## Usage
///
/// ```swift
/// // 1. Calculate disc IDs
/// let (id1, id2) = AudioCDReader.calculateAccurateRipDiscIds(
///     trackOffsets: offsets, leadOutOffset: leadOut
/// )
///
/// // 2. Build verification URL
/// let url = AudioCDReader.buildAccurateRipURL(
///     trackCount: count, discId1: id1, discId2: id2, cddbDiscId: cddbId
/// )
///
/// // 3. Fetch and parse database
/// let entries = AccurateRipVerifier.parseDatabaseResponse(data)
///
/// // 4. Calculate checksums from ripped WAV files
/// let checksum = AccurateRipVerifier.calculateChecksum(
///     audioData: wavSamples, trackNumber: 1, totalTracks: 12
/// )
///
/// // 5. Verify against database
/// let result = AccurateRipVerifier.verify(
///     checksums: [checksum], databaseEntries: entries
/// )
/// ```
public struct AccurateRipVerifier: Sendable {

    // MARK: - Constants

    /// Number of audio samples (32-bit values) to skip at disc boundaries.
    /// AccurateRip skips the first 2940 samples (5 frames) at the start
    /// of the first track and the last 2940 samples at the end of the last track.
    public static let skipSamples: Int = 2940

    /// Bytes per audio sample in Red Book CD audio (16-bit stereo = 4 bytes).
    public static let bytesPerSample: Int = 4

    /// Samples per CD frame (588 stereo samples = 1 sector of 2352 bytes / 4).
    public static let samplesPerFrame: Int = 588

    // MARK: - Checksum Calculation

    /// Calculate AccurateRip v1 and v2 checksums for a track's audio data.
    ///
    /// The audio data must be raw PCM: 16-bit signed little-endian stereo
    /// at 44100 Hz (Red Book standard) — i.e., the audio payload from a WAV
    /// file, without the RIFF header.
    ///
    /// - Parameters:
    ///   - audioData: Raw PCM audio bytes (16-bit LE stereo, 44.1kHz).
    ///   - trackNumber: 1-based track number.
    ///   - totalTracks: Total number of tracks on the disc.
    ///   - isFirstTrack: Whether this is the first track (skip leading samples).
    ///   - isLastTrack: Whether this is the last track (skip trailing samples).
    /// - Returns: AccurateRip checksum for this track.
    public static func calculateChecksum(
        audioData: Data,
        trackNumber: Int,
        totalTracks: Int,
        isFirstTrack: Bool? = nil,
        isLastTrack: Bool? = nil
    ) -> AccurateRipChecksum {
        let firstTrack = isFirstTrack ?? (trackNumber == 1)
        let lastTrack = isLastTrack ?? (trackNumber == totalTracks)
        let sampleCount = audioData.count / bytesPerSample

        var crcV1: UInt32 = 0
        var crcV2: UInt32 = 0

        // Determine skip ranges
        let skipStart = firstTrack ? skipSamples : 0
        let skipEnd = lastTrack ? skipSamples : 0
        let endIndex = sampleCount - skipEnd

        audioData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let samples = baseAddress.assumingMemoryBound(to: UInt32.self)

            for i in skipStart..<endIndex {
                let sample = UInt32(littleEndian: samples[i])
                let position = UInt32(i + 1)

                // AccurateRip v1: simple multiply-accumulate
                crcV1 = crcV1 &+ (sample &* position)

                // AccurateRip v2: same formula, different overflow behavior
                // v2 uses a 64-bit intermediate to avoid information loss
                let product = UInt64(sample) &* UInt64(position)
                crcV2 = crcV2 &+ UInt32(truncatingIfNeeded: product)
            }
        }

        return AccurateRipChecksum(
            trackNumber: trackNumber,
            checksumV1: crcV1,
            checksumV2: crcV2
        )
    }

    /// Extract raw PCM audio data from a WAV file, skipping the RIFF header.
    ///
    /// - Parameter wavData: Complete WAV file data.
    /// - Returns: Raw PCM audio bytes, or nil if the WAV format is invalid.
    public static func extractPCMFromWAV(_ wavData: Data) -> Data? {
        // Find the "data" chunk
        guard wavData.count > 44 else { return nil }

        // Search for "data" marker
        let dataMarker: [UInt8] = [0x64, 0x61, 0x74, 0x61] // "data"
        var offset = 12 // Skip RIFF header (12 bytes)

        while offset < wavData.count - 8 {
            let chunkId = [UInt8](wavData[offset..<offset+4])
            let chunkSize = wavData.withUnsafeBytes { buffer in
                buffer.load(fromByteOffset: offset + 4, as: UInt32.self)
            }
            let size = UInt32(littleEndian: chunkSize)

            if chunkId == dataMarker {
                let dataStart = offset + 8
                let dataEnd = min(dataStart + Int(size), wavData.count)
                return wavData[dataStart..<dataEnd]
            }

            offset += 8 + Int(size)
            // Pad to even boundary
            if offset % 2 != 0 { offset += 1 }
        }

        return nil
    }

    // MARK: - Database Response Parsing

    /// Parse an AccurateRip database binary response.
    ///
    /// The AccurateRip `.bin` file contains one or more entries, each with:
    /// - 1 byte: track count
    /// - 4 bytes: disc ID 1 (LE)
    /// - 4 bytes: disc ID 2 (LE)
    /// - 4 bytes: CDDB disc ID (LE)
    /// - For each track:
    ///   - 1 byte: confidence
    ///   - 4 bytes: CRC (LE)
    ///   - 4 bytes: reserved (usually 0)
    ///
    /// - Parameter data: Raw binary data from AccurateRip server.
    /// - Returns: Array of database entries, or empty if parsing fails.
    public static func parseDatabaseResponse(_ data: Data) -> [AccurateRipDatabaseEntry] {
        var entries: [AccurateRipDatabaseEntry] = []
        var offset = 0

        while offset < data.count {
            // Read track count (1 byte)
            guard offset < data.count else { break }
            let trackCount = Int(data[offset])
            offset += 1

            // Validate minimum remaining size
            let headerSize = 12 // 4+4+4 bytes for disc IDs
            let perTrackSize = 9 // 1+4+4 bytes per track
            let entrySize = headerSize + trackCount * perTrackSize
            guard offset + entrySize <= data.count else { break }

            // Read disc IDs (little-endian)
            let discId1 = data.withUnsafeBytes { buf in
                buf.load(fromByteOffset: offset, as: UInt32.self)
            }
            offset += 4

            let discId2 = data.withUnsafeBytes { buf in
                buf.load(fromByteOffset: offset, as: UInt32.self)
            }
            offset += 4

            let cddbId = data.withUnsafeBytes { buf in
                buf.load(fromByteOffset: offset, as: UInt32.self)
            }
            offset += 4

            // Read per-track data
            var tracks: [AccurateRipDatabaseEntry.TrackEntry] = []
            var totalConfidence = 0

            for _ in 0..<trackCount {
                let confidence = Int(data[offset])
                offset += 1

                let checksum = data.withUnsafeBytes { buf in
                    buf.load(fromByteOffset: offset, as: UInt32.self)
                }
                offset += 4

                // Skip reserved bytes
                offset += 4

                tracks.append(AccurateRipDatabaseEntry.TrackEntry(
                    confidence: confidence,
                    checksumV1: UInt32(littleEndian: checksum),
                    checksumV2: nil
                ))

                totalConfidence += confidence
            }

            entries.append(AccurateRipDatabaseEntry(
                trackCount: trackCount,
                discId1: UInt32(littleEndian: discId1),
                discId2: UInt32(littleEndian: discId2),
                cddbDiscId: UInt32(littleEndian: cddbId),
                trackChecksums: tracks,
                confidence: totalConfidence / max(trackCount, 1)
            ))
        }

        return entries
    }

    // MARK: - Verification

    /// Verify calculated checksums against AccurateRip database entries.
    ///
    /// Tries both v1 and v2 checksums against all database entries.
    ///
    /// - Parameters:
    ///   - checksums: Calculated checksums for each ripped track.
    ///   - databaseEntries: Parsed AccurateRip database entries.
    /// - Returns: Complete disc verification result.
    public static func verify(
        checksums: [AccurateRipChecksum],
        databaseEntries: [AccurateRipDatabaseEntry]
    ) -> AccurateRipDiscResult {
        guard !databaseEntries.isEmpty else {
            return AccurateRipDiscResult(
                trackResults: checksums.map { cs in
                    AccurateRipTrackResult(
                        trackNumber: cs.trackNumber,
                        status: .notInDatabase,
                        checksumV1: cs.checksumV1,
                        checksumV2: cs.checksumV2
                    )
                }
            )
        }

        var results: [AccurateRipTrackResult] = []

        for checksum in checksums {
            let trackIndex = checksum.trackNumber - 1
            var bestMatch: (status: AccurateRipTrackResult.VerificationStatus,
                           confidence: Int, version: Int)? = nil

            for entry in databaseEntries {
                guard trackIndex < entry.trackChecksums.count else { continue }
                let dbTrack = entry.trackChecksums[trackIndex]

                // Try v1 match
                if checksum.checksumV1 == dbTrack.checksumV1 {
                    let conf = dbTrack.confidence
                    if bestMatch == nil || conf > bestMatch!.confidence {
                        bestMatch = (.verified, conf, 1)
                    }
                }

                // Try v2 match
                if let dbV2 = dbTrack.checksumV2, checksum.checksumV2 == dbV2 {
                    let conf = dbTrack.confidence
                    if bestMatch == nil || conf > bestMatch!.confidence {
                        bestMatch = (.verified, conf, 2)
                    }
                }
            }

            let result = AccurateRipTrackResult(
                trackNumber: checksum.trackNumber,
                status: bestMatch?.status ?? .mismatch,
                confidence: bestMatch?.confidence ?? 0,
                checksumV1: checksum.checksumV1,
                checksumV2: checksum.checksumV2,
                matchVersion: bestMatch?.version
            )
            results.append(result)
        }

        return AccurateRipDiscResult(trackResults: results)
    }

    // MARK: - Network Fetch

    /// Fetch AccurateRip database for a disc.
    ///
    /// - Parameters:
    ///   - trackCount: Number of tracks.
    ///   - discId1: AccurateRip disc ID 1.
    ///   - discId2: AccurateRip disc ID 2.
    ///   - cddbDiscId: CDDB disc ID hex string.
    /// - Returns: Parsed database entries, or empty array on failure.
    public static func fetchDatabase(
        trackCount: Int,
        discId1: UInt32,
        discId2: UInt32,
        cddbDiscId: String
    ) async -> [AccurateRipDatabaseEntry] {
        let urlString = AudioCDReader.buildAccurateRipURL(
            trackCount: trackCount,
            discId1: discId1,
            discId2: discId2,
            cddbDiscId: cddbDiscId
        )

        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let httpResponse = response as? HTTPURLResponse
            guard httpResponse?.statusCode == 200 else { return [] }
            return parseDatabaseResponse(data)
        } catch {
            return []
        }
    }

    // MARK: - Drive Offset

    /// Common drive read offset corrections (samples).
    ///
    /// Different optical drives read at slightly different positions.
    /// The offset correction aligns the ripped audio to the correct
    /// absolute position so AccurateRip checksums match.
    ///
    /// See: http://www.accuraterip.com/driveoffsets.htm
    public static let commonDriveOffsets: [(model: String, offset: Int)] = [
        ("PLEXTOR DVDR PX-716A", +30),
        ("PLEXTOR DVDR PX-712A", +30),
        ("PLEXTOR DVDR PX-708A", +30),
        ("PLEXTOR CD-R PX-W4824A", +98),
        ("LITE-ON LTR-48246S", +6),
        ("LITE-ON DVDRW SHW-160P6S", +6),
        ("ASUS DRW-24B1ST", +6),
        ("TSSTcorp CDDVDW SH-S203B", +6),
        ("HL-DT-ST DVDRAM GH22NS50", +667),
        ("HL-DT-ST BD-RE WH16NS40", +667),
        ("MATSHITA DVD-RAM UJ-852S", +102),
        ("MATSHITA BD-MLT UJ260", +102),
        ("PIONEER DVD-RW DVR-112D", +48),
        ("PIONEER BD-RW BDR-209D", +48),
        ("SONY DVD RW DRU-800A", +6),
        ("SAMSUNG CDRW/DVD SN-324B", +6),
    ]

    /// Apply drive offset correction to audio data.
    ///
    /// Shifts the audio by the specified number of samples to compensate
    /// for the drive's read offset.
    ///
    /// - Parameters:
    ///   - audioData: Raw PCM audio data.
    ///   - offsetSamples: Number of samples to shift (positive = read ahead).
    /// - Returns: Offset-corrected audio data.
    public static func applyDriveOffset(
        audioData: Data,
        offsetSamples: Int
    ) -> Data {
        let byteOffset = offsetSamples * bytesPerSample

        if byteOffset == 0 {
            return audioData
        }

        if byteOffset > 0 {
            // Positive offset: skip leading bytes, pad trailing with silence
            let skip = min(byteOffset, audioData.count)
            var result = Data(audioData[skip...])
            result.append(Data(count: skip)) // Zero-pad
            return result
        } else {
            // Negative offset: pad leading with silence, truncate trailing
            let pad = min(-byteOffset, audioData.count)
            var result = Data(count: pad) // Zero-pad
            result.append(audioData[0..<(audioData.count - pad)])
            return result
        }
    }
}
