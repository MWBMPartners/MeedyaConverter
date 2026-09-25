// ============================================================================
// MeedyaConverter — AutoTagger
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - AutoTagSource

/// Sources used for automatic metadata tagging.
public enum AutoTagSource: String, Codable, Sendable, CaseIterable {
    /// Parse metadata from filename patterns.
    case filename = "filename"

    /// Use AcoustID/Chromaprint audio fingerprint.
    case audioFingerprint = "audio_fingerprint"

    /// Use existing file metadata (copy from source).
    case existingMetadata = "existing_metadata"

    /// Look up from TMDB by title/year.
    case tmdb = "tmdb"

    /// Look up from TheTVDB by show/season/episode.
    case tvdb = "tvdb"

    /// Look up from MusicBrainz by recording.
    case musicBrainz = "musicbrainz"

    /// Look up from Discogs by barcode or catalog number.
    case discogs = "discogs"

    /// Display name.
    public var displayName: String {
        switch self {
        case .filename: return "Filename Parsing"
        case .audioFingerprint: return "Audio Fingerprint"
        case .existingMetadata: return "Existing Metadata"
        case .tmdb: return "TMDB Lookup"
        case .tvdb: return "TheTVDB Lookup"
        case .musicBrainz: return "MusicBrainz Lookup"
        case .discogs: return "Discogs Lookup"
        }
    }

    /// Whether this source requires network access.
    public var requiresNetwork: Bool {
        switch self {
        case .filename, .existingMetadata: return false
        default: return true
        }
    }

    /// Whether this source requires an API key.
    public var requiresAPIKey: Bool {
        switch self {
        case .filename, .existingMetadata, .musicBrainz: return false
        default: return true
        }
    }
}

// MARK: - AutoTagConfig

/// Configuration for automatic metadata tagging on encode.
public struct AutoTagConfig: Codable, Sendable, Equatable {
    /// Whether auto-tagging is enabled.
    public var enabled: Bool

    /// Ordered list of sources to try (first match wins).
    public var sources: [AutoTagSource]

    /// Minimum confidence threshold (0.0–1.0) for accepting a match.
    public var minimumConfidence: Double

    /// Whether to embed artwork (poster/cover) into the output file.
    ///
    /// Not acted on yet. Nothing in this codebase reads this flag and embeds
    /// artwork during an encode — see `buildArtworkArguments` below for why
    /// that would currently break one. It defaults to `false` so the field
    /// cannot silently promise something no code delivers.
    public var embedArtwork: Bool

    /// Whether to write Kodi-compatible NFO alongside the output.
    public var writeNFO: Bool

    /// Whether to rename the output file using metadata.
    ///
    /// Not acted on yet. Nothing calls `generateOutputFilename` from a real
    /// encode path today; see issue #508's plan for why renaming is a
    /// separate, later piece of work (it touches ~10 post-encode readers of
    /// the output path).
    public var renameOutput: Bool

    /// Naming template for renamed output (Plex-style by default).
    ///
    /// Not acted on yet — this only has an effect once `renameOutput` above
    /// does.
    public var namingTemplate: NamingTemplate

    /// Maximum number of search results to consider.
    public var maxResults: Int

    /// Language preference for metadata (ISO 639-1).
    public var language: String

    public init(
        enabled: Bool = false,
        sources: [AutoTagSource] = [.filename, .existingMetadata, .tmdb],
        minimumConfidence: Double = 0.7,
        embedArtwork: Bool = false,
        writeNFO: Bool = false,
        renameOutput: Bool = false,
        namingTemplate: NamingTemplate = .plex,
        maxResults: Int = 5,
        language: String = "en"
    ) {
        self.enabled = enabled
        self.sources = sources
        self.minimumConfidence = minimumConfidence
        self.embedArtwork = embedArtwork
        self.writeNFO = writeNFO
        self.renameOutput = renameOutput
        self.namingTemplate = namingTemplate
        self.maxResults = maxResults
        self.language = language
    }
}

// MARK: - NamingTemplate

/// File naming templates for auto-tag rename.
public enum NamingTemplate: String, Codable, Sendable, CaseIterable {
    /// Plex naming: "Movie (Year).ext" / "Show - S01E02 - Episode.ext"
    case plex = "plex"

    /// Jellyfin naming (same as Plex for most purposes).
    case jellyfin = "jellyfin"

    /// Kodi naming: "Movie (Year)/Movie (Year).ext"
    case kodi = "kodi"

    /// Simple: "Title.ext"
    case simple = "simple"

    /// Display name.
    public var displayName: String {
        switch self {
        case .plex: return "Plex"
        case .jellyfin: return "Jellyfin"
        case .kodi: return "Kodi"
        case .simple: return "Simple"
        }
    }
}

// MARK: - AutoTagger

