// ============================================================================
// MeedyaConverter — CLI Probe Command
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import ArgumentParser
import Foundation
import ConverterEngine

struct ProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe",
        abstract: "Inspect a media file and print its metadata."
    )

    @Option(name: [.short, .customLong("input")], help: "Path to the media file to inspect.")
    var inputPath: String

    @Option(name: [.short, .customLong("format")], help: "Output format: text (default), json.")
    var outputFormat: OutputFormat = .text

    @Flag(name: .customLong("streams-only"), help: "Show only stream information.")
    var streamsOnly = false

    @Flag(name: .customLong("hdr"), help: "Show HDR metadata details.")
    var showHDR = false

    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
    }

    func validate() throws {
        let url = URL(fileURLWithPath: inputPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("Input file not found: \(inputPath)")
        }
    }

    func run() async throws {
        let inputURL = URL(fileURLWithPath: inputPath)

        let engine = EncodingEngine()
        try engine.configure()

        let mediaFile: MediaFile
        do {
            mediaFile = try await engine.probe(url: inputURL)
        } catch {
            printStderr("Probe failed: \(error.localizedDescription)")
            throw ExitCode(ExitCodes.encodingFailed.rawValue)
        }

        switch outputFormat {
        case .text:
            printTextOutput(mediaFile)
        case .json:
            printJSONOutput(mediaFile)
        }
    }

    // MARK: - Text Output

    private func printTextOutput(_ file: MediaFile) {
        if !streamsOnly {
            print("File: \(file.fileName)")
            print("Path: \(file.fileURL.path)")
            print("Size: \(file.fileSizeString)")
            if let duration = file.durationString {
                print("Duration: \(duration)")
            }
            if let bitrate = file.overallBitrate {
                print("Bitrate: \(bitrate / 1000) kbps")
            }
            print("Container: \(file.containerFormat?.rawValue ?? "unknown")")

            if file.hasHDR {
                var hdrTypes: [String] = []
                if file.hasDolbyVision { hdrTypes.append("Dolby Vision") }
                if file.hasPQ { hdrTypes.append("HDR10 (PQ)") }
                if file.hasHLG { hdrTypes.append("HLG") }
                print("HDR: \(hdrTypes.joined(separator: ", "))")
            }

            if !file.chapters.isEmpty {
                print("Chapters: \(file.chapters.count)")
            }

            print("")
        }

        // Video streams
        let videoStreams = file.videoStreams
        if !videoStreams.isEmpty {
            print("Video Streams:")
            for stream in videoStreams {
                var info = "  #\(stream.streamIndex): \(stream.codecName ?? "unknown")"
                if let res = stream.resolutionString { info += " \(res)" }
                if let fps = stream.frameRate { info += " \(String(format: "%.2f", fps)) fps" }
                if let br = stream.bitrate { info += " \(br / 1000) kbps" }
                if !stream.hdrFormats.isEmpty {
                    let hdrStr = stream.hdrFormats.map(\.rawValue).joined(separator: "+")
                    info += " [\(hdrStr)]"
                }
                if stream.isDefault { info += " (default)" }
                print(info)

                if showHDR, let colour = stream.colourProperties {
                    printColourProperties(colour)
                }
            }
            print("")
        }

        // Audio streams
        let audioStreams = file.audioStreams
        if !audioStreams.isEmpty {
            print("Audio Streams:")
            for stream in audioStreams {
                var info = "  #\(stream.streamIndex): \(stream.codecName ?? "unknown")"
                if let layout = stream.channelLayout { info += " \(layout.description)" }
                if let sr = stream.sampleRate { info += " \(sr) Hz" }
                if let br = stream.bitrate { info += " \(br / 1000) kbps" }
                if let lang = stream.language { info += " [\(lang)]" }
                if let title = stream.title { info += " \"\(title)\"" }
                if stream.isDefault { info += " (default)" }
                print(info)
            }
            print("")
        }

        // Subtitle streams
        let subtitleStreams = file.subtitleStreams
        if !subtitleStreams.isEmpty {
            print("Subtitle Streams:")
            for stream in subtitleStreams {
                var info = "  #\(stream.streamIndex): \(stream.subtitleFormat?.rawValue ?? stream.codecName ?? "unknown")"
                if let lang = stream.language { info += " [\(lang)]" }
                if let title = stream.title { info += " \"\(title)\"" }
                if stream.isForced { info += " (forced)" }
                if stream.isDefault { info += " (default)" }
                print(info)
            }
            print("")
        }

        // Metadata
        if !streamsOnly && !file.metadata.isEmpty {
            print("Metadata:")
            for (key, value) in file.metadata.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value)")
            }
        }
    }

    private func printColourProperties(_ colour: ColourProperties) {
        if let primaries = colour.colourPrimaries {
            print("    Primaries: \(primaries)")
        }
        if let transfer = colour.transferCharacteristics {
            print("    Transfer: \(transfer)")
        }
        if let matrix = colour.matrixCoefficients {
            print("    Matrix: \(matrix)")
        }
        if let maxCLL = colour.maxCLL {
            print("    MaxCLL: \(maxCLL) nits")
        }
        if let maxFALL = colour.maxFALL {
            print("    MaxFALL: \(maxFALL) nits")
        }
        if let maxLum = colour.masteringDisplayMaxLuminance {
            print("    Mastering Max: \(maxLum) nits")
        }
        if let minLum = colour.masteringDisplayMinLuminance {
            print("    Mastering Min: \(minLum) nits")
        }
    }

    // MARK: - JSON Output

    private func printJSONOutput(_ file: MediaFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(file)
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } catch {
            printStderr("Failed to encode JSON: \(error.localizedDescription)")
        }
    }
}
