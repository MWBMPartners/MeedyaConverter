# MeedyaConverter — Durable Memory (OpenAI / Codex)

> Durable, slow-changing facts. Live status lives in `.claude/HANDOFF.md`.
> Last updated: 2026-09-21.

## Identity

- **Product:** MeedyaConverter — professional, cross-platform media conversion
  toolkit; a modern HandBrake alternative. Proprietary, © MWBM Partners Ltd.
- **Primary platform:** macOS 15+ (Apple Silicon + Intel universal), Swift 6.3 /
  SwiftUI. Windows/Linux are planned (v2.0).
- **Part of the Meedya suite:** MeedyaConverter, MeedyaDL, MeedyaManager,
  MeedyaDB, and the optional Rust core MeedyaSuite-core.

## Architecture

- **ConverterEngine** — cross-platform Swift core library (all encoding,
  analysis, disc, metadata logic).
- **meedya-convert** — command-line tool (Swift ArgumentParser) built on the
  engine. Subcommands: `encode`, `probe`, `profiles`, `batch`, `manifest`,
  `validate`, `serve`.
- **MeedyaConverter** — macOS SwiftUI app (MVVM, `@Observable @MainActor`).
- **Media engine:** FFmpeg subprocess (Direct build) or FFmpegKit (App Store).
- **APIs:** the CLI, plus an alpha HTTP server (`meedya-convert serve`). Both are
  documented as OpenAPI 3.1 in `docs/api/` with a self-hostable Swagger UI.

## Release / branch state

- **Working branch:** `wip/alpha-consolidation` — all work commits here; reaches
  `alpha` via one PR later (no PR stacking).
- `main` = trunk; `alpha`/`beta` = live pre-release channel branches (pushing to
  them mints a public pre-release — never delete them).
- Latest Direct release line: `v0.1.0-rc.3`; alpha channel `v0.1.0-alpha.3`.

## Subsystem status relevant to disc work (as of 2026-09)

- **Disc burning** (writing an existing image to physical media via
  cdrecord/growisofs/hdiutil) is **real and reachable**.
- **Audio CD imaging** is real: `DiscImagingController` drives `cdrdao` to make a
  verified BIN/CUE image, with a DRM detect-and-**refuse** gate (never decrypts).
- **Raw disc→image copying** args exist in `DiscImager` (dd / ddrescue / readom /
  hdiutil).
- **Disc ripping/authoring is orphaned** — `DVDReader`, `BlurayReader`,
  `DiscAuthor`, `DiscImager` and friends have no UI/CLI entry point. Umbrella
  issue: **#476**.
