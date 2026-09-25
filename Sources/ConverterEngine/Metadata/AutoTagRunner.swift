// ============================================================================
// MeedyaConverter — AutoTagRunner (Issue #508, commit 4/10: films)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The piece that actually LOOKS A FILE UP for the auto-tag feature: it
// decides whether a file is a film, a song or neither, searches TMDB for a
// film, scores what comes back, and works out which tags are missing from the
// file. Everything it needs arrives in one `AutoTagRequest` (built per job by
// `AutoTagSettingsSource.currentRequest()`, commit 3).
//
// ⚠️ WHAT THIS COMMIT DOES NOT DO YET — read before assuming anything runs:
//   * NOTHING CALLS `AutoTagRunner.run` YET. `EncodingEngine` calling it after
//     the source probe is #508 commit 6. Until then this file is exercised
//     only by `AutoTagRunnerTests`.
//   * MUSIC IS NOT LOOKED UP. A music file is recognised and planned
//     (`AutoTagPlan.music`), but `run` returns `.skipped` with
//     `Reasons.musicNotBuiltYet` for it. The MusicBrainz half is commit 5.
//   * TV EPISODES ARE NOT LOOKED UP. A file whose name matches
//     `FilenameParser`'s "S01E02" pattern is skipped (`Reasons.tvEpisode`).
//   * NO NFO, NO RENAMING, NO ARTWORK. The NFO writer is commit 7; renaming
//     and artwork are separate follow-up issues (see the plan).
//   See `.claude/plans/autotag-encode-plan.md`.
//
// THREE TRAPS THIS FILE IS BUILT AROUND
//
// 1. Every TMDB result says it is 50% certain. `TMDBLookupService
//    .parseSearchResults` never sets `confidence`, so it keeps
//    `MetadataResult`'s default of 0.5 — below the 0.7 threshold. Calling
//    `AutoTagger.meetsThreshold` on raw results would therefore NEVER accept
//    anything, and the feature would silently never tag a single file. This
//    runner scores every candidate for real with `DiscIdentifier.rank`
//    (running time, title, year) and COPIES that score into `confidence`
//    before asking `meetsThreshold`. `AutoTagRunnerTests` pins both halves.
//
// 2. Cover art reads as video. ffprobe reports an MP3's embedded picture as
//    a video stream, so `hasVideo` is true for a tagged song. Deciding "is
//    this a film?" from `hasVideo` would send songs to TMDB. The decision
//    uses `looksLikeVideoContent` (moving video in a container that can hold
//    it), and "is this music?" is `hasAudio && !looksLikeVideoContent` —
//    never `isAudioOnly`, which says NO to that same MP3.
//
// 3. A lookup must never hold up, or wrongly cancel, an encode. `run` races
//    the lookup against a deadline and against the user pressing Stop; the
//    first to finish wins and the others are cancelled. Only a genuine stop
//    or cancellation is thrown (as `CancellationError`); everything else —
//    no key, no network, a rejected key, a slow server — comes back as an
//    outcome, so the caller (the engine, from #508 commit 6) can log it and
//    carry on encoding without the extra tags.
//
// WHY A FILE WITH NO RUNNING TIME IS NEVER TAGGED. Running time carries half
// the score's weight and is the only signal that tells two films with the
// same name apart. Without it the best possible score is 0.5 (title 0.35 +
// year 0.15), which can never reach 0.7 anyway — so the runner says so up
// front and makes no request at all, rather than spending TMDB calls on a
// match it could never accept. The owner's decision (plan, decision 6):
// conservative.
// ============================================================================

import Foundation

// MARK: - AutoTagPlan

/// What the runner intends to do with a file, decided from the probe alone
/// (no network). See `AutoTagRunner.plan(for:jobTags:)`.
public enum AutoTagPlan: Sendable, Equatable {
    /// Look the file up as a film on TMDB, searching for this.
    case film(MetadataSearchQuery)
    /// The file is music. Planned here so the decision is testable today;
    /// the MusicBrainz lookup itself arrives in #508 commit 5, so `run`
    /// currently reports this as skipped.
    case music(MetadataSearchQuery)
    /// Nothing will be looked up, for the plain-English `reason` given.
    case skip(reason: String)
}

// MARK: - AutoTagMatchSummary

