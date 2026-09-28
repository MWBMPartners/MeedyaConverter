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
// Both are now left for ffmpeg to copy, with a note in the job's log — but
// ONLY where the output's writer really stores the text as it is. The second
// independent review found MP4 cutting `romanian` to `rom` (Romany), MPEG-TS
// dropping it, and MOV dropping German, Chinese and Greek, all while the note
// said "kept as the source had it". One table now says what each file type
// stores (`TrackLanguage.LanguageFieldStorage`); ContainerLanguageToolTests
// checks it against the real ffmpeg, and TrackPreservationToolTests checks
// whole conversions.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class LanguageFieldTests: XCTestCase {

    // MARK: - Helpers

    private func write(
        _ source: String?,
        unrecognised: String? = nil,
        stored: String? = nil,
        edited: String? = nil,
        to container: ContainerFormat?,
        replacement: Bool = false,
        keepSource: Bool = true
    ) -> TrackLanguage.LanguageWrite {
        TrackLanguage.languageWrite(
            streamNumber: 2, edited: edited, sourceLanguage: source, sourceUnrecognised: unrecognised,
            sourceStoredText: stored, container: container, isReplacement: replacement, keepsSourceMetadata: keepSource
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

    /// An unrecognised value is left for ffmpeg to copy, with a note — in
    /// the file types that store any text (Matroska, Ogg).
    func test_unrecognisedValueIsKeptWhereTheFieldHoldsAnyText() {
        for container: ContainerFormat in [.mkv, .webm, .ogg] {
            let result = write("und", unrecognised: "english", to: container)
            XCTAssertNil(result.value)
            XCTAssertTrue(result.note?.hasPrefix("Stream #2: the file's language “english” is not a language code; kept") == true)
        }
    }

    /// MP4 keeps only the first three letters, so an unrecognised value
    /// would be CUT — `romanian` to `rom`, which is Romany. The round-2 build
    /// left it to ffmpeg and said "kept as the source had it" (this test
    /// asserted that). Now `und`, and a note saying exactly what would have
    /// happened. MPEG-TS stores only three-letter codes, so it gets `und` too;
    /// MOV cannot even store `und`, so nothing is written there.
    func test_unrecognisedValueIsNotLeftToBeCutOrDropped() {
        XCTAssertEqual(write("und", unrecognised: "romanian", to: .mp4), .init(
            value: "und",
            note: "Stream #2: the file's language “romanian” is not a language code, and this file type would keep only "
                + "its first three letters, “rom”, which is itself a language code, and may not be the language meant, "
                + "so it is written as “und” (not known). Set the right language in the stream editor if you know it."
        ))
        XCTAssertEqual(write("und", unrecognised: "romanian", to: .mpegTS), .init(
            value: "und",
            note: "Stream #2: the file's language “romanian” is not a language code, and this file type can only store "
                + "codes of exactly three letters, so it is written as “und” (not known). Set the right language in the "
                + "stream editor if you know it."
        ))
        let mov = write("und", unrecognised: "english", to: .mov)
        XCTAssertNil(mov.value)
        XCTAssertEqual(
            mov.note,
            "Stream #2: the file's language “english” is not a language code, and this file type (QuickTime) can only "
                + "store the languages on its old list, so no language is stored. Set the right language in the stream "
                + "editor if you know it."
        )
        // A cut that is not a language code is said to be so.
        XCTAssertTrue(write("und", unrecognised: "zzzq", to: .mp4).note?.contains("“zzz”, which is not a language code") == true)
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

    // MARK: - What each file type stores (second review, must-fix 3)

    /// The table itself, value by value (ContainerLanguageToolTests checks
    /// the same values against the real ffmpeg).
    func test_whatEachFileTypeStores() {
        let mp4 = TrackLanguage.languageFieldStorage(for: .mp4)
        XCTAssertEqual(mp4, .firstThreeLowerCase)
        XCTAssertEqual(mp4.stored("deu"), "deu")
        XCTAssertEqual(mp4.stored("romanian"), "rom", "cut to three letters")
        XCTAssertNil(mp4.stored("de"))
        XCTAssertNil(mp4.stored("en-GB"))
        XCTAssertNil(mp4.stored("ENG"), "upper case is not stored")
        XCTAssertEqual(TrackLanguage.languageFieldStorage(for: .threeGP), .firstThreeLowerCase)

        let mov = TrackLanguage.languageFieldStorage(for: .mov)
        XCTAssertEqual(mov.stored("ger"), "ger")
        XCTAssertEqual(mov.stored("hr "), "hr ")
        XCTAssertNil(mov.stored("deu"), "not on the QuickTime list")
        XCTAssertNil(mov.stored("und"))

        let ts = TrackLanguage.languageFieldStorage(for: .mpegTS)
        XCTAssertEqual(ts.stored("ENG"), "ENG")
        XCTAssertEqual(ts.stored("eng,fre"), "eng,fre")
        XCTAssertEqual(ts.stored("eng,french"), "eng")
        XCTAssertNil(ts.stored("romanian"))

        XCTAssertEqual(TrackLanguage.languageFieldStorage(for: .mkv).stored("fr-CA"), "fr-CA")
        XCTAssertEqual(TrackLanguage.languageFieldStorage(for: .ogg).stored("romanian"), "romanian")
        for container: ContainerFormat in [.avi, .mpegPS, .flv, .mxf, .aiff, .caf, .w64, .rf64] {
            XCTAssertEqual(TrackLanguage.languageFieldStorage(for: container), .nothing, "\(container)")
        }
        XCTAssertEqual(TrackLanguage.languageFieldStorage(for: nil), .unchecked)
    }

    /// MOV gets the QuickTime list's entry for the same language — `ger`,
    /// `chi`, `gre`, `jpn` — where the round-2 build wrote `deu`, `zho` and
    /// `ell`, which MOV's writer drops without a word. A language not on the
    /// list (Swedish is listed as `sve`, which is not a language code and
    /// reads back as something else) cannot be kept, and the note says so.
    func test_movGetsTheQuickTimeListsCode() {
        XCTAssertEqual(write("de", to: .mov), .init(value: "ger", note: nil))
        XCTAssertEqual(write("zh", to: .mov), .init(value: "chi", note: nil))
        XCTAssertEqual(write("el", to: .mov), .init(value: "gre", note: nil))
        XCTAssertEqual(write("ja", to: .mov), .init(value: "jpn", note: nil))
        XCTAssertEqual(write("hr", to: .mov), .init(value: "hr ", note: nil), "the list's own label, space and all")
        XCTAssertEqual(write("und", to: .mov), .init(value: nil, note: nil), "MOV cannot store und; nothing is lost")
        XCTAssertEqual(write("sv", to: .mov), .init(
            value: nil,
            note: "Stream #2: this file type (QuickTime) can only store the languages on its old list, and “sv” is not "
                + "on it, so no language is stored."
        ))
        XCTAssertEqual(write("zh-Hant", to: .mov), .init(
            value: "chi",
            note: "Stream #2: this file type can only store the language, so “Hant” in “zh-Hant” is not saved "
                + "(written as “chi”)."
        ))
        XCTAssertEqual(TrackLanguage.languageFieldForm(for: .mov), .quickTimeList)
    }

    /// MPEG-TS keeps codes of exactly three letters, so `yue` is kept as it
    /// is; a region is cut with a note.
    func test_transportStreamKeepsThreeLetterCodes() {
        XCTAssertEqual(write("yue", to: .mpegTS).value, nil)
        XCTAssertEqual(write("yue", to: .mpegTS).note, "Stream #2: language “yue” has no three-letter code; kept as the source had it.")
        XCTAssertEqual(write("de", to: .mpegTS), .init(value: "deu", note: nil))
        XCTAssertEqual(write("fr-CA", stored: "fr-CA", to: .mpegTS).value, "fra")
    }

    /// A file type with no place for a track's language says so — the
    /// round-2 build wrote a code there, which vanished without a word.
    func test_fileTypesWithNoLanguageFieldSaySo() {
        XCTAssertEqual(write("en", to: .avi), .init(
            value: nil, note: "Stream #2: this file type has no place for a track's language, so “en” is not kept."
        ))
        XCTAssertEqual(write("und", to: .avi), .init(value: nil, note: nil), "“not known” loses nothing")
        XCTAssertEqual(write(nil, to: .avi), .init(value: nil, note: nil))
    }

    /// When the source's own field says LESS than its language — mkvmerge
    /// writes `chi` in the old field for Cantonese `yue` — copying it would
    /// turn Cantonese into Chinese. The language's own tag is written
    /// instead, where the file type keeps it as it is (Matroska, MP4), with
    /// a note; MOV cannot keep it and says so.
    func test_aSourceFieldThatSaysLessIsNotCopied() {
        XCTAssertEqual(write("yue", stored: "chi", to: .mkv), .init(
            value: "yue",
            note: "Stream #2: language “yue” has no three-letter code, so “yue” is written into the field as it is, "
                + "because copying the source's own field (“chi”) would not keep it."
        ))
        XCTAssertEqual(write("yue", stored: "chi", to: .mp4).value, "yue")
        XCTAssertNil(write("yue", stored: "chi", to: .mov).value)
        XCTAssertEqual(write("fr-CA", stored: "fre", to: .mkv).value, "fr-CA")
        XCTAssertEqual(write("fr-CA", stored: "fre", to: .mp4).value, "fra")
        // The source's own text is copied when it says the same.
        XCTAssertNil(write("fr-CA", stored: "fre-ca", to: .mkv).value)
    }

    /// With no file type known nothing can be promised: the code is written
    /// as before, and anything else becomes `und`, saying why.
    func test_anUnknownFileTypeWritesCodesOrUnd() {
        XCTAssertEqual(write("de", to: nil), .init(value: "deu", note: nil))
        XCTAssertEqual(write("yue", to: nil).value, "und")
        XCTAssertTrue(write("yue", to: nil).note?.contains("the output's file type is not known") == true)
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
        // `und-GB`: it is the REGION that cannot be stored (the round-2
        // build said "und-GB has no three-letter code").
        XCTAssertEqual(write("fr", edited: "und-GB", to: .mkv), .init(
            value: "und",
            note: "Stream #2: this file type can only store the language, so “GB” in “und-GB” is not saved (written as “und”)."
        ))
        XCTAssertEqual(StreamMetadataEditor.storageNote(for: "und-GB", in: .mkv),
                       "This file type can only store the language, so “GB” will not be saved.")
        // MOV and the file types with no language field.
        XCTAssertEqual(write("fr", edited: "de", to: .mov), .init(value: "ger", note: nil))
        XCTAssertEqual(write("fr", edited: "sv", to: .mov).value, nil)
        XCTAssertEqual(StreamMetadataEditor.storageNote(for: "sv", in: .mov),
                       "This file type (QuickTime) can only store the languages on its old list, and “sv” is not on it, "
                           + "so no language will be saved.")
        XCTAssertEqual(write("fr", edited: "de", to: .avi), .init(
            value: nil, note: "Stream #2: this file type has no place for a track's language, so “de”, set in the stream editor, is not saved."
        ))
        XCTAssertEqual(StreamMetadataEditor.storageNote(for: "de", in: .avi),
                       "This file type has no place for a track's language, so it will not be saved.")
    }

    // MARK: - The policy's data

    /// With the data bundled (as in every test run and every shipped build),
    /// there is no problem to report. When it is missing, `dataProblem` is
    /// what the app shows and what goes to standard error — never standard
    /// output, where it broke `probe --format json` (review item 13).
    func test_noDataProblemWhenTheDataIsThere() {
        XCTAssertNotNil(TrackLanguage.policy)
        XCTAssertNil(TrackLanguage.dataProblem)
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
        // Matroska keeps `xx-bogus` as it is; MP4 cannot hold it (it is
        // not three lower-case letters), so it gets `und` there — both noted.
        for (output, written) in [("/tmp/out.mkv", ["language=ger"]), ("/tmp/out.mp4", ["language=deu", "language=und"])] {
            var builder = FFmpegArgumentBuilder()
            builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
            builder.outputURL = URL(fileURLWithPath: output)
            builder.sourceStreams = sources
            builder.mapAllStreams = true
            builder.videoPassthrough = true
            builder.audioPassthrough = true
            let args = builder.build()
            let languages = zip(args, args.dropFirst()).filter { $0.0.hasPrefix("-metadata:s:") && $0.1.hasPrefix("language=") }.map(\.1)
            XCTAssertEqual(languages, written, "\(output): what is written")
            XCTAssertEqual(builder.trackWritingNotes().count, 2, "\(output): yue and xx-bogus are reported")
        }
    }
}
