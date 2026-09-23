# `.OpenAI/` — OpenAI / Codex memory & context mirror

This folder is the OpenAI/Codex counterpart to `.claude/`. It gives Codex (and
any OpenAI-based tooling) the same durable project memory and working context
that Claude keeps in `.claude/`, so either service can pick up work cleanly.

## Files

| File | What it holds |
| ---- | ------------- |
| `MEMORY.md` | Durable facts about the project — identity, architecture, current status, key subsystems, constraints. |
| `CONTEXT.md` | How we work — the standing operating rules, model/tooling routing, review loop, and pointers to the canonical sources. |
| `README.md` | This file. |

## Relationship to `.claude/`

`.claude/` remains the **canonical, most detailed** source of project memory and
live status. In particular:

- `.claude/HANDOFF.md` — the live, up-to-the-minute handoff (resume-anywhere state).
- `.claude/standing_tasks.md` — the full standing-rules checklist.
- `.claude/project_brief.md` — the durable project overview.

This folder is a **faithful summary + pointer set**, not a competing source of
truth. After each task, update **both** `.claude/` and `.OpenAI/` so they tell the
same story (standing rule W14).

Last updated: 2026-09-23.
