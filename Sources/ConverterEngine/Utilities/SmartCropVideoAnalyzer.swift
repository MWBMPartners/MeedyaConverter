// ============================================================================
// MeedyaConverter — SmartCropVideoAnalyzer (Issue #299)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import CoreGraphics

// MARK: - Seams

/// "Write one video frame as a PNG". `FFmpegFrameExtractor` is the production
/// conformer; tests inject a mock that writes canned bytes.
public protocol SmartCropFrameExtracting: Sendable {
    func extractFrame(from videoURL: URL, at timestamp: TimeInterval, to outputURL: URL) async throws
}

/// "Find subjects in one image". `SmartCropDetector` (Vision) is the
/// production conformer; tests inject canned results.
public protocol SubjectDetecting: Sendable {
    func detectSubjects(imageURL: URL) async -> [SubjectDetectionResult]
}

// MARK: - FFmpegFrameExtractor

/// Extracts one frame per call through `FFmpegProcessController`, using the
/// same argv as `ComparisonCapture.captureFrame` (fast `-ss` before `-i`,
/// `-frames:v 1`, `scale=<frameWidth>:-2`, PNG). Success requires exit 0 AND
/// the output file to exist: a seek past the end of the file makes ffmpeg exit
/// 0 without writing anything ("Output file is empty").
public struct FFmpegFrameExtractor: SmartCropFrameExtracting {
    public let ffmpegPath: String
    /// Width the frame is scaled to for analysis and preview (default 960).
    /// Vision's results are normalised, so this never affects crop coordinates.
    public let frameWidth: Int

    public init(ffmpegPath: String, frameWidth: Int = 960) {
        self.ffmpegPath = ffmpegPath
        self.frameWidth = frameWidth
    }

    /// The ffmpeg argv (excluding the binary and the flags
    /// `FFmpegProcessController` adds around it).
    public static func arguments(videoURL: URL, timestamp: TimeInterval, outputURL: URL, frameWidth: Int) -> [String] {
        ComparisonCapture.captureFrame(
            inputPath: videoURL.path, outputPath: outputURL.path,
            timestamp: timestamp, width: frameWidth)
    }

    public func extractFrame(from videoURL: URL, at timestamp: TimeInterval, to outputURL: URL) async throws {
        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        let stream = try controller.startEncoding(
            arguments: Self.arguments(videoURL: videoURL, timestamp: timestamp,
                                      outputURL: outputURL, frameWidth: frameWidth))
        for await _ in stream {
            if Task.isCancelled { controller.stopEncoding(); break }
        }
        if Task.isCancelled { throw CancellationError() }
        if let code = controller.exitCode, code != 0 {
            throw FFmpegProcessError.processFailure(exitCode: code, stderr: controller.errorOutput)
        }
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw FFmpegProcessError.processFailure(
                exitCode: controller.exitCode ?? 0,
                stderr: "ffmpeg wrote no frame for \(timestamp)s (seek past the end of the file?)")
        }
    }
}

// MARK: - Sampling

public enum SmartCropSampling {
    /// `count` sample times (≥1) at the midpoints of equal slices of the middle
    /// 90 % of the video (first/last 5 % skipped, as `CropDetector` does, to
    /// avoid intros/credits). Unknown or non-positive duration → `[0]`.
    /// `count == 1` → exactly the middle of the video.
    public static func timestamps(duration: TimeInterval?, count: Int) -> [TimeInterval] {
        let n = max(1, count)
        guard let duration, duration.isFinite, duration > 0 else { return [0] }
        let start = duration * 0.05
        let span = duration * 0.90
        return (0..<n).map { start + (Double($0) + 0.5) * span / Double(n) }
    }
}

// MARK: - Value types

public struct SmartCropSubjectSummary: Sendable, Equatable {
    public let framesAnalysed: Int
    public let framesWithSubjects: Int
    /// Total face detections across all frames (a face seen in 5 frames counts 5).
    public let faceCount: Int
    /// Component-wise MEDIAN of the per-frame interest-rect centres; normalised,
    /// top-left origin. nil when no frame had a subject.
    public let centroid: CGPoint?
    /// Union of the per-frame interest rects; normalised, top-left origin. nil when none.
    public let extent: CGRect?

    public init(framesAnalysed: Int, framesWithSubjects: Int, faceCount: Int, centroid: CGPoint?, extent: CGRect?) {
        self.framesAnalysed = framesAnalysed
        self.framesWithSubjects = framesWithSubjects
        self.faceCount = faceCount
        self.centroid = centroid
        self.extent = extent
    }
}

public struct SmartCropVideoRequest: Sendable {
    public var videoURL: URL
    public var duration: TimeInterval?
    public var sampleCount: Int

    public init(videoURL: URL, duration: TimeInterval?, sampleCount: Int = 9) {
        self.videoURL = videoURL
        self.duration = duration
        self.sampleCount = sampleCount
    }
}

public struct SmartCropVideoProgress: Sendable, Equatable {
    public let completedFrames: Int   // planned frames finished (extracted OR skipped)
    public let totalFrames: Int

