// ============================================================================
// MeedyaConverter — OutputPathResolver mirror tests (#275)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards the mode-aware directory resolution the CLI batch path now uses
/// (#275) — a recursive batch used to flatten the source tree.
final class OutputPathResolverMirrorTests: XCTestCase {

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-opr-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func test_flatten_returnsOutputDirUnchanged() {
        let out = URL(fileURLWithPath: "/out")
        let dir = OutputPathResolver.resolveOutputDirectory(
            inputURL: URL(fileURLWithPath: "/src/a/b/clip.mov"),
            baseInputDir: URL(fileURLWithPath: "/src"),
            outputDir: out, mode: .flatten)
        XCTAssertEqual(dir, out)
    }

    func test_mirror_reproducesRelativeSubtreeAndCreatesIt() {
        let base = tempDir(); let out = tempDir()
        defer { try? FileManager.default.removeItem(at: base); try? FileManager.default.removeItem(at: out) }
        let input = base.appendingPathComponent("a/b/clip.mov")
        let dir = OutputPathResolver.resolveOutputDirectory(
            inputURL: input, baseInputDir: base, outputDir: out, mode: .mirror)
        XCTAssertEqual(dir.path, out.appendingPathComponent("a/b").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path), "mirror must create the subtree")
    }

    func test_mirror_nilBase_degradesToOutputDir() {
        let out = URL(fileURLWithPath: "/out")
        let dir = OutputPathResolver.resolveOutputDirectory(
            inputURL: URL(fileURLWithPath: "/src/a/clip.mov"),
            baseInputDir: nil, outputDir: out, mode: .mirror)
        XCTAssertEqual(dir, out)
    }

    func test_mirror_inputNotUnderBase_degradesToOutputDir() {
        let out = URL(fileURLWithPath: "/out")
        let dir = OutputPathResolver.resolveOutputDirectory(
            inputURL: URL(fileURLWithPath: "/elsewhere/clip.mov"),
            baseInputDir: URL(fileURLWithPath: "/src"),
            outputDir: out, mode: .mirror)
        XCTAssertEqual(dir, out)
    }

    /// A file directly in the base (no subfolder) mirrors to the output root.
    func test_mirror_fileAtBaseRoot_isOutputDir() {
        let base = tempDir(); let out = tempDir()
        defer { try? FileManager.default.removeItem(at: base); try? FileManager.default.removeItem(at: out) }
        let input = base.appendingPathComponent("clip.mov")
        let dir = OutputPathResolver.resolveOutputDirectory(
            inputURL: input, baseInputDir: base, outputDir: out, mode: .mirror)
        XCTAssertEqual(dir, out)
    }
}
