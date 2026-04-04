// ============================================================================
// MeedyaConverter — CLI Manifest Command
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import ArgumentParser
import Foundation
import ConverterEngine

struct ManifestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "manifest",
        abstract: "Generate adaptive streaming manifests (HLS/DASH) with multi-bitrate variants."
    )

    // MARK: - Required Arguments

    @Option(name: [.short, .customLong("input")], help: "Path to the source media file.")
    var inputPath: String

    @Option(name: [.short, .customLong("output")], help: "Output directory for manifest and segments.")
    var outputDirectory: String

    // MARK: - Format Options

    @Option(name: [.short, .customLong("format")], help: "Manifest format: hls, dash, or cmaf.")
    var format: String = "hls"

    // MARK: - Codec Options

    @Option(name: .customLong("video-codec"), help: "Video codec for all variants (h264, h265, av1).")
    var videoCodec: String = "h264"

    @Option(name: .customLong("audio-codec"), help: "Audio codec (aac, ac3, eac3, opus).")
    var audioCodec: String = "aac"

    @Option(name: .customLong("preset"), help: "Encoder preset (ultrafast, fast, medium, slow, veryslow).")
    var preset: String = "medium"

    // MARK: - Segment Options

    @Option(name: .customLong("segment-duration"), help: "Segment duration in seconds.")
    var segmentDuration: Double = 6.0

    @Option(name: .customLong("keyframe-interval"), help: "Keyframe interval in seconds (GOP alignment).")
    var keyframeInterval: Double = 2.0

    // MARK: - Variant Ladder

    @Option(name: .customLong("variants"), help: "Variant ladder preset: default, 4k, custom.")
    var variantPreset: String = "default"

    @Option(name: .customLong("ladder-file"), help: "Path to JSON file defining custom variant ladder.")
    var ladderFile: String?

    // MARK: - HDR Options

    @Flag(name: .customLong("hdr"), help: "Preserve HDR in output variants.")
    var preserveHDR = false

    @Option(name: .customLong("pixel-format"), help: "Pixel format (yuv420p, yuv420p10le).")
    var pixelFormat: String?

    // MARK: - Hardware

    @Flag(name: .customLong("hardware"), help: "Use hardware encoder if available.")
    var useHardware = false

    // MARK: - Output Control

    @Flag(name: .customLong("dry-run"), help: "Show FFmpeg commands without executing.")
    var dryRun = false

    @Flag(name: .customLong("quiet"), help: "Suppress progress output.")
    var quiet = false

    @Flag(name: .customLong("json"), help: "Output result as JSON.")
    var jsonOutput = false

    @Flag(name: [.short, .customLong("yes")], help: "Overwrite existing output without prompting.")
    var overwrite = false

    // MARK: - Validation

    func validate() throws {
        let url = URL(fileURLWithPath: inputPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("Input file not found: \(inputPath)")
        }

        guard ["hls", "dash", "cmaf"].contains(format.lowercased()) else {
            throw ValidationError("Invalid format '\(format)'. Use: hls, dash, or cmaf.")
        }
    }

    // MARK: - Execution

    func run() async throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputDir = URL(fileURLWithPath: outputDirectory)

        // Initialise engine
        let engine = EncodingEngine()
        try engine.configure()

        guard let ffmpegPath = engine.ffmpegInfo?.path else {
            printStderr("FFmpeg is not available.")
            throw ExitCode(ExitCodes.generalError.rawValue)
        }

        // Resolve manifest format
        guard let manifestFormat = ManifestFormat(rawValue: format.lowercased()) else {
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        // Resolve codecs
        let vCodec = VideoCodec(rawValue: videoCodec) ?? .h264
        let aCodec = AudioCodec(rawValue: audioCodec) ?? .aacLC

        // Resolve variant ladder
        let variants = try resolveVariants()

        // Build config
        let config = ManifestConfig(
            inputURL: inputURL,
            outputDirectory: outputDir,
            format: manifestFormat,
            videoCodec: vCodec,
            audioCodec: aCodec,
            preset: preset,
            keyframeInterval: keyframeInterval,
            segmentDuration: segmentDuration,
            variants: variants,
            preserveHDR: preserveHDR,
            pixelFormat: pixelFormat,
            useHardwareEncoding: useHardware
        )

        let generator = ManifestGenerator(ffmpegPath: ffmpegPath)

        // Validate
        let issues = generator.validate(config: config)
        if !issues.isEmpty {
            for issue in issues {
                printStderr("Warning: \(issue)")
            }
        }

        if dryRun {
            printDryRun(generator: generator, config: config)
            return
        }

        // Create output directory
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Create variant subdirectories
        for (i, variant) in config.variants.enumerated() {
            let variantDir = outputDir.appendingPathComponent("v\(i)_\(variant.label)")
            try FileManager.default.createDirectory(at: variantDir, withIntermediateDirectories: true)
        }

        if !quiet { printStderr("Generating \(format.uppercased()) manifest with \(variants.count) variants...") }

        // Encode each variant
        let startTime = Date()
        for (i, variant) in config.variants.enumerated() {
            if !quiet { printStderr("Encoding variant \(i + 1)/\(config.variants.count): \(variant.label) (\(variant.width)x\(variant.height))") }

            let args = generator.buildVariantArguments(config: config, variant: variant, variantIndex: i)

            // Run FFmpeg for this variant
            try await engine.runFFmpeg(arguments: args) { progressInfo in
                if !quiet && !jsonOutput {
                    let progress = progressInfo.fractionComplete ?? 0
                    let overallProgress = (Double(i) + progress) / Double(config.variants.count)
                    let pct = Int(overallProgress * 100)
                    printStderr("\r  [\(variant.label)] \(pct)%", terminator: "")
                }
            }
            if !quiet && !jsonOutput { printStderr("") }
        }

        // Write master manifest
        switch config.format {
        case .hls, .cmaf:
            let masterPlaylist = generator.buildMasterPlaylist(config: config)
            let masterURL = outputDir.appendingPathComponent("master.m3u8")
            try masterPlaylist.write(to: masterURL, atomically: true, encoding: .utf8)
            if !quiet { printStderr("Master playlist: \(masterURL.path)") }

        case .dash:
            let mpd = generator.buildDASHManifest(config: config)
            let mpdURL = outputDir.appendingPathComponent("manifest.mpd")
            try mpd.write(to: mpdURL, atomically: true, encoding: .utf8)
            if !quiet { printStderr("DASH manifest: \(mpdURL.path)") }
        }

        // Also write DASH for CMAF (dual manifest)
        if config.format == .cmaf {
            let mpd = generator.buildDASHManifest(config: config)
            let mpdURL = outputDir.appendingPathComponent("manifest.mpd")
            try mpd.write(to: mpdURL, atomically: true, encoding: .utf8)
            if !quiet { printStderr("DASH manifest: \(mpdURL.path)") }
        }

        let elapsed = Date().timeIntervalSince(startTime)

        if jsonOutput {
            let result: [String: Any] = [
                "status": "completed",
                "format": format,
                "variants": variants.count,
                "output": outputDir.path,
                "elapsed_seconds": elapsed,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else if !quiet {
            let mins = Int(elapsed) / 60
            let secs = Int(elapsed) % 60
            printStderr("Done in \(mins)m \(secs)s — \(variants.count) variants → \(outputDir.path)")
        }
    }

    // MARK: - Helpers

    private func resolveVariants() throws -> [StreamingVariant] {
        if let path = ladderFile {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([StreamingVariant].self, from: data)
        }

        switch variantPreset.lowercased() {
        case "4k", "uhd": return StreamingVariant.uhdrLadder
        default: return StreamingVariant.defaultLadder
        }
    }

    private func printDryRun(generator: ManifestGenerator, config: ManifestConfig) {
        print("Dry run — FFmpeg commands that would be executed:")
        print("")
        for (i, variant) in config.variants.enumerated() {
            let args = generator.buildVariantArguments(config: config, variant: variant, variantIndex: i)
            print("# Variant \(i + 1): \(variant.label)")
            print("ffmpeg \(args.joined(separator: " "))")
            print("")
        }

        print("# Master manifest would be written to:")
        switch config.format {
        case .hls, .cmaf: print("\(config.outputDirectory.path)/master.m3u8")
        case .dash: print("\(config.outputDirectory.path)/manifest.mpd")
        }
    }
}
