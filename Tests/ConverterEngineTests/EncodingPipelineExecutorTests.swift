// ============================================================================
// MeedyaConverter — EncodingPipelineExecutor tests (#278)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards the pipeline executor that turns #278 from an arg-builder that never
/// ran into a real, sequenced, self-cleaning runner. The step runner is mocked
/// so sequencing / failure-abort / cleanup are tested without spawning ffmpeg.
final class EncodingPipelineExecutorTests: XCTestCase {

    // MARK: - Mock runner

    /// Records the order steps run in, and can be told to fail at a given step.
    private actor MockRunner: PipelineStepRunning {
        private(set) var ran: [Int] = []          // stepNumbers, in run order
        let failAtStepNumber: Int?
        init(failAtStepNumber: Int? = nil) { self.failAtStepNumber = failAtStepNumber }
        func run(_ step: ResolvedPipelineStep) async throws {
            ran.append(step.stepNumber)
            if step.stepNumber == failAtStepNumber {
                throw EncodingPipelineExecutorError.stepFailed(
                    stepNumber: step.stepNumber, stepName: step.step.name,
                    type: step.step.type, underlying: "boom")
            }
        }
        func order() -> [Int] { ran }
    }

    private func step(_ name: String, _ type: PipelineStepType, profile: EncodingProfile? = nil) -> PipelineStep {
        PipelineStep(name: name, type: type, profile: profile)
    }

    // MARK: - resolve (pure)

    func test_resolve_chainsTransformOutputForwardAndSideOutputsReadCurrent() {
        // encode -> thumbnail: the thumbnail reads the encode's output.
        let pipeline = EncodingPipeline(name: "P", steps: [
            step("enc", .encode, profile: .webStandard),
            step("thumb", .extractThumbnail),
        ])
        let resolved = EncodingPipelineExecutor.resolve(
            pipeline: pipeline, sourcePath: "/src/movie.mkv", outputDir: "/out")

        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].inputPath, "/src/movie.mkv")       // encode reads source
        XCTAssertTrue(resolved[0].isTransform)
        XCTAssertEqual(resolved[1].inputPath, resolved[0].outputPath) // thumb reads encode output
        XCTAssertFalse(resolved[1].isTransform)
        XCTAssertEqual(resolved[0].executable, "ffmpeg")
    }

    func test_resolve_probeUsesFfprobe() {
        let pipeline = EncodingPipeline(name: "P", steps: [step("probe", .probe)])
        let resolved = EncodingPipelineExecutor.resolve(
            pipeline: pipeline, sourcePath: "/src/movie.mkv", outputDir: "/out")
        XCTAssertEqual(resolved[0].executable, "ffprobe")
        XCTAssertFalse(resolved[0].isTransform)
    }

    func test_resolve_encodeUsesProfileAwareArguments() {
        // The profile-aware path produces a real transcode, not `-c copy`.
        let pipeline = EncodingPipeline(name: "P", steps: [step("enc", .encode, profile: .webStandard)])
        let resolved = EncodingPipelineExecutor.resolve(
            pipeline: pipeline, sourcePath: "/src/movie.mkv", outputDir: "/out")
        // A real encode carries codec flags; the copy fallback would be `-c copy`.
        XCTAssertFalse(resolved[0].arguments.contains("copy"), "\(resolved[0].arguments)")
        XCTAssertTrue(resolved[0].arguments.contains("-i"))
    }

    // MARK: - intermediateOutputs

    func test_intermediates_singleTransformHasNone() {
        // encode + thumbnail: BOTH are deliverables, nothing is intermediate.
        let pipeline = EncodingPipeline(name: "P", steps: [
            step("enc", .encode, profile: .webStandard),
            step("thumb", .extractThumbnail),
        ])
        let resolved = EncodingPipelineExecutor.resolve(
            pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out")
        XCTAssertTrue(EncodingPipelineExecutor.intermediateOutputs(of: resolved).isEmpty)
    }

    func test_intermediates_earlierTransformIsSuperseded() {
        // encode -> encode: the first encode output is superseded by the second.
        let pipeline = EncodingPipeline(name: "P", steps: [
            step("enc1", .encode, profile: .webStandard),
            step("enc2", .encode, profile: .webStandard),
        ])
        let resolved = EncodingPipelineExecutor.resolve(
            pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out")
        let intermediates = EncodingPipelineExecutor.intermediateOutputs(of: resolved)
        XCTAssertEqual(intermediates, [resolved[0].outputPath])
        XCTAssertFalse(intermediates.contains(resolved[1].outputPath), "final transform is a deliverable")
    }

    // MARK: - execute (sequencing / abort)

    func test_execute_runsAllStepsInOrder() async throws {
        let runner = MockRunner()
        let executor = EncodingPipelineExecutor(stepRunner: runner)
        let pipeline = EncodingPipeline(name: "P", steps: [
            step("a", .extractThumbnail),
            step("b", .extractAudio),
            step("c", .probe),
        ], cleanIntermediateFiles: false)
        _ = try await executor.execute(pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out")
        let order = await runner.order()
        XCTAssertEqual(order, [1, 2, 3])
    }

    func test_execute_haltsOnFirstFailure() async {
        let runner = MockRunner(failAtStepNumber: 2)
        let executor = EncodingPipelineExecutor(stepRunner: runner)
        let pipeline = EncodingPipeline(name: "P", steps: [
            step("a", .extractThumbnail),
            step("b", .extractAudio),
            step("c", .probe),
        ])
        do {
            _ = try await executor.execute(pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out")
            XCTFail("expected the failing step to throw")
        } catch {
            // step 3 must NOT have run.
            let order = await runner.order()
            XCTAssertEqual(order, [1, 2])
        }
    }

    func test_execute_emptyPipelineIsNoOpSuccess() async throws {
        let executor = EncodingPipelineExecutor(stepRunner: MockRunner())
        let result = try await executor.execute(
            pipeline: EncodingPipeline(name: "empty"), sourcePath: "/s/m.mkv", outputDir: "/out")
        XCTAssertTrue(result.deliverables.isEmpty)
        XCTAssertTrue(result.cleanedIntermediates.isEmpty)
    }
}
