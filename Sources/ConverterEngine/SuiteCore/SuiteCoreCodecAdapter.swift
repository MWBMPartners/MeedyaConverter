// ============================================================================
// MeedyaConverter — SuiteCoreCodecAdapter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Adapter that supplements FFprobe output parsing with `meedya-codecs`
// detection. When MeedyaSuite-core is linked the adapter forwards codec
// identification to the Rust crate, which provides authoritative
// classification for spatial audio formats (Dolby Atmos, Sony 360RA,
// Ambisonics), lossless codecs, and channel layouts.
//
// When SUITE_CORE is not set, the adapter falls back to a table-driven
// classifier that mirrors the meedya-codecs mapping closely enough for the
// rest of the pipeline to make format-handling decisions.
//
// GitHub Issue #372 — Integrate MeedyaSuite-core codec detection for
// format handling.
// ============================================================================

import Foundation

#if SUITE_CORE
@_implementationOnly import MeedyaCore
#endif

// MARK: - SuiteCoreCodecAdapter

public enum SuiteCoreCodecClassifier: Sendable {

    /// Looks up the descriptor for a given FFprobe codec_name string.
    /// When suite-core is linked, delegates to the Rust implementation.
    /// Otherwise, uses the built-in classification table.
    public static func classify(
        ffprobeCodecName: String,
        channelLayout: String? = nil,
        sampleFormat: String? = nil
    ) -> SuiteCoreCodecDescriptor {
        #if SUITE_CORE
        if let descriptor = MeedyaCore.classifyCodec(
            ffprobeName: ffprobeCodecName,
            channelLayout: channelLayout,
            sampleFormat: sampleFormat
        ) {
            return SuiteCoreCodecDescriptor(
                identifier: descriptor.identifier,
                displayName: descriptor.displayName,
                isLossless: descriptor.isLossless,
                isSpatial: descriptor.isSpatial,
                channelLayout: descriptor.channelLayout
            )
        }
        #endif
        return fallbackClassify(
            ffprobeCodecName: ffprobeCodecName,
            channelLayout: channelLayout,
            sampleFormat: sampleFormat
        )
    }

    /// Whether the given codec is lossless (bit-exact reconstruction).
    public static func isLossless(ffprobeCodecName: String) -> Bool {
        return classify(ffprobeCodecName: ffprobeCodecName).isLossless
    }

    /// Whether the given codec-and-layout combination carries spatial audio.
    public static func isSpatial(
        ffprobeCodecName: String,
        channelLayout: String? = nil
    ) -> Bool {
        return classify(
            ffprobeCodecName: ffprobeCodecName,
            channelLayout: channelLayout
        ).isSpatial
    }

    // MARK: Fallback table

    /// Codec identifiers that are lossless regardless of parameters.
    static let losslessCodecs: Set<String> = [
        "flac", "alac", "ape", "wavpack", "tta", "tak",
        "truehd", "mlp", "dts-hd ma", "dts_hd_ma",
        "pcm_s8", "pcm_u8", "pcm_s16le", "pcm_s16be",
        "pcm_s24le", "pcm_s24be", "pcm_s32le", "pcm_s32be",
        "pcm_f32le", "pcm_f64le",
    ]

    /// Codec identifiers that are spatial regardless of channel layout.
    static let alwaysSpatialCodecs: Set<String> = [
        "atmos", "eac3_atmos", "truehd_atmos",
        "mha1", "mhm1",            // MPEG-H 3D Audio
        "iamf",                    // Immersive Audio Model and Formats
        "dts_x", "dtsx",           // DTS:X
        "ac4_ims",                 // AC-4 Immersive Stereo
    ]

    /// Channel layout tokens that imply spatial content.
    static let spatialChannelLayouts: Set<String> = [
        "7.1.2", "7.1.4", "7.2.4", "9.1.6", "11.1",
        "5.1.2", "5.1.4",
        "tbe", "ambisonic",
    ]

    /// Human-readable display names for well-known codecs.
    static let displayNames: [String: String] = [
        "aac": "AAC",
        "ac3": "Dolby Digital (AC-3)",
        "eac3": "Dolby Digital Plus (E-AC-3)",
        "eac3_atmos": "Dolby Digital Plus with Atmos",
        "truehd": "Dolby TrueHD",
        "truehd_atmos": "Dolby TrueHD with Atmos",
        "opus": "Opus",
        "flac": "FLAC",
        "alac": "Apple Lossless (ALAC)",
        "vorbis": "Vorbis",
        "mp3": "MP3",
        "dts": "DTS",
        "dts_hd_ma": "DTS-HD Master Audio",
        "dtsx": "DTS:X",
        "mha1": "MPEG-H 3D Audio (MHA1)",
        "mhm1": "MPEG-H 3D Audio (MHM1)",
        "iamf": "IAMF Immersive",
    ]

    static func fallbackClassify(
        ffprobeCodecName: String,
        channelLayout: String?,
        sampleFormat: String?
    ) -> SuiteCoreCodecDescriptor {
        let id = ffprobeCodecName.lowercased()
        let layout = channelLayout?.lowercased()
        let layoutIsSpatial = layout.map { spatialChannelLayouts.contains($0) } ?? false
        let codecIsSpatial = alwaysSpatialCodecs.contains(id)
        let isLossless = losslessCodecs.contains(id)
        let displayName = displayNames[id] ?? ffprobeCodecName.uppercased()
        return SuiteCoreCodecDescriptor(
            identifier: id,
            displayName: displayName,
            isLossless: isLossless,
            isSpatial: codecIsSpatial || layoutIsSpatial,
            channelLayout: channelLayout
        )
    }
}
