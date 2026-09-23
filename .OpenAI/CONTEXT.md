# MeedyaConverter — Working Context (OpenAI / Codex)

> How we work on this repo. Mirror of the `.claude/` operating rules, written for
> Codex/OpenAI continuity. Canonical detail lives in `.claude/standing_tasks.md`.
> Last updated: 2026-09-23.

## The one-line summary

Proprietary Swift macOS/CLI media converter (a modern HandBrake alternative) by
MWBM Partners Ltd. All work goes on the single working branch
`wip/alpha-consolidation`, which will reach `alpha` via **one** pull request
created later (no stacked PRs).

## Standing operating rules (digest)

1. **Model / tool routing.** Analysis and planning (including deep analysis and
   deep planning) → **Opus** agents, run **one at a time** (never in parallel).
   *Changed 2026-09-23:* this used to be Fable with an Opus fallback; the owner
   moved it because the newest Opus is cheaper than Fable and at least as good,
   so older "retry Fable next run" notes are superseded. Implementation →
   **Sonnet or Haiku**, whichever fits (**Opus** when genuinely complex, and for
   verification). The rule is about the tier, not the name. Philosophy:
   **GIRFT — Get It Right First Time**, spending usage efficiently.
   **Ultrathink first, and use workflows to plan AND do the work** (2026-09-20):
   think harder about scope, risks and ordering *before* starting, and orchestrate
   the work through workflows/agents rather than one single pass.
2. **Cross-LLM review loop.** Build with one service, review with a different one
   (Claude Code ⇄ Codex). Reviewer finds issues → fix → re-review, until a round
   finds no real problems. Check every finding against the code; a finding that
   is wrong is written down with the reason, never "fixed" to quiet the reviewer.
   Record the number of rounds. If Codex is not reachable (cloud session, or out
   of usage credit), review with an independent Claude reviewer, **say so in the
   report and commit message**, and treat the work as owing a full Codex review
   over the whole stretch once Codex is back.
3. **Cross-LLM fallback.** If the primary service runs out of credits or is
   unavailable, hand off to another suitable one — only if the context survives
   the move (handoff doc + committed work). Try the primary first on every new
   run, switch back at the next natural break, run a full review of the fallback
   period once it is back, and record every fallback.
4. **After each task:** commit **and push** to `wip/alpha-consolidation`, then
   watch CI to green; update the relevant GitHub issue(s) individually; update
   `.claude/` memory/context and this `.OpenAI/` mirror; update
   `.claude/HANDOFF.md` (the **only** handoff — kept current as the work happens,
   not tidied up at the end); cross-system review until clean; show the progress
   table.
5. **Thorough documentation.** Keep all `.md` docs, in-app help
   (`Sources/MeedyaConverter/Resources/Help/`), and the OpenAPI/Swagger specs
   (`docs/api/*.yaml`, browsable via `docs/api/swagger-ui/`) current.
6. **Plain-English communication.** Explain things in plain, jargon-light English;
   gloss unavoidable technical terms on first use.
7. **Autonomy.** Work the whole queue autonomously; only pause for a genuine
   user decision, surfaced **upfront** and in the simplest wording, then continue.
8. **Verification gates.** `swift build --target ConverterEngine` before every
   Swift commit; `swift test` and SwiftLint **cannot** run locally (no Xcode) —
   **CI is the test gate**; `actionlint` works locally. Never claim tests pass
   from a local compile.
9. **Progress tables.** Frequent status updates as a table of queued tasks (task,
   issue, status, note), at least after each finished unit and whenever the queue
   changes. Status words: Queued · In progress · In review · Blocked · Done · Dropped.
10. **Plugins.** Use the dev-team plugin where it fits — including for suggesting
   further fixes/enhancements (raised as issues, not built unless asked) and for
   routing review to a different AI system. It must not create a second handoff.
11. **Sibling repos** (`MeedyaDL`, `MeedyaSuite-core`) are **read-only** from a
   MeedyaConverter session — other sessions edit them concurrently.

## Conventions

- UK English in user-facing docs; proprietary copyright headers on source files.
- Every commit references its issue number(s) and ends with the required
  attribution trailers (`Co-Authored-By:` and the session link) — this is the
  repo's established convention and the one sanctioned place a model name appears.
- Outside those required attribution trailers, do **not** add AI model names into
  code, PR/issue prose, commit subject lines, or any other pushed artifact — keep
  that to chat.

## Canonical sources (read these first)

- `.claude/HANDOFF.md` — live status / resume point.
- `.claude/standing_tasks.md` — full rules.
- `.claude/project_brief.md` — durable overview.
- `PROJECT_STATUS.md`, `Project_Plan.md`, `README.md` — public project state.
