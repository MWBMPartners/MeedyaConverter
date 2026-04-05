#!/usr/bin/env bash
# =============================================================================
# MeedyaConverter — Create DMG Installer
# Copyright (c) 2026 MWBM Partners Ltd. All rights reserved.
# Proprietary and confidential. Unauthorized copying or distribution
# of this file, via any medium, is strictly prohibited.
# =============================================================================
#
# Usage:
#   ./scripts/create-dmg.sh <app_path> <version>
#
# Description:
#   Creates a compressed DMG disk image containing the .app bundle and an
#   /Applications symlink for drag-install. Uses hdiutil on macOS.
#
# Arguments:
#   app_path  Path to the .app bundle (e.g., "MeedyaConverter.app")
#   version   Semantic version number (e.g., "0.1.0")
#
# Environment Variables (optional):
#   DMG_BACKGROUND   Path to a background image for the DMG window
#   DMG_VOLUME_ICON  Path to a .icns file to use as the volume icon
#   DMG_OUTPUT_DIR   Directory for the output DMG (default: current directory)
#
# Output:
#   Prints the path to the created DMG file on stdout.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if [ $# -lt 2 ]; then
    echo "Usage: $0 <app_path> <version>" >&2
    exit 1
fi

APP_PATH="$1"
VERSION="$2"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found at '${APP_PATH}'" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify we are running on macOS (hdiutil is macOS-only)
# ---------------------------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
    echo "Error: DMG creation requires macOS (hdiutil)." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
APP_NAME=$(basename "$APP_PATH" .app)
VOLUME_NAME="${APP_NAME} ${VERSION}"
DMG_OUTPUT_DIR="${DMG_OUTPUT_DIR:-.}"
DMG_FILENAME="${APP_NAME}-${VERSION}-macOS.dmg"
DMG_PATH="${DMG_OUTPUT_DIR}/${DMG_FILENAME}"
STAGING_DIR=$(mktemp -d -t dmg-staging)

# Optional customisation
DMG_BACKGROUND="${DMG_BACKGROUND:-}"
DMG_VOLUME_ICON="${DMG_VOLUME_ICON:-}"

echo "Creating DMG: ${DMG_FILENAME}"
echo "  App bundle:   ${APP_PATH}"
echo "  Volume name:  ${VOLUME_NAME}"
echo "  Output:       ${DMG_PATH}"

# ---------------------------------------------------------------------------
# Stage the DMG contents
# ---------------------------------------------------------------------------
echo "Staging DMG contents..."

# Copy the .app bundle into the staging directory
cp -R "$APP_PATH" "${STAGING_DIR}/"

# Create the /Applications symlink for drag-install
ln -s /Applications "${STAGING_DIR}/Applications"

# Copy optional background image
if [ -n "$DMG_BACKGROUND" ] && [ -f "$DMG_BACKGROUND" ]; then
    mkdir -p "${STAGING_DIR}/.background"
    cp "$DMG_BACKGROUND" "${STAGING_DIR}/.background/background.png"
    echo "  Background:   ${DMG_BACKGROUND}"
fi

# ---------------------------------------------------------------------------
# Create the DMG (compressed UDZO format)
# ---------------------------------------------------------------------------
echo "Running hdiutil create..."

# Remove any existing DMG at the output path
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# ---------------------------------------------------------------------------
# Set the volume icon if provided
# ---------------------------------------------------------------------------
if [ -n "$DMG_VOLUME_ICON" ] && [ -f "$DMG_VOLUME_ICON" ]; then
    echo "Setting volume icon..."

    # Mount the DMG read-write temporarily to set the icon
    MOUNT_POINT=$(mktemp -d -t dmg-mount)
    hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -readwrite -noverify -noautoopen

    # Copy the icon file
    cp "$DMG_VOLUME_ICON" "${MOUNT_POINT}/.VolumeIcon.icns"

    # Set the custom icon attribute on the volume
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true

    # Unmount
    hdiutil detach "$MOUNT_POINT" -force
    rm -rf "$MOUNT_POINT"

    # Convert back to compressed read-only format
    TEMP_DMG="${DMG_PATH}.tmp"
    mv "$DMG_PATH" "$TEMP_DMG"
    hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
    rm -f "$TEMP_DMG"

    echo "  Volume icon:  ${DMG_VOLUME_ICON}"
fi

# ---------------------------------------------------------------------------
# Clean up staging directory
# ---------------------------------------------------------------------------
rm -rf "$STAGING_DIR"

# ---------------------------------------------------------------------------
# Report results
# ---------------------------------------------------------------------------
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')
echo ""
echo "DMG created successfully:"
echo "  Path: ${DMG_PATH}"
echo "  Size: ${DMG_SIZE}"

# Output the DMG path (for use by CI scripts)
echo "$DMG_PATH"
