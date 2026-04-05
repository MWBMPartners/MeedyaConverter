// ============================================================================
// MeedyaConverter — WebhookSender (Issue #296)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - WebhookJobInfo

/// Summarised job information included in webhook payloads.
///
/// Deliberately omits file paths and system-specific data.
/// Only human-readable metadata is transmitted.
public struct WebhookJobInfo: Codable, Sendable {

    // MARK: - Properties

    /// The display name of the source file (no path).
    public var fileName: String

    /// The encoding profile name used for this job.
    public var profile: String

    /// Total encoding duration in seconds.
    public var durationSeconds: Double

    /// Output file size in bytes.
    public var outputSizeBytes: Int64

    // MARK: - Initialiser

    /// Create a new webhook job info summary.
    ///
    /// - Parameters:
    ///   - fileName: Display name of the source file.
    ///   - profile: Encoding profile name.
    ///   - durationSeconds: Total encoding duration in seconds.
    ///   - outputSizeBytes: Output file size in bytes.
    public init(
        fileName: String,
        profile: String,
        durationSeconds: Double,
        outputSizeBytes: Int64
    ) {
        self.fileName = fileName
        self.profile = profile
        self.durationSeconds = durationSeconds
        self.outputSizeBytes = outputSizeBytes
    }
}

// MARK: - WebhookPayload

/// The JSON payload sent to webhook endpoints on encode events.
///
/// Contains enough information for automation or monitoring systems
/// to act on encode results without exposing file paths or sensitive data.
public struct WebhookPayload: Codable, Sendable {

    // MARK: - Properties

    /// The event type that triggered this webhook.
    ///
    /// Common values: `encode_complete`, `encode_failed`, `queue_complete`.
    public var event: String

    /// ISO 8601 timestamp of when the event occurred.
    public var timestamp: String

    /// Summarised job information (file name, profile, duration, output size).
    public var job: WebhookJobInfo

    /// The outcome status: `success` or `failure`.
    public var status: String

    /// An optional error message when the status is `failure`.
    public var errorMessage: String?

    // MARK: - Initialiser

    /// Create a new webhook payload.
    ///
    /// - Parameters:
    ///   - event: The event type (e.g. `encode_complete`).
    ///   - timestamp: ISO 8601 timestamp string.
    ///   - job: Summarised job info.
    ///   - status: Outcome status (`success` or `failure`).
    ///   - errorMessage: Optional error message for failures.
    public init(
        event: String,
        timestamp: String,
        job: WebhookJobInfo,
        status: String,
        errorMessage: String? = nil
    ) {
        self.event = event
        self.timestamp = timestamp
        self.job = job
        self.status = status
        self.errorMessage = errorMessage
    }

    /// Create a payload with the current timestamp.
    ///
    /// - Parameters:
    ///   - event: The event type.
    ///   - job: Summarised job info.
    ///   - status: Outcome status.
    ///   - errorMessage: Optional error message.
    /// - Returns: A new `WebhookPayload` with the `timestamp` set to now (ISO 8601).
    public static func now(
        event: String,
        job: WebhookJobInfo,
        status: String,
        errorMessage: String? = nil
    ) -> WebhookPayload {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return WebhookPayload(
            event: event,
            timestamp: formatter.string(from: Date()),
            job: job,
            status: status,
            errorMessage: errorMessage
        )
    }
}

// MARK: - WebhookConfig

/// Configuration for a webhook endpoint including retry behaviour.
///
/// Includes factory methods for popular services (Discord, Slack) that
/// format the payload according to each service's expected structure.
public struct WebhookConfig: Codable, Sendable {

    // MARK: - Properties

    /// The webhook endpoint URL.
    public var url: URL

    /// HTTP method (always `POST` for webhooks).
    public var method: String

    /// Additional HTTP headers to include in the request.
    public var headers: [String: String]

    /// Number of retry attempts on failure (0 = no retries).
    public var retryCount: Int

    /// Delay between retry attempts in seconds.
    public var retryDelaySeconds: Int

    // MARK: - Initialiser

