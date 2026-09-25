// ============================================================================
// MeedyaConverter — AutoTagEncodeDeliveryTests (Issue #508, commit 6/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Proves DELIVERY: that a looked-up tag actually reaches the argument list a
// real `EncodingEngine.encode(job:onProgress:)` launches FFmpeg with — not
// merely that some function returned the right dictionary. The runner's own
// decisions (scoring, ambiguity, the deadline, …) are pinned by
// `AutoTagRunnerTests`; this file pins the wiring around it.
//
// HOW. Every test builds a private folder holding:
//   * a fake `ffmpeg` — a shell script that answers `-version` (so
//     `configure()` accepts it) and otherwise writes its whole argument list,
//     each argument followed by a NUL byte, to a file, then exits 0. The
//     engine adds `-progress pipe:1` AFTER the output path, so nothing here
//     treats the last argument as the output;
//   * a fake `ffprobe` — prints JSON for a ~148-minute h264 + AAC Matroska
//     file, with whatever format tags the test asks for;
//   * an empty input file named "Inception (2010).mkv", which is all the
//     engine checks exists.
// HTTP goes to a private stub client; nothing touches the network.
//
// A FIXTURE TRAP (found while building #508 commit 4). The film search is
// seeded from the file's `title` tag in preference to its name. A title tag
// that does not match the film ("My own title") scores 0 for the title, so
// the best possible score is 0.5 + 0 + 0.15 = 0.65 — below the 0.7
// threshold — and nothing would ever be tagged. The fixtures therefore use
// a MATCHING title tag ("Inception"), and prove "the file's own tags are
// never replaced" with a different tag TMDB would also write: `genre`.
//
// A "baseline" below is the argument list the SAME job produces on an engine
// with no auto-tag settings source at all — i.e. exactly what every encode
// did before #508.
//
// Public API only (`import ConverterEngine`, no `@testable`).
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// MARK: - Fixtures shared by the helpers below

/// A v3 TMDB key: 32 hex characters, sent in the URL — the form that can
/// leak. File-level so `@Sendable` closures can use it without capturing the
/// test case.
private let autoTagDeliveryTestKey = "fedcba9876543210fedcba9876543210"

private let autoTagDeliveryInceptionID = 27205

/// Thrown to end a test that has already recorded an `XCTFail`, so it stops
/// instead of carrying on (or hanging) in a state that means nothing.
private struct AutoTagDeliveryGaveUp: Error {
    let what: String
}

// MARK: - AutoTagDeliveryStubHTTPClient

/// Records every request and answers it as the current `route` says. The
/// route can be replaced mid-test (the stop test re-runs a job against a
/// working server). Uniquely named so it never collides with the other stub
/// clients in this test module.
private final class AutoTagDeliveryStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {

    enum Reply: Sendable {
        /// Answer with this status and body.
        case respond(status: Int, body: Data)
        /// Fail the way URLSession does when there is no network.
        case transportError(URLError)
        /// Never answer: suspend until the calling task is cancelled, then
        /// throw `URLError(.cancelled)` exactly as URLSession does.
        case hang
    }

    private let lock = NSLock()
    private var route: @Sendable (URLRequest) -> Reply
    private var recorded: [URLRequest] = []
    private var cancelled = 0

    init(route: @escaping @Sendable (URLRequest) -> Reply) {
        self.route = route
    }

    var requestCount: Int { lock.withLock { recorded.count } }
    var requests: [URLRequest] { lock.withLock { recorded } }
    /// How many `.hang` requests were ended by cancellation.
    var cancelledCount: Int { lock.withLock { cancelled } }

    func replaceRoute(_ newRoute: @escaping @Sendable (URLRequest) -> Reply) {
        lock.withLock { route = newRoute }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let currentRoute: @Sendable (URLRequest) -> Reply = lock.withLock {
            recorded.append(request)
            return route
        }

        switch currentRoute(request) {
        case .respond(let status, let body):
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"),
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )
            guard let response else { throw URLError(.badServerResponse) }
            return (body, response)
        case .transportError(let error):
            throw error
        case .hang:
            do {
                try await AutoTagDeliveryHangingCall().wait()
            } catch {
                lock.withLock { cancelled += 1 }
                throw error
            }
            // `wait()` only ever ends by throwing.
            throw URLError(.unknown)
        }
    }
}

