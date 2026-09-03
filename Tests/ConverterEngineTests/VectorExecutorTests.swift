// ============================================================================
// MeedyaConverter — VectorExecutorTests (#473)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Coverage for the #473 executor layer: `RasterVectorExecutor`,
// `ProResVectorExecutor`, `SVGFragmentExtractor`, and the `BundledToolLocator`
// paths the vector views resolve potrace/vtracer through. No real potrace,
// vtracer, or ffmpeg process ever runs in CI — every executor test is driven
// against `VectorMockExternalToolRunner`; real-tool behaviour is verified
// only on the manual matrix (macOS Direct DMG, both arches).
//
// No `@testable import`: every symbol under test is `public`.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// MARK: - VectorMockExternalToolRunner

/// An `ExternalToolRunning` conformer backed by a caller-supplied `behaviour`
/// closure, so the executors can be exercised without any real subprocess.
/// Records every call under a lock.
final class VectorMockExternalToolRunner: ExternalToolRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(binaryPath: String, arguments: [String])] = []

    /// Every call `run(binaryPath:arguments:)` was invoked with, in order.
    var calls: [(binaryPath: String, arguments: [String])] { lock.withLock { _calls } }

    /// Given a call, returns the exit code; may write a file at the output
    /// path to simulate a tool. Defaults to "always succeeds, writes nothing".
    var behaviour: @Sendable (String, [String]) throws -> Int32 = { _, _ in 0 }

    func run(binaryPath: String, arguments: [String]) async throws -> ExternalToolResult {
        lock.withLock { _calls.append((binaryPath, arguments)) }   // withLock — never lock()/unlock() in async
        let code = try behaviour(binaryPath, arguments)
        return ExternalToolResult(exitCode: code, stderr: code == 0 ? "" : "simulated failure")
    }
}

// MARK: - VectorExecutorTests

final class VectorExecutorTests: XCTestCase {

    // =========================================================================
    // MARK: - 1. SVGFragmentExtractor
    // =========================================================================

    func test_svgFragmentExtractor_potraceStyleDocument() {
        let doc = """
        <?xml version="1.0" standalone="no"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.0//EN" "http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd">
        <svg xmlns="http://www.w3.org/2000/svg" width="100pt" height="50pt" viewBox="0 0 100 50">
        <metadata>Created by potrace</metadata>
        <g transform="translate(0,50) scale(0.1,-0.1)">
        <path d="M0 0"/>
        </g>
        </svg>
        """
        guard let body = SVGFragmentExtractor.body(of: doc) else {
            XCTFail("expected a non-nil body"); return
        }
        XCTAssertTrue(body.contains("<g transform=\"translate(0,50) scale(0.1,-0.1)\">"))
        XCTAssertTrue(body.contains("<path d=\"M0 0\"/>"))
        XCTAssertTrue(body.hasSuffix("</g>"))
    }

    func test_svgFragmentExtractor_vtracerStyleBareRoot() {
        let doc = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><path d=\"M1 1\"/></svg>"
        XCTAssertEqual(SVGFragmentExtractor.body(of: doc), "<path d=\"M1 1\"/>")
    }

    func test_svgFragmentExtractor_selfClosingRootReturnsEmptyString() {
        let doc = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"/>"
        XCTAssertEqual(SVGFragmentExtractor.body(of: doc), "")
    }

    func test_svgFragmentExtractor_missingClosingTagReturnsNil() {
        let doc = "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M1 1\"/>"
        XCTAssertNil(SVGFragmentExtractor.body(of: doc))
    }

    // =========================================================================
    // MARK: - 2. RasterVectorExecutor
    // =========================================================================

    func test_rasterVectorExecutor_outline_callsFFmpegThenPotrace() async throws {
        let runner = VectorMockExternalToolRunner()
        runner.behaviour = Self.svgWritingBehaviour()
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: "/usr/bin/potrace", vtracer: nil)
        let config = RasterToVectorConfig(inputFormat: .png, tracingMode: .outline, preset: .logoIcon)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")

