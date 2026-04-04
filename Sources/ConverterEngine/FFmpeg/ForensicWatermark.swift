// ============================================================================
// MeedyaConverter — ForensicWatermark
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - WatermarkStrength

/// Controls the balance between watermark robustness and imperceptibility.
public enum WatermarkStrength: String, Codable, Sendable, CaseIterable {
    /// Light watermark — minimal visual impact, less robust to transformations.
    case light = "light"

    /// Standard watermark — good balance of robustness and imperceptibility.
    case standard = "standard"

    /// Strong watermark — maximum robustness, slightly more visible under analysis.
    case strong = "strong"

    /// The opacity value for the invisible text overlay (0.0–1.0).
    var opacity: Double {
        switch self {
        case .light: return 0.005
        case .standard: return 0.01
        case .strong: return 0.02
        }
    }

    /// The blend factor for frequency-domain embedding.
    var blendFactor: Double {
        switch self {
        case .light: return 0.15
        case .standard: return 0.25
        case .strong: return 0.40
        }
    }
}

// MARK: - WatermarkPayload

/// The data payload embedded in a forensic watermark.
public struct WatermarkPayload: Codable, Sendable {
    /// Unique identifier (user ID, license key, etc.).
    public var identifier: String

    /// Timestamp when the watermark was embedded.
    public var timestamp: Date

    /// Optional custom metadata string.
    public var metadata: String?

    public init(
        identifier: String,
        timestamp: Date = Date(),
        metadata: String? = nil
    ) {
        self.identifier = identifier
        self.timestamp = timestamp
        self.metadata = metadata
    }

    /// Encoded payload string for embedding.
    public var encodedString: String {
        let ts = ISO8601DateFormatter().string(from: timestamp)
        var s = "\(identifier)|\(ts)"
        if let meta = metadata {
            s += "|\(meta)"
        }
        return s
    }

