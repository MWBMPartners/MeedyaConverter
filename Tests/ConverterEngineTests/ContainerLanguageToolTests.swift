// ============================================================================
// MeedyaConverter — ContainerLanguageToolTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The language policy's TRACK-070 says: which fields a tool writes "change
// over time. Each project MUST check them against the tool it actually runs,
// with a test, rather than rely on this table." This is that test.
//
// Two checks, both with the ffmpeg on this machine:
//
//   * `test_eachFileTypeStoresWhatTheTableSays`: for every file type in
//     `TrackLanguage.LanguageFieldStorage` that ffmpeg can write from a plain
//     audio track, it writes a set of language values (`ger`, `deu`, `fr-CA`,
//     `romanian`, `yue`, `ENG`, `und`, `hr `, `e_g`, `eng,fre`) and reads each
//     back with ffprobe, and requires exactly what the table says is stored.
//     The second independent review found the round-2 notes saying "kept as
//     the source had it" where MP4 had cut the value, and MPEG-TS and MOV had
//     dropped it — the table did not exist, so nothing checked it.
//   * `test_ffmpegWritesTheLanguageFieldsWeRelyOn`: a tiny two-track source,
//     probed with FFmpegProbe, converted with MeedyaConverter's own arguments
//     to Matroska, MP4 and MOV, and read back.
//
// Skipped when no ffmpeg/ffprobe is installed, per CONTRIBUTING's rule for
// tests that need FFmpeg — but FAILED in CI's build-and-test job, which
// installs the tools and requires them (`MediaTools.missing`). DASH, HLS and MXF were checked by hand
// (28 Sept 2026, ffmpeg 9.0.1), not here: they need a folder of segments or a
// video track.
//
// First run 28 Sept 2026 with ffmpeg 9.0.1 (Homebrew): passed. It also
// prints whether the Matroska output holds a `LanguageBCP47` element — ffmpeg
// 9.0.1 writes none; if a later ffmpeg does, the print says so and the
// region/script loss documented in TrackLanguage can be revisited.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class ContainerLanguageToolTests: XCTestCase {

    // MARK: - Tools

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

    /// ffprobe's raw view of each stream: language tag, title tag and the
    /// dispositions this test cares about.
    private func rawStreams(_ ffprobe: String, _ file: URL) throws -> [[String: Any]] {
        let (status, data) = try run(ffprobe, [
            "-v", "error", "-print_format", "json", "-show_entries",
            "stream=index,codec_type:stream_tags=language,title:stream_disposition=default,original,comment",
            file.path
        ])
        XCTAssertEqual(status, 0)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["streams"] as? [[String: Any]] ?? []
    }

    // MARK: - The table of what each file type stores

    /// Whether this ffmpeg has the named encoder.
    private func hasEncoder(_ ffmpeg: String, _ name: String) throws -> Bool {
        let listed = try run(ffmpeg, ["-hide_banner", "-encoders"])
        return String(bytes: listed.output, encoding: .utf8)?.contains(" \(name) ") ?? false
    }

    func test_eachFileTypeStoresWhatTheTableSays() throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — TRACK-070 tool check")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-lang-table-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // Each file type: its ffmpeg writer, a file extension, and an audio
        // encoder that writer takes (all built into ffmpeg, except WebM's).
        var rows: [(ContainerFormat, String, String, [String])] = [
            (.mkv, "matroska", "mkv", ["-c:a", "aac"]),
            (.mp4, "mp4", "mp4", ["-c:a", "aac"]),
            (.threeGP, "3gp", "3gp", ["-c:a", "aac"]),
            (.mov, "mov", "mov", ["-c:a", "aac"]),
            (.mpegTS, "mpegts", "ts", ["-c:a", "aac"]),
            (.ogg, "ogg", "ogg", ["-c:a", "flac"]),
            (.avi, "avi", "avi", ["-c:a", "pcm_s16le"]),
            (.flv, "flv", "flv", ["-c:a", "aac"]),
            (.mpegPS, "mpeg", "mpg", ["-c:a", "mp2"]),
            (.aiff, "aiff", "aiff", ["-c:a", "pcm_s16be"]),
            (.caf, "caf", "caf", ["-c:a", "pcm_s16le"]),
            (.w64, "w64", "w64", ["-c:a", "pcm_s16le"])
        ]
        if try hasEncoder(ffmpeg, "libopus") {
            rows.append((.webm, "webm", "webm", ["-c:a", "libopus"]))
        } else if MediaTools.required {
            try MediaTools.missing("this ffmpeg has no libopus (needed for the WebM row)")
        }
        let values = ["ger", "deu", "fr-CA", "romanian", "yue", "ENG", "und", "hr ", "e_g", "eng,fre"]
        var mismatches: [String] = []
        for (container, muxer, fileExtension, codec) in rows {
            let storage = TrackLanguage.languageFieldStorage(for: container)
            for (index, value) in values.enumerated() {
                let output = folder.appendingPathComponent("v\(index).\(fileExtension)")
                let made = try run(ffmpeg, [
                    "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.2"
                ] + codec + ["-metadata:s:a:0", "language=\(value)", "-f", muxer, output.path])
                guard made.status == 0 else {
                    mismatches.append("\(container): ffmpeg could not write “\(value)”")
                    continue
                }
                let streams = try rawStreams(ffprobe, output)
                let read = (streams.first?["tags"] as? [String: Any])?["language"] as? String
                var expected = storage.stored(value)
                // ffmpeg's Matroska reader reports a stored `und` as no
                // language at all (it is also RFC 9559's "not known").
                if storage == .anyText, container != .ogg, expected == "und" { expected = nil }
                if read != expected {
                    mismatches.append("\(container): “\(value)” read back as \(read.map { "“\($0)”" } ?? "nothing"), "
                        + "the table says \(expected.map { "“\($0)”" } ?? "nothing")")
                }
            }
        }
        XCTAssertEqual(mismatches, [], "what ffmpeg stores differs from TrackLanguage.LanguageFieldStorage")
        print("TRACK-070 table check: \(rows.count) file types × \(values.count) values, \(mismatches.count) mismatches")
    }

    /// MOV's language as APPLE'S players read it (the third independent
    /// review): every QuickTime-list entry this converter writes
    /// (`TrackLanguage.quickTimeCodesByTag`) must read back, through Apple's
    /// AVFoundation, as the very tag it is written for — `chi` as `zh-Hant`,
    /// `aze` as `az-Cyrl`, `mon` as `mn-Mong`, `ger` as German. And the two
    /// labels never written read as Swedish and Irish there, while ffprobe
    /// gives back the text `sve`/`iri` (which is why they are never written).
    /// One MOV file with one short audio track per entry, made by ffmpeg.
    func test_movCodesAreWhatApplesPlayersRead() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — TRACK-070 tool check")
        }
        let policy = try XCTUnwrap(TrackLanguage.policy)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-lang-quicktime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let written = TrackLanguage.quickTimeCodesByTag.sorted { $0.key < $1.key }
        XCTAssertGreaterThan(written.count, 90, "nearly the whole list is written")
        let entries = written.map(\.value) + ["sve", "iri"]
        var arguments = ["-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.1"]
        for (index, entry) in entries.enumerated() {
            arguments += ["-map", "0:a", "-metadata:s:a:\(index)", "language=\(entry)"]
        }
        let output = folder.appendingPathComponent("list.mov")
        XCTAssertEqual(try run(ffmpeg, arguments + ["-c:a", "aac", "-f", "mov", output.path]).status, 0, "making list.mov")

        // ffprobe reads each label back.
        let labels = try rawStreams(ffprobe, output).map { ($0["tags"] as? [String: Any])?["language"] as? String }
        XCTAssertEqual(labels, entries.map(Optional.some), "ffprobe reads the labels back")

        guard let apple = try await MediaTools.appleAudioLanguages(of: output) else {
            try MediaTools.missing("AVFoundation is not available here")
        }
        XCTAssertEqual(apple.count, entries.count)
        var mismatches: [String] = []
        for (index, (tag, entry)) in written.enumerated() where index < apple.count {
            // Apple's reading as a tag: its extended tag when it gives one
            // (`zh-Hant`), else its three-letter code read by the policy.
            let read = apple[index].tag ?? apple[index].code.flatMap { policy.reader.read($0) }
            if read != tag { mismatches.append("“\(entry)” for “\(tag)”: Apple reads \(apple[index])") }
        }
        XCTAssertEqual(mismatches, [], "what Apple's players read differs from TrackLanguage.quickTimeCodesByTag")
        XCTAssertEqual(apple.suffix(2).map(\.code), ["swe", "gle"], "sve and iri: Swedish and Irish to Apple")
        print("QuickTime check: \(written.count) entries read back by AVFoundation, \(mismatches.count) mismatches")
    }

    /// The fact `TrackLanguage.LanguageWrite.Action.clear` rests on: an
    /// EMPTY value (`-metadata:s:a:0 language=`) removes the language, where
    /// giving ffmpeg nothing copies the source's own value in. The third
    /// independent review found MOV outputs holding the copied `chi` and
    /// `eng` under a note saying "no language is stored". MOV then stores no
    /// language (Apple's AVFoundation reads `und`), MP4 stores `und` (its
    /// writer's value for "none"), and Matroska, MPEG-TS and Ogg store none.
    func test_anEmptyValueClearsTheField() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — TRACK-070 tool check")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-lang-clear-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mkv")
        XCTAssertEqual(try run(ffmpeg, [
            "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.2",
            "-c:a", "aac", "-metadata:s:a:0", "language=eng", source.path
        ]).status, 0, "making the source")

        for (muxer, fileExtension, codec, cleared) in [
            ("mov", "mov", "aac", nil), ("mp4", "mp4", "aac", "und"), ("matroska", "mkv", "aac", nil),
            ("mpegts", "ts", "aac", nil), ("ogg", "ogg", "flac", nil)
        ] as [(String, String, String, String?)] {
            for (clear, expected) in [(false, "eng"), (true, cleared)] {
                let output = folder.appendingPathComponent("\(clear ? "cleared" : "copied").\(fileExtension)")
                let made = try run(ffmpeg, ["-v", "error", "-y", "-i", source.path, "-map", "0", "-c:a", codec]
                    + (clear ? ["-metadata:s:a:0", "language="] : []) + ["-f", muxer, output.path])
                XCTAssertEqual(made.status, 0, "\(muxer), cleared: \(clear)")
                let read = (try rawStreams(ffprobe, output).first?["tags"] as? [String: Any])?["language"] as? String
                XCTAssertEqual(read, expected, "\(muxer), cleared: \(clear)")
                if muxer == "mov", let apple = try await MediaTools.appleAudioLanguages(of: output) {
                    XCTAssertEqual(apple.map(\.isNone), [clear], "MOV, cleared: \(clear) — AVFoundation \(apple)")
                }
            }
        }
    }

    // MARK: - The check

    func test_ffmpegWritesTheLanguageFieldsWeRelyOn() async throws {
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — TRACK-070 tool check")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-lang-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // A source with German commentary first and the Japanese original
        // second, written with OLD Matroska codes (as most real files have).
        let source = folder.appendingPathComponent("source.mkv")
        let made = try run(ffmpeg, [
            "-v", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3",
            "-f", "lavfi", "-i", "sine=frequency=660:duration=0.3",
            "-map", "0", "-map", "1", "-c:a", "aac",
            "-metadata:s:a:0", "language=ger", "-disposition:a:0", "comment",
            "-metadata:s:a:1", "language=jpn", "-disposition:a:1", "default+original",
            source.path
        ])
        XCTAssertEqual(made.status, 0, "making the source")

        // The probe reads them through the policy (LANG-002).
        let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: source)
        XCTAssertEqual(probed.streams.map(\.language), ["de", "ja"])
        XCTAssertEqual(probed.streams.map(\.isOriginalLanguage), [false, true])

        // MOV gets the QuickTime list's entries — `ger`, not `deu`, which
        // MOV's writer drops (the second review's finding).
        for (name, expectedCodes) in [("out.mkv", ["jpn", "ger"]), ("out.mp4", ["jpn", "deu"]), ("out.mov", ["jpn", "ger"])] {
            let output = folder.appendingPathComponent(name)
            var builder = FFmpegArgumentBuilder()
            builder.inputURL = source
            builder.outputURL = output
            builder.sourceStreams = probed.streams
            builder.audioPassthrough = true
            builder.videoPassthrough = true
            let encoded = try run(ffmpeg, ["-v", "error"] + builder.build())
            XCTAssertEqual(encoded.status, 0, "encoding \(name)")

            let streams = try rawStreams(ffprobe, output)
            let codes = streams.map { ($0["tags"] as? [String: Any])?["language"] as? String }
            // The original (Japanese) is first; each field holds the
            // three-letter code in the form this container needs.
            XCTAssertEqual(codes, expectedCodes, "\(name): language fields as ffprobe reads them")
            let comment = streams.map { ($0["disposition"] as? [String: Any])?["comment"] as? Int }
            if name == "out.mov" {
                // ffmpeg's MOV writer keeps no role but "default" (checked
                // with 9.0.1). Recorded here so a change in ffmpeg shows up;
                // reporting the loss in the job's notes is issue #541.
                XCTAssertEqual(comment, [0, 0], "\(name): MOV cannot keep the commentary role (#541)")
            } else {
                XCTAssertEqual(comment, [0, 1], "\(name): the commentary role survives")
            }

            if name == "out.mkv" {
                let titles = streams.map { ($0["tags"] as? [String: Any])?["title"] as? String }
                // Automatic titles (NAME-010) say the language AND the
                // roles, so the German commentary is not just "Deutsch".
                XCTAssertEqual(titles, ["日本語", "Deutsch — Commentary"], "automatic titles (NAME-010, UI-070)")
                let original = streams.map { ($0["disposition"] as? [String: Any])?["original"] as? Int }
                XCTAssertEqual(original, [1, 0], "Matroska keeps FlagOriginal")
                // Informational: does this ffmpeg write LanguageBCP47
                // (EBML ID 0x22B59D)? 9.0.1 does not.
                let bytes = try Data(contentsOf: output)
                let hasBCP47 = bytes.range(of: Data([0x22, 0xB5, 0x9D])) != nil
                print("TRACK-070 tool check: Matroska LanguageBCP47 element written by this ffmpeg: \(hasBCP47)")
            }

            // And the probe reads the output back to the same tags.
            let reread = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: output)
            XCTAssertEqual(reread.streams.map(\.language), ["ja", "de"], "\(name): read back through the policy")
        }
    }
}
