// ============================================================================
// MeedyaConverter — DualDynamicHDRPipelineExecutorTests (Issue #370)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Pure, CI-runnable tests for `DualDynamicHDRPipelineExecutor` — no real
// dovi_tool / hdr10plus_tool / ffmpeg binary is ever invoked. A
// `MockDualDynamicHDRStepRunner` (conforming to the public
// `DualDynamicHDRStepRunning` protocol) is injected in place of the real
// `DualDynamicHDRToolStepRunner`, so sequencing, failure-abort, progress
// reporting, and temp-file cleanup can all be exercised deterministically.
//
// `DualDynamicHDRToolStepRunner`'s own dispatch-on-`step.tool` logic is
// covered too, but only for the `default` (unsupported tool) branch, which
// never touches a real binary.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

// MARK: - MockDualDynamicHDRStepRunner

/// Records the order `run(step:)` was called in, optionally throws when a
/// configured step number runs, and optionally materialises `step.outputPath`
/// as an empty file so the executor's cleanup logic has something real to
/// remove — simulating what a real tool run would have left behind.
final class MockDualDynamicHDRStepRunner: DualDynamicHDRStepRunning, @unchecked Sendable {
    struct SimulatedFailure: Error, Equatable {
        let stepNumber: Int
    }

    private let lock = NSLock()
    private var recordedSteps: [Int] = []

    /// If set, `run(step:)` throws `SimulatedFailure` when this step number
    /// is reached, after recording it (but before creating its output file).
    var failAtStepNumber: Int?

    /// Whether `run(step:)` should create an (empty) file at
    /// `step.outputPath`, simulating a real tool producing its declared
    /// output. Defaults to `true`.
    var createsOutputFiles: Bool = true

    /// Step numbers `run(step:)` was called for, in call order.
    var ranSteps: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSteps
    }

    func run(step: PipelineStepDescriptor) async throws {
        lock.lock()
        recordedSteps.append(step.stepNumber)
        lock.unlock()

        if step.stepNumber == failAtStepNumber {
            throw SimulatedFailure(stepNumber: step.stepNumber)
        }

        if createsOutputFiles {
            FileManager.default.createFile(
                atPath: step.outputPath,
                contents: Data("step-\(step.stepNumber)-output".utf8)
            )
        }
    }
}

// MARK: - ProgressRecorder

