// ============================================================================
// MeedyaConverter — SettingsKeyRegistry (Issue #506 commit 4)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// ONE table with a deliberate decision for EVERY setting MeedyaConverter
// stores in its settings file (`UserDefaults`), plus one for every file it
// keeps in `~/Library/Application Support/MeedyaConverter/`.
//
// This is an allow-list. Export writes only settings marked `.allowed` or
// `.thisMac`, and import writes only those, only in the groups the person
// ticked (`SettingsExporter`, `SettingsImporter`). A setting that is not in this table at all is never
// exported. That is the safe failure, but it would still be a silent gap,
// so `Tests/ConverterEngineTests/SettingsKeyCoverageTests.swift` scans
// `Sources/` and FAILS whenever:
//   - a setting is found in the code with no decision here, naming it; or
//   - this table lists a setting nothing in the code uses any more.
// `SettingsKeyRegistrySentinelTests` separately pins the secrets and other
// risky settings to `.never`, without relying on that scan.
//
// Adding a setting: add an entry below, in the group it belongs to, with a
// plain-English label and location, and either the value rules or the
// reason it never travels. When unsure, `.never` is the safe choice.
//
// Where the decisions come from: `.claude/plans/settings-export-import-plan.md`
// §1 (the inventory, with reasons) and §9 (owner decisions, all applied):
//   - hooks (`postEncodeActionChain`) are left out entirely in this version;
//   - "This Mac only" is off by default;
//   - consents never travel (MakeMKV terms, the render-farm insecure opt-in,
//     analytics);
//   - the webhook address and webhook headers are NEVER exported;
//   - encoding profiles are their own group.
//
// Where this table deliberately differs from the plan's §1 inventory
// (re-checked against the code on 2026-09-25, with #508 and #506 commits
// 1-3 in place):
//   - `autotag.enabled` and `autotag.writeNFO` are new since the plan was
//     counted (#508). Both are allowed, in Encoding (reasons on the entries).
//   - `mediaServerAPIKey` is now reached through
//     `MediaServerCredentialStore.legacyDefaultsKey` (#506 commit 1), not a
//     literal, and is marked `.legacyCredential`.
//   - SIX settings the plan allowed are `.never(.noScreenChangesIt)`, by the
//     plan's own rule ("exported only if a user can see and change it"):
//     `vectorConversion.preserveMetadata`, `vectorConversion.ocrTextRegions`,
//     `proresVector.tracing.preserveMetadata`,
//     `proresVector.tracing.ocrTextRegions`, `proresVector.shapePersistence`
//     and `proresVector.keyframeExtraction`. Their toggles were removed from
//     the screens because no converter implements them (see the comments in
//     `RasterToVectorConfigEditor.swift` and `ProResVectorView.swift`); the
//     stored values are only carried along for compatibility.
//
// Counts at the time of writing (the tests do not pin these numbers, so a
// new setting only needs its own entry): 106 settings = 71 allowed
// (13 general, 29 encoding, 29 connections) + 7 This Mac only + 28 never;
// and 13 Application Support stores (1 allowed, 12 never).
//
// Settings that belong to other code, and are deliberately NOT in this table
// (the scan knows about them; see `SettingsSourceKeyScanner.swift`):
//   - `GloballyEnabled`, read from Apple's own `com.apple.WindowManager`
//     settings by `StageManagerOptimizer.swift`. Not ours; never touched.
//   - Settings written by frameworks (Sparkle's `SU…` keys in Direct builds,
//     AppKit window positions, the open panel's last folder). The code never
//     names them, so the scan cannot see them; an allow-list never exports
//     them, which is the safe direction.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsKeyRegistry

/// The decision for every stored setting and every Application Support
/// store. See the file overview for how it is kept complete.
public enum SettingsKeyRegistry {

    // MARK: Lookup

    /// The entry for `key`, or `nil` if the key has no decision (and would
    /// therefore never be exported or imported).
    public static func entry(for key: String) -> SettingsKeyEntry? {
        entriesByKey[key]
    }

    /// Every key that has a decision.
    public static var allKeys: Set<String> {
        Set(entriesByKey.keys)
    }

    /// The entries whose decision is `.allowed(category, _)` for `category`,
    /// or `.thisMac` when `category` is `.thisMac`. Empty for
    /// `.encodingProfiles`, which is a file store, not settings keys.
    public static func entries(in category: SettingsCategory) -> [SettingsKeyEntry] {
        entries.filter { $0.category == category }
    }

    /// Built with `uniquingKeysWith` rather than `uniqueKeysWithValues`: a
    /// duplicated key in the table must fail a TEST
    /// (`SettingsKeyRegistrySentinelTests`), never crash the app at launch.
    /// The first entry wins so a lookup is at least predictable.
    private static let entriesByKey: [String: SettingsKeyEntry] =
        Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    // MARK: Shared wording

