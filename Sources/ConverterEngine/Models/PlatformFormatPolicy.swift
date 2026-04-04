// ============================================================================
// MeedyaConverter — PlatformFormatPolicy
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - PlatformFormatPolicy

/// Defines platform-specific format support and recommendations.
///
/// Different platforms (macOS, iOS, tvOS, web browsers, streaming services)
/// have varying codec and container support. This policy engine helps guide
/// users toward compatible format choices and warns when a selected
/// combination may not play on their target platform.
///
/// Phase 3.27 / Issue #192
public struct PlatformFormatPolicy: Sendable {

    /// A target playback platform with known format support.
    public enum Platform: String, Codable, Sendable, CaseIterable {
        case macOS
        case iOS
        case tvOS
        case windows
        case android
        case chromecast
        case webBrowser
        case plex
        case jellyfin
        case roku
        case fireTV

        /// Display name for UI.
        public var displayName: String {
            switch self {
            case .macOS: return "macOS"
            case .iOS: return "iOS / iPadOS"
            case .tvOS: return "Apple TV (tvOS)"
            case .windows: return "Windows"
            case .android: return "Android"
            case .chromecast: return "Chromecast"
            case .webBrowser: return "Web Browser"
            case .plex: return "Plex"
            case .jellyfin: return "Jellyfin"
            case .roku: return "Roku"
            case .fireTV: return "Fire TV"
            }
        }
    }

    /// A format compatibility result.
    public enum Compatibility: Sendable {
        /// Fully supported — will play without issues.
        case supported
        /// Supported but may require transcoding by the player/server.
        case transcodeMayBeRequired(reason: String)
        /// Not supported — will not play on this platform.
        case unsupported(reason: String)
    }

    /// Check whether a video codec is supported on a platform.
    public static func checkVideoCodec(_ codec: VideoCodec, on platform: Platform) -> Compatibility {
        switch platform {
        case .macOS, .iOS, .tvOS:
            switch codec {
            case .h264, .h265, .prores: return .supported
            case .av1: return .supported // macOS 13+, iOS 16+
            case .vp9: return .supported // Safari 16+
            case .vp8: return .transcodeMayBeRequired(reason: "VP8 has limited native support")
            case .mpeg2: return .supported
            default: return .unsupported(reason: "\(codec.rawValue) is not natively supported on Apple platforms")
            }

        case .windows:
            switch codec {
            case .h264, .h265: return .supported
            case .av1: return .supported // Windows 11+
            case .vp9: return .supported
            case .mpeg2: return .supported
            case .prores: return .transcodeMayBeRequired(reason: "ProRes requires codec pack on Windows")
            default: return .unsupported(reason: "\(codec.rawValue) has limited Windows support")
            }

        case .android, .chromecast, .fireTV:
            switch codec {
            case .h264: return .supported
            case .h265: return .supported // Most modern Android devices
            case .av1: return .transcodeMayBeRequired(reason: "AV1 requires Android 14+ or hardware support")
            case .vp9: return .supported
            case .vp8: return .supported
            default: return .unsupported(reason: "\(codec.rawValue) is not supported on Android")
            }

        case .webBrowser:
            switch codec {
            case .h264: return .supported
            case .h265: return .transcodeMayBeRequired(reason: "H.265 is not universally supported in browsers")
            case .vp8, .vp9: return .supported
            case .av1: return .supported // Chrome 70+, Firefox 98+
            default: return .unsupported(reason: "\(codec.rawValue) is not supported in web browsers")
            }

        case .plex, .jellyfin:
            switch codec {
            case .h264, .h265, .vp9, .av1, .mpeg2: return .supported
            default: return .transcodeMayBeRequired(reason: "Server may transcode \(codec.rawValue) for client compatibility")
            }

        case .roku:
            switch codec {
            case .h264, .h265: return .supported
            case .av1: return .transcodeMayBeRequired(reason: "AV1 requires newer Roku hardware")
            case .vp9: return .supported
            default: return .unsupported(reason: "\(codec.rawValue) is not supported on Roku")
            }
        }
    }

