<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

> **Status: IMPLEMENTED**, on branch `worktree-agent-aecc2da233ac2a105` (all
> nine commits, `522367d`..`becbb1d`, plus two Codex-round review fixes
> `f41813b`/`becbb1d`). Not yet reviewed by a second system. This plan is kept
> for its design record (the full key-by-key inventory, the owner decisions,
> and the risks in §9); the CODE is the source of truth for exact behaviour —
> see "Where the build differed from this plan" immediately below for every
> point where the two disagree.

## Where the build differed from this plan

Re-checked against the code on the working branch, 2026-09-25 (commit 9/9,
documentation). Everything below is the build's actual, verified behaviour;
where this plan's body still describes the original design, read the note
here as the correction.

- **106 settings, not 104.** The plan's §1 inventory counted 104 keys before
  #508 landed. #508 added `autotag.enabled` and `autotag.writeNFO` (both
  allowed, in Encoding), bringing the registry to 106: 71 allowed (13
  general, 29 encoding, 29 connections) + 7 This Mac only + 28 never, plus
  13 Application Support stores (1 allowed, 12 never). See the header
  comment in `Sources/ConverterEngine/Settings/SettingsKeyRegistry.swift`.
- **`hasStoredKey` is a `static` method on `APIKeyManager`**, not an instance
  method as §4 sketches it — it never constructs an `APIKeyManager` (which
  would read every secret out of the Keychain to populate itself), so
  "still needs a key" cannot accidentally read a secret just by checking
  for one.
- **A built-in profile claiming to be built-in is refused outright**, not
  silently coerced to a user profile as an implementation might default to.
  `SettingsImportError.invalidValue` fires and the whole file is refused —
  consistent with "one bad value refuses the whole file" elsewhere in this
  plan, but worth stating explicitly since §1 doesn't spell out which of
  "refuse" or "coerce" was chosen.
- **Test settings "suites" are files, not plain named suites.** §7 says
  "Every test uses its own `UserDefaults` suite named with a fresh UUID",
  but the build goes further: each suite is named by an absolute path
  inside that test's own temporary folder (`UserDefaults(suiteName:
  tempDir.appendingPathComponent(UUID().uuidString).path)`), not a bare
  UUID string. A plain suite name still leaves a real, emptied `.plist`
  behind in `~/Library/Preferences` after `tearDown`, because macOS
  rewrites the file the moment the suite is touched — commit 5 found 1,532
  of these left over from one test run before switching to path-named
  suites, which macOS creates under the temp folder and which vanish with
  it.
- **The CLI flag is `--mode merge|replace`**, not `--replace` as an earlier
  sketch of §6 might suggest — merge is a real, named alternative to
  replace, not replace's absence.
- **`SettingsCLIReport` lives in `ConverterEngine`**, not in the
  `meedya-convert` target. `SwiftPM` will not let `Tests/MeedyaConvertTests`
  import another test target's sources, and the schema checker
  (`SettingsSchemaMiniValidator`) lives in `Tests/ConverterEngineTests`; so
  the report type moved to the engine, where both the CLI and the schema
  test can call the exact same function to build it.
- **Two settings gained a real reload hook** (commit 8): saved encoding
  pipelines and keyboard shortcuts are re-read from `UserDefaults`
  immediately after an import, instead of only taking effect at the next
  launch as §5 originally described for every setting loaded once at
  startup. Their registry entries were flipped from `.nextLaunch` to
  `.immediately`, pinned by a test so the flip can't quietly regress.
  Everything else loaded once at launch is still `.nextLaunch`.
- **The Replace-confirmation flow was hardened after review** (`becbb1d`,
  review of commit 8): the footer's "Import" button no longer relabels
  itself "Replace Anyway" and apply on a second press — a real defect found
  in review, where a fast double-click could apply a Replace (removing
  profiles, servers and rules) before its warning could be read. The "Import"
  button now stays disabled while a Replace confirmation is showing, and the
  ONLY way to proceed is a separate, differently-placed "Replace Anyway"
  button, wired to its own method that does nothing unless a confirmation is
  actually on screen.
- **A refused settings domain no longer crashes the CLI** (`f41813b`, review
  of commit 7): `UserDefaults(suiteName:)` also refuses reserved names such
  as `NSGlobalDomain` and the program's own bundle identifier, not only an
  empty string as an earlier assumption held. `--defaults-suite
  NSGlobalDomain` used to crash the tool via `fatalError`; it now prints a
  plain message and exits with the documented invalid-arguments code (2).

# Plan for #506: export and import settings between installations, with no secrets in the file

All paths below are relative to the repo root: the repo root. Line numbers are from the working tree on `wip/alpha-consolidation` (HEAD `89570c5`, with the in-flight edits uncommitted). Re-check them by searching for the text before editing. Per the HANDOFF note, nothing gets built until the Codex round-1 fixes have landed.

## The short version

- **One table of decisions in the engine** (`SettingsKeyRegistry`) lists every stored setting. Each one is marked: allowed (with its group), never exported (with a reason), or "This Mac only". Export writes only allowed keys. Import writes only allowed keys, and only in the groups the user ticked.
- **A tripwire test** scans `Sources/` for every settings key. It fails when a key has no decision, and also when the table lists a key nothing uses any more.
- **The engine owns everything that matters**: the file format, validation, preview, apply, and the "still needs a key" check. The app only adds file panels and one Settings tab. The CLI adds `settings export` and `settings import`, which call the same engine functions.
- **Findings that change the design** (details in §1 and §9):
  - There are **104 keys, not about 74**.
  - **`webhookURL` is itself a secret.** The issue did not flag it.
  - **Hooks (`postEncodeActionChain`) can hold shell commands** that run after every encode, so a settings file must never be able to plant them.
  - **The CLI would read the wrong settings file** unless it targets the app's settings domain explicitly.
  - **Several places load a setting once and later write the whole thing back.** That could silently undo an import unless they reload.

---

## 1. Verified inventory

**Method.** I found every `@AppStorage(…)`, `forKey:` and `settingKey:` use in `Sources/`, plus every named key constant.
- 88 distinct string literals came up. 5 are not settings: `title`, `artist`, `album`, `album_artist` and `date` are tag look-ups in `MusicBrainzTagMapping.swift:42-46` and `TMDBTagMapping.swift:116-122`. 1 belongs to Apple, not us: `GloballyEnabled`, read from the `com.apple.WindowManager` domain in `StageManagerOptimizer.swift:57-58`.
- That leaves **82 literal keys**.
- **22 more keys** are only ever reached through named constants (`Keys.enabled`, `Self.userDefaultsKey`, and so on).
- **Total: 104 keys** in our settings domain, read or written in **about 40 files**. The issue said about 74 keys across 27 files.
- **Proposed split: 82 allowed** (13 General, 33 Encoding, 29 Connections, 7 This Mac) **and 22 never exported.**

### General and appearance (`general`)

**Allowed (13):**
- `appearanceMode` (String: System, Light or Dark). `SettingsView.swift:162`, `MeedyaConverterApp.swift:106`.
- `confirmBeforeEncoding`, `showMenuBarStatus`, `autoScrollLog` (Bool).
- `notifyOnCompletion`, `notifyOnFailure`, `notifyOnQueueFinished`, `playSoundOnCompletion` (Bool). These are read live via `settingKey` at `AppViewModel.swift:2287-2296`, with the literals passed at lines 1594-2049.
- `customAccentColor`, `customSidebarTint` (hex String) and `customThemeData` (JSON `CustomTheme`). `ThemeManager.swift:72-90` writes them. Its `init` (134-148) reads them once, so they **take effect at next launch**.
- `keyboard_shortcuts` (JSON `[ShortcutBinding]`). `KeyboardShortcutManager.swift:232/249/384` loads once, and every change rewrites the whole list. **It needs a reload after import** (see §5).
- `updateChannel` (String). `SettingsView.swift:897`, `AppUpdateChecker.swift:118`.

**Never (6):**
- `hasCompletedOnboarding`: it would skip onboarding on a fresh install.
- `menuBarMode`: a copy of `showMenuBarStatus` that is rewritten at every launch (`MeedyaConverterApp.swift:177-184` says so itself).
- `hideDockIconWhenMinimised`: nothing in the UI sets it (it's only written inside `MenuBarController.swift:64-66`).
- `com.mwbm.meedyaconverter.selectedLanguage`: `LocalizationManager.setLanguage` has no callers.
- `controlCenterAutoShow` and `controlCenterAutoHide`: `ControlCenterWidget` is never created.
- **Rule used for these:** a setting is exported only if a user can see and change it in the app.

### Encoding and output (`encoding`)

**Allowed (33):**
- `defaultProfileName`. Read once in `AppViewModel.init` (`AppViewModel.swift:603`), so the queue picks it up at next launch.
- `useHardwareAcceleration`. Its default is **true**, and "missing" must stay meaning true (`HardwareAccelerationPreference.swift:39-64`).
- `overwriteExisting` and `deleteSourceAfterEncode`. **Both show a warning when the file sets them to true.**
- `filenameTemplate`.
- `parallelMaxConcurrentJobs` (`ParallelEncoder.swift:155`).
- `conditionalRules` (JSON `[ConditionalRule]`).
- `savedPipelines` (JSON `[EncodingPipeline]`). Loaded once at `AppViewModel.swift:1181-1205` and rewritten whole, so it **needs a reload**.
- `metadataBackend`. Visible in Settings but nothing reads it, as the #508 plan also found. Exported because the user can see it.
- `vectorConversion.*` (8 keys).
- `proresVector.*` (14 keys: all except the two trim points below).
- `accurateRip.enabled` (warning when true) and `accurateRip.softwareId`.
- **Ready for #508:** `autotag.enabled` (warning when true: "looks files up online") and `autotag.writeNFO`.

**Never (2):**
- `proresVector.startTimeSeconds` and `proresVector.endTimeSeconds`. They are the last clip's trim points and mean nothing for a different file.

### Your encoding profiles (`encodingProfiles`)

- This is a file store, not a setting: `~/Library/Application Support/MeedyaConverter/Profiles/user_profiles.json` (`EncodingProfile.swift:903-1093`).
- **Allowed**, merging by `id`. Built-in profiles are never exported. A file that claims a profile is built-in is refused.

### Connections to other services (`connections`): addresses and options only

**Allowed (29):**
- Email: `emailSMTPHost`, `emailSMTPPort` (1–65535), `emailSMTPUsername`, `emailSMTPUseTLS`, `emailFromAddress`, `emailToAddresses` (a String holding a JSON `[String]`), and the three `emailOn*` switches.
- Media server: `mediaServerType`, `mediaServerHost`, `mediaServerPort`, `mediaServerUseTLS`, `mediaServerLibraryId`, `mediaServerAutoScan`.
- Webhooks: `webhookPreset` and the three `webhookOn*` switches.
- MeedyaDB:
  - `meedyadb.enabled` (warning when true);
  - `meedyadb.baseURL` (the address check below applies);
  - `meedyadb.submissionMode` (anonymous or full; warning when full, because the disc label is sent too).
- Render farm: `renderFarm.discoveryIntervalSeconds`, `renderFarm.chunkSizeMiB`, and `renderFarm.agentsJSON` (host, port and ssh user only; `RenderFarmAgent.swift:67-97`).
- `sftpProfiles` (`SFTPUploader.swift:722`). **Re-redacted at export**, see below.
- `cloudStorageProfiles` (`CloudStorageUploader.swift:628`). **Re-redacted at export**: `accessToken` becomes `""`, and `refreshToken` and `secretAccessKey` become `nil`, even though `CloudStorageView.persistConfigs` (507) already does this.
- `teamProfiles.gitRemote` (address check applies) and `teamProfiles.gitBranch`.

**The address check.** An `http(s)` address with anything before an `@` (a user name, or user and password) is never exported. The same applies to any address containing a password. On import it is treated as an invalid value. This matters because `https://<token>@github.com/…` is a common way of embedding a GitHub token.

