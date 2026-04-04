// ============================================================================
// MeedyaConverter — MetadataProviders
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - TheTVDBClient

/// Builds TheTVDB API v4 request URLs for TV show metadata lookup.
///
/// TheTVDB uses bearer token authentication obtained via API key.
///
/// Phase 14.5
public struct TheTVDBClient: Sendable {

    /// TheTVDB API v4 base URL.
    public static let baseURL = "https://api4.thetvdb.com/v4"

    /// Build a login request body.
    ///
    /// - Parameter apiKey: TheTVDB API key.
    /// - Returns: JSON body string.
    public static func buildLoginBody(apiKey: String) -> String {
        return "{\"apikey\":\"\(apiKey)\"}"
    }

    /// Build login URL.
    ///
    /// - Returns: Login endpoint URL.
    public static func buildLoginURL() -> String {
        return "\(baseURL)/login"
    }

    /// Build HTTP headers with bearer token.
    ///
    /// - Parameter bearerToken: Authentication token from login.
    /// - Returns: Header dictionary.
    public static func buildHeaders(bearerToken: String) -> [String: String] {
        return [
            "Authorization": "Bearer \(bearerToken)",
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
    }

    /// Build a TV series search URL.
    ///
    /// - Parameters:
    ///   - query: Search query.
    ///   - year: Filter by year (optional).
    /// - Returns: Search URL.
    public static func buildSearchURL(
        query: String,
        year: Int? = nil
    ) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var url = "\(baseURL)/search?query=\(encoded)&type=series"
        if let y = year { url += "&year=\(y)" }
        return url
    }

    /// Build a series details URL.
    ///
    /// - Parameter seriesId: TheTVDB series ID.
    /// - Returns: Series details URL with extended info.
    public static func buildSeriesURL(seriesId: Int) -> String {
        return "\(baseURL)/series/\(seriesId)/extended"
    }

    /// Build a season episodes URL.
    ///
    /// - Parameters:
    ///   - seriesId: TheTVDB series ID.
    ///   - seasonNumber: Season number.
    /// - Returns: Episodes URL.
    public static func buildEpisodesURL(
        seriesId: Int,
        seasonNumber: Int
    ) -> String {
        return "\(baseURL)/series/\(seriesId)/episodes/default?season=\(seasonNumber)"
    }

    /// Build an episode details URL.
    ///
    /// - Parameter episodeId: TheTVDB episode ID.
    /// - Returns: Episode details URL.
    public static func buildEpisodeURL(episodeId: Int) -> String {
        return "\(baseURL)/episodes/\(episodeId)/extended"
    }

    /// Build series artwork URL.
    ///
    /// - Parameter seriesId: TheTVDB series ID.
    /// - Returns: Artwork list URL.
    public static func buildArtworkURL(seriesId: Int) -> String {
        return "\(baseURL)/series/\(seriesId)/artworks"
    }
}

// MARK: - OMDbClient

/// Builds OMDb (Open Movie Database) API request URLs.
///
/// OMDb provides IMDB data through a free/paid API proxy.
///
/// Phase 14.6
public struct OMDbClient: Sendable {

    /// OMDb API base URL.
    public static let baseURL = "https://www.omdbapi.com"

    /// Build a search URL by title.
    ///
    /// - Parameters:
    ///   - title: Movie/show title.
    ///   - year: Year of release (optional).
    ///   - type: Media type ("movie", "series", "episode").
    ///   - apiKey: OMDb API key.
    /// - Returns: Search URL.
    public static func buildSearchURL(
        title: String,
        year: Int? = nil,
        type: String? = nil,
        apiKey: String
    ) -> String {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        var url = "\(baseURL)/?s=\(encoded)&apikey=\(apiKey)"
        if let y = year { url += "&y=\(y)" }
        if let t = type { url += "&type=\(t)" }
        return url
    }

    /// Build a detail lookup URL by title.
    ///
    /// - Parameters:
    ///   - title: Exact movie/show title.
    ///   - year: Year of release (optional).
    ///   - plot: Plot length ("short" or "full").
    ///   - apiKey: OMDb API key.
    /// - Returns: Detail URL.
    public static func buildTitleLookupURL(
        title: String,
        year: Int? = nil,
        plot: String = "full",
        apiKey: String
    ) -> String {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        var url = "\(baseURL)/?t=\(encoded)&plot=\(plot)&apikey=\(apiKey)"
        if let y = year { url += "&y=\(y)" }
        return url
    }

