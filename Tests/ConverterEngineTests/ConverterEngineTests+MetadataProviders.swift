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

    // MARK: - Phase 2/3: Metadata Passthrough Tests

    // MARK: MetadataPassthroughMode

    /// Verifies metadata passthrough mode display names.
    func test_metadataPassthroughMode_displayNames() {
        XCTAssertEqual(MetadataPassthroughMode.copyAll.displayName, "Copy All Metadata")
        XCTAssertEqual(MetadataPassthroughMode.strip.displayName, "Strip All Metadata")
    }

    /// Verifies chapter passthrough mode display names.
    func test_chapterPassthroughMode_displayNames() {
        XCTAssertEqual(ChapterPassthroughMode.copy.displayName, "Preserve Chapters")
        XCTAssertEqual(ChapterPassthroughMode.strip.displayName, "Remove Chapters")
    }

    // MARK: MetadataPassthroughBuilder

    /// Verifies copyAll metadata arguments.
    func test_metadataPassthroughBuilder_copyAll() {
        let args = MetadataPassthroughBuilder.buildMetadataArguments(
            config: MetadataPassthroughConfig(mode: .copyAll)
        )
        XCTAssertTrue(args.contains("-map_metadata"))
        XCTAssertTrue(args.contains("0"))
    }

    /// Verifies strip metadata arguments.
    func test_metadataPassthroughBuilder_strip() {
        let args = MetadataPassthroughBuilder.buildMetadataArguments(
            config: MetadataPassthroughConfig(mode: .strip)
        )
        XCTAssertTrue(args.contains("-map_metadata"))
        XCTAssertTrue(args.contains("-1"))
    }

    /// Verifies custom metadata strip arguments.
    func test_metadataPassthroughBuilder_custom() {
        let config = MetadataPassthroughConfig(
            mode: .custom,
            stripKeys: ["comment", "encoder"]
        )
        let args = MetadataPassthroughBuilder.buildMetadataArguments(config: config)
        XCTAssertTrue(args.contains("comment="))
        XCTAssertTrue(args.contains("encoder="))
    }

    /// Verifies chapter copy arguments.
    func test_metadataPassthroughBuilder_chapterCopy() {
        let args = MetadataPassthroughBuilder.buildChapterArguments(mode: .copy)
        XCTAssertTrue(args.contains("-map_chapters"))
        XCTAssertTrue(args.contains("0"))
    }

    /// Verifies chapter strip arguments.
    func test_metadataPassthroughBuilder_chapterStrip() {
        let args = MetadataPassthroughBuilder.buildChapterArguments(mode: .strip)
        XCTAssertTrue(args.contains("-map_chapters"))
        XCTAssertTrue(args.contains("-1"))
    }

    /// Verifies aspect ratio override arguments.
    func test_metadataPassthroughBuilder_aspectRatioOverride() {
        let args = MetadataPassthroughBuilder.buildAspectRatioArguments(
            mode: .override_,
            customRatio: "16:9"
        )
        XCTAssertTrue(args.contains("-aspect"))
        XCTAssertTrue(args.contains("16:9"))
    }

    /// Verifies aspect ratio preserve returns no arguments.
    func test_metadataPassthroughBuilder_aspectRatioPreserve() {
        let args = MetadataPassthroughBuilder.buildAspectRatioArguments(mode: .preserve)
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies disposition reset arguments.
    func test_metadataPassthroughBuilder_dispositionReset() {
        let args = MetadataPassthroughBuilder.buildDispositionArguments(
            copyDispositions: false,
            streamIndex: 1
        )
        XCTAssertTrue(args.contains("-disposition:1"))
        XCTAssertTrue(args.contains("0"))
    }

    /// Verifies set default stream arguments.
    func test_metadataPassthroughBuilder_setDefault() {
        let args = MetadataPassthroughBuilder.buildSetDefaultStream(streamSpecifier: "a:0")
        XCTAssertTrue(args.contains("-disposition:a:0"))
        XCTAssertTrue(args.contains("default"))
    }

    /// Verifies color description preservation arguments.
    func test_metadataPassthroughBuilder_colorDescription() {
        let args = MetadataPassthroughBuilder.buildColorDescriptionArguments(
            colorPrimaries: "bt2020",
            transferCharacteristics: "smpte2084",
            colorMatrix: "bt2020nc"
        )
        XCTAssertTrue(args.contains("-color_primaries"))
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("smpte2084"))
        XCTAssertTrue(args.contains("-colorspace"))
        XCTAssertTrue(args.contains("bt2020nc"))
    }

    /// Verifies full argument builder combines all config.
    func test_metadataPassthroughBuilder_allArguments() {
        let config = MetadataPassthroughConfig(
            mode: .copyAll,
            chapterMode: .copy,
            aspectRatioMode: .override_,
            customAspectRatio: "2.35:1",
            preserveCodecMetadata: true,
            copyDispositions: true
        )
        let args = MetadataPassthroughBuilder.buildAllArguments(config: config)
        XCTAssertTrue(args.contains("-map_metadata"))
        XCTAssertTrue(args.contains("-map_chapters"))
        XCTAssertTrue(args.contains("-aspect"))
        XCTAssertTrue(args.contains("2.35:1"))
    }

    /// Verifies AFD preservation arguments.
    func test_metadataPassthroughBuilder_afdPreservation() {
        let args = MetadataPassthroughBuilder.buildAFDPreservationArguments(preserveAFD: true)
        XCTAssertTrue(args.contains("-copy_unknown"))

        let empty = MetadataPassthroughBuilder.buildAFDPreservationArguments(preserveAFD: false)
        XCTAssertTrue(empty.isEmpty)
    }

    /// Verifies codec metadata bitexact strip.
    func test_metadataPassthroughBuilder_codecMetadata() {
        let strip = MetadataPassthroughBuilder.buildCodecMetadataArguments(preserve: false)
        XCTAssertTrue(strip.contains("-bitexact"))

        let preserve = MetadataPassthroughBuilder.buildCodecMetadataArguments(preserve: true)
        XCTAssertTrue(preserve.isEmpty)
    }

    /// Verifies default MetadataPassthroughConfig.
    func test_metadataPassthroughConfig_defaults() {
        let config = MetadataPassthroughConfig()
        XCTAssertEqual(config.mode, .copyAll)
        XCTAssertEqual(config.chapterMode, .copy)
        XCTAssertEqual(config.aspectRatioMode, .preserve)
        XCTAssertTrue(config.preserveCodecMetadata)
        XCTAssertTrue(config.copyDispositions)
    }

    /// Verifies MediaServer enum.
    func test_mediaServer_displayNames() {
        XCTAssertEqual(MediaServerTagging.MediaServer.plex.displayName, "Plex")
        XCTAssertEqual(MediaServerTagging.MediaServer.jellyfin.displayName, "Jellyfin")
        XCTAssertEqual(MediaServerTagging.MediaServer.emby.displayName, "Emby")
        XCTAssertEqual(MediaServerTagging.MediaServer.kodi.displayName, "Kodi")
    }

}
