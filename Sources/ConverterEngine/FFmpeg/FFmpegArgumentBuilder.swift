// ============================================================================
// MeedyaConverter — FFmpegArgumentBuilder
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FFmpegArgumentBuilder

/// Builds FFmpeg command-line arguments from encoding configuration.
///
/// The argument builder translates high-level encoding settings (codec,
/// quality, container, stream selection) into the specific FFmpeg CLI
/// arguments needed to execute the encode.
///
/// Usage:
/// ```swift
/// var builder = FFmpegArgumentBuilder()
/// builder.inputURL = sourceFile
/// builder.outputURL = outputFile
/// builder.videoCodec = .h265
/// builder.videoCRF = 22
/// builder.audioCodec = .aacLC
/// builder.audioBitrate = 160_000
/// let args = builder.build()
/// // ["-i", "/path/source.mkv", "-c:v", "libx265", "-crf", "22",
/// //  "-c:a", "aac", "-b:a", "160k", "/path/output.mp4"]
/// ```
public struct FFmpegArgumentBuilder: Sendable {

    // MARK: - Input/Output

    /// The input file URL.
    public var inputURL: URL?

    /// The output file URL.
    public var outputURL: URL?

    /// Additional input files (for multi-input operations).
    public var additionalInputs: [URL] = []

    // MARK: - Video Settings

    /// The video codec to use for encoding. Nil means copy (passthrough).
    public var videoCodec: VideoCodec?

    /// Whether to passthrough (copy) the video stream without re-encoding.
    public var videoPassthrough: Bool = false

    /// Constant Rate Factor for quality-based VBR encoding.
    /// Lower values = higher quality. Typical range: 18-28 for H.265.
    public var videoCRF: Int?

    /// Quantization Parameter for hardware encoders.
    public var videoQP: Int?

    /// Target video bitrate in bits per second (for CBR/CVBR modes).
    public var videoBitrate: Int?

    /// Maximum video bitrate in bits per second (for CVBR/VBV buffering).
    public var videoMaxBitrate: Int?

    /// VBV buffer size in bits (for CVBR mode, typically 2x maxBitrate).
    public var videoBufferSize: Int?

    /// Output video width in pixels. Nil means match source.
    public var videoWidth: Int?

    /// Output video height in pixels. Nil means match source.
    public var videoHeight: Int?

    /// Output frame rate. Nil means match source.
    public var videoFrameRate: Double?

    /// Pixel format (e.g., "yuv420p", "yuv420p10le").
    public var pixelFormat: String?

    /// Video encoder preset (e.g., "medium", "slow", "veryslow" for x265).
    public var videoPreset: String?

    /// Video encoder tune parameter (e.g., "film", "animation", "grain").
    public var videoTune: String?

    /// Video encoder profile (e.g., "main", "main10", "high").
    public var videoProfile: String?

    /// Video encoder level (e.g., "4.1", "5.1").
    public var videoLevel: String?

    // MARK: - HDR / Tone Mapping (Phase 3.9b–3.9c)

    /// Whether to apply HDR-to-SDR tone mapping.
    /// When true, builds a libplacebo/zscale tone mapping filter chain that converts
    /// PQ/HLG/HDR10 → BT.709 SDR with the configured algorithm and parameters.
    public var toneMap: Bool = false

    /// Tone mapping algorithm. Maps to libplacebo tonemap function.
    public enum ToneMapAlgorithm: String, Sendable, CaseIterable {
        case hable      // Filmic S-curve (default, good for movies)
        case reinhard   // Simple, can clip highlights
        case mobius     // Smooth roll-off, good for mixed content
        case bt2390     // ITU-R BT.2390 reference curve
        case clip       // Hard clip (fastest, lowest quality)
    }

    /// The tone mapping algorithm to use.
    public var toneMapAlgorithm: ToneMapAlgorithm = .hable

    /// Peak brightness of the source in nits. Nil means auto-detect from metadata.
    public var toneMapPeakNits: Double?

    /// Desaturation strength (0.0 = none, 1.0 = full). Controls how much bright
    /// colours are desaturated during tone mapping to avoid over-saturation.
    public var toneMapDesaturation: Double?

    // MARK: - PQ → HLG Conversion (Issue #254)

    /// Whether to convert PQ (SMPTE ST 2084) transfer to HLG (ARIB STD-B67).
    /// This preserves HDR but changes the transfer function for broadcast compatibility.
    /// Uses a zscale filter chain: PQ input → linear → HLG output, keeping BT.2020 colour.
    public var convertPQToHLG: Bool = false

    // MARK: - HDR Metadata Injection (Issue #43, #245)