    /// Build a detail lookup URL by IMDB ID.
    ///
    /// - Parameters:
    ///   - imdbId: IMDB identifier (e.g., "tt1234567").
    ///   - plot: Plot length ("short" or "full").
    ///   - apiKey: OMDb API key.
    /// - Returns: Detail URL.
    public static func buildIMDBLookupURL(
        imdbId: String,
        plot: String = "full",
        apiKey: String
    ) -> String {
        return "\(baseURL)/?i=\(imdbId)&plot=\(plot)&apikey=\(apiKey)"
    }

    /// Build a season detail URL.
    ///
    /// - Parameters:
    ///   - imdbId: IMDB ID of the series.
    ///   - season: Season number.
    ///   - apiKey: OMDb API key.
    /// - Returns: Season detail URL.
    public static func buildSeasonURL(
        imdbId: String,
        season: Int,
        apiKey: String
    ) -> String {
        return "\(baseURL)/?i=\(imdbId)&Season=\(season)&apikey=\(apiKey)"
    }
}

// MARK: - DiscogsClient

/// Builds Discogs API request URLs for physical media / vinyl metadata.
///
/// Phase 14.8
public struct DiscogsClient: Sendable {

    /// Discogs API base URL.
    public static let baseURL = "https://api.discogs.com"

    /// Build HTTP headers for Discogs API.
    ///
    /// - Parameter personalAccessToken: Discogs personal access token.
    /// - Returns: Header dictionary.
    public static func buildHeaders(personalAccessToken: String) -> [String: String] {
        return [
            "Authorization": "Discogs token=\(personalAccessToken)",
            "User-Agent": "MeedyaConverter/1.0",
        ]
    }

    /// Build a release search URL.
    ///
    /// - Parameters:
    ///   - query: Search query.
    ///   - type: Search type ("release", "master", "artist", "label").
    ///   - perPage: Results per page.
    /// - Returns: Search URL.
    public static func buildSearchURL(
        query: String,
        type: String = "release",
        perPage: Int = 10
    ) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return "\(baseURL)/database/search?q=\(encoded)&type=\(type)&per_page=\(perPage)"
    }

    /// Build a release details URL.
    ///
    /// - Parameter releaseId: Discogs release ID.
    /// - Returns: Release details URL.
    public static func buildReleaseURL(releaseId: Int) -> String {
        return "\(baseURL)/releases/\(releaseId)"
    }

    /// Build a master release URL.
    ///
    /// - Parameter masterId: Discogs master release ID.
    /// - Returns: Master release URL.
    public static func buildMasterURL(masterId: Int) -> String {
        return "\(baseURL)/masters/\(masterId)"
    }

    /// Build an artist details URL.
    ///
    /// - Parameter artistId: Discogs artist ID.
    /// - Returns: Artist details URL.
    public static func buildArtistURL(artistId: Int) -> String {
        return "\(baseURL)/artists/\(artistId)"
    }

    /// Build a label details URL.
    ///
    /// - Parameter labelId: Discogs label ID.
    /// - Returns: Label details URL.
    public static func buildLabelURL(labelId: Int) -> String {
        return "\(baseURL)/labels/\(labelId)"
    }

    /// Build a barcode/catalog number search URL.
    ///
    /// - Parameter barcode: UPC/EAN barcode.
    /// - Returns: Search URL filtered by barcode.
    public static func buildBarcodeSearchURL(barcode: String) -> String {
        return "\(baseURL)/database/search?barcode=\(barcode)&type=release"
    }
}

// MARK: - FanArtTVClient

/// Builds FanArt.tv API request URLs for high-quality artwork.
///
/// Phase 14.9
public struct FanArtTVClient: Sendable {

    /// FanArt.tv API base URL.
    public static let baseURL = "https://webservice.fanart.tv/v3"

