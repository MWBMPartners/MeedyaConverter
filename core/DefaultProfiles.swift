// File: adaptix/core/DefaultProfiles.swift
// Purpose: Provides pre-configured encoding profiles for common streaming scenarios including Apple HLS, MPEG-DASH, and platform-specific requirements.
// Role: Offers ready-to-use profiles for users who want quick setup without manual configuration.
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

// MARK: - Default Profile Factory

class DefaultProfiles {

    // MARK: - Apple HLS Profiles

    /// Apple HLS recommended specifications for adaptive streaming
    /// Based on Apple's HLS Authoring Specification
    static func appleHLS() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "Apple HLS Standard",
            description: "Optimized for Apple devices following HLS authoring specifications",
            videoSettings: VideoSettings(
                codec: "h264",
                bitrateLadder: [8000, 6000, 4500, 3000, 2000, 1000, 500, 300],
                crf: nil, // Use bitrate mode for HLS
                maxBitrate: 10000,
                retainHDR: false,
                watermark: nil,
                multipass: true
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [256, 128, 64],
                normalization: true,
                replayGain: false,
                downmixToStereo: false
            ),
            subtitleSettings: SubtitleSettings(
                supportedFormats: ["webvtt"],
                embedCEA608: false
            ),
            outputFormat: "mp4",
            splitAudioVideo: true,
            encryption: nil,
            profile: nil
        )
    }

    /// Apple HLS with HDR10 support for modern Apple devices
    static func appleHLSHDR() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "Apple HLS HDR10",
            description: "Apple HLS with HDR10 support for iPhone 12+, iPad Pro, Apple TV 4K",
            videoSettings: VideoSettings(
                codec: "hevc",
                bitrateLadder: [10000, 8000, 6000, 4500, 3000],
                crf: nil,
                maxBitrate: 12000,
                retainHDR: true,
                watermark: nil,
                multipass: true
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [256, 128],
                normalization: true,
                replayGain: false,
                downmixToStereo: false
            ),
            subtitleSettings: SubtitleSettings(
                supportedFormats: ["webvtt"],
                embedCEA608: false
            ),
            outputFormat: "mp4",
            splitAudioVideo: true,
            encryption: nil,
            profile: "main10"
        )
    }

    // MARK: - MPEG-DASH Profiles

    /// Standard MPEG-DASH profile for cross-platform compatibility
    static func mpegDASH() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "MPEG-DASH Standard",
            description: "Cross-platform DASH profile for web, Android, and smart TVs",
            videoSettings: VideoSettings(
                codec: "h264",
                bitrateLadder: [8000, 6000, 4500, 3000, 2000, 1000, 500],
                crf: nil,
                maxBitrate: 10000,
                retainHDR: false,
                watermark: nil,
                multipass: true
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [192, 128, 64],
                normalization: true,
                replayGain: false,
                downmixToStereo: false
            ),
            subtitleSettings: SubtitleSettings(
                supportedFormats: ["ttml", "webvtt"],
                embedCEA608: false
            ),
            outputFormat: "mp4",
            splitAudioVideo: true,
            encryption: nil,
            profile: nil
        )
    }

    // MARK: - YouTube-Style ABR Ladder

    /// YouTube-style adaptive bitrate ladder
    static func youTubeStyle() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "YouTube-Style ABR",
            description: "Adaptive bitrate ladder similar to YouTube's encoding",
            videoSettings: VideoSettings(
                codec: "h264",
                bitrateLadder: [
                    // 4K
                    13000, 15000,
                    // 1440p
                    9000, 12000,
                    // 1080p
                    4500, 6000, 8000,
                    // 720p
                    2500, 4000,
                    // 480p
                    1000, 1500,
                    // 360p
                    600, 800,
                    // 240p
                    300, 400
                ],
                crf: 23,
                maxBitrate: 16000,
                retainHDR: false,
                watermark: nil,
                multipass: true
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [384, 256, 192, 128],
                normalization: true,
                replayGain: true,
                downmixToStereo: false
            ),
            subtitleSettings: SubtitleSettings(
                supportedFormats: ["webvtt", "srt"],
                embedCEA608: false
            ),
            outputFormat: "mp4",
            splitAudioVideo: true,
            encryption: nil,
            profile: nil
        )
    }

    // MARK: - High Efficiency Profiles

    /// Modern HEVC/H.265 profile for efficient streaming
    static func hevcEfficient() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "HEVC Efficient",
            description: "H.265/HEVC encoding for bandwidth-efficient streaming",
            videoSettings: VideoSettings(
                codec: "hevc",
                bitrateLadder: [6000, 4500, 3000, 2000, 1000, 500],
                crf: 28,
                maxBitrate: 8000,
                retainHDR: true,
                watermark: nil,
                multipass: true
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [192, 128, 64],
                normalization: true,
                replayGain: false,
                downmixToStereo: false
            ),
            subtitleSettings: SubtitleSettings(
                supportedFormats: ["webvtt"],
                embedCEA608: false
            ),
            outputFormat: "mp4",
            splitAudioVideo: true,
            encryption: nil,
            profile: "main"
        )
    }

    /// AV1 profile for next-generation efficient streaming
    static func av1NextGen() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "AV1 Next-Gen",
            description: "AV1 encoding for maximum efficiency (slower encoding)",
            videoSettings: VideoSettings(
                codec: "av1",
                bitrateLadder: [5000, 3500, 2500, 1500, 800, 400],
                crf: 32,
                maxBitrate: 6000,
                retainHDR: true,
                watermark: nil,
                multipass: true
            ),
            audioSettings: AudioSettings(
                codec: "opus",
                bitrates: [192, 128, 64],
                normalization: true,
                replayGain: false,
                downmixToStereo: false
            ),
            subtitleSettings: SubtitleSettings(
                supportedFormats: ["webvtt"],
                embedCEA608: false
            ),
            outputFormat: "mp4",
            splitAudioVideo: true,
            encryption: nil,
            profile: nil
        )
    }

    // MARK: - Audio-Only Profiles

    /// Podcast/Audio streaming profile
    static func podcast() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "Podcast/Audio Only",
            description: "Optimized for voice content and music streaming",
            videoSettings: nil,
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [192, 128, 64, 32],
                normalization: true,
                replayGain: true,
                downmixToStereo: true
            ),
            subtitleSettings: nil,
            outputFormat: "m4a",
            splitAudioVideo: false,
            encryption: nil,
            profile: nil
        )
    }

    /// Music streaming profile with high quality
    static func musicStreaming() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "Music Streaming",
            description: "High-quality audio streaming for music content",
            videoSettings: nil,
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [320, 256, 192, 128],
                normalization: false,
                replayGain: true,
                downmixToStereo: false
            ),
            subtitleSettings: nil,
            outputFormat: "m4a",
            splitAudioVideo: false,
            encryption: nil,
            profile: nil
        )
    }

    // MARK: - Platform-Specific Profiles

    /// Facebook video specifications
    static func facebook() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "Facebook Video",
            description: "Optimized for Facebook video platform",
            videoSettings: VideoSettings(
                codec: "h264",
                bitrateLadder: [4000, 2000, 1000],
                crf: 23,
                maxBitrate: 5000,
                retainHDR: false,
                watermark: nil,
                multipass: false
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [128],
                normalization: true,
                replayGain: false,
                downmixToStereo: true
            ),
            subtitleSettings: SubtitleSettings(
                supportedFormats: ["srt"],
                embedCEA608: false
            ),
            outputFormat: "mp4",
            splitAudioVideo: false,
            encryption: nil,
            profile: "high"
        )
    }

    /// Twitter/X video specifications
    static func twitter() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "Twitter/X Video",
            description: "Optimized for Twitter/X platform (max 2min 20sec)",
            videoSettings: VideoSettings(
                codec: "h264",
                bitrateLadder: [6000, 3000, 1000],
                crf: 23,
                maxBitrate: 8000,
                retainHDR: false,
                watermark: nil,
                multipass: false
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [128],
                normalization: true,
                replayGain: false,
                downmixToStereo: true
            ),
            subtitleSettings: nil,
            outputFormat: "mp4",
            splitAudioVideo: false,
            encryption: nil,
            profile: "high"
        )
    }

    // MARK: - Archival/Master Profiles

    /// High-quality archival profile
    static func archival() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "Archival Master",
            description: "High-quality preservation encoding",
            videoSettings: VideoSettings(
                codec: "hevc",
                bitrateLadder: [20000],
                crf: 18,
                maxBitrate: 25000,
                retainHDR: true,
                watermark: nil,
                multipass: true
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [320],
                normalization: false,
                replayGain: false,
                downmixToStereo: false
            ),
            subtitleSettings: SubtitleSettings(
                supportedFormats: ["ass", "srt"],
                embedCEA608: false
            ),
            outputFormat: "mp4",
            splitAudioVideo: false,
            encryption: nil,
            profile: "main10"
        )
    }

    // MARK: - Low Bandwidth Profiles

    /// Ultra-low bandwidth for slow connections
    static func lowBandwidth() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "Low Bandwidth",
            description: "Optimized for slow connections (mobile 3G)",
            videoSettings: VideoSettings(
                codec: "h264",
                bitrateLadder: [400, 250, 150],
                crf: 28,
                maxBitrate: 500,
                retainHDR: false,
                watermark: nil,
                multipass: false
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [48, 32],
                normalization: true,
                replayGain: false,
                downmixToStereo: true
            ),
            subtitleSettings: SubtitleSettings(
                supportedFormats: ["webvtt"],
                embedCEA608: false
            ),
            outputFormat: "mp4",
            splitAudioVideo: true,
            encryption: nil,
            profile: "baseline"
        )
    }

    // MARK: - Testing/Development Profiles

    /// Fast encoding for testing
    static func fastTest() -> EncodingProfile {
        EncodingProfile(
            id: UUID(),
            name: "Fast Test",
            description: "Quick encoding for testing (low quality)",
            videoSettings: VideoSettings(
                codec: "h264",
                bitrateLadder: [1000],
                crf: 28,
                maxBitrate: 1500,
                retainHDR: false,
                watermark: nil,
                multipass: false
            ),
            audioSettings: AudioSettings(
                codec: "aac",
                bitrates: [128],
                normalization: false,
                replayGain: false,
                downmixToStereo: true
            ),
            subtitleSettings: nil,
            outputFormat: "mp4",
            splitAudioVideo: false,
            encryption: nil,
            profile: "baseline"
        )
    }

    // MARK: - Profile Collection

    /// Returns all available default profiles
    static func allProfiles() -> [EncodingProfile] {
        return [
            appleHLS(),
            appleHLSHDR(),
            mpegDASH(),
            youTubeStyle(),
            hevcEfficient(),
            av1NextGen(),
            podcast(),
            musicStreaming(),
            facebook(),
            twitter(),
            archival(),
            lowBandwidth(),
            fastTest()
        ]
    }

    /// Returns profiles filtered by category
    static func profiles(for category: ProfileCategory) -> [EncodingProfile] {
        switch category {
        case .streaming:
            return [appleHLS(), appleHLSHDR(), mpegDASH(), youTubeStyle()]
        case .efficient:
            return [hevcEfficient(), av1NextGen(), lowBandwidth()]
        case .audio:
            return [podcast(), musicStreaming()]
        case .social:
            return [facebook(), twitter()]
        case .archival:
            return [archival()]
        case .development:
            return [fastTest()]
        }
    }

    /// Profile categories for organization
    enum ProfileCategory: String, CaseIterable {
        case streaming = "Streaming Platforms"
        case efficient = "Efficient/Modern Codecs"
        case audio = "Audio Only"
        case social = "Social Media"
        case archival = "Archival/Master"
        case development = "Development/Testing"
    }
}

