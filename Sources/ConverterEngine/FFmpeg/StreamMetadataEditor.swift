// ============================================================================
// MeedyaConverter — StreamMetadataEditor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import MediaLanguagePolicy

// MARK: - StreamMetadataEdit

/// A single metadata edit operation on a stream.
public struct StreamMetadataEdit: Codable, Sendable, Identifiable {
    public let id: UUID
    public var streamIndex: Int
    public var key: String
    public var value: String?

    public init(
        id: UUID = UUID(),
        streamIndex: Int,
        key: String,
        value: String? = nil
    ) {
        self.id = id
        self.streamIndex = streamIndex
        self.key = key
        self.value = value
    }
}

// MARK: - DispositionEdit

/// A disposition flag edit for a stream.
public struct DispositionEdit: Codable, Sendable {
    public var streamIndex: Int
    public var disposition: StreamDisposition

    public init(streamIndex: Int, disposition: StreamDisposition) {
        self.streamIndex = streamIndex
        self.disposition = disposition
    }
}

// MARK: - StreamDisposition

/// Standard FFmpeg stream disposition flags — the structured record of a
/// track's roles (language policy TRACK-010: roles are structured data, not
/// words in a title). ffmpeg maps them to Matroska's flags (FlagOriginal,
/// FlagCommentary, FlagHearingImpaired, FlagVisualImpaired,
/// FlagTextDescriptions …) and to MP4's `kind` boxes where those exist.
///
/// NOTHING A FILE SAYS IS DROPPED HERE. Besides the role flags a person can
/// change in the stream editor, this keeps `attached_pic` (cover art) and,
/// by name, every other flag ffprobe reports as set (`still_image`,
/// `timed_thumbnails`, `dependent`, `non_diegetic`, `metadata`,
/// `multilayer`, and any a later ffmpeg adds). `ffmpegValue` writes all of
/// them back. Until the second review round of the language policy work it
/// kept only the twelve role flags, so the `-disposition` the argument
/// builder wrote for every output stream CLEARED everything else: an M4A's
/// cover art came out of "Remux to MP4" as a plain, default video track
/// placed before the audio (policy COMPAT-030: keep valid metadata).
public struct StreamDisposition: Codable, Sendable, Equatable {
    public var isDefault: Bool
    public var isDub: Bool
    public var isOriginal: Bool
    public var isComment: Bool
    public var isLyrics: Bool
    public var isKaraoke: Bool
    public var isForced: Bool
    public var isHearingImpaired: Bool
    public var isVisualImpaired: Bool
    public var isCleanEffects: Bool
    public var isDescriptions: Bool
    /// ffmpeg's `captions` flag (closed captions — an SDH role, TRACK-010).
    /// Added with the language policy work; older saved data has none.
    public var isCaptions: Bool
    /// ffmpeg's `attached_pic`: this "video stream" is a picture attached to
    /// the file — an album's cover art, a film's poster — not a track.
    /// Matroska stores such a picture as an attachment and MP4 as the `covr`
    /// item; ffmpeg only treats it that way while the flag is set. Added in
    /// the second review round; older saved data has none.
    public var isAttachedPicture: Bool
    /// Every OTHER flag the file sets, by ffmpeg's own name (`still_image`,
    /// `timed_thumbnails`, `dependent`, `non_diegetic`, `metadata`,
    /// `multilayer`, and any a later ffmpeg adds) — carried through so a
    /// copy or conversion writes them back. Sorted and without duplicates,
    /// so the same flags always give the same command line. Nothing in the
    /// app lets a person change these. Older saved data has none.
    public private(set) var otherFlags: [String]

