<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — Ranked new-work proposals for the alpha cycle (wip/alpha-consolidation @ 9511291)

Grounded against the tree on 2026-09-02. Items already queued in `.claude/HANDOFF.md` "RESUME HERE" (Background Removal save, Storage Analysis ffprobe, Smart Crop video, Team Profile git, metadata lookup, vector tracers) are deliberately not repeated.

---

**1. Make the `alpha` branch produce a real installable build (notarized .app + DMG with bundled ffmpeg)** — net-new; supports #428
Rationale: `.github/workflows/beta-alpha.yml` "Package release artifacts" (lines 238-258) tars up only `.build/release/meedya-convert` — an alpha push today ships testers a bare CLI, not the app. `dev-build.yml` builds an .app (146-215) but never runs `scripts/bundle-ffmpeg.sh` and codesigns the DMG without notarizing (274-306), so testers need Homebrew ffmpeg and get Gatekeeper prompts. `release.yml` has the full correct chain (Create app bundle 340 → Bundle FFmpeg 433 → Sign 452 → Notarize 477 → DMG 492 → notarize DMG 501).
Touches: extract release.yml steps 340-517 into a `workflow_call` reusable workflow (`.github/workflows/package-app.yml`); consume from `beta-alpha.yml` and `release.yml`; `dev-build.yml` optionally. Uses the six org-level `APPLE_*` secrets (already accessible per memory).
Effort: M. Risk: workflow refactor of the one proven release path — verify with a throwaway tag on `alpha` and `spctl --assess` + `docs/distribution/direct-release.md` §6 smoke checklist before touching release.yml's caller. Watch CI to green.

**2. Direct-build entitlement provider: unlock all tiers when `!APP_STORE`** — maps #286, #424 (decides "extend #307")
Rationale: `FeatureGateManager.shared` defaults to `FreeGateProvider` and nothing in `MeedyaConverterApp.swift`/`AppViewModel.swift` ever sets a provider for Direct builds. The only GUI consumers are `AppViewModel.swift:2072` and `ParallelEncodingView.swift:61` (`.parallelEncoding`, a `.plus` feature per `EntitlementGating.swift:213`), so `ParallelEncoder.resolveConcurrency` (ParallelEncoder.swift:184) clamps every alpha tester to 1 — the exact "width > 1 unverified" gap HANDOFF records for #286. `rc4-known-limitations.md` currently contradicts itself ("All features are free" vs "limited to 1 concurrent job").
Touches: new `DirectBuildGateProvider` (returns `.pro`) in `Sources/ConverterEngine/Licensing/EntitlementGating.swift`; set it in `AppViewModel.init` under `#if !APP_STORE`; while there, make `resolveConcurrency` read `ProcessInfo.processInfo.thermalState` (serious/critical → halve, min 1) since testers will first exercise parallel width on laptops; fix the limitations doc.
Effort: S. Risk: the TaskGroup concurrency path (AppViewModel.swift:1445-1524) has never run at width > 1 in the wild — that is why we want testers on it; default the slider to 2, not max.

**3. "Save Diagnostics Bundle…" + git SHA baked into the build** — net-new
Rationale: alpha bug reports will be unactionable without version/sha/ffmpeg/hardware context. `ActivityLogView.swift:211-242` already exports text/JSON and `LogEntry.Source.ffmpeg` (AppViewModel.swift:2691) captures stderr, but there is no single artefact to attach to an issue. `dev-build.yml:109` computes `SHORT_SHA` and then discards it; no view shows a commit.
Touches: `AppViewModel.exportLogAsText` → new `DiagnosticsBundle` (ConverterEngine) collecting CFBundleShortVersionString/CFBundleVersion/`MWBMGitCommit`, macOS version, arch, `FFmpegBundleManager().locateFFmpeg()` path + `ffmpeg -version`, `HardwareEncoderDetector` result, last 500 log entries, checkpoint list, settings minus secrets; "Save Diagnostics Bundle…" button in `ActivityLogView` and Settings; PlistBuddy `Set :MWBMGitCommit` in all three packaging workflows; show sha in About/Settings.
Effort: M. Verification: unit-test the redaction (Keychain-backed keys must not leak); manual open of the zip.

**4. Pre-release update channel in `GitHubReleaseChecker`** — maps #416/#428 (pre-Sparkle)
Rationale: `GitHubReleaseChecker.swift:232` only accepts `prerelease == false && draft == false`, so an alpha tester on `v0.1.0-alpha.3` is never told `alpha.4` exists — the one update mechanism the alpha cycle actually has (`updates.md:72` says Sparkle is v0.2.0).
Touches: `UpdateChannel` enum (stable/beta/alpha) persisted via `@AppStorage("updateChannel")` in `SettingsView.swift` (~719 update tab); channel-aware filter + semver-with-prerelease ordering in `GitHubReleaseChecker.check`; `AppUpdateChecker.swift:353` passes the channel; a fixture-JSON unit test in `Tests/`.
Effort: S. Risk: version comparison must treat `0.1.0-alpha.4 < 0.1.0`; test that explicitly.

