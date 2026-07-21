// ============================================================================
// MeedyaConverter — ConverterEngine unit tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Split from ConverterEngineTests.swift (re #452) to keep the test file
// under a manageable size. This file extends `ConverterEngineTests`
// (declared in ConverterEngineTests.swift) with a cohesive group of test
// methods. No test body, name, or assertion was changed during the split.
// ============================================================================

import XCTest
import ConverterEngine

extension ConverterEngineTests {
    // MARK: - AccurateRip Verifier Tests

    /// Verifies AccurateRip checksum hex formatting.
    func test_accurateRip_checksumHex() {
        let cs = AccurateRipChecksum(
            trackNumber: 1,
            checksumV1: 0xDEADBEEF,
            checksumV2: 0x12345678
        )
        XCTAssertEqual(cs.v1Hex, "DEADBEEF")
        XCTAssertEqual(cs.v2Hex, "12345678")
    }

    /// Verifies AccurateRip checksum calculation with known data.
    func test_accurateRip_calculateChecksum() {
        // Create 4 seconds of silence (44100 * 4 stereo samples * 4 bytes)
        // Silence should produce a checksum of 0
        let sampleCount = 44100 * 4
        let data = Data(count: sampleCount * 4) // All zeros

        let cs = AccurateRipVerifier.calculateChecksum(
            audioData: data,
            trackNumber: 1,
            totalTracks: 1,
            isFirstTrack: true,
            isLastTrack: true
        )
        // Silence with zero samples should give 0 checksums
        XCTAssertEqual(cs.checksumV1, 0)
        XCTAssertEqual(cs.checksumV2, 0)
        XCTAssertEqual(cs.trackNumber, 1)
    }

    /// Verifies AccurateRip checksum with non-zero data.
    func test_accurateRip_checksumNonZero() {
        // Create simple pattern: 4 bytes per sample, 3000 samples
        // (small enough to be > skipSamples for middle track)
        var data = Data(count: 12000) // 3000 samples
        // Write a pattern: each sample = 0x00000001
        for i in stride(from: 0, to: 12000, by: 4) {
            data[i] = 1
            data[i+1] = 0
            data[i+2] = 0
            data[i+3] = 0
        }

        // Middle track (not first, not last) — no skip
        let cs = AccurateRipVerifier.calculateChecksum(
            audioData: data,
            trackNumber: 5,
            totalTracks: 12,
            isFirstTrack: false,
            isLastTrack: false
        )
        // Each sample is 1, so v1 = sum(1 * (i+1)) for i=0..2999
        // = sum(1..3000) = 3000 * 3001 / 2 = 4501500
        XCTAssertEqual(cs.checksumV1, 4501500)
        XCTAssertTrue(cs.checksumV2 > 0)
    }

    /// Verifies database response parsing with empty data.
    func test_accurateRip_parseEmpty() {
        let entries = AccurateRipVerifier.parseDatabaseResponse(Data())
        XCTAssertTrue(entries.isEmpty)
    }

