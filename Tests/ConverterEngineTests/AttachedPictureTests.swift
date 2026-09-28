// ============================================================================
// MeedyaConverter — AttachedPictureTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Cover art and every other stream flag must come through a copy or a
// conversion unchanged (language policy COMPAT-030). The independent review
// of the language policy work found that the argument builder wrote a
// `-disposition` for every output stream from the twelve ROLE flags only —
// and a `-disposition` value replaces ALL of a stream's flags — so an M4A's
// cover art lost `attached_pic`, became a default video track, and was
// sorted in front of the audio. These tests pin the fix:
//   * every flag ffprobe reports is kept (`attached_pic` modelled, the rest
//     by name), and an edit changes only the flags it can;
//   * pictures are not ordered as tracks: they go after every real track;
//   * in a Matroska output a picture with a copy is ATTACHED (`-attach`),
//     because ffmpeg's Matroska muxer would make it a video track.
// TrackPreservationToolTests checks the same with a real ffmpeg.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class AttachedPictureTests: XCTestCase {

    // MARK: - Helpers

    private func maps(_ args: [String]) -> [String] {
        zip(args, args.dropFirst()).filter { $0.0 == "-map" }.map(\.1)
    }

    /// Every `flag value` pair whose flag starts with `prefix`, as "flag value".
    private func pairs(_ args: [String], _ prefix: String) -> [String] {
        zip(args, args.dropFirst()).filter { $0.0.hasPrefix(prefix) }.map { "\($0.0) \($0.1)" }
    }

    /// A cover picture as ffprobe describes it.
    private func cover(_ index: Int, name: String? = nil) -> MediaStream {
        MediaStream(
            streamIndex: index, streamType: .video, codecName: "mjpeg",
            disposition: StreamDisposition(isAttachedPicture: true),
            attachmentFileName: name, attachmentMimeType: name == nil ? nil : "image/jpeg"
        )
    }

    private func remux(_ sources: [MediaStream], to output: String) -> FFmpegArgumentBuilder {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in")
        builder.outputURL = URL(fileURLWithPath: output)
        builder.sourceStreams = sources
        builder.mapAllStreams = true
        builder.videoPassthrough = true
        builder.audioPassthrough = true
        builder.subtitlePassthrough = true
        return builder
    }

    // MARK: - Every flag is kept

    func test_ffprobeFlagsAreAllKept() {
        let disposition = StreamDisposition(ffprobe: [
            "default": 0, "attached_pic": 1, "still_image": 1, "dependent": 0,
            "some_future_flag": 1, "comment": 1
        ])
        XCTAssertTrue(disposition.isAttachedPicture)
        XCTAssertTrue(disposition.isComment)
        XCTAssertEqual(disposition.otherFlags, ["some_future_flag", "still_image"])
        XCTAssertEqual(disposition.ffmpegValue, "comment+attached_pic+some_future_flag+still_image")
    }

    /// Data saved before the new fields existed still loads, as "not set".
    func test_olderSavedDispositionStillDecodes() throws {
        let old = Data(#"{"isDefault":true,"isForced":true}"#.utf8)
        let decoded = try JSONDecoder().decode(StreamDisposition.self, from: old)
        XCTAssertEqual(decoded, StreamDisposition(isDefault: true, isForced: true))
        XCTAssertFalse(decoded.isAttachedPicture)
        XCTAssertEqual(decoded.otherFlags, [])
    }

    func test_newFieldsSurviveSaving() throws {
        let original = StreamDisposition(isAttachedPicture: true, otherFlags: ["still_image"])
        let copy = try JSONDecoder().decode(StreamDisposition.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(copy, original)
    }

    /// Only names shaped like ffmpeg's own reach a `-disposition` value.
    func test_otherFlagsAreCleanedUp() {
        let disposition = StreamDisposition(otherFlags: ["still_image", "Bad Flag", "a+b", "default", "still_image", ""])
        XCTAssertEqual(disposition.otherFlags, ["still_image"])
    }

    /// `parse` matches whole names (it used to test "contains").
    func test_parseMatchesWholeNames() {
        let disposition = StreamDisposition.parse("default+attached_pic+still_image")
        XCTAssertTrue(disposition.isDefault)
        XCTAssertTrue(disposition.isAttachedPicture)
        XCTAssertEqual(disposition.otherFlags, ["still_image"])
        XCTAssertEqual(StreamDisposition.parse("0"), StreamDisposition())
    }

    // MARK: - Order and flags in the command

    /// The review's case: an M4A (audio #0, cover #1) through "Remux to MP4".
    /// Audio stays first; the picture keeps `attached_pic`.
    func test_m4aCoverStaysAfterTheAudioWithItsFlag() {
        let sources = [
            MediaStream(streamIndex: 0, streamType: .audio, codecName: "aac", language: "und",
                        disposition: StreamDisposition(isDefault: true)),
            cover(1)
        ]
        let args = remux(sources, to: "/tmp/out.mp4").build()
        XCTAssertEqual(maps(args), ["0:0", "0:1"])
        XCTAssertEqual(pairs(args, "-disposition"), ["-disposition:a:0 default", "-disposition:v:0 attached_pic"])
        XCTAssertFalse(args.contains("-attach"), "MP4 keeps a mapped picture as cover art by itself")
    }

    /// A picture that comes first in the source still goes after every real
    /// track, and never becomes the first video stream.
    func test_pictureFirstInTheSourceGoesLast() {
        let sources = [
            cover(0),
            MediaStream(streamIndex: 1, streamType: .video, codecName: "h264", disposition: StreamDisposition()),
            MediaStream(streamIndex: 2, streamType: .audio, language: "en", disposition: StreamDisposition()),
            MediaStream(streamIndex: 3, streamType: .subtitle, language: "en", disposition: StreamDisposition())
        ]
        let args = remux(sources, to: "/tmp/out.mp4").build()
        XCTAssertEqual(maps(args), ["0:1", "0:2", "0:3", "0:0"])
        XCTAssertTrue(pairs(args, "-disposition").contains("-disposition:v:1 attached_pic"))
    }

    /// With the policy's order switched off nothing moves — the picture too.
    func test_orderSwitchedOffLeavesThePictureWhereItWas() {
        var builder = remux([cover(0), MediaStream(streamIndex: 1, streamType: .audio, disposition: StreamDisposition())],
                            to: "/tmp/out.mp4")
        builder.orderTracksCanonically = false
        XCTAssertEqual(maps(builder.build()), ["0:0", "0:1"])
    }

    /// An edit changes only the flags the editor has switches for; the
    /// rest come from the file.
    func test_anEditKeepsTheFlagsItCannotChange() {
        var builder = remux([
            MediaStream(streamIndex: 0, streamType: .audio, language: "en",
                        disposition: StreamDisposition(isDefault: true, otherFlags: ["non_diegetic"]))
        ], to: "/tmp/out.mkv")
        builder.sourceStreamEdits = [0: SourceStreamEdit(disposition: StreamDisposition(isComment: true))]
        XCTAssertEqual(pairs(builder.build(), "-disposition"), ["-disposition:a:0 comment+non_diegetic"])
    }

    // MARK: - Matroska attachments

    /// A film with a font attachment (#3) and a named cover (#4), to MKV,
    /// with the engine's copy of the cover: the cover is ATTACHED under its
    /// own name, after the mapped font, and not mapped as a stream.
    func test_matroskaAttachesTheCopyUnderItsOwnName() {
        let sources = [
            MediaStream(streamIndex: 0, streamType: .video, codecName: "h264", disposition: StreamDisposition()),
            MediaStream(streamIndex: 1, streamType: .audio, language: "en", disposition: StreamDisposition()),
            MediaStream(streamIndex: 2, streamType: .subtitle, language: "en", disposition: StreamDisposition()),
            MediaStream(streamIndex: 3, streamType: .attachment, codecName: "ttf", disposition: StreamDisposition()),
            cover(4, name: "small_cover.jpg")
        ]
        var builder = remux(sources, to: "/tmp/out.mkv")
        builder.attachedPictureFiles = [4: URL(fileURLWithPath: "/tmp/pic-4.jpg")]
        let args = builder.build()
        XCTAssertEqual(maps(args), ["0:0", "0:1", "0:2", "0:3"])
        XCTAssertEqual(pairs(args, "-attach"), ["-attach /tmp/pic-4.jpg"])
        XCTAssertEqual(pairs(args, "-metadata:s:t:"), [
            "-metadata:s:t:1 mimetype=image/jpeg", "-metadata:s:t:1 filename=small_cover.jpg"
        ], "the mapped font is attachment 0, so the picture is attachment 1")
        XCTAssertFalse(pairs(args, "-disposition").contains { $0.contains("attached_pic") })
        XCTAssertEqual(builder.trackWritingNotes(), [])
    }

    /// Without a copy (paths that build one command and nothing else) the
    /// picture is mapped, keeping its flag, and the notes say what ffmpeg
    /// will make of it.
    func test_matroskaWithoutACopyMapsThePictureAndSaysSo() {
        let builder = remux([MediaStream(streamIndex: 0, streamType: .audio, disposition: StreamDisposition()), cover(1)],
                            to: "/tmp/out.mka")
        let args = builder.build()
        XCTAssertEqual(maps(args), ["0:0", "0:1"])
        XCTAssertFalse(args.contains("-attach"))
        XCTAssertTrue(pairs(args, "-disposition").contains("-disposition:v:0 attached_pic"))
        XCTAssertEqual(builder.trackWritingNotes().count, 1)
        XCTAssertTrue(builder.trackWritingNotes()[0].hasPrefix("Stream #1 is a picture attached to the file"))
    }

    /// Only a Matroska output needs copies — not MP4, not WebM.
    func test_onlyMatroskaNeedsCopies() {
        let sources = [MediaStream(streamIndex: 0, streamType: .audio, disposition: StreamDisposition()), cover(1)]
        XCTAssertEqual(remux(sources, to: "/tmp/out.mkv").attachedPicturesNeedingCopies().map(\.streamIndex), [1])
        XCTAssertEqual(remux(sources, to: "/tmp/out.mkv").attachedPicturesNeedingCopies().map(\.fileExtension), ["jpg"])
        XCTAssertTrue(remux(sources, to: "/tmp/out.mp4").attachedPicturesNeedingCopies().isEmpty)
        XCTAssertTrue(remux(sources, to: "/tmp/out.webm").attachedPicturesNeedingCopies().isEmpty)
    }

    /// Pictures with no name of their own (MP4 cover art) get Matroska's
    /// conventional `cover.<ext>`; with two, the stream number keeps them
    /// apart.
    func test_unnamedPicturesGetConventionalNames() {
        let one = remux([MediaStream(streamIndex: 0, streamType: .audio, disposition: StreamDisposition()), cover(1)],
                        to: "/tmp/out.mka")
        var withCopy = one
        withCopy.attachedPictureFiles = [1: URL(fileURLWithPath: "/tmp/p1.jpg")]
        XCTAssertTrue(pairs(withCopy.build(), "-metadata:s:t:").contains("-metadata:s:t:0 filename=cover.jpg"))

        var two = remux([MediaStream(streamIndex: 0, streamType: .audio, disposition: StreamDisposition()), cover(1), cover(2)],
                        to: "/tmp/out.mka")
        two.attachedPictureFiles = [1: URL(fileURLWithPath: "/tmp/p1.jpg"), 2: URL(fileURLWithPath: "/tmp/p2.jpg")]
        let names = pairs(two.build(), "-metadata:s:t:").filter { $0.contains("filename=") }
        XCTAssertEqual(names, ["-metadata:s:t:0 filename=cover-1.jpg", "-metadata:s:t:1 filename=cover-2.jpg"])
    }

    /// The copying step's own arguments: a byte-for-byte copy of one frame.
    func test_extractionArguments() {
        let args = AttachedPictures.extractionArguments(
            input: URL(fileURLWithPath: "/tmp/in.m4a"), streamIndex: 1, output: URL(fileURLWithPath: "/tmp/p.jpg")
        )
        XCTAssertEqual(args, ["-y", "-nostdin", "-v", "error", "-i", "/tmp/in.m4a", "-map", "0:1",
                              "-c", "copy", "-frames:v", "1", "-f", "image2", "/tmp/p.jpg"])
    }
}
