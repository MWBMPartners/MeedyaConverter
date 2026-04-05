// ============================================================================
// MeedyaConverter — VideoStabilizer (Issue #323)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - StabilizationConfig

/// Configuration for the two-pass ``vid.stab`` video stabilization pipeline.
///
/// The ``vid.stab`` library operates in two passes:
/// 1. **Analysis** (``vidstabdetect``): Scans the input for camera motion
///    and writes transform data to a file.
/// 2. **Stabilization** (``vidstabtransform``): Applies the inverse
///    transforms to counteract camera shake.
///
/// Parameter ranges follow the ``vid.stab`` library documentation:
/// - https://github.com/georgmartius/vid.stab
///
/// Phase 10 — Video Stabilization (Issue #323)
public struct StabilizationConfig: Codable, Sendable {

    /// Shakiness of the video content (1–10).
    /// Higher values widen the motion search radius for the analysis pass.
    /// - `1` = very stable footage (tripod with slight drift)
    /// - `10` = extremely shaky footage (handheld action camera)
    public let shakiness: Int

    /// Accuracy of the motion estimation (1–15).
    /// Higher values improve detection quality at the cost of speed.
    /// - `1` = fastest, least accurate
    /// - `15` = slowest, most accurate
    public let accuracy: Int

    /// Step size for the motion search in pixels.
    /// Smaller values give finer motion estimation but are slower.
    /// Typical range: 1–32. Default: 6.
    public let stepSize: Int

    /// Maximum zoom percentage to apply for filling black borders.
    /// - `0` = no zoom (black borders may appear)
    /// - Positive values zoom in to hide border artefacts
    public let zoom: Double

    /// Optimal zoom strategy:
    /// - `0` = use static zoom (the ``zoom`` value)
    /// - `1` = optimal static zoom (no borders visible)
    /// - `2` = adaptive zoom (zoom changes per frame to minimise borders)
    public let optzoom: Int

    /// Number of frames used for low-pass filtering of camera motion.
    /// Higher values produce smoother (more stabilised) output but may
    /// introduce a floating/dreamy look.
    /// Typical range: 1–100. Default: 10.
    public let smoothing: Int

    /// Creates a new stabilization configuration.
    ///
    /// - Parameters:
    ///   - shakiness: Motion search radius (1–10, default 5).
    ///   - accuracy: Motion estimation accuracy (1–15, default 15).
    ///   - stepSize: Search step size in pixels (default 6).
    ///   - zoom: Maximum zoom percentage (default 0).
    ///   - optzoom: Zoom strategy (0–2, default 1).
    ///   - smoothing: Low-pass filter window size (default 10).
    public init(
        shakiness: Int = 5,
        accuracy: Int = 15,
        stepSize: Int = 6,
        zoom: Double = 0,
        optzoom: Int = 1,
        smoothing: Int = 10
    ) {
        self.shakiness = min(max(shakiness, 1), 10)
        self.accuracy = min(max(accuracy, 1), 15)
        self.stepSize = max(stepSize, 1)
        self.zoom = zoom
        self.optzoom = min(max(optzoom, 0), 2)
        self.smoothing = max(smoothing, 1)
    }
}

// MARK: - VideoStabilizer

/// Builds FFmpeg argument arrays for two-pass video stabilization using
/// the ``vid.stab`` library (``vidstabdetect`` + ``vidstabtransform``).
///
/// The typical workflow:
/// 1. Run pass 1 with ``buildAnalysisArguments`` to generate a transforms
///    file (``*.trf``).
/// 2. Run pass 2 with ``buildStabilizeArguments`` using the transforms
///    file to produce the stabilized output.
///
/// Pre-built presets are available for common use cases:
/// - ``.light``: Tripod footage with minor drift.
/// - ``.medium``: Handheld footage with moderate shake.
/// - ``.heavy``: Action camera or extreme handheld shake.
///
/// Phase 10 — Video Stabilization (Issue #323)
public struct VideoStabilizer: Sendable {

    // MARK: - Presets

    /// Light stabilization for tripod footage with minor drift.
    ///
    /// Low shakiness, minimal zoom, gentle smoothing. Preserves most
    /// of the original camera motion while removing micro-jitter.
    public static let light = StabilizationConfig(
        shakiness: 3,
        accuracy: 9,
        stepSize: 6,
        zoom: 0,
        optzoom: 0,
        smoothing: 5
    )

