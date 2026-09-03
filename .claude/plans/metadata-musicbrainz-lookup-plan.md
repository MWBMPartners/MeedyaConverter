<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Implementation Plan — MusicBrainz metadata lookup executes and feeds auto-tagging (#205, follows #493)

> **Status: PLANNED.** Fable 5.1 deep-plan (2026-09-03) against HEAD `20d1534` on `wip/alpha-consolidation` (tree clean; the snapshot in the task brief said `9511291` — HEAD has moved, re-verify anchors with `git log -1` before editing). `swift test` is CI-only; **`swift build --build-tests` also fails locally** (`no such module 'XCTest'` — verified this session), so test files can only be gated by `swiftc -parse` + CI. Live MusicBrainz traffic is NOT CI-verifiable; the seam makes everything below it testable with canned JSON captured from the real API this session.

## Decisions (trade-offs weighed before design)

1. **Protocol seam, not a `URLProtocol` mock.** The house already has `MockURLProtocol` (`CloudUploadExecutorTests.swift:43-106`) with a process-global static FIFO queue — fragile under `swift test --parallel` and its name is taken. A `MetadataHTTPClient: Sendable` protocol (mirrors `DualDynamicHDRStepRunning`, `MediaFileProbing`, `GitRunning`) gives per-test isolation and lets the mock record request timing for throttle tests.
2. **Plain `Sendable` on the URLSession conformer.** Verified in the local SDK: `NSURLSession` is `NS_SWIFT_SENDABLE` (`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSURLSession.h:119`) and `NSHTTPURLResponse` too (`NSURLResponse.h:124`); `CloudUploadExecutor.swift:222` already compiles a `@Sendable (Data, HTTPURLResponse)` closure. Fallback if CI's compiler objects: `@unchecked Sendable` with the rationale at `CloudUploadExecutor.swift:76-83`.
3. **A rich `MusicBrainzRecordingMatch` model plus a bridge to the existing `MetadataResult`.** `MetadataResult` (`MetadataLookup.swift:133-242`) cannot carry release/artist MBIDs, the `releases` list or a millisecond length, all of which the editor's picker needs. Rather than widen `MetadataResult`, the new model bridges via `.metadataResult` — and that bridge gets a real caller by wiring `SuiteCoreMetadataAdapter.searchViaInline` for `.musicBrainz` (Decision 4).
4. **Wire the adapter's inline MusicBrainz path (small) rather than only fixing its comments.** `SuiteCoreMetadataAdapter.swift:190-195` states "there is no `URLSession` anywhere in that directory" and always throws `.notImplemented`. After this lands that comment is false either way; wiring `.musicBrainz` through the service (~15 lines + 2 test edits) makes the Settings "Inline only" metadata-backend option (`SettingsView.swift:255-290`) mean something, and gives `metadataResult` its caller. Every other source keeps throwing `.notImplemented` (they need keys — out of scope).
5. **Recording search only; the `/release` builder stays a builder.** A recording search response already embeds the matching release (album title, date, medium position, track number, release-group) — verified in the captured response — so one request answers auto-tagging. Executing `buildReleaseSearchURL`/`buildRecordingLookupURL`/`AudioCDReader.buildMusicBrainzLookupURL` would add symbols with no UI caller; they are listed as follow-ups (Risk 12).
6. **Tag-key spelling is preserved.** `FFmpegProbe.swift:146` whitelists `format_tags=title,artist,album,date,comment,genre,track,encoder` but keys keep the container's spelling (FLAC/Vorbis files surface `TITLE`/`ARTIST`), so the mapper matches case-insensitively, rewrites the *existing* tag in place (same `id`, same key spelling) and only appends canonical lowercase keys that are missing.
7. **Rank by score, then by closeness to the file's duration.** The real top-2 hits for `recording:"Bohemian Rhapsody" AND artist:"Queen"` were both *live* recordings at score 100; the file's ffprobe `duration` is the cheapest disambiguator. Pure, tested.

## Files

| Action | Path |
|---|---|
| **Create** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/Sources/ConverterEngine/Metadata/MetadataHTTPClient.swift` — `MetadataHTTPClient` protocol, `URLSessionMetadataHTTPClient`, `MetadataHTTPClientError` |
| **Create** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/Sources/ConverterEngine/Metadata/MusicBrainzLookupService.swift` — `MusicBrainzRecordingMatch`, `MusicBrainzLookupError`, `MusicBrainzRequestThrottle`, `MusicBrainzLookupService` (+ private wire-format `Decodable` structs) |
| **Create** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/Sources/ConverterEngine/Metadata/MusicBrainzTagMapping.swift` — `MusicBrainzTagMapping` (seed query, ranking, apply-to-tags) |
| **Modify** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/Sources/ConverterEngine/Metadata/MetadataLookup.swift` — `MusicBrainzClient` type doc + `buildRecordingSearchRequest(title:artist:)` + `requestTimeoutSeconds` |
| **Modify** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/Sources/ConverterEngine/SuiteCore/SuiteCoreMetadataAdapter.swift` — inject service, route `.musicBrainz` inline, rewrite false doc |
| **Create** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/Sources/MeedyaConverter/Views/MusicBrainzLookupSheet.swift` — the lookup sheet (module `MeedyaConverterCore`) |
| **Modify** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/Sources/MeedyaConverter/Views/MetadataTagEditorView.swift` — "Look Up…" button, sheet, apply, header doc, empty-state text |
| **Create** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/Tests/ConverterEngineTests/MusicBrainzLookupServiceTests.swift` — mock client, fixtures, ~34 cases |
| **Modify** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/Tests/ConverterEngineTests/ConverterEngineTests+SuiteCore.swift` — two tests at L151-199 |
| **Modify** | `/Users/lance.manasse/Projects/Coding & Development/MWBM Partners Ltd/GitHub/MeedyaSuite/MeedyaConverter/CHANGELOG.md` — one bullet, first under `## [Unreleased]` → `### Added` (anchor by text: before `- **Video stabilization**`) |

Reference patterns (read, don't modify): `DualDynamicHDRPipelineExecutor.swift:61-75` (seam doc + protocol); `CloudUploadExecutor.swift:129-164` (`UploadError` shape: `invalidResponse`/`httpError(statusCode:bodySnippet:)`/`transport(String)`), `:168-183` (injected session); `GitHubReleaseChecker.swift:211-215` (Accept/User-Agent/timeout on the request), `:218-273` (status switch + `URLError` code mapping); `MediaServerIntegration.swift:127-139`; `CloudStorageView.swift:655-662` (plain `Task { }` is correct for `URLSession` work — no `Task.detached`); `MetadataTagEditorView.swift:599-613` (`View` struct methods are main-actor; plain `Task { }` inherits it); `StorageAnalyzerProbeTests.swift:53-123` (async mock using `lock.withLock`); `GitProfileSyncTests.swift:39-101`; `DualDynamicHDRPipelineExecutorTests.swift:60-63` (why `withLock`).

## Current behaviour (verified against code, not comments)

`Sources/ConverterEngine/Metadata/MetadataLookup.swift` (647 lines)
- `MetadataSource` L13-68: `.musicBrainz` L21, `baseURL` L53 = `https://musicbrainz.org/ws/2`, `requiresAPIKey` L61-67 (`false` only for `.musicBrainz`). `MediaLookupType` L73-79. `MetadataSearchQuery` L84-128 (`Codable, Sendable`, NOT `Equatable`; `title`, `artist`, `album`, …). `MetadataResult` L133-242 (`externalId`, `title`, `year`, `releaseDate`, `artist` L186, `album` L189, `trackNumber` L192, `confidence` L195; all-defaults init L197).
- `MusicBrainzClient` L296-510: `private` `escapeLucenePhraseValue` L381-386 and `luceneClause` L408-410, `safeQueryValueCharacters` L441-445, `percentEncodeQueryValue` L457-459; **public builders return `String`**: `buildRecordingSearchURL(title:artist:)` L469-479 (`…/recording?query=<enc>&fmt=json&limit=10`), `buildReleaseSearchURL` L485-495, `buildRecordingLookupURL(recordingId:)` L502-506; `userAgent` L509 = `MeedyaConverter/1.0 (https://github.com/MWBMPartners/MeedyaConverter)`. Type doc L300-311 says "this type parses no response at all" — true, and stays true for this type.
- **What is missing:** no `URLRequest`, no `URLSession`, no `JSONDecoder`, no `Codable` response struct, no error type, no throttle — anywhere in `Sources/ConverterEngine/Metadata/` (grep across `Sources` confirmed; the only `URLSession` calls in the engine are `MediaServerIntegration`, `WebhookSender`, `TeamProfileManager`, `AnalyticsEngine`, `CloudUploadExecutor`). Nothing in either app or engine calls any `MusicBrainzClient` builder except tests.
- `FilenameParser.parse(filename:)` L557-647: TV → movie → music (`Artist - Title`, L630-646) → fallback `.movie` with `.`/`_` → space.

`Sources/ConverterEngine/Metadata/MetadataProviders.swift` — every client takes a key/token: `TheTVDBClient` L29 (bearer; "scheduled for removal #374" L12-15), `OMDbClient` L122, `DiscogsClient` L204, `FanArtTVClient` L282, `AcoustIDClient` L360, `MeedyaDBClient` L432. Keyless = MusicBrainz only (plus `AudioCDReader.buildMusicBrainzLookupURL(toc:)` L371-373, also MusicBrainz, also unexecuted). `MediaServerTagging.buildFFmpegMetadataArguments(result:)` L637-677 consumes `MetadataResult.artist/album/trackNumber`.

`Sources/ConverterEngine/SuiteCore/SuiteCoreMetadataAdapter.swift` — `public struct … Sendable` L56, `backend` L59, `init(backend:)` L75-77, `search(source:query:)` L152-161 → `searchViaInline` L203-210 **always throws** `SuiteCoreBridgeError.notImplemented("Inline metadata search for \(source.displayName)")`. Doc L190-195 claims "Neither file performs HTTP (there is no `URLSession` anywhere in that directory)"; L196-200 says the recorded strategy "chooses the latter" (suite-core). No app code calls `.search` (only `SettingsView.swift:271` mentions the adapter in a comment).

`Tests/ConverterEngineTests/ConverterEngineTests+SuiteCore.swift` — L151-182 `test_suiteCoreMetadataAdapter_inlinePathThrowsRatherThanFakingEmptyResults` asserts `.musicBrainz` inline throws `.notImplemented` (doc L157-159 repeats the "no `URLSession`" claim); L184-199 `…everyInlineSourceThrowsNotImplemented` iterates `MetadataSource.allCases`. Both break when MusicBrainz becomes real — they must be rewritten, not deleted.

`Sources/ConverterEngine/Utilities/MetadataTagEditor.swift` — `MediaTag` L19-42 (`id: UUID`, `key`, `value`; `init(id:key:value:)` L37; `Equatable` includes `id`). `buildWriteArguments(tags:artworkPath:)` L95-131 emits `-metadata key=value` for every tag with non-empty key AND value (L126-128).

`Sources/MeedyaConverter/Views/MetadataTagEditorView.swift` (722 lines) — `@State tags: [MediaTag]` L31, `selectedTagID` L34, `showingEditor` L49, `writeStatusMessage` L83. `body` L95-141: `.sheet(isPresented: $showingEditor)` L112-114, `.onDisappear { cancelWrite() }` L127-129, seeding L135-140 → `seedTagsFromSelectedFile()` L146-154 maps `viewModel.selectedFile?.metadata` (`[String: String]`) to `MediaTag`s sorted by key. `controlsBar` L159-210: Add L161-166, Edit L168-174, Remove L176-182, `Divider` L184-185, Clear All L187-193, `Spacer` L195, template `Picker` L197-206. `emptyTagsView` text L487-490. `writeTags()` L614-690 (real ffmpeg write; logs via `viewModel.appendLog(.info, …, category: .metadata)` L671-675). Header doc L14-21 lists features — no lookup. **No lookup control exists anywhere in the UI.**
- Reachability: `NavigationItem.metadataTags` (`AppViewModel.swift:82`) is NOT in `NavigationItem.unavailable` (`AppViewModel.swift:178` = `[.vectorConversion, .proresVector, .cloudSync]`); `SidebarView.swift:54` lists it; `ContentView.swift:132-133` renders `MetadataTagEditorView()`. So a button added to `controlsBar` is reachable.

Engine facts for seeding/sanitising
- `MediaFile` (`Models/MediaFile.swift:17`): `fileURL` L25, `fileName` L28-30, `duration: TimeInterval?` L51, `metadata: [String: String]` L57. `AppViewModel.selectedFile: MediaFile?` L351; `appendLog(_:_:source:category:rawOutput:details:jobID:)` L2422-2440; `LogEntry.Category.metadata` L2722.
- `FFmpegProbe.swift:146` whitelist (`title,artist,album,date,comment,genre,track,encoder`); keys/values sanitised via `MetadataSanitizer.sanitize` L479-485 (SECURITY.md F-006). `MetadataSanitizer.sanitize` L88, `sanitizeSingleLine` L130 — MusicBrainz strings are untrusted input rendered in UI/log/argv, so they get `sanitizeSingleLine`.
- Entitlements: `com.apple.security.network.client` present in both `MeedyaConverter.entitlements:26` and `MeedyaConverter-AppStore.entitlements:16`.
- Test-target facts: top-level names already taken in `ConverterEngineTests` include `MockURLProtocol`, `ProgressRecorder`, `DoubleProgressRecorder`, `SmartCropProgressRecorder`, `MockMediaFileProber`, `MockGitRunner`, `MockFrameExtractor`, `MockSubjectDetector`, `MockDualDynamicHDRStepRunner`. All new test types are `MusicBrainz…`-prefixed. SwiftLint: `type_name` max 60, `line_length` disabled.
- Toolchain: local Swift 6.3.3; CI `macos-15`, `swift build` then `swift test --parallel` (`build.yml:143,152`); `.macOS(.v15)`, `.swiftLanguageMode(.v6)` on both `ConverterEngine` and `MeedyaConverterCore`.

**Real MusicBrainz response shape** (captured this session, `GET /ws/2/recording?query=recording%3A%22Bohemian%20Rhapsody%22%20AND%20artist%3A%22Queen%22&fmt=json&limit=2`, HTTP 200 `application/json`): envelope `{created, count, offset, recordings[]}`; each recording `{id, score:Int, title, length:Int(ms, may be absent), disambiguation?, video:null, artist-credit:[{name, joinphrase?, artist:{id,name,sort-name,disambiguation?,aliases?}}], first-release-date? ("1992" — partial dates occur), releases:[{id, title, status?, status-id?, count, artist-credit?, release-group:{id,title,primary-type?,secondary-types?[]}, date?, country?, release-events?, track-count, media:[{id, position, format?, track:[{id, number:String, title, length}], track-count, track-offset}]}]}`. Only the medium containing the recording is listed in `media`, with only the matching `track`. HTTP 400 body (captured, `query=` empty): `{"help":"For usage, please see: https://musicbrainz.org/development/mmd","error":"The given parameters do not match any available query type for the recording resource."}`. Rate-limit policy per https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting: ~1 request/second per IP, HTTP 503 when exceeded, a descriptive `User-Agent` required.

## Design

### Seam — `MetadataHTTPClient.swift`
```swift
/// Abstraction over "send one HTTP request", so metadata lookups can be
/// unit-tested with canned responses (`MusicBrainzMockHTTPClient` in
/// `MusicBrainzLookupServiceTests`) and never hit the network in CI.
/// `URLSessionMetadataHTTPClient` is the production conformer.
public protocol MetadataHTTPClient: Sendable {
    /// Send `request` and return the body plus the HTTP response.
    /// - Throws: Any transport error (`URLError` from `URLSession`, or
    ///   `MetadataHTTPClientError.nonHTTPResponse`). Cancellation surfaces as
    ///   `URLError.cancelled` from `URLSession`; callers normalise it.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum MetadataHTTPClientError: Error, Sendable, Equatable, LocalizedError {
    case nonHTTPResponse
    public var errorDescription: String? { "The server returned a response that was not an HTTP response." }
}

public struct URLSessionMetadataHTTPClient: MetadataHTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MetadataHTTPClientError.nonHTTPResponse }
        return (data, http)
    }
}
```

### Request builder — extend `MusicBrainzClient` (`MetadataLookup.swift`, after L509)
```swift
/// Per-request timeout for MusicBrainz calls (seconds).
public static let requestTimeoutSeconds: TimeInterval = 15

/// The ready-to-send request for a recording search: the URL from
/// `buildRecordingSearchURL(title:artist:)` plus the two headers MusicBrainz
/// requires — `User-Agent` (`userAgent`; see
/// https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting) and
/// `Accept: application/json` — and `requestTimeoutSeconds`.
/// Returns `nil` only if Foundation rejects the assembled string as a URL,
/// which is not expected: every user-controlled character is percent-encoded.
/// Called by `MusicBrainzLookupService.searchRecordings(title:artist:)`.
public static func buildRecordingSearchRequest(title: String, artist: String?) -> URLRequest? {
    guard let url = URL(string: buildRecordingSearchURL(title: title, artist: artist)) else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = requestTimeoutSeconds
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
}
```

### Throttle, model, errors, service — `MusicBrainzLookupService.swift`
```swift
/// Serialises MusicBrainz requests so the process never exceeds the documented
/// ~1 request/second. Each caller is handed the next free slot BEFORE it
/// suspends, so concurrent callers get strictly spaced slots even though
/// the actor is not blocked while they sleep. Cancelling a waiting caller
/// throws `CancellationError` from `Task.sleep`; its slot stays consumed
/// (conservative — never lets a cancel produce a burst).
public actor MusicBrainzRequestThrottle {
    /// Process-wide instance every production `MusicBrainzLookupService` uses.
    /// 1.1 s rather than 1.0 s so clock jitter cannot trip the server limit.
    public static let shared = MusicBrainzRequestThrottle(minimumInterval: .milliseconds(1100))
    private let minimumInterval: Duration
    private var nextPermittedStart: ContinuousClock.Instant?
    public init(minimumInterval: Duration) { self.minimumInterval = minimumInterval }
    public func waitForTurn() async throws {
        let now = ContinuousClock.now
        let start = max(now, nextPermittedStart ?? now)
        nextPermittedStart = start + minimumInterval
        if start > now { try await Task.sleep(until: start, clock: .continuous) }
    }
}

public struct MusicBrainzRecordingMatch: Sendable, Equatable, Identifiable {
    public struct ArtistCredit: Sendable, Equatable {
        public let name: String        // credited name (may differ from artist.name)
        public let joinPhrase: String  // "" when absent; e.g. " & ", " feat. "
        public let artistID: String?   // artist MBID
        public init(name: String, joinPhrase: String = "", artistID: String? = nil)
    }
    public struct Release: Sendable, Equatable {
        public let id: String                 // release MBID
        public let title: String
        public let status: String?            // "Official", "Bootleg", …
        public let date: String?              // "YYYY", "YYYY-MM" or "YYYY-MM-DD"
        public let country: String?
        public let albumArtist: String?       // joined release artist-credit, nil if absent
        public let releaseGroupID: String?
        public let primaryType: String?       // "Album", "Single", …
        public let secondaryTypes: [String]   // "Live", "Compilation", …
        public let trackNumber: String?       // as MusicBrainz reports it ("1", "B5")
        public let mediumPosition: Int?
        public let mediumFormat: String?
        public let mediumTrackCount: Int?
        public var trackNumberValue: Int? { trackNumber.flatMap { Int($0) } }
        public init(id:title:status:date:country:albumArtist:releaseGroupID:primaryType:secondaryTypes:trackNumber:mediumPosition:mediumFormat:mediumTrackCount:) // all optionals default nil, secondaryTypes default []
    }
    public let id: String                 // recording MBID
    public let title: String
    public let score: Int                 // 0…100 as MusicBrainz reports it
    public let artistCredits: [ArtistCredit]
    public let artist: String             // credits joined: name+joinPhrase…; "" when no credits
    public let lengthMilliseconds: Int?
    public let disambiguation: String?
    public let firstReleaseDate: String?
    public let releases: [Release]
    public var lengthSeconds: Double? { lengthMilliseconds.map { Double($0) / 1000 } }
    public var artistIDs: [String] { artistCredits.compactMap(\.artistID) }
    public init(id:title:score:artistCredits:lengthMilliseconds:disambiguation:firstReleaseDate:releases:) // public memberwise; `artist` derived

    /// The release to take album/date/track from: exact (case-insensitive)
    /// album-title match → first "Official" release whose release-group is a
    /// plain "Album" (no secondary types) → first "Official" → first listed.
    public func bestRelease(preferringAlbumTitled album: String?) -> Release?

    /// Lossy bridge to the house `MetadataResult` (no MBIDs beyond `externalId`).
    /// Used by `SuiteCoreMetadataAdapter.searchViaInline`.
    public var metadataResult: MetadataResult  // source .musicBrainz, externalId id, year = first 4 chars of (bestRelease(nil)?.date ?? firstReleaseDate) as Int, releaseDate same string, artist, album = bestRelease(nil)?.title, trackNumber = bestRelease(nil)?.trackNumberValue, confidence = Double(score)/100
}

public enum MusicBrainzLookupError: Error, Sendable, Equatable, LocalizedError {
    case emptyQuery
    case invalidURL(String)
    case rateLimited(serverMessage: String?)          // HTTP 503
    case badRequest(serverMessage: String?)           // HTTP 400 (bad Lucene query)
    case httpStatus(statusCode: Int, bodySnippet: String)
    case transport(String)                            // URLError etc., no HTTP response
    case malformedResponse(String)                    // 2xx but undecodable
    // errorDescription: "Enter a title to search MusicBrainz." / "The MusicBrainz search URL could not be formed: …" /
    // "MusicBrainz is rate-limiting requests (HTTP 503). Wait a moment and try again." (+ ": <serverMessage>") /
    // "MusicBrainz rejected the query (HTTP 400): …" / "MusicBrainz returned HTTP \(code): \(snippet)" /
    // "Could not reach MusicBrainz: …" / "MusicBrainz returned a response that could not be read: …"
}

public struct MusicBrainzLookupService: Sendable {
    private let httpClient: any MetadataHTTPClient
    private let throttle: MusicBrainzRequestThrottle
    public init(httpClient: any MetadataHTTPClient = URLSessionMetadataHTTPClient(),
                throttle: MusicBrainzRequestThrottle = .shared)

    /// Search MusicBrainz recordings by title (+ optional artist).
    /// Trims both; blank title → `.emptyQuery` (no request); blank artist → no `artist:` clause.
    /// Waits for the throttle, sends via the seam, maps status → error, parses 2xx.
    /// Cancellation (Task cancel during throttle sleep or transfer) rethrows `CancellationError`.
    public func searchRecordings(title: String, artist: String?) async throws -> [MusicBrainzRecordingMatch]

    /// Pure decode of a `/ws/2/recording?…&fmt=json` body into matches, in server order.
    /// Recordings with no usable title are dropped; every string is passed through
    /// `MetadataSanitizer.sanitizeSingleLine` and trimmed (F-006: untrusted input).
    /// - Throws: `.malformedResponse` if the body is not the MusicBrainz envelope.
    public static func parseRecordingSearch(_ data: Data) throws -> [MusicBrainzRecordingMatch]
}
```
`searchRecordings` body (verbatim intent):
```swift
let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
guard !trimmedTitle.isEmpty else { throw MusicBrainzLookupError.emptyQuery }
let trimmedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
let effectiveArtist = (trimmedArtist?.isEmpty ?? true) ? nil : trimmedArtist
guard let request = MusicBrainzClient.buildRecordingSearchRequest(title: trimmedTitle, artist: effectiveArtist) else {
    throw MusicBrainzLookupError.invalidURL(MusicBrainzClient.buildRecordingSearchURL(title: trimmedTitle, artist: effectiveArtist))
}
try await throttle.waitForTurn()
let result: (Data, HTTPURLResponse)
do {
    result = try await httpClient.data(for: request)
} catch is CancellationError {
    throw CancellationError()
} catch let urlError as URLError where urlError.code == .cancelled {
    throw CancellationError()
} catch {
    throw MusicBrainzLookupError.transport(error.localizedDescription)
}
let (data, response) = result
switch response.statusCode {
case 200...299: return try Self.parseRecordingSearch(data)
case 503: throw MusicBrainzLookupError.rateLimited(serverMessage: Self.serverErrorMessage(from: data))
case 400: throw MusicBrainzLookupError.badRequest(serverMessage: Self.serverErrorMessage(from: data))
default: throw MusicBrainzLookupError.httpStatus(statusCode: response.statusCode, bodySnippet: Self.bodySnippet(data))
}
```
`serverErrorMessage(from:)` decodes `private struct ErrorEnvelope: Decodable { let error: String; let help: String? }` → `sanitizeSingleLine(error)`, else `nil`. `bodySnippet` = first 200 characters, `sanitizeSingleLine`d.

Wire-format decode (private, explicit `CodingKeys` for kebab-case; everything optional except `id`):
`RecordingSearchEnvelope { recordings: [WireRecording]? }`; `WireRecording { id, score: Int?, title: String?, length: Int?, disambiguation: String?, artistCredit ("artist-credit"): [WireArtistCredit]?, firstReleaseDate ("first-release-date"): String?, releases: [WireRelease]? }`; `WireArtistCredit { name: String?, joinphrase: String?, artist: WireArtist? }`; `WireArtist { id: String, name: String? }`; `WireRelease { id, title: String?, status: String?, date: String?, country: String?, artistCredit: [WireArtistCredit]?, releaseGroup ("release-group"): WireReleaseGroup?, trackCount ("track-count"): Int?, media: [WireMedium]? }`; `WireReleaseGroup { id, title: String?, primaryType ("primary-type"): String?, secondaryTypes ("secondary-types"): [String]? }`; `WireMedium { position: Int?, format: String?, track: [WireTrack]?, trackCount ("track-count"): Int? }`; `WireTrack { id, number: String?, title: String?, length: Int? }`. Mapping: `artist = credits.map { $0.name + $0.joinPhrase }.joined()`; release fields from `media?.first` (the only medium MusicBrainz includes) and `track?.first`; `score ?? 0`.

### Tag mapping — `MusicBrainzTagMapping.swift`
```swift
public enum MusicBrainzTagMapping {
    /// Case-insensitive lookup of a tag value (first match, trimmed, nil if blank).
    public static func value(forKey key: String, in tags: [MediaTag]) -> String?

    /// Seed for the lookup sheet: title/artist/album from the file's existing tags
    /// (`title`, `artist` → `album_artist`, `album`, any key spelling), falling back to
    /// `FilenameParser.parse(filename:)` — its `title` always, its `artist` only when
    /// it recognised the `Artist - Title` music pattern. `mediaType` is `.music`.
    public static func seedQuery(tags: [MediaTag], filename: String) -> MetadataSearchQuery

    /// Stable order: score descending, then |lengthSeconds − fileDurationSeconds|
    /// ascending (unknown length last), then server order. Unchanged when
    /// `fileDurationSeconds` is nil or ≤ 0.
    public static func ranked(_ matches: [MusicBrainzRecordingMatch], fileDurationSeconds: Double?) -> [MusicBrainzRecordingMatch]

    /// Returns `tags` with the match's fields applied. For each canonical key with a
    /// non-empty value — `title`, `artist`, `album`, `album_artist`, `date`
    /// (release.date ?? firstReleaseDate), `track` (numeric only; also matches an
    /// existing `tracknumber`), `disc` (only when mediumPosition > 1) and, when
    /// `includeIdentifiers`, `musicbrainz_trackid` (recording MBID),
    /// `musicbrainz_albumid`, `musicbrainz_releasegroupid`, `musicbrainz_artistid`
    /// (IDs joined with "; ", the house convention from
    /// `MediaServerTagging.buildFFmpegMetadataArguments`) — the FIRST existing tag whose
    /// key matches case-insensitively is replaced in place (same `id`, same key
    /// spelling), otherwise a `MediaTag(key: canonical, value:)` is appended in that
    /// order. Tags with no corresponding field are untouched; nothing is deleted.
    public static func applying(_ match: MusicBrainzRecordingMatch,
                                release: MusicBrainzRecordingMatch.Release?,
                                to tags: [MediaTag],
                                includeIdentifiers: Bool) -> [MediaTag]
}
```
Doc-comment honesty on identifiers: "Written with `-metadata` like any other key; whether a container keeps non-standard keys is up to ffmpeg's muxer (FLAC/Ogg store them as Vorbis comments; ffmpeg's MP4 muxer drops keys it does not recognise unless `-movflags use_metadata_tags` is passed, which `MetadataTagEditor.buildWriteArguments` does not)."

### Adapter wiring — `SuiteCoreMetadataAdapter.swift`
- Add `public let musicBrainzLookup: MusicBrainzLookupService`; init becomes `public init(backend: SuiteCoreMetadataBackend = .automatic, musicBrainzLookup: MusicBrainzLookupService = MusicBrainzLookupService())` (existing `SuiteCoreMetadataAdapter(backend:)` call sites keep compiling).
- `searchViaInline`: 
```swift
switch source {
case .musicBrainz:
    return try await musicBrainzLookup.searchRecordings(title: query.title, artist: query.artist).map(\.metadataResult)
default:
    throw SuiteCoreBridgeError.notImplemented("Inline metadata search for \(source.displayName)")
}
```
- Rewrite doc L179-210: MusicBrainz is now a real inline lookup through `MusicBrainzLookupService` (keyless; `MetadataHTTPClient` seam; `MusicBrainzRequestThrottle.shared`); every other source still throws `.notImplemented` because it requires an API key this build does not manage — never `[]`. Delete the "there is no `URLSession` anywhere in that directory" sentence and the "strategy chooses the latter" sentence (replace with: "#205 chose a native-Swift backend for the keyless MusicBrainz path; keyed providers remain follow-ups"). Header L8-11: add "`MetadataTagEditorView`'s lookup sheet calls `MusicBrainzLookupService` directly because it needs `MusicBrainzRecordingMatch` (releases, MBIDs), which `MetadataResult` cannot carry."

### Sheet — `MusicBrainzLookupSheet.swift` (module `MeedyaConverterCore`)
```swift
struct MusicBrainzLookupSheet: View {
    let preferredAlbum: String?
    let fileDurationSeconds: Double?
    let onApply: @MainActor (MusicBrainzRecordingMatch, MusicBrainzRecordingMatch.Release?, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String
    @State private var matches: [MusicBrainzRecordingMatch] = []
    @State private var selectedMatchID: String?
    @State private var isSearching = false
    @State private var statusMessage: String?
    @State private var includeIdentifiers = true
    @State private var searchTask: Task<Void, Never>?
    private let service = MusicBrainzLookupService()

    init(initialTitle: String, initialArtist: String, preferredAlbum: String?, fileDurationSeconds: Double?,
         onApply: @escaping @MainActor (MusicBrainzRecordingMatch, MusicBrainzRecordingMatch.Release?, Bool) -> Void) {
        _title = State(initialValue: initialTitle); _artist = State(initialValue: initialArtist); …
    }
}
```
Body: `Text("Look Up on MusicBrainz").font(.headline)`; `Form { TextField("Title", text: $title); TextField("Artist", text: $artist) }`; HStack: `Button("Search", action: search).keyboardShortcut(.defaultAction).disabled(isSearching || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)`, and while `isSearching` a `ProgressView().controlSize(.small)` + `Button("Cancel") { searchTask?.cancel() }`; `List(selection: $selectedMatchID) { ForEach(matches) { row } }` — row: `Text("\(m.title) — \(m.artist.isEmpty ? "Unknown artist" : m.artist)")` + caption joining (with " · ", dropping nils) `bestRelease?.title`, `bestRelease?.date ?? m.firstReleaseDate`, length as `m:ss`, `m.disambiguation`, `"score \(m.score)"` where `bestRelease = m.bestRelease(preferringAlbumTitled: preferredAlbum)`; `statusMessage` as `.caption` (red when it `hasPrefix("Error")`, mirroring `writeStatusColor(for:)` at `MetadataTagEditorView.swift:371-375`); `Toggle("Include MusicBrainz IDs as tags", isOn: $includeIdentifiers)`; footer `Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)` and `Button("Apply") { … }.disabled(selectedMatchID == nil)` → `onApply(match, match.bestRelease(preferringAlbumTitled: preferredAlbum), includeIdentifiers); dismiss()`. `.onDisappear { searchTask?.cancel() }`. `.padding(20).frame(minWidth: 560, minHeight: 440)`.

```swift
private func search() {
    guard !isSearching else { return }
    let queryTitle = title
    let queryArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
    isSearching = true; statusMessage = nil; matches = []; selectedMatchID = nil
    searchTask = Task {
        do {
            let found = try await service.searchRecordings(title: queryTitle, artist: queryArtist.isEmpty ? nil : queryArtist)
            guard !Task.isCancelled else { return }
            matches = MusicBrainzTagMapping.ranked(found, fileDurationSeconds: fileDurationSeconds)
            selectedMatchID = matches.first?.id
            statusMessage = matches.isEmpty ? "No MusicBrainz recordings matched." : "\(matches.count) match\(matches.count == 1 ? "" : "es")."
        } catch is CancellationError {
            statusMessage = "Cancelled."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
        isSearching = false
    }
}
```
Concurrency: the sheet is a `View` struct → main-actor; the plain `Task { }` inherits it (house statement at `MetadataTagEditorView.swift:610-613`), so `@State` writes are direct. `service.searchRecordings` is a nonisolated `async` method on a `Sendable` struct, so the throttle wait and the `URLSession` transfer run off the main actor — the `CloudStorageView.swift:655-662` rule ("genuinely async, no blocking syscalls, so no `Task.detached`") applies. No `self` crosses an isolation boundary. Cancel = `searchTask?.cancel()` → throttle `Task.sleep` or `URLSession` throws → normalised to `CancellationError` → "Cancelled.".

### Editor wiring — `MetadataTagEditorView.swift`
1. Header doc L14-21: add "…a 'Look Up…' action that searches MusicBrainz recordings from the file's title/artist (`MusicBrainzLookupSheet` → `MusicBrainzLookupService`) and applies a chosen match to the tag table via `MusicBrainzTagMapping.applying` (#205);…".
2. State after L58: `@State private var showingLookup = false`.
3. `controlsBar`: after the Clear All button (L193) and before `Spacer()` (L195) insert
```swift
Divider().frame(height: 16)
Button { showingLookup = true } label: { Label("Look Up…", systemImage: "magnifyingglass") }
    .disabled(viewModel.selectedFile == nil || isWriting)
    .accessibilityLabel("Look up metadata on MusicBrainz")
```
4. In `body`, attach the new sheet to `controlsBar` (a different node from the existing `.sheet` at L112, so two sheets never share one presenter): replace L98 `controlsBar` with
```swift
controlsBar
    .sheet(isPresented: $showingLookup) {
        let seed = MusicBrainzTagMapping.seedQuery(tags: tags, filename: viewModel.selectedFile?.fileName ?? "")
        MusicBrainzLookupSheet(
            initialTitle: seed.title,
            initialArtist: seed.artist ?? "",
            preferredAlbum: seed.album,
            fileDurationSeconds: viewModel.selectedFile?.duration,
            onApply: applyLookupMatch
        )
    }
```
5. New action (in `// MARK: - Actions`):
```swift
/// Merge a chosen MusicBrainz match into the tag table (pure mapping in
/// `MusicBrainzTagMapping.applying`); the user still reviews and writes via
/// "Write Tags…". Nothing touches the file here.
private func applyLookupMatch(_ match: MusicBrainzRecordingMatch,
                              release: MusicBrainzRecordingMatch.Release?,
                              includeIdentifiers: Bool) {
    tags = MusicBrainzTagMapping.applying(match, release: release, to: tags, includeIdentifiers: includeIdentifiers)
    selectedTagID = nil
    viewModel.appendLog(.info, "MusicBrainz match applied: \(match.artist) – \(match.title) (\(match.id))", category: .metadata)
}
```
6. `emptyTagsView` text L487-490 → "Add tags manually, use a template, click a common tag suggestion below, or use Look Up… to fetch them from MusicBrainz."

### `MetadataLookup.swift` doc edits
- L296: "Builds MusicBrainz API request URLs for music metadata lookup." → append "Execution, throttling and JSON parsing live in `MusicBrainzLookupService` (#205); this type remains a pure URL/request builder."
- L309-311: keep "this type parses no response at all" and add: "`MusicBrainzLookupService.parseRecordingSearch` decodes only recording / artist-credit / release / release-group / media / track fields — no relationships — so the SEARCH-752 `target` change still does not apply."

### CHANGELOG.md
Insert as the first bullet under `## [Unreleased]` → `### Added` (before `- **Video stabilization**`):
```
- **MusicBrainz metadata lookup** in the Metadata Tag Editor: "Look Up…" searches
  MusicBrainz recordings (keyless; the required User-Agent and a 1-request-per-second
  throttle are built in) from the file's title/artist, lists candidate matches ranked
  by score and closeness to the file's duration, and applies the chosen match's
  title/artist/album/date/track (and MusicBrainz IDs) to the tag table for the
  existing "Write Tags…" path (#205, follows #493).
```

## Tests — `Tests/ConverterEngineTests/MusicBrainzLookupServiceTests.swift`
`import Foundation`, `import XCTest`, `import ConverterEngine` (no `@testable`). House header. Types (all module-unique, `MusicBrainz`-prefixed):
- `final class MusicBrainzMockHTTPClient: MetadataHTTPClient, @unchecked Sendable` — `private let lock = NSLock()`; FIFO `responders: [(URLRequest) throws -> (Data, HTTPURLResponse)]`; `requests: [URLRequest]`; `requestStartTimes: [ContinuousClock.Instant]`; `var delay: Duration = .zero` (getter/setter under `lock.withLock`); `enqueue(status: Int, body: String, contentType: String = "application/json")` builds `HTTPURLResponse(url: request.url!, statusCode:, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!`; `enqueueFailure(_ error: Error)`; `struct Underscripted: Error` thrown when the queue is empty. `data(for:)`: record request + `ContinuousClock.now` under `lock.withLock`; if `delay > .zero` → `try await Task.sleep(for: delay)` (**`try`, not `try?`** — the cancellation test needs the throw); pop responder under `lock.withLock`; run it. **Every lock use is `lock.withLock { }`; never `lock.lock()/unlock()`** (Swift 6 rejects those in async; invisible to `-parse`).
- `enum MusicBrainzFixtures` with `static let` JSON strings: `recordingSearchBohemian` (the captured two-recording response above with `aliases` arrays removed — keep real IDs/values; scratch copy at `/private/tmp/claude-501/…/scratchpad/mb_recording_search.json` for this session only), `recordingSearchUnderPressure` (synthetic, shape-conformant: score 93, `length` 248000, two artist credits `Queen` + joinphrase `" & "` + `David Bowie`, `first-release-date` `"1981-10-26"`, releases: `Hot Space` status `Official`, primary-type `Album`, date `"1982-05-21"`, medium position 1 format `12" Vinyl` track number `"B5"`, with `artist-credit`; and `Greatest Hits II` status `Official`, secondary-types `["Compilation"]`, date `"1991-10-28"`, medium position 1 track number `"4"`, track-count 17, NO `artist-credit`), `recordingSearchMinimal` (`{"recordings":[{"id":"aaaaaaaa-0000-4000-8000-000000000001","title":"Solo"},{"id":"aaaaaaaa-0000-4000-8000-000000000002","score":50}]}`), `recordingSearchMultiDisc` (one release, medium position 2, track `"3"`), `recordingSearchEmpty` (`{"created":"…","count":0,"offset":0,"recordings":[]}`), `errorBody400` (captured verbatim), `errorBody503` (`{"error":"Your requests are exceeding the allowable rate limit. Please see https://musicbrainz.org/doc/XML_Web_Service/Rate_Limiting for more information.","help":"For usage, please see: https://musicbrainz.org/development/mmd"}` — same envelope as the captured 400), `notJSON` (`"<html><body>Service Unavailable</body></html>"`).
- `final class MusicBrainzLookupServiceTests: XCTestCase` with `makeService(client:) -> MusicBrainzLookupService` using `MusicBrainzRequestThrottle(minimumInterval: .zero)` (**never `.shared` in tests** — `--parallel`) and `tag(_ key: String, _ value: String) -> MediaTag`.

Cases:
1. `test_parseRecordingSearch_decodesIDTitleScoreAndDisambiguation` (Bohemian: 2 matches; ids/scores/disambiguation as captured).
2. `test_parseRecordingSearch_joinsArtistCreditsWithJoinPhrase` (Under Pressure → `"Queen & David Bowie"`, `artistIDs.count == 2`).
3. `test_parseRecordingSearch_extractsReleaseAlbumDateTrackAndMBIDs` (Bohemian[1]: release `Opera Omnia`, status `Bootleg`, date `"1992"`, country `IT`, releaseGroupID `22655e64-…`, trackNumber `"1"`, mediumPosition 2, mediumFormat `CD`, mediumTrackCount 21, albumArtist `Queen`).
4. `test_parseRecordingSearch_nonNumericTrackNumberHasNilValue` (`"B5"` → `trackNumberValue == nil`, `trackNumber == "B5"`).
5. `test_parseRecordingSearch_missingOptionalFieldsDecodeAndTitlelessRecordingIsDropped` (Minimal → 1 match, `artist == ""`, `lengthMilliseconds == nil`, `releases == []`, score 0).
6. `test_parseRecordingSearch_emptyRecordingsReturnsEmpty`.
7. `test_parseRecordingSearch_notJSONThrowsMalformedResponse`.
8. `test_parseRecordingSearch_preservesServerOrder`.
9. `test_parseRecordingSearch_lengthSecondsFromMilliseconds` (130400 → 130.4).
10. `test_parseRecordingSearch_sanitisesControlCharacters` (title with `\u{0000}` and `\u{202E}` → stripped via `sanitizeSingleLine`).
11. `test_bestRelease_prefersAlbumTitleMatchThenOfficialPlainAlbumThenFirst` (Under Pressure: `preferringAlbumTitled: "greatest hits ii"` → Greatest Hits II; `nil` → Hot Space (Official + Album, no secondary types); Bohemian[0] → The Freddie Mercury Tribute (first, no status)).
12. `test_metadataResultBridge_mapsFieldsAndConfidence` (source `.musicBrainz`, externalId, year 1982, album `Hot Space`, trackNumber nil, confidence 0.93 ±0.001).
13. `test_buildRecordingSearchRequest_setsHeadersTimeoutAndURL` (User-Agent == `MusicBrainzClient.userAgent`, Accept `application/json`, timeout 15, `url.absoluteString == buildRecordingSearchURL(...)`).
14. `test_searchRecordings_sendsExactlyOneRequestWithBuiltURLAndHeaders`.
15. `test_searchRecordings_200ReturnsParsedMatches`.
16. `test_searchRecordings_503ThrowsRateLimitedWithServerMessage` (`XCTAssertEqual(error, .rateLimited(serverMessage: "Your requests are exceeding…"))`).
17. `test_searchRecordings_400ThrowsBadRequestWithServerMessage` (captured message).
18. `test_searchRecordings_otherStatusThrowsHTTPStatusWithSnippet` (500 + notJSON → snippet non-empty, single-line).
19. `test_searchRecordings_transportErrorThrowsTransport` (`enqueueFailure(URLError(.notConnectedToInternet))`).
20. `test_searchRecordings_malformedBodyThrowsMalformedResponse` (200 + notJSON).
21. `test_searchRecordings_blankTitleThrowsEmptyQueryWithoutRequest` (`"   "` → `.emptyQuery`, `requests.isEmpty`).
22. `test_searchRecordings_trimsTitleAndDropsBlankArtistClause` (`"  Bohemian Rhapsody "`, artist `" "` → URL has no `artist%3A`).
23. `test_searchRecordings_cancellationPropagatesAsCancellationError` (delay 5 s; `Task { try await … }`; bounded wait ≤2 s until `requests.count == 1`; `task.cancel()`; expect `CancellationError`).
24. `test_throttle_spacesSequentialRequestsByMinimumInterval` (interval 150 ms; 3 sequential searches; `requestStartTimes[0].duration(to: requestStartTimes[2]) >= .milliseconds(300)` — one-sided lower bound only).
25. `test_throttle_spacesConcurrentRequestsSharingOneThrottle` (`async let` ×2 on one throttle; start gap ≥ interval).
26. `test_throttle_zeroIntervalDoesNotDelay` (just asserts both calls return; no timing assertion).
27. `test_seedQuery_prefersExistingTagsCaseInsensitively` (`TITLE`/`ARTIST`/`ALBUM` tags + filename `Queen - Bohemian Rhapsody.flac` → title/artist/album from tags).
28. `test_seedQuery_fallsBackToFilenameParserMusicPattern` (no tags; `Queen - Bohemian Rhapsody.flac` → artist Queen, title Bohemian Rhapsody).
29. `test_seedQuery_fallsBackToCleanedFilenameTitleWithoutArtist` (`bohemian_rhapsody.flac` → title `bohemian rhapsody`, artist nil).
30. `test_ranked_ordersByScoreThenClosenessToFileDuration` (three matches: scores 100/100/95 with lengths 130.4/338.3/354.0 s, duration 355 → order: 338.3, 130.4, 354.0 — score first) and `test_ranked_isIdentityWithoutDuration`.
31. `test_applying_replacesExistingKeysInPlacePreservingSpellingAndID` (`TITLE`/`ARTIST` tags keep key spelling and `id`).
32. `test_applying_appendsMissingCanonicalKeysInOrder` and `test_applying_matchesTracknumberAliasAndSkipsNonNumericTrack`.
33. `test_applying_identifiersToggle` (on → `musicbrainz_trackid`/`albumid`/`releasegroupid`/`artistid` present, artistid joined with `"; "`; off → absent) and `test_applying_writesDiscOnlyForMediumPositionAboveOne` (MultiDisc → `disc == "2"`; Hot Space → no `disc`).
34. `test_applying_leavesUnrelatedTagsUntouched_thenBuildWriteArgumentsEmitsPairs` (`comment`/`encoder` unchanged; `MetadataTagEditor.buildWriteArguments` output contains `-metadata` `title=Under Pressure` and `artist=Queen & David Bowie`).

`ConverterEngineTests+SuiteCore.swift` edits:
- L151-182 → `test_suiteCoreMetadataAdapter_inlineMusicBrainzRunsARealLookup() async throws`: `MusicBrainzMockHTTPClient` + `recordingSearchBohemian`, `SuiteCoreMetadataAdapter(backend: .inlineOnly, musicBrainzLookup: service)`, `.music` query → `client.requests.count == 1`, 2 results, `source == .musicBrainz`, `externalId == "46fe768c-7b38-4147-9f02-815b9f0759e2"`, `artist == "Queen"`. Doc: "#205 replaced the always-throwing inline path for MusicBrainz with a real lookup; injected mock, no network."
- L184-199 → `test_suiteCoreMetadataAdapter_everyOtherInlineSourceThrowsNotImplemented`: `for source in MetadataSource.allCases where source != .musicBrainz`. Doc: keyed providers still throw rather than fake `[]`.

## Verification gates
```
swift build --target ConverterEngine
swift build 2>&1 | grep "error:" | grep -v "PreviewsMacros\|Preview(_:body:)\|external macro\|emit-module"   # must be empty
swiftc -parse Tests/ConverterEngineTests/MusicBrainzLookupServiceTests.swift
swiftc -parse "Tests/ConverterEngineTests/ConverterEngineTests+SuiteCore.swift"
grep -n "lock.lock()\|lock.unlock()" Tests/ConverterEngineTests/MusicBrainzLookupServiceTests.swift   # must be empty
grep -rhn "^final class \|^struct \|^enum \|^actor " Tests/ConverterEngineTests | sed 's/^[0-9]*://' | sort | uniq -d   # must be empty (duplicate top-level names)
```
Then commit, push, and watch CI to green (`swift test --parallel` on `macos-15` is the only place the tests run; `swift build --build-tests` fails locally with `no such module 'XCTest'`).

## Risks
1. **False-comment / dead-code hygiene.** Four now-false statements are rewritten in code: `SuiteCoreMetadataAdapter.swift:190-200`, its header L8-11, `ConverterEngineTests+SuiteCore.swift:157-159`, and the `MetadataTagEditorView` header L14-21 (which would otherwise omit a feature). Every new public symbol has a caller: seam ← service; service ← sheet and adapter; `parseRecordingSearch` ← service; `buildRecordingSearchRequest` ← service; `bestRelease`/`ranked`/`seedQuery`/`applying`/`value(forKey:)` ← sheet/editor; `metadataResult` ← adapter; `requestTimeoutSeconds` ← request builder. `buildReleaseSearchURL`/`buildRecordingLookupURL` stay as they were (pre-existing builders with tests — kept per the #493 decision).
2. **Rate limit.** One shared 1.1 s actor throttle per process; a 503 is still surfaced (never retried automatically — retrying would compound the limit). The User-Agent is the existing `MusicBrainzClient.userAgent` (already asserted by `test_musicBrainzClient_userAgent`).
3. **Live network is unverifiable in CI**; only the seam-level behaviour is. The fixtures are real captured JSON, so a schema drift on MusicBrainz's side would first show up as `.malformedResponse` in the sheet — surfaced, never a crash — because all decode fields except `id` are optional.
4. **Docs that become false when this lands** (plan does not edit them; fix in the same PR or immediately after): `docs/distribution/rc4-known-limitations.md:59-60` ("Media metadata lookup / auto-tagging … is not in this release"), `README.md:121` ("Not implemented at all … no `URLSession` … no lookup control anywhere in the UI") and `README.md:365` (Phase 15 status), `docs/Home.md:108-112`, `docs/FAQ.md:216`, `docs/MeedyaSuite-core-integration.md:30-34` ("contains no `URLSession` … nothing in the app calls them").
5. **Swift 6 isolation.** `onApply` is declared `@MainActor` so passing `applyLookupMatch` (a method of a main-actor `View`) compiles; the sheet's `Task { }` inherits main-actor isolation; the service is `Sendable` with a nonisolated async method. If CI's compiler objects to `URLSessionMetadataHTTPClient: Sendable`, switch to `@unchecked Sendable` with the `CloudUploadExecutor.swift:76-83` rationale — do NOT weaken the protocol's `Sendable` requirement.
6. **Two `.sheet`s on one view.** The lookup sheet is attached to `controlsBar`, not chained after the existing `.sheet` on the `VStack`, so each presenter owns one sheet.
7. **Tag-key spelling / container behaviour.** In-place replacement keeps `TITLE` on FLAC files; ffmpeg's `-metadata` matches keys case-insensitively so no duplicates are written. MBID keys survive on FLAC/Ogg/ID3 (as TXXX) but ffmpeg's MP4 muxer drops unknown keys without `-movflags use_metadata_tags` — stated in the doc comment; follow-up to add the flag in `buildWriteArguments` for `.mp4/.m4a` outputs.
8. **Adapter behaviour change.** `SuiteCoreMetadataAdapter.search(source: .musicBrainz)` on `.inlineOnly`/`.automatic`-without-SUITE_CORE now performs a network request instead of throwing. No app code calls it today (verified), so no runtime path changes silently; the two pinned tests are rewritten to inject the mock.
9. **`MetadataSearchQuery` is not `Equatable`** — seed tests assert fields individually.
10. **Timing tests** are one-sided lower bounds (≥ interval); if CI flakes, raise the interval, not the assertion. Test 23's wait loop is bounded (≤2 s) so a regression cannot hang the run.
11. **Sandboxed App Store build**: outbound HTTP is allowed (`com.apple.security.network.client` in both entitlement files) — lookup works in both distributions; no parity claim needed.
12. **Follow-ups (out of scope, noted so nobody mistakes them for done):** executing `buildReleaseSearchURL` (album-first lookup), `buildRecordingLookupURL` (needed to turn `FingerprintMatch.recordingId` from `AudioFingerprinter.swift:49` into tags), `AudioCDReader.buildMusicBrainzLookupURL` (disc-ID lookup for the CD ripper), and keyed providers (TMDB/TheTVDB/OMDb/Discogs/FanArt.tv/OpenSubtitles) which additionally need an API-key UI — the `MetadataHTTPClient` seam is provider-agnostic on purpose.
13. **Concurrent sibling edits.** Anchors verified at `20d1534`; the CHANGELOG is anchored by text. Re-verify `MetadataTagEditorView.swift` L159-210 and `SuiteCoreMetadataAdapter.swift` L179-210 before editing.