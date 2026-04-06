// ============================================================================
// MeedyaConverter — VoiceIsolator (Issue #293)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - IsolationMethod

/// The technique used for voice/dialogue isolation.
///
/// Each method has different trade-offs in quality, processing speed,
/// and availability. FFmpeg-based methods work everywhere; ML-based
/// methods require specific macOS frameworks.
///
/// Phase 11 — Voice Isolation / Dialogue Extraction (Issue #293)
public enum IsolationMethod: String, Codable, Sendable, CaseIterable {

    /// Basic FFmpeg bandpass filter targeting speech frequencies (300Hz–3400Hz).
    /// Fast and universally available, but limited quality — non-speech
    /// content within the speech band is preserved.
    case ffmpegHighpass

    /// On-device ML sound classification (SoundAnalysis framework).
    /// Provides better separation but requires macOS with Core ML support.
    case visionSoundAnalysis

    /// FFmpeg ``afftdn`` (FFT-based denoising) for spectral subtraction.
    /// Good for reducing steady-state background noise while preserving speech.
    case spectralSubtraction

    /// Human-readable display name for UI presentation.
    public var displayName: String {
        switch self {
        case .ffmpegHighpass:
            return "FFmpeg Bandpass (Basic)"
        case .visionSoundAnalysis:
            return "ML Sound Analysis"
        case .spectralSubtraction:
            return "Spectral Subtraction"
        }
    }
}

// MARK: - VoiceIsolationConfig

/// Configuration for voice isolation and dialogue extraction operations.
///
/// Controls the isolation method, sensitivity threshold, and optional
/// output audio format override.
///
/// Phase 11 — Voice Isolation / Dialogue Extraction (Issue #293)
public struct VoiceIsolationConfig: Codable, Sendable {

    /// The isolation technique to use.
    public var method: IsolationMethod

    /// Sensitivity of the isolation algorithm (0.0–1.0).
    ///
    /// Higher values are more aggressive about removing non-speech content:
    /// - `0.0` = minimal processing (preserve more of the original)
    /// - `0.5` = balanced (default)
    /// - `1.0` = maximum isolation (may clip some speech edges)
    ///
    /// For ``ffmpegHighpass``, this controls the bandwidth of the bandpass filter.
    /// For ``spectralSubtraction``, this controls the noise reduction strength.
    public var sensitivity: Double

    /// Optional output audio codec override.
    /// When `nil`, the output uses the same codec as the input.
    public var outputFormat: String?

    /// Creates a new voice isolation configuration.
    ///
    /// - Parameters:
    ///   - method: The isolation technique (default: `.ffmpegHighpass`).
    ///   - sensitivity: Isolation aggressiveness, 0.0–1.0 (default: 0.5).
    ///   - outputFormat: Optional output codec name (e.g. ``"aac"``, ``"flac"``).
    public init(
        method: IsolationMethod = .ffmpegHighpass,
        sensitivity: Double = 0.5,
        outputFormat: String? = nil
    ) {
        self.method = method
        self.sensitivity = max(0, min(1, sensitivity))
        self.outputFormat = outputFormat
    }
}

// MARK: - VoiceIsolator

/// Builds FFmpeg argument arrays for voice isolation and dialogue extraction.
///
/// Provides three complementary approaches to separating speech from
/// other audio content:
///
/// 1. **Bandpass filtering** — simple highpass + lowpass to isolate the
///    speech frequency range (300Hz–3400Hz), with optional compression.
///
/// 2. **Spectral subtraction** — FFmpeg's ``afftdn`` filter for removing
///    steady-state background noise while preserving speech transients.
///
/// 3. **Centre channel extraction** — extracts the centre channel from
///    surround sound mixes, where dialogue is typically placed in
///    film and television content.
///
/// Usage:
/// ```swift
/// let config = VoiceIsolationConfig(method: .ffmpegHighpass, sensitivity: 0.7)
/// let args = VoiceIsolator.buildFFmpegIsolationArguments(
///     inputPath: "/input.mkv",
///     outputPath: "/output_voice.wav",
///     config: config
/// )
/// // Execute via Process with FFmpeg
/// ```
///
/// Phase 11 — Voice Isolation / Dialogue Extraction (Issue #293)
public struct VoiceIsolator: Sendable {

    // MARK: - FFmpeg Bandpass Isolation

