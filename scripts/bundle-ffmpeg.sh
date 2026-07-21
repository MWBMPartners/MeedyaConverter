#!/bin/bash
# =============================================================================
# MeedyaConverter — Bundle FFmpeg components script
# Copyright (c) 2026 MWBM Partners Ltd. All rights reserved.
# =============================================================================
#
# Downloads and extracts the FFmpeg toolkit (ffmpeg, ffprobe, ffplay) and
# stages the binaries at the path FFmpegBundleManager searches at runtime.
# Called by the release pipeline and by developers who want a self-contained
# local checkout.
#
# Usage:
#   scripts/bundle-ffmpeg.sh <DEST_DIR> [VERSION] [ARCHITECTURE]
#   scripts/bundle-ffmpeg.sh --refresh-checksums [VERSION] [ARCHITECTURE]
#
# Arguments:
#   DEST_DIR      Destination directory (required for the normal build path).
#                 Binaries are written to ${DEST_DIR}/ffmpeg, /ffprobe, /ffplay.
#   VERSION       FFmpeg version for the fallback source (default: 7.1.2).
#   ARCHITECTURE  Target arch: arm64 (default) or x86_64.
#
# Source policy (MeedyaDL-Tools FIRST)
# ------------------------------------
# Per the MeedyaSuite tooling policy, bundled tools are obtained from the
# first-party mirror **MeedyaSuite/MeedyaDL-Tools** in the first instance,
# pinned to an immutable dated release tag (MDLT_TAG). A third-party static
# build (osxexperts.net) is used ONLY as a fallback for (tool, arch)
# combinations the mirror does not yet publish.
#
# As of MDLT_TAG the mirror publishes `ffmpeg` for macOS arm64 only — it does
# NOT yet publish ffprobe/ffplay, nor a macOS x86_64 (Intel) ffmpeg. Those are
# tracked upstream in MeedyaSuite/MeedyaDL-Tools#15 (ffprobe/ffplay) and a
# related Intel-coverage note; until they land, the affected tools resolve via
# the verified fallback below.
#
# Supply-chain integrity (SECURITY.md F-011)
# ------------------------------------------
# HTTPS protects transport only, not source integrity, and the release
# pipeline code-signs + notarises whatever is downloaded under MWBM's
# Developer ID — so an unverified binary would ship Gatekeeper-approved.
# Every downloaded archive is therefore SHA-256-verified BEFORE it is
# unpacked, and the script FAILS CLOSED (no pin / mismatch => non-zero exit).
#
# Verification source, in order of preference:
#   1. MeedyaDL-Tools `SHA256SUMS` fetched from the SAME pinned release
#      (MeedyaSuite/MeedyaDL-Tools#19). This is the target end-state — the
#      trust root is the first-party tagged release; no hashes are hand-kept.
#   2. A locally-committed pin in `scripts/ffmpeg-checksums.txt`, keyed by the
#      full download URL. Used for fallback-source artefacts, and as a bridge
#      for MeedyaDL-Tools artefacts until #19 publishes SHA256SUMS.
#
# `--refresh-checksums` records local pins (trust-on-first-use) for whatever
# the sources serve now — a deliberate, separate command; it NEVER runs during
# a normal build (auto-recording would defeat the gate). A version/tag bump is
# a deliberate edit: change VERSION / MDLT_TAG, re-run --refresh-checksums (or
# rely on MeedyaDL-Tools SHA256SUMS once #19 lands), and commit the manifest.
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
    DEST_DIR="$(mktemp -d)"
    VERSION="${1:-7.1.2}"
    ARCH="${2:-arm64}"
    echo "[bundle-ffmpeg] REFRESH-CHECKSUMS mode  version=${VERSION} arch=${ARCH}"
    echo "[bundle-ffmpeg] WARNING: records trust-on-first-use hashes for whatever"
    echo "[bundle-ffmpeg]          the sources serve NOW — run from a trusted network"
    echo "[bundle-ffmpeg]          and review the recorded hashes before committing."
else
    DEST_DIR="${1:?usage: bundle-ffmpeg.sh <DEST_DIR> [VERSION] [ARCH]  |  --refresh-checksums [VERSION] [ARCH]}"
    VERSION="${2:-7.1.2}"
    ARCH="${3:-arm64}"
    echo "[bundle-ffmpeg] dest=${DEST_DIR} version=${VERSION} arch=${ARCH}"
fi

case "${ARCH}" in
    arm64|x86_64) ;;
    *) echo "[bundle-ffmpeg] unsupported arch: ${ARCH}" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# MeedyaDL-Tools primary source, pinned to an IMMUTABLE dated tag. Bump this
# deliberately (and re-pin/verify) to pick up newer mirrored binaries; do NOT
# point it at the rolling `latest` tag, which would break reproducibility and
# the supply-chain pin.
MDLT_REPO="MeedyaSuite/MeedyaDL-Tools"
MDLT_TAG="2026-07-02"
MDLT_BASE="https://github.com/${MDLT_REPO}/releases/download/${MDLT_TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKSUM_FILE="${SCRIPT_DIR}/ffmpeg-checksums.txt"