    /// Whether to inject HDR10 static metadata into the output stream.
    /// When true and the source has MDCV/CLL metadata, these are signalled in the
    /// output via codec-specific parameters (-x265-params for HEVC, side data for AV1).
    public var preserveHDRMetadata: Bool = true

    /// Mastering display colour volume: display primaries as G(x,y)B(x,y)R(x,y)WP(x,y)
    /// in CIE 1931 coordinates multiplied by 50000 (SMPTE ST 2086).
    /// Format: "G(gx,gy)B(bx,by)R(rx,ry)WP(wpx,wpy)L(max,min)"
    /// Example: "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
    public var masteringDisplay: String?

    /// Maximum Content Light Level in nits (MaxCLL).
    public var maxCLL: Int?

    /// Maximum Frame-Average Light Level in nits (MaxFALL).
    public var maxFALL: Int?

    /// Whether to use hardware encoding (VideoToolbox on macOS).
    public var useHardwareEncoding: Bool = false

    /// Keyframe interval in seconds (for adaptive streaming GOP alignment).
    public var keyframeInterval: Double?

    /// Number of encoding passes (1 or 2).
    public var encodingPasses: Int = 1

    /// Path to the multipass log file (for two-pass encoding).
    public var multipassLogPath: String?

    /// Current pass number (1 or 2) when doing multi-pass encoding.
    public var currentPass: Int?

    // MARK: - Audio Settings

    /// The audio codec to use for encoding. Nil means copy (passthrough).
    public var audioCodec: AudioCodec?

    /// Whether to passthrough (copy) the audio stream without re-encoding.
    public var audioPassthrough: Bool = false

    /// Audio bitrate in bits per second.
    public var audioBitrate: Int?

    /// Audio sample rate in Hz (e.g., 44100, 48000). Nil means match source.
    public var audioSampleRate: Int?

    /// Number of audio channels. Nil means match source.
    public var audioChannels: Int?

    /// Audio channel layout string (e.g., "stereo", "5.1").
    public var audioChannelLayout: String?

    // MARK: - Subtitle Settings

    /// Whether to passthrough (copy) subtitle streams.
    public var subtitlePassthrough: Bool = false

    /// Whether to disable all subtitle streams in output.
    public var disableSubtitles: Bool = false

    // MARK: - Per-Stream Audio Settings (Phase 3.2 / Issue #38)

    /// Per-stream audio codec overrides, keyed by output audio stream index.
    /// When set, these take precedence over the global `audioCodec` for the
    /// corresponding stream. Enables multi-codec audio output (e.g., AAC default + TrueHD).
    public var perStreamAudioCodec: [Int: AudioCodec] = [:]

    /// Per-stream audio bitrate overrides.
    public var perStreamAudioBitrate: [Int: Int] = [:]

    // MARK: - Per-Stream Video Settings (Phase 3.5 / Issue #41)

    /// Per-stream video codec overrides, keyed by output video stream index.
    public var perStreamVideoCodec: [Int: VideoCodec] = [:]

    /// Per-stream video passthrough flags.
    public var perStreamVideoPassthrough: [Int: Bool] = [:]

    /// Per-stream video CRF overrides.
    public var perStreamVideoCRF: [Int: Int] = [:]

    /// Per-stream video bitrate overrides.
    public var perStreamVideoBitrate: [Int: Int] = [:]

    /// Per-stream video preset overrides.
    public var perStreamVideoPreset: [Int: String] = [:]

    // MARK: - Stream Selection

    /// Specific video stream index to use from source. Nil means default.
    public var videoStreamIndex: Int?

    /// Specific audio stream index to use from source. Nil means default.
    public var audioStreamIndex: Int?

    /// Specific subtitle stream index to use. Nil means default.
    public var subtitleStreamIndex: Int?

    /// Whether to map all streams from source (not just default).
    public var mapAllStreams: Bool = false

    // MARK: - Container / Output

    /// Output container format. Inferred from output extension if nil.
    public var containerFormat: ContainerFormat?

    /// Whether to overwrite existing output file without prompting.
    /// Always true in MeedyaConverter (we handle confirmation in the UI).
    public var overwriteOutput: Bool = true

    /// Whether to copy all metadata from the source file to the output.
    /// Enabled by default so passthrough preserves track names, language tags,
    /// and all other stream/container metadata unless overridden in the UI.
    public var copySourceMetadata: Bool = true

    // MARK: - Metadata

    /// Metadata key-value pairs to write to the output file.
    public var metadata: [String: String] = [:]

