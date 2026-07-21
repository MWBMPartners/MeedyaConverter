// ============================================================================
// MeedyaConverter — ConverterEngine unit tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Split from ConverterEngineTests.swift (re #452) to keep the test file
// under a manageable size. This file extends `ConverterEngineTests`
// (declared in ConverterEngineTests.swift) with a cohesive group of test
// methods. No test body, name, or assertion was changed during the split.
// ============================================================================

import XCTest
import ConverterEngine

extension ConverterEngineTests {
    // MARK: - SuiteCore (#373)

    /// Verifies that the suite-core availability flag reflects the build flag.
    /// In CI (without SUITE_CORE=1 set) this must be false so the fallback
    /// codepaths are exercised.
    func test_suiteCore_availabilityMatchesBuildFlag() {
        #if SUITE_CORE
        XCTAssertTrue(SuiteCoreAvailability.isAvailable)
        XCTAssertNotNil(SuiteCoreAvailability.linkedVersion)
        #else
        XCTAssertFalse(SuiteCoreAvailability.isAvailable)
        XCTAssertNil(SuiteCoreAvailability.linkedVersion)
        #endif
    }

    /// The smoke test must throw `.notCompiledIn` when the suite-core
    /// dependency is absent.
    func test_suiteCore_smokeTestThrowsWhenNotCompiledIn() {
        #if !SUITE_CORE
        XCTAssertThrowsError(try SuiteCoreSmokeTest.ping()) { error in
            guard let bridgeError = error as? SuiteCoreBridgeError else {
                XCTFail("Expected SuiteCoreBridgeError, got \(error)")
                return
            }
            if case .notCompiledIn = bridgeError {
                // expected
            } else {
                XCTFail("Expected .notCompiledIn, got \(bridgeError)")
            }
        }
        #endif
    }

    /// Verifies the SuiteCoreCodecDescriptor is Codable and preserves values
    /// through an encode/decode round trip.
    func test_suiteCore_codecDescriptorRoundTrip() throws {
        let original = SuiteCoreCodecDescriptor(
            identifier: "eac3_atmos",
            displayName: "Dolby Digital Plus with Atmos",
            isLossless: false,
            isSpatial: true,
            channelLayout: "7.1.4"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SuiteCoreCodecDescriptor.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.channelLayout, "7.1.4")
    }

    /// Verifies fingerprint result round-trips through Codable.
    func test_suiteCore_fingerprintResultRoundTrip() throws {
        let original = SuiteCoreFingerprintResult(
            fingerprint: "AQADtEmSRImSJImSRImSJEmUJEn",
            durationSeconds: 184.52
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SuiteCoreFingerprintResult.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.durationSeconds, 184.52, accuracy: 0.0001)
    }

    // MARK: - SuiteCoreMetadataAdapter (#371)

    /// Without SUITE_CORE, `.automatic` backend routes all inline sources
    /// through the inline implementation.
    func test_suiteCoreMetadataAdapter_automaticBackendOffByDefault() {
        let adapter = SuiteCoreMetadataAdapter(backend: .automatic)
        #if !SUITE_CORE
        XCTAssertFalse(adapter.routesThroughSuiteCore(source: .tmdb))
        XCTAssertFalse(adapter.routesThroughSuiteCore(source: .tvdb))
        #endif
    }

    /// `.inlineOnly` always bypasses suite-core.
    func test_suiteCoreMetadataAdapter_inlineOnlyAlwaysFallsBack() {
        let adapter = SuiteCoreMetadataAdapter(backend: .inlineOnly)
        for source in MetadataSource.allCases {
            XCTAssertFalse(adapter.routesThroughSuiteCore(source: source))
        }
    }

    /// `.suiteCore` forces the suite-core path regardless of availability.
    func test_suiteCoreMetadataAdapter_forcedSuiteCoreRoutes() {
        let adapter = SuiteCoreMetadataAdapter(backend: .suiteCore)
        for source in MetadataSource.allCases {
            XCTAssertTrue(adapter.routesThroughSuiteCore(source: source))
        }
    }

