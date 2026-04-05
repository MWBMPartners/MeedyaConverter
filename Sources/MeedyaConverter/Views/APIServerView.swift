// ============================================================================
// MeedyaConverter — APIServerView (Issue #355)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - APIServerViewModel
// ---------------------------------------------------------------------------
/// Observable view model for the REST API server management interface.
///
/// Wraps the `APIServer` from ConverterEngine, providing SwiftUI-friendly
/// state for the port configuration, server lifecycle, API key management,
/// and request log display.
///
/// Thread safety: `@MainActor`-isolated for safe SwiftUI binding.
@MainActor
@Observable
final class APIServerViewModel {

    // MARK: - Configuration

    /// The TCP port the server will listen on.
    var port: String = "8484"

    /// The bearer token for API authentication.
    var apiKey: String = ""

    // MARK: - State

    /// Whether the server is currently running.
    var isRunning: Bool = false

    /// Status message displayed in the UI.
    var statusMessage: String = "Server stopped"

    /// Error message from the last failed operation, if any.
    var errorMessage: String?

    /// Recent API request log entries for display.
    var requestLog: [APIRequestLogEntry] = []

    /// Whether the API key is visible in the UI (vs. masked).
    var isAPIKeyVisible: Bool = false

    // MARK: - Private

    /// The underlying API server instance.
    private var server: APIServer?

    /// Timer for polling the server's request log.
    private var logPollTimer: Timer?

    // MARK: - Lifecycle

    /// Generates a new random API key (32-character hex string).
    func generateAPIKey() {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        apiKey = bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Starts the API server with the current configuration.
    ///
    /// Validates the port number, creates an `APIServer` instance,
    /// and begins listening for connections.
    func startServer() {
        guard let portNumber = UInt16(port), portNumber > 0 else {
            errorMessage = "Invalid port number. Enter a value between 1 and 65535."
            return
        }

        guard !apiKey.isEmpty else {
            errorMessage = "API key is required. Generate or enter one before starting."
            return
        }

        errorMessage = nil

        let newServer = APIServer(port: portNumber, apiKey: apiKey)
        do {
            try newServer.start()
            server = newServer
            isRunning = true
            statusMessage = "Server running on port \(portNumber)"
            startLogPolling()
        } catch {
            errorMessage = "Failed to start server: \(error.localizedDescription)"
            statusMessage = "Server failed to start"
        }
    }

    /// Stops the running API server.
    func stopServer() {
        server?.stop()
        server = nil
        isRunning = false
        statusMessage = "Server stopped"
        stopLogPolling()
    }

    /// Toggles the server between running and stopped states.
    func toggleServer() {
        if isRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    // MARK: - Log Polling

    /// Starts a timer that polls the server's request log every second.
    private func startLogPolling() {
        logPollTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestLog = self?.server?.requestLog ?? []
            }
        }
    }

    /// Stops the log polling timer.
    private func stopLogPolling() {
        logPollTimer?.invalidate()
        logPollTimer = nil
    }

    /// Clears the displayed request log.
    func clearLog() {
        requestLog.removeAll()
    }
}

// ---------------------------------------------------------------------------
// MARK: - APIServerView
// ---------------------------------------------------------------------------
/// REST API server management interface.
///
/// Provides controls for configuring the server port, managing the API key,
/// starting/stopping the server, viewing the request log, and browsing
/// endpoint documentation.
///
/// Phase 12 — REST API Server Mode (Issue #355)
struct APIServerView: View {

    // MARK: - State

    /// View model managing the API server lifecycle.
    @State private var viewModel = APIServerViewModel()