    /// Per-stream metadata (keyed by stream specifier like "s:a:0").
    public var streamMetadata: [String: [String: String]] = [:]

    // MARK: - Filters

    /// Video filter chain string (e.g., "scale=1920:1080,tonemap=hable").
    public var videoFilterChain: String?

    /// Audio filter chain string (e.g., "loudnorm=I=-14").
    public var audioFilterChain: String?

    // MARK: - Stream Disposition (Phase 3.11 / TrueHD-in-MP4)

    /// Per-stream disposition overrides.
    /// Key is the stream specifier (e.g., "a:0", "a:1"), value is the disposition
    /// string (e.g., "default", "0" to clear default).
    /// Used to enforce non-default TrueHD in MP4 containers.
    public var streamDispositions: [String: String] = [:]

    // MARK: - Codec Metadata Preservation (Phase 3.16a)

    /// Preserve codec-specific metadata when re-encoding within the same codec family.
    /// When true and the source/output audio codecs match, dialog normalization,
    /// dynamic range, surround mode flags, etc. are carried through.
    public var preserveCodecMetadata: Bool = true

    // MARK: - Aspect Ratio (Phase 3.16b)

    /// Display Aspect Ratio override (e.g., "16:9", "2.35:1").
    /// When set, applies -aspect to the output. When nil, aspect is copied from source.
    public var displayAspectRatio: String?

    // MARK: - Additional Arguments

    /// Extra FFmpeg arguments to append (for advanced use cases).
    public var extraArguments: [String] = []

    // MARK: - Initialiser

    public init() {}

    // MARK: - Build

    /// Build the complete FFmpeg argument array.
    ///
    /// Returns the arguments to pass to FFmpeg (not including the binary path itself).
    /// Arguments are ordered: global options → inputs → codec/quality → filters → output.
    public func build() -> [String] {
        var args: [String] = []

        // --- Global options ---
        if overwriteOutput {
            args.append("-y")
        }

        // Suppress interactive prompts
        args.append("-nostdin")

        // --- Input files ---
        if let input = inputURL {
            args.append(contentsOf: ["-i", input.path])
        }

        for additionalInput in additionalInputs {
            args.append(contentsOf: ["-i", additionalInput.path])
        }

        // --- Stream mapping ---
        args.append(contentsOf: buildStreamMapping())

        // --- Source metadata passthrough ---
        // Copy all metadata (track names, language, title, etc.) and chapters
        // from the source file by default. Per-stream overrides from the UI
        // are applied separately via buildMetadataArguments().
        if copySourceMetadata {
            args.append(contentsOf: ["-map_metadata", "0"])
            args.append(contentsOf: ["-map_chapters", "0"])
        }

        // --- Video codec and quality ---
        args.append(contentsOf: buildVideoArguments())

        // --- Audio codec and quality ---
        args.append(contentsOf: buildAudioArguments())

        // --- Subtitle handling ---
        args.append(contentsOf: buildSubtitleArguments())

        // --- Video filters ---
        // Build the complete video filter chain: user filters + tone mapping
        let vfChain = buildVideoFilterChain()
        if !vfChain.isEmpty {
            args.append(contentsOf: ["-vf", vfChain])
        }

        // --- Audio filters ---
        if let af = audioFilterChain, !af.isEmpty {
            args.append(contentsOf: ["-af", af])
        }

        // --- Display aspect ratio override ---
        if let dar = displayAspectRatio, !dar.isEmpty {
            args.append(contentsOf: ["-aspect", dar])
        }

        // --- Stream disposition (TrueHD non-default enforcement) ---
        args.append(contentsOf: buildDispositionArguments())

        // --- Metadata ---
        args.append(contentsOf: buildMetadataArguments())

        // --- Container format override ---
        if let format = containerFormat {
            args.append(contentsOf: ["-f", ffmpegFormatName(for: format)])
        }

        // --- Container-specific muxing flags ---
        args.append(contentsOf: buildContainerFlags())

        // --- Extra arguments ---
        args.append(contentsOf: extraArguments)

        // --- Output file ---
        if let output = outputURL {
            // For two-pass first pass, output to /dev/null
            if encodingPasses == 2 && currentPass == 1 {
                args.append("/dev/null")
            } else {
                args.append(output.path)
            }
        }

        return args
    }

    // MARK: - Video Filter Chain

