// ============================================================================
// MeedyaConverter — CdrdaoProgressParser
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CdrdaoProgressParser

/// Pure parsing of `cdrdao`'s console output into typed events, plus the pure
/// combiner that turns a polled output-file size into the *existing*
/// `ImagingProgress` value (reused from `DiscImager` — there is no new
/// progress model).
///
/// ## Why file-size polling drives the fraction, not the console
///
/// `cdrdao` prints per-track markers on the console — "Reading track 3
/// (AUDIO)…", "Found ISRC code.", and a lead-in TOC table — but it does *not*
/// print a byte or percentage counter there. Byte-level progress streaming
/// only exists in cdrdao's `--remote` binary protocol, which this integration
/// deliberately does not use (it complicates the subprocess contract for no
/// fidelity gain). So the executor derives the completion fraction by polling
/// the growing `.bin` file's size against
/// `RawCDReadPlanner.expectedBinByteCount`, and treats the parsed console
/// events as *advisory* colour — worst case the progress is coarse, never
/// wrong. The exact wording cdrdao prints is version- and locale-dependent, so
/// the accepted shapes below are taken from cdrdao 1.2.4 / 1.2.5 and must be
/// confirmed against captured output on the hardware matrix (any drift becomes
/// new fixture strings, never a code guess).
public struct CdrdaoProgressParser: Sendable {

    /// A single typed event lifted from one line of cdrdao's console output.
    public enum Event: Sendable, Equatable {
        /// The drive identified itself, e.g. `/dev/sr0: MATSHITA … Rev: 1.00`.
        case driveIdentified(description: String)

        /// A row of cdrdao's "Track Mode Flags Start Length" lead-in table.
        /// `startSector` and `lengthSectors` come from the parenthesised
        /// sector columns, e.g. `… 00:00:00(     0)     03:27:70( 15595)`.
        case tocTableRow(track: Int, mode: String, startSector: Int, lengthSectors: Int)

        /// cdrdao began reading a track, e.g. `Reading track 3 (AUDIO)…` or
        /// `Copying audio tracks 1-12: …`.
        case readingTrack(number: Int, mode: String)

        /// `Found ISRC code.`
        case foundISRC

        /// `Found disk catalogue number.`
        case foundCatalogNumber

        /// `Reading of toc and track data finished successfully.`
        case finished

        /// An `ERROR: …` line; the message is everything after the prefix.
        case fatalError(message: String)
    }

    /// Parse one line of cdrdao stderr into an `Event`, or `nil` for chatter.
    ///
    /// Named per the task brief. This is the single line-level entry point; the
    /// executor feeds every captured stderr line through it.
    ///
    /// - Parameter line: One line of cdrdao console output (no trailing
    ///   newline required).
    /// - Returns: The typed event, or `nil` when the line carries nothing we
    ///   model.
    public static func parseCdrdaoProgress(line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Fatal errors — highest priority.
        if let range = trimmed.range(of: "ERROR:") {
            let message = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return .fatalError(message: message)
        }

        if trimmed == "Found ISRC code." {
            return .foundISRC
        }
        if trimmed == "Found disk catalogue number." {
            return .foundCatalogNumber
        }
        if trimmed.hasPrefix("Reading of toc and track data finished successfully") {
            return .finished
        }

        // "Reading track N (MODE)…"
        if trimmed.hasPrefix("Reading track") {
            if let event = parseReadingTrack(trimmed) { return event }
        }

        // "Copying audio tracks X-Y: …"
        if trimmed.hasPrefix("Copying audio tracks") {
            if let event = parseCopyingTracks(trimmed) { return event }
        }

        // Drive identification line: "/dev/sr0: … Rev: …".
        if trimmed.hasPrefix("/dev/") && trimmed.contains("Rev:") {
            return .driveIdentified(description: trimmed)
        }

        // Lead-in TOC table row: a leading integer track, a mode word, and at
        // least two parenthesised sector columns.
        if let event = parseTocTableRow(trimmed) {
            return event
        }

        return nil
    }

