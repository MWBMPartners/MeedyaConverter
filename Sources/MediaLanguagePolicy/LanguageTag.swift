// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / LanguageTag
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Job 1 of policy §9: tag parsing and canonical form (LANG-001, LANG-026).
//
// A language is identified by a canonical BCP 47 tag, never by a name. This
// file turns any text that claims to be a tag into one of four things:
//
//   * ordinary      — a normal tag, in canonical form (`en-GB`, `zh-Hant-TW`);
//   * grandfathered — a registry grandfathered tag with no replacement,
//                     kept exactly as the registry spells it (`i-default`);
//   * private use   — a tag that is private use from the start (`x-foo`);
//   * malformed     — not a well-formed tag. Its text is KEPT (LANG-026):
//                     it is reported and sorted last, never dropped or
//                     "repaired" into a guess.
//
// The steps follow the policy's LANG-001 exactly, in its order. The throwaway
// Python reference that the conformance cases were cross-checked against
// does the same; where this file looks longer than it needs to be, it is
// usually spelling out a step the policy numbers separately.
// ============================================================================

import Foundation

// MARK: - LanguageTagKind

/// Which of the four kinds of value a canonicalised tag is.
public enum LanguageTagKind: String, Sendable, Hashable, Codable {
    case ordinary
    case grandfathered
    case privateUse = "privateuse"
    case malformed
}

// MARK: - LanguageTag

/// A language tag after canonicalisation (LANG-001).
///
/// The subtag fields are filled only for `ordinary` tags (and `privateUse`
/// for private-use tags); they are already in canonical case.
public struct LanguageTag: Sendable, Hashable {

    /// What kind of value this is.
    public let kind: LanguageTagKind

    /// The canonical tag text — or, for a malformed value, the value as given
    /// with the four whitespace characters trimmed (LANG-026 keeps it).
    public let text: String

    /// The primary language subtag, lower case (`zh` in `zh-Hant-TW`).
    public let language: String?

    /// An extlang the registry does not list (a listed one is replaced).
    public let extlang: String?

    /// Script, title case (`Hant`).
    public let script: String?

    /// Region: two letters upper case (`GB`) or three digits (`419`).
    public let region: String?

    /// Variants, lower case, in written order.
    public let variants: [String]

    /// Extensions: each is its singleton followed by its subtags, lower case,
    /// ordered by singleton.
    public let extensions: [[String]]

    /// Private-use subtags after `x`, lower case.
    public let privateUse: [String]

    /// The canonical tag, or `nil` for a malformed value.
    public var canonical: String? { kind == .malformed ? nil : text }

    /// Whether the value is not a well-formed tag.
    public var isMalformed: Bool { kind == .malformed }

    init(
        kind: LanguageTagKind,
        text: String,
        language: String? = nil,
        extlang: String? = nil,
        script: String? = nil,
        region: String? = nil,
        variants: [String] = [],
        extensions: [[String]] = [],
        privateUse: [String] = []
    ) {
        self.kind = kind
        self.text = text
        self.language = language
        self.extlang = extlang
        self.script = script
        self.region = region
        self.variants = variants
        self.extensions = extensions
        self.privateUse = privateUse
    }

    /// The tag's hyphen-separated parts in lower case — what matching counts
    /// (MATCH-020/030 distance counts every part, single letters included).
    var lowerCasedParts: [String] {
        text.lowercased().split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    }
}

// MARK: - Canonicalisation

/// Turns text into a canonical `LanguageTag` (LANG-001).
public struct LanguageTagCanonicaliser: Sendable {

    /// The registry data the replacements come from.
    public let data: LanguageReferenceData

    public init(data: LanguageReferenceData) {
        self.data = data
    }

