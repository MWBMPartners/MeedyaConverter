// File: adaptix/core/FFmpegArgumentBuilder.swift
// Purpose: Constructs FFmpeg command-line arguments from EncodingProfile for video/audio/subtitle tracks
// Role: Supports FFmpegController by providing modular, reusable, profile-driven argument generation for encoding passes
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

/// FFmpegArgumentBuilder generates command-line arguments for FFmpeg based on user-selected EncodingProfile.
/// It is used by FFmpegController to construct encoding pipelines for video/audio/subtitle processing.
struct FFmpegArgumentBuilder {

    /// Builds arguments for encoding video separately.
    /// - Parameter profile: EncodingProfile containing video settings.
    /// - Returns: FFmpeg-compatible argument list.
    static func buildVideoArguments(from profile: EncodingProfile) -> [String] {
        var args: [String] = []
        
        // Input file
        args += ["-i", profile.inputPath]
        
        // Video codec and quality
        args += ["-c:v", profile.videoCodec.rawValue]
        args += ["-crf", String(profile.videoCRF)]
        if profile.videoMaxBitrate > 0 {
            args += ["-maxrate", "\(profile.videoMaxBitrate)k"]
            args += ["-bufsize", "\(profile.videoMaxBitrate * 2)k"]
        }

        // HDR metadata copy
        if profile.retainHDRMetadata {
            args += ["-color_primaries", "bt2020"]
            args += ["-colorspace", "bt2020nc"]
            args += ["-color_trc", "smpte2084"]
        }

        // Keyframe interval
        if let gop = profile.keyframeInterval {
            args += ["-g", String(gop)]
        }

        // Multipass
        if profile.videoPasses == 2 {
            args += ["-pass", "1"] // This should be looped externally for pass=1 then pass=2
        }

        // Watermarking
        if let watermarkPath = profile.videoWatermarkPath {
            args += ["-vf", "movie='\(watermarkPath)'[wm];[in][wm]overlay=10:10[out]"]
        }

        // Output
        args += ["-f", "mp4", profile.outputVideoPath]
        
        return args
    }

    /// Builds arguments for encoding audio separately.
    /// - Parameter profile: EncodingProfile containing audio settings.
    /// - Returns: FFmpeg-compatible argument list.
    static func buildAudioArguments(from profile: EncodingProfile) -> [String] {
        var args: [String] = []
        
        args += ["-i", profile.inputPath]
        args += ["-vn"] // No video
        args += ["-c:a", profile.audioCodec.rawValue]

        // Bitrate and normalization
        if profile.audioBitrate > 0 {
            args += ["-b:a", "\(profile.audioBitrate)k"]
        }

        if profile.audioNormalize {
            args += ["-af", "loudnorm"]
        }

        // Sample rate and depth
        if let sampleRate = profile.audioSampleRate {
            args += ["-ar", String(sampleRate)]
        }

        if let bitDepth = profile.audioBitDepth {
            args += ["-sample_fmt", bitDepth == 16 ? "s16" : bitDepth == 24 ? "s32" : "fltp"]
        }

        args += ["-f", "mp4", profile.outputAudioPath]

        return args
    }

    /// Builds arguments for subtitle extraction or conversion.
    /// - Parameter profile: EncodingProfile containing subtitle settings.
    /// - Returns: FFmpeg-compatible argument list.
    static func buildSubtitleArguments(from profile: EncodingProfile) -> [String] {
        var args: [String] = []

        args += ["-i", profile.inputPath]
        args += ["-map", "0:s:0"] // First subtitle stream (adjustable later)

        args += ["-c:s", profile.subtitleCodec.rawValue] // e.g., srt, webvtt, ass
        args += [profile.outputSubtitlePath ?? "output_subs.srt"]

        return args
    }
}

// 📑 See: https://ffmpeg.org/ffmpeg-codecs.html for supported codecs
// 🔸 Use one function at a time in separate FFmpeg calls for separate outputs
// 🪙 Pipe-based progress monitoring is managed by FFmpegController.swift
