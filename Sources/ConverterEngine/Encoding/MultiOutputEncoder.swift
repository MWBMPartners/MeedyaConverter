// ============================================================================
// MeedyaConverter — MultiOutputEncoder (Issue #335)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - OutputSpec

/// A single output specification within a multi-output encoding job.
///
/// Each output spec pairs an encoding profile with a destination URL
/// and an enable toggle, allowing the user to temporarily disable
/// individual outputs without removing them from the configuration.
public struct OutputSpec: Identifiable, Codable, Sendable, Equatable {

    /// Unique identifier for this output specification.
    public let id: UUID

    /// The encoding profile defining codec, quality, and container settings.
    public var profile: EncodingProfile

    /// The file URL where this output will be written.
    public var outputURL: URL

    /// Whether this output is currently enabled for encoding.
    public var enabled: Bool

    /// Creates a new output specification.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - profile: The encoding profile for this output.
    ///   - outputURL: The destination file URL.
    ///   - enabled: Whether this output is enabled (defaults to `true`).
    public init(
        id: UUID = UUID(),
        profile: EncodingProfile,
        outputURL: URL,
        enabled: Bool = true
    ) {
        self.id = id
        self.profile = profile
        self.outputURL = outputURL
        self.enabled = enabled
    }
}

// MARK: - MultiOutputConfig

/// Configuration for a single-source, multiple-output encoding job.
///
/// Allows one source file to be encoded into multiple output formats
/// simultaneously (via FFmpeg tee muxer) or sequentially (as a
/// fallback when tee is not compatible).
public struct MultiOutputConfig: Codable, Sendable {

    /// The source media file URL.
    public var sourceURL: URL

    /// The list of output specifications.
    public var outputs: [OutputSpec]

    /// Creates a new multi-output configuration.
    ///
    /// - Parameters:
    ///   - sourceURL: The source media file URL.
    ///   - outputs: The list of output specifications.
    public init(sourceURL: URL, outputs: [OutputSpec]) {
        self.sourceURL = sourceURL
        self.outputs = outputs
    }
}

// MARK: - MultiOutputEncoder

/// Builds FFmpeg arguments for encoding a single source to multiple outputs.
///
/// Supports two strategies:
/// 1. **Tee muxer** — encodes once and writes to multiple outputs
///    simultaneously, which is faster but requires compatible codecs
///    and containers across all outputs.
/// 2. **Sequential encoding** — encodes each output separately, which
///    is more flexible but slower.
///
/// Phase 11.3 — Multiple Output Formats per Job (Issue #335)
public struct MultiOutputEncoder: Sendable {

    // MARK: - Tee Muxer Arguments

    /// Build FFmpeg arguments using the tee muxer for simultaneous outputs.
    ///
    /// The tee muxer writes the same encoded stream to multiple output
    /// files in a single pass. All outputs must use the same video and
    /// audio codec for tee to work.
    ///
    /// Example output:
    /// ```
    /// ["-y", "-i", "input.mkv", "-c:v", "libx265", "-crf", "22",
    ///  "-c:a", "aac", "-f", "tee",
    ///  "[f=mp4]out.mp4|[f=mkv]out.mkv"]
    /// ```
    ///
    /// - Parameter config: The multi-output configuration.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildTeeArguments(config: MultiOutputConfig) -> [String] {
        let enabledOutputs = config.outputs.filter(\.enabled)
        guard !enabledOutputs.isEmpty else { return [] }

        var args: [String] = ["-y", "-i", config.sourceURL.path]

        // Use the first output's profile for encoding settings since
        // tee requires a single encode pass.
        let primaryProfile = enabledOutputs[0].profile

        // Video codec arguments.
        if primaryProfile.videoPassthrough {
            args += ["-c:v", "copy"]
        } else if let codec = primaryProfile.videoCodec,
                  let encoder = codec.ffmpegEncoder {
            args += ["-c:v", encoder]
            if let crf = primaryProfile.videoCRF {
                args += ["-crf", "\(crf)"]
            }
        }

        // Audio codec arguments.
        if primaryProfile.audioPassthrough {
            args += ["-c:a", "copy"]
        } else if let codec = primaryProfile.audioCodec,
                  let encoder = codec.ffmpegEncoder {
            args += ["-c:a", encoder]
            if let bitrate = primaryProfile.audioBitrate {
                args += ["-b:a", "\(bitrate)"]
            }
        }

        // Build the tee output string.
        args += ["-f", "tee"]

        let teeOutputs = enabledOutputs.map { spec -> String in
            let container = spec.profile.containerFormat.ffmpegFormatName
            return "[f=\(container)]\(spec.outputURL.path)"
        }
        args.append(teeOutputs.joined(separator: "|"))

        return args
    }

    // MARK: - Sequential Arguments

    /// Build FFmpeg arguments for sequential (one-at-a-time) encoding.
    ///
    /// Returns one argument array per enabled output. Each array is a
    /// complete FFmpeg invocation that can be executed independently.
    /// This is the fallback when tee muxer is not compatible.
    ///
    /// - Parameter config: The multi-output configuration.
    /// - Returns: An array of FFmpeg argument arrays, one per output.
    public static func buildSequentialArguments(
        config: MultiOutputConfig
    ) -> [[String]] {
        let enabledOutputs = config.outputs.filter(\.enabled)

        return enabledOutputs.map { spec -> [String] in
            var args: [String] = ["-y", "-i", config.sourceURL.path]

            // Video codec arguments from this output's profile.
            if spec.profile.videoPassthrough {
                args += ["-c:v", "copy"]
            } else if let codec = spec.profile.videoCodec,
                      let encoder = codec.ffmpegEncoder {
                args += ["-c:v", encoder]
                if let crf = spec.profile.videoCRF {
                    args += ["-crf", "\(crf)"]
                }
            }

            // Audio codec arguments from this output's profile.
            if spec.profile.audioPassthrough {
                args += ["-c:a", "copy"]
            } else if let codec = spec.profile.audioCodec,
                      let encoder = codec.ffmpegEncoder {
                args += ["-c:a", encoder]
                if let bitrate = spec.profile.audioBitrate {
                    args += ["-b:a", "\(bitrate)"]
                }
            }

            args.append(spec.outputURL.path)
            return args
        }
    }

    // MARK: - Tee Compatibility Check

    /// Check whether all outputs are compatible with the FFmpeg tee muxer.
    ///
    /// Tee muxer requires all outputs to share the same video and audio
    /// codec (or all be passthrough), because the media is only encoded
    /// once. Outputs with different codecs must be encoded sequentially.
    ///
    /// - Parameter outputs: The list of output specifications to check.
    /// - Returns: `true` if all outputs can be muxed with tee.
    public static func canUseTee(outputs: [OutputSpec]) -> Bool {
        let enabled = outputs.filter(\.enabled)
        guard enabled.count > 1 else { return true }

        let first = enabled[0].profile

        return enabled.allSatisfy { spec in
            let p = spec.profile

            // Video codec must match.
            let videoMatch: Bool
            if first.videoPassthrough && p.videoPassthrough {
                videoMatch = true
            } else if first.videoCodec == p.videoCodec {
                videoMatch = true
            } else {
                videoMatch = false
            }

            // Audio codec must match.
            let audioMatch: Bool
            if first.audioPassthrough && p.audioPassthrough {
                audioMatch = true
            } else if first.audioCodec == p.audioCodec {
                audioMatch = true
            } else {
                audioMatch = false
            }

            return videoMatch && audioMatch
        }
    }
}
