// ============================================================================
// MeedyaConverter — MakeMKVBackend (Issue #503)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// FILE OVERVIEW
// -------------
// Slice 1 of the *optional, opt-in* MakeMKV disc-read/ripping backend (#503).
//
// This file is **pure**: it builds `makemkvcon` command lines and parses
// `makemkvcon`'s robot-mode (`-r`) text output into value models. That is ALL it
// does. By itself it:
//   • does NOT locate `makemkvcon` (that is slice 2 — the locator + user-set path),
//   • does NOT launch any subprocess (that is slice 3 — the executor),
//   • does NOT enable anything (that is slice 2 — the opt-in setting + terms
//     acknowledgement gate), and
//   • does NOT bundle or redistribute MakeMKV (never — the user installs it).
//
// It therefore changes NO policy. In particular the shared
// `DiscProtectionDetector` refuse-gate (#492) is untouched: MeedyaConverter's raw
// imaging path still detects and refuses copy-protected discs and never
// circumvents protection. MakeMKV is a *separate*, user-gated decision that only
// the later slices wire in, behind an explicit consent object — exactly the way
// the note in `DiscIdentification.swift` anticipated. Because nothing here runs,
// no real subprocess touches CI; the whole file is unit-tested against canned
// robot-mode text.
//
// Robot-mode format (from MakeMKV's `apdefs.h` / `makemkvcon` docs), one record
// per line, comma-separated, string fields double-quoted (a literal `"` is
// doubled `""`):
//   MSG:code,flags,count,message,format,param0,param1,...   — a status message
//   DRV:index,visible,enabled,flags,name,discName,devicePath — a drive slot
//   TCOUNT:count                                            — number of titles
//   CINFO:id,code,value                                     — a disc attribute
//   TINFO:title,id,code,value                               — a title attribute
//   SINFO:title,stream,id,code,value                        — a stream attribute
//   PRGC:code,id,name / PRGT:code,id,name                   — progress captions
//   PRGV:current,total,max                                  — progress values
// The `id` on C/T/SINFO is an `AP_ItemAttributeId` (see `MakeMKVAttributeID`).
// ============================================================================

import Foundation

// MARK: - Source + selectors

/// What `makemkvcon` should read from. Rendered to the tool's source specifier.
public enum MakeMKVSource: Sendable, Equatable {
    /// An optical drive by MakeMKV's own zero-based index → `disc:N`.
    case disc(Int)
    /// A raw device node → `dev:/dev/rdisk2` (macOS) / `dev:/dev/sr0` (Linux).
    case device(String)
    /// A decrypted folder (a `VIDEO_TS`/`BDMV` parent) → `file:/path`.
    case file(String)
    /// A disc image → `iso:/path/to/image.iso`.
    case iso(String)

    /// The exact token handed to `makemkvcon` (e.g. `disc:0`).
    public var specifier: String {
        switch self {
        case .disc(let index): return "disc:\(index)"
        case .device(let path): return "dev:\(path)"
        case .file(let path): return "file:\(path)"
        case .iso(let path): return "iso:\(path)"
        }
    }
}

/// Which titles to rip with the `mkv` command.
public enum MakeMKVTitleSelector: Sendable, Equatable {
    /// Every title MakeMKV chooses to expose → `all`.
    case all
    /// A single title by its zero-based index.
    case index(Int)

    /// The token handed to `makemkvcon mkv <source> <this>`.
    public var argument: String {
        switch self {
        case .all: return "all"
        case .index(let index): return String(index)
        }
    }
}

// MARK: - Attribute model

