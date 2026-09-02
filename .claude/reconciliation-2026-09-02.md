<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — Open-Issue Reconciliation (wip/alpha-consolidation, 2026-09-02)

Scope: 87 open issues. The evidence set covered 86; **#283 was missing** and has been verified here directly. Spot-checks were re-run by grep on the current tree for every claim flagged below as NEEDS_RECHECK.

Override summary vs. agent recommendations: **#495 CLOSE → COMMENT_KEEP_OPEN** (hardware acceptance criterion unverified), **#477 NO_CHANGE → COMMENT_KEEP_OPEN** (its "all 28 dead" claim is now false for VideoStabilizer), **#283 added as NO_CHANGE**. Nothing is recommended for CLOSE.

---

## 1. ACTIONS table

| # | Verified state | Action | Justification |
|---|---|---|---|
| 275 | PARTIAL | COMMENT_KEEP_OPEN | Mirror mode wired (GUI single-file + CLI batch); outputMode not persisted, no GUI batch-enqueue, no empty-dir option. |
| 278 | PARTIAL | COMMENT_KEEP_OPEN | Pipelines save/run for real; no tag-metadata step, no branching, linear list not graph editor. |
| 280 | PARTIAL | COMMENT_KEEP_OPEN | Floating NSPanel fed by live queue; auto-show/position-persist/pause/opacity absent; stale header comment. |
| 281 | PARTIAL | COMMENT_KEEP_OPEN | NSStatusItem wired to live queue; headline drag-and-drop absent (no NSDraggingDestination anywhere) despite header comment. |
| 286 | PARTIAL | COMMENT_KEEP_OPEN | TaskGroup concurrency real and entitlement-gated; partitionJobs dead, thermal display-only. |
| 288 | PARTIAL | COMMENT_KEEP_OPEN | Detection + chapter embed wired end-to-end; no drag timeline, no batch. |
| 298 | PARTIAL (mislabelled) | COMMENT_KEEP_OPEN | Watermark shipped into video-profile path; ImageConversionView (the issue's subject) has zero watermark refs. |
| 302 | PARTIAL | COMMENT_KEEP_OPEN | sdef → NSScriptCommand → live engine confirmed; only 3 verbs, no properties/events; stale "not live yet" comment. |
| 320 | PARTIAL | COMMENT_KEEP_OPEN | Single-file tag write + artwork real; batch and user templates absent (doc comment claims batch). |
| 322 | PARTIAL | COMMENT_KEEP_OPEN | Demuxer/filter concat execute; crossfade UI disabled and always nil. |
| 323 | PARTIAL | COMMENT_KEEP_OPEN | Two-pass vidstab executes; no before/after preview. |
| 324 | PARTIAL | COMMENT_KEEP_OPEN | yadif/bwdif wired + tested; detectInterlaced has no callers, FieldOrder has no UI. |
| 330 | PARTIAL | COMMENT_KEEP_OPEN | Real UndoManager + Cmd+Z; exactly one registerUndo site (profile picker). |
| 331 | PARTIAL | COMMENT_KEEP_OPEN | Recorder/conflicts/reset real and consumed; no Cmd+1-9, no pause/stop actions. |
| 335 | PARTIAL | COMMENT_KEEP_OPEN | Per-output jobs enqueue for real; tee muxer preview-only, never executed. |
| 343 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | SlateGeneratorView unreachable (no nav case, zero refs) and never runs ffmpeg. |
| 346 | DEFERRED_CORRECT | NO_CHANGE | Issue body already states protocol-only; code matches (no transport, zero client instantiations). |
| 353 | PARTIAL | COMMENT_KEEP_OPEN | Bundle loading real; hooks never called from encode path; PluginManagerView unreachable; no sandbox. |
| 357 | PARTIAL | COMMENT_KEEP_OPEN | registerServices() never called; no .action bundle; working Shortcuts work is #282's. |
| 476 | PARTIAL | COMMENT_KEEP_OPEN | Named 7 types still dead (see recheck on AudioCDReader); #495 added a second reachable disc path bypassing them. |
| 477 | NOT_STARTED (list now inaccurate) | COMMENT_KEEP_OPEN | 27 of 28 still dead; **VideoStabilizer is wired via StabilizationView (#323)** — list must be corrected. |
| 492 | PARTIAL | COMMENT_KEEP_OPEN | P1 landed/tested; NRG, DVD/BD, mixed-mode, restore all unbuilt. |
| 493 | PARTIAL | COMMENT_KEEP_OPEN | Part A done+tested, Part B evidenced "no change needed", Part C unverifiable from this repo. |
| 494 | PARTIAL | COMMENT_KEEP_OPEN | DR-0001 accepted + App Store GPL tripwire landed (f453856); binaries/licenses/tarballs not staged. |
| 495 | DONE except hardware AC | COMMENT_KEEP_OPEN | All code/tests/CI proven; manual physical-drive matrix is an explicit acceptance item and is unverified. Owner may close if that pass has run. |
| 257 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | ToolUpdateChecker fully built/tested, zero callers; duplicates a #477 line item. |
| 479 | NOT_STARTED | NO_CHANGE | No fixtures, no ffmpeg-gated test convention; issue is a follow-up and says so. |
| 468 | PARTIAL | COMMENT_KEEP_OPEN | Checkpoints written every ~5% + sidebar live; resume re-queues from 0% (code comment admits). |
| 205 | DEAD_CODE_ONLY | NO_CHANGE | Unchanged since last comment; builders only, no URLSession, no live caller (see recheck). |
| 373 | PARTIAL | NO_CHANGE | Gated dependency + smoke test exist; blocked on absent MeedyaSuite-core tag; unchanged since last comment. |
| 374 | PARTIAL | COMMENT_KEEP_OPEN | Prep (removal notice + checklist doc) landed; deletion correctly blocked; no comment on issue yet. |
| 383 | NOT_STARTED | COMMENT_KEEP_OPEN | Zero LyricsFile code; upstream Rust prereq done (core#34) but no Swift tag — blocker narrower than issue text. |
| 416 | DEFERRED_CORRECT | NO_CHANGE | GitHubReleaseChecker's own comment and #428 both scope update.mwbm.io as v0.2.0. |
| 464 | NOT_STARTED | COMMENT_KEEP_OPEN | Zero relocation code; all four status items outstanding. |
| 428 | PARTIAL | NO_CHANGE | Umbrella's own checkboxes match repo (no rc.4 tag, VERSION=0.1.0, [Unreleased] open). |
| 465 | PARTIAL | NO_CHANGE | No commits since last comment; HMAC + re-poll gaps still stand as recorded. |
| 178 | PARTIAL | COMMENT_KEEP_OPEN | Metadata/docs present; FFmpegKitBackend all-notImplemented; env-var vs -D flag mismatch means ffmpeg-kit never links in CI. |
| 386 | PARTIAL | COMMENT_KEEP_OPEN | .zip+altool path landed; workflow disabled_manually, zero runs since fix. |
| 387 | PARTIAL | COMMENT_KEEP_OPEN | .pkg path removed; shared APPLE_SIGNING_IDENTITY secret is asserted as "Developer ID Application" by release.yml — wrong family for App Store. Needs human. |
| 388 | PARTIAL | COMMENT_KEEP_OPEN | PlistBuddy + validation step landed; AC's .pkg check moot; no post-fix upload. |
| 389 | PARTIAL | COMMENT_KEEP_OPEN | Single Info.plist source of truth (15.0 = .v15) with CI guard; no post-fix upload. |
| 391 | PARTIAL | COMMENT_KEEP_OPEN | Embed step real (secret renamed APP_STORE_PROVISIONING_PROFILE); secret population + device install unverifiable. |
| 392 | PARTIAL | NO_CHANGE | Tracking issue; none of its 3 pre-conditions met, mitigations still in place — accurate as-is. |
| 147 | NOT_STARTED | NO_CHANGE | macOS-only Package.swift; no Windows toolchain/CI. |
| 148 | NOT_STARTED | NO_CHANGE | No WinUI code beyond a display-name string. |
| 149 | NOT_STARTED | NO_CHANGE | ffmpeg.exe path string only; no binary, no build target. |
| 150 | PARTIAL | COMMENT_KEEP_OPEN | Encoder tables used on macOS; WindowsPlatform NVENC/QSV/AMF builders test-only; no Windows build. |
| 151 | PARTIAL | COMMENT_KEEP_OPEN | generateWiXComponent test-only; no MSI/MSIX/signing/CI. |
| 152 | NOT_STARTED | NO_CHANGE | No windows-latest runner anywhere. |
| 153 | PARTIAL | COMMENT_KEEP_OPEN | IMAPI script builder test-only; no detection/drive mapping; blocked on #147. |
| 154 | NOT_STARTED | NO_CHANGE | No Linux swift build in CI; ubuntu jobs are lint/metadata only. |
| 155 | NOT_STARTED | NO_CHANGE | Only "GTK4" label + apt package-name strings. |
| 156 | PARTIAL | COMMENT_KEEP_OPEN | Package-format helpers test-only; no manifests; blocked on #154. |
| 157 | PARTIAL | COMMENT_KEEP_OPEN | VAAPI tables live; LinuxPlatform VAAPI/V4L2 builders test-only; blocked on #154. |
| 158 | NOT_STARTED | NO_CHANGE | Generic V4L2 string builder only; nothing Pi-specific. |
| 159 | NOT_STARTED | NO_CHANGE | No .deb/.rpm/.desktop/.spec files; no CI. |
| 160 | NOT_STARTED | NO_CHANGE | No udev/udisks/cdrecord code; no Linux target. |
| 163 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | CloudFrontDistribution builder only; no executor/UI/enum case. |
| 164 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | AzureBlobUploader builder only; executor switch lacks .azureBlob. |
| 165 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | CloudflareStreamUploader builder only; no dispatch/UI. |
| 169 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | SharePointUploader builder only; no dispatch/UI. |
| 170 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | ICloudDriveUploader helper only; no dispatch/UI. |
| 171 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | MegaUploader builder only; not in either provider enum. |
| 172 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | MuxUploader builder only; no dispatch/UI. |
| 173 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | AkamaiNetStorageUploader builder only; no dispatch/UI/enum. |
| 294 | PARTIAL | COMMENT_KEEP_OPEN | Builders + view exist; remote-gated off because OAuth incomplete (gate's own comment); 0/9 AC met. |
| 59 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | HLSEncryption test-only; in-app docs already disclose it as unavailable. |
| 63 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | ThumbnailSpriteGenerator test-only; no EXT-X-IMAGE-STREAM-INF, no pipeline call. |
| 230 | NOT_STARTED | NO_CHANGE | No ImageCommand; "image" absent from subcommand list. |
| 235 | NOT_STARTED | NO_CHANGE | Wishlist; no code. |
| 236 | NOT_STARTED | NO_CHANGE | Wishlist; no code. |
| 237 | NOT_STARTED | NO_CHANGE | Wishlist; no code. |
| 303 | DEAD_CODE_ONLY (not NOT_STARTED) | NO_CHANGE | LocalizationManager + en.lproj strings exist with zero callers; already reopened with this exact finding 2026-09-01. |
| 359 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | NSStatusItem substitute, not WidgetKit; never instantiated; no tests. Scope decision needed. |
| 360 | NOT_STARTED | NO_CHANGE | No ActivityKit/WidgetKit target. |
| 362 | DEAD_CODE_ONLY | COMMENT_KEEP_OPEN | HandoffManager never instantiated; no becomeCurrent/onContinueUserActivity. |
| 364 | NOT_STARTED | NO_CHANGE | Only StoreKit price display; no cost tracking. |
| 419 | NOT_STARTED | NO_CHANGE | Zero OFX matches. |
| 420 | NOT_STARTED | NO_CHANGE | Zero OCIO matches. |
| 421 | NOT_STARTED | NO_CHANGE | AudioFingerprinter is AcoustID lookup, unrelated; no offset code. |
| 422 | NOT_STARTED | NO_CHANGE | Depends on #421. |
| 423 | NOT_STARTED | NO_CHANGE | Depends on #421/#422. |
| 424 | PARTIAL (different system) | COMMENT_KEEP_OPEN | Proposed API/flags/Expert Mode absent; pre-existing 3-tier EntitlementGating (#307) not referenced by issue. |
| 425 | NOT_STARTED | NO_CHANGE | Depends on #421/#422. |
| 426 | NOT_STARTED | NO_CHANGE | Zero SubtitleSync matches. |
| 427 | NOT_STARTED | NO_CHANGE | Issue itself says not actionable until #422 + #426. |
| **283** | DEAD_CODE_ONLY | NO_CHANGE | (Missing from evidence; verified here.) FinderQuickAction.registerAsService() still has zero callers, no NSServices in Info.plist, no extension target; identical finding already posted 2026-09-01. |

---

## 2. Final comment texts (COMMENT_KEEP_OPEN only; no CLOSE actions)

**#275**
Verified: mirror mode is wired — GUI single-file enqueue (AppViewModel.swift:949-1000 → OutputPathResolver) and CLI `batch --dir --recursive --output-mode mirror` (BatchCommand.swift:106-134); intermediate dirs created, collisions auto-numbered.
Gaps: `outputMode` (AppViewModel.swift:369) has no UserDefaults/@AppStorage, so it resets to Flatten each launch; no empty-directory option; the GUI has no batch-enqueue action (only `selectedFile` is ever enqueued) — folder-tree batch is CLI-only; collision handling is auto-rename only, no prompt.
Keeping open for persistence, GUI batch-enqueue, and the empty-dir option.

**#278**
Verified: PipelineEditorView (Output Settings → Pipeline Editor…) saves via `AppViewModel.savePipeline` (UserDefaults) and runs via `AppViewModel.runPipeline` → `EncodingPipelineExecutor` with real FFmpeg steps (encode/thumbnail/GIF/extractAudio/probe).
Gaps: no `tag metadata` step in `PipelineStepType`; no conditional/alternate-step branching (failure halts); editor is a reorderable list, not a node/connector graph.
Keeping open for the metadata step, branching, and a decision on whether a graph editor is still required.

**#280**
Verified: MiniPlayerController is a real floating NSPanel (MiniPlayerWindow.swift:161-203) fed live from the queue (AppViewModel.swift:2141-2145), toggled from toolbar buttons; click-to-expand works.
Gaps: no auto-show on minimise/encode-start (the header comment at line 17 claims this; no window-miniaturize observer exists); always-on-top is hardcoded, no toggle; position not persisted; no pause/cancel buttons; no translucent option.
Keeping open; please also fix the stale header comment.

**#281**
Verified: MenuBarController creates a real NSStatusItem, persists the mode, and Quick Encode / Open Main Window are wired to the live AppViewModel via `wireMenuBarActions()` (MeedyaConverterApp.swift:558-590).
Not implemented: drag-and-drop onto the icon — no `registerForDraggedTypes`/`NSDraggingDestination` anywhere in Sources/, despite the file's header comment claiming it; no idle/encoding/error indicator or animation (static `film.stack`); no badge; no recent completions; no global shortcut.
Keeping open for drag-and-drop (the headline item) and the status/badge/recents items; fix the stale header comment.

**#286**
Verified: `AppViewModel.startQueue()` (AppViewModel.swift:1445-1524) runs jobs concurrently in a TaskGroup bounded by `ParallelEncoder.resolveConcurrency` (entitlement-gated, clamps to 1); slider in ParallelEncodingView is live; priority affects claim order.
Gaps: `ParallelEncoder.partitionJobs` (the GPU/CPU balancer) has zero callers — dead code; thermal state only drives a warning label, `resolveConcurrency` never reads `ProcessInfo.thermalState`; priority does not change per-job resources.
Keeping open to wire-or-delete partitionJobs, make thermal pressure reduce width, and settle the priority-resources criterion.

**#288**
Verified end-to-end: SceneDetectorView (Analyze tab) runs real `select=gt(scene,X)` detection, writes chapter files, stages them on `AppViewModel.pendingChaptersFile`, consumed by `enqueueSelectedFile` → `EncodingJobConfig.externalChaptersFile` → FFmpegArgumentBuilder.swift:416-435 (`-map_chapters`).
Gaps: scenes are a thumbnail list, not a drag-adjustable timeline; single-file only, no batch detection.
Keeping open for those two items.

**#298**
Verified: a real watermark engine exists (WatermarkOverlay.swift) and is wired into the *video* profile path — WatermarkView → `EncodingProfile.watermark` → FFmpegArgumentBuilder.swift:531-532.
However this issue is about batch *image* watermarking: `ImageConversionView.swift` has zero references to watermarking and drives its own separate Process pipeline, so nothing here applies to the issue's subject. Also missing on any path: tiled position, rotation, custom X/Y offset, sample-image preview.
Keeping open — the shipped work solves a different problem than the one filed.

**#302**
Verified live: MeedyaConverter.sdef declares `<cocoa class>` mappings to NSScriptCommand subclasses in ScriptingCommands.swift, which dispatch to `ScriptingBridge.shared`, wired to the real engine/queue/profile store in AppViewModel.init (549-556); Info.plist has NSAppleScriptEnabled + OSAScriptingDefinition; sdef bundled in Package.swift.
Gaps: only `encode`/`probe`/`list profiles`; no batch verb, no scriptable properties (queue count/current job/progress), no encode-complete event.
Note: ScriptingBridge.swift:302-312 still says "AppleScript dispatch is not live yet" — stale, should be removed.

**#320**
Verified: MetadataTagEditorView writes tags and embeds artwork via a real FFmpeg process (`writeTags()`, MetadataTagEditorView.swift:613+; MetadataTagEditor.buildWriteArguments/buildArtworkEmbedArguments).
Gaps: batch editing is not implemented — `writeTags()` operates on the single `viewModel.selectedFile` to one NSSavePanel output; the view's doc comment (line 17) claims batch but no multi-file path exists. Templates are hardcoded presets, not user-saveable JSON/plist.
Keeping open for multi-file batch writes and saveable templates; fix the doc comment.

**#322**
Verified: drag-to-reorder (`.onMove`, ConcatenationView.swift:267), demuxer concat and filter concat both execute through FFmpegProcessController (runDemuxerConcat 630-677, runFilterConcat 687-721).
Remaining: crossfade — toggle/slider are `.disabled(true)` (lines 322-345) and `runFilterConcat` always passes `crossfade: nil` (line 695); needs per-clip duration probing for xfade/acrossfade offsets.

**#323**
Verified: two-pass vidstab executes — `runStabilization` (StabilizationView.swift:278-334) builds both passes via VideoStabilizer and runs each through FFmpegProcessController; shakiness/accuracy/zoom controls are bound.
Remaining: no before/after (split-view) preview anywhere in StabilizationView.swift.

**#324**
Verified: Off/Fast(yadif)/Quality(bwdif) picker (OutputSettingsView.swift:412-417) → `EncodingProfile.deinterlace` → first `-vf` stage (FFmpegArgumentBuilder.swift:506-507), covered by DeinterlaceWiringTests.
Remaining: `DeinterlacePresets.detectInterlaced(probeOutput:)` (DeinterlaceConfig.swift:232) has zero callers; `FieldOrder` (tff/bff) has no UI — every preset hardcodes `parity: .auto`.

**#330**
Verified: SettingsUndoManager wraps a real UndoManager and Cmd+Z/Cmd+Shift+Z are functional (MeedyaConverterApp.swift:198-214).
Remaining: `registerUndo` is called from exactly one site — the profile picker (OutputSettingsView.swift:249-255). No individual output field or stream-selection change registers undo; no toast/highlight feedback beyond the menu title.

**#331**
Verified: KeyboardShortcutsView (SettingsView.swift:55) records shortcuts, detects conflicts, resets to defaults; bindings are consumed by real menu commands (MeedyaConverterApp.swift:277-313) and the Add-to-Queue button (ContentView.swift:235).
Remaining: no Cmd+1-9 quick-profile shortcuts; `encode.start` is the only encoding action — no pause/stop actions exist to customise.

**#335**
Verified: `AppViewModel.enqueueMultiOutput` (AppViewModel.swift:1113-1131), called from MultiOutputView.swift:158, enqueues one real EncodingJobConfig per enabled output, so each gets independent progress/status.
Remaining: tee-muxer shared decode — `MultiOutputEncoder.buildTeeArguments`/`buildSequentialArguments` only render the argument preview (MultiOutputView.swift:224-227) and are never executed; AppViewModel.swift:1086-1106 documents this explicitly.

**#343**
Verified: SlateGenerator.swift has real builders (bars+tone, slate, countdown, full leader) and SlateGeneratorView calls them — but the view is unreachable: no NavigationItem case, no SidebarView/ContentView entry, no sheet presentation; repo-wide grep finds no reference outside its own file.
Even opened, `generateLeader()`/`prependLeader()` (SlateGeneratorView.swift:399-449) only build an argument array and set a "Run with ffmpeg" status — no process is ever launched.
Keeping open until it is wired into navigation and actually executes.

**#353**
Verified: MeedyaPlugin protocol + PluginManager Bundle-based loading from `~/Library/Application Support/MeedyaConverter/Plugins/` (PluginManager.swift:80-140) are real.
Remaining: `runPreProcess`/`runPostProcess`/`collectAdditionalArguments` (188-246) have zero callers in the encode path — a loaded plugin cannot affect an encode; no sandboxing; no Xcode template (only ExamplePlugin.swift); PluginManagerView is not referenced from SidebarView/ContentView/SettingsView — unreachable.

**#357**
Verified: `EncodeMediaActionHandler.handle` (EncodeMediaAction.swift:116) has real logic, but its only caller `ServiceProvider.handleServiceRequest` requires `AutomatorIntegration.registerServices()` (AutomatorIntegration.swift:90), which is never called anywhere — dead at runtime. No `.action` bundle exists (file header defers it). No Probe Media action.
Note: the working Shortcuts/AppIntents support (ConvertMediaIntent, ProbeMediaIntent) is tagged #282 in its headers, not this issue.
Also note #283's `FinderQuickAction.registerAsService()` would set the same `NSApp.servicesProvider` — wiring both needs a single provider.

**#476**
Re-verified: DVDReader, BlurayReader, DiscImager, DiscAuthor, DCPGenerator, AccurateRipVerifier have zero external callers; AudioCDReader's only caller is AccurateRipVerifier.swift:541, itself dead — so the cluster remains unreachable. AccurateRipVerifier appears in SettingsView.swift only as strings/comments.
Changed since filing: #495 added a *separate* reachable path — `meedya-convert disc image|toc|drives` (DiscCommand.swift, registered MeedyaConvert.swift:29) → DiscImagingController/RawCDReadPlanner/BundledToolLocator → cdrdao — bypassing every type named here. Burning is no longer the only reachable disc feature.
Recommend narrowing scope to the still-dead clusters, or wire-or-delete per #477.

**#477**
Re-checked all 28 listed types on wip/alpha-consolidation: 27 still have zero callers outside their own file/tests.
Correction to the list: **VideoStabilizer is no longer dead** — StabilizationView.swift:54-56 and :300/:307 call `VideoStabilizer.light/medium/heavy` and `buildAnalysisArguments`/`buildStabilizeArguments`, and the view executes both passes (see #323). Please strike it from the list.
Overlap note: ToolUpdateChecker here is also tracked separately as #257 — pick one home.

**#492**
P1 (#495) has landed and is reachable + tested: `meedya-convert disc image` → DiscImagingController → cdrdao, verified BIN+CUE with ISRC/CD-Text/pregaps/FLAGS PRE, round-tripped by CueSheetParser (ConverterEngineTests+DiscImaging.swift). `ImagingConfig.imageFormat`/`DiscImageFormat` are now consumed (DiscCommand.swift:235-248).
Unbuilt: NRG writer (only an enum label), DVD/HD DVD/Blu-ray imaging (readers dead per #476), mixed-mode/eCD/multisession (DiscCommand.swift:312-320 refuses any data session), restore/mount/burn-back.

**#493**
Part A done and tested: `MusicBrainzClient.luceneClause`/`escapeLucenePhraseValue` (MetadataLookup.swift:381-409) with test_musicBrainzClient_recordingSearch_escapesReservedCharacters; base URL centralised — AudioCDReader.swift:372 now reads `MetadataSource.musicBrainz.baseURL`.
Part B resolved as "verified unaffected": announcement + all 12 SEARCH tickets fetched first-hand; conclusion recorded at MetadataLookup.swift:300-330 — no migration code needed for this client's query shape.
Part C (MeedyaSuite-core provider) cannot be verified from this repo — please confirm there or record N/A. Suggest ticking the Part A boxes.

**#494**
Update since the 2026-09-01 comment: the App Store GPL exclusion guard has landed in f453856 — `BundledTool.isGPLFamily`/`ToolBundleManifest.isAppStoreSafe` (ToolBundleManifest.swift:52-55, ~218), regression test `test_toolBundleManifest_defaultManifestIsAppStoreSafe`, and `scripts/verify-no-gpl-in-appstore.sh` wired at testflight.yml:331. No GPL tool is in `defaultManifest`, so the tripwire is live.
Still open per DR-0001's own tracking: license-text staging, source-tarball archival in the MeedyaDL-Tools mirror, and actually bundling pinned cdrdao/ddrescue/wodim into the Direct .dmg.

**#495**
Verified: every listed component exists and is wired — `meedya-convert disc image` (DiscCommand.swift, registered MeedyaConvert.swift:29) → DiscImagingController (real Process, AsyncStream progress) → cdrdao via BundledToolLocator, with byte-count + SHA-256 verification (DiscCommand.swift:351-360); CueSheetWriter emits CATALOG/SONGWRITER/FLAGS PRE/ISRC/PREGAP and CueSheetParser round-trips (test_cueSheetRoundTrip_golden); `ImagingConfig.imageFormat` is now consumed. Tests in ConverterEngineTests+DiscImaging.swift and RawCDImagingExecutorTests.swift; CI green.
The one acceptance item not provable from code is the manual hardware matrix (physical Audio CD on macOS-Direct + Linux). If that pass has been run, this can close; otherwise it stays open for that step only.

**#257**
The issue description matches the code: ToolUpdateChecker.swift (341 lines) is fully implemented and unit-tested (ConverterEngineTests+Pipelines.swift:452-579), but `isCheckDue`/`buildResult`/etc. have zero callers in the app or CLI — nothing schedules a check or shows a result.
This is also line-itemed in #477. Recommend either wiring a launch-time check + Settings surface here, or resolving it under #477's sweep and closing this as a duplicate.

**#468**
Two of three criteria now met: checkpoints written every ~5% during encode plus on failure/cancel (AppViewModel.swift:1679-1697, 1982, 2233); `NavigationItem.resumableJobs` is live (SidebarView.swift:40, ContentView.swift:106).
Remaining: `ResumableJobsView.resumeCheckpoint` (ResumableJobsView.swift:158-195) re-queues a fresh job from 0% — the code comment at 160-164 states true mid-file resume is deferred. Today this is re-queue, not resume. Keep open until seeking to `checkpoint.lastGoodTimestamp` is implemented.

**#374**
Verified: removal notice on `TheTVDBClient` (MetadataProviders.swift:12, 23-28) and checklist at docs/migration/suite-core-cleanup.md are landed; the type is intentionally untouched.
Blocker still unmet: `gh api repos/MWBMPartners/MeedyaSuite-core/tags` and `/releases` both empty, so `SUITE_CORE=1` cannot resolve as a normal dependency.
Remaining: publish tag → flip SUITE_CORE default-on → execute the checklist (remove TheTVDBClient, MetadataSource enum, per-provider URL helpers; migrate the 5 URL-builder tests).

**#383**
No LyricsFile/`.lyrics` code exists in this repo (grep across Sources/ and Tests/: zero).
The named prerequisite has landed upstream — MeedyaSuite-core#34 is closed (with #60 closed, #61/#85 open) — but MeedyaSuite-core has published no Swift Package tag, so there is still no consumable API here.
Correctly open; the blocker is now "Swift tag + SuiteCore wiring", narrower than the issue text implies.

**#464**
Verified: no first-launch relocation code anywhere — grep for firstLaunch/moveToApplications/relocateSelf and variants returns zero; the only nearby hit (PluginProtocol.swift:86) is an unrelated doc comment.
All four Status checklist items remain outstanding.

**#178**
Verified: metadata/en-US/*, metadata/{copyright,primary_category,secondary_category,review_information.yml}, screenshots/README.md and docs/distribution/app-store-submission.md all exist.
The ⚠️ row is still false: FFmpegKitBackend.swift is gated on `#if APP_STORE`, every method throws `notImplemented`, `import ffmpegkit_macos` is commented out (line 79); `FFmpegBackendFactory.makeDefault()` returns this stub, so an App Store build cannot convert anything.
Separately, Package.swift adds ffmpeg-kit only when the `APP_STORE` *env var* is set, but testflight.yml passes only `-Xswiftc -DAPP_STORE` — the package is never resolved in CI even once the stub is filled.

**#386**
Fix landed (a3d3671): testflight.yml codesigns the .app, `ditto`-zips it and uploads via `xcrun altool --upload-app --type macos`, with a guard failing on any `.pkg` artefact.
Unverified against Apple: the workflow is `disabled_manually` and `gh run list` shows only the original 2026-05-18 build-244 run. The acceptance criterion ("confirm ITMS-90270 no longer fires") needs one smoke-test run.

**#387**
The .pkg/productsign path was removed (a3d3671) rather than given an installer cert — no APPLE_INSTALLER_* secrets exist anywhere — so the specific installer-cert requirement no longer applies.
Open risk: testflight.yml signs with `secrets.APPLE_SIGNING_IDENTITY`/`APPLE_CERTIFICATE`, the same names release.yml uses, and release.yml:146-152 asserts that identity contains "Developer ID Application" — the wrong family for App Store/TestFlight ("Apple Distribution"/"3rd Party Mac Developer Application"). If the org secret is the Direct cert, this rejection reappears at the .app layer.
Repo-level secrets are empty and org secrets are not visible here. Needs an org secret admin to confirm, plus a cert-family assert in testflight.yml, before a smoke-test.

**#388**
Fixed at code level (4fbef68): PlistBuddy sets `CFBundleIdentifier` = `Ltd.MWBMpartners.MeedyaConverter.Lite` and `CFBundleShortVersionString` from VERSION; a "Validate Info.plist metadata" step fails before signing on a missing `.Lite` suffix or non-`X.Y.Z` version.
The AC's ".pkg product-metadata.plist" check is now moot (path removed per #386); the equivalent check lives on the .app's Info.plist.
Unverified by a real upload — close after the #386 smoke-test passes.

**#389**
Verified: Info.plist `LSMinimumSystemVersion` = 15.0 matches Package.swift `.macOS(.v15)`; the Validate step hard-fails if it drifts (`EXPECTED_MIN_OS="15.0"`).
With the .pkg/Distribution.xml path gone (#386) there is no second minimum-OS declaration to diverge — root cause removed structurally.
Unverified by a real upload — close after the #386 smoke-test passes.

**#391**
Implemented (0590cc4): "Embed App Store provisioning profile" step decodes `secrets.APP_STORE_PROVISIONING_PROFILE` (issue specified `APPLE_PROVISIONING_PROFILE`; harmless rename) to Contents/embedded.provisionprofile, validates via `security cms -D`, and asserts the App ID ends in `.Lite`.
Unverifiable from code: whether the secret is populated (repo-level secrets: 0; org-level not visible) and whether a TestFlight install to a device has succeeded. Keep open for those.

**#150**
Verified: nvenc/qsv/amf encoder tables (HardwareEncoderDetector.swift:40-102) are used by the real macOS encode path. Nothing Windows-specific is reachable: Package.swift is macOS-only, no windows-latest CI, and WindowsPlatform.swift's NVENC/QSV/AMF builders are called only from ConverterEngineTests+Platform.swift.
Remaining: Windows build target (#147), wiring the builders into an encode controller, hardware verification.

**#151**
Verified: `WindowsInstallerType` and `generateWiXComponent` (WindowsPlatform.swift:347-355) exist; only caller is ConverterEngineTests+Platform.swift:191-196. No MSI/MSIX artefact, no signtool/Authenticode, no CI job. Effectively unimplemented; blocked on #147/#148/#149.

**#153**
Verified: only `buildIMAPIBurnScript` (WindowsPlatform.swift:276-298) exists, called solely from ConverterEngineTests+Platform.swift:179-186. No drive detection, drive-letter mapping, or AutoPlay handling. Blocked on #147.

**#156**
Verified: `LinuxPackageFormat`, AppRun generator and `flatpakPermissions` (LinuxPlatform.swift:132-167, 407-467) are called only from ConverterEngineTests+Platform.swift. No AppImage/Flatpak/Snap manifests in the repo; no Linux build target. Blocked on #154.

**#157**
Verified: VAAPI entries in HardwareEncoderDetector.swift are used by the real pipeline; but `LinuxPlatform.buildVAAPIEncodeArguments`/`buildVAAPIDecodeArguments`/`buildV4L2EncodeArguments` (LinuxPlatform.swift:187-264) are called only from ConverterEngineTests+Platform.swift:265-292 — not wired into EncodingEngine or any controller. No Linux build target. Blocked on #154.

**#163**
Verified: `CloudFrontDistribution` (ExtendedCloudProviders.swift:15) is a unit-tested URL/XML builder with zero callers outside its file — no CloudUploadExecutor case, no UI (CloudStorageView offers only Dropbox/OneDrive/Google Drive/S3), no `CloudProvider` case. Nothing performs a CloudFront request.
Remaining: executor wiring, UI entry point, tests for the wired path.

**#164**
Verified: `AzureBlobUploader` (CloudProviders.swift:193) has zero callers outside its file; `CloudUploadExecutor.uploadToCloudStorage` switches only on .dropbox/.googleDrive/.onedrive/.s3; CloudStorageView has no Azure option. Builder-only.
Remaining: `.azureBlob` executor case with real block-upload + commit, Azure credentials UI, wired-path tests.

**#165**
Verified: `CloudflareStreamUploader` (CloudProviders.swift:326) has zero callers outside its file; no executor case, no UI option. Builder-only.
Remaining: TUS upload execution, UI destination, wired-path tests.

**#169**
Verified: `SharePointUploader` (ExtendedCloudProviders.swift:73) has zero callers outside its file; no executor case, no UI. Builder-only.
Remaining: Graph upload execution, UI destination, wired-path tests.

**#170**
Verified: `ICloudDriveUploader` (ExtendedCloudProviders.swift:147) has zero callers outside its file; no executor/UI wiring despite `CloudProvider.iCloudDrive` existing (never dispatched). Helper-only.
Remaining: reachable copy/availability flow, UI destination, tests.

**#171**
Verified: `MegaUploader` (ExtendedCloudProviders.swift:191) has zero callers outside its file; no executor, no UI, not in either provider enum. Builder-only.
Remaining: login/upload/complete execution, UI destination, tests.

**#172**
Verified: `MuxUploader` (ExtendedCloudProviders.swift:290) has zero callers outside its file; `CloudProvider.mux` is never dispatched; no UI. Builder-only.
Remaining: direct-upload + asset-creation execution, UI destination, tests.

**#173**
Verified: `AkamaiNetStorageUploader` (ExtendedCloudProviders.swift:394) has zero callers outside its file; no executor, no UI, no enum case. Builder-only.
Remaining: signed-upload execution, UI destination, tests.

**#294**
Verified: `VideoUploader` builds YouTube/Vimeo resumable-upload requests and OAuth URLs (VideoUploader.swift:205-369) with no network execution; `VideoUploadView` (358 lines) is wired at ContentView.swift:179 but hidden unless the remote `video-upload` flag is on — `AppViewModel` defaults `isVideoUploadEnabled` false, and RemoteFeatureGateProvider.swift:1-15 says it "shipped disabled … because its OAuth2 wiring is incomplete".
0 of 9 acceptance boxes are met. Remaining: OAuth token exchange + Keychain, actual upload execution, metadata form, progress/resume, multi-account, history, retry, thumbnails, then flip the flag.

**#59**
Verified: `HLSEncryption` (StreamingEnhancements.swift:18-106) generates keys, key-info files and `-hls_key_info_file`, tested at ConverterEngineTests+Manifest.swift:290 — but has zero callers in the app/CLI/manifest pipeline; faq.md:68 and adaptive-streaming.md:66-70 already tell users it cannot be enabled.
Remaining: pipeline wiring, KeyManager, key rotation, SAMPLE-AES, EXT-X-KEY emission, UI/CLI config.

**#63**
Verified: `ThumbnailSpriteGenerator` (StreamingEnhancements.swift:137-268) builds extraction/tiling args and one generic WebVTT; only referenced from ConverterEngineTests+Manifest.swift:308-340. No pipeline call, no EXT-X-IMAGE-STREAM-INF anywhere, no player-specific VTT variants, no progress reporting. Dead builder.

**#359**
Verified: `ControlCenterWidget` (ControlCenterModule.swift) is, per its own header (lines 14-17), an NSStatusItem+NSPopover substitute — it does not attempt the WidgetKit `ControlWidget` the AC specifies. It also has zero call sites (`ControlCenterWidget(`/`.install()` never appear) and no tests.
Decision needed: re-scope to accept the status-bar substitute (then wire it), or keep the WidgetKit criterion and mark blocked on platform API.

**#362**
Verified: HandoffManager.swift implements `createActivity`/`handleIncomingActivity`, but grep finds no `HandoffManager(` instantiation, no `.becomeCurrent()`, and no `.onContinueUserActivity`/`application(_:continue:)` anywhere including MeedyaConverterApp.swift. The activity is never advertised or received; no tests. Unreachable helper.

**#424**
Verified: none of this issue's proposed mechanism exists — `Entitlement.shared.canUse(...)`, `audioSyncDrift`, `MEEDYACONVERTER_DEV_BUILD`, developer-bypass keychain key: zero matches. "Expert Mode": zero matches.
A separate pre-existing three-tier system (free/plus/pro, EntitlementGating.swift, #307) is live via RemoteFeatureGateProvider but is not referenced by this issue and gates none of #419/#420/#421/#422 (which do not exist yet).
Decision needed: extend #307's system rather than build a parallel one? Not started against this issue's scope either way.

---

## 3. GROUPED SUMMARY

**Done-and-closeable:** none unconditionally. **#495** is the only candidate — all code, tests and CI criteria are proven; it closes as soon as the owner confirms the manual physical-drive pass (an explicit acceptance item; memory note says hardware verification was deferred).

**Partial epics — real work shipped, gaps specific and documented (COMMENT_KEEP_OPEN):**
#275, #278, #280, #281, #286, #288, #302, #320, #322, #323, #324, #330, #331, #335, #353, #468, #492, #493, #494, #374, #383, #178, #386–#391. The App Store cluster (#386/#388/#389/#391) is blocked on a single smoke-test run plus the #387 cert-family question; all four could carry a one-line "close after #392 smoke-test" comment rather than four essays.

**Dead-code-only — built, tested, never reachable (COMMENT_KEEP_OPEN unless already commented):**
#343, #257, #59, #63, #163, #164, #165, #169, #170, #171, #172, #173, #359, #362, and (already commented 2026-09-01, NO_CHANGE) #205, #283, #303. These are the same defect class #477 tracks; consider a single "wire-or-delete" sweep with #477 as the parent rather than 17 independent comments.

**Builder-only, blocked on a platform target that does not exist (COMMENT_KEEP_OPEN, low priority):**
#150, #151, #153 (Windows), #156, #157 (Linux). Siblings #147–#149, #152, #154, #155, #158–#160 are NOT_STARTED and need no comment.

**Correctly deferred / self-accurate (NO_CHANGE):**
#346, #416, #428, #392, #373, #465, #479, #230, #235–#237, #360, #364, #419–#423, #425–#427.

**Mislabelled / scope mismatch:**
- **#298** — title says batch *images*; shipped watermark is video-profile only. Either retitle the shipped work under a new issue or keep #298 for ImageConversionView.
- **#357 vs #282** — the working Shortcuts/AppIntents code is #282's; #357's Automator/Services code is dead. Don't let #282's success be read as #357 progress.
- **#477** — list is now stale (VideoStabilizer wired). Needs a correction comment, not silence.
- **#424** — describes a gating system that competes with the existing #307 system.

**Needs-human-decision:**
1. **#495** — has the physical-drive matrix been run? (Yes → close.)
2. **#387** — does the org `APPLE_SIGNING_IDENTITY` hold an Apple Distribution cert or the Developer ID cert release.yml demands? Blocks the whole TestFlight cluster.
3. **#359** — accept the NSStatusItem substitute or hold to WidgetKit?
4. **#424** — extend EntitlementGating (#307) or build the proposed single-tier system?
5. **#257 vs #477** — one home for ToolUpdateChecker.
6. **#476 vs #492/#495** — narrow #476 now that a reachable disc path exists.
7. **#357 vs #283** — both dead Services providers would set `NSApp.servicesProvider`; only one can win. Decide which is canonical before wiring either.
8. **Stale/false doc comments** (memory: recurring defect) — MiniPlayerWindow.swift:17 (auto-show), MenuBarController.swift:17 (drag-and-drop), MetadataTagEditorView.swift:17 (batch), ScriptingBridge.swift:302-312 (not live). One housekeeping PR would clear all four.

---

## 4. NEEDS_RECHECK — findings that over- or under-claim

| Issue | Claim in evidence | Problem | Effect on action |
|---|---|---|---|
| **#477** | "every one [of 28 types] still returns zero matches outside its own file and its tests" | **False for VideoStabilizer.** Confirmed by grep: StabilizationView.swift:54-56, 300, 307 call it, and #323's own evidence says the view executes both passes. The two findings contradict each other; #323 is right. | NO_CHANGE → COMMENT_KEEP_OPEN (correct the list). |
| **#495** | recommendedAction CLOSE, while evidence says the hardware matrix "is outside static/code verification" | Internal tension: CLOSE recommended against an admitted unverified acceptance criterion. | Downgraded to COMMENT_KEEP_OPEN; close on owner confirmation. |
| **#476** | "zero external callers … AudioCDReader" | Under-precise: AccurateRipVerifier.swift:541 calls `AudioCDReader.buildAccurateRipURL` (real code). AccurateRipVerifier is itself dead, so the cluster conclusion stands. | Comment tightened; action unchanged. |
| **#205** | "grep … returns only doc-comment references: AudioCDReader.swift:354,369" | Under-claims: AudioCDReader.swift:372 is a *code* use of `MetadataSource.musicBrainz.baseURL` (introduced by #493). AudioCDReader is unreachable, so DEAD_CODE_ONLY still holds transitively. #493 and #205 should agree on this. | NO_CHANGE stands. |
| **#303** | "No localization infrastructure exists" / NOT_STARTED | Over-claims absence: `Sources/MeedyaConverter/Localization/LocalizationManager.swift` and `en.lproj/Localizable.strings` (204 lines) exist; LocalizationManager has zero callers. Correct state is DEAD_CODE_ONLY, which is exactly what the 2026-09-01 reopen comment already says. | NO_CHANGE stands (already commented). |
| **#283** | absent from evidence set (86/87) | Verified here: FinderQuickAction.registerAsService() zero callers, no NSServices in Info.plist, no extension target — unchanged from the 2026-09-01 comment. | NO_CHANGE. |
| **#387** | "wrong certificate family … functionally the same class of rejection" | Plausible but *inferred* from release.yml's assert, not from the secret's contents (org secrets 403). Should be stated as a risk, not a finding, in the comment — done above. | Action unchanged; flagged for human. |
| **#357 / #283** | Each assessed in isolation | Both files independently claim to own `NSApp.servicesProvider` (AutomatorIntegration.swift:101 vs FinderQuickAction.registerAsService). Neither finding notes the collision. | Noted in #357 comment and human-decision list. |
| **#492** | "`ImagingConfig.imageFormat`/`DiscImageFormat` are now consumed by real code (DiscCommand.swift:245-264)" | Verified true (DiscCommand.swift:235-248). No change; recorded because #476 simultaneously lists `DiscImager` (where `ImagingConfig` is declared) as dead — the *type file* is partially live now; only DiscImager's raw-dd builder itself remains uncalled. | #476 comment worded accordingly. |