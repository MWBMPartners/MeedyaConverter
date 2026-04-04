// ============================================================================
// MeedyaConverter — CLI Validate Command
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import ArgumentParser
import Foundation
import ConverterEngine

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate encoding profiles, manifest configurations, and platform compatibility."
    )

    // MARK: - Validation Targets

    @Option(name: .customLong("profile"), help: "Validate a named encoding profile.")
    var profileName: String?

    @Option(name: .customLong("profile-file"), help: "Validate a profile from a JSON file.")
    var profileFile: String?

    @Option(name: .customLong("manifest"), help: "Validate a manifest config JSON file.")
    var manifestFile: String?

    @Option(name: .customLong("platform"), help: "Target platform for compatibility check (macOS, iOS, tvOS, windows, android, chromecast, webBrowser, plex, jellyfin, roku, fireTV).")
    var platform: String?

    // MARK: - Options

    @Flag(name: .customLong("json"), help: "Output validation results as JSON.")
    var jsonOutput = false

    @Flag(name: .customLong("strict"), help: "Treat warnings as errors (exit code 6 on warnings).")
    var strict = false

    // MARK: - Validation

    func validate() throws {
        let hasTarget = profileName != nil || profileFile != nil || manifestFile != nil
        guard hasTarget else {
            throw ValidationError("Specify at least one of: --profile, --profile-file, or --manifest.")
        }
    }

    // MARK: - Execution

    func run() async throws {
        var allWarnings: [String] = []
        var allErrors: [String] = []

        // Validate named profile
        if let name = profileName {
            let (warnings, errors) = validateNamedProfile(name)
            allWarnings += warnings
            allErrors += errors
        }

        // Validate profile from file
        if let path = profileFile {
            let (warnings, errors) = try validateProfileFromFile(path)
            allWarnings += warnings
            allErrors += errors
        }

        // Validate manifest config
        if let path = manifestFile {
            let (warnings, errors) = try validateManifestConfig(path)
            allWarnings += warnings
            allErrors += errors
        }

        // Output results
        if jsonOutput {
            printJSON(warnings: allWarnings, errors: allErrors)
        } else {
            printText(warnings: allWarnings, errors: allErrors)
        }

        // Exit code
        if !allErrors.isEmpty {
            throw ExitCode(ExitCodes.validationFailed.rawValue)
        }
        if strict && !allWarnings.isEmpty {
            throw ExitCode(ExitCodes.validationFailed.rawValue)
        }
    }

    // MARK: - Profile Validation

    private func validateNamedProfile(_ name: String) -> (warnings: [String], errors: [String]) {
        var warnings: [String] = []
        var errors: [String] = []

        guard let profile = EncodingProfile.builtInProfiles.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) else {
            errors.append("Profile not found: \(name)")
            return (warnings, errors)
        }

        warnings += validateProfileSettings(profile)

        // Platform compatibility check
        if let platformName = platform,
           let plat = PlatformFormatPolicy.Platform(rawValue: platformName) {
            let platWarnings = PlatformFormatPolicy.validate(profile: profile, for: plat)
            warnings += platWarnings.map { "[\(platformName)] \($0)" }
        }

        return (warnings, errors)
    }

    private func validateProfileFromFile(_ path: String) throws -> (warnings: [String], errors: [String]) {
        var warnings: [String] = []
        var errors: [String] = []

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errors.append("Profile file not found: \(path)")
            return (warnings, errors)
        }

        do {
            let data = try Data(contentsOf: url)
            let profile = try JSONDecoder().decode(EncodingProfile.self, from: data)
            warnings += validateProfileSettings(profile)

            if let platformName = platform,
               let plat = PlatformFormatPolicy.Platform(rawValue: platformName) {
                let platWarnings = PlatformFormatPolicy.validate(profile: profile, for: plat)
                warnings += platWarnings.map { "[\(platformName)] \($0)" }
            }
        } catch {
            errors.append("Failed to parse profile JSON: \(error.localizedDescription)")
        }

        return (warnings, errors)
    }

    private func validateProfileSettings(_ profile: EncodingProfile) -> [String] {
        var warnings: [String] = []

        // Check codec-container compatibility
        if let videoCodec = profile.videoCodec {
            if !profile.containerFormat.supportsVideoCodec(videoCodec) {
                warnings.append("Video codec \(videoCodec.rawValue) is not supported in \(profile.containerFormat.rawValue) container")
            }
        }

        if let audioCodec = profile.audioCodec {
            if !profile.containerFormat.supportsAudioCodec(audioCodec) {
                warnings.append("Audio codec \(audioCodec.rawValue) is not supported in \(profile.containerFormat.rawValue) container")
            }
        }

        // Check HDR settings consistency
        if profile.toneMapToSDR && profile.preserveHDR {
            warnings.append("Both toneMapToSDR and preserveHDR are true — tone mapping will override HDR preservation")
        }

        if profile.toneMapToSDR && profile.convertPQToHLG {
            warnings.append("Both toneMapToSDR and convertPQToHLG are true — these are mutually exclusive")
        }

        // Check HDR codec support
        if profile.preserveHDR, let vc = profile.videoCodec, !vc.supportsHDR {
            warnings.append("preserveHDR is true but \(vc.rawValue) does not support HDR")
        }

        // Check CRF range
        if let crf = profile.videoCRF {
            if crf < 0 || crf > 63 {
                warnings.append("CRF value \(crf) is outside valid range (0-63)")
            }
        }

        // Check hardware encoding with CRF
        if profile.useHardwareEncoding && profile.videoCRF != nil && profile.videoQP == nil {
            warnings.append("Hardware encoders use QP, not CRF — CRF will be ignored with hardware encoding")
        }

        // Check bitrate consistency
        if profile.videoBitrate != nil && profile.videoCRF != nil {
            warnings.append("Both video bitrate and CRF set — CRF takes precedence with software encoders")
        }

        return warnings
    }

    // MARK: - Manifest Validation

    private func validateManifestConfig(_ path: String) throws -> (warnings: [String], errors: [String]) {
        var warnings: [String] = []
        var errors: [String] = []

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errors.append("Manifest config file not found: \(path)")
            return (warnings, errors)
        }

        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(ManifestConfig.self, from: data)

            // Use ManifestGenerator's built-in validation
            let generator = ManifestGenerator(ffmpegPath: "ffmpeg")
            let issues = generator.validate(config: config)
            warnings += issues

            // Additional checks
            if config.variants.count > 10 {
                warnings.append("Large variant ladder (\(config.variants.count) variants) — consider reducing for faster encoding")
            }

            // Check for duplicate resolutions
            let resolutions = config.variants.map { "\($0.width)x\($0.height)" }
            let uniqueResolutions = Set(resolutions)
            if resolutions.count != uniqueResolutions.count {
                warnings.append("Duplicate resolutions found in variant ladder")
            }

            // Check bitrate ordering
            let sortedByBitrate = config.variants.sorted { $0.videoBitrate > $1.videoBitrate }
            let sortedByResolution = config.variants.sorted { $0.width * $0.height > $1.width * $1.height }
            if sortedByBitrate.map(\.label) != sortedByResolution.map(\.label) {
                warnings.append("Bitrate ordering does not match resolution ordering — higher resolutions should have higher bitrates")
            }
        } catch {
            errors.append("Failed to parse manifest config: \(error.localizedDescription)")
        }

        return (warnings, errors)
    }

    // MARK: - Output

    private func printJSON(warnings: [String], errors: [String]) {
        let result: [String: Any] = [
            "valid": errors.isEmpty && (!strict || warnings.isEmpty),
            "errors": errors,
            "warnings": warnings,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    private func printText(warnings: [String], errors: [String]) {
        if errors.isEmpty && warnings.isEmpty {
            print("Validation passed — no issues found.")
            return
        }

        if !errors.isEmpty {
            print("Errors (\(errors.count)):")
            for err in errors {
                print("  ERROR: \(err)")
            }
        }

        if !warnings.isEmpty {
            print("Warnings (\(warnings.count)):")
            for warn in warnings {
                print("  WARN: \(warn)")
            }
        }

        if errors.isEmpty {
            print("\nValidation passed with \(warnings.count) warning(s).")
        } else {
            print("\nValidation failed with \(errors.count) error(s).")
        }
    }
}
