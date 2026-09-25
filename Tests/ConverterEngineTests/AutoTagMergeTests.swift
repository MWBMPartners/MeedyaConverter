// ============================================================================
// MeedyaConverter — AutoTagMergeTests (Issue #508, commit 2/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Coverage for `AutoTagMerge.additions`, the "only add what's missing" rule
// the (not-yet-built) auto-tag runner will use. Everything under test is
// `public`; no `@testable import` (matching the repo convention). Pure logic,
// no network, no I/O.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class AutoTagMergeTests: XCTestCase {

    /// A TMDB lookup result with a full set of fields, used across cases so
    /// each test only has to vary the file's existing tags.
    private func tmdbResult(confidence: Double = 0.9) -> MetadataResult {
        MetadataResult(
            source: .tmdb,
            externalId: "27205",
            title: "Inception",
            year: 2010,
            overview: "A thief who steals corporate secrets...",
            genres: ["Action", "Sci-Fi"],
            directors: ["Christopher Nolan"],
            confidence: confidence
        )
    }

    /// Binds `TMDBTagMapping.applying` to a fixed result, matching the shape
    /// `AutoTagMerge.additions(applying:)` expects: a closure from the base
    /// tag list to the tag list after the match is applied.
    private func tmdbApplying(_ result: MetadataResult) -> ([MediaTag]) -> [MediaTag] {
        { base in TMDBTagMapping.applying(result, to: base, includeIdentifiers: true) }
    }

    // MARK: - Fills gaps only

    /// A file with none of TMDB's fields should gain all of them.
    /// Two input rows sharing one id used to crash the process: the id lookup
    /// was built with `Dictionary(uniqueKeysWithValues:)`, which traps on a
    /// duplicate. That is reachable because `MediaTag.init` accepts a
    /// caller-supplied id. It must now simply work, and still refuse to
    /// overwrite the title the file already has.
    func test_additions_duplicateIDsAcrossInputs_doNotCrash() {
        let sharedID = UUID()
        let existing = [MediaTag(id: sharedID, key: "title", value: "My Own Title")]
        let jobTags = [MediaTag(id: sharedID, key: "genre", value: "Mine")]

        let result = AutoTagMerge.additions(
            existing: existing,
            jobTags: jobTags,
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertFalse(
            result.added.contains { $0.key.caseInsensitiveCompare("title") == .orderedSame },
            "the file's own title must still never be overwritten"
        )
        XCTAssertFalse(
            result.added.contains { $0.key.caseInsensitiveCompare("genre") == .orderedSame },
            "the job's own genre must still win"
        )
    }

    func test_additions_fillsEveryMissingField_whenFileHasNone() {
        let outcome = AutoTagMerge.additions(
            existing: [],
            jobTags: [],
            applying: tmdbApplying(tmdbResult())
        )

        let addedKeys = Set(outcome.added.map { $0.key })
        XCTAssertTrue(addedKeys.contains("title"))
        XCTAssertTrue(addedKeys.contains("date"))
        XCTAssertTrue(addedKeys.contains("genre"))
        XCTAssertTrue(addedKeys.contains("description"))
        XCTAssertTrue(addedKeys.contains("director"))
        XCTAssertTrue(addedKeys.contains("tmdb_id"))
        XCTAssertTrue(outcome.keptExisting.isEmpty)
    }

    /// A file that already has every field TMDB would supply should gain
    /// nothing at all — the whole point of the "only missing" rule.
    func test_additions_addsNothing_whenFileAlreadyHasEveryField() {
        let existing = [
            MediaTag(key: "title", value: "My Own Title"),
            MediaTag(key: "date", value: "2011"),
            MediaTag(key: "genre", value: "Comedy"),
            MediaTag(key: "description", value: "My own summary."),
            MediaTag(key: "director", value: "Someone Else"),
            MediaTag(key: "tmdb_id", value: "999"),
        ]

        let outcome = AutoTagMerge.additions(
            existing: existing,
            jobTags: [],
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertTrue(outcome.added.isEmpty, "expected nothing added, got \(outcome.added)")
        XCTAssertEqual(outcome.keptExisting.count, existing.count)
    }

    /// A file missing only `director` should gain only `director`.
    func test_additions_fillsOnlyTheOneMissingField() {
        let existing = [
            MediaTag(key: "title", value: "My Own Title"),
            MediaTag(key: "date", value: "2011"),
            MediaTag(key: "genre", value: "Comedy"),
            MediaTag(key: "description", value: "My own summary."),
            MediaTag(key: "tmdb_id", value: "999"),
        ]

        let outcome = AutoTagMerge.additions(
            existing: existing,
            jobTags: [],
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertEqual(outcome.added.map { $0.key }, ["director"])
        XCTAssertEqual(outcome.added.first?.value, "Christopher Nolan")
        XCTAssertEqual(outcome.keptExisting.count, existing.count)
    }

    // MARK: - Alias- and case-aware

    /// `year` is the alias `TMDBTagMapping.applying` checks `date` against.
    /// A file with `year` already set must not also gain a `date` row.
    func test_additions_respectsAlias_yearForDate() {
        let existing = [MediaTag(key: "year", value: "1999")]

        let outcome = AutoTagMerge.additions(
            existing: existing,
            jobTags: [],
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertFalse(outcome.added.contains { $0.key.caseInsensitiveCompare("date") == .orderedSame })
        XCTAssertFalse(outcome.added.contains { $0.key.caseInsensitiveCompare("year") == .orderedSame })
        XCTAssertTrue(outcome.keptExisting.contains { $0.key == "year" && $0.value == "1999" })
    }

    /// `synopsis` is the alias `TMDBTagMapping.applying` checks `description`
    /// against.
    func test_additions_respectsAlias_synopsisForDescription() {
        let existing = [MediaTag(key: "synopsis", value: "The user's own synopsis.")]

        let outcome = AutoTagMerge.additions(
            existing: existing,
            jobTags: [],
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertFalse(outcome.added.contains { $0.key.caseInsensitiveCompare("description") == .orderedSame })
        XCTAssertTrue(outcome.keptExisting.contains { $0.key == "synopsis" })
    }

    /// Matching must be case-insensitive: `TITLE` already present must block
    /// a lowercase `title` addition.
    func test_additions_respectsCase_upperCaseKeyBlocksLowerCaseAddition() {
        let existing = [MediaTag(key: "TITLE", value: "Some Title")]

        let outcome = AutoTagMerge.additions(
            existing: existing,
            jobTags: [],
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertFalse(outcome.added.contains { $0.key.caseInsensitiveCompare("title") == .orderedSame })
        XCTAssertTrue(outcome.keptExisting.contains { $0.key == "TITLE" })
    }

    // MARK: - Blank source values don't block

    /// A blank (whitespace-only) existing tag must not count as "already
    /// has this tag" — ffprobe can report a key with nothing meaningful in
    /// it, and that must not block a real looked-up value.
    func test_additions_blankExistingValue_doesNotBlockLookup() {
        let existing = [MediaTag(key: "director", value: "   ")]

        let outcome = AutoTagMerge.additions(
            existing: existing,
            jobTags: [],
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertTrue(outcome.added.contains { $0.key == "director" && $0.value == "Christopher Nolan" })
        XCTAssertFalse(outcome.keptExisting.contains { $0.key == "director" })
    }

    /// An entirely empty existing value behaves the same as whitespace-only.
    func test_additions_emptyExistingValue_doesNotBlockLookup() {
        let existing = [MediaTag(key: "genre", value: "")]

        let outcome = AutoTagMerge.additions(
            existing: existing,
            jobTags: [],
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertTrue(outcome.added.contains { $0.key == "genre" })
    }

    // MARK: - The job's tags win

    /// When the job's own `outputMetadata` and the source file disagree on a
    /// key, the job's tag is what blocks the lookup — and its value, not the
    /// source file's, is what comes back in `keptExisting`.
    func test_additions_jobTagsWinOverSourceFile() {
        let existing = [MediaTag(key: "title", value: "Source File Title")]
        let jobTags = [MediaTag(key: "title", value: "Job's Chosen Title")]

        let outcome = AutoTagMerge.additions(
            existing: existing,
            jobTags: jobTags,
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertFalse(outcome.added.contains { $0.key == "title" })
        XCTAssertEqual(
            outcome.keptExisting.first { $0.key == "title" }?.value,
            "Job's Chosen Title"
        )
    }

    /// A key present only in the job's tags (not the source file at all)
    /// still blocks the lookup for that key.
    func test_additions_jobOnlyTag_blocksLookup() {
        let jobTags = [MediaTag(key: "genre", value: "Job Genre")]

        let outcome = AutoTagMerge.additions(
            existing: [],
            jobTags: jobTags,
            applying: tmdbApplying(tmdbResult())
        )

        XCTAssertFalse(outcome.added.contains { $0.key == "genre" })
        XCTAssertEqual(outcome.keptExisting.first { $0.key == "genre" }?.value, "Job Genre")
    }

    // MARK: - MusicBrainz path (a different `applying` closure)

    /// The same merge works with `MusicBrainzTagMapping.applying` bound in,
    /// proving `AutoTagMerge` genuinely doesn't know or care which lookup
    /// produced the match.
    func test_additions_worksWithMusicBrainzApplying() {
        let match = MusicBrainzRecordingMatch(
            id: "track-mbid",
            title: "Test Recording",
            score: 95,
            artistCredits: [
                MusicBrainzRecordingMatch.ArtistCredit(name: "Test Artist", artistID: "artist-mbid"),
            ],
            lengthMilliseconds: 180_000,
            disambiguation: nil,
            firstReleaseDate: nil,
            releases: []
        )

        let outcome = AutoTagMerge.additions(
            existing: [],
            jobTags: [],
            applying: { base in
                MusicBrainzTagMapping.applying(match, release: nil, to: base, includeIdentifiers: true)
            }
        )

        let addedKeys = Set(outcome.added.map { $0.key })
        XCTAssertTrue(addedKeys.contains("title"))
        XCTAssertTrue(addedKeys.contains("artist"))
        XCTAssertTrue(addedKeys.contains("musicbrainz_trackid"))
    }

    // MARK: - `keysItMayWrite` stays inside what the probe reads

    /// Every key either mapping type can write must be a key the probe
    /// actually reads (`FFmpegProbe.formatTagKeys`) — otherwise the "only
    /// add what's missing" rule would be blind to that key's existing value
    /// in a real file, and could silently add a duplicate. This is the test
    /// the doc comments on both `FFmpegProbe.formatTagKeys` and
    /// `AutoTagMerge.keysItMayWrite` point at.
    func test_keysItMayWrite_isSubsetOf_probeFormatTagKeys() {
        let probeKeys = Set(FFmpegProbe.formatTagKeys)
        let notCovered = AutoTagMerge.keysItMayWrite.subtracting(probeKeys)
        XCTAssertTrue(
            notCovered.isEmpty,
            "AutoTagMerge.keysItMayWrite has keys the probe never reads: \(notCovered)"
        )
    }
}