/// Records `onProgress` callback invocations under a lock. The executor's
/// `onProgress` parameter is a plain (non-async) `@Sendable` closure — see
/// `DualDynamicHDRPipelineExecutor`'s doc comment — so tests need a
/// synchronous, thread-safe sink rather than an `actor` (which would force
/// the closure to hop via a detached `Task`, breaking the ordering this
/// test asserts on). Mirrors the lock-protected recorder pattern in
/// `CloudUploadExecutorTests.MockURLProtocol`.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [(index: Int, stepNumber: Int)] = []

    var calls: [(index: Int, stepNumber: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func record(index: Int, stepNumber: Int) {
        lock.lock()
        recordedCalls.append((index, stepNumber))
        lock.unlock()
    }
}

// MARK: - DualDynamicHDRPipelineExecutorTests

final class DualDynamicHDRPipelineExecutorTests: XCTestCase {

    // MARK: - Fixtures

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual-hdr-executor-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    /// Builds `count` steps with real, distinct file paths under `tempDir`,
    /// numbered 1...count.
    private func makeSteps(count: Int, tool: String = "dovi_tool") -> [PipelineStepDescriptor] {
        (1...count).map { n in
            PipelineStepDescriptor(
                stepNumber: n,
                tool: tool,
                description: "Step \(n)",
                arguments: ["noop-\(n)"],
                inputPath: tempDir.appendingPathComponent("in\(n).bin").path,
                outputPath: tempDir.appendingPathComponent("out\(n).bin").path
            )
        }
    }

    // MARK: - Sequencing

    func test_execute_runsAllStepsInOrder() async throws {
        let steps = makeSteps(count: 4)
        let mock = MockDualDynamicHDRStepRunner()
        let executor = DualDynamicHDRPipelineExecutor(stepRunner: mock)

        try await executor.execute(steps: steps)

        XCTAssertEqual(mock.ranSteps, [1, 2, 3, 4])
    }

    func test_execute_emptySteps_isNoOpSuccess() async throws {
        let mock = MockDualDynamicHDRStepRunner()
        let executor = DualDynamicHDRPipelineExecutor(stepRunner: mock)

        try await executor.execute(steps: [])

        XCTAssertEqual(mock.ranSteps, [])
    }

    func test_execute_reportsProgressForEachStepBeforeItRuns() async throws {
        let steps = makeSteps(count: 3)
        let mock = MockDualDynamicHDRStepRunner()
        let executor = DualDynamicHDRPipelineExecutor(stepRunner: mock)
        let recorder = ProgressRecorder()

        try await executor.execute(steps: steps) { index, step in
            recorder.record(index: index, stepNumber: step.stepNumber)
        }

        XCTAssertEqual(recorder.calls.map(\.index), [0, 1, 2])
        XCTAssertEqual(recorder.calls.map(\.stepNumber), [1, 2, 3])
    }

    // MARK: - Failure Abort

    func test_execute_abortsOnFirstFailure_laterStepsNeverRun() async throws {
        let steps = makeSteps(count: 5)
        let mock = MockDualDynamicHDRStepRunner()
        mock.failAtStepNumber = 3
        let executor = DualDynamicHDRPipelineExecutor(stepRunner: mock)

        do {
            try await executor.execute(steps: steps)
            XCTFail("Expected the executor to throw when step 3 fails")
        } catch let error as MockDualDynamicHDRStepRunner.SimulatedFailure {
            XCTAssertEqual(error.stepNumber, 3)
        }

        // Steps 1 and 2 ran; step 3 ran (and threw); steps 4 and 5 never ran.
        XCTAssertEqual(mock.ranSteps, [1, 2, 3])
    }

    func test_execute_neverFabricatesSuccessAfterFailure() async throws {
        let steps = makeSteps(count: 2)
        let mock = MockDualDynamicHDRStepRunner()
        mock.failAtStepNumber = 1
        let executor = DualDynamicHDRPipelineExecutor(stepRunner: mock)

        var threw = false
        do {
            try await executor.execute(steps: steps)
        } catch {
            threw = true
        }
        XCTAssertTrue(threw, "A failing first step must propagate as a thrown error, never a silent success")
    }

    // MARK: - Cleanup

    func test_execute_onSuccess_removesIntermediateOutputs_keepsFinalOutput() async throws {
        let steps = makeSteps(count: 3)
        let mock = MockDualDynamicHDRStepRunner()
        let executor = DualDynamicHDRPipelineExecutor(stepRunner: mock)

        try await executor.execute(steps: steps)

        // Steps 1 and 2's outputs are intermediate — removed after success.
        XCTAssertFalse(FileManager.default.fileExists(atPath: steps[0].outputPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: steps[1].outputPath))
        // Step 3's output is the pipeline's final result — preserved.
        XCTAssertTrue(FileManager.default.fileExists(atPath: steps[2].outputPath))
    }

    func test_execute_onFailure_removesFilesProducedBeforeTheFailingStep() async throws {
        let steps = makeSteps(count: 4)
        let mock = MockDualDynamicHDRStepRunner()
        mock.failAtStepNumber = 3
        let executor = DualDynamicHDRPipelineExecutor(stepRunner: mock)

        do {
            try await executor.execute(steps: steps)
            XCTFail("Expected failure")
        } catch {
            // expected
        }

        // Steps 1 and 2 produced real files before the failure — cleaned up.
        XCTAssertFalse(FileManager.default.fileExists(atPath: steps[0].outputPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: steps[1].outputPath))
        // Step 3 threw before creating its output file in this mock.
        XCTAssertFalse(FileManager.default.fileExists(atPath: steps[2].outputPath))
        // Step 4 never ran.
        XCTAssertFalse(FileManager.default.fileExists(atPath: steps[3].outputPath))
    }

    func test_execute_neverRemoves_stepInputPaths() async throws {
        // A source file that happens to live in the same temp directory as
        // the pipeline's intermediate outputs must never be touched by
        // cleanup — only `step.outputPath`s are ever candidates for removal.
        let sourcePath = tempDir.appendingPathComponent("real_source.hevc").path
        FileManager.default.createFile(atPath: sourcePath, contents: Data("source".utf8))

        let steps = [
            PipelineStepDescriptor(
                stepNumber: 1,
                tool: "dovi_tool",
                description: "Extract",
                arguments: ["extract-rpu", "-i", sourcePath, "-o", tempDir.appendingPathComponent("rpu.bin").path],
                inputPath: sourcePath,
                outputPath: tempDir.appendingPathComponent("rpu.bin").path
            ),
        ]
        let mock = MockDualDynamicHDRStepRunner()
        let executor = DualDynamicHDRPipelineExecutor(stepRunner: mock)

        try await executor.execute(steps: steps)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath), "The real source file must never be deleted by cleanup")
    }

    // MARK: - DualDynamicHDRToolStepRunner (real dispatcher, unsupported-tool branch only)

    func test_toolStepRunner_unsupportedTool_throwsWithoutTouchingAnyRealBinary() async throws {
        let runner = DualDynamicHDRToolStepRunner()
        let step = PipelineStepDescriptor(
            stepNumber: 1,
            tool: "not_a_real_tool",
            description: "Bogus step",
            arguments: [],
            inputPath: "/dev/null",
            outputPath: tempDir.appendingPathComponent("out.bin").path
        )

        do {
            try await runner.run(step: step)
            XCTFail("Expected unsupportedTool to be thrown")
        } catch let error as DualDynamicHDRPipelineExecutorError {
            XCTAssertEqual(error, .unsupportedTool("not_a_real_tool"))
        }
    }
}