    /// Build the complete video filter chain combining user filters and tone mapping.
    private func buildVideoFilterChain() -> String {
        var filters: [String] = []

        // User-specified video filter chain (crop, scale, etc.)
        if let vf = videoFilterChain, !vf.isEmpty {
            filters.append(vf)
        }

        // HDR → SDR tone mapping filter (Phase 3.9b)
        if toneMap && !videoPassthrough {
            filters.append(buildToneMapFilter())
        }

        // PQ → HLG transfer function conversion (Issue #254)
        // Mutually exclusive with tone mapping — PQ→HLG keeps HDR, tone mapping goes to SDR.
        if convertPQToHLG && !toneMap && !videoPassthrough {
            filters.append(buildPQToHLGFilter())
        }

        return filters.joined(separator: ",")
    }

    /// Build the zscale/tonemap filter chain for HDR → SDR conversion.
    ///
    /// Uses zscale for colour space conversion (BT.2020 → BT.709) and
    /// tonemap for dynamic range compression (PQ/HLG → SDR).
    ///
    /// Pipeline: zscale(transfer=linear) → tonemap → zscale(BT.709) → format(yuv420p)
    private func buildToneMapFilter() -> String {
        var parts: [String] = []

        // Step 1: Convert to linear light for tone mapping
        parts.append("zscale=t=linear:npl=100")

        // Step 2: Apply tone mapping algorithm
        var tonemapArgs = "tonemap=\(toneMapAlgorithm.rawValue)"
        if let peak = toneMapPeakNits {
            tonemapArgs += ":peak=\(peak / 10000.0)" // FFmpeg expects normalised (0-1)
        }
        if let desat = toneMapDesaturation {
            tonemapArgs += ":desat=\(desat)"
        }
        parts.append(tonemapArgs)

        // Step 3: Convert to BT.709 colour space
        parts.append("zscale=p=bt709:t=bt709:m=bt709:r=tv")

        // Step 4: Convert to 8-bit output
        parts.append("format=yuv420p")

        return parts.joined(separator: ",")
    }

    /// Build the zscale filter chain for PQ → HLG transfer function conversion.
    ///
    /// Converts PQ (SMPTE ST 2084) transfer to HLG (ARIB STD-B67) while preserving
    /// BT.2020 wide colour gamut and 10-bit depth. Used for broadcast delivery where
    /// HLG is required but the source was mastered in PQ.
    ///
    /// Pipeline: zscale(PQ→linear) → zscale(linear→HLG, BT.2020 preserved) → format(10-bit)
    private func buildPQToHLGFilter() -> String {
        var parts: [String] = []

        // Step 1: Convert from PQ to linear light
        parts.append("zscale=tin=smpte2084:t=linear:pin=bt2020:p=bt2020:min=bt2020nc:m=bt2020nc")

        // Step 2: Convert from linear to HLG transfer, keep BT.2020 colour space
        parts.append("zscale=t=arib-std-b67:p=bt2020:m=bt2020nc")

        // Step 3: Ensure 10-bit YUV 4:2:0 output for HLG
        parts.append("format=yuv420p10le")

        return parts.joined(separator: ",")
    }

    // MARK: - Private Builders

    /// Build stream mapping arguments (-map).
    private func buildStreamMapping() -> [String] {
        var args: [String] = []

        if mapAllStreams {
            // Map all streams from first input
            args.append(contentsOf: ["-map", "0"])
        } else {
            // Map specific streams
            if let vi = videoStreamIndex {
                args.append(contentsOf: ["-map", "0:v:\(vi)"])
            } else if !disableSubtitles {
                // Default: map first video and first audio
                args.append(contentsOf: ["-map", "0:v?"])
            }

            if let ai = audioStreamIndex {
                args.append(contentsOf: ["-map", "0:a:\(ai)"])
            } else {
                args.append(contentsOf: ["-map", "0:a?"])
            }

            if subtitlePassthrough {
                if let si = subtitleStreamIndex {
                    args.append(contentsOf: ["-map", "0:s:\(si)"])
                } else {
                    args.append(contentsOf: ["-map", "0:s?"])
                }
            }
        }

        return args
    }

