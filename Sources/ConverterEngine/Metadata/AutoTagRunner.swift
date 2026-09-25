// ============================================================================
// MeedyaConverter — AutoTagRunner (Issue #508, commit 5/10: music)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The piece that actually LOOKS A FILE UP for the auto-tag feature: it
// decides whether a file is a film, a song or neither, searches TMDB for a
// film or MusicBrainz for a song, scores what comes back, and works out
// which tags are missing from the file. Everything it needs arrives in one
// `AutoTagRequest` (built per job by `AutoTagSettingsSource.currentRequest()`,
// commit 3).
//
// ⚠️ WHAT IS AND ISN'T WIRED UP — read before assuming anything runs:
//   * `EncodingEngine.encode(job:onProgress:)` calls `AutoTagRunner.run` after
//     the source probe and before any FFmpeg pass (#508 commit 6) — but ONLY
//     for an engine that was given an `AutoTagSettingsSource` when it was
//     built, and only while the setting is on. The APP's engine is given
//     one, in `AppViewModel.init` (#508 commit 8), and the Settings switch
//     that turns the setting on shipped in commit 9 — so a real encode from
//     the app's queue, watch folders, scheduled jobs or AppleScript DOES
//     reach this file today, whenever "Tag files automatically while
//     converting" is on. `AutoTagEncodeDeliveryTests` also drives it
//     directly through a real `encode` with fake FFmpeg/ffprobe programs. An
//     `EncodingEngine` built anywhere else — the `meedya-convert` CLI, or any
//     encoding pipeline — is never given a settings source, so it never
//     reaches this file at all.
//   * TV EPISODES ARE NOT LOOKED UP. A file whose name matches
//     `FilenameParser`'s "S01E02" pattern is skipped (`Reasons.tvEpisode`).
//   * NO ARTWORK, NO RENAMING. Both are separate follow-up issues (see the
//     plan). This file has no part in either.
//   * THE NFO WRITER (`AutoTagNFOWriter`, #508 commit 7) IS A SEPARATE FILE.
//     This runner never writes one itself; it only ever hands the engine a
//     report whose `identifiedFilm` the engine can pass on. There is no
//     music equivalent of the film NFO planned at all — `identifiedFilm` is
//     always `nil` on the music path (see that property's own doc comment
//     below), so the engine has nothing to write one from for a song.
//   See `.claude/plans/autotag-encode-plan.md`.
//
// FOUR TRAPS THIS FILE IS BUILT AROUND
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
//    carry on encoding without the extra tags. `runFilmLookup` and
//    `runMusicLookup` both race through the SAME `race(deadline:pollInterval
//    :shouldStop:operation:)` helper, so this guarantee is not duplicated
//    code that could drift between the two media kinds.
//
// 4. Searching MusicBrainz by title alone is too easy to get wrong. A film's
//    running time alone tells two same-named films apart; a song has no such
//    luxury, because thousands of completely different recordings share a
//    title ("Yesterday", "Hallelujah"). So an artist is REQUIRED before a
//    music file is looked up AT ALL (`Reasons.noArtistForMusic`, checked
//    before anything is sent) — from a tag, or from a file name shaped like
//    "Artist - Title" or "Artist – Title" (en dash;
//    `musicArtistTitleFromFileName`). Once a search does run, length plays
//    the part running time plays for films: a recording with no length, or
//    whose length is off from the file's own duration by more than
//    `max(5 seconds, 3%)`, scores confidence 0 (`musicConfidence`) however
//    well its title and artist matched — the owner's decision (plan,
//    decision 1).
//
// WHY A FILE WITH NO RUNNING TIME IS NEVER TAGGED. Running time carries half
// the score's weight and is the only signal that tells two films with the
// same name apart. Without it the best possible score is 0.5 (title 0.35 +
// year 0.15), which can never reach 0.7 anyway — so the runner says so up
// front and makes no request at all, rather than spending TMDB calls on a
// match it could never accept. The owner's decision (plan, decision 6):
// conservative. The same running-time gate in `plan(for:)` covers music too,
// because `musicConfidence` needs the file's own duration just as much as
// the film side needs it for `DiscIdentifier.rank`.
// ============================================================================

import Foundation

// MARK: - AutoTagPlan

