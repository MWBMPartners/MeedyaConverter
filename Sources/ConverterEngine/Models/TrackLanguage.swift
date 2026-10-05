// ============================================================================
// MeedyaConverter — TrackLanguage
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The engine's one doorway to the shared language policy (MWBM-MEDIA-LANG,
// docs/standards/media-language-bcp47-policy.md — read it before changing
// anything about languages, tracks, roles or their order). The rules live in
// the MediaLanguagePolicy module; this file only connects them to the
// engine's own types (`MediaStream`, `StreamDisposition`):
//
//   * reading a language value found in a file (LANG-002);
//   * turning ffmpeg's dispositions into the policy's roles (TRACK-010/050).
//
// If the policy's reference data cannot be loaded (its resource bundle was
// not shipped — a packaging mistake) the engine does NOT guess: language
// values are kept exactly as the file gives them, and a warning is written
// once to standard error (and shown in the app's Activity Log). The release
// workflows fail the build before that can ship.
// ============================================================================

import Foundation
import MediaLanguagePolicy

/// Connects the engine to the language policy.
public enum TrackLanguage {

    /// The policy on its bundled data, or `nil` if the data is missing (see
    /// the file header). Loaded once; the warning (`dataProblem`) is written
    /// once, to standard ERROR.
    ///
    /// It used to be `print`ed to standard OUTPUT, where it broke anything
    /// reading that as data — `meedya-convert probe --format json` among
    /// them — and the app never showed it (found in the independent review).
    /// The app now shows `dataProblem` in its Activity Log at start.
    public static let policy: MediaLanguagePolicy? = {
        switch MediaLanguagePolicy.shared {
        case .success(let policy):
            return policy
        case .failure:
            FileHandle.standardError.write(Data("Warning: \(dataProblem ?? "")\n".utf8))
            return nil
        }
    }()

    /// What is wrong with the policy's data, in plain English, or `nil` when
    /// it loaded. For a place a person will see it (the app's Activity Log);
    /// `policy` also writes it once to standard error.
    public static let dataProblem: String? = {
        guard case .failure(let error) = MediaLanguagePolicy.shared else { return nil }
        return "\(error) Track languages are kept exactly as each file gives them, and are not checked "
            + "or put in the standard order. Reinstalling MeedyaConverter should fix this."
    }()

    /// A language value read from a file.
    public struct Reading: Sendable, Equatable {
        /// The canonical BCP 47 tag, or `und` when the value was not
        /// recognised (never a guess).
        public let language: String
        /// The value as found, when it was not recognised; else `nil`.
        public let unrecognised: String?
    }

    /// Reads a language value found in a file or reported by a tool such as
    /// ffprobe (LANG-002): old three-letter codes (`eng`, `ger`), `XXX`,
    /// null padding, Matroska's `fre-ca`, or a real tag. An unrecognised
    /// value becomes `und`, with the original kept.
    ///
    /// Without the policy's data the value is returned unchanged (see the
    /// file header) — never replaced by a guess.
    public static func read(fileValue raw: String) -> Reading {
        guard let policy else {
            return Reading(language: raw, unrecognised: nil)
        }
        switch policy.reader.reading(raw) {
        case .tag(let tag):
            return Reading(language: tag, unrecognised: nil)
        case .unrecognised(let text):
            return Reading(language: "und", unrecognised: text)
        }
    }
}

// MARK: - Roles

extension StreamDisposition {

    /// The policy's roles (TRACK-010) for a stream of `type` with these
    /// dispositions — what ordering and selection work from.
    ///
    /// ffmpeg has no flag for an "alternate main mix", so no track is ever
    /// given that role here. `default`, `original` and `dub` are not roles
    /// (they are the default and original-language markers).
    public func policyRoles(for type: StreamType) -> [TrackRole] {
        var roles: [TrackRole] = []
        switch type {
        case .audio:
            if isComment { roles.append(.commentary) }
            // ffmpeg marks audio description `visual_impaired`; MP4's `kind`
            // "description" is read back as visual_impaired + descriptions
            // (checked with ffmpeg 9.0.1), so either flag means AD on audio.
            if isVisualImpaired || isDescriptions { roles.append(.audioDescription) }
            // Music-and-effects, karaoke, lyrics, hearing-impaired audio: roles
            // the policy's audio list does not name — "anything else".
            if isCleanEffects || isKaraoke || isLyrics || isHearingImpaired { roles.append(.other) }
        case .subtitle:
            if isHearingImpaired || isCaptions { roles.append(.sdh) }
            if isForced { roles.append(.forced) }
            if isComment { roles.append(.commentary) }
            // Text descriptions of the picture, lyrics, karaoke: not in the
            // subtitle list (full, SDH, forced, commentary) — "anything else".
            if isDescriptions || isLyrics || isKaraoke || isVisualImpaired { roles.append(.other) }
        case .video, .data, .attachment, .unknown:
            break
        }
        return roles
    }
}

extension StreamType {

    /// The policy's track type for this kind of stream (TRACK-060): data,
    /// attachments and unknown streams are all "anything else".
    public var policyTrackType: TrackType {
        switch self {
        case .video: return .video
        case .audio: return .audio
        case .subtitle: return .subtitle
        case .data, .attachment, .unknown: return .other
        }
    }
}

extension MediaStream {

    /// The policy's track type for this stream (TRACK-060).
    public var policyTrackType: TrackType { streamType.policyTrackType }

    /// The stream's roles in the policy's terms (TRACK-010), from its full
    /// dispositions — or, for a stream described before those were kept,
    /// from `isForced` alone.
    public var policyRoles: [TrackRole] {
        let disposition = disposition ?? StreamDisposition(isDefault: isDefault, isForced: isForced)
        return disposition.policyRoles(for: streamType)
    }

    /// Whether the file marks this stream as being in the original language
    /// (LANG-010; ffmpeg's `original`, Matroska's FlagOriginal).
    public var isOriginalLanguage: Bool {
        disposition?.isOriginal ?? false
    }
}

// MARK: - Writing (TRACK-070, NAME-010)

extension TrackLanguage {

    /// The form the POLICY wants in a container's language field (TRACK-070)
    /// — what the converter writes when it writes a code. What the field can
    /// actually HOLD is a separate question (`LanguageFieldStorage`): the two
    /// are kept apart because they differ (MOV's field holds only ffmpeg's
    /// QuickTime list; Matroska's holds any text).
    public enum LanguageFieldForm: Sendable, Equatable {
        /// ISO 639-2 bibliographic (`ger`) — Matroska's old `Language`.
        case bibliographic
        /// ISO 639-2 terminology (`deu`) — MP4's `mdhd`; also used for the
        /// containers the policy's table does not name (MPEG-TS, DASH …).
        case terminology
        /// The entry on ffmpeg's QuickTime language list that Apple's players
        /// read as the same language (`ger`, `fra`, `jpn`, `gre`; `chi` only
        /// for `zh-Hant` — see `quickTimeCodesByTag`) — MOV, whose writer
        /// stores nothing else. Writing the terminology code there (`deu`)
        /// stored nothing.
        case quickTimeList
        /// The canonical BCP 47 tag — free-text fields (Ogg's Vorbis comment
        /// `LANGUAGE`).
        case fullTag
    }

    /// The form `container`'s language field needs (see `LanguageFieldForm`).
    public static func languageFieldForm(for container: ContainerFormat?) -> LanguageFieldForm {
        switch container {
        case .mkv, .mka, .mks, .mk3d, .webm:
            return .bibliographic
        case .mov:
            return .quickTimeList
        case .ogg, .ogm:
            return .fullTag
        default:
            return .terminology
        }
    }

