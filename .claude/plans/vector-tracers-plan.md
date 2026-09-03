<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Implementation Plan — Vector tracers (#473 / #494): potrace + vtracer, Direct builds only, GPL-compliant

> **Status: PLANNED.** Fable 5.1 deep-plan (2026-09-03) against MeedyaConverter HEAD `24dd90a` on
> `wip/alpha-consolidation` (moved past the scouts' `9511291`; the only intervening change is
> `.claude/HANDOFF.md`, so every Source/Tests/scripts anchor below was re-verified at `24dd90a`) and
> against `MeedyaSuite/MeedyaDL-Tools` `main` (+ open PR #25 `feat/gpl-disc-tools`, MERGEABLE, unmerged).
> Suggested save path: `.claude/plans/vector-tracers-plan.md`. `swift test` is CI-only here; gate locally
> with the compile filter, push, watch CI to green. Re-run `git log -1` before editing.

## Corrections to the scout inputs (verified live, not from memory)

These change the plan; implementers must not follow the scouts where they conflict with this list.

1. **vtracer's licence** is `MIT OR Apache-2.0` (workspace `Cargo.toml` `license = "MIT OR Apache-2.0"`; GitHub's licence detection on the root `LICENSE` file says MIT). Either way **not GPL-family** — scout C/B were right on the conclusion. Record it in the manifest as `"MIT"` with a comment noting the dual licence.
2. **vtracer's CLI has been restructured since the arg builder was written.** Current release is **`1.0.0-alpha.4`** (2026-08-29, GitHub `prerelease=false`), crate `crates/vtracer-cli`, clap 4 with `rename_all = "kebab-case"` (`crates/vtracer-cli/src/main.rs:16`): flags are `--input/-i`, `--output/-o`, `--preset`, `--clustering {color-cluster|bw|watershed}`, `--hierarchical`, `--mode/-m {pixel|polygon|spline}`, `--filter-speckle/-f` (0..=128), `--color-precision/-p` (1..=8), `--gradient-step/-g` (0..=255), `--simplify`, `--path-precision`, `--palette`, `--max-colors N`, `--optimize`, `--threshold`, `--adaptive*`, `--watershed-detail`; `--corner-threshold`/`--segment-length`/`--splice-threshold` are hidden. The last 0.x release, `0.6.4` (2024, clap 2), used `--colormode`, `--filter_speckle`, `--segment_length`, etc. **`--no-alpha`, `--flatten`, `--preserve-metadata` exist in NO version.** `RasterVectorConverter.buildVTracerArguments` (`RasterVectorConverter.swift:281-305`) emits `--preserve-metadata` under the *default* config (`preserveMetadata: true`), so as written vtracer would exit with a clap usage error on every run. The builder must be rewritten against the pinned version (Part 2 §C).
3. **potrace reads only PBM/PGM/PPM/BMP** (`potrace(1)`: "potrace can read bitmaps in the following formats: PBM, PGM, PPM … as well as BMP") — not PNG/JPEG. The executor needs an ffmpeg pre-pass to BMP. potrace's licence is GPL-2.0-or-later (its README: "either version 2 of the License, or (at your option) any later version"); tarball `https://potrace.sourceforge.net/download/1.16/potrace-1.16.tar.gz` is live (HTTP 200, 657,314 bytes).
4. **`ProResToVectorConverter.buildFrameExtractionArguments` passes `-vf` twice** when `frameStride > 1` (`ProResToVectorConverter.swift:202-213`); ffmpeg keeps only the last `-vf`, silently dropping `format=rgba` / the HDR tonemap chain. Also `-r <fps>` + `select=` makes ffmpeg duplicate kept frames to hold the output rate, defeating the stride. Fix in Part 2 §C.
5. **`#if DIRECT` is not the gate.** `release.yml:264-267` explicitly keeps `DIRECT` UNSET (Sparkle). The only compile-time distinguishing flag actually set by any pipeline is **`-Xswiftc -DAPP_STORE`** (`testflight.yml:170`, `dev-build.yml:131`), which reaches every target including `MeedyaConverterCore`; precedent `Sources/ConverterEngine/AppInfo.swift:34`. DR-0001 consequence #5's "gate on `isDirectBuild`" is therefore implemented as **`#if APP_STORE` → hidden; otherwise available**. (The runtime `AppUpdateChecker.isDirectBuild` bundle-ID check is a third signal; do not use it for this — it returns `true` under xctest.)
6. **`.claude/HANDOFF.md:224` ("MeedyaDL-Tools … has no macOS compile runner yet") is wrong** — a `macos-latest` matrix leg already exists (`populate.yml:1279-1281`, job `build-python-tools`, used for PyInstaller + Homebrew aria2c at `1374-1387`). What is missing is a job that *compiles a C/Rust tool* on it. Fix the HANDOFF sentence in Part 2 §H.
7. **PR #25's flatten-filter bug is on `main` too** (`populate.yml:1456`): only `*.tar.gz|*.zip|*.exe` reach the release. potrace's source tarball is `.tar.gz` so it survives by accident; fix the filter anyway (Part 1 §5).
8. Upstream vtracer publishes prebuilt `vtracer-{aarch64,x86_64}-apple-darwin.tar.gz`; we still **build from source** (DR-0001 operational decision 3, `0001-gpl-disc-tools.md:136-139`; F-011 — we sign+notarise what we bundle).

---

# PART 1 — MeedyaSuite/MeedyaDL-Tools PR (the unblocker)

## Branch / PR mechanics

- **Fresh branch `feat/vector-tracing-tools` off `main`; its own PR. Do not fold into PR #25.** Reasons: PR #25 carries a confirmed defect (flatten filter) and stale prose ("no macOS runner", "mirroring how ffmpeg's universal binary is assembled" — no lipo exists anywhere in that repo) that need their own fix-up; potrace/vtracer serve a different feature (#473) with a different consumer path; a small PR lints/reviews independently and does not wait on the disc-tool decisions. Expect a one-line conflict at `populate.yml:1456` if #25 merges first — trivial.
- **Never push to `main` directly.** `populate.yml` triggers on `push: branches: [main]` (`:29`) and forces a full rebuild of every tool (`:83-94`), cutting a dated release.
- **To exercise the build on the PR, label it `update-tools`** — every build job is gated on `github.event_name != 'pull_request' || contains(labels, 'update-tools')` (`:328-332`, `:1266-1269`). `upload-release` never runs on PRs (`:1421-1423`), so **no release is cut until merge**; after merge the push trigger builds everything and publishes `YYYY-MM-DD[.N]` + `latest` (`:1481-1542`). That post-merge tag is what Part 2 pins.
- Lint gate: `lint.yml` runs actionlint v1.7.12 with shellcheck at `--severity=error` on workflow changes. Run `actionlint` locally before pushing.

## Files

| Action | Path (MeedyaDL-Tools) |
|---|---|
| **Modify** | `.github/workflows/populate.yml` — env pins; `check-versions` outputs/force-list/pinned-compare/versions-new.json; new job `build-tracing-tools`; `upload-release` `needs`/`if`; flatten filter fix |
| **Modify** | `versions.json` — `"potrace": "1.16"`, `"vtracer": "1.0.0-alpha.4"` |
| **Modify** | `README.md` — tool table (`:31`), platform table (`:52`), `tool_id` list (`:64`) |
| **Modify** | `DEV_Status.md` — matrix rows (`:30`), legend/build-notes rows |

## 1. Pins (env block, `populate.yml:39-40` on `main`, directly under `BENTO4_VERSION`)

```yaml
env:
  BENTO4_VERSION: "1-6-0-641"
  # Vector tracing tools for MeedyaConverter (#473 / #494, DR-0001). PINNED on
  # purpose: MeedyaConverter's argument builders are coupled to each tool's
  # exact CLI flag set, so a bump is a deliberate PR here plus a builder+test
  # change there — never an automatic upstream follow. Both are compiled from
  # source on every platform; potrace (GPL-2.0-or-later) additionally has its
  # exact source tarball archived next to the binaries (corresponding source).
  POTRACE_VERSION: "1.16"
  VTRACER_VERSION: "1.0.0-alpha.4"
```

`versions.json` (flat `{tool_id: version}` map — there are no platform/SHA fields; SHA lives only in the release's `SHA256SUMS`): append

```json
  "potrace": "1.16",
  "vtracer": "1.0.0-alpha.4"
```

## 2. `check-versions` job edits

1. `outputs:` (`:51-70`): add `potrace: ${{ steps.check.outputs.potrace }}` and `vtracer: ${{ steps.check.outputs.vtracer }}`.
2. Force list (`:85-86`): append `potrace vtracer` to the `for tool in …` list so push/dispatch/PR runs build them.
3. Pinned compare — insert after the mp4decrypt block (`:181-190`), same shape:
```bash
          # potrace / vtracer: pinned versions — compare against workflow env vars
          for pin in "potrace=${{ env.POTRACE_VERSION }}" "vtracer=${{ env.VTRACER_VERSION }}"; do
            key="${pin%%=*}"; want="${pin#*=}"
            cur=$(echo "$VERSIONS" | jq -r ".\"$key\" // \"\"")
            if [ "$cur" != "$want" ] || [ -z "$cur" ]; then
              echo "${key}=true" >> "$GITHUB_OUTPUT"
              echo "→ $key: CHANGED ($cur → $want)"
              ANY_BINARY="true"
            else
              echo "${key}=false" >> "$GITHUB_OUTPUT"
              echo "→ $key: unchanged ($cur)"
            fi
          done
```
`ANY_BINARY=true` feeds `any_changed` (`:221-228`) so `upload-release` runs.
4. `Write updated versions.json` Python block (`:290-306`): add `versions["potrace"] = "${{ env.POTRACE_VERSION }}"` and `versions["vtracer"] = "${{ env.VTRACER_VERSION }}"` after the `mp4decrypt` line — otherwise the next scheduled run **drops the keys** when it rewrites `versions.json` (`:1544-1566`).

## 3. New job `build-tracing-tools` (insert between `build-python-tools` and `upload-release`, i.e. before `:1417`)

Shape decision: a **dedicated job with its own 3-leg matrix**, not extra steps in `build-python-tools` (that job is gated on `python_tools == 'true'`, `:1262-1265`, which would skip our tools on a scheduled run where only a pin changed). macOS produces **two thin per-arch tarballs, no lipo** — matching how ffmpeg is published today (`README.md:56-66` naming; PR #20 ships per-arch tarballs; no `lipo` exists in the mirror) — and MeedyaConverter's bundle script lipo-combines them, exactly as `bundle-ffmpeg.sh:120-148` does. Only first-party `actions/*` are used (the repo uses no third-party actions; rustup is preinstalled on all three runner images).

```yaml
  # =====================================================================
  # Job 2b: Vector tracing tools for MeedyaConverter (#473 / #494)
  #   potrace  — C/autotools, GPL-2.0-or-later, source tarball ARCHIVED
  #   vtracer  — Rust/cargo, MIT OR Apache-2.0
  # Compiled FROM SOURCE on every platform (DR-0001 provenance rule); macOS
  # ships two thin per-arch tarballs (the consumer lipo-combines them, as it
  # does for ffmpeg). Versions are pinned in env (see POTRACE_VERSION).
  # =====================================================================
  build-tracing-tools:
    needs: [check-versions]
    if: >-
      (needs.check-versions.outputs.potrace == 'true' ||
       needs.check-versions.outputs.vtracer == 'true') &&
      (github.event_name != 'pull_request' ||
      contains(github.event.pull_request.labels.*.name, 'update-tools'))
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-latest
            platform: linux
            arch: x86_64
          - os: ubuntu-24.04-arm
            platform: linux
            arch: aarch64
          - os: macos-latest
            platform: macos
            arch: aarch64      # host arch; this leg ALSO cross-builds x86_64
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v7

      - name: Create staging directories
        run: mkdir -p staging work

      # ---------------- potrace ----------------
      - name: "potrace: fetch source (+ archive corresponding source, GPL)"
        if: needs.check-versions.outputs.potrace == 'true'
        continue-on-error: true
        run: |
          set -euo pipefail
          VER="${POTRACE_VERSION}"
          curl -fL --retry 3 -o "work/potrace-${VER}.tar.gz" \
            "https://potrace.sourceforge.net/download/${VER}/potrace-${VER}.tar.gz"
          # Corresponding source for the GPL binaries below. Published ONCE
          # (linux-x86_64 leg) so the flatten step does not race two copies.
          if [ "${{ matrix.platform }}-${{ matrix.arch }}" = "linux-x86_64" ]; then
            cp "work/potrace-${VER}.tar.gz" "staging/potrace-${VER}.src.tar.gz"
          fi

      - name: "potrace: Linux ${{ matrix.arch }} (compile from source)"
        if: needs.check-versions.outputs.potrace == 'true' && matrix.platform == 'linux'
        continue-on-error: true
        run: |
          set -euo pipefail
          VER="${POTRACE_VERSION}"
          rm -rf work/potrace-build && mkdir -p work/potrace-build
          tar -xzf "work/potrace-${VER}.tar.gz" -C work/potrace-build --strip-components=1
          cd work/potrace-build
          ./configure CFLAGS='-O2'
          make -j"$(nproc)"
          strip src/potrace
          cd ../..
          mkdir -p work/pkg
          cp work/potrace-build/src/potrace work/pkg/potrace
          cp work/potrace-build/COPYING   work/pkg/COPYING
          chmod +x work/pkg/potrace
          work/pkg/potrace --version | head -1 | grep -q "${VER}"
          tar -czf "staging/potrace-linux-${{ matrix.arch }}.tar.gz" -C work/pkg potrace COPYING
          rm -rf work/pkg work/potrace-build
          echo "✓ potrace-linux-${{ matrix.arch }}.tar.gz"

      - name: "potrace: macOS arm64 + x86_64 (compile from source, two thin binaries)"
        if: needs.check-versions.outputs.potrace == 'true' && matrix.platform == 'macos'
        continue-on-error: true
        run: |
          set -euo pipefail
          VER="${POTRACE_VERSION}"
          # potrace 1.16 (2019) ships a config.sub/config.guess that predate
          # Apple Silicon; regenerate them (autoreconf -fi copies fresh ones).
          brew install autoconf automake libtool >/dev/null
          build_arch() {   # $1 clang arch (arm64|x86_64)   $2 asset arch (aarch64|x86_64)   $3 --host or ""
            local carch="$1" aarch="$2" host="$3"
            rm -rf "work/potrace-${carch}" && mkdir -p "work/potrace-${carch}"
            tar -xzf "work/potrace-${VER}.tar.gz" -C "work/potrace-${carch}" --strip-components=1
            ( cd "work/potrace-${carch}" \
              && autoreconf -fi \
              && ./configure ${host} CC="clang -arch ${carch}" CFLAGS='-O2 -mmacosx-version-min=13.0' \
              && make -j"$(sysctl -n hw.ncpu)" \
              && strip src/potrace )
            lipo -archs "work/potrace-${carch}/src/potrace" | grep -q "${carch}"
            mkdir -p work/pkg
            cp "work/potrace-${carch}/src/potrace" work/pkg/potrace
            cp "work/potrace-${carch}/COPYING"     work/pkg/COPYING
            chmod +x work/pkg/potrace
            tar -czf "staging/potrace-macos-${aarch}.tar.gz" -C work/pkg potrace COPYING
            rm -rf work/pkg
            echo "✓ potrace-macos-${aarch}.tar.gz"
          }
          build_arch arm64  aarch64 ""
          build_arch x86_64 x86_64  "--host=x86_64-apple-darwin"
          # Only the host-arch binary is runnable here; smoke it.
          "work/potrace-arm64/src/potrace" --version | head -1 | grep -q "${VER}"

      # ---------------- vtracer ----------------
      - name: "vtracer: fetch pinned source"
        if: needs.check-versions.outputs.vtracer == 'true'
        continue-on-error: true
        run: |
          set -euo pipefail
          VER="${VTRACER_VERSION}"
          curl -fL --retry 3 -o "work/vtracer-${VER}.tar.gz" \
            "https://github.com/visioncortex/vtracer/archive/refs/tags/${VER}.tar.gz"
          # Not a GPL obligation (MIT OR Apache-2.0) — archived for the same
          # provenance reason as every other from-source build here.
          if [ "${{ matrix.platform }}-${{ matrix.arch }}" = "linux-x86_64" ]; then
            cp "work/vtracer-${VER}.tar.gz" "staging/vtracer-${VER}.src.tar.gz"
          fi
          rm -rf work/vtracer-src && mkdir -p work/vtracer-src
          tar -xzf "work/vtracer-${VER}.tar.gz" -C work/vtracer-src --strip-components=1
          rustup update stable >/dev/null && rustup default stable
          rustc --version   # edition 2024 crate → needs rustc >= 1.85

      - name: "vtracer: Linux ${{ matrix.arch }} (cargo, static musl)"
        if: needs.check-versions.outputs.vtracer == 'true' && matrix.platform == 'linux'
        continue-on-error: true
        run: |
          set -euo pipefail
          VER="${VTRACER_VERSION}"
          case "${{ matrix.arch }}" in
            x86_64)  TARGET=x86_64-unknown-linux-musl ;;
            aarch64) TARGET=aarch64-unknown-linux-musl ;;
          esac
          sudo apt-get install -y musl-tools
          rustup target add "${TARGET}"
          ( cd work/vtracer-src && cargo build --release --locked -p vtracer-cli --target "${TARGET}" )
          mkdir -p work/pkg
          cp "work/vtracer-src/target/${TARGET}/release/vtracer" work/pkg/vtracer
          cp work/vtracer-src/LICENSE work/pkg/LICENSE
          strip work/pkg/vtracer && chmod +x work/pkg/vtracer
          # Flag tripwire: MeedyaConverter's builder depends on exactly these.
          HELP="$(work/pkg/vtracer --help)"
          for f in --input --output --mode --filter-speckle --color-precision --gradient-step --max-colors --clustering; do
            echo "$HELP" | grep -q -- "$f" || { echo "::error::vtracer ${VER} --help lacks ${f}"; exit 1; }
          done
          tar -czf "staging/vtracer-linux-${{ matrix.arch }}.tar.gz" -C work/pkg vtracer LICENSE
          rm -rf work/pkg
          echo "✓ vtracer-linux-${{ matrix.arch }}.tar.gz"

      - name: "vtracer: macOS arm64 + x86_64 (cargo, two thin binaries)"
        if: needs.check-versions.outputs.vtracer == 'true' && matrix.platform == 'macos'
        continue-on-error: true
        run: |
          set -euo pipefail
          VER="${VTRACER_VERSION}"
          rustup target add x86_64-apple-darwin
          build_target() {   # $1 rust target   $2 asset arch
            local target="$1" aarch="$2"
            ( cd work/vtracer-src && cargo build --release --locked -p vtracer-cli --target "${target}" )
            mkdir -p work/pkg
            cp "work/vtracer-src/target/${target}/release/vtracer" work/pkg/vtracer
            cp work/vtracer-src/LICENSE work/pkg/LICENSE
            strip work/pkg/vtracer && chmod +x work/pkg/vtracer
            tar -czf "staging/vtracer-macos-${aarch}.tar.gz" -C work/pkg vtracer LICENSE
            rm -rf work/pkg
            echo "✓ vtracer-macos-${aarch}.tar.gz"
          }
          build_target aarch64-apple-darwin aarch64
          build_target x86_64-apple-darwin  x86_64
          HELP="$(work/vtracer-src/target/aarch64-apple-darwin/release/vtracer --help)"
          for f in --input --output --mode --filter-speckle --color-precision --gradient-step --max-colors --clustering; do
            echo "$HELP" | grep -q -- "$f" || { echo "::error::vtracer ${VER} --help lacks ${f}"; exit 1; }
          done

      - name: List produced assets
        run: ls -lh staging/ 2>/dev/null || echo "No assets produced"

      - uses: actions/upload-artifact@v7
        with:
          name: tracing-tools-${{ matrix.platform }}-${{ matrix.arch }}
          path: staging/
          retention-days: 1
          if-no-files-found: warn
```

Notes for the implementer:
- `continue-on-error: true` follows every other tool step in this workflow (a broken potrace build must not block the daily ffmpeg/yt-dlp mirror). The consequence is that a failed leg is a **warning annotation, not a red job**: on the labelled PR run, open the macOS leg's "List produced assets" output and confirm all four macOS tarballs exist before merging. MeedyaConverter's bundle script fails closed if any is missing (exit 6).
- potrace links zlib dynamically from the OS (default configure; libz is part of macOS and every glibc distro) — same posture as the aria2c/ddrescue precedents. Do **not** patch potrace or link `libpotrace` into anything (DR-0001 consequence #1).
- If `autoreconf -fi` fails on the first macOS run (uncertain — potrace 1.16 is autotools but its bundled `config.sub` predates arm64), fall back to overwriting `config.sub`/`config.guess` from `automake --print-libdir`'s copies; report which path worked in the PR.
- The `--help` tripwire is the flag-drift guard: if a future pin bump renames a flag, the mirror build fails before MeedyaConverter ever sees a binary that would break `buildVTracerArguments`.

## 4. `upload-release` job (`:1417-1428`)

```yaml
    needs: [check-versions, download-binaries, build-python-tools, build-tracing-tools]
    if: >-
      always() &&
      github.event_name != 'pull_request' &&
      needs.check-versions.outputs.any_changed == 'true' &&
      (needs.download-binaries.result == 'success' || needs.download-binaries.result == 'skipped') &&
      (needs.build-python-tools.result == 'success' || needs.build-python-tools.result == 'skipped') &&
      (needs.build-tracing-tools.result == 'success' || needs.build-tracing-tools.result == 'skipped') &&
      (needs.download-binaries.result == 'success' || needs.build-python-tools.result == 'success' || needs.build-tracing-tools.result == 'success')
```
`actions/download-artifact@v8` with `path: all-assets` (`:1447-1451`) already downloads every artifact, so the new `tracing-tools-*` artifacts flow into flatten → `SHA256SUMS` (`:1464-1479`, automatic — it hashes everything in `staging/`) → both releases. No other change.

## 5. Flatten filter fix (`:1456`)

```bash
          find all-assets -type f \( -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.tar.lz" \
                                     -o -name "*.tar.bz2" -o -name "*.zip" -o -name "*.exe" \) \
            -exec cp {} staging/ \; 2>/dev/null || true
```
This is the PR #25 silent-drop bug (`ddrescue-1.28.src.tar.lz` never reaches a release). potrace's `.src.tar.gz` would pass the old filter by accident; fix the mechanism so the source-archival obligation does not depend on an upstream's choice of compressor.

## 6. README / DEV_Status rows

`README.md`: after `:31` add `| **potrace** | Bitmap → vector tracing (outline / monochrome) | [potrace.sourceforge.net](https://potrace.sourceforge.net/) | GPL v2+ |` and `| **VTracer** | Raster → SVG colour tracing | [visioncortex/vtracer](https://github.com/visioncortex/vtracer) | MIT / Apache-2.0 |`; platform table after `:52`: `| potrace | Y* | Y* | — | — | — | Y* |` and `| VTracer | Y* | Y* | — | — | — | Y* |` (add a `macOS x86_64` column note or a footnote that macOS ships both arches as separate assets — the current table only has a "macOS ARM" column); `:64` `tool_id` list: append `potrace`, `vtracer`. `DEV_Status.md`: rows after `:30` using `OK*` (= "Compiled from source in CI", legend `:35`), and a Build Notes row: "potrace/vtracer (macOS): compiled on `macos-latest`; x86_64 cross-built from the arm64 host; two thin assets, lipo'd by the consumer". Do **not** write "universal binary" anywhere in this repo — none is produced here.

## 7. Release assets MeedyaConverter will consume (exact names)

| Asset | Contents (tar root) | Consumer |
|---|---|---|
| `potrace-macos-aarch64.tar.gz` | `potrace`, `COPYING` | `bundle-tracing-tools.sh` (lipo input) |
| `potrace-macos-x86_64.tar.gz` | `potrace`, `COPYING` | same |
| `vtracer-macos-aarch64.tar.gz` | `vtracer`, `LICENSE` | same |
| `vtracer-macos-x86_64.tar.gz` | `vtracer`, `LICENSE` | same |
| `potrace-1.16.src.tar.gz` | upstream tarball, byte-identical | the written source offer points here |
| `vtracer-1.0.0-alpha.4.src.tar.gz` | GitHub tag archive | provenance only |
| `potrace-linux-{x86_64,aarch64}.tar.gz`, `vtracer-linux-{x86_64,aarch64}.tar.gz` | binary + licence | parity with DR-0001's macOS+Linux scope; not consumed this round |
| `SHA256SUMS` | covers all of the above | verification root (F-011) |

## Part 1 verification

1. `actionlint .github/workflows/populate.yml` clean.
2. Open PR, apply label `update-tools`, watch `gh run watch`; in job `build-tracing-tools` confirm the six macOS/Linux tarballs + two `.src.tar.gz` in each leg's "List produced assets". A `::error::` from the `--help` tripwire is a hard stop.
3. Merge → `gh run watch` on the `main` push → `gh release view <YYYY-MM-DD[.N]> --repo MeedyaSuite/MeedyaDL-Tools --json assets --jq '.assets[].name' | grep -E '^(potrace|vtracer)-'` shows all eight, and `SHA256SUMS` lists them. **Record that tag** — it is Part 2's `MDLT_TAG`.

---

# PART 2 — MeedyaConverter changes (gated on Part 1's release existing)

## Files

| Action | Path |
|---|---|
| **Create** | `scripts/bundle-tracing-tools.sh` — fetch/verify/lipo potrace + vtracer from the mirror; stage licence texts + written source offer |
| **Modify** | `scripts/verify-no-gpl-in-appstore.sh:45-53` — add `potrace` to `GPL_BINARIES` (NOT vtracer) |
| **Modify** | `.github/workflows/release.yml` — new step after "Bundle FFmpeg + HDR tools" (`:433-444`), before "Sign app bundle" (`:452`) |
| **Modify** | `Sources/ConverterEngine/Utilities/ToolBundleManifest.swift` — vtracer into `defaultManifest`; new `directOnlyManifest` (potrace) + `activeManifest` gated `#if APP_STORE` |
| **Create** | `Sources/ConverterEngine/Utilities/ExternalToolRunner.swift` — `ExternalToolRunning` seam + `ExternalToolRunner` (Process, no progress, cancellable) |
| **Create** | `Sources/ConverterEngine/FFmpeg/RasterVectorExecutor.swift` — raster→SVG orchestration, `VectorToolPaths`, `SVGFragmentExtractor` |
| **Create** | `Sources/ConverterEngine/FFmpeg/ProResVectorExecutor.swift` — frame dump → per-frame trace → SMIL assembly |
| **Modify** | `Sources/ConverterEngine/FFmpeg/RasterVectorConverter.swift` — vtracer builder rewrite (1.0.0-alpha.4 flags), ffmpeg pre-pass builder, header/doc/error-message truth fixes |
| **Modify** | `Sources/ConverterEngine/FFmpeg/ProResToVectorConverter.swift` — single `-vf` chain + `-fps_mode vfr`, SMIL wrapper semantics, header fix |
| **Modify** | `Sources/MeedyaConverter/ViewModels/AppViewModel.swift:166-181` — `unavailable` gated on `#if APP_STORE`; doc rewrite |
| **Modify** | `Sources/MeedyaConverter/Views/SidebarView.swift:67-77` — restore two rows; comment |
| **Modify** | `Sources/MeedyaConverter/Views/VectorConversionView.swift` — Source picker, tool detection, Convert/Cancel/progress, execution |
| **Modify** | `Sources/MeedyaConverter/Views/ProResVectorView.swift` — Source from `viewModel.selectedFile`, tool detection, staged progress, hide inert Assembly section, SMIL-only picker |
| **Modify** | `Sources/MeedyaConverter/Views/RasterToVectorConfigEditor.swift:128-136` — remove the two inert toggles ("Other" section) |
| **Modify** | `Sources/MeedyaConverter/Views/SettingsView.swift` (`PathSettingsTab`, `:512-560`) — `customPotracePath` / `customVTracerPath` override fields |
| **Modify** | `Tests/MeedyaConverterCoreTests/NavigationItemAvailabilityTests.swift` — flip pins, `#if APP_STORE` branch, header |
| **Modify** | `Tests/ConverterEngineTests/ConverterEngineTests+VectorConverters.swift` — flag assertions for the new builders |
| **Modify** | `Tests/ConverterEngineTests/ConverterEngineTests+ToolingAndMetadata.swift:21-31, 44-53` — count 7; direct-manifest tests |
| **Create** | `Tests/ConverterEngineTests/VectorExecutorTests.swift` — mock runner; executor/assembly/extractor/cancellation/locator tests |
| **Modify** | docs: `docs/decisions/0001-gpl-disc-tools.md` (amendment), `CHANGELOG.md`, `README.md:124`, `docs/distribution/rc4-known-limitations.md:17-19`, `Sources/MeedyaConverter/Resources/Help/vector-conversion.md`, `.claude/HANDOFF.md:223-228` |

Reference patterns (read, don't modify): `StabilizationView.swift:261-372` (NSSavePanel → Task → controller → cancel/onDisappear), `DiscImagingController.swift:462-524` (`runToCompletion`/`prepareProcess`: lock use kept out of async, terminationHandler→continuation, no `waitUntilExit`), `BundledToolLocator.swift:79,153` (construct + `locate()`), `DoviToolWrapper.swift:103` (locator with user override), `RawCDImagingExecutorTests.swift:459-524` (locator tests, `uniqueToolName()`), `ImageConversionView.swift:536-541` (NSOpenPanel for images), `AppViewModel.swift:542-547` (custom path → engine), `.claude/plans/storage-analysis-ffprobe-plan.md` (seam + `@Sendable` progress hop `Task { @MainActor in … }`).

**Ordering dependency (hard):** `scripts/bundle-tracing-tools.sh` pins `MDLT_TAG` to the Part 1 post-merge release. Until that tag exists, commit the script with `MDLT_TAG="<PENDING-MeedyaDL-Tools-release>"`; it then fails closed at the `SHA256SUMS` fetch (exit 6) — and since `build.yml` (the CI Build & Test gate) never runs bundle scripts, the whole Part 2 PR can be developed and CI-green **before** the pin, with the pin as the final commit. **Do not cut a release tag or merge to `main` while the placeholder is in place.** Keep this pin **separate** from `bundle-ffmpeg.sh`'s `MDLT_TAG` (`2026-07-05.3`): bumping the shared one would also silently refresh ffmpeg/ffprobe/ffplay to the newer mirror build.

## A. `scripts/bundle-tracing-tools.sh` (new)

Usage: `scripts/bundle-tracing-tools.sh <HELPERS_DIR> <LICENSES_DIR>`. Copy the skeleton of `bundle-ffmpeg.sh` verbatim — `set -euo pipefail`, `MDLT_REPO`/`MDLT_TAG`/`MDLT_BASE` (`:53-55`), fail-closed `SHA256SUMS` fetch (exit 6, `:67-71`), `expected_sha` (`:74-76`), `fetch_arch_binary` (`:81-115`, exit 7 on mismatch), `build_universal` (`:120-148`, exit 8 if not 2-arch) — with these differences:
- Header comment: name the origin (`bundle-ffmpeg.sh`), state that the duplication is deliberate (own pin; the ffmpeg pin must not move with this one), and list what it stages.
- `build_universal potrace 1` and `build_universal vtracer 1` — both **required**. No optional tool.
- After each `fetch_arch_binary`, also copy the licence file from the extracted archive (the mirror tars `COPYING` next to `potrace` and `LICENSE` next to `vtracer`): `cp "$(dirname "${arm}")/COPYING" "${LICENSES_DIR}/potrace-COPYING.txt"`, `cp …/LICENSE "${LICENSES_DIR}/vtracer-LICENSE.txt"`; fail (exit 9) if a licence file is missing — DR-0001 consequence #2 is not optional.
- Write `${LICENSES_DIR}/SOURCE-OFFER-potrace.txt` (DR-0001 consequence #3), substituting `MDLT_TAG`:
  ```
  Written offer for corresponding source — potrace 1.16 (GPL-2.0-or-later)

  MeedyaConverter (Direct distribution) includes an unmodified potrace 1.16
  binary, invoked as a separate program. The complete corresponding source
  used to build it is published, with its SHA-256, at:
    https://github.com/MeedyaSuite/MeedyaDL-Tools/releases/download/<MDLT_TAG>/potrace-1.16.src.tar.gz
    https://github.com/MeedyaSuite/MeedyaDL-Tools/releases/download/<MDLT_TAG>/SHA256SUMS
  This offer is valid to any third party for at least three years from the
  build date of this copy, at no charge beyond the cost of distribution.
  MWBM Partners Ltd — <contact address to be confirmed by the maintainer>
  ```
  (Wording to be confirmed by the maintainer/legal before the first Direct release that carries potrace — flagged in Risks.)
- Post-stage smoke: `"${HELPERS_DIR}/potrace" --version | head -1` must contain `1.16`; `"${HELPERS_DIR}/vtracer" --help` must contain `--max-colors` (exit 5 otherwise) — the converter-side half of the flag tripwire.
- `LICENSES_DIR` = `Contents/Resources/Licenses` (see §B). `scripts/codesign.sh:186-187` signs only Mach-O under `Contents/Helpers`/`Contents/Resources`, so text files are inert and no codesign change is needed; the binaries get hardened runtime + timestamp + GUI entitlements automatically (`sign_nested_executables`).

## B. `release.yml` step (insert after `:444`, before `:446`)

```yaml
      # ---------------------------------------------------------------------
      # Step 9c: Bundle vector tracing tools (Direct only — #473 / #494)
      # ---------------------------------------------------------------------
      # potrace (GPL-2.0-or-later) + vtracer (MIT). Universal via lipo from the
      # mirror's per-arch builds, SHA-256 verified (F-011). Licence texts and
      # the potrace written source offer land in Contents/Resources/Licenses
      # (DR-0001 consequences 2–3). This step exists ONLY here: testflight.yml
      # must never gain it (verify-no-gpl-in-appstore.sh is its tripwire).
      # ---------------------------------------------------------------------
      - name: Bundle vector tracing tools
        run: |
          APP_BUNDLE="MeedyaConverter.app"
          chmod +x scripts/bundle-tracing-tools.sh
          ./scripts/bundle-tracing-tools.sh \
            "${APP_BUNDLE}/Contents/Helpers" \
            "${APP_BUNDLE}/Contents/Resources/Licenses"
          ls -la "${APP_BUNDLE}/Contents/Helpers" "${APP_BUNDLE}/Contents/Resources/Licenses"
```
`dev-build.yml`: **no change** (scope decision, stated in the PR): it bundles no helpers at all today (zero `Helpers`/`ffmpeg` references); dev builds resolve every tool via PATH/Homebrew and the views' detect-and-disable caption says so. `testflight.yml`: no change; its `:331` tripwire now also catches `potrace` because of §C.1.

## C. Engine changes

### C.1 `scripts/verify-no-gpl-in-appstore.sh:45-53`
Add `potrace` to `GPL_BINARIES` (after `cd-paranoia`) and extend the comment at `:42-44`: "…and `potrace` (#473 vector tracing). vtracer is MIT and deliberately NOT listed." Run `./scripts/verify-no-gpl-in-appstore.sh <any .app containing a file named potrace>` locally to see exit 7.

### C.2 `ToolBundleManifest.swift`
1. Append to `defaultManifest.tools` (`:165-174` after `subtitle_tonemap`):
```swift
            BundledTool(
                id: "vtracer",
                name: "VTracer",
                version: "1.0.0-alpha.4",
                sourceURL: "https://github.com/visioncortex/vtracer",
                lastUpdated: "<staging date>",
                binaryName: "vtracer",
                description: "Raster → SVG colour tracing (colour-quantised and photorealistic modes)",
                // Upstream is dual-licensed "MIT OR Apache-2.0"; MIT is the LICENSE
                // file at the repo root. Not GPL-family → ships in every distribution.
                license: "MIT"
            ),
```
2. New section before `// MARK: - Lookup`:
```swift
    // MARK: - Direct-only manifest (issue #494 / DR-0001)

    /// GPL-family tools that ship ONLY in the Direct `.dmg`. Kept out of
    /// `defaultManifest` so `test_toolBundleManifest_defaultManifestIsAppStoreSafe`
    /// stays the tripwire it was designed to be. First occupant: potrace (#473).
    public static let directOnlyManifest = ToolBundleManifest(
        tools: [
            BundledTool(
                id: "potrace",
                name: "potrace",
                version: "1.16",
                sourceURL: "https://potrace.sourceforge.net/",
                lastUpdated: "<staging date>",
                binaryName: "potrace",
                description: "Bitmap → SVG outline / monochrome tracing (invoked as a separate process; never linked)",
                license: "GPL-2.0-or-later"
            ),
        ],
        schemaVersion: 1,
        generatedDate: "<staging date>"
    )

    /// The manifest describing what THIS build actually bundles. App Store
    /// builds (`-DAPP_STORE`, testflight.yml/dev-build.yml) get `defaultManifest`
    /// only; every other build also carries `directOnlyManifest`. `#if APP_STORE`
    /// is the gate because it is the only build-type flag the pipelines set —
    /// release.yml keeps `DIRECT` unset (Sparkle), see release.yml:264.
    public static var activeManifest: ToolBundleManifest {
        #if APP_STORE
        return defaultManifest
        #else
        return ToolBundleManifest(
            tools: defaultManifest.tools + directOnlyManifest.tools,
            schemaVersion: defaultManifest.schemaVersion,
            generatedDate: defaultManifest.generatedDate
        )
        #endif
    }
```
3. Fix the now-false prose at `:210-217` (`isAppStoreSafe` doc): replace "When the disc-imaging executor lands … belong in a Direct-only manifest or behind an `isDirectBuild` gate — not here" with "Direct-only GPL tools live in `directOnlyManifest`; `activeManifest` merges them except under `#if APP_STORE`. `verify-no-gpl-in-appstore.sh` is the second line of defence on the assembled bundle." `grep -rn "defaultManifest" Sources` shows **no runtime reader today** (verified) — nothing else to switch.

### C.3 `RasterVectorConverter.swift`
1. Header `:8-22` → rewrite: potrace + vtracer are executed by `RasterVectorExecutor` (Direct builds bundle both; #473). Drop the autotrace/Inkscape/librsvg claims — none is referenced anywhere. State plainly: `buildRsvgConvertArguments` remains an argument builder with **no executor** (vector→raster is out of scope; `rsvg-convert` is not bundled).
2. `RasterVectorError` (`:28-49`): add `case toolFailed(tool: String, exitCode: Int32, stderr: String)` ("\(tool) exited with code N: <stderr.prefix(500)>") and `case outputMissing(String)`; change `.tracingToolNotFound` text to `"The '\(tool)' tracing tool was not found. The Direct build bundles it in Contents/Helpers; otherwise set its path in Settings › Paths."` (the current "Install via Homebrew" is wrong for a bundled tool).
3. **Rewrite `buildVTracerArguments` for vtracer 1.0.0-alpha.4** (keep `-i`/`-o` at positions 0–3 — they exist as short flags in 1.0):
```swift
        var args: [String] = [
            "-i", inputPath,
            "-o", outputPath,
            "--mode", vtracerCurveMode(for: config.tracingMode),                  // pixel|polygon|spline
            "--filter-speckle", String(min(128, max(0, Int(config.curveSimplification.rounded())))),
            "--color-precision", "8",
            "--gradient-step", "10",
        ]
        switch config.tracingMode {
        case .monochrome, .outline:
            args += ["--clustering", "bw"]
        case .colorQuantization, .photorealistic:
            args += ["--clustering", "color-cluster", "--max-colors", String(config.colorCount)]
        }
        return args
```
   Remove `--colormode`, `--segment_length <colorCount>` (semantically wrong knob; hidden in 1.0), `--no-alpha`, `--flatten`, `--preserve-metadata` (none exist). Doc comment: "Targets vtracer 1.0.0-alpha.4's kebab-case CLI (`crates/vtracer-cli/src/main.rs`); the mirror's build tripwire and `test_vtracerArguments_*` pin this flag set. Alpha is handled by the ffmpeg pre-pass, not here."
4. `buildPotraceArguments` (`:308-329`): unchanged flags are all valid (`-s`/`--svg` duplicate is harmless; `-t`, `-a`, `--opttolerance` valid per `potrace(1)`); add `"-r", "72"` so 1 px = 1 SVG user unit (needed for the ProRes assembly's `viewBox`), and doc: "`inputPath` MUST be BMP/PNM — potrace cannot read PNG; see `buildPrePassArguments`."
5. New builder (pure, tested) — the ffmpeg normalisation pre-pass that every trace goes through (so supported input = ffmpeg's decoders, which is what `RasterFormat`'s doc at `:53-55` already claims):
```swift
    /// ffmpeg arguments that normalise ANY supported raster (first frame only)
    /// into the one format the chosen tracer can read, applying `config.alpha`:
    ///   potrace → 8-bit greyscale BMP (potrace thresholds it; reads no PNG)
    ///   vtracer → PNG, RGBA when alpha is kept, RGB24 when discarded/flattened
    public static func buildPrePassArguments(
        inputPath: String, intermediatePath: String, config: RasterToVectorConfig, tool: String
    ) -> [String] {
        let flatten = "[0:v]format=rgba,split=2[fg][bg];[bg]drawbox=color=white:t=fill[w];[w][fg]overlay=format=auto"
        var args = ["-y", "-i", inputPath, "-frames:v", "1"]
        switch (tool, config.alpha) {
        case ("potrace", .discard):
            args += ["-vf", "format=gray"]
        case ("potrace", _):
            args += ["-filter_complex", flatten + ",format=gray[out]", "-map", "[out]"]
        case (_, .flatten):
            args += ["-filter_complex", flatten + ",format=rgb24[out]", "-map", "[out]"]
        case (_, .discard):
            args += ["-vf", "format=rgb24"]
        case (_, .clipPathWithOpacity):
            args += ["-vf", "format=rgba"]
        }
        args += tool == "potrace" ? ["-c:v", "bmp"] : ["-c:v", "png"]
        args.append(intermediatePath)
        return args
    }
```
   The filter graphs are deterministic strings; **their behaviour on real ffmpeg is verified only on the manual matrix** (CI never runs ffmpeg on images) — say so in the doc comment.
6. **Truth fixes** on config docs: `AlphaStrategy` (`:167-177`) — `.clipPathWithOpacity` currently promises clip-path synthesis; rewrite each case to what the executor does (kept as RGBA for vtracer's native handling / composited on white for potrace; flatten = white composite; discard = alpha dropped). `preserveMetadata` (`:205-206`) and `ocrTextRegions` (`:207-209`) → "Reserved — **not applied** by `RasterVectorExecutor`; no bundled tool implements it. Kept for JSON/AppStorage compatibility." `animation` (`:204`) → "Reserved for raster inputs — `RasterVectorExecutor` traces the first frame only; animated raster → animated SVG is not implemented (#376 follow-up)."

### C.4 `ProResToVectorConverter.swift`
1. Header `:20-21` → "Execution lives in `ProResVectorExecutor` (#473)."
2. `buildFrameExtractionArguments` `:201-219` — one filter chain, stride-aware rate:
```swift
        var filters: [String] = []
        if config.frameStride > 1 { filters.append("select=not(mod(n\\,\(config.frameStride)))") }
        if config.sourceVariant.requiresTonemapping {
            filters.append("zscale=t=linear:npl=100,tonemap=hable,zscale=t=bt709:m=bt709:r=tv")
        }
        filters.append(alphaFilter(for: config.alphaHandling))   // see 3.
        args += ["-vf", filters.joined(separator: ",")]
        if config.frameStride > 1 {
            args += ["-fps_mode", "vfr"]          // keep only the selected frames
        } else {
            args += ["-r", String(format: "%.6f", config.frameRate.doubleValue)]
        }
        args += ["-vcodec", "png", "-pix_fmt", config.alphaHandling == .preservePerFrame ? "rgba" : "rgb24", framePatternPath]
```
   (`select` before tonemap so dropped frames are not tonemapped; `-fps_mode` is the modern spelling of `-vsync`, present in the mirror's current ffmpeg.)
3. New `private static func alphaFilter(for:)`: `.preservePerFrame` → `"format=rgba"`; `.flatten` → the same white-composite graph as C.3.5 followed by `format=rgb24` (as a `-vf` this needs the two-input overlay → use `-filter_complex` + `-map "[out]"` exactly as in C.3.5; share the string via an `internal static let whiteCompositeGraph` in `RasterVectorConverter`); `.alphaMatteOnly` → `"alphaextract,format=gray"` and the executor forces **potrace** for this mode (a matte is monochrome by definition).
4. `buildSMILFrameWrapper` (`:275-290`): the current `<animate … fill="freeze">` leaves every earlier frame at opacity 1, so alpha frames stack visibly. Replace the inner element with
   `<set attributeName="opacity" to="1" begin="\(begin)s" dur="\(durPerFrame)s" fill="remove"/>` — visible only in its own slot — and update `test_smilFrameWrapper_hasCorrectTiming` (`+VectorConverters.swift:254-263`) to assert `fill="remove"` and `dur="0.041667s"`.
5. Add `public static let svgClosingTag = "</svg>"` and `public static let frameClosingTag = "</g>"` (used by the assembler; keeps templates in one file).

### C.5 `ExternalToolRunner.swift` (new, `Sources/ConverterEngine/Utilities/`)
```swift
public struct ExternalToolResult: Sendable { public let exitCode: Int32; public let stderr: String }

public enum ExternalToolError: LocalizedError, Sendable {
    case launchFailed(binaryPath: String, reason: String)
}

/// Seam: "run this binary with these arguments to completion". The tracers print
/// no machine-readable progress, so there is no stream — just an exit status and
/// captured stderr. `ExternalToolRunner` is production; tests inject a mock.
public protocol ExternalToolRunning: Sendable {
    func run(binaryPath: String, arguments: [String]) async throws -> ExternalToolResult
}

public final class ExternalToolRunner: ExternalToolRunning, Sendable {
    public init() {}
    public func run(binaryPath: String, arguments: [String]) async throws -> ExternalToolResult
}
```
Implementation rules (mirror `DiscImagingController.runToCompletion`/`prepareProcess`, `:462-509`): build the `Process` (stdout → `FileHandle.nullDevice`, stdin → `nullDevice`, stderr → `Pipe` with `readabilityHandler` appending to a buffer capped at 10 MiB via a copy of `trimBufferIfNeeded`) inside a small `final class ProcessBox: @unchecked Sendable` whose `NSLock` use stays in **synchronous** helpers (Swift 6 forbids `lock()`/`unlock()` in async contexts). Await the exit through `withTaskCancellationHandler(operation:onCancel:)` wrapping `withCheckedThrowingContinuation`; `terminationHandler` nils the readability handler and resumes with the status; `onCancel` calls `box.terminate()` (`SIGCONT` then `terminate()` — same as `stopImaging()` `:352-354`). After resumption, `if Task.isCancelled { throw CancellationError() }`. `proc.run()` failure → `ExternalToolError.launchFailed`. **No `waitUntilExit`.** Doc the honest boundary: "Launches a real subprocess; CI never runs potrace/vtracer — executor behaviour with the real tools is verified on the manual matrix only."

### C.6 `RasterVectorExecutor.swift` (new)
```swift
public struct VectorToolPaths: Sendable {
    public var ffmpeg: String
    public var potrace: String?
    public var vtracer: String?
    public init(ffmpeg: String, potrace: String? = nil, vtracer: String? = nil)
    /// The resolved path for `tool` ("potrace"/"vtracer"), or nil.
    public func path(for tool: String) -> String?
}

public enum RasterVectorExecutor: Sendable {
    /// Trace one raster into `outputURL` (SVG). Throws `RasterVectorError`.
    public static func convert(inputURL: URL, outputURL: URL, config: RasterToVectorConfig,
                               tools: VectorToolPaths, runner: any ExternalToolRunning) async throws
    /// Shared with ProResVectorExecutor: pre-pass + trace of one raster file.
    static func traceOne(inputPath: String, outputPath: String, config: RasterToVectorConfig,
                         tool: String, tools: VectorToolPaths, runner: any ExternalToolRunning,
                         workDirectory: URL) async throws
}

/// Pure: the inner content of an SVG document (between the opening `<svg …>`
/// and the final `</svg>`), or nil if either tag is absent. Handles the XML
/// prolog/DOCTYPE potrace emits and the bare root vtracer emits.
public enum SVGFragmentExtractor { public static func body(of svg: String) -> String? }
```
`convert` steps, in order: `RasterVectorConverter.validate` → `let tool = preferredTracingTool(for: config.tracingMode)` → `guard let toolPath = tools.path(for: tool) else { throw .tracingToolNotFound(tool) }` → temp dir `meedya-vector-<UUID>` under `FileManager.default.temporaryDirectory` (removed in a `defer`) → `traceOne` → `guard fileExists(outputURL.path) else throw .outputMissing(...)`. `traceOne`: intermediate `frame.<bmp|png>` → `runner.run(ffmpeg, buildPrePassArguments(...))`, non-zero → `.toolFailed(tool: "ffmpeg", …)` → `try Task.checkCancellation()` → `runner.run(toolPath, tool == "potrace" ? buildPotraceArguments(...) : buildVTracerArguments(...))`, non-zero → `.toolFailed`. `SVGFragmentExtractor.body`: locate the first `"<svg"`, then the next `">"` after it (return `""` if that tag ends with `"/>"`), then the **last** `"</svg>"`; return the trimmed substring between.

### C.7 `ProResVectorExecutor.swift` (new)
```swift
public struct ProResVectorProgress: Sendable {
    public enum Stage: Sendable, Equatable { case extractingFrames, tracing(frame: Int, of: Int), assembling }
    public let stage: Stage
    public let fraction: Double     // overall 0…1: extract 0–0.15, tracing 0.15–0.95, assembly 0.95–1
}

public enum ProResVectorExecutor: Sendable {
    public static func convert(inputURL: URL, outputURL: URL, sourceWidth: Int, sourceHeight: Int,
                               config: ProResToVectorConfig, tools: VectorToolPaths,
                               runner: any ExternalToolRunning,
                               progress: (@Sendable (ProResVectorProgress) -> Void)? = nil) async throws -> Int
    /// Pure assembly (tested without tools): root + per-frame wrapper + body + closers.
    public static func assembleAnimatedSVG(frameBodies: [String], widthPixels: Int, heightPixels: Int,
                                           frameRate: Double, method: AnimationMethod) throws -> String
}
```
`convert`: `guard config.animation == .smil else { throw RasterVectorError.invalidConfiguration("Only SMIL animation is implemented in this build") }` (the GUI picker offers only `.smil`, see §E; the check is for API callers) → work dir → `runner.run(ffmpeg, buildFrameExtractionArguments(…framePatternPath: work/frame_%06d.png…))` → list `frame_*.png` sorted; empty → `.operationFailed("ffmpeg extracted no frames")` → per frame: derive the tracing config (`var tracing = config.tracing; tracing.inputFormat = .png; tracing.alpha = {preservePerFrame→.clipPathWithOpacity, flatten→.flatten, alphaMatteOnly→.discard}`), tool = `.alphaMatteOnly ? "potrace" : preferredTracingTool(for: tracing.tracingMode)` (resolve once, before the loop, so a missing tool fails before any frame is dumped), `try Task.checkCancellation()`, `traceOne`, read the frame SVG, `SVGFragmentExtractor.body` (nil → `.operationFailed("frame N produced no SVG body")`), `progress?(…)` → `assembleAnimatedSVG` → `write(to: outputURL, atomically: true, encoding: .utf8)` → return frame count. `assembleAnimatedSVG` (SMIL): `buildSVGAnimationRoot(...)` + `"\n"` + for each frame `buildSMILFrameWrapper(frameIndex:frameCount:frameRate:)` + body + `frameClosingTag` + `svgClosingTag`; other methods throw the same `.invalidConfiguration`. Frame bodies from potrace carry their own `<g transform="translate(0,H) scale(0.1,-0.1)">` in pt units — with `-r 72` (C.3.4) 1 pt = 1 px, so they land correctly inside the pixel `viewBox`.

## D. Navigation / gating

`AppViewModel.swift:166-178`:
```swift
    /// Features whose UI exists but that cannot function in the shipped build …
    ///
    /// - `.vectorConversion` / `.proresVector` are hidden ONLY in App Store
    ///   builds (`-DAPP_STORE`, testflight.yml / dev-build.yml): the sandbox
    ///   cannot spawn potrace/vtracer/ffmpeg and potrace is GPL (DR-0001 #5).
    ///   In every other build they are visible; inside the view the Convert
    ///   button is disabled with a reason when a required tool is not found.
    /// - `.cloudSync`: … (unchanged)
    #if APP_STORE
    static let unavailable: Set<NavigationItem> = [.vectorConversion, .proresVector, .cloudSync]
    #else
    static let unavailable: Set<NavigationItem> = [.cloudSync]
    #endif
```
(The old doc's "the tracing tools … are GPL" was false for vtracer/rsvg — remove it.) `SidebarView.swift:67-77`: add `sidebarLabel(for: .vectorConversion)` and `sidebarLabel(for: .proresVector)` after `.images`, wrapped in `if NavigationItem.vectorConversion.isAvailable { … }` so the hardcoded list and the set cannot disagree; replace the comment at `:67-70` with "Vector Conversion / ProRes-to-Vector are App-Store-hidden (see `NavigationItem.unavailable`)". `ContentView.swift:122-125` already routes both — no change. `selectedNavItem` `didSet` (`:302-308`) — no change.

## E. Views

**Shared additions** (both views): `@AppStorage("customPotracePath") private var customPotracePath = ""`, `@AppStorage("customVTracerPath") private var customVTracerPath = ""`; `@State private var toolPaths: VectorToolPaths?`, `@State private var toolLookupError: String?`, `@State private var isConverting = false`, `@State private var convertTask: Task<Void, Never>?`, `@State private var statusMessage: String?`, `@State private var errorMessage: String?`. Resolution (`.task` on appear, and `.onChange` of the two override keys and of the tracing mode):
```swift
    private func resolveTools() async {
        let bundleManager = viewModel.engine.bundleManager          // honours the Settings ffmpeg override
        let potraceOverride = customPotracePath.isEmpty ? nil : customPotracePath
        let vtracerOverride = customVTracerPath.isEmpty ? nil : customVTracerPath
        let resolved: VectorToolPaths? = await Task.detached {
            guard let ffmpeg = try? bundleManager.locateFFmpeg().path else { return nil }
            return VectorToolPaths(
                ffmpeg: ffmpeg,
                potrace: try? BundledToolLocator(toolName: "potrace", userOverridePath: potraceOverride).locate(),
                vtracer: try? BundledToolLocator(toolName: "vtracer", userOverridePath: vtracerOverride).locate()
            )
        }.value
        toolPaths = resolved
    }
```
Caption logic (`toolStatusCaption`): ffmpeg missing → "FFmpeg was not found — set its path in Settings › Paths."; required tracer missing → "\(tool) was not found. The Direct build bundles it in Contents/Helpers; a dev/Homebrew build needs it on PATH or a path in Settings › Paths."; else "Tracing with \(tool) at \(path)" (secondary). Convert button `.disabled(source == nil || requiredToolPath == nil || isConverting)` — **never an enabled button that can only fail**. Cancel: `convertTask?.cancel()` (the runner's cancellation handler terminates the live process); `.onDisappear { cancel() }`. Progress hops from the `@Sendable` callback via `Task { @MainActor in self.progress = … }`. Log via `viewModel.appendLog(.info/.error, …, category: .encoding)`.

**`VectorConversionView.swift`**: replace the "Input" picker section (`:111-118`) with a "Source" section: `Button("Choose Image…")` → `NSOpenPanel` (`allowedContentTypes = [.image]`, single file; pattern `ImageConversionView.swift:536-541`) → `@State selectedImageURL: URL?`; show file name + detected format (`RasterFormat.from(fileExtension:)`; nil → caption "Unrecognised raster format" and Convert disabled). Delete the `vectorConversion.inputFormat` AppStorage (`:38-39`, `:57-63`) — it becomes dead; feed the editor `inputFormat: detectedFormat ?? .png`, `showAnimationSection: false` (animation is not implemented for raster — C.3.6). Run section (after the editor): Convert… → `NSSavePanel` (`allowedContentTypes = [.svg]`, name `<stem>.svg`) → `Task { await runConversion(...) }` → `RasterVectorExecutor.convert(inputURL:outputURL:config:tools:runner: ExternalToolRunner())`; while running: `ProgressView()` (indeterminate — the tracers print nothing) + "Tracing with \(tool)…" + Cancel; success/failure rows as `StabilizationView.statusRow`. Header comment `:8-13` → describe the real flow.

**`ProResVectorView.swift`**: add a "Source" row at the top of the Source section: `viewModel.selectedFile` (as `StabilizationView.sourceSection`, `:133-142`) — require `primaryVideoStream?.width/height` non-nil (else caption "Source has no video dimensions" and Convert disabled); the output-size warning (`:290-310`, `:327-334`) now uses the **real** `file.duration` when a file is selected, falling back to the synthetic reference otherwise (fix the comment at `:282-289`). Hide the "Assembly" section (`:268-280`) — `shapePersistence`/`keyframeExtraction` are not implemented by the executor; keep the AppStorage keys and add a comment saying why the section is gone. Animation picker (`:259-266`): offer `.smil` only (`ForEach([AnimationMethod.smil], …)`) with caption "CSS/hybrid/frame-sequence assembly are not implemented in this build." Run section: Convert… → `NSSavePanel` `.svg` → `ProResVectorExecutor.convert(... sourceWidth:sourceHeight: from the stream, progress: { p in Task { @MainActor in progress = p.fraction; stageLabel = label(for: p.stage) } })`; staged `ProgressView(value:)` + Cancel; result "Animated SVG (N frames) saved to …". Header comment `:8-24`: update layout list (Assembly removed; Run added).

**`RasterToVectorConfigEditor.swift:128-136`**: delete the "Other" section (both toggles are inert — C.3.6); update the header's section list (`:8-10`).

**`SettingsView.swift` `PathSettingsTab`**: after the FFmpeg section add `Section("Vector Tracing Tools")` with two `TextField`+`Browse…` rows for `customPotracePath` / `customVTracerPath` (`prompt: Text("Auto-detect")`, same `browseBinary()` helper, a11y labels "Custom potrace binary path"/"Custom vtracer binary path"). The keys are read by the views, not the engine (no `EncodingEngine` change).

## F. Tests

**`NavigationItemAvailabilityTests.swift`** — header `:6-11` → "…hidden only in App Store builds (`#if APP_STORE`); visible elsewhere now that `RasterVectorExecutor`/`ProResVectorExecutor` run the bundled tools (#473)". Replace `test_vectorToolsAreUnavailable` with:
```swift
    func test_vectorToolsAvailabilityFollowsBuildType() {
        #if APP_STORE
        XCTAssertFalse(NavigationItem.vectorConversion.isAvailable)
        XCTAssertFalse(NavigationItem.proresVector.isAvailable)
        #else
        XCTAssertTrue(NavigationItem.vectorConversion.isAvailable)
        XCTAssertTrue(NavigationItem.proresVector.isAvailable)
        #endif
        XCTAssertFalse(NavigationItem.cloudSync.isAvailable)
    }
```
Tests 24-42 unchanged.

**`+ToolingAndMetadata.swift`**: `:24` count → 7, add `XCTAssertNotNil(manifest.tool(id: "vtracer"))`; new `test_toolBundleManifest_directOnlyCarriesPotraceOnly` (`directOnlyManifest.gplTools.map(\.id) == ["potrace"]`, `tool(id: "potrace")?.isGPLFamily == true`, `defaultManifest.tool(id: "potrace") == nil`); `test_toolBundleManifest_activeManifestRespectsBuildType` (`#if APP_STORE` → `activeManifest.isAppStoreSafe`; else `activeManifest.tool(id: "potrace") != nil`). `test_toolBundleManifest_defaultManifestIsAppStoreSafe` stays and must still pass.

**`+VectorConverters.swift`**: `test_vtracerArguments_includeInputAndOutput` → keep positions 0–3; assert `--clustering` followed by `color-cluster` and `--max-colors` followed by `"32"` **via `firstIndex(of:)` + `[idx+1]`** (never `args.first`/fixed offsets for flags); `test_vtracerArguments_monochromeBinary` → `--clustering` then `bw`, and assert `!args.contains("--colormode")`, `!args.contains("--preserve-metadata")`, `!args.contains("--no-alpha")`, `!args.contains("--flatten")`; new `test_vtracerArguments_useKebabCaseFlags` (all flags in the emitted list match `^--[a-z-]+$|^-[io]$`); new `test_potraceArguments_includeResolution72`; new `test_prePassArguments_potraceProducesGrayBMP` / `_vtracerKeepsRGBA` / `_flattenUsesFilterComplex`; `test_proResFrameExtractionArguments_singleFilterChain` (exactly one `-vf` in the list; with `frameStride: 2` the chain contains both `select=` and `format=`, `-fps_mode` present, `-r` absent; with stride 1, `-r` present); update `test_smilFrameWrapper_hasCorrectTiming` per C.4.4.

**`VectorExecutorTests.swift`** (new; `import XCTest`, `import ConverterEngine`, house header). Before pushing: `grep -rhE "^(final class|class|struct|enum|actor) " Tests/ConverterEngineTests/ | sed -E 's/^(final class|class|struct|enum|actor) ([A-Za-z0-9_]+).*/\2/' | sort | uniq -d` must be empty (verified free today: `VectorExecutorTests`, `MockExternalToolRunner`). Mock:
```swift
final class MockExternalToolRunner: ExternalToolRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(binaryPath: String, arguments: [String])] = []
    var calls: [(binaryPath: String, arguments: [String])] { lock.withLock { _calls } }
    /// Given a call, returns the exit code; may write a file at the output path to simulate a tool.
    var behaviour: @Sendable (String, [String]) throws -> Int32 = { _, _ in 0 }
    func run(binaryPath: String, arguments: [String]) async throws -> ExternalToolResult {
        lock.withLock { _calls.append((binaryPath, arguments)) }          // withLock — never lock()/unlock() in async
        let code = try behaviour(binaryPath, arguments)
        return ExternalToolResult(exitCode: code, stderr: code == 0 ? "" : "simulated failure")
    }
}
```
Cases: (1) `SVGFragmentExtractor.body` on a potrace-style doc (prolog + DOCTYPE + `<metadata>` + `<g transform…>`) returns the inner `<g…>…</g>`; (2) on a vtracer-style bare root; (3) self-closing root → `""`; (4) no `</svg>` → nil; (5) `RasterVectorExecutor.convert` with `.outline` calls ffmpeg then potrace, intermediate ends `.bmp`, output written by the mock exists; (6) `.colorQuantization` → vtracer, intermediate `.png`; (7) missing tracer path → `.tracingToolNotFound`; (8) tracer exit 2 → `.toolFailed(tool:"potrace"…)`; (9) mock that never writes → `.outputMissing`; (10) `ProResVectorExecutor.convert` with a mock whose ffmpeg call writes 3 `frame_%06d.png` files and whose tracer writes a canned SVG → output contains `data-frame-count="3"`, three `id="frame-N"`, three `</g>`, ends with `</svg>`, returns 3; (11) `.alphaMatteOnly` selects potrace regardless of tracing mode; (12) `.cssKeyframes` → `.invalidConfiguration`; (13) progress callback observed stages in order extracting → tracing(1..3) → assembling with non-decreasing fractions; (14) cancellation: behaviour sleeps 200 ms per call, cancel the outer task after the first frame → throws `CancellationError`, `calls.count <= 3`, no output file; (15) zero frames extracted → `.operationFailed`; (16) `assembleAnimatedSVG` pure test with two bodies; (17) locator: `BundledToolLocator(toolName: "potrace", userOverridePath: <temp executable>).locate()` returns the override, and `BundledToolLocator(toolName: uniqueName)` throws (copy the `RawCDImagingExecutorTests.swift:497-524` pattern). Timing assertions one-sided (`<=`) only.

## G. Docs / packaging text (all in the same PR)

- `docs/decisions/0001-gpl-disc-tools.md`: append **"Amendment 1 — <date>"**: (a) the first GPL tool actually shipped is `potrace` (#473), not a disc tool; (b) the Direct-only mechanism is `ToolBundleManifest.directOnlyManifest` + `activeManifest` gated on **`#if APP_STORE`** — not `isDirectBuild`/`DIRECT`, which `release.yml:264` deliberately never sets — so consequence #5 reads "hidden when `APP_STORE`"; (c) macOS "universal" (op-decision 3, `:137-139`) is achieved on the converter side via `lipo` — the mirror publishes thin per-arch assets; (d) correct `:140-150`: `RawCDReadPlanner`/`DiscImagingController`/`CdrdaoTocParser`/`BundledToolLocator` now exist and `DiscCommand` invokes `cdrdao`, yet `cdrdao` is still neither in the mirror nor bundled — an open gap under the "same change" rule, tracked on #494/#495, **not** fixed here. Do not rewrite the accepted text; amend.
- `CHANGELOG.md`: under `## [Unreleased]` add `### Added` (or extend it) bullet: "**Vector Conversion** and **ProRes → Vector** now run for real in Direct builds: bundled `potrace` (GPL-2.0-or-later, Direct-only, licence + written source offer in `Contents/Resources/Licenses`) and `vtracer` (MIT); raster → SVG and ProRes 4444 → SMIL-animated SVG with progress and Cancel; hidden in App Store builds (#473, #494)." Update the NOTE at `:15-20` (they are no longer hidden — the rc.4 "first-class sidebar entries" line becomes true again for Direct) and the `:95` "Hidden dead-end surfaces" bullet (drop the vector half).
- `README.md:124` row → "**Direct builds only.** Raster → SVG and ProRes 4444 → animated SVG execute with bundled potrace/vtracer; OCR, metadata preservation, shape persistence, keyframe extraction and non-SMIL animation are not implemented (#473)".
- `docs/distribution/rc4-known-limitations.md:17-19` → move to a "Direct-only" note; list the same not-implemented toggles.
- `Sources/MeedyaConverter/Resources/Help/vector-conversion.md`: replace the Status paragraph ("describe the exact tracing pipeline the engine will run" is false): describe the real pipeline (ffmpeg normalise → potrace/vtracer → SVG; ProRes: frame dump → per-frame trace → SMIL), the Direct-only availability, the Settings › Paths overrides, and the list of options that are not applied. Remove any mention of Inkscape/autotrace/rsvg.
- `.claude/HANDOFF.md:223-228`: replace the "no macOS compile runner" sentence with the plan reference and the actual state.

## Verification gates (in this order)

```
swift build --target ConverterEngine
swift build 2>&1 | grep "error:" | grep -v "PreviewsMacros\|Preview(_:body:)\|external macro\|emit-module"   # must print nothing; never touch #Preview blocks
swiftc -parse Tests/ConverterEngineTests/VectorExecutorTests.swift
swiftc -parse Tests/MeedyaConverterCoreTests/NavigationItemAvailabilityTests.swift
grep -rhE "^(final class|class|struct|enum|actor) " Tests/ConverterEngineTests/ | sed -E 's/^(final class|class|struct|enum|actor) ([A-Za-z0-9_]+).*/\2/' | sort | uniq -d   # empty
grep -rhE "^(final class|class|struct|enum|actor) " Tests/MeedyaConverterCoreTests/ | sed -E 's/^(final class|class|struct|enum|actor) ([A-Za-z0-9_]+).*/\2/' | sort | uniq -d   # empty
grep -n "lock()\|unlock()" Tests/ConverterEngineTests/VectorExecutorTests.swift   # must be empty (withLock only)
bash -n scripts/bundle-tracing-tools.sh && shellcheck scripts/bundle-tracing-tools.sh
actionlint .github/workflows/release.yml
./scripts/verify-no-gpl-in-appstore.sh <fixture .app containing Contents/Helpers/potrace>   # expect exit 7
```
Once `MDLT_TAG` is pinned: `scripts/bundle-tracing-tools.sh /tmp/helpers /tmp/licenses && lipo -archs /tmp/helpers/potrace /tmp/helpers/vtracer` (both arches) and `ls /tmp/licenses` (three files). Then commit, push, **watch CI to green** (`gh run list --branch wip/alpha-consolidation`, `gh run watch`); a red test run is the only place a logic bug in the new tests will surface. State the gate honestly in the commit/issue: "CI green" = build + `swift test --parallel`; **no CI job ever executes potrace, vtracer or ffmpeg on an image** — real conversions are verified only on the manual matrix (macOS Direct DMG, both arches).

---

# RECOMMENDED SEQUENCING

1. **MeedyaDL-Tools PR** (`feat/vector-tracing-tools`, label `update-tools`) → confirm the eight assets in the PR run → merge → note the dated release tag. Nothing in MeedyaConverter can ship before this exists.
2. **In parallel**, MeedyaConverter engine + tests (C.2–C.7, F) on `wip/alpha-consolidation` — no tool needed to develop or CI-test; keep `MDLT_TAG` as the fail-closed placeholder.
3. Views + navigation + settings (D, E) — same PR/branch; the nav test flips in the same commit that wires execution (the pinning test exists precisely to force this coupling).
4. Bundle script + `release.yml` step + tripwire + manifest (A, B, C.1, C.2) — same change as step 3 (DR-0001 "same change" rule, `:149-150`).
5. Docs (G) — same PR.
6. **Last commit: pin `MDLT_TAG`** to step 1's tag; run the local bundle-script check; push; watch CI.
7. First Direct release after this: check the notarised `.app` contains `Contents/Helpers/{potrace,vtracer}` (universal) and `Contents/Resources/Licenses/*`, and that `testflight.yml`'s tripwire still passes on the App Store variant.

# RISKS

1. **GPL compliance (potrace).** Safe only as mere aggregation: subprocess invocation (`ExternalToolRunner`), unmodified upstream binary, no `libpotrace` linking, licence text + written source offer shipped, source tarball archived at the pinned mirror release. The offer wording in §A is a draft — **maintainer/legal sign-off required before the first Direct release that carries potrace**; the code makes shipping it mechanically impossible to forget (exit 9 if the licence file is missing).
2. **App Store tripwire.** Three independent guards: `test_toolBundleManifest_defaultManifestIsAppStoreSafe` (potrace is in `directOnlyManifest`, never `defaultManifest`), `verify-no-gpl-in-appstore.sh` (now lists `potrace`; runs only in `testflight.yml:331`), and `#if APP_STORE` hiding the nav entries. Residual: `testflight.yml` must never gain the bundle step — the step comment says so; a reviewer checklist item.
3. **Mirror → converter pin ordering.** The tag is unknowable until Part 1 merges; the placeholder fails closed (exit 6). The pin is a **separate** `MDLT_TAG` so ffmpeg's `2026-07-05.3` is untouched. Also: merging Part 1 forces a full mirror rebuild of *every* tool (`:83-94`); a flaky unrelated tool that day does not block us (all steps are `continue-on-error`), but a failed `build-tracing-tools` leg would leave assets missing → converter exit 6. Check the asset list before pinning.
4. **Notarisation of third-party binaries in the .app.** `codesign.sh:186` signs everything in `Contents/Helpers` with hardened runtime + timestamp + GUI entitlements — the same path ffmpeg already passes. potrace links system libz dynamically (present on every macOS); vtracer is a static Rust binary. `-mmacosx-version-min=13.0` for potrace is below the app's `.macOS(.v15)` — harmless. Unknown until the first run: none expected, but a notarytool rejection would name the binary; fix in the mirror build flags, never by patching the binary.
5. **Runtime availability unverifiable in CI.** No CI job runs potrace/vtracer/ffmpeg-on-images; executors are tested against `MockExternalToolRunner` only, and the ffmpeg filter graphs (white composite, `alphaextract`, `select`+`fps_mode`) are asserted as strings. Real behaviour is verified on the manual matrix; say exactly that in commit messages, the help page and the CHANGELOG — never "tested end-to-end".
6. **False comments / fabricated capability** — the codebase's recurring defect. This plan removes or corrects: the vtracer flags that never existed; `AlphaStrategy`'s clip-path promise; `preserveMetadata`/`ocrTextRegions`/`shapePersistence`/`keyframeExtraction` toggles (hidden, docs say "not applied"); non-SMIL animation methods (picker restricted, executor throws); the "Install via Homebrew" error text; `AppViewModel`'s "are GPL" claim; the help page's "describe the exact pipeline the engine will run"; HANDOFF's "no macOS runner"; DR-0001's stale executor/mirror claims. Reviewer question for every new comment: *does this hold at every call site?*
7. **vtracer is a `1.0.0-alpha` pin.** Flags could change in `alpha.5`. Mitigations: exact-tag pin (no `latest`), the `--help` tripwire in the mirror build, the converter-side `--max-colors` smoke, and `test_vtracerArguments_useKebabCaseFlags`. A bump is a deliberate two-repo change.
8. **potrace 1.16 autotools on Apple Silicon.** Its bundled `config.sub` predates arm64; `autoreconf -fi` after `brew install autoconf automake libtool` is the fix, verified only by the first CI run — fallback documented in Part 1 §3.
9. **`-vf` / stride fix changes ffmpeg behaviour** for `frameStride > 1` (previously the tonemap/format chain was silently dropped and frames duplicated). This is a bug fix, not a regression; tests pin the single-chain shape.
10. **SMIL semantics change** (`<set fill="remove">` instead of `<animate fill="freeze">`): required so alpha frames do not stack; the existing test assertion on `fill="freeze"` must change with it.
11. **dev builds carry no helpers** (unchanged scope): the Vector tools appear in dev builds but the Convert button is disabled with the "not found" caption unless Homebrew/PATH provides the tools. Not a dead button — a disabled one with a reason.
12. **Output size / long ProRes clips**: per-frame tracing is slow and the SVG can be huge; the existing warning now uses the real duration, and Cancel terminates the live process and discards partial output (temp dir removed in every exit path).
13. **Swift 6 isolation**: `@Sendable` progress hops via `Task { @MainActor in … }` (precedent `DualDynamicHDRView.swift:629-634`); `NSLock` only in synchronous helpers; `Process` wrapped in an `@unchecked Sendable` box. If CI's Swift objects, capture a `Binding`/`sink` rather than weakening `@Sendable`.
14. **Concurrent edits**: `CHANGELOG.md`, `README.md`, `.claude/HANDOFF.md` move often on this branch — anchor those edits by text, and re-verify `AppViewModel.swift:166-181` / `SidebarView.swift:67-77` line numbers against HEAD before editing.
15. **CLI parity not included**: `meedya-convert` gets no `vector` subcommand this round (the help page already says GUI-only); note as follow-up, do not claim it.