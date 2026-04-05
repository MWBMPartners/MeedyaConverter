// ============================================================================
// MeedyaConverter — VideoUploader
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides request builders for uploading encoded video files directly to
// YouTube and Vimeo from within MeedyaConverter.
//
// Features:
//   - YouTube Data API v3 resumable upload request construction.
//   - Vimeo API tus-based upload request construction.
//   - OAuth 2.0 authorization URL generation for both services.
//   - Codable configuration for upload metadata (title, description, tags,
//     privacy level).
//   - Fully Sendable and stateless (struct with static methods).
//
// Phase 11 — YouTube/Vimeo Direct Upload (Issue #294)
// ---------------------------------------------------------------------------

import Foundation

// MARK: - VideoService

/// Supported video hosting services for direct upload.
public enum VideoService: String, Codable, Sendable, CaseIterable {
    /// YouTube via the Data API v3.
    case youtube
    /// Vimeo via the Vimeo API.
    case vimeo

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .vimeo: return "Vimeo"
        }
    }
}

// MARK: - VideoPrivacy

/// Privacy / visibility level for an uploaded video.
public enum VideoPrivacy: String, Codable, Sendable, CaseIterable {
    /// Publicly listed and searchable.
    case `public`
    /// Accessible only via direct link.
    case unlisted
    /// Visible only to the uploader.
    case `private`

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .public: return "Public"
        case .unlisted: return "Unlisted"
        case .private: return "Private"
        }
    }
}

// MARK: - VideoUploadConfig

/// Configuration describing the metadata and destination for a video upload.
///
/// Includes the target service, video metadata (title, description, tags),
/// privacy setting, and the OAuth access token for authentication.
public struct VideoUploadConfig: Codable, Sendable {

    // MARK: - Properties

    /// The video hosting service to upload to.
    public var service: VideoService

    /// Title of the video.
    public var title: String

    /// Description of the video.
    public var description: String

    /// Tags / keywords for the video.
    public var tags: [String]

    /// Privacy / visibility setting.
    public var privacy: VideoPrivacy

    /// OAuth 2.0 access token for authenticating with the service API.
    public var accessToken: String

    // MARK: - Initialiser

    /// Creates a new video upload configuration.
    ///
    /// - Parameters:
    ///   - service: Target video hosting service.
    ///   - title: Video title.
    ///   - description: Video description.
    ///   - tags: Tags / keywords.
    ///   - privacy: Visibility level.
    ///   - accessToken: OAuth access token.
    public init(
        service: VideoService,
        title: String,
        description: String = "",
        tags: [String] = [],
        privacy: VideoPrivacy = .private,
        accessToken: String
    ) {
        self.service = service
        self.title = title
        self.description = description
        self.tags = tags
        self.privacy = privacy
        self.accessToken = accessToken
    }
}

// MARK: - VideoUploadHistory

/// A record of a completed (or attempted) video upload.
public struct VideoUploadHistory: Identifiable, Codable, Sendable {

    /// Unique identifier for this history entry.
    public let id: UUID

    /// The file that was uploaded.
    public var filePath: String

    /// The service it was uploaded to.
    public var service: VideoService

    /// Title used for the upload.
    public var title: String

    /// Timestamp of the upload attempt.
    public var uploadedAt: Date

    /// Whether the upload was successful.
    public var success: Bool

    /// Remote video URL if available.
    public var remoteURL: String?

    /// Error message if the upload failed.
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        filePath: String,
        service: VideoService,
        title: String,
        uploadedAt: Date = Date(),
        success: Bool,
        remoteURL: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.service = service
        self.title = title
        self.uploadedAt = uploadedAt
        self.success = success
        self.remoteURL = remoteURL
        self.errorMessage = errorMessage
    }
}

// MARK: - VideoUploader

/// Stateless utility for building upload requests to YouTube and Vimeo.
///
/// All methods are `static` so callers do not need to create an instance.
/// The struct itself is `Sendable` as it holds no mutable state.
///
/// ### YouTube Upload Flow
/// 1. Build a resumable upload initiation request via
///    ``buildYouTubeUploadRequest(filePath:config:)``.
/// 2. Send the request to receive an upload URI in the `Location` header.
/// 3. PUT the video bytes to that URI in one or more chunks.
///
/// ### Vimeo Upload Flow
/// 1. Build a tus-compatible upload creation request via
///    ``buildVimeoUploadRequest(filePath:config:)``.
/// 2. Send the request to receive the tus upload link.
/// 3. PATCH the video bytes to the tus endpoint.
public struct VideoUploader: Sendable {

    // MARK: - YouTube