    /// WHAT EACH FILE TYPE'S WRITER REALLY STORES in a track's language
    /// field, given ffmpeg's `language` value. This is the ONE table the
    /// command, the job's notes and the stream editor's warning all use, so
    /// a note can only say "kept" where the value really is kept.
    ///
    /// Checked with ffmpeg / ffprobe 9.0.1 on 28 Sept 2026 — writing values
    /// such as `ger`, `deu`, `fr-CA`, `romanian`, `yue`, `ENG`, `und` and
    /// `hr ` into each file type and reading them back — and re-checked
    /// against whatever ffmpeg the test machine has by
    /// `ContainerLanguageToolTests` (TRACK-070: "check them against the tool
    /// it actually runs, with a test, rather than rely on this table"). The
    /// second independent review found the notes said "kept as the source had
    /// it" for MP4, MOV and MPEG-TS where these writers had cut or dropped
    /// the value.
    public enum LanguageFieldStorage: Sendable, Equatable {
        /// The text exactly as given, whatever it is: Matroska and WebM
        /// (ffmpeg writes it into the OLD `Language` element, even `en-GB`
        /// or `romanian`; it never writes `LanguageBCP47`), Ogg (the
        /// `LANGUAGE` comment), and DASH's manifest (whose segments,
        /// separately, always get `und` — see issue #533).
        case anyText
        /// MP4, M4A, M4V, M4B, 3GP, 3G2 (`mdhd`): the FIRST THREE
        /// characters, when each is a lower-case letter (or one of
        /// `` ` { | } ~ `` and DEL, which pack the same way). Anything after
        /// the third is CUT — `romanian` becomes `rom` (Romany), `latvian`
        /// `lat` (Latin), `slovenian` `slo` (Slovak) — and anything else
        /// (`de`, `en-GB`, `ENG`, `e_g`) stores nothing. No `elng` box.
        case firstThreeLowerCase
        /// MOV: the language is stored as an old Macintosh language number,
        /// so only the strings on ffmpeg's QuickTime list
        /// (`quickTimeListEntries`) are stored, matched exactly. Anything
        /// else stores nothing — `deu`, `zho`, `ell`, `yue` and `und` too.
        /// (What is stored is ffprobe's reading. What Apple's players read
        /// can differ — see `quickTimeCodesByTag`.)
        case quickTimeList
        /// MPEG-TS, and HLS (whose segments are MPEG-TS): comma-separated
        /// pieces of exactly three bytes, any characters, any case (`ENG`,
        /// `hr ` and `eng,fre` are kept); other pieces are dropped, so
        /// `romanian`, `fr-CA` or `日本語` store nothing.
        case threeCharacterPieces
        /// No place for a track's language at all: MPEG-PS, AVI, FLV, MXF,
        /// AIFF, CAF, W64, RF64 and DCP (which ffmpeg writes as MXF).
        case nothing
        /// No file type known (only when the argument builder is used
        /// directly): nothing was checked, so nothing can be promised.
        case unchecked

        /// What the file will hold for `value` — what reading the output back
        /// gives — or `nil` when it holds nothing. (Matroska stores `und`
        /// too, but ffmpeg reports it as no language at all; either way it
        /// means "not known".) `nil` for `.unchecked`: nothing is promised.
        public func stored(_ value: String) -> String? {
            switch self {
            case .anyText:
                return value
            case .firstThreeLowerCase:
                let bytes = Array(value.utf8)
                // ffmpeg writes `und` for an empty value.
                if bytes.isEmpty { return "und" }
                guard bytes.count >= 3, bytes[0..<3].allSatisfy({ $0 >= 0x60 && $0 <= 0x7F }) else { return nil }
                // Three ASCII bytes, so this always succeeds.
                return String(bytes: bytes[0..<3], encoding: .utf8)
            case .quickTimeList:
                return TrackLanguage.quickTimeListEntries.contains(value) ? value : nil
            case .threeCharacterPieces:
                let pieces = value.split(separator: ",", omittingEmptySubsequences: false).filter { $0.utf8.count == 3 }
                return pieces.isEmpty ? nil : pieces.joined(separator: ",")
            case .nothing, .unchecked:
                return nil
            }
        }

        /// Whether `value` is stored exactly as it is.
        func keeps(_ value: String) -> Bool {
            stored(value) == value
        }
    }

    /// What `container`'s writer stores (see `LanguageFieldStorage`).
    public static func languageFieldStorage(for container: ContainerFormat?) -> LanguageFieldStorage {
        guard let container else { return .unchecked }
        switch container {
        case .mkv, .mka, .mks, .mk3d, .webm, .ogg, .ogm, .dash:
            return .anyText
        case .mp4, .m4v, .m4a, .m4b, .m4p, .threeGP, .threeG2:
            return .firstThreeLowerCase
        case .mov:
            return .quickTimeList
        case .mpegTS, .hls:
            return .threeCharacterPieces
        case .mpegPS, .avi, .flv, .mxf, .aiff, .caf, .w64, .rf64, .dcp:
            return .nothing
        }
    }

    // WHAT A QUICKTIME LANGUAGE NUMBER MEANS
    // --------------------------------------
    // A MOV file does not store the label (`chi`): it stores an old
    // Macintosh language NUMBER, and the label is only ffmpeg's name for it —
    // ffprobe reports the label, and ffmpeg's MOV writer turns a label back
    // into the FIRST number that has it. Apple's players read the NUMBER, and
    // for some numbers they read a script as well. Checked on 4 Oct 2026
    // with ffmpeg 9.0.1 and Apple's AVFoundation, writing EVERY number from 0
    // to 151 into one MOV and reading each back both ways (the table below;
    // the third independent review had checked the 101 labels):
    //
    //   * 19 `chi` is Traditional Chinese (`zh-Hant`) and 33 — ALSO labelled
    //     `chi` — Simplified (`zh-Hans`); 49 `aze` is Azerbaijani in Cyrillic
    //     (`az-Cyrl`) and 50, also `aze`, in Arabic script; 57 `mon` is
    //     Mongolian in Mongolian script (`mn-Mong`); 84, a second `may`,
    //     Malay in Arabic script. ffmpeg writes `chi` as 19, `aze` as 49,
    //     `mon` as 57, so each is written ONLY for that tag: `chi` for plain
    //     `zh` would say more than the track does, and for `zh-Hans` it would
    //     be a different script. Round 3 wrote `chi` for any Chinese.
    //   * 5 `sve` and 35 `iri` Apple reads as Swedish and Irish. But `sve`
    //     and `iri` are the registered codes of OTHER languages — Serili and
    //     Rigwe — and that is how any program reading ffprobe's text, or an
    //     MP4's packed letters, reads them. So they are never written for
    //     Swedish or Irish from anywhere else (`quickTimeEntriesNamingAnother
    //     Language`): the output would say Swedish to Apple and Serili to
    //     everyone else. A MOV source's OWN `sve` is kept on a MOV-to-MOV
    //     remux, where the output says exactly what the source said.
    //   * Every other number with a label reads the same in both: `ger` is
    //     German, `hr ` Croatian, `nor` Norwegian.
    //   * Numbers with no label in ffmpeg's list (34, 58, 95–127, 139–151)
    //     come out of ffprobe as no language at all, and ffmpeg cannot write
    //     them. They are not read here.
    //
    // The same table READS a MOV or MP4 source: given the number a track
    // stores (`QuickTimeTrackList`), its language is what Apple's players
    // read (`quickTimeLanguage(number:label:)`), so a MOV-to-MOV remux keeps
    // `chi`, `aze`, `mon`, `sve` and `iri`, and a MOV-to-MKV remux writes
    // what they mean (`zh-Hant`, `sv` …). Until the fourth independent review
    // a source's `chi` was read as plain Chinese whatever its number, so a
    // MOV-to-MOV remux of a Traditional-Chinese track stored no language.
    //
    // A language the list has only in one of these ways stores no language,
    // and the note says why (`quickTimeGapWords`).

