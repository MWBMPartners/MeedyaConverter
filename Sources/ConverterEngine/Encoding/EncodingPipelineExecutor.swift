// ============================================================================
// MeedyaConverter — EncodingPipelineExecutor (Issue #278)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// `EncodingPipeline` + `PipelineExecutor.buildStepArguments(...)` (issue #278)
// could build a step's FFmpeg command line, but nothing ran them — the editor
// only previewed configuration, so a pipeline never produced a file. This is
// the missing executor: it resolves a pipeline against a source into an
// ordered list of concrete invocations, runs them in sequence, halts on the
// first failure, and cleans up superseded intermediate files on success.
//
// It deliberately mirrors the shipped `DualDynamicHDRPipelineExecutor` (#370):
// an injectable step-running protocol keeps the sequencing / failure-abort /
// cleanup logic fully unit-testable without spawning ffmpeg/ffprobe, and the
// real runner delegates to the same `FFmpegProcessController` +
// `FFmpegBundleManager` machinery the rest of the app uses.
// ============================================================================

import Foundation

// MARK: - EncodingPipelineExecutorError

/// Errors surfaced by `EncodingPipelineExecutor`.
public enum EncodingPipelineExecutorError: LocalizedError, Sendable, Equatable {

    /// A step's process exited non-zero (or its runner otherwise failed).
    /// Carries the 1-based step number, the step name, its type, and the
    /// underlying tool's own error text — never a fabricated success.
    case stepFailed(stepNumber: Int, stepName: String, type: PipelineStepType, underlying: String)

    /// A resolved step named an executable the runner does not support.
    case unsupportedExecutable(String)

    public var errorDescription: String? {
        switch self {
        case let .stepFailed(stepNumber, stepName, type, underlying):
            return "Pipeline step \(stepNumber) (\(stepName) — \(type.displayName)) failed: \(underlying)"
        case let .unsupportedExecutable(exe):
            return "Pipeline step uses an unsupported tool: \(exe)"
        }
    }
}

// MARK: - ResolvedPipelineStep

/// A single pipeline step resolved against a concrete source into an
/// executable invocation, with the paths it reads and writes.
public struct ResolvedPipelineStep: Sendable {

    /// The originating step.
    public let step: PipelineStep

    /// 1-based position in the pipeline (for user-facing messages).
    public let stepNumber: Int

    /// The tool to run: `"ffmpeg"` or `"ffprobe"`.
    public let executable: String

    /// The tool's argument list.
    public let arguments: [String]

    /// The file this step reads.
    public let inputPath: String

    /// The file this step writes.
    public let outputPath: String

    /// Whether this step advances the "current media" (an `.encode`) rather
    /// than producing a side deliverable (thumbnail / GIF / audio / probe).
    /// Only superseded transform outputs are treated as intermediates.
    public let isTransform: Bool

    public init(
        step: PipelineStep,
        stepNumber: Int,
        executable: String,
        arguments: [String],
        inputPath: String,
        outputPath: String,
        isTransform: Bool
    ) {
        self.step = step
        self.stepNumber = stepNumber
        self.executable = executable
        self.arguments = arguments
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.isTransform = isTransform
    }
}

// MARK: - PipelineRunResult

/// The outcome of a successful pipeline run.
public struct PipelineRunResult: Sendable, Equatable {

    /// The files the run produced and kept (final transform output + every
    /// extract/probe side output).
    public let deliverables: [String]

    /// The intermediate files that were removed on success (transform outputs
    /// superseded by a later transform).
    public let cleanedIntermediates: [String]

    public init(deliverables: [String], cleanedIntermediates: [String]) {
        self.deliverables = deliverables
        self.cleanedIntermediates = cleanedIntermediates
    }
}

// MARK: - PipelineStepRunning

/// Runs one resolved pipeline step. Injectable so the executor's sequencing,
/// failure-abort, and cleanup can be unit-tested without spawning real
/// ffmpeg/ffprobe processes.
public protocol PipelineStepRunning: Sendable {
    /// Run one step. Throw on failure — the executor treats any thrown error
    /// as fatal for the whole pipeline (no partial-success reporting).
    func run(_ step: ResolvedPipelineStep) async throws
}

// MARK: - EncodingPipelineExecutor

