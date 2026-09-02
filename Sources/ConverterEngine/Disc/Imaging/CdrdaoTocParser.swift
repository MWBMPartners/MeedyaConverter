// ============================================================================
// MeedyaConverter — CdrdaoTocParser
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CdrdaoTocParser

/// Parses a `cdrdao` `.toc` text file into the *existing*
/// `DiscTableOfContents` model — there is deliberately no parallel model. The
/// output feeds straight into the reused `CueSheetWriter`, so a
/// `.toc → DiscTableOfContents → CueSheetWriter → CueSheetParser` round-trip
/// preserves track numbers, modes, ISRC codes, the catalogue number, CD-TEXT,
/// pre-emphasis flags, and INDEX 00/01/02+ positions.
///
/// ## The `.toc` shapes accepted
///
/// This follows the emission of `cdrdao` 1.2.4 / 1.2.5 `read-toc` and
/// `read-cd`. A file looks like:
///
/// ```
/// CD_DA                              // or CD_ROM / CD_ROM_XA
/// CATALOG "1234567890123"            // optional, 13 digits, quoted
/// CD_TEXT { LANGUAGE_MAP { 0 : EN }  // optional disc-level block
///   LANGUAGE 0 { TITLE "Album" PERFORMER "Artist" SONGWRITER "…" } }
/// // Track 1                         // comments — ignored
/// TRACK AUDIO                        // or MODE1 / MODE1_RAW / MODE2… variants
/// NO COPY                            // or COPY — ignored
/// NO PRE_EMPHASIS                    // or PRE_EMPHASIS → hasPreEmphasis
/// TWO_CHANNEL_AUDIO                  // or FOUR_CHANNEL_AUDIO — accepted, not modelled
/// ISRC "GBAYE0000351"                // optional → DiscTrack.isrc
/// CD_TEXT { LANGUAGE 0 { TITLE "Track title" … } }   // optional per-track
/// FILE "Album.bin" 0 03:27:70        // data statement: start + length (MSF or #bytes)
/// SILENCE 00:02:00                   // virtual pregap (read-toc form)
/// ZERO 00:02:00                      // zero-filled data statement
/// START 00:02:00                     // offset of INDEX 01 within the track
/// INDEX 00:10:00                     // sub-index relative to INDEX 01 → INDEX 02+
/// ```
///
/// ## Sector arithmetic
///
/// Absolute LBA is accumulated across data statements in file order: `read-cd`
/// emits one shared datafile whose offset 0 is disc sector 0, so each track's
/// data begins at the running counter. `SILENCE`/`ZERO` advance the counter
/// like any other data statement (for a `read-cd` image those sectors are
/// physically present in the datafile). A track's `sectorCount` is the sum of
/// its data-statement lengths; `leadOutSector` is the final cumulative sector;
/// `startSector` is the INDEX 01 position (track data start plus any `START`
/// pregap); `duration` is `sectorCount / 75`.
///
/// The parser is tolerant of blank lines, `//` comments, CRLF line endings,
/// and single-line statements it does not model (accepted and ignored). It
/// throws `ImagingError.malformedCdrdaoToc` for an unknown `TRACK` mode, an
/// unparsable MSF value, or a `TRACK` with no data statement.
public struct CdrdaoTocParser: Sendable {

    /// Frames (sectors) per second — Red Book: 75.
    private static let framesPerSecond = 75

    /// Bytes per main-channel sector, used to convert a `#byteLength` FILE
    /// operand into a sector count.
    private static let mainSectorBytes = 2352

