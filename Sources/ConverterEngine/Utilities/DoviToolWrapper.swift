// ============================================================================
// MeedyaConverter — DoviToolWrapper
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DoviToolError

/// Errors from dovi_tool operations.
public enum DoviToolError: LocalizedError, Sendable {
    /// dovi_tool binary was not found.
    case binaryNotFound
    /// dovi_tool operation failed.
    case operationFailed(String)
    /// Input file doesn't contain Dolby Vision metadata.
    case noDolbyVision
    /// The requested DV profile conversion is not supported.
    case unsupportedConversion(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "dovi_tool binary not found. Install dovi_tool or specify its location in Settings."
        case .operationFailed(let detail):
            return "dovi_tool failed: \(detail)"
        case .noDolbyVision:
            return "Input file does not contain Dolby Vision metadata."
        case .unsupportedConversion(let detail):
            return "Unsupported Dolby Vision conversion: \(detail)"
        }
    }
}

// MARK: - DoviProfile

/// Dolby Vision profiles for RPU generation and conversion.
public enum DoviProfile: Int, Sendable, CaseIterable {
    /// Profile 5 — IPTPQc2 single-layer, used in streaming (Netflix, Disney+).
    case profile5 = 5

    /// Profile 7 — MEL/FEL dual-layer, used on UHD Blu-ray.
    /// Can be converted to Profile 8.1 for single-layer compatibility.
    case profile7 = 7

    /// Profile 8.1 — HDR10 base + DV enhancement RPU, single-layer.
    /// Most common streaming profile. Compatible with non-DV players as HDR10.
    case profile8_1 = 81

    /// Profile 8.4 — HLG base + DV enhancement RPU, single-layer.
    /// Used for HLG-to-DV conversion. Compatible with HLG players as fallback.
    case profile8_4 = 84

    public var displayName: String {
        switch self {
        case .profile5: return "Profile 5 (IPTPQc2)"
        case .profile7: return "Profile 7 (MEL/FEL)"
        case .profile8_1: return "Profile 8.1 (HDR10 base)"
        case .profile8_4: return "Profile 8.4 (HLG base)"
        }
    }

    /// The dovi_tool mode value for this profile.
    public var modeValue: Int {
        switch self {
        case .profile5: return 0
        case .profile7: return 1
        case .profile8_1: return 2
        case .profile8_4: return 4
        }
    }
}

// MARK: - DoviToolWrapper

/// Wrapper for the `dovi_tool` command-line utility for Dolby Vision RPU handling.
///
/// dovi_tool is used for:
/// - Extracting DV RPU (Reference Processing Unit) metadata from HEVC streams
/// - Converting between DV profiles (e.g., Profile 7 → Profile 8.1)
/// - Injecting RPU metadata into an HEVC stream after re-encoding
/// - Generating DV RPU from HDR10+ or HLG content
///
/// This wrapper coordinates dovi_tool operations with FFmpeg encoding
/// to preserve Dolby Vision metadata through the transcode pipeline.
public final class DoviToolWrapper: @unchecked Sendable {

    // MARK: - Properties

    /// Path to the dovi_tool binary.
    private var binaryPath: String?

    /// Search paths for locating dovi_tool.
    private let searchPaths: [String] = [
        "/opt/homebrew/bin/dovi_tool",
        "/usr/local/bin/dovi_tool",
        "/usr/bin/dovi_tool",
    ]

    /// Lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Initialiser

