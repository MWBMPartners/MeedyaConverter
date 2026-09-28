// ============================================================================
// MeedyaConverter — MediaLanguagePolicyTests / ConformanceTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The conformance runner for MWBM-MEDIA-LANG (policy §8.1). It runs EVERY
// case in EVERY section of Tests/Fixtures/MediaLanguage/
// bcp47-language-policy-v1.json — the exact copy checked against the master
// by scripts/media-lang/check_copies.py — and:
//
//   * collects every failure and reports them all together, so one run
//     shows the whole picture;
//   * runs both automatic-selection sections a second time with the tracks
//     reversed (AUTO-010: the answer must not depend on list order);
//   * checks every canonicalise answer is stable (canonicalising it again
//     changes nothing — revision 2);
//   * treats a case marked "error": true as passing ONLY if the call throws;
//   * FAILS — never passes — when the file has a section it does not know,
//     a section is missing or empty, or a case lacks a field the schema
//     requires (policy §8.1, revision 3): a runner that quietly runs fewer
//     checks than the file holds is how a broken implementation passes;
//   * before running anything, checks the WHOLE file against the schema copy
//     (`FixtureShapeCheck`): every field's type — an object is never taken
//     for a list (`{}` for `[]`) nor a number for true/false, and null only
//     where the schema allows it — no field the schema does not list, the
//     allowed words, `error` only ever `true` and only on a case expecting
//     null. Any problem fails the run and NO case is run. (Added when the
//     copies moved to core aaaa585: until then only field PRESENCE was
//     checked, so `roles: {}` or `input: 5` would have passed);
//   * checks the number of cases run equals the number in the file;
//   * runs the cases from the SAME reading of the file the shape check
//     checked (`JSONValue.plainValue`) — one reading, so a case can never
//     run on a different input from the one checked. (Until the second
//     independent review the cases came from a second reading with
//     `JSONSerialization`, which on macOS drops a leading U+FEFF.)
//
// Presentation cases name groups with the case's display_names and sort
// them by comparing its collation_keys as plain strings, then by subtag
// (`LanguageGroupCollation.plainKeys`), as the policy requires — so the
// answers do not depend on the platform's locale data.
// ============================================================================

import Foundation
import XCTest
@testable import MediaLanguagePolicy

final class ConformanceTests: XCTestCase {

    // MARK: - What the file must contain

    /// Every section, with the fields each case must have (from the schema's
    /// `required` lists — `test_requiredFieldTableMatchesTheSchema` checks
    /// this table against the schema copy, so it cannot drift).
    static let sectionFields: [String: [String]] = [
        "canonicalise": ["id", "rules", "input", "expected", "kind"],
        "legacy_three_letter": ["id", "rules", "input", "expected"],
        "iso639_2_write": ["id", "rules", "input", "expected"],
        "posix_locale": ["id", "rules", "input", "expected"],
        "sidecar_name": ["id", "rules", "mode", "stem", "expected"],
        "canonical_order": ["id", "rules", "description", "items", "expected"],
        "track_order": ["id", "rules", "description", "tracks", "expected"],
        "presentation_order": [
            "id", "rules", "description", "preferences", "accessibility",
            "display_names", "collation_keys", "items", "expected"
        ],
        "subtitle_menu": [
            "id", "rules", "description", "preferences", "accessibility",
            "display_names", "collation_keys", "items", "expected"
        ],
        "label": ["id", "rules", "type", "language_name", "roles", "role_names", "channels", "expected"],
        "match": ["id", "rules", "preference", "candidate", "expected"],
        "auto_select_audio": ["id", "rules", "description", "preferences", "accessibility", "tracks", "expected"],
        "auto_select_subtitle": [
            "id", "rules", "description", "mode", "preferences", "accessibility", "audio", "tracks", "expected"
        ]
    ]

    /// Extra fields a sidecar case needs, by its mode.
    static let sidecarModeFields: [String: [String]] = [
        "build": ["tag", "roles", "extension", "number"],
        "parse": ["filename"]
    ]

    /// Top-level keys that are not sections.
    static let headerKeys: Set<String> = ["$schema", "policy", "policy_version", "fixtures_version", "data_version"]

    // MARK: - Files

    /// Tests/Fixtures/MediaLanguage — found from this source file's own path,
    /// so the copy the checker guards is the one the tests read.
    static let fixturesFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/MediaLanguage")

