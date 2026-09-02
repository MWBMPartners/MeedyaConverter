// ============================================================================
// MeedyaConverter — FilterChainComposer / filter-graph staging tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards the compose helper the Filter Graph "Apply to Next Encode" path uses
/// to fold a staged graph onto the crop filter, and that the composed chain
/// reaches the encode's -vf / -af.
final class FilterGraphStagingTests: XCTestCase {

    private func value(_ args: [String], after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    func test_compose_joinsInOrderAndDropsEmpty() {
        XCTAssertEqual(FilterChainComposer.compose("crop=1:2:3:4", "scale=w=1:h=2"),
                       "crop=1:2:3:4,scale=w=1:h=2")
        XCTAssertNil(FilterChainComposer.compose(nil, "  "))
        XCTAssertEqual(FilterChainComposer.compose(nil, "eq=x"), "eq=x")
        XCTAssertNil(FilterChainComposer.compose(nil, nil))
    }

    func test_composedChainReachesVfAndAf() {
        var config = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/in.mkv"),
            outputURL: URL(fileURLWithPath: "/out.mp4"),
            profile: EncodingProfile(name: "t", videoCodec: .h264))
        config.videoFilterChain = "crop=1920:800:0:140,scale=w=1280:h=720"
        config.audioFilterChain = "loudnorm=I=-14"
        let args = config.buildArguments()
        XCTAssertEqual(value(args, after: "-vf"), "crop=1920:800:0:140,scale=w=1280:h=720", "\(args)")
        XCTAssertTrue(value(args, after: "-af")?.contains("loudnorm") == true, "\(args)")
    }
}