    /// Build a movie artwork URL.
    ///
    /// - Parameters:
    ///   - tmdbId: TMDB movie ID.
    ///   - apiKey: FanArt.tv API key.
    /// - Returns: Movie artwork URL.
    public static func buildMovieArtworkURL(
        tmdbId: Int,
        apiKey: String
    ) -> String {
        return "\(baseURL)/movies/\(tmdbId)?api_key=\(apiKey)"
    }

    /// Build a TV show artwork URL.
    ///
    /// - Parameters:
    ///   - tvdbId: TheTVDB series ID.
    ///   - apiKey: FanArt.tv API key.
    /// - Returns: TV artwork URL.
    public static func buildTVArtworkURL(
        tvdbId: Int,
        apiKey: String
    ) -> String {
        return "\(baseURL)/tv/\(tvdbId)?api_key=\(apiKey)"
    }

    /// Build a music artist artwork URL.
    ///
    /// - Parameters:
    ///   - musicBrainzId: MusicBrainz artist ID.
    ///   - apiKey: FanArt.tv API key.
    /// - Returns: Music artwork URL.
    public static func buildMusicArtworkURL(
        musicBrainzId: String,
        apiKey: String
    ) -> String {
        return "\(baseURL)/music/\(musicBrainzId)?api_key=\(apiKey)"
    }

    /// Build a music album artwork URL.
    ///
    /// - Parameters:
    ///   - musicBrainzAlbumId: MusicBrainz release group ID.
    ///   - apiKey: FanArt.tv API key.
    /// - Returns: Album artwork URL.
    public static func buildAlbumArtworkURL(
        musicBrainzAlbumId: String,
        apiKey: String
    ) -> String {
        return "\(baseURL)/music/albums/\(musicBrainzAlbumId)?api_key=\(apiKey)"
    }

    /// Available artwork types for movies.
    public static let movieArtworkTypes = [
        "hdmovielogo", "movieposter", "moviethumb", "moviebackground",
        "hdmovieclearart", "movieart", "moviedisc", "moviebanner",
    ]

    /// Available artwork types for TV shows.
    public static let tvArtworkTypes = [
        "hdtvlogo", "tvposter", "tvthumb", "showbackground",
        "hdclearart", "tvbanner", "characterart", "seasonposter",
    ]
}

// MARK: - AcoustIDClient

/// Builds AcoustID / Chromaprint API request URLs for audio fingerprint identification.
///
/// AcoustID uses audio fingerprints generated by Chromaprint (fpcalc)
/// to identify music recordings and link them to MusicBrainz.
///
/// Phase 14.3
public struct AcoustIDClient: Sendable {

    /// AcoustID API base URL.
    public static let baseURL = "https://api.acoustid.org/v2"

    /// Build a lookup URL for an audio fingerprint.
    ///
    /// - Parameters:
    ///   - fingerprint: Chromaprint fingerprint string.
    ///   - duration: Audio duration in seconds.
    ///   - apiKey: AcoustID application API key.
    /// - Returns: Lookup URL.
    public static func buildLookupURL(
        fingerprint: String,
        duration: Int,
        apiKey: String
    ) -> String {
        let meta = "recordings+releasegroups+compress"
        return "\(baseURL)/lookup?client=\(apiKey)&duration=\(duration)&fingerprint=\(fingerprint)&meta=\(meta)"
    }

    /// Build fpcalc (Chromaprint) command-line arguments for fingerprint generation.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the audio file.
    ///   - maxDuration: Maximum duration to analyze in seconds (default 120).
    /// - Returns: Argument array for fpcalc binary.
    public static func buildFpcalcArguments(
        inputPath: String,
        maxDuration: Int = 120
    ) -> [String] {
        return ["-json", "-length", "\(maxDuration)", inputPath]
    }

    /// Build FFmpeg arguments for generating a Chromaprint fingerprint.
    ///
    /// Uses FFmpeg's built-in chromaprint muxer as an alternative to fpcalc.
    ///
    /// - Parameters:
    ///   - inputPath: Source audio file.
    ///   - maxDuration: Maximum duration to analyze in seconds.
    /// - Returns: FFmpeg argument array.
    public static func buildFFmpegFingerprintArguments(
        inputPath: String,
        maxDuration: Int = 120
    ) -> [String] {
        return [
            "-i", inputPath,
            "-t", "\(maxDuration)",
            "-ac", "1",
            "-ar", "11025",
            "-f", "chromaprint",
            "-fp_format", "raw",
            "-",
        ]
    }