    public init(completedFrames: Int, totalFrames: Int) {
        self.completedFrames = completedFrames
        self.totalFrames = totalFrames
    }
}

public struct SmartCropVideoResult: Sendable {
    public let plannedTimestamps: [TimeInterval]
    /// Timestamps that yielded a frame, in order; `perFrameSubjects[i]` belongs to `analysedTimestamps[i]`.
    public let analysedTimestamps: [TimeInterval]
    public let perFrameSubjects: [[SubjectDetectionResult]]
    public let skippedFrames: Int
    public let summary: SmartCropSubjectSummary
    /// PNG bytes of the extracted frame nearest the middle sample, for preview.
    public let previewFramePNG: Data?
    /// Index into `perFrameSubjects` of the preview frame.
    public let previewFrameIndex: Int?

    public init(
        plannedTimestamps: [TimeInterval],
        analysedTimestamps: [TimeInterval],
        perFrameSubjects: [[SubjectDetectionResult]],
        skippedFrames: Int,
        summary: SmartCropSubjectSummary,
        previewFramePNG: Data?,
        previewFrameIndex: Int?
    ) {
        self.plannedTimestamps = plannedTimestamps
        self.analysedTimestamps = analysedTimestamps
        self.perFrameSubjects = perFrameSubjects
        self.skippedFrames = skippedFrames
        self.summary = summary
        self.previewFramePNG = previewFramePNG
        self.previewFrameIndex = previewFrameIndex
    }
}

public enum SmartCropVideoError: LocalizedError, Sendable, Equatable {
    case noFramesExtracted(attempted: Int, lastError: String?)

    public var errorDescription: String? {
        switch self {
        case .noFramesExtracted(let attempted, let lastError):
            return "None of the \(attempted) sampled frames could be read from the video"
                + (lastError.map { " (\($0))" } ?? "") + "."
        }
    }
}

// MARK: - SmartCropVideoAnalyzer

/// Samples frames from a video, detects subjects in each, and turns the
/// per-frame results into ONE crop rectangle for the whole video.
/// `SmartCropView.runAnalysis()` is the caller; tests drive it with mocks.
public struct SmartCropVideoAnalyzer: Sendable {
    private let frameExtractor: any SmartCropFrameExtracting
    private let subjectDetector: any SubjectDetecting

    public init(frameExtractor: any SmartCropFrameExtracting, subjectDetector: any SubjectDetecting) {
        self.frameExtractor = frameExtractor
        self.subjectDetector = subjectDetector
    }

