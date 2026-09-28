// ============================================================================
// MeedyaConverter — TrackWritingTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// What the argument builder writes for each output track under the shared
// language policy (docs/standards/media-language-bcp47-policy.md):
//   * stored track order (TRACK-050/060, LANG-010 to LANG-027);
//   * the language in the form each container's field needs (TRACK-070);
//   * an autonym title where there is no real one (NAME-010);
//   * every role as a disposition (TRACK-010/030/040);
//   * a fixed argument order.
// ContainerLanguageToolTests checks the same against a real ffmpeg.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class TrackWritingTests: XCTestCase {

    // MARK: - A realistic source

    /// A film: video #0; audio #1 English commentary, #2 German, #3 Japanese
    /// (original, default), #4 English main (titled "Track 5" by some tool);
    /// subtitles #5 English forced, #6 English SDH, #7 English full with a
    /// real title.
    private let film: [MediaStream] = [
        MediaStream(streamIndex: 0, streamType: .video, language: "und"),
        MediaStream(streamIndex: 1, streamType: .audio, language: "en", title: "Director's commentary",
                    disposition: StreamDisposition(isComment: true)),
        MediaStream(streamIndex: 2, streamType: .audio, language: "de",
                    disposition: StreamDisposition(isDub: true)),
        MediaStream(streamIndex: 3, streamType: .audio, language: "ja", isDefault: true,
                    disposition: StreamDisposition(isDefault: true, isOriginal: true)),
        MediaStream(streamIndex: 4, streamType: .audio, language: "en", title: "Track 5",
                    disposition: StreamDisposition(isDub: true)),
        MediaStream(streamIndex: 5, streamType: .subtitle, language: "en", isForced: true,
                    disposition: StreamDisposition(isForced: true)),
        MediaStream(streamIndex: 6, streamType: .subtitle, language: "en",
                    disposition: StreamDisposition(isHearingImpaired: true)),
        MediaStream(streamIndex: 7, streamType: .subtitle, language: "en", title: "English (full)",
                    disposition: StreamDisposition())
    ]

    private func builder(output: String = "/tmp/out.mkv") -> FFmpegArgumentBuilder {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/in.mkv")
        builder.outputURL = URL(fileURLWithPath: output)
        builder.sourceStreams = film
        builder.mapAllStreams = true
        builder.videoPassthrough = true
        builder.audioPassthrough = true
        builder.subtitlePassthrough = true
        return builder
    }

    private func maps(_ args: [String]) -> [String] {
        zip(args, args.dropFirst()).filter { $0.0 == "-map" }.map(\.1)
    }

    /// Every `flag value` pair whose flag starts with `prefix`, as "flag value".
    private func pairs(_ args: [String], _ prefix: String) -> [String] {
        zip(args, args.dropFirst()).filter { $0.0.hasPrefix(prefix) }.map { "\($0.0) \($0.1)" }
    }

    // MARK: - Order (TRACK-050/060, LANG-010)

    /// Audio: the original (Japanese) first; then German before English
    /// (code order, not names); within English the main programme before the
    /// commentary. Subtitles: full → SDH → forced.
    func test_tracksAreWrittenInStoredOrder() {
        XCTAssertEqual(maps(builder().build()), ["0:0", "0:3", "0:2", "0:4", "0:1", "0:7", "0:6", "0:5"])
    }

    /// The order can be switched off, keeping the source's order.
    func test_orderCanBeSwitchedOff() {
        var builder = builder()
        builder.orderTracksCanonically = false
        XCTAssertEqual(maps(builder.build()), ["0:0", "0:1", "0:2", "0:3", "0:4", "0:5", "0:6", "0:7"])
    }

    /// Order follows what the output will SAY: re-tagged French audio sorts
    /// after English (`fr` after `en`), wherever it sat in the source.
    func test_orderUsesEditedLanguage() {
        var builder = builder()
        builder.sourceStreamEdits = [1: SourceStreamEdit(language: "fr")]
        XCTAssertEqual(maps(builder.build()).prefix(5), ["0:0", "0:3", "0:2", "0:4", "0:1"])
        builder.sourceStreamEdits = [2: SourceStreamEdit(language: "fr")]
        XCTAssertEqual(maps(builder.build()).prefix(5), ["0:0", "0:3", "0:4", "0:1", "0:2"])
    }

    // MARK: - Language fields (TRACK-070)

    /// Matroska: bibliographic codes (`ger`, `jpn`, `eng`) — ffmpeg writes
    /// the old `Language` element, which takes that form.
    func test_matroskaGetsBibliographicCodes() {
        let languages = pairs(builder().build(), "-metadata:s:").filter { $0.contains("language=") }
        XCTAssertEqual(languages, [
            "-metadata:s:v:0 language=und",
            "-metadata:s:a:0 language=jpn", "-metadata:s:a:1 language=ger",
            "-metadata:s:a:2 language=eng", "-metadata:s:a:3 language=eng",
            "-metadata:s:s:0 language=eng", "-metadata:s:s:1 language=eng", "-metadata:s:s:2 language=eng"
        ])
    }

    /// MP4: terminology codes (`deu`) — ffmpeg writes whatever three letters
    /// it is given into `mdhd`, and drops a two-letter or longer tag.
    func test_mp4GetsTerminologyCodes() {
        let args = builder(output: "/tmp/out.mp4").build()
        XCTAssertTrue(args.contains("language=deu"), "\(args)")
        XCTAssertFalse(args.contains("language=ger"))
    }

    /// Ogg: the full canonical tag in its free-text LANGUAGE comment.
    func test_oggGetsTheFullTag() {
        var builder = builder(output: "/tmp/out.ogg")
        builder.sourceStreamEdits = [2: SourceStreamEdit(language: "de-CH")]
        XCTAssertTrue(builder.build().contains("language=de-CH"))
    }

    /// A language with no ISO 639-2 code, or a malformed edit, is written as
    /// `und` in a three-letter field — never a guess, never garbage.
    func test_unknownOrMalformedBecomesUnd() {
        var builder = builder()
        builder.sourceStreamEdits = [2: SourceStreamEdit(language: "English!"), 1: SourceStreamEdit(language: "yue")]
        let languages = pairs(builder.build(), "-metadata:s:a:").filter { $0.contains("language=") }
        // Order: ja (original), en, yue, then the malformed value last.
        // `yue` (Cantonese) has no ISO 639-2 code, so it is written `und`;
        // the malformed value is written `und` too.
        XCTAssertEqual(languages, [
            "-metadata:s:a:0 language=jpn", "-metadata:s:a:1 language=eng",
            "-metadata:s:a:2 language=und", "-metadata:s:a:3 language=und"
        ])
    }

    // MARK: - Titles (NAME-010)

    /// No title, or a placeholder ("Track 5"): the autonym. A real title is
    /// never overwritten.
    func test_autonymTitlesOnlyWhereThereIsNoRealTitle() {
        let titles = pairs(builder().build(), "-metadata:s:").filter { $0.contains("title=") }
        XCTAssertEqual(titles, [
            "-metadata:s:a:0 title=日本語",
            "-metadata:s:a:1 title=Deutsch",
            "-metadata:s:a:2 title=English",
            "-metadata:s:s:1 title=English",
            "-metadata:s:s:2 title=English"
        ], "The commentary (a:3) and the titled full subtitles (s:0) keep their own titles")
    }

    /// The editor's title wins, and an empty one clears.
    func test_editorTitleWins() {
        var builder = builder()
        builder.sourceStreamEdits = [2: SourceStreamEdit(title: "German dub"), 7: SourceStreamEdit(title: "")]
        let titles = pairs(builder.build(), "-metadata:s:").filter { $0.contains("title=") }
        XCTAssertTrue(titles.contains("-metadata:s:a:1 title=German dub"))
        XCTAssertTrue(titles.contains("-metadata:s:s:0 title="))
    }

    /// When the source's metadata is to be dropped (`-map_metadata -1`),
    /// nothing is taken from the source — only the editor's changes.
    func test_droppedSourceMetadataWritesOnlyEdits() {
        var builder = builder()
        builder.extraArguments = ["-map_metadata", "-1"]
        builder.sourceStreamEdits = [2: SourceStreamEdit(language: "de")]
        let metadata = pairs(builder.build(), "-metadata:s:")
        XCTAssertEqual(metadata, ["-metadata:s:a:1 language=ger"])
    }

    // MARK: - Roles (TRACK-010/030/040)

    /// Every track's roles are written, in output order.
    func test_everyRoleIsWritten() {
        XCTAssertEqual(pairs(builder().build(), "-disposition"), [
            "-disposition:a:0 default+original",
            "-disposition:a:1 dub",
            "-disposition:a:2 dub",
            "-disposition:a:3 comment",
            "-disposition:s:0 0",
            "-disposition:s:1 hearing_impaired",
            "-disposition:s:2 forced"
        ], "The video has no known roles (no disposition recorded), so it gets none")
    }

    /// The editor's roles replace the source's for that track.
    func test_editorRolesReachTheOutput() {
        var builder = builder()
        builder.sourceStreamEdits = [7: SourceStreamEdit(disposition: StreamDisposition(isDefault: true))]
        XCTAssertTrue(pairs(builder.build(), "-disposition").contains("-disposition:s:0 default"))
    }

    /// A tone-mapped REPLACEMENT subtitle (from a separate file with no tags)
    /// gets its source's language, roles and real title (#409 path).
    func test_toneMapReplacementKeepsLanguageRolesAndTitle() {
        var builder = builder()
        builder.mapAllStreams = false
        builder.subtitleStreamActions = [
            .init(streamIndex: 5, action: .passthrough),
            .init(streamIndex: 6, action: .passthrough),
            .init(streamIndex: 7, action: .replaceWith(URL(fileURLWithPath: "/tmp/sub7.sup")))
        ]
        let args = builder.build()
        XCTAssertEqual(maps(args).suffix(3), ["1:s:0", "0:6", "0:5"], "full (replaced) → SDH → forced")
        XCTAssertTrue(pairs(args, "-metadata:s:s:0").contains("-metadata:s:s:0 title=English (full)"))
        XCTAssertTrue(pairs(args, "-metadata:s:s:0").contains("-metadata:s:s:0 language=eng"))
        XCTAssertTrue(pairs(args, "-disposition:s:0").contains("-disposition:s:0 0"))
    }

    // MARK: - Determinism

    func test_sameSettingsSameCommandLine() {
        let builder = builder()
        let first = builder.build()
        for _ in 0..<5 {
            XCTAssertEqual(builder.build(), first)
        }
    }

    // MARK: - Helpers

    func test_placeholderTitles() {
        for placeholder in ["", "  ", "Track 2", "track", "Audio", "Stream #3", "Subtitle 1", "SUBS"] {
            XCTAssertFalse(TrackLanguage.isMeaningfulTitle(placeholder), placeholder)
        }
        for real in ["Director's commentary", "English", "ENG DUB", "Track 2 (remastered)"] {
            XCTAssertTrue(TrackLanguage.isMeaningfulTitle(real), real)
        }
        XCTAssertFalse(TrackLanguage.isMeaningfulTitle(nil))
    }
}
