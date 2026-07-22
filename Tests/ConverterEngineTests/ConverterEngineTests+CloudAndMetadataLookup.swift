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
    // -----------------------------------------------------------------
    // MARK: - Phase 12: Cloud Integration
    // -----------------------------------------------------------------

    /// Verifies CloudProvider CaseIterable and display names.
    func test_cloudProvider_allCases() {
        XCTAssertEqual(CloudProvider.allCases.count, 11)
        XCTAssertEqual(CloudProvider.awsS3.displayName, "Amazon S3")
        XCTAssertEqual(CloudProvider.dropbox.displayName, "Dropbox")
        XCTAssertEqual(CloudProvider.sftp.displayName, "SFTP")
    }

    /// Verifies streaming provider detection.
    func test_cloudProvider_supportsStreaming() {
        XCTAssertTrue(CloudProvider.cloudflareStream.supportsStreaming)
        XCTAssertTrue(CloudProvider.mux.supportsStreaming)
        XCTAssertFalse(CloudProvider.awsS3.supportsStreaming)
        XCTAssertFalse(CloudProvider.dropbox.supportsStreaming)
    }

    /// Verifies OAuth provider detection.
    func test_cloudProvider_usesOAuth() {
        XCTAssertTrue(CloudProvider.googleDrive.usesOAuth)
        XCTAssertTrue(CloudProvider.dropbox.usesOAuth)
        XCTAssertFalse(CloudProvider.awsS3.usesOAuth)
        XCTAssertFalse(CloudProvider.sftp.usesOAuth)
    }

    /// Verifies CloudCredential configuration validation.
    func test_cloudCredential_isConfigured() {
        let s3 = CloudCredential(provider: .awsS3, apiKey: "key", secret: "secret", bucket: "bucket")
        XCTAssertTrue(s3.isConfigured)

        let s3Incomplete = CloudCredential(provider: .awsS3, apiKey: "key")
        XCTAssertFalse(s3Incomplete.isConfigured)

        let sftp = CloudCredential(provider: .sftp, endpoint: "host.com", username: "user")
        XCTAssertTrue(sftp.isConfigured)

        let sftpIncomplete = CloudCredential(provider: .sftp)
        XCTAssertFalse(sftpIncomplete.isConfigured)
    }

    /// Verifies token expiry detection.
    func test_cloudCredential_tokenExpiry() {
        let expired = CloudCredential(
            provider: .googleDrive,
            accessToken: "token",
            tokenExpiry: Date(timeIntervalSinceNow: -3600)
        )
        XCTAssertTrue(expired.isTokenExpired)

        let valid = CloudCredential(
            provider: .googleDrive,
            accessToken: "token",
            tokenExpiry: Date(timeIntervalSinceNow: 3600)
        )
        XCTAssertFalse(valid.isTokenExpired)
    }

    /// Verifies UploadProgress calculations.
    func test_uploadProgress_calculations() {
        let progress = UploadProgress(
            bytesUploaded: 500_000_000,
            totalBytes: 1_000_000_000,
            bytesPerSecond: 10_000_000
        )
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.percentage, 50)
        XCTAssertNotNil(progress.estimatedTimeRemaining)
        XCTAssertEqual(progress.estimatedTimeRemaining!, 50.0, accuracy: 0.1)
    }

    /// Verifies content type detection.
    func test_uploadConfig_contentType() {
        XCTAssertEqual(UploadConfig.contentType(for: "movie.mp4"), "video/mp4")
        XCTAssertEqual(UploadConfig.contentType(for: "audio.flac"), "audio/flac")
        XCTAssertEqual(UploadConfig.contentType(for: "subs.vtt"), "text/vtt")
        XCTAssertEqual(UploadConfig.contentType(for: "unknown.xyz"), "application/octet-stream")
    }

    /// Verifies S3 endpoint URL construction.
    func test_s3Uploader_endpointURL() {
        let cred = CloudCredential(
            provider: .awsS3, region: "eu-west-1", bucket: "my-bucket"
        )
        let url = S3Uploader.buildEndpointURL(credential: cred, objectKey: "video/output.mp4")
        XCTAssertTrue(url.contains("s3.eu-west-1.amazonaws.com"))
        XCTAssertTrue(url.contains("my-bucket"))
        XCTAssertTrue(url.contains("video/output.mp4"))
    }

    /// Verifies S3 multipart threshold.
    func test_s3Uploader_shouldUseMultipart() {
        XCTAssertFalse(S3Uploader.shouldUseMultipart(fileSize: 50 * 1024 * 1024)) // 50 MB
        XCTAssertTrue(S3Uploader.shouldUseMultipart(fileSize: 200 * 1024 * 1024)) // 200 MB
    }

    /// Verifies S3 part count calculation.
    func test_s3Uploader_partCount() {
        let count = S3Uploader.calculatePartCount(
            fileSize: 100_000_000, // 100 MB
            partSize: 8 * 1024 * 1024 // 8 MB parts
        )
        XCTAssertEqual(count, 12) // ceil(100_000_000 / 8_388_608)
    }

    /// Verifies S3 credential validation.
    func test_s3Uploader_validate() {
        let valid = CloudCredential(provider: .awsS3, apiKey: "k", secret: "s", bucket: "b")
        XCTAssertTrue(S3Uploader.validate(credential: valid).isEmpty)

        let invalid = CloudCredential(provider: .awsS3)
        XCTAssertFalse(S3Uploader.validate(credential: invalid).isEmpty)
    }

    /// Verifies S3 upload headers.
    func test_s3Uploader_headers() {
        let headers = S3Uploader.buildUploadHeaders(
            contentType: "video/mp4",
            contentLength: 1_000_000,
            metadata: ["title": "Test Video"]
        )
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
        XCTAssertEqual(headers["Content-Length"], "1000000")
        XCTAssertEqual(headers["x-amz-meta-title"], "Test Video")
    }

    /// Verifies SFTP SCP arguments.
    func test_sftpUploader_scpArguments() {
        let config = SFTPServerConfig(
            host: "server.com",
            port: 2222,
            username: "user",
            authMethod: .password("pass"),
            remotePath: "/uploads",
            label: "Test"
        )
        let args = SFTPUploader.buildSCPArguments(
            localPath: "/tmp/video.mp4",
            config: config
        )
        XCTAssertTrue(args.contains("-P"))
        XCTAssertTrue(args.contains("2222"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
    }

    /// Verifies SFTP rsync arguments.
    func test_sftpUploader_rsync() {
        let config = SFTPServerConfig(
            host: "server.com",
            port: 22,
            username: "user",
            authMethod: .agent,
            remotePath: "/uploads",
            label: "Test"
        )
        let args = SFTPUploader.buildRsyncArguments(
            localPath: "/tmp/file.mp4",
            config: config
        )
        XCTAssertFalse(args.isEmpty)
        XCTAssertTrue(args.contains(where: { $0.contains("ssh") }))
    }

    // -----------------------------------------------------------------
    // MARK: - Issue #380: FTP credentials via curl config file
    // -----------------------------------------------------------------
    //
    // The audit follow-up replaced `-u user:pass` (visible in `ps aux`)
    // with `-K <path>` reading from a 0600-permissioned config file. The
    // tests below verify the three security-relevant invariants:
    //
    //   1. The on-disk config file has POSIX mode 0600.
    //   2. The credentials directive escapes embedded `"` and `\` so a
    //      malicious password cannot break out of the quoted form.
    //   3. The argument array no longer contains `-u` or any substring
    //      that includes the plaintext password.

    /// Verifies the FTP credentials file is written with `0600` perms and
    /// contains a properly escaped `user` directive.
    func test_sftpUploader_ftpCredentialsConfig_isOwnerReadableOnly() throws {
        // Use a password containing the two characters that must be
        // escaped for curl's quoted config syntax — `\` and `"`.
        let config = FTPServerConfig(
            host: "ftp.example.com",
            port: 21,
            username: "alice",
            password: "p\"ass\\word",
            useTLS: false,
            remotePath: "/incoming",
            label: "Test"
        )

        let url = try SFTPUploader.writeFTPCredentialsConfig(config: config)
        defer { try? FileManager.default.removeItem(at: url) }

        // ---- Perms must be exactly 0600 (owner rw, no group/other) ----
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600,
                       "FTP credentials file must be 0600 to keep "
                       + "credentials unreadable by other local users.")

        // ---- The file lives in the system temp dir, not the cwd ----
        let tempPath = FileManager.default.temporaryDirectory
            .standardizedFileURL.path
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(tempPath),
                      "Credentials file must live under the temp "
                      + "directory, not in the project working tree.")

        // ---- Contents: backslash and double quote are escaped ----
        let body = try String(contentsOf: url, encoding: .utf8)
        // Backslashes are doubled, then the embedded `"` is `\"`.
        // The full expected line is:
        //     user = "alice:p\"ass\\word"
        XCTAssertEqual(body, "user = \"alice:p\\\"ass\\\\word\"\n",
                       "Credentials directive must escape `\\` and `\"` "
                       + "to prevent password breakout from the quoted "
                       + "config value.")
    }

    /// Verifies the curl argument array references `-K <path>` and no
    /// longer carries `-u user:pass` (the pre-#380 form that exposed
    /// credentials to `ps aux`).
    func test_sftpUploader_ftpUploadArguments_useConfigFileNotInlineCreds() {
        let config = FTPServerConfig(
            host: "ftp.example.com",
            port: 21,
            username: "alice",
            password: "supersecret",
            useTLS: true,
            remotePath: "/incoming",
            label: "Test"
        )
        let configPath = "/tmp/fake-credentials.curlrc"

        let args = SFTPUploader.buildFTPUploadArguments(
            localPath: "/tmp/video.mp4",
            config: config,
            credentialsConfigPath: configPath
        )

        // ---- `-K <path>` must be present and adjacent ----
        guard let kIndex = args.firstIndex(of: "-K") else {
            return XCTFail("Expected `-K` flag in curl arguments.")
        }
        XCTAssertLessThan(kIndex + 1, args.count,
                          "`-K` must be followed by the config path.")
        XCTAssertEqual(args[kIndex + 1], configPath)

        // ---- `-u` (inline credentials) must NOT appear ----
        XCTAssertFalse(args.contains("-u"),
                       "Inline `-u user:pass` is forbidden — credentials "
                       + "must come from the `-K` config file.")

        // ---- Plaintext password must not appear anywhere in argv ----
        XCTAssertFalse(args.contains(where: { $0.contains("supersecret") }),
                       "Plaintext password leaked into argv; this would "
                       + "be visible via `ps aux`.")

        // ---- TLS settings still applied ----
        XCTAssertTrue(args.contains("--ssl-reqd"),
                      "FTPS uploads must still pass --ssl-reqd.")
        XCTAssertTrue(args.contains(where: { $0.hasPrefix("ftps://") }),
                      "FTPS uploads must use the ftps:// URL scheme.")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 15: Media Metadata Lookup
    // -----------------------------------------------------------------

    /// Verifies MetadataSource CaseIterable and properties.
    func test_metadataSource_allCases() {
        XCTAssertEqual(MetadataSource.allCases.count, 7)
        XCTAssertEqual(MetadataSource.tmdb.displayName, "The Movie Database (TMDB)")
        XCTAssertFalse(MetadataSource.musicBrainz.requiresAPIKey)
        XCTAssertTrue(MetadataSource.tmdb.requiresAPIKey)
    }

    /// Verifies TMDB movie search URL construction.
    func test_tmdbClient_movieSearchURL() {
        let url = TMDBClient.buildMovieSearchURL(
            query: "Inception", year: 2010, apiKey: "test-key"
        )
        XCTAssertTrue(url.contains("api.themoviedb.org/3/search/movie"))
        XCTAssertTrue(url.contains("api_key=test-key"))
        XCTAssertTrue(url.contains("query=Inception"))
        XCTAssertTrue(url.contains("year=2010"))
    }

    /// Verifies TMDB TV search URL construction.
    func test_tmdbClient_tvSearchURL() {
        let url = TMDBClient.buildTVSearchURL(
            query: "Breaking Bad", apiKey: "test-key"
        )
        XCTAssertTrue(url.contains("search/tv"))
        XCTAssertTrue(url.contains("Breaking"))
    }

    /// Verifies TMDB poster URL construction.
    func test_tmdbClient_posterURL() {
        let url = TMDBClient.posterURL(path: "/abc123.jpg")
        XCTAssertEqual(url, "https://image.tmdb.org/t/p/w500/abc123.jpg")
    }

    /// Verifies MusicBrainz recording search URL.
    func test_musicBrainzClient_recordingSearch() {
        let url = MusicBrainzClient.buildRecordingSearchURL(
            title: "Bohemian Rhapsody", artist: "Queen"
        )
        XCTAssertTrue(url.contains("musicbrainz.org/ws/2/recording"))
        XCTAssertTrue(url.contains("fmt=json"))
        XCTAssertTrue(url.contains("Bohemian"))
    }

    /// Verifies MusicBrainz User-Agent.
    func test_musicBrainzClient_userAgent() {
        XCTAssertTrue(MusicBrainzClient.userAgent.contains("MeedyaConverter"))
    }

    /// Verifies OpenSubtitles search URL.
    func test_openSubtitlesClient_searchURL() {
        let url = OpenSubtitlesClient.buildSearchURL(
            query: "Inception", language: "en", apiKey: "test"
        )
        XCTAssertTrue(url.contains("opensubtitles.com"))
        XCTAssertTrue(url.contains("query=Inception"))
        XCTAssertTrue(url.contains("languages=en"))
    }

    /// Verifies OpenSubtitles headers.
    func test_openSubtitlesClient_headers() {
        let headers = OpenSubtitlesClient.buildHeaders(apiKey: "mykey")
        XCTAssertEqual(headers["Api-Key"], "mykey")
        XCTAssertNotNil(headers["User-Agent"])
    }

    /// Verifies filename parser — TV show pattern.
    func test_filenameParser_tvShow() {
        let result = FilenameParser.parse(filename: "Breaking.Bad.S03E07.720p.BluRay.mkv")
        XCTAssertEqual(result.mediaType, .tvEpisode)
        XCTAssertEqual(result.title, "Breaking Bad")
        XCTAssertEqual(result.season, 3)
        XCTAssertEqual(result.episode, 7)
    }

    /// Verifies filename parser — movie pattern.
    func test_filenameParser_movie() {
        let result = FilenameParser.parse(filename: "Inception (2010).mkv")
        XCTAssertEqual(result.mediaType, .movie)
        XCTAssertEqual(result.title, "Inception")
        XCTAssertEqual(result.year, 2010)
    }

    /// Verifies filename parser — music pattern.
    func test_filenameParser_music() {
        let result = FilenameParser.parse(filename: "Queen - Bohemian Rhapsody.flac")
        XCTAssertEqual(result.mediaType, .music)
        XCTAssertEqual(result.artist, "Queen")
        XCTAssertTrue(result.title.contains("Bohemian Rhapsody"))
    }

    /// Verifies filename parser — fallback.
    func test_filenameParser_fallback() {
        let result = FilenameParser.parse(filename: "random_video_file.mp4")
        XCTAssertEqual(result.mediaType, .movie)
        XCTAssertTrue(result.title.contains("random"))
    }

    /// Verifies MetadataResult construction.
    func test_metadataResult_construction() {
        let result = MetadataResult(
            source: .tmdb,
            externalId: "27205",
            title: "Inception",
            year: 2010,
            genres: ["Sci-Fi", "Action"],
            score: 8.4,
            runtimeMinutes: 148,
            directors: ["Christopher Nolan"],
            confidence: 0.95
        )
        XCTAssertEqual(result.source, .tmdb)
        XCTAssertEqual(result.title, "Inception")
        XCTAssertEqual(result.year, 2010)
        XCTAssertEqual(result.genres.count, 2)
        XCTAssertEqual(result.confidence, 0.95)
    }

}
