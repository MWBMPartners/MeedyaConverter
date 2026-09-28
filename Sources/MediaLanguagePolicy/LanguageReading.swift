// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / LanguageReading
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Reading a language value that came from somewhere else — a file, a tag,
// another program, the operating system — into a canonical tag.
//
//   * LANG-002 (`LegacyLanguageReader`): EVERY language value read from a
//     file, a tag or another system goes through this, not straight into
//     canonicalisation, because containers and tools store old three-letter
//     ISO 639-2 codes (`eng`, `ger`, `fre`), sometimes padded with nulls or
//     in Matroska's old `fre-ca` form. ffprobe's `language` tag is one such
//     value.
//   * LANG-004 (`POSIXLocaleConverter`): locale names such as `en_US.UTF-8`.
//
// An unrecognised value is NEVER turned into a guessed language (LANG-002,
// COMPAT-040): the reading says "unrecognised", the structured value is
// `und`, and the original text is kept so a person can fix it.
// ============================================================================

import Foundation

// MARK: - LanguageReading

/// The result of reading a language value from a file or another system.
public enum LanguageReading: Sendable, Hashable {
    /// A canonical BCP 47 tag.
    case tag(String)
    /// Not a language this policy can recognise. The structured value is
    /// `und`; `raw` is the text as found, kept so nothing is lost.
    case unrecognised(raw: String)

    /// The tag to store: the canonical tag, or `und` when unrecognised.
    public var tagOrUndetermined: String {
        switch self {
        case .tag(let tag): return tag
        case .unrecognised: return "und"
        }
    }

    /// The original text when the value was unrecognised, else `nil`.
    public var unrecognisedText: String? {
        if case .unrecognised(let raw) = self { return raw }
        return nil
    }
}

// MARK: - LegacyLanguageReader (LANG-002)

/// Reads a language value from a file, a tag or another system (LANG-002).
public struct LegacyLanguageReader: Sendable {

    /// The canonicaliser (and through it the registry data) this reader uses.
    public let canonicaliser: LanguageTagCanonicaliser

    public init(canonicaliser: LanguageTagCanonicaliser) {
        self.canonicaliser = canonicaliser
    }

    /// Reads `raw`, returning the canonical tag or `nil` when unrecognised —
    /// the exact shape the conformance cases use (`legacy_three_letter`).
    /// Most callers want `reading(_:)`, which keeps the raw text.
    public func read(_ raw: String) -> String? {
        let value = Self.prepare(raw)
        return readPrepared(value)
    }

    /// Reads `raw`, keeping the original text when it is unrecognised.
    public func reading(_ raw: String) -> LanguageReading {
        if let tag = read(raw) {
            return .tag(tag)
        }
        return .unrecognised(raw: raw)
    }

    /// Before the steps: strip trailing U+0000 (fixed-width fields are padded
    /// with them) and the four whitespace characters; if a U+0000 is still
    /// inside, the field holds several null-separated values (ID3v2.4), and
    /// the first is the primary language.
    static func prepare(_ raw: String) -> String {
        var scalars = Substring(raw).unicodeScalars
        while let last = scalars.last, last == "\u{0}" {
            scalars.removeLast()
        }
        var value = LanguageTagCanonicaliser.trimPolicyWhitespace(String(scalars))
        if let nul = value.unicodeScalars.firstIndex(of: "\u{0}") {
            value = LanguageTagCanonicaliser.trimPolicyWhitespace(String(value.unicodeScalars[..<nul]))
        }
        return value
    }

