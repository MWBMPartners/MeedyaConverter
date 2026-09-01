# MeedyaConverter — Standing Tasks

> These tasks MUST be performed automatically after EVERY development prompt/action.
> Saved for Claude AI context continuity.
> They are **project- and repo-wide**: they apply to ALL contributors, across ANY
> dev environment (macOS/Xcode, VS Code, Linux container, CI), not just one session.
> Last updated: 2026-09-01

## Mandatory Post-Action Tasks

### 1. GitHub Issue Management

- Before starting work: create a GitHub Issue (or sub-issue) for the action being taken
- Use highly detailed descriptions with acceptance criteria
- Assign to the correct milestone/phase
- If implementation is incomplete, update issue status to "In Progress" with a progress comment
- Once complete, close the issue with a summary comment

### 1a. Acceptance Criteria Tracking

**Policy (clarified 2026-07-18 per #429):** incremental ticking is the ideal,
but the *enforceable gate* is close-time, so the document's authority does not
erode when incremental ticking is impractical.

- **Tick incrementally where practical** — as each acceptance-criterion item is
  verified complete, flip it to `- [x]` (`gh issue edit {number} --body-file` or a
  `gh issue comment` progress note). Do this as you go, not only at the end.
- **Hard gate (must hold at close):** before an issue is closed, EVERY acceptance-
  criterion box is either ticked, or explicitly annotated as deferred with a
  tracking issue reference (e.g. "engine consumption tracked in #346"). Closing an
  issue with silently-unchecked criteria and no annotation is not permitted.
- **Evidence:** each close (or each incremental tick batch) carries a short comment
  citing the PR/commit/test that satisfies the criteria — the audit trail a
  third-party reviewer can follow.
- **Enforcement:** the merge-gate checklist in `.github/PULL_REQUEST_TEMPLATE.md`
  prompts the merger to confirm AC boxes are ticked before merge.
- Applies to ALL issues, ALL phases, consistently — no exceptions.

### 2. Code Quality — Lint, Syntax & Structure

- Run thorough codebase checks for lint, syntax, and structural issues
- Resolve ALL issues regardless of severity (errors, warnings, notices, recommendations)
- Include pre-existing issues in modified files
- **Repeat checks until zero issues remain**

### 3. Security Audit

- Run thorough project security checks on all changed code
- Check for: command injection, path traversal, insecure file permissions, hardcoded secrets, dependency vulnerabilities
- Resolve all security gaps/vulnerabilities found
- **Repeat checks until zero issues remain**

### 4. Accessibility Compliance

- All UI code must be accessibility compliant
- VoiceOver support, keyboard navigation, Dynamic Type
- Proper accessibility labels and hints on all interactive elements

### 5. Documentation Updates — Markdown Files

- Thoroughly update ALL `.md` documents to ensure they are current:
  - README.md
  - CHANGELOG.md
  - PROJECT_STATUS.md
  - Project_Plan.md
  - DEV_NOTES.md (if exists)
  - Sources/MeedyaConverter/Resources/Help/*.md (all help documentation)

### 6. GitHub Updates

- Thoroughly update:
  - GitHub Issues (create new, update existing, close completed)
  - GitHub Milestones (update progress)
  - GitHub Project board (move cards)
  - GitHub Wiki (update relevant pages)

### 7. In-App Documentation

- Update all in-app help content in Sources/MeedyaConverter/Resources/Help/
- Ensure help text matches current feature state

### 8. Gitignore Maintenance

- Maintain .gitignore suitably for this project
- Consider all dev environments: VSCode, Xcode, macOS, Windows, Raspberry Pi

### 9. Stage & Commit After Each Dev Step (No Push)

- After EACH dev step/task is actioned, STAGE changed files (`git add`) and COMMIT with a descriptive message
- Do this incrementally — not in a batch at the end. Each logical unit of work gets its own commit
- Commit messages should reference the task/issue number (e.g., "Phase 1.3: Integrate libmediainfo (#225)")
- Do NOT push — push is manual only. We will push when ready
- Never skip staging — all changes must be tracked

### 10. Cleanup

- Remove temporary development files
- Clean up any build artifacts not needed

### 11. CLI API Documentation (Swagger/OpenAPI)

- Update detailed Swagger/OpenAPI documentation for MeedyaConverter's CLI API after each task
- Document all CLI commands, options, arguments, exit codes, and JSON schemas
- Keep in sync with actual CLI implementation
- Store in `docs/api/` as OpenAPI YAML spec
- This ensures the CLI API documentation is always current and machine-readable

### 12. Dev Cache Cleanup (after each PR + at session end)

- After **each merged PR**, run `./scripts/clean-dev-caches.sh` (default `--quick`):
  - Clears the project's `.build/`, `.swiftpm/xcode/`, `.swiftpm/configuration/`
  - Clears the project-specific Xcode `DerivedData/MeedyaConverter-*`
  - Frees ~1-3 GiB on this codebase; fast, no impact on other Rust / Swift work on the machine
- At **session end** (or when disk pressure is felt), run `./scripts/clean-dev-caches.sh --deep`:
  - Adds the global SwiftPM download cache + cargo registry cache (+ source)
  - Adds any sibling `MeedyaSuite-core/target/` if checked out
  - Slower first build for any project on the machine afterwards, but recovers the most space
- Use `--dry-run` to preview what would be removed without deleting
- Why: everything cleaned regenerates automatically (build outputs from source, download caches from network). Aggressive cleanup prevents the disk-full failures we hit on 2026-05-20 mid-session when `/tmp` ran out and Claude tools blocked
- Safe to skip: never. The script is non-destructive in the data-loss sense; the only cost is regeneration time

### 13. Claude Context Updates

- Update .claude/ memory, context, and prompt files
- Keep project brief current
- Update MEMORY.md in Claude's memory directory

### 14. GitHub PR Security Checks (monitor on EVERY PR — always applicable)

- On every pull request, monitor GitHub's own security checks and fix any real finding before merge — a green `Build & Test (macOS)` is necessary but NOT sufficient:
  - **CodeQL / code scanning** (`Analyze Swift`) — investigate and fix security alerts, not just the pass/fail box
  - **Dependency Review** — resolve any flagged vulnerable or incompatible-license dependency
  - **Secret scanning / push protection** — never merge if a secret is detected; remove + rotate it
  - **`security-check` pin-hygiene workflow** — keep all GitHub Actions pinned (semver tag or SHA)
  - **OpenSSF Scorecard** advisories surfaced in the dependency-review comment — address where actionable
- Applies regardless of session, branch, or task. If a security check fails or a scanning alert appears, treat it like any CI failure: investigate, fix, re-run to green.

## Code Standards (Apply to All Code)

- Detailed comments/annotations on every code block (not abbreviated)
- Proprietary copyright headers: `// (C) 2026–present MWBM Partners Ltd. All rights reserved.`
- Copyright year end should use `Calendar.current.component(.year, from: Date())` in code where dynamic
- Full code formatting (line breaks, indentation, readable structure)
- Modular architecture
- Swift 6.3 with strict concurrency checking

## Apple-Specific Standards

- Native Swift 6.3 / SwiftUI for macOS
- Meet App Store distribution guidelines where possible
- Explicitly call out any features that cannot meet App Store guidelines
- Code signing and notarization ready (paid Apple Developer Programme account)
- Dual distribution: App Store (sandboxed) + Direct (Sparkle updates)

---

## Workflow & Processing Standing Tasks (added 2026-08-04)

> Repo-wide operating procedure. Applies to every contributor and every dev
> environment. These are process directives; the numbered "Mandatory Post-Action
> Tasks" above remain the per-step checklist.

### W1. Project-state accuracy (GitHub Issues + Claude context)

- Periodically (and whenever significant work lands) do a **full sweep of ALL
  GitHub Issues — open AND closed** — and reconcile each against the **actual
  codebase**, never against commit titles, PR text, or other documents. No
  assumptions/inferences: confirm by reading the code (callers exist, the code
  path executes, the setting is read, the UI/CLI reaches it).
- Update all **Claude memory / context / prompt files** in `.claude/`
  (`project_brief.md`, `standing_tasks.md`, `prompt_history.md`, `HANDOFF.md`,
  and any others) to match reality.
- Where a fix is implemented on the working branch but not yet merged, mark the
  issue **"implemented on branch, closes on merge"** with an evidence comment —
  do not close it until the change is actually released to the target branch.

### W2. Keep the Handoff document current (crash-safe continuity)

- Update `.claude/HANDOFF.md` **as you go**, not only at the end, so any session
  can resume exactly where the last left off after any interruption.

### W3. Analysis & planning → Fable (sequential); implementation → Sonnet

- Perform **ALL analysis and planning — including deep planning** — using
  **sequential (never parallel) Fable agents** (Fable 5). Run analysis/planning
  agents strictly one at a time; do NOT fan them out in parallel. If Fable is
  unavailable, fall back to Opus for that run and **retry Fable** on the next
  analysis/planning run.
- Carry out **implementation** with **Sonnet**. (Haiku is acceptable for trivial
  mechanical edits; use **Opus only when the implementation is genuinely
  complex**.)
- Philosophy: **GIRFT — Get It Right First Time.** Spend tokens/credits
  efficiently while still producing top-quality, correct code.
- Reaffirmed and broadened per user directive 2026-09-01: previously scoped to
  *deep* analysis/planning; now applies to **all** analysis and planning, with
  implementation on **Sonnet**.

### W4. Use available plugins

- Use the **dev-team plugin** (<https://github.com/MWBMPartners/dev-team-plugin>)
  to help perform, manage, or propose development **throughout this project repo
  and its development** — planning, orchestration, review, security, CI, docs, and
  shipping. Use its skills / commands / agents wherever they add leverage.
- Also use any other configured plugins/skills where they help.
- Explicit plugin reference added per user directive 2026-09-01.

### W5. Steps after EACH task

1. **Commit and push** the work to the single working branch that will eventually
   target `alpha` (currently `wip/alpha-consolidation`).
2. **Update the relevant GitHub Issue(s) individually** for that task (progress
   comment, tick acceptance-criteria boxes, close only when truly satisfied).
3. **Update Claude memory & context** in `.claude/`.
4. **Update the Handoff document** so work is resumable at any point.

### W6. Thorough documentation update

- Keep ALL `.md` docs current (README, CHANGELOG, PROJECT_STATUS, Project_Plan,
  DEV_NOTES, FEATURES, PROJECT, `docs/**`, help markdown).
- Update **in-app help / guides** (`Sources/MeedyaConverter/Resources/Help/`).
- Update **Claude memory/context** in `.claude/`.
- If the project exposes an **API**, update the **OpenAPI/Swagger** spec
  (`docs/api/*.yaml`).
- If the project gains **web-based components** and a browsable **Swagger UI**
  isn't already bundled, include one — prepared to be **hostable on shared
  hosting (no Docker / no build step)**. (Already present at
  `docs/api/swagger-ui/`.)

### W7. Efficient / smart processing

- Reorder and bundle these tasks as needed to execute efficiently, provided none
  is dropped.

### W8. Autonomy

- Work through ALL queued tasks **autonomously**. Only pause when an **EXPLICIT
  decision or action from the user** is required — state, in the simplest wording,
  exactly what is needed and why — then **continue autonomously** with the rest of
  the queue without waiting.
- **Surface clarification / decision questions UPFRONT** — gather them and present
  them at the *start* of the work, batched so the user can resolve them in one
  pass, rather than trickling them out as/when each arises mid-task. Then continue
  autonomously. (Per user directive 2026-09-01.)

### W9. No PR stacking

- **Do not** open multiple stacked PRs. Commit all work to the single working
  branch (`wip/alpha-consolidation`) which will target `alpha` via **one** PR
  created later. This avoids PR merge-race conditions.
- Exception already in force: MWBM-intAppsAPI changes go to that repo's
  `feat/feature-targeting-consolidated` branch.
