// ============================================================================
// MeedyaConverter — SettingsSourceKeyScanner (Issue #506 commit 4, test-only)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Reads every `.swift` file under `Sources/` as TEXT (it does not compile
// anything) and lists every settings key the code reads or writes, so
// `SettingsKeyCoverageTests` can check each one has a decision in
// `SettingsKeyRegistry`.
//
// What it looks for:
//   - `@AppStorage("key")`, `@AppStorage(wrappedValue: x, "key")` and
//     `@AppStorage(SomeType.Keys.name)`;
//   - `forKey: "key"` and `forKey: SomeConstant` — this covers every
//     `UserDefaults` read, write and removal (`set(_:forKey:)`,
//     `bool(forKey:)`, `removeObject(forKey:)`, …), including calls split
//     over several lines;
//   - `settingKey: "key"` — `AppViewModel`'s notification helpers take the
//     key as a parameter and read it with `forKey: settingKey`, so the
//     literal only ever appears at the call site;
//   - `UserDefaults(suiteName:` — opening a different settings domain;
//   - `applicationSupportDirectory` — building a path in Application
//     Support — and "Application Support" spelled out in a string.
//
// What it deliberately skips, because these are not settings:
//   - `removeValue(forKey:` (a Swift dictionary);
//   - `forKey: .something` (a `Codable` coding key);
//   - `forKey: "…", in:` (tag look-ups in `MusicBrainzTagMapping` and
//     `TMDBTagMapping`);
//   - a `settingKey: String` parameter declaration;
//   - any line that is ENTIRELY a comment (`//` or `///` after optional
//     indentation). A comment can therefore never make a key look "used"
//     and keep a dead registry entry alive. A comment AFTER code on the
//     same line is still read; that can only add a key to check, never
//     hide one.
//
// Anything at a settings call site that is neither a plain string nor a
// plain name (an interpolated string like "\(prefix)x", an expression like
// `prefix + "x"`, a raw or multi-line string) is reported as UNREADABLE,
// and the test fails on it. That is how keys built at run time are caught
// at the call site rather than silently missed.
//
// A key reached through a name (a constant) is recorded as
// "File.swift|Name.path". The test then needs that name in
// `SettingsKeyScanMap.symbols`, which says which key it stands for, or that
// it is not a settings key at all (with the reason).
//
// WHAT IT CANNOT CATCH (its blind spots, stated honestly):
//   1. Settings written by frameworks, whose names never appear in our code:
//      Sparkle's `SU…` keys (Direct builds), AppKit window positions, the
//      open and save panels' last folder. The allow-list never exports
//      them, which is the safe direction.
//   2. Settings written through other interfaces: `register(defaults:)`,
//      `setValuesForKeys`, Cocoa bindings, `NSUserDefaultsController`,
//      `@SceneStorage`, `CFPreferences…`. None is used in `Sources/` today
//      (searched when this was written); a new one would not be seen.
//   3. A constant whose TEXT changes while its NAME stays the same. The map
//      records "this name means this key"; for PUBLIC engine constants,
//      `SettingsKeyCoverageTests` compares the map with the real constant,
//      so the compiler catches a change. PRIVATE constants
//      (`AnalyticsEngine`'s three keys, `EntitlementGating`'s two,
//      `KeyboardShortcutManager.storageKey`,
//      `LocalizationManager.languageKey`, and the two views' private copies
//      of the SFTP and cloud keys) cannot be checked that way. The app test
//      `SettingsRegistryAppConstantsTests` covers the app's internal ones
//      it can reach.
//   4. A key held in a variable and passed around (`let k = "x"; …
//      forKey: k`): the call site shows a NAME, so the test demands a map
//      entry, which is the right outcome, but the map entry is only as
//      right as the person who writes it.
//   5. Keys in other programs' settings, or in App Group suites. The
//      `UserDefaults(suiteName:` check flags any new domain being opened.
//   6. Lines inside a `/* … */` block comment that do not start with `//`
//      ARE read. That can only add keys to check, never hide one.
//   7. Two source files with the same name in different folders would make
//      "File.swift|Name" ambiguous. The test fails if that ever happens for
//      a file with a settings call in it.
//   8. It is text matching, not a Swift parser. The self-test in
//      `SettingsKeyCoverageTests` feeds it synthetic code to show what it
//      does and does not recognise.
//
// Keys built at run time in `Sources/` today: none at a call site. The only
// keys built with string interpolation are `AnalyticsEngine`'s three
// ("\(keyPrefix)enabled" and so on). They are built in private constants,
// and the call sites use the constants' names, so they are covered by the
// map (`AnalyticsEngine.swift|Self.enabledKey` → `analytics_enabled`, …),
// with blind spot 3 applying.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsSourceKeyScanner

/// Finds settings keys in Swift source text. Test-only. Pure: it reads the
/// text it is given (or the files under a folder) and returns what it found.
struct SettingsSourceKeyScanner {

    /// A place in the source: file (relative to `Sources/`), line, and the
    /// line's text, for readable failure messages.
    struct Site: Hashable, Comparable, CustomStringConvertible, Sendable {
        let file: String
        let line: Int
        let excerpt: String

        static func < (lhs: Site, rhs: Site) -> Bool {
            (lhs.file, lhs.line) < (rhs.file, rhs.line)
        }

        var description: String { "\(file):\(line): \(excerpt)" }
    }

    /// Everything one scan found.
    struct Result: Sendable {
        /// Keys written as plain strings → the files they appear in.
        var literalKeys: [String: Set<String>] = [:]
        /// "File.swift|Name.path" → where that name is used as a key.
        var symbolReferences: [String: [Site]] = [:]
        /// Settings call sites whose key could not be read as text.
        var unreadableSites: [Site] = []
        /// Every `UserDefaults(suiteName:` call.
        var suiteNameSites: [Site] = []
        /// File name → how many times it names `applicationSupportDirectory`.
        var applicationSupportCalls: [String: Int] = [:]
        /// Code lines spelling out "Application Support" inside a string.
        var applicationSupportLiteralSites: [Site] = []
        /// File name → the relative paths with that name, for files that had
        /// at least one settings finding (to detect ambiguous names).
        var relativePathsByFileName: [String: Set<String>] = [:]
        /// How many `.swift` files were read.
        var scannedFileCount = 0

        /// Every key found: plain strings plus names resolved through `map`
        /// (names that are not settings keys, or not in the map, are left
        /// out; the test reports unmapped names separately).
        func allKeys(resolvingWith map: [String: SettingsKeyScanMap.Target]) -> [String: Set<String>] {
            var keys = literalKeys
            for (symbol, sites) in symbolReferences {
                guard case .key(let key)? = map[symbol] else { continue }
                keys[key, default: []].formUnion(sites.map(\.file))
            }
            return keys
        }

        mutating func merge(_ other: Result) {
            for (key, files) in other.literalKeys { literalKeys[key, default: []].formUnion(files) }
            for (symbol, sites) in other.symbolReferences { symbolReferences[symbol, default: []] += sites }
            unreadableSites += other.unreadableSites
            suiteNameSites += other.suiteNameSites
            for (file, count) in other.applicationSupportCalls { applicationSupportCalls[file, default: 0] += count }
            applicationSupportLiteralSites += other.applicationSupportLiteralSites
            for (name, paths) in other.relativePathsByFileName {
                relativePathsByFileName[name, default: []].formUnion(paths)
            }
            scannedFileCount += other.scannedFileCount
        }
    }

    /// `LocalizedError` so XCTest shows this text, not a generic message.
    enum ScanError: LocalizedError {
        case cannotList(URL)
        var errorDescription: String? {
            switch self {
            case .cannotList(let url): return "Could not list the files in \(url.path)"
            }
        }
    }