    /// Canonicalises `raw` — a value already known to be meant as a BCP 47
    /// tag, such as one a person types into a tag field. A value read from a
    /// file or another system goes through `LegacyLanguageReader` instead
    /// (LANG-002), because those often hold old three-letter codes.
    public func canonicalise(_ raw: String) -> LanguageTag {
        // Step 1: trim ONLY space, tab, line feed and carriage return. A
        // no-break space (or anything else) is part of the value and makes it
        // malformed — trimming more would let two implementations disagree.
        let trimmed = Self.trimPolicyWhitespace(raw)
        guard !trimmed.isEmpty else {
            return LanguageTag(kind: .malformed, text: raw)
        }
        let lower = trimmed.lowercased()

        // Step 2: a whole grandfathered tag — its replacement (then carry on
        // with that), or the registry's own spelling, never split.
        if let entry = data.grandfathered[lower] {
            if let preferred = entry.preferred {
                return canonicalise(preferred)
            }
            return LanguageTag(kind: .grandfathered, text: entry.tag)
        }

        // Step 3: well-formedness. A value that fails is malformed.
        guard var parsed = Self.parseWellFormed(trimmed, data: data) else {
            return LanguageTag(kind: .malformed, text: trimmed)
        }
        guard let language = parsed.language else {
            // Private use from the start (`x-…`).
            return LanguageTag(kind: .privateUse, text: parsed.joined(), privateUse: parsed.privateUse)
        }

        // Step 4: a whole redundant tag with a replacement.
        if let replacement = data.redundantPreferred[parsed.joined().lowercased()] {
            return canonicalise(replacement)
        }

        // Step 5: Preferred-Value replacements. A REGISTERED extlang replaces
        // the language before it, and what it leaves is itself checked for a
        // replacement (`ar-ajp` → `ajp` → `apc`). An unregistered extlang is
        // kept where it is (`zh-abc`).
        var newLanguage = language
        if let extlang = parsed.extlang, let replacement = data.preferredExtlang[extlang] {
            newLanguage = replacement
            parsed.extlang = nil
        }
        parsed.language = data.preferredLanguage[newLanguage] ?? newLanguage
        if let script = parsed.script {
            parsed.script = data.preferredScript[script] ?? script
        }
        if let region = parsed.region {
            parsed.region = data.preferredRegion[region] ?? region
        }
        // A replacement can leave the same variant twice
        // (`hepburn-heploc-alalc97` → `hepburn-alalc97-alalc97`): the later
        // one is dropped, so the result is well formed and stable.
        var seenVariants = Set<String>()
        parsed.variants = parsed.variants
            .map { data.preferredVariant[$0] ?? $0 }
            .filter { seenVariants.insert($0).inserted }

        // Step 6: extensions in order of their singleton, each keeping its
        // own subtags in written order (a stable sort).
        parsed.extensions = Self.stableSorted(parsed.extensions) { $0[0] < $1[0] }

        // Step 7 (case) was applied while parsing.
        let result = parsed.joined()

        // Canonical form is stable (revision 2): steps 4 and 5 repeat until
        // the tag stops changing, because a replacement can create a
        // redundant or grandfathered tag (`sgn-DD` → `sgn-DE` → `gsg`).
        let resultLower = result.lowercased()
        if resultLower != lower,
           data.redundantPreferred[resultLower] != nil || data.grandfathered[resultLower] != nil {
            return canonicalise(result)
        }

        return LanguageTag(
            kind: .ordinary,
            text: result,
            language: parsed.language,
            extlang: parsed.extlang,
            script: parsed.script,
            region: parsed.region,
            variants: parsed.variants,
            extensions: parsed.extensions,
            privateUse: parsed.privateUse
        )
    }

    // MARK: Helpers shared with the other jobs

    /// LANG-001 step 1's trim: U+0020, U+0009, U+000A, U+000D and nothing else.
    static func trimPolicyWhitespace(_ value: String) -> String {
        let scalars = value.unicodeScalars
        func isPolicySpace(_ s: Unicode.Scalar) -> Bool {
            s == " " || s == "\t" || s == "\n" || s == "\r"
        }
        guard let first = scalars.firstIndex(where: { !isPolicySpace($0) }),
              let last = scalars.lastIndex(where: { !isPolicySpace($0) }) else {
            return ""
        }
        return String(scalars[first...last])
    }

    /// A stable sort (Swift's `sorted` makes no stability promise, and the
    /// policy's LANG-027 needs one everywhere).
    static func stableSorted<T>(_ items: [T], by areInIncreasingOrder: (T, T) -> Bool) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    // MARK: Parsing (LANG-001 step 3)

    /// The parts of a well-formed tag, already in canonical case.
    struct ParsedTag {
        var language: String?
        var extlang: String?
        var script: String?
        var region: String?
        var variants: [String] = []
        var extensions: [[String]] = []
        var privateUse: [String] = []

