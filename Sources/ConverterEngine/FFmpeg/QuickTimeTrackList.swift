// ============================================================================
// MeedyaConverter — QuickTimeTrackList
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// WHY THIS FILE EXISTS
// --------------------
// A MOV or MP4 track's language is a 16-bit number in its media header
// (`mdhd`), and that number means one of two things (ISO/IEC 14496-12 and
// Apple's QuickTime file format):
//
//   * below 0x400: an old Macintosh language NUMBER — 0 English, 2 German,
//     19 Traditional Chinese, 33 Simplified Chinese …;
//   * otherwise (0x7FFF aside, which means "not specified"): three letters,
//     five bits each — an ISO 639-2 code such as `zho` or `swe`.
//
// ffprobe reports BOTH as three letters. For a Macintosh number it gives
// the label of ffmpeg's own list (`chi`, `sve`), which is not always what the
// number means, and several numbers share a label: 19 (Traditional Chinese)
// and 33 (Simplified Chinese) are both `chi`, 49 and 50 (Azerbaijani in
// Cyrillic and in Arabic script) both `aze`. Apple's players read the
// NUMBER. So from ffprobe alone a MOV's `chi` (number 19, Traditional
// Chinese), a MOV's other `chi` (number 33, Simplified Chinese) and an MP4's
// packed `chi` (plain Chinese) all look the same — and a MOV written by
// Apple's own tools stores PACKED codes (`aze`, `mon`, `sve`), which Apple
// reads literally, beside an extended language box for the script. Checked
// with ffmpeg 9.0.1 and Apple's AVFoundation on 4 Oct 2026, writing every
// number from 0 to 151 into a MOV and reading each back both ways, and
// exporting MOVs with Apple's `avconvert`.
//
// A track may also carry an EXTENDED LANGUAGE box (`elng`, inside `mdia`)
// holding the full BCP 47 tag — the language policy's full-tag field for
// MP4 and MOV (TRACK-070). Apple writes one (`zh-Hant` beside a packed
// `zho`); ffmpeg neither writes nor reads it.
//
// This reads, for each track, its handler type, the `mdhd` number and the
// `elng` tag, so `FFmpegProbe` can read each language as Apple's players do
// (`FFmpegProbe.applyingQuickTimeLanguages`). Until the fourth independent
// review of the language policy work the converter read ffprobe's text
// only: a MOV's Traditional-Chinese `chi` was read as plain Chinese, so a
// MOV-to-MOV remux stored no language at all, and a MOV's `sve` (Swedish to
// Apple) as Serili, the language `sve` is registered for elsewhere.
//
// WHAT IT CANNOT DO
// -----------------
// * It reads only the first `moov` box, and inside it only `trak` → `mdia`
//   → `hdlr`, `mdhd` and `elng`, seeking over everything else — it never
//   reads the sample tables or the media. A movie header that is compressed
//   (`cmov`, from very old QuickTime) or damaged makes it answer `nil`:
//   nothing is changed, never guessed.
// * It looks at no more than 65,536 box headers and 1,024 tracks in all,
//   and reads no box body larger than 4 KiB (`hdlr`, `mdhd` and `elng` are a
//   few dozen bytes), so a damaged or hostile file cannot make it read
//   without end.
// * It reads; it never writes. ffmpeg writes neither an `elng` box nor a
//   packed code into a MOV (only the Macintosh numbers on its list) — see
//   `TrackLanguage.LanguageFieldStorage`.
// * Matching tracks to ffprobe's streams is by ORDER (ffmpeg makes one
//   stream per `trak`, in the file's order; cover art from the file's tags
//   is an extra picture stream, left out of the match); `streamsMatched`
//   refuses the match unless the counts and every type agree.
// ============================================================================

import Foundation

/// The language fields of each track of a MOV or MP4 file, as the file
/// itself records them.
public struct QuickTimeTrackList: Sendable, Equatable {

    /// One track (`trak`).
    public struct Track: Sendable, Equatable {
        /// The handler type from `hdlr` — `vide`, `soun`, `subt`, `text`,
        /// `sbtl`, `clcp`, `tmcd` … — or `nil` when the track has none.
        public let handler: String?
        /// The language number from `mdhd`, or `nil` when there is no media
        /// header. Below 0x400 it is a Macintosh language number; otherwise
        /// three packed letters (0x7FFF: not specified).
        public let languageCode: UInt16?
        /// The full tag from `elng`, or `nil` when the box is absent, empty,
        /// or not valid UTF-8.
        public let extendedLanguage: String?