    /// A file as plain dictionaries — read with `JSONDecoder` (`JSONValue`),
    /// the same reader the shape check and the runner use, never with
    /// `JSONSerialization`, which on macOS drops a leading U+FEFF from a
    /// string (see `JSONValue.plainValue`).
    static func loadJSON(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: fixturesFolder.appendingPathComponent(name))
        guard let object = try JSONDecoder().decode(JSONValue.self, from: data).plainValue as? [String: Any] else {
            throw HarnessError("\(name) is not a JSON object")
        }
        return object
    }

    /// The case file's raw bytes.
    static func loadData(_ name: String) throws -> Data {
        try Data(contentsOf: fixturesFolder.appendingPathComponent(name))
    }

    /// The schema copy, read so objects stay objects (for `FixtureShapeCheck`).
    static func loadSchema() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: loadData("bcp47-language-policy-v1.schema.json"))
    }

    /// The policy on the BUNDLED data — so the tests also prove the resource
    /// bundle is found where the code looks for it.
    static func policyUnderTest() throws -> MediaLanguagePolicy {
        try MediaLanguagePolicy.shared.get()
    }

    // MARK: - The conformance run

    func test_everyCaseInEverySectionPasses() throws {
        let policy = try Self.policyUnderTest()
        let fixture = try Self.loadData("bcp47-language-policy-v1.json")
        var run = ConformanceRun(policy: policy, schema: try Self.loadSchema())
        let totalCases = run.runFile(fixture, dataVersion: try LanguageReferenceData.bundled.get().dataVersion)

        let summary = "MWBM-MEDIA-LANG conformance: \(run.casesRun) of \(totalCases) cases run, "
            + "\(run.checks) checks (incl. \(run.reversedRuns) reversed selection runs and "
            + "\(run.stabilityChecks) stability checks), \(run.failures.count) failure(s)."
        print(summary)
        XCTAssertEqual(run.casesRun, totalCases, "The runner must run every case in the file")
        if !run.failures.isEmpty {
            XCTFail(summary + "\n" + run.failures.joined(separator: "\n"))
        }
    }

    /// The field table above must say exactly what the schema copy says.
    func test_requiredFieldTableMatchesTheSchema() throws {
        let schema = try Self.loadJSON("bcp47-language-policy-v1.schema.json")
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let definitions = schema["$defs"] as? [String: Any] ?? [:]

        func resolve(_ node: [String: Any]) -> [String: Any] {
            if let ref = node["$ref"] as? String, let name = ref.split(separator: "/").last {
                return definitions[String(name)] as? [String: Any] ?? [:]
            }
            return node
        }

        let schemaSections = Set(properties.keys).subtracting(Self.headerKeys)
        XCTAssertEqual(schemaSections, Set(Self.sectionFields.keys), "Sections in the schema")

        for (section, fields) in Self.sectionFields {
            guard let property = properties[section] as? [String: Any],
                  let items = property["items"] as? [String: Any] else {
                XCTFail("schema has no items for \(section)")
                continue
            }
            let item = resolve(items)
            if let alternatives = item["oneOf"] as? [[String: Any]] {
                // sidecar_name: build / parse cases have different fields.
                for alternative in alternatives.map(resolve) {
                    let required = Set(alternative["required"] as? [String] ?? [])
                    let mode = ((alternative["properties"] as? [String: Any])?["mode"] as? [String: Any])?["const"] as? String ?? ""
                    XCTAssertEqual(required, Set(fields + (Self.sidecarModeFields[mode] ?? [])), "\(section) (\(mode))")
                }
            } else {
                XCTAssertEqual(Set(item["required"] as? [String] ?? []), Set(fields), section)
            }
        }
    }

    /// The runner itself must fail on a broken file — proven on doctored
    /// copies of the real one, in memory.
    func test_runnerFailsOnUnknownMissingEmptyOrIncompleteSections() throws {
        let policy = try Self.policyUnderTest()
        let schema = try Self.loadSchema()
        let fixture = try Self.loadJSON("bcp47-language-policy-v1.json")
        let dataVersion = try LanguageReferenceData.bundled.get().dataVersion

        // The real file passes, so each doctored copy below fails only
        // because of what was done to it.
        var clean = ConformanceRun(policy: policy, schema: schema)
        _ = clean.runFile(try Self.loadData("bcp47-language-policy-v1.json"), dataVersion: dataVersion)
        XCTAssertTrue(clean.failures.isEmpty, clean.failures.joined(separator: "\n"))

        // A doctored copy is written back out as JSON and run like the real
        // file, so the shape check reads it exactly as it would a file.
        func failures(after change: (inout [String: Any]) -> Void) -> [String] {
            var doctored = fixture
            change(&doctored)
            guard let data = try? JSONSerialization.data(withJSONObject: doctored) else {
                return ["(could not write the doctored copy)"]
            }
            var run = ConformanceRun(policy: policy, schema: schema)
            _ = run.runFile(data, dataVersion: dataVersion)
            return run.failures
        }

        // An unknown section.
        XCTAssertTrue(failures { $0["new_section"] = [["id": "new-01"]] }.contains { $0.contains("unknown section") })
        // A missing section.
        XCTAssertTrue(failures { $0.removeValue(forKey: "label") }.contains { $0.contains("'label' is missing") })
        // An empty section.
        XCTAssertTrue(failures { $0["match"] = [[String: Any]]() }.contains { $0.contains("'match' is empty") })
        // A case lacking a required field.
        XCTAssertTrue(failures { file in
            var cases = file["match"] as? [[String: Any]] ?? []
            cases[0].removeValue(forKey: "expected")
            file["match"] = cases
        }.contains { $0.contains("missing required field 'expected'") })
        // A refusal case the implementation answered instead of refusing
        // would fail: here the refusal flag is added to an ordinary case,
        // with the null answer the schema requires alongside it, so the file
        // is well formed and the case really runs.
        XCTAssertTrue(failures { file in
            var cases = file["sidecar_name"] as? [[String: Any]] ?? []
            if let index = cases.firstIndex(where: { ($0["mode"] as? String) == "build" && !($0["error"] as? Bool ?? false) }) {
                cases[index]["error"] = true
                cases[index]["expected"] = NSNull()
            }
            file["sidecar_name"] = cases
        }.contains { $0.contains("must be refused") })

        // The shape check: wrong types, {} for [] and [] for {}, null where
        // the schema allows none, fields the schema does not list, words it
        // does not allow, and `error` anywhere but on a refusal expecting
        // null. Each fails the run, and then NO case is run.
        func shapeFailure(_ section: String, _ index: Int = 0, _ change: (inout [String: Any]) -> Void) -> [String] {
            failures { file in
                var cases = file[section] as? [[String: Any]] ?? []
                change(&cases[index])
                file[section] = cases
            }
        }
        func track(_ change: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
            { selectionCase in
                var tracks = selectionCase["tracks"] as? [[String: Any]] ?? []
                change(&tracks[0])
                selectionCase["tracks"] = tracks
            }
        }
        let shapeProblems: [(String, [String])] = [
            ("roles: {}", shapeFailure("auto_select_audio", 0, track { $0["roles"] = [String: Any]() })),
            ("roles: null", shapeFailure("auto_select_audio", 0, track { $0["roles"] = NSNull() })),
            ("accessibility: []", shapeFailure("auto_select_audio") { $0["accessibility"] = [Any]() }),
            ("display_names: []", shapeFailure("presentation_order") { $0["display_names"] = [Any]() }),
            ("input: 5", shapeFailure("canonicalise") { $0["input"] = 5 }),
            ("channels: 5", shapeFailure("label") { $0["channels"] = 5 }),
            ("default: 1", shapeFailure("auto_select_audio", 0, track { $0["default"] = 1 })),
            ("description: null", shapeFailure("match") { $0["description"] = NSNull() }),
            ("an unknown field", shapeFailure("match") { $0["surprise"] = "x" }),
            ("error: true where refusals are not allowed", shapeFailure("match") { $0["error"] = true }),
            ("error: false", shapeFailure("auto_select_audio") { $0["error"] = false; $0["expected"] = NSNull() }),
            ("error with an answer", shapeFailure("auto_select_audio") { $0["error"] = true }),
            ("an unknown role", shapeFailure("auto_select_audio", 0, track { $0["roles"] = ["narrator"] })),
            ("a bad case id", shapeFailure("match") { $0["id"] = "match-1" }),
            ("a bad rule id", shapeFailure("match") { $0["rules"] = ["MATCH-10"] }),
            ("a case id ending in a line break", shapeFailure("match") { $0["id"] = "match-01\n" }),
            ("a number out of range", shapeFailure("sidecar_name", 0) { $0["number"] = 1_000_000_000 })
        ]
        for (what, found) in shapeProblems {
            XCTAssertFalse(found.isEmpty, "\(what) must fail the run")
            XCTAssertTrue(found.contains { $0.contains("shape:") }, "\(what) must fail the SHAPE check: \(found)")
            XCTAssertFalse(found.contains { $0.contains("got ") }, "\(what): no case may run: \(found)")
        }
        // The top level too.
        XCTAssertTrue(failures { $0["policy_version"] = 1 }.contains { $0.contains("shape:") })
        XCTAssertTrue(failures { $0["fixtures_version"] = "1.0" }.contains { $0.contains("shape:") })

        // A case with an explicit null where a value is required still runs
        // (null is a real answer for many cases); a missing key does not.
        XCTAssertTrue(ConformanceRun.has(["expected": NSNull()], "expected"))
        XCTAssertFalse(ConformanceRun.has([:], "expected"))
    }

    /// The cases are run from the file AS WRITTEN. A doctored copy of the
    /// real file with one extra case whose input starts with U+FEFF (an
    /// invisible character) and which expects plain `en` must FAIL: the
    /// canonicaliser refuses a tag with a character outside ASCII. With the
    /// runner's old second reading (`JSONSerialization`, which on macOS drops
    /// that character) the case passed — the second independent review
    /// planted exactly this. Both ways of writing the character are tried:
    /// the JSON escape `\ufeff` and the character itself.
    func test_runnerRunsTheFileAsWritten() throws {
        let policy = try Self.policyUnderTest()
        let dataVersion = try LanguageReferenceData.bundled.get().dataVersion
        let original = try XCTUnwrap(String(data: try Self.loadData("bcp47-language-policy-v1.json"), encoding: .utf8))
        let marker = "\"canonicalise\": ["
        XCTAssertTrue(original.contains(marker), "the case file's canonicalise section")
        for (label, input) in [("escaped", "\\ufeffen"), ("raw", "\u{FEFF}en")] {
            let planted = #"{"id": "canon-99", "rules": ["LANG-001"], "input": ""# + input
                + #"", "expected": "en", "kind": "ordinary"},"#
            let doctored = original.replacingOccurrences(of: marker, with: marker + planted)
            var run = ConformanceRun(policy: policy, schema: try Self.loadSchema())
            _ = run.runFile(Data(doctored.utf8), dataVersion: dataVersion)
            XCTAssertFalse(run.failures.contains { $0.contains("shape:") }, "\(label): the doctored copy is well formed")
            XCTAssertTrue(run.failures.contains { $0.contains("canon-99") }, "\(label): the planted case must fail")
            XCTAssertEqual(run.failures.count, 1, "\(label): only the planted case fails: \(run.failures)")
        }
    }

    /// The shape check's reader keeps every kind of value apart — the reason
    /// the file is read into `JSONValue` rather than plain dictionaries —
    /// and its pattern check does not let a final line break through.
    func test_shapeReaderKeepsKindsApart() throws {
        let decoded = try JSONDecoder().decode(
            JSONValue.self, from: Data(#"{"a":{},"b":[],"c":true,"d":1,"e":1.5,"f":null,"g":"x"}"#.utf8)
        )
        guard case .object(let object) = decoded else { return XCTFail("not an object") }
        XCTAssertEqual(object["a"]?.kind, "an object")
        XCTAssertEqual(object["b"]?.kind, "a list")
        XCTAssertEqual(object["c"]?.kind, "true/false")
        XCTAssertEqual(object["d"]?.kind, "a whole number")
        XCTAssertEqual(object["e"]?.kind, "a number")
        XCTAssertEqual(object["f"]?.kind, "null")
        XCTAssertEqual(object["g"]?.kind, "a string")
        XCTAssertTrue(FixtureShapeCheck.matches("match-01", "^[a-z]+-[0-9]{2}$"))
        XCTAssertFalse(FixtureShapeCheck.matches("match-01\n", "^[a-z]+-[0-9]{2}$"))
        // A schema keyword the checker does not know is a problem, not a pass.
        let unknown = FixtureShapeCheck(schema: .object(["format": .string("date")]))
        XCTAssertEqual(unknown.problems(in: .string("x")).count, 1)
    }

    // MARK: - Behaviour the shared cases cannot express

    /// Duplicate-variant detection is linear: 20,000 distinct variants are
    /// read quickly (a quadratic check took seconds in another implementation).
    func test_manyVariantsAreCheckedInLinearTime() throws {
        let canonicaliser = try Self.policyUnderTest().canonicaliser
        let variants = (0..<20_000).map { String(format: "v%06d", $0) }
        let tag = "en-" + variants.joined(separator: "-")
        let start = Date()
        let result = canonicaliser.canonicalise(tag)
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(result.kind, .ordinary)
        XCTAssertLessThan(seconds, 1.0, "20,000 variants took \(seconds) s")
        XCTAssertEqual(canonicaliser.canonicalise("en-" + variants[0] + "-" + variants[0]).kind, .malformed)
    }

    /// AUTO-010's one fixed identifier order.
    func test_identifierOrder() {
        func sorted(_ ids: [String]) -> [String] { ids.sorted(by: TrackIdentifierOrder.less) }
        XCTAssertEqual(sorted(["10", "9"]), ["9", "10"])
        XCTAssertEqual(sorted(["1", "01"]), ["01", "1"])
        XCTAssertEqual(sorted(["1a", "10", "2"]), ["2", "10", "1a"], "digits-only first, then text")
        XCTAssertEqual(sorted(["b", "a", "007", "7"]), ["007", "7", "a", "b"])
        // Longer than any integer type: still compared as numbers.
        XCTAssertEqual(sorted(["100000000000000000000000", "99999999999999999999999"]),
                       ["99999999999999999999999", "100000000000000000000000"])
    }

    /// Canonical form refuses what the policy says is malformed, including a
    /// line break inside a subtag (canon-49's point, from the builder side).
    func test_lineBreakInsideAValueIsMalformed() throws {
        let policy = try Self.policyUnderTest()
        XCTAssertTrue(policy.canonicaliser.canonicalise("en-x-foo\n-bar").isMalformed)
        XCTAssertEqual(try policy.sidecarNames.build(stem: "Film", tag: "en-x-foo\n-bar", roles: [],
                                                     fileExtension: "srt", number: nil), "Film.und.srt")
    }

    /// The platform's names (UI-010, NAME-010). Not part of the shared cases
    /// — those supply their own names — so only a few names every CLDR
    /// version agrees on are checked.
    func test_platformNames() {
        XCTAssertEqual(LanguageNames.autonym(of: "de"), "Deutsch")
        XCTAssertEqual(LanguageNames.autonym(of: "fr"), "Français")
        XCTAssertEqual(LanguageNames.localizedName(of: "de", in: Locale(identifier: "en")), "German")
        XCTAssertEqual(LanguageNames.localizedName(of: "en-GB", in: Locale(identifier: "en")), "English (United Kingdom)")
        XCTAssertNil(LanguageNames.autonym(of: "und"), "A special code has no autonym")
    }
}

