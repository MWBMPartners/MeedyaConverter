// ============================================================================
// MeedyaConverter — SmartCropVideoAnalyzerTests (Issue #299)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Pure, CI-runnable tests for `SmartCropVideoAnalyzer` — no real ffmpeg /
// Vision is invoked for the orchestration tests, which drive the analyzer
// through mocks conforming to the public `SmartCropFrameExtracting` /
// `SubjectDetecting` seams. `FFmpegFrameExtractor` itself is exercised
// against a fake ffmpeg (a shell script), mirroring the fixture-script
// pattern in `FFmpegProbeSuiteCoreCodecTests`.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`).
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

// MARK: - MockFrameExtractor

/// Records the timestamps and output URLs it was asked to extract, in call
/// order. Simulates failure for configured call indices, and an artificial
/// per-call delay for the cancellation test.
final class MockFrameExtractor: SmartCropFrameExtracting, @unchecked Sendable {
    struct SimulatedFailure: Error {}

    private let lock = NSLock()
    private var callCount = 0
    private var recordedTimestamps: [TimeInterval] = []
    private var recordedOutputURLs: [URL] = []

    /// Call indices (0-based, in call order) that should throw `SimulatedFailure`.
    var failAtCallIndices: Set<Int> = []
    /// Artificial delay before each call resolves — used to exercise cancellation.
    var delay: Duration = .zero

    var requestedTimestamps: [TimeInterval] {
        lock.withLock { recordedTimestamps }
    }
    var outputURLs: [URL] {
        lock.withLock { recordedOutputURLs }
    }

    func extractFrame(from videoURL: URL, at timestamp: TimeInterval, to outputURL: URL) async throws {
        let callIndex = lock.withLock { () -> Int in
            let index = callCount
            callCount += 1
            recordedTimestamps.append(timestamp)
            recordedOutputURLs.append(outputURL)
            return index
        }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if failAtCallIndices.contains(callIndex) {
            throw SimulatedFailure()
        }
        try Data("frame-\(callIndex)".utf8).write(to: outputURL)
    }
}

// MARK: - MockSubjectDetector

/// Returns canned per-frame results in call order; `[]` once exhausted.
final class MockSubjectDetector: SubjectDetecting, @unchecked Sendable {
    private let lock = NSLock()
    private var nextIndex = 0
    private let results: [[SubjectDetectionResult]]
    private var recordedURLs: [URL] = []

    init(results: [[SubjectDetectionResult]]) {
        self.results = results
    }

    var receivedURLs: [URL] {
        lock.withLock { recordedURLs }
    }

    func detectSubjects(imageURL: URL) async -> [SubjectDetectionResult] {
        lock.withLock {
            recordedURLs.append(imageURL)
            guard nextIndex < results.count else { return [] }
            defer { nextIndex += 1 }
            return results[nextIndex]
        }
    }
}

// MARK: - SmartCropProgressRecorder

/// Records `analyze`'s progress callback invocations under a lock — the
/// callback is a plain (non-async) `@Sendable` closure, so a lock-guarded
/// sink (not an actor) keeps ordering deterministic.
final class SmartCropProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SmartCropVideoProgress] = []

    var values: [SmartCropVideoProgress] {
        lock.withLock { recorded }
    }

    func record(_ progress: SmartCropVideoProgress) {
        lock.withLock { recorded.append(progress) }
    }
}

// MARK: - SmartCropVideoAnalyzerTests

final class SmartCropVideoAnalyzerTests: XCTestCase {

    // MARK: - Fixture helpers

    private var fixturesToCleanUp: [String] = []

    override func tearDown() {
        for path in fixturesToCleanUp {
            try? FileManager.default.removeItem(atPath: path)
        }
        fixturesToCleanUp.removeAll()
        super.tearDown()
    }

    /// Vision-coordinate (bottom-left origin) face detection.
    private func face(x: Double, y: Double, w: Double, h: Double, conf: Double = 0.9) -> SubjectDetectionResult {
        SubjectDetectionResult(boundingBox: CGRect(x: x, y: y, width: w, height: h), confidence: conf, subjectType: .face)
    }

