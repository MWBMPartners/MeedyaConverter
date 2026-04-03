// ============================================================================
// MeedyaConverter — EncodingProfile
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - EncodingProfile

/// A reusable encoding preset that defines video, audio, and container settings.
///
/// Profiles can be built-in (shipped with the app), user-created, or imported.
/// They are serialised as JSON for persistence and sharing.
public struct EncodingProfile: Identifiable, Codable, Sendable, Equatable {

    // MARK: - Identity

    /// Unique identifier for this profile.
    public let id: UUID

    /// Human-readable name for this profile (e.g., "Web Standard", "4K HDR Master").
    public var name: String

    /// Description of what this profile is optimised for.
    public var description: String

    /// Category for UI grouping (e.g., "Quick Start", "Streaming", "Disc", "Custom").
    public var category: ProfileCategory

    /// Whether this is a built-in (non-deletable) profile.
    public var isBuiltIn: Bool

    // MARK: - Video Settings

    /// The video codec for encoding.
    public var videoCodec: VideoCodec?

    /// Whether to passthrough video without re-encoding.
    public var videoPassthrough: Bool

    /// CRF value for quality-based VBR encoding (software encoders).
    public var videoCRF: Int?

    /// QP value for hardware encoders.
    public var videoQP: Int?

    /// Target video bitrate in bits per second (for CBR/CVBR modes).
    public var videoBitrate: Int?

    /// Maximum video bitrate for CVBR mode.
    public var videoMaxBitrate: Int?

    /// Video encoder preset (e.g., "medium", "slow").
    public var videoPreset: String?

    /// Video encoder tune (e.g., "film", "animation").
    public var videoTune: String?

    /// Output resolution width. Nil means match source.
    public var outputWidth: Int?

    /// Output resolution height. Nil means match source.
    public var outputHeight: Int?

    /// Output frame rate. Nil means match source.
    public var outputFrameRate: Double?

    /// Pixel format (e.g., "yuv420p", "yuv420p10le").
    public var pixelFormat: String?

    /// Whether to use hardware encoding when available.
    public var useHardwareEncoding: Bool

    /// Number of encoding passes (1 or 2).
    public var encodingPasses: Int

    /// Whether to preserve HDR metadata when source is HDR.
    public var preserveHDR: Bool

    // MARK: - Audio Settings

    /// The audio codec for encoding.
    public var audioCodec: AudioCodec?

    /// Whether to passthrough audio without re-encoding.
    public var audioPassthrough: Bool

    /// Audio bitrate in bits per second.
    public var audioBitrate: Int?

    /// Audio sample rate in Hz. Nil means match source.
    public var audioSampleRate: Int?

    /// Number of audio channels. Nil means match source.
    public var audioChannels: Int?

    // MARK: - Subtitle Settings

    /// Whether to passthrough subtitles.
    public var subtitlePassthrough: Bool

    // MARK: - Container

    /// The output container format.
    public var containerFormat: ContainerFormat

    // MARK: - Streaming (CVBR settings for HLS/DASH)

    /// Keyframe interval in seconds (for adaptive streaming).
    public var keyframeIntervalSeconds: Double?

    /// VBV buffer size in bits (for CVBR mode).
    public var videoBufferSize: Int?

