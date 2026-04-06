// ============================================================================
// MeedyaConverter — EmailNotifier (Issue #348)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - SMTPConfig

/// Configuration for an SMTP mail server used for email notifications.
///
/// Stores all credentials and addressing information required to send
/// email via an SMTP relay. The password should be stored securely
/// (e.g. in the macOS Keychain) and populated at runtime.
///
/// Phase 17 — Email Notification on Job Completion (Issue #348)
public struct SMTPConfig: Codable, Sendable {

    // MARK: - Properties

    /// The SMTP server hostname (e.g. "smtp.gmail.com").
    public var host: String

    /// The SMTP server port (e.g. 587 for STARTTLS, 465 for implicit TLS).
    public var port: Int

    /// The SMTP authentication username (often an email address).
    public var username: String

    /// The SMTP authentication password or app-specific password.
    public var password: String

    /// Whether to use TLS encryption for the SMTP connection.
    ///
    /// When `true`, the connection uses `smtps://` (implicit TLS).
    /// When `false`, the connection uses `smtp://` (plaintext or STARTTLS).
    public var useTLS: Bool

    /// The "From" email address shown in the notification email.
    public var fromAddress: String

    /// One or more "To" email addresses that receive the notification.
    public var toAddresses: [String]

    // MARK: - Initialiser

    /// Create a new SMTP configuration.
    ///
    /// - Parameters:
    ///   - host: SMTP server hostname.
    ///   - port: SMTP server port.
    ///   - username: SMTP authentication username.
    ///   - password: SMTP authentication password.
    ///   - useTLS: Whether to use TLS encryption.
    ///   - fromAddress: The sender email address.
    ///   - toAddresses: One or more recipient email addresses.
    public init(
        host: String,
        port: Int,
        username: String,
        password: String,
        useTLS: Bool,
        fromAddress: String,
        toAddresses: [String]
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useTLS = useTLS
        self.fromAddress = fromAddress
        self.toAddresses = toAddresses
    }
}

// MARK: - EmailNotifier

/// Builds and dispatches email notifications for encoding job events.
///
/// Uses `curl` as the SMTP transport, constructing raw MIME messages and
/// shell-invocable argument arrays. This avoids a dependency on third-party
/// SMTP libraries while remaining compatible with all major mail providers
/// (Gmail, Outlook, Amazon SES, self-hosted Postfix, etc.).
///
/// Phase 17 — Email Notification on Job Completion (Issue #348)
public struct EmailNotifier: Sendable {

    // MARK: - MIME Email Builder

    /// Build a raw MIME email string suitable for SMTP submission.
    ///
    /// Constructs a multipart MIME message with an HTML body. The resulting
    /// string can be written to a temporary file and uploaded via `curl`
    /// using the `--upload-file` flag.
    ///
    /// - Parameters:
    ///   - subject: The email subject line.
    ///   - body: The HTML body content.
    ///   - config: The SMTP configuration containing addressing info.
    /// - Returns: A raw MIME-formatted email string.
    public static func buildNotificationEmail(
        subject: String,
        body: String,
        config: SMTPConfig
    ) -> String {
        let boundary = "MeedyaConverter-\(UUID().uuidString)"
        let toHeader = config.toAddresses.joined(separator: ", ")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = dateFormatter.string(from: Date())

        var email = ""
        email += "From: MeedyaConverter <\(config.fromAddress)>\r\n"
        email += "To: \(toHeader)\r\n"
        email += "Subject: \(subject)\r\n"
        email += "Date: \(dateString)\r\n"
        email += "MIME-Version: 1.0\r\n"
        email += "Content-Type: multipart/alternative; boundary=\"\(boundary)\"\r\n"
        email += "\r\n"
        email += "--\(boundary)\r\n"
        email += "Content-Type: text/html; charset=UTF-8\r\n"
        email += "Content-Transfer-Encoding: 7bit\r\n"
        email += "\r\n"
        email += body
        email += "\r\n"
        email += "--\(boundary)--\r\n"

        return email
    }

    // MARK: - Curl Argument Builders

    /// Build `curl` command-line arguments for sending an email via SMTP.
    ///
    /// The returned array is suitable for passing to `Process.arguments`.
    /// The `email` parameter should be written to a temporary file whose
    /// path is passed as the `--upload-file` value.
    ///
    /// - Parameters:
    ///   - email: The raw MIME email string (written to a temp file first).
    ///   - config: The SMTP configuration with server and addressing details.
    /// - Returns: An array of `curl` argument strings.
    public static func sendViaProcess(
        email: String,
        config: SMTPConfig
    ) -> [String] {
        let scheme = config.useTLS ? "smtps" : "smtp"
        let url = "\(scheme)://\(config.host):\(config.port)"

        var args: [String] = [
            "--url", url,
            "--ssl-reqd",
            "--mail-from", config.fromAddress,
        ]

        // Add each recipient as a separate --mail-rcpt argument.
        for recipient in config.toAddresses {
            args.append(contentsOf: ["--mail-rcpt", recipient])
        }

        args.append(contentsOf: [
            "--user", "\(config.username):\(config.password)",
            "--upload-file", "-",
        ])

        return args
    }