    /// Create a new webhook configuration.
    ///
    /// - Parameters:
    ///   - url: The webhook endpoint URL.
    ///   - method: HTTP method (defaults to `POST`).
    ///   - headers: Additional HTTP headers.
    ///   - retryCount: Number of retry attempts (defaults to 2).
    ///   - retryDelaySeconds: Delay between retries in seconds (defaults to 5).
    public init(
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        retryCount: Int = 2,
        retryDelaySeconds: Int = 5
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.retryCount = retryCount
        self.retryDelaySeconds = retryDelaySeconds
    }

    // MARK: - Presets

    /// A Discord-compatible webhook configuration.
    ///
    /// Formats the payload as a Discord embed with colour-coded status
    /// (green for success, red for failure).
    ///
    /// - Parameter webhookURL: The Discord webhook URL.
    /// - Returns: A configured `WebhookConfig` for Discord.
    public static func discord(webhookURL: URL) -> WebhookConfig {
        WebhookConfig(
            url: webhookURL,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            retryCount: 2,
            retryDelaySeconds: 5
        )
    }

    /// A Slack-compatible webhook configuration.
    ///
    /// Formats the payload as a Slack Block Kit message with status emoji
    /// and structured fields.
    ///
    /// - Parameter webhookURL: The Slack incoming webhook URL.
    /// - Returns: A configured `WebhookConfig` for Slack.
    public static func slack(webhookURL: URL) -> WebhookConfig {
        WebhookConfig(
            url: webhookURL,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            retryCount: 2,
            retryDelaySeconds: 5
        )
    }

    /// A generic webhook configuration with standard JSON headers.
    ///
    /// - Parameter url: The webhook endpoint URL.
    /// - Returns: A configured `WebhookConfig` for generic JSON endpoints.
    public static func generic(url: URL) -> WebhookConfig {
        WebhookConfig(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            retryCount: 2,
            retryDelaySeconds: 5
        )
    }
}

// MARK: - WebhookSender

/// Sends webhook payloads to configured endpoints with retry logic.
///
/// Uses `URLSession` with a 30-second timeout per attempt. Failed attempts
/// are retried up to `config.retryCount` times with a configurable delay
/// between attempts.
///
/// Phase 17 — Post-Encode Hooks (Issue #296)
public struct WebhookSender: Sendable {

    // MARK: - Errors

    /// Errors that can occur during webhook delivery.
    public enum WebhookError: LocalizedError, Sendable {
        /// The server responded with a non-success HTTP status code.
        case httpError(statusCode: Int, body: String?)
        /// All retry attempts were exhausted without a successful delivery.
        case allRetriesFailed(lastError: String)
        /// The webhook URL is invalid or unreachable.
        case invalidURL

        public var errorDescription: String? {
            switch self {
            case .httpError(let code, let body):
                return "Webhook HTTP error \(code)\(body.map { ": \($0)" } ?? "")"
            case .allRetriesFailed(let lastError):
                return "All webhook retries failed. Last error: \(lastError)"
            case .invalidURL:
                return "The webhook URL is invalid or unreachable."
            }
        }
    }

    // MARK: - Sending

    /// Send a webhook payload to the configured endpoint.
    ///
    /// Encodes the payload as JSON and sends it via HTTP POST. If the request
    /// fails, it retries up to `config.retryCount` times with a delay of
    /// `config.retryDelaySeconds` between each attempt.
    ///
    /// - Parameters:
    ///   - payload: The webhook payload to send.
    ///   - config: The webhook configuration (URL, headers, retry settings).
    /// - Throws: `WebhookError` if delivery fails after all retry attempts.
    public static func send(payload: WebhookPayload, config: WebhookConfig) async throws {
        let bodyData: Data

        // Format the body according to the webhook preset type.
        if config.url.host?.contains("discord") == true {
            bodyData = try formatDiscordPayload(payload)
        } else if config.url.host?.contains("slack") == true {
            bodyData = try formatSlackPayload(payload)
        } else {
            bodyData = try JSONEncoder().encode(payload)
        }

        let totalAttempts = config.retryCount + 1
        var lastError: String = "Unknown error"

        for attempt in 1...totalAttempts {
            do {
                try await performRequest(bodyData: bodyData, config: config)
                return // Success — exit immediately.
            } catch {
                lastError = error.localizedDescription

                // If this was not the last attempt, wait before retrying.
                if attempt < totalAttempts {
                    try await Task.sleep(for: .seconds(config.retryDelaySeconds))
                }
            }
        }

        throw WebhookError.allRetriesFailed(lastError: lastError)
    }

