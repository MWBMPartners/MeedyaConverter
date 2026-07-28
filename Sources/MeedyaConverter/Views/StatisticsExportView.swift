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
/// - Previewing the export output before saving.
/// - Exporting via an NSSavePanel.
///
/// Reads from `EncodingStatisticsStore` — the single source of truth for
/// encoding statistics (Issue #284, re #363) — rather than fabricating
/// empty data. No column picker: `EncodingStatisticsStore.exportAsCSV()`/
/// `exportAsJSON()` always emit the full, real per-job record (see
/// `EncodingStatistics.csvHeader`/`csvRow`).
///
/// Phase 15 — Export Encoding Statistics to CSV (Issue #363)
struct StatisticsExportView: View {

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

    /// Whether the preview section is expanded.
    @State private var showPreview: Bool = false

    /// Status message after export attempt.
    @State private var statusMessage: String?

    /// Persisted history of completed encoding job statistics, backing the
    /// export below. Real, already-tested component
    /// (`EncodingStatisticsStore` in `ConverterEngine`) — reads its JSON
    /// history from disk in its initializer, the same way
    /// `EncodingGraphsView` seeds its `@State` directly from a fresh
    /// instance (Issue #284, re #363).
    @State private var statisticsStore = EncodingStatisticsStore()

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
                        .disabled(statisticsStore.allStatistics.isEmpty)
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
        .onAppear {
            // Reload from disk each time this view appears so a job
            // completed since the store was last constructed shows up.
            // `EncodingStatisticsStore` only reads its history file inside
            // `init()`, so a fresh instance is how a re-read happens. Kept
            // off the main actor via `Task.detached`, mirroring
            // `EncodingGraphsView.onAppear`.
            Task {
                statisticsStore = await Task.detached {
                    EncodingStatisticsStore()
                }.value
            }
        }
    }

    // MARK: - Computed Properties

    /// Generates preview content based on the current export configuration.
    private var previewContent: String {
        switch exportFormat {
        case .csv:
            let data = statisticsStore.exportAsCSV(
                startDate: filterByDate ? startDate : nil,
                endDate: filterByDate ? endDate : nil
            )
            return String(data: data, encoding: .utf8) ?? ""
        case .json:
            if let data = try? statisticsStore.exportAsJSON(
                startDate: filterByDate ? startDate : nil,
                endDate: filterByDate ? endDate : nil
            ), let string = String(data: data, encoding: .utf8) {
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
            let data: Data
            switch exportFormat {
            case .csv:
                data = statisticsStore.exportAsCSV(
                    startDate: filterByDate ? startDate : nil,
                    endDate: filterByDate ? endDate : nil
                )
            case .json:
                data = try statisticsStore.exportAsJSON(
                    startDate: filterByDate ? startDate : nil,
                    endDate: filterByDate ? endDate : nil
                )
            }

            try data.write(to: url, options: .atomic)
            statusMessage = "Exported to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}