    /// Create a DoviToolWrapper.
    ///
    /// - Parameter binaryPath: Optional explicit path to the dovi_tool binary.
    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath
    }

    // MARK: - Discovery

    /// Locate the dovi_tool binary on the system.
    ///
    /// Searches user-specified path, then Homebrew, then standard locations.
    ///
    /// - Returns: The path to dovi_tool, or nil if not found.
    public func locateBinary() -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let path = binaryPath, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                binaryPath = path
                return path
            }
        }

        // Try which(1) as fallback
        if let result = try? runCommand("/usr/bin/which", arguments: ["dovi_tool"]),
           !result.isEmpty,
           FileManager.default.isExecutableFile(atPath: result) {
            binaryPath = result
            return result
        }

        return nil
    }

    /// Whether dovi_tool is available on this system.
    public var isAvailable: Bool {
        locateBinary() != nil
    }

    // MARK: - RPU Extraction

    /// Extract the Dolby Vision RPU from an HEVC elementary stream or raw HEVC file.
    ///
    /// Runs: `dovi_tool extract-rpu -i input.hevc -o output.bin`
    ///
    /// - Parameters:
    ///   - inputPath: Path to the HEVC elementary stream (extracted from container).
    ///   - outputPath: Path where the RPU binary file will be written.
    /// - Throws: `DoviToolError` if extraction fails.
    public func extractRPU(inputPath: String, outputPath: String) async throws {
        guard let binary = locateBinary() else {
            throw DoviToolError.binaryNotFound
        }

        let result = try await runAsync(binary, arguments: [
            "extract-rpu",
            "-i", inputPath,
            "-o", outputPath
        ])

        if !result.success {
            throw DoviToolError.operationFailed(result.stderr)
        }
    }

    // MARK: - RPU Injection

    /// Inject a Dolby Vision RPU into an HEVC elementary stream.
    ///
    /// Runs: `dovi_tool inject-rpu -i input.hevc --rpu-in rpu.bin -o output.hevc`
    ///
    /// This is used after re-encoding HEVC to re-attach the original DV metadata.
    ///
    /// - Parameters:
    ///   - hevcPath: Path to the re-encoded HEVC elementary stream.
    ///   - rpuPath: Path to the RPU binary file (from extractRPU).
    ///   - outputPath: Path for the output HEVC stream with DV metadata.
    /// - Throws: `DoviToolError` if injection fails.
    public func injectRPU(hevcPath: String, rpuPath: String, outputPath: String) async throws {
        guard let binary = locateBinary() else {
            throw DoviToolError.binaryNotFound
        }

        let result = try await runAsync(binary, arguments: [
            "inject-rpu",
            "-i", hevcPath,
            "--rpu-in", rpuPath,
            "-o", outputPath
        ])

        if !result.success {
            throw DoviToolError.operationFailed(result.stderr)
        }
    }

    // MARK: - Profile Conversion

    /// Convert a Dolby Vision RPU between profiles.
    ///
    /// Common conversions:
    /// - Profile 7 → Profile 8.1 (dual-layer to single-layer for streaming compatibility)
    /// - Profile 5 → Profile 8.1 (for HDR10 fallback compatibility)
    ///
    /// Runs: `dovi_tool convert --discard -i input.hevc -o output.hevc`
    ///       or `dovi_tool convert -m <mode> -i input.rpu -o output.rpu`
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source RPU or HEVC stream.
    ///   - outputPath: Path for the converted output.
    ///   - targetProfile: The target DV profile.
    /// - Throws: `DoviToolError` if conversion fails.
    public func convertProfile(
        inputPath: String,
        outputPath: String,
        targetProfile: DoviProfile
    ) async throws {
        guard let binary = locateBinary() else {
            throw DoviToolError.binaryNotFound
        }

        var args = ["convert", "-m", "\(targetProfile.modeValue)"]

        // Profile 7 → 8.1 requires --discard to remove enhancement layer
        if targetProfile == .profile8_1 {
            args.append("--discard")
        }

        args.append(contentsOf: ["-i", inputPath, "-o", outputPath])

        let result = try await runAsync(binary, arguments: args)

        if !result.success {
            throw DoviToolError.operationFailed(result.stderr)
        }
    }

    // MARK: - RPU Generation (Phase 3.9)

    /// Generate a Dolby Vision RPU from HDR10 static metadata.
    ///
    /// Creates a Profile 8.1 RPU using the source's MaxCLL/MaxFALL/mastering
    /// display colour volume metadata. This is used for the HDR10+ → DV
    /// auto-conversion feature.
    ///
    /// Runs: `dovi_tool generate -o output.bin --hdr10plus-json metadata.json`
    ///       or with static values: `dovi_tool generate --min-lum 50 --max-lum 1000 ...`
    ///
    /// - Parameters:
    ///   - outputPath: Path for the generated RPU binary.
    ///   - maxCLL: Maximum Content Light Level in nits.
    ///   - maxFALL: Maximum Frame Average Light Level in nits.
    ///   - minLuminance: Display mastering minimum luminance (nits × 10000).
    ///   - maxLuminance: Display mastering maximum luminance (nits).
    /// - Throws: `DoviToolError` if generation fails.
    public func generateRPU(
        outputPath: String,
        maxCLL: Int? = nil,
        maxFALL: Int? = nil,
        minLuminance: Int? = nil,
        maxLuminance: Int? = nil
    ) async throws {
        guard let binary = locateBinary() else {
            throw DoviToolError.binaryNotFound
        }

        var args = ["generate", "-o", outputPath]

        if let maxL = maxLuminance {
            args.append(contentsOf: ["--max-lum", "\(maxL)"])
        }
        if let minL = minLuminance {
            args.append(contentsOf: ["--min-lum", "\(minL)"])
        }
        if let cll = maxCLL {
            args.append(contentsOf: ["--max-cll", "\(cll)"])
        }
        if let fall = maxFALL {
            args.append(contentsOf: ["--max-fall", "\(fall)"])
        }

        let result = try await runAsync(binary, arguments: args)

        if !result.success {
            throw DoviToolError.operationFailed(result.stderr)
        }
    }

    // MARK: - Info / Validation

    /// Get information about the Dolby Vision RPU in a file.
    ///
    /// Runs: `dovi_tool info -i input.hevc`
    ///
    /// - Parameter inputPath: Path to the HEVC stream or RPU file.
    /// - Returns: The dovi_tool info output string.
    public func info(inputPath: String) async throws -> String {
        guard let binary = locateBinary() else {
            throw DoviToolError.binaryNotFound
        }

        let result = try await runAsync(binary, arguments: [
            "info", "-i", inputPath
        ])

        if !result.success {
            throw DoviToolError.operationFailed(result.stderr)
        }

        return result.stdout
    }

    // MARK: - Private Helpers

    private struct CommandResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        var success: Bool { exitCode == 0 }
    }

    private func runAsync(_ path: String, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: path)
                    process.arguments = arguments

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let result = CommandResult(
                        stdout: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        exitCode: process.terminationStatus
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runCommand(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
