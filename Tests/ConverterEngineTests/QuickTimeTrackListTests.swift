// ============================================================================
// MeedyaConverter — QuickTimeTrackListTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// A MOV or MP4 track's language is a NUMBER in its media header, and Apple's
// players read the number: 19 is Traditional Chinese, 33 Simplified — both
// `chi` to ffprobe — and 5 is Swedish, although ffprobe's `sve` is the
// registered code of Serili. The fourth independent review of the language
// policy work found a MOV's Traditional-Chinese track read as plain Chinese,
// so a MOV-to-MOV remux stored no language at all, and a MOV's Swedish read
// as Serili. These tests pin the fix:
//
//   * `QuickTimeTrackList` reads each track's handler, language number and
//     full tag (`elng`) from bytes built here by hand (so the reader is
//     checked without any tool installed), and refuses anything it cannot
//     read with certainty;
//   * the probe reads each language as Apple's players do, and the table it
//     uses (`TrackLanguage.quickTimeNumbers`) is checked against Apple's
//     AVFoundation for every number;
//   * with ffmpeg installed, MOV files go all the way through
//     MeedyaConverter's own arguments to MOV, MP4 and Matroska, read back
//     with ffprobe and AVFoundation (skipped otherwise — FAILED in CI's
//     build-and-test job, which installs and requires the tools).
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class QuickTimeTrackListTests: XCTestCase {

    // MARK: - Building boxes by hand

    /// A box: a 32-bit size, a four-letter type, its data.
    private func box(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let size = UInt32(8 + data.count)
        return [UInt8(size >> 24), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)]
            + Array(type.utf8) + data
    }

    /// A media header (`mdhd`) holding language `code`, version 0 or 1.
    private func mdhd(_ code: UInt16, version: UInt8 = 0) -> [UInt8] {
        let times = [UInt8](repeating: 0, count: version == 0 ? 16 : 28)
        return box("mdhd", [version, 0, 0, 0] + times + [UInt8(code >> 8), UInt8(code & 0xFF), 0, 0])
    }

    /// A handler (`hdlr`) of type `handler`.
    private func hdlr(_ handler: String) -> [UInt8] {
        box("hdlr", [0, 0, 0, 0] + Array("mhlr".utf8) + Array(handler.utf8) + [UInt8](repeating: 0, count: 13))
    }

    /// An extended language box (`elng`) holding `tag`.
    private func elng(_ tag: String) -> [UInt8] {
        box("elng", [0, 0, 0, 0] + Array(tag.utf8) + [0])
    }

    /// A track whose `mdia` holds `children`.
    private func trak(_ children: [UInt8]) -> [UInt8] {
        box("trak", box("tkhd", [UInt8](repeating: 0, count: 84)) + box("mdia", children))
    }

    /// Three packed letters, as an MP4 stores `swe`.
    private func packed(_ letters: String) -> UInt16 {
        letters.utf8.reduce(UInt16(0)) { ($0 << 5) | (UInt16($1) - 0x60) }
    }

    private let ftyp: [UInt8] = [0, 0, 0, 20] + Array("ftypqt  ".utf8) + [0, 0, 2, 0] + Array("qt  ".utf8)

    /// An `ftyp` box with main brand `major` and compatible brands `compatible`.
    private func fileType(_ major: String, _ compatible: [String]) -> [UInt8] {
        box("ftyp", Array(major.utf8) + [0, 0, 2, 0] + Array(compatible.joined().utf8))
    }

    /// A MOV like ffmpeg's: video; audio with Macintosh number 19 (`chi`);
    /// audio with packed `swe` and a full tag; a subtitle track.
    private var movie: [UInt8] {
        ftyp + box("moov", box("mvhd", [UInt8](repeating: 0, count: 100))
            + trak(mdhd(0x7FFF) + hdlr("vide"))
            + trak(hdlr("soun") + mdhd(19))
            + trak(mdhd(packed("swe"), version: 1) + hdlr("soun") + elng("sv-SE"))
            + trak(hdlr("sbtl") + mdhd(0)))
            + box("mdat", [1, 2, 3])
    }

    // MARK: - Reading

    func test_readsHandlerNumberAndFullTagOfEachTrack() throws {
        let list = try XCTUnwrap(QuickTimeTrackList.read(bytes: movie))
        XCTAssertEqual(list.tracks, [
            .init(handler: "vide", languageCode: 0x7FFF, extendedLanguage: nil),
            .init(handler: "soun", languageCode: 19, extendedLanguage: nil),
            .init(handler: "soun", languageCode: packed("swe"), extendedLanguage: "sv-SE"),
            .init(handler: "sbtl", languageCode: 0, extendedLanguage: nil)
        ])
        XCTAssertEqual(list.tracks.map(\.hasMacintoshLanguageNumber), [false, true, false, true])
    }

    /// Whether the file is a QuickTime movie — where Apple's players read a
    /// number below 0x400 as a Macintosh language — is its `ftyp` box's
    /// brands: `qt  ` as the main brand or a compatible one, or no `ftyp`
    /// box before the movie header at all (an old QuickTime movie). Any
    /// other is an MP4. A file-type box too large to be real: unreadable.
    func test_theFileTypeSaysWhetherItIsAQuickTimeMovie() {
        let movieHeader = box("moov", trak(hdlr("soun") + mdhd(2)))
        let cases: [(String, [UInt8], Bool)] = [
            ("ffmpeg's MOV", ftyp, true),
            ("MP4", fileType("isom", ["isom", "iso2", "mp41"]), false),
            ("M4A", fileType("M4A ", ["M4A ", "isom"]), false),
            ("MP4 brand, QuickTime compatible", fileType("isom", ["isom", "qt  "]), true),
            ("QuickTime brand only", fileType("qt  ", ["isom"]), true),
            ("no ftyp", [], true)
        ]
        for (name, head, quickTime) in cases {
            XCTAssertEqual(QuickTimeTrackList.read(bytes: head + movieHeader)?.isQuickTimeFile, quickTime, name)
        }
        XCTAssertNil(QuickTimeTrackList.read(bytes: box("ftyp", [UInt8](repeating: 0x61, count: 5000)) + movieHeader))
    }

    /// The movie header after a large media box with a 64-bit size, as a
    /// file written without "fast start" has it: stepped over, not read.
    func test_aMovieHeaderAfterTheMediaIsFound() throws {
        let large: [UInt8] = [0, 0, 0, 1] + Array("mdat".utf8) + [0, 0, 0, 0, 0, 0, 0, 20] + [9, 9, 9, 9]
        let bytes = ftyp + large + box("moov", trak(hdlr("soun") + mdhd(2)))
        XCTAssertEqual(QuickTimeTrackList.read(bytes: bytes)?.tracks.map(\.languageCode), [2])
    }

    /// Damage, compression, too many tracks or no movie header: `nil`, never
    /// a guess.
    func test_damagedOrUnreadableInputIsRefused() {
        XCTAssertNil(QuickTimeTrackList.read(bytes: []))
        XCTAssertNil(QuickTimeTrackList.read(bytes: ftyp + box("mdat", [1, 2, 3])), "no moov")
        XCTAssertNil(QuickTimeTrackList.read(bytes: ftyp + box("moov", box("cmov", [0, 0, 0, 0]))), "compressed")
        // A child that runs past its parent.
        var broken = box("moov", trak(hdlr("soun") + mdhd(2)))
        broken[3] = UInt8(broken.count - 1)
        XCTAssertNil(QuickTimeTrackList.read(bytes: ftyp + broken))
        // A media header too short to hold a language, or of an unknown version.
        XCTAssertNil(QuickTimeTrackList.read(bytes: ftyp + box("moov", trak(box("mdhd", [0, 0, 0, 0, 1, 2])))))
        XCTAssertNil(QuickTimeTrackList.read(bytes: ftyp + box("moov", trak(mdhd(2, version: 7)))))
        // A media header far larger than any real one.
        XCTAssertNil(QuickTimeTrackList.read(bytes: ftyp + box("moov", trak(box("mdhd", [UInt8](repeating: 0, count: 5000))))))
        // More than 1,024 tracks.
        let many = [UInt8]((0...QuickTimeTrackList.trackLimit).map { _ in trak(hdlr("soun") + mdhd(0)) }.joined())
        XCTAssertNil(QuickTimeTrackList.read(bytes: ftyp + box("moov", many)))
        let enough = [UInt8]((1...QuickTimeTrackList.trackLimit).map { _ in trak(hdlr("soun") + mdhd(0)) }.joined())
        XCTAssertEqual(QuickTimeTrackList.read(bytes: ftyp + box("moov", enough))?.tracks.count, QuickTimeTrackList.trackLimit)
    }

    /// A movie header of tiny filler boxes cannot make it look forever: it
    /// stops at the box limit, counted (never timed).
    func test_theWalkIsBounded() {
        let filler = [UInt8]((0..<(QuickTimeTrackList.boxLimit + 10)).map { _ in box("free", []) }.joined())
        var effort = QuickTimeTrackList.Effort()
        XCTAssertNil(QuickTimeTrackList.read(bytes: ftyp + box("moov", filler), effort: &effort))
        XCTAssertLessThanOrEqual(effort.boxesVisited, QuickTimeTrackList.boxLimit)
    }

    /// An empty or unreadable full tag counts as absent.
    func test_anEmptyFullTagIsAbsent() throws {
        let bytes = ftyp + box("moov", trak(hdlr("soun") + mdhd(0) + box("elng", [0, 0, 0, 0, 0]))
                                 + trak(hdlr("soun") + mdhd(0) + box("elng", [0, 0, 0, 0, 0xFF, 0xFE, 0])))
        XCTAssertEqual(try XCTUnwrap(QuickTimeTrackList.read(bytes: bytes)).tracks.map(\.extendedLanguage), [nil, nil])
    }

    /// The same bytes read from a FILE and from memory give the same list —
    /// including an `elng` box with no body at all (8 bytes), and an empty
    /// one. The stand-in review of round 5 found that a file read of zero
    /// bytes answered `nil` (`FileHandle.read(upToCount: 0)`), so a bodiless
    /// `elng` made the whole list unreadable from a file while memory read
    /// it — and the file's OTHER tracks lost the language Apple reads. Only
    /// memory was tested; this reads both.
    func test_aFileAndMemoryReadTheSame() throws {
        let cases: [(String, [UInt8])] = [
            ("ffmpeg-like", movie),
            ("bodiless elng", ftyp + box("moov", trak(hdlr("soun") + mdhd(19)) + trak(hdlr("soun") + mdhd(0) + box("elng", [])))),
            ("empty elng", ftyp + box("moov", trak(hdlr("soun") + mdhd(19) + box("elng", [0, 0, 0, 0, 0])))),
            ("empty moov", ftyp + box("moov", []))
        ]
        for (name, bytes) in cases {
            let fromMemory = try XCTUnwrap(QuickTimeTrackList.read(bytes: bytes), name)
            XCTAssertEqual(QuickTimeTrackList.read(url: try scratch(bytes)), fromMemory, "\(name): file and memory agree")
        }
        XCTAssertEqual(QuickTimeTrackList.read(url: try scratch(cases[1].1))?.tracks.map(\.languageCode), [19, 0])
    }

    // MARK: - Matching ffprobe's streams

    private func stream(_ index: Int, _ type: StreamType, language: String? = nil, picture: Bool = false) -> MediaStream {
        MediaStream(streamIndex: index, streamType: type, language: language.map { TrackLanguage.read(fileValue: $0).language },
                    languageAsStored: language, disposition: StreamDisposition(isAttachedPicture: picture))
    }

    func test_tracksAreMatchedToStreamsByOrderAndType() throws {
        let list = try XCTUnwrap(QuickTimeTrackList.read(bytes: movie))
        // Cover art from the file's tags is an extra picture stream: left out.
        let streams = [stream(0, .video), stream(1, .audio), stream(2, .audio), stream(3, .subtitle),
                       stream(4, .video, picture: true)]
        let matched = try XCTUnwrap(list.streamsMatched(to: streams))
        XCTAssertEqual(matched[1]?.languageCode, 19)
        XCTAssertEqual(matched[2]?.extendedLanguage, "sv-SE")
        XCTAssertNil(matched[4])
        // A different count or a different type: no match at all.
        XCTAssertNil(list.streamsMatched(to: Array(streams.prefix(3))))
        XCTAssertNil(list.streamsMatched(to: [stream(0, .video), stream(1, .audio), stream(2, .video), stream(3, .subtitle)]))
    }

    // MARK: - Apple's reading of each number

    /// The number table: ffmpeg's labels, in number order, are the list the
    /// MOV writer accepts (unchanged from round 4), and each number reads as
    /// Apple's players read it — including the ones that share a label.
    func test_eachNumberReadsAsApplesPlayersReadIt() {
        XCTAssertEqual(TrackLanguage.quickTimeListEntries, [
            "eng", "fra", "ger", "ita", "dut", "sve", "spa", "dan", "por", "nor", "heb", "jpn", "ara", "fin",
            "gre", "ice", "mlt", "tur", "hr ", "chi", "urd", "hin", "tha", "kor", "lit", "pol", "hun", "est",
            "lav", "smi", "fo ", "per", "rus", "iri", "alb", "ron", "ces", "slk", "slv", "yid", "sr ", "mac",
            "bul", "ukr", "bel", "uzb", "kaz", "aze", "arm", "geo", "mol", "kir", "tgk", "tuk", "mon", "pus",
            "kur", "kas", "snd", "tib", "nep", "san", "mar", "ben", "asm", "guj", "pa ", "ori", "mal", "kan",
            "tam", "tel", "sin", "bur", "khm", "lao", "vie", "ind", "tgl", "may", "amh", "tir", "orm", "som",
            "swa", "kin", "run", "nya", "mlg", "epo", "wel", "baq", "cat", "lat", "que", "grn", "aym", "tat",
            "uig", "dzo", "jav"
        ])
        let cases: [(UInt16, String, String?)] = [
            (0, "eng", "en"), (2, "ger", "de"), (5, "sve", "sv"), (18, "hr ", "hr"), (19, "chi", "zh-Hant"),
            (33, "chi", "zh-Hans"), (35, "iri", "ga"), (49, "aze", "az-Cyrl"), (50, "aze", "az-Arab"),
            (57, "mon", "mn-Mong"), (83, "may", "ms"), (84, "may", "ms-Arab"), (138, "jav", "jv"),
            // A label that is not ffmpeg's for that number: not matched with
            // certainty, so nothing is read.
            (33, "eng", nil), (19, "zho", nil), (34, "dut", nil),
            // Numbers ffmpeg has NO label for (ffprobe gives no text) are
            // still read as Apple's players read them (the stand-in review of
            // round 5: they were not read at all); 95–127 Apple reads as none.
            (34, "", "nl"), (58, "", "mn"), (140, "", "gl"), (146, "", "ga-Latg"), (150, "", "az"),
            (151, "", "non"), (95, "", nil), (127, "", nil)
        ]
        for (number, label, expected) in cases {
            XCTAssertEqual(TrackLanguage.quickTimeLanguage(number: number, label: label), expected, "\(number) “\(label)”")
        }
        // Writing is unchanged: `chi` only for `zh-Hant`, never `sve` or `iri`.
        XCTAssertEqual(TrackLanguage.quickTimeCodesByTag["zh-Hant"], "chi")
        XCTAssertNil(TrackLanguage.quickTimeCodesByTag["zh-Hans"])
        XCTAssertNil(TrackLanguage.quickTimeCodesByTag["sv"])
        XCTAssertNil(TrackLanguage.quickTimeCodesByTag["ga"])
        // What a written entry is read back as: as ffmpeg writes it.
        XCTAssertEqual(TrackLanguage.quickTimeMeaning(ofEntry: "chi"), "zh-Hant")
        XCTAssertEqual(TrackLanguage.quickTimeMeaning(ofEntry: "sve"), "sv")
        XCTAssertEqual(TrackLanguage.quickTimeEntriesReadWithAScript.map(\.tag), ["zh-Hant", "az-Cyrl", "mn-Mong"])
    }

    // MARK: - The probe

    private func scratch(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-qtl-\(UUID().uuidString).mov")
        try Data(bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// The probe reads each language as Apple's players do: a Macintosh
    /// number by the table (also one ffmpeg has no label for), a full tag
    /// over the old field, packed letters as they are. ffprobe's text stays
    /// as what ffmpeg copies — empty where ffprobe gave none.
    func test_theProbeReadsLanguagesAsApplesPlayersDo() throws {
        let bytes = ftyp + box("moov",
            trak(hdlr("soun") + mdhd(19))                            // chi: Traditional
            + trak(hdlr("soun") + mdhd(33))                          // chi: Simplified
            + trak(hdlr("soun") + mdhd(5))                           // sve: Swedish
            + trak(hdlr("soun") + mdhd(packed("sve")))               // packed sve: Serili
            + trak(hdlr("soun") + mdhd(packed("zho")) + elng("zh-Hant")) // Apple's own writer
            + trak(hdlr("soun") + mdhd(0x7FFF) + elng("en-GB"))      // no number, a full tag
            + trak(hdlr("soun") + mdhd(34))                          // no label: Dutch
            + trak(hdlr("soun") + mdhd(100)))                        // no label, no language
        let url = try scratch(bytes)
        let probed = [stream(0, .audio, language: "chi"), stream(1, .audio, language: "chi"), stream(2, .audio, language: "sve"),
                      stream(3, .audio, language: "sve"), stream(4, .audio, language: "zho"), stream(5, .audio),
                      stream(6, .audio), stream(7, .audio)]
        let streams = FFmpegProbe.applyingQuickTimeLanguages(to: probed, fileURL: url, formatName: "mov,mp4,m4a,3gp,3g2,mj2")
        XCTAssertEqual(streams.map(\.language), ["zh-Hant", "zh-Hans", "sv", "sve", "zh-Hant", "en-GB", "nl", nil])
        XCTAssertEqual(streams.map(\.languageAsStored), ["chi", "chi", "sve", "sve", "zho", "", "", nil], "what ffmpeg copies")
        // Not a MOV / MP4 file: unchanged.
        XCTAssertEqual(FFmpegProbe.applyingQuickTimeLanguages(to: probed, fileURL: url, formatName: "matroska,webm")
            .map(\.language), probed.map(\.language))
        // A track list that does not match ffprobe's streams: ffprobe's
        // readings stand, and each track is marked — the job's notes then say
        // the source may record a fuller language that could not be read
        // (the stand-in review of round 5: nothing was said).
        let unmatched = FFmpegProbe.applyingQuickTimeLanguages(to: Array(probed.prefix(2)), fileURL: url,
                                                               formatName: "mov,mp4,m4a,3gp,3g2,mj2")
        XCTAssertEqual(unmatched.map(\.language), ["zh", "zh"])
        XCTAssertEqual(unmatched.map(\.languageFullTagUnknown), [true, true])
        XCTAssertEqual(streams.map(\.languageFullTagUnknown), [Bool?](repeating: nil, count: 8), "read: nothing marked")
    }

    /// In an MP4 (no QuickTime brand) a number below 0x400 is read as Apple's
    /// players read it THERE: packed letters that are no language — 2 is
    /// "``b", not ffprobe's German `ger`; 5 is not Swedish — 0 is `und`, and
    /// nine numbers give AVFoundation's extended tag (19 `zh-Hant`). The
    /// stand-in review of round 5 found an MP4's 2, 5 and 35 read as German,
    /// Swedish and Irish. ffprobe's text stays as what ffmpeg copies.
    func test_anMP4sNumbersAreReadAsApplesPlayersReadThem() throws {
        let bytes = fileType("isom", ["isom", "iso2", "mp41"]) + box("moov",
            trak(hdlr("soun") + mdhd(0)) + trak(hdlr("soun") + mdhd(2)) + trak(hdlr("soun") + mdhd(5))
            + trak(hdlr("soun") + mdhd(19)) + trak(hdlr("soun") + mdhd(35)) + trak(hdlr("soun") + mdhd(34))
            + trak(hdlr("soun") + mdhd(packed("swe"))))
        let labels: [String?] = ["eng", "ger", "sve", "chi", "iri", nil, "swe"]
        let probed = labels.enumerated().map { stream($0.offset, .audio, language: $0.element) }
        let streams = FFmpegProbe.applyingQuickTimeLanguages(to: probed, fileURL: try scratch(bytes),
                                                             formatName: "mov,mp4,m4a,3gp,3g2,mj2")
        XCTAssertEqual(streams.map(\.language), ["und", "und", "und", "zh-Hant", "und", "und", "sv"])
        XCTAssertEqual(streams.map(\.unrecognisedLanguage), [nil, "``b", "``e", nil, "`ac", "`ab", nil])
        XCTAssertEqual(streams.map(\.languageAsStored), ["eng", "ger", "sve", "chi", "iri", "", "swe"], "what ffmpeg copies")
        // The same numbers in a QuickTime movie: the Macintosh languages.
        let quickTime = ftyp + bytes.dropFirst(fileType("isom", ["isom", "iso2", "mp41"]).count)
        XCTAssertEqual(FFmpegProbe.applyingQuickTimeLanguages(to: probed, fileURL: try scratch(Array(quickTime)),
                                                              formatName: "mov,mp4,m4a,3gp,3g2,mj2").map(\.language),
                       ["en", "de", "sv", "zh-Hant", "ga", "nl", "sv"])
        XCTAssertEqual(TrackLanguage.mp4Reading(ofNumber: 1000), TrackLanguage.Reading(language: "und", unrecognised: "`h"),
                       "DEL (0x7F) is removed, as from any text the probe reads")
    }

    /// A track list that cannot be read at all — here an `elng` box larger
    /// than any real one — leaves ffprobe's readings, marks every real track
    /// (not cover art), and the job's notes say a fuller language may not
    /// have been read. And a bodiless `elng` on one track, read from a FILE,
    /// no longer costs another track its language (the stand-in review of
    /// round 5's `e0-empty.mov`: Traditional Chinese read as plain `chi`).
    func test_aTrackListThatCannotBeReadIsSaid() throws {
        let huge = ftyp + box("moov", trak(hdlr("soun") + mdhd(19))
                                  + trak(hdlr("soun") + mdhd(0) + box("elng", [0, 0, 0, 0] + [UInt8](repeating: 0x61, count: 5000))))
        let probed = [stream(0, .audio, language: "chi"), stream(1, .audio, language: "eng"),
                      stream(2, .video, picture: true)]
        let format = "mov,mp4,m4a,3gp,3g2,mj2"
        let unread = FFmpegProbe.applyingQuickTimeLanguages(to: probed, fileURL: try scratch(huge), formatName: format)
        XCTAssertEqual(unread.map(\.language), ["zh", "en", nil], "ffprobe's readings stand")
        XCTAssertEqual(unread.map(\.languageFullTagUnknown), [true, true, nil], "cover art is not a track")

        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mov")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mov")
        builder.sourceStreams = Array(unread.prefix(2))
        builder.mapAllStreams = true
        builder.audioPassthrough = true
        builder.orderTracksCanonically = false
        let gap = "Stream #0: this file type (QuickTime) can only store the languages on its old list; that list "
            + "has Chinese only as “chi”, which Apple's players read as Chinese in Traditional script (“zh-Hant”), "
            + "and “zh” does not say that, so no language is stored."
        let mayBeFuller = "The source may also record a fuller language for this track (with a region or script, "
            + "say), which could not be read; if it does, that is not kept, and no automatic title is made from "
            + "the three-letter code “chi”."
        XCTAssertEqual(builder.trackWritingNotes(), [
            gap + " " + mayBeFuller,
            "Stream #1: " + mayBeFuller.replacingOccurrences(of: "“chi”", with: "“eng”")
        ])

        let bodiless = ftyp + box("moov", trak(hdlr("soun") + mdhd(19)) + trak(hdlr("soun") + mdhd(0) + box("elng", [])))
        let read = FFmpegProbe.applyingQuickTimeLanguages(to: Array(probed.prefix(2)), fileURL: try scratch(bodiless),
                                                          formatName: format)
        XCTAssertEqual(read.map(\.language), ["zh-Hant", "en"], "read from a file, as Apple's players read it")
        XCTAssertEqual(read.map(\.languageFullTagUnknown), [nil, nil])
    }

    // MARK: - With the real tools

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

    /// The audio languages ffprobe reads from `url`, in order (`nil` = none).
    private func audioLanguages(_ ffprobe: String, _ url: URL) throws -> [String?] {
        let (status, data) = try run(ffprobe, ["-v", "error", "-print_format", "json", "-show_entries",
                                               "stream=codec_type:stream_tags=language", url.path])
        XCTAssertEqual(status, 0, "ffprobe \(url.lastPathComponent)")
        let streams = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["streams"] as? [[String: Any]] ?? []
        return streams.filter { $0["codec_type"] as? String == "audio" }
            .map { ($0["tags"] as? [String: Any])?["language"] as? String }
    }

    /// Sets the language number of every track of a MOV, in order, from
    /// `numbers` — straight into the file's `mdhd` boxes (ffmpeg can only
    /// write the first number of each label).
    private func setLanguageNumbers(of url: URL, to numbers: [UInt16]) throws {
        var data = [UInt8](try Data(contentsOf: url))
        func children(_ start: Int, _ end: Int) -> [(type: String, data: Int, end: Int)] {
            var result: [(type: String, data: Int, end: Int)] = []
            var offset = start
            while offset + 8 <= end {
                let size = Int(data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                guard size >= 8, offset + size <= end else { break }
                result.append((String(decoding: data[offset + 4..<offset + 8], as: UTF8.self), offset + 8, offset + size))
                offset += size
            }
            return result
        }
        var next = 0
        for movie in children(0, data.count) where movie.type == "moov" {
            for track in children(movie.data, movie.end) where track.type == "trak" {
                for media in children(track.data, track.end) where media.type == "mdia" {
                    for header in children(media.data, media.end) where header.type == "mdhd" && next < numbers.count {
                        let at = header.data + (data[header.data] == 0 ? 20 : 32)
                        data[at] = UInt8(numbers[next] >> 8)
                        data[at + 1] = UInt8(numbers[next] & 0xFF)
                        next += 1
                    }
                }
            }
        }
        XCTAssertEqual(next, numbers.count, "every track numbered")
        try Data(data).write(to: url)
    }

    /// The whole table (`TrackLanguage.quickTimeNumbers`) against the tools:
    /// one MOV with an audio track per number, each number set straight into
    /// the file; ffprobe must give ffmpeg's label for it, and Apple's
    /// AVFoundation must read exactly the code and extended tag the table
    /// records.
    func test_quickTimeNumbersAreWhatApplesPlayersRead() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — QuickTime number check")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-qtn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let table = TrackLanguage.quickTimeNumbers
        let output = folder.appendingPathComponent("numbers.mov")
        var arguments = ["-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.1"]
        for _ in table { arguments += ["-map", "0:a"] }
        XCTAssertEqual(try run(ffmpeg, arguments + ["-c:a", "aac", "-f", "mov", output.path]).status, 0, "making numbers.mov")
        try setLanguageNumbers(of: output, to: table.map(\.number))

        XCTAssertEqual(try audioLanguages(ffprobe, output), table.map { $0.label.isEmpty ? nil : $0.label },
                       "ffprobe gives ffmpeg's labels, and nothing for the 15 numbers it has none for")
        guard let apple = try await MediaTools.appleAudioLanguages(of: output) else {
            try MediaTools.missing("AVFoundation is not available here")
        }
        XCTAssertEqual(apple.count, table.count)
        let mismatches = zip(table, apple).filter { $0.0.appleCode != $0.1.code || $0.0.appleTag != $0.1.tag }
            .map { "\($0.0.number) “\($0.0.label)”: table \($0.0.appleCode)/\($0.0.appleTag ?? "nil"), Apple \($0.1)" }
        XCTAssertEqual(mismatches, [], "what Apple's players read differs from TrackLanguage.quickTimeNumbers")
        print("QuickTime numbers: \(table.count) read back by AVFoundation, \(mismatches.count) mismatches")
    }

    /// Which files the numbers are Macintosh languages in, against Apple's
    /// own reader: one file with an audio track for every number from 0 to
    /// 151 and five above (152, 200, 500, 1000, 1023), in four forms that
    /// differ ONLY in the `ftyp` box — ffmpeg's MOV (`qt  `), an MP4
    /// (`isom`), an MP4 brand with `qt  ` compatible, and no `ftyp` at all.
    /// For every track the probe must read what AVFoundation reads: the
    /// Macintosh language in the three QuickTime forms, and in the MP4 the
    /// packed letters (no language) or the extended tag AVFoundation still
    /// gives. The stand-in review of round 5 found an MP4's numbers read
    /// with the Macintosh table (2 as German), which Apple does not do.
    func test_mp4NumbersAreReadAsApplesPlayersReadThem() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — MP4 number check")
        }
        let policy = try XCTUnwrap(TrackLanguage.policy)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-mp4n-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let numbers = Array(UInt16(0)...151) + [152, 200, 500, 1000, 1023]
        let made = folder.appendingPathComponent("made.mov")
        var arguments = ["-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.1"]
        for _ in numbers { arguments += ["-map", "0:a"] }
        XCTAssertEqual(try run(ffmpeg, arguments + ["-c:a", "aac", "-f", "mov", made.path]).status, 0, "making made.mov")
        try setLanguageNumbers(of: made, to: numbers)
        let original = [UInt8](try Data(contentsOf: made))
        XCTAssertEqual(Array(original[4..<12]), Array("ftypqt  ".utf8), "ffmpeg's MOV starts with a 20-byte ftyp")

        // What Apple's players read: the extended tag, else the code — a
        // code that starts with a backtick is packed letters, not a language.
        func apples(_ read: MediaTools.AppleLanguage) -> (language: String?, unrecognised: String?) {
            if let tag = read.tag { return (policy.canonicaliser.canonicalise(tag).canonical, nil) }
            let code = (read.code ?? "").replacingOccurrences(of: "\u{7F}", with: "")
            if code.isEmpty || code == "und" { return ("und", nil) }
            if code.hasPrefix("`") { return ("und", code) }
            return (policy.reader.read(code), nil)
        }
        let forms: [(name: String, type: String, major: String, compatible: String, quickTime: Bool)] = [
            ("qt.mov", "ftyp", "qt  ", "qt  ", true), ("isom.mov", "ftyp", "isom", "isom", false),
            ("isom-qt.mov", "ftyp", "isom", "qt  ", true), ("no-ftyp.mov", "free", "qt  ", "qt  ", true)
        ]
        var checked = 0
        for form in forms {
            var bytes = original
            bytes.replaceSubrange(4..<12, with: Array((form.type + form.major).utf8))
            bytes.replaceSubrange(16..<20, with: Array(form.compatible.utf8))
            let url = folder.appendingPathComponent(form.name)
            try Data(bytes).write(to: url)
            XCTAssertEqual(QuickTimeTrackList.read(url: url)?.isQuickTimeFile, form.quickTime, form.name)
            guard let apple = try await MediaTools.appleAudioLanguages(of: url) else {
                try MediaTools.missing("AVFoundation is not available here")
            }
            let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: url).streams.filter { $0.streamType == .audio }
            XCTAssertEqual(probed.count, numbers.count, form.name)
            XCTAssertEqual(apple.count, numbers.count, form.name)
            let mismatches = zip(numbers, zip(probed, apple)).compactMap { number, pair -> String? in
                let want = apples(pair.1)
                let got = (pair.0.language ?? "und", pair.0.unrecognisedLanguage)
                return want == got ? nil : "\(form.name) \(number): Apple \(pair.1) → \(want), probe \(got)"
            }
            XCTAssertEqual(mismatches, [], "the probe reads differently from Apple's players")
            checked += numbers.count
        }
        print("MP4 numbers: \(checked) tracks in \(forms.count) file types read back by AVFoundation")
    }

    /// The fourth independent review's carried-over case, end to end: a MOV
    /// with `chi`, `aze`, `mon`, `sve` and `iri` tracks (numbers 19, 49, 57,
    /// 5, 35, as ffmpeg writes them) — Traditional Chinese, Azerbaijani in
    /// Cyrillic, Mongolian in Mongolian script, Swedish and Irish to Apple's
    /// players — and the same with number 33 (Simplified Chinese, also
    /// `chi` to ffprobe). Remuxed with MeedyaConverter's own arguments:
    ///
    /// * to MOV, every language Apple shows is kept (round 4 stored none of
    ///   the five); Simplified Chinese, which ffmpeg's writer cannot store,
    ///   gets no language and a true note;
    /// * to MP4, the languages are kept, as `swe` and `gle` for Swedish and
    ///   Irish (round 4 copied `sve` and `iri`, which Apple reads in an MP4
    ///   as Serili and Rigwe), the scripts noted as not saved;
    /// * to Matroska, what they mean: `zh-Hant`, `az-Cyrl`, `mn-Mong` as
    ///   text, `swe`, `gle`.
    ///
    /// Read back with ffprobe and with Apple's AVFoundation.
    func test_movLanguagesSurviveAsApplesPlayersReadThem() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — MOV language check")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-movlang-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let labels = ["chi", "aze", "mon", "sve", "iri"]
        let source = folder.appendingPathComponent("five.mov")
        var arguments = ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=64x48:rate=5:duration=0.4",
                         "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4", "-map", "0:v"]
        for (index, label) in labels.enumerated() {
            arguments += ["-map", "1:a", "-metadata:s:a:\(index)", "language=\(label)"]
        }
        XCTAssertEqual(try run(ffmpeg, arguments + ["-c:v", "mpeg4", "-c:a", "aac", "-f", "mov", source.path]).status, 0)
        let simplified = folder.appendingPathComponent("simplified.mov")
        try FileManager.default.copyItem(at: source, to: simplified)
        try setLanguageNumbers(of: simplified, to: [0x7FFF, 33, 49, 57, 5, 35])

        let apple = try await MediaTools.appleAudioLanguages(of: source)
        if let apple {
            XCTAssertEqual(apple.map(\.description), ["zho/zh-Hant", "aze/az-Cyrl", "mon/mn-Mong", "swe/nil", "gle/nil"],
                           "the source, as Apple's players read it")
        }

        func convert(_ input: URL, _ name: String, _ container: ContainerFormat) async throws -> (URL, [String]) {
            try await remux(input, to: folder.appendingPathComponent(name), container, ffmpeg: ffmpeg, ffprobe: ffprobe)
        }

        // The probe reads them as Apple does.
        let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: source).streams.filter { $0.streamType == .audio }
        XCTAssertEqual(probed.map(\.language), ["zh-Hant", "az-Cyrl", "mn-Mong", "sv", "ga"])

        // MOV → MOV: every one kept, as Apple reads it.
        let (mov, movNotes) = try await convert(source, "out.mov", .mov)
        XCTAssertEqual(try audioLanguages(ffprobe, mov), labels.map(Optional.some), "out.mov: ffprobe")
        if let read = try await MediaTools.appleAudioLanguages(of: mov) {
            XCTAssertEqual(read.map(\.description), ["zho/zh-Hant", "aze/az-Cyrl", "mon/mn-Mong", "swe/nil", "gle/nil"],
                           "out.mov: AVFoundation")
        }
        XCTAssertEqual(movNotes, [("4", "sve", "Swedish", "Serili"), ("5", "iri", "Irish", "Rigwe")].map {
            "Stream #\($0.0): the source's own QuickTime code “\($0.1)” is kept as it was. Apple's players read it as "
                + "\($0.2), but other programs read it as \($0.3), the language that code is registered for."
        })

        // MOV → MP4: Swedish and Irish as `swe` and `gle`; scripts noted.
        let (mp4, mp4Notes) = try await convert(source, "out.mp4", .mp4)
        XCTAssertEqual(try audioLanguages(ffprobe, mp4), ["zho", "aze", "mon", "swe", "gle"], "out.mp4: ffprobe")
        if let read = try await MediaTools.appleAudioLanguages(of: mp4) {
            XCTAssertEqual(read.map(\.code), ["zho", "aze", "mon", "swe", "gle"], "out.mp4: AVFoundation")
        }
        XCTAssertEqual(mp4Notes, [("1", "Hant", "zh-Hant", "zho"), ("2", "Cyrl", "az-Cyrl", "aze"), ("3", "Mong", "mn-Mong", "mon")].map {
            "Stream #\($0.0): this file type can only store the language, so “\($0.1)” in “\($0.2)” is not saved "
                + "(written as “\($0.3)”)."
        })

        // MOV → Matroska: what they mean.
        let (mkv, _) = try await convert(source, "out.mkv", .mkv)
        XCTAssertEqual(try audioLanguages(ffprobe, mkv), ["zh-Hant", "az-Cyrl", "mn-Mong", "swe", "gle"], "out.mkv: ffprobe")

        // Number 33, Simplified Chinese — `chi` to ffprobe, as 19 is.
        let (fromSimplified, simplifiedNotes) = try await convert(simplified, "simplified-out.mov", .mov)
        XCTAssertEqual(try audioLanguages(ffprobe, fromSimplified), [nil, "aze", "mon", "sve", "iri"])
        XCTAssertEqual(simplifiedNotes.first,
                       "Stream #1: this file type (QuickTime) can only store the languages on its old list; that list "
                           + "has Chinese only as “chi”, which Apple's players read as Chinese in Traditional script "
                           + "(“zh-Hant”), and “zh-Hans” is not that, so no language is stored.")
        let (simplifiedMKV, _) = try await convert(simplified, "simplified-out.mkv", .mkv)
        XCTAssertEqual(try audioLanguages(ffprobe, simplifiedMKV).first, "zh-Hans")
    }

    /// Remuxes `input` to `output` (`container`) with MeedyaConverter's own
    /// arguments, in the source's track order: the output, and the job's
    /// notes.
    private func remux(_ input: URL, to output: URL, _ container: ContainerFormat, ffmpeg: String,
                       ffprobe: String) async throws -> (URL, [String]) {
        var profile = container == .mkv ? EncodingProfile.remuxToMKV : EncodingProfile.remuxToMP4
        profile.containerFormat = container
        profile.orderTracksCanonically = false
        var config = EncodingJobConfig(inputURL: input, outputURL: output, profile: profile)
        config.sourceStreams = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: input).streams
        XCTAssertEqual(try run(ffmpeg, ["-v", "error"] + config.buildArguments()).status, 0,
                       "encoding \(output.lastPathComponent)")
        return (output, config.trackWritingNotes())
    }

    /// The stand-in review of round 5: Apple's players read fifteen numbers
    /// ffmpeg has NO label for (ffprobe gives no language) — here 34 Dutch,
    /// 58 Mongolian, 140 Galician, 146 Irish in the old Gaelic script and
    /// 150 Azerbaijani — and every output of such a MOV had no language and
    /// no note. Now they are read as Apple reads them, so MP4 and Matroska
    /// keep each language, MOV keeps Dutch (as `dut`), and MOV's notes say
    /// why it cannot store the others. Read back with ffprobe and
    /// AVFoundation.
    func test_numbersFFmpegHasNoLabelForKeepTheirLanguage() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — unlabelled QuickTime number check")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-qtgap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("gaps.mov")
        var arguments = ["-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4"]
        for _ in 0..<5 { arguments += ["-map", "0:a"] }
        XCTAssertEqual(try run(ffmpeg, arguments + ["-c:a", "aac", "-f", "mov", source.path]).status, 0, "making gaps.mov")
        try setLanguageNumbers(of: source, to: [34, 58, 140, 146, 150])
        XCTAssertEqual(try audioLanguages(ffprobe, source), [nil, nil, nil, nil, nil], "ffprobe gives no language for any")
        if let apple = try await MediaTools.appleAudioLanguages(of: source) {
            XCTAssertEqual(apple.map(\.description), ["nld/nil", "mon/mn", "glg/nil", "gle/ga-Latg", "aze/az"],
                           "the source, as Apple's players read it")
        }
        let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: source).streams.filter { $0.streamType == .audio }
        XCTAssertEqual(probed.map(\.language), ["nl", "mn", "gl", "ga-Latg", "az"])

        // MOV → MOV: Dutch as `dut` (number 4, which Apple reads as Dutch);
        // the others cannot be stored, each with the reason.
        let (mov, movNotes) = try await remux(source, to: folder.appendingPathComponent("out.mov"), .mov,
                                              ffmpeg: ffmpeg, ffprobe: ffprobe)
        XCTAssertEqual(try audioLanguages(ffprobe, mov), ["dut", nil, nil, nil, nil], "out.mov: ffprobe")
        if let read = try await MediaTools.appleAudioLanguages(of: mov) {
            XCTAssertEqual(read.map(\.code), ["nld", "und", "und", "und", "und"], "out.mov: AVFoundation")
        }
        let onlyTheList = "this file type (QuickTime) can only store the languages on its old list"
        XCTAssertEqual(movNotes, [
            "Stream #1: \(onlyTheList); that list has Mongolian only as “mon”, which Apple's players read as Mongolian "
                + "in Mongolian script (“mn-Mong”), and “mn” does not say that, so no language is stored.",
            "Stream #2: \(onlyTheList), and “gl” is not on it, so no language is stored.",
            "Stream #3: \(onlyTheList); that list has Irish only as “iri”, which Apple's players read as Irish but "
                + "other programs read as Rigwe, the language that code is registered for, so no language is stored.",
            "Stream #4: \(onlyTheList); that list has Azerbaijani only as “aze”, which Apple's players read as "
                + "Azerbaijani in Cyrillic script (“az-Cyrl”), and “az” does not say that, so no language is stored."
        ])

        // MOV → MP4: every language, the script of `ga-Latg` noted as not saved.
        let (mp4, mp4Notes) = try await remux(source, to: folder.appendingPathComponent("out.mp4"), .mp4,
                                              ffmpeg: ffmpeg, ffprobe: ffprobe)
        XCTAssertEqual(try audioLanguages(ffprobe, mp4), ["nld", "mon", "glg", "gle", "aze"], "out.mp4: ffprobe")
        if let read = try await MediaTools.appleAudioLanguages(of: mp4) {
            XCTAssertEqual(read.map(\.code), ["nld", "mon", "glg", "gle", "aze"], "out.mp4: AVFoundation")
        }
        XCTAssertEqual(mp4Notes, ["Stream #3: this file type can only store the language, so “Latg” in “ga-Latg” is not "
                                  + "saved (written as “gle”)."])

        // MOV → Matroska: every language; `ga-Latg` as text.
        let (mkv, _) = try await remux(source, to: folder.appendingPathComponent("out.mkv"), .mkv,
                                       ffmpeg: ffmpeg, ffprobe: ffprobe)
        XCTAssertEqual(try audioLanguages(ffprobe, mkv), ["dut", "mon", "glg", "ga-Latg", "aze"], "out.mkv: ffprobe")
    }

    /// MOV files written by APPLE'S OWN tools (`avconvert`, which ships with
    /// macOS) store a language differently from ffmpeg: three packed letters
    /// (`aze`, `sve` — which Apple then reads literally, so `sve` is Serili
    /// there) and, for a script, an `elng` box beside them (`zh-Hant` with a
    /// plain `zho`). Whatever Apple writes, the probe must read each track as
    /// Apple's players do — never `az-Cyrl` for a packed `aze`, never Swedish
    /// for a packed `sve`. Checked against AVFoundation track by track, for
    /// an export of an ffmpeg MOV (Macintosh numbers) and of an ffmpeg MP4
    /// (packed letters). Skipped where `avconvert` is missing.
    func test_appleWrittenMOVsAreReadAsApplesPlayersReadThem() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — Apple-written MOV check")
        }
        let policy = try XCTUnwrap(TrackLanguage.policy)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-applemov-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let avconvert = "/usr/bin/avconvert"
        guard FileManager.default.isExecutableFile(atPath: avconvert) else {
            try MediaTools.missing("avconvert (part of macOS) not found")
        }

        var arguments = ["-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4"]
        for (index, label) in ["chi", "aze", "mon", "sve", "iri"].enumerated() {
            arguments += ["-map", "0:a", "-metadata:s:a:\(index)", "language=\(label)"]
        }
        for (name, muxer) in [("ffmpeg.mov", "mov"), ("ffmpeg.mp4", "mp4")] {
            let made = folder.appendingPathComponent(name)
            XCTAssertEqual(try run(ffmpeg, arguments + ["-c:a", "aac", "-f", muxer, made.path]).status, 0, name)
            let exported = folder.appendingPathComponent("apple-\(muxer).mov")
            let status = try run(avconvert, ["--source", made.path, "--preset", "PresetPassthrough",
                                             "--output", exported.path, "--replace"]).status
            XCTAssertEqual(status, 0, "avconvert \(name)")
            guard let apple = try await MediaTools.appleAudioLanguages(of: exported) else {
                try MediaTools.missing("AVFoundation is not available here")
            }
            let applesReading = apple.map { $0.tag.flatMap { policy.canonicaliser.canonicalise($0).canonical }
                ?? $0.code.flatMap { policy.reader.read($0) } }
            let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: exported).streams
                .filter { $0.streamType == .audio }.map(\.language)
            XCTAssertEqual(probed, applesReading, "\(exported.lastPathComponent): the probe reads what Apple reads (\(apple))")
        }
    }
}
