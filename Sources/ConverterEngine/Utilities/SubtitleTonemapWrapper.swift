// ============================================================================
// MeedyaConverter — SubtitleTonemapWrapper
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Wrapper for the `subtitle_tonemap` command-line utility
// (https://github.com/quietvoid/subtitle_tonemap) which tone-maps subtitle
// colours to match an HDR→SDR video conversion. Without this, burned-in
// subtitles on tone-mapped video appear with incorrect colours (washed-out
// or overly bright).
//
// Supported input subtitle formats: PGS (.sup), VobSub (.sub/.idx),
// ASS/SSA text subtitles with RGB colour tags. Output preserves the input
// format — the wrapper only rewrites the colour values.
//
// Follows the same pattern as DoviToolWrapper and HlgToolsWrapper:
//   - Binary discovery via search paths and `which(1)` fallback
//   - NSLock-guarded caching of the discovered path
//   - Async run via Process + pipes
//
// GitHub Issue #369 — Integrate subtitle_tonemap for HDR subtitle colour
// correction.
// ============================================================================

import Foundation

// MARK: - SubtitleTonemapError

/// Errors from subtitle_tonemap operations.
public enum SubtitleTonemapError: LocalizedError, Sendable {
    /// subtitle_tonemap binary was not found.
    case binaryNotFound
    /// subtitle_tonemap operation failed with the given stderr.
    case operationFailed(String)
    /// The provided subtitle format is not supported by subtitle_tonemap.
    case unsupportedFormat(String)
    /// The requested HDR source profile is not recognised.
    case unsupportedSourceProfile(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "subtitle_tonemap binary not found. Install subtitle_tonemap "
                 + "(https://github.com/quietvoid/subtitle_tonemap) or specify "
                 + "its location in Settings."
        case .operationFailed(let detail):
            return "subtitle_tonemap failed: \(detail)"
        case .unsupportedFormat(let format):
            return "Unsupported subtitle format: \(format). "
                 + "Supported: PGS (.sup), VobSub (.sub/.idx), ASS/SSA."
        case .unsupportedSourceProfile(let profile):
            return "Unsupported HDR source profile: \(profile). "
                 + "Supported: hdr10, hdr10plus, dolby_vision, hlg."
        }
    }
}

// MARK: - SubtitleHDRSourceProfile

/// HDR source profile used to select the correct tone-mapping curve.
public enum SubtitleHDRSourceProfile: String, Codable, Sendable, CaseIterable {
    /// HDR10 / PQ (SMPTE ST 2084).
    case hdr10 = "hdr10"
    /// HDR10+ with dynamic metadata.
    case hdr10Plus = "hdr10plus"
    /// Dolby Vision.
    case dolbyVision = "dolby_vision"
    /// Hybrid Log-Gamma (ARIB STD-B67).
    case hlg = "hlg"

    /// Display name for UI surfaces.
    public var displayName: String {
        switch self {
        case .hdr10: return "HDR10"
        case .hdr10Plus: return "HDR10+"
        case .dolbyVision: return "Dolby Vision"
        case .hlg: return "HLG"
        }
    }

    /// Command-line flag for subtitle_tonemap.
    public var cliFlag: String {
        "--\(rawValue.replacingOccurrences(of: "_", with: "-"))"
    }
}

// MARK: - SubtitleTonemapConfig

/// Configuration for a subtitle_tonemap invocation.
///
/// `Hashable` is included so this can be nested inside other Hashable
/// types (e.g. `EncodingProfile`) without breaking their auto-synthesis.
/// All stored properties are already Hashable (`String`-raw enum,
/// `Double`, `Bool`), so the conformance is synthesised for free.
public struct SubtitleTonemapConfig: Codable, Sendable, Hashable {
    /// HDR source profile.
    public var sourceProfile: SubtitleHDRSourceProfile
    /// Target SDR peak luminance in nits (typical: 100).
    public var targetLuminanceNits: Double
    /// Preserve the alpha channel on PGS subtitles (recommended: true).
    public var preserveAlpha: Bool