    /// Verifies database response parsing with constructed binary data.
    func test_accurateRip_parseDatabaseEntry() {
        // Construct a minimal AccurateRip database entry:
        // 1 byte: trackCount = 2
        // 4 bytes: discId1
        // 4 bytes: discId2
        // 4 bytes: cddbDiscId
        // Per track (9 bytes each): 1 byte confidence + 4 bytes CRC + 4 bytes reserved
        var data = Data()
        data.append(2) // trackCount = 2
        // discId1 = 0x00000001
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
        // discId2 = 0x00000002
        data.append(contentsOf: [0x02, 0x00, 0x00, 0x00])
        // cddbDiscId = 0x00000003
        data.append(contentsOf: [0x03, 0x00, 0x00, 0x00])
        // Track 1: confidence=5, CRC=0xAABBCCDD, reserved=0
        data.append(5)
        data.append(contentsOf: [0xDD, 0xCC, 0xBB, 0xAA])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        // Track 2: confidence=3, CRC=0x11223344, reserved=0
        data.append(3)
        data.append(contentsOf: [0x44, 0x33, 0x22, 0x11])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        let entries = AccurateRipVerifier.parseDatabaseResponse(data)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].trackCount, 2)
        XCTAssertEqual(entries[0].discId1, 1)
        XCTAssertEqual(entries[0].discId2, 2)
        XCTAssertEqual(entries[0].trackChecksums.count, 2)
        XCTAssertEqual(entries[0].trackChecksums[0].confidence, 5)
        XCTAssertEqual(entries[0].trackChecksums[0].checksumV1, 0xAABBCCDD)
        XCTAssertEqual(entries[0].trackChecksums[1].confidence, 3)
        XCTAssertEqual(entries[0].trackChecksums[1].checksumV1, 0x11223344)
    }

    /// Verifies verification against empty database returns notInDatabase.
    func test_accurateRip_verifyNotInDatabase() {
        let checksums = [
            AccurateRipChecksum(trackNumber: 1, checksumV1: 123, checksumV2: 456),
        ]
        let result = AccurateRipVerifier.verify(checksums: checksums, databaseEntries: [])
        XCTAssertEqual(result.trackResults.count, 1)
        XCTAssertEqual(result.trackResults[0].status, .notInDatabase)
        XCTAssertEqual(result.overallStatus, .notInDatabase)
    }

    /// Verifies successful v1 checksum match.
    func test_accurateRip_verifyMatch() {
        let checksums = [
            AccurateRipChecksum(trackNumber: 1, checksumV1: 0xAABBCCDD, checksumV2: 0),
        ]
        let dbEntry = AccurateRipDatabaseEntry(
            trackCount: 1,
            discId1: 1,
            discId2: 2,
            cddbDiscId: 3,
            trackChecksums: [
                .init(confidence: 10, checksumV1: 0xAABBCCDD, checksumV2: nil),
            ],
            confidence: 10
        )
        let result = AccurateRipVerifier.verify(
            checksums: checksums,
            databaseEntries: [dbEntry]
        )
        XCTAssertEqual(result.trackResults[0].status, .verified)
        XCTAssertEqual(result.trackResults[0].confidence, 10)
        XCTAssertEqual(result.trackResults[0].matchVersion, 1)
        XCTAssertEqual(result.overallStatus, .verified)
    }

    /// Verifies checksum mismatch detection.
    func test_accurateRip_verifyMismatch() {
        let checksums = [
            AccurateRipChecksum(trackNumber: 1, checksumV1: 0x11111111, checksumV2: 0x22222222),
        ]
        let dbEntry = AccurateRipDatabaseEntry(
            trackCount: 1,
            discId1: 1,
            discId2: 2,
            cddbDiscId: 3,
            trackChecksums: [
                .init(confidence: 5, checksumV1: 0xAAAAAAAA, checksumV2: nil),
            ],
            confidence: 5
        )
        let result = AccurateRipVerifier.verify(
            checksums: checksums,
            databaseEntries: [dbEntry]
        )
        XCTAssertEqual(result.trackResults[0].status, .mismatch)
        XCTAssertEqual(result.overallStatus, .mismatch)
    }

    /// Verifies disc result summary strings.
    func test_accurateRip_discResultSummary() {
        let allVerified = AccurateRipDiscResult(trackResults: [
            AccurateRipTrackResult(trackNumber: 1, status: .verified, confidence: 5,
                                   checksumV1: 1, checksumV2: 2, matchVersion: 1),
            AccurateRipTrackResult(trackNumber: 2, status: .verified, confidence: 3,
                                   checksumV1: 3, checksumV2: 4, matchVersion: 1),
        ])
        XCTAssertTrue(allVerified.summary.contains("All 2 tracks verified"))
        XCTAssertEqual(allVerified.minimumConfidence, 3)
        XCTAssertEqual(allVerified.verifiedCount, 2)
    }

    /// Verifies WAV PCM extraction.
    func test_accurateRip_extractPCMFromWAV() {
        // Minimal valid WAV header
        var wavData = Data()
        // RIFF header
        wavData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wavData.append(contentsOf: [0x24, 0x00, 0x00, 0x00]) // file size - 8
        wavData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        // fmt chunk
        wavData.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        wavData.append(contentsOf: [0x10, 0x00, 0x00, 0x00]) // chunk size = 16
        wavData.append(contentsOf: [0x01, 0x00])             // PCM
        wavData.append(contentsOf: [0x02, 0x00])             // 2 channels
        wavData.append(contentsOf: [0x44, 0xAC, 0x00, 0x00]) // 44100 Hz
        wavData.append(contentsOf: [0x10, 0xB1, 0x02, 0x00]) // byte rate
        wavData.append(contentsOf: [0x04, 0x00])             // block align
        wavData.append(contentsOf: [0x10, 0x00])             // bits per sample
        // data chunk
        wavData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wavData.append(contentsOf: [0x04, 0x00, 0x00, 0x00]) // chunk size = 4
        wavData.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD]) // audio data

        let pcm = AccurateRipVerifier.extractPCMFromWAV(wavData)
        XCTAssertNotNil(pcm)
        XCTAssertEqual(pcm?.count, 4)
        XCTAssertEqual(pcm?[0], 0xAA)
        XCTAssertEqual(pcm?[1], 0xBB)
    }

    /// Verifies drive offset application.
    func test_accurateRip_driveOffset() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

        // Zero offset = no change
        let zero = AccurateRipVerifier.applyDriveOffset(audioData: data, offsetSamples: 0)
        XCTAssertEqual(zero, data)

        // Positive offset: skip leading, pad trailing
        let positive = AccurateRipVerifier.applyDriveOffset(audioData: data, offsetSamples: 1)
        XCTAssertEqual(positive.count, data.count)
        XCTAssertEqual(positive[0], 0x05) // Skipped 4 bytes (1 sample)

        // Negative offset: pad leading, truncate trailing
        let negative = AccurateRipVerifier.applyDriveOffset(audioData: data, offsetSamples: -1)
        XCTAssertEqual(negative.count, data.count)
        XCTAssertEqual(negative[0], 0x00) // Zero-padded
    }

    /// Verifies common drive offsets table is populated.
    func test_accurateRip_driveOffsets() {
        XCTAssertFalse(AccurateRipVerifier.commonDriveOffsets.isEmpty)
        // PLEXTOR drives typically have +30 offset
        let plextor = AccurateRipVerifier.commonDriveOffsets.first {
            $0.model.contains("PX-716A")
        }
        XCTAssertNotNil(plextor)
        XCTAssertEqual(plextor?.offset, 30)
    }

    /// Verifies verification status properties.
    func test_accurateRip_verificationStatus() {
        XCTAssertTrue(AccurateRipTrackResult.VerificationStatus.verified.isAccurate)
        XCTAssertFalse(AccurateRipTrackResult.VerificationStatus.mismatch.isAccurate)
        XCTAssertFalse(AccurateRipTrackResult.VerificationStatus.notInDatabase.isAccurate)
        XCTAssertEqual(AccurateRipTrackResult.VerificationStatus.verified.displayName, "Verified")
    }

    // MARK: - AccurateRip Submission Tests

    /// Verifies submission config defaults.
    func test_accurateRip_submissionConfigDefaults() {
        let config = AccurateRipVerifier.SubmissionConfig()
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.driveModel, "")
        XCTAssertEqual(config.driveOffset, 0)
        XCTAssertEqual(config.softwareId, "MeedyaConverter")
    }

    /// Verifies submission payload is built for verified rips.
    func test_accurateRip_buildSubmissionPayload_verified() {
        let checksums = [
            AccurateRipChecksum(trackNumber: 1, checksumV1: 0xAABBCCDD, checksumV2: 0x11223344),
        ]
        let discResult = AccurateRipDiscResult(trackResults: [
            AccurateRipTrackResult(trackNumber: 1, status: .verified, confidence: 5,
                                   checksumV1: 0xAABBCCDD, checksumV2: 0x11223344, matchVersion: 1),
        ])
        let config = AccurateRipVerifier.SubmissionConfig(
            enabled: true, driveModel: "PLEXTOR PX-716A", driveOffset: 30
        )

        let payload = AccurateRipVerifier.buildSubmissionPayload(
            checksums: checksums, discResult: discResult,
            discId1: 100, discId2: 200, cddbDiscId: "AABB1122",
            config: config, errorFreeRip: true
        )

        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.trackCount, 1)
        XCTAssertEqual(payload?.discId1, 100)
        XCTAssertEqual(payload?.driveModel, "PLEXTOR PX-716A")
        XCTAssertEqual(payload?.driveOffset, 30)
        XCTAssertTrue(payload?.errorFreeRip ?? false)
    }

    /// Verifies submission payload is built for not-in-database rips (new disc).
    func test_accurateRip_buildSubmissionPayload_notInDatabase() {
        let checksums = [
            AccurateRipChecksum(trackNumber: 1, checksumV1: 0x12345678, checksumV2: 0x87654321),
        ]
        let discResult = AccurateRipDiscResult(trackResults: [
            AccurateRipTrackResult(trackNumber: 1, status: .notInDatabase,
                                   checksumV1: 0x12345678, checksumV2: 0x87654321),
        ])
        let config = AccurateRipVerifier.SubmissionConfig(enabled: true, driveModel: "Test Drive")

        let payload = AccurateRipVerifier.buildSubmissionPayload(
            checksums: checksums, discResult: discResult,
            discId1: 1, discId2: 2, cddbDiscId: "00000001",
            config: config, errorFreeRip: true
        )

        // Not-in-database is acceptable — this adds a new entry
        XCTAssertNotNil(payload)
    }

    /// Verifies submission is blocked for mismatched rips.
    func test_accurateRip_buildSubmissionPayload_mismatchBlocked() {
        let checksums = [
            AccurateRipChecksum(trackNumber: 1, checksumV1: 0x11111111, checksumV2: 0x22222222),
        ]
        let discResult = AccurateRipDiscResult(trackResults: [
            AccurateRipTrackResult(trackNumber: 1, status: .mismatch,
                                   checksumV1: 0x11111111, checksumV2: 0x22222222),
        ])
        let config = AccurateRipVerifier.SubmissionConfig(enabled: true)

        let payload = AccurateRipVerifier.buildSubmissionPayload(
            checksums: checksums, discResult: discResult,
            discId1: 1, discId2: 2, cddbDiscId: "00000001",
            config: config, errorFreeRip: true
        )

        // Mismatched rips must not be submitted
        XCTAssertNil(payload)
    }

    /// Verifies submission is blocked when disabled.
    func test_accurateRip_buildSubmissionPayload_disabled() {
        let checksums = [
            AccurateRipChecksum(trackNumber: 1, checksumV1: 1, checksumV2: 2),
        ]
        let discResult = AccurateRipDiscResult(trackResults: [
            AccurateRipTrackResult(trackNumber: 1, status: .verified, confidence: 5,
                                   checksumV1: 1, checksumV2: 2, matchVersion: 1),
        ])
        let config = AccurateRipVerifier.SubmissionConfig(enabled: false)

        let payload = AccurateRipVerifier.buildSubmissionPayload(
            checksums: checksums, discResult: discResult,
            discId1: 1, discId2: 2, cddbDiscId: "00000001",
            config: config, errorFreeRip: true
        )

        XCTAssertNil(payload)
    }

    /// Verifies submission is blocked for rips with errors.
    func test_accurateRip_buildSubmissionPayload_ripErrors() {
        let checksums = [
            AccurateRipChecksum(trackNumber: 1, checksumV1: 1, checksumV2: 2),
        ]
        let discResult = AccurateRipDiscResult(trackResults: [
            AccurateRipTrackResult(trackNumber: 1, status: .verified, confidence: 5,
                                   checksumV1: 1, checksumV2: 2, matchVersion: 1),
        ])
        let config = AccurateRipVerifier.SubmissionConfig(enabled: true)

        let payload = AccurateRipVerifier.buildSubmissionPayload(
            checksums: checksums, discResult: discResult,
            discId1: 1, discId2: 2, cddbDiscId: "00000001",
            config: config, errorFreeRip: false
        )

        XCTAssertNil(payload)
    }

    /// Verifies binary encoding of submission data.
    func test_accurateRip_encodeSubmissionData() {
        let payload = AccurateRipVerifier.SubmissionPayload(
            trackCount: 2,
            discId1: 0x00000001,
            discId2: 0x00000002,
            cddbDiscId: "00000003",
            trackChecksums: [
                AccurateRipChecksum(trackNumber: 1, checksumV1: 0xAABBCCDD, checksumV2: 0x11223344),
                AccurateRipChecksum(trackNumber: 2, checksumV1: 0x55667788, checksumV2: 0x99AABBCC),
            ],
            driveModel: "Test",
            driveOffset: 0,
            softwareId: "MeedyaConverter",
            errorFreeRip: true
        )

        let data = AccurateRipVerifier.encodeSubmissionData(payload)

        // Track count (1 byte) + disc IDs (12 bytes) + 2 tracks * 9 bytes = 31 bytes
        XCTAssertEqual(data.count, 1 + 12 + 2 * 9)

        // First byte = track count
        XCTAssertEqual(data[0], 2)

        // Disc ID 1 at offset 1 (LE)
        XCTAssertEqual(data[1], 0x01)
        XCTAssertEqual(data[2], 0x00)
        XCTAssertEqual(data[3], 0x00)
        XCTAssertEqual(data[4], 0x00)

        // First track: confidence=1 at offset 13
        XCTAssertEqual(data[13], 1)
    }

    /// Verifies submission URL format.
    func test_accurateRip_submissionURL() {
        let url = AccurateRipVerifier.buildSubmissionURL(
            trackCount: 12,
            discId1: 0x0012ABCD,
            discId2: 0x00ABCDEF,
            cddbDiscId: "deadbeef"
        )
        XCTAssertTrue(url.contains("accuraterip/submit/"))
        XCTAssertTrue(url.contains("dBAR-012-"))
        XCTAssertTrue(url.contains("0012abcd"))
        XCTAssertTrue(url.contains("00abcdef"))
        XCTAssertTrue(url.contains("deadbeef"))
    }

    // MARK: - AudioDiscFidelity Tests

    /// Helper to create a sample TOC for testing.
    private func makeSampleTOC(
        trackCount: Int = 3,
        withIndexes: Bool = false,
        withCDText: Bool = false
    ) -> DiscTableOfContents {
        let tracks = (1...trackCount).map { i in
            DiscTrack(
                number: i,
                title: "Track \(i)",
                artist: "Artist",
                duration: 240.0,
                startSector: (i - 1) * 18000,
                sectorCount: 18000,
                isData: false,
                hasPreEmphasis: i == 2
            )
        }

        var indexes: [TrackIndex] = []
        if withIndexes {
            // Add INDEX 02 at 1 minute into track 1
            indexes.append(TrackIndex(
                trackNumber: 1,
                indexNumber: 2,
                sector: 4500,
                offsetInTrack: 60.0,
                absoluteTime: 60.0
            ))
            // Add INDEX 03 at 2 minutes into track 1
            indexes.append(TrackIndex(
                trackNumber: 1,
                indexNumber: 3,
                sector: 9000,
                offsetInTrack: 120.0,
                absoluteTime: 120.0
            ))
        }

        let cdText: CDTextInfo? = withCDText ? CDTextInfo(
            albumTitle: "Test Album",
            albumArtist: "Test Artist",
            trackTitles: Dictionary(uniqueKeysWithValues: (1...trackCount).map { ($0, "Song \($0)") }),
            trackArtists: Dictionary(uniqueKeysWithValues: (1...trackCount).map { ($0, "Artist \($0)") })
        ) : nil

        return DiscTableOfContents(
            discType: "Audio CD",
            tracks: tracks,
            indexes: indexes,
            leadOutSector: trackCount * 18000,
            firstTrackNumber: 1,
            lastTrackNumber: trackCount,
            cddbDiscId: "AB0CD123",
            musicBrainzDiscId: "mb-disc-id-test",
            catalogNumber: "1234567890123",
            cdText: cdText
        )
    }

    // MARK: CDTOC

    /// Verifies CDTOC string format.
    func test_audioDiscFidelity_buildCDTOCString() {
        let toc = makeSampleTOC()
        let tocString = AudioDiscFidelity.buildCDTOCString(toc: toc)
        XCTAssertEqual(tocString, "1 3 54000 0 18000 36000")
    }

    /// Verifies CDTOC FFmpeg arguments include all metadata.
    func test_audioDiscFidelity_buildCDTOCArguments() {
        let toc = makeSampleTOC()
        let args = AudioDiscFidelity.buildCDTOCArguments(toc: toc, format: .flac)

        XCTAssertTrue(args.contains("-metadata"))
        XCTAssertTrue(args.contains("CDTOC=1 3 54000 0 18000 36000"))
        XCTAssertTrue(args.contains("MUSICBRAINZ_DISCID=mb-disc-id-test"))
        XCTAssertTrue(args.contains("CDDB_DISCID=AB0CD123"))
        XCTAssertTrue(args.contains("MCN=1234567890123"))
        XCTAssertTrue(args.contains("UPC=1234567890123"))
        XCTAssertTrue(args.contains("DISCTYPE=Audio CD"))
        XCTAssertTrue(args.contains("TOTALTRACKS=3"))
    }

    /// Verifies CDTOC works for ALL formats (not just lossless).
    func test_audioDiscFidelity_cdtocAllFormats() {
        let toc = makeSampleTOC(trackCount: 1)
        for format in CDDAFormat.allCases {
            XCTAssertTrue(AudioDiscFidelity.supportsCDTOC(format),
                          "\(format) should support CDTOC")
            let args = AudioDiscFidelity.buildCDTOCArguments(toc: toc, format: format)
            XCTAssertFalse(args.isEmpty, "\(format) should produce CDTOC arguments")
        }
    }

    // MARK: Cuesheet

    /// Verifies cuesheet generation.
    func test_audioDiscFidelity_generateCuesheet() {
        let toc = makeSampleTOC(withCDText: true)
        let cue = AudioDiscFidelity.generateCuesheet(toc: toc, audioFileName: "disc.flac")

        XCTAssertTrue(cue.contains("CATALOG 1234567890123"))
        XCTAssertTrue(cue.contains("TITLE \"Test Album\""))
        XCTAssertTrue(cue.contains("PERFORMER \"Test Artist\""))
        XCTAssertTrue(cue.contains("FILE \"disc.flac\" WAVE"))
        XCTAssertTrue(cue.contains("TRACK 01 AUDIO"))
        XCTAssertTrue(cue.contains("TRACK 02 AUDIO"))
        XCTAssertTrue(cue.contains("TRACK 03 AUDIO"))
        XCTAssertTrue(cue.contains("TITLE \"Song 1\""))
        XCTAssertTrue(cue.contains("PERFORMER \"Artist 1\""))
        XCTAssertTrue(cue.contains("INDEX 01 00:00:00"))
        XCTAssertTrue(cue.contains("REM DISCID AB0CD123"))
    }

    /// Verifies cuesheet includes pre-emphasis flags.
    func test_audioDiscFidelity_cuesheetPreEmphasis() {
        let toc = makeSampleTOC()
        let cue = AudioDiscFidelity.generateCuesheet(toc: toc, audioFileName: "disc.wav")
        XCTAssertTrue(cue.contains("FLAGS PRE"))
    }

    /// Verifies cuesheet embedding with sub-track indexes.
    func test_audioDiscFidelity_cuesheetWithIndexes() {
        let toc = makeSampleTOC(withIndexes: true)
        let cue = AudioDiscFidelity.generateCuesheet(toc: toc, audioFileName: "disc.flac")
        XCTAssertTrue(cue.contains("INDEX 02"))
        XCTAssertTrue(cue.contains("INDEX 03"))
    }

    /// Verifies cuesheet supported for all formats.
    func test_audioDiscFidelity_cuesheetAllFormats() {
        for format in CDDAFormat.allCases {
            XCTAssertTrue(AudioDiscFidelity.supportsCuesheet(format),
                          "\(format) should support cuesheet")
        }
    }

    /// Verifies cuesheet arguments.
    func test_audioDiscFidelity_buildCuesheetArguments() {
        let toc = makeSampleTOC()
        let args = AudioDiscFidelity.buildCuesheetArguments(
            toc: toc, audioFileName: "disc.mp3", format: .mp3
        )
        XCTAssertTrue(args.contains { $0.hasPrefix("CUESHEET=") })
    }

    /// Verifies cue sidecar path generation.
    func test_audioDiscFidelity_cueSidecarPath() {
        let path = AudioDiscFidelity.buildCueSidecarPath(audioFilePath: "/music/disc.flac")
        XCTAssertEqual(path, "/music/disc.cue")
    }

    // MARK: Chapter Marks

    /// Verifies whole-disc chapter marks from track boundaries.
    func test_audioDiscFidelity_wholeDiscChapters() {
        let toc = makeSampleTOC()
        let chapters = AudioDiscFidelity.buildChapterMarks(toc: toc, wholeDiscMode: true)

        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].title, "Track 1")
        XCTAssertEqual(chapters[0].startTime, 0.0, accuracy: 0.01)
        XCTAssertEqual(chapters[1].startTime, 240.0, accuracy: 0.01)
        XCTAssertEqual(chapters[2].startTime, 480.0, accuracy: 0.01)
        // End times
        XCTAssertEqual(chapters[0].endTime!, 240.0, accuracy: 0.01)
        XCTAssertEqual(chapters[2].endTime!, 720.0, accuracy: 0.01)
    }

    /// Verifies chapter marks include sub-track indexes.
    func test_audioDiscFidelity_chaptersWithIndexes() {
        let toc = makeSampleTOC(withIndexes: true)
        let chapters = AudioDiscFidelity.buildChapterMarks(
            toc: toc, wholeDiscMode: true, includeIndexes: true
        )

        // 3 tracks + 2 indexes in track 1
        XCTAssertEqual(chapters.count, 5)
        let indexChapters = chapters.filter { $0.title.contains("Index") }
        XCTAssertEqual(indexChapters.count, 2)
    }

    /// Verifies per-track chapter marks from sub-track indexes.
    func test_audioDiscFidelity_perTrackIndexChapters() {
        let toc = makeSampleTOC(withIndexes: true)
        let chapters = AudioDiscFidelity.buildChapterMarks(
            toc: toc, wholeDiscMode: false, trackNumber: 1
        )

        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "Index 2")
        XCTAssertEqual(chapters[0].startTime, 60.0, accuracy: 0.01)
        XCTAssertEqual(chapters[1].title, "Index 3")
        XCTAssertEqual(chapters[1].startTime, 120.0, accuracy: 0.01)
    }

    /// Verifies no chapters when no sub-track indexes for a track.
    func test_audioDiscFidelity_noIndexesNoChapters() {
        let toc = makeSampleTOC(withIndexes: true)
        let chapters = AudioDiscFidelity.buildChapterMarks(
            toc: toc, wholeDiscMode: false, trackNumber: 3
        )
        XCTAssertTrue(chapters.isEmpty)
    }

    /// Verifies chapter support detection.
    func test_audioDiscFidelity_supportsChapters() {
        XCTAssertTrue(AudioDiscFidelity.supportsChapters(.mp3))
        XCTAssertTrue(AudioDiscFidelity.supportsChapters(.aacLC))
        XCTAssertTrue(AudioDiscFidelity.supportsChapters(.alac))
        XCTAssertTrue(AudioDiscFidelity.supportsChapters(.flac))
        XCTAssertTrue(AudioDiscFidelity.supportsChapters(.oggVorbis))
        XCTAssertTrue(AudioDiscFidelity.supportsChapters(.opus))
        XCTAssertFalse(AudioDiscFidelity.supportsChapters(.wav))
        XCTAssertFalse(AudioDiscFidelity.supportsChapters(.aiff))
    }

    // MARK: FFMETADATA

    /// Verifies FFMETADATA chapter file generation.
    func test_audioDiscFidelity_ffmetadataChapterFile() {
        let chapters = [
            ChapterMark(title: "Intro", startTime: 0.0, endTime: 60.0),
            ChapterMark(title: "Verse", startTime: 60.0, endTime: 180.0),
        ]
        let content = AudioDiscFidelity.buildFFmetadataChapterFile(chapters: chapters)

        XCTAssertTrue(content.hasPrefix(";FFMETADATA1\n"))
        XCTAssertTrue(content.contains("[CHAPTER]"))
        XCTAssertTrue(content.contains("TIMEBASE=1/1000"))
        XCTAssertTrue(content.contains("START=0"))
        XCTAssertTrue(content.contains("END=60000"))
        XCTAssertTrue(content.contains("title=Intro"))
        XCTAssertTrue(content.contains("START=60000"))
        XCTAssertTrue(content.contains("END=180000"))
        XCTAssertTrue(content.contains("title=Verse"))
    }

    /// Verifies FFMETADATA infers end time from next chapter.
    func test_audioDiscFidelity_ffmetadataInferredEndTime() {
        let chapters = [
            ChapterMark(title: "A", startTime: 0.0),
            ChapterMark(title: "B", startTime: 30.0),
        ]
        let content = AudioDiscFidelity.buildFFmetadataChapterFile(chapters: chapters)
        // First chapter end = second chapter start
        XCTAssertTrue(content.contains("END=30000"))
    }

    // MARK: Vorbis Chapter Tags

    /// Verifies Vorbis comment chapter arguments.
    func test_audioDiscFidelity_vorbisChapterArguments() {
        let chapters = [
            ChapterMark(title: "Track 1", startTime: 0.0),
            ChapterMark(title: "Track 2", startTime: 120.5),
        ]
        let args = AudioDiscFidelity.buildVorbisChapterArguments(chapters: chapters)

        XCTAssertTrue(args.contains("CHAPTER01=00:00:00.000"))
        XCTAssertTrue(args.contains("CHAPTER01NAME=Track 1"))
        XCTAssertTrue(args.contains("CHAPTER02=00:02:00.500"))
        XCTAssertTrue(args.contains("CHAPTER02NAME=Track 2"))
    }

    // MARK: ChapterMark / TrackIndex

    /// Verifies ChapterMark FFmpeg timestamp formatting.
    func test_chapterMark_ffmpegTimestamp() {
        let ch1 = ChapterMark(title: "T", startTime: 0.0)
        XCTAssertEqual(ch1.ffmpegTimestamp, "00:00:00.000")

        let ch2 = ChapterMark(title: "T", startTime: 3661.5)
        XCTAssertEqual(ch2.ffmpegTimestamp, "01:01:01.500")
    }

    /// Verifies TrackIndex MSF string formatting.
    func test_trackIndex_msfString() {
        let idx = TrackIndex(trackNumber: 1, indexNumber: 1, sector: 0)
        XCTAssertEqual(idx.msfString, "00:00:00")

        let idx2 = TrackIndex(trackNumber: 1, indexNumber: 2, sector: 9075)
        // 9075 / (75*60) = 2 min, (9075/75)%60 = 1 sec, 9075%75 = 0 frames
        XCTAssertEqual(idx2.msfString, "02:01:00")
    }

    /// Verifies DiscTableOfContents computed properties.
    func test_discTableOfContents_properties() {
        let toc = makeSampleTOC(withIndexes: true)

        XCTAssertEqual(toc.totalDuration, Double(54000) / 75.0, accuracy: 0.01)
        XCTAssertEqual(toc.trackOffsets, [0, 18000, 36000])
        XCTAssertEqual(toc.chapterIndexes.count, 2)
        XCTAssertTrue(toc.hasSubTrackIndexes)
    }

    /// Verifies disc without indexes reports no sub-tracks.
    func test_discTableOfContents_noIndexes() {
        let toc = makeSampleTOC()
        XCTAssertFalse(toc.hasSubTrackIndexes)
        XCTAssertTrue(toc.chapterIndexes.isEmpty)
    }

    // MARK: Whole-Disc Ripping

    /// Verifies cdparanoia arguments for whole-disc rip.
    func test_audioDiscFidelity_wholeDiscRipArguments() {
        let args = AudioDiscFidelity.buildWholeDiscRipArguments(
            devicePath: "/dev/cdrom",
            outputPath: "/tmp/disc.wav",
            paranoia: .full,
            readSpeed: 8
        )

        XCTAssertTrue(args.contains("-d"))
        XCTAssertTrue(args.contains("/dev/cdrom"))
        XCTAssertTrue(args.contains("-S"))
        XCTAssertTrue(args.contains("8"))
        XCTAssertTrue(args.contains("[.0]-"))
        XCTAssertTrue(args.contains("/tmp/disc.wav"))
    }

    /// Verifies whole-disc encode arguments combine all fidelity features.
    func test_audioDiscFidelity_wholeDiscEncodeArguments() {
        let toc = makeSampleTOC(withIndexes: true, withCDText: true)
        let args = AudioDiscFidelity.buildWholeDiscEncodeArguments(
            inputWavPath: "/tmp/disc.wav",
            outputPath: "/music/disc.flac",
            format: .flac,
            toc: toc,
            embedCuesheet: true,
            embedCDTOC: true,
            embedChapters: true,
            chapterMetadataPath: "/tmp/chapters.txt"
        )

        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/disc.wav"))
        XCTAssertTrue(args.contains("/tmp/chapters.txt"))
        XCTAssertTrue(args.contains("-c:a"))
        XCTAssertTrue(args.contains("flac"))
        XCTAssertTrue(args.contains("-compression_level"))
        XCTAssertTrue(args.contains { $0.hasPrefix("CDTOC=") })
        XCTAssertTrue(args.contains { $0.hasPrefix("CUESHEET=") })
        XCTAssertTrue(args.contains { $0.hasPrefix("CHAPTER01=") })
        XCTAssertTrue(args.contains("-y"))
        XCTAssertTrue(args.contains("/music/disc.flac"))
    }

    /// Verifies whole-disc encode with lossy format includes bitrate.
    func test_audioDiscFidelity_wholeDiscEncodeLossy() {
        let toc = makeSampleTOC()
        let args = AudioDiscFidelity.buildWholeDiscEncodeArguments(
            inputWavPath: "/tmp/disc.wav",
            outputPath: "/music/disc.mp3",
            format: .mp3,
            toc: toc,
            bitrate: 320,
            embedChapters: false
        )

        XCTAssertTrue(args.contains("-b:a"))
        XCTAssertTrue(args.contains("320k"))
        XCTAssertFalse(args.contains("-compression_level"))
    }

    // MARK: Filename Generation

    /// Verifies whole-disc filename generation with CD-TEXT.
    func test_audioDiscFidelity_wholeDiscFilename() {
        let cdText = CDTextInfo(
            albumTitle: "Greatest Hits",
            albumArtist: "The Band",
            trackTitles: [:],
            trackArtists: [:]
        )
        let name = AudioDiscFidelity.buildWholeDiscFilename(cdText: cdText, format: .flac)
        XCTAssertEqual(name, "The Band - Greatest Hits.flac")
    }

    /// Verifies filename generation without CD-TEXT.
    func test_audioDiscFidelity_wholeDiscFilenameNoText() {
        let name = AudioDiscFidelity.buildWholeDiscFilename(cdText: nil, format: .wav)
        XCTAssertEqual(name, "Full Disc.wav")
    }

    /// Verifies filename sanitization.
    func test_audioDiscFidelity_filenameSanitization() {
        let cdText = CDTextInfo(
            albumTitle: "AC/DC: Live",
            albumArtist: nil,
            trackTitles: [:],
            trackArtists: [:]
        )
        let name = AudioDiscFidelity.buildWholeDiscFilename(cdText: cdText, format: .mp3)
        XCTAssertEqual(name, "AC-DC- Live.mp3")
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
    }

    // MARK: CuesheetEmbedMethod

    /// Verifies CuesheetEmbedMethod raw values.
    func test_cuesheetEmbedMethod_rawValues() {
        XCTAssertEqual(CuesheetEmbedMethod.flacNative.rawValue, "flac_native")
        XCTAssertEqual(CuesheetEmbedMethod.vorbisComment.rawValue, "vorbis_comment")
        XCTAssertEqual(CuesheetEmbedMethod.id3v2.rawValue, "id3v2")
        XCTAssertEqual(CuesheetEmbedMethod.mp4Tag.rawValue, "mp4_tag")
        XCTAssertEqual(CuesheetEmbedMethod.wmaTag.rawValue, "wma_tag")
        XCTAssertEqual(CuesheetEmbedMethod.apeTag.rawValue, "ape_tag")
    }

    /// Verifies chapter embed arguments reference the metadata file.
    func test_audioDiscFidelity_chapterEmbedArguments() {
        let args = AudioDiscFidelity.buildChapterEmbedArguments(
            metadataFilePath: "/tmp/meta.txt"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/meta.txt"))
        XCTAssertTrue(args.contains("-map_metadata"))
        XCTAssertTrue(args.contains("-map_chapters"))
        XCTAssertTrue(args.contains("1"))
    }

}