// MARK: - Profile Extensions

extension EncodingProfile {

    /// Returns a user-friendly summary of the profile
    var summary: String {
        var summary = "\(name)\n\(description)\n\n"

        if let video = videoSettings {
            summary += "Video: \(video.codec.uppercased())\n"
            summary += "Bitrates: \(video.bitrateLadder.map { "\($0)kbps" }.joined(separator: ", "))\n"
            if video.retainHDR {
                summary += "HDR: Enabled\n"
            }
            if video.multipass {
                summary += "Multi-pass: Enabled\n"
            }
        }

        if let audio = audioSettings {
            summary += "\nAudio: \(audio.codec.uppercased())\n"
            summary += "Bitrates: \(audio.bitrates.map { "\($0)kbps" }.joined(separator: ", "))\n"
            if audio.normalization {
                summary += "Normalization: Enabled\n"
            }
        }

        return summary
    }

    /// Validates that the profile is properly configured
    func validate() throws {
        if videoSettings == nil && audioSettings == nil {
            throw ProfileError.noCodecsConfigured
        }

        if let video = videoSettings {
            if video.bitrateLadder.isEmpty {
                throw ProfileError.emptyBitrateLadder
            }
        }
    }
}

// MARK: - Errors

enum ProfileError: Error, LocalizedError {
    case noCodecsConfigured
    case emptyBitrateLadder
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .noCodecsConfigured:
            return "Profile must have video or audio settings configured"
        case .emptyBitrateLadder:
            return "Video bitrate ladder cannot be empty"
        case .invalidConfiguration:
            return "Profile configuration is invalid"
        }
    }
}