    /// Build `curl` arguments for testing SMTP connectivity.
    ///
    /// Performs a connection test without sending an actual email.
    /// Uses `--connect-timeout` to fail fast and `--no-transfer` to
    /// avoid data exchange beyond the initial handshake.
    ///
    /// - Parameter config: The SMTP configuration to test.
    /// - Returns: An array of `curl` argument strings for the connection test.
    public static func testConnection(config: SMTPConfig) -> [String] {
        let scheme = config.useTLS ? "smtps" : "smtp"
        let url = "\(scheme)://\(config.host):\(config.port)"

        return [
            "--url", url,
            "--ssl-reqd",
            "--user", "\(config.username):\(config.password)",
            "--connect-timeout", "10",
            "--no-transfer",
        ]
    }

    // MARK: - Email Formatting

    /// Format a job completion notification as an HTML email.
    ///
    /// Produces a styled HTML email with a status badge (green for success,
    /// red for failure), job details, and the MeedyaConverter branding.
    ///
    /// - Parameters:
    ///   - fileName: The display name of the source file.
    ///   - profile: The encoding profile name used.
    ///   - duration: Human-readable encoding duration (e.g. "2m 35s").
    ///   - outputSize: Human-readable output file size (e.g. "1.5 GB").
    ///   - success: Whether the encoding job completed successfully.
    ///   - errorMessage: An optional error description when `success` is `false`.
    /// - Returns: A tuple of `(subject, body)` where `body` is HTML content.
    public static func formatJobCompletionEmail(
        fileName: String,
        profile: String,
        duration: String,
        outputSize: String,
        success: Bool,
        errorMessage: String? = nil
    ) -> (subject: String, body: String) {
        let statusEmoji = success ? "✅" : "❌"
        let statusText = success ? "Completed Successfully" : "Failed"
        let subject = "\(statusEmoji) MeedyaConverter — \(fileName) \(statusText)"

        let badgeColor = success ? "#2ecc71" : "#e74c3c"
        let badgeText = success ? "SUCCESS" : "FAILED"

        var errorSection = ""
        if let errorMessage, !errorMessage.isEmpty {
            errorSection = """
            <tr>
                <td style="padding: 8px 12px; font-weight: 600; color: #555;">Error</td>
                <td style="padding: 8px 12px; color: #e74c3c;">\(escapeHTML(errorMessage))</td>
            </tr>
            """
        }

        let body = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"></head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; \
        margin: 0; padding: 20px; background-color: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 8px; \
        overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">

            <!-- Header -->
            <div style="background: #1a1a2e; padding: 20px 24px; color: #ffffff;">
                <h1 style="margin: 0; font-size: 20px;">MeedyaConverter</h1>
                <p style="margin: 4px 0 0; font-size: 13px; opacity: 0.8;">Encoding Job Notification</p>
            </div>

            <!-- Status Badge -->
            <div style="padding: 20px 24px; text-align: center;">
                <span style="display: inline-block; padding: 6px 16px; border-radius: 20px; \
        background: \(badgeColor); color: #ffffff; font-weight: 700; font-size: 14px; \
        letter-spacing: 0.5px;">\(badgeText)</span>
            </div>

            <!-- Details Table -->
            <table style="width: 100%; border-collapse: collapse; margin: 0 24px 20px; \
        max-width: calc(100% - 48px);">
                <tr style="border-bottom: 1px solid #eee;">
                    <td style="padding: 8px 12px; font-weight: 600; color: #555; width: 120px;">File</td>
                    <td style="padding: 8px 12px;">\(escapeHTML(fileName))</td>
                </tr>
                <tr style="border-bottom: 1px solid #eee;">
                    <td style="padding: 8px 12px; font-weight: 600; color: #555;">Profile</td>
                    <td style="padding: 8px 12px;">\(escapeHTML(profile))</td>
                </tr>
                <tr style="border-bottom: 1px solid #eee;">
                    <td style="padding: 8px 12px; font-weight: 600; color: #555;">Duration</td>
                    <td style="padding: 8px 12px;">\(escapeHTML(duration))</td>
                </tr>
                <tr style="border-bottom: 1px solid #eee;">
                    <td style="padding: 8px 12px; font-weight: 600; color: #555;">Output Size</td>
                    <td style="padding: 8px 12px;">\(escapeHTML(outputSize))</td>
                </tr>
                \(errorSection)
            </table>

            <!-- Footer -->
            <div style="padding: 16px 24px; background: #f8f8f8; font-size: 12px; color: #999; \
        text-align: center;">
                Sent by MeedyaConverter &mdash; MWBM Partners Ltd &copy; 2026
            </div>
        </div>
        </body>
        </html>
        """

        return (subject: subject, body: body)
    }

    // MARK: - Private Helpers

    /// Escape HTML special characters to prevent injection in email bodies.
    ///
    /// - Parameter string: The raw string to escape.
    /// - Returns: The HTML-safe escaped string.
    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
