// ============================================================================
// MeedyaConverter — HDR10PlusToolWrapper
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - HDR10PlusToolError

/// Errors from hdr10plus_tool operations.
public enum HDR10PlusToolError: LocalizedError, Sendable {
    /// hdr10plus_tool binary was not found.
    case binaryNotFound
    /// hdr10plus_tool operation failed.
    case operationFailed(String)
    /// Input file doesn't contain HDR10+ metadata.
    case noHDR10Plus

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "hdr10plus_tool binary not found. Install hdr10plus_tool or specify its location in Settings."
        case .operationFailed(let detail):
            return "hdr10plus_tool failed: \(detail)"
        case .noHDR10Plus:
            return "Input file does not contain HDR10+ metadata."
        }
    }
}

// MARK: - HDR10PlusToolWrapper

/// Wrapper for the `hdr10plus_tool` command-line utility for HDR10+ metadata handling.
///
/// hdr10plus_tool is used for:
/// - Extracting HDR10+ dynamic metadata from HEVC streams
/// - Injecting HDR10+ metadata into an HEVC stream after re-encoding
/// - Inspecting HDR10+ metadata summaries
/// - Validating HDR10+ JSON metadata files
///
/// This wrapper coordinates hdr10plus_tool operations with FFmpeg encoding
/// and dovi_tool to enable dual dynamic HDR (DV + HDR10+) pipelines.
///
/// Phase 3.9 / Issue #368
public final class HDR10PlusToolWrapper: @unchecked Sendable {

    // MARK: - Properties

    /// Path to the hdr10plus_tool binary.
    private var binaryPath: String?

    /// Search paths for locating hdr10plus_tool.
    private let searchPaths: [String] = [
        "/opt/homebrew/bin/hdr10plus_tool",
        "/usr/local/bin/hdr10plus_tool",
        "/usr/bin/hdr10plus_tool",
    ]

    /// Lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Initialiser

