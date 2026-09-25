// ============================================================================
// MeedyaConverter — AutoTagRunnerTests (Issue #508, commit 5/10: music)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pins what `AutoTagRunner` delivers for FILMS and MUSIC: which files are
// looked up at all, what is sent where, how a match is scored and judged,
// which tags come back, and that a lookup can never hold up — or wrongly
// cancel — an encode. Every request goes to a private stub HTTP client;
// nothing touches the network. Public API only.
//
// Things these tests exist to catch, because each would fail silently in
// production:
//   * THE 0.5 TRAP. Raw TMDB results all carry confidence 0.5, below the 0.7
//     threshold. Without real scoring the feature would never tag anything.
//   * COVER ART. An MP3 with an embedded picture has `hasVideo == true`; it
//     must never be sent to TMDB as a film, and once it has been correctly
//     routed to music it must still make a real MusicBrainz request, not
//     silently do nothing.
//   * THE ARTIST TRAP. Searching MusicBrainz by title alone is far too
//     ambiguous ("Yesterday" has thousands of recordings) — an artist is
//     required before any request is sent, from a tag or from an
//     "Artist - Title" / "Artist – Title" (en dash) file name.
//   * THE LENGTH TRAP. A recording's raw MusicBrainz score says nothing
//     about whether it's actually the same length as the file; confidence
//     must be forced to 0 when the length is missing or too far off, exactly
//     as running time does for films.
//   * THE KEY. A v3 TMDB key travels in the URL. It must appear in no
//     failure reason, whatever the server sends back. (MusicBrainz never
//     uses a key at all, so there is nothing to leak on that path.)
//   * ZERO REQUESTS where nothing should be sent: off, no key, TV, a music
//     file with no artist, no running time.
//
// HOW THE TIMING TESTS AVOID FLAKING UNDER `swift test --parallel`. None of
// them races two wall-clock sleeps against each other. The stub's `.hang`
// reply suspends on a continuation that is resumed ONLY by cancellation (the
// way URLSession behaves), so the lookup can never finish on its own:
//   * deadline test — a 50 ms deadline against a request that never answers
//     and a stop that is never requested. Only the deadline CAN win.
//   * stop test — a 120 s deadline, and `shouldStop` becomes true the moment
//     the stub has recorded the request. Only the stop can realistically win.
//   * cancel test — the stub cancels the calling task from inside the
//     request itself, so there is no "wait until it has started" guesswork.
// The wall-clock bounds asserted afterwards are generous (10 s) and only
// prove the in-flight request was really abandoned, not waited out.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// MARK: - Fixtures shared by the helpers below

/// A v3 TMDB key: 32 hex characters, sent in the URL — the form that can leak.
/// File-level (not a test-case property) so `@Sendable` closures can use it
/// without capturing the test case.
private let autoTagRunnerTestKey = "0123456789abcdef0123456789abcdef"

private let inceptionID = 27205

// MARK: - AutoTagRunnerStubHTTPClient

/// Records every request and answers each one as `route` says. Uniquely named
/// so it never collides with the other stub clients in this test module.
private final class AutoTagRunnerStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {

    enum Reply: Sendable {
        /// Answer with this status and body.
        case respond(status: Int, body: Data)
        /// Fail the way URLSession does when there is no network.
        case transportError(URLError)
        /// Throw `CancellationError` although nobody cancelled anything.
        case spuriousCancellation
        /// Never answer: suspend until the calling task is cancelled, then
        /// throw `URLError(.cancelled)` exactly as URLSession does.
        case hang
    }

    private let lock = NSLock()
    private let route: @Sendable (URLRequest) -> Reply
    private let onRequest: @Sendable () -> Void
    private var recorded: [URLRequest] = []
    private var cancelled = 0

    init(
        onRequest: @escaping @Sendable () -> Void = {},
        route: @escaping @Sendable (URLRequest) -> Reply
    ) {
        self.onRequest = onRequest
        self.route = route
    }

