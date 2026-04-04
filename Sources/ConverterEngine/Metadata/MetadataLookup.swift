// ============================================================================
// MeedyaConverter — MetadataLookup
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MetadataSource

/// Supported metadata lookup sources.
public enum MetadataSource: String, Codable, Sendable, CaseIterable {
    /// The Movie Database (TMDB) — movies and TV shows.
    case tmdb = "tmdb"

    /// TheTVDB — TV show metadata.
    case tvdb = "tvdb"

    /// MusicBrainz — music metadata.
    case musicBrainz = "musicbrainz"

    /// Discogs — physical media / vinyl metadata.
    case discogs = "discogs"

    /// FanArt.tv — high-quality artwork.
    case fanArtTV = "fanart_tv"

    /// OpenSubtitles — subtitle search.
    case openSubtitles = "opensubtitles"

    /// OMDb API — IMDB data proxy.
    case omdb = "omdb"

    /// Display name.
    public var displayName: String {
        switch self {
        case .tmdb: return "The Movie Database (TMDB)"
        case .tvdb: return "TheTVDB"
        case .musicBrainz: return "MusicBrainz"
        case .discogs: return "Discogs"
        case .fanArtTV: return "FanArt.tv"
        case .openSubtitles: return "OpenSubtitles"
        case .omdb: return "OMDb (IMDB)"
        }
    }

    /// Base API URL for the source.
    public var baseURL: String {
        switch self {
        case .tmdb: return "https://api.themoviedb.org/3"
        case .tvdb: return "https://api4.thetvdb.com/v4"
        case .musicBrainz: return "https://musicbrainz.org/ws/2"
        case .discogs: return "https://api.discogs.com"
        case .fanArtTV: return "https://webservice.fanart.tv/v3"
        case .openSubtitles: return "https://api.opensubtitles.com/api/v1"
        case .omdb: return "https://www.omdbapi.com"
        }
    }

    /// Whether this source requires an API key.
    public var requiresAPIKey: Bool {
        switch self {
        case .musicBrainz: return false // Public API with rate limiting
        default: return true
        }
    }
}

// MARK: - MediaType

/// The type of media being looked up.
public enum MediaLookupType: String, Codable, Sendable {
    case movie = "movie"
    case tvShow = "tv"
    case tvEpisode = "episode"
    case music = "music"
    case musicAlbum = "album"
}

// MARK: - MetadataSearchQuery

/// A query for metadata search.
public struct MetadataSearchQuery: Codable, Sendable {
    /// The media type to search for.
    public var mediaType: MediaLookupType

    /// Search title/name.
    public var title: String

    /// Year of release (optional, improves accuracy).
    public var year: Int?

    /// Season number (for TV episodes).
    public var season: Int?

    /// Episode number (for TV episodes).
    public var episode: Int?

    /// Artist name (for music).
    public var artist: String?

    /// Album name (for music).
    public var album: String?

    /// Language preference for results (ISO 639-1).
    public var language: String

    public init(
        mediaType: MediaLookupType,
        title: String,
        year: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        artist: String? = nil,
        album: String? = nil,
        language: String = "en"
    ) {
        self.mediaType = mediaType
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.artist = artist
        self.album = album
        self.language = language
    }
}

// MARK: - MetadataResult

/// A metadata lookup result.
public struct MetadataResult: Codable, Sendable {
    /// The source that provided this result.
    public var source: MetadataSource

    /// External ID from the source.
    public var externalId: String

    /// Title / name.
    public var title: String

    /// Original title (if different from localised).
    public var originalTitle: String?

    /// Year of release.
    public var year: Int?

    /// Description / synopsis.
    public var overview: String?

    /// Genres.
    public var genres: [String]

    /// Poster image URL.
    public var posterURL: String?

    /// Backdrop / fanart URL.
    public var backdropURL: String?

    /// Content rating (e.g., "PG-13", "TV-MA").
    public var rating: String?

    /// Average user score (0.0–10.0).
    public var score: Double?

    /// Runtime in minutes.
    public var runtimeMinutes: Int?

