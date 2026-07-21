#!/usr/bin/env bash
# ============================================================================
# MeedyaConverter — security-check-action-pins.sh
# Copyright © 2026 MWBM Partners Ltd. All rights reserved.
#
# Static linter for GitHub Actions pin hygiene.
# Per SECURITY.md F-010 (T7 — supply-chain).
#
# Scans BOTH `.github/workflows/*.yml` AND `*.yaml` (GitHub honours
# both extensions). Fails (exit 1) on any of these "loose pin"
# patterns:
#
#   uses: actor/repo@main            ← branch pin (re-tagged at will)
#   uses: actor/repo@master          ← branch pin (re-tagged at will)
#   uses: actor/repo@branch-name     ← any non-semver, non-SHA ref
#   uses: actor/repo                 ← no ref (defaults to a branch)
#   uses: docker://alpine:3.19       ← mutable docker tag (re-pushable)
#   uses: docker://img:latest        ← mutable docker tag (re-pushable)
#
# Allowed:
#   uses: actor/repo@v4                    ← major tag (v0.1.0 baseline)
#   uses: actor/repo@v4.1.7                ← exact tag
#   uses: actor/repo@a8b9c0d…40-char       ← SHA pin (preferred)
#   uses: docker://img@sha256:<64 hex>     ← digest-pinned docker image
#   uses: ./.github/actions/local          ← in-repo local action
#
# Intended as a pre-merge CI gate so a future workflow author cannot
# silently regress to a mutable reference. Currently does NOT enforce
# SHA-only pinning for marketplace actions — that's the explicit
# POLISH-tier follow-up captured in SECURITY.md F-010, because
# flipping every existing `@v4` reference to a SHA is a larger commit
# that needs separate review.
# ============================================================================

set -euo pipefail

WORKFLOW_DIR="${1:-.github/workflows}"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo "security-check-action-pins: workflow dir not found: $WORKFLOW_DIR" >&2
    exit 2
fi

violations=0

# Find every workflow file under the dir. GitHub honours BOTH `.yml`
# and `.yaml` in `.github/workflows/`, so we must scan both — a
# `.yaml`-suffixed workflow would otherwise slip past the gate.
# `git ls-files` is preferred so the check is reproducible across
# environments; fall back to a direct find when not in a git tree.
if git -C "$WORKFLOW_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    toplevel=$(git -C "$WORKFLOW_DIR" rev-parse --show-toplevel)
    files=$(git -C "$toplevel" ls-files "$WORKFLOW_DIR"'/*.yml' "$WORKFLOW_DIR"'/*.yaml' 2>/dev/null || true)
else
    files=$(find "$WORKFLOW_DIR" \( -name '*.yml' -o -name '*.yaml' \) -type f 2>/dev/null || true)
fi

if [[ -z "$files" ]]; then
    echo "security-check-action-pins: no workflow YAML files found in $WORKFLOW_DIR" >&2
    exit 0
fi

while IFS= read -r yml; do
    [[ -z "$yml" ]] && continue

    # Inspect EVERY `uses:` line, not only those containing `@`, so
    # that mutable `docker://image:tag` references (which have no `@`)
    # are also classified.
    while IFS= read -r line; do
        # Extract the reference token after `uses:` (strip the grep
        # `N:` line-number prefix and everything up to `uses:`, then a
        # trailing inline `# comment` and surrounding quotes).
        target=$(echo "$line" \
            | sed -E 's/^.*uses:[[:space:]]*//' \
            | sed -E 's/[[:space:]]*#.*$//' \
            | sed -E 's/^["'"'"']//; s/["'"'"']$//')

        [[ -z "$target" ]] && continue

        if [[ "$target" == ./* || "$target" == /* ]]; then
            # Local action (in-repo path) — not a remote supply-chain
            # mutation vector; allowed.
            continue
        elif [[ "$target" == docker://* ]]; then
            # Docker image reference. Pinned ONLY when it carries an
            # `@sha256:<64 hex>` digest; a `:tag` (or bare) form is
            # mutable and can be re-pushed by the publisher at will.
            if [[ "$target" =~ @sha256:[0-9a-f]{64}$ ]]; then
                continue
            fi
            echo "  VIOLATION  $yml: $line   (mutable docker:// tag — pin to @sha256:<digest>)" >&2
            violations=$((violations + 1))
            continue
        elif [[ "$target" == *@* ]]; then
            # actor/repo@ref — inspect the ref.
            ref="${target##*@}"
            # Allowlist: SHA (40-char hex) or semver tag (vX / vX.Y / vX.Y.Z).
            if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
                continue
            fi
            if [[ "$ref" =~ ^v[0-9]+(\.[0-9]+)*$ ]]; then
                continue
            fi
            echo "  VIOLATION  $yml: $line   (mutable ref '$ref' — pin to a semver tag or 40-char SHA)" >&2
            violations=$((violations + 1))
        else
            # `uses: actor/repo` with no ref at all — GitHub treats
            # this as the default branch; flag it as unpinned.
            echo "  VIOLATION  $yml: $line   (no ref — pin to a semver tag or 40-char SHA)" >&2
            violations=$((violations + 1))
        fi
    done < <(grep -nE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^[:space:]]' "$yml" || true)
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
