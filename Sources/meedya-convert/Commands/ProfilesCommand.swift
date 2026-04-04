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

    @Option(name: .customLong("export"), help: "Export a named profile to a JSON file.")
    var exportProfile: String?

    @Option(name: .customLong("export-file"), help: "Output file path for profile export (defaults to stdout).")
    var exportFile: String?

    @Option(name: .customLong("import"), help: "Import a profile from a JSON file.")
    var importFile: String?

    @Option(name: .customLong("validate"), help: "Validate a named profile's codec/container compatibility.")
    var validateProfile: String?

    @Option(name: .customLong("platform"), help: "Target platform for compatibility check.")
    var platform: String?

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    func run() async throws {
        if let name = exportProfile {
            try exportProfileToFile(name)
        } else if let path = importFile {
            try importProfileFromFile(path)
        } else if let name = validateProfile {
            try validateProfileByName(name)
        } else if let name = showProfile {
            try showProfileDetails(name)
        } else {
            listAllProfiles()
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
            let category = profile.category.rawValue
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

    private func exportProfileToFile(_ name: String) throws {
        guard let profile = EncodingProfile.builtInProfiles.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) else {
            printStderr("Profile not found: \(name)")
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)

        if let path = exportFile {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            printStderr("Exported '\(profile.name)' to \(path)")
        } else {
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        }
    }

    private func importProfileFromFile(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            printStderr("File not found: \(path)")
            throw ExitCode(ExitCodes.inputNotFound.rawValue)
        }

        let data = try Data(contentsOf: url)
        let store = EncodingProfileStore()
        let profile = try store.importProfile(from: data)

        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(profile),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("Imported profile: \(profile.name)")
            print("Category: custom")
            if let vc = profile.videoCodec { print("Video: \(vc.displayName)") }
            if let ac = profile.audioCodec { print("Audio: \(ac.displayName)") }
            print("Container: \(profile.containerFormat.displayName)")
        }
    }

    private func validateProfileByName(_ name: String) throws {
        guard let profile = EncodingProfile.builtInProfiles.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) else {
            printStderr("Profile not found: \(name)")
            throw ExitCode(ExitCodes.invalidArguments.rawValue)
        }

        var warnings: [String] = []

        // Codec-container compatibility
        if let vc = profile.videoCodec, !profile.containerFormat.supportsVideoCodec(vc) {
            warnings.append("Video codec \(vc.rawValue) not supported in \(profile.containerFormat.rawValue)")
        }
        if let ac = profile.audioCodec, !profile.containerFormat.supportsAudioCodec(ac) {
            warnings.append("Audio codec \(ac.rawValue) not supported in \(profile.containerFormat.rawValue)")
        }
        if profile.toneMapToSDR && profile.convertPQToHLG {
            warnings.append("toneMapToSDR and convertPQToHLG are mutually exclusive")
        }
        if profile.preserveHDR, let vc = profile.videoCodec, !vc.supportsHDR {
            warnings.append("preserveHDR enabled but \(vc.rawValue) doesn't support HDR")
        }

        // Platform check
        if let platformName = platform,
           let plat = PlatformFormatPolicy.Platform(rawValue: platformName) {
            let platWarnings = PlatformFormatPolicy.validate(profile: profile, for: plat)
            warnings += platWarnings
        }

        if jsonOutput {
            let result: [String: Any] = [
                "profile": name,
                "valid": warnings.isEmpty,
                "warnings": warnings,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            if warnings.isEmpty {
                print("Profile '\(name)' is valid — no issues found.")
            } else {
                print("Profile '\(name)' — \(warnings.count) warning(s):")
                for w in warnings { print("  WARN: \(w)") }
            }
        }
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
        print("Category: \(profile.category.rawValue)")
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