    /// Parse a `cdrdao` `.toc` file into a `DiscTableOfContents`.
    ///
    /// - Parameter tocText: The contents of a `.toc` file.
    /// - Returns: The reconstructed table of contents. `hasSubchannel` is not
    ///   encoded in a `.toc`, so it is left at its default `false`; callers set
    ///   it from the read plan (`RawCDImagingConfig.captureSubchannel`).
    /// - Throws: `ImagingError.malformedCdrdaoToc` on a bad `TRACK` mode, an
    ///   unparsable MSF value, or a `TRACK` with no data statement.
    public static func parse(_ tocText: String) throws -> DiscTableOfContents {
        var discType = "Audio CD"
        var catalog: String?

        // Disc- and track-level CD-TEXT accumulators.
        var albumTitle: String?
        var albumArtist: String?
        var songwriter: String?
        var trackTitles: [Int: String] = [:]
        var trackArtists: [Int: String] = [:]

        var tracks: [DiscTrack] = []
        var indexes: [TrackIndex] = []

        // Running absolute sector position across all data statements.
        var currentLBA = 0

        // Per-track scratch state, valid between one TRACK line and the next.
        var curNumber: Int?
        var curMode: TrackMode?
        var curPreEmphasis = false
        var curISRC: String?
        var curTrackStartLBA = 0
        var curDataSectors = 0
        var curStartFrames = 0
        var curLeadingSilence = 0
        var curSawFileData = false
        var curSubIndexFrames: [Int] = []
        var curSawData = false

        // CD-TEXT brace tracking. `cdTextDepth > 0` means we are inside a
        // CD_TEXT { … } block and TITLE/PERFORMER/SONGWRITER lines are
        // metadata rather than (nonexistent) top-level directives.
        var cdTextDepth = 0

        func resetTrackScratch() {
            curNumber = nil
            curMode = nil
            curPreEmphasis = false
            curISRC = nil
            curTrackStartLBA = 0
            curDataSectors = 0
            curStartFrames = 0
            curLeadingSilence = 0
            curSawFileData = false
            curSubIndexFrames = []
            curSawData = false
        }

        func finalizeTrack() throws {
            guard let number = curNumber, let mode = curMode else { return }
            guard curSawData else {
                throw ImagingError.malformedCdrdaoToc(
                    "TRACK \(number) has no FILE/SILENCE/ZERO data statement"
                )
            }

            // The pregap is any leading SILENCE/ZERO (data placed before the
            // track's real audio) plus an in-file START offset; INDEX 01 sits
            // after it.
            let pregapFrames = curLeadingSilence + curStartFrames
            let index01LBA = curTrackStartLBA + pregapFrames

            // INDEX 00 (pregap) only when there is a pregap to mark.
            if pregapFrames > 0 {
                indexes.append(TrackIndex(
                    trackNumber: number,
                    indexNumber: 0,
                    sector: curTrackStartLBA,
                    offsetInTrack: Double(curTrackStartLBA - index01LBA) / Double(framesPerSecond),
                    absoluteTime: Double(curTrackStartLBA) / Double(framesPerSecond)
                ))
            }

            // INDEX 01 — every track has one.
            indexes.append(TrackIndex(
                trackNumber: number,
                indexNumber: 1,
                sector: index01LBA,
                offsetInTrack: 0,
                absoluteTime: Double(index01LBA) / Double(framesPerSecond)
            ))

            // INDEX 02+ — the frame offsets are relative to INDEX 01.
            var indexNumber = 2
            for relativeFrames in curSubIndexFrames {
                let absolute = index01LBA + relativeFrames
                indexes.append(TrackIndex(
                    trackNumber: number,
                    indexNumber: indexNumber,
                    sector: absolute,
                    offsetInTrack: Double(relativeFrames) / Double(framesPerSecond),
                    absoluteTime: Double(absolute) / Double(framesPerSecond)
                ))
                indexNumber += 1
            }

            tracks.append(DiscTrack(
                number: number,
                duration: Double(curDataSectors) / Double(framesPerSecond),
                startSector: index01LBA,
                sectorCount: curDataSectors,
                isData: mode != .audio,
                hasPreEmphasis: curPreEmphasis,
                isrc: curISRC,
                trackMode: mode
            ))
        }

        let lines = tocText.components(separatedBy: .newlines)
        for rawLine in lines {
            // Strip trailing `// comments` and surrounding whitespace.
            var line = rawLine
            if let commentRange = line.range(of: "//") {
                line = String(line[line.startIndex..<commentRange.lowerBound])
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Track brace nesting so CD_TEXT content is recognised. A single
            // physical line can open and close braces, so account for both.
            let opens = trimmed.filter { $0 == "{" }.count
            let closes = trimmed.filter { $0 == "}" }.count
            let wasInCDText = cdTextDepth > 0

            if trimmed.hasPrefix("CD_TEXT") {
                cdTextDepth += opens
                cdTextDepth -= closes
                // A CD_TEXT header line never itself carries a TITLE payload.
                continue
            }

            if wasInCDText {
                // Inside a CD_TEXT block: capture the metadata packs we model.
                captureCDText(
                    line: trimmed,
                    trackNumber: curNumber,
                    albumTitle: &albumTitle,
                    albumArtist: &albumArtist,
                    songwriter: &songwriter,
                    trackTitles: &trackTitles,
                    trackArtists: &trackArtists
                )
                cdTextDepth += opens
                cdTextDepth -= closes
                continue
            }

            let (keyword, remainder) = splitKeyword(trimmed)

            switch keyword.uppercased() {
            case "CD_DA":
                discType = "Audio CD"
            case "CD_ROM":
                discType = "CD-ROM"
            case "CD_ROM_XA":
                discType = "CD-ROM XA"

            case "CATALOG":
                catalog = unquote(remainder)

            case "TRACK":
                try finalizeTrack()
                resetTrackScratch()
                let token = remainder.split(separator: " ", maxSplits: 1).first.map(String.init) ?? remainder
                // cdrdao `.toc` TRACK lines carry no explicit number; tracks
                // are numbered sequentially from 1. finalizeTrack() has just
                // appended every prior track, so the next number is count + 1.
                curNumber = tracks.count + 1
                curMode = try trackMode(fromTocToken: token)
                curTrackStartLBA = currentLBA

            case "ISRC":
                if curNumber != nil { curISRC = unquote(remainder) }

            case "PRE_EMPHASIS":
                // Exact token only — "NO PRE_EMPHASIS" is split so its keyword
                // is "NO" and never reaches here.
                curPreEmphasis = true

            case "FILE":
                curDataSectors += try fileStatementLength(remainder)
                currentLBA = curTrackStartLBA + curDataSectors
                curSawFileData = true
                curSawData = true

            case "DATAFILE":
                curDataSectors += try dataFileStatementLength(remainder)
                currentLBA = curTrackStartLBA + curDataSectors
                curSawFileData = true
                curSawData = true

            case "SILENCE", "ZERO":
                let frames = try msfToFrames(firstToken(remainder))
                // Leading silence (before any real audio data) is the track's
                // pregap and pushes INDEX 01 forward; silence after audio just
                // extends the track body.
                if !curSawFileData { curLeadingSilence += frames }
                curDataSectors += frames
                currentLBA = curTrackStartLBA + curDataSectors
                curSawData = true

            case "START":
                curStartFrames = remainder.isEmpty ? 0 : try msfToFrames(firstToken(remainder))

            case "INDEX":
                curSubIndexFrames.append(try msfToFrames(firstToken(remainder)))

            default:
                // COPY / NO COPY / TWO_CHANNEL_AUDIO / FOUR_CHANNEL_AUDIO /
                // NO PRE_EMPHASIS / unknown single-line statements — accepted
                // and ignored.
                continue
            }
        }

        try finalizeTrack()

        var cdText: CDTextInfo?
        if albumTitle != nil || albumArtist != nil || songwriter != nil
            || !trackTitles.isEmpty || !trackArtists.isEmpty {
            cdText = CDTextInfo(
                albumTitle: albumTitle,
                albumArtist: albumArtist,
                trackTitles: trackTitles,
                trackArtists: trackArtists,
                songwriter: songwriter
            )
        }

        return DiscTableOfContents(
            discType: discType,
            tracks: tracks,
            indexes: indexes,
            leadOutSector: currentLBA,
            firstTrackNumber: tracks.first?.number ?? 1,
            lastTrackNumber: tracks.last?.number ?? 0,
            catalogNumber: catalog,
            cdText: cdText
        )
    }

    // MARK: - CD-TEXT capture

    /// Capture a TITLE / PERFORMER / SONGWRITER line seen inside a CD_TEXT
    /// block. When a track is in scope the value is a track pack; otherwise it
    /// is a disc-level pack. Lines without one of these keywords (e.g.
    /// `LANGUAGE 0 {`, `0 : EN`) are silently skipped.
    private static func captureCDText(
        line: String,
        trackNumber: Int?,
        albumTitle: inout String?,
        albumArtist: inout String?,
        songwriter: inout String?,
        trackTitles: inout [Int: String],
        trackArtists: inout [Int: String]
    ) {
        let (keyword, remainder) = splitKeyword(line)
        guard let value = extractQuoted(remainder) else { return }
        switch keyword.uppercased() {
        case "TITLE":
            if let number = trackNumber { trackTitles[number] = value } else { albumTitle = value }
        case "PERFORMER":
            if let number = trackNumber { trackArtists[number] = value } else { albumArtist = value }
        case "SONGWRITER":
            if trackNumber == nil { songwriter = value }
        default:
            break
        }
    }

    // MARK: - Tokenizing helpers

    /// Split a trimmed line into its leading keyword and the trimmed remainder.
    private static func splitKeyword(_ line: String) -> (keyword: String, remainder: String) {
        guard let spaceIndex = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return (line, "")
        }
        let keyword = String(line[line.startIndex..<spaceIndex])
        let remainder = String(line[line.index(after: spaceIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (keyword, remainder)
    }

    /// The first whitespace-delimited token of a string.
    private static func firstToken(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? s
    }

    /// Strip a single pair of surrounding double quotes, if present.
    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
        return String(s.dropFirst().dropLast())
    }

    /// Extract the text between the first pair of double quotes, or `nil` when
    /// there is no quoted substring.
    private static func extractQuoted(_ s: String) -> String? {
        guard let first = s.firstIndex(of: "\""),
              let last = s.lastIndex(of: "\""),
              first != last else {
            return nil
        }
        return String(s[s.index(after: first)..<last])
    }

    /// Map a `cdrdao` `TRACK <mode>` token to a `TrackMode`.
    ///
    /// `AUDIO → .audio`; `MODE1`/`MODE1_RAW → .mode1`;
    /// `MODE2_FORM1 → .mode2Form1`; `MODE2_FORM2 → .mode2Form2`;
    /// `MODE2`/`MODE2_RAW`/`MODE2_FORM_MIX → .mode2Raw`. Anything else throws.
    private static func trackMode(fromTocToken token: String) throws -> TrackMode {
        switch token.uppercased() {
        case "AUDIO":
            return .audio
        case "MODE1", "MODE1_RAW":
            return .mode1
        case "MODE2_FORM1":
            return .mode2Form1
        case "MODE2_FORM2":
            return .mode2Form2
        case "MODE2", "MODE2_RAW", "MODE2_FORM_MIX":
            return .mode2Raw
        default:
            throw ImagingError.malformedCdrdaoToc("Unknown TRACK mode: \(token)")
        }
    }

    /// Length in sectors of a `FILE "<name>" [#<byteOffset>] <start> [<length>]`
    /// statement.
    ///
    /// cdrdao's real grammar (trackdb/TocParser.g) allows an optional
    /// `#<byteOffset>` **before** `<start>` — a byte offset into the data file,
    /// never a length. The previous implementation took the second operand as
    /// the length unconditionally, so a leading `#offset` (or an authored
    /// `#off <start> <length>` triple) shifted every operand and mis-read the
    /// start as the length. We therefore drop a leading `#`-operand first; the
    /// remainder is `<start> [<length>]`, and the length — when present — is the
    /// last operand. cdrdao's own read output always writes an explicit length,
    /// so a start with no length is treated as malformed rather than guessed.
    private static func fileStatementLength(_ remainder: String) throws -> Int {
        var operands = operandsAfterQuotedName(remainder)
        if operands.first?.hasPrefix("#") == true {
            operands.removeFirst()
        }
        guard operands.count >= 2, let lengthToken = operands.last else {
            throw ImagingError.malformedCdrdaoToc("FILE statement has no explicit length: \(remainder)")
        }
        return try lengthFrames(lengthToken)
    }

    /// Length in sectors of a `DATAFILE "<name>" [#<byteOffset>] <length>`
    /// statement.
    ///
    /// A DATAFILE has no `<start>`, but the same grammar permits an optional
    /// leading `#<byteOffset>` — and, confusingly, cdrdao also writes the data
    /// **length** itself as `#<byteCount>`. The two are distinguished by
    /// position: a `#`-operand is only an offset when a further operand (the
    /// length) follows it. So a leading `#` is dropped only when two or more
    /// operands are present; a lone `#N` is the length.
    private static func dataFileStatementLength(_ remainder: String) throws -> Int {
        var operands = operandsAfterQuotedName(remainder)
        if operands.count >= 2, operands.first?.hasPrefix("#") == true {
            operands.removeFirst()
        }
        guard let lengthToken = operands.first else {
            throw ImagingError.malformedCdrdaoToc("DATAFILE statement missing a length: \(remainder)")
        }
        return try lengthFrames(lengthToken)
    }

    /// The whitespace-delimited operands that follow a leading quoted filename.
    /// When no quote is present the whole remainder is tokenised (lenient).
    private static func operandsAfterQuotedName(_ remainder: String) -> [String] {
        if let first = remainder.firstIndex(of: "\""),
           let close = remainder[remainder.index(after: first)...].firstIndex(of: "\"") {
            let after = remainder[remainder.index(after: close)...]
            return after.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        }
        return remainder.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    /// Convert a length operand to a sector count. Forms: `MM:SS:FF` (MSF),
    /// `#<byteLength>` (bytes ÷ 2352), or a bare integer (already frames).
    private static func lengthFrames(_ token: String) throws -> Int {
        if token.hasPrefix("#") {
            guard let bytes = Int(token.dropFirst()) else {
                throw ImagingError.malformedCdrdaoToc("Unparsable byte length: \(token)")
            }
            return bytes / mainSectorBytes
        }
        if token.contains(":") {
            return try msfToFrames(token)
        }
        guard let frames = Int(token) else {
            throw ImagingError.malformedCdrdaoToc("Unparsable length: \(token)")
        }
        return frames
    }

    /// Parse an `MM:SS:FF` value into an absolute frame count.
    private static func msfToFrames(_ msf: String) throws -> Int {
        let parts = msf.split(separator: ":")
        guard parts.count == 3,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]),
              let frames = Int(parts[2]) else {
            throw ImagingError.malformedCdrdaoToc("Invalid MM:SS:FF value: \(msf)")
        }
        return minutes * 60 * framesPerSecond + seconds * framesPerSecond + frames
    }
}
