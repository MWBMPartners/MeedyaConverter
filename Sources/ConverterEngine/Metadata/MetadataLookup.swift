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
/// Execution, throttling and JSON parsing live in `MusicBrainzLookupService`
/// (#205); this type remains a pure URL/request builder.
///
/// Phase 15.2
///
/// ## MusicBrainz "Search upgrades, Nov 30 2026" — verified unaffected
///
/// The Nov 30 2026 search-service upgrade (Solr 9 to 10; breaking tickets
/// SEARCH-444, SEARCH-642, SEARCH-666, SEARCH-752, SEARCH-764) was assessed
/// against every MusicBrainz request this client builds, re-verified on
/// 2026-09-01 against the announcement and all twelve linked tickets fetched
/// first-hand. None apply: we use only the `recording`/`release` search
/// entities (fields `recording`, `release`, `artist`) and the
/// `recording/<mbid>` and `discid` lookups. We never search
/// `area`/`url`/`cdstub`/`tag`, never use the `quality:` field, and parse no
/// relationship `target` property — in fact this type parses no response at
/// all. No migration is required (issue #493, Part B).
///
/// `MusicBrainzLookupService.parseRecordingSearch` decodes only recording /
/// artist-credit / release / release-group / media / track fields — no
/// relationships — so the SEARCH-752 `target` change still does not apply.
///
/// ### If `quality:` filtering is ever added — read this first
///
/// The working syntax **changes on 30 November 2026**, so which form is
/// correct depends on when your code runs:
///
///   - **Before the upgrade:** only NUMERIC values work
///     (`0`=low, `1`=normal, `2`=high, `-1`=unknown). `quality:low`,
///     `quality:normal` and `quality:high` all return nothing — SEARCH-666
///     records this as the bug being fixed, not as intended behaviour.
///   - **From the upgrade onwards:** SEARCH-666 makes the NAMES the working
///     form. Do not hard-code the numeric IDs against the new server.
///
/// ### New capability the upgrade brings (SEARCH-681)
///
/// The upgrade adds "Genre" as a *search target type*. It deliberately does
/// **not** add genre as a search *field* — you still cannot search a
/// recording by genre MBID. Searching by genre NAME already works today via
/// the `tag` field, so any genre-filtering feature should use `tag:` and
/// needs no upgrade to function.
///
/// ## Lucene query hardening (issue #493, Part A)
///
/// MusicBrainz's `/recording` and `/release` search endpoints parse the
/// `query` parameter as a Lucene query string
/// (https://musicbrainz.org/doc/MusicBrainz_API/Search,
/// https://lucene.apache.org/core/.../QueryParserSyntax.html). Building
/// that string by raw interpolation is unsafe on two independent axes:
///
///   1. **Lucene syntax** — a bare, unquoted multi-word value only binds
///      its first token to the field (`recording:Bohemian Rhapsody`
///      parses as `recording:Bohemian` AND an unfielded `Rhapsody`
///      clause), and characters such as `: ( ) [ ] { } ~ * ? ^ " \` are
///      Lucene operators when they appear outside of a quoted phrase.
///   2. **URL syntax** — characters such as `& + = ? # / ; : @ $ ,` are
///      significant in a URL's query-string encoding (`&` separates
///      parameters, `+` decodes to a space, etc.), so passing them
///      through unescaped can corrupt the request even before Lucene
///      ever sees it.
///
/// `luceneClause(field:value:)` and `safeQueryValueCharacters` address
/// each axis independently: the former produces a phrase-quoted,
/// Lucene-escaped clause; the latter percent-encodes that clause so it
/// survives transport as a single query-string value. Percent-encoding
/// is fully transparent to MusicBrainz — the server percent-decodes the
/// query string before handing it to the Lucene parser — so it is
/// always safe to encode a character even when Lucene would have
/// accepted it literally (e.g. the `:` in `field:"value"`).
public struct MusicBrainzClient: Sendable {

    // MARK: - Lucene Query Escaping

    /// Escape a raw string for safe embedding inside a double-quoted
    /// Lucene phrase.
    ///
    /// Per Lucene's escaping rules, a backslash-escape sequence is
    /// introduced with `\`, so any literal backslash in the value must
    /// be escaped to `\\` *before* the phrase-terminating `"` character
    /// is escaped to `\"` — doing it in the other order would
    /// re-escape the backslashes just inserted for the quote, corrupting
    /// the value. Once quoted, Lucene treats every other special
    /// character (`: ( ) [ ] { } ~ * ? ^` and friends) as a literal
    /// part of the phrase rather than an operator, so no further
    /// escaping is required.
    ///
    /// - Parameter value: The raw, unescaped field value (e.g. a track
    ///   title or artist name) as supplied by the caller.
    /// - Returns: `value` with `\` and `"` backslash-escaped, ready to
    ///   be wrapped in double quotes by `luceneClause(field:value:)`.
    private static func escapeLucenePhraseValue(_ value: String) -> String {
        // Order matters — see the doc comment above.
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }

    /// Build a single, safely phrase-quoted Lucene field clause of the
    /// form `field:"<escaped value>"`.
    ///
    /// Wrapping `value` in double quotes turns the whole value into one
    /// Lucene "phrase" term. This both keeps multi-word values attached
    /// to `field` (rather than the trailing words leaking into an
    /// unfielded default clause) and neutralises Lucene's special
    /// characters within the value, since they only carry syntactic
    /// meaning *outside* of a quoted phrase.
    ///
    /// `field` is assumed to be a literal, developer-controlled constant
    /// (`"recording"`, `"release"`, `"artist"`) and is emitted verbatim,
    /// unquoted and unescaped, exactly as MusicBrainz's field-search
    /// syntax requires. Only `value` — which may originate from
    /// arbitrary file- or user-derived input — is escaped and quoted.
    ///
    /// - Parameters:
    ///   - field: The Lucene/MusicBrainz field name, e.g. `"recording"`.
    ///   - value: The raw value to search for within that field.
    /// - Returns: A Lucene clause, e.g. `recording:"Bohemian Rhapsody"`.
    private static func luceneClause(field: String, value: String) -> String {
        "\(field):\"\(escapeLucenePhraseValue(value))\""
    }