    /// Forced suite-core backend must throw `.notCompiledIn` when unlinked.
    func test_suiteCoreMetadataAdapter_forcedSuiteCoreThrowsWhenAbsent() async {
        #if !SUITE_CORE
        let adapter = SuiteCoreMetadataAdapter(backend: .suiteCore)
        let query = MetadataSearchQuery(mediaType: .movie, title: "Dune")
        do {
            _ = try await adapter.search(source: .tmdb, query: query)
            XCTFail("Expected SuiteCoreBridgeError.notCompiledIn")
        } catch let error as SuiteCoreBridgeError {
            if case .notCompiledIn = error { return }
            XCTFail("Expected .notCompiledIn, got \(error)")
        } catch {
            XCTFail("Expected SuiteCoreBridgeError, got \(error)")
        }
        #endif
    }

    /// Request body encodes all fields and uses sorted JSON keys.
    func test_suiteCoreMetadataAdapter_requestBodyEncodesAllFields() throws {
        let query = MetadataSearchQuery(
            mediaType: .tvEpisode,
            title: "The Expanse",
            year: 2015,
            season: 3,
            episode: 7,
            artist: nil,
            album: nil,
            language: "en"
        )
        let data = try XCTUnwrap(
            SuiteCoreMetadataAdapter.buildSuiteCoreRequestBody(source: .tvdb, query: query)
        )
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["provider"] as? String, "tvdb")
        XCTAssertEqual(json["mediaType"] as? String, "episode")
        XCTAssertEqual(json["title"] as? String, "The Expanse")
        XCTAssertEqual(json["year"] as? Int, 2015)
        XCTAssertEqual(json["season"] as? Int, 3)
        XCTAssertEqual(json["episode"] as? Int, 7)
        XCTAssertEqual(json["language"] as? String, "en")
    }

    /// The advertised provider list differs depending on backend selection.
    func test_suiteCoreMetadataAdapter_providerListDiffers() {
        let inline = SuiteCoreMetadataAdapter(backend: .inlineOnly)
        let forced = SuiteCoreMetadataAdapter(backend: .suiteCore)
        XCTAssertLessThan(
            inline.availableProviderIdentifiers().count,
            forced.availableProviderIdentifiers().count
        )
    }

    // MARK: - SuiteCoreCodecClassifier (#372)

    /// FLAC classifies as lossless, non-spatial.
    func test_codecClassifier_flacIsLossless() {
        let d = SuiteCoreCodecClassifier.classify(ffprobeCodecName: "flac")
        XCTAssertTrue(d.isLossless)
        XCTAssertFalse(d.isSpatial)
        XCTAssertEqual(d.displayName, "FLAC")
    }

    /// Opus classifies as lossy, non-spatial.
    func test_codecClassifier_opusIsLossy() {
        let d = SuiteCoreCodecClassifier.classify(ffprobeCodecName: "opus")
        XCTAssertFalse(d.isLossless)
        XCTAssertFalse(d.isSpatial)
    }

    /// E-AC-3 JOC (Atmos) classifies as spatial.
    func test_codecClassifier_eac3AtmosIsSpatial() {
        let d = SuiteCoreCodecClassifier.classify(ffprobeCodecName: "eac3_atmos")
        XCTAssertTrue(d.isSpatial)
        XCTAssertFalse(d.isLossless)
    }

    /// TrueHD Atmos is both lossless and spatial.
    func test_codecClassifier_truehdAtmosIsLosslessAndSpatial() {
        let d = SuiteCoreCodecClassifier.classify(ffprobeCodecName: "truehd_atmos")
        XCTAssertTrue(d.isLossless)
        XCTAssertTrue(d.isSpatial)
    }

    /// Channel layout alone can promote a codec to spatial (7.1.4 height channels).
    func test_codecClassifier_spatialChannelLayoutPromotesSpatial() {
        let d = SuiteCoreCodecClassifier.classify(
            ffprobeCodecName: "eac3",
            channelLayout: "7.1.4"
        )
        XCTAssertTrue(d.isSpatial)
    }

    /// Unknown codecs fall back to an uppercased identifier as display name.
    func test_codecClassifier_unknownCodecFallback() {
        let d = SuiteCoreCodecClassifier.classify(ffprobeCodecName: "xyz_custom")
        XCTAssertEqual(d.identifier, "xyz_custom")
        XCTAssertEqual(d.displayName, "XYZ_CUSTOM")
        XCTAssertFalse(d.isLossless)
        XCTAssertFalse(d.isSpatial)
    }

    /// PCM variants are all lossless.
    func test_codecClassifier_pcmIsLossless() {
        for codec in ["pcm_s16le", "pcm_s24le", "pcm_f32le"] {
            XCTAssertTrue(
                SuiteCoreCodecClassifier.isLossless(ffprobeCodecName: codec),
                "Expected \(codec) to be classified lossless"
            )
        }
    }

    // MARK: - MediaStream + SuiteCoreCodecClassifier adoption (#372)
    //
    // `SuiteCoreCodecClassifier` shipped in #372 with a built-in fallback
    // table but zero production call sites. These tests cover its
    // adoption: `MediaStream.suiteCoreCodecDescriptor` (populated by
    // `FFmpegProbe.parseStream` from `codec_name` / `channel_layout` /
    // `sample_fmt`) and the `isLosslessAudio` / `isSpatialAudio`
    // convenience properties the Stream Inspector badges read from.

    /// New field defaults to nil so every pre-existing `MediaStream(...)`
    /// call site (which never mentions it) keeps compiling and behaving
    /// exactly as before.
    func test_mediaStream_suiteCoreCodecDescriptor_defaultsToNilWhenOmitted() {
        let stream = MediaStream(streamIndex: 0, streamType: .audio, codecName: "aac")
        XCTAssertNil(stream.suiteCoreCodecDescriptor)
        XCTAssertNil(stream.isLosslessAudio)
        XCTAssertNil(stream.isSpatialAudio)
    }

    /// A TrueHD stream in a 7.1.4 (Atmos bed) layout classifies as both
    /// lossless and spatial — mirrors what `FFmpegProbe` would attach
    /// after calling `SuiteCoreCodecClassifier.classify`.
    func test_mediaStream_suiteCoreCodecDescriptor_losslessSpatialTrueHDAtmos() {
        let descriptor = SuiteCoreCodecClassifier.classify(
            ffprobeCodecName: "truehd",
            channelLayout: "7.1.4"
        )
        let stream = MediaStream(
            streamIndex: 1,
            streamType: .audio,
            codecName: "truehd",
            channelLayout: ChannelLayout(channelCount: 12, layoutName: "7.1.4"),
            suiteCoreCodecDescriptor: descriptor
        )
        XCTAssertEqual(stream.isLosslessAudio, true)
        XCTAssertEqual(stream.isSpatialAudio, true)
    }

    /// A plain AAC stereo stream is neither lossless nor spatial.
    func test_mediaStream_suiteCoreCodecDescriptor_lossyStereoIsNeitherLosslessNorSpatial() {
        let descriptor = SuiteCoreCodecClassifier.classify(
            ffprobeCodecName: "aac",
            channelLayout: "stereo"
        )
        let stream = MediaStream(
            streamIndex: 2,
            streamType: .audio,
            codecName: "aac",
            channelLayout: ChannelLayout(channelCount: 2, layoutName: "stereo"),
            suiteCoreCodecDescriptor: descriptor
        )
        XCTAssertEqual(stream.isLosslessAudio, false)
        XCTAssertEqual(stream.isSpatialAudio, false)
    }

    /// The field round-trips through `Codable` when populated.
    func test_mediaStream_suiteCoreCodecDescriptor_codableRoundTrip() throws {
        let descriptor = SuiteCoreCodecClassifier.classify(
            ffprobeCodecName: "eac3_atmos",
            channelLayout: "5.1.4"
        )
        let original = MediaStream(
            streamIndex: 3,
            streamType: .audio,
            codecName: "eac3_atmos",
            suiteCoreCodecDescriptor: descriptor
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MediaStream.self, from: data)
        XCTAssertEqual(decoded.suiteCoreCodecDescriptor, original.suiteCoreCodecDescriptor)
        XCTAssertEqual(decoded.isLosslessAudio, false)
        XCTAssertEqual(decoded.isSpatialAudio, true)
    }

    /// A `MediaStream` JSON payload persisted *before* #372 (no
    /// `suiteCoreCodecDescriptor` key at all — e.g. a saved encoding job
    /// from an older app version) must still decode successfully, with
    /// the new field resolving to nil rather than throwing.
    func test_mediaStream_decodesLegacyJSONWithoutSuiteCoreCodecDescriptorKey() throws {
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "streamIndex": 0,
            "streamType": "audio",
            "codecName": "aac",
            "isDefault": true,
            "isForced": false,
            "isEnabled": true,
            "hdrFormats": [],
            "isStereo3D": false
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(MediaStream.self, from: data)
        XCTAssertEqual(decoded.codecName, "aac")
        XCTAssertNil(decoded.suiteCoreCodecDescriptor)
        XCTAssertNil(decoded.isLosslessAudio)
        XCTAssertNil(decoded.isSpatialAudio)
    }

}