// MARK: - The runner

/// A thrown description of a problem with the case file itself.
struct HarnessError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Runs cases and collects every failure (so they are reported together).
struct ConformanceRun {
    let policy: MediaLanguagePolicy
    /// The case file's schema, for the shape check (`FixtureShapeCheck`).
    let shapeCheck: FixtureShapeCheck
    var failures: [String] = []
    var casesRun = 0
    var checks = 0
    var reversedRuns = 0
    var stabilityChecks = 0

    init(policy: MediaLanguagePolicy, schema: JSONValue) {
        self.policy = policy
        self.shapeCheck = FixtureShapeCheck(schema: schema)
    }

    // MARK: The whole file

    /// Checks the whole file against its schema, checks the header, refuses
    /// unknown, missing and empty sections (policy §8.1), and — only when
    /// the file is well formed — runs every case. Returns the number of cases
    /// in the file (for the "every case was run" check).
    mutating func runFile(_ data: Data, dataVersion: String) -> Int {
        // Read ONCE: the shape check and the cases both work from this one
        // reading (`JSONValue`, kept exact; the cases get it as plain
        // dictionaries through `plainValue`). The file used to be read a
        // second time with `JSONSerialization` to run the cases from — and on
        // macOS that reader drops a leading U+FEFF from a string, so a case
        // could run on a different input from the one checked (the second
        // independent review's finding; `test_runnerRunsTheFileAsWritten`).
        let shaped: JSONValue
        let fixture: [String: Any]
        do {
            shaped = try JSONDecoder().decode(JSONValue.self, from: data)
            guard let object = shaped.plainValue as? [String: Any] else {
                fail("file", "is not a JSON object")
                return 0
            }
            fixture = object
        } catch {
            fail("file", "is not readable JSON: \(error)")
            return 0
        }
        let shapeProblems = shapeCheck.problems(in: shaped)
        for problem in shapeProblems {
            fail("shape", problem)
        }

        expect("header policy", fixture["policy"] as? String, "MWBM-MEDIA-LANG")
        expect("header policy_version", fixture["policy_version"] as? String, "1.0.0")
        expect("header data_version", fixture["data_version"] as? String, dataVersion)

        var totalCases = 0
        for key in fixture.keys.sorted()
        where !ConformanceTests.headerKeys.contains(key) && ConformanceTests.sectionFields[key] == nil {
            fail("file", "unknown section '\(key)' — the runner does not know how to check it")
        }
        for section in ConformanceTests.sectionFields.keys.sorted() {
            guard let cases = fixture[section] as? [[String: Any]] else {
                fail("file", "section '\(section)' is missing or not a list of cases")
                continue
            }
            if cases.isEmpty {
                fail("file", "section '\(section)' is empty")
            }
            totalCases += cases.count
            // A file that breaks its schema is not run at all: a case read
            // with a wrong-typed field could pass or fail for the wrong
            // reason. The count check then fails too.
            guard shapeProblems.isEmpty else { continue }
            for testCase in cases {
                runCase(section: section, testCase)
            }
        }
        return totalCases
    }

