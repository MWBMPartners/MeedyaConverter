// ============================================================================
// MeedyaConverter — OutputStreamPlan
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// WHY THIS FILE EXISTS (issue #530)
// ---------------------------------
// Every stream in a media file has a number: its position in the WHOLE file.
// That is the `#N` that `meedya-convert probe`, the app's stream pickers and
// `MediaStream.streamIndex` all show. ffmpeg has two different ways of naming
// a stream, and they are easy to mix up:
//
//   * `0:5`            — stream 5 of input 0, counted over the whole file.
//   * `0:a:1`, `-c:a:1`, `-metadata:s:a:1`, `-disposition:a:1`
//                      — the SECOND AUDIO stream, counted only among streams
//                        of that type. For options that change the output
//                        (`-c`, `-metadata:s`, `-disposition`) the count is
//                        among the OUTPUT file's streams of that type.
//
// Until #530 the argument builder took whole-file numbers from the pickers,
// the CLI flags, the subtitle tone-map step and the per-stream settings, and
// wrote them into the type-counted form. The two only agree by coincidence,
// so a choice or an edit could land on the wrong track, or on none at all.
//
// This file is the ONE place that converts:
//
//   * choosing a stream from the source   → `StreamSpecifier.source(_:)`,
//     `0:<whole-file number>`. Always right; needs nothing else.
//   * an option aimed at an output stream → `OutputStreamPlan`, the actual
//     ordered list of output streams, which says which output stream (and so
//     which type-counted position) each source stream became. That stays right
//     when tracks are dropped, replaced or reordered.
//
// WHAT IT CANNOT DO
// -----------------
// Without the list of the source's streams (`FFmpegArgumentBuilder
// .sourceStreams` — normally from probing), there is no way to know which
// output stream a source stream becomes. The builder then does NOT guess:
// options aimed at output streams are left out and reported through
// `streamSelectionProblems()`, and the engine refuses the job with that text
// rather than editing whichever stream happens to share the number.
// ============================================================================

import Foundation
import MediaLanguagePolicy

// MARK: - StreamSpecifier

/// Builds the ffmpeg stream names used to *choose* streams from an input.
///
/// Every `-map` that picks one particular source stream goes through here,
/// so the whole-file numbering is used in exactly one way (issue #530).
public enum StreamSpecifier {

    /// The `-map` value that chooses one stream of an input by its
    /// whole-file number: `0:5` for stream 5 of the first input.
    ///
    /// - Parameters:
    ///   - streamIndex: The stream's whole-file number (`MediaStream.streamIndex`).
    ///   - input: The ffmpeg input it belongs to (0 = the source file).
    /// - Returns: The specifier, for example `"0:5"`.
    public static func source(_ streamIndex: Int, input: Int = 0) -> String {
        "\(input):\(streamIndex)"
    }

    /// The negative `-map` value that removes one stream (by whole-file
    /// number) from an earlier, broader `-map`: `-0:5`.
    ///
    /// Only the legacy glob mapping (no source stream list) uses this; with a
    /// plan the removed stream is simply never mapped.
    public static func excludeSource(_ streamIndex: Int, input: Int = 0) -> String {
        "-\(source(streamIndex, input: input))"
    }

    /// ffmpeg's one-letter code for a stream type inside a specifier
    /// (`v`, `a`, `s`, `d`, `t`). `nil` for a type ffmpeg has no letter for.
    public static func typeLetter(for type: StreamType) -> String? {
        switch type {
        case .video: return "v"
        case .audio: return "a"
        case .subtitle: return "s"
        case .data: return "d"
        case .attachment: return "t"
        case .unknown: return nil
        }
    }
}

// MARK: - OutputStreamPlan

/// The ordered list of streams the output file will contain, and where each
/// one comes from.
///
/// Built by `FFmpegArgumentBuilder` when it knows the source's streams. It
/// is both the source of the `-map` arguments (so what is mapped and what the
/// options refer to can never disagree) and the answer to "which output
/// stream did source stream #N become?".
public struct OutputStreamPlan: Sendable, Equatable {