    private static let sidebar = "in the main window's sidebar"
    private static let settingsFilePathNote =
        "A path on the Mac the file came from; the same tool may be somewhere else on another Mac."
    private static let noScreenForVectorOption =
        "No screen lets you change it: the toggle was removed because no converter implements "
        + "it, and the stored value is only carried along for compatibility. If a screen that "
        + "edits it comes back, decide again."

    // MARK: Value limits used more than once

    /// TCP ports.
    private static let portRange: ClosedRange<Int> = 1...65_535

    /// The colour-count Stepper in `RasterToVectorConfigEditor` (2...256).
    private static let tracingColourCountRange: ClosedRange<Int> = 2...256

    /// The curve-simplification Stepper in `RasterToVectorConfigEditor`
    /// (0.0...10.0).
    private static let curveSimplificationRange: ClosedRange<Double> = 0.0...10.0

    // MARK: - The table

    /// One entry per stored setting. Grouped as the plan groups them:
    /// general, encoding, connections, This Mac only; within each, the
    /// allowed entries first, then the never entries.
    public static let entries: [SettingsKeyEntry] = generalEntries
        + encodingEntries
        + connectionEntries
        + thisMacEntries

    // MARK: General and appearance

    private static let generalEntries: [SettingsKeyEntry] = [
        allowed(
            "appearanceMode", .general,
            // `AppearanceMode` is an app-module type the engine cannot see,
            // so its raw values are written out here. The app test
            // `SettingsRegistryAppConstantsTests` fails if they drift.
            .oneOf(["System", "Light", "Dark"]),
            label: "Appearance: System, Light or Dark",
            location: "Settings › General"
        ),
        allowed(
            "confirmBeforeEncoding", .general, .bool,
            label: "Confirm before starting encoding",
            location: "Settings › General"
        ),
        allowed(
            "showMenuBarStatus", .general, .bool,
            label: "Show status in the menu bar",
            location: "Settings › General"
        ),
        allowed(
            "autoScrollLog", .general, .bool,
            label: "Auto-scroll the activity log",
            location: "Settings › General"
        ),
        allowed(
            "notifyOnCompletion", .general, .bool,
            label: "Notify when a job completes",
            location: "Settings › Notifications"
        ),
        allowed(
            "notifyOnFailure", .general, .bool,
            label: "Notify when a job fails",
            location: "Settings › Notifications"
        ),
        allowed(
            "notifyOnQueueFinished", .general, .bool,
            label: "Notify when the queue finishes",
            location: "Settings › Notifications"
        ),
        allowed(
            "playSoundOnCompletion", .general, .bool,
            label: "Play a sound on completion",
            location: "Settings › Notifications"
        ),
        // `ThemeManager.init` reads the three theme settings once, so a new
        // value shows the next time the app opens.
        allowed(
            "customAccentColor", .general, .hexColour,
            label: "Theme accent colour",
            location: "Settings › Theme",
            takesEffect: .nextLaunch
        ),
        allowed(
            "customSidebarTint", .general, .hexColour,
            label: "Theme sidebar tint",
            location: "Settings › Theme",
            takesEffect: .nextLaunch
        ),
        allowed(
            "customThemeData", .general, .json(.customTheme),
            label: "The chosen colour theme",
            location: "Settings › Theme",
            takesEffect: .nextLaunch
        ),
        // `KeyboardShortcutManager` loads the list once and writes the WHOLE
        // list back on every change, so an import used to only show after a
        // relaunch. #506 commit 8 adds `KeyboardShortcutManager
        // .reloadFromDefaults(_:)`, called from the Import & Export screen
        // right after `apply` succeeds, so the running app now notices an
        // imported list straight away — hence `.immediately` (the default;
        // see `allowed`'s own default). Pinned by
        // `SettingsKeyRegistrySentinelTests.test_reloadedSettingsTakeEffectImmediately`.
        allowed(
            "keyboard_shortcuts", .general, .json(.keyboardShortcuts),
            label: "Keyboard shortcuts",
            location: "Settings › Shortcuts"
        ),
        allowed(
            "updateChannel", .general,
            // `UpdateChannel` is an app-module type; pinned by
            // `SettingsRegistryAppConstantsTests`, like `appearanceMode`.
            .oneOf(["stable", "beta", "alpha"]),
            label: "Update channel: stable, beta or alpha",
            location: "Settings › Updates"
        ),

        never(
            "hasCompletedOnboarding", .appBookkeeping,
            label: "The welcome screens have been seen",
            location: "Not in Settings (set by the welcome screens)",
            reason: "Records that this Mac has shown the welcome screens. Copying it would skip "
                + "them on a Mac that has never shown them."
        ),
        never(
            "menuBarMode", .appBookkeeping,
            label: "Older copy of “Show status in the menu bar”",
            location: "Not in Settings (kept by the menu bar controller)",
            reason: "An older copy of “Show status in the menu bar”. The app rewrites it from that "
                + "setting every time it opens (MeedyaConverterApp.swift), so copying it changes "
                + "nothing."
        ),
        never(
            "hideDockIconWhenMinimised", .noScreenChangesIt,
            label: "Hide the Dock icon when minimised",
            location: "Not shown anywhere in the app",
            reason: "No screen sets it; only MenuBarController reads and writes it."
        ),
        never(
            "com.mwbm.meedyaconverter.selectedLanguage", .noScreenChangesIt,
            label: "Chosen app language",
            location: "Not shown anywhere in the app",
            reason: "Nothing in the app calls LocalizationManager.setLanguage, the only code that sets it."
        ),
        never(
            "controlCenterAutoShow", .noScreenChangesIt,
            label: "Control Center panel: show when encoding starts",
            location: "Not shown anywhere in the app",
            reason: "The Control Center panel that uses it (ControlCenterWidget) is never created."
        ),
        never(
            "controlCenterAutoHide", .noScreenChangesIt,
            label: "Control Center panel: hide when idle",
            location: "Not shown anywhere in the app",
            reason: "The Control Center panel that uses it (ControlCenterWidget) is never created."
        ),
    ]