    /// Create an HDR10PlusToolWrapper.
    ///
    /// - Parameter binaryPath: Optional explicit path to the hdr10plus_tool binary.
    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath
    }

    // MARK: - Discovery

    /// Locate the hdr10plus_tool binary on the system.
    ///
    /// Searches user-specified path, then Homebrew, then standard locations.
    ///
    /// - Returns: The path to hdr10plus_tool, or nil if not found.
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
        if let result = locateViaWhich(),
           FileManager.default.isExecutableFile(atPath: result) {
            binaryPath = result
            return result
        }

        return nil
    }

    /// Whether hdr10plus_tool is available on this system.
    public var isAvailable: Bool {
        locateBinary() != nil
    }

    /// Detect the installed hdr10plus_tool version.
    ///
    /// Runs: `hdr10plus_tool --version`
    ///
    /// - Returns: The version string, or nil if detection fails.
    public var version: String? {
        guard let binary = locateBinary() else { return nil }

        guard let result = try? runCommand(binary, arguments: ["--version"]),
              !result.isEmpty else {
            return nil
        }

        // hdr10plus_tool --version typically outputs "hdr10plus_tool x.y.z"
        // Extract just the version number.
        let components = result.split(separator: " ")
        if components.count >= 2 {
            return String(components.last!)
        }
        return result
    }

    // MARK: - Metadata Extraction

    /// Extract HDR10+ dynamic metadata from an HEVC elementary stream.
    ///
    /// Runs: `hdr10plus_tool extract -i input.hevc -o metadata.json`
    ///
    /// - Parameters:
    ///   - inputPath: Path to the HEVC elementary stream.
    ///   - outputPath: Path where the HDR10+ JSON metadata will be written.
    /// - Throws: `HDR10PlusToolError` if extraction fails.
    public func extractMetadata(inputPath: String, outputPath: String) async throws {
        guard let binary = locateBinary() else {
            throw HDR10PlusToolError.binaryNotFound
        }

        let result = try await runAsync(binary, arguments: [
            "extract",
            "-i", inputPath,
            "-o", outputPath,
        ])

        if !result.success {
            if result.stderr.lowercased().contains("no hdr10+") ||
               result.stderr.lowercased().contains("no dynamic metadata") {
                throw HDR10PlusToolError.noHDR10Plus
            }
            throw HDR10PlusToolError.operationFailed(result.stderr)
        }
    }

    // MARK: - Metadata Injection

    /// Inject HDR10+ dynamic metadata into an HEVC elementary stream.
    ///
    /// Runs: `hdr10plus_tool inject -i input.hevc -j metadata.json -o output.hevc`
    ///
    /// This is used after re-encoding HEVC to attach HDR10+ metadata,
    /// or during dual dynamic HDR pipeline to add HDR10+ alongside DV RPU.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the HEVC elementary stream.
    ///   - metadataPath: Path to the HDR10+ JSON metadata file.
    ///   - outputPath: Path for the output HEVC stream with HDR10+ metadata.
    /// - Throws: `HDR10PlusToolError` if injection fails.
    public func injectMetadata(
        inputPath: String,
        metadataPath: String,
        outputPath: String
    ) async throws {
        guard let binary = locateBinary() else {
            throw HDR10PlusToolError.binaryNotFound
        }

        let result = try await runAsync(binary, arguments: [
            "inject",
            "-i", inputPath,
            "-j", metadataPath,
            "-o", outputPath,
        ])

        if !result.success {
            throw HDR10PlusToolError.operationFailed(result.stderr)
        }
    }

    // MARK: - Info

    /// Get information about HDR10+ metadata in a file.
    ///
    /// Runs: `hdr10plus_tool info -i input.hevc`
    ///
    /// - Parameter inputPath: Path to the HEVC stream.
    /// - Returns: The HDR10+ metadata summary string.
    /// - Throws: `HDR10PlusToolError` if the operation fails.
    public func getInfo(inputPath: String) async throws -> String {
        guard let binary = locateBinary() else {
            throw HDR10PlusToolError.binaryNotFound
        }

        let result = try await runAsync(binary, arguments: [
            "info",
            "-i", inputPath,
        ])

        if !result.success {
            throw HDR10PlusToolError.operationFailed(result.stderr)
        }

        return result.stdout
    }

    // MARK: - Validation

    /// Validate an HDR10+ JSON metadata file.
    ///
    /// Runs: `hdr10plus_tool validate -j metadata.json`
    ///
    /// - Parameter metadataPath: Path to the HDR10+ JSON metadata file.
    /// - Returns: `true` if the metadata is valid.
    /// - Throws: `HDR10PlusToolError` if the operation fails.
    public func validateMetadata(metadataPath: String) async throws -> Bool {
        guard let binary = locateBinary() else {
            throw HDR10PlusToolError.binaryNotFound
        }

        let result = try await runAsync(binary, arguments: [
            "validate",
            "-j", metadataPath,
        ])

        return result.success
    }

    // MARK: - Argument Builders

    /// Build command-line arguments for HDR10+ metadata extraction.
    ///
    /// Returns the argument array for use in external process coordination
    /// (e.g., pipeline orchestration where the caller manages execution).
    ///
    /// - Parameters:
    ///   - inputPath: Path to the HEVC elementary stream.
    ///   - outputPath: Path where the HDR10+ JSON metadata will be written.
    /// - Returns: Argument array for hdr10plus_tool extract.
    public func buildExtractArguments(inputPath: String, outputPath: String) -> [String] {
        return ["extract", "-i", inputPath, "-o", outputPath]
    }

    /// Build command-line arguments for HDR10+ metadata injection.
    ///
    /// Returns the argument array for use in external process coordination
    /// (e.g., dual dynamic HDR pipeline where inject follows DV RPU processing).
    ///
    /// - Parameters:
    ///   - inputPath: Path to the HEVC elementary stream.
    ///   - metadataPath: Path to the HDR10+ JSON metadata file.
    ///   - outputPath: Path for the output HEVC stream with HDR10+ metadata.
    /// - Returns: Argument array for hdr10plus_tool inject.
    public func buildInjectArguments(
        inputPath: String,
        metadataPath: String,
        outputPath: String
    ) -> [String] {
        return ["inject", "-i", inputPath, "-j", metadataPath, "-o", outputPath]
    }

    // MARK: - Private Helpers

    /// Result of a command-line process execution.
    private struct CommandResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        var success: Bool { exitCode == 0 }
    }

    /// Run a command asynchronously and capture its output.
    ///
    /// Dispatches the process to a background queue and returns the result
    /// via a checked continuation. Matches the pattern used by DoviToolWrapper.
    ///
    /// - Parameters:
    ///   - path: Path to the executable binary.
    ///   - arguments: Command-line arguments.
    /// - Returns: A `CommandResult` with stdout, stderr, and exit code.
    /// - Throws: Process launch errors.
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
                        stdout: String(data: stdoutData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        exitCode: process.terminationStatus
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Run a command synchronously and return its trimmed stdout.
    ///
    /// Used for lightweight operations like version detection.
    ///
    /// - Parameters:
    ///   - path: Path to the executable binary.
    ///   - arguments: Command-line arguments.
    /// - Returns: Trimmed stdout string.
    /// - Throws: Process launch errors.
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
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Locate hdr10plus_tool via the `which` command as a last-resort fallback.
    ///
    /// - Returns: The path to hdr10plus_tool if found, or nil.
    private func locateViaWhich() -> String? {
        guard let result = try? runCommand("/usr/bin/which", arguments: ["hdr10plus_tool"]),
              !result.isEmpty else {
            return nil
        }
        return result
    }
}