    /// fpcalc binary name.
    public static let fpcalcBinaryName = "fpcalc"

    /// Default API key placeholder (users must register their own).
    public static let registrationURL = "https://acoustid.org/new-application"
}

// MARK: - MeedyaDBClient

/// Builds MeedyaDB API request URLs for the app's own metadata service.
///
/// MeedyaDB aggregates metadata from multiple sources and provides
/// unified search with pre-matched results for common media.
///
/// Phase 14.7
public struct MeedyaDBClient: Sendable {

    /// MeedyaDB API base URL.
    public static let baseURL = "https://api.meedya.tv/v1"

    /// Build a unified search URL.
    ///
    /// - Parameters:
    ///   - query: Search query.
    ///   - mediaType: Media type filter ("movie", "tv", "music").
    ///   - limit: Maximum results.
    /// - Returns: Search URL.
    public static func buildSearchURL(
        query: String,
        mediaType: String? = nil,
        limit: Int = 20
    ) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var url = "\(baseURL)/search?q=\(encoded)&limit=\(limit)"
        if let type = mediaType { url += "&type=\(type)" }
        return url
    }

    /// Build a media details URL.
    ///
    /// - Parameter mediaId: MeedyaDB media ID.
    /// - Returns: Media details URL.
    public static func buildDetailsURL(mediaId: String) -> String {
        return "\(baseURL)/media/\(mediaId)"
    }

    /// Build a match-by-filename URL.
    ///
    /// - Parameter filename: The media filename to match.
    /// - Returns: Match URL.
    public static func buildMatchURL(filename: String) -> String {
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
        return "\(baseURL)/match?filename=\(encoded)"
    }

    /// Build HTTP headers for MeedyaDB API.
    ///
    /// - Parameter apiKey: MeedyaDB API key.
    /// - Returns: Header dictionary.
    public static func buildHeaders(apiKey: String) -> [String: String] {
        return [
            "X-API-Key": apiKey,
            "User-Agent": "MeedyaConverter/1.0",
            "Accept": "application/json",
        ]
    }
}

// MARK: - MediaServerTagging

/// Builds metadata tags compatible with popular media server conventions.
///
/// Supports Plex, Jellyfin, Emby, and Kodi naming and NFO conventions.
///
/// Phase 14.13
public struct MediaServerTagging: Sendable {

    /// Media server types for tagging compatibility.
    public enum MediaServer: String, Codable, Sendable, CaseIterable {
        case plex
        case jellyfin
        case emby
        case kodi

        /// Display name.
        public var displayName: String {
            switch self {
            case .plex: return "Plex"
            case .jellyfin: return "Jellyfin"
            case .emby: return "Emby"
            case .kodi: return "Kodi"
            }
        }
    }

    /// Build a Plex-compatible filename for a movie.
    ///
    /// - Parameters:
    ///   - title: Movie title.
    ///   - year: Release year.
    ///   - extension_: File extension (without dot).
    /// - Returns: Plex-compatible filename.
    public static func buildPlexMovieFilename(
        title: String,
        year: Int,
        extension_: String
    ) -> String {
        return "\(title) (\(year)).\(extension_)"
    }

    /// Build a Plex-compatible filename for a TV episode.
    ///
    /// - Parameters:
    ///   - showTitle: Show name.
    ///   - season: Season number.
    ///   - episode: Episode number.
    ///   - episodeTitle: Episode title (optional).
    ///   - extension_: File extension (without dot).
    /// - Returns: Plex-compatible filename.
    public static func buildPlexEpisodeFilename(
        showTitle: String,
        season: Int,
        episode: Int,
        episodeTitle: String? = nil,
        extension_: String
    ) -> String {
        let sePart = String(format: "S%02dE%02d", season, episode)
        if let epTitle = episodeTitle {
            return "\(showTitle) - \(sePart) - \(epTitle).\(extension_)"
        }
        return "\(showTitle) - \(sePart).\(extension_)"
    }