    // MARK: Recording

    mutating func fail(_ id: String, _ message: String) {
        failures.append("  \(id): \(message)")
    }

    mutating func expect<T: Equatable>(_ id: String, _ got: T, _ expected: T) {
        checks += 1
        if got != expected {
            fail(id, "got \(String(describing: got)), expected \(String(describing: expected))")
        }
    }

    /// Whether `key` is present (an explicit JSON null counts as present).
    static func has(_ object: [String: Any], _ key: String) -> Bool {
        object.index(forKey: key) != nil
    }

    // MARK: Field access that fails loudly

    /// Unwraps a field, or throws if it has the wrong type.
    static func need<T>(_ value: T?, _ field: String) throws -> T {
        guard let value else { throw HarnessError("field '\(field)' has the wrong type") }
        return value
    }

    static func string(_ value: Any?) -> String? { value as? String }
    static func optionalString(_ value: Any?) -> String?? {
        if value is NSNull { return .some(nil) }
        if let string = value as? String { return .some(string) }
        return nil
    }
    static func strings(_ value: Any?) -> [String]? { value as? [String] }
    static func objects(_ value: Any?) -> [[String: Any]]? { value as? [[String: Any]] }

    /// The case must be marked as a refusal ("error": true).
    static func expectsError(_ testCase: [String: Any]) -> Bool {
        (testCase["error"] as? Bool) == true
    }