        public init(handler: String?, languageCode: UInt16?, extendedLanguage: String?) {
            self.handler = handler
            self.languageCode = languageCode
            self.extendedLanguage = extendedLanguage
        }

        /// Whether `languageCode` is a Macintosh language number (below
        /// 0x400) rather than three packed letters.
        public var hasMacintoshLanguageNumber: Bool {
            guard let languageCode else { return false }
            return languageCode < 0x400
        }
    }

    /// The tracks in the file's order.
    public let tracks: [Track]

    public init(tracks: [Track]) {
        self.tracks = tracks
    }

    // MARK: - Limits

    /// The most box headers read in all, at every level.
    static let boxLimit = 65_536
    /// The most tracks read. More makes the list unreadable (`nil`); no real
    /// file comes near it.
    static let trackLimit = 1024
    /// The largest `hdlr`, `mdhd` or `elng` body read. Anything larger is
    /// damage, and the whole list is refused.
    static let smallBoxLimit: UInt64 = 4096

    /// How much one read looked at — so tests can prove the walk stays
    /// bounded by counting, never by timing.
    struct Effort: Sendable, Equatable {
        /// Box headers read, at every level.
        var boxesVisited = 0
    }

    // MARK: - Reading a file

    /// Reads `url`'s track list, or `nil` when the file cannot be opened,
    /// has no `moov` box that can be walked, or is not MOV / MP4 at all.
    public static func read(url: URL) -> QuickTimeTrackList? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var effort = Effort()
        return read(from: FileSource(handle: handle, size: size), effort: &effort)
    }

    /// Reads a track list from bytes already in memory (for tests).
    public static func read(bytes: [UInt8]) -> QuickTimeTrackList? {
        var effort = Effort()
        return read(bytes: bytes, effort: &effort)
    }

    /// `read(bytes:)`, also counting what it looked at (`Effort`).
    static func read(bytes: [UInt8], effort: inout Effort) -> QuickTimeTrackList? {
        read(from: MemorySource(bytes: bytes), effort: &effort)
    }

    /// The walk: the top-level boxes until the first `moov`, then its tracks.
    private static func read(from source: some ByteSource, effort: inout Effort) -> QuickTimeTrackList? {
        var offset: UInt64 = 0
        while offset < source.size, effort.boxesVisited < boxLimit {
            guard let box = boxHeader(in: source, at: offset, end: source.size) else { return nil }
            effort.boxesVisited += 1
            if box.type == "moov" {
                return tracks(inMovie: box, source: source, effort: &effort).map(QuickTimeTrackList.init(tracks:))
            }
            offset = box.end
        }
        return nil
    }

    /// Every track in a `moov` box, or `nil` when the box is damaged, holds
    /// more than `trackLimit` tracks, or is compressed (`cmov`).
    private static func tracks(inMovie movie: BoxHeader, source: some ByteSource, effort: inout Effort) -> [Track]? {
        var result: [Track] = []
        var damaged = false
        let walked = forEachChild(of: movie, source: source, effort: &effort) { child, effort in
            switch child.type {
            case "cmov":
                damaged = true
                return false
            case "trak":
                guard result.count < trackLimit, let track = track(in: child, source: source, effort: &effort) else {
                    damaged = true
                    return false
                }
                result.append(track)
            default:
                break
            }
            return true
        }
        return walked && !damaged ? result : nil
    }

    /// One `trak` box's handler, language number and full tag, or `nil` when
    /// it is damaged. For each, the FIRST box counts.
    private static func track(in trak: BoxHeader, source: some ByteSource, effort: inout Effort) -> Track? {
        var handler: String?
        var code: UInt16?
        var full: String?
        var damaged = false
        let walked = forEachChild(of: trak, source: source, effort: &effort) { media, effort in
            guard media.type == "mdia" else { return true }
            let inner = forEachChild(of: media, source: source, effort: &effort) { box, _ in
                guard ["hdlr", "mdhd", "elng"].contains(box.type) else { return true }
                guard box.end - box.dataStart <= smallBoxLimit,
                      let body = source.bytes(at: box.dataStart, count: Int(box.end - box.dataStart)) else {
                    damaged = true
                    return false
                }
                switch box.type {
                case "hdlr" where handler == nil:
                    // FullBox (4) + pre_defined / QuickTime's component type (4),
                    // then the handler type (4).
                    guard body.count >= 12 else { damaged = true; return false }
                    handler = String(bytes: body[8..<12], encoding: .isoLatin1)
                case "mdhd" where code == nil:
                    // FullBox: version 0 has 32-bit times and duration (the
                    // language at byte 20), version 1 64-bit (byte 32).
                    guard let version = body.first, version <= 1 else { damaged = true; return false }
                    let at = version == 0 ? 20 : 32
                    guard body.count >= at + 2 else { damaged = true; return false }
                    code = UInt16(body[at]) << 8 | UInt16(body[at + 1])
                case "elng" where full == nil:
                    // FullBox (4), then the tag up to a NUL.
                    full = body.count > 4 ? text(body[4...]) : nil
                default:
                    break
                }
                return true
            }
            return inner && !damaged
        }
        return walked && !damaged ? Track(handler: handler, languageCode: code, extendedLanguage: full) : nil
    }

    // MARK: - Matching ffprobe's streams

    /// The track each of ffprobe's streams comes from, keyed by the stream's
    /// whole-file number — or `nil` when the two lists cannot be matched with
    /// certainty. ffmpeg makes one stream per `trak`, in the file's order;
    /// cover art from the file's tags (`covr`) is an extra picture stream and
    /// is left out of the match. Refused unless the counts and every type
    /// agree: `vide` must be a video stream, `soun` audio, anything else a
    /// subtitle, data or unknown stream.
    public func streamsMatched(to streams: [MediaStream]) -> [Int: Track]? {
        let trackStreams = streams
            .filter { $0.streamType != .attachment && $0.disposition?.isAttachedPicture != true }
            .sorted { $0.streamIndex < $1.streamIndex }
        guard trackStreams.count == tracks.count else { return nil }
        var matched: [Int: Track] = [:]
        for (track, stream) in zip(tracks, trackStreams) {
            let fits: Bool
            switch track.handler {
            case "vide": fits = stream.streamType == .video
            case "soun": fits = stream.streamType == .audio
            case nil: fits = false
            default: fits = stream.streamType == .subtitle || stream.streamType == .data || stream.streamType == .unknown
            }
            guard fits else { return nil }
            matched[stream.streamIndex] = track
        }
        return matched
    }

    // MARK: - Boxes

    /// A box's type, where its data starts and where it ends.
    private struct BoxHeader {
        let type: String
        let dataStart: UInt64
        let end: UInt64
    }

    /// The box header at `offset`, or `nil` when it does not fit before
    /// `end` or is malformed. A size of 1 means a 64-bit size follows; 0
    /// means "to the end of the parent".
    private static func boxHeader(in source: some ByteSource, at offset: UInt64, end: UInt64) -> BoxHeader? {
        guard offset < end, end - offset >= 8, let head = source.bytes(at: offset, count: 8) else { return nil }
        let small = head[0..<4].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard let type = String(bytes: head[4..<8], encoding: .isoLatin1) else { return nil }
        var size = small
        var headerLength: UInt64 = 8
        if small == 1 {
            guard end - offset >= 16, let large = source.bytes(at: offset + 8, count: 8) else { return nil }
            size = large.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            headerLength = 16
        } else if small == 0 {
            size = end - offset
        }
        guard size >= headerLength, size <= end - offset else { return nil }
        return BoxHeader(type: type, dataStart: offset + headerLength, end: offset + size)
    }

    /// Calls `visit` for each child box of `parent`, in order, until it
    /// returns `false`. Returns `false` when a child does not fit, or the box
    /// limit is reached — the caller then treats the list as unreadable.
    private static func forEachChild(
        of parent: BoxHeader,
        source: some ByteSource,
        effort: inout Effort,
        _ visit: (BoxHeader, inout Effort) -> Bool
    ) -> Bool {
        var offset = parent.dataStart
        while offset < parent.end {
            guard effort.boxesVisited < boxLimit,
                  let child = boxHeader(in: source, at: offset, end: parent.end) else { return false }
            effort.boxesVisited += 1
            guard visit(child, &effort) else { return false }
            offset = child.end
        }
        return true
    }

    /// A string's text: the bytes up to the first NUL, as UTF-8, spaces
    /// trimmed, at most 256 bytes — or `nil` when that is empty or not valid
    /// UTF-8, so damaged text is treated as absent rather than read as
    /// something else.
    private static func text(_ data: ArraySlice<UInt8>) -> String? {
        let used = data.prefix { $0 != 0 }.prefix(256)
        guard let decoded = String(bytes: used, encoding: .utf8) else { return nil }
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
