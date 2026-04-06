// ============================================================================
// MeedyaConverter — DualDynamicHDRPipeline
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DualHDRTarget

/// Target format for dual dynamic HDR conversion.
///
/// Each target produces a single HEVC stream with multiple HDR metadata layers,
/// enabling automatic fallback across devices with varying HDR capabilities.
public enum DualHDRTarget: String, Codable, Sendable, CaseIterable {
    /// DV Profile 8.1 + HDR10+ — four-tier playback chain.
    ///
    /// Fallback order: Dolby Vision -> HDR10+ -> HDR10 -> SDR.
    /// Profile 8.1 uses PQ (ST 2084) transfer function for the HDR10 base layer.
    /// This is the broadest compatibility option, covering DV displays, HDR10+ displays,
    /// standard HDR10 displays, and SDR displays from a single stream.
    case dvPlusHDR10Plus = "dv_plus_hdr10plus"

    /// DV Profile 8.4 + HDR10+ + HLG — five-tier playback chain.
    ///
    /// Fallback order: Dolby Vision -> HDR10+ -> HLG -> HDR10 -> SDR.
    /// Profile 8.4 uses HLG (ARIB STD-B67) transfer function for the base layer,
    /// adding an HLG tier for broadcast-compatible displays. Requires PQ->HLG
    /// base layer conversion during the pipeline.
    case dvPlusHDR10PlusHLG = "dv_plus_hdr10plus_hlg"

    /// Human-readable display name for the UI.
    public var displayName: String {
        switch self {
        case .dvPlusHDR10Plus:
            return "DV + HDR10+ (Four-Tier)"
        case .dvPlusHDR10PlusHLG:
            return "DV + HDR10+ + HLG (Five-Tier)"
        }
    }

    /// Description of the fallback chain for the target.
    public var fallbackChain: String {
        switch self {
        case .dvPlusHDR10Plus:
            return "Dolby Vision \u{2192} HDR10+ \u{2192} HDR10 \u{2192} SDR"
        case .dvPlusHDR10PlusHLG:
            return "Dolby Vision \u{2192} HDR10+ \u{2192} HLG \u{2192} HDR10 \u{2192} SDR"
        }
    }

    /// Number of playback tiers in the fallback chain.
    public var tierCount: Int {
        switch self {
        case .dvPlusHDR10Plus: return 4
        case .dvPlusHDR10PlusHLG: return 5
        }
    }
}

// MARK: - DualDynamicHDRConfig

/// Configuration for a dual dynamic HDR conversion pipeline.
///
/// Specifies the source DV profile, target format, and processing options
/// for the multi-step conversion from single-format DV to dual dynamic HDR.
public struct DualDynamicHDRConfig: Codable, Sendable {
    /// The source Dolby Vision profile detected from the input file.
    public var sourceProfile: DoviProfile

    /// The target dual dynamic HDR format.
    public var target: DualHDRTarget

    /// Whether to preserve existing DV dynamic metadata from the source RPU.
    ///
    /// When `true`, the existing DV RPU is converted (Profile 5/7 -> 8.x) and its
    /// per-frame dynamic data is used as the basis for HDR10+ metadata generation.
    /// When `false`, new static RPU metadata is generated from MaxCLL/MaxFALL.
    public var preserveDVDynamicMetadata: Bool

    /// Temporary directory for intermediate files produced during the pipeline.
    public var tempDirectory: URL

    public init(
        sourceProfile: DoviProfile,
        target: DualHDRTarget,
        preserveDVDynamicMetadata: Bool = true,
        tempDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.sourceProfile = sourceProfile
        self.target = target
        self.preserveDVDynamicMetadata = preserveDVDynamicMetadata
        self.tempDirectory = tempDirectory
    }
}

// MARK: - PipelineStepDescriptor

/// Describes a single step in the dual dynamic HDR conversion pipeline.
///
/// Each step maps to one invocation of an external tool (dovi_tool,
/// hdr10plus_tool, or ffmpeg). The pipeline executor runs these in order,
/// feeding each step's output as the next step's input.
public struct PipelineStepDescriptor: Identifiable, Sendable {
    /// Unique identifier for this step.
    public let id: UUID

    /// Sequential step number (1-based).
    public let stepNumber: Int

    /// The external tool to invoke (e.g., "dovi_tool", "hdr10plus_tool", "ffmpeg").
    public let tool: String

    /// Human-readable description of what this step does.
    public let description: String

    /// Command-line arguments for the tool invocation.
    public let arguments: [String]

