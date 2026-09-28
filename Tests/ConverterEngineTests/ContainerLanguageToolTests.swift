// ============================================================================
// MeedyaConverter — ContainerLanguageToolTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The language policy's TRACK-070 says: which fields a tool writes "change
// over time. Each project MUST check them against the tool it actually runs,
// with a test, rather than rely on this table." This is that test.
//
// It makes a tiny two-track source with the ffmpeg on this machine, probes
// it with FFmpegProbe, builds MeedyaConverter's own arguments for a Matroska
// and an MP4 output, runs ffmpeg with them, and reads the results back with
// ffprobe. It checks exactly the facts `TrackLanguage.LanguageFieldForm`
// relies on. Skipped (not failed) when no ffmpeg/ffprobe is installed, per
// CONTRIBUTING's rule for tests that need FFmpeg.
//
// First run 28 Sept 2026 with ffmpeg 9.0.1 (Homebrew): passed. It also
// prints whether the Matroska output holds a `LanguageBCP47` element — ffmpeg
// 9.0.1 writes none; if a later ffmpeg does, the print says so and the
// region/script loss documented in TrackLanguage can be revisited.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class ContainerLanguageToolTests: XCTestCase {

    // MARK: - Tools

    /// The first executable found for `name` in the usual places.
    private func tool(_ name: String) -> String? {
        let folders = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return folders.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs a tool and returns its exit code and standard output.
    @discardableResult
    private func run(_ path: String, _ arguments: [String]) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    /// ffprobe's raw view of each stream: language tag, title tag and the
    /// dispositions this test cares about.
    private func rawStreams(_ ffprobe: String, _ file: URL) throws -> [[String: Any]] {
        let (status, data) = try run(ffprobe, [
            "-v", "error", "-print_format", "json", "-show_entries",
            "stream=index,codec_type:stream_tags=language,title:stream_disposition=default,original,comment",
            file.path
        ])
        XCTAssertEqual(status, 0)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["streams"] as? [[String: Any]] ?? []
    }

    // MARK: - The check

    func test_ffmpegWritesTheLanguageFieldsWeRelyOn() async throws {
        guard let ffmpeg = tool("ffmpeg"), let ffprobe = tool("ffprobe") else {
            throw XCTSkip("ffmpeg/ffprobe not installed — TRACK-070 tool check skipped")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-lang-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // A source with German commentary first and the Japanese original
        // second, written with OLD Matroska codes (as most real files have).
        let source = folder.appendingPathComponent("source.mkv")
        let made = try run(ffmpeg, [
            "-v", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3",
            "-f", "lavfi", "-i", "sine=frequency=660:duration=0.3",
            "-map", "0", "-map", "1", "-c:a", "aac",
            "-metadata:s:a:0", "language=ger", "-disposition:a:0", "comment",
            "-metadata:s:a:1", "language=jpn", "-disposition:a:1", "default+original",
            source.path
        ])
        XCTAssertEqual(made.status, 0, "making the source")

        // The probe reads them through the policy (LANG-002).
        let probed = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: source)
        XCTAssertEqual(probed.streams.map(\.language), ["de", "ja"])
        XCTAssertEqual(probed.streams.map(\.isOriginalLanguage), [false, true])

        for (name, expectedCodes) in [("out.mkv", ["jpn", "ger"]), ("out.mp4", ["jpn", "deu"])] {
            let output = folder.appendingPathComponent(name)
            var builder = FFmpegArgumentBuilder()
            builder.inputURL = source
            builder.outputURL = output
            builder.sourceStreams = probed.streams
            builder.audioPassthrough = true
            builder.videoPassthrough = true
            let encoded = try run(ffmpeg, ["-v", "error"] + builder.build())
            XCTAssertEqual(encoded.status, 0, "encoding \(name)")

            let streams = try rawStreams(ffprobe, output)
            let codes = streams.map { ($0["tags"] as? [String: Any])?["language"] as? String }
            // The original (Japanese) is first; each field holds the
            // three-letter code in the form this container needs.
            XCTAssertEqual(codes, expectedCodes, "\(name): language fields as ffprobe reads them")
            let comment = streams.map { ($0["disposition"] as? [String: Any])?["comment"] as? Int }
            XCTAssertEqual(comment, [0, 1], "\(name): the commentary role survives")

            if name == "out.mkv" {
                let titles = streams.map { ($0["tags"] as? [String: Any])?["title"] as? String }
                // Automatic titles (NAME-010) say the language AND the
                // roles, so the German commentary is not just "Deutsch".
                XCTAssertEqual(titles, ["日本語", "Deutsch — Commentary"], "automatic titles (NAME-010, UI-070)")
                let original = streams.map { ($0["disposition"] as? [String: Any])?["original"] as? Int }
                XCTAssertEqual(original, [1, 0], "Matroska keeps FlagOriginal")
                // Informational: does this ffmpeg write LanguageBCP47
                // (EBML ID 0x22B59D)? 9.0.1 does not.
                let bytes = try Data(contentsOf: output)
                let hasBCP47 = bytes.range(of: Data([0x22, 0xB5, 0x9D])) != nil
                print("TRACK-070 tool check: Matroska LanguageBCP47 element written by this ffmpeg: \(hasBCP47)")
            }

            // And the probe reads the output back to the same tags.
            let reread = try await FFmpegProbe(ffprobePath: ffprobe).analyze(url: output)
            XCTAssertEqual(reread.streams.map(\.language), ["ja", "de"], "\(name): read back through the policy")
        }
    }
}
