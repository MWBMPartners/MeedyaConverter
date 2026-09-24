# MeedyaConverter — Standing Tasks

> These tasks MUST be performed automatically after EVERY development prompt/action.
> Saved for Claude AI context continuity.
> They are **project- and repo-wide**: they apply to ALL contributors, across ANY
> dev environment (macOS/Xcode, VS Code, Linux container, CI), not just one session.
> Last updated: 2026-09-24 (owner directive of 2026-09-24: new **W16** — a watchdog on
> every asynchronous step, so nothing is missed and the queue never moves on blind.)
> Previous: 2026-09-23 (owner directive of 2026-09-23: planning moved from Fable to
> **Opus** in W3/W12; W2 handoff timing tightened; W4 suggestions + cross-system checking;
> W5 now lists the `.OpenAI/` mirror and the progress table; W13 loop-stopping rule; new
> W15 progress tables. Nothing was removed.)
> Previous: 2026-09-17 (added §16 plain-English communication, W12 cross-LLM fallback,
> W13 review loop, W14 `.OpenAI/` mirror; reconciled §9 push policy with W5)

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

### 9. Stage, Commit & Push After Each Dev Step

- After EACH dev step/task is actioned, STAGE changed files (`git add`) and COMMIT with a descriptive message
- Do this incrementally — not in a batch at the end. Each logical unit of work gets its own commit
- Commit messages should reference the task/issue number (e.g., "Phase 1.3: Integrate libmediainfo (#225)")
- **Push policy (updated — see the "§9 ↔ W5 reconciliation" section near the end of
  this file):** on the working branch `wip/alpha-consolidation`, **push after each
  task** (per W5), then watch CI to green (§15). Pushing to any **other** branch still
  needs explicit user instruction. The old "no push — manual only" wording is
  **superseded** for the working branch.
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

### 15. Monitor CI / checks after EVERY push, sync, or PR — stay until green

- After ANY `git push`, branch sync, or PR raise/update, **do NOT walk away or start
  unrelated work** — stay and watch the checks the push triggered through to
  completion (`gh run watch <id> --exit-status`, or poll
  `gh run list --branch <branch>`). A push is not "done" until its run is green.
- Treat a red run as an **immediate** task: open the failed job log
  (`gh run view <id> --log-failed`), find the real cause, fix it (code *or* test),
  re-push, and watch again — before moving on to anything else.
- Applies to **every** check a push triggers — CI Build & Test, CodeQL / code
  scanning, actionlint / Lint Workflows, Dependency Review, `security-check`
  pin-hygiene, TestFlight / release gates — not just Build & Test. §14 is the
  security-specific subset of this rule.
- **CI is the only test gate here** (`swift test` cannot run locally — see W10):
  a green local `swift build` does NOT prove tests pass. Never declare "CI green"
  from a compile; confirm the actual run's conclusion.
- **Rationale (learned 2026-09-02):** CI on the working branch went red and stayed
  red across many commits because a test regression was pushed without watching the
  run. Monitoring each push surfaces a break in ONE iteration, not N commits later.
- **See W16** for the general watchdog rule this is one case of — including how to
  watch CI where the `gh` tool is not installed (cloud sessions), and the trap
  that **any push to the branch cancels the run already in flight**.


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
- Concretely (reaffirmed 2026-09-23): update it **after each piece of work**, before
  starting the next; **the moment something is learned** that would change how
  somebody continues (a wrong assumption, a trap, a decision, an approach tried and
  rejected); and **before starting anything long-running**, so an interruption in
  the middle is survivable.
- It must carry what a replacement needs: what is being attempted and why, what is
  established, which files matter, **what was tried and rejected**, what is verified
  versus assumed, and what to do next.
- **There is exactly one handoff: `.claude/HANDOFF.md`.** Do not create a second one
  anywhere else "for convenience" (see W4 on plugins that write their own).
- Why it matters so much: the cross-LLM fallback (W12) is only safe because this
  file exists and is current. When the moment comes, the system that knew what was
  going on is the one that has stopped answering.

### W3. Analysis & planning → Opus (sequential); implementation → Sonnet / Haiku

- Perform **ALL analysis and planning — including deep analysis and deep planning** —
  using **sequential (never parallel) Opus agents**. Run analysis/planning agents
  strictly one at a time, so each step sees what the previous one established; do
  NOT fan them out in parallel.
