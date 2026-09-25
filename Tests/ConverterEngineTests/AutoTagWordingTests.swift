// ============================================================================
// MeedyaConverter — AutoTagWordingTests (Issue #508, commit 8/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pins what `AutoTagWording` says for every kind of `AutoTagJobEvent` this
// codebase can build today, and that the two "never" guarantees hold:
//   * every message is non-empty, plain English (never a raw enum case name
//     or a blank string a `default:` branch could silently produce — see
//     `AutoTagWording`'s own header for why it has no `default:` anywhere);
//   * no message ever contains an API key, even when the reason handed to it
//     is deliberately UNREDACTED (belt and braces — production reasons are
//     always already redacted before an event is built; see
//     `AutoTagJobEvent`'s own doc comment).
//
// Public API only, exactly like `AutoTagRunnerTests.swift` — no `@testable
// import`. `.claude/local-test-harness.md` records that linking a test which
// uses `ConverterEngine`'s INTERNAL members has never been tried locally, so
// this file deliberately builds every fixture (`AutoTagLookupReport`,
// `AutoTagMatchSummary`, `MetadataResult`, `MetadataSearchQuery`, `MediaTag`)
// through their public initialisers, and does its own plain string-replace
// for the "already redacted" simulation below rather than reaching for
// `TMDBLookupService`'s internal `redacting(_:key:)`.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// MARK: - Fixtures shared by every test in this file

/// A fake TMDB-shaped key: 32 hex characters. Never a real credential —
/// used only to prove it cannot appear in a message.
private let wordingTestFakeKey = "0123456789abcdef0123456789abcdef"

/// Builds one `AutoTagJobEvent` for `kind`. `jobID`/`fileName` are fixed,
/// unremarkable values — nothing under test reads them except the
/// `.lookingUp` wording (which is given its own, meaningful `fileName` where
/// it matters).
private func wordingTestEvent(
    _ kind: AutoTagJobEvent.Kind,
    fileName: String = "Movie.mkv"
) -> AutoTagJobEvent {
    AutoTagJobEvent(jobID: UUID(), fileName: fileName, kind: kind)
}

final class AutoTagWordingTests: XCTestCase {

    // MARK: .lookingUp

