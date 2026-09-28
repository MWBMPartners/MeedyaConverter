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
//     way through MeedyaConverter's own arguments (skipped otherwise).
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
        XCTAssertEqual(streams.map(\.languageAsStored), [nil, "chi", "fre", "en"])
        XCTAssertEqual(streams.map(\.languageFullTagUnknown), [nil, nil, nil, nil])
        // Not Matroska: unchanged.
        XCTAssertEqual(FFmpegProbe.applyingMatroskaFullLanguageTags(
            to: withText, fileURL: url, formatName: "mov,mp4,m4a,3gp,3g2,mj2", statisticsWritingApplication: nil
        ).map(\.language), withText.map(\.language))
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
            "Stream #1: The source may also record a fuller language tag for this track (with a region or script, "
                + "say), which could not be read; if it does, that is not kept, and no automatic title is made from "
                + "the three-letter code “chi”."
        ])
    }

    // MARK: - With the real tools

    /// The first executable found for `name` in the usual places.
    private func tool(_ name: String) -> String? {
        let folders = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return folders.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

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

    /// The review's case end to end: four tracks tagged by mkvmerge as
    /// `yue`, `cmn`, `nan` and `fr-CA`, remuxed with MeedyaConverter's own
    /// arguments to MKV and to MP4. None may become `chi` or `fre`, and
    /// Cantonese must never be titled "中文". Skipped without ffmpeg,
    /// ffprobe and mkvmerge.
    func test_aRealMkvmergeFileKeepsItsLanguages() async throws {
        guard let ffmpeg = tool("ffmpeg"), let ffprobe = tool("ffprobe"), let mkvmerge = tool("mkvmerge") else {
            throw XCTSkip("ffmpeg, ffprobe or mkvmerge not installed")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-mkvmerge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let plain = folder.appendingPathComponent("plain.mkv")
        var arguments = ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=64x48:rate=5:duration=0.4"]
        for frequency in [440, 550, 660, 770] {
            arguments += ["-f", "lavfi", "-i", "sine=frequency=\(frequency):duration=0.4"]
        }
        arguments += ["-map", "0", "-map", "1", "-map", "2", "-map", "3", "-map", "4", "-c:v", "mpeg4", "-c:a", "aac", plain.path]
        XCTAssertEqual(try run(ffmpeg, arguments).status, 0, "making the source")

        let tagged = folder.appendingPathComponent("tagged.mkv")
        let merged = try run(mkvmerge, ["-q", "-o", tagged.path, "--language", "1:yue", "--language", "2:cmn",
                                        "--language", "3:nan", "--language", "4:fr-CA", plain.path])
        XCTAssertLessThan(merged.status, 2, "mkvmerge (1 is warnings only)")

        let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: tagged)
        let audio = probed.streams.filter { $0.streamType == .audio }
        XCTAssertEqual(audio.map(\.language), ["yue", "cmn", "nan", "fr-CA"], "the full tags win")
        XCTAssertEqual(audio.map(\.languageAsStored), ["chi", "chi", "chi", "fre"], "what ffmpeg would copy")

        for (name, container, expected) in [
            ("out.mkv", ContainerFormat.mkv, ["cmn", "fr-CA", "nan", "yue"]),
            ("out.mp4", ContainerFormat.mp4, ["cmn", "fra", "nan", "yue"])
        ] {
            let output = folder.appendingPathComponent(name)
            var profile = container == .mkv ? EncodingProfile.remuxToMKV : EncodingProfile.remuxToMP4
            profile.orderTracksCanonically = false
            var config = EncodingJobConfig(inputURL: tagged, outputURL: output, profile: profile)
            config.sourceStreams = probed.streams
            XCTAssertEqual(try run(ffmpeg, ["-v", "error"] + config.buildArguments()).status, 0, "encoding \(name)")
            let (status, data) = try run(ffprobe, ["-v", "error", "-print_format", "json", "-show_entries",
                                                   "stream=codec_type:stream_tags=language,title", output.path])
            XCTAssertEqual(status, 0)
            let streams = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["streams"] as? [[String: Any]] ?? []
            let tags = streams.filter { $0["codec_type"] as? String == "audio" }.map { $0["tags"] as? [String: Any] ?? [:] }
            XCTAssertEqual(tags.compactMap { $0["language"] as? String }.sorted(), expected, "\(name): no chi or fre")
            let cantonese = tags.first { $0["language"] as? String == "yue" }
            XCTAssertNotNil(cantonese, "\(name): Cantonese is there")
            XCTAssertNotEqual(cantonese?["title"] as? String, "中文", "\(name): Cantonese is not titled 中文")
            XCTAssertEqual(config.trackWritingNotes().count, 4, "\(name): each is reported")
        }
    }
}
