// ============================================================================
// MeedyaConverter — RawCDImagingExecutorTests (Issue #495, part of #492)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Pure, CI-runnable tests for the raw Audio CD → BIN/CUE executor's logic:
//   * RawCDReadPlanner cdrdao argument builders + expectedBinByteCount
//   * RawCDImagingConfig(imagingConfig:) — the wiring that consumes the
//     previously dead ImagingConfig.imageFormat and refuses non-.bin formats
//   * CdrdaoTocParser — .toc → DiscTableOfContents, including a round-trip
//     through the reused CueSheetWriter/CueSheetParser
//   * CdrdaoProgressParser — stderr line → typed event, and makeProgress
//   * DiscProtectionDetector — classification + policy for the DRM gate
//   * BundledToolLocator — search-directory ordering + temp-dir locate()
//   * DriveListingParser — scanbus / drutil list / drutil status parsers
//   * ImageVerification + DiscImageFormat.ccd / supportsRawAudioImaging
//
// Nothing here launches cdrdao or touches a device: DiscImagingController's
// device-facing methods are compile-checked only and hardware-verified on the
// manual matrix. Only public API is exercised (no @testable import), matching
// the policy at the top of ConverterEngineTests.swift.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class RawCDImagingExecutorTests: XCTestCase {

    // =========================================================================
    // MARK: - 1. RawCDReadPlanner argument builders
    // =========================================================================

    func test_buildReadTocArguments_minimal() {
        let args = RawCDReadPlanner.buildReadTocArguments(
            device: "/dev/sr0",
            datafileName: "album.bin",
            tocPath: "/out/album.toc"
        )
        XCTAssertEqual(args, [
            "read-toc", "--device", "/dev/sr0",
            "--datafile", "album.bin", "-v", "2", "/out/album.toc",
        ])
        XCTAssertEqual(args.last, "/out/album.toc", "toc-file must be the final argument")
    }

    func test_buildReadTocArguments_maximal() {
        let args = RawCDReadPlanner.buildReadTocArguments(
            device: "/dev/sr0",
            driver: "generic-mmc",
            session: 2,
            fastToc: true,
            datafileName: "album.bin",
            tocPath: "/out/album.toc"
        )
        XCTAssertEqual(args, [
            "read-toc", "--device", "/dev/sr0",
            "--driver", "generic-mmc",
            "--session", "2",
            "--fast-toc",
            "--datafile", "album.bin", "-v", "2", "/out/album.toc",
        ])
    }

    func test_buildReadCdArguments_default() {
        let config = RawCDImagingConfig(
            device: "/dev/sr0",
            binPath: "/out/album.bin",
            tocPath: "/out/album.toc"
        )
        let args = RawCDReadPlanner.buildReadCdArguments(config: config)
        XCTAssertEqual(args, [
            "read-cd", "--read-raw", "--device", "/dev/sr0",
            "--paranoia-mode", "3",
            "--datafile", "/out/album.bin", "-v", "2", "/out/album.toc",
        ])
        XCTAssertTrue(args.contains("--read-raw"))
        XCTAssertFalse(args.contains("--read-subchan"))
        XCTAssertEqual(args.last, "/out/album.toc")
    }

    func test_buildReadCdArguments_allOptions() {
        let config = RawCDImagingConfig(
            device: "/dev/sr0",
            driver: "generic-mmc",
            readSpeed: 8,
            paranoia: .noScratchRepair,
            captureSubchannel: true,
            session: 3,
            binPath: "/out/album.bin",
            tocPath: "/out/album.toc"
        )
        let args = RawCDReadPlanner.buildReadCdArguments(config: config)
        XCTAssertEqual(args, [
            "read-cd", "--read-raw", "--device", "/dev/sr0",
            "--driver", "generic-mmc",
            "--speed", "8",
            "--paranoia-mode", "2",
            "--read-subchan", "rw_raw",
            "--session", "3",
            "--datafile", "/out/album.bin", "-v", "2", "/out/album.toc",
        ])
    }

    func test_buildScanbusArguments() {
        XCTAssertEqual(RawCDReadPlanner.buildScanbusArguments(), ["scanbus"])
    }

    func test_buildMacOSUnmountArguments() {
        let result = RawCDReadPlanner.buildMacOSUnmountArguments(diskNode: "/dev/disk4")
        XCTAssertEqual(result.tool, "diskutil")
        XCTAssertEqual(result.arguments, ["unmountDisk", "/dev/disk4"])
    }

    func test_expectedBinByteCount() {
        let toc = DiscTableOfContents(leadOutSector: 15595)
        XCTAssertEqual(RawCDReadPlanner.expectedBinByteCount(toc: toc, includeSubchannel: false), 15595 * 2352)
        XCTAssertEqual(RawCDReadPlanner.expectedBinByteCount(toc: toc, includeSubchannel: true), 15595 * 2448)
        let empty = DiscTableOfContents(leadOutSector: 0)
        XCTAssertEqual(RawCDReadPlanner.expectedBinByteCount(toc: empty, includeSubchannel: false), 0)
    }

    // =========================================================================
    // MARK: - 2. RawCDImagingConfig(imagingConfig:) wiring
    // =========================================================================

    func test_imagingConfigBridge_binPasses() throws {
        let imaging = ImagingConfig(
            sourcePath: "/dev/sr0",
            outputPath: "/out/My Album.bin",
            imageFormat: .bin,
            readSpeed: 4,
            verifyAfterCopy: false
        )
        let config = try RawCDImagingConfig(imagingConfig: imaging, device: "/dev/sr0")
        XCTAssertEqual(config.binPath, "/out/My Album.bin")
        XCTAssertEqual(config.tocPath, "/out/My Album.toc")
        XCTAssertEqual(config.readSpeed, 4)
        XCTAssertFalse(config.verifyAfterRead)
    }

    func test_imagingConfigBridge_nonBinFormatsThrow() {
        for format: DiscImageFormat in [.iso, .img, .nrg, .mdf, .ccd] {
            let imaging = ImagingConfig(
                sourcePath: "/dev/sr0",
                outputPath: "/out/album.\(format.rawValue)",
                imageFormat: format
            )
            XCTAssertThrowsError(
                try RawCDImagingConfig(imagingConfig: imaging, device: "/dev/sr0"),
                "\(format.rawValue) must be refused"
            ) { error in
                guard case ImagingError.unsupportedImageFormat(let offending) = error else {
                    return XCTFail("Expected unsupportedImageFormat, got \(error)")
                }
                XCTAssertEqual(offending, format)
            }
        }
    }

    // =========================================================================
    // MARK: - 3. CdrdaoTocParser
    // =========================================================================

    /// A three-track CD_DA image with CATALOG, disc + track CD_TEXT, an ISRC
    /// and PRE_EMPHASIS on track 2, a SILENCE pregap on track 1, and an in-file
    /// pregap (START) plus two sub-indexes on track 3.
    private let threeTrackToc = """
    CD_DA

    CATALOG "1234567890123"

    CD_TEXT {
      LANGUAGE_MAP {
        0 : EN
      }
      LANGUAGE 0 {
        TITLE "Greatest Hits"
        PERFORMER "The Band"
        SONGWRITER "A Writer"
      }
    }

    // Track 1
    TRACK AUDIO
    NO COPY
    NO PRE_EMPHASIS
    TWO_CHANNEL_AUDIO
    CD_TEXT {
      LANGUAGE 0 {
        TITLE "Opening"
        PERFORMER "The Band"
      }
    }
    SILENCE 00:02:00
    FILE "album.bin" 0 03:00:00

    // Track 2
    TRACK AUDIO
    NO COPY
    PRE_EMPHASIS
    TWO_CHANNEL_AUDIO
    ISRC "GBAYE0000351"
    CD_TEXT {
      LANGUAGE 0 {
        TITLE "Second"
        PERFORMER "The Band"
      }
    }
    FILE "album.bin" 03:02:00 04:00:00

    // Track 3
    TRACK AUDIO
    NO COPY
    NO PRE_EMPHASIS
    TWO_CHANNEL_AUDIO
    FILE "album.bin" 07:02:00 05:00:00
    START 00:02:00
    INDEX 00:30:00
    INDEX 01:00:00
    """

    func test_tocParser_fullFidelity() throws {
        let toc = try CdrdaoTocParser.parse(threeTrackToc)

        XCTAssertEqual(toc.discType, "Audio CD")
        XCTAssertEqual(toc.catalogNumber, "1234567890123")
        XCTAssertEqual(toc.tracks.count, 3)
        XCTAssertEqual(toc.firstTrackNumber, 1)
        XCTAssertEqual(toc.lastTrackNumber, 3)

        // Track 1: 150 (silence) + 13500 (03:00:00) = 13650; INDEX 01 after the
        // 150-frame pregap.
        let t1 = toc.tracks[0]
        XCTAssertEqual(t1.number, 1)
        XCTAssertEqual(t1.startSector, 150)
        XCTAssertEqual(t1.sectorCount, 13650)
        XCTAssertEqual(t1.trackMode, .audio)
        XCTAssertFalse(t1.hasPreEmphasis)
        XCTAssertNil(t1.isrc)

        // Track 2: starts at 13650, length 04:00:00 = 18000.
        let t2 = toc.tracks[1]
        XCTAssertEqual(t2.number, 2)
        XCTAssertEqual(t2.startSector, 13650)
        XCTAssertEqual(t2.sectorCount, 18000)
        XCTAssertTrue(t2.hasPreEmphasis)
        XCTAssertEqual(t2.isrc, "GBAYE0000351")

        // Track 3: track data starts at 31650, START 00:02:00 pushes INDEX 01
        // to 31800; length 05:00:00 = 22500.
        let t3 = toc.tracks[2]
        XCTAssertEqual(t3.number, 3)
        XCTAssertEqual(t3.startSector, 31800)
        XCTAssertEqual(t3.sectorCount, 22500)

        // Lead-out is the final cumulative sector.
        XCTAssertEqual(toc.leadOutSector, 54150)

        // Index points.
        XCTAssertEqual(indexSector(toc, track: 1, index: 0), 0)
        XCTAssertEqual(indexSector(toc, track: 1, index: 1), 150)
        XCTAssertEqual(indexSector(toc, track: 2, index: 1), 13650)
        XCTAssertEqual(indexSector(toc, track: 3, index: 0), 31650)
        XCTAssertEqual(indexSector(toc, track: 3, index: 1), 31800)
        XCTAssertEqual(indexSector(toc, track: 3, index: 2), 31800 + 2250) // INDEX 00:30:00
        XCTAssertEqual(indexSector(toc, track: 3, index: 3), 31800 + 4500) // INDEX 01:00:00

        // CD-TEXT.
        XCTAssertEqual(toc.cdText?.albumTitle, "Greatest Hits")
        XCTAssertEqual(toc.cdText?.albumArtist, "The Band")
        XCTAssertEqual(toc.cdText?.songwriter, "A Writer")
        XCTAssertEqual(toc.cdText?.trackTitles[1], "Opening")
        XCTAssertEqual(toc.cdText?.trackTitles[2], "Second")
    }

    func test_tocParser_mixedModeDataTrack() throws {
        let toc = try CdrdaoTocParser.parse("""
        CD_ROM
        // Track 1
        TRACK MODE1_RAW
        FILE "data.bin" 0 10:00:00
        """)
        XCTAssertEqual(toc.tracks.count, 1)
        XCTAssertEqual(toc.tracks[0].trackMode, .mode1)
        XCTAssertTrue(toc.tracks[0].isData)
    }

    func test_tocParser_crlfAndCommentTolerance() throws {
        let crlf = "CD_DA\r\n// a comment line\r\nTRACK AUDIO\r\nFILE \"a.bin\" 0 02:00:00\r\n"
        let toc = try CdrdaoTocParser.parse(crlf)
        XCTAssertEqual(toc.tracks.count, 1)
        XCTAssertEqual(toc.tracks[0].sectorCount, 9000) // 02:00:00 = 2*4500
    }

    func test_tocParser_malformedInputsThrow() {
        // Unknown TRACK mode.
        XCTAssertThrowsError(try CdrdaoTocParser.parse("CD_DA\nTRACK WEIRD\nFILE \"a.bin\" 0 01:00:00")) {
            assertMalformedToc($0)
        }
        // Unparsable MSF.
        XCTAssertThrowsError(try CdrdaoTocParser.parse("CD_DA\nTRACK AUDIO\nFILE \"a.bin\" 0 99:aa:00")) {
            assertMalformedToc($0)
        }
        // TRACK with no data statement.
        XCTAssertThrowsError(try CdrdaoTocParser.parse("CD_DA\nTRACK AUDIO")) {
            assertMalformedToc($0)
        }
    }

    /// The round-trip contract: parse → CueSheetWriter.write → CueSheetParser
    /// preserves track numbers/modes, ISRC, catalogue, CD-TEXT, pre-emphasis,
    /// and INDEX positions (leadOutSector and the last track's sectorCount are
    /// documented CUE-format losses and excluded).
    func test_tocParser_roundTripThroughCueSheet() throws {
        let original = try CdrdaoTocParser.parse(threeTrackToc)
        let cue = CueSheetWriter.write(toc: original, binaryFileName: "album.bin")
        let restored = try CueSheetParser.parse(cue)

        XCTAssertEqual(restored.catalogNumber, original.catalogNumber)
        XCTAssertEqual(restored.tracks.count, original.tracks.count)

        for (a, b) in zip(original.tracks, restored.tracks) {
            XCTAssertEqual(a.number, b.number)
            XCTAssertEqual(a.startSector, b.startSector)
            XCTAssertEqual(a.trackMode, b.trackMode)
            XCTAssertEqual(a.hasPreEmphasis, b.hasPreEmphasis)
            XCTAssertEqual(a.isrc, b.isrc)
        }

        XCTAssertEqual(restored.cdText?.albumTitle, original.cdText?.albumTitle)
        XCTAssertEqual(restored.cdText?.albumArtist, original.cdText?.albumArtist)
        XCTAssertEqual(restored.cdText?.songwriter, original.cdText?.songwriter)
        XCTAssertEqual(restored.cdText?.trackTitles[1], "Opening")
        XCTAssertEqual(restored.cdText?.trackTitles[2], "Second")

        // Index positions survive (INDEX 00/01 on track 1, 00/01/02/03 on 3).
        XCTAssertEqual(indexSector(restored, track: 1, index: 0), 0)
        XCTAssertEqual(indexSector(restored, track: 1, index: 1), 150)
        XCTAssertEqual(indexSector(restored, track: 3, index: 2), 31800 + 2250)
        XCTAssertEqual(indexSector(restored, track: 3, index: 3), 31800 + 4500)
    }

    // =========================================================================
    // MARK: - 4. CdrdaoProgressParser
    // =========================================================================

    func test_progressParser_events() {
        XCTAssertEqual(
            CdrdaoProgressParser.parseCdrdaoProgress(
                line: " 1      AUDIO   0      00:00:00(     0)     03:27:70( 15595)"),
            .tocTableRow(track: 1, mode: "AUDIO", startSector: 0, lengthSectors: 15595)
        )
        XCTAssertEqual(
            CdrdaoProgressParser.parseCdrdaoProgress(line: "Reading track 3 (AUDIO)..."),
            .readingTrack(number: 3, mode: "AUDIO")
        )
        XCTAssertEqual(
            CdrdaoProgressParser.parseCdrdaoProgress(line: "Copying audio tracks 1-12: start..."),
            .readingTrack(number: 1, mode: "AUDIO")
        )
        XCTAssertEqual(CdrdaoProgressParser.parseCdrdaoProgress(line: "Found ISRC code."), .foundISRC)
        XCTAssertEqual(
            CdrdaoProgressParser.parseCdrdaoProgress(line: "Found disk catalogue number."),
            .foundCatalogNumber
        )
        XCTAssertEqual(
            CdrdaoProgressParser.parseCdrdaoProgress(
                line: "Reading of toc and track data finished successfully."),
            .finished
        )
        XCTAssertEqual(
            CdrdaoProgressParser.parseCdrdaoProgress(line: "ERROR: Unit not ready, giving up."),
            .fatalError(message: "Unit not ready, giving up.")
        )
        XCTAssertEqual(
            CdrdaoProgressParser.parseCdrdaoProgress(
                line: "/dev/sr0: MATSHITA DVD-RAM UJ-8E0 Rev: 1.00"),
            .driveIdentified(description: "/dev/sr0: MATSHITA DVD-RAM UJ-8E0 Rev: 1.00")
        )
        XCTAssertNil(CdrdaoProgressParser.parseCdrdaoProgress(line: "Starting write at speed 8..."))
        XCTAssertNil(CdrdaoProgressParser.parseCdrdaoProgress(line: ""))
    }

    func test_progressParser_makeProgress() {
        let half = CdrdaoProgressParser.makeProgress(
            bytesOnDisk: 5000, expectedTotalBytes: 10000,
            currentTrack: 3, errorCount: 2, bytesPerSecond: 1234
        )
        XCTAssertEqual(half.fractionComplete, 0.5)
        XCTAssertEqual(half.errorCount, 2)
        XCTAssertEqual(half.currentSector, 3)

        // Zero total → unknown fraction.
        let unknown = CdrdaoProgressParser.makeProgress(
            bytesOnDisk: 5000, expectedTotalBytes: 0,
            currentTrack: nil, errorCount: 0, bytesPerSecond: 0
        )
        XCTAssertNil(unknown.totalBytes)
        XCTAssertNil(unknown.fractionComplete)

        // Over-run clamps to 1.0.
        let clamped = CdrdaoProgressParser.makeProgress(
            bytesOnDisk: 15000, expectedTotalBytes: 10000,
            currentTrack: 1, errorCount: 0, bytesPerSecond: 0
        )
        XCTAssertEqual(clamped.fractionComplete, 1.0)
    }

    // =========================================================================
    // MARK: - 5. DiscProtectionDetector
    // =========================================================================

    func test_detector_classification() {
        // Plain Red Book Audio CD — the P1 target — is unprotected.
        XCTAssertEqual(DiscProtectionDetector.detect(markers:
            DiscProtectionMarkers(discType: .audioCd)), .none)
        // Audio CD with an unreadable extra data session → structural.
        XCTAssertEqual(DiscProtectionDetector.detect(markers:
            DiscProtectionMarkers(discType: .audioCd, hasUnreadableDataSession: true)), .unknownStructural)
        // DVD with the copyright flag set → CSS; without → none.
        XCTAssertEqual(DiscProtectionDetector.detect(markers:
            DiscProtectionMarkers(discType: .dvdVideo, dvdCopyrightFlagSet: true)), .css)
        XCTAssertEqual(DiscProtectionDetector.detect(markers:
            DiscProtectionMarkers(discType: .dvdVideo, dvdCopyrightFlagSet: false)), .none)
        // Blu-ray with AACS directory → AACS; with BDSVM (and AACS) → BD+.
        XCTAssertEqual(DiscProtectionDetector.detect(markers:
            DiscProtectionMarkers(discType: .bluray, rootEntryNames: ["BDMV", "AACS"])), .aacs)
        XCTAssertEqual(DiscProtectionDetector.detect(markers:
            DiscProtectionMarkers(discType: .bluray, rootEntryNames: ["BDMV", "AACS", "BDSVM"])), .bdPlus)
        // UHD Blu-ray with AACS → AACS 2.0.
        XCTAssertEqual(DiscProtectionDetector.detect(markers:
            DiscProtectionMarkers(discType: .uhdBluray, rootEntryNames: ["AACS"])), .aacs2)
        // AACS directory on a DVD-typed disc → structural mismatch.
        XCTAssertEqual(DiscProtectionDetector.detect(markers:
            DiscProtectionMarkers(discType: .dvdVideo, rootEntryNames: ["AACS"])), .unknownStructural)
        // Root-entry matching is case-insensitive.
        XCTAssertEqual(DiscProtectionDetector.detect(markers:
            DiscProtectionMarkers(discType: .bluray, rootEntryNames: ["bdmv", "aacs"])), .aacs)
    }

    func test_detector_policy() {
        XCTAssertEqual(DiscProtectionDetector.policy(for: .none), .proceed)
        for protection: DiscProtectionType in [.css, .aacs, .bdPlus, .aacs2, .unknownStructural] {
            guard case .refuse(let reason) = DiscProtectionDetector.policy(for: protection) else {
                return XCTFail("\(protection) must refuse")
            }
            XCTAssertFalse(reason.isEmpty)
            XCTAssertTrue(reason.contains("never circumvents"),
                          "refusal must state the no-circumvention policy")
        }
    }

    // =========================================================================
    // MARK: - 6. BundledToolLocator
    // =========================================================================

    func test_locator_searchDirectoriesOrdering() {
        let dirs = BundledToolLocator.searchDirectories(
            userOverridePath: "/custom/bin/cdrdao",
            bundleURL: URL(fileURLWithPath: "/App.app"),
            resourcePath: "/App.app/Contents/Resources",
            executablePath: "/App.app/Contents/MacOS/App"
        )
        XCTAssertEqual(dirs, [
            "/custom/bin",
            "/App.app/Contents/Helpers",
            "/App.app/Contents/Resources/Tools",
            "/App.app/Contents/Resources",
            "/App.app/Contents/MacOS",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
        ])
    }

    func test_locator_searchDirectoriesNilInjectionsOmitted() {
        let dirs = BundledToolLocator.searchDirectories(
            userOverridePath: nil, bundleURL: nil, resourcePath: nil, executablePath: nil
        )
        XCTAssertEqual(dirs, ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"])
    }

    func test_locator_locateViaExecutableOverrideAndCache() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let binary = tempDir.appendingPathComponent("cdrdao")
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let locator = BundledToolLocator(toolName: uniqueToolName(), userOverridePath: binary.path)
        XCTAssertEqual(try locator.locate(), binary.path)

        // Cache survives deletion of the underlying file…
        try FileManager.default.removeItem(at: binary)
        XCTAssertEqual(try locator.locate(), binary.path)

        // …until cleared, after which the (unique) tool is not found anywhere.
        locator.clearCache()
        XCTAssertThrowsError(try locator.locate()) { assertToolNotFound($0) }
    }

    func test_locator_nonExecutableOverrideSkipped() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let binary = tempDir.appendingPathComponent("cdrdao")
        try Data("not executable".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: binary.path)

        let locator = BundledToolLocator(toolName: uniqueToolName(), userOverridePath: binary.path)
        XCTAssertThrowsError(try locator.locate()) { assertToolNotFound($0) }
    }

    func test_locator_nothingFound() {
        let locator = BundledToolLocator(toolName: uniqueToolName())
        XCTAssertThrowsError(try locator.locate()) { assertToolNotFound($0) }
    }

    // =========================================================================
    // MARK: - 7. DriveListingParser
    // =========================================================================

    func test_driveParser_scanbus() {
        let output = """
        Using libscg version 'ubuntu-0.9'
        /dev/sr0 : TSSTcorp, CDDVDW SH-224DB, SB00

        /dev/sr1 : HL-DT-ST, DVDRAM GH24, 1.00
        """
        let drives = DriveListingParser.parseScanbus(output)
        XCTAssertEqual(drives.count, 2)
        XCTAssertEqual(drives[0].device, "/dev/sr0")
        XCTAssertEqual(drives[0].description, "TSSTcorp, CDDVDW SH-224DB, SB00")
        XCTAssertEqual(drives[1].device, "/dev/sr1")
    }

    func test_driveParser_drutilListNeverFabricatesDevice() {
        let output = """
        Vendor   Product           Rev
        1  HL-DT-ST DVDRW GX40N     RQ09  via USB
        2  MATSHITA DVD-R UJ-8A8    HB13
        """
        let drives = DriveListingParser.parseDrutilList(output)
        XCTAssertEqual(drives.count, 2)
        // Regression: `drutil list` reveals no node, so device MUST be nil —
        // never the old fabricated "/dev/rdisk<n>".
        XCTAssertNil(drives[0].device)
        XCTAssertNil(drives[1].device)
        XCTAssertTrue(drives[0].description.contains("HL-DT-ST"))
    }

    func test_driveParser_drutilStatusDeviceName() {
        let withMedia = """
         Type: CD-ROM
         Name: /dev/disk4
         Sessions: 1
        """
        XCTAssertEqual(DriveListingParser.parseDrutilStatusDeviceName(withMedia), "/dev/disk4")
        XCTAssertNil(DriveListingParser.parseDrutilStatusDeviceName("No Media Inserted"))
    }

    func test_driveParser_rawDeviceNode() {
        XCTAssertEqual(DriveListingParser.rawDeviceNode(forDiskNode: "/dev/disk4"), "/dev/rdisk4")
        XCTAssertEqual(DriveListingParser.rawDeviceNode(forDiskNode: "/dev/sr0"), "/dev/sr0")
        XCTAssertEqual(DriveListingParser.rawDeviceNode(forDiskNode: "not a node"), "not a node")
    }

    // =========================================================================
    // MARK: - 8. ImageVerification
    // =========================================================================

    func test_imageVerification_sizeMatchesAndCodable() throws {
        let match = ImageVerification(byteCount: 1000, expectedByteCount: 1000, sha256Hex: "abc")
        XCTAssertTrue(match.sizeMatches)
        let mismatch = ImageVerification(byteCount: 999, expectedByteCount: 1000, sha256Hex: nil)
        XCTAssertFalse(mismatch.sizeMatches)

        let data = try JSONEncoder().encode(match)
        let decoded = try JSONDecoder().decode(ImageVerification.self, from: data)
        XCTAssertEqual(decoded, match)
    }

    // =========================================================================
    // MARK: - 9. DiscImageFormat.ccd / supportsRawAudioImaging
    // =========================================================================

    func test_discImageFormat_ccdDeclaredAndRefused() {
        XCTAssertEqual(DiscImageFormat.ccd.rawValue, "ccd")
        XCTAssertEqual(DiscImageFormat.ccd.displayName, "CloneCD (CCD/IMG/SUB)")
        // Every case must make a deliberate choice; only .bin supports raw
        // Audio CD imaging today.
        for format in DiscImageFormat.allCases {
            XCTAssertEqual(format.supportsRawAudioImaging, format == .bin,
                           "\(format.rawValue) supportsRawAudioImaging mismatch")
        }
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    private func indexSector(_ toc: DiscTableOfContents, track: Int, index: Int) -> Int? {
        toc.indexes.first { $0.trackNumber == track && $0.indexNumber == index }?.sector
    }

    private func assertMalformedToc(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard case ImagingError.malformedCdrdaoToc = error else {
            return XCTFail("Expected malformedCdrdaoToc, got \(error)", file: file, line: line)
        }
    }

    private func assertToolNotFound(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard case ToolLocatorError.toolNotFound = error else {
            return XCTFail("Expected toolNotFound, got \(error)", file: file, line: line)
        }
    }

    private func makeTempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meedya-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func uniqueToolName() -> String {
        "cdrdao-test-\(UUID().uuidString.prefix(8))"
    }
}
