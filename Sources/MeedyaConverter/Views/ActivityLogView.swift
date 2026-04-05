// ============================================================================
// MeedyaConverter — ActivityLogView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers

// MARK: - ActivityLogView

/// Unified activity log showing structured application events and raw
/// FFmpeg/tool output in a single filterable panel.
///
/// Supports filtering by severity level and source category, keyword
/// search, export as text/JSON, and colour-coded entries. FFmpeg output
/// is displayed in monospace; app events use the standard font.
struct ActivityLogView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var searchText = ""
    @State private var selectedLevel: LogEntry.Level?
    @State private var selectedSource: LogEntry.Source?
    @State private var autoScroll = true

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
            ToolbarItemGroup(placement: .automatic) {
                logToolbar
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            // Search field
            TextField("Search log...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)
                .accessibilityLabel("Search log entries")

            Divider().frame(height: 20)

            // Level filter
            levelFilterChip("All", level: nil)
            levelFilterChip("Info", level: .info)
            levelFilterChip("Warn", level: .warning)
            levelFilterChip("Error", level: .error)

            Divider().frame(height: 20)

            // Source filter
            sourceFilterChip("All Sources", source: nil)
            sourceFilterChip("App", source: .app)
            sourceFilterChip("FFmpeg", source: .ffmpeg)

            Spacer()

            // Auto-scroll toggle
            Toggle(isOn: $autoScroll) {
                Image(systemName: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .help(autoScroll ? "Auto-scroll enabled" : "Auto-scroll disabled")

            // Entry count
            Text("\(filteredEntries.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func levelFilterChip(_ label: String, level: LogEntry.Level?) -> some View {
        Button(label) {
            selectedLevel = level
        }
        .buttonStyle(.bordered)
        .tint(selectedLevel == level ? .accentColor : nil)
        .controlSize(.small)
    }

    private func sourceFilterChip(_ label: String, source: LogEntry.Source?) -> some View {
        Button(label) {
            selectedSource = source
        }
        .buttonStyle(.bordered)
        .tint(selectedSource == source ? .accentColor : nil)
        .controlSize(.small)
    }

    // MARK: - Filtered Entries

    private var filteredEntries: [LogEntry] {
        viewModel.logEntries.filter { entry in
            if let level = selectedLevel, entry.level != level {
                return false
            }
            if let source = selectedSource, entry.source != source {
                return false
            }
            if !searchText.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollViewReader { proxy in
            List(filteredEntries) { entry in
                logEntryRow(entry)
                    .id(entry.id)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: viewModel.logEntries.count) { _, _ in
                if autoScroll, let last = filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logEntryRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(formatTimestamp(entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            // Level icon
            Image(systemName: entry.level.systemImage)
                .foregroundStyle(entry.level.color)
                .frame(width: 16)

            // Source badge
            Text(entry.source.rawValue.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(sourceColor(entry.source))
                .frame(width: 50, alignment: .leading)

            // Message — monospace for FFmpeg output, regular for app events
            if entry.source == .ffmpeg {
                Text(entry.rawOutput ?? entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            } else {
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(entry.level.color)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue): \(entry.message)")
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var logToolbar: some View {
        // Export as text
        Button("Export Text", systemImage: "doc.text") {
            exportAsText()
        }
        .disabled(viewModel.logEntries.isEmpty)
        .help("Export log as plain text file")

        // Export as JSON
        Button("Export JSON", systemImage: "doc.badge.arrow.up") {
            exportAsJSON()
        }
        .disabled(viewModel.logEntries.isEmpty)
        .help("Export log as JSON file")

        // Copy to clipboard
        Button("Copy", systemImage: "doc.on.doc") {
            let text = viewModel.exportLogAsText()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        .disabled(viewModel.logEntries.isEmpty)
        .help("Copy log to clipboard")

        // Clear
        Button("Clear", systemImage: "trash") {
            viewModel.logEntries.removeAll()
        }
        .disabled(viewModel.logEntries.isEmpty)
        .help("Clear all log entries")
    }

    // MARK: - Export

    private func exportAsText() {
        let panel = NSSavePanel()
        panel.title = "Export Log"
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "meedya_log_\(formattedDate()).txt"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = viewModel.exportLogAsText()
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportAsJSON() {
        let panel = NSSavePanel()
        panel.title = "Export Log as JSON"
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "meedya_log_\(formattedDate()).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let data = try? viewModel.exportLogAsJSON() {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }

    private func sourceColor(_ source: LogEntry.Source) -> Color {
        switch source {
        case .app: return .blue
        case .ffmpeg: return .secondary
        case .mediainfo: return .purple
        case .doviTool: return .orange
        case .hlgTools: return .teal
        case .system: return .green
        }
    }
}