**Never (14):**
- `mediaServerAPIKey`: a credential sitting in plain UserDefaults (`MediaServerSettingsView.swift:42`, read at :97). Commit 1 moves it.
- **`webhookURL`: missed by the issue.** For the Slack and Discord presets, the address itself works like a password: anyone who has it can post to the channel (`WebhookSettingsView.swift:40`, presets at 17-24).
- `webhookCustomHeaders`: free-form, and people put `Authorization` headers in it (:55). It is also displayed **in clear text** at :114.
- **`postEncodeActionChain`: missed as a risk.** `PostEncodeActions.swift:33` has `.runShellScript` with `config["script"]` (run at 325-336), `.webhook` carries a URL (338), and `.moveSourceToTrash` exists (25). Importing it would plant a shell command that runs after every encode. The key belongs to the app (`PostEncodeActionsView.swift:119`), not the engine as the issue says.
- `renderFarm.allowInsecureTransports` and `renderFarm.insecureAcknowledgement`: a typed opt-in that lowers security (`RenderFarmConfigurationLoader.swift:158-169`). It must be made on the Mac itself.
- `makemkv.enabled` and `makemkv.termsAcknowledgement`: the terms must be accepted on each Mac by the person using it (`MakeMKVAccess.swift:69-92`).
- `cloudProfileSyncEnabled`: the iCloud Sync screen is hidden in every build (`AppViewModel.swift:203-205`).
- `analytics_enabled`, `analytics_endpointURL` and `analytics_anonymousId` (`AnalyticsEngine.swift:103-112`). Consent to send usage data is asked on each Mac, and the ID identifies this particular installation.
- `Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel` and `…entitlementCacheExpiry` (`EntitlementGating.swift:408-411`). **Importing these would let a file grant a paid tier.**

### This Mac only (`thisMac`): off by default, with a warning

**Allowed (7):**
- `customFFmpegPath` and `customFFprobePath`. Read only in `AppViewModel.init` (574-575), so they take effect at next launch.
- `customPotracePath`, `customVTracerPath` and `makemkv.binaryPath`.
- `accurateRip.driveModel` and `accurateRip.driveOffset`: the Stepper allows -500…500 (`SettingsView.swift:577`).

### Other stores

**Application Support files.** 13 places call `applicationSupportDirectory`. Only `Profiles/user_profiles.json` is exported. The rest are never exported, each with a reason:
- `Keys/api_keys.json`: the index of credentials.
- `WatchFolderMonitorConfigs.json`: every entry is a folder path on this Mac. Could join "This Mac" in a later version.
- `scheduled_jobs.json`, `Checkpoints/`: pending work, not settings.
- ETA history, analytics events, the comparison library, recent files: records of work (the issue already puts these out of scope).
- `Plugins/`: plugins aren't loaded yet (#353).
- `TeamProfiles/`: a git cache.
- `RemoteFeatures/flags_cache.json`: a server cache.