    /// Build video codec and quality arguments.
    ///
    /// Supports two modes:
    /// 1. **Global**: Single video codec for all streams (default).
    /// 2. **Per-stream**: Different codecs per output video stream via `perStreamVideoCodec`.
    ///    Uses FFmpeg stream specifier syntax (-c:v:0, -c:v:1, etc.).
    private func buildVideoArguments() -> [String] {
        var args: [String] = []

        // Per-stream video codec overrides (Phase 3.5 / Issue #41)
        // FFmpeg supports per-stream codec selection via -c:v:N but some options
        // (CRF, preset) are global encoder options that don't accept stream specifiers.
        // For per-stream quality/preset, we apply the first override's values globally
        // since FFmpeg uses one encoder instance per codec type.
        if !perStreamVideoCodec.isEmpty || !perStreamVideoPassthrough.isEmpty {
            for (index, isPassthrough) in perStreamVideoPassthrough.sorted(by: { $0.key < $1.key }) {
                if isPassthrough {
                    args.append(contentsOf: ["-c:v:\(index)", "copy"])
                }
            }
            for (index, codec) in perStreamVideoCodec.sorted(by: { $0.key < $1.key }) {
                guard perStreamVideoPassthrough[index] != true else { continue }
                if let encoderName = codec.ffmpegEncoder {
                    args.append(contentsOf: ["-c:v:\(index)", encoderName])
                }
                if let br = perStreamVideoBitrate[index] {
                    args.append(contentsOf: ["-b:v:\(index)", formatBitrate(br)])
                }
            }
            // Apply CRF and preset from the first video override (global encoder options)
            if let firstCRF = perStreamVideoCRF.sorted(by: { $0.key < $1.key }).first?.value {
                args.append(contentsOf: ["-crf", "\(firstCRF)"])
            }
            if let firstPreset = perStreamVideoPreset.sorted(by: { $0.key < $1.key }).first?.value {
                args.append(contentsOf: ["-preset", firstPreset])
            }
            // Apply global codec for streams without per-stream overrides
            if videoPassthrough {
                // Only if no per-stream codec overrides set the global default to copy
                let overriddenIndices = Set(perStreamVideoCodec.keys).union(Set(perStreamVideoPassthrough.keys))
                if overriddenIndices.isEmpty {
                    args.append(contentsOf: ["-c:v", "copy"])
                }
            }
            return args
        }

        if videoPassthrough {
            // Passthrough — copy video without re-encoding
            args.append(contentsOf: ["-c:v", "copy"])
            return args
        }

        guard let codec = videoCodec else {
            // No video codec specified and not passthrough — disable video
            args.append("-vn")
            return args
        }

        // Select encoder
        let encoderName: String
        if useHardwareEncoding && codec.supportsVideoToolbox {
            // Use VideoToolbox hardware encoder
            switch codec {
            case .h264: encoderName = "h264_videotoolbox"
            case .h265: encoderName = "hevc_videotoolbox"
            case .prores: encoderName = "prores_videotoolbox"
            case .av1: encoderName = "av1_videotoolbox"
            default: encoderName = codec.ffmpegEncoder ?? "libx264"
            }
        } else {
            encoderName = codec.ffmpegEncoder ?? "libx264"
        }

        args.append(contentsOf: ["-c:v", encoderName])

        // Quality settings
        if let crf = videoCRF, !useHardwareEncoding {
            // CRF mode (software encoders)
            args.append(contentsOf: ["-crf", "\(crf)"])
        } else if let qp = videoQP ?? videoCRF, useHardwareEncoding {
            // QP mode (hardware encoders)
            args.append(contentsOf: ["-q:v", "\(qp)"])
        }

        if let bitrate = videoBitrate {
            args.append(contentsOf: ["-b:v", formatBitrate(bitrate)])
        }

        if let maxBr = videoMaxBitrate {
            args.append(contentsOf: ["-maxrate", formatBitrate(maxBr)])
        }

        if let bufSize = videoBufferSize {
            args.append(contentsOf: ["-bufsize", formatBitrate(bufSize)])
        }

        // Resolution
        if let w = videoWidth, let h = videoHeight {
            args.append(contentsOf: ["-s", "\(w)x\(h)"])
        }

        // Frame rate
        if let fps = videoFrameRate {
            args.append(contentsOf: ["-r", String(format: "%.3f", fps)])
        }

        // Pixel format
        if let pf = pixelFormat {
            args.append(contentsOf: ["-pix_fmt", pf])
        }

        // Encoder preset
        if let preset = videoPreset {
            args.append(contentsOf: ["-preset", preset])
        }

        // Encoder tune
        if let tune = videoTune {
            args.append(contentsOf: ["-tune", tune])
        }

        // Encoder profile
        if let profile = videoProfile {
            args.append(contentsOf: ["-profile:v", profile])
        }

        // Encoder level
        if let level = videoLevel {
            args.append(contentsOf: ["-level", level])
        }

        // Keyframe interval (GOP size for adaptive streaming)
        if let kfInterval = keyframeInterval, let fps = videoFrameRate {
            let gopSize = Int(kfInterval * fps)
            args.append(contentsOf: ["-g", "\(gopSize)"])
            args.append(contentsOf: ["-keyint_min", "\(gopSize)"])
        }

        // HDR10 metadata injection (Phase 3.7 / Issue #43, #245)
        // When preserving HDR and the source has mastering display / content light level
        // metadata, inject it into the output via codec-specific mechanisms.
        if preserveHDRMetadata && !toneMap && !convertPQToHLG {
            args.append(contentsOf: buildHDR10MetadataArguments(codec: codec))
        }

        // Two-pass encoding
        if encodingPasses == 2 {
            args.append(contentsOf: ["-pass", "\(currentPass ?? 1)"])
            if let logPath = multipassLogPath {
                args.append(contentsOf: ["-passlogfile", logPath])
            }
            // First pass: disable audio, use fast analysis
            if currentPass == 1 {
                args.append("-an")
            }
        }

        return args
    }