    // MARK: - Initialiser

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        category: ProfileCategory = .custom,
        isBuiltIn: Bool = false,
        videoCodec: VideoCodec? = .h265,
        videoPassthrough: Bool = false,
        videoCRF: Int? = 22,
        videoQP: Int? = nil,
        videoBitrate: Int? = nil,
        videoMaxBitrate: Int? = nil,
        videoPreset: String? = "medium",
        videoTune: String? = nil,
        outputWidth: Int? = nil,
        outputHeight: Int? = nil,
        outputFrameRate: Double? = nil,
        pixelFormat: String? = nil,
        useHardwareEncoding: Bool = false,
        encodingPasses: Int = 1,
        preserveHDR: Bool = true,
        audioCodec: AudioCodec? = .aacLC,
        audioPassthrough: Bool = false,
        audioBitrate: Int? = 160_000,
        audioSampleRate: Int? = nil,
        audioChannels: Int? = nil,
        subtitlePassthrough: Bool = true,
        containerFormat: ContainerFormat = .mkv,
        keyframeIntervalSeconds: Double? = nil,
        videoBufferSize: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.isBuiltIn = isBuiltIn
        self.videoCodec = videoCodec
        self.videoPassthrough = videoPassthrough
        self.videoCRF = videoCRF
        self.videoQP = videoQP
        self.videoBitrate = videoBitrate
        self.videoMaxBitrate = videoMaxBitrate
        self.videoPreset = videoPreset
        self.videoTune = videoTune
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.outputFrameRate = outputFrameRate
        self.pixelFormat = pixelFormat
        self.useHardwareEncoding = useHardwareEncoding
        self.encodingPasses = encodingPasses
        self.preserveHDR = preserveHDR
        self.audioCodec = audioCodec
        self.audioPassthrough = audioPassthrough
        self.audioBitrate = audioBitrate
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.subtitlePassthrough = subtitlePassthrough
        self.containerFormat = containerFormat
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
        self.videoBufferSize = videoBufferSize
    }

    // MARK: - Argument Builder Conversion

    /// Convert this profile into an FFmpegArgumentBuilder with the settings applied.
    ///
    /// - Parameters:
    ///   - inputURL: The source file URL.
    ///   - outputURL: The destination file URL.
    /// - Returns: A configured FFmpegArgumentBuilder ready to build() arguments.
    public func toArgumentBuilder(inputURL: URL, outputURL: URL) -> FFmpegArgumentBuilder {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = inputURL
        builder.outputURL = outputURL

        // Video
        builder.videoPassthrough = videoPassthrough
        builder.videoCodec = videoPassthrough ? nil : videoCodec
        builder.videoCRF = videoCRF
        builder.videoQP = videoQP
        builder.videoBitrate = videoBitrate
        builder.videoMaxBitrate = videoMaxBitrate
        builder.videoBufferSize = videoBufferSize
        builder.videoWidth = outputWidth
        builder.videoHeight = outputHeight
        builder.videoFrameRate = outputFrameRate
        builder.pixelFormat = pixelFormat
        builder.videoPreset = videoPreset
        builder.videoTune = videoTune
        builder.useHardwareEncoding = useHardwareEncoding
        builder.encodingPasses = encodingPasses
        builder.keyframeInterval = keyframeIntervalSeconds

        // Audio
        builder.audioPassthrough = audioPassthrough
        builder.audioCodec = audioPassthrough ? nil : audioCodec
        builder.audioBitrate = audioBitrate
        builder.audioSampleRate = audioSampleRate
        builder.audioChannels = audioChannels

        // Subtitles
        builder.subtitlePassthrough = subtitlePassthrough

        // Container
        builder.containerFormat = containerFormat

        return builder
    }
}

// MARK: - ProfileCategory

/// Categories for grouping encoding profiles in the UI.
public enum ProfileCategory: String, Codable, Sendable, CaseIterable {
    /// Quick-start profiles for common use cases.
    case quickStart = "quick_start"

    /// Profiles optimised for adaptive streaming (HLS/DASH).
    case streaming

    /// Profiles for optical disc authoring (DVD, Blu-ray).
    case disc

    /// Profiles for archival/preservation.
    case archival

    /// User-created custom profiles.
    case custom

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .quickStart: return "Quick Start"
        case .streaming: return "Streaming"
        case .disc: return "Disc Authoring"
        case .archival: return "Archival"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Built-In Profiles

extension EncodingProfile {

    /// All built-in profiles shipped with MeedyaConverter.
    public static let builtInProfiles: [EncodingProfile] = [
        .webStandard,
        .webHighQuality,
        .webNextGen,
        .fourKHDRMaster,
        .audioExtract,
        .quickConvert,
        .archiveLossless,
    ]

