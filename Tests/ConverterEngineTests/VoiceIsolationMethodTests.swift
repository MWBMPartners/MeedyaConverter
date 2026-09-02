// ============================================================================
// MeedyaConverter — VoiceIsolation method tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards that the fake "ML Sound Analysis" method was removed (it ran the same
/// bandpass as the basic method) and pins the surviving real bandpass formula.
final class VoiceIsolationMethodTests: XCTestCase {

    func test_fakeMLMethodRemoved() {
        XCTAssertEqual(Set(IsolationMethod.allCases), [.ffmpegHighpass, .spectralSubtraction])
        XCTAssertNil(IsolationMethod(rawValue: "visionSoundAnalysis"))
    }

    func test_bandpassFormula() {
        let config = VoiceIsolationConfig(method: .ffmpegHighpass, sensitivity: 0.5, outputFormat: nil)
        let args = VoiceIsolator.buildFFmpegIsolationArguments(
            inputPath: "/in.wav", outputPath: "/out.wav", config: config)
        guard let i = args.firstIndex(of: "-af"), i + 1 < args.count else { return XCTFail("no -af: \(args)") }
        let af = args[i + 1]
        XCTAssertTrue(af.contains("highpass=f=300:poles=2"), af)   // 100 + 0.5*400
        XCTAssertTrue(af.contains("lowpass=f=3750:poles=2"), af)   // 5000 - 0.5*2500
    }
}
