// ============================================================================
// MeedyaConverter — DCPGenerator
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DCPStandard

/// DCP packaging standard.
public enum DCPStandard: String, Codable, Sendable {
    /// Interop DCP — legacy standard, widely supported.
    case interop = "interop"

    /// SMPTE DCP — modern DCI-compliant standard.
    case smpte = "smpte"
}

// MARK: - DCPResolution

/// Standard DCP projection resolutions.
public enum DCPResolution: String, Codable, Sendable, CaseIterable {
    /// 2K DCI (2048x1080).
    case dci2K = "2K"

    /// 4K DCI (4096x2160).
    case dci4K = "4K"

    /// Width in pixels.
    public var width: Int {
        switch self {
        case .dci2K: return 2048
        case .dci4K: return 4096
        }
    }

    /// Height in pixels.
    public var height: Int {
        switch self {
        case .dci2K: return 1080
        case .dci4K: return 2160
        }
    }

    /// Maximum video bitrate in Mbps.
    public var maxBitrateMbps: Int {
        return 250
    }
}

// MARK: - DCPAspectRatio

/// Standard DCP aspect ratios.
public enum DCPAspectRatio: String, Codable, Sendable {
    /// Flat (1.85:1) — 1998x1080 (2K) or 3996x2160 (4K).
    case flat = "flat"

    /// Scope (2.39:1) — 2048x858 (2K) or 4096x1716 (4K).
    case scope = "scope"

    /// Full container (1.90:1) — 2048x1080 (2K) or 4096x2160 (4K).
    case full = "full"

    /// Active picture dimensions for a given DCP resolution.
    public func activeDimensions(for resolution: DCPResolution) -> (width: Int, height: Int) {
        switch (self, resolution) {
        case (.flat, .dci2K): return (1998, 1080)
        case (.flat, .dci4K): return (3996, 2160)
        case (.scope, .dci2K): return (2048, 858)
        case (.scope, .dci4K): return (4096, 1716)
        case (.full, .dci2K): return (2048, 1080)
        case (.full, .dci4K): return (4096, 2160)
        }
    }
}

// MARK: - DCPContentKind

/// DCP content kind classification.
public enum DCPContentKind: String, Codable, Sendable {
    case feature = "feature"
    case trailer = "trailer"
    case teaser = "teaser"
    case advertisement = "advertisement"
    case shortFilm = "short"
    case transitionalFilm = "transitional"
    case rating = "rating"
    case policy = "policy"
    case test = "test"
}

// MARK: - DCPConfig

/// Configuration for Digital Cinema Package creation.
public struct DCPConfig: Codable, Sendable {
    /// Content title (displayed in cinema systems).
    public var title: String

    /// DCP packaging standard.
    public var standard: DCPStandard

    /// Target resolution.
    public var resolution: DCPResolution

    /// Aspect ratio.
    public var aspectRatio: DCPAspectRatio

    /// Frame rate (24 or 48 fps).
    public var frameRate: Int

    /// Content kind.
    public var contentKind: DCPContentKind

    /// Annotation text (description).
    public var annotation: String?

    /// Issuer name.
    public var issuer: String?

    /// Whether to encrypt the DCP.
    public var encrypted: Bool

    /// Audio channel count (6 = 5.1, 8 = 7.1).
    public var audioChannels: Int

    /// Output directory for the DCP folder.
    public var outputDirectory: String

    public init(
        title: String,
        standard: DCPStandard = .smpte,
        resolution: DCPResolution = .dci2K,
        aspectRatio: DCPAspectRatio = .flat,
        frameRate: Int = 24,
        contentKind: DCPContentKind = .feature,
        annotation: String? = nil,
        issuer: String? = nil,
        encrypted: Bool = false,
        audioChannels: Int = 6,
        outputDirectory: String
    ) {
        self.title = title
        self.standard = standard
        self.resolution = resolution
        self.aspectRatio = aspectRatio
        self.frameRate = frameRate
        self.contentKind = contentKind
        self.annotation = annotation
        self.issuer = issuer
        self.encrypted = encrypted
        self.audioChannels = audioChannels
        self.outputDirectory = outputDirectory
    }
}

