// ============================================================================
// MeedyaConverter — WebhookSettingsView (Issue #296)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - WebhookPreset

/// Preset configurations for popular webhook services.
///
/// Each preset pre-configures the webhook URL format expectations
/// and appropriate headers for the target service.
enum WebhookPreset: String, CaseIterable {
    /// A generic JSON webhook endpoint.
    case generic = "Generic"
    /// A Discord incoming webhook.
    case discord = "Discord"
    /// A Slack incoming webhook.
    case slack = "Slack"
}

// MARK: - WebhookSettingsView

/// Settings view for configuring webhook notifications.
///
/// Allows the user to set a webhook URL, choose a service preset,
/// add custom headers, select which events trigger the webhook,
/// and send a test payload to verify connectivity.
///
/// Phase 17 — Webhook Notifications (Issue #296)
struct WebhookSettingsView: View {

    // MARK: - State

    /// The webhook endpoint URL string.
    @AppStorage("webhookURL") private var webhookURL = ""

    /// The selected webhook preset.
    @AppStorage("webhookPreset") private var webhookPreset = WebhookPreset.generic.rawValue

    /// Whether to fire the webhook on successful encode completion.
    @AppStorage("webhookOnComplete") private var webhookOnComplete = true

    /// Whether to fire the webhook on encode failure.
    @AppStorage("webhookOnFailure") private var webhookOnFailure = true

    /// Whether to fire the webhook when the entire queue finishes.
    @AppStorage("webhookOnQueueFinished") private var webhookOnQueueFinished = false

    /// Custom headers stored as a JSON string (key-value pairs).
    @AppStorage("webhookCustomHeaders") private var customHeadersJSON = ""

    /// Whether the test webhook is currently being sent.
    @State private var isSendingTest = false

    /// Feedback message after a test webhook attempt.
    @State private var testResult: String?

    /// Whether the custom headers editor sheet is presented.
    @State private var showHeadersEditor = false

    // MARK: - Body

    var body: some View {
        Form {
            // MARK: Endpoint
            Section("Webhook Endpoint") {
                Picker("Preset", selection: $webhookPreset) {
                    ForEach(WebhookPreset.allCases, id: \.rawValue) { preset in
                        Text(preset.rawValue).tag(preset.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Webhook service preset")

                TextField("Webhook URL", text: $webhookURL, prompt: Text("https://hooks.example.com/..."))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Webhook endpoint URL")

                if webhookPreset == WebhookPreset.discord.rawValue {
                    Text("Paste your Discord channel webhook URL.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if webhookPreset == WebhookPreset.slack.rawValue {
                    Text("Paste your Slack incoming webhook URL.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Events
            Section("Trigger Events") {
                Toggle("Encode completed successfully", isOn: $webhookOnComplete)
                    .accessibilityLabel("Send webhook when an encode completes successfully")
                Toggle("Encode failed", isOn: $webhookOnFailure)
                    .accessibilityLabel("Send webhook when an encode fails")
                Toggle("Queue finished", isOn: $webhookOnQueueFinished)
                    .accessibilityLabel("Send webhook when the entire queue finishes")
            }

            // MARK: Custom Headers
            Section("Custom Headers") {
                let headers = parseHeaders()
                if headers.isEmpty {
                    Text("No custom headers configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(headers.keys.sorted()), id: \.self) { key in
                        LabeledContent(key, value: headers[key] ?? "")
                            .font(.caption)
                    }
                }

                Button("Edit Headers...") {
                    showHeadersEditor = true
                }
                .accessibilityLabel("Open custom headers editor")
            }

            // MARK: Test
            Section("Test") {
                HStack {
                    Button {
                        sendTestWebhook()
                    } label: {
                        Label("Send Test Webhook", systemImage: "paperplane")
                    }
                    .disabled(webhookURL.isEmpty || isSendingTest)
                    .accessibilityLabel("Send a test webhook payload")

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
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Webhooks")
        .sheet(isPresented: $showHeadersEditor) {
            CustomHeadersEditor(headersJSON: $customHeadersJSON)
        }
    }

    // MARK: - Helpers

    /// Parse the stored custom headers JSON string into a dictionary.
    ///
    /// - Returns: A `[String: String]` dictionary of header key-value pairs.
    private func parseHeaders() -> [String: String] {
        guard !customHeadersJSON.isEmpty,
              let data = customHeadersJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    /// Build a `WebhookConfig` from the current settings.
    ///
    /// - Returns: A configured `WebhookConfig` or `nil` if the URL is invalid.
    private func buildConfig() -> WebhookConfig? {
        guard let url = URL(string: webhookURL) else { return nil }

        let preset = WebhookPreset(rawValue: webhookPreset) ?? .generic
        var config: WebhookConfig

        switch preset {
        case .discord:
            config = .discord(webhookURL: url)
        case .slack:
            config = .slack(webhookURL: url)
        case .generic:
            config = .generic(url: url)
        }

        // Merge custom headers.
        let custom = parseHeaders()
        for (key, value) in custom {
            config.headers[key] = value
        }

        return config
    }

    /// Send a test webhook payload to verify the endpoint.
    private func sendTestWebhook() {
        guard let config = buildConfig() else {
            testResult = "Error: Invalid webhook URL."
            return
        }

        isSendingTest = true
        testResult = nil

        Task {
            do {
                let testJob = WebhookJobInfo(
                    fileName: "test_file.mp4",
                    profile: "Web Standard",
                    durationSeconds: 42.5,
                    outputSizeBytes: 104_857_600
                )
                let payload = WebhookPayload.now(
                    event: "test",
                    job: testJob,
                    status: "success"
                )
                try await WebhookSender.send(payload: payload, config: config)

                await MainActor.run {
                    testResult = "Test webhook sent successfully."
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
}

// MARK: - CustomHeadersEditor

/// A sheet for editing custom HTTP headers as key-value pairs.
struct CustomHeadersEditor: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    /// Binding to the JSON-encoded headers string in `AppStorage`.
    @Binding var headersJSON: String

    /// The in-progress header entries being edited.
    @State private var entries: [HeaderEntry] = []

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            Text("Custom HTTP Headers")
                .font(.headline)

            List {
                ForEach($entries) { $entry in
                    HStack {
                        TextField("Key", text: $entry.key)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 150)
                        TextField("Value", text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .onDelete(perform: deleteEntries)
            }
            .frame(minHeight: 100)

            Button {
                entries.append(HeaderEntry(key: "", value: ""))
            } label: {
                Label("Add Header", systemImage: "plus")
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveHeaders()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
        .onAppear { loadHeaders() }
    }

    // MARK: - Helpers

    /// Load headers from the JSON string into editable entries.
    private func loadHeaders() {
        guard !headersJSON.isEmpty,
              let data = headersJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        entries = dict.map { HeaderEntry(key: $0.key, value: $0.value) }
    }

    /// Save the edited entries back to the JSON string.
    private func saveHeaders() {
        let dict = Dictionary(
            entries.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        if let data = try? JSONEncoder().encode(dict),
           let json = String(data: data, encoding: .utf8) {
            headersJSON = json
        }
    }

    /// Delete header entries at the specified indices.
    ///
    /// - Parameter offsets: The index set of entries to remove.
    private func deleteEntries(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }
}

// MARK: - HeaderEntry

/// A single key-value header entry for the custom headers editor.
struct HeaderEntry: Identifiable {
    /// Unique identifier for SwiftUI list management.
    let id = UUID()
    /// The HTTP header name.
    var key: String
    /// The HTTP header value.
    var value: String
}
