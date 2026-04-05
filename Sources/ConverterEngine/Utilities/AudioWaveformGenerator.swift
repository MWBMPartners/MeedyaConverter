// ============================================================================
// MeedyaConverter — AudioWaveformGenerator
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - WaveformData

/// Holds normalised amplitude samples extracted from an audio stream.
///
/// The data is used by ``AudioWaveformView`` to render a visual waveform
/// representation of the audio. Samples are normalised to the range -1...1
/// and represent peak amplitudes at the requested sample rate.
public struct WaveformData: Sendable {

    // MARK: - Properties

    /// Normalised amplitude samples in the range -1...1.
    ///
    /// Each sample represents the peak amplitude for a time window
    /// determined by `duration / samples.count`. Positive and negative
    /// values represent the waveform's upper and lower halves respectively.
    public let samples: [Float]

    /// Total duration of the audio in seconds.
    public let duration: TimeInterval

    /// Number of audio channels in the source.
    public let channels: Int

    /// The effective sample rate of the waveform data (samples per second).
    public let sampleRate: Int

    /// The absolute peak amplitude found in the source audio (0...1).
    public let peakAmplitude: Float

    /// Whether any sample reached or exceeded 0.99, indicating potential clipping.
    ///
    /// When `true`, the waveform view highlights clipped regions in red
    /// to warn the user of possible audio quality issues.
    public let hasClipping: Bool

    // MARK: - Initialiser

    /// Create a new waveform data container.
    ///
    /// - Parameters:
    ///   - samples: Normalised amplitude samples (-1...1).
    ///   - duration: Total audio duration in seconds.
    ///   - channels: Number of source audio channels.
    ///   - sampleRate: Samples per second in this waveform data.
    ///   - peakAmplitude: Absolute peak amplitude (0...1).
    ///   - hasClipping: Whether clipping was detected.
    public init(
        samples: [Float],
        duration: TimeInterval,
        channels: Int,
        sampleRate: Int,
        peakAmplitude: Float,
        hasClipping: Bool
    ) {
        self.samples = samples
        self.duration = duration
        self.channels = channels
        self.sampleRate = sampleRate
        self.peakAmplitude = peakAmplitude
        self.hasClipping = hasClipping
    }
}

// MARK: - AudioWaveformGenerator

/// Generates waveform data from audio files using FFmpeg.
///
/// The generator works in two phases:
/// 1. **Extract** — uses FFmpeg to export raw 32-bit float PCM data at a
///    reduced sample rate (default 8000 Hz) for efficient waveform rendering.
/// 2. **Parse** — reads the raw PCM file and computes normalised amplitude
///    samples suitable for visual rendering.
///
/// The caller is responsible for executing the FFmpeg process; this struct
/// only builds the argument list and parses the result.
public struct AudioWaveformGenerator: Sendable {

    // MARK: - Constants

    /// Default waveform sample rate in Hz.
    ///
    /// 8000 Hz provides approximately 8 samples per millisecond, which is
    /// more than sufficient for visual waveform rendering even when zoomed in.
    public static let defaultSampleRate: Int = 8000

    // MARK: - FFmpeg Argument Building

    /// Build FFmpeg arguments to extract raw PCM data from an audio file.
    ///
    /// The output is a raw 32-bit floating-point little-endian mono PCM file.
    /// This format is easy to parse: each sample is a 4-byte IEEE 754 float.
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source audio/video file.
    ///   - outputPath: Absolute path for the raw PCM output file.
    ///   - samplesPerSecond: The target sample rate for the waveform data.
    ///     Lower values produce smaller files and faster rendering.
    /// - Returns: Array of FFmpeg arguments (the caller prepends the `ffmpeg` executable).
    public static func buildWaveformArguments(
        inputPath: String,
        outputPath: String,
        samplesPerSecond: Int = defaultSampleRate
    ) -> [String] {
        return [
            "-i", inputPath,
            "-ac", "1",                 // downmix to mono
            "-f", "f32le",              // raw 32-bit float little-endian
            "-ar", "\(samplesPerSecond)", // target sample rate
            "-y",                       // overwrite output
            outputPath
        ]
    }

    // MARK: - Waveform Parsing

    /// Parse raw 32-bit float PCM data into ``WaveformData``.
    ///
    /// Reads the binary file at `rawPCMPath`, interprets each 4-byte chunk
    /// as an IEEE 754 float, then computes peak amplitude and clipping
    /// statistics.
    ///
    /// - Parameters:
    ///   - rawPCMPath: Absolute path to the raw PCM file produced by FFmpeg.
    ///   - duration: Total duration of the source audio in seconds.
    ///   - channels: Number of channels in the original audio (for metadata only;
    ///     the PCM data is already downmixed to mono).
    ///   - sampleRate: The sample rate used when extracting the PCM data.
    /// - Returns: Parsed ``WaveformData``, or `nil` if the file cannot be read.
    public static func parseWaveformData(
        from rawPCMPath: String,
        duration: TimeInterval,
        channels: Int = 1,
        sampleRate: Int = defaultSampleRate
    ) -> WaveformData? {
        guard let data = FileManager.default.contents(atPath: rawPCMPath) else {
            return nil
        }

        // Each sample is a 32-bit (4-byte) float
        let bytesPerSample = MemoryLayout<Float>.size
        let sampleCount = data.count / bytesPerSample

        guard sampleCount > 0 else {
            return nil
        }

        // Read all float samples from the raw data
        var samples = [Float](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            for i in 0..<sampleCount {
                samples[i] = floatBuffer[i]
            }
        }

        // Compute peak amplitude and clipping detection
        var peakAmplitude: Float = 0
        var hasClipping = false
        let clippingThreshold: Float = 0.99

        for sample in samples {
            let absSample = abs(sample)
            if absSample > peakAmplitude {
                peakAmplitude = absSample
            }
            if absSample >= clippingThreshold {
                hasClipping = true
            }
        }

        return WaveformData(
            samples: samples,
            duration: duration,
            channels: channels,
            sampleRate: sampleRate,
            peakAmplitude: peakAmplitude,
            hasClipping: hasClipping
        )
    }

    // MARK: - Downsampling

    /// Downsample waveform data for display at a given zoom level.
    ///
    /// When rendering a waveform in a view that is narrower than the sample count,
    /// this method reduces the data by computing peak values per display column.
    ///
    /// - Parameters:
    ///   - waveform: The source waveform data.
    ///   - targetSampleCount: The desired number of output samples (typically
    ///     equal to the view's point width).
    /// - Returns: A new array of peak amplitude values sized to `targetSampleCount`.
    public static func downsample(
        _ waveform: WaveformData,
        targetSampleCount: Int
    ) -> [Float] {
        let source = waveform.samples
        guard targetSampleCount > 0, !source.isEmpty else { return [] }

        if targetSampleCount >= source.count {
            return source
        }

        let samplesPerBucket = Double(source.count) / Double(targetSampleCount)
        var result = [Float](repeating: 0, count: targetSampleCount)

        for i in 0..<targetSampleCount {
            let startIndex = Int(Double(i) * samplesPerBucket)
            let endIndex = min(Int(Double(i + 1) * samplesPerBucket), source.count)

            var peak: Float = 0
            for j in startIndex..<endIndex {
                let absSample = abs(source[j])
                if absSample > peak {
                    peak = absSample
                }
            }
            result[i] = peak
        }

        return result
    }
}
