// ============================================================================
// MeedyaConverter — PerStreamSettingsView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - PerStreamSettingsView

/// Per-stream encoding settings editor.
///
/// Allows configuring different codec, bitrate, and quality settings for each
/// individual stream in the output. Streams without overrides inherit the
/// profile defaults.
///
/// Phase 3.5 — Per-Stream Encoding Settings (Issue #41)
struct PerStreamSettingsView: View {
    let mediaFile: MediaFile
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var viewModel

    @State private var perStream: PerStreamSettings = PerStreamSettings()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Per-Stream Encoding Settings")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Apply") {
                    applySettings()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            List {
                // Video streams
                if !mediaFile.videoStreams.isEmpty {
                    Section("Video Streams") {
                        ForEach(mediaFile.videoStreams, id: \.streamIndex) { stream in
                            videoStreamRow(stream)
                        }
                    }
                }

                // Audio streams
                if !mediaFile.audioStreams.isEmpty {
                    Section("Audio Streams") {
                        ForEach(mediaFile.audioStreams, id: \.streamIndex) { stream in
                            audioStreamRow(stream)
                        }
                    }
                }

                // Subtitle streams
                if !mediaFile.subtitleStreams.isEmpty {
                    Section("Subtitle Streams") {
                        ForEach(mediaFile.subtitleStreams, id: \.streamIndex) { stream in
                            subtitleStreamRow(stream)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear { loadExistingSettings() }
    }

    // MARK: - Video Stream Row

    @ViewBuilder
    private func videoStreamRow(_ stream: MediaStream) -> some View {
        let hasOverride = perStream.videoOverrides[stream.streamIndex] != nil

        DisclosureGroup {
            videoOverrideControls(for: stream.streamIndex)
        } label: {
            HStack {
                Label("Video #\(stream.streamIndex)", systemImage: "film")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(stream.summaryString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasOverride {
                    Text("Custom")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .clipShape(Capsule())
                } else {
                    Text("Profile Default")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func videoOverrideControls(for index: Int) -> some View {
        let override = videoOverrideBinding(for: index)

        Toggle("Use custom settings for this stream", isOn: Binding(
            get: { perStream.videoOverrides[index] != nil },
            set: { enabled in
                if enabled {
                    perStream.videoOverrides[index] = VideoStreamOverride()
                } else {
                    perStream.videoOverrides.removeValue(forKey: index)
                }
            }
        ))
        .accessibilityLabel("Enable per-stream encoding for video stream \(index)")

        if perStream.videoOverrides[index] != nil {
            Toggle("Passthrough (copy)", isOn: Binding(
                get: { override.wrappedValue.passthrough ?? false },
                set: { override.wrappedValue.passthrough = $0 ? true : nil }
            ))

            if override.wrappedValue.passthrough != true {
                Picker("Codec", selection: Binding(
                    get: { override.wrappedValue.codec ?? viewModel.selectedProfile.videoCodec },
                    set: { override.wrappedValue.codec = $0 }
                )) {
                    ForEach(VideoCodec.allCases.filter(\.canEncode), id: \.self) { codec in
                        Text(codec.displayName).tag(codec as VideoCodec?)
                    }
                }

                HStack {
                    Text("CRF")
                    TextField("CRF", value: Binding(
                        get: { override.wrappedValue.crf },
                        set: { override.wrappedValue.crf = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)

                    Text("Bitrate (bps)")
                    TextField("Bitrate", value: Binding(
                        get: { override.wrappedValue.bitrate },
                        set: { override.wrappedValue.bitrate = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                }

                TextField("Preset", text: Binding(
                    get: { override.wrappedValue.preset ?? "" },
                    set: { override.wrappedValue.preset = $0.isEmpty ? nil : $0 }
                ), prompt: Text("e.g., medium, slow"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            }
        }
    }

    // MARK: - Audio Stream Row

    @ViewBuilder
    private func audioStreamRow(_ stream: MediaStream) -> some View {
        let hasOverride = perStream.audioOverrides[stream.streamIndex] != nil

        DisclosureGroup {
            audioOverrideControls(for: stream.streamIndex)
        } label: {
            HStack {
                Label("Audio #\(stream.streamIndex)", systemImage: "waveform")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(stream.summaryString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasOverride {
                    Text("Custom")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .clipShape(Capsule())
                } else {
                    Text("Profile Default")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func audioOverrideControls(for index: Int) -> some View {
        let override = audioOverrideBinding(for: index)

        Toggle("Use custom settings for this stream", isOn: Binding(
            get: { perStream.audioOverrides[index] != nil },
            set: { enabled in
                if enabled {
                    perStream.audioOverrides[index] = AudioStreamOverride()
                } else {
                    perStream.audioOverrides.removeValue(forKey: index)
                }
            }
        ))
        .accessibilityLabel("Enable per-stream encoding for audio stream \(index)")

        if perStream.audioOverrides[index] != nil {
            Toggle("Passthrough (copy)", isOn: Binding(
                get: { override.wrappedValue.passthrough ?? false },
                set: { override.wrappedValue.passthrough = $0 ? true : nil }
            ))

            if override.wrappedValue.passthrough != true {
                Picker("Codec", selection: Binding(
                    get: { override.wrappedValue.codec ?? viewModel.selectedProfile.audioCodec },
                    set: { override.wrappedValue.codec = $0 }
                )) {
                    ForEach(AudioCodec.allCases.filter(\.canEncode), id: \.self) { codec in
                        Text(codec.displayName).tag(codec as AudioCodec?)
                    }
                }

                HStack {
                    Text("Bitrate (bps)")
                    TextField("Bitrate", value: Binding(
                        get: { override.wrappedValue.bitrate },
                        set: { override.wrappedValue.bitrate = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)

                    Text("Sample Rate (Hz)")
                    TextField("Sample Rate", value: Binding(
                        get: { override.wrappedValue.sampleRate },
                        set: { override.wrappedValue.sampleRate = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)

                    Text("Channels")
                    TextField("Channels", value: Binding(
                        get: { override.wrappedValue.channels },
                        set: { override.wrappedValue.channels = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 60)
                }
            }
        }
    }

    // MARK: - Subtitle Stream Row

    @ViewBuilder
    private func subtitleStreamRow(_ stream: MediaStream) -> some View {
        let hasOverride = perStream.subtitleOverrides[stream.streamIndex] != nil

        HStack {
            Label("Subtitle #\(stream.streamIndex)", systemImage: "captions.bubble")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(stream.summaryString)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            Toggle("Include", isOn: Binding(
                get: { perStream.subtitleOverrides[stream.streamIndex]?.include ?? true },
                set: { include in
                    perStream.subtitleOverrides[stream.streamIndex] = SubtitleStreamOverride(
                        include: include,
                        passthrough: perStream.subtitleOverrides[stream.streamIndex]?.passthrough ?? true
                    )
                }
            ))

            if hasOverride {
                Text("Custom")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Bindings

    private func videoOverrideBinding(for index: Int) -> Binding<VideoStreamOverride> {
        Binding(
            get: { perStream.videoOverrides[index] ?? VideoStreamOverride() },
            set: { perStream.videoOverrides[index] = $0 }
        )
    }

    private func audioOverrideBinding(for index: Int) -> Binding<AudioStreamOverride> {
        Binding(
            get: { perStream.audioOverrides[index] ?? AudioStreamOverride() },
            set: { perStream.audioOverrides[index] = $0 }
        )
    }

    // MARK: - Load / Apply

    private func loadExistingSettings() {
        if let existing = viewModel.selectedProfile.perStreamSettings {
            perStream = existing
        }
    }

    private func applySettings() {
        viewModel.selectedProfile.perStreamSettings = perStream.hasOverrides ? perStream : nil
        let overrideCount = perStream.videoOverrides.count + perStream.audioOverrides.count + perStream.subtitleOverrides.count
        viewModel.appendLog(.info, "Applied per-stream encoding overrides for \(overrideCount) stream(s)",
                            category: .encoding)
    }
}
