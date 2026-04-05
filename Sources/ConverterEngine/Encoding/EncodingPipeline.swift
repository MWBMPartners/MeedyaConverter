// ============================================================================
// MeedyaConverter — EncodingPipeline
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - PipelineStepType

/// The type of operation a pipeline step performs.
///
/// Each case maps to a distinct FFmpeg invocation pattern (or supporting tool).
/// Steps are executed sequentially by the ``PipelineExecutor``, with the output
/// of one step potentially feeding into the next.
public enum PipelineStepType: String, Codable, Sendable, CaseIterable {

    /// Transcode the media file using an ``EncodingProfile``.
    case encode

    /// Extract a single still frame at a specified timestamp.
    case extractThumbnail

    /// Generate a short animated GIF preview from the source.
    case generatePreviewGIF

    /// Extract the audio track to a separate file.
    case extractAudio

    /// Analyse the output file to verify integrity (probe).
    case probe

    // MARK: - Display

    /// Human-readable label for UI display.
    public var displayName: String {
        switch self {
        case .encode:             return "Encode"
        case .extractThumbnail:   return "Extract Thumbnail"
        case .generatePreviewGIF: return "Generate Preview GIF"
        case .extractAudio:       return "Extract Audio"
        case .probe:              return "Probe / Verify"
        }
    }

    /// SF Symbol name for the step type icon.
    public var systemImage: String {
        switch self {
        case .encode:             return "film"
        case .extractThumbnail:   return "photo"
        case .generatePreviewGIF: return "play.rectangle"
        case .extractAudio:       return "waveform"
        case .probe:              return "magnifyingglass"
        }
    }
}

// MARK: - PipelineStep

/// A single step within an ``EncodingPipeline``.
///
/// Each step has a type that determines the FFmpeg invocation pattern,
/// an optional ``EncodingProfile`` (for `.encode` steps), and a
/// free-form configuration dictionary for step-specific parameters
/// such as thumbnail timestamp, GIF duration, or audio format.
public struct PipelineStep: Identifiable, Codable, Sendable {

    // MARK: - Properties

    /// Unique identifier for this step.
    public let id: UUID

    /// Human-readable name for this step (e.g., "Encode to H.265", "Thumbnail at 30s").
    public var name: String

    /// The operation this step performs.
    public var type: PipelineStepType

    /// The encoding profile to use (only relevant for `.encode` steps).
    public var profile: EncodingProfile?

    /// Step-specific configuration key-value pairs.
    ///
    /// Common keys by step type:
    /// - `.extractThumbnail`: `"timestamp"` (e.g. `"00:00:30"`)
    /// - `.generatePreviewGIF`: `"startTime"`, `"duration"`, `"fps"`, `"width"`
    /// - `.extractAudio`: `"format"` (e.g. `"flac"`, `"aac"`, `"wav"`)
    /// - `.probe`: `"format"` (e.g. `"json"`, `"flat"`)
    public var config: [String: String]

    // MARK: - Initialiser

    /// Create a new pipeline step.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - name: Human-readable name.
    ///   - type: The operation type for this step.
    ///   - profile: Encoding profile (for `.encode` steps).
    ///   - config: Step-specific configuration dictionary.
    public init(
        id: UUID = UUID(),
        name: String,
        type: PipelineStepType,
        profile: EncodingProfile? = nil,
        config: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.profile = profile
        self.config = config
    }
}

// MARK: - EncodingPipeline

/// An ordered sequence of ``PipelineStep``s that are executed in series
/// against a single input file.
///
/// Pipelines allow users to chain multiple operations — for example,
/// encoding a file, extracting a thumbnail, and generating a preview GIF
/// in a single automated workflow.
public struct EncodingPipeline: Identifiable, Codable, Sendable {

    // MARK: - Properties

    /// Unique identifier for this pipeline.
    public let id: UUID

    /// Human-readable name (e.g., "Encode + Thumbnail").
    public var name: String

    /// The ordered list of steps to execute.
    public var steps: [PipelineStep]

    /// Whether to remove intermediate files after the pipeline completes.
    ///
    /// When `true`, only the final output and explicitly requested artefacts
    /// (thumbnails, GIFs, extracted audio) are kept.
    public var cleanIntermediateFiles: Bool

    // MARK: - Initialiser

    /// Create a new encoding pipeline.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - name: Human-readable name.
    ///   - steps: Ordered list of pipeline steps.
    ///   - cleanIntermediateFiles: Whether to clean up intermediate files.
    public init(
        id: UUID = UUID(),
        name: String,
        steps: [PipelineStep] = [],
        cleanIntermediateFiles: Bool = true
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.cleanIntermediateFiles = cleanIntermediateFiles
    }
}

// MARK: - PipelineExecutor

/// Builds FFmpeg argument lists for each ``PipelineStep``.
///
/// The executor does not run the commands itself — it produces the
/// executable path, argument array, and expected output path so that
/// the caller (e.g., ``EncodingEngine``) can orchestrate execution.
public struct PipelineExecutor: Sendable {

    // MARK: - Argument Building

