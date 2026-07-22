// ============================================================================
// MeedyaConverter — DualDynamicHDRPipelineExecutor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `DualDynamicHDRPipeline.buildPipelineSteps(...)` (issue #370) already
// builds a fully-formed, ordered list of `PipelineStepDescriptor`s — each
// carrying a real tool name, real argument array, and real input/output
// paths — but nothing in the app ever ran them; `DualDynamicHDRView
// .startConversion()` set `isConverting = true` and stopped, per a comment
// noting "actual execution would be performed by the EncodingEngine".
//
// This file is that execution layer. It does not invent any new process-
// spawning logic: each step is dispatched to the *existing*, already-tested
// runners —
//   - `tool == "dovi_tool"`      → `DoviToolWrapper.run(arguments:)`
//   - `tool == "hdr10plus_tool"` → `HDR10PlusToolWrapper.run(arguments:)`
//   - `tool == "internal"`       → `DualDynamicHDRPipeline
//                                    .convertDVMetadataToHDR10Plus(...)`
//   - `tool == "ffmpeg"`         → `FFmpegProcessController.startEncoding`
//                                    (the five-tier HLG target's PQ→HLG
//                                    base-layer pass; the four-tier target
//                                    never produces this step)
// via `DualDynamicHDRToolStepRunner`, the default (real) implementation of
// the `DualDynamicHDRStepRunning` protocol. `DualDynamicHDRPipelineExecutor`
// itself only sequences steps, reports progress, aborts on the first
// failure, and cleans up intermediate temp files — logic that is pure
// enough to unit-test with a mock `DualDynamicHDRStepRunning` and no real
// dovi_tool/hdr10plus_tool/ffmpeg binaries, matching the "no real tools in
// CI" constraint.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - DualDynamicHDRPipelineExecutorError

/// Errors surfaced by `DualDynamicHDRPipelineExecutor`.
public enum DualDynamicHDRPipelineExecutorError: LocalizedError, Sendable, Equatable {
    /// A pipeline step failed. `underlying` is the tool's own error text
    /// (e.g. dovi_tool/hdr10plus_tool stderr) — never fabricated.
    case stepFailed(stepNumber: Int, tool: String, description: String, underlying: String)

    /// A step named a tool the runner has no dispatch case for.
    case unsupportedTool(String)

    public var errorDescription: String? {
        switch self {
        case let .stepFailed(stepNumber, tool, description, underlying):
            return "Step \(stepNumber) (\(tool) — \(description)) failed: \(underlying)"
        case .unsupportedTool(let tool):
            return "Dual dynamic HDR pipeline step references an unsupported tool \"\(tool)\"."
        }
    }
}

// MARK: - DualDynamicHDRStepRunning

/// Abstraction over "run one pipeline step", so `DualDynamicHDRPipelineExecutor`
/// can be unit-tested with a mock — sequencing, failure-abort, and cleanup —
/// without invoking real dovi_tool / hdr10plus_tool / ffmpeg binaries.
///
/// `DualDynamicHDRToolStepRunner` (below) is the real, production
/// implementation; tests substitute their own conformer.
public protocol DualDynamicHDRStepRunning: Sendable {
    /// Run a single step. Implementations dispatch on `step.tool`.
    ///
    /// - Throws: On failure. The executor treats any thrown error as fatal
    ///   for the whole pipeline (no partial-success reporting).
    func run(step: PipelineStepDescriptor) async throws
}

// MARK: - DualDynamicHDRToolStepRunner

/// The real `DualDynamicHDRStepRunning` implementation used in production.
///
/// Every case below delegates to an existing, already-tested runner —
/// see the file-level overview for the mapping. No ffmpeg/dovi_tool/
/// hdr10plus_tool invocation logic is reimplemented here.
public struct DualDynamicHDRToolStepRunner: DualDynamicHDRStepRunning {

    private let doviTool: DoviToolWrapper
    private let hdr10PlusTool: HDR10PlusToolWrapper

