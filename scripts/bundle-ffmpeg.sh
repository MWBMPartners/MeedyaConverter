#!/bin/bash
# =============================================================================
# MeedyaConverter — Bundle FFmpeg components script (universal)
# Copyright (c) 2026 MWBM Partners Ltd. All rights reserved.
# =============================================================================
#
# Stages UNIVERSAL (arm64 + x86_64) ffmpeg / ffprobe / ffplay binaries at the
# path FFmpegBundleManager searches at runtime. Called by the release pipeline
# and by developers who want a self-contained local checkout.
#
# Usage:
#   scripts/bundle-ffmpeg.sh <DEST_DIR>
#
# Arguments:
#   DEST_DIR   Destination directory (required). Universal binaries are written
#              to ${DEST_DIR}/ffmpeg, ${DEST_DIR}/ffprobe, ${DEST_DIR}/ffplay.
#
# Source (MeedyaDL-Tools, first-party, pinned + verified)
# -------------------------------------------------------
# All tools come from the first-party mirror MeedyaSuite/MeedyaDL-Tools, pinned
# to an immutable dated release (MDLT_TAG). The mirror publishes REAL native
# builds for BOTH arches — macOS arm64 (osxexperts.net static builds) and
# macOS x86_64 (evermeet.cx) — and this script lipo-combines them into a single
# universal binary per tool. There is no third-party fallback in this repo: the
# mirror is the sole source, so the supply chain is entirely first-party.
#
# Supply-chain integrity (SECURITY.md F-011)
# ------------------------------------------
# HTTPS protects transport only, and the release pipeline code-signs + notarises
# whatever is bundled under MWBM's Developer ID — so an unverified binary would
# ship Gatekeeper-approved. Every downloaded archive is therefore SHA-256
# verified against the SAME release's SHA256SUMS BEFORE it is unpacked, and the
# script FAILS CLOSED: missing SHA256SUMS or a missing pin -> exit 6, a hash
# MISMATCH -> exit 7 (always fatal, even for the optional ffplay).
#
# Bumping the pinned version is a single deliberate edit: change MDLT_TAG to a
# newer MeedyaDL-Tools release. No local hashes are maintained — the trust root
# is the first-party tagged release's own SHA256SUMS.
#
# GitHub Issue #378 — package ALL FFmpeg components; universal per MWBM ship.
# =============================================================================

set -euo pipefail

DEST_DIR="${1:?usage: bundle-ffmpeg.sh <DEST_DIR>}"

# -----------------------------------------------------------------------------
# Pinned first-party source
# -----------------------------------------------------------------------------
# Immutable dated MeedyaDL-Tools release that ships real arm64 + x86_64 macOS
# ffmpeg/ffprobe/ffplay AND a SHA256SUMS asset. Bump deliberately to pick up a
# newer FFmpeg; the mirror keeps this current on its daily schedule.
MDLT_REPO="MeedyaSuite/MeedyaDL-Tools"
MDLT_TAG="2026-07-05.3"
MDLT_BASE="https://github.com/${MDLT_REPO}/releases/download/${MDLT_TAG}"

mkdir -p "${DEST_DIR}"
WORK="$(mktemp -d)"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

echo "[bundle-ffmpeg] source: ${MDLT_REPO}@${MDLT_TAG}  dest: ${DEST_DIR}"

