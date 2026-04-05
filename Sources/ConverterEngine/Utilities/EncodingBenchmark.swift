// ============================================================================
// MeedyaConverter — EncodingBenchmark (Issue #325)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - BenchmarkResult
// ---------------------------------------------------------------------------
/// The measured outcome of a single encoding speed benchmark run.
///
/// Each result captures the codec, preset, resolution, achieved frame rate,
/// wall-clock duration, and whether hardware acceleration was employed.
/// Results are `Identifiable` for SwiftUI list rendering and `Codable`
/// for persistence/export.
public struct BenchmarkResult: Identifiable, Codable, Sendable {

    /// Unique identifier for this result.
    public let id: UUID

    /// The FFmpeg encoder name used (e.g., "libx264", "libsvtav1").
    public let codec: String

    /// The encoder preset (e.g., "medium", "fast", "veryslow").
    public let preset: String

    /// The test resolution (e.g., "1920x1080", "3840x2160").
    public let resolution: String

    /// Achieved encoding speed in frames per second.
    public let fps: Double

    /// Wall-clock time taken for the benchmark in seconds.
    public let duration: TimeInterval

    /// Whether hardware acceleration (VideoToolbox, NVENC, etc.) was used.
    public let hardwareAccelerated: Bool

    /// Memberwise initializer.
    public init(
        id: UUID = UUID(),
        codec: String,
        preset: String,
        resolution: String,
        fps: Double,
        duration: TimeInterval,
        hardwareAccelerated: Bool
    ) {
        self.id = id
        self.codec = codec
        self.preset = preset
        self.resolution = resolution
        self.fps = fps
        self.duration = duration
        self.hardwareAccelerated = hardwareAccelerated
    }
}

// ---------------------------------------------------------------------------
// MARK: - EncodingBenchmark
// ---------------------------------------------------------------------------
/// Builds FFmpeg arguments for synthetic encoding speed benchmarks and
/// parses the resulting output to extract performance metrics.
///
/// Benchmarks use FFmpeg's built-in `testsrc2` test pattern generator so
/// that no real media file is required. The encoded output is discarded
/// (`-f null -`) to measure pure encoding throughput without disk I/O
/// bottlenecks.
///
/// Usage:
/// ```swift
/// let args = EncodingBenchmark.buildBenchmarkArguments(
///     codec: .h264,
///     preset: "medium",
///     resolution: "1920x1080",
///     duration: 10.0,
///     hwAccel: false
/// )
/// // Run via FFmpegProcessController, capture stderr...
/// if let result = EncodingBenchmark.parseBenchmarkOutput(stderr) {
///     print("Achieved \(result.fps) fps")
/// }
/// ```
public struct EncodingBenchmark: Sendable {

    // MARK: - Argument Builder

    /// Builds FFmpeg arguments for a synthetic encoding benchmark.
    ///
    /// The generated command creates a test pattern of the specified
    /// resolution and duration, encodes it with the given codec/preset,
    /// and discards the output. This isolates encoder performance from
    /// disk or network I/O.
    ///
    /// - Parameters:
    ///   - codec: The ``VideoCodec`` to benchmark.
    ///   - preset: The encoder preset (e.g., "medium", "fast"). The
    ///     meaning is codec-specific.
    ///   - resolution: Output resolution as "WIDTHxHEIGHT" (e.g., "1920x1080").
    ///   - duration: Duration of the test pattern in seconds (default 10).
    ///   - hwAccel: If `true`, uses the hardware-accelerated encoder variant
    ///     (e.g., `h264_videotoolbox` instead of `libx264`).
    /// - Returns: Array of arguments suitable for `Process.arguments`.
    public static func buildBenchmarkArguments(
        codec: VideoCodec,
        preset: String,
        resolution: String,
        duration: Double = 10.0,
        hwAccel: Bool = false
    ) -> [String] {
        // Determine encoder name based on codec and hardware acceleration.
        let encoderName: String
        if hwAccel {
            encoderName = codec.videoToolboxEncoder ?? codec.ffmpegEncoder ?? "libx264"
        } else {
            encoderName = codec.ffmpegEncoder ?? "libx264"
        }

        // Parse resolution for the test source.
        let size = resolution.contains("x") ? resolution : "1920x1080"

        // Extract frame rate from resolution or default to 30.
        let frameRate = 30

        var args: [String] = [
            "-f", "lavfi",
            "-i", "testsrc2=duration=\(Int(duration)):size=\(size):rate=\(frameRate)",
            "-c:v", encoderName
        ]

        // Add preset flag. VideoToolbox encoders don't support -preset;
        // software encoders (libx264, libx265, libsvtav1) do.
        if !hwAccel {
            args += ["-preset", preset]
        }

        // Discard output — benchmark measures encoding speed only.
        args += ["-f", "null", "-"]

        return args
    }

