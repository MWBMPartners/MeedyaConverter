// File: adaptix/core/EncodingProfile.swift
// Purpose: Defines reusable encoding presets for adaptive streaming. Includes parameters for video/audio formats, bitrates, quality ladders, and optional subtitle handling.
// Role: Core configuration component used by FFmpegController to consistently apply settings across batch or manual jobs.
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

/// A struct representing a full encoding configuration profile.
/// This is serializable and user-definable, and may be saved for reuse or distributed with the app.
struct EncodingProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String

    // MARK: - Video Settings
    var videoCodec: String // e.g., "libx264", "libx265", "libvpx-vp9", "libaom-av1"
    var videoBitrates: [Int] // in kbps
    var videoCRF: Int
    var videoMaxBitrate: Int?
    var retainHDR: Bool
    var watermarkPath: String?
    var enableMultipass: Bool

    // MARK: - Audio Settings
    var audioCodec: String // e.g., "aac", "ac3", "eac3", "flac"
    var audioBitrates: [Int] // in kbps
    var normalizeAudio: Bool
    var downmixToProLogicII: Bool

    // MARK: - Subtitle Settings
    var subtitleFormats: [String] // e.g., ["srt", "ass", "cea-608"]
    var embedCEA608: Bool

    // MARK: - Output and Behavior
    var containerFormat: String // e.g., "mp4", "mkv"
    var splitAudioVideo: Bool
    var enableEncryption: Bool
    var encryptionKeyPath: String?
    var enableReplayGain: Bool
    var allowPassthrough: Bool

    // MARK: - Initializer
    init(
        name: String,
        description: String,
        videoCodec: String,
        videoBitrates: [Int],
        videoCRF: Int,
        videoMaxBitrate: Int? = nil,
        retainHDR: Bool = false,
        watermarkPath: String? = nil,
        enableMultipass: Bool = true,
        audioCodec: String,
        audioBitrates: [Int],
        normalizeAudio: Bool = false,
        downmixToProLogicII: Bool = false,
        subtitleFormats: [String] = [],
        embedCEA608: Bool = false,
        containerFormat: String = "mp4",
        splitAudioVideo: Bool = true,
        enableEncryption: Bool = false,
        encryptionKeyPath: String? = nil,
        enableReplayGain: Bool = false,
        allowPassthrough: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.videoCodec = videoCodec
        self.videoBitrates = videoBitrates
        self.videoCRF = videoCRF
        self.videoMaxBitrate = videoMaxBitrate
        self.retainHDR = retainHDR
        self.watermarkPath = watermarkPath
        self.enableMultipass = enableMultipass
        self.audioCodec = audioCodec
        self.audioBitrates = audioBitrates
        self.normalizeAudio = normalizeAudio
        self.downmixToProLogicII = downmixToProLogicII
        self.subtitleFormats = subtitleFormats
        self.embedCEA608 = embedCEA608
        self.containerFormat = containerFormat
        self.splitAudioVideo = splitAudioVideo
        self.enableEncryption = enableEncryption
        self.encryptionKeyPath = encryptionKeyPath
        self.enableReplayGain = enableReplayGain
        self.allowPassthrough = allowPassthrough
    }
}

// 📚 Codec References:
// - https://ffmpeg.org/ffmpeg-codecs.html
// - https://developer.apple.com/documentation/coremedia/cmformatdescription
// - https://trac.ffmpeg.org/wiki/Encode/HighQuality