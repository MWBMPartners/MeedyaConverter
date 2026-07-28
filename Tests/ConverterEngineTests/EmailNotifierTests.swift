// ============================================================================
// MeedyaConverter — EmailNotifierTests (Issue #348)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import XCTest

// Per this repo's test policy (see the header comment in
// `ConverterEngineTests.swift`): `EmailNotifier`'s tested surface
// (`buildNotificationEmail`, `sendViaProcess`, `testConnection`,
// `formatJobCompletionEmail`) and `SMTPConfig` are all `public`, so this
// file exercises them via the public API — `import ConverterEngine`, no
// `@testable import`.
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - EmailNotifierTests
// ---------------------------------------------------------------------------
/// Tests for `EmailNotifier`'s pure MIME/curl-argument construction (Issue
/// #348 — "email on completion" roadmap verification pass).
///
/// `EmailNotifier`/`SMTPConfig` are the only pieces of the completion-email
/// feature that live in `ConverterEngine` and are therefore reachable from
/// this test target. The wiring that *calls* them —
/// `AppViewModel.sendCompletionEmail(...)`, gated on the `emailOnComplete`/
/// `emailOnFailure` `UserDefaults` keys, and `EmailSettingsView.loadSMTPConfig()`
/// / Keychain access — lives in the `MeedyaConverter` executable target,
/// which no test target imports (Swift forbids importing a module containing
/// `@main` into a test target; see `MeedyaConvertTests`'s target comment in
/// `Package.swift`). That wiring was verified by code inspection instead:
/// `sendCompletionEmail`'s `UserDefaults.standard.bool(forKey: "emailOnComplete"/
/// "emailOnFailure")` reads the exact keys `EmailSettingsView`'s
/// `@AppStorage("emailOnComplete")`/`@AppStorage("emailOnFailure")` toggles
/// write; `EmailSettingsView.loadSMTPConfig()` reads the same `UserDefaults`
/// keys as its own `@AppStorage` SMTP fields, plus the password via
/// `loadPasswordFromKeychain()`, which shares the exact `keychainService`/
/// `keychainAccount` constants `savePasswordToKeychain()` writes with; and a
/// missing/incomplete config makes `loadSMTPConfig()` return `nil`, which
/// `sendCompletionEmail` guards on and returns early — no crash, no
/// fabricated "email sent" message (the curl `Process` failure path is also
/// silently, intentionally dropped, matching `sendNotification`'s existing
/// fire-and-forget style). No mismatch was found; nothing was changed there.
final class EmailNotifierTests: XCTestCase {

    // MARK: - Fixtures

    private func makeConfig(
        useTLS: Bool = true,
        toAddresses: [String] = ["a@example.com", "b@example.com"]
    ) -> SMTPConfig {
        SMTPConfig(
            host: "smtp.example.com",
            port: 587,
            username: "user@example.com",
            password: "s3cret",
            useTLS: useTLS,
            fromAddress: "noreply@example.com",
            toAddresses: toAddresses
        )
    }

    // MARK: - buildNotificationEmail

    func test_buildNotificationEmail_containsRequiredHeaders() {
        let config = makeConfig()
        let email = EmailNotifier.buildNotificationEmail(
            subject: "Test Subject",
            body: "<p>Hello</p>",
            config: config
        )

        XCTAssertTrue(email.contains("From: MeedyaConverter <noreply@example.com>\r\n"))
        XCTAssertTrue(email.contains("To: a@example.com, b@example.com\r\n"))
        XCTAssertTrue(email.contains("Subject: Test Subject\r\n"))
        XCTAssertTrue(email.contains("MIME-Version: 1.0\r\n"))
        XCTAssertTrue(email.contains("Content-Type: multipart/alternative; boundary=\""))
        XCTAssertTrue(email.contains("<p>Hello</p>"))
    }

    func test_buildNotificationEmail_boundaryOpensAndCloses() {
        let email = EmailNotifier.buildNotificationEmail(
            subject: "S",
            body: "B",
            config: makeConfig()
        )

        // Extract the boundary token from the Content-Type header.
        guard let boundaryRange = email.range(of: "boundary=\""),
              let closingQuoteRange = email.range(of: "\"", range: boundaryRange.upperBound..<email.endIndex) else {
            return XCTFail("Could not find MIME boundary in generated email")
        }
        let boundary = String(email[boundaryRange.upperBound..<closingQuoteRange.lowerBound])

        XCTAssertTrue(boundary.hasPrefix("MeedyaConverter-"))
        XCTAssertTrue(email.contains("--\(boundary)\r\n"))
        XCTAssertTrue(email.contains("--\(boundary)--\r\n"), "the final boundary must be properly closed")
    }

    func test_buildNotificationEmail_boundaryIsUniquePerCall() {
        let config = makeConfig()
        let email1 = EmailNotifier.buildNotificationEmail(subject: "S", body: "B", config: config)
        let email2 = EmailNotifier.buildNotificationEmail(subject: "S", body: "B", config: config)
        XCTAssertNotEqual(email1, email2, "each email should get a fresh MIME boundary (contains a UUID)")
    }

    // MARK: - sendViaProcess (curl argument construction)

    func test_sendViaProcess_usesSmtpsSchemeWhenTLSEnabled() {
        let args = EmailNotifier.sendViaProcess(email: "irrelevant", config: makeConfig(useTLS: true))
        XCTAssertEqual(args[0], "--url")
        XCTAssertEqual(args[1], "smtps://smtp.example.com:587")
    }