    public init(
        isDefault: Bool = false,
        isDub: Bool = false,
        isOriginal: Bool = false,
        isComment: Bool = false,
        isLyrics: Bool = false,
        isKaraoke: Bool = false,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isVisualImpaired: Bool = false,
        isCleanEffects: Bool = false,
        isDescriptions: Bool = false,
        isCaptions: Bool = false,
        isAttachedPicture: Bool = false,
        otherFlags: [String] = []
    ) {
        self.isDefault = isDefault
        self.isDub = isDub
        self.isOriginal = isOriginal
        self.isComment = isComment
        self.isLyrics = isLyrics
        self.isKaraoke = isKaraoke
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isVisualImpaired = isVisualImpaired
        self.isCleanEffects = isCleanEffects
        self.isDescriptions = isDescriptions
        self.isCaptions = isCaptions
        self.isAttachedPicture = isAttachedPicture
        self.otherFlags = Self.normalisedOtherFlags(otherFlags)
    }

    /// The names of the flags this type has a property for, in the order
    /// `ffmpegValue` writes them. Every other set flag goes to `otherFlags`.
    static let modelledFlagNames: [String] = [
        "default", "dub", "original", "comment", "lyrics", "karaoke", "forced",
        "hearing_impaired", "visual_impaired", "clean_effects", "descriptions",
        "captions", "attached_pic"
    ]

    /// `otherFlags` as stored: only names that look like ffmpeg's own flag
    /// names (lower-case letters, digits, underscores — so a hand-edited
    /// saved job cannot slip anything else into a `-disposition` value), none
    /// of the modelled ones, sorted, without duplicates.
    private static func normalisedOtherFlags(_ flags: [String]) -> [String] {
        let modelled = Set(modelledFlagNames)
        let valid = flags.filter { name in
            !name.isEmpty && !modelled.contains(name)
                && name.unicodeScalars.allSatisfy { scalar in
                    (0x61...0x7A).contains(scalar.value) || (0x30...0x39).contains(scalar.value) || scalar.value == 0x5F
                }
        }
        return Array(Set(valid)).sorted()
    }

    /// Reads ffprobe's per-stream `disposition` object (`"default": 1,
    /// "forced": 0, …`). A flag ffprobe did not report counts as off; a flag
    /// it reports as set that this type has no property for is kept by name
    /// in `otherFlags`.
    ///
    /// Until the language policy work the probe read only `default` and
    /// `forced`, so original, commentary, SDH, captions, audio description
    /// and text descriptions were dropped on every re-encode (TRACK-040).
    /// Until its second review round `attached_pic` and the rest were still
    /// dropped (see the type's comment).
    public init(ffprobe disposition: [String: Any]) {
        func flag(_ key: String) -> Bool { (disposition[key] as? Int) == 1 }
        self.init(
            isDefault: flag("default"),
            isDub: flag("dub"),
            isOriginal: flag("original"),
            isComment: flag("comment"),
            isLyrics: flag("lyrics"),
            isKaraoke: flag("karaoke"),
            isForced: flag("forced"),
            isHearingImpaired: flag("hearing_impaired"),
            isVisualImpaired: flag("visual_impaired"),
            isCleanEffects: flag("clean_effects"),
            isDescriptions: flag("descriptions"),
            isCaptions: flag("captions"),
            isAttachedPicture: flag("attached_pic"),
            otherFlags: disposition.keys.filter { flag($0) }
        )
    }

