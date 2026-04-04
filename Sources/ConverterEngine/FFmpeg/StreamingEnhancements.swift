// ============================================================================
// MeedyaConverter — StreamingEnhancements
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - HLSEncryption

/// Configuration for HLS AES-128 content encryption.
///
/// Encrypts HLS segments using AES-128-CBC with a key served via HTTPS.
/// The master playlist includes `#EXT-X-KEY` tags pointing to the key URL.
///
/// Phase 6.6
public struct HLSEncryption: Codable, Sendable {

    /// The 16-byte AES-128 key (hex-encoded, 32 characters).
    public var keyHex: String

    /// The URL where the decryption key is served.
    /// Players fetch this URL to obtain the key for decryption.
    public var keyInfoURL: String

    /// Optional initialization vector (hex-encoded, 32 characters).
    /// If nil, the segment sequence number is used as IV.
    public var ivHex: String?

    public init(keyHex: String, keyInfoURL: String, ivHex: String? = nil) {
        self.keyHex = keyHex
        self.keyInfoURL = keyInfoURL
        self.ivHex = ivHex
    }

    /// Generate a random 128-bit encryption key.
    ///
    /// - Returns: A tuple of (hex string, raw bytes) for the AES key.
    public static func generateKey() -> (hex: String, bytes: Data) {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        let data = Data(bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return (hex, data)
    }

    /// Build FFmpeg HLS encryption arguments.
    ///
    /// Writes a key info file that FFmpeg reads to configure segment encryption.
    /// The key info file format is:
    /// ```
    /// <key URI>
    /// <key file path>
    /// <IV (optional)>
    /// ```
    ///
    /// - Parameters:
    ///   - keyFilePath: Local path to write the raw key file.
    ///   - keyInfoFilePath: Local path to write the key info file.
    /// - Returns: FFmpeg arguments for HLS encryption.
    public func buildEncryptionArguments(
        keyFilePath: String,
        keyInfoFilePath: String
    ) -> [String] {
        return ["-hls_key_info_file", keyInfoFilePath]
    }

    /// Write the key and key info files to disk for FFmpeg.
    ///
    /// - Parameters:
    ///   - keyFilePath: Path for the raw binary key file.
    ///   - keyInfoFilePath: Path for the key info file.
    public func writeKeyFiles(
        keyFilePath: String,
        keyInfoFilePath: String
    ) throws {
        // Write the raw key bytes
        guard let keyData = Data(hexString: keyHex) else {
            throw HLSEncryptionError.invalidKey("Key must be 32 hex characters (16 bytes)")
        }
        try keyData.write(to: URL(fileURLWithPath: keyFilePath))

        // Write the key info file
        var keyInfo = "\(keyInfoURL)\n\(keyFilePath)\n"
        if let iv = ivHex {
            keyInfo += iv
        }
        try keyInfo.write(toFile: keyInfoFilePath, atomically: true, encoding: .utf8)
    }
}

/// Errors from HLS encryption operations.
public enum HLSEncryptionError: LocalizedError, Sendable {
    case invalidKey(String)
    case keyWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey(let msg): return "Invalid encryption key: \(msg)"
        case .keyWriteFailed(let msg): return "Failed to write key file: \(msg)"
        }
    }
}

// MARK: - Data hex initializer

extension Data {
    /// Initialize Data from a hex-encoded string.
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count % 2 == 0 else { return nil }

        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        self.init(bytes)
    }
}

// MARK: - ThumbnailSpriteGenerator

/// Generates thumbnail sprite sheets for video scrubbing (trick play).
///
/// Creates a grid of thumbnail images at regular intervals throughout
/// the video, combined into a single sprite sheet image. The accompanying
/// WebVTT file maps timestamps to regions within the sprite.
///
/// Phase 6.10
public struct ThumbnailSpriteGenerator: Sendable {

    /// Configuration for thumbnail sprite generation.
    public struct Config: Codable, Sendable {
        /// Interval between thumbnails in seconds.
        public var intervalSeconds: Double

        /// Width of each thumbnail in pixels.
        public var thumbnailWidth: Int

        /// Height of each thumbnail in pixels.
        public var thumbnailHeight: Int

        /// Number of columns in the sprite sheet.
        public var columns: Int

        /// JPEG quality (1-100) for the sprite sheet.
        public var quality: Int

        public init(
            intervalSeconds: Double = 10.0,
            thumbnailWidth: Int = 160,
            thumbnailHeight: Int = 90,
            columns: Int = 10,
            quality: Int = 75
        ) {
            self.intervalSeconds = intervalSeconds
            self.thumbnailWidth = thumbnailWidth
            self.thumbnailHeight = thumbnailHeight
            self.columns = columns
            self.quality = quality
        }
    }

