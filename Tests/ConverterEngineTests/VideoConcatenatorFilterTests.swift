// ============================================================================
// MeedyaConverter — VideoConcatenator filter/crossfade tests (#322)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards the re-encode filter-concat path now wired into ConcatenationView
/// (#322), and the crossfade-offset fix (transitions were all hardcoded to
/// offset=0, firing at t=0 instead of at each clip boundary).
final class VideoConcatenatorFilterTests: XCTestCase {

    private func filterComplex(_ args: [String]) -> String? {
        guard let i = args.firstIndex(of: "-filter_complex"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private func hasPair(_ args: [String], _ f: String, _ v: String) -> Bool {
        for i in args.indices.dropLast() where args[i] == f && args[i + 1] == v { return true }
        return false
    }
    private func urls(_ n: Int) -> [URL] { (0..<n).map { URL(fileURLWithPath: "/clip\($0).mov") } }

    // MARK: - Simple (no crossfade) re-encode join

    func test_simpleConcat_usesConcatFilterAndExplicitCodecs() {
        let args = VideoConcatenator.buildFilterConcatArguments(
            files: urls(3), outputPath: "/out.mp4", crossfade: nil)
        XCTAssertEqual(args.filter { $0 == "-i" }.count, 3)
        XCTAssertEqual(filterComplex(args), "[0:v][0:a][1:v][1:a][2:v][2:a]concat=n=3:v=1:a=1[v][a]")
        XCTAssertTrue(hasPair(args, "-map", "[v]") && hasPair(args, "-map", "[a]"), "\(args)")
        // Re-encode must name codecs explicitly, not lean on container defaults.
        XCTAssertTrue(hasPair(args, "-c:v", "libx264"), "\(args)")
        XCTAssertTrue(hasPair(args, "-c:a", "aac"), "\(args)")
        XCTAssertEqual(args.last, "/out.mp4")
    }

    // MARK: - Crossfade offsets

    func test_crossfade_twoClips_offsetIsFirstDurationMinusCrossfade() {
        let args = VideoConcatenator.buildFilterConcatArguments(
            files: urls(2), durations: [10, 10], outputPath: "/out.mp4", crossfade: 1)
        let fc = filterComplex(args) ?? ""
        // offset must be d0 - crossfade = 9.000, NOT the old hardcoded 0.
        XCTAssertTrue(fc.contains("offset=9.000"), fc)
        XCTAssertFalse(fc.contains("offset=0.000"), "the offset=0 bug must be gone: \(fc)")
        XCTAssertTrue(fc.contains("[0:v][1:v]xfade=transition=fade:duration=1.000"), fc)
        XCTAssertTrue(hasPair(args, "-map", "[vout]") && hasPair(args, "-map", "[aout]"))
    }

    func test_crossfade_threeClips_offsetsAreCumulative() {
        let args = VideoConcatenator.buildFilterConcatArguments(
            files: urls(3), durations: [10, 10, 10], outputPath: "/out.mp4", crossfade: 1)
        let fc = filterComplex(args) ?? ""
        // First join at d0 - c = 9; second join at (d0 + d1 - c) - c = 18.
        XCTAssertTrue(fc.contains("offset=9.000"), fc)
        XCTAssertTrue(fc.contains("offset=18.000"), fc)
    }

    /// Crossfade requested but durations missing/mismatched → safe fallback to a
    /// plain sequential join (never transitions at wrong offsets).
    func test_crossfade_withoutMatchingDurations_fallsBackToSimpleConcat() {
        let args = VideoConcatenator.buildFilterConcatArguments(
            files: urls(2), durations: [], outputPath: "/out.mp4", crossfade: 1)
        let fc = filterComplex(args) ?? ""
        XCTAssertTrue(fc.contains("concat=n=2:v=1:a=1[v][a]"), fc)
        XCTAssertFalse(fc.contains("xfade"), "must not emit crossfade without durations: \(fc)")
    }
}