**Keychain.** Never exported, including:
- the APIKeyManager items (service `Ltd.MWBMpartners.MeedyaConverter.APIKeys`);
- the SMTP password (`EmailSettingsView.swift:391-394`);
- SFTP passwords (`com.mwbm.MeedyaConverter.sftp`);
- the licence key.

**Why `sftpProfiles` must be re-redacted at export.** The only place a legacy plaintext SFTP password is moved into the Keychain is `SFTPSettingsView.loadProfiles()` (`SFTPSettingsView.swift:514-570`). Someone who upgraded but never opened the SFTP screen still has `.password("hunter2")` in the settings file. So the exporter itself forces `.password("")`.

**A setting of Apple's that we must not touch.** `SettingsView.swift:226`-area code and `StageManagerOptimizer.swift:57` read `GloballyEnabled` from `com.apple.WindowManager`. It isn't ours; the scan ignores it, with that reason recorded.

---

## 2. The file format ("envelope"), JSON Schema and engine API

**What "envelope" means here.** A small fixed wrapper saying what the file is and which version wrote it. The settings sit inside it, grouped by category.

```json
{
  "format": "meedyaconverter.settings",
  "version": 1,
  "exportedAt": "2026-09-25T14:03:11Z",
  "appVersion": "0.1.0",
  "categories": {
    "general":          { "settings": { "appearanceMode": "Dark", "notifyOnFailure": true } },
    "encoding":         { "settings": { "defaultProfileName": "My HEVC", "parallelMaxConcurrentJobs": 2, "conditionalRules": [ … ] } },
    "encodingProfiles": { "profiles": [ { …EncodingProfile… } ] },
    "connections":      { "settings": { "emailSMTPHost": "smtp.example.com",
                          "sftpProfiles": [ { "id": "…", "host": "nas.local", "port": 22, "username": "media",
                                              "authMethod": { "password": { "_0": "" } }, "remotePath": "/media", "label": "NAS" } ] } },
    "thisMac":          { "settings": { "customFFmpegPath": "/opt/homebrew/bin/ffmpeg", "accurateRip.driveOffset": 6 } }
  },
  "notIncluded": ["tmdbKey", "mediaServerKey", "smtpPassword", "webhookAddress"]
}
```

**How values are written.** Values are plain JSON. Settings stored as JSON blobs (`Data`) are written out as real JSON, decoded through their Swift type, so redaction and validation happen on the typed model rather than on raw bytes. `JSONValue` already exists and is public (`IntAppsAPIClient.swift:63`). Move it to `Sources/ConverterEngine/Utilities/JSONValue.swift` without changing it, and reuse it.

**`notIncluded`** is a fixed list of names drawn from a closed set. It never holds a value.
- The names: `tmdbKey`, `meedyaDBKey`, `mediaServerKey`, `smtpPassword`, `webhookAddress`, `webhookHeaders`, `hooks`, `makeMKVConsent`, `renderFarmInsecureTransport`.
- It records which of these were set up on the Mac that exported the file. That is what lets the importing Mac say "TMDB still needs a key", because nothing else in the file could imply it. The cost is that it reveals which services were in use. Owner question 4.

**Room for #505.**
- `categories` is an open map. A category this version doesn't know is **reported and ignored**, not rejected.
- #505 adds `case submissionQueue` and a handler whose payload is `{ "submissions": [ … ] }`. The version stays at 1, and older builds simply report "1 group this version doesn't know".
- A version bump is only for breaking changes to the envelope itself.

### Engine layout (all new, in `Sources/ConverterEngine/Settings/`)

- **`SettingsCategory.swift`**: `enum SettingsCategory: String, Codable, CaseIterable { general, encoding, encodingProfiles, connections, thisMac }`. Each case has:
  - `displayName` and `explanation`;
  - `includedByDefault`, which is false only for `thisMac`;
  - `warning`, which for `thisMac` reads: *"These describe the Mac the file came from: where FFmpeg and other tools are installed, and your CD drive's model and read offset. Only include them if this Mac has the same tools in the same places and the same CD drive. A wrong read offset makes good CD rips fail their AccurateRip check."*
- **`SettingsKeyRegistry.swift`**:
  - `struct SettingsKeyEntry` holds:
    - `key` and `label` (plain English, also used as the schema `description`);
    - `decision` (`.export(SettingsCategory)` or `.never(reason: String)`);
    - `kind` (`.bool`, `.int(ClosedRange<Int>?)`, `.double(ClosedRange<Double>?)`, `.string(allowed: Set<String>?, maxLength: 4096)`, `.url(noCredentials)`, `.json(SettingsJSONCodec)`);
    - `settingsLocation` (e.g. "Settings › Encoding");
    - `importWarning` (optional, e.g. `.whenTrue("…")`);
    - `takesEffect` (`.immediately` or `.nextLaunch`).
  - `enum SettingsKeyRegistry` has `static let entries` and `entry(for:)`, plus the file-store decisions (§1).
  - For enum values that are engine types (`MediaServerType`, `SuiteCoreMetadataBackend`, the vector enums, `MeedyaDBSubmissionMode`), the allowed values are built from `allCases`.
  - For app-module enums (`AppearanceMode`, `UpdateChannel`), the allowed values are written out as literals and pinned by an app test.
- **`SettingsValueCodecs.swift`**: one typed codec per JSON blob:
  - SFTP: redacts on export, and on import requires every `.password` to be `""`;
  - Cloud: redacts, and applies the address check to `endpoint`;
  - render-farm agents, `ConditionalRule` and `EncodingPipeline`;
  - a shape-only codec for the two blobs owned by the app (`ShortcutBinding`: id, action, label, key, modifiers; `CustomTheme`: id, name, accentHex, sidebarTintHex?).
  - Each codec declares its merge rule: `.wholeValue` (shortcuts, theme) or `.byItemID` (SFTP, cloud, agents, rules, pipelines).
- **`SettingsSectionHandler.swift`**: `protocol SettingsSectionHandler { category; export; validate(payload) -> validated section; preview; apply(mode) throws }`. It has a UserDefaults-backed handler and a profiles handler. #505 adds a third.
- **`SettingsDocument.swift`**: the Codable envelope, `formatIdentifier = "meedyaconverter.settings"`, and `currentVersion = 1`.
- **`SettingsExporter.swift`**:
  - `init(defaults: UserDefaults, domainName: String, profileStore: EncodingProfileStore, presence: SettingsCredentialPresence, now:, appVersion: AppInfo.Version.number)`.
  - `makeData(categories: Set<SettingsCategory>) throws -> Data` produces pretty, sorted JSON.
  - `write(to: URL, categories:) throws` writes with `.atomic`. Both the app and the CLI call `write`, so there is one path.
  - It reads a **snapshot** from `defaults.persistentDomain(forName: domainName)`, so neither macOS-wide defaults nor registered defaults leak into the file.
  - It reads booleans and numbers by checking the underlying type (`CFBooleanGetTypeID` against CFNumber), because Foundation happily turns 1 into `true`. A stored value of the wrong type is skipped and reported, never guessed at.
  - Before returning, it runs its own output back through `SettingsImporter.prepare`, so it can never write a file it would itself refuse.
