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
    // MARK: - Phase 12: Cloud Providers Tests

    // MARK: Google Drive

    /// Verifies Google Drive simple upload URL construction.
    func test_googleDriveUploader_simpleUploadURL() {
        let url = GoogleDriveUploader.buildSimpleUploadURL(accessToken: "ya29.test")
        XCTAssertTrue(url.contains("googleapis.com/upload/drive/v3/files"))
        XCTAssertTrue(url.contains("uploadType=media"))
    }

    /// Verifies Google Drive resumable upload URL construction.
    func test_googleDriveUploader_resumableUploadURL() {
        let url = GoogleDriveUploader.buildResumableUploadURL()
        XCTAssertTrue(url.contains("uploadType=resumable"))
    }

    /// Verifies Google Drive upload headers include authorization and content type.
    func test_googleDriveUploader_uploadHeaders() {
        let headers = GoogleDriveUploader.buildUploadHeaders(
            accessToken: "ya29.test",
            contentType: "video/mp4",
            contentLength: 1024
        )
        XCTAssertEqual(headers["Authorization"], "Bearer ya29.test")
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
        XCTAssertEqual(headers["Content-Length"], "1024")
    }

    /// Verifies Google Drive upload headers omit content-length when nil.
    func test_googleDriveUploader_uploadHeaders_noLength() {
        let headers = GoogleDriveUploader.buildUploadHeaders(
            accessToken: "tok",
            contentType: "video/mp4"
        )
        XCTAssertNil(headers["Content-Length"])
    }

    /// Verifies Google Drive upload metadata JSON with folder.
    func test_googleDriveUploader_uploadMetadata_withFolder() {
        let json = GoogleDriveUploader.buildUploadMetadata(
            filename: "movie.mp4",
            mimeType: "video/mp4",
            folderId: "folder123"
        )
        XCTAssertTrue(json.contains("\"name\":\"movie.mp4\""))
        XCTAssertTrue(json.contains("\"mimeType\":\"video/mp4\""))
        XCTAssertTrue(json.contains("\"parents\":[\"folder123\"]"))
    }

    /// Verifies Google Drive upload metadata JSON without folder.
    func test_googleDriveUploader_uploadMetadata_noFolder() {
        let json = GoogleDriveUploader.buildUploadMetadata(
            filename: "test.mov",
            mimeType: "video/quicktime"
        )
        XCTAssertFalse(json.contains("parents"))
    }

    /// Verifies Google Drive folder creation body.
    func test_googleDriveUploader_createFolderBody() {
        let json = GoogleDriveUploader.buildCreateFolderBody(
            folderName: "Exports",
            parentId: "root123"
        )
        XCTAssertTrue(json.contains("\"name\":\"Exports\""))
        XCTAssertTrue(json.contains("application/vnd.google-apps.folder"))
        XCTAssertTrue(json.contains("\"parents\":[\"root123\"]"))
    }

    /// Verifies Google Drive upload size constants.
    func test_googleDriveUploader_constants() {
        XCTAssertEqual(GoogleDriveUploader.simpleUploadMaxBytes, 5 * 1024 * 1024)
        XCTAssertEqual(GoogleDriveUploader.resumableChunkSize, 5 * 1024 * 1024)
    }

    // MARK: Dropbox

    /// Verifies Dropbox upload URLs.
    func test_dropboxUploader_urls() {
        XCTAssertTrue(DropboxUploader.uploadURL.contains("content.dropboxapi.com"))
        XCTAssertTrue(DropboxUploader.sessionStartURL.contains("upload_session/start"))
        XCTAssertTrue(DropboxUploader.sessionAppendURL.contains("upload_session/append_v2"))
        XCTAssertTrue(DropboxUploader.sessionFinishURL.contains("upload_session/finish"))
    }

    /// Verifies Dropbox upload headers with overwrite mode.
    func test_dropboxUploader_uploadHeaders_overwrite() {
        let headers = DropboxUploader.buildUploadHeaders(
            accessToken: "dbx_tok",
            dropboxPath: "/Videos/movie.mp4",
            overwrite: true
        )
        XCTAssertEqual(headers["Authorization"], "Bearer dbx_tok")
        XCTAssertEqual(headers["Content-Type"], "application/octet-stream")
        let apiArg = headers["Dropbox-API-Arg"]!
        XCTAssertTrue(apiArg.contains("\"mode\":\"overwrite\""))
        XCTAssertTrue(apiArg.contains("/Videos/movie.mp4"))
    }

    /// Verifies Dropbox upload headers default to add mode.
    func test_dropboxUploader_uploadHeaders_addMode() {
        let headers = DropboxUploader.buildUploadHeaders(
            accessToken: "tok",
            dropboxPath: "/test.mp4"
        )
        let apiArg = headers["Dropbox-API-Arg"]!
        XCTAssertTrue(apiArg.contains("\"mode\":\"add\""))
        XCTAssertTrue(apiArg.contains("\"autorename\":true"))
    }

    /// Verifies Dropbox session start headers.
    func test_dropboxUploader_sessionStartHeaders() {
        let headers = DropboxUploader.buildSessionStartHeaders(accessToken: "dbx_tok")
        XCTAssertEqual(headers["Authorization"], "Bearer dbx_tok")
        XCTAssertEqual(headers["Content-Type"], "application/octet-stream")
    }

    /// Verifies Dropbox session finish headers include cursor and commit.
    func test_dropboxUploader_sessionFinishHeaders() {
        let headers = DropboxUploader.buildSessionFinishHeaders(
            accessToken: "dbx_tok",
            sessionId: "sess_abc123",
            offset: 8388608,
            dropboxPath: "/Videos/large.mp4"
        )
        let apiArg = headers["Dropbox-API-Arg"]!
        XCTAssertTrue(apiArg.contains("\"session_id\":\"sess_abc123\""))
        XCTAssertTrue(apiArg.contains("\"offset\":8388608"))
        XCTAssertTrue(apiArg.contains("/Videos/large.mp4"))
    }

    /// Verifies Dropbox size constants.
    func test_dropboxUploader_constants() {
        XCTAssertEqual(DropboxUploader.singleUploadMaxBytes, 150 * 1024 * 1024)
        XCTAssertEqual(DropboxUploader.sessionChunkSize, 8 * 1024 * 1024)
    }

    // MARK: Azure Blob

    /// Verifies Azure Blob URL construction.
    func test_azureBlobUploader_buildBlobURL() {
        let url = AzureBlobUploader.buildBlobURL(
            accountName: "myaccount",
            containerName: "videos",
            blobName: "movie.mp4"
        )
        XCTAssertEqual(url, "https://myaccount.blob.core.windows.net/videos/movie.mp4")
    }

    /// Verifies Azure Blob upload headers.
    func test_azureBlobUploader_uploadHeaders() {
        let headers = AzureBlobUploader.buildUploadHeaders(
            sasToken: "sv=2023-11-03&sig=abc",
            contentType: "video/mp4",
            contentLength: 5000000
        )
        XCTAssertEqual(headers["x-ms-blob-type"], "BlockBlob")
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
        XCTAssertEqual(headers["Content-Length"], "5000000")
        XCTAssertEqual(headers["x-ms-version"], "2023-11-03")
    }

    /// Verifies Azure Blob authenticated URL with SAS token.
    func test_azureBlobUploader_authenticatedURL() {
        let url = AzureBlobUploader.buildAuthenticatedURL(
            blobURL: "https://acct.blob.core.windows.net/c/b.mp4",
            sasToken: "sv=2023&sig=xyz"
        )
        XCTAssertEqual(url, "https://acct.blob.core.windows.net/c/b.mp4?sv=2023&sig=xyz")
    }

    /// Verifies Azure Blob block list XML generation.
    func test_azureBlobUploader_blockListXML() {
        let xml = AzureBlobUploader.buildBlockListXML(blockIds: ["YmxvY2sx", "YmxvY2sy"])
        XCTAssertTrue(xml.contains("<?xml version=\"1.0\""))
        XCTAssertTrue(xml.contains("<BlockList>"))
        XCTAssertTrue(xml.contains("<Latest>YmxvY2sx</Latest>"))
        XCTAssertTrue(xml.contains("<Latest>YmxvY2sy</Latest>"))
        XCTAssertTrue(xml.contains("</BlockList>"))
    }

    /// Verifies Azure Blob size constants.
    func test_azureBlobUploader_constants() {
        XCTAssertEqual(AzureBlobUploader.maxBlockSize, 100 * 1024 * 1024)
        XCTAssertEqual(AzureBlobUploader.defaultBlockSize, 4 * 1024 * 1024)
    }

    // MARK: OneDrive

    /// Verifies OneDrive simple upload URL.
    func test_oneDriveUploader_simpleUploadURL() {
        let url = OneDriveUploader.buildSimpleUploadURL(drivePath: "/Videos/movie.mp4")
        XCTAssertTrue(url.contains("graph.microsoft.com/v1.0"))
        XCTAssertTrue(url.contains("/me/drive/root:/Videos/movie.mp4:/content"))
    }

    /// Verifies OneDrive create session URL.
    func test_oneDriveUploader_createSessionURL() {
        let url = OneDriveUploader.buildCreateSessionURL(drivePath: "/Videos/movie.mp4")
        XCTAssertTrue(url.contains("/createUploadSession"))
        XCTAssertTrue(url.contains("/Videos/movie.mp4"))
    }

    /// Verifies OneDrive upload headers.
    func test_oneDriveUploader_uploadHeaders() {
        let headers = OneDriveUploader.buildUploadHeaders(
            accessToken: "ey_msft_token",
            contentType: "video/mp4"
        )
        XCTAssertEqual(headers["Authorization"], "Bearer ey_msft_token")
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
    }

    /// Verifies OneDrive session body with custom conflict behavior.
    func test_oneDriveUploader_sessionBody() {
        let body = OneDriveUploader.buildSessionBody(conflictBehavior: "replace")
        XCTAssertTrue(body.contains("\"@microsoft.graph.conflictBehavior\":\"replace\""))
    }

    /// Verifies OneDrive session body defaults to rename.
    func test_oneDriveUploader_sessionBody_defaultRename() {
        let body = OneDriveUploader.buildSessionBody()
        XCTAssertTrue(body.contains("\"rename\""))
    }

    /// Verifies OneDrive size constants.
    func test_oneDriveUploader_constants() {
        XCTAssertEqual(OneDriveUploader.simpleUploadMaxBytes, 4 * 1024 * 1024)
        XCTAssertEqual(OneDriveUploader.fragmentSize, 10 * 1024 * 1024)
    }

    // MARK: Cloudflare Stream

    /// Verifies Cloudflare Stream direct upload URL.
    func test_cloudflareStreamUploader_directUploadURL() {
        let url = CloudflareStreamUploader.buildDirectUploadURL(accountId: "acc_123")
        XCTAssertTrue(url.contains("api.cloudflare.com/client/v4"))
        XCTAssertTrue(url.contains("accounts/acc_123/stream/direct_upload"))
    }

    /// Verifies Cloudflare Stream TUS upload URL.
    func test_cloudflareStreamUploader_tusUploadURL() {
        let url = CloudflareStreamUploader.buildTUSUploadURL(accountId: "acc_456")
        XCTAssertTrue(url.contains("accounts/acc_456/stream"))
        XCTAssertFalse(url.contains("direct_upload"))
    }

    /// Verifies Cloudflare Stream upload headers include TUS protocol headers.
    func test_cloudflareStreamUploader_uploadHeaders() {
        let headers = CloudflareStreamUploader.buildUploadHeaders(
            apiToken: "cf_token",
            contentLength: 50_000_000
        )
        XCTAssertEqual(headers["Authorization"], "Bearer cf_token")
        XCTAssertEqual(headers["Tus-Resumable"], "1.0.0")
        XCTAssertEqual(headers["Upload-Length"], "50000000")
        XCTAssertEqual(headers["Content-Length"], "50000000")
    }

    /// Verifies Cloudflare Stream upload metadata encoding.
    func test_cloudflareStreamUploader_uploadMetadata() {
        let metadata = CloudflareStreamUploader.buildUploadMetadata(
            name: "My Video",
            requireSignedURLs: true
        )
        XCTAssertTrue(metadata.contains("name "))
        XCTAssertTrue(metadata.contains("requiresignedurls "))
    }

    /// Verifies Cloudflare Stream metadata without signed URLs.
    func test_cloudflareStreamUploader_uploadMetadata_noSigned() {
        let metadata = CloudflareStreamUploader.buildUploadMetadata(name: "Test")
        XCTAssertTrue(metadata.contains("name "))
        XCTAssertFalse(metadata.contains("requiresignedurls"))
    }

    // MARK: FTP

    /// Verifies FTP curl upload arguments with FTPS.
    func test_ftpUploader_curlArguments_ftps() {
        let args = FTPUploader.buildCurlUploadArguments(
            localPath: "/tmp/video.mp4",
            ftpURL: "ftp://server.com/uploads/video.mp4",
            username: "user",
            password: "pass",
            useFTPS: true
        )
        XCTAssertTrue(args.contains("-T"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        XCTAssertTrue(args.contains("-u"))
        XCTAssertTrue(args.contains("user:pass"))
        XCTAssertTrue(args.contains("--ssl-reqd"))
        XCTAssertTrue(args.contains("--ftp-create-dirs"))
        XCTAssertTrue(args.contains("ftp://server.com/uploads/video.mp4"))
    }

    /// Verifies FTP curl upload arguments without FTPS.
    func test_ftpUploader_curlArguments_noFTPS() {
        let args = FTPUploader.buildCurlUploadArguments(
            localPath: "/tmp/file.mp4",
            ftpURL: "ftp://server.com/file.mp4",
            username: "u",
            password: "p",
            useFTPS: false
        )
        XCTAssertFalse(args.contains("--ssl-reqd"))
        XCTAssertTrue(args.contains("--progress-bar"))
    }

    /// Verifies lftp command string construction.
    func test_ftpUploader_lftpCommand() {
        let cmd = FTPUploader.buildLftpCommand(
            localPath: "/tmp/video.mp4",
            remotePath: "/uploads/video.mp4",
            host: "ftp.example.com",
            username: "user",
            password: "pass",
            useFTPS: true
        )
        XCTAssertTrue(cmd.contains("open ftps://"))
        XCTAssertTrue(cmd.contains("user:pass@ftp.example.com"))
        XCTAssertTrue(cmd.contains("put /tmp/video.mp4 -o /uploads/video.mp4"))
        XCTAssertTrue(cmd.contains("&& bye"))
    }

    /// Verifies lftp command with plain FTP.
    func test_ftpUploader_lftpCommand_plainFTP() {
        let cmd = FTPUploader.buildLftpCommand(
            localPath: "/tmp/f.mp4",
            remotePath: "/f.mp4",
            host: "ftp.test.com",
            username: "u",
            password: "p",
            useFTPS: false
        )
        XCTAssertTrue(cmd.contains("open ftp://"))
        XCTAssertFalse(cmd.contains("ftps://"))
    }

    // MARK: APIKeyConfig

    /// Verifies APIKeyConfig initialization and validity.
    func test_apiKeyConfig_isValid() {
        let config = APIKeyConfig(
            provider: .googleDrive,
            apiKey: "ya29.test_key"
        )
        XCTAssertTrue(config.isValid)
        XCTAssertEqual(config.provider, .googleDrive)
        XCTAssertEqual(config.apiKey, "ya29.test_key")
        XCTAssertNil(config.secretKey)
        XCTAssertNil(config.refreshToken)
    }

    /// Verifies APIKeyConfig with empty key is invalid.
    func test_apiKeyConfig_emptyKey_isInvalid() {
        let config = APIKeyConfig(
            provider: .dropbox,
            apiKey: ""
        )
        XCTAssertFalse(config.isValid)
    }

    /// Verifies APIKeyConfig token expiry detection.
    func test_apiKeyConfig_tokenExpired() {
        let expired = APIKeyConfig(
            provider: .oneDrive,
            apiKey: "token",
            tokenExpiresAt: Date(timeIntervalSinceNow: -3600)
        )
        XCTAssertTrue(expired.isTokenExpired)

        let valid = APIKeyConfig(
            provider: .oneDrive,
            apiKey: "token",
            tokenExpiresAt: Date(timeIntervalSinceNow: 3600)
        )
        XCTAssertFalse(valid.isTokenExpired)
    }

    /// Verifies APIKeyConfig without expiry is not expired.
    func test_apiKeyConfig_noExpiry_notExpired() {
        let config = APIKeyConfig(
            provider: .azureBlob,
            apiKey: "key"
        )
        XCTAssertFalse(config.isTokenExpired)
    }

    /// Verifies APIKeyConfig with all optional fields.
    func test_apiKeyConfig_fullInit() {
        let config = APIKeyConfig(
            provider: .awsS3,
            apiKey: "AKIAIOSFODNN7EXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            refreshToken: nil,
            tokenExpiresAt: nil,
            region: "us-east-1",
            customEndpoint: "https://s3.us-east-1.amazonaws.com",
            label: "Production S3"
        )
        XCTAssertTrue(config.isValid)
        XCTAssertEqual(config.secretKey, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        XCTAssertEqual(config.region, "us-east-1")
        XCTAssertEqual(config.customEndpoint, "https://s3.us-east-1.amazonaws.com")
        XCTAssertEqual(config.label, "Production S3")
    }

    // MARK: - Phase 12: Extended Cloud Providers Tests

    // MARK: CloudFront

    /// Verifies CloudFront invalidation URL construction.
    func test_cloudFrontDistribution_invalidationURL() {
        let url = CloudFrontDistribution.buildInvalidationURL(distributionId: "E1A2B3C4D5")
        XCTAssertTrue(url.contains("cloudfront.amazonaws.com"))
        XCTAssertTrue(url.contains("E1A2B3C4D5/invalidation"))
    }

    /// Verifies CloudFront invalidation body XML.
    func test_cloudFrontDistribution_invalidationBody() {
        let body = CloudFrontDistribution.buildInvalidationBody(
            paths: ["/videos/*", "/thumbnails/*"],
            callerReference: "ref-123"
        )
        XCTAssertTrue(body.contains("<Quantity>2</Quantity>"))
        XCTAssertTrue(body.contains("<Path>/videos/*</Path>"))
        XCTAssertTrue(body.contains("<Path>/thumbnails/*</Path>"))
        XCTAssertTrue(body.contains("<CallerReference>ref-123</CallerReference>"))
    }

    /// Verifies CloudFront distribution URL.
    func test_cloudFrontDistribution_distributionURL() {
        let url = CloudFrontDistribution.buildDistributionURL(
            distributionDomain: "d12345.cloudfront.net",
            objectKey: "videos/movie.mp4"
        )
        XCTAssertEqual(url, "https://d12345.cloudfront.net/videos/movie.mp4")
    }

    // MARK: SharePoint

    /// Verifies SharePoint upload URL construction.
    func test_sharePointUploader_uploadURL() {
        let url = SharePointUploader.buildUploadURL(
            siteId: "site-abc",
            driveId: "drive-123",
            itemPath: "/Videos/movie.mp4"
        )
        XCTAssertTrue(url.contains("graph.microsoft.com/v1.0"))
        XCTAssertTrue(url.contains("sites/site-abc"))
        XCTAssertTrue(url.contains("drives/drive-123"))
        XCTAssertTrue(url.contains("/Videos/movie.mp4:/content"))
    }

    /// Verifies SharePoint upload session URL.
    func test_sharePointUploader_sessionURL() {
        let url = SharePointUploader.buildCreateSessionURL(
            siteId: "site-abc",
            driveId: "drive-123",
            itemPath: "/Videos/large.mp4"
        )
        XCTAssertTrue(url.contains("/createUploadSession"))
    }

    /// Verifies SharePoint upload headers.
    func test_sharePointUploader_headers() {
        let headers = SharePointUploader.buildUploadHeaders(
            accessToken: "eyJ_token",
            contentType: "video/mp4"
        )
        XCTAssertEqual(headers["Authorization"], "Bearer eyJ_token")
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
    }

    /// Verifies SharePoint constants.
    func test_sharePointUploader_constants() {
        XCTAssertEqual(SharePointUploader.simpleUploadMaxBytes, 4 * 1024 * 1024)
        XCTAssertEqual(SharePointUploader.fragmentSize, 10 * 1024 * 1024)
    }

    // MARK: iCloud Drive

    /// Verifies iCloud Drive container path construction.
    func test_iCloudDriveUploader_containerPath() {
        let path = ICloudDriveUploader.buildContainerPath(containerId: "iCloud.com.mwbm.MeedyaConverter")
        XCTAssertTrue(path.contains("Mobile Documents"))
        XCTAssertTrue(path.contains("iCloud.com.mwbm.MeedyaConverter"))
    }

    /// Verifies iCloud Drive document path.
    func test_iCloudDriveUploader_documentPath() {
        let path = ICloudDriveUploader.buildDocumentPath(
            containerId: "iCloud.com.mwbm.MeedyaConverter",
            relativePath: "Exports/movie.mp4"
        )
        XCTAssertTrue(path.contains("Documents/Exports/movie.mp4"))
    }

    /// Verifies default container ID.
    func test_iCloudDriveUploader_defaultContainerId() {
        XCTAssertEqual(ICloudDriveUploader.defaultContainerId, "iCloud.com.mwbm.MeedyaConverter")
    }

    // MARK: Mega

    /// Verifies Mega command URL construction.
    func test_megaUploader_commandURL() {
        let url = MegaUploader.buildCommandURL(sequenceNumber: 42)
        XCTAssertTrue(url.contains("g.api.mega.co.nz/cs"))
        XCTAssertTrue(url.contains("id=42"))
    }

    /// Verifies Mega upload request command.
    func test_megaUploader_uploadRequest() {
        let cmd = MegaUploader.buildUploadRequestCommand(fileSize: 50_000_000)
        XCTAssertTrue(cmd.contains("\"a\":\"u\""))
        XCTAssertTrue(cmd.contains("\"s\":50000000"))
    }

    /// Verifies Mega chunk size progression.
    func test_megaUploader_chunkSizes() {
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 0), 128 * 1024)
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 1), 256 * 1024)
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 2), 512 * 1024)
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 3), 1024 * 1024)
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 10), 1024 * 1024)
    }

    // MARK: Mux

    /// Verifies Mux direct upload URL.
    func test_muxUploader_directUploadURL() {
        let url = MuxUploader.buildCreateDirectUploadURL()
        XCTAssertTrue(url.contains("api.mux.com/video/v1/uploads"))
    }

    /// Verifies Mux asset URL.
    func test_muxUploader_assetURL() {
        let url = MuxUploader.buildAssetURL(assetId: "asset_abc123")
        XCTAssertTrue(url.contains("video/v1/assets/asset_abc123"))
    }

    /// Verifies Mux headers with Basic auth.
    func test_muxUploader_headers() {
        let headers = MuxUploader.buildHeaders(
            tokenId: "tok_id",
            tokenSecret: "tok_secret"
        )
        XCTAssertTrue(headers["Authorization"]!.hasPrefix("Basic "))
        XCTAssertEqual(headers["Content-Type"], "application/json")
    }

    /// Verifies Mux playback URL construction.
    func test_muxUploader_playbackURL() {
        let url = MuxUploader.buildPlaybackURL(playbackId: "play_abc")
        XCTAssertEqual(url, "https://stream.mux.com/play_abc.m3u8")
    }

    /// Verifies Mux thumbnail URL.
    func test_muxUploader_thumbnailURL() {
        let url = MuxUploader.buildThumbnailURL(playbackId: "play_abc", width: 320, time: 5.0)
        XCTAssertTrue(url.contains("image.mux.com/play_abc"))
        XCTAssertTrue(url.contains("width=320"))
        XCTAssertTrue(url.contains("time=5.0"))
    }

    /// Verifies Mux direct upload body.
    func test_muxUploader_directUploadBody() {
        let body = MuxUploader.buildDirectUploadBody(
            corsOrigin: "https://app.example.com",
            playbackPolicy: "signed",
            mp4Support: true
        )
        XCTAssertTrue(body.contains("https://app.example.com"))
        XCTAssertTrue(body.contains("\"signed\""))
        XCTAssertTrue(body.contains("mp4_support"))
    }

    // MARK: Akamai

    /// Verifies Akamai NetStorage upload URL.
    func test_akamaiNetStorageUploader_uploadURL() {
        let url = AkamaiNetStorageUploader.buildUploadURL(
            hostname: "example-nsu.akamaihd.net",
            cpCode: "123456",
            remotePath: "videos/movie.mp4"
        )
        XCTAssertEqual(url, "https://example-nsu.akamaihd.net/123456/videos/movie.mp4")
    }

    /// Verifies Akamai action header.
    func test_akamaiNetStorageUploader_actionHeader() {
        let header = AkamaiNetStorageUploader.buildActionHeader(action: "upload", version: 1)
        XCTAssertEqual(header, "version=1&action=upload")
    }

    /// Verifies Akamai upload headers.
    func test_akamaiNetStorageUploader_headers() {
        let headers = AkamaiNetStorageUploader.buildUploadHeaders(
            authData: "5, 0.0.0.0, 0.0.0.0, 1234, nonce, key",
            authSign: "hmac_signature",
            action: "version=1&action=upload",
            contentType: "video/mp4"
        )
        XCTAssertEqual(headers["X-Akamai-ACS-Auth-Data"], "5, 0.0.0.0, 0.0.0.0, 1234, nonce, key")
        XCTAssertEqual(headers["X-Akamai-ACS-Auth-Sign"], "hmac_signature")
        XCTAssertEqual(headers["X-Akamai-ACS-Action"], "version=1&action=upload")
    }

    // MARK: Backblaze B2

    /// Verifies Backblaze B2 authorization header.
    func test_backblazeB2Uploader_authHeader() {
        let header = BackblazeB2Uploader.buildAuthorizationHeader(
            keyId: "app_key_id",
            applicationKey: "app_key"
        )
        XCTAssertTrue(header.hasPrefix("Basic "))
    }

    /// Verifies Backblaze B2 upload headers.
    func test_backblazeB2Uploader_uploadHeaders() {
        let headers = BackblazeB2Uploader.buildUploadHeaders(
            authorizationToken: "auth_tok",
            filename: "video.mp4",
            contentType: "video/mp4",
            sha1: "abc123"
        )
        XCTAssertEqual(headers["Authorization"], "auth_tok")
        XCTAssertEqual(headers["X-Bz-Content-Sha1"], "abc123")
        XCTAssertNotNil(headers["X-Bz-File-Name"])
    }

    /// Verifies Backblaze B2 constants.
    func test_backblazeB2Uploader_constants() {
        XCTAssertEqual(BackblazeB2Uploader.minimumPartSize, 5 * 1024 * 1024)
        XCTAssertEqual(BackblazeB2Uploader.recommendedPartSize, 100 * 1024 * 1024)
    }

}
