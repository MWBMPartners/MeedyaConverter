// ============================================================================
// MeedyaConverter — SubchannelCodec
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ImagingError

/// Errors raised while building, splitting, or parsing BIN/CUE disc image
/// data. Shared across the `Disc/Imaging` pure-logic types
/// (`SubchannelCodec`, `CueSheetWriter`, `CueSheetParser`,
/// `BinCueImageWriter`).
public enum ImagingError: Error, Sendable, Equatable, LocalizedError {
    /// Raw sector data length is not an exact multiple of the expected
    /// per-sector size, so the buffer cannot be split into whole sectors.
    case invalidSectorDataLength(byteCount: Int, sectorSize: Int)

    /// A CUE sheet directive could not be parsed (unexpected token count,
    /// bad MM:SS:FF value, unsupported track mode, structural problem such
    /// as a track with no INDEX points, etc.). The associated string
    /// describes what went wrong.
    case malformedCueSheet(String)

    /// A `cdrdao` `.toc` file could not be parsed by `CdrdaoTocParser`: an
    /// unknown `TRACK` mode, an unparsable MM:SS:FF value, or a track with no
    /// FILE/SILENCE/ZERO data statement. The associated string describes what
    /// went wrong. (Additive case, issue #495 — the raw Audio CD executor.)
    case malformedCdrdaoToc(String)

    /// The requested `DiscImageFormat` is not supported by the raw Audio CD
    /// imaging executor. P1 supports only `.bin` (BIN/CUE); every other
    /// format — including the declared-but-refused `.ccd` — raises this rather
    /// than silently producing the wrong artifact. Carries the offending
    /// format. (Additive case, issue #495.)
    case unsupportedImageFormat(DiscImageFormat)

    public var errorDescription: String? {
        switch self {
        case .invalidSectorDataLength(let byteCount, let sectorSize):
            return "Raw sector data (\(byteCount) bytes) is not a multiple of "
                + "\(sectorSize) bytes per sector."
        case .malformedCueSheet(let reason):
            return "Malformed CUE sheet: \(reason)"
        case .malformedCdrdaoToc(let reason):
            return "Malformed cdrdao .toc file: \(reason)"
        case .unsupportedImageFormat(let format):
            return "The raw Audio CD imaging executor cannot emit the "
                + "\(format.displayName) format. Only BIN/CUE is supported."
        }
    }
}

// MARK: - SubchannelCodec

/// Pure byte-level operations for separating a CD's main channel data from
/// its interleaved P–W subchannel data, when a disc image was captured in
/// "raw + subchannel" mode.
///
/// ## Background
///
/// A physical CD sector, as returned by a drive's raw-read command, comes
/// back in one of two shapes:
///
/// - **2352 bytes** — just the main channel: sync pattern + header/
///   sub-header + user data + EDC/ECC for a data sector, or 2352 bytes of
///   16-bit/44.1kHz stereo PCM for an audio sector. This is what an
///   ordinary `.bin` file stores, one sector after another with no gaps.
/// - **2448 bytes** — the same 2352-byte main channel, immediately
///   followed by 96 bytes of subchannel data. The subchannel carries the
///   P (basic play/pause flag) through W (often proprietary — e.g. CD+G
///   graphics) channels. Drives and ripping tools generally hand this back
///   already **deinterleaved**: a contiguous 96-byte block per sector,
///   organized as 12 bytes per channel × 8 channels (P, Q, R, S, T, U, V,
///   W, in that order) — rather than the physically bit-interleaved form
///   the disc actually stores on the media (where each of the 96 bytes in
///   a sector holds one bit from each of the 8 channels).
///
/// This type performs the mechanical de-mux of concatenated 2448-byte raw
/// sectors into two separate streams. It does **not**:
/// - re-derive bit-interleaved subchannel data from the deinterleaved form
///   (or vice versa) — callers are expected to hand in already-deinterleaved
///   subchannel bytes, which is what every common ripping tool produces;
/// - decode any subchannel *content* — in particular, CD+G graphics packets
///   carried across the R–W channels (24-byte packets spread over 4
///   consecutive sectors' worth of R–W nibbles) are not decoded here. That
///   is tracked separately — see the `TODO(#492-G)` below — because CD+G
///   decoding is a distinct, higher-level feature built on top of the raw
///   subchannel bytes this type extracts.
///
/// All operations here are pure functions over `Data` with no device or
/// file I/O, so they are trivially `Sendable` and safe to call from any
/// isolation context, including from within `async` code without hopping
/// to an actor.
public struct SubchannelCodec: Sendable {