    /// Build the executable path, arguments, and output path for a pipeline step.
    ///
    /// - Parameters:
    ///   - step: The pipeline step to build arguments for.
    ///   - inputPath: Absolute path to the input file.
    ///   - outputDir: Directory where output files should be written.
    ///   - stepIndex: Zero-based index of this step in the pipeline (used for naming).
    /// - Returns: A tuple of `(executable, arguments, outputPath)`.
    public static func buildStepArguments(
        step: PipelineStep,
        inputPath: String,
        outputDir: String,
        stepIndex: Int
    ) -> (executable: String, arguments: [String], outputPath: String) {

        let baseName = (inputPath as NSString).lastPathComponent
            .replacingOccurrences(of: ".\((inputPath as NSString).pathExtension)", with: "")
        let ffmpeg = "ffmpeg"

        switch step.type {

        // -----------------------------------------------------------------
        // Encode — full transcode using the step's encoding profile
        // -----------------------------------------------------------------
        case .encode:
            let ext = step.config["extension"] ?? "mkv"
            let outputPath = (outputDir as NSString).appendingPathComponent(
                "\(baseName)_step\(stepIndex).\(ext)"
            )
            var args = ["-i", inputPath, "-y"]
            // Delegate detailed argument construction to the profile if available;
            // otherwise emit a simple copy.
            if step.profile != nil {
                // The caller should use EncodingJobConfig.buildArguments() for
                // full profile-aware argument generation. We provide a minimal
                // fallback here.
                args += ["-c", "copy", outputPath]
            } else {
                args += ["-c", "copy", outputPath]
            }
            return (ffmpeg, args, outputPath)

        // -----------------------------------------------------------------
        // Extract Thumbnail — single still frame at a timestamp
        // -----------------------------------------------------------------
        case .extractThumbnail:
            let timestamp = step.config["timestamp"] ?? "00:00:05"
            let outputPath = (outputDir as NSString).appendingPathComponent(
                "\(baseName)_thumb.jpg"
            )
            let args = [
                "-i", inputPath,
                "-ss", timestamp,
                "-vframes", "1",
                "-q:v", "2",
                "-y", outputPath
            ]
            return (ffmpeg, args, outputPath)

        // -----------------------------------------------------------------
        // Generate Preview GIF — short animated GIF
        // -----------------------------------------------------------------
        case .generatePreviewGIF:
            let startTime = step.config["startTime"] ?? "00:00:05"
            let duration = step.config["duration"] ?? "5"
            let fps = step.config["fps"] ?? "10"
            let width = step.config["width"] ?? "480"
            let outputPath = (outputDir as NSString).appendingPathComponent(
                "\(baseName)_preview.gif"
            )
            let filterComplex = "fps=\(fps),scale=\(width):-1:flags=lanczos,split[s0][s1];" +
                "[s0]palettegen[p];[s1][p]paletteuse"
            let args = [
                "-i", inputPath,
                "-ss", startTime,
                "-t", duration,
                "-filter_complex", filterComplex,
                "-y", outputPath
            ]
            return (ffmpeg, args, outputPath)

        // -----------------------------------------------------------------
        // Extract Audio — demux audio to a separate file
        // -----------------------------------------------------------------
        case .extractAudio:
            let format = step.config["format"] ?? "flac"
            let outputPath = (outputDir as NSString).appendingPathComponent(
                "\(baseName)_audio.\(format)"
            )
            var args = [
                "-i", inputPath,
                "-vn",          // no video
                "-sn",          // no subtitles
            ]
            if format == "flac" {
                args += ["-c:a", "flac"]
            } else if format == "wav" {
                args += ["-c:a", "pcm_s16le"]
            } else if format == "aac" {
                args += ["-c:a", "aac", "-b:a", step.config["bitrate"] ?? "256k"]
            } else {
                args += ["-c:a", "copy"]
            }
            args += ["-y", outputPath]
            return (ffmpeg, args, outputPath)

        // -----------------------------------------------------------------
        // Probe — analyse the file using ffprobe
        // -----------------------------------------------------------------
        case .probe:
            let probeFormat = step.config["format"] ?? "json"
            let outputPath = (outputDir as NSString).appendingPathComponent(
                "\(baseName)_probe.\(probeFormat == "json" ? "json" : "txt")"
            )
            let args = [
                "-v", "quiet",
                "-print_format", probeFormat,
                "-show_format",
                "-show_streams",
                inputPath
            ]
            return ("ffprobe", args, outputPath)
        }
    }
}

// MARK: - Built-In Pipeline Templates

extension EncodingPipeline {

    /// Built-in pipeline: Encode the file then extract a thumbnail at the 30-second mark.
    public static let encodePlusThumbnail = EncodingPipeline(
        name: "Encode + Thumbnail",
        steps: [
            PipelineStep(
                name: "Encode",
                type: .encode,
                profile: .webStandard
            ),
            PipelineStep(
                name: "Extract Thumbnail at 00:00:30",
                type: .extractThumbnail,
                config: ["timestamp": "00:00:30"]
            ),
        ],
        cleanIntermediateFiles: true
    )

    /// Built-in pipeline: Encode the file then generate a short animated GIF preview.
    public static let encodePlusPreviewGIF = EncodingPipeline(
        name: "Encode + Preview GIF",
        steps: [
            PipelineStep(
                name: "Encode",
                type: .encode,
                profile: .webStandard
            ),
            PipelineStep(
                name: "Generate 5s Preview GIF",
                type: .generatePreviewGIF,
                config: [
                    "startTime": "00:00:10",
                    "duration": "5",
                    "fps": "10",
                    "width": "480",
                ]
            ),
        ],
        cleanIntermediateFiles: true
    )

    /// Built-in pipeline: Encode the file then extract the audio track as FLAC.
    public static let encodePlusExtractAudio = EncodingPipeline(
        name: "Encode + Extract Audio",
        steps: [
            PipelineStep(
                name: "Encode",
                type: .encode,
                profile: .webStandard
            ),
            PipelineStep(
                name: "Extract Audio (FLAC)",
                type: .extractAudio,
                config: ["format": "flac"]
            ),
        ],
        cleanIntermediateFiles: true
    )

    /// All built-in pipeline templates for the template picker.
    public static let builtInTemplates: [EncodingPipeline] = [
        .encodePlusThumbnail,
        .encodePlusPreviewGIF,
        .encodePlusExtractAudio,
    ]
}
