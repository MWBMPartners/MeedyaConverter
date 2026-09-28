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
        // The profile-aware path emits an explicit video codec (`-c:v <encoder>`);
        // the copy-only fallback in buildStepArguments emits a bare `-c copy`.
        // Assert on that distinction rather than the mere absence of the word
        // "copy" (a full encode still legitimately copies e.g. subtitles via
        // `-c:s copy`).
        let a = resolved[0].arguments
        func hasPair(_ f: String, _ v: String) -> Bool {
            for i in a.indices.dropLast() where a[i] == f && a[i + 1] == v { return true }
            return false
        }
        XCTAssertTrue(a.contains("-c:v"), "expected an explicit video codec: \(a)")
        XCTAssertFalse(hasPair("-c:v", "copy"), "video must be re-encoded")
        XCTAssertFalse(hasPair("-c", "copy"), "must not be the copy-only fallback")
        XCTAssertTrue(a.contains("-i"))
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

    // MARK: - execute (the encode step reads its source's streams)

    /// Records every step's arguments as it runs.
    private actor RecordingRunner: PipelineStepRunning {
        private(set) var arguments: [[String]] = []
        func run(_ step: ResolvedPipelineStep) async throws { arguments.append(step.arguments) }
        func recorded() -> [[String]] { arguments }
    }

    private func maps(_ args: [String]) -> [String] {
        zip(args, args.dropFirst()).filter { $0.0 == "-map" }.map(\.1)
    }

    /// The encode step is built from its input's streams, as
    /// `EncodingEngine.encode` builds a job: an explicit output plan in the
    /// language policy's order. (Found in the independent review: this path
    /// never read the source's streams.)
    func test_execute_encodeStepUsesTheSourcesStreams() async throws {
        let runner = RecordingRunner()
        let executor = EncodingPipelineExecutor(stepRunner: runner, streamProber: { _ in [
            MediaStream(streamIndex: 0, streamType: .audio, language: "en", disposition: StreamDisposition()),
            MediaStream(streamIndex: 1, streamType: .video, disposition: StreamDisposition())
        ] })
        let pipeline = EncodingPipeline(name: "P", steps: [step("enc", .encode, profile: .remuxToMKV)])
        _ = try await executor.execute(pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out")
        let recorded = await runner.recorded()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(maps(recorded[0]), ["0:1", "0:0"], "video first, from the probed streams")
    }

    /// Streams that cannot be read, with per-stream settings in the
    /// profile: refused with the engine's own error, and nothing runs.
    func test_execute_refusesPerStreamSettingsWhenTheStreamsCannotBeRead() async {
        struct Unreadable: Error {}
        let runner = RecordingRunner()
        let executor = EncodingPipelineExecutor(stepRunner: runner, streamProber: { _ in throw Unreadable() })
        var profile = EncodingProfile.remuxToMKV
        profile.perStreamSettings = PerStreamSettings(audioOverrides: [1: AudioStreamOverride(codec: .flac)])
        let pipeline = EncodingPipeline(name: "P", steps: [step("enc", .encode, profile: profile)])
        do {
            _ = try await executor.execute(pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out")
            XCTFail("expected a refusal")
        } catch let error as EncodingEngineError {
            guard case .streamSelectionInvalid = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error: \(error)")
        }
        let recorded = await runner.recorded()
        XCTAssertTrue(recorded.isEmpty, "nothing ran")
    }

    /// Streams that cannot be read, with no per-stream settings: the step
    /// still runs, exactly as `resolve` built it.
    func test_execute_runsWithoutStreamsWhenNothingDependsOnThem() async throws {
        struct Unreadable: Error {}
        let runner = RecordingRunner()
        let executor = EncodingPipelineExecutor(stepRunner: runner, streamProber: { _ in throw Unreadable() })
        let pipeline = EncodingPipeline(name: "P", steps: [step("enc", .encode, profile: .webStandard)])
        let resolved = EncodingPipelineExecutor.resolve(pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out")
        _ = try await executor.execute(pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out")
        let recorded = await runner.recorded()
        XCTAssertEqual(recorded, [resolved[0].arguments])
    }

    // MARK: - Cover art and notes (second review, should-fix 5)

    /// A runner that "copies" a picture by writing a few bytes where the
    /// extraction step's output goes (its last argument), and records every
    /// command it was given.
    private actor CopyingRunner: PipelineStepRunning {
        private(set) var arguments: [[String]] = []
        func run(_ step: ResolvedPipelineStep) async throws {
            arguments.append(step.arguments)
            if step.arguments.contains("image2"), let output = step.arguments.last {
                try Data([0xFF, 0xD8, 0xFF]).write(to: URL(fileURLWithPath: output))
            }
        }
        func recorded() -> [[String]] { arguments }
    }

    /// Collects notes from `onNote` (called from any thread).
    private final class NoteBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ note: String) { lock.lock(); items.append(note); lock.unlock() }
        var notes: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    /// A cover picture as ffprobe describes it.
    private func cover(_ index: Int) -> MediaStream {
        MediaStream(streamIndex: index, streamType: .video, codecName: "mjpeg",
                    disposition: StreamDisposition(isAttachedPicture: true),
                    attachmentFileName: "cover.jpg", attachmentMimeType: "image/jpeg")
    }

    /// An encode step to MKV takes the same picture step as the full encode:
    /// the cover is copied out first (by the step runner), then ATTACHED —
    /// the second review found a pipeline mapped it as a stream, which ffmpeg
    /// makes an MJPEG video track in Matroska.
    func test_execute_encodeStepCopiesAndAttachesCoverArt() async throws {
        let runner = CopyingRunner()
        let streams = [
            MediaStream(streamIndex: 0, streamType: .video, codecName: "h264", disposition: StreamDisposition()),
            MediaStream(streamIndex: 1, streamType: .audio, language: "en", disposition: StreamDisposition()),
            cover(2)
        ]
        let executor = EncodingPipelineExecutor(stepRunner: runner, streamProber: { _ in streams })
        let notes = NoteBox()
        let pipeline = EncodingPipeline(name: "P", steps: [step("enc", .encode, profile: .remuxToMKV)])
        _ = try await executor.execute(pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out",
                                       onNote: { _, note in notes.add(note) })
        let recorded = await runner.recorded()
        XCTAssertEqual(recorded.count, 2, "the copy, then the encode")
        XCTAssertTrue(recorded[0].contains("image2"), "the first command copies the picture out")
        XCTAssertEqual(maps(recorded[1]), ["0:0", "0:1"], "the picture is not mapped")
        XCTAssertTrue(recorded[1].contains("-attach"), "it is attached")
        XCTAssertTrue(recorded[1].contains("-metadata:s:t:0") && recorded[1].contains("filename=cover.jpg"))
        XCTAssertEqual(notes.notes, [])
        // The copy's folder is removed after the step.
        let copy = try XCTUnwrap(recorded[0].last)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy))
    }

    /// The step's notes reach `onNote`: here a WebM output, which cannot
    /// hold cover art at all — left out, and said.
    func test_execute_encodeStepReportsItsNotes() async throws {
        let runner = RecordingRunner()
        let streams = [
            MediaStream(streamIndex: 0, streamType: .video, codecName: "vp9", disposition: StreamDisposition()),
            MediaStream(streamIndex: 1, streamType: .audio, language: "en", disposition: StreamDisposition()),
            cover(2)
        ]
        let executor = EncodingPipelineExecutor(stepRunner: runner, streamProber: { _ in streams })
        let notes = NoteBox()
        let pipeline = EncodingPipeline(name: "P", steps: [step("enc", .encode, profile: .webNextGen)])
        _ = try await executor.execute(pipeline: pipeline, sourcePath: "/s/m.mkv", outputDir: "/out",
                                       onNote: { _, note in notes.add(note) })
        let recorded = await runner.recorded()
        XCTAssertEqual(recorded.count, 1, "no copy for a file type that cannot hold pictures")
        XCTAssertEqual(maps(recorded[0]), ["0:0", "0:1"])
        XCTAssertEqual(notes.notes, [
            "Stream #2 is a picture attached to the file (cover art). ffmpeg cannot write pictures into this "
                + "file type (WebM), so it is left out."
        ])
    }

    func test_execute_emptyPipelineIsNoOpSuccess() async throws {
        let executor = EncodingPipelineExecutor(stepRunner: MockRunner())
        let result = try await executor.execute(
            pipeline: EncodingPipeline(name: "empty"), sourcePath: "/s/m.mkv", outputDir: "/out")
        XCTAssertTrue(result.deliverables.isEmpty)
        XCTAssertTrue(result.cleanedIntermediates.isEmpty)
    }
}
