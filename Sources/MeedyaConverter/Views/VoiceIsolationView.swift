// ============================================================================
// MeedyaConverter — VoiceIsolationView (Issue #293)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine
import AVFoundation

// MARK: - VoiceIsolationView

/// Provides a visual interface for voice isolation and dialogue extraction
/// from audio/video files using FFmpeg filter chains.
///
/// Features:
/// - Method selector (bandpass, spectral subtraction, centre channel extraction)
/// - Sensitivity slider for tuning isolation aggressiveness
/// - Source file/track selector
/// - Output format picker
/// - Audio preview (play isolated audio)
/// - Extract button with progress indicator
/// - Export as separate audio track
///
/// Phase 11 — Voice Isolation / Dialogue Extraction (Issue #293)
struct VoiceIsolationView: View {

    // MARK: - State

    /// The selected source media file URL.
    @State private var selectedFileURL: URL?

    /// The selected isolation method.
    @State private var isolationMethod: IsolationMethod = .ffmpegHighpass

    /// Sensitivity slider value (0.0–1.0).
    @State private var sensitivity: Double = 0.5

    /// Whether to extract only the centre channel (for surround content).
    @State private var centerChannelOnly = true

    /// The selected output audio format.
    @State private var outputFormat: String = "wav"

    /// Whether extraction is in progress.
    @State private var isExtracting = false

    /// The output file URL after successful extraction.
    @State private var outputFileURL: URL?

    /// The generated FFmpeg arguments for display.
    @State private var ffmpegArguments: [String] = []

    /// Whether ML sound analysis is available on this system.
    @State private var mlAvailable = false

    /// Audio player for previewing the isolated audio.
    @State private var audioPlayer: AVAudioPlayer?

    /// Whether preview audio is currently playing.
    @State private var isPlaying = false

    /// Error message from the most recent operation.
    @State private var errorMessage: String?

    /// Success message from the most recent operation.
    @State private var successMessage: String?

    // MARK: - Available Output Formats