- **Changed 2026-09-23 (owner directive):** this used to say *Fable*, falling back
  to Opus. The owner's reason for the change: the newest Opus (Opus 5.5 at the time
  of writing) is **cheaper than the latest Fable and at least as good** at this
  work, so there is nothing left to fall back from. Older handoff entries that say
  "retry Fable next run" are **superseded** — do not act on them. The rule is about
  the *tier* ("the strongest reasoning available, one agent at a time"), not the
  name; if a better-value model arrives, the tier moves with it.
- Carry out **implementation** with **Sonnet or Haiku, whichever fits** (Haiku for
  mechanical edits). Use **Opus when the implementation is genuinely complex**, and
  for verification — verification is never done by a weaker model than the build.
- Philosophy: **GIRFT — Get It Right First Time.** Spend tokens/credits
  efficiently while still producing top-quality, correct code.
- Reaffirmed and broadened per user directive 2026-09-01: previously scoped to
  *deep* analysis/planning; now applies to **all** analysis and planning, with
  implementation on **Sonnet**.
- **Ultrathink first, and use workflows to plan AND do the work** (added
  2026-09-20, user directive). Before starting a piece of work, think harder
  about it than feels necessary — reason through the real scope, the risks, what
  could go wrong, and the right order of work — *then* start. Use **workflows /
  orchestrated agents** to help both **plan** and **carry out** the work, rather
  than doing everything in a single pass. This sits on top of (does not replace)
  the sequential-planning rule above: planning agents still run one at a time, and
  implementation still goes to Sonnet/Haiku (Opus only when genuinely complex).

### W4. Use available plugins