    /// One stream of the output file.
    public struct Entry: Sendable, Equatable {
        /// The ffmpeg input the stream is taken from: 0 is the source file; a
        /// higher number is a separate file (a tone-mapped subtitle
        /// replacement, for example).
        public let inputIndex: Int

        /// The source stream (whole-file number) this output stream carries —
        /// or, for a replacement, the source stream it stands in for. Metadata
        /// and roles belonging to that source stream follow it here.
        public let sourceStreamIndex: Int

        /// What kind of stream it is in the output.
        public let streamType: StreamType

        /// The `-map` value that selects it.
        public let mapSpecifier: String

        /// Whether this stream comes from a replacement file rather than
        /// straight from the source.
        public var isReplacement: Bool { inputIndex != 0 }

        public init(inputIndex: Int, sourceStreamIndex: Int, streamType: StreamType, mapSpecifier: String) {
            self.inputIndex = inputIndex
            self.sourceStreamIndex = sourceStreamIndex
            self.streamType = streamType
            self.mapSpecifier = mapSpecifier
        }
    }

    /// The output streams, in output order.
    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The `-map` arguments, one pair per output stream, in output order.
    public var mapArguments: [String] {
        entries.flatMap { ["-map", $0.mapSpecifier] }
    }

    /// The output stream that source stream `index` became, or `nil` when it
    /// is not in the output. If a source stream were somehow mapped twice,
    /// the first copy is the one returned.
    public func entry(forSourceStream index: Int) -> Entry? {
        entries.first { $0.sourceStreamIndex == index }
    }

    /// The type-counted position of source stream `index` in the OUTPUT —
    /// the `N` in `-c:a:N`, `-metadata:s:a:N` and `-disposition:a:N`.
    ///
    /// - Parameters:
    ///   - index: The source stream's whole-file number.
    ///   - type: When given, the answer is `nil` unless the output stream is
    ///     of this type (so an audio setting can never land on a subtitle).
    /// - Returns: The position among output streams of the same type, or
    ///   `nil` if the stream is not in the output (or is not of `type`).
    public func outputPosition(forSourceStream index: Int, ofType type: StreamType? = nil) -> Int? {
        guard let position = entries.firstIndex(where: { $0.sourceStreamIndex == index }) else {
            return nil
        }
        let target = entries[position]
        if let type, target.streamType != type {
            return nil
        }
        // Count the earlier output streams of the same type: that count is the
        // type-counted position ffmpeg expects.
        return entries[..<position].filter { $0.streamType == target.streamType }.count
    }

    /// Every output stream with its full output specifier (`v:0`, `a:1`,
    /// `s:0` …), in output order — worked out in one pass. Streams of a type
    /// with no ffmpeg letter are left out.
    public var entriesWithSpecifiers: [(entry: Entry, specifier: String)] {
        var counts: [StreamType: Int] = [:]
        var result: [(entry: Entry, specifier: String)] = []
        for entry in entries {
            let position = counts[entry.streamType, default: 0]
            counts[entry.streamType] = position + 1
            if let letter = StreamSpecifier.typeLetter(for: entry.streamType) {
                result.append((entry, "\(letter):\(position)"))
            }
        }
        return result
    }

    /// The full output specifier for source stream `index`, such as `a:1`,
    /// for options written `-disposition:<specifier>` or
    /// `-metadata:s:<specifier>`. `nil` when the stream is not in the output
    /// or its type has no ffmpeg letter.
    public func outputSpecifier(forSourceStream index: Int) -> String? {
        guard let target = entry(forSourceStream: index),
              let letter = StreamSpecifier.typeLetter(for: target.streamType),
              let position = outputPosition(forSourceStream: index) else {
            return nil
        }
        return "\(letter):\(position)"
    }
}

// MARK: - SourceStreamEdit