    /// Decodes saved data, treating any flag the data does not mention as
    /// off — so data saved before a flag existed (`isCaptions`,
    /// `isAttachedPicture`, `otherFlags`) still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) throws -> Bool { try container.decodeIfPresent(Bool.self, forKey: key) ?? false }
        self.init(
            isDefault: try flag(.isDefault),
            isDub: try flag(.isDub),
            isOriginal: try flag(.isOriginal),
            isComment: try flag(.isComment),
            isLyrics: try flag(.isLyrics),
            isKaraoke: try flag(.isKaraoke),
            isForced: try flag(.isForced),
            isHearingImpaired: try flag(.isHearingImpaired),
            isVisualImpaired: try flag(.isVisualImpaired),
            isCleanEffects: try flag(.isCleanEffects),
            isDescriptions: try flag(.isDescriptions),
            isCaptions: try flag(.isCaptions),
            isAttachedPicture: try flag(.isAttachedPicture),
            otherFlags: try container.decodeIfPresent([String].self, forKey: .otherFlags) ?? []
        )
    }

    /// FFmpeg disposition string (e.g., "default+forced") — EVERY flag this
    /// holds, the modelled ones in a fixed order and then `otherFlags`, or
    /// "0" when there are none. Writing it for an output stream therefore
    /// gives that stream exactly these flags and clears the rest.
    public var ffmpegValue: String {
        var flags: [String] = []
        if isDefault { flags.append("default") }
        if isDub { flags.append("dub") }
        if isOriginal { flags.append("original") }
        if isComment { flags.append("comment") }
        if isLyrics { flags.append("lyrics") }
        if isKaraoke { flags.append("karaoke") }
        if isForced { flags.append("forced") }
        if isHearingImpaired { flags.append("hearing_impaired") }
        if isVisualImpaired { flags.append("visual_impaired") }
        if isCleanEffects { flags.append("clean_effects") }
        if isDescriptions { flags.append("descriptions") }
        if isCaptions { flags.append("captions") }
        if isAttachedPicture { flags.append("attached_pic") }
        flags += otherFlags
        return flags.isEmpty ? "0" : flags.joined(separator: "+")
    }

    /// Parse from FFmpeg disposition string (`default+forced`, or `0`).
    ///
    /// Splits on `+` and matches whole names. It used to test whether the
    /// whole string CONTAINED each name, which is only safe while no flag's
    /// name is part of another's; unknown names now go to `otherFlags`.
    public static func parse(_ value: String) -> StreamDisposition {
        let names = Set(value.lowercased().split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        })
        return StreamDisposition(
            isDefault: names.contains("default"),
            isDub: names.contains("dub"),
            isOriginal: names.contains("original"),
            isComment: names.contains("comment"),
            isLyrics: names.contains("lyrics"),
            isKaraoke: names.contains("karaoke"),
            isForced: names.contains("forced"),
            isHearingImpaired: names.contains("hearing_impaired"),
            isVisualImpaired: names.contains("visual_impaired"),
            isCleanEffects: names.contains("clean_effects"),
            isDescriptions: names.contains("descriptions"),
            isCaptions: names.contains("captions"),
            isAttachedPicture: names.contains("attached_pic"),
            otherFlags: names.filter { $0 != "0" }.map { $0 }
        )
    }

    /// These flags as a person changed them, with the flags a person CANNOT
    /// change taken from `source` — the file's own flags.
    ///
    /// The stream editor shows role toggles only; it has no switch for
    /// `attached_pic` or `otherFlags`. A saved edit carries whatever those
    /// were when the editor opened, so the file's CURRENT flags (a fresh
    /// probe) are the authority for them. That is what "the source's flags
    /// with only the person's edits applied" means in practice. With no
    /// `source` (data saved before flags were kept), the edit stands as is.
    public func keepingUneditableFlags(of source: StreamDisposition?) -> StreamDisposition {
        guard let source else { return self }
        var result = self
        result.isAttachedPicture = source.isAttachedPicture
        result.otherFlags = source.otherFlags
        return result
    }
}

// MARK: - StreamMetadataEditSet

/// A collection of metadata edits to apply during encoding.
public struct StreamMetadataEditSet: Codable, Sendable {
    /// Global (file-level) metadata edits.
    public var globalEdits: [String: String?]

    /// Per-stream metadata edits.
    public var streamEdits: [StreamMetadataEdit]

    /// Per-stream disposition edits.
    public var dispositionEdits: [DispositionEdit]

