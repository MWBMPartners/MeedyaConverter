// ============================================================================
// MeedyaConverter — StorageAnalyzerProbeTests (Issue #365)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Coverage for the #365 slice: `StorageAnalyzer.probeFiles`/`analysis(from:
// base:)` replace a scan's file-name guesses with real ffprobe data through
// the `MediaFileProbing` seam.
//
// Three layers:
//   1. Pure mapping (`StorageAnalyzer.analysis(from:base:)`) against
//      hand-built `MediaFile`/`MediaStream` values — no I/O at all.
//   2. `StorageAnalyzer.probeFiles` sequencing/concurrency/progress/
//      cancellation against a `MockMediaFileProber` (a mock
//      `MediaFileProbing` conformer) — no real ffprobe/ffmpeg process.
//   3. The real `FFmpegProbe` (the production `MediaFileProbing` conformer)
//      driven through canned-JSON fixture scripts, following the pattern in
//      `FFmpegProbeSuiteCoreCodecTests`: a fake "ffprobe" is a shell script
//      that `cat`s pre-baked JSON, and `FFmpegProbe.analyze`'s only
//      precondition is that the target URL exists on disk — so the script's
//      own path doubles as the "media file" URL.
//   4. `StorageAnalyzer.scanDirectory`/`generateReport` — confirming the
//      inferred side of the seam (provenance tagging, the `hevc` fallback
//      codec key that now matches ffprobe's own `codec_name`).
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching `DualDynamicHDRPipelineExecutorTests`.
// ---------------------------------------------------------------------------

import Foundation
import XCTest
import ConverterEngine

// MARK: - MockMediaFileProber

/// A `MediaFileProbing` conformer that never touches a real ffprobe binary.
///
/// Configure it with `set(_:for:)` (a URL returns that `MediaFile`) or
/// `fail(_:)` (a URL always throws). A URL that was never configured either
/// way also throws — `probeFiles` must treat "unknown" the same as
/// "explicitly failing": the base `FileAnalysis` is kept unchanged.
///
/// `analyze(url:)` records every URL it was called for (`startedURLs`, in
/// call-start order) and tracks the high-water mark of concurrently
/// in-flight calls (`maxObservedConcurrency`), so tests can assert on
/// `StorageAnalyzer.probeFiles`'s bounded-concurrency behaviour without
/// depending on wall-clock timing beyond a configured artificial `delay`.
final class MockMediaFileProber: MediaFileProbing, @unchecked Sendable {
    /// Thrown by `analyze(url:)` for a URL registered via `fail(_:)`, or
    /// for any URL never registered via `set(_:for:)` at all.
    struct ProbeFailure: Error, Equatable {
        let url: URL
    }

    private let lock = NSLock()
    private var _results: [URL: MediaFile] = [:]
    private var _failures: Set<URL> = []
    private var _startedURLs: [URL] = []
    private var _inFlight = 0
    private var _maxObservedConcurrency = 0
    private var _delay: Duration = .zero
    private var _perURLDelay: [URL: Duration] = [:]

    /// Artificial delay applied to every call unless overridden per-URL via
    /// `setDelay(_:for:)`. Lets tests force overlap so bounded-concurrency
    /// and cancellation behaviour is observable.
    var delay: Duration {
        get { lock.withLock { _delay } }
        set { lock.withLock { _delay = newValue } }
    }

    /// URLs `analyze(url:)` was called for, in the order each call started.
    var startedURLs: [URL] {
        lock.withLock { _startedURLs }
    }

    /// The largest number of `analyze(url:)` calls observed in flight at
    /// once (i.e. started but not yet returned/thrown).
    var maxObservedConcurrency: Int {
        lock.withLock { _maxObservedConcurrency }
    }

    func set(_ mediaFile: MediaFile, for url: URL) {
        lock.withLock { _results[url] = mediaFile }
    }

    func fail(_ url: URL) {
        lock.withLock { _failures.insert(url) }
    }