    /// Build HDR10 static metadata injection arguments.
    ///
    /// For HEVC (x265): uses `-x265-params` to set mastering display and CLL.
    /// For AV1 (SVT-AV1): uses `--enable-hdr` and related parameters.
    /// For other codecs: uses FFmpeg's generic `-master_display` and `-max_muxing_queue_size`.
    ///
    /// HDR10 requires:
    /// - Colour primaries: BT.2020
    /// - Transfer characteristics: SMPTE ST 2084 (PQ)
    /// - Matrix coefficients: BT.2020 NCL
    /// - Mastering Display Colour Volume (MDCV) — SMPTE ST 2086
    /// - Content Light Level (CLL) — MaxCLL + MaxFALL
    private func buildHDR10MetadataArguments(codec: VideoCodec) -> [String] {
        var args: [String] = []

        // Colour signalling — always needed for HDR output
        args.append(contentsOf: ["-color_primaries", "bt2020"])
        args.append(contentsOf: ["-color_trc", "smpte2084"])
        args.append(contentsOf: ["-colorspace", "bt2020nc"])

        let hasMDCV = masteringDisplay != nil
        let hasCLL = maxCLL != nil || maxFALL != nil
        guard hasMDCV || hasCLL else { return args }

        switch codec {
        case .h265:
            // x265 uses its own parameter syntax for HDR10 metadata
            var x265Params: [String] = []

            // Always signal HDR10 mode
            x265Params.append("hdr10-opt=1")
            x265Params.append("repeat-headers=1")

            if let md = masteringDisplay {
                // x265 format: G(gx,gy)B(bx,by)R(rx,ry)WP(wpx,wpy)L(max,min)
                x265Params.append("master-display=\(md)")
            }

            if let cll = maxCLL, let fall = maxFALL {
                x265Params.append("max-cll=\(cll),\(fall)")
            } else if let cll = maxCLL {
                x265Params.append("max-cll=\(cll),0")
            }

            if !x265Params.isEmpty {
                args.append(contentsOf: ["-x265-params", x265Params.joined(separator: ":")])
            }

        case .av1:
            // SVT-AV1 uses --enable-hdr and chroma-sample-position
            // Metadata is passed via FFmpeg side data
            if let md = masteringDisplay {
                args.append(contentsOf: ["-master_display", md])
            }
            if let cll = maxCLL, let fall = maxFALL {
                args.append(contentsOf: ["-max_muxing_queue_size", "9999"])
                args.append(contentsOf: ["-content_light", "\(cll),\(fall)"])
            }

        default:
            // Generic FFmpeg metadata for other codecs (VP9, etc.)
            if let md = masteringDisplay {
                args.append(contentsOf: ["-master_display", md])
            }
            if let cll = maxCLL, let fall = maxFALL {
                args.append(contentsOf: ["-content_light", "\(cll),\(fall)"])
            }
        }

        return args
    }

