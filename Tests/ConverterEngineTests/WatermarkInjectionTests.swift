// ============================================================================
// MeedyaConverter — Watermark injection tests (#298)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards that a configured watermark is actually injected into the encode's
/// `-vf` chain — the #298 gap was a UI that previewed a filter string which
/// never reached an encode.
final class WatermarkInjectionTests: XCTestCase {

    // MARK: - Helpers

    /// The value FFmpeg receives after `-vf`, or nil if none was emitted.
    private func vfValue(_ args: [String]) -> String? {
        guard let i = args.firstIndex(of: "-vf"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private func builder(passthrough: Bool = false,
                         base: String? = nil,
                         watermark: OverlayWatermarkConfig?) -> FFmpegArgumentBuilder {
        var b = FFmpegArgumentBuilder()
        b.inputURL = URL(fileURLWithPath: "/in.mp4")
        b.outputURL = URL(fileURLWithPath: "/out.mp4")
        b.videoCodec = .h264
        b.videoPassthrough = passthrough
        b.videoFilterChain = base
        b.watermark = watermark
        return b
    }

    // MARK: - appendToVideoFilterChain — text

    func test_text_emptyChain_isJustDrawtext() {
        let out = WatermarkOverlay.appendToVideoFilterChain(
            "", config: OverlayWatermarkConfig(type: .text, text: "Copyright"))
        XCTAssertTrue(out.hasPrefix("drawtext="), out)
        XCTAssertTrue(out.contains("text='Copyright'"), out)
    }

    func test_text_appendsAfterExistingChainWithComma() {
        let out = WatermarkOverlay.appendToVideoFilterChain(
            "scale=1280:720", config: OverlayWatermarkConfig(type: .text, text: "X"))
        XCTAssertTrue(out.hasPrefix("scale=1280:720,drawtext="), out)
    }

    // MARK: - appendToVideoFilterChain — image (movie source, no 2nd input)

    func test_image_emptyChain_usesMovieSourceAndInOutPads() {
        let out = WatermarkOverlay.appendToVideoFilterChain(
            "", config: OverlayWatermarkConfig(type: .image, imagePath: "/logo.png"))
        XCTAssertTrue(out.contains("movie="), out)
        XCTAssertTrue(out.contains("[wm]"), out)
        XCTAssertTrue(out.contains("[in][wm]overlay="), out)
        XCTAssertTrue(out.hasSuffix("[out]"), out)
        XCTAssertFalse(out.contains("[base]"), "no base stage when chain is empty: \(out)")
    }

    func test_image_wrapsExistingChainAsBaseStage() {
        let out = WatermarkOverlay.appendToVideoFilterChain(
            "scale=1280:720", config: OverlayWatermarkConfig(type: .image, imagePath: "/logo.png"))
        XCTAssertTrue(out.contains("[in]scale=1280:720[base]"), out)
        XCTAssertTrue(out.contains("[base][wm]overlay="), out)
    }

    func test_image_noImagePath_isNoOp() {
        let chain = "scale=1280:720"
        XCTAssertEqual(
            WatermarkOverlay.appendToVideoFilterChain(chain, config: OverlayWatermarkConfig(type: .image, imagePath: nil)),
            chain)
        XCTAssertEqual(
            WatermarkOverlay.appendToVideoFilterChain(chain, config: OverlayWatermarkConfig(type: .image, imagePath: "")),
            chain)
    }

    func test_image_pathIsSingleQuotedAndQuotesAreBrokenOut() {
        let out = WatermarkOverlay.appendToVideoFilterChain(
            "", config: OverlayWatermarkConfig(type: .image, imagePath: "/tmp/my logo's:wm.png"))
        // Single-quoted (protects space + colon); the apostrophe is emitted
        // via the '\'' idiom (close, escaped bare quote, reopen).
        XCTAssertTrue(out.contains("movie='/tmp/my logo'\\''s:wm.png'"), out)
    }

    // MARK: - FFmpegArgumentBuilder integration

    func test_builder_textWatermark_addsDrawtextVf_noExtraInput() {
        let args = builder(watermark: OverlayWatermarkConfig(type: .text, text: "Hi")).build()
        XCTAssertTrue(vfValue(args)?.contains("drawtext=") == true, "\(args)")
        XCTAssertEqual(args.filter { $0 == "-i" }.count, 1, "text watermark needs no second input")
    }

    func test_builder_imageWatermark_addsMovieOverlay_noSecondInput_noMapRewrite() {
        let args = builder(watermark: OverlayWatermarkConfig(type: .image, imagePath: "/logo.png")).build()
        let vf = vfValue(args)
        XCTAssertTrue(vf?.contains("movie=") == true, "\(args)")
        XCTAssertTrue(vf?.contains("overlay=") == true, "\(args)")
        XCTAssertEqual(args.filter { $0 == "-i" }.count, 1, "movie-source overlay needs no second -i input")
        // The filtergraph output stays inside -vf, so mapping is untouched.
        XCTAssertFalse(args.contains("[vout]"), "\(args)")
    }

    func test_builder_passthroughVideo_skipsWatermark() {
        let args = builder(passthrough: true,
                           watermark: OverlayWatermarkConfig(type: .text, text: "Hi")).build()
        XCTAssertNil(vfValue(args), "a copied stream cannot be filtered: \(args)")
    }

    // MARK: - Profile threading + Codable back-compat

    func test_profile_threadsWatermarkIntoBuilder() {
        let profile = EncodingProfile(
            name: "WM", videoCodec: .h264,
            watermark: OverlayWatermarkConfig(type: .text, text: "Studio"))
        let args = profile.toArgumentBuilder(
            inputURL: URL(fileURLWithPath: "/in.mp4"),
            outputURL: URL(fileURLWithPath: "/out.mp4")).build()
        XCTAssertTrue(vfValue(args)?.contains("text='Studio'") == true, "\(args)")
    }

    func test_profile_roundTripsWatermark() throws {
        let original = EncodingProfile(
            name: "WM",
            watermark: OverlayWatermarkConfig(type: .image, imagePath: "/logo.png", opacity: 0.3))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: data)
        XCTAssertEqual(decoded.watermark, original.watermark)
    }

    /// A profile JSON written before #298 (no `watermark` key) decodes to nil.
    func test_profile_absentWatermarkKeyDecodesToNil() throws {
        let withWM = EncodingProfile(
            name: "WM", watermark: OverlayWatermarkConfig(type: .text, text: "x"))
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(withWM)) as! [String: Any]
        json.removeValue(forKey: "watermark")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: stripped)
        XCTAssertNil(decoded.watermark)
    }
}