    /// One number of the QuickTime language list that ffmpeg gives a label
    /// (see above): the number a file stores, ffmpeg 9.0.1's label for it
    /// (`mov_mdhd_language_map` in its `isom.c` — what ffprobe reports), and
    /// what Apple's AVFoundation reads it as: `languageCode` (ISO 639-2/T)
    /// and, where it gives one, `extendedLanguageTag` (BCP 47).
    struct QuickTimeLanguageNumber: Sendable {
        let number: UInt16
        let label: String
        let appleCode: String
        let appleTag: String?

        init(_ number: UInt16, _ label: String, _ appleCode: String, _ appleTag: String?) {
            self.number = number
            self.label = label
            self.appleCode = appleCode
            self.appleTag = appleTag
        }
    }

    /// Every number ffmpeg 9.0.1 gives a label, with Apple's reading of it —
    /// measured, not assumed (see above), and re-checked against
    /// AVFoundation by `ContainerLanguageToolTests
    /// .test_quickTimeNumbersAreWhatApplesPlayersRead`. Four labels end in a
    /// space (`hr `, `fo `, `sr `, `pa `).
    static let quickTimeNumbers: [QuickTimeLanguageNumber] = [
.init(0, "eng", "eng", nil), .init(1, "fra", "fra", nil), .init(2, "ger", "deu", nil),
        .init(3, "ita", "ita", nil), .init(4, "dut", "nld", nil), .init(5, "sve", "swe", nil),
        .init(6, "spa", "spa", nil), .init(7, "dan", "dan", nil), .init(8, "por", "por", nil),
        .init(9, "nor", "nor", nil), .init(10, "heb", "heb", nil), .init(11, "jpn", "jpn", nil),
        .init(12, "ara", "ara", nil), .init(13, "fin", "fin", nil), .init(14, "gre", "ell", nil),
        .init(15, "ice", "isl", nil), .init(16, "mlt", "mlt", nil), .init(17, "tur", "tur", nil),
        .init(18, "hr ", "hrv", nil), .init(19, "chi", "zho", "zh-Hant"), .init(20, "urd", "urd", nil),
        .init(21, "hin", "hin", nil), .init(22, "tha", "tha", nil), .init(23, "kor", "kor", nil),
        .init(24, "lit", "lit", nil), .init(25, "pol", "pol", nil), .init(26, "hun", "hun", nil),
        .init(27, "est", "est", nil), .init(28, "lav", "lav", nil), .init(29, "smi", "smi", nil),
        .init(30, "fo ", "fao", nil), .init(31, "per", "fas", nil), .init(32, "rus", "rus", nil),
        .init(33, "chi", "zho", "zh-Hans"), .init(35, "iri", "gle", nil), .init(36, "alb", "sqi", nil),
        .init(37, "ron", "ron", nil), .init(38, "ces", "ces", nil), .init(39, "slk", "slk", nil),
        .init(40, "slv", "slv", nil), .init(41, "yid", "yid", nil), .init(42, "sr ", "srp", nil),
        .init(43, "mac", "mkd", nil), .init(44, "bul", "bul", nil), .init(45, "ukr", "ukr", nil),
        .init(46, "bel", "bel", nil), .init(47, "uzb", "uzb", nil), .init(48, "kaz", "kaz", nil),
        .init(49, "aze", "aze", "az-Cyrl"), .init(50, "aze", "aze", "az-Arab"), .init(51, "arm", "hye", nil),
        .init(52, "geo", "kat", nil), .init(53, "mol", "mol", nil), .init(54, "kir", "kir", nil),
        .init(55, "tgk", "tgk", nil), .init(56, "tuk", "tuk", nil), .init(57, "mon", "mon", "mn-Mong"),
        .init(59, "pus", "pus", nil), .init(60, "kur", "kur", nil), .init(61, "kas", "kas", nil),
        .init(62, "snd", "snd", nil), .init(63, "tib", "bod", nil), .init(64, "nep", "nep", nil),
        .init(65, "san", "san", nil), .init(66, "mar", "mar", nil), .init(67, "ben", "ben", nil),
        .init(68, "asm", "asm", nil), .init(69, "guj", "guj", nil), .init(70, "pa ", "pan", nil),
        .init(71, "ori", "ori", nil), .init(72, "mal", "mal", nil), .init(73, "kan", "kan", nil),
        .init(74, "tam", "tam", nil), .init(75, "tel", "tel", nil), .init(76, "sin", "sin", nil),
        .init(77, "bur", "mya", nil), .init(78, "khm", "khm", nil), .init(79, "lao", "lao", nil),
        .init(80, "vie", "vie", nil), .init(81, "ind", "ind", nil), .init(82, "tgl", "tgl", nil),
        .init(83, "may", "msa", nil), .init(84, "may", "msa", "ms-Arab"), .init(85, "amh", "amh", nil),
        .init(86, "tir", "tir", nil), .init(87, "orm", "orm", nil), .init(88, "som", "som", nil),
        .init(89, "swa", "swa", nil), .init(90, "kin", "kin", nil), .init(91, "run", "run", nil),
        .init(92, "nya", "nya", nil), .init(93, "mlg", "mlg", nil), .init(94, "epo", "epo", nil),
        .init(128, "wel", "cym", nil), .init(129, "baq", "eus", nil), .init(130, "cat", "cat", nil),
        .init(131, "lat", "lat", nil), .init(132, "que", "que", nil), .init(133, "grn", "grn", nil),
        .init(134, "aym", "aym", nil), .init(135, "tat", "tat", nil), .init(136, "uig", "uig", nil),
        .init(137, "dzo", "dzo", nil), .init(138, "jav", "jav", nil)
    ]

    /// The strings ffmpeg's MOV writer accepts as a language, in the order of
    /// its QuickTime list: each label once, in number order (`chi` is 19,
    /// not 33). Several are not ISO 639-2 codes of the language they stand
    /// for (`sve`, `iri`, `chi`'s Traditional script), and four end in a
    /// space.
    static let quickTimeListEntries: [String] = {
        var labels: [String] = []
        for entry in quickTimeNumbers where !labels.contains(entry.label) { labels.append(entry.label) }
        return labels
    }()

    /// A QuickTime-list entry Apple's players read WITH a script, as ffmpeg
    /// writes it (the first number with the label): the words for notes.
    struct QuickTimeScriptEntry: Sendable {
        /// ffmpeg's label (`chi`).
        let entry: String
        /// The language's English name, for notes (`Chinese`).
        let languageName: String
        /// The whole meaning in words, for notes.
        let meaning: String
        /// What Apple's players read it as (`zh-Hant`), from the table.
        var tag: String { TrackLanguage.quickTimeMeaning(ofEntry: entry) ?? "" }
    }

