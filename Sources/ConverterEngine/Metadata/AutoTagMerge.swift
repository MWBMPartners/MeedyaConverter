// ============================================================================
// MeedyaConverter — AutoTagMerge (Issue #508, commit 2/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The "only add what's missing" rule for the auto-tag feature (#508).
//
// `TMDBTagMapping.applying` and `MusicBrainzTagMapping.applying` were both
// written for the USER-DRIVEN "Write Tags…" flow in the tag editor, where the
// point is exactly the opposite of what auto-tagging needs: the user picked a
// match on purpose, so an existing tag SHOULD be overwritten with it. Both
// functions replace an existing row (matched case-insensitively, including
// known alias spellings such as `date`/`year`, `description`/`synopsis` and
// `track`/`tracknumber`) in place, and only append a fresh row for a key that
// was genuinely absent.
//
// This file reuses that exact matching logic — rather than re-implementing
// "does the file already have a tag equivalent to this key" separately and
// risking it drifting out of step — by running the same `applying` function
// and then sorting its output back into "rows it appended" (safe to add) and
// "rows it replaced" (must NOT be touched; the pre-existing value is kept).
//
// Nothing calls this yet. The runner that will call it during an encode is a
// later commit in issue #508's plan (`.claude/plans/autotag-encode-plan.md`).
// ============================================================================

import Foundation

// MARK: - AutoTagAdditions

/// The result of merging a metadata lookup into a file's existing tags,
/// keeping only what was actually missing.
public struct AutoTagAdditions: Equatable, Sendable {

    /// Tags the lookup supplied for a key neither the job nor the source
    /// file already had. Safe to add to the encode's output metadata.
    public let added: [MediaTag]

    /// Existing tags (the job's own, or copied from the source file) that a
    /// lookup match WOULD have replaced, had this been the user-driven
    /// "Write Tags…" flow. The auto-tag rule deliberately keeps the file's
    /// own value here instead — this list exists mainly so the caller can
    /// report it (the plan's Activity Log wording says "Kept the file's
    /// own: …").
    public let keptExisting: [MediaTag]

    public init(added: [MediaTag], keptExisting: [MediaTag]) {
        self.added = added
        self.keptExisting = keptExisting
    }
}

// MARK: - AutoTagMerge

/// Computes which looked-up tags are genuinely missing from a file.
public enum AutoTagMerge {

    /// Every canonical key (and alias) that `TMDBTagMapping.applying` or
    /// `MusicBrainzTagMapping.applying` can write into the tag table.
    ///
    /// This exists as a single named list, rather than being reconstructed
    /// ad hoc wherever it's needed, because `AutoTagMergeTests` checks it is
    /// a subset of `FFmpegProbe.formatTagKeys`. The auto-tag merge can only
    /// tell whether a key is already present in a file if the probe asked
    /// ffprobe for that key in the first place (see `FFmpegProbe
    /// .formatTagKeys`'s doc comment for why). If a key is ever added to
    /// either mapping type without a matching probe key, that containment
    /// test fails — which is much cheaper to catch than a real file quietly
    /// growing a duplicate tag under a spelling the probe never looked for.
    public static let keysItMayWrite: Set<String> = [
        // `TMDBTagMapping.applying`'s canonical keys and their aliases.
        "title", "date", "year", "genre", "description", "synopsis",
        "director", "tmdb_id",
        // `MusicBrainzTagMapping.applying`'s canonical keys and aliases.
        // ("title" and "date" are shared with TMDB's list above.)
        "artist", "album", "album_artist", "track", "tracknumber", "disc",
        "musicbrainz_trackid", "musicbrainz_albumid",
        "musicbrainz_releasegroupid", "musicbrainz_artistid",
    ]

    /// Work out which looked-up tags are missing from a file, without ever
    /// overwriting a tag the file — or the job — already carries.
    ///
    /// - Parameters:
    ///   - existing: The source file's own tags, as read by the probe (see
    ///     `FFmpegProbe.formatTagKeys`). Blank values (whitespace-only, or
    ///     empty) are treated as absent, because ffprobe can report a tag
    ///     key with nothing meaningful in it and that must not block a real
    ///     value the lookup found.
    ///   - jobTags: The encode job's own `outputMetadata`, which always
    ///     takes priority: a value the user set for THIS job wins over both
    ///     the source file's existing value and anything a lookup found.
    ///   - applying: Runs one of `TMDBTagMapping.applying` or
    ///     `MusicBrainzTagMapping.applying`, already bound to the chosen
    ///     lookup result, over the base tag list this function builds. This
    ///     function does not know about `MetadataResult` or
    ///     `MusicBrainzRecordingMatch` at all — it only relies on the
    ///     contract both `applying` functions share: replace an existing row
    ///     in place (same `id`, same key spelling) when a matching key or
    ///     alias is found, otherwise append a brand new `MediaTag` (a fresh
    ///     `id`).
    /// - Returns: Which rows are genuinely new (`added`), and which rows a
    ///   lookup would have replaced but were kept as they were
    ///   (`keptExisting`).
    public static func additions(
        existing: [MediaTag],
        jobTags: [MediaTag],
        applying: ([MediaTag]) -> [MediaTag]
    ) -> AutoTagAdditions {
        // Non-blank source tags first, then the job's own tags layered on
        // top (replacing a source tag with the same key, case-insensitively,
        // so the job's value is the one `applying` sees for that key). Only
        // the SET OF KEYS present in `base` matters for what follows — any
        // key already here causes `applying` to replace, not append — but
        // using the job's value keeps `keptExisting` honest about what the
        // encode will actually carry.
        let nonBlankExisting = existing.filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var base = nonBlankExisting
        for jobTag in jobTags {
            if let index = base.firstIndex(where: {
                $0.key.caseInsensitiveCompare(jobTag.key) == .orderedSame
            }) {
                base[index] = jobTag
            } else {
                base.append(jobTag)
            }
        }

        // Every id in `base` existed BEFORE `applying` ran. Both
        // `TMDBTagMapping.applying` and `MusicBrainzTagMapping.applying`
        // preserve a replaced row's `id` and only mint a fresh one
        // (`MediaTag(key:value:)`'s default `id: UUID()`) for a row they
        // append — so an id from `result` that is NOT in this set can only
        // be a row `applying` appended because it found no existing key or
        // alias for it. That is exactly "genuinely missing".
        let baseIDsByID = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })

        let result = applying(base)

        var added: [MediaTag] = []
        var keptExisting: [MediaTag] = []
        for tag in result {
            if let original = baseIDsByID[tag.id] {
                // `applying` replaced this row — keep the ORIGINAL value
                // (`original`), not `tag` (which carries the lookup's
                // replacement value that must not be applied here).
                keptExisting.append(original)
            } else {
                added.append(tag)
            }
        }
        return AutoTagAdditions(added: added, keptExisting: keptExisting)
    }
}
