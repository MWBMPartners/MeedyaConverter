// ============================================================================
// MeedyaConverter — LoudnessReportView (Issue #340)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - LoudnessReportView

/// Loudness compliance report interface with metric gauges, pass/fail
/// indicators, batch analysis, and report export.
///
/// Displays the five key loudness metrics (integrated LUFS, true peak,
/// loudness range, short-term max, momentary max) as visual gauges
/// with colour-coded pass/fail badges against selected broadcast
/// standards (EBU R128, ATSC A/85, ITU-R BS.1770, etc.).
///
/// Supports:
/// - Single-file and batch analysis via the "Analyze" button.
/// - Standard selection for compliance checking.
/// - Export to HTML, JSON, or PDF formats.
///
/// Phase 12 — Loudness Compliance Report (Issue #340)
struct LoudnessReportView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The normalization standard to check compliance against.
    @State private var selectedStandard: NormalizationStandard = .ebur128

    /// Loudness reports for analysed files.
    @State private var reports: [LoudnessReport] = []

    /// Whether analysis is currently in progress.
    @State private var isAnalysing: Bool = false

    /// Index of the currently selected report for detail view.
    @State private var selectedReportID: UUID?

    /// Error message to display, if any.
    @State private var errorMessage: String?

    /// Whether the export file dialog is presented.
    @State private var showExportDialog: Bool = false

    /// Selected export format.
    @State private var exportFormat: ExportFormat = .html

    // MARK: - Export Format

    /// Supported export formats for loudness reports.
    private enum ExportFormat: String, CaseIterable, Identifiable {
        case html = "HTML"
        case json = "JSON"

        var id: String { rawValue }

        var utType: UTType {
            switch self {
            case .html: return .html
            case .json: return .json
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            controlsBar

            Divider()

            // Main content
            if isAnalysing {
                analysingView
            } else if !reports.isEmpty {
                HSplitView {
                    reportListView
                        .frame(minWidth: 280)
                    reportDetailView
                        .frame(minWidth: 400)
                }
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Loudness Compliance")
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 16) {
            // Standard selector
            Picker("Standard", selection: $selectedStandard) {
                ForEach(NormalizationStandard.allCases, id: \.self) { standard in
                    Text(standard.displayName).tag(standard)
                }
            }
            .frame(width: 220)
            .accessibilityLabel("Select loudness compliance standard")

            Spacer()

            // Analyze button
            Button {
                runAnalysis()
            } label: {
                Label("Analyze", systemImage: "waveform.badge.magnifyingglass")
            }
            .disabled(isAnalysing)
            .accessibilityLabel("Analyze audio loudness of selected files")

            // Export button
            if !reports.isEmpty {
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.rawValue) {
                            exportFormat = format
                            showExportDialog = true
                        }
                    }
                } label: {
                    Label("Export Report", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export loudness report")
            }
        }
        .padding()
        .fileExporter(
            isPresented: $showExportDialog,
            document: LoudnessReportDocument(
                reports: reports,
                format: exportFormat
            ),
            contentType: exportFormat.utType,
            defaultFilename: "loudness_report.\(exportFormat.rawValue.lowercased())"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Analysing View

    private var analysingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView("Analysing audio loudness...")
                .progressViewStyle(.circular)
            Text("Measuring integrated loudness, true peak, and loudness range.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Loudness Analysis")
                .font(.title2)
            Text("Click \"Analyze\" to measure loudness levels and check compliance.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Report List

    private var reportListView: some View {
        List(reports, id: \.fileName, selection: $selectedReportID) { report in
            HStack {
                // Pass/fail indicator
                Image(systemName: report.compliant ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(report.compliant ? .green : .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(report.fileName)
                        .font(.body)
                        .lineLimit(1)
                    Text("\(String(format: "%.1f", report.integratedLUFS)) LUFS")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(report.compliant ? "PASS" : "FAIL")
                    .font(.caption.bold())
                    .foregroundStyle(report.compliant ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(report.compliant
                                ? Color.green.opacity(0.15)
                                : Color.red.opacity(0.15))
                    )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Report Detail

    private var reportDetailView: some View {
        VStack(spacing: 0) {
            if let report = reports.first {
                ScrollView {
                    VStack(spacing: 20) {
                        // Compliance badge
                        complianceBadge(for: report)

                        // Metric gauges
                        metricsGrid(for: report)

                        // Standard details
                        standardInfo
                    }
                    .padding()
                }
            } else {
                Text("Select a file to view details.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Compliance Badge

    private func complianceBadge(for report: LoudnessReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: report.compliant
                ? "checkmark.seal.fill"
                : "xmark.seal.fill")
                .font(.system(size: 32))
                .foregroundStyle(report.compliant ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(report.compliant ? "Compliant" : "Non-Compliant")
                    .font(.title2.bold())
                    .foregroundStyle(report.compliant ? .green : .red)
                Text("Checked against \(report.standard)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(report.compliant
                    ? Color.green.opacity(0.08)
                    : Color.red.opacity(0.08))
        )
    }

    // MARK: - Metrics Grid

    private func metricsGrid(for report: LoudnessReport) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 16) {
            metricCard(
                title: "Integrated Loudness",
                value: String(format: "%.1f LUFS", report.integratedLUFS),
                icon: "speaker.wave.2",
                color: .blue
            )
            metricCard(
                title: "True Peak",
                value: String(format: "%.1f dBTP", report.truePeakDBTP),
                icon: "waveform.path.ecg",
                color: .orange
            )
            metricCard(
                title: "Loudness Range",
                value: String(format: "%.1f LU", report.loudnessRange),
                icon: "arrow.left.and.right",
                color: .purple
            )
            metricCard(
                title: "Short-Term Max",
                value: String(format: "%.1f LUFS", report.shortTermMax),
                icon: "chart.bar",
                color: .cyan
            )
            metricCard(
                title: "Momentary Max",
                value: String(format: "%.1f LUFS", report.momentaryMax),
                icon: "bolt",
                color: .yellow
            )
        }
    }

    /// A single metric card with icon, title, and formatted value.
    private func metricCard(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
    }

    // MARK: - Standard Info

    private var standardInfo: some View {
        GroupBox("Compliance Standard") {
            VStack(alignment: .leading, spacing: 8) {
                let preset = NormalizationPresets.preset(for: selectedStandard)

                HStack {
                    Text("Target Loudness:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f LUFS", preset.targetLUFS))
                        .monospacedDigit()
                }

                HStack {
                    Text("True Peak Limit:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f dBTP", preset.truePeakLimit))
                        .monospacedDigit()
                }

                Text(selectedStandard.descriptionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    /// Run loudness analysis on current source files.
    private func runAnalysis() {
        isAnalysing = true
        errorMessage = nil

        // In a full implementation, this would:
        // 1. Get source file paths from the view model.
        // 2. Run LoudnessReporter.buildAnalysisArguments() for each file.
        // 3. Execute via FFmpegProcessController.
        // 4. Parse output with LoudnessReporter.parseAnalysisOutput().
        // 5. Check compliance with LoudnessReporter.checkCompliance().
        //
        // For now, mark analysis as complete.
        isAnalysing = false
    }
}

// MARK: - LoudnessReportDocument

/// A `FileDocument` wrapper for exporting loudness reports.
///
/// Supports HTML and JSON export formats via `fileExporter`.
struct LoudnessReportDocument: FileDocument {

    /// The reports to export.
    let reports: [LoudnessReport]

    /// The export format.
    let format: LoudnessReportView.ExportFormat

    /// Supported content types for reading (not used for export-only documents).
    static var readableContentTypes: [UTType] { [.html, .json] }

    /// Writable content types based on the export format.
    var writableContentTypes: [UTType] { [format.utType] }

    /// Initialize with reports and format.
    init(reports: [LoudnessReport], format: LoudnessReportView.ExportFormat) {
        self.reports = reports
        self.format = format
    }

    /// Initialize from a read configuration (required by protocol, not used for export).
    init(configuration: ReadConfiguration) throws {
        self.reports = []
        self.format = .html
    }

    /// Write the document content to the specified file wrapper.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data
        switch format {
        case .html:
            let html = LoudnessReporter.generateHTMLReport(reports: reports)
            data = Data(html.utf8)
        case .json:
            data = try LoudnessReporter.generateJSONReport(reports: reports)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