    public init(
        globalEdits: [String: String?] = [:],
        streamEdits: [StreamMetadataEdit] = [],
        dispositionEdits: [DispositionEdit] = []
    ) {
        self.globalEdits = globalEdits
        self.streamEdits = streamEdits
        self.dispositionEdits = dispositionEdits
    }

    /// Whether any edits are pending.
    public var hasEdits: Bool {
        !globalEdits.isEmpty || !streamEdits.isEmpty || !dispositionEdits.isEmpty
    }
}

// MARK: - StreamMetadataEditor

/// Builds FFmpeg arguments for editing stream and file-level metadata.
///
/// Enables per-stream title, language, and disposition editing during
/// transcoding or remuxing. Supports both setting and clearing metadata fields.
///
/// Phase 3.6
public struct StreamMetadataEditor: Sendable {

    /// Common metadata keys for streams.
    public enum CommonKey: String, CaseIterable, Sendable {
        case title = "title"
        case language = "language"
        case handler = "handler_name"
        case encoder = "encoder"
        case comment = "comment"
        case artist = "artist"
        case album = "album"
        case genre = "genre"
        case date = "date"
        case track = "track"
        case copyright = "copyright"
    }

    // MARK: - Argument Building

    /// Build FFmpeg arguments from a metadata edit set.
    ///
    /// - Parameter editSet: The collection of edits to apply.
    /// - Returns: FFmpeg argument array.
    public static func buildArguments(
        from editSet: StreamMetadataEditSet
    ) -> [String] {
        var args: [String] = []

        // Global metadata edits
        for (key, value) in editSet.globalEdits.sorted(by: { $0.key < $1.key }) {
            if let val = value {
                args += ["-metadata", "\(key)=\(val)"]
            } else {
                // Setting to empty string clears the key
                args += ["-metadata", "\(key)="]
            }
        }

        // Per-stream metadata edits
        for edit in editSet.streamEdits {
            if let value = edit.value {
                args += ["-metadata:s:\(edit.streamIndex)", "\(edit.key)=\(value)"]
            } else {
                args += ["-metadata:s:\(edit.streamIndex)", "\(edit.key)="]
            }
        }

        // Disposition edits
        for edit in editSet.dispositionEdits {
            args += ["-disposition:\(edit.streamIndex)", edit.disposition.ffmpegValue]
        }

        return args
    }

    /// Build FFmpeg arguments to set a stream's title.
    ///
    /// - Parameters:
    ///   - streamIndex: Stream index.
    ///   - title: New title (nil to clear).
    /// - Returns: FFmpeg argument array.
    public static func buildSetTitle(
        streamIndex: Int,
        title: String?
    ) -> [String] {
        return ["-metadata:s:\(streamIndex)", "title=\(title ?? "")"]
    }

    /// Build FFmpeg arguments to set a stream's language.
    ///
    /// - Parameters:
    ///   - streamIndex: Stream index.
    ///   - language: BCP 47 / ISO 639 language code (e.g., "eng", "fra", "deu").
    /// - Returns: FFmpeg argument array.
    public static func buildSetLanguage(
        streamIndex: Int,
        language: String
    ) -> [String] {
        return ["-metadata:s:\(streamIndex)", "language=\(language)"]
    }

    /// Build FFmpeg arguments to set stream disposition.
    ///
    /// - Parameters:
    ///   - streamIndex: Stream index.
    ///   - disposition: Disposition flags.
    /// - Returns: FFmpeg argument array.
    public static func buildSetDisposition(
        streamIndex: Int,
        disposition: StreamDisposition
    ) -> [String] {
        return ["-disposition:\(streamIndex)", disposition.ffmpegValue]
    }

    /// Build FFmpeg arguments to set the global title.
    ///
    /// - Parameter title: File title (nil to clear).
    /// - Returns: FFmpeg argument array.
    public static func buildSetGlobalTitle(
        title: String?
    ) -> [String] {
        return ["-metadata", "title=\(title ?? "")"]
    }

