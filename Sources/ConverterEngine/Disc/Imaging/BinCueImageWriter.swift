// ============================================================================
// MeedyaConverter — BinCueImageWriter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - BinCueImageWriter

/// Pure, in-memory assembly of a BIN/CUE disc image pair.
///
/// `BinCueImageWriter` composes `SubchannelCodec` (to separate main-channel
/// sector data from any interleaved subchannel) and `CueSheetWriter` (to
/// serialize the CUE text) into the two artifacts a BIN/CUE image consists
/// of: the `.bin` file's bytes, and the `.cue` file's text. It performs no
/// device I/O and no filesystem writes — that belongs to a later batch
/// (issue #492) that wires this pure core up to an executor and actually
/// writes the files to disk. Everything here is bytes in, bytes/text out.
public struct BinCueImageWriter: Sendable {

    /// Build the `.bin` main-channel image data from raw captured sectors,
    /// splitting out any interleaved subchannel data.
    ///
    /// - Parameters:
    ///   - sectors: Concatenated raw sectors as captured from the disc
    ///     (or an existing raw image). See
    ///     `SubchannelCodec.splitRawSectors(_:hasSubchannel:)` for the
    ///     exact expected per-sector layout.
    ///   - hasSubchannel: Whether `sectors` interleaves 96 bytes of
    ///     subchannel data after every 2352-byte main-channel sector.
    /// - Returns: `bin` — the bytes that should be written to the `.bin`
    ///   file (the concatenated 2352-byte-per-sector main channel).
    ///   `subchannel` — the concatenated 96-byte-per-sector subchannel
    ///   stream, or `nil` when `hasSubchannel` is `false`. Callers that
    ///   want to preserve subchannel data write it to a separate `.sub`
    ///   sidecar file (out of scope here — no file I/O in this batch).
    /// - Throws: `ImagingError.invalidSectorDataLength` if `sectors.count`
    ///   is not an exact multiple of the expected per-sector size.
    public static func makeBin(
        fromRawSectors sectors: Data,
        hasSubchannel: Bool
    ) throws -> (bin: Data, subchannel: Data?) {
        let split = try SubchannelCodec.splitRawSectors(sectors, hasSubchannel: hasSubchannel)
        return (bin: split.main, subchannel: split.subchannel)
    }

    /// Build the CUE sheet text pairing `toc` with a `.bin` image named
    /// `binaryFileName`. A thin, discoverable wrapper over
    /// `CueSheetWriter.write(toc:binaryFileName:)` so callers assembling a
    /// full BIN/CUE pair have a single entry point for both halves.
    ///
    /// - Parameters:
    ///   - toc: The disc's table of contents.
    ///   - binaryFileName: The `.bin` file name to reference in the CUE
    ///     sheet's `FILE` directive.
    /// - Returns: The complete CUE sheet text.
    public static func makeCueSheet(toc: DiscTableOfContents, binaryFileName: String) -> String {
        CueSheetWriter.write(toc: toc, binaryFileName: binaryFileName)
    }

    /// Derive the `.cue` file name that should be paired with a given
    /// `.bin` path — same base name, `.cue` extension — matching the
    /// convention used by cdrdao, ImgBurn, and virtually every other
    /// BIN/CUE authoring tool.
    ///
    /// - Parameter binPath: A `.bin` file name or path (extension optional
    ///   — any existing extension is discarded).
    /// - Returns: The bare `.cue` file name (no directory component).
    public static func cueFileName(forBin binPath: String) -> String {
        let url = URL(fileURLWithPath: binPath)
        return url.deletingPathExtension().appendingPathExtension("cue").lastPathComponent
    }

    /// Derive a paired `(bin, cue)` file name sharing a common base name.
    ///
    /// - Parameter baseName: A file name or path with or without an
    ///   extension (e.g. `"My Album"`, `"My Album.bin"`,
    ///   `"/out/My Album.iso"`). Any existing extension is discarded and
    ///   only the final path component is used.
    /// - Returns: The bare `.bin` and `.cue` file names (no directory
    ///   component) sharing `baseName`'s stem.
    public static func pairedFileNames(baseName: String) -> (bin: String, cue: String) {
        let url = URL(fileURLWithPath: baseName)
        let stem = url.deletingPathExtension().lastPathComponent
        return (bin: "\(stem).bin", cue: "\(stem).cue")
    }
}
