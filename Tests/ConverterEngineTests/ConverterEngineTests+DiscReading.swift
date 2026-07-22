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
    // =========================================================================
    // MARK: - Phase 8: Disc Reading — DiscModels
    // =========================================================================

    /// Verifies DiscType enum properties.
    func test_discType_properties() {
        XCTAssertEqual(DiscType.audioCd.displayName, "Audio CD")
        XCTAssertTrue(DiscType.audioCd.hasAudio)
        XCTAssertFalse(DiscType.audioCd.hasVideo)

        XCTAssertEqual(DiscType.dvdVideo.displayName, "DVD-Video")
        XCTAssertTrue(DiscType.dvdVideo.hasVideo)
        XCTAssertFalse(DiscType.dvdVideo.hasAudio)

        XCTAssertEqual(DiscType.bluray.displayName, "Blu-ray")
        XCTAssertTrue(DiscType.bluray.hasVideo)

        XCTAssertEqual(DiscType.sacd.displayName, "Super Audio CD")
        XCTAssertTrue(DiscType.sacd.hasAudio)
    }

    /// Verifies disc capacity values.
    func test_discType_capacity() {
        XCTAssertEqual(DiscType.audioCd.maxCapacityBytes, 737_280_000)
        XCTAssertTrue(DiscType.dvdVideo.maxCapacityBytes > 8_000_000_000)
        XCTAssertTrue(DiscType.bluray.maxCapacityBytes > 50_000_000_000)
        XCTAssertTrue(DiscType.uhdBluray.maxCapacityBytes > 100_000_000_000 - 1)
    }

    /// Verifies DiscInfo initialization.
    func test_discInfo_init() {
        let info = DiscInfo(
            discType: .dvdVideo,
            label: "MY_MOVIE",
            titleCount: 5,
            totalDuration: 7200,
            isProtected: true,
            protectionType: "CSS",
            regionCode: 1
        )
        XCTAssertEqual(info.discType, .dvdVideo)
        XCTAssertEqual(info.label, "MY_MOVIE")
        XCTAssertEqual(info.titleCount, 5)
        XCTAssertTrue(info.isProtected)
        XCTAssertEqual(info.protectionType, "CSS")
    }

    /// Verifies DiscTrack constants.
    func test_discTrack_constants() {
        XCTAssertEqual(DiscTrack.sectorSize, 2352)
        XCTAssertEqual(DiscTrack.sectorsPerSecond, 75)
    }

    /// Verifies DiscTitle initialization.
    func test_discTitle_init() {
        let title = DiscTitle(
            number: 1,
            duration: 7200,
            chapterCount: 25,
            audioStreams: [
                DiscAudioStream(index: 0, language: "eng", codec: "AC-3", channels: 6),
            ],
            videoWidth: 720,
            videoHeight: 480,
            isMainFeature: true
        )
        XCTAssertEqual(title.number, 1)
        XCTAssertEqual(title.chapterCount, 25)
        XCTAssertTrue(title.isMainFeature)
        XCTAssertEqual(title.audioStreams.count, 1)
        XCTAssertEqual(title.audioStreams[0].channels, 6)
    }

    /// Verifies DriveCapability read/write checks.
    func test_driveCapability_canRead() {
        let drive = DriveCapability(
            devicePath: "/dev/sr0",
            canReadCD: true,
            canReadDVD: true,
            canReadBluray: true,
            canReadUHDBluray: false,
            canWriteCD: true,
            canWriteDVD: true
        )
        XCTAssertTrue(drive.canRead(.audioCd))
        XCTAssertTrue(drive.canRead(.dvdVideo))
        XCTAssertTrue(drive.canRead(.bluray))
        XCTAssertFalse(drive.canRead(.uhdBluray))
        XCTAssertTrue(drive.canWrite(.audioCd))
        XCTAssertTrue(drive.canWrite(.dvdVideo))
        XCTAssertFalse(drive.canWrite(.bluray))
        XCTAssertFalse(drive.canWrite(.uhdBluray))
    }

    /// Verifies DiscRipConfig defaults.
    func test_discRipConfig_defaults() {
        let config = DiscRipConfig(
            sourcePath: "/dev/sr0",
            outputDirectory: "/tmp/rip"
        )
        XCTAssertTrue(config.decryptIfNeeded)
        XCTAssertTrue(config.paranoiaMode)
        XCTAssertTrue(config.mainFeatureOnly)
        XCTAssertEqual(config.retryCount, 20)
    }

    /// Verifies RipProgress calculations.
    func test_ripProgress_fraction() {
        let progress = RipProgress(
            bytesRead: 500_000_000,
            totalBytes: 1_000_000_000
        )
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.percentage, 50)
    }

    // =========================================================================
    // MARK: - Phase 8: Audio CD Reader
    // =========================================================================

    /// Verifies cdparanoia single track rip arguments.
    func test_audioCDReader_ripTrackArguments() {
        let args = AudioCDReader.buildRipTrackArguments(
            devicePath: "/dev/sr0",
            trackNumber: 3,
            outputPath: "/tmp/track03.wav",
            paranoia: .full,
            readSpeed: 8
        )
        XCTAssertTrue(args.contains("-d"))
        XCTAssertTrue(args.contains("/dev/sr0"))
        XCTAssertTrue(args.contains("3"))
        XCTAssertTrue(args.contains("/tmp/track03.wav"))
        XCTAssertTrue(args.contains("-S"))
        XCTAssertTrue(args.contains("8"))
    }

    /// Verifies cdparanoia batch rip arguments.
    func test_audioCDReader_ripAllArguments() {
        let args = AudioCDReader.buildRipAllArguments(
            devicePath: "/dev/sr0",
            outputDir: "/tmp/rip"
        )
        XCTAssertTrue(args.contains("-B"))
        XCTAssertTrue(args.contains("-O"))
        XCTAssertTrue(args.contains("/tmp/rip"))
    }

    /// Verifies FFmpeg encoding arguments for FLAC.
    func test_audioCDReader_encodeFlac() {
        let args = AudioCDReader.buildEncodeArguments(
            inputPath: "/tmp/track01.wav",
            outputPath: "/tmp/track01.flac",
            format: .flac,
            metadata: ["title": "Test Track", "artist": "Test Artist"]
        )
        XCTAssertTrue(args.contains("flac"))
        XCTAssertTrue(args.contains("-compression_level"))
        XCTAssertTrue(args.contains("-metadata"))
    }

    /// Verifies FFmpeg encoding arguments for lossy MP3.
    func test_audioCDReader_encodeMp3() {
        let args = AudioCDReader.buildEncodeArguments(
            inputPath: "/tmp/track01.wav",
            outputPath: "/tmp/track01.mp3",
            format: .mp3,
            bitrate: 320
        )
        XCTAssertTrue(args.contains("libmp3lame"))
        XCTAssertTrue(args.contains("320k"))
    }

    /// Verifies CDDB disc ID calculation.
    func test_audioCDReader_cddbDiscId() {
        let tracks = [
            DiscTrack(number: 1, startSector: 0, sectorCount: 15000),
            DiscTrack(number: 2, startSector: 15000, sectorCount: 18000),
            DiscTrack(number: 3, startSector: 33000, sectorCount: 20000),
        ]
        let discId = AudioCDReader.calculateCDDBDiscId(
            tracks: tracks,
            leadOutSector: 53000
        )
        XCTAssertEqual(discId.count, 8) // 8-char hex string
        XCTAssertFalse(discId.isEmpty)
    }

    /// Verifies MusicBrainz TOC construction.
    func test_audioCDReader_musicBrainzTOC() {
        let toc = AudioCDReader.buildMusicBrainzTOC(
            firstTrack: 1,
            lastTrack: 10,
            leadOutOffset: 200000,
            trackOffsets: [150, 18000, 36000]
        )
        XCTAssertTrue(toc.contains("1+10+200000"))
        XCTAssertTrue(toc.contains("150"))
    }

    /// Verifies MusicBrainz lookup URL.
    func test_audioCDReader_musicBrainzURL() {
        let url = AudioCDReader.buildMusicBrainzLookupURL(toc: "1+10+200000+150")
        XCTAssertTrue(url.contains("musicbrainz.org"))
        XCTAssertTrue(url.contains("toc="))
    }

    /// Verifies AccurateRip disc ID calculation.
    func test_audioCDReader_accurateRipIds() {
        let offsets = [150, 18000, 36000]
        let (id1, id2) = AudioCDReader.calculateAccurateRipDiscIds(
            trackOffsets: offsets,
            leadOutOffset: 200000
        )
        XCTAssertTrue(id1 > 0)
        XCTAssertTrue(id2 > 0)
    }

    /// Verifies track duration calculation.
    func test_audioCDReader_trackDuration() {
        let duration = AudioCDReader.trackDuration(
            startSector: 0,
            nextStartSector: 33075 // 441 seconds at 75 sectors/sec
        )
        XCTAssertEqual(duration, 441.0, accuracy: 0.01)
    }

    /// Verifies output filename generation.
    func test_audioCDReader_outputFilename() {
        let name = AudioCDReader.buildOutputFilename(
            trackNumber: 3,
            title: "My Song",
            artist: "My Artist",
            format: .flac
        )
        XCTAssertEqual(name, "03 - My Artist - My Song.flac")

        let nameNoMeta = AudioCDReader.buildOutputFilename(
            trackNumber: 1,
            format: .wav
        )
        XCTAssertEqual(nameNoMeta, "01.wav")
    }

    /// Verifies CDDAFormat properties.
    func test_cddaFormat_properties() {
        XCTAssertTrue(CDDAFormat.flac.isLossless)
        XCTAssertTrue(CDDAFormat.wav.isLossless)
        XCTAssertFalse(CDDAFormat.mp3.isLossless)
        XCTAssertFalse(CDDAFormat.aacLC.isLossless)
        XCTAssertEqual(CDDAFormat.flac.fileExtension, "flac")
        XCTAssertEqual(CDDAFormat.alac.fileExtension, "m4a")
    }

    /// Verifies CDParanoiaMode flags.
    func test_paranoiaMode_flags() {
        XCTAssertEqual(CDParanoiaMode.disabled.paranoiaFlags, "--disable-paranoia")
        XCTAssertEqual(CDParanoiaMode.full.paranoiaFlags, "--never-skip=40")
    }

    // =========================================================================
    // MARK: - Phase 8: DVD Reader
    // =========================================================================

    /// Verifies FFmpeg DVD rip arguments.
    func test_dvdReader_ripArguments() {
        let args = DVDReader.buildRipArguments(
            devicePath: "/dev/sr0",
            titleNumber: 1,
            outputPath: "/tmp/movie.mkv"
        )
        XCTAssertTrue(args.contains("-dvd-device"))
        XCTAssertTrue(args.contains("/dev/sr0"))
        XCTAssertTrue(args.contains("dvd://1"))
        XCTAssertTrue(args.contains("copy"))
        XCTAssertTrue(args.contains("/tmp/movie.mkv"))
    }

    /// Verifies DVD rip with specific streams.
    func test_dvdReader_ripWithStreams() {
        let args = DVDReader.buildRipArguments(
            devicePath: "/dev/sr0",
            titleNumber: 1,
            outputPath: "/tmp/movie.mkv",
            audioStreams: [0, 1],
            subtitleStreams: [0]
        )
        XCTAssertTrue(args.contains("0:a:0"))
        XCTAssertTrue(args.contains("0:a:1"))
        XCTAssertTrue(args.contains("0:s:0"))
    }

    /// Verifies VOB concatenation arguments.
    func test_dvdReader_vobConcat() {
        let args = DVDReader.buildVOBConcatArguments(
            vobFiles: ["/mnt/dvd/VTS_01_1.VOB", "/mnt/dvd/VTS_01_2.VOB"],
            outputPath: "/tmp/title.vob"
        )
        XCTAssertTrue(args.contains("-i"))
        let concatArg = args.first { $0.hasPrefix("concat:") }
        XCTAssertNotNil(concatArg)
        XCTAssertTrue(concatArg?.contains("|") == true)
    }

    /// Verifies lsdvd arguments.
    func test_dvdReader_lsdvdArguments() {
        let args = DVDReader.buildLsdvdArguments(devicePath: "/dev/sr0")
        XCTAssertTrue(args.contains("-a"))
        XCTAssertTrue(args.contains("-s"))
        XCTAssertTrue(args.contains("-c"))
        XCTAssertTrue(args.contains("-Oj"))
    }

    /// Verifies dvdbackup arguments.
    func test_dvdReader_backupArguments() {
        let args = DVDReader.buildDVDBackupArguments(
            devicePath: "/dev/sr0",
            outputDir: "/tmp/dvd",
            titleNumber: 1
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains("-t"))
        XCTAssertTrue(args.contains("1"))

        let mirrorArgs = DVDReader.buildDVDBackupArguments(
            devicePath: "/dev/sr0",
            outputDir: "/tmp/dvd"
        )
        XCTAssertTrue(mirrorArgs.contains("-M"))
    }

    /// Verifies VOB filename generation.
    func test_dvdReader_expectedVOBFiles() {
        let files = DVDReader.expectedVOBFiles(titleSetNumber: 1, partCount: 3)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files[0], "VTS_01_1.VOB")
        XCTAssertEqual(files[1], "VTS_01_2.VOB")
        XCTAssertEqual(files[2], "VTS_01_3.VOB")
    }

    /// Verifies VIDEO_TS path construction.
    func test_dvdReader_videoTSPath() {
        let path = DVDReader.videoTSPath(from: "/mnt/dvd")
        XCTAssertTrue(path.hasSuffix("VIDEO_TS"))
    }

    /// Verifies IFO file path construction.
    func test_dvdReader_ifoFilePath() {
        let vmg = DVDReader.ifoFilePath(videoTSDir: "/mnt/dvd/VIDEO_TS", titleSetNumber: 0)
        XCTAssertTrue(vmg.hasSuffix("VIDEO_TS.IFO"))

        let vts = DVDReader.ifoFilePath(videoTSDir: "/mnt/dvd/VIDEO_TS", titleSetNumber: 1)
        XCTAssertTrue(vts.hasSuffix("VTS_01_0.IFO"))
    }

    /// Verifies DVD region check.
    func test_dvdReader_regionCheck() {
        // Region 1 disc: bit 0 = 0 (allowed), bits 1-7 = 1 (blocked)
        let regionMask: UInt8 = 0xFE
        XCTAssertTrue(DVDReader.isRegionAllowed(regionMask: regionMask, region: 1))
        XCTAssertFalse(DVDReader.isRegionAllowed(regionMask: regionMask, region: 2))

        // Region-free: all bits 0
        XCTAssertTrue(DVDReader.isRegionAllowed(regionMask: 0x00, region: 1))
        XCTAssertTrue(DVDReader.isRegionAllowed(regionMask: 0x00, region: 4))
    }

    /// Verifies DVD structure properties.
    func test_dvdStructure_regions() {
        let structure = DVDStructure(regionMask: 0xFE) // Region 1 only
        XCTAssertEqual(structure.regions, [1])

        let regionFree = DVDStructure(regionMask: 0x00)
        XCTAssertEqual(regionFree.regions.count, 8)
    }

    /// Verifies main feature detection.
    func test_dvdReader_mainFeatureDetection() {
        let titles = [
            DiscTitle(number: 1, duration: 120),    // 2 min (menu)
            DiscTitle(number: 2, duration: 7200),   // 2 hours (main)
            DiscTitle(number: 3, duration: 600),    // 10 min (extras)
        ]
        let main = DVDReader.detectMainFeature(titles: titles)
        XCTAssertEqual(main?.number, 2)
    }

    // =========================================================================
    // MARK: - Phase 8: Blu-ray Reader
    // =========================================================================

    /// Verifies FFmpeg Blu-ray rip arguments.
    func test_blurayReader_ripArguments() {
        let args = BlurayReader.buildRipArguments(
            devicePath: "/dev/sr0",
            playlistNumber: 800,
            outputPath: "/tmp/movie.mkv"
        )
        XCTAssertTrue(args.contains("-playlist"))
        XCTAssertTrue(args.contains("800"))
        XCTAssertTrue(args.contains("bluray:/dev/sr0"))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies Blu-ray rip with stream selection.
    func test_blurayReader_ripWithStreams() {
        let args = BlurayReader.buildRipArguments(
            devicePath: "/dev/sr0",
            playlistNumber: 800,
            outputPath: "/tmp/movie.mkv",
            audioStreams: [0, 2],
            subtitleStreams: [0]
        )
        XCTAssertTrue(args.contains("0:a:0"))
        XCTAssertTrue(args.contains("0:a:2"))
        XCTAssertTrue(args.contains("0:s:0"))
    }

    /// Verifies M2TS rip arguments.
    func test_blurayReader_m2tsRip() {
        let args = BlurayReader.buildM2TSRipArguments(
            m2tsPath: "/mnt/bd/BDMV/STREAM/00001.m2ts",
            outputPath: "/tmp/clip.mkv"
        )
        XCTAssertTrue(args.contains(where: { $0.contains("00001.m2ts") }))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies BDMV path construction.
    func test_blurayReader_bdmvPaths() {
        let paths = BlurayReader.bdmvPaths(from: "/mnt/bd")
        XCTAssertTrue(paths["stream"]?.contains("STREAM") == true)
        XCTAssertTrue(paths["playlist"]?.contains("PLAYLIST") == true)
        XCTAssertTrue(paths["clipinf"]?.contains("CLIPINF") == true)
    }

    /// Verifies MPLS file path construction.
    func test_blurayReader_mplsFilePath() {
        let path = BlurayReader.mplsFilePath(basePath: "/mnt/bd", playlistNumber: 800)
        XCTAssertTrue(path.hasSuffix("00800.mpls"))
        XCTAssertTrue(path.contains("PLAYLIST"))
    }

    /// Verifies M2TS file path construction.
    func test_blurayReader_m2tsFilePath() {
        let path = BlurayReader.m2tsFilePath(basePath: "/mnt/bd", clipNumber: 1)
        XCTAssertTrue(path.hasSuffix("00001.m2ts"))
        XCTAssertTrue(path.contains("STREAM"))
    }

    /// Verifies main feature detection for Blu-ray.
    func test_blurayReader_mainFeatureDetection() {
        let playlists = [
            BlurayPlaylist(number: 1, duration: 30),       // Menu
            BlurayPlaylist(number: 800, duration: 7800),   // Main feature
            BlurayPlaylist(number: 801, duration: 900),    // Extra
        ]
        let main = BlurayReader.detectMainFeature(playlists: playlists)
        XCTAssertEqual(main?.number, 800)
    }

    /// Verifies HDR10 preservation arguments.
    func test_blurayReader_hdr10Arguments() {
        let args = BlurayReader.buildHDR10PreservationArguments()
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("smpte2084"))
    }

    /// Verifies BlurayVideoStream UHD detection.
    func test_blurayVideoStream_isUHD() {
        let uhd = BlurayVideoStream(width: 3840, height: 2160)
        XCTAssertTrue(uhd.isUHD)

        let hd = BlurayVideoStream(width: 1920, height: 1080)
        XCTAssertFalse(hd.isUHD)
    }

    /// Verifies BlurayProtection canDecrypt logic.
    func test_blurayProtection_canDecrypt() {
        let withKeys = BlurayProtection(hasAACS: true, hasKeyFile: true)
        XCTAssertTrue(withKeys.canDecrypt)

        let noKeys = BlurayProtection(hasAACS: true, hasKeyFile: false)
        XCTAssertFalse(noKeys.canDecrypt)

        let aacs2 = BlurayProtection(hasAACS2: true, hasKeyFile: true)
        XCTAssertFalse(aacs2.canDecrypt)

        let noProtection = BlurayProtection()
        XCTAssertTrue(noProtection.canDecrypt)
    }

    /// Verifies UHD and HDR detection helpers.
    func test_blurayReader_uhdAndHdrDetection() {
        let streams = [
            BlurayVideoStream(width: 3840, height: 2160, isHDR: true, hdrFormat: "HDR10"),
        ]
        XCTAssertTrue(BlurayReader.isUHDDisc(videoStreams: streams))
        XCTAssertTrue(BlurayReader.hasHDRContent(videoStreams: streams))

        let sdStreams = [BlurayVideoStream(width: 1920, height: 1080)]
        XCTAssertFalse(BlurayReader.isUHDDisc(videoStreams: sdStreams))
        XCTAssertFalse(BlurayReader.hasHDRContent(videoStreams: sdStreams))
    }

}
