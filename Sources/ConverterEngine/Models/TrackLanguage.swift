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

    /// Which form a container's language field takes when ffmpeg writes it.
    ///
    /// WHAT WAS CHECKED, AND WITH WHAT (TRACK-070 says: test the tool you
    /// actually run, do not trust a table). On 28 Sept 2026, with ffmpeg /
    /// ffprobe 9.0.1 (Homebrew) and MKVToolNix 101.0 on the developer's Mac:
    ///
    /// * Matroska / WebM: ffmpeg writes the `language` metadata string, as
    ///   given, into the OLD `Language` element — even `en-GB` or `zh-Hant`,
    ///   which that element (ISO 639-2 bibliographic, RFC 9559 §12) cannot
    ///   hold. It never writes `LanguageBCP47`. When READING, ffmpeg ignores
    ///   `LanguageBCP47` (a file made by mkvmerge with `en-GB` probes as
    ///   `eng`), and a `-c copy` remux drops it. So the only field ffmpeg can
    ///   write is the old one, and it is written in the bibliographic form
    ///   the policy requires (`ger`, `fre`, `chi`). Region and script CANNOT
    ///   be stored in a Matroska file made by ffmpeg — the autonym title
    ///   (NAME-010) still says them in words. Writing LanguageBCP47 would
    ///   need a post-pass (mkvpropedit, or our own EBML writer).
    /// * MP4 / MOV: ffmpeg writes the `mdhd` language from the metadata
    ///   string AS GIVEN if it is three letters (`ger` stays `ger` — the
    ///   wrong form for MP4) and silently drops anything else (`en-GB`,
    ///   `de`). It writes no `elng` box. So the terminology form (`deu`,
    ///   `fra`, `zho`) must be passed explicitly. Whether ffprobe would read
    ///   an `elng` box could not be checked: no tool here writes one.
    /// * Roles: ffmpeg writes FlagOriginal, FlagCommentary,
    ///   FlagHearingImpaired, FlagVisualImpaired, FlagForced and (on subtitle
    ///   tracks) FlagTextDescriptions to Matroska and reads them back; MP4
    ///   keeps forced/commentary/SDH/captions/description through `kind`
    ///   boxes but has no "original" flag at all.
    ///
    /// ContainerLanguageToolTests re-checks the facts this code relies on
    /// against whatever ffmpeg the test machine has (skipped without one).
    public enum LanguageFieldForm: Sendable, Equatable {
        /// ISO 639-2 bibliographic (`ger`) — Matroska's old `Language`.
        case bibliographic
        /// ISO 639-2 terminology (`deu`) — MP4/MOV `mdhd`; also used for
        /// containers the policy's table does not name, whose ffmpeg writers
        /// take a three-letter code (MPEG-TS keeps only the first three
        /// characters of whatever it is given).
        case terminology
        /// The canonical BCP 47 tag — free-text fields (Ogg's Vorbis
        /// comment `LANGUAGE`).
        case fullTag
    }

    /// The form `container`'s language field needs (see `LanguageFieldForm`).
    public static func languageFieldForm(for container: ContainerFormat?) -> LanguageFieldForm {
        switch container {
        case .mkv, .mka, .mks, .mk3d, .webm:
            return .bibliographic
        case .ogg, .ogm:
            return .fullTag
        default:
            return .terminology
        }
    }

    /// Whether ffmpeg writes a copied `language` value into `container`'s
    /// field AS GIVEN, whatever it is — true for Matroska and WebM (ffmpeg
    /// 9.0.1 puts the text straight into the old `Language` element; see
    /// `LanguageFieldForm`). MP4/MOV keep only exactly three letters and
    /// drop anything else; other containers were not checked, so are
    /// treated like MP4.
    static func keepsCopiedLanguageText(_ container: ContainerFormat?) -> Bool {
        switch container {
        case .mkv, .mka, .mks, .mk3d, .webm: return true
        default: return false
        }
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
        }
        /// What the field gets.
        public let value: String
        /// Why it is less than the tag, if it is.
        public let limit: Limit
    }

    /// How `tag` (set by a person) is stored in `container`'s language
    /// field, or `nil` when the policy's data is missing.
    public static func editedLanguageField(_ tag: String, in container: ContainerFormat?) -> EditedLanguageField? {
        guard let policy else { return nil }
        let parsed = policy.canonicaliser.canonicalise(tag)
        guard let canonical = parsed.canonical else {
            return EditedLanguageField(value: "und", limit: .notATag)
        }
        let form = languageFieldForm(for: container)
        if form == .fullTag { return EditedLanguageField(value: canonical, limit: .fits) }
        let codes = policy.iso6392.codes(for: canonical)
        let code = form == .bibliographic ? codes.b : codes.t
        if code == "und", canonical != "und" {
            return EditedLanguageField(value: code, limit: .noThreeLetterCode(canonical: canonical))
        }
        if let lost = partsBeyondLanguage(parsed) {
            return EditedLanguageField(value: code, limit: .losesParts(lost: lost, canonical: canonical))
        }
        return EditedLanguageField(value: code, limit: .fits)
    }

    /// What a three-letter field loses of `tag`: everything after the
    /// primary language (`GB` of `en-GB`, `Hant-TW` of `zh-Hant-TW`), or
    /// `nil` when there is nothing after it.
    static func partsBeyondLanguage(_ tag: LanguageTag) -> String? {
        guard tag.kind == .ordinary, let language = tag.language, tag.text.count > language.count else { return nil }
        return String(tag.text.dropFirst(language.count + 1))
    }

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
    /// change (COMPAT-030). Where the policy's preferred form cannot be
    /// written, what the source had is kept and the job's log says so.
    ///
    /// A stream the person did NOT edit:
    /// * a value the probe could not recognise (`english`, `xx-bogus`) is
    ///   left for ffmpeg to copy as it is, with a note — it used to be
    ///   overwritten with `und`, erasing it (COMPAT-040: report doubt);
    /// * in a free-text field (Ogg) the canonical tag is written;
    /// * in a three-letter field the policy's code is written when it is a
    ///   real code and nothing is lost (`deu` → `ger` in Matroska: a
    ///   correction), or when the source itself said "not known" (`und`);
    /// * a real language with NO three-letter code (`yue`, `cmn`, `nan`) is
    ///   left for ffmpeg to copy, with a note — the policy's form would be
    ///   `und`, which is what the first build wrote, erasing the language;
    /// * a tag with a region or script (`fr-CA`): Matroska is left to copy
    ///   the source's own text (which keeps it); MP4 and the rest can hold
    ///   only three letters, so the code is written (`fra`) with a note.
    /// A stream the person DID edit gets the policy's form of their tag,
    /// with a note when the field cannot hold all of it (`en-GB` → `eng`).
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
        container: ContainerFormat?,
        isReplacement: Bool,
        keepsSourceMetadata: Bool
    ) -> LanguageWrite {
        let stream = "Stream #\(streamNumber)"
        guard let policy else {
            if let edited { return LanguageWrite(value: edited, note: nil) }
            return LanguageWrite(value: keepsSourceMetadata ? sourceLanguage : nil, note: nil)
        }
        let form = languageFieldForm(for: container)

        // The code for an old three-letter field, in this container's form.
        func threeLetter(_ tag: String) -> String {
            let codes = policy.iso6392.codes(for: tag)
            return form == .bibliographic ? codes.b : codes.t
        }

        // --- An edit: the person asked for this language. ---
        if let edited, let field = editedLanguageField(edited, in: container) {
            switch field.limit {
            case .fits:
                return LanguageWrite(value: field.value, note: nil)
            case .notATag:
                return LanguageWrite(
                    value: field.value,
                    note: "\(stream): “\(edited)”, set in the stream editor, is not a language tag, "
                        + "so the language is written as “und” (not known)."
                )
            case .noThreeLetterCode(let canonical):
                return LanguageWrite(
                    value: field.value,
                    note: "\(stream): this file type can only store three-letter language codes, and "
                        + "“\(canonical)” has none, so the language is written as “und” (not known)."
                )
            case .losesParts(let lost, let canonical):
                return LanguageWrite(
                    value: field.value,
                    note: "\(stream): this file type can only store the language, so “\(lost)” in "
                        + "“\(canonical)” is not saved (written as “\(field.value)”)."
                )
            }
        }

        // --- No edit: keep what the source had. ---
        guard keepsSourceMetadata else { return LanguageWrite(value: nil, note: nil) }
        if let raw = sourceUnrecognised {
            return LanguageWrite(
                value: isReplacement ? raw : nil,
                note: "\(stream): the file's language “\(raw)” is not a language code; kept as the "
                    + "source had it. Set the right language in the stream editor if you know it."
            )
        }
        guard let source = sourceLanguage else { return LanguageWrite(value: nil, note: nil) }
        let tag = policy.canonicaliser.canonicalise(source)
        guard let canonical = tag.canonical else {
            // Not from the probe (it stores `und` plus the text); kept as is.
            return LanguageWrite(
                value: isReplacement ? source : nil,
                note: "\(stream): the language “\(source)” is not a language tag; kept as the source had it."
            )
        }
        if form == .fullTag { return LanguageWrite(value: canonical, note: nil) }
        let code = threeLetter(canonical)
        let lost = partsBeyondLanguage(tag)
        if code == "und", canonical != "und" {
            if lost == nil || keepsCopiedLanguageText(container) {
                // A well-formed tag whose language is not in the registry
                // (`xx-bogus`) is reported as that, so the person can fix it
                // (LANG-001 says such a tag SHOULD be reported).
                let registered = tag.language.map(policy.isRegisteredLanguage) ?? true
                return LanguageWrite(
                    value: isReplacement ? canonical : nil,
                    note: registered
                        ? "\(stream): language “\(canonical)” has no three-letter code; kept as the source had it."
                        : "\(stream): the file's language “\(canonical)” is not a registered language code; kept as "
                            + "the source had it. Set the right language in the stream editor if you know it."
                )
            }
            // MP4 and the rest keep only three letters, so neither the
            // source's text nor a code can be stored: say so plainly.
            return LanguageWrite(
                value: code,
                note: "\(stream): language “\(canonical)” has no three-letter code, and this file type can "
                    + "store nothing else, so it is written as “und” (not known)."
            )
        }
        if let lost {
            if keepsCopiedLanguageText(container) {
                return LanguageWrite(
                    value: isReplacement ? canonical : nil,
                    note: "\(stream): language “\(canonical)” cannot be written to this file type's three-letter "
                        + "language field without losing “\(lost)”; kept as the source had it."
                )
            }
            return LanguageWrite(
                value: code,
                note: "\(stream): this file type can only store the language, so “\(lost)” in "
                    + "“\(canonical)” is not saved (written as “\(code)”)."
            )
        }
        return LanguageWrite(value: code, note: nil)
    }

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
