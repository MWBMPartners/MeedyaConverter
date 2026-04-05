#!/bin/bash
set -euo pipefail
# ============================================================================
# MeedyaConverter — Notarization Script
# Copyright © 2026 MWBM Partners Ltd. All rights reserved.
# ============================================================================
#
# Purpose:
#   Submits a signed .app bundle or .dmg to Apple's notarization service,
#   waits for the result, and staples the notarization ticket on success.
#
# Usage:
#   ./scripts/notarize.sh <APP_PATH_OR_DMG_PATH>
#
# Required environment variables:
#   APPLE_ID       — Apple ID email for notarization
#   APPLE_PASSWORD — App-specific password for the Apple ID
#   APPLE_TEAM_ID  — Apple Developer Team ID
#
# Notes:
#   - The artifact must be signed with a Developer ID certificate and
#     hardened runtime before submission.
#   - Notarization timeout is 15 minutes (900 seconds).
#   - On failure, the notarization log is retrieved and printed.
# ============================================================================

# ---------------------------------------------------------------------------
# Colour helpers for log output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No colour

log_info()  { echo -e "${GREEN}[notarize]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[notarize]${NC} $*"; }
log_error() { echo -e "${RED}[notarize]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
NOTARIZATION_TIMEOUT=900  # 15 minutes in seconds

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ARTIFACT_PATH="${1:-}"

if [ -z "$ARTIFACT_PATH" ]; then
    log_error "Usage: $0 <APP_PATH_OR_DMG_PATH>"
    log_error "  Provide the path to a .app bundle or .dmg file."
    exit 1
fi

if [ ! -e "$ARTIFACT_PATH" ]; then
    log_error "Artifact does not exist: $ARTIFACT_PATH"
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
: "${APPLE_ID:?Error: APPLE_ID environment variable is not set}"
: "${APPLE_PASSWORD:?Error: APPLE_PASSWORD environment variable is not set}"
: "${APPLE_TEAM_ID:?Error: APPLE_TEAM_ID environment variable is not set}"

# ---------------------------------------------------------------------------
# Prepare the submission artifact
# ---------------------------------------------------------------------------
# notarytool accepts .dmg, .pkg, and .zip files directly.
# For .app bundles, we need to create a zip archive first.
# ---------------------------------------------------------------------------
SUBMIT_PATH="$ARTIFACT_PATH"
CLEANUP_ZIP=false

if [[ "$ARTIFACT_PATH" == *.app ]]; then
    log_info "Creating zip archive of app bundle for submission..."
    ZIP_PATH="${ARTIFACT_PATH%.app}.zip"
    ditto -c -k --sequesterRsrc --keepParent "$ARTIFACT_PATH" "$ZIP_PATH"
    SUBMIT_PATH="$ZIP_PATH"
    CLEANUP_ZIP=true
    log_info "Created: $ZIP_PATH"
fi

# ---------------------------------------------------------------------------
# Submit for notarization
# ---------------------------------------------------------------------------
log_info "Submitting for notarization: $SUBMIT_PATH"
log_info "Apple ID: $APPLE_ID"
log_info "Team ID:  $APPLE_TEAM_ID"

SUBMISSION_OUTPUT=$(xcrun notarytool submit "$SUBMIT_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --output-format json \
    2>&1)

# Extract the submission ID from the JSON output
SUBMISSION_ID=$(echo "$SUBMISSION_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('id', ''))
except:
    print('')
")

if [ -z "$SUBMISSION_ID" ]; then
    log_error "Failed to submit for notarization."
    log_error "Output: $SUBMISSION_OUTPUT"
    exit 1
fi

log_info "Submission ID: $SUBMISSION_ID"

# ---------------------------------------------------------------------------
# Wait for notarization to complete
# ---------------------------------------------------------------------------
log_info "Waiting for notarization (timeout: ${NOTARIZATION_TIMEOUT}s)..."

WAIT_OUTPUT=$(xcrun notarytool wait "$SUBMISSION_ID" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --timeout "$NOTARIZATION_TIMEOUT" \
    --output-format json \
    2>&1)

# Extract the status from the JSON output
NOTARIZATION_STATUS=$(echo "$WAIT_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('status', 'Unknown'))
except:
    print('Unknown')
")

log_info "Notarization status: $NOTARIZATION_STATUS"

# ---------------------------------------------------------------------------
# Handle the result
# ---------------------------------------------------------------------------
if [ "$NOTARIZATION_STATUS" = "Accepted" ]; then
    log_info "Notarization SUCCEEDED."

    # Clean up the temporary zip if we created one
    if [ "$CLEANUP_ZIP" = true ] && [ -f "$SUBMIT_PATH" ]; then
        rm -f "$SUBMIT_PATH"
        log_info "Cleaned up temporary zip: $SUBMIT_PATH"
    fi

    # Staple the notarization ticket to the original artifact
    log_info "Stapling notarization ticket to: $ARTIFACT_PATH"
    if xcrun stapler staple "$ARTIFACT_PATH" 2>&1; then
        log_info "Stapling completed successfully."
    else
        log_warn "Stapling failed. The artifact is still notarized but the"
        log_warn "ticket is not embedded. Users will need network access for"
        log_warn "Gatekeeper verification on first launch."
    fi

    # Verify the staple
    log_info "Verifying stapled ticket..."
    if xcrun stapler validate "$ARTIFACT_PATH" 2>&1; then
        log_info "Stapled ticket is valid."
    else
        log_warn "Staple validation returned a warning (artifact is still notarized)."
    fi

    log_info "Notarization and stapling completed successfully."
else
    log_error "Notarization FAILED with status: $NOTARIZATION_STATUS"

    # Retrieve and display the notarization log for debugging
    log_error "Retrieving notarization log..."
    xcrun notarytool log "$SUBMISSION_ID" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        2>&1 || true

    # Clean up the temporary zip if we created one
    if [ "$CLEANUP_ZIP" = true ] && [ -f "$SUBMIT_PATH" ]; then
        rm -f "$SUBMIT_PATH"
    fi

    exit 1
fi
