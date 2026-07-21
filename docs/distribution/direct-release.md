<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — Direct-distribution release runbook (Issue #428)

## 1. Scope

**Direct distribution (signed + notarised DMG and CLI tarball via
GitHub Releases) is MeedyaConverter's primary release channel.** This
document is the authoritative, step-by-step runbook for cutting a
Direct release, driven entirely by `.github/workflows/release.yml`.

This document does **not** cover the Mac App Store / TestFlight path
(the `Ltd.MWBMpartners.MeedyaConverter.Lite` build using the
`Mac Distribution` / `Apple Distribution` cert family and Apple's
`testflight.yml` workflow) — see
[`app-store-submission.md`](app-store-submission.md) for that.

## 2. Release at a glance

1. Date the `CHANGELOG.md` `## [<version>]` heading in the repo
   (CI does **not** commit this for you — see [Known gaps](#9-known-gaps--sharp-edges)).
2. Push a `vX.Y.Z[-rc.N]` tag pointing at the intended commit on `main`.
3. `precheck-secrets` fails fast if any `APPLE_*` secret is missing or
   wrong-family.
4. `release` job builds a universal (arm64 + x86_64) release binary and
   runs the release-mode test suite.
5. Assembles the `.app` bundle: SwiftPM resource bundle, generated
   `.icns`, and the first-party FFmpeg helpers.
6. Signs inside-out (helpers → frameworks → main executable → bundle).
7. Notarises and staples — the `.app` first, then again for the `.dmg`.
8. Generates SHA-256 checksums for the DMG and CLI tarball.
9. Publishes the GitHub Release with all four assets.
10. Maintainer runs a local smoke test, then the release soaks before GA.

## 3. Pre-flight checklist

- [ ] All six `APPLE_*` GitHub Actions secrets are populated with the
      **Developer ID Application** cert family. See
      [`apple-secrets-setup.md`](apple-secrets-setup.md). The
      `precheck-secrets` job in `release.yml` fail-fasts on this before
      any build or signing step runs, asserting `APPLE_SIGNING_IDENTITY`
      contains the literal substring `Developer ID Application`.
- [ ] `CHANGELOG.md` has a `## [<version>]` heading **with the real
      release date already filled in**, committed to `main` before you
      tag. CI's "Update CHANGELOG.md with release date" step only edits
      the runner's checkout — it is never committed back to the repo
      (see [Known gaps](#9-known-gaps--sharp-edges)).
- [ ] The commit you are about to tag is actually on `main`. GitHub
      Actions cannot enforce this for a tag push — `on.push.tags: ["v*"]`
      fires for a `v*` tag against any commit, on any branch or none.
      This is a maintainer discipline check, not a CI gate.
- [ ] The `VERSION` file at the repo root matches the base version
      you're about to tag (e.g. `0.1.0` for both `v0.1.0-rc.4` and
      `v0.1.0`). `release.yml` overwrites `VERSION` from the tag during
      the run, but keeping it in sync beforehand avoids confusion for
      anyone reading the tree between releases.

## 4. Cutting the release (rc.4 / GA)

```bash
# Release candidate — tag the exact commit sha on main
git tag v0.1.0-rc.4 <sha-on-main>
git push origin v0.1.0-rc.4

# General availability, once the rc has soaked clean
git tag v0.1.0 <sha-on-main>
git push origin v0.1.0
```

The tag must match `on.push.tags: ["v*"]` to trigger the workflow at
all, and its stripped version (the part after `v`) must then pass the
semver gate in the "Extract and validate semver from tag" step:

```text
^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+(\.[0-9]+)?)?$
```

i.e. `X.Y.Z` or `X.Y.Z-label.N` (`0.1.0`, `0.1.0-rc.4`, `1.2.3-beta.1`,
…). A tag that doesn't start with `v` never triggers the workflow; a
`v`-prefixed tag whose remainder fails this regex triggers the workflow
but fails the "Extract and validate semver from tag" step immediately.

**Critical nuance:** `release.yml` marks a release `--prerelease`
whenever the **major version is 0**, regardless of any `-rc`/`-beta`
suffix. That means **`v0.1.0` itself — the GA tag — still publishes as
a GitHub pre-release**, because `0.1.0`'s major component is `0`. Only
a `v1.0.0`-or-later tag (with no pre-release suffix) gets `--latest`
and a plain "Release" title. Don't be surprised when the "GA" release
shows up marked "Pre-release" on the Releases page — that's the
workflow behaving as written, not a bug.

The workflow's concurrency group is `production-release` with
`cancel-in-progress: true`: if you push a second tag while a release
run is still in flight, the earlier run is **cancelled**, not queued.
Don't push a second tag to "fix" something while a run is active —
wait for it to finish or fail first.

## 5. What CI does, step by step

Mirrors the jobs and numbered steps in `release.yml` as of this
writing:

- **`precheck-secrets`** (ubuntu-latest, ~2 min budget) — asserts all
  six `APPLE_*` secrets are non-empty and that `APPLE_SIGNING_IDENTITY`
  contains `Developer ID Application`. Never prints secret values.
- **Checkout** — full history (`fetch-depth: 0`), needed for the
  changelog step and the build-number calculation.
- **Universal build** — `swift build -c release --arch arm64 --arch
  x86_64`. SwiftPM writes universal output under
  `.build/apple/Products/Release`, not `.build/release`, so the workflow
  resolves the real path via `swift build ... --show-bin-path` and
  exports it as `SWIFT_BIN`.
- **Tests (release)** — `swift test -c release --parallel` gates the
  entire release; a failing (or flaky) test here blocks publication
  even if the build itself is fine.
- **Semver extraction** — strips the tag's `v`, validates the regex
  above, derives `IS_PRERELEASE`, syncs the `VERSION` file, and
  computes `BUILD_NUMBER` as `git rev-list --count HEAD` (a
  deterministic, monotonically-increasing integer required by Apple for
  `CFBundleVersion`).
- **App bundle assembly** — copies the universal binary into
  `MeedyaConverter.app/Contents/MacOS/`, then copies the SwiftPM
  resource bundle `MeedyaConverter_MeedyaConverter.bundle` (Assets,
  the AppleScript `.sdef`, bundled Help Markdown) into
  `Contents/Resources` — **fail-closed** if it's missing, added for
  #429 after a prior release silently shipped without it. Generates
  `MeedyaConverter.icns` via `scripts/generate-app-icns.sh`.
- **FFmpeg bundling** — `scripts/bundle-ffmpeg.sh` stages universal
  (arm64 + x86_64) `ffmpeg`/`ffprobe`/`ffplay` into `Contents/Helpers`,
  sourced solely from the first-party `MeedyaSuite/MeedyaDL-Tools`
  mirror pinned at `MDLT_TAG`, SHA-256-verified against that release's
  own `SHA256SUMS` before unpack, fail-closed on a missing pin/checksum
  file or a hash mismatch (F-011).
- **Signing** — `scripts/codesign.sh` signs **inside-out**: nested
  Mach-O executables under `Contents/Helpers`/`Contents/Resources`
  first (so bundled FFmpeg gets hardened runtime — required for
  notarisation), then frameworks/dylibs, then any nested `.app`
  bundles, then the main executable, then the top-level bundle. The
  CLI binary is signed standalone with its own entitlements.
- **Notarisation** — `scripts/notarize.sh` submits via
  `xcrun notarytool`, waits (15-minute timeout), and staples the
  ticket on success. Runs once for the `.app` and again for the `.dmg`.
- **DMG creation** — `scripts/create-dmg.sh` builds
  `MeedyaConverter-<version>-macOS.dmg` (compressed UDZO) containing
  the notarised `.app` plus an `/Applications` symlink, then the DMG
  itself is signed and put through notarisation + stapling a second
  time.
- **CLI tarball** — `meedya-convert-<version>-macOS.tar.gz`, containing
  the signed (but **not separately notarised**) CLI binary.
- **SHA-256 checksums** *(added in this change)* — `<asset>.sha256`
  generated for both the DMG and the CLI tarball after both exist.
- **`gh release create`** — publishes the tag as a GitHub Release with
  all four assets (DMG, CLI tarball, and their two `.sha256` files),
  the extracted changelog section as the release body, and
  `--prerelease`/`--latest` per the semver rule in
  [§4](#4-cutting-the-release-rc4--ga).

## 6. Verifying the artefacts locally (smoke test)

Run this after every cut, before telling anyone the release is ready:

```bash
# 1. Download both assets and their checksums from the Release page, then:
cd ~/Downloads
shasum -a 256 -c MeedyaConverter-<version>-macOS.dmg.sha256
shasum -a 256 -c meedya-convert-<version>-macOS.tar.gz.sha256

# 2. Gatekeeper + notarisation ticket checks on the DMG itself
spctl -a -vvv -t install MeedyaConverter-<version>-macOS.dmg
xcrun stapler validate MeedyaConverter-<version>-macOS.dmg

# 3. Mount, drag-install, then verify the installed app
#    (double-click the DMG, drag MeedyaConverter.app to /Applications)
codesign --verify --deep --strict /Applications/MeedyaConverter.app
xcrun stapler validate /Applications/MeedyaConverter.app
spctl --assess --type execute --verbose /Applications/MeedyaConverter.app
# expect: "accepted" / "source=Notarized Developer ID"

# 4. Confirm both the app binary and the bundled ffmpeg are genuinely universal
lipo -archs /Applications/MeedyaConverter.app/Contents/MacOS/MeedyaConverter
lipo -archs /Applications/MeedyaConverter.app/Contents/Helpers/ffmpeg
# expect: "x86_64 arm64" (order may vary) for both

# 5. Launch the app and run one real conversion end-to-end — this is the
#    only way to prove the bundled ffmpeg actually resolves and executes
#    at runtime, not just that it's present on disk.

# 6. CLI tarball
tar -xzf meedya-convert-<version>-macOS.tar.gz
./meedya-convert --version
```

Treat any failure here as release-blocking — do not tell users the
release is ready until every check above passes.

## 7. If the run fails / re-running

- **`precheck-secrets` fails** — fix the offending secret, then
  `gh run rerun <run-id>` (find the ID with
  `gh run list --workflow=release.yml`). There is **no
  `workflow_dispatch` trigger**, so `gh workflow run` will not work —
  don't push a new tag just to retry a secrets fix.
- **A later step fails after the GitHub Release already exists** (e.g.
  `gh release create` partially succeeded, or a step after it failed) —
  either `gh release delete <tag>` and delete/re-push the tag to run
  the whole pipeline again, or `gh release upload <tag> <missing-asset>`
  to patch in whatever didn't make it, whichever is cheaper for the
  specific failure.
- **A flaky `swift test -c release` failure blocks the whole release**
  — the release job has no test-retry logic; a genuinely flaky test
  will fail the run even when the code is fine. Re-run with
  `gh run rerun <run-id>` rather than assuming the code is broken; only
  escalate to fixing the test itself if it fails consistently.
- **A second tag pushed while a run is in flight cancels the first**
  (the `production-release` concurrency group has
  `cancel-in-progress: true`) — if the cancelled tag still needs to be
  released, `gh run rerun <run-id>` on the cancelled run restarts it
  cleanly; don't assume the cancelled run left anything usable behind
  (partial `.app`/DMG state is discarded with the runner).

## 8. Soak-window policy

> **TODO (owner: define in #428):** how long does an `-rc.N` release
> need to soak, and what counts as a clean bill of health, before it's
> promoted to GA?
>
> Placeholder policy pending that decision: an `rc.N` soaks for
> **TBD days** with real usage before `v0.1.0` GA is cut; GA requires
> **zero P0/P1 issues** filed against that specific rc during the soak
> window. Update this section once the owner has actually set the
> number.

## 9. Known gaps & sharp edges

- **(a) The CHANGELOG date step doesn't persist.** The "Update
  CHANGELOG.md with release date" step in `release.yml` stamps
  `## [Unreleased]` → `## [<version>] - <today>` (or adds a date to an
  existing undated heading), but it only edits the *runner's* checkout
  — nothing commits that change back to the repository. **Date the
  `## [<version>]` heading in the repo yourself, before tagging**, or
  the published release notes will show a date that never makes it
  into `main`'s history.
- **(b) The CLI tarball is signed but not notarised.** Only the `.app`
  and the `.dmg` go through `scripts/notarize.sh`; the CLI binary
  inside `meedya-convert-<version>-macOS.tar.gz` is Developer-ID-signed
  only. A copy downloaded via a browser (and therefore
  quarantine-flagged) may need
  `xattr -d com.apple.quarantine meedya-convert` before Gatekeeper will
  let it run, since there's no stapled ticket to satisfy an offline
  check.
- **(c) Bumping the FFmpeg pin is one deliberate edit.** The FFmpeg
  supply chain is pinned to `MDLT_TAG` in
  `scripts/bundle-ffmpeg.sh`. Picking up a newer FFmpeg build is a
  single, intentional change to that one line — there's no
  auto-update, and there's no local checksum list to keep in sync
  (the first-party release's own `SHA256SUMS` is the trust root).

## 10. Cross-links

- [`apple-secrets-setup.md`](apple-secrets-setup.md) — populate the six
  `APPLE_*` secrets this pipeline depends on.
- README ["Install — Direct download"](../../README.md#-install--direct-download) —
  the user-facing instructions for the assets this pipeline produces.
  Keep asset names in lock-step with `release.yml`: any rename here
  needs a matching README update, and vice versa.
- [`sparkle-cloudflare-worker.md`](sparkle-cloudflare-worker.md) — the
  planned in-app auto-update path (Sparkle 2 + Cloudflare Worker
  appcast proxy). Not active for `v0.1.0` — updates are manual until
  that lands.
- [`app-store-submission.md`](app-store-submission.md) — the separate
  Mac App Store / TestFlight (`.Lite`) submission path, out of scope
  for this document.
