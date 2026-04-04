// ============================================================================
// MeedyaConverter — CLI Encode Command
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import ArgumentParser
import Foundation
import ConverterEngine

struct EncodeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "encode",
        abstract: "Transcode a media file using a named profile or custom settings."
    )

    // MARK: - Required Arguments

    @Option(name: [.short, .customLong("input")], help: "Path to the input media file.")
    var inputPath: String

    // MARK: - Output Options

    @Option(name: [.short, .customLong("output")], help: "Path to the output file. Defaults to input directory with profile-based extension.")
    var outputPath: String?

    // MARK: - Profile Selection

    @Option(name: [.short, .customLong("profile")], help: "Name or ID of the encoding profile to use.")
    var profileName: String?

    // MARK: - Video Options

    @Option(name: .customLong("video-codec"), help: "Video codec (h264, h265, av1, prores, vp9, copy).")
    var videoCodec: String?

    @Option(name: .customLong("crf"), help: "Constant Rate Factor (quality, lower = better).")
    var crf: Int?

    @Option(name: .customLong("video-bitrate"), help: "Video bitrate (e.g., 5000k, 10M).")
    var videoBitrate: String?

    @Option(name: .customLong("preset"), help: "Encoder preset (ultrafast, fast, medium, slow, veryslow).")
    var preset: String?

    @Option(name: .customLong("resolution"), help: "Output resolution (e.g., 1920x1080, 1280x720).")
    var resolution: String?

    @Flag(name: .customLong("video-passthrough"), help: "Copy video stream without re-encoding.")
    var videoPassthrough = false

    // MARK: - Audio Options

    @Option(name: .customLong("audio-codec"), help: "Audio codec (aac, ac3, eac3, flac, opus, copy).")
    var audioCodec: String?

    @Option(name: .customLong("audio-bitrate"), help: "Audio bitrate (e.g., 128k, 256k, 640k).")
    var audioBitrate: String?

    @Option(name: .customLong("audio-channels"), help: "Audio channel count (1, 2, 6 for 5.1, 8 for 7.1).")
    var audioChannels: Int?

    @Flag(name: .customLong("audio-passthrough"), help: "Copy audio stream without re-encoding.")
    var audioPassthrough = false

    // MARK: - Subtitle Options

    @Flag(name: .customLong("subtitle-passthrough"), help: "Copy subtitle streams.")
    var subtitlePassthrough = false

    @Flag(name: .customLong("no-subtitles"), help: "Exclude all subtitle streams from output.")
    var noSubtitles = false

    // MARK: - Container

    @Option(name: .customLong("container"), help: "Output container format (mkv, mp4, webm, mov, ts).")
    var container: String?

    // MARK: - HDR Options

    @Flag(name: .customLong("tonemap"), help: "Enable HDR → SDR tone mapping.")
    var toneMap = false

    @Option(name: .customLong("tonemap-algorithm"), help: "Tone mapping algorithm (hable, reinhard, mobius, bt2390, linear).")
    var toneMapAlgorithm: String?

    @Flag(name: .customLong("pq-to-hlg"), help: "Convert PQ (HDR10) to HLG transfer function.")
    var pqToHlg = false

    @Flag(name: .customLong("pq-to-dv-hlg"), help: "Convert PQ to Dolby Vision Profile 8.4 + HLG.")
    var pqToDvHlg = false

    // MARK: - Metadata

    @Flag(name: .customLong("no-copy-metadata"), help: "Do not copy source metadata to output.")
    var noCopyMetadata = false

    @Flag(name: .customLong("no-copy-chapters"), help: "Do not copy chapter markers to output.")
    var noCopyChapters = false

    // MARK: - Stream Selection

    @Option(name: .customLong("video-stream"), help: "Video stream index to encode (default: first).")
    var videoStreamIndex: Int?

    @Option(name: .customLong("audio-stream"), help: "Audio stream index to encode (default: first).")
    var audioStreamIndex: Int?

    @Option(name: .customLong("subtitle-stream"), help: "Subtitle stream index to include.")
    var subtitleStreamIndex: Int?

    @Flag(name: .customLong("map-all"), help: "Map all streams from source.")
    var mapAllStreams = false

    // MARK: - Hardware Encoding

    @Flag(name: .customLong("hardware"), help: "Use hardware encoder if available.")
    var useHardware = false

    // MARK: - Output Control

    @Flag(name: .customLong("quiet"), help: "Suppress progress output.")
    var quiet = false

    @Flag(name: .customLong("json"), help: "Output progress and result as JSON.")
    var jsonOutput = false

    @Flag(name: [.short, .customLong("yes")], help: "Overwrite output file without prompting.")
    var overwrite = false

    // MARK: - Execution

    func validate() throws {
        let url = URL(fileURLWithPath: inputPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("Input file not found: \(inputPath)")
        }

        if videoPassthrough && videoCodec != nil {
            throw ValidationError("Cannot specify --video-codec with --video-passthrough.")
        }
        if audioPassthrough && audioCodec != nil {
            throw ValidationError("Cannot specify --audio-codec with --audio-passthrough.")
        }
        if toneMap && pqToHlg {
            throw ValidationError("Cannot use --tonemap and --pq-to-hlg together (mutually exclusive).")
        }
    }

    func run() async throws {
        let inputURL = URL(fileURLWithPath: inputPath)

        // Initialise engine
        let engine = EncodingEngine()
        try engine.configure()

        // Probe input file
        if !quiet { printStderr("Probing \(inputURL.lastPathComponent)...") }
        let mediaFile = try await engine.probe(url: inputURL)

        // Resolve encoding profile
        let profile = try resolveProfile(engine: engine, mediaFile: mediaFile)

        // Determine output URL
        let outputURL = resolveOutputURL(inputURL: inputURL, profile: profile)

        // Check for existing output
        if FileManager.default.fileExists(atPath: outputURL.path) && !overwrite {
            throw ExitCode(ExitCodes.outputWriteError.rawValue)
        }

        // Build job config
        var config = EncodingJobConfig(
            inputURL: inputURL,
            outputURL: outputURL,
            profile: profile,
            videoStreamIndex: videoStreamIndex,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            mapAllStreams: mapAllStreams
        )

        if noCopyMetadata {
            config.extraArguments += ["-map_metadata", "-1"]
        }
        if noCopyChapters {
            config.extraArguments += ["-map_chapters", "-1"]
        }

        // Run encode
        let startTime = Date()
        if !quiet && !jsonOutput {
            printStderr("Encoding \(inputURL.lastPathComponent) → \(outputURL.lastPathComponent)")
            printStderr("Profile: \(profile.name)")
        }

        do {
            try await engine.encode(job: config) { progressInfo in
                if !quiet {
                    let progress = progressInfo.fractionComplete ?? 0
                    if jsonOutput {
                        printProgressJSON(progress: progress)
                    } else {
                        printProgressBar(progress: progress)
                    }
                }
            }
        } catch {
            printStderr("Encoding failed: \(error.localizedDescription)")
            throw ExitCode(ExitCodes.encodingFailed.rawValue)
        }

        let elapsed = Date().timeIntervalSince(startTime)

        if jsonOutput {
            let result: [String: Any] = [
                "status": "completed",
                "input": inputURL.path,
                "output": outputURL.path,
                "elapsed_seconds": elapsed,
                "profile": profile.name,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else if !quiet {
            let mins = Int(elapsed) / 60
            let secs = Int(elapsed) % 60
            printStderr("Done in \(mins)m \(secs)s → \(outputURL.path)")
        }
    }

    // MARK: - Helpers

    private func resolveProfile(engine: EncodingEngine, mediaFile: MediaFile) throws -> EncodingProfile {
        if let name = profileName {
            // Look up by name in built-in profiles
            if let profile = EncodingProfile.builtInProfiles.first(where: {
                $0.name.lowercased() == name.lowercased()
            }) {
                return applyOverrides(to: profile)
            }
            // Look up in profile store
            if let profile = engine.profileStore.profile(named: name) {
                return applyOverrides(to: profile)
            }
            throw ValidationError("Profile not found: \(name)")
        }

        // Build profile from CLI flags
        var profile = EncodingProfile.quickConvert
        profile = applyOverrides(to: profile)
        return profile
    }

    private func applyOverrides(to base: EncodingProfile) -> EncodingProfile {
        var profile = base

        if videoPassthrough { profile.videoPassthrough = true }
        if audioPassthrough { profile.audioPassthrough = true }
        if subtitlePassthrough { profile.subtitlePassthrough = true }
        if noSubtitles { profile.subtitlePassthrough = false }

        if let codec = videoCodec {
            profile.videoCodec = VideoCodec(rawValue: codec)
        }
        if let c = crf { profile.videoCRF = c }
        if let br = videoBitrate { profile.videoBitrate = parseBitrate(br) }
        if let p = preset { profile.videoPreset = p }
        if let r = resolution, let parsed = parseResolution(r) {
            profile.outputWidth = parsed.width
            profile.outputHeight = parsed.height
        }

        if let codec = audioCodec {
            profile.audioCodec = AudioCodec(rawValue: codec)
        }
        if let br = audioBitrate { profile.audioBitrate = parseBitrate(br) }
        if let ch = audioChannels { profile.audioChannels = ch }

        if let fmt = container {
            if let cf = ContainerFormat(rawValue: fmt) {
                profile.containerFormat = cf
            } else if let cf = ContainerFormat.from(fileExtension: fmt) {
                profile.containerFormat = cf
            }
        }

        if toneMap { profile.toneMapToSDR = true }
        if let algo = toneMapAlgorithm { profile.toneMapAlgorithm = algo }
        if pqToHlg { profile.convertPQToHLG = true }
        if pqToDvHlg { profile.convertPQToDVHLG = true }

        if useHardware { profile.useHardwareEncoding = true }

        return profile
    }

    private func resolveOutputURL(inputURL: URL, profile: EncodingProfile) -> URL {
        if let path = outputPath {
            return URL(fileURLWithPath: path)
        }
        let dir = inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let ext = profile.preferredExtension
        return dir.appendingPathComponent("\(stem)_converted.\(ext)")
    }

    private func parseResolution(_ str: String) -> (width: Int, height: Int)? {
        let parts = str.lowercased().split(separator: "x")
        guard parts.count == 2,
              let w = Int(parts[0]),
              let h = Int(parts[1]) else { return nil }
        return (w, h)
    }

    private func parseBitrate(_ str: String) -> Int? {
        let lowered = str.lowercased().trimmingCharacters(in: .whitespaces)
        if lowered.hasSuffix("m") {
            return Int(lowered.dropLast()).map { $0 * 1_000_000 }
        } else if lowered.hasSuffix("k") {
            return Int(lowered.dropLast()).map { $0 * 1000 }
        }
        return Int(lowered)
    }
}

// MARK: - Progress Display

private func printProgressBar(progress: Double) {
    let pct = Int(progress * 100)
    let filled = pct / 2
    let empty = 50 - filled
    let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    printStderr("\r[\(bar)] \(pct)%", terminator: "")
    if pct >= 100 { printStderr("") }
}

private func printProgressJSON(progress: Double) {
    let pct = Int(progress * 100)
    printStderr("{\"progress\":\(pct)}")
}
