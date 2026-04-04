// ============================================================================
// MeedyaConverter — CodecMetadataPreserver
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DynamicAspectRatioInfo

/// Information about dynamic aspect ratio switching in a video stream.
public struct DynamicAspectRatioInfo: Codable, Sendable {
    /// Active Format Description code (0-15).
    public var afdCode: Int?

    /// Bar data present (SMPTE 2016-1 letterbox/pillarbox signalling).
    public var hasBarData: Bool

    /// Display aspect ratios found in the stream.
    public var detectedRatios: [String]

    /// Whether the stream uses AFD-based aspect ratio switching.
    public var usesDynamicAR: Bool

    public init(
        afdCode: Int? = nil,
        hasBarData: Bool = false,
        detectedRatios: [String] = [],
        usesDynamicAR: Bool = false
    ) {
        self.afdCode = afdCode
        self.hasBarData = hasBarData
        self.detectedRatios = detectedRatios
        self.usesDynamicAR = usesDynamicAR
    }
}

// MARK: - CodecParameterSet

/// Codec-specific parameters extracted from source for re-encode preservation.
public struct CodecParameterSet: Codable, Sendable {
    // Colour description
    public var colorPrimaries: String?
    public var transferCharacteristics: String?
    public var colorMatrix: String?
    public var colorRange: String?

    // HDR metadata
    public var masteringDisplayColorVolume: String?
    public var contentLightLevel: String?

    // Pixel format
    public var pixelFormat: String?
    public var bitDepth: Int?
    public var chromaSubsampling: String?

    // Video properties
    public var fieldOrder: String?
    public var displayAspectRatio: String?
    public var sampleAspectRatio: String?

    // Dynamic metadata
    public var dynamicAspectRatio: DynamicAspectRatioInfo?

    // Rotation
    public var rotationDegrees: Int?

    public init(
        colorPrimaries: String? = nil,
        transferCharacteristics: String? = nil,
        colorMatrix: String? = nil,
        colorRange: String? = nil,
        masteringDisplayColorVolume: String? = nil,
        contentLightLevel: String? = nil,
        pixelFormat: String? = nil,
        bitDepth: Int? = nil,
        chromaSubsampling: String? = nil,
        fieldOrder: String? = nil,
        displayAspectRatio: String? = nil,
        sampleAspectRatio: String? = nil,
        dynamicAspectRatio: DynamicAspectRatioInfo? = nil,
        rotationDegrees: Int? = nil
    ) {
        self.colorPrimaries = colorPrimaries
        self.transferCharacteristics = transferCharacteristics
        self.colorMatrix = colorMatrix
        self.colorRange = colorRange
        self.masteringDisplayColorVolume = masteringDisplayColorVolume
        self.contentLightLevel = contentLightLevel
        self.pixelFormat = pixelFormat
        self.bitDepth = bitDepth
        self.chromaSubsampling = chromaSubsampling
        self.fieldOrder = fieldOrder
        self.displayAspectRatio = displayAspectRatio
        self.sampleAspectRatio = sampleAspectRatio
        self.dynamicAspectRatio = dynamicAspectRatio
        self.rotationDegrees = rotationDegrees
    }
}

// MARK: - CodecMetadataPreserver

/// Builds FFmpeg arguments for deep codec metadata preservation during
/// same-format re-encoding and dynamic aspect ratio handling.
///
/// When re-encoding (e.g., H.265→H.265 at different CRF), all codec-level
/// parameters should be preserved unless the user explicitly changes them.
/// This includes colour description, HDR SEI, mastering display metadata,
/// pixel format, field order, and dynamic aspect ratio signalling.
///
/// Phase 3 / Issues #243, #244
public struct CodecMetadataPreserver: Sendable {

    // MARK: - Same-Format Re-encode

    /// Build FFmpeg arguments to preserve all codec parameters on same-format re-encode.
    ///
    /// - Parameter params: Extracted codec parameters from source.
    /// - Returns: FFmpeg argument array.
    public static func buildPreservationArguments(
        params: CodecParameterSet
    ) -> [String] {
        var args: [String] = []

        // Colour description
        args += buildColorDescriptionArguments(params: params)

        // HDR mastering display
        if let mdcv = params.masteringDisplayColorVolume {
            args += ["-master_disp", mdcv]
        }

        // Content light level
        if let cll = params.contentLightLevel {
            args += ["-max_cll", cll]
        }

        // Pixel format
        if let pf = params.pixelFormat {
            args += ["-pix_fmt", pf]
        }

        // Field order (interlaced content)
        if let fo = params.fieldOrder, fo != "progressive" {
            args += ["-field_order", fo]
        }

        // Sample aspect ratio
        if let sar = params.sampleAspectRatio, sar != "1:1" {
            args += ["-aspect", params.displayAspectRatio ?? sar]
        }

        // Rotation
        if let rot = params.rotationDegrees, rot != 0 {
            args += ["-metadata:s:v:0", "rotate=\(rot)"]
        }

        // Dynamic aspect ratio (AFD/bar data)
        args += buildDynamicARPreservationArguments(info: params.dynamicAspectRatio)

        return args
    }

    /// Build FFmpeg arguments for colour description preservation.
    ///
    /// - Parameter params: Codec parameters.
    /// - Returns: FFmpeg argument array.
    public static func buildColorDescriptionArguments(
        params: CodecParameterSet
    ) -> [String] {
        var args: [String] = []

        if let cp = params.colorPrimaries {
            args += ["-color_primaries", cp]
        }
        if let tc = params.transferCharacteristics {
            args += ["-color_trc", tc]
        }
        if let cm = params.colorMatrix {
            args += ["-colorspace", cm]
        }
        if let cr = params.colorRange {
            args += ["-color_range", cr]
        }

        return args
    }