    /// Build audio codec and quality arguments.
    ///
    /// Supports two modes:
    /// 1. **Global**: Single audio codec for all streams (default).
    /// 2. **Per-stream**: Different codecs per output audio stream via `perStreamAudioCodec`.
    ///    Used for multi-codec scenarios like TrueHD + AAC fallback in MP4.
    private func buildAudioArguments() -> [String] {
        var args: [String] = []

        // Skip audio in first pass of two-pass encoding
        if encodingPasses == 2 && currentPass == 1 {
            return ["-an"]
        }

        // Per-stream audio codec overrides
        if !perStreamAudioCodec.isEmpty {
            for (index, codec) in perStreamAudioCodec.sorted(by: { $0.key < $1.key }) {
                if let encoderName = codec.ffmpegEncoder {
                    args.append(contentsOf: ["-c:a:\(index)", encoderName])
                } else {
                    args.append(contentsOf: ["-c:a:\(index)", "copy"])
                }
                if let br = perStreamAudioBitrate[index] {
                    args.append(contentsOf: ["-b:a:\(index)", formatBitrate(br)])
                }
            }
            return args
        }

        // Global audio settings
        if audioPassthrough {
            args.append(contentsOf: ["-c:a", "copy"])
            return args
        }

        guard let codec = audioCodec else {
            // No audio codec specified — disable audio
            args.append("-an")
            return args
        }

        // Select encoder
        guard let encoderName = codec.ffmpegEncoder else {
            // Codec cannot be encoded by FFmpeg — fall back to passthrough
            args.append(contentsOf: ["-c:a", "copy"])
            return args
        }

        args.append(contentsOf: ["-c:a", encoderName])

        // Bitrate
        if let br = audioBitrate {
            args.append(contentsOf: ["-b:a", formatBitrate(br)])
        }

        // Sample rate
        if let sr = audioSampleRate {
            args.append(contentsOf: ["-ar", "\(sr)"])
        }

        // Channel count
        if let ch = audioChannels {
            args.append(contentsOf: ["-ac", "\(ch)"])
        }

        // Channel layout
        if let layout = audioChannelLayout {
            args.append(contentsOf: ["-channel_layout", layout])
        }

        return args
    }

    /// Build subtitle handling arguments.
    private func buildSubtitleArguments() -> [String] {
        if disableSubtitles {
            return ["-sn"]
        }

        if subtitlePassthrough {
            return ["-c:s", "copy"]
        }

        // Default: no subtitle processing (subtitles from mapping will be copied if compatible)
        return []
    }

    /// Build stream disposition arguments.
    /// Used to enforce non-default flags for codecs that require it in certain containers
    /// (e.g., TrueHD in MP4 must not be default).
    private func buildDispositionArguments() -> [String] {
        var args: [String] = []
        for (streamSpec, disposition) in streamDispositions {
            args.append(contentsOf: ["-disposition:\(streamSpec)", disposition])
        }
        return args
    }

    /// Build metadata arguments.
    private func buildMetadataArguments() -> [String] {
        var args: [String] = []

        // File-level metadata
        for (key, value) in metadata {
            args.append(contentsOf: ["-metadata", "\(key)=\(value)"])
        }

        // Per-stream metadata
        for (streamSpec, tags) in streamMetadata {
            for (key, value) in tags {
                args.append(contentsOf: ["-metadata:\(streamSpec)", "\(key)=\(value)"])
            }
        }

        return args
    }

    // MARK: - Helpers

