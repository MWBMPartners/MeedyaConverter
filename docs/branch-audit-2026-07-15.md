# Branch Audit & Consolidation Plan

**Date:** 2026-07-15
**Scope:** Audit of `autopilot/2026-06-30-clean` and `claude/review-issues-continue-4b8W0`;
determine whether they can be consolidated into a single base branch for new dev work.
**Method:** 3 sequential deep-analysis passes (vision/roadmap → issue backlog → consolidation
strategy), each cross-checked against the live git graph and repo contents.

---

## TL;DR

- **`claude/review-issues-continue-4b8W0` has ZERO unique commits.** Its tip (`6bb813e`,
  2026-04-20) is a fully-merged **ancestor of both `main` and `autopilot`**. Its work landed on
  `main` in April as the **#382 integration batch** (merged PRs #382 + #413). The branch is
  obsolete — safe to archive-tag and delete.
- **`autopilot/2026-06-30-clean` already IS the consolidated superset.** It is a clean
  fast-forward of `main` (**+38 / 0 behind**) and already contains 100% of the claude/review
  work plus 99 additional commits. There is nothing to "merge" *from* claude/review.
- **Consolidation = promote `autopilot` to become the single base; retire the dead branch.**
  Recommended path: a **gated PR** into `main` (Option C below).

---

## 1. Verified branch topology

| Branch | Tip | vs `main` | Unique commits | Open PR | Verdict |
|---|---|---|---|---|---|
| `autopilot/2026-06-30-clean` | 2026-07-04 | **+38 / 0 behind** (clean FF) | 38 (active work) | none | ✅ Green CI — the de-facto trunk. **Promote to `main`.** |
| `claude/review-issues-continue-4b8W0` | 2026-04-20 | 0 / **61 behind** | **0** | none | ❌ Obsolete, fully absorbed. **Archive-tag + delete.** |
| `alpha` | 2026-04-06 | 0 / 75 behind | 0 | — | ⚠️ Live pre-release channel (`beta-alpha.yml`). **Leave untouched.** |
| `beta` | 2026-04-06 | 0 / 75 behind | 0 | — | ⚠️ Live pre-release channel (`beta-alpha.yml`). **Leave untouched.** |

**Ancestry confirmed** (`git merge-base --is-ancestor`): `claude/review`, `alpha`, and `beta`
are all strict ancestors of `main` with zero unique commits. `main` is an ancestor of
`autopilot` (clean fast-forward). `autopilot` vs `main` = 71 files, +7,407 / −459.

---

## 2. What each branch is

