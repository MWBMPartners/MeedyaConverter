// ============================================================================
// MeedyaConverter — MediaServerNotifier
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MediaServerType

/// Supported media server types for post-encode notifications.
public enum MediaServerType: String, Codable, Sendable, CaseIterable {
    case plex
    case jellyfin
    case emby

    /// Display name.
    public var displayName: String {
        switch self {
        case .plex: return "Plex"
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
        }
    }

    /// Default API port.
    public var defaultPort: Int {
        switch self {
        case .plex: return 32400
        case .jellyfin: return 8096
        case .emby: return 8096
        }
    }
}

// MARK: - MediaServerConfig

/// Configuration for connecting to a media server instance.
public struct MediaServerConfig: Codable, Sendable, Identifiable {
    public let id: UUID
    public var serverType: MediaServerType
    public var displayName: String
    public var host: String
    public var port: Int
    public var apiKey: String
    public var useTLS: Bool
    public var libraryID: String?
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        serverType: MediaServerType,
        displayName: String,
        host: String = "localhost",
        port: Int? = nil,
        apiKey: String,
        useTLS: Bool = false,
        libraryID: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.serverType = serverType
        self.displayName = displayName
        self.host = host
        self.port = port ?? serverType.defaultPort
        self.apiKey = apiKey
        self.useTLS = useTLS
        self.libraryID = libraryID
        self.enabled = enabled
    }

    /// Base URL for API requests.
    public var baseURL: String {
        let scheme = useTLS ? "https" : "http"
        return "\(scheme)://\(host):\(port)"
    }
}

// MARK: - NotificationEvent

/// Events that can trigger media server notifications.
public enum NotificationEvent: String, Codable, Sendable {
    case encodingCompleted = "encoding_completed"
    case encodingFailed = "encoding_failed"
    case queueCompleted = "queue_completed"
    case libraryRefreshRequested = "library_refresh"
}

// MARK: - NotificationResult

/// Result of a media server notification attempt.
public struct NotificationResult: Sendable {
    public let server: MediaServerConfig
    public let event: NotificationEvent
    public let success: Bool
    public let statusCode: Int?
    public let errorMessage: String?
    public let timestamp: Date

    public init(
        server: MediaServerConfig,
        event: NotificationEvent,
        success: Bool,
        statusCode: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.server = server
        self.event = event
        self.success = success
        self.statusCode = statusCode
        self.errorMessage = errorMessage
        self.timestamp = Date()
    }
}

// MARK: - MediaServerNotifier

/// Sends post-encode notifications to media servers (Plex, Jellyfin, Emby).
///
/// Supports library scan triggers and webhook notifications after encoding
/// jobs complete, enabling automatic media library updates.
///
/// Phase 7.19
public struct MediaServerNotifier: Sendable {

    // MARK: - URL Building

    /// Build the library scan URL for a Plex server.
    ///
    /// - Parameters:
    ///   - config: Plex server configuration.
    ///   - librarySection: Optional specific library section ID to scan.
    /// - Returns: The scan URL and HTTP method.
    public static func buildPlexScanURL(
        config: MediaServerConfig,
        librarySection: String? = nil
    ) -> (url: String, method: String, headers: [String: String]) {
        let section = librarySection ?? config.libraryID
        let path: String
        if let sec = section {
            path = "/library/sections/\(sec)/refresh"
        } else {
            path = "/library/sections/all/refresh"
        }
        return (
            url: "\(config.baseURL)\(path)",
            method: "GET",
            headers: ["X-Plex-Token": config.apiKey]
        )
    }

    /// Build the library scan URL for a Jellyfin server.
    ///
    /// - Parameter config: Jellyfin server configuration.
    /// - Returns: The scan URL, HTTP method, and headers.
    public static func buildJellyfinScanURL(
        config: MediaServerConfig
    ) -> (url: String, method: String, headers: [String: String]) {
        let path = "/Library/Refresh"
        return (
            url: "\(config.baseURL)\(path)",
            method: "POST",
            headers: [
                "X-Emby-Token": config.apiKey,
                "Content-Type": "application/json",
            ]
        )
    }

    /// Build the library scan URL for an Emby server.
    ///
    /// - Parameter config: Emby server configuration.
    /// - Returns: The scan URL, HTTP method, and headers.
    public static func buildEmbyScanURL(
        config: MediaServerConfig
    ) -> (url: String, method: String, headers: [String: String]) {
        let path = "/Library/Refresh"
        return (
            url: "\(config.baseURL)\(path)",
            method: "POST",
            headers: [
                "X-Emby-Token": config.apiKey,
                "Content-Type": "application/json",
            ]
        )
    }