    /// Extracts `request.sampleCount` frames sequentially and detects subjects
    /// in each. A frame ffmpeg cannot produce is skipped (counted in
    /// `skippedFrames`); cancellation is rethrown immediately. Throws
    /// `SmartCropVideoError.noFramesExtracted` when every frame failed.
    /// `progress` fires once per planned frame, off the main actor.
    public func analyze(
        _ request: SmartCropVideoRequest,
        progress: (@Sendable (SmartCropVideoProgress) -> Void)? = nil
    ) async throws -> SmartCropVideoResult {
        let timestamps = SmartCropSampling.timestamps(duration: request.duration, count: request.sampleCount)
        let previewTarget = timestamps.count / 2
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-smartcrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var perFrame: [[SubjectDetectionResult]] = []
        var analysed: [TimeInterval] = []
        var skipped = 0
        var lastError: String?
        var preview: (data: Data, index: Int, distance: Int)?

        for (i, t) in timestamps.enumerated() {
            try Task.checkCancellation()
            let frameURL = scratch.appendingPathComponent("frame-\(i).png")
            do {
                try await frameExtractor.extractFrame(from: request.videoURL, at: t, to: frameURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skipped += 1
                lastError = error.localizedDescription
                progress?(SmartCropVideoProgress(completedFrames: i + 1, totalFrames: timestamps.count))
                continue
            }
            let subjects = await subjectDetector.detectSubjects(imageURL: frameURL)
            perFrame.append(subjects)
            analysed.append(t)
            let distance = abs(i - previewTarget)
            if preview == nil || distance < preview!.distance,
               let data = try? Data(contentsOf: frameURL) {
                preview = (data, perFrame.count - 1, distance)
            }
            progress?(SmartCropVideoProgress(completedFrames: i + 1, totalFrames: timestamps.count))
        }

        guard !perFrame.isEmpty else {
            throw SmartCropVideoError.noFramesExtracted(attempted: timestamps.count, lastError: lastError)
        }
        return SmartCropVideoResult(
            plannedTimestamps: timestamps, analysedTimestamps: analysed,
            perFrameSubjects: perFrame, skippedFrames: skipped,
            summary: Self.summarise(perFrame: perFrame),
            previewFramePNG: preview?.data, previewFrameIndex: preview?.index)
    }

    // MARK: - Pure aggregation

    /// Per frame: the union of its FACE boxes, or of all its subjects when it
    /// has no faces; frames with no subjects contribute nothing. The centroid
    /// is the median of those rect centres, so one frame with a stray
    /// detection at the edge cannot drag the crop. Vision's bottom-left boxes
    /// are converted to top-left here.
    public static func summarise(perFrame: [[SubjectDetectionResult]]) -> SmartCropSubjectSummary {
        var rects: [CGRect] = []
        var faceCount = 0
        for subjects in perFrame {
            faceCount += subjects.filter { $0.subjectType == .face }.count
            if let rect = interestRect(of: subjects) { rects.append(rect) }
        }
        guard let first = rects.first else {
            return SmartCropSubjectSummary(framesAnalysed: perFrame.count, framesWithSubjects: 0,
                                           faceCount: faceCount, centroid: nil, extent: nil)
        }
        return SmartCropSubjectSummary(
            framesAnalysed: perFrame.count, framesWithSubjects: rects.count, faceCount: faceCount,
            centroid: CGPoint(x: median(rects.map(\.midX)), y: median(rects.map(\.midY))),
            extent: rects.dropFirst().reduce(first) { $0.union($1) })
    }

    /// The crop for the whole video: ALWAYS exactly `targetAspectRatio` (w/h)
    /// and as large as `activeArea` (else the full source) allows; all four
    /// values even (codec/chroma alignment, matching cropdetect `round=2`);
    /// anchored on `summary.centroid` (centre of the bounds when nil) and
    /// clamped inside the bounds. It does not shrink or distort to include
    /// every subject. With `useRuleOfThirds` and a centroid, the subject is
    /// placed on whichever of the four thirds intersections needs the least
    /// clamping to keep the crop inside the bounds (ties → first of
    /// (1/3,1/3), (2/3,1/3), (1/3,2/3), (2/3,2/3)).
    public static func cropRect(
        summary: SmartCropSubjectSummary,
        sourceWidth: Int, sourceHeight: Int,
        targetAspectRatio: Double,
        useRuleOfThirds: Bool,
        activeArea: CropRect? = nil
    ) -> CropRect {
        let srcW = Double(max(2, sourceWidth)), srcH = Double(max(2, sourceHeight))
        var bx = 0.0, by = 0.0, bw = evenDown(srcW), bh = evenDown(srcH)
        if let a = activeArea, a.width >= 2, a.height >= 2 {
            let ax = min(max(evenUp(Double(a.x)), 0), bw - 2)
            let ay = min(max(evenUp(Double(a.y)), 0), bh - 2)
            let aw = max(2, min(evenDown(Double(a.width)), bw - ax))
            let ah = max(2, min(evenDown(Double(a.height)), bh - ay))
            bx = ax; by = ay; bw = aw; bh = ah
        }
        let ratio = (targetAspectRatio.isFinite && targetAspectRatio > 0) ? targetAspectRatio : bw / bh
        var w: Double, h: Double
        if bw / bh > ratio { h = bh; w = bh * ratio } else { w = bw; h = bw / ratio }
        w = max(2, evenDown(w)); h = max(2, evenDown(h))

        let anchor = summary.centroid.map { CGPoint(x: $0.x * srcW, y: $0.y * srcH) }
            ?? CGPoint(x: bx + bw / 2, y: by + bh / 2)
        let minX = bx, maxX = bx + bw - w, minY = by, maxY = by + bh - h
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

        var x = anchor.x - w / 2, y = anchor.y - h / 2
        if useRuleOfThirds, summary.centroid != nil {
            let thirds: [(Double, Double)] = [(1/3, 1/3), (2/3, 1/3), (1/3, 2/3), (2/3, 2/3)]
            var best: (x: Double, y: Double, displacement: Double)?
            for (tx, ty) in thirds {
                let ox = anchor.x - tx * w, oy = anchor.y - ty * h
                let cx = clamp(ox, minX, maxX), cy = clamp(oy, minY, maxY)
                let d = ((ox - cx) * (ox - cx) + (oy - cy) * (oy - cy)).squareRoot()
                if let b = best, d >= b.displacement { continue }
                best = (cx, cy, d)
            }
            if let b = best { x = b.x; y = b.y }
        }
        x = clamp(evenDown(clamp(x, minX, maxX)), minX, maxX)
        y = clamp(evenDown(clamp(y, minY, maxY)), minY, maxY)
        return CropRect(width: Int(w), height: Int(h), x: Int(x), y: Int(y))
    }

    // MARK: - Private

    private static func interestRect(of subjects: [SubjectDetectionResult]) -> CGRect? {
        let faces = subjects.filter { $0.subjectType == .face }
        let boxes = (faces.isEmpty ? subjects : faces).map { topLeftNormalised($0.boundingBox) }
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
    private static func topLeftNormalised(_ box: CGRect) -> CGRect {
        CGRect(x: box.origin.x, y: 1.0 - box.origin.y - box.height, width: box.width, height: box.height)
    }
    private static func median(_ values: [CGFloat]) -> CGFloat {
        let s = values.sorted(); let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
    private static func evenDown(_ v: Double) -> Double { (v / 2).rounded(.down) * 2 }
    private static func evenUp(_ v: Double) -> Double { (v / 2).rounded(.up) * 2 }
}