# Lazily-fetched MeedyaDL-Tools SHA256SUMS (empty until first needed;
# "MISSING" once we've confirmed the pinned release has none).
MDLT_SUMS_FILE=""

mkdir -p "${DEST_DIR}"

# ---------------------------------------------------------------------------
# Local pin manifest helpers (URL-keyed: `<url> <sha256>`)
# ---------------------------------------------------------------------------
expected_sha() {
    local url="$1"
    [[ -f "${CHECKSUM_FILE}" ]] || return 1
    awk -v u="${url}" '$1==u { print $2; found=1 } END { exit(found?0:1) }' "${CHECKSUM_FILE}"
}

record_sha() {
    local url="$1" sha="$2"
    touch "${CHECKSUM_FILE}"
    local tmp
    tmp="$(mktemp)"
    awk -v u="${url}" '!($1==u)' "${CHECKSUM_FILE}" > "${tmp}"
    printf '%s %s\n' "${url}" "${sha}" >> "${tmp}"
    { grep -E '^#' "${tmp}" || true; grep -vE '^#|^[[:space:]]*$' "${tmp}" | sort; } > "${CHECKSUM_FILE}"
    rm -f "${tmp}"
    echo "[bundle-ffmpeg] recorded pin: ${url}  ${sha}"
}

# ---------------------------------------------------------------------------
# Source mapping
# ---------------------------------------------------------------------------
# MeedyaDL-Tools asset name for (tool, arch), or empty if the mirror does not
# publish it yet. Extend as MeedyaSuite/MeedyaDL-Tools#15 / Intel coverage land.
mdlt_asset_for() {
    local tool="$1" arch="$2"
    case "${tool}-${arch}" in
        ffmpeg-arm64)  echo "ffmpeg-macos-aarch64.tar.gz" ;;
        # ffprobe-arm64 / ffplay-arm64 -> pending MeedyaDL-Tools#15
        # ffmpeg-x86_64 / ffprobe-x86_64 -> pending MeedyaDL-Tools Intel coverage
        *)             echo "" ;;
    esac
}

# Third-party fallback URL (osxexperts static builds).
osxexperts_url_for() {
    local tool="$1" arch="$2"
    local v="${VERSION//./}" suffix
    case "${arch}" in
        arm64)  suffix="arm" ;;
        x86_64) suffix="intel" ;;
    esac
    echo "https://www.osxexperts.net/${tool}${v}${suffix}.zip"
}

# ---------------------------------------------------------------------------
# MeedyaDL-Tools SHA256SUMS (preferred verification for mirror artefacts)
# ---------------------------------------------------------------------------
# Fetches the pinned release's SHA256SUMS once. Returns the expected hash for
# the named asset on stdout (rc 0), or rc 1 if no SHA256SUMS is published yet
# (MeedyaDL-Tools#19) or the asset is absent from it.
mdlt_expected_sha() {
    local asset="$1"
    if [[ -z "${MDLT_SUMS_FILE}" ]]; then
        local tmp
        tmp="$(mktemp)"
        if curl --fail --silent --show-error --location "${MDLT_BASE}/SHA256SUMS" -o "${tmp}" 2>/dev/null; then
            MDLT_SUMS_FILE="${tmp}"
            echo "[bundle-ffmpeg] using MeedyaDL-Tools SHA256SUMS from ${MDLT_TAG}" >&2
        else
            rm -f "${tmp}"
            MDLT_SUMS_FILE="MISSING"
            echo "[bundle-ffmpeg] note: ${MDLT_TAG} has no SHA256SUMS yet (MeedyaDL-Tools#19) — using local pins" >&2
        fi
    fi
    [[ "${MDLT_SUMS_FILE}" == "MISSING" ]] && return 1
    # SHA256SUMS format: `<sha256>  <filename>`
    awk -v f="${asset}" '$2==f { print $1; found=1 } END { exit(found?0:1) }' "${MDLT_SUMS_FILE}"
}

# ---------------------------------------------------------------------------
# Extraction (handles both .tar.gz mirror assets and .zip fallback assets)
# ---------------------------------------------------------------------------
extract_binary() {
    local archive="$1" tool="$2" workdir="$3"
    case "${archive}" in
        *.tar.gz|*.tgz) tar -xzf "${archive}" -C "${workdir}" ;;
        *.zip)          unzip -q "${archive}" -d "${workdir}" ;;
        *) echo "[bundle-ffmpeg] unknown archive type: ${archive}" >&2; exit 3 ;;
    esac
    local binary
    binary="$(find "${workdir}" -type f -name "${tool}" -perm -u+x | head -1)"
    if [[ -z "${binary}" ]]; then
        echo "[bundle-ffmpeg] ${tool} binary not found in ${archive}" >&2
        exit 3
    fi
    install -m 0755 "${binary}" "${DEST_DIR}/${tool}"
}

