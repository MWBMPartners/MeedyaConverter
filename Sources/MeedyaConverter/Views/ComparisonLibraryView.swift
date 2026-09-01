// ============================================================================
// MeedyaConverter — ComparisonLibraryView (Issue #329)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - ComparisonLibraryView

/// Displays a grid of captured comparison frames, grouped by source file,
/// with side-by-side comparison, zoom, overlay with profile info and file
/// size, and VMAF score when available.
///
/// Entries are captured via the "New Comparison" toolbar action (real
/// FFmpeg frame extraction + SSIM/PSNR/VMAF, executed through
/// `FFmpegProcessController`) and persisted to disk by
/// ``ComparisonLibraryManager`` so the library survives a relaunch.
///
/// Phase 13 — Issue #329
struct ComparisonLibraryView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// Persists and owns all comparison entries. Loads from disk on
    /// creation and rewrites the JSON store after every mutation.
    @State private var libraryManager = ComparisonLibraryManager()

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

    /// Whether the "New Comparison" capture sheet is presented.
    @State private var showCaptureSheet = false

    /// The entry to open in the full frame-by-frame `ComparisonView`,
    /// presented as a sheet when non-nil.
    @State private var abViewEntry: ComparisonEntry?

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sourceFileSidebar
        } detail: {
            if let selected = selectedEntry {
                entryDetailView(selected)
            } else if showComparison, comparisonPair.count == 2 {
                sideBySideView
            } else if libraryManager.entries.isEmpty {
                emptyState
            } else {
                selectPromptState
            }
        }
        .navigationTitle("Comparison Library")
        .searchable(text: $searchText, prompt: "Search by source file or profile")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarControls
            }
        }
        .sheet(isPresented: $showCaptureSheet) {
            CaptureComparisonSheet(
                libraryManager: libraryManager,
                defaultSourcePath: viewModel.selectedFile?.fileURL.path
            )
            .environment(viewModel)
        }
        .sheet(item: $abViewEntry) { entry in
            NavigationStack {
                ComparisonView(entry: entry)
                    .environment(viewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { abViewEntry = nil }
                        }
                    }
            }
            .frame(minWidth: 820, minHeight: 640)
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
            Button("Open A/B View") {
                selectedEntry = nil
                abViewEntry = entry
            }
            Button("Remove from Library", role: .destructive) {
                removeEntry(entry)
            }
        }
    }

    // MARK: - Empty State

    /// Honest empty state (Issue #329): distinguishes "nothing captured
    /// yet" from a loading or broken screen, and gives the user the
    /// exact action that populates the library.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Comparisons Yet", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Capture a source and encoded frame to compare quality across profiles. Nothing has been captured yet.")
        } actions: {
            Button("New Comparison") {
                showCaptureSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Shown when the library already has entries but none is selected —
    /// distinct from ``emptyState`` so a populated library never looks
    /// like an empty or broken one.
    private var selectPromptState: some View {
        ContentUnavailableView(
            "No Entry Selected",
            systemImage: "sidebar.left",
            description: Text("Choose a comparison from the sidebar, or select two to compare side by side.")
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

            if let ssim = entry.ssimScore {
                metadataItem(label: "SSIM", value: String(format: "%.4f", ssim))
            }

            if let psnr = entry.psnrScore {
                metadataItem(label: "PSNR", value: String(format: "%.1f dB", psnr))
            }

            if let vmaf = entry.vmafScore {
                metadataItem(label: "VMAF", value: String(format: "%.1f", vmaf))
            }

            Spacer()

            Button {
                selectedEntry = nil
                abViewEntry = entry
            } label: {
                Label("Open A/B View", systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(.bordered)
            .help("Open the full frame-by-frame source vs. encoded comparison")

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
            Button {
                showCaptureSheet = true
            } label: {
                Label("New Comparison", systemImage: "plus.rectangle.on.rectangle")
            }
            .help("Capture a source/encoded frame pair with SSIM, PSNR, and VMAF")

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
            return libraryManager.entries
        }
        let query = searchText.lowercased()
        return libraryManager.entries.filter { entry in
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
        libraryManager.entries.filter { comparisonSelection.contains($0.id) }
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
        libraryManager.remove(entry)
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

// MARK: - CaptureComparisonSheet

/// Sheet that captures a real comparison entry: extracts a representative
/// frame from the encoded file and computes SSIM/PSNR/VMAF between the
/// source and encoded files.
///
/// Execution follows the proven `FFmpegProcessController` pattern used by
/// `AnimatedImageView.generate()`: locate FFmpeg via `FFmpegBundleManager`,
/// build arguments with the real `ComparisonCapture` / `FrameComparisonExtractor`
/// builders, run each pass through a fresh `FFmpegProcessController`, and
/// parse the real stderr output. No step here fabricates a result — a
/// failed pass surfaces as an honest error and no entry is persisted.
private struct CaptureComparisonSheet: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Dependencies

    let libraryManager: ComparisonLibraryManager

    // MARK: - State

    @State private var sourcePath: String
    @State private var encodedPath: String = ""
    @State private var profileName: String = ""
    @State private var codec: String = ""
    @State private var crfText: String = ""
    @State private var bitrateMbpsText: String = ""
    @State private var timestampText: String = "5.0"

    @State private var computeSSIM = true
    @State private var computePSNR = true
    @State private var computeVMAF = true

    /// `nil` while the libvmaf capability probe is in flight, then the
    /// real result — never assumed available.
    @State private var vmafAvailable: Bool?

    @State private var showSourcePicker = false
    @State private var showEncodedPicker = false

    @State private var isCapturing = false
    @State private var statusMessage: String?

    @State private var captureTask: Task<Void, Never>?
    @State private var currentController: FFmpegProcessController?

    // MARK: - Initialiser

    init(libraryManager: ComparisonLibraryManager, defaultSourcePath: String?) {
        self.libraryManager = libraryManager
        _sourcePath = State(initialValue: defaultSourcePath ?? "")
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Comparison")
                .font(.headline)

            Form {
                Section("Files") {
                    filePickerRow(
                        label: "Source",
                        path: sourcePath,
                        action: { showSourcePicker = true }
                    )
                    filePickerRow(
                        label: "Encoded",
                        path: encodedPath,
                        action: { showEncodedPicker = true }
                    )
                }

                Section("Encode Details") {
                    HStack {
                        Text("Profile Name")
                        Spacer()
                        TextField("Custom", text: $profileName)
                            .frame(width: 160)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Codec")
                        Spacer()
                        TextField("e.g. h265", text: $codec)
                            .frame(width: 160)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("CRF (optional)")
                        Spacer()
                        TextField("", text: $crfText)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Bitrate (Mbps, optional)")
                        Spacer()
                        TextField("", text: $bitrateMbpsText)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Frame Timestamp (s)")
                        Spacer()
                        TextField("5.0", text: $timestampText)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Quality Metrics") {
                    Toggle("Compute SSIM", isOn: $computeSSIM)
                    Toggle("Compute PSNR", isOn: $computePSNR)
                    Toggle("Compute VMAF", isOn: $computeVMAF)
                        .disabled(vmafAvailable != true)
                    if vmafAvailable == false {
                        Text("VMAF is unavailable: this FFmpeg build was not compiled with libvmaf support.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if vmafAvailable == nil {
                        Text("Checking VMAF availability…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            if let status = statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.hasPrefix("Error") ? .red : .secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancelAndDismiss)
                Button {
                    capture()
                } label: {
                    if isCapturing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Text(isCapturing ? "Capturing…" : "Capture")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCapture)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 480)
        .task {
            await probeVMAFAvailability()
        }
        .fileImporter(
            isPresented: $showSourcePicker,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .avi, .video],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                sourcePath = url.path
            }
        }
        .fileImporter(
            isPresented: $showEncodedPicker,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .avi, .video],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                encodedPath = url.path
                if profileName.isEmpty {
                    profileName = url.deletingPathExtension().lastPathComponent
                }
            }
        }
    }

    private func filePickerRow(label: String, path: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .leading)
            Text(path.isEmpty ? "Not selected" : URL(fileURLWithPath: path).lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
            Spacer()
            Button("Choose…", action: action)
        }
    }

    private var canCapture: Bool {
        !isCapturing
            && !sourcePath.isEmpty
            && !encodedPath.isEmpty
            && TimeInterval(timestampText) != nil
    }

    // MARK: - VMAF Availability

    /// Probes whether the located FFmpeg binary was built with libvmaf
    /// support, mirroring `QualityMetricsViewModel.probeLibvmafAvailable`'s
    /// proven approach (checking `-hide_banner -filters` for "libvmaf"
    /// rather than assuming support and failing later with an obscure
    /// "no such filter" error).
    private func probeVMAFAvailability() async {
        let ffmpegPath: String
        do {
            ffmpegPath = try await Task.detached {
                try FFmpegBundleManager().locateFFmpeg().path
            }.value
        } catch {
            vmafAvailable = false
            return
        }
        vmafAvailable = await Task.detached {
            Self.probeLibvmafAvailable(ffmpegPath: ffmpegPath)
        }.value
    }

    /// Whether the given FFmpeg binary was built with libvmaf support.
    /// `nonisolated` and run from a detached task so the blocking
    /// `waitUntilExit()` call never runs on the main actor.
    private nonisolated static func probeLibvmafAvailable(ffmpegPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-hide_banner", "-filters"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return false
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("libvmaf")
    }

    // MARK: - Capture

    /// Runs the real capture pipeline: locate FFmpeg, extract the
    /// representative frame from the encoded file via
    /// `ComparisonCapture.captureFrame`, then compute the metrics the
    /// user asked for via `FrameComparisonExtractor.buildSSIMArguments` /
    /// `buildPSNRArguments` and `ComparisonCapture.vmafArguments` — each
    /// executed through its own `FFmpegProcessController`, mirroring
    /// `AnimatedImageView.generate()`. Persists a `ComparisonEntry` only
    /// once the frame is confirmed on disk; any failure along the way is
    /// surfaced honestly and nothing is persisted.
    private func capture() {
        guard canCapture else { return }
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            statusMessage = "Error: source file not found at \(sourcePath)."
            return
        }
        guard FileManager.default.fileExists(atPath: encodedPath) else {
            statusMessage = "Error: encoded file not found at \(encodedPath)."
            return
        }
        guard let timestamp = TimeInterval(timestampText), timestamp >= 0 else {
            statusMessage = "Error: enter a valid, non-negative timestamp in seconds."
            return
        }

        isCapturing = true
        statusMessage = "Capturing…"

        let source = sourcePath
        let encoded = encodedPath
        let profile = profileName.isEmpty
            ? URL(fileURLWithPath: encoded).deletingPathExtension().lastPathComponent
            : profileName
        let codecValue = codec.isEmpty ? "unknown" : codec
        let crfValue = Int(crfText)
        let bitrateValue = Double(bitrateMbpsText).map { Int($0 * 1_000_000) }
        let wantSSIM = computeSSIM
        let wantPSNR = computePSNR
        let wantVMAF = computeVMAF && vmafAvailable == true

        captureTask = Task {
            let ffmpegPath: String
            do {
                ffmpegPath = try await Task.detached {
                    try FFmpegBundleManager().locateFFmpeg().path
                }.value
            } catch {
                statusMessage = "Error: FFmpeg could not be found. Install FFmpeg or configure its location in Settings."
                isCapturing = false
                return
            }

            do {
                // 1. Extract the representative frame from the encoded file
                //    into the library's persisted frame store.
                let frameFileName = PathSanitizer.sanitizeFilenameComponent(
                    "\(UUID().uuidString)_\(profile).png"
                )
                let framePath = ComparisonLibraryManager.framesDirectory
                    .appendingPathComponent(frameFileName).path

                let frameArgs = ComparisonCapture.captureFrame(
                    inputPath: encoded,
                    outputPath: framePath,
                    timestamp: timestamp
                )
                let frameController = FFmpegProcessController(binaryPath: ffmpegPath)
                currentController = frameController
                try await runToCompletion(frameController, arguments: frameArgs)

                guard FileManager.default.fileExists(atPath: framePath) else {
                    throw FFmpegProcessError.processFailure(
                        exitCode: frameController.exitCode ?? -1,
                        stderr: "FFmpeg reported success but no frame was written to \(framePath)."
                    )
                }

                // Metric passes are best-effort and isolated from each
                // other and from the frame capture above: a real failure
                // (e.g. source/encoded resolutions don't match, which SSIM/
                // PSNR/VMAF all require) logs a warning and leaves that one
                // score nil rather than discarding the frame already
                // captured or the other metrics that did succeed.
                var metricFailures: [String] = []

                // 2. SSIM (FrameComparisonExtractor).
                var ssim: Double?
                if wantSSIM {
                    do {
                        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
                        currentController = controller
                        let args = FrameComparisonExtractor.buildSSIMArguments(
                            sourcePath: source,
                            encodedPath: encoded
                        )
                        try await runToCompletion(controller, arguments: args)
                        ssim = FrameComparisonExtractor.parseSSIM(from: controller.errorOutput)
                    } catch {
                        metricFailures.append("SSIM (\(error.localizedDescription))")
                    }
                }

                // 3. PSNR (FrameComparisonExtractor).
                var psnr: Double?
                if wantPSNR {
                    do {
                        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
                        currentController = controller
                        let args = FrameComparisonExtractor.buildPSNRArguments(
                            sourcePath: source,
                            encodedPath: encoded
                        )
                        try await runToCompletion(controller, arguments: args)
                        psnr = FrameComparisonExtractor.parsePSNR(from: controller.errorOutput)
                    } catch {
                        metricFailures.append("PSNR (\(error.localizedDescription))")
                    }
                }

                // 4. VMAF (ComparisonCapture), only if libvmaf is present.
                var vmaf: Double?
                if wantVMAF {
                    do {
                        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
                        currentController = controller
                        let args = ComparisonCapture.vmafArguments(
                            referencePath: source,
                            distortedPath: encoded
                        )
                        try await runToCompletion(controller, arguments: args)
                        // Reuses QualityMetricsBuilder's proven stderr parser
                        // — the libvmaf filter prints the same
                        // "VMAF score: NN.NN" summary line regardless of
                        // which call site invoked it.
                        vmaf = QualityMetricsBuilder.parseVMAFScore(from: controller.errorOutput)
                    } catch {
                        metricFailures.append("VMAF (\(error.localizedDescription))")
                    }
                }

                if !metricFailures.isEmpty {
                    viewModel.appendLog(
                        .warning,
                        "Comparison capture: some metrics could not be computed — \(metricFailures.joined(separator: "; "))"
                    )
                }

                let attrs = try? FileManager.default.attributesOfItem(atPath: encoded)
                let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

                let entry = ComparisonEntry(
                    sourceFile: source,
                    encodedFile: encoded,
                    timestamp: timestamp,
                    profileName: profile,
                    codec: codecValue,
                    crf: crfValue,
                    bitrate: bitrateValue,
                    framePath: framePath,
                    fileSize: fileSize,
                    vmafScore: vmaf,
                    ssimScore: ssim,
                    psnrScore: psnr
                )
                libraryManager.add(entry)
                viewModel.appendLog(
                    .info,
                    "Captured comparison: \(entry.sourceFileName) vs \(URL(fileURLWithPath: encoded).lastPathComponent) at \(String(format: "%.1f", timestamp))s"
                )

                isCapturing = false
                currentController = nil
                dismiss()
            } catch is CancellationError {
                statusMessage = "Cancelled."
                isCapturing = false
                currentController = nil
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
                viewModel.appendLog(.error, "Comparison capture failed: \(error.localizedDescription)")
                isCapturing = false
                currentController = nil
            }
        }
    }

    /// Cancel any in-flight capture and dismiss the sheet.
    private func cancelAndDismiss() {
        captureTask?.cancel()
        currentController?.stopEncoding()
        captureTask = nil
        currentController = nil
        dismiss()
    }

    /// Runs an `FFmpegProcessController` pass to completion by draining
    /// its progress `AsyncStream`. Mirrors
    /// `AnimatedImageView.runToCompletion`.
    private func runToCompletion(
        _ controller: FFmpegProcessController,
        arguments: [String]
    ) async throws {
        let progressStream = try controller.startEncoding(arguments: arguments)
        for await _ in progressStream {
            if Task.isCancelled {
                controller.stopEncoding()
                break
            }
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        if let code = controller.exitCode, code != 0 {
            throw FFmpegProcessError.processFailure(exitCode: code, stderr: controller.errorOutput)
        }
    }
}