    /// The three entries Apple's players read with a script (see above).
    static let quickTimeEntriesReadWithAScript: [QuickTimeScriptEntry] = [
        QuickTimeScriptEntry(entry: "chi", languageName: "Chinese", meaning: "Chinese in Traditional script"),
        QuickTimeScriptEntry(entry: "aze", languageName: "Azerbaijani", meaning: "Azerbaijani in Cyrillic script"),
        QuickTimeScriptEntry(entry: "mon", languageName: "Mongolian", meaning: "Mongolian in Mongolian script")
    ]

    /// A QuickTime-list entry whose label is the registered code of ANOTHER
    /// language (see above).
    struct QuickTimeEntryNamingAnotherLanguage: Sendable {
        /// ffmpeg's label (`sve`).
        let entry: String
        /// The language Apple's players read it as (`sv`).
        let language: String
        /// That language's English name, for notes (`Swedish`).
        let languageName: String
        /// The English name of the language the label is the registered
        /// code for (`Serili`) — how other programs read it.
        let registeredName: String
    }

    /// The two entries never written for a language from elsewhere (see
    /// above).
    static let quickTimeEntriesNamingAnotherLanguage: [QuickTimeEntryNamingAnotherLanguage] = [
        QuickTimeEntryNamingAnotherLanguage(entry: "sve", language: "sv", languageName: "Swedish", registeredName: "Serili"),
        QuickTimeEntryNamingAnotherLanguage(entry: "iri", language: "ga", languageName: "Irish", registeredName: "Rigwe")
    ]

    /// What Apple's players read `entry` as, as a canonical tag — its
    /// extended tag where AVFoundation gives one (`zh-Hant`), else the
    /// policy's reading of its `languageCode` (`swe` → `sv`) — or `nil` when
    /// that is not a language (`und`), or without the policy's data.
    static func appleMeaning(of entry: QuickTimeLanguageNumber) -> String? {
        guard let policy else { return nil }
        if let tag = entry.appleTag { return policy.canonicaliser.canonicalise(tag).canonical }
        let reading = read(fileValue: entry.appleCode)
        guard reading.unrecognised == nil, reading.language != "und" else { return nil }
        return reading.language
    }

    /// The language a MOV or MP4 track with QuickTime language NUMBER
    /// `number` has, as Apple's players read it (`zh-Hant` for 19, `zh-Hans`
    /// for 33, `sv` for 5) — or `nil` when the number has no label, `label`
    /// (ffprobe's text for the track) is not ffmpeg's label for that number
    /// (then the track and the number were not matched with certainty, and
    /// nothing is changed), or without the policy's data. For the probe
    /// (`FFmpegProbe.applyingQuickTimeLanguages`).
    public static func quickTimeLanguage(number: UInt16, label: String) -> String? {
        guard let entry = quickTimeNumbers.first(where: { $0.number == number }), entry.label == label else { return nil }
        return appleMeaning(of: entry)
    }

    /// The language tag Apple's players read QuickTime-list entry `entry`
    /// as, AS FFMPEG WRITES IT — the first number with that label: `zh-Hant`
    /// for `chi` (19), `de` for `ger`, `sv` for `sve` — or `nil` for text not
    /// on the list, or without the policy's data. What a value written into
    /// a MOV will be read back as (`meaningOnceStored`).
    static func quickTimeMeaning(ofEntry entry: String) -> String? {
        guard let first = quickTimeNumbers.first(where: { $0.label == entry }) else { return nil }
        return appleMeaning(of: first)
    }

    /// The entry this converter writes for each tag MOV can store, keyed by
    /// what Apple's players read the entry as (`zh-Hant` → `chi`, `de` →
    /// `ger`). The first match in list order wins, as in ffmpeg (`ron`
    /// before `mol` for Romanian). Never `sve` or `iri` (see above). Empty
    /// without the policy's data.
    static let quickTimeCodesByTag: [String: String] = {
        var table: [String: String] = [:]
        for entry in quickTimeListEntries where !quickTimeEntriesNamingAnotherLanguage.contains(where: { $0.entry == entry }) {
            guard let meaning = quickTimeMeaning(ofEntry: entry), table[meaning] == nil else { continue }
            table[meaning] = entry
        }
        return table
    }()

    /// The QuickTime-list entry for `tag`, and the part of the tag that entry
    /// says (`zh-Hant` for `zh-Hant-TW` → `chi`; `sr` for `sr-Latn` → `sr `),
    /// or `nil` when MOV cannot store the tag's language as it is.
    static func quickTimeEntry(for tag: LanguageTag) -> (code: String, says: String)? {
        guard tag.kind == .ordinary, let language = tag.language else { return nil }
        if let script = tag.script, let code = quickTimeCodesByTag["\(language)-\(script)"] {
            return (code, "\(language)-\(script)")
        }
        if let code = quickTimeCodesByTag[language] { return (code, language) }
        return nil
    }

    /// Why MOV stores no language for `canonical` although its QuickTime
    /// list has the language — or the code — in SOME form: words that
    /// complete "this file type (QuickTime) can only store the languages on
    /// its old list; …" — or `nil` when the list does not have it at all.
    /// Shared by the job's notes and the stream editor's warning. `named` is
    /// how the tag is named in the words (`“zh”`, or `“zh”, set in the
    /// stream editor,`).
    static func quickTimeGapWords(for canonical: String, named: String? = nil) -> String? {
        guard let policy else { return nil }
        let tag = policy.canonicaliser.canonicalise(canonical)
        guard tag.kind == .ordinary, let language = tag.language, quickTimeEntry(for: tag) == nil else { return nil }
        let named = named ?? "“\(canonical)”"
        if let scripted = quickTimeEntriesReadWithAScript.first(where: { $0.tag.hasPrefix(language + "-") }) {
            let differs = tag.script == nil ? "\(named) does not say that" : "\(named) is not that"
            return "that list has \(scripted.languageName) only as “\(scripted.entry)”, which Apple's players read as "
                + "\(scripted.meaning) (“\(scripted.tag)”), and \(differs)"
        }
        // Swedish or Irish: on the list only under another language's code.
        if let other = quickTimeEntriesNamingAnotherLanguage.first(where: { $0.language == language }) {
            return "that list has \(other.languageName) only as “\(other.entry)”, which Apple's players read as "
                + "\(other.languageName) but other programs read as \(other.registeredName), the language that code "
                + "is registered for"
        }
        // Serili or Rigwe (a Matroska `sve` track, say): the code is on the
        // list, but as Apple's code for Swedish or Irish. The third review's
        // build said it was not on the list at all, which was untrue.
        if let other = quickTimeEntriesNamingAnotherLanguage.first(where: { $0.entry == language }) {
            return "\(named) is on that list, but Apple's players read it as \(other.languageName), not as "
                + "\(other.registeredName)"
        }
        return nil
    }

    /// How a language a person set in the stream editor is stored in a
    /// container's language field — ONE answer shared by the job's notes
    /// (`languageWrite`) and the editor's warning before Apply
    /// (`StreamMetadataEditor.storageNote`), so they cannot disagree.
    public struct EditedLanguageField: Sendable, Equatable {
        /// Why the field cannot hold the whole tag, if it cannot.
        public enum Limit: Sendable, Equatable {
            /// It holds everything the tag says.
            case fits
            /// What was set is not a language tag at all (written `und`).
            case notATag
            /// A real language with no three-letter code (written `und`).
            case noThreeLetterCode(canonical: String)
            /// A three-letter field keeps only the language: `lost` (the
            /// region, script …) of `canonical` is not stored.
            case losesParts(lost: String, canonical: String)
            /// This file type cannot store this language at all: MOV, whose
            /// list has no entry for it, or a file type with no place for a
            /// language. The output stores NO language for the track: the
            /// command clears the field, so the source's value is not copied
            /// in instead (`LanguageWrite.Action.clear`).
            case cannotStore(canonical: String)
        }
        /// What the field gets, or `nil` when the output stores no language
        /// for the track (the file type cannot store this one — or cannot
        /// store even `und`). `nil` never means "leave the source's value":
        /// the command clears the field (`LanguageWrite.Action.clear`).
        public let value: String?
        /// Why it is less than the tag, if it is.
        public let limit: Limit
    }