/// One request that never answers until its task is cancelled.
///
/// The continuation and the cancellation handler can run in either order:
/// cancellation may arrive before the continuation is stored. The lock and
/// the `cancelled` flag make both orders resume the continuation exactly
/// once. (The same shape as `AutoTagRunnerTests`' private helper, copied
/// under a module-unique name because that one is file-private.)
private final class AutoTagDeliveryHangingCall: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var cancelled = false

    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let alreadyCancelled: Bool = self.lock.withLock {
                    if self.cancelled { return true }
                    self.continuation = continuation
                    return false
                }
                if alreadyCancelled {
                    continuation.resume(throwing: URLError(.cancelled))
                }
            }
        } onCancel: {
            let pending: CheckedContinuation<Void, any Error>? = self.lock.withLock {
                self.cancelled = true
                let pending = self.continuation
                self.continuation = nil
                return pending
            }
            pending?.resume(throwing: URLError(.cancelled))
        }
    }
}

// MARK: - AutoTagFakeToolchain

/// A private folder with a fake `ffmpeg`, a fake `ffprobe`, an input file and
/// room for the output and the engine's temp files. One per test, so tests
/// can run in parallel without sharing anything.
private struct AutoTagFakeToolchain: Sendable {
    let folder: URL
    let ffmpegPath: String
    let ffprobePath: String
    /// Written by the fake `ffmpeg`: its last launch's arguments, each
    /// followed by a NUL byte. Written to a side file and renamed into
    /// place, so it is never seen half-written.
    let argumentsFile: URL
    /// One line appended per real (non `-version`) `ffmpeg` launch.
    let launchLog: URL
    let probeJSONFile: URL
    /// While this file exists, the fake `ffprobe` waits before answering
    /// (the stop-during-probe test).
    let probeHoldFile: URL
    /// Created by the fake `ffprobe` when it starts waiting on the hold.
    let probeStartedFile: URL
    let inputURL: URL
    let outputURL: URL
    let tempDirectory: URL

    init(inputName: String = "Inception (2010).mkv") throws {
        // No spaces or quotes in this path: it is pasted, single-quoted,
        // into the shell scripts below.
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("autotag-delivery-\(UUID().uuidString)")
        tempDirectory = folder.appendingPathComponent("engine-temp")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        ffmpegPath = folder.appendingPathComponent("ffmpeg").path
        ffprobePath = folder.appendingPathComponent("ffprobe").path
        argumentsFile = folder.appendingPathComponent("ffmpeg-arguments.bin")
        launchLog = folder.appendingPathComponent("ffmpeg-launches.log")
        probeJSONFile = folder.appendingPathComponent("probe.json")
        probeHoldFile = folder.appendingPathComponent("probe-hold")
        probeStartedFile = folder.appendingPathComponent("probe-started")
        inputURL = folder.appendingPathComponent(inputName)
        outputURL = folder.appendingPathComponent(
            (inputName as NSString).deletingPathExtension + ".mp4"
        )

        // The engine only checks the input exists; the fake ffprobe answers
        // for it, so it can be empty.
        try Data().write(to: inputURL)

        let ffmpeg = """
        #!/bin/sh
        # Fake ffmpeg for AutoTagEncodeDeliveryTests. Never encodes anything.
        if [ "$1" = "-version" ]; then
          echo "ffmpeg version 0.0-autotag-delivery-fake Copyright (c) test fixture"
          exit 0
        fi
        echo launched >> '\(launchLog.path)'
        : > '\(argumentsFile.path).partial'
        for arg in "$@"; do
          printf '%s\\000' "$arg" >> '\(argumentsFile.path).partial'
        done
        mv '\(argumentsFile.path).partial' '\(argumentsFile.path)'
        exit 0
        """
        let ffprobe = """
        #!/bin/sh
        # Fake ffprobe for AutoTagEncodeDeliveryTests.
        if [ "$1" = "-version" ]; then
          echo "ffprobe version 0.0-autotag-delivery-fake Copyright (c) test fixture"
          exit 0
        fi
        if [ -f '\(probeHoldFile.path)' ]; then
          echo started > '\(probeStartedFile.path)'
          while [ -f '\(probeHoldFile.path)' ]; do sleep 0.05; done
        fi
        cat '\(probeJSONFile.path)'
        """
        for (path, script) in [(ffmpegPath, ffmpeg), (ffprobePath, ffprobe)] {
            try script.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }

        try writeProbe()
    }

