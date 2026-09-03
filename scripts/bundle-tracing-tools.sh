#!/bin/bash
# =============================================================================
# MeedyaConverter — Bundle vector tracing tools script (universal)
# Copyright (c) 2026 MWBM Partners Ltd. All rights reserved.
# =============================================================================
#
# Sibling of scripts/bundle-ffmpeg.sh (same skeleton: pinned first-party
# mirror release, fail-closed SHA256SUMS verification, per-arch fetch +
# lipo). The duplication is DELIBERATE, not copy-paste debt: this script has
# its own MDLT_TAG pin, separate from bundle-ffmpeg.sh's — bumping one must
# never silently move the other (ffmpeg/ffprobe/ffplay are a different
# release cadence from potrace/vtracer, whose CLI flags this codebase's
# argument builders are coupled to exact-version).
#
# Stages, for the release pipeline (Direct builds only — issue #473 / #494):
#   - ${HELPERS_DIR}/potrace  — universal (arm64 + x86_64), GPL-2.0-or-later
#   - ${HELPERS_DIR}/vtracer  — universal (arm64 + x86_64), MIT
#   - ${LICENSES_DIR}/potrace-COPYING.txt
#   - ${LICENSES_DIR}/vtracer-LICENSE.txt
#   - ${LICENSES_DIR}/SOURCE-OFFER-potrace.txt (DR-0001 written source offer;
#     potrace is GPL-2.0-or-later — the corresponding source is archived at
#     the pinned mirror release, and this file points at it by URL)
#
# Usage:
#   scripts/bundle-tracing-tools.sh <HELPERS_DIR> <LICENSES_DIR>
#
# Both tools are REQUIRED — unlike bundle-ffmpeg.sh's optional ffplay, there
# is no "ship without it" case here: a Direct build without potrace has no
# working "Vector Conversion" tool at all, and shipping vtracer alone would
# silently drop Outline/Monochrome tracing modes without saying so.
#
# Supply-chain integrity (SECURITY.md F-011) — identical posture to
# bundle-ffmpeg.sh: every downloaded archive is SHA-256 verified against the
# SAME release's SHA256SUMS before it is unpacked; the script fails closed.
#
# GitHub Issue #473 / #494 — potrace + vtracer, Direct builds only, GPL-safe.
# =============================================================================

set -euo pipefail

HELPERS_DIR="${1:?usage: bundle-tracing-tools.sh <HELPERS_DIR> <LICENSES_DIR>}"
LICENSES_DIR="${2:?usage: bundle-tracing-tools.sh <HELPERS_DIR> <LICENSES_DIR>}"

# -----------------------------------------------------------------------------
# Pinned first-party source
# -----------------------------------------------------------------------------
# Immutable dated MeedyaDL-Tools release that ships potrace + vtracer for
# macOS arm64 + x86_64, their corresponding-source archives, and a
# SHA256SUMS asset. PINNED ON PURPOSE, separately from bundle-ffmpeg.sh's
# MDLT_TAG: this repo's argument builders (RasterVectorConverter) are coupled
# to each tool's exact CLI flag set, so a version bump is a deliberate PR
# here plus a builder+test change there — never an automatic upstream
# follow, and never bundled with an unrelated ffmpeg refresh.
#
# ORDERING DEPENDENCY (hard): this tag does not exist until the companion
# MeedyaDL-Tools PR (feat/vector-tracing-tools, see
# .claude/plans/vector-tracers-plan.md Part 1) merges to `main` and its
# post-merge release is cut. Until then this is a deliberate placeholder
# that FAILS CLOSED at the SHA256SUMS fetch below (exit 6) — the whole of
# Part 2 (engine, executors, views, tests) can be developed and CI-tested
# without this pin ever resolving, because `build.yml` never runs this
# script. Do NOT cut a Direct release, or merge to `main`, while this
# placeholder is in place.
MDLT_REPO="MeedyaSuite/MeedyaDL-Tools"
MDLT_TAG="<PENDING-MeedyaDL-Tools-release>"
MDLT_BASE="https://github.com/${MDLT_REPO}/releases/download/${MDLT_TAG}"

mkdir -p "${HELPERS_DIR}" "${LICENSES_DIR}"
WORK="$(mktemp -d)"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