    // MARK: - Percent-Encoding

    /// Characters considered safe to leave un-encoded when embedding an
    /// assembled Lucene query string as the value of a URL query
    /// parameter.
    ///
    /// `CharacterSet.urlQueryAllowed` is too permissive for this
    /// specific use: it treats `& + = ? # / ; : @ $ ,` as "safe" because
    /// those characters are legal *somewhere* in a URL query component
    /// in general, but several of them are reserved for our own use of
    /// the query string and must not appear un-encoded inside the
    /// `query=` value itself:
    ///   - `&` separates the `query=`, `fmt=`, and `limit=` parameters —
    ///     an un-encoded `&` inside a title/artist would prematurely end
    ///     the `query` value and inject bogus parameters into the URL.
    ///   - `+` decodes to a literal space in query-string encoding,
    ///     which would corrupt word boundaries in the value.
    ///   - `= ? # ; : @ $ ,` are either parameter/fragment delimiters or
    ///     characters best kept encoded to avoid any ambiguity with the
    ///     surrounding URL structure.
    /// We also explicitly exclude the space character, which
    /// `.urlQueryAllowed` already disallows, but calling it out keeps
    /// this set self-documenting.
    ///
    /// We start from the standard "allowed in a URL query" set and
    /// *remove* the characters known to be unsafe for this specific
    /// usage, rather than enumerating an "allowed" set from scratch —
    /// this avoids accidentally permitting something Foundation already
    /// excludes (such as `%` itself).
    private static let safeQueryValueCharacters: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#/;:@$, ")
        return set
    }()

    /// Percent-encode an assembled Lucene query string for safe use as
    /// the value of a URL query parameter.
    ///
    /// See `safeQueryValueCharacters` for the rationale behind the
    /// specific character set used here instead of `.urlQueryAllowed`.
    ///
    /// - Parameter query: The raw (unencoded) Lucene query string, e.g.
    ///   `recording:"Bohemian Rhapsody" AND artist:"Queen"`.
    /// - Returns: The percent-encoded query, safe to interpolate as a
    ///   single `query=` parameter value.
    private static func percentEncodeQueryValue(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: safeQueryValueCharacters) ?? query
    }

    // MARK: - URL Builders

    /// Build a MusicBrainz recording search URL.
    ///
    /// The `title` (and, if present, `artist`) are each wrapped as a
    /// phrase-quoted, Lucene-escaped field clause via `luceneClause`
    /// before the whole query is percent-encoded — see the type-level
    /// doc comment for why both steps are necessary.
    public static func buildRecordingSearchURL(
        title: String,
        artist: String? = nil
    ) -> String {
        var query = luceneClause(field: "recording", value: title)
        if let art = artist {
            query += " AND \(luceneClause(field: "artist", value: art))"
        }
        let encoded = percentEncodeQueryValue(query)
        return "\(MetadataSource.musicBrainz.baseURL)/recording?query=\(encoded)&fmt=json&limit=10"
    }

    /// Build a MusicBrainz release (album) search URL.
    ///
    /// See `buildRecordingSearchURL(title:artist:)` — the same
    /// phrase-quoting and percent-encoding treatment applies here.
    public static func buildReleaseSearchURL(
        album: String,
        artist: String? = nil
    ) -> String {
        var query = luceneClause(field: "release", value: album)
        if let art = artist {
            query += " AND \(luceneClause(field: "artist", value: art))"
        }
        let encoded = percentEncodeQueryValue(query)
        return "\(MetadataSource.musicBrainz.baseURL)/release?query=\(encoded)&fmt=json&limit=10"
    }

    /// Build a MusicBrainz lookup URL by recording ID.
    ///
    /// `recordingId` is a MusicBrainz Identifier (MBID) — a UUID — so it
    /// contains no characters that require Lucene escaping or
    /// percent-encoding, unlike the free-text search builders above.
    public static func buildRecordingLookupURL(
        recordingId: String
    ) -> String {
        return "\(MetadataSource.musicBrainz.baseURL)/recording/\(recordingId)?inc=artists+releases&fmt=json"
    }

    /// Required User-Agent header for MusicBrainz API.
    public static let userAgent = "MeedyaConverter/1.0 (https://github.com/MWBMPartners/MeedyaConverter)"

    /// Per-request timeout for MusicBrainz calls (seconds).
    public static let requestTimeoutSeconds: TimeInterval = 15

    /// The ready-to-send request for a recording search: the URL from
    /// `buildRecordingSearchURL(title:artist:)` plus the two headers MusicBrainz
    /// requires — `User-Agent` (`userAgent`; see
    /// https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting) and
    /// `Accept: application/json` — and `requestTimeoutSeconds`.
    /// Returns `nil` only if Foundation rejects the assembled string as a URL,
    /// which is not expected: every user-controlled character is percent-encoded.
    /// Called by `MusicBrainzLookupService.searchRecordings(title:artist:)`.
    public static func buildRecordingSearchRequest(title: String, artist: String?) -> URLRequest? {
        guard let url = URL(string: buildRecordingSearchURL(title: title, artist: artist)) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeoutSeconds
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
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
