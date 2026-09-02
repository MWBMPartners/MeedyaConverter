// ============================================================================
// MeedyaConverter — StorageAnalysisView (Issue #365)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - StorageAnalysisView

/// Provides a folder picker, a scan/probe progress indicator with Cancel,
/// and breakdown lists (by codec, resolution, container).
///
/// `performScan()` runs `StorageAnalyzer.scanDirectory` (file-system facts +
/// file-name guesses) then `StorageAnalyzer.probeFiles` with a real
/// `FFmpegProbe` resolved via `viewModel.engine.bundleManager` (the app's
/// ffmpeg/ffprobe location, honouring any Settings override) to replace
/// those guesses with real codec/resolution/HDR/duration data. When ffprobe
/// cannot be located, or cannot read a given file, the file-name guess is
/// kept and the report's caption says so.
///
/// Phase 13 — Issue #365
struct StorageAnalysisView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The selected directory URL to scan.
    @State private var selectedDirectory: URL?

    /// Whether to scan subdirectories recursively.
    @State private var scanRecursively = true

    /// Whether a scan is currently in progress.
    @State private var isScanning = false

    /// The list of analysed files from the most recent scan. Read by
    /// `provenanceCaption` to report how many were read by ffprobe.
    @State private var analysedFiles: [FileAnalysis] = []

    /// The generated storage report.
    @State private var report: StorageReport?

    /// The currently selected breakdown tab.
    @State private var selectedBreakdown: BreakdownTab = .codec

    /// Whether to show the folder-picker panel.
    @State private var showFolderPicker = false

    /// Fraction (0...1) of the ffprobe pass completed, or `nil` while the
    /// file-system scan is still running (before probing starts).
    @State private var probeProgress: Double?

    /// Total number of files being probed, for the progress caption.
    @State private var probeTotal = 0

    /// Whether ffprobe was located for the most recent (or in-progress) scan.
    @State private var ffprobeLocated = false

    /// The in-flight `performScan()` task, retained so Cancel / `onDisappear`
    /// can cancel it.
    @State private var scanTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header: folder selection and scan controls.
            scanHeader
                .padding()

            Divider()

            // Main content: report or empty state.
            if let report {
                reportContent(report)
            } else if isScanning {
                scanningIndicator
            } else {
                emptyState
            }
        }
        .navigationTitle("Storage Analysis")
        .onDisappear {
            scanTask?.cancel()
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                selectedDirectory = url
            }
        }
    }

    // MARK: - Scan Header

    private var scanHeader: some View {
        HStack(spacing: 12) {
            // Folder selection.
            Button {
                showFolderPicker = true
            } label: {
                Label("Choose Folder", systemImage: "folder")
            }

            if let dir = selectedDirectory {
                Text(dir.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Toggle("Recursive", isOn: $scanRecursively)
                .toggleStyle(.checkbox)

            Spacer()

            if isScanning {
                Button(role: .cancel) {
                    scanTask?.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            } else {
                Button {
                    scanTask = Task { await performScan() }
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                }
                .disabled(selectedDirectory == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Storage Analysis",
            systemImage: "internaldrive",
            description: Text("Choose a folder and scan to analyse media storage usage.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Scanning Indicator

    @ViewBuilder
    private var scanningIndicator: some View {
        if let probeProgress {
            VStack(spacing: 16) {
                ProgressView(value: probeProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 320)
                Text("Reading \(probeTotal) files with ffprobe… \(Int(probeProgress * 100))%")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Scanning media files...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Report Content

    @ViewBuilder
    private func reportContent(_ report: StorageReport) -> some View {
        VStack(spacing: 0) {
            // Summary bar.
            summaryBar(report)
                .padding()

            if let caption = provenanceCaption {
                Label(caption.text, systemImage: caption.isWarning ? "exclamationmark.triangle" : "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(caption.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            Divider()

            // Breakdown tabs.
            Picker("Breakdown", selection: $selectedBreakdown) {
                ForEach(BreakdownTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Breakdown list.
            breakdownList(report)
        }
    }

    // MARK: - Summary Bar

    private func summaryBar(_ report: StorageReport) -> some View {
        HStack(spacing: 24) {
            summaryItem(
                title: "Files",
                value: "\(report.totalFiles)",
                icon: "doc.fill"
            )
            summaryItem(
                title: "Total Size",
                value: report.formattedTotalSize,
                icon: "internaldrive.fill"
            )
            summaryItem(
                title: "Codecs",
                value: "\(report.byCodec.count)",
                icon: "film"
            )
            summaryItem(
                title: "Containers",
                value: "\(report.byContainer.count)",
                icon: "shippingbox"
            )

            Spacer()
        }
    }

    private func summaryItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Breakdown List

    private func breakdownList(_ report: StorageReport) -> some View {
        let items: [(key: String, count: Int, size: Int64)] = {
            switch selectedBreakdown {
            case .codec:
                return report.byCodec.map { (key: $0.key, count: $0.value.count, size: $0.value.size) }
                    .sorted { $0.size > $1.size }
            case .resolution:
                return report.byResolution.map { (key: $0.key, count: $0.value.count, size: $0.value.size) }
                    .sorted { $0.size > $1.size }
            case .container:
                return report.byContainer.map { (key: $0.key, count: $0.value.count, size: $0.value.size) }
                    .sorted { $0.size > $1.size }
            }
        }()

        return List {
            ForEach(items, id: \.key) { item in
                breakdownRow(
                    label: item.key,
                    count: item.count,
                    size: item.size,
                    totalSize: report.totalSize
                )
            }
        }
        .listStyle(.inset)
    }

    private func breakdownRow(label: String, count: Int, size: Int64, totalSize: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label.uppercased())
                    .font(.headline)

                Spacer()

                Text("\(count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formatBytes(size))
                    .font(.callout.bold())
            }

            // Proportional bar.
            GeometryReader { geometry in
                let fraction = totalSize > 0 ? CGFloat(size) / CGFloat(totalSize) : 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(.blue.opacity(0.3))
                    .frame(width: geometry.size.width * fraction)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.blue)
                            .frame(width: geometry.size.width * fraction)
                    }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Provenance

    /// Caption describing how many analysed files' codec/resolution/HDR came
    /// from a real ffprobe read versus a file-name guess. `nil` before any
    /// scan has completed.
    private var provenanceCaption: (text: String, isWarning: Bool)? {
        guard report != nil, !analysedFiles.isEmpty else { return nil }
        let total = analysedFiles.count
        let probed = analysedFiles.filter { $0.provenance == .probed }.count
        if !ffprobeLocated {
            return ("ffprobe was not found — codec, resolution and HDR are guessed from file names.", true)
        }
        if probed == total {
            return ("Codec, resolution and HDR were read by ffprobe for all \(total) files.", false)
        }
        return ("\(probed) of \(total) files were read by ffprobe; \(total - probed) could not be read and are guessed from file names.", true)
    }

    // MARK: - Actions

    /// Perform the directory scan asynchronously: `StorageAnalyzer
    /// .scanDirectory` for file-system facts and file-name guesses, then
    /// (when ffprobe can be located) `StorageAnalyzer.probeFiles` to replace
    /// those guesses with real ffprobe data, with progress reported via
    /// `probeProgress`.
    private func performScan() async {
        guard let directory = selectedDirectory else { return }

        isScanning = true
        report = nil
        analysedFiles = []
        probeProgress = nil
        probeTotal = 0
        ffprobeLocated = false

        let accessing = directory.startAccessingSecurityScopedResource()
        defer {
            if accessing { directory.stopAccessingSecurityScopedResource() }
            isScanning = false
        }

        let scanned = await StorageAnalyzer.scanDirectory(at: directory, recursive: scanRecursively)
        guard !Task.isCancelled else { return }

        let bundleManager = viewModel.engine.bundleManager
        let ffprobePath: String? = await Task.detached {
            try? bundleManager.locateFFprobe().path
        }.value
        guard !Task.isCancelled else { return }

        let files: [FileAnalysis]
        if let ffprobePath {
            ffprobeLocated = true
            probeTotal = scanned.count
            probeProgress = 0
            files = await StorageAnalyzer.probeFiles(
                scanned,
                using: FFmpegProbe(ffprobePath: ffprobePath)
            ) { fraction in
                Task { @MainActor in self.probeProgress = fraction }
            }
        } else {
            files = scanned
        }
        guard !Task.isCancelled else { return }

        analysedFiles = files
        report = StorageAnalyzer.generateReport(files: files)
    }

    // MARK: - Formatting

    /// Format a byte count to a human-readable string.
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - BreakdownTab

/// Tab selection for the storage breakdown view.
private enum BreakdownTab: String, CaseIterable {
    case codec
    case resolution
    case container

    var label: String {
        switch self {
        case .codec:      return "By Codec"
        case .resolution: return "By Resolution"
        case .container:  return "By Container"
        }
    }
}
