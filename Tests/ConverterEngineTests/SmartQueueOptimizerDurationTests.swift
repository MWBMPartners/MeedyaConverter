// ============================================================================
// MeedyaConverter — SmartQueueOptimizer duration tests (#326)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Regression tests for #326: `estimatedSourceDuration` is now a real stored
/// field, so the duration-based strategies genuinely reorder — and, crucially,
/// setting it no longer smuggles a `__duration:` token onto the ffmpeg command
/// line.
final class SmartQueueOptimizerDurationTests: XCTestCase {

    private func job(_ name: String, duration: TimeInterval?) -> EncodingJobConfig {
        var config = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/\(name).mov"),
            outputURL: URL(fileURLWithPath: "/tmp/\(name).mp4"),
            profile: .webStandard
        )
        config.estimatedSourceDuration = duration
        return config
    }

    /// Setting the duration must NOT add anything to `extraArguments` — that is
    /// the landmine the old computed-property smuggling created, because
    /// `FFmpegArgumentBuilder` appends `extraArguments` verbatim to the command
    /// line, so a `__duration:123` token would have been passed to ffmpeg.
    func test_settingDuration_doesNotPolluteExtraArguments() {
        var config = job("a", duration: nil)
        config.estimatedSourceDuration = 123.4
        XCTAssertEqual(config.estimatedSourceDuration, 123.4)
        XCTAssertTrue(config.extraArguments.isEmpty, "duration leaked into extraArguments: \(config.extraArguments)")
        XCTAssertFalse(
            config.buildArguments().contains(where: { $0.contains("__duration") }),
            "the __duration token reached the ffmpeg command line"
        )
    }

    /// A real duration survives a Codable round-trip (it is a genuine field now).
    func test_duration_survivesCodableRoundTrip() throws {
        let original = job("b", duration: 42.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EncodingJobConfig.self, from: data)
        XCTAssertEqual(decoded.estimatedSourceDuration, 42.0)
    }

    /// Old persisted configs without the key decode with a nil duration. Built
    /// by encoding a real config and removing only the duration key, so the
    /// test stays robust to every other field the struct requires.
    func test_duration_absentKeyDecodesToNil() throws {
        let encoded = try JSONEncoder().encode(job("c", duration: 99.0))
        var dict = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        dict.removeValue(forKey: "estimatedSourceDuration")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(EncodingJobConfig.self, from: stripped)
        XCTAssertNil(decoded.estimatedSourceDuration)
    }

    /// shortestFirst / longestFirst genuinely reorder a mixed queue.
    func test_shortestAndLongestFirst_reorder() {
        let jobs = [job("long", duration: 300), job("short", duration: 30), job("mid", duration: 120)]

        let shortest = SmartQueueOptimizer.optimize(jobs: jobs, strategy: .shortestFirst)
        XCTAssertEqual(shortest.map { $0.estimatedSourceDuration }, [30, 120, 300])

        let longest = SmartQueueOptimizer.optimize(jobs: jobs, strategy: .longestFirst)
        XCTAssertEqual(longest.map { $0.estimatedSourceDuration }, [300, 120, 30])
    }

    /// Jobs with unknown duration sort to the end for shortestFirst.
    func test_unknownDuration_sortsLast() {
        let jobs = [job("unknown", duration: nil), job("known", duration: 60)]
        let shortest = SmartQueueOptimizer.optimize(jobs: jobs, strategy: .shortestFirst)
        XCTAssertEqual(shortest.first?.estimatedSourceDuration, 60)
        XCTAssertNil(shortest.last?.estimatedSourceDuration)
    }
}