    /// Path to the input file consumed by this step.
    public let inputPath: String

    /// Path to the output file produced by this step.
    public let outputPath: String

    public init(
        id: UUID = UUID(),
        stepNumber: Int,
        tool: String,
        description: String,
        arguments: [String],
        inputPath: String,
        outputPath: String
    ) {
        self.id = id
        self.stepNumber = stepNumber
        self.tool = tool
        self.description = description
        self.arguments = arguments
        self.inputPath = inputPath
        self.outputPath = outputPath
    }
}

// MARK: - DualDynamicHDRPipeline

/// Builds and describes the multi-step pipeline for converting Dolby Vision
/// content to dual dynamic HDR (DV + HDR10+) output.
///
/// The pipeline chains dovi_tool and hdr10plus_tool operations to produce
/// an HEVC stream carrying both Dolby Vision RPU and HDR10+ SEI metadata.
/// This enables maximum device compatibility: DV-capable displays use the
/// RPU layer, HDR10+ displays use the SEI layer, and all others fall back
/// to static HDR10 or SDR.
///
/// ## Pipeline Overview (Profile 5 -> DV 8.1 + HDR10+)
///
/// ```
/// Step 1: dovi_tool extract-rpu          — extract original RPU
/// Step 2: dovi_tool convert              — convert RPU to Profile 8.1
/// Step 3: dovi_tool export               — export DV dynamic data as JSON
/// Step 4: internal conversion            — DV metadata JSON -> HDR10+ JSON
/// Step 5: hdr10plus_tool inject          — inject HDR10+ into HEVC stream
/// Step 6: dovi_tool inject-rpu           — inject converted RPU into final stream
/// ```
///
/// Phase 3.9 / Issue #370
public struct DualDynamicHDRPipeline: Sendable {

    // MARK: - Pipeline Building