    // MARK: Encoding and output

    private static let encodingEntries: [SettingsKeyEntry] = [
        // Read once in `AppViewModel.init`, so the queue uses a new default
        // profile from the next launch.
        allowed(
            "defaultProfileName", .encoding, .text,
            label: "Default encoding profile (by name)",
            location: "Settings › Encoding",
            takesEffect: .nextLaunch
        ),
        // Missing must keep meaning TRUE (`HardwareAccelerationPreference`),
        // so the importer must never write a default of false for it.
        allowed(
            "useHardwareAcceleration", .encoding, .bool,
            label: "Prefer hardware acceleration",
            location: "Settings › Encoding"
        ),
        allowed(
            "overwriteExisting", .encoding, .bool,
            label: "Overwrite existing output files",
            location: "Settings › Encoding",
            warning: .whenTrue(
                "Overwrite existing output files: ON. A file already at the output path is replaced."
            )
        ),
        allowed(
            "deleteSourceAfterEncode", .encoding, .bool,
            label: "Delete the source file after a successful encode",
            location: "Settings › Encoding",
            warning: .whenTrue(
                "Delete source after successful encode: ON. Source files are permanently deleted "
                + "after they convert successfully. This cannot be undone."
            )
        ),
        allowed(
            "filenameTemplate", .encoding, .text,
            label: "Output filename template",
            location: "Output, \(sidebar)"
        ),
        // The slider's top is max(2 × the hardware recommendation, 8), and
        // the recommendation is capped at 8 (`ParallelEncoder
        // .determineMaxConcurrent`), so it can produce 1...16 today. The
        // limit here is a looser sanity bound: the queue re-clamps to THIS
        // Mac's hardware and licence on every use
        // (`ParallelEncoder.resolveConcurrency`), so a bigger Mac's number
        // is only ever an upper request.
        allowed(
            ParallelEncoder.maxConcurrentJobsDefaultsKey, .encoding, .int(1...64),
            label: "Maximum encoding jobs at once",
            location: "Parallel Encoding, \(sidebar)"
        ),
        allowed(
            "conditionalRules", .encoding, .json(.conditionalRules),
            label: "Conditional rules",
            location: "Conditional Rules, \(sidebar)"
        ),
        // Loaded once into `AppViewModel.savedPipelines` and written back
        // whole on every save, so an import used to only show after a
        // relaunch. #506 commit 8 adds `AppViewModel
        // .reloadAfterSettingsImport(from:)`, called from the Import &
        // Export screen right after `apply` succeeds, so the running app
        // now notices an imported pipeline list straight away — hence
        // `.immediately` (the default; see `allowed`'s own default). Pinned
        // by `SettingsKeyRegistrySentinelTests
        // .test_reloadedSettingsTakeEffectImmediately`.
        allowed(
            "savedPipelines", .encoding, .json(.encodingPipelines),
            label: "Saved encoding pipelines",
            location: "Output, \(sidebar)"
        ),
        // Visible in Settings but nothing reads it yet (#512). Exported
        // because a person can see and change it.
        allowed(
            "metadataBackend", .encoding,
            .oneOf(SuiteCoreMetadataBackend.allCases.map(\.rawValue)),
            label: "Metadata lookup backend",
            location: "Settings › Metadata"
        ),

        // Vector Conversion tool (one setting per `RasterToVectorConfig`
        // field the screen still edits).
        allowed(
            "vectorConversion.preset", .encoding,
            .oneOf(EditabilityPreset.allCases.map(\.rawValue)),
            label: "Vector Conversion: editability preset",
            location: "Vector Conversion, \(sidebar)"
        ),
        allowed(
            "vectorConversion.tracingMode", .encoding,
            .oneOf(TracingMode.allCases.map(\.rawValue)),
            label: "Vector Conversion: tracing mode",
            location: "Vector Conversion, \(sidebar)"
        ),
        allowed(
            "vectorConversion.colorCount", .encoding, .int(tracingColourCountRange),
            label: "Vector Conversion: number of colours",
            location: "Vector Conversion, \(sidebar)"
        ),
        allowed(
            "vectorConversion.alpha", .encoding,
            .oneOf(AlphaStrategy.allCases.map(\.rawValue)),
            label: "Vector Conversion: transparency handling",
            location: "Vector Conversion, \(sidebar)"
        ),
        allowed(
            "vectorConversion.animation", .encoding,
            .oneOf(AnimationMethod.allCases.map(\.rawValue)),
            label: "Vector Conversion: animation method",
            location: "Vector Conversion, \(sidebar)"
        ),
        allowed(
            "vectorConversion.curveSimplification", .encoding, .double(curveSimplificationRange),
            label: "Vector Conversion: curve simplification",
            location: "Vector Conversion, \(sidebar)"
        ),

        // ProRes to Vector tool.
        allowed(
            "proresVector.sourceVariant", .encoding,
            .oneOf(ProResVariant.allCases.map(\.rawValue)),
            label: "ProRes to Vector: ProRes variant",
            location: "ProRes to Vector, \(sidebar)"
        ),
        allowed(
            "proresVector.frameRate", .encoding,
            .oneOf(ProResFrameRate.allCases.map(\.rawValue)),
            label: "ProRes to Vector: frame rate",
            location: "ProRes to Vector, \(sidebar)"
        ),
        // The Stepper in `ProResVectorView` (1...10).
        allowed(
            "proresVector.frameStride", .encoding, .int(1...10),
            label: "ProRes to Vector: process every Nth frame",
            location: "ProRes to Vector, \(sidebar)"
        ),
        allowed(
            "proresVector.alphaHandling", .encoding,
            .oneOf(ProResAlphaHandling.allCases.map(\.rawValue)),
            label: "ProRes to Vector: alpha handling",
            location: "ProRes to Vector, \(sidebar)"
        ),
        // The screen only offers SMIL today (the executor rejects the
        // others), but every stored value that decodes to a real
        // `AnimationMethod` is accepted, so a value saved by an older build
        // does not make the whole export fail.
        allowed(
            "proresVector.animation", .encoding,
            .oneOf(AnimationMethod.allCases.map(\.rawValue)),
            label: "ProRes to Vector: animation method",
            location: "ProRes to Vector, \(sidebar)"
        ),
        allowed(
            "proresVector.tracing.preset", .encoding,
            .oneOf(EditabilityPreset.allCases.map(\.rawValue)),
            label: "ProRes to Vector: tracing editability preset",
            location: "ProRes to Vector, \(sidebar)"
        ),
        allowed(
            "proresVector.tracing.tracingMode", .encoding,
            .oneOf(TracingMode.allCases.map(\.rawValue)),
            label: "ProRes to Vector: tracing mode",
            location: "ProRes to Vector, \(sidebar)"
        ),
        allowed(
            "proresVector.tracing.colorCount", .encoding, .int(tracingColourCountRange),
            label: "ProRes to Vector: number of colours",
            location: "ProRes to Vector, \(sidebar)"
        ),
        allowed(
            "proresVector.tracing.alpha", .encoding,
            .oneOf(AlphaStrategy.allCases.map(\.rawValue)),
            label: "ProRes to Vector: tracing transparency handling",
            location: "ProRes to Vector, \(sidebar)"
        ),
        allowed(
            "proresVector.tracing.curveSimplification", .encoding, .double(curveSimplificationRange),
            label: "ProRes to Vector: curve simplification",
            location: "ProRes to Vector, \(sidebar)"
        ),

        // Audio CD (AccurateRip). The drive model and offset are This Mac
        // only (below): they belong to the physical drive.
        allowed(
            "accurateRip.enabled", .encoding, .bool,
            label: "Submit verified rips to AccurateRip",
            location: "Settings › Audio CD",
            warning: .whenTrue(
                "Submit verified rips to AccurateRip: ON. Successfully verified CD rips are "
                + "contributed to the AccurateRip database."
            )
        ),
        allowed(
            "accurateRip.softwareId", .encoding, .text,
            label: "AccurateRip software identifier",
            location: "Settings › Audio CD"
        ),

        // Auto-tagging (#508), new since the plan's count. Encoding, not
        // Connections: it changes what happens to each file while it
        // converts (adds missing tags, optionally writes an .nfo), and it
        // holds no address or credential (the TMDB key it needs lives in
        // the Keychain and never travels). Allowed, because a person turns
        // it on deliberately in Settings › Metadata; the warning says
        // plainly that titles are sent online, in the screen's own words.
        allowed(
            AutoTagSettingsStore.Keys.enabled, .encoding, .bool,
            label: "Tag files automatically while converting",
            location: "Settings › Metadata",
            warning: .whenTrue(
                "Tag files automatically while converting: ON. Each file's title (and year, if "
                + "known) is sent to TMDB or MusicBrainz to look it up."
            )
        ),
        allowed(
            AutoTagSettingsStore.Keys.writeNFO, .encoding, .bool,
            label: "Also save a Kodi .nfo file next to each identified film",
            location: "Settings › Metadata"
        ),

        never(
            "proresVector.startTimeSeconds", .lastFileOnly,
            label: "ProRes to Vector: start time",
            location: "ProRes to Vector, \(sidebar)",
            reason: "The last clip's trim point. It means nothing for a different file."
        ),
        never(
            "proresVector.endTimeSeconds", .lastFileOnly,
            label: "ProRes to Vector: end time",
            location: "ProRes to Vector, \(sidebar)",
            reason: "The last clip's trim point. It means nothing for a different file."
        ),
        never(
            "vectorConversion.preserveMetadata", .noScreenChangesIt,
            label: "Vector Conversion: preserve image metadata",
            location: "No longer shown (removed from Vector Conversion)",
            reason: noScreenForVectorOption
        ),
        never(
            "vectorConversion.ocrTextRegions", .noScreenChangesIt,
            label: "Vector Conversion: recognise text regions",
            location: "No longer shown (removed from Vector Conversion)",
            reason: noScreenForVectorOption
        ),
        never(
            "proresVector.tracing.preserveMetadata", .noScreenChangesIt,
            label: "ProRes to Vector: preserve image metadata",
            location: "No longer shown (removed from ProRes to Vector)",
            reason: noScreenForVectorOption
        ),
        never(
            "proresVector.tracing.ocrTextRegions", .noScreenChangesIt,
            label: "ProRes to Vector: recognise text regions",
            location: "No longer shown (removed from ProRes to Vector)",
            reason: noScreenForVectorOption
        ),
        never(
            "proresVector.shapePersistence", .noScreenChangesIt,
            label: "ProRes to Vector: keep shapes between frames",
            location: "No longer shown (removed from ProRes to Vector)",
            reason: noScreenForVectorOption
        ),
        never(
            "proresVector.keyframeExtraction", .noScreenChangesIt,
            label: "ProRes to Vector: skip unchanged frames",
            location: "No longer shown (removed from ProRes to Vector)",
            reason: noScreenForVectorOption
        ),
    ]

