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
#   scripts/bundle-ffmpeg.sh --refresh-checksums [VERSION] [ARCHITECTURE]
#
# Arguments:
#   DEST_DIR      Destination directory (required for the normal build path).
#                 Binaries are written to ${DEST_DIR}/ffmpeg, /ffprobe, /ffplay.
#   VERSION       FFmpeg version (default: 7.1.2).
#   ARCHITECTURE  Target arch: arm64 (default) or x86_64.
#
# Supply-chain integrity (SECURITY.md F-011)
# ------------------------------------------
# The static builds are downloaded over HTTPS, which protects TRANSPORT
# only — not source integrity (the URLs are not content-addressed). The
# release pipeline then code-signs + notarises whatever is downloaded
# under MWBM's Developer ID, so an un-verified binary would ship
# Gatekeeper-approved. To close that gap this script VERIFIES each
# downloaded .zip against a pinned SHA-256 recorded in
# `scripts/ffmpeg-checksums.txt`, keyed by (version, arch, tool), and
# FAILS CLOSED if the entry is missing or mismatched.
#
# Because the checksum is pinned per VERSION, a version bump is a
# deliberate two-part edit: change VERSION here (and in release.yml),
# then regenerate the pins with:
#
#     scripts/bundle-ffmpeg.sh --refresh-checksums <NEW_VERSION> arm64
#     scripts/bundle-ffmpeg.sh --refresh-checksums <NEW_VERSION> x86_64
#
# and COMMIT the updated ffmpeg-checksums.txt alongside the version bump.
# `--refresh-checksums` establishes trust-on-first-use: it records
# whatever the server serves right now, so run it from a trusted network
# and ideally cross-check the recorded hash against an independent build
# once. It NEVER runs implicitly during a normal build — that would
# defeat the whole purpose.
#
# GitHub Issue #378 — Extract and package ALL FFmpeg components.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Mode + argument parsing
# ---------------------------------------------------------------------------
REFRESH_CHECKSUMS=0
if [[ "${1:-}" == "--refresh-checksums" ]]; then
    REFRESH_CHECKSUMS=1
    shift
fi

if [[ "${REFRESH_CHECKSUMS}" -eq 1 ]]; then
    # DEST_DIR is irrelevant when only (re)recording checksums.
    DEST_DIR="$(mktemp -d)"
    VERSION="${1:-7.1.2}"
    ARCH="${2:-arm64}"
    echo "[bundle-ffmpeg] REFRESH-CHECKSUMS mode  version=${VERSION} arch=${ARCH}"
    echo "[bundle-ffmpeg] WARNING: records trust-on-first-use hashes for whatever"
    echo "[bundle-ffmpeg]          the server serves NOW — run from a trusted network"
    echo "[bundle-ffmpeg]          and review the recorded hashes before committing."
else
    DEST_DIR="${1:?usage: bundle-ffmpeg.sh <DEST_DIR> [VERSION] [ARCH]  |  --refresh-checksums [VERSION] [ARCH]}"
    VERSION="${2:-7.1.2}"
    ARCH="${3:-arm64}"
    echo "[bundle-ffmpeg] dest=${DEST_DIR} version=${VERSION} arch=${ARCH}"
fi

# Path to the pinned-checksum manifest (sits next to this script).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKSUM_FILE="${SCRIPT_DIR}/ffmpeg-checksums.txt"

# Look up the pinned SHA-256 for (VERSION, ARCH, tool). Emits the hash
# and returns 0 when found; emits nothing and returns 1 when absent.
# Manifest comment/blank lines are ignored by the field match.
expected_sha() {
    local tool="$1"
    [[ -f "${CHECKSUM_FILE}" ]] || return 1
    awk -v v="${VERSION}" -v a="${ARCH}" -v t="${tool}" \
        '$1==v && $2==a && $3==t { print $4; found=1 } END { exit(found?0:1) }' \
        "${CHECKSUM_FILE}"
}

# Record (or replace) the pinned SHA-256 for (VERSION, ARCH, tool).
# Used only by --refresh-checksums. Keeps the manifest sorted with
# comment lines on top for a stable, review-friendly diff.
record_sha() {
    local tool="$1" sha="$2"
    touch "${CHECKSUM_FILE}"
    local tmp
    tmp="$(mktemp)"
    awk -v v="${VERSION}" -v a="${ARCH}" -v t="${tool}" \
        '!($1==v && $2==a && $3==t)' "${CHECKSUM_FILE}" > "${tmp}"
    printf '%s %s %s %s\n' "${VERSION}" "${ARCH}" "${tool}" "${sha}" >> "${tmp}"
    { grep -E '^#' "${tmp}" || true; grep -vE '^#|^[[:space:]]*$' "${tmp}" | sort; } > "${CHECKSUM_FILE}"
    rm -f "${tmp}"
    echo "[bundle-ffmpeg] recorded: ${VERSION} ${ARCH} ${tool} ${sha}"
}

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

    # -----------------------------------------------------------------
    # SHA-256 integrity gate (F-011). Verify the DOWNLOADED BYTES before
    # we unzip or trust anything from the archive. The hash is taken of
    # the .zip (the exact transfer unit), immediately after curl.
    # -----------------------------------------------------------------
    local actual
    actual="$(shasum -a 256 "${tmp}/${tool}.zip" | awk '{print $1}')"

    if [[ "${REFRESH_CHECKSUMS}" -eq 1 ]]; then
        # Trust-on-first-use: record whatever we just downloaded. Still
        # falls through to unzip + -version validation below so a broken
        # download can't be blessed.
        record_sha "${tool}" "${actual}"
    else
        local expected
        if ! expected="$(expected_sha "${tool}")"; then
            echo "[bundle-ffmpeg] FATAL: no pinned SHA-256 for ${VERSION}/${ARCH}/${tool} in" >&2
            echo "                ${CHECKSUM_FILE}" >&2
            echo "                Refusing to bundle an unverified binary (F-011)." >&2
            echo "                Populate it with:" >&2
            echo "                  scripts/bundle-ffmpeg.sh --refresh-checksums ${VERSION} ${ARCH}" >&2
            rm -rf "${tmp}"
            exit 6
        fi
        if [[ "${actual}" != "${expected}" ]]; then
            echo "[bundle-ffmpeg] FATAL: SHA-256 MISMATCH for ${VERSION}/${ARCH}/${tool} (F-011)" >&2
            echo "                expected ${expected}" >&2
            echo "                actual   ${actual}" >&2
            echo "                The upstream artefact changed since it was pinned — do NOT" >&2
            echo "                ship it. If the change is legitimate, re-pin deliberately" >&2
            echo "                via --refresh-checksums after verifying the new build." >&2
            rm -rf "${tmp}"
            exit 7
        fi
        echo "[bundle-ffmpeg] ${tool}.zip SHA-256 verified (${actual})"
    fi

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

if [[ "${REFRESH_CHECKSUMS}" -eq 1 ]]; then
    echo "[bundle-ffmpeg] checksums refreshed in ${CHECKSUM_FILE}"
    echo "[bundle-ffmpeg] review the diff and commit it alongside the version bump."
    rm -rf "${DEST_DIR}"
else
    echo "[bundle-ffmpeg] all three components staged (SHA-256-verified) at ${DEST_DIR}"
fi