# -----------------------------------------------------------------------------
# Fetch the release's SHA256SUMS (the verification root). Fail closed if absent.
# -----------------------------------------------------------------------------
if ! curl -fsSL --retry 3 "${MDLT_BASE}/SHA256SUMS" -o "${WORK}/SHA256SUMS"; then
    echo "[bundle-ffmpeg] FATAL: no SHA256SUMS at ${MDLT_TAG} (F-011) — refusing to bundle" >&2
    echo "                unverified binaries. Pin MDLT_TAG at a release that has one." >&2
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

    echo "[bundle-ffmpeg]   fetch ${asset}" >&2
    if ! curl -fsSL --retry 5 --retry-delay 3 "${MDLT_BASE}/${asset}" -o "${dest}"; then
        echo "[bundle-ffmpeg]   ✗ download failed: ${asset}" >&2
        return 1
    fi

    local expected actual
    if ! expected="$(expected_sha "${asset}")"; then
        echo "[bundle-ffmpeg]   ✗ ${asset} not in SHA256SUMS" >&2
        return 1
    fi
    actual="$(shasum -a 256 "${dest}" | awk '{print $1}')"
    if [ "${actual}" != "${expected}" ]; then
        echo "[bundle-ffmpeg] FATAL: SHA-256 MISMATCH for ${asset} (F-011)" >&2
        echo "                expected ${expected}" >&2
        echo "                actual   ${actual}" >&2
        exit 7
    fi

    local ex="${WORK}/ex-${tool}-${arch}"
    mkdir -p "${ex}"
    tar -xzf "${dest}" -C "${ex}"
    local bin
    bin="$(find "${ex}" -type f -name "${tool}" | head -1)"
    if [ -z "${bin}" ]; then
        echo "[bundle-ffmpeg]   ✗ ${tool} binary not found in ${asset}" >&2
        return 1
    fi
    echo "${bin}"
}

# Build a universal (arm64 + x86_64) binary for a tool by lipo-combining the two
# per-arch downloads. `required=1` fails the build if either arch is missing;
# `required=0` (ffplay) skips the tool best-effort.
build_universal() {
    local tool="$1" required="$2"
    local arm x86
    echo "[bundle-ffmpeg] ${tool}: universal (arm64 + x86_64)" >&2

    if ! arm="$(fetch_arch_binary "${tool}" aarch64)" \
       || ! x86="$(fetch_arch_binary "${tool}" x86_64)"; then
        if [ "${required}" -eq 1 ]; then
            echo "[bundle-ffmpeg] FATAL: could not obtain both arches of ${tool} (F-011)" >&2
            exit 6
        fi
        echo "[bundle-ffmpeg] ⚠ ${tool} unavailable (optional) — skipping" >&2
        return 0
    fi

    lipo -create "${arm}" "${x86}" -output "${DEST_DIR}/${tool}"
    chmod 0755 "${DEST_DIR}/${tool}"

    # Assert the result really is a 2-arch universal binary.
    local archs
    archs="$(lipo -archs "${DEST_DIR}/${tool}" 2>/dev/null || echo "")"
    case "${archs}" in
        *arm64*x86_64*|*x86_64*arm64*)
            echo "[bundle-ffmpeg] ✓ ${tool} universal (${archs})" >&2 ;;
        *)
            echo "[bundle-ffmpeg] FATAL: ${tool} is not universal (got: ${archs})" >&2
            exit 8 ;;
    esac
}

# ffmpeg + ffprobe are REQUIRED at runtime; ffplay drives only the in-app
# preview and is optional.
build_universal ffmpeg  1
build_universal ffprobe 1
build_universal ffplay  0

# -----------------------------------------------------------------------------
# Post-install validation (required tools must be executable + report a version)
# -----------------------------------------------------------------------------
echo "[bundle-ffmpeg] validating staged binaries..."
for tool in ffmpeg ffprobe; do
    if [ ! -x "${DEST_DIR}/${tool}" ]; then
        echo "[bundle-ffmpeg] FATAL: ${tool} is missing or not executable" >&2
        exit 4
    fi
    printf "[bundle-ffmpeg]   %s -> " "${tool}"
    "${DEST_DIR}/${tool}" -version 2>/dev/null | head -1 || {
        echo "[bundle-ffmpeg] FATAL: ${tool} failed -version check" >&2
        exit 5
    }
done

echo "[bundle-ffmpeg] done — universal binaries staged (SHA-256-verified) at ${DEST_DIR}"
