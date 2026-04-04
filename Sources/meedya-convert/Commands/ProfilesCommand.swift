// ============================================================================
// MeedyaConverter — CLI Profiles Command
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import ArgumentParser
import Foundation
import ConverterEngine

struct ProfilesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profiles",
        abstract: "List, show, or validate encoding profiles."
    )

    @Flag(name: .customLong("list"), help: "List all available encoding profiles.")
    var listProfiles = false

    @Option(name: .customLong("show"), help: "Show details of a named profile.")
    var showProfile: String?

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    func run() async throws {
        if listProfiles || showProfile == nil {
            listAllProfiles()
        } else if let name = showProfile {
            try showProfileDetails(name)
        }
    }

    private func listAllProfiles() {
        let profiles = EncodingProfile.builtInProfiles

        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(profiles),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            return
        }

        print("Available Encoding Profiles (\(profiles.count) built-in):")
        print("")

        var currentCategory: String?
        for profile in profiles {
            let category = profile.category?.rawValue ?? "uncategorized"
            if category != currentCategory {
                currentCategory = category
                print("  \(category.capitalized):")
            }

            var line = "    \(profile.name)"
            if let vc = profile.videoCodec {
                line += " — \(vc.displayName)"
            }
            if let ac = profile.audioCodec {
                line += " + \(ac.displayName)"
            }
            line += " → .\(profile.containerFormat.rawValue)"
            print(line)
        }

        print("")
        print("Use --show <name> for details.")
    }

    private func showProfileDetails(_ name: String) throws {
        guard let profile = EncodingProfile.builtInProfiles.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) else {
            printStderr("Profile not found: \(name)")
            printStderr("Use --list to see available profiles.")
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(profile),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            return
        }

        print("Profile: \(profile.name)")
        print("Category: \(profile.category?.rawValue ?? "custom")")
        print("")

        print("Video:")
        if profile.videoPassthrough {
            print("  Codec: passthrough (copy)")
        } else if let vc = profile.videoCodec {
            print("  Codec: \(vc.displayName) (\(vc.ffmpegEncoder ?? "n/a"))")
            if let crf = profile.videoCRF { print("  CRF: \(crf)") }
            if let preset = profile.videoPreset { print("  Preset: \(preset)") }
            if let w = profile.outputWidth, let h = profile.outputHeight {
                print("  Resolution: \(w)x\(h)")
            }
        }

        print("")
        print("Audio:")
        if profile.audioPassthrough {
            print("  Codec: passthrough (copy)")
        } else if let ac = profile.audioCodec {
            print("  Codec: \(ac.displayName) (\(ac.ffmpegEncoder ?? "n/a"))")
            if let br = profile.audioBitrate { print("  Bitrate: \(br / 1000)k") }
            if let ch = profile.audioChannels { print("  Channels: \(ch)") }
        }

        print("")
        print("Container: \(profile.containerFormat.displayName)")

        if profile.toneMapToSDR { print("Tone mapping: enabled (\(profile.toneMapAlgorithm ?? "hable"))") }
        if profile.convertPQToHLG { print("PQ → HLG: enabled") }
        if profile.convertPQToDVHLG { print("PQ → DV+HLG: enabled") }
    }
}
