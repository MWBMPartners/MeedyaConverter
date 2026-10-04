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
// back with ffprobe — the way the review reproduced them. The second
// independent review's cover-art findings (WebM, MPEG-TS, AVI, audio-only
// MP4, Matroska names and descriptions) are checked the same way.
//
// Skipped when ffmpeg/ffprobe are not installed, per CONTRIBUTING's rule for
// tests that need FFmpeg — but FAILED in CI's build-and-test job, which
// installs the tools and requires them (`MediaTools.missing`). First run 28 Sept 2026
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
        guard let ffmpeg = MediaTools.find("ffmpeg"), let ffprobe = MediaTools.find("ffprobe") else {
            try MediaTools.missing("ffmpeg/ffprobe not installed — tool checks")
        }
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("meedya-preserve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
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
    private func convert(
        _ source: URL,
        to name: String,
        profile: EncodingProfile,
        videoFilter: String? = nil,
        mapAll: Bool = false
    ) async throws -> (output: URL, config: EncodingJobConfig) {
        let output = folder.appendingPathComponent(name)
        var config = EncodingJobConfig(inputURL: source, outputURL: output, profile: profile, videoFilterChain: videoFilter)
        config.mapAllStreams = mapAll
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

    /// Re-encoding the video keeps the cover art as it was: an M4A with a
    /// cover through "Quick Convert" (H.264/AAC in MP4), and a film with an
    /// attached cover, re-encoded and scaled. With the cover's flag kept but
    /// the picture re-encoded as H.264, ffmpeg refuses the whole job.
    func test_coverArtSurvivesAVideoReencode() async throws {
        let picture = try makePicture()
        let song = try make("song.m4a", [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3", "-i", picture.path,
            "-map", "0", "-map", "1", "-c:a", "aac", "-c:v", "copy", "-disposition:v:0", "attached_pic"
        ])
        let (fromSong, _) = try await convert(song, to: "song.mp4", profile: .quickConvert)
        let seenSong = try streams(fromSong)
        XCTAssertEqual(seenSong.map(\.type), ["audio", "video"])
        XCTAssertEqual(seenSong.last?.attachedPicture, true)
        XCTAssertEqual(seenSong.last?.codec, "mjpeg", "copied, not re-encoded")

        let film = try make("film.mkv", [
            "-f", "lavfi", "-i", "testsrc=size=64x48:rate=5:duration=0.4",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4",
            "-map", "0", "-map", "1", "-c:v", "mpeg4", "-c:a", "aac",
            "-attach", picture.path, "-metadata:s:t:0", "mimetype=image/jpeg",
            "-metadata:s:t:0", "filename=cover.jpg"
        ])
        let (fromFilm, _) = try await convert(film, to: "film.mp4", profile: .quickConvert, videoFilter: "scale=32:24")
        let seenFilm = try streams(fromFilm)
        XCTAssertEqual(seenFilm.map(\.codec), ["h264", "aac", "mjpeg"])
        XCTAssertEqual(seenFilm.map(\.attachedPicture), [false, false, true])
    }

    // MARK: - Cover art, second review (items 1, 2 and 6)

    /// A PNG picture, to use as a second cover.
    private func makePNG(_ name: String) throws -> URL {
        try make(name, ["-f", "lavfi", "-i", "color=c=blue:size=16x16:duration=1", "-frames:v", "1"])
    }

    /// A small film (MPEG-4 video, AAC audio) with `pictures` attached as
    /// Matroska attachments: (file, MIME type, description).
    private func makeFilm(_ name: String, pictures: [(URL, String, String?)]) throws -> URL {
        var arguments = [
            "-f", "lavfi", "-i", "testsrc=size=64x48:rate=5:duration=0.4",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4",
            "-map", "0", "-map", "1", "-c:v", "mpeg4", "-c:a", "aac"
        ]
        for (index, picture) in pictures.enumerated() {
            arguments += ["-attach", picture.0.path, "-metadata:s:t:\(index)", "mimetype=\(picture.1)",
                          "-metadata:s:t:\(index)", "filename=\(picture.0.lastPathComponent)"]
            if let description = picture.2 {
                arguments += ["-metadata:s:t:\(index)", "title=\(description)"]
            }
        }
        return try make(name, arguments)
    }

    /// Cover art to WebM: ffmpeg refused the whole job (exit 234) in the
    /// round-2 build — the second review's must-fix 1. Now the picture is
    /// left out, the job succeeds, and the notes say so. Needs VP9 and Opus
    /// encoders (skipped without them).
    func test_coverArtToWebMIsLeftOutAndTheJobSucceeds() async throws {
        guard try hasEncoder("libvpx-vp9"), try hasEncoder("libopus") else {
            try MediaTools.missing("this ffmpeg has no libvpx-vp9 or libopus")
        }
        let film = try makeFilm("film.mkv", pictures: [(try makePicture(), "image/jpeg", nil)])
        var profile = EncodingProfile.webNextGen
        profile.videoCodec = .vp9
        profile.videoCRF = 40
        profile.videoPreset = nil
        let (output, config) = try await convert(film, to: "out.webm", profile: profile)
        XCTAssertEqual(try streams(output).map(\.type), ["video", "audio"])
        XCTAssertEqual(config.trackWritingNotes(), [
            "Stream #2 is a picture attached to the file (cover art). ffmpeg cannot write pictures into this "
                + "file type (WebM), so it is left out."
        ])
    }

    /// A Matroska cover keeps its own name and description. The second
    /// review found `small_cover.png` described "Back of the box" came out as
    /// `cover.png` with no description: the probe never asked ffprobe for
    /// `filename`, and the description was never written.
    func test_matroskaCoverKeepsItsNameAndDescription() async throws {
        let film = try makeFilm("film.mkv", pictures: [(try makePNG("small_cover.png"), "image/png", "Back of the box")])
        let (output, _) = try await convert(film, to: "out.mkv", profile: .remuxToMKV)
        let picture = try streams(output).last
        XCTAssertEqual(picture?.attachedPicture, true)
        XCTAssertEqual(picture?.fileName, "small_cover.png")
        XCTAssertEqual(picture?.title, "Back of the box")
    }

    /// Two covers keep both names (no `cover-3.jpg`, `cover-4.png`).
    func test_twoMatroskaCoversKeepTheirNames() async throws {
        let film = try makeFilm("film.mkv", pictures: [
            (try makePicture(), "image/jpeg", nil), (try makePNG("small_cover.png"), "image/png", nil)
        ])
        let (output, _) = try await convert(film, to: "out.mkv", profile: .remuxToMKV)
        XCTAssertEqual(try streams(output).compactMap(\.fileName), ["cover.jpg", "small_cover.png"])
    }

    /// GIF and TIFF covers to MP4: ffmpeg's MP4 writer takes only JPEG, PNG or
    /// BMP cover art, and refused the WHOLE job (exit 234) when a GIF or TIFF
    /// picture was mapped — the third independent review. Now the job
    /// succeeds, those two are left out with a note each, and a JPEG cover
    /// beside them is kept as cover art.
    func test_gifAndTIFFCoversToMP4AreLeftOutAndTheJobSucceeds() async throws {
        let gif = try make("back.gif", ["-f", "lavfi", "-i", "color=c=green:size=16x16:duration=1", "-frames:v", "1"])
        let tiff = try make("disc.tif", ["-f", "lavfi", "-i", "color=c=yellow:size=16x16:duration=1", "-frames:v", "1"])
        let film = try makeFilm("film.mkv", pictures: [
            (gif, "image/gif", nil), (tiff, "image/tiff", nil), (try makePicture(), "image/jpeg", nil)
        ])
        XCTAssertEqual(try streams(film).map(\.codec), ["mpeg4", "aac", "gif", "tiff", "mjpeg"], "the source as made")
        let (output, config) = try await convert(film, to: "out.mp4", profile: .remuxToMP4)
        let seen = try streams(output)
        XCTAssertEqual(seen.map(\.codec), ["mpeg4", "aac", "mjpeg"], "only the JPEG cover is written")
        XCTAssertEqual(seen.last?.attachedPicture, true, "and it is still cover art")
        XCTAssertEqual(config.trackWritingNotes(), [("#2", "GIF"), ("#3", "TIFF")].map {
            "Stream \($0.0) is a picture attached to the file (cover art). ffmpeg can only write JPEG, PNG or BMP "
                + "cover art into MP4 (MPEG-4 Part 14) files, and this picture is \($0.1), so it is left out."
        })
    }

    /// The engine ALWAYS replaces a job's saved picture list
    /// (`attachedPictureFiles`) with the copies it made just now — even when
    /// it made none. A job file is saved with that list, so it can carry
    /// paths from an earlier run, or ones written by hand; only a copy made
    /// in this job's own temporary folder may be attached. The second review
    /// found the list replaced only when a copy was made, and the third found
    /// no test would notice if that came back (its planted fault M15 failed
    /// nothing). Here the real `EncodingEngine.encode` runs with a stand-in
    /// for ffmpeg that refuses only the picture copy (the one command writing
    /// an `image2` file) and runs the real ffmpeg for everything else; the
    /// job carries a stale picture for the source's cover. The cover must be
    /// left out — never replaced by the stale file.
    func test_theEngineNeverAttachesASavedPictureListItDidNotJustMake() async throws {
        let film = try makeFilm("film.mkv", pictures: [(try makePicture(), "image/jpeg", nil)])
        XCTAssertEqual(try streams(film).map(\.attachedPicture), [false, false, true], "the source as made")

        let stand = folder.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: stand, withIntermediateDirectories: true)
        let wrapper = stand.appendingPathComponent("ffmpeg")
        let script = "#!/bin/sh\n"
            + "# Test stand-in: refuse the picture copy (-f image2), run the real ffmpeg for everything else.\n"
            + "for argument in \"$@\"; do [ \"$argument\" = image2 ] && exit 1; done\n"
            + "exec '\(ffmpeg)' \"$@\"\n"
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)

        let stale = try makePNG("stale.png")
        let output = folder.appendingPathComponent("out.mkv")
        var job = EncodingJobConfig(inputURL: film, outputURL: output, profile: .remuxToMKV)
        job.attachedPictureFiles = [2: stale]
        let temporary = folder.appendingPathComponent("engine-temp")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let engine = EncodingEngine(ffmpegPath: wrapper.path, ffprobePath: ffprobe, tempDirectory: temporary)
        try engine.configure()
        try await engine.encode(job: job)

        let seen = try streams(output)
        XCTAssertEqual(seen.map(\.type), ["video", "audio"], "the cover is left out; the stale picture is not attached")
        XCTAssertFalse(seen.contains { $0.attachedPicture })
    }

    /// The fourth independent review: a Matroska film carrying a font and a
    /// BMP and a WebP picture — which ffmpeg reads as plain ATTACHMENTS, not
    /// as cover art — converted to MP4 with "map all streams" made ffmpeg
    /// refuse the WHOLE job (exit 234, "Could not find tag for codec none");
    /// MOV the same, MPEG-TS turned the font into a `bin_data` stream, and
    /// WebM dropped it without a word. Without "map all streams" the
    /// attachments were dropped
    /// without a word. Now each job succeeds, only the video and audio are
    /// written, and every attachment is noted — with or without "map all
    /// streams".
    func test_attachmentsAreLeftOutOfOtherFileTypesAndTheJobSucceeds() async throws {
        // ffmpeg never reads an attachment's bytes, so the font and the WebP
        // picture are stand-ins: a TrueType signature, and a RIFF/WEBP one.
        let font = folder.appendingPathComponent("f.ttf")
        try Data([0x00, 0x01, 0x00, 0x00] + [UInt8](repeating: 0, count: 60)).write(to: font)
        let webp = folder.appendingPathComponent("f.webp")
        try Data(Array("RIFF".utf8) + [0x04, 0, 0, 0] + Array("WEBP".utf8)).write(to: webp)
        let bmp = try make("c.bmp", ["-f", "lavfi", "-i", "color=c=blue:size=16x16:duration=1", "-frames:v", "1"])
        let film = try makeFilm("film.mkv", pictures: [(font, "font/ttf", nil), (bmp, "image/bmp", nil), (webp, "image/webp", nil)])
        XCTAssertEqual(try streams(film).map(\.type), ["video", "audio", "attachment", "attachment", "attachment"],
                       "the source as made: three plain attachments")

        let rows: [(name: String, container: ContainerFormat, mapAll: Bool)] = [
            ("all.mp4", .mp4, true), ("chosen.mp4", .mp4, false), ("all.mov", .mov, true), ("all.ts", .mpegTS, true)
        ]
        for row in rows {
            var profile = EncodingProfile.remuxToMP4
            profile.containerFormat = row.container
            let (output, config) = try await convert(film, to: row.name, profile: profile, mapAll: row.mapAll)
            XCTAssertEqual(try streams(output).map(\.type), ["video", "audio"], "\(row.name): nothing else is written")
            XCTAssertEqual(config.trackWritingNotes(), [
                "Stream #2 is a font attached to the file (“f.ttf”, font/ttf).",
                "Stream #3 is a picture attached to the file (“c.bmp”, image/bmp) that ffmpeg reads as a plain "
                    + "attachment, not as cover art.",
                "Stream #4 is a picture attached to the file (“f.webp”, image/webp) that ffmpeg reads as a plain "
                    + "attachment, not as cover art."
            ].map {
                $0 + " Only a Matroska file can hold attachments, so it is left out of this \(row.container.displayName) file."
            }, row.name)
        }

        // Matroska with "map all streams" still copies all three.
        let (mkv, mkvJob) = try await convert(film, to: "all.mkv", profile: .remuxToMKV, mapAll: true)
        XCTAssertEqual(try streams(mkv).compactMap(\.fileName), ["f.ttf", "c.bmp", "f.webp"])
        XCTAssertEqual(mkvJob.trackWritingNotes(), [])
    }

    /// MPEG-TS turned the cover into a `bin_data` stream and AVI into a stray
    /// MJPEG video track. Now it is left out of both, with a note.
    func test_coverArtIsLeftOutOfTransportStreamAndAVI() async throws {
        let film = try makeFilm("film.mkv", pictures: [(try makePicture(), "image/jpeg", nil)])
        for (name, container) in [("out.ts", ContainerFormat.mpegTS), ("out.avi", ContainerFormat.avi)] {
            var profile = EncodingProfile.remuxToMKV
            profile.containerFormat = container
            let (output, config) = try await convert(film, to: name, profile: profile)
            XCTAssertEqual(try streams(output).map(\.type), ["video", "audio"], "\(name): nothing else")
            XCTAssertEqual(config.trackWritingNotes().count, 1, name)
            XCTAssertTrue(config.trackWritingNotes().first?.contains("is left out") == true, name)
        }
    }

    /// An audio-only output to M4A (`-vn`): ffmpeg drops the cover with the
    /// video, so it is left out and the notes say so (it was dropped without
    /// a word). The same to Matroska audio keeps it, as an attachment.
    func test_audioOnlyOutputsNoteOrKeepTheCover() async throws {
        let song = try make("song.m4a", [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3", "-i", try makePicture().path,
            "-map", "0", "-map", "1", "-c:a", "aac", "-c:v", "copy", "-disposition:v:0", "attached_pic"
        ])
        var toM4A = EncodingProfile.audioExtract
        toM4A.audioCodec = .aacLC
        toM4A.audioBitrate = 96_000
        toM4A.containerFormat = .m4a
        let (m4a, m4aJob) = try await convert(song, to: "out.m4a", profile: toM4A)
        XCTAssertEqual(try streams(m4a).map(\.type), ["audio"])
        XCTAssertEqual(m4aJob.trackWritingNotes().count, 1)
        XCTAssertTrue(m4aJob.trackWritingNotes().first?.contains("This output has no video") == true)

        let (mka, mkaJob) = try await convert(song, to: "out.mka", profile: .audioExtract)
        XCTAssertEqual(try streams(mka).map(\.attachedPicture), [false, true], "attached, so kept")
        XCTAssertEqual(mkaJob.trackWritingNotes(), [])
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
        if checked == 0 { try MediaTools.missing("this ffmpeg has neither libvorbis nor libopus") }
    }

    // MARK: - Languages (review items 3 and 4)

    /// Four audio tracks tagged `yue`, `cmn`, `nan` (valid languages with no
    /// three-letter code) and `deu`, in `name`'s container.
    private func makeFourLanguages(_ name: String) throws -> URL {
        var arguments = ["-f", "lavfi", "-i", "testsrc=size=64x48:rate=5:duration=0.4"]
        for frequency in [440, 550, 660, 770] {
            arguments += ["-f", "lavfi", "-i", "sine=frequency=\(frequency):duration=0.4"]
        }
        arguments += ["-map", "0", "-map", "1", "-map", "2", "-map", "3", "-map", "4", "-c:v", "mpeg4", "-c:a", "aac"]
        for (index, code) in ["yue", "cmn", "nan", "deu"].enumerated() {
            arguments += ["-metadata:s:a:\(index)", "language=\(code)"]
        }
        return try make(name, arguments)
    }

    /// The audio languages ffprobe reads from `file`, sorted.
    private func audioLanguages(_ file: URL) throws -> [String] {
        try streams(file).filter { $0.type == "audio" }.map { $0.language ?? "(none)" }.sorted()
    }

    /// `yue`, `cmn` and `nan` survive a remux to MKV and to MP4, from MKV
    /// and from MP4; `deu` still becomes `ger` in Matroska (a correction —
    /// nothing is lost). The first build wrote `und` over the other three.
    func test_languagesWithNoThreeLetterCodeSurvive() async throws {
        for sourceName in ["langs.mkv", "langs.mp4"] {
            let source = try makeFourLanguages(sourceName)
            let (mkv, mkvJob) = try await convert(source, to: "from-\(sourceName).mkv", profile: .remuxToMKV)
            XCTAssertEqual(try audioLanguages(mkv), ["cmn", "ger", "nan", "yue"], "\(sourceName) → MKV")
            XCTAssertEqual(mkvJob.trackWritingNotes().count, 3, "each kept value is reported")
            let (mp4, _) = try await convert(source, to: "from-\(sourceName).mp4", profile: .remuxToMP4)
            XCTAssertEqual(try audioLanguages(mp4), ["cmn", "deu", "nan", "yue"], "\(sourceName) → MP4")
        }
    }

    /// Values nothing can read (`english`, `xx-bogus`) are kept as they were,
    /// not replaced with `und`.
    func test_unrecognisedLanguageTextSurvives() async throws {
        let source = try make("unrec.mkv", [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3",
            "-f", "lavfi", "-i", "sine=frequency=550:duration=0.3",
            "-map", "0", "-map", "1", "-c:a", "aac",
            "-metadata:s:a:0", "language=english", "-metadata:s:a:1", "language=xx-bogus"
        ])
        let (output, job) = try await convert(source, to: "out.mkv", profile: .remuxToMKV)
        XCTAssertEqual(try audioLanguages(output), ["english", "xx-bogus"])
        XCTAssertEqual(job.trackWritingNotes().count, 2)
    }

    /// `xx-bogus` to Ogg: kept whole (Ogg's field holds any text), and the
    /// job's notes say it is not a registered language — the third
    /// independent review found no note at all. Needs the Opus encoder.
    func test_anUnregisteredLanguageToOggIsKeptAndNoted() async throws {
        guard try hasEncoder("libopus") else { try MediaTools.missing("this ffmpeg has no libopus") }
        let source = try make("bogus.mkv", [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3", "-c:a", "aac", "-metadata:s:a:0", "language=xx-bogus"
        ])
        var profile = EncodingProfile.audioExtract
        profile.audioCodec = .opus
        profile.containerFormat = .ogg
        let (output, job) = try await convert(source, to: "out.ogg", profile: profile)
        XCTAssertEqual(try streams(output).map(\.language), ["xx-bogus"])
        XCTAssertEqual(job.trackWritingNotes(), [
            "Stream #0: the file's language “xx-bogus” is not a registered language code; kept as the source had it. "
                + "Set the right language in the stream editor if you know it."
        ])
    }

    /// An edit MOV cannot store must leave the track with NO language: `sv`
    /// (Swedish is on ffmpeg's QuickTime list only as `sve`, which other
    /// programs read as Serili, the language that code is registered for, so
    /// it is never written for Swedish from elsewhere) and
    /// `english` (not a language tag at all, as a job file could carry).
    /// The round-3 build gave ffmpeg nothing for them, so ffmpeg copied the
    /// source's `eng` in — under a note saying "no language is stored" (the
    /// third independent review's must-fix). Read back with ffprobe and
    /// with Apple's AVFoundation.
    func test_editsMOVCannotStoreLeaveNoLanguage() async throws {
        let source = try make("english.mkv", [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3",
            "-f", "lavfi", "-i", "sine=frequency=550:duration=0.3",
            "-map", "0", "-map", "1", "-c:a", "aac",
            "-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=eng"
        ])
        let output = folder.appendingPathComponent("out.mov")
        var profile = EncodingProfile.remuxToMKV
        profile.containerFormat = .mov
        profile.orderTracksCanonically = false
        var config = EncodingJobConfig(inputURL: source, outputURL: output, profile: profile)
        config.sourceStreams = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: source).streams
        var swedish = SourceStreamEdit()
        swedish.language = "sv"
        var notATag = SourceStreamEdit()
        notATag.language = "english"
        config.sourceStreamEdits = [0: swedish, 1: notATag]
        XCTAssertEqual(try run(ffmpeg, ["-v", "error"] + config.buildArguments()).status, 0, "encoding out.mov")

        XCTAssertEqual(try streams(output).map(\.language), [nil, nil], "ffprobe: no language on either track")
        if let apple = try await MediaTools.appleAudioLanguages(of: output) {
            XCTAssertEqual(apple.map(\.isNone), [true, true], "AVFoundation: \(apple)")
        }
        XCTAssertEqual(config.trackWritingNotes(), [
            "Stream #0: this file type (QuickTime) can only store the languages on its old list; that list has "
                + "Swedish only as “sve”, which Apple's players read as Swedish but other programs read as Serili, the "
                + "language that code is registered for, so no language is stored.",
            "Stream #1: “english”, set in the stream editor, is not a language tag, so no language is stored."
        ])
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