    func test_sendViaProcess_usesSmtpSchemeWhenTLSDisabled() {
        let args = EmailNotifier.sendViaProcess(email: "irrelevant", config: makeConfig(useTLS: false))
        XCTAssertEqual(args[1], "smtp://smtp.example.com:587")
    }

    func test_sendViaProcess_includesMailFromAndEachRecipient() {
        let args = EmailNotifier.sendViaProcess(
            email: "irrelevant",
            config: makeConfig(toAddresses: ["x@example.com", "y@example.com", "z@example.com"])
        )

        guard let fromIndex = args.firstIndex(of: "--mail-from") else {
            return XCTFail("Expected --mail-from")
        }
        XCTAssertEqual(args[fromIndex + 1], "noreply@example.com")

        let rcptIndices = args.indices.filter { args[$0] == "--mail-rcpt" }
        XCTAssertEqual(rcptIndices.count, 3, "one --mail-rcpt per recipient")
        let recipients = rcptIndices.map { args[$0 + 1] }
        XCTAssertEqual(recipients, ["x@example.com", "y@example.com", "z@example.com"])
    }

    func test_sendViaProcess_includesUserCredentialsAndStdinUpload() {
        let args = EmailNotifier.sendViaProcess(email: "irrelevant", config: makeConfig())

        guard let userIndex = args.firstIndex(of: "--user") else {
            return XCTFail("Expected --user")
        }
        XCTAssertEqual(args[userIndex + 1], "user@example.com:s3cret")

        guard let uploadIndex = args.firstIndex(of: "--upload-file") else {
            return XCTFail("Expected --upload-file")
        }
        XCTAssertEqual(args[uploadIndex + 1], "-", "email body is piped via stdin, never written unescaped into argv")
        XCTAssertTrue(args.contains("--ssl-reqd"))
    }

    func test_sendViaProcess_neverEmbedsRawEmailBodyInArguments() {
        // Guards against a regression where the MIME body (which can contain
        // attacker-influenced file names / error messages) gets interpolated
        // directly into the curl argv instead of being piped via stdin.
        let email = "Subject: shouldn't leak\r\n\r\n<script>evil()</script>"
        let args = EmailNotifier.sendViaProcess(email: email, config: makeConfig())
        XCTAssertFalse(args.contains(email))
        XCTAssertFalse(args.contains { $0.contains("evil()") })
    }

    // MARK: - testConnection

    func test_testConnection_isReadOnlyProbe_noRecipientsOrUpload() {
        let args = EmailNotifier.testConnection(config: makeConfig())
        XCTAssertTrue(args.contains("--no-transfer"))
        XCTAssertTrue(args.contains("--connect-timeout"))
        XCTAssertFalse(args.contains("--mail-rcpt"), "a connectivity test must not attempt to send to real recipients")
        XCTAssertFalse(args.contains("--upload-file"))
    }

    // MARK: - formatJobCompletionEmail

    func test_formatJobCompletionEmail_success_usesSuccessBadgeAndSubject() {
        let (subject, body) = EmailNotifier.formatJobCompletionEmail(
            fileName: "movie.mov",
            profile: "Web Standard",
            duration: "2m 10s",
            outputSize: "500 MB",
            success: true
        )
        XCTAssertTrue(subject.contains("movie.mov"))
        XCTAssertTrue(subject.contains("Completed Successfully"))
        XCTAssertTrue(body.contains("SUCCESS"))
        XCTAssertTrue(body.contains("movie.mov"))
        XCTAssertTrue(body.contains("Web Standard"))
        XCTAssertTrue(body.contains("2m 10s"))
        XCTAssertTrue(body.contains("500 MB"))
        XCTAssertFalse(body.contains("Error"), "a successful job must not render an error row")
    }

    func test_formatJobCompletionEmail_failure_usesFailedBadgeAndErrorRow() {
        let (subject, body) = EmailNotifier.formatJobCompletionEmail(
            fileName: "movie.mov",
            profile: "Web Standard",
            duration: "unknown",
            outputSize: "—",
            success: false,
            errorMessage: "FFmpeg exited with code 1"
        )
        XCTAssertTrue(subject.contains("Failed"))
        XCTAssertTrue(body.contains("FAILED"))
        XCTAssertTrue(body.contains("FFmpeg exited with code 1"))
    }

    func test_formatJobCompletionEmail_escapesHTMLInUserSuppliedFields() {
        // File names and error messages can contain characters the OS/FFmpeg
        // allow but that are unsafe to interpolate raw into HTML.
        let (_, body) = EmailNotifier.formatJobCompletionEmail(
            fileName: "<script>alert(1)</script>.mov",
            profile: "A & B",
            duration: "1s",
            outputSize: "1 MB",
            success: false,
            errorMessage: "<b>bold</b> & \"quoted\""
        )
        XCTAssertFalse(body.contains("<script>alert(1)</script>"))
        XCTAssertTrue(body.contains("&lt;script&gt;"))
        XCTAssertTrue(body.contains("A &amp; B"))
        XCTAssertTrue(body.contains("&lt;b&gt;bold&lt;/b&gt; &amp; &quot;quoted&quot;"))
    }

    func test_formatJobCompletionEmail_noErrorMessage_omitsErrorRow() {
        let (_, body) = EmailNotifier.formatJobCompletionEmail(
            fileName: "movie.mov",
            profile: "Web Standard",
            duration: "1m",
            outputSize: "1 MB",
            success: false
        )
        XCTAssertFalse(body.contains("<td style=\"padding: 8px 12px; font-weight: 600; color: #555;\">Error</td>"))
    }
}
