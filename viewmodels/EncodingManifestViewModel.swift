// File: adaptix/viewmodel/EncodingManifestViewModel.swift
// Purpose: ViewModel for managing manifest generation logic and state, powering ManifestGeneratorView
// Role: Handles inputs, validation, encryption logic, track handling, and calls ManifestGenerator
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services)
// Version: 1.0.0

import Foundation
import Combine

/// ViewModel to manage encoding manifest generation UI and logic.
class EncodingManifestViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var sourceVideoURL: URL? = nil
    @Published var outputDirectory: URL? = nil
    @Published var trackGroups: [TrackGroupConfig] = []
    @Published var selectedFormat: ManifestFormat = .hls
    @Published var encryptionKey: String = ""
    @Published var encryptionKeyURL: String = ""
    @Published var useEncryption: Bool = false
    @Published var autoGenerateEncryptionKey: Bool = false

    @Published var generationInProgress: Bool = false
    @Published var logs: String = ""
    @Published var manifestPreview: String = ""

    // MARK: - Error/State Flags
    @Published var validationError: String? = nil
    @Published var showToast: Bool = false
    @Published var toastMessage: String = ""

    // MARK: - Methods
    func validateInputs() -> Bool {
        guard sourceVideoURL != nil else {
            validationError = "❗ Please select a source video."
            return false
        }
        guard outputDirectory != nil else {
            validationError = "❗ Please select an output directory."
            return false
        }
        guard !trackGroups.isEmpty else {
            validationError = "❗ Please define at least one track group."
            return false
        }
        return true
    }

    func generateManifest(usingProfile profile: EncodingProfile?) {
        validationError = nil
        logs = ""
        manifestPreview = ""

        guard validateInputs() else {
            return
        }

        generationInProgress = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Determine encryption key from precedence hierarchy
            var effectiveKey = self.encryptionKey
            if effectiveKey.isEmpty {
                if profile?.encryptionKey.isEmpty == false {
                    effectiveKey = profile!.encryptionKey
                } else if self.autoGenerateEncryptionKey {
                    effectiveKey = Self.randomAESKey()
                }
            }

            let manifest = ManifestGenerator.generate(
                format: self.selectedFormat,
                source: self.sourceVideoURL!,
                outputDirectory: self.outputDirectory!,
                tracks: self.trackGroups,
                encryptionKey: effectiveKey,
                encryptionKeyURL: self.encryptionKeyURL,
                useEncryption: self.useEncryption && !effectiveKey.isEmpty
            )

            DispatchQueue.main.async {
                self.generationInProgress = false
                self.manifestPreview = manifest
                self.logs += "✅ Manifest generation complete."
                self.toastMessage = "✅ Manifest successfully generated."
                self.showToast = true
            }
        }
    }

    static func randomAESKey() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).map { String(format: "%02x", $0) }.joined()
    }
}