        try await RasterVectorExecutor.convert(
            inputURL: URL(fileURLWithPath: "/tmp/in.png"),
            outputURL: outputURL, config: config, tools: tools, runner: runner
        )

        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].binaryPath, "/usr/bin/ffmpeg")
        XCTAssertEqual(runner.calls[0].arguments.last?.hasSuffix(".bmp"), true)
        XCTAssertEqual(runner.calls[1].binaryPath, "/usr/bin/potrace")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func test_rasterVectorExecutor_colorQuantization_callsVTracerWithPNGIntermediate() async throws {
        let runner = VectorMockExternalToolRunner()
        runner.behaviour = Self.svgWritingBehaviour()
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: nil, vtracer: "/usr/bin/vtracer")
        let config = RasterToVectorConfig(inputFormat: .png, tracingMode: .colorQuantization, preset: .illustration)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")

        try await RasterVectorExecutor.convert(
            inputURL: URL(fileURLWithPath: "/tmp/in.png"),
            outputURL: outputURL, config: config, tools: tools, runner: runner
        )

        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].arguments.last?.hasSuffix(".png"), true)
        XCTAssertEqual(runner.calls[1].binaryPath, "/usr/bin/vtracer")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func test_rasterVectorExecutor_missingToolThrowsToolNotFound() async throws {
        let runner = VectorMockExternalToolRunner()
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg")   // no potrace, no vtracer
        let config = RasterToVectorConfig(inputFormat: .png, tracingMode: .outline, preset: .logoIcon)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")

        do {
            try await RasterVectorExecutor.convert(
                inputURL: URL(fileURLWithPath: "/tmp/in.png"),
                outputURL: outputURL, config: config, tools: tools, runner: runner
            )
            XCTFail("expected tracingToolNotFound")
        } catch RasterVectorError.tracingToolNotFound(let tool) {
            XCTAssertEqual(tool, "potrace")
        }
        XCTAssertTrue(runner.calls.isEmpty, "should fail before running anything")
    }

    func test_rasterVectorExecutor_tracerFailureThrowsToolFailed() async throws {
        let runner = VectorMockExternalToolRunner()
        runner.behaviour = { binaryPath, _ in binaryPath == "/usr/bin/potrace" ? 2 : 0 }
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: "/usr/bin/potrace", vtracer: nil)
        let config = RasterToVectorConfig(inputFormat: .png, tracingMode: .outline, preset: .logoIcon)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")

        do {
            try await RasterVectorExecutor.convert(
                inputURL: URL(fileURLWithPath: "/tmp/in.png"),
                outputURL: outputURL, config: config, tools: tools, runner: runner
            )
            XCTFail("expected toolFailed")
        } catch RasterVectorError.toolFailed(let tool, let exitCode, _) {
            XCTAssertEqual(tool, "potrace")
            XCTAssertEqual(exitCode, 2)
        }
    }

    func test_rasterVectorExecutor_noOutputWrittenThrowsOutputMissing() async throws {
        let runner = VectorMockExternalToolRunner()   // default behaviour: succeeds, writes nothing
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: "/usr/bin/potrace", vtracer: nil)
        let config = RasterToVectorConfig(inputFormat: .png, tracingMode: .outline, preset: .logoIcon)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")

        do {
            try await RasterVectorExecutor.convert(
                inputURL: URL(fileURLWithPath: "/tmp/in.png"),
                outputURL: outputURL, config: config, tools: tools, runner: runner
            )
            XCTFail("expected outputMissing")
        } catch RasterVectorError.outputMissing {
            // expected
        }
    }

    // =========================================================================
    // MARK: - 3. ProResVectorExecutor
    // =========================================================================

    func test_proResVectorExecutor_assemblesThreeFramesIntoOneSVG() async throws {
        let runner = VectorMockExternalToolRunner()
        runner.behaviour = Self.frameExtractingAndSVGWritingBehaviour(frameCount: 3)
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: "/usr/bin/potrace", vtracer: "/usr/bin/vtracer")
        let config = ProResToVectorConfig(frameRate: .fps24)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")

        let frameCount = try await ProResVectorExecutor.convert(
            inputURL: URL(fileURLWithPath: "/tmp/in.mov"), outputURL: outputURL,
            sourceWidth: 100, sourceHeight: 50, config: config, tools: tools, runner: runner
        )

        XCTAssertEqual(frameCount, 3)
        let output = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(output.contains("data-frame-count=\"3\""))
        XCTAssertEqual(output.components(separatedBy: "id=\"frame-").count - 1, 3)
        XCTAssertEqual(output.components(separatedBy: "</g>").count - 1, 3)
        XCTAssertTrue(output.hasSuffix("</svg>"))
    }

    func test_proResVectorExecutor_alphaMatteOnlyForcesPotrace() async throws {
        let runner = VectorMockExternalToolRunner()
        runner.behaviour = Self.frameExtractingAndSVGWritingBehaviour(frameCount: 1)
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: "/usr/bin/potrace", vtracer: "/usr/bin/vtracer")
        let config = ProResToVectorConfig(
            alphaHandling: .alphaMatteOnly,
            tracing: RasterToVectorConfig(inputFormat: .png, tracingMode: .colorQuantization, preset: .custom)
        )
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")

        _ = try await ProResVectorExecutor.convert(
            inputURL: URL(fileURLWithPath: "/tmp/in.mov"), outputURL: outputURL,
            sourceWidth: 10, sourceHeight: 10, config: config, tools: tools, runner: runner
        )

        let tracerCalls = runner.calls.filter {
            $0.binaryPath == "/usr/bin/potrace" || $0.binaryPath == "/usr/bin/vtracer"
        }
        XCTAssertFalse(tracerCalls.isEmpty)
        XCTAssertTrue(tracerCalls.allSatisfy { $0.binaryPath == "/usr/bin/potrace" })
    }

    func test_proResVectorExecutor_nonSMILAnimationThrowsInvalidConfiguration() async throws {
        let runner = VectorMockExternalToolRunner()
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: "/usr/bin/potrace", vtracer: "/usr/bin/vtracer")
        let config = ProResToVectorConfig(animation: .cssKeyframes)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")

        do {
            _ = try await ProResVectorExecutor.convert(
                inputURL: URL(fileURLWithPath: "/tmp/in.mov"), outputURL: outputURL,
                sourceWidth: 10, sourceHeight: 10, config: config, tools: tools, runner: runner
            )
            XCTFail("expected invalidConfiguration")
        } catch RasterVectorError.invalidConfiguration {
            // expected
        }
        XCTAssertTrue(runner.calls.isEmpty, "should fail before running anything")
    }

    func test_proResVectorExecutor_progressStagesAreOrderedAndMonotonic() async throws {
        let runner = VectorMockExternalToolRunner()
        runner.behaviour = Self.frameExtractingAndSVGWritingBehaviour(frameCount: 3)
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: "/usr/bin/potrace", vtracer: "/usr/bin/vtracer")
        let config = ProResToVectorConfig(frameRate: .fps24)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")
        let recorder = VectorProgressRecorder()

        _ = try await ProResVectorExecutor.convert(
            inputURL: URL(fileURLWithPath: "/tmp/in.mov"), outputURL: outputURL,
            sourceWidth: 10, sourceHeight: 10, config: config, tools: tools, runner: runner,
            progress: { recorder.record($0) }
        )

        let observed = recorder.snapshot()
        XCTAssertEqual(observed.first?.stage, .extractingFrames)
        XCTAssertEqual(observed.last?.stage, .assembling)
        for (earlier, later) in zip(observed, observed.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.fraction, later.fraction)
        }
        let tracingFrames: [Int] = observed.compactMap {
            if case .tracing(let frame, _) = $0.stage { return frame }
            return nil
        }
        XCTAssertEqual(tracingFrames, [1, 2, 3])
    }

    /// Self-cancellation from inside the progress callback: cancelling the
    /// SAME task that is currently running it is guaranteed (by program
    /// order, not by timing) to be observed by that task's NEXT
    /// `Task.checkCancellation()` — the one at the top of the per-frame loop
    /// — so frame 1's processing never starts. A cross-thread "sleep then
    /// cancel from the test" design cannot make this guarantee: there is no
    /// bound on how much of frame 1 (or later frames) the executor might
    /// complete before the test's own `cancel()` call is scheduled.
    func test_proResVectorExecutor_cancellationStopsAfterFirstFrame() async throws {
        let runner = VectorMockExternalToolRunner()
        runner.behaviour = Self.frameExtractingAndSVGWritingBehaviour(frameCount: 3)
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: "/usr/bin/potrace", vtracer: "/usr/bin/vtracer")
        let config = ProResToVectorConfig(frameRate: .fps24)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")
        let box = VectorTaskBox()

        let task = Task<Int, Error> {
            try await ProResVectorExecutor.convert(
                inputURL: URL(fileURLWithPath: "/tmp/in.mov"), outputURL: outputURL,
                sourceWidth: 10, sourceHeight: 10, config: config, tools: tools, runner: runner,
                progress: { progress in
                    if case .tracing(let frame, _) = progress.stage, frame == 1 {
                        box.cancel()
                    }
                }
            )
        }
        box.set(task)

        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        }
        XCTAssertLessThanOrEqual(runner.calls.count, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func test_proResVectorExecutor_noFramesExtractedThrowsOperationFailed() async throws {
        let runner = VectorMockExternalToolRunner()
        runner.behaviour = Self.frameExtractingAndSVGWritingBehaviour(frameCount: 0)
        let tools = VectorToolPaths(ffmpeg: "/usr/bin/ffmpeg", potrace: "/usr/bin/potrace", vtracer: "/usr/bin/vtracer")
        let config = ProResToVectorConfig(frameRate: .fps24)
        let outputURL = try makeTempDir().appendingPathComponent("out.svg")

        do {
            _ = try await ProResVectorExecutor.convert(
                inputURL: URL(fileURLWithPath: "/tmp/in.mov"), outputURL: outputURL,
                sourceWidth: 10, sourceHeight: 10, config: config, tools: tools, runner: runner
            )
            XCTFail("expected operationFailed")
        } catch RasterVectorError.operationFailed {
            // expected
        }
    }

    func test_assembleAnimatedSVG_twoFrameBodies() throws {
        let svg = try ProResVectorExecutor.assembleAnimatedSVG(
            frameBodies: ["<path d=\"A\"/>", "<path d=\"B\"/>"],
            widthPixels: 100, heightPixels: 50, frameRate: 24.0, method: .smil
        )
        XCTAssertTrue(svg.contains("data-frame-count=\"2\""))
        XCTAssertTrue(svg.contains("id=\"frame-0\""))
        XCTAssertTrue(svg.contains("id=\"frame-1\""))
        XCTAssertTrue(svg.contains("<path d=\"A\"/>"))
        XCTAssertTrue(svg.contains("<path d=\"B\"/>"))
        XCTAssertEqual(svg.components(separatedBy: "</g>").count - 1, 2)
        XCTAssertTrue(svg.hasSuffix("</svg>"))
    }

    // =========================================================================
    // MARK: - 4. BundledToolLocator (potrace/vtracer resolution)
    // =========================================================================

    func test_locator_userOverridePathIsUsed() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let binary = tempDir.appendingPathComponent("potrace")
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let locator = BundledToolLocator(toolName: "potrace", userOverridePath: binary.path)
        XCTAssertEqual(try locator.locate(), binary.path)
    }

    func test_locator_uniqueToolIsNeverFound() {
        let locator = BundledToolLocator(toolName: uniqueToolName())
        XCTAssertThrowsError(try locator.locate()) { error in
            guard case ToolLocatorError.toolNotFound = error else {
                XCTFail("expected toolNotFound, got \(error)"); return
            }
        }
    }

    // =========================================================================
    // MARK: - Fixtures
    // =========================================================================

    /// A `behaviour` for `VectorMockExternalToolRunner` that simulates "any
    /// non-ffmpeg call writes a canned SVG at its `-o` argument" — enough for
    /// `RasterVectorExecutor` tests, which never call ffmpeg's frame
    /// extraction (only the single-frame pre-pass, whose output nothing
    /// checks).
    private static func svgWritingBehaviour() -> @Sendable (String, [String]) throws -> Int32 {
        { binaryPath, arguments in
            guard !binaryPath.hasSuffix("ffmpeg"), let idx = arguments.firstIndex(of: "-o") else {
                return 0
            }
            let svg = "<?xml version=\"1.0\"?><svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0\"/></svg>"
            FileManager.default.createFile(atPath: arguments[idx + 1], contents: Data(svg.utf8))
            return 0
        }
    }

    /// Extends `svgWritingBehaviour` to also simulate ffmpeg's frame-dump
    /// call (the one whose last argument is a `%06d`-style pattern): writes
    /// `frameCount` placeholder `frame_NNNNNN.png` files next to it, so
    /// `ProResVectorExecutor` finds real files to iterate.
    private static func frameExtractingAndSVGWritingBehaviour(
        frameCount: Int
    ) -> @Sendable (String, [String]) throws -> Int32 {
        let svgBehaviour = svgWritingBehaviour()
        return { binaryPath, arguments in
            if binaryPath.hasSuffix("ffmpeg"), let pattern = arguments.last, pattern.contains("%06d") {
                let directory = (pattern as NSString).deletingLastPathComponent
                for index in 0..<frameCount {
                    let name = String(format: "frame_%06d.png", index)
                    let path = (directory as NSString).appendingPathComponent(name)
                    FileManager.default.createFile(atPath: path, contents: Data())
                }
                return 0
            }
            return try svgBehaviour(binaryPath, arguments)
        }
    }

    private func makeTempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meedya-vector-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func uniqueToolName() -> String {
        "vector-tool-test-\(UUID().uuidString.prefix(8))"
    }
}

// MARK: - VectorProgressRecorder

/// Records `ProResVectorProgress` events under a lock, for assertions about
/// stage ordering and monotonic fractions.
final class VectorProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ProResVectorProgress] = []

    func record(_ event: ProResVectorProgress) {
        lock.withLock { events.append(event) }
    }

    func snapshot() -> [ProResVectorProgress] {
        lock.withLock { events }
    }
}

// MARK: - VectorTaskBox

/// Holds a `Task` handle so a `@Sendable` progress closure running INSIDE
/// that task can cancel it — see
/// `test_proResVectorExecutor_cancellationStopsAfterFirstFrame`'s doc comment
/// for why this (rather than a cross-thread "sleep, then cancel from the
/// test") is the only way to deterministically bound how many calls happen
/// after cancellation.
final class VectorTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Int, Error>?

    func set(_ task: Task<Int, Error>) {
        lock.withLock { self.task = task }
    }

    func cancel() {
        lock.withLock { task }?.cancel()
    }
}
