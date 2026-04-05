// ============================================================================
// MeedyaConverter — EDLHandler (Issue #342)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - EDLEvent
// ---------------------------------------------------------------------------
/// Represents a single edit event in an Edit Decision List (EDL).
///
/// An EDL event describes one edit operation: a segment of source material
/// placed onto the timeline at a specific record position. Events follow
/// the CMX 3600 convention by default, with fields for reel name, track
/// type (video/audio), and timecode-style in/out points.
///
/// Timecodes are stored as strings (e.g., "01:00:05:12") to preserve
/// frame-accurate representation without committing to a specific frame
/// rate at the model level.
public struct EDLEvent: Identifiable, Codable, Sendable {

    /// Unique identifier for this event.
    public let id: UUID

    /// Sequential event number (1-based, as in CMX 3600).
    public var eventNumber: Int

    /// Source reel or clip name (e.g., "AX", "BL", or a file reference).
    public var reelName: String

    /// Track type: "V" for video, "A" for audio, "A2" for audio track 2, etc.
    public var trackType: String

    /// Edit type: "C" for cut, "D" for dissolve, "W" for wipe, etc.
    public var editType: String

    /// Source in-point timecode (e.g., "01:00:00:00").
    public var sourceIn: String

    /// Source out-point timecode.
    public var sourceOut: String

    /// Record (timeline) in-point timecode.
    public var recordIn: String

    /// Record (timeline) out-point timecode.
    public var recordOut: String

    /// Memberwise initializer.
    public init(
        id: UUID = UUID(),
        eventNumber: Int,
        reelName: String,
        trackType: String = "V",
        editType: String = "C",
        sourceIn: String,
        sourceOut: String,
        recordIn: String,
        recordOut: String
    ) {
        self.id = id
        self.eventNumber = eventNumber
        self.reelName = reelName
        self.trackType = trackType
        self.editType = editType
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.recordIn = recordIn
        self.recordOut = recordOut
    }
}

// ---------------------------------------------------------------------------
// MARK: - EDLHandler
// ---------------------------------------------------------------------------
/// Parses and generates Edit Decision Lists in CMX 3600 (`.edl`) and
/// Final Cut Pro XML (`.fcpxml`) formats.
///
/// `EDLHandler` is a pure-function utility: all methods are static and
/// operate on string content rather than file handles, making them easy
/// to test and compose.
///
/// Usage:
/// ```swift
/// // Parse a CMX 3600 EDL
/// let content = try String(contentsOfFile: "/path/to/timeline.edl")
/// let events = EDLHandler.parseCMX3600(content)
///
/// // Generate an EDL from events
/// let edlString = EDLHandler.generateCMX3600(events: events, title: "My Edit")
///
/// // Convert chapter markers to EDL events
/// let chapters: [Chapter] = ...
/// let chapterEvents = EDLHandler.eventsFromChapters(chapters: chapters)
/// ```
public struct EDLHandler: Sendable {

    // MARK: - CMX 3600 Parsing

    /// Parses a CMX 3600 format EDL string into an array of ``EDLEvent``
    /// values.
    ///
    /// CMX 3600 format consists of a title line followed by numbered events:
    /// ```
    /// TITLE: My Sequence
    /// 001  AX       V     C        01:00:00:00 01:00:05:00 01:00:00:00 01:00:05:00
    /// 002  AX       A     C        01:00:05:00 01:00:10:00 01:00:05:00 01:00:10:00
    /// ```
    ///
    /// - Parameter content: The full text content of a CMX 3600 EDL file.
    /// - Returns: Array of parsed ``EDLEvent`` values in event-number order.
    public static func parseCMX3600(_ content: String) -> [EDLEvent] {
        var events: [EDLEvent] = []

        // Each event line has the format:
        // NNN  REEL  TRACK  EDIT  SRC_IN SRC_OUT REC_IN REC_OUT
        let pattern = #"^\s*(\d{3,})\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d{2}:\d{2}:\d{2}:\d{2})\s+(\d{2}:\d{2}:\d{2}:\d{2})\s+(\d{2}:\d{2}:\d{2}:\d{2})\s+(\d{2}:\d{2}:\d{2}:\d{2})"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .anchorsMatchLines
        ) else {
            return events
        }

        let nsContent = content as NSString
        let matches = regex.matches(
            in: content,
            range: NSRange(location: 0, length: nsContent.length)
        )

