// ============================================================================
// MeedyaConverter — AnalyticsEngine
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - AnalyticsEventType

/// Predefined analytics event types.
///
/// Each event captures a single, anonymised user action. No PII
/// (file names, file paths, user data, IP addresses) is ever attached
/// to any event.
public enum AnalyticsEventType: String, Codable, Sendable {
    /// Application launched.
    case appLaunch = "app_launch"
    /// An encoding job started (codec + container only, never file names).
    case encodeStart = "encode_start"
    /// An encoding job completed successfully.
    case encodeComplete = "encode_complete"
    /// An encoding job failed.
    case encodeFailed = "encode_failed"
    /// A built-in encoding profile was selected.
    case profileUsed = "profile_used"
    /// A specific feature was exercised.
    case featureUsed = "feature_used"
    /// A video/audio codec was selected.
    case codecUsed = "codec_used"
    /// A container format was selected.
    case containerUsed = "container_used"
}

// MARK: - AnalyticsEvent

/// A single analytics event queued for eventual upload.
///
/// Events are anonymous: they contain no file names, paths, or PII.
/// The ``sessionId`` groups events within a single app run; the
/// ``anonymousId`` (from ``AnalyticsConfig``) is a random UUID that
/// the user can reset or delete at any time.
public struct AnalyticsEvent: Codable, Sendable {
    /// The event type name (raw value of ``AnalyticsEventType``).
    public let name: String
    /// Arbitrary key-value properties (codec, container, duration category, etc.).
    public let properties: [String: String]
    /// When the event occurred.
    public let timestamp: Date
    /// Identifies the current app session.
    public let sessionId: UUID
}

// MARK: - AnalyticsConfig

/// Persisted analytics configuration.
///
/// Stored in ``UserDefaults`` with the `analytics_` key prefix.
/// ``enabled`` defaults to `false` — analytics is strictly opt-in.
public struct AnalyticsConfig: Codable, Sendable {
    /// Whether analytics collection is enabled. Defaults to `false` (opt-in).
    public var enabled: Bool
    /// A randomly generated anonymous identifier. Contains no PII.
    /// Persisted so the same device can be recognised across sessions
    /// without collecting any personal information.
    public var anonymousId: UUID
    /// Optional remote endpoint for batch upload. When `nil`, events
    /// are stored locally only.
    public var endpointURL: URL?

    /// Create a default (disabled) configuration with a fresh anonymous ID.
    public init() {
        self.enabled = false
        self.anonymousId = UUID()
        self.endpointURL = nil
    }
}

// MARK: - AnalyticsEngine

/// Privacy-respecting, opt-in analytics engine.
///
/// Collects anonymous usage events (codec choices, encode durations,
/// feature usage) to help improve MeedyaConverter. The engine is
/// **disabled by default** and collects **zero data** until the user
/// explicitly opts in from Settings > Analytics.
///
/// Guarantees:
/// - No PII is ever collected (no file names, paths, user data, IPs).
/// - All data can be exported (``exportCollectedData()``) or deleted
///   (``deleteAllData()``) at any time (GDPR compliance).
/// - Thread-safe via ``NSLock``.
/// - Events are persisted to a local JSON file in Application Support
///   and batch-uploaded periodically when an endpoint is configured.
///
/// Phase 12 — Analytics Integration (Issue #183)
public final class AnalyticsEngine: @unchecked Sendable {

    // MARK: - Constants

    /// UserDefaults key prefix for all analytics settings.
    private static let keyPrefix = "analytics_"

    /// UserDefaults key for the ``enabled`` flag.
    private static let enabledKey = "\(keyPrefix)enabled"

    /// UserDefaults key for the persisted anonymous ID.
    private static let anonymousIdKey = "\(keyPrefix)anonymousId"

    /// UserDefaults key for the endpoint URL.
    private static let endpointURLKey = "\(keyPrefix)endpointURL"

    /// File name for the persisted event queue.
    private static let queueFileName = "analytics_events.json"

    /// Batch upload interval in seconds (5 minutes).
    private static let uploadInterval: TimeInterval = 300

    // MARK: - Properties

    /// Lock for thread-safe access to mutable state.
    private let lock = NSLock()