    // MARK: Entry points

    /// Scans every `.swift` file under `sources` (recursively).
    static func scanSourcesDirectory(_ sources: URL) throws -> Result {
        let root = sources.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ScanError.cannotList(root)
        }
        var result = Result()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let resolved = url.resolvingSymlinksInPath().path
            let relative = resolved.hasPrefix(rootPath)
                ? String(resolved.dropFirst(rootPath.count))
                : url.lastPathComponent
            let data = try Data(contentsOf: url)
            result.merge(scan(source: String(decoding: data, as: UTF8.self), relativePath: relative))
        }
        return result
    }

    /// Scans one file's text. `relativePath` is only used for reporting and
    /// for the "File.swift|Name" map keys (its last component).
    static func scan(source: String, relativePath: String) -> Result {
        var parser = Parser(bytes: stripFullLineComments(Array(source.utf8)), relativePath: relativePath)
        parser.run()
        var result = parser.result
        result.scannedFileCount = 1
        return result
    }

    // MARK: Comment stripping

    /// Blanks every line whose first non-space characters are `//`, keeping
    /// the line break so line numbers stay right. Works on bytes (so a
    /// Windows line ending cannot hide a line break from it).
    static func stripFullLineComments(_ bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var lineStart = 0
        while lineStart < bytes.count {
            var lineEnd = lineStart
            while lineEnd < bytes.count && bytes[lineEnd] != Byte.newline { lineEnd += 1 }
            var first = lineStart
            while first < lineEnd && (bytes[first] == Byte.space || bytes[first] == Byte.tab) { first += 1 }
            let isCommentLine = first + 1 < lineEnd && bytes[first] == Byte.slash && bytes[first + 1] == Byte.slash
            if !isCommentLine {
                output.append(contentsOf: bytes[lineStart..<lineEnd])
            }
            if lineEnd < bytes.count { output.append(Byte.newline) }
            lineStart = lineEnd + 1
        }
        return output
    }
}

// MARK: - Byte constants

private enum Byte {
    static let newline = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let slash = UInt8(ascii: "/")
    static let quote = UInt8(ascii: "\"")
    static let backslash = UInt8(ascii: "\\")
    static let comma = UInt8(ascii: ",")
    static let openParen = UInt8(ascii: "(")
    static let closeParen = UInt8(ascii: ")")
    static let openBracket = UInt8(ascii: "[")
    static let closeBracket = UInt8(ascii: "]")
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")
    static let dot = UInt8(ascii: ".")

    static func isIdentifierStart(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
            || byte == UInt8(ascii: "_")
    }

    static func isIdentifierByte(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
    }

    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == space || byte == tab || byte == newline || byte == carriageReturn
    }
}

// MARK: - Parser

/// The text matcher behind `SettingsSourceKeyScanner.scan`. One per file.
private struct Parser {
    let bytes: [UInt8]
    let relativePath: String
    let fileName: String
    var result = SettingsSourceKeyScanner.Result()
    /// Byte offset where each line starts, for line numbers.
    private let lineStarts: [Int]

    init(bytes: [UInt8], relativePath: String) {
        self.bytes = bytes
        self.relativePath = relativePath
        self.fileName = (relativePath as NSString).lastPathComponent
        var starts = [0]
        for (index, byte) in bytes.enumerated() where byte == Byte.newline { starts.append(index + 1) }
        self.lineStarts = starts
    }

    /// What was found where a key belongs.
    private enum KeyToken {
        case literal(String)
        case symbol(String)
        case unreadable
    }

