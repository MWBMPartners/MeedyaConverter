// ============================================================================
// MeedyaConverter — SettingsCommandProcessTests (Issue #506 commit 7)
// Tests/MeedyaConvertTests/SettingsCommandProcessTests.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// #506 plan §7 test 9: end-to-end tests for `meedya-convert settings export`
// and `meedya-convert settings import`, run as the REAL BUILT BINARY via
// `Process` — the only way to test this CLI target at all, since Swift does
// not allow a second `@main` type inside this test bundle
// (`MeedyaConvertTests.swift`'s own header explains this; see also
// `Package.swift`'s comment on why this target depends on `ConverterEngine`
// and not on `meedya-convert` itself).
//
// WHY THIS FILE DOES NOT VALIDATE `--format json` AGAINST THE SCHEMA
// DIRECTLY. `SettingsSchemaMiniValidator` lives inside
// `Tests/ConverterEngineTests`, a different test target this one cannot
// import. Rather than duplicate that checker here (two copies that could
// drift), `SettingsCLIReportTests` (ConverterEngineTests) already proves
// that `SettingsCLIReport` — the exact function
// `Sources/meedya-convert/Commands/SettingsCommand.swift` calls to build
// its `--format json` output — produces reports that validate against
// `docs/schemas/settings-cli-report-v1.schema.json`. What is left for THIS
// file to prove is narrower, and just as real: that the actual binary,
// launched as a subprocess, calls that function and prints exactly what it
// returns. So these tests decode the printed JSON with a plain
// `JSONDecoder` into `MinimalSettingsReport` (below) and check the handful
// of fields that tell "the report shape from the engine" apart from
// "something else got printed" — they do not re-implement schema checking.
//
// SAFETY: NO REAL DOMAIN, NO REAL KEYCHAIN SERVICE. Every run below passes
// `--defaults-suite` (an absolute path inside this test's own temporary
// folder — never a plain suite name, which would live in
// `~/Library/Preferences` and could not be reliably cleaned up; see
// `SettingsTransferFixture`'s file overview in ConverterEngineTests for the
// same reasoning), `--profiles-dir`, `--api-keys-dir` and
// `--keychain-service`, all pointing at this run's own throwaway folder.
// `--categories` is deliberately kept to `general,encoding,encodingProfiles`
// throughout this file — NEVER `connections` — because the SMTP presence
// check (`SMTPPasswordKeychain`) has no override reachable from outside the
// engine module (see `SettingsCommand.swift`'s file overview): selecting
// "Connections" would make the real CLI binary ask the REAL, PRODUCTION SMTP
// Keychain service whether an item exists — an attributes-only existence
// check, never a read of its value, but still contact with something real,
// which the owner's safety rule for this work says plainly not to do. Every
// OTHER Keychain-backed check this file's scenarios can reach (the TMDB "is
// a key saved?" presence check, reached via the "encoding" group's
// `tmdbKey`) IS redirected, via `--api-keys-dir`/`--keychain-service`, to a
// throwaway service unique to each test. `tearDown` deletes the whole
// temporary folder; nothing here writes to the Keychain at all (the
// presence check only ever reads), so there is nothing to delete there —
// confirmed by hand with `security find-generic-password` against this
// file's throwaway service names before this commit (see the commit
// message's Verification section).
//
// NOT RUN BY THE LOCAL HARNESS. `.claude/local-test-harness.md` (its
// "Limits" §6) says plainly: "CLI tests: not attempted. They would need
// swift-argument-parser linked in." This file could only be type-checked
// locally (`swiftc -typecheck`), not compiled into a runnable harness
// binary the way an engine test can. It is exercised for real only by
// `swift test` in CI, and by hand — the exact scenarios below were run by
// hand against the built binary before this file was written, and their
// output is quoted in the commit message's Verification section.
// ---------------------------------------------------------------------------

import XCTest
import Foundation

final class SettingsCommandProcessTests: XCTestCase {

