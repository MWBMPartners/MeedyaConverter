// ============================================================================
// MeedyaConverter — ConverterEngine unit tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Split from ConverterEngineTests.swift (re #452) to keep the test file
// under a manageable size. This file extends `ConverterEngineTests`
// (declared in ConverterEngineTests.swift) with a cohesive group of test
// methods. No test body, name, or assertion was changed during the split.
// ============================================================================

import XCTest
import ConverterEngine

extension ConverterEngineTests {
    // MARK: - Phase 14: Metadata Providers Tests

    // MARK: TheTVDB

    /// Verifies TheTVDB login URL and body.
    func test_theTVDBClient_login() {
        let url = TheTVDBClient.buildLoginURL()
        XCTAssertTrue(url.contains("api4.thetvdb.com/v4/login"))

        let body = TheTVDBClient.buildLoginBody(apiKey: "my_api_key")
        XCTAssertTrue(body.contains("\"apikey\":\"my_api_key\""))
    }

    /// Verifies TheTVDB search URL.
    func test_theTVDBClient_searchURL() {
        let url = TheTVDBClient.buildSearchURL(query: "Breaking Bad", year: 2008)
        XCTAssertTrue(url.contains("search?query=Breaking"))
        XCTAssertTrue(url.contains("type=series"))
        XCTAssertTrue(url.contains("year=2008"))
    }

    /// Verifies TheTVDB series details URL.
    func test_theTVDBClient_seriesURL() {
        let url = TheTVDBClient.buildSeriesURL(seriesId: 81189)
        XCTAssertTrue(url.contains("series/81189/extended"))
    }

    /// Verifies TheTVDB episodes URL.
    func test_theTVDBClient_episodesURL() {
        let url = TheTVDBClient.buildEpisodesURL(seriesId: 81189, seasonNumber: 3)
        XCTAssertTrue(url.contains("series/81189/episodes"))
        XCTAssertTrue(url.contains("season=3"))
    }

    /// Verifies TheTVDB headers.
    func test_theTVDBClient_headers() {
        let headers = TheTVDBClient.buildHeaders(bearerToken: "jwt_token")
        XCTAssertEqual(headers["Authorization"], "Bearer jwt_token")
        XCTAssertEqual(headers["Accept"], "application/json")
    }

    // MARK: OMDb

    /// Verifies OMDb search URL.
    func test_omdbClient_searchURL() {
        let url = OMDbClient.buildSearchURL(
            title: "Inception",
            year: 2010,
            type: "movie",
            apiKey: "abc123"
        )
        XCTAssertTrue(url.contains("s=Inception"))
        XCTAssertTrue(url.contains("y=2010"))
        XCTAssertTrue(url.contains("type=movie"))
        XCTAssertTrue(url.contains("apikey=abc123"))
    }

    /// Verifies OMDb IMDB lookup URL.
    func test_omdbClient_imdbLookupURL() {
        let url = OMDbClient.buildIMDBLookupURL(
            imdbId: "tt1375666",
            apiKey: "abc123"
        )
        XCTAssertTrue(url.contains("i=tt1375666"))
        XCTAssertTrue(url.contains("plot=full"))
    }

    /// Verifies OMDb season URL.
    func test_omdbClient_seasonURL() {
        let url = OMDbClient.buildSeasonURL(
            imdbId: "tt0903747",
            season: 5,
            apiKey: "key"
        )
        XCTAssertTrue(url.contains("i=tt0903747"))
        XCTAssertTrue(url.contains("Season=5"))
    }

    // MARK: Discogs

    /// Verifies Discogs headers.
    func test_discogsClient_headers() {
        let headers = DiscogsClient.buildHeaders(personalAccessToken: "my_token")
        XCTAssertEqual(headers["Authorization"], "Discogs token=my_token")
        XCTAssertEqual(headers["User-Agent"], "MeedyaConverter/1.0")
    }

    /// Verifies Discogs search URL.
    func test_discogsClient_searchURL() {
        let url = DiscogsClient.buildSearchURL(query: "Dark Side of the Moon", type: "master")
        XCTAssertTrue(url.contains("database/search"))
        XCTAssertTrue(url.contains("type=master"))
    }

