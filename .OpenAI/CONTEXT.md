# MeedyaConverter — Working Context (OpenAI / Codex)

> How we work on this repo. Mirror of the `.claude/` operating rules, written for
> Codex/OpenAI continuity. Canonical detail lives in `.claude/standing_tasks.md`.
> Last updated: 2026-09-17.

## The one-line summary

Proprietary Swift macOS/CLI media converter (a modern HandBrake alternative) by
MWBM Partners Ltd. All work goes on the single working branch
`wip/alpha-consolidation`, which will reach `alpha` via **one** pull request
created later (no stacked PRs).

## Standing operating rules (digest)

1. **Model / tool routing.** Analysis and planning → **Fable** agents, run **one
   at a time** (never in parallel); if Fable is unavailable, fall back to
   **Opus** for that run and retry Fable next time. Implementation → **Sonnet**
   (Haiku for trivial edits; **Opus** only when genuinely complex). Philosophy:
   **GIRFT — Get It Right First Time**, spending usage efficiently.
   **Ultrathink first, and use workflows to plan AND do the work** (2026-09-20):
   think harder about scope, risks and ordering *before* starting, and orchestrate
   the work through workflows/agents rather than one single pass.
2. **Cross-LLM review loop.** Build with one service, review with a different one
   (Claude Code ⇄ Codex). Reviewer finds issues → fix → re-review, until clean.
   If Codex is not reachable in the current environment, review with an
   independent Claude reviewer and note that a full Codex cross-review is still
   owed.
3. **Cross-LLM fallback.** If the primary service runs out of credits or is
   unavailable, hand off to another suitable one (state stays safe because of the
   handoff doc + committed work), and switch back to the primary frequently.
4. **After each task:** commit **and push** to `wip/alpha-consolidation`, then
   watch CI to green; update the relevant GitHub issue(s) individually; update
   `.claude/` memory/context and this `.OpenAI/` mirror; update
   `.claude/HANDOFF.md`.
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
9. **Sibling repos** (`MeedyaDL`, `MeedyaSuite-core`) are **read-only** from a
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