    /// Cast / performers.
    public var cast: [String]

    /// Director(s).
    public var directors: [String]

    /// Release date.
    public var releaseDate: String?

    /// Season number (TV).
    public var season: Int?

    /// Episode number (TV).
    public var episode: Int?

    /// Artist (music).
    public var artist: String?

    /// Album (music).
    public var album: String?

    /// Track number (music).
    public var trackNumber: Int?

    /// Match confidence (0.0–1.0).
    public var confidence: Double

    public init(
        source: MetadataSource,
        externalId: String,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        genres: [String] = [],
        posterURL: String? = nil,
        backdropURL: String? = nil,
        rating: String? = nil,
        score: Double? = nil,
        runtimeMinutes: Int? = nil,
        cast: [String] = [],
        directors: [String] = [],
        releaseDate: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        artist: String? = nil,
        album: String? = nil,
        trackNumber: Int? = nil,
        confidence: Double = 0.5
    ) {
        self.source = source
        self.externalId = externalId
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.overview = overview
        self.genres = genres
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.rating = rating
        self.score = score
        self.runtimeMinutes = runtimeMinutes
        self.cast = cast
        self.directors = directors
        self.releaseDate = releaseDate
        self.season = season
        self.episode = episode
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.confidence = confidence
    }
}

// MARK: - TMDBClient

/// Builds TMDB API request URLs for movie and TV metadata lookup.
///
/// Phase 15.1
public struct TMDBClient: Sendable {

    /// Build a TMDB movie search URL.
    public static func buildMovieSearchURL(
        query: String,
        year: Int? = nil,
        language: String = "en-US",
        apiKey: String
    ) -> String {
        var url = "\(MetadataSource.tmdb.baseURL)/search/movie?api_key=\(apiKey)"
        url += "&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        url += "&language=\(language)"
        if let y = year { url += "&year=\(y)" }
        return url
    }

    /// Build a TMDB TV show search URL.
    public static func buildTVSearchURL(
        query: String,
        year: Int? = nil,
        language: String = "en-US",
        apiKey: String
    ) -> String {
        var url = "\(MetadataSource.tmdb.baseURL)/search/tv?api_key=\(apiKey)"
        url += "&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        url += "&language=\(language)"
        if let y = year { url += "&first_air_date_year=\(y)" }
        return url
    }

    /// Build a TMDB movie details URL.
    public static func buildMovieDetailsURL(
        movieId: Int,
        language: String = "en-US",
        apiKey: String
    ) -> String {
        return "\(MetadataSource.tmdb.baseURL)/movie/\(movieId)?api_key=\(apiKey)&language=\(language)&append_to_response=credits"
    }

    /// Build the full poster image URL from a TMDB poster path.
    public static func posterURL(path: String, size: String = "w500") -> String {
        return "https://image.tmdb.org/t/p/\(size)\(path)"
    }
}

// MARK: - MusicBrainzClient

/// Builds MusicBrainz API request URLs for music metadata lookup.
///
/// Phase 15.2
public struct MusicBrainzClient: Sendable {

    /// Build a MusicBrainz recording search URL.
    public static func buildRecordingSearchURL(
        title: String,
        artist: String? = nil
    ) -> String {
        var query = "recording:\(title)"
        if let art = artist { query += " AND artist:\(art)" }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return "\(MetadataSource.musicBrainz.baseURL)/recording?query=\(encoded)&fmt=json&limit=10"
    }

    /// Build a MusicBrainz release (album) search URL.
    public static func buildReleaseSearchURL(
        album: String,
        artist: String? = nil
    ) -> String {
        var query = "release:\(album)"
        if let art = artist { query += " AND artist:\(art)" }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return "\(MetadataSource.musicBrainz.baseURL)/release?query=\(encoded)&fmt=json&limit=10"
    }

    /// Build a MusicBrainz lookup URL by recording ID.
    public static func buildRecordingLookupURL(
        recordingId: String
    ) -> String {
        return "\(MetadataSource.musicBrainz.baseURL)/recording/\(recordingId)?inc=artists+releases&fmt=json"
    }

