<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# DR-0001 — Bundling GPL disc tools for optical-disc imaging

- **Status:** Accepted
- **Date:** 2026-09-01
- **Decision maker:** MWBM Partners Ltd (maintainer)
- **Tracking issue:** [#494](https://github.com/MWBMPartners/MeedyaConverter/issues/494)
- **Feature this gates:** [#492](https://github.com/MWBMPartners/MeedyaConverter/issues/492) cross-platform disc-backup imaging, [#495](https://github.com/MWBMPartners/MeedyaConverter/issues/495) Audio CD → BIN/CUE

## Context

Optical-disc imaging needs raw sector reads with subchannel capture. The
practical tools for that are `cdrdao` (GPLv2), GNU `ddrescue` (GPLv3) and
`wodim`/cdrkit (GPLv2). MeedyaConverter is proprietary, and
`ToolBundleManifest` bundles **no GPL tools today** — the closest precedent is
LGPL-2.1 `fpcalc`.

The original framing treated this as a licensing question with an App Store
dimension. **That framing was incomplete.** The App Store dimension is settled
by a technical fact, not by licensing:

`Sources/MeedyaConverter/Resources/MeedyaConverter-AppStore.entitlements`
declares `com.apple.security.app-sandbox` with only `network.client`,
`files.user-selected.read-write`, `files.bookmarks.app-scope` and
`files.downloads.read-write`. **The App Sandbox has no entitlement that grants
raw optical-device access** (`/dev/rdisk*`, SCSI/MMC passthrough) — Apple does
not offer one. Disc imaging therefore cannot function in an App Store build
**whatever licence the tools carry**, and even a clean-room native MMC
reimplementation would not change that.

So the real question is narrower than it looked: given the feature is
Direct-distribution-only regardless, how do we obtain the tools?

## Decision

**Bundle the GPL binaries in the Direct `.dmg` only.**

Rationale:

- Shelling out to **unmodified** GPL binaries is *mere aggregation*
  (GPLv2 §2, GPLv3 §5). That is safe for a proprietary application provided we
  do not link against them, do not maintain a private fork, ship each tool's
  licence text, and make a written offer for the corresponding source.
  The disc code is already arg-builder + subprocess, so it fits this shape.
- The alternative (PATH-detect only) is zero-risk but would leave the feature
  silently unavailable for almost every alpha tester, which defeats the point
  of shipping it in an alpha cycle.
- Native MMC reimplementation removes the GPL question but is XL effort,
  heavily drive-quirk dependent, and — per the sandbox fact above — buys no
  App Store eligibility in return.

## Consequences

**Must hold before any Direct release that carries these tools:**

1. **Never link `libcdio` (GPL) into `ConverterEngine`.** CLI tools only,
   invoked as subprocesses. Linking would make the aggregation argument fail.
2. **Ship each tool's licence text** in the `.dmg` alongside the binaries.
3. **Ship a written offer for source**, and archive the exact source tarballs
   used for each bundled build so the offer can be honoured.
4. **The App Store bundle must contain none of these binaries.** Packaging
   needs a build-time check that fails if a GPL-licensed `BundledTool` is
   present in an App Store bundle — mirroring the existing ITMS-90236 icon
   guard in `testflight.yml`.
5. **The feature must be hidden, not merely broken, in App Store builds** —
   gate the UI and CLI entry points on the same `isDirectBuild` flag
   `Package.swift` already defines.
6. **NRG and other proprietary formats stay clean-room** — implemented from
   public format documentation, never by copying GPL `libmirage` code, and
   described as "Nero-compatible" rather than by trademark.

**Not affected:** the existing `ToolBundleManifest` entries (MIT / MPL-2.0 /
BSD-2-Clause / LGPL-2.1) and the FFmpeg supply chain, which is separate.

## Drafted `ToolBundleManifest` entries

These are **drafted, not committed to `defaultManifest`**, and deliberately so.
`ToolBundleManifest.defaultManifest` describes tools the app *actually ships*;
adding entries for binaries that are not yet in the bundle would make the app
assert a capability it does not have — the fabricated-capability pattern this
codebase treats as a defect. Move these into `defaultManifest` in the same
change that first stages the binaries into the Direct `.dmg`, not before.

```swift
BundledTool(
    id: "cdrdao",
    name: "cdrdao",
    version: "1.2.5",                       // pin the exact build shipped
    sourceURL: "https://github.com/cdrdao/cdrdao",
    lastUpdated: "<staging date>",
    binaryName: "cdrdao",
    description: "Raw CD sector and subchannel reading (TOC, ISRC, CD-Text, pre-gaps)",
    license: "GPL-2.0-or-later"
),
BundledTool(
    id: "ddrescue",
    name: "GNU ddrescue",
    version: "1.28",
    sourceURL: "https://www.gnu.org/software/ddrescue/",
    lastUpdated: "<staging date>",
    binaryName: "ddrescue",
    description: "Fault-tolerant sector recovery for damaged or degrading discs",
    license: "GPL-3.0-or-later"
),
BundledTool(
    id: "wodim",
    name: "wodim (cdrkit)",
    version: "1.1.11",
    sourceURL: "https://github.com/Distrotech/cdrkit",
    lastUpdated: "<staging date>",
    binaryName: "wodim",
    description: "Disc writing and device enumeration",
    license: "GPL-2.0-only"
),
```

Note the `license` strings are SPDX identifiers, whereas the existing entries
use looser forms (`"MIT"`, `"LGPL-2.1"`). Normalise the whole manifest to SPDX
in the same change, so the App-Store-exclusion check can match on a reliable
prefix (`GPL-`) rather than on free text.

## Operational decisions (finalised 2026-09-02, by the maintainer)

The four follow-on questions the decision left open are now answered:

1. **Issue scope** — #494 stays **open** until the packaging work is complete,
   not merely until the decision is recorded.
2. **Where the source lives** — the corresponding GPL source, and the built
   binaries, are hosted in the existing first-party tools mirror
   **`MeedyaSuite/MeedyaDL-Tools`**, exactly as ffmpeg / mediainfo / fpcalc
   already are. That repo's `populate.yml` workflow is extended to build the
   tools and to **archive the exact source tarball** for each, published as a
   release asset alongside the binaries and the `SHA256SUMS`. The written offer
   in the `.dmg` points at that release.
3. **Provenance** — **build our own**, per platform, from the upstream source
   tarball, matching how ffmpeg is already produced (compiled on the mirror's
   CI runners, SHA-256-verified, universal on macOS). Not redistributed
   third-party binaries.
4. **Which tools, which round** — **all of them in the mirror this round**
   (efficient, and a mirror holding a binary asserts nothing about the app),
   but **none in the app yet**. This is a stronger statement than "P1 subset":
   the disc-imaging *executor* does not exist — `RawCDReadPlanner`,
   `DiscImagingController`, `CdrdaoTocParser` and `BundledToolLocator` are all
   absent, and `cdrdao`/`wodim`/`cdparanoia` have zero code references (the only
   `ddrescue` mentions are in the orphaned `DiscImager` arg-builder that nothing
   runs). Bundling a binary the app cannot invoke, or listing it in
   `ToolBundleManifest.defaultManifest`, would be the fabricated-capability
   defect this project polices. The tools enter the app's bundle and manifest
   in the same change that first invokes them (#495's missing executor half).

**Platform scope:** macOS (universal arm64 + x86_64) and Linux only, matching
#495's stated target. `cdrdao`/`wodim` are Linux-centric and do not build
cleanly on Windows, where optical imaging is a separate future effort (IMAPI /
SPTI), so no Windows disc-tool build is attempted.

## Guards now in place (MeedyaConverter side)

The App-Store-exclusion criterion is implemented as defence in depth, and holds
today because no GPL tool is bundled yet:

- **Manifest invariant + test.** `BundledTool.isGPLFamily` (SPDX-aware, excludes
  LGPL) and `ToolBundleManifest.isAppStoreSafe`; a regression test
  (`test_toolBundleManifest_defaultManifestIsAppStoreSafe`) fails CI if any
  GPL-family tool ever appears in `defaultManifest`, which ships to every
  distribution including the App Store.
- **Bundle tripwire.** `scripts/verify-no-gpl-in-appstore.sh` scans an assembled
  `.app` for the GPL tool binaries by name and exits non-zero if any is found.
  It is wired into `testflight.yml`'s pre-signing validation, alongside the
  existing ITMS-90236 icon guard.

## Status of the work

Recorded here and on #494. The packaging work — acquiring and pinning the
binaries, licence-text staging, source archival, the App-Store-exclusion build
check, and moving the drafted entries into `defaultManifest` — is **not yet
implemented** and remains tracked on #494.

## Amendment 1 — 2026-09-03

The packaging work above has now landed for the FIRST GPL tool, and two
statements in the original decision text need correcting against what was
actually built:

(a) The first GPL tool actually shipped is **potrace** (#473 vector tracing),
not a disc tool. `cdrdao`/`ddrescue`/`wodim`/`cdparanoia` remain unbundled —
see (d) below.

(b) The Direct-only mechanism is `ToolBundleManifest.directOnlyManifest` +
`activeManifest`, gated on **`#if APP_STORE`** — not `isDirectBuild`/`DIRECT`,
which `release.yml` deliberately never sets (Sparkle updates require it stay
unset). Consequence #5 above ("gate on `isDirectBuild`") reads in practice as
"hidden when `APP_STORE`, bundled and reachable otherwise": `defaultManifest`
ships in every distribution (vtracer, MIT, lives there — it was never
GPL-family despite some earlier drafts saying otherwise); `directOnlyManifest`
holds potrace and is merged into `activeManifest` except under `#if APP_STORE`.
The manifest invariant test, the bundle tripwire
(`scripts/verify-no-gpl-in-appstore.sh`, which now also lists `potrace`), and
the `#if APP_STORE` nav gate are three independent guards.

(c) macOS "universal" (operational decision 3, above) is achieved on the
**converter side** via `lipo` (`scripts/bundle-tracing-tools.sh`, mirroring
`scripts/bundle-ffmpeg.sh`) — the mirror (`MeedyaDL-Tools`) publishes THIN
per-arch assets only; there is no `lipo` step in that repo.

(d) Correcting operational decision 4's inventory: `RawCDReadPlanner`,
`DiscImagingController`, `CdrdaoTocParser`, and `BundledToolLocator` now exist
(issue #495), and `DiscCommand` invokes `cdrdao` — yet `cdrdao` is still
neither built by the mirror nor bundled by the converter. This is an open gap
under the "same change" rule stated above (tools enter the bundle/manifest in
the same change that first invokes them): `cdrdao` is invoked but not bundled.
Tracked on #494/#495; **not fixed by this amendment** — potrace's packaging
followed the rule correctly (the executor and the bundle step landed together)
and is not a precedent for leaving `cdrdao` half-wired.

The accepted decision text above is left as originally recorded; this
amendment corrects it against what shipped, per the project's "no false
comments" policy.
