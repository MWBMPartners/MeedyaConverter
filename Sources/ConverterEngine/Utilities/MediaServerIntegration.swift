// ============================================================================
// MeedyaConverter — MediaServerIntegration (Issue #295)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MediaServerIntegration

/// High-level media server integration utilities that complement the
/// lower-level `MediaServerNotifier`.
///
/// Provides convenience methods for triggering library scans (with
/// throwing semantics), testing connections, and listing available
/// libraries from Plex, Jellyfin, and Emby servers.
///
/// Unlike `MediaServerNotifier.sendLibraryScan` which returns a
/// `NotificationResult`, these methods throw on failure for simpler
/// error handling in UI code.
///
/// Phase 17 — Post-Encode Hooks (Issue #295)
public struct MediaServerIntegration: Sendable {

    // MARK: - Errors

    /// Errors that can occur during media server communication.
    public enum MediaServerError: LocalizedError, Sendable {
        /// The server returned a non-success HTTP status code.
        case httpError(statusCode: Int)
        /// The server's response could not be parsed.
        case invalidResponse
        /// The server URL or constructed endpoint is malformed.
        case invalidURL
        /// Connection test failed.
        case connectionFailed(reason: String)

        public var errorDescription: String? {
            switch self {
            case .httpError(let code):
                return "Media server returned HTTP \(code)."
            case .invalidResponse:
                return "The media server returned an unexpected response."
            case .invalidURL:
                return "The media server URL is invalid."
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            }
        }
    }

    // MARK: - Library Scan (Throwing)

    /// Trigger a library scan on the configured media server.
    ///
    /// Delegates to `MediaServerNotifier.sendLibraryScan` but converts
    /// the result-based API into throwing semantics for simpler UI usage.
    ///
    /// - Parameter config: The media server configuration.
    /// - Throws: `MediaServerError` on failure.
    public static func triggerLibraryScan(config: MediaServerConfig) async throws {
        let result = await MediaServerNotifier.sendLibraryScan(config: config)
        guard result.success else {
            throw MediaServerError.connectionFailed(
                reason: result.errorMessage ?? "Unknown error"
            )
        }
    }

    // MARK: - Test Connection (Throwing)

    /// Test connectivity to the configured media server.
    ///
    /// Delegates to `MediaServerNotifier.testConnection` but provides
    /// throwing semantics on failure for easier UI error handling.
    ///
    /// - Parameter config: The media server configuration.
    /// - Returns: `true` if the server responds with a 2xx status.
    /// - Throws: `MediaServerError.connectionFailed` if the test fails.
    public static func testConnection(config: MediaServerConfig) async throws -> Bool {
        let reachable = await MediaServerNotifier.testConnection(config: config)
        guard reachable else {
            throw MediaServerError.connectionFailed(
                reason: "Server did not respond successfully."
            )
        }
        return true
    }

    // MARK: - List Libraries

    /// Retrieve the list of available libraries from the media server.
    ///
    /// - **Plex:** `GET /library/sections` with `X-Plex-Token` header
    ///   and `Accept: application/json`. Parses the JSON response to
    ///   extract section key and title.
    /// - **Jellyfin / Emby:** `GET /Library/VirtualFolders` with
    ///   `X-Emby-Token` header. Parses the JSON response to extract
    ///   folder ItemId and Name.
    ///
    /// - Parameter config: The media server configuration.
    /// - Returns: An array of `(id, name)` tuples for each library.
    /// - Throws: `MediaServerError` on failure.
    public static func listLibraries(config: MediaServerConfig) async throws -> [(id: String, name: String)] {
        switch config.serverType {
        case .plex:
            return try await listPlexLibraries(config: config)
        case .jellyfin, .emby:
            return try await listJellyfinLibraries(config: config)
        }
    }

    // MARK: - Private: Plex Libraries

    /// Fetch Plex library sections via the Plex API.
    ///
    /// Requests JSON format via the `Accept` header for easier parsing.
    ///
    /// - Parameter config: The media server configuration.
    /// - Returns: An array of `(id, name)` tuples.
    private static func listPlexLibraries(config: MediaServerConfig) async throws -> [(id: String, name: String)] {
        guard let url = URL(string: "\(config.baseURL)/library/sections") else {
            throw MediaServerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-Plex-Token")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MediaServerError.httpError(statusCode: code)
        }

        // Parse Plex JSON: { "MediaContainer": { "Directory": [{ "key": "1", "title": "Movies" }] } }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let container = json["MediaContainer"] as? [String: Any],
              let directories = container["Directory"] as? [[String: Any]] else {
            throw MediaServerError.invalidResponse
        }

        return directories.compactMap { dir in
            guard let key = dir["key"] as? String,
                  let title = dir["title"] as? String else {
                return nil
            }
            return (id: key, name: title)
        }
    }

    // MARK: - Private: Jellyfin / Emby Libraries

    /// Fetch Jellyfin or Emby library folders via their shared API.
    ///
    /// - Parameter config: The media server configuration.
    /// - Returns: An array of `(id, name)` tuples.
    private static func listJellyfinLibraries(config: MediaServerConfig) async throws -> [(id: String, name: String)] {
        guard let url = URL(string: "\(config.baseURL)/Library/VirtualFolders") else {
            throw MediaServerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(config.apiKey, forHTTPHeaderField: "X-Emby-Token")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MediaServerError.httpError(statusCode: code)
        }

        // Parse Jellyfin/Emby JSON: [{ "ItemId": "abc", "Name": "Movies" }]
        guard let folders = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MediaServerError.invalidResponse
        }

        return folders.compactMap { folder in
            guard let itemId = folder["ItemId"] as? String,
                  let name = folder["Name"] as? String else {
                return nil
            }
            return (id: itemId, name: name)
        }
    }
}