    // MARK: - Dynamic Aspect Ratio

    /// Build FFmpeg arguments to preserve dynamic aspect ratio switching metadata.
    ///
    /// Active Format Description (AFD) and bar data (SMPTE 2016-1) signal
    /// dynamic aspect ratio changes within a stream. These are used by
    /// broadcast content that switches between 4:3 and 16:9, or scope
    /// and flat ratios in cinema content.
    ///
    /// - Parameter info: Dynamic aspect ratio information.
    /// - Returns: FFmpeg argument array.
    public static func buildDynamicARPreservationArguments(
        info: DynamicAspectRatioInfo?
    ) -> [String] {
        guard let info = info, info.usesDynamicAR else { return [] }

        var args: [String] = []

        // Preserve unknown/vendor-specific data packets including AFD
        args += ["-copy_unknown"]

        // Pass through AFD SEI in H.264/H.265
        if info.hasBarData {
            args += ["-bsf:v", "extract_extradata"]
        }

        return args
    }

    /// Build FFmpeg arguments to detect AFD in a source stream.
    ///
    /// - Parameter inputPath: Source video file.
    /// - Returns: FFmpeg argument array for AFD detection analysis.
    public static func buildAFDDetectionArguments(
        inputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-vf", "showinfo",
            "-vframes", "100",
            "-f", "null",
            "-hide_banner",
            "-",
        ]
    }

    // MARK: - Extraction from FFprobe

    /// Parse CodecParameterSet from FFprobe JSON video stream data.
    ///
    /// Expected keys from FFprobe JSON `streams[0]`:
    /// - `color_primaries`, `color_transfer`, `color_space`, `color_range`
    /// - `pix_fmt`, `bits_per_raw_sample`
    /// - `field_order`
    /// - `display_aspect_ratio`, `sample_aspect_ratio`
    ///
    /// - Parameter streamData: Dictionary from FFprobe JSON stream entry.
    /// - Returns: Parsed codec parameter set.
    public static func parseFromFFprobeStream(
        _ streamData: [String: Any]
    ) -> CodecParameterSet {
        return CodecParameterSet(
            colorPrimaries: streamData["color_primaries"] as? String,
            transferCharacteristics: streamData["color_transfer"] as? String,
            colorMatrix: streamData["color_space"] as? String,
            colorRange: streamData["color_range"] as? String,
            pixelFormat: streamData["pix_fmt"] as? String,
            bitDepth: streamData["bits_per_raw_sample"] as? Int,
            fieldOrder: streamData["field_order"] as? String,
            displayAspectRatio: streamData["display_aspect_ratio"] as? String,
            sampleAspectRatio: streamData["sample_aspect_ratio"] as? String
        )
    }

    /// Parse mastering display and content light level from FFprobe side data.
    ///
    /// - Parameter sideDataList: Array of side data dictionaries from FFprobe.
    /// - Returns: Tuple of (masteringDisplay, contentLightLevel) strings.
    public static func parseHDRSideData(
        _ sideDataList: [[String: Any]]
    ) -> (masteringDisplay: String?, contentLightLevel: String?) {
        var mdcv: String?
        var cll: String?

        for sideData in sideDataList {
            let type = sideData["side_data_type"] as? String ?? ""

            if type.contains("Mastering display") {
                // Build MDCV string from components
                if let rX = sideData["red_x"] as? String,
                   let rY = sideData["red_y"] as? String,
                   let gX = sideData["green_x"] as? String,
                   let gY = sideData["green_y"] as? String,
                   let bX = sideData["blue_x"] as? String,
                   let bY = sideData["blue_y"] as? String,
                   let wpX = sideData["white_point_x"] as? String,
                   let wpY = sideData["white_point_y"] as? String,
                   let maxL = sideData["max_luminance"] as? String,
                   let minL = sideData["min_luminance"] as? String {
                    mdcv = "G(\(gX),\(gY))B(\(bX),\(bY))R(\(rX),\(rY))WP(\(wpX),\(wpY))L(\(maxL),\(minL))"
                }
            }

            if type.contains("Content light level") {
                if let maxCLL = sideData["max_content"] as? Int,
                   let maxFALL = sideData["max_average"] as? Int {
                    cll = "\(maxCLL),\(maxFALL)"
                }
            }
        }

        return (masteringDisplay: mdcv, contentLightLevel: cll)
    }

    // MARK: - Validation

    /// Validate that codec parameters are consistent.
    ///
    /// - Parameter params: Codec parameter set to validate.
    /// - Returns: Array of warnings. Empty means valid.
    public static func validateParameters(_ params: CodecParameterSet) -> [String] {
        var warnings: [String] = []

        // HDR requires bt2020 primaries
        if let tc = params.transferCharacteristics,
           (tc == "smpte2084" || tc == "arib-std-b67") {
            if let cp = params.colorPrimaries, cp != "bt2020" {
                warnings.append("HDR transfer '\(tc)' typically requires bt2020 primaries, found '\(cp)'")
            }
        }

        // 10-bit required for HDR
        if let tc = params.transferCharacteristics,
           (tc == "smpte2084" || tc == "arib-std-b67") {
            if let bd = params.bitDepth, bd < 10 {
                warnings.append("HDR requires at least 10-bit depth, found \(bd)-bit")
            }
        }

        return warnings
    }
}
