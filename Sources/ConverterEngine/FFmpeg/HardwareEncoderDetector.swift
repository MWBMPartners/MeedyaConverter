// ============================================================================
// MeedyaConverter — HardwareEncoderDetector
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - HardwareEncoderInfo

/// Describes an available hardware encoder discovered on the system.
public struct HardwareEncoderInfo: Sendable, Equatable {
    /// The FFmpeg encoder name (e.g., "h264_videotoolbox").
    public let encoderName: String

    /// The human-readable display name.
    public let displayName: String

    /// The video codec this encoder handles.
    public let codec: VideoCodec

    /// The hardware acceleration API used.
    public let api: HardwareAPI

    public init(encoderName: String, displayName: String, codec: VideoCodec, api: HardwareAPI) {
        self.encoderName = encoderName
        self.displayName = displayName
        self.codec = codec
        self.api = api
    }
}

// MARK: - HardwareAPI

/// Hardware acceleration APIs supported by FFmpeg.
public enum HardwareAPI: String, Sendable, CaseIterable {
    /// Apple VideoToolbox (macOS/iOS).
    case videoToolbox = "videotoolbox"
    /// NVIDIA NVENC (Windows/Linux).
    case nvenc
    /// Intel Quick Sync Video (Windows/Linux/macOS).
    case qsv
    /// AMD Advanced Media Framework (Windows).
    case amf
    /// VA-API (Linux).
    case vaapi

    public var displayName: String {
        switch self {
        case .videoToolbox: return "VideoToolbox (Apple)"
        case .nvenc: return "NVENC (NVIDIA)"
        case .qsv: return "Quick Sync (Intel)"
        case .amf: return "AMF (AMD)"
        case .vaapi: return "VA-API (Linux)"
        }
    }
}

// MARK: - HardwareEncoderDetector

/// Detects available hardware video encoders by querying FFmpeg.
///
/// On macOS, this checks for VideoToolbox-based encoders. The detector
/// runs `ffmpeg -encoders` and parses the output for hardware-accelerated
/// encoder names (e.g., `h264_videotoolbox`, `hevc_videotoolbox`).
///
/// Results are cached for the session since hardware capabilities don't
/// change at runtime.
public final class HardwareEncoderDetector: @unchecked Sendable {

    // MARK: - Properties

    /// Cached detection results.
    private var cachedEncoders: [HardwareEncoderInfo]?

    /// Lock for thread-safe cache access.
    private let lock = NSLock()

    /// Known hardware encoder mappings: FFmpeg encoder name → (codec, API, display name).
    private static let knownHardwareEncoders: [(String, VideoCodec, HardwareAPI, String)] = [
        // VideoToolbox (macOS)
        ("h264_videotoolbox", .h264, .videoToolbox, "H.264 (VideoToolbox)"),
        ("hevc_videotoolbox", .h265, .videoToolbox, "H.265/HEVC (VideoToolbox)"),
        ("prores_videotoolbox", .prores, .videoToolbox, "ProRes (VideoToolbox)"),
        ("av1_videotoolbox", .av1, .videoToolbox, "AV1 (VideoToolbox)"),

        // NVENC (NVIDIA GPU)
        ("h264_nvenc", .h264, .nvenc, "H.264 (NVENC)"),
        ("hevc_nvenc", .h265, .nvenc, "H.265/HEVC (NVENC)"),
        ("av1_nvenc", .av1, .nvenc, "AV1 (NVENC)"),

        // QSV (Intel)
        ("h264_qsv", .h264, .qsv, "H.264 (Quick Sync)"),
        ("hevc_qsv", .h265, .qsv, "H.265/HEVC (Quick Sync)"),
        ("av1_qsv", .av1, .qsv, "AV1 (Quick Sync)"),
        ("vp9_qsv", .vp9, .qsv, "VP9 (Quick Sync)"),

        // AMF (AMD)
        ("h264_amf", .h264, .amf, "H.264 (AMF)"),
        ("hevc_amf", .h265, .amf, "H.265/HEVC (AMF)"),
        ("av1_amf", .av1, .amf, "AV1 (AMF)"),

        // VA-API (Linux)
        ("h264_vaapi", .h264, .vaapi, "H.264 (VA-API)"),
        ("hevc_vaapi", .h265, .vaapi, "H.265/HEVC (VA-API)"),
        ("av1_vaapi", .av1, .vaapi, "AV1 (VA-API)"),
        ("vp9_vaapi", .vp9, .vaapi, "VP9 (VA-API)"),
    ]

