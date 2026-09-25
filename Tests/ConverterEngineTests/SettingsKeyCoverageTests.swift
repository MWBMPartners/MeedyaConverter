// ============================================================================
// MeedyaConverter — SettingsKeyCoverageTests (Issue #506 commit 4)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// THE TRIPWIRE. Settings export (#506) is an allow-list: only settings with
// a decision in `SettingsKeyRegistry` can ever travel. The owner's fear is a
// NEW setting added somewhere (say a new API key in a new `@AppStorage`)
// that nobody thinks about. These tests read every `.swift` file under
// `Sources/` (via `SettingsSourceKeyScanner`) and FAIL, naming the setting,
// when:
//   - a setting is used in the code but has no decision in the registry;
//   - the registry lists a setting nothing in the code uses any more (a
//     typo, or a removed feature);
//   - a settings call site uses a key the scanner cannot read as text (for
//     example one built at run time), so it cannot be checked;
//   - a name used as a key is not in `SettingsKeyScanMap`, or the map has a
//     name the code no longer uses;
//   - a new settings domain is opened with `UserDefaults(suiteName:`;
//   - a file keeps data in Application Support without a file-store
//     decision.
//
// How it finds `Sources/`: from this file's own path (`#filePath`), three
// levels up: Tests/ConverterEngineTests/<this file> → the repository root.
// CI runs `swift test` from a checkout, where `#filePath` is the absolute
// path of this file in that checkout, so `Sources/` is right there. If the
// folder cannot be found the tests FAIL (they never quietly pass on an
// empty scan): `test_sourcesFolderIsFoundAndScanned` checks it, and every
// other test calls the same `scanRealSources()`, which throws.
//
// The scanner's blind spots are listed at the top of
// `SettingsSourceKeyScanner.swift`. The secrets are pinned to "never" by
// `SettingsKeyRegistrySentinelTests`, which does not use this scan at all.
//
// Only public API is used (`import ConverterEngine`, no `@testable`),
// matching the policy at the top of `ConverterEngineTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class SettingsKeyCoverageTests: XCTestCase {

    // MARK: - Finding and scanning Sources/

    /// The repository's `Sources/` folder, worked out from this file's path.
    /// `URL(fileURLWithPath:)` also copes with a relative `#filePath` (a
    /// hand-run compile that was given relative paths), resolving it against
    /// the current folder.
    private static func sourcesDirectory(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()   // Tests/ConverterEngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Sources", isDirectory: true)
    }

    /// `LocalizedError`, not just `Error`: XCTest reports a thrown error by
    /// its `localizedDescription`, which for a plain `Error` is only "The
    /// operation couldn't be completed" (seen when this was first tried).
    private struct SourcesNotFound: LocalizedError {
        let path: String
        var errorDescription: String? {
            "Sources/ was not found at \(path). The tripwire cannot check anything without it."
        }
    }

    /// Scans the real `Sources/`. Throws (failing the test) if the folder is
    /// missing or suspiciously empty, so a wrong path can never pass.
    private func scanRealSources() throws -> SettingsSourceKeyScanner.Result {
        let sources = Self.sourcesDirectory()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sources.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SourcesNotFound(path: sources.path)
        }
        let result = try SettingsSourceKeyScanner.scanSourcesDirectory(sources)
        // There are about 340 Swift files. Far fewer means the wrong folder.
        guard result.scannedFileCount >= 100 else {
            throw SourcesNotFound(path: sources.path + " (only \(result.scannedFileCount) .swift files)")
        }
        return result
    }

    /// Formats "key (in a.swift, b.swift)" lines for failure messages.
    private func describe(_ keys: [String], in found: [String: Set<String>]) -> String {
        keys.sorted().map { key in
            let files = found[key].map { $0.sorted().joined(separator: ", ") } ?? "?"
            return "  - \(key)  (in \(files))"
        }.joined(separator: "\n")
    }

    // MARK: - The folder is really there

    func test_sourcesFolderIsFoundAndScanned() throws {
        let result = try scanRealSources()
        XCTAssertGreaterThanOrEqual(result.scannedFileCount, 100)
        // A handful of keys that must be found if the scan works at all,
        // one per way of writing a key (literal @AppStorage, literal
        // forKey:, a settingKey: argument, a mapped constant).
        let found = result.allKeys(resolvingWith: SettingsKeyScanMap.symbols)
        for key in ["appearanceMode", "savedPipelines", "emailOnFailure", "makemkv.enabled"] {
            XCTAssertNotNil(found[key], "The scan did not find \(key); the scanner is broken.")
        }
    }

    // MARK: - The two tripwires

    /// FAILS for every setting used in `Sources/` that has no decision.
    func test_everySettingFoundInSourcesHasADecision() throws {
        let result = try scanRealSources()
        let found = result.allKeys(resolvingWith: SettingsKeyScanMap.symbols)
        let undecided = Set(found.keys)
            .subtracting(SettingsKeyRegistry.allKeys)
            .subtracting(SettingsKeyScanMap.foreignLiteralKeys.keys)
        XCTAssertTrue(
            undecided.isEmpty,
            """
            \(undecided.count) setting(s) are used in Sources/ but have NO decision in \
            SettingsKeyRegistry. Add each one to SettingsKeyRegistry.swift as .allowed, \
            .thisMac or .never (when unsure, .never), with a plain-English label and reason:
            \(describe(Array(undecided), in: found))
            """
        )
    }

    /// FAILS for every registry entry nothing in `Sources/` uses any more.
    func test_everyRegistryEntryIsStillUsedInSources() throws {
        let result = try scanRealSources()
        let found = result.allKeys(resolvingWith: SettingsKeyScanMap.symbols)
        let stale = SettingsKeyRegistry.allKeys.subtracting(found.keys)
        XCTAssertTrue(
            stale.isEmpty,
            """
            \(stale.count) SettingsKeyRegistry entr(y/ies) are not used anywhere in Sources/ \
            (comment-only lines do not count). Either the setting was removed (delete the \
            entry) or the entry has a typo:
            \(stale.sorted().map { "  - \($0)" }.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Keys the scan cannot check

    /// A key built at run time, or written as anything but a plain string or
    /// a plain name, cannot be checked, so it fails here instead of being
    /// silently missed.
    func test_noSettingsCallSiteHasAKeyTheScannerCannotRead() throws {
        let result = try scanRealSources()
        XCTAssertTrue(
            result.unreadableSites.isEmpty,
            """
            These settings call sites use a key the scanner cannot read (an interpolated or \
            multi-line string, or an expression). Use a plain string or a named constant, so \
            the key can be checked against SettingsKeyRegistry:
            \(result.unreadableSites.sorted().map { "  - \($0)" }.joined(separator: "\n"))
            """
        )
    }

    /// Every name used as a key must be in `SettingsKeyScanMap.symbols`.
    func test_everyNameUsedAsAKeyIsMapped() throws {
        let result = try scanRealSources()
        let unmapped = Set(result.symbolReferences.keys).subtracting(SettingsKeyScanMap.symbols.keys)
        let lines = unmapped.sorted().map { symbol -> String in
            let sites = result.symbolReferences[symbol, default: []].sorted().map(\.description)
            return "  - \(symbol)\n      " + sites.joined(separator: "\n      ")
        }
        XCTAssertTrue(
            unmapped.isEmpty,
            """
            These names are used as settings keys but SettingsKeyScanMap.symbols does not say \
            which key they stand for (or that they are not settings keys). Add each one:
            \(lines.joined(separator: "\n"))
            """
        )
    }

    /// A map entry the code no longer uses is out of date: remove it.
    func test_everyMapEntryIsStillUsed() throws {
        let result = try scanRealSources()
        let unused = Set(SettingsKeyScanMap.symbols.keys).subtracting(result.symbolReferences.keys)
        XCTAssertTrue(
            unused.isEmpty,
            "SettingsKeyScanMap.symbols has entries no code uses any more:\n"
                + unused.sorted().map { "  - \($0)" }.joined(separator: "\n")
        )
    }

    /// "File.swift|Name" is only unambiguous while no two files with a
    /// settings call share a name.
    func test_fileNamesUsedByTheScanAreUnambiguous() throws {
        let result = try scanRealSources()
        let ambiguous = result.relativePathsByFileName.filter { $0.value.count > 1 }
        XCTAssertTrue(
            ambiguous.isEmpty,
            "Two or more files with settings calls share a name, so SettingsKeyScanMap entries "
                + "would be ambiguous. Rename one, or change the scanner to use relative paths: "
                + "\(ambiguous)"
        )
    }

    /// Plain-string keys that belong to someone else must stay out of the
    /// registry, and must still be found (or be removed from the list).
    func test_foreignKeysAreKnownAndNotInTheRegistry() throws {
        let result = try scanRealSources()
        for (key, reason) in SettingsKeyScanMap.foreignLiteralKeys {
            XCTAssertNil(
                SettingsKeyRegistry.entry(for: key),
                "\(key) is not ours (\(reason)) and must not be in SettingsKeyRegistry."
            )
            XCTAssertNotNil(
                result.literalKeys[key],
                "\(key) is listed as a foreign key but no code uses it any more; remove it from "
                    + "SettingsKeyScanMap.foreignLiteralKeys."
            )
        }
    }

    // MARK: - Other settings domains

    func test_otherSettingsDomainsAreOnlyOpenedWhereExpected() throws {
        let result = try scanRealSources()
        let filesOpeningASuite = Set(result.suiteNameSites.map { ($0.file as NSString).lastPathComponent })
        let unexpected = result.suiteNameSites.filter {
            SettingsKeyScanMap.allowedSuiteNameFiles[($0.file as NSString).lastPathComponent] == nil
        }
        XCTAssertTrue(
            unexpected.isEmpty,
            """
            UserDefaults(suiteName:) opens a different settings domain, whose keys would be \
            outside the app's own settings and outside this check. If that is intended, add the \
            file to SettingsKeyScanMap.allowedSuiteNameFiles with the reason:
            \(unexpected.sorted().map { "  - \($0)" }.joined(separator: "\n"))
            """
        )
        let stale = Set(SettingsKeyScanMap.allowedSuiteNameFiles.keys).subtracting(filesOpeningASuite)
        XCTAssertTrue(stale.isEmpty, "allowedSuiteNameFiles lists files that no longer open a suite: \(stale.sorted())")
    }

    // MARK: - Application Support file stores

    /// Every file that asks macOS for the Application Support folder must
    /// have one file-store decision per time it does so.
    func test_everyApplicationSupportStoreHasADecision() throws {
        let result = try scanRealSources()
        var decided: [String: Int] = [:]
        for store in SettingsKeyRegistry.fileStores { decided[store.sourceFile, default: 0] += 1 }
        XCTAssertEqual(
            result.applicationSupportCalls, decided,
            """
            The files that use applicationSupportDirectory (left, with how many times) do not \
            match SettingsKeyRegistry.fileStores (right, by sourceFile). A new file or folder in \
            Application Support needs a SettingsFileStoreEntry saying whether it is exported \
            (almost always: never, with the reason).
            """
        )
    }

    /// A store could also be built from the folder's name typed out as text,
    /// dodging the check above. Only the files listed may do that.
    func test_applicationSupportIsOnlySpelledOutWhereExpected() throws {
        let result = try scanRealSources()
        let unexpected = result.applicationSupportLiteralSites.filter {
            SettingsKeyScanMap.allowedApplicationSupportLiteralFiles[($0.file as NSString).lastPathComponent] == nil
        }
        XCTAssertTrue(
            unexpected.isEmpty,
            """
            These lines spell out "Application Support" in a string instead of asking macOS for \
            the folder. If one builds a new store, it needs a SettingsKeyRegistry.fileStores \
            entry; then add the file to allowedApplicationSupportLiteralFiles with the reason:
            \(unexpected.sorted().map { "  - \($0)" }.joined(separator: "\n"))
            """
        )
        let filesSpellingItOut = Set(result.applicationSupportLiteralSites.map { ($0.file as NSString).lastPathComponent })
        let stale = Set(SettingsKeyScanMap.allowedApplicationSupportLiteralFiles.keys).subtracting(filesSpellingItOut)
        XCTAssertTrue(stale.isEmpty, "allowedApplicationSupportLiteralFiles lists files that no longer do this: \(stale.sorted())")
    }

    // MARK: - Map entries the compiler can check

    /// For every PUBLIC engine constant, the map must say exactly what the
    /// constant really is. If a constant's text changes, this fails at once
    /// (private constants cannot be checked this way; see the scanner's
    /// blind spot 3).
    ///
    /// The two `…View.swift|Self.userDefaultsKey` rows are private copies in
    /// the app (`SFTPSettingsView`, `CloudStorageView`), each written today as
    /// `= <engine store>.userDefaultsKey`. This compares the map with that
    /// engine constant; it cannot see the private copy itself, so it would
    /// not notice if a copy were changed to a different string.
    func test_publicKeyConstantsMatchTheScanMap() {
        let checks: [(mapKey: String, constant: String)] = [
            ("AppViewModel.swift|ParallelEncoder.maxConcurrentJobsDefaultsKey", ParallelEncoder.maxConcurrentJobsDefaultsKey),
            ("ParallelEncodingView.swift|ParallelEncoder.maxConcurrentJobsDefaultsKey", ParallelEncoder.maxConcurrentJobsDefaultsKey),
            ("AutoTagSettings.swift|Keys.enabled", AutoTagSettingsStore.Keys.enabled),
            ("AutoTagSettings.swift|Keys.writeNFO", AutoTagSettingsStore.Keys.writeNFO),
            ("AutoTagSettingsSection.swift|AutoTagSettingsStore.Keys.enabled", AutoTagSettingsStore.Keys.enabled),
            ("AutoTagSettingsSection.swift|AutoTagSettingsStore.Keys.writeNFO", AutoTagSettingsStore.Keys.writeNFO),
            ("FFmpegPreviewView.swift|AutoTagSettingsStore.Keys.enabled", AutoTagSettingsStore.Keys.enabled),
            ("CloudStorageUploader.swift|userDefaultsKey", CloudStorageProfileStore.userDefaultsKey),
            ("CloudStorageView.swift|Self.userDefaultsKey", CloudStorageProfileStore.userDefaultsKey),
            ("SFTPUploader.swift|userDefaultsKey", SFTPProfileStore.userDefaultsKey),
            ("SFTPSettingsView.swift|Self.userDefaultsKey", SFTPProfileStore.userDefaultsKey),
            ("DiscIdentifyView.swift|MeedyaDBConfigStore.Keys.enabled", MeedyaDBConfigStore.Keys.enabled),
            ("DiscIdentifyView.swift|MeedyaDBConfigStore.Keys.baseURL", MeedyaDBConfigStore.Keys.baseURL),
            ("MakeMKVRipView.swift|MeedyaDBConfigStore.Keys.enabled", MeedyaDBConfigStore.Keys.enabled),
            ("MakeMKVRipView.swift|MeedyaDBConfigStore.Keys.baseURL", MeedyaDBConfigStore.Keys.baseURL),
            ("MeedyaDBAccess.swift|Keys.enabled", MeedyaDBConfigStore.Keys.enabled),
            ("MeedyaDBAccess.swift|Keys.baseURL", MeedyaDBConfigStore.Keys.baseURL),
            ("MeedyaDBAccess.swift|Keys.submissionMode", MeedyaDBConfigStore.Keys.submissionMode),
            ("MeedyaDBSettingsTab.swift|MeedyaDBConfigStore.Keys.enabled", MeedyaDBConfigStore.Keys.enabled),
            ("MeedyaDBSettingsTab.swift|MeedyaDBConfigStore.Keys.baseURL", MeedyaDBConfigStore.Keys.baseURL),
            ("MeedyaDBSettingsTab.swift|MeedyaDBConfigStore.Keys.submissionMode", MeedyaDBConfigStore.Keys.submissionMode),
            ("MakeMKVAccess.swift|Keys.enabled", MakeMKVConsentStore.Keys.enabled),
            ("MakeMKVAccess.swift|Keys.termsAcknowledgement", MakeMKVConsentStore.Keys.termsAcknowledgement),
            ("MakeMKVAccess.swift|Keys.binaryPath", MakeMKVConsentStore.Keys.binaryPath),
            ("MakeMKVRipView.swift|MakeMKVConsentStore.Keys.enabled", MakeMKVConsentStore.Keys.enabled),
            ("MakeMKVRipView.swift|MakeMKVConsentStore.Keys.termsAcknowledgement", MakeMKVConsentStore.Keys.termsAcknowledgement),
            ("MakeMKVRipView.swift|MakeMKVConsentStore.Keys.binaryPath", MakeMKVConsentStore.Keys.binaryPath),
            ("MakeMKVSettingsTab.swift|MakeMKVConsentStore.Keys.enabled", MakeMKVConsentStore.Keys.enabled),
            ("MakeMKVSettingsTab.swift|MakeMKVConsentStore.Keys.termsAcknowledgement", MakeMKVConsentStore.Keys.termsAcknowledgement),
            ("MakeMKVSettingsTab.swift|MakeMKVConsentStore.Keys.binaryPath", MakeMKVConsentStore.Keys.binaryPath),
            ("MediaServerCredentialStore.swift|legacyDefaultsKey", MediaServerCredentialStore.legacyDefaultsKey),
            ("MediaServerSettingsView.swift|MediaServerCredentialStore.legacyDefaultsKey", MediaServerCredentialStore.legacyDefaultsKey),
            ("RenderFarmConfigurationLoader.swift|Keys.allowInsecureTransports", RenderFarmConfigurationLoader.Keys.allowInsecureTransports),
            ("RenderFarmConfigurationLoader.swift|Keys.insecureAcknowledgement", RenderFarmConfigurationLoader.Keys.insecureAcknowledgement),
            ("RenderFarmConfigurationLoader.swift|Keys.discoveryIntervalSeconds", RenderFarmConfigurationLoader.Keys.discoveryIntervalSeconds),
            ("RenderFarmConfigurationLoader.swift|Keys.chunkSizeMiB", RenderFarmConfigurationLoader.Keys.chunkSizeMiB),
            ("RenderFarmConfigurationLoader.swift|Keys.agentsJSON", RenderFarmConfigurationLoader.Keys.agentsJSON),
            ("RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.allowInsecureTransports", RenderFarmConfigurationLoader.Keys.allowInsecureTransports),
            ("RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.insecureAcknowledgement", RenderFarmConfigurationLoader.Keys.insecureAcknowledgement),
            ("RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.discoveryIntervalSeconds", RenderFarmConfigurationLoader.Keys.discoveryIntervalSeconds),
            ("RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.chunkSizeMiB", RenderFarmConfigurationLoader.Keys.chunkSizeMiB),
            ("RenderFarmSettingsTab.swift|RenderFarmConfigurationLoader.Keys.agentsJSON", RenderFarmConfigurationLoader.Keys.agentsJSON),
        ]
        for check in checks {
            XCTAssertEqual(
                SettingsKeyScanMap.symbols[check.mapKey], .key(check.constant),
                "SettingsKeyScanMap says \(check.mapKey) is something other than its real value \"\(check.constant)\"."
            )
        }
    }

    // MARK: - The scanner itself (synthetic source)

    /// Feeds the scanner made-up code and checks it finds what it should.
    /// This is what proves the tripwire would actually notice a new key.
    func test_scannerFindsKeysWrittenEveryWay() {
        let source = """
        struct Planted {
            @AppStorage("brandNewApiKey") private var apiKey = ""
            @AppStorage(wrappedValue: 1, "with.wrappedValue") private var count
            @AppStorage(wrappedValue: [1, 2].count, "with.expression") private var other
            @AppStorage(SomeStore.Keys.named) private var named = false
            func f(defaults: UserDefaults) {
                defaults.set(true, forKey: "x.y")
                _ = defaults.string(
                    forKey: "split.over.lines"
                )
                defaults.removeObject(forKey: "removed.key")
                _ = defaults.bool(forKey: Self.privateKey)
                notify(settingKey: "via.settingKey", title: "t")
                let other = UserDefaults(suiteName: "group.example")
                _ = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                let path = "~/Library/Application Support/Somewhere"
                let trailing = 1 // defaults.set(1, forKey: "trailing.comment")
            }
        }
        """
        let result = SettingsSourceKeyScanner.scan(source: source, relativePath: "Folder/Planted.swift")
        for key in ["brandNewApiKey", "with.wrappedValue", "with.expression", "x.y", "split.over.lines",
                    "removed.key", "via.settingKey", "trailing.comment"] {
            XCTAssertNotNil(result.literalKeys[key], "The scanner missed \(key).")
        }
        XCTAssertEqual(result.literalKeys["x.y"], ["Folder/Planted.swift"])
        XCTAssertNotNil(result.symbolReferences["Planted.swift|SomeStore.Keys.named"])
        XCTAssertNotNil(result.symbolReferences["Planted.swift|Self.privateKey"])
        XCTAssertEqual(result.suiteNameSites.count, 1)
        XCTAssertEqual(result.applicationSupportCalls["Planted.swift"], 1)
        XCTAssertEqual(result.applicationSupportLiteralSites.count, 1)
        XCTAssertTrue(result.unreadableSites.isEmpty, "\(result.unreadableSites)")

        // Line numbers stay right after a call split over several lines
        // (lines 8-10 above): `Self.privateKey` is on line 12.
        let afterSplit = result.symbolReferences["Planted.swift|Self.privateKey"]?.first
        XCTAssertEqual(afterSplit?.line, 12)
    }

    /// Keys built at run time, or written as expressions, must be reported
    /// as unreadable rather than missed.
    func test_scannerFlagsKeysItCannotRead() {
        let source = #"""
        func f(defaults: UserDefaults, prefix: String) {
            defaults.set(1, forKey: "\(prefix)count")
            defaults.set(2, forKey: prefix + "suffix")
            defaults.set(3, forKey: #"raw"#)
            @AppStorage("a\(b)") var interpolated = 0
            notify(settingKey: makeKey(), title: "t")
        }
        """#
        let result = SettingsSourceKeyScanner.scan(source: source, relativePath: "Dynamic.swift")
        XCTAssertEqual(result.unreadableSites.count, 5, "\(result.unreadableSites)")
        XCTAssertEqual(result.unreadableSites.map(\.line).sorted(), [2, 3, 4, 5, 6])
        XCTAssertTrue(result.literalKeys.isEmpty, "\(result.literalKeys)")
    }

    /// Look-alikes that are not settings must NOT be reported, or the
    /// tripwire would cry wolf and be ignored.
    func test_scannerIgnoresThingsThatAreNotSettings() {
        let source = """
        // @AppStorage("commented.out") — a full-line comment never counts.
            /// defaults.set(1, forKey: "doc.comment")
        func f(container: KeyedDecodingContainer<CodingKeys>, tags: [MediaTag], cache: [String: Int]) throws {
            var dictionary = cache
            dictionary.removeValue(forKey: "dictionary.key")
            _ = try container.decode(Int.self, forKey: .codingKey)
            _ = MusicBrainzTagMapping.value(forKey: "title", in: tags)
        }
        func notify(settingKey: String, title: String) {}
        func value(forKey key: String, in tags: [MediaTag]) -> String? { nil }
        """
        let result = SettingsSourceKeyScanner.scan(source: source, relativePath: "Lookalikes.swift")
        XCTAssertTrue(result.literalKeys.isEmpty, "\(result.literalKeys)")
        XCTAssertTrue(result.symbolReferences.isEmpty, "\(result.symbolReferences)")
        XCTAssertTrue(result.unreadableSites.isEmpty, "\(result.unreadableSites)")
    }
}