    /// Bytes per sector in the main channel only — the Red Book / Yellow
    /// Book raw sector size used by an ordinary `.bin` image.
    public static let mainSectorSize = 2352

    /// Bytes of subchannel data per sector (P–W, deinterleaved: 12 bytes ×
    /// 8 channels = 96 bytes).
    public static let subchannelSize = 96

    /// Bytes per sector when the main channel and subchannel are captured
    /// together as a single raw read (`mainSectorSize + subchannelSize`).
    public static let rawSectorWithSubSize = mainSectorSize + subchannelSize

    /// Split a buffer of concatenated raw sectors into the main-channel
    /// stream and, when present, the subchannel stream.
    ///
    /// - Parameters:
    ///   - data: Concatenated raw sectors, back to back with no padding
    ///     between sectors. When `hasSubchannel` is `true`, each sector
    ///     must be exactly `rawSectorWithSubSize` (2448) bytes — 2352 bytes
    ///     of main channel immediately followed by 96 bytes of
    ///     already-deinterleaved P–W subchannel. When `false`, each sector
    ///     must be exactly `mainSectorSize` (2352) bytes.
    ///   - hasSubchannel: Whether `data` interleaves subchannel data after
    ///     every main-channel sector.
    /// - Returns: A tuple of
    ///   - `main`: the concatenated 2352-byte-per-sector main channel
    ///     stream — exactly what a `.bin` file should contain.
    ///   - `subchannel`: the concatenated 96-byte-per-sector subchannel
    ///     stream, or `nil` when `hasSubchannel` is `false`.
    /// - Throws: `ImagingError.invalidSectorDataLength` if `data.count` is
    ///   not an exact multiple of the expected per-sector size for the
    ///   requested mode.
    public static func splitRawSectors(
        _ data: Data,
        hasSubchannel: Bool
    ) throws -> (main: Data, subchannel: Data?) {
        guard hasSubchannel else {
            guard data.count % mainSectorSize == 0 else {
                throw ImagingError.invalidSectorDataLength(
                    byteCount: data.count,
                    sectorSize: mainSectorSize
                )
            }
            return (data, nil)
        }

        guard data.count % rawSectorWithSubSize == 0 else {
            throw ImagingError.invalidSectorDataLength(
                byteCount: data.count,
                sectorSize: rawSectorWithSubSize
            )
        }

        let sectorCount = data.count / rawSectorWithSubSize
        var mainData = Data(capacity: sectorCount * mainSectorSize)
        var subchannelData = Data(capacity: sectorCount * subchannelSize)

        let base = data.startIndex
        for sectorIndex in 0..<sectorCount {
            let sectorStart = base + sectorIndex * rawSectorWithSubSize
            let mainEnd = sectorStart + mainSectorSize
            let subEnd = mainEnd + subchannelSize

            mainData.append(data[sectorStart..<mainEnd])
            subchannelData.append(data[mainEnd..<subEnd])
        }

        // TODO(#492-G): Decode CD+G graphics packets from the R–W
        // subchannel bytes returned here. This batch only performs the
        // mechanical main/subchannel split (pure byte de-mux, no device
        // I/O); packet-level CD+G decoding — 24-byte packets assembled from
        // the R–W nibbles of 4 consecutive sectors' subchannel data — is
        // deferred to the CD+G work tracked under issue #492-G.

        return (mainData, subchannelData)
    }
}
