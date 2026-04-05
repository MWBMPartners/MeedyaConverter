// ============================================================================
// MeedyaConverter — StatisticsExportView (Issue #363)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - StatisticsExportView
// ---------------------------------------------------------------------------
/// View for exporting encoding statistics to CSV or JSON format.
///
/// Provides controls for:
/// - Selecting the export format (CSV or JSON).
/// - Filtering by date range (start and end dates).
/// - Choosing which columns to include in the CSV export.
/// - Previewing the export output before saving.
/// - Exporting via an NSSavePanel.
///
/// Phase 15 — Export Encoding Statistics to CSV (Issue #363)
struct StatisticsExportView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Types

    /// Supported export file formats.
    private enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
    }

    // MARK: - State

    /// The selected export format.
    @State private var exportFormat: ExportFormat = .csv

    /// Whether date range filtering is enabled.
    @State private var filterByDate: Bool = false

    /// The start date for the export range filter.
    @State private var startDate: Date = Calendar.current.date(
        byAdding: .month, value: -1, to: Date()
    ) ?? Date()

    /// The end date for the export range filter.
    @State private var endDate: Date = Date()

    /// The set of columns selected for CSV export.
    @State private var selectedColumns: Set<ExportColumn> = Set(ExportColumn.allCases)

    /// Whether the preview section is expanded.
    @State private var showPreview: Bool = false

    /// Status message after export attempt.
    @State private var statusMessage: String?

    // MARK: - Body

    var body: some View {
        Form {
            // -----------------------------------------------------------------
            // Format Selection
            // -----------------------------------------------------------------
            Section("Export Format") {
                Picker("Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
            }

            // -----------------------------------------------------------------
            // Date Range Filter
            // -----------------------------------------------------------------
            Section("Date Range") {
                Toggle("Filter by Date Range", isOn: $filterByDate)

                if filterByDate {
                    DatePicker(
                        "Start Date",
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "End Date",
                        selection: $endDate,
                        displayedComponents: .date
                    )
                }
            }

            // -----------------------------------------------------------------
            // Column Selection (CSV only)
            // -----------------------------------------------------------------
            if exportFormat == .csv {
                Section("Columns") {
                    ForEach(ExportColumn.allCases) { column in
                        Toggle(column.displayName, isOn: Binding(
                            get: { selectedColumns.contains(column) },
                            set: { isOn in
                                if isOn {
                                    selectedColumns.insert(column)
                                } else {
                                    selectedColumns.remove(column)
                                }
                            }
                        ))
                    }

                    HStack {
                        Button("Select All") {
                            selectedColumns = Set(ExportColumn.allCases)
                        }
                        Button("Deselect All") {
                            selectedColumns.removeAll()
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // Preview
            // -----------------------------------------------------------------
            Section("Preview") {
                DisclosureGroup("Export Preview", isExpanded: $showPreview) {
                    ScrollView {
                        Text(previewContent)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // -----------------------------------------------------------------
            // Export Button
            // -----------------------------------------------------------------
            Section {
                HStack {
                    Spacer()
                    Button("Export \(exportFormat.rawValue)...", action: exportData)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(exportFormat == .csv && selectedColumns.isEmpty)
                    Spacer()
                }

                if let status = statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.contains("Error") ? .red : .green)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Export Statistics")
    }

    // MARK: - Computed Properties

    /// Generates preview content based on the current export configuration.
    private var previewContent: String {
        let stats = EncodingStats()
        let history: [EncodeHistoryEntry] = []

        switch exportFormat {
        case .csv:
            let columns = ExportColumn.allCases.filter { selectedColumns.contains($0) }
            return StatisticsExporter.exportAsCSV(
                stats: stats,
                history: history,
                columns: columns,
                startDate: filterByDate ? startDate : nil,
                endDate: filterByDate ? endDate : nil
            )
        case .json:
            if let data = try? StatisticsExporter.exportAsJSON(stats: stats),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return "{ }"
        }
    }

    // MARK: - Actions

    /// Presents an NSSavePanel and writes the exported data to the chosen location.
    private func exportData() {
        let panel = NSSavePanel()
        panel.title = "Export Statistics"

        switch exportFormat {
        case .csv:
            panel.nameFieldStringValue = "encoding_statistics.csv"
            panel.allowedContentTypes = [UTType.commaSeparatedText]
        case .json:
            panel.nameFieldStringValue = "encoding_statistics.json"
            panel.allowedContentTypes = [UTType.json]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let stats = EncodingStats()
            let history: [EncodeHistoryEntry] = []

            let content: String
            switch exportFormat {
            case .csv:
                let columns = ExportColumn.allCases.filter { selectedColumns.contains($0) }
                content = StatisticsExporter.exportAsCSV(
                    stats: stats,
                    history: history,
                    columns: columns,
                    startDate: filterByDate ? startDate : nil,
                    endDate: filterByDate ? endDate : nil
                )
            case .json:
                let data = try StatisticsExporter.exportAsJSON(stats: stats)
                content = String(data: data, encoding: .utf8) ?? "{ }"
            }

            try content.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Exported to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}