/// Runs an `EncodingPipeline` against a source file.
///
/// ## Media model
///
/// A single "current media" file flows through the pipeline. It starts as the
/// source. An `.encode` step (a *transform*) reads the current media and its
/// output becomes the new current media. An extract/probe step reads the
/// current media and produces a **side deliverable** without changing it. So
/// `encode → thumbnail` yields both the encoded video *and* a thumbnail of it,
/// and both are kept.
///
/// ## Cleanup
///
/// Only a transform output that a *later* transform supersedes is an
/// intermediate; those are removed on success. The final transform output and
/// every side deliverable are kept. The source is never a step output, so it
/// is never at risk. Cleanup runs on success only — a failing run leaves every
/// file in place for inspection.
///
/// Concurrency: a `final class` holding only a `Sendable` protocol value, so
/// trivially `Sendable`. `execute(...)` is a non-isolated `async` method and
/// its `onProgress` callback is a plain `@Sendable` closure that may resume on
/// any thread — callers touching `@MainActor` state must hop explicitly, as
/// `AppViewModel.startQueue()` does.
public final class EncodingPipelineExecutor: Sendable {

    private let stepRunner: PipelineStepRunning

    /// - Parameter stepRunner: Defaults to `FFmpegPipelineStepRunner()` (the
    ///   real ffmpeg/ffprobe dispatcher). Tests inject a mock.
    public init(stepRunner: PipelineStepRunning = FFmpegPipelineStepRunner()) {
        self.stepRunner = stepRunner
    }

    /// Resolve a pipeline into ordered concrete invocations, threading the
    /// "current media" through transform steps. Pure — no I/O, no process
    /// spawning — so the chaining/naming can be tested directly.
    ///
    /// `.encode` steps with a profile are resolved with the full profile-aware
    /// `EncodingJobConfig.buildArguments()` (not the copy-only fallback in
    /// `PipelineExecutor.buildStepArguments`), so a pipeline encode is a real
    /// transcode. Every other step defers to `PipelineExecutor` verbatim.
    ///
    /// - Parameters:
    ///   - pipeline: The pipeline to resolve.
    ///   - sourcePath: Absolute path to the source media.
    ///   - outputDir: Directory for step outputs.
    /// - Returns: The ordered resolved steps.
    public static func resolve(
        pipeline: EncodingPipeline,
        sourcePath: String,
        outputDir: String
    ) -> [ResolvedPipelineStep] {
        var current = sourcePath
        var resolved: [ResolvedPipelineStep] = []

        for (index, step) in pipeline.steps.enumerated() {
            let built = PipelineExecutor.buildStepArguments(
                step: step,
                inputPath: current,
                outputDir: outputDir,
                stepIndex: index
            )

            var executable = built.executable
            var arguments = built.arguments
            var outputPath = built.outputPath

            // A real encode: prefer full profile-aware arguments over the
            // copy-only fallback baked into buildStepArguments.
            if step.type == .encode, let profile = step.profile {
                let ext = profile.containerFormat.fileExtensions.first
                    ?? step.config["extension"] ?? "mkv"
                let base = (current as NSString).lastPathComponent
                let baseNoExt = (base as NSString).deletingPathExtension
                outputPath = (outputDir as NSString).appendingPathComponent(
                    PathSanitizer.sanitizeFilenameComponent("\(baseNoExt)_step\(index).\(ext)")
                )
                let jobConfig = EncodingJobConfig(
                    inputURL: URL(fileURLWithPath: current),
                    outputURL: URL(fileURLWithPath: outputPath),
                    profile: profile
                )
                arguments = jobConfig.buildArguments()
                executable = "ffmpeg"
            }

            let isTransform = (step.type == .encode)
            resolved.append(
                ResolvedPipelineStep(
                    step: step,
                    stepNumber: index + 1,
                    executable: executable,
                    arguments: arguments,
                    inputPath: current,
                    outputPath: outputPath,
                    isTransform: isTransform
                )
            )

            if isTransform { current = outputPath }
        }

        return resolved
    }

    /// The intermediate outputs for a resolved pipeline: every transform
    /// output except the last transform's (which is the final media). Pure, so
    /// the cleanup contract is testable without touching the filesystem.
    public static func intermediateOutputs(of steps: [ResolvedPipelineStep]) -> [String] {
        let transformOutputs = steps.filter(\.isTransform).map(\.outputPath)
        return transformOutputs.isEmpty ? [] : Array(transformOutputs.dropLast())
    }