    /// Resolves the ffmpeg binary path for the (HLG-target-only) "ffmpeg"
    /// step. Defaults to the same `FFmpegBundleManager.locateFFmpeg()`
    /// lookup used by `QualityMetricsView.runAnalysis()` and
    /// `VideoTrimmerView.applyTrim()`, run off the calling context via
    /// `Task.detached` since `locateFFmpeg()` does synchronous filesystem
    /// probing. Overridable so tests never touch the real filesystem search
    /// path or spawn a real ffmpeg process.
    private let ffmpegBinaryPath: @Sendable () async throws -> String

    public init(
        doviTool: DoviToolWrapper = DoviToolWrapper(),
        hdr10PlusTool: HDR10PlusToolWrapper = HDR10PlusToolWrapper(),
        ffmpegBinaryPath: @escaping @Sendable () async throws -> String = {
            try await Task.detached {
                try FFmpegBundleManager().locateFFmpeg().path
            }.value
        }
    ) {
        self.doviTool = doviTool
        self.hdr10PlusTool = hdr10PlusTool
        self.ffmpegBinaryPath = ffmpegBinaryPath
    }

    public func run(step: PipelineStepDescriptor) async throws {
        switch step.tool {
        case "dovi_tool":
            let result = try await doviTool.run(arguments: step.arguments)
            guard result.exitCode == 0 else {
                throw DualDynamicHDRPipelineExecutorError.stepFailed(
                    stepNumber: step.stepNumber,
                    tool: step.tool,
                    description: step.description,
                    underlying: result.stderr.isEmpty ? "dovi_tool exited with code \(result.exitCode)" : result.stderr
                )
            }

        case "hdr10plus_tool":
            let result = try await hdr10PlusTool.run(arguments: step.arguments)
            guard result.exitCode == 0 else {
                throw DualDynamicHDRPipelineExecutorError.stepFailed(
                    stepNumber: step.stepNumber,
                    tool: step.tool,
                    description: step.description,
                    underlying: result.stderr.isEmpty ? "hdr10plus_tool exited with code \(result.exitCode)" : result.stderr
                )
            }

        case "internal":
            // `convertDVMetadataToHDR10Plus` does synchronous file I/O
            // (Data(contentsOf:) / Data.write(to:)), so it is dispatched via
            // `Task.detached` — mirroring the codebase's own pattern for
            // wrapping blocking, non-async work (e.g.
            // `QualityMetricsView.runAnalysis()`'s `FFmpegBundleManager
            // .locateFFmpeg()` call) — rather than blocking whatever
            // executor/thread is driving this async function.
            try await Task.detached {
                try DualDynamicHDRPipeline.convertDVMetadataToHDR10Plus(
                    dvMetadataPath: step.inputPath,
                    hdr10PlusOutputPath: step.outputPath
                )
            }.value

        case "ffmpeg":
            // Only produced for the five-tier (DV + HDR10+ + HLG) target's
            // PQ→HLG base-layer conversion step. Uses the same
            // FFmpegProcessController.startEncoding(arguments:) /
            // AsyncStream consumption pattern as
            // `VideoTrimmerView.runToCompletion` — the process's own
            // completion is awaited by draining its progress stream, not by
            // any bespoke polling.
            let binary = try await ffmpegBinaryPath()
            let controller = FFmpegProcessController(binaryPath: binary)
            let progressStream = try controller.startEncoding(arguments: step.arguments)
            for await _ in progressStream {
                if Task.isCancelled {
                    controller.stopEncoding()
                    break
                }
            }
            if Task.isCancelled {
                throw CancellationError()
            }
            if let code = controller.exitCode, code != 0 {
                throw DualDynamicHDRPipelineExecutorError.stepFailed(
                    stepNumber: step.stepNumber,
                    tool: step.tool,
                    description: step.description,
                    underlying: controller.errorOutput.isEmpty
                        ? "ffmpeg exited with code \(code)" : controller.errorOutput
                )
            }

        default:
            throw DualDynamicHDRPipelineExecutorError.unsupportedTool(step.tool)
        }
    }
}

// MARK: - DualDynamicHDRPipelineExecutor