    /// Check whether an audio codec is supported on a platform.
    public static func checkAudioCodec(_ codec: AudioCodec, on platform: Platform) -> Compatibility {
        switch platform {
        case .macOS, .iOS, .tvOS:
            switch codec {
            case .aacLC, .aacHE, .aacHEv2, .alac, .ac3, .eac3, .flac, .mp3, .pcm:
                return .supported
            case .trueHD:
                return .transcodeMayBeRequired(reason: "TrueHD requires compatible AV receiver passthrough")
            case .opus:
                return .supported // macOS 11+, iOS 14+
            case .dts, .dtsHDMA, .dtsHDHRA, .dtsX:
                return .unsupported(reason: "DTS is not natively supported on Apple platforms")
            default:
                return .transcodeMayBeRequired(reason: "\(codec.rawValue) may need transcoding")
            }

        case .windows:
            switch codec {
            case .aacLC, .aacHE, .aacHEv2, .ac3, .eac3, .flac, .mp3, .pcm:
                return .supported
            case .dts, .dtsHDMA, .dtsHDHRA, .dtsX:
                return .supported
            case .trueHD:
                return .supported
            case .opus:
                return .supported
            default:
                return .transcodeMayBeRequired(reason: "\(codec.rawValue) may need codec pack")
            }

        case .android, .chromecast, .fireTV:
            switch codec {
            case .aacLC, .aacHE, .aacHEv2, .ac3, .eac3, .mp3, .opus, .vorbis, .flac:
                return .supported
            case .trueHD:
                return .transcodeMayBeRequired(reason: "TrueHD requires compatible receiver")
            case .dts:
                return .transcodeMayBeRequired(reason: "DTS support varies by device")
            default:
                return .unsupported(reason: "\(codec.rawValue) not supported on Android")
            }

        case .webBrowser:
            switch codec {
            case .aacLC, .aacHE, .mp3, .opus, .vorbis, .flac:
                return .supported
            case .ac3, .eac3:
                return .transcodeMayBeRequired(reason: "Dolby audio not universally supported in browsers")
            default:
                return .unsupported(reason: "\(codec.rawValue) is not supported in browsers")
            }

        case .plex, .jellyfin:
            // Media servers can transcode any codec
            return .supported

        case .roku:
            switch codec {
            case .aacLC, .ac3, .eac3, .mp3:
                return .supported
            case .dts:
                return .supported
            default:
                return .transcodeMayBeRequired(reason: "\(codec.rawValue) may need transcoding on Roku")
            }
        }
    }

    /// Check whether a container format is supported on a platform.
    public static func checkContainer(_ container: ContainerFormat, on platform: Platform) -> Compatibility {
        switch platform {
        case .macOS, .iOS, .tvOS:
            switch container {
            case .mp4, .m4v, .m4a, .mov, .mpegTS:
                return .supported
            case .mkv:
                return .transcodeMayBeRequired(reason: "MKV requires third-party player (VLC/IINA) on Apple platforms")
            case .webm:
                return .supported // Safari 16+
            default:
                return .transcodeMayBeRequired(reason: "\(container.rawValue) may need remuxing")
            }

        case .windows:
            switch container {
            case .mp4, .m4v, .mkv, .avi, .mpegTS, .webm:
                return .supported
            case .mov:
                return .supported
            default:
                return .transcodeMayBeRequired(reason: "\(container.rawValue) may need remuxing")
            }

        case .android, .chromecast, .fireTV:
            switch container {
            case .mp4, .mkv, .webm, .mpegTS:
                return .supported
            case .mov:
                return .transcodeMayBeRequired(reason: "MOV support varies on Android")
            default:
                return .unsupported(reason: "\(container.rawValue) not supported on Android")
            }

        case .webBrowser:
            switch container {
            case .mp4, .webm:
                return .supported
            case .mkv:
                return .unsupported(reason: "MKV is not supported in web browsers")
            default:
                return .unsupported(reason: "\(container.rawValue) not supported in browsers")
            }

        case .plex, .jellyfin:
            return .supported // Servers handle all containers

        case .roku:
            switch container {
            case .mp4, .mkv, .mpegTS:
                return .supported
            default:
                return .transcodeMayBeRequired(reason: "\(container.rawValue) may need remuxing on Roku")
            }
        }
    }

    /// Validate a full encoding profile against a target platform.
    ///
    /// Returns a list of warnings for any incompatible settings.
    public static func validate(
        profile: EncodingProfile,
        for platform: Platform
    ) -> [String] {
        var warnings: [String] = []

        if let videoCodec = profile.videoCodec {
            let result = checkVideoCodec(videoCodec, on: platform)
            switch result {
            case .supported: break
            case .transcodeMayBeRequired(let reason): warnings.append("Video: \(reason)")
            case .unsupported(let reason): warnings.append("Video: \(reason)")
            }
        }

        if let audioCodec = profile.audioCodec {
            let result = checkAudioCodec(audioCodec, on: platform)
            switch result {
            case .supported: break
            case .transcodeMayBeRequired(let reason): warnings.append("Audio: \(reason)")
            case .unsupported(let reason): warnings.append("Audio: \(reason)")
            }
        }

        let containerResult = checkContainer(profile.containerFormat, on: platform)
        switch containerResult {
        case .supported: break
        case .transcodeMayBeRequired(let reason): warnings.append("Container: \(reason)")
        case .unsupported(let reason): warnings.append("Container: \(reason)")
        }

        return warnings
    }

    /// Suggest the best encoding profile for a target platform.
    ///
    /// Returns the name of a built-in profile that best matches the platform's capabilities.
    public static func recommendedProfile(for platform: Platform) -> EncodingProfile {
        switch platform {
        case .macOS, .iOS, .tvOS:
            return .webHighQuality // H.265/AAC in MP4
        case .windows, .android, .chromecast, .fireTV, .roku:
            return .webStandard // H.264/AAC in MP4 — maximum compatibility
        case .webBrowser:
            return .webNextGen // AV1/Opus in WebM
        case .plex, .jellyfin:
            return .fourKHDRCompact // H.265 HDR in MKV for media servers
        }
    }
}
