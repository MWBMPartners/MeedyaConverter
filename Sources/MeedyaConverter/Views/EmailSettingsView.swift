// ============================================================================
// MeedyaConverter — EmailSettingsView (Issue #348)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - EmailSettingsView

/// Settings view for configuring SMTP email notifications.
///
/// Provides a form for entering SMTP server details, sender/recipient
/// addresses, event triggers, and a test email button. The SMTP password
/// is stored securely in the macOS Keychain via the Security framework.
///
/// Phase 17 — Email Notification on Job Completion (Issue #348)
struct EmailSettingsView: View {

    // MARK: - SMTP Server State

    /// The SMTP server hostname.
    @AppStorage("emailSMTPHost") private var smtpHost = ""

    /// The SMTP server port.
    @AppStorage("emailSMTPPort") private var smtpPort = 587

    /// The SMTP authentication username.
    @AppStorage("emailSMTPUsername") private var smtpUsername = ""

    /// Whether to use TLS encryption for the SMTP connection.
    @AppStorage("emailSMTPUseTLS") private var smtpUseTLS = true

    // MARK: - Addressing State

    /// The sender "From" email address.
    @AppStorage("emailFromAddress") private var fromAddress = ""

    /// JSON-encoded array of recipient email addresses.
    @AppStorage("emailToAddresses") private var toAddressesJSON = "[]"

    // MARK: - Event Trigger State

    /// Whether to send an email when an encode completes successfully.
    @AppStorage("emailOnComplete") private var emailOnComplete = true

    /// Whether to send an email when an encode fails.
    @AppStorage("emailOnFailure") private var emailOnFailure = true

    /// Whether to send an email when the entire queue finishes.
    @AppStorage("emailOnQueueFinished") private var emailOnQueueFinished = false

    // MARK: - Transient State

    /// The SMTP password (not persisted in AppStorage — uses Keychain).
    @State private var smtpPassword = ""

    /// A new recipient address being entered.
    @State private var newRecipient = ""

    /// Whether a test email is currently being sent.
    @State private var isSendingTest = false

    /// Feedback message after a test email attempt.
    @State private var testResult: String?

    /// Whether the password has been loaded from the Keychain.
    @State private var passwordLoaded = false

    // MARK: - Body