    /// Build FFmpeg arguments for a remux-only metadata edit (no re-encoding).
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output file.
    ///   - editSet: Metadata edits to apply.
    /// - Returns: Complete FFmpeg argument array.
    public static func buildRemuxEditArguments(
        inputPath: String,
        outputPath: String,
        editSet: StreamMetadataEditSet
    ) -> [String] {
        var args = [
            "-i", inputPath,
            "-map", "0",
            "-c", "copy",
        ]

        args += buildArguments(from: editSet)

        args += ["-y", outputPath]
        return args
    }

    // MARK: - Language Codes
    //
    // Languages follow the shared language policy (MWBM-MEDIA-LANG,
    // docs/standards/media-language-bcp47-policy.md): a language is a
    // canonical BCP 47 TAG (`en`, `en-GB`, `zh-Hant`, `es-419`), never a name.
    // This used to be a hand-typed list of 21 three-letter codes labelled
    // "ISO 639-2/B" (they were actually the /T forms) with English names, and
    // a check that accepted only two or three letters — so `en-GB`,
    // `zh-Hant` and `es-419` were refused. Names now come from the platform
    // (UI-010), never from a typed list.

    /// Languages offered as quick picks in the stream editor, as canonical
    /// BCP 47 tags (the same set the old list had, `und` included, plus the
    /// two Chinese scripts). Shown with names in the interface language and in
    /// menu order — see `orderedLanguageSuggestions(interfaceLocale:preferences:)`.
    public static let commonLanguageTags: [String] = [
        "ar", "da", "de", "en", "es", "fi", "fr", "hi", "it", "ja", "ko", "nl",
        "no", "pl", "pt", "ru", "sv", "th", "tr", "vi", "zh", "zh-Hans", "zh-Hant", "und"
    ]

    /// Whether `code` is something the stream editor accepts as a language:
    /// a BCP 47 tag or an old three-letter code, read the way a value from a
    /// file is read (LANG-002) — `en`, `en-GB`, `zh-Hant`, `es-419`, `eng` —
    /// rather than a name such as `English`, digits or stray punctuation.
    public static func isValidLanguageCode(_ code: String) -> Bool {
        if case .valid = checkLanguageEntry(code) { return true }
        return false
    }

    /// What a person typed into a language field, checked by the policy.
    public enum LanguageEntryCheck: Sendable, Equatable {
        /// Nothing typed: the language is "not set", so nothing is written
        /// and the file's own value is kept.
        case empty
        /// A language, as the canonical tag that will be saved (`eng` →
        /// `en`, `EN-gb` → `en-GB`), with an optional plain-English note
        /// worth showing (how it was read; an unregistered code).
        case valid(tag: String, note: String?)
        /// Not a language; `message` says so in plain English, with
        /// examples. The editor's Apply stays off until it is fixed.
        case invalid(message: String)
    }