    func setDelay(_ delay: Duration, for url: URL) {
        lock.withLock { _perURLDelay[url] = delay }
    }

    func analyze(url: URL) async throws -> MediaFile {
        let effectiveDelay: Duration = lock.withLock {
            _startedURLs.append(url)
            _inFlight += 1
            _maxObservedConcurrency = max(_maxObservedConcurrency, _inFlight)
            return _perURLDelay[url] ?? _delay
        }
        defer {
            lock.withLock { _inFlight -= 1 }
        }

        if effectiveDelay > .zero {
            try? await Task.sleep(for: effectiveDelay)
        }

        let (result, shouldFail): (MediaFile?, Bool) = lock.withLock {
            (_results[url], _failures.contains(url))
        }
        guard !shouldFail, let result else {
            throw ProbeFailure(url: url)
        }
        return result
    }
}

// MARK: - DoubleProgressRecorder

/// Records `probeFiles`'s `progress` callback invocations under a lock.
/// The callback is a plain `@Sendable (Double) -> Void`, not actor-isolated
/// — mirrors `ProgressRecorder` in `DualDynamicHDRPipelineExecutorTests`.
final class DoubleProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []

    var values: [Double] {
        lock.withLock { recorded }
    }

    func record(_ value: Double) {
        lock.withLock { recorded.append(value) }
    }
}

// MARK: - StorageAnalyzerProbeTests

final class StorageAnalyzerProbeTests: XCTestCase {

    // MARK: - Fixture helpers

    private var fixturesToCleanUp: [String] = []

    override func tearDown() {
        for path in fixturesToCleanUp {
            try? FileManager.default.removeItem(atPath: path)
        }
        fixturesToCleanUp.removeAll()
        super.tearDown()
    }

    /// Writes `json` to a temp file and a companion shell script that
    /// `cat`s it — stands in for `ffprobe -show_streams -show_format
    /// -print_format json ...`. Returns the executable script's path.
    /// Verbatim pattern from `FFmpegProbeSuiteCoreCodecTests`.
    private func makeFFprobeFixture(json: String) throws -> String {
        let jsonPath = NSTemporaryDirectory() + "storage-analyzer-fixture-\(UUID().uuidString).json"
        try json.write(toFile: jsonPath, atomically: true, encoding: .utf8)
        fixturesToCleanUp.append(jsonPath)

        let scriptPath = NSTemporaryDirectory() + "storage-analyzer-fixture-\(UUID().uuidString).sh"
        let script = "#!/bin/sh\ncat \"\(jsonPath)\"\n"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        fixturesToCleanUp.append(scriptPath)

        return scriptPath
    }

    /// A fake "ffprobe" that always exits non-zero — exercises the
    /// `FFmpegProbeError.probeFailed` path through `probeFiles`.
    private func makeFailingFFprobeFixture() throws -> String {
        let scriptPath = NSTemporaryDirectory() + "storage-analyzer-fixture-\(UUID().uuidString)-fail.sh"
        let script = "#!/bin/sh\necho 'synthetic ffprobe failure' 1>&2\nexit 1\n"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        fixturesToCleanUp.append(scriptPath)
        return scriptPath
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-analyzer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fixturesToCleanUp.append(dir.path)
        return dir
    }

    // MARK: - Model helpers

    private func makeBase(
        url: URL = URL(fileURLWithPath: "/tmp/storage-analyzer-tests/movie.mkv"),
        fileSize: Int64 = 1_000_000,
        codec: String? = "hevc",
        resolution: String? = nil,
        container: String? = "mkv",
        hasHDR: Bool = false,
        provenance: FileAnalysis.Provenance = .inferredFromFilename
    ) -> FileAnalysis {
        FileAnalysis(
            url: url, fileSize: fileSize, codec: codec, resolution: resolution,
            container: container, hasHDR: hasHDR, duration: nil, provenance: provenance
        )
    }

