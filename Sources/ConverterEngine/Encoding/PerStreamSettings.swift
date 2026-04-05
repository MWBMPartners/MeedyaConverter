// ============================================================================
// MeedyaConverter — PerStreamSettings
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - PerStreamSettings

/// Per-stream encoding overrides that allow different codec, bitrate, and quality
/// settings for each individual stream in the output.
///
/// When attached to an `EncodingProfile`, these overrides take precedence over the
/// profile's global settings for the specified stream index. Streams without an
/// override inherit the profile defaults.
///
/// Phase 3.5 — Per-Stream Encoding Settings (Issue #41)
public struct PerStreamSettings: Codable, Sendable, Hashable {

    // MARK: - Video Stream Overrides

    /// Per-video-stream encoding overrides, keyed by output video stream index.
    public var videoOverrides: [Int: VideoStreamOverride]

    /// Per-audio-stream encoding overrides, keyed by output audio stream index.
    public var audioOverrides: [Int: AudioStreamOverride]

    /// Per-subtitle-stream encoding overrides, keyed by output subtitle stream index.
    public var subtitleOverrides: [Int: SubtitleStreamOverride]

    public init(
        videoOverrides: [Int: VideoStreamOverride] = [:],
        audioOverrides: [Int: AudioStreamOverride] = [:],
        subtitleOverrides: [Int: SubtitleStreamOverride] = [:]
    ) {
        self.videoOverrides = videoOverrides
        self.audioOverrides = audioOverrides
        self.subtitleOverrides = subtitleOverrides
    }

    /// Whether any per-stream overrides are configured.
    public var hasOverrides: Bool {
        !videoOverrides.isEmpty || !audioOverrides.isEmpty || !subtitleOverrides.isEmpty
    }
}

// MARK: - VideoStreamOverride

/// Encoding settings override for a single video stream.
public struct VideoStreamOverride: Codable, Sendable, Hashable {
    /// Video codec override. Nil means use profile default.
    public var codec: VideoCodec?

    /// Whether to passthrough (copy) this stream without re-encoding.
    public var passthrough: Bool?

    /// CRF override for quality-based encoding.
    public var crf: Int?

    /// QP override for hardware encoders.
    public var qp: Int?

    /// Bitrate override in bits per second.
    public var bitrate: Int?

    /// Maximum bitrate override in bits per second.
    public var maxBitrate: Int?

    /// Encoder preset override.
    public var preset: String?

    /// Output width override.
    public var width: Int?

    /// Output height override.
    public var height: Int?

    /// Frame rate override.
    public var frameRate: Double?

    public init(
        codec: VideoCodec? = nil,
        passthrough: Bool? = nil,
        crf: Int? = nil,
        qp: Int? = nil,
        bitrate: Int? = nil,
        maxBitrate: Int? = nil,
        preset: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil
    ) {
        self.codec = codec
        self.passthrough = passthrough
        self.crf = crf
        self.qp = qp
        self.bitrate = bitrate
        self.maxBitrate = maxBitrate
        self.preset = preset
        self.width = width
        self.height = height
        self.frameRate = frameRate
    }
}

// MARK: - AudioStreamOverride

/// Encoding settings override for a single audio stream.
public struct AudioStreamOverride: Codable, Sendable, Hashable {
    /// Audio codec override. Nil means use profile default.
    public var codec: AudioCodec?

    /// Whether to passthrough (copy) this stream without re-encoding.
    public var passthrough: Bool?

    /// Bitrate override in bits per second.
    public var bitrate: Int?

    /// Sample rate override in Hz.
    public var sampleRate: Int?

    /// Channel count override.
    public var channels: Int?

    /// Channel layout override (e.g., "stereo", "5.1").
    public var channelLayout: String?

    public init(
        codec: AudioCodec? = nil,
        passthrough: Bool? = nil,
        bitrate: Int? = nil,
        sampleRate: Int? = nil,
        channels: Int? = nil,
        channelLayout: String? = nil
    ) {
        self.codec = codec
        self.passthrough = passthrough
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.channelLayout = channelLayout
    }
}

// MARK: - SubtitleStreamOverride

/// Encoding settings override for a single subtitle stream.
public struct SubtitleStreamOverride: Codable, Sendable, Hashable {
    /// Whether to copy this subtitle stream to the output.
    public var include: Bool

    /// Whether to passthrough (copy) or convert the subtitle format.
    public var passthrough: Bool

    public init(
        include: Bool = true,
        passthrough: Bool = true
    ) {
        self.include = include
        self.passthrough = passthrough
    }
}