    /// Supported output audio formats for the format picker.
    private let outputFormats = ["wav", "flac", "aac", "mp3", "opus"]

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            filePickerSection
            methodSection
            sensitivitySection
            outputSection
            if isExtracting {
                ProgressView("Extracting voice audio…")
                    .padding()
            }
            if !ffmpegArguments.isEmpty {
                commandPreviewSection
            }
            if outputFileURL != nil {
                previewSection
            }
            if let error = errorMessage {
                errorBanner(message: error)
            }
            if let success = successMessage {
                successBanner(message: success)
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            mlAvailable = VoiceIsolator.isMLAvailable()
        }
    }

    // MARK: - Header

    /// Title and description area.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Voice Isolation")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Extract dialogue and voice audio from media files using FFmpeg filter chains and spectral processing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - File Picker

    /// Source file selection control.
    private var filePickerSection: some View {
        HStack(spacing: 12) {
            Button("Choose Source File…") {
                chooseSourceFile()
            }

            if let url = selectedFileURL {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Method Selection

    /// Isolation method selector with descriptions.
    private var methodSection: some View {
        GroupBox("Isolation Method") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Method:", selection: $isolationMethod) {
                    ForEach(IsolationMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.radioGroup)

                // Method description
                Text(methodDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // ML availability warning
                if isolationMethod == .visionSoundAnalysis && !mlAvailable {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("ML Sound Analysis is not available on this system. Falling back to FFmpeg bandpass.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                // Centre channel option (only relevant for dialogue extraction)
                if isolationMethod == .ffmpegHighpass || isolationMethod == .spectralSubtraction {
                    Divider()
                    Toggle("Also extract centre channel (for surround audio)", isOn: $centerChannelOnly)
                        .toggleStyle(.checkbox)
                }
            }
        }
    }

    /// Description text for the currently selected isolation method.
    private var methodDescription: String {
        switch isolationMethod {
        case .ffmpegHighpass:
            return "Applies a bandpass filter targeting speech frequencies (300Hz-3400Hz) with dynamic range compression. Fast and universally available."
        case .visionSoundAnalysis:
            return "Uses on-device machine learning to classify and separate sound types. Best quality but requires ML framework support."
        case .spectralSubtraction:
            return "FFT-based noise reduction that removes steady-state background noise while preserving speech transients. Good for consistent background noise."
        }
    }

    // MARK: - Sensitivity

    /// Sensitivity slider for tuning isolation aggressiveness.
    private var sensitivitySection: some View {
        GroupBox("Sensitivity") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Preserve more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $sensitivity, in: 0...1, step: 0.05)
                    Text("Isolate more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: "%.0f%%", sensitivity * 100))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Output Settings

    /// Output format picker and extract button.
    private var outputSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text("Output Format").font(.caption).foregroundStyle(.secondary)
                Picker("Format", selection: $outputFormat) {
                    ForEach(outputFormats, id: \.self) { fmt in
                        Text(fmt.uppercased()).tag(fmt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
            }

            Spacer()

            Button("Generate Command") {
                generateCommand()
            }
            .disabled(selectedFileURL == nil)
            .buttonStyle(.bordered)

            Button("Extract") {
                Task { await performExtraction() }
            }
            .disabled(selectedFileURL == nil || isExtracting)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Command Preview

    /// Displays the generated FFmpeg arguments for review.
    private var commandPreviewSection: some View {
        GroupBox("FFmpeg Command") {
            ScrollView(.horizontal, showsIndicators: true) {
                Text("ffmpeg " + ffmpegArguments.joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Preview Playback

    /// Audio playback controls for previewing the isolated result.
    @ViewBuilder
    private var previewSection: some View {
        GroupBox("Preview") {
            HStack(spacing: 12) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)

                if let url = outputFileURL {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Export…") {
                    exportOutput()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Status Banners

    /// Displays an error message.
    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
            Spacer()
            Button("Dismiss") {
                errorMessage = nil
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Displays a success message.
    private func successBanner(message: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text(message)
                .foregroundStyle(.green)
            Spacer()
            Button("Dismiss") {
                successMessage = nil
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    /// Presents an open panel to choose a source media file.
    private func chooseSourceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a media file for voice isolation."
        if panel.runModal() == .OK, let url = panel.url {
            selectedFileURL = url
            outputFileURL = nil
            ffmpegArguments = []
            errorMessage = nil
            successMessage = nil
            stopPlayback()
        }
    }

    /// Generates the FFmpeg command arguments based on current settings.
    private func generateCommand() {
        guard let inputURL = selectedFileURL else { return }

        let outputPath = buildOutputPath(for: inputURL)
        let config = VoiceIsolationConfig(
            method: isolationMethod,
            sensitivity: sensitivity,
            outputFormat: outputFormat
        )

        switch isolationMethod {
        case .ffmpegHighpass:
            ffmpegArguments = VoiceIsolator.buildFFmpegIsolationArguments(
                inputPath: inputURL.path,
                outputPath: outputPath,
                config: config
            )
        case .visionSoundAnalysis:
            // Fall back to FFmpeg bandpass if ML not available
            ffmpegArguments = VoiceIsolator.buildFFmpegIsolationArguments(
                inputPath: inputURL.path,
                outputPath: outputPath,
                config: config
            )
        case .spectralSubtraction:
            ffmpegArguments = VoiceIsolator.buildSpectralSubtractionArguments(
                inputPath: inputURL.path,
                outputPath: outputPath
            )
        }
    }

    /// Performs the voice extraction using FFmpeg.
    private func performExtraction() async {
        guard let inputURL = selectedFileURL else { return }
        isExtracting = true
        errorMessage = nil
        successMessage = nil
        stopPlayback()

        let outputPath = buildOutputPath(for: inputURL)
        let config = VoiceIsolationConfig(
            method: isolationMethod,
            sensitivity: sensitivity,
            outputFormat: outputFormat
        )

        // Build the arguments
        let args: [String]
        switch isolationMethod {
        case .ffmpegHighpass, .visionSoundAnalysis:
            args = VoiceIsolator.buildFFmpegIsolationArguments(
                inputPath: inputURL.path,
                outputPath: outputPath,
                config: config
            )
        case .spectralSubtraction:
            args = VoiceIsolator.buildSpectralSubtractionArguments(
                inputPath: inputURL.path,
                outputPath: outputPath
            )
        }

        ffmpegArguments = args

        // Execute FFmpeg
        do {
            try await runFFmpeg(arguments: args)
            let url = URL(fileURLWithPath: outputPath)
            outputFileURL = url
            successMessage = "Voice extraction complete."
        } catch {
            errorMessage = "Extraction failed: \(error.localizedDescription)"
        }

        isExtracting = false
    }

    /// Runs FFmpeg with the given arguments.
    ///
    /// - Parameter arguments: FFmpeg command-line arguments.
    /// - Throws: If FFmpeg is not found or exits with a non-zero code.
    private func runFFmpeg(arguments: [String]) async throws {
        let ffmpegPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        guard let ffmpegPath = ffmpegPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw NSError(
                domain: "VoiceIsolation",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "FFmpeg not found on this system."]
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "VoiceIsolation",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "FFmpeg exited with code \(process.terminationStatus)."]
            )
        }
    }

    /// Builds an output file path based on the input URL and selected format.
    ///
    /// - Parameter inputURL: The source file URL.
    /// - Returns: The output file path string.
    private func buildOutputPath(for inputURL: URL) -> String {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let dir = inputURL.deletingLastPathComponent().path
        return "\(dir)/\(baseName)_voice.\(outputFormat)"
    }

    /// Toggles audio playback of the extracted output.
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    /// Starts playing the extracted audio file.
    private func startPlayback() {
        guard let url = outputFileURL else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            isPlaying = true
        } catch {
            errorMessage = "Playback failed: \(error.localizedDescription)"
        }
    }

    /// Stops audio playback.
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    /// Presents a save panel to export the extracted audio to a chosen location.
    private func exportOutput() {
        guard let sourceURL = outputFileURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.audio]
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.message = "Choose where to save the extracted audio."
        if panel.runModal() == .OK, let destURL = panel.url {
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                successMessage = "Exported to \(destURL.lastPathComponent)"
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
