// ============================================================================
// MeedyaConverter — LanguageFieldTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// What each output stream's `language` field gets (TRACK-070), under the
// rule that a copy or conversion never loses what the source had
// (COMPAT-030) — `TrackLanguage.languageWrite`. The independent review of
// the language policy work found the first build wrote `und` over:
//   * valid languages with no three-letter code (`yue`, `cmn`, `nan`);
//   * values it could not recognise (`english`, `xx-bogus`).
// Both are now left for ffmpeg to copy, with a note in the job's log.
// TrackPreservationToolTests checks the same with a real ffmpeg.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class LanguageFieldTests: XCTestCase {

    // MARK: - Helpers

    private func write(
        _ source: String?,
        unrecognised: String? = nil,
        edited: String? = nil,
        to container: ContainerFormat?,
        replacement: Bool = false,
        keepSource: Bool = true
    ) -> TrackLanguage.LanguageWrite {
        TrackLanguage.languageWrite(
            streamNumber: 2, edited: edited, sourceLanguage: source, sourceUnrecognised: unrecognised,
            container: container, isReplacement: replacement, keepsSourceMetadata: keepSource
        )
    }

    // MARK: - Not edited: keep what the source had

    /// No three-letter code: nothing written, so ffmpeg copies `yue`.
    func test_languageWithNoThreeLetterCodeIsKept() {
        for tag in ["yue", "cmn", "nan"] {
            for container: ContainerFormat in [.mkv, .mp4] {
                let result = write(tag, to: container)
                XCTAssertNil(result.value, "\(tag) in \(container)")
                XCTAssertEqual(result.note, "Stream #2: language “\(tag)” has no three-letter code; kept as the source had it.")
            }
        }
    }

    /// A real correction loses nothing and is still made.
    func test_realCodesAreStillWrittenInTheContainersForm() {
        XCTAssertEqual(write("de", to: .mkv), .init(value: "ger", note: nil))
        XCTAssertEqual(write("de", to: .mp4), .init(value: "deu", note: nil))
        XCTAssertEqual(write("und", to: .mkv), .init(value: "und", note: nil), "the source said \"not known\"")
        XCTAssertEqual(write(nil, to: .mkv), .init(value: nil, note: nil), "the source said nothing")
    }

    /// An unrecognised value is left for ffmpeg to copy, with a note.
    func test_unrecognisedValueIsKept() {
        for container: ContainerFormat in [.mkv, .mp4, .ogg] {
            let result = write("und", unrecognised: "english", to: container)
            XCTAssertNil(result.value)
            XCTAssertTrue(result.note?.hasPrefix("Stream #2: the file's language “english” is not a language code; kept") == true)
        }
    }

    /// `xx-bogus` is shaped like a tag but its language is not registered:
    /// kept, and reported as not registered (the review's second example).
    func test_unregisteredTagIsKeptAndReportedAsSuch() {
        let result = write("xx-bogus", to: .mkv)
        XCTAssertNil(result.value)
        XCTAssertEqual(
            result.note,
            "Stream #2: the file's language “xx-bogus” is not a registered language code; kept as the source had it. "
                + "Set the right language in the stream editor if you know it."
        )
    }

    /// A region or script: Matroska keeps the source's text; MP4 can only
    /// hold the language, and says so.
    func test_regionIsKeptWhereTheFieldCanHoldIt() {
        let matroska = write("fr-CA", to: .mkv)
        XCTAssertNil(matroska.value)
        XCTAssertEqual(
            matroska.note,
            "Stream #2: language “fr-CA” cannot be written to this file type's three-letter language field "
                + "without losing “CA”; kept as the source had it."
        )
        let mp4 = write("fr-CA", to: .mp4)
        XCTAssertEqual(mp4.value, "fra")
        XCTAssertEqual(mp4.note, "Stream #2: this file type can only store the language, so “CA” in “fr-CA” is not saved (written as “fra”).")
    }

    /// Free-text fields (Ogg) take the whole canonical tag: nothing lost.
    func test_freeTextFieldsGetTheWholeTag() {
        XCTAssertEqual(write("yue", to: .ogg), .init(value: "yue", note: nil))
        XCTAssertEqual(write("zh-Hant-TW", to: .ogg), .init(value: "zh-Hant-TW", note: nil))
    }

    /// A replacement stream comes from a separate file with no tags, so
    /// "leave it for ffmpeg to copy" would lose it: the value is written.
    func test_replacementStreamsGetTheSourcesValueWritten() {
        XCTAssertEqual(write("yue", to: .mkv, replacement: true).value, "yue")
        XCTAssertEqual(write("und", unrecognised: "english", to: .mkv, replacement: true).value, "english")
    }

    /// With the source's metadata dropped, nothing of the source's is written.
    func test_droppedSourceMetadataWritesNothing() {
        XCTAssertEqual(write("yue", to: .mkv, keepSource: false), .init(value: nil, note: nil))
    }

    // MARK: - Edited: the person's tag, in the field's form

    func test_editedTagsAreWrittenWithANoteWhenSomethingCannotBeStored() {
        XCTAssertEqual(write("fr", edited: "en-GB", to: .mkv), .init(
            value: "eng",
            note: "Stream #2: this file type can only store the language, so “GB” in “en-GB” is not saved (written as “eng”)."
        ))
        XCTAssertEqual(write("fr", edited: "en-GB", to: .ogg), .init(value: "en-GB", note: nil))
        XCTAssertEqual(write("fr", edited: "yue", to: .mp4), .init(
            value: "und",
            note: "Stream #2: this file type can only store three-letter language codes, and “yue” has none, "
                + "so the language is written as “und” (not known)."
        ))
        XCTAssertEqual(write("fr", edited: "de", to: .mkv), .init(value: "ger", note: nil))
    }

    // MARK: - Through the argument builder

    /// The whole path: an MKV with `yue`, `cmn`, `nan`, `deu` and an
    /// unrecognised value, remuxed to MKV and to MP4.
    func test_theBuilderLeavesTheFieldAloneAndReportsIt() {
        let sources = [
            MediaStream(streamIndex: 0, streamType: .video, disposition: StreamDisposition()),
            MediaStream(streamIndex: 1, streamType: .audio, language: "yue", disposition: StreamDisposition()),
            MediaStream(streamIndex: 2, streamType: .audio, language: "de", disposition: StreamDisposition()),
            MediaStream(streamIndex: 3, streamType: .audio, language: "und", unrecognisedLanguage: "xx-bogus",
                        disposition: StreamDisposition())
        ]
        for (output, german) in [("/tmp/out.mkv", "ger"), ("/tmp/out.mp4", "deu")] {
            var builder = FFmpegArgumentBuilder()
            builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
            builder.outputURL = URL(fileURLWithPath: output)
            builder.sourceStreams = sources
            builder.mapAllStreams = true
            builder.videoPassthrough = true
            builder.audioPassthrough = true
            let args = builder.build()
            let languages = zip(args, args.dropFirst()).filter { $0.0.hasPrefix("-metadata:s:") && $0.1.hasPrefix("language=") }.map(\.1)
            XCTAssertEqual(languages, ["language=\(german)"], "\(output): only German is written")
            XCTAssertEqual(builder.trackWritingNotes().count, 2, "\(output): yue and xx-bogus are reported")
        }
    }
}