    private func makeVideoStream(
        codecName: String? = "hevc",
        isDefault: Bool = true,
        width: Int? = 1920,
        height: Int? = 1080,
        hdrFormats: [HDRFormat] = [],
        colourProperties: ColourProperties? = nil,
        duration: TimeInterval? = nil
    ) -> MediaStream {
        MediaStream(
            streamIndex: 0, streamType: .video, codecName: codecName, duration: duration,
            isDefault: isDefault, width: width, height: height,
            hdrFormats: hdrFormats, colourProperties: colourProperties
        )
    }

    private func makeAudioStream(
        codecName: String? = "aac",
        isDefault: Bool = true,
        duration: TimeInterval? = nil
    ) -> MediaStream {
        MediaStream(streamIndex: 1, streamType: .audio, codecName: codecName, duration: duration, isDefault: isDefault)
    }

    private func makeMediaFile(
        url: URL,
        duration: TimeInterval? = nil,
        streams: [MediaStream] = []
    ) -> MediaFile {
        MediaFile(fileURL: url, streams: streams, duration: duration)
    }

    // ------------------------------------------------------------------
    // MARK: - Mapping: StorageAnalyzer.analysis(from:base:)
    // ------------------------------------------------------------------

    func test_analysis_preservesBaseIdentityFileSizeAndContainer_andSetsProbedProvenance() {
        let base = makeBase(fileSize: 12345, container: "mp4", provenance: .inferredFromFilename)
        let mediaFile = makeMediaFile(url: base.url, streams: [])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.id, base.id)
        XCTAssertEqual(result.url, base.url)
        XCTAssertEqual(result.fileSize, 12345)
        XCTAssertEqual(result.container, "mp4")
        XCTAssertEqual(result.provenance, .probed)
    }

    func test_analysis_videoStream_prefersDefaultDispositionOverFirst() {
        let base = makeBase()
        let notDefault = makeVideoStream(codecName: "h264", isDefault: false, width: 1280, height: 720)
        let isDefaultStream = makeVideoStream(codecName: "hevc", isDefault: true, width: 3840, height: 2160)
        let mediaFile = makeMediaFile(url: base.url, streams: [notDefault, isDefaultStream])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "hevc")
        XCTAssertEqual(result.resolution, "3840x2160")
    }

    func test_analysis_videoStream_fallsBackToFirstStreamWhenNoneIsDefault() {
        let base = makeBase()
        let first = makeVideoStream(codecName: "h264", isDefault: false, width: 1280, height: 720)
        let second = makeVideoStream(codecName: "hevc", isDefault: false, width: 3840, height: 2160)
        let mediaFile = makeMediaFile(url: base.url, streams: [first, second])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "h264")
        XCTAssertEqual(result.resolution, "1280x720")
    }

    func test_analysis_codec_prefersVideoCodecNameOverAudioCodecName() {
        let base = makeBase()
        let video = makeVideoStream(codecName: "hevc")
        let audio = makeAudioStream(codecName: "aac")
        let mediaFile = makeMediaFile(url: base.url, streams: [video, audio])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "hevc")
    }

    func test_analysis_codec_fallsBackToAudioCodecNameWhenNoVideoStream() {
        let base = makeBase(container: "flac")
        let audio = makeAudioStream(codecName: "flac")
        let mediaFile = makeMediaFile(url: base.url, streams: [audio])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "flac")
        XCTAssertNil(result.resolution)
        XCTAssertFalse(result.hasHDR)
    }

    func test_analysis_codec_isNilWhenNoStreamsAtAll() {
        let base = makeBase()
        let mediaFile = makeMediaFile(url: base.url, streams: [])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertNil(result.codec)
        XCTAssertNil(result.resolution)
        XCTAssertFalse(result.hasHDR)
    }

    func test_analysis_resolution_usesLowercaseXSeparator() {
        let base = makeBase()
        let video = makeVideoStream(width: 1920, height: 1080)
        let mediaFile = makeMediaFile(url: base.url, streams: [video])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.resolution, "1920x1080")
        XCTAssertFalse(result.resolution?.contains("×") ?? true, "must use a lowercase ASCII x, not MediaStream.resolutionString's × separator")
    }

    func test_analysis_resolution_isNilWhenWidthOrHeightMissing() {
        let base = makeBase()
        let video = makeVideoStream(width: nil, height: 1080)
        let mediaFile = makeMediaFile(url: base.url, streams: [video])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertNil(result.resolution)
    }

    func test_analysis_resolution_isNilWhenWidthOrHeightIsZero() {
        let base = makeBase()
        let video = makeVideoStream(width: 0, height: 1080)
        let mediaFile = makeMediaFile(url: base.url, streams: [video])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertNil(result.resolution)
    }

    func test_analysis_hasHDR_trueWhenVideoStreamHasHDRFormats() {
        let base = makeBase()
        let video = makeVideoStream(hdrFormats: [.pq, .hdr10])
        let mediaFile = makeMediaFile(url: base.url, streams: [video])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertTrue(result.hasHDR)
    }

    func test_analysis_hasHDR_falseForWideGamutPrimariesAloneWithoutHDRFormats() {
        let base = makeBase()
        let video = makeVideoStream(hdrFormats: [], colourProperties: ColourProperties(primaries: "bt2020"))
        let mediaFile = makeMediaFile(url: base.url, streams: [video])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertFalse(result.hasHDR, "BT.2020 primaries alone must not be treated as HDR — only hdrFormats decides")
    }

    func test_analysis_duration_prefersContainerDurationOverStreamDurations() {
        let base = makeBase()
        let video = makeVideoStream(duration: 50)
        let mediaFile = makeMediaFile(url: base.url, duration: 120, streams: [video])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.duration, 120)
    }

    func test_analysis_duration_fallsBackToVideoStreamDurationWhenNoContainerDuration() {
        let base = makeBase()
        let video = makeVideoStream(duration: 50)
        let mediaFile = makeMediaFile(url: base.url, duration: nil, streams: [video])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.duration, 50)
    }

    func test_analysis_duration_fallsBackToLongestStreamDurationWhenNoContainerOrVideoDuration() {
        let base = makeBase(container: "flac")
        let audio1 = makeAudioStream(duration: 30)
        let audio2 = makeAudioStream(duration: 90)
        let mediaFile = makeMediaFile(url: base.url, duration: nil, streams: [audio1, audio2])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.duration, 90)
    }

    func test_analysis_duration_isNilWhenNonPositiveOrNonFinite() {
        let base = makeBase()

        XCTAssertNil(StorageAnalyzer.analysis(from: makeMediaFile(url: base.url, duration: 0), base: base).duration)
        XCTAssertNil(StorageAnalyzer.analysis(from: makeMediaFile(url: base.url, duration: -5), base: base).duration)
        XCTAssertNil(StorageAnalyzer.analysis(from: makeMediaFile(url: base.url, duration: .nan), base: base).duration)
        XCTAssertNil(StorageAnalyzer.analysis(from: makeMediaFile(url: base.url, duration: .infinity), base: base).duration)
    }

    func test_analysis_audioOnlyContainer_excludesStillImageCoverArtFromVideoCandidates() {
        let base = makeBase(container: "mp3")
        let coverArt = makeVideoStream(codecName: "mjpeg", isDefault: true, width: 600, height: 600)
        let audio = makeAudioStream(codecName: "mp3")
        let mediaFile = makeMediaFile(url: base.url, streams: [coverArt, audio])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "mp3", "embedded cover art must not be reported as the file's video codec")
        XCTAssertNil(result.resolution, "embedded cover art dimensions must not be reported as the file's resolution")
    }

    func test_analysis_nonAudioContainer_doesNotExcludeStillImageCodecs() {
        let base = makeBase(container: "mp4")
        let mjpegVideo = makeVideoStream(codecName: "mjpeg", isDefault: true, width: 1920, height: 1080)
        let mediaFile = makeMediaFile(url: base.url, streams: [mjpegVideo])

        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "mjpeg", "the still-image exclusion only applies to audio-only containers")
        XCTAssertEqual(result.resolution, "1920x1080")
    }

    // ------------------------------------------------------------------
    // MARK: - StorageAnalyzer.probeFiles (mock prober)
    // ------------------------------------------------------------------

    func test_probeFiles_preservesInputOrderRegardlessOfCompletionOrder() async {
        let mock = MockMediaFileProber()
        let files = (0..<4).map { i in
            makeBase(url: URL(fileURLWithPath: "/tmp/storage-analyzer-tests/order\(i).mkv"), codec: nil)
        }
        for (i, file) in files.enumerated() {
            mock.set(makeMediaFile(url: file.url, streams: [makeVideoStream(codecName: "codec-\(i)")]), for: file.url)
        }
        // File 0 finishes last; the rest finish quickly — proves results are
        // written back by index, not by completion order.
        mock.setDelay(.milliseconds(150), for: files[0].url)
        for file in files.dropFirst() {
            mock.setDelay(.milliseconds(5), for: file.url)
        }

        let results = await StorageAnalyzer.probeFiles(files, using: mock, maxConcurrency: files.count)

        XCTAssertEqual(results.count, 4)
        for (i, result) in results.enumerated() {
            XCTAssertEqual(result.codec, "codec-\(i)", "result at index \(i) must correspond to input file \(i)")
        }
    }

    func test_probeFiles_keepsBaseUnchangedOnExplicitFailure() async {
        let mock = MockMediaFileProber()
        let base = makeBase(codec: "h264", resolution: "1280x720")
        mock.fail(base.url)

        let results = await StorageAnalyzer.probeFiles([base], using: mock)

        let result = results[0]
        XCTAssertEqual(result.codec, "h264")
        XCTAssertEqual(result.resolution, "1280x720")
        XCTAssertEqual(result.provenance, .inferredFromFilename)
    }

    func test_probeFiles_leavesEntryUnchanged_whenURLWasNeverConfigured() async {
        let mock = MockMediaFileProber()
        let base = makeBase(codec: "av1", resolution: "3840x2160")

        let results = await StorageAnalyzer.probeFiles([base], using: mock)

        let result = results[0]
        XCTAssertEqual(result.codec, "av1")
        XCTAssertEqual(result.resolution, "3840x2160")
        XCTAssertEqual(result.provenance, .inferredFromFilename)
    }

    func test_probeFiles_emptyInput_returnsEmptyAndNeverCallsProgress() async {
        let mock = MockMediaFileProber()
        let recorder = DoubleProgressRecorder()

        let results = await StorageAnalyzer.probeFiles([], using: mock) { fraction in
            recorder.record(fraction)
        }

        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(recorder.values.isEmpty, "progress must never be called for an empty input")
    }

    func test_probeFiles_progress_calledOncePerCompletedFile_reachingOne() async {
        let mock = MockMediaFileProber()
        let files = (0..<4).map { i in
            makeBase(url: URL(fileURLWithPath: "/tmp/storage-analyzer-tests/progress\(i).mkv"))
        }
        for file in files {
            mock.set(makeMediaFile(url: file.url, streams: [makeVideoStream()]), for: file.url)
        }
        let recorder = DoubleProgressRecorder()

        _ = await StorageAnalyzer.probeFiles(files, using: mock, maxConcurrency: 2) { fraction in
            recorder.record(fraction)
        }

        let values = recorder.values
        XCTAssertEqual(values.count, 4, "progress must be called exactly once per completed file, not once per file scheduled")
        XCTAssertEqual(values.last, 1.0)
        XCTAssertTrue(values.allSatisfy { $0 > 0 && $0 <= 1 })
    }

    func test_probeFiles_boundsConcurrencyToMaxConcurrency() async {
        let mock = MockMediaFileProber()
        mock.delay = .milliseconds(60)
        let files = (0..<6).map { i in
            makeBase(url: URL(fileURLWithPath: "/tmp/storage-analyzer-tests/bound\(i).mkv"))
        }
        for file in files {
            mock.set(makeMediaFile(url: file.url, streams: [makeVideoStream()]), for: file.url)
        }

        let results = await StorageAnalyzer.probeFiles(files, using: mock, maxConcurrency: 2)

        XCTAssertEqual(results.count, 6)
        XCTAssertEqual(mock.startedURLs.count, 6, "every file must eventually be probed")
        XCTAssertLessThanOrEqual(mock.maxObservedConcurrency, 2, "must never exceed the requested maxConcurrency")
    }

    func test_probeFiles_clampsMaxConcurrencyBelowOneToOne() async {
        let mock = MockMediaFileProber()
        mock.delay = .milliseconds(30)
        let files = (0..<3).map { i in
            makeBase(url: URL(fileURLWithPath: "/tmp/storage-analyzer-tests/clamp\(i).mkv"))
        }
        for file in files {
            mock.set(makeMediaFile(url: file.url, streams: [makeVideoStream()]), for: file.url)
        }

        let results = await StorageAnalyzer.probeFiles(files, using: mock, maxConcurrency: 0)

        XCTAssertEqual(results.count, 3)
        XCTAssertLessThanOrEqual(mock.maxObservedConcurrency, 1, "maxConcurrency <= 0 must be clamped to 1, never 0 (which would hang)")
    }

    func test_probeFiles_cancellation_stopsSchedulingNewProbes() async {
        let mock = MockMediaFileProber()
        mock.delay = .milliseconds(150)
        let files = (0..<6).map { i in
            makeBase(url: URL(fileURLWithPath: "/tmp/storage-analyzer-tests/cancel\(i).mkv"))
        }
        for file in files {
            mock.set(makeMediaFile(url: file.url, streams: [makeVideoStream()]), for: file.url)
        }

        let task = Task {
            await StorageAnalyzer.probeFiles(files, using: mock, maxConcurrency: 2)
        }
        // Give the task group time to schedule its initial (bounded) batch
        // before requesting cancellation — the in-flight probes' 150ms
        // delay keeps them running well past this point.
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let results = await task.value

        XCTAssertEqual(results.count, 6, "probeFiles must always return one entry per input file, cancelled or not")
        XCTAssertLessThanOrEqual(mock.startedURLs.count, 2, "cancellation must stop scheduling probes beyond the in-flight batch")
    }

    // ------------------------------------------------------------------
    // MARK: - Real FFmpegProbe (canned-JSON fixtures)
    // ------------------------------------------------------------------

    /// HDR10 — hevc, 3840×2160, PQ (SMPTE ST 2084) transfer.
    private let fixtureHDR10HevcJSON = """
    {
        "streams": [
            {
                "index": 0,
                "codec_name": "hevc",
                "codec_type": "video",
                "width": 3840,
                "height": 2160,
                "color_transfer": "smpte2084",
                "color_primaries": "bt2020",
                "disposition": { "default": 1, "forced": 0 }
            }
        ],
        "format": {
            "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
            "duration": "3600.000000"
        }
    }
    """

    /// HLG — hevc, 1920×1080, ARIB STD-B67 transfer.
    private let fixtureHLGHevcJSON = """
    {
        "streams": [
            {
                "index": 0,
                "codec_name": "hevc",
                "codec_type": "video",
                "width": 1920,
                "height": 1080,
                "color_transfer": "arib-std-b67",
                "disposition": { "default": 1, "forced": 0 }
            }
        ],
        "format": {
            "format_name": "matroska,webm",
            "duration": "600.000000"
        }
    }
    """

    /// SDR — h264, 1920×1080, BT.709 transfer.
    private let fixtureSDRH264JSON = """
    {
        "streams": [
            {
                "index": 0,
                "codec_name": "h264",
                "codec_type": "video",
                "width": 1920,
                "height": 1080,
                "color_transfer": "bt709",
                "disposition": { "default": 1, "forced": 0 }
            }
        ],
        "format": {
            "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
            "duration": "300.000000"
        }
    }
    """

    /// FLAC — audio-only, no video stream.
    private let fixtureFlacAudioJSON = """
    {
        "streams": [
            {
                "index": 0,
                "codec_name": "flac",
                "codec_type": "audio",
                "sample_rate": "44100",
                "channels": 2,
                "channel_layout": "stereo",
                "disposition": { "default": 1, "forced": 0 }
            }
        ],
        "format": {
            "format_name": "flac",
            "duration": "245.500000"
        }
    }
    """

    func test_realFFmpegProbe_hdr10Hevc_mapsCodecResolutionHDRAndDuration() async throws {
        let scriptPath = try makeFFprobeFixture(json: fixtureHDR10HevcJSON)
        let probe = FFmpegProbe(ffprobePath: scriptPath)
        let base = makeBase(url: URL(fileURLWithPath: scriptPath), codec: nil, container: "mp4")

        let mediaFile = try await probe.analyze(url: base.url)
        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "hevc")
        XCTAssertEqual(result.resolution, "3840x2160")
        XCTAssertTrue(result.hasHDR)
        XCTAssertEqual(result.duration, 3600)
        XCTAssertEqual(result.provenance, .probed)
    }

    func test_realFFmpegProbe_hlgHevc_mapsAsHDR() async throws {
        let scriptPath = try makeFFprobeFixture(json: fixtureHLGHevcJSON)
        let probe = FFmpegProbe(ffprobePath: scriptPath)
        let base = makeBase(url: URL(fileURLWithPath: scriptPath), codec: nil, container: "mkv")

        let mediaFile = try await probe.analyze(url: base.url)
        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "hevc")
        XCTAssertEqual(result.resolution, "1920x1080")
        XCTAssertTrue(result.hasHDR, "HLG (ARIB STD-B67 transfer) must be detected as HDR")
    }

    func test_realFFmpegProbe_sdrH264_hasHDRFalse() async throws {
        let scriptPath = try makeFFprobeFixture(json: fixtureSDRH264JSON)
        let probe = FFmpegProbe(ffprobePath: scriptPath)
        let base = makeBase(url: URL(fileURLWithPath: scriptPath), codec: nil, container: "mp4")

        let mediaFile = try await probe.analyze(url: base.url)
        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "h264")
        XCTAssertEqual(result.resolution, "1920x1080")
        XCTAssertFalse(result.hasHDR)
    }

    func test_realFFmpegProbe_flacAudioOnly_mapsCodecAndDuration_noResolution() async throws {
        let scriptPath = try makeFFprobeFixture(json: fixtureFlacAudioJSON)
        let probe = FFmpegProbe(ffprobePath: scriptPath)
        let base = makeBase(url: URL(fileURLWithPath: scriptPath), codec: nil, container: "flac")

        let mediaFile = try await probe.analyze(url: base.url)
        let result = StorageAnalyzer.analysis(from: mediaFile, base: base)

        XCTAssertEqual(result.codec, "flac")
        XCTAssertNil(result.resolution)
        XCTAssertFalse(result.hasHDR)
        XCTAssertEqual(result.duration, 245.5)
    }

    func test_probeFiles_realFFmpegProbe_ffprobeExitsNonZero_leavesEntryUnchanged() async throws {
        let scriptPath = try makeFailingFFprobeFixture()
        let probe = FFmpegProbe(ffprobePath: scriptPath)
        let base = makeBase(url: URL(fileURLWithPath: scriptPath), codec: "h264", resolution: "1920x1080")

        let results = await StorageAnalyzer.probeFiles([base], using: probe)

        let result = results[0]
        XCTAssertEqual(result.codec, "h264")
        XCTAssertEqual(result.resolution, "1920x1080")
        XCTAssertEqual(result.provenance, .inferredFromFilename)
    }

    func test_probeFiles_endToEnd_withRealFFmpegProbe() async throws {
        // The fixture script ignores its arguments and always emits the
        // same canned JSON, so every file probed through this one
        // `FFmpegProbe` instance maps to the same `MediaFile`. The point of
        // this test is the plumbing — StorageAnalyzer.probeFiles driving
        // the real, production `MediaFileProbing` conformer across several
        // files with bounded concurrency and order preservation — not
        // per-file content variety (covered by the single-fixture tests
        // above).
        let hdrScript = try makeFFprobeFixture(json: fixtureHDR10HevcJSON)
        let otherExistingFile1 = try makeFFprobeFixture(json: fixtureSDRH264JSON)
        let otherExistingFile2 = try makeFFprobeFixture(json: fixtureFlacAudioJSON)
        let probe = FFmpegProbe(ffprobePath: hdrScript)

        let files = [
            makeBase(url: URL(fileURLWithPath: hdrScript), codec: nil, container: "mp4"),
            makeBase(url: URL(fileURLWithPath: otherExistingFile1), codec: nil, container: "mp4"),
            makeBase(url: URL(fileURLWithPath: otherExistingFile2), codec: nil, container: "mp4"),
        ]

        let results = await StorageAnalyzer.probeFiles(files, using: probe, maxConcurrency: 2)

        XCTAssertEqual(results.count, 3)
        for (index, result) in results.enumerated() {
            XCTAssertEqual(result.id, files[index].id, "order must be preserved")
            XCTAssertEqual(result.codec, "hevc")
            XCTAssertTrue(result.hasHDR)
            XCTAssertEqual(result.provenance, .probed)
        }
    }

    // ------------------------------------------------------------------
    // MARK: - scanDirectory / generateReport
    // ------------------------------------------------------------------

    func test_scanDirectory_marksEntriesInferredFromFilename_sizeAndContainerAreFacts() async throws {
        let dir = try makeTempDirectory()
        let fileURL = dir.appendingPathComponent("movie.mkv")
        let content = Data(repeating: 0x41, count: 2048)
        try content.write(to: fileURL)

        let results = await StorageAnalyzer.scanDirectory(at: dir, recursive: false)

        XCTAssertEqual(results.count, 1)
        let result = results[0]
        XCTAssertEqual(result.provenance, .inferredFromFilename)
        XCTAssertEqual(result.container, "mkv")
        XCTAssertEqual(result.fileSize, Int64(content.count))
        XCTAssertNil(result.duration, "scanDirectory never sets duration — only probeFiles can")
    }

    func test_scanDirectory_inferCodec_returnsHevcNotH265_soReportKeysMatchProbedFiles() async throws {
        let dir = try makeTempDirectory()
        let fileURL = dir.appendingPathComponent("movie.x265.mkv")
        try Data([0x00]).write(to: fileURL)

        let results = await StorageAnalyzer.scanDirectory(at: dir, recursive: false)

        XCTAssertEqual(results.first?.codec, "hevc", "the fallback codec key must be ffprobe's own \"hevc\", not the old \"h265\"")
    }

    func test_generateReport_groupsProbedAndInferredHevcFilesUnderSameKey() {
        let probedURL = URL(fileURLWithPath: "/tmp/storage-analyzer-tests/probed.mkv")
        let probedBase = makeBase(url: probedURL, codec: nil)
        let probedMediaFile = makeMediaFile(url: probedURL, streams: [makeVideoStream(codecName: "hevc", width: 1920, height: 1080)])
        let probedFile = StorageAnalyzer.analysis(from: probedMediaFile, base: probedBase)

        let inferredFile = makeBase(
            url: URL(fileURLWithPath: "/tmp/storage-analyzer-tests/inferred.x265.mkv"),
            codec: "hevc",
            provenance: .inferredFromFilename
        )

        let report = StorageAnalyzer.generateReport(files: [probedFile, inferredFile])

        XCTAssertEqual(report.byCodec["hevc"]?.count, 2, "probed and file-name-inferred HEVC files must share one report key")
        XCTAssertNil(report.byCodec["h265"], "the old h265 key must no longer be produced")
    }
}
