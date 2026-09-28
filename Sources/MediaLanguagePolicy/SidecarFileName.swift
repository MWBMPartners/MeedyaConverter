// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / SidecarFileName
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// TEXT-030: a sidecar file named by language (subtitles, lyrics) has the
// shape
//
//     {media file stem}.{tag}[.{role}…][.{n}].{extension}
//
// The tag always comes first, so a role word is never mistaken for a
// language (`sdh` is also Southern Kurdish, `hi` Hindi). A builder reads
// its language with LANG-002's reader, as a reader of the name will, so what
// is written is what is read back (`fre` → `fr`). A malformed or unrecognised
// value never goes into a file name (it could hold characters unsafe in a
// path): it is written as `und`. Reading one back takes the stem from the media file
// it belongs to — never guessing where the stem ends.
// ============================================================================

import Foundation

/// Why a sidecar name could not be built.
public enum SidecarFileNameError: Error, Sendable, Equatable {
    /// The clash-avoiding number must be 2 to 999999999 (numbering starts
    /// from the second file; a longer number could not be read back).
    case invalidNumber(Int)
}

/// The parts read back from a sidecar file name.
public struct SidecarNameParts: Sendable, Hashable {
    /// The language (LANG-002's reader); `und` when the part was
    /// unrecognised; `nil` when the name has no language part at all.
    public let tag: String?
    /// The language part as written, when it was unrecognised.
    public let unrecognised: String?
    /// Roles from role words, each once, in TRACK-050 subtitle order.
    public let roles: [TrackRole]
    /// The clash-avoiding number, or `nil`.
    public let number: Int?
    /// The file extension, without the dot.
    public let fileExtension: String
}

/// Builds and reads sidecar file names (TEXT-030).
public struct SidecarFileName: Sendable {

    /// The reader the language part goes through (it canonicalises too).
    public let reader: LegacyLanguageReader

    public init(reader: LegacyLanguageReader) {
        self.reader = reader
    }

    /// The only role words written: `sdh`, `forced`, `commentary`.
    private static let writtenRoles: [TrackRole] = [.sdh, .forced, .commentary]

    /// Words read as roles (case-insensitive). `cc` and `hi` are read as
    /// `sdh` because other tools write them.
    private static let readRoles: [String: TrackRole] = [
        "sdh": .sdh, "cc": .sdh, "hi": .sdh, "forced": .forced, "commentary": .commentary
    ]

    /// The largest clash-avoiding number (nine digits).
    public static let largestNumber = 999_999_999

    /// Builds a sidecar file name.
    ///
    /// - Parameters:
    ///   - stem: The media file's name without its extension.
    ///   - tag: The language, read with LANG-002's reader exactly as a
    ///     reader of the name will read it back (TEXT-030): `fre` is written
    ///     `fr`, and a value the reader does not recognise — malformed, or an
    ///     unknown three-letter code such as `zzz` — is written `und`.
    ///   - roles: The track's roles; only `sdh`, `forced` and `commentary`
    ///     produce a role word (each once, in TRACK-050 order).
    ///   - fileExtension: Without the dot.
    ///   - number: The clash-avoiding number (2…999999999), or `nil`.
    /// - Throws: `SidecarFileNameError.invalidNumber` for any other number.
    public func build(stem: String, tag: String, roles: [TrackRole], fileExtension: String, number: Int?) throws -> String {
        if let number, !(2...Self.largestNumber).contains(number) {
            throw SidecarFileNameError.invalidNumber(number)
        }
        // Read, not just canonicalised (core revision 6, cases sidecar-27
        // and -28): canonicalising alone wrote `Film.fre.srt` for `fre` and
        // `Film.zzz.srt` for `zzz`, which a reader then read back as `fr`
        // and `und` — so what was written was not what is read.
        let language = reader.read(tag) ?? "und"
        let present = Set(roles)
        let words = Self.writtenRoles.filter { present.contains($0) }.map(\.word)
        var parts = [stem, language] + words
        if let number { parts.append(String(number)) }
        parts.append(fileExtension)
        return parts.joined(separator: ".")
    }

    /// Reads a sidecar file name that belongs to the media file with `stem`.
    ///
    /// - Returns: `nil` unless `fileName` starts with `stem` followed by a
    ///   dot. After the language part, role words are roles (each once), a
    ///   part of one to nine ASCII digits is the number (the last one counts;
    ///   a longer run of digits is not a number), and anything else is
    ///   ignored.
    public func parse(stem: String, fileName: String) -> SidecarNameParts? {
        let prefix = stem + "."
        guard fileName.hasPrefix(prefix) else { return nil }
        let parts = String(fileName.dropFirst(prefix.count))
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        let fileExtension = parts.last ?? ""
        let middle = parts.dropLast()
        guard let languagePart = middle.first else {
            return SidecarNameParts(tag: nil, unrecognised: nil, roles: [], number: nil, fileExtension: fileExtension)
        }

        let reading = reader.reading(languagePart)
        var roles = Set<TrackRole>()
        var number: Int?
        for part in middle.dropFirst() {
            if (1...9).contains(part.utf8.count), LanguageTagCanonicaliser.isAllDigits(part) {
                number = Int(part)
            } else if let role = Self.readRoles[part.lowercased()] {
                roles.insert(role)
            }
        }
        return SidecarNameParts(
            tag: reading.tagOrUndetermined,
            unrecognised: reading.unrecognisedText,
            roles: Self.writtenRoles.filter { roles.contains($0) },
            number: number,
            fileExtension: fileExtension
        )
    }
}
