// ============================================================================
// MeedyaConverter — CueSheetParser
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CueSheetParser

/// Parses CUE sheet text back into a `DiscTableOfContents`.
///
/// `CueSheetParser.parse(_:)` is designed to round-trip everything
/// `CueSheetWriter.write(toc:binaryFileName:)` emits: `CATALOG`, disc- and
/// track-level CD-TEXT (`TITLE`/`PERFORMER`/`SONGWRITER`), `FILE`,
/// `TRACK`+mode, `FLAGS PRE`, `ISRC`, `PREGAP`, and `INDEX` points. It is
/// tolerant of extra whitespace and line-ending style, and silently ignores
/// directives it does not model (`REM`, `CDTEXTFILE`, `POSTGAP`, etc.) —
/// this batch is a pure-text parser with no device or file I/O.
///
/// ### Inherent CUE-format limitations reflected in the parsed result
///
/// A CUE sheet does not encode everything `DiscTableOfContents` can carry.
/// The following fields cannot be recovered from CUE text alone and are
/// therefore always defaulted on the parsed disc:
///
/// - `discType` — defaults to `"Audio CD"` (there is no CUE directive for
///   it).
/// - `cddbDiscId` / `musicBrainzDiscId` — no standard CUE directive carries
///   these; they are always `nil` after parsing.
/// - `leadOutSector` — CUE sheets have no lead-out directive; it is always
///   `0` after parsing. A caller with access to the actual `.bin` file can
///   derive the true lead-out from its size.
/// - The **last** track's `sectorCount` — a track's length is only ever
///   implied by the gap to the *next* track's `INDEX 01`, so it can be
///   computed for every track except the last. The last track's
///   `sectorCount` is `0` after parsing; a caller with the `.bin` file's
///   size can compute the true value.
///
/// Every other field `CueSheetWriter` emits — track modes, ISRC, the
/// catalog number, CD-TEXT, pre-emphasis flags, and pregap/index points —
/// round-trips exactly.
public struct CueSheetParser: Sendable {

    /// Frames (sectors) per second for MSF conversion — Red Book: 75.
    private static let framesPerSecond = 75

    /// Parse CUE sheet text into a `DiscTableOfContents`.
    ///
    /// - Parameter cue: The CUE sheet text.
    /// - Returns: The reconstructed table of contents. See the type-level
    ///   documentation for which fields cannot be recovered from CUE text
    ///   alone.
    /// - Throws: `ImagingError.malformedCueSheet` if a directive this
    ///   parser does model is present but cannot be parsed (bad `TRACK`
    ///   line, unsupported track mode, unparsable `MM:SS:FF` value, or a
    ///   track with no `INDEX` points at all).
    public static func parse(_ cue: String) throws -> DiscTableOfContents {
        var discTitle: String?
        var discPerformer: String?
        var discSongwriter: String?
        var catalog: String?

        var tracks: [DiscTrack] = []
        var allIndexes: [TrackIndex] = []
        var trackTitles: [Int: String] = [:]
        var trackArtists: [Int: String] = [:]

        // Scratch state for the track currently being parsed — valid
        // between a TRACK line and the next TRACK line (or end of input).
        var currentNumber: Int?
        var currentMode: TrackMode?
        var currentPreEmphasis = false
        var currentISRC: String?
        var currentPregapFrames: Int?
        var currentIndexEntries: [(number: Int, sector: Int)] = []

        func resetTrackScratchState() {
            currentNumber = nil
            currentMode = nil
            currentPreEmphasis = false
            currentISRC = nil
            currentPregapFrames = nil
            currentIndexEntries = []
        }

        /// Package up the in-progress track (if any) into a `DiscTrack`
        /// plus its `TrackIndex` entries, appending both to the result
        /// accumulators. A no-op when no TRACK line has been seen yet.
        func finalizeCurrentTrack() throws {
            guard let number = currentNumber, let mode = currentMode else { return }

            var entries = currentIndexEntries.sorted { $0.number < $1.number }

            // Synthesize INDEX 00 from a PREGAP duration if the sheet used
            // the virtual-pregap form without also giving a literal
            // INDEX 00 line.
            if let pregapFrames = currentPregapFrames,
               !entries.contains(where: { $0.number == 0 }) {
                let index1Sector = entries.first(where: { $0.number == 1 })?.sector ?? 0
                entries.append((number: 0, sector: max(0, index1Sector - pregapFrames)))
                entries.sort { $0.number < $1.number }
            }

            guard !entries.isEmpty else {
                throw ImagingError.malformedCueSheet(
                    "TRACK \(number) has no INDEX points"
                )
            }

            let startSector = entries.first(where: { $0.number == 1 })?.sector
                ?? entries.map(\.sector).min() ?? 0

            for entry in entries {
                allIndexes.append(TrackIndex(
                    trackNumber: number,
                    indexNumber: entry.number,
                    sector: entry.sector,
                    offsetInTrack: Double(entry.sector - startSector) / Double(framesPerSecond),
                    absoluteTime: Double(entry.sector) / Double(framesPerSecond)
                ))
            }

            tracks.append(DiscTrack(
                number: number,
                title: trackTitles[number],
                artist: trackArtists[number],
                startSector: startSector,
                isData: mode != .audio,
                hasPreEmphasis: currentPreEmphasis,
                isrc: currentISRC,
                trackMode: mode
            ))
        }

        let lines = cue.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let (keyword, remainder) = splitDirective(line)

            switch keyword.uppercased() {
            case "REM":
                continue // Free-form comment — never modeled.

            case "CATALOG":
                catalog = remainder

            case "FILE":
                continue // Binary file name is not part of the TOC model.

            case "TRACK":
                try finalizeCurrentTrack()
                resetTrackScratchState()

                let parts = remainder.split(separator: " ", maxSplits: 1)
                guard let numberPart = parts.first, let number = Int(numberPart) else {
                    throw ImagingError.malformedCueSheet("Invalid TRACK directive: \(line)")
                }
                guard parts.count > 1 else {
                    throw ImagingError.malformedCueSheet("TRACK \(number) is missing a mode")
                }
                currentNumber = number
                currentMode = try trackMode(fromCueToken: String(parts[1]))

            case "FLAGS":
                if remainder.uppercased().contains("PRE") {
                    currentPreEmphasis = true
                }

            case "ISRC":
                if currentNumber != nil {
                    currentISRC = remainder
                }

            case "TITLE":
                guard let value = extractQuoted(remainder) else { break }
                if let number = currentNumber {
                    trackTitles[number] = value
                } else {
                    discTitle = value
                }

            case "PERFORMER":
                guard let value = extractQuoted(remainder) else { break }
                if let number = currentNumber {
                    trackArtists[number] = value
                } else {
                    discPerformer = value
                }

            case "SONGWRITER":
                guard let value = extractQuoted(remainder) else { break }
                if currentNumber == nil {
                    discSongwriter = value
                }
                // A per-track SONGWRITER is valid CD-TEXT, but the current
                // model only carries a disc-level songwriter, so a
                // track-level value (rare in practice) is accepted here
                // without error but not retained.

            case "PREGAP":
                currentPregapFrames = try msfToFrames(remainder)

            case "INDEX":
                let parts = remainder.split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let indexNumber = Int(parts[0]) else {
                    throw ImagingError.malformedCueSheet("Invalid INDEX directive: \(line)")
                }
                let sector = try msfToFrames(String(parts[1]))
                currentIndexEntries.append((number: indexNumber, sector: sector))

            default:
                continue // Unsupported directive — ignored.
            }
        }