    // MARK: Connections to other services (addresses and options only)

    private static let connectionEntries: [SettingsKeyEntry] = [
        // Email. The SMTP password is in the Keychain and never travels.
        // The host is checked as an ADDRESS (#506 commit 5): a host typed as
        // `user:password@smtp.example.com` would otherwise carry the
        // password into the file.
        allowed(
            "emailSMTPHost", .connections, .address,
            label: "Email: SMTP server",
            location: "Settings › Email"
        ),
        allowed(
            "emailSMTPPort", .connections, .int(portRange),
            label: "Email: SMTP port",
            location: "Settings › Email"
        ),
        allowed(
            "emailSMTPUsername", .connections, .text,
            label: "Email: SMTP user name",
            location: "Settings › Email"
        ),
        allowed(
            "emailSMTPUseTLS", .connections, .bool,
            label: "Email: use TLS",
            location: "Settings › Email"
        ),
        allowed(
            "emailFromAddress", .connections, .text,
            label: "Email: from address",
            location: "Settings › Email"
        ),
        allowed(
            "emailToAddresses", .connections, .json(.emailRecipients),
            label: "Email: recipients",
            location: "Settings › Email"
        ),
        allowed(
            "emailOnComplete", .connections, .bool,
            label: "Email when an encode completes",
            location: "Settings › Email"
        ),
        allowed(
            "emailOnFailure", .connections, .bool,
            label: "Email when an encode fails",
            location: "Settings › Email"
        ),
        allowed(
            "emailOnQueueFinished", .connections, .bool,
            label: "Email when the queue finishes",
            location: "Settings › Email"
        ),

        // Media server. The key is in the Keychain (#506 commit 1).
        allowed(
            "mediaServerType", .connections,
            .oneOf(MediaServerType.allCases.map(\.rawValue)),
            label: "Media server: type (Plex, Jellyfin or Emby)",
            location: "Settings › Media Server"
        ),
        // Checked as an ADDRESS (#506 commit 5): Plex addresses are often
        // copied with `?X-Plex-Token=…` on the end, which is the key itself.
        allowed(
            "mediaServerHost", .connections, .address,
            label: "Media server: host",
            location: "Settings › Media Server"
        ),
        allowed(
            "mediaServerPort", .connections, .int(portRange),
            label: "Media server: port",
            location: "Settings › Media Server"
        ),
        allowed(
            "mediaServerUseTLS", .connections, .bool,
            label: "Media server: use TLS",
            location: "Settings › Media Server"
        ),
        allowed(
            "mediaServerLibraryId", .connections, .text,
            label: "Media server: library",
            location: "Settings › Media Server"
        ),
        allowed(
            "mediaServerAutoScan", .connections, .bool,
            label: "Media server: scan the library after a successful encode",
            location: "Settings › Media Server"
        ),

        // Webhooks: only the preset and the three event switches. The
        // address and headers are never exported (below).
        allowed(
            "webhookPreset", .connections,
            // `WebhookPreset` is an app-module type; pinned by
            // `SettingsRegistryAppConstantsTests`.
            .oneOf(["Generic", "Discord", "Slack"]),
            label: "Webhooks: preset (Generic, Discord or Slack)",
            location: "Settings › Webhooks"
        ),
        allowed(
            "webhookOnComplete", .connections, .bool,
            label: "Webhook when an encode completes",
            location: "Settings › Webhooks"
        ),
        allowed(
            "webhookOnFailure", .connections, .bool,
            label: "Webhook when an encode fails",
            location: "Settings › Webhooks"
        ),
        allowed(
            "webhookOnQueueFinished", .connections, .bool,
            label: "Webhook when the queue finishes",
            location: "Settings › Webhooks"
        ),

        // MeedyaDB. The key is in the Keychain and never travels.
        allowed(
            MeedyaDBConfigStore.Keys.enabled, .connections, .bool,
            label: "MeedyaDB: contribute identified discs",
            location: "Settings › MeedyaDB",
            warning: .whenTrue(
                "Contribute identified discs to MeedyaDB: ON. A disc you identify can be sent to "
                + "the MeedyaDB server."
            )
        ),
        allowed(
            MeedyaDBConfigStore.Keys.baseURL, .connections, .address,
            label: "MeedyaDB: server address",
            location: "Settings › MeedyaDB"
        ),
        allowed(
            MeedyaDBConfigStore.Keys.submissionMode, .connections,
            // `MeedyaDBSubmissionMode` is not `CaseIterable`, so its cases
            // are named one by one. A third mode would need adding here.
            .oneOf([MeedyaDBSubmissionMode.anonymous.rawValue, MeedyaDBSubmissionMode.full.rawValue]),
            label: "MeedyaDB: what to send (just the identity, or the label too)",
            location: "Settings › MeedyaDB",
            warning: .whenValue(
                MeedyaDBSubmissionMode.full.rawValue,
                message: "What MeedyaDB is sent: identity and the disc's label. The text of each "
                    + "disc's label is sent too, not just its identity."
            )
        ),

        // Render farm: addresses and tuning only. The two settings that
        // allow unencrypted connections are a consent (below).
        allowed(
            RenderFarmConfigurationLoader.Keys.discoveryIntervalSeconds, .connections,
            .double(RenderFarmConfigurationLoader.discoveryIntervalBounds),
            label: "Render farm: discovery refresh interval (seconds)",
            location: "Settings › Render Farm"
        ),
        allowed(
            RenderFarmConfigurationLoader.Keys.chunkSizeMiB, .connections,
            .int(RenderFarmConfigurationLoader.chunkSizeMiBBounds),
            label: "Render farm: upload chunk size (MiB)",
            location: "Settings › Render Farm"
        ),
        allowed(
            RenderFarmConfigurationLoader.Keys.agentsJSON, .connections, .json(.renderFarmAgents),
            label: "Render farm: agents you added (name, host, port, SSH user name)",
            location: "Settings › Render Farm"
        ),

        // SFTP and cloud storage: allowed, but only with secrets removed by
        // the exporter itself (see `SettingsJSONBlob.mustRemoveSecretsOnExport`).
        allowed(
            SFTPProfileStore.userDefaultsKey, .connections, .json(.sftpProfiles),
            label: "SFTP servers (passwords removed)",
            location: "SFTP, \(sidebar)"
        ),
        allowed(
            CloudStorageProfileStore.userDefaultsKey, .connections, .json(.cloudStorageProfiles),
            label: "Cloud storage destinations (tokens and keys removed)",
            location: "Cloud Storage, \(sidebar)"
        ),

        // Team profiles.
        allowed(
            "teamProfiles.gitRemote", .connections, .address,
            label: "Team profiles: git remote address",
            location: "Team Profile, \(sidebar)"
        ),
        allowed(
            "teamProfiles.gitBranch", .connections, .text,
            label: "Team profiles: git branch",
            location: "Team Profile, \(sidebar)"
        ),

        never(
            MediaServerCredentialStore.legacyDefaultsKey, .legacyCredential,
            label: "Media server API key (old location)",
            location: "Settings › Media Server (the key is now saved in the Keychain)",
            reason: "Versions before #506 kept the media server's key here in plain text. It now "
                + "lives in the Keychain, and this name stays decided as “never” so a settings "
                + "file can never put a key back here."
        ),
        never(
            "webhookURL", .credential,
            label: "Webhook address",
            location: "Settings › Webhooks",
            reason: "For Slack and Discord the address itself works like a password: anyone who "
                + "has it can post to your channel."
        ),
        never(
            "webhookCustomHeaders", .credential,
            label: "Webhook custom headers",
            location: "Settings › Webhooks",
            reason: "Free-form headers, which people use for Authorization tokens."
        ),
        // The key belongs to the app (`PostEncodeActionsView.userDefaultsKey`).
        never(
            "postEncodeActionChain", .runsCommands,
            label: "Hooks (actions after each encode)",
            location: "Settings › Hooks",
            reason: "Hooks can run a shell script, call a web address, or move the source file to "
                + "the Trash after every encode. A settings file must never be able to set those "
                + "up. Set hooks up again on the other Mac."
        ),
        never(
            RenderFarmConfigurationLoader.Keys.allowInsecureTransports, .consent,
            label: "Render farm: allow unencrypted connections",
            location: "Settings › Render Farm",
            reason: "A typed opt-in that lowers security. It has to be made on the Mac itself."
        ),
        never(
            RenderFarmConfigurationLoader.Keys.insecureAcknowledgement, .consent,
            label: "Render farm: typed acknowledgement for unencrypted connections",
            location: "Settings › Render Farm",
            reason: "The typed half of the opt-in above. It has to be made on the Mac itself."
        ),
        never(
            MakeMKVConsentStore.Keys.enabled, .consent,
            label: "MakeMKV: switched on",
            location: "Settings › MakeMKV",
            reason: "MakeMKV's terms have to be accepted on each Mac by the person using it."
        ),
        never(
            MakeMKVConsentStore.Keys.termsAcknowledgement, .consent,
            label: "MakeMKV: terms accepted",
            location: "Settings › MakeMKV",
            reason: "MakeMKV's terms have to be accepted on each Mac by the person using it."
        ),
        never(
            "cloudProfileSyncEnabled", .noScreenChangesIt,
            label: "iCloud profile sync switched on",
            location: "Cloud Sync (hidden in every build)",
            reason: "The iCloud Sync screen is hidden in every build (NavigationItem.unavailable), "
                + "so nobody can switch it on."
        ),
        never(
            "analytics_enabled", .consent,
            label: "Share anonymous usage data",
            location: "Settings › Analytics",
            reason: "Agreeing to share usage data is asked on each Mac."
        ),
        never(
            "analytics_endpointURL", .consent,
            label: "Where usage data is sent",
            location: "Not shown anywhere in the app",
            reason: "Part of the usage-data choice made on each Mac. Nothing in the app sets it "
                + "today, and a settings file must never be able to send usage data somewhere new."
        ),
        never(
            "analytics_anonymousId", .installationIdentity,
            label: "Anonymous analytics ID",
            location: "Not shown anywhere in the app",
            reason: "Identifies this particular installation. A copy would make two Macs look like one."
        ),
        never(
            "Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel", .licenceCache,
            label: "Cached licence level",
            location: "Not shown anywhere in the app",
            reason: "A cached licence answer. Importing it could unlock paid features on a Mac that "
                + "has not paid for them."
        ),
        never(
            "Ltd.MWBMpartners.MeedyaConverter.entitlementCacheExpiry", .licenceCache,
            label: "When the cached licence level expires",
            location: "Not shown anywhere in the app",
            reason: "Goes with the cached licence level. Importing it could keep a paid level "
                + "alive on a Mac that has not paid."
        ),
    ]

