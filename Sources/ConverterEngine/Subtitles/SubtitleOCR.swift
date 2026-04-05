// ============================================================================
// MeedyaConverter — SubtitleOCR (Issue #317)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - SubtitlePosition

/// Vertical position for burned-in subtitle text.
///
/// Controls the placement of subtitle overlays when using the burn-in
/// pipeline. The position maps to the ``MarginV`` parameter in ASS/SSA
/// styling and the ``y`` offset in FFmpeg's ``subtitles`` filter.
public enum SubtitlePosition: String, Codable, Sendable, CaseIterable {

    /// Bottom of the video frame — the default and most common placement.
    case bottom

    /// Top of the video frame — used for commentary or secondary subtitles.
    case top

    /// Vertically centred — rarely used; useful for karaoke or artistic effects.
    case center

    /// Human-readable label for display in the UI.
    public var displayName: String {
        switch self {
        case .bottom: return "Bottom"
        case .top:    return "Top"
        case .center: return "Center"
        }
    }
}

// MARK: - BurnInStyle

/// Visual styling parameters for subtitle burn-in.
///
/// Maps to the ``force_style`` option of FFmpeg's ``subtitles`` and ``ass``
/// video filters. When ``nil`` values are supplied, FFmpeg uses its built-in
/// defaults for that property.
///
/// Example force_style string:
/// ```
/// subtitles=input.srt:force_style='FontSize=24,FontName=Arial,
///   PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000'
/// ```
///
/// Phase 5 — Subtitle OCR and Burn-in (Issue #317)
public struct BurnInStyle: Codable, Sendable {

    /// Font size in points for the burned-in text.
    public let fontSize: Int

    /// Font family name (e.g., "Arial", "Helvetica Neue").
    /// When ``nil``, FFmpeg uses its default sans-serif font.
    public let fontName: String?

    /// Primary (fill) colour in ASS ``&HAABBGGRR`` hex format.
    /// Example: ``"&H00FFFFFF"`` for opaque white.
    public let primaryColor: String?

    /// Outline (border) colour in ASS ``&HAABBGGRR`` hex format.
    /// Example: ``"&H00000000"`` for opaque black.
    public let outlineColor: String?

    /// Vertical position of the subtitle text within the frame.
    public let position: SubtitlePosition

    /// Creates a new burn-in style configuration.
    ///
    /// - Parameters:
    ///   - fontSize: Font size in points (default 24).
    ///   - fontName: Optional font family name.
    ///   - primaryColor: Fill colour in ASS hex format.
    ///   - outlineColor: Outline colour in ASS hex format.
    ///   - position: Vertical text position (default ``.bottom``).
    public init(
        fontSize: Int = 24,
        fontName: String? = nil,
        primaryColor: String? = nil,
        outlineColor: String? = nil,
        position: SubtitlePosition = .bottom
    ) {
        self.fontSize = fontSize
        self.fontName = fontName
        self.primaryColor = primaryColor
        self.outlineColor = outlineColor
        self.position = position
    }
}

// MARK: - SubtitleOCR

/// Builds FFmpeg / Tesseract argument arrays for subtitle OCR extraction
/// and subtitle burn-in.
///
/// Three primary workflows:
/// 1. **PGS → SRT**: Extract bitmap PGS (Blu-ray) subtitles to images,
///    then OCR with Tesseract into SubRip text.
/// 2. **VobSub → SRT**: Extract bitmap VobSub (DVD) subtitles to images,
///    then OCR with Tesseract into SubRip text.
/// 3. **Burn-in**: Overlay text subtitles (SRT, ASS) onto the video frame
///    as a permanent visual element using FFmpeg video filters.
///
/// Phase 5 — Subtitle OCR and Burn-in (Issue #317)
public struct SubtitleOCR: Sendable {

    // MARK: - PGS → SRT

    /// Builds FFmpeg arguments to extract PGS bitmap subtitles and OCR
    /// them into an SRT file.
    ///
    /// The pipeline extracts the PGS stream as individual PNG images
    /// using FFmpeg, then relies on an external Tesseract pass to convert
    /// the images to text. This method returns the FFmpeg extraction step.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source MKV/M2TS file containing PGS subs.
    ///   - outputPath: Destination path for the output SRT file.
    ///   - trackIndex: Zero-based subtitle stream index within the container.
    /// - Returns: FFmpeg argument array for PGS extraction.
    public static func buildPGSToSRTArguments(
        inputPath: String,
        outputPath: String,
        trackIndex: Int
    ) -> [String] {
        var args: [String] = ["-y", "-nostdin"]

        // Input file
        args += ["-i", inputPath]

        // Map the specific PGS subtitle stream
        args += ["-map", "0:s:\(trackIndex)"]

        // Output as bitmap images for Tesseract OCR processing.
        // FFmpeg extracts PGS to PGS format; downstream Tesseract
        // converts the bitmaps to SRT text.
        args += ["-c:s", "copy"]

        // Use the .sup (PGS) intermediate for OCR tools like PGSToSRT
        let intermediateSupPath = (outputPath as NSString)
            .deletingPathExtension
            .appending(".sup")
        args += [intermediateSupPath]

        return args
    }

    // MARK: - VobSub → SRT