    /// How `tag` (set by a person) is stored in `container`'s language
    /// field, or `nil` when the policy's data is missing.
    public static func editedLanguageField(_ tag: String, in container: ContainerFormat?) -> EditedLanguageField? {
        guard let policy else { return nil }
        let parsed = policy.canonicaliser.canonicalise(tag)
        let storage = languageFieldStorage(for: container)
        // What "not known" becomes in this file type: `und`, or nothing where
        // even that cannot be stored (MOV, the file types with no field).
        let unknown = storedUnknown(in: storage)
        guard let canonical = parsed.canonical else {
            return EditedLanguageField(value: unknown, limit: .notATag)
        }
        if storage == .nothing {
            return EditedLanguageField(value: nil, limit: canonical == "und" ? .fits : .cannotStore(canonical: canonical))
        }
        let form = languageFieldForm(for: container)
        if form == .fullTag { return EditedLanguageField(value: canonical, limit: .fits) }
        let code = policyCode(for: parsed, form: form)
        let primary = parsed.language ?? canonical
        guard let code else {
            // No code for the language in this field's form.
            if primary == "und" { return EditedLanguageField(value: unknown, limit: .fits) }
            if form == .quickTimeList { return EditedLanguageField(value: nil, limit: .cannotStore(canonical: canonical)) }
            return EditedLanguageField(value: unknown, limit: .noThreeLetterCode(canonical: canonical))
        }
        if let lost = partsNotSaid(of: parsed, form: form) {
            return EditedLanguageField(value: code, limit: .losesParts(lost: lost, canonical: canonical))
        }
        return EditedLanguageField(value: code, limit: .fits)
    }

    /// The policy's code for `tag`'s primary language in `form` — `ger`
    /// (bibliographic), `deu` (terminology), the QuickTime list's entry — or
    /// `nil` when there is none (`yue`, a grandfathered or private-use tag,
    /// a MOV language not on the list, or on it only with another script —
    /// see `quickTimeEntry(for:)`). `und` itself gives `und` (it has no
    /// QuickTime entry, so `nil` there). Not for `.fullTag`.
    static func policyCode(for tag: LanguageTag, form: LanguageFieldForm) -> String? {
        guard let policy else { return nil }
        switch form {
        case .bibliographic, .terminology, .fullTag:
            let codes = policy.iso6392.codes(for: tag.text)
            let code = form == .bibliographic ? codes.b : codes.t
            // `und` is a real answer only for `und` itself.
            if code == "und" && tag.language != "und" { return nil }
            return code
        case .quickTimeList:
            return quickTimeEntry(for: tag)?.code
        }
    }

    /// What `form`'s code for `tag` does not say: for a three-letter field,
    /// everything after the primary language (`partsBeyondLanguage`); for
    /// MOV, everything after what the QuickTime entry says — `TW` of
    /// `zh-Hant-TW` (whose entry `chi` says `zh-Hant`), `Latn` of `sr-Latn`.
    static func partsNotSaid(of tag: LanguageTag, form: LanguageFieldForm) -> String? {
        guard form == .quickTimeList, let says = quickTimeEntry(for: tag)?.says,
              tag.text.hasPrefix(says) else { return partsBeyondLanguage(tag) }
        guard tag.text.count > says.count else { return nil }
        return String(tag.text.dropFirst(says.count + 1))
    }

    /// What a value written into `storage`'s field will be read back as —
    /// for MOV, what Apple's players read the entry as, as ffmpeg writes it
    /// (`chi` is `zh-Hant`, `sve` is `sv`); elsewhere, the policy's reading
    /// of the text (`fre` is `fr`, `sve` is Serili). `nil` when it is not a
    /// language.
    static func meaningOnceStored(_ value: String, in storage: LanguageFieldStorage) -> String? {
        if storage == .quickTimeList { return quickTimeMeaning(ofEntry: value) }
        let reading = read(fileValue: value)
        return reading.unrecognised == nil ? reading.language : nil
    }

    /// What "not known" is stored as: `und`, or `nil` where even that cannot
    /// be stored (MOV, the file types with no language field) — the output
    /// then stores no language, and the command clears the field rather than
    /// let ffmpeg copy the source's value in (`LanguageWrite.Action.clear`).
    static func storedUnknown(in storage: LanguageFieldStorage) -> String? {
        storage == .unchecked ? "und" : storage.stored("und")
    }

    /// What a three-letter field loses of `tag`: everything after the
    /// primary language (`GB` of `en-GB`, `Hant-TW` of `zh-Hant-TW`), or
    /// `nil` when there is nothing after it.
    static func partsBeyondLanguage(_ tag: LanguageTag) -> String? {
        guard tag.kind == .ordinary, let language = tag.language, tag.text.count > language.count else { return nil }
        return String(tag.text.dropFirst(language.count + 1))
    }
}

extension TrackLanguage {

    /// What one output stream's `language` field gets, and what to tell the
    /// person about it.
    public struct LanguageWrite: Sendable, Equatable {

        /// What the command does with the output stream's `language` field.
        /// There are THREE outcomes, not two. Until the third independent
        /// review there were two — write a value, or give ffmpeg nothing —
        /// and "nothing" was used for "store no language" as well. But given
        /// nothing, ffmpeg COPIES the source's own value in: an mkvmerge file
        /// whose old field says `chi` for Cantonese came out of a MOV
        /// conversion as `chi` (which Apple's players read as Traditional
        /// Chinese), and an edit to `sv` left `eng`, both while the job's
        /// note said "no language is stored".
        public enum Action: Sendable, Equatable {
            /// Give ffmpeg nothing: it copies the source's own value unchanged
            /// — or there is no value to copy.
            case copySource
            /// Give ffmpeg this value.
            case write(String)
            /// Give ffmpeg an EMPTY value (`-metadata:s:<type>:N language=`),
            /// which removes the key: the output stores no language, whatever
            /// the source had. (ffmpeg then treats the stream as having none;
            /// checked with ffmpeg 9.0.1 — ffprobe and Apple's AVFoundation
            /// both read no language back from a MOV made this way.)
            case clear
        }

        /// What happens to the field.
        public let action: Action
        /// A plain-English line for the job's log when the output cannot
        /// hold exactly what the track says, else `nil`.
        public let note: String?

        public init(action: Action, note: String?) {
            self.action = action
            self.note = note
        }

        /// The text after `language=` in ffmpeg's arguments: the value, an
        /// empty string to clear the field, or `nil` when nothing is given.
        public var argumentValue: String? {
            switch action {
            case .copySource: return nil
            case .write(let value): return value
            case .clear: return ""
            }
        }
    }