    // MARK: This Mac only (off by default)

    private static let thisMacEntries: [SettingsKeyEntry] = [
        // Read only in `AppViewModel.init`.
        thisMac(
            "customFFmpegPath", .filePath,
            label: "FFmpeg location",
            location: "Settings › Paths",
            reason: settingsFilePathNote,
            takesEffect: .nextLaunch
        ),
        thisMac(
            "customFFprobePath", .filePath,
            label: "FFprobe location",
            location: "Settings › Paths",
            reason: settingsFilePathNote,
            takesEffect: .nextLaunch
        ),
        thisMac(
            "customPotracePath", .filePath,
            label: "potrace location",
            location: "Settings › Paths",
            reason: settingsFilePathNote
        ),
        thisMac(
            "customVTracerPath", .filePath,
            label: "VTracer location",
            location: "Settings › Paths",
            reason: settingsFilePathNote
        ),
        thisMac(
            MakeMKVConsentStore.Keys.binaryPath, .filePath,
            label: "makemkvcon location",
            location: "Settings › MakeMKV",
            reason: settingsFilePathNote
        ),
        thisMac(
            "accurateRip.driveModel", .text,
            label: "CD drive model",
            location: "Settings › Audio CD",
            reason: "Belongs to the physical CD drive on the Mac the file came from."
        ),
        // The Stepper in `AccurateRipSettingsTab` allows -500...500.
        thisMac(
            "accurateRip.driveOffset", .int(-500...500),
            label: "CD drive read offset (samples)",
            location: "Settings › Audio CD",
            reason: "Belongs to the physical CD drive. A wrong offset makes good CD rips fail "
                + "their AccurateRip check."
        ),
    ]