- Use the **dev-team plugin** (<https://github.com/MWBMPartners/dev-team-plugin>)
  to help perform, manage, or propose development **throughout this project repo
  and its development** — planning, orchestration, review, security, CI, docs, and
  shipping. Use its skills / commands / agents wherever they add leverage.
- Also use any other configured plugins/skills where they help.
- Explicit plugin reference added per user directive 2026-09-01.
- **Suggestions (reaffirmed 2026-09-23):** use the plugin to propose further fixes,
  tweaks, enhancements and new features too. Anything outside the task in hand is
  **raised** (a GitHub issue, or a line in the report) — not built — unless the owner
  says so.
- **Cross-system checking:** use the plugin to route review to a *different* AI
  system from the one that built the work (plan/build in Claude Code → review in
  Codex, and vice versa). See W13.
- **A plugin must not create a second handoff or a competing plan.** Read the
  plugin's settings in the repo first (cost setting, branch policy, switches). The
  dev-team plugin can write its own `HANDOFF.md` / `PROJECT.md` at the repo root —
  `.claude/HANDOFF.md` stays the only handoff. (The root `PROJECT.md` and
  `.dev-team/autopilot.json` are the plugin's July 2026 autopilot brief — mission
  marked terminal on 2026-07-01; they are historical, not live status.)

### W5. Steps after EACH task

1. **Commit and push** the work to the single working branch that will eventually
   target `alpha` (currently `wip/alpha-consolidation`), **then stay and watch the
   triggered CI run to green (§15), with a watchdog (W16)** — a red run is fixed
   before moving on.
2. **Update the relevant GitHub Issue(s) individually** for that task (progress
   comment, tick acceptance-criteria boxes, close only when truly satisfied).
3. **Update Claude memory & context** in `.claude/`.
4. **Update the OpenAI / Codex memory & context** in `.OpenAI/` (W14) so both
   tell the same story.
5. **Update the Handoff document** so work is resumable at any point.
6. **Have it reviewed by a different AI system** (W13) — code *and* the note
   changes — and repeat until a round comes back clean. A handoff-only progress
   note may be committed first; the next review round covers it.
7. **Show the progress table** (W15).

- Verify it yourself before committing: run the checks (W10) and **read their exit
  codes directly** — never pipe a check into `grep`/`tail` and rely on `&&`, because
  the pipe hides the real exit code. Read the diff once with security in mind.
- Commit titles start with their type (`feat:`, `fix:`, `docs:` …) and use the
  GitHub username **`Salem874`**, never a real name.

### W6. Thorough documentation update

- **When:** a standing task — after each real body of work, and always **before its
  pull request is opened** (reaffirmed 2026-09-23). It covers the `.OpenAI/` mirror
  too (W14).
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

### W10. Verification gates — what CAN and CANNOT be checked locally

Established 2026-09-01. Older notes saying "no local macOS build available" are
**wrong** and should not be trusted.

- **`swift build --target ConverterEngine` — RUN THIS BEFORE EVERY SWIFT COMMIT.**
  A Swift 6.3.3 toolchain is present at `/usr/bin/swift`. This is a real compile
  gate and catches the class of error that used to reach CI.
- **`swift build` (whole package) fails on `#Preview` macros** — the active
  developer directory is CommandLineTools, which has no `PreviewsMacros` plugin.
  This is an environment limitation. **Do not "fix" the `#Preview` blocks.**
- **`swift test` CANNOT run** — no Xcode, so no `XCTest` module. For a new or
  changed test file, `swiftc -parse <file>` gives a syntax check; type-checking
  and execution are **CI's** job. Never claim tests pass locally.
- **SwiftLint CANNOT run locally** — it needs `sourcekitdInProc` from Xcode. CI
  runs it (with `continue-on-error`). Note that `.swiftlint.yml` disables
  `line_length`, `file_length`, `trailing_whitespace` and several others, so
  long doc comments are fine.
- **`actionlint` works locally** (`brew install actionlint`). CI runs it with
  `SHELLCHECK_OPTS=--severity=error`, so the cosmetic SC2086/SC2129 findings in
  `dev-build.yml` / `release.yml` / `testflight.yml` / `beta-alpha.yml` are
  deliberately suppressed — do not "fix" them as part of unrelated work.
- **CI now runs on every push to `wip/**`** (#496). `cancel-in-progress` is on,
  so rapid pushes cancel superseded runs and only the branch tip is verified —
  that is fine, but do not read a `cancelled` run as a failure.

### W11. Sibling repos are read-only from a MeedyaConverter session

The workspace holds `MeedyaConverter`, `MeedyaDL` and `MeedyaSuite-core` side by
side, and **other Claude sessions work in them concurrently** — on 2026-09-01 a
second session switched branches, merged, committed and pushed inside
MeedyaSuite-core while this session was running, and deleted two remote branches.

- **Do not edit, commit, branch, or "restore" state in `MeedyaDL` or
  `MeedyaSuite-core`** from a MeedyaConverter session. Read them, cite them,
  report findings, and let the user route the work.
- Re-run `git fetch` + `git status` before citing anything there; prefer citing
  **commits** over line numbers, which move under you.
- Cross-repo work that genuinely belongs elsewhere goes in the handoff's
  "cross-repo items" list for the user, not into a drive-by commit.

### W9. No PR stacking

- **Do not** open multiple stacked PRs. Commit all work to the single working
  branch (`wip/alpha-consolidation`) which will target `alpha` via **one** PR
  created later. This avoids PR merge-race conditions.
- Exception already in force: MWBM-intAppsAPI changes go to that repo's
  `feat/feature-targeting-consolidated` branch.

---

## Communication & Cross-LLM Standing Tasks (added 2026-09-17)

> New deltas from the 2026-09-17 user directive. The rest of this file already
> codified the Fable→Sonnet split (W3 — planner since changed to Opus, 2026-09-23), dev-team plugin (W4), per-task
> commit/push + issue/handoff updates (W5), thorough docs + Swagger UI (W6),
> autonomy + upfront clarifications (W8), and no-PR-stacking (W9). These sections
> add what was genuinely new.

### §16. Plain-English communication (no jargon)

- When explaining, reporting back, or writing user-facing text, use **plain,
  easy-to-understand English**. Avoid unexplained technical jargon — it can
  confuse even technically proficient readers.
- Where a technical term is unavoidable, add a short plain-English gloss the
  first time it appears (e.g. "notarisation — Apple's security stamp that lets
  the app open without a warning").
- This applies to chat replies, commit/PR summaries, issue bodies, and docs.
- Code itself stays precise; this rule is about how we *explain* things.

### W12. Cross-LLM fallback & recovery (tool-agnostic; repo- AND device-level)

> Also written to the device-level `~/.claude/CLAUDE.md` so it applies across all
> projects on this machine, phrased so we never have to name specific tools.

- If the **primary** AI service or agent for a piece of work becomes unavailable
  or runs out of usage credits/tokens (e.g. Claude Code / Codex / a Fable agent),
  **hand off to another suitable service or model** and keep going — provided the
  context and progress can carry over safely (handoff doc + committed state make
  this safe).
- **Switch back to the primary service frequently.** The cross-LLM review loop
  (W13) is expected to catch methodology differences between services, but once
  the primary is available again, run a **full review** with it.
- Keep the **handoff document up to the minute** (W2) so any service can resume
  cleanly — this is what makes fallback safe.
- Concrete current mapping (updated 2026-09-23): analysis/planning → Opus,
  one agent at a time (W3 — Fable is no longer the planner); build → Sonnet/Haiku;
  review → Codex, falling back to an independent Claude reviewer when Codex is not
  reachable (W13). Do this flexibly — the rule is "use whatever suitable tool is
  available", not a fixed roster.
- **When to hand over:** the service or agent refuses the work (out of credit, spend
  cap, rate limit, quota, outage) and one retry has already failed for a reason that
  will not change by itself. *Not* merely because something is slow.
- **Only hand over if the work survives the move** — enough context can go with it
  (what is being attempted, what is established, which files matter, what was tried
  and rejected, how the result will be checked). If it cannot, say plainly that the
  work is blocked and why.
- **Always try the preferred service first on each new run**, even if it failed last
  time — limits reset and outages end.
- **Record every fallback** where the work is recorded (commit message, handoff,
  progress report): which parts had the usual checking, what the catch-up review
  must cover, and whether repeated fallbacks suggest a limit needs raising.

### W13. Cross-LLM review loop (Codex ⇄ Claude), fix-until-clean

- Pass **all code** (and material docs/config) through a review process:
  plan/implement with one service, then **review with a different one** (e.g.
  build with Claude Code, review with Codex, and vice versa) for extra quality.
- The reviewer **finds issues → they get fixed → re-review**, repeating **until
  no issues remain**. Aim: GIRFT (Get It Right First Time).
- **The reviewer must not be the builder**, and must not be an agent that remembers
  building the work.
- **Read every finding, and check it against the code** rather than taking the
  reviewer's word. Fix the real ones. A finding you are sure is wrong does **not**
  keep the loop going and must **never** be "fixed" just to quiet the reviewer —
  write down why it is wrong (commit message or handoff) and move on.
- **Stop when a round finds no real problems.** Record how many rounds it took
  where the work is recorded.
- **Fallback (per W12):** when Codex (or any configured external reviewer) is not
  reachable in the current environment — e.g. no `codex` CLI on PATH in a cloud
  session, or Codex out of usage credit — run the review with an **independent
  Claude reviewer agent** (a different model or a fresh agent with no memory of the
  build) and label it clearly as the Claude-side fallback, **in the report and the
  commit message** — never let silence imply an independent review happened. Treat
  the change as not fully reviewed: a full **Codex cross-review** is still owed and
  runs once Codex is reachable again, over the **whole run of work** done in the
  meantime (reviewed as one body, not commit by commit).
- Codex **is installed on the owner's Mac** (`/opt/homebrew/bin/codex`, confirmed
  2026-09-23). The "not reachable" cases so far were cloud sessions (no Codex) and
  Codex usage limits.

### W14. OpenAI / Codex memory & context mirror (`.OpenAI/`)

- Mirror the durable Claude context into a **`.OpenAI/`** directory at the repo
  root so Codex/OpenAI tooling has the same continuity Claude does.
- After each task, update **both** `.claude/` (Claude memory/context/handoff) and
  `.OpenAI/` (OpenAI/Codex memory + context). Keep them consistent; `.claude/` and
  `.OpenAI/` should tell the same story.
- `.OpenAI/` holds `MEMORY.md` (durable facts), `CONTEXT.md` (how-we-work +
  pointers to the `.claude/` sources), and `README.md` (what the folder is).

### W15. Progress tables (added 2026-09-23)

- Give **frequent** status updates as a table of the queued tasks — one row per
  task, with its issue number, its status and a short note. Show it at least
  **after each finished unit** and **whenever the queue changes**.
- Status words: **Queued · In progress · In review · Blocked (say on what) ·
  Done (say the commit) · Dropped (say why)**.
- Where tasks were reordered or bundled (W7), the table says so, so nothing looks
  dropped.

| # | Task | Issue | Status | Notes |
|---|------|-------|--------|-------|
| 1 | Plain-English name | #nnn | Done — pushed `abc1234` | review: 2 rounds, last clean |
| 2 | … | #nnn | Blocked — waiting on decision 1 | continuing with 3 meanwhile |

### W16. Watchdog every asynchronous step — never move on without the result (added 2026-09-24)

**In plain English:** when a step starts something that finishes *later* — a CI
run, a background agent, a workflow, a long-running command — set up a
**watchdog** (something that waits and reports back when it has finished) at the
moment it starts. Do not begin any queued step that depends on the outcome, and
do not call the task done, until the watchdog has reported a **final** result.
This is how nothing gets missed and nothing is built on a result nobody saw.

§15 already says this for CI. W16 makes it the rule for **every** asynchronous
step, and fixes the gaps that showed up on 2026-09-21.

**1. What needs a watchdog.** Anything the next step depends on that does not
finish immediately:
- the CI run triggered by every push (and every other check that push starts — §15);
- background agents, subagents and workflows — including review agents (W13);
- long local commands (builds, test runs, downloads, scripts run in the background);
- anything else started now whose result is only known later.

**2. Set it up when the work starts — not afterwards.** The watchdog is part of
starting the work, the same way a push is followed by watching CI.

**3. Wait for a FINAL state, and cover every one of them.** Final means success,
failure, cancelled, or timed out. A watchdog that only listens for success stays
silent through a crash, and **silence is not success**. A **cancelled** run is not
a pass either: it proves nothing about the code.

**4. Give every watchdog a deadline.** If it expires without a final state, say so
and find out why. Never assume it worked. (A CI run here takes ~3–5 minutes; a
deadline of ~20 minutes is generous.)

**5. Don't block needlessly.** While a watchdog runs, carry on with work that does
**not** depend on its result. What must wait is anything that *does* depend on it,
reporting the task complete, and moving the queue on. In the progress table
(W15), an item waiting on a watchdog is **In progress** or **In review** — never
**Done**.

**6. ⚠️ Never let a push kill the run being watched.** `.github/workflows/build.yml`
sets `cancel-in-progress: true`, grouped by branch — so **any push to the branch
cancels the CI run already in flight**. Either wait for the run to finish before
pushing again, or batch the commits and push once. After a cancellation, confirm
a **completed, green** run on a commit that contains the same code before treating
that code as verified.
*Learned 2026-09-21:* runs 353, 355 and 358 were cancelled by follow-up
documentation pushes — 355's tests never ran to completion, and the code was only
proven by the next run.

**7. Read the overall result, not the step-by-step progress.** On 2026-09-21 the
per-step status from the GitHub API lagged by several minutes and made a test
step that had already passed look as if it were still running. Judge by the
**run's / job's final conclusion**; if the step view disagrees, trust the
conclusion.

**8. Mechanisms (use whatever the environment provides):**
- **Local long command:** run it in the background with a loop that exits on
  *either* outcome, so there is exactly one notification when it ends.
- **Background agent / workflow:** its completion notification *is* the
  watchdog. Never report, act on, or predict its result before that arrives.
- **CI with the `gh` tool (the Mac):** `gh run watch <id> --exit-status` (§15).
- **CI without `gh` (cloud sessions):** a background timer (e.g. a backgrounded
  `sleep 60`) that wakes the session, then read the run's **conclusion** through
  the GitHub API tools that are available; repeat until final or the deadline.
  Don't poll faster than every ~30–60 seconds.
- **⚠️ Before ending a turn with anything still in flight,** schedule a fallback
  check-in (a scheduled self-reminder, where the environment offers one) so an
  idle session still comes back to it. An ended turn with no check-in is exactly
  how a result gets missed.

**9. Queue discipline.** A queue item is **complete** only when every watchdog it
started has reported a final **success**. A failure becomes the current task
(§15): fix it, push, and watch the fix to green with its own watchdog — *then*
move to the next item.

### §9 ↔ W5 reconciliation (push policy)

- §9 above ("Stage & Commit After Each Dev Step — No Push") reflects the older
  manual-push posture. **W5 supersedes it for the working branch:** on
  `wip/alpha-consolidation`, each completed task is **committed AND pushed**, then
  CI is watched to green (§15). Push to any **other** branch still needs explicit
  user instruction. This matches the 2026-09-17 user directive and the session
  task framing.
