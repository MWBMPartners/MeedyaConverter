// ============================================================================
// MeedyaConverter — SlateGeneratorView (Issue #343)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - SlateGeneratorView

/// View for configuring and generating broadcast slate cards and leader sequences.
///
/// Provides form controls for all slate text fields (title, client, agency, date,
/// duration, format, audio config), colour pickers, leader options (colour bars,
/// countdown, tone, black burst), resolution selection, and actions for generating
/// leaders and prepending them to source video files.
///
/// Phase 12 — Slate and Leader Generation for Broadcast Delivery (Issue #343)
struct SlateGeneratorView: View {

    // MARK: - Slate Text State

    /// The programme or project title.
    @State private var slateTitle = ""

    /// The client or commissioning entity name.
    @State private var slateClient = ""

    /// The advertising agency name.
    @State private var slateAgency = ""

    /// The air date or delivery date.
    @State private var slateDate = ""

    /// The programme duration string.
    @State private var slateDuration = ""

    /// The delivery format description.
    @State private var slateFormat = "HD 1080i 25fps"

    /// The audio configuration description.
    @State private var slateAudioConfig = "Stereo 48kHz 24-bit"

    /// The slate hold duration in seconds.
    @State private var slateDurationSeconds: Double = 10.0

    // MARK: - Colour State

    /// The slate background colour.
    @State private var backgroundColor = Color(red: 0.1, green: 0.1, blue: 0.18)

    /// The slate text colour.
    @State private var textColor = Color.white

    // MARK: - Leader Options State

    /// Duration of the SMPTE colour bars in seconds.
    @State private var colorBarsDuration: Double = 30.0

    /// Duration of the countdown timer in seconds.
    @State private var countdownDuration: Double = 10.0

    /// Whether to include a countdown segment.
    @State private var includeCountdown = true

    /// Frequency of the reference tone in Hz.
    @State private var toneFrequency: Int = 1000

    /// Duration of the reference tone in seconds.
    @State private var toneDuration: Double = 10.0

    /// Whether to include a black burst segment.
    @State private var includeBlackBurst = true

    /// Duration of the black burst segment in seconds.
    @State private var blackBurstDuration: Double = 3.0

    // MARK: - Resolution State

    /// The selected output resolution.
    @State private var selectedResolution = "1920x1080"

    /// Available resolution options.
    private let resolutions = [
        "1920x1080",
        "3840x2160",
        "1280x720",
        "720x576",
        "720x480",
    ]

    // MARK: - Action State

    /// Whether a generate operation is in progress.
    @State private var isGenerating = false

    /// Status message for the last operation.
    @State private var statusMessage: String?

    /// The source video file URL for prepend operations.
    @State private var sourceVideoURL: URL?

    /// Whether the file importer dialog is presented.
    @State private var showFileImporter = false

    // MARK: - Body