    // MARK: - Application Support stores

    /// Every file or folder MeedyaConverter keeps in
    /// `~/Library/Application Support/MeedyaConverter/`. Only the user
    /// profiles file travels. The tripwire test checks that every source
    /// file asking macOS for the Application Support folder appears here,
    /// once per store it builds.
    public static let fileStores: [SettingsFileStoreEntry] = [
        SettingsFileStoreEntry(
            path: "Profiles/user_profiles.json", sourceFile: "EncodingProfile.swift",
            label: "Your encoding profiles",
            decision: .allowed(.encodingProfiles)
        ),
        SettingsFileStoreEntry(
            path: "Keys/api_keys.json", sourceFile: "APIKeyManager.swift",
            label: "The list of saved API keys",
            decision: .never(reason: "The index of saved credentials. The secrets themselves are "
                + "in the Keychain and never travel either.")
        ),
        SettingsFileStoreEntry(
            path: "WatchFolderMonitorConfigs.json", sourceFile: "WatchFolderMonitor.swift",
            label: "Watch folders",
            decision: .never(reason: "Every entry is a folder on this Mac. A later version could "
                + "offer these under “This Mac only”.")
        ),
        SettingsFileStoreEntry(
            path: "scheduled_jobs.json", sourceFile: "EncodingScheduler.swift",
            label: "Scheduled jobs",
            decision: .never(reason: "Work waiting to run on this Mac, not settings.")
        ),
        SettingsFileStoreEntry(
            path: "Checkpoints/", sourceFile: "EncodingCheckpoint.swift",
            label: "Checkpoints for resuming encodes",
            decision: .never(reason: "Part-finished work on this Mac, not settings.")
        ),
        SettingsFileStoreEntry(
            path: "encode_history.json", sourceFile: "ETAPredictor.swift",
            label: "Past encode times, used to estimate how long a job will take",
            decision: .never(reason: "A record of work done on this Mac's hardware, not settings.")
        ),
        SettingsFileStoreEntry(
            path: "analytics_events.json", sourceFile: "AnalyticsEngine.swift",
            label: "Usage events waiting to be sent",
            decision: .never(reason: "A record of what was done on this Mac, tied to that Mac's "
                + "own usage-data choice.")
        ),
        SettingsFileStoreEntry(
            path: "comparison_library.json", sourceFile: "ComparisonLibraryManager.swift",
            label: "The comparison library",
            decision: .never(reason: "A record of work, not settings.")
        ),
        SettingsFileStoreEntry(
            path: "ComparisonFrames/", sourceFile: "ComparisonLibraryManager.swift",
            label: "Frames captured for the comparison library",
            decision: .never(reason: "Pictures captured from your files, not settings.")
        ),
        SettingsFileStoreEntry(
            path: "recent_files.json", sourceFile: "RecentFilesManager.swift",
            label: "Recently opened files",
            decision: .never(reason: "A record of files opened on this Mac, not settings.")
        ),
        SettingsFileStoreEntry(
            path: "Plugins/", sourceFile: "PluginManager.swift",
            label: "Plugins",
            decision: .never(reason: "Plugins are program code, which a settings file must never "
                + "carry. (They are not loaded yet either: #353.)")
        ),
        SettingsFileStoreEntry(
            path: "TeamProfiles/GitCache/", sourceFile: "GitProfileSync.swift",
            label: "Downloaded copy of the team profiles git repository",
            decision: .never(reason: "A cache: it is downloaded again from the git remote, which "
                + "is exported.")
        ),
        SettingsFileStoreEntry(
            path: "RemoteFeatures/flags_cache.json", sourceFile: "RemoteFeatureGateProvider.swift",
            label: "Cached feature switches from MWBM's server",
            decision: .never(reason: "A server cache. Importing one could switch features on "
                + "that the server has not switched on for this Mac.")
        ),
    ]

