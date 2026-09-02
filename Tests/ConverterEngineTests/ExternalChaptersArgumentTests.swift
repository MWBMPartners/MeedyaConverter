// ============================================================================
// MeedyaConverter — external chapters embedding tests (#288)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards that scene-detected chapters can actually be embedded into an encode
/// (#288) — the view could export a chapter file but the job model had no way
/// to bake it into the output.
final class ExternalChaptersArgumentTests: XCTestCase {

    private func builder(chapters: URL?, additionalInputs: [URL] = []) -> FFmpegArgumentBuilder {
        var b = FFmpegArgumentBuilder()
        b.inputURL = URL(fileURLWithPath: "/in.mp4")
        b.outputURL = URL(fileURLWithPath: "/out.mp4")
        b.videoCodec = .h264
        b.additionalInputs = additionalInputs
        b.externalChaptersFile = chapters
        return b
    }

    /// Consecutive [flag, value] pair present in argv.
    private func hasPair(_ args: [String], _ flag: String, _ value: String) -> Bool {
        for i in args.indices.dropLast() where args[i] == flag && args[i + 1] == value { return true }
        return false
    }

    func test_noChapters_mapsSourceChapters() {
        let args = builder(chapters: nil).build()
        XCTAssertTrue(hasPair(args, "-map_chapters", "0"), "\(args)")
        XCTAssertEqual(args.filter { $0 == "-i" }.count, 1)
    }

    func test_withChapters_addsInputAndMapsFromIt() {
        let chapters = URL(fileURLWithPath: "/tmp/chapters.txt")
        let args = builder(chapters: chapters).build()
        // Second input is the chapters file...
        XCTAssertEqual(args.filter { $0 == "-i" }.count, 2, "\(args)")
        XCTAssertTrue(hasPair(args, "-i", "/tmp/chapters.txt"), "\(args)")
        // ...mapped from index 1, NOT from source (index 0).
        XCTAssertTrue(hasPair(args, "-map_chapters", "1"), "\(args)")
        XCTAssertFalse(hasPair(args, "-map_chapters", "0"), "\(args)")
    }

    /// The chapters input index accounts for other additional inputs.
    func test_withChapters_indexAccountsForAdditionalInputs() {
        let chapters = URL(fileURLWithPath: "/tmp/chapters.txt")
        let extra = URL(fileURLWithPath: "/tmp/logo.png")
        let args = builder(chapters: chapters, additionalInputs: [extra]).build()
        // inputURL(0), logo(1), chapters(2)
        XCTAssertTrue(hasPair(args, "-map_chapters", "2"), "\(args)")
    }
}
