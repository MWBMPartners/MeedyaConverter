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
// ============================================================================

import Foundation
import XCTest
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Finding the real media tools, and reading files as Apple's players do.
enum MediaTools {

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
