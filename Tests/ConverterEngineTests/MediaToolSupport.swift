// ============================================================================
// MeedyaConverter — MediaToolSupport
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Shared by the tests that run the REAL tools — ffmpeg, ffprobe and
// MKVToolNix's mkvmerge. The language policy says what a tool writes must be
// checked against the tool itself, with a test (TRACK-070), so these tests are
// the evidence behind the job's notes.
//
// It also reads a file the way Apple's players do (AVFoundation). For MOV that
// matters: ffprobe gives back the label of ffmpeg's QuickTime language list
// (`chi`), while Apple reads the same stored number as Traditional Chinese
// (`zh-Hant`) — the third independent review of the language policy work
// found MOV notes that were true for ffprobe and untrue for Apple's players.
//
// WHY "SKIP HERE, FAIL IN CI"
// ---------------------------
// On a developer's Mac without the tools these tests SKIP (CONTRIBUTING's
// rule for tests that need FFmpeg). Until the third independent review they
// skipped in CI too, and nothing showed whether the CI runner had the tools
// at all — so a green CI run said nothing about them. Now CI's build-and-test
// job (`.github/workflows/build.yml`) installs ffmpeg and MKVToolNix and sets
// `MEEDYA_REQUIRE_MEDIA_TOOLS=1`; with it set, a missing tool, or a missing
// encoder a test needs, FAILS the test instead (`MediaTools.missing`).
//
// The variable is the project's own rather than GitHub's general `CI=true`,
// on purpose: the other workflows that run `swift test` (dev builds,
// pre-releases, releases) do not install Homebrew's ffmpeg — a release
// bundles its own checked copy, and a second ffmpeg on that runner would only
// blur which one is used. They skip, as before; the build-and-test job, which
// runs on every push and pull request, is where these tests are required.
//
// WHAT IT CANNOT DO: it cannot make a test that does not call it fail. A new
// real-tool test must say "not here" with `MediaTools.missing(_:)`, never with
// `XCTSkip` directly.
// ============================================================================

import Foundation
import XCTest
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Finding the real media tools, and reading files as Apple's players do.
enum MediaTools {

    /// Whether this run must have the tools (see the file header): set by
    /// CI's build-and-test job.
    static var required: Bool {
        ProcessInfo.processInfo.environment["MEEDYA_REQUIRE_MEDIA_TOOLS"] == "1"
    }

    /// A tool — or an encoder, or AVFoundation — a test needs is not here:
    /// SKIP on a developer's Mac, FAIL in CI (see the file header). Always
    /// throws.
    static func missing(_ what: String) throws -> Never {
        if required { throw RequiredToolMissing(what: what) }
        throw XCTSkip("\(what) — skipped here (CI's build-and-test job requires it: MEEDYA_REQUIRE_MEDIA_TOOLS=1)")
    }

    /// The error that FAILS a test in CI when something it needs is missing.
    /// A `LocalizedError`, so XCTest shows these words, not "error 1".
    struct RequiredToolMissing: LocalizedError, Sendable, CustomStringConvertible {
        let what: String
        var errorDescription: String? { description }
        var description: String {
            "\(what), but this run requires the real media tools (MEEDYA_REQUIRE_MEDIA_TOOLS=1): the CI job "
                + "must install them (brew install ffmpeg mkvtoolnix)"
        }
    }

    /// The first executable found for `name` on `PATH` or in the usual
    /// Homebrew and system folders.
    static func find(_ name: String) -> String? {
        let folders = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return folders.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// What Apple's AVFoundation reads as each AUDIO track's language:
    /// `languageCode` (ISO 639-2/T, `zho`) and `extendedLanguageTag` (BCP 47,
    /// `zh-Hant`), each `nil` when there is none. `nil` where AVFoundation is
    /// not available (it always is on macOS, where these tests run).
    static func appleAudioLanguages(of url: URL) async throws -> [AppleLanguage]? {
        #if canImport(AVFoundation)
        let asset = AVURLAsset(url: url)
        var result: [AppleLanguage] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            result.append(AppleLanguage(
                code: try await track.load(.languageCode),
                tag: try await track.load(.extendedLanguageTag)
            ))
        }
        return result
        #else
        return nil
        #endif
    }

    /// One audio track's language as AVFoundation reads it.
    struct AppleLanguage: Sendable, Equatable, CustomStringConvertible {
        let code: String?
        let tag: String?
        /// No language at all: AVFoundation reports `und` (or nothing) and no
        /// extended tag.
        var isNone: Bool { (code == nil || code == "und") && tag == nil }
        var description: String { "\(code ?? "nil")/\(tag ?? "nil")" }
    }
}
