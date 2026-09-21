// ============================================================================
// MeedyaConverter — TMDB → tag table mapping (Issue #205)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The video counterpart of `MusicBrainzTagMapping`: turn a chosen TMDB
// result into rows in the metadata tag table, and work out what to search
// for in the first place.
//
// Pure and deterministic — no network, no I/O — so the wording of every tag
// it writes is unit-tested.
//
// Key spellings follow `MediaServerTagging.buildFFmpegMetadataArguments`
// (`title`, `date`, `description`/`synopsis`, `genre`, `director`), because
// a file tagged here and a file tagged by the auto-tagger must end up with
// the SAME keys — otherwise a media server sees two different schemas
// depending on which route produced the file.
// ============================================================================

import Foundation

// MARK: - EmbeddedArtwork

/// Telling an embedded cover image apart from actual moving video.
///
/// ⚠️ ffprobe reports an attached picture as a *video stream*, so an MP3 or
/// FLAC with cover art has `hasVideo == true`. Anything deciding "is this a
/// film or a song?" from `hasVideo` alone will offer a film lookup for a
/// music file. `MediaStream` carries no disposition field, so the codec is
/// what we have to go on.
public enum EmbeddedArtwork {

    /// Codecs that only ever appear as a still image in a media file.
    public static let stillImageCodecs: Set<String> = [
        "mjpeg", "jpeg", "jpg", "png", "bmp", "gif", "webp",
        "tiff", "ppm", "pgm", "targa", "tga", "smc", "qdraw",
    ]

    /// Whether `stream` is a still image rather than moving video.
    public static func isStillImage(_ stream: MediaStream) -> Bool {
        guard let codec = stream.codecName?.lowercased(), !codec.isEmpty else {
            return false
        }
        return stillImageCodecs.contains(codec)
    }
}

extension MediaFile {

    /// Video streams that actually move, with embedded artwork excluded.
    public var movingVideoStreams: [MediaStream] {
        videoStreams.filter { !EmbeddedArtwork.isStillImage($0) }
    }

    /// Whether this file carries real moving video.
    ///
    /// Use this rather than `hasVideo` whenever the answer decides how the
    /// file is TREATED — `hasVideo` counts cover art, so it says yes to a
    /// tagged MP3.
    public var hasMovingVideo: Bool {
        !movingVideoStreams.isEmpty
    }

    /// Whether to treat this as a film or programme rather than music.
    ///
    /// Requires BOTH moving video and a container that can hold video: an
    /// `.m4a` should never be offered a film lookup whatever its streams
    /// claim, and a container check alone would say yes to every `.mp3`.
    public var looksLikeVideoContent: Bool {
        guard hasMovingVideo else { return false }
        guard let container = containerFormat else { return true }
        return container.supportsVideo
    }
}

// MARK: - TMDBTagMapping

public enum TMDBTagMapping {

    /// The value of `key` in `tags`, matched case-insensitively.
    public static func value(forKey key: String, in tags: [MediaTag]) -> String? {
        tags.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    /// What to search TMDB for, given the file's existing tags and its name.
    ///
    /// Prefers a `title` tag the file already carries; falls back to parsing
    /// the filename, which is where a year usually comes from too.
    public static func seedQuery(tags: [MediaTag], filename: String) -> MetadataSearchQuery {
        let parsed = FilenameParser.parse(filename: filename)
        let taggedTitle = value(forKey: "title", in: tags)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let title = (taggedTitle?.isEmpty == false ? taggedTitle : nil) ?? parsed.title

        // A four-digit `date` tag is a year; a full date still starts with one.
        let taggedYear = value(forKey: "date", in: tags)
            .flatMap { Int($0.prefix(4)) }
            .flatMap { (1900...2100).contains($0) ? $0 : nil }

        return MetadataSearchQuery(
            mediaType: parsed.mediaType == .tvEpisode ? .tvShow : .movie,
            title: title,
            year: taggedYear ?? parsed.year
        )
    }

    /// Apply a chosen TMDB result to the tag table.
    ///
    /// Existing rows are REPLACED in place (keeping their id and their
    /// original key spelling) and missing ones appended. Nothing is ever
    /// deleted: a tag the file already had that TMDB knows nothing about is
    /// the user's, not ours to discard.
    public static func applying(
        _ result: MetadataResult,
        to tags: [MediaTag],
        includeIdentifiers: Bool
    ) -> [MediaTag] {
        var updated = tags

        func apply(canonicalKey: String, value: String?, aliases: [String] = []) {
            guard let value, !value.isEmpty else { return }
            let candidateKeys = [canonicalKey] + aliases
            if let index = updated.firstIndex(where: { tag in
                candidateKeys.contains { tag.key.caseInsensitiveCompare($0) == .orderedSame }
            }) {
                let existing = updated[index]
                updated[index] = MediaTag(id: existing.id, key: existing.key, value: value)
            } else {
                updated.append(MediaTag(key: canonicalKey, value: value))
            }
        }

        apply(canonicalKey: "title", value: result.title)
        apply(canonicalKey: "date", value: result.year.map { String($0) }, aliases: ["year"])
        if !result.genres.isEmpty {
            apply(canonicalKey: "genre", value: result.genres.joined(separator: "; "))
        }
        // `synopsis` only — deliberately NOT `comment`. A comment is usually
        // the user's own note about the file ("ripped from my DVD"), and
        // silently replacing it with a studio synopsis destroys something
        // they wrote and cannot get back.
        apply(canonicalKey: "description", value: result.overview, aliases: ["synopsis"])
        if !result.directors.isEmpty {
            apply(canonicalKey: "director", value: result.directors.joined(separator: "; "))
        }

        if includeIdentifiers {
            // Namespaced so it can never collide with a tag the file already
            // had, and so its origin is obvious to anyone reading the table.
            apply(canonicalKey: "tmdb_id", value: result.externalId)
        }

        return updated
    }
}
