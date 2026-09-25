// ============================================================================
// MeedyaConverter — AutoTagWording (Issue #508, commit 8/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Turns one `AutoTagJobEvent` — data only, published on
// `EncodingEngine.autoTagEvents` — into the ONE-LINE, plain-English sentence
// the Activity Log shows for it, and says whether that line should be logged
// as a warning or as plain information. This is the ONLY place #508's Activity
// Log wording lives: the app-side event consumer (`AppViewModel`, wired up in
// this same commit) does nothing but call `message(for:)` and `isWarning(for:)`
// and hand the result straight to `appendLog`.
//
// Kept in `ConverterEngine`, not the app module, for two reasons: it can be
// unit-tested here (`AutoTagWordingTests`) without pulling in SwiftUI or
// `AppViewModel`, and a future CLI auto-tag flag (a follow-up issue — see the
// plan's "Other follow-ups to open") can print these exact sentences without
// depending on the app target at all.
//
// EVERY CASE OF EVERY ENUM THIS TOUCHES IS COVERED BY AN EXHAUSTIVE `switch`,
// DELIBERATELY WITH NO `default:` anywhere in this file. `AutoTagJobEvent
// .Kind`, `AutoTagOutcome`, `AutoTagNFOOutcome` and `MetadataSource` have all
// grown new cases across #508's earlier commits, and `MetadataSource` is
// shared with the (unrelated) cloud-metadata-provider code, so it could grow
// again for a reason that has nothing to do with auto-tagging at all. A
// `default:` here would let any of those silently fall through with no
// wording decision ever made for it — the compiler error a new case now
// causes is deliberate friction, not an oversight to route around.
//
// WHERE THIS DELIBERATELY DIVERGES FROM THE PLAN'S "PROPOSED WORDING"
// (`.claude/plans/autotag-encode-plan.md`):
//   * The plan's example "Looking up 'X' on TMDB…" reads as if X is the
//     title already being searched for (the way the success line quotes
//     'Inception (2010)'). But `AutoTagJobEvent.Kind.lookingUp` carries only
//     the `MetadataSource` about to be asked — deliberately minimal, per
//     that case's own doc comment — so this function has no search title to
//     quote at that point. `AutoTagJobEvent.fileName` (the source file's own
//     name) fills X here instead. Widening the event to also carry the
//     query would be a reasonable follow-up if this reads oddly in practice.
//   * The plan gives no wording for `.matchedNothingToAdd` (a real
//     `AutoTagOutcome` case since commit 4: a confident match that added
//     nothing because the file already had every tag it offered) or for a
//     successful MUSIC match specifically. Both are invented here. The music
//     case has no title to quote at all — `AutoTagLookupReport
//     .identifiedFilm` is always `nil` on the music path (see that
//     property's own doc comment in `AutoTagRunner.swift`) — so its wording
//     names only the provider and the tags, never a song title.
//   * "TMDB didn't answer within 30 seconds…" and "TMDB couldn't be
//     reached: <reason>" are the SAME `AutoTagOutcome` case in the code
//     (`.failed(reason:)` — see `AutoTagRunner.Reasons.didNotAnswer`, whose
//     text already names the provider and ends with a full stop). Rather
//     than re-prepending a provider name `reason` may already contain, this
//     file's `.failed` wording is simply `"<reason> Converted without extra
//     tags."` — every `reason` reaching here has already been built as a
//     complete sentence by `AutoTagRunner`.
// ============================================================================

import Foundation

// MARK: - AutoTagWording

/// Turns auto-tag events into Activity Log text. Stateless: every input
/// arrives through the call, and nothing here ever performs a lookup, reads
/// a setting, or touches the Keychain.
public enum AutoTagWording {

    // MARK: The message

    /// The one-line, plain-English sentence for `event`.
    ///
    /// Never empty — `AutoTagWordingTests` pins that for every `Kind` this
    /// type knows about — and never contains raw key material: the only text
    /// an event can carry is a file name, a lookup report, or an NFO
    /// outcome's path/reason, and every failure `reason` reaching here has
    /// already been through `TMDBLookupService`'s key redaction before the
    /// engine ever built the event (see `AutoTagJobEvent`'s own doc comment).
    /// `AutoTagWordingTests` also plants a fake key into a reason string and
    /// checks it never survives into this function's output, belt and
    /// braces.
    public static func message(for event: AutoTagJobEvent) -> String {
        switch event.kind {
        case .lookingUp(let source):
            return "Looking up '\(event.fileName)' on \(shortName(source))…"
        case .lookup(let report):
            return lookupMessage(report)
        case .nfo(let outcome):
            return nfoMessage(outcome)
        }
    }