    /// Builds FFmpeg arguments for bandpass-based voice isolation.
    ///
    /// Applies a highpass filter at 300Hz, a lowpass filter at 3400Hz
    /// (the standard telephony speech band), and a compressor to even
    /// out the dynamic range. The sensitivity parameter adjusts the
    /// filter bandwidth:
    ///
    /// - Lower sensitivity → wider band (more content preserved)
    /// - Higher sensitivity → narrower band (more aggressive isolation)
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source media file.
    ///   - outputPath: Path for the isolated audio output.
    ///   - config: Voice isolation configuration.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildFFmpegIsolationArguments(
        inputPath: String,
        outputPath: String,
        config: VoiceIsolationConfig
    ) -> [String] {
        // Scale sensitivity to adjust the frequency band
        // sensitivity 0.0 → 100Hz–5000Hz (wide band)
        // sensitivity 0.5 → 300Hz–3400Hz (standard speech)
        // sensitivity 1.0 → 500Hz–2500Hz (narrow, aggressive)
        let lowCutoff = Int(100 + config.sensitivity * 400)   // 100–500 Hz
        let highCutoff = Int(5000 - config.sensitivity * 2500) // 5000–2500 Hz

        let filterChain = [
            "highpass=f=\(lowCutoff):poles=2",
            "lowpass=f=\(highCutoff):poles=2",
            "acompressor=threshold=-20dB:ratio=4:attack=5:release=50"
        ].joined(separator: ",")

        var args = [
            "-i", inputPath,
            "-af", filterChain,
            "-vn"  // Strip video
        ]

        // Output codec
        if let codec = config.outputFormat {
            args.append(contentsOf: ["-c:a", codec])
        }

        args.append(contentsOf: ["-y", outputPath])

        return args
    }

    // MARK: - Spectral Subtraction

    /// Builds FFmpeg arguments for spectral subtraction noise reduction.
    ///
    /// Uses the ``afftdn`` (FFT-based denoiser) filter to reduce
    /// steady-state background noise while preserving speech content.
    /// This is effective for content with consistent background noise
    /// (air conditioning, road noise, equipment hum).
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source media file.
    ///   - outputPath: Path for the denoised audio output.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildSpectralSubtractionArguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        // afftdn: Adaptive FFT-based noise reduction
        // nr = noise reduction level in dB (higher = more aggressive)
        // nf = noise floor in dB
        // tn = enable tracking of noise floor changes
        let filterChain = "afftdn=nr=20:nf=-30:tn=1"

        return [
            "-i", inputPath,
            "-af", filterChain,
            "-vn",
            "-y", outputPath
        ]
    }

    // MARK: - Centre Channel Extraction

    /// Builds FFmpeg arguments for extracting the centre channel from surround audio.
    ///
    /// In 5.1 and 7.1 surround mixes, dialogue is typically placed in the
    /// centre channel (channel index 2 in the standard layout: FL, FR, FC, LFE, BL, BR).
    /// This method extracts that channel as a mono track.
    ///
    /// When ``centerChannelOnly`` is `false`, a stereo downmix is produced that
    /// emphasises the centre channel by boosting it relative to the surrounds.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source media file.
    ///   - outputPath: Path for the extracted dialogue output.
    ///   - centerChannelOnly: If `true`, extract only the centre channel as mono.
    ///     If `false`, produce a centre-emphasised stereo downmix.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildDialogueExtractionArguments(
        inputPath: String,
        outputPath: String,
        centerChannelOnly: Bool
    ) -> [String] {
        let filterChain: String

        if centerChannelOnly {
            // Extract centre channel (channel 2) as mono output
            filterChain = "pan=mono|c0=FC"
        } else {
            // Centre-emphasised stereo downmix:
            // Boost centre channel by 3dB, reduce surrounds by 6dB
            filterChain = "pan=stereo|FL=0.5*FL+1.0*FC+0.25*BL|FR=0.5*FR+1.0*FC+0.25*BR"
        }

        return [
            "-i", inputPath,
            "-af", filterChain,
            "-vn",
            "-y", outputPath
        ]
    }

    // MARK: - ML Availability Check

    /// Checks whether the SoundAnalysis framework is available on the current system.
    ///
    /// SoundAnalysis requires macOS 15.0+ and may not be available on all
    /// hardware configurations. This method checks for framework availability
    /// at runtime.
    ///
    /// - Returns: `true` if SoundAnalysis is available for on-device ML processing.
    public static func isMLAvailable() -> Bool {
        // SoundAnalysis framework is available on macOS 15+
        // Check by attempting to load the framework bundle
        if let bundle = Bundle(identifier: "com.apple.SoundAnalysis") {
            return bundle.isLoaded || bundle.load()
        }
        // Fallback: check if the framework path exists
        return FileManager.default.fileExists(
            atPath: "/System/Library/Frameworks/SoundAnalysis.framework"
        )
    }
}