- **`SettingsImporter.swift`**:
  - `prepare(_ data: Data) throws -> SettingsImportPlan` validates the **whole** file and writes nothing.
  - `preview(_:selection:mode:) -> SettingsImportPreview` shows per category: a count, how many differ, items added / updated / removed, warnings, and plain statements.
  - `apply(_:selection:mode:) throws -> SettingsImportResult` returns keys written, keys ignored, what still needs entering, and what takes effect at next launch.
  - **Order of writing inside `apply`:** profiles first (the only step that can fail), then UserDefaults (`set` cannot fail). A failure therefore leaves everything untouched, never half-applied.
- **`SettingsCredentialNeeds.swift`**: `SettingsLeftOutItem` (the closed set), a `SettingsCredentialPresence` protocol, and a production implementation (§4).

**Errors** (`enum SettingsImportError: LocalizedError, Equatable`):

| Error | When |
|---|---|
| `fileTooLarge(bytes:limit:)` | Over 10 MB |
| `notJSON` | Not parseable |
| `notASettingsFile` | The `format` marker is missing or wrong |
| `newerFormat(found:supported:)` | Message: "This file was made by a newer version of MeedyaConverter (format 2). This version reads format 1. Update MeedyaConverter, then import again." |
| `unsupportedFormat(found:)` | Version below 1 |
| `malformed(path:reason:)` | The envelope's shape is wrong; `path` comes from the decoder's coding path |
| `invalidValue(category:key:reason:)` | A known key has the wrong type, is out of range, is not an allowed value, contains a password in an address, a profile claims to be built-in, or IDs are duplicated. **The whole file is refused.** |
| `profileStoreWriteFailed(reason:)` | At apply time only |

**Reported, never written, never fatal:**
- unknown keys;
- unknown categories;
- a known key sitting in the wrong category;
- keys marked "never" that turn up in a file (e.g. `mediaServerAPIKey`, reported as "never imported: it's a password or key");
- unknown `notIncluded` names.

**Merge and replace.**
- **Merge:** only keys present in the file are set. List-type settings add new items and update existing ones by `id`.
- **Replace:** within the **ticked** groups only, keys missing from the file are removed (back to their default), and list items or profiles missing from the file are removed.
- **Neither ever touches** a "never" key, a credential, or a group the user did not tick.

**Supporting engine changes:**
- `EncodingProfileStore.upsertUserProfiles(_:) throws` and `replaceUserProfiles(with:) throws`.
  - These keep IDs. Today's `importProfile` gives each profile a new UUID, which would break the rule-to-profile links.
  - They force `isBuiltIn = false`.
  - They write atomically and **throw** on failure. Today's `saveUserProfiles` only prints (`EncodingProfile.swift:1080-1093`).
  - They update memory only after the write succeeds.

### JSON Schema

**Files:**
- `docs/schemas/settings-export-v1.schema.json`: draft 2020-12, `$id` `urn:mwbm:meedyaconverter:settings-export:v1`.
- `docs/schemas/settings-cli-report-v1.schema.json`: for the CLI's `--format json` output.
- Both live under `docs/` so `Package.swift` doesn't need a resources or exclude change.

**How the export schema is made.** `SettingsExportSchema.generate()` builds it from the registry. Every property's `description` is the registry label. Categories get `additionalProperties: false` over their allowed keys, with per-key types, ranges and enums.
- **Honest limit:** the schema describes what *this* version writes. The importer is deliberately more lenient about unknown keys and categories; a `$comment` says so.

**Three safeguards against a leak, independent of the registry filter:**
- `sftpProfiles[].authMethod.password._0` is `{"const": ""}`.
- `cloudStorageProfiles[].accessToken` is `{"const": ""}`.
- `secretAccessKey` and `refreshToken` are forbidden (not listed, with `additionalProperties: false`).

So a real export that somehow carried a secret would fail the schema test.

**Where the schema is loose, and says so.** For the big engine models (`EncodingProfile`, which has about 45 fields; `EncodingPipeline`; `ConditionalRule`), only the identity fields are required, with `additionalProperties: true`. Each description says: "validated on import by decoding into `<Type>` (`<path>`)".

**How the validation is wired in.** No JSON Schema validator is a dependency (checked `Package.swift`, CI and `scripts/`).
- Plan a **small test-only checker**, `SettingsSchemaMiniValidator`, in `ConverterEngineTests`.
- It supports exactly: `type`, `properties`, `required`, `additionalProperties`, `items`, `enum`, `const`, `minimum`/`maximum`, `minLength`/`maxLength`, `minProperties`/`maxProperties`, `pattern`, `format` (date-time and uuid), and local `$ref`/`$defs`. It ignores `description`, `$comment`, `title`, `$id` and `$schema`.
- It **fails on any other keyword**, so the schema can't quietly use something the checker ignores.
- **What it can't catch:** it is not a conformance-tested JSON Schema implementation, and anything outside that keyword list is untested. Duplicate keys in a JSON object also can't be detected: Foundation keeps the last one.

---

## 3. How every key is found, and the "new key without a decision" test

**Judgement:**
- **A scan of the source alone** is reliable for keys written as literal strings, blind to keys reached through constants unless it has a map, and blind to keys built at runtime. It also can't carry a decision.
- **A central registry alone** carries the decisions, but can't see a new `@AppStorage` added elsewhere, which is the exact failure the owner fears.
- **So use both:** the registry holds the decisions, and the scan is the tripwire.
- **Don't convert the ~40 files to registry constants in #506.** It churns files that are currently being edited, for no gain in safety.

**`Tests/ConverterEngineTests/SettingsKeyCoverageTests.swift`** plus a test-only scanner, `SettingsSourceKeyScanner` (the name is unique within the module):

1. **Find the source.** Locate the repo from `#filePath` (up 3 levels) and fail if `Sources/` is missing. CI runs `swift build` (`build.yml:143`) and then `swift test --parallel` (:152) from the checkout.
2. **Scan every `Sources/**/*.swift` file** for:
   - literal keys: `@AppStorage\(([^)]*)\)`, taking the first string or symbol argument (this also catches `@AppStorage(wrappedValue:…, "k")`), `forKey:\s*"…"`, and `settingKey:\s*"…"`;
   - named constants: `forKey:\s*<Identifier.path>` and `@AppStorage(<Identifier.path>)`.
   - **Excluded:** `removeValue(forKey:`, any `forKey: .x` (Codable coding keys), and `forKey: "…", in:` (the tag look-ups).
3. **Named constants** must appear in a checked-in map, `SettingsKeyScanMap.symbols`, keyed as `"File.swift|symbol"` → key. For example, `"AnalyticsEngine.swift|Self.enabledKey" → "analytics_enabled"`. Otherwise they must appear in `notUserDefaults`, with a reason, for example:
   - `ThumbnailCache.swift|key` → NSCache;
   - `LocalizationManager.swift|key` → `localizedString`;
   - `AppViewModel.swift|settingKey` → callers pass literals, which are caught by the `settingKey:` pattern.