    /// Vision-coordinate (bottom-left origin) saliency detection.
    private func saliency(x: Double, y: Double, w: Double, h: Double, conf: Double = 0.5) -> SubjectDetectionResult {
        SubjectDetectionResult(boundingBox: CGRect(x: x, y: y, width: w, height: h), confidence: conf, subjectType: .saliency)
    }

    /// A minimal summary carrying only the centroid the geometry tests need.
    private func summary(centroid: CGPoint?) -> SmartCropSubjectSummary {
        SmartCropSubjectSummary(
            framesAnalysed: 1, framesWithSubjects: centroid == nil ? 0 : 1,
            faceCount: 0, centroid: centroid, extent: nil)
    }

    /// Writes an executable shell-script fake ffmpeg binary. Mirrors
    /// `FFmpegProbeSuiteCoreCodecTests.makeFFprobeFixture`.
    private func makeFakeFFmpeg(script: String) throws -> String {
        let scriptPath = NSTemporaryDirectory() + "smartcrop-fake-ffmpeg-\(UUID().uuidString).sh"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        fixturesToCleanUp.append(scriptPath)
        return scriptPath
    }

    // MARK: - SmartCropSampling.timestamps

    func test_timestamps_nilDuration_returnsZero() {
        XCTAssertEqual(SmartCropSampling.timestamps(duration: nil, count: 9), [0])
    }

    func test_timestamps_countOne_isMidpoint() {
        XCTAssertEqual(SmartCropSampling.timestamps(duration: 100, count: 1), [50])
    }

    func test_timestamps_nine_areMidpointsWithin5To95Percent() {
        let timestamps = SmartCropSampling.timestamps(duration: 100, count: 9)
        XCTAssertEqual(timestamps.count, 9)
        XCTAssertEqual(timestamps.first!, 10, accuracy: 1e-9)
        XCTAssertEqual(timestamps.last!, 90, accuracy: 1e-9)
        XCTAssertEqual(timestamps, timestamps.sorted())
        XCTAssertEqual(Set(timestamps).count, timestamps.count)
    }

    func test_timestamps_countClampedToAtLeastOne() {
        XCTAssertEqual(SmartCropSampling.timestamps(duration: 100, count: 0).count, 1)
    }

    // MARK: - SmartCropVideoAnalyzer.summarise

    func test_summarise_empty_hasNilCentroidAndExtent() {
        let summary = SmartCropVideoAnalyzer.summarise(perFrame: [])
        XCTAssertEqual(summary.framesAnalysed, 0)
        XCTAssertEqual(summary.framesWithSubjects, 0)
        XCTAssertEqual(summary.faceCount, 0)
        XCTAssertNil(summary.centroid)
        XCTAssertNil(summary.extent)
    }

