# MeedyaConverter — Durable Memory (OpenAI / Codex)

> Durable, slow-changing facts. Live status lives in `.claude/HANDOFF.md`.
> Last updated: 2026-09-17.

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
