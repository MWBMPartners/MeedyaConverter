// ============================================================================
// MeedyaConverter — CueSheetWriter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CueSheetWriter

/// Serializes a `DiscTableOfContents` into a full-fidelity CUE sheet
/// describing a raw BIN/CUE disc image.
///
/// This is distinct from `AudioDiscFidelity.generateCuesheet(toc:audioFileName:)`,
/// which produces a lightweight CUE sidecar for embedding into a *single
/// ripped audio file* (`FILE "..." WAVE`). `CueSheetWriter` instead targets
/// a **raw binary disc image** (`FILE "..." BINARY`) and preserves the full
/// set of Red Book / Yellow Book track metadata needed to describe the
/// image byte-for-byte: track mode (audio vs. which data sub-mode), ISRC
/// codes, the media catalog number, CD-TEXT at both the disc and track
/// level, pre-emphasis flags, and pregap/index points. `generateCuesheet`
/// is untouched by this type and continues to serve its existing callers.
///
/// ## CUE sheet directive reference
///
/// - `CATALOG <13 digits>` — Media Catalog Number (UPC/EAN), disc-wide.
/// - `TITLE` / `PERFORMER` / `SONGWRITER` — CD-TEXT packs. Valid at the
///   disc level (written before the first `FILE`) and, separately, at the
///   track level (written inside a `TRACK` block).
/// - `FILE "<name>" BINARY` — the raw disc image this CUE sheet describes.
///   Unlike a `WAVE`/`MP3` FILE type, `BINARY` sectors have no container
///   header of their own — the CUE sheet is the only place sector
///   boundaries and per-track modes are recorded.
/// - `TRACK NN <MODE>` — starts a new track. `MODE` is `AUDIO` for Red Book
///   CD-DA, or `MODEn/2352` for a raw Yellow Book data sector (see
///   `TrackMode` for what each `MODEn` collapses from).
/// - `FLAGS PRE` — the track carries pre-emphasis and must be
///   de-emphasized on playback.
/// - `ISRC <12 chars>` — International Standard Recording Code.
/// - `PREGAP MM:SS:FF` — declares a *virtual* pregap of the given duration
///   that is **not** physically present in the binary file; a compliant
///   player or burner synthesizes silence for it. Written here (in
///   addition to the literal `INDEX 00` line below) purely for
///   compatibility with tools that expect the duration form.
/// - `INDEX 00 MM:SS:FF` — a *real* pregap: sectors that ARE physically
///   present in the binary file, immediately before the track's official
///   start.
/// - `INDEX 01 MM:SS:FF` — the track's official start position. Every
///   track has at least this one index.
/// - `INDEX 02`, `03`, … — sub-track index marks within the track body.
///
/// All positions are Minutes:Seconds:Frames (MSF) — 75 frames (sectors)
/// per second, per the Red Book specification.
public struct CueSheetWriter: Sendable {

    /// Frames (sectors) per second for MSF conversion — Red Book: 75.
    private static let framesPerSecond = 75

    /// Serialize a full CUE sheet describing `toc` against a single raw
    /// binary image file named `binaryFileName`.
    ///
    /// - Parameters:
    ///   - toc: The disc's table of contents (tracks, indexes, CD-TEXT,
    ///     catalog number).
    ///   - binaryFileName: The `.bin` file name referenced by the `FILE`
    ///     directive. Pass a bare file name (not a full path) so the
    ///     `.bin`/`.cue` pair stays portable when moved or copied together
    ///     — this matches the convention used by cdrdao, ImgBurn, and
    ///     virtually every other BIN/CUE authoring tool.
    /// - Returns: The complete CUE sheet text, `\n`-terminated per line.
    public static func write(toc: DiscTableOfContents, binaryFileName: String) -> String {
        var cue = ""

        // MARK: Disc-level header

        if let catalog = toc.catalogNumber {
            cue += "CATALOG \(catalog)\n"
        }
        if let cdText = toc.cdText {
            if let title = cdText.albumTitle {
                cue += "TITLE \"\(title)\"\n"
            }
            if let performer = cdText.albumArtist {
                cue += "PERFORMER \"\(performer)\"\n"
            }
            if let songwriter = cdText.songwriter {
                cue += "SONGWRITER \"\(songwriter)\"\n"
            }
        }

        cue += "FILE \"\(binaryFileName)\" BINARY\n"

        // MARK: Tracks

        for track in toc.tracks {
            let trackNum = String(format: "%02d", track.number)
            cue += "  TRACK \(trackNum) \(cueMode(for: track.trackMode))\n"

            if track.hasPreEmphasis {
                cue += "    FLAGS PRE\n"
            }

            if let isrc = track.isrc {
                cue += "    ISRC \(isrc)\n"
            }

            if let cdText = toc.cdText {
                if let title = cdText.trackTitles[track.number] {
                    cue += "    TITLE \"\(title)\"\n"
                }
                if let performer = cdText.trackArtists[track.number] {
                    cue += "    PERFORMER \"\(performer)\"\n"
                }
            }

            let trackIndexes = toc.indexes
                .filter { $0.trackNumber == track.number }
                .sorted { $0.indexNumber < $1.indexNumber }

            // A real (in-file) pregap is recorded as an INDEX 00 point in
            // `toc.indexes`. When one is present we also emit a PREGAP
            // duration line ahead of the index list, computed as the gap
            // between INDEX 00 and INDEX 01, for consumers that expect the
            // duration form rather than (or in addition to) INDEX 00.
            if let index0 = trackIndexes.first(where: { $0.indexNumber == 0 }) {
                let index1Sector = trackIndexes.first(where: { $0.indexNumber == 1 })?.sector
                    ?? track.startSector
                let pregapFrames = max(0, index1Sector - index0.sector)
                cue += "    PREGAP \(framesToMSF(pregapFrames))\n"
            }

            if trackIndexes.isEmpty {
                // No explicit indexes recorded for this track — INDEX 01 is
                // implied by the track's start sector, mirroring the
                // fallback in AudioDiscFidelity.generateCuesheet.
                cue += "    INDEX 01 \(framesToMSF(track.startSector))\n"
            } else {
                for index in trackIndexes {
                    let indexNum = String(format: "%02d", index.indexNumber)
                    cue += "    INDEX \(indexNum) \(framesToMSF(index.sector))\n"
                }
            }
        }

        return cue
    }

    /// Map a `TrackMode` to its CUE `TRACK NN <mode>` token.
    ///
    /// The CUE format's raw-sector mode tokens cannot distinguish Mode 2
    /// Form 1 from Form 2 (or an undetermined/raw Mode 2 sector) — all
    /// three collapse to `MODE2/2352` because the `.bin` stores the full
    /// 2352-byte raw sector regardless of form. Recovering the form, where
    /// it matters, requires inspecting the sector's sub-header at read
    /// time, which is out of scope for this pure-logic batch.
    private static func cueMode(for mode: TrackMode) -> String {
        switch mode {
        case .audio: return "AUDIO"
        case .mode1: return "MODE1/2352"
        case .mode2Form1, .mode2Form2, .mode2Raw: return "MODE2/2352"
        }
    }

    /// Convert a frame count — either an absolute sector position or a
    /// duration expressed in frames — to `MM:SS:FF` (75 frames/second, per
    /// Red Book).
    private static func framesToMSF(_ frames: Int) -> String {
        let minutes = frames / (framesPerSecond * 60)
        let seconds = (frames / framesPerSecond) % 60
        let remainderFrames = frames % framesPerSecond
        return String(format: "%02d:%02d:%02d", minutes, seconds, remainderFrames)
    }
}