    /// The current analytics configuration, mirrored to UserDefaults.
    private var config: AnalyticsConfig

    /// In-memory event queue, persisted to disk on every append.
    private var eventQueue: [AnalyticsEvent] = []

    /// Session identifier for the current app run.
    private let sessionId = UUID()

    /// Path to the JSON file storing queued events.
    private let queueFileURL: URL

    /// Timer for periodic batch upload.
    private var uploadTimer: Timer?

    // MARK: - Public API

    /// Whether analytics collection is currently enabled.
    ///
    /// When `false`, ``track(_:properties:)`` is a complete no-op:
    /// no events are queued, no data is written to disk, no network
    /// calls are made.
    public var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return config.enabled
    }

    /// The anonymous identifier for this installation.
    ///
    /// Users can view this in Settings > Analytics to reference it
    /// in data-deletion requests.
    public var anonymousId: UUID {
        lock.lock()
        defer { lock.unlock() }
        return config.anonymousId
    }

    /// The number of events currently queued.
    public var queuedEventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return eventQueue.count
    }

    // MARK: - Initialiser

    /// Create a new AnalyticsEngine, loading persisted config and events.
    ///
    /// The engine is disabled by default. No data is collected until
    /// ``setEnabled(_:)`` is called with `true`.
    public init() {
        // Determine the events file path in Application Support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("MeedyaConverter", isDirectory: true)

        // Ensure the directory exists
        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        self.queueFileURL = appSupport.appendingPathComponent(Self.queueFileName)

        // Load config from UserDefaults
        var loadedConfig = AnalyticsConfig()
        let defaults = UserDefaults.standard

        loadedConfig.enabled = defaults.bool(forKey: Self.enabledKey)

        if let idString = defaults.string(forKey: Self.anonymousIdKey),
           let id = UUID(uuidString: idString) {
            loadedConfig.anonymousId = id
        } else {
            // First launch — persist the generated anonymous ID
            defaults.set(loadedConfig.anonymousId.uuidString, forKey: Self.anonymousIdKey)
        }

        if let urlString = defaults.string(forKey: Self.endpointURLKey),
           let url = URL(string: urlString) {
            loadedConfig.endpointURL = url
        }

        self.config = loadedConfig

        // Load persisted event queue
        self.eventQueue = Self.loadEvents(from: queueFileURL)

        // Start upload timer if enabled
        if config.enabled {
            startUploadTimer()
        }
    }

    // MARK: - Enable / Disable

    /// Enable or disable analytics collection.
    ///
    /// When disabled, all pending events remain on disk but no new
    /// events are recorded and no uploads occur.
    ///
    /// - Parameter enabled: `true` to opt in, `false` to opt out.
    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        config.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        lock.unlock()

        if enabled {
            startUploadTimer()
        } else {
            stopUploadTimer()
        }
    }

    // MARK: - Tracking

    /// Record an analytics event.
    ///
    /// If analytics is disabled, this method is a complete no-op.
    /// Properties must **never** contain PII (file names, paths, user data).
    ///
    /// - Parameters:
    ///   - eventType: The type of event to record.
    ///   - properties: Optional key-value metadata (e.g. `["codec": "h265"]`).
    public func track(_ eventType: AnalyticsEventType, properties: [String: String] = [:]) {
        lock.lock()
        guard config.enabled else {
            lock.unlock()
            return
        }

        let event = AnalyticsEvent(
            name: eventType.rawValue,
            properties: properties,
            timestamp: Date(),
            sessionId: sessionId
        )

        eventQueue.append(event)
        let events = eventQueue
        lock.unlock()

        // Persist to disk (off the lock to avoid holding it during I/O)
        persistEvents(events)
    }

    // MARK: - Data Export (GDPR)

    /// Export all collected analytics data as JSON.
    ///
    /// Users can inspect exactly what has been collected via
    /// Settings > Analytics > View Collected Data.
    ///
    /// - Returns: Pretty-printed JSON ``Data`` of all queued events.
    public func exportCollectedData() -> Data {
        lock.lock()
        let events = eventQueue
        let id = config.anonymousId
        lock.unlock()

        let export: [String: Any] = [
            "anonymousId": id.uuidString,
            "eventCount": events.count,
            "exportedAt": ISO8601DateFormatter().string(from: Date())
        ]

        // Encode events separately for type safety
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let eventsData = try? encoder.encode(events),
              let eventsJSON = try? JSONSerialization.jsonObject(with: eventsData) else {
            return Data()
        }

        var fullExport = export
        fullExport["events"] = eventsJSON

        guard let data = try? JSONSerialization.data(
            withJSONObject: fullExport,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return Data()
        }

        return data
    }

    /// Export collected data as a UTF-8 JSON string.
    ///
    /// Convenience wrapper around ``exportCollectedData()`` for display
    /// in the settings UI.
    ///
    /// - Returns: A pretty-printed JSON string, or an empty-object string on failure.
    public func exportCollectedDataString() -> String {
        let data = exportCollectedData()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Data Deletion (GDPR)

    /// Delete all collected analytics data and generate a new anonymous ID.
    ///
    /// Implements the GDPR right to erasure. After calling this method,
    /// no previously collected data remains on disk or in memory.
    /// A new anonymous ID is generated so future (opt-in) events cannot
    /// be correlated with deleted data.
    public func deleteAllData() {
        lock.lock()
        eventQueue.removeAll()

        // Generate a new anonymous ID
        let newId = UUID()
        config.anonymousId = newId
        UserDefaults.standard.set(newId.uuidString, forKey: Self.anonymousIdKey)
        lock.unlock()

        // Delete the events file
        try? FileManager.default.removeItem(at: queueFileURL)
    }

    // MARK: - Endpoint Configuration

    /// Set the remote endpoint URL for batch uploads.
    ///
    /// - Parameter url: The endpoint URL, or `nil` to disable uploads.
    public func setEndpointURL(_ url: URL?) {
        lock.lock()
        config.endpointURL = url
        UserDefaults.standard.set(url?.absoluteString, forKey: Self.endpointURLKey)
        lock.unlock()
    }

    // MARK: - Batch Upload

    /// Attempt to upload queued events to the configured endpoint.
    ///
    /// Called automatically by the upload timer. Events are only removed
    /// from the queue after a successful upload (HTTP 2xx).
    public func flushEvents() {
        lock.lock()
        guard config.enabled,
              let endpointURL = config.endpointURL,
              !eventQueue.isEmpty else {
            lock.unlock()
            return
        }

        let eventsToSend = eventQueue
        let anonymousId = config.anonymousId
        lock.unlock()

        // Build the upload payload
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        struct UploadPayload: Encodable {
            let anonymousId: String
            let events: [AnalyticsEvent]
        }

        let payload = UploadPayload(
            anonymousId: anonymousId.uuidString,
            events: eventsToSend
        )

        guard let body = try? encoder.encode(payload) else { return }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30

        // Fire-and-forget upload
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return // Keep events for next attempt
            }

            // Successfully uploaded — remove sent events
            self.lock.lock()
            self.eventQueue.removeAll { event in
                eventsToSend.contains { $0.timestamp == event.timestamp && $0.name == event.name }
            }
            let remaining = self.eventQueue
            self.lock.unlock()

            self.persistEvents(remaining)
        }
        task.resume()
    }

    // MARK: - Private Helpers

    /// Start the periodic upload timer on the main run loop.
    private func startUploadTimer() {
        stopUploadTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.uploadTimer = Timer.scheduledTimer(
                withTimeInterval: Self.uploadInterval,
                repeats: true
            ) { [weak self] _ in
                self?.flushEvents()
            }
        }
    }

    /// Invalidate the upload timer.
    private func stopUploadTimer() {
        uploadTimer?.invalidate()
        uploadTimer = nil
    }

    /// Persist the event queue to disk as JSON.
    private func persistEvents(_ events: [AnalyticsEvent]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: queueFileURL, options: .atomic)
    }

    /// Load persisted events from a JSON file.
    private static func loadEvents(from url: URL) -> [AnalyticsEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AnalyticsEvent].self, from: data)) ?? []
    }

    deinit {
        uploadTimer?.invalidate()
    }
}
