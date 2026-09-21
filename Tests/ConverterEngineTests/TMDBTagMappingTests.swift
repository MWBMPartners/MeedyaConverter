// ============================================================================
// MeedyaConverter — TMDBTagMappingTests (Issue #205)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pure mapping, so this is exhaustive and needs nothing injected.
//
// The most important case is the cover-art one: ffprobe reports an embedded
// picture as a video stream, so "does this file have video?" answers YES for
// a tagged MP3. Anything branching on that alone offers a film lookup for a
// song, which is how a music file ends up tagged as a documentary.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class TMDBTagMappingTests: XCTestCase {

    // MARK: - Fixtures

    private func result(
        title: String = "Fight Club",
        year: Int? = 1999,
        genres: [String] = ["Drama"],
        overview: String? = "Prose.",
        directors: [String] = [],
        id: String = "550"
    ) -> MetadataResult {
        MetadataResult(
            source: .tmdb,
            externalId: id,
            title: title,
            year: year,
            overview: overview,
            genres: genres,
            directors: directors
        )
    }

    private func stream(_ type: StreamType, codec: String?) -> MediaStream {
        MediaStream(streamIndex: 0, streamType: type, codecName: codec)
    }

    // MARK: - Embedded artwork is not video

    func test_stillImageCodecsAreRecognisedAsArtwork() {
        for codec in ["mjpeg", "MJPEG", "png", "bmp", "gif", "webp"] {
            XCTAssertTrue(
                EmbeddedArtwork.isStillImage(stream(.video, codec: codec)),
                "\(codec) is cover art, not a film"
            )
        }
    }

    func test_realVideoCodecsAreNotArtwork() {
        for codec in ["h264", "hevc", "vp9", "av1", "mpeg2video", "prores"] {
            XCTAssertFalse(
                EmbeddedArtwork.isStillImage(stream(.video, codec: codec)),
                "\(codec) is moving video"
            )
        }
    }

    func test_unknownCodecIsTreatedAsVideoNotArtwork() {
        // Erring towards "it's video" means an unrecognised codec gets a film
        // lookup offered, which is recoverable. Erring the other way would
        // silently withhold the feature for a real film.
        XCTAssertFalse(EmbeddedArtwork.isStillImage(stream(.video, codec: nil)))
        XCTAssertFalse(EmbeddedArtwork.isStillImage(stream(.video, codec: "")))
        XCTAssertFalse(EmbeddedArtwork.isStillImage(stream(.video, codec: "some_new_codec")))
    }

    // MARK: - The trap: an MP3 with cover art

    func test_audioFileWithCoverArtIsNotTreatedAsAFilm() {
        // `containerFormat` is nil because ContainerFormat has no mp3 case —
        // which is also what production holds for such a file, so this is the
        // real shape rather than a convenient one.
        let mp3 = MediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/song.mp3"),
            containerFormat: nil,
            streams: [
                stream(.audio, codec: "mp3"),
                stream(.video, codec: "mjpeg"),   // the cover art
            ]
        )

        XCTAssertTrue(mp3.hasVideo, "precondition: the naive check is fooled by cover art")
        XCTAssertFalse(mp3.hasMovingVideo, "the artwork stream does not make it a film")
        XCTAssertFalse(
            mp3.looksLikeVideoContent,
            "offering a film lookup here is how a song gets tagged as a documentary"
        )
    }

    func test_aRealFilmIsTreatedAsVideo() {
        let film = MediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/film.mkv"),
            containerFormat: .mkv,
            streams: [
                stream(.video, codec: "h264"),
                stream(.audio, codec: "aac"),
            ]
        )

        XCTAssertTrue(film.hasMovingVideo)
        XCTAssertTrue(film.looksLikeVideoContent)
    }

    func test_anAudioOnlyContainerIsNeverVideoWhateverItsStreamsClaim() {
        // Belt and braces: an .m4a cannot hold video, so even a stream that
        // looks like one must not flip the verdict.
        let m4a = MediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/track.m4a"),
            containerFormat: .m4a,
            streams: [
                stream(.audio, codec: "alac"),
                stream(.video, codec: "h264"),
            ]
        )

        XCTAssertTrue(m4a.hasMovingVideo, "the stream itself is moving video")
        XCTAssertFalse(m4a.looksLikeVideoContent, "but the container cannot hold a film")
    }

    func test_anAudioFileWithNoArtworkIsNotVideo() {
        let flac = MediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/track.flac"),
            containerFormat: nil,
            streams: [stream(.audio, codec: "flac")]
        )
        XCTAssertFalse(flac.hasMovingVideo)
        XCTAssertFalse(flac.looksLikeVideoContent)
    }

    // MARK: - Seeding a search

    func test_seedQuery_prefersATitleTheFileAlreadyCarries() {
        let tags = [MediaTag(key: "title", value: "Blade Runner"), MediaTag(key: "date", value: "1982")]
        let query = TMDBTagMapping.seedQuery(tags: tags, filename: "some.random.file.mkv")

        XCTAssertEqual(query.title, "Blade Runner")
        XCTAssertEqual(query.year, 1982)
    }

    func test_seedQuery_fallsBackToTheFilename() {
        let query = TMDBTagMapping.seedQuery(tags: [], filename: "Blade Runner (1982).mkv")

        XCTAssertFalse(query.title.isEmpty)
        XCTAssertEqual(query.year, 1982)
    }

    func test_seedQuery_ignoresAnImplausibleDateTag() {
        // A junk `date` tag must not become a year filter that hides the film.
        let tags = [MediaTag(key: "title", value: "A Film"), MediaTag(key: "date", value: "not a year")]
        let query = TMDBTagMapping.seedQuery(tags: tags, filename: "A Film.mkv")
        XCTAssertNil(query.year)
    }

    func test_seedQuery_blankTitleTagFallsBackRatherThanSearchingForNothing() {
        let tags = [MediaTag(key: "title", value: "   ")]
        let query = TMDBTagMapping.seedQuery(tags: tags, filename: "Blade Runner (1982).mkv")
        XCTAssertFalse(query.title.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Applying a result

    func test_applying_writesTheCanonicalKeys() {
        let tags = TMDBTagMapping.applying(
            result(directors: ["David Fincher"]),
            to: [],
            includeIdentifiers: true
        )

        XCTAssertEqual(TMDBTagMapping.value(forKey: "title", in: tags), "Fight Club")
        XCTAssertEqual(TMDBTagMapping.value(forKey: "date", in: tags), "1999")
        XCTAssertEqual(TMDBTagMapping.value(forKey: "genre", in: tags), "Drama")
        XCTAssertEqual(TMDBTagMapping.value(forKey: "description", in: tags), "Prose.")
        XCTAssertEqual(TMDBTagMapping.value(forKey: "director", in: tags), "David Fincher")
        XCTAssertEqual(TMDBTagMapping.value(forKey: "tmdb_id", in: tags), "550")
    }

    func test_applying_replacesInPlaceAndKeepsTheOriginalKeySpelling() throws {
        let existing = [MediaTag(key: "Title", value: "Wrong Name")]
        let tags = TMDBTagMapping.applying(result(), to: existing, includeIdentifiers: false)

        XCTAssertEqual(tags.count, 4, "title replaced; date, genre and description added")
        let titleTag = try XCTUnwrap(tags.first { $0.key.caseInsensitiveCompare("title") == .orderedSame })
        XCTAssertEqual(titleTag.key, "Title", "the file's own spelling is preserved")
        XCTAssertEqual(titleTag.value, "Fight Club")
        XCTAssertEqual(titleTag.id, existing[0].id, "replacing in place keeps the row's identity")
    }

    func test_applying_neverDeletesATagWeKnowNothingAbout() {
        // A tag the user added by hand is theirs, not ours to discard.
        let existing = [MediaTag(key: "custom", value: "keep me")]
        let tags = TMDBTagMapping.applying(result(), to: existing, includeIdentifiers: false)

        XCTAssertEqual(TMDBTagMapping.value(forKey: "custom", in: tags), "keep me")
    }

    func test_applying_neverOverwritesTheUsersOwnComment() {
        // "comment" is where someone writes "ripped from my own DVD".
        // Replacing that with a studio synopsis destroys something they wrote
        // and cannot get back, so the synopsis goes to `description` only.
        let existing = [MediaTag(key: "comment", value: "ripped from my own DVD")]
        let tags = TMDBTagMapping.applying(
            result(overview: "A studio synopsis."),
            to: existing,
            includeIdentifiers: false
        )

        XCTAssertEqual(TMDBTagMapping.value(forKey: "comment", in: tags), "ripped from my own DVD")
        XCTAssertEqual(TMDBTagMapping.value(forKey: "description", in: tags), "A studio synopsis.")
    }

    func test_applying_withoutIdentifiersLeavesNoTMDBRow() {
        let tags = TMDBTagMapping.applying(result(), to: [], includeIdentifiers: false)
        XCTAssertNil(TMDBTagMapping.value(forKey: "tmdb_id", in: tags))
    }

    func test_applying_skipsEmptyFieldsRatherThanWritingBlanks() {
        let sparse = MetadataResult(source: .tmdb, externalId: "1", title: "Untitled")
        let tags = TMDBTagMapping.applying(sparse, to: [], includeIdentifiers: false)

        XCTAssertEqual(tags.count, 1, "only the title is known, so only the title is written")
        XCTAssertEqual(TMDBTagMapping.value(forKey: "title", in: tags), "Untitled")
    }
}