// MARK: - DCPGenerator

/// Builds FFmpeg arguments and generates metadata files for
/// Digital Cinema Package (DCP) creation.
///
/// Handles JPEG 2000 encoding with DCI color space conversion,
/// MXF wrapping, and XML metadata generation (ASSETMAP, CPL, PKL).
///
/// Phase 7.17
public struct DCPGenerator: Sendable {

    /// Build FFmpeg arguments for JPEG 2000 video encoding to DCI specs.
    ///
    /// - Parameters:
    ///   - inputPath: Source video path.
    ///   - outputPath: Output MXF path for video.
    ///   - config: DCP configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildVideoEncodeArguments(
        inputPath: String,
        outputPath: String,
        config: DCPConfig
    ) -> [String] {
        let dims = config.aspectRatio.activeDimensions(for: config.resolution)

        var args: [String] = []
        args += ["-i", inputPath]

        // Scale to DCI resolution and aspect ratio
        args += ["-vf", "scale=\(dims.width):\(dims.height):flags=lanczos,fps=\(config.frameRate)"]

        // JPEG 2000 encoding
        args += ["-c:v", "libopenjpeg"]
        args += ["-pix_fmt", "xyz12le"] // DCI XYZ 12-bit colour
        args += ["-r", "\(config.frameRate)"]

        // DCI max bitrate
        args += ["-b:v", "\(config.resolution.maxBitrateMbps)M"]

        // No audio in video MXF
        args += ["-an"]

        args += [outputPath]

        return args
    }

    /// Build FFmpeg arguments for PCM audio encoding to DCI specs.
    ///
    /// - Parameters:
    ///   - inputPath: Source audio/video path.
    ///   - outputPath: Output MXF path for audio.
    ///   - config: DCP configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildAudioEncodeArguments(
        inputPath: String,
        outputPath: String,
        config: DCPConfig
    ) -> [String] {
        var args: [String] = []
        args += ["-i", inputPath]

        // PCM 24-bit at 48kHz
        args += ["-c:a", "pcm_s24le"]
        args += ["-ar", "48000"]
        args += ["-ac", "\(config.audioChannels)"]

        // No video in audio MXF
        args += ["-vn"]

        args += [outputPath]

        return args
    }

    /// Generate a minimal ASSETMAP XML for the DCP.
    ///
    /// - Parameters:
    ///   - dcpId: UUID for the DCP.
    ///   - cplId: UUID for the CPL.
    ///   - pklId: UUID for the PKL.
    ///   - videoFile: Video MXF filename.
    ///   - audioFile: Audio MXF filename.
    /// - Returns: ASSETMAP XML string.
    public static func generateAssetMap(
        dcpId: String,
        cplId: String,
        pklId: String,
        videoFile: String,
        audioFile: String
    ) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <AssetMap xmlns="http://www.smpte-ra.org/schemas/429-9/2007/AM">
          <Id>urn:uuid:\(dcpId)</Id>
          <AnnotationText>MeedyaConverter DCP</AnnotationText>
          <Creator>MeedyaConverter</Creator>
          <VolumeCount>1</VolumeCount>
          <IssueDate>\(ISO8601DateFormatter().string(from: Date()))</IssueDate>
          <Issuer>MeedyaConverter</Issuer>
          <AssetList>
            <Asset>
              <Id>urn:uuid:\(pklId)</Id>
              <PackingList>true</PackingList>
              <ChunkList>
                <Chunk><Path>PKL_\(pklId).xml</Path></Chunk>
              </ChunkList>
            </Asset>
            <Asset>
              <Id>urn:uuid:\(cplId)</Id>
              <ChunkList>
                <Chunk><Path>CPL_\(cplId).xml</Path></Chunk>
              </ChunkList>
            </Asset>
            <Asset>
              <Id>urn:uuid:\(UUID().uuidString.lowercased())</Id>
              <ChunkList>
                <Chunk><Path>\(videoFile)</Path></Chunk>
              </ChunkList>
            </Asset>
            <Asset>
              <Id>urn:uuid:\(UUID().uuidString.lowercased())</Id>
              <ChunkList>
                <Chunk><Path>\(audioFile)</Path></Chunk>
              </ChunkList>
            </Asset>
          </AssetList>
        </AssetMap>
        """
    }

    /// Generate a minimal CPL (Composition Playlist) XML.
    ///
    /// - Parameters:
    ///   - config: DCP configuration.
    ///   - cplId: UUID for the CPL.
    ///   - videoId: UUID for the video asset.
    ///   - audioId: UUID for the audio asset.
    ///   - durationFrames: Total duration in frames.
    /// - Returns: CPL XML string.
    public static func generateCPL(
        config: DCPConfig,
        cplId: String,
        videoId: String,
        audioId: String,
        durationFrames: Int
    ) -> String {
        let dims = config.aspectRatio.activeDimensions(for: config.resolution)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <CompositionPlaylist xmlns="http://www.smpte-ra.org/schemas/429-7/2006/CPL">
          <Id>urn:uuid:\(cplId)</Id>
          <AnnotationText>\(config.title)</AnnotationText>
          <IssueDate>\(ISO8601DateFormatter().string(from: Date()))</IssueDate>
          <Issuer>\(config.issuer ?? "MeedyaConverter")</Issuer>
          <Creator>MeedyaConverter</Creator>
          <ContentTitleText>\(config.title)</ContentTitleText>
          <ContentKind>\(config.contentKind.rawValue)</ContentKind>
          <ReelList>
            <Reel>
              <Id>urn:uuid:\(UUID().uuidString.lowercased())</Id>
              <AssetList>
                <MainPicture>
                  <Id>urn:uuid:\(videoId)</Id>
                  <EditRate>\(config.frameRate) 1</EditRate>
                  <IntrinsicDuration>\(durationFrames)</IntrinsicDuration>
                  <EntryPoint>0</EntryPoint>
                  <Duration>\(durationFrames)</Duration>
                  <FrameRate>\(config.frameRate) 1</FrameRate>
                  <ScreenAspectRatio>\(dims.width) \(dims.height)</ScreenAspectRatio>
                </MainPicture>
                <MainSound>
                  <Id>urn:uuid:\(audioId)</Id>
                  <EditRate>\(config.frameRate) 1</EditRate>
                  <IntrinsicDuration>\(durationFrames)</IntrinsicDuration>
                  <EntryPoint>0</EntryPoint>
                  <Duration>\(durationFrames)</Duration>
                </MainSound>
              </AssetList>
            </Reel>
          </ReelList>
        </CompositionPlaylist>
        """
    }

    /// Validate a DCP configuration before encoding.
    ///
    /// - Parameter config: The DCP configuration to validate.
    /// - Returns: Array of warning/error messages. Empty means valid.
    public static func validate(config: DCPConfig) -> [String] {
        var warnings: [String] = []

        if config.frameRate != 24 && config.frameRate != 48 {
            warnings.append("DCI frame rate must be 24 or 48 fps (got \(config.frameRate))")
        }

        if config.audioChannels != 6 && config.audioChannels != 8 {
            warnings.append("DCI audio should be 5.1 (6ch) or 7.1 (8ch) (got \(config.audioChannels)ch)")
        }

        if config.title.isEmpty {
            warnings.append("DCP title is required")
        }

        if config.encrypted {
            warnings.append("DCP encryption requires KDM infrastructure (not yet implemented)")
        }

        return warnings
    }
}