    /// Builds FFmpeg arguments to extract VobSub bitmap subtitles for OCR
    /// processing into SRT.
    ///
    /// VobSub subtitles (DVD .sub/.idx pairs) are extracted as a raw
    /// bitmap stream. Downstream OCR tools (e.g., VobSub2SRT, Tesseract)
    /// then convert the extracted bitmaps to text.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source file containing VobSub subs.
    ///   - outputPath: Destination path for the output SRT file.
    ///   - trackIndex: Zero-based subtitle stream index.
    /// - Returns: FFmpeg argument array for VobSub extraction.
    public static func buildVobSubToSRTArguments(
        inputPath: String,
        outputPath: String,
        trackIndex: Int
    ) -> [String] {
        var args: [String] = ["-y", "-nostdin"]

        // Input file
        args += ["-i", inputPath]

        // Map the specific VobSub subtitle stream
        args += ["-map", "0:s:\(trackIndex)"]

        // Copy the VobSub stream to a .sub file for OCR tools
        args += ["-c:s", "dvdsub"]

        let intermediateSubPath = (outputPath as NSString)
            .deletingPathExtension
            .appending(".sub")
        args += [intermediateSubPath]

        return args
    }

    // MARK: - Burn-in

    /// Builds FFmpeg arguments to burn subtitles into the video frame.
    ///
    /// Supports both SRT (using the ``subtitles`` filter) and ASS/SSA
    /// (using the ``ass`` filter). When a ``BurnInStyle`` is provided,
    /// it is mapped to the ``force_style`` parameter of the filter.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source video file.
    ///   - subtitlePath: Path to the subtitle file (.srt, .ass, .ssa).
    ///   - style: Optional visual styling for the burned-in text.
    /// - Returns: FFmpeg argument array for subtitle burn-in.
    public static func buildBurnInArguments(
        inputPath: String,
        subtitlePath: String,
        style: BurnInStyle?
    ) -> [String] {
        var args: [String] = ["-y", "-nostdin"]

        // Input video
        args += ["-i", inputPath]

        // Determine filter based on subtitle file extension
        let ext = (subtitlePath as NSString).pathExtension.lowercased()
        let isASS = ext == "ass" || ext == "ssa"

        // Build the video filter string
        let filterString: String
        if isASS {
            filterString = buildASSFilterString(
                subtitlePath: subtitlePath,
                style: style
            )
        } else {
            filterString = buildSRTFilterString(
                subtitlePath: subtitlePath,
                style: style
            )
        }

        args += ["-vf", filterString]

        // Copy audio and other streams untouched
        args += ["-c:a", "copy"]

        return args
    }

    // MARK: - Private Helpers

    /// Builds the ``subtitles`` filter string for SRT/text subtitle burn-in.
    ///
    /// - Parameters:
    ///   - subtitlePath: Path to the SRT file (colons and backslashes are escaped).
    ///   - style: Optional burn-in styling parameters.
    /// - Returns: FFmpeg ``-vf`` filter string.
    private static func buildSRTFilterString(
        subtitlePath: String,
        style: BurnInStyle?
    ) -> String {
        // Escape special characters in the path for FFmpeg filter syntax
        let escapedPath = subtitlePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")

        var filter = "subtitles='\(escapedPath)'"

        if let style = style {
            let forceStyle = buildForceStyleString(style: style)
            if !forceStyle.isEmpty {
                filter += ":force_style='\(forceStyle)'"
            }
        }

        return filter
    }

    /// Builds the ``ass`` filter string for ASS/SSA subtitle burn-in.
    ///
    /// - Parameters:
    ///   - subtitlePath: Path to the ASS/SSA file.
    ///   - style: Optional burn-in styling overrides.
    /// - Returns: FFmpeg ``-vf`` filter string.
    private static func buildASSFilterString(
        subtitlePath: String,
        style: BurnInStyle?
    ) -> String {
        let escapedPath = subtitlePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")

        var filter = "ass='\(escapedPath)'"

        if let style = style {
            let forceStyle = buildForceStyleString(style: style)
            if !forceStyle.isEmpty {
                filter += ":force_style='\(forceStyle)'"
            }
        }

        return filter
    }

    /// Assembles the ASS ``force_style`` parameter string from a ``BurnInStyle``.
    ///
    /// - Parameter style: The burn-in style configuration.
    /// - Returns: Comma-separated ASS style overrides (e.g., "FontSize=24,FontName=Arial").
    private static func buildForceStyleString(style: BurnInStyle) -> String {
        var parts: [String] = []

        parts.append("FontSize=\(style.fontSize)")

        if let fontName = style.fontName {
            parts.append("FontName=\(fontName)")
        }

        if let primaryColor = style.primaryColor {
            parts.append("PrimaryColour=\(primaryColor)")
        }

        if let outlineColor = style.outlineColor {
            parts.append("OutlineColour=\(outlineColor)")
        }

        // Map SubtitlePosition to ASS Alignment values.
        // ASS uses numpad-style alignment: 2=bottom-center, 8=top-center, 5=center.
        switch style.position {
        case .bottom:
            parts.append("Alignment=2")
        case .top:
            parts.append("Alignment=8")
        case .center:
            parts.append("Alignment=5")
        }

        return parts.joined(separator: ",")
    }
}
