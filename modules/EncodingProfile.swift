// File: adaptix/models/EncodingProfile.swift
// Purpose: Defines the data model and persistence logic for encoding profiles
// Role: Stores and loads encoding parameters for reuse in the encoding pipeline
// 
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services)
// Version: 1.0.0

import Foundation

/// A serializable struct representing a user-defined encoding profile.
struct EncodingProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var videoCodec: String
    var crf: Int
    var maxVideoBitrate: String
    var useMultipass: Bool
    var retainHDR: Bool
    var includeWatermark: Bool

    var audioCodec: String
    var audioBitrateMode: String
    var audioBitrate: String
    var normalizeAudio: Bool
    var enableProLogicII: Bool

    var embedBroadcastCaptions: Bool
    var preserveSubtitleStyle: Bool

    var separateAV: Bool
    var enableEncryption: Bool
}

/// Manages saving/loading of profiles to disk.
class EncodingProfileStore: ObservableObject {
    static let shared = EncodingProfileStore()
    private let filename = "encoding_profiles.json"
    @Published var profiles: [EncodingProfile] = []

    private init() {
        loadProfiles()
    }

    /// Loads profiles from the app’s document directory.
    func loadProfiles() {
        let url = profileFileURL()
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([EncodingProfile].self, from: data) {
            self.profiles = decoded
        }
    }

    /// Saves current profiles to disk.
    func saveProfiles() {
        let url = profileFileURL()
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: url)
        }
    }

    /// Adds a new profile and persists the change.
    func addProfile(_ profile: EncodingProfile) {
        profiles.append(profile)
        saveProfiles()
    }

    /// Overwrites an existing profile or appends it.
    func saveOrUpdate(_ profile: EncodingProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        saveProfiles()
    }

    /// File URL for storing profiles.
    private func profileFileURL() -> URL {
        let manager = FileManager.default
        let docs = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(filename)
    }
}