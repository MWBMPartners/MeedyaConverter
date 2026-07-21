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
    // MARK: - Phase 13: Tool Bundle Manifest Tests

    /// Verifies default manifest has all expected tools.
    func test_toolBundleManifest_defaultManifest() {
        let manifest = ToolBundleManifest.defaultManifest
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.tools.count, 6)
        XCTAssertNotNil(manifest.tool(id: "dovi_tool"))
        XCTAssertNotNil(manifest.tool(id: "hlg_tools"))
        XCTAssertNotNil(manifest.tool(id: "hdr10plus_tool"))
        XCTAssertNotNil(manifest.tool(id: "mediainfo"))
        XCTAssertNotNil(manifest.tool(id: "fpcalc"))
        XCTAssertNotNil(manifest.tool(id: "subtitle_tonemap"))
    }

    /// Verifies tool lookup by binary name.
    func test_toolBundleManifest_lookupByBinaryName() {
        let manifest = ToolBundleManifest.defaultManifest
        XCTAssertEqual(manifest.tool(binaryName: "pq2hlg")?.id, "hlg_tools")
        XCTAssertEqual(manifest.tool(binaryName: "dovi_tool")?.id, "dovi_tool")
    }

    /// Verifies version comparison.
    func test_toolBundleManifest_versionComparison() {
        XCTAssertTrue(ToolBundleManifest.isUpdateAvailable(installed: "2.1.0", latest: "2.1.2"))
        XCTAssertTrue(ToolBundleManifest.isUpdateAvailable(installed: "1.9.9", latest: "2.0.0"))
        XCTAssertFalse(ToolBundleManifest.isUpdateAvailable(installed: "2.1.2", latest: "2.1.2"))
        XCTAssertFalse(ToolBundleManifest.isUpdateAvailable(installed: "3.0.0", latest: "2.1.2"))
    }

    /// Verifies GitHub release URL builder.
    func test_toolBundleManifest_releaseURL() {
        let tool = ToolBundleManifest.defaultManifest.tool(id: "dovi_tool")!
        let url = ToolBundleManifest.buildLatestReleaseURL(tool: tool)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.contains("api.github.com/repos"))
        XCTAssertTrue(url!.contains("quietvoid/dovi_tool"))
    }

    /// Verifies manifest JSON serialization.
    func test_toolBundleManifest_jsonRoundTrip() throws {
        let manifest = ToolBundleManifest.defaultManifest
        let data = try manifest.toJSON()
        let decoded = try ToolBundleManifest.fromJSON(data)
        XCTAssertEqual(decoded.tools.count, manifest.tools.count)
        XCTAssertEqual(decoded.schemaVersion, manifest.schemaVersion)
    }

    /// Verifies bundled binary path construction.
    func test_toolBundleManifest_bundledBinaryPath() {
        let tool = BundledTool(
            id: "test",
            name: "Test Tool",
            version: "1.0",
            sourceURL: "https://github.com/example/test",
            lastUpdated: "2026-01-01",
            binaryName: "testtool",
            description: "A test tool",
            license: "MIT"
        )
        let path = ToolBundleManifest.bundledBinaryPath(tool: tool, bundlePath: "/app")
        XCTAssertTrue(path.contains("testtool"))
    }

    // MARK: - Phase 14: Auto Tagger Tests

    /// Verifies auto-tag source properties.
    func test_autoTagSource_properties() {
        XCTAssertFalse(AutoTagSource.filename.requiresNetwork)
        XCTAssertFalse(AutoTagSource.existingMetadata.requiresNetwork)
        XCTAssertTrue(AutoTagSource.tmdb.requiresNetwork)
        XCTAssertTrue(AutoTagSource.tmdb.requiresAPIKey)
        XCTAssertFalse(AutoTagSource.musicBrainz.requiresAPIKey)
    }

    /// Verifies auto-tag config defaults.
    func test_autoTagConfig_defaults() {
        let config = AutoTagConfig()
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.minimumConfidence, 0.7)
        XCTAssertTrue(config.embedArtwork)
        XCTAssertFalse(config.writeNFO)
        XCTAssertEqual(config.namingTemplate, .plex)
    }

    /// Verifies output filename generation for movies.
    func test_autoTagger_generateFilename_movie() {
        let result = MetadataResult(
            source: .tmdb,
            externalId: "27205",
            title: "Inception",
            year: 2010,
            confidence: 0.95
        )
        let filename = AutoTagger.generateOutputFilename(
            result: result,
            template: .plex,
            extension_: "mkv"
        )
        XCTAssertEqual(filename, "Inception (2010).mkv")
    }

    /// Verifies output filename generation for TV episodes.
    func test_autoTagger_generateFilename_tv() {
        let result = MetadataResult(
            source: .tvdb,
            externalId: "123",
            title: "Breaking Bad",
            season: 5,
            episode: 16,
            confidence: 0.9
        )
        let filename = AutoTagger.generateOutputFilename(
            result: result,
            template: .plex,
            extension_: "mp4"
        )
        XCTAssertTrue(filename.contains("S05E16"))
    }

    /// Verifies NFO path generation.
    func test_autoTagger_nfoPath() {
        let path = AutoTagger.generateNFOPath(
            outputPath: "/output/Inception (2010).mkv",
            mediaType: .movie
        )
        XCTAssertEqual(path, "/output/Inception (2010).nfo")
    }

    /// Verifies lookup order determination.
    func test_autoTagger_lookupOrder() {
        let query = MetadataSearchQuery(mediaType: .movie, title: "Inception")
        let config = AutoTagConfig(sources: [.filename, .tmdb, .tvdb, .musicBrainz])
        let order = AutoTagger.determineLookupOrder(query: query, config: config)
        XCTAssertTrue(order.contains(.tmdb))
        XCTAssertFalse(order.contains(.musicBrainz))
    }

    /// Verifies confidence threshold check.
    func test_autoTagger_meetsThreshold() {
        let config = AutoTagConfig(minimumConfidence: 0.7)
        let good = MetadataResult(source: .tmdb, externalId: "1", title: "Test", confidence: 0.9)
        let bad = MetadataResult(source: .tmdb, externalId: "2", title: "Test", confidence: 0.3)
        XCTAssertTrue(AutoTagger.meetsThreshold(result: good, config: config))
        XCTAssertFalse(AutoTagger.meetsThreshold(result: bad, config: config))
    }

    /// Verifies filename sanitisation.
    func test_autoTagger_sanitiseFilename() {
        XCTAssertEqual(AutoTagger.sanitiseFilename("Movie: The Sequel"), "Movie The Sequel")
        XCTAssertEqual(AutoTagger.sanitiseFilename("File<>Name"), "FileName")
        XCTAssertEqual(AutoTagger.sanitiseFilename("trailing..."), "trailing")
    }

    /// Verifies artwork embedding arguments.
    func test_autoTagger_artworkArguments() {
        let args = AutoTagger.buildArtworkArguments(artworkPath: "/tmp/poster.jpg")
        XCTAssertTrue(args.contains("/tmp/poster.jpg"))
        XCTAssertTrue(args.contains("attached_pic"))
    }

    // MARK: - Phase 3: TrueHD in MP4 Tests

    /// Verifies TrueHD mux arguments.
    func test_trueHDMP4Muxer_muxArguments() {
        let args = TrueHDMP4Muxer.buildMuxArguments(
            inputPath: "/tmp/movie.mkv",
            outputPath: "/tmp/movie.mp4",
            fallbackCodec: "aac",
            fallbackBitrate: 256
        )
        XCTAssertTrue(args.contains("-strict"))
        XCTAssertTrue(args.contains("unofficial"))
        XCTAssertTrue(args.contains("aac"))
        XCTAssertTrue(args.contains("256k"))
        XCTAssertTrue(args.contains("default"))
    }

    /// Verifies TrueHD remux arguments.
    func test_trueHDMP4Muxer_remuxArguments() {
        let args = TrueHDMP4Muxer.buildRemuxArguments(
            inputPath: "/tmp/in.mkv",
            outputPath: "/tmp/out.mp4"
        )
        XCTAssertTrue(args.contains("-strict"))
        XCTAssertTrue(args.contains("unofficial"))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies AC-3 core extraction arguments.
    func test_trueHDMP4Muxer_ac3Extract() {
        let args = TrueHDMP4Muxer.buildAC3CoreExtractArguments(
            inputPath: "/tmp/movie.mkv",
            outputPath: "/tmp/ac3.ac3"
        )
        XCTAssertTrue(args.contains("ac3"))
        XCTAssertTrue(args.contains("640k"))
    }

    /// Verifies TrueHD validation with fallback track.
    func test_trueHDMP4Muxer_validate_withFallback() {
        let warnings = TrueHDMP4Muxer.validate(
            audioCodecs: ["aac", "truehd"],
            audioDefaults: [true, false]
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    /// Verifies TrueHD validation without fallback.
    func test_trueHDMP4Muxer_validate_noFallback() {
        let warnings = TrueHDMP4Muxer.validate(
            audioCodecs: ["truehd"],
            audioDefaults: [true]
        )
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(warnings[0].contains("fallback"))
    }

    /// Verifies TrueHD validation with default TrueHD.
    func test_trueHDMP4Muxer_validate_trueHDDefault() {
        let warnings = TrueHDMP4Muxer.validate(
            audioCodecs: ["truehd", "aac"],
            audioDefaults: [true, false]
        )
        XCTAssertTrue(warnings.contains { $0.contains("default") })
    }

    /// Verifies container support levels.
    func test_trueHDMP4Muxer_containerSupport() {
        XCTAssertEqual(TrueHDMP4Muxer.trueHDSupport(container: "mkv"), .native)
        XCTAssertEqual(TrueHDMP4Muxer.trueHDSupport(container: "mp4"), .unofficial)
        XCTAssertEqual(TrueHDMP4Muxer.trueHDSupport(container: "webm"), .unsupported)
    }

    /// Verifies no warnings for non-TrueHD content.
    func test_trueHDMP4Muxer_validate_noTrueHD() {
        let warnings = TrueHDMP4Muxer.validate(
            audioCodecs: ["aac", "ac3"],
            audioDefaults: [true, false]
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    // MARK: - Phase 12: API Key Manager Tests

    /// Verifies API key provider properties.
    func test_apiKeyProvider_properties() {
        XCTAssertEqual(APIKeyProvider.tmdb.category, .metadata)
        XCTAssertEqual(APIKeyProvider.awsS3.category, .cloudStorage)
        XCTAssertTrue(APIKeyProvider.googleDrive.usesOAuth)
        XCTAssertFalse(APIKeyProvider.tmdb.usesOAuth)
    }

    /// Verifies API key provider registration URLs.
    func test_apiKeyProvider_registrationURLs() {
        XCTAssertNotNil(APIKeyProvider.tmdb.registrationURL)
        XCTAssertNotNil(APIKeyProvider.acoustID.registrationURL)
        XCTAssertTrue(APIKeyProvider.tmdb.registrationURL!.contains("themoviedb"))
    }

    /// Verifies stored API key validity.
    func test_storedAPIKey_validity() {
        let valid = StoredAPIKey(provider: .tmdb, apiKey: "abc123")
        XCTAssertTrue(valid.isValid)

        let empty = StoredAPIKey(provider: .tmdb, apiKey: "")
        XCTAssertFalse(empty.isValid)

        let awsNoSecret = StoredAPIKey(provider: .awsS3, apiKey: "AKID")
        XCTAssertFalse(awsNoSecret.isValid)

        let awsFull = StoredAPIKey(provider: .awsS3, apiKey: "AKID", secretKey: "secret")
        XCTAssertTrue(awsFull.isValid)
    }

    /// Verifies stored API key token expiry.
    func test_storedAPIKey_tokenExpiry() {
        let expired = StoredAPIKey(
            provider: .googleDrive,
            apiKey: "key",
            accessToken: "tok",
            tokenExpiry: Date(timeIntervalSinceNow: -3600)
        )
        XCTAssertTrue(expired.isTokenExpired)

        let fresh = StoredAPIKey(
            provider: .googleDrive,
            apiKey: "key",
            accessToken: "tok",
            tokenExpiry: Date(timeIntervalSinceNow: 3600)
        )
        XCTAssertFalse(fresh.isTokenExpired)
    }

    /// Verifies API key category display names.
    func test_apiKeyCategory_displayNames() {
        XCTAssertEqual(APIKeyCategory.cloudStorage.displayName, "Cloud Storage & Delivery")
        XCTAssertEqual(APIKeyCategory.metadata.displayName, "Metadata Providers")
    }

    /// Verifies naming template display names.
    func test_namingTemplate_displayNames() {
        XCTAssertEqual(NamingTemplate.plex.displayName, "Plex")
        XCTAssertEqual(NamingTemplate.kodi.displayName, "Kodi")
        XCTAssertEqual(NamingTemplate.simple.displayName, "Simple")
    }

}