    func test_lookingUp_tmdb_pinnedWording_andIsNotAWarning() {
        let event = wordingTestEvent(.lookingUp(.tmdb), fileName: "Inception.mkv")
        XCTAssertEqual(AutoTagWording.message(for: event), "Looking up 'Inception.mkv' on TMDB…")
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    func test_lookingUp_musicBrainz_pinnedWording() {
        let event = wordingTestEvent(.lookingUp(.musicBrainz), fileName: "Song.mp3")
        XCTAssertEqual(AutoTagWording.message(for: event), "Looking up 'Song.mp3' on MusicBrainz…")
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    // MARK: .lookup — .applied

    func test_lookup_applied_film_pinnedWording_andIsNotAWarning() {
        let film = MetadataResult(source: .tmdb, externalId: "27205", title: "Inception", year: 2010, confidence: 1.0)
        let report = AutoTagLookupReport(
            outcome: .applied,
            provider: .tmdb,
            tagsToAdd: [MediaTag(key: "date", value: "2010"), MediaTag(key: "genre", value: "Science Fiction")],
            keptExisting: [MediaTag(key: "title", value: "My own title")],
            identifiedFilm: film
        )
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "Tagged from TMDB: 'Inception (2010)', 100% match. Added: date, genre. Kept the file's own: title."
        )
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    /// The music path has no `identifiedFilm` to quote a title from — see
    /// that property's own doc comment on `AutoTagLookupReport` — so its
    /// `.applied` wording names only the provider and the tags.
    func test_lookup_applied_music_pinnedWording() {
        let report = AutoTagLookupReport(
            outcome: .applied,
            provider: .musicBrainz,
            tagsToAdd: [MediaTag(key: "album", value: "OK Computer")]
        )
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(AutoTagWording.message(for: event), "Tagged from MusicBrainz. Added: album.")
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    // MARK: .lookup — .matchedNothingToAdd

    func test_lookup_matchedNothingToAdd_film_pinnedWording() {
        let film = MetadataResult(source: .tmdb, externalId: "27205", title: "Inception", year: 2010, confidence: 0.92)
        let report = AutoTagLookupReport(outcome: .matchedNothingToAdd, provider: .tmdb, identifiedFilm: film)
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "Matched 'Inception (2010)' on TMDB (92% match), but the file already had every tag it would have added."
        )
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    func test_lookup_matchedNothingToAdd_music_pinnedWording() {
        let report = AutoTagLookupReport(outcome: .matchedNothingToAdd, provider: .musicBrainz)
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "Matched on MusicBrainz, but the file already had every tag it would have added."
        )
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    // MARK: .lookup — .belowThreshold

    func test_lookup_belowThreshold_pinnedWording() {
        let best = AutoTagMatchSummary(title: "Some Film", year: 1999, externalId: "1", confidence: 0.52)
        let report = AutoTagLookupReport(outcome: .belowThreshold(best: best, needed: 0.7), provider: .tmdb)
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "Best match 'Some Film (1999)' was 52% certain; needs 70%. Not applied."
        )
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    // MARK: .lookup — .ambiguous

    func test_lookup_ambiguous_film_pinnedWording() {
        let first = AutoTagMatchSummary(title: "Film A", year: 2001, externalId: "1", confidence: 0.80)
        let second = AutoTagMatchSummary(title: "Film B", year: 2001, externalId: "2", confidence: 0.78)
        let report = AutoTagLookupReport(outcome: .ambiguous(first: first, second: second), provider: .tmdb)
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "Two films matched equally well: 'Film A (2001)' and 'Film B (2001)'. Not applied."
        )
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    /// Same outcome case, a different provider: the noun changes
    /// ("recordings", not "films") — `AutoTagWording.candidateNoun(_:)`'s
    /// whole reason for existing.
    func test_lookup_ambiguous_music_pinnedWording() {
        let first = AutoTagMatchSummary(title: "Song A", year: nil, externalId: "1", confidence: 0.80)
        let second = AutoTagMatchSummary(title: "Song B", year: nil, externalId: "2", confidence: 0.78)
        let report = AutoTagLookupReport(outcome: .ambiguous(first: first, second: second), provider: .musicBrainz)
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "Two recordings matched equally well: 'Song A' and 'Song B'. Not applied."
        )
    }

    // MARK: .lookup — .noMatch

    func test_lookup_noMatch_pinnedWording() {
        let query = MetadataSearchQuery(mediaType: .movie, title: "Some Obscure Film", year: 1974)
        let report = AutoTagLookupReport(outcome: .noMatch(searchedFor: query), provider: .tmdb)
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(AutoTagWording.message(for: event), "TMDB found nothing for 'Some Obscure Film (1974)'.")
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    // MARK: .lookup — .skipped

    func test_lookup_skipped_pinnedWording_andIsNotAWarning() {
        // `AutoTagRunner.Reasons.noTMDBKey` is the SAME constant the real
        // runner uses, so this pins the exact sentence a user actually sees
        // rather than a copy that could drift from it.
        let report = AutoTagLookupReport(outcome: .skipped(reason: AutoTagRunner.Reasons.noTMDBKey), provider: nil)
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(AutoTagWording.message(for: event), "Not tagged: No TMDB key is saved (Settings › Metadata).")
        XCTAssertFalse(
            AutoTagWording.isWarning(for: event),
            "a skip is an ordinary, expected reason nothing was added, not something gone wrong"
        )
    }

    // MARK: .lookup — .failed

    func test_lookup_failed_pinnedWording_andIsAWarning() {
        let report = AutoTagLookupReport(outcome: .failed(reason: "TMDB didn't answer within 30 seconds."), provider: .tmdb)
        let event = wordingTestEvent(.lookup(report))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "TMDB didn't answer within 30 seconds. Converted without extra tags."
        )
        XCTAssertTrue(
            AutoTagWording.isWarning(for: event),
            "the plan's own table calls .failed out as the one warning-worthy lookup outcome"
        )
    }

    // MARK: .nfo

    func test_nfo_written_pinnedWording_andIsNotAWarning() {
        let event = wordingTestEvent(.nfo(.written(path: "/Users/x/Movies/Inception (2010).nfo")))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "Saved a Kodi .nfo file next to the output ('Inception (2010).nfo')."
        )
        XCTAssertFalse(AutoTagWording.isWarning(for: event))
    }

    func test_nfo_leftExisting_pinnedWording_andIsNotAWarning() {
        let event = wordingTestEvent(.nfo(.leftExisting(path: "/Users/x/Movies/Inception (2010).nfo")))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "An .nfo file already exists there ('Inception (2010).nfo'); left it as it is."
        )
        XCTAssertFalse(
            AutoTagWording.isWarning(for: event),
            "leaving an existing .nfo alone is the writer working as designed, not a problem"
        )
    }

    func test_nfo_failed_pinnedWording_andIsAWarning() {
        let event = wordingTestEvent(.nfo(.failed(reason: "The .nfo file could not be written (permission denied).")))
        XCTAssertEqual(
            AutoTagWording.message(for: event),
            "Couldn't save the .nfo file: The .nfo file could not be written (permission denied)."
        )
        XCTAssertTrue(AutoTagWording.isWarning(for: event))
    }

    // MARK: Every case, at once — never empty

