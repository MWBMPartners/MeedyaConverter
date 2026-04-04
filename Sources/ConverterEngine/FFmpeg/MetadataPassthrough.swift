// ============================================================================
// MeedyaConverter — MetadataPassthrough
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MetadataPassthroughMode

/// Modes for handling metadata during transcoding.
public enum MetadataPassthroughMode: String, Codable, Sendable, CaseIterable {
    /// Copy all global and stream metadata from source.
    case copyAll = "copy_all"

    /// Copy global metadata only (not per-stream).
    case globalOnly = "global_only"

    /// Copy stream metadata only (not global).
    case streamOnly = "stream_only"

    /// Strip all metadata from output.
    case strip = "strip"

    /// Custom — selectively copy specific metadata keys.
    case custom = "custom"

    /// Display name.
    public var displayName: String {
        switch self {
        case .copyAll: return "Copy All Metadata"
        case .globalOnly: return "Global Metadata Only"
        case .streamOnly: return "Stream Metadata Only"
        case .strip: return "Strip All Metadata"
        case .custom: return "Custom Selection"
        }
    }
}

// MARK: - ChapterPassthroughMode

/// Modes for handling chapter markers during transcoding.
public enum ChapterPassthroughMode: String, Codable, Sendable, CaseIterable {
    /// Copy all chapters from source.
    case copy = "copy"

    /// Strip all chapters.
    case strip = "strip"

    /// Display name.
    public var displayName: String {
        switch self {
        case .copy: return "Preserve Chapters"
        case .strip: return "Remove Chapters"
        }
    }
}

// MARK: - AspectRatioMode

/// Modes for handling display aspect ratio metadata.
public enum AspectRatioMode: String, Codable, Sendable, CaseIterable {
    /// Preserve source display aspect ratio (DAR) metadata.
    case preserve = "preserve"

    /// Override with specific aspect ratio.
    case override_ = "override"

    /// Remove DAR metadata (use SAR from pixel dimensions).
    case remove = "remove"

    /// Display name.
    public var displayName: String {
        switch self {
        case .preserve: return "Preserve Source Aspect Ratio"
        case .override_: return "Override Aspect Ratio"
        case .remove: return "Remove (Use Pixel Dimensions)"
        }
    }
}

// MARK: - MetadataPassthroughConfig

/// Configuration for metadata handling during transcoding.
public struct MetadataPassthroughConfig: Codable, Sendable {
    /// Global/stream metadata mode.
    public var mode: MetadataPassthroughMode

    /// Chapter handling mode.
    public var chapterMode: ChapterPassthroughMode

    /// Aspect ratio handling mode.
    public var aspectRatioMode: AspectRatioMode

    /// Custom aspect ratio (only used when aspectRatioMode == .override_).
    public var customAspectRatio: String?

    /// Specific metadata keys to preserve (for custom mode).
    public var preserveKeys: [String]

    /// Specific metadata keys to strip (for custom mode).
    public var stripKeys: [String]

    /// Whether to preserve codec-specific metadata (e.g., HDR side data).
    public var preserveCodecMetadata: Bool

    /// Whether to copy disposition flags (default, forced, etc.).
    public var copyDispositions: Bool

    public init(
        mode: MetadataPassthroughMode = .copyAll,
        chapterMode: ChapterPassthroughMode = .copy,
        aspectRatioMode: AspectRatioMode = .preserve,
        customAspectRatio: String? = nil,
        preserveKeys: [String] = [],
        stripKeys: [String] = [],
        preserveCodecMetadata: Bool = true,
        copyDispositions: Bool = true
    ) {
        self.mode = mode
        self.chapterMode = chapterMode
        self.aspectRatioMode = aspectRatioMode
        self.customAspectRatio = customAspectRatio
        self.preserveKeys = preserveKeys
        self.stripKeys = stripKeys
        self.preserveCodecMetadata = preserveCodecMetadata
        self.copyDispositions = copyDispositions
    }
}

// MARK: - MetadataPassthroughBuilder

/// Builds FFmpeg arguments for metadata passthrough, chapter preservation,
/// and aspect ratio handling during transcoding.
///
/// Phases 2.9 / 3.16 / 3.16a
public struct MetadataPassthroughBuilder: Sendable {

    // MARK: - Global Metadata