    func test_summarise_convertsVisionBottomLeftToTopLeft() {
        let perFrame = [[face(x: 0.1, y: 0.6, w: 0.2, h: 0.2)]]
        let summary = SmartCropVideoAnalyzer.summarise(perFrame: perFrame)
        XCTAssertNotNil(summary.extent)
        XCTAssertEqual(summary.extent!.origin.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(summary.extent!.origin.y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(summary.extent!.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(summary.extent!.height, 0.2, accuracy: 1e-9)
        XCTAssertNotNil(summary.centroid)
        XCTAssertEqual(summary.centroid!.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(summary.centroid!.y, 0.3, accuracy: 1e-9)
    }

    func test_summarise_prefersFacesOverSaliencyWithinAFrame() {
        let frame = [
            face(x: 0.4, y: 0.4, w: 0.2, h: 0.2),
            saliency(x: 0.0, y: 0.0, w: 0.1, h: 0.1)
        ]
        let summary = SmartCropVideoAnalyzer.summarise(perFrame: [frame])
        // The saliency box (bottom-left corner) must not have widened the extent.
        XCTAssertEqual(summary.extent!.origin.x, 0.4, accuracy: 1e-9)
        XCTAssertEqual(summary.extent!.width, 0.2, accuracy: 1e-9)
    }

    func test_summarise_usesSaliencyWhenFrameHasNoFaces() {
        let frame = [saliency(x: 0.3, y: 0.3, w: 0.2, h: 0.2)]
        let summary = SmartCropVideoAnalyzer.summarise(perFrame: [frame])
        XCTAssertEqual(summary.extent!.origin.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(summary.extent!.width, 0.2, accuracy: 1e-9)
    }

    func test_summarise_medianCentroidIgnoresOutlierFrame() {
        // Four frames with a face centred at x≈0.3, one outlier at x=0.95.
        let normal = [face(x: 0.25, y: 0.45, w: 0.1, h: 0.1)]   // midX = 0.3
        let outlier = [face(x: 0.90, y: 0.45, w: 0.1, h: 0.1)]  // midX = 0.95
        let perFrame = [normal, normal, normal, normal, outlier]
        let summary = SmartCropVideoAnalyzer.summarise(perFrame: perFrame)
        XCTAssertEqual(summary.centroid!.x, 0.3, accuracy: 1e-9)
    }

    func test_summarise_countsFramesWithSubjectsAndFaces() {
        let perFrame: [[SubjectDetectionResult]] = [
            [face(x: 0.1, y: 0.1, w: 0.1, h: 0.1), face(x: 0.5, y: 0.5, w: 0.1, h: 0.1)],
            [],
            [saliency(x: 0.2, y: 0.2, w: 0.1, h: 0.1)]
        ]
        let summary = SmartCropVideoAnalyzer.summarise(perFrame: perFrame)
        XCTAssertEqual(summary.framesAnalysed, 3)
        XCTAssertEqual(summary.framesWithSubjects, 2)
        XCTAssertEqual(summary.faceCount, 2)
    }

    // MARK: - SmartCropVideoAnalyzer.cropRect

    func test_cropRect_noSubjects_isCentredMaxSize_16x9To9x16() {
        let crop = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: nil), sourceWidth: 1920, sourceHeight: 1080,
            targetAspectRatio: 9.0 / 16.0, useRuleOfThirds: false)
        XCTAssertEqual(crop, CropRect(width: 606, height: 1080, x: 656, y: 0))
    }

    func test_cropRect_allValuesEven() {
        let crop = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: nil), sourceWidth: 1919, sourceHeight: 1079,
            targetAspectRatio: 4.0 / 3.0, useRuleOfThirds: false)
        XCTAssertEqual(crop.width % 2, 0)
        XCTAssertEqual(crop.height % 2, 0)
        XCTAssertEqual(crop.x % 2, 0)
        XCTAssertEqual(crop.y % 2, 0)
        XCTAssertLessThanOrEqual(crop.x + crop.width, 1919)
        XCTAssertLessThanOrEqual(crop.y + crop.height, 1079)
    }

    func test_cropRect_centroidShiftsOrigin() {
        let crop = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: CGPoint(x: 0.25, y: 0.5)),
            sourceWidth: 1920, sourceHeight: 1080,
            targetAspectRatio: 9.0 / 16.0, useRuleOfThirds: false)
        XCTAssertEqual(crop.x, 176)
    }

    func test_cropRect_clampsAtEdge() {
        let crop = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: CGPoint(x: 0.05, y: 0.5)),
            sourceWidth: 1920, sourceHeight: 1080,
            targetAspectRatio: 9.0 / 16.0, useRuleOfThirds: false)
        XCTAssertEqual(crop.x, 0)
    }

    func test_cropRect_insideActiveArea_letterbox() {
        let activeArea = CropRect(width: 1920, height: 800, x: 0, y: 140)
        let crop = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: nil), sourceWidth: 1920, sourceHeight: 1080,
            targetAspectRatio: 9.0 / 16.0, useRuleOfThirds: false, activeArea: activeArea)
        XCTAssertEqual(crop, CropRect(width: 450, height: 800, x: 734, y: 140))
    }

    func test_cropRect_activeAreaLargerThanSourceIsClampedToSource() {
        let oversizedArea = CropRect(width: 4000, height: 3000, x: 0, y: 0)
        let crop = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: nil), sourceWidth: 1920, sourceHeight: 1080,
            targetAspectRatio: 16.0 / 9.0, useRuleOfThirds: false, activeArea: oversizedArea)
        XCTAssertLessThanOrEqual(crop.width, 1920)
        XCTAssertLessThanOrEqual(crop.height, 1080)
        XCTAssertGreaterThanOrEqual(crop.x, 0)
        XCTAssertGreaterThanOrEqual(crop.y, 0)
    }

    func test_cropRect_ruleOfThirds_picksLeastClampedThird() {
        let centred = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: CGPoint(x: 0.7, y: 0.5)),
            sourceWidth: 1920, sourceHeight: 1080,
            targetAspectRatio: 1.0, useRuleOfThirds: false)
        XCTAssertEqual(centred.x, 804)

        let thirded = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: CGPoint(x: 0.7, y: 0.5)),
            sourceWidth: 1920, sourceHeight: 1080,
            targetAspectRatio: 1.0, useRuleOfThirds: true)
        XCTAssertEqual(thirded.x, 624)
        XCTAssertEqual(thirded.y, 0)
    }

    func test_cropRect_ruleOfThirds_withoutSubjectsIsCentred() {
        let crop = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: nil), sourceWidth: 1920, sourceHeight: 1080,
            targetAspectRatio: 9.0 / 16.0, useRuleOfThirds: true)
        XCTAssertEqual(crop, CropRect(width: 606, height: 1080, x: 656, y: 0))
    }

    func test_cropRect_targetWiderThanSource_usesFullWidth() {
        let crop = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: nil), sourceWidth: 1080, sourceHeight: 1920,
            targetAspectRatio: 16.0 / 9.0, useRuleOfThirds: false)
        XCTAssertEqual(crop, CropRect(width: 1080, height: 606, x: 0, y: 656))
    }

    func test_cropRect_filterStringIsFFmpegSyntax() {
        let crop = SmartCropVideoAnalyzer.cropRect(
            summary: summary(centroid: nil), sourceWidth: 1920, sourceHeight: 1080,
            targetAspectRatio: 9.0 / 16.0, useRuleOfThirds: false)
        XCTAssertEqual(crop.filterString, "crop=606:1080:656:0")
    }

    // MARK: - SmartCropVideoAnalyzer.analyze (mocked)

    private func makeRequest(sampleCount: Int = 9, duration: TimeInterval = 100) -> SmartCropVideoRequest {
        SmartCropVideoRequest(videoURL: URL(fileURLWithPath: "/tmp/smartcrop-analyzer-test.mp4"),
                              duration: duration, sampleCount: sampleCount)
    }

    func test_analyze_extractsPlannedTimestampsInOrder() async throws {
        let extractor = MockFrameExtractor()
        let detector = MockSubjectDetector(results: [])
        let analyzer = SmartCropVideoAnalyzer(frameExtractor: extractor, subjectDetector: detector)
        let request = makeRequest(sampleCount: 9)
        let result = try await analyzer.analyze(request)
        XCTAssertEqual(extractor.requestedTimestamps, result.plannedTimestamps)
    }

    func test_analyze_skipsFailedFramesAndCountsThem() async throws {
        let extractor = MockFrameExtractor()
        extractor.failAtCallIndices = [1, 7]
        let detector = MockSubjectDetector(results: [])
        let analyzer = SmartCropVideoAnalyzer(frameExtractor: extractor, subjectDetector: detector)
        let request = makeRequest(sampleCount: 9)
        let result = try await analyzer.analyze(request)
        XCTAssertEqual(result.perFrameSubjects.count, 7)
        XCTAssertEqual(result.skippedFrames, 2)
        XCTAssertEqual(result.analysedTimestamps.count, 7)
        let planned = result.plannedTimestamps
        XCTAssertFalse(result.analysedTimestamps.contains(planned[1]))
        XCTAssertFalse(result.analysedTimestamps.contains(planned[7]))
    }

    func test_analyze_throwsWhenEveryFrameFails() async throws {
        let extractor = MockFrameExtractor()
        extractor.failAtCallIndices = Set(0..<9)
        let detector = MockSubjectDetector(results: [])
        let analyzer = SmartCropVideoAnalyzer(frameExtractor: extractor, subjectDetector: detector)
        let request = makeRequest(sampleCount: 9)
        do {
            _ = try await analyzer.analyze(request)
            XCTFail("expected noFramesExtracted")
        } catch let error as SmartCropVideoError {
            guard case .noFramesExtracted(let attempted, _) = error else {
                XCTFail("wrong case: \(error)")
                return
            }
            XCTAssertEqual(attempted, 9)
        }
    }

    func test_analyze_previewIsMiddleFrameBytes() async throws {
        let extractor = MockFrameExtractor()
        let detector = MockSubjectDetector(results: [])
        let analyzer = SmartCropVideoAnalyzer(frameExtractor: extractor, subjectDetector: detector)
        let request = makeRequest(sampleCount: 9)
        let result = try await analyzer.analyze(request)
        XCTAssertEqual(result.previewFramePNG, Data("frame-4".utf8))
        XCTAssertEqual(result.previewFrameIndex, 4)
    }

    func test_analyze_previewFallsBackToNearestExtractedFrame() async throws {
        let extractor = MockFrameExtractor()
        extractor.failAtCallIndices = [4]
        let detector = MockSubjectDetector(results: [])
        let analyzer = SmartCropVideoAnalyzer(frameExtractor: extractor, subjectDetector: detector)
        let request = makeRequest(sampleCount: 9)
        let result = try await analyzer.analyze(request)
        XCTAssertNotNil(result.previewFramePNG)
        let bytes = result.previewFramePNG!
        XCTAssertTrue(bytes == Data("frame-3".utf8) || bytes == Data("frame-5".utf8))
    }

    func test_analyze_progressFiresPerPlannedFrameIncludingSkipped() async throws {
        let extractor = MockFrameExtractor()
        extractor.failAtCallIndices = [2]
        let detector = MockSubjectDetector(results: [])
        let analyzer = SmartCropVideoAnalyzer(frameExtractor: extractor, subjectDetector: detector)
        let request = makeRequest(sampleCount: 9)
        let recorder = SmartCropProgressRecorder()
        _ = try await analyzer.analyze(request) { recorder.record($0) }
        let values = recorder.values
        XCTAssertEqual(values.count, 9)
        XCTAssertEqual(values.last, SmartCropVideoProgress(completedFrames: 9, totalFrames: 9))
        let completed = values.map(\.completedFrames)
        XCTAssertEqual(completed, completed.sorted())
        XCTAssertEqual(Set(completed).count, completed.count)
    }

    func test_analyze_cancellationStopsAndThrowsCancellationError() async throws {
        let extractor = MockFrameExtractor()
        extractor.delay = .milliseconds(200)
        let detector = MockSubjectDetector(results: [])
        let analyzer = SmartCropVideoAnalyzer(frameExtractor: extractor, subjectDetector: detector)
        let request = makeRequest(sampleCount: 9)

        let task = Task<SmartCropVideoResult, Error> {
            try await analyzer.analyze(request)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let outcome = await task.result
        switch outcome {
        case .success:
            XCTFail("expected cancellation")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertLessThanOrEqual(extractor.requestedTimestamps.count, 2)
    }

    func test_analyze_removesScratchDirectory() async throws {
        let extractor = MockFrameExtractor()
        let detector = MockSubjectDetector(results: [])
        let analyzer = SmartCropVideoAnalyzer(frameExtractor: extractor, subjectDetector: detector)
        let request = makeRequest(sampleCount: 3)
        _ = try await analyzer.analyze(request)
        let scratchDir = extractor.outputURLs[0].deletingLastPathComponent()
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratchDir.path))
    }

    func test_analyze_summaryReflectsDetectorResults() async throws {
        let extractor = MockFrameExtractor()
        let detector = MockSubjectDetector(results: [
            [face(x: 0.4, y: 0.4, w: 0.2, h: 0.2)],
            [],
            [face(x: 0.4, y: 0.4, w: 0.2, h: 0.2)]
        ])
        let analyzer = SmartCropVideoAnalyzer(frameExtractor: extractor, subjectDetector: detector)
        let request = makeRequest(sampleCount: 3)
        let result = try await analyzer.analyze(request)
        XCTAssertEqual(result.summary.framesAnalysed, 3)
        XCTAssertEqual(result.summary.framesWithSubjects, 2)
        XCTAssertEqual(result.summary.faceCount, 2)
    }

    // MARK: - FFmpegFrameExtractor.arguments (pure)

    func test_frameExtractor_arguments_matchComparisonCapture() {
        let outputURL = URL(fileURLWithPath: "/tmp/smartcrop-frame.png")
        let args = FFmpegFrameExtractor.arguments(
            videoURL: URL(fileURLWithPath: "/tmp/input.mp4"), timestamp: 2.5,
            outputURL: outputURL, frameWidth: 960)
        XCTAssertTrue(zip(args, args.dropFirst()).contains { $0 == "-ss" && $1 == "00:00:02.500" })
        XCTAssertTrue(zip(args, args.dropFirst()).contains { $0 == "-frames:v" && $1 == "1" })
        XCTAssertTrue(zip(args, args.dropFirst()).contains { $0 == "-vf" && $1 == "scale=960:-2" })
        XCTAssertTrue(zip(args, args.dropFirst()).contains { $0 == "-c:v" && $1 == "png" })
        XCTAssertEqual(args.last, outputURL.path)
    }

    // MARK: - FFmpegFrameExtractor (real controller, fake ffmpeg script)

    func test_frameExtractor_succeedsWhenToolWritesOutput() async throws {
        let script = """
        #!/bin/sh
        out=""
        for a in "$@"; do
            case "$a" in
                *.png) out="$a";;
            esac
        done
        [ -n "$out" ] && printf 'PNGBYTES' > "$out"
        exit 0
        """
        let ffmpegPath = try makeFakeFFmpeg(script: script)
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "smartcrop-extractor-\(UUID().uuidString).png")
        fixturesToCleanUp.append(outputURL.path)
        let extractor = FFmpegFrameExtractor(ffmpegPath: ffmpegPath)
        try await extractor.extractFrame(from: URL(fileURLWithPath: "/tmp/input.mp4"), at: 1.0, to: outputURL)
        let data = try Data(contentsOf: outputURL)
        XCTAssertEqual(data, Data("PNGBYTES".utf8))
    }

    func test_frameExtractor_throwsWhenToolWritesNothing() async throws {
        let script = """
        #!/bin/sh
        exit 0
        """
        let ffmpegPath = try makeFakeFFmpeg(script: script)
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "smartcrop-extractor-\(UUID().uuidString).png")
        let extractor = FFmpegFrameExtractor(ffmpegPath: ffmpegPath)
        do {
            try await extractor.extractFrame(from: URL(fileURLWithPath: "/tmp/input.mp4"), at: 1.0, to: outputURL)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is FFmpegProcessError)
        }
    }

    func test_frameExtractor_throwsOnNonZeroExit() async throws {
        let script = """
        #!/bin/sh
        exit 1
        """
        let ffmpegPath = try makeFakeFFmpeg(script: script)
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "smartcrop-extractor-\(UUID().uuidString).png")
        let extractor = FFmpegFrameExtractor(ffmpegPath: ffmpegPath)
        do {
            try await extractor.extractFrame(from: URL(fileURLWithPath: "/tmp/input.mp4"), at: 1.0, to: outputURL)
            XCTFail("expected an error")
        } catch let error as FFmpegProcessError {
            guard case .processFailure(let exitCode, _) = error else {
                XCTFail("wrong case: \(error)")
                return
            }
            XCTAssertEqual(exitCode, 1)
        }
    }
}