/// A short, comparable description of one scored candidate — enough for an
/// Activity Log line such as "Best match 'X (1999)' was 52% certain".
public struct AutoTagMatchSummary: Sendable, Equatable {
    /// The candidate's title as the provider gave it.
    public let title: String
    /// The candidate's release year, when the provider gave one.
    public let year: Int?
    /// The provider's own id for it (a TMDB film id, for films).
    public let externalId: String
    /// The runner's score for it, 0...1 — `DiscIdentifier.rank`'s, NOT the
    /// 0.5 every raw TMDB result carries.
    public let confidence: Double

    public init(title: String, year: Int?, externalId: String, confidence: Double) {
        self.title = title
        self.year = year
        self.externalId = externalId
        self.confidence = confidence
    }

    init(_ result: MetadataResult) {
        self.init(
            title: result.title,
            year: result.year,
            externalId: result.externalId,
            confidence: result.confidence
        )
    }
}

// MARK: - AutoTagOutcome

/// What happened when a file was looked up. Only `.applied` means tags will
/// be added; no other case adds any.
public enum AutoTagOutcome: Sendable, Equatable {
    /// A confident, unambiguous match, and the file was missing at least one
    /// tag it supplied. The report's `tagsToAdd` lists them.
    case applied
    /// A confident, unambiguous match, but the file (or the job) already had
    /// every tag it would have supplied, so there is nothing to add.
    case matchedNothingToAdd
    /// The best candidate scored below the threshold (`needed`, 0...1).
    case belowThreshold(best: AutoTagMatchSummary, needed: Double)
    /// Two DIFFERENT films both passed the threshold and scored within
    /// `AutoTagRunner.ambiguityMargin` of each other, so neither is trusted.
    case ambiguous(first: AutoTagMatchSummary, second: AutoTagMatchSummary)
    /// The provider returned no candidates at all for this search.
    case noMatch(searchedFor: MetadataSearchQuery)
    /// Nothing was looked up, for a reason that is expected rather than a
    /// fault: auto-tagging off, no key saved, a TV episode, music (not built
    /// yet), no running time, and so on. No request is ever sent for a
    /// skipped file, and the report's `provider` is always `nil`.
    case skipped(reason: String)
    /// The lookup was attempted and went wrong: unreachable, key rejected,
    /// rate-limited, a server error, or no answer before the deadline.
    /// `reason` has been passed through the TMDB key redaction, which
    /// replaces every exact occurrence of the key, so the key cannot appear
    /// in it as written.
    case failed(reason: String)
}

// MARK: - AutoTagLookupReport

/// Everything the encode (and the Activity Log) needs to know about one
/// file's lookup.
public struct AutoTagLookupReport: Sendable {

    /// What happened.
    public let outcome: AutoTagOutcome

    /// Which service was asked, or `nil` when nothing was asked. Always
    /// `nil` for `.skipped`, because no skip ever sends a request.
    public let provider: MetadataSource?

    /// Tags the file lacks that the match supplies. Non-empty ONLY for
    /// `.applied`. Never includes a key the source file (with a non-blank
    /// value) or the job already carries, matched case-insensitively and
    /// through aliases such as `date`/`year` — see `AutoTagMerge`.
    public let tagsToAdd: [MediaTag]

    /// Tags the match WOULD have replaced but which were kept as the file
    /// (or job) had them. For the Activity Log's "Kept the file's own: …".
    /// Empty unless a match was accepted.
    public let keptExisting: [MediaTag]

    /// The accepted film, with `confidence` set to the runner's real score.
    /// Set for `.applied` and `.matchedNothingToAdd` (the NFO writer in #508
    /// commit 7 needs it even when no tag was missing); `nil` otherwise.
    public let identifiedFilm: MetadataResult?

    public init(
        outcome: AutoTagOutcome,
        provider: MetadataSource?,
        tagsToAdd: [MediaTag] = [],
        keptExisting: [MediaTag] = [],
        identifiedFilm: MetadataResult? = nil
    ) {
        self.outcome = outcome
        self.provider = provider
        self.tagsToAdd = tagsToAdd
        self.keptExisting = keptExisting
        self.identifiedFilm = identifiedFilm
    }