/// A person's explicit change to one stream of the source file, made in the
/// stream editor. Stored keyed by the stream's whole-file number
/// (`EncodingJobConfig.sourceStreamEdits`) and written to whichever output
/// stream that source stream becomes (issue #530).
///
/// `nil` in a field means "leave it as the source has it".
public struct SourceStreamEdit: Codable, Sendable, Equatable {
    /// The new title. `nil` leaves the source's title; an empty string clears it.
    public var title: String?

    /// The new language, as a BCP 47 tag. `nil` leaves the source's language.
    public var language: String?

    /// The new roles (ffmpeg dispositions: default, forced, original,
    /// commentary, SDH …). `nil` leaves the source's roles. When set, it
    /// replaces all of them — that is what the editor's toggles mean.
    public var disposition: StreamDisposition?

    public init(title: String? = nil, language: String? = nil, disposition: StreamDisposition? = nil) {
        self.title = title
        self.language = language
        self.disposition = disposition
    }

    /// Whether this edit changes anything at all.
    public var isEmpty: Bool {
        title == nil && language == nil && disposition == nil
    }
}

// MARK: - Building the plan

extension FFmpegArgumentBuilder {

    /// The source's streams in whole-file order with duplicates removed, or
    /// `nil` when the builder was not told them (an empty list counts as not
    /// told: a real file always has at least one stream).
    var orderedSourceStreams: [MediaStream]? {
        guard let sourceStreams, !sourceStreams.isEmpty else { return nil }
        var seen = Set<Int>()
        return sourceStreams
            .sorted { $0.streamIndex < $1.streamIndex }
            .filter { seen.insert($0.streamIndex).inserted }
    }

    /// Works out the output streams from the source's streams and the stream
    /// choices on this builder, or `nil` when the source's streams are not
    /// known.
    ///
    /// The selection rules are exactly those the older glob mapping (`-map 0`,
    /// `0:v?`, `0:a?`, `0:s?`) expressed — including its oddity that video is
    /// only mapped by default when subtitles are not disabled — so turning the
    /// plan on changes WHICH NUMBERS are used, never which streams are chosen.
    func makeOutputStreamPlan() -> OutputStreamPlan? {
        guard let source = orderedSourceStreams else { return nil }
        let byIndex = Dictionary(uniqueKeysWithValues: source.map { ($0.streamIndex, $0) })

        var entries: [OutputStreamPlan.Entry] = []

        // Adds one source stream (input 0) to the output.
        func add(_ stream: MediaStream) {
            entries.append(.init(
                inputIndex: 0,
                sourceStreamIndex: stream.streamIndex,
                streamType: stream.streamType,
                mapSpecifier: StreamSpecifier.source(stream.streamIndex)
            ))
        }

        // Adds the stream a picker or CLI flag chose, if it exists and is of
        // the expected type. A wrong or missing number is NOT mapped; it is
        // reported by `streamSelectionProblems()` instead.
        func addPicked(_ index: Int, expecting type: StreamType) {
            if let stream = byIndex[index], stream.streamType == type {
                add(stream)
            }
        }

        if mapAllStreams {
            // `-map 0` equivalent: every stream, in the source's order.
            source.forEach(add)
        } else {
            // Video: the picked stream, else every video stream. (The legacy
            // mapping skipped video here when subtitles were disabled; that is
            // preserved on purpose, see the doc comment above.)
            if let vi = videoStreamIndex {
                addPicked(vi, expecting: .video)
            } else if !disableSubtitles {
                source.filter { $0.streamType == .video }.forEach(add)
            }

            // Audio: the picked stream, else every audio stream.
            if let ai = audioStreamIndex {
                addPicked(ai, expecting: .audio)
            } else {
                source.filter { $0.streamType == .audio }.forEach(add)
            }

            // Subtitles: an explicit per-stream action list wins (#409);
            // otherwise the passthrough switch with an optional pick.
            if !subtitleStreamActions.isEmpty {
                // Replacement files are extra ffmpeg inputs numbered after the
                // source (0) and any additional inputs, in encounter order —
                // the same numbering `build()` gives their `-i` arguments.
                var nextReplacementInput = 1 + additionalInputs.count
                for action in subtitleStreamActions {
                    switch action.action {
                    case .passthrough:
                        addPicked(action.streamIndex, expecting: .subtitle)
                    case .replaceWith:
                        // A replacement file holds one subtitle stream (its
                        // first); it stands in for the source stream, so that
                        // stream's language and roles follow it.
                        entries.append(.init(
                            inputIndex: nextReplacementInput,
                            sourceStreamIndex: action.streamIndex,
                            streamType: .subtitle,
                            mapSpecifier: "\(nextReplacementInput):s:0"
                        ))
                        nextReplacementInput += 1
                    case .drop:
                        continue
                    }
                }
            } else if subtitlePassthrough {
                if let si = subtitleStreamIndex {
                    addPicked(si, expecting: .subtitle)
                } else {
                    source.filter { $0.streamType == .subtitle }.forEach(add)
                }
            }
        }

        // Per-stream subtitle exclusions (#41): remove SOURCE subtitle streams
        // switched off in the per-stream settings. A key that is not a
        // subtitle stream of this file is ignored here (and reported as
        // skipped), so a stale setting can never drop a video or audio track.
        entries.removeAll { entry in
            entry.inputIndex == 0
                && entry.streamType == .subtitle
                && perStreamSubtitleInclude[entry.sourceStreamIndex] == false
        }

        return OutputStreamPlan(entries: orderedCanonically(entries, sources: byIndex))
    }

