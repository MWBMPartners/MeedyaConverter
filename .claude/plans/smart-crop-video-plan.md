<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Implementation Plan — Smart Crop analyses the selected VIDEO and stages its crop onto the next encode (#299)

> **Status: PLANNED.** Fable 5.1 deep-plan (2026-09-02) against HEAD `0606746` on `wip/alpha-consolidation`. `swift test` is CI-only; gate locally with the compile filter, push, and watch CI to green. Re-run `git log -1` before editing; if HEAD moved, re-verify the `AppViewModel.swift` anchors by text (a sibling agent edits that file concurrently).

## Files

| Action | Path |
|---|---|
| **Create** | `Sources/ConverterEngine/Utilities/SmartCropVideoAnalyzer.swift` — `SmartCropFrameExtracting` + `SubjectDetecting` seams, `FFmpegFrameExtractor`, `SmartCropSampling`, `SmartCropSubjectSummary`, `SmartCropVideoRequest/Progress/Result/Error`, `SmartCropVideoAnalyzer` (orchestrator + the two PURE public functions `summarise` and `cropRect`) |
| **Modify** | `Sources/ConverterEngine/Utilities/SmartCropDetector.swift` — `detectSubjects` becomes an instance method conforming to `SubjectDetecting`; `public init()`; doc rewrite; **delete** the four dead-after-this-change crop-geometry functions (decision D3) |
| **Modify** | `Sources/MeedyaConverter/Views/SmartCropView.swift` (module `MeedyaConverterCore`, `path: "Sources/MeedyaConverter"`) — rewrite: analyses `viewModel.selectedFile`, progress + Cancel, preview frame, recompute-on-aspect-change, "Apply to Next Encode" + Copy |
| **Modify** | `Sources/MeedyaConverter/ViewModels/AppViewModel.swift` — `pendingManualCropFilter` doc (L402-411); passthrough guard in `enqueueSelectedFile()` crop block (L1013-1024) |
| **Create** | `Tests/ConverterEngineTests/SmartCropVideoAnalyzerTests.swift` — pure sampling/summary/geometry tests, mocked orchestration (order, skip, cancel, progress, preview, scratch cleanup), shell-script ffmpeg fixture through the real `FFmpegFrameExtractor` |
| **Create** | `Tests/MeedyaConverterCoreTests/SmartCropStagingTests.swift` — `AppViewModel.enqueueSelectedFile()` consumes the staged crop; precedence over auto-crop; composes before a staged graph; dropped for passthrough; `activeArea` guard |
| **Modify** | `CHANGELOG.md` — one `### Added` bullet (after the "#300" Background Removal bullet, L44-46) + one `### Fixed` bullet (first under `### Fixed`, before the Storage Analysis bullet L52) |

Reference patterns (read, don't modify): `FFmpegProcessController.swift:188-277,310-327,344-357` (start/drain/stop/exitCode/errorOutput; note L207 appends `-nostdin -y … -progress pipe:1`), `StabilizationView.swift:77,135-140,206-232,289,338-352,357-373` (controller drain with `Task.isCancelled → stopEncoding()`, no-file wording, run/cancel section), `DualDynamicHDRView.swift:63,99-100,536,580,630` (retained task, `onDisappear` cancel, `Task.detached` tool lookup, `Task { @MainActor in }` progress hop), `FilterGraphEditorView.swift:996-1024` (stage onto `AppViewModel`, "Staged"/"Apply to Next Encode" label, `.help`), `ComparisonCapture.swift:153-188,279-284` (frame-extraction argv — reused verbatim), `DualDynamicHDRPipelineExecutorTests.swift:35-78,89-104` (lock-guarded mock + `ProgressRecorder`, `import ConverterEngine` no `@testable`), `FFmpegProbeSuiteCoreCodecTests.swift:39-51` (shell-script tool fixture), `SettingsUndoManagerTests.swift:14-21` (`@MainActor` test constructing `AppViewModel()`).

## Current behaviour (verified against code, not comments)

**Two unrelated crop detectors exist; only one is on the encode path today.**

`Sources/ConverterEngine/FFmpeg/CropDetector.swift` — ffmpeg `cropdetect` black-bar detector. **LIVE end-to-end**: `EncodingEngine.detectCrop(for:)` (`EncodingEngine.swift:616-632`, needs `configure()` L161-175) → `AppViewModel.detectCropForSelectedFile()` (L811-831) → `AppViewModel.detectedCrop: CropDetectionResult?` (L397) → consumed in `enqueueSelectedFile()` L1021-1024 when `autoCropEnabled` (L394, default `true`) and `willCrop` → `FilterChainComposer.compose(cropFilter, stagedVideoGraph)` L1050 → `EncodingJobConfig.videoFilterChain` L1061 → `-vf` (`FFmpegArgumentBuilder.swift:452-455,510-513`). UI: `OutputSettingsView.cropDetectionControls` L630-668 ("Auto-crop black bars" toggle, "Detect Now"). Internals: `CropRect` (L13-50, `filterString` = `crop=W:H:X:Y`, `Codable/Sendable/Equatable/Hashable`), `CropDetectionResult` (L55-105, `willCrop`, `sourceWidth/Height`), `detect` (L168-199) runs a bare `Process` per sample (L222-257, no cancel/progress), `parseCropDetectOutput` public (L263-274) with the pure line parser at L277-295, private `mostCommonCrop` (mode) L298-317. The public parser is tested at `ConverterEngineTests+QualityAndScene.swift:573-585` with a fixture that lacks the `limit:`/`crop=` fields; the real ffmpeg 8.1.2 line (verified in the scratchpad: `[Parsed_cropdetect_0 @ 0x…] x1:0 x2:1279 y1:92 y2:627 w:1280 h:536 x:0 y:92 pts:1024 t:0.080000 limit:24.000000 crop=1280:536:0:92`) still parses because the first `w:`/`h:`/`x:`/`y:` occurrences are the right ones.

`Sources/ConverterEngine/Utilities/SmartCropDetector.swift` — Vision subject detector (faces + attention saliency). Reachable **only** from `SmartCropView` (grep: no other callers, no tests). `detectSubjects(imageURL:)` is `public static` (L104-117); `calculateCropRect` (L133-174), `buildCropFilter` (L183-189), `applyRuleOfThirds` (L202-236), private `centredCropRect` (L310-354). Two geometry bugs the video path would inherit verbatim: (a) `centredCropRect` L336-347 enlarges for `minWidth/minHeight` then clamps each axis independently, so the result is **not** the target aspect ratio whenever subjects don't fit (e.g. 1920×1080 → "9:16" with a 1200 px-wide subject union yields 1440×1080); (b) `applyRuleOfThirds` L220-225 computes `dx = subjectCenter.x - (cropOriginX + tx*w)` where `cropOriginX = subjectCenter.x - tx*w`, i.e. `dx == dy == 0` for every candidate, so it **always** picks `(1/3, 1/3)` — the doc "Choose the intersection closest to the subject" is false.

`Sources/MeedyaConverter/Views/SmartCropView.swift` (426 lines) — header L13-27 claims "load an image (or video frame)"; the picker (L129-131, `chooseImage()` L337-352) only accepts `.image/.png/.jpeg/.tiff` — no video path exists. `detectSubjects()` L355-392 runs Vision on that still and sizes the crop from `NSImage.size` (L368-369, **points not pixels**). "Apply to Job" (L271-274 → `applyCropToJob()` L394-409) **does** set `viewModel.pendingManualCropFilter` (L403), and `enqueueSelectedFile()` L1017-1020 **does** consume it with precedence over auto-crop — so the summary "does not attach to an encode" is wrong. The real defect: the rect is computed on an arbitrary user-chosen image, in that image's coordinates, not on the selected video; if the image's dimensions differ from the video's, the staged `crop=` is simply wrong. `errorMessage` (L81) is set but never rendered (body L89-108). `@Environment(AppViewModel.self)` is used (L403-404). Navigation: `NavigationItem.smartCrop` (`AppViewModel.swift:115`), not in `unavailable` (L178), rendered at `ContentView.swift:154-155`, sidebar "Images & Audio" (`SidebarView.swift:71-77`).

**Enqueue composition facts** (`AppViewModel.swift`): `pendingManualCropFilter` (L411) wins over `detectedCrop` (L1017-1024) — so a staged Smart Crop **ignores** the black bars unless its rect already excludes them; staged graph is composed AFTER crop (L1026-1050, warning at L1045-1047 if the graph also has `crop=`); passthrough drops the **graph** halves (L1037-1044) but **not the crop**. `FFmpegArgumentBuilder.buildVideoFilterChain` L510-513 appends `videoFilterChain` with no `videoPassthrough` guard (deinterlace L506, tone-map L516, watermark L531 are guarded). Verified: ffmpeg 8.1.2 exits 234 with `Filtergraph 'crop=…' was specified, but codec copy was selected. Filtering and streamcopy cannot be used together.` — so any staged/auto crop on a copy-video profile fails the whole job today. `detectedCrop` is never cleared when `selectedFile` changes (assignments L665, 772, 798, 805; only `detectCropForSelectedFile` L814 nils it), and `CropDetectionResult` carries no URL — only `sourceWidth/Height`.

**Engine facts**: `EncodingEngine.bundleManager` is `public let` (L71), `FFmpegBundleManager` is `final class … @unchecked Sendable` (L108) → safe to capture in `Task.detached`; the app's manager honours the Settings override, a fresh `FFmpegBundleManager()` (as `StabilizationView:289`, `SceneDetectorView:487`) does not. `EncodingEngine.queue` (L80) → `EncodingQueue.addJob` (`EncodingJob.swift:378-393`) is in-memory only (no auto-start, no persistence); `jobs` L345 is `public private(set)`; `EncodingJobState.config` L243. `ComparisonCapture.captureFrame(inputPath:outputPath:timestamp:width:)` (L153-188) builds `-ss HH:MM:SS.mmm -i in -frames:v 1 [-vf scale=W:-2] -f image2 -c:v png -y out`. Empirically (ffmpeg 8.1.2, controller-shaped argv `-nostdin -y … -progress pipe:1`): in-range seek → exit 0, 960×540 PNG written; **seek past EOF → exit 0 and NO file** ("Output file is empty"), so the extractor must check file existence, not just exit code. `MediaFile.init(fileURL:streams:duration:)`, `MediaStream.init(streamIndex:streamType:codecName:width:height:)`, `primaryVideoStream`, `MediaFile.id` exist. `LogEntry.Level` = `.info/.warning/.error/.debug` (L2660-2664); `Category` includes `.filter` (L2706-2716); `logEntries` L503. `View` is `@MainActor` in the macOS 15 SDK — `StabilizationView.runStabilization` mutates `@State` after `await` on that basis. Toolchain: CI `macos-15`, `swift test --parallel`; `.swiftLanguageMode(.v6)`.

## Design

### D1 — Detection approach: Vision on ffmpeg-sampled frames, composed with the live `cropdetect` result

Trade-off, weighed explicitly:

- **`cropdetect` for Smart Crop (rejected).** It is more deterministic and its parser is already public+tested — but it is *already shipped and reachable* as "Auto-crop black bars" in Output Settings. Making Smart Crop a second cropdetect UI would duplicate that feature, and the aspect-ratio picker, rule-of-thirds and Vision code (the only thing that makes it "smart") would become dead. It also cannot do the one thing Smart Crop is for: reframe 16:9 → 9:16/1:1 around the subject.
- **Vision on sampled frames (chosen).** Every primitive is already present: subject detection (`SmartCropDetector.detectSubjects`), the frame-extraction argv (`ComparisonCapture.captureFrame`), the process runner (`FFmpegProcessController`), and the black-bar rect (`viewModel.detectedCrop`). The only new code is orchestration and two pure functions (aggregate → rect), which is exactly the part that is unit-testable without ffmpeg or Vision. Reliability is made deterministic by contract: the crop is **always exactly the target aspect ratio and as large as the active area allows**, positioned on the **median** per-frame subject centroid (robust to one bad frame); no subjects → centred (the existing fallback). Vision itself is the only untestable piece and sits behind a seam.
- **Composition instead of conflict.** The rect is computed *inside* the auto-detected black-bar area (when auto-crop is on and the detection matches this file's dimensions). Because the manual crop already takes precedence at enqueue, exactly one `crop=` is emitted that both removes the bars and reframes — no double crop, and letterboxed sources no longer keep their bars when Smart Crop is used.

### D2 — Seams (in `SmartCropVideoAnalyzer.swift`)

```swift
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
```

### D3 — Existing SmartCrop symbols: live / dead / deleted (flagged decision)

| Symbol | After this change |
|---|---|
| `SubjectType`, `SubjectDetectionResult` | **live** (per-frame results, preview overlay) |
| `SmartCropDetector.detectSubjects` | **live**, becomes an *instance* method (the `SubjectDetecting` conformance); `detectFaces/detectSaliency` unchanged |
| `SmartCropDetector.calculateCropRect`, `buildCropFilter`, `applyRuleOfThirds`, `centredCropRect` | **dead** (zero callers; `SmartCropView` no longer calls them; no tests reference them) **and buggy** (see Current behaviour). **Delete them.** Alternative if the orchestrator vetoes deletion: leave them untouched and record in Risk 8 that they are unused public API with two known bugs — do NOT describe them as used anywhere. |
| `CropDetector`, `CropRect`, `CropDetectionResult` | **live** (unchanged); `CropRect` is reused as Smart Crop's result type |
| `SmartCropView.chooseImage()` / `selectedImageURL` / image picker | **removed** — the input is now `viewModel.selectedFile`, as in every sibling tool |

### D4 — Coordinates (state these in doc comments; tests pin them)
- Vision → `SubjectDetectionResult.boundingBox`: normalised, **bottom-left** origin.
- `SmartCropSubjectSummary.centroid/extent`: normalised, **top-left** origin (converted in `summarise`).
- `CropRect` / active area: **source pixels**, top-left origin, ffmpeg `crop=w:h:x:y`. Subjects are detected on a 960-wide PNG but Vision's coordinates are normalised, so they scale to the source dimensions from `MediaStream.width/height` (never from `NSImage.size`).

### D5 — Concurrency / progress / cancel
- `SmartCropVideoAnalyzer.analyze` is a nonisolated `async` method → runs off the main actor even when awaited from the view's `Task`. Frames are extracted **sequentially** (one short ffmpeg each); Vision runs inside the detector (synchronous CPU work on a cooperative thread, as today).
- `progress: (@Sendable (SmartCropVideoProgress) -> Void)?` fires once per planned frame (including skipped ones); the view hops with `Task { @MainActor in self.progress = p }` (DualDynamicHDRView:630 pattern).
- Cancellation: `try Task.checkCancellation()` before each frame; `FFmpegFrameExtractor` calls `controller.stopEncoding()` when `Task.isCancelled` inside its drain loop and then throws `CancellationError`; the analyzer **rethrows** `CancellationError` (never counts it as a skipped frame). The view retains `analysisTask`, cancels it from a Cancel button and `.onDisappear`.
- ffmpeg lookup: `viewModel.engine.bundleManager.locateFFmpeg().path` inside `Task.detached` (spawns `ffmpeg -version`; off-main).
- Scratch: `temporaryDirectory/meedya-smartcrop-<UUID>/frame-<i>.png`, removed in `defer`; the preview crosses the module boundary as `Data` (PNG bytes), so no temp-file ownership contract with the view.

## Exact changes — `Sources/ConverterEngine/Utilities/SmartCropVideoAnalyzer.swift` (new)

House header (`MeedyaConverter — SmartCropVideoAnalyzer (Issue #299)`), `import Foundation`, `import CoreGraphics`. Contents, in order:

1. The two protocols from D2.

2. Frame extractor (production conformer):
```swift
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
```

3. Sampling (pure):
```swift
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
```

4. Value types:
```swift
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
    public init(framesAnalysed: Int, framesWithSubjects: Int, faceCount: Int, centroid: CGPoint?, extent: CGRect?)
}

public struct SmartCropVideoRequest: Sendable {
    public var videoURL: URL
    public var duration: TimeInterval?
    public var sampleCount: Int
    public init(videoURL: URL, duration: TimeInterval?, sampleCount: Int = 9)
}

public struct SmartCropVideoProgress: Sendable, Equatable {
    public let completedFrames: Int   // planned frames finished (extracted OR skipped)
    public let totalFrames: Int
    public init(completedFrames: Int, totalFrames: Int)
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
    public init(/* memberwise, all labels */)
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
```

5. The analyzer (orchestration + pure functions):
```swift
/// Samples frames from a video, detects subjects in each, and turns the
/// per-frame results into ONE crop rectangle for the whole video.
/// `SmartCropView.runAnalysis()` is the caller; tests drive it with mocks.
public struct SmartCropVideoAnalyzer: Sendable {
    private let frameExtractor: any SmartCropFrameExtracting
    private let subjectDetector: any SubjectDetecting

    public init(frameExtractor: any SmartCropFrameExtracting, subjectDetector: any SubjectDetecting) { … }

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
```
Worked values the tests pin (hand-computed from this code): 1920×1080 no subjects, 9:16 → `crop=606:1080:656:0`; same with active area 1920×800+0+140 → `crop=450:800:734:140`; 1080×1920 source, 16:9 → `crop=1080:606:0:656`; 1920×1080 1:1, centroid (0.7, 0.5): centred x = 804, rule-of-thirds x = 624, y = 0.

## Exact changes — `Sources/ConverterEngine/Utilities/SmartCropDetector.swift`

1. Type doc L72-92 → replace with:
```swift
/// Vision-framework subject detection for Smart Crop (Issue #299).
///
/// `detectSubjects(imageURL:)` runs face detection
/// (`VNDetectFaceRectanglesRequest`) and attention-based saliency
/// (`VNGenerateAttentionBasedSaliencyImageRequest`) on one image and returns
/// every hit as a `SubjectDetectionResult` in Vision's normalised,
/// bottom-left-origin coordinates, sorted by confidence. `SmartCropVideoAnalyzer`
/// calls it once per sampled video frame (through the `SubjectDetecting`
/// seam) and turns the per-frame results into a crop rectangle; this type
/// does no crop geometry itself.
```
2. L93 → `public struct SmartCropDetector: Sendable, SubjectDetecting {` and add `public init() {}` as the first member.
3. L104 `public static func detectSubjects(imageURL: URL) async -> [SubjectDetectionResult]` → `public func detectSubjects(imageURL: URL) async -> [SubjectDetectionResult]` (body unchanged; it calls the private *static* `detectFaces/detectSaliency`, which stays valid). Doc L97-103: replace "Runs … in parallel" (false — they run sequentially, L108/L112) with "Runs face detection, then attention-based saliency, and merges the results".
4. **D3 — delete** L119-236 (`calculateCropRect`, `buildCropFilter`, `applyRuleOfThirds`) and L300-354 (`centredCropRect`). Keep `// MARK: - Private Helpers` with `detectFaces`/`detectSaliency`. Do not touch imports.

## Exact changes — `Sources/MeedyaConverter/ViewModels/AppViewModel.swift`

1. Replace the doc L402-410 above `var pendingManualCropFilter: String?` (L411):
```swift
    /// A crop filter string (`crop=W:H:X:Y`, source-pixel coordinates) staged by
    /// `SmartCropView.applyCropToJob()` — the subject-aware crop that
    /// `SmartCropVideoAnalyzer` computed from sampled frames of the selected
    /// file, inside the auto-detected black-bar area when `autoCropEnabled`
    /// and `detectedCrop` say there is one for this file. Consumed by the next
    /// `enqueueSelectedFile()`, where it takes precedence over
    /// `detectedCrop`/`autoCropEnabled` (the staged rect already excludes the
    /// bars, so applying both would double-crop), is merged into
    /// `videoFilterChain` before any staged filter graph, then cleared so it
    /// does not silently keep applying to unrelated future jobs.
```
2. Replace L1013-1024 (comment + crop block) with:
```swift
        // Apply a Smart Crop staged by SmartCropView.applyCropToJob() if one is
        // pending, otherwise fall back to auto-crop if enabled and a crop was
        // detected. Either way the crop is dropped — with a warning — when the
        // effective profile copies the video stream: FFmpeg refuses `-vf`
        // together with `-c:v copy` ("Filtering and streamcopy cannot be used
        // together"), so keeping it would fail the whole job.
        var cropFilter: String? = nil
        if let manualCrop = pendingManualCropFilter {
            cropFilter = manualCrop
            appendLog(.info, "Smart Crop: applying manually selected crop (\(manualCrop))")
            pendingManualCropFilter = nil
        } else if autoCropEnabled, let crop = detectedCrop, crop.willCrop {
            cropFilter = crop.recommendedCrop.filterString
            appendLog(.info, "Auto-crop: \(crop.recommendedCrop.displayString) (\(String(format: "%.1f", crop.cropPercentage))% removed)")
        }
        if cropFilter != nil, effectiveProfile.videoPassthrough {
            appendLog(.warning, "Crop discarded — profile \"\(effectiveProfile.name)\" copies the video stream, and a copied stream cannot be filtered", category: .filter)
            cropFilter = nil
        }
```
Nothing else in `enqueueSelectedFile` changes (graph block L1026-1050 and `compose(cropFilter, stagedVideoGraph)` stay as they are).

## Exact changes — `Sources/MeedyaConverter/Views/SmartCropView.swift` (rewrite)

Keep: header block, `import SwiftUI`/`import ConverterEngine`, `AspectRatioOption` (L37-52), `boundingBoxOverlay` (L285-307), `cropOverlay` (L310-332, takes `CGRect`), `colorForSubjectType` (L417-424), the name `applyCropToJob()` (AppViewModel's doc names it). Remove: `selectedImageURL`, `chooseImage()`, `cropFilterString`, `detectSubjects()`.

1. Header doc (L13-27) →
```swift
/// Subject-aware crop for the selected source file (Issue #299).
///
/// "Analyze" samples frames across the selected video with ffmpeg, runs
/// Vision face/saliency detection on each (`SmartCropVideoAnalyzer`), and
/// computes one crop at the chosen aspect ratio — inside the auto-detected
/// black-bar area when "Auto-crop black bars" is on. The preview shows the
/// middle sampled frame with that frame's subjects and the crop; changing
/// the aspect ratio or rule-of-thirds recomputes the crop without
/// re-analysing. "Apply to Next Encode" stages the crop on
/// `AppViewModel.pendingManualCropFilter`, which the next
/// `enqueueSelectedFile()` merges into the job's `-vf` (before any staged
/// filter graph, with precedence over auto-crop). Runs ffmpeg with progress
/// and Cancel; needs a re-encoding (non-passthrough) profile to apply.
```
2. State:
```swift
@Environment(AppViewModel.self) private var viewModel
@State private var selectedAspectRatio: AspectRatioOption = .ratio16_9
@State private var useRuleOfThirds = false
@State private var sampleCount = 9
@State private var isAnalysing = false
@State private var analysisTask: Task<Void, Never>?
@State private var progress: SmartCropVideoProgress?
@State private var statusText = ""
@State private var result: SmartCropVideoResult?
@State private var analysedFileURL: URL?
@State private var sourceWidth = 0
@State private var sourceHeight = 0
@State private var activeArea: CropRect?
@State private var previewImage: NSImage?
@State private var cropRect: CropRect?
@State private var errorMessage: String?
@State private var didApplyToJob = false
@State private var didCopyFilter = false
```
3. Body: `VStack(alignment: .leading, spacing: 16) { headerSection; sourceSection; controlsSection; if isAnalysing { progressSection }; HStack(spacing: 16) { previewSection; resultsSection }; if let cropRect { cropFilterSection(cropRect) }; if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) }; Spacer() }.padding().frame(minWidth: 700, minHeight: 500)` plus
`.onChange(of: selectedAspectRatio) { recomputeCrop() }`, `.onChange(of: useRuleOfThirds) { recomputeCrop() }`, `.onChange(of: viewModel.selectedFile?.fileURL) { _, new in if new != analysedFileURL { resetResults() } }`, `.onDisappear { cancel() }`.
   - `headerSection` text: "Smart Crop" / "Detect subjects across the selected video and compute a crop for the desired aspect ratio."
   - `sourceSection`: `LabeledContent("File", value: file.fileName)` + "\(w)×\(h)" from `primaryVideoStream`, else `Text("Select a source file in the Source tab to crop.").foregroundStyle(.secondary)` (StabilizationView:138 wording).
   - `controlsSection`: aspect `Picker` (unchanged), `Toggle("Rule of Thirds")`, `Stepper("Sample frames: \(sampleCount)", value: $sampleCount, in: 3...21, step: 2)`, and `Button("Analyze Video") { startAnalysis() }.buttonStyle(.borderedProminent).disabled(viewModel.selectedFile == nil || isAnalysing)`.
   - `progressSection`: `HStack { ProgressView().controlSize(.small); Text(statusText).foregroundStyle(.secondary); Spacer(); Button("Cancel", role: .cancel, action: cancel) }` and, when `progress != nil`, `ProgressView(value: Double(p.completedFrames), total: Double(p.totalFrames))`.
   - `previewSection`: GroupBox("Preview") — as today but `imageSize: CGSize(width: sourceWidth, height: sourceHeight)`, subjects = `result.previewFrameIndex.map { result.perFrameSubjects[$0] } ?? []`, crop overlay from `cropRect.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }`; placeholder "Analyze the selected video to see a preview."
   - `resultsSection`: GroupBox("Detection") with `Text("Subjects in \(s.framesWithSubjects) of \(s.framesAnalysed) frames · \(s.faceCount) face detections")`, `if r.skippedFrames > 0 { Text("\(r.skippedFrames) frame(s) could not be read") }`, `if let activeArea { Label("Inside auto-detected picture area \(activeArea.displayString)", systemImage: "rectangle.dashed") }`, placeholder "No analysis yet."
   - `cropFilterSection(_ crop: CropRect)`: GroupBox("FFmpeg Crop Filter") — `Text("\(crop.displayString)")` caption, `Text(crop.filterString).font(.system(.body, design: .monospaced)).textSelection(.enabled)`, Spacer, `Button { copyFilter(crop) } label: { Label(didCopyFilter ? "Copied!" : "Copy Filter", systemImage: didCopyFilter ? "checkmark" : "doc.on.doc") }`, `Button { applyCropToJob() } label: { Label(didApplyToJob ? "Staged" : "Apply to Next Encode", systemImage: didApplyToJob ? "checkmark" : "arrow.right.circle") }.buttonStyle(.borderedProminent).disabled(viewModel.selectedProfile.videoPassthrough).help("Stage this crop onto the next job you queue")`. Below the row: if `viewModel.selectedProfile.videoPassthrough` → caption "The selected profile copies the video stream — choose a re-encoding profile to crop."; if `viewModel.pendingFilterGraphVideo?.contains("crop=") == true` → caption "A staged Filter Graph also contains a crop; both will apply in sequence."
4. Actions (verbatim):
```swift
private func startAnalysis() {
    guard let file = viewModel.selectedFile else { return }
    guard let video = file.primaryVideoStream, let w = video.width, let h = video.height, w > 0, h > 0 else {
        errorMessage = "The selected file has no video stream with known dimensions."
        return
    }
    resetResults()
    sourceWidth = w
    sourceHeight = h
    isAnalysing = true
    statusText = "Locating FFmpeg…"
    analysisTask = Task { await runAnalysis(file: file) }
}

private func runAnalysis(file: MediaFile) async {
    defer { finish() }
    let bundleManager = viewModel.engine.bundleManager
    let ffmpegPath: String
    do {
        ffmpegPath = try await Task.detached { try bundleManager.locateFFmpeg().path }.value
    } catch {
        errorMessage = "FFmpeg could not be found: \(error.localizedDescription) Install FFmpeg or set its path in Settings."
        return
    }
    guard !Task.isCancelled else { return }

    // Black bars: reuse the live auto-crop pass so the smart crop is computed
    // inside the picture area (and a single `crop=` removes bars AND reframes).
    if viewModel.autoCropEnabled, viewModel.detectedCrop == nil {
        statusText = "Detecting black bars…"
        await viewModel.detectCropForSelectedFile()
    }
    guard !Task.isCancelled else { return }
    activeArea = Self.activeArea(
        from: viewModel.detectedCrop, autoCropEnabled: viewModel.autoCropEnabled,
        sourceWidth: sourceWidth, sourceHeight: sourceHeight)

    let analyzer = SmartCropVideoAnalyzer(
        frameExtractor: FFmpegFrameExtractor(ffmpegPath: ffmpegPath),
        subjectDetector: SmartCropDetector())
    let request = SmartCropVideoRequest(videoURL: file.fileURL, duration: file.duration, sampleCount: sampleCount)
    statusText = "Analysing frame 1 of \(sampleCount)…"
    do {
        let analysis = try await analyzer.analyze(request) { p in
            Task { @MainActor in
                self.progress = p
                self.statusText = "Analysing frame \(min(p.completedFrames + 1, p.totalFrames)) of \(p.totalFrames)…"
            }
        }
        guard !Task.isCancelled else { return }
        result = analysis
        analysedFileURL = file.fileURL
        previewImage = analysis.previewFramePNG.flatMap { NSImage(data: $0) }
        recomputeCrop()
        viewModel.appendLog(.info, "Smart Crop: analysed \(analysis.perFrameSubjects.count) frames of \(file.fileName) — subjects in \(analysis.summary.framesWithSubjects), \(analysis.summary.faceCount) face detections", category: .filter)
    } catch is CancellationError {
        statusText = ""
    } catch {
        errorMessage = error.localizedDescription
        viewModel.appendLog(.warning, "Smart Crop analysis failed: \(error.localizedDescription)", category: .filter)
    }
}

/// The auto-crop rect is used as the picture area only when auto-crop is on,
/// it actually crops, and it was measured on a frame of THESE dimensions —
/// `detectedCrop` is not cleared when the selection changes, and carries no URL.
static func activeArea(from detected: CropDetectionResult?, autoCropEnabled: Bool,
                       sourceWidth: Int, sourceHeight: Int) -> CropRect? {
    guard autoCropEnabled, let detected, detected.willCrop,
          detected.sourceWidth == sourceWidth, detected.sourceHeight == sourceHeight else { return nil }
    return detected.recommendedCrop
}

private func recomputeCrop() {
    guard let result, sourceWidth > 0, sourceHeight > 0 else { cropRect = nil; return }
    cropRect = SmartCropVideoAnalyzer.cropRect(
        summary: result.summary, sourceWidth: sourceWidth, sourceHeight: sourceHeight,
        targetAspectRatio: selectedAspectRatio.numericValue,
        useRuleOfThirds: useRuleOfThirds, activeArea: activeArea)
    didApplyToJob = false
}

/// Stages the crop on `AppViewModel.pendingManualCropFilter`; the next
/// `enqueueSelectedFile()` merges it into `videoFilterChain` (before any
/// staged filter graph, with precedence over auto-crop) and clears it.
private func applyCropToJob() {
    guard let cropRect else { return }
    viewModel.pendingManualCropFilter = cropRect.filterString
    viewModel.appendLog(.info, "Smart Crop: \(cropRect.filterString) will be applied to the next queued job", category: .filter)
    withAnimation { didApplyToJob = true }
}

private func copyFilter(_ crop: CropRect) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(crop.filterString, forType: .string)
    didCopyFilter = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { didCopyFilter = false }
}

private func resetResults() {
    result = nil; analysedFileURL = nil; previewImage = nil; cropRect = nil
    activeArea = nil; errorMessage = nil; didApplyToJob = false; progress = nil
}

private func finish() { analysisTask = nil; isAnalysing = false; progress = nil }

private func cancel() { analysisTask?.cancel(); finish() }
```
`activeArea(from:…)` is `static` and internal (not private) so `SmartCropStagingTests` can reach it via `@testable`.

## CHANGELOG.md

Under `### Added`, after the Background Removal bullet ending "(#300)." (before `### Changed`):
```
- **Smart Crop** now analyses the **selected video** — it samples frames with
  ffmpeg, runs Vision face/saliency detection on each, and computes a stable
  crop at the chosen aspect ratio (inside the auto-detected black-bar area when
  one is present), with a preview frame, progress and Cancel; "Apply to Next
  Encode" stages it onto the next queued job (#299).
```
First bullet under `### Fixed` (before "**Storage Analysis** now reads…"):
```
- A staged or auto-detected crop is now dropped (with a warning) when the
  profile copies the video stream, instead of emitting `-vf crop=…` next to
  `-c:v copy`, which FFmpeg rejects and which failed the whole job.
```

## Tests

### `Tests/ConverterEngineTests/SmartCropVideoAnalyzerTests.swift`
`import XCTest`, `import ConverterEngine` (no `@testable`), house header. Fixtures:
- `MockFrameExtractor: SmartCropFrameExtracting, @unchecked Sendable` — `NSLock`; `var failAtCallIndices: Set<Int>`; `var delay: Duration = .zero`; records `requestedTimestamps: [TimeInterval]` and `outputURLs: [URL]`; `extractFrame` increments a call counter under `lock.withLock`, `if delay > .zero { try await Task.sleep(for: delay) }`, throws `struct SimulatedFailure: Error` for failing indices, else writes `Data("frame-\(callIndex)".utf8)` to `outputURL`.
- `MockSubjectDetector: SubjectDetecting, @unchecked Sendable` — lock-guarded `results: [[SubjectDetectionResult]]` returned in call order (`[]` once exhausted); records `receivedURLs`.
- `ProgressRecorder` (lock-guarded `[SmartCropVideoProgress]`).
- Helpers `face(x:y:w:h:conf:)` / `saliency(…)` building `SubjectDetectionResult` in Vision (bottom-left) coordinates; `summary(centroid:)` building a `SmartCropSubjectSummary` directly.

Cases:
1. `test_timestamps_nilDuration_returnsZero`
2. `test_timestamps_countOne_isMidpoint` (100 s → `[50]`)
3. `test_timestamps_nine_areMidpointsWithin5To95Percent` (100 s → first 10, last 90, strictly increasing, count 9)
4. `test_timestamps_countClampedToAtLeastOne` (count 0 → 1 element)
5. `test_summarise_empty_hasNilCentroidAndExtent`
6. `test_summarise_convertsVisionBottomLeftToTopLeft` (face at Vision (0.1, 0.6, 0.2, 0.2) → extent (0.1, 0.2, 0.2, 0.2), centroid (0.2, 0.3), accuracy 1e-9)
7. `test_summarise_prefersFacesOverSaliencyWithinAFrame`
8. `test_summarise_usesSaliencyWhenFrameHasNoFaces`
9. `test_summarise_medianCentroidIgnoresOutlierFrame` (4 frames at x≈0.3, 1 at 0.95 → centroid.x == 0.3 ± 1e-9)
10. `test_summarise_countsFramesWithSubjectsAndFaces`
11. `test_cropRect_noSubjects_isCentredMaxSize_16x9To9x16` → `CropRect(606, 1080, 656, 0)`
12. `test_cropRect_allValuesEven` (1919×1079 source, 4:3 → all four `% 2 == 0`, fits inside source)
13. `test_cropRect_centroidShiftsOrigin` (centroid (0.25, 0.5) → x == 176)
14. `test_cropRect_clampsAtEdge` (centroid (0.05, 0.5) → x == 0)
15. `test_cropRect_insideActiveArea_letterbox` (active 1920×800+0+140, 9:16 → `CropRect(450, 800, 734, 140)`)
16. `test_cropRect_activeAreaLargerThanSourceIsClampedToSource`
17. `test_cropRect_ruleOfThirds_picksLeastClampedThird` (1920×1080, 1:1, centroid (0.7, 0.5): `useRuleOfThirds: false` → x 804; `true` → x 624, y 0)
18. `test_cropRect_ruleOfThirds_withoutSubjectsIsCentred`
19. `test_cropRect_targetWiderThanSource_usesFullWidth` (1080×1920, 16:9 → `CropRect(1080, 606, 0, 656)`)
20. `test_cropRect_filterStringIsFFmpegSyntax` (`"crop=606:1080:656:0"`)
21. `test_analyze_extractsPlannedTimestampsInOrder` (9 → `requestedTimestamps == plannedTimestamps`)
22. `test_analyze_skipsFailedFramesAndCountsThem` (fail {1, 7} → `perFrameSubjects.count == 7`, `skippedFrames == 2`, `analysedTimestamps` excludes those)
23. `test_analyze_throwsWhenEveryFrameFails` (`SmartCropVideoError.noFramesExtracted(attempted: 9, …)`)
24. `test_analyze_previewIsMiddleFrameBytes` (9 → `previewFramePNG == Data("frame-4".utf8)`, `previewFrameIndex == 4`)
25. `test_analyze_previewFallsBackToNearestExtractedFrame` (fail {4} → preview non-nil, bytes are `frame-3` or `frame-5`)
26. `test_analyze_progressFiresPerPlannedFrameIncludingSkipped` (fail {2}; 9 calls; last == `(9, 9)`; `completedFrames` strictly increasing)
27. `test_analyze_cancellationStopsAndThrowsCancellationError` (delay 200 ms; cancel after 50 ms; `await task.result` is `.failure` of `CancellationError`; `requestedTimestamps.count <= 2`)
28. `test_analyze_removesScratchDirectory` (after success, `outputURLs[0].deletingLastPathComponent()` no longer exists)
29. `test_analyze_summaryReflectsDetectorResults`
30. `test_frameExtractor_arguments_matchComparisonCapture` (contains `"-ss","00:00:02.500"`, `"-frames:v","1"`, `"-vf","scale=960:-2"`, `"-c:v","png"`; `last == outputURL.path`)
31. `test_frameExtractor_succeedsWhenToolWritesOutput` — script fixture (mirrors `makeFFprobeFixture`): `#!/bin/sh` / `out=""; for a in "$@"; do case "$a" in *.png) out="$a";; esac; done` / `[ -n "$out" ] && printf 'PNGBYTES' > "$out"` / `exit 0`; assert no throw and file contents `PNGBYTES` (position-independent, so the controller's appended `-progress pipe:1` doesn't matter)
32. `test_frameExtractor_throwsWhenToolWritesNothing` (script `exit 0` only — the past-EOF case; `XCTAssertThrowsError` with `error is FFmpegProcessError`)
33. `test_frameExtractor_throwsOnNonZeroExit` (script `exit 1`; `.processFailure(exitCode: 1, _)`)

### `Tests/MeedyaConverterCoreTests/SmartCropStagingTests.swift`
`import XCTest`, `import SwiftUI`, `@testable import MeedyaConverterCore`, `import ConverterEngine`, `@MainActor final class`. Helper `makeFile()` → `MediaFile(fileURL: URL(fileURLWithPath: "/tmp/smartcrop-test.mp4"), streams: [MediaStream(streamIndex: 0, streamType: .video, codecName: "h264", width: 1920, height: 1080)], duration: 60)`; `vm.selectedProfile = EncodingProfile(name: "t", videoCodec: .h264)`; read the job via `vm.engine.queue.jobs.last?.config`.
34. `test_enqueue_consumesPendingSmartCropIntoVideoFilterChain` (`videoFilterChain == "crop=606:1080:656:0"`, `pendingManualCropFilter == nil` afterwards)
35. `test_enqueue_smartCropWinsOverAutoCrop` (`detectedCrop` = result with `crop=1920:800:0:140`, `autoCropEnabled = true`, pending set → chain is the pending one)
36. `test_enqueue_smartCropComposesBeforeStagedFilterGraph` (`pendingFilterGraphVideo = "eq=contrast=1.1"` → `"crop=606:1080:656:0,eq=contrast=1.1"`)
37. `test_enqueue_dropsCropForVideoPassthroughProfile` (`EncodingProfile(name: "copy", videoCodec: .h264, videoPassthrough: true)` → `videoFilterChain == nil`; a `logEntries` entry with `level == .warning` whose message hasPrefix `"Crop discarded"`; `pendingManualCropFilter == nil`)
38. `test_activeArea_requiresAutoCropWillCropAndMatchingDimensions` (nil when auto-crop off; nil when `!willCrop`; nil when 1280×720 result vs 1920×1080 source; the rect otherwise)

## Verification gates
```
swift build --target ConverterEngine
swift build 2>&1 | grep "error:" | grep -v "PreviewsMacros\|Preview(_:body:)\|external macro\|emit-module"   # must be empty
swiftc -parse Tests/ConverterEngineTests/SmartCropVideoAnalyzerTests.swift
swiftc -parse Tests/MeedyaConverterCoreTests/SmartCropStagingTests.swift
grep -rn "calculateCropRect\|applyRuleOfThirds\|buildCropFilter\|centredCropRect" Sources Tests   # must be empty after D3
```
Then commit, push, and watch CI to green (`swift test --parallel` on `macos-15`); fix reds immediately.

## Risks

1. **False-comment / dead-code hygiene.** Rewritten false claims: `SmartCropView` header L13-27 ("or video frame"), L118, `AppViewModel` L402-410 ("standalone Smart Crop tool rather than automatic source-file crop detection"), `SmartCropDetector` L72-92 usage example and "in parallel" (L99). Dead view state `errorMessage` becomes rendered. Every new public symbol has a caller reachable from `SmartCropView.runAnalysis()` → `applyCropToJob()` → `enqueueSelectedFile()`; the last gate greps for the deleted names. The question to ask of every new doc comment: *is this literally what the code beneath it does?*
2. **Double-crop avoidance.** Manual precedence at enqueue (L1017) means auto-crop is never appended alongside the Smart Crop; the Smart Crop rect is computed *inside* the auto-crop area, so bars are still removed by the one `crop=`; a staged Filter Graph containing `crop=` keeps the existing L1045 warning (crop-then-graph order unchanged) and the view now shows the same hint before staging.
3. **Passthrough.** The new enqueue guard fixes a pre-existing failure for auto-crop too (a re-encode → copy profile switch after "Detect Now" produced a failing job). The view also disables Apply for passthrough profiles, but the enqueue guard is the authority because the profile can change between staging and enqueue.
4. **Stale `detectedCrop`** (never cleared on selection change, no URL). Smart Crop guards by dimensions only — two different files with identical dimensions could still borrow the wrong bars. The auto-crop path at L1021 has the same pre-existing exposure; out of scope, follow-up: nil `detectedCrop` wherever `selectedFile` is assigned (L665, 772, 798, 805).
5. **Cancel during the black-bar pass is deferred**: `CropDetector` uses bare `Process` (L222-257) with no cancellation, so Cancel takes effect after it returns (a few seconds); the frame-sampling phase cancels immediately. Documented in the header; hardening `CropDetector` is out of scope.
6. **Detection quality.** Vision is non-deterministic across frames and may find nothing (→ centred crop, as today). Faces are prioritised; saliency of large bright areas can win when no faces exist. HDR sources produce un-tonemapped PNGs — detection still works, the preview looks washed out. Not in scope: tone-mapping the preview.
7. **Anamorphic sources (SAR ≠ 1).** The crop and the aspect ratio are in coded pixels because `crop` operates on coded pixels; on anamorphic content "16:9" is not display 16:9. Same limitation as the existing auto-crop path; flag in the header if it bites.
8. **D3 deletes public engine API.** No in-repo callers or tests; out-of-repo consumers unknown. If vetoed, keep them untouched and treat as dead (Risk 1 must then not describe them as used).
9. **Swift 6 isolation.** View members are `@MainActor` (SDK `View`); the `@Sendable` progress closure hops via `Task { @MainActor in self.… }` (DualDynamicHDRView:630). If CI's compiler objects to capturing `self` (a value-type View) in the `@Sendable` closure, capture `let sink = $progress` / `$statusText` bindings instead — do NOT weaken `@Sendable`. Existentials `any SmartCropFrameExtracting` / `any SubjectDetecting` are `Sendable` because the protocols are.
10. **`FFmpegProcessController` contract.** `startEncoding` appends `-nostdin -y … -progress pipe:1`; the extractor relies on `exitCode` being non-nil once the stream finishes (terminationHandler sets `.completed` before `finish()`, L224-232) and on `errorOutput` possibly being incomplete for very fast processes (used only in error text). The script fixtures locate the output by `*.png` so they're insensitive to argv position.
11. **Timing test (27)** is one-sided (`<= 2` frames requested); if it flakes on CI, raise the mock delay, not the assertion.
12. **Performance.** ~9 × (ffmpeg spawn + PNG encode + Vision) ≈ 3–8 s plus the black-bar pass ≈ 3–5 s on first use; mitigated by determinate progress, Cancel, a 3–21 frame stepper, and instant recompute on aspect/rule-of-thirds change (no re-analysis).
13. **Preview scale.** The preview is the 960-wide analysis PNG; overlays scale by the *source* dimensions, which is exact for the normalised subject boxes and within 1 px for the crop (the `-2` height rounding).
14. **App-module enqueue tests** construct `AppViewModel()` (StoreKit/`ScriptingBridge` side effects) exactly as `SettingsUndoManagerTests` already does; `enqueueSelectedFile` reads `UserDefaults.standard["conditionalRules"]` — a polluted defaults domain from another test could pick a different profile, in which case assert on `videoFilterChain` only (already the case).
15. **Pre-existing false docs out of scope:** `docs/Architecture.md:47,165` name a `SmartCropIntegration` type that does not exist in `Sources`; `ConverterEngineTests+QualityAndScene.swift:576-577` fixture omits the `limit:`/`crop=` fields real ffmpeg emits (parser verified against 8.1.2 regardless). `docs/distribution/rc4-known-limitations.md` does not mention Smart Crop, so no edit is required there.
16. **Concurrent edits.** HEAD moved from `9511291` to `0606746` during planning; `AppViewModel.swift` is edited by a sibling agent — re-verify the two `AppViewModel` anchors by text ("Apply a manually-selected Smart Crop filter" comment and the `pendingManualCropFilter` doc) before editing.