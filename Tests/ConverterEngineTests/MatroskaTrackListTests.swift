// ============================================================================
// MeedyaConverter — MatroskaTrackListTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// A Matroska track's FULL language tag (`LanguageBCP47`) must win over its
// old three-letter field (TRACK-070). ffprobe reads only the old field, so
// the second independent review of the language policy work found a file
// made by mkvmerge — Cantonese `yue`, Mandarin `cmn`, Min Nan `nan`, Canadian
// French `fr-CA` — remuxed as `chi`, `chi`, `chi`, `fre`, with Cantonese
// titled "中文" and nothing in the job's log. These tests pin the fix:
//
//   * `MatroskaTrackList` reads the track list itself, from bytes built here
//     by hand (so the reader is checked without any tool installed), and
//     refuses anything it cannot read with certainty;
//   * the probe takes the full tag, keeps the old field's text, and — when
//     the list cannot be read and the file's writer may have written full
//     tags — marks the tracks, so the notes say so and no automatic title is
//     made from the old code;
//   * with MKVToolNix and ffmpeg installed, a real mkvmerge file goes all the
//     way through MeedyaConverter's own arguments (skipped otherwise — but
//     failed in CI's build-and-test job, which installs and requires them);
//   * a full tag over an old field that says only `und` (Abaza `abq`,
//     `und-Latn` …) is written, not left for ffmpeg to copy — it copies
//     nothing (the fourth independent review).
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class MatroskaTrackListTests: XCTestCase {

    // MARK: - Building EBML by hand

    /// An element: its ID bytes, a one- to eight-byte size, and its data.
    private func element(_ id: [UInt8], _ data: [UInt8]) -> [UInt8] {
        id + size(data.count) + data
    }

    /// An EBML size: one byte when it fits, else eight.
    private func size(_ count: Int) -> [UInt8] {
        if count < 0x7F { return [0x80 | UInt8(count)] }
        return [0x01] + (0..<7).reversed().map { UInt8((count >> ($0 * 8)) & 0xFF) }
    }

    private func text(_ id: [UInt8], _ value: String) -> [UInt8] { element(id, Array(value.utf8)) }
    private func uint(_ id: [UInt8], _ value: UInt8) -> [UInt8] { element(id, [value]) }

    /// A TrackEntry with a number, a type and its language fields.
    private func track(_ number: UInt8, type: UInt8, language: String?, full: String?) -> [UInt8] {
        var body = uint([0xD7], number) + uint([0x83], type)
        if let language { body += text([0x22, 0xB5, 0x9C], language) }
        if let full { body += text([0x22, 0xB5, 0x9D], full) }
        return element([0xAE], body)
    }

    /// A whole file: the EBML header, then a Segment of UNKNOWN size (as a
    /// live recording writes it) holding `children`.
    private func file(_ children: [UInt8]) -> [UInt8] {
        let header = element([0x1A, 0x45, 0xDF, 0xA3], text([0x42, 0x82], "matroska"))
        return header + [0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF] + children
    }

    private func info(_ writer: String) -> [UInt8] {
        element([0x15, 0x49, 0xA9, 0x66], text([0x57, 0x41], writer))
    }

    private func tracks(_ entries: [UInt8]) -> [UInt8] {
        element([0x16, 0x54, 0xAE, 0x6B], entries)
    }

    private let cluster: [UInt8] = [0x1F, 0x43, 0xB6, 0x75, 0x81, 0x00]

    /// The review's file, by hand: video, then Cantonese, Canadian French and
    /// an English subtitle, as mkvmerge writes them.
    private var mkvmergeLike: [UInt8] {
        file(info("mkvmerge v101.0 ('Time To Turn') 64-bit")
            + tracks(track(1, type: 1, language: "und", full: "und")
                     + track(2, type: 2, language: "chi", full: "yue")
                     + track(3, type: 2, language: "fre", full: "fr-CA")
                     + track(4, type: 0x11, language: "eng", full: nil))
            + cluster)
    }

    // MARK: - Reading

    func test_readsBothLanguageFieldsAndTheWriter() throws {
        let list = try XCTUnwrap(MatroskaTrackList.read(bytes: mkvmergeLike))
        XCTAssertEqual(list.writingApplication, "mkvmerge v101.0 ('Time To Turn') 64-bit")
        XCTAssertEqual(list.tracks, [
            .init(number: 1, type: 1, language: "und", languageBCP47: "und"),
            .init(number: 2, type: 2, language: "chi", languageBCP47: "yue"),
            .init(number: 3, type: 2, language: "fre", languageBCP47: "fr-CA"),
            .init(number: 4, type: 0x11, language: "eng", languageBCP47: nil)
        ])
    }

    /// A track list that comes after the first Cluster is not looked for;
    /// the writer is still known.
    func test_aTrackListAfterTheMediaIsNotRead() throws {
        let late = file(info("SomeWriter 1.0") + cluster + tracks(track(1, type: 2, language: "chi", full: "yue")))
        let list = try XCTUnwrap(MatroskaTrackList.read(bytes: late))
        XCTAssertNil(list.tracks)
        XCTAssertEqual(list.writingApplication, "SomeWriter 1.0")
    }

    /// Damaged or foreign input is refused — never guessed at.
    func test_damagedOrForeignInputIsRefused() {
        XCTAssertNil(MatroskaTrackList.read(bytes: []))
        XCTAssertNil(MatroskaTrackList.read(bytes: Array("RIFF....WAVE".utf8)), "not Matroska")
        // A track list claiming more bytes than the file has.
        var truncated = file(tracks(track(1, type: 2, language: "chi", full: "yue")))
        truncated.removeLast(4)
        XCTAssertNil(MatroskaTrackList.read(bytes: truncated)?.tracks)
        // A track entry whose field claims more than its entry holds.
        let broken = file(tracks(element([0xAE], [0xD7, 0x88, 0x01])))
        XCTAssertNil(MatroskaTrackList.read(bytes: broken)?.tracks)
    }

    /// The variable-length numbers EBML uses.
    func test_variableLengthNumbers() {
        XCTAssertEqual(MatroskaTrackList.variableLengthNumber([0x81], at: 0, maxLength: 8, keepMarker: false)?.value, 1)
        XCTAssertEqual(MatroskaTrackList.variableLengthNumber([0x40, 0x02], at: 0, maxLength: 8, keepMarker: false)?.value, 2)
        XCTAssertEqual(MatroskaTrackList.variableLengthNumber([0xFF], at: 0, maxLength: 8, keepMarker: false)?.isUnknown, true)
        XCTAssertEqual(
            MatroskaTrackList.variableLengthNumber([0x1A, 0x45, 0xDF, 0xA3], at: 0, maxLength: 4, keepMarker: true)?.value,
            0x1A45_DFA3
        )
        XCTAssertNil(MatroskaTrackList.variableLengthNumber([0x00], at: 0, maxLength: 8, keepMarker: false))
        XCTAssertNil(MatroskaTrackList.variableLengthNumber([0x08, 0x00], at: 0, maxLength: 4, keepMarker: true), "too long an ID")
    }

    // MARK: - Bounds (third independent review)

    /// The reviewer's shape: a track list of just under 16 MiB made of
    /// EMPTY track entries (`AE 80`, 8,388,000 of them). The first version
    /// copied every one — 32.7 seconds and 631 MB of memory. Now a list of
    /// more than 1,024 entries is "unreadable" as soon as the 1,025th is
    /// seen. Counted (`Effort`), never timed.
    func test_aTrackListOfMoreThan1024EntriesIsRefusedEarly() throws {
        let count = 8_388_000
        var body = [UInt8](repeating: 0x80, count: count * 2)
        for index in stride(from: 0, to: body.count, by: 2) { body[index] = 0xAE }
        var effort = MatroskaTrackList.Effort()
        let list = MatroskaTrackList.read(bytes: file(info("mkvmerge v101.0") + tracks(body)), effort: &effort)
        XCTAssertEqual(list?.writingApplication, "mkvmerge v101.0", "the writer is still read")
        XCTAssertNil(list?.tracks, "more than 1,024 entries: the list is unreadable")
        XCTAssertLessThanOrEqual(effort.elementsVisited, 1_030, "stopped at the 1,025th entry, not after \(count)")

        // 1,024 entries are read; 1,025 are not.
        let entry: [UInt8] = [0xAE, 0x80]
        let limit = MatroskaTrackList.trackEntryLimit
        XCTAssertEqual(limit, 1024)
        let atLimit = Array(Array(repeating: entry, count: limit).joined())
        XCTAssertEqual(MatroskaTrackList.read(bytes: file(tracks(atLimit)))?.tracks?.count, limit)
        XCTAssertNil(MatroskaTrackList.read(bytes: file(tracks(atLimit + entry)))?.tracks)
    }

    /// Filler (EBML `Void`, which writers leave as padding) is stepped over
    /// wherever it is: 5,000 elements of it before the track list — which
    /// stopped the first version reading at all, as each counted against its
    /// 4,096-element limit — 100,000 inside the track list, and some between
    /// a track entry's fields. Counted (`Effort`), never timed.
    func test_fillerIsSteppedOver() throws {
        let void: [UInt8] = [0xEC, 0x80]
        let before = file(Array(Array(repeating: void, count: 5000).joined())
                          + info("mkvmerge v101.0") + tracks(track(1, type: 2, language: "chi", full: "yue")))
        var effort = MatroskaTrackList.Effort()
        let list = MatroskaTrackList.read(bytes: before, effort: &effort)
        XCTAssertEqual(list?.writingApplication, "mkvmerge v101.0")
        XCTAssertEqual(list?.tracks, [.init(number: 1, type: 2, language: "chi", languageBCP47: "yue")])
        XCTAssertEqual(effort.fillerSkipped, 5000)

        let inside = file(tracks(track(1, type: 2, language: "chi", full: "yue")
                                 + Array(Array(repeating: void, count: 100_000).joined())
                                 + track(2, type: 2, language: "fre", full: "fr-CA")))
        effort = MatroskaTrackList.Effort()
        XCTAssertEqual(MatroskaTrackList.read(bytes: inside, effort: &effort)?.tracks?.map(\.languageBCP47), ["yue", "fr-CA"])
        XCTAssertEqual(effort.fillerSkipped, 100_000)

        // Filler among a track entry's own fields (a two-byte and a
        // four-byte `Void`).
        let entry = element([0xAE], uint([0xD7], 1) + void + uint([0x83], 2) + [0xEC, 0x82, 0x00, 0x00]
                            + text([0x22, 0xB5, 0x9D], "yue"))
        XCTAssertEqual(MatroskaTrackList.read(bytes: file(tracks(entry)))?.tracks,
                       [.init(number: 1, type: 2, language: nil, languageBCP47: "yue")])
    }

    // MARK: - Matching ffprobe's streams

    private func stream(_ index: Int, _ type: StreamType, language: String? = nil, picture: Bool = false) -> MediaStream {
        MediaStream(streamIndex: index, streamType: type, language: language, languageAsStored: language,
                    disposition: StreamDisposition(isAttachedPicture: picture))
    }

    func test_tracksAreMatchedToStreamsByOrderAndType() throws {
        let list = try XCTUnwrap(MatroskaTrackList.read(bytes: mkvmergeLike))
        let streams = [stream(0, .video), stream(1, .audio), stream(2, .audio), stream(3, .subtitle),
                       stream(4, .attachment), stream(5, .video, picture: true)]
        let matched = try XCTUnwrap(list.streamsMatched(to: streams))
        XCTAssertEqual(matched[1]?.languageBCP47, "yue")
        XCTAssertEqual(matched[2]?.languageBCP47, "fr-CA")
        XCTAssertNil(matched[4], "attachments come after the tracks")
        // A different count or a different type: no match at all.
        XCTAssertNil(list.streamsMatched(to: Array(streams.prefix(3))))
        XCTAssertNil(list.streamsMatched(to: [stream(0, .video), stream(1, .audio), stream(2, .subtitle), stream(3, .subtitle)]))
    }

    func test_whoMayHaveWrittenFullTags() {
        XCTAssertFalse(MatroskaTrackList.mayHoldFullLanguageTags(writtenBy: "Lavf63.1.101"))
        XCTAssertTrue(MatroskaTrackList.mayHoldFullLanguageTags(writtenBy: "mkvmerge v101.0 ('Time To Turn') 64-bit"))
        XCTAssertTrue(MatroskaTrackList.mayHoldFullLanguageTags(writtenBy: nil), "cannot tell counts as may")
    }

    // MARK: - The probe

    /// Writes `bytes` to a scratch file and returns its URL.
    private func scratch(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-mkl-\(UUID().uuidString).mkv")
        try Data(bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// The probe takes the full tag and keeps the old field's text.
    func test_theProbeTakesTheFullTag() throws {
        let url = try scratch(mkvmergeLike)
        let probed = [stream(0, .video), stream(1, .audio, language: "zh"), stream(2, .audio, language: "fr"),
                      stream(3, .subtitle, language: "en")]
        var withText = probed
        withText[1].languageAsStored = "chi"
        withText[2].languageAsStored = "fre"
        let streams = FFmpegProbe.applyingMatroskaFullLanguageTags(
            to: withText, fileURL: url, formatName: "matroska,webm", statisticsWritingApplication: nil
        )
        XCTAssertEqual(streams.map(\.language), ["und", "yue", "fr-CA", "en"])
        // The video's old field says `und`, which ffprobe hides: an EMPTY
        // text records that ffmpeg copies nothing (not `nil`, "not known").
        XCTAssertEqual(streams.map(\.languageAsStored), ["", "chi", "fre", "en"])
        XCTAssertEqual(streams.map(\.languageFullTagUnknown), [nil, nil, nil, nil])
        // Not Matroska: unchanged.
        XCTAssertEqual(FFmpegProbe.applyingMatroskaFullLanguageTags(
            to: withText, fileURL: url, formatName: "mov,mp4,m4a,3gp,3g2,mj2", statisticsWritingApplication: nil
        ).map(\.language), withText.map(\.language))
    }

    /// A full tag that is not a well-formed language tag — damaged text, or
    /// text with a control character — never replaces the old field: the
    /// old field's reading stands, and the stream records the ignored tag
    /// (for the job's note). The stand-in review of round 5 found
    /// `en_GB!x?a12` over a valid `eng` turned into "not known".
    func test_aDamagedFullTagNeverOverridesTheOldField() throws {
        let bytes = file(info("mkvmerge v101.0 ('Time To Turn') 64-bit")
            + tracks(track(1, type: 2, language: "eng", full: "en_GB!x?a12")
                     + track(2, type: 2, language: "und", full: "1#3")
                     + track(3, type: 2, language: "eng", full: "en\u{01}-GB")
                     + track(4, type: 2, language: "eng", full: "en-GB"))
            + cluster)
        let probed = [stream(0, .audio, language: "en"), stream(1, .audio), stream(2, .audio, language: "en"),
                      stream(3, .audio, language: "en")]
        var withText = probed
        for index in [0, 2, 3] { withText[index].languageAsStored = "eng" }
        let streams = FFmpegProbe.applyingMatroskaFullLanguageTags(
            to: withText, fileURL: try scratch(bytes), formatName: "matroska,webm", statisticsWritingApplication: nil
        )
        XCTAssertEqual(streams.map(\.language), ["en", nil, "en", "en-GB"], "only a real tag replaces the old field")
        XCTAssertEqual(streams.map(\.unrecognisedLanguage), [nil, nil, nil, nil])
        XCTAssertEqual(streams.map(\.languageAsStored), ["eng", nil, "eng", "eng"], "what ffmpeg copies, unchanged")
        XCTAssertEqual(streams.map(\.ignoredFullLanguageTag),
                       [.notATag("en_GB!x?a12"), .notATag("1#3"), .notATag("en\u{FFFD}-GB"), nil],
                       "a control character is damage: the tag is ignored, the character shown as �")
    }

    /// A full tag longer than the reader reads (256 bytes) is refused — the
    /// old field's language stands — never cut to a shorter, different tag
    /// (the stand-in review of round 5: cut to 64 characters, and written).
    func test_aFullTagLongerThanTheReaderReadsIsRefusedNotCut() throws {
        let long = "en-GB-x-" + Array(repeating: "abcdefgh", count: 36).joined(separator: "-")
        let bytes = file(info("mkvmerge v101.0 ('Time To Turn') 64-bit")
            + tracks(track(1, type: 2, language: "eng", full: long)) + cluster)
        let list = try XCTUnwrap(MatroskaTrackList.read(bytes: bytes))
        XCTAssertEqual(list.tracks, [.init(number: 1, type: 2, language: "eng", languageBCP47: nil, languageBCP47TooLong: true)])
        var probed = [stream(0, .audio, language: "en")]
        probed[0].languageAsStored = "eng"
        let streams = FFmpegProbe.applyingMatroskaFullLanguageTags(
            to: probed, fileURL: try scratch(bytes), formatName: "matroska,webm", statisticsWritingApplication: nil
        )
        XCTAssertEqual(streams.map(\.language), ["en"])
        XCTAssertEqual(streams.map(\.ignoredFullLanguageTag), [.tooLong(maximumBytes: 256)])
        XCTAssertEqual(streams.map(\.languageAsStored), ["eng"])
    }

    /// When the track list cannot be read, a file whose writer may have
    /// written full tags has its tracks marked; one written by ffmpeg is not.
    func test_anUnreadableTrackListMarksTheTracksUnlessFFmpegWroteTheFile() throws {
        let url = try scratch(file(info("mkvmerge v101.0") + cluster + tracks(track(1, type: 2, language: "chi", full: "yue"))))
        let streams = [stream(0, .audio, language: "zh")]
        XCTAssertEqual(FFmpegProbe.applyingMatroskaFullLanguageTags(
            to: streams, fileURL: url, formatName: "matroska,webm", statisticsWritingApplication: nil
        ).map(\.languageFullTagUnknown), [true])

        let byFFmpeg = try scratch(file(info("Lavf63.1.101") + cluster))
        XCTAssertEqual(FFmpegProbe.applyingMatroskaFullLanguageTags(
            to: streams, fileURL: byFFmpeg, formatName: "matroska,webm", statisticsWritingApplication: nil
        ).map(\.languageFullTagUnknown), [nil])

        // Nothing readable at all, and no writer named: cannot tell, so marked.
        let missing = URL(fileURLWithPath: "/nonexistent/meedya-\(UUID().uuidString).mkv")
        XCTAssertEqual(FFmpegProbe.applyingMatroskaFullLanguageTags(
            to: streams, fileURL: missing, formatName: "matroska,webm", statisticsWritingApplication: nil
        ).map(\.languageFullTagUnknown), [true])
        // ffprobe's own statistics tag names the writer when the file cannot.
        XCTAssertEqual(FFmpegProbe.applyingMatroskaFullLanguageTags(
            to: streams, fileURL: missing, formatName: "matroska,webm", statisticsWritingApplication: "Lavf63.1.101"
        ).map(\.languageFullTagUnknown), [nil])
    }

    // MARK: - The argument builder

    /// A marked track gets a note and no automatic title from its old code.
    func test_aMarkedTrackIsNotedAndGetsNoAutomaticTitle() {
        var marked = stream(1, .audio, language: "zh")
        marked.languageAsStored = "chi"
        marked.languageFullTagUnknown = true
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mkv")
        builder.sourceStreams = [stream(0, .video), marked, stream(2, .audio, language: "en")]
        builder.mapAllStreams = true
        builder.videoPassthrough = true
        builder.audioPassthrough = true
        let args = builder.build()
        let titles = zip(args, args.dropFirst()).filter { $0.1.hasPrefix("title=") }.map(\.1)
        XCTAssertEqual(titles, ["title=English"], "only the unmarked track is named")
        XCTAssertEqual(builder.trackWritingNotes(), [
            "Stream #1: The source may also record a fuller language for this track (with a region or script, "
                + "say), which could not be read; if it does, that is not kept, and no automatic title is made from "
                + "the three-letter code “chi”."
        ])
    }

    // MARK: - With the real tools

    /// Runs a tool and returns its exit code and standard output.
    @discardableResult
    private func run(_ path: String, _ arguments: [String]) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    /// The review's case end to end: five tracks tagged by mkvmerge as
    /// `yue`, `cmn`, `nan`, `fr-CA` and `apc` (Levantine Arabic), remuxed
    /// with MeedyaConverter's own arguments to MKV, MP4 and MOV. mkvmerge
    /// writes the old field as `chi`, `chi`, `chi`, `fre` and `ara`. None may
    /// become `chi`, `fre` or `ara`, and Cantonese must never be titled
    /// "中文".
    ///
    /// MOV (the third independent review's must-fix): its field holds only
    /// ffmpeg's QuickTime list, which has none of `yue`, `cmn`, `nan`, `apc`
    /// — so each must come out with NO language, and each note must say so
    /// truthfully. The round-3 build gave ffmpeg nothing for them, so ffmpeg
    /// copied the old field in: `chi` (which Apple's players read as
    /// Traditional Chinese) and `ara`, under a note saying "no language is
    /// stored". Read back with ffprobe AND with Apple's AVFoundation.
    /// Skipped without ffmpeg, ffprobe and mkvmerge — FAILED without them
    /// in CI's build-and-test job (`MediaTools.missing`).
    func test_aRealMkvmergeFileKeepsItsLanguages() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe"),
              let mkvmerge = MediaTools.find("mkvmerge") else {
            try MediaTools.missing("ffmpeg, ffprobe or mkvmerge not installed")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-mkvmerge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let plain = folder.appendingPathComponent("plain.mkv")
        var arguments = ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=64x48:rate=5:duration=0.4"]
        for frequency in [440, 550, 660, 770, 880] {
            arguments += ["-f", "lavfi", "-i", "sine=frequency=\(frequency):duration=0.4"]
        }
        arguments += ["-map", "0", "-map", "1", "-map", "2", "-map", "3", "-map", "4", "-map", "5",
                      "-c:v", "mpeg4", "-c:a", "aac", plain.path]
        XCTAssertEqual(try run(ffmpeg, arguments).status, 0, "making the source")

        let tagged = folder.appendingPathComponent("tagged.mkv")
        let merged = try run(mkvmerge, ["-q", "-o", tagged.path, "--language", "1:yue", "--language", "2:cmn",
                                        "--language", "3:nan", "--language", "4:fr-CA", "--language", "5:apc", plain.path])
        XCTAssertLessThan(merged.status, 2, "mkvmerge (1 is warnings only)")

        let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: tagged)
        let audio = probed.streams.filter { $0.streamType == .audio }
        XCTAssertEqual(audio.map(\.language), ["yue", "cmn", "nan", "fr-CA", "apc"], "the full tags win")
        XCTAssertEqual(audio.map(\.languageAsStored), ["chi", "chi", "chi", "fre", "ara"], "what ffmpeg would copy")

        // Each output: what ffprobe must read for each audio track, in order.
        // `nil` = no language at all.
        let cases: [(name: String, container: ContainerFormat, expected: [String?])] = [
            ("out.mkv", .mkv, ["yue", "cmn", "nan", "fr-CA", "apc"]),
            ("out.mp4", .mp4, ["yue", "cmn", "nan", "fra", "apc"]),
            ("out.mov", .mov, [nil, nil, nil, "fra", nil])
        ]
        for (name, container, expected) in cases {
            let output = folder.appendingPathComponent(name)
            var profile = container == .mkv ? EncodingProfile.remuxToMKV : EncodingProfile.remuxToMP4
            profile.containerFormat = container
            profile.orderTracksCanonically = false
            var config = EncodingJobConfig(inputURL: tagged, outputURL: output, profile: profile)
            config.sourceStreams = probed.streams
            XCTAssertEqual(try run(ffmpeg, ["-v", "error"] + config.buildArguments()).status, 0, "encoding \(name)")
            let (status, data) = try run(ffprobe, ["-v", "error", "-print_format", "json", "-show_entries",
                                                   "stream=codec_type:stream_tags=language,title", output.path])
            XCTAssertEqual(status, 0)
            let streams = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["streams"] as? [[String: Any]] ?? []
            let tags = streams.filter { $0["codec_type"] as? String == "audio" }.map { $0["tags"] as? [String: Any] ?? [:] }
            XCTAssertEqual(tags.map { $0["language"] as? String }, expected, "\(name): no chi, fre or ara")
            if container == .mkv {
                let cantonese = tags.first { $0["language"] as? String == "yue" }
                XCTAssertNotNil(cantonese, "\(name): Cantonese is there")
                XCTAssertNotEqual(cantonese?["title"] as? String, "中文", "\(name): Cantonese is not titled 中文")
            }
            XCTAssertEqual(config.trackWritingNotes().count, 5, "\(name): each is reported")
            if container == .mov {
                // The notes say what the file really holds.
                for (stream, tag) in [(1, "yue"), (2, "cmn"), (3, "nan"), (5, "apc")] {
                    XCTAssertTrue(config.trackWritingNotes().contains(
                        "Stream #\(stream): this file type (QuickTime) can only store the languages on its old list, "
                            + "and “\(tag)” is not on it, so no language is stored."
                    ), "\(name): the note for \(tag)")
                }
                // And Apple's players read the same: no language on the four,
                // French on the fifth — never Traditional Chinese or Arabic.
                if let apple = try await MediaTools.appleAudioLanguages(of: output) {
                    XCTAssertEqual(apple.map(\.isNone), [true, true, true, false, true], "\(name): AVFoundation \(apple)")
                    XCTAssertEqual(apple.dropFirst(3).first?.code, "fra", "\(name): AVFoundation \(apple)")
                }
            }
        }
    }

    /// The audio languages ffprobe reads from `url`, in order (`nil` = none).
    private func audioLanguages(_ ffprobe: String, _ url: URL) throws -> [String?] {
        let (status, data) = try run(ffprobe, ["-v", "error", "-print_format", "json", "-show_entries",
                                               "stream=codec_type:stream_tags=language", url.path])
        XCTAssertEqual(status, 0, "ffprobe \(url.lastPathComponent)")
        let streams = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["streams"] as? [[String: Any]] ?? []
        return streams.filter { $0["codec_type"] as? String == "audio" }
            .map { ($0["tags"] as? [String: Any])?["language"] as? String }
    }

    /// The audio languages mkvmerge reads from `url` (its `language` field).
    private func mkvmergeAudioLanguages(_ mkvmerge: String, _ url: URL) throws -> [String?] {
        let (status, data) = try run(mkvmerge, ["-J", url.path])
        XCTAssertEqual(status, 0, "mkvmerge -J \(url.lastPathComponent)")
        let tracks = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["tracks"] as? [[String: Any]] ?? []
        return tracks.filter { $0["type"] as? String == "audio" }
            .map { ($0["properties"] as? [String: Any])?["language"] as? String }
    }

    /// The stand-in review of round 5, with real tools: mkvmerge writes `eng`
    /// and `en-GB` for an English (UK) track; with the full tag damaged in
    /// the file (`e?-GB`, same length), mkvmerge itself reads the track as
    /// `eng` — and so must the converter. Round 5 wrote the damaged text
    /// into Matroska ("kept as the source had it") and nothing into MP4 and
    /// MOV. Now each output gets `eng`, and the note says the full tag was
    /// ignored and not kept. Read back with ffprobe, mkvmerge and Apple's
    /// AVFoundation. Skipped without the tools — FAILED in CI without them.
    func test_aDamagedFullTagLeavesTheOldFieldsLanguage() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe"),
              let mkvmerge = MediaTools.find("mkvmerge") else {
            try MediaTools.missing("ffmpeg, ffprobe or mkvmerge not installed")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-damaged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = folder.appendingPathComponent("plain.mkv")
        XCTAssertEqual(try run(ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=64x48:rate=5:duration=0.4",
                                        "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4", "-map", "0", "-map", "1",
                                        "-c:v", "mpeg4", "-c:a", "aac", plain.path]).status, 0, "making the source")
        let tagged = folder.appendingPathComponent("tagged.mkv")
        XCTAssertLessThan(try run(mkvmerge, ["-q", "-o", tagged.path, "--language", "1:en-GB", plain.path]).status, 2)
        // Damage the full tag in place: LanguageBCP47 (22 B5 9D), size 5.
        var bytes = [UInt8](try Data(contentsOf: tagged))
        let field: [UInt8] = [0x22, 0xB5, 0x9D, 0x85] + Array("en-GB".utf8)
        let at = try XCTUnwrap((0...(bytes.count - field.count)).first { Array(bytes[$0..<$0 + field.count]) == field })
        bytes.replaceSubrange(at + 4..<at + 9, with: Array("e?-GB".utf8))
        let damaged = folder.appendingPathComponent("damaged.mkv")
        try Data(bytes).write(to: damaged)
        XCTAssertEqual(try mkvmergeAudioLanguages(mkvmerge, damaged), ["eng"], "mkvmerge reads the old field")

        let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: damaged)
        let audio = try XCTUnwrap(probed.streams.first { $0.streamType == .audio })
        XCTAssertEqual(audio.language, "en")
        XCTAssertEqual(audio.ignoredFullLanguageTag, .notATag("e?-GB"))
        let note = "Stream #1: The source also records a full language tag for this track, “e?-GB”, which is not a "
            + "valid language tag, so it is ignored and not kept; the language is taken from the track's old language "
            + "field (“eng”)."
        for (name, container) in [("out.mkv", ContainerFormat.mkv), ("out.mp4", .mp4), ("out.mov", .mov)] {
            var profile = container == .mkv ? EncodingProfile.remuxToMKV : EncodingProfile.remuxToMP4
            profile.containerFormat = container
            let output = folder.appendingPathComponent(name)
            var config = EncodingJobConfig(inputURL: damaged, outputURL: output, profile: profile)
            config.sourceStreams = probed.streams
            XCTAssertEqual(try run(ffmpeg, ["-v", "error"] + config.buildArguments()).status, 0, "encoding \(name)")
            XCTAssertEqual(config.trackWritingNotes(), [note], name)
            XCTAssertEqual(try audioLanguages(ffprobe, output), ["eng"], "\(name): ffprobe")
            if container == .mkv {
                XCTAssertEqual(try mkvmergeAudioLanguages(mkvmerge, output), ["eng"], "\(name): mkvmerge")
            } else if let apple = try await MediaTools.appleAudioLanguages(of: output) {
                XCTAssertEqual(apple.map(\.code), ["eng"], "\(name): AVFoundation")
            }
        }
    }

    /// The fourth independent review's case: a language with NO three-letter
    /// code of its own — Abaza `abq`, Western Panjabi `pnb` — and the tags
    /// `und-x-foo`, `und-Latn`, `und-419`. mkvmerge writes `und` in the old
    /// field for every one of them, and ffprobe hides `und`, so ffmpeg has
    /// NOTHING to copy. The round-4 build left the field "for ffmpeg to
    /// copy" anyway: Matroska, MP4 and MPEG-TS outputs lost `abq` and `pnb`
    /// (and Matroska the three `und-…` tags) under the note "kept as the
    /// source had it". Now the tag is written as text wherever the file type
    /// keeps it; MP4 and MPEG-TS, which hold three letters, get `und` for the
    /// `und-…` tags with a note saying what is not saved. MOV (none of them
    /// is on its list: no language, noted) and Ogg (the whole tag) are as
    /// they were. Read back with ffprobe, with mkvmerge (Matroska) and with
    /// Apple's AVFoundation (MP4, MOV). Skipped without ffmpeg, ffprobe and
    /// mkvmerge — FAILED without them in CI's build-and-test job.
    func test_aFullTagOverAnOldFieldThatSaysUndIsWritten() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe"),
              let mkvmerge = MediaTools.find("mkvmerge") else {
            try MediaTools.missing("ffmpeg, ffprobe or mkvmerge not installed")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-undfield-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let tags = ["abq", "pnb", "und-x-foo", "und-Latn", "und-419"]
        let plain = folder.appendingPathComponent("plain.mkv")
        var arguments = ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=64x48:rate=5:duration=0.4"]
        for frequency in [440, 550, 660, 770, 880] {
            arguments += ["-f", "lavfi", "-i", "sine=frequency=\(frequency):duration=0.4"]
        }
        arguments += ["-map", "0", "-map", "1", "-map", "2", "-map", "3", "-map", "4", "-map", "5",
                      "-c:v", "mpeg4", "-c:a", "aac", plain.path]
        XCTAssertEqual(try run(ffmpeg, arguments).status, 0, "making the source")
        let tagged = folder.appendingPathComponent("tagged.mkv")
        var merge = ["-q", "-o", tagged.path]
        for (track, tag) in tags.enumerated() { merge += ["--language", "\(track + 1):\(tag)"] }
        XCTAssertLessThan(try run(mkvmerge, merge + [plain.path]).status, 2, "mkvmerge (1 is warnings only)")
        XCTAssertEqual(try mkvmergeAudioLanguages(mkvmerge, tagged), ["und", "und", "und", "und", "und"],
                       "mkvmerge writes `und` in the old field")

        let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: tagged)
        let audio = probed.streams.filter { $0.streamType == .audio }
        XCTAssertEqual(audio.map(\.language), tags, "the full tags win")
        XCTAssertEqual(audio.map(\.languageAsStored), ["", "", "", "", ""], "ffmpeg copies nothing")

        let because = "because copying the source's old field (which ffmpeg reads as holding no language) would not keep it."
        func convert(_ name: String, _ profile: EncodingProfile) throws -> (URL, [String]) {
            let output = folder.appendingPathComponent(name)
            var profile = profile
            profile.orderTracksCanonically = false
            var config = EncodingJobConfig(inputURL: tagged, outputURL: output, profile: profile)
            config.sourceStreams = probed.streams
            config.mapAllStreams = profile.containerFormat == .ogg
            XCTAssertEqual(try run(ffmpeg, ["-v", "error"] + config.buildArguments()).status, 0, "encoding \(name)")
            let notes = config.trackWritingNotes()
            XCTAssertFalse(notes.contains { $0.contains("kept as the source had it") }, "\(name): nothing is \"kept\"")
            return (output, notes)
        }

        // Matroska keeps any text: every tag, as text.
        var mkv = EncodingProfile.remuxToMKV
        mkv.containerFormat = .mkv
        let (mkvOut, mkvNotes) = try convert("out.mkv", mkv)
        XCTAssertEqual(try audioLanguages(ffprobe, mkvOut), tags, "out.mkv: ffprobe")
        XCTAssertEqual(try mkvmergeAudioLanguages(mkvmerge, mkvOut), ["abq", "pnb", "und", "und", "und"],
                       "out.mkv: mkvmerge reads the language of each text")
        XCTAssertEqual(mkvNotes.count, 5)
        XCTAssertTrue(mkvNotes.allSatisfy { $0.hasSuffix("is written into the field as it is, " + because) }, "\(mkvNotes)")

        // MP4 and MPEG-TS hold three letters: `abq` and `pnb` as they are;
        // `und` for the `und-…` tags, saying what is not saved.
        for (name, container) in [("out.mp4", ContainerFormat.mp4), ("out.ts", .mpegTS)] {
            var profile = EncodingProfile.remuxToMP4
            profile.containerFormat = container
            let (output, notes) = try convert(name, profile)
            XCTAssertEqual(try audioLanguages(ffprobe, output), ["abq", "pnb", "und", "und", "und"], "\(name): ffprobe")
            XCTAssertEqual(notes, [
                "Stream #1: language “abq” has no code on the older three-letter list (ISO 639-2), so “abq” is written into the field as it is, " + because,
                "Stream #2: language “pnb” has no code on the older three-letter list (ISO 639-2), so “pnb” is written into the field as it is, " + because,
                "Stream #3: this file type can only store the language, so “x-foo” in “und-x-foo” is not saved "
                    + "(written as “und”).",
                "Stream #4: this file type can only store the language, so “Latn” in “und-Latn” is not saved "
                    + "(written as “und”).",
                "Stream #5: this file type can only store the language, so “419” in “und-419” is not saved "
                    + "(written as “und”)."
            ], name)
            if container == .mp4, let apple = try await MediaTools.appleAudioLanguages(of: output) {
                XCTAssertEqual(apple.map(\.code), ["abq", "pnb", "und", "und", "und"], "\(name): AVFoundation \(apple)")
            }
        }

        // MOV: none of them is on its list — no language, each noted (as before).
        var mov = EncodingProfile.remuxToMKV
        mov.containerFormat = .mov
        let (movOut, movNotes) = try convert("out.mov", mov)
        XCTAssertEqual(try audioLanguages(ffprobe, movOut), [nil, nil, nil, nil, nil], "out.mov: ffprobe")
        XCTAssertEqual(movNotes, tags.enumerated().map {
            "Stream #\($0.offset + 1): this file type (QuickTime) can only store the languages on its old list, and "
                + "“\($0.element)” is not on it, so no language is stored."
        })
        if let apple = try await MediaTools.appleAudioLanguages(of: movOut) {
            XCTAssertEqual(apple.map(\.isNone), [true, true, true, true, true], "out.mov: AVFoundation \(apple)")
        }

        // Ogg: the whole tag (as before). Needs the Opus encoder; checked
        // last, so the cases above run on any machine with the tools.
        let encoders = String(decoding: try run(ffmpeg, ["-hide_banner", "-encoders"]).output, as: UTF8.self)
        guard encoders.contains(" libopus ") else { try MediaTools.missing("this ffmpeg has no libopus (the Ogg case)") }
        var ogg = EncodingProfile.audioExtract
        ogg.audioCodec = .opus
        ogg.containerFormat = .ogg
        let (oggOut, oggNotes) = try convert("out.ogg", ogg)
        XCTAssertEqual(try audioLanguages(ffprobe, oggOut), tags, "out.ogg: ffprobe")
        XCTAssertEqual(oggNotes, [], "out.ogg: the whole tag is kept")
    }
}
