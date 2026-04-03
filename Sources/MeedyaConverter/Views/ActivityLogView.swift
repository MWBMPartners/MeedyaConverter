// ============================================================================
// MeedyaConverter — ActivityLogView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI

// MARK: - ActivityLogView

/// Unified activity log showing structured application events.
///
/// Displays timestamped, colour-coded log entries filterable by
/// severity level. Supports searching and clearing the log.
struct ActivityLogView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var searchText = ""
    @State private var selectedLevel: LogEntry.Level?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            Divider()

            // Log entries
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No Log Entries",
                    systemImage: "text.page",
                    description: Text(viewModel.logEntries.isEmpty
                        ? "Activity will appear here as you use the app."
                        : "No entries match the current filter.")
                )
            } else {
                logList
            }
        }
        .navigationTitle("Activity Log")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear Log", systemImage: "trash") {
                    viewModel.logEntries.removeAll()
                }
                .disabled(viewModel.logEntries.isEmpty)
                .help("Clear all log entries")
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            // Search field
            TextField("Search log...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .accessibilityLabel("Search log entries")

            // Level filter chips
            filterChip("All", level: nil)
            filterChip("Info", level: .info)
            filterChip("Warn", level: .warning)
            filterChip("Error", level: .error)

            Spacer()

            // Entry count
            Text("\(filteredEntries.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func filterChip(_ label: String, level: LogEntry.Level?) -> some View {
        Button(label) {
            selectedLevel = level
        }
        .buttonStyle(.bordered)
        .tint(selectedLevel == level ? .accentColor : nil)
        .controlSize(.small)
    }

    // MARK: - Filtered Entries

    private var filteredEntries: [LogEntry] {
        viewModel.logEntries.filter { entry in
            // Level filter
            if let level = selectedLevel, entry.level != level {
                return false
            }
            // Search filter
            if !searchText.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    // MARK: - Log List

    private var logList: some View {
        List(filteredEntries.reversed()) { entry in
            logEntryRow(entry)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .font(.system(.caption, design: .monospaced))
    }

    private func logEntryRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(formatTimestamp(entry.timestamp))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            // Level icon
            Image(systemName: entry.level.systemImage)
                .foregroundStyle(entry.level.color)
                .frame(width: 16)

            // Level label
            Text(entry.level.rawValue)
                .foregroundStyle(entry.level.color)
                .fontWeight(.medium)
                .frame(width: 40, alignment: .leading)

            // Message
            Text(entry.message)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue): \(entry.message)")
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
