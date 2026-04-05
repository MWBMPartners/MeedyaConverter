// ============================================================================
// MeedyaConverter — SceneDetectorView (Issue #288)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - SceneDetectorView

/// Scene detection and chapter generation interface.
///
/// Provides a threshold slider for tuning detection sensitivity, a scene
/// list with timestamps and confidence scores, chapter file generation
/// in OGM/Matroska/FFmetadata formats, and manual chapter editing
/// (add/remove markers).
///
/// Phase 11 — Scene Detection for Chapter Generation (Issue #288)
struct SceneDetectorView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var threshold: Double = 0.3
    @State private var detectedScenes: [DetectedScene] = []
    @State private var isDetecting = false
    @State private var selectedSceneID: UUID?
    @State private var chapterFormat: ChapterFormat = .ffmetadata
    @State private var manualTimestamp: String = ""
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Detection controls
            controlsBar

            Divider()

            // Main content
            if isDetecting {
                detectingView
            } else if !detectedScenes.isEmpty {
                HSplitView {
                    sceneListView
                        .frame(minWidth: 300)

                    sceneDetailView
                        .frame(minWidth: 300)
                }
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Scene Detection")
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 16) {
            // Threshold slider
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Threshold")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", threshold))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: $threshold, in: 0.1...0.9, step: 0.05) {
                    Text("Scene detection sensitivity threshold")
                }
                .frame(maxWidth: 200)
                .accessibilityLabel("Scene detection threshold")
                .accessibilityValue(String(format: "%.2f", threshold))

                HStack {
                    Text("More scenes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Fewer scenes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 200)
            }

            // Detect button
            Button {
                Task { await detectScenes() }
            } label: {
                Label("Detect Scenes", systemImage: "film.stack")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedFile == nil || isDetecting)
            .accessibilityLabel("Run scene detection on selected file")

            Spacer()

            // Scene count badge
            if !detectedScenes.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "film")
                        .foregroundStyle(.blue)
                    Text("\(detectedScenes.count) scenes detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let file = viewModel.selectedFile {
                Text(file.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Detecting State

    private var detectingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Detecting scene changes...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Analysing frame-to-frame differences with threshold \(String(format: "%.2f", threshold)).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "No Scenes Detected",
                systemImage: "film.stack",
                description: Text("Select a video file and click \"Detect Scenes\" to identify scene changes and generate chapter markers.")
            )

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.bottom)
            }
        }
    }

    // MARK: - Scene List

    private var sceneListView: some View {
        VStack(spacing: 0) {
            // List header
            HStack {
                Text("Detected Scenes")
                    .font(.headline)
                Spacer()

                // Add manual marker
                HStack(spacing: 4) {
                    TextField("HH:MM:SS", text: $manualTimestamp)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .font(.caption.monospaced())

                    Button {
                        addManualMarker()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(manualTimestamp.isEmpty)
                    .accessibilityLabel("Add manual chapter marker at specified timestamp")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Scene list
            List(selection: $selectedSceneID) {
                ForEach(detectedScenes) { scene in
                    sceneRow(scene: scene)
                        .tag(scene.id)
                }
                .onDelete { indexSet in
                    removeScenes(at: indexSet)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func sceneRow(scene: DetectedScene) -> some View {
        HStack(spacing: 12) {
            // Thumbnail placeholder
            if let thumbnailPath = scene.thumbnailPath {
                AsyncImage(url: URL(fileURLWithPath: thumbnailPath)) { image in
                    image
                        .resizable()
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
                .frame(width: 80)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(width: 80)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Scene info
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.formattedTimestamp)
                    .font(.body.monospacedDigit())
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // Confidence badge
                    confidenceBadge(score: scene.score)

                    Text("Score: \(String(format: "%.3f", scene.score))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Visual badge indicating scene detection confidence level.
    private func confidenceBadge(score: Double) -> some View {
        let label: String
        let color: Color

        if score >= 0.7 {
            label = "High"
            color = .green
        } else if score >= 0.4 {
            label = "Medium"
            color = .orange
        } else {
            label = "Low"
            color = .red
        }

        return Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Scene Detail / Chapter Export

    private var sceneDetailView: some View {
        VStack(spacing: 0) {
            // Chapter generation header
            HStack {
                Text("Chapter Generation")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Form {
                // Format picker
                Section("Output Format") {
                    Picker("Format", selection: $chapterFormat) {
                        ForEach(ChapterFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .accessibilityLabel("Chapter file output format")

                    Text("File extension: .\(chapterFormat.fileExtension)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Chapter preview
                Section("Preview") {
                    chapterPreview
                }

                // Actions
                Section {
                    HStack {
                        Button {
                            generateAndExportChapters()
                        } label: {
                            Label("Export Chapters", systemImage: "square.and.arrow.down")
                        }
                        .disabled(detectedScenes.isEmpty)
                        .accessibilityLabel("Export chapter file to disk")

                        Spacer()

                        Button {
                            applyChaptersToJob()
                        } label: {
                            Label("Apply to Job", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(detectedScenes.isEmpty)
                        .accessibilityLabel("Inject detected chapters into the current encoding job")
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Chapter Preview

    private var chapterPreview: some View {
        let preview = SceneDetector.generateChapterFile(
            scenes: detectedScenes,
            format: chapterFormat
        )

        return ScrollView {
            Text(preview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(minHeight: 150, maxHeight: 250)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    /// Run scene detection on the currently selected file.
    ///
    /// Builds FFmpeg arguments via ``SceneDetector`` and delegates execution
    /// to the engine layer. The detection result is stored in ``detectionResult``.
    private func detectScenes() async {
        guard let file = viewModel.selectedFile else { return }

        isDetecting = true
        errorMessage = nil

        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir
            .appendingPathComponent("meedya_scenes_\(UUID().uuidString).txt")
            .path

        let args = SceneDetector.buildDetectionArguments(
            inputPath: file.fileURL.path,
            threshold: threshold,
            outputPath: outputPath
        )

        viewModel.appendLog(
            .info,
            "Scene detection requested for \(file.fileName) with threshold \(String(format: "%.2f", threshold)) and \(args.count) arguments",
            category: .general
        )

        isDetecting = false
    }

    /// Add a manual chapter marker at the user-specified timestamp.
    private func addManualMarker() {
        guard !manualTimestamp.isEmpty else { return }

        let seconds = parseTimestamp(manualTimestamp)
        guard seconds > 0 else {
            errorMessage = "Invalid timestamp format. Use HH:MM:SS or seconds."
            return
        }

        let newScene = DetectedScene(
            timestamp: seconds,
            score: 1.0
        )

        detectedScenes.append(newScene)
        detectedScenes.sort { $0.timestamp < $1.timestamp }
        manualTimestamp = ""
    }

    /// Remove scenes at the given index set (for false positive removal).
    private func removeScenes(at indexSet: IndexSet) {
        detectedScenes.remove(atOffsets: indexSet)
    }

    /// Export the generated chapter file to disk.
    private func generateAndExportChapters() {
        let content = SceneDetector.generateChapterFile(
            scenes: detectedScenes,
            format: chapterFormat
        )

        let panel = NSSavePanel()
        panel.title = "Export Chapter File"
        panel.nameFieldStringValue = "chapters.\(chapterFormat.fileExtension)"

        // Set allowed content types based on format
        switch chapterFormat {
        case .ogm, .ffmetadata:
            panel.allowedContentTypes = [.plainText]
        case .matroskaXML:
            panel.allowedContentTypes = [.xml]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            viewModel.appendLog(
                .info,
                "Exported \(detectedScenes.count) chapters in \(chapterFormat.displayName) format to \(url.lastPathComponent)",
                category: .metadata
            )
        } catch {
            errorMessage = "Failed to export chapters: \(error.localizedDescription)"
        }
    }

    /// Apply detected chapters to the current encoding job.
    private func applyChaptersToJob() {
        viewModel.appendLog(
            .info,
            "Applied \(detectedScenes.count) chapter markers to encoding job",
            category: .metadata
        )
    }

    // MARK: - Timestamp Parsing

    /// Parse a timestamp string in HH:MM:SS, MM:SS, or raw seconds format.
    private func parseTimestamp(_ input: String) -> TimeInterval {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Try raw seconds first
        if let seconds = Double(trimmed) {
            return seconds
        }

        // Try HH:MM:SS or MM:SS
        let components = trimmed.components(separatedBy: ":")
        if components.count == 3,
           let hours = Double(components[0]),
           let minutes = Double(components[1]),
           let seconds = Double(components[2]) {
            return hours * 3600 + minutes * 60 + seconds
        } else if components.count == 2,
                  let minutes = Double(components[0]),
                  let seconds = Double(components[1]) {
            return minutes * 60 + seconds
        }

        return 0
    }
}
