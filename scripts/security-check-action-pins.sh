#!/usr/bin/env bash
# ============================================================================
# MeedyaConverter — security-check-action-pins.sh
# Copyright © 2026 MWBM Partners Ltd. All rights reserved.
#
# Static linter for GitHub Actions pin hygiene.
# Per SECURITY.md F-010 (T7 — supply-chain).
#
# Fails (exit 1) on any of these "loose pin" patterns inside
# .github/workflows/*.yml:
#
#   uses: actor/repo@main         ← branch pin (re-tagged at will)
#   uses: actor/repo@master       ← branch pin (re-tagged at will)
#   uses: actor/repo@dev          ← branch pin (re-tagged at will)
#   uses: actor/repo@branch-name  ← any non-semver, non-SHA reference
#
# Allowed:
#   uses: actor/repo@v4                 ← major tag (the v0.1.0 baseline)
#   uses: actor/repo@v4.1.7             ← exact tag
#   uses: actor/repo@a8b9c0d…40-char    ← SHA pin (preferred long-term)
#
# Intended as a pre-merge CI gate so a future workflow author cannot
# silently regress to a branch pin. Currently does NOT enforce
# SHA-only pinning — that's the explicit POLISH-tier follow-up
# captured in SECURITY.md F-010, because flipping every existing
# `@v4` reference to a SHA is a larger commit that needs separate
# review.
# ============================================================================

set -euo pipefail

WORKFLOW_DIR="${1:-.github/workflows}"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo "security-check-action-pins: workflow dir not found: $WORKFLOW_DIR" >&2
    exit 2
fi

violations=0

# Find every `uses:` reference in any .yml under the workflow dir.
# `git ls-files` is preferred so the check is reproducible across
# environments; fall back to a direct find when not in a git tree.
if git -C "$WORKFLOW_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    files=$(git -C "$(git -C "$WORKFLOW_DIR" rev-parse --show-toplevel)" ls-files "$WORKFLOW_DIR"'/*.yml' 2>/dev/null || true)
else
    files=$(find "$WORKFLOW_DIR" -name '*.yml' -type f 2>/dev/null || true)
fi

if [[ -z "$files" ]]; then
    echo "security-check-action-pins: no workflow YAML files found in $WORKFLOW_DIR" >&2
    exit 0
fi

while IFS= read -r yml; do
    [[ -z "$yml" ]] && continue

    # Match `uses: actor/repo@ref` and inspect the ref.
    # Refs that are pure SHA (40 hex chars) or that start with `v`
    # followed by digits/dot are allowed.
    while IFS= read -r line; do
        ref=$(echo "$line" | sed -E 's/^.*uses:[[:space:]]*[^@[:space:]]+@([^[:space:]]+).*$/\1/')

        # Skip if the line wasn't actually a `uses:` reference.
        [[ "$ref" == "$line" ]] && continue

        # Allowlist: SHA (40-char hex) or semver-tag (`vX`, `vX.Y`, `vX.Y.Z`).
        if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
            continue
        fi
        if [[ "$ref" =~ ^v[0-9]+(\.[0-9]+)*$ ]]; then
            continue
        fi

        # Anything else (branch names like "main", "master", "dev",
        # "release/next", or unpinned releases) is a violation.
        echo "  VIOLATION  $yml: $line" >&2
        violations=$((violations + 1))
    done < <(grep -nE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^[:space:]]+@' "$yml" || true)
done <<< "$files"

if [[ $violations -gt 0 ]]; then
    echo "security-check-action-pins: $violations loose-pin violation(s) found." >&2
    echo "  Pin actions to a semver tag (vX or vX.Y.Z) or a 40-char SHA." >&2
    echo "  Branch pins (main/master/dev/...) let the action's maintainer or a" >&2
    echo "  compromised account silently swap behaviour on every workflow run." >&2
    exit 1
fi

echo "security-check-action-pins: ok — no loose pins detected."
exit 0