echo "[bundle-tracing-tools] source: ${MDLT_REPO}@${MDLT_TAG}  helpers: ${HELPERS_DIR}  licenses: ${LICENSES_DIR}"

# -----------------------------------------------------------------------------
# Fetch the release's SHA256SUMS (the verification root). Fail closed if
# absent — this is also where the fail-closed placeholder above bites: a tag
# named "<PENDING-MeedyaDL-Tools-release>" can never resolve to a real
# GitHub release, so this curl always fails until MDLT_TAG is pinned for
# real, and we exit 6 rather than silently staging nothing.
# -----------------------------------------------------------------------------
if ! curl -fsSL --retry 3 "${MDLT_BASE}/SHA256SUMS" -o "${WORK}/SHA256SUMS"; then
    echo "[bundle-tracing-tools] FATAL: no SHA256SUMS at ${MDLT_TAG} (F-011) — refusing to bundle" >&2
    echo "                       unverified binaries. Pin MDLT_TAG at a release that has one." >&2
    exit 6
fi

# Expected sha256 for an asset from SHA256SUMS ('<sha>  <file>'); rc 1 if absent.
expected_sha() {
    awk -v a="$1" '$2==a { print $1; found=1 } END { exit(found?0:1) }' "${WORK}/SHA256SUMS"
}

# Download + SHA-256-verify an asset, then extract its named binary. Echoes the
# extracted binary path on stdout (logs go to stderr). Returns non-zero on a
# download / missing-asset failure; a hash MISMATCH is always fatal (exit 7).
fetch_arch_binary() {
    local tool="$1" arch="$2"
    local asset="${tool}-macos-${arch}.tar.gz"
    local dest="${WORK}/${asset}"

    echo "[bundle-tracing-tools]   fetch ${asset}" >&2
    if ! curl -fsSL --retry 5 --retry-delay 3 "${MDLT_BASE}/${asset}" -o "${dest}"; then
        echo "[bundle-tracing-tools]   ✗ download failed: ${asset}" >&2
        return 1
    fi

    local expected actual
    if ! expected="$(expected_sha "${asset}")"; then
        echo "[bundle-tracing-tools]   ✗ ${asset} not in SHA256SUMS" >&2
        return 1
    fi
    actual="$(shasum -a 256 "${dest}" | awk '{print $1}')"
    if [ "${actual}" != "${expected}" ]; then
        echo "[bundle-tracing-tools] FATAL: SHA-256 MISMATCH for ${asset} (F-011)" >&2
        echo "                       expected ${expected}" >&2
        echo "                       actual   ${actual}" >&2
        exit 7
    fi

    local ex="${WORK}/ex-${tool}-${arch}"
    mkdir -p "${ex}"
    tar -xzf "${dest}" -C "${ex}"
    local bin
    bin="$(find "${ex}" -type f -name "${tool}" | head -1)"
    if [ -z "${bin}" ]; then
        echo "[bundle-tracing-tools]   ✗ ${tool} binary not found in ${asset}" >&2
        return 1
    fi
    echo "${bin}"
}

# Licence file basename the mirror tars next to each tool's binary (see Part
# 1 of the plan: potrace ships COPYING, vtracer ships LICENSE).
licence_basename_for() {
    case "$1" in
        potrace) echo "COPYING" ;;
        vtracer) echo "LICENSE" ;;
        *) echo "" ;;
    esac
}