    /// The four steps of LANG-002 on an already-prepared value.
    private func readPrepared(_ value: String) -> String? {
        let data = canonicaliser.data

        // Step 1: ID3's own "language not known" marker, in any case.
        if value.utf8.count == 3, value.uppercased() == "XXX" {
            return "und"
        }

        // Step 3: three letters, a hyphen and two letters — Matroska's old
        // country form (`fre-ca`) — but ONLY when the three letters are not
        // themselves a registered language subtag. `und-GB` and `yue-HK` are
        // ordinary tags and fall to step 4, so nothing they say is lost.
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2,
           parts[0].utf8.count == 3, LanguageTagCanonicaliser.isAllLetters(parts[0]),
           parts[1].utf8.count == 2, LanguageTagCanonicaliser.isAllLetters(parts[1]),
           !data.languages.contains(parts[0].lowercased()) {
            guard let base = readPrepared(parts[0]), base != "und" else { return nil }
            return canonicaliser.canonicalise("\(base)-\(parts[1])").canonical
        }

        // Step 2: exactly three ASCII letters.
        if value.utf8.count == 3, LanguageTagCanonicaliser.isAllLetters(value) {
            let code = value.lowercased()
            if let language = data.iso6392Reading[code] {
                return language
            }
            if data.isRegisteredLanguage(code) {
                return canonicaliser.canonicalise(code).canonical
            }
            return nil
        }

        // Step 4: anything else is canonicalised as a tag; malformed means
        // unrecognised.
        return canonicaliser.canonicalise(value).canonical
    }
}

// MARK: - POSIXLocaleConverter (LANG-004)

/// Converts an operating-system locale name (`en_US.UTF-8`, `sr_RS@latin`)
/// into a canonical tag (LANG-004).
public struct POSIXLocaleConverter: Sendable {

    /// The canonicaliser used for the final step.
    public let canonicaliser: LanguageTagCanonicaliser

    public init(canonicaliser: LanguageTagCanonicaliser) {
        self.canonicaliser = canonicaliser
    }

    /// The result of a conversion.
    public struct Conversion: Sendable, Hashable {
        /// The canonical tag, or `nil` when the locale names no language
        /// (`C`, `POSIX`) or cannot be converted.
        public let tag: String?
        /// A modifier other than `@latin` / `@cyrillic`, which was dropped
        /// and SHOULD be reported. `nil` when there was none.
        public let droppedModifier: String?
    }

    /// Converts `raw`, returning just the tag (the conformance cases' shape).
    public func convert(_ raw: String) -> String? {
        conversion(raw).tag
    }

    /// Converts `raw`, also reporting a dropped modifier.
    public func conversion(_ raw: String) -> Conversion {
        // Trim ONLY LANG-001 step 1's four characters (space, tab, line
        // feed, carriage return). Foundation's `.whitespacesAndNewlines`,
        // used here before core revision 6, also removes a no-break space
        // (U+00A0) and other Unicode spaces, so ` en_US` (a leading
        // no-break space) became `en-US` instead of staying malformed
        // (policy case posix-11).
        var value = LanguageTagCanonicaliser.trimPolicyWhitespace(raw)
        // 1. `C` and `POSIX` mean "no language".
        if value.isEmpty || value == "C" || value == "POSIX" {
            return Conversion(tag: nil, droppedModifier: nil)
        }
        // 2. Split off `@modifier`, then drop `.charset`.
        var modifier: String?
        if let at = value.firstIndex(of: "@") {
            modifier = String(value[value.index(after: at)...])
            value = String(value[..<at])
        }
        if let dot = value.firstIndex(of: ".") {
            value = String(value[..<dot])
        }
        // 3. Underscores become hyphens.
        value = value.replacingOccurrences(of: "_", with: "-")
        // 4. `@latin` / `@cyrillic` become a script after the language; any
        //    other modifier is dropped (and reported).
        var dropped: String?
        if let modifier {
            let script: String? = modifier == "latin" ? "Latn" : (modifier == "cyrillic" ? "Cyrl" : nil)
            if let script {
                var parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                parts.insert(script, at: min(1, parts.count))
                value = parts.joined(separator: "-")
            } else {
                dropped = modifier
            }
        }
        // 5. Canonicalise.
        return Conversion(tag: canonicaliser.canonicalise(value).canonical, droppedModifier: dropped)
    }
}
