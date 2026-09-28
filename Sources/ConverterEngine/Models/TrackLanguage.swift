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
// values are kept exactly as the file gives them, and a warning is printed
// once. The release workflows fail the build before that can ship.
// ============================================================================

import Foundation
import MediaLanguagePolicy

/// Connects the engine to the language policy.
public enum TrackLanguage {

    /// The policy on its bundled data, or `nil` if the data is missing (see
    /// the file header). Loaded once; the warning is printed once.
    public static let policy: MediaLanguagePolicy? = {
        switch MediaLanguagePolicy.shared {
        case .success(let policy):
            return policy
        case .failure(let error):
            print("Warning: \(error) Track languages are kept exactly as each file gives them.")
            return nil
        }
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

    /// The value to give ffmpeg's `language` metadata for a track in
    /// `tag`'s language, in `container` (TRACK-070): the old three-letter
    /// code in the form the container needs (a language with no ISO 639-2
    /// code, `und`, or a malformed value → `und`), or the canonical tag for a
    /// free-text field.
    ///
    /// Without the policy's data the tag is returned as given (nothing is
    /// guessed; see the file header).
    public static func containerValue(for tag: String, in container: ContainerFormat?) -> String {
        guard let policy else { return tag }
        switch languageFieldForm(for: container) {
        case .bibliographic: return policy.iso6392.codes(for: tag).b
        case .terminology: return policy.iso6392.codes(for: tag).t
        case .fullTag: return policy.canonicaliser.canonicalise(tag).canonical ?? "und"
        }
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
