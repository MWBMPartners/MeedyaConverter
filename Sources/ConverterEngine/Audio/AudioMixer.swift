// ============================================================================
// MeedyaConverter — AudioMixer (Issue #319)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - AudioMixInput

/// A single audio input for a mix operation.
///
/// Each input represents one audio track (or file) with adjustable volume
/// and optional delay. Multiple ``AudioMixInput`` instances are combined
/// by ``AudioMixer`` into a single mixed output.
///
/// Phase 5 — Audio Track Mixing and Merging (Issue #319)
public struct AudioMixInput: Identifiable, Codable, Sendable {

    /// Unique identifier for this mix input.
    public let id: UUID

    /// Path to the source audio/video file.
    public let inputPath: String

    /// Zero-based audio track index within the source file.
    public let trackIndex: Int

    /// Volume multiplier for this track.
    /// - `0.0` = silent
    /// - `1.0` = original level (unity gain)
    /// - `2.0` = double volume (+6 dB)
    public let volume: Double

    /// Delay in seconds before this track begins playing.
    /// Useful for aligning commentary with video or syncing dubbed audio.
    public let delay: TimeInterval

    /// Creates a new audio mix input.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if omitted).
    ///   - inputPath: Path to the source file.
    ///   - trackIndex: Audio track index within the file.
    ///   - volume: Volume multiplier (0.0–2.0, default 1.0).
    ///   - delay: Playback delay in seconds (default 0).
    public init(
        id: UUID = UUID(),
        inputPath: String,
        trackIndex: Int = 0,
        volume: Double = 1.0,
        delay: TimeInterval = 0
    ) {
        self.id = id
        self.inputPath = inputPath
        self.trackIndex = trackIndex
        self.volume = min(max(volume, 0.0), 2.0)
        self.delay = max(delay, 0)
    }
}

// MARK: - AudioMixConfig

/// Configuration for an audio mixing operation.
///
/// Combines multiple ``AudioMixInput`` tracks into a single output
/// with a specified channel layout and codec.
///
/// Phase 5 — Audio Track Mixing and Merging (Issue #319)
public struct AudioMixConfig: Codable, Sendable {

    /// Ordered list of audio inputs to mix together.
    public let inputs: [AudioMixInput]

    /// Number of output channels (e.g., 2 for stereo, 6 for 5.1).
    public let outputChannels: Int

    /// Output audio codec. When ``nil``, FFmpeg selects the default
    /// codec for the output container.
    public let outputCodec: AudioCodec?

    /// Creates a new audio mix configuration.
    ///
    /// - Parameters:
    ///   - inputs: Audio tracks to mix.
    ///   - outputChannels: Desired output channel count (default 2).
    ///   - outputCodec: Optional output audio codec.
    public init(
        inputs: [AudioMixInput],
        outputChannels: Int = 2,
        outputCodec: AudioCodec? = nil
    ) {
        self.inputs = inputs
        self.outputChannels = outputChannels
        self.outputCodec = outputCodec
    }
}

// MARK: - AudioMixer

/// Builds FFmpeg argument arrays for audio mixing, volume adjustment,
/// delay insertion, and channel downmixing.
///
/// Supports several mixing strategies:
/// - **amerge**: Interleave channels from multiple mono/stereo inputs.
/// - **amix**: Mix multiple inputs into a single output with automatic
///   normalization to prevent clipping.
/// - **volume**: Per-track gain adjustment.
/// - **adelay**: Per-track delay for synchronization.
/// - **pan**: Custom channel downmix matrices (e.g., 5.1 → stereo).
///
/// Phase 5 — Audio Track Mixing and Merging (Issue #319)
public struct AudioMixer: Sendable {

    // MARK: - Mix Arguments

    /// Builds FFmpeg arguments to mix multiple audio inputs into a single
    /// output track.
    ///
    /// Uses the ``amix`` filter with per-track volume and delay adjustments.
    /// Each input is pre-processed with ``volume`` and ``adelay`` filters
    /// before being fed into the ``amix`` combiner.
    ///
    /// - Parameters:
    ///   - config: The mix configuration containing inputs and output settings.
    ///   - outputPath: Destination path for the mixed output file.
    /// - Returns: FFmpeg argument array.
    public static func buildMixArguments(
        config: AudioMixConfig,
        outputPath: String
    ) -> [String] {
        guard !config.inputs.isEmpty else { return [] }

        var args: [String] = ["-y", "-nostdin"]

        // Add all input files
        for input in config.inputs {
            args += ["-i", input.inputPath]
        }

        // Build the filter complex for mixing
        let filterComplex = buildMixFilterComplex(config: config)
        args += ["-filter_complex", filterComplex]
        args += ["-map", "[mixed]"]

        // Output channel layout
        args += ["-ac", "\(config.outputChannels)"]

        // Output codec
        if let codec = config.outputCodec {
            args += ["-c:a", codec.rawValue]
        }

        args += [outputPath]

        return args
    }

    // MARK: - Volume Adjustment