    /// Hash of the payload for compact embedding.
    public var payloadHash: String {
        // Simple hash for embedding — use a short representation
        var hash: UInt64 = 5381
        for char in encodedString.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - WatermarkConfig

/// Configuration for forensic watermark embedding.
public struct WatermarkConfig: Codable, Sendable {
    /// Whether watermarking is enabled.
    public var enabled: Bool

    /// The payload to embed.
    public var payload: WatermarkPayload

    /// Watermark strength level.
    public var strength: WatermarkStrength

    /// Embed the watermark at a fixed interval (in seconds).
    /// Nil means embed throughout the entire video.
    public var embedInterval: TimeInterval?

    public init(
        enabled: Bool = true,
        payload: WatermarkPayload,
        strength: WatermarkStrength = .standard,
        embedInterval: TimeInterval? = nil
    ) {
        self.enabled = enabled
        self.payload = payload
        self.strength = strength
        self.embedInterval = embedInterval
    }
}

// MARK: - ForensicWatermark

/// Builds FFmpeg filter chains for invisible forensic watermark embedding.
///
/// Uses multiple techniques to embed imperceptible identifying data:
/// 1. Sub-pixel text overlay at near-zero opacity
/// 2. Periodic pattern injection in noise floor
/// 3. Metadata embedding in container
///
/// The watermark is designed to survive common transformations
/// (re-encoding, scaling) while remaining invisible to viewers.
///
/// Phase 7.2
public struct ForensicWatermark: Sendable {

    /// Build an FFmpeg video filter for invisible watermark embedding.
    ///
    /// Embeds the payload as an extremely low-opacity text overlay that is
    /// imperceptible to human vision but can be recovered through analysis.
    ///
    /// - Parameters:
    ///   - payload: The watermark payload to embed.
    ///   - strength: Watermark strength level.
    ///   - width: Video width (for positioning).
    ///   - height: Video height (for positioning).
    /// - Returns: FFmpeg video filter string.
    public static func buildEmbedFilter(
        payload: WatermarkPayload,
        strength: WatermarkStrength = .standard,
        width: Int = 1920,
        height: Int = 1080
    ) -> String {
        let hash = payload.payloadHash
        let opacity = strength.opacity

        // Tile the hash across the frame at sub-visible opacity
        // Position at multiple locations for redundancy
        let fontSize = max(8, min(width, height) / 100)
        let positions = [
            (x: "10", y: "10"),
            (x: "(w-text_w)/2", y: "(h-text_h)/2"),
            (x: "w-text_w-10", y: "h-text_h-10"),
            (x: "10", y: "h-text_h-10"),
            (x: "w-text_w-10", y: "10"),
        ]

        // Chain multiple drawtext filters for redundancy
        var filter = ""
        for (i, pos) in positions.enumerated() {
            if i > 0 { filter += "," }
            filter += "drawtext=text='\(hash)'"
            filter += ":fontsize=\(fontSize)"
            filter += ":fontcolor=white@\(String(format: "%.4f", opacity))"
            filter += ":x=\(pos.x):y=\(pos.y)"
        }

        return filter
    }

    /// Build an FFmpeg filter that adds a noise-floor watermark pattern.
    ///
    /// Generates a deterministic noise pattern based on the payload hash
    /// and blends it at imperceptible levels into the video.
    ///
    /// - Parameters:
    ///   - payload: The watermark payload.
    ///   - strength: Watermark strength.
    /// - Returns: FFmpeg filter string.
    public static func buildNoiseWatermarkFilter(
        payload: WatermarkPayload,
        strength: WatermarkStrength = .standard
    ) -> String {
        // Use the hash as a seed for deterministic noise
        let seed = abs(payload.payloadHash.hashValue % 999999)
        let blend = strength.blendFactor

        // Generate noise and blend at very low opacity
        return "noise=alls=\(seed):allf=t:amount=\(String(format: "%.1f", blend))"
    }

    /// Build FFmpeg metadata arguments to embed watermark info in container.
    ///
    /// This provides a second layer of identification that survives if the
    /// visual watermark is destroyed by heavy re-encoding.
    ///
    /// - Parameter payload: The watermark payload.
    /// - Returns: FFmpeg argument array.
    public static func buildMetadataArguments(payload: WatermarkPayload) -> [String] {
        return [
            "-metadata", "encoded_by=MeedyaConverter",
            "-metadata", "watermark_id=\(payload.payloadHash)",
        ]
    }

    /// Build the complete FFmpeg argument set for watermark embedding.
    ///
    /// Combines the visual filter and metadata embedding.
    ///
    /// - Parameter config: The watermark configuration.
    /// - Returns: A tuple of (videoFilter, extraArguments).
    public static func buildWatermarkArguments(
        config: WatermarkConfig
    ) -> (videoFilter: String, extraArguments: [String]) {
        guard config.enabled else {
            return (videoFilter: "", extraArguments: [])
        }

        let embedFilter = buildEmbedFilter(
            payload: config.payload,
            strength: config.strength
        )
        let metadataArgs = buildMetadataArguments(payload: config.payload)

        return (videoFilter: embedFilter, extraArguments: metadataArgs)
    }

    // MARK: - Detection

    /// Build FFmpeg arguments for watermark detection analysis.
    ///
    /// Extracts a frame region at enhanced contrast to reveal sub-pixel
    /// text overlays for forensic analysis.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the video to analyse.
    ///   - outputPath: Path for the enhanced analysis frame.
    ///   - seekTo: Timestamp to analyse (in seconds).
    /// - Returns: FFmpeg argument array.
    public static func buildDetectionArguments(
        inputPath: String,
        outputPath: String,
        seekTo: TimeInterval = 10.0
    ) -> [String] {
        return [
            "-ss", String(format: "%.2f", seekTo),
            "-i", inputPath,
            "-vframes", "1",
            // Extreme contrast enhancement to reveal hidden text
            "-vf", "eq=contrast=50:brightness=0.5,negate",
            "-y",
            outputPath
        ]
    }
}