- **Content-based disc identification — slice 1 (#502).** New pure engine
  `Disc/DiscIdentification.swift` (`DiscSignals`, `DiscIdentifier`) ranks candidate
  identities against a disc's own content (running time, title, year). Offline,
  deterministic, no decryption. Later: provider adapters (#205), reader wiring
  (#476), UI. Keyless MusicBrainz Audio CD/TOC lookup landed (26fcb06). MeedyaDB
  publishing hook landed (3a0108a) — see below.
  MakeMKV backend (#503): slice 1 pure parser (8350640), slice 2 opt-in/terms gate
  (fb8adc8), slice 3 executor (d6c7f15), slice 4a identification bridge (253f21e)
  — all CI-green. **4b = GUI rip flow (owner chose it, 2026-09-20)**; design at
  `.claude/plans/makemkv-gui-rip-flow-plan.md` (includes a ranked compile-trap list).
  Remaining after 4b: (5) docs/licences.
- **Music discs are identifiable AND contributable (e017f89, CI run 325).** A CD's track
  layout is a near-fingerprint, so the MusicBrainz lookup is an EXACT hit — stronger than
  the video path's ranked guess. `MusicBrainzDiscID` computes the canonical Disc ID
  (`DiscTableOfContents.musicBrainzDiscId` had existed unfilled since day one), and
  `MeedyaDBSubmissionBuilder` turns either kind of disc (music or video) into
  `MeedyaDBPublisher` inputs — previously nothing built a submission at all.
- **The app layer IS unit-testable**: it is a library target `MeedyaConverterCore` with
  `Tests/MeedyaConverterCoreTests` (`@testable import`). Do not assume SwiftUI code here
  is untestable — view models can and should be covered.
- **#503 slice 4b SHIPPED (7ce4d04, run 329):** the MakeMKV rip screen (sidebar entry,
  gated, scan → pick titles → rip with progress). Ripped files are just saved — no
  auto-queue/auto-identify by owner decision. Remaining: slice 5 (docs/licences), and a
  pre-decrypted VIDEO_TS/BDMV folder source is not offered yet.
- **DUAL DISC IDs (b567642 + MeedyaDB 7569e99):** `compute(for:)` = music-only
  (MusicBrainz-compatible, used for lookups AND as MeedyaDB's key);
  `computeWholeDisc(for:)` = whole physical disc, sent as a `fulldisc-discid`
  identifier when it differs. Identical on an ordinary CD. `musicBrainzTOCString`
  changed in lockstep — Enhanced-CD lookups now ask about the music portion.
- **IDENTIFICATION NOW ACTUALLY RUNS for music discs (996cc19 + 1bee778).** New
  `MusicDiscIdentifier` chains an already-read TOC → disc IDs → MusicBrainz → MeedyaDB
  submission → publish, plus a CLI `meedya-convert disc identify` (`--device` reads a
  real disc via the cdrdao path `disc toc` already used; `--toc` reads a saved file;
  `--offline` contacts nothing). Reading the disc stays in `DiscImagingController`, so
  the chain is testable with no hardware.
  **The failure posture is the design, not an oversight:** a MusicBrainz outage keeps the
  locally computed IDs and STILL contributes (an unknown disc is the interesting one);
  MeedyaDB off/unconfigured is `.notAttempted`, NEVER `.failed` (that is everyone until
  the server is live); cancellation is never folded into `.failed`; a disc with no audio
  short-circuits before the network. `identify` throws only `CancellationError`.
  Contributing is opt-in per run (`--submit`); the API key is env-only (`MEEDYADB_API_KEY`)
  because argv is world-readable via `ps`.
- **VIDEO identification is wired too (202ef0a), and the app has an Identify Disc
  screen (8df1936) + a MeedyaDB settings tab (6f4ee66).** `MeedyaDBContributor`
  (`MeedyaDBAccess.swift`) is now the ONE home of the contribute failure posture,
  shared by music and video — two copies of those judgement calls would drift.
- **Video identification is a RANKED GUESS, never an exact hit** (music is exact, from
  the TOC). The summary deliberately says "Best guess: X (98% confident)". Candidates
  are passed IN by the caller because every video provider is keyed and unwired (#205),
  so `candidates: []` is normal — the disc is still contributed on its structural
  fingerprint. **#205 is now the binding constraint on video identification.**
- **Unmounting a disc is NEVER automatic** (owner decision, 2026-09-21): `DiscBusyDetector`
  decides whether to offer the remedy, and the user presses the button.
  `buildMacOSUnmountArguments` is no longer unwired — its "needs hardware to map the
  device back" note does not apply in this direction, because the app already holds the
  device path and `diskNode(forRawDeviceNode:)` just undoes the known transform.
- **`isEnhancedCD` is decided STRUCTURALLY** (from `leadOutSource`), not by comparing two
  ID strings — a stored/stale tag would make an ordinary CD look Enhanced.
- **A `static` stored property on a `@MainActor` type is MainActor-isolated**, so it
  cannot serve as a default argument evaluated at a nonisolated call site. Inline the
  closure instead (`DiscIdentifyViewModel` does).
- **`MetadataResult` and `ScoredDiscMatch` are NOT `Equatable`** — anything carrying them
  cannot be either.
- ~~Nothing in the app constructs `MeedyaDBPublisherConfig`~~ — **DONE** (c89590a + 6f4ee66):
  `MeedyaDBConfigStore` / `MeedyaDBGate` + a settings tab. The key lives in the
  **Keychain** via `APIKeyProvider.meedyaDB`, never in `@AppStorage` (a plain-text plist);
  a test sweeps the whole defaults suite to prove it never lands there. The stored
  submission mode fails SAFE — anything but an exact `full` reads as `anonymous`.
- **`Task { [weak self] in await self?.f() }` infers `Task<()?, Never>`** and will not
  match `Task<Void, Never>`. Always `guard let self else { return }` first. CI caught
  this; the review did not.
- **A bare enum case does not match against an `Optional` in a `switch`** — `case .foo:`
  over a `T?` needs `case .foo?:` or an unwrap first. Same family as the `as?` trap below.
- **Cancel methods must ONLY cancel.** Clearing the busy flag / task handle / message in
  the canceller as well as in the task's own tail lets a stale task clobber whatever
  started next. Leaving the busy flag set until the task itself tidies up also closes the
  re-entry window for free (learned on the rip screen, run 331).
- **Test the WIRING, not just the layer.** The label-scrubbing privacy rule was tested in
  `MeedyaDBPublisherTests`, one layer below the code that passes `mode:` in — so
  hardcoding `.full` at the call site would have left every test green while real data
  leaked. Cover the call site, by asserting on the bytes that reach the seam.
- **Never put backticks in `git commit -m "…"`** — the shell executes them and eats
  words. Use `git commit -F <file>` with a quoted heredoc.
- **MakeMKV (#503) is APPROVED as an *optional, opt-in* backend** (owner,
  2026-09-17, accepting the legal implications) — no longer "deferred". Slice 1
  landed CI-green (8350640, run 314): `MakeMKVBackend` is a **pure** arg-builder +
  robot-mode parser only. It does NOT locate, run, enable, or bundle makemkvcon
  and changes NO policy. Slice 2 landed CI-green (fb8adc8, run 317): the
  off-by-default opt-in + terms gate — `MakeMKVAccess.swift` (`MakeMKVConsent`,
  `MakeMKVConsentStore`, `MakeMKVGate.readiness`) + a `MakeMKVSettingsTab` (opt-in
  toggle, terms field, path, honest status). Remaining: executor (3), rip-flow +
  CLI wiring (4), docs/licences (5).
- **Metadata lookup is largely dead:** MusicBrainz lookup executes (#205 slice),
  but the keyed providers (TMDB, TheTVDB, Discogs, FanArt.tv, OpenSubtitles,
  OMDb) only build request URLs, and `AutoTagger` has no callers. Metadata
  **writing** is real (#467). Tracking: **#205**.
- **DRM posture:** the raw imaging path deliberately detects and **refuses**
  copy-protected discs; it never decrypts (#492) — `DiscProtectionDetector.policy`.
  This refuse-by-default line stays for every path EXCEPT the owner-approved,
  off-by-default, consent-gated MakeMKV opt-in path (#503), which delegates
  unlocking to the user-installed MakeMKV. Slice 1 (the pure backend) touches none
  of this; a test pins that the refuse-gate still refuses.

## Third-party disc libraries (invoked as subprocesses, not linked)

libdvdread/libdvdnav (GPL2), libbluray (LGPL 2.1), libcdio/cdparanoia (GPL),
Tesseract OCR (Apache 2.0), libmediainfo (BSD-2). GPL tools are run as
subprocesses to keep the proprietary app code licence-clean.

## Environment facts (do not re-learn the hard way)

- Swift 6.3 toolchain is present: `swift build --target ConverterEngine` works and
  is the pre-commit gate. `swift test` / SwiftLint cannot run locally (no Xcode) —
  **CI is the test gate**.
- `swift build` of the whole package fails only on `#Preview` macros (a
  CommandLineTools limitation) — not a code bug; do not "fix" the previews.
- CI runs on every push to `wip/**` (#496).
- **CI runs `swift test --parallel`** → never share a mutable global across test
  methods (UserDefaults suite name, temp path, top-level type name): a sibling
  test's setUp/teardown can wipe your state mid-run. Use a **unique UUID
  UserDefaults suite per test instance**. Reviewers trace tests in isolation and
  miss these races; only CI catches them (learned on #503 run 316→317).
- **`swift build` (library/app) does NOT compile the test targets** — a test-only
  compile error (e.g. matching an enum case against an `Optional` from `as?` without
  unwrapping) passes the build step and only fails at `swift test`. Reviews miss these;
  CI is the definitive compile gate (learned on #503 run 319→320). Unwrap `as?` with
  `guard/if let` before a `case` pattern match.
