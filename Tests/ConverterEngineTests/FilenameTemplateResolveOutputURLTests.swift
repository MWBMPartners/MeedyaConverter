// ============================================================================
// MeedyaConverter — FilenameTemplate.resolveOutputURL tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Tests for `FilenameTemplate.resolveOutputURL(sourceFile:profile:
// outputDirectory:fileExtension:overwriteExisting:date:)`, added alongside
// the completeness-audit fix for `SettingsView.overwriteExisting`
// (previously persisted but never read by any encoding path).
//
// This is the one piece of *pure, public* `ConverterEngine` logic that fix
// introduced — the wiring itself (reading the `UserDefaults` key in
// `AppViewModel.enqueueSelectedFile()`) lives in the app target, which
// cannot be imported by tests (see the policy note at the top of
// `ConverterEngineTests.swift`), so that half is inspection-only.
//
// Uses plain `import ConverterEngine` — every method under test here is
// public API.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class FilenameTemplateResolveOutputURLTests: XCTestCase {

    // MARK: - Fixtures

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilenameTemplateResolveOutputURLTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeSourceFile(named name: String = "movie") -> MediaFile {
        MediaFile(fileURL: URL(fileURLWithPath: "/tmp/\(name).mov"))
    }

    // MARK: - No Collision

    /// With no existing file at the resolved path, `overwriteExisting`
    /// true or false must resolve to the exact same URL.
    func test_resolveOutputURL_noCollision_bothModesAgree() {
        let template = FilenameTemplate(template: "{title}")
        let source = makeSourceFile(named: "no_collision")
        let profile = EncodingProfile.webStandard

        let overwriteURL = template.resolveOutputURL(
            sourceFile: source, profile: profile,
            outputDirectory: tempDirectory, fileExtension: "mp4",
            overwriteExisting: true
        )
        let renameURL = template.resolveOutputURL(
            sourceFile: source, profile: profile,
            outputDirectory: tempDirectory, fileExtension: "mp4",
            overwriteExisting: false
        )

        XCTAssertEqual(overwriteURL, renameURL)
        XCTAssertEqual(overwriteURL.lastPathComponent, "no_collision.mp4")
    }

    // MARK: - Collision, overwriteExisting: false

    /// The pre-existing default behaviour: a collision at the resolved
    /// path gets a numeric suffix rather than being overwritten.
    func test_resolveOutputURL_collision_overwriteFalse_appendsSuffix() throws {
        let template = FilenameTemplate(template: "{title}")
        let source = makeSourceFile(named: "collide")
        let profile = EncodingProfile.webStandard

        let existing = tempDirectory.appendingPathComponent("collide.mp4")
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let resolved = template.resolveOutputURL(
            sourceFile: source, profile: profile,
            outputDirectory: tempDirectory, fileExtension: "mp4",
            overwriteExisting: false
        )

        XCTAssertEqual(resolved.lastPathComponent, "collide_1.mp4")
        XCTAssertEqual(
            resolved,
            template.resolveWithCollisionHandling(
                sourceFile: source, profile: profile,
                outputDirectory: tempDirectory, fileExtension: "mp4"
            ),
            "overwriteExisting: false must match the existing resolveWithCollisionHandling behaviour exactly."
        )
    }

    /// Multiple collisions increment the suffix, matching
    /// `resolveWithCollisionHandling`'s documented `_1`, `_2`, ... scheme.
    func test_resolveOutputURL_collision_overwriteFalse_incrementsSuffix() throws {
        let template = FilenameTemplate(template: "{title}")
        let source = makeSourceFile(named: "multi")
        let profile = EncodingProfile.webStandard

        FileManager.default.createFile(atPath: tempDirectory.appendingPathComponent("multi.mp4").path, contents: Data())
        FileManager.default.createFile(atPath: tempDirectory.appendingPathComponent("multi_1.mp4").path, contents: Data())

        let resolved = template.resolveOutputURL(
            sourceFile: source, profile: profile,
            outputDirectory: tempDirectory, fileExtension: "mp4",
            overwriteExisting: false
        )

        XCTAssertEqual(resolved.lastPathComponent, "multi_2.mp4")
    }

    // MARK: - Collision, overwriteExisting: true

    /// With `overwriteExisting: true`, an existing file at the resolved
    /// path is not suffixed — the plain resolved path is returned so the
    /// caller (FFmpeg's own `-y`) overwrites it in place.
    func test_resolveOutputURL_collision_overwriteTrue_reusesExistingPath() throws {
        let template = FilenameTemplate(template: "{title}")
        let source = makeSourceFile(named: "reuse")
        let profile = EncodingProfile.webStandard

        let existing = tempDirectory.appendingPathComponent("reuse.mp4")
        FileManager.default.createFile(atPath: existing.path, contents: Data("stale output".utf8))

        let resolved = template.resolveOutputURL(
            sourceFile: source, profile: profile,
            outputDirectory: tempDirectory, fileExtension: "mp4",
            overwriteExisting: true
        )

        XCTAssertEqual(resolved, existing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path), "resolveOutputURL itself must not delete or touch the existing file — only the caller's subsequent encode does.")
    }
}