/// A set of small, pure helpers used by the auto-tag feature (issue #508).
///
/// **What this type actually does today.** It is a bag of stateless helper
/// functions — filename parsing/sanitising, output-filename and NFO-path
/// generation, lookup-order and confidence-threshold checks. None of them run
/// automatically. Nothing in this codebase calls them from a real encode: the
/// only callers outside this file are its own tests
/// (`ConverterEngineTests+ToolingAndMetadata.swift`).
///
/// **What is missing, and where it is being built.** The piece that actually
/// runs a lookup during an encode and merges the result into the job's
/// metadata is being added incrementally under issue #508 — see
/// `.claude/plans/autotag-encode-plan.md`. `AutoTagSettingsStore` and
/// `AutoTagSettingsSource` (added in that plan's third commit) hold the
/// setting and the fixed parts of the configuration; `EncodingEngine` reads
/// them and calls into a runner (a later commit) that uses the helpers below.
/// Until that wiring lands, changing `AutoTagConfig`'s fields has no visible
/// effect on any encode.
///
/// Previously this type also had `buildMetadataArguments(result:config:)`,
/// which was removed in this commit: it had no caller anywhere in `Sources/`
/// or `Tests/`, ignored the `config` it was given, and built a different set
/// of metadata keys than the ones the real merge path (`AutoTagMerge`, added
/// alongside the runner) uses. Keeping a dead, misleading function around was
/// worse than deleting it.
public struct AutoTagger: Sendable {

    // MARK: - FFmpeg Metadata Building

    /// Build FFmpeg arguments to embed cover art from a local file.
    ///
    /// - Warning: This is a **remux-only** argument fragment. It adds a
    ///   second `-map` for the artwork and forces `-c copy`, so appending it
    ///   to the arguments for a real transcode (any encode that is not
    ///   `-c copy` already) would silently turn that transcode into a copy —
    ///   the video/audio codec settings the job asked for would be dropped.
    ///   Nothing in this codebase calls this yet; a caller must not use it
    ///   inside an encode pipeline without accounting for that.
    ///
    /// - Parameters:
    ///   - artworkPath: Local path to the artwork file.
    ///   - streamIndex: Stream index for the artwork (typically after video+audio).
    /// - Returns: FFmpeg argument array.
    public static func buildArtworkArguments(
        artworkPath: String,
        streamIndex: Int = 2
    ) -> [String] {
        return [
            "-i", artworkPath,
            "-map", "0", "-map", "1",
            "-c", "copy",
            "-disposition:v:\(streamIndex)", "attached_pic",
        ]
    }

    // MARK: - Output Path Generation

    /// Generate the output filename based on metadata and naming template.
    ///
    /// - Parameters:
    ///   - result: Metadata lookup result.
    ///   - template: Naming template.
    ///   - extension_: File extension (without dot).
    /// - Returns: Generated filename.
    public static func generateOutputFilename(
        result: MetadataResult,
        template: NamingTemplate,
        extension_: String
    ) -> String {
        switch template {
        case .plex, .jellyfin:
            switch result.source {
            case .tmdb, .omdb:
                return MediaServerTagging.buildPlexMovieFilename(
                    title: result.title,
                    year: result.year ?? 0,
                    extension_: extension_
                )
            case .tvdb:
                return MediaServerTagging.buildPlexEpisodeFilename(
                    showTitle: result.title,
                    season: result.season ?? 1,
                    episode: result.episode ?? 1,
                    extension_: extension_
                )
            default:
                return "\(result.title).\(extension_)"
            }

        case .kodi:
            if let year = result.year {
                return "\(result.title) (\(year)).\(extension_)"
            }
            return "\(result.title).\(extension_)"

        case .simple:
            return "\(result.title).\(extension_)"
        }
    }

    /// Generate the Kodi NFO sidecar path for a given output path.
    ///
    /// - Parameters:
    ///   - outputPath: Path to the encoded output file.
    ///   - mediaType: Type of media (movie, TV, music).
    /// - Returns: NFO file path.
    public static func generateNFOPath(
        outputPath: String,
        mediaType: MediaLookupType
    ) -> String {
        let basePath = (outputPath as NSString).deletingPathExtension
        return "\(basePath).nfo"
    }

    // MARK: - Pipeline Orchestration

    /// Determine which lookup sources to try based on parsed filename.
    ///
    /// - Parameters:
    ///   - query: Parsed filename metadata query.
    ///   - config: Auto-tag configuration.
    /// - Returns: Ordered list of (source, url-builder) to try.
    public static func determineLookupOrder(
        query: MetadataSearchQuery,
        config: AutoTagConfig
    ) -> [AutoTagSource] {
        return config.sources.filter { source in
            switch source {
            case .tmdb:
                return query.mediaType == .movie || query.mediaType == .tvShow
            case .tvdb:
                return query.mediaType == .tvEpisode || query.mediaType == .tvShow
            case .musicBrainz, .discogs, .audioFingerprint:
                return query.mediaType == .music || query.mediaType == .musicAlbum
            case .filename, .existingMetadata:
                return true
            }
        }
    }

    /// Check if a result meets the confidence threshold.
    ///
    /// - Parameters:
    ///   - result: Metadata result to check.
    ///   - config: Auto-tag configuration.
    /// - Returns: `true` if confidence is sufficient.
    public static func meetsThreshold(
        result: MetadataResult,
        config: AutoTagConfig
    ) -> Bool {
        return result.confidence >= config.minimumConfidence
    }

    /// Sanitise a filename by removing invalid characters.
    ///
    /// - Parameter filename: Raw filename.
    /// - Returns: Sanitised filename safe for all platforms.
    public static func sanitiseFilename(_ filename: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        var sanitised = filename.components(separatedBy: invalidChars).joined(separator: "")
        // Trim whitespace and dots from ends
        sanitised = sanitised.trimmingCharacters(in: .whitespaces)
        // Remove trailing dots (invalid on Windows)
        while sanitised.hasSuffix(".") {
            sanitised = String(sanitised.dropLast())
        }
        return sanitised
    }
}