    // MARK: - Entry builders
    //
    // Small helpers so each table row reads as one decision. They add no
    // behaviour; they only fill in `SettingsKeyEntry`.

    private static func allowed(
        _ key: String,
        _ category: SettingsCategory,
        _ kind: SettingsValueKind,
        label: String,
        location: String,
        warning: SettingsImportWarning? = nil,
        takesEffect: SettingsTakesEffect = .immediately
    ) -> SettingsKeyEntry {
        SettingsKeyEntry(
            key: key, label: label, location: location,
            decision: .allowed(
                category,
                SettingsValueRules(kind: kind, importWarning: warning, takesEffect: takesEffect)
            )
        )
    }

    private static func thisMac(
        _ key: String,
        _ kind: SettingsValueKind,
        label: String,
        location: String,
        reason: String,
        takesEffect: SettingsTakesEffect = .immediately
    ) -> SettingsKeyEntry {
        SettingsKeyEntry(
            key: key, label: label, location: location,
            decision: .thisMac(SettingsValueRules(kind: kind, takesEffect: takesEffect), reason: reason)
        )
    }

    private static func never(
        _ key: String,
        _ kind: SettingsNeverKind,
        label: String,
        location: String,
        reason: String
    ) -> SettingsKeyEntry {
        SettingsKeyEntry(key: key, label: label, location: location, decision: .never(kind, reason: reason))
    }
}