# Verify a freshly-downloaded archive against `expected`, or fail closed.
# In --refresh-checksums mode, records the pin instead (keyed by URL).
verify_or_record() {
    local url="$1" archive="$2" expected="$3" expected_from="$4"
    local actual
    actual="$(shasum -a 256 "${archive}" | awk '{print $1}')"

    if [[ "${REFRESH_CHECKSUMS}" -eq 1 ]]; then
        record_sha "${url}" "${actual}"
        return 0
    fi
    if [[ -z "${expected}" ]]; then
        echo "[bundle-ffmpeg] FATAL: no pinned SHA-256 for ${url} (F-011)" >&2
        echo "                Refusing to bundle an unverified binary." >&2
        echo "                Populate with: scripts/bundle-ffmpeg.sh --refresh-checksums ${VERSION} ${ARCH}" >&2
        echo "                (or wait for MeedyaDL-Tools#19 to publish SHA256SUMS)." >&2
        exit 6
    fi
    if [[ "${actual}" != "${expected}" ]]; then
        echo "[bundle-ffmpeg] FATAL: SHA-256 MISMATCH for ${url} (F-011)" >&2
        echo "                expected ${expected}  (${expected_from})" >&2
        echo "                actual   ${actual}" >&2
        echo "                The artefact changed since it was pinned — do NOT ship it." >&2
        exit 7
    fi
    echo "[bundle-ffmpeg] verified ${tool:-archive} (${expected_from}): ${actual}"
}

# ---------------------------------------------------------------------------
# Fetch one tool: MeedyaDL-Tools first, verified fallback otherwise.
# ---------------------------------------------------------------------------
fetch_tool() {
    local tool="$1"
    local tmp; tmp="$(mktemp -d)"
    local asset url archive expected expected_from

    asset="$(mdlt_asset_for "${tool}" "${ARCH}")"
    if [[ -n "${asset}" ]]; then
        url="${MDLT_BASE}/${asset}"
        archive="${tmp}/${asset}"
        echo "[bundle-ffmpeg] fetching ${tool} from MeedyaDL-Tools ${MDLT_TAG} (${asset})"
        if curl --fail --silent --show-error --location "${url}" -o "${archive}"; then
            # Prefer the mirror's own SHA256SUMS; bridge to the local pin.
            if expected="$(mdlt_expected_sha "${asset}")"; then
                expected_from="MeedyaDL-Tools SHA256SUMS"
            else
                expected="$(expected_sha "${url}" || true)"
                expected_from="local pin"
            fi
            verify_or_record "${url}" "${archive}" "${expected}" "${expected_from}"
            extract_binary "${archive}" "${tool}" "${tmp}"
            rm -rf "${tmp}"
            return 0
        fi
        echo "[bundle-ffmpeg] MeedyaDL-Tools asset ${asset} unavailable — falling back" >&2
    fi

    # Fallback source (third-party static build).
    url="$(osxexperts_url_for "${tool}" "${ARCH}")"
    archive="${tmp}/${tool}.zip"
    echo "[bundle-ffmpeg] fetching ${tool} from fallback ${url}"
    if ! curl --fail --silent --show-error --location "${url}" -o "${archive}"; then
        echo "[bundle-ffmpeg] FATAL: cannot obtain a verified ${tool} for ${ARCH} (F-011)." >&2
        echo "                MeedyaDL-Tools has no ${tool}/${ARCH} asset yet" >&2
        echo "                (pending MeedyaSuite/MeedyaDL-Tools#15 for ffprobe/ffplay," >&2
        echo "                 and Intel coverage for x86_64), and the fallback download" >&2
        echo "                failed: ${url}" >&2
        echo "                Refusing to continue — land the mirror asset, or populate a" >&2
        echo "                working fallback + pin via --refresh-checksums." >&2
        rm -rf "${tmp}"
        exit 6
    fi
    expected="$(expected_sha "${url}" || true)"
    verify_or_record "${url}" "${archive}" "${expected}" "local pin"
    extract_binary "${archive}" "${tool}" "${tmp}"
    rm -rf "${tmp}"
}

fetch_tool "ffmpeg"
fetch_tool "ffprobe"
fetch_tool "ffplay"

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

[[ "${MDLT_SUMS_FILE}" != "" && "${MDLT_SUMS_FILE}" != "MISSING" ]] && rm -f "${MDLT_SUMS_FILE}"

if [[ "${REFRESH_CHECKSUMS}" -eq 1 ]]; then
    echo "[bundle-ffmpeg] checksums refreshed in ${CHECKSUM_FILE}"
    echo "[bundle-ffmpeg] review the diff and commit it alongside the version/tag bump."
    rm -rf "${DEST_DIR}"
else
    echo "[bundle-ffmpeg] all three components staged (SHA-256-verified) at ${DEST_DIR}"
fi
