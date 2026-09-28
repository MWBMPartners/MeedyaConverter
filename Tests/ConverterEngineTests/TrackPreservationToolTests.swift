// ============================================================================
// MeedyaConverter — TrackPreservationToolTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// A copy or conversion must never lose or damage anything the source had
// that the person did not ask to change (language policy COMPAT-030). The
// independent review of the language policy work found cases where it did;
// each test here makes a small file with the ffmpeg on this machine, runs
// MeedyaConverter's own arguments through that ffmpeg, and reads the result
// back with ffprobe — the way the review reproduced them.
//
// Skipped (not failed) when ffmpeg/ffprobe are not installed, per
// CONTRIBUTING's rule for tests that need FFmpeg. First run 28 Sept 2026
// with ffmpeg 9.0.1 (Homebrew): passed.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class TrackPreservationToolTests: XCTestCase {

    // MARK: - Tools

    private var ffmpeg = ""
    private var ffprobe = ""
    private var folder = URL(fileURLWithPath: "/")

    override func setUpWithError() throws {
        guard let ffmpeg = tool("ffmpeg"), let ffprobe = tool("ffprobe") else {
            throw XCTSkip("ffmpeg/ffprobe not installed — tool checks skipped")
        }
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-preserve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

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

    /// Makes a file with this machine's ffmpeg; fails the test if it cannot.
    private func make(_ name: String, _ arguments: [String]) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let made = try run(ffmpeg, ["-v", "error", "-y"] + arguments + [url.path])
        XCTAssertEqual(made.status, 0, "making \(name)")
        return url
    }

    /// A one-second JPEG picture, to use as cover art.
    private func makePicture() throws -> URL {
        try make("cover.jpg", ["-f", "lavfi", "-i", "color=c=red:size=32x32:duration=1", "-frames:v", "1"])
    }

    /// What ffprobe says about each stream of `file`.
    private struct Seen {
        var type: String
        var codec: String
        var language: String?
        var title: String?
        var attachedPicture: Bool
        var fileName: String?
    }

    private func streams(_ file: URL) throws -> [Seen] {
        let (status, data) = try run(ffprobe, [
            "-v", "error", "-print_format", "json", "-show_entries",
            "stream=index,codec_type,codec_name:stream_tags=language,title,filename:stream_disposition=attached_pic",
            file.path
        ])
        XCTAssertEqual(status, 0)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["streams"] as? [[String: Any]] ?? []).map { stream in
            let tags = stream["tags"] as? [String: Any] ?? [:]
            func tag(_ key: String) -> String? {
                tags.first { $0.key.lowercased() == key }?.value as? String
            }
            return Seen(
                type: stream["codec_type"] as? String ?? "",
                codec: stream["codec_name"] as? String ?? "",
                language: tag("language"),
                title: tag("title"),
                attachedPicture: (stream["disposition"] as? [String: Any])?["attached_pic"] as? Int == 1,
                fileName: tag("filename")
            )
        }
    }

    /// Converts `source` with `profile` the way `EncodingEngine.encode`
    /// does the parts that matter here: a fresh probe, the cover-art copying
    /// step for a Matroska output, then MeedyaConverter's own arguments.
    @discardableResult
    private func convert(_ source: URL, to name: String, profile: EncodingProfile) async throws -> (output: URL, config: EncodingJobConfig) {
        let output = folder.appendingPathComponent(name)
        var config = EncodingJobConfig(inputURL: source, outputURL: output, profile: profile)
        config.sourceStreams = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: source).streams
        var copies: [Int: URL] = [:]
        for picture in config.attachedPicturesNeedingCopies() {
            let copy = folder.appendingPathComponent("copy-\(picture.streamIndex).\(picture.fileExtension)")
            let copied = try run(ffmpeg, AttachedPictures.extractionArguments(
                input: source, streamIndex: picture.streamIndex, output: copy
            ))
            XCTAssertEqual(copied.status, 0, "copying picture #\(picture.streamIndex)")
            copies[picture.streamIndex] = copy
        }
        if !copies.isEmpty { config.attachedPictureFiles = copies }
        XCTAssertEqual(config.streamSelectionProblems(), [])
        let encoded = try run(ffmpeg, ["-v", "error"] + config.buildArguments())
        XCTAssertEqual(encoded.status, 0, "encoding \(name)")
        return (output, config)
    }

    // MARK: - Cover art (review item 1)

    /// An M4A with cover art through "Remux to MP4": the audio stays first
    /// and the picture stays cover art (`attached_pic`).
    func test_m4aCoverArtSurvivesRemuxToMP4() async throws {
        let picture = try makePicture()
        let source = try make("song.m4a", [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3", "-i", picture.path,
            "-map", "0", "-map", "1", "-c:a", "aac", "-c:v", "copy",
            "-disposition:v:0", "attached_pic", "-metadata", "title=My Song"
        ])
        XCTAssertEqual(try streams(source).map(\.attachedPicture), [false, true], "the source as made")

        let (output, _) = try await convert(source, to: "out.mp4", profile: .remuxToMP4)
        let seen = try streams(output)
        XCTAssertEqual(seen.map(\.type), ["audio", "video"], "audio first")
        XCTAssertEqual(seen.map(\.attachedPicture), [false, true], "the picture is still cover art")
    }

    /// An MKV whose cover is a Matroska ATTACHMENT, through "Remux to MKV"
    /// (kept as an attachment, same name) and "Remux to MP4" (cover art).
    func test_matroskaCoverAttachmentSurvives() async throws {
        let picture = try makePicture()
        let source = try make("film.mkv", [
            "-f", "lavfi", "-i", "testsrc=size=64x48:rate=5:duration=0.4",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4",
            "-map", "0", "-map", "1", "-c:v", "mpeg4", "-c:a", "aac",
            "-attach", picture.path, "-metadata:s:t:0", "mimetype=image/jpeg",
            "-metadata:s:t:0", "filename=cover.jpg"
        ])
        let before = try streams(source)
        XCTAssertEqual(before.map(\.attachedPicture), [false, false, true], "ffprobe shows the attachment as a picture")

        let (mkv, config) = try await convert(source, to: "out.mkv", profile: .remuxToMKV)
        let seen = try streams(mkv)
        XCTAssertEqual(seen.map(\.type), ["video", "audio", "video"])
        XCTAssertEqual(seen.last?.attachedPicture, true, "still an attached picture, not a video track")
        XCTAssertEqual(seen.last?.fileName, "cover.jpg", "under its own name")
        XCTAssertEqual(config.trackWritingNotes(), [])

        let (mp4, _) = try await convert(source, to: "out.mp4", profile: .remuxToMP4)
        XCTAssertEqual(try streams(mp4).map(\.attachedPicture), [false, false, true])
    }

    // MARK: - Titles (review items 2 and 15)

    /// Whether this ffmpeg has the named encoder.
    private func hasEncoder(_ name: String) throws -> Bool {
        let listed = try run(ffmpeg, ["-hide_banner", "-encoders"])
        return String(bytes: listed.output, encoding: .utf8)?.contains(" \(name) ") ?? false
    }

    /// A song converted to Ogg keeps its title. In Ogg ffmpeg merges the
    /// file's title into the stream's comments, and the first build's
    /// automatic stream title ("English") replaced "My Song" there.
    func test_songTitleSurvivesConversionToOgg() async throws {
        let source = try make("music.m4a", [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.5", "-c:a", "aac",
            "-metadata:s:a:0", "language=eng", "-metadata", "title=My Song", "-metadata", "artist=Band"
        ])
        var checked = 0
        for (codec, name) in [(AudioCodec.vorbis, "out.ogg"), (AudioCodec.opus, "out.opus")] {
            guard let encoder = codec.ffmpegEncoder, try hasEncoder(encoder) else { continue }
            var profile = EncodingProfile.audioExtract
            profile.audioCodec = codec
            profile.containerFormat = .ogg
            let (output, _) = try await convert(source, to: name, profile: profile)
            XCTAssertEqual(try streams(output).map(\.title), ["My Song"], "\(name): the song keeps its title")
            checked += 1
        }
        if checked == 0 { throw XCTSkip("this ffmpeg has neither libvorbis nor libopus") }
    }

    /// Two untitled audio tracks in Matroska get their languages' own names.
    func test_untitledTracksInMatroskaGetAutomaticTitles() async throws {
        let source = try make("two.mka", [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3",
            "-f", "lavfi", "-i", "sine=frequency=550:duration=0.3",
            "-map", "0", "-map", "1", "-c:a", "aac",
            "-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=jpn"
        ])
        let (output, _) = try await convert(source, to: "out.mka", profile: .remuxToMKV)
        XCTAssertEqual(try streams(output).map(\.title), ["English", "日本語"])
    }
}