    /// Makes the fake `ffprobe` describe a Matroska file with one h264
    /// video stream and one AAC stream, `minutes` long, carrying `tags` as
    /// its format-level tags.
    ///
    /// The default tags are a matching title (see the header's FIXTURE
    /// TRAP) and the file's own genre, "Mine" — so by default a confident
    /// match adds exactly `inceptionAdditions` (date, description,
    /// tmdb_id), and every test that tags also checks TMDB's genre did NOT
    /// replace the file's.
    func writeProbe(
        minutes: Double = 148,
        tags: [String: String] = ["title": "Inception", "genre": "Mine"]
    ) throws {
        var format: [String: Any] = [
            "format_name": "matroska,webm",
            "duration": String(format: "%.6f", minutes * 60),
        ]
        if !tags.isEmpty {
            format["tags"] = tags
        }
        let root: [String: Any] = [
            "streams": [
                [
                    "index": 0, "codec_name": "h264", "codec_type": "video",
                    "width": 1920, "height": 1080,
                    "r_frame_rate": "24000/1001", "avg_frame_rate": "24000/1001",
                ],
                [
                    "index": 1, "codec_name": "aac", "codec_type": "audio",
                    "sample_rate": "48000", "channels": 2, "channel_layout": "stereo",
                ],
            ],
            "format": format,
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try data.write(to: probeJSONFile)
    }

    /// A new job (a fresh id each call) for this folder's input and output.
    func job(outputMetadata: [String: String] = [:]) -> EncodingJobConfig {
        EncodingJobConfig(
            inputURL: inputURL,
            outputURL: outputURL,
            profile: .webStandard,
            outputMetadata: outputMetadata
        )
    }

    func makeEngine(settings: AutoTagSettingsSource?) throws -> EncodingEngine {
        let engine = EncodingEngine(
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            tempDirectory: tempDirectory,
            autoTagSettings: settings
        )
        try engine.configure()
        return engine
    }

    /// The arguments of the fake `ffmpeg`'s last launch. The record is then
    /// deleted, so the next launch is read fresh and a launch that never
    /// happened cannot be mistaken for one that did.
    func takeRecordedArguments() throws -> [String] {
        let data = try Data(contentsOf: argumentsFile)
        try FileManager.default.removeItem(at: argumentsFile)
        var parts = data.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        // Every argument is FOLLOWED by a NUL, so the split leaves one empty
        // piece after the last. An empty argument mid-list is kept.
        if parts.last == "" {
            parts.removeLast()
        }
        return parts
    }

    /// How many times the fake `ffmpeg` was launched to do work (its
    /// `-version` answers during `configure()` are not counted).
    var ffmpegLaunchCount: Int {
        guard let text = try? String(contentsOf: launchLog, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").count
    }

    func holdProbe() throws {
        try Data().write(to: probeHoldFile)
    }

    func releaseProbe() {
        try? FileManager.default.removeItem(at: probeHoldFile)
    }

    var probeHasStarted: Bool {
        FileManager.default.fileExists(atPath: probeStartedFile.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

// MARK: - AutoTagDeliverySettings

/// A settings source reading a private, per-test `UserDefaults` suite, so no
/// test ever touches the developer's real defaults or another test's.
private final class AutoTagDeliverySettings {
    let suiteName = "AutoTagEncodeDeliveryTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let source: AutoTagSettingsSource

    init(
        client: AutoTagDeliveryStubHTTPClient,
        key: String?,
        enabled: Bool,
        deadline: Duration = .seconds(60)
    ) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw AutoTagDeliveryGaveUp(what: "could not open a UserDefaults suite")
        }
        self.defaults = defaults
        defaults.set(enabled, forKey: AutoTagSettingsStore.Keys.enabled)
        source = AutoTagSettingsSource(
            suiteName: suiteName,
            tmdbKeyProvider: { key },
            httpClient: client,
            musicBrainzThrottle: MusicBrainzRequestThrottle(minimumInterval: .zero),
            deadline: deadline
        )
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: AutoTagSettingsStore.Keys.enabled)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Tests

final class AutoTagEncodeDeliveryTests: XCTestCase {

    // MARK: TMDB response bodies

    private static let inceptionSearch = Data(#"""
    {"page":1,"results":[{"id":27205,"title":"Inception","release_date":"2010-07-15","overview":"An overview."}]}
    """#.utf8)

    private static let inceptionDetails = Data(#"""
    {"id":27205,"title":"Inception","release_date":"2010-07-15","runtime":148,
     "overview":"An overview.","genres":[{"name":"Action"},{"name":"Science Fiction"}]}
    """#.utf8)

    /// Answers `/search/movie` and `/movie/27205` as TMDB would for
    /// Inception; anything else is a 404.
    private static let inceptionRoute: @Sendable (URLRequest) -> AutoTagDeliveryStubHTTPClient.Reply = { request in
        let path = request.url?.path ?? ""
        if path.hasSuffix("/search/movie") {
            return .respond(status: 200, body: inceptionSearch)
        }
        if path.hasSuffix("/movie/\(autoTagDeliveryInceptionID)") {
            return .respond(status: 200, body: inceptionDetails)
        }
        return .respond(status: 404, body: Data())
    }

    /// What a confident Inception match adds to a file that already has
    /// `title` and `genre` (the default fake probe): the rest of what
    /// `TMDBTagMapping.applying` writes.
    private static let inceptionAdditions: Set<String> = [
        "date=2010",
        "description=An overview.",
        "tmdb_id=\(autoTagDeliveryInceptionID)",
    ]

    // MARK: Helpers

    /// The values that follow each file-level `-metadata` flag. Per-stream
    /// `-metadata:s:…` flags are a different argument and are not included.
    private static func fileLevelMetadata(in arguments: [String]) -> [String] {
        var values: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            if arguments[index] == "-metadata", index + 1 < arguments.endIndex {
                values.append(arguments[index + 1])
                index += 2
            } else {
                index += 1
            }
        }
        return values
    }

    /// `arguments` with every file-level `-metadata key=value` pair taken
    /// out, everything else left in order — so an argument list that gained
    /// tags can be compared with the baseline for "nothing ELSE changed".
    private static func removingFileLevelMetadata(from arguments: [String]) -> [String] {
        var kept: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            if arguments[index] == "-metadata", index + 1 < arguments.endIndex {
                index += 2
            } else {
                kept.append(arguments[index])
                index += 1
            }
        }
        return kept
    }

    /// Whether `flag` is immediately followed by `value` somewhere.
    private static func contains(_ arguments: [String], flag: String, value: String) -> Bool {
        zip(arguments, arguments.dropFirst()).contains { $0 == flag && $1 == value }
    }

    /// Every event `stream` delivers until it finishes, or `nil` if it has
    /// not finished within five seconds — so a missing event, or an engine
    /// that was never released (its `deinit` is what finishes the stream),
    /// fails the test instead of hanging it.
    private static func drain(_ stream: AsyncStream<AutoTagJobEvent>) async -> [AutoTagJobEvent]? {
        await withTaskGroup(of: [AutoTagJobEvent]?.self) { group in
            group.addTask {
                var collected: [AutoTagJobEvent] = []
                for await event in stream {
                    collected.append(event)
                }
                return collected
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Builds a configured engine, runs `body` with it, RELEASES it, and
    /// returns `body`'s result with every auto-tag event the engine
    /// published. Releasing the engine is what finishes its event stream.
    private static func withEngine<T>(
        _ toolchain: AutoTagFakeToolchain,
        settings: AutoTagSettingsSource?,
        _ body: (EncodingEngine) async throws -> T
    ) async throws -> (result: T, events: [AutoTagJobEvent]) {
        let stream: AsyncStream<AutoTagJobEvent>
        let result: T
        do {
            let engine = try toolchain.makeEngine(settings: settings)
            stream = engine.autoTagEvents
            result = try await body(engine)
        }
        guard let events = await drain(stream) else {
            XCTFail("the auto-tag event stream did not finish within 5 s of the engine being released")
            throw AutoTagDeliveryGaveUp(what: "event stream")
        }
        return (result, events)
    }

    /// Runs `job` on `engine` and returns the arguments FFmpeg was launched with.
    private static func encodeAndRecord(
        _ engine: EncodingEngine,
        _ job: EncodingJobConfig,
        _ toolchain: AutoTagFakeToolchain
    ) async throws -> [String] {
        try await engine.encode(job: job)
        return try toolchain.takeRecordedArguments()
    }

    /// The arguments `job` gets on an engine with NO auto-tag settings
    /// source — what every encode did before #508.
    private static func baselineArguments(
        _ toolchain: AutoTagFakeToolchain,
        _ job: EncodingJobConfig
    ) async throws -> [String] {
        let (arguments, events) = try await withEngine(toolchain, settings: nil) { engine in
            try await encodeAndRecord(engine, job, toolchain)
        }
        XCTAssertTrue(events.isEmpty, "an engine with no settings source publishes nothing")
        return arguments
    }

    /// Waits for `condition`, failing (not hanging) after five seconds.
    private static func waitUntil(
        _ what: String,
        _ condition: () -> Bool
    ) async throws {
        let started = ContinuousClock.now
        while !condition() {
            if started.duration(to: .now) > .seconds(5) {
                XCTFail("timed out waiting for \(what)")
                throw AutoTagDeliveryGaveUp(what: what)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func describe(_ events: [AutoTagJobEvent]) -> String {
        events.map { String(reflecting: $0) }.joined(separator: "\n")
    }

    /// Checks `events` is exactly: looking up on `provider`, then a lookup
    /// with `outcome` — both for `job`.
    private static func assertLookedUp(
        _ events: [AutoTagJobEvent],
        on provider: MetadataSource,
        outcome: AutoTagOutcome,
        for job: EncodingJobConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard events.count == 2,
              case .lookingUp(let askedProvider) = events[0].kind,
              case .lookup(let report) = events[1].kind else {
            return XCTFail("expected [.lookingUp, .lookup], got:\n\(describe(events))", file: file, line: line)
        }
        XCTAssertEqual(askedProvider, provider, file: file, line: line)
        XCTAssertEqual(report.outcome, outcome, file: file, line: line)
        for event in events {
            XCTAssertEqual(event.jobID, job.id, file: file, line: line)
            XCTAssertEqual(event.fileName, job.inputURL.lastPathComponent, file: file, line: line)
        }
    }

    // MARK: - On, with a key

    func test_onWithAKey_ffmpegReceivesOnlyTheMissingTags_andNothingElseChanges() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        // Spelled out rather than left to the default: the file's own title
        // matches (see the header's FIXTURE TRAP), and its own genre is one
        // TMDB would also write.
        try toolchain.writeProbe(minutes: 148, tags: ["title": "Inception", "genre": "Mine"])
        let client = AutoTagDeliveryStubHTTPClient(route: Self.inceptionRoute)
        let settings = try AutoTagDeliverySettings(client: client, key: autoTagDeliveryTestKey, enabled: true)
        defer { settings.remove() }
        let job = toolchain.job()

        let baseline = try await Self.baselineArguments(toolchain, job)
        let (tagged, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            try await Self.encodeAndRecord(engine, job, toolchain)
        }

        // Sanity: this really is the argument list of an encode of this job.
        XCTAssertTrue(Self.contains(tagged, flag: "-i", value: toolchain.inputURL.path))
        XCTAssertTrue(tagged.contains(toolchain.outputURL.path))
        XCTAssertTrue(Self.fileLevelMetadata(in: baseline).isEmpty, "precondition: the job sets no tags of its own")

        XCTAssertEqual(Set(Self.fileLevelMetadata(in: tagged)), Self.inceptionAdditions)
        XCTAssertEqual(Self.fileLevelMetadata(in: tagged).count, Self.inceptionAdditions.count, "each tag once")
        XCTAssertTrue(
            Self.contains(tagged, flag: "-map_metadata", value: "0"),
            "the file's own tags still travel by -map_metadata 0"
        )
        XCTAssertFalse(
            tagged.contains { $0.hasPrefix("genre=") },
            "the file's own genre (\"Mine\") must not be overridden by TMDB's"
        )
        XCTAssertFalse(tagged.contains { $0.hasPrefix("title=") }, "the file's own title is kept, not rewritten")
        XCTAssertEqual(
            Self.removingFileLevelMetadata(from: tagged), baseline,
            "the ONLY difference from an encode without auto-tagging is the added tags"
        )

        XCTAssertEqual(client.requestCount, 2, "one search, one details request for the running time")
        XCTAssertEqual(toolchain.ffmpegLaunchCount, 2, "one launch for the baseline, one for the tagged run")
        Self.assertLookedUp(events, on: .tmdb, outcome: .applied, for: job)
    }

    // MARK: - Off

    func test_off_isIdenticalToNoSettingsSource_andSendsNothing() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        let client = AutoTagDeliveryStubHTTPClient(route: Self.inceptionRoute)
        let settings = try AutoTagDeliverySettings(client: client, key: autoTagDeliveryTestKey, enabled: false)
        defer { settings.remove() }
        let job = toolchain.job()

        let baseline = try await Self.baselineArguments(toolchain, job)
        let (arguments, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            try await Self.encodeAndRecord(engine, job, toolchain)
        }

        XCTAssertEqual(arguments, baseline)
        XCTAssertEqual(client.requestCount, 0, "switched off sends nothing")
        XCTAssertTrue(events.isEmpty, "switched off publishes nothing:\n\(Self.describe(events))")
    }

    func test_theSettingIsReadPerJob_offThenOnOnTheSameEngineTagsTheSecondJob() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        let client = AutoTagDeliveryStubHTTPClient(route: Self.inceptionRoute)
        let settings = try AutoTagDeliverySettings(client: client, key: autoTagDeliveryTestKey, enabled: false)
        defer { settings.remove() }
        let firstJob = toolchain.job()
        let secondJob = toolchain.job()

        let baseline = try await Self.baselineArguments(toolchain, firstJob)
        let (arguments, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            let first = try await Self.encodeAndRecord(engine, firstJob, toolchain)
            let requestsWhileOff = client.requestCount
            settings.setEnabled(true)
            let second = try await Self.encodeAndRecord(engine, secondJob, toolchain)
            return (first: first, second: second, requestsWhileOff: requestsWhileOff)
        }

        XCTAssertEqual(arguments.first, baseline, "the first job ran while the setting was off")
        XCTAssertEqual(arguments.requestsWhileOff, 0)
        XCTAssertEqual(
            Set(Self.fileLevelMetadata(in: arguments.second)), Self.inceptionAdditions,
            "the SAME engine tagged the second job once the setting was switched on"
        )
        // Also proves the first job published nothing: the buffer keeps
        // order, so an event from it would come first.
        Self.assertLookedUp(events, on: .tmdb, outcome: .applied, for: secondJob)
    }

    // MARK: - Skips and failures never fail the encode

    func test_noKey_sendsNothing_andEncodesWithTheBaselineArguments() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        let client = AutoTagDeliveryStubHTTPClient(route: Self.inceptionRoute)
        let settings = try AutoTagDeliverySettings(client: client, key: nil, enabled: true)
        defer { settings.remove() }
        let job = toolchain.job()

        let baseline = try await Self.baselineArguments(toolchain, job)
        let (arguments, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            try await Self.encodeAndRecord(engine, job, toolchain)
        }

        XCTAssertEqual(arguments, baseline)
        XCTAssertEqual(client.requestCount, 0, "no key means no request is even attempted")
        // No `.lookingUp`: nothing was about to be sent.
        guard events.count == 1, case .lookup(let report) = events[0].kind else {
            return XCTFail("expected one .lookup event, got:\n\(Self.describe(events))")
        }
        XCTAssertEqual(report.outcome, .skipped(reason: AutoTagRunner.Reasons.noTMDBKey))
        XCTAssertEqual(events[0].jobID, job.id)
    }

    func test_aTransportError_stillEncodes_withTheBaselineArguments() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        let client = AutoTagDeliveryStubHTTPClient(route: { _ in .transportError(URLError(.notConnectedToInternet)) })
        let settings = try AutoTagDeliverySettings(client: client, key: autoTagDeliveryTestKey, enabled: true)
        defer { settings.remove() }
        let job = toolchain.job()

        let baseline = try await Self.baselineArguments(toolchain, job)
        let (arguments, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            try await Self.encodeAndRecord(engine, job, toolchain)
        }

        XCTAssertEqual(arguments, baseline, "a failed lookup changes nothing about the encode")
        XCTAssertEqual(client.requestCount, 1)
        guard events.count == 2, case .lookup(let report) = events[1].kind,
              case .failed = report.outcome else {
            return XCTFail("expected [.lookingUp, .lookup(.failed)], got:\n\(Self.describe(events))")
        }
    }

    func test_theWrongRunningTime_isBelowThreshold_andEncodesWithTheBaselineArguments() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        // A 90-minute file against the 148-minute film: title and year match
        // (0.35 + 0.15) but the running time scores 0, so 0.5 < 0.7.
        try toolchain.writeProbe(minutes: 90, tags: ["title": "Inception"])
        let client = AutoTagDeliveryStubHTTPClient(route: Self.inceptionRoute)
        let settings = try AutoTagDeliverySettings(client: client, key: autoTagDeliveryTestKey, enabled: true)
        defer { settings.remove() }
        let job = toolchain.job()

        let baseline = try await Self.baselineArguments(toolchain, job)
        let (arguments, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            try await Self.encodeAndRecord(engine, job, toolchain)
        }

        XCTAssertEqual(arguments, baseline)
        XCTAssertEqual(client.requestCount, 2, "it did look — and then declined")
        guard events.count == 2, case .lookup(let report) = events[1].kind,
              case .belowThreshold = report.outcome else {
            return XCTFail("expected [.lookingUp, .lookup(.belowThreshold)], got:\n\(Self.describe(events))")
        }
    }

    // MARK: - Precedence

    func test_theJobsOwnTagWins_overTheLookup() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        // No genre in the FILE this time, so the only thing that can keep
        // TMDB's genre out is the job's own.
        try toolchain.writeProbe(minutes: 148, tags: ["title": "Inception"])
        let client = AutoTagDeliveryStubHTTPClient(route: Self.inceptionRoute)
        let settings = try AutoTagDeliverySettings(client: client, key: autoTagDeliveryTestKey, enabled: true)
        defer { settings.remove() }
        let job = toolchain.job(outputMetadata: ["genre": "The job's own genre"])

        let baseline = try await Self.baselineArguments(toolchain, job)
        let (tagged, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            try await Self.encodeAndRecord(engine, job, toolchain)
        }

        XCTAssertEqual(Self.fileLevelMetadata(in: baseline), ["genre=The job's own genre"])
        XCTAssertEqual(
            Set(Self.fileLevelMetadata(in: tagged)),
            Self.inceptionAdditions.union(["genre=The job's own genre"])
        )
        XCTAssertEqual(
            tagged.filter { $0.hasPrefix("genre=") }, ["genre=The job's own genre"],
            "exactly one genre, and it is the job's — never TMDB's \"Action; Science Fiction\""
        )
        Self.assertLookedUp(events, on: .tmdb, outcome: .applied, for: job)
    }

    // MARK: - Stop

    func test_stopEncoding_duringTheLookup_throwsCancellationQuickly_andFFmpegNeverStarts() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        let client = AutoTagDeliveryStubHTTPClient(route: { _ in .hang })
        // A two-minute deadline: only the stop can realistically end this.
        let settings = try AutoTagDeliverySettings(
            client: client, key: autoTagDeliveryTestKey, enabled: true, deadline: .seconds(120)
        )
        defer { settings.remove() }
        let job = toolchain.job()

        let (rerun, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            let encoding = Task { try await engine.encode(job: job) }
            try await Self.waitUntil("the lookup's request to arrive") { client.requestCount > 0 }

            let stopPressed = ContinuousClock.now
            engine.stopEncoding()
            do {
                try await encoding.value
                XCTFail("a stop during the lookup must throw, not encode")
            } catch is CancellationError {
                // Expected.
            } catch {
                XCTFail("expected CancellationError, got \(error)")
            }
            XCTAssertLessThan(stopPressed.duration(to: .now), .seconds(2), "stop is noticed within a poll")
            XCTAssertEqual(client.cancelledCount, 1, "the in-flight request was cancelled, not left running")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: toolchain.argumentsFile.path),
                "FFmpeg was never launched"
            )
            XCTAssertEqual(toolchain.ffmpegLaunchCount, 0)

            // The stop belonged to THAT run. Running the same job again on
            // the same engine must not be cancelled by a leftover flag.
            client.replaceRoute(Self.inceptionRoute)
            return try await Self.encodeAndRecord(engine, job, toolchain)
        }

        XCTAssertEqual(Set(Self.fileLevelMetadata(in: rerun)), Self.inceptionAdditions)
        // The stopped run published `.lookingUp` and NO `.lookup`; the re-run
        // published both.
        guard events.count == 3,
              case .lookingUp = events[0].kind,
              case .lookingUp = events[1].kind,
              case .lookup(let report) = events[2].kind else {
            return XCTFail("expected [.lookingUp, .lookingUp, .lookup], got:\n\(Self.describe(events))")
        }
        XCTAssertEqual(report.outcome, .applied)
    }

    func test_stopEncodingForThisJob_duringTheLookup_throwsCancellation() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        let client = AutoTagDeliveryStubHTTPClient(route: { _ in .hang })
        let settings = try AutoTagDeliverySettings(
            client: client, key: autoTagDeliveryTestKey, enabled: true, deadline: .seconds(120)
        )
        defer { settings.remove() }
        let job = toolchain.job()

        _ = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            let encoding = Task { try await engine.encode(job: job) }
            try await Self.waitUntil("the lookup's request to arrive") { client.requestCount > 0 }

            let stopPressed = ContinuousClock.now
            engine.stopEncoding(jobID: job.id)
            do {
                try await encoding.value
                XCTFail("a stop for this job must throw, not encode")
            } catch is CancellationError {
                // Expected.
            } catch {
                XCTFail("expected CancellationError, got \(error)")
            }
            XCTAssertLessThan(stopPressed.duration(to: .now), .seconds(2))
        }
        XCTAssertEqual(toolchain.ffmpegLaunchCount, 0, "FFmpeg was never launched")
    }

    func test_stopEncodingForAnotherJob_leavesThisJobAlone() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        let client = AutoTagDeliveryStubHTTPClient(route: { _ in .hang })
        // Short enough that the lookup gives up on its own and the encode
        // carries on, long enough for several stop polls to see (and
        // ignore) the other job's stop.
        let settings = try AutoTagDeliverySettings(
            client: client, key: autoTagDeliveryTestKey, enabled: true, deadline: .milliseconds(1500)
        )
        defer { settings.remove() }
        let job = toolchain.job()

        let baseline = try await Self.baselineArguments(toolchain, job)
        let (arguments, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            let encoding = Task { try await Self.encodeAndRecord(engine, job, toolchain) }
            try await Self.waitUntil("the lookup's request to arrive") { client.requestCount > 0 }
            engine.stopEncoding(jobID: UUID())
            return try await encoding.value
        }

        XCTAssertEqual(arguments, baseline, "another job's stop must not touch this one")
        guard events.count == 2, case .lookup(let report) = events[1].kind,
              case .failed = report.outcome else {
            return XCTFail("expected the lookup to run out of time, got:\n\(Self.describe(events))")
        }
    }

    func test_aStopDuringTheProbe_isHonoured_evenWithNoSettingsSource() async throws {
        // Before #508 commit 6 a Stop pressed while the source was being
        // probed reached nothing (no FFmpeg process was registered yet) and
        // the encode ran to the end regardless. The stop registry fixes that
        // for every engine, not only one that auto-tags.
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        let job = toolchain.job()
        try toolchain.holdProbe()

        _ = try await Self.withEngine(toolchain, settings: nil) { engine in
            let encoding = Task { try await engine.encode(job: job) }
            try await Self.waitUntil("the probe to start") { toolchain.probeHasStarted }
            engine.stopEncoding()
            toolchain.releaseProbe()
            do {
                try await encoding.value
                XCTFail("a stop during the probe must throw, not encode")
            } catch is CancellationError {
                // Expected.
            } catch {
                XCTFail("expected CancellationError, got \(error)")
            }
        }
        XCTAssertEqual(toolchain.ffmpegLaunchCount, 0, "FFmpeg was never launched")
    }

    // MARK: - The key

    func test_theKeyAppearsInNoArgumentAndNoEvent() async throws {
        let toolchain = try AutoTagFakeToolchain()
        defer { toolchain.remove() }
        // First a server that echoes the key back in an error body (the way
        // TMDB's own errors quote the request), then a working one.
        let echoingKey: @Sendable (URLRequest) -> AutoTagDeliveryStubHTTPClient.Reply = { _ in
            .respond(status: 500, body: Data("upstream failed for api_key=\(autoTagDeliveryTestKey)".utf8))
        }
        let client = AutoTagDeliveryStubHTTPClient(route: echoingKey)
        let settings = try AutoTagDeliverySettings(client: client, key: autoTagDeliveryTestKey, enabled: true)
        defer { settings.remove() }

        let (arguments, events) = try await Self.withEngine(toolchain, settings: settings.source) { engine in
            let failed = try await Self.encodeAndRecord(engine, toolchain.job(), toolchain)
            client.replaceRoute(Self.inceptionRoute)
            let tagged = try await Self.encodeAndRecord(engine, toolchain.job(), toolchain)
            return failed + tagged
        }

        // Not vacuous: the key really was sent (a v3 key travels in the URL).
        XCTAssertTrue(
            client.requests.contains { $0.url?.absoluteString.contains(autoTagDeliveryTestKey) == true },
            "precondition: the key was in play"
        )
        XCTAssertEqual(events.count, 4, "two jobs, each [.lookingUp, .lookup]:\n\(Self.describe(events))")
        XCTAssertFalse(arguments.contains { $0.contains(autoTagDeliveryTestKey) }, "the key reached FFmpeg")
        for event in events {
            XCTAssertFalse(
                String(reflecting: event).contains(autoTagDeliveryTestKey),
                "the key is in an event: \(String(reflecting: event))"
            )
        }
    }
}