    public init(
        sourceProfile: SubtitleHDRSourceProfile = .hdr10,
        targetLuminanceNits: Double = 100.0,
        preserveAlpha: Bool = true
    ) {
        self.sourceProfile = sourceProfile
        self.targetLuminanceNits = targetLuminanceNits
        self.preserveAlpha = preserveAlpha
    }
}

// MARK: - SubtitleTonemapWrapper

/// Wrapper for the `subtitle_tonemap` command-line utility.
///
/// Typical invocation:
/// ```
/// subtitle_tonemap -i input.sup -o output.sup --hdr10 --target-nits 100
/// ```
public final class SubtitleTonemapWrapper: @unchecked Sendable {

    /// Path to the subtitle_tonemap binary (cached after discovery).
    private var binaryPath: String?

    /// Standard search locations for the binary.
    private let searchPaths: [String] = [
        "/opt/homebrew/bin/subtitle_tonemap",
        "/usr/local/bin/subtitle_tonemap",
        "/usr/bin/subtitle_tonemap",
    ]

    /// Lock for thread-safe access to `binaryPath`.
    private let lock = NSLock()

    /// Create a SubtitleTonemapWrapper.
    ///
    /// - Parameter binaryPath: Optional explicit path to the binary.
    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath
    }

    // MARK: Discovery

    /// Locate the subtitle_tonemap binary on the system.
    public func locateBinary() -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let path = binaryPath, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        for path in searchPaths where FileManager.default.isExecutableFile(atPath: path) {
            binaryPath = path
            return path
        }
        return nil
    }

    /// Whether subtitle_tonemap is available on this system.
    public var isAvailable: Bool {
        locateBinary() != nil
    }

    // MARK: Argument construction (pure, unit-testable)

    /// Builds the CLI arguments for a tone-map run. Exposed for unit tests
    /// and for the CLI `meedya-convert` subcommand that surfaces this feature.
    public static func buildArguments(
        inputPath: String,
        outputPath: String,
        config: SubtitleTonemapConfig
    ) -> [String] {
        var args: [String] = [
            "-i", inputPath,
            "-o", outputPath,
            config.sourceProfile.cliFlag,
            "--target-nits", String(format: "%.0f", config.targetLuminanceNits),
        ]
        if config.preserveAlpha {
            args.append("--preserve-alpha")
        }
        return args
    }

    /// Returns true when the given subtitle extension is supported by
    /// subtitle_tonemap. Text-only formats without colour (SRT, WebVTT plain)
    /// are rejected — there is nothing to tone-map.
    public static func isFormatSupported(fileExtension: String) -> Bool {
        let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let supported: Set<String> = ["sup", "sub", "idx", "ass", "ssa"]
        return supported.contains(ext)
    }

    // MARK: Execution

    /// Run subtitle_tonemap against an input subtitle file.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the HDR subtitle file.
    ///   - outputPath: Where to write the tone-mapped SDR subtitle.
    ///   - config: Tone-mapping configuration.
    public func toneMap(
        inputPath: String,
        outputPath: String,
        config: SubtitleTonemapConfig
    ) async throws {
        guard let binary = locateBinary() else {
            throw SubtitleTonemapError.binaryNotFound
        }
        let ext = (inputPath as NSString).pathExtension
        guard Self.isFormatSupported(fileExtension: ext) else {
            throw SubtitleTonemapError.unsupportedFormat(ext)
        }
        let result = try await runAsync(
            binary,
            arguments: Self.buildArguments(
                inputPath: inputPath,
                outputPath: outputPath,
                config: config
            )
        )
        if !result.success {
            throw SubtitleTonemapError.operationFailed(result.stderr)
        }
    }

    // MARK: Process helpers

    private struct CommandResult: Sendable {
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
}