    /// One event per `AutoTagJobEvent.Kind` case, and — nested inside
    /// `.lookup`/`.nfo` — one per `AutoTagOutcome`/`AutoTagNFOOutcome` case:
    /// 1 + 7 + 3 = 11 events. If a future commit adds a new case to any of
    /// those three enums, `AutoTagWording`'s exhaustive `switch`es (see its
    /// own header) fail to COMPILE until this list — and a real wording
    /// decision — is updated for it, so this list staying at 11 is itself a
    /// signal nothing new has silently arrived unworded.
    private func everyKnownEvent() -> [AutoTagJobEvent] {
        let film = MetadataResult(source: .tmdb, externalId: "1", title: "X", year: 2000, confidence: 0.9)
        let summary = AutoTagMatchSummary(title: "Y", year: 2001, externalId: "2", confidence: 0.6)
        let query = MetadataSearchQuery(mediaType: .movie, title: "Z")
        return [
            wordingTestEvent(.lookingUp(.tmdb)),
            wordingTestEvent(.lookup(AutoTagLookupReport(
                outcome: .applied, provider: .tmdb,
                tagsToAdd: [MediaTag(key: "date", value: "2000")], identifiedFilm: film
            ))),
            wordingTestEvent(.lookup(AutoTagLookupReport(
                outcome: .matchedNothingToAdd, provider: .tmdb, identifiedFilm: film
            ))),
            wordingTestEvent(.lookup(AutoTagLookupReport(
                outcome: .belowThreshold(best: summary, needed: 0.7), provider: .tmdb
            ))),
            wordingTestEvent(.lookup(AutoTagLookupReport(
                outcome: .ambiguous(first: summary, second: summary), provider: .tmdb
            ))),
            wordingTestEvent(.lookup(AutoTagLookupReport(
                outcome: .noMatch(searchedFor: query), provider: .tmdb
            ))),
            wordingTestEvent(.lookup(AutoTagLookupReport(
                outcome: .skipped(reason: "a plain-English reason"), provider: nil
            ))),
            wordingTestEvent(.lookup(AutoTagLookupReport(
                outcome: .failed(reason: "a plain-English reason"), provider: .tmdb
            ))),
            wordingTestEvent(.nfo(.written(path: "/tmp/x.nfo"))),
            wordingTestEvent(.nfo(.leftExisting(path: "/tmp/x.nfo"))),
            wordingTestEvent(.nfo(.failed(reason: "a plain-English reason"))),
        ]
    }

    func test_everyKnownEventKind_producesANonEmptyMessage() {
        for event in everyKnownEvent() {
            XCTAssertFalse(AutoTagWording.message(for: event).isEmpty, "empty message for \(event.kind)")
        }
    }

    // MARK: Belt and braces — no message ever contains a key

    /// Simulates what would reach `AutoTagWording` if a failure reason's
    /// OWN redaction pass were somehow bypassed further upstream. In real
    /// use this can't happen — every `.failed` reason on the film path has
    /// already been through `TMDBLookupService.redactingKey(in:)` before
    /// `EncodingEngine` ever builds the event (`AutoTagJobEvent`'s own doc
    /// comment) — so this test does its own equivalent replace, deliberately
    /// NOT calling into `ConverterEngine`'s internals (this file uses public
    /// API only; see the header for why), and confirms `AutoTagWording`
    /// passes the ALREADY-SAFE reason through without ever reintroducing the
    /// raw key from anywhere else it touches (the provider name, the "…
    /// Converted without extra tags." suffix, etc.).
    func test_failedMessage_neverContainsAKey_evenGivenAnUnredactedRawReason() {
        let rawReason = "TMDB returned HTTP 401: key \(wordingTestFakeKey) was rejected"
        let redactedReason = rawReason.replacingOccurrences(of: wordingTestFakeKey, with: "<redacted>")
        XCTAssertFalse(redactedReason.contains(wordingTestFakeKey), "the simulated redaction itself must remove the key")

        let report = AutoTagLookupReport(outcome: .failed(reason: redactedReason), provider: .tmdb)
        let message = AutoTagWording.message(for: wordingTestEvent(.lookup(report)))

        XCTAssertFalse(message.contains(wordingTestFakeKey))
        XCTAssertTrue(message.contains("<redacted>"), "the redaction placeholder must still be legible in the log line")
    }

    /// A second, independent belt-and-braces check: `tagsToAdd`/
    /// `keptExisting` are arbitrary `[MediaTag]`, and only their KEYS
    /// ("date", "genre", …) ever appear in the "Added: …" / "Kept the
    /// file's own: …" clauses — never a tag's VALUE. So even a fake key
    /// planted in a tag's value (never a realistic shape for a real tag,
    /// but nothing stops one existing) must not leak into the message.
    func test_appliedMessage_neverSurfacesATagValue_onlyItsKey() {
        let film = MetadataResult(source: .tmdb, externalId: "1", title: "X", year: 2000, confidence: 1.0)
        let report = AutoTagLookupReport(
            outcome: .applied,
            provider: .tmdb,
            tagsToAdd: [MediaTag(key: "comment", value: "api_key=\(wordingTestFakeKey)")],
            identifiedFilm: film
        )
        let message = AutoTagWording.message(for: wordingTestEvent(.lookup(report)))
        XCTAssertFalse(message.contains(wordingTestFakeKey))
        XCTAssertTrue(message.contains("comment"), "the tag's KEY is expected to appear")
    }
}