    /// Required User-Agent header for MusicBrainz API.
    public static let userAgent = "MeedyaConverter/1.0 (https://github.com/MWBMPartners/MeedyaConverter)"
}

// MARK: - OpenSubtitlesClient

/// Builds OpenSubtitles API request URLs for subtitle search.
///
/// Phase 15.7
public struct OpenSubtitlesClient: Sendable {

    /// Build an OpenSubtitles search URL.
    public static func buildSearchURL(
        query: String? = nil,
        imdbId: String? = nil,
        language: String = "en",
        apiKey: String
    ) -> String {
        var url = "\(MetadataSource.openSubtitles.baseURL)/subtitles?"

        if let q = query {
            url += "query=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)&"
        }
        if let imdb = imdbId {
            url += "imdb_id=\(imdb)&"
        }
        url += "languages=\(language)"

        return url
    }

    /// Required headers for OpenSubtitles API.
    public static func buildHeaders(apiKey: String) -> [String: String] {
        return [
            "Api-Key": apiKey,
            "User-Agent": "MeedyaConverter v1.0",
            "Content-Type": "application/json",
        ]
    }
}

// MARK: - FilenameParser

/// Parses media filenames to extract metadata hints for lookup.
///
/// Handles common naming conventions like:
/// - "Movie Title (2024).mkv"
/// - "Show.Name.S03E07.720p.mkv"
/// - "Artist - Album - 01 Track.flac"
public struct FilenameParser: Sendable {

    /// Parse a filename to extract metadata hints.
    public static func parse(filename: String) -> MetadataSearchQuery {
        let name = (filename as NSString).deletingPathExtension

        // Try TV show pattern: S01E02 or 1x02
        if let tvMatch = parseTVShow(name) {
            return tvMatch
        }

        // Try movie pattern: Title (Year) or Title.Year
        if let movieMatch = parseMovie(name) {
            return movieMatch
        }

        // Try music pattern: Artist - Title or Artist - Album - Track
        if let musicMatch = parseMusic(name) {
            return musicMatch
        }

        // Fallback: use the filename as a movie title search
        let cleaned = name
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return MetadataSearchQuery(mediaType: .movie, title: cleaned)
    }

    private static func parseTVShow(_ name: String) -> MetadataSearchQuery? {
        // Match S01E02 pattern
        let pattern = "(.+?)[\\s._-]+[Ss](\\d{1,2})[Ee](\\d{1,3})"
        guard let regex = try? Regex(pattern),
              let match = name.firstMatch(of: regex) else {
            return nil
        }

        let title = String(match.output[1].substring ?? "")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let season = Int(match.output[2].substring ?? "")
        let episode = Int(match.output[3].substring ?? "")

        return MetadataSearchQuery(
            mediaType: .tvEpisode,
            title: title,
            season: season,
            episode: episode
        )
    }

    private static func parseMovie(_ name: String) -> MetadataSearchQuery? {
        // Match "Title (2024)" or "Title.2024"
        let pattern = "(.+?)[\\s._-]*[\\(]?((?:19|20)\\d{2})[\\)]?"
        guard let regex = try? Regex(pattern),
              let match = name.firstMatch(of: regex) else {
            return nil
        }

        let title = String(match.output[1].substring ?? "")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let year = Int(match.output[2].substring ?? "")

        // Filter out quality indicators mistaken for years
        if let y = year, y > 2030 || y < 1900 { return nil }

        return MetadataSearchQuery(
            mediaType: .movie,
            title: title,
            year: year
        )
    }

    private static func parseMusic(_ name: String) -> MetadataSearchQuery? {
        // Match "Artist - Title" or "Artist - Album - 01 Title"
        let parts = name.split(separator: "-").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        guard parts.count >= 2 else { return nil }

        let artist = parts[0]
        let title = parts.last ?? ""

        return MetadataSearchQuery(
            mediaType: .music,
            title: String(title),
            artist: artist
        )
    }
}
