// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / LanguageReferenceData
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The registry data every part of the language policy (MWBM-MEDIA-LANG,
// docs/standards/media-language-bcp47-policy.md) reads: which subtags exist,
// which have replacements, and the two ISO 639-2 tables (reading old
// three-letter codes, writing them).
//
// WHERE THE DATA COMES FROM
// -------------------------
// `Resources/bcp47-language-data-v1.json` is an EXACT copy of the master in
// MWBMPartners/MeedyaSuite-core, generated there from the IANA Language
// Subtag Registry and Debian's ISO 639-2 list. It is checked byte for byte
// in CI by scripts/media-lang/check_copies.py against the commit in
// docs/standards/MWBM-MEDIA-LANG.lock. Never edit it here: change the master
// and take it with `check_copies.py --update <commit>` (policy §8.3). It is
// NOT hand-typed into Swift, on purpose: two copies of a list drift.
//
// HOW IT IS FOUND AT RUN TIME
// ---------------------------
// SwiftPM copies the file into a resource bundle named
// `MeedyaConverter_MediaLanguagePolicy.bundle` (`.resources` on Linux). The
// accessor SwiftPM generates (`Bundle.module`) STOPS THE PROGRAM if the bundle
// is missing — and this toolchain's accessor looks only beside the main
// executable and in the app's Resources folder. A shipped command-line tool
// without the bundle next to it would crash the moment it read a language.
// So this file does its own search of the same places (plus the folder of a
// test bundle, used by `swift test`) and reports a plain error instead of
// crashing. The release workflows copy the bundle into the app and next to
// the command-line tool.
// ============================================================================

import Foundation

// MARK: - Errors

/// Why the reference data could not be loaded.
public enum LanguageReferenceDataError: Error, CustomStringConvertible, Sendable {
    /// The resource bundle was not found in any of the places searched.
    case bundleNotFound(searched: [String])
    /// The file was found but is not the data this code understands.
    case unreadable(String)

    public var description: String {
        switch self {
        case .bundleNotFound(let searched):
            return "The language reference data (\(LanguageReferenceData.bundleBaseName)) was not found. "
                + "Looked in: \(searched.joined(separator: ", "))."
        case .unreadable(let reason):
            return "The language reference data could not be read: \(reason)"
        }
    }
}

// MARK: - ISO 639-2 codes

/// A language's ISO 639-2 code in both of its forms (policy TRACK-070).
///
/// The two differ for twenty languages (`ger`/`deu`, `fre`/`fra`, `chi`/`zho`
/// …), so using the wrong one is a real error, not a matter of taste.
public struct ISO6392Codes: Sendable, Hashable, Codable {
    /// Bibliographic form — what Matroska's old `Language` field uses.
    public let b: String
    /// Terminology form — what MP4/MOV's `mdhd` field (and ID3) use.
    public let t: String

    public init(b: String, t: String) {
        self.b = b
        self.t = t
    }

    /// `und` in both forms: "language not known".
    public static let undetermined = ISO6392Codes(b: "und", t: "und")
}

// MARK: - LanguageReferenceData

/// The parsed reference data file. Immutable and `Sendable`, so one loaded
/// copy can be shared by every thread.
public struct LanguageReferenceData: Sendable {

    /// SwiftPM's name for this target's resource bundle (package name,
    /// underscore, target name).
    public static let bundleBaseName = "MeedyaConverter_MediaLanguagePolicy"

    /// The data file's name inside the bundle.
    public static let fileName = "bcp47-language-data-v1.json"

    /// The data file's own version (`data_version`).
    public let dataVersion: String

    /// Grandfathered tags keyed in lower case (LANG-001 step 2): the
    /// registry's spelling, and its replacement if it has one.
    let grandfathered: [String: (tag: String, preferred: String?)]

    /// Redundant tags (lower case) that have a replacement (LANG-001 step 4).
    let redundantPreferred: [String: String]

    /// Preferred-Value replacements by subtag type (LANG-001 step 5). Keys use
    /// each type's canonical case: language/extlang/variant lower case,
    /// script title case, region upper case.
    let preferredLanguage: [String: String]
    let preferredExtlang: [String: String]
    let preferredScript: [String: String]
    let preferredRegion: [String: String]
    let preferredVariant: [String: String]

    /// Every registered primary language subtag (lower case).
    let languages: Set<String>

    /// Registered ranges of language subtags (`qaa`…`qtz`), inclusive.
    let languageRanges: [(String, String)]

    /// Reading old three-letter codes (LANG-002): both ISO 639-2 forms, plus
    /// four withdrawn codes, to the canonical language subtag.
    let iso6392Reading: [String: String]

    /// Writing old three-letter fields (TRACK-070): canonical language subtag
    /// to both ISO 639-2 forms.
    let iso6392Writing: [String: ISO6392Codes]

    /// The ISO 639-2 local-use range (`qaa`…`qtz`), inclusive.
    let iso6392LocalUse: (String, String)

    // MARK: Loading

    /// Parses the reference data JSON.
    ///
    /// - Throws: `LanguageReferenceDataError.unreadable` if it is not the
    ///   expected shape.
    public init(jsonData: Data) throws {
        let raw: RawData
        do {
            raw = try JSONDecoder().decode(RawData.self, from: jsonData)
        } catch {
            throw LanguageReferenceDataError.unreadable(String(describing: error))
        }
        func pair(_ list: [String], _ what: String) throws -> (String, String) {
            guard list.count == 2 else {
                throw LanguageReferenceDataError.unreadable("\(what) is not a [first, last] pair")
            }
            return (list[0], list[1])
        }
        dataVersion = raw.dataVersion
        grandfathered = raw.grandfathered.mapValues { ($0.tag, $0.preferred) }
        redundantPreferred = raw.redundantPreferred
        preferredLanguage = raw.preferred["language"] ?? [:]
        preferredExtlang = raw.preferred["extlang"] ?? [:]
        preferredScript = raw.preferred["script"] ?? [:]
        preferredRegion = raw.preferred["region"] ?? [:]
        preferredVariant = raw.preferred["variant"] ?? [:]
        languages = Set(raw.languages)
        languageRanges = try raw.languageRanges.map { try pair($0, "language_ranges") }
        iso6392Reading = raw.iso6392
        iso6392Writing = raw.iso6392ForLanguage
        iso6392LocalUse = try pair(raw.iso6392LocalUse, "iso639_2_local_use")
    }

    /// Whether `subtag` (lower case) is a registered primary language subtag,
    /// counting the local-use range.
    func isRegisteredLanguage(_ subtag: String) -> Bool {
        languages.contains(subtag) || languageRanges.contains { $0.0 <= subtag && subtag <= $0.1 }
    }

    /// Whether `subtag` (lower case, three letters) is in the ISO 639-2
    /// local-use range `qaa`…`qtz`.
    func isLocalUse(_ subtag: String) -> Bool {
        subtag.utf8.count == 3 && iso6392LocalUse.0 <= subtag && subtag <= iso6392LocalUse.1
    }

    // MARK: The bundled copy

    /// The bundled reference data, loaded once for the whole process.
    ///
    /// A `Result` rather than a crash: if the bundle is missing (a packaging
    /// mistake), callers get a plain error and can keep the raw language
    /// text instead of guessing (policy LANG-002 / COMPAT-040).
    public static let bundled: Result<LanguageReferenceData, LanguageReferenceDataError> = {
        do {
            let url = try locateBundledFile()
            let data = try Data(contentsOf: url)
            return .success(try LanguageReferenceData(jsonData: data))
        } catch let error as LanguageReferenceDataError {
            return .failure(error)
        } catch {
            return .failure(.unreadable(String(describing: error)))
        }
    }()

    /// Finds the bundled data file without using `Bundle.module` (which stops
    /// the program when the bundle is missing — see the file header).
    ///
    /// Searched, in order: the app's Resources folder (`.app` builds), the
    /// folder of the running executable (the command-line tool; `swift run`),
    /// the same folder with symbolic links resolved (a tool linked into
    /// `/usr/local/bin`), and the folder holding the bundle this code was
    /// loaded from (`swift test`, where the code lives in a test bundle
    /// beside the resource bundle).
    static func locateBundledFile() throws -> URL {
        var folders: [URL] = []
        if let resources = Bundle.main.resourceURL { folders.append(resources) }
        folders.append(Bundle.main.bundleURL)
        if let executable = Bundle.main.executableURL {
            folders.append(executable.resolvingSymlinksInPath().deletingLastPathComponent())
        }
        let codeBundle = Bundle(for: BundleLocator.self)
        folders.append(codeBundle.bundleURL.deletingLastPathComponent())
        if let resources = codeBundle.resourceURL { folders.append(resources) }

        var searched: [String] = []
        for folder in folders {
            // `.bundle` on Apple platforms, `.resources` on Linux.
            for suffix in ["bundle", "resources"] {
                let bundleURL = folder.appendingPathComponent("\(bundleBaseName).\(suffix)")
                searched.append(bundleURL.path)
                // A `.copy` resource sits at the bundle's top level on some
                // build systems and under Contents/Resources on others.
                for candidate in [
                    bundleURL.appendingPathComponent(fileName),
                    bundleURL.appendingPathComponent("Contents/Resources/\(fileName)"),
                ] where FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        throw LanguageReferenceDataError.bundleNotFound(searched: searched)
    }

    /// A class defined in this module, so `Bundle(for:)` can find the bundle
    /// this code was loaded from.
    private final class BundleLocator {}
}

// MARK: - The file's shape

/// The JSON file's shape, decoded as written. Only the keys this code uses
/// are declared; the others (sources, scripts, regions …) are ignored.
private struct RawData: Decodable {
    struct Grandfathered: Decodable {
        let tag: String
        let preferred: String?
    }

    let dataVersion: String
    let grandfathered: [String: Grandfathered]
    let redundantPreferred: [String: String]
    let preferred: [String: [String: String]]
    let languages: [String]
    let languageRanges: [[String]]
    let iso6392: [String: String]
    let iso6392ForLanguage: [String: ISO6392Codes]
    let iso6392LocalUse: [String]

    enum CodingKeys: String, CodingKey {
        case dataVersion = "data_version"
        case grandfathered
        case redundantPreferred = "redundant_preferred"
        case preferred
        case languages
        case languageRanges = "language_ranges"
        case iso6392 = "iso639_2"
        case iso6392ForLanguage = "iso639_2_for_language"
        case iso6392LocalUse = "iso639_2_local_use"
    }
}
