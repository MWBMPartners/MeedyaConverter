<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — instructions for coding agents

For any coding assistant working in this repository (Codex, Claude Code or
another). It is short on purpose: the rules live in the files it points to,
so they are written once and cannot drift.

## Read first

- **Working rules:** [`.claude/standing_tasks.md`](.claude/standing_tasks.md) —
  the standing tasks and rules W1–W16 (plain English, the one handoff, what can
  and cannot be checked locally, the review loop, commits, watchdogs). They
  apply to every assistant, not only Claude.
- **Where the work stands:** [`.claude/HANDOFF.md`](.claude/HANDOFF.md) — the one
  handoff document. Do not start a second one.
- **Codex / OpenAI context:** [`.OpenAI/CONTEXT.md`](.OpenAI/CONTEXT.md) and
  [`.OpenAI/MEMORY.md`](.OpenAI/MEMORY.md) (a summary that mirrors `.claude/`).
- **Code style, commits and tests:** [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Languages, tracks, subtitles and lyrics — mandatory

**Languages, tracks, subtitles and lyrics — mandatory:** any work touching BCP 47
language tags, languages, translations, audio or subtitle tracks, lyrics, track
order or naming, language preferences, or accessibility roles (SDH, audio
description, forced, commentary) MUST read and follow
[`docs/standards/media-language-bcp47-policy.md`](docs/standards/media-language-bcp47-policy.md)
(policy `MWBM-MEDIA-LANG`). It is normative and is not repeated here. Its
conformance cases (`Tests/Fixtures/MediaLanguage/`, run by
`Tests/MediaLanguagePolicyTests`) must pass. The copy is checked against the
master in MWBMPartners/MeedyaSuite-core by `scripts/media-lang/check_copies.py`;
never edit the copies — change the master.