### `claude/review-issues-continue-4b8W0` — obsolete
The **2026-04-20 integration session**: issues #371–378, #178, #380 (security audit), #381 (UI
gap audit) → merged to `main` as the **#382 batch** (~3,700 lines, 21 commits, 2026-05-18);
subtitle tone-mapping #413 merged 2026-05-20. All of it is on `main` and therefore in
`autopilot`. Its still-open follow-ups (#371–374, #178) remain open **by design** — blocked on
external MeedyaSuite-core work behind the `SUITE_CORE=1` flag — not un-merged code. **Nothing is
lost by deleting the branch.**

### `autopilot/2026-06-30-clean` — the trunk
An autonomous "Autopilot" loop ran **26 cycles under umbrella issue #428** (v0.1.0 GA):
- **Security hardening** — threat rotations T1–T7, findings F-001…F-010 all closed/risk-accepted.
  New `PathSanitizer`, `MetadataSanitizer`, `SFTPCredentialStore` (plaintext-SSH-password fix),
  FFmpegProbe watchdog + byte-cap, ScriptingBridge sanitisation, release-download host allowlist,
  Keychain `ThisDeviceOnly`; root `SECURITY.md` threat model.
- **App Store ITMS fixes** — #386–391 (ITMS-90230/90236/90237/90264/90270/90889) in
  `testflight.yml`.
- **FFmpeg backend abstraction** — `FFmpegBackend` protocol; `ProcessFFmpegBackend` (real,
  Direct channel) + `FFmpegKitBackend` (deliberate `.notImplemented` stub for the parked App
  Store path).
- **CI/distribution hardening** — Dependabot, CodeQL, action-pin linter, distribution docs.
- Tests 967 → 1039; self-declared mission TERMINAL at `b58d676` (2026-07-01).

---

## 3. Product/roadmap context

- **Product:** macOS-first professional media converter (HandBrake alternative), Swift 6/SwiftUI,
  part of MeedyaSuite. `VERSION` = 0.1.0.
- **Current milestone:** ship **v0.1.0 GA on the Direct channel** (signed/notarised DMG via
  GitHub Releases). App Store "Lite" path prepared but deliberately deferred.
- **Open backlog (44 issues) bifurcates:**
  - **Near-term (3):** #428 (GA umbrella — code done, but the *release ritual* is 0% executed),
    #429 (release-readiness hygiene), #416 (in-app updater — v0.2.0 feature).
  - **App Store Lite track (8):** #386–392, #178 — parked behind user cert/provisioning work.
  - **Long-horizon (~33):** gate-ledger differentiators #419–427, cross-platform #147–160 (v2.0),
    AI #235–237, suite-core #371–374 (externally blocked).

---

## 4. Recommended consolidation — Option C (gated promotion)

`autopilot` is a clean fast-forward, so merge risk is ~zero. The only real concern is that its
"GA-ready" verdict is **self-reported on a squashed history** (ledger claims 58 commits; branch
has 38). So don't raw-push it onto the protected default branch — **gate it through a PR.**

| Option | Summary | Trade-off |
|---|---|---|
| A. Merge `autopilot`→`main` now | PR + merge today | Fast, zero merge risk — but lands self-reported "GA-ready" + 3 conflicting status docs on `main` unverified. |
| B. Keep `autopilot` as long-lived dev branch | Rename `develop`, merge at GA | Main stays 38 commits stale; two sources of truth persist — the disease we're curing. |
| **C. Gated promotion (RECOMMENDED)** | Cut `release/v0.1.0-ga` off autopilot, add 2 reconciliation commits, PR → `main`, merge once the gate is green | FF-clean (~zero risk); gate answers the verification concern *before* `main` receives it; matches the autopilot loop's designed user-driven hand-off. Costs ~1 short session of cheap gate work. |

### Execution outline (Option C)
1. **Archive-tag** retiring pointers (`archive/claude-review-issues-continue-4b8W0`, optional
   `archive/alpha`, `archive/beta`) → all deletes become fully recoverable.
2. **Cut `release/v0.1.0-ga`** off the autopilot tip (leaves `autopilot` untouched).
3. **Two reconciliation commits** (Sonnet/Haiku tier): collapse the 3 conflicting status
   narratives into one truthful `PROJECT_STATUS.md` + refresh stale (2026-04-20) `.claude/`
   context files; decide keep/archive for loop state files (`PROJECT.md`, `FEATURES.md`,
   `.dev-team/autopilot.json` — **keep** `SECURITY.md`).
4. **Open PR → `main`**; run **fresh CI** on that exact tip; merge with a **merge commit** (not
   squash — preserves the 38 SHAs and bisectability).
5. **After merge + explicit approval:** delete `claude/review-issues-continue-4b8W0` and
   `autopilot/2026-06-30-clean`. **Leave `alpha`/`beta`** (deleting them kills the pre-release
   channel wired via `beta-alpha.yml`).
6. **First sprint off the new `main`:** #428 release ritual → #429 (re-scoped) → #416.

### Pre-merge gate checklist
- [ ] Fresh CI (build + full test suite + security-check + CodeQL) on the PR tip — do **not**
      trust the month-old green on the autopilot branch.
- [x] Dependabot target — **already correct** (no active `target-branch`; targets default). Verify only.
- [ ] Status reconciliation committed (one narrative).
- [ ] Autopilot loop state files decided (keep/archive/prune).
- [ ] Deliberate stubs documented as deliberate (`FFmpegKitBackend`, TestFlight auto-submit off
      per #392, `SUITE_CORE=1` flag) — so a future session doesn't "fix" them.
- [ ] Human skim of the 71-file diff, especially the 8 `.github/workflows/*` (they become live
      automation on `main`).

---

## 5. Corrections found during verification (amend earlier assumptions)

1. **Dependabot is already fixed** on the `-clean` tip — the dead `target-branch:
   autopilot/2026-06-30` pin was removed; it now targets the default branch. Verify-only, not a fix.
2. **`Resources/Help/` is not empty** — it has `updates.md`, top-level `help/` has 10 docs, and
   `HelpView.swift` embeds content. Issue #429's "ships with no help" is stale against the
   autopilot tip; **re-scope #429** before doing work (real gap is likely "is help bundled into
   the DMG", not "write help").
3. **`alpha`/`beta` are live channel branches**, not junk — `.github/workflows/beta-alpha.yml`
   mints `-alpha/-beta` GitHub pre-releases on push. Deleting them kills the channel; pushing to
   them mints a pre-release. **Leave untouched** pending a separate post-GA channel decision.

---

## 6. Risks & non-actions

- **Do NOT touch first:** gate-ledger #419–427, cross-platform #147–160, AI #235–237, suite-core
  #371–374 (blocked/long-horizon); the `FFmpegKitBackend` stub, TestFlight auto-submit, and
  `SUITE_CORE` flag (deliberate — document, don't fix); `alpha`/`beta` (live channel wiring).
- **Residual risks:** the `-clean` history is a squash of the original run — if fresh CI fails,
  debugging maps poorly to the 58-commit ledger (archive tag preserves the pointer). 8 workflow
  files become live on `main` (expect a burst of Dependabot PRs). The #428 release ritual needs
  signing/notarisation secrets present in repo settings — verify before tagging or the GA run
  fails mid-way with a dangling tag.

---

*Analysis only — no branches were created, merged, or deleted in producing this audit.*
