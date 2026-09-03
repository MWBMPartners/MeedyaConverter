// ============================================================================
// MeedyaConverter — MusicBrainzTagMapping (Issue #205, follows #493)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MusicBrainzTagMapping

/// Pure helpers that connect a `MusicBrainzRecordingMatch` to the tag table
/// `MetadataTagEditorView` edits: seeding the lookup query from the file's
/// current tags/filename, ranking candidate matches, and merging a chosen
/// match's fields into the `[MediaTag]` array the "Write Tags…" path already
/// writes with FFmpeg's `-metadata key=value` arguments.
///
/// Identifier tags (`musicbrainz_trackid` etc.) are written with `-metadata`
/// like any other key; whether a container keeps non-standard keys is up to
/// ffmpeg's muxer (FLAC/Ogg store them as Vorbis comments; ffmpeg's MP4
/// muxer drops keys it does not recognise unless `-movflags
/// use_metadata_tags` is passed, which `MetadataTagEditor.buildWriteArguments`
/// does not).
public enum MusicBrainzTagMapping {

    /// Case-insensitive lookup of a tag value (first match, trimmed, nil if blank).
    public static func value(forKey key: String, in tags: [MediaTag]) -> String? {
        for tag in tags where tag.key.caseInsensitiveCompare(key) == .orderedSame {
            let trimmed = tag.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    /// Seed for the lookup sheet: title/artist/album from the file's existing tags
    /// (`title`, `artist` → `album_artist`, `album`, any key spelling), falling back to
    /// `FilenameParser.parse(filename:)` — its `title` always, its `artist` only when
    /// it recognised the `Artist - Title` music pattern. `mediaType` is `.music`.
    public static func seedQuery(tags: [MediaTag], filename: String) -> MetadataSearchQuery {
        let parsed = FilenameParser.parse(filename: filename)

        let title = value(forKey: "title", in: tags) ?? parsed.title
        let artist = value(forKey: "artist", in: tags)
            ?? value(forKey: "album_artist", in: tags)
            ?? (parsed.mediaType == .music ? parsed.artist : nil)
        let album = value(forKey: "album", in: tags)

        return MetadataSearchQuery(mediaType: .music, title: title, artist: artist, album: album)
    }

    /// Stable order: score descending, then |lengthSeconds − fileDurationSeconds|
    /// ascending (unknown length last), then server order. Unchanged when
    /// `fileDurationSeconds` is nil or ≤ 0.
    public static func ranked(
        _ matches: [MusicBrainzRecordingMatch],
        fileDurationSeconds: Double?
    ) -> [MusicBrainzRecordingMatch] {
        guard let fileDurationSeconds, fileDurationSeconds > 0 else { return matches }

        let indexed = Array(matches.enumerated())
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.element.score != rhs.element.score {
                return lhs.element.score > rhs.element.score
            }
            let lhsDiff = lhs.element.lengthSeconds.map { abs($0 - fileDurationSeconds) }
            let rhsDiff = rhs.element.lengthSeconds.map { abs($0 - fileDurationSeconds) }
            switch (lhsDiff, rhsDiff) {
            case let (l?, r?):
                if l != r { return l < r }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }
            return lhs.offset < rhs.offset
        }
        return sorted.map(\.element)
    }

    /// Returns `tags` with the match's fields applied. For each canonical key with a
    /// non-empty value — `title`, `artist`, `album`, `album_artist`, `date`
    /// (release.date ?? firstReleaseDate), `track` (numeric only; also matches an
    /// existing `tracknumber`), `disc` (only when mediumPosition > 1) and, when
    /// `includeIdentifiers`, `musicbrainz_trackid` (recording MBID),
    /// `musicbrainz_albumid`, `musicbrainz_releasegroupid`, `musicbrainz_artistid`
    /// (IDs joined with "; ", the house convention from
    /// `MediaServerTagging.buildFFmpegMetadataArguments`) — the FIRST existing tag whose
    /// key matches case-insensitively is replaced in place (same `id`, same key
    /// spelling), otherwise a `MediaTag(key: canonical, value:)` is appended in that
    /// order. Tags with no corresponding field are untouched; nothing is deleted.
    public static func applying(
        _ match: MusicBrainzRecordingMatch,
        release: MusicBrainzRecordingMatch.Release?,
        to tags: [MediaTag],
        includeIdentifiers: Bool
    ) -> [MediaTag] {
        var result = tags

        func apply(canonicalKey: String, value: String?, aliases: [String] = []) {
            guard let value, !value.isEmpty else { return }
            let candidateKeys = [canonicalKey] + aliases
            if let index = result.firstIndex(where: { tag in
                candidateKeys.contains { tag.key.caseInsensitiveCompare($0) == .orderedSame }
            }) {
                let existing = result[index]
                result[index] = MediaTag(id: existing.id, key: existing.key, value: value)
            } else {
                result.append(MediaTag(key: canonicalKey, value: value))
            }
        }

        apply(canonicalKey: "title", value: match.title)
        apply(canonicalKey: "artist", value: match.artist)
        apply(canonicalKey: "album", value: release?.title)
        apply(canonicalKey: "album_artist", value: release?.albumArtist)
        apply(canonicalKey: "date", value: release?.date ?? match.firstReleaseDate)
        if let trackValue = release?.trackNumberValue {
            apply(canonicalKey: "track", value: String(trackValue), aliases: ["tracknumber"])
        }
        if let position = release?.mediumPosition, position > 1 {
            apply(canonicalKey: "disc", value: String(position))
        }
        if includeIdentifiers {
            apply(canonicalKey: "musicbrainz_trackid", value: match.id)
            apply(canonicalKey: "musicbrainz_albumid", value: release?.id)
            apply(canonicalKey: "musicbrainz_releasegroupid", value: release?.releaseGroupID)
            let artistIDs = match.artistIDs
            if !artistIDs.isEmpty {
                apply(canonicalKey: "musicbrainz_artistid", value: artistIDs.joined(separator: "; "))
            }
        }

        return result
    }
}