/// A MakeMKV item-attribute id (`AP_ItemAttributeId`). Only the ids we read are
/// named; any other id is still preserved on `MakeMKVAttribute.id`, so nothing is
/// silently dropped.
public enum MakeMKVAttributeID: Int, Sendable {
    case type = 1
    case name = 2
    case langCode = 3
    case langName = 4
    case codecId = 5
    case codecShort = 6
    case codecLong = 7
    case chapterCount = 8
    case duration = 9
    case diskSize = 10
    case diskSizeBytes = 11
    case streamTypeExtension = 12
    case bitrate = 13
    case audioChannelsCount = 14
    case angleInfo = 15
    case sourceFileName = 16
    case audioSampleRate = 17
    case audioSampleSize = 18
    case videoSize = 19
    case videoAspectRatio = 20
    case videoFrameRate = 21
    case streamFlags = 22
    case dateTime = 23
    case originalTitleId = 24
    case segmentsCount = 25
    case segmentsMap = 26
    case outputFileName = 27
    case metadataLanguageCode = 28
    case metadataLanguageName = 29
    case treeInfo = 30
    case panelTitle = 31
    case volumeName = 32
    case orderWeight = 33
    case outputFormat = 34
    case outputFormatDescription = 35
    case seamlessInfo = 36
    case panelText = 37
    case mkvFlags = 38
    case mkvFlagsText = 39
    case audioChannelLayoutName = 40
    case comment = 49
}

/// One attribute value from a C/T/SINFO record: its raw id, the localisation
/// `code` MakeMKV attaches, and the string value.
public struct MakeMKVAttribute: Sendable, Equatable {
    public var id: Int
    public var code: Int
    public var value: String

    public init(id: Int, code: Int, value: String) {
        self.id = id
        self.code = code
        self.value = value
    }

    /// The named attribute, when we recognise the id.
    public var attribute: MakeMKVAttributeID? { MakeMKVAttributeID(rawValue: id) }
}

extension Array where Element == MakeMKVAttribute {
    /// The value for a named attribute, or `nil` when absent.
    public func value(for attribute: MakeMKVAttributeID) -> String? {
        first { $0.id == attribute.rawValue }?.value
    }
}

// MARK: - Info models

/// A drive slot from a `DRV:` record. Empty slots have blank names.
public struct MakeMKVDrive: Sendable, Equatable {
    public var index: Int
    /// MakeMKV's drive-state code (its own enum); kept raw — we don't guess its
    /// meaning, only surface it.
    public var stateCode: Int
    public var flags: Int
    public var driveName: String
    public var discName: String
    public var devicePath: String

    public init(index: Int, stateCode: Int, flags: Int, driveName: String, discName: String, devicePath: String) {
        self.index = index
        self.stateCode = stateCode
        self.flags = flags
        self.driveName = driveName
        self.discName = discName
        self.devicePath = devicePath
    }

