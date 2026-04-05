// ============================================================================
// MeedyaConverter — QualityCheckView (Issue #344)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - QualityCheckView
// ---------------------------------------------------------------------------
/// Automated quality-control interface for verifying media files against
/// configurable QC profiles.
///
/// Provides a profile picker (Broadcast, Streaming, Archive), a run
/// button, a results list with pass/fail badges and severity indicators,
/// and an export button for generating text-based QC reports.
///
/// Phase 14 — Automated QC Checks (Issue #344)
struct QualityCheckView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The currently selected built-in QC profile.
    @State private var selectedProfileName: String = "Broadcast"

    /// Results from the most recent QC run.
    @State private var results: [QCResult] = []

    /// Whether a QC analysis is currently in progress.
    @State private var isRunning = false

    /// Error message from the most recent operation, if any.
    @State private var errorMessage: String?

    /// Controls visibility of the export save panel.
    @State private var showExportPanel = false

    /// Available built-in profile names for the picker.
    private let profileNames = ["Broadcast", "Streaming", "Archive"]

    // MARK: - Computed Properties

    /// Returns the ``QCProfile`` matching the selected profile name.
    private var selectedProfile: QCProfile {
        switch selectedProfileName {
        case "Broadcast": return QualityChecker.broadcast
        case "Streaming": return QualityChecker.streaming
        case "Archive": return QualityChecker.archive
        default: return QualityChecker.broadcast
        }
    }

    /// Number of checks that passed in the current results.
    private var passCount: Int {
        results.filter(\.passed).count
    }

    /// Number of checks that failed in the current results.
    private var failCount: Int {
        results.filter { !$0.passed }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with profile picker and run button
            toolbar

            Divider()

            // Main content area
            if isRunning {
                runningView
            } else if !results.isEmpty {
                resultsList
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Toolbar

    /// Top toolbar with profile selection, run button, and export.
    private var toolbar: some View {
        HStack(spacing: 12) {
            // Profile picker
            Picker("QC Profile:", selection: $selectedProfileName) {
                ForEach(profileNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Spacer()

            // Run button
            Button {
                runQualityChecks()
            } label: {
                Label("Run QC", systemImage: "checkmark.shield")
            }
            .disabled(isRunning || viewModel.selectedFile == nil)
            .keyboardShortcut("r", modifiers: .command)

            // Export button
            Button {
                showExportPanel = true
            } label: {
                Label("Export Report", systemImage: "square.and.arrow.up")
            }
            .disabled(results.isEmpty)
            .fileExporter(
                isPresented: $showExportPanel,
                document: QCReportDocument(report: generateReport()),
                contentType: .plainText,
                defaultFilename: "QC_Report.txt"
            ) { result in
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Running View

    /// Progress indicator shown while QC checks are executing.
    private var runningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Running quality checks...")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Profile: \(selectedProfileName)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    /// Scrollable list of QC results with pass/fail badges.
    private var resultsList: some View {
        VStack(spacing: 0) {
            // Summary bar
            summaryBar

            Divider()

            // Results
            List(results) { result in
                resultRow(result)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    /// Summary bar showing pass/fail counts.
    private var summaryBar: some View {
        HStack(spacing: 16) {
            Label("\(passCount) Passed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Label("\(failCount) Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(failCount > 0 ? .red : .secondary)

            Spacer()

            Text("Profile: \(selectedProfileName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// A single result row with pass/fail badge, severity, and details.
    private func resultRow(_ result: QCResult) -> some View {
        HStack(spacing: 12) {
            // Pass/fail badge
            Image(systemName: result.passed
                  ? "checkmark.circle.fill"
                  : "xmark.circle.fill")
            .foregroundStyle(result.passed ? .green : .red)
            .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                // Check type
                Text(result.check.rawValue.replacingOccurrences(
                    of: "([A-Z])",
                    with: " $1",
                    options: .regularExpression
                ).capitalized)
                .font(.headline)

                // Details
                Text(result.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Severity badge
            severityBadge(result.severity)

            // Timestamp if available
            if let timestamp = result.timestamp {
                Text(String(format: "%.2fs", timestamp))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Coloured severity badge.
    private func severityBadge(_ severity: String) -> some View {
        Text(severity.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor(severity).opacity(0.15))
            .foregroundStyle(severityColor(severity))
            .clipShape(Capsule())
    }

    /// Maps severity string to a colour.
    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "error": return .red
        case "warning": return .orange
        default: return .blue
        }
    }

    // MARK: - Empty State

    /// Placeholder shown when no results are available.
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Quality Control")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Select a media file and QC profile, then click Run QC to check for issues.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Executes quality checks using the selected profile.
    private func runQualityChecks() {
        guard let file = viewModel.selectedFile else {
            errorMessage = "No file selected."
            return
        }

        isRunning = true
        errorMessage = nil

        // Run checks asynchronously to avoid blocking the main thread.
        Task {
            let checkResults = QualityChecker.runAllChecks(
                inputPath: file.fileURL.path,
                profile: selectedProfile
            )

            await MainActor.run {
                results = checkResults
                isRunning = false
            }
        }
    }

    /// Generates a plain-text QC report from the current results.
    private func generateReport() -> String {
        var lines: [String] = []
        lines.append("Quality Control Report")
        lines.append("Profile: \(selectedProfileName)")
        lines.append("Date: \(Date().formatted())")
        if let file = viewModel.selectedFile {
            lines.append("File: \(file.fileURL.path)")
        }
        lines.append(String(repeating: "-", count: 60))
        lines.append("")

        for result in results {
            let status = result.passed ? "PASS" : "FAIL"
            let ts = result.timestamp.map { String(format: " @ %.2fs", $0) } ?? ""
            lines.append("[\(status)] \(result.check.rawValue)\(ts)")
            lines.append("  Severity: \(result.severity)")
            lines.append("  \(result.details)")
            lines.append("")
        }

        lines.append(String(repeating: "-", count: 60))
        lines.append("Summary: \(passCount) passed, \(failCount) failed")

        return lines.joined(separator: "\n")
    }
}

// ---------------------------------------------------------------------------
// MARK: - QCReportDocument
// ---------------------------------------------------------------------------
/// A `FileDocument` wrapper for exporting QC reports as plain text.
///
/// Conforms to `FileDocument` so it can be used with SwiftUI's
/// `.fileExporter` modifier.
struct QCReportDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.plainText] }

    var report: String

    init(report: String) {
        self.report = report
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            report = String(data: data, encoding: .utf8) ?? ""
        } else {
            report = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(report.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