    /// Checks what a person typed into a stream's language field.
    ///
    /// Read with the SAME reader as a value found in a file (LANG-002), so
    /// the old three-letter codes people know work as they expect: `eng` is
    /// saved as `en`, `fre` as `fr`, `ger` as `de`. The first build checked
    /// it as a new tag only (LANG-001), so `eng` was kept as the tag `eng`
    /// — which has no ISO 639-2 entry as a TAG, so the file got `und` while
    /// the automatic title said "English" (found in the independent review).
    /// Now the saved tag, the written field and the title all come from the
    /// one reading. Anything the reader cannot read is refused, never
    /// guessed (COMPAT-040). A well-formed tag whose language is not in the
    /// registry (`xx`) is accepted with a note (LANG-001: report it).
    public static func checkLanguageEntry(_ text: String) -> LanguageEntryCheck {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        guard let policy = TrackLanguage.policy else {
            // Without the policy's data nothing can be checked: accept what
            // was typed, and say so.
            return .valid(tag: trimmed, note: "Language data unavailable — not checked.")
        }
        guard let tag = policy.reader.read(trimmed) else {
            return .invalid(
                message: "“\(trimmed)” is not a language code. Type a code such as en, pt-BR or zh-Hant, "
                    + "or und if the language is not known."
            )
        }
        var notes: [String] = []
        if tag.lowercased() != trimmed.lowercased() {
            notes.append("“\(trimmed)” is saved as “\(tag)”.")
        }
        if let language = tag.split(separator: "-").first.map(String.init),
           policy.canonicaliser.canonicalise(tag).kind == .ordinary,
           !policy.isRegisteredLanguage(language) {
            notes.append("“\(language)” is not a registered language code.")
        }
        return .valid(tag: tag, note: notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    /// What `container`'s language field will NOT keep of `tag`, in plain
    /// English for the stream editor to show before Apply, or `nil` when it
    /// keeps all of it. Old three-letter fields (Matroska, MP4 …) hold only
    /// the language: "This file type can only store the language, so “GB”
    /// will not be saved." — and that is what `und-GB` gets too (the round-2
    /// build said `und-GB` "has no three-letter code"; it is the REGION that
    /// cannot be stored). MOV stores only the languages on its old QuickTime
    /// list, and some file types store no language at all. The same answer
    /// as the job's log gives (`TrackLanguage.editedLanguageField`, which
    /// reads the one table of what each file type stores).
    public static func storageNote(for tag: String, in container: ContainerFormat?) -> String? {
        guard let field = TrackLanguage.editedLanguageField(tag, in: container) else { return nil }
        switch field.limit {
        case .fits, .notATag:
            return nil
        case .noThreeLetterCode(let canonical):
            return "This file type can only store language codes from the older three-letter list (ISO 639-2), "
                + "and “\(canonical)” is not on it, so it will be saved as “und” (not known)."
        case .losesParts(let lost, _):
            let words = TrackLanguage.onlyStoresWords(TrackLanguage.languageFieldStorage(for: container))
            return words.prefix(1).uppercased() + words.dropFirst() + ", so “\(lost)” will not be saved."
        case .cannotStore(let canonical):
            // "The track will have no language" — not "no language will be
            // saved", which reads as though the track's OLD language stays.
            // And it is true: the command clears the field rather than let
            // ffmpeg copy the source's language in (the third independent
            // review found an edit to `sv` leaving `eng` in a MOV file).
            if TrackLanguage.languageFieldStorage(for: container) == .nothing {
                return "This file type has no place for a track's language, so the track will have no language."
            }
            // The same words as the job's note (`TrackLanguage.quickTimeWords`):
            // "…and “yue” is not on it", or why a language the list has in
            // some form still cannot be stored (`zh` — the list's `chi` is
            // Traditional Chinese to Apple's players; `sv` — its label `sve`
            // is not a language code).
            let words = TrackLanguage.quickTimeWords(for: canonical)
            return words.prefix(1).uppercased() + words.dropFirst() + ", so the track will have no language."
        }
    }

    /// `commonLanguageTags` in MENU order (policy Part B, UI-020 to UI-040):
    /// the person's own languages first (`preferences`, e.g.
    /// `Locale.preferredLanguages`), then the rest alphabetically by name in
    /// the interface language, sorted by that language's rules; special
    /// codes such as `und` last. Without the policy's data, the list as is.
    public static func orderedLanguageSuggestions(interfaceLocale: Locale, preferences: [String]) -> [String] {
        guard let policy = TrackLanguage.policy else { return commonLanguageTags }
        let items = commonLanguageTags.map { PresentationItem(tag: $0) }
        return policy.presentationOrder.order(
            items,
            // Accepts both `en-GB` and the operating system's `en_GB` shape (LANG-004).
            preferences: preferences.map { policy.posixLocales.convert($0) ?? $0 },
            collation: .localizedNames(in: interfaceLocale)
        ).map { commonLanguageTags[$0] }
    }
}
