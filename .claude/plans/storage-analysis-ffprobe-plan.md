<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Implementation Plan — Storage Analysis reads REAL ffprobe metadata (#365)

> **Status: PLANNED.** Fable 5.1 deep-plan (2026-09-02) against HEAD `0606746` on
> `wip/alpha-consolidation`. `swift test` is CI-only; gate locally with the
> compile filter, push, and watch CI to green. Re-run `git log -1` before editing;
> if HEAD moved past `0606746`, re-verify the two target-file anchors (they were
> untouched by the last concurrent commit; the CHANGELOG was not — anchor it by text).

## Files

| Action | Path |
|---|---|
| **Modify** | `Sources/ConverterEngine/Utilities/StorageAnalyzer.swift` — `FileAnalysis.Provenance`, `MediaFileProbing` seam + `FFmpegProbe` conformance, `probeFiles`, `analysis(from:base:)`, `defaultProbeConcurrency`, codec-key normalisation, doc rewrites |
| **Modify** | `Sources/MeedyaConverter/Views/StorageAnalysisView.swift` (module `MeedyaConverterCore`, `path: "Sources/MeedyaConverter"`) — probe progress, Cancel, provenance caption, real ffprobe wiring, false-header fix |
| **Create** | `Tests/ConverterEngineTests/StorageAnalyzerProbeTests.swift` — mock prober, pure-mapping tests, bounded-concurrency/progress/cancellation tests, canned-JSON tests through real `FFmpegProbe` |
| **Modify** | `CHANGELOG.md` — one bullet, first under `## [Unreleased]` → `### Fixed` (anchor by text) |

Reference patterns (read, don't modify): `FFmpegProbe.swift` (canonical ffprobe path), `MediaScanner.swift:340-502` (sibling probe — what NOT to duplicate), `DualDynamicHDRPipelineExecutor.swift:69-75,206-216,243-246` (seam + `@Sendable` progress), `DualDynamicHDRPipelineExecutorTests.swift:35-78,89-104` (lock-guarded mock + `ProgressRecorder`, `import ConverterEngine` no `@testable`), `FFmpegProbeSuiteCoreCodecTests.swift:39-51` (shell-script ffprobe fixture), `DualDynamicHDRView.swift:60-63,99-101,536,580-582,629-634` (task cancel, off-main tool lookup, `Task { @MainActor in self.… }` progress hop).

## Current behaviour (verified)

`StorageAnalyzer.swift`
- `FileAnalysis` (L16-73): `id/url/fileSize/codec/resolution/container/hasHDR/duration`, public init L42-60. Doc L12-15 says fields come "from the file system and, where available, from media probing" — false today: nothing probes. L27 documents codec as `"h265"`.
- `scanDirectory` (L160-180) → `performScan` (L183-239): reads only `.fileSizeKey` (L212-217), `container = ext` (L218), then `inferCodec/inferResolution/inferHDR` from the FILE NAME (L220-223), `duration: nil` (L232).
- `inferCodec` (L327-351) returns `"h265"` for hevc/x265 hints (ffprobe's name is `"hevc"` → two keys). `inferResolution` (L354-370) matches `"hd"/"sd"` substrings. `inferHDR` (L373-377) matches `"dv"` (hits "dvd").
- `generateReport` (L248-283) groups by string keys; never fills `StorageReport.estimatedSavings` (default `[:]`).
- `estimateSavings` (L299-322) guesses duration from bytes via `estimateDurationFromSize` (L381-398). NO CALLER in any target — pre-existing dead public API.
- The only `FileAnalysis` constructor is `performScan` L225-233 → adding a required init param breaks nothing in-repo.

`StorageAnalysisView.swift`
- Header doc L13-17 promises "estimated savings per profile, and an 'Optimise' button" — neither exists. False comment.
- `@Environment(AppViewModel.self) private var viewModel` (L22) never used. `analysedFiles` (L36) written (L285), never read.
- `performScan` (L269-288): `scanDirectory` → `generateReport`; no progress, no cancel. Reachable via `ContentView.swift:170-171`, `SidebarView.swift:84`; `.storageAnalysis` NOT in `NavigationItem.unavailable`.

Engine facts
- Real ffprobe decode is `FFmpegProbe` (`public final class ... Sendable`; `init(ffprobePath:timeoutSeconds:byteCap:)`; `analyze(url:) async throws -> MediaFile` — requires file to exist). Parsing via `JSONSerialization` → `[String:Any]`; decode types are `MediaFile/MediaStream/ColourProperties/HDRFormat` (no Codable structs). Width/height, `hdrFormats` via `detectHDRFormats` (PQ/HLG transfer, HDR10+/DV side data, `dvhe/dvh1/dvav` codec names), format duration; disposition reads only default/forced (no `attached_pic`).
- `FFmpegProbe.runFFprobe` carries SECURITY.md F-007 protections (watchdog SIGTERM→SIGKILL, 10MB cap, independent pipe drainers). `MediaScanner.runFFprobe` is a bare Process with none.
- `MediaFile.primaryVideoStream/primaryAudioStream` prefer `isDefault`; `MediaStream.resolutionString` uses `"×"` while `FileAnalysis`/`MediaScanner` use `"x"`. `ColourProperties.isWideGamut` (primaries) separate from `isHDRTransfer`.
- ffprobe lookup: `FFmpegBundleManager.locateFFprobe() throws -> FFmpegBinaryInfo`, `.path`; user override first; missing → `FFmpegBundleError.ffprobeNotFound`; spawns `ffprobe -version` → run off main actor. The app's engine manager honours the Settings override (`AppViewModel.engine.bundleManager`); a fresh `FFmpegBundleManager()` IGNORES it. `EncodingEngine` `@unchecked Sendable` with `public let bundleManager`; `AppViewModel` `@MainActor @Observable` with `let engine`.
- `ParallelEncoder.resolveConcurrency` is a PAID-tier encode gate (returns 1 unless `.parallelEncoding`) — probing must NOT use it.
- `MetadataSource` already exists → new per-file enum is `Provenance` (no clash).
- Toolchain: local Swift 6.3.3; CI `macos-15` `swift test --parallel`; `.macOS(.v15)`, `.swiftLanguageMode(.v6)`. Use nothing newer than Swift 6.0 APIs.

## Design

Probe output = `MediaFile` from `FFmpegProbe` (house decode types + F-007 hardening + full HDR detection). Rejected: a third JSON parser or bare Process.

- **Seam.** `public protocol MediaFileProbing: Sendable { func analyze(url: URL) async throws -> MediaFile }` + `extension FFmpegProbe: MediaFileProbing {}` (same module, empty body). Tests inject `MockMediaFileProber`.
- **Pure builder** `analysis(from mediaFile: MediaFile, base: FileAnalysis) -> FileAnalysis`: keeps id/url/fileSize/container; replaces codec/resolution/hasHDR/duration; marks `.probed`.
  - Video stream = `videoStreams` minus still-image codecs (`mjpeg png bmp gif tiff webp`) ONLY when `base.container` is audio-only; prefer `isDefault` else first.
  - `codec` = video `codecName` ?? primary audio `codecName`.
  - `resolution` = `"WxH"` when both > 0 (keep `"x"` style).
  - `hasHDR` = `!videoStream.hdrFormats.isEmpty` (BT.2020 primaries alone is NOT HDR).
  - `duration` = container ?? video stream ?? longest stream; nil unless finite & > 0.
- **`probeFiles`** takes the `[FileAnalysis]` from `scanDirectory` (not `[URL]`). Bounded `withTaskGroup(of:(index:Int,analysis:FileAnalysis).self)` top-up on completion; results written by index → output order == input order. Per-file error → input entry unchanged (size-only degradation). Never throws. `progress` fires once per completed probe (`completed/total`), off main actor. `Task.isCancelled` checked before every schedule.
- **Ceiling** `defaultProbeConcurrency = max(1, min(4, activeProcessorCount/2))`; `maxConcurrency` clamped ≥ 1.
- **View** `performScan()` (MainActor, retained `scanTask`): scan → resolve ffprobe via `viewModel.engine.bundleManager.locateFFprobe()` in `Task.detached` → probe with progress hop `Task { @MainActor in self.probeProgress = fraction }` → `generateReport`. ffprobe not found → use scan as-is, caption says so. Cancel + `.onDisappear` cancel; on cancel discard partial (empty).
- **Fallback labelled** via `FileAnalysis.provenance` (`.probed`/`.inferredFromFilename`); caption from `analysedFiles`.
- **Dead/fallback**: `inferCodec/Resolution/HDR` become fallback-only (still called, now labelled). `estimateDurationFromSize` unchanged. `estimateSavings` + `StorageReport.estimatedSavings` stay pre-existing-dead (do NOT delete — Risk 2). Every new symbol is reached from `performScan()`.

## Exact changes — StorageAnalyzer.swift

1. `FileAnalysis` doc L12-15 → "Analysis result for a single media file… `scanDirectory` produces entries whose codec/resolution/HDR are guessed from the file name (`provenance == .inferredFromFilename`); `probeFiles(_:using:maxConcurrency:progress:)` replaces those guesses with ffprobe data (`.probed`) for every file it can read."
2. Add nested enum in `FileAnalysis` (after opening brace, before `id`):
```swift
/// How the codec / resolution / HDR / duration fields were obtained.
public enum Provenance: String, Sendable, Equatable {
    /// Read from the container by ffprobe (`StorageAnalyzer.probeFiles`).
    case probed
    /// Guessed from the file name and extension (`StorageAnalyzer.scanDirectory`);
    /// may be wrong or `nil`. Also what a file keeps when ffprobe cannot read it.
    case inferredFromFilename
}
```
3. L27 doc → `/// The video codec as ffprobe names it (e.g. "hevc", "h264", "av1"); for audio-only files the primary audio codec (e.g. "flac"). nil if unknown.`
4. Add stored prop after `duration`: `public let provenance: Provenance`.
5. Init: append REQUIRED param `provenance: Provenance` (no default) after `duration:`; assign.
6. Before `// MARK: - StorageAnalyzer`:
```swift
// MARK: - MediaFileProbing

/// Abstraction over "probe one file", so `StorageAnalyzer.probeFiles` can be
/// unit-tested with a mock. `FFmpegProbe` is the production conformer;
/// `StorageAnalysisView.performScan()` passes `FFmpegProbe(ffprobePath:)`
/// resolved via the app's `FFmpegBundleManager`.
public protocol MediaFileProbing: Sendable {
    func analyze(url: URL) async throws -> MediaFile
}

extension FFmpegProbe: MediaFileProbing {}
```
7. `StorageAnalyzer` type doc: 2nd paragraph → "Two stages: scanDirectory (file-system facts + file-name guesses, no subprocesses) then probeFiles (real ffprobe through an injected MediaFileProbing, bounded concurrency). StorageAnalysisView.performScan() runs both. estimateSavings estimates re-encode savings from FileSizeEstimator using probed durations when present." Keep "All methods are static."
8. Hoist `audioOnlyContainers` to `private static let audioOnlyContainers: Set<String> = ["mp3","m4a","aac","flac","wav","ogg","opus","wma"]`; make `estimateDurationFromSize` use `Self.audioOnlyContainers`. Add `private static let stillImageCodecs: Set<String> = ["mjpeg","png","bmp","gif","tiff","webp"]` and `public static var defaultProbeConcurrency: Int { max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2)) }`.
9. `scanDirectory` doc: add "Every entry is marked `.inferredFromFilename`: only size and container (extension) are facts; codec/resolution/HDR are file-name guesses and duration is nil. No ffprobe runs here — pass the result to probeFiles."
10. `performScan` FileAnalysis call: add `provenance: .inferredFromFilename`. Rewrite L220 comment → "File-name guesses only; replaced by real data in probeFiles(...) when ffprobe can read the file."
11. `inferCodec` return `"hevc"` not `"h265"` — comment "ffprobe's codec_name, so probed and inferred files share a report key."
12. New `// MARK: - Probing` section after Directory Scanning block (verbatim code):
```swift
public static func probeFiles(
    _ files: [FileAnalysis],
    using prober: any MediaFileProbing,
    maxConcurrency: Int = StorageAnalyzer.defaultProbeConcurrency,
    progress: (@Sendable (Double) -> Void)? = nil
) async -> [FileAnalysis] {
    guard !files.isEmpty else { return [] }
    let limit = max(1, maxConcurrency)
    let total = files.count

    return await withTaskGroup(of: (index: Int, analysis: FileAnalysis).self) { group in
        var results = files
        var completed = 0
        var nextIndex = 0

        while nextIndex < min(limit, total), !Task.isCancelled {
            let index = nextIndex
            group.addTask { (index: index, analysis: await probeOne(files[index], using: prober)) }
            nextIndex += 1
        }

        for await item in group {
            results[item.index] = item.analysis
            completed += 1
            progress?(Double(completed) / Double(total))

            if nextIndex < total, !Task.isCancelled {
                let index = nextIndex
                group.addTask { (index: index, analysis: await probeOne(files[index], using: prober)) }
                nextIndex += 1
            }
        }
        return results
    }
}

private static func probeOne(_ base: FileAnalysis, using prober: any MediaFileProbing) async -> FileAnalysis {
    do {
        return analysis(from: try await prober.analyze(url: base.url), base: base)
    } catch {
        return base
    }
}

public static func analysis(from mediaFile: MediaFile, base: FileAnalysis) -> FileAnalysis {
    let container = base.container ?? base.url.pathExtension.lowercased()
    let isAudioContainer = audioOnlyContainers.contains(container)
    let candidates = mediaFile.videoStreams.filter { stream in
        guard isAudioContainer else { return true }
        return !stillImageCodecs.contains(stream.codecName?.lowercased() ?? "")
    }
    let videoStream = candidates.first { $0.isDefault } ?? candidates.first
    let audioStream = mediaFile.primaryAudioStream

    let codec = videoStream?.codecName ?? audioStream?.codecName
    let resolution: String? = {
        guard let v = videoStream, let w = v.width, let h = v.height, w > 0, h > 0 else { return nil }
        return "\(w)x\(h)"
    }()
    let hasHDR = videoStream.map { !$0.hdrFormats.isEmpty } ?? false
    let rawDuration = mediaFile.duration
        ?? videoStream?.duration
        ?? mediaFile.streams.compactMap(\.duration).max()
    let duration = rawDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }

    return FileAnalysis(
        id: base.id, url: base.url, fileSize: base.fileSize,
        codec: codec, resolution: resolution, container: base.container,
        hasHDR: hasHDR, duration: duration, provenance: .probed
    )
}
```
Swift 6: declare `results/completed/nextIndex` INSIDE `withTaskGroup` (not `@Sendable`); `addTask` closures capture only `files`, `prober`, `index`. Full doc comments per the plan (probeFiles: order, never throws, empty→[], progress once per completed off-main, cancellation stops scheduling but FFmpegProbe.analyze ignores cancellation).
13. `estimateSavings` doc: add "Uses file.duration when a probe supplied it, otherwise estimateDurationFromSize."

## Exact changes — StorageAnalysisView.swift

1. Header doc L13-17 → describe folder picker, scan/probe progress with Cancel, breakdown lists, provenance caption; `performScan()` runs scanDirectory then probeFiles with FFmpegProbe resolved via `viewModel.engine.bundleManager`; ffprobe-not-found/unreadable → file-name guess + caption. `Phase 13 — Issue #365`.
2. State after L45: `@State private var probeProgress: Double?`, `@State private var probeTotal = 0`, `@State private var ffprobeLocated = false`, `@State private var scanTask: Task<Void, Never>?`. Rewrite `analysedFiles` doc → "read by provenanceCaption".
3. Body: add `.onDisappear { scanTask?.cancel() }`.
4. Scan header: Cancel button while `isScanning` (`scanTask?.cancel()`), else Scan button `scanTask = Task { await performScan() }` disabled when `selectedDirectory == nil`, `.keyboardShortcut(.defaultAction)`.
5. `scanningIndicator`: if `probeProgress` non-nil → `ProgressView(value:).progressViewStyle(.linear).frame(maxWidth:320)` + "Reading N files with ffprobe… X%"; else spinner + "Scanning media files...".
6. In `reportContent` between `summaryBar` and `Divider()` insert a `Label(caption.text, systemImage: warning ? "exclamationmark.triangle" : "checkmark.seal")` `.font(.caption)` colored orange/secondary; add `provenanceCaption` computed prop:
```swift
private var provenanceCaption: (text: String, isWarning: Bool)? {
    guard report != nil, !analysedFiles.isEmpty else { return nil }
    let total = analysedFiles.count
    let probed = analysedFiles.filter { $0.provenance == .probed }.count
    if !ffprobeLocated {
        return ("ffprobe was not found — codec, resolution and HDR are guessed from file names.", true)
    }
    if probed == total {
        return ("Codec, resolution and HDR were read by ffprobe for all \(total) files.", false)
    }
    return ("\(probed) of \(total) files were read by ffprobe; \(total - probed) could not be read and are guessed from file names.", true)
}
```
(use `AnyShapeStyle(.orange)`/`AnyShapeStyle(.secondary)` for the conditional `foregroundStyle`.)
7. Replace `performScan()` entirely (verbatim):
```swift
private func performScan() async {
    guard let directory = selectedDirectory else { return }

    isScanning = true
    report = nil
    analysedFiles = []
    probeProgress = nil
    probeTotal = 0
    ffprobeLocated = false

    let accessing = directory.startAccessingSecurityScopedResource()
    defer {
        if accessing { directory.stopAccessingSecurityScopedResource() }
        isScanning = false
    }

    let scanned = await StorageAnalyzer.scanDirectory(at: directory, recursive: scanRecursively)
    guard !Task.isCancelled else { return }

    let bundleManager = viewModel.engine.bundleManager
    let ffprobePath: String? = await Task.detached {
        try? bundleManager.locateFFprobe().path
    }.value
    guard !Task.isCancelled else { return }

    let files: [FileAnalysis]
    if let ffprobePath {
        ffprobeLocated = true
        probeTotal = scanned.count
        probeProgress = 0
        files = await StorageAnalyzer.probeFiles(
            scanned,
            using: FFmpegProbe(ffprobePath: ffprobePath)
        ) { fraction in
            Task { @MainActor in self.probeProgress = fraction }
        }
    } else {
        files = scanned
    }
    guard !Task.isCancelled else { return }

    analysedFiles = files
    report = StorageAnalyzer.generateReport(files: files)
}
```
Confirm the exact `scanDirectory` signature/labels and `scanRecursively`/`selectedDirectory`/`isScanning`/`report` names by reading the file. `viewModel` and `analysedFiles` are now both read.

## CHANGELOG.md
First bullet under `## [Unreleased]` → `### Fixed`:
```
- **Storage Analysis** now reads codec, resolution, HDR and duration with
  **ffprobe** (a few concurrent probes, with progress and Cancel) instead of
  guessing them from file names; files ffprobe cannot read keep the file-name
  guess and the report says how many did (#365).
```

## Tests — Tests/ConverterEngineTests/StorageAnalyzerProbeTests.swift
`import XCTest`, `import ConverterEngine` (no @testable). House header. `MockMediaFileProber: MediaFileProbing, @unchecked Sendable` (NSLock-guarded; `set(_:for:)`, `fail(_:)`, `var delay: Duration = .zero`; records `startedURLs`, `maxObservedConcurrency` via in-flight counter under lock; `analyze` sleeps `delay` then throws for failing/unknown URLs). `ProgressRecorder` copy. `tempDir` per test. Helpers `makeBase/makeVideo/makeAudio/makeMediaFile/makeFFprobeFixture` (last verbatim from FFmpegProbeSuiteCoreCodecTests:39-51 — script path doubles as media URL since analyze only needs the file to exist). Canned JSON A(HDR10 hevc 3840x2160 smpte2084), B(flac audio 245.5s), C(HLG hevc 1920x1080 arib-std-b67), D(SDR h264 1920x1080 bt709). 30 cases per the plan: mapping (1-13), probeFiles order/failure/progress/concurrency/clamp/cancel (14-21), real FFmpegProbe canned JSON (22-27), scan+report (28-30). Timing tests use 10-300ms sleeps, one-sided `<=` asserts only.

## Verification gates
```
swift build --target ConverterEngine
swift build 2>&1 | grep "error:" | grep -v "PreviewsMacros\|Preview(_:body:)\|external macro\|emit-module"   # empty
swiftc -parse Tests/ConverterEngineTests/StorageAnalyzerProbeTests.swift
```
Then commit, push, watch CI green.

## Risks (abridged — full list in session transcript)
1. False-comment/dead-code hygiene: rewrites 4 false claims; 2 dead view members become read; every new symbol has a caller.
2. `estimateSavings`/`estimatedSavings` stay pre-existing-dead (out of scope; follow-up: `generateReport(files:profiles:)` + a "Potential savings" section — what the header falsely promised).
3. Slower scan (one ffprobe/file); mitigated by bounded concurrency + determinate progress + Cancel + kept 60s watchdog.
4. Sandboxed/App Store: Process can't launch → all fall back, caption says so. No App Store parity claim.
5. HDR stricter than MediaScanner (BT.2020 primaries alone ≠ HDR). Deliberate; leave MediaScanner.
6. Cover-art heuristic only for audio-only containers (an .mp4 audiobook w/ art → mjpeg). Acceptable; constant for widening.
7. Fallback key change: `hevc` (HEVC) not `h265`. Required for shared bar.
8. Swift 6 isolation: `@Sendable` progress hops via `Task { @MainActor in self.… }` (matches DualDynamicHDRView:629-634). Fallback if CI Swift 6.0 objects: capture `Binding<Double?>` (`let sink = $probeProgress`); do NOT weaken `@Sendable`.
9. Required `provenance:` init param source-breaks out-of-repo constructors (none in-repo).
10. Cancellation discards results (deliberate; documented).
11. Timing tests one-sided; if flake, raise delay not assertion.
12. Concurrent branch edits: re-verify anchors vs current HEAD; CHANGELOG anchored by text.
