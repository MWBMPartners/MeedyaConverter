// ============================================================================
// MeedyaConverter — HlgToolsWrapper
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - HlgToolsError

/// Errors from hlg-tools operations.
public enum HlgToolsError: LocalizedError, Sendable {
    /// hlg-tools binary was not found.
    case binaryNotFound
    /// hlg-tools operation failed.
    case operationFailed(String)
    /// Source does not contain PQ (ST 2084) transfer.
    case noPQTransfer

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "hlg-tools binary not found. Install hlg-tools (https://github.com/wswartzendruber/hlg-tools) or specify its location in Settings."
        case .operationFailed(let detail):
            return "hlg-tools failed: \(detail)"
        case .noPQTransfer:
            return "Source does not contain PQ (SMPTE ST 2084) transfer function."
        }
    }
}

// MARK: - HlgToolsWrapper

/// Wrapper for the `hlg-tools` command-line utilities for PQ→HLG HDR conversion.
///
/// hlg-tools (https://github.com/wswartzendruber/hlg-tools) provides high-quality
/// conversion from PQ (SMPTE ST 2084) to HLG (ARIB STD-B67) transfer function.
/// The primary binary used is `pq2hlg` which performs pixel-level transfer
/// function conversion.
///
/// MeedyaConverter uses hlg-tools as an optional enhancement over FFmpeg's
/// built-in zscale filter for PQ→HLG conversion. When hlg-tools is not
/// available, the engine falls back to FFmpeg's zscale filter chain.
///
/// ## Usage
/// ```swift
/// let hlgTools = HlgToolsWrapper()
/// if hlgTools.isAvailable {
///     // Use hlg-tools for higher quality conversion
///     try await hlgTools.convertPQToHLG(inputPath: "source.y4m", outputPath: "output.y4m")
/// }
/// ```
public final class HlgToolsWrapper: @unchecked Sendable {

    // MARK: - Properties

    /// Path to the pq2hlg binary.
    private var binaryPath: String?

    /// Search paths for locating hlg-tools binaries.
    private let searchPaths: [String] = [
        "/opt/homebrew/bin/pq2hlg",
        "/usr/local/bin/pq2hlg",
        "/usr/bin/pq2hlg",
    ]

    /// Lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Initialiser

    /// Create an HlgToolsWrapper.
    ///
    /// - Parameter binaryPath: Optional explicit path to the pq2hlg binary.
    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath
    }

    // MARK: - Discovery

    /// Locate the pq2hlg binary on the system.
    ///
    /// Searches user-specified path, then Homebrew, then standard locations.
    ///
    /// - Returns: The path to pq2hlg, or nil if not found.
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
        if let result = try? runCommand("/usr/bin/which", arguments: ["pq2hlg"]),
           !result.isEmpty,
           FileManager.default.isExecutableFile(atPath: result) {
            binaryPath = result
            return result
        }

        return nil
    }

    /// Whether hlg-tools (pq2hlg) is available on this system.
    public var isAvailable: Bool {
        locateBinary() != nil
    }

    // MARK: - PQ → HLG Conversion

    /// Convert a raw video file from PQ transfer to HLG transfer.
    ///
    /// This operates on raw pixel data (Y4M format). The typical workflow is:
    /// 1. FFmpeg decodes source to Y4M pipe
    /// 2. pq2hlg converts PQ pixels to HLG
    /// 3. FFmpeg encodes the HLG output
    ///
    /// Runs: `pq2hlg -i input.y4m -o output.y4m --max-cll <nits>`
    ///
    /// - Parameters:
    ///   - inputPath: Path to the PQ-encoded raw video (Y4M format).
    ///   - outputPath: Path for the HLG-converted output.
    ///   - maxCLL: Maximum Content Light Level in nits (for tone curve).
    /// - Throws: `HlgToolsError` if conversion fails.
    public func convertPQToHLG(
        inputPath: String,
        outputPath: String,
        maxCLL: Int? = nil
    ) async throws {
        guard let binary = locateBinary() else {
            throw HlgToolsError.binaryNotFound
        }

        var args = [
            "-i", inputPath,
            "-o", outputPath,
        ]

        if let cll = maxCLL {
            args.append(contentsOf: ["--max-cll", "\(cll)"])
        }

        let result = try await runAsync(binary, arguments: args)

        if !result.success {
            throw HlgToolsError.operationFailed(result.stderr)
        }
    }

    // MARK: - Version Info

    /// Get the version string of the installed hlg-tools.
    ///
    /// - Returns: Version string, or nil if not available.
    public func version() -> String? {
        guard let binary = locateBinary() else { return nil }

        guard let result = try? runCommand(binary, arguments: ["--version"]) else {
            return nil
        }

        return result.isEmpty ? nil : result
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
