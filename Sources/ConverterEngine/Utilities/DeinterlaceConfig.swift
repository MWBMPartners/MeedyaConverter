// ============================================================================
// MeedyaConverter — DeinterlaceConfig (Issue #324)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DeinterlaceFilter

/// FFmpeg deinterlacing filter algorithms, ordered from fastest to
/// highest quality.
///
/// Each filter offers a different trade-off between processing speed and
/// visual quality:
/// - ``yadif``: The fastest general-purpose deinterlacer.
/// - ``bwdif``: Bob Weaver — better quality than yadif with moderate cost.
/// - ``w3fdif``: Weston 3-field — high quality, slower processing.
/// - ``nnedi``: Neural network — best quality, significantly slower.
///
/// Phase 10 — Deinterlacing Presets (Issue #324)
public enum DeinterlaceFilter: String, Codable, Sendable, CaseIterable {

    /// Yet Another DeInterlacing Filter — the standard FFmpeg deinterlacer.
    /// Fast with acceptable quality for most content.
    case yadif

    /// Bob Weaver Deinterlacing Filter — improved quality over yadif.
    /// Uses a larger temporal window for better motion compensation.
    case bwdif

    /// Weston Three Field Deinterlacing Filter — high-quality deinterlacer.
    /// Uses three fields for interpolation, producing smoother results.
    case w3fdif

    /// Neural Network Edge Directed Interpolation — best quality.
    /// Uses a trained neural network for field interpolation. Significantly
    /// slower but produces the cleanest output with minimal artefacts.
    case nnedi

    /// Human-readable display name for the filter.
    public var displayName: String {
        switch self {
        case .yadif:  return "Yadif (Fast)"
        case .bwdif:  return "Bwdif (Quality)"
        case .w3fdif: return "W3FDIF (High Quality)"
        case .nnedi:  return "NNEDI (Best Quality)"
        }
    }

    /// Brief description of the filter's characteristics.
    public var descriptionText: String {
        switch self {
        case .yadif:
            return "Standard deinterlacer. Fast with acceptable quality for most content."
        case .bwdif:
            return "Bob Weaver filter. Better quality than yadif with moderate performance cost."
        case .w3fdif:
            return "Weston 3-field filter. High quality using three fields for interpolation."
        case .nnedi:
            return "Neural network interpolation. Best quality but significantly slower."
        }
    }
}

// MARK: - FieldOrder

/// Field dominance (parity) for interlaced video.
///
/// Determines which field is displayed first in each interlaced frame.
/// Incorrect field order causes visible combing and judder artefacts.
public enum FieldOrder: String, Codable, Sendable, CaseIterable {

    /// Automatic detection from the source stream metadata.
    /// FFmpeg reads the field order from the container or codec headers.
    case auto

    /// Top Field First — the most common field order for PAL content
    /// and many professional HD formats.
    case tff

    /// Bottom Field First — common in NTSC DV and some consumer formats.
    case bff

    /// Human-readable display name for the field order.
    public var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .tff:  return "Top Field First"
        case .bff:  return "Bottom Field First"
        }
    }
}

// MARK: - DeinterlaceConfig

/// Complete configuration for a deinterlacing operation.
///
/// Encapsulates the filter algorithm, output mode, field parity, and
/// selective-deinterlace flag. Use ``DeinterlacePresets`` for pre-built
/// configurations optimised for speed or quality.
///
/// Phase 10 — Deinterlacing Presets (Issue #324)
public struct DeinterlaceConfig: Codable, Sendable {

    /// The deinterlacing filter algorithm to use.
    public let filter: DeinterlaceFilter

    /// Output mode:
    /// - `0` = output one frame per frame (same frame rate as input).
    /// - `1` = output one frame per field (doubles the frame rate).
    public let mode: Int

    /// Field parity (dominance) for the input video.
    public let parity: FieldOrder

    /// Selective deinterlace flag:
    /// - `0` = deinterlace all frames unconditionally.
    /// - `1` = only deinterlace frames marked as interlaced in metadata.
    public let deint: Int

    /// Creates a new deinterlace configuration.
    ///
    /// - Parameters:
    ///   - filter: Deinterlacing algorithm (default ``.yadif``).
    ///   - mode: Output mode — 0 for frame, 1 for field (default 0).
    ///   - parity: Field order (default ``.auto``).
    ///   - deint: Selective deinterlace — 0 for all, 1 for interlaced only (default 0).
    public init(
        filter: DeinterlaceFilter = .yadif,
        mode: Int = 0,
        parity: FieldOrder = .auto,
        deint: Int = 0
    ) {
        self.filter = filter
        self.mode = min(max(mode, 0), 1)
        self.parity = parity
        self.deint = min(max(deint, 0), 1)
    }
}

// MARK: - DeinterlacePresets

/// Pre-built deinterlace configurations and filter string generation.
///
/// Provides three preset tiers:
/// - ``.fast``: Yadif mode 0 — fastest, acceptable quality.
/// - ``.quality``: Bwdif mode 1 (field output) — good balance.
/// - ``.best``: NNEDI — best quality, slowest.
///
/// Also includes ``detectInterlaced(probeOutput:)`` to parse FFprobe
/// output for interlace flags, enabling automatic deinterlace triggering.
///
/// Phase 10 — Deinterlacing Presets (Issue #324)
public struct DeinterlacePresets: Sendable {

    // MARK: - Presets