    // MARK: - Output Parser

    /// Parses FFmpeg stderr output to extract the encoding speed as a
    /// ``BenchmarkResult``.
    ///
    /// FFmpeg reports encoding progress on stderr with lines like:
    /// ```
    /// frame=  300 fps= 45 q=28.0 Lsize=       0kB time=00:00:10.00 ...
    /// ```
    /// This method extracts the final `fps` value from the last progress
    /// line and the wall-clock `time` to construct a result.
    ///
    /// - Parameter output: The raw stderr text from FFmpeg.
    /// - Returns: A ``BenchmarkResult`` if parsing succeeds, or `nil` if
    ///   the output does not contain recognisable progress information.
    public static func parseBenchmarkOutput(_ output: String) -> BenchmarkResult? {
        // Find the last line containing fps information.
        let lines = output.components(separatedBy: .newlines)
        var lastFps: Double?
        var lastTime: String?

        // Pattern: fps=XX or fps= XX (with optional spaces)
        let fpsPattern = #"fps=\s*(\d+\.?\d*)"#
        let timePattern = #"time=(\d{2}:\d{2}:\d{2}\.\d{2})"#

        guard let fpsRegex = try? NSRegularExpression(pattern: fpsPattern),
              let timeRegex = try? NSRegularExpression(pattern: timePattern) else {
            return nil
        }

        for line in lines {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            if let fpsMatch = fpsRegex.firstMatch(in: line, range: range) {
                let fpsStr = nsLine.substring(with: fpsMatch.range(at: 1))
                lastFps = Double(fpsStr)
            }

            if let timeMatch = timeRegex.firstMatch(in: line, range: range) {
                lastTime = nsLine.substring(with: timeMatch.range(at: 1))
            }
        }

        guard let fps = lastFps else { return nil }

        // Parse wall-clock duration from the time field.
        var duration: TimeInterval = 0
        if let timeStr = lastTime {
            let parts = timeStr.split(separator: ":")
            if parts.count == 3 {
                let hours = Double(parts[0]) ?? 0
                let mins = Double(parts[1]) ?? 0
                let secs = Double(parts[2]) ?? 0
                duration = hours * 3600 + mins * 60 + secs
            }
        }

        return BenchmarkResult(
            codec: "unknown",
            preset: "unknown",
            resolution: "unknown",
            fps: fps,
            duration: duration,
            hardwareAccelerated: false
        )
    }

    // MARK: - Standard Benchmark Suite

    /// A predefined set of codec/preset/resolution combinations that
    /// exercises common encoding scenarios.
    ///
    /// The suite covers H.264, H.265, and AV1 at standard resolutions
    /// with representative presets. It is used by ``BenchmarkView`` to
    /// offer a one-click "Run All Benchmarks" experience.
    public static let standardBenchmarks: [(codec: VideoCodec, preset: String, resolution: String)] = [
        // H.264 benchmarks
        (.h264, "ultrafast", "1920x1080"),
        (.h264, "medium", "1920x1080"),
        (.h264, "slow", "1920x1080"),
        (.h264, "medium", "3840x2160"),

        // H.265 benchmarks
        (.h265, "ultrafast", "1920x1080"),
        (.h265, "medium", "1920x1080"),
        (.h265, "slow", "1920x1080"),
        (.h265, "medium", "3840x2160"),

        // AV1 benchmarks
        (.av1, "8", "1920x1080"),
        (.av1, "6", "1920x1080"),
        (.av1, "4", "1920x1080"),
    ]
}

// ---------------------------------------------------------------------------
// MARK: - VideoCodec Extension (VideoToolbox Encoder)
// ---------------------------------------------------------------------------
/// Extends ``VideoCodec`` with a property to retrieve the VideoToolbox
/// hardware encoder name for benchmark hardware-acceleration support.
extension VideoCodec {

    /// The VideoToolbox hardware encoder name, or `nil` if the codec
    /// does not support hardware acceleration on macOS.
    var videoToolboxEncoder: String? {
        switch self {
        case .h264: return "h264_videotoolbox"
        case .h265: return "hevc_videotoolbox"
        case .prores: return "prores_videotoolbox"
        default: return nil
        }
    }
}
