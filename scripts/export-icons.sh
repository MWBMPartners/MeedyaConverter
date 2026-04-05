#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
#  MeedyaConverter — Icon Export Script
#  Copyright © 2026 MWBM Partners Ltd. All rights reserved.
#
#  Generates PNG exports from the SVG icon mark at all required sizes
#  for macOS, iOS, web, Windows, Linux, and Android platforms.
#
#  Dependencies (one of):
#    - sips   (macOS built-in, uses intermediate PNG)
#    - rsvg-convert (from librsvg: brew install librsvg)
#
#  Usage:
#    ./scripts/export-icons.sh [--tool sips|rsvg]
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ICONS_DIR="$PROJECT_ROOT/assets/branding/brandkit/icons"
SOURCE_SVG="$PROJECT_ROOT/assets/branding/brandkit/logos/mark/meedyaconverter-mark.svg"

# ── Detect or override tool ──────────────────────────────────────────
TOOL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TOOL" ]]; then
  if command -v rsvg-convert &>/dev/null; then
    TOOL="rsvg"
  elif command -v sips &>/dev/null; then
    TOOL="sips"
  else
    echo "Error: Neither rsvg-convert nor sips found." >&2
    echo "Install librsvg (brew install librsvg) or run on macOS for sips." >&2
    exit 1
  fi
fi

echo "Using tool: $TOOL"
echo "Source SVG: $SOURCE_SVG"

if [[ ! -f "$SOURCE_SVG" ]]; then
  echo "Error: Source SVG not found at $SOURCE_SVG" >&2
  exit 1
fi

# ── Helper: convert SVG to PNG at given size ─────────────────────────
convert_icon() {
  local size="$1"
  local output="$2"

  mkdir -p "$(dirname "$output")"

  if [[ "$TOOL" == "rsvg" ]]; then
    rsvg-convert -w "$size" -h "$size" "$SOURCE_SVG" -o "$output"
  elif [[ "$TOOL" == "sips" ]]; then
    # sips cannot read SVG directly; use a temporary high-res PNG
    # generated once, then resample from it.
    if [[ ! -f "$TMPDIR/mc-icon-master.png" ]]; then
      # Use qlmanage to render SVG to PNG on macOS
      qlmanage -t -s 1024 -o "$TMPDIR" "$SOURCE_SVG" 2>/dev/null || true
      local ql_output="$TMPDIR/$(basename "$SOURCE_SVG").png"
      if [[ -f "$ql_output" ]]; then
        mv "$ql_output" "$TMPDIR/mc-icon-master.png"
      else
        echo "Warning: qlmanage failed. Trying rsvg-convert as fallback..." >&2
        if command -v rsvg-convert &>/dev/null; then
          rsvg-convert -w 1024 -h 1024 "$SOURCE_SVG" -o "$TMPDIR/mc-icon-master.png"
        else
          echo "Error: Cannot render SVG. Install librsvg: brew install librsvg" >&2
          exit 1
        fi
      fi
    fi
    cp "$TMPDIR/mc-icon-master.png" "$output"
    sips -z "$size" "$size" "$output" --out "$output" &>/dev/null
  fi

  echo "  Created: $output (${size}x${size})"
}

# ── macOS icon sizes (pt x scale = px) ───────────────────────────────
echo ""
echo "=== macOS ==="
MACOS_DIR="$ICONS_DIR/macos"
for size in 16 32 64 128 256 512 1024; do
  convert_icon "$size" "$MACOS_DIR/icon_${size}x${size}.png"
done

# ── iOS icon sizes ───────────────────────────────────────────────────
echo ""
echo "=== iOS ==="
IOS_DIR="$ICONS_DIR/ios"
for size in 20 29 40 58 60 76 80 87 120 152 167 180 1024; do
  convert_icon "$size" "$IOS_DIR/icon_${size}x${size}.png"
done

# ── Web icons ────────────────────────────────────────────────────────
echo ""
echo "=== Web ==="
WEB_DIR="$ICONS_DIR/web"
for size in 16 32 48 96 144 192 512; do
  convert_icon "$size" "$WEB_DIR/icon-${size}.png"
done

# ── Windows icons ────────────────────────────────────────────────────
echo ""
echo "=== Windows ==="
WIN_DIR="$ICONS_DIR/windows"
for size in 16 24 32 48 64 256; do
  convert_icon "$size" "$WIN_DIR/icon_${size}x${size}.png"
done

# ── Linux icons ──────────────────────────────────────────────────────
echo ""
echo "=== Linux ==="
LINUX_DIR="$ICONS_DIR/linux"
for size in 16 22 24 32 48 64 128 256 512; do
  convert_icon "$size" "$LINUX_DIR/icon_${size}x${size}.png"
done

# ── Android adaptive icon layers ─────────────────────────────────────
echo ""
echo "=== Android ==="
ANDROID_DIR="$ICONS_DIR/android"
for size in 48 72 96 144 192; do
  convert_icon "$size" "$ANDROID_DIR/icon_${size}x${size}.png"
done

# ── Copy into Xcode asset catalog ────────────────────────────────────
echo ""
echo "=== Xcode Asset Catalog ==="
APPICONSET="$PROJECT_ROOT/Sources/MeedyaConverter/Resources/Assets.xcassets/AppIcon.appiconset"
cp "$SOURCE_SVG" "$APPICONSET/app-icon.svg"
echo "  Copied SVG into $APPICONSET/app-icon.svg"

# ── Clean up master temp file ────────────────────────────────────────
rm -f "$TMPDIR/mc-icon-master.png"

echo ""
echo "Icon export complete."
