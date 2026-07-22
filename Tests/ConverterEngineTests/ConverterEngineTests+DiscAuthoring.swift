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
    // MARK: - Phase 9: Disc Authoring
    // =========================================================================

    /// Verifies DiscAuthorFormat properties.
    func test_discAuthorFormat_properties() {
        XCTAssertEqual(DiscAuthorFormat.dvdVideo.displayName, "DVD-Video")
        XCTAssertEqual(DiscAuthorFormat.audioCd.displayName, "Audio CD")
        XCTAssertTrue(DiscAuthorFormat.dvdVideo.defaultCapacityBytes > 4_000_000_000)
    }

    /// Verifies DiscCapacity values.
    func test_discCapacity_values() {
        XCTAssertTrue(DiscCapacity.dvd5.capacityBytes > 4_700_000_000)
        XCTAssertTrue(DiscCapacity.dvd9.capacityBytes > 8_500_000_000)
        XCTAssertTrue(DiscCapacity.bd25.capacityBytes > 25_000_000_000)
        XCTAssertTrue(DiscCapacity.bd50.capacityBytes > 50_000_000_000)
    }

    /// Verifies dvdauthor arguments.
    func test_discAuthor_dvdAuthorArguments() {
        let args = DiscAuthor.buildDVDAuthorArguments(
            xmlConfigPath: "/tmp/dvdauthor.xml",
            outputDir: "/tmp/dvd_out"
        )
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains("/tmp/dvd_out"))
        XCTAssertTrue(args.contains("-x"))
        XCTAssertTrue(args.contains("/tmp/dvdauthor.xml"))
    }

    /// Verifies dvdauthor XML generation.
    func test_discAuthor_dvdAuthorXML() {
        let config = AuthoringConfig(
            format: .dvdVideo,
            volumeLabel: "MY_DVD",
            outputDirectory: "/tmp/dvd_out",
            videoStandard: .ntsc
        )
        let xml = DiscAuthor.generateDVDAuthorXML(
            config: config,
            vobFiles: ["/tmp/title1.mpg", "/tmp/title2.mpg"]
        )
        XCTAssertTrue(xml.contains("<dvdauthor"))
        XCTAssertTrue(xml.contains("ntsc"))
        XCTAssertTrue(xml.contains("title1.mpg"))
        XCTAssertTrue(xml.contains("title2.mpg"))
    }

    /// Verifies DVD encode arguments.
    func test_discAuthor_dvdEncodeArguments() {
        let args = DiscAuthor.buildDVDEncodeArguments(
            inputPath: "/tmp/movie.mp4",
            outputPath: "/tmp/movie.mpg",
            standard: .pal,
            bitrate: 8000
        )
        XCTAssertTrue(args.contains("mpeg2video"))
        XCTAssertTrue(args.contains("8000k"))
        XCTAssertTrue(args.contains(where: { $0.contains("720:576") }))
        XCTAssertTrue(args.contains("ac3"))
        XCTAssertTrue(args.contains("dvd"))
    }

    /// Verifies Audio CD preparation arguments.
    func test_discAuthor_audioCDPrepare() {
        let args = DiscAuthor.buildAudioCDPrepareArguments(
            inputPath: "/tmp/song.mp3",
            outputPath: "/tmp/song.wav"
        )
        XCTAssertTrue(args.contains("pcm_s16le"))
        XCTAssertTrue(args.contains("44100"))
        XCTAssertTrue(args.contains("2"))
    }

    /// Verifies tsMuxeR meta file generation.
    func test_discAuthor_tsMuxeRMeta() {
        let meta = DiscAuthor.generateTsMuxeRMeta(
            videoPath: "/tmp/video.264",
            audioPaths: ["/tmp/audio.ac3", "/tmp/audio.dts"],
            subtitlePaths: ["/tmp/subs.sup"],
            outputDir: "/tmp/bdmv"
        )
        XCTAssertTrue(meta.contains("MUXOPT"))
        XCTAssertTrue(meta.contains("V_MPEG4"))
        XCTAssertTrue(meta.contains("A_AC3"))
        XCTAssertTrue(meta.contains("A_DTS"))
        XCTAssertTrue(meta.contains("S_HDMV/PGS"))
    }

    /// Verifies genisoimage arguments.
    func test_discAuthor_genisoimageArguments() {
        let config = AuthoringConfig(
            format: .dvdVideo,
            volumeLabel: "TEST_DVD"
        )
        let args = DiscAuthor.buildGenisoimageArguments(
            config: config,
            sourceDir: "/tmp/dvd_struct",
            outputPath: "/tmp/movie.iso"
        )
        XCTAssertTrue(args.contains("-V"))
        XCTAssertTrue(args.contains("TEST_DVD"))
        XCTAssertTrue(args.contains("-dvd-video"))
        XCTAssertTrue(args.contains("-udf"))
        XCTAssertTrue(args.contains("-o"))
    }

    /// Verifies capacity validation.
    func test_discAuthor_capacityValidation() {
        // Fits on DVD-5
        let fitResult = DiscAuthor.validateCapacity(
            totalSizeBytes: 3_000_000_000,
            capacity: .dvd5
        )
        XCTAssertTrue(fitResult.fits)
        XCTAssertTrue(fitResult.remainingBytes > 0)
        XCTAssertTrue(fitResult.usedPercent < 100)

        // Doesn't fit on DVD-5
        let overResult = DiscAuthor.validateCapacity(
            totalSizeBytes: 6_000_000_000,
            capacity: .dvd5
        )
        XCTAssertFalse(overResult.fits)
        XCTAssertTrue(overResult.remainingBytes < 0)
        XCTAssertTrue(overResult.usedPercent > 100)
    }

    /// Verifies capacity validation summary.
    func test_capacityValidation_summary() {
        let fit = DiscAuthor.validateCapacity(
            totalSizeBytes: 2_000_000_000,
            capacity: .dvd5
        )
        XCTAssertTrue(fit.summary.contains("fits"))

        let over = DiscAuthor.validateCapacity(
            totalSizeBytes: 6_000_000_000,
            capacity: .dvd5
        )
        XCTAssertTrue(over.summary.contains("exceeds"))
    }

    // =========================================================================
    // MARK: - Phase 9: Disc Burner
    // =========================================================================

    /// Verifies audio CD burn arguments.
    func test_discBurner_audioCDBurn() {
        let config = BurnConfig(
            devicePath: "/dev/sr0",
            sourcePath: "",
            speed: .multiplier(8),
            ejectAfterBurn: true,
            format: .audioCd
        )
        let args = DiscBurner.buildAudioCDBurnArguments(
            config: config,
            wavFiles: ["/tmp/track01.wav", "/tmp/track02.wav"]
        )
        XCTAssertTrue(args.contains("dev=/dev/sr0"))
        XCTAssertTrue(args.contains("speed=8"))
        XCTAssertTrue(args.contains("-audio"))
        XCTAssertTrue(args.contains("-dao"))
        XCTAssertTrue(args.contains("-eject"))
        XCTAssertTrue(args.contains("/tmp/track01.wav"))
        XCTAssertTrue(args.contains("/tmp/track02.wav"))
    }

    /// Verifies data disc burn arguments.
    func test_discBurner_dataDiscBurn() {
        let config = BurnConfig(
            devicePath: "/dev/sr0",
            sourcePath: "/tmp/movie.iso",
            simulate: true
        )
        let args = DiscBurner.buildDataDiscBurnArguments(config: config)
        XCTAssertTrue(args.contains("dev=/dev/sr0"))
        XCTAssertTrue(args.contains("-dummy"))
        XCTAssertTrue(args.contains("/tmp/movie.iso"))
    }

    /// Verifies disc blanking arguments.
    func test_discBurner_blankArguments() {
        let args = DiscBurner.buildBlankArguments(
            devicePath: "/dev/sr0",
            blankType: "fast"
        )
        XCTAssertTrue(args.contains("dev=/dev/sr0"))
        XCTAssertTrue(args.contains("blank=fast"))
    }

    /// Verifies growisofs arguments.
    func test_discBurner_growisofsArguments() {
        let config = BurnConfig(
            devicePath: "/dev/sr0",
            sourcePath: "/tmp/movie.iso",
            speed: .multiplier(4),
            format: .dvdVideo
        )
        let args = DiscBurner.buildGrowisofsArguments(config: config)
        XCTAssertTrue(args.contains("-speed=4"))
        XCTAssertTrue(args.contains("-dvd-compat"))
        XCTAssertTrue(args.contains("-Z"))
        XCTAssertTrue(args.contains(where: { $0.contains("/dev/sr0") && $0.contains("/tmp/movie.iso") }))
    }

    /// Verifies hdiutil burn arguments.
    func test_discBurner_hdiutilBurn() {
        let args = DiscBurner.buildHdiutilBurnArguments(
            isoPath: "/tmp/movie.iso",
            verify: true
        )
        XCTAssertTrue(args.contains("burn"))
        XCTAssertTrue(args.contains("/tmp/movie.iso"))
        XCTAssertTrue(args.contains("-verifyburn"))
    }

    /// Verifies burn configuration validation.
    func test_discBurner_validation() {
        let emptyConfig = BurnConfig(devicePath: "", sourcePath: "")
        let errors = DiscBurner.validate(config: emptyConfig)
        XCTAssertEqual(errors.count, 2)

        let validConfig = BurnConfig(
            devicePath: "/dev/sr0",
            sourcePath: "/tmp/disc.iso"
        )
        let noErrors = DiscBurner.validate(config: validConfig)
        XCTAssertTrue(noErrors.isEmpty)
    }

    /// Verifies BurnSpeed cdrecord values.
    func test_burnSpeed_cdrecordValue() {
        XCTAssertEqual(BurnSpeed.auto.cdrecordValue, "0")
        XCTAssertEqual(BurnSpeed.multiplier(16).cdrecordValue, "16")
        XCTAssertEqual(BurnSpeed.maximum.cdrecordValue, "99")
    }

    /// Verifies BurnPhase display names.
    func test_burnPhase_displayNames() {
        XCTAssertEqual(BurnPhase.writing.displayName, "Writing data")
        XCTAssertEqual(BurnPhase.verifying.displayName, "Verifying burn")
        XCTAssertEqual(BurnPhase.fixating.displayName, "Fixating disc")
    }

    /// Verifies BurnProgress calculations.
    func test_burnProgress_fraction() {
        let progress = BurnProgress(
            phase: .writing,
            bytesWritten: 2_000_000_000,
            totalBytes: 4_000_000_000
        )
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.percentage, 50)
    }

    /// Verifies eject arguments.
    func test_discBurner_ejectArguments() {
        let args = DiscBurner.buildEjectArguments(devicePath: "/dev/sr0")
        XCTAssertEqual(args, ["/dev/sr0"])
    }

    /// Verifies DVDVideoStandard properties.
    func test_dvdVideoStandard_properties() {
        XCTAssertEqual(DVDVideoStandard.ntsc.frameRate, 29.97)
        XCTAssertEqual(DVDVideoStandard.pal.frameRate, 25.0)

        let ntscRes = DVDVideoStandard.ntsc.resolution
        XCTAssertEqual(ntscRes.width, 720)
        XCTAssertEqual(ntscRes.height, 480)

        let palRes = DVDVideoStandard.pal.resolution
        XCTAssertEqual(palRes.width, 720)
        XCTAssertEqual(palRes.height, 576)
    }

    /// Verifies DiscImageFormat properties.
    func test_discImageFormat_properties() {
        XCTAssertEqual(DiscImageFormat.iso.displayName, "ISO 9660")
        XCTAssertEqual(DiscImageFormat.bin.displayName, "BIN/CUE")
        XCTAssertEqual(DiscImageFormat.iso.fileExtension, "iso")
    }

}
