// ============================================================================
// MeedyaConverter — MatroskaTrackList
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// WHY THIS FILE EXISTS
// --------------------
// A Matroska track has TWO language fields (RFC 9559): the old `Language`
// (a three-letter ISO 639-2 code) and `LanguageBCP47` (the full tag). The
// language policy says a reader MUST ignore the old field when the full tag
// is present (TRACK-070). ffprobe does not: ffmpeg 9.0.1 reads only the old
// field. mkvmerge (MKVToolNix, since version 51) writes both — and for a
// language with no three-letter code of its own, the old field gets the
// nearest one: Cantonese `yue`, Mandarin `cmn` and Min Nan `nan` all become
// `chi`, Canadian French `fr-CA` becomes `fre`. So a file made by mkvmerge
// probed as three tracks of "Chinese" and one of "French"; a remux wrote
// `chi`/`fre`, dropped the full tag, and titled Cantonese "中文" — with no
// note (found in the second independent review of the language policy work).
//
// This reads the file's own track list — a small, bounded read of the start
// of the file — and gives each track's two language fields, plus the
// application that wrote the file. `FFmpegProbe` then takes the full tag
// where there is one (`MediaStream.language`), keeping the old field's text
// (`MediaStream.languageAsStored`), which is what ffmpeg copies.
//
// WHAT IT CANNOT DO
// -----------------
// * It reads only the elements before the first Cluster (the first block of
//   media data). The track list comes before it in every file mkvmerge and
//   ffmpeg write, as RFC 9559 recommends; a file with its track list at the
//   END is not read, and the caller treats it as "could not tell".
// * It never reads more than 16 MiB for the track list or 1 MiB for the
//   segment information, and looks at no more than 4,096 top-level elements
//   (plus up to 65,536 filler elements — EBML `Void`, which writers leave as
//   padding), so a damaged or hostile file cannot make it read without end.
//   Anything it does not understand makes it stop and answer `nil` — never
//   a guess.
// * Inside the track list it walks each element's children BY POSITION in
//   the one buffer it read, copying nothing but the few short values it
//   keeps; it steps over filler; and a list of more than 1,024 tracks is
//   treated as unreadable (the caller then says the full tags could not be
//   read). The third independent review found the first version copied
//   every child: a 16 MiB track list of 8,388,000 empty entries took 32.7
//   seconds and 631 MB of memory, and 5,000 filler elements before the track
//   list stopped it reading at all. `Effort` counts what a read looked at,
//   so tests can prove the bounds without timing anything.
// * It reads; it never writes. Writing `LanguageBCP47` into an output is
//   issue #532 (ffmpeg cannot).
// * Matching tracks to ffprobe's streams is by ORDER (ffmpeg makes one stream
//   per video, audio, subtitle and metadata track, in the file's order, and
//   then one per attachment); `streamsMatched` refuses the match unless the
//   counts and every type agree.
// ============================================================================

import Foundation

/// The track list of a Matroska or WebM file, as the file itself records it.
public struct MatroskaTrackList: Sendable, Equatable {

    /// One track (`TrackEntry`).
    public struct Track: Sendable, Equatable {
        /// `TrackNumber`, when present.
        public let number: UInt64?
        /// `TrackType`: 1 video, 2 audio, 0x11 subtitle, 0x21 metadata …
        public let type: UInt64?
        /// The old `Language` field's text, or `nil` when the element is
        /// absent (RFC 9559's default is then `eng`, which ffprobe reports).
        public let language: String?
        /// `LanguageBCP47`, the full tag, or `nil` when absent.
        public let languageBCP47: String?

        public init(number: UInt64?, type: UInt64?, language: String?, languageBCP47: String?) {
            self.number = number
            self.type = type
            self.language = language
            self.languageBCP47 = languageBCP47
        }
    }

    /// `WritingApp` from the segment information (`mkvmerge v101.0 …`,
    /// `Lavf63.1.101`), when it was read.
    public let writingApplication: String?