    /// Fast preset — yadif with frame output and auto parity.
    ///
    /// Best for batch processing or when speed is prioritised over quality.
    /// Produces one output frame per input frame at the same frame rate.
    public static let fast = DeinterlaceConfig(
        filter: .yadif,
        mode: 0,
        parity: .auto,
        deint: 0
    )

    /// Quality preset — bwdif with field output and auto parity.
    ///
    /// Doubles the frame rate by outputting one frame per field. Produces
    /// smoother motion at the cost of higher bitrate and processing time.
    public static let quality = DeinterlaceConfig(
        filter: .bwdif,
        mode: 1,
        parity: .auto,
        deint: 0
    )

    /// Best preset — nnedi with frame output and auto parity.
    ///
    /// Uses neural network interpolation for the highest quality output.
    /// Significantly slower but produces the cleanest results with minimal
    /// combing or interpolation artefacts.
    public static let best = DeinterlaceConfig(
        filter: .nnedi,
        mode: 0,
        parity: .auto,
        deint: 0
    )

    // MARK: - Filter String Generation

    /// Builds the FFmpeg video filter string for the given deinterlace
    /// configuration.
    ///
    /// Examples:
    /// - ``yadif=mode=0:parity=-1:deint=0``
    /// - ``bwdif=mode=1:parity=-1:deint=0``
    /// - ``nnedi=weights='nnedi3_weights.bin'``
    ///
    /// - Parameter config: The deinterlace configuration.
    /// - Returns: FFmpeg ``-vf`` filter string.
    public static func buildFilterString(config: DeinterlaceConfig) -> String {
        switch config.filter {
        case .yadif:
            return buildYadifString(config: config)
        case .bwdif:
            return buildBwdifString(config: config)
        case .w3fdif:
            return buildW3fdifString(config: config)
        case .nnedi:
            return buildNnediString(config: config)
        }
    }

    // MARK: - Interlace Detection

    /// Analyses FFprobe output text to determine if the source video
    /// is interlaced.
    ///
    /// Checks for common interlace indicators in FFprobe's JSON or
    /// text output:
    /// - ``field_order`` values: ``tt``, ``bb``, ``tb``, ``bt``
    /// - ``interlaced_frame`` flag in frame analysis
    /// - ``codec_field_order`` in stream info
    ///
    /// - Parameter probeOutput: Raw text output from FFprobe.
    /// - Returns: ``true`` if interlace markers are detected.
    public static func detectInterlaced(probeOutput: String) -> Bool {
        let lowered = probeOutput.lowercased()

        // Check for field_order indicators (top/bottom field first)
        let fieldOrderPatterns = ["field_order=tt", "field_order=bb",
                                  "field_order=tb", "field_order=bt",
                                  "\"field_order\": \"tt\"",
                                  "\"field_order\": \"bb\"",
                                  "\"field_order\": \"tb\"",
                                  "\"field_order\": \"bt\""]
        for pattern in fieldOrderPatterns {
            if lowered.contains(pattern) {
                return true
            }
        }

        // Check for interlaced_frame flag
        if lowered.contains("interlaced_frame=1") ||
           lowered.contains("\"interlaced_frame\": \"1\"") {
            return true
        }

        // Check for codec_field_order
        if lowered.contains("codec_field_order=tt") ||
           lowered.contains("codec_field_order=bb") {
            return true
        }

        return false
    }

    // MARK: - Private Filter Builders

    /// Builds the yadif filter string with mode, parity, and deint parameters.
    private static func buildYadifString(config: DeinterlaceConfig) -> String {
        let parityValue = parityIntValue(config.parity)
        return "yadif=mode=\(config.mode):parity=\(parityValue):deint=\(config.deint)"
    }

    /// Builds the bwdif filter string with mode, parity, and deint parameters.
    private static func buildBwdifString(config: DeinterlaceConfig) -> String {
        let parityValue = parityIntValue(config.parity)
        return "bwdif=mode=\(config.mode):parity=\(parityValue):deint=\(config.deint)"
    }

    /// Builds the w3fdif filter string with mode and deint parameters.
    private static func buildW3fdifString(config: DeinterlaceConfig) -> String {
        // w3fdif uses "filter" param (0=simple, 1=complex) instead of parity.
        // We map mode 0 → simple, mode 1 → complex for quality scaling.
        let filterType = config.mode == 0 ? 0 : 1
        return "w3fdif=filter=\(filterType):deint=\(config.deint)"
    }

    /// Builds the nnedi filter string.
    ///
    /// NNEDI requires a weights file. FFmpeg ships ``nnedi3_weights.bin``
    /// and the filter auto-locates it when installed properly.
    private static func buildNnediString(config: DeinterlaceConfig) -> String {
        let parityValue = parityIntValue(config.parity)
        // field: -1 = auto, 0 = BFF output, 1 = TFF output
        // nsize and nns control quality vs. speed
        return "nnedi=weights='nnedi3_weights.bin':field=\(parityValue):nsize=s32x6:nns=n128"
    }

    /// Converts a ``FieldOrder`` to the integer value expected by FFmpeg
    /// filter parameters.
    ///
    /// - Parameter parity: The field order.
    /// - Returns: FFmpeg parity integer: -1 (auto), 0 (TFF), 1 (BFF).
    private static func parityIntValue(_ parity: FieldOrder) -> Int {
        switch parity {
        case .auto: return -1
        case .tff:  return 0
        case .bff:  return 1
        }
    }
}
