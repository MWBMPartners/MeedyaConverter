// File: adaptix/ui/components/EncodingProfilePickerView.swift
// Purpose: SwiftUI view to select, edit, or create new encoding profiles
// Role: Bridges user interaction with the EncodingProfileStore for modular encoding, including encryption key fallback awareness
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services)
// Version: 1.2.0

import SwiftUI

/// Displays a list of saved encoding profiles and allows selection/editing.
struct EncodingProfilePickerView: View {
    @ObservedObject var store = EncodingProfileStore.shared
    @Binding var selectedProfile: EncodingProfile?
    @State private var showEditor = false
    @State private var editingProfile: EncodingProfile? = nil

    var body: some View {
        VStack(alignment: .leading) {
            Text("🎛️ Select Encoding Profile")
                .font(.headline)

            List {
                ForEach(store.profiles) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(profile.name)
                                .fontWeight(profile.id == selectedProfile?.id ? .bold : .regular)
                            Spacer()
                            Button("Edit") {
                                editingProfile = profile
                                showEditor = true
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }

                        // 🔐 Display encryption settings summary
                        if profile.enableEncryption {
                            Text("🔐 Encrypted")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("🚫 No Encryption")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedProfile = profile
                    }
                }
            }

            Button("➕ Create New Profile") {
                editingProfile = EncodingProfile(
                    name: "New Profile",
                    videoCodec: "H264",
                    crf: 23,
                    maxVideoBitrate: "4M",
                    useMultipass: false,
                    retainHDR: false,
                    includeWatermark: false,
                    audioCodec: "AAC",
                    audioBitrateMode: "VBR",
                    audioBitrate: "192k",
                    normalizeAudio: false,
                    enableProLogicII: false,
                    embedBroadcastCaptions: true,
                    preserveSubtitleStyle: true,
                    separateAV: true,
                    enableEncryption: true,
                    encryptionKey: "",  // ✳️ Use fallback if blank
                    encryptionKeyURL: "" // ✳️ Resolved at manifest generation
                )
                showEditor = true
            }
            .padding(.top)
        }
        .sheet(isPresented: $showEditor) {
            if let editingProfile = editingProfile {
                EncodingProfileView(profile: editingProfile) { updated in
                    EncodingProfileStore.shared.saveOrUpdate(updated)
                    selectedProfile = updated
                }
            }
        }
    }
}