    var requestCount: Int { lock.withLock { recorded.count } }
    var requests: [URLRequest] { lock.withLock { recorded } }
    /// How many `.hang` requests were ended by cancellation.
    var cancelledCount: Int { lock.withLock { cancelled } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        onRequest()

        switch route(request) {
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
        case .spuriousCancellation:
            throw CancellationError()
        case .hang:
            do {
                try await AutoTagRunnerHangingCall().wait()
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
/// the `cancelled` flag make both orders resume the continuation exactly once.
private final class AutoTagRunnerHangingCall: @unchecked Sendable {
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

/// Cancels a task from inside the stub, the moment a request arrives. The
/// task may not have been handed over yet when that happens (it starts
/// running as soon as it is created), so a cancel that arrives first is
/// remembered and applied on hand-over.
private final class AutoTagRunnerTaskCanceller: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<AutoTagLookupReport, any Error>?
    private var fired = false

    func hold(_ task: Task<AutoTagLookupReport, any Error>) {
        let cancelNow: Bool = lock.withLock {
            self.task = task
            return fired
        }
        if cancelNow { task.cancel() }
    }

    func fire() {
        let task: Task<AutoTagLookupReport, any Error>? = lock.withLock {
            fired = true
            return self.task
        }
        task?.cancel()
    }
}

// MARK: - Tests

final class AutoTagRunnerTests: XCTestCase {

    // MARK: TMDB response bodies

    private static func searchBody(_ rows: [(id: Int, title: String, date: String?)]) -> Data {
        let items = rows.map { row -> String in
            let date = row.date.map { "\"\($0)\"" } ?? "null"
            return #"{"id":\#(row.id),"title":"\#(row.title)","release_date":\#(date),"overview":"An overview."}"#
        }
        return Data(#"{"page":1,"results":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    private static func detailsBody(id: Int, title: String, date: String, runtime: Int, genres: [String]) -> Data {
        let genreList = genres.map { #"{"name":"\#($0)"}"# }.joined(separator: ",")
        return Data(#"""
        {"id":\#(id),"title":"\#(title)","release_date":"\#(date)","runtime":\#(runtime),
         "overview":"An overview.","genres":[\#(genreList)]}
        """#.utf8)
    }

    private static let inceptionSearch = searchBody([(inceptionID, "Inception", "2010-07-15")])
    private static let inceptionDetails = detailsBody(
        id: inceptionID, title: "Inception", date: "2010-07-15", runtime: 148,
        genres: ["Action", "Science Fiction"]
    )
    private static let emptySearch = Data(#"{"page":1,"results":[]}"#.utf8)

    /// Answers `/search/movie` with `search` and `/movie/{id}` with the
    /// matching entry in `details`.
    private static func tmdbRoute(
        search: Data,
        details: [Int: Data]
    ) -> @Sendable (URLRequest) -> AutoTagRunnerStubHTTPClient.Reply {
        return { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/search/movie") {
                return .respond(status: 200, body: search)
            }
            if let idText = path.split(separator: "/").last, let id = Int(idText), let body = details[id] {
                return .respond(status: 200, body: body)
            }
            return .respond(status: 404, body: Data())
        }
    }

    private static let inceptionRoute = tmdbRoute(search: inceptionSearch, details: [inceptionID: inceptionDetails])

    // MARK: MusicBrainz response bodies

    /// One `/recording` search result row. `artistId` is optional because
    /// most tests only care about the title/artist/length; the ambiguity and
    /// "adds only what's missing" tests set it to also exercise
    /// `musicbrainz_artistid`.
    private struct StubRecording {
        let id: String
        let score: Int
        let title: String
        let artist: String
        var artistId: String? = nil
        var lengthMs: Int? = nil
    }

    private static func artistCreditJSON(name: String, artistId: String?) -> String {
        guard let artistId else {
            return #"{"name":"\#(name)","joinphrase":""}"#
        }
        return #"{"name":"\#(name)","joinphrase":"","artist":{"id":"\#(artistId)","name":"\#(name)"}}"#
    }

    private static func recordingSearchBody(_ rows: [StubRecording]) -> Data {
        let items = rows.map { row -> String in
            let length = row.lengthMs.map(String.init) ?? "null"
            return #"{"id":"\#(row.id)","score":\#(row.score),"title":"\#(row.title)","length":\#(length),"artist-credit":[\#(artistCreditJSON(name: row.artist, artistId: row.artistId))]}"#
        }
        return Data(#"{"recordings":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    private static let emptyMusicSearch = Data(#"{"recordings":[]}"#.utf8)

    private static let bohemianRhapsodyID = "b1a9c0e9-d987-4042-ae91-78d6a3267d69"
    private static let queenID = "0383dadf-2a4e-4d10-a46a-e9e041da8eb3"

    /// A single, confident, length-matching "Bohemian Rhapsody" / "Queen"
    /// result. `lengthMs` defaults to 354 000 ms (354 s) — the same duration
    /// `song()`'s own default uses, so a test that doesn't care about the
    /// length tolerance can just use both defaults together.
    private static func bohemianRhapsodySearch(lengthMs: Int? = 354_000, score: Int = 100) -> Data {
        recordingSearchBody([
            StubRecording(
                id: bohemianRhapsodyID, score: score, title: "Bohemian Rhapsody", artist: "Queen",
                artistId: queenID, lengthMs: lengthMs
            ),
        ])
    }

    /// Answers MusicBrainz's `/recording` search with `search`. Every other
    /// path (in particular TMDB's `/search/movie`) gets a 404, so a test
    /// combining this with `tmdbRoute` in one dispatcher can tell the two
    /// providers apart by which one actually got a request.
    private static func musicBrainzRoute(search: Data) -> @Sendable (URLRequest) -> AutoTagRunnerStubHTTPClient.Reply {
        return { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/recording") {
                return .respond(status: 200, body: search)
            }
            return .respond(status: 404, body: Data())
        }
    }

    private static let bohemianRhapsodyRoute = musicBrainzRoute(search: bohemianRhapsodySearch())

    // MARK: Media files

    private static func stream(_ type: StreamType, codec: String, fps: Double? = nil) -> MediaStream {
        MediaStream(streamIndex: 0, streamType: type, codecName: codec, frameRate: fps)
    }

    /// A film: moving h264 video plus audio in an MKV.
    private static func film(
        named name: String = "Inception (2010).mkv",
        minutes: Double? = 148,
        tags: [String: String] = [:]
    ) -> MediaFile {
        MediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/\(name)"),
            containerFormat: .mkv,
            streams: [stream(.video, codec: "h264", fps: 23.976), stream(.audio, codec: "aac")],
            duration: minutes.map { $0 * 60 },
            metadata: tags
        )
    }

    /// An MP3 with embedded cover art — named like a film, to make the trap
    /// as tempting as possible. `containerFormat` is nil because
    /// `ContainerFormat` has no mp3 case, which is also what production
    /// holds for such a file. Its name gives no artist, so a lookup on this
    /// one is skipped before any request — `mp3WithCoverArtAndArtist` below
    /// is the sibling fixture that proves a real MusicBrainz request happens
    /// once an artist IS available.
    private static let mp3WithCoverArt = MediaFile(
        fileURL: URL(fileURLWithPath: "/tmp/Inception (2010).mp3"),
        containerFormat: nil,
        streams: [stream(.audio, codec: "mp3"), stream(.video, codec: "mjpeg", fps: 90000)],
        duration: 355
    )

    /// The same cover-art trap as `mp3WithCoverArt`, but named "Artist -
    /// Title" so it actually HAS an artist to search with. Proves cover art
    /// is routed to MUSIC and MusicBrainz end-to-end — a real search
    /// happens — never to TMDB, complementing `mp3WithCoverArt` (which
    /// proves the opposite edge: no artist means no request to either).
    private static let mp3WithCoverArtAndArtist = MediaFile(
        fileURL: URL(fileURLWithPath: "/tmp/Queen - Bohemian Rhapsody.mp3"),
        containerFormat: nil,
        streams: [stream(.audio, codec: "mp3"), stream(.video, codec: "mjpeg", fps: 90000)],
        duration: 354
    )

    /// A song: one plain audio stream, no cover art. Named "Artist - Title"
    /// (an ASCII hyphen) so the shared, existing `FilenameParser`/
    /// `MusicBrainzTagMapping.seedQuery` path already finds the artist —
    /// most tests below don't need the runner's OWN en-dash fallback
    /// (`musicArtistTitleFromFileName`), which has its own dedicated tests.
    private static func song(
        named name: String = "Queen - Bohemian Rhapsody.flac",
        seconds: Double? = 354,
        tags: [String: String] = [:]
    ) -> MediaFile {
        MediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/\(name)"),
            streams: [stream(.audio, codec: "flac")],
            duration: seconds,
            metadata: tags
        )
    }

    // MARK: Requests

    private static let fixedSources: [AutoTagSource] = [.filename, .existingMetadata, .tmdb, .musicBrainz]

    private static func request(
        client: AutoTagRunnerStubHTTPClient,
        key: String? = autoTagRunnerTestKey,
        enabled: Bool = true,
        sources: [AutoTagSource] = fixedSources,
        deadline: Duration = .seconds(60)
    ) -> AutoTagRequest {
        AutoTagRequest(
            config: AutoTagConfig(enabled: enabled, sources: sources),
            tmdbService: key.map { TMDBLookupService(apiKey: $0, httpClient: client) },
            musicBrainzService: MusicBrainzLookupService(
                httpClient: client,
                throttle: MusicBrainzRequestThrottle(minimumInterval: .zero)
            ),
            deadline: deadline
        )
    }

    private static func lookUp(
        _ request: AutoTagRequest,
        _ file: MediaFile,
        jobTags: [String: String] = [:],
        shouldStop: @escaping @Sendable () -> Bool = { false }
    ) async throws -> AutoTagLookupReport {
        try await AutoTagRunner.run(request: request, source: file, jobTags: jobTags, shouldStop: shouldStop)
    }

    private static func pairs(_ tags: [MediaTag]) -> [String: String] {
        Dictionary(tags.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    private static func failureReason(_ report: AutoTagLookupReport) -> String? {
        if case .failed(let reason) = report.outcome { return reason }
        return nil
    }

    // MARK: - Planning: what counts as a film

    func test_plan_aFilmIsSearchedForByItsNameAndYear() {
        XCTAssertEqual(
            AutoTagRunner.plan(for: Self.film()),
            .film(MetadataSearchQuery(mediaType: .movie, title: "Inception", year: 2010))
        )
    }

    func test_plan_anMP3WithCoverArtIsMusicNeverAFilm() {
        let mp3 = Self.mp3WithCoverArt
        XCTAssertTrue(mp3.hasVideo, "precondition: the naive check is fooled by the cover art")
        XCTAssertFalse(mp3.isAudioOnly, "precondition: isAudioOnly says no to it too")

        guard case .music = AutoTagRunner.plan(for: mp3) else {
            return XCTFail("an MP3 with cover art is music, got \(AutoTagRunner.plan(for: mp3))")
        }
    }

    func test_run_anMP3WithCoverArtButNoArtistIsNeverSentToTMDB_andIsSkippedZeroRequests() async throws {
        // `mp3WithCoverArt`'s name ("Inception (2010).mp3") gives no artist,
        // so — now that music is genuinely looked up (#508 commit 5) — this
        // is the "no artist" skip, not a blanket "music isn't built" one.
        // `test_run_anMP3WithCoverArtAndArtist_isLookedUpOnMusicBrainzNotTMDB`
        // below is the sibling that proves a real request happens once an
        // artist IS available.
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)

        let report = try await Self.lookUp(Self.request(client: client), Self.mp3WithCoverArt)

        XCTAssertEqual(client.requestCount, 0, "a song must never be looked up as a film, or without an artist")
        XCTAssertEqual(report.outcome, .skipped(reason: AutoTagRunner.Reasons.noArtistForMusic))
        XCTAssertNil(report.provider)
        XCTAssertTrue(report.tagsToAdd.isEmpty)
    }

    func test_run_music_noArtistAnywhere_isSkipped_zeroRequests() async throws {
        // No hyphen in the name, and no tags at all: nothing gives an
        // artist, so this must be skipped before any request — to EITHER
        // provider — is made.
        let client = AutoTagRunnerStubHTTPClient(route: Self.bohemianRhapsodyRoute)
        let untitledHum = Self.song(named: "Symphony No. 5.flac", seconds: 1800)

        let report = try await Self.lookUp(Self.request(client: client), untitledHum)

        XCTAssertEqual(report.outcome, .skipped(reason: AutoTagRunner.Reasons.noArtistForMusic))
        XCTAssertEqual(
            AutoTagRunner.Reasons.noArtistForMusic,
            "Music needs an artist to look up safely; searching by title alone is too ambiguous to apply unattended."
        )
        XCTAssertNil(report.provider)
        XCTAssertEqual(client.requestCount, 0)
    }

    func test_run_anMP3WithCoverArtAndArtist_isLookedUpOnMusicBrainzNotTMDB() async throws {
        // The positive half of the cover-art trap: once cover art is
        // correctly routed to music AND an artist is available, a real
        // MusicBrainz search must actually happen — never TMDB.
        let client = AutoTagRunnerStubHTTPClient(route: Self.bohemianRhapsodyRoute)

        let report = try await Self.lookUp(Self.request(client: client), Self.mp3WithCoverArtAndArtist)

        XCTAssertEqual(report.outcome, .applied)
        XCTAssertEqual(report.provider, .musicBrainz)
        XCTAssertFalse(
            client.requests.contains { ($0.url?.path ?? "").hasSuffix("/search/movie") },
            "cover art must never reach TMDB"
        )
        XCTAssertTrue(
            client.requests.contains { ($0.url?.path ?? "").hasSuffix("/recording") },
            "a real MusicBrainz search must have happened"
        )
    }

    func test_plan_aTVEpisodeNameIsSkipped_andNothingIsSent() async throws {
        let episode = Self.film(named: "Show.Name.S03E07.720p.mkv", minutes: 44)
        XCTAssertEqual(AutoTagRunner.plan(for: episode), .skip(reason: AutoTagRunner.Reasons.tvEpisode))

        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)
        let report = try await Self.lookUp(Self.request(client: client), episode)

        XCTAssertEqual(report.outcome, .skipped(reason: "TV episodes aren't looked up yet."))
        XCTAssertNil(report.provider)
        XCTAssertEqual(client.requestCount, 0)
    }

    func test_plan_anEmptyProbeIsSkipped() {
        let empty = MediaFile(fileURL: URL(fileURLWithPath: "/tmp/Inception (2010).mkv"))
        XCTAssertEqual(AutoTagRunner.plan(for: empty), .skip(reason: AutoTagRunner.Reasons.emptyProbe))
    }

    func test_plan_aFileWithNoMovingVideoOrAudioIsSkipped() {
        let subtitlesOnly = MediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/Inception (2010).mks"),
            streams: [Self.stream(.subtitle, codec: "subrip")],
            duration: 8880
        )
        let pictureOnly = MediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/Inception (2010).mkv"),
            streams: [Self.stream(.video, codec: "mjpeg")],
            duration: 8880
        )
        XCTAssertEqual(AutoTagRunner.plan(for: subtitlesOnly), .skip(reason: AutoTagRunner.Reasons.nothingToIdentify))
        XCTAssertEqual(AutoTagRunner.plan(for: pictureOnly), .skip(reason: AutoTagRunner.Reasons.nothingToIdentify))
    }

    func test_aFileWithNoRunningTimeIsNeverLookedUp() async throws {
        // The owner's decision (plan, decision 6). Without a running time the
        // best possible score is 0.5, so a request could never be accepted.
        for minutes in [nil, 0] as [Double?] {
            let file = Self.film(minutes: minutes)
            XCTAssertEqual(AutoTagRunner.plan(for: file), .skip(reason: AutoTagRunner.Reasons.noRunningTime))

            let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)
            let report = try await Self.lookUp(Self.request(client: client), file)
            XCTAssertEqual(report.outcome, .skipped(reason: AutoTagRunner.Reasons.noRunningTime))
            XCTAssertNil(report.provider)
            XCTAssertEqual(client.requestCount, 0)
        }
    }

    func test_plan_aTitleTheJobSetsIsWhatIsSearchedFor() {
        // The job's own title is what the output will say, so it beats the
        // source file's tag (spelled differently, to prove the case-blind
        // replacement).
        let file = Self.film(tags: ["TITLE": "Some Rip"])
        XCTAssertEqual(
            AutoTagRunner.plan(for: file, jobTags: ["title": "Inception"]),
            .film(MetadataSearchQuery(mediaType: .movie, title: "Inception", year: 2010))
        )
        XCTAssertEqual(
            AutoTagRunner.plan(for: file, jobTags: ["title": "   "]),
            .film(MetadataSearchQuery(mediaType: .movie, title: "Some Rip", year: 2010)),
            "a blank job title is ignored, not searched for"
        )
    }

    // MARK: - Choosing a provider

    func test_chooseProvider_notConnectedIsADifferentReasonFromNoKey() {
        let notConnected = AutoTagRunner.chooseProvider(
            from: [.filename, .tvdb], runnable: [.tmdb], hasTMDBService: true
        )
        let noKey = AutoTagRunner.chooseProvider(
            from: [.filename, .existingMetadata, .tmdb], runnable: [.tmdb], hasTMDBService: false
        )

        XCTAssertEqual(noKey, .skip(reason: AutoTagRunner.Reasons.noTMDBKey))
        XCTAssertEqual(
            notConnected,
            .skip(reason: "TheTVDB isn't connected yet, so it can't be used even with a key.")
        )
        XCTAssertNotEqual(notConnected, noKey, "telling someone to add a key for TheTVDB would be a pointless errand")
        XCTAssertEqual(
            AutoTagRunner.Reasons.notConnectedYet([.discogs, .audioFingerprint]),
            "Discogs and Audio fingerprinting aren't connected yet, so they can't be used even with a key."
        )
    }

    func test_chooseProvider_passesOverWhatCannotRunAndUsesTMDB() {
        XCTAssertEqual(
            AutoTagRunner.chooseProvider(from: [.filename, .tvdb, .tmdb], runnable: [.tmdb], hasTMDBService: true),
            .lookUp(.tmdb)
        )
        XCTAssertEqual(
            AutoTagRunner.chooseProvider(from: [.filename, .existingMetadata], runnable: [.tmdb], hasTMDBService: true),
            .skip(reason: AutoTagRunner.Reasons.noUsableSource),
            "file name and existing tags only seed a search; they look nothing up"
        )
    }

    func test_run_withTMDBNotAmongTheSources_sendsNothing() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)
        let request = Self.request(client: client, sources: [.filename, .existingMetadata, .musicBrainz])

        let report = try await Self.lookUp(request, Self.film())

        XCTAssertEqual(report.outcome, .skipped(reason: AutoTagRunner.Reasons.noUsableSource))
        XCTAssertEqual(client.requestCount, 0)
    }

    // MARK: - The failure table

    func test_off_sendsNothing() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)

        let report = try await Self.lookUp(Self.request(client: client, enabled: false), Self.film())

        XCTAssertEqual(report.outcome, .skipped(reason: "Automatic tagging is off."))
        XCTAssertNil(report.provider)
        XCTAssertEqual(client.requestCount, 0)
    }

    func test_noKey_isSkippedNotFailed_andSendsNothing() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)

        let report = try await Self.lookUp(Self.request(client: client, key: nil), Self.film())

        XCTAssertEqual(report.outcome, .skipped(reason: AutoTagRunner.Reasons.noTMDBKey))
        XCTAssertEqual(AutoTagRunner.Reasons.noTMDBKey, "No TMDB key is saved (Settings › Metadata).")
        XCTAssertNil(report.provider, "nothing was asked")
        XCTAssertEqual(client.requestCount, 0, "no key must mean zero requests, not a request that fails")
    }

    func test_aBlankKey_isTreatedAsNoKey_andSendsNothing() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)

        let report = try await Self.lookUp(Self.request(client: client, key: "   "), Self.film())

        XCTAssertEqual(report.outcome, .skipped(reason: AutoTagRunner.Reasons.noTMDBKey))
        XCTAssertNil(report.provider, "the service refused before sending, so nothing was asked")
        XCTAssertEqual(client.requestCount, 0)
    }

    func test_unreachable_401_429_and5xx_areFailuresThatNeverCarryTheKey() async throws {
        // The server echoing the key back is exactly how a key leaks.
        let echo = Data(#"{"status_message":"Invalid key: \#(autoTagRunnerTestKey)"}"#.utf8)
        let cases: [(name: String, reply: AutoTagRunnerStubHTTPClient.Reply, expected: String?)] = [
            ("unreachable", .transportError(URLError(.notConnectedToInternet)), nil),
            ("401", .respond(status: 401, body: echo), TMDBLookupError.unauthorized.errorDescription),
            ("429", .respond(status: 429, body: echo), TMDBLookupError.rateLimited.errorDescription),
            ("503", .respond(status: 503, body: echo), nil),
        ]

        for testCase in cases {
            let reply = testCase.reply
            let client = AutoTagRunnerStubHTTPClient(route: { _ in reply })

            let report = try await Self.lookUp(Self.request(client: client), Self.film())

            let reason = try XCTUnwrap(Self.failureReason(report), "\(testCase.name) must be a failure")
            XCTAssertFalse(reason.contains(autoTagRunnerTestKey), "\(testCase.name) leaked the key: \(reason)")
            if let expected = testCase.expected {
                XCTAssertEqual(reason, expected, testCase.name)
            }
            XCTAssertEqual(report.provider, .tmdb)
            XCTAssertTrue(report.tagsToAdd.isEmpty, "\(testCase.name) must add nothing")
            XCTAssertNil(report.identifiedFilm)
        }
    }

    func test_unreachable_saysSoInPlainWords() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: { _ in .transportError(URLError(.notConnectedToInternet)) })
        let report = try await Self.lookUp(Self.request(client: client), Self.film())
        let reason = try XCTUnwrap(Self.failureReason(report))
        XCTAssertTrue(reason.hasPrefix("Could not reach TMDB"), reason)
    }

    func test_aServerError_reportsItsStatus() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: { _ in .respond(status: 503, body: Data("busy".utf8)) })
        let report = try await Self.lookUp(Self.request(client: client), Self.film())
        let reason = try XCTUnwrap(Self.failureReason(report))
        XCTAssertTrue(reason.contains("HTTP 503"), reason)
    }

    func test_aCancellationNobodyAskedFor_isAFailedLookupNotAStoppedJob() async throws {
        // A CancellationError from the HTTP layer when neither Stop nor the
        // deadline cancelled anything must not escape: `run` throwing it
        // would mark the whole encode Cancelled because TMDB hiccupped.
        let client = AutoTagRunnerStubHTTPClient(route: { _ in .spuriousCancellation })

        let report = try await Self.lookUp(Self.request(client: client), Self.film())

        XCTAssertNotNil(Self.failureReason(report), "got \(report.outcome)")
    }

    func test_noResults_isNoMatch_afterRetryingWithoutTheYear() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.tmdbRoute(search: Self.emptySearch, details: [:]))

        let report = try await Self.lookUp(Self.request(client: client), Self.film())

        XCTAssertEqual(
            report.outcome,
            .noMatch(searchedFor: MetadataSearchQuery(mediaType: .movie, title: "Inception", year: 2010))
        )
        let searches = client.requests.map { request -> Bool in
            let items = URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems ?? []
            return items.contains { $0.name == "year" }
        }
        XCTAssertEqual(searches, [true, false], "one search with the year, then one without")
    }

    func test_anEmptyYearSearch_isRetriedWithoutTheYear_andCanStillMatch() async throws {
        // The file says 2011; TMDB lists the film under 2010. The retry finds
        // it, and the year mismatch costs only the year's 0.15 of the score.
        // Copied into locals so the `@Sendable` closure captures plain `Data`
        // values, not the test class's type.
        let empty = Self.emptySearch
        let found = Self.inceptionSearch
        let details = Self.inceptionDetails
        let route: @Sendable (URLRequest) -> AutoTagRunnerStubHTTPClient.Reply = { request in
            let items = URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems ?? []
            if (request.url?.path ?? "").hasSuffix("/search/movie") {
                return .respond(status: 200, body: items.contains { $0.name == "year" } ? empty : found)
            }
            return .respond(status: 200, body: details)
        }
        let client = AutoTagRunnerStubHTTPClient(route: route)

        let report = try await Self.lookUp(Self.request(client: client), Self.film(named: "Inception (2011).mkv"))

        XCTAssertEqual(report.outcome, .applied)
        XCTAssertEqual(report.identifiedFilm?.confidence ?? 0, 0.85, accuracy: 1e-9)
        XCTAssertEqual(client.requestCount, 3, "search with year, search without, one details request")
    }

    // MARK: - Scoring

    func test_theTrap_rawTMDBResultsNeverPassTheThreshold_soRealScoringIsWhatTags() async throws {
        // Half one: the trap exists. Every parsed result carries 0.5.
        let raw = try TMDBLookupService.parseSearchResults(Self.inceptionSearch, kind: .movie)
        let firstRaw = try XCTUnwrap(raw.first)
        let config = AutoTagConfig(enabled: true)
        XCTAssertEqual(firstRaw.confidence, 0.5)
        XCTAssertEqual(config.minimumConfidence, 0.7)
        XCTAssertFalse(
            AutoTagger.meetsThreshold(result: firstRaw, config: config),
            "if this ever passes, the threshold or the parser changed; re-read the runner's header"
        )

        // Half two: the runner still accepts a genuine match, because it
        // copies the rank's score into `confidence` before judging.
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)
        let report = try await Self.lookUp(Self.request(client: client), Self.film())

        XCTAssertEqual(report.outcome, .applied)
        XCTAssertEqual(report.identifiedFilm?.confidence ?? 0, 1.0, accuracy: 1e-9,
                       "running time, title and year all match: the rank's full score")
    }

    func test_belowThreshold_isNotApplied() async throws {
        // A 90-minute file against a 148-minute film: title and year match
        // (0.35 + 0.15) but the running time scores 0, so 0.5 < 0.7.
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)

        let report = try await Self.lookUp(Self.request(client: client), Self.film(minutes: 90))

        guard case .belowThreshold(let best, let needed) = report.outcome else {
            return XCTFail("expected below threshold, got \(report.outcome)")
        }
        XCTAssertEqual(best.title, "Inception")
        XCTAssertEqual(best.year, 2010)
        XCTAssertEqual(best.confidence, 0.5, accuracy: 1e-9)
        XCTAssertEqual(needed, 0.7, accuracy: 1e-9)
        XCTAssertTrue(report.tagsToAdd.isEmpty)
        XCTAssertNil(report.identifiedFilm)
    }

    func test_ambiguity_twoDifferentFilmsNeckAndNeck_appliesNeither() async throws {
        // "Solaris.mkv", 100 minutes, no year. Two films called Solaris at
        // 100 and 101 minutes score 0.85 and 0.825: both pass, 0.025 apart.
        let search = Self.searchBody([(1, "Solaris", "2002-11-27"), (2, "Solaris", "1972-03-20")])
        let client = AutoTagRunnerStubHTTPClient(route: Self.tmdbRoute(search: search, details: [
            1: Self.detailsBody(id: 1, title: "Solaris", date: "2002-11-27", runtime: 100, genres: ["Drama"]),
            2: Self.detailsBody(id: 2, title: "Solaris", date: "1972-03-20", runtime: 101, genres: ["Drama"]),
        ]))

        let report = try await Self.lookUp(Self.request(client: client), Self.film(named: "Solaris.mkv", minutes: 100))

        guard case .ambiguous(let first, let second) = report.outcome else {
            return XCTFail("expected ambiguous, got \(report.outcome)")
        }
        XCTAssertEqual(first.externalId, "1")
        XCTAssertEqual(second.externalId, "2")
        XCTAssertEqual(first.confidence, 0.85, accuracy: 1e-9)
        XCTAssertEqual(second.confidence, 0.825, accuracy: 1e-9)
        XCTAssertTrue(report.tagsToAdd.isEmpty)
        XCTAssertNil(report.identifiedFilm)
    }

    func test_ambiguity_aClearWinnerIsStillApplied() async throws {
        // Same two films, but the second runs 105 minutes: it still passes
        // (0.725) yet trails by 0.125, well outside the 0.05 margin.
        let search = Self.searchBody([(1, "Solaris", "2002-11-27"), (2, "Solaris", "1972-03-20")])
        let client = AutoTagRunnerStubHTTPClient(route: Self.tmdbRoute(search: search, details: [
            1: Self.detailsBody(id: 1, title: "Solaris", date: "2002-11-27", runtime: 100, genres: ["Drama"]),
            2: Self.detailsBody(id: 2, title: "Solaris", date: "1972-03-20", runtime: 105, genres: ["Drama"]),
        ]))

        let report = try await Self.lookUp(Self.request(client: client), Self.film(named: "Solaris.mkv", minutes: 100))

        XCTAssertEqual(report.outcome, .applied)
        XCTAssertEqual(report.identifiedFilm?.externalId, "1")
        XCTAssertEqual(AutoTagRunner.ambiguityMargin, 0.05)
    }

    func test_rankIgnoresDiscType() {
        // The runner scores files with `DiscIdentifier.rank`, which was
        // written for discs, and passes `.dataDisc` only because
        // `DiscSignals` requires a disc type. Pinned: if `rank` ever starts
        // reading `discType`, file scores would shift and this fails first.
        let candidates = [
            MetadataResult(source: .tmdb, externalId: "1", title: "Inception", year: 2010, runtimeMinutes: 148),
            MetadataResult(source: .tmdb, externalId: "2", title: "Inception Extras", year: 2011, runtimeMinutes: 20),
            MetadataResult(source: .tmdb, externalId: "3", title: "Something Else", year: nil, runtimeMinutes: nil),
        ]
        func scores(_ type: DiscType) -> [String] {
            let signals = DiscSignals(
                discType: type, mainFeatureDurationSeconds: 8880, seedTitle: "Inception", seedYear: 2010
            )
            return DiscIdentifier.rank(signals: signals, candidates: candidates)
                .map { "\($0.candidate.externalId)=\($0.score.confidence)" }
        }

        let baseline = scores(.dataDisc)
        for type in DiscType.allCases {
            XCTAssertEqual(scores(type), baseline, "rank must not depend on discType (\(type))")
        }
    }

    // MARK: - What a successful match adds

    func test_success_addsOnlyMissingTags_andNeverOverwritesTheFileOrTheJob() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)
        let file = Self.film(tags: ["TITLE": "Inception", "date": "2010"])

        let report = try await Self.lookUp(Self.request(client: client), file, jobTags: ["genre": "Mine"])

        XCTAssertEqual(report.outcome, .applied)
        XCTAssertEqual(report.provider, .tmdb)
        XCTAssertEqual(
            report.metadataToAdd,
            ["description": "An overview.", "tmdb_id": String(inceptionID)],
            "title and date are the file's own and genre is the job's own; only the rest is added"
        )
        XCTAssertEqual(
            Self.pairs(report.keptExisting),
            ["TITLE": "Inception", "date": "2010", "genre": "Mine"],
            "kept with their ORIGINAL values, not TMDB's"
        )
        XCTAssertEqual(report.identifiedFilm?.externalId, String(inceptionID))
    }

    func test_success_onAnUntaggedFile_addsEverythingTheMatchSupplies() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)

        let report = try await Self.lookUp(Self.request(client: client), Self.film())

        XCTAssertEqual(report.outcome, .applied)
        XCTAssertEqual(report.metadataToAdd, [
            "title": "Inception",
            "date": "2010",
            "genre": "Action; Science Fiction",
            "description": "An overview.",
            "tmdb_id": String(inceptionID),
        ])
        XCTAssertTrue(report.keptExisting.isEmpty)
        XCTAssertEqual(client.requestCount, 2, "one search, one details request for the running time")
    }

    func test_aConfidentMatchWithNothingMissing_isMatchedNothingToAdd() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)
        let file = Self.film(tags: [
            "title": "Inception", "date": "2010", "genre": "Heist",
            "synopsis": "My own words.", "tmdb_id": String(inceptionID),
        ])

        let report = try await Self.lookUp(Self.request(client: client), file)

        XCTAssertEqual(report.outcome, .matchedNothingToAdd)
        XCTAssertTrue(report.tagsToAdd.isEmpty)
        XCTAssertNotNil(report.identifiedFilm, "the film was still identified (the NFO writer needs it)")
    }

    func test_success_throughTheRealSettingsSource() async throws {
        // The same path the engine will take (#508 commit 6): a settings
        // source reads the switch, builds the request, and the runner uses it.
        let suiteName = "AutoTagRunnerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)

        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)
        let source = AutoTagSettingsSource(
            suiteName: suiteName,
            tmdbKeyProvider: { autoTagRunnerTestKey },
            httpClient: client,
            musicBrainzThrottle: MusicBrainzRequestThrottle(minimumInterval: .zero)
        )
        let request = try XCTUnwrap(source.currentRequest())

        let report = try await Self.lookUp(request, Self.film())

        XCTAssertEqual(report.outcome, .applied)
        XCTAssertEqual(report.metadataToAdd["tmdb_id"], String(inceptionID))
    }

    // MARK: - Deadline and Stop

    func test_deadline_givesAFailure_andReallyAbandonsTheRequest() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: { _ in .hang })
        let started = ContinuousClock.now

        let report = try await Self.lookUp(Self.request(client: client, deadline: .milliseconds(50)), Self.film())

        XCTAssertEqual(report.outcome, .failed(reason: "TMDB didn't answer within 0.05 seconds."))
        XCTAssertEqual(report.provider, .tmdb)
        XCTAssertEqual(
            client.cancelledCount, 1,
            "the in-flight request was cancelled, and `run` waited for it to end rather than leaving it running"
        )
        XCTAssertLessThan(started.duration(to: .now), .seconds(10))
    }

    func test_deadlineWording() {
        XCTAssertEqual(
            AutoTagRunner.Reasons.didNotAnswer(provider: "TMDB", within: .seconds(30)),
            "TMDB didn't answer within 30 seconds."
        )
        XCTAssertEqual(
            AutoTagRunner.Reasons.didNotAnswer(provider: "TMDB", within: .seconds(1)),
            "TMDB didn't answer within 1 second."
        )
    }

    func test_stopDuringTheLookup_throwsCancellation_quickly() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: { _ in .hang })
        let started = ContinuousClock.now

        do {
            _ = try await Self.lookUp(
                Self.request(client: client, deadline: .seconds(120)),
                Self.film(),
                shouldStop: { client.requestCount > 0 }
            )
            XCTFail("a stop must throw, not return a report")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(client.cancelledCount, 1, "the in-flight request was cancelled, not left running")
        XCTAssertLessThan(started.duration(to: .now), .seconds(10), "stop is noticed within a poll, not at the deadline")
    }

    func test_stopBeforeTheLookup_throwsCancellation_andSendsNothing() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.inceptionRoute)

        do {
            _ = try await Self.lookUp(Self.request(client: client), Self.film(), shouldStop: { true })
            XCTFail("a stop must throw")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertEqual(client.requestCount, 0)
    }

    func test_cancellingTheCallingTask_throwsCancellation_andCancelsTheRequest() async throws {
        let canceller = AutoTagRunnerTaskCanceller()
        let client = AutoTagRunnerStubHTTPClient(onRequest: { canceller.fire() }, route: { _ in .hang })
        let request = Self.request(client: client, deadline: .seconds(120))
        let file = Self.film()
        let started = ContinuousClock.now

        let task = Task {
            try await AutoTagRunner.run(request: request, source: file, jobTags: [:], shouldStop: { false })
        }
        canceller.hold(task)

        do {
            _ = try await task.value
            XCTFail("a cancelled task must throw")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertEqual(client.cancelledCount, 1)
        XCTAssertLessThan(started.duration(to: .now), .seconds(10))
    }

    // MARK: - Music: choosing an artist to search with (pure, no network)

    func test_plan_music_artistFromATagIsUsed() {
        let file = Self.song(named: "Track 4.flac", tags: ["artist": "Queen", "title": "Bohemian Rhapsody"])
        XCTAssertEqual(
            AutoTagRunner.plan(for: file),
            .music(MetadataSearchQuery(mediaType: .music, title: "Bohemian Rhapsody", artist: "Queen"))
        )
    }

    func test_plan_music_artistFromAHyphenFileNameIsUsed() {
        // The shared `FilenameParser`/`MusicBrainzTagMapping.seedQuery` path
        // already handles the ASCII hyphen; this pins that the runner's own
        // plan carries it through untouched.
        let plan = AutoTagRunner.plan(for: Self.song(named: "Queen - Bohemian Rhapsody.flac"))
        guard case .music(let query) = plan else {
            return XCTFail("expected .music, got \(plan)")
        }
        XCTAssertEqual(query.artist, "Queen")
        XCTAssertEqual(query.title, "Bohemian Rhapsody")
    }

    func test_plan_music_artistFromAnEnDashFileNameIsUsed() {
        // The shared parser only recognises an ASCII hyphen; an en dash is
        // the runner's OWN fallback (`musicArtistTitleFromFileName`), which
        // exists because this exact shape is common in real music files.
        let plan = AutoTagRunner.plan(for: Self.song(named: "Queen – Bohemian Rhapsody.flac"))
        guard case .music(let query) = plan else {
            return XCTFail("expected .music, got \(plan)")
        }
        XCTAssertEqual(query.artist, "Queen")
        XCTAssertEqual(query.title, "Bohemian Rhapsody")
    }

    func test_plan_music_aTagTitleIsNeverOverwrittenByTheFileNameFallback() {
        // A `title` TAG must win even when the file name also looks like
        // "Artist – Title" — only the missing ARTIST is topped up from the
        // name, exactly as `seedQuery` already prefers a tag's own title.
        let file = Self.song(named: "Queen – Bohemian Rhapsody.flac", tags: ["title": "My Own Rip"])
        guard case .music(let query) = AutoTagRunner.plan(for: file) else {
            return XCTFail("expected .music, got \(AutoTagRunner.plan(for: file))")
        }
        XCTAssertEqual(query.artist, "Queen")
        XCTAssertEqual(query.title, "My Own Rip")
    }

    func test_plan_music_withNoArtistAnywhereIsStillClassifiedAsMusic() {
        // `plan` only CLASSIFIES a file; it does not enforce "an artist is
        // required" (that's `run`'s `Reasons.noArtistForMusic`) — a music
        // file with no artist anywhere must still come back `.music`, not
        // `.skip`, the same shape `test_plan_anMP3WithCoverArtIsMusicNeverAFilm`
        // already pins for the cover-art case.
        let file = Self.song(named: "Symphony No. 5.flac")
        guard case .music(let query) = AutoTagRunner.plan(for: file) else {
            return XCTFail("expected .music, got \(AutoTagRunner.plan(for: file))")
        }
        XCTAssertNil(query.artist)
    }

    // MARK: - Music: what a successful match adds

    func test_success_music_addsOnlyMissingTags_andNeverOverwritesTheFileOrTheJob() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: Self.bohemianRhapsodyRoute)
        let file = Self.song(tags: ["TITLE": "Bohemian Rhapsody"])

        let report = try await Self.lookUp(Self.request(client: client), file, jobTags: ["artist": "Someone Else"])

        XCTAssertEqual(report.outcome, .applied)
        XCTAssertEqual(report.provider, .musicBrainz)
        XCTAssertEqual(
            report.metadataToAdd,
            ["musicbrainz_trackid": Self.bohemianRhapsodyID, "musicbrainz_artistid": Self.queenID],
            "title is the file's own and artist is the job's own; only the identifiers were genuinely missing"
        )
        XCTAssertEqual(
            Self.pairs(report.keptExisting),
            ["TITLE": "Bohemian Rhapsody", "artist": "Someone Else"],
            "kept with their ORIGINAL values, not MusicBrainz's"
        )
    }

    // MARK: - Music: the length rule (owner's decision: max(5s, 3%), an artist required)

    func test_run_music_lengthWithinTolerance_isApplied() async throws {
        // The file is 200 s; the tolerance is max(5, 200 * 0.03) = 6 s. A
        // recording 5 s off is INSIDE that, so the match must be trusted.
        let search = Self.recordingSearchBody([
            StubRecording(id: Self.bohemianRhapsodyID, score: 90, title: "Bohemian Rhapsody", artist: "Queen", lengthMs: 205_000),
        ])
        let client = AutoTagRunnerStubHTTPClient(route: Self.musicBrainzRoute(search: search))

        let report = try await Self.lookUp(Self.request(client: client), Self.song(seconds: 200))

        XCTAssertEqual(report.outcome, .applied)
        XCTAssertEqual(report.metadataToAdd["title"], "Bohemian Rhapsody")
        XCTAssertEqual(report.metadataToAdd["artist"], "Queen")
    }

    func test_run_music_lengthJustOutsideTolerance_isBelowThreshold_notApplied() async throws {
        // Same 200 s file and the same 6 s tolerance; this recording is 7 s
        // off — just past it — so it must score confidence 0 and be
        // REJECTED even though its title, artist and raw MusicBrainz score
        // all matched well.
        let search = Self.recordingSearchBody([
            StubRecording(id: Self.bohemianRhapsodyID, score: 90, title: "Bohemian Rhapsody", artist: "Queen", lengthMs: 207_000),
        ])
        let client = AutoTagRunnerStubHTTPClient(route: Self.musicBrainzRoute(search: search))

        let report = try await Self.lookUp(Self.request(client: client), Self.song(seconds: 200))

        guard case .belowThreshold(let best, let needed) = report.outcome else {
            return XCTFail("expected below threshold, got \(report.outcome)")
        }
        XCTAssertEqual(best.confidence, 0, "a length outside tolerance must zero the confidence, whatever the raw score")
        XCTAssertEqual(needed, 0.7, accuracy: 1e-9)
        XCTAssertTrue(report.tagsToAdd.isEmpty)
    }

    func test_run_music_recordingWithNoLength_isBelowThreshold_notApplied() async throws {
        let search = Self.recordingSearchBody([
            StubRecording(id: Self.bohemianRhapsodyID, score: 100, title: "Bohemian Rhapsody", artist: "Queen", lengthMs: nil),
        ])
        let client = AutoTagRunnerStubHTTPClient(route: Self.musicBrainzRoute(search: search))

        let report = try await Self.lookUp(Self.request(client: client), Self.song())

        guard case .belowThreshold(let best, _) = report.outcome else {
            return XCTFail("expected below threshold, got \(report.outcome)")
        }
        XCTAssertEqual(best.confidence, 0, "no length at all must zero the confidence, however high the raw score")
        XCTAssertTrue(report.tagsToAdd.isEmpty)
    }

    func test_ambiguity_music_twoDifferentRecordingsNeckAndNeck_appliesNeither() async throws {
        // Two different recordings of the same song, both a good length
        // match, scored 90 and 87: both clear the 0.7 threshold and are
        // only 0.03 apart — inside the 0.05 margin — so neither is trusted.
        let search = Self.recordingSearchBody([
            StubRecording(
                id: "11111111-0000-0000-0000-000000000001", score: 90,
                title: "Bohemian Rhapsody", artist: "Queen", lengthMs: 354_000
            ),
            StubRecording(
                id: "11111111-0000-0000-0000-000000000002", score: 87,
                title: "Bohemian Rhapsody", artist: "Queen", lengthMs: 354_000
            ),
        ])
        let client = AutoTagRunnerStubHTTPClient(route: Self.musicBrainzRoute(search: search))

        let report = try await Self.lookUp(Self.request(client: client), Self.song())

        guard case .ambiguous(let first, let second) = report.outcome else {
            return XCTFail("expected ambiguous, got \(report.outcome)")
        }
        XCTAssertEqual(first.externalId, "11111111-0000-0000-0000-000000000001")
        XCTAssertEqual(second.externalId, "11111111-0000-0000-0000-000000000002")
        XCTAssertEqual(first.confidence, 0.90, accuracy: 1e-9)
        XCTAssertEqual(second.confidence, 0.87, accuracy: 1e-9)
        XCTAssertTrue(report.tagsToAdd.isEmpty)
        XCTAssertEqual(AutoTagRunner.ambiguityMargin, 0.05)
    }

    // MARK: - Music: deadline and Stop (same race the film path uses)

    func test_deadline_music_givesAFailure_andReallyAbandonsTheRequest() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: { _ in .hang })
        let started = ContinuousClock.now

        let report = try await Self.lookUp(Self.request(client: client, deadline: .milliseconds(50)), Self.song())

        XCTAssertEqual(report.outcome, .failed(reason: "MusicBrainz didn't answer within 0.05 seconds."))
        XCTAssertEqual(report.provider, .musicBrainz)
        XCTAssertEqual(
            client.cancelledCount, 1,
            "the in-flight request was cancelled, and `run` waited for it to end rather than leaving it running"
        )
        XCTAssertLessThan(started.duration(to: .now), .seconds(10))
    }

    func test_stopDuringTheLookup_music_throwsCancellation_quickly() async throws {
        let client = AutoTagRunnerStubHTTPClient(route: { _ in .hang })
        let started = ContinuousClock.now

        do {
            _ = try await Self.lookUp(
                Self.request(client: client, deadline: .seconds(120)),
                Self.song(),
                shouldStop: { client.requestCount > 0 }
            )
            XCTFail("a stop must throw, not return a report")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(client.cancelledCount, 1, "the in-flight request was cancelled, not left running")
        XCTAssertLessThan(started.duration(to: .now), .seconds(10), "stop is noticed within a poll, not at the deadline")
    }
}
