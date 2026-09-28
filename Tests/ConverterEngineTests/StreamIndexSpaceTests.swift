// ============================================================================
// MeedyaConverter — StreamIndexSpaceTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Issue #530: streams are chosen by their WHOLE-FILE number (the `#N` the
// probe and the pickers show), but ffmpeg's `0:a:N`, `-c:a:N`,
// `-metadata:s:a:N` and `-disposition:a:N` count only streams of one type
// (and, for output options, only OUTPUT streams). These tests use files where
// the two numbering schemes DIFFER — that is where the old code went wrong —
// and pin the one conversion (`StreamSpecifier`, `OutputStreamPlan`).
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Builds a source stream list for tests: one stream per type given, with
/// whole-file numbers 0, 1, 2 … in that order. `streamLayout(.video, .audio,
/// .audio)` is a file with video #0 and audio #1 and #2. Shared by other test
/// files in this target (PerStreamArgumentTests, the argument-builder tests).
func streamLayout(_ types: StreamType...) -> [MediaStream] {
    types.enumerated().map { MediaStream(streamIndex: $0.offset, streamType: $0.element) }
}

final class StreamIndexSpaceTests: XCTestCase {

    // MARK: - Helpers

    /// A builder with dummy input/output files.
    private func makeBuilder() -> FFmpegArgumentBuilder {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mkv")
        return builder
    }

    /// The value after each `-map`, in order.
    private func maps(_ args: [String]) -> [String] {
        zip(args, args.dropFirst()).filter { $0.0 == "-map" }.map(\.1)
    }

    /// Whether `flag` is immediately followed by `value`.
    private func hasPair(_ args: [String], _ flag: String, _ value: String) -> Bool {
        zip(args, args.dropFirst()).contains { $0.0 == flag && $0.1 == value }
    }

    /// A typical film layout where the numbers disagree: video #0, audio #1
    /// (English) and #2 (commentary), subtitles #3 and #4.
    private let film = streamLayout(.video, .audio, .audio, .subtitle, .subtitle)

    // MARK: - StreamSpecifier

    func test_streamSpecifier_usesWholeFileNumbers() {
        XCTAssertEqual(StreamSpecifier.source(5), "0:5")
        XCTAssertEqual(StreamSpecifier.source(2, input: 3), "3:2")
        XCTAssertEqual(StreamSpecifier.excludeSource(4), "-0:4")
        XCTAssertEqual(StreamSpecifier.typeLetter(for: .audio), "a")
        XCTAssertEqual(StreamSpecifier.typeLetter(for: .attachment), "t")
        XCTAssertNil(StreamSpecifier.typeLetter(for: .unknown))
    }

    // MARK: - OutputStreamPlan

    /// Output positions count OUTPUT streams of the same type, in output order.
    func test_outputStreamPlan_positionsCountOutputStreamsOfOneType() {
        let plan = OutputStreamPlan(entries: [
            .init(inputIndex: 0, sourceStreamIndex: 0, streamType: .video, mapSpecifier: "0:0"),
            .init(inputIndex: 0, sourceStreamIndex: 2, streamType: .audio, mapSpecifier: "0:2"),
            .init(inputIndex: 0, sourceStreamIndex: 1, streamType: .audio, mapSpecifier: "0:1"),
            .init(inputIndex: 1, sourceStreamIndex: 4, streamType: .subtitle, mapSpecifier: "1:s:0"),
        ])
        XCTAssertEqual(plan.outputPosition(forSourceStream: 2), 0)
        XCTAssertEqual(plan.outputPosition(forSourceStream: 1), 1)
        XCTAssertEqual(plan.outputSpecifier(forSourceStream: 1), "a:1")
        XCTAssertEqual(plan.outputSpecifier(forSourceStream: 4), "s:0")
        XCTAssertNil(plan.outputPosition(forSourceStream: 3), "Not in the output")
        XCTAssertNil(plan.outputPosition(forSourceStream: 2, ofType: .subtitle), "Wrong type")
        XCTAssertEqual(plan.mapArguments, ["-map", "0:0", "-map", "0:2", "-map", "0:1", "-map", "1:s:0"])
    }

    // MARK: - Choosing streams

    /// Without the source list (legacy mapping), a picked stream is still
    /// named by its whole-file number. The old code wrote `0:a:2` — the THIRD
    /// audio stream, which this layout does not even have.
    func test_legacyMapping_picksUseWholeFileNumbers() {
        var builder = makeBuilder()
        builder.videoStreamIndex = 0
        builder.audioStreamIndex = 2
        builder.subtitlePassthrough = true
        builder.subtitleStreamIndex = 4

        XCTAssertEqual(maps(builder.build()), ["0:0", "0:2", "0:4"])
    }