    /// Build FFmpeg arguments to extract thumbnails at regular intervals.
    ///
    /// Extracts individual frame images that are later assembled into
    /// a sprite sheet using an image tool or FFmpeg tile filter.
    ///
    /// - Parameters:
    ///   - inputURL: Source video file.
    ///   - outputPattern: Output path pattern (e.g., "/tmp/thumb_%04d.jpg").
    ///   - config: Sprite configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildExtractionArguments(
        inputURL: URL,
        outputPattern: String,
        config: Config = Config()
    ) -> [String] {
        let fps = 1.0 / config.intervalSeconds
        return [
            "-y", "-nostdin",
            "-i", inputURL.path,
            "-vf", "fps=\(String(format: "%.4f", fps)),scale=\(config.thumbnailWidth):\(config.thumbnailHeight)",
            "-q:v", "\(max(1, min(31, (100 - config.quality) * 31 / 100)))",
            "-an", "-sn",
            outputPattern,
        ]
    }

    /// Build FFmpeg arguments to create a sprite sheet from individual thumbnails.
    ///
    /// Uses the tile filter to combine individual thumbnails into a grid.
    ///
    /// - Parameters:
    ///   - inputURL: Source video file.
    ///   - outputPath: Output sprite sheet path (e.g., "/tmp/sprites.jpg").
    ///   - config: Sprite configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildSpriteSheetArguments(
        inputURL: URL,
        outputPath: String,
        config: Config = Config()
    ) -> [String] {
        let fps = 1.0 / config.intervalSeconds
        let tileFilter = "tile=\(config.columns)x0"
        return [
            "-y", "-nostdin",
            "-i", inputURL.path,
            "-vf", "fps=\(String(format: "%.4f", fps)),scale=\(config.thumbnailWidth):\(config.thumbnailHeight),\(tileFilter)",
            "-q:v", "\(max(1, min(31, (100 - config.quality) * 31 / 100)))",
            "-an", "-sn",
            "-frames:v", "1",
            outputPath,
        ]
    }

    /// Generate a WebVTT file mapping timestamps to sprite regions.
    ///
    /// - Parameters:
    ///   - spriteURL: URL of the sprite sheet image (relative or absolute).
    ///   - config: Sprite configuration.
    ///   - totalDuration: Total video duration in seconds.
    /// - Returns: The WebVTT content as a string.
    public static func buildWebVTT(
        spriteURL: String,
        config: Config,
        totalDuration: Double
    ) -> String {
        var vtt = "WEBVTT\n\n"

        var currentTime: Double = 0
        var index = 0

        while currentTime < totalDuration {
            let endTime = min(currentTime + config.intervalSeconds, totalDuration)
            let col = index % config.columns
            let row = index / config.columns
            let x = col * config.thumbnailWidth
            let y = row * config.thumbnailHeight

            let startStr = formatVTTTime(currentTime)
            let endStr = formatVTTTime(endTime)

            vtt += "\(startStr) --> \(endStr)\n"
            vtt += "\(spriteURL)#xywh=\(x),\(y),\(config.thumbnailWidth),\(config.thumbnailHeight)\n\n"

            currentTime = endTime
            index += 1
        }

        return vtt
    }

    private static func formatVTTTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - Double(Int(seconds))) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}

// MARK: - StreamingPreset

/// Pre-configured adaptive streaming presets for common delivery targets.
///
/// Each preset defines the codec, variant ladder, segment duration, and
/// container settings optimized for a specific streaming platform or standard.
///
/// Phase 6.9
public struct StreamingPreset: Sendable {

    /// The preset name.
    public let name: String

    /// Description of the target use case.
    public let description: String

    /// The manifest format.
    public let format: ManifestFormat

    /// The video codec.
    public let videoCodec: VideoCodec

    /// The audio codec.
    public let audioCodec: AudioCodec

    /// The variant ladder.
    public let variants: [StreamingVariant]

    /// Segment duration in seconds.
    public let segmentDuration: Double

    /// Keyframe interval in seconds.
    public let keyframeInterval: Double

    /// Encoder preset.
    public let preset: String

    /// Pixel format.
    public let pixelFormat: String?

    /// All built-in streaming presets.
    public static let builtInPresets: [StreamingPreset] = [
        appleHLS,
        mpegDASH,
        youtubeLike,
        twitchLive,
        netflixLike,
    ]

    /// Apple HLS — optimized for Apple devices and Safari.
    /// H.264/AAC, 6s segments, fMP4 preferred.
    public static let appleHLS = StreamingPreset(
        name: "Apple HLS",
        description: "Optimized for Apple devices, Safari, and tvOS — H.264/AAC with 6s segments",
        format: .hls,
        videoCodec: .h264,
        audioCodec: .aacLC,
        variants: StreamingVariant.defaultLadder,
        segmentDuration: 6.0,
        keyframeInterval: 2.0,
        preset: "medium",
        pixelFormat: "yuv420p"
    )