    // MARK: - Initialiser

    public init() {}

    // MARK: - Detection

    /// Detect all available hardware encoders by querying FFmpeg.
    ///
    /// Runs `ffmpeg -encoders` and cross-references the output against
    /// known hardware encoder names. Results are cached after the first call.
    ///
    /// - Parameter ffmpegPath: Path to the FFmpeg binary.
    /// - Returns: Array of available hardware encoders on this system.
    public func detectEncoders(ffmpegPath: String) -> [HardwareEncoderInfo] {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedEncoders {
            return cached
        }

        let encoders = performDetection(ffmpegPath: ffmpegPath)
        cachedEncoders = encoders
        return encoders
    }

    /// Check whether a specific hardware encoder is available.
    ///
    /// - Parameters:
    ///   - codec: The video codec to check.
    ///   - api: The hardware API (e.g., `.videoToolbox`).
    ///   - ffmpegPath: Path to the FFmpeg binary.
    /// - Returns: The encoder info if available, nil otherwise.
    public func encoder(for codec: VideoCodec, api: HardwareAPI, ffmpegPath: String) -> HardwareEncoderInfo? {
        let available = detectEncoders(ffmpegPath: ffmpegPath)
        return available.first { $0.codec == codec && $0.api == api }
    }

    /// Get all available hardware encoders for a specific codec.
    ///
    /// - Parameters:
    ///   - codec: The video codec.
    ///   - ffmpegPath: Path to the FFmpeg binary.
    /// - Returns: All hardware encoders that can encode the given codec.
    public func encoders(for codec: VideoCodec, ffmpegPath: String) -> [HardwareEncoderInfo] {
        let available = detectEncoders(ffmpegPath: ffmpegPath)
        return available.filter { $0.codec == codec }
    }

    /// Whether any hardware encoder is available on this system.
    public func hasHardwareSupport(ffmpegPath: String) -> Bool {
        !detectEncoders(ffmpegPath: ffmpegPath).isEmpty
    }

    /// Clear the cached results, forcing re-detection on next call.
    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedEncoders = nil
    }

    // MARK: - Private

    private func performDetection(ffmpegPath: String) -> [HardwareEncoderInfo] {
        guard let output = runFFmpegEncoders(ffmpegPath: ffmpegPath) else {
            return []
        }

        // Parse FFmpeg -encoders output. Each encoder line looks like:
        //  V..... h264_videotoolbox    VideoToolbox H.264 Encoder (codec h264)
        let lines = output.split(separator: "\n").map(String.init)
        let encoderNames = Set(lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Encoder lines start with capability flags like "V....."
            guard trimmed.count > 7,
                  let first = trimmed.first,
                  (first == "V" || first == "A" || first == "S") else { return nil }
            // Extract the encoder name (second whitespace-separated token)
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return nil }
            return String(parts[1])
        })

        // Match against known hardware encoders
        return Self.knownHardwareEncoders.compactMap { (name, codec, api, displayName) in
            guard encoderNames.contains(name) else { return nil }
            return HardwareEncoderInfo(
                encoderName: name,
                displayName: displayName,
                codec: codec,
                api: api
            )
        }
    }

    /// Run `ffmpeg -encoders` and capture stdout.
    private func runFFmpegEncoders(ffmpegPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-encoders", "-hide_banner"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
