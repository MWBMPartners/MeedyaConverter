// ============================================================================
// MeedyaConverter — deinterlace wiring tests (#324)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards that a deinterlace preset actually reaches the encode's `-vf` chain
/// (#324) — DeinterlaceConfig/Presets existed but had zero callers, so
/// selecting a preset could not change any encode.
final class DeinterlaceWiringTests: XCTestCase {

    private func vf(_ args: [String]) -> String? {
        guard let i = args.firstIndex(of: "-vf"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private func builder(passthrough: Bool = false, base: String? = nil,
                         deinterlace: DeinterlaceConfig?) -> FFmpegArgumentBuilder {
        var b = FFmpegArgumentBuilder()
        b.inputURL = URL(fileURLWithPath: "/in.mkv")
        b.outputURL = URL(fileURLWithPath: "/out.mp4")
        b.videoCodec = .h264
        b.videoPassthrough = passthrough
        b.videoFilterChain = base
        b.deinterlace = deinterlace
        return b
    }

    func test_deinterlace_isFirstVfStage() {
        let vfStr = vf(builder(base: "scale=1280:720", deinterlace: DeinterlacePresets.fast).build())
        XCTAssertNotNil(vfStr)
        XCTAssertTrue(vfStr!.hasPrefix("yadif"), "deinterlace must come first: \(vfStr!)")
        XCTAssertTrue(vfStr!.contains("scale=1280:720"), vfStr!)
        XCTAssertLessThan(vfStr!.range(of: "yadif")!.lowerBound,
                          vfStr!.range(of: "scale")!.lowerBound)
    }

    func test_deinterlace_qualityUsesBwdif() {
        let vfStr = vf(builder(deinterlace: DeinterlacePresets.quality).build())
        XCTAssertTrue(vfStr?.contains("bwdif") == true, "\(vfStr ?? "nil")")
    }

    func test_deinterlace_passthroughSkips() {
        let vfStr = vf(builder(passthrough: true, deinterlace: DeinterlacePresets.fast).build())
        XCTAssertNil(vfStr, "a copied stream cannot be filtered")
    }

    func test_profile_threadsDeinterlace() {
        let profile = EncodingProfile(name: "DI", videoCodec: .h264,
                                      deinterlace: DeinterlacePresets.fast)
        let args = profile.toArgumentBuilder(
            inputURL: URL(fileURLWithPath: "/in.mkv"),
            outputURL: URL(fileURLWithPath: "/out.mp4")).build()
        XCTAssertTrue(vf(args)?.contains("yadif") == true, "\(args)")
    }

    func test_presets_configs() {
        XCTAssertEqual(DeinterlacePresets.fast.filter, .yadif)
        XCTAssertEqual(DeinterlacePresets.quality.filter, .bwdif)
        XCTAssertEqual(DeinterlacePresets.quality.mode, 1, "quality doubles fps (field output)")
    }

    func test_profile_absentDeinterlaceDecodesToNil() throws {
        let withDI = EncodingProfile(name: "DI", deinterlace: DeinterlacePresets.fast)
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(withDI)) as! [String: Any]
        json.removeValue(forKey: "deinterlace")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: stripped)
        XCTAssertNil(decoded.deinterlace)
    }
}