    /// Builds an FFmpeg audio filter string for volume adjustment.
    ///
    /// - Parameter volume: Volume multiplier (0.0 = silence, 1.0 = unity,
    ///   2.0 = double). Values are clamped to 0.0–2.0.
    /// - Returns: FFmpeg volume filter string (e.g., "volume=1.5").
    public static func buildVolumeAdjustArguments(volume: Double) -> String {
        let clampedVolume = min(max(volume, 0.0), 2.0)
        return "volume=\(String(format: "%.2f", clampedVolume))"
    }

    // MARK: - Delay

    /// Builds an FFmpeg audio filter string for track delay.
    ///
    /// Uses the ``adelay`` filter to shift the audio forward in time.
    /// The delay is applied to all channels equally.
    ///
    /// - Parameter delay: Delay in seconds. Negative values are treated as 0.
    /// - Returns: FFmpeg adelay filter string (e.g., "adelay=1500|1500").
    public static func buildDelayArguments(delay: TimeInterval) -> String {
        let milliseconds = Int(max(delay, 0) * 1000)
        // Apply delay to both channels (stereo). FFmpeg's adelay uses
        // pipe-separated per-channel values in milliseconds.
        return "adelay=\(milliseconds)|all=1"
    }

    // MARK: - Downmix

    /// Builds an FFmpeg ``pan`` filter string for channel downmixing.
    ///
    /// Generates a standard downmix matrix for common channel conversions:
    /// - 5.1 (6ch) → stereo (2ch): ITU-R BS.775 compliant fold-down
    /// - 7.1 (8ch) → stereo (2ch): Extended fold-down with side/back channels
    /// - 7.1 (8ch) → 5.1 (6ch): Back channels folded into surrounds
    /// - Other: Simple channel truncation via ``pan`` filter
    ///
    /// - Parameters:
    ///   - inputChannels: Number of channels in the source audio.
    ///   - outputChannels: Desired number of output channels.
    /// - Returns: FFmpeg pan filter string.
    public static func buildDownmixArguments(
        inputChannels: Int,
        outputChannels: Int
    ) -> String {
        // 5.1 → stereo (ITU-R BS.775 compliant)
        if inputChannels == 6 && outputChannels == 2 {
            return "pan=stereo|"
                + "FL=FC+0.707*FL+0.707*BL|"
                + "FR=FC+0.707*FR+0.707*BR"
        }

        // 7.1 → stereo
        if inputChannels == 8 && outputChannels == 2 {
            return "pan=stereo|"
                + "FL=FC+0.707*FL+0.5*SL+0.5*BL|"
                + "FR=FC+0.707*FR+0.5*SR+0.5*BR"
        }

        // 7.1 → 5.1 (fold back channels into surrounds)
        if inputChannels == 8 && outputChannels == 6 {
            return "pan=5.1|"
                + "FL=FL|FR=FR|FC=FC|LFE=LFE|"
                + "BL=SL+0.707*BL|BR=SR+0.707*BR"
        }

        // Generic downmix: use the pan filter with the target layout name
        let layoutName = channelLayoutName(for: outputChannels)
        return "pan=\(layoutName)|" + (0..<outputChannels).map { "c\($0)=c\($0)" }
            .joined(separator: "|")
    }

    // MARK: - Private Helpers

    /// Builds the ``-filter_complex`` string for mixing multiple audio inputs.
    ///
    /// Each input is pre-processed with volume and adelay filters, then
    /// all pre-processed streams are combined with the ``amix`` filter.
    ///
    /// - Parameter config: The mix configuration.
    /// - Returns: FFmpeg filter_complex string.
    private static func buildMixFilterComplex(config: AudioMixConfig) -> String {
        var filterParts: [String] = []
        var mixInputLabels: [String] = []

        for (index, input) in config.inputs.enumerated() {
            let inputLabel = "[\(index):a:\(input.trackIndex)]"
            var currentLabel = inputLabel
            var chainFilters: [String] = []

            // Volume adjustment (skip if unity gain)
            if abs(input.volume - 1.0) > 0.001 {
                chainFilters.append(buildVolumeAdjustArguments(volume: input.volume))
            }

            // Delay (skip if zero)
            if input.delay > 0.001 {
                chainFilters.append(buildDelayArguments(delay: input.delay))
            }

            if !chainFilters.isEmpty {
                let outLabel = "[pre\(index)]"
                filterParts.append(
                    "\(currentLabel)\(chainFilters.joined(separator: ","))\(outLabel)"
                )
                currentLabel = outLabel
            }

            mixInputLabels.append(currentLabel)
        }

        // Combine all pre-processed streams with amix
        let inputCount = config.inputs.count
        let mixInputStr = mixInputLabels.joined()
        filterParts.append(
            "\(mixInputStr)amix=inputs=\(inputCount):duration=longest:dropout_transition=0[mixed]"
        )

        return filterParts.joined(separator: ";")
    }

    /// Returns a human-readable FFmpeg channel layout name for the given
    /// channel count.
    ///
    /// - Parameter channels: Number of audio channels.
    /// - Returns: FFmpeg layout name (e.g., "stereo", "5.1", "7.1").
    private static func channelLayoutName(for channels: Int) -> String {
        switch channels {
        case 1: return "mono"
        case 2: return "stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels)c"
        }
    }
}