    /// Execute a pipeline against a source.
    ///
    /// - Parameters:
    ///   - pipeline: The pipeline to run. An empty pipeline is a no-op success.
    ///   - sourcePath: Absolute path to the source media (never modified or
    ///     deleted).
    ///   - outputDir: Directory for step outputs.
    ///   - onProgress: Invoked immediately before each step runs, with its
    ///     0-based index and resolved descriptor.
    /// - Returns: The produced deliverables and the intermediates cleaned up.
    /// - Throws: `CancellationError` if the calling `Task` is cancelled
    ///   between steps; otherwise the failing step's error (real callers see
    ///   `EncodingPipelineExecutorError.stepFailed` carrying the tool's own
    ///   stderr). On failure nothing is cleaned up.
    @discardableResult
    public func execute(
        pipeline: EncodingPipeline,
        sourcePath: String,
        outputDir: String,
        onProgress: (@Sendable (Int, ResolvedPipelineStep) -> Void)? = nil
    ) async throws -> PipelineRunResult {
        let steps = Self.resolve(
            pipeline: pipeline,
            sourcePath: sourcePath,
            outputDir: outputDir
        )
        guard !steps.isEmpty else {
            return PipelineRunResult(deliverables: [], cleanedIntermediates: [])
        }

        var produced: [String] = []
        for (index, step) in steps.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            onProgress?(index, step)
            try await stepRunner.run(step)
            produced.append(step.outputPath)
        }

        // Success only: remove superseded transform intermediates, keep the
        // final media and every side deliverable — unless the pipeline opts
        // out of cleanup (`cleanIntermediateFiles == false`), in which case
        // every produced file is kept.
        let intermediates = pipeline.cleanIntermediateFiles
            ? Self.intermediateOutputs(of: steps)
            : []
        var cleaned: [String] = []
        for path in intermediates {
            try? FileManager.default.removeItem(atPath: path)
            cleaned.append(path)
        }
        let deliverables = produced.filter { !intermediates.contains($0) }
        return PipelineRunResult(deliverables: deliverables, cleanedIntermediates: cleaned)
    }
}

// MARK: - FFmpegPipelineStepRunner

/// The real `PipelineStepRunning` used in production.
///
/// `ffmpeg` steps run via `FFmpegProcessController` (the same controller +
/// AsyncStream-drain pattern `DualDynamicHDRPipelineExecutor` and
/// `VideoTrimmerView` use). `ffprobe` steps run as a plain `Process` whose
/// stdout is captured and written to the step's output path — the probe
/// arguments print the report to stdout rather than a file. Binary lookup goes
/// through `FFmpegBundleManager` (bundled → Homebrew → PATH), off the calling
/// context via `Task.detached` since the search does synchronous filesystem
/// probing. Both resolvers are injectable so tests never touch the real search
/// path or spawn a process.
public struct FFmpegPipelineStepRunner: PipelineStepRunning {

    private let ffmpegBinaryPath: @Sendable () async throws -> String
    private let ffprobeBinaryPath: @Sendable () async throws -> String

    public init(
        ffmpegBinaryPath: @escaping @Sendable () async throws -> String = {
            try await Task.detached { try FFmpegBundleManager().locateFFmpeg().path }.value
        },
        ffprobeBinaryPath: @escaping @Sendable () async throws -> String = {
            try await Task.detached { try FFmpegBundleManager().locateFFprobe().path }.value
        }
    ) {
        self.ffmpegBinaryPath = ffmpegBinaryPath
        self.ffprobeBinaryPath = ffprobeBinaryPath
    }

    public func run(_ step: ResolvedPipelineStep) async throws {
        switch step.executable {
        case "ffmpeg":
            let binary = try await ffmpegBinaryPath()
            let controller = FFmpegProcessController(binaryPath: binary)
            let progressStream = try controller.startEncoding(arguments: step.arguments)
            for await _ in progressStream {
                if Task.isCancelled {
                    controller.stopEncoding()
                    break
                }
            }
            if Task.isCancelled { throw CancellationError() }
            if let code = controller.exitCode, code != 0 {
                throw EncodingPipelineExecutorError.stepFailed(
                    stepNumber: step.stepNumber,
                    stepName: step.step.name,
                    type: step.step.type,
                    underlying: controller.errorOutput.isEmpty
                        ? "ffmpeg exited with code \(code)" : controller.errorOutput
                )
            }

        case "ffprobe":
            let binary = try await ffprobeBinaryPath()
            try await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = step.arguments
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                try process.run()
                // Read before waitUntilExit to avoid deadlocking on a full pipe.
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let err = String(data: errData, encoding: .utf8) ?? ""
                    throw EncodingPipelineExecutorError.stepFailed(
                        stepNumber: step.stepNumber,
                        stepName: step.step.name,
                        type: step.step.type,
                        underlying: err.isEmpty
                            ? "ffprobe exited with code \(process.terminationStatus)" : err
                    )
                }
                try outData.write(to: URL(fileURLWithPath: step.outputPath))
            }.value

        default:
            throw EncodingPipelineExecutorError.unsupportedExecutable(step.executable)
        }
    }
}