    /// How long a single `meedya-convert` invocation may run before this
    /// test terminates it and fails — the plan's own "Watchdog: 30 s per
    /// run, then terminate and fail (W16)".
    private static let watchdogSeconds: TimeInterval = 30

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-convert-settings-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    // MARK: - Locating the built binary

    /// The directory the test bundle itself was built into — the same
    /// products directory `meedya-convert` lands in, per the commented
    /// skeleton this file replaces (`MeedyaConvertTests.swift`'s own
    /// "Future Integration Test Skeleton").
    private var productsDirectory: URL? {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        return nil
    }

    /// The built `meedya-convert` binary, or nil if this run's products
    /// directory doesn't have one (a `swiftc -typecheck`-only run, or a
    /// build that didn't produce it — the plan's own "skip if it isn't
    /// there; CI builds it first").
    private var binaryURL: URL? {
        guard let dir = productsDirectory else { return nil }
        let url = dir.appendingPathComponent("meedya-convert")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Skips the calling test with a clear reason when the binary isn't
    /// available, rather than failing — matching the plan's "skip if it
    /// isn't there".
    private func requireBinary() throws -> URL {
        guard let binaryURL else {
            throw XCTSkip("meedya-convert was not found in the products directory; CI builds it before running this test.")
        }
        return binaryURL
    }

    // MARK: - Running the binary

    struct CLIResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs `meedya-convert` with `arguments`, under the watchdog above.
    /// Reads both pipes only after the process has exited (or been killed),
    /// which is safe here because every scenario's output is a short
    /// report — nowhere near a pipe buffer's size.
    private func run(_ binary: URL, _ arguments: [String]) throws -> CLIResult {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        let deadline = Date().addingTimeInterval(Self.watchdogSeconds)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            XCTFail(
                "meedya-convert did not finish within \(Int(Self.watchdogSeconds))s "
                    + "(arguments: \(arguments)) — terminated by the test's own watchdog (W16)."
            )
        } else {
            process.waitUntilExit()
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    // MARK: - A throwaway world per scenario

    /// One scenario's throwaway settings suite, profiles folder, API-key
    /// folder and Keychain service — all inside this TEST's `root`, so
    /// `tearDown` removes everything at once. The suite is named by an
    /// absolute path (never a plain name), for the same reason
    /// `SettingsTransferFixture` uses one in ConverterEngineTests: a plain
    /// name lives in `~/Library/Preferences`, which macOS keeps rewriting
    /// for a second or two after it is removed.
    private struct Scenario {
        let suitePath: String
        let profilesDir: String
        let apiKeysDir: String
        let keychainService: String

        /// The four hidden flags every invocation in this file passes, so
        /// nothing ever touches the real settings domain, the real profiles
        /// folder, or the real API-key Keychain service.
        var testFlags: [String] {
            ["--defaults-suite", suitePath, "--profiles-dir", profilesDir,
             "--api-keys-dir", apiKeysDir, "--keychain-service", keychainService]
        }
    }

    private func makeScenario(_ label: String) -> Scenario {
        let unique = UUID().uuidString
        return Scenario(
            suitePath: root.appendingPathComponent("\(label)-\(unique).plist").path,
            profilesDir: root.appendingPathComponent("\(label)-profiles-\(unique)").path,
            apiKeysDir: root.appendingPathComponent("\(label)-apikeys-\(unique)").path,
            keychainService: "MeedyaConverter.Tests.SettingsCLI.\(label).\(unique)"
        )
    }

    /// Seeds `values` directly into `suitePath`'s domain — the same
    /// mechanism `meedya-convert` itself reads (`persistentDomain(forName:)`
    /// on a `UserDefaults(suiteName:)` opened on that same path).
    private func seed(_ suitePath: String, _ values: [String: Any]) {
        guard let defaults = UserDefaults(suiteName: suitePath) else {
            return XCTFail("UserDefaults(suiteName:) refused \(suitePath)")
        }
        defaults.removePersistentDomain(forName: suitePath)
        for (key, value) in values { defaults.set(value, forKey: key) }
        defaults.synchronize()
    }

    /// Reads `suitePath`'s domain back, calling `synchronize()` first — the
    /// plan's own note ("Call synchronize() before each run, because this
    /// reads settings across processes") applies just as much to READING a
    /// domain the CHILD process just wrote as to the writes themselves.
    private func readDomain(_ suitePath: String) -> [String: Any] {
        guard let defaults = UserDefaults(suiteName: suitePath) else { return [:] }
        defaults.synchronize()
        return defaults.persistentDomain(forName: suitePath) ?? [:]
    }

    // MARK: - export

    func test_export_writesFileWithNoPlantedSecret_exitZero() throws {
        let binary = try requireBinary()
        let scenario = makeScenario("export")
        let sentinel = "SENTINEL-\(UUID().uuidString)"
        // `webhookURL` is a registered "never" key (a credential): even
        // though "connections" is not in this test's --categories, seeding
        // it here and re-affirming its absence from the file is a cheap
        // extra check that a category mistake elsewhere could not leak it.
        seed(scenario.suitePath, [
            "appearanceMode": "Dark",
            "filenameTemplate": "{name}-{profile}",
            "webhookURL": "https://hooks.example.com/\(sentinel)",
        ])
        let file = root.appendingPathComponent("export-\(UUID().uuidString).json").path

        let result = try run(binary, ["settings", "export", file, "--categories", "general,encoding,encodingProfiles"]
            + scenario.testFlags)

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file), "export should have written \(file)")
        let contents = try String(contentsOfFile: file, encoding: .utf8)
        XCTAssertFalse(contents.contains(sentinel), "the exported file must never contain a planted secret")
        XCTAssertTrue(contents.contains("appearanceMode"))
    }