4. **Assertions:**
   - every literal and every mapped key is in the registry;
   - every registry key is still found somewhere (this catches stale entries and typos);
   - **any interpolated string at a settings call site fails** (`forKey:\s*"[^"]*\\\(`);
   - any `UserDefaults(suiteName:` outside an allowed list fails (today: `StageManagerOptimizer.swift`, plus the comment in `RenderFarmConfigurationLoader`);
   - every file that calls `applicationSupportDirectory` has a file-store decision.
5. **Checks the compiler enforces** for public constants, for example `XCTAssertEqual(map["MakeMKVSettingsTab.swift|MakeMKVConsentStore.Keys.enabled"], MakeMKVConsentStore.Keys.enabled)`. The same applies to the `MeedyaDBConfigStore.Keys.*`, `RenderFarmConfigurationLoader.Keys.*`, `ParallelEncoder.maxConcurrentJobsDefaultsKey`, `SFTPProfileStore.userDefaultsKey` and `CloudStorageProfileStore.userDefaultsKey` constants. App-internal constants (`PostEncodeActionsView.userDefaultsKey`, `HardwareAccelerationPreference.defaultsKey`) get the same check in `MeedyaConverterCoreTests` via `@testable`.
6. **Test the detector itself.** Feed the scanner synthetic source: `@AppStorage("brandNewApiKey")`, `forKey: "x.y"`, `@AppStorage(wrappedValue: 1, "k")`, and an interpolated key. Assert all are found or flagged.
7. **Force every new key into the round trip.** The round-trip test has a sample value for every allowed key and **fails if an allowed key has no sample**.