    /// Build the appropriate library scan request for a media server.
    ///
    /// - Parameter config: Server configuration.
    /// - Returns: A URLRequest for the library scan endpoint.
    public static func buildScanRequest(config: MediaServerConfig) -> URLRequest? {
        let info: (url: String, method: String, headers: [String: String])

        switch config.serverType {
        case .plex:
            info = buildPlexScanURL(config: config)
        case .jellyfin:
            info = buildJellyfinScanURL(config: config)
        case .emby:
            info = buildEmbyScanURL(config: config)
        }

        guard let url = URL(string: info.url) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = info.method
        request.timeoutInterval = 30
        for (key, value) in info.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    // MARK: - Notification Sending

    /// Send a library scan notification to a media server.
    ///
    /// - Parameter config: Server configuration.
    /// - Returns: The result of the notification attempt.
    public static func sendLibraryScan(
        config: MediaServerConfig
    ) async -> NotificationResult {
        guard config.enabled else {
            return NotificationResult(
                server: config,
                event: .libraryRefreshRequested,
                success: false,
                errorMessage: "Server is disabled"
            )
        }

        guard let request = buildScanRequest(config: config) else {
            return NotificationResult(
                server: config,
                event: .libraryRefreshRequested,
                success: false,
                errorMessage: "Invalid server URL: \(config.baseURL)"
            )
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            let success = (200..<300).contains(statusCode)

            return NotificationResult(
                server: config,
                event: .libraryRefreshRequested,
                success: success,
                statusCode: statusCode,
                errorMessage: success ? nil : "HTTP \(statusCode)"
            )
        } catch {
            return NotificationResult(
                server: config,
                event: .libraryRefreshRequested,
                success: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    /// Send library scan notifications to all configured servers.
    ///
    /// - Parameter configs: Array of server configurations.
    /// - Returns: Results for each server.
    public static func sendLibraryScanToAll(
        configs: [MediaServerConfig]
    ) async -> [NotificationResult] {
        let enabledConfigs = configs.filter(\.enabled)
        guard !enabledConfigs.isEmpty else { return [] }

        return await withTaskGroup(of: NotificationResult.self) { group in
            for config in enabledConfigs {
                group.addTask {
                    await sendLibraryScan(config: config)
                }
            }

            var results: [NotificationResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    // MARK: - Webhook Support

    /// Build a generic webhook payload for an encoding event.
    ///
    /// - Parameters:
    ///   - event: The notification event type.
    ///   - jobName: Name/identifier of the encoding job.
    ///   - inputFile: Input file path.
    ///   - outputFile: Output file path.
    ///   - duration: Encoding duration in seconds.
    ///   - fileSize: Output file size in bytes.
    /// - Returns: JSON-encoded webhook payload data.
    public static func buildWebhookPayload(
        event: NotificationEvent,
        jobName: String,
        inputFile: String,
        outputFile: String,
        duration: TimeInterval? = nil,
        fileSize: Int64? = nil
    ) -> Data? {
        var payload: [String: Any] = [
            "event": event.rawValue,
            "job_name": jobName,
            "input_file": inputFile,
            "output_file": outputFile,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "engine_version": ConverterEngine.version,
        ]

        if let dur = duration {
            payload["encoding_duration_seconds"] = dur
        }
        if let size = fileSize {
            payload["output_file_size_bytes"] = size
        }

        return try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    /// Send a webhook notification to a custom URL.
    ///
    /// - Parameters:
    ///   - url: Webhook endpoint URL.
    ///   - payload: JSON payload data.
    ///   - headers: Optional custom HTTP headers.
    /// - Returns: HTTP status code, or nil on failure.
    public static func sendWebhook(
        url: URL,
        payload: Data,
        headers: [String: String] = [:]
    ) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConverterEngine.buildIdentifier, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    // MARK: - Server Validation

    /// Test connectivity to a media server.
    ///
    /// - Parameter config: Server configuration to test.
    /// - Returns: `true` if the server responds successfully.
    public static func testConnection(
        config: MediaServerConfig
    ) async -> Bool {
        let testURL: String
        let headers: [String: String]

        switch config.serverType {
        case .plex:
            testURL = "\(config.baseURL)/identity"
            headers = ["X-Plex-Token": config.apiKey]
        case .jellyfin:
            testURL = "\(config.baseURL)/System/Info/Public"
            headers = ["X-Emby-Token": config.apiKey]
        case .emby:
            testURL = "\(config.baseURL)/System/Info/Public"
            headers = ["X-Emby-Token": config.apiKey]
        }

        guard let url = URL(string: testURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(status)
        } catch {
            return false
        }
    }
}

// MARK: - MediaServerConfigStore

/// Persists media server configurations to disk.
///
/// Stores server connection details as JSON in the app's configuration
/// directory alongside encoding profiles.
public final class MediaServerConfigStore: @unchecked Sendable {
    private var configs: [MediaServerConfig] = []
    private let lock = NSLock()
    private let storageURL: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MeedyaConverter/Servers")
        self.storageURL = dir.appendingPathComponent("media_servers.json")
        loadConfigs()
    }

    /// All configured servers.
    public var allConfigs: [MediaServerConfig] {
        lock.lock()
        defer { lock.unlock() }
        return configs
    }

    /// Enabled servers only.
    public var enabledConfigs: [MediaServerConfig] {
        allConfigs.filter(\.enabled)
    }

    /// Add a server configuration.
    public func addConfig(_ config: MediaServerConfig) {
        lock.lock()
        configs.append(config)
        lock.unlock()
        saveConfigs()
    }

    /// Update an existing configuration.
    public func updateConfig(_ config: MediaServerConfig) {
        lock.lock()
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        }
        lock.unlock()
        saveConfigs()
    }

    /// Remove a configuration.
    public func removeConfig(id: UUID) {
        lock.lock()
        configs.removeAll { $0.id == id }
        lock.unlock()
        saveConfigs()
    }

    /// Export configurations as JSON data.
    public func exportAsJSON() throws -> Data {
        lock.lock()
        let current = configs
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(current)
    }

    /// Import configurations from JSON data.
    public func importFromJSON(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let imported = try decoder.decode([MediaServerConfig].self, from: data)
        lock.lock()
        let existingIDs = Set(configs.map(\.id))
        let newConfigs = imported.filter { !existingIDs.contains($0.id) }
        configs.append(contentsOf: newConfigs)
        lock.unlock()
        saveConfigs()
        return newConfigs.count
    }

    // MARK: - Persistence

    private func loadConfigs() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            lock.lock()
            configs = try decoder.decode([MediaServerConfig].self, from: data)
            lock.unlock()
        } catch {
            // Silently ignore corrupt config files
        }
    }

    private func saveConfigs() {
        lock.lock()
        let current = configs
        lock.unlock()

        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(current)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Persistence failure is non-fatal
        }
    }
}