    mutating func run() {
        for anchor in occurrences(of: "AppStorage(", wordStart: true) {
            handleAppStorage(argumentsStart: anchor + "AppStorage(".utf8.count, anchor: anchor)
        }
        for anchor in occurrences(of: "forKey:", wordStart: true) {
            handleForKey(valueStart: anchor + "forKey:".utf8.count, anchor: anchor)
        }
        for anchor in occurrences(of: "settingKey:", wordStart: true) {
            handleSettingKey(valueStart: anchor + "settingKey:".utf8.count, anchor: anchor)
        }
        for anchor in occurrences(of: "UserDefaults(suiteName:", wordStart: true) {
            result.suiteNameSites.append(site(at: anchor))
        }
        let supportCalls = occurrences(of: "applicationSupportDirectory", wordStart: true, wordEnd: true)
        if !supportCalls.isEmpty {
            result.applicationSupportCalls[fileName, default: 0] += supportCalls.count
        }
        findApplicationSupportLiterals()
        if !result.literalKeys.isEmpty || !result.symbolReferences.isEmpty || !result.unreadableSites.isEmpty {
            result.relativePathsByFileName[fileName, default: []].insert(relativePath)
        }
    }

    // MARK: Call-site handlers

    private mutating func handleAppStorage(argumentsStart: Int, anchor: Int) {
        var position = skipWhitespace(from: argumentsStart)
        // `@AppStorage(wrappedValue: <expression>, "key")`: step over the
        // first argument to the key.
        if startsWith("wrappedValue:", at: position) {
            guard let afterComma = indexAfterTopLevelComma(from: position + "wrappedValue:".utf8.count) else {
                result.unreadableSites.append(site(at: anchor))
                return
            }
            position = skipWhitespace(from: afterComma)
        }
        record(parseKeyToken(at: position).token, anchor: anchor)
    }

    private mutating func handleForKey(valueStart: Int, anchor: Int) {
        // A Swift dictionary's `removeValue(forKey:)`, not a setting.
        if precededBy("removeValue(", anchor: anchor) { return }
        let position = skipWhitespace(from: valueStart)
        // `forKey: .name` is a `Codable` coding key, not a setting.
        if position < bytes.count, bytes[position] == Byte.dot { return }
        let (token, end) = parseKeyToken(at: position)
        // `value(forKey: "title", in: tags)` is a tag look-up, not a setting.
        if case .literal = token, followedByArgumentLabel("in:", from: end) { return }
        record(token, anchor: anchor)
    }

    private mutating func handleSettingKey(valueStart: Int, anchor: Int) {
        let position = skipWhitespace(from: valueStart)
        let (token, _) = parseKeyToken(at: position)
        // `settingKey: String` is the parameter's declaration.
        if case .symbol("String") = token { return }
        record(token, anchor: anchor)
    }

    private mutating func record(_ token: KeyToken, anchor: Int) {
        switch token {
        case .literal(let key):
            result.literalKeys[key, default: []].insert(relativePath)
        case .symbol(let name):
            result.symbolReferences["\(fileName)|\(name)", default: []].append(site(at: anchor))
        case .unreadable:
            result.unreadableSites.append(site(at: anchor))
        }
    }

    private mutating func findApplicationSupportLiterals() {
        for (index, start) in lineStarts.enumerated() {
            let end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : bytes.count
            guard start < end else { continue }
            let line = String(decoding: bytes[start..<end], as: UTF8.self)
            guard let range = line.range(of: "Application Support") else { continue }
            let before = line[line.startIndex..<range.lowerBound]
            let after = line[range.upperBound...]
            if before.contains("\"") && after.contains("\"") {
                result.applicationSupportLiteralSites.append(site(at: start))
            }
        }
    }

    // MARK: Token parsing