/// What the runner intends to do with a file, decided from the probe alone
/// (no network). See `AutoTagRunner.plan(for:jobTags:)`.
public enum AutoTagPlan: Sendable, Equatable {
    /// Look the file up as a film on TMDB, searching for this.
    case film(MetadataSearchQuery)
    /// The file is music, to be looked up on MusicBrainz searching for
    /// this. `query.artist` may still be `nil` here — `plan(for:)` only
    /// classifies the file, it does not enforce the "an artist is
    /// required" rule; `run` does that (`Reasons.noArtistForMusic`) so a
    /// music file without one is reported honestly as skipped rather than
    /// silently reclassified as something else.
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
    /// The provider's own id for it (a TMDB film id for a film; a
    /// MusicBrainz recording MBID for a song).
    public let externalId: String
    /// The runner's own score for it, 0...1 — for a film,
    /// `DiscIdentifier.rank`'s score, NOT the 0.5 every raw TMDB result
    /// carries; for a song, `musicConfidence`'s score, NOT MusicBrainz's raw
    /// 0...100 one.
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
    /// Two DIFFERENT candidates (films, or MusicBrainz recordings) both
    /// passed the threshold and scored within `AutoTagRunner.ambiguityMargin`
    /// of each other, so neither is trusted.
    case ambiguous(first: AutoTagMatchSummary, second: AutoTagMatchSummary)
    /// The provider returned no candidates at all for this search.
    case noMatch(searchedFor: MetadataSearchQuery)
    /// Nothing was looked up, for a reason that is expected rather than a
    /// fault: auto-tagging off, no key saved, a TV episode, a music file with
    /// no artist, no running time, and so on. No request is ever sent for a
    /// skipped file, and the report's `provider` is always `nil`.
    case skipped(reason: String)
    /// The lookup was attempted and went wrong: unreachable, key rejected,
    /// rate-limited, a server error, or no answer before the deadline. For
    /// the FILM path, `reason` has been passed through the TMDB key
    /// redaction, which replaces every exact occurrence of the key, so the
    /// key cannot appear in it as written. MusicBrainz never uses a key, so
    /// there is nothing to redact on the music path.
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

    /// The accepted FILM, with `confidence` set to the runner's real score.
    /// Set for `.applied` and `.matchedNothingToAdd` on the film path (the
    /// NFO writer in #508 commit 7 needs it even when no tag was missing);
    /// `nil` otherwise, and always `nil` for a music match — there is no
    /// music NFO, and nothing yet needs the identified recording on its own
    /// (its title/artist/etc. are already in `tagsToAdd`/`keptExisting`). If
    /// a later commit needs the full `MusicBrainzRecordingMatch` for
    /// something `tagsToAdd` can't carry, add its own field rather than
    /// putting a recording into a property named for a film.
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