    /// With the source list, the mapping is an explicit plan in source order,
    /// and the chosen audio stream is the file's #2.
    func test_plan_mapsExplicitListWithChosenStream() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.audioStreamIndex = 2

        XCTAssertEqual(maps(builder.build()), ["0:0", "0:2"])
        XCTAssertTrue(builder.streamSelectionProblems().isEmpty)
    }

    /// `-map 0` becomes an explicit list of every stream.
    func test_plan_mapAllListsEveryStream() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.mapAllStreams = true

        XCTAssertEqual(maps(builder.build()), ["0:0", "0:1", "0:2", "0:3", "0:4"])
    }

    /// A picked number of the wrong type is refused in plain words, and not
    /// mapped (ffmpeg would otherwise encode the wrong track).
    func test_plan_wrongTypePickIsAProblem() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.audioStreamIndex = 3   // #3 is a subtitle stream

        let problems = builder.streamSelectionProblems()
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("Stream #3 is a subtitle stream, not an audio stream"), problems[0])
        XCTAssertFalse(maps(builder.build()).contains("0:3"))
    }

    /// A number that is not in the file at all is refused too.
    func test_plan_missingPickIsAProblem() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.videoStreamIndex = 9

        XCTAssertTrue(builder.streamSelectionProblems().contains {
            $0.contains("video stream #9 does not exist")
        })
    }

    // MARK: - Options aimed at output streams

    /// The classic #530 case: the user picks audio #2 and sets its codec. It
    /// is the ONLY audio stream in the output, so the option is `-c:a:0`. The
    /// old code wrote `-c:a:2`, which matches nothing.
    func test_plan_perStreamCodecLandsOnTheOutputStreamItBecame() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.audioStreamIndex = 2
        builder.perStreamAudioCodec = [2: .flac]

        let args = builder.build()
        XCTAssertTrue(hasPair(args, "-c:a:0", "flac"), "\(args)")
        XCTAssertFalse(args.contains("-c:a:2"))
    }

    /// With both audio streams in the output, source #2 is output audio 1.
    func test_plan_perStreamCodecCountsOnlyOutputAudio() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.perStreamAudioCodec = [2: .flac]

        XCTAssertTrue(hasPair(builder.build(), "-c:a:1", "flac"))
    }

    /// A per-stream setting for a stream that is not in the output (or not of
    /// that type) is skipped and reported, never applied to another stream.
    func test_plan_settingForAbsentStreamIsSkippedAndReported() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.audioStreamIndex = 1
        builder.perStreamAudioCodec = [2: .flac, 3: .aacLC]   // #2 not chosen; #3 is a subtitle

        let args = builder.build()
        XCTAssertFalse(args.contains { $0.hasPrefix("-c:a:") }, "\(args)")
        let skipped = builder.skippedStreamSettings()
        XCTAssertEqual(skipped.count, 2, "\(skipped)")
        XCTAssertTrue(builder.streamSelectionProblems().isEmpty, "Skipped settings are not a reason to refuse")
    }

    /// Without the source list, per-stream settings cannot be placed: they are
    /// left out and the job is refused with a plain explanation, rather than
    /// written with the whole-file number as a type-counted one.
    func test_legacy_perStreamSettingsAreRefusedNotGuessed() {
        var builder = makeBuilder()
        builder.perStreamAudioCodec = [2: .flac]

        XCTAssertFalse(builder.build().contains { $0.hasPrefix("-c:a:") })
        let problems = builder.streamSelectionProblems()
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("audio codec (stream #2)"), problems[0])
    }

    // MARK: - Subtitle tone-map replacements (#409 path)

    /// A tone-mapped replacement stands in for its source stream: editor
    /// changes to that source stream follow it to the replacement's output
    /// position, and the passthrough neighbour is named by whole-file number.
    func test_plan_toneMapReplacementKeepsItsSourceStreamsEdits() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.subtitleStreamActions = [
            .init(streamIndex: 3, action: .replaceWith(URL(fileURLWithPath: "/tmp/sub3.sup"))),
            .init(streamIndex: 4, action: .passthrough),
        ]
        builder.sourceStreamEdits = [
            3: SourceStreamEdit(title: "English"),
            4: SourceStreamEdit(title: "Français"),
        ]

        let args = builder.build()
        XCTAssertEqual(maps(args), ["0:0", "0:1", "0:2", "1:s:0", "0:4"])
        XCTAssertTrue(hasPair(args, "-metadata:s:s:0", "title=English"), "\(args)")
        XCTAssertTrue(hasPair(args, "-metadata:s:s:1", "title=Français"), "\(args)")
    }

    // MARK: - Per-stream subtitle removal (#41 path)

    /// Removal keys are whole-file numbers; a key that is not a subtitle
    /// stream (a stale setting from another file) never removes a video or
    /// audio track.
    func test_plan_subtitleRemovalOnlyRemovesSubtitles() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.subtitlePassthrough = true
        builder.perStreamSubtitleInclude = [4: false, 1: false]

        let mapped = maps(builder.build())
        XCTAssertEqual(mapped, ["0:0", "0:1", "0:2", "0:3"])
        XCTAssertFalse(mapped.contains { $0.hasPrefix("-") }, "A plan needs no negative maps")
    }

    // MARK: - Stream editor changes

    /// Editor changes land on the output stream their source stream became —
    /// `s:a:1` for source #2 here. The old editor wrote `s:a:2`. (The output
    /// is Matroska, whose language field takes the three-letter bibliographic
    /// code, so the edit's `en` is written `eng` — TRACK-070.)
    func test_plan_editorChangesUseOutputPositions() {
        var builder = makeBuilder()
        builder.sourceStreams = film
        builder.sourceStreamEdits = [2: SourceStreamEdit(title: "Commentary", language: "en")]
        // This test is about numbering only. With the policy's track order on,
        // #2 (now English) would move ahead of #1 (no language) — correct, and
        // covered by TrackWritingTests — so keep the source order here.
        builder.orderTracksCanonically = false

        let args = builder.build()
        XCTAssertTrue(hasPair(args, "-metadata:s:a:1", "title=Commentary"), "\(args)")
        XCTAssertTrue(hasPair(args, "-metadata:s:a:1", "language=eng"), "\(args)")
        XCTAssertFalse(args.contains("-metadata:s:a:2"))
    }

    // MARK: - Determinism

    /// The same settings always give the same command line: metadata and
    /// dispositions are written in sorted order, not dictionary order.
    func test_metadataAndDispositionsAreInAFixedOrder() {
        var builder = makeBuilder()
        builder.metadata = ["title": "T", "artist": "A", "comment": "C", "album": "B"]
        builder.streamMetadata = ["s:a:1": ["title": "x", "handler_name": "y"], "s:a:0": ["title": "z"]]
        builder.streamDispositions = ["a:1": "0", "a:0": "default"]

        let args = builder.build()
        let metadataValues = zip(args, args.dropFirst()).filter { $0.0.hasPrefix("-metadata") }.map { "\($0.0) \($0.1)" }
        XCTAssertEqual(metadataValues, [
            "-metadata album=B", "-metadata artist=A", "-metadata comment=C", "-metadata title=T",
            "-metadata:s:a:0 title=z", "-metadata:s:a:1 handler_name=y", "-metadata:s:a:1 title=x",
        ])
        let dispositions = zip(args, args.dropFirst()).filter { $0.0.hasPrefix("-disposition") }.map { "\($0.0) \($0.1)" }
        XCTAssertEqual(dispositions, ["-disposition:a:0 default", "-disposition:a:1 0"])
        for _ in 0..<5 {
            XCTAssertEqual(builder.build(), args)
        }
    }

    // MARK: - EncodingJobConfig

    /// The job carries the source list and edits to the builder, and reports
    /// the same problems the builder finds.
    func test_jobConfig_threadsSourceStreamsAndReportsProblems() {
        // Subtitle passthrough off, so only video and the chosen audio are mapped.
        let profile = EncodingProfile(
            name: "t", videoCodec: .h265, audioCodec: .aacLC, subtitlePassthrough: false, containerFormat: .mkv
        )
        var config = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/in.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/out.mkv"),
            profile: profile,
            audioStreamIndex: 2
        )
        config.sourceStreams = film
        XCTAssertEqual(maps(config.buildArguments()), ["0:0", "0:2"])
        XCTAssertTrue(config.streamSelectionProblems().isEmpty)

        config.audioStreamIndex = 0
        XCTAssertFalse(config.streamSelectionProblems().isEmpty, "#0 is video, not audio")
    }
}
