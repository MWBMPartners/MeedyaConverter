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
//     under its own name and with its description, because ffmpeg's
//     Matroska muxer would make it a video track.
// The SECOND independent review found WebM jobs with cover art failing
// outright, cover art turned into a `bin_data` stream (MPEG-TS) or a stray
// MJPEG track (AVI), dropped without a word (MOV, Ogg, audio-only MP4), and
// Matroska covers renamed and stripped of their descriptions. Pictures a file
// type cannot hold are now left out, with a note.
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

    /// Without a copy (the copying step failed, or a caller built the
    /// command without running it) the picture is LEFT OUT, and the notes
    /// say so. The round-2 build mapped it, so ffmpeg made it a one-frame
    /// video track — and its note said so even when the output had no video
    /// and the picture was simply dropped (the second review's finding).
    func test_matroskaWithoutACopyLeavesThePictureOutAndSaysSo() {
        let builder = remux([MediaStream(streamIndex: 0, streamType: .audio, disposition: StreamDisposition()), cover(1)],
                            to: "/tmp/out.mka")
        let args = builder.build()
        XCTAssertEqual(maps(args), ["0:0"])
        XCTAssertFalse(args.contains("-attach"))
        XCTAssertFalse(pairs(args, "-disposition").contains { $0.contains("attached_pic") })
        XCTAssertEqual(builder.trackWritingNotes(), [
            "Stream #1 is a picture attached to the file (cover art). A Matroska file can only keep it as an "
                + "attachment, and it could not be copied out of the source to attach, so it is left out."
        ])
    }

    /// A picture in a format with no known file type cannot be attached:
    /// left out of a Matroska output, with a note naming the format.
    func test_matroskaLeavesOutAPictureItCannotAttach() {
        let odd = MediaStream(streamIndex: 1, streamType: .video, codecName: "jpegxl",
                              disposition: StreamDisposition(isAttachedPicture: true))
        var builder = remux([MediaStream(streamIndex: 0, streamType: .audio, disposition: StreamDisposition()), odd],
                            to: "/tmp/out.mkv")
        builder.attachedPictureFiles = [1: URL(fileURLWithPath: "/tmp/p1.jxl")]
        XCTAssertEqual(maps(builder.build()), ["0:0"])
        XCTAssertTrue(builder.attachedPicturesNeedingCopies().isEmpty)
        XCTAssertEqual(builder.trackWritingNotes().count, 1)
        XCTAssertTrue(builder.trackWritingNotes()[0].contains("(jpegxl) is not one MeedyaConverter can attach"))
    }

    // MARK: - File types that cannot hold pictures (second review, items 1 and 6)

    /// A film with cover art to a file type ffmpeg cannot write pictures
    /// into. WebM refused the whole job (exit 234 — the second review's
    /// must-fix 1), MPEG-TS gained a `bin_data` stream, AVI a stray MJPEG
    /// track, and MOV and Ogg lost it without a word. Now the picture is not
    /// mapped at all, and the notes say so.
    func test_fileTypesThatCannotHoldPicturesLeaveThemOutAndSaySo() {
        let sources = [
            MediaStream(streamIndex: 0, streamType: .video, codecName: "h264", disposition: StreamDisposition()),
            MediaStream(streamIndex: 1, streamType: .audio, language: "en", disposition: StreamDisposition()),
            cover(2, name: "cover.jpg")
        ]
        for (output, name) in [("/tmp/out.webm", "WebM"), ("/tmp/out.ts", "MPEG-TS (Transport Stream)"),
                               ("/tmp/out.avi", "AVI"), ("/tmp/out.mov", "MOV (QuickTime)"), ("/tmp/out.ogg", "OGG"),
                               ("/tmp/out.3gp", "3GP"), ("/tmp/out.mpg", "MPEG-PS (Program Stream)")] {
            let builder = remux(sources, to: output)
            let args = builder.build()
            XCTAssertEqual(maps(args), ["0:0", "0:1"], "\(output): the picture is not mapped")
            XCTAssertFalse(args.contains("-attach"), output)
            XCTAssertFalse(pairs(args, "-disposition").contains { $0.contains("attached_pic") }, output)
            XCTAssertEqual(builder.trackWritingNotes(), [
                "Stream #2 is a picture attached to the file (cover art). ffmpeg cannot write pictures into this "
                    + "file type (\(name)), so it is left out."
            ], output)
            XCTAssertTrue(builder.attachedPicturesNeedingCopies().isEmpty, output)
        }
    }

    /// An audio-only output (`-vn`) to MP4/M4A: ffmpeg drops a mapped picture
    /// with the video, so it is left out and noted. The same profile to a
    /// Matroska file keeps it, because it is attached, not mapped.
    func test_anOutputWithNoVideoLeavesMappedPicturesOutButAttachesInMatroska() {
        let sources = [
            MediaStream(streamIndex: 0, streamType: .audio, codecName: "aac", language: "und",
                        disposition: StreamDisposition(isDefault: true)),
            cover(1)
        ]
        var m4a = remux(sources, to: "/tmp/out.m4a")
        m4a.videoPassthrough = false
        m4a.videoCodec = nil
        let args = m4a.build()
        XCTAssertTrue(args.contains("-vn"))
        XCTAssertEqual(maps(args), ["0:0"])
        XCTAssertEqual(m4a.trackWritingNotes(), [
            "Stream #1 is a picture attached to the file (cover art). This output has no video, and ffmpeg "
                + "drops pictures along with the video, so it is left out."
        ])

        var mka = remux(sources, to: "/tmp/out.mka")
        mka.videoPassthrough = false
        mka.videoCodec = nil
        mka.attachedPictureFiles = [1: URL(fileURLWithPath: "/tmp/p1.jpg")]
        let mkaArgs = mka.build()
        XCTAssertEqual(maps(mkaArgs), ["0:0"])
        XCTAssertEqual(pairs(mkaArgs, "-attach"), ["-attach /tmp/p1.jpg"])
        XCTAssertEqual(mka.trackWritingNotes(), [])
    }

    /// With no file type known (only possible when the builder is used
    /// directly) nothing was checked, so the picture is mapped as it always
    /// was.
    func test_anUnknownFileTypeStillMapsThePicture() {
        let builder = remux([MediaStream(streamIndex: 0, streamType: .audio, disposition: StreamDisposition()), cover(1)],
                            to: "/tmp/out.unknownext")
        XCTAssertEqual(maps(builder.build()), ["0:0", "0:1"])
        XCTAssertEqual(builder.trackWritingNotes(), [])
    }

    /// The table itself.
    func test_pictureSupportPerFileType() {
        XCTAssertEqual(AttachedPictures.pictureSupport(in: .mp4), .mappedAsCoverArt)
        XCTAssertEqual(AttachedPictures.pictureSupport(in: .m4a), .mappedAsCoverArt)
        XCTAssertEqual(AttachedPictures.pictureSupport(in: .mkv), .attachment)
        XCTAssertEqual(AttachedPictures.pictureSupport(in: .mka), .attachment)
        XCTAssertEqual(AttachedPictures.pictureSupport(in: .webm), .none)
        XCTAssertEqual(AttachedPictures.pictureSupport(in: .mov), .none)
        XCTAssertEqual(AttachedPictures.pictureSupport(in: nil), .unchecked)
    }

    // MARK: - Names and descriptions (second review, item 2)

    /// A Matroska cover keeps its own description: written as the
    /// attachment's `title`, which ffmpeg stores as FileDescription.
    func test_matroskaAttachmentKeepsItsDescription() {
        var picture = cover(1, name: "small_cover.png")
        picture.codecName = "png"
        picture.attachmentMimeType = "image/png"
        picture.title = "Back of the box"
        var builder = remux([MediaStream(streamIndex: 0, streamType: .audio, disposition: StreamDisposition()), picture],
                            to: "/tmp/out.mkv")
        builder.attachedPictureFiles = [1: URL(fileURLWithPath: "/tmp/p1.png")]
        XCTAssertEqual(pairs(builder.build(), "-metadata:s:t:"), [
            "-metadata:s:t:0 mimetype=image/png", "-metadata:s:t:0 filename=small_cover.png",
            "-metadata:s:t:0 title=Back of the box"
        ])

        // A description set in the stream editor wins; an empty one clears it.
        builder.sourceStreamEdits = [1: SourceStreamEdit(title: "Rear")]
        XCTAssertTrue(pairs(builder.build(), "-metadata:s:t:").contains("-metadata:s:t:0 title=Rear"))
        builder.sourceStreamEdits = [1: SourceStreamEdit(title: "")]
        XCTAssertFalse(pairs(builder.build(), "-metadata:s:t:").contains { $0.contains("title=") })
    }

    /// Two named covers keep both names (the second review found `cover-3.jpg`
    /// and `cover-4.png`, because the probe never asked ffprobe for them).
    func test_twoNamedCoversKeepTheirNames() {
        var small = cover(2, name: "small_cover.png")
        small.codecName = "png"
        var builder = remux([MediaStream(streamIndex: 0, streamType: .audio, disposition: StreamDisposition()),
                             cover(1, name: "cover.jpg"), small], to: "/tmp/out.mkv")
        builder.attachedPictureFiles = [1: URL(fileURLWithPath: "/tmp/p1.jpg"), 2: URL(fileURLWithPath: "/tmp/p2.png")]
        let names = pairs(builder.build(), "-metadata:s:t:").filter { $0.contains("filename=") }
        XCTAssertEqual(names, ["-metadata:s:t:0 filename=cover.jpg", "-metadata:s:t:1 filename=small_cover.png"])
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

    // MARK: - Re-encoded video

    /// A film with cover art, re-encoded to MP4: the picture is COPIED, not
    /// re-encoded with the film's encoder (MP4 cover art must stay JPEG/PNG,
    /// or ffmpeg refuses the job), and the video filters go to the real
    /// video only (a filter on a copied stream is refused too).
    func test_reencodedVideoCopiesThePictureAndFiltersOnlyTheVideo() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mp4")
        builder.sourceStreams = [
            MediaStream(streamIndex: 0, streamType: .video, codecName: "h264", disposition: StreamDisposition()),
            MediaStream(streamIndex: 1, streamType: .audio, language: "en", disposition: StreamDisposition()),
            cover(2)
        ]
        builder.videoCodec = .h264
        builder.audioCodec = .aacLC
        builder.videoFilterChain = "scale=80:60"
        let args = builder.build()
        XCTAssertEqual(maps(args), ["0:0", "0:1", "0:2"])
        XCTAssertEqual(pairs(args, "-c:v"), ["-c:v libx264", "-c:v:1 copy"])
        XCTAssertEqual(pairs(args, "-filter:v"), ["-filter:v:0 scale=80:60"])
        XCTAssertFalse(args.contains("-vf"))
    }

    /// Without cover art nothing changes: one `-vf` for all video.
    func test_withoutPicturesTheFilterIsUnchanged() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mp4")
        builder.sourceStreams = [MediaStream(streamIndex: 0, streamType: .video, disposition: StreamDisposition())]
        builder.videoCodec = .h264
        builder.videoFilterChain = "scale=80:60"
        let args = builder.build()
        XCTAssertEqual(pairs(args, "-vf"), ["-vf scale=80:60"])
        XCTAssertFalse(args.contains { $0.hasPrefix("-c:v:") })
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