**5. First-launch ffmpeg self-test with a visible banner** — net-new
Rationale: `direct-release.md` §6 step 5 states the only proof the bundled ffmpeg works is running it; nothing in `AppViewModel.init` (528-548) does. Only `ConvertMediaIntent`, `DualDynamicHDRView`, `MetadataTagEditorView`, `BenchmarkView` call `locateFFmpeg()` ad hoc; a tester whose ffmpeg is missing/quarantined discovers it on the first failed encode.
Touches: `AppViewModel.init` → async `verifyToolchain()` running `ffmpeg -version` and `ffprobe -version` via `FFmpegProcessController`; publish `toolchainStatus`; banner in `ContentView.swift` linking to `HelpView.swift:473` ("FFmpeg Not Found") and the Settings path fields (#475); an extra `OnboardingView.swift` page showing detected ffmpeg + hardware encoders.
Effort: S-M. Verification: temporarily rename `Contents/Helpers/ffmpeg` in a built .app and confirm the banner.

**6. ffmpeg-gated integration test tier** — maps #479
Rationale: the recurring alpha-cycle defect class is "arguments build, ffmpeg rejects at runtime" (crossfade offsets, `-map_chapters`, two-pass vidstab, concat). `build.yml:152` runs `swift test --parallel` on macos-15 where ffmpeg can be installed, yet only 4 `XCTSkip` uses exist and none are ffmpeg-gated. Fixtures can be synthesised with `ffmpeg -f lavfi -i testsrc` at test time — no binary fixtures in git.
Touches: `Tests/ConverterEngineTests/Integration/` with a `FFmpegFixture` helper gated on `MEEDYA_FFMPEG_TESTS=1`; `build.yml` `brew install ffmpeg` + env var; first cases: encode round-trip per hardware/software profile, demuxer concat, yadif, chapter embed, stabilization pass 1+2.
Effort: M. Risk: CI time — cap at ~2 min with 2-second clips.

**7. In-app "What's in this alpha" — known-limitations in Help + onboarding** — net-new; supports #428
Rationale: `docs/distribution/rc4-known-limitations.md` is the honest list but lives only in the repo; testers will file bugs against hidden/disabled features (Filter Graph, Render Farm, crossfade, resume). `Sources/MeedyaConverter/Resources/Help/` already bundles markdown (`updates.md`, `troubleshooting.md`).
Touches: copy the limitations doc into `Resources/Help/known-limitations.md` (single source: a script or CI check that the two match); `HelpView.swift` entry; final `OnboardingView.swift` page "What to test / what not to report" with a link to the GitHub issue template.
Effort: S. Verification: doc-sync check in `lint.yml` so it can't drift.

**8. Failed-job forensics in the queue + crash breadcrumb file** — net-new
Rationale: `FFmpegProcessController.swift:15-32` truncates stderr to 500 chars in the thrown error, and there is no `NSSetUncaughtExceptionHandler`/signal handler anywhere in `Sources/`, so a crash leaves no trace for the tester to send.
Touches: per-job "Show FFmpeg log" (full `stderrBuffer`) and "Copy command line" actions on failed rows in the queue view, fed from `EncodingEngine`; minimal uncaught-exception handler in `MeedyaConverterApp.swift` writing `~/Library/Application Support/MeedyaConverter/crash-<date>.log` with the last log tail; next launch offers to include it in the diagnostics bundle (#3).
Effort: S-M. Risk: exception handler must be allocation-free and never throw; keep it to a synchronous file write.

**9. Stale/false comment housekeeping PR** — maps #280, #281, #302, #320 comments; memory "false comments are the recurring defect"
Rationale: four header comments describe features that do not exist and will mislead the next implementer: `Components/MiniPlayerWindow.swift` header (auto-show on minimise), `Components/MenuBarController.swift:17` (drag-and-drop), `Views/MetadataTagEditorView.swift:17` (batch tag editing), `Scripting/ScriptingBridge.swift:302-312` (claims the sdef has no `<cocoa>` mappings — now false, dispatch is live). HANDOFF also flags `BackgroundRemover.swift:~237`.
Touches: those five files only; no behaviour change.
Effort: S. Verification: compile gate; re-grep each claim.

**10. Concatenation crossfade — implement it, or hide the disabled controls** — maps #322
Rationale: `ConcatenationView.swift:322-345` shows a permanently `.disabled(true)` toggle/slider and `runFilterConcat` (695) always passes `crossfade: nil`; disabled controls generate "it doesn't work" reports. Durations are already obtainable via `FFmpegProbe`.
Touches: probe each clip's duration in `ConcatenationView.runFilterConcat` (687-721), compute cumulative `xfade`/`acrossfade` offsets in the existing concat builder, enable the controls; add an argument-builder unit test with three clips. Fallback if not done for alpha: remove the controls and add a one-line note.
Effort: M (implement) / S (hide). Risk: audio/video stream count mismatches — validate all clips have the same stream layout before offering crossfade.

**11. Persist `outputMode`; relabel "Resume" as "Restart"** — maps #275, #468
Rationale: `AppViewModel.swift:369` `outputMode` has no `@AppStorage`/UserDefaults, so mirror mode silently reverts to Flatten every launch. `ResumableJobsView.swift:158-195` re-queues from 0% while the button says Resume — a guaranteed alpha bug report.
Touches: UserDefaults load/save around `outputMode` (pattern at AppViewModel.swift:565-570 for `defaultProfileName`); button title + help text in `ResumableJobsView`; update the limitations doc line.
Effort: S. Verification: relaunch test; string-only change for the label.

**12. Menu-bar icon drag-and-drop** — maps #281 (headline item)
Rationale: the one #281 feature testers will try first (the header comment advertises it) does not exist — no `registerForDraggedTypes`/`NSDraggingDestination` anywhere in `Sources/`. `MenuBarController` already has a live path to `AppViewModel` via `wireMenuBarActions()` (MeedyaConverterApp.swift:558-590).
Touches: `Components/MenuBarController.swift` — `statusItem.button?.window?.registerForDraggedTypes([.fileURL])` with a small `NSDraggingDestination` proxy view over the button; route dropped URLs to the same enqueue path as Quick Encode.
Effort: S-M. Risk: NSStatusBarButton drop handling is fiddly across macOS versions; verify on 15.x, and remove the header claim if it slips (#9).

**13. Notarize the CLI tarball** — supports #428
Rationale: `rc4-known-limitations.md` admits the CLI is signed but not notarized, so testers must `xattr -d com.apple.quarantine`. `scripts/notarize.sh` exists and `notarytool` accepts a zip of the binary; `release.yml:524` "Package CLI binary" is the insertion point.
Touches: `release.yml` (and the reusable workflow from #1): zip `meedya-convert`, `notarize.sh` it, then tar; drop the limitation line.
Effort: S. Verification: `spctl -a -t exec` on the extracted binary from a browser download.

**14. Move-to-/Applications prompt on first launch** — maps #464
Rationale: DMG testers routinely run from the mounted image; App Translocation then randomises `Bundle.main.bundleURL`, and the Sparkle path in v0.2.0 needs a writable install location. Zero relocation code exists today (grep confirmed).
Touches: `MeedyaConverterApp.swift` app-delegate `applicationDidFinishLaunching` — if `Bundle.main.bundleURL` is under `/Volumes/` or a translocation path, offer to copy to `/Applications` and relaunch. Skip under `#if APP_STORE`.
Effort: S-M. Risk: never loop on failure; one prompt per launch max, "Don't ask again" persisted.

**15. Wire-or-delete sweep of the small dead engine paths that shadow live features** — maps #477, #286, #324, #335
Rationale: three dead branches sit next to live code and invite regressions: `ParallelEncoder.partitionJobs` (ParallelEncoder.swift:204, zero callers), `DeinterlacePresets.detectInterlaced` (DeinterlaceConfig.swift:232, zero callers — could feed an "Auto" option in the OutputSettingsView.swift:412 picker), and `MultiOutputEncoder.buildTeeArguments` (preview-only). Decide per item; the disc/cloud/Windows/Linux clusters stay in #477.
Touches: the three files above + their tests; `detectInterlaced` is the one worth wiring (S) since it makes the existing deinterlace picker self-configuring.
Effort: S each. Verification: compile gate + existing `DeinterlaceWiringTests`.

---

**If you only do three things:**
1. #1 — a notarized, ffmpeg-bundled DMG from the `alpha` branch; without it there is no alpha to test.
2. #2 — `DirectBuildGateProvider` so testers can actually exercise parallel encoding (and the rest of the plus/pro surface) in a build where licensing is hidden.
3. #3 + #4 together — diagnostics bundle with git SHA, and a pre-release update channel, so every report is attributable and every tester is on the latest alpha.