// ============================================================================
// MeedyaConverter — AnimatedImageView (Issue #321)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - AnimatedImageView
// ---------------------------------------------------------------------------
/// View for creating animated GIF and APNG images from video sources.
///
/// Provides controls for:
/// - Selecting the output format (GIF or APNG).
/// - Defining the time range (start time and duration).
/// - Adjusting output dimensions (width with auto-calculated height).
/// - Setting frame rate, colour palette size, and dithering mode.
/// - Configuring the animation loop count.
/// - Previewing the FFmpeg command before execution.
/// - Generating the animated image via an NSSavePanel.
///
/// Phase 12 — GIF/APNG Creation from Video (Issue #321)
struct AnimatedImageView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The selected animated image output format.
    @State private var format: AnimatedImageFormat = .gif

    /// Start time in the source video, in seconds.
    @State private var startTime: String = "0.0"

    /// Duration of the clip to extract, in seconds.
    @State private var duration: String = "5.0"

    /// Output width in pixels. Empty string means "use source width".
    @State private var width: String = ""

    /// Output frame rate (frames per second).
    @State private var fps: String = "15"

    /// Maximum palette colours (GIF only, 2–256).
    @State private var maxColors: String = "256"

    /// Whether dithering is enabled (GIF only).
    @State private var dithering: Bool = true

    /// Number of times the animation loops (0 = infinite).
    @State private var loopCount: String = "0"

    /// Whether the command preview section is expanded.
    @State private var showPreview: Bool = false

    /// Status message displayed after generation attempt.
    @State private var statusMessage: String?

    /// Whether a generation operation is currently running.
    @State private var isGenerating: Bool = false

    // MARK: - Body

    var body: some View {
        Form {
            // -----------------------------------------------------------------
            // Format Selection
            // -----------------------------------------------------------------
            Section("Output Format") {
                Picker("Format", selection: $format) {
                    ForEach(AnimatedImageFormat.allCases, id: \.self) { fmt in
                        Text(fmt.rawValue.uppercased()).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
            }

            // -----------------------------------------------------------------
            // Time Range
            // -----------------------------------------------------------------
            Section("Time Range") {
                HStack {
                    Text("Start Time (s)")
                    Spacer()
                    TextField("0.0", text: $startTime)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Duration (s)")
                    Spacer()
                    TextField("5.0", text: $duration)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
            }

            // -----------------------------------------------------------------
            // Dimensions & Frame Rate
            // -----------------------------------------------------------------
            Section("Dimensions & Frame Rate") {
                HStack {
                    Text("Width (px)")
                    Spacer()
                    TextField("Source", text: $width)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                Text("Height is auto-calculated to maintain aspect ratio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Frame Rate (fps)")
                    Spacer()
                    TextField("15", text: $fps)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
            }

            // -----------------------------------------------------------------
            // Colour / Dithering (GIF only)
            // -----------------------------------------------------------------
            if format == .gif {
                Section("Colour Settings (GIF)") {
                    HStack {
                        Text("Max Colours (2–256)")
                        Spacer()
                        TextField("256", text: $maxColors)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Enable Dithering", isOn: $dithering)
                }
            }

            // -----------------------------------------------------------------
            // Loop Count
            // -----------------------------------------------------------------
            Section("Looping") {
                HStack {
                    Text("Loop Count (0 = infinite)")
                    Spacer()
                    TextField("0", text: $loopCount)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
            }

            // -----------------------------------------------------------------
            // Command Preview
            // -----------------------------------------------------------------
            Section("Preview") {
                DisclosureGroup("FFmpeg Command Preview", isExpanded: $showPreview) {
                    Text(previewCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // -----------------------------------------------------------------
            // Generate Button
            // -----------------------------------------------------------------
            Section {
                HStack {
                    Spacer()
                    Button(action: generate) {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text("Generate \(format.rawValue.uppercased())")
                    }
                    .disabled(isGenerating)
                    .keyboardShortcut(.return, modifiers: .command)
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
        .navigationTitle("Animated Image")
    }

    // MARK: - Computed Properties

    /// Builds the current configuration from the form state.
    private var currentConfig: AnimatedImageConfig {
        AnimatedImageConfig(
            format: format,
            startTime: Double(startTime) ?? 0,
            duration: Double(duration) ?? 5,
            width: Int(width),
            fps: Int(fps) ?? 15,
            maxColors: Int(maxColors) ?? 256,
            dithering: dithering,
            loopCount: Int(loopCount) ?? 0
        )
    }

    /// Generates a human-readable preview of the FFmpeg command.
    private var previewCommand: String {
        let config = currentConfig
        let input = "<input>"
        let output = "<output>.\(format.rawValue)"

        switch format {
        case .gif:
            let passes = AnimatedImageGenerator.buildGIFArguments(
                inputPath: input,
                outputPath: output,
                config: config
            )
            let pass1 = "ffmpeg " + passes[0].joined(separator: " ")
            let pass2 = "ffmpeg " + passes[1].joined(separator: " ")
            return "# Pass 1 (palette generation)\n\(pass1)\n\n# Pass 2 (GIF creation)\n\(pass2)"

        case .apng:
            let args = AnimatedImageGenerator.buildAPNGArguments(
                inputPath: input,
                outputPath: output,
                config: config
            )
            return "ffmpeg " + args.joined(separator: " ")
        }
    }

    // MARK: - Actions

    /// Presents an NSSavePanel and generates the animated image.
    private func generate() {
        let panel = NSSavePanel()
        panel.title = "Save Animated Image"
        panel.nameFieldStringValue = "output.\(format.rawValue)"
        panel.allowedContentTypes = [
            format == .gif
                ? .gif
                : .png
        ]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        statusMessage = "Generating..."
        isGenerating = true

        // In a real implementation this would invoke FFmpegBackend to
        // run the generated arguments. For now we store the args to
        // demonstrate the pipeline integration point.
        let config = currentConfig
        let _ = format == .gif
            ? AnimatedImageGenerator.buildGIFArguments(
                inputPath: "<source>",
                outputPath: url.path,
                config: config
            )
            : [AnimatedImageGenerator.buildAPNGArguments(
                inputPath: "<source>",
                outputPath: url.path,
                config: config
            )]

        statusMessage = "Arguments prepared for \(url.lastPathComponent)"
        isGenerating = false
    }
}