    static func accessibility(_ value: Any?) -> AccessibilityPreferences {
        let object = value as? [String: Any] ?? [:]
        return AccessibilityPreferences(
            audioDescription: (object["audio_description"] as? Bool) ?? false,
            captions: (object["captions"] as? Bool) ?? false
        )
    }

    static func roles(_ value: Any?) -> [TrackRole] {
        (value as? [String] ?? []).map(TrackRole.init(word:))
    }

    // MARK: One case

    mutating func runCase(section: String, _ testCase: [String: Any]) {
        let id = (testCase["id"] as? String) ?? "(case with no id in \(section))"
        var required = ConformanceTests.sectionFields[section] ?? []
        if section == "sidecar_name", let mode = testCase["mode"] as? String {
            required += ConformanceTests.sidecarModeFields[mode] ?? []
        }
        let missing = required.filter { !Self.has(testCase, $0) }
        guard missing.isEmpty else {
            fail(id, "case lacks required field(s) \(missing.joined(separator: ", "))")
            return
        }
        casesRun += 1
        do {
            try dispatch(section: section, id: id, testCase)
        } catch {
            fail(id, "could not be read: \(error)")
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private mutating func dispatch(section: String, id: String, _ c: [String: Any]) throws {
        func need<T>(_ value: T?, _ field: String) throws -> T { try Self.need(value, field) }

        switch section {
        case "canonicalise":
            let input = try need(Self.string(c["input"]), "input")
            let expected = try need(Self.optionalString(c["expected"]), "expected")
            let kind = try need(Self.string(c["kind"]), "kind")
            let tag = policy.canonicaliser.canonicalise(input)
            expect(id, "\(tag.canonical ?? "null") [\(tag.kind.rawValue)]", "\(expected ?? "null") [\(kind)]")
            if let expected {
                // Revision 2: canonical form is stable.
                stabilityChecks += 1
                expect(id + " (stability)", policy.canonicaliser.canonicalise(expected).canonical, expected)
            }

        case "legacy_three_letter":
            let input = try need(Self.string(c["input"]), "input")
            let expected = try need(Self.optionalString(c["expected"]), "expected")
            expect(id, policy.reader.read(input), expected)

        case "iso639_2_write":
            let input = try need(Self.string(c["input"]), "input")
            let expected = try need(c["expected"] as? [String: String], "expected")
            let codes = policy.iso6392.codes(for: input)
            expect(id, ["b": codes.b, "t": codes.t], expected)

        case "posix_locale":
            let input = try need(Self.string(c["input"]), "input")
            let expected = try need(Self.optionalString(c["expected"]), "expected")
            expect(id, policy.posixLocales.convert(input), expected)

        case "sidecar_name":
            try runSidecar(id: id, c)

        case "canonical_order":
            let items = try need(Self.objects(c["items"]), "items")
            let expected = try need(Self.strings(c["expected"]), "expected")
            var ids: [String] = []
            var orderItems: [CanonicalOrderItem] = []
            for item in items {
                let tag = try need(Self.string(item["tag"]), "items.tag")
                ids.append((item["id"] as? String) ?? tag)
                orderItems.append(CanonicalOrderItem(tag: tag, isOriginal: (item["original"] as? Bool) ?? false))
            }
            expect(id, policy.canonicalOrder.order(orderItems).map { ids[$0] }, expected)

        case "track_order":
            let tracks = try need(Self.objects(c["tracks"]), "tracks")
            let expected = try need(Self.strings(c["expected"]), "expected")
            var ids: [String] = []
            var items: [CanonicalOrderItem] = []
            for track in tracks {
                for field in ["id", "type", "tag", "roles"] where !Self.has(track, field) {
                    throw HarnessError("track lacks '\(field)'")
                }
                ids.append(try need(Self.string(track["id"]), "tracks.id"))
                let type = try need(TrackType(rawValue: Self.string(track["type"]) ?? ""), "tracks.type")
                items.append(CanonicalOrderItem(
                    tag: try need(Self.string(track["tag"]), "tracks.tag"),
                    isOriginal: (track["original"] as? Bool) ?? false,
                    type: type,
                    roles: Self.roles(track["roles"])
                ))
            }
            expect(id, policy.canonicalOrder.trackOrder(items).map { ids[$0] }, expected)

        case "presentation_order", "subtitle_menu":
            let expected = try need(Self.strings(c["expected"]), "expected")
            let (ids, items, preferences, accessibility, collation) = try presentationInputs(c)
            if section == "subtitle_menu" {
                let menu = policy.presentationOrder.subtitleMenu(
                    items, preferences: preferences, accessibility: accessibility, collation: collation
                )
                let got = menu.map { entry -> String in
                    if case .track(let index) = entry { return ids[index] }
                    return "off"
                }
                expect(id, got, expected)
            } else {
                let order = policy.presentationOrder.order(
                    items, preferences: preferences, accessibility: accessibility, collation: collation
                )
                expect(id, order.map { ids[$0] }, expected)
            }

        case "label":
            let type = try need(TrackType(rawValue: Self.string(c["type"]) ?? ""), "type")
            let names = try need(c["role_names"] as? [String: String], "role_names")
            var roleNames: [TrackRole: String] = [:]
            for (word, name) in names { roleNames[TrackRole(word: word)] = name }
            let channels = try need(Self.optionalString(c["channels"]), "channels")
            let label = TrackMenuLabel.label(
                languageName: try need(Self.string(c["language_name"]), "language_name"),
                roles: Self.roles(c["roles"]),
                type: type,
                roleNames: roleNames,
                channels: channels
            )
            expect(id, label, try need(Self.string(c["expected"]), "expected"))

        case "match":
            let expected = try need(c["expected"] as? [String: Any], "expected")
            let result = policy.matcher.match(
                preference: try need(Self.string(c["preference"]), "preference"),
                candidate: try need(Self.string(c["candidate"]), "candidate")
            )
            expect(id, result.level.word, try need(expected["level"] as? String, "expected.level"))
            expect(id + " distance", result.distance, try need(expected["distance"] as? Int, "expected.distance"))

        case "auto_select_audio", "auto_select_subtitle":
            try runSelection(section: section, id: id, c)

        default:
            throw HarnessError("no runner for section '\(section)'")
        }
    }

    // MARK: Sections with more parts

    private mutating func runSidecar(id: String, _ c: [String: Any]) throws {
        let mode = c["mode"] as? String
        let stem = c["stem"] as? String ?? ""
        switch mode {
        case "build":
            let number: Int?
            if c["number"] is NSNull { number = nil } else if let value = c["number"] as? Int { number = value } else {
                throw HarnessError("field 'number' has the wrong type")
            }
            let names = policy.sidecarNames
            let build = { try names.build(
                stem: stem,
                tag: c["tag"] as? String ?? "",
                roles: Self.roles(c["roles"]),
                fileExtension: c["extension"] as? String ?? "",
                number: number
            ) }
            checks += 1
            if Self.expectsError(c) {
                // A refusal case: only a thrown error passes; any returned
                // value fails it.
                do {
                    let value = try build()
                    fail(id, "must be refused with an error, but returned \(value)")
                } catch {
                    // Refused, as required.
                }
            } else {
                do {
                    let name = try build()
                    if name != c["expected"] as? String {
                        fail(id, "got \(name), expected \(String(describing: c["expected"]))")
                    }
                } catch {
                    fail(id, "threw \(error), expected \(String(describing: c["expected"]))")
                }
            }
        case "parse":
            let parts = policy.sidecarNames.parse(stem: stem, fileName: c["filename"] as? String ?? "")
            let got: String
            if let parts {
                got = Self.describeParts(
                    tag: parts.tag, unrecognised: parts.unrecognised, roles: parts.roles.map(\.word),
                    number: parts.number, fileExtension: parts.fileExtension
                )
            } else {
                got = "null"
            }
            let expected: String
            if let object = c["expected"] as? [String: Any] {
                expected = Self.describeParts(
                    tag: object["tag"] as? String, unrecognised: object["unrecognised"] as? String,
                    roles: object["roles"] as? [String] ?? [], number: object["number"] as? Int,
                    fileExtension: object["extension"] as? String ?? ""
                )
            } else if c["expected"] is NSNull {
                expected = "null"
            } else {
                throw HarnessError("field 'expected' has the wrong type")
            }
            expect(id, got, expected)
        default:
            throw HarnessError("unknown sidecar mode '\(mode ?? "none")'")
        }
    }

    static func describeParts(tag: String?, unrecognised: String?, roles: [String], number: Int?, fileExtension: String) -> String {
        "tag=\(tag ?? "null") unrecognised=\(unrecognised ?? "null") roles=\(roles) "
            + "number=\(number.map(String.init) ?? "null") extension=\(fileExtension)"
    }

    private func presentationInputs(_ c: [String: Any]) throws -> (
        [String], [PresentationItem], [String], AccessibilityPreferences, LanguageGroupCollation
    ) {
        guard let rawItems = Self.objects(c["items"]),
              let preferences = Self.strings(c["preferences"]),
              let keys = c["collation_keys"] as? [String: String],
              c["display_names"] is [String: String] else {
            throw HarnessError("presentation fields have the wrong type")
        }
        var ids: [String] = []
        var items: [PresentationItem] = []
        for item in rawItems {
            guard let itemID = item["id"] as? String, let tag = item["tag"] as? String else {
                throw HarnessError("item lacks 'id' or 'tag'")
            }
            ids.append(itemID)
            items.append(PresentationItem(
                tag: tag,
                type: (item["type"] as? String).flatMap(TrackType.init(rawValue:)),
                roles: Self.roles(item["roles"]),
                isOriginal: (item["original"] as? Bool) ?? false
            ))
            // Every ordinary language present must have a sorting key, or the
            // stand-in collation would silently sort it as "".
            let canonical = policy.canonicaliser.canonicalise(tag)
            if canonical.kind == .ordinary, let language = canonical.language,
               LanguageBucket(canonical) == .ordinary, keys[language] == nil {
                throw HarnessError("no collation key for '\(language)'")
            }
        }
        return (ids, items, preferences, Self.accessibility(c["accessibility"]), .plainKeys(keys))
    }

    private mutating func runSelection(section: String, id: String, _ c: [String: Any]) throws {
        guard let rawTracks = Self.objects(c["tracks"]), let preferences = Self.strings(c["preferences"]) else {
            throw HarnessError("selection fields have the wrong type")
        }
        let tracks = try rawTracks.map { track -> SelectableTrack in
            guard let trackID = track["id"] as? String, let tag = track["tag"] as? String, Self.has(track, "roles") else {
                throw HarnessError("track lacks 'id', 'tag' or 'roles'")
            }
            return SelectableTrack(
                id: trackID, tag: tag, roles: Self.roles(track["roles"]),
                isDefault: (track["default"] as? Bool) ?? false,
                isOriginal: (track["original"] as? Bool) ?? false
            )
        }
        let accessibility = Self.accessibility(c["accessibility"])
        let expected: String? = try Self.need(Self.optionalString(c["expected"]), "expected")

        let selector = policy.selector
        let select: ([SelectableTrack]) throws -> String?
        if section == "auto_select_audio" {
            select = { try selector.selectAudio($0, preferences: preferences, accessibility: accessibility) }
        } else {
            guard let mode = SubtitleMode(rawValue: c["mode"] as? String ?? "") else {
                throw HarnessError("unknown subtitle mode")
            }
            let audio: String? = try Self.need(Self.optionalString(c["audio"]), "audio")
            select = {
                try selector.selectSubtitle($0, audioTag: audio, preferences: preferences,
                                            mode: mode, accessibility: accessibility)
            }
        }

        // Once in file order, once reversed: the answer must be the same.
        for (label, list) in [("", tracks), (" (reversed)", Array(tracks.reversed()))] {
            if !label.isEmpty { reversedRuns += 1 }
            checks += 1
            if Self.expectsError(c) {
                // Only a thrown error passes. (Not `try?`: that would take
                // "chose no track" — a returned nil — for a refusal.)
                do {
                    let value = try select(list)
                    fail(id + label, "must be refused with an error, but returned \(value ?? "null")")
                } catch {
                    // Refused, as required.
                }
            } else {
                do {
                    let got = try select(list)
                    if got != expected {
                        fail(id + label, "got \(got ?? "null"), expected \(expected ?? "null")")
                    }
                } catch {
                    fail(id + label, "threw \(error), expected \(expected ?? "null")")
                }
            }
        }
    }
}