    /// Decides one output stream's `language` field (TRACK-070), under the
    /// rule for the whole of this work: a copy or conversion must never lose
    /// or damage anything the source had that the person did not ask to
    /// change (COMPAT-030), must never silently turn a value into a different
    /// language (COMPAT-040), and says plainly — and truly — where something
    /// cannot be kept. What the file type can hold comes from ONE table
    /// (`LanguageFieldStorage`), so "kept as the source had it" is said only
    /// where it really is.
    ///
    /// A stream the person did NOT edit gets the first of these that works:
    /// 1. the policy's code in the field's form (`ger` for German in
    ///    Matroska, `deu` in MP4, `ger` from the QuickTime list in MOV), when
    ///    it loses nothing and the file type stores it — a correction, if the
    ///    source had another form;
    /// 2. nothing, so ffmpeg copies the source's own text, when the file type
    ///    stores that text exactly AND it still reads as the same language
    ///    (`yue` into MP4 or Matroska, Matroska's `fr-CA`) — "kept as the
    ///    source had it";
    /// 3. the language's own tag as text (`yue`, `fr-CA`), when the file type
    ///    stores it exactly — needed when the source's old field says less
    ///    than its full-tag field (mkvmerge writes `chi` for Cantonese), or
    ///    nothing ffmpeg copies (`und` for Abaza `abq`: then 2 never applies);
    /// 4. the policy's code with the region or script cut (`fra` for
    ///    `fr-CA` in MP4), with a note naming what is not saved;
    /// 5. otherwise `und` (not known) — or NO language, where even `und`
    ///    cannot be stored — with a note saying exactly why. The tool is
    ///    never left to cut or drop a value on its own: `romanian` into MP4
    ///    would have become `rom` (Romany), a different language.
    /// A value the probe could not read at all (`english`, `romanian`) takes
    /// only 2 or 5. In a free-text field (Ogg) the canonical tag is written.
    ///
    /// A stream the person DID edit gets the policy's form of their tag, with
    /// a note when the field cannot hold all of it (`editedLanguageField`).
    ///
    /// "No language" is never left to chance: when the answer is that the
    /// output stores none and ffmpeg would otherwise copy the source's value
    /// in, the field is CLEARED (`LanguageWrite.Action.clear`). See `Action`
    /// for the fault this fixed.
    ///
    /// Without the policy's data nothing is converted: an edit is written as
    /// typed, and an unedited value as the file gave it.
    ///
    /// - Parameters:
    ///   - streamNumber: The source stream's whole-file number (for notes).
    ///   - edited: The stream editor's tag, or `nil` if not edited.
    ///   - sourceLanguage: The probe's canonical tag (`und` when it could not
    ///     read the value), or `nil` when the file states none.
    ///   - sourceUnrecognised: The file's own text when unrecognised.
    ///   - sourceStoredText: The text the source's language field holds —
    ///     what ffmpeg copies when given no value (`MediaStream
    ///     .languageAsStored`). `nil` when unknown (data probed before it was
    ///     kept): then the source is taken to hold `sourceLanguage` itself.
    ///     EMPTY when ffmpeg copies nothing (a Matroska full tag whose old
    ///     field says only `und`): then nothing is left for ffmpeg to copy,
    ///     and a value that must be kept is written instead.
    ///   - fullTagUnknown: The source is a Matroska, MOV or MP4 file that
    ///     may record a fuller language than its old field says, which could
    ///     not be read (`MediaStream.languageFullTagUnknown`) — said in a note.
    ///   - container: The output container.
    ///   - isReplacement: The output stream comes from a separate file
    ///     (a tone-mapped subtitle), so ffmpeg has nothing to copy from:
    ///     what would be "left to copy" is written instead.
    ///   - keepsSourceMetadata: Whether the source's metadata is kept at
    ///     all (`-map_metadata -1` drops it; then only edits are written).
    public static func languageWrite(
        streamNumber: Int,
        edited: String?,
        sourceLanguage: String?,
        sourceUnrecognised: String?,
        sourceStoredText: String? = nil,
        fullTagUnknown: Bool = false,
        container: ContainerFormat?,
        isReplacement: Bool,
        keepsSourceMetadata: Bool
    ) -> LanguageWrite {
        let stream = "Stream #\(streamNumber)"
        guard let policy else {
            if let edited { return LanguageWrite(action: .write(edited), note: nil) }
            guard keepsSourceMetadata, let sourceLanguage else { return LanguageWrite(action: .copySource, note: nil) }
            return LanguageWrite(action: .write(sourceLanguage), note: nil)
        }
        let storage = languageFieldStorage(for: container)
        let unknown = storedUnknown(in: storage)
        // "Store no language": CLEAR the field when ffmpeg would otherwise
        // copy a value in — the source's own (when its metadata is kept), or
        // a replacement stream's file's. With nothing to copy, giving ffmpeg
        // nothing already stores nothing, and the command stays as it was.
        let copiesAValue = isReplacement
            || (keepsSourceMetadata && (sourceStoredText ?? sourceUnrecognised ?? sourceLanguage) != nil)
        let storeNothing: LanguageWrite.Action = copiesAValue ? .clear : .copySource
        // What "not known" becomes: `und`, or no language where even that
        // cannot be stored (MOV, the file types with no field).
        let unknownAction = unknown.map(LanguageWrite.Action.write) ?? storeNothing
        // "written as “und” (not known)", or where even that cannot be
        // stored: "no language is stored".
        let unknownWords = unknown == nil ? "no language is stored" : "it is written as “und” (not known)"

        // --- An edit: the person asked for this language. ---
        if let edited, let field = editedLanguageField(edited, in: container) {
            return editedWrite(edited: edited, field: field, stream: stream, storage: storage, storeNothing: storeNothing)
        }

        // --- No edit: keep what the source had. ---
        guard keepsSourceMetadata else { return LanguageWrite(action: .copySource, note: nil) }

        // The file type has no place for a language at all.
        if storage == .nothing {
            let what = sourceUnrecognised ?? sourceLanguage
            guard let what, what != "und" else { return LanguageWrite(action: storeNothing, note: nil) }
            return LanguageWrite(
                action: storeNothing,
                note: "\(stream): this file type has no place for a track's language, so “\(what)” is not kept."
            )
        }

        // A value that is not a language at all: kept only where this file
        // type stores it exactly; otherwise `und`, and why. Never in MOV,
        // where whatever its list holds Apple's players read as a language:
        // text the source did not give as a language would silently become
        // one (COMPAT-040).
        if let raw = sourceUnrecognised ?? nonTag(sourceLanguage, policy: policy) {
            let fix = " Set the right language in the stream editor if you know it."
            if storage != .unchecked, storage != .quickTimeList, storage.keeps(raw) {
                // Left for ffmpeg to copy only when what it copies IS that
                // text; a Matroska full tag's text is not in the old field
                // ffmpeg copies (which may say only `und`, copied as
                // nothing), so there it is written.
                let copiesRaw = (sourceStoredText ?? raw) == raw
                return LanguageWrite(
                    action: isReplacement || !copiesRaw ? .write(raw) : .copySource,
                    note: "\(stream): the file's language “\(raw)” is not a language code; kept as the source had it." + fix
                )
            }
            return LanguageWrite(
                action: unknownAction,
                note: "\(stream): the file's language “\(raw)” is not a language code, and "
                    + limitWords(for: raw, in: storage) + ", so \(unknownWords)." + fix
            )
        }

        guard let source = sourceLanguage else { return LanguageWrite(action: .copySource, note: nil) }
        let tag = policy.canonicaliser.canonicalise(source)
        guard let canonical = tag.canonical else { return LanguageWrite(action: .copySource, note: nil) }
        let copied = sourceStoredText ?? source
        // ffmpeg copies NOTHING (see `MediaStream.languageAsStored`): a
        // Matroska track whose full tag is `abq`, `pnb` or `und-Latn` while
        // its old field says only `und`. Then step 2 below ("leave it for
        // ffmpeg to copy") can never keep the language, and step 3 writes the
        // tag as text. The fourth independent review found `abq` and `pnb`
        // gone from Matroska, MP4 and MPEG-TS outputs under the note "kept
        // as the source had it", because the empty field was taken to say
        // `abq`.
        let copiesNothing = copied.isEmpty
        let sourceField = copiesNothing
            ? "the source's old field (which says only “und”, not known)"
            : "the source's own field (“\(copied)”)"
        // A Matroska, MOV or MP4 source whose fuller language could not be
        // read (see `MediaStream.languageFullTagUnknown`): said on its own,
        // or after whatever else is said about this stream. "A fuller
        // language", not "a fuller language tag": in a MOV it may be what
        // the track's language NUMBER means to Apple's players (19 is
        // Traditional Chinese), not a tag.
        let fullTagSentence = "The source may also record a fuller language for this track (with a region "
            + "or script, say), which could not be read; if it does, that is not kept, and no automatic title is "
            + "made from the three-letter code “\(copied)”."
        func write(_ action: LanguageWrite.Action, _ note: String?) -> LanguageWrite {
            guard fullTagUnknown else { return LanguageWrite(action: action, note: note) }
            return LanguageWrite(action: action, note: note.map { $0 + " " + fullTagSentence } ?? "\(stream): " + fullTagSentence)
        }

        // "Not known" in the source: `und` where it can be stored.
        if canonical == "und" { return write(unknownAction, nil) }

        let form = languageFieldForm(for: container)
        let registered = tag.language.map(policy.isRegisteredLanguage) ?? true
        if form == .fullTag {
            // A free-text field (Ogg) keeps the whole tag — but a language
            // that is not registered (`xx-bogus`) is said, as it is for
            // Matroska (LANG-001: report it; COMPAT-040). The third
            // independent review found Ogg wrote it with no note.
            guard !registered else { return write(.write(canonical), nil) }
            let kept = copied == canonical ? "kept as the source had it" : "written as “\(canonical)”"
            return write(
                .write(canonical),
                "\(stream): the file's language “\(canonical)” is not a registered language code; \(kept). "
                    + "Set the right language in the stream editor if you know it."
            )
        }

        let code = policyCode(for: tag, form: form)
        let lost = partsNotSaid(of: tag, form: form)
        // Why the policy's code will not do, in words: having no code at all
        // matters more than losing a region.
        let reason: String
        if code == nil, !registered {
            reason = "the file's language “\(canonical)” is not a registered language code"
        } else if code == nil, form == .quickTimeList {
            reason = "language “\(canonical)” is not on the QuickTime list of languages this file type can store"
        } else if code == nil {
            reason = "language “\(canonical)” has no three-letter code"
        } else {
            reason = "language “\(canonical)” cannot be written to this file type's three-letter language field "
                + "without losing “\(lost ?? "")”"
        }
        let fix = registered ? "" : " Set the right language in the stream editor if you know it."

        // 1. The policy's code, when it loses nothing and is stored as it is.
        if let code, lost == nil, storage == .unchecked || storage.keeps(code) {
            return write(.write(code), nil)
        }
        if storage != .unchecked {
            // 2. The source's own text, when stored exactly and still the
            //    same language once stored — for MOV, as Apple's players read
            //    it: `chi` copied in for plain `zh` would become Traditional
            //    Chinese there.
            //    Never when ffmpeg copies nothing (`copiesNothing`).
            if !copiesNothing, storage.keeps(copied), meaningOnceStored(copied, in: storage) == canonical {
                // MOV, and the source's own `sve` or `iri` (a MOV's Swedish
                // or Irish): kept, because the output then says exactly what
                // the source said — but never written for Swedish or Irish
                // from anywhere else, so the note says why this is different.
                if storage == .quickTimeList,
                   let other = quickTimeEntriesNamingAnotherLanguage.first(where: { $0.entry == copied }) {
                    return write(
                        isReplacement ? .write(copied) : .copySource,
                        "\(stream): the source's own QuickTime code “\(copied)” is kept as it was. Apple's players read it as "
                            + "\(other.languageName), but other programs read it as \(other.registeredName), the language "
                            + "that code is registered for."
                    )
                }
                return write(isReplacement ? .write(copied) : .copySource, "\(stream): \(reason); kept as the source had it.\(fix)")
            }
            // 3. The language's tag itself, as text.
            if storage.keeps(canonical), storage != .quickTimeList || meaningOnceStored(canonical, in: storage) == canonical {
                return write(
                    .write(canonical),
                    "\(stream): \(reason), so “\(canonical)” is written into the field as it is, because copying "
                        + "\(sourceField) would not keep it.\(fix)"
                )
            }
        }
        // 4. The code with the region or script cut.
        if let code, let lost, storage == .unchecked || storage.keeps(code) {
            return write(
                .write(code),
                "\(stream): " + onlyStoresWords(storage) + ", so “\(lost)” in “\(canonical)” is not saved "
                    + "(written as “\(code)”)."
            )
        }
        // 5. Not known, and why.
        if storage == .quickTimeList, code == nil {
            return write(unknownAction, "\(stream): " + quickTimeWords(for: canonical) + ", so \(unknownWords).\(fix)")
        }
        return write(unknownAction, "\(stream): \(reason), and " + limitWords(for: canonical, in: storage) + ", so \(unknownWords).\(fix)")
    }