/// Runs an ordered list of `PipelineStepDescriptor`s produced by
/// `DualDynamicHDRPipeline.buildPipelineSteps(...)`, in order, via an
/// injected `DualDynamicHDRStepRunning`.
///
/// Responsibilities kept deliberately narrow and pure so this class is
/// fully unit-testable with a mock step runner:
///   - **Sequencing**: steps run strictly in array order, one at a time.
///   - **Failure-abort**: the first step to throw stops the pipeline;
///     no later step runs.
///   - **Progress**: `onProgress` (if provided) is invoked just before each
///     step starts, with its 0-based index and the descriptor itself.
///   - **Cleanup**: every intermediate step output (i.e. every
///     `step.outputPath` except the final step's) is removed once the
///     pipeline finishes, whether it finished by succeeding or by throwing.
///     `step.inputPath` is never touched, so the caller's real source file
///     is never at risk even if it happens to sit in the same directory.
///
/// Concurrency: a plain `final class` holding only a `Sendable` protocol
/// value — no mutable state — so it is trivially `Sendable` without
/// `@unchecked`. `execute(steps:onProgress:)` is a non-isolated `async`
/// method; the `onProgress` callback is a plain `@Sendable` closure (not
/// `@MainActor`-isolated) and may run on whatever thread the current step's
/// `await` resumes on — exactly like `EncodingEngine.encode(job:onProgress:)`'s
/// `@Sendable (FFmpegProgressInfo) -> Void` callback. Callers that need to
/// touch `@MainActor`-isolated state (SwiftUI `@State`, etc.) from
/// `onProgress` must hop explicitly, e.g. `Task { @MainActor in ... }`,
/// exactly as `AppViewModel.startQueue()` does around its own
/// `progressInfo` callback.
public final class DualDynamicHDRPipelineExecutor: Sendable {

    private let stepRunner: DualDynamicHDRStepRunning

    /// - Parameter stepRunner: Defaults to `DualDynamicHDRToolStepRunner()`
    ///   (the real dovi_tool/hdr10plus_tool/ffmpeg dispatcher). Tests inject
    ///   a mock conforming to `DualDynamicHDRStepRunning` instead.
    public init(stepRunner: DualDynamicHDRStepRunning = DualDynamicHDRToolStepRunner()) {
        self.stepRunner = stepRunner
    }

    /// Execute `steps` in order.
    ///
    /// - Parameters:
    ///   - steps: The ordered pipeline, typically from
    ///     `DualDynamicHDRPipeline.buildPipelineSteps(...)`. A `nil`/empty
    ///     array is a no-op success.
    ///   - onProgress: Invoked immediately before each step runs, with that
    ///     step's 0-based index and descriptor. Never invoked after the
    ///     pipeline has finished (successfully or not).
    /// - Throws: `CancellationError` if the calling `Task` is cancelled
    ///   between steps; otherwise, whatever the failing step's
    ///   `DualDynamicHDRStepRunning.run(step:)` threw (real callers see
    ///   `DualDynamicHDRPipelineExecutorError.stepFailed`, carrying the
    ///   real tool's own stderr — this executor never fabricates a
    ///   generic/success result on failure).
    public func execute(
        steps: [PipelineStepDescriptor],
        onProgress: (@Sendable (Int, PipelineStepDescriptor) -> Void)? = nil
    ) async throws {
        guard !steps.isEmpty else { return }

        let finalOutputPath = steps.last?.outputPath
        var producedOutputs: [String] = []

        do {
            for (index, step) in steps.enumerated() {
                if Task.isCancelled {
                    throw CancellationError()
                }
                onProgress?(index, step)
                try await stepRunner.run(step: step)
                producedOutputs.append(step.outputPath)
            }
        } catch {
            cleanUpIntermediateFiles(producedOutputs, finalOutputPath: finalOutputPath)
            throw error
        }

        cleanUpIntermediateFiles(producedOutputs, finalOutputPath: finalOutputPath)
    }

    /// Removes every produced output except the pipeline's final output.
    /// Best-effort: a file that does not exist, or cannot be removed, is
    /// silently skipped — cleanup failures must never mask (or be confused
    /// with) the pipeline's real success/failure result.
    private func cleanUpIntermediateFiles(_ paths: [String], finalOutputPath: String?) {
        for path in paths where path != finalOutputPath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
