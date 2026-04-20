#!/bin/bash
# =============================================================================
# MeedyaConverter — Bundle FFmpeg components script
# Copyright (c) 2026 MWBM Partners Ltd. All rights reserved.
# =============================================================================
#
# Downloads and extracts the complete FFmpeg toolkit (ffmpeg, ffprobe, ffplay)
# from a static-build distribution and stages the binaries at the path the
# FFmpegBundleManager searches at runtime. Called by the release pipeline and
# by developers who want a self-contained local checkout.
#
# Usage:
#   scripts/bundle-ffmpeg.sh <DEST_DIR> [VERSION] [ARCHITECTURE]
#
# Arguments:
#   DEST_DIR      Destination directory (required). Binaries are written to
#                 ${DEST_DIR}/ffmpeg, ${DEST_DIR}/ffprobe, ${DEST_DIR}/ffplay.
#   VERSION       FFmpeg version (default: 7.1.2).
#   ARCHITECTURE  Target arch: arm64 (default) or x86_64.
#
# GitHub Issue #378 — Extract and package ALL FFmpeg components.
# =============================================================================

set -euo pipefail

DEST_DIR="${1:?usage: bundle-ffmpeg.sh <DEST_DIR> [VERSION] [ARCH]}"
VERSION="${2:-7.1.2}"
ARCH="${3:-arm64}"

echo "[bundle-ffmpeg] dest=${DEST_DIR} version=${VERSION} arch=${ARCH}"

# ---------------------------------------------------------------------------
# Source selection
# ---------------------------------------------------------------------------
# We download from the osxexperts static builds (gyan.dev for x86_64, evermeet
# for arm64). These bundle ffmpeg + ffprobe + ffplay together, which is the
# core requirement of issue #378 — prior releases extracted only the first two.
# ---------------------------------------------------------------------------
case "${ARCH}" in
    arm64)
        FFMPEG_URL="https://www.osxexperts.net/ffmpeg${VERSION//./}arm.zip"
        FFPROBE_URL="https://www.osxexperts.net/ffprobe${VERSION//./}arm.zip"
        FFPLAY_URL="https://www.osxexperts.net/ffplay${VERSION//./}arm.zip"
        ;;
    x86_64)
        FFMPEG_URL="https://www.osxexperts.net/ffmpeg${VERSION//./}intel.zip"
        FFPROBE_URL="https://www.osxexperts.net/ffprobe${VERSION//./}intel.zip"
        FFPLAY_URL="https://www.osxexperts.net/ffplay${VERSION//./}intel.zip"
        ;;
    *)
        echo "[bundle-ffmpeg] unsupported arch: ${ARCH}" >&2
        exit 2
        ;;
esac

mkdir -p "${DEST_DIR}"

fetch_and_extract() {
    local url="$1"
    local tool="$2"
    local tmp
    tmp="$(mktemp -d)"
    echo "[bundle-ffmpeg] fetching ${tool} from ${url}"
    curl --fail --silent --show-error --location "${url}" -o "${tmp}/${tool}.zip"
    unzip -q "${tmp}/${tool}.zip" -d "${tmp}/"
    # Find the binary — zip layouts vary by source.
    local binary
    binary="$(find "${tmp}" -type f -name "${tool}" -perm -u+x | head -1)"
    if [[ -z "${binary}" ]]; then
        echo "[bundle-ffmpeg] ${tool} binary not found in ${url}" >&2
        exit 3
    fi
    install -m 0755 "${binary}" "${DEST_DIR}/${tool}"
    rm -rf "${tmp}"
}

fetch_and_extract "${FFMPEG_URL}" "ffmpeg"
fetch_and_extract "${FFPROBE_URL}" "ffprobe"
fetch_and_extract "${FFPLAY_URL}" "ffplay"

# ---------------------------------------------------------------------------
# Post-install validation
# ---------------------------------------------------------------------------
echo "[bundle-ffmpeg] validating extracted binaries..."
for tool in ffmpeg ffprobe ffplay; do
    if [[ ! -x "${DEST_DIR}/${tool}" ]]; then
        echo "[bundle-ffmpeg] ${tool} is not executable" >&2
        exit 4
    fi
    printf "[bundle-ffmpeg] %s -> " "${tool}"
    "${DEST_DIR}/${tool}" -version 2>/dev/null | head -1 || {
        echo "[bundle-ffmpeg] ${tool} failed -version check" >&2
        exit 5
    }
done

echo "[bundle-ffmpeg] all three components staged at ${DEST_DIR}"