    /// Whether the endpoint documentation section is expanded.
    @State private var showEndpointDocs: Bool = true

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                serverConfigSection
                serverControlSection
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }
                endpointDocumentationSection
                requestLogSection
            }
            .padding(20)
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            if viewModel.apiKey.isEmpty {
                viewModel.generateAPIKey()
            }
        }
    }

    // MARK: - Server Configuration

    /// Port and API key configuration fields.
    private var serverConfigSection: some View {
        GroupBox("Server Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                // Port
                HStack {
                    Text("Port:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("8484", text: $viewModel.port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .disabled(viewModel.isRunning)
                    Text("Default: 8484")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // API Key
                HStack {
                    Text("API Key:")
                        .frame(width: 80, alignment: .trailing)

                    if viewModel.isAPIKeyVisible {
                        TextField("API Key", text: $viewModel.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .disabled(viewModel.isRunning)
                    } else {
                        SecureField("API Key", text: $viewModel.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(viewModel.isRunning)
                    }

                    Button {
                        viewModel.isAPIKeyVisible.toggle()
                    } label: {
                        Image(systemName: viewModel.isAPIKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(viewModel.isAPIKeyVisible ? "Hide API key" : "Show API key")

                    Button("Generate") {
                        viewModel.generateAPIKey()
                    }
                    .disabled(viewModel.isRunning)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.apiKey, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy API key to clipboard")
                }
            }
            .padding(8)
        }
    }

    // MARK: - Server Control

    /// Start/stop toggle and status display.
    private var serverControlSection: some View {
        GroupBox("Server Status") {
            HStack(spacing: 16) {
                // Status indicator
                Circle()
                    .fill(viewModel.isRunning ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text(viewModel.statusMessage)
                    .font(.body)

                Spacer()

                Button {
                    viewModel.toggleServer()
                } label: {
                    Label(
                        viewModel.isRunning ? "Stop Server" : "Start Server",
                        systemImage: viewModel.isRunning ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRunning ? .red : .green)
            }
            .padding(8)
        }
    }

    // MARK: - Error Banner

    /// Displays an error message with a dismiss button.
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                viewModel.errorMessage = nil
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Endpoint Documentation

    /// Collapsible section documenting all available API endpoints.
    private var endpointDocumentationSection: some View {
        GroupBox {
            DisclosureGroup("API Endpoint Documentation", isExpanded: $showEndpointDocs) {
                VStack(alignment: .leading, spacing: 12) {
                    endpointRow(
                        method: "POST",
                        path: "/encode",
                        description: "Submit an encoding job. Body: {\"input\": \"path\", \"output\": \"path\", \"profile\": \"name\"}"
                    )
                    endpointRow(
                        method: "POST",
                        path: "/probe",
                        description: "Probe a media file. Body: {\"path\": \"/path/to/file\"}"
                    )
                    endpointRow(
                        method: "GET",
                        path: "/status",
                        description: "Server status and system information."
                    )
                    endpointRow(
                        method: "GET",
                        path: "/queue",
                        description: "Current encoding queue with job statuses."
                    )
                    endpointRow(
                        method: "GET",
                        path: "/profiles",
                        description: "List all available encoding profiles."
                    )

                    Divider()

                    Text("Authentication: Include header `Authorization: Bearer <api-key>`")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.isRunning, let portNum = UInt16(viewModel.port) {
                        Text("Base URL: http://localhost:\(portNum)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    /// A single endpoint documentation row.
    private func endpointRow(method: String, path: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(method)
                .font(.caption.bold().monospaced())
                .foregroundStyle(method == "POST" ? .orange : .green)
                .frame(width: 40, alignment: .trailing)

            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .leading)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Request Log

    /// Table displaying recent API requests and their responses.
    private var requestLogSection: some View {
        GroupBox("Request Log") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(viewModel.requestLog.count) requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearLog()
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.requestLog.isEmpty)
                }

                if viewModel.requestLog.isEmpty {
                    Text("No requests received yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    Table(viewModel.requestLog) {
                        TableColumn("Time") { entry in
                            Text(entry.timestamp, style: .time)
                                .font(.caption.monospaced())
                        }
                        .width(min: 70, ideal: 80)

                        TableColumn("Method") { entry in
                            Text(entry.method)
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(entry.method == "POST" ? .orange : .green)
                        }
                        .width(min: 50, ideal: 60)

                        TableColumn("Path") { entry in
                            Text(entry.path)
                                .font(.caption.monospaced())
                        }
                        .width(min: 80, ideal: 100)

                        TableColumn("Status") { entry in
                            Text("\(entry.statusCode)")
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.statusCode < 400 ? .green : .red)
                        }
                        .width(min: 50, ideal: 60)

                        TableColumn("Duration") { entry in
                            Text(String(format: "%.1f ms", entry.durationMs))
                                .font(.caption.monospaced())
                        }
                        .width(min: 60, ideal: 80)
                    }
                    .frame(minHeight: 150)
                }
            }
            .padding(8)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Preview
// ---------------------------------------------------------------------------
#if DEBUG
#Preview("API Server") {
    APIServerView()
        .frame(width: 700, height: 600)
}
#endif