        for match in matches {
            let eventNum = Int(nsContent.substring(with: match.range(at: 1))) ?? 0
            let reel = nsContent.substring(with: match.range(at: 2))
            let track = nsContent.substring(with: match.range(at: 3))
            let edit = nsContent.substring(with: match.range(at: 4))
            let srcIn = nsContent.substring(with: match.range(at: 5))
            let srcOut = nsContent.substring(with: match.range(at: 6))
            let recIn = nsContent.substring(with: match.range(at: 7))
            let recOut = nsContent.substring(with: match.range(at: 8))

            events.append(EDLEvent(
                eventNumber: eventNum,
                reelName: reel,
                trackType: track,
                editType: edit,
                sourceIn: srcIn,
                sourceOut: srcOut,
                recordIn: recIn,
                recordOut: recOut
            ))
        }

        return events
    }

    // MARK: - CMX 3600 Generation

    /// Generates a CMX 3600 format EDL string from an array of events.
    ///
    /// The output includes a `TITLE:` header line followed by one line per
    /// event. Event numbers are zero-padded to three digits. Fields are
    /// tab-aligned for readability.
    ///
    /// - Parameters:
    ///   - events: The edit events to serialize.
    ///   - title: The sequence title for the EDL header.
    /// - Returns: A complete CMX 3600 EDL as a string.
    public static func generateCMX3600(
        events: [EDLEvent],
        title: String
    ) -> String {
        var lines: [String] = []
        lines.append("TITLE: \(title)")
        lines.append("") // Blank line after title

        for event in events {
            let line = String(
                format: "%03d  %-8s %-5s %-4s %s %s %s %s",
                event.eventNumber,
                (event.reelName as NSString).utf8String ?? "",
                (event.trackType as NSString).utf8String ?? "",
                (event.editType as NSString).utf8String ?? "",
                event.sourceIn,
                event.sourceOut,
                event.recordIn,
                event.recordOut
            )
            lines.append(line)
        }

        lines.append("") // Trailing newline
        return lines.joined(separator: "\n")
    }

    // MARK: - FCPXML Parsing

    /// Parses a Final Cut Pro XML (FCPXML) document into ``EDLEvent`` values.
    ///
    /// This is a simplified parser that extracts `<asset-clip>` and
    /// `<clip>` elements from the XML. Full FCPXML support (compound clips,
    /// multicam, roles) is planned for a future release.
    ///
    /// - Parameter content: The full text content of an FCPXML file.
    /// - Returns: Array of parsed ``EDLEvent`` values.
    public static func parseFCPXML(_ content: String) -> [EDLEvent] {
        var events: [EDLEvent] = []

        // Simplified extraction of clip elements.
        // Full XML parsing via XMLDocument would be used in production;
        // this regex approach handles the common single-timeline case.
        let clipPattern = #"<(?:asset-clip|clip)\s+[^>]*name="([^"]*)"[^>]*offset="([^"]*)"[^>]*duration="([^"]*)"[^>]*/?"#
        guard let regex = try? NSRegularExpression(pattern: clipPattern) else {
            return events
        }

        let nsContent = content as NSString
        let matches = regex.matches(
            in: content,
            range: NSRange(location: 0, length: nsContent.length)
        )

        for (index, match) in matches.enumerated() {
            let name = nsContent.substring(with: match.range(at: 1))
            let offset = nsContent.substring(with: match.range(at: 2))
            let duration = nsContent.substring(with: match.range(at: 3))

            // Convert FCPXML rational time (e.g., "300/30s") to timecode-like
            // representation for EDLEvent compatibility.
            let offsetTC = Self.fcpxmlTimeToTimecode(offset)
            let durationSeconds = Self.fcpxmlTimeToSeconds(duration)
            let endTC = Self.secondsToTimecode(
                Self.fcpxmlTimeToSeconds(offset) + durationSeconds
            )

            events.append(EDLEvent(
                eventNumber: index + 1,
                reelName: name,
                trackType: "V",
                editType: "C",
                sourceIn: "00:00:00:00",
                sourceOut: Self.secondsToTimecode(durationSeconds),
                recordIn: offsetTC,
                recordOut: endTC
            ))
        }

        return events
    }

    // MARK: - FCPXML Generation

    /// Generates a minimal Final Cut Pro XML (FCPXML) document from
    /// an array of events.
    ///
    /// The generated XML follows FCPXML v1.11 schema conventions with a
    /// single timeline containing the provided events as asset-clips.
    /// Frame rate is assumed to be 30 fps for timecode conversion.
    ///
    /// - Parameters:
    ///   - events: The edit events to serialize.
    ///   - title: The project / timeline title.
    /// - Returns: A complete FCPXML document as a string.
    public static func generateFCPXML(
        events: [EDLEvent],
        title: String
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.11">
            <resources/>
            <library>
                <event name="\(title)">
                    <project name="\(title)">
                        <sequence format="r1">
                            <spine>

        """

        for event in events {
            let offsetSeconds = Self.timecodeToSeconds(event.recordIn)
            let durationSeconds = Self.timecodeToSeconds(event.recordOut)
                                - Self.timecodeToSeconds(event.recordIn)
            let offset = Self.secondsToFCPXMLTime(offsetSeconds)
            let duration = Self.secondsToFCPXMLTime(
                max(durationSeconds, 0)
            )

            xml += "                        "
            xml += "<asset-clip name=\"\(event.reelName)\" "
            xml += "offset=\"\(offset)\" "
            xml += "duration=\"\(duration)\"/>\n"
        }

        xml += """
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>

        """

        return xml
    }

    // MARK: - Chapter Conversion

    /// Converts an array of ``Chapter`` markers into ``EDLEvent`` values.
    ///
    /// Each chapter becomes a cut event on the video track. The chapter's
    /// start/end times are converted to SMPTE-style timecodes at 30 fps.
    /// The chapter title (or a fallback "Chapter N") is used as the reel
    /// name.
    ///
    /// - Parameter chapters: The chapter markers to convert.
    /// - Returns: Array of ``EDLEvent`` values, one per chapter.
    public static func eventsFromChapters(chapters: [Chapter]) -> [EDLEvent] {
        return chapters.enumerated().map { index, chapter in
            let title = chapter.title ?? "Chapter \(chapter.number)"
            return EDLEvent(
                eventNumber: index + 1,
                reelName: title,
                trackType: "V",
                editType: "C",
                sourceIn: secondsToTimecode(chapter.startTime),
                sourceOut: secondsToTimecode(chapter.endTime),
                recordIn: secondsToTimecode(chapter.startTime),
                recordOut: secondsToTimecode(chapter.endTime)
            )
        }
    }

    // MARK: - Timecode Helpers (Private)

    /// Converts seconds to SMPTE timecode string at 30 fps.
    /// Format: HH:MM:SS:FF
    static func secondsToTimecode(_ seconds: TimeInterval) -> String {
        let totalFrames = Int(seconds * 30.0)
        let frames = totalFrames % 30
        let totalSeconds = totalFrames / 30
        let secs = totalSeconds % 60
        let mins = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d:%02d", hours, mins, secs, frames)
    }

    /// Converts SMPTE timecode string to seconds at 30 fps.
    static func timecodeToSeconds(_ timecode: String) -> TimeInterval {
        let parts = timecode.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 4 else { return 0 }
        let totalFrames = parts[0] * 108000  // hours * 30 * 60 * 60
                        + parts[1] * 1800    // minutes * 30 * 60
                        + parts[2] * 30      // seconds * 30
                        + parts[3]           // frames
        return TimeInterval(totalFrames) / 30.0
    }

    /// Converts FCPXML rational time (e.g., "300/30s" or "10s") to seconds.
    private static func fcpxmlTimeToSeconds(_ time: String) -> TimeInterval {
        let cleaned = time.replacingOccurrences(of: "s", with: "")
        if cleaned.contains("/") {
            let parts = cleaned.split(separator: "/")
            guard parts.count == 2,
                  let num = Double(parts[0]),
                  let den = Double(parts[1]),
                  den != 0 else { return 0 }
            return num / den
        }
        return Double(cleaned) ?? 0
    }

    /// Converts FCPXML rational time to SMPTE timecode.
    private static func fcpxmlTimeToTimecode(_ time: String) -> String {
        return secondsToTimecode(fcpxmlTimeToSeconds(time))
    }

    /// Converts seconds to FCPXML rational time format (e.g., "300/30s").
    private static func secondsToFCPXMLTime(_ seconds: TimeInterval) -> String {
        let frames = Int(seconds * 30.0)
        return "\(frames)/30s"
    }
}
