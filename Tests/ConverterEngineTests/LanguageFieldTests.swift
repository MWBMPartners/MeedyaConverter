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
//   * valid languages with no ISO 639-2 code (`yue`, `cmn`, `nan`);
//   * values it could not recognise (`english`, `xx-bogus`).
// Both are now left for ffmpeg to copy, with a note in the job's log — but
// ONLY where the output's writer really stores the text as it is. The second
// independent review found MP4 cutting `romanian` to `rom` (Romany), MPEG-TS
// dropping it, and MOV dropping German, Chinese and Greek, all while the note
// said "kept as the source had it". One table now says what each file type
// stores (`TrackLanguage.LanguageFieldStorage`); ContainerLanguageToolTests
// checks it against the real ffmpeg, and TrackPreservationToolTests checks
// whole conversions.
//
// The third independent review found "no language is stored" (MOV) was not
// true either: giving ffmpeg NO value made it COPY the source's own value in
// (`chi` for mkvmerge's Cantonese, `eng` under an edit to `sv`). A write now
// has three outcomes — copy the source's value, write a value, or CLEAR the
// field (`TrackLanguage.LanguageWrite.Action`) — and these tests say which.
//
// The fourth independent review found "leave it for ffmpeg to copy" used
// where ffmpeg copies NOTHING: a Matroska track whose full tag is Abaza
// `abq` while its old field says only `und` (which ffprobe hides). The
// probe now records that as an empty text, and the tag is written instead.
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
        fromQuickTimeNumber: Bool = false,
        ignored: IgnoredFullLanguageTag? = nil,
        to container: ContainerFormat?,
        replacement: Bool = false,
        keepSource: Bool = true
    ) -> TrackLanguage.LanguageWrite {
        TrackLanguage.languageWrite(
            streamNumber: 2, edited: edited, sourceLanguage: source, sourceUnrecognised: unrecognised,
            sourceStoredText: stored, sourceReadFromQuickTimeNumber: fromQuickTimeNumber, ignoredFullTag: ignored,
            container: container, isReplacement: replacement, keepsSourceMetadata: keepSource
        )
    }

    // MARK: - Not edited: keep what the source had

    /// No three-letter code: nothing written, so ffmpeg copies `yue`.
    func test_languageWithNoThreeLetterCodeIsKept() {
        for tag in ["yue", "cmn", "nan"] {
            for container: ContainerFormat in [.mkv, .mp4] {
                let result = write(tag, to: container)
                XCTAssertEqual(result.action, .copySource, "\(tag) in \(container)")
                XCTAssertEqual(result.note, "Stream #2: language “\(tag)” has no code on the older three-letter list (ISO 639-2); kept as the source had it.")
            }
        }
    }

    /// A real correction loses nothing and is still made.
    func test_realCodesAreStillWrittenInTheContainersForm() {
        XCTAssertEqual(write("de", to: .mkv), .init(action: .write("ger"), note: nil))
        XCTAssertEqual(write("de", to: .mp4), .init(action: .write("deu"), note: nil))
        XCTAssertEqual(write("und", to: .mkv), .init(action: .write("und"), note: nil), "the source said \"not known\"")
        XCTAssertEqual(write(nil, to: .mkv), .init(action: .copySource, note: nil), "the source said nothing")
    }

    /// What each outcome puts after `language=` in ffmpeg's arguments.
    func test_eachOutcomesArgument() {
        XCTAssertNil(TrackLanguage.LanguageWrite(action: .copySource, note: nil).argumentValue)
        XCTAssertEqual(TrackLanguage.LanguageWrite(action: .write("ger"), note: nil).argumentValue, "ger")
        XCTAssertEqual(TrackLanguage.LanguageWrite(action: .clear, note: nil).argumentValue, "")
    }

    /// An unrecognised value is left for ffmpeg to copy, with a note — in
    /// the file types that store any text (Matroska, Ogg).
    func test_unrecognisedValueIsKeptWhereTheFieldHoldsAnyText() {
        for container: ContainerFormat in [.mkv, .webm, .ogg] {
            let result = write("und", unrecognised: "english", to: container)
            XCTAssertEqual(result.action, .copySource)
            XCTAssertTrue(result.note?.hasPrefix("Stream #2: the file's language “english” is not a language code; kept") == true)
        }
    }

    /// MP4 keeps only the first three letters, so an unrecognised value
    /// would be CUT — `romanian` to `rom`, which is Romany. The round-2 build
    /// left it to ffmpeg and said "kept as the source had it" (this test
    /// asserted that). Now `und`, and a note saying exactly what would have
    /// happened. MPEG-TS stores only three-letter codes, so it gets `und` too;
    /// MOV cannot even store `und`, so its field is CLEARED there (given
    /// nothing, ffmpeg would copy the source's text in).
    func test_unrecognisedValueIsNotLeftToBeCutOrDropped() {
        XCTAssertEqual(write("und", unrecognised: "romanian", to: .mp4), .init(
            action: .write("und"),
            note: "Stream #2: the file's language “romanian” is not a language code, and this file type would keep only "
                + "its first three letters, “rom”, which is itself a language code, and may not be the language meant, "
                + "so it is written as “und” (not known). Set the right language in the stream editor if you know it."
        ))
        XCTAssertEqual(write("und", unrecognised: "romanian", to: .mpegTS), .init(
            action: .write("und"),
            note: "Stream #2: the file's language “romanian” is not a language code, and this file type can only store "
                + "codes of exactly three letters, so it is written as “und” (not known). Set the right language in the "
                + "stream editor if you know it."
        ))
        let mov = write("und", unrecognised: "english", to: .mov)
        XCTAssertEqual(mov.action, .clear)
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
        XCTAssertEqual(result.action, .copySource)
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
        XCTAssertEqual(matroska.action, .copySource)
        XCTAssertEqual(
            matroska.note,
            "Stream #2: language “fr-CA” cannot be written to this file type's three-letter language field "
                + "without losing “CA”; kept as the source had it."
        )
        let mp4 = write("fr-CA", to: .mp4)
        XCTAssertEqual(mp4.action, .write("fra"))
        XCTAssertEqual(mp4.note, "Stream #2: this file type can only store the language, so “CA” in “fr-CA” is not saved (written as “fra”).")
    }

    /// Free-text fields (Ogg) take the whole canonical tag: nothing lost.
    func test_freeTextFieldsGetTheWholeTag() {
        XCTAssertEqual(write("yue", to: .ogg), .init(action: .write("yue"), note: nil))
        XCTAssertEqual(write("zh-Hant-TW", to: .ogg), .init(action: .write("zh-Hant-TW"), note: nil))
    }

    /// Ogg keeps `xx-bogus` whole, but it is still not a registered
    /// language, and the note says so — as it does for Matroska. The third
    /// independent review found Ogg wrote it with no note at all.
    func test_anUnregisteredLanguageIsReportedInOggToo() {
        XCTAssertEqual(write("xx-bogus", to: .ogg), .init(
            action: .write("xx-bogus"),
            note: "Stream #2: the file's language “xx-bogus” is not a registered language code; kept as the source had "
                + "it. Set the right language in the stream editor if you know it."
        ))
        XCTAssertEqual(write("xx-bogus", stored: "XX-Bogus", to: .ogm).note,
                       "Stream #2: the file's language “xx-bogus” is not a registered language code; written as "
                           + "“xx-bogus”. Set the right language in the stream editor if you know it.")
    }

    /// A replacement stream comes from a separate file with no tags, so
    /// "leave it for ffmpeg to copy" would lose it: the value is written.
    /// Where the output stores no language, a replacement's field is cleared
    /// too (its own file could carry a value).
    func test_replacementStreamsGetTheSourcesValueWritten() {
        XCTAssertEqual(write("yue", to: .mkv, replacement: true).action, .write("yue"))
        XCTAssertEqual(write("und", unrecognised: "english", to: .mkv, replacement: true).action, .write("english"))
        XCTAssertEqual(write("sv", to: .mov, replacement: true).action, .clear)
    }

    /// With the source's metadata dropped, nothing of the source's is written
    /// — and nothing is copied either, so there is nothing to clear.
    func test_droppedSourceMetadataWritesNothing() {
        XCTAssertEqual(write("yue", to: .mkv, keepSource: false), .init(action: .copySource, note: nil))
        XCTAssertEqual(write("yue", stored: "chi", to: .mov, keepSource: false), .init(action: .copySource, note: nil))
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
    /// list cannot be kept, and the note says so.
    func test_movGetsTheQuickTimeListsCode() {
        XCTAssertEqual(write("de", to: .mov), .init(action: .write("ger"), note: nil))
        XCTAssertEqual(write("fr", to: .mov), .init(action: .write("fra"), note: nil))
        XCTAssertEqual(write("el", to: .mov), .init(action: .write("gre"), note: nil))
        XCTAssertEqual(write("ja", to: .mov), .init(action: .write("jpn"), note: nil))
        XCTAssertEqual(write("hr", to: .mov), .init(action: .write("hr "), note: nil), "the list's own label, space and all")
        // MOV cannot store `und`: the field is cleared, which stores no
        // language — "not known" either way, so nothing is lost or noted.
        XCTAssertEqual(write("und", to: .mov), .init(action: .clear, note: nil))
        XCTAssertEqual(write("yue", to: .mov), .init(
            action: .clear,
            note: "Stream #2: this file type (QuickTime) can only store the languages on its old list, and “yue” is not "
                + "on it, so no language is stored."
        ))
        XCTAssertEqual(write("sr-Latn", to: .mov), .init(
            action: .write("sr "),
            note: "Stream #2: this file type (QuickTime) can only store the languages on its old list, so “Latn” in "
                + "“sr-Latn” is not saved (written as “sr ”)."
        ))
        XCTAssertEqual(TrackLanguage.languageFieldForm(for: .mov), .quickTimeList)
    }

    /// The QuickTime list as Apple's players read it (the third independent
    /// review): `chi` is Traditional Chinese, `aze` Azerbaijani in Cyrillic,
    /// `mon` Mongolian in Mongolian script — so each is written only for that
    /// tag, and plain `zh`, `zh-Hans`, `az`, `mn` store no language, saying
    /// why. Round 3 wrote `chi` for any Chinese, so `zh-Hans` became
    /// Traditional Chinese to Apple's players. `sve` and `iri`, which Apple
    /// reads as Swedish and Irish, are the registered codes of other
    /// languages — Serili and Rigwe — as every other program reads them, so
    /// they are never written for Swedish or Irish from elsewhere (the fourth
    /// independent review corrected "not language codes" to that).
    func test_movCodesAreWhatApplesPlayersRead() {
        XCTAssertEqual(write("zh-Hant", to: .mov), .init(action: .write("chi"), note: nil), "what chi means")
        XCTAssertEqual(write("az-Cyrl", to: .mov), .init(action: .write("aze"), note: nil))
        XCTAssertEqual(write("mn-Mong", to: .mov), .init(action: .write("mon"), note: nil))
        XCTAssertEqual(write("zh-Hant-TW", to: .mov), .init(
            action: .write("chi"),
            note: "Stream #2: this file type (QuickTime) can only store the languages on its old list, so “TW” in "
                + "“zh-Hant-TW” is not saved (written as “chi”)."
        ))
        func chinese(_ tag: String, _ differs: String) -> String {
            "Stream #2: this file type (QuickTime) can only store the languages on its old list; that list has Chinese "
                + "only as “chi”, which Apple's players read as Chinese in Traditional script (“zh-Hant”), and “\(tag)” "
                + "\(differs), so no language is stored."
        }
        XCTAssertEqual(write("zh", to: .mov), .init(action: .clear, note: chinese("zh", "does not say that")))
        XCTAssertEqual(write("zh-Hans", to: .mov), .init(action: .clear, note: chinese("zh-Hans", "is not that")))
        XCTAssertEqual(write("zh-TW", to: .mov), .init(action: .clear, note: chinese("zh-TW", "does not say that")))
        XCTAssertEqual(write("az", to: .mov).action, .clear)
        XCTAssertTrue(write("az", to: .mov).note?.contains("Azerbaijani in Cyrillic script (“az-Cyrl”), and “az” does not say that") == true)
        XCTAssertEqual(write("az-Latn", to: .mov).action, .clear)
        XCTAssertEqual(write("mn", to: .mov).action, .clear)
        XCTAssertTrue(write("mn-Cyrl", to: .mov).note?.contains("Mongolian in Mongolian script (“mn-Mong”), and “mn-Cyrl” is not that") == true)
        // An MP4 source's packed `chi` — plain Chinese — is not copied into a
        // MOV output either: there it would be number 19, Traditional Chinese
        // to Apple's players, which the track does not say. (A MOV source's
        // own `chi` is read by its NUMBER — see QuickTimeTrackListTests — so
        // it arrives here as `zh-Hant`, and `chi` is written.)
        XCTAssertEqual(write("zh", stored: "chi", to: .mov).action, .clear)
        XCTAssertEqual(write("zh-Hant", stored: "chi", to: .mov), .init(action: .write("chi"), note: nil))

        XCTAssertEqual(write("sv", to: .mov), .init(
            action: .clear,
            note: "Stream #2: this file type (QuickTime) can only store the languages on its old list; that list has "
                + "Swedish only as “sve”, which Apple's players read as Swedish but other programs read as Serili, "
                + "the language that code is registered for, so no language is stored."
        ))
        XCTAssertTrue(write("ga", to: .mov).note?.contains(
            "Irish only as “iri”, which Apple's players read as Irish but other programs read as Rigwe"
        ) == true)
        // Serili — a Matroska `sve` track: `sve` IS on the list, but as Apple's
        // code for Swedish, so it cannot be kept, and the note says that (the
        // fourth independent review: it said "“sve” is not on it").
        XCTAssertEqual(write("sve", stored: "sve", to: .mov), .init(
            action: .clear,
            note: "Stream #2: this file type (QuickTime) can only store the languages on its old list; “sve” is on that "
                + "list, but Apple's players read it as Swedish, not as Serili, so no language is stored."
        ))
        XCTAssertEqual(write("fr", edited: "iri", to: .mov).note,
                       "Stream #2: this file type (QuickTime) can only store the languages on its old list; “iri”, set "
                           + "in the stream editor, is on that list, but Apple's players read it as Irish, not as Rigwe, "
                           + "so no language is stored.")
        // A MOV source's own Swedish (`sve`, number 5, read as `sv`) is kept
        // on a MOV-to-MOV remux — the output says what the source said — and
        // the note says how others read it.
        XCTAssertEqual(write("sv", stored: "sve", fromQuickTimeNumber: true, to: .mov), .init(
            action: .copySource,
            note: "Stream #2: the source's own QuickTime code “sve” is kept as it was. Apple's players read it as "
                + "Swedish, but other programs read it as Serili, the language that code is registered for."
        ))
        // …but only a MOV's own number: a Matroska track whose old field says
        // `sve` and whose full tag says `sv` is Swedish from elsewhere, so it
        // gets no language and the reason (the stand-in review of round 5:
        // it was kept as `sve`, "the source's own QuickTime code").
        XCTAssertEqual(write("sv", stored: "sve", to: .mov), .init(
            action: .clear,
            note: "Stream #2: this file type (QuickTime) can only store the languages on its old list; that list has "
                + "Swedish only as “sve”, which Apple's players read as Swedish but other programs read as Serili, "
                + "the language that code is registered for, so no language is stored."
        ))
        // …but never copied where it would say Serili: MP4 and Matroska get
        // Swedish's own code.
        XCTAssertEqual(write("sv", stored: "sve", to: .mp4), .init(action: .write("swe"), note: nil))
        XCTAssertEqual(write("ga", stored: "iri", to: .mkv), .init(action: .write("gle"), note: nil))
        // Text the source did not give as a language never becomes one: an
        // unrecognised value is not copied into MOV, where Apple's players
        // read every entry as a language.
        // (Round 5 tested an unrecognised `sve` here — an impossible input,
        // `sve` being a registered code. A reachable one: an MP4's old
        // QuickTime number 5, which Apple reads there as "``e" while ffmpeg
        // would copy `sve` — Swedish to Apple in a MOV. It is cleared.)
        XCTAssertEqual(write("und", unrecognised: "``e", stored: "sve", to: .mov), .init(
            action: .clear,
            note: "Stream #2: the file's language “``e” is not a language code, and this file type (QuickTime) can "
                + "only store the languages on its old list, so no language is stored. Set the right language in the "
                + "stream editor if you know it."
        ))

        // The table itself: never `sve` or `iri`; the three with their script.
        let written = Set(TrackLanguage.quickTimeCodesByTag.values)
        XCTAssertFalse(written.contains("sve"))
        XCTAssertFalse(written.contains("iri"))
        XCTAssertEqual(TrackLanguage.quickTimeCodesByTag["zh-Hant"], "chi")
        XCTAssertNil(TrackLanguage.quickTimeCodesByTag["zh"])
        XCTAssertNil(TrackLanguage.quickTimeCodesByTag["az"])
        XCTAssertNil(TrackLanguage.quickTimeCodesByTag["mn"])
        XCTAssertEqual(TrackLanguage.quickTimeCodesByTag["ro"], "ron", "first in list order, as in ffmpeg")

        // Edits and the editor's warning say the same.
        XCTAssertEqual(write("fr", edited: "zh", to: .mov), .init(
            action: .clear,
            note: "Stream #2: this file type (QuickTime) can only store the languages on its old list; that list has "
                + "Chinese only as “chi”, which Apple's players read as Chinese in Traditional script (“zh-Hant”), and "
                + "“zh”, set in the stream editor, does not say that, so no language is stored."
        ))
        XCTAssertEqual(
            StreamMetadataEditor.storageNote(for: "zh", in: .mov),
            "This file type (QuickTime) can only store the languages on its old list; that list has Chinese only as "
                + "“chi”, which Apple's players read as Chinese in Traditional script (“zh-Hant”), and “zh” does not say "
                + "that, so the track will have no language."
        )
        XCTAssertEqual(StreamMetadataEditor.storageNote(for: "zh-Hant-TW", in: .mov),
                       "This file type (QuickTime) can only store the languages on its old list, so “TW” will not be saved.")
        XCTAssertNil(StreamMetadataEditor.storageNote(for: "zh-Hant", in: .mov))
    }

    /// "No language is stored" must be TRUE (third independent review, its
    /// must-fix): giving ffmpeg nothing made it copy the source's own value,
    /// and MOV keeps whatever is on its QuickTime list. mkvmerge writes `chi`
    /// in the old field for Cantonese, Mandarin and Min Nan, and `ara` for
    /// Levantine Arabic — all on the list, so all came out as that. Now the
    /// field is CLEARED, and the note is true.
    func test_movStoresNoLanguageByClearingTheField() {
        for (tag, oldField) in [("yue", "chi"), ("cmn", "chi"), ("nan", "chi"), ("apc", "ara")] {
            let result = write(tag, stored: oldField, to: .mov)
            XCTAssertEqual(result.action, .clear, tag)
            XCTAssertEqual(
                result.note,
                "Stream #2: this file type (QuickTime) can only store the languages on its old list, and “\(tag)” is "
                    + "not on it, so no language is stored.",
                tag
            )
        }
        // Edits: an edit to `sv` (not storable) or to `english` (not a tag)
        // used to leave the source's `eng` in the file.
        XCTAssertEqual(write("en", stored: "eng", edited: "sv", to: .mov).action, .clear)
        XCTAssertEqual(write("en", stored: "eng", edited: "english", to: .mov), .init(
            action: .clear,
            note: "Stream #2: “english”, set in the stream editor, is not a language tag, so no language is stored."
        ))
        // An edit to `und`: MOV cannot store it, so the output has no
        // language — which is what "not known" means. No note.
        XCTAssertEqual(write("en", stored: "eng", edited: "und", to: .mov), .init(action: .clear, note: nil))
        // With nothing in the source, there is nothing to clear.
        XCTAssertEqual(write(nil, edited: "sv", to: .mov).action, .copySource)
    }

    /// MPEG-TS keeps codes of exactly three letters, so `yue` is kept as it
    /// is; a region is cut with a note.
    func test_transportStreamKeepsThreeLetterCodes() {
        XCTAssertEqual(write("yue", to: .mpegTS).action, .copySource)
        XCTAssertEqual(write("yue", to: .mpegTS).note, "Stream #2: language “yue” has no code on the older three-letter list (ISO 639-2); kept as the source had it.")
        XCTAssertEqual(write("de", to: .mpegTS), .init(action: .write("deu"), note: nil))
        XCTAssertEqual(write("fr-CA", stored: "fr-CA", to: .mpegTS).action, .write("fra"))
    }

    /// A file type with no place for a track's language says so — the
    /// round-2 build wrote a code there, which vanished without a word. The
    /// field is cleared too, so "not kept" stays true even if a later
    /// ffmpeg began to store something there.
    func test_fileTypesWithNoLanguageFieldSaySo() {
        XCTAssertEqual(write("en", to: .avi), .init(
            action: .clear, note: "Stream #2: this file type has no place for a track's language, so “en” is not kept."
        ))
        XCTAssertEqual(write("und", to: .avi), .init(action: .clear, note: nil), "“not known” loses nothing")
        XCTAssertEqual(write(nil, to: .avi), .init(action: .copySource, note: nil))
    }

    /// When the source's own field says LESS than its language — mkvmerge
    /// writes `chi` in the old field for Cantonese `yue` — copying it would
    /// turn Cantonese into Chinese. The language's own tag is written
    /// instead, where the file type keeps it as it is (Matroska, MP4), with
    /// a note; MOV cannot keep it and says so — and CLEARS its field, which
    /// would otherwise get `chi` copied in (the third review's must-fix).
    func test_aSourceFieldThatSaysLessIsNotCopied() {
        XCTAssertEqual(write("yue", stored: "chi", to: .mkv), .init(
            action: .write("yue"),
            note: "Stream #2: language “yue” has no code on the older three-letter list (ISO 639-2), so “yue” is written into the field as it is, "
                + "because copying the source's own field (“chi”) would not keep it."
        ))
        XCTAssertEqual(write("yue", stored: "chi", to: .mp4).action, .write("yue"))
        XCTAssertEqual(write("yue", stored: "chi", to: .mov).action, .clear)
        XCTAssertEqual(write("fr-CA", stored: "fre", to: .mkv).action, .write("fr-CA"))
        XCTAssertEqual(write("fr-CA", stored: "fre", to: .mp4).action, .write("fra"))
        // The source's own text is copied when it says the same.
        XCTAssertEqual(write("fr-CA", stored: "fre-ca", to: .mkv).action, .copySource)
    }

    /// When the source's old field holds NOTHING ffmpeg copies — mkvmerge
    /// writes `und` there for Abaza `abq`, Western Panjabi `pnb` and tags
    /// such as `und-Latn`, and ffprobe hides `und`, so the probe records an
    /// EMPTY text — leaving the field "for ffmpeg to copy" keeps nothing.
    /// The fourth independent review found `abq` and `pnb` gone from
    /// Matroska, MP4 and MPEG-TS outputs under "kept as the source had it".
    /// The tag is written as text wherever the file type keeps it; MOV still
    /// cannot, and clears; Ogg still writes the whole tag.
    func test_aSourceFieldThatHoldsNothingIsNotLeftToBeCopied() {
        let because = "because copying the source's old field (which ffmpeg reads as holding no language) would not keep it."
        for tag in ["abq", "pnb"] {
            for container: ContainerFormat in [.mkv, .mp4, .mpegTS] {
                XCTAssertEqual(write(tag, stored: "", to: container), .init(
                    action: .write(tag),
                    note: "Stream #2: language “\(tag)” has no code on the older three-letter list (ISO 639-2), so “\(tag)” is written into the field "
                        + "as it is, " + because
                ), "\(tag) in \(container)")
            }
            XCTAssertEqual(write(tag, stored: "", to: .mov).action, .clear, "\(tag) in MOV: none, as before")
            XCTAssertEqual(write(tag, stored: "", to: .ogg).action, .write(tag), "\(tag) in Ogg: the whole tag, as before")
        }
        for (tag, lost) in [("und-Latn", "Latn"), ("und-419", "419"), ("und-x-foo", "x-foo")] {
            // Matroska keeps any text: the whole tag, as text.
            XCTAssertEqual(write(tag, stored: "", to: .mkv), .init(
                action: .write(tag),
                note: "Stream #2: language “\(tag)” cannot be written to this file type's three-letter language field "
                    + "without losing “\(lost)”, so “\(tag)” is written into the field as it is, " + because
            ))
            // MP4 and MPEG-TS hold three letters: `und`, saying what is lost.
            for container: ContainerFormat in [.mp4, .mpegTS] {
                XCTAssertEqual(write(tag, stored: "", to: container), .init(
                    action: .write("und"),
                    note: "Stream #2: this file type can only store the language, so “\(lost)” in “\(tag)” is not saved "
                        + "(written as “und”)."
                ), "\(tag) in \(container)")
            }
            XCTAssertEqual(write(tag, stored: "", to: .mov).action, .clear)
            XCTAssertEqual(write(tag, stored: "", to: .ogg).action, .write(tag))
        }
        // (A full tag that is not a language tag is never used — the probe
        // ignores it and keeps the old field's reading; see
        // `test_aDamagedFullTagIsIgnoredAndSaidSo`. Round 5 pinned writing
        // such a tag's text here, which the stand-in review of round 5 found
        // replaced a valid `eng`.)
        // "Not known" itself needs nothing written but `und`.
        XCTAssertEqual(write("und", stored: "", to: .mkv), .init(action: .write("und"), note: nil))
    }

    /// A full language tag that is not a language tag (`en_GB!x?a12`) is
    /// IGNORED by the probe, so the old field's language is written as it
    /// would be with no full tag, and the note says the full tag was ignored
    /// and is not kept — never that the damaged text was "kept as the source
    /// had it" (the stand-in review of round 5: a damaged tag replaced a
    /// valid `eng`). Said after whatever else is said, or on its own; not
    /// for an edited language, nor when the source's metadata is dropped.
    func test_aDamagedFullTagIsIgnoredAndSaidSo() {
        let damaged = IgnoredFullLanguageTag.notATag("en_GB!x?a12")
        let ignoredFromEng = "The source also records a full language tag for this track, “en_GB!x?a12”, which is "
            + "not a valid language tag, so it is ignored and not kept; the language is taken from the track's old "
            + "language field (“eng”)."
        for (container, code) in [(ContainerFormat.mkv, "eng"), (.mp4, "eng"), (.mov, "eng"), (.mpegTS, "eng")] {
            XCTAssertEqual(write("en", stored: "eng", ignored: damaged, to: container),
                           .init(action: .write(code), note: "Stream #2: " + ignoredFromEng), "\(container)")
        }
        // After another note for the same track.
        XCTAssertEqual(write("en-GB", stored: "eng", ignored: damaged, to: .mp4).note,
                       "Stream #2: this file type can only store the language, so “GB” in “en-GB” is not saved "
                           + "(written as “eng”). " + ignoredFromEng)
        // An old field that holds no language: nothing is written (as with no
        // full tag at all), and the note says so.
        XCTAssertEqual(write(nil, ignored: damaged, to: .mkv), .init(
            action: .copySource,
            note: "Stream #2: The source also records a full language tag for this track, “en_GB!x?a12”, which is "
                + "not a valid language tag, so it is ignored and not kept; the track's old language field gives no "
                + "language."
        ))
        // Longer than the reader reads: refused, never cut, and said so.
        XCTAssertEqual(write("en", stored: "eng", ignored: .tooLong(maximumBytes: 256), to: .mkv), .init(
            action: .write("eng"),
            note: "Stream #2: The source also records a full language tag for this track that is longer than 256 "
                + "bytes, more than this converter reads, so it is ignored and not kept; the language is taken from "
                + "the track's old language field (“eng”)."
        ))
        XCTAssertNil(write("en", stored: "eng", edited: "de", ignored: damaged, to: .mkv).note, "the person set it")
        XCTAssertNil(write("en", stored: "eng", ignored: damaged, to: .mkv, keepSource: false).note)
    }

    /// An MP4 holding an old QuickTime number (2) is read as Apple's players
    /// read it there — "``b", no language — while ffprobe, and so ffmpeg's
    /// copy, says `ger`. The unrecognised text is WRITTEN, never left for
    /// ffmpeg to copy: copying would make the track German in the output
    /// under a note saying "kept as the source had it". Into MP4, "``b"
    /// packs back to the same number 2; MOV stores no language. A number
    /// Apple reads as `und` (0, which ffprobe calls `eng`) is written as
    /// `und`, and MOV clears it rather than copy `eng` in.
    func test_anMP4NumberIsNeverCopiedAsFFmpegsLabel() {
        let kept = "Stream #2: the file's language “``b” is not a language code; kept as the source had it. "
            + "Set the right language in the stream editor if you know it."
        XCTAssertEqual(write("und", unrecognised: "``b", stored: "ger", to: .mp4), .init(action: .write("``b"), note: kept))
        XCTAssertEqual(write("und", unrecognised: "``b", stored: "ger", to: .mkv), .init(action: .write("``b"), note: kept))
        XCTAssertEqual(write("und", unrecognised: "``b", stored: "ger", to: .mov), .init(
            action: .clear,
            note: "Stream #2: the file's language “``b” is not a language code, and this file type (QuickTime) can only "
                + "store the languages on its old list, so no language is stored. Set the right language in the "
                + "stream editor if you know it."
        ))
        XCTAssertEqual(write("und", stored: "eng", to: .mp4), .init(action: .write("und"), note: nil))
        XCTAssertEqual(write("und", stored: "eng", to: .mov), .init(action: .clear, note: nil))
        // ffprobe's own text, when that IS the unrecognised value, is left
        // for ffmpeg to copy, as before.
        XCTAssertEqual(write("und", unrecognised: "english", stored: "english", to: .mkv).action, .copySource)
    }

    /// With no file type known nothing can be promised: the code is written
    /// as before, and anything else becomes `und`, saying why.
    func test_anUnknownFileTypeWritesCodesOrUnd() {
        XCTAssertEqual(write("de", to: nil), .init(action: .write("deu"), note: nil))
        XCTAssertEqual(write("yue", to: nil).action, .write("und"))
        XCTAssertTrue(write("yue", to: nil).note?.contains("the output's file type is not known") == true)
    }

    // MARK: - Edited: the person's tag, in the field's form

    func test_editedTagsAreWrittenWithANoteWhenSomethingCannotBeStored() {
        XCTAssertEqual(write("fr", edited: "en-GB", to: .mkv), .init(
            action: .write("eng"),
            note: "Stream #2: this file type can only store the language, so “GB” in “en-GB” is not saved (written as “eng”)."
        ))
        XCTAssertEqual(write("fr", edited: "en-GB", to: .ogg), .init(action: .write("en-GB"), note: nil))
        XCTAssertEqual(write("fr", edited: "yue", to: .mp4), .init(
            action: .write("und"),
            note: "Stream #2: this file type can only store language codes from the older three-letter list "
                + "(ISO 639-2), and “yue” is not on it, so the language is written as “und” (not known)."
        ))
        XCTAssertEqual(write("fr", edited: "de", to: .mkv), .init(action: .write("ger"), note: nil))
        // `und-GB`: it is the REGION that cannot be stored (the round-2
        // build said "und-GB has no three-letter code").
        XCTAssertEqual(write("fr", edited: "und-GB", to: .mkv), .init(
            action: .write("und"),
            note: "Stream #2: this file type can only store the language, so “GB” in “und-GB” is not saved (written as “und”)."
        ))
        XCTAssertEqual(StreamMetadataEditor.storageNote(for: "und-GB", in: .mkv),
                       "This file type can only store the language, so “GB” will not be saved.")
        // MOV and the file types with no language field: the source's `fr`
        // is CLEARED, not left to be copied in.
        XCTAssertEqual(write("fr", edited: "de", to: .mov), .init(action: .write("ger"), note: nil))
        XCTAssertEqual(write("fr", edited: "sv", to: .mov).action, .clear)
        XCTAssertEqual(StreamMetadataEditor.storageNote(for: "sv", in: .mov),
                       "This file type (QuickTime) can only store the languages on its old list; that list has Swedish "
                           + "only as “sve”, which Apple's players read as Swedish but other programs read as "
                           + "Serili, the language that code is registered for, so the track will have no language.")
        XCTAssertEqual(StreamMetadataEditor.storageNote(for: "yue", in: .mov),
                       "This file type (QuickTime) can only store the languages on its old list, and “yue” is not on it, "
                           + "so the track will have no language.")
        XCTAssertEqual(write("fr", edited: "de", to: .avi), .init(
            action: .clear, note: "Stream #2: this file type has no place for a track's language, so “de”, set in the stream editor, is not saved."
        ))
        XCTAssertEqual(StreamMetadataEditor.storageNote(for: "de", in: .avi),
                       "This file type has no place for a track's language, so the track will have no language.")
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

    /// The command CLEARS what MOV cannot store (`language=`, an empty
    /// value), on the output stream each source stream became: mkvmerge's
    /// Cantonese (old field `chi`), an edit to `sv`, and an unedited
    /// `und`. German still gets the QuickTime list's `ger`.
    func test_theBuilderClearsWhatMOVCannotStore() {
        let sources = [
            MediaStream(streamIndex: 0, streamType: .video, disposition: StreamDisposition()),
            MediaStream(streamIndex: 1, streamType: .audio, language: "yue", languageAsStored: "chi",
                        disposition: StreamDisposition()),
            MediaStream(streamIndex: 2, streamType: .audio, language: "en", languageAsStored: "eng",
                        disposition: StreamDisposition()),
            MediaStream(streamIndex: 3, streamType: .audio, language: "de", languageAsStored: "ger",
                        disposition: StreamDisposition()),
            MediaStream(streamIndex: 4, streamType: .audio, language: "und", languageAsStored: "und",
                        disposition: StreamDisposition())
        ]
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/out.mov")
        builder.sourceStreams = sources
        builder.mapAllStreams = true
        builder.videoPassthrough = true
        builder.audioPassthrough = true
        builder.orderTracksCanonically = false
        var swedish = SourceStreamEdit()
        swedish.language = "sv"
        builder.sourceStreamEdits = [2: swedish]
        let args = builder.build()
        let languages = zip(args, args.dropFirst())
            .filter { $0.0.hasPrefix("-metadata:s:") && $0.1.hasPrefix("language=") }
            .map { "\($0.0) \($0.1)" }
        XCTAssertEqual(languages, [
            "-metadata:s:a:0 language=", "-metadata:s:a:1 language=", "-metadata:s:a:2 language=ger",
            "-metadata:s:a:3 language="
        ])
        XCTAssertEqual(builder.trackWritingNotes().count, 2, "yue and the sv edit are reported; und is not a loss")
    }
}