    /// Whether `event` should be logged as a warning rather than plain
    /// information.
    ///
    /// A separate function from `message(for:)` — not a combined tuple
    /// return — so a caller that wants only one of the two never computes
    /// both, and so the tests that pin exact wording and the tests that pin
    /// warning-ness each read as one clear assertion rather than picking a
    /// field out of a pair.
    public static func isWarning(for event: AutoTagJobEvent) -> Bool {
        switch event.kind {
        case .lookingUp:
            return false
        case .lookup(let report):
            switch report.outcome {
            case .applied, .matchedNothingToAdd, .belowThreshold, .ambiguous, .noMatch, .skipped:
                // Every one of these is an ORDINARY, expected reason nothing
                // (more) was added — off, no key, a TV name, not confident
                // enough, a tie, nothing found. None of them is something
                // gone wrong.
                return false
            case .failed:
                // The one outcome the plan's own "What happens in each case"
                // table calls out as a warning ("Unreachable, 401, 429,
                // 5xx | … | warning …"): a lookup that was ATTEMPTED and did
                // not go as it should have.
                return true
            }
        case .nfo(let outcome):
            switch outcome {
            case .written, .leftExisting:
                // Both are the writer working exactly as designed — see
                // `AutoTagNFOWriter`'s own header, rule 1: an existing `.nfo`
                // being left alone is success, not a problem.
                return false
            case .failed:
                return true
            }
        }
    }

    // MARK: Lookup wording

    /// `AutoTagLookupReport` → one line, covering every `AutoTagOutcome`
    /// case with no `default:` (see this file's header).
    private static func lookupMessage(_ report: AutoTagLookupReport) -> String {
        let provider = report.provider.map(shortName) ?? "the lookup"
        switch report.outcome {
        case .applied:
            return appliedMessage(report, provider: provider)
        case .matchedNothingToAdd:
            return matchedNothingToAddMessage(report, provider: provider)
        case .belowThreshold(let best, let needed):
            return "Best match '\(label(best))' was \(percent(best.confidence)) certain; "
                + "needs \(percent(needed)). Not applied."
        case .ambiguous(let first, let second):
            let noun = candidateNoun(report.provider)
            return "Two \(noun)s matched equally well: '\(label(first))' and '\(label(second))'. Not applied."
        case .noMatch(let query):
            return "\(provider) found nothing for '\(label(query))'."
        case .skipped(let reason):
            return "Not tagged: \(reason)"
        case .failed(let reason):
            return "\(reason) Converted without extra tags."
        }
    }

    /// The `.applied` line: a confident, unambiguous match that added at
    /// least one tag the file was missing. `tagsToAdd` is guaranteed
    /// non-empty for this case (`AutoTagLookupReport.tagsToAdd`'s own doc
    /// comment), so the "Added: …" clause always has something to list.
    private static func appliedMessage(_ report: AutoTagLookupReport, provider: String) -> String {
        let added = tagKeys(report.tagsToAdd)
        var text: String
        if let film = report.identifiedFilm {
            text = "Tagged from \(provider): '\(label(film))', \(percent(film.confidence)) match. Added: \(added)."
        } else {
            // The music path — see this file's header for why there is no
            // title to quote here.
            text = "Tagged from \(provider). Added: \(added)."
        }
        let kept = tagKeys(report.keptExisting)
        if !kept.isEmpty {
            text += " Kept the file's own: \(kept)."
        }
        return text
    }

    /// The `.matchedNothingToAdd` line: a confident match, but the file (or
    /// the job) already carried every tag it would have supplied. Not in the
    /// plan's wording table (see this file's header) — invented here so the
    /// case is not left silently unworded.
    private static func matchedNothingToAddMessage(_ report: AutoTagLookupReport, provider: String) -> String {
        if let film = report.identifiedFilm {
            return "Matched '\(label(film))' on \(provider) (\(percent(film.confidence)) match), "
                + "but the file already had every tag it would have added."
        }
        return "Matched on \(provider), but the file already had every tag it would have added."
    }