    /// Build the ordered list of pipeline steps for the given configuration.
    ///
    /// Each step is a self-contained tool invocation with explicit input/output
    /// paths rooted in the config's temp directory. The caller is responsible
    /// for executing the steps in order and cleaning up temp files.
    ///
    /// - Parameters:
    ///   - config: The dual dynamic HDR configuration.
    ///   - inputPath: Path to the source HEVC elementary stream.
    ///   - outputPath: Path for the final HEVC stream with dual HDR metadata.
    /// - Returns: Ordered array of pipeline step descriptors.
    public static func buildPipelineSteps(
        config: DualDynamicHDRConfig,
        inputPath: String,
        outputPath: String
    ) -> [PipelineStepDescriptor] {
        let tempDir = config.tempDirectory.path

        // Intermediate file paths
        let rpuBin = "\(tempDir)/rpu.bin"
        let rpuConverted: String
        let dvMetadataJSON = "\(tempDir)/dv_metadata.json"
        let hdr10PlusJSON = "\(tempDir)/hdr10plus.json"
        let hevcWithH10P = "\(tempDir)/hevc_with_h10p.hevc"

        // Determine target DV profile and conversion mode
        let targetProfile: DoviProfile
        switch config.target {
        case .dvPlusHDR10Plus:
            targetProfile = .profile8_1
            rpuConverted = "\(tempDir)/rpu_p81.bin"
        case .dvPlusHDR10PlusHLG:
            targetProfile = .profile8_4
            rpuConverted = "\(tempDir)/rpu_p84.bin"
        }

        var steps: [PipelineStepDescriptor] = []
        var stepNum = 1

        // Step 1: Extract original RPU from source HEVC
        steps.append(PipelineStepDescriptor(
            stepNumber: stepNum,
            tool: "dovi_tool",
            description: "Extract Dolby Vision RPU from source HEVC stream",
            arguments: ["extract-rpu", "-i", inputPath, "-o", rpuBin],
            inputPath: inputPath,
            outputPath: rpuBin
        ))
        stepNum += 1

        // Step 2: Convert RPU to target profile (e.g., Profile 5 -> 8.1)
        // The --discard flag is needed for Profile 5/7 sources to drop
        // IPTPQc2 or FEL data that cannot be represented in Profile 8.x.
        var convertArgs = ["convert", "--discard", "-m", "\(targetProfile.modeValue)",
                           "-i", rpuBin, "-o", rpuConverted]
        // For Profile 8.x -> 8.x conversions, --discard is not needed
        // but dovi_tool handles it gracefully either way.
        if config.sourceProfile == .profile8_1 || config.sourceProfile == .profile8_4 {
            convertArgs = ["convert", "-m", "\(targetProfile.modeValue)",
                           "-i", rpuBin, "-o", rpuConverted]
        }
        steps.append(PipelineStepDescriptor(
            stepNumber: stepNum,
            tool: "dovi_tool",
            description: "Convert RPU from \(config.sourceProfile.displayName) to \(targetProfile.displayName)",
            arguments: convertArgs,
            inputPath: rpuBin,
            outputPath: rpuConverted
        ))
        stepNum += 1

        // Step 3: Export DV dynamic metadata to JSON for HDR10+ conversion
        steps.append(PipelineStepDescriptor(
            stepNumber: stepNum,
            tool: "dovi_tool",
            description: "Export Dolby Vision dynamic metadata to JSON",
            arguments: ["export", "-i", rpuBin, "-o", dvMetadataJSON],
            inputPath: rpuBin,
            outputPath: dvMetadataJSON
        ))
        stepNum += 1

        // Step 4: Convert DV metadata JSON to HDR10+ JSON format
        // This is an internal conversion step (no external tool invocation).
        // The pipeline executor should call convertDVMetadataToHDR10Plus() for this step.
        steps.append(PipelineStepDescriptor(
            stepNumber: stepNum,
            tool: "internal",
            description: "Convert Dolby Vision dynamic metadata to HDR10+ format",
            arguments: ["convert-metadata", dvMetadataJSON, hdr10PlusJSON],
            inputPath: dvMetadataJSON,
            outputPath: hdr10PlusJSON
        ))
        stepNum += 1

        // Step 5: Inject HDR10+ metadata into the HEVC stream
        steps.append(PipelineStepDescriptor(
            stepNumber: stepNum,
            tool: "hdr10plus_tool",
            description: "Inject HDR10+ dynamic metadata into HEVC stream",
            arguments: ["inject", "-i", inputPath, "-j", hdr10PlusJSON, "-o", hevcWithH10P],
            inputPath: inputPath,
            outputPath: hevcWithH10P
        ))
        stepNum += 1

        // Step 5.5 (HLG target only): Convert PQ base layer to HLG
        if config.target == .dvPlusHDR10PlusHLG {
            let hevcHLG = "\(tempDir)/hevc_hlg.hevc"
            steps.append(PipelineStepDescriptor(
                stepNumber: stepNum,
                tool: "ffmpeg",
                description: "Convert PQ base layer to HLG transfer function",
                arguments: [
                    "-i", hevcWithH10P,
                    "-vf", "zscale=transfer=arib-std-b67:primaries=bt2020:matrix=bt2020nc",
                    "-c:v", "libx265",
                    "-pix_fmt", "yuv420p10le",
                    "-y", hevcHLG,
                ],
                inputPath: hevcWithH10P,
                outputPath: hevcHLG
            ))
            stepNum += 1

            // Step 6: Inject converted RPU into HLG HEVC stream
            steps.append(PipelineStepDescriptor(
                stepNumber: stepNum,
                tool: "dovi_tool",
                description: "Inject DV \(targetProfile.displayName) RPU into final HEVC stream",
                arguments: ["inject-rpu", "-i", hevcHLG, "--rpu-in", rpuConverted, "-o", outputPath],
                inputPath: hevcHLG,
                outputPath: outputPath
            ))
        } else {
            // Step 6: Inject converted RPU into HDR10+-carrying HEVC stream
            steps.append(PipelineStepDescriptor(
                stepNumber: stepNum,
                tool: "dovi_tool",
                description: "Inject DV \(targetProfile.displayName) RPU into final HEVC stream",
                arguments: ["inject-rpu", "-i", hevcWithH10P, "--rpu-in", rpuConverted, "-o", outputPath],
                inputPath: hevcWithH10P,
                outputPath: outputPath
            ))
        }

        return steps
    }

    // MARK: - Metadata Conversion