    var body: some View {
        Form {
            // MARK: Slate Information
            Section("Slate Information") {
                TextField("Title", text: $slateTitle, prompt: Text("Programme Title"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Programme title for slate")

                TextField("Client", text: $slateClient, prompt: Text("Client Name (optional)"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Client name for slate")

                TextField("Agency", text: $slateAgency, prompt: Text("Agency Name (optional)"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Agency name for slate")

                TextField("Date", text: $slateDate, prompt: Text("2026-04-05"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Air date or delivery date")

                TextField("Duration", text: $slateDuration, prompt: Text("00:30:00"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Programme duration")

                TextField("Format", text: $slateFormat, prompt: Text("HD 1080i 25fps"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Delivery format")

                TextField("Audio Config", text: $slateAudioConfig, prompt: Text("Stereo 48kHz 24-bit"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Audio configuration")

                HStack {
                    Text("Slate Duration")
                    Spacer()
                    TextField("Seconds", value: $slateDurationSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 80)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Slate hold duration in seconds")
            }

            // MARK: Colours
            Section("Colours") {
                ColorPicker("Background Colour", selection: $backgroundColor)
                    .accessibilityLabel("Slate background colour")
                ColorPicker("Text Colour", selection: $textColor)
                    .accessibilityLabel("Slate text colour")
            }

            // MARK: Leader Options
            Section("Leader Options") {
                HStack {
                    Text("Colour Bars Duration")
                    Spacer()
                    TextField("Seconds", value: $colorBarsDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 80)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("SMPTE colour bars duration")

                Toggle("Include Countdown", isOn: $includeCountdown)
                    .accessibilityLabel("Include countdown timer segment")

                if includeCountdown {
                    HStack {
                        Text("Countdown Duration")
                        Spacer()
                        TextField("Seconds", value: $countdownDuration, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 80)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Countdown timer duration")
                }

                HStack {
                    Text("Tone Frequency")
                    Spacer()
                    TextField("Hz", value: $toneFrequency, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 80)
                    Text("Hz")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Reference tone frequency")

                HStack {
                    Text("Tone Duration")
                    Spacer()
                    TextField("Seconds", value: $toneDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 80)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Reference tone duration")

                Toggle("Include Black Burst", isOn: $includeBlackBurst)
                    .accessibilityLabel("Include black burst segment after countdown")

                if includeBlackBurst {
                    HStack {
                        Text("Black Burst Duration")
                        Spacer()
                        TextField("Seconds", value: $blackBurstDuration, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 80)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Black burst segment duration")
                }
            }

            // MARK: Resolution
            Section("Output Resolution") {
                Picker("Resolution", selection: $selectedResolution) {
                    ForEach(resolutions, id: \.self) { res in
                        Text(res).tag(res)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Output resolution for leader generation")
            }

            // MARK: Slate Preview
            Section("Slate Preview") {
                slatePreview
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Preview of the slate text layout")
            }

            // MARK: Actions
            Section("Actions") {
                HStack {
                    Button {
                        generateLeader()
                    } label: {
                        Label("Generate Leader", systemImage: "film")
                    }
                    .disabled(slateTitle.isEmpty || isGenerating)
                    .accessibilityLabel("Generate the complete broadcast leader sequence")

                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Divider()

                HStack {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Select Source Video", systemImage: "doc.badge.plus")
                    }
                    .accessibilityLabel("Choose a source video to prepend the leader to")

                    if let url = sourceVideoURL {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Button {
                    prependLeader()
                } label: {
                    Label("Prepend to Video", systemImage: "arrow.right.doc.on.clipboard")
                }
                .disabled(sourceVideoURL == nil || slateTitle.isEmpty || isGenerating)
                .accessibilityLabel("Prepend the generated leader to the selected source video")

                if let message = statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.contains("Error") ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Slate & Leader Generator")
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                sourceVideoURL = urls.first
            case .failure(let error):
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Slate Preview

    /// A visual preview of the slate text layout.
    private var slatePreview: some View {
        ZStack {
            Rectangle()
                .fill(backgroundColor)

            VStack(spacing: 12) {
                Text(slateTitle.isEmpty ? "Programme Title" : slateTitle)
                    .font(.title2.bold())
                    .foregroundStyle(textColor)

                if !slateClient.isEmpty {
                    Text("CLIENT: \(slateClient)")
                        .font(.body)
                        .foregroundStyle(textColor.opacity(0.9))
                }
                if !slateAgency.isEmpty {
                    Text("AGENCY: \(slateAgency)")
                        .font(.body)
                        .foregroundStyle(textColor.opacity(0.9))
                }

                Divider()
                    .background(textColor.opacity(0.3))
                    .frame(maxWidth: 300)

                Group {
                    if !slateDate.isEmpty {
                        Text("DATE: \(slateDate)")
                    }
                    if !slateDuration.isEmpty {
                        Text("DURATION: \(slateDuration)")
                    }
                    Text("FORMAT: \(slateFormat)")
                    if !slateAudioConfig.isEmpty {
                        Text("AUDIO: \(slateAudioConfig)")
                    }
                }
                .font(.callout)
                .foregroundStyle(textColor.opacity(0.85))
            }
            .padding()
        }
    }

    // MARK: - Config Builders

    /// Build a `SlateConfig` from the current form state.
    ///
    /// - Returns: A configured `SlateConfig` instance.
    private func buildSlateConfig() -> SlateConfig {
        SlateConfig(
            title: slateTitle,
            client: slateClient.isEmpty ? nil : slateClient,
            agency: slateAgency.isEmpty ? nil : slateAgency,
            date: slateDate,
            duration: slateDuration,
            format: slateFormat,
            audioConfig: slateAudioConfig.isEmpty ? nil : slateAudioConfig,
            backgroundColor: colorToHex(backgroundColor),
            textColor: colorToHex(textColor),
            durationSeconds: slateDurationSeconds
        )
    }

    /// Build a `LeaderConfig` from the current form state.
    ///
    /// - Returns: A configured `LeaderConfig` instance.
    private func buildLeaderConfig() -> LeaderConfig {
        LeaderConfig(
            colorBarsDuration: colorBarsDuration,
            countdownDuration: includeCountdown ? countdownDuration : 0,
            toneFrequency: toneFrequency,
            toneDuration: toneDuration,
            includeBlackBurst: includeBlackBurst,
            blackBurstDuration: blackBurstDuration
        )
    }

    // MARK: - Actions

    /// Generate a complete broadcast leader sequence.
    private func generateLeader() {
        isGenerating = true
        statusMessage = nil

        let slateConfig = buildSlateConfig()
        let leaderConfig = buildLeaderConfig()

        let args = SlateGenerator.buildFullLeaderArguments(
            outputPath: "leader_output.mov",
            slateConfig: slateConfig,
            leaderConfig: leaderConfig,
            resolution: selectedResolution
        )

        statusMessage = "Leader arguments generated (\(args.count) args). "
            + "Run with ffmpeg to produce output."
        isGenerating = false
    }

    /// Prepend the generated leader to the selected source video.
    private func prependLeader() {
        guard let videoURL = sourceVideoURL else {
            statusMessage = "Error: No source video selected."
            return
        }

        isGenerating = true
        statusMessage = nil

        let outputName = "leader_\(videoURL.lastPathComponent)"
        let outputPath = videoURL
            .deletingLastPathComponent()
            .appendingPathComponent(outputName)
            .path

        let args = SlateGenerator.prependToVideo(
            leaderPath: "leader_output.mov",
            videoPath: videoURL.path,
            outputPath: outputPath
        )

        statusMessage = "Prepend arguments generated (\(args.count) args). "
            + "Run with ffmpeg to produce output."
        isGenerating = false
    }

    // MARK: - Colour Helpers

    /// Convert a SwiftUI `Color` to a hex string.
    ///
    /// - Parameter color: The SwiftUI colour to convert.
    /// - Returns: A hex colour string prefixed with "#" (e.g. "#1a1a2e").
    private func colorToHex(_ color: Color) -> String {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return "#000000"
        }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