    /// Verifies Discogs release URL.
    func test_discogsClient_releaseURL() {
        let url = DiscogsClient.buildReleaseURL(releaseId: 249504)
        XCTAssertEqual(url, "https://api.discogs.com/releases/249504")
    }

    /// Verifies Discogs barcode search.
    func test_discogsClient_barcodeSearch() {
        let url = DiscogsClient.buildBarcodeSearchURL(barcode: "0724349691704")
        XCTAssertTrue(url.contains("barcode=0724349691704"))
        XCTAssertTrue(url.contains("type=release"))
    }

    // MARK: FanArt.tv

    /// Verifies FanArt.tv movie artwork URL.
    func test_fanArtTVClient_movieArtworkURL() {
        let url = FanArtTVClient.buildMovieArtworkURL(tmdbId: 27205, apiKey: "fa_key")
        XCTAssertTrue(url.contains("movies/27205"))
        XCTAssertTrue(url.contains("api_key=fa_key"))
    }

    /// Verifies FanArt.tv TV artwork URL.
    func test_fanArtTVClient_tvArtworkURL() {
        let url = FanArtTVClient.buildTVArtworkURL(tvdbId: 81189, apiKey: "fa_key")
        XCTAssertTrue(url.contains("tv/81189"))
    }

    /// Verifies FanArt.tv music artwork URL.
    func test_fanArtTVClient_musicArtworkURL() {
        let url = FanArtTVClient.buildMusicArtworkURL(
            musicBrainzId: "65f4f0c5-ef9e-490c-aee3-909e7ae6b2ab",
            apiKey: "fa_key"
        )
        XCTAssertTrue(url.contains("music/65f4f0c5"))
    }

    /// Verifies FanArt.tv artwork types.
    func test_fanArtTVClient_artworkTypes() {
        XCTAssertTrue(FanArtTVClient.movieArtworkTypes.contains("movieposter"))
        XCTAssertTrue(FanArtTVClient.tvArtworkTypes.contains("tvposter"))
    }

    // MARK: AcoustID

    /// Verifies AcoustID lookup URL.
    func test_acoustIDClient_lookupURL() {
        let url = AcoustIDClient.buildLookupURL(
            fingerprint: "AQADtF...fingerprint",
            duration: 240,
            apiKey: "acoust_key"
        )
        XCTAssertTrue(url.contains("api.acoustid.org/v2/lookup"))
        XCTAssertTrue(url.contains("duration=240"))
        XCTAssertTrue(url.contains("client=acoust_key"))
        XCTAssertTrue(url.contains("meta=recordings"))
    }

    /// Verifies fpcalc arguments.
    func test_acoustIDClient_fpcalcArguments() {
        let args = AcoustIDClient.buildFpcalcArguments(inputPath: "/tmp/song.flac", maxDuration: 60)
        XCTAssertTrue(args.contains("-json"))
        XCTAssertTrue(args.contains("-length"))
        XCTAssertTrue(args.contains("60"))
        XCTAssertTrue(args.contains("/tmp/song.flac"))
    }