    /// Builds a YouTube Data API v3 resumable upload initiation request.
    ///
    /// The returned `URLRequest` initiates a resumable upload session.
    /// After sending this request, the response `Location` header contains
    /// the upload URI to which the actual video bytes should be PUT.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the video file on disk.
    ///   - config: Upload configuration with metadata and auth token.
    /// - Returns: A configured `URLRequest`, or `nil` if the file cannot
    ///   be read or the URL cannot be constructed.
    public static func buildYouTubeUploadRequest(
        filePath: String,
        config: VideoUploadConfig
    ) -> URLRequest? {
        guard let fileSize = try? FileManager.default.attributesOfItem(
            atPath: filePath
        )[.size] as? Int64 else {
            return nil
        }

        // YouTube resumable upload endpoint.
        guard var components = URLComponents(
            string: "https://www.googleapis.com/upload/youtube/v3/videos"
        ) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "part", value: "snippet,status")
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(config.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            String(fileSize),
            forHTTPHeaderField: "X-Upload-Content-Length"
        )
        request.setValue(
            "video/*",
            forHTTPHeaderField: "X-Upload-Content-Type"
        )

        // Build the JSON metadata body.
        let metadata: [String: Any] = [
            "snippet": [
                "title": config.title,
                "description": config.description,
                "tags": config.tags
            ],
            "status": [
                "privacyStatus": config.privacy.rawValue
            ]
        ]

        request.httpBody = try? JSONSerialization.data(
            withJSONObject: metadata,
            options: []
        )

        return request
    }

    /// Generates the OAuth 2.0 authorisation URL for YouTube.
    ///
    /// Opens this URL in the user's browser to begin the OAuth flow.
    /// After approval, Google redirects to the `redirectURI` with an
    /// authorisation code that can be exchanged for an access token.
    ///
    /// - Parameters:
    ///   - clientId: The OAuth client ID from Google Cloud Console.
    ///   - redirectURI: The redirect URI registered for the app.
    /// - Returns: The fully-constructed authorisation URL.
    public static func youtubeAuthURL(
        clientId: String,
        redirectURI: String
    ) -> URL {
        var components = URLComponents(
            string: "https://accounts.google.com/o/oauth2/v2/auth"
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope",
                value: "https://www.googleapis.com/auth/youtube.upload"
            ),
            URLQueryItem(name: "access_type", value: "offline")
        ]
        return components.url!
    }

    // MARK: - Vimeo

    /// Builds a Vimeo API tus upload creation request.
    ///
    /// The returned `URLRequest` creates a new video resource and initiates
    /// a tus-based upload. After sending this request, the response contains
    /// the `upload.upload_link` to which video bytes are PATCHed.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the video file on disk.
    ///   - config: Upload configuration with metadata and auth token.
    /// - Returns: A configured `URLRequest`, or `nil` if the file cannot
    ///   be read.
    public static func buildVimeoUploadRequest(
        filePath: String,
        config: VideoUploadConfig
    ) -> URLRequest? {
        guard let fileSize = try? FileManager.default.attributesOfItem(
            atPath: filePath
        )[.size] as? Int64 else {
            return nil
        }

        guard let url = URL(string: "https://api.vimeo.com/me/videos") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "bearer \(config.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("3.4", forHTTPHeaderField: "Accept")

        // Vimeo privacy mapping.
        let vimeoPrivacy: String
        switch config.privacy {
        case .public:   vimeoPrivacy = "anybody"
        case .unlisted: vimeoPrivacy = "unlisted"
        case .private:  vimeoPrivacy = "nobody"
        }

        let body: [String: Any] = [
            "upload": [
                "approach": "tus",
                "size": String(fileSize)
            ],
            "name": config.title,
            "description": config.description,
            "privacy": [
                "view": vimeoPrivacy
            ]
        ]

        request.httpBody = try? JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

        return request
    }

    /// Generates the OAuth 2.0 authorisation URL for Vimeo.
    ///
    /// Opens this URL in the user's browser to begin the OAuth flow.
    /// After approval, Vimeo redirects to the `redirectURI` with an
    /// authorisation code.
    ///
    /// - Parameters:
    ///   - clientId: The OAuth client ID from the Vimeo developer console.
    ///   - redirectURI: The redirect URI registered for the app.
    /// - Returns: The fully-constructed authorisation URL.
    public static func vimeoAuthURL(
        clientId: String,
        redirectURI: String
    ) -> URL {
        var components = URLComponents(
            string: "https://api.vimeo.com/oauth/authorize"
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "upload")
        ]
        return components.url!
    }
}