    /// Convert Dolby Vision dynamic metadata JSON to HDR10+ JSON format.
    ///
    /// Maps per-frame DV target display luminance curves to HDR10+ bezier curves.
    /// If direct mapping fails (e.g., missing per-frame data), falls back to
    /// generating HDR10+ metadata from static MaxCLL/MaxFALL values.
    ///
    /// ## Mapping Strategy
    ///
    /// DV RPU JSON contains per-frame `target_max_pq` and `target_min_pq` values
    /// that describe the intended display luminance range. These are converted to
    /// HDR10+ `bezier_curve_anchors` and `targeted_system_display_maximum_luminance`
    /// values that serve an analogous purpose for HDR10+ tone mapping.
    ///
    /// - Parameters:
    ///   - dvMetadataPath: Path to the exported DV metadata JSON.
    ///   - hdr10PlusOutputPath: Path where the HDR10+ JSON will be written.
    /// - Throws: File I/O errors or JSON encoding/decoding errors.
    public static func convertDVMetadataToHDR10Plus(
        dvMetadataPath: String,
        hdr10PlusOutputPath: String
    ) throws {
        let dvData = try Data(contentsOf: URL(fileURLWithPath: dvMetadataPath))

        // Attempt to parse the DV export JSON.
        // The dovi_tool export format contains per-frame RPU data with
        // target display luminance information.
        guard let dvJSON = try JSONSerialization.jsonObject(with: dvData) as? [String: Any] else {
            // Fallback: generate minimal HDR10+ with default static values
            try generateFallbackHDR10Plus(
                maxCLL: 1000,
                maxFALL: 400,
                outputPath: hdr10PlusOutputPath
            )
            return
        }

        // Extract per-frame data from DV export
        // dovi_tool export format uses "rpu_list" array with per-frame entries
        guard let rpuList = dvJSON["rpu_list"] as? [[String: Any]], !rpuList.isEmpty else {
            // No per-frame data available — use static metadata fallback
            let maxCLL = (dvJSON["max_cll"] as? Int) ?? 1000
            let maxFALL = (dvJSON["max_fall"] as? Int) ?? 400
            try generateFallbackHDR10Plus(
                maxCLL: maxCLL,
                maxFALL: maxFALL,
                outputPath: hdr10PlusOutputPath
            )
            return
        }

        // Build HDR10+ JSON structure
        // HDR10+ uses SMPTE ST 2094-40 Application 4 format
        var hdr10PlusFrames: [[String: Any]] = []

        for rpuEntry in rpuList {
            var frame: [String: Any] = [:]

            // Extract target display luminance from DV RPU
            // DV uses PQ-encoded values (0-4095 range for 12-bit)
            let targetMaxPQ = rpuEntry["target_max_pq"] as? Int ?? 2081 // ~1000 nits
            let targetMinPQ = rpuEntry["target_min_pq"] as? Int ?? 62   // ~0.005 nits

            // Convert PQ code to linear luminance (nits)
            let maxLuminance = pqToNits(pqCode: targetMaxPQ)
            let minLuminance = pqToNits(pqCode: targetMinPQ)

            // Map to HDR10+ targeted system display parameters
            frame["targeted_system_display_maximum_luminance"] = Int(maxLuminance)

            // Generate bezier curve anchors from DV tone mapping data.
            // DV RPU contains polynomial coefficients for tone mapping;
            // we approximate these as HDR10+ bezier curve anchor points.
            // A simple linear-ish mapping provides reasonable results.
            let anchors = generateBezierAnchors(
                targetMaxNits: maxLuminance,
                targetMinNits: minLuminance
            )
            frame["bezier_curve_anchors"] = anchors

            // HDR10+ distribution parameters
            frame["maxscl"] = [
                rpuEntry["max_content_light_level"] as? Int ?? Int(maxLuminance),
                rpuEntry["max_content_light_level"] as? Int ?? Int(maxLuminance),
                rpuEntry["max_content_light_level"] as? Int ?? Int(maxLuminance),
            ]

            // Average maxRGB (approximation from DV data)
            frame["average_maxrgb"] = rpuEntry["avg_content_light_level"] as? Int ?? Int(maxLuminance * 0.3)

            // Number of distribution maxRGB percentiles
            frame["num_distribution_maxrgb_percentiles"] = 9

            hdr10PlusFrames.append(frame)
        }

        // Assemble the complete HDR10+ JSON
        let hdr10PlusRoot: [String: Any] = [
            "JSONInfo": [
                "HDR10plusProfile": "A",
                "Version": "1.0",
            ],
            "SceneInfo": hdr10PlusFrames,
        ]

        let outputData = try JSONSerialization.data(
            withJSONObject: hdr10PlusRoot,
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: URL(fileURLWithPath: hdr10PlusOutputPath))
    }

    // MARK: - Tool Availability

    /// Check whether both required tools are available for dual dynamic HDR.
    ///
    /// Both dovi_tool and hdr10plus_tool must be installed and locatable
    /// for the dual dynamic HDR pipeline to function.
    ///
    /// - Parameters:
    ///   - doviTool: The DoviToolWrapper instance.
    ///   - hdr10PlusTool: The HDR10PlusToolWrapper instance.
    /// - Returns: `true` if both tools are available.
    public static func isSupported(
        doviTool: DoviToolWrapper,
        hdr10PlusTool: HDR10PlusToolWrapper
    ) -> Bool {
        return doviTool.isAvailable && hdr10PlusTool.isAvailable
    }

