// ============================================================================
// MeedyaConverter — ProfileImportSubtitleTonemapTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `EncodingProfileStore.importProfile(from:)` and `ProfileSharing
// .importFromJSON` each field-by-field reconstruct the decoded
// `EncodingProfile` (to force a fresh UUID and `isBuiltIn = false`), and
// both had silently dropped `subtitleTonemap` from that reconstruction —
// an imported or shared profile with subtitle HDR tone-mapping configured
// came back with `subtitleTonemap == nil` regardless of what was exported.
// These tests pin the fix: a profile with a non-default `subtitleTonemap`
// must round-trip unchanged through both import paths, and a profile with
// no `subtitleTonemap` must keep decoding to `nil`.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class ProfileImportSubtitleTonemapTests: XCTestCase {

    // MARK: - Fixtures

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-import-subtitle-tonemap-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    /// A profile whose `subtitleTonemap` is deliberately non-default in
    /// every field, so a naive `nil` fallback (or a default-initialised
    /// replacement) in the reconstruction would be caught.
    private func makeProfileWithNonDefaultSubtitleTonemap() -> EncodingProfile {
        EncodingProfile(
            name: "HDR Subtitle Test Profile",
            subtitleTonemap: SubtitleTonemapConfig(
                sourceProfile: .dolbyVision,
                targetLuminanceNits: 203,
                preserveAlpha: false
            )
        )
    }

    // MARK: - EncodingProfileStore.importProfile(from:)

    func test_encodingProfileStore_importProfile_preservesSubtitleTonemap() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let original = makeProfileWithNonDefaultSubtitleTonemap()

        let data = try store.exportProfile(original)
        let imported = try store.importProfile(from: data)

        XCTAssertEqual(imported.subtitleTonemap, original.subtitleTonemap)
        XCTAssertNotEqual(imported.id, original.id, "Import should assign a fresh UUID")
    }

    func test_encodingProfileStore_importProfile_preservesNilSubtitleTonemap() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let original = EncodingProfile(name: "No Subtitle Tonemap")
        XCTAssertNil(original.subtitleTonemap)

        let data = try store.exportProfile(original)
        let imported = try store.importProfile(from: data)

        XCTAssertNil(imported.subtitleTonemap)
    }

    // MARK: - ProfileSharing.importFromJSON

    func test_profileSharing_importFromJSON_preservesSubtitleTonemap() throws {
        let original = makeProfileWithNonDefaultSubtitleTonemap()

        let data = try ProfileSharing.exportAsJSON(original)
        let imported = try ProfileSharing.importFromJSON(data)

        XCTAssertEqual(imported.subtitleTonemap, original.subtitleTonemap)
        XCTAssertNotEqual(imported.id, original.id, "Import should assign a fresh UUID")
    }

    func test_profileSharing_importFromJSON_preservesNilSubtitleTonemap() throws {
        let original = EncodingProfile(name: "No Subtitle Tonemap")

        let data = try ProfileSharing.exportAsJSON(original)
        let imported = try ProfileSharing.importFromJSON(data)

        XCTAssertNil(imported.subtitleTonemap)
    }
}