    /// Web Standard — H.264/AAC in MP4, maximum compatibility.
    public static let webStandard = EncodingProfile(
        name: "Web Standard",
        description: "H.264 + AAC in MP4 — maximum compatibility for web playback",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: 20,
        videoPreset: "medium",
        audioCodec: .aacLC,
        audioBitrate: 160_000,
        containerFormat: .mp4
    )

    /// Web High Quality — H.265/AAC in MP4, better quality at smaller size.
    public static let webHighQuality = EncodingProfile(
        name: "Web High Quality",
        description: "H.265 + AAC in MP4 — better quality, smaller files",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 22,
        videoPreset: "medium",
        audioCodec: .aacLC,
        audioBitrate: 192_000,
        containerFormat: .mp4
    )

    /// Web Next-Gen — AV1/Opus in WebM, best compression efficiency.
    public static let webNextGen = EncodingProfile(
        name: "Web Next-Gen",
        description: "AV1 + Opus in WebM — best efficiency for modern browsers",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .av1,
        videoCRF: 30,
        videoPreset: "6", // SVT-AV1 preset
        audioCodec: .opus,
        audioBitrate: 128_000,
        containerFormat: .webm
    )

    /// 4K HDR Master — H.265/E-AC-3 in MKV, high-quality archive with HDR.
    public static let fourKHDRMaster = EncodingProfile(
        name: "4K HDR Master",
        description: "H.265 HDR + E-AC-3 7.1 in MKV — high-quality archive",
        category: .archival,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 18,
        videoPreset: "slow",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        audioCodec: .eac3,
        audioBitrate: 640_000,
        audioChannels: 8,
        containerFormat: .mkv
    )

    /// Audio Extract — extract and convert audio to FLAC.
    public static let audioExtract = EncodingProfile(
        name: "Audio Extract (FLAC)",
        description: "Extract audio to lossless FLAC — no video",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: nil,
        videoPassthrough: false,
        videoCRF: nil,
        videoPreset: nil,
        audioCodec: .flac,
        audioBitrate: nil, // Lossless — no bitrate needed
        containerFormat: .mka
    )

    /// Quick Convert — fast H.264 at reasonable quality.
    public static let quickConvert = EncodingProfile(
        name: "Quick Convert",
        description: "Fast H.264 encode — good enough quality, maximum speed",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: 23,
        videoPreset: "fast",
        audioCodec: .aacLC,
        audioBitrate: 128_000,
        containerFormat: .mp4
    )

    /// Archive Lossless — FFV1/FLAC in MKV for archival preservation.
    public static let archiveLossless = EncodingProfile(
        name: "Archive (Lossless)",
        description: "FFV1 + FLAC in MKV — lossless archival preservation",
        category: .archival,
        isBuiltIn: true,
        videoCodec: .ffv1,
        videoCRF: nil,
        videoPreset: nil,
        audioCodec: .flac,
        audioBitrate: nil,
        containerFormat: .mkv
    )
}

// MARK: - EncodingProfileStore

/// Manages the collection of encoding profiles (built-in + user-created).
///
/// Profiles are persisted as JSON in the app's support directory.
/// The store provides CRUD operations and JSON import/export.
public final class EncodingProfileStore: @unchecked Sendable {

    // MARK: - Properties

    /// All available profiles (built-in + user-created).
    public private(set) var profiles: [EncodingProfile]

    /// The file URL where user profiles are persisted.
    private let storageURL: URL

    /// Serial lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Initialiser

    /// Create a profile store with the given storage location.
    ///
    /// - Parameter storageDirectory: Directory where user profiles JSON is saved.
    ///   Defaults to Application Support/MeedyaConverter/Profiles/.
    public init(storageDirectory: URL? = nil) {
        let defaultDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MeedyaConverter")
            .appendingPathComponent("Profiles")

        let dir = storageDirectory ?? defaultDir
        self.storageURL = dir.appendingPathComponent("user_profiles.json")

        // Start with built-in profiles
        self.profiles = EncodingProfile.builtInProfiles

        // Load user profiles from disk
        loadUserProfiles()
    }

