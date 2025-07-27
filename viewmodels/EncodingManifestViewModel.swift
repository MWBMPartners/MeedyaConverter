// File: adaptix/viewmodels/EncodingManifestViewModel.swift
// Purpose: ViewModel managing manifest generation state and logic for HLS/DASH adaptive streaming
// Role: Central logic hub for manifest creation, encryption hierarchy, validation, and logging
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services)
// Version: 1.3.0

import Foundation
import Combine

/// ViewModel that handles the logic for manifest generation, including encryption, track metadata, and progress.
class EncodingManifestViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedVideoTracks: [MediaTrack] = []
    @Published var selectedAudioTracks: [MediaTrack] = []
    @Published var selectedSubtitleTracks: [MediaTrack] = []

    @Published var groupID: String = "adaptix"
    @Published var defaultLanguage: String = "en"
    @Published var autoGenerateEncryptionKey: Bool = true

    @Published var appLevelEncryptionKey: String = ""
    @Published var profileEncryptionKey: String = ""
    @Published var jobEncryptionKey: String = ""

    @Published var encryptionKeyURL: String = ""
    @Published var useEncryption: Bool = false

    @Published var logs: [String] = []
    @Published var generationInProgress: Bool = false
    @Published var showSuccessBanner: Bool = false

    // MARK: - Internal Helpers

    /// Generates a manifest using a given encoding profile and the selected tracks.
    func generateManifest(usingProfile profile: EncodingProfile) {
        logs.removeAll()
        generationInProgress = true

        let key = resolveEncryptionKey(usingProfile: profile)
        let encryptionEnabled = (key != nil && !key!.isEmpty)

        log("📁 Starting manifest generation...")
        log("🔐 Encryption: \(encryptionEnabled ? "Enabled" : "Disabled")")

        ManifestGenerator.generate(
            videoTracks: selectedVideoTracks,
            audioTracks: selectedAudioTracks,
            subtitleTracks: selectedSubtitleTracks,
            groupID: groupID,
            defaultLanguage: defaultLanguage,
            encryptionKey: key,
            encryptionKeyURL: encryptionKeyURL,
            useEncryption: encryptionEnabled
        ) { success, message in
            DispatchQueue.main.async {
                self.generationInProgress = false
                self.logs.append(contentsOf: message.split(separator: "\n").map(String.init))
                self.showSuccessBanner = success
                if success {
                    self.log("✅ Manifest generation complete.")
                } else {
                    self.log("❌ Manifest generation failed.")
                }
            }
        }
    }

    /// Determine the effective encryption key based on job > profile > app-level > auto-generated fallback.
    private func resolveEncryptionKey(usingProfile profile: EncodingProfile) -> String? {
        if !jobEncryptionKey.isEmpty {
            return jobEncryptionKey
        }
        if !profile.encryptionKey.isEmpty {
            return profile.encryptionKey
        }
        if !appLevelEncryptionKey.isEmpty {
            return appLevelEncryptionKey
        }
        if autoGenerateEncryptionKey {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return nil // fallback disables encryption
    }

    /// Logs a message to the internal console
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append(message)
        }
    }

    /// Validates manifest parameters
    func validateInputs() -> Bool {
        guard !selectedVideoTracks.isEmpty else {
            log("⚠️ No video tracks selected.")
            return false
        }
        guard !selectedAudioTracks.isEmpty else {
            log("⚠️ No audio tracks selected.")
            return false
        }
        return true
    }
}
