#!/usr/bin/env bash
# =============================================================================
# MeedyaConverter — Extract Changelog Section
# Copyright (c) 2026 MWBM Partners Ltd. All rights reserved.
# Proprietary and confidential. Unauthorized copying or distribution
# of this file, via any medium, is strictly prohibited.
# =============================================================================
#
# Usage:
#   ./scripts/extract-changelog.sh <version>
#
# Description:
#   Extracts the changelog section for a given version from CHANGELOG.md.
#   Falls back to git log output if no matching section is found.
#
# Arguments:
#   version  Semantic version number (e.g., "0.1.0", "1.2.3")
#
# Output:
#   Markdown-formatted release notes to stdout.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <version>" >&2
    exit 1
fi

VERSION="$1"
CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}"

# ---------------------------------------------------------------------------
# Locate the changelog file relative to the repo root
# ---------------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
if [ ! -f "$CHANGELOG_FILE" ] && [ -f "$REPO_ROOT/$CHANGELOG_FILE" ]; then
    CHANGELOG_FILE="$REPO_ROOT/$CHANGELOG_FILE"
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "Warning: $CHANGELOG_FILE not found, falling back to git log." >&2
    PREVIOUS_TAG=$(git tag --sort=-creatordate | grep -E '^v[0-9]' | sed -n '2p' || true)
    if [ -n "$PREVIOUS_TAG" ]; then
        git log "${PREVIOUS_TAG}..HEAD" --pretty=format:"- %s (%h)" --no-merges
    else
        git log --pretty=format:"- %s (%h)" --no-merges | head -50
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Extract the section for the requested version
# ---------------------------------------------------------------------------
# Match lines like: ## [0.1.0] or ## [0.1.0] - 2026-04-05
# Capture everything until the next ## heading or end of file.
# ---------------------------------------------------------------------------
SECTION=$(awk -v ver="$VERSION" '
    /^## \[/ {
        # Check if this heading matches our version
        if (match($0, "\\[" ver "\\]")) {
            found = 1
            next
        } else if (found) {
            # We hit the next version heading, stop
            exit
        }
    }
    found { print }
' "$CHANGELOG_FILE")

# ---------------------------------------------------------------------------
# Strip leading/trailing blank lines from the extracted section
# ---------------------------------------------------------------------------
SECTION=$(echo "$SECTION" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba}')

if [ -n "$SECTION" ]; then
    echo "$SECTION"
else
    echo "No changelog section found for version $VERSION, falling back to git log." >&2

    # Fall back to git log between the previous tag and HEAD (or the current tag)
    CURRENT_TAG="v${VERSION}"
    PREVIOUS_TAG=$(git tag --sort=-creatordate | grep -E '^v[0-9]' | grep -v "^${CURRENT_TAG}$" | head -1 || true)

    if [ -n "$PREVIOUS_TAG" ]; then
        git log "${PREVIOUS_TAG}..${CURRENT_TAG}" --pretty=format:"- %s (%h)" --no-merges 2>/dev/null \
            || git log "${PREVIOUS_TAG}..HEAD" --pretty=format:"- %s (%h)" --no-merges
    else
        git log --pretty=format:"- %s (%h)" --no-merges | head -50
    fi
fi