    // MARK: - CRUD Operations

    /// Add a new user-created profile.
    public func addProfile(_ profile: EncodingProfile) {
        lock.lock()
        defer { lock.unlock() }
        profiles.append(profile)
        saveUserProfiles()
    }

    /// Update an existing profile by ID.
    public func updateProfile(_ profile: EncodingProfile) {
        lock.lock()
        defer { lock.unlock() }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveUserProfiles()
        }
    }

    /// Delete a profile by ID. Built-in profiles cannot be deleted.
    public func deleteProfile(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        profiles.removeAll { $0.id == id && !$0.isBuiltIn }
        saveUserProfiles()
    }

    /// Get a profile by its name.
    public func profile(named name: String) -> EncodingProfile? {
        lock.lock()
        defer { lock.unlock() }
        return profiles.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Get a profile by its ID.
    public func profile(id: UUID) -> EncodingProfile? {
        lock.lock()
        defer { lock.unlock() }
        return profiles.first { $0.id == id }
    }

    /// All profiles in a specific category.
    public func profiles(in category: ProfileCategory) -> [EncodingProfile] {
        lock.lock()
        defer { lock.unlock() }
        return profiles.filter { $0.category == category }
    }

    // MARK: - Import/Export

    /// Export a profile to JSON data for sharing.
    public func exportProfile(_ profile: EncodingProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    /// Import a profile from JSON data.
    public func importProfile(from data: Data) throws -> EncodingProfile {
        let decoder = JSONDecoder()
        var profile = try decoder.decode(EncodingProfile.self, from: data)
        // Imported profiles are never built-in
        profile = EncodingProfile(
            id: UUID(), // Generate new ID to avoid conflicts
            name: profile.name,
            description: profile.description,
            category: .custom,
            isBuiltIn: false,
            videoCodec: profile.videoCodec,
            videoPassthrough: profile.videoPassthrough,
            videoCRF: profile.videoCRF,
            videoQP: profile.videoQP,
            videoBitrate: profile.videoBitrate,
            videoMaxBitrate: profile.videoMaxBitrate,
            videoPreset: profile.videoPreset,
            videoTune: profile.videoTune,
            outputWidth: profile.outputWidth,
            outputHeight: profile.outputHeight,
            outputFrameRate: profile.outputFrameRate,
            pixelFormat: profile.pixelFormat,
            useHardwareEncoding: profile.useHardwareEncoding,
            encodingPasses: profile.encodingPasses,
            preserveHDR: profile.preserveHDR,
            audioCodec: profile.audioCodec,
            audioPassthrough: profile.audioPassthrough,
            audioBitrate: profile.audioBitrate,
            audioSampleRate: profile.audioSampleRate,
            audioChannels: profile.audioChannels,
            subtitlePassthrough: profile.subtitlePassthrough,
            containerFormat: profile.containerFormat,
            keyframeIntervalSeconds: profile.keyframeIntervalSeconds,
            videoBufferSize: profile.videoBufferSize
        )
        addProfile(profile)
        return profile
    }

    // MARK: - Persistence

    /// Load user-created profiles from disk.
    private func loadUserProfiles() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            let userProfiles = try decoder.decode([EncodingProfile].self, from: data)
            profiles.append(contentsOf: userProfiles)
        } catch {
            // Log but don't crash — user can re-create profiles
            print("Warning: Could not load user profiles: \(error.localizedDescription)")
        }
    }

    /// Save user-created profiles to disk.
    private func saveUserProfiles() {
        let userProfiles = profiles.filter { !$0.isBuiltIn }

        do {
            // Ensure directory exists
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(userProfiles)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Warning: Could not save user profiles: \(error.localizedDescription)")
        }
    }
}