    /// Medium stabilization for handheld footage with moderate shake.
    ///
    /// Balanced settings suitable for most handheld shooting scenarios.
    /// Applies adaptive zoom to minimise black borders.
    public static let medium = StabilizationConfig(
        shakiness: 5,
        accuracy: 15,
        stepSize: 6,
        zoom: 0,
        optzoom: 1,
        smoothing: 10
    )

    /// Heavy stabilization for extremely shaky footage.
    ///
    /// Maximum shakiness detection, aggressive smoothing, and adaptive
    /// zoom to handle action cameras, running, or vehicle-mounted shots.
    public static let heavy = StabilizationConfig(
        shakiness: 10,
        accuracy: 15,
        stepSize: 4,
        zoom: 5,
        optzoom: 2,
        smoothing: 30
    )

    // MARK: - Pass 1: Analysis

    /// Builds FFmpeg arguments for the analysis pass (pass 1) of video
    /// stabilization.
    ///
    /// Runs the ``vidstabdetect`` video filter to analyse camera motion
    /// and write transform data to a ``.trf`` file. No output video is
    /// produced — the output is sent to ``/dev/null``.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source video file.
    ///   - transformsPath: Path to write the transforms data file (e.g.,
    ///     ``"/tmp/transforms.trf"``).
    ///   - config: Stabilization configuration controlling shakiness and
    ///     accuracy.
    /// - Returns: FFmpeg argument array for the analysis pass.
    public static func buildAnalysisArguments(
        inputPath: String,
        transformsPath: String,
        config: StabilizationConfig
    ) -> [String] {
        var args: [String] = ["-y", "-nostdin"]

        // Input video
        args += ["-i", inputPath]

        // Build the vidstabdetect filter string
        let detectFilter = [
            "vidstabdetect",
            "shakiness=\(config.shakiness)",
            "accuracy=\(config.accuracy)",
            "stepsize=\(config.stepSize)",
            "result='\(transformsPath)'"
        ].joined(separator: "=")
            // vidstabdetect uses colon-separated key=value pairs
            .replacingOccurrences(of: "detect=", with: "detect=")

        // Properly formatted: vidstabdetect=shakiness=N:accuracy=N:...
        let filterString = "vidstabdetect="
            + "shakiness=\(config.shakiness)"
            + ":accuracy=\(config.accuracy)"
            + ":stepsize=\(config.stepSize)"
            + ":result='\(transformsPath)'"

        args += ["-vf", filterString]

        // No output file needed — analysis only. Send to null.
        args += ["-f", "null", "-"]

        return args
    }

    // MARK: - Pass 2: Stabilization

    /// Builds FFmpeg arguments for the stabilization pass (pass 2) that
    /// applies the transforms computed in pass 1.
    ///
    /// Reads the transform data from the ``.trf`` file and applies the
    /// ``vidstabtransform`` filter with the configured zoom and smoothing
    /// parameters to produce the stabilized output video.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source video file (same as pass 1).
    ///   - outputPath: Destination path for the stabilized output.
    ///   - transformsPath: Path to the transforms data file from pass 1.
    ///   - config: Stabilization configuration controlling zoom and smoothing.
    /// - Returns: FFmpeg argument array for the stabilization pass.
    public static func buildStabilizeArguments(
        inputPath: String,
        outputPath: String,
        transformsPath: String,
        config: StabilizationConfig
    ) -> [String] {
        var args: [String] = ["-y", "-nostdin"]

        // Input video
        args += ["-i", inputPath]

        // Build the vidstabtransform filter string
        let filterString = "vidstabtransform="
            + "input='\(transformsPath)'"
            + ":zoom=\(String(format: "%.1f", config.zoom))"
            + ":optzoom=\(config.optzoom)"
            + ":smoothing=\(config.smoothing)"

        // Add unsharp mask after stabilization to compensate for
        // interpolation softness introduced by the transform.
        let combinedFilter = filterString + ",unsharp=5:5:0.8:3:3:0.4"

        args += ["-vf", combinedFilter]

        // Copy audio untouched
        args += ["-c:a", "copy"]

        args += [outputPath]

        return args
    }
}