    /// The tracks in the file's order, or `nil` when the track list could
    /// not be read.
    public let tracks: [Track]?

    public init(writingApplication: String?, tracks: [Track]?) {
        self.writingApplication = writingApplication
        self.tracks = tracks
    }

    // MARK: - Element IDs (RFC 9559)

    private enum ID {
        static let ebmlHeader: UInt32 = 0x1A45_DFA3
        static let segment: UInt32 = 0x1853_8067
        static let info: UInt32 = 0x1549_A966
        static let tracks: UInt32 = 0x1654_AE6B
        static let cluster: UInt32 = 0x1F43_B675
        static let writingApp: UInt32 = 0x5741
        static let trackEntry: UInt32 = 0xAE
        static let trackNumber: UInt32 = 0xD7
        static let trackType: UInt32 = 0x83
        static let language: UInt32 = 0x22_B59C
        static let languageBCP47: UInt32 = 0x22_B59D
    }

    /// The most read for the track list and for the segment information.
    private static let tracksLimit: UInt64 = 16 * 1024 * 1024
    private static let infoLimit: UInt64 = 1024 * 1024
    /// The most top-level elements looked at before giving up — filler not
    /// counted, as it has its own limit.
    private static let elementLimit = 4096
    /// The most top-level filler (EBML `Void`) elements stepped over before
    /// giving up. Writers leave one or a few as padding; 65,536 is far more
    /// than any real file, and each costs one small read.
    private static let fillerLimit = 65_536
    /// The most track entries read. More makes the list "unreadable" (`nil`
    /// tracks), which the caller reports; no real file comes near it.
    static let trackEntryLimit = 1024
    /// EBML `Void`: filler that says nothing, allowed anywhere.
    private static let voidID: UInt32 = 0xEC

    /// How much one read looked at — so tests can prove the walk stays
    /// bounded by counting, never by timing.
    struct Effort: Sendable, Equatable {
        /// Elements whose header was read, at every level, filler included.
        var elementsVisited = 0
        /// Filler (`Void`) elements stepped over, at every level.
        var fillerSkipped = 0
    }

    // MARK: - Reading a file