    /// Format a bitrate integer into FFmpeg's string format (e.g., 160000 → "160k").
    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return "\(bps / 1_000_000)M"
        } else if bps >= 1000 {
            return "\(bps / 1000)k"
        }
        return "\(bps)"
    }

    /// Get the FFmpeg format name for a container format.
    /// Delegates to ContainerFormat.ffmpegFormatName to avoid duplication.
    private func ffmpegFormatName(for container: ContainerFormat) -> String {
        container.ffmpegFormatName
    }

    // MARK: - Container-Specific Flags (Phase 3.11)

    /// Build container-specific muxing flags.
    ///
    /// Different containers require special FFmpeg muxer options:
    /// - MP4/M4V/MOV: `-movflags +faststart` moves the moov atom to the front
    ///   for progressive web playback (no need to download entire file first).
    /// - MPEG-TS: PCR and PAT/PMT intervals for broadcast compliance.
    /// - MKV: cluster size hint for better seeking.
    private func buildContainerFlags() -> [String] {
        let format = resolveContainerFormat()
        guard let format else { return [] }

        var args: [String] = []

        switch format {
        case .mp4, .m4v, .m4a, .m4b, .m4p, .mov:
            // Move moov atom to start for progressive download / web streaming.
            // Without this, players must download the entire file before playback.
            args.append(contentsOf: ["-movflags", "+faststart"])

        case .mpegTS:
            // Set PAT/PMT period for broadcast compliance and better random access.
            args.append(contentsOf: ["-mpegts_flags", "+resend_headers"])

        default:
            break
        }

        return args
    }

    /// Resolve the effective container format from explicit setting or output extension.
    private func resolveContainerFormat() -> ContainerFormat? {
        if let format = containerFormat { return format }
        guard let ext = outputURL?.pathExtension else { return nil }
        return ContainerFormat.from(fileExtension: ext)
    }

    // MARK: - HLG Metadata Preservation (Issue #245)

    /// Build FFmpeg arguments to preserve HLG HDR metadata in the output.
    ///
    /// When the source has HLG transfer characteristics and the output codec/container
    /// supports HDR, these arguments ensure the colour metadata is correctly signalled:
    /// - colour_primaries=9 (BT.2020)
    /// - transfer_characteristics=18 (ARIB STD-B67 / HLG)
    /// - matrix_coefficients=9 (BT.2020 non-constant luminance)
    ///
    /// Call this method and append the result when encoding HLG content without
    /// tone mapping or transfer function conversion.
    public func buildHLGPreservationArguments() -> [String] {
        guard !toneMap, !convertPQToHLG, !videoPassthrough else { return [] }
        return [
            "-color_primaries", "bt2020",
            "-color_trc", "arib-std-b67",
            "-colorspace", "bt2020nc",
        ]
    }

    /// Build FFmpeg arguments to preserve HDR10/PQ metadata in the output.
    public func buildPQPreservationArguments() -> [String] {
        guard !toneMap, !convertPQToHLG, !videoPassthrough else { return [] }
        return [
            "-color_primaries", "bt2020",
            "-color_trc", "smpte2084",
            "-colorspace", "bt2020nc",
        ]
    }

    // MARK: - TrueHD Disposition Enforcement (Issue #253)

    /// Automatically set stream dispositions when TrueHD is used in MP4-family containers.
    ///
    /// When TrueHD audio is present in an MP4 output, it MUST NOT be the default stream.
    /// A compatible fallback codec (AAC, AC-3, E-AC-3) must be present and set as default.
    ///
    /// - Parameters:
    ///   - audioStreams: The audio streams being included in the output.
    ///   - container: The target container format.
    /// - Returns: Disposition arguments to append.
    public static func buildTrueHDDispositionArguments(
        audioStreams: [(index: Int, codec: AudioCodec)],
        container: ContainerFormat
    ) -> [String] {
        guard container.requiresNonDefault(.trueHD) else { return [] }

        let hasTrueHD = audioStreams.contains { $0.codec == .trueHD }
        guard hasTrueHD else { return [] }

        var args: [String] = []
        var defaultSet = false

        for stream in audioStreams {
            let spec = "a:\(stream.index)"
            if stream.codec == .trueHD {
                // TrueHD must not be default in MP4
                args.append(contentsOf: ["-disposition:\(spec)", "0"])
            } else if !defaultSet {
                // First non-TrueHD stream becomes the default
                args.append(contentsOf: ["-disposition:\(spec)", "default"])
                defaultSet = true
            }
        }

        return args
    }

    // MARK: - PCM Format Selection (Issue #49)

    /// Map a PCM bit depth to the appropriate FFmpeg PCM encoder name.
    ///
    /// - Parameter bitDepth: The desired bit depth (16, 24, 32, or 64).
    /// - Parameter floatingPoint: Whether to use floating-point PCM.
    /// - Returns: The FFmpeg encoder name string.
    public static func pcmEncoderName(bitDepth: Int = 16, floatingPoint: Bool = false) -> String {
        if floatingPoint {
            switch bitDepth {
            case 64: return "pcm_f64le"
            default: return "pcm_f32le"
            }
        }
        switch bitDepth {
        case 24: return "pcm_s24le"
        case 32: return "pcm_s32le"
        default: return "pcm_s16le"
        }
    }

    // MARK: - ProRes Profile Selection (Issue #48)

    /// Map a ProRes profile name to the FFmpeg -profile:v value.
    ///
    /// ProRes profiles from lowest to highest quality:
    /// - Proxy (0): Offline editing, ~45 Mbps at 1080p
    /// - LT (1): Light editing, ~100 Mbps at 1080p
    /// - Standard (2): Standard quality, ~150 Mbps at 1080p
    /// - HQ (3): High quality mastering, ~220 Mbps at 1080p
    /// - 4444 (4): Highest quality with alpha channel support
    /// - 4444 XQ (5): Extended quality 4444 with higher data rate
    public static func proresProfileValue(for profileName: String) -> Int? {
        switch profileName.lowercased() {
        case "proxy": return 0
        case "lt": return 1
        case "standard": return 2
        case "hq": return 3
        case "4444": return 4
        case "4444xq", "4444 xq": return 5
        default: return nil
        }
    }

    // MARK: - DNxHR Profile Selection (Issue #48)

    /// Map a DNxHR profile name to the FFmpeg -profile:v value.
    public static func dnxhrProfileValue(for profileName: String) -> String? {
        switch profileName.lowercased() {
        case "lb": return "dnxhr_lb"
        case "sq": return "dnxhr_sq"
        case "hq": return "dnxhr_hq"
        case "hqx": return "dnxhr_hqx"
        case "444": return "dnxhr_444"
        default: return nil
        }
    }
}