**What the scan cannot catch (to be written in its header):**
- keys written by frameworks (Sparkle `SU*`, AppKit window frames, the open panel's last folder). The allow-list never exports them, which is the safe direction;
- keys written through other APIs (`register(defaults:)`, `setValuesForKeys`, bindings; none exist today);
- a **private** constant whose string changes without the map being updated (`AnalyticsEngine`, `KeyboardShortcutManager.storageKey`, `LocalizationManager.languageKey`, `EntitlementGating`). The round trip covers the allowed ones among them;
- keys held in other apps' domains or App Group suites (the `suiteName` tripwire flags new ones);
- comments that mention a key count as "found", so a comment alone could keep a dead registry entry alive. That can only err towards flagging, never towards hiding.

**#508** adds `AutoTagSettingsStore.Keys.enabled` and `writeNFO`, and `@AppStorage(AutoTagSettingsStore.Keys.enabled)` in `AutoTagSettingsSection.swift`. Whichever of #506 and #508 lands second must add the registry entries, map entries and round-trip samples. The test enforces this.

---

## 4. The `mediaServerAPIKey` migration, and the webhook verdict

**What exists today.** There is no `.mediaServer` provider. Add `case mediaServer = "media_server"` to `APIKeyProvider` (`APIKeyManager.swift:20-50`), with `displayName` "Media server (Plex, Jellyfin, Emby)" and a new `APIKeyCategory.mediaServers`. `keys(in:)` and `APIKeyCategory.allCases` have no callers, so the new category is safe to add. The only exhaustive switches over the provider are in this file (`displayName` and `category`).

**New file `Sources/ConverterEngine/Cloud/MediaServerCredentialStore.swift`:**
- `legacyDefaultsKey = "mediaServerAPIKey"` and `keyLabel = "Media Server"`.
- A small protocol, `MediaServerKeyStoring`, over `APIKeyManager`, so tests can put a failing fake Keychain in its place.
- `migrateLegacyKeyIfNeeded(defaults:store:) -> MigrationOutcome`, where the outcome is `.nothingToMigrate`, `.removedEmptyLegacyValue`, `.migrated`, or `.failedKeptLegacyValue(reason)`.
- `currentKey(defaults:store:)` looks in the Keychain first. It falls back to the old settings-file value **only while that value still exists**, i.e. only while migration keeps failing.
- `saveKey` and `removeKey`.

**Migration steps:**
1. Read the old value once. If absent: nothing to do.
2. If blank: remove it and stop.
3. Otherwise `storeKey(StoredAPIKey(provider: .mediaServer, apiKey: old, label: keyLabel))`. **The old value always wins**, even over a different value already in the Keychain. The current build never writes the old key, so an old value can only exist because either the app crashed between steps 3 and 4, or an older build wrote it more recently.
4. **Verify by reading back.** `key(for: .mediaServer)?.apiKey == old`. After the in-flight change this re-reads `api_keys.json` and the Keychain before answering. This matters: `storeKey` does not report Keychain failures (`APIKeyManager.swift:447-461`). The Keychain-backed test also asserts through a second, freshly created manager.
5. If they match, remove `mediaServerAPIKey` from UserDefaults. If they don't, **leave it** and return `.failedKeptLegacyValue`.

**When it runs:** once per launch, from `AppViewModel.init` via a tiny `AppStartupMigrations.run(defaults:keyManager:)` that returns its outcomes.
- **Next launch:** the old key is gone, so it does nothing.
- **On failure:** the old value stays, is retried every launch, and auto-scan keeps working through the fallback. The Media Server screen shows: *"Your media server key is still in the app's settings file because the Keychain didn't accept it. It will be moved automatically when the Keychain allows."*
- **If someone downgrades** after a successful migration: the older build finds no key and auto-scan stops until the key is re-entered.

**`MediaServerSettingsView.swift` changes:**
- Replace the `@AppStorage` at :42 with a `SecureField` for typing a new key, plus Save / Replace / Remove buttons and "A key is saved in your Keychain". Copy the pattern of `MetadataSettingsTab.providerKeysSection`.
- Listen for `didChangeNotification` so the screen refreshes.
- `loadMediaServerConfig(defaults: = .standard, keyManager: = APIKeyManager())` (:93-115) gets its key from `currentKey`.
- **Also fix:** `currentConfig` (:76-78) runs on every redraw. After this change it would hit the Keychain every time, so enable the buttons from `hasKey && !host.isEmpty` and build the full config only inside the actions.

**SECURITY.md:**
- Add **F-013**: `mediaServerAPIKey` was stored in plain text (fixed), and `webhookURL` / `webhookCustomHeaders` are still open (tracked).
- **Correct F-004(c).** It says "no `UserDefaults.standard.set` writes a credential", but that search missed `@AppStorage`, which is how this key got in.

**Verdict on `webhookCustomHeaders`:** never exported. **Yes, it should also move to the Keychain, and so should `webhookURL`.** Both are secret-bearing values in a plain-text file. Move them in their own small change using the same migration pattern, with the whole headers blob stored as one Keychain item. In the same change, mask header values in the Settings list (:114 shows them in clear text). Export is safe regardless.

**What the "still needs a key" step reads, and it never reads a secret:**
- **API keys:** the APIKeyManager index (`~/Library/Application Support/MeedyaConverter/Keys/api_keys.json`, re-read fresh as per the in-flight change) for an active record, plus the matching Keychain item: service `Ltd.MWBMpartners.MeedyaConverter.APIKeys`, account `<provider>:<label|default>`. This covers TMDB, MeedyaDB, the media server, and cloud storage (by provider and label).
  - This needs a new `APIKeyManager.hasStoredKey(for:label:) -> Bool`. It reads the index **without loading the secrets from the Keychain**, and calls a new private `KeychainStore.exists`.
  - The index lookup behaves like `reloadLocked`'s two cases. If the index file is missing, the key counts as missing. If the file exists but can't be read, the item is shown as "couldn't check" rather than "missing".
- **SFTP:** a new `SFTPCredentialStore.exists(forProfileID:)` (service `com.mwbm.MeedyaConverter.sftp`, account = profile UUID), plus `FileManager.fileExists` for `.keyFile` paths.
- **SMTP:** service `Ltd.MWBMpartners.MeedyaConverter.smtp`, account `smtpPassword`. Move those two constants into the engine and point `EmailSettingsView.swift:391-394` at them.
- **Webhook:** `webhookURL` non-empty in UserDefaults (until it moves).
- **MakeMKV:** `MakeMKVConsentStore.consent(in:) != nil`.
- **Render farm:** `RenderFarmConfigurationLoader.loadConfiguration().insecureTransportOverride`.
- **How the Keychain is asked:** attributes only, with no `kSecReturnData`. The CLI is a different program from the app, and reading secret data the app saved would probably make macOS prompt, or fail.

---

## 5. The app

**Where it lives.** A new tab, `Tab("Import & Export", systemImage: "square.and.arrow.up.on.square")`, in the "Account" section, placed just before Updates (`SettingsView.swift:144`). That is a one-line insertion, made after the in-flight `SettingsView` commit.
- `Sources/MeedyaConverter/Views/SettingsTransferTab.swift`
- `Sources/MeedyaConverter/Views/SettingsImportPreviewSheet.swift`
- `Sources/MeedyaConverter/ViewModels/SettingsTransferViewModel.swift`, which holds all the logic and receives the file panels as closures, so tests can drive it.

**Export section:**
- One tick box per group; "This Mac only" is off, with its warning.
- An "Export Settings…" button opens an `NSSavePanel` (`UTType.json`, named "MeedyaConverter Settings YYYY-MM-DD.json") and calls `exporter.write(to:)`.
- Success is shown in place: "Saved “…”."
- **Errors appear in an alert.** The profile screen's export only logs errors (`ProfileManagementView.swift:333-335`); don't copy that part.
- Caption: *"Saves your preferences, encoding profiles and connection details to a file you can import on another Mac. Passwords and API keys are never included: you enter those again on the other Mac."*
- A disclosure, "What's never included", lists every "never" entry with its reason, generated from the registry so it can't go out of date.

**Import section:**
- "Import Settings…" opens an `NSOpenPanel` and calls `prepare`. On error, an alert gives the reason and says **"Nothing was changed."**
- The preview sheet shows:
  - the source: "Made by MeedyaConverter 0.1.0 on 25 Sep 2026";
  - per group: a tick box, a count (e.g. "14 settings, 5 differ from yours"; "3 profiles: 2 new, 1 updates one you have"), and a disclosure showing each item's file value against yours;
  - warnings, including "Delete source after successful encode: ON";
  - cross-checks. For example: "Default profile ‘My HEVC’ isn't on this Mac and isn't being imported, so Web Standard will be used."
  - ignored items: "2 settings this version doesn't know will be ignored: …".
- **Mode choice:**
  - **"Add to my settings (recommended)"**: *"Only the settings in this file change. Anything the file doesn't mention stays as it is."*
  - **"Replace my settings in the ticked groups"**: *"Makes the ticked groups match the file exactly. Settings in those groups that aren't in the file go back to their defaults, and profiles, servers and rules that aren't in the file are removed. Passwords and keys are never touched."*
  - Replace asks for confirmation, with counts: "This removes 2 profiles and 1 SFTP server."
- **Result, in the same sheet:**
  - "Imported 31 settings and 3 profiles."
  - "Still needed on this Mac", listing each item with its real location. SFTP and Cloud Storage are in the **main window's sidebar**, not in Settings (`AppViewModel.swift:162-165`, `ContentView.swift:183-187`). Examples:
    - "TMDB key: Settings › Metadata"
    - "Media server key: Settings › Media Server"
    - "SMTP password: Settings › Email"
    - "Webhook address: Settings › Webhooks. For Slack and Discord the address works like a password, so it's never copied."
    - "SFTP server ‘NAS’ password: SFTP, in the main window's sidebar"
    - "MakeMKV: Settings › MakeMKV. The terms have to be accepted on each Mac."
    - "Hooks aren't copied: set them up again in Settings › Hooks."
  - "These take effect next time you open MeedyaConverter: …"
- **Never claim** "your setup has been restored", or that anything is "secure".

**Reloads that stop an import being silently undone:**
- `AppViewModel.reloadAfterSettingsImport(from defaults: = .standard)` re-reads `savedPipelines`.
- `KeyboardShortcutManager.reloadFromDefaults(_:)` re-reads the shortcuts without writing them back (its `didSet` always saves, so it needs a guard).
- `ThemeManager`, which is `@State` in `MeedyaConverterApp`, and the other settings read only at launch are marked `.nextLaunch` and listed in the result.
- Profiles go through the live `viewModel.engine.profileStore`, **never a new store object**. A second store would lose updates exactly like the in-flight `APIKeyManager` bug.

---

## 6. The CLI

**New file** `Sources/meedya-convert/Commands/SettingsCommand.swift`, registered in `MeedyaConvert.swift:21-30`. It is a parent command with subcommands, like `DiscCommand` (`DiscCommand.swift:28-39`). `ProfilesCommand` uses `--export`/`--import` flags instead.

```
meedya-convert settings export <file> [--categories general,encoding,encodingProfiles,connections[,thisMac]] [--format text|json]
meedya-convert settings import <file> [--apply] [--replace] [--categories …] [--format text|json]
```

- **Default groups:** all except `thisMac`. Naming `thisMac` prints the warning to stderr.
- **`import` shows the preview only, unless `--apply` is given.** This keeps "preview before writing" (owner decision 5) without an interactive prompt. Owner question 2.
- **`--format`** copies the newer `DiscOutputFormat` convention (`DiscCommand.swift:16-19`). The `--format json` report is the engine's `SettingsTransferReport`, checked against `settings-cli-report-v1.schema.json`.
- **Which settings file it uses:** `UserDefaults(suiteName: AppInfo.Application.directBundleId)` (`AppInfo.swift:29`). **Never `.standard`**: in a command-line tool that is a different, empty domain, and the command would quietly export nothing.
  - **Limit:** the App Store build keeps its settings inside a sandbox the CLI can't reach. The CLI works with the Direct build only; say so in `--help` and the docs.
  - Call `synchronize()` before exit so the writes are saved.
- **Refuses `--apply` while MeedyaConverter is running.** Detected with `NSRunningApplication` (`import AppKit` in this file only). Message: *"MeedyaConverter is open. Quit it first: it keeps some settings in memory and would overwrite what you import the next time it saves."*
- **Hidden test options** `--defaults-suite` and `--profiles-dir`. When these are set, the running-app check is skipped.
- **Exit codes** (`CLIUtilities.swift:16-40`):
  - 0: done or previewed
  - 2: bad arguments
  - 3: file not found
  - 5: export write error
  - 6: invalid file or newer format
  - 1: app running, or any other error
- **Text output:** a header (app version and date), one row per group with counts, the ignored items, the mode, "Nothing has been changed. Run again with --apply to import." After applying, the same "still needed" and "next launch" lists as the app.

---

## 7. Tests (each one checks the real result, not just that a function was called)

Every test uses its own `UserDefaults` suite named with a fresh UUID, removed in `tearDown`, and a temporary profiles directory. Keychain tests use a UUID service and skip when the Keychain round-trip probe fails (`APIKeyManagerKeychainTests.swift:70-140`). Async mocks use `lock.withLock {}`. Helper type names are unique within their module.

**ConverterEngineTests:**
1. **`SettingsKeyCoverageTests`** (§3): undecided key, stale entry, interpolated key, unexpected suite, file-store decisions, public-constant equality, and the planted-key detector test.
2. **`SettingsExportNoSecretTests`.** Plant sentinel strings (`SENTINEL-…`) everywhere a secret could hide:
   - `mediaServerAPIKey`;
   - a Discord `webhookURL`;
   - `webhookCustomHeaders` holding `Authorization: Bearer`;
   - an **unmigrated** `sftpProfiles` blob with a plaintext password;
   - `cloudStorageProfiles` with unredacted tokens and an S3 secret;
   - `gitRemote` as `https://user:SENTINEL@…`;
   - a hook chain with a script;
   - the analytics ID and the licence cache;
   - and, where the Keychain works, a real TMDB key.

   Then export with **every** group ticked, write the file, re-read the **bytes on disk**, and assert that "SENTINEL" appears nowhere.
3. **`SettingsImportValidationTests`.** Each bad file below must be refused as a whole, with **the suite's settings identical before and after** (compare `persistentDomain` snapshots):
   - newer version;
   - not JSON;
   - wrong marker;
   - version 0;
   - no `categories`;
   - a string where a bool belongs, alongside valid keys;
   - port 70000;
   - an unknown enum value;
   - an address containing a password;
   - a profile marked built-in;
   - a file over the size limit.

   Also: unknown key, unknown group, a known key in the wrong group, and a "never" key present in the file are all ignored and reported, and absent from the suite after apply.
4. **`SettingsRoundTripTests`:**
   - every allowed key gets a sample that is **not** its default; export, apply to a fresh suite and store, and check each value by type and each profile by `id`;
   - the same through a file on disk;
   - merge keeps local-only keys and items; replace removes them only in ticked groups; neither touches unticked groups or "never" keys;
   - SFTP merge keeps a local profile and its Keychain password;
   - `thisMac` is not applied unless ticked;
   - **half-apply guard:** make the profiles directory unwritable; `apply` throws and the settings are unchanged;
   - `SettingsImporter.prepare(exporter output)` always succeeds.
5. **`SettingsCredentialNeedsTests`:** with a fake presence checker, the right items and locations are listed. Password-auth SFTP and missing key files are listed. The Keychain query builder **never** includes `kSecReturnData`.
   - **Honest limit:** this checks the query, not the absence of a prompt. That needs one manual run of the CLI against a real app Keychain.
6. **`MediaServerCredentialMigrationTests`:**
   - with the fake store: migrates and removes the old value; a failing store keeps the old value and reports failure; a blank value is removed; an absent value does nothing; the old value wins over a different stored one;
   - with a real `APIKeyManager` (skip if no Keychain): after migration, a **fresh** manager returns the key and the suite no longer has it;
   - `saveKey` never writes to UserDefaults.
7. **`SettingsSchemaTests`:**
   - the generated schema equals the checked-in file (on mismatch, the failure message gives the path of a regenerated copy);
   - a real full export passes the checker;
   - every property has a non-empty `description`;
   - the checker rejects a wrong type, a missing required field, a non-empty SFTP password, and an unknown keyword.
8. **`EncodingProfileStoreBulkImportTests`:** IDs are kept; built-ins are kept on replace; a write failure throws and leaves memory unchanged.

**MeedyaConvertTests:**

9. **`SettingsCommandProcessTests`.** Run the **built** `meedya-convert` from the products directory (skip if it isn't there; CI builds it first). Watchdog: 30 s per run, then terminate and fail (W16).
   - `export --defaults-suite S --profiles-dir D`: exit 0, the file exists, no sentinel.
   - `import … --defaults-suite S2 --apply --format json`: exit 0; S2 holds the values; the JSON output passes the report schema.
   - `import` without `--apply`: S3 unchanged.
   - A newer-format file: exit 6, unchanged.
   - Call `synchronize()` before each run, because this reads settings across processes.

**MeedyaConverterCoreTests:**

10. **`SettingsTransferViewModelTests`** (injected suite, store, presence checker and panel closures):
    - export writes a real file with no sentinel;
    - the preview has This Mac off;
    - confirming writes the suite;
    - replace needs its confirmation step;
    - a bad file sets `errorMessage`, not just a log line.
11. **`SettingsImportReloadTests`:** after an import, `reloadAfterSettingsImport(from:)` shows the imported `savedPipelines`; the shortcut manager shows the imported bindings and did not write back.
12. **`SettingsRegistryAppConstantsTests`:** the registry's allowed values match `AppearanceMode.allCases` and `UpdateChannel.allCases`; the `PostEncodeActionsView.userDefaultsKey` and `HardwareAccelerationPreference.defaultsKey` mappings are right.
13. **`MediaServerSettingsWiringTests`:** `loadMediaServerConfig(defaults:keyManager:)` returns the key from the Keychain; `AppStartupMigrations.run` includes the media-server migration.

---

## 8. Commits, in order (each builds on its own)

Gate for every Swift commit: `swift build --target ConverterEngine`, then the filtered whole-package build. `swift test` and SwiftLint can't run locally; CI runs them.

0. **Prerequisite, not ours:** the in-flight `APIKeyManager` / `SettingsView` / `MeedyaDBSettingsTab` commit and the Codex round-1 fixes have landed.
1. **`fix(security): keep the media server key in the Keychain, not the settings file`.** Sonnet builds; Opus checks the migration.
   - Files: `APIKeyManager.swift` (provider and category only), the new `Cloud/MediaServerCredentialStore.swift`, `MediaServerSettingsView.swift`, `AppViewModel.swift` (one startup line), SECURITY.md (F-013 and the F-004 correction), test files 6 and 13.
2. **`feat(engine): check a key is saved without reading it`.** **Opus** (Keychain behaviour).
   - `APIKeyManager.hasStoredKey`, private `KeychainStore.exists`, `SFTPCredentialStore.exists`, the SMTP constants moved into the engine (with a small `EmailSettingsView` edit), and tests.
3. **`feat(engine): bulk profile import that keeps IDs and reports failure`.** Sonnet. `EncodingProfileStore` and test file 8.
4. **`feat(settings): the allow-list, and a test that fails on an undecided setting`.** **Opus.** The `JSONValue` move, `SettingsCategory`, `SettingsKeyRegistry` (all 104 keys and 13 file stores), the scanner, test 1, and test 12.
5. **`feat(settings): export and import in the engine`.** **Opus.** Codecs and redaction, handlers, document, exporter, importer, credential needs, report, and tests 2–5.
6. **`feat(settings): JSON Schema for the settings file, checked by a test`.** Sonnet. The generator, both schema files, the checker, and test 7.
7. **`feat(cli): meedya-convert settings export/import`.** Sonnet builds; Opus checks. `SettingsCommand.swift`, its registration, and test 9.
8. **`feat(ui): Import & Export in Settings`.** Sonnet builds; Opus checks. The view model, tab and sheet, the one-line insertion in `SettingsView.swift`, the reload hooks, and tests 10–11.
9. **`docs: settings export/import`.** Haiku or Sonnet.
   - `docs/CLI-Reference.md`; the `/settings` paths in `docs/api/meedya-convert-api.yaml`;
   - a Help topic `Resources/Help/settings-transfer.md`, plus its metadata entry in `HelpView.swift` (around line 263);
   - a FAQ entry, "Does a settings file contain my passwords?";
   - User-Guide, Architecture, FEATURES, README, CHANGELOG;
   - tick #506's acceptance criteria with evidence, and open the follow-up issues (§9).

**Dependencies between them:** 4 → 5 → 6 → 7 and 8. Commit 2 comes before 5. Commit 1 comes first and stands alone.

---

## 9. Risks, questions for you, and what the issue got wrong

### Risks

- **Keychain prompt from the CLI.** Reading secret data the app saved would probably prompt or fail in the CLI. Attribute-only checks are designed to avoid this, but no test can prove it; it needs one manual run.
- **Downgrading after a new provider is added.** Older builds can't read an index file containing `media_server`, so every API key looks missing to them. If the older build then saves a key, it rewrites the index and orphans the other records; the secrets stay in the Keychain. The same risk was accepted when `.intAppsAPI` was added (`abcd0f9`). Follow-up: decode records one by one, so an unknown provider hides only its own record.
- **Settings loaded once and written back whole** could undo an import. Reload hooks cover pipelines and shortcuts; everything else is marked "next launch".
- **Reading settings across processes** (the CLI test) can be flaky; hence `synchronize()` on both sides.
- **The schema is generated from the registry**, so it is not an independent judge of which keys are allowed or never. The sentinel test is the independent one.
- **The scan's blind spots** are listed in §3.

### Questions for you (with the recommended answer)

1. **Leave hooks out of v1?** **Yes.** Follow-up: allow the actions that don't execute anything (notification, reveal in Finder, SFTP or cloud upload by profile); always leave out scripts, webhook addresses and "move to Trash".
2. **Should CLI `import` only preview unless `--apply` is given?** **Yes.**
3. **Should "This Mac" be off by default on export as well as import?** **Yes.**
4. **Should the file name which services were set up (`notIncluded`, names only)?** **Yes.** Without it, "TMDB still needs a key" can't be said.
5. **Move `webhookURL` and `webhookCustomHeaders` to the Keychain: now or as a follow-up?** **A follow-up issue straight after #506**, using the same pattern. Export is safe regardless.
6. **Consents never travel** (MakeMKV terms, the render-farm insecure opt-in, analytics)? **Yes.**
7. **Include encoding profiles as their own group?** **Yes.**
8. **May the presence check add a small method to `APIKeyManager` after the in-flight work lands?** **Yes.**

### What the issue got wrong

- **"~74 settings across 27 files".** It is 104 keys across about 40 files, plus 13 Application Support stores.
- **`webhookURL` is missing from the risk table.** Slack and Discord addresses are secrets.
- **`postEncodeActionChain`** is described as holding connection details. It can hold **shell commands**, and it belongs to the app, not the engine.
- **It lists 4 engine-owned keys.** There are many more: `renderFarm.*`, `makemkv.*`, `meedyadb.*`, `analytics_*`, the entitlement cache, `cloudProfileSyncEnabled`, `sftpProfiles`, `cloudStorageProfiles` and `parallelMaxConcurrentJobs`.
- **It doesn't mention these, all of which travel badly:**
  - the licence cache;
  - the analytics installation ID;
  - SFTP blobs that were never migrated;
  - tokens inside git addresses.
- **The pattern to copy is not quite as described.**
  - Profile export errors are only logged, not shown.
  - `ProfilesCommand` uses flags and encodes the JSON itself instead of calling the engine's `exportProfile`.
  - The engine's `importProfile` gives each profile a new ID, which breaks rule-to-profile links.
- **"Merge touches only keys present"** would delete local SFTP servers, rules and pipelines. List-type settings need merging by `id`.
- **The CLI's settings domain and the App Store sandbox** aren't mentioned.

### Pre-existing bugs found (raise as issues; don't fix here)

- **Built-in profiles get a new random ID every launch.** `EncodingProfile.init(id: UUID = UUID())` (`EncodingProfile.swift:196`), with `webStandard` at :496. Conditional rules find their profile by ID (`ConditionalRule.swift:241`) and default to the first built-in (`ConditionalRulesView.swift:227`). So most rules stop matching after a relaunch.
- **SECURITY.md's F-004(c) is false**, as covered in §4.
- **Legacy plaintext SFTP passwords are only migrated when the SFTP screen is opened.** They should also be migrated at launch.

---

## 10. Overlap with work in flight, and with `02a5964..HEAD`

- **`APIKeyManager.swift` (in flight).**
  - Commit 1 edits only the provider list and categories (lines 20-140).
  - Commit 2 adds a method after `configuredProviders()` and a private `KeychainStore.exists`, next to the in-flight changes around 520-610.
  - **Both must wait for the in-flight commit.** Commit 1's check-by-reading-back relies on its re-read-before-lookup behaviour.
- **`SettingsView.swift` (in flight, plus Codex F7 wording at :460-461).** Only a one-line `Tab` insertion before :144, made after that commit.
- **`MeedyaDBSettingsTab.swift`, the MakeMKV rip screen, the disc identify screen and their view models:** not edited. The scan only reads them.
- **#508** adds keys (handled by the tripwire, §3) and also edits `AppViewModel.init` (around 576). Commit 1 adds one startup line there; put it on a separate line and expect a trivial conflict.
- **Codex specs:** they touch `docs/FAQ.md:214-227`. Commit 9 adds a separate FAQ entry, so keep it out of those lines.
- **Files in `02a5964..HEAD` this plan touches:**
  - `AppViewModel.swift` (+24 in that range): commit 1's startup line and commit 8's reload hook;
  - `SettingsView.swift`: the one-line tab insertion;
  - `HelpView.swift`: one Help topic entry (commit 9);
  - `docs/api/meedya-convert-api.yaml` (+101) and `docs/FAQ.md`: commit 9.

  Files in that range the plan only reads, and must map in the registry: `MeedyaDBAccess.swift` and `MakeMKVAccess.swift` (their `Keys` enums), `MakeMKVSettingsTab.swift`, `MakeMKVRipView.swift`, `DiscIdentifyView.swift`. `DiscCommand.swift` is the CLI pattern being copied and is not edited.

### Critical files for implementation
- `Sources/ConverterEngine/Cloud/APIKeyManager.swift` (in flight: the new provider, and presence checks that never read the secret)
- `Sources/MeedyaConverter/Views/MediaServerSettingsView.swift` (the leak, and its move to the Keychain)
- `Sources/ConverterEngine/Encoding/EncodingProfile.swift` (bulk profile import that keeps IDs and throws on failure, :903-1093)
- `Sources/ConverterEngine/Settings/SettingsKeyRegistry.swift` (new: the 104-key allow/never table) and `Tests/ConverterEngineTests/SettingsKeyCoverageTests.swift` (new: the tripwire)
- `Sources/meedya-convert/Commands/SettingsCommand.swift` (new; copies `DiscCommand.swift` conventions and must use `AppInfo.Application.directBundleId`)