    /// Puts the output streams in the language policy's STORED order
    /// (TRACK-060, TRACK-050, LANG-010 to LANG-027): video, then audio, then
    /// subtitles, then anything else — each type on its own, the original
    /// language's tracks first, then by role, then by language code
    /// (general before specific), ties keeping their order.
    ///
    /// It orders by what each output track will SAY — the stream editor's
    /// language and roles where the person changed them — so the order and
    /// the written tags agree. This is only ever used for a file being
    /// created (COMPAT-020: existing files are never rewritten just to
    /// reorder them). It is skipped when `orderTracksCanonically` is off, or
    /// when the policy's data is missing (then the selection order stands).
    ///
    /// Attached pictures (cover art — `StreamDisposition.isAttachedPicture`)
    /// are NOT tracks, so they are not ordered as tracks: they go after every
    /// real track, in their source order, keeping their flags. ffmpeg reports
    /// them as video streams, and they used to be sorted in with the real
    /// video — which put an M4A's cover art BEFORE its only audio track.
    func orderedCanonically(_ entries: [OutputStreamPlan.Entry], sources: [Int: MediaStream]) -> [OutputStreamPlan.Entry] {
        guard orderTracksCanonically, let policy = TrackLanguage.policy else { return entries }
        let pictures = entries.filter { isAttachedPicture($0, sources: sources) }
        let tracks = entries.filter { !isAttachedPicture($0, sources: sources) }
        let items = tracks.map { entry -> CanonicalOrderItem in
            let facts = outputFacts(for: entry.sourceStreamIndex, sources: sources)
            return CanonicalOrderItem(
                // A track with no language at all sorts with "not known"
                // (LANG-003), never as a real language.
                tag: facts.language ?? "und",
                isOriginal: facts.disposition?.isOriginal ?? false,
                type: entry.streamType.policyTrackType,
                roles: facts.disposition?.policyRoles(for: entry.streamType) ?? []
            )
        }
        return policy.canonicalOrder.trackOrder(items).map { tracks[$0] } + pictures
    }

    /// Whether `entry` is an attached picture (cover art) rather than a
    /// track: a video stream whose flags — as the output will have them —
    /// include `attached_pic`. Unknown flags (data saved before they were
    /// kept) count as a real track, as they always did.
    func isAttachedPicture(_ entry: OutputStreamPlan.Entry, sources: [Int: MediaStream]) -> Bool {
        entry.streamType == .video
            && outputFacts(for: entry.sourceStreamIndex, sources: sources).disposition?.isAttachedPicture == true
    }

