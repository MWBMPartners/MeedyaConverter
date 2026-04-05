// ============================================================================
// MeedyaConverter — MetadataTagEditor (Issue #320)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MediaTag

/// A single key-value metadata tag for a media file.
///
/// Represents one FFmpeg metadata entry such as ``title``, ``artist``,
/// ``album``, etc. Tags are written to the output file using the
/// ``-metadata key=value`` FFmpeg argument syntax.
///
/// Phase 6 — Full Metadata Tag Editor (Issue #320)
public struct MediaTag: Identifiable, Codable, Sendable, Equatable {

    /// Unique identifier for this tag instance.
    public let id: UUID

    /// The metadata key (e.g., "title", "artist", "album").
    /// Case-insensitive in FFmpeg; stored as provided by the user.
    public let key: String

    /// The metadata value (e.g., "My Movie", "John Doe").
    public let value: String

    /// Creates a new media tag.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if omitted).
    ///   - key: Metadata key name.
    ///   - value: Metadata value.
    public init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

// MARK: - MetadataTagEditor

/// Builds FFmpeg argument arrays for reading, writing, clearing, and
/// embedding metadata tags and artwork in media files.
///
/// Supports three operations:
/// 1. **Write tags** — add or overwrite specific metadata fields using
///    ``-metadata key=value`` arguments, with optional artwork embedding.
/// 2. **Clear tags** — remove all existing metadata using ``-map_metadata -1``.
/// 3. **Embed artwork** — attach a cover image using the ``-attach`` mechanism
///    or via a video stream mapped as a thumbnail.
///
/// Phase 6 — Full Metadata Tag Editor (Issue #320)
public struct MetadataTagEditor: Sendable {

    // MARK: - Common Tags

    /// Standard metadata tag keys commonly used across media formats.
    ///
    /// These keys are widely supported by FFmpeg, MP4, MKV, FLAC, and
    /// other container formats. The list follows the Vorbis Comment /
    /// FFmpeg naming convention.
    public static let commonTags: [String] = [
        "title",
        "artist",
        "album",
        "album_artist",
        "date",
        "genre",
        "track",
        "disc",
        "comment",
        "description",
        "copyright",
        "encoder"
    ]

    // MARK: - Write Arguments

    /// Builds FFmpeg arguments to write metadata tags and optionally
    /// embed artwork into a media file.
    ///
    /// Each tag is emitted as a ``-metadata key=value`` argument.
    /// If ``artworkPath`` is provided, the artwork is attached as an
    /// additional input mapped as a video stream (cover art).
    ///
    /// - Parameters:
    ///   - tags: Array of ``MediaTag`` key-value pairs to write.
    ///   - artworkPath: Optional path to a cover art image file
    ///     (JPEG, PNG). Pass ``nil`` to skip artwork embedding.
    /// - Returns: FFmpeg argument array (to be appended after input/output args).
    public static func buildWriteArguments(
        tags: [MediaTag],
        artworkPath: String?
    ) -> [String] {
        var args: [String] = []

        // Add metadata tags
        for tag in tags where !tag.key.isEmpty && !tag.value.isEmpty {
            args += ["-metadata", "\(tag.key)=\(tag.value)"]
        }

        // Embed artwork if provided
        if let artworkPath = artworkPath {
            args += buildArtworkEmbedArguments(artworkPath: artworkPath)
        }

        return args
    }

    // MARK: - Clear Arguments

    /// Builds FFmpeg arguments to strip all existing metadata from a
    /// media file.
    ///
    /// Uses ``-map_metadata -1`` to discard all global, stream, and
    /// chapter metadata from the output. Useful for sanitising files
    /// before redistribution or when starting fresh with new tags.
    ///
    /// - Returns: FFmpeg argument array for metadata removal.
    public static func buildClearArguments() -> [String] {
        ["-map_metadata", "-1"]
    }

    // MARK: - Artwork Embedding

    /// Builds FFmpeg arguments to embed a cover art image into a
    /// media file.
    ///
    /// The artwork is added as an additional input and mapped as a
    /// video stream with the ``attached_pic`` disposition. This is the
    /// standard method for embedding cover art in MP4, MKV, and other
    /// container formats.
    ///
    /// Supported image formats: JPEG, PNG, BMP.
    ///
    /// - Parameter artworkPath: Absolute path to the cover art image file.
    /// - Returns: FFmpeg argument array for artwork embedding.
    public static func buildArtworkEmbedArguments(artworkPath: String) -> [String] {
        var args: [String] = []

        // Add artwork as an additional input
        args += ["-i", artworkPath]

        // Map the artwork stream and set its disposition to attached_pic.
        // The artwork input index depends on context; callers should adjust
        // the map index if multiple inputs are used. This uses a
        // placeholder index that assumes artwork is the second input.
        args += ["-map", "1:v:0"]
        args += ["-c:v:1", "copy"]
        args += ["-disposition:v:1", "attached_pic"]

        // Set the MIME type metadata for the artwork stream
        args += ["-metadata:s:v:1", "mimetype=image/jpeg"]

        return args
    }
}