    // MARK: - import preview (no --apply)

    func test_importWithoutApply_writesNothing_exitZero() throws {
        let binary = try requireBinary()
        let sourceScenario = makeScenario("preview-source")
        seed(sourceScenario.suitePath, ["appearanceMode": "Dark", "filenameTemplate": "{name}-preview"])
        let file = root.appendingPathComponent("preview-\(UUID().uuidString).json").path
        let exportResult = try run(
            binary,
            ["settings", "export", file, "--categories", "general,encoding,encodingProfiles"] + sourceScenario.testFlags
        )
        XCTAssertEqual(exportResult.exitCode, 0, "setup export failed: \(exportResult.stderr)")

        let targetScenario = makeScenario("preview-target")
        let importResult = try run(
            binary,
            ["settings", "import", file, "--categories", "general,encoding,encodingProfiles"] + targetScenario.testFlags
        )

        XCTAssertEqual(importResult.exitCode, 0, "stderr: \(importResult.stderr)")
        XCTAssertTrue(importResult.stdout.contains("Nothing has been changed."))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: targetScenario.suitePath) == false
                || readDomain(targetScenario.suitePath).isEmpty,
            "a preview (no --apply) must write NOTHING to the target domain"
        )
    }

    // MARK: - import --apply

    func test_importWithApply_writesValues_jsonReportShapeIsRight_exitZero() throws {
        let binary = try requireBinary()
        let sourceScenario = makeScenario("apply-source")
        seed(sourceScenario.suitePath, ["appearanceMode": "Dark", "filenameTemplate": "{name}-apply"])
        let file = root.appendingPathComponent("apply-\(UUID().uuidString).json").path
        let exportResult = try run(
            binary,
            ["settings", "export", file, "--categories", "general,encoding,encodingProfiles"] + sourceScenario.testFlags
        )
        XCTAssertEqual(exportResult.exitCode, 0, "setup export failed: \(exportResult.stderr)")

        let targetScenario = makeScenario("apply-target")
        let importResult = try run(
            binary,
            ["settings", "import", file, "--apply", "--format", "json",
             "--categories", "general,encoding,encodingProfiles"] + targetScenario.testFlags
        )

        XCTAssertEqual(importResult.exitCode, 0, "stderr: \(importResult.stderr)")
        let target = readDomain(targetScenario.suitePath)
        XCTAssertEqual(target["appearanceMode"] as? String, "Dark")
        XCTAssertEqual(target["filenameTemplate"] as? String, "{name}-apply")

        // The JSON shape itself is proven against the real schema in
        // ConverterEngineTests (`SettingsCLIReportTests`, against the exact
        // function this binary calls). Here: decode what the real process
        // printed and check the handful of fields that tell "the engine's
        // report" apart from "something else" — see the file overview.
        guard let data = importResult.stdout.data(using: .utf8) else {
            return XCTFail("stdout was not valid UTF-8")
        }
        let report = try JSONDecoder().decode(MinimalSettingsReport.self, from: data)
        XCTAssertEqual(report.command, "import")
        XCTAssertEqual(report.applied, true)
        XCTAssertEqual(report.mode, "merge")
        XCTAssertFalse(report.categories.isEmpty)
        XCTAssertTrue(report.categories.contains { $0.category == "general" })
        // `generatedAt` must actually be an ISO-8601 date-time, not merely a
        // string that happens to be present.
        XCTAssertNotNil(ISO8601DateFormatter().date(from: report.generatedAt))
    }

    // MARK: - Invalid file

    func test_invalidFile_exitSix_writesNothing() throws {
        let binary = try requireBinary()
        let file = root.appendingPathComponent("not-json-\(UUID().uuidString).json").path
        try "this is not a settings file".write(toFile: file, atomically: true, encoding: .utf8)
        let scenario = makeScenario("invalid")

        let result = try run(
            binary,
            ["settings", "import", file, "--apply", "--categories", "general,encoding,encodingProfiles"]
                + scenario.testFlags
        )

        XCTAssertEqual(result.exitCode, 6)
        XCTAssertTrue(result.stderr.lowercased().contains("not") || result.stderr.contains("Nothing was changed"))
        XCTAssertTrue(readDomain(scenario.suitePath).isEmpty, "a refused file must write nothing")
    }

    func test_newerFormatFile_exitSix_writesNothing() throws {
        let binary = try requireBinary()
        let file = root.appendingPathComponent("newer-\(UUID().uuidString).json").path
        let newerFormat = #"{"format":"meedyaconverter.settings","version":99,"categories":{},"notIncluded":[]}"#
        try newerFormat.write(toFile: file, atomically: true, encoding: .utf8)
        let scenario = makeScenario("newer")

        let result = try run(
            binary,
            ["settings", "import", file, "--apply", "--categories", "general,encoding,encodingProfiles"]
                + scenario.testFlags
        )

        XCTAssertEqual(result.exitCode, 6)
        XCTAssertTrue(result.stderr.contains("newer version"))
        XCTAssertTrue(readDomain(scenario.suitePath).isEmpty)
    }

    func test_missingFile_exitThree() throws {
        let binary = try requireBinary()
        let scenario = makeScenario("missing")
        let missingPath = root.appendingPathComponent("does-not-exist-\(UUID().uuidString).json").path

        let result = try run(
            binary,
            ["settings", "import", missingPath, "--apply", "--categories", "general,encoding,encodingProfiles"]
                + scenario.testFlags
        )

        XCTAssertEqual(result.exitCode, 3)
    }

    func test_unknownCategory_exitTwo() throws {
        let binary = try requireBinary()
        let scenario = makeScenario("badcat")
        let file = root.appendingPathComponent("badcat-\(UUID().uuidString).json").path

        let result = try run(binary, ["settings", "export", file, "--categories", "bogus"] + scenario.testFlags)

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file))
    }
}

// MARK: - A minimal, hand-written decode of the JSON report

/// Only the fields this file's tests actually check — deliberately NOT a
/// full mirror of `SettingsCLIReportSchema` (that would duplicate a
/// definition that already lives, once, in `ConverterEngineTests`). Extra
/// fields in the real report are simply ignored by `JSONDecoder`.
private struct MinimalSettingsReport: Decodable {
    struct Category: Decodable {
        let category: String
    }
    let command: String
    let applied: Bool?
    let mode: String?
    let generatedAt: String
    let categories: [Category]
}