# Build a universal (arm64 + x86_64) binary for a tool by lipo-combining the two
# per-arch downloads, then stage its licence file. `required=1` fails the
# build if either arch — or the licence file — is missing; there is no
# `required=0` case in this script (unlike bundle-ffmpeg.sh's optional
# ffplay): both tools are mandatory for a working Direct build.
build_universal() {
    local tool="$1" required="$2"
    local arm x86
    echo "[bundle-tracing-tools] ${tool}: universal (arm64 + x86_64)" >&2

    if ! arm="$(fetch_arch_binary "${tool}" aarch64)" \
       || ! x86="$(fetch_arch_binary "${tool}" x86_64)"; then
        if [ "${required}" -eq 1 ]; then
            echo "[bundle-tracing-tools] FATAL: could not obtain both arches of ${tool} (F-011)" >&2
            exit 6
        fi
        echo "[bundle-tracing-tools] ⚠ ${tool} unavailable (optional) — skipping" >&2
        return 0
    fi

    lipo -create "${arm}" "${x86}" -output "${HELPERS_DIR}/${tool}"
    chmod 0755 "${HELPERS_DIR}/${tool}"

    # Assert the result really is a 2-arch universal binary.
    local archs
    archs="$(lipo -archs "${HELPERS_DIR}/${tool}" 2>/dev/null || echo "")"
    case "${archs}" in
        *arm64*x86_64*|*x86_64*arm64*)
            echo "[bundle-tracing-tools] ✓ ${tool} universal (${archs})" >&2 ;;
        *)
            echo "[bundle-tracing-tools] FATAL: ${tool} is not universal (got: ${archs})" >&2
            exit 8 ;;
    esac

    # DR-0001 consequence #2: licence text is not optional. The mirror tars
    # it next to the binary in the same (flat) archive, so it sits alongside
    # the extracted binary — copy it from the arm64 extraction.
    local licence_name dest_name
    licence_name="$(licence_basename_for "${tool}")"
    dest_name="${tool}-${licence_name}.txt"
    local licence_src
    licence_src="$(dirname "${arm}")/${licence_name}"
    if [ ! -f "${licence_src}" ]; then
        echo "[bundle-tracing-tools] FATAL: ${tool}'s licence file (${licence_name}) missing from its archive (DR-0001)" >&2
        exit 9
    fi
    cp "${licence_src}" "${LICENSES_DIR}/${dest_name}"
    echo "[bundle-tracing-tools] ✓ staged ${dest_name}" >&2
}

# Both tools are required — no optional tool in this script.
build_universal potrace 1
build_universal vtracer 1

# -----------------------------------------------------------------------------
# Written source offer for potrace (GPL-2.0-or-later) — DR-0001 consequence
# #3. Safe only as mere aggregation: an unmodified upstream binary invoked
# as a separate subprocess (ExternalToolRunner/RasterVectorExecutor never
# link libpotrace), with the exact corresponding source archived at the same
# pinned mirror release this script fetched the binary from.
#
# WORDING DRAFT — maintainer/legal sign-off required before the first Direct
# release that carries potrace (see the plan's Risks section).
# -----------------------------------------------------------------------------
cat > "${LICENSES_DIR}/SOURCE-OFFER-potrace.txt" <<EOF
Written offer for corresponding source — potrace 1.16 (GPL-2.0-or-later)

MeedyaConverter (Direct distribution) includes an unmodified potrace 1.16
binary, invoked as a separate program. The complete corresponding source
used to build it is published, with its SHA-256, at:
  https://github.com/${MDLT_REPO}/releases/download/${MDLT_TAG}/potrace-1.16.src.tar.gz
  https://github.com/${MDLT_REPO}/releases/download/${MDLT_TAG}/SHA256SUMS
This offer is valid to any third party for at least three years from the
build date of this copy, at no charge beyond the cost of distribution.
MWBM Partners Ltd — <contact address to be confirmed by the maintainer>
EOF
echo "[bundle-tracing-tools] ✓ staged SOURCE-OFFER-potrace.txt"

# -----------------------------------------------------------------------------
# Post-stage smoke tests — the converter-side half of the mirror's --help
# flag tripwire (Part 1 of the plan). A version/help string that doesn't
# match means the pin drifted to a build that would silently break
# RasterVectorConverter's argument builders.
# -----------------------------------------------------------------------------
echo "[bundle-tracing-tools] validating staged binaries..."

if ! "${HELPERS_DIR}/potrace" --version 2>/dev/null | head -1 | grep -q "1.16"; then
    echo "[bundle-tracing-tools] FATAL: potrace --version does not report 1.16" >&2
    exit 5
fi
echo "[bundle-tracing-tools]   potrace -> OK (1.16)"

if ! "${HELPERS_DIR}/vtracer" --help 2>/dev/null | grep -q -- "--max-colors"; then
    echo "[bundle-tracing-tools] FATAL: vtracer --help lacks --max-colors (flag drift?)" >&2
    exit 5
fi
echo "[bundle-tracing-tools]   vtracer -> OK (--max-colors present)"

echo "[bundle-tracing-tools] done — universal binaries + licences staged (SHA-256-verified)"
echo "                       helpers: ${HELPERS_DIR}"
echo "                       licenses: ${LICENSES_DIR}"
