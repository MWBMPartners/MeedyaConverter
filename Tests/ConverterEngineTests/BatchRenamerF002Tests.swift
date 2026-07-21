// ============================================================================
// MeedyaConverter — BatchRenamerF002Tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// Regression coverage for the F-002 POLISH follow-up (SECURITY.md):
/// `BatchRenamer.apply(files:rules:)` now routes its computed filename
/// through `PathSanitizer.sanitizeFilenameComponent` before calling
/// `appendingPathComponent`. Unlike the already-covered
/// `URL.lastPathComponent` sites, `apply`'s `stem` is rewritten by
/// arbitrary user-supplied find/replace (and regex-template)
/// `RenameRule`s, so a rule whose `replaceWith` contains a path
/// separator or `..` can genuinely produce a component that would
/// otherwise escape the file's own directory.
final class BatchRenamerF002Tests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchRenamerF002Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try super.tearDownWithError()
    }

    /// A rename rule whose replacement text contains a path separator
    /// and a parent-traversal sequence must not be able to move the
    /// file outside its own directory.
    func test_apply_ruleInjectingPathTraversal_staysWithinDirectory() throws {
        let originalURL = tempDir.appendingPathComponent("original.txt")
        try "hello".write(to: originalURL, atomically: true, encoding: .utf8)

        let rule = RenameRule(
            findPattern: "original",
            replaceWith: "../../../../tmp/escaped",
            isRegex: false
        )

        let results = try BatchRenamer.apply(files: [originalURL], rules: [rule])

        XCTAssertEqual(results.count, 1)
        let newURL = results[0]

        // The load-bearing assertion: the renamed file must still be
        // a child of the same directory it started in.
        XCTAssertEqual(
            newURL.deletingLastPathComponent().standardized.path,
            tempDir.standardized.path,
            "Renamed file escaped its directory: \(newURL.path)"
        )
        XCTAssertFalse(newURL.path.contains(".."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
    }

    /// Ordinary rename rules on ordinary filenames must be completely
    /// unaffected by the sanitiser (no-op for benign input).
    func test_apply_ordinaryRule_behavesAsBefore() throws {
        let originalURL = tempDir.appendingPathComponent("holiday-clip.mov")
        try "hello".write(to: originalURL, atomically: true, encoding: .utf8)

        let rule = RenameRule(findPattern: "holiday", replaceWith: "vacation", isRegex: false)

        let results = try BatchRenamer.apply(files: [originalURL], rules: [rule])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].lastPathComponent, "vacation-clip.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: results[0].path))
    }
}