    /// Build an `ImagingProgress` (the reused type) from the polled output-file
    /// size, the expected total, the latest track event, an error count, and a
    /// caller-supplied wall-clock rate.
    ///
    /// The completion fraction comes entirely from `bytesOnDisk /
    /// expectedTotalBytes` via `ImagingProgress.fractionComplete`. `bytesOnDisk`
    /// is clamped to the expected total so the fraction never exceeds 1.0 when
    /// the datafile briefly runs a little ahead of the sizing estimate; a
    /// non-positive expected total yields a `nil` `totalBytes` (and therefore a
    /// `nil` fraction), matching the "unknown size" contract of the reused
    /// struct.
    ///
    /// Because cdrdao reports progress at track granularity rather than sector
    /// granularity, the current track number is carried in `currentSector`
    /// (there is no track field on the reused `ImagingProgress`); it is the
    /// most faithful "where are we" datum the console gives us.
    ///
    /// - Parameters:
    ///   - bytesOnDisk: Current size of the growing `.bin` datafile.
    ///   - expectedTotalBytes: `RawCDReadPlanner.expectedBinByteCount` for the
    ///     disc; `<= 0` means the size is not yet known.
    ///   - currentTrack: The track cdrdao last reported reading, if any.
    ///   - errorCount: Number of `ERROR:`/read errors seen so far.
    ///   - bytesPerSecond: Caller's wall-clock-derived read rate.
    /// - Returns: A populated `ImagingProgress`.
    public static func makeProgress(
        bytesOnDisk: Int64,
        expectedTotalBytes: Int64,
        currentTrack: Int?,
        errorCount: Int,
        bytesPerSecond: Double
    ) -> ImagingProgress {
        let hasTotal = expectedTotalBytes > 0
        let clampedBytes = hasTotal ? min(bytesOnDisk, expectedTotalBytes) : bytesOnDisk
        return ImagingProgress(
            bytesCopied: max(0, clampedBytes),
            totalBytes: hasTotal ? expectedTotalBytes : nil,
            bytesPerSecond: bytesPerSecond,
            errorCount: errorCount,
            badSectors: 0,
            currentSector: Int64(currentTrack ?? 0)
        )
    }

    // MARK: - Line parsing helpers

    /// Parse "Reading track N (MODE)…".
    private static func parseReadingTrack(_ line: String) -> Event? {
        // Drop the "Reading track " prefix; expect "N (MODE)…".
        let rest = line.dropFirst("Reading track".count).trimmingCharacters(in: .whitespaces)
        let numberPart = rest.prefix { $0.isNumber }
        guard let number = Int(numberPart) else { return nil }
        let mode = extractParenthesised(String(rest)) ?? ""
        return .readingTrack(number: number, mode: mode)
    }

    /// Parse "Copying audio tracks X-Y: …" — the first track is the anchor and
    /// audio is the implied mode.
    private static func parseCopyingTracks(_ line: String) -> Event? {
        let rest = line.dropFirst("Copying audio tracks".count).trimmingCharacters(in: .whitespaces)
        let firstNumber = rest.prefix { $0.isNumber }
        guard let number = Int(firstNumber) else { return nil }
        return .readingTrack(number: number, mode: "AUDIO")
    }

    /// Parse a lead-in TOC table row: a leading integer track number, a mode
    /// word, and two-or-more parenthesised sector columns whose first two
    /// values are the start sector and the length in sectors.
    private static func parseTocTableRow(_ line: String) -> Event? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = tokens.first, let track = Int(first), tokens.count >= 2 else { return nil }
        let mode = tokens[1]
        // The mode column must be a word (letters/underscore/digits), not a
        // number — this rejects ordinary numeric log lines.
        guard mode.first?.isLetter == true else { return nil }

        let sectorValues = parenthesisedIntegers(line)
        guard sectorValues.count >= 2 else { return nil }
        return .tocTableRow(
            track: track,
            mode: mode,
            startSector: sectorValues[0],
            lengthSectors: sectorValues[1]
        )
    }

    /// Extract the first `(...)`-delimited substring's trimmed content.
    private static func extractParenthesised(_ s: String) -> String? {
        guard let open = s.firstIndex(of: "("),
              let close = s[s.index(after: open)...].firstIndex(of: ")") else {
            return nil
        }
        return String(s[s.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
    }

    /// Every integer that appears inside `( … )` groups, in order.
    private static func parenthesisedIntegers(_ s: String) -> [Int] {
        var results: [Int] = []
        var chars = Substring(s)
        while let open = chars.firstIndex(of: "(") {
            let afterOpen = chars.index(after: open)
            guard let close = chars[afterOpen...].firstIndex(of: ")") else { break }
            let inside = chars[afterOpen..<close].trimmingCharacters(in: .whitespaces)
            if let value = Int(inside) {
                results.append(value)
            }
            chars = chars[chars.index(after: close)...]
        }
        return results
    }
}
