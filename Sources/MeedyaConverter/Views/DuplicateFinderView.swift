// ============================================================================
// MeedyaConverter — DuplicateFinderView (Issue #290)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - DuplicateFinderView

/// Provides a folder picker, scan method selector, results grouped by duplicate
/// sets, keep/delete toggles, and a total recoverable space display.
///
/// Phase 11 — Duplicate File Detection (Issue #290)
struct DuplicateFinderView: View {

    // MARK: - State

    /// The selected directory URL to scan for duplicates.
    @State private var selectedDirectory: URL?

    /// The chosen matching algorithm.
    @State private var selectedMethod: MatchType = .exactHash

    /// Whether a scan is currently in progress.
    @State private var isScanning = false

    /// The discovered duplicate groups from the most recent scan.
    @State private var duplicateGroups: [DuplicateGroup] = []

    /// Tracks which file URLs the user has marked for deletion.
    @State private var markedForDeletion: Set<URL> = []

    /// An error message to display, if any.
    @State private var errorMessage: String?

    // MARK: - Computed Properties

    /// The total recoverable disk space from files marked for deletion (in bytes).
    private var recoverableBytes: Int64 {
        var total: Int64 = 0
        for url in markedForDeletion {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    /// Human-readable representation of recoverable space.
    private var recoverableLabel: String {
        ByteCountFormatter.string(fromByteCount: recoverableBytes, countStyle: .file)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            controlsSection
            if isScanning {
                ProgressView("Scanning for duplicates…")
                    .padding()
            }
            if !duplicateGroups.isEmpty {
                resultsSection
                footerSection
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Header

    /// Title and description area.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duplicate Finder")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Scan a folder to find duplicate media files and recover disk space.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    /// Folder picker, method selector, and scan button.
    private var controlsSection: some View {
        HStack(spacing: 12) {
            Button("Choose Folder…") {
                chooseFolder()
            }

            if let dir = selectedDirectory {
                Text(dir.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            Picker("Method:", selection: $selectedMethod) {
                ForEach(MatchType.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)

            Button("Scan") {
                Task { await performScan() }
            }
            .disabled(selectedDirectory == nil || isScanning)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Results

    /// Lists duplicate groups with keep/delete toggles.
    private var resultsSection: some View {
        List {
            ForEach(duplicateGroups) { group in
                Section {
                    ForEach(group.files, id: \.self) { url in
                        HStack {
                            Toggle(isOn: deletionBinding(for: url)) {
                                VStack(alignment: .leading) {
                                    Text(url.lastPathComponent)
                                        .fontWeight(.medium)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(fileSizeLabel(for: url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Group — \(group.matchType.rawValue) (\(group.files.count) files)")
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Footer

    /// Shows recoverable space and a delete button.
    private var footerSection: some View {
        HStack {
            Text("Recoverable space: \(recoverableLabel)")
                .fontWeight(.medium)
            Spacer()
            Button("Delete Marked Files", role: .destructive) {
                deleteMarkedFiles()
            }
            .disabled(markedForDeletion.isEmpty)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    /// Presents an open panel to choose a directory.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan for duplicate files."
        if panel.runModal() == .OK {
            selectedDirectory = panel.url
            duplicateGroups = []
            markedForDeletion = []
        }
    }

    /// Enumerates files in the selected directory and runs the duplicate detector.
    private func performScan() async {
        guard let directory = selectedDirectory else { return }
        isScanning = true
        duplicateGroups = []
        markedForDeletion = []
        errorMessage = nil

        let fileURLs = collectFiles(in: directory)

        let results = await DuplicateDetector.findDuplicates(in: fileURLs, method: selectedMethod)
        duplicateGroups = results
        isScanning = false
    }

    /// Synchronously enumerates regular files in the given directory.
    ///
    /// Separated from the `async` scan method to avoid Swift 6 concurrency
    /// restrictions on `NSDirectoryEnumerator.makeIterator()`.
    private func collectFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        var fileURLs: [URL] = []
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let url = enumerator.nextObject() as? URL {
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
               values.isRegularFile == true {
                fileURLs.append(url)
            }
        }
        return fileURLs
    }

    /// Moves marked files to the Trash.
    private func deleteMarkedFiles() {
        for url in markedForDeletion {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        markedForDeletion = []
        // Re-scan to refresh results.
        Task { await performScan() }
    }

    // MARK: - Helpers

    /// Creates a binding that toggles membership of a URL in `markedForDeletion`.
    private func deletionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { markedForDeletion.contains(url) },
            set: { isMarked in
                if isMarked {
                    markedForDeletion.insert(url)
                } else {
                    markedForDeletion.remove(url)
                }
            }
        )
    }

    /// Returns a human-readable file-size label for the given URL.
    private func fileSizeLabel(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