        /// Neither a tag nor the file name gave an artist for a music file.
        /// Checked before `chooseProvider` even runs, so a music file with
        /// no artist makes ZERO requests — the same shape as every other
        /// skip. See this file's header, trap 4, for why an artist (not
        /// just a title) is required before MusicBrainz is ever asked.
        public static let noArtistForMusic =
            "Music needs an artist to look up safely; searching by title alone is too ambiguous to apply unattended."

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
    /// (a podcast, say) goes down the music route.
    ///
    /// Music's query is built by `musicQuery(seedTags:fileName:)`, which may
    /// still come back with no `artist` — a classification decision here is
    /// NOT the same thing as "safe to look up", so this function does not
    /// enforce "an artist is required" itself; see `.music`'s own doc
    /// comment and `run`'s `Reasons.noArtistForMusic`.
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
            return .music(musicQuery(seedTags: seedTags, fileName: file.fileName))
        }

        return .skip(reason: Reasons.nothingToIdentify)
    }

    /// Builds the music search query: `MusicBrainzTagMapping.seedQuery`'s own
    /// tag- and (hyphen-only) filename-based artist, topped up — only when
    /// that found none — by a LOCAL "Artist - Title" / "Artist – Title" (en
    /// dash) split read straight from the file name.
    ///
    /// Deliberately NOT done by teaching `FilenameParser.parseMusic` itself
    /// to recognise an en dash: that shared parser also feeds the FILM path
    /// (`TMDBTagMapping.seedQuery`, for any file whose name carries no year),
    /// and an en dash is common in film titles too ("Kill Bill – Volume 1").
    /// Widening it there would risk turning a yearless film name into a
    /// false music match. This function only ever runs once a file has
    /// ALREADY been probed as music (`plan(for:)`'s `hasAudio` branch), so
    /// that risk does not apply here — the film-or-music decision was made
    /// from the actual audio/video streams, not from the name.
    static func musicQuery(seedTags: [MediaTag], fileName: String) -> MetadataSearchQuery {
        var query = MusicBrainzTagMapping.seedQuery(tags: seedTags, filename: fileName)

        // The shared `FilenameParser.parseMusic` splits on ANY hyphen and takes
        // the first part as the artist, so "01 - Song Title.mp3" gives the
        // artist "01", a track number. That would satisfy this runner's "an
        // artist is required" safety gate with no real artist at all. So a
        // digits-only artist that came from the FILE NAME is treated as
        // missing, and the stricter local fallback below decides instead.
        // An `artist` TAG is always trusted, even if it is digits only: "311"
        // is a real band. Fixing the shared parser itself is a separate issue,
        // because it also serves the tag editor's lookup and the film path.
        if let artist = query.artist,
           isAllASCIIDigits(artist.trimmingCharacters(in: .whitespaces)),
           MusicBrainzTagMapping.value(forKey: "artist", in: seedTags) == nil {
            query.artist = nil
        }

        guard query.artist == nil, let hint = musicArtistTitleFromFileName(fileName) else {
            return query
        }
        query.artist = hint.artist
        // Only replace the title with the file-name guess if nothing more
        // specific (a `title` tag) already set it — `seedQuery` prefers a
        // tag's title over the file name, and that must not be undone here.
        if MusicBrainzTagMapping.value(forKey: "title", in: seedTags) == nil {
            query.title = hint.title
        }
        return query
    }

    /// A last-resort split of a file name shaped like "Artist - Title" or
    /// "Artist – Title" (en dash), used only once a file is already known to
    /// be music.
    ///
    /// Splits ONLY on a SPACED dash (" – " or " - "), the conventional
    /// artist/title separator, so a hyphen INSIDE a name ("Sub-Title",
    /// "Jay-Z") is never mistaken for one. The en dash is tried first.
    ///
    /// Accepted shapes:
    ///   * exactly two parts, "Artist - Title", when the first part is not
    ///     just digits;
    ///   * exactly three parts whose first is just digits, "01 - Artist -
    ///     Title": the leading track number is dropped.
    /// Anything else returns `nil`, so no guess is made.
    ///
    /// Rejected earlier version (the orchestrator's review of #508 5/10):
    /// it split on any bare "-" and took the FIRST part as the artist and the
    /// LAST as the title. So the very common "01 - Song Title.mp3" produced
    /// the artist "01". That satisfied the "an artist is required" safety
    /// gate with a track number, which is exactly what that gate exists to
    /// stop.
    static func musicArtistTitleFromFileName(_ fileName: String) -> (artist: String, title: String)? {
        let name = (fileName as NSString).deletingPathExtension
        for separator in [" – ", " - "] {
            let parts = name.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            switch parts.count {
            case 2 where !isAllASCIIDigits(parts[0]):
                return (parts[0], parts[1])
            case 3 where isAllASCIIDigits(parts[0]) && !isAllASCIIDigits(parts[1]):
                return (parts[1], parts[2])
            default:
                continue
            }
        }
        return nil
    }

    /// True for a non-empty string made only of ASCII 0-9: a track number
    /// such as "01", never an artist.
    static func isAllASCIIDigits(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (0x30...0x39).contains($0) }
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
    /// skip, when a music file has no artist to search with
    /// (`Reasons.noArtistForMusic`), or when no usable provider is
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
    ///   - onLookingUp: Called at most once, with the service about to be
    ///     asked, immediately before the FIRST request is sent — never for a
    ///     skip (off, a TV name, no key, a music file with no artist, …),
    ///     because a skip sends nothing. Added in #508 commit 6 so the engine
    ///     can report "looking this file up on TMDB" only when that is true,
    ///     without copying this function's skip decisions into the engine
    ///     (a copy would drift). Called on the calling task, before the race
    ///     starts, so it always happens before `run` returns. Defaults to
    ///     doing nothing, so earlier callers are unchanged.
    /// - Returns: The report. Every failure is IN the report, never thrown.
    /// - Throws: `CancellationError` — and nothing else — when `shouldStop()`
    ///   returns `true` or the calling task is cancelled, before or during
    ///   the lookup. A Stop pressed at the same moment the lookup finished
    ///   still wins: the caller asked to stop, so it is told the job stopped.
    public static func run(
        request: AutoTagRequest,
        source: MediaFile,
        jobTags: [String: String],
        shouldStop: @escaping @Sendable () -> Bool,
        onLookingUp: @escaping @Sendable (MetadataSource) -> Void = { _ in }
    ) async throws -> AutoTagLookupReport {
        try throwIfStopped(shouldStop)

        guard request.config.enabled else {
            return .skipped(Reasons.off)
        }

        switch plan(for: source, jobTags: jobTags) {
        case .skip(let reason):
            return .skipped(reason)
        case .film(let query):
            return try await runFilmLookup(
                query: query, request: request, source: source, jobTags: jobTags,
                shouldStop: shouldStop, onLookingUp: onLookingUp
            )
        case .music(let query):
            return try await runMusicLookup(
                query: query, request: request, source: source, jobTags: jobTags,
                shouldStop: shouldStop, onLookingUp: onLookingUp
            )
        }
    }

    /// The film half of `run`: choose TMDB or skip, then race the lookup
    /// against the deadline and Stop. Split out of `run` only so the two
    /// media kinds' near-identical "choose a provider, then race" shape
    /// reads as two short functions rather than one long `switch`; nothing
    /// about the race, the deadline wording or the key redaction changed
    /// from #508 commit 4.
    static func runFilmLookup(
        query: MetadataSearchQuery,
        request: AutoTagRequest,
        source: MediaFile,
        jobTags: [String: String],
        shouldStop: @escaping @Sendable () -> Bool,
        onLookingUp: @escaping @Sendable (MetadataSource) -> Void = { _ in }
    ) async throws -> AutoTagLookupReport {
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

        // Every skip is behind us: the next thing that happens is a request.
        onLookingUp(.tmdb)

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

    /// The music half of `run`, added in #508 commit 5. The same shape as
    /// `runFilmLookup` — choose a provider, then race the search against the
    /// deadline and Stop — with one extra gate in front: an artist is
    /// required (this file's header, trap 4), checked BEFORE
    /// `chooseProvider` even runs, so a music file with no artist makes ZERO
    /// requests, exactly like every other skip.
    ///
    /// MusicBrainz never needs a key, so — unlike the film half — this can
    /// only skip for "not connected yet" or "no usable source", never for
    /// anything resembling `Reasons.noTMDBKey`.
    static func runMusicLookup(
        query: MetadataSearchQuery,
        request: AutoTagRequest,
        source: MediaFile,
        jobTags: [String: String],
        shouldStop: @escaping @Sendable () -> Bool,
        onLookingUp: @escaping @Sendable (MetadataSource) -> Void = { _ in }
    ) async throws -> AutoTagLookupReport {
        guard let artist = query.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty else {
            return .skipped(Reasons.noArtistForMusic)
        }

        let order = AutoTagger.determineLookupOrder(query: query, config: request.config)
        // `hasTMDBService` only matters to `chooseProvider`'s `.tmdb` branch,
        // and `order` cannot contain `.tmdb` here — `determineLookupOrder`
        // filters sources by the query's media type, and this query's is
        // `.music`. `false` documents that the value is unused, not a guess.
        switch chooseProvider(from: order, runnable: [.musicBrainz], hasTMDBService: false) {
        case .skip(let reason):
            return .skipped(reason)
        case .lookUp:
            break
        }

        // Every skip is behind us: the next thing that happens is a request.
        onLookingUp(.musicBrainz)

        let service = request.musicBrainzService
        let config = request.config
        let winner = try await race(
            deadline: request.deadline,
            pollInterval: stopPollInterval,
            shouldStop: shouldStop
        ) {
            try await lookUpMusic(
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
            return failedMusic(Reasons.didNotAnswer(provider: "MusicBrainz", within: request.deadline))
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

    // MARK: The music lookup

    /// Search, rank, score and judge — the music counterpart of
    /// `lookUpFilm`, added in #508 commit 5. Throws ONLY `CancellationError`,
    /// and only when THIS task was cancelled; every other problem becomes a
    /// `.failed` (or `.skipped`) report, exactly like the film path.
    static func lookUpMusic(
        query: MetadataSearchQuery,
        service: MusicBrainzLookupService,
        file: MediaFile,
        jobTags: [String: String],
        config: AutoTagConfig
    ) async throws -> AutoTagLookupReport {
        do {
            let matches = try await service.searchRecordings(title: query.title, artist: query.artist)
            guard !matches.isEmpty else {
                return AutoTagLookupReport(outcome: .noMatch(searchedFor: query), provider: .musicBrainz)
            }
            let scored = scoreMusic(candidates: matches, fileDurationSeconds: file.duration)
            return judgeMusic(scored: scored, query: query, file: file, jobTags: jobTags, config: config)
        } catch is CancellationError {
            // Same reasoning as `lookUpFilm`: pass on only a cancellation of
            // THIS task (Stop, the deadline, or the job being cancelled). A
            // `CancellationError` from the HTTP layer when nobody cancelled
            // us is a failed lookup, not a stopped job.
            if Task.isCancelled { throw CancellationError() }
            return failedMusic("The MusicBrainz request was cancelled before it finished.")
        } catch let error as MusicBrainzLookupError {
            switch error {
            case .emptyQuery:
                // `runMusicLookup` already refuses a blank artist, and
                // `plan(for:)`/`musicQuery` always give SOME title text from
                // a tag or the file name, so this is not an expected path —
                // a second line of defence, the same reasoning `lookUpFilm`
                // gives for its own `.emptyQuery` branch.
                return .skipped(Reasons.noSearchTitle)
            default:
                return failedMusic(error.errorDescription ?? "The MusicBrainz lookup failed.")
            }
        } catch {
            // Not expected — the service throws only `MusicBrainzLookupError`
            // — but a lookup must never be able to fail an encode.
            return failedMusic("The MusicBrainz lookup failed: \(error.localizedDescription)")
        }
    }

    /// Rank every candidate with `MusicBrainzTagMapping.ranked`, then compute
    /// each one's CONFIDENCE per the owner's music acceptance rule (plan,
    /// decision 1; this file's header, trap 4): `score / 100`, but 0 when the
    /// recording has no usable length, or its length is off from the file's
    /// own duration by more than `max(5 seconds, 3% of the file's duration)`.
    ///
    /// `ranked`'s own sort key is MusicBrainz's raw 0...100 score, broken
    /// only by RAW duration closeness — not the tolerance rule above. That
    /// is unlike the film side, where `DiscIdentifier.rank`'s score IS the
    /// confidence `judge` uses, so `score(candidates:query:fileDuration:)`'s
    /// output is already sorted by confidence. Here a high-scoring recording
    /// whose length is a little too far off (zeroed by the rule above) could
    /// otherwise sit ahead of a lower-scoring one that IS within tolerance,
    /// so this function re-sorts by the computed confidence, best first,
    /// before `judgeMusic` ever looks at "the best candidate" or "the top
    /// two" — the same meaning those phrases have on the film side.
    static func scoreMusic(
        candidates: [MusicBrainzRecordingMatch],
        fileDurationSeconds: TimeInterval?
    ) -> [(match: MusicBrainzRecordingMatch, result: MetadataResult)] {
        let byMusicBrainzOrder = MusicBrainzTagMapping.ranked(candidates, fileDurationSeconds: fileDurationSeconds)
        let withConfidence = byMusicBrainzOrder.map { match -> (match: MusicBrainzRecordingMatch, result: MetadataResult) in
            var result = match.metadataResult
            result.confidence = musicConfidence(for: match, fileDurationSeconds: fileDurationSeconds)
            return (match, result)
        }
        // Stable by construction (`Array.sorted(by:)` is a documented stable
        // sort since Swift 5), but the offset tie-break is written out
        // explicitly anyway — the same style `MusicBrainzTagMapping.ranked`
        // itself uses — so this does not silently depend on that guarantee.
        let indexed = Array(withConfidence.enumerated())
        return indexed.sorted { lhs, rhs in
            if lhs.element.result.confidence != rhs.element.result.confidence {
                return lhs.element.result.confidence > rhs.element.result.confidence
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The owner's music acceptance rule (plan, decision 1) for ONE
    /// candidate: its MusicBrainz score (0...100) as a 0...1 confidence,
    /// UNLESS its length can't be trusted — absent, zero, or more than
    /// `max(5 seconds, 3%)` away from the file's own duration — in which case
    /// the confidence is 0, however high the raw score.
    ///
    /// 0, not "drop the candidate": a run of all-mismatched candidates still
    /// has a real "best" to report through `.belowThreshold`, which reads far
    /// better in the Activity Log than the misleading `.noMatch` when
    /// MusicBrainz did find something with that title and artist.
    static func musicConfidence(for match: MusicBrainzRecordingMatch, fileDurationSeconds: TimeInterval?) -> Double {
        guard let fileDurationSeconds, fileDurationSeconds > 0, fileDurationSeconds.isFinite else {
            // `plan(for:)` already refuses a file with no usable running
            // time before a music lookup is ever attempted; this keeps the
            // function correct on its own terms regardless.
            return 0
        }
        guard let recordingLength = match.lengthSeconds, recordingLength > 0 else {
            return 0
        }
        let tolerance = max(5.0, fileDurationSeconds * 0.03)
        guard abs(recordingLength - fileDurationSeconds) <= tolerance else {
            return 0
        }
        return Double(match.score) / 100
    }

    /// Decide what to do with scored candidates (best first). Pure — the
    /// music counterpart of `judge`, including the SAME ambiguity rule: two
    /// DIFFERENT recordings (by MusicBrainz id, never the same recording
    /// listed twice) both meeting the threshold and within `ambiguityMargin`
    /// of each other are trusted to neither.
    static func judgeMusic(
        scored: [(match: MusicBrainzRecordingMatch, result: MetadataResult)],
        query: MetadataSearchQuery,
        file: MediaFile,
        jobTags: [String: String],
        config: AutoTagConfig
    ) -> AutoTagLookupReport {
        guard let best = scored.first else {
            // `lookUpMusic` returns `.noMatch` before scoring an empty list,
            // so this is not reached today. Same defensive answer as
            // `judge`'s: nothing to judge IS no match.
            return AutoTagLookupReport(outcome: .noMatch(searchedFor: query), provider: .musicBrainz)
        }

        guard AutoTagger.meetsThreshold(result: best.result, config: config) else {
            return AutoTagLookupReport(
                outcome: .belowThreshold(best: AutoTagMatchSummary(best.result), needed: config.minimumConfidence),
                provider: .musicBrainz
            )
        }

        // The runner-up is the best-scoring DIFFERENT recording: the same
        // MusicBrainz id twice is one recording listed twice, not a tie.
        if let runnerUp = scored.dropFirst().first(where: { $0.match.id != best.match.id }),
           AutoTagger.meetsThreshold(result: runnerUp.result, config: config),
           // A hair of tolerance so "exactly 0.05 apart" counts as within the
           // margin whatever the floating-point rounding of the two scores —
           // the same reasoning `judge`'s own check gives.
           best.result.confidence - runnerUp.result.confidence <= ambiguityMargin + 1e-9 {
            return AutoTagLookupReport(
                outcome: .ambiguous(first: AutoTagMatchSummary(best.result), second: AutoTagMatchSummary(runnerUp.result)),
                provider: .musicBrainz
            )
        }

        let release = best.match.bestRelease(preferringAlbumTitled: query.album)
        let additions = AutoTagMerge.additions(
            existing: tagList(file.metadata),
            jobTags: tagList(jobTags),
            applying: { MusicBrainzTagMapping.applying(best.match, release: release, to: $0, includeIdentifiers: true) }
        )
        return AutoTagLookupReport(
            outcome: additions.added.isEmpty ? .matchedNothingToAdd : .applied,
            provider: .musicBrainz,
            tagsToAdd: additions.added,
            keptExisting: additions.keptExisting
            // `identifiedFilm` stays nil: see that property's own doc
            // comment for why a recording does not belong in it.
        )
    }

    // MARK: Helpers

    /// A `.failed` TMDB report whose reason has been through the key
    /// redaction. The ONLY way this file builds a `.failed` outcome for the
    /// FILM path, so no film failure text can skip the redaction. See
    /// `failedMusic` for the MusicBrainz equivalent, which has no key to
    /// redact.
    static func failed(_ reason: String, service: TMDBLookupService) -> AutoTagLookupReport {
        AutoTagLookupReport(outcome: .failed(reason: service.redactingKey(in: reason)), provider: .tmdb)
    }

    /// A `.failed` MusicBrainz report. No key is ever sent to MusicBrainz —
    /// unlike `failed(_:service:)` for TMDB — so there is nothing to redact;
    /// the reason is used exactly as given. Kept as its own tiny function,
    /// rather than folding every caller into `failed(_:service:)`, so this
    /// remains the ONLY way this file builds a `.failed` outcome for the
    /// MUSIC path.
    static func failedMusic(_ reason: String) -> AutoTagLookupReport {
        AutoTagLookupReport(outcome: .failed(reason: reason), provider: .musicBrainz)
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
