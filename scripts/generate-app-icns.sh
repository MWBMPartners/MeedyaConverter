#!/usr/bin/env bash
# =============================================================================
# generate-app-icns.sh — assemble MeedyaConverter.icns from AppIcon.appiconset
# Copyright © 2026 MWBM Partners Ltd. All rights reserved.
# =============================================================================
#
# Why this exists
# ---------------
# The repository ships icon PNGs at every standard macOS size
# (16/32/64/128/256/512/1024) under
# Sources/MeedyaConverter/Resources/Assets.xcassets/AppIcon.appiconset.
# That's enough for SwiftPM / Xcode to render the app icon at runtime,
# BUT the **App Store Connect ITMS validator** statically inspects the
# uploaded bundle and rejects with ITMS-90236 (#390) if there is no
# Contents/Resources/<CFBundleIconFile>.icns containing the full
# Retina-pair set including the 512@2x slot.
#
# Direct DMG distribution doesn't have an App Store validator, but
# shipping the .icns there too means Finder / Get Info / Spotlight
# pick up a sharper rendering in edge cases that bypass the xcassets
# lookup. So both the release.yml (Direct) and testflight.yml (App
# Store Lite) workflows invoke this script before bundle assembly.
#
# Why we generate at build time rather than commit the binary
# -----------------------------------------------------------
# The .icns is fully deterministic given the PNG inputs, and adding
# a ~250 KB binary blob to the repo just to commit something derived
# from sources already committed feels backwards. Generating in CI
# also means a maintainer editing one of the PNGs in AppIcon.appiconset
# automatically updates the bundle's .icns on the next release run
# without having to remember to re-run iconutil locally.
#
# What this script does
# ---------------------
# 1. Maps each AppIcon.appiconset PNG to one or two iconset slot
#    filenames per the macOS iconset convention (16x16, 16x16@2x,
#    32x32, 32x32@2x, ..., 512x512, 512x512@2x).
# 2. Runs `iconutil --convert icns` on the assembled iconset
#    directory.
# 3. Writes the output .icns to the path passed as $1 (default:
#    Sources/MeedyaConverter/Resources/MeedyaConverter.icns; in CI
#    the workflows pass a temp path that lives only for the run).
#
# Usage
# -----
#   ./scripts/generate-app-icns.sh                          # default output path
#   ./scripts/generate-app-icns.sh /tmp/MeedyaConverter.icns # explicit output
#
# Requirements: macOS with `iconutil` available (any macOS — it ships
# in the base system).
# =============================================================================

set -euo pipefail

# Source: where the per-size PNGs live.
APPICONSET="Sources/MeedyaConverter/Resources/Assets.xcassets/AppIcon.appiconset"

# Output: where the assembled .icns goes (caller-overridable).
OUTPUT_ICNS="${1:-Sources/MeedyaConverter/Resources/MeedyaConverter.icns}"

# Sanity checks: all required PNGs must exist.
REQUIRED=(
    "icon_16x16.png"
    "icon_32x32.png"
    "icon_64x64.png"
    "icon_128x128.png"
    "icon_256x256.png"
    "icon_512x512.png"
    "icon_1024x1024.png"
)
for f in "${REQUIRED[@]}"; do
    if [[ ! -f "${APPICONSET}/${f}" ]]; then
        echo "::error::Missing required source PNG: ${APPICONSET}/${f}" >&2
        exit 1
    fi
done

if ! command -v iconutil >/dev/null 2>&1; then
    echo "::error::iconutil not found — this script requires macOS" >&2
    exit 1
fi

# Scratch dir, auto-cleaned at exit.
SCRATCH="$(mktemp -d -t meedyaconverter-iconset)"
trap 'rm -rf "${SCRATCH}"' EXIT
ICONSET="${SCRATCH}/MeedyaConverter.iconset"
mkdir -p "${ICONSET}"

# Map source PNGs (named by pixel size) into the canonical iconutil
# slot names. The doubled-pixel sizes serve as both the @2x of the
# smaller logical size AND the base of the next logical size, so
# several source PNGs map to two destination slot names.
cp "${APPICONSET}/icon_16x16.png"     "${ICONSET}/icon_16x16.png"        # 16
cp "${APPICONSET}/icon_32x32.png"     "${ICONSET}/icon_16x16@2x.png"     # 32
cp "${APPICONSET}/icon_32x32.png"     "${ICONSET}/icon_32x32.png"        # 32
cp "${APPICONSET}/icon_64x64.png"     "${ICONSET}/icon_32x32@2x.png"     # 64
cp "${APPICONSET}/icon_128x128.png"   "${ICONSET}/icon_128x128.png"      # 128
cp "${APPICONSET}/icon_256x256.png"   "${ICONSET}/icon_128x128@2x.png"   # 256
cp "${APPICONSET}/icon_256x256.png"   "${ICONSET}/icon_256x256.png"      # 256
cp "${APPICONSET}/icon_512x512.png"   "${ICONSET}/icon_256x256@2x.png"   # 512
cp "${APPICONSET}/icon_512x512.png"   "${ICONSET}/icon_512x512.png"      # 512
cp "${APPICONSET}/icon_1024x1024.png" "${ICONSET}/icon_512x512@2x.png"   # 1024 — the slot ITMS-90236 specifically checks for

mkdir -p "$(dirname "${OUTPUT_ICNS}")"
iconutil --convert icns "${ICONSET}" --output "${OUTPUT_ICNS}"

echo "Generated: ${OUTPUT_ICNS} (size: $(stat -f '%z' "${OUTPUT_ICNS}") bytes)"
