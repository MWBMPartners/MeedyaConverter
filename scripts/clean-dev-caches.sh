#!/usr/bin/env bash
# =============================================================================
# MeedyaConverter — Dev Cache Cleaner
# Copyright (c) 2026 MWBM Partners Ltd. All rights reserved.
# Proprietary and confidential. Unauthorized copying or distribution
# of this file, via any medium, is strictly prohibited.
# =============================================================================
#
# Purpose:
#   Free disk space by removing build / dependency caches that regenerate
#   automatically on next use. Codified as standing task #12 — see
#   `.claude/standing_tasks.md`. The two modes are:
#
#     --quick (default, AFTER EACH PR)
#       Project-local caches only. Fast, no impact on other Rust /
#       Swift work on this machine. The project's `.build/` directory
#       is the dominant win (typically 1-3 GB on this codebase).
#
#     --deep (AT SESSION END or when disk pressure is felt)
#       Adds global caches that are shared with other projects:
#       Swift Package Manager dependency-download cache and the
#       cargo registry cache. Recovering more space at the cost of
#       a slower first build the next time a Rust or Swift project
#       on this machine needs the cache.
#
#   All targets are documented before deletion so a reader can audit
#   what runs. Nothing here is destructive in the data-loss sense —
#   every file removed is regeneratable from network sources or local
#   source code.
#
# Usage:
#   ./scripts/clean-dev-caches.sh           # quick
#   ./scripts/clean-dev-caches.sh --quick   # explicit quick
#   ./scripts/clean-dev-caches.sh --deep    # quick + global caches
#   ./scripts/clean-dev-caches.sh --dry-run # list targets, remove nothing
#
# Exit codes:
#   0  Success (one or more targets cleaned, or already-empty)
#   1  Invalid argument
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Arg parsing
# -----------------------------------------------------------------------------

MODE="quick"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)   MODE="quick";  shift ;;
    --deep)    MODE="deep";   shift ;;
    --dry-run) DRY_RUN=1;     shift ;;
    -h|--help)
      sed -n '2,40p' "$0" | sed 's/^#\s\{0,1\}//' >&2
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--quick|--deep] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Resolve the project root from the script's own location, so the script
# works whether invoked as `./scripts/clean-dev-caches.sh` from the root
# or via an absolute path from elsewhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Track totals across all targets so the user gets one final summary line.
total_freed_bytes=0
total_targets=0

# Human-readable byte count (falls back to raw bytes on platforms without
# `numfmt` — macOS doesn't ship coreutils by default).
human_bytes() {
  local bytes="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec "$bytes"
  else
    # Cheap inline conversion: pick the largest unit that yields a
    # one-or-two-digit integer prefix. Good enough for a status line.
    if   [[ $bytes -ge 1073741824 ]]; then echo "$(( bytes / 1073741824 )) GiB"
    elif [[ $bytes -ge 1048576    ]]; then echo "$(( bytes / 1048576 )) MiB"
    elif [[ $bytes -ge 1024       ]]; then echo "$(( bytes / 1024 )) KiB"
    else                                   echo "${bytes} B"
    fi
  fi
}

# Print + remove a single target path. Tolerates missing paths (no-op +
# zero contribution) so the caller can list every potential target
# without guarding each one individually.
clean_target() {
  local label="$1"
  local path="$2"

  if [[ ! -e "$path" ]]; then
    printf '  • %-40s %s\n' "$label" "(not present — nothing to clean)"
    return 0
  fi

  # `du -sk` returns size in 1024-byte blocks. macOS BSD du and GNU du
  # both honour `-s -k`, so this is portable enough for our targets.
  local bytes
  bytes=$(du -sk "$path" 2>/dev/null | awk '{ print $1 * 1024 }')
  bytes=${bytes:-0}

  printf '  • %-40s %s\n' "$label" "$(human_bytes "$bytes")"

  if [[ $DRY_RUN -eq 1 ]]; then
    printf '      DRY RUN — would remove: %s\n' "$path"
  else
    rm -rf "$path"
  fi

  total_freed_bytes=$(( total_freed_bytes + bytes ))
  total_targets=$(( total_targets + 1 ))
}

# -----------------------------------------------------------------------------
# Cleanup pass
# -----------------------------------------------------------------------------

# Header label. `${DRY_RUN:+...}` would expand for the integer 0 too
# (DRY_RUN is non-empty when set to the default 0), so use an explicit
# `if` instead — keeps the label honest when --dry-run is NOT passed.
if [[ $DRY_RUN -eq 1 ]]; then
  echo "MeedyaConverter dev-cache cleaner — mode: $MODE (dry run)"
else
  echo "MeedyaConverter dev-cache cleaner — mode: $MODE"
fi
echo "Project root: $PROJECT_ROOT"
echo ""

# ---- Quick (project-local) ---------------------------------------------------
#
# `.build/` is the dominant win — usually 1-3 GiB on this codebase after a
# full test run. The `.swiftpm/configuration/` and `.swiftpm/xcode/`
# directories cache SwiftPM-Xcode integration state and regenerate when
# Xcode is reopened against this package.

echo "Project-local caches (always cleaned):"
clean_target "SPM build directory"      "$PROJECT_ROOT/.build"
clean_target "SwiftPM Xcode metadata"   "$PROJECT_ROOT/.swiftpm/xcode"
clean_target "SwiftPM configuration"    "$PROJECT_ROOT/.swiftpm/configuration"

# Project-specific Xcode DerivedData (the name suffix is per-checkout so
# we glob; only this project's DerivedData is touched).
echo ""
echo "Xcode DerivedData for this project:"
local_derived_dir=~/Library/Developer/Xcode/DerivedData
if [[ -d "$local_derived_dir" ]]; then
  found_any=0
  for d in "$local_derived_dir"/MeedyaConverter-*; do
    if [[ -e "$d" ]]; then
      clean_target "DerivedData ($(basename "$d"))" "$d"
      found_any=1
    fi
  done
  if [[ $found_any -eq 0 ]]; then
    printf '  • %-40s %s\n' "DerivedData/MeedyaConverter-*" "(no matching entries)"
  fi
else
  printf '  • %-40s %s\n' "DerivedData root" "(DerivedData dir absent)"
fi

# ---- Deep (global caches shared with other projects) ------------------------

if [[ "$MODE" == "deep" ]]; then
  echo ""
  echo "Global caches (shared with other projects on this machine):"

  # SwiftPM download cache — clearing this forces SwiftPM to re-download
  # every dependency on the next `swift package resolve` for any project
  # on this machine. Worth it for disk space; the cost is bandwidth.
  clean_target "SwiftPM download cache" "$HOME/Library/Caches/org.swift.swiftpm"

  # Cargo registry cache — same logic for any local Rust work.
  # Includes the MeedyaSuite-core dependency when checked out locally.
  clean_target "Cargo registry cache"   "$HOME/.cargo/registry/cache"
  clean_target "Cargo registry source"  "$HOME/.cargo/registry/src"

  # Rust build cache — any `target/` directory inside MeedyaSuite-core
  # if it's been checked out as a sibling. Best-effort; missing is fine.
  if [[ -d "$PROJECT_ROOT/../MeedyaSuite-core" ]]; then
    clean_target "MeedyaSuite-core Rust target" \
      "$PROJECT_ROOT/../MeedyaSuite-core/target"
  fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY RUN complete: would have freed approximately $(human_bytes "$total_freed_bytes") across $total_targets target(s)."
else
  echo "Cleaned $total_targets target(s); freed approximately $(human_bytes "$total_freed_bytes")."
fi
