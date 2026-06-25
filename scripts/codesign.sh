#!/bin/bash
set -euo pipefail
# ============================================================================
# MeedyaConverter — Code Signing Script
# Copyright © 2026 MWBM Partners Ltd. All rights reserved.
# ============================================================================
#
# Purpose:
#   Signs the MeedyaConverter app bundle and CLI binary with a Developer ID
#   certificate, using hardened runtime and the appropriate entitlements.
#
# Usage:
#   ./scripts/codesign.sh <APP_PATH> [SIGNING_IDENTITY]
#
# Environment variables (used as fallbacks):
#   APPLE_SIGNING_IDENTITY — The signing identity (e.g. "Developer ID Application: ...")
#
# Notes:
#   - Apple recommends signing each binary individually rather than using
#     --deep. This script recursively finds and signs all nested binaries,
#     frameworks, and dylibs before signing the top-level bundle.
#   - Hardened runtime (--options runtime) is required for notarization.
# ============================================================================

# ---------------------------------------------------------------------------
# Colour helpers for log output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No colour

log_info()  { echo -e "${GREEN}[codesign]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[codesign]${NC} $*"; }
log_error() { echo -e "${RED}[codesign]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
APP_PATH="${1:-}"
SIGNING_IDENTITY="${2:-${APPLE_SIGNING_IDENTITY:-}}"

if [ -z "$APP_PATH" ]; then
    log_error "Usage: $0 <APP_PATH> [SIGNING_IDENTITY]"
    log_error "  APP_PATH          Path to the .app bundle or binary to sign"
    log_error "  SIGNING_IDENTITY  Signing identity (or set APPLE_SIGNING_IDENTITY env var)"
    exit 1
fi

if [ -z "$SIGNING_IDENTITY" ]; then
    log_error "No signing identity provided."
    log_error "Pass it as the second argument or set APPLE_SIGNING_IDENTITY."
    exit 1
fi

if [ ! -e "$APP_PATH" ]; then
    log_error "Path does not exist: $APP_PATH"
    exit 1
fi

# ---------------------------------------------------------------------------
# Determine the entitlements file to use
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default entitlements for the GUI app
GUI_ENTITLEMENTS="$PROJECT_ROOT/Sources/MeedyaConverter/Resources/MeedyaConverter.entitlements"
CLI_ENTITLEMENTS="$PROJECT_ROOT/Sources/meedya-convert/Resources/meedya-convert.entitlements"

# ---------------------------------------------------------------------------
# sign_binary — Sign a single binary or bundle
# ---------------------------------------------------------------------------
# Arguments:
#   $1 — Path to the binary or bundle
#   $2 — Path to the entitlements file (optional, omit for frameworks/dylibs)
# ---------------------------------------------------------------------------
sign_binary() {
    local target="$1"
    local entitlements="${2:-}"

    local sign_args=(
        --sign "$SIGNING_IDENTITY"
        --options runtime
        --force
        --timestamp
    )

    if [ -n "$entitlements" ] && [ -f "$entitlements" ]; then
        sign_args+=(--entitlements "$entitlements")
    fi

    log_info "Signing: $target"
    codesign "${sign_args[@]}" "$target"
}

# ---------------------------------------------------------------------------
# is_macho_executable — Return 0 iff $1 is a Mach-O binary (executable, dylib,
# or bundle). Used to filter out data resources (.nib, .strings, .png, .icns,
# .json, .plist, fonts, etc.) that must never be passed to codesign as a
# standalone target. We deliberately use `file` rather than the extension or
# the executable bit because:
#   - bundled FFmpeg/HDR helpers may have any name (no extension)
#   - .nib bundles can carry the +x bit on extracted contents
#   - some Mach-O dylibs ship without the +x bit
# ---------------------------------------------------------------------------
is_macho_executable() {
    local target="$1"
    # `file -b` prints just the description. Mach-O outputs always begin with
    # "Mach-O" and cover thin + fat (universal) binaries, dylibs, and bundles.
    local description
    description="$(file -b "$target" 2>/dev/null || true)"
    [[ "$description" == Mach-O* ]]
}

# ---------------------------------------------------------------------------
# sign_nested_executables — Recursively sign every Mach-O executable under a
# directory with hardened runtime, a secure timestamp, and the supplied
# entitlements. Required so bundled helpers (FFmpeg, ffprobe, ffplay, HDR
# tooling, etc.) pass notarisation — Apple notarisation rejects any nested
# Mach-O that lacks `--options runtime` even if the parent bundle is signed.
# ---------------------------------------------------------------------------
# Arguments:
#   $1 — Directory to scan (skipped silently if it does not exist)
#   $2 — Path to entitlements file (optional)
# ---------------------------------------------------------------------------
sign_nested_executables() {
    local scan_dir="$1"
    local entitlements="${2:-}"

    if [ ! -d "$scan_dir" ]; then
        return 0
    fi

    log_info "Scanning for nested Mach-O executables in: $scan_dir"

    # Use a NUL-delimited stream so paths with spaces survive intact, and a
    # process-substitution `< <(...)` so the loop runs in the current shell
    # (a piped `while` runs in a subshell and would lose any state we set).
    local found_any=0
    while IFS= read -r -d '' candidate; do
        # Skip files inside *.framework — frameworks are signed as a unit
        # later by sign_binary on the framework bundle itself; signing the
        # inner Mach-O directly first is fine, but we already handle
        # frameworks in their own step, so avoid double work here.
        case "$candidate" in
            */*.framework/*) continue ;;
        esac

        if is_macho_executable "$candidate"; then
            sign_binary "$candidate" "$entitlements"
            found_any=1
        fi
    done < <(find "$scan_dir" -type f -print0)

    if [ "$found_any" -eq 0 ]; then
        log_info "No nested Mach-O executables found under $scan_dir"
    fi
}

# ---------------------------------------------------------------------------
# Sign an app bundle (recursively, inside-out)
# ---------------------------------------------------------------------------
sign_app_bundle() {
    local app_path="$1"

    log_info "Signing app bundle: $app_path"
    log_info "Using identity: $SIGNING_IDENTITY"

    # ---------------------------------------------------------------------
    # Inside-out signing order (notarisation requirement):
    #   1. Nested Mach-O executables under Contents/Helpers and
    #      Contents/Resources (FFmpeg, ffprobe, ffplay, HDR helpers, …)
    #   2. Nested frameworks and dylibs
    #   3. Nested .app bundles (XPC-like sub-apps)
    #   4. The main executable
    #   5. The top-level .app bundle (seals the lot)
    # Each Mach-O is signed with --options runtime + --timestamp +
    # --entitlements, which is what notarytool actually checks.
    # ---------------------------------------------------------------------

    # Step 1: Sign nested helpers/resources executables FIRST (inside-out).
    # Apple notarisation rejects any Mach-O inside the bundle that lacks the
    # hardened runtime flag, even if the outer bundle is correctly signed.
    # This step is what unblocks bundled FFmpeg + HDR helper notarisation.
    sign_nested_executables "$app_path/Contents/Helpers"   "$GUI_ENTITLEMENTS"
    sign_nested_executables "$app_path/Contents/Resources" "$GUI_ENTITLEMENTS"

    # Step 2: Sign all nested frameworks and dylibs
    if [ -d "$app_path/Contents/Frameworks" ]; then
        log_info "Signing nested frameworks..."
        find "$app_path/Contents/Frameworks" -type f \( -name "*.dylib" -o -perm +111 \) | while read -r binary; do
            sign_binary "$binary"
        done

        # Sign framework bundles themselves
        find "$app_path/Contents/Frameworks" -name "*.framework" -type d | while read -r framework; do
            sign_binary "$framework"
        done
    fi

    # Step 3: Sign all nested helpers and XPC services under Contents/Library
    # (legacy XPC location — distinct from the Contents/Helpers scan above).
    if [ -d "$app_path/Contents/Library" ]; then
        log_info "Signing nested helpers (Contents/Library)..."
        find "$app_path/Contents/Library" -type f -perm +111 | while read -r helper; do
            sign_binary "$helper"
        done
    fi

    # Step 4: Sign any nested app bundles
    find "$app_path/Contents" -name "*.app" -type d -not -path "$app_path" | while read -r nested_app; do
        sign_binary "$nested_app"
    done

    # Step 5: Sign the main executable with GUI entitlements
    local main_executable="$app_path/Contents/MacOS/MeedyaConverter"
    if [ -f "$main_executable" ]; then
        sign_binary "$main_executable" "$GUI_ENTITLEMENTS"
    fi

    # Step 6: Sign the top-level app bundle
    sign_binary "$app_path" "$GUI_ENTITLEMENTS"

    log_info "App bundle signing complete."
}

# ---------------------------------------------------------------------------
# Sign a standalone binary (CLI tool)
# ---------------------------------------------------------------------------
sign_standalone_binary() {
    local binary_path="$1"

    log_info "Signing standalone binary: $binary_path"
    log_info "Using identity: $SIGNING_IDENTITY"

    sign_binary "$binary_path" "$CLI_ENTITLEMENTS"

    log_info "Standalone binary signing complete."
}

# ---------------------------------------------------------------------------
# Main: Determine what we're signing and dispatch
# ---------------------------------------------------------------------------
if [[ "$APP_PATH" == *.app ]]; then
    sign_app_bundle "$APP_PATH"
elif [ -f "$APP_PATH" ]; then
    sign_standalone_binary "$APP_PATH"
else
    log_error "Unsupported target: $APP_PATH"
    log_error "Provide a .app bundle or a binary file."
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify the signature
# ---------------------------------------------------------------------------
log_info "Verifying signature..."
if codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1; then
    log_info "Signature verification passed."
else
    log_error "Signature verification FAILED."
    exit 1
fi

# ---------------------------------------------------------------------------
# Display signing information
# ---------------------------------------------------------------------------
log_info "Signature details:"
codesign --display --verbose=2 "$APP_PATH" 2>&1 || true

log_info "Code signing completed successfully."