    /// Why MOV cannot store `canonical`, in words for a note or the stream
    /// editor's warning: "this file type (QuickTime) can only store the
    /// languages on its old list, and “yue” is not on it" — or, where the
    /// list has the language only with another script or under a label that
    /// is not a language code, which (`quickTimeGapWords`).
    static func quickTimeWords(for canonical: String, named: String? = nil) -> String {
        let start = "this file type (QuickTime) can only store the languages on its old list"
        if let gap = quickTimeGapWords(for: canonical, named: named) { return "\(start); \(gap)" }
        return "\(start), and \(named ?? "“\(canonical)”") is not on it"
    }

    /// What a field that keeps less than the whole tag can store, in words:
    /// "this file type can only store the language" — or, for MOV, whose
    /// entries can carry a script as well (`chi` is `zh-Hant` to Apple's
    /// players), "…only store the languages on its old list".
    static func onlyStoresWords(_ storage: LanguageFieldStorage) -> String {
        storage == .quickTimeList
            ? "this file type (QuickTime) can only store the languages on its old list"
            : "this file type can only store the language"
    }

    /// `text` when it is not a language tag at all (data probed before the
    /// probe kept unrecognised values apart), else `nil`.
    private static func nonTag(_ text: String?, policy: MediaLanguagePolicy) -> String? {
        guard let text, policy.canonicaliser.canonicalise(text).canonical == nil else { return nil }
        return text
    }

    /// Why `storage` cannot keep `value` as it is, in words, for a note:
    /// "this file type keeps only its first three letters (“rom”, which is a
    /// different language)".
    static func limitWords(for value: String, in storage: LanguageFieldStorage) -> String {
        switch storage {
        case .firstThreeLowerCase:
            if let cut = storage.stored(value) {
                // The cut text may itself be a language code — `romanian`
                // becomes `rom`, which is Romany — so it is never left to
                // stand: whether it is the language meant cannot be known.
                let reading = read(fileValue: cut)
                let meaning = reading.unrecognised == nil && reading.language != "und"
                    ? "which is itself a language code, and may not be the language meant"
                    : "which is not a language code"
                return "this file type would keep only its first three letters, “\(cut)”, \(meaning)"
            }
            return "this file type can only store three lower-case letters"
        case .threeCharacterPieces:
            return "this file type can only store codes of exactly three letters"
        case .quickTimeList:
            if let other = quickTimeEntriesNamingAnotherLanguage.first(where: { $0.entry == value }) {
                return "this file type (QuickTime) would store “\(value)” as the code Apple's players read as "
                    + "\(other.languageName)"
            }
            return "this file type (QuickTime) can only store the languages on its old list"
        case .nothing:
            return "this file type has no place for a track's language"
        case .unchecked:
            return "the output's file type is not known (so it cannot be checked that it would be kept)"
        case .anyText:
            return "this file type cannot store it"
        }
    }

