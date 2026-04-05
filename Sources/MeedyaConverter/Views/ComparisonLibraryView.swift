// ============================================================================
// MeedyaConverter — ComparisonLibraryView (Issue #329)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - ComparisonLibraryView

/// Displays a grid of captured comparison frames, grouped by source file,
/// with side-by-side comparison, zoom, overlay with profile info and file
/// size, and VMAF score when available.
///
/// Phase 13 — Issue #329
struct ComparisonLibraryView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// All persisted comparison entries loaded from disk.
    @State private var entries: [ComparisonEntry] = []

    /// Search filter text.
    @State private var searchText = ""

    /// The entry currently selected for detail viewing.
    @State private var selectedEntry: ComparisonEntry?

    /// Entries selected for side-by-side comparison (max 2).
    @State private var comparisonSelection: Set<UUID> = []

    /// Whether the side-by-side comparison sheet is presented.
    @State private var showComparison = false

    /// Zoom scale factor for the detail view.
    @State private var zoomScale: CGFloat = 1.0

    /// Whether to show the overlay with profile info and metrics.
    @State private var showOverlay = true

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sourceFileSidebar
        } detail: {
            if let selected = selectedEntry {
                entryDetailView(selected)
            } else if showComparison, comparisonPair.count == 2 {
                sideBySideView
            } else {
                emptyState
            }
        }
        .navigationTitle("Comparison Library")
        .searchable(text: $searchText, prompt: "Search by source file or profile")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarControls
            }
        }
    }

    // MARK: - Source File Sidebar

    private var sourceFileSidebar: some View {
        List(selection: $selectedEntry) {
            ForEach(groupedBySource.keys.sorted(), id: \.self) { sourceFile in
                Section(sourceFile) {
                    if let group = groupedBySource[sourceFile] {
                        ForEach(group) { entry in
                            sidebarRow(entry)
                                .tag(entry)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(_ entry: ComparisonEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.profileName)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(entry.settingsSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(entry.formattedFileSize)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            // Selection indicator for comparison mode.
            if comparisonSelection.contains(entry.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedEntry = entry
        }
        .contextMenu {
            Button("Select for Comparison") {
                toggleComparisonSelection(entry)
            }
            Button("Remove from Library", role: .destructive) {
                removeEntry(entry)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Comparison Frames",
            systemImage: "photo.on.rectangle.angled",
            description: Text("Capture frames during encoding to compare quality across profiles.")
        )
    }

    // MARK: - Entry Detail View

    private func entryDetailView(_ entry: ComparisonEntry) -> some View {
        VStack(spacing: 0) {
            // Frame image with zoom.
            frameImageView(entry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Metadata overlay bar.
            if showOverlay {
                entryMetadataBar(entry)
                    .padding()
            }
        }
    }

    private func frameImageView(_ entry: ComparisonEntry) -> some View {
        Group {
            let imageURL = URL(fileURLWithPath: entry.framePath)
            if let nsImage = NSImage(contentsOf: imageURL) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoomScale = max(0.5, min(5.0, value.magnification))
                        }
                )
            } else {
                ContentUnavailableView(
                    "Frame Not Found",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("The captured frame file could not be loaded from:\n\(entry.framePath)")
                )
            }
        }
    }

    private func entryMetadataBar(_ entry: ComparisonEntry) -> some View {
        HStack(spacing: 20) {
            metadataItem(label: "Profile", value: entry.profileName)
            metadataItem(label: "Codec", value: entry.codec.uppercased())

            if let crf = entry.crf {
                metadataItem(label: "CRF", value: "\(crf)")
            }

            if let bitrate = entry.bitrate {
                let mbps = Double(bitrate) / 1_000_000.0
                metadataItem(label: "Bitrate", value: String(format: "%.1f Mbps", mbps))
            }

            metadataItem(label: "File Size", value: entry.formattedFileSize)

            metadataItem(label: "Timestamp", value: formatTimestamp(entry.timestamp))

            if let vmaf = entry.vmafScore {
                metadataItem(label: "VMAF", value: String(format: "%.1f", vmaf))
            }

            Spacer()

            // Zoom controls.
            HStack(spacing: 4) {
                Button {
                    zoomScale = max(0.5, zoomScale - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Text("\(Int(zoomScale * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 40)

                Button {
                    zoomScale = min(5.0, zoomScale + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func metadataItem(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.callout.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Side-by-Side Comparison

    private var sideBySideView: some View {
        let pair = comparisonPair
        guard pair.count == 2 else { return AnyView(emptyState) }

        let left = pair[0]
        let right = pair[1]

        return AnyView(
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    VStack {
                        frameImageView(left)
                        entryMetadataBar(left)
                            .padding(8)
                    }
                    .background(.background)

                    VStack {
                        frameImageView(right)
                        entryMetadataBar(right)
                            .padding(8)
                    }
                    .background(.background)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }

    // MARK: - Toolbar

    private var toolbarControls: some View {
        Group {
            Toggle(isOn: $showOverlay) {
                Label("Info Overlay", systemImage: "info.circle")
            }
            .toggleStyle(.button)

            Button {
                if comparisonPair.count == 2 {
                    selectedEntry = nil
                    showComparison = true
                }
            } label: {
                Label("Compare", systemImage: "square.split.2x1")
            }
            .disabled(comparisonSelection.count != 2)
            .help("Select exactly 2 entries for side-by-side comparison")
        }
    }

    // MARK: - Computed Properties

    /// Entries filtered by search text.
    private var filteredEntries: [ComparisonEntry] {
        if searchText.isEmpty {
            return entries
        }
        let query = searchText.lowercased()
        return entries.filter { entry in
            entry.sourceFileName.lowercased().contains(query)
                || entry.profileName.lowercased().contains(query)
                || entry.codec.lowercased().contains(query)
        }
    }

    /// Entries grouped by source file name.
    private var groupedBySource: [String: [ComparisonEntry]] {
        Dictionary(grouping: filteredEntries, by: \.sourceFileName)
    }

    /// The two entries selected for side-by-side comparison.
    private var comparisonPair: [ComparisonEntry] {
        entries.filter { comparisonSelection.contains($0.id) }
    }

    // MARK: - Actions

    /// Toggle whether an entry is included in the comparison pair.
    private func toggleComparisonSelection(_ entry: ComparisonEntry) {
        if comparisonSelection.contains(entry.id) {
            comparisonSelection.remove(entry.id)
        } else {
            // Limit to 2 selections; remove oldest if adding a third.
            if comparisonSelection.count >= 2 {
                comparisonSelection.removeFirst()
            }
            comparisonSelection.insert(entry.id)
        }
    }

    /// Remove a comparison entry from the library.
    private func removeEntry(_ entry: ComparisonEntry) {
        entries.removeAll { $0.id == entry.id }
        comparisonSelection.remove(entry.id)
        if selectedEntry?.id == entry.id {
            selectedEntry = nil
        }
    }

    // MARK: - Formatting

    /// Format a timestamp in seconds to a display string (e.g., "1:23.4").
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", minutes, secs)
    }
}