        /// The parts joined with hyphens, in RFC 5646 order.
        func joined() -> String {
            var out: [String] = []
            if let language { out.append(language) }
            if let extlang { out.append(extlang) }
            if let script { out.append(script) }
            if let region { out.append(region) }
            out += variants
            for ext in extensions { out += ext }
            if !privateUse.isEmpty { out += ["x"] + privateUse }
            return out.joined(separator: "-")
        }
    }

    /// Checks `value` against RFC 5646's grammar as the policy narrows it
    /// (LANG-001 step 3) and returns its parts, or `nil` if it is malformed.
    ///
    /// Narrowings the policy states: at most one extlang (no valid tag has
    /// more); the same variant or extension singleton twice is malformed; a
    /// primary language of four to eight letters counts only if the registry
    /// lists it (none does today), so a NAME such as `English` is malformed.
    static func parseWellFormed(_ value: String, data: LanguageReferenceData) -> ParsedTag? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        // Every part: 1–8 ASCII letters or digits. (Underscores, spaces and
        // non-ASCII letters all fail here.)
        guard parts.allSatisfy({ (1...8).contains($0.utf8.count) && $0.utf8.allSatisfy(isASCIIAlphanumeric) }) else {
            return nil
        }
        let lower = parts.map { $0.lowercased() }
        var result = ParsedTag()
        var index = 0

        // Private use from the start: `x-` and at least one subtag.
        if lower[0] == "x" {
            guard lower.count >= 2 else { return nil }
            result.privateUse = Array(lower[1...])
            return result
        }

        // Primary language: 2–8 letters; 4–8 only if registered.
        guard isAllLetters(lower[0]), (2...8).contains(lower[0].utf8.count) else { return nil }
        if lower[0].utf8.count >= 4, !data.languages.contains(lower[0]) { return nil }
        result.language = lower[0]
        index = 1

        // At most one extlang (three letters), only after a 2–3 letter language.
        if lower[0].utf8.count <= 3 {
            var count = 0
            while index < lower.count, lower[index].utf8.count == 3, isAllLetters(lower[index]) {
                count += 1
                if count > 1 { return nil }
                result.extlang = lower[index]
                index += 1
            }
        }

        // Script: four letters, title case.
        if index < lower.count, lower[index].utf8.count == 4, isAllLetters(lower[index]) {
            result.script = lower[index].prefix(1).uppercased() + lower[index].dropFirst()
            index += 1
        }

        // Region: two letters (upper case) or three digits (unchanged).
        if index < lower.count {
            let part = lower[index]
            if part.utf8.count == 2, isAllLetters(part) {
                result.region = part.uppercased()
                index += 1
            } else if part.utf8.count == 3, isAllDigits(part) {
                result.region = part
                index += 1
            }
        }

        // Variants: 5–8 characters, or 4 starting with a digit; no repeats.
        // The repeat check uses a set, so a hostile value with thousands of
        // variants costs time in proportion to its length, not its square.
        var seenVariants = Set<String>()
        while index < lower.count {
            let part = lower[index]
            let length = part.utf8.count
            let isVariant = (5...8).contains(length) || (length == 4 && part.utf8.first.map(isASCIIDigit) == true)
            guard isVariant else { break }
            guard seenVariants.insert(part).inserted else { return nil }
            result.variants.append(part)
            index += 1
        }

        // Extensions: a singleton other than `x`, then at least one 2–8
        // character subtag; the same singleton twice is malformed.
        var singletons = Set<String>()
        while index < lower.count, lower[index].utf8.count == 1, lower[index] != "x" {
            let singleton = lower[index]
            guard singletons.insert(singleton).inserted else { return nil }
            index += 1
            var subtags: [String] = []
            while index < lower.count, (2...8).contains(lower[index].utf8.count) {
                subtags.append(lower[index])
                index += 1
            }
            guard !subtags.isEmpty else { return nil }
            result.extensions.append([singleton] + subtags)
        }

        // Private use at the end: `x` and at least one subtag.
        if index < lower.count, lower[index] == "x" {
            index += 1
            guard index < lower.count else { return nil }
            result.privateUse = Array(lower[index...])
            index = lower.count
        }

        // Anything left over does not fit the grammar.
        return index == lower.count ? result : nil
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        isASCIILetter(byte) || isASCIIDigit(byte)
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
    }

    static func isAllLetters(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy(isASCIILetter)
    }

    static func isAllDigits(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy(isASCIIDigit)
    }
}