    /// Reads a plain string literal or a plain dotted name at `position`,
    /// which must be followed (after spaces) by `,` or `)` to count. Anything
    /// else is `.unreadable`. Returns where the token ended.
    private func parseKeyToken(at position: Int) -> (token: KeyToken, end: Int) {
        guard position < bytes.count else { return (.unreadable, position) }
        if bytes[position] == Byte.quote {
            // `"""` starts a multi-line string: not a plain key.
            if startsWith("\"\"\"", at: position) { return (.unreadable, position) }
            var index = position + 1
            var content: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                // Any escape, including `\(` interpolation, makes the key
                // something other than plain text.
                if byte == Byte.backslash || byte == Byte.newline { return (.unreadable, index) }
                if byte == Byte.quote { break }
                content.append(byte)
                index += 1
            }
            guard index < bytes.count else { return (.unreadable, index) }
            let end = index + 1
            guard endsArgument(from: end) else { return (.unreadable, end) }
            return (.literal(String(decoding: content, as: UTF8.self)), end)
        }
        if Byte.isIdentifierStart(bytes[position]) {
            var index = position
            while index < bytes.count {
                guard Byte.isIdentifierStart(bytes[index]) else { break }
                while index < bytes.count && Byte.isIdentifierByte(bytes[index]) { index += 1 }
                if index + 1 < bytes.count && bytes[index] == Byte.dot && Byte.isIdentifierStart(bytes[index + 1]) {
                    index += 1
                    continue
                }
                break
            }
            let name = String(decoding: bytes[position..<index], as: UTF8.self)
            guard endsArgument(from: index) else { return (.unreadable, index) }
            return (.symbol(name), index)
        }
        return (.unreadable, position)
    }

    /// True when the next non-space byte is `,` or `)`.
    private func endsArgument(from position: Int) -> Bool {
        let next = skipWhitespace(from: position)
        guard next < bytes.count else { return false }
        return bytes[next] == Byte.comma || bytes[next] == Byte.closeParen
    }

    /// True when the text after `position` is `, <label>`.
    private func followedByArgumentLabel(_ label: String, from position: Int) -> Bool {
        let comma = skipWhitespace(from: position)
        guard comma < bytes.count, bytes[comma] == Byte.comma else { return false }
        return startsWith(label, at: skipWhitespace(from: comma + 1))
    }

    /// Steps over one argument expression, tracking brackets and string
    /// literals, and returns the index just after the comma that ends it.
    /// `nil` if the argument list closes first.
    private func indexAfterTopLevelComma(from start: Int) -> Int? {
        var depth = 0
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == Byte.quote {
                index += 1
                while index < bytes.count && bytes[index] != Byte.quote && bytes[index] != Byte.newline {
                    index += bytes[index] == Byte.backslash ? 2 : 1
                }
            } else if byte == Byte.openParen || byte == Byte.openBracket || byte == Byte.openBrace {
                depth += 1
            } else if byte == Byte.closeParen || byte == Byte.closeBracket || byte == Byte.closeBrace {
                if depth == 0 { return nil }
                depth -= 1
            } else if byte == Byte.comma && depth == 0 {
                return index + 1
            }
            index += 1
        }
        return nil
    }

    // MARK: Low-level helpers

    private func skipWhitespace(from position: Int) -> Int {
        var index = position
        while index < bytes.count && Byte.isWhitespace(bytes[index]) { index += 1 }
        return index
    }

    private func startsWith(_ text: String, at position: Int) -> Bool {
        let needle = Array(text.utf8)
        guard position >= 0, position + needle.count <= bytes.count else { return false }
        return bytes[position..<(position + needle.count)].elementsEqual(needle)
    }

    /// True when `text` ends right before `anchor`, ignoring spaces between.
    private func precededBy(_ text: String, anchor: Int) -> Bool {
        var index = anchor - 1
        while index >= 0 && Byte.isWhitespace(bytes[index]) { index -= 1 }
        let needle = Array(text.utf8)
        let start = index - needle.count + 1
        return start >= 0 && bytes[start...index].elementsEqual(needle)
    }

    /// Every offset where `text` occurs. `wordStart` requires the byte before
    /// not to be part of a name (so `xforKey:` does not count); `wordEnd`
    /// requires the same of the byte after.
    private func occurrences(of text: String, wordStart: Bool, wordEnd: Bool = false) -> [Int] {
        let needle = Array(text.utf8)
        guard let first = needle.first, needle.count <= bytes.count else { return [] }
        var found: [Int] = []
        var index = 0
        while index + needle.count <= bytes.count {
            if bytes[index] == first && bytes[index..<(index + needle.count)].elementsEqual(needle) {
                let startOK = !wordStart || index == 0 || !Byte.isIdentifierByte(bytes[index - 1])
                let endIndex = index + needle.count
                let endOK = !wordEnd || endIndex >= bytes.count || !Byte.isIdentifierByte(bytes[endIndex])
                if startOK && endOK { found.append(index) }
                index += needle.count
            } else {
                index += 1
            }
        }
        return found
    }

    private func lineNumber(at offset: Int) -> Int {
        // The number of line starts at or before `offset`.
        var low = 0
        var high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private func site(at offset: Int) -> SettingsSourceKeyScanner.Site {
        let line = lineNumber(at: offset)
        let start = lineStarts[line - 1]
        var end = start
        while end < bytes.count && bytes[end] != Byte.newline { end += 1 }
        let text = String(decoding: bytes[start..<end], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        return SettingsSourceKeyScanner.Site(file: relativePath, line: line, excerpt: String(text.prefix(160)))
    }
}

// MARK: - SettingsKeyScanMap

/// What each NAME used as a settings key stands for, and the other fixed
/// lists the tripwire test checks against. Test-only.
///
/// Map keys are "<file name>|<name as written>", e.g.
/// "MakeMKVSettingsTab.swift|MakeMKVConsentStore.Keys.enabled".
enum SettingsKeyScanMap {

    /// What a name at a settings call site stands for.
    enum Target: Equatable, Sendable {
        /// It is the settings key `key`.
        case key(String)
        /// It is not a settings key at all (a dictionary, a cache, a
        /// translation look-up, a parameter), for `reason`.
        case notUserDefaults(reason: String)
        /// It IS a settings key, but not one fixed name: a variable in the
        /// settings export/import engine holding a key it took from
        /// `SettingsKeyRegistry` at run time, so only ever one the registry
        /// allows (#506 commit 5). The registry itself is what decides those
        /// keys, so there is nothing to map. `SettingsKeyCoverageTests` checks
        /// this is only used inside `Sources/ConverterEngine/Settings/`.
        case keyFromRegistry(reason: String)
    }

    static let symbols: [String: Target] = [
        // Analytics: private constants built as "\(keyPrefix)…" with
        // keyPrefix "analytics_". Private, so no compiler check (blind spot 3).
        "AnalyticsEngine.swift|Self.enabledKey": .key("analytics_enabled"),
        "AnalyticsEngine.swift|Self.anonymousIdKey": .key("analytics_anonymousId"),
        "AnalyticsEngine.swift|Self.endpointURLKey": .key("analytics_endpointURL"),

        "AppViewModel.swift|ParallelEncoder.maxConcurrentJobsDefaultsKey": .key("parallelMaxConcurrentJobs"),
        "AppViewModel.swift|settingKey": .notUserDefaults(
            reason: "A parameter of the notification helpers. Every caller passes a plain string, "
                + "which the `settingKey:` pattern reads at the call site."
        ),

        "AutoTagSettings.swift|Keys.enabled": .key("autotag.enabled"),
        "AutoTagSettings.swift|Keys.writeNFO": .key("autotag.writeNFO"),
        "AutoTagSettingsSection.swift|AutoTagSettingsStore.Keys.enabled": .key("autotag.enabled"),
        "AutoTagSettingsSection.swift|AutoTagSettingsStore.Keys.writeNFO": .key("autotag.writeNFO"),
        "FFmpegPreviewView.swift|AutoTagSettingsStore.Keys.enabled": .key("autotag.enabled"),

        "CloudStorageUploader.swift|userDefaultsKey": .key("cloudStorageProfiles"),
        // A private copy: `private static let userDefaultsKey =
        // CloudStorageProfileStore.userDefaultsKey`.
        "CloudStorageView.swift|Self.userDefaultsKey": .key("cloudStorageProfiles"),

        "DiscIdentifyView.swift|MeedyaDBConfigStore.Keys.enabled": .key("meedyadb.enabled"),
        "DiscIdentifyView.swift|MeedyaDBConfigStore.Keys.baseURL": .key("meedyadb.baseURL"),

        "EntitlementGating.swift|Self.cachedLevelKey": .key("Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel"),
        "EntitlementGating.swift|Self.cacheExpiryKey": .key("Ltd.MWBMpartners.MeedyaConverter.entitlementCacheExpiry"),

        // App-internal; pinned by `SettingsRegistryAppConstantsTests`.
        "HardwareAccelerationPreference.swift|defaultsKey": .key("useHardwareAcceleration"),

        "KeyboardShortcutManager.swift|Self.storageKey": .key("keyboard_shortcuts"),

        "LocalizationManager.swift|LocalizationManager.languageKey": .key("com.mwbm.meedyaconverter.selectedLanguage"),
        "LocalizationManager.swift|key": .notUserDefaults(
            reason: "`Bundle.localizedString(forKey:value:table:)`: a translation look-up."
        ),

        "MakeMKVAccess.swift|Keys.enabled": .key("makemkv.enabled"),
        "MakeMKVAccess.swift|Keys.termsAcknowledgement": .key("makemkv.termsAcknowledgement"),
        "MakeMKVAccess.swift|Keys.binaryPath": .key("makemkv.binaryPath"),
        "MakeMKVRipView.swift|MakeMKVConsentStore.Keys.enabled": .key("makemkv.enabled"),
        "MakeMKVRipView.swift|MakeMKVConsentStore.Keys.termsAcknowledgement": .key("makemkv.termsAcknowledgement"),
        "MakeMKVRipView.swift|MakeMKVConsentStore.Keys.binaryPath": .key("makemkv.binaryPath"),
        "MakeMKVRipView.swift|MeedyaDBConfigStore.Keys.enabled": .key("meedyadb.enabled"),
        "MakeMKVRipView.swift|MeedyaDBConfigStore.Keys.baseURL": .key("meedyadb.baseURL"),
        "MakeMKVSettingsTab.swift|MakeMKVConsentStore.Keys.enabled": .key("makemkv.enabled"),
        "MakeMKVSettingsTab.swift|MakeMKVConsentStore.Keys.termsAcknowledgement": .key("makemkv.termsAcknowledgement"),
        "MakeMKVSettingsTab.swift|MakeMKVConsentStore.Keys.binaryPath": .key("makemkv.binaryPath"),

        "MediaServerCredentialStore.swift|legacyDefaultsKey": .key("mediaServerAPIKey"),
        // #506 commit 5: the "is the old media server key still here?" check.
        "SettingsCredentialNeeds.swift|MediaServerCredentialStore.legacyDefaultsKey": .key("mediaServerAPIKey"),
        // #506 commit 5: the settings engine's only two writes (`set` and
        // `removeObject`), whose key comes from the registry at run time.
        "SettingsDomain.swift|key": .keyFromRegistry(
            reason: "SettingsDomain.write/remove: every key is one SettingsKeyRegistry allows, checked by "
                + "SettingsImporter.apply before its first write."
        ),
        "MediaServerSettingsView.swift|MediaServerCredentialStore.legacyDefaultsKey": .key("mediaServerAPIKey"),

        "MeedyaDBAccess.swift|Keys.enabled": .key("meedyadb.enabled"),
        "MeedyaDBAccess.swift|Keys.baseURL": .key("meedyadb.baseURL"),
        "MeedyaDBAccess.swift|Keys.submissionMode": .key("meedyadb.submissionMode"),
        "MeedyaDBSettingsTab.swift|MeedyaDBConfigStore.Keys.enabled": .key("meedyadb.enabled"),
        "MeedyaDBSettingsTab.swift|MeedyaDBConfigStore.Keys.baseURL": .key("meedyadb.baseURL"),
        "MeedyaDBSettingsTab.swift|MeedyaDBConfigStore.Keys.submissionMode": .key("meedyadb.submissionMode"),

        "ParallelEncodingView.swift|ParallelEncoder.maxConcurrentJobsDefaultsKey": .key("parallelMaxConcurrentJobs"),

        // App-internal; pinned by `SettingsRegistryAppConstantsTests`.
        "PostEncodeActionsView.swift|Self.userDefaultsKey": .key("postEncodeActionChain"),
        "PostEncodeActionsView.swift|userDefaultsKey": .key("postEncodeActionChain"),

        "RenderFarmConfigurationLoader.swift|Keys.allowInsecureTransports": .key("renderFarm.allowInsecureTransports"),
        "RenderFarmConfigurationLoader.swift|Keys.insecureAcknowledgement": .key("renderFarm.insecureAcknowledgement"),
        "RenderFarmConfigurationLoader.swift|Keys.discoveryIntervalSeconds": .key("renderFarm.discoveryIntervalSeconds"),
        "RenderFarmConfigurationLoader.swift|Keys.chunkSizeMiB": .key("renderFarm.chunkSizeMiB"),
        "RenderFarmConfigurationLoader.swift|Keys.agentsJSON": .key("renderFarm.agentsJSON"),
        "RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.allowInsecureTransports": .key("renderFarm.allowInsecureTransports"),
        "RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.insecureAcknowledgement": .key("renderFarm.insecureAcknowledgement"),
        "RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.discoveryIntervalSeconds": .key("renderFarm.discoveryIntervalSeconds"),
        "RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.chunkSizeMiB": .key("renderFarm.chunkSizeMiB"),
        "RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.agentsJSON": .key("renderFarm.agentsJSON"),

        "SFTPUploader.swift|userDefaultsKey": .key("sftpProfiles"),
        // A private copy: `private static let userDefaultsKey =
        // SFTPProfileStore.userDefaultsKey`.
        "SFTPSettingsView.swift|Self.userDefaultsKey": .key("sftpProfiles"),

        "ThumbnailCache.swift|key": .notUserDefaults(
            reason: "An `NSCache` of thumbnails (`object(forKey:)`, `setObject(_:forKey:cost:)`)."
        ),
    ]

    /// Plain-string keys found at settings call sites that are NOT ours, and
    /// so deliberately have no registry entry. The test fails if one of
    /// these ever appears in the registry, or stops being found.
    static let foreignLiteralKeys: [String: String] = [
        "GloballyEnabled": "Apple's own Stage Manager setting, read (never written) from the "
            + "com.apple.WindowManager domain by StageManagerOptimizer.swift.",
    ]

    /// Files allowed to open a different settings domain with
    /// `UserDefaults(suiteName:`. Any other file doing so fails the test,
    /// because keys there would be outside the app's own settings.
    static let allowedSuiteNameFiles: [String: String] = [
        "StageManagerOptimizer.swift": "Reads Apple's com.apple.WindowManager domain, read-only "
            + "(GloballyEnabled).",
        "AutoTagSettings.swift": "Opens a per-test suite only when tests pass a suite name; the app "
            + "passes nil and reads its own standard settings.",
    ]

    /// Files allowed to spell "Application Support" out in a string, rather
    /// than asking macOS for the folder. Any other file doing so fails the
    /// test, because a store built that way would dodge the
    /// `applicationSupportDirectory` check.
    static let allowedApplicationSupportLiteralFiles: [String: String] = [
        "PlatformSupport.swift": "`PlatformPaths.applicationDataDirectory` returns the folder's "
            + "name as text for display; nothing is stored through it.",
        "GitProfileSync.swift": "A fallback path for the same git cache store "
            + "(TeamProfiles/GitCache/) when macOS cannot give the folder.",
    ]
}