    /// What the output stream carrying source stream `index` will say: the
    /// source's language, roles and title with any stream-editor change
    /// applied. `disposition` is `nil` when neither the source (data saved
    /// before roles were kept) nor the editor says anything about roles.
    ///
    /// An edited disposition keeps the flags the editor has no switch for
    /// (`attached_pic` and the rest) from the source: the source's flags with
    /// only the person's edits applied, so an edit can never clear them.
    func outputFacts(
        for index: Int,
        sources: [Int: MediaStream]
    ) -> (language: String?, disposition: StreamDisposition?, sourceTitle: String?) {
        let source = sources[index]
        let edit = sourceStreamEdits[index]
        let language = edit?.language ?? source?.language
        let disposition = edit?.disposition.map { $0.keepingUneditableFlags(of: source?.disposition) }
            ?? source?.disposition
        return (language, disposition, source?.title)
    }

    // MARK: - Problems the builder could not honour

    /// Stream choices and per-stream settings that `build()` could NOT apply,
    /// in plain English, for the caller to refuse the job with. Empty when
    /// everything was applied.
    ///
    /// These are the cases where applying something anyway would mean
    /// guessing, which is how #530 happened:
    /// - a picked stream number that is not in the file, or is the wrong type;
    /// - per-stream settings or editor changes when the source's streams are
    ///   not known, so the output stream they belong to cannot be worked out;
    /// - a selection that leaves the output with no streams at all.
    public func streamSelectionProblems() -> [String] {
        guard let source = orderedSourceStreams else {
            // Without the source's streams, only the settings aimed at output
            // streams are a problem — picks become `-map 0:<number>`, which is
            // correct whatever the file holds.
            return perStreamSettingDescriptions().isEmpty ? [] : [
                "The source file's streams could not be read, so these per-stream settings "
                    + "cannot be matched to the right output tracks: "
                    + perStreamSettingDescriptions().joined(separator: "; ")
                    + ". Nothing was guessed; re-open the file and try again."
            ]
        }

        let byIndex = Dictionary(uniqueKeysWithValues: source.map { ($0.streamIndex, $0) })
        var problems: [String] = []

        // Checks one picked number against the file.
        func check(_ index: Int?, expecting type: StreamType, label: String) {
            guard let index, !mapAllStreams else { return }
            guard let stream = byIndex[index] else {
                problems.append("The chosen \(label) stream #\(index) does not exist in this file.")
                return
            }
            if stream.streamType != type {
                problems.append(
                    "Stream #\(index) is \(Self.describe(stream.streamType)), not \(Self.describe(type)). "
                        + "Stream numbers count every stream in the file, as the probe shows them."
                )
            }
        }

        check(videoStreamIndex, expecting: .video, label: "video")
        check(audioStreamIndex, expecting: .audio, label: "audio")
        if subtitleStreamActions.isEmpty, subtitlePassthrough {
            check(subtitleStreamIndex, expecting: .subtitle, label: "subtitle")
        }
        if !mapAllStreams {
            for action in subtitleStreamActions where action.action == .passthrough {
                check(action.streamIndex, expecting: .subtitle, label: "subtitle")
            }
        }

        if let plan = makeOutputStreamPlan(), plan.entries.isEmpty {
            problems.append("These settings choose no streams at all from this file, so there is nothing to write.")
        }
        return problems
    }

