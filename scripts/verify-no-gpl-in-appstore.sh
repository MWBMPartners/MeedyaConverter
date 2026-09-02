#!/usr/bin/env bash
# =============================================================================
# verify-no-gpl-in-appstore.sh — App Store GPL tripwire (issue #494 / DR-0001)
# Copyright (c) 2026 MWBM Partners Ltd. All rights reserved.
# =============================================================================
#
# Fails the build if a GPL-licensed helper binary is present inside an .app
# bundle that is destined for the App Store.
#
# Why this exists
# ---------------
# The optical-disc imaging feature (#492/#495) shells out to GPL command-line
# tools (cdrdao GPLv2, GNU ddrescue GPLv3, wodim GPLv2, cdparanoia GPLv2).
# DR-0001 permits those ONLY in the Direct-distribution .dmg — never in an App
# Store build, on two independent grounds: the GPL is incompatible with the App
# Store terms, and the feature cannot function in the App Sandbox anyway (no
# raw-device entitlement).
#
# The primary defence is the manifest/test layer
# (ToolBundleManifest.isAppStoreSafe + its regression test). This script is the
# second line: it inspects the *assembled bundle*, so it catches a GPL binary
# that a future DMG-bundling step copies in without going through the manifest.
#
# Usage:
#   scripts/verify-no-gpl-in-appstore.sh <path-to-.app>
#
# Exit codes:
#   0  clean — no GPL helper found
#   1  usage error / bundle not found
#   7  a GPL binary was found in the App Store bundle (fail the build)
# =============================================================================

set -euo pipefail

APP_PATH="${1:?usage: verify-no-gpl-in-appstore.sh <path-to-.app>}"

if [ ! -d "${APP_PATH}" ]; then
    echo "::error::verify-no-gpl-in-appstore: bundle not found: ${APP_PATH}" >&2
    exit 1
fi

# Basenames of the GPL command-line tools this project may bundle for Direct
# builds. Keep in step with the GPL entries drafted in DR-0001 and with
# ToolBundleManifest. `readom`/`icedax` are cdrkit siblings of `wodim`.
GPL_BINARIES=(
    cdrdao
    ddrescue
    wodim
    readom
    icedax
    cdparanoia
    cd-paranoia
)

found=0
for name in "${GPL_BINARIES[@]}"; do
    # -type f so a directory that merely shares the name does not trip it;
    # search the whole bundle, not just Contents/Helpers, in case a future
    # step stages tools elsewhere.
    while IFS= read -r hit; do
        echo "::error::verify-no-gpl-in-appstore: GPL binary '${name}' found in an App Store bundle at: ${hit}" >&2
        echo "  GPL tools are Direct-distribution only (DR-0001). Exclude them from the App Store build." >&2
        found=1
    done < <(find "${APP_PATH}" -type f -name "${name}" 2>/dev/null)
done

if [ "${found}" -ne 0 ]; then
    exit 7
fi

echo "[verify-no-gpl-in-appstore] OK — no GPL helper binary in ${APP_PATH}"
