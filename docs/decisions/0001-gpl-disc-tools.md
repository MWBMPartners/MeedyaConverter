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

## Status of the work

Recorded here and on #494. The packaging work — acquiring and pinning the
binaries, licence-text staging, source archival, the App-Store-exclusion build
check, and moving the drafted entries into `defaultManifest` — is **not yet
implemented** and remains tracked on #494.