    /// Whether the slot reports a loaded disc (a non-blank disc name).
    public var hasDisc: Bool { !discName.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// One stream inside a title (`SINFO:` records).
public struct MakeMKVStream: Sendable, Equatable {
    public var index: Int
    public var attributes: [MakeMKVAttribute]

    public init(index: Int, attributes: [MakeMKVAttribute]) {
        self.index = index
        self.attributes = attributes
    }

    /// e.g. "Video", "Audio", "Subtitles".
    public var typeName: String? { attributes.value(for: .type) }
    public var codecShort: String? { attributes.value(for: .codecShort) }
    public var languageCode: String? { attributes.value(for: .langCode) }
    public var languageName: String? { attributes.value(for: .langName) }
    public var name: String? { attributes.value(for: .name) }
}

/// One title on the disc (`TINFO:` + its `SINFO:` streams).
public struct MakeMKVTitle: Sendable, Equatable {
    public var index: Int
    public var attributes: [MakeMKVAttribute]
    public var streams: [MakeMKVStream]

    public init(index: Int, attributes: [MakeMKVAttribute], streams: [MakeMKVStream]) {
        self.index = index
        self.attributes = attributes
        self.streams = streams
    }

    public var name: String? { attributes.value(for: .name) }
    /// The disc's own duration string, e.g. "1:57:21".
    public var duration: String? { attributes.value(for: .duration) }
    /// The duration parsed to whole seconds, when it is well-formed.
    public var durationSeconds: Int? { duration.flatMap(MakeMKVBackend.parseDuration) }
    public var chapterCount: Int? { attributes.value(for: .chapterCount).flatMap { Int($0) } }
    /// Human size string, e.g. "26.5 GB".
    public var sizeText: String? { attributes.value(for: .diskSize) }
    /// Exact size in bytes, when reported.
    public var sizeBytes: Int64? { attributes.value(for: .diskSizeBytes).flatMap { Int64($0) } }
    /// The source object name, e.g. "00800.mpls" (Blu-ray) / "VTS_01" (DVD).
    public var sourceFileName: String? { attributes.value(for: .sourceFileName) }
    public var segmentsMap: String? { attributes.value(for: .segmentsMap) }
}

/// The parsed result of a `makemkvcon info` run.
public struct MakeMKVDiscInfo: Sendable, Equatable {
    /// Drive slots (only populated by a drive scan, e.g. `info disc:9999`).
    public var drives: [MakeMKVDrive]
    /// Disc-level attributes (`CINFO:`).
    public var discAttributes: [MakeMKVAttribute]
    /// Titles, sorted by index.
    public var titles: [MakeMKVTitle]
    /// The count MakeMKV announced via `TCOUNT:`, if present.
    public var expectedTitleCount: Int?

    public init(
        drives: [MakeMKVDrive] = [],
        discAttributes: [MakeMKVAttribute] = [],
        titles: [MakeMKVTitle] = [],
        expectedTitleCount: Int? = nil
    ) {
        self.drives = drives
        self.discAttributes = discAttributes
        self.titles = titles
        self.expectedTitleCount = expectedTitleCount
    }

    /// The disc's name attribute, if any.
    public var discName: String? { discAttributes.value(for: .name) }
    /// The disc's volume name, if any.
    public var volumeName: String? { discAttributes.value(for: .volumeName) }
}

// MARK: - Progress + message models

/// One robot-mode progress record.
public enum MakeMKVProgressEvent: Sendable, Equatable {
    /// `PRGC:` — the caption of the current operation.
    case currentTitle(code: Int, id: Int, name: String)
    /// `PRGT:` — the caption of the overall operation.
    case totalTitle(code: Int, id: Int, name: String)
    /// `PRGV:` — current/total against a maximum (MakeMKV uses 65536).
    case values(current: Int, total: Int, max: Int)
}

extension MakeMKVProgressEvent {
    /// For a `.values` event, the "total" progress as a 0…1 fraction; `nil`
    /// otherwise or when `max` is not positive.
    public var totalFraction: Double? {
        guard case .values(_, let total, let max) = self, max > 0 else { return nil }
        return min(1.0, Double(total) / Double(max))
    }

    /// For a `.values` event, the "current" step as a 0…1 fraction; `nil`
    /// otherwise or when `max` is not positive.
    public var currentFraction: Double? {
        guard case .values(let current, _, let max) = self, max > 0 else { return nil }
        return min(1.0, Double(current) / Double(max))
    }
}

/// A parsed `MSG:` status message.
public struct MakeMKVMessage: Sendable, Equatable {
    public var code: Int
    public var flags: Int
    /// The already-formatted, human-readable message.
    public var text: String
    /// The raw format string (before parameter substitution).
    public var rawFormat: String
    public var parameters: [String]

    public init(code: Int, flags: Int, text: String, rawFormat: String, parameters: [String]) {
        self.code = code
        self.flags = flags
        self.text = text
        self.rawFormat = rawFormat
        self.parameters = parameters
    }
}

// MARK: - MakeMKVBackend (pure builders + parsers)

/// A pure namespace: it builds `makemkvcon` command lines and parses its
/// robot-mode output. Nothing here locates, launches, enables or bundles
/// MakeMKV — see the file overview.
public enum MakeMKVBackend {

    // MARK: Argument builders

    /// Build the argument list for `makemkvcon info <source>` (enumerate a disc's
    /// titles/streams). Global options precede the command, per the tool's syntax.
    ///
    /// - Parameters:
    ///   - source: what to read.
    ///   - robotMode: emit machine-readable output (`-r`). Default `true` — we
    ///     always parse robot output.
    ///   - noScan: skip the initial drive re-scan (`--noscan`), faster when the
    ///     source is already known.
    ///   - minLengthSeconds: `--minlength` — ignore titles shorter than this.
    ///   - cacheSizeMB: `--cache` read-ahead cache in MB.
    public static func buildInfoArguments(
        source: MakeMKVSource,
        robotMode: Bool = true,
        noScan: Bool = false,
        minLengthSeconds: Int? = nil,
        cacheSizeMB: Int? = nil
    ) -> [String] {
        var args: [String] = []
        if robotMode { args.append("-r") }
        if noScan { args.append("--noscan") }
        if let cacheSizeMB { args.append("--cache=\(cacheSizeMB)") }
        if let minLengthSeconds { args.append("--minlength=\(minLengthSeconds)") }
        args.append("info")
        args.append(source.specifier)
        return args
    }

    /// Build the argument list for `makemkvcon mkv <source> <titles> <dest>`
    /// (decode selected titles to `.mkv` files in `destinationDirectory`).
    ///
    /// Note: `mkv` inherently unlocks the disc — that is MakeMKV's purpose and
    /// exactly why this whole backend is opt-in and consent-gated in later slices.
    /// This builder only assembles the argv; it does not decide whether the run is
    /// permitted.
    public static func buildRipArguments(
        source: MakeMKVSource,
        titles: MakeMKVTitleSelector,
        destinationDirectory: String,
        robotMode: Bool = true,
        noScan: Bool = false,
        minLengthSeconds: Int? = nil,
        cacheSizeMB: Int? = nil,
        showProgress: Bool = true
    ) -> [String] {
        var args: [String] = []
        if robotMode { args.append("-r") }
        if noScan { args.append("--noscan") }
        if let cacheSizeMB { args.append("--cache=\(cacheSizeMB)") }
        if let minLengthSeconds { args.append("--minlength=\(minLengthSeconds)") }
        // `-same` routes progress to the same stream as messages, so a single
        // reader sees MSG/PRG interleaved.
        if showProgress { args.append("--progress=-same") }
        args.append("mkv")
        args.append(source.specifier)
        args.append(titles.argument)
        args.append(destinationDirectory)
        return args
    }

    /// Build the argument list for `makemkvcon backup --decrypt <source> <dest>`
    /// (a full, decrypted disc backup rather than per-title `.mkv`). Same consent
    /// posture as `buildRipArguments`.
    public static func buildBackupArguments(
        source: MakeMKVSource,
        destinationDirectory: String,
        decrypt: Bool = true,
        robotMode: Bool = true,
        noScan: Bool = false,
        cacheSizeMB: Int? = nil,
        showProgress: Bool = true
    ) -> [String] {
        var args: [String] = []
        if robotMode { args.append("-r") }
        if noScan { args.append("--noscan") }
        if let cacheSizeMB { args.append("--cache=\(cacheSizeMB)") }
        if showProgress { args.append("--progress=-same") }
        args.append("backup")
        if decrypt { args.append("--decrypt") }
        args.append(source.specifier)
        args.append(destinationDirectory)
        return args
    }

    // MARK: Robot-field splitting

    /// Split one robot-mode record body into its fields, honouring
    /// double-quoted strings (which may contain commas) and MakeMKV's
    /// backslash escaping. Bare numeric fields are returned verbatim.
    ///
    /// ⚠️ CODEX REVIEW ROUND 1, FINDING 9 (#503) — the primary source
    /// (https://www.makemkv.com/developers/usage.txt) says: "All strings are
    /// quoted, all control characters and quotes are backslash-escaped."
    /// Real 1.18.3 output looks like:
    ///   MSG:2010,0,1,"Optical drive \"BD-RE PIONEER\" opened in OS access
    ///   mode.","Optical drive \"%1\" opened in OS access mode.","BD-RE
    ///   PIONEER"
    /// This used to understand only a DOUBLED quote (`""`) as an escape, so
    /// it read the backslash before each embedded quote as a literal
    /// character and then closed the string one quote early — corrupting
    /// both the human-readable text AND the drive-name parameter that
    /// followed it. `2,0,"A \"B,C\""` parsed to `["2","0","A \\B","C\\"]`
    /// instead of the intended single field `A "B,C"`.
    ///
    /// So: INSIDE quotes, a backslash means "take the next character
    /// literally" — `\"` is a literal quote, `\\` is a literal backslash,
    /// `\,` is a literal comma (a bare comma inside quotes would otherwise
    /// look like a field separator). A lone trailing backslash with nothing
    /// after it (truncated/malformed input) is kept as a literal backslash
    /// rather than crashing or silently vanishing.
    ///
    /// The doubled-quote (`""`) handling is KEPT, but only as a TOLERANCE —
    /// it is NOT part of MakeMKV's documented format. It is safe to keep
    /// because in MakeMKV's own format a closing quote is always
    /// immediately followed by a comma or end of line, so seeing a SECOND
    /// quote immediately after one is otherwise never valid — reading it as
    /// one literal quote character can never misinterpret real output.
    ///
    /// KNOWN LIMIT, NOT FIXED HERE: MakeMKV can also use a trailing
    /// backslash at the end of a whole PHYSICAL LINE to continue a message
    /// onto the next line. This parser (and `parseInfo`/`parseMessageLine`,
    /// which split on line breaks before calling this) do not join
    /// continued lines back together first, so a message that MakeMKV
    /// splits this way — its message 3334 warning is one such case — is
    /// still parsed as if the first physical line were the whole thing,
    /// silently dropping the continuation. That is a separate follow-up.
    public static func parseRobotFields(_ body: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = body.makeIterator()
        var pending: Character? = iterator.next()

        while let character = pending {
            if inQuotes {
                switch character {
                case "\\":
                    // THE REAL FORMAT: take the next character literally,
                    // whatever it is (quote, backslash, comma, ...).
                    if let escaped = iterator.next() {
                        current.append(escaped)
                        pending = iterator.next()
                    } else {
                        // A lone trailing backslash with nothing after it —
                        // not valid MakeMKV output, but keep the character
                        // rather than dropping it or crashing on a
                        // force-unwrapped `iterator.next()`.
                        current.append("\\")
                        pending = nil
                    }
                case "\"":
                    // TOLERANCE, not the documented format — see above.
                    let next = iterator.next()
                    if next == "\"" {
                        current.append("\"") // doubled-quote escape
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                        pending = next
                    }
                default:
                    current.append(character)
                    pending = iterator.next()
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                    pending = iterator.next()
                case ",":
                    fields.append(current)
                    current = ""
                    pending = iterator.next()
                default:
                    current.append(character)
                    pending = iterator.next()
                }
            }
        }
        fields.append(current)
        return fields
    }

    // MARK: Info parsing

    /// Parse a full `makemkvcon info` robot-mode transcript into a
    /// `MakeMKVDiscInfo`. Best-effort and total: malformed or unknown lines are
    /// skipped, and titles/streams may arrive in any order.
    public static func parseInfo(_ output: String) -> MakeMKVDiscInfo {
        var drives: [MakeMKVDrive] = []
        var discAttributes: [MakeMKVAttribute] = []
        var expectedTitleCount: Int?
        // Accumulators keyed by index so out-of-order records still coalesce.
        var titleAttributes: [Int: [MakeMKVAttribute]] = [:]
        var titleStreams: [Int: [Int: [MakeMKVAttribute]]] = [:]

        for rawLine in output.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let prefix = String(line[line.startIndex..<colon])
            let body = String(line[line.index(after: colon)...])
            let fields = parseRobotFields(body)

            switch prefix {
            case "DRV":
                guard fields.count >= 7,
                      let index = Int(fields[0]) else { continue }
                drives.append(MakeMKVDrive(
                    index: index,
                    stateCode: Int(fields[1]) ?? 0,
                    flags: Int(fields[3]) ?? 0,
                    driveName: fields[4],
                    discName: fields[5],
                    devicePath: fields[6]
                ))
            case "TCOUNT":
                // Assign only on a clean parse, so a later malformed TCOUNT can
                // never null out an earlier valid count.
                if let count = Int(fields.first ?? "") { expectedTitleCount = count }
            case "CINFO":
                guard fields.count >= 3, let id = Int(fields[0]) else { continue }
                discAttributes.append(MakeMKVAttribute(id: id, code: Int(fields[1]) ?? 0, value: fields[2]))
            case "TINFO":
                guard fields.count >= 4,
                      let title = Int(fields[0]),
                      let id = Int(fields[1]) else { continue }
                titleAttributes[title, default: []].append(
                    MakeMKVAttribute(id: id, code: Int(fields[2]) ?? 0, value: fields[3])
                )
            case "SINFO":
                guard fields.count >= 5,
                      let title = Int(fields[0]),
                      let stream = Int(fields[1]),
                      let id = Int(fields[2]) else { continue }
                titleStreams[title, default: [:]][stream, default: []].append(
                    MakeMKVAttribute(id: id, code: Int(fields[3]) ?? 0, value: fields[4])
                )
            default:
                continue
            }
        }

        let titleIndices = Set(titleAttributes.keys).union(titleStreams.keys).sorted()
        let titles: [MakeMKVTitle] = titleIndices.map { titleIndex in
            let streams = (titleStreams[titleIndex] ?? [:])
                .keys.sorted()
                .map { streamIndex in
                    MakeMKVStream(index: streamIndex, attributes: titleStreams[titleIndex]?[streamIndex] ?? [])
                }
            return MakeMKVTitle(
                index: titleIndex,
                attributes: titleAttributes[titleIndex] ?? [],
                streams: streams
            )
        }

        return MakeMKVDiscInfo(
            drives: drives,
            discAttributes: discAttributes,
            titles: titles,
            expectedTitleCount: expectedTitleCount
        )
    }

    // MARK: Progress + message parsing

    /// Parse a single `PRGC:`/`PRGT:`/`PRGV:` line, or `nil` for anything else.
    public static func parseProgressLine(_ rawLine: String) -> MakeMKVProgressEvent? {
        let line = stripTrailingCR(rawLine)
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let prefix = String(line[line.startIndex..<colon])
        let fields = parseRobotFields(String(line[line.index(after: colon)...]))
        switch prefix {
        case "PRGC":
            guard fields.count >= 3, let code = Int(fields[0]), let id = Int(fields[1]) else { return nil }
            return .currentTitle(code: code, id: id, name: fields[2])
        case "PRGT":
            guard fields.count >= 3, let code = Int(fields[0]), let id = Int(fields[1]) else { return nil }
            return .totalTitle(code: code, id: id, name: fields[2])
        case "PRGV":
            guard fields.count >= 3,
                  let current = Int(fields[0]),
                  let total = Int(fields[1]),
                  let max = Int(fields[2]) else { return nil }
            return .values(current: current, total: total, max: max)
        default:
            return nil
        }
    }

    /// Parse a single `MSG:` line, or `nil` for anything else.
    public static func parseMessageLine(_ rawLine: String) -> MakeMKVMessage? {
        let line = stripTrailingCR(rawLine)
        guard let colon = line.firstIndex(of: ":"),
              String(line[line.startIndex..<colon]) == "MSG" else { return nil }
        let fields = parseRobotFields(String(line[line.index(after: colon)...]))
        guard fields.count >= 5,
              let code = Int(fields[0]),
              let flags = Int(fields[1]) else { return nil }
        let parameters = fields.count > 5 ? Array(fields[5...]) : []
        return MakeMKVMessage(
            code: code,
            flags: flags,
            text: fields[3],
            rawFormat: fields[4],
            parameters: parameters
        )
    }

    // MARK: Helpers

    /// A single robot line with any one trailing carriage return removed, so a
    /// caller that hand-splits streamed output on "\n" alone (as the future
    /// executor will) still parses the final field cleanly.
    private static func stripTrailingCR(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }

    /// Parse a MakeMKV duration string ("H:MM:SS" or "MM:SS") to whole seconds.
    /// Returns `nil` when the string is not a well-formed clock value.
    public static func parseDuration(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var seconds = 0
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            // Minutes/seconds beyond an hour field should still be < 60, but we
            // accept the tool's own value rather than reject a real transcript.
            seconds = seconds * 60 + value
        }
        return seconds
    }
}
