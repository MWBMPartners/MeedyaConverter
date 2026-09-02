<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Known limitations — v0.1.0-rc.4 Direct test build (DRAFT)

This is the honest list of what is **partial, disabled, or not in** the first
Direct-distribution test build, so testers don't chase features that aren't
ready. It is release-notes content: fold the relevant items into the GitHub
Release body when the tag is cut. Everything here was reconciled against the
actual code (a pre-release readiness pass), not comments.

> Assumes `wip/alpha-consolidation` is merged to `main` before the tag — several
> items below (hidden vector tools, wired pipelines/chapters, etc.) reflect that
> branch. If the tag is cut from `main` without that merge, re-verify.

## Not in this build (hidden)

- **Vector Conversion** and **ProRes → Vector** — the tracing engines can't
  execute yet (no bundled potrace/vtracer/rsvg), so the views are hidden until
  they can.
- **Cloud Sync (iCloud)** — the Direct build carries no iCloud entitlement, so
  it could only fail; hidden. Cloud **Storage** (below) is unaffected.
- **YouTube / Vimeo upload** — disabled pending OAuth app registration.

## Requires separately-installed tools

- **Dual Dynamic HDR** needs `dovi_tool` and `hdr10plus_tool` (Homebrew); they
  are not bundled. The Convert button stays disabled and the view shows what's
  missing.
- **Disc burning** supports **ISO images via `hdiutil`** only. DVD-Video /
  Blu-ray authoring and Audio-CD burning need tools macOS doesn't ship
  (cdrecord/growisofs); those paths fail cleanly if the tools aren't installed,
  and "Simulate (dry run)" is honoured only for Audio CD.
- `meedya-convert disc` (CD → BIN/CUE imaging) needs a separately installed
  `cdrdao` and an optical drive.

## Partial / configuration-only

- **Cloud uploads** cover **S3** (incl. S3-compatible endpoints), **Dropbox**,
  **Google Drive**, and **OneDrive**. GCS, Azure, and Backblaze-native are not
  selectable yet.
- **SFTP** uploads run as **post-encode actions** (Settings → Hooks); the SFTP
  settings screen tests/saves connections only. Key-based auth only.
- **Render Farm** settings are configuration-only; distributed encoding is not
  active yet (the tab says so).
- **Filter Graph editor** produces a filter string to copy — it does not yet
  attach to encodes.
- **Plugins** — the plugin host does not yet load or run third-party plugins.
- **Resumable jobs** re-queue from 0% (restart, not seek-resume).
- **Parallel encoding** is limited to 1 concurrent job in unlicensed builds.
- **Media metadata *lookup* / auto-tagging** (MusicBrainz, TMDB, …) is not in
  this release. The metadata tag **editor** writes tags for real.
- `meedya-convert serve` accepts jobs over its REST API but does not drive the
  queue — jobs stay `queued` until run (documented in the CLI reference).
- **In-app auto-update** is not active for 0.1.0 — updates are manual DMG
  downloads from GitHub Releases.
- **CLI tarball** is signed but not notarized in this build; a browser-downloaded
  copy may need `xattr -d com.apple.quarantine meedya-convert` on first run.

## What genuinely works (highlights)

End-to-end conversion (import/probe → 24 profiles → queue with real
pause/resume/cancel, live progress, crash-safe checkpoints); HDR tone-mapping /
PQ→HLG / subtitle tone-mapping through to output; scene detection with chapter
embedding, bitrate heatmap, quality/VMAF/SSIM/PSNR metrics, loudness reports;
concatenation (lossless + re-encode), two-pass stabilization, deinterlacing,
watermarking, metadata tag writing, batch rename with undo; watch folders,
conditional rules, scheduled encodes, multi-output, post-encode hooks (email,
webhooks, Plex/Jellyfin/Emby scans); statistics with CSV/JSON export; authenticated
uploads to S3/Dropbox/Drive/OneDrive; mini-player, menu-bar status, custom
keyboard shortcuts, settings undo/redo, AppleScript/JXA; and the full CLI
(`encode`, `probe`, `profiles`, `batch`, `manifest`, `validate`, `serve`, `disc`).