    /// Reads `url`'s track list and writing application, or `nil` when the
    /// file cannot be opened or is not Matroska / WebM at all.
    public static func read(url: URL) -> MatroskaTrackList? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var effort = Effort()
        return read(from: FileSource(handle: handle, size: size), effort: &effort)
    }

    /// Reads a track list from bytes already in memory (for tests, and any
    /// caller that has the start of a file).
    public static func read(bytes: [UInt8]) -> MatroskaTrackList? {
        var effort = Effort()
        return read(bytes: bytes, effort: &effort)
    }

    /// `read(bytes:)`, also counting what it looked at (`Effort`).
    static func read(bytes: [UInt8], effort: inout Effort) -> MatroskaTrackList? {
        read(from: MemorySource(bytes: bytes), effort: &effort)
    }

    /// The walk itself: the EBML header, then the Segment's top-level
    /// elements up to the first Cluster.
    private static func read(from source: some ByteSource, effort: inout Effort) -> MatroskaTrackList? {
        // The EBML header must come first; its size says where the Segment is.
        guard let header = elementHeader(in: source, at: 0, end: source.size),
              header.id == ID.ebmlHeader, let headerSize = header.size else { return nil }
        let segmentStart = header.dataStart + headerSize
        guard let segment = elementHeader(in: source, at: segmentStart, end: source.size),
              segment.id == ID.segment else { return nil }
        // A Segment of unknown size (a live recording) runs to the end.
        let segmentEnd = segment.size.map { min(segment.dataStart + $0, source.size) } ?? source.size

        var writingApp: String?
        var tracks: [Track]?
        var offset = segment.dataStart
        var looked = 0
        var filler = 0
        while offset < segmentEnd, looked < elementLimit, filler < fillerLimit, tracks == nil || writingApp == nil {
            guard let element = elementHeader(in: source, at: offset, end: segmentEnd) else { break }
            effort.elementsVisited += 1
            if element.id == ID.cluster { break }
            // An element of unknown size cannot be stepped over.
            guard let size = element.size, element.dataStart + size <= segmentEnd else { break }
            if element.id == voidID {
                // Filler: stepped over, and counted against its own limit.
                filler += 1
                effort.fillerSkipped += 1
            } else {
                looked += 1
                if element.id == ID.info, size <= infoLimit,
                   let body = source.bytes(at: element.dataStart, count: Int(size)) {
                    writingApp = writingApplication(in: body, effort: &effort)
                } else if element.id == ID.tracks, size <= tracksLimit,
                          let body = source.bytes(at: element.dataStart, count: Int(size)) {
                    tracks = trackEntries(in: body, effort: &effort)
                }
            }
            offset = element.dataStart + size
        }
        guard tracks != nil || writingApp != nil else { return nil }
        return MatroskaTrackList(writingApplication: writingApp, tracks: tracks)
    }

    /// Every `TrackEntry` in a `Tracks` element's body, or `nil` when the
    /// body is damaged or holds more than `trackEntryLimit` entries. Walked
    /// by position (`ChildWalker`): nothing is copied but the four short
    /// values kept from each entry, and filler is stepped over. For each
    /// field the FIRST occurrence counts, as before.
    private static func trackEntries(in body: [UInt8], effort: inout Effort) -> [Track]? {
        var result: [Track] = []
        var entries = ChildWalker(body: body, range: 0..<body.count)
        defer { entries.addCounts(to: &effort) }
        while let entry = entries.next() {
            guard entry.id == ID.trackEntry else { continue }
            guard result.count < trackEntryLimit else { return nil }
            var number: Range<Int>?, type: Range<Int>?, language: Range<Int>?, full: Range<Int>?
            var fields = ChildWalker(body: body, range: entry.data)
            while let field = fields.next() {
                switch field.id {
                case ID.trackNumber where number == nil: number = field.data
                case ID.trackType where type == nil: type = field.data
                case ID.language where language == nil: language = field.data
                case ID.languageBCP47 where full == nil: full = field.data
                default: break
                }
            }
            fields.addCounts(to: &effort)
            guard !fields.isDamaged else { return nil }
            result.append(Track(
                number: number.flatMap { unsigned(body[$0]) },
                type: type.flatMap { unsigned(body[$0]) },
                language: language.flatMap { text(body[$0]) },
                languageBCP47: full.flatMap { text(body[$0]) }
            ))
        }
        return entries.isDamaged ? nil : result
    }

    /// `WritingApp` from a segment-information body — the first one — or
    /// `nil` (also when the body is damaged: nothing else there matters).
    private static func writingApplication(in body: [UInt8], effort: inout Effort) -> String? {
        var children = ChildWalker(body: body, range: 0..<body.count)
        var found: Range<Int>?
        while let child = children.next() {
            if found == nil, child.id == ID.writingApp { found = child.data }
        }
        children.addCounts(to: &effort)
        guard !children.isDamaged, let found else { return nil }
        return text(body[found])
    }

    // MARK: - Matching ffprobe's streams

    /// The track each of ffprobe's streams comes from, keyed by the stream's
    /// whole-file number — or `nil` when the two lists cannot be matched
    /// with certainty. ffmpeg makes one stream per video, audio, subtitle
    /// and metadata track, in the file's order (it skips other kinds of
    /// track), then one per attachment; so the match is by order, and it is
    /// refused unless the counts and every stream's type agree.
    public func streamsMatched(to streams: [MediaStream]) -> [Int: Track]? {
        guard let tracks else { return nil }
        let trackStreams = streams
            .filter { $0.streamType != .attachment && $0.disposition?.isAttachedPicture != true }
            .sorted { $0.streamIndex < $1.streamIndex }
        let usable = tracks.filter { [1, 2, 0x11, 0x21].contains($0.type ?? 0) }
        guard usable.count == trackStreams.count else { return nil }
        var matched: [Int: Track] = [:]
        for (track, stream) in zip(usable, trackStreams) {
            let fits: Bool
            switch track.type {
            case 1: fits = stream.streamType == .video
            case 2: fits = stream.streamType == .audio
            case 0x11: fits = stream.streamType == .subtitle
            default: fits = stream.streamType == .data || stream.streamType == .subtitle || stream.streamType == .unknown
            }
            guard fits else { return nil }
            matched[stream.streamIndex] = track
        }
        return matched
    }

    /// Whether a file written by `application` may hold `LanguageBCP47`
    /// fields — used only when the track list itself could not be read.
    /// Only ffmpeg's own writer (`Lavf…`) is known never to write one
    /// (checked with ffmpeg 9.0.1; `ContainerLanguageToolTests` prints
    /// whether the test machine's ffmpeg does). mkvmerge writes them since
    /// MKVToolNix 51; any other writer — or none named — might: "cannot
    /// tell" counts as "may".
    public static func mayHoldFullLanguageTags(writtenBy application: String?) -> Bool {
        guard let application = application?.trimmingCharacters(in: .whitespaces) else { return true }
        return !application.hasPrefix("Lavf")
    }

    // MARK: - EBML

    /// An element's ID, where its data starts, and its size (`nil` when the
    /// file says "unknown").
    private struct ElementHeader {
        let id: UInt32
        let dataStart: UInt64
        let size: UInt64?
    }

    /// One child element: its ID and where its data lies in the parent's
    /// body — a position, never a copy.
    private struct ChildPlace {
        let id: UInt32
        let data: Range<Int>
    }

    /// Walks the children of a master element's body, one at a time, by
    /// position, stepping over filler (`Void`). It stops, and says
    /// `isDamaged`, at a child that does not fit or has an unknown size.
    /// A plain loop rather than a list of children, so a body of millions of
    /// tiny elements costs a counter, not millions of copies.
    private struct ChildWalker {
        let body: [UInt8]
        private var index: Int
        private let end: Int
        /// Whether the walk stopped at a child that did not fit.
        private(set) var isDamaged = false
        /// Children whose header was read, filler included.
        private(set) var visited = 0
        /// Filler children stepped over.
        private(set) var fillerSkipped = 0

        init(body: [UInt8], range: Range<Int>) {
            self.body = body
            index = range.lowerBound
            end = min(range.upperBound, body.count)
        }

        /// The next child that is not filler, or `nil` at the end of the
        /// body or at damage.
        mutating func next() -> ChildPlace? {
            while index < end, !isDamaged {
                guard let id = MatroskaTrackList.variableLengthNumber(body, at: index, maxLength: 4, keepMarker: true),
                      let size = MatroskaTrackList.variableLengthNumber(
                        body, at: index + id.length, maxLength: 8, keepMarker: false
                      ),
                      !size.isUnknown else {
                    isDamaged = true
                    return nil
                }
                visited += 1
                let start = index + id.length + size.length
                guard start <= end, size.value <= UInt64(end - start) else {
                    isDamaged = true
                    return nil
                }
                let stop = start + Int(size.value)
                index = stop
                let childID = UInt32(truncatingIfNeeded: id.value)
                if childID == MatroskaTrackList.voidID {
                    fillerSkipped += 1
                    continue
                }
                return ChildPlace(id: childID, data: start..<stop)
            }
            return nil
        }

        /// Adds this walk's counts to `effort`.
        func addCounts(to effort: inout Effort) {
            effort.elementsVisited += visited
            effort.fillerSkipped += fillerSkipped
        }
    }

    /// The element header at `offset`, or `nil` when it does not fit before
    /// `end` or is malformed.
    private static func elementHeader(in source: some ByteSource, at offset: UInt64, end: UInt64) -> ElementHeader? {
        guard offset < end else { return nil }
        let available = Int(min(12, end - offset))
        guard let bytes = source.bytes(at: offset, count: available),
              let id = variableLengthNumber(bytes, at: 0, maxLength: 4, keepMarker: true),
              let size = variableLengthNumber(bytes, at: id.length, maxLength: 8, keepMarker: false) else { return nil }
        return ElementHeader(
            id: UInt32(truncatingIfNeeded: id.value),
            dataStart: offset + UInt64(id.length + size.length),
            size: size.isUnknown ? nil : size.value
        )
    }

    /// An EBML variable-length number at `index`: its value, its length in
    /// bytes, and whether every value bit is set (for a size: "unknown").
    /// `keepMarker` keeps the length marker bit, as element IDs are written.
    static func variableLengthNumber(
        _ bytes: [UInt8], at index: Int, maxLength: Int, keepMarker: Bool
    ) -> (value: UInt64, length: Int, isUnknown: Bool)? {
        guard index >= 0, index < bytes.count, bytes[index] != 0 else { return nil }
        let first = bytes[index]
        let length = first.leadingZeroBitCount + 1
        guard length <= maxLength, index + length <= bytes.count else { return nil }
        let valueBitsOfFirst = length >= 8 ? UInt8(0) : UInt8(0xFF) >> UInt8(length)
        var value = UInt64(keepMarker ? first : first & valueBitsOfFirst)
        var allOnes = (first & valueBitsOfFirst) == valueBitsOfFirst
        for offset in 1..<length {
            let byte = bytes[index + offset]
            value = (value << 8) | UInt64(byte)
            allOnes = allOnes && byte == 0xFF
        }
        return (value, length, allOnes)
    }

    /// An unsigned integer element's value (at most 8 bytes, big-endian).
    private static func unsigned(_ data: ArraySlice<UInt8>) -> UInt64? {
        guard data.count <= 8 else { return nil }
        return data.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    /// A string element's text: the bytes up to the first NUL, as UTF-8,
    /// spaces trimmed, at most 256 bytes — or `nil` when that is empty or
    /// not valid UTF-8 (a language tag or a program's name never is), so
    /// damaged text is treated as absent rather than read as something else.
    private static func text(_ data: ArraySlice<UInt8>) -> String? {
        let used = data.prefix { $0 != 0 }.prefix(256)
        guard let decoded = String(bytes: used, encoding: .utf8) else { return nil }
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Byte sources

/// Where a track-list reader gets its bytes: a file, or memory. Shared by
/// `MatroskaTrackList` and `QuickTimeTrackList`.
protocol ByteSource {
    var size: UInt64 { get }
    func bytes(at offset: UInt64, count: Int) -> [UInt8]?
}

/// Bytes from an open file, read only where asked.
///
/// A read of ZERO bytes gives an empty list, as `MemorySource` does.
/// `FileHandle.read(upToCount: 0)` answers `nil`, and until the stand-in
/// review of round 5 that `nil` was passed on: an 8-byte `elng` box (a
/// header with no body) was "absent" when the bytes were in memory but made
/// the WHOLE track list unreadable when read from a file — so another track
/// of that file lost its language. The tests read the same bytes both ways
/// (`QuickTimeTrackListTests.test_aFileAndMemoryReadTheSame`).
struct FileSource: ByteSource {
    let handle: FileHandle
    let size: UInt64

    func bytes(at offset: UInt64, count: Int) -> [UInt8]? {
        guard count >= 0, offset <= size, UInt64(count) <= size - offset else { return nil }
        if count == 0 { return [] }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return [UInt8](data)
    }
}

/// Bytes already in memory.
struct MemorySource: ByteSource {
    let bytesInMemory: [UInt8]
    var size: UInt64 { UInt64(bytesInMemory.count) }

    init(bytes: [UInt8]) { bytesInMemory = bytes }

    func bytes(at offset: UInt64, count: Int) -> [UInt8]? {
        guard count >= 0, offset <= size, UInt64(count) <= size - offset else { return nil }
        let start = Int(offset)
        return Array(bytesInMemory[start..<(start + count)])
    }
}