    /// Build a Kodi NFO XML for a movie.
    ///
    /// - Parameter result: Metadata result to format.
    /// - Returns: Kodi-compatible NFO XML string.
    public static func buildKodiMovieNFO(result: MetadataResult) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<movie>\n"
        xml += "  <title>\(escapeXML(result.title))</title>\n"
        if let orig = result.originalTitle {
            xml += "  <originaltitle>\(escapeXML(orig))</originaltitle>\n"
        }
        if let year = result.year {
            xml += "  <year>\(year)</year>\n"
        }
        if let overview = result.overview {
            xml += "  <plot>\(escapeXML(overview))</plot>\n"
        }
        if let rating = result.rating {
            xml += "  <mpaa>\(escapeXML(rating))</mpaa>\n"
        }
        if let score = result.score {
            xml += "  <rating>\(score)</rating>\n"
        }
        if let runtime = result.runtimeMinutes {
            xml += "  <runtime>\(runtime)</runtime>\n"
        }
        for genre in result.genres {
            xml += "  <genre>\(escapeXML(genre))</genre>\n"
        }
        for director in result.directors {
            xml += "  <director>\(escapeXML(director))</director>\n"
        }
        for actor in result.cast {
            xml += "  <actor>\n    <name>\(escapeXML(actor))</name>\n  </actor>\n"
        }
        if result.source == .tmdb {
            xml += "  <uniqueid type=\"tmdb\">\(result.externalId)</uniqueid>\n"
        }
        if result.source == .omdb {
            xml += "  <uniqueid type=\"imdb\">\(result.externalId)</uniqueid>\n"
        }
        if let poster = result.posterURL {
            xml += "  <thumb>\(escapeXML(poster))</thumb>\n"
        }
        if let backdrop = result.backdropURL {
            xml += "  <fanart>\n    <thumb>\(escapeXML(backdrop))</thumb>\n  </fanart>\n"
        }
        xml += "</movie>\n"
        return xml
    }

    /// Build a Kodi NFO XML for a TV episode.
    ///
    /// - Parameter result: Metadata result to format.
    /// - Returns: Kodi-compatible episode NFO XML string.
    public static func buildKodiEpisodeNFO(result: MetadataResult) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<episodedetails>\n"
        xml += "  <title>\(escapeXML(result.title))</title>\n"
        if let season = result.season {
            xml += "  <season>\(season)</season>\n"
        }
        if let episode = result.episode {
            xml += "  <episode>\(episode)</episode>\n"
        }
        if let overview = result.overview {
            xml += "  <plot>\(escapeXML(overview))</plot>\n"
        }
        if let date = result.releaseDate {
            xml += "  <aired>\(escapeXML(date))</aired>\n"
        }
        if let score = result.score {
            xml += "  <rating>\(score)</rating>\n"
        }
        for director in result.directors {
            xml += "  <director>\(escapeXML(director))</director>\n"
        }
        xml += "</episodedetails>\n"
        return xml
    }

    /// Build FFmpeg metadata arguments from a MetadataResult.
    ///
    /// Embeds metadata directly into the output file's container metadata.
    ///
    /// - Parameter result: Metadata result.
    /// - Returns: FFmpeg argument array for metadata embedding.
    public static func buildFFmpegMetadataArguments(result: MetadataResult) -> [String] {
        var args: [String] = []

        args += ["-metadata", "title=\(result.title)"]

        if let year = result.year {
            args += ["-metadata", "year=\(year)"]
            args += ["-metadata", "date=\(year)"]
        }

        if let overview = result.overview {
            args += ["-metadata", "description=\(overview)"]
            args += ["-metadata", "synopsis=\(overview)"]
        }

        if !result.genres.isEmpty {
            args += ["-metadata", "genre=\(result.genres.joined(separator: "; "))"]
        }

        if let artist = result.artist {
            args += ["-metadata", "artist=\(artist)"]
        }

        if let album = result.album {
            args += ["-metadata", "album=\(album)"]
        }

        if let track = result.trackNumber {
            args += ["-metadata", "track=\(track)"]
        }

        if !result.directors.isEmpty {
            args += ["-metadata", "director=\(result.directors.joined(separator: "; "))"]
        }

        if let rating = result.rating {
            args += ["-metadata", "rating=\(rating)"]
        }

        return args
    }

    /// Escape special XML characters.
    private static func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