    // MARK: - Private Helpers

    /// Generate fallback HDR10+ metadata from static MaxCLL/MaxFALL values.
    ///
    /// Used when per-frame DV dynamic metadata cannot be mapped to HDR10+ format.
    /// Produces a single-scene HDR10+ JSON with static luminance parameters.
    ///
    /// - Parameters:
    ///   - maxCLL: Maximum Content Light Level in nits.
    ///   - maxFALL: Maximum Frame Average Light Level in nits.
    ///   - outputPath: Path where the HDR10+ JSON will be written.
    /// - Throws: File I/O errors.
    private static func generateFallbackHDR10Plus(
        maxCLL: Int,
        maxFALL: Int,
        outputPath: String
    ) throws {
        let anchors = generateBezierAnchors(
            targetMaxNits: Double(maxCLL),
            targetMinNits: 0.005
        )

        let frame: [String: Any] = [
            "targeted_system_display_maximum_luminance": min(maxCLL, 4000),
            "bezier_curve_anchors": anchors,
            "maxscl": [maxCLL, maxCLL, maxCLL],
            "average_maxrgb": maxFALL,
            "num_distribution_maxrgb_percentiles": 9,
        ]

        let hdr10PlusRoot: [String: Any] = [
            "JSONInfo": [
                "HDR10plusProfile": "A",
                "Version": "1.0",
            ],
            "SceneInfo": [frame],
        ]

        let data = try JSONSerialization.data(
            withJSONObject: hdr10PlusRoot,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: outputPath))
    }

    /// Convert a PQ (SMPTE ST 2084) code value to linear luminance in nits.
    ///
    /// Uses the ST 2084 EOTF (Electro-Optical Transfer Function) to convert
    /// a 12-bit PQ code (0-4095) to absolute luminance (0-10000 nits).
    ///
    /// - Parameter pqCode: The PQ code value (0-4095 for 12-bit).
    /// - Returns: Linear luminance in nits.
    private static func pqToNits(pqCode: Int) -> Double {
        // Normalise to 0..1
        let pqNorm = Double(pqCode) / 4095.0

        // ST 2084 constants
        let m1 = 0.1593017578125
        let m2 = 78.84375
        let c1 = 0.8359375
        let c2 = 18.8515625
        let c3 = 18.6875

        // Inverse PQ EOTF
        let powPQ = pow(pqNorm, 1.0 / m2)
        let numerator = max(powPQ - c1, 0.0)
        let denominator = c2 - c3 * powPQ
        let linearNorm = pow(numerator / max(denominator, 1e-10), 1.0 / m1)

        // Scale to 10000 nits peak
        return linearNorm * 10000.0
    }

    /// Generate bezier curve anchor points for HDR10+ tone mapping.
    ///
    /// Creates a set of anchor points (0.0-1.0 normalised) that approximate
    /// a reasonable tone mapping curve for the given target display range.
    /// The curve is designed to preserve detail in highlights while
    /// smoothly rolling off above the target display's peak luminance.
    ///
    /// - Parameters:
    ///   - targetMaxNits: Target display maximum luminance in nits.
    ///   - targetMinNits: Target display minimum luminance in nits.
    /// - Returns: Array of bezier anchor values (typically 9 points).
    private static func generateBezierAnchors(
        targetMaxNits: Double,
        targetMinNits: Double
    ) -> [Double] {
        // Generate 9 anchor points for the bezier curve.
        // The curve maps source content luminance to display luminance,
        // with a gentle roll-off above 50% of the target peak.
        let peakRatio = min(targetMaxNits / 10000.0, 1.0)

        var anchors: [Double] = []
        for i in 1...9 {
            let t = Double(i) / 10.0
            // Apply a soft-knee curve that compresses highlights
            let anchor: Double
            if t <= 0.5 {
                // Linear region below midpoint
                anchor = t * peakRatio * 2.0
            } else {
                // Compressed region above midpoint
                let excess = (t - 0.5) * 2.0
                let compressed = 1.0 - pow(1.0 - excess, 1.5)
                anchor = peakRatio * (0.5 + compressed * 0.5) * (2.0 * t)
            }
            anchors.append(min(max(anchor, 0.0), 1.0))
        }

        return anchors
    }
}