        try finalizeCurrentTrack()

        var cdText: CDTextInfo?
        if discTitle != nil || discPerformer != nil || discSongwriter != nil
            || !trackTitles.isEmpty || !trackArtists.isEmpty {
            cdText = CDTextInfo(
                albumTitle: discTitle,
                albumArtist: discPerformer,
                trackTitles: trackTitles,
                trackArtists: trackArtists,
                songwriter: discSongwriter
            )
        }

        let sortedTracks = tracks.sorted { $0.number < $1.number }
        return DiscTableOfContents(
            tracks: sortedTracks,
            indexes: allIndexes,
            firstTrackNumber: sortedTracks.first?.number ?? 1,
            lastTrackNumber: sortedTracks.last?.number ?? 0,
            catalogNumber: catalog,
            cdText: cdText
        )
    }

    // MARK: - Line tokenizing helpers

    /// Split a trimmed CUE line into its leading directive keyword and the
    /// (trimmed) remainder of the line.
    private static func splitDirective(_ line: String) -> (keyword: String, remainder: String) {
        guard let spaceIndex = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return (line, "")
        }
        let keyword = String(line[line.startIndex..<spaceIndex])
        let remainder = String(line[line.index(after: spaceIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (keyword, remainder)
    }

    /// Extract the text between the first pair of double quotes in `s`.
    /// Falls back to the raw (trimmed) string when no quotes are present,
    /// so bare, unquoted single-token values from lenient CUE generators
    /// still parse.
    private static func extractQuoted(_ s: String) -> String? {
        guard let first = s.firstIndex(of: "\""),
              let last = s.lastIndex(of: "\""),
              first != last else {
            return s.isEmpty ? nil : s
        }
        return String(s[s.index(after: first)..<last])
    }

    /// Map a CUE `TRACK NN <mode>` token to a `TrackMode`.
    ///
    /// `MODE2/2352` (and the less common `MODE2/2336`/`MODE2/2324`, which
    /// some generators emit for streaming/Form 2 content) cannot be
    /// distinguished as Form 1 vs. Form 2 from the CUE token alone, so they
    /// all map to `.mode2Raw` — see `TrackMode` and
    /// `CueSheetWriter.cueMode(for:)`.
    private static func trackMode(fromCueToken token: String) throws -> TrackMode {
        switch token.uppercased() {
        case "AUDIO":
            return .audio
        case "MODE1/2352", "MODE1/2048":
            return .mode1
        case "MODE2/2352", "MODE2/2336", "MODE2/2324", "MODE2/2048":
            return .mode2Raw
        default:
            throw ImagingError.malformedCueSheet("Unsupported TRACK mode: \(token)")
        }
    }

    /// Parse an `MM:SS:FF` value into an absolute frame count.
    private static func msfToFrames(_ msf: String) throws -> Int {
        let parts = msf.split(separator: ":")
        guard parts.count == 3,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]),
              let frames = Int(parts[2]) else {
            throw ImagingError.malformedCueSheet("Invalid MM:SS:FF value: \(msf)")
        }
        return minutes * 60 * framesPerSecond + seconds * framesPerSecond + frames
    }
}