    /// Verifies FFmpeg fingerprint arguments.
    func test_acoustIDClient_ffmpegFingerprint() {
        let args = AcoustIDClient.buildFFmpegFingerprintArguments(inputPath: "/tmp/song.mp3")
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("chromaprint"))
        XCTAssertTrue(args.contains("-ac"))
        XCTAssertTrue(args.contains("1"))
    }

    // MARK: MeedyaDB

    /// Verifies MeedyaDB search URL.
    func test_meedyaDBClient_searchURL() {
        let url = MeedyaDBClient.buildSearchURL(query: "Inception", mediaType: "movie")
        XCTAssertTrue(url.contains("api.meedya.tv/v1/search"))
        XCTAssertTrue(url.contains("type=movie"))
    }

    /// Verifies MeedyaDB match URL.
    func test_meedyaDBClient_matchURL() {
        let url = MeedyaDBClient.buildMatchURL(filename: "Inception.2010.1080p.BluRay.mkv")
        XCTAssertTrue(url.contains("match?filename="))
    }

    /// Verifies MeedyaDB headers.
    func test_meedyaDBClient_headers() {
        let headers = MeedyaDBClient.buildHeaders(apiKey: "mdb_key")
        XCTAssertEqual(headers["X-API-Key"], "mdb_key")
    }

    // MARK: MediaServerTagging

    /// Verifies Plex movie filename generation.
    func test_mediaServerTagging_plexMovieFilename() {
        let name = MediaServerTagging.buildPlexMovieFilename(
            title: "Inception",
            year: 2010,
            extension_: "mkv"
        )
        XCTAssertEqual(name, "Inception (2010).mkv")
    }

    /// Verifies Plex episode filename generation.
    func test_mediaServerTagging_plexEpisodeFilename() {
        let name = MediaServerTagging.buildPlexEpisodeFilename(
            showTitle: "Breaking Bad",
            season: 5,
            episode: 16,
            episodeTitle: "Felina",
            extension_: "mkv"
        )
        XCTAssertEqual(name, "Breaking Bad - S05E16 - Felina.mkv")
    }

    /// Verifies Plex episode filename without episode title.
    func test_mediaServerTagging_plexEpisodeFilename_noTitle() {
        let name = MediaServerTagging.buildPlexEpisodeFilename(
            showTitle: "Lost",
            season: 1,
            episode: 1,
            extension_: "mp4"
        )
        XCTAssertEqual(name, "Lost - S01E01.mp4")
    }

    /// Verifies Kodi movie NFO generation.
    func test_mediaServerTagging_kodiMovieNFO() {
        let result = MetadataResult(
            source: .tmdb,
            externalId: "27205",
            title: "Inception",
            year: 2010,
            overview: "A mind-bending thriller",
            genres: ["Sci-Fi", "Action"],
            directors: ["Christopher Nolan"],
            confidence: 0.95
        )
        let nfo = MediaServerTagging.buildKodiMovieNFO(result: result)
        XCTAssertTrue(nfo.contains("<movie>"))
        XCTAssertTrue(nfo.contains("<title>Inception</title>"))
        XCTAssertTrue(nfo.contains("<year>2010</year>"))
        XCTAssertTrue(nfo.contains("<genre>Sci-Fi</genre>"))
        XCTAssertTrue(nfo.contains("<director>Christopher Nolan</director>"))
        XCTAssertTrue(nfo.contains("uniqueid type=\"tmdb\""))
    }

    /// Verifies Kodi episode NFO generation.
    func test_mediaServerTagging_kodiEpisodeNFO() {
        let result = MetadataResult(
            source: .tvdb,
            externalId: "12345",
            title: "Pilot",
            season: 1,
            episode: 1,
            confidence: 0.9
        )
        let nfo = MediaServerTagging.buildKodiEpisodeNFO(result: result)
        XCTAssertTrue(nfo.contains("<episodedetails>"))
        XCTAssertTrue(nfo.contains("<season>1</season>"))
        XCTAssertTrue(nfo.contains("<episode>1</episode>"))
    }

    /// Verifies FFmpeg metadata arguments from MetadataResult.
    func test_mediaServerTagging_ffmpegMetadata() {
        let result = MetadataResult(
            source: .tmdb,
            externalId: "27205",
            title: "Inception",
            year: 2010,
            genres: ["Sci-Fi"],
            directors: ["Christopher Nolan"],
            confidence: 0.95
        )
        let args = MediaServerTagging.buildFFmpegMetadataArguments(result: result)
        XCTAssertTrue(args.contains("title=Inception"))
        XCTAssertTrue(args.contains("year=2010"))
        XCTAssertTrue(args.contains("genre=Sci-Fi"))
        XCTAssertTrue(args.contains("director=Christopher Nolan"))
    }

    /// Verifies MediaServer enum.
    func test_mediaServer_displayNames() {
        XCTAssertEqual(MediaServerTagging.MediaServer.plex.displayName, "Plex")
        XCTAssertEqual(MediaServerTagging.MediaServer.jellyfin.displayName, "Jellyfin")
        XCTAssertEqual(MediaServerTagging.MediaServer.emby.displayName, "Emby")
        XCTAssertEqual(MediaServerTagging.MediaServer.kodi.displayName, "Kodi")
    }

}