    // MARK: - Private Helpers

    /// Perform a single HTTP request to the webhook endpoint.
    ///
    /// - Parameters:
    ///   - bodyData: The pre-encoded JSON body.
    ///   - config: The webhook configuration.
    /// - Throws: `WebhookError.httpError` on non-2xx responses.
    private static func performRequest(bodyData: Data, config: WebhookConfig) async throws {
        var request = URLRequest(url: config.url)
        request.httpMethod = config.method
        request.httpBody = bodyData
        request.timeoutInterval = 30

        for (key, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebhookError.invalidURL
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw WebhookError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }

    /// Format a payload as a Discord embed message.
    ///
    /// - Parameter payload: The webhook payload.
    /// - Returns: JSON-encoded data in Discord's embed format.
    private static func formatDiscordPayload(_ payload: WebhookPayload) throws -> Data {
        let color = payload.status == "success" ? 3_066_993 : 15_158_332 // Green or red
        let emoji = payload.status == "success" ? "✅" : "❌"
        let duration = formatDuration(payload.job.durationSeconds)
        let size = formatFileSize(payload.job.outputSizeBytes)

        let embed: [String: Any] = [
            "embeds": [[
                "title": "\(emoji) MeedyaConverter — \(payload.event.replacingOccurrences(of: "_", with: " ").capitalized)",
                "color": color,
                "fields": [
                    ["name": "File", "value": payload.job.fileName, "inline": true],
                    ["name": "Profile", "value": payload.job.profile, "inline": true],
                    ["name": "Duration", "value": duration, "inline": true],
                    ["name": "Output Size", "value": size, "inline": true],
                    ["name": "Status", "value": payload.status.capitalized, "inline": true]
                ],
                "timestamp": payload.timestamp
            ] as [String: Any]]
        ]

        return try JSONSerialization.data(withJSONObject: embed)
    }

    /// Format a payload as a Slack Block Kit message.
    ///
    /// - Parameter payload: The webhook payload.
    /// - Returns: JSON-encoded data in Slack's block format.
    private static func formatSlackPayload(_ payload: WebhookPayload) throws -> Data {
        let emoji = payload.status == "success" ? ":white_check_mark:" : ":x:"
        let duration = formatDuration(payload.job.durationSeconds)
        let size = formatFileSize(payload.job.outputSizeBytes)

        let message: [String: Any] = [
            "blocks": [
                [
                    "type": "header",
                    "text": [
                        "type": "plain_text",
                        "text": "\(emoji) MeedyaConverter — \(payload.event.replacingOccurrences(of: "_", with: " ").capitalized)"
                    ]
                ],
                [
                    "type": "section",
                    "fields": [
                        ["type": "mrkdwn", "text": "*File:* \(payload.job.fileName)"],
                        ["type": "mrkdwn", "text": "*Profile:* \(payload.job.profile)"],
                        ["type": "mrkdwn", "text": "*Duration:* \(duration)"],
                        ["type": "mrkdwn", "text": "*Size:* \(size)"],
                        ["type": "mrkdwn", "text": "*Status:* \(payload.status.capitalized)"]
                    ]
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: message)
    }

    /// Format seconds as a human-readable duration string.
    ///
    /// - Parameter seconds: The duration in seconds.
    /// - Returns: A formatted string (e.g. "2m 35s").
    private static func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    /// Format bytes as a human-readable file size string.
    ///
    /// - Parameter bytes: The size in bytes.
    /// - Returns: A formatted string (e.g. "1.5 GB").
    private static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
