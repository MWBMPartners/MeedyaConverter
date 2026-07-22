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
    // MARK: - PQToHLGPipeline Tests

    /// Verifies PQToHLGMethod display names.
    func test_pqToHLGMethod_displayNames() {
        XCTAssertEqual(PQToHLGMethod.hlgTools.displayName, "hlg-tools (High Quality)")
        XCTAssertEqual(PQToHLGMethod.ffmpegZscale.displayName, "FFmpeg zscale (Built-in)")
        XCTAssertEqual(PQToHLGMethod.auto.displayName, "Auto (Best Available)")
    }

    /// Verifies PQToHLGMethod raw values.
    func test_pqToHLGMethod_rawValues() {
        XCTAssertEqual(PQToHLGMethod.hlgTools.rawValue, "hlg_tools")
        XCTAssertEqual(PQToHLGMethod.ffmpegZscale.rawValue, "ffmpeg_zscale")
        XCTAssertEqual(PQToHLGMethod.auto.rawValue, "auto")
    }

    /// Verifies PQToHLGConfig default initializer values.
    func test_pqToHLGConfig_defaults() {
        let config = PQToHLGConfig()
        XCTAssertEqual(config.method, .auto)
        XCTAssertNil(config.maxCLL)
        XCTAssertNil(config.maxFALL)
        XCTAssertFalse(config.generateDolbyVision)
        XCTAssertEqual(config.encoder, "libx265")
        XCTAssertEqual(config.crf, 18)
        XCTAssertEqual(config.preset, "medium")
        XCTAssertTrue(config.passthroughOtherStreams)
    }

    /// Verifies the zscale PQ→HLG filter string.
    func test_pqToHLGPipeline_buildPQToHLGFilter_containsZscaleSteps() {
        let filter = PQToHLGPipeline.buildPQToHLGFilter()
        XCTAssertTrue(filter.contains("zscale=t=linear:npl=1000"))
        XCTAssertTrue(filter.contains("format=gbrpf32le"))
        XCTAssertTrue(filter.contains("zscale=t=arib-std-b67"))
        XCTAssertTrue(filter.contains("format=yuv420p10le"))
    }

    /// Verifies zscale argument building includes input, filter, encoder, and HLG metadata.
    func test_pqToHLGPipeline_buildZscaleArguments_containsHLGMetadata() {
        let args = PQToHLGPipeline.buildZscaleArguments(
            inputPath: "/input.mkv",
            outputPath: "/output.mkv"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/input.mkv"))
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("-c:v"))
        XCTAssertTrue(args.contains("libx265"))
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("arib-std-b67"))
        XCTAssertTrue(args.contains("-color_primaries"))
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("-pix_fmt"))
        XCTAssertTrue(args.contains("yuv420p10le"))
        XCTAssertTrue(args.contains("/output.mkv"))
    }

    /// Verifies zscale arguments include CLL when provided.
    func test_pqToHLGPipeline_buildZscaleArguments_includesCLL() {
        let config = PQToHLGConfig(maxCLL: 1000, maxFALL: 400)
        let args = PQToHLGPipeline.buildZscaleArguments(
            inputPath: "/in.mkv",
            outputPath: "/out.mkv",
            config: config
        )
        XCTAssertTrue(args.contains("-max_cll"))
        XCTAssertTrue(args.contains("1000,400"))
    }

    /// Verifies zscale arguments include audio/subtitle passthrough by default.
    func test_pqToHLGPipeline_buildZscaleArguments_passthroughStreams() {
        let args = PQToHLGPipeline.buildZscaleArguments(
            inputPath: "/in.mkv",
            outputPath: "/out.mkv"
        )
        XCTAssertTrue(args.contains("-c:a"))
        XCTAssertTrue(args.contains("-c:s"))
    }

    /// Verifies zscale arguments omit passthrough when disabled.
    func test_pqToHLGPipeline_buildZscaleArguments_noPassthroughWhenDisabled() {
        let config = PQToHLGConfig(passthroughOtherStreams: false)
        let args = PQToHLGPipeline.buildZscaleArguments(
            inputPath: "/in.mkv",
            outputPath: "/out.mkv",
            config: config
        )
        XCTAssertFalse(args.contains("-c:a"))
        XCTAssertFalse(args.contains("-c:s"))
    }

    /// Verifies decode-to-Y4M arguments for hlg-tools pipeline.
    func test_pqToHLGPipeline_buildDecodeToY4MArguments_containsY4MPipe() {
        let args = PQToHLGPipeline.buildDecodeToY4MArguments(
            inputPath: "/src.mkv",
            y4mOutputPath: "/tmp/video.y4m"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/src.mkv"))
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("yuv4mpegpipe"))
        XCTAssertTrue(args.contains("/tmp/video.y4m"))
        XCTAssertTrue(args.contains("yuv420p10le"))
    }

    /// Verifies pq2hlg argument building with and without maxCLL.
    func test_pqToHLGPipeline_buildPQ2HLGArguments_withAndWithoutCLL() {
        let argsNoCLL = PQToHLGPipeline.buildPQ2HLGArguments(
            y4mInputPath: "/tmp/in.y4m",
            y4mOutputPath: "/tmp/out.y4m"
        )
        XCTAssertTrue(argsNoCLL.contains("-i"))
        XCTAssertTrue(argsNoCLL.contains("-o"))
        XCTAssertFalse(argsNoCLL.contains("--max-cll"))

        let argsWithCLL = PQToHLGPipeline.buildPQ2HLGArguments(
            y4mInputPath: "/tmp/in.y4m",
            y4mOutputPath: "/tmp/out.y4m",
            maxCLL: 1000
        )
        XCTAssertTrue(argsWithCLL.contains("--max-cll"))
        XCTAssertTrue(argsWithCLL.contains("1000"))
    }

    /// Verifies encode-from-Y4M arguments include both inputs and HLG metadata.
    func test_pqToHLGPipeline_buildEncodeFromY4MArguments_dualInput() {
        let args = PQToHLGPipeline.buildEncodeFromY4MArguments(
            y4mInputPath: "/tmp/hlg.y4m",
            originalInputPath: "/src.mkv",
            outputPath: "/out.mkv"
        )
        // Two -i inputs
        let iIndices = args.enumerated().filter { $0.element == "-i" }.map { $0.offset }
        XCTAssertEqual(iIndices.count, 2)
        XCTAssertTrue(args.contains("/tmp/hlg.y4m"))
        XCTAssertTrue(args.contains("/src.mkv"))
        // Stream mapping
        XCTAssertTrue(args.contains("0:v"))
        XCTAssertTrue(args.contains("1:a?"))
        XCTAssertTrue(args.contains("1:s?"))
        // HLG metadata
        XCTAssertTrue(args.contains("arib-std-b67"))
        XCTAssertTrue(args.contains("bt2020"))
    }

    /// Verifies DV Profile 8.4 RPU generation arguments.
    func test_pqToHLGPipeline_buildGenerateProfile84RPUArguments_containsMode4() {
        let args = PQToHLGPipeline.buildGenerateProfile84RPUArguments(
            outputRPUPath: "/tmp/rpu.bin",
            maxCLL: 1000,
            maxFALL: 400,
            maxLuminance: 4000,
            minLuminance: 50
        )
        XCTAssertTrue(args.contains("generate"))
        XCTAssertTrue(args.contains("-m"))
        XCTAssertTrue(args.contains("4"))
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains("/tmp/rpu.bin"))
        XCTAssertTrue(args.contains("--max-lum"))
        XCTAssertTrue(args.contains("4000"))
        XCTAssertTrue(args.contains("--min-lum"))
        XCTAssertTrue(args.contains("50"))
        XCTAssertTrue(args.contains("--max-cll"))
        XCTAssertTrue(args.contains("1000"))
        XCTAssertTrue(args.contains("--max-fall"))
        XCTAssertTrue(args.contains("400"))
    }

    /// Verifies DV Profile 8.4 RPU generation with no optional params.
    func test_pqToHLGPipeline_buildGenerateProfile84RPUArguments_minimalArgs() {
        let args = PQToHLGPipeline.buildGenerateProfile84RPUArguments(
            outputRPUPath: "/tmp/rpu.bin"
        )
        XCTAssertEqual(args.count, 5) // generate -m 4 -o /path
        XCTAssertFalse(args.contains("--max-lum"))
        XCTAssertFalse(args.contains("--max-cll"))
    }

    /// Verifies RPU injection arguments.
    func test_pqToHLGPipeline_buildInjectRPUArguments_containsRPUIn() {
        let args = PQToHLGPipeline.buildInjectRPUArguments(
            hevcInputPath: "/tmp/video.hevc",
            rpuPath: "/tmp/rpu.bin",
            outputPath: "/tmp/dv.hevc"
        )
        XCTAssertTrue(args.contains("inject-rpu"))
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/video.hevc"))
        XCTAssertTrue(args.contains("--rpu-in"))
        XCTAssertTrue(args.contains("/tmp/rpu.bin"))
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains("/tmp/dv.hevc"))
    }

    /// Verifies HEVC extraction arguments include annexb bitstream filter.
    func test_pqToHLGPipeline_buildExtractHEVCArguments_containsAnnexB() {
        let args = PQToHLGPipeline.buildExtractHEVCArguments(
            inputPath: "/src.mkv",
            outputPath: "/tmp/video.hevc"
        )
        XCTAssertTrue(args.contains("-bsf:v"))
        XCTAssertTrue(args.contains("hevc_mp4toannexb"))
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("hevc"))
        XCTAssertTrue(args.contains("0:v:0"))
    }

    /// Verifies DV+HLG mux arguments include strict unofficial.
    func test_pqToHLGPipeline_buildMuxDVHLGArguments_containsStrictUnofficial() {
        let args = PQToHLGPipeline.buildMuxDVHLGArguments(
            hevcPath: "/tmp/dv.hevc",
            originalPath: "/src.mkv",
            outputPath: "/final.mkv"
        )
        XCTAssertTrue(args.contains("-strict"))
        XCTAssertTrue(args.contains("unofficial"))
        XCTAssertTrue(args.contains("0:v"))
        XCTAssertTrue(args.contains("1:a?"))
        XCTAssertTrue(args.contains("1:s?"))
    }

    /// Verifies pipeline description for hlg-tools method.
    func test_pqToHLGPipeline_describePipeline_hlgToolsMethod() {
        let config = PQToHLGConfig(method: .hlgTools)
        let steps = PQToHLGPipeline.describePipeline(config: config)
        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps[0].contains("Y4M"))
        XCTAssertTrue(steps[1].contains("pq2hlg"))
        XCTAssertTrue(steps[2].contains("Encode"))
    }

    /// Verifies pipeline description for zscale method.
    func test_pqToHLGPipeline_describePipeline_zscaleMethod() {
        let config = PQToHLGConfig(method: .ffmpegZscale)
        let steps = PQToHLGPipeline.describePipeline(config: config)
        XCTAssertEqual(steps.count, 2)
        XCTAssertTrue(steps[0].contains("zscale"))
    }

    /// Verifies pipeline description includes DV steps when enabled.
    func test_pqToHLGPipeline_describePipeline_withDolbyVision() {
        let config = PQToHLGConfig(method: .ffmpegZscale, generateDolbyVision: true)
        let steps = PQToHLGPipeline.describePipeline(config: config)
        XCTAssertTrue(steps.count > 2)
        let dvSteps = steps.filter { $0.contains("Dolby Vision") || $0.contains("RPU") || $0.contains("HEVC") || $0.contains("Mux") || $0.contains("Inject") }
        XCTAssertTrue(dvSteps.count >= 3)
    }

    /// Verifies PQToHLGConfig Codable round-trip.
    func test_pqToHLGConfig_codableRoundTrip() throws {
        let config = PQToHLGConfig(
            method: .hlgTools,
            maxCLL: 1000,
            maxFALL: 400,
            generateDolbyVision: true,
            encoder: "libx265",
            crf: 20,
            preset: "slow",
            passthroughOtherStreams: false
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PQToHLGConfig.self, from: data)
        XCTAssertEqual(decoded.method, .hlgTools)
        XCTAssertEqual(decoded.maxCLL, 1000)
        XCTAssertEqual(decoded.maxFALL, 400)
        XCTAssertTrue(decoded.generateDolbyVision)
        XCTAssertEqual(decoded.crf, 20)
        XCTAssertEqual(decoded.preset, "slow")
        XCTAssertFalse(decoded.passthroughOtherStreams)
    }

    // MARK: - VVCEncoder Tests

    /// Verifies VVCPreset display names and raw values.
    func test_vvcPreset_displayNamesAndRawValues() {
        XCTAssertEqual(VVCPreset.faster.rawValue, "faster")
        XCTAssertEqual(VVCPreset.medium.rawValue, "medium")
        XCTAssertEqual(VVCPreset.slower.rawValue, "slower")
        XCTAssertTrue(VVCPreset.medium.displayName.contains("Default"))
    }

    /// Verifies VVCConfig default values.
    func test_vvcConfig_defaults() {
        let config = VVCConfig()
        XCTAssertEqual(config.qp, 28)
        XCTAssertEqual(config.preset, .medium)
        XCTAssertNil(config.bitrate)
        XCTAssertEqual(config.tier, .main)
        XCTAssertEqual(config.threads, 0)
        XCTAssertFalse(config.hdr10)
        XCTAssertEqual(config.bitDepth, 10)
        XCTAssertFalse(config.intraRefresh)
        XCTAssertTrue(config.outputMP4)
    }

    /// Verifies VVC encode arguments include libvvenc and QP.
    func test_vvcEncoder_buildEncodeArguments_defaultConfig() {
        let args = VVCEncoder.buildEncodeArguments(
            inputPath: "/input.mkv",
            outputPath: "/output.mp4"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/input.mkv"))
        XCTAssertTrue(args.contains("-c:v"))
        XCTAssertTrue(args.contains("libvvenc"))
        XCTAssertTrue(args.contains("-qp"))
        XCTAssertTrue(args.contains("28"))
        XCTAssertTrue(args.contains("-preset"))
        XCTAssertTrue(args.contains("medium"))
        XCTAssertTrue(args.contains("-pix_fmt"))
        XCTAssertTrue(args.contains("yuv420p10le"))
        XCTAssertTrue(args.contains("-strict"))
        XCTAssertTrue(args.contains("unofficial"))
    }

    /// Verifies VVC encode with bitrate uses -b:v instead of -qp.
    func test_vvcEncoder_buildEncodeArguments_withBitrate() {
        let config = VVCConfig(bitrate: 5000)
        let args = VVCEncoder.buildEncodeArguments(
            inputPath: "/in.mkv",
            outputPath: "/out.mkv",
            config: config
        )
        XCTAssertTrue(args.contains("-b:v"))
        XCTAssertTrue(args.contains("5000k"))
        XCTAssertFalse(args.contains("-qp"))
    }

    /// Verifies VVC encode with HDR10 includes colour metadata.
    func test_vvcEncoder_buildEncodeArguments_withHDR10() {
        let config = VVCConfig(hdr10: true)
        let args = VVCEncoder.buildEncodeArguments(
            inputPath: "/in.mkv",
            outputPath: "/out.mkv",
            config: config
        )
        XCTAssertTrue(args.contains("-color_primaries"))
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("smpte2084"))
    }

    /// Verifies VVC encode with 8-bit uses yuv420p.
    func test_vvcEncoder_buildEncodeArguments_8bit() {
        let config = VVCConfig(bitDepth: 8)
        let args = VVCEncoder.buildEncodeArguments(
            inputPath: "/in.mkv",
            outputPath: "/out.mkv",
            config: config
        )
        XCTAssertTrue(args.contains("yuv420p"))
        XCTAssertFalse(args.contains("yuv420p10le"))
    }

    /// Verifies VVC MKV output does not add -strict unofficial.
    func test_vvcEncoder_buildEncodeArguments_mkvNoStrict() {
        let config = VVCConfig(outputMP4: false)
        let args = VVCEncoder.buildEncodeArguments(
            inputPath: "/in.mkv",
            outputPath: "/out.mkv",
            config: config
        )
        XCTAssertFalse(args.contains("-strict"))
    }

    /// Verifies vvencapp argument building.
    func test_vvcEncoder_buildVvencAppArguments_containsResolution() {
        let args = VVCEncoder.buildVvencAppArguments(
            inputPath: "-",
            outputPath: "/out.vvc",
            width: 3840,
            height: 2160,
            frameRate: 24.0
        )
        XCTAssertTrue(args.contains("-s"))
        XCTAssertTrue(args.contains("3840x2160"))
        XCTAssertTrue(args.contains("-r"))
        XCTAssertTrue(args.contains("24"))
        XCTAssertTrue(args.contains("--internal-bitdepth"))
        XCTAssertTrue(args.contains("10"))
    }

    /// Verifies VVC container support info.
    func test_vvcEncoder_containerSupport_mp4RequiresStrict() {
        let mp4 = VVCEncoder.containerSupport(container: "mp4")
        XCTAssertTrue(mp4.supported)
        XCTAssertTrue(mp4.requiresStrict)

        let mkv = VVCEncoder.containerSupport(container: "mkv")
        XCTAssertTrue(mkv.supported)
        XCTAssertFalse(mkv.requiresStrict)

        let webm = VVCEncoder.containerSupport(container: "webm")
        XCTAssertFalse(webm.supported)
    }

    /// Verifies VVC supported containers list.
    func test_vvcEncoder_supportedContainers() {
        let containers = VVCEncoder.supportedContainers()
        XCTAssertTrue(containers.contains("mp4"))
        XCTAssertTrue(containers.contains("mkv"))
        XCTAssertTrue(containers.contains("ts"))
    }

    /// Verifies HEVC-equivalent CRF approximation.
    func test_vvcEncoder_approximateHEVCEquivalentCRF() {
        XCTAssertEqual(VVCEncoder.approximateHEVCEquivalentCRF(qp: 28), 32)
        XCTAssertEqual(VVCEncoder.approximateHEVCEquivalentCRF(qp: 20), 24)
        XCTAssertEqual(VVCEncoder.approximateHEVCEquivalentCRF(qp: 50), 51) // Clamped
    }

    /// Verifies VVC bitrate savings estimation.
    func test_vvcEncoder_estimatedBitrateSavings() {
        let savings = VVCEncoder.estimatedBitrateSavings(hevcBitrateKbps: 10000)
        XCTAssertEqual(savings.min, 5000)  // 50% saving
        XCTAssertEqual(savings.max, 7000)  // 30% saving
    }

    /// Verifies VVC pipeline description.
    func test_vvcEncoder_describePipeline_withHDR() {
        let config = VVCConfig(hdr10: true, outputMP4: true)
        let steps = VVCEncoder.describePipeline(config: config)
        XCTAssertTrue(steps.count >= 3)
        XCTAssertTrue(steps.contains { $0.contains("HDR10") })
        XCTAssertTrue(steps.contains { $0.contains("libvvenc") })
        XCTAssertTrue(steps.contains { $0.contains("MP4") })
    }

    // MARK: - HLGToDolbyVision Tests

    /// Verifies DVProfileTarget properties.
    func test_dvProfileTarget_properties() {
        XCTAssertEqual(DVProfileTarget.profile84.doviToolMode, "4")
        XCTAssertEqual(DVProfileTarget.profile5.doviToolMode, "0")
        XCTAssertTrue(DVProfileTarget.profile84.hlgCompatible)
        XCTAssertFalse(DVProfileTarget.profile5.hlgCompatible)
        XCTAssertEqual(DVProfileTarget.profile84.baseLayerTransfer, "arib-std-b67")
        XCTAssertEqual(DVProfileTarget.profile5.baseLayerTransfer, "smpte2084")
    }

    /// Verifies HLGToDVConfig defaults.
    func test_hlgToDVConfig_defaults() {
        let config = HLGToDVConfig()
        XCTAssertEqual(config.profile, .profile84)
        XCTAssertEqual(config.maxLuminance, 1000)
        XCTAssertEqual(config.minLuminance, 50)
        XCTAssertEqual(config.encoder, "libx265")
        XCTAssertEqual(config.crf, 18)
    }

    /// Verifies Profile 8.4 encode arguments preserve HLG metadata.
    func test_hlgToDV_buildProfile84EncodeArguments_preservesHLG() {
        let args = HLGToDolbyVision.buildProfile84EncodeArguments(
            inputPath: "/hlg.mkv",
            outputPath: "/out.mkv"
        )
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("arib-std-b67"))
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("yuv420p10le"))
    }

    /// Verifies Profile 5 encode arguments convert HLG→PQ.
    func test_hlgToDV_buildProfile5EncodeArguments_convertsToPQ() {
        let config = HLGToDVConfig(profile: .profile5)
        let args = HLGToDolbyVision.buildProfile5EncodeArguments(
            inputPath: "/hlg.mkv",
            outputPath: "/out.mkv",
            config: config
        )
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("smpte2084"))
    }

    /// Verifies HLG→PQ filter contains correct zscale stages.
    func test_hlgToDV_buildHLGToPQFilter_containsZscale() {
        let filter = HLGToDolbyVision.buildHLGToPQFilter()
        XCTAssertTrue(filter.contains("zscale=t=linear"))
        XCTAssertTrue(filter.contains("format=gbrpf32le"))
        XCTAssertTrue(filter.contains("zscale=t=smpte2084"))
        XCTAssertTrue(filter.contains("format=yuv420p10le"))
    }

    /// Verifies RPU generation arguments contain correct mode.
    func test_hlgToDV_buildGenerateRPUArguments_profile84() {
        let config = HLGToDVConfig(maxCLL: 800, maxFALL: 300)
        let args = HLGToDolbyVision.buildGenerateRPUArguments(
            outputRPUPath: "/tmp/rpu.bin",
            config: config
        )
        XCTAssertTrue(args.contains("generate"))
        XCTAssertTrue(args.contains("-m"))
        XCTAssertTrue(args.contains("4")) // Profile 8.4 mode
        XCTAssertTrue(args.contains("--max-cll"))
        XCTAssertTrue(args.contains("800"))
        XCTAssertTrue(args.contains("--max-fall"))
        XCTAssertTrue(args.contains("300"))
        XCTAssertTrue(args.contains("--max-lum"))
        XCTAssertTrue(args.contains("--min-lum"))
    }

    /// Verifies HEVC extraction arguments.
    func test_hlgToDV_buildExtractHEVCArguments_containsAnnexB() {
        let args = HLGToDolbyVision.buildExtractHEVCArguments(
            inputPath: "/src.mkv",
            outputPath: "/tmp/video.hevc"
        )
        XCTAssertTrue(args.contains("hevc_mp4toannexb"))
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("hevc"))
    }

    /// Verifies RPU injection arguments.
    func test_hlgToDV_buildInjectRPUArguments() {
        let args = HLGToDolbyVision.buildInjectRPUArguments(
            hevcInputPath: "/tmp/video.hevc",
            rpuPath: "/tmp/rpu.bin",
            outputPath: "/tmp/dv.hevc"
        )
        XCTAssertTrue(args.contains("inject-rpu"))
        XCTAssertTrue(args.contains("--rpu-in"))
    }

    /// Verifies mux arguments include strict unofficial.
    func test_hlgToDV_buildMuxArguments_containsStrictUnofficial() {
        let args = HLGToDolbyVision.buildMuxArguments(
            hevcPath: "/tmp/dv.hevc",
            originalPath: "/src.mkv",
            outputPath: "/final.mkv"
        )
        XCTAssertTrue(args.contains("-strict"))
        XCTAssertTrue(args.contains("unofficial"))
        XCTAssertTrue(args.contains("1:a?"))
        XCTAssertTrue(args.contains("1:s?"))
    }

    /// Verifies pipeline description step count per profile.
    func test_hlgToDV_describePipeline_stepCounts() {
        let p84 = HLGToDolbyVision.describePipeline(config: HLGToDVConfig(profile: .profile84))
        XCTAssertEqual(p84.count, 5)

        let p5 = HLGToDolbyVision.describePipeline(config: HLGToDVConfig(profile: .profile5))
        XCTAssertEqual(p5.count, 6)
    }

    /// Verifies encoder validation.
    func test_hlgToDV_validateEncoder_hevcValid() {
        XCTAssertTrue(HLGToDolbyVision.validateEncoder("libx265").isEmpty)
        XCTAssertTrue(HLGToDolbyVision.validateEncoder("hevc_videotoolbox").isEmpty)
        XCTAssertFalse(HLGToDolbyVision.validateEncoder("libx264").isEmpty)
        XCTAssertFalse(HLGToDolbyVision.validateEncoder("libsvtav1").isEmpty)
    }

    /// Verifies config validation.
    func test_hlgToDV_validateConfig_valid() {
        let config = HLGToDVConfig()
        XCTAssertTrue(HLGToDolbyVision.validateConfig(config).isEmpty)
    }

    /// Verifies config validation catches bad luminance.
    func test_hlgToDV_validateConfig_badLuminance() {
        let config = HLGToDVConfig(maxLuminance: 0)
        let warnings = HLGToDolbyVision.validateConfig(config)
        XCTAssertFalse(warnings.isEmpty)
    }

    // MARK: - SmartCropIntegration Tests

    /// Verifies CropMode properties.
    func test_cropMode_thresholds() {
        XCTAssertEqual(CropMode.auto.threshold, 24)
        XCTAssertEqual(CropMode.aggressive.threshold, 16)
        XCTAssertEqual(CropMode.conservative.threshold, 40)
        XCTAssertEqual(CropMode.none.threshold, 0)
    }

    /// Verifies letterbox detection — horizontal bars.
    func test_smartCrop_detectLetterboxType_letterbox() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        let type = SmartCropIntegration.detectLetterboxType(
            crop: crop, sourceWidth: 1920, sourceHeight: 1080
        )
        XCTAssertEqual(type, .letterbox)
    }

    /// Verifies pillarbox detection — vertical bars.
    func test_smartCrop_detectLetterboxType_pillarbox() {
        let crop = CropRect(width: 1440, height: 1080, x: 240, y: 0)
        let type = SmartCropIntegration.detectLetterboxType(
            crop: crop, sourceWidth: 1920, sourceHeight: 1080
        )
        XCTAssertEqual(type, .pillarbox)
    }

    /// Verifies windowbox detection — all sides.
    func test_smartCrop_detectLetterboxType_windowbox() {
        let crop = CropRect(width: 1440, height: 800, x: 240, y: 140)
        let type = SmartCropIntegration.detectLetterboxType(
            crop: crop, sourceWidth: 1920, sourceHeight: 1080
        )
        XCTAssertEqual(type, .windowbox)
    }

    /// Verifies no letterbox detection.
    func test_smartCrop_detectLetterboxType_none() {
        let crop = CropRect(width: 1920, height: 1080, x: 0, y: 0)
        let type = SmartCropIntegration.detectLetterboxType(
            crop: crop, sourceWidth: 1920, sourceHeight: 1080
        )
        XCTAssertEqual(type, .none)
    }

    /// Verifies aspect ratio matching for 2.40:1.
    func test_smartCrop_matchAspectRatio_240() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140) // 2.4:1
        let ratio = SmartCropIntegration.matchAspectRatio(crop: crop)
        XCTAssertEqual(ratio, .ratio_2_40_1)
    }

    /// Verifies aspect ratio matching for 16:9.
    func test_smartCrop_matchAspectRatio_16_9() {
        let crop = CropRect(width: 1920, height: 1080, x: 0, y: 0) // 1.778:1
        let ratio = SmartCropIntegration.matchAspectRatio(crop: crop)
        XCTAssertNotNil(ratio)
    }

    /// Verifies snap-to-ratio adjusts dimensions correctly.
    func test_smartCrop_snapToRatio_adjustsWidth() {
        let crop = CropRect(width: 1920, height: 804, x: 0, y: 138)
        let snapped = SmartCropIntegration.snapToRatio(
            crop: crop,
            ratio: .ratio_2_39_1,
            sourceWidth: 1920,
            sourceHeight: 1080
        )
        let snappedRatio = Double(snapped.width) / Double(snapped.height)
        XCTAssertEqual(snappedRatio, 2.39, accuracy: 0.05)
    }

    /// Verifies crop validation passes for normal crop.
    func test_smartCrop_validateCrop_normalCropPasses() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        let warnings = SmartCropIntegration.validateCrop(
            crop: crop, sourceWidth: 1920, sourceHeight: 1080
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    /// Verifies crop validation catches excessive crop.
    func test_smartCrop_validateCrop_excessiveCropWarns() {
        let crop = CropRect(width: 640, height: 480, x: 640, y: 300)
        let config = SmartCropConfig(maxCropPercentage: 40.0)
        let warnings = SmartCropIntegration.validateCrop(
            crop: crop, sourceWidth: 1920, sourceHeight: 1080,
            config: config
        )
        XCTAssertFalse(warnings.isEmpty)
    }

    /// Verifies crop validation catches tiny dimensions.
    func test_smartCrop_validateCrop_tinyDimensionsWarns() {
        let crop = CropRect(width: 32, height: 32, x: 0, y: 0)
        let warnings = SmartCropIntegration.validateCrop(
            crop: crop, sourceWidth: 1920, sourceHeight: 1080
        )
        XCTAssertTrue(warnings.contains { $0.contains("too small") })
    }

    /// Verifies crop filter string generation.
    func test_smartCrop_buildCropFilter() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        let filter = SmartCropIntegration.buildCropFilter(crop: crop)
        XCTAssertEqual(filter, "crop=1920:800:0:140")
    }

    /// Verifies combined crop + scale filter.
    func test_smartCrop_buildCropAndScaleFilter_withTarget() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        let filter = SmartCropIntegration.buildCropAndScaleFilter(
            crop: crop, targetWidth: 1280, targetHeight: 534
        )
        XCTAssertTrue(filter.contains("crop=1920:800:0:140"))
        XCTAssertTrue(filter.contains("scale=1280:534"))
    }

    /// Verifies crop arguments generation.
    func test_smartCrop_buildCropArguments() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        let args = SmartCropIntegration.buildCropArguments(crop: crop)
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("crop=1920:800:0:140"))
    }

    /// Verifies cropdetect arguments use correct threshold.
    func test_smartCrop_buildCropDetectArguments_usesConfigThreshold() {
        let config = SmartCropConfig(mode: .aggressive)
        let args = SmartCropIntegration.buildCropDetectArguments(
            inputPath: "/video.mkv",
            config: config
        )
        XCTAssertTrue(args.contains { $0.contains("limit=16") })
    }

    /// Verifies multi-segment analysis generates correct segment count.
    func test_smartCrop_buildMultiSegmentAnalysis_segmentCount() {
        let segments = SmartCropIntegration.buildMultiSegmentAnalysisArguments(
            inputPath: "/video.mkv",
            duration: 7200.0,
            segments: 5
        )
        XCTAssertEqual(segments.count, 5)
        XCTAssertTrue(segments[0].timestamp > 0)
    }

    /// Verifies variable letterboxing detection.
    func test_smartCrop_hasVariableLetterboxing() {
        let uniform = [
            CropRect(width: 1920, height: 800, x: 0, y: 140),
            CropRect(width: 1920, height: 800, x: 0, y: 140),
        ]
        XCTAssertFalse(SmartCropIntegration.hasVariableLetterboxing(crops: uniform))

        let variable = [
            CropRect(width: 1920, height: 800, x: 0, y: 140),
            CropRect(width: 1920, height: 1080, x: 0, y: 0),
        ]
        XCTAssertTrue(SmartCropIntegration.hasVariableLetterboxing(crops: variable))
    }

    /// Verifies best crop selection from multiple detections.
    func test_smartCrop_selectBestCrop_selectsMostCommon() {
        let crops = [
            CropRect(width: 1920, height: 800, x: 0, y: 140),
            CropRect(width: 1920, height: 800, x: 0, y: 140),
            CropRect(width: 1920, height: 800, x: 0, y: 140),
            CropRect(width: 1920, height: 1080, x: 0, y: 0),
        ]
        let best = SmartCropIntegration.selectBestCrop(crops: crops)
        XCTAssertNotNil(best)
        XCTAssertEqual(best?.height, 800)
    }

    /// Verifies best crop returns nil when no dominant crop.
    func test_smartCrop_selectBestCrop_nilWhenNoDominant() {
        let crops = [
            CropRect(width: 1920, height: 800, x: 0, y: 140),
            CropRect(width: 1920, height: 1080, x: 0, y: 0),
        ]
        let best = SmartCropIntegration.selectBestCrop(crops: crops, minimumFrequency: 0.6)
        XCTAssertNil(best)
    }

    /// Verifies SmartCropConfig defaults.
    func test_smartCropConfig_defaults() {
        let config = SmartCropConfig()
        XCTAssertEqual(config.mode, .auto)
        XCTAssertEqual(config.minimumConfidence, 0.7)
        XCTAssertTrue(config.snapToAspectRatio)
        XCTAssertEqual(config.sampleCount, 10)
        XCTAssertEqual(config.maxCropPercentage, 40.0)
        XCTAssertEqual(config.round, 2)
    }

    /// Verifies CommonAspectRatio numeric values.
    func test_commonAspectRatio_numericValues() {
        XCTAssertEqual(CommonAspectRatio.ratio_16_9.numericValue, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(CommonAspectRatio.ratio_4_3.numericValue, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(CommonAspectRatio.ratio_2_39_1.numericValue, 2.39, accuracy: 0.001)
    }

    // MARK: - CodecMetadataPreserver Tests

    /// Verifies CodecParameterSet default init.
    func test_codecParameterSet_defaultInit() {
        let params = CodecParameterSet()
        XCTAssertNil(params.colorPrimaries)
        XCTAssertNil(params.transferCharacteristics)
        XCTAssertNil(params.pixelFormat)
        XCTAssertNil(params.rotationDegrees)
    }

    /// Verifies preservation arguments include colour description.
    func test_codecMetadataPreserver_buildPreservationArguments_colorDescription() {
        let params = CodecParameterSet(
            colorPrimaries: "bt2020",
            transferCharacteristics: "smpte2084",
            colorMatrix: "bt2020nc",
            colorRange: "tv"
        )
        let args = CodecMetadataPreserver.buildPreservationArguments(params: params)
        XCTAssertTrue(args.contains("-color_primaries"))
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("smpte2084"))
        XCTAssertTrue(args.contains("-colorspace"))
        XCTAssertTrue(args.contains("bt2020nc"))
        XCTAssertTrue(args.contains("-color_range"))
        XCTAssertTrue(args.contains("tv"))
    }

    /// Verifies preservation includes HDR mastering display metadata.
    func test_codecMetadataPreserver_buildPreservationArguments_hdrMetadata() {
        let params = CodecParameterSet(
            masteringDisplayColorVolume: "G(0.265,0.690)B(0.150,0.060)R(0.680,0.320)WP(0.313,0.329)L(1000,0.0001)",
            contentLightLevel: "1000,400"
        )
        let args = CodecMetadataPreserver.buildPreservationArguments(params: params)
        XCTAssertTrue(args.contains("-master_disp"))
        XCTAssertTrue(args.contains("-max_cll"))
        XCTAssertTrue(args.contains("1000,400"))
    }

    /// Verifies preservation includes pixel format.
    func test_codecMetadataPreserver_buildPreservationArguments_pixelFormat() {
        let params = CodecParameterSet(pixelFormat: "yuv420p10le")
        let args = CodecMetadataPreserver.buildPreservationArguments(params: params)
        XCTAssertTrue(args.contains("-pix_fmt"))
        XCTAssertTrue(args.contains("yuv420p10le"))
    }

    /// Verifies preservation includes field order for interlaced.
    func test_codecMetadataPreserver_buildPreservationArguments_interlaced() {
        let params = CodecParameterSet(fieldOrder: "tt")
        let args = CodecMetadataPreserver.buildPreservationArguments(params: params)
        XCTAssertTrue(args.contains("-field_order"))
        XCTAssertTrue(args.contains("tt"))
    }

    /// Verifies progressive field order is not emitted.
    func test_codecMetadataPreserver_buildPreservationArguments_progressiveSkipped() {
        let params = CodecParameterSet(fieldOrder: "progressive")
        let args = CodecMetadataPreserver.buildPreservationArguments(params: params)
        XCTAssertFalse(args.contains("-field_order"))
    }

    /// Verifies rotation metadata preservation.
    func test_codecMetadataPreserver_buildPreservationArguments_rotation() {
        let params = CodecParameterSet(rotationDegrees: 90)
        let args = CodecMetadataPreserver.buildPreservationArguments(params: params)
        XCTAssertTrue(args.contains { $0.contains("rotate=90") })
    }

    /// Verifies dynamic AR preservation with AFD.
    func test_codecMetadataPreserver_buildDynamicARPreservation_withAFD() {
        let info = DynamicAspectRatioInfo(
            afdCode: 10,
            hasBarData: true,
            detectedRatios: ["16:9", "4:3"],
            usesDynamicAR: true
        )
        let args = CodecMetadataPreserver.buildDynamicARPreservationArguments(info: info)
        XCTAssertTrue(args.contains("-copy_unknown"))
        XCTAssertTrue(args.contains("-bsf:v"))
    }

    /// Verifies no args when dynamic AR not used.
    func test_codecMetadataPreserver_buildDynamicARPreservation_noAFD() {
        let args = CodecMetadataPreserver.buildDynamicARPreservationArguments(info: nil)
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies AFD detection arguments.
    func test_codecMetadataPreserver_buildAFDDetectionArguments() {
        let args = CodecMetadataPreserver.buildAFDDetectionArguments(inputPath: "/video.ts")
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("showinfo"))
        XCTAssertTrue(args.contains("/video.ts"))
    }

    /// Verifies FFprobe stream parsing.
    func test_codecMetadataPreserver_parseFromFFprobeStream() {
        let stream: [String: Any] = [
            "color_primaries": "bt709",
            "color_transfer": "bt709",
            "color_space": "bt709",
            "color_range": "tv",
            "pix_fmt": "yuv420p",
            "field_order": "progressive",
            "display_aspect_ratio": "16:9",
        ]
        let params = CodecMetadataPreserver.parseFromFFprobeStream(stream)
        XCTAssertEqual(params.colorPrimaries, "bt709")
        XCTAssertEqual(params.transferCharacteristics, "bt709")
        XCTAssertEqual(params.colorMatrix, "bt709")
        XCTAssertEqual(params.pixelFormat, "yuv420p")
        XCTAssertEqual(params.displayAspectRatio, "16:9")
    }

    /// Verifies parameter validation catches HDR with wrong primaries.
    func test_codecMetadataPreserver_validateParameters_hdrWithWrongPrimaries() {
        let params = CodecParameterSet(
            colorPrimaries: "bt709",
            transferCharacteristics: "smpte2084"
        )
        let warnings = CodecMetadataPreserver.validateParameters(params)
        XCTAssertFalse(warnings.isEmpty)
    }

    /// Verifies parameter validation passes for valid HDR.
    func test_codecMetadataPreserver_validateParameters_validHDR() {
        let params = CodecParameterSet(
            colorPrimaries: "bt2020",
            transferCharacteristics: "smpte2084",
            bitDepth: 10
        )
        let warnings = CodecMetadataPreserver.validateParameters(params)
        XCTAssertTrue(warnings.isEmpty)
    }

    // MARK: - ToolUpdateChecker Tests

    /// Verifies ToolUpdateStatus display names.
    func test_toolUpdateStatus_displayNames() {
        XCTAssertEqual(ToolUpdateStatus.upToDate.displayName, "Up to Date")
        XCTAssertEqual(ToolUpdateStatus.updateAvailable.displayName, "Update Available")
        XCTAssertEqual(ToolUpdateStatus.checkFailed.displayName, "Check Failed")
    }

    /// Verifies ToolUpdateConfig defaults.
    func test_toolUpdateConfig_defaults() {
        let config = ToolUpdateConfig()
        XCTAssertTrue(config.autoCheckEnabled)
        XCTAssertEqual(config.checkIntervalSeconds, 604800)
        XCTAssertFalse(config.includePreRelease)
        XCTAssertFalse(config.autoDownload)
    }

    /// Verifies URL building for latest release.
    func test_toolUpdateChecker_buildLatestReleaseURL() {
        let tool = BundledTool(
            id: "test",
            name: "Test",
            version: "1.0.0",
            sourceURL: "https://github.com/owner/repo",
            lastUpdated: "2026-01-01",
            binaryName: "test",
            description: "Test tool",
            license: "MIT"
        )
        let url = ToolUpdateChecker.buildLatestReleaseURL(tool: tool)
        XCTAssertEqual(url, "https://api.github.com/repos/owner/repo/releases/latest")
    }

    /// Verifies all releases URL building.
    func test_toolUpdateChecker_buildAllReleasesURL() {
        let tool = BundledTool(
            id: "test",
            name: "Test",
            version: "1.0.0",
            sourceURL: "https://github.com/owner/repo",
            lastUpdated: "2026-01-01",
            binaryName: "test",
            description: "Test tool",
            license: "MIT"
        )
        let url = ToolUpdateChecker.buildAllReleasesURL(tool: tool)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.contains("releases?per_page=10"))
    }

    /// Verifies version comparison.
    func test_toolUpdateChecker_compareVersions() {
        XCTAssertEqual(
            ToolUpdateChecker.compareVersions(installed: "1.0.0", latest: "1.1.0"),
            .updateAvailable
        )
        XCTAssertEqual(
            ToolUpdateChecker.compareVersions(installed: "2.0.0", latest: "2.0.0"),
            .upToDate
        )
        XCTAssertEqual(
            ToolUpdateChecker.compareVersions(installed: "2.1.0", latest: "2.0.0"),
            .upToDate
        )
    }

    /// Verifies result building.
    func test_toolUpdateChecker_buildResult_updateAvailable() {
        let tool = BundledTool(
            id: "dovi_tool",
            name: "dovi_tool",
            version: "2.1.2",
            sourceURL: "https://github.com/quietvoid/dovi_tool",
            lastUpdated: "2026-04-01",
            binaryName: "dovi_tool",
            description: "Dolby Vision tool",
            license: "MIT"
        )
        let result = ToolUpdateChecker.buildResult(
            tool: tool,
            latestVersion: "2.2.0",
            downloadURL: "https://example.com/download"
        )
        XCTAssertEqual(result.status, .updateAvailable)
        XCTAssertTrue(result.hasUpdate)
        XCTAssertEqual(result.installedVersion, "2.1.2")
        XCTAssertEqual(result.latestVersion, "2.2.0")
    }

    /// Verifies error result building.
    func test_toolUpdateChecker_buildErrorResult() {
        let tool = BundledTool(
            id: "test",
            name: "Test",
            version: "1.0.0",
            sourceURL: "https://github.com/owner/repo",
            lastUpdated: "2026-01-01",
            binaryName: "test",
            description: "Test",
            license: "MIT"
        )
        let result = ToolUpdateChecker.buildErrorResult(tool: tool)
        XCTAssertEqual(result.status, .checkFailed)
        XCTAssertFalse(result.hasUpdate)
    }

    /// Verifies check scheduling.
    func test_toolUpdateChecker_isCheckDue() {
        // Never checked — should be due
        XCTAssertTrue(ToolUpdateChecker.isCheckDue(lastCheckDate: nil))

        // Checked just now — not due
        XCTAssertFalse(ToolUpdateChecker.isCheckDue(lastCheckDate: Date()))

        // Checked 8 days ago — due (default interval is 7 days)
        let eightDaysAgo = Date(timeIntervalSinceNow: -691200)
        XCTAssertTrue(ToolUpdateChecker.isCheckDue(lastCheckDate: eightDaysAgo))

        // Auto-check disabled — not due
        let config = ToolUpdateConfig(autoCheckEnabled: false)
        XCTAssertFalse(ToolUpdateChecker.isCheckDue(lastCheckDate: nil, config: config))
    }

    /// Verifies results Codable round-trip.
    func test_toolUpdateChecker_resultsRoundTrip() throws {
        let results = [
            ToolUpdateResult(
                toolId: "test",
                toolName: "Test Tool",
                installedVersion: "1.0.0",
                latestVersion: "1.1.0",
                status: .updateAvailable
            )
        ]
        let data = try ToolUpdateChecker.encodeResults(results)
        let decoded = try ToolUpdateChecker.decodeResults(data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].toolId, "test")
        XCTAssertEqual(decoded[0].status, .updateAvailable)
    }

    // MARK: - AdditionalEncodingProfiles Tests

    /// Verifies AV1 profiles have correct codec.
    func test_additionalProfiles_av1_correctCodec() {
        XCTAssertEqual(EncodingProfile.av1_1080p.videoCodec, .av1)
        XCTAssertEqual(EncodingProfile.av1_4K.videoCodec, .av1)
        XCTAssertEqual(EncodingProfile.av1_4KHDR.videoCodec, .av1)
    }

    /// Verifies AV1 4K HDR preserves HDR.
    func test_additionalProfiles_av1_4KHDR_preservesHDR() {
        XCTAssertTrue(EncodingProfile.av1_4KHDR.preserveHDR)
        XCTAssertEqual(EncodingProfile.av1_4KHDR.pixelFormat, "yuv420p10le")
    }

    /// Verifies H.265 extended profiles.
    func test_additionalProfiles_h265_variants() {
        XCTAssertEqual(EncodingProfile.h265_720p.outputWidth, 1280)
        XCTAssertEqual(EncodingProfile.h265_720p.outputHeight, 720)
        XCTAssertEqual(EncodingProfile.h265_1080pHQ.videoPreset, "slow")
        XCTAssertEqual(EncodingProfile.h265_8K.outputWidth, 7680)
    }

    /// Verifies VP9 profiles use WebM container.
    func test_additionalProfiles_vp9_usesWebM() {
        XCTAssertEqual(EncodingProfile.vp9_1080p.containerFormat, .webm)
        XCTAssertEqual(EncodingProfile.vp9_4K.containerFormat, .webm)
    }

    /// Verifies surround profiles have correct channel counts.
    func test_additionalProfiles_surround_channelCounts() {
        XCTAssertEqual(EncodingProfile.h265_1080p_surround.audioChannels, 6)
        XCTAssertEqual(EncodingProfile.h265_4K_dolby.audioChannels, 8)
    }

    /// Verifies audio-only profiles.
    func test_additionalProfiles_audioOnly() {
        XCTAssertEqual(EncodingProfile.audioMP3_HQ.audioBitrate, 320_000)
        XCTAssertEqual(EncodingProfile.audioOpus_voice.audioBitrate, 64_000)
        XCTAssertNil(EncodingProfile.audioFLAC.audioBitrate) // Lossless has no bitrate
    }

    /// Verifies social media profiles have appropriate frame rates.
    func test_additionalProfiles_social_frameRates() {
        XCTAssertEqual(EncodingProfile.socialTwitter.outputFrameRate, 30.0)
        XCTAssertEqual(EncodingProfile.socialInstagram.outputFrameRate, 30.0)
    }

    /// Verifies YouTube profile uses slow preset for quality.
    func test_additionalProfiles_youtube_slowPreset() {
        XCTAssertEqual(EncodingProfile.socialYouTube.videoPreset, "slow")
        XCTAssertEqual(EncodingProfile.socialYouTube.videoCRF, 18)
    }

    /// Verifies all additional profiles list is complete.
    func test_additionalProfiles_allAdditionalProfiles_count() {
        let profiles = EncodingProfile.allAdditionalProfiles
        XCTAssertEqual(profiles.count, 19)
        // All should be built-in
        XCTAssertTrue(profiles.allSatisfy { $0.isBuiltIn })
    }

}