    /// Build FFmpeg arguments for metadata passthrough.
    ///
    /// - Parameter config: Metadata passthrough configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildMetadataArguments(
        config: MetadataPassthroughConfig = MetadataPassthroughConfig()
    ) -> [String] {
        var args: [String] = []

        switch config.mode {
        case .copyAll:
            // -map_metadata 0 copies all metadata from first input
            args += ["-map_metadata", "0"]
        case .globalOnly:
            args += ["-map_metadata", "0"]
            // Strip per-stream metadata by mapping to -1 for each stream type
            args += ["-map_metadata:s", "-1"]
        case .streamOnly:
            args += ["-map_metadata", "-1"]
            args += ["-map_metadata:s:v", "0:s:v"]
            args += ["-map_metadata:s:a", "0:s:a"]
            args += ["-map_metadata:s:s", "0:s:s"]
        case .strip:
            args += ["-map_metadata", "-1"]
        case .custom:
            // Start with all metadata, then strip specific keys
            args += ["-map_metadata", "0"]
            for key in config.stripKeys {
                args += ["-metadata", "\(key)="]
            }
        }

        return args
    }

    // MARK: - Chapter Passthrough

    /// Build FFmpeg arguments for chapter handling.
    ///
    /// - Parameter mode: Chapter passthrough mode.
    /// - Returns: FFmpeg argument array.
    public static func buildChapterArguments(
        mode: ChapterPassthroughMode = .copy
    ) -> [String] {
        switch mode {
        case .copy:
            // -map_chapters 0 copies chapters from first input
            return ["-map_chapters", "0"]
        case .strip:
            // -map_chapters -1 removes all chapters
            return ["-map_chapters", "-1"]
        }
    }

    // MARK: - Aspect Ratio

    /// Build FFmpeg arguments for display aspect ratio handling.
    ///
    /// - Parameters:
    ///   - mode: Aspect ratio handling mode.
    ///   - customRatio: Custom aspect ratio string (e.g., "16:9").
    /// - Returns: FFmpeg argument array.
    public static func buildAspectRatioArguments(
        mode: AspectRatioMode = .preserve,
        customRatio: String? = nil
    ) -> [String] {
        switch mode {
        case .preserve:
            // FFmpeg preserves aspect ratio by default when using -c:v copy
            // For re-encodes, we need -aspect to explicitly set it
            return []
        case .override_:
            guard let ratio = customRatio else { return [] }
            return ["-aspect", ratio]
        case .remove:
            // Setting aspect to 0 removes SAR/DAR metadata
            return ["-aspect", "0"]
        }
    }

    // MARK: - Disposition Flags

    /// Build FFmpeg arguments for stream disposition flag copying.
    ///
    /// Dispositions include: default, dub, original, comment,
    /// lyrics, karaoke, forced, hearing_impaired, visual_impaired.
    ///
    /// - Parameters:
    ///   - copyDispositions: Whether to preserve disposition flags.
    ///   - streamIndex: Stream index (nil = all streams).
    /// - Returns: FFmpeg argument array.
    public static func buildDispositionArguments(
        copyDispositions: Bool = true,
        streamIndex: Int? = nil
    ) -> [String] {
        guard !copyDispositions else { return [] }
        // Reset dispositions to 0 (none)
        if let idx = streamIndex {
            return ["-disposition:\(idx)", "0"]
        }
        return ["-disposition", "0"]
    }

    /// Build FFmpeg arguments to set a stream as default.
    ///
    /// - Parameters:
    ///   - streamSpecifier: Stream specifier (e.g., "a:0" for first audio).
    /// - Returns: FFmpeg argument array.
    public static func buildSetDefaultStream(
        streamSpecifier: String
    ) -> [String] {
        return ["-disposition:\(streamSpecifier)", "default"]
    }

    // MARK: - Codec Metadata

    /// Build FFmpeg arguments to preserve codec-specific side data.
    ///
    /// This includes HDR metadata (mastering display, content light level),
    /// rotation metadata, and other codec-specific parameters.
    ///
    /// - Parameter preserve: Whether to preserve codec metadata.
    /// - Returns: FFmpeg argument array.
    public static func buildCodecMetadataArguments(
        preserve: Bool = true
    ) -> [String] {
        guard preserve else {
            return ["-bitexact"]
        }
        return []
    }

    // MARK: - Full Builder

    /// Build complete FFmpeg metadata arguments from configuration.
    ///
    /// Combines metadata, chapter, aspect ratio, and disposition arguments.
    ///
    /// - Parameter config: Full metadata passthrough configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildAllArguments(
        config: MetadataPassthroughConfig = MetadataPassthroughConfig()
    ) -> [String] {
        var args: [String] = []

        args += buildMetadataArguments(config: config)
        args += buildChapterArguments(mode: config.chapterMode)
        args += buildAspectRatioArguments(
            mode: config.aspectRatioMode,
            customRatio: config.customAspectRatio
        )

        if !config.copyDispositions {
            args += buildDispositionArguments(copyDispositions: false)
        }

        args += buildCodecMetadataArguments(preserve: config.preserveCodecMetadata)

        return args
    }

    // MARK: - Same-Format Re-encode Metadata

    /// Build FFmpeg arguments to preserve codec-specific metadata on same-format re-encode.
    ///
    /// When re-encoding H.265 to H.265, for instance, certain codec parameters
    /// (VUI, colour description, HDR SEI) should be preserved unless explicitly changed.
    ///
    /// Phase 3.16a
    ///
    /// - Parameters:
    ///   - colorPrimaries: Source colour primaries (e.g., "bt2020").
    ///   - transferCharacteristics: Source transfer function (e.g., "smpte2084").
    ///   - colorMatrix: Source colour matrix (e.g., "bt2020nc").
    /// - Returns: FFmpeg argument array for colour description preservation.
    public static func buildColorDescriptionArguments(
        colorPrimaries: String?,
        transferCharacteristics: String?,
        colorMatrix: String?
    ) -> [String] {
        var args: [String] = []
        if let cp = colorPrimaries {
            args += ["-color_primaries", cp]
        }
        if let tc = transferCharacteristics {
            args += ["-color_trc", tc]
        }
        if let cm = colorMatrix {
            args += ["-colorspace", cm]
        }
        return args
    }

    /// Build FFmpeg arguments for dynamic aspect ratio switching metadata.
    ///
    /// Some content uses Active Format Description (AFD) or bar data
    /// to signal aspect ratio changes within a stream.
    ///
    /// Phase 3.16
    ///
    /// - Parameter preserveAFD: Whether to preserve AFD data.
    /// - Returns: FFmpeg argument array.
    public static func buildAFDPreservationArguments(
        preserveAFD: Bool = true
    ) -> [String] {
        guard preserveAFD else { return [] }
        // Pass through AFD/bar data via stream copy or metadata
        return ["-copy_unknown"]
    }
}
