// File: adaptix/ui/EncodingProfileView.swift
// Purpose: SwiftUI interface for creating, editing, and saving encoding profiles
// Role: Lets the user define complete streaming settings visually for video/audio/subtitles, stored as EncodingProfile objects
// 
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services)
// Version: 1.0.0

import SwiftUI

/// SwiftUI view that allows users to configure a full encoding profile
struct EncodingProfileView: View {
    @ObservedObject var viewModel: EncodingProfileViewModel

    var body: some View {
        Form {
            Section(header: Text("🎞 Video Settings")) {
                Picker("Codec", selection: $viewModel.videoCodec) {
                    ForEach(viewModel.availableVideoCodecs, id: \.\self) { Text($0) }
                }
                Toggle("Retain HDR Metadata", isOn: $viewModel.retainHDR)
                Stepper(value: $viewModel.crf, in: 0...51) {
                    Text("CRF: \(viewModel.crf)")
                }
                TextField("Max Bitrate (kbps)", text: $viewModel.maxVideoBitrate)
                Toggle("Enable Multipass", isOn: $viewModel.useMultipass)
                Toggle("Watermark", isOn: $viewModel.includeWatermark)
            }

            Section(header: Text("🔊 Audio Settings")) {
                Picker("Codec", selection: $viewModel.audioCodec) {
                    ForEach(viewModel.availableAudioCodecs, id: \.\self) { Text($0) }
                }
                Picker("Bitrate Mode", selection: $viewModel.audioBitrateMode) {
                    ForEach(viewModel.availableAudioModes, id: \.\self) { Text($0) }
                }
                TextField("Bitrate (kbps)", text: $viewModel.audioBitrate)
                Toggle("Normalize (ReplayGain/EBU)", isOn: $viewModel.normalizeAudio)
                Toggle("Downmix Pro Logic II", isOn: $viewModel.enableProLogicII)
            }

            Section(header: Text("💬 Subtitle Options")) {
                Toggle("Embed CEA-608/708/709", isOn: $viewModel.embedBroadcastCaptions)
                Toggle("Preserve SSA/ASS formatting", isOn: $viewModel.preserveSubtitleStyle)
            }

            Section(header: Text("📦 Packaging")) {
                Toggle("Separate Video & Audio Streams", isOn: $viewModel.separateAV)
                Toggle("AES-128 Encryption", isOn: $viewModel.enableEncryption)
                TextField("Profile Name", text: $viewModel.profileName)
                Button("💾 Save Profile") {
                    viewModel.saveProfile()
                }
            }
        }
        .navigationTitle("🎛 Encoding Profile")
        .padding()
    }
}

#Preview {
    EncodingProfileView(viewModel: EncodingProfileViewModel())
} // 📚 ViewModel will define default values and I/O to EncodingProfile model
