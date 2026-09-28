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
        /// The entry on ffmpeg's QuickTime language list for the same
        /// language (`ger`, `fra`, `chi`, `jpn`, `gre` — see
        /// `quickTimeCode(forLanguage:)`) — MOV, whose writer stores nothing
        /// else. Writing the terminology code there (`deu`) stored nothing.
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

    /// The strings ffmpeg's MOV writer accepts as a language, in the order of
    /// its QuickTime list (`mov_mdhd_language_map` in ffmpeg's `isom.c`,
    /// 9.0.1): each is the label ffmpeg gives one old Macintosh language
    /// number, and it reads the same label back. Several are not ISO 639-2
    /// codes at all (`sve`, `iri`), and four end in a space (`hr `, `fo `,
    /// `sr `, `pa `). Empty entries are left out.
    static let quickTimeListEntries: [String] = [
        "eng", "fra", "ger", "ita", "dut", "sve", "spa", "dan", "por", "nor", "heb", "jpn", "ara", "fin",
        "gre", "ice", "mlt", "tur", "hr ", "chi", "urd", "hin", "tha", "kor", "lit", "pol", "hun", "est",
        "lav", "smi", "fo ", "per", "rus", "iri", "alb", "ron", "ces", "slk", "slv", "yid", "sr ", "mac",
        "bul", "ukr", "bel", "uzb", "kaz", "aze", "arm", "geo", "mol", "kir", "tgk", "tuk", "mon", "pus",
        "kur", "kas", "snd", "tib", "nep", "san", "mar", "ben", "asm", "guj", "pa ", "ori", "mal", "kan",
        "tam", "tel", "sin", "bur", "khm", "lao", "vie", "ind", "tgl", "may", "amh", "tir", "orm", "som",
        "swa", "kin", "run", "nya", "mlg", "epo", "wel", "baq", "cat", "lat", "que", "grn", "aym", "tat",
        "uig", "dzo", "jav"
    ]

    /// The QuickTime list's entry for primary language `language` (`de` →
    /// `ger`, `zh` → `chi`, `el` → `gre`), or `nil` when the list has none.
    /// An entry counts only when the policy's reader reads it back as that
    /// SAME language (LANG-002) — so the next program to open the file,
    /// this one included, gets the language back. That leaves out the
    /// labels that are not language codes: `sve` (Swedish) and `iri`
    /// (Irish) read as other text, so Swedish and Irish cannot be kept in a
    /// MOV file made by ffmpeg, and are reported. The first match in list
    /// order wins, as in ffmpeg (`ron` before `mol` for Romanian).
    static func quickTimeCode(forLanguage language: String) -> String? {
        quickTimeCodesByLanguage[language]
    }

    /// `quickTimeCode(forLanguage:)`'s table, worked out once from the list
    /// and the policy's reader. Empty without the policy's data.
    private static let quickTimeCodesByLanguage: [String: String] = {
        var table: [String: String] = [:]
        for entry in quickTimeListEntries {
            let reading = read(fileValue: entry)
            guard reading.unrecognised == nil, reading.language != "und", policy != nil,
                  table[reading.language] == nil else { continue }
            table[reading.language] = entry
        }
        return table
    }()

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
            /// language. Nothing is written.
            case cannotStore(canonical: String)
        }
        /// What the field gets, or `nil` when nothing is written (the file
        /// type cannot store it — or cannot store even `und`).
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
        if let lost = partsBeyondLanguage(parsed) {
            return EditedLanguageField(value: code, limit: .losesParts(lost: lost, canonical: canonical))
        }
        return EditedLanguageField(value: code, limit: .fits)
    }

    /// The policy's code for `tag`'s primary language in `form` — `ger`
    /// (bibliographic), `deu` (terminology), the QuickTime list's entry — or
    /// `nil` when there is none (`yue`, a grandfathered or private-use tag,
    /// a MOV language not on the list). `und` itself gives `und` (it has no
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
            guard let language = tag.language else { return nil }
            return quickTimeCode(forLanguage: language)
        }
    }

    /// What "not known" is stored as: `und`, or `nil` where even that cannot
    /// be stored (MOV, the file types with no language field).
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
        /// The value to give ffmpeg, or `nil` to give none — ffmpeg then
        /// copies the source's own value unchanged (or there is none).
        public let value: String?
        /// A plain-English line for the job's log when the output cannot
        /// hold exactly what the track says, else `nil`.
        public let note: String?
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
    ///    than its full-tag field (mkvmerge writes `chi` for Cantonese);
    /// 4. the policy's code with the region or script cut (`fra` for
    ///    `fr-CA` in MP4), with a note naming what is not saved;
    /// 5. otherwise `und` (not known) — or nothing, where even `und` cannot
    ///    be stored — with a note saying exactly why. The tool is never left
    ///    to cut or drop a value on its own: `romanian` into MP4 would have
    ///    become `rom` (Romany), a different language.
    /// A value the probe could not read at all (`english`, `romanian`) takes
    /// only 2 or 5. In a free-text field (Ogg) the canonical tag is written.
    ///
    /// A stream the person DID edit gets the policy's form of their tag, with
    /// a note when the field cannot hold all of it (`editedLanguageField`).
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
    ///   - fullTagUnknown: The source is a Matroska file that may record a
    ///     fuller language than its old field says, which could not be read
    ///     (`MediaStream.languageFullTagUnknown`) — said in a note.
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
            if let edited { return LanguageWrite(value: edited, note: nil) }
            return LanguageWrite(value: keepsSourceMetadata ? sourceLanguage : nil, note: nil)
        }
        let storage = languageFieldStorage(for: container)
        let unknown = storedUnknown(in: storage)
        // "written as “und” (not known)", or where even that cannot be
        // stored: "no language is stored".
        let unknownWords = unknown == nil ? "no language is stored" : "it is written as “und” (not known)"

        // --- An edit: the person asked for this language. ---
        if let edited, let field = editedLanguageField(edited, in: container) {
            return editedWrite(edited: edited, field: field, stream: stream, storage: storage)
        }

        // --- No edit: keep what the source had. ---
        guard keepsSourceMetadata else { return LanguageWrite(value: nil, note: nil) }

        // The file type has no place for a language at all.
        if storage == .nothing {
            let what = sourceUnrecognised ?? sourceLanguage
            guard let what, what != "und" else { return LanguageWrite(value: nil, note: nil) }
            return LanguageWrite(
                value: nil,
                note: "\(stream): this file type has no place for a track's language, so “\(what)” is not kept."
            )
        }

        // A value that is not a language at all: kept only where this file
        // type stores it exactly; otherwise `und`, and why.
        if let raw = sourceUnrecognised ?? nonTag(sourceLanguage, policy: policy) {
            let fix = " Set the right language in the stream editor if you know it."
            if storage != .unchecked, storage.keeps(raw) {
                return LanguageWrite(
                    value: isReplacement ? raw : nil,
                    note: "\(stream): the file's language “\(raw)” is not a language code; kept as the source had it." + fix
                )
            }
            return LanguageWrite(
                value: unknown,
                note: "\(stream): the file's language “\(raw)” is not a language code, and "
                    + limitWords(for: raw, in: storage) + ", so \(unknownWords)." + fix
            )
        }

        guard let source = sourceLanguage else { return LanguageWrite(value: nil, note: nil) }
        let tag = policy.canonicaliser.canonicalise(source)
        guard let canonical = tag.canonical else { return LanguageWrite(value: nil, note: nil) }
        let copied = sourceStoredText ?? source
        // A Matroska source whose fuller language tag could not be read
        // (see `MediaStream.languageFullTagUnknown`): said on its own, or
        // after whatever else is said about this stream.
        let fullTagSentence = "The source may also record a fuller language tag for this track (with a region "
            + "or script, say), which could not be read; if it does, that is not kept, and no automatic title is "
            + "made from the three-letter code “\(copied)”."
        func write(_ value: String?, _ note: String?) -> LanguageWrite {
            guard fullTagUnknown else { return LanguageWrite(value: value, note: note) }
            return LanguageWrite(value: value, note: note.map { $0 + " " + fullTagSentence } ?? "\(stream): " + fullTagSentence)
        }

        // "Not known" in the source: `und` where it can be stored.
        if canonical == "und" { return write(unknown, nil) }

        let form = languageFieldForm(for: container)
        if form == .fullTag { return write(canonical, nil) }

        let code = policyCode(for: tag, form: form)
        let lost = partsBeyondLanguage(tag)
        let registered = tag.language.map(policy.isRegisteredLanguage) ?? true
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
            return write(code, nil)
        }
        if storage != .unchecked {
            // 2. The source's own text, when stored exactly and still the
            //    same language.
            if storage.keeps(copied), read(fileValue: copied).language == canonical {
                return write(isReplacement ? copied : nil, "\(stream): \(reason); kept as the source had it.\(fix)")
            }
            // 3. The language's tag itself, as text.
            if storage.keeps(canonical) {
                return write(
                    canonical,
                    "\(stream): \(reason), so “\(canonical)” is written into the field as it is, because copying "
                        + "the source's own field (“\(copied)”) would not keep it.\(fix)"
                )
            }
        }
        // 4. The code with the region or script cut.
        if let code, let lost, storage == .unchecked || storage.keeps(code) {
            return write(
                code,
                "\(stream): this file type can only store the language, so “\(lost)” in “\(canonical)” is not saved "
                    + "(written as “\(code)”)."
            )
        }
        // 5. Not known, and why.
        if storage == .quickTimeList, code == nil {
            return write(
                unknown,
                "\(stream): this file type (QuickTime) can only store the languages on its old list, and "
                    + "“\(canonical)” is not on it, so \(unknownWords).\(fix)"
            )
        }
        return write(unknown, "\(stream): \(reason), and " + limitWords(for: canonical, in: storage) + ", so \(unknownWords).\(fix)")
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
            return "this file type (QuickTime) can only store the languages on its old list"
        case .nothing:
            return "this file type has no place for a track's language"
        case .unchecked:
            return "the output's file type is not known (so it cannot be checked that it would be kept)"
        case .anyText:
            return "this file type cannot store it"
        }
    }

    /// The write for an edited language (see `editedLanguageField`).
    private static func editedWrite(
        edited: String, field: EditedLanguageField, stream: String, storage: LanguageFieldStorage
    ) -> LanguageWrite {
        let unknownWords = field.value == nil ? "no language is stored" : "the language is written as “und” (not known)"
        switch field.limit {
        case .fits:
            return LanguageWrite(value: field.value, note: nil)
        case .notATag:
            return LanguageWrite(
                value: field.value,
                note: "\(stream): “\(edited)”, set in the stream editor, is not a language tag, so \(unknownWords)."
            )
        case .noThreeLetterCode(let canonical):
            return LanguageWrite(
                value: field.value,
                note: "\(stream): this file type can only store three-letter language codes, and “\(canonical)” has "
                    + "none, so \(unknownWords)."
            )
        case .losesParts(let lost, let canonical):
            return LanguageWrite(
                value: field.value,
                note: "\(stream): this file type can only store the language, so “\(lost)” in “\(canonical)” is not "
                    + "saved (written as “\(field.value ?? "und")”)."
            )
        case .cannotStore(let canonical):
            return LanguageWrite(
                value: nil,
                note: storage == .nothing
                    ? "\(stream): this file type has no place for a track's language, so “\(canonical)”, set in the "
                        + "stream editor, is not saved."
                    : "\(stream): this file type (QuickTime) can only store the languages on its old list, and "
                        + "“\(canonical)”, set in the stream editor, is not on it, so no language is stored."
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