    // MARK: NFO wording

    /// `AutoTagNFOOutcome` → one line, covering all three cases with no
    /// `default:`.
    private static func nfoMessage(_ outcome: AutoTagNFOOutcome) -> String {
        switch outcome {
        case .written(let path):
            return "Saved a Kodi .nfo file next to the output ('\(lastPathComponent(path))')."
        case .leftExisting(let path):
            return "An .nfo file already exists there ('\(lastPathComponent(path))'); left it as it is."
        case .failed(let reason):
            return "Couldn't save the .nfo file: \(reason)"
        }
    }

    // MARK: Helpers

    /// A provider's short, familiar name for a log line ("TMDB", not "The
    /// Movie Database (TMDB)" — `MetadataSource.displayName`'s longer form
    /// reads better in a settings picker than in a sentence). Exhaustive
    /// over every `MetadataSource` case, not only the two (`.tmdb`,
    /// `.musicBrainz`) an auto-tag event can carry today — `MetadataSource`
    /// is shared with the unrelated cloud-metadata-provider code (see this
    /// file's header), so this must keep compiling, and keep making a real
    /// choice, however that enum grows.
    static func shortName(_ source: MetadataSource) -> String {
        switch source {
        case .tmdb: return "TMDB"
        case .tvdb: return "TheTVDB"
        case .musicBrainz: return "MusicBrainz"
        case .discogs: return "Discogs"
        case .fanArtTV: return "FanArt.tv"
        case .openSubtitles: return "OpenSubtitles"
        case .omdb: return "OMDb"
        }
    }

    /// What to call two tied candidates in the `.ambiguous` line — "films"
    /// for TMDB, "recordings" for MusicBrainz, and the neutral "matches" for
    /// every other source (none of which an ambiguous auto-tag outcome can
    /// actually carry today, but see `shortName(_:)` for why this still
    /// covers all of them rather than defaulting).
    static func candidateNoun(_ source: MetadataSource?) -> String {
        guard let source else { return "match" }
        switch source {
        case .tmdb: return "film"
        case .musicBrainz: return "recording"
        case .tvdb, .discogs, .fanArtTV, .openSubtitles, .omdb: return "match"
        }
    }

    /// "Title (Year)", or just "Title" when there is no year.
    static func label(_ summary: AutoTagMatchSummary) -> String {
        guard let year = summary.year else { return summary.title }
        return "\(summary.title) (\(year))"
    }

    /// "Title (Year)", or just "Title" — the searched-for query, for the
    /// `.noMatch` line.
    static func label(_ query: MetadataSearchQuery) -> String {
        guard let year = query.year else { return query.title }
        return "\(query.title) (\(year))"
    }

    /// "Title (Year)", or just "Title" — the identified film, for the
    /// `.applied`/`.matchedNothingToAdd` lines.
    static func label(_ film: MetadataResult) -> String {
        guard let year = film.year else { return film.title }
        return "\(film.title) (\(year))"
    }

    /// `confidence` (0...1) as a whole-number percentage string ("52%",
    /// "100%"). Rounds rather than truncates, so a 0.695 read from a real
    /// score never prints as "69%" one point below what actually cleared
    /// (or missed) the threshold it is being compared against in the same
    /// sentence.
    static func percent(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }

    /// A comma-separated list of tag keys, in the order the report gave
    /// them, for the "Added: …" / "Kept the file's own: …" clauses. Lists
    /// raw keys (`date`, `tmdb_id`, …) rather than a humanised name for
    /// each — the same spelling the Metadata tag editor already shows, so a
    /// user comparing the log line against the file's actual tags is
    /// reading the same vocabulary in both places.
    static func tagKeys(_ tags: [MediaTag]) -> String {
        tags.map(\.key).joined(separator: ", ")
    }

    /// The last path component of a full filesystem path, for the NFO
    /// wording — the `.nfo` file's own name, not its full path (which would
    /// repeat the user's whole output folder structure in every log line).
    static func lastPathComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
