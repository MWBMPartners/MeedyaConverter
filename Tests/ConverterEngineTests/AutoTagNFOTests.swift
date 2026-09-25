// ============================================================================
// MeedyaConverter — AutoTagNFOTests (Issue #508, commit 7/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pins `AutoTagNFOWriter.write`'s three rules — see that file's own header
// for why each one is deliberate:
//   1. an existing `.nfo` is left completely alone;
//   2. the output must already exist, or nothing is written;
//   3. nothing here ever throws, whatever the filesystem does.
//
// Pure filesystem tests: no network, no `UserDefaults`, no real
// `EncodingEngine.encode`. The end-to-end wiring — that the ENGINE calls this
// writer at the right moment, for the right jobs, and publishes the right
// event — is `AutoTagEncodeDeliveryTests`'s job, not this file's.
//
// Public API only (`import ConverterEngine`, no `@testable`), matching every
// other AutoTag test file in this module.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class AutoTagNFOTests: XCTestCase {

    // MARK: Fixtures

    /// A confident TMDB film match, reused by every test below. `source` is
    /// `.tmdb` so `MediaServerTagging.buildKodiMovieNFO` writes the
    /// `uniqueid type="tmdb"` row the content-check test looks for.
    private static let inception = MetadataResult(
        source: .tmdb,
        externalId: "27205",
        title: "Inception",
        year: 2010,
        overview: "A mind-bending thriller.",
        confidence: 0.95
    )

    // MARK: Helpers

    /// A fresh, empty folder for one test only — never shared with another
    /// test, so tests can run in parallel without interfering with each
    /// other's files.
    private func makeScratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("autotag-nfo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Written

    func test_write_savesTheSidecar_withTheFilmsTitleYearAndTMDBId() throws {
        let folder = try makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputURL = folder.appendingPathComponent("Inception (2010).mp4")
        // Content doesn't matter to the writer — only that the path exists.
        try Data("a fake encoded output".utf8).write(to: outputURL)

        let outcome = AutoTagNFOWriter.write(film: Self.inception, nextTo: outputURL)

        let expectedPath = folder.appendingPathComponent("Inception (2010).nfo").path
        XCTAssertEqual(outcome, .written(path: expectedPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath), "the .nfo was actually saved to disk")

        let nfo = try String(contentsOfFile: expectedPath, encoding: .utf8)
        XCTAssertTrue(nfo.contains("<title>Inception</title>"), "the film's title:\n\(nfo)")
        XCTAssertTrue(nfo.contains("<year>2010</year>"), "the film's year:\n\(nfo)")
        XCTAssertTrue(nfo.contains("uniqueid type=\"tmdb\">27205</uniqueid>"), "the TMDB id:\n\(nfo)")
    }

    // MARK: - An existing .nfo is left alone

    func test_write_anExistingNFO_isLeftCompletelyUnchanged() throws {
        let folder = try makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputURL = folder.appendingPathComponent("Inception (2010).mp4")
        try Data("a fake encoded output".utf8).write(to: outputURL)
        let nfoURL = folder.appendingPathComponent("Inception (2010).nfo")
        // Written BEFORE `write` is ever called, so the ONLY way the writer
        // could see this file is `.withoutOverwriting`'s atomic refusal —
        // never a "check, then write" race this test's own setup could win.
        let original = "a hand-edited .nfo a real user made, with a poster path the scraper never knew about"
        try original.write(to: nfoURL, atomically: true, encoding: .utf8)

        let outcome = AutoTagNFOWriter.write(film: Self.inception, nextTo: outputURL)

        XCTAssertEqual(outcome, .leftExisting(path: nfoURL.path))
        let afterWrite = try String(contentsOf: nfoURL, encoding: .utf8)
        XCTAssertEqual(afterWrite, original, "not one byte of an existing .nfo may change")
    }

    // MARK: - The output is missing

    func test_write_theOutputDoesNotExist_fails_andWritesNothing() throws {
        let folder = try makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Deliberately never created.
        let outputURL = folder.appendingPathComponent("Inception (2010).mp4")

        let outcome = AutoTagNFOWriter.write(film: Self.inception, nextTo: outputURL)

        guard case .failed(let reason) = outcome else {
            return XCTFail("expected .failed when the output doesn't exist, got \(outcome)")
        }
        XCTAssertFalse(reason.isEmpty, "a plain-English reason, not a blank string")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("Inception (2010).nfo").path),
            "nothing should be written when there is nowhere real to sit next to"
        )
    }

    // MARK: - An unwritable folder

    func test_write_anUnwritableFolder_fails_withoutThrowing() throws {
        let folder = try makeScratchFolder()
        let restrictedFolder = folder.appendingPathComponent("restricted")
        try FileManager.default.createDirectory(at: restrictedFolder, withIntermediateDirectories: true)
        let outputURL = restrictedFolder.appendingPathComponent("Inception (2010).mp4")
        try Data("a fake encoded output".utf8).write(to: outputURL)

        // Read + execute, no write: creating a NEW file (the .nfo) inside
        // this folder must now fail with a permission error — a DIFFERENT
        // failure from "the file already exists", which the previous test
        // covers.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: restrictedFolder.path)
        defer {
            // Write permission must be restored BEFORE removal: deleting the
            // pre-existing output file from inside `restrictedFolder` needs
            // write access to `restrictedFolder` itself, the very thing this
            // test just took away.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restrictedFolder.path)
            try? FileManager.default.removeItem(at: folder)
        }

        // The call itself must not throw — `write` returns a value, so a
        // compiler error here would already prove that much; this test is
        // about what VALUE comes back for a real permission failure.
        let outcome = AutoTagNFOWriter.write(film: Self.inception, nextTo: outputURL)

        guard case .failed(let reason) = outcome else {
            return XCTFail("expected .failed for a read-only folder, got \(outcome)")
        }
        XCTAssertFalse(reason.isEmpty, "a plain-English reason, not a blank string")
    }
}
