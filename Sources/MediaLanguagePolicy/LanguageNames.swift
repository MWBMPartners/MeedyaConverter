// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / LanguageNames
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Job "localised names" of policy §9.
//
//   * UI-010 — a menu shows a language's name in the INTERFACE language:
//     `de` is "German" in an English interface, "allemand" in a French one,
//     with its qualifier for regional or script forms ("English (United
//     Kingdom)", "Chinese (Traditional)").
//   * NAME-010 — a name written INTO a file (a track title for simple
//     players) uses the language's own name, its autonym: "Deutsch",
//     "English", "Español", "日本語".
//
// Both come from the platform's own locale data (Foundation's `Locale`,
// backed by Unicode CLDR through ICU on Apple platforms and Linux alike) —
// never from a hand-typed list, which is what the old editor had.
//
// WHAT IT CANNOT DO
// -----------------
// A name is presentation, never identity (LANG-001, NAME-020): nothing here
// is ever read back as a language. The platform's names can differ between
// OS versions; that is fine for display and is why the conformance cases
// supply their own names instead of testing these. A tag the platform does
// not know gets `nil`, and callers fall back to showing the tag itself.
// ============================================================================

import Foundation

/// Language names from the platform's locale data.
public enum LanguageNames {

    /// The name of `tag` in the interface language `interfaceLocale` (UI-010),
    /// with its first letter capitalised for display at the start of a label.
    ///
    /// - Returns: The name, or `nil` if the platform has no name for it.
    public static func localizedName(of tag: String, in interfaceLocale: Locale) -> String? {
        guard let name = interfaceLocale.localizedString(forIdentifier: tag),
              !name.isEmpty, name != tag else {
            return nil
        }
        return capitalisingFirstLetter(name, locale: interfaceLocale)
    }

    /// The language's own name for `tag` — its autonym (NAME-010) — with its
    /// first letter capitalised, as a track title starts with a capital:
    /// "Deutsch", "Español (México)", "日本語".
    ///
    /// Special codes (`und`, `mul`, `mis`, `zxx`, `qaa`–`qtz`) have no
    /// autonym and give `nil`: a title must not pretend "Undetermined" is a
    /// language's name.
    public static func autonym(of tag: String) -> String? {
        let primary = tag.split(separator: "-").first.map { $0.lowercased() } ?? ""
        if ["und", "mul", "mis", "zxx"].contains(primary) { return nil }
        if primary.utf8.count == 3, primary >= "qaa", primary <= "qtz" { return nil }
        let own = Locale(identifier: tag)
        return localizedName(of: tag, in: own)
    }

    /// Capitalises only the first character, using `locale`'s case rules
    /// (so a Turkish `i` becomes `İ`). Scripts without case are unchanged.
    static func capitalisingFirstLetter(_ text: String, locale: Locale) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }
}

// MARK: - ISO6392Writer (TRACK-070)

/// The ISO 639-2 code to write into an old three-letter field (TRACK-070).
///
/// Which FORM a field needs is the container's business: Matroska's old
/// `Language` field takes the bibliographic form (`ger`), MP4/MOV's `mdhd`
/// field and ID3 the terminology form (`deu`). This only supplies both.
public struct ISO6392Writer: Sendable {

    /// The canonicaliser the tag is read with.
    public let canonicaliser: LanguageTagCanonicaliser

    public init(canonicaliser: LanguageTagCanonicaliser) {
        self.canonicaliser = canonicaliser
    }

    /// Both ISO 639-2 forms for `tag` (raw; canonicalised first):
    /// - the data file's entry for the tag's primary language, if any;
    /// - a primary language in the local-use range `qaa`–`qtz`: itself;
    /// - anything else — no ISO 639-2 code, `und`, a grandfathered,
    ///   private-use or malformed value: `und`.
    ///
    /// Converting down loses region and script — which is why a format's
    /// full-tag field must also be written wherever it exists.
    public func codes(for tag: String) -> ISO6392Codes {
        let canonical = canonicaliser.canonicalise(tag)
        guard canonical.kind == .ordinary, let language = canonical.language else {
            return .undetermined
        }
        if let codes = canonicaliser.data.iso6392Writing[language] {
            return codes
        }
        if canonicaliser.data.isLocalUse(language) {
            return ISO6392Codes(b: language, t: language)
        }
        return .undetermined
    }
}