    /// Per-stream settings that were aimed at a source stream but did not
    /// reach the output, because that stream is not in the output or is of
    /// another type (a profile's per-stream settings made on a different
    /// file, for example). Informational: the job can still run.
    public func skippedStreamSettings() -> [String] {
        guard let plan = makeOutputStreamPlan() else { return [] }
        var skipped: [String] = []

        func note(_ keys: some Sequence<Int>, _ type: StreamType, _ what: String) {
            for key in Set(keys).sorted() where plan.outputPosition(forSourceStream: key, ofType: type) == nil {
                skipped.append("\(what) for stream #\(key) (not \(Self.describe(type)) in this output)")
            }
        }

        note(perStreamVideoCodec.keys, .video, "Video codec")
        note(perStreamVideoPassthrough.keys, .video, "Video copy")
        note(perStreamVideoBitrate.keys, .video, "Video bitrate")
        note(perStreamAudioCodec.keys, .audio, "Audio codec")
        note(perStreamAudioBitrate.keys, .audio, "Audio bitrate")
        note(perStreamSubtitlePassthrough.keys, .subtitle, "Subtitle copy")
        for key in sourceStreamEdits.keys.sorted() where plan.entry(forSourceStream: key) == nil {
            skipped.append("Stream editor changes for stream #\(key) (not in this output)")
        }
        return skipped
    }

    /// What this output will keep differently from the source, and why, in
    /// plain English — one line per stream, for the job's log
    /// (`EncodingEngine.jobNotices`, and standard error for the command-line
    /// tool). Empty when every stream is written as the source has it or as
    /// the person asked. Informational: the job still runs.
    public func trackWritingNotes() -> [String] {
        guard let plan = makeOutputStreamPlan(), let sources = sourceStreamsByIndex else { return [] }
        var notes: [String] = []

        // Language fields that cannot hold exactly what the track says, or
        // that are left as the source had them (`languageWrite`). Pictures
        // attached as Matroska attachments carry no language field.
        let attachments = Set(pictureAttachments(in: plan).map(\.sourceStreamIndex))
        let container = resolveContainerFormat()
        for entry in plan.entries where !(entry.inputIndex == 0 && attachments.contains(entry.sourceStreamIndex)) {
            if let note = languageWrite(for: entry, sources: sources, container: container).note {
                notes.append(note)
            }
        }

        // Cover art a Matroska output can only keep as an attachment, but
        // with no copy of the picture to attach (see `AttachedPictures`).
        if AttachedPictures.needsAttachment(in: container) {
            for entry in plan.entries where entry.inputIndex == 0
                && isAttachedPicture(entry, sources: sources)
                && !attachments.contains(entry.sourceStreamIndex) {
                notes.append(
                    "Stream #\(entry.sourceStreamIndex) is a picture attached to the file (cover art). "
                        + "It could not be kept as an attachment, so ffmpeg writes it into this "
                        + "Matroska file as a one-frame picture track."
                )
            }
        }
        return notes
    }

    /// Short descriptions of every per-stream setting aimed at an output
    /// stream, used when none of them can be placed.
    private func perStreamSettingDescriptions() -> [String] {
        var parts: [String] = []
        func add(_ keys: some Sequence<Int>, _ what: String) {
            let sorted = Set(keys).sorted()
            if !sorted.isEmpty {
                parts.append("\(what) (stream \(sorted.map { "#\($0)" }.joined(separator: ", ")))")
            }
        }
        add(perStreamVideoCodec.keys, "video codec")
        add(perStreamVideoPassthrough.keys, "video copy")
        add(perStreamVideoBitrate.keys, "video bitrate")
        add(perStreamAudioCodec.keys, "audio codec")
        add(perStreamAudioBitrate.keys, "audio bitrate")
        add(perStreamSubtitlePassthrough.keys, "subtitle copy")
        add(perStreamSubtitleInclude.filter { $0.value == false }.keys, "subtitle removal")
        add(sourceStreamEdits.filter { !$0.value.isEmpty }.keys, "stream editor changes")
        return parts
    }

    /// "a video stream", "an audio stream" … for the plain-English messages.
    static func describe(_ type: StreamType) -> String {
        switch type {
        case .video: return "a video stream"
        case .audio: return "an audio stream"
        case .subtitle: return "a subtitle stream"
        case .data: return "a data stream"
        case .attachment: return "an attachment"
        case .unknown: return "a stream of unknown type"
        }
    }
}
