// ============================================================================
// MeedyaConverter — FFmpegProbeLanguageTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The probe reads each stream's language through the shared language policy
// (LANG-002) and keeps every role flag (TRACK-010/040). Driven through the
// real, public `analyze(url:)` with a fake `ffprobe` (a shell script that
// prints crafted JSON) — the pattern of FFmpegProbeSuiteCoreCodecTests.
// ============================================================================

import Foundation
import MediaLanguagePolicy
import XCTest
@testable import ConverterEngine

final class FFmpegProbeLanguageTests: XCTestCase {

    // MARK: - Fixture helpers

    private var fixturesToCleanUp: [String] = []

    override func tearDown() {
        for path in fixturesToCleanUp {
            try? FileManager.default.removeItem(atPath: path)
        }
        fixturesToCleanUp.removeAll()
        super.tearDown()
    }

    /// A fake `ffprobe` that prints `json`. Its own path doubles as the
    /// "media file" (analyze only checks the file exists).
    private func probe(json: String) async throws -> MediaFile {
        let jsonPath = NSTemporaryDirectory() + "ffprobe-language-\(UUID().uuidString).json"
        try json.write(toFile: jsonPath, atomically: true, encoding: .utf8)
        fixturesToCleanUp.append(jsonPath)
        let scriptPath = NSTemporaryDirectory() + "ffprobe-language-\(UUID().uuidString).sh"
        try "#!/bin/sh\ncat \"\(jsonPath)\"\n".write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        fixturesToCleanUp.append(scriptPath)
        return try await FFmpegProbe(ffprobePath: scriptPath).analyze(url: URL(fileURLWithPath: scriptPath))
    }

    /// One audio stream per language value (index = position), plus one with
    /// no language tag at all.
    private func json(languages: [String]) -> String {
        var streams = languages.enumerated().map { index, language in
            #"{"index": \#(index), "codec_type": "audio", "codec_name": "aac", "tags": {"language": "\#(language)"}}"#
        }
        streams.append(#"{"index": \#(languages.count), "codec_type": "audio", "codec_name": "aac"}"#)
        return #"{"streams": [\#(streams.joined(separator: ","))], "format": {}}"#
    }

    // MARK: - Languages (LANG-002)

    /// Old three-letter codes become canonical tags; a real tag is
    /// canonicalised; Matroska's old `fre-ca` form keeps its region.
    func test_probe_readsLanguagesThroughThePolicy() async throws {
        let file = try await probe(json: json(languages: ["eng", "ger", "deu", "fre-ca", "EN-gb", "zh-hant", "XXX", "yue"]))
        XCTAssertEqual(file.streams.map(\.language), ["en", "de", "de", "fr-CA", "en-GB", "zh-Hant", "und", "yue", nil])
        XCTAssertEqual(file.streams.compactMap(\.unrecognisedLanguage), [], "All of these were recognised")
    }

    /// A value that cannot be recognised is `und` — never a guess — with the
    /// original text kept for a person to fix (COMPAT-040).
    func test_probe_keepsUnrecognisedTextAndStoresUnd() async throws {
        let file = try await probe(json: json(languages: ["english", "zzz", "Deutsch"]))
        XCTAssertEqual(file.streams.prefix(3).map(\.language), ["und", "und", "und"])
        XCTAssertEqual(file.streams.prefix(3).map(\.unrecognisedLanguage), ["english", "zzz", "Deutsch"])
    }

    // MARK: - Roles (TRACK-010/040)

    /// Every disposition is kept, and turned into the policy's roles.
    func test_probe_keepsEveryRoleFlag() async throws {
        let file = try await probe(json: #"""
        {"format": {}, "streams": [
          {"index": 0, "codec_type": "audio", "codec_name": "aac", "tags": {"language": "jpn"},
           "disposition": {"default": 1, "original": 1}},
          {"index": 1, "codec_type": "audio", "codec_name": "aac", "tags": {"language": "eng"},
           "disposition": {"comment": 1}},
          {"index": 2, "codec_type": "audio", "codec_name": "aac", "tags": {"language": "eng"},
           "disposition": {"visual_impaired": 1, "dub": 1}},
          {"index": 3, "codec_type": "subtitle", "codec_name": "subrip", "tags": {"language": "eng"},
           "disposition": {"hearing_impaired": 1, "captions": 1}},
          {"index": 4, "codec_type": "subtitle", "codec_name": "subrip", "tags": {"language": "eng"},
           "disposition": {"forced": 1}},
          {"index": 5, "codec_type": "subtitle", "codec_name": "subrip", "tags": {"language": "eng"},
           "disposition": {"descriptions": 1}}
        ]}
        """#)
        let streams = file.streams
        XCTAssertEqual(streams[0].disposition?.isOriginal, true)
        XCTAssertTrue(streams[0].isOriginalLanguage)
        XCTAssertTrue(streams[0].isDefault)
        XCTAssertEqual(streams[0].policyRoles, [])
        XCTAssertEqual(streams[1].policyRoles, [.commentary])
        XCTAssertEqual(streams[2].policyRoles, [.audioDescription])
        XCTAssertEqual(streams[2].disposition?.isDub, true)
        XCTAssertEqual(streams[3].disposition?.isCaptions, true)
        XCTAssertEqual(streams[3].policyRoles, [.sdh])
        XCTAssertTrue(streams[4].isForced)
        XCTAssertEqual(streams[4].policyRoles, [.forced])
        XCTAssertEqual(streams[5].policyRoles, [.other], "Text descriptions are not in the subtitle role list")
    }

    /// Saved data from before `captions` existed still decodes.
    func test_streamDisposition_decodesOlderData() throws {
        let old = #"{"isDefault":true,"isDub":false,"isOriginal":false,"isComment":false,"isLyrics":false,"#
            + #""isKaraoke":false,"isForced":true,"isHearingImpaired":false,"isVisualImpaired":false,"#
            + #""isCleanEffects":false,"isDescriptions":false}"#
        let decoded = try JSONDecoder().decode(StreamDisposition.self, from: Data(old.utf8))
        XCTAssertEqual(decoded, StreamDisposition(isDefault: true, isForced: true))
        XCTAssertEqual(StreamDisposition(isCaptions: true).ffmpegValue, "captions")
    }
}