    /// The write for an edited language (see `editedLanguageField`). Where
    /// the field gets nothing, `storeNothing` says how that is made true:
    /// CLEAR it when ffmpeg would otherwise copy the source's value in —
    /// an edit to `sv` going to MOV used to leave the source's `eng`.
    private static func editedWrite(
        edited: String, field: EditedLanguageField, stream: String, storage: LanguageFieldStorage,
        storeNothing: LanguageWrite.Action
    ) -> LanguageWrite {
        let action = field.value.map(LanguageWrite.Action.write) ?? storeNothing
        let unknownWords = field.value == nil ? "no language is stored" : "the language is written as “und” (not known)"
        switch field.limit {
        case .fits:
            return LanguageWrite(action: action, note: nil)
        case .notATag:
            return LanguageWrite(
                action: action,
                note: "\(stream): “\(edited)”, set in the stream editor, is not a language tag, so \(unknownWords)."
            )
        case .noThreeLetterCode(let canonical):
            return LanguageWrite(
                action: action,
                note: "\(stream): this file type can only store three-letter language codes, and “\(canonical)” has "
                    + "none, so \(unknownWords)."
            )
        case .losesParts(let lost, let canonical):
            return LanguageWrite(
                action: action,
                note: "\(stream): " + onlyStoresWords(storage) + ", so “\(lost)” in “\(canonical)” is not "
                    + "saved (written as “\(field.value ?? "und")”)."
            )
        case .cannotStore(let canonical):
            return LanguageWrite(
                action: storeNothing,
                note: storage == .nothing
                    ? "\(stream): this file type has no place for a track's language, so “\(canonical)”, set in the "
                        + "stream editor, is not saved."
                    : "\(stream): " + quickTimeWords(for: canonical, named: "“\(canonical)”, set in the stream editor,")
                        + ", so no language is stored."
            )
        }
    }
}

// MARK: - Automatic titles (NAME-010)

extension TrackLanguage {

    /// The title to write for a track in `tag`'s language when it has no
    /// meaningful title of its own (NAME-010): the language's own name,
    /// "Deutsch", "English (United Kingdom)", "日本語". `nil` for special
    /// codes (`und`, `mul`, `mis`, `zxx`, local use), for a value that is
    /// not a well-formed tag, and when the policy's data is missing.
    public static func autonymTitle(for tag: String) -> String? {
        guard let policy, let canonical = policy.canonicaliser.canonicalise(tag).canonical else { return nil }
        return LanguageNames.autonym(of: canonical)
    }

    /// Whether ffmpeg keeps each stream's title apart from the file's own
    /// title in `container` — the ONLY containers an automatic title
    /// (NAME-010) is written to.
    ///
    /// Checked with ffmpeg 9.0.1 (28 Sept 2026), writing a file title and a
    /// title on each of two audio streams, then reading them back:
    /// * Matroska, Matroska audio and WebM keep each track's name and the
    ///   file's title separately. Allowed.
    /// * Ogg (Vorbis, Opus, FLAC in Ogg) does NOT: ffmpeg puts the file's tags
    ///   into every stream's comments, and a stream `TITLE` replaces the
    ///   song's title there — the independent review's case, where a song
    ///   called "My Song" came out called "English". Not allowed.
    /// * MP4, MOV and M4A keep the file's title, but ffmpeg writes no track
    ///   title at all (it is simply dropped). Not allowed: writing one would
    ///   do nothing.
    /// * Anything else was not checked, so gets none. This is an allow-list
    ///   on purpose: a container nobody checked can never lose a title.
    public static func keepsStreamTitlesSeparately(_ container: ContainerFormat?) -> Bool {
        switch container {
        case .mkv, .mka, .mks, .mk3d, .webm: return true
        default: return false
        }
    }

    /// The automatic title (NAME-010) for a track in `tag`'s language with
    /// the roles `disposition` records: the language's own name, then the
    /// track's roles in words, joined as the policy's menu labels are
    /// (UI-070, " — "): "English", "English — SDH", "English — Forced",
    /// "Deutsch — Commentary". Built from the same structured data as the
    /// label, so two tracks of one language with DIFFERENT roles never get
    /// the same title (the first build wrote "English" on all of them).
    /// Roles stay in words in English, as the policy's own examples are;
    /// the flags themselves are always written too (TRACK-010).
    ///
    /// `nil` when the language has no autonym (see `autonymTitle`).
    public static func automaticTitle(for tag: String, disposition: StreamDisposition?, type: StreamType) -> String? {
        guard let autonym = autonymTitle(for: tag) else { return nil }
        let words = disposition.map { titleRoleWords(for: $0, type: type) } ?? []
        return TrackMenuLabel.label(
            languageName: autonym,
            roles: words.map(\.role),
            type: type.policyTrackType,
            roleNames: Dictionary(words.map { ($0.role, $0.word) }, uniquingKeysWith: { first, _ in first }),
            channels: nil
        )
    }

    /// The roles of a track in words, for an automatic title. The policy's
    /// own roles come first in its order (`TrackMenuLabel` sorts them); the
    /// flags the policy files under "anything else" are named one by one
    /// (as `TrackRole.unrecognised`, which ranks as "anything else"), so a
    /// karaoke track and a lyrics track do not share a title either.
    /// `default`, `original` and `dub` are not roles and are not named.
    static func titleRoleWords(for disposition: StreamDisposition, type: StreamType) -> [(role: TrackRole, word: String)] {
        var words: [(role: TrackRole, word: String)] = []
        switch type {
        case .audio:
            if disposition.isComment { words.append((.commentary, "Commentary")) }
            if disposition.isVisualImpaired || disposition.isDescriptions {
                words.append((.audioDescription, "Audio Description"))
            }
            if disposition.isCleanEffects { words.append((.unrecognised("clean_effects"), "Music and Effects")) }
            if disposition.isKaraoke { words.append((.unrecognised("karaoke"), "Karaoke")) }
            if disposition.isLyrics { words.append((.unrecognised("lyrics"), "Lyrics")) }
            if disposition.isHearingImpaired { words.append((.unrecognised("hearing_impaired"), "Hearing Impaired")) }
        case .subtitle:
            if disposition.isHearingImpaired || disposition.isCaptions { words.append((.sdh, "SDH")) }
            if disposition.isForced { words.append((.forced, "Forced")) }
            if disposition.isComment { words.append((.commentary, "Commentary")) }
            if disposition.isDescriptions { words.append((.unrecognised("descriptions"), "Text Descriptions")) }
            if disposition.isLyrics { words.append((.unrecognised("lyrics"), "Lyrics")) }
            if disposition.isKaraoke { words.append((.unrecognised("karaoke"), "Karaoke")) }
            if disposition.isVisualImpaired { words.append((.unrecognised("visual_impaired"), "Visually Impaired")) }
        case .video, .data, .attachment, .unknown:
            break
        }
        return words
    }
}