    /// `tagsToAdd` as the `[String: String]` shape `EncodingJobConfig
    /// .outputMetadata` uses, ready for the engine (#508 commit 6) to merge
    /// with `outputMetadata.merge(metadataToAdd) { job, _ in job }`.
    ///
    /// Built with `uniquingKeysWith`, NOT `uniqueKeysWithValues`: the latter
    /// crashes the process on a duplicate key, and a tagging helper must
    /// never be able to crash an encode (the same reason `AutoTagMerge` was
    /// fixed in `4891dd0`). `TMDBTagMapping.applying` writes each key once,
    /// so a duplicate is not expected; if one ever appears the first wins.
    public var metadataToAdd: [String: String] {
        Dictionary(tagsToAdd.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// A `.skipped` report. Takes no provider on purpose: no skip ever sends
    /// a request, so `provider` is always `nil` (see its doc comment), and
    /// this helper — the only way the runner builds a skip — cannot say
    /// otherwise.
    static func skipped(_ reason: String) -> AutoTagLookupReport {
        AutoTagLookupReport(outcome: .skipped(reason: reason), provider: nil)
    }
}

// MARK: - AutoTagProviderChoice

/// Which lookup service the runner will use for a file, or why none.
public enum AutoTagProviderChoice: Sendable, Equatable {
    /// Use this source.
    case lookUp(AutoTagSource)
    /// Use nothing, for this plain-English reason.
    case skip(reason: String)
}

// MARK: - AutoTagRunner

/// Looks one file up for the auto-tag feature. Stateless: every input comes
/// in through the parameters, so one file's lookup can never leak into
/// another's.
public enum AutoTagRunner {

    // MARK: Wording

    /// The plain-English reasons `run` gives for skipping a file. Public and
    /// named so the Activity Log wording (#508 commit 8) and the tests can
    /// refer to them rather than copying the text. Treat an edit as a
    /// user-facing copy change.
    public enum Reasons {
        /// The master switch is off. The same words the Settings status line
        /// uses (`AutoTagGate.offReason`), so the two can never disagree.
        public static let off = AutoTagGate.offReason

        /// The probe found no streams at all.
        public static let emptyProbe =
            "Nothing could be read from the file's streams, so there was nothing to look up."

        /// Streams, but no moving video and no audio (for example a file of
        /// subtitles, or of a picture alone).
        public static let nothingToIdentify =
            "The file has no moving video or audio to identify."

        /// The file name matches the TV-episode pattern ("Show S01E02").
        public static let tvEpisode = "TV episodes aren't looked up yet."

        /// No usable running time was probed. See this file's header for why
        /// such a file is never tagged.
        public static let noRunningTime =
            "The file's running time couldn't be read, and a match is only trusted when its running time can be checked."

        /// Neither a title tag nor the file name gave anything to search for.
        public static let noSearchTitle =
            "Neither the file's name nor its tags give a title to search for."

        /// Films need TMDB, and no TMDB key is saved. Worded to match the
        /// plan's Activity Log table ("…skipped: no TMDB key is saved
        /// (Settings › Metadata).").
        public static let noTMDBKey = "No TMDB key is saved (Settings › Metadata)."

        /// Music is recognised but not looked up yet (#508 commit 5).
        public static let musicNotBuiltYet =
            "Music files aren't looked up yet: looking them up on MusicBrainz during a conversion hasn't been built."

        /// None of the chosen sources can identify this kind of file.
        public static let noUsableSource =
            "None of the chosen lookup sources can identify this kind of file."

        /// Sources that exist as settings but have no working lookup behind
        /// them, so they can't run EVEN WITH a key. Deliberately a different
        /// reason from `noTMDBKey`: telling someone to add a key for a
        /// service that would still do nothing sends them on a pointless
        /// errand.
        public static func notConnectedYet(_ sources: [AutoTagSource]) -> String {
            let names = sources.map(shortName(for:))
            let list: String
            switch names.count {
            case 0: list = "That lookup source"
            case 1: list = names[0]
            default: list = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
            }
            let verb = names.count > 1 ? "aren't" : "isn't"
            return "\(list) \(verb) connected yet, so \(names.count > 1 ? "they" : "it") can't be used even with a key."
        }

        /// The lookup was abandoned because it passed the deadline.
        public static func didNotAnswer(provider: String, within deadline: Duration) -> String {
            "\(provider) didn't answer within \(describe(deadline))."
        }

        /// A short name for a source, for the wording above.
        static func shortName(for source: AutoTagSource) -> String {
            switch source {
            case .filename: return "File-name parsing"
            case .existingMetadata: return "The file's own tags"
            case .tmdb: return "TMDB"
            case .tvdb: return "TheTVDB"
            case .musicBrainz: return "MusicBrainz"
            case .discogs: return "Discogs"
            case .audioFingerprint: return "Audio fingerprinting"
            }
        }

        /// "30 seconds", "1 second", "0.05 seconds". Whole numbers are
        /// written without a decimal point; anything else to at most two
        /// places. `String(format:)` is not localised, so the decimal point
        /// is always ".", which keeps the wording (and its tests) stable
        /// whatever the Mac's region is.
        static func describe(_ duration: Duration) -> String {
            let parts = duration.components
            let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
            if seconds == seconds.rounded() {
                let whole = Int(seconds)
                return whole == 1 ? "1 second" : "\(whole) seconds"
            }
            var text = String(format: "%.2f", seconds)
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
            return "\(text) seconds"
        }
    }

    // MARK: Tuning

    /// Two different films scoring within this much of each other (and both
    /// passing the threshold) are treated as a tie, and neither is applied.
    /// The owner's decision (plan, decision 2).
    public static let ambiguityMargin = 0.05

    /// How often `run` asks `shouldStop()`. A quarter of a second: quick
    /// enough that Stop feels immediate, slow enough to cost nothing.
    static let stopPollInterval: Duration = .milliseconds(250)

    /// The most TMDB detail requests (one per candidate, the only source of
    /// running time) a single lookup may make, whatever `maxResults` says.
    static let maxRuntimeFetches = 5

    // MARK: Planning (pure)

    /// Decide what to do with `file`, from its probe alone. No network.
    ///
    /// The checks run in this order, and the first that applies decides:
    ///   1. No streams at all → skip (`Reasons.emptyProbe`).
    ///   2. Moving video in a container that can hold it
    ///      (`looksLikeVideoContent`, never `hasVideo`) → a film, unless:
    ///      - the file name matches the TV-episode pattern → skip;
    ///      - there is no running time → skip (see the file header);
    ///      - there is no title to search for → skip.
    ///   3. Audio and no moving video (`hasAudio && !looksLikeVideoContent`,
    ///      never `isAudioOnly`) → music, unless there is no running time.
    ///   4. Anything else → skip (`Reasons.nothingToIdentify`).
    ///
    /// The TV check applies to video only. A TV-style name on an audio file
    /// (a podcast, say) goes down the music route; the plan's rule for music
    /// (an artist is required, #508 commit 5) is what will decide it.
    ///
    /// - Parameters:
    ///   - file: The probed source file.
    ///   - jobTags: The job's own `outputMetadata`. Used ONLY to seed the
    ///     search: a title the job sets for its output is a better thing to
    ///     search for than whatever the source file carried, because it is
    ///     what the output will actually say. Blank values are ignored.
    public static func plan(for file: MediaFile, jobTags: [String: String] = [:]) -> AutoTagPlan {
        guard !file.streams.isEmpty else {
            return .skip(reason: Reasons.emptyProbe)
        }

        let hasRunningTime = (file.duration ?? 0) > 0 && (file.duration ?? 0).isFinite
        let seedTags = seedTags(file: file, jobTags: jobTags)

        if file.looksLikeVideoContent {
            if isTVEpisodeName(file.fileName) {
                return .skip(reason: Reasons.tvEpisode)
            }
            guard hasRunningTime else {
                return .skip(reason: Reasons.noRunningTime)
            }
            let query = TMDBTagMapping.seedQuery(tags: seedTags, filename: file.fileName)
            guard !query.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .skip(reason: Reasons.noSearchTitle)
            }
            return .film(query)
        }

        if file.hasAudio {
            guard hasRunningTime else {
                return .skip(reason: Reasons.noRunningTime)
            }
            return .music(MusicBrainzTagMapping.seedQuery(tags: seedTags, filename: file.fileName))
        }

        return .skip(reason: Reasons.nothingToIdentify)
    }

    /// Whether `fileName` matches `FilenameParser`'s TV-episode pattern.
    ///
    /// Reuses the parser rather than copying its regular expression:
    /// `FilenameParser.parse` tries the TV pattern FIRST and it is the only
    /// branch that returns `.tvEpisode`, so "parsed as `.tvEpisode`" is
    /// exactly "matched the TV pattern". A copied pattern would drift the
    /// day someone improves the parser.
    ///
    /// ⚠️ It recognises only the "S01E02" form. The parser's own doc comment
    /// also mentions "1x02", but no code handles that form, so a "Show 1x02"
    /// file is NOT caught here and would be searched for as a film.
    static func isTVEpisodeName(_ fileName: String) -> Bool {
        FilenameParser.parse(filename: fileName).mediaType == .tvEpisode
    }

    /// The tags used to SEED a search: the source file's non-blank tags,
    /// with the job's own non-blank tags layered on top (the job wins, as it
    /// does for what the output carries). Sorted by key so the order — and
    /// so which duplicate spelling a case-insensitive lookup finds first —
    /// never depends on dictionary ordering.
    static func seedTags(file: MediaFile, jobTags: [String: String]) -> [MediaTag] {
        var merged: [String: String] = [:]
        for (key, value) in file.metadata where !isBlank(value) {
            merged[key] = value
        }
        for (key, value) in jobTags where !isBlank(value) {
            // Replace a file tag spelled differently ("TITLE" vs "title").
            // The clashing keys are collected first, so the dictionary is
            // never changed while its own keys are being walked.
            let clashing = merged.keys.filter { $0.caseInsensitiveCompare(key) == .orderedSame }
            for existing in clashing {
                merged.removeValue(forKey: existing)
            }
            merged[key] = value
        }
        return tagList(merged)
    }

    // MARK: Choosing a provider (pure)

    /// Walk `order` (from `AutoTagger.determineLookupOrder`) and pick the
    /// first source this runner can actually use.
    ///
    ///   * `.filename` and `.existingMetadata` only SEED the search (that
    ///     already happened in `plan(for:jobTags:)`); they are passed over.
    ///   * `.tvdb`, `.discogs` and `.audioFingerprint` have no working lookup
    ///     behind them. They are passed over and, if nothing else is usable,
    ///     reported as "not connected yet" — not as "no key".
    ///   * `.tmdb` with no key saved is passed over (issue #508: "skip a
    ///     provider with no key rather than treat it as an error"). If
    ///     nothing else is usable, the reason is `Reasons.noTMDBKey`.
    ///   * A source not in `runnable` (what this runner can execute for this
    ///     kind of file) is passed over silently.
    ///
    /// Pure, and makes no request.
    public static func chooseProvider(
        from order: [AutoTagSource],
        runnable: Set<AutoTagSource>,
        hasTMDBService: Bool
    ) -> AutoTagProviderChoice {
        var tmdbHadNoKey = false
        var notConnected: [AutoTagSource] = []

        for source in order {
            switch source {
            case .filename, .existingMetadata:
                continue
            case .tvdb, .discogs, .audioFingerprint:
                if !notConnected.contains(source) { notConnected.append(source) }
            case .tmdb:
                guard runnable.contains(.tmdb) else { continue }
                if hasTMDBService { return .lookUp(.tmdb) }
                tmdbHadNoKey = true
            case .musicBrainz:
                guard runnable.contains(.musicBrainz) else { continue }
                return .lookUp(.musicBrainz)
            }
        }

        // The actionable reason first: saving a key fixes "no key"; nothing
        // the user can do fixes "not connected".
        if tmdbHadNoKey { return .skip(reason: Reasons.noTMDBKey) }
        if !notConnected.isEmpty { return .skip(reason: Reasons.notConnectedYet(notConnected)) }
        return .skip(reason: Reasons.noUsableSource)
    }

    // MARK: Running

    /// Look `source` up and report which tags it is missing.
    ///
    /// Makes no request at all when auto-tagging is off, when the plan is a
    /// skip, for music (not built yet), or when no usable provider is
    /// configured (for films: no TMDB key).
    ///
    /// **Deadline and Stop.** The lookup runs in a task group alongside two
    /// other tasks: one that sleeps for `request.deadline`, and one that asks
    /// `shouldStop()` every quarter of a second. The first of the three to
    /// finish wins and the group cancels the other two. Cancelling the
    /// lookup task reaches the HTTP request itself: `URLSession`'s async
    /// `data(for:)` cancels its network task when the calling task is
    /// cancelled, and `TMDBLookupService` turns the resulting
    /// `URLError.cancelled` back into `CancellationError`. Because it is a
    /// task GROUP, `run` cannot return until all three tasks have ended —
    /// nothing it started is left running afterwards.
    ///
    /// ⚠️ That last guarantee has a cost worth knowing: an HTTP client that
    /// ignored cancellation would hold `run` open until the request ended on
    /// its own (a TMDB request gives up after 20 seconds with no data
    /// arriving — `URLRequest.timeoutInterval` is an idle limit, not a total
    /// one). The production client honours cancellation (Apple documents
    /// that for `URLSession`'s async methods); a test stub must too.
    ///
    /// - Parameters:
    ///   - request: This job's settings and services.
    ///   - source: The probed source file.
    ///   - jobTags: The job's own `outputMetadata`. Its keys are never
    ///     overwritten, and it seeds the search (see `plan(for:jobTags:)`).
    ///   - shouldStop: Returns `true` once the user has asked for this job to
    ///     stop. Called from a background task, so it must be cheap and safe
    ///     to call from any thread.
    /// - Returns: The report. Every failure is IN the report, never thrown.
    /// - Throws: `CancellationError` — and nothing else — when `shouldStop()`
    ///   returns `true` or the calling task is cancelled, before or during
    ///   the lookup. A Stop pressed at the same moment the lookup finished
    ///   still wins: the caller asked to stop, so it is told the job stopped.
    public static func run(
        request: AutoTagRequest,
        source: MediaFile,
        jobTags: [String: String],
        shouldStop: @escaping @Sendable () -> Bool
    ) async throws -> AutoTagLookupReport {
        try throwIfStopped(shouldStop)

        guard request.config.enabled else {
            return .skipped(Reasons.off)
        }

        let query: MetadataSearchQuery
        switch plan(for: source, jobTags: jobTags) {
        case .skip(let reason):
            return .skipped(reason)
        case .music:
            // Honest, not pretend: the MusicBrainz lookup is #508 commit 5.
            return .skipped(Reasons.musicNotBuiltYet)
        case .film(let filmQuery):
            query = filmQuery
        }

        let order = AutoTagger.determineLookupOrder(query: query, config: request.config)
        switch chooseProvider(from: order, runnable: [.tmdb], hasTMDBService: request.tmdbService != nil) {
        case .skip(let reason):
            return .skipped(reason)
        case .lookUp:
            break
        }
        // `chooseProvider` only returns `.lookUp(.tmdb)` when a service
        // exists; unwrapped again here rather than force-unwrapped.
        guard let service = request.tmdbService else {
            return .skipped(Reasons.noTMDBKey)
        }

        let config = request.config
        let winner = try await race(
            deadline: request.deadline,
            pollInterval: stopPollInterval,
            shouldStop: shouldStop
        ) {
            try await lookUpFilm(
                query: query,
                service: service,
                file: source,
                jobTags: jobTags,
                config: config
            )
        }

        // Stop wins a tie with anything, including a lookup that finished in
        // the same instant: the user asked for the job to stop.
        try throwIfStopped(shouldStop)

        switch winner {
        case .finished(let report):
            return report
        case .deadlinePassed:
            return failed(
                Reasons.didNotAnswer(provider: "TMDB", within: request.deadline),
                service: service
            )
        case .stopRequested:
            throw CancellationError()
        }
    }

    // MARK: The race

    /// Which of the three racing tasks finished first.
    enum RaceWinner<Value: Sendable>: Sendable {
        case finished(Value)
        case deadlinePassed
        case stopRequested
    }

    /// Run `operation` against a deadline and a stop poll; the first of the
    /// three to finish wins and the other two are cancelled.
    ///
    /// Throws only when a child throws, and each child throws only
    /// `CancellationError` (the sleeps when cancelled; `operation` by its
    /// contract). A child throwing first can only mean the calling task was
    /// cancelled, which is rethrown as the stop it is.
    ///
    /// Rejected alternative: an unstructured `Task` for the lookup, abandoned
    /// when the deadline passed. That returns sooner from a client that
    /// ignores cancellation, but leaves its request running after `run` has
    /// returned, still using the network for a result nobody will read. A
    /// task group makes that impossible.
    static func race<Value: Sendable>(
        deadline: Duration,
        pollInterval: Duration,
        shouldStop: @escaping @Sendable () -> Bool,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> RaceWinner<Value> {
        try await withThrowingTaskGroup(of: RaceWinner<Value>.self) { group in
            group.addTask {
                let value = try await operation()
                return .finished(value)
            }
            group.addTask {
                try await Task.sleep(for: deadline)
                return .deadlinePassed
            }
            group.addTask {
                // Checked BEFORE the first sleep, so a stop that is already
                // requested wins at once rather than a quarter-second later.
                while !shouldStop() {
                    try await Task.sleep(for: pollInterval)
                }
                return .stopRequested
            }

            // `defer` so the losers are told to stop even when `next()`
            // throws — the group then still waits for them before this
            // closure's caller resumes, which is what guarantees nothing
            // outlives `run`. Their results (and their CancellationErrors)
            // are discarded unread, which is what a task group does with
            // results nobody asks `next()` for.
            defer { group.cancelAll() }

            guard let first = try await group.next() else {
                // Unreachable: three tasks were added above. Treated as a
                // stop rather than a crash.
                throw CancellationError()
            }
            return first
        }
    }

    // MARK: The film lookup

    /// Search, fetch running times, score, and judge. Throws ONLY
    /// `CancellationError`, and only when THIS task was cancelled; every
    /// other problem becomes a `.failed` (or `.skipped`) report.
    static func lookUpFilm(
        query: MetadataSearchQuery,
        service: TMDBLookupService,
        file: MediaFile,
        jobTags: [String: String],
        config: AutoTagConfig
    ) async throws -> AutoTagLookupReport {
        do {
            let language = config.language
            var found = try await service.searchMovies(title: query.title, year: query.year, language: language)
            if found.isEmpty, query.year != nil {
                // A wrong year in a file name or tag is common ("Film
                // (2019)" for a 2018 release). An empty year-filtered search
                // is retried once without the year; the seed year still
                // counts in the score, so a result from a different year is
                // marked down, not ignored.
                try Task.checkCancellation()
                found = try await service.searchMovies(title: query.title, year: nil, language: language)
            }
            guard !found.isEmpty else {
                return AutoTagLookupReport(outcome: .noMatch(searchedFor: query), provider: .tmdb)
            }

            // Consider at most `maxResults` (at least one, so a zero in a
            // config can't turn every search into "found nothing"), and fetch
            // running times — one request each — for at most five of them.
            let considered = max(1, config.maxResults)
            try Task.checkCancellation()
            let withRuntimes = try await service.withRuntimes(
                Array(found.prefix(considered)),
                limit: min(considered, maxRuntimeFetches),
                language: language
            )
            try Task.checkCancellation()

            let scored = score(candidates: withRuntimes, query: query, fileDuration: file.duration)
            return judge(scored: scored, query: query, file: file, jobTags: jobTags, config: config)
        } catch is CancellationError {
            // Pass on only a cancellation of THIS task (Stop, the deadline,
            // or the job being cancelled). A CancellationError from the HTTP
            // layer when nobody cancelled us — a URLSession invalidated
            // underneath, say — is a failed lookup, not a stopped job:
            // throwing it would mark the whole encode Cancelled because a
            // film database hiccupped.
            if Task.isCancelled { throw CancellationError() }
            return failed("The TMDB request was cancelled before it finished.", service: service)
        } catch let error as TMDBLookupError {
            switch error {
            case .missingAPIKey:
                // A service built with a blank key throws this before sending
                // anything. Same meaning as having no service at all, so the
                // same answer: skipped, and nothing was asked.
                return .skipped(Reasons.noTMDBKey)
            case .emptyQuery:
                // Also thrown before sending. `plan` already refuses a blank
                // title, so this is a second line, not an expected path.
                return .skipped(Reasons.noSearchTitle)
            default:
                // `errorDescription` is built without the request URL, and
                // the service redacts the key from any server text it quotes;
                // `failed` redacts again.
                return failed(error.errorDescription ?? "The TMDB lookup failed.", service: service)
            }
        } catch {
            // Not expected — the service throws only the two kinds above —
            // but a lookup must never be able to fail an encode.
            return failed("The TMDB lookup failed: \(error.localizedDescription)", service: service)
        }
    }

    /// Score every candidate with `DiscIdentifier.rank` and copy the score
    /// into `confidence`, best first.
    ///
    /// `rank` was written for discs but reads only the three signals set
    /// here — the main feature's running time, the seed title and the seed
    /// year. `discType` is required by `DiscSignals`' initialiser and set to
    /// `.dataDisc` (a file is not a disc), but `rank` ignores it.
    /// `AutoTagRunnerTests.test_rankIgnoresDiscType` scores the same
    /// candidates under every disc type and fails if any score differs.
    static func score(
        candidates: [MetadataResult],
        query: MetadataSearchQuery,
        fileDuration: TimeInterval?
    ) -> [MetadataResult] {
        let signals = DiscSignals(
            discType: .dataDisc,
            mainFeatureDurationSeconds: fileDuration,
            seedTitle: query.title,
            seedYear: query.year
        )
        return DiscIdentifier.rank(signals: signals, candidates: candidates).map { match in
            var result = match.candidate
            result.confidence = match.score.confidence
            return result
        }
    }

    /// Decide what to do with scored candidates (best first). Pure.
    static func judge(
        scored: [MetadataResult],
        query: MetadataSearchQuery,
        file: MediaFile,
        jobTags: [String: String],
        config: AutoTagConfig
    ) -> AutoTagLookupReport {
        guard let best = scored.first else {
            // `lookUpFilm` returns `.noMatch` before scoring an empty list,
            // so this is not reached today. It gives the same answer rather
            // than trapping, because nothing to judge IS no match.
            return AutoTagLookupReport(outcome: .noMatch(searchedFor: query), provider: .tmdb)
        }

        guard AutoTagger.meetsThreshold(result: best, config: config) else {
            return AutoTagLookupReport(
                outcome: .belowThreshold(best: AutoTagMatchSummary(best), needed: config.minimumConfidence),
                provider: .tmdb
            )
        }

        // The runner-up is the best-scoring DIFFERENT film: the same TMDB id
        // twice is one film listed twice, not a tie.
        if let runnerUp = scored.dropFirst().first(where: { $0.externalId != best.externalId }),
           AutoTagger.meetsThreshold(result: runnerUp, config: config),
           // A hair of tolerance so "exactly 0.05 apart" counts as within the
           // margin whatever the floating-point rounding of the two scores.
           best.confidence - runnerUp.confidence <= ambiguityMargin + 1e-9 {
            return AutoTagLookupReport(
                outcome: .ambiguous(first: AutoTagMatchSummary(best), second: AutoTagMatchSummary(runnerUp)),
                provider: .tmdb
            )
        }

        let additions = AutoTagMerge.additions(
            existing: tagList(file.metadata),
            jobTags: tagList(jobTags),
            applying: { TMDBTagMapping.applying(best, to: $0, includeIdentifiers: true) }
        )
        return AutoTagLookupReport(
            outcome: additions.added.isEmpty ? .matchedNothingToAdd : .applied,
            provider: .tmdb,
            tagsToAdd: additions.added,
            keptExisting: additions.keptExisting,
            identifiedFilm: best
        )
    }

    // MARK: Helpers

    /// A `.failed` report whose reason has been through the key redaction.
    /// The ONLY way this file builds a `.failed` outcome, so no failure text
    /// can skip the redaction.
    static func failed(_ reason: String, service: TMDBLookupService) -> AutoTagLookupReport {
        AutoTagLookupReport(outcome: .failed(reason: service.redactingKey(in: reason)), provider: .tmdb)
    }

    /// Throws `CancellationError` if the caller has asked to stop, or the
    /// calling task has been cancelled.
    static func throwIfStopped(_ shouldStop: @Sendable () -> Bool) throws {
        if Task.isCancelled || shouldStop() {
            throw CancellationError()
        }
    }

    /// A `[String: String]` tag dictionary as `[MediaTag]`, sorted by key so
    /// the order never depends on dictionary ordering.
    static func tagList(_ tags: [String: String]) -> [MediaTag] {
        tags.sorted { $0.key < $1.key }.map { MediaTag(key: $0.key, value: $0.value) }
    }

    static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