    var body: some View {
        Form {
            // MARK: SMTP Server
            Section("SMTP Server") {
                TextField("Host", text: $smtpHost, prompt: Text("smtp.gmail.com"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("SMTP server hostname")

                TextField("Port", value: $smtpPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .accessibilityLabel("SMTP server port")

                TextField("Username", text: $smtpUsername, prompt: Text("user@example.com"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("SMTP authentication username")

                SecureField("Password", text: $smtpPassword, prompt: Text("App password"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("SMTP authentication password")
                    .onChange(of: smtpPassword) {
                        if passwordLoaded {
                            savePasswordToKeychain(smtpPassword)
                        }
                    }

                Toggle("Use TLS", isOn: $smtpUseTLS)
                    .accessibilityLabel("Enable TLS encryption for SMTP")

                Text(smtpUseTLS
                    ? "Uses smtps:// (implicit TLS on port 465 or 587)."
                    : "Uses smtp:// (plaintext — not recommended).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Addresses
            Section("Email Addresses") {
                TextField("From Address", text: $fromAddress, prompt: Text("noreply@example.com"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Sender email address")

                let recipients = parseRecipients()
                if !recipients.isEmpty {
                    ForEach(recipients, id: \.self) { address in
                        HStack {
                            Text(address)
                                .font(.body)
                            Spacer()
                            Button {
                                removeRecipient(address)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove recipient \(address)")
                        }
                    }
                }

                HStack {
                    TextField("Add recipient", text: $newRecipient, prompt: Text("user@example.com"))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("New recipient email address")
                        .onSubmit { addRecipient() }

                    Button {
                        addRecipient()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(newRecipient.isEmpty)
                    .accessibilityLabel("Add recipient")
                }
            }

            // MARK: Event Triggers
            Section("Trigger Events") {
                Toggle("Encode completed successfully", isOn: $emailOnComplete)
                    .accessibilityLabel("Send email when an encode completes successfully")
                Toggle("Encode failed", isOn: $emailOnFailure)
                    .accessibilityLabel("Send email when an encode fails")
                Toggle("Queue finished", isOn: $emailOnQueueFinished)
                    .accessibilityLabel("Send email when the entire queue finishes")
            }

            // MARK: Actions
            Section("Actions") {
                HStack {
                    Button {
                        sendTestEmail()
                    } label: {
                        Label("Send Test Email", systemImage: "envelope")
                    }
                    .disabled(!isConfigValid || isSendingTest)
                    .accessibilityLabel("Send a test email to verify SMTP settings")

                    if isSendingTest {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("Error") ? .red : .green)
                }

                Button("Save Configuration") {
                    savePasswordToKeychain(smtpPassword)
                    testResult = "Configuration saved."
                }
                .accessibilityLabel("Save SMTP configuration and store password in Keychain")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Email Notifications")
        .onAppear {
            smtpPassword = loadPasswordFromKeychain()
            passwordLoaded = true
        }
    }

    // MARK: - Computed Properties

    /// Whether the current SMTP configuration has enough data to attempt sending.
    private var isConfigValid: Bool {
        !smtpHost.isEmpty
            && !smtpUsername.isEmpty
            && !smtpPassword.isEmpty
            && !fromAddress.isEmpty
            && !parseRecipients().isEmpty
    }

    // MARK: - Recipient Management

    /// Parse the stored recipient JSON into an array of email addresses.
    ///
    /// - Returns: An array of recipient email address strings.
    private func parseRecipients() -> [String] {
        guard let data = toAddressesJSON.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }

    /// Add the currently entered recipient to the recipients list.
    private func addRecipient() {
        let trimmed = newRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var recipients = parseRecipients()
        if !recipients.contains(trimmed) {
            recipients.append(trimmed)
            saveRecipients(recipients)
        }
        newRecipient = ""
    }

    /// Remove a recipient from the recipients list.
    ///
    /// - Parameter address: The email address to remove.
    private func removeRecipient(_ address: String) {
        var recipients = parseRecipients()
        recipients.removeAll { $0 == address }
        saveRecipients(recipients)
    }

    /// Persist the recipients list to `AppStorage` as JSON.
    ///
    /// - Parameter recipients: The array of email addresses to save.
    private func saveRecipients(_ recipients: [String]) {
        if let data = try? JSONEncoder().encode(recipients),
           let json = String(data: data, encoding: .utf8) {
            toAddressesJSON = json
        }
    }

    // MARK: - SMTP Config Builder

    /// Build an `SMTPConfig` from the current form state.
    ///
    /// - Returns: A configured `SMTPConfig` instance.
    private func buildSMTPConfig() -> SMTPConfig {
        SMTPConfig(
            host: smtpHost,
            port: smtpPort,
            username: smtpUsername,
            password: smtpPassword,
            useTLS: smtpUseTLS,
            fromAddress: fromAddress,
            toAddresses: parseRecipients()
        )
    }

    // MARK: - Test Email

    /// Send a test email using the current SMTP configuration.
    private func sendTestEmail() {
        isSendingTest = true
        testResult = nil

        let config = buildSMTPConfig()
        let (subject, body) = EmailNotifier.formatJobCompletionEmail(
            fileName: "test_file.mp4",
            profile: "Web Standard",
            duration: "1m 42s",
            outputSize: "100 MB",
            success: true
        )
        let rawEmail = EmailNotifier.buildNotificationEmail(
            subject: subject,
            body: body,
            config: config
        )
        let curlArgs = EmailNotifier.sendViaProcess(email: rawEmail, config: config)

        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = curlArgs

                let inputPipe = Pipe()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                try process.run()

                // Write the email content to stdin.
                if let emailData = rawEmail.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(emailData)
                }
                inputPipe.fileHandleForWriting.closeFile()

                process.waitUntilExit()

                let status = process.terminationStatus

                await MainActor.run {
                    if status == 0 {
                        testResult = "Test email sent successfully."
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        testResult = "Error: curl exit code \(status) — \(errorString)"
                    }
                    isSendingTest = false
                }
            } catch {
                await MainActor.run {
                    testResult = "Error: \(error.localizedDescription)"
                    isSendingTest = false
                }
            }
        }
    }

    // MARK: - Keychain Helpers

    /// The Keychain service identifier for the SMTP password.
    private static let keychainService = "com.mwbmpartners.MeedyaConverter.smtp"

    /// The Keychain account key for the SMTP password.
    private static let keychainAccount = "smtpPassword"

    /// Save the SMTP password to the macOS Keychain.
    ///
    /// - Parameter password: The password string to store.
    private func savePasswordToKeychain(_ password: String) {
        guard let data = password.data(using: .utf8) else { return }

        // Delete any existing entry first.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new password.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: data,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Load the SMTP password from the macOS Keychain.
    ///
    /// - Returns: The stored password string, or an empty string if not found.
    private func loadPasswordFromKeychain() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return ""
        }
        return password
    }
}