    /// MPEG-DASH — standards-based adaptive streaming.
    /// H.265/AAC, 4s segments.
    public static let mpegDASH = StreamingPreset(
        name: "MPEG-DASH",
        description: "Standards-based streaming — H.265/AAC with 4s segments for cross-platform delivery",
        format: .dash,
        videoCodec: .h265,
        audioCodec: .aacLC,
        variants: StreamingVariant.defaultLadder,
        segmentDuration: 4.0,
        keyframeInterval: 2.0,
        preset: "medium",
        pixelFormat: nil
    )

    /// YouTube-like — high quality with modern codecs.
    /// AV1/Opus, aggressive ladder for bandwidth savings.
    public static let youtubeLike = StreamingPreset(
        name: "YouTube-Like",
        description: "Modern codecs (AV1/Opus) for maximum efficiency — requires AV1-capable clients",
        format: .dash,
        videoCodec: .av1,
        audioCodec: .opus,
        variants: [
            StreamingVariant(label: "1080p", width: 1920, height: 1080,
                            videoBitrate: 3_000_000, videoMaxBitrate: 4_500_000,
                            videoBufferSize: 6_000_000, audioBitrate: 128_000, audioChannels: 2),
            StreamingVariant(label: "720p", width: 1280, height: 720,
                            videoBitrate: 1_500_000, videoMaxBitrate: 2_250_000,
                            videoBufferSize: 3_000_000, audioBitrate: 128_000, audioChannels: 2),
            StreamingVariant(label: "480p", width: 854, height: 480,
                            videoBitrate: 750_000, videoMaxBitrate: 1_125_000,
                            videoBufferSize: 1_500_000, audioBitrate: 64_000, audioChannels: 2),
            StreamingVariant(label: "360p", width: 640, height: 360,
                            videoBitrate: 400_000, videoMaxBitrate: 600_000,
                            videoBufferSize: 800_000, audioBitrate: 48_000, audioChannels: 2),
        ],
        segmentDuration: 4.0,
        keyframeInterval: 2.0,
        preset: "6", // SVT-AV1 preset
        pixelFormat: nil
    )

    /// Twitch Live — low-latency streaming optimized for live content.
    /// H.264/AAC, 2s segments, fast preset.
    public static let twitchLive = StreamingPreset(
        name: "Twitch Live",
        description: "Low-latency live streaming — H.264/AAC with 2s segments and fast preset",
        format: .hls,
        videoCodec: .h264,
        audioCodec: .aacLC,
        variants: [
            StreamingVariant(label: "1080p60", width: 1920, height: 1080,
                            videoBitrate: 6_000_000, videoMaxBitrate: 7_500_000,
                            videoBufferSize: 12_000_000, audioBitrate: 160_000, audioChannels: 2),
            StreamingVariant(label: "720p60", width: 1280, height: 720,
                            videoBitrate: 3_500_000, videoMaxBitrate: 4_500_000,
                            videoBufferSize: 7_000_000, audioBitrate: 128_000, audioChannels: 2),
            StreamingVariant(label: "480p", width: 854, height: 480,
                            videoBitrate: 1_500_000, videoMaxBitrate: 2_000_000,
                            videoBufferSize: 3_000_000, audioBitrate: 96_000, audioChannels: 2),
        ],
        segmentDuration: 2.0,
        keyframeInterval: 2.0,
        preset: "veryfast",
        pixelFormat: "yuv420p"
    )

    /// Netflix-like — premium quality with HDR support.
    /// H.265/E-AC-3, 4K ladder with 10-bit HDR.
    public static let netflixLike = StreamingPreset(
        name: "Netflix-Like",
        description: "Premium quality streaming — H.265/E-AC-3 with 4K HDR and surround audio",
        format: .cmaf,
        videoCodec: .h265,
        audioCodec: .eac3,
        variants: StreamingVariant.uhdrLadder,
        segmentDuration: 4.0,
        keyframeInterval: 2.0,
        preset: "slow",
        pixelFormat: "yuv420p10le"
    )

    /// Convert this preset to a ManifestConfig.
    public func toManifestConfig(inputURL: URL, outputDirectory: URL) -> ManifestConfig {
        ManifestConfig(
            inputURL: inputURL,
            outputDirectory: outputDirectory,
            format: format,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            preset: preset,
            keyframeInterval: keyframeInterval,
            segmentDuration: segmentDuration,
            variants: variants,
            pixelFormat: pixelFormat
        )
    }
}
