<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — Session Handoff / Continuity Doc

**Purpose:** crash-safe resume point. If a session ends unexpectedly, read this
first to pick up exactly where we left off. Updated after each completed task.

**Last updated:** 2026-09-23 (evening) · VERSION 0.1.0

## 📍 CURRENT STATE — 2026-09-23 (read this first)

This is the resume point for a **fresh session with no chat history**. The owner
may restart to update Claude Code before the Codex review at about 00:09. Everything
needed to carry on is in this block, `.claude/standing_tasks.md`, and the sections
below it.

### Where things stand

- **Branch:** `wip/alpha-consolidation`. **No code has changed since 21 Sept 08:26 UTC**
  (`1d56d37`, CI run `35577889183` green). The only commit after that is this
  session's notes-and-rules commit (see "What this session did").
- **No pull request is open.** One PR to `alpha` will be opened later, **only when the
  owner says** (W9). ⚠️ Pushing to `alpha` publishes a public pre-release automatically.
- The latest feature work (17–21 Sept) is disc identification, MakeMKV ripping, MeedyaDB
  contribution and TMDB film lookup. It is described in the dated sections below; the
  most recent is "2026-09-21 — VIDEO IDENTIFICATION IS NOW REACHABLE".

### Starting a fresh session — do these first

1. `git fetch origin && git status -sb`, then fast-forward if behind
   (`git merge --ff-only origin/wip/alpha-consolidation`). **Cloud sessions push to this
   branch too.** On 23 Sept this Mac's copy was 59 commits behind without anyone noticing.
2. Read this block, then `.claude/standing_tasks.md`: W2 (handoff), W3 (models),
   W12 (fallback), W13 (review loop), W15 (progress tables).
3. Check Codex is back (below). If it is, the catch-up review is the first job.

### ⏰ FIRST JOB: the owed Codex catch-up review

**Why it is owed.** All **59 commits from 17–21 Sept** (`74d0f59` … `1d56d37`: 67 files,
about 16,700 lines added) were built in **cloud Claude sessions**, where Codex was not
installed. They were checked **only by independent Claude reviewer agents**, which is the
fallback, not the standard (W12/W13). Those reviews did find and fix real defects,
recorded in the sections below. Codex has not seen any of this work.

**Why it has not happened yet.** Codex **is** installed on this Mac
(`/opt/homebrew/bin/codex`, v0.154.0). It is **out of usage credit** until
**24 Sept 2026 at 00:09** (local time), according to Codex's own message in a session
earlier on 23 Sept.

**How to run it (starting point; not yet run):**

```bash
git branch codex-review-base 02a5964   # the commit just before 74d0f59
codex review --base codex-review-base "<focus notes below>"
```

`--base` asks for a branch name, which is why the temporary branch is used. Passing the
commit ID directly has not been tested. Delete the temporary branch afterwards (it is
local only). The run of work is big, so it may be better to review it in parts, one
area per run (list below). **Review it as a whole body of work** as well, because
differences in approach show up across a run of work more than inside one commit.

**Areas, and what to point the reviewer at:**

| Area | Issues | Focus |
| --- | --- | --- |
| Disc identification engine (music + film) | #502, #504 | Scoring maths; music Disc ID calculation; Enhanced CD handling |
| MeedyaDB contribution | #502, #507 | Privacy: label text only sent in `full` mode; publishing off unless set up; contributor failure handling |
| MakeMKV backend + rip screen | #503 | Consent gate can't be bypassed; the copy-protection refusal still holds everywhere else; cancel and race handling in `MakeMKVRipViewModel` |
| Busy drive + unmount | #502 | Never unmounts on its own; device path conversion can't point at the wrong disk |
| TMDB film lookup + tag mapping | #205 | API key never leaks into errors or logs (including partial keys); label cleaning; cover art vs real video |
| Identify Disc screen + film identify on rip screen | #502 | "Promise vs delivery": does what the screen says happen actually happen? |
| Docs: `docs/Disc-Tools.md`, in-app help, `docs/api/meedya-convert-api.yaml` | — | Do they claim anything the code doesn't do? |

**The repeated defect to look for** (found five times so far): two correct pieces with
nothing connecting them, and tests that check the *promise* rather than the *delivery*.
Test: `grep -rn 'TypeName' Sources/ Tests/`. If every use outside its own file is under
`Tests/`, the feature doesn't reach users.

**The loop (W13):** read every finding and check it against the code. Fix the real ones
(Sonnet builds; Opus if complex), push, watch CI to green, and re-review until a round
finds nothing real. Write down any finding judged wrong, with the reason. Record the
number of rounds here and in the commit messages. If Codex is still out of credit, say
so plainly and use a fresh Claude reviewer only as a stopgap. That does **not** clear
this debt.

**Not verified:** whether work *before* 17 Sept ever had a Codex review. Older notes say
Codex was missing in those cloud sessions too. The scope above is only what is *known*
to be owed.

### After that: the queue (the owner hasn't scheduled these; recommended order)

| # | Task | Issue | Status | Notes |
|---|------|-------|--------|-------|
| 1 | Codex catch-up review of 17–21 Sept work | #502 #503 #504 #205 | Blocked: Codex out of credit until 00:09 | first job |
| 2 | Half-set-up MeedyaDB wrongly says "wasn't requested" | #507 | Queued | small; fix goes in `MeedyaDBContributor`, not in either screen |
| 3 | `AutoTagger` is never called, so looked-up tags are never written into files | #508 | Queued | part of #205 |
| 4 | Settings export/import (allow-list only, no secrets) | #506 | Queued | #505 depends on it |
| 5 | Saved submission queue for when MeedyaDB is down | #505 | Queued | only temporary failures go in the queue; privacy rules are in the section below |
| 6 | Full documentation sweep (W6) | — | Queued | before the PR |
| 7 | Hardware checks: real Enhanced CD, real drive unmount, real MakeMKV disc | #504 #503 | Blocked: needs a person with hardware | |
| 8 | MeedyaDB hosting + API key | — | Blocked: owner | nothing can actually be submitted until then |

### Questions for the owner (asked 23 Sept; carry on with other work meanwhile)

1. **Old plugin files at the repo root.** `PROJECT.md` and `.dev-team/autopilot.json`
   are the dev-team plugin's "autopilot" brief from July, and it says that mission
   finished on 1 July. The new rules say a plugin must not keep a second plan
   alongside the handoff. *Recommended:* keep both files, and add a line at the top of
   `PROJECT.md` saying it is historical and pointing to this handoff. Nothing will be
   moved or deleted without a yes.
2. **What comes after the Codex review?** *Recommended:* the order in the table above
   (#507 → #508 → #506 → #505), with each one proceeding on its own.

### What this session (23 Sept) did — notes and rules only, no code

- Fast-forwarded this Mac's copy by 59 commits (nothing local was overwritten; the copy
  was clean).
- **Standing rules updated** (`.claude/standing_tasks.md`), following the owner's
  directive of 23 Sept. Nothing was removed:
  - **W3:** analysis and planning now use **Opus**, one agent at a time. It used to be
    Fable with an Opus fallback. The owner's reason: the newest Opus is cheaper and at
    least as good. **Every older "retry Fable next run" note in this file is superseded.**
    `.claude/agents/deep-architect.md` was switched from Fable to Opus to match.
  - **W2:** when to update the handoff, and what it must carry. There is only one
    handoff.
  - **W4:** use the plugin for suggestions (raised, not built) and for review by a
    different system. It must not create a second handoff.
  - **W5:** now lists the `.OpenAI/` update, the cross-system review and the progress
    table; exit codes must be read directly.
  - **W6:** the documentation sweep runs before every PR.
  - **W12/W13:** when to hand over, when to go back, and how to stop the review loop.
    A fallback review must be named in the commit message.
  - **W15 (new):** progress tables.
  - §16 (plain English), W8 (autonomy, questions up front) and W9 (no PR stacking)
    were already in place and still match the directive.
- `.OpenAI/CONTEXT.md`, `MEMORY.md` and `README.md` were mirrored to match.
- The rules for all projects on this Mac (`~/.claude/CLAUDE.md`, linked as
  `~/.codex/AGENTS.md`) **already** covered plain English, the fallback rule and the
  Opus change. They were checked and not edited.
- **Review status of this commit:** notes and rules only. Codex was out of credit, so
  **it has not been reviewed by another system**. It is included in the catch-up
  review above.

## 📍 2026-09-17 state (superseded by the 2026-09-23 block above — kept as history)

This session was **governance + one research idea, not code.** Nothing in the
Swift app, CLI, API, releases or CI changed — the 2026-09-15 block below is still
accurate for the code. What changed this session:

- **New research issue #502** — "smart, content-based disc identification for
  ripping/imaging". Prompted by a user asking whether the MIT-licensed MakeMKV
  Claude skill `threadgill-dev/dvd-autorip-skill` (from a Reddit thread) could help
  copy and identify discs while making disc images. **Verdict in the issue:**
  useful as a *reference/technique* (identify a disc from its own
  subtitles/dialogue/runtime, not fuzzy title matching) and for operational
  lessons — but **not a drop-in** (it is a Claude-in-the-loop plug-in; we must stay
  offline-capable). The crux is a **legal/policy call on MakeMKV**: it *decrypts*
  protected discs, whereas our `DiscImagingController` deliberately *refuses* them.
  Filed as a **not-scheduled spike**, linked to #476 (orphaned disc engine) and
  #205 (metadata lookup/auto-tag). No implementation started.
- **New standing rules** in `.claude/standing_tasks.md`: §16 plain-English
  communication; W12 cross-LLM fallback; W13 cross-LLM review loop (Codex ⇄ Claude,
  fix-until-clean); W14 `.OpenAI/` memory mirror; and a §9↔W5 push-policy
  reconciliation (push-per-task is the rule on `wip/alpha-consolidation`). A
  device-level copy of the fallback + plain-English rules is at `~/.claude/CLAUDE.md`
  (ephemeral in a cloud container — the durable copy is the repo file).
- **New `.OpenAI/` folder** (`README.md`, `MEMORY.md`, `CONTEXT.md`) mirroring the
  Claude context so Codex/OpenAI tooling has the same continuity. Update it
  alongside `.claude/` after each task (W14).
- **Tooling notes for next session:** Fable 5.1 returned **"out of usage credits"**
  (HTTP 429) when spawned for the deep analysis, so this run fell back to **Opus**
  per W3 — **retry Fable on the next analysis/planning run.** **Codex is not
  installed** in this cloud session, so the review used an independent Claude
  reviewer (W13 fallback); a **full Codex cross-review is still owed** when Codex is
  reachable.
- **Review pass done + fixes applied.** An independent Claude reviewer checked the
  session's changes; three real fixes landed in a follow-up commit: (1) reconciled
  the contradictory commit-trailer wording in `.OpenAI/CONTEXT.md`; (2) fixed §9 in
  `.claude/standing_tasks.md` so it no longer says "no push" at the top while the
  reconciliation sat at the bottom; (3) corrected a **stale** "metadata lookup is
  dead in full / no URLSession" claim in `.claude/project_brief.md` — MusicBrainz
  lookup has actually executed since `90f37a3` (#205). One reviewer sub-claim was
  wrong and dismissed: commit `74d0f59` **does** carry the Co-Authored-By +
  Claude-Session trailers (confirmed in the CI run metadata).
- **IMPLEMENTED slice 1 of #502 (user said "let's do it", 2026-09-17).** Built the
  SAFE half: an **offline disc-identification engine** —
  `Sources/ConverterEngine/Disc/DiscIdentification.swift` (`DiscSignals`,
  `DiscIdentityScore`, `ScoredDiscMatch`, `DiscIdentifier.rank/buildQuery`) — that
  works out what a disc most likely is from its own content (running time, title
  text, year) and ranks candidate `MetadataResult`s. Pure, deterministic, offline,
  **no network / hardware / decryption**. Tests:
  `Tests/ConverterEngineTests/DiscIdentificationTests.swift` (XCTest, public API).
  Deep plan: `.claude/plans/disc-identification-plan.md` (written on **Opus** —
  Fable was out of credits on two retries; retry Fable next planning run).
  **Environment gap:** this cloud container has **no `swift` toolchain**, so the
  local build gate (W10) could not run — relying on the independent Claude reviewer
  (Codex not installed) + **CI** as the compile gate. Independent review came back
  **compile-clean** (it verified every initialiser order, access level,
  Sendable/Equatable synthesis, and SPM inclusion, and re-computed the scoring
  maths) and caught **one test bug** — a case-sensitive `reason.contains(...)`
  assertion that missed the capitalised string — now fixed. First push `2647c24`
  (CI run 307) built fine but failed that one test; the fix `26977de` is
  **CI-green (run 308)**. **Slice 1 is complete**, with a progress note on #502.
- **DECISIONS (owner, 2026-09-17) — 4 answers that set the autonomous plan:**
  1. **MakeMKV — APPROVED as an *optional, opt-in* backend** (owner accepted the legal
     implications). REVERSES the refuse-protected stance ONLY on the opt-in path;
     refuse-by-default stays everywhere else. Tracked in **#503** with guardrails (off by
     default, not bundled — user installs MakeMKV, terms acknowledgement, honest UI).
  2. **Identification next = keyless audio first** — a MusicBrainz Audio CD (disc/TOC)
     lookup, no API keys, feeding `DiscIdentifier`.
  3. **Full autonomy** — slice by slice, commit/push each, CI green, stop only for a genuine
     blocker.
  4. **Also tackle safe backlog** when this feature pauses (nothing release-, legal-, or
     people-gated).
  Work order: (a) keyless audio identification slice → (b) the #503 MakeMKV optional backend
  → (c) safe backlog. LATER identification slices: video providers + API-key UI (#205),
  wiring the orphaned readers + subtitle pipeline (#476), `AutoTagger` + UI. Fable is still
  "out of usage credits" (3rd retry failed) → planning on Opus, retry Fable next run; Codex
  still absent → Claude reviewer is the standing fallback (full Codex cross-review owed).
- **SLICE 2 of #502 DONE + CI-GREEN (`26fcb06`).** Keyless **MusicBrainz Audio CD
  (disc/TOC) lookup** — `Sources/ConverterEngine/Disc/MusicBrainzDiscLookup.swift`
  (`MusicBrainzDiscMatch`, `MusicBrainzDiscLookupService`,
  `musicBrainzTOCString(for:)`, `buildLookupRequest`, `lookup(disc:)` /
  `lookup(tocString:)`, `parseDiscLookup`) — turns an Audio CD's own table of
  contents into candidate releases with **no API keys**, feeding `DiscIdentifier`.
  Reuses the existing `MetadataHTTPClient` seam + throttle + sanitizer (so it is
  unit-tested with canned responses, no network in CI). `+ Tests`.
- **SLICE 3 of #502 DONE + CI-GREEN (`3a0108a`, CI run 312 = success).** The
  **MeedyaDB publishing hook** — `Sources/ConverterEngine/Disc/MeedyaDBPublisher.swift`
  (+ `MeedyaDBPublisherTests.swift`, 11 tests). Contributes an identified disc's
  identifiers to **MeedyaDB** (our combined all-in-one media database) via its
  `disc_ingest` endpoint and returns a MeedyaDB id to store against the disc.
  **Privacy posture (owner decision):** submission is **anonymised by default**
  (structural facts + public identifiers only; the disc's printed label text is sent
  ONLY in opt-in `.full` mode), and publishing is **off unless the user configures +
  enables it** (base URL + `mdk_` API key). Independent Claude review = **NO BLOCKERS**
  (3 non-blocking nits recorded as optional follow-ups: double-slash edge in baseURL
  stripping, apiKey not whitespace-trimmed for the header, no end-to-end body-strip
  test). No fixes needed. This closes the MeedyaConverter↔MeedyaDB integration loop
  on the engine side.
- **MeedyaDB repo bootstrapped (separate repo `MWBMPartners/MeedyaDB`, branch
  `wip/bootstrap`, CI runs #1/#2 green).** Its own governance (`.claude/` + `.OpenAI/`
  + handoff + copied standing rules), the API/schema design note
  (`docs/api-schema-design.md`), the schema (`appWeb/.sql/schema.sql`, 16 tables), and
  the **core JSON API** (`appWeb/public_html/api.php` + `includes/`: envelope, `mdk_`
  key auth, repositories) — endpoints health / resolve / entity / **disc_ingest** /
  identifier_add / link_add — with an installer, a PHP test harness, and CI that
  installs the schema into a real MariaDB. PHP 8.5 / MySQL, DreamHost shared hosting
  (no Composer), same house conventions as iHymns/WebMS-Intra/etc. The
  `MeedyaDBPublisher` above targets its `disc_ingest` contract. Continuity lives in
  that repo's `.claude/sessions/2026-09-17-HANDOFF.md`.
- **WORK ORDER from here (autonomous):** (a) keyless audio ID slice ✅ →
  (b) MeedyaDB publishing hook ✅ → **(c) #503 MakeMKV optional backend (NEXT)** →
  (d) safe backlog. Still-owed wiring (not yet started): wire `MeedyaDBPublisher` +
  a Settings UI (enable + baseURL + `mdk_` key) into the app, and wire
  disc-identification into the ripping flow (#476). MeedyaDB nice-to-haves:
  read/search browse endpoints + UI, admin (API-key CRUD, migration runner), Swagger-UI
  over an OpenAPI `api-docs.yaml`.
- **#503 MakeMKV optional backend — SLICE 1 DONE + CI-GREEN (`8350640`, run 314).**
  `Sources/ConverterEngine/Disc/MakeMKVBackend.swift` (+ `MakeMKVBackendTests.swift`)
  is a **pure** `makemkvcon` argument-builder (`info` / `mkv` / `backup --decrypt`)
  and robot-mode (`-r`) output parser (`parseRobotFields` handling quoted commas +
  doubled-quote escapes; `parseInfo` → `MakeMKVDiscInfo` with drives/titles/streams;
  `parseProgressLine` PRGC/PRGT/PRGV; `parseMessageLine` MSG; `parseDuration`). It
  **locates nothing, runs nothing, enables nothing, bundles nothing, and changes NO
  policy** — a test pins that the #492 copy-protection refuse-gate still refuses
  protected discs. **Deep planning:** Fable retried and was **out of credits (429)
  again** → planned on Opus; the independent review ran on **Opus** (Fable 429'd
  there too) and returned **BLOCKERS: none**; two of its robustness nits (trailing
  `\r` tolerance in the progress/message parsers; `TCOUNT` assign-on-success) were
  folded in before push. **Retry Fable next run.** **Remaining slices of #503:**
  (2) locator (`BundledToolLocator(toolName:"makemkvcon")`) + opt-in setting +
  terms-acknowledgement gate (RenderFarm `InsecureTransportOverride` consent
  pattern; GUI `@AppStorage` + explicit CLI flag; disc ripping is `studio` tier);
  (3) executor via the `ExternalToolRunning` seam (progress/cancel like
  `DiscImagingController`); (4) wire into the rip flow (#476) + feed titles into
  disc identification (#502); (5) docs + third-party licence notes + honest
  capability notes. MakeMKV is proprietary → **never bundled**, Direct-only distribution
  discipline (DR-0001) still applies.
- **#503 SLICE 2 DONE + CI-GREEN (`fb8adc8`, run 317).** The **off-by-default opt-in
  + terms-acknowledgement gate**, in two parts:
  - **2a engine gate** (`da3d3e7`) — `Sources/ConverterEngine/Disc/MakeMKVAccess.swift`:
    `MakeMKVConsent` (un-constructable except via `userAcknowledged(_:)`, mirroring the
    render-farm `InsecureTransportOverride`), `MakeMKVConsentStore` (reads injectable
    `UserDefaults`; `consent()` needs BOTH the `makemkv.enabled` toggle AND a non-blank
    `makemkv.termsAcknowledgement` — off by default), and `MakeMKVGate.readiness(...)`
    → `notEnabled` / `notInstalled(reason)` / `ready(binaryPath)` via `BundledToolLocator`.
    Never launches makemkvcon; refuse-gate (#492) untouched (a 2a test still asserts it).
  - **2b Settings UI** (`0091058`) — `Sources/MeedyaConverter/Views/MakeMKVSettingsTab.swift`
    + a `Tab` in `SettingsView`'s Encoding group. `@AppStorage` on the shared keys;
    toggle + (when on) acknowledgement + optional binary-path fields + a live honest
    Status verdict — never a dead button.
  - Both parts **reviewed clean on Opus** (Fable still 429 — retry next run). **CI-RED
    LESSON (run 316→317):** the first push failed one test — `MakeMKVAccessTests` shared a
    single `UserDefaults` suite name, and under `swift test --parallel` a sibling test's
    `setUp` `removePersistentDomain` wiped a value mid-test. Fixed by a **unique UUID suite
    per test instance** (`fb8adc8`). Reinforces the standing parallel-test rule: never share
    a mutable global (UserDefaults suite, temp path, top-level type name) across test methods
    — reviewers trace tests in isolation and miss `--parallel` races; CI is the real gate.
  - **#503 remaining:** (3) executor via the `ExternalToolRunning` seam
    (progress/cancel, streamed robot output → `MakeMKVBackend.parseProgressLine`);
    (4) wire into the rip flow (#476) + a CLI opt-in flag (explicit consent, since the CLI
    ignores GUI UserDefaults) + feed ripped titles into disc identification (#502);
    (5) docs + third-party licence notes.
- **#503 SLICE 3 DONE + CI-GREEN (`d6c7f15`, run 320).** The **executor** —
  `Sources/ConverterEngine/Disc/MakeMKVExecutor.swift` (+ tests). `MakeMKVExecutor`
  (Sendable struct) requires a `MakeMKVConsent` + resolved path at init (compile-time
  gate), reads no `UserDefaults`. `info(source:)` runs `makemkvcon info` to completion
  and parses; `rip(...)` streams typed `MakeMKVRipEvent` (progress/message) via
  `AsyncThrowingStream` with cancel + exit→error mapping; `make(readiness:consent:)`
  maps slice-2 output into `.notConsented`/`.launchFailed`. Injectable
  `MakeMKVLineStreaming` seam (production `MakeMKVProcessRunner` reads **stdout** —
  robot output is on stdout — line-buffered under NSLock, terminationHandler→
  continuation, SIGCONT+terminate; real-process path is manual-matrix only, like
  `ExternalToolRunner`) + a pure `MakeMKVLineAssembler` (byte-split on 0x0A, UTF-8-safe).
  Deep design + review on **Opus** (Fable still 429 — retry next run); no policy change.
  **CI-RED LESSON (run 319→320):** the review passed but the test target would not
  compile — `guard case MakeMKVExecutorError.launchFailed = (error as? MakeMKVExecutorError)`
  matches a non-optional against an `Optional`; unwrap with `guard let` first. Second
  time a review missed a compile/parallel subtlety CI caught (slice 2 = `--parallel`
  race). **CI is the definitive compile/test gate; reviews are advisory for it.**
- **#503 SLICE 4a DONE + CI-GREEN (`253f21e`, run 322).** The MakeMKV→identification
  bridge — `Sources/ConverterEngine/Disc/MakeMKVIdentification.swift` (+ tests):
  `MakeMKVIdentification.discSignals(from:discType:seedTitle:)` maps a `MakeMKVDiscInfo`
  (from the executor's `info()`) into the #502 `DiscSignals` fingerprint
  (`DiscIdentifier.rank` input) — main feature = longest title, all durations, chapters,
  audio/subtitle languages, disc/volume label, seed title, `.music` hint for audio discs.
  Pure; no policy change. **Self-reviewed + CI-gated** (verified against confirmed engine
  APIs: `DiscType.hasAudio`, `MediaLookupType.music`, `DiscSignals` init) — no CI red.
- **#503 REMAINING — needs an owner/architecture call (surfaced to user):**
  **(4b) the rip-flow ENTRY POINT (#476).** #476 ("disc ripping engine has no entry
  point") is a separate open epic; how to expose the (now-complete, consent-gated)
  MakeMKV rip is a genuine product/architecture fork — CLI subcommand (lowest-risk,
  testable; `Sources/meedya-convert/Commands/DiscCommand.swift` is the natural home;
  CLI takes explicit `--i-accept-makemkv-terms` consent, not GUI UserDefaults), a GUI
  rip flow, or both, and how far into #476 to go. **(5) docs + third-party licence notes.**
  RECOMMENDED default if proceeding autonomously: a minimal CLI opt-in `makemkv`
  subcommand first, GUI later. Engine layer (slices 1–4a) is DONE and independently usable.

## 📍 2026-09-20 — owner picked the GUI; music-disc identity closed

- **OWNER DECISION: #503 slice 4b = the GUI rip flow** (not the CLI). Design complete and
  saved at **`.claude/plans/makemkv-gui-rip-flow-plan.md`** — read that before touching 4b.
  It is grounded in real file:line evidence and includes a ranked list of **compile traps**
  with the proven in-repo alternative for each. Key correction it surfaced: the app layer
  **is** a testable library target (`MeedyaConverterCore` + `Tests/MeedyaConverterCoreTests`),
  so the scan→select→rip view model IS unit-testable with a mock `MakeMKVLineStreaming` —
  an earlier assumption that it was untestable was wrong.
- **NEW STANDING RULE (user, 2026-09-20): "ultrathink first + use workflows to plan AND do
  the work."** Added to W3 in `.claude/standing_tasks.md`, mirrored in `.OpenAI/CONTEXT.md`,
  **and** copied to the MeedyaDB repo and to the device-level `~/.claude/CLAUDE.md`
  (tool-agnostic wording). It sits on top of the sequential-Fable rule; it does not replace it.
- **MUSIC DISCS now identifiable AND contributable — `e017f89`, CI run 325 GREEN (#502).**
  The owner asked whether music discs could be identified and their ID submitted to MeedyaDB
  the way video discs are. They could be *identified* already (keyless MusicBrainz TOC lookup,
  slice 2 / `26fcb06`) — and that path is **stronger** than video's, because a CD's track
  layout is a near-fingerprint, so it is an exact hit rather than a ranked guess. Two real gaps
  were closed:
  1. **`Sources/ConverterEngine/Disc/MusicBrainzDiscID.swift`** — computes the canonical
     MusicBrainz **Disc ID**. `DiscTableOfContents.musicBrainzDiscId` had existed from day one
     and **nothing ever filled it**; the lookup service only built the *query* TOC string, never
     the disc's identity. Published algorithm (hex TOC → SHA-1 → base64 with `.`/`_`/`-`
     substitutions). Data tracks excluded + 150-frame pregap applied, so the Disc ID and the
     lookup string always describe the same tracks. **Verification:** the spec-derivable
     hash-input string is asserted directly, and the one non-inspectable constant was
     cross-checked against an independent implementation (a Python reimplementation run here).
     Real pressed discs remain a manual-matrix item.
  2. **`Sources/ConverterEngine/Disc/MeedyaDBSubmissionBuilder.swift`** — the missing join.
     **Nothing had ever built a MeedyaDB submission at all**, so `MeedyaDBPublisher` had no
     production caller. Now `audioCD(toc:matches:labelText:)` and
     `videoDisc(info:discType:ranked:labelText:)` both produce
     `MeedyaDBDiscSubmissionInputs`. Music: disc carries its Disc ID + TOC fingerprint + audio
     track count, Disc ID goes up as a `musicbrainz-discid` identifier, each matched release is
     a candidate with its `musicbrainz-release` id; several pressings can share one TOC so
     confidence is split evenly (1/N) rather than faking a single answer. Video: type/title
     count/label + ranked candidates carrying provider id (`tmdb`/`tvdb`/…) and scorer
     confidence. Privacy unchanged — the publisher still drops `labelText` outside opt-in
     `.full` mode, and publishing stays off unless configured and enabled.
- **MeedyaDB side (`3f2a35d` on `wip/bootstrap`):** `tblIdentifierTypes` was created but
  **never seeded**, leaving `identifier_add` unable to accept any type our apps use
  (`disc_ingest` does not validate types, so ingest itself already worked). Seeded 15 types
  idempotently (`INSERT IGNORE` + `uq_idtype`) incl. `musicbrainz-discid`; added `disc` to the
  documented `Scope` vocabulary; CI now asserts the seed landed and stays duplicate-free across
  the two installs it already did.
- **⚠️ STILL UNWIRED (the pervasive defect in this repo).** Everything above is engine-level.
  `MeedyaDBPublisher`, `MusicBrainzDiscLookupService`, `MakeMKVIdentification`,
  `DiscIdentifier.rank` and now `MeedyaDBSubmissionBuilder` are each referenced **only by their
  own tests** — no production caller yet. The GUI rip flow (4b) is the first thing that puts a
  real caller behind a button. A follow-up should wire the audio path (read TOC → look up →
  build submission → publish) into the Audio CD flow.

## 📍 OWNER DECISIONS — 2026-09-20 (answered via questions; drive the work order)

1. **Enhanced/CD-Extra disc IDs → record BOTH (owner's own proposal, better than the
   options offered).** Use the **music-only** portion for MusicBrainz and similar
   lookups (that is the ID they recognise), but store **both** IDs in MeedyaDB — the
   music-only one as the matching key, and the **whole-disc** one as an extra
   identifier — for "full, proper coverage".
   - *Why it works:* `DiscSession.leadOutSector` already exists
     (`AudioDiscFidelity.swift`), so when a disc reports its session layout we can use
     session 1's **actual** lead-out — no guessed constant. Only when session info is
     absent do we fall back to deriving it from the data track's start minus the
     standard session gap; that fallback is the ONLY unverified part and must be
     confirmed on a real Enhanced CD (see #504).
   - *Design:* `musicBrainzDiscId` = music-only (MusicBrainz-compatible);
     whole-disc ID goes up as a separate identifier (needs a new seeded type in the
     MeedyaDB repo). On a plain audio CD the two are identical, so nothing changes for
     the vast majority. The whole-disc ID is the MORE precise physical key (same album,
     different bonus content ⇒ same music-only ID, different whole-disc ID).
   - `musicBrainzTOCString` must move in lockstep with the music-only calculation or the
     ID and the lookup would describe different discs.
2. **After a MakeMKV rip: just save the files.** No auto-queueing, no auto-identify in
   this first version — keep the hardware-dependent path simple and diagnosable.
3. **MeedyaDB: build the wiring now, deploy later.** Both sides are already CI-proven
   against the same contract; deployment needs hosting/DB credentials only the owner can
   provide. Wiring now means it works the day it is deployed.
4. **Next after the rip screen: make identification actually run** — read disc →
   identify → contribute, **music CDs first**. This is the priority because every part is
   built and tested but *nothing calls any of it* (the standing "builder exists but
   unwired" gap). Slice 5 (MakeMKV docs/licences) comes after.

## 📍 2026-09-20 (later) — slice 4b SHIPPED + dual disc IDs SHIPPED, both CI-green

- **#503 SLICE 4b DONE + CI-GREEN (`7ce4d04`, run 329).** The **MakeMKV rip screen** —
  the owner-chosen entry point for the engine from slices 1–3. Sidebar entry (hidden in
  App Store builds), gated state that always offers a way forward, then
  source → scan → pick titles → destination → rip with live progress → outcome.
  - `Sources/ConverterEngine/Disc/MakeMKVRipPlanning.swift` (pure: progress folding,
    title formatting, default main-feature selection, run planning, aggregate progress,
    plain-English failure text) + `MakeMKVRipViewModel` (`@MainActor @Observable`, with
    the line-streaming seam injected so the whole scan→rip flow is unit-tested with
    canned output) + `MakeMKVRipView`.
  - **Ripped files are simply saved** — no auto-queueing or auto-identify (owner's call).
  - Implemented by a Sonnet agent from `.claude/plans/makemkv-gui-rip-flow-plan.md`; it
    caught three real problems itself (a shared failure message that would have said
    "the rip was cancelled" on a *scan*; a singular/plural title count; and that
    `Result<_, String>` does not compile because the failure type must be an `Error`).
  - **CI-RED LESSON (run 328→329):** `Task { [weak self] in await self?.doThing() }`
    infers `Task<()?, Never>`, which does not match a declared `Task<Void, Never>`.
    `guard let self else { return }` first. **Third time this session CI caught what a
    review did not, all the same class: code that reads correctly but does not
    type-check.** For this repo's SwiftUI, reviews are for logic; CI is the compile gate.
  - Known gap (deliberate, follow-up): the source picker offers drive / device / ISO but
    not a pre-decrypted `VIDEO_TS`/`BDMV` folder (`MakeMKVSource.file`).
- **DUAL DISC IDs DONE + CI-GREEN (`b567642`, run 329; MeedyaDB `7569e99`, run 8).**
  Implements the owner's decision above.
  - `MusicBrainzDiscID.musicSessionLeadOutSector(for:)` reports **where the music ends
    and how it knows**: `.reportedSession` (the disc said so — exact),
    `.derivedFromDataTrack` (data-track start − 11,400, the ONLY estimate, and refused
    if it would land before the last music track), or `.singleSession` (a plain CD).
    `sessionGapSectors` is written as `6750 + 4500 + 150` so it reads as lead-out +
    lead-in + pregap rather than a magic number.
  - `compute(for:)` = music-only (MusicBrainz-compatible); `computeWholeDisc(for:)` =
    whole physical disc. **Identical on an ordinary CD** (pinned by a test).
  - ⚠️ **`musicBrainzTOCString` changed in lockstep** — a deliberate behaviour change:
    lookups for Enhanced CDs now ask about the music portion, which is what MusicBrainz
    can actually answer, so those discs should start matching where before they never did.
  - Submission sends music-only as the disc key + `fulldisc-discid` when it differs
    (source `meedyaconverter`, NOT `musicbrainz` — they never produce that value).
  - Expected IDs were computed independently before implementing and then confirmed by
    CI: music-only `CPTueITWo5NCOrtwPU8RgeVxyrA-`, whole-disc
    `gxp6QVA8pvq._RJLsqjz8ptjZXk-`, music-only TOC `1+2+88750+150+20150`.
  - Still owed: a real Enhanced CD to confirm the estimated path (#504).
- **MeedyaDB also gained OpenAPI + self-hosted Swagger UI** (`541fb0e`, run 7): a full
  OpenAPI 3.1 description of the real API and a browsable page at `/api-docs/`. The
  viewer is fetched by `tools/vendor-swagger-ui.sh` (plain curl, no Docker/Node — suits
  shared hosting), served from our own host, and checksummed. Outbound fetch is blocked
  in this container, so the assets could not be vendored here and the page says what to
  run instead of failing silently.
- **⚠️ ENVIRONMENT GOTCHA:** backticks inside a double-quoted `git commit -m "..."` are
  executed by the shell and silently eat words from the message (it happened once and
  was fixed by amending). **Use `git commit -F <file>` with a quoted heredoc.**

## 📍 2026-09-20 (latest) — rip screen hardened + IDENTIFICATION NOW ACTUALLY RUNS

Branch `wip/alpha-consolidation`. Three commits, CI-green through `996cc19` (run 332);
`1bee778` pushed and awaiting its run.

### 1. Rip-screen review findings closed (`a1f4652`, run 331 green)

The cross-review of slice 4b found **no blockers** but three MAJOR items. All fixed,
plus four MINORs the fixes exposed.

- **MAJOR-1 — `cancelScan()` raced its own task.** It eagerly cleared `isScanning`,
  `scanTask` and wrote `scanErrorMessage`, all of which the cancelled task's tail also
  writes. A stale task could land on top of a *newer* scan: re-enabling the button,
  orphaning `scanTask`, overwriting the new message. It now **only cancels**, exactly as
  `cancelRip()` already did. Note the second-order effect that makes this a real close
  rather than a narrowing: because `isScanning` now stays true until the cancelled task
  finishes, `scan()`'s own guard blocks a new scan for that whole window, so the race
  has nowhere left to happen.
- **MAJOR-2 — a scan could not be cancelled from the UI at all.** Cancel button added to
  the Titles progress row (the same place the rip's Cancel sits — deliberately ONE
  cancel affordance, not two).
- **MAJOR-3 — disabled buttons said nothing.** `scanBlockedReason` / `ripBlockedReason`
  on the view model (not in the view, so the wording is unit-tested) name the next step.
- MINOR-2 (`rip()` cleared live state above its already-running guard, so a second press
  wiped the running rip's log), MINOR-3 (`isCancellingScan`/`isCancellingRip` — without
  them the new Cancel button looks inert for minutes while makemkvcon winds down),
  MINOR-5 (stale cross-operation banners).
- MINOR-4 — **real in-flight cancellation is now tested.** `BlockingMakeMKVRunner` parks
  a call until the task is cancelled, with a start signal so tests reach the mid-flight
  state deterministically — no sleeping, no polling, safe under `--parallel`.

### 2. Music-disc identification WIRED END TO END (`996cc19` run 332 green, `1bee778`)

**This was the "everything is built and nothing calls it" gap, now closed for music.**
Confirmed by grep beforehand: `MusicBrainzDiscID`, `MusicBrainzDiscLookupService`,
`MeedyaDBSubmissionBuilder` and `MeedyaDBPublisher` were each referenced ONLY by their
own tests.

- **A real TOC reader already existed** — `DiscImagingController.readTableOfContents`
  (cdrdao `read-toc`), already used by `meedya-convert disc toc`. The gap was never
  "nothing can read a disc"; it was that nothing chained reader → identify → contribute.
- **NEW `Sources/ConverterEngine/Disc/MusicDiscIdentification.swift`** —
  `MusicDiscIdentifier.identify(toc:labelText:contribute:mode:)` does that chaining.
  Reading the disc is deliberately NOT part of it (that needs hardware), so the whole
  flow is unit-testable with no disc, no network, no MeedyaDB.
- **NEW CLI `meedya-convert disc identify`** — `--device` (reads a real disc) or `--toc`
  (a file saved earlier); text or JSON; `--offline` computes IDs and contacts nothing.

**⚠️ THE FAILURE POSTURE IS THE DESIGN — do not "tidy" it into something tidier.** A CD's
track layout is a near-fingerprint, so the locally computed IDs are valuable alone:
- a MusicBrainz outage does **not** throw and does **not** abandon the run — the IDs are
  kept and the contribution still goes ahead, because a disc MusicBrainz has never heard
  of is exactly the one MeedyaDB most wants;
- MeedyaDB being off or unconfigured is **`.notAttempted`, never `.failed`** — that is
  everyone's situation until the server is live, and must never show as an error;
- cancellation stays cancellation and is never folded into `.failed`;
- a disc with no audio tracks short-circuits **before** the network (zero requests).
- The only error `identify` throws is `CancellationError`.

**Privacy decisions in the CLI:** contributing is opt-in on *every run* (`--submit`),
never a stored setting someone ticked and forgot; the API key comes from
`MEEDYADB_API_KEY` and is **never** an argument, because arguments are visible to other
users via `ps`; `--submit` exits non-zero whenever nothing reached MeedyaDB, so a script
can never read "exit 0" as "contributed".

### 3. Review of the above (`1bee778`) — no compile errors, two real defects

- **MAJOR — the privacy wiring was untested.** Nothing passed `labelText`/`mode` through
  `identify()`, so hardcoding `mode: .full` would have left every test green while
  anonymous users began sending disc labels. The scrub was tested one layer *down*, in
  the publisher, which cannot catch a wiring mistake above it. Now two tests decode the
  body that actually reached the wire.
- **MAJOR — `--offline --submit`** parsed, exited 0 and sent nothing while skipping the
  loud "MeedyaDB isn't set up" gate. `validate()` now rejects it.
- MINORs: trim mismatch (a newline-only API key passed the CLI gate then failed quietly
  downstream); "no audio tracks" printed under "Audio tracks: 3" for a *damaged* TOC, now
  a distinct state; `identity(for:)` always computed the disc ID while the builder prefers
  a stored one, so shown ID ≠ sent ID — now the same preference, and `isEnhancedCD` is
  decided **structurally** (from `leadOutSource`) rather than by comparing ID strings,
  which a stale stored tag would break; cdrdao's `.bin` sidecar was leaking from both
  `disc identify` and the pre-existing `disc toc`.
- **Filed, not fixed:** the submission builder can attach a spurious `fulldisc-discid` to
  a plain CD when the TOC carries a stored ID, because it compares a *stored* value with
  a *computed* one. Pre-existing and unreachable today (nothing writes that field).

### NEXT, in order

1. **MeedyaDB config source** — nothing constructs `MeedyaDBPublisherConfig` in the app.
   Needs a settings tab + `meedyadb.enabled`/`meedyadb.baseURL` (house style: an engine
   `Keys` enum like `MakeMKVConsentStore`) and the API key in the **Keychain** —
   `APIKeyProvider.meedyaDB = "meedya_db"` already exists in `APIKeyManager.swift`.
   NOT `@AppStorage`: that is plain-text `UserDefaults`.
2. **A GUI screen** for identify (NavigationItem case + `systemImage` + `accessibilityLabel`
   arms + `ContentView.detailView` arm + a SidebarView row).
3. #503 slice 5 — MakeMKV docs/licences.
4. Video-disc identification has the same wiring gap; `MeedyaDBSubmissionBuilder.videoDisc`
   exists and has no production caller.

**⚠️ Known blocker for a GUI disc read on macOS:** `RawCDReadPlanner.buildMacOSUnmountArguments`
is deliberately unwired — the medium must be unmounted before cdrdao can claim the device,
and mapping a cdrdao `--device` string to a `diskutil` node needs real hardware to verify.
Expect "device busy" on an auto-mounted disc until that is resolved.

## 📍 2026-09-21 (overnight) — the owner's whole queue, cleared

Branch `wip/alpha-consolidation`. Owner answered four questions before sleeping and
asked for the rest of the queue to be worked autonomously. All four answers applied.

### OWNER DECISIONS — 2026-09-21

1. **Busy drive:** explain it and offer an **Unmount button**; never unmount silently.
2. **Video discs:** wire them the same way as music, **including the GUI**.
3. **Queue:** do **all** of it (MakeMKV docs, the fulldisc fix, VIDEO_TS/BDMV source,
   MeedyaDB settings screen).
4. **No PR yet** — keep accumulating on the branch (matches the no-stacking rule).

### What landed (all CI-green unless noted)

| Commit | What | Run |
| --- | --- | --- |
| `eee5289` | fulldisc-discid fix (was a filed follow-up; owner asked for it directly) | 337 |
| `6f4ee66` | MeedyaDB settings tab (UI) | 337 |
| `1a3be8f` | Pre-decrypted VIDEO_TS/BDMV rip source (#503) | 337 ✅ |
| `202ef0a` | **Video disc identification wired end to end** | 338 ✅ |
| `8dc5287` | Busy-drive detection + `diskutil` unmount | 339 ✅ |
| `8df1936` | **In-app Identify Disc screen** | 340 |
| `1aaf596` | Disc-tools docs + in-app help + MakeMKV licence position (#503 slice 5) | 341 |

### The things worth knowing later

- **`MeedyaDBContributor` is now the ONE place the contribute failure posture lives**
  (`MeedyaDBAccess.swift`). Music and video both go through it. Those judgement calls —
  off is not failed, a real rejection is, cancellation stays cancellation, an
  unmatchable submission is skipped rather than sent as noise — would drift if copied.
  `MusicDiscIdentifier` kept its public init and now delegates; its two shared reason
  strings are forwarded so the two can never disagree.
- **Video identification is a RANKED GUESS, not an exact hit.** Music gets an exact
  MusicBrainz match from the TOC; video is scored on running time / title / year and
  the summary says "Best guess: X (98% confident)" on purpose. Do not "tidy" that into
  a flat statement of fact.
- **Video candidates are passed IN by the caller.** Every video provider is keyed and
  none is wired up (#205), so `candidates: []` is the normal case today — and the disc
  is still contributed on its structural fingerprint alone. That is not a failure.
- **`buildMacOSUnmountArguments` is no longer unwired.** Its old note said the blocker
  was mapping cdrdao's `--device` back to a `diskutil` node, unverifiable without
  hardware. That mapping is NOT needed in this direction: the app is handed a device
  path and `DriveListingParser.diskNode(forRawDeviceNode:)` just undoes the
  well-defined `/dev/diskN` → `/dev/rdiskN` transform. A path not in that form is
  passed through untouched so `diskutil` rejects it, rather than being mangled into a
  different device and unmounting the wrong disk. Round-trip test pins the pair.
- **Unmounting is NEVER automatic** (owner decision). `DiscBusyDetector` decides which
  remedy to offer; getting it wrong costs in both directions, so it is conservative and
  both directions are tested.
- **`isEnhancedCD` is now structural**, from `leadOutSource`, not a comparison of two ID
  strings — a stored/stale disc-ID tag would otherwise make an ordinary CD look Enhanced.
- **`VideoDiscIdentificationResult` is deliberately NOT `Equatable`** — it carries
  `ScoredDiscMatch`, whose `MetadataResult` is `Codable, Sendable` but not `Equatable`.
- **A static stored property on a `@MainActor` type is MainActor-isolated**, so it can't
  be a default argument evaluated at a nonisolated call site. `DiscIdentifyViewModel`
  inlines its TOC-reader default closure for exactly that reason.

### CROSS-REVIEW OF THE ABOVE — one blocker, fixed in `ba922a9` (run 343 green)

No compile errors. But two real defects, both the same shape and both in the new screen:

- **BLOCKER — the screen could promise a contribution and never send one.** It held ONE
  `MusicDiscIdentifier` built at construction; the production default builds it with an
  empty, DISABLED publisher, and the MeedyaDB config it had just read was never handed
  to it. Fully configured, the screen showed "This disc will also be contributed" and
  then "MeedyaDB publishing is turned off", having sent nothing. The identifier is now
  built PER RUN from the config in force, and `contribute` is derived from that SAME
  value, so promise and delivery cannot drift apart.
- **MAJOR — the Settings privacy picker was a dead control.** `MeedyaDBConfigStore
  .submissionMode(in:)` had zero readers; the screen always sent anonymously while the
  tab warned about sending the disc label. Only ever under-sent, but it broke the rule
  written into that same file: a setting that is on and silently doing nothing is worse
  than one that is off. Now read per run; the disc's CD-Text rides along as the label
  (still stripped by the publisher unless the mode is `full`).
- Plus: the retry re-read whatever the form said rather than the drive it had just
  released; a hung `diskutil` could not be cancelled; "permission denied" made the
  screen assert a fact that may be false.

**The tests were structured so neither could be caught** — they asserted the PROMISE,
never the delivery, and the fixture paired ready settings with a disabled publisher,
mirroring the bug. Three tests now assert on the bytes reaching the wire.

### NEXT

1. **#205 — the keyed metadata providers.** This is now the binding constraint on video
   identification: the chain runs, but nothing supplies candidates.
2. A real Enhanced CD to verify the derived lead-out (#504), and a real drive to verify
   the unmount path. Both need a person with hardware.
3. MeedyaDB hosting + credentials before anything can actually be submitted.
4. `AutoTagger` still has no callers (#205).

## 📍 2026-09-21 — VIDEO IDENTIFICATION IS NOW REACHABLE (`a9f7646`)

The handoff said "Video disc identification wired end to end (`202ef0a`)". That
was true of the ENGINE chain and false of the app: **`VideoDiscIdentifier` had no
production constructor at all.** All eighteen were in tests.
`TMDBDiscCandidates.provider(service:)` — the thing that feeds it candidates —
appeared only inside a doc comment, and the CLI's `disc identify` is music-only.
Fully built, fully tested, and no way in.

### ⚠️ THE RECURRING DEFECT, FOR THE FOURTH TIME

Two correct components, no connection between them, and tests that assert the
PROMISE rather than the DELIVERY. The previous three were the identify screen's
disabled publisher, the dead submission-mode picker, and the untested privacy
wiring. **When a piece of work "lands", grep for a PRODUCTION caller before
believing it.** `grep -rn 'TypeName(' Sources/ Tests/` and look at which
directory the hits are in — if they are all under `Tests/`, it does not ship.

### Where it went, and why not the Identify Disc screen

The **MakeMKV Rip screen**. A film disc has no table of contents: its structure
only exists once MakeMKV has scanned it, and that screen already holds the scan
result (`discInfo`) and the consent gate. Doing it on the Identify Disc screen
would mean a second scan (minutes on a Blu-ray) and a second copy of the consent
gate. The Identify Disc screen now carries one line saying where to go, so the
feature is discoverable and not merely reachable.

Music is the other way round for a good reason: it reads a TOC with cdrdao,
needs no MakeMKV, and gets an EXACT MusicBrainz hit rather than a ranked guess.

### The things worth knowing later

- **`MakeMKVIdentification.suggestedDiscType(from:)` is a SUGGESTION, and returns
  an Optional to force callers to say so.** The identifier needs a `DiscType` and
  nothing could supply one. That file's header says MakeMKV's type strings are
  localised free text and are not relied on — still true: the picker is
  pre-filled, always editable, and simply stays EMPTY when MakeMKV said nothing
  recognisable, with the button explaining it needs an answer. A wrong disc type
  reaches a shared database and cannot be walked back.
- **⚠️ The order of the checks in `suggestedDiscType` is load-bearing.** Every
  later pattern is a substring of an earlier one's real strings: "UHD Blu-ray
  disc" contains "blu-ray", "HD DVD disc" contains "dvd". Reordering them
  silently DOWNGRADES discs. A test pins every pair — this is the same class of
  mistake as CI run 349's noise list, so it is pinned rather than trusted.
- **Substring matching survives localisation** ("Disque Blu-ray" still matches)
  because the surrounding words get translated while the format names are proper
  nouns. That is why it is `contains`, not equality.
- **Identification starts NO subprocess** — it works from the scan already in
  hand — so it is deliberately NOT put back through `gatedExecutor()`. The gate
  was satisfied by the scan that produced the data; re-checking would refuse to
  name a disc the user had legitimately scanned. A test pins that identifying
  adds no second MakeMKV call.
- **It does not block on `isRipping`** either, for the same reason: no tool, no
  file, so there is no cause to make someone wait out an hour-long rip.
- **All three of the identify screen's shipped defects are designed out, not
  re-fixed.** The identifier is built PER RUN from the config in force (a stored
  one promises a contribution and sends nothing); the submission mode is read per
  run (or the Settings picker is a dead control); the label comes from the same
  `DiscSignals` that were ranked (so what is shown and what is sent cannot
  disagree).
- **A scan clears the previous disc's identification.** Leaving the last film's
  name on screen while a different disc is scanned is worse than showing nothing.

### CROSS-REVIEW OF THE ABOVE — two MAJORs, fixed in `4689693` (no blockers)

The review found **nothing that failed to compile and nothing that failed CI**
(run 356 was green on build, all tests and SwiftLint before the fixes landed).
Both defects were in the new VIEW wiring, not the engine, and both were the
house recurring shape yet again — promise and delivery drifting apart.

- **MAJOR — a scan could start while an identification was still running.**
  `scan()` guarded `!isScanning, !isRipping` but not `!isIdentifying`, so the
  Scan button stayed live through a run that can take a dozen TMDB requests.
  `scan()` clears `identifyResult`; the in-flight run's tail then writes the
  OLD disc's answer straight back, and the previous film's name sits under a
  different disc. **The test that "covered" this only ran the SEQUENTIAL case**
  — identify, await, then scan — which is the easy half and proves nothing
  about the interleave the live button invites.
  Fixed by making scanning and identifying exclude each other. Worth keeping
  the second-order reason: an in-flight run now always reaches its own tail
  BEFORE a new scan can begin, so everything it writes is written before
  `scan()` clears — and `scan()` clears it. **The guard, not the clearing, is
  what makes the race impossible** — the identical insight that fixed
  `cancelScan()` earlier. The new test parks the lookup so a run is genuinely
  in flight.
- **MAJOR — the contribution notice could go stale.** The screen read the
  MeedyaDB verdict only in `.onAppear`. **Settings is a separate window on
  macOS**, so this screen never disappears while someone changes a setting
  there and `.onAppear` never fires again: the notice kept saying contributing
  was off while the run (correctly re-reading the setting) contributed, or
  promised one that had just been switched off. `DiscIdentifyView` already
  watched the keys with `@AppStorage` + `.onChange`; the rip screen now does
  too. ⚠️ **`.onAppear` is not "re-read rather than cached" on macOS.** The
  Keychain-held API key still cannot be watched — same limit on both screens.
- **MINOR, filed as #507, not fixed here.** With MeedyaDB on but unconfigured,
  the after-the-run line says contributing "wasn't requested" when it was.
  Both screens collapse the three-state `MeedyaDBReadiness` into a `Bool`
  before `MeedyaDBContributor` sees it, so `.incomplete` is indistinguishable
  from "never asked". Fixing it belongs in the shared contributor — patching
  one screen would start exactly the drift that type exists to prevent.
- **Checked and clean** (don't re-check): the TMDB key seam is genuinely
  connected to the Settings field, the submission-mode picker is genuinely
  read, `.onDisappear`/`deinit` cancel the new task, and no real-world MakeMKV
  type string produces a WRONG disc type under the current check order. Some
  builds report a UHD disc as plain "Blu-ray disc" — a downgrade the editable
  picker and its caption are the designed answer to, not a defect.

## 📋 QUEUED — not scheduled

Work the owner has asked for but not scheduled. Each has a GitHub issue; the issue is
the source of truth, these are one-line pointers.

> ⚠️ **The check that found #502's gap and #508: before believing a feature landed,**
> `grep -rn 'TypeName' Sources/ Tests/ --include=*.swift` — **if every hit outside the
> type's own file is under `Tests/`, it does not ship.** Five instances so far, all the
> same shape: two correct components, no connection, tests asserting the promise.

| Issue | What | Raised |
| --- | --- | --- |
| **#505** | **Persistent submission queue** — retain a MeedyaDB contribution when the service is down, survive restarts, retry with backoff, and make the queue exportable/importable between installs. | 2026-09-21 |
| **#506** | **Settings export/import** — move a MeedyaConverter setup between installations as one versioned JSON file. Raised as the "necessary, implied" feature behind #505, which depends on it. | 2026-09-21 |
| **#507** | **Half-configured MeedyaDB says "wasn't requested"** when it was — both screens flatten the three-state readiness into a Bool before the shared contributor sees it. Fix belongs in `MeedyaDBContributor`, not one screen. | 2026-09-21 |
| **#508** | **`AutoTagger` is never called** — looked-up metadata is never embedded during an encode. The fifth "no production caller" find; part of #205. | 2026-09-21 |

### #505, the parts that need care (full reasoning in the issue)

- **Only MeedyaDB receives submissions today.** MusicBrainz and TMDB are read-only for
  us — a failed *lookup* has nothing to queue, it should just be retried. Build the
  queue provider-agnostic anyway: MusicBrainz disc-ID submission is the obvious next
  producer.
- **Queue transient failures only.** Transport/5xx/429 yes; 401 and 400 never — a bad
  key or a malformed payload does not fix itself, and retrying is a loop that hammers
  someone's server. The decision belongs in **`MeedyaDBContributor`**, already the
  single home of the contribute failure posture.
- **⚠️ Privacy.** Never queue while contributions are OFF (otherwise the app stockpiles
  data the user declined to send, and switching it on later fires a backlog they never
  agreed to). Store the **already-scrubbed wire payload**, not the inputs — queueing
  inputs means a later switch to `full` would send a label that was queued under
  `anonymous`. The user must be able to see and delete what is held.
- **Export/import now has a host: #506.** The open question ("standalone, or drive the
  creation of settings export/import?") was ANSWERED by the owner on 2026-09-21 — it
  drives it. The queue is **one category inside #506's envelope**, not a second bespoke
  file format. Import still means submitting someone else's data under your API key:
  validate the file, say so plainly, and never put credentials in an export.
- Also: backoff with a ceiling, a dead-letter state rather than infinite retry,
  de-duplicate on enqueue, cap the queue, and store it in Application Support as JSON
  with atomic writes — not `UserDefaults`.

### #506, the parts that need care (full reasoning in the issue)

- **⚠️ The export must be an ALLOW-LIST, never a dump.** Two credentials are sitting in
  plain `UserDefaults` right now, verified: `mediaServerAPIKey`
  (`MediaServerSettingsView.swift:42`) and `webhookCustomHeaders`
  (`WebhookSettingsView.swift:55`), which is free-form JSON people put
  `Authorization: Bearer …` into. A whole-defaults export would carry both. A
  deny-list is the wrong shape — the next `@AppStorage("…apiKey")` anyone adds would
  silently widen the export and nobody would notice until a settings file was emailed
  to someone. Pin it with a test that fails when a new key is added without a decision.
- **Credentials never go in the file at all.** Not encrypted, not opt-in. Settings files
  get emailed and dropped in shared folders. Import should instead TELL the user which
  services still need a key and where to put it. (The SMTP password and every
  `APIKeyProvider` key are already correctly in the Keychain — follow that pattern.)
- **Some settings must not travel.** Tool paths (`customFFmpegPath` and friends) break
  across an Intel/Apple-Silicon Homebrew prefix change, and `accurateRip.driveOffset` is
  a **physical property of one optical drive** — copying it produces rips that fail
  verification and look like bad discs. Hence categories, with a "this machine" group
  excluded by default.
- **Copy the encoding-profile pattern, it already works.** Engine owns the format and
  validation (`profileStore.exportProfile`/`importProfile`), the view owns the panels
  (`ProfileManagementView`), the CLI gets the same verbs (`ProfilesCommand`). That split
  is what makes the format testable without a UI.
- Also: versioned envelope, validate-then-apply (never half-apply), preview by category
  before writing, merge by default, and refuse unknown keys rather than writing them
  into `UserDefaults`.
- Separate pre-existing bug worth fixing on the way past: `mediaServerAPIKey` should move
  to `APIKeyManager`/Keychain. The export must be safe either way.

## 📍 2026-09-21 — #205: TMDB EXECUTES, and is reachable

Owner said "proceed with #205 autonomously". Reading the issue properly first
changed the plan: **MusicBrainz already worked** (wired into the tag editor's
Look Up sheet, Sept 3). What was dead was the **keyed** providers. TMDB is the one
that matters — it is what would name a film on a disc, and what tags a video file.

| Commit | What | Run |
| --- | --- | --- |
| `20d34be` | `TMDBLookupService` (real execution) + `TMDBDiscCandidates` + candidate seam | 346 ✅ |
| `d5bba98` | TMDB key field in Settings → Metadata | 346 ✅ |
| `448768e` | `TMDBTagMapping` + `EmbeddedArtwork` cover-art detection | 347 ✅ |
| `04f4605` | TMDB lookup sheet in the tag editor | 347 ✅ |

### The three things that would bite a later session

1. **THE API KEY HAS TWO FORMS AND ONE OF THEM TRAVELS IN THE URL.** TMDB issues a
   v3 API key (32 hex, query parameter only) *and* a v4 read access token (a JWT,
   `Authorization: Bearer`). Both work; people paste whichever they find, so
   `usesBearerToken(_:)` detects which. Because a v3 key is in the URL, **no error
   in `TMDBLookupService` may ever carry a URL** — they carry an endpoint NAME
   (`search/movie`) — and server text goes through `redacting(_:)`. A test sweeps
   five failure paths asserting the key is in none of their messages. **Keep that
   sweep if you add an error case.**
2. **SEARCH RESULTS HAVE NO RUNNING TIME.** Only `/movie/{id}` does. Running time is
   by far the strongest signal `DiscIdentifier.rank` has, so a result set without it
   ranks every candidate alike — noise that *looks* like working code. `withRuntimes`
   fills it in for the top few (capped: one request each). TMDB reports `0` for
   "unknown", treated as absent — a zero-length film would score terribly.
3. **ffprobe REPORTS COVER ART AS A VIDEO STREAM.** `MediaFile.hasVideo` is therefore
   TRUE for an artwork-tagged MP3. Anything deciding "film or song?" must use
   **`looksLikeVideoContent`** (excludes still-image codecs AND requires a container
   that can hold video). Using `hasVideo` sends music files to the film database.

### Deliberate limits

- **Films only.** TMDB gives one running time for a film but an array of typical
  episode lengths for a series — not the same quantity, so ranking a series against
  a disc's main feature would be wrong. TV needs its own comparison rule.
- **`SuiteCoreMetadataAdapter` still throws `.notImplemented` for TMDB.** It has no
  access to an API key, it is never instantiated anywhere in `Sources`, and wiring a
  real lookup into an unwired router would add nothing while breaking
  `ConverterEngineTests+SuiteCore.swift`'s pinned "every other source throws" test.
- **Only TMDB gets a key field.** TheTVDB, OMDb, Discogs, FanArt.tv and OpenSubtitles
  are still URL builders with no caller; the settings tab NAMES them and says they
  will appear as each starts working, so their absence reads as honest rather than
  forgotten. Offering a box for a provider nothing calls is the dead-control defect
  this project keeps shipping.

### Cross-review of the TMDB work — 1 blocker + 4 logic errors, all fixed (`07915e3`, run 350 ✅)

CI was green on all of it beforehand, which is the point: every one of these builds,
passes and is wrong.

- **BLOCKER — a partial API key could escape.** Error snippets were truncated to 200
  characters and *then* redacted; a proxy echoing the request URL could leave a
  31-of-32-character fragment that whole-key matching cannot see. Redaction now
  precedes truncation. The old sweep test could not have caught it (whole key only);
  the new one echoes the key across the cut and sweeps 8/12/16/24-char substrings.
- **The label cleaner destroyed real titles** — *Ray*, *1917*, *300*, *1984*,
  *The Blind Side*, *Plan B*. See the memory entry for the rules that replaced it.
- **"BLADE_RUNNER_2049" searched for Blade Runner released in 2049.** Empty
  year-filtered searches now retry without the year.
- **Motion JPEG was written off as cover art**, silently removing the film lookup for
  camcorder files. Frame rate decides now.
- **The settings caption claimed disc naming worked.** It does not in this build —
  reworded to claim only the tag lookup. Same overclaiming defect as the night before,
  in the very section whose own comment forbids it.
- Plus: a stuck spinner on a cancel race; a music video having no route back to
  MusicBrainz (now a menu keeping the smart default AND offering both); a legacy
  unlabelled TMDB key shadowing a new one; `Bearer eyJ…` pasted verbatim going into
  the URL; and a test named "passes the year to TMDB" that never looked at a request.

**One CI failure (run 349), self-inflicted:** fixing the noise list, I removed seven
words when the review had named four — `bd` had an existing test. Changing a shared
constant means re-reading what depends on it. The fix was verified by running all 23
cases (old tests + new) through the rules before pushing, not by eye.

### ⚠️ STILL NOT WIRED: TMDB → video disc identification

`VideoDiscIdentifier` gained a `candidateProvider` seam and `TMDBDiscCandidates`
builds one — but **nothing in production constructs it**, because
`VideoDiscIdentifier` itself has no production caller. The Identify Disc screen is
music-only; the CLI is music-only. The cheapest real route is the **MakeMKV Rip
screen**, which already scans a disc into `MakeMKVDiscInfo`: offer "Identify this
disc" after a scan and feed that info straight in. That is the next piece.

## 📍 PRIOR STATE — 2026-09-15

Where the project actually stands right now, in plain terms:

- **Working branch `wip/alpha-consolidation` is the live state of the project.** It
  is many commits ahead of `alpha` and is green (all this session's work passed
  CI). `alpha` itself still holds the older `v0.1.0-alpha.3` code; the `wip` work
  has **not** been merged to `alpha` yet. So if you are reading this copy on the
  `alpha` branch: the handoff describes the `wip` state, which is ahead of the
  code on `alpha`. (This handoff was pushed to `alpha` on request so the
  project-status note is visible there; the code that goes with it lives on `wip`.)
- **Landed on `wip` this cycle, all CI-green:** the six pre-release features
  (Filter Graph attach-to-encode; Dual-HDR wrapper tool discovery; Voice
  Isolation cleanup; Background Removal single-image save #300; Storage Analysis
  real ffprobe #365; Team Profile real git #345; Smart Crop video-based #299;
  MusicBrainz metadata lookup #205), the full 87-issue reconciliation with issue
  comments, and the docs/memory refresh. Details in the dated sections below.
- **Vector tracers (#473/#494) — code done + CI-green both sides; two steps left,
  both need a person:** the mirror PR `MeedyaSuite/MeedyaDL-Tools#26` (builds
  potrace + vtracer) is open and green and awaits a **merge decision** (merging
  cuts a mirror release); after that, pin `MDLT_TAG` in
  `scripts/bundle-tracing-tools.sh` (a fail-closed placeholder today). Plus a
  standing legal item: the potrace GPL source-offer wording needs sign-off before
  the first Direct release that ships potrace. Full detail in the vector-tracers
  section below.
- **NEW — foldable support requested across BOTH native mobile apps: filed as
  issues #500 (Apple iPhone Duo) and #501 (foldable Android).** Both are labelled
  **`for-consideration`** + **`wishlist`** — a mobile app has **not yet been
  scoped or committed**, so these are aspirational ideas awaiting a go/no-go
  decision (may never be built), not accepted roadmap work. Both
  carry the same crucial caveat: **MeedyaConverter has no mobile app today** — it
  is macOS-only (`.macOS(.v15)`, no iOS or Android target), so each foldable issue
  presupposes first shipping that mobile app, which is unstarted. They should be
  considered together as "foldable support across our native apps".
  - **#500 — iPhone Duo (Apple foldable):** use the wide 7.6″ inner display when
    open, the cover display when folded, re-flow live across the fold; adapt by
    size class not orientation; `NavigationSplitView`/`TabView` adapt across
    poses. Apple's tooling (Xcode 27.1 beta) + deep docs were still rolling out
    ("later this month") as of 2026-09-15 — issue written to plan from, to be
    tightened once the SDK lands.
  - **#501 — foldable Android:** one adaptive (universal) app across folded /
    open / **tabletop** / **book** postures via Jetpack WindowManager
    (`FoldingFeature` state + hinge orientation), window size classes, and Compose
    Material 3 adaptive scaffolds. Android's foldable APIs are mature + stable
    (no "coming later" gap) — the issue is concrete on the "how"; the open
    question is strategic (do we ship on Android, and in what form).
- **Still open, needing your calls:** merge of `MeedyaDL-Tools#26`; which of the
  15 alpha proposals in `.claude/proposals-2026-09-02b.md` to build (top picks: a
  reusable notarized-DMG workflow so `alpha` ships an app not just a CLI, and a
  `DirectBuildGateProvider`); and the 8 issue-level decisions in
  `.claude/reconciliation-2026-09-02.md`.

## 🎉 SESSION OUTCOME — MERGED & RELEASED (2026-08-04)

**PR #472 (`wip/alpha-consolidation` → `alpha`) is MERGED** as merge commit **`f9943bf`** (merge commit, 280
commits preserved). The `beta-alpha.yml` pre-release workflow (run #4) completed **success**, minting public
pre-release **`v0.1.0-alpha.3`** (https://github.com/MWBMPartners/MeedyaConverter/releases/tag/v0.1.0-alpha.3).
All PR CI green (Build & Test macOS, CodeQL, Dependency Review, actionlint, pin hygiene).

- **24 fully-complete issues CLOSED** (landed in alpha): #459 #284 #348 #296 #268 #334 #279 #470 #486 #484 #485
  #487 #483 #467 #292 #469 #488 #489 #490 #466 #474 #481 #355 #491.
- **Left OPEN (genuine partials / deferred):** #448, #475, #277 (failure-path hook), #482 (r25 conflicts UI),
  #451, #476 (rip/author), #473 (vector executor), #278 (pipeline exec), #288 (scene-detect exec), #477 (orphan
  remainder: ColorSpaceConverter US / EncodingBackend / FeatureGate + surgical cuts + 3D/disc/DCP/app-service),
  #468 (honest-minimal shipped; true seek-resume future), #471 (client shipped; dormant until server provisioned).
- **⚠️ IMPORTANT for the next session:** PR #472 is MERGED and FINISHED. `wip/alpha-consolidation`'s PR must NOT
  be reused. Any follow-up = a FRESH change: restart from `alpha` (`git fetch origin alpha && git checkout -B
  <new-branch> origin/alpha`), do the work, open a NEW PR.

---


> **Location note:** this doc lives at `.claude/HANDOFF.md` (moved from repo root 2026-07-22).

## 🟢 ACTIVE session — 2026-09-01b (MusicBrainz Nov-30 re-verification with LIVE sources + full state sweep + docs)

**User directive (this session):** (1) act on the MusicBrainz Nov-30-2026 search changes so nothing is lost or
broken; (2) full sweep of ALL GitHub Issues (open + closed) reconciled against the ACTUAL codebase; (3) refresh
all `.claude/` memory/context + this handoff; (4) ranked new-work proposals for the alpha cycle; (5) thorough
documentation update (`.md` + in-app help + OpenAPI + Swagger UI). Analysis/planning via **sequential Fable**;
implementation via **Sonnet/Haiku** (Opus only if genuinely complex). No PR stacking — everything commits to
`wip/alpha-consolidation`.

### State at session start
- Branch `wip/alpha-consolidation` @ `b8ca922`, tree clean, **6 ahead / 0 behind `origin/alpha`**.
- **89 open issues / 361 closed** (450 total).
- Unmerged-on-branch work: `45f2706` (MB builder hardening), `46c1dfb` (MB verified-safe docs),
  `bbb3c05` (standing tasks W3/W4/W8), `ece3b87` (handoff), `b8ca922` (#495 BIN/CUE serializer core).

### 🔑 TWO ENVIRONMENT CHANGES vs every previous session — both material
1. **Egress to MetaBrainz is OPEN.** `blog.metabrainz.org/2026/08/31/search-upgrades-nov-30-2026/` returns
   **HTTP 200** (was 403 in every prior session, which is why #493 Part B was "blocked / user-supplied text").
   The announcement AND all nine linked JIRA tickets (SEARCH-444/452/642/646/666/677/680/681/751/752/753/764)
   were fetched **first-hand** this session via `tickets.metabrainz.org/rest/api/2/issue/<KEY>`. The prior
   session's "verified safe" conclusion was reached from user-supplied text; it is now checkable against
   primary sources. Ticket detail beyond the blog post: SEARCH-666 says `quality:low|normal|high` are
   *currently broken* and only numeric `quality:0|1|2|-1` work — the fix makes names work; SEARCH-681 notes it
   does **not** add genre as a search *field*, and that searching by genre **name** already works via the
   `tag` field.
2. **A Swift 6.3.3 toolchain IS present locally** (`/usr/bin/swift`, swiftlang-6.3.3.1.3).
   - `swift build --target ConverterEngine` → **clean, 0 errors** (this verifies `b8ca922`'s #495 disc-imaging
     code, which was committed with "not yet built/tested").
   - `swift build` (whole package) fails **only** on `#Preview` macros — CommandLineTools has no
     `PreviewsMacros` plugin. Environment limitation, not a code defect.
   - `swift test` **cannot** run: no Xcode ⇒ no `XCTest` module. **CI remains the test gate.**

### ⚠️ CI GAP FOUND (new, real)
`.github/workflows/build.yml` triggers only on push/PR to `main`/`beta`/`alpha`. Since PR #472 merged, the
`wip/alpha-consolidation` branch has had **no CI at all** — all 6 commits ahead of `alpha` are CI-unverified.
Combined with the deliberate no-PR-stacking policy, the working branch accumulates unverified work by design.
Fix queued: add `wip/**` to the `push` triggers so the working branch is continuously built and tested.

### Progress (update as you go)
- [x] Fetched + archived the MusicBrainz announcement and all linked tickets from primary sources.
- [x] Confirmed local `swift build --target ConverterEngine` is clean at `b8ca922`.
- [x] Dumped all 450 issues to the session scratchpad; sliced the 89 open issues 6 ways for evidence agents.
- [x] **#496 CI gap FIXED + CLOSED** — `4c42111` adds `'wip/**'` to `build.yml` `push.branches`.
      **CI run [33557525771](https://github.com/MWBMPartners/MeedyaConverter/actions/runs/33557525771)
      = SUCCESS** at `4c42111`, the first `CI Build & Test` on this branch since 2026-08-04. That single run
      also retro-verifies the five commits before it — including **`b8ca922` (#495), which was committed
      with "not yet built/tested"**: `swift build` + `swift test --parallel` both pass over its ~1,350 lines
      of disc-imaging code and 500 lines of new tests. #495 updated with a per-criterion status.
- [x] Claude memory seeded at
      `~/.claude/projects/…-MeedyaConverter/memory/` (3 files + `MEMORY.md`): local-toolchain reality,
      the CI-trigger trap, and the now-open MetaBrainz egress.
- [x] Docs-defect inventory built (for the docs pass): **10 modules deleted in the orphan sweep are still
      documented as live** — `MetadataPassthrough`, `MetadataTagger`, `ColourSpaceConverter`,
      `SubtitleConverter`, `EncodingReport`, `MultiStreamSelector`, `SmartCropIntegration`, `HDRPolicyEngine`,
      `PQToHLGPipeline`, `ClosedCaptionHandler` — in `docs/Architecture.md` (presented as live architecture),
      `FEATURES.md`, `PROJECT_STATUS.md`, `docs/MeedyaSuite-core-integration.md`,
      `docs/migration/suite-core-cleanup.md`. Also: the CLI OpenAPI spec
      (`docs/api/meedya-convert-api.yaml`) has **no `/serve` path** despite `serve` shipping in `1773763`,
      and `Resources/Help/cli-reference.md` never mentions `serve`. Both OpenAPI specs parse clean (3.1.0);
      the HTTP spec's 5 paths do match `APIServer.swift:458-466`. Swagger UI at `docs/api/swagger-ui/`
      is present, static, CDN-pinned and shared-hosting-ready — W6 already satisfied there.
      All 12 help `.md` files are registered in `HelpView.swift`'s `HelpTopicRegistry` (no orphans).
- [~] Workflow `wpssl6pvl` RUNNING — 9 parallel Sonnet evidence agents (code-first, citation-only) then
      4 **sequential** Fable analysis passes (MusicBrainz plan → issue reconciliation ×2 → ranked proposals).

## 🟢 ACTIVE — 2026-09-01c (user selected 11 proposals; #494 decided)

### ✅ #494 DECIDED — bundle GPL disc tools, Direct builds only

Recorded as **`docs/decisions/0001-gpl-disc-tools.md` (DR-0001)**, commit `f9d06fe`, and on #494.

**The reframing that settled it:** the App Store angle is **technical, not licensing**.
`MeedyaConverter-AppStore.entitlements` declares `com.apple.security.app-sandbox` with only
`network.client`, `files.user-selected.read-write`, `files.bookmarks.app-scope` and
`files.downloads.read-write` — and the App Sandbox offers **no entitlement for raw optical-device
access**. Disc imaging cannot work in an App Store build whatever licence the tools carry, so even a
clean-room native MMC rewrite would not unlock it. That removed option C's entire rationale.

**Binding consequences** (all in DR-0001): never link `libcdio`; ship licence texts; ship a written
source offer + archive the tarballs; a build check must FAIL if a GPL `BundledTool` reaches an App
Store bundle (mirror the ITMS-90236 guard at `testflight.yml:317`); hide-don't-break via the existing
`isDirectBuild` flag; NRG stays clean-room.

**Deliberate:** the `ToolBundleManifest` entries are drafted **in the decision record, NOT in
`defaultManifest`** — that manifest describes tools the app actually ships, so listing unbundled
binaries would be the fabricated-capability defect. They move across with the binaries. #494 stays
OPEN for the packaging work.

### ✅ 12 closed-in-error issues REOPENED (proposal #4 — done)

Every claim re-verified by the orchestrator's own grep before acting. Open count **86 → 98**.

| Issue | Evidence |
|---|---|
| #343 slate | `SlateGenerator`/`SlateGeneratorView` — 0 refs outside own files, no tests, no nav entry |
| #63 sprites · #59 HLS AES | both in `StreamingEnhancements.swift`; refs only from that file + `ConverterEngineTests+Manifest.swift` |
| #323 vidstab · #324 deinterlace | 0 refs outside own file, no tests |
| #257 tool updates | 0 refs in `Sources/`; only URL-builder asserts in `ConverterEngineTests+Pipelines.swift:482,498` |
| #285 drag-out | 0 callers; `SourceFileView.swift:132` has `handleDrop` only — drag **in**, not out |
| #280 mini player · #330 settings undo · #361 notification actions | 0 callers each |
| #303 localisation | 0 callers; only `en.lproj` exists despite a 6-language table in the manager's header |
| #336 themes | persists accent/sidebar tint, but **no `.tint(...)` at app root** — saved then ignored |

### 🔨 SELECTED WORK — user picked 11 items (2026-09-01)

Ordered by the batching the orchestrator chose (file-collision aware — `AppViewModel.swift`,
`MeedyaConverterApp.swift` and `SettingsView.swift` are each touched by more than one item, so those
run sequentially):

- **Batch A (parallel Sonnet, disjoint files) — RUNNING as workflow `wk2po9vjp`:**
  #322 concatenation Start · #331 keyboard shortcuts apply · #288 scene detection executes ·
  #451 ScriptingBridge semaphore. Each followed by a **sequential Fable** adversarial review.
- **Batch B (sequential — shared files):** #277 failure-path hooks · #475 `useHardwareAcceleration` ·
  #356 non-profile URL scheme · #281 menu-bar controller.
- **Batch C (large, Opus):** #286 bounded-concurrency queue · #329 A/B comparison loop.
- Then: full issue re-sweep, docs sweep, `.claude/` refresh, round-2 proposals.

## 🟢 2026-09-02 — pre-release FEATURE BUILD (autonomous, Fable-plan → Sonnet-impl)

**User directive:** before the first Direct release, build a set of partial/dead features autonomously
(sequential Fable for analysis/deep-planning, Sonnet for implementation), NO pausing, all decisions
surfaced upfront. Commit each change, update the GitHub issue, update THIS handoff per piece (crash-safe).

**Decisions locked (user, via AskUserQuestion):**
- Direct **licensing → DEFER** (StoreKit can't work in Direct); **Subscription tab hidden**.
- Metadata backend → **native-Swift** (no upstream Rust dep; the MeedyaSuite-core option aliases native).
- Vector tracers → **wire execution AND build+bundle GPL binaries** (cross-repo into MeedyaDL-Tools, like ffmpeg).
- Distributed Render Farm → **DEFER** (config-only + disclosed).
- Plus (my defaults, unobjected): MusicBrainz-keyless metadata lookup; remove the fake Voice "Vision Sound
  Analysis" option; the small view fixes as scoped.

**BUILD LIST:** Filter Graph (attach to encode), Dual HDR wrappers (search Contents/Helpers), Smart Crop
(video-based crop), Background Removal (single-image save), Voice Isolation (drop fake ML option), Storage
Analysis (real ffprobe), Team Profile (real git), native metadata backend + MusicBrainz lookup, vector
tracers (exec + bundle binaries).

**Progress:**
- `beaf3cc` — **DEFERRALS**: hid the Subscription + Plugins Settings tabs (SettingsView); updated
  `rc4-known-limitations.md` (Subscription/Plugins hidden, render-farm/licensing deferred). App target builds
  clean. (CI green.)
- **`9511291` — DONE + CI GREEN (run 33681466109)** — three features in one sub-batch (Fable-planned,
  implemented directly after the parallel Sonnet agents stalled):
  - **Filter Graph → attach to encode.** `FilterGraphEditorView` split its node string into
    `toVideoFilterString`/`toAudioFilterString` + an "Apply to Next Encode" button that stages onto
    `AppViewModel.pendingFilterGraphVideo/Audio`; `enqueueSelectedFile()` consumes them (video composed
    AFTER crop via **new `FilterChainComposer.compose`**, audio into `-af`), with passthrough guards. Was
    clipboard-only before.
  - **Dual HDR wrappers.** `DoviToolWrapper` / `HDR10PlusToolWrapper` now resolve their binary via
    `BundledToolLocator` (Contents/Helpers → Homebrew → PATH → which) instead of a hardcoded 3-path list that
    never checked the bundled tools; dead which-fallback helpers removed; `FFmpegBundleManager`'s false
    "stages the HDR helpers" comment corrected.
  - **Voice Isolation.** Removed the fake "ML Sound Analysis" method (ran the identical bandpass as basic) +
    the dead centre-channel toggle + `VoiceIsolator.isMLAvailable()`.
  - Tests: `FilterGraphStagingTests`, `HDRToolWrapperDiscoveryTests`, `VoiceIsolationMethodTests`.

### ✅ PRE-RELEASE FEATURE BUILD — quick-fixes + Team git ALL DONE (2026-09-03)

Branch `wip/alpha-consolidation`, tree CLEAN, **CI GREEN @ `3ced838`**. All decided quick-fixes and Team git
landed and CI-verified this session (each: Fable plan → Sonnet impl → 5-gate verify → commit → issue comment
→ watch CI green). No agents running.

**A. Quick-fixes — DONE:**
1. **Background Removal single-image save (#300)** — `4ba5e62`. "Save…" → `NSSavePanel`, exact bytes (alpha
   preserved), F-002 name; fixed a false comment. CI green.
2. **Storage Analysis real ffprobe (#365)** — `743650c`. New `MediaFileProbing` seam (`FFmpegProbe` conforms),
   pure `analysis(from:base:)`, `probeFiles` (bounded concurrency + progress + Cancel + graceful fallback),
   `Provenance` labelling; view shows a probed-vs-guessed caption. 34 tests. CI green.
3. **Smart Crop video-based (#299)** — `16db504` (+ test fix `3ced838`). New `SmartCropVideoAnalyzer` (frame
   sampling + Vision + median-centroid crop at target aspect, inside the black-bar area), view rewritten to
   analyse the selected video with progress/Cancel/preview; enqueue now drops a crop on stream-copy profiles
   (fixed a real `-vf`+`-c:v copy` job failure); deleted 4 dead geometry fns. 38 tests. CI green.

**B. Team Profile real git (#345) — DONE:** `0bfd5e1` (+ test fixes `56ae4d6`, `1fdc86f`). New `GitProfileSync`
(injectable `GitRunning` seam; clone/fetch/checkout/add/commit/push; user's own credentials; `GIT_TERMINAL_PROMPT=0`;
App-Sandbox warning), repository git fields, `pullProfiles` async, 3 new errors. 19 tests. CI green. Plan:
`.claude/plans/team-profile-git-plan.md`.

> ⚠️ **CI-only test-failure lesson (this session):** all three CI reds were TEST bugs invisible to local
> single-file `swiftc -parse` — (1) raw `NSLock.lock()` in an `async` mock method, (2) a `.arguments.first`
> sequence assertion that labelled `-c commit…` as `-c`, (3) a top-level `ProgressRecorder` colliding with the
> same-named type in another test file of the module. Production was correct each time. Fixes + prevention in
> memory [[verification-gates-and-what-cannot-be-tested]]. **Before pushing a new test file: use `withLock` in
> async mocks; label commands, don't take `.first`; grep the module for duplicate top-level type names.**

### ✅ / ⏸️ Larger feature-build items:
- **Native-Swift metadata backend + MusicBrainz lookup / auto-tagging (#205) — DONE** (`90f37a3` feature;
  `d9d1935` test-fix+docs; `b7ffcb5` join-phrase production fix). Keyless MusicBrainz executes via a
  `MetadataHTTPClient` seam + `MusicBrainzLookupService` (User-Agent + 1 req/sec throttle) → "Look Up…" sheet
  in the Metadata Tag Editor → applies to the tag table. 37 tests. Keyed providers (TMDB/TVDB/Discogs/…) still
  need an API-key UI; fingerprint/album-disc-ID/`AutoTagger` are noted follow-ups. Plan:
  `.claude/plans/metadata-musicbrainz-lookup-plan.md`. CI green. Docs reconciled (README/Home/FAQ/rc4/suite-core).
- **🟢 Vector tracers (#473/#494) — CODE DONE + CI-GREEN both sides; only merge + pin remain.** Deep plan:
  `.claude/plans/vector-tracers-plan.md`.
  - **Part 1 (mirror) — PR OPEN + GREEN, ready to merge:** `MeedyaSuite/MeedyaDL-Tools#26`
    (branch `feat/vector-tracing-tools`). New `build-tracing-tools` job compiled potrace 1.16 (GPL, from source,
    corresponding-source archived) + vtracer 1.0.0-alpha.4 (MIT) on macOS + Linux per-arch with SHA verification;
    actionlint clean; artifacts produced. (Correction to earlier: `populate.yml` **already had** a `macos-latest`
    leg; the missing piece was a C/Rust compile job — added.) **Merging cuts a dated release (outward-facing) —
    left for the user's call.**
  - **Part 2 (this repo) — LANDED + GREEN:** `32234bf` (feature) + `c07daae` (test arg-order) + `2ac0721`
    (progress-clamp). `RasterVectorExecutor`/`ProResVectorExecutor` (new) wire the converters to real
    potrace/vtracer via `ExternalToolRunner`; vtracer arg-builder rewritten to the pinned `1.0.0-alpha.4` CLI
    (old flags never existed); nav un-hidden behind `#if APP_STORE`; potrace in `directOnlyManifest` (GPL,
    Direct-only, tripwire green), vtracer in `defaultManifest` (MIT). Also fixed 3 real latent bugs (double `-vf`,
    non-existent vtracer flags, SMIL fill stacking).
  - **REMAINING (2 steps):** (1) user merges #26 → note the dated tag; (2) pin `MDLT_TAG` in
    `scripts/bundle-tracing-tools.sh` (currently a fail-closed placeholder — exit 6 — so **no Direct release
    ships until pinned**; CI Build & Test is unaffected). Plus the standing legal item: potrace GPL
    corresponding-source **written-offer wording needs maintainer/legal sign-off** before the first Direct
    release that carries potrace.

**Deferred/disclosed (NOT to build this pass):** Direct licensing (Subscription hidden ✓), Distributed
Render Farm (config-only + disclosed).

## 🟢 2026-09-02 — full open-issue sweep + ranked proposals (autonomous bulk-work cycle)

User re-issued the standard bulk-work prompt ("proceed autonomously, no pauses"): full GitHub-issue sweep
vs real code, ranked new-work proposals, docs/memory/handoff refresh, commit-per-task, no PR stacking.

- **Reconciliation DONE** — a 10-agent workflow (8 parallel Sonnet evidence agents, code-first + citation-only,
  across all 87 open issues → sequential Fable reconciliation → sequential Fable proposals). Full output saved
  to **`.claude/reconciliation-2026-09-02.md`** (per-issue ACTIONS table + comment texts + 8 human decisions)
  and **`.claude/proposals-2026-09-02b.md`** (15 ranked proposals). Key finding: **nothing is unconditionally
  closeable** — every open issue is a partial epic, dead-code-only (built+tested but zero callers), or
  correctly deferred. The pervasive defect is *builder-exists-but-unwired* (same class as
  [[metadata-lookup-is-dead-in-full]]).
- **10 targeted issue comments posted** (state changed / record stale): #477 (corrected dead-list — struck
  VideoStabilizer, now wired via #323; folded the cloud/streaming/broadcast dead clusters here as the parent
  tracker), #257, #492, #493, #494, #374, #298 (scope mismatch — shipped watermark is video, issue is batch
  images), #392 + #387 (App Store cluster consolidated status + cert-family blocker), #495 (all code/tests/CI
  proven; only the hardware matrix remains). Did NOT re-comment epics that already carry current comments from
  this session.
- **Memory added:** [[alpha-test-build-packaging-gaps]] (alpha ships CLI-only; Direct sets no entitlement
  provider → testers clamped to Free), [[appstore-testflight-blocked-cert-family]] (#387 cert-family + one
  smoke-test gate the App Store track; Direct build unaffected).
- **⚠️ AWAITING USER DECISION (surfaced, non-blocking):** which of the 15 proposals to build. Top-3 shortlist:
  **#1** reusable notarized-DMG package workflow so the `alpha` branch ships an installable app (today it ships
  a bare CLI); **#2** `DirectBuildGateProvider` (unlock plus/pro for testers in Direct); **#3+#4** diagnostics
  bundle w/ git SHA + a pre-release update channel. Plus 8 issue-level human decisions in the reconciliation
  doc (§Needs-human-decision): #495 hardware pass?, #387 cert family?, #359 WidgetKit vs status-item?, #424
  extend #307 vs new gating?, #257↔#477 home, #476 narrow scope, #357↔#283 canonical Services provider, and a
  stale-doc-comment housekeeping PR.
- **Feature build continues in parallel** (already-decided prior directive): #300 Background Removal save DONE
  (`4ba5e62`); next = Storage Analysis ffprobe → Smart Crop → Team Profile git (plan in
  `.claude/plans/team-profile-git-plan.md`), each via a sequential Fable plan then Sonnet impl.

## 🟢 2026-09-02 — pre-release hardening for the first Direct test build (autonomous)

**User directive:** prep the first Direct-distribution test build; first do any *recommended pre-build
tasks*, autonomously, using **sequential Fable 5.1 agents for analysis/deep-planning** and **Sonnet for
implementation**.

**Analysis:** two sequential Fable agents reconciled the whole release surface against real code —
(A) the build/sign/notarize PIPELINE, (B) FUNCTIONAL/content readiness. Both reports are thorough (Fable
even caught 2 false comments). Implementation via 2 parallel Sonnet agents (disjoint files) + me for the
CI-critical/shared/content items. **CI-green batches landed on `wip/alpha-consolidation`:**

- `92c7d42` — **correctness/blocker fixes**: ffmpeg resolution (Image/Voice/MediaScanner → FFmpegBundleManager,
  so they work in a Finder-launched notarized app, not just Homebrew); VideoTrimmer seeds real duration (was
  hardcoded 120 s); disc-burn "Simulate" refuses to write a real disc on hdiutil/growisofs (only Audio-CD
  `-dummy` is a real dry run) + honest "verified"; EDL CMX3600 dangling-pointer UB fixed (+ test); queue
  drag-reorder moves the right job; zero-condition rule can't be saved; stale concat note removed; Cloud Sync
  hidden (no iCloud entitlement in Direct).
- `936bde3` — **pipeline + drift**: release.yml (CLI `--version` sync via sed before build, missing-CLI hard
  fail, job timeout 45→90, DIRECT-must-stay-unset doc); notarize.sh (timeout 900→1800, stop `2>&1` corrupting
  the notarytool JSON parse); false comments fixed (Package.swift bundle name, AppInfo sync-script);
  README/direct-release.md drift; CHANGELOG `[Unreleased]` backfilled with this session's work (+ release-cut
  NOTE to fold into a dated `[0.1.0-rc.4]` and correct the stale "vector = first-class sidebar entries"
  highlight — they're hidden now, #473).
- `docs/distribution/rc4-known-limitations.md` (DRAFT) — the honest partial/disabled feature list for the
  test-build release notes.

**DEFERRED / DISCLOSED (not fixed — in the known-limitations doc):** CLI notarization (invasive/untestable —
disclosed, `xattr -d` workaround); entitlements hardening-key trim (ship as-is, trim in rc.2); Dual-HDR
tools, Smart Crop still-image crop, Storage Analysis filename-guesses, Team-git relabel, background-removal
single-image save, etc.

**⚠️ USER DECISIONS that gate the actual tag (surfaced, not blocking):**
1. **Merge `wip/alpha-consolidation` → `main`** — REQUIRED: the release tags a commit on `main`, which is 89
   behind `alpha` / 175 behind wip; none of this session's work ships in rc.4 without the merge.
2. **6 Apple secrets** (APPLE_CERTIFICATE/_PASSWORD, APPLE_SIGNING_IDENTITY [Developer ID Application],
   APPLE_ID, APPLE_PASSWORD [app-specific], APPLE_TEAM_ID) — only the owner can set; release.yml fails fast
   without them.
3. **Tag/version** (v0.1.0-rc.4 per CHANGELOG?).
4. **Hide Subscription/Plugins Settings tabs in Direct?** (product call).
5. **GPL disc-tools bundling** — recommend DEFER for the first build (disclosed).
6. **DIRECT stays UNSET** — recommend yes (documented in release.yml; setting it crashes at launch until
   Sparkle framework embedding lands, #416).

Pipeline logic itself verified sound by the Fable audit; the genuine gate is the merge + the 6 secrets.

## 🟢 2026-09-02 — post-round-2 dead-feature sweep (autonomous, CI-monitored)

After the round-2 register completed, the user added a **standing rule** and directed autonomous work on
outstanding elements. Done:

- **Standing rule §15** (`standing_tasks.md` + W5 + memory [[always-monitor-ci-after-push]]): stay and
  watch CI to green after every push/sync/PR; fix reds immediately. Committed `76114f7` (CI green). This
  closed the gap that let CI sit red from #468. **Every push below was watched to green.**
- **#499 CLOSED** — the test-target split was genuinely done but the handoff had *falsely* marked it
  closed; it was still open with 0 comments. Actually closed now (another false-record instance — verify
  issue state, don't trust the handoff's "closed" claims).
- **Triage workflow** (`wf_83fca15b-515`, 13 agents) reconciled actionable macOS-alpha issues (#275 #280
  #281 #283 #320 #322 #323 #324 #330 #331 #374 #477) against REAL code and ranked them. Excluded: #283
  (needs an Xcode .appex target — not SPM-buildable), #374 (blocked on MeedyaSuite-core tag). Signature
  defect ("dead engine / dead UI, never executed") confirmed pervasive. Full result in the workflow output.
- **#323 video stabilization — DONE (epic OPEN)** (`2d991c5`, CI green). `VideoStabilizer` was a
  zero-caller two-pass builder. New `StabilizationView` runs both passes (vidstabdetect→.trf→vidstabtransform)
  via `FFmpegProcessController`, presets + custom sliders, progress/cancel, libvidstab-missing message,
  Tools nav entry. `VideoStabilizerArgumentTests`.
- **#320 metadata editor — DONE (epic OPEN)** (`3905a7e`, CI green). Was write-only + destructive: added
  the READ path (seed tags from `selectedFile.metadata`), and fixed `MetadataTagEditor.buildWriteArguments`
  — metadata-only now `-map 0 -c copy` (was re-encoding the whole file), artwork now keeps source streams
  (`-map 0` + cover; was dropping A/V, output was just the image). `MetadataTagWriteArgumentTests`.
- **#275 folder mirroring — DONE (epic OPEN)** (`9f5e123`, CI green pending). CLI `batch --dir` flattened
  even under `--recursive`; added `--output-mode mirror` routed through the GUI's
  `OutputPathResolver.resolveOutputDirectory`. `OutputPathResolverMirrorTests`. Remaining AC (persist GUI
  outputMode, WatchFolderManager honour it, collision prompt) tracked on the issue.

- **#322 concat re-encode + crossfade fix — DONE (epic OPEN)** (`13ae775`, CI green). Demuxer path worked;
  the re-encode filter path was dead (`buildFilterConcatArguments` zero callers, UI-gated) and
  `buildCrossfadeFilterComplex` hardcoded `offset=0` (crossfade fired at t=0). Fixed the offset math
  (durations-based cumulative), added explicit codecs, wired `runFilterConcat` for differing-codec joins.
  Crossfade UI still gated on the view probing durations. `VideoConcatenatorFilterTests`.
- **#324 deinterlace — DONE (epic OPEN)** (`b8817e8`, CI green pending). `DeinterlaceConfig`/Presets had
  zero callers. Wired like #298: `FFmpegArgumentBuilder.deinterlace` (first -vf stage), `EncodingProfile
  .deinterlace` (back-compat, config now Hashable), `OutputSettingsView` Deinterlace picker (Off/Fast/
  Quality; nnedi omitted — needs external weights). `DeinterlaceWiringTests`.

**CI discipline note:** pushing again while a run is in-flight triggers concurrency-cancel on the prior run
(lost 9f5e123's validation). RULE: watch each push fully to green BEFORE the next push. All pushes here
were watched; #323/#320/#275 validated by 288cbcc (green), #322 by 13ae775 (green), #324 by b8817e8.

- **#280 mini-player — DONE (epic OPEN)** (`4ca48f8`, CI green). `MiniPlayerController.updateProgress`
  had zero callers → panel was a permanent "No active encoding". `refreshAggregateActivityIndicator`
  now drives it live; new `resetToIdle()` at both queue-finish points. Remaining: panel pause/cancel
  buttons, frame persistence, always-on-top/translucency toggles, auto-show.
- **#331 shortcut recorder — DONE (epic OPEN)** (`a43c5b7`, CI green pending). Recorder was decorative
  (no key capture). New pure `ShortcutBinding.captureBinding(...)` + an NSEvent key-down monitor active
  only while recording, writing to the manager (didSet saves). `ShortcutCaptureTests`. Remaining:
  Cmd+1-9 profile shortcuts, encode.pause/stop actions, per-conflict reassign.

- **#281 menu-bar status — DONE (epic OPEN)** (`27db132`, CI green pending). Dropdown showed permanent
  "Idle"/"Web Standard" (updateQueueStatus/lastUsedProfileName never called). Added
  `AppViewModel.menuBarStatusText` (coarse) + App `.onChange` observers pushing it +
  `selectedProfile.name` to the controller. Remaining: drag-to-encode onto the status item, dock-hide.

**Next candidates (remaining from triage, executableNow):** #330 undo/redo (L), #477 dead-cluster sweep
(L), #281 menu-bar drag+status (M). #283 (needs Xcode .appex target) and #374 (needs MeedyaSuite-core tag)
need a user decision / upstream first. Done this phase: #323 #320 #275 #322 #324 #280 #331 #281 (+ #499 closed). Remaining executable: #330
undo/redo (L), #477 dead-cluster wire-or-delete (L), #281 drag-to-encode. #283/#374 blocked (Xcode appex / upstream tag).

## 🟢 2026-09-02 — round-2 quick wins in progress (autonomous)

Working the round-2 register (`.claude/proposals-round2-2026-09-02.json`) in rank order, per "continue
autonomously". Each: verify vs code → fix → test → commit → close issue.

- **#336 themes ignored — DONE + CLOSED** (`cd3ca6b`). Root cause: no `.tint` at the app root AND
  `ThemeSettingsView` owned a *private* `@State ThemeManager`, so even its edits died locally. Now one
  shared `ThemeManager` injected into every scene + `.tint(accentColor)` at each root; `ContentView`
  applies the optional `sidebarTint` to the nav column. The picker now recolours the app.
- **#326 queue optimiser — DONE + CLOSED** (`10468c3`). The landmine I flagged: `estimatedSourceDuration`
  was a *computed* property smuggling `__duration:<v>` into `extraArguments`, which `FFmpegArgumentBuilder`
  appends to argv — so the obvious "populate it" would pass `__duration:123` to ffmpeg. Now a real stored
  field (Codable-back-compat), smuggling deleted, populated at enqueue from `file.duration`. 6 tests incl.
  the "no __duration in argv" guard. shortest/longest/estimated-time now genuinely reorder.

- **#361 notification actions — DONE + CLOSED** (`3d2c115`). `NotificationActionHandler` was a complete
  UNUserNotificationCenter delegate with zero references — never set as delegate, categories never
  registered, notifications never stamped a categoryIdentifier. Wired the full chain: handler held for
  app lifetime + set as delegate + registerCategories at launch; `sendNotification` stamps category +
  userInfo (complete→output path, failed→input path, queue→output dir); AppViewModel observes the three
  decoupled posts (Start Next→startQueue, View Log→.log, Retry→re-import+enqueue).

- **#498 watch-folder conditional rules — DONE + CLOSED** (`34f47f9`, filed as a #469 follow-up). The
  manual enqueue evaluated #469's conditional rules; the watch-folder (automation) path — where per-file
  rules matter most — did not. Made `enqueueWatchFolderFile` async (its caller was already in a Task),
  probe the detected file, evaluate rules against the probed metadata, swap profile on match; probe
  failure degrades gracefully. Also populates `estimatedSourceDuration` (#326) for this path.

- **Reentrant-actor regression test — DONE** (`c54c3cb`, re #361). Added the missing guard for the
  defect class that nearly shipped: `PostEncodeHookRunner` gains an internal injectable-executor seam
  (mirroring `PostEncodeActionChain.execute`'s), and `PostEncodeHookRunnerSerialisationTests` fires three
  chains concurrently (later ones sleeping less) and asserts no overlap + FIFO order + `drain()` waits.
  A reintroduced reentrancy bug fails CI.

- **#285 drag-out — DONE + CLOSED** (`69921ae`). `DraggableFileView`/`.draggableFile` were a complete
  drag-source with zero callers; applied to completed `JobRow`s (output URL for completed, nil otherwise).

- **#499 app-module test target — DONE + CLOSED** (`62290d2`; user approved the build-layout change).
  The app module had NO testable surface (an executable target can't be `@testable import`ed), which is
  why this session's subtlest defects (the #475 default-polarity trap, the #331 KeyEquivalent crash)
  shipped unguarded. **Split into a thin `MeedyaConverter` executable + a testable `MeedyaConverterCore`
  library** (standard SwiftPM pattern): all app code moves to the library (path unchanged), the exe is a
  one-line `MeedyaConverterApp.main()`, `MeedyaConverterApp` is now public + `@main` removed + `body`
  public. New `MeedyaConverterCoreTests` seeded with regression tests for both defects.
  **⚠️ The SwiftPM resource bundle renamed** `MeedyaConverter_MeedyaConverter.bundle` →
  `MeedyaConverter_MeedyaConverterCore.bundle` (package_target); `release.yml` + `dev-build.yml` copy
  step updated to match (name verified against the built artefact). **The `.app` resource-bundle copy
  only runs on a release/dev build, so that one line is confirmed on the next such build** — CI Build &
  Test verifies the compile + the new tests only.

- **#468 periodic checkpointing — DONE** (`1e95455`, left OPEN for true seek-resume). saveCheckpoint
  fired only on failure/cancel; a mid-encode crash left nothing resumable. Now the progress closure
  writes a checkpoint every ~5% (throttled via new `EncodingJobState.lastCheckpointFraction`, off-main
  via `Task.detached`), and the success branch DELETES it (so completed jobs aren't shown resumable).
  New `CheckpointManagerTests` (save/load, overwrite, delete). Still honest-minimal (re-queue from 0%).

- **#482 team-profile conflicts — DONE + CLOSED** (`c2abb36`). The fake-push-success half was fixed
  earlier (real PUT); the remaining gap was that `conflictedProfiles` was initialised to `[]` and
  **never populated** — nothing computed a diff — so the Conflicts section could never render and
  `resolveAllConflicts` always merged against `[]`. Added `TeamProfileManager.detectConflicts(local:
  remote:)` (remote profiles sharing an id with a local one but whose whole `Hashable` value differs);
  `pullProfiles` now populates it + notes the count. New `TeamProfileConflictTests` (differing-same-id
  is a conflict; identical isn't; new-remote-id isn't; only the conflicting subset, in remote order).

- **#286 throughput tiles — DONE (epic left OPEN)** (`bdb477f`). Runner + Active Jobs list were live;
  the **Throughput** tiles (Combined Speed / Active / Avg Progress) were computed in the parent
  `ParallelEncodingView` body, which — being `@Observable`-based over `viewModel.activeJobStates` —
  never subscribed to each `EncodingJobState` (a Combine `ObservableObject`). Per-job `ActiveJobRow`
  updates via `@ObservedObject`; the aggregate tiles didn't, so they froze until the array changed.
  Extracted `ThroughputTilesView(jobs:)` subscribing to all jobs at once via
  `.onReceive(Publishers.MergeMany(jobs.map(\.objectWillChange)))` → bump `@State` → re-read fresh
  numbers. Type-checks clean (only `#Preview` env errors). No unit test: the defect is a SwiftUI
  runtime subscription, not the aggregate math. Epic stays OPEN — GPU/CPU load-balancing enforcement,
  per-job priority, thermal-throttling still to do (see issue comment for the checklist).

- **#298 watermarks — DONE (epic left OPEN)** (`73c4469`). `WatermarkView` previewed a filter string
  that never reached an encode; `EncodingProfile` had no watermark field and the builder emitted none.
  Wired end-to-end single-pass inside the existing `-vf` slot (no `-map`/HDR interaction): text →
  `drawtext`; image → the `movie` *source* filter (`movie='logo'[wm];[in]<chain>[base];[base][wm]
  overlay=x:y[out]`) so **no second `-i` and no `-map` rewrite**. New
  `WatermarkOverlay.appendToVideoFilterChain` + `escapeFilterPath` (single-quote + `'\''` idiom).
  `EncodingProfile.watermark: OverlayWatermarkConfig?` (optional back-compat; config now Equatable/
  Hashable so profile's synthesized conformances hold); view loads/applies/removes on `selectedProfile`.
  Skipped for passthrough. Tests: chain composition, no-2nd-input/no-map invariant, path escaping,
  passthrough-skip, threading, Codable back-compat. Epic OPEN — tiled/custom-XY/rotation/font-config/
  rendered-preview remain.

- **#335 multi-output — DONE (epic left OPEN)** (`e4a87bb`). `MultiOutputView` previewed FFmpeg args
  but had no run action — nothing executed. Wired via the existing queue rather than the simplified
  `MultiOutputEncoder` arg arrays: new `AppViewModel.enqueueMultiOutput(_:)` enqueues one full-fidelity
  `EncodingJobConfig` per enabled output → independent per-output progress + per-output status from the
  existing `EncodingJobState`, and #286 runs them in parallel. New "Add N Outputs to Queue" button.
  Global HW kill switch honoured per output. No ConverterEngine change; verified by inspection+compile
  (AppViewModel construction too side-effectful for a hermetic test). Epic OPEN — single-pass `tee`
  shared-decode needs a distinct one-process/many-outputs job+backend model.

- **#473 vector tools — DONE + CLOSED** (`8e38fe1`). VectorConversionView/ProResVectorView are
  settings-only forms; `RasterVectorConverter`/`ProResToVectorConverter` are **arg-builders only** (no
  process runner) and the tracing tools (potrace/vtracer/rsvg) are GPL + not bundled — so neither can
  convert. Took #473's 2nd option (hide until wired): `NavigationItem.unavailable =
  [.vectorConversion,.proresVector]` + derived `isAvailable`; sidebar drops the entries; `selectedNavItem`
  `didSet` snaps unavailable selections back to `.source` (not persisted, no AppleScript path — sidebar
  was the only live entry). Views/routing kept for re-enable. `NavigationItemAvailabilityTests` guards it.
  Re-enable gated on bundling tracing tools (#494/MeedyaDL-Tools; refs #376/#377/#402/#404).

- **#278 pipeline editor — DONE (epic left OPEN)** (`93a1b49`). `buildStepArguments` had no caller,
  editor only previewed, `onSave` was nil. New `EncodingPipelineExecutor` (mirrors #370): pure
  `resolve` (threads a "current media" through steps; `.encode` = transform via full profile-aware
  `EncodingJobConfig.buildArguments()`; extract/probe = side deliverables), `intermediateOutputs`
  (only *superseded* transform outputs), `execute` (in-order, halt-on-fail rethrowing tool stderr,
  cancellation-aware, success-only cleanup honouring `cleanIntermediateFiles`). Injectable
  `PipelineStepRunning`; real `FFmpegPipelineStepRunner` (ffmpeg via controller, ffprobe stdout->file).
  `AppViewModel.savedPipelines` (JSON/UserDefaults) + save/delete/`runPipeline`; editor "Run..." button;
  `OutputSettingsView` passes `onSave`. `EncodingPipelineExecutorTests` (mock runner). Epic OPEN —
  drag-drop graph, branching, per-step progress bars, template sharing remain.

- **#302 AppleScript/JXA — DONE (epic left OPEN)** (`f26695f`). `.sdef` + `ScriptingBridge`
  (encode/probe/listProfiles) existed but were inert. Activated: Info.plist `NSAppleScriptEnabled` +
  `OSAScriptingDefinition`; `.sdef` `<cocoa class>` bindings; new `ScriptingCommands.swift`
  (NSScriptCommand subclasses → `ScriptingBridge.shared` via `MainActor.assumeIsolated`, defensive
  arg-key lookup); `AppViewModel.init` wires `ScriptingBridge.shared.{engine,queue,profileStore}`;
  release.yml + dev-build.yml stage the `.sdef` at `Contents/Resources/` (was nested too deep for OSA);
  `Help/applescript-scripting.md` + HelpView registration. ⚠️ Runtime OSA dispatch is NOT CI-verifiable
  (needs signed .app + osascript) — compile/Info.plist/.sdef/staging verified, live round-trip must be
  smoke-tested on a packaged build. Epic OPEN — encode-complete events, queue-status properties,
  scriptable object graph remain.

- **#288 chapters — DONE (epic left OPEN)** (`914053d`). Detection + disk-export already worked; the gap
  was embedding chapters into an encode (job model had no field — button honestly disabled). Added
  `FFmpegArgumentBuilder.externalChaptersFile` (last `-i` input + `-map_chapters <idx>` instead of source,
  index-safe vs subtitle-replacement inputs) + `EncodingJobConfig.externalChaptersFile` (back-compat) +
  `AppViewModel.pendingChaptersFile` (mirrors `pendingManualCropFilter`, consumed once by enqueue). View's
  disabled "Apply to Job" → working "Embed in Next Encode" (writes FFmetadata, stages it).
  `ExternalChaptersArgumentTests`. Epic OPEN — timeline thumbnails, drag markers, batch detect remain.

- **CI fix — pre-existing test failures cleared** (`317e571`). CI on `wip/alpha-consolidation` had been
  RED since #468 over two `CheckpointManagerTests` using a non-existent `inputURL` (`listResumable
  Checkpoints()` filters checkpoints whose source file is gone — correct behaviour), plus my new
  `EncodingPipelineExecutorTests` "no copy" assertion catching `-c:s copy`. All three were TEST bugs
  (production code correct); fixed. **CI Build & Test is now GREEN on `wip/alpha-consolidation`
  (run 33652516255, commit 317e571)** — all round-2 tests + the fixed ones pass. Lesson recorded in
  [[verification-gates-and-what-cannot-be-tested]]: always check `gh run` after pushing test-bearing
  commits, since `swift test` can't run locally.

- **New standing rule (2026-09-02, user directive): monitor CI after every push/sync/PR, stay until
  green, fix reds immediately.** Codified as `standing_tasks.md` §15 + folded into W5 step 1 + memory
  [[always-monitor-ci-after-push]]. This closes the process gap that let CI stay red from #468 onward.

**Round-2 register: COMPLETE.** All eight worked this session — #482 conflicts, #286 throughput, #298
watermarks, #335 multi-output, #473 vector, #278 pipeline editor, #302 AppleScript/JXA, #288 chapters.
Six are epics left OPEN with detailed acceptance-criteria checklists in their issue comments (the
"never executed" defect is fixed in each; remaining items are visual/UX polish); #482 and #473 CLOSED.

---

## 🟢 2026-09-02 — disc-imaging executor (#495 P1) BUILT + docs + CI

**Landed on `wip/alpha-consolidation`:** `96f0617` (executor), `7325c5d` (docs + `-o` flag fix),
`+CHANGELOG`. Fable planned (exact signatures), Opus built the engine, Sonnet the CLI, Fable
adversarially reviewed; **all review findings fixed before commit.**

New (`Sources/ConverterEngine/Disc/Imaging/` + CLI): `RawCDReadPlanner`/`RawCDImagingConfig` (the bridge
that finally **consumes the dead `ImagingConfig.imageFormat`**), `CdrdaoTocParser` (→ existing
`DiscTableOfContents`), `CdrdaoProgressParser`, `DiscImagingController` (Process+AsyncStream+cancel+
checksum-verify), `BundledToolLocator`, `DiscProtectionDetector` (the #492 DRM policy in code),
`DriveListingParser`; `DiscImageFormat.ccd`; `BurnSettingsView` real device-node parsing; CLI
`meedya-convert disc {drives|toc|image}`. **29 unit tests** incl. a `.toc`→CUE round-trip.

**Review findings fixed (all real):**
- MAJOR — `.toc` FILE/DATAFILE grammar mis-read a leading `#byteOffset` as a length. Fixed
  (behaviour-preserving for cdrdao's own 2-operand output).
- MAJOR (**the fabricated-capability pattern again**) — the DRM gate could never fire: the image command
  hardcoded all-default markers → `detect()` always `.none` → dead refuse branch. Now the image path
  reads the TOC FIRST and refuses (genuinely reachable) any data-session disc (mixed-mode = later phase,
  #108/#135), so the audio-only markers it then feeds the gate are a *checked fact*. CSS/AACS/BD+/AACS2
  refusal is documented as DVD/BD-reader-phase markers.
- Controller lifecycle hardened (exitCode guards `isRunning`; terminationHandler clears the stderr
  readabilityHandler) — matching the FFmpeg model.
- CLI `-o` collisions fixed (`-o` = output path everywhere; `--format` has no short) — one caught in the
  review, a **second one (`DiscTocCommand`) I caught myself** during the docs pass.
- `buildMacOSUnmountArguments` doc corrected: I'd written it claimed a controller pre-step that doesn't
  exist (would have been another false comment) — reworded to honestly say it's a pure builder,
  not-yet-wired (the cdrdao-device→diskutil-node mapping needs hardware).

**Docs:** OpenAPI `/disc-drives|toc|image` (valid 3.1.0), in-app `cli-reference.md` disc section
(eight subcommands now), CHANGELOG. **#495 updated per-criterion.**

**⚠️ VERIFICATION BOUNDARY (stated everywhere):** `swift build` + the 29 tests are CI-green; but there
is **no optical drive in this environment or CI**, so every path that launches cdrdao against a device
is **compile-checked only, hardware-verified on the manual matrix (macOS-Direct + Linux)**. No simulated
read, no canned TOC, no fabricated node — it fails cleanly without a drive rather than faking success.
cdrdao is **not** in `ToolBundleManifest` yet (DR-0001 — bundled when the mirror stages it, PR
MeedyaDL-Tools#25); `BundledToolLocator` finds a PATH/Homebrew cdrdao meanwhile.

**#495 P1 remaining = hardware-matrix verification only.** Next disc components (later phases): NRG/MDX
writers, DVD/BD/UHD readers + their filesystem-marker DRM detection, mixed-mode (#108/#135), the GUI view.

---

## (superseded) 🔨 2026-09-02 — BUILDING the disc-imaging executor (#495 P1), autonomously

User: proceed autonomously; surface decisions upfront. Decisions stated + defaults taken (none blocking):
- **Increment = #495 P1: Audio CD → BIN/CUE vertical slice**, CLI-first (GUI is a follow-up — a SwiftUI
  view can only be compiled here, not exercised; the CLI read path is arg-builder-testable).
- cdrdao via subprocess, never linking libcdio (DR-0001).
- **Verification boundary, stated honestly:** pure logic (planners, parsers, protection detection, path
  resolution, drutil-parse fix) is CI-unit-tested; the actual cdrdao process execution against a physical
  disc is **compile-clean only here, hardware-verified on the manual matrix** — same split #495's
  serializer core used. No fabricated device I/O.

**Workflow `wvtgj7p76` (`wf_8354bc90-899`) RUNNING** — sequential pipeline:
1. Fable deep plan (exact type signatures so implementers align + DRM detector design + test plan).
2. Opus builds the engine core: `RawCDReadPlanner` (cdrdao arg builders), `CdrdaoTocParser`,
   `parseCdrdaoProgress`, `DiscImagingController` (Process+AsyncStream+cancel+checksum-verify, modelled on
   `FFmpegProcessController`), `BundledToolLocator` (factored from `FFmpegBundleManager`),
   `DiscProtectionDetector` (detect-and-warn gate, markers-only, Audio CD → .none), `.ccd` +
   `ImagingConfig.imageFormat` wiring, and the `BurnSettingsView.parseDrutilOutput` real-device fix.
3. Sonnet builds the CLI `disc image` / `disc info` on top.
4. Fable adversarial review — told a fabricated execution path or a wrong cdrdao invocation is a BLOCKER.

On completion: verify `swift build --target ConverterEngine` clean + `swift build` (filter #Preview) +
`swiftc -parse` tests; apply review findings; commit to `wip/alpha-consolidation`; update #495 (per-AC),
handoff, memory. The DRM detect-and-warn gate is built into the flow per the confirmed #492 policy.

---

## 🟢 2026-09-02 — #494 packaging + disc-imaging scope clarification

### #494 — user answered the four follow-on decisions; packaging begun

User decisions (recorded in DR-0001, `docs/decisions/0001-gpl-disc-tools.md`):
1. Keep #494 **open** until packaging is complete.
2. Host GPL **source + binaries in `MeedyaSuite/MeedyaDL-Tools`**, with per-tool source archival + CI updated.
3. **Build our own**, per platform, like ffmpeg.
4. Q "why not all tools at once?" → **all in the mirror this round; none in the app yet** — because the
   disc-imaging *executor* does not exist (`RawCDReadPlanner`/`DiscImagingController`/`CdrdaoTocParser`/
   `BundledToolLocator` all absent; cdrdao/wodim/cdparanoia have zero callers). Bundling one would be a
   fabricated capability. They enter the app with #495's executor.

**Done + pushed (MeedyaConverter, `f453856` on `wip/alpha-consolidation`):**
- `BundledTool.isGPLFamily` (SPDX-aware, excludes LGPL) + `ToolBundleManifest.gplTools`/`isAppStoreSafe`.
- Regression test: fails CI if any GPL tool enters `defaultManifest` (which ships to App Store).
- `scripts/verify-no-gpl-in-appstore.sh` — scans an assembled `.app` for GPL binaries; exit 7 if found;
  self-tested; wired into `testflight.yml` pre-signing validation.
- DR-0001 finalised with all four decisions + the guards.
- NOT done, deliberately (fabricated-capability): no GPL tool in `defaultManifest`, none in the DMG.

**Done + pushed (mirror `MeedyaSuite/MeedyaDL-Tools`, branch `feat/gpl-disc-tools`, PR #25):**
- versions.json + env pins for ddrescue/cdrdao/cdparanoia/wodim.
- **ddrescue** built from source (Linux x86_64) + **source tarball archived** to the release — the
  working template (GPLv3 corresponding-source obligation met from the mirror's own release).
- **Follow-ups documented in that repo's DEV_Status.md, NOT done blind:** cdrdao/cdparanoia/wodim Linux
  builds (finicky deps) and the **macOS-universal builds** — the mirror has **no macOS compile runner**
  today (macOS assets are downloaded, not compiled), so "build our own for macOS" needs a new
  `macos-latest` job. PR #25 is unlabelled; labelling it `update-tools` runs CI validation without
  publishing.

### ⚠️ DISC-IMAGING SCOPE CLARIFIED + a DRM DECISION SURFACED (issue #492 comment)

User clarified #492 is **bit-for-bit** copies across the full optical range — Audio CD, CD-G, mixed-mode/
eCD, CD, DVD, HD DVD, Blu-ray, 3D BD, **4K UHD Blu-ray** — with output to **ISO, CUE/BIN, NRG, MDX** and
compatible formats. Posted a detailed media→tool→format matrix on #492. Key facts recorded there:
- The GPL supply chain (cdrdao/ddrescue/cdparanoia/wodim) covers **reading** every media type; the
  container **formats** (ISO/BIN-CUE/NRG/MDX) are **our own clean-room serialisers**, not external tools.
  BIN/CUE writer already exists (#495 P1); NRG/MDX are clean-room to write.

**🔴 DECISION THE USER STILL OWES (surfaced on #492 and to the user directly):** the **DRM boundary**.
4K UHD BD (AACS 2.0), commercial BD/3D BD (AACS) and DVD (CSS) are protected, and the app's FAQ says it
does not circumvent DRM. Two readings:
- ✅ **Raw imaging** — copy the bits including encryption; a protected disc images as an *encrypted* file.
  Backup/preservation, NOT circumvention. This is the default and the ONLY thing I will build.
- ❌ **Decrypting** protected content to a playable copy = DRM circumvention. Conflicts with the app's
  policy, unlawful under DMCA §1201 / EU Copyright Directive Art. 6, and I will **not** implement it.
**RESOLVED 2026-09-02:** user confirmed **raw-imaging-only, never circumvention**, and added the
detect-and-warn rule: if a disc is DRM-protected such that even a bit-for-bit copy would be
non-functional (broken even on a legitimate DRM-capable player/drive), **do not produce a broken
artifact** — detect the protection via public markers (CSS IFO flags, `AACS/` dir, `BDSVM/` BD+,
drive-reported status; never touch keys) and warn "copy-protected, a working copy cannot be made
without circumvention, which we do not do." The warning fires ONLY when the copy would actually break
because of DRM. In practice this means the feature images Audio CD/CD-G/mixed-mode/eCD + unprotected
CD/DVD/BD, and declines-with-reason on genuinely-encrypted commercial DVD/BD/UHD. Full policy on the
#492 comment thread and in Claude memory (`disc-imaging-drm-policy`). No code yet — this is executor
design capture; the executor (#495's missing half) must implement the detect-and-warn gate first and
never add a decrypt path. **No open DRM decision remains.**

---

## 🟢 SESSION COMPLETE — 2026-09-02 · all queued work done

### ✅ Final state

- **Branch `wip/alpha-consolidation`, 31 commits ahead of `alpha`, tree clean, CI green on every commit.**
  No PR opened (per the no-stacking rule). `swift build` + `swift test --parallel` pass.
- **Issues: 93 open / 359 closed.** Closed this session: #496, #497, #277, #475, #356, #329, #390,
  #448, #471, #451. Reopened as closed-in-error: 12.
- Documentation fully reconciled: CHANGELOG, README, PROJECT_STATUS, FEATURES, docs/Architecture,
  all docs/ guides, both OpenAPI specs (3.1.0 valid), the Swagger UI banner, and 5 in-app help files.
- `.claude/` refreshed: `project_brief.md`, `standing_tasks.md` (W10 verification gates, W11
  read-only siblings), `HANDOFF.md`, and 9 Claude memory files.

### ⚠️ Two errors of MINE, caught by the final re-verification and corrected

Recording these because the correction matters more than the appearance of a clean run:

1. **`761101c`'s commit message claimed the File-menu ⌘O fix had landed. It had not.**
   `MeedyaConverterApp.swift` kept its literal `.keyboardShortcut("o", modifiers: .command)`, so
   rebinding `file.import` changed the toolbar button while the menu silently stayed on ⌘O.
   Fixed in `f4bb44f`; #331 comment corrected publicly.
2. **The #280 reopen rationale was factually wrong.** I wrote "`MiniPlayerWindow` has zero callers.
   Nothing constructs or presents it." In fact `MiniPlayerController` IS constructed
   (`AppViewModel.swift:389`) and toggled from two live sites (`ContentView.swift:235`,
   `MeedyaConverterApp.swift:185`). My grep matched the FILE name, not the type, and I generalised
   without confirming — the exact mistake this session was auditing for. The issue stays open for a
   narrower real defect: `updateProgress` has zero callers, so the panel shows no live progress.
   Correction posted.

### 📋 ROUND-2 RANKED PROPOSALS — awaiting user selection

Full detail in `.claude/proposals-round2-2026-09-02.json`. Ranks 1-2 spot-verified by the orchestrator.

| # | Size/Risk | Proposal | Issue |
|---|---|---|---|
| 1 | XS/low | Apply the persisted theme: tint the app root from ThemeManager so Appearance settings stop being ignored | 336 |
| 2 | S/low | Populate estimatedSourceDuration at enqueue AND stop the __duration: tag leaking into the ffmpeg argv | 326 |
| 3 | XS/low | Unfreeze ParallelEncodingView's throughput tiles — they read unobserved ObservableObjects at parent level | 286 |
| 4 | S/low | Wire NotificationActionHandler: register categories, set the delegate, stamp categoryIdentifier on posted notifications | 361 |
| 5 | XS/low | Unit-test PostEncodeHookRunner's serialisation — the reentrant-actor defect class has no regression guard | new |
| 6 | S/medium | Evaluate conditional rules on the watch-folder enqueue path — the automation path skips the automation feature | new (follow-up to closed #469) |
| 7 | S/low | Drag completed outputs out of the queue — wire the orphaned DraggableFileView onto finished job rows | 285 |
| 8 | S/medium | Top up free queue slots when jobs are added mid-run, not only when a job finishes | 286 |
| 9 | M/low | Periodic checkpointing during healthy encodes — crash-safe resume data for the scenario resumability exists for | 468 |
| 10 | M/medium | Activate AppleScript dispatch (#302) — until it lands, this session's #451 suspend/resume rewrite is unreachable code | 302 |
| 11 | M/low | Strategic: add a MeedyaConverterTests target — the app module where this session's defects lived has zero testable surface | new |
| 12 | M/medium | Team profiles: compute the local-vs-remote conflict diff so the Conflicts section can ever render, and test the manager | 482 |
| 13 | M/medium | Give scene detection's chapters somewhere to live: add chapters to EncodingJobConfig and enable Apply to Job | 288 |
| 14 | M/medium | Apply watermarks for real: persist WatermarkConfig on the profile and inject the overlay at encode time | 298 |
| 15 | M/medium | Multi-output encoding executes: run tee when possible, else enqueue per-output jobs | 335 |
| 16 | M/medium | Vector conversion screens: wire input picker + Convert, or hide both nav entries until they work | 473 |
| 17 | L/medium | Strategic: make the pipeline editor stop discarding work — persist pipelines and fix the executor's dead-conditional encode stub | 278 |

**Orchestrator verification of the top two:**
- **#1 (#336 themes)** — confirmed: `grep '\.tint(' MeedyaConverterApp.swift ContentView.swift`
  returns **nothing**. The accent colour and sidebar tint are persisted and then ignored.
- **#2 (#326 queue optimiser)** — confirmed, and it is a **latent landmine, not just a no-op**:
  `estimatedSourceDuration` is implemented by smuggling a `__duration:<value>` string into
  `extraArguments` (`SmartQueueOptimizer.swift:194-203`), and
  `FFmpegArgumentBuilder.swift:446` does `args.append(contentsOf: extraArguments)`. Nothing sets it
  today, so nothing breaks — but **populating the duration, which is the obvious fix, would pass
  `__duration:123.4` to ffmpeg as a literal argument.** The smuggling must be removed first. A good
  example of why the proposal register cites code rather than issue text.

### Deferred / blocked, for the record

- **#494** — decision Accepted (DR-0001); packaging work (licence texts, source offer, App-Store
  exclusion check, moving the drafted manifest entries) not started. User's call whether the issue
  closes on the decision or stays open for execution.
- **#286 width > 1** — never run. Unverifiable here and in CI. Opt-in, entitlement-gated, default 1.
- **MeedyaSuite-core** — its MusicBrainz hardening still sits on `feature/work-in-progress`,
  unmerged; `main` still builds Lucene queries by raw interpolation. Needs merging before Nov 30.
- **MeedyaDL** — uncommitted staged rename + 2 untracked files on `alpha`, one `git clean` from loss.

### ✅ ALL 11 SELECTED ITEMS DONE — batch C committed, CI green on every commit

`45a8931` — **#286** bounded-concurrency queue (opt-in, width 1 default) · **#329** A/B comparison
capture→persist→compare. **CI `Build & Test (macOS)` SUCCESS at `45a8931`, `761101c`, `b845cf7`,
`2f9519f`** — so `swift build` + `swift test --parallel` pass over everything.

**#286 was deliberately gated behind a Fable go/no-go plan** before any code was written. It returned
`proceed-reduced-scope`, and its most valuable finding is that three hazards are **bugs in the CURRENT
sequential queue**, not merely risks of going concurrent:

1. `EncodingEngine` held ONE `activeController` optional and `runFFmpegPass`'s
   `defer { setActiveController(nil) }` cleared it unconditionally — **`cancelCurrentJob` already
   races that defer today**. Now a keyed `[UUID: FFmpegProcessController]` registry.
2. Both statistics writes built a **fresh** `EncodingStatisticsStore` doing load-append-rewrite of
   `encoding_history.json`; the per-instance `NSLock` protects nothing across instances. Safe today
   only because the sequential loop awaits each write. Now one `EncodingStatisticsRecorder` actor.
3. `EncodingActivityIndicator.stopTracking` tears down the menu-bar item and dock tile, so the first
   job to finish would blank them while others ran. Lifecycle moved to the queue.

**Rollback is two-layered:** persisted max-concurrency defaults to **1** (TaskGroup degenerates to
today's exact sequence), and `.parallelEncoding` is entitlement-gated (`EntitlementGating.swift:152`,
`FreeGateProvider` returns false) so width clamps to 1 when unentitled.

⚠️ **NOT VERIFIED, and stated as such in the commit, the issue and the eventual PR:** no interleaved
multi-job encode has been run anywhere. `swift test` cannot run here and **CI cannot spawn a real
multi-job FFmpeg encode either**. Width > 1 is unproven at runtime.

#### The false-comment pattern struck again — in code written this session

`PostEncodeHookRunner` was an `actor` whose doc promised chains run "strictly one at a time". **It
serialised nothing.** Swift actors are **reentrant**: the whole body was one `await chain.execute(...)`,
so the actor was released on entry and two concurrent completions would run the user's shell scripts
in parallel. Fixed by chaining each run behind a stored tail task; the comments now say explicitly
that actor isolation is *not* what provides serialisation.

Also fixed: the menu-bar popover's ETA/Bitrate rows went permanently empty (their only writer was the
Combine sink the queue no longer uses), contradicting the "width 1 is exactly the old behaviour" claim
the whole safety argument rests on.

**That is the FIFTH false comment this session, and the THIRD written by a well-intentioned change
rather than inherited.** Recorded in Claude memory as the project's dominant defect class, with the
review question that catches it: *does this claim hold at every call site, not just the one in front
of me?*

#### #329 review findings fixed
Difference mode never generated its image when it was already the active mode as frames loaded (both
triggers are `onChange` and neither value changes there) — the user saw an honest-*looking* but false
"could not be generated". And the frame scrubber's `0...0` range when only one extraction pass
succeeded is degenerate (NaN thumb position).

### Issue state after all implementation

**94 open / 358 closed.** Closed this session: #496, #497, #277, #475, #356, #329, #390, #448, #471.
Reopened as closed-in-error (12): #343, #63, #59, #323, #324, #257, #285, #280, #330, #361, #303, #336.
Left open with precisely-stated remaining scope: #322 (crossfade), #288 (chapters on job model),
#451 (likely closeable), #281 (drag-onto-icon), #331, #286 (width > 1 unverified), #494 (packaging).

### 🔄 FINAL PHASE RUNNING — workflow `w8hn1ymz9` / `wf_70efdf65-caf`

Three parallel Sonnet docs agents (CHANGELOG/README/PROJECT_STATUS · FEATURES/Architecture/in-app help
· OpenAPI specs + docs guides), then **sequential Fable**: re-verify every issue this session touched
(including whether anything was closed prematurely, and whether any of the 12 reopens was wrong), then
produce the **round-2 ranked proposal register**.

### ✅ Batches A and B COMMITTED + PUSHED — 9 of the 11 selected items done

| Commit | Items |
|---|---|
| `b845cf7` | **#322** concatenation Start · **#288** scene detection executes · **#451** ScriptingBridge semaphore · **#331** (toolbar shortcuts) |
| `761101c` | **#277** failure-path hooks · **#475** hardware kill switch · **#356** URL-scheme routing · **#281** menu bar · **#331** (navigation commands) |

**Issues:** #277, #475, #356 **CLOSED**. #322, #288, #451, #281, #331 updated and left open for their
stated remaining scope. CI green at `b845cf7`; `761101c` in flight.

#### Defects the adversarial reviews caught (all fixed before commit)

These are the reason the review layer is worth its cost — several would have shipped:

- **#475 default polarity — would have regressed every fresh install.** `UserDefaults.bool(forKey:)`
  answers `false` for a key never written, so a kill switch defaulting to `false` would have been
  **engaged out of the box**, silently downgrading the built-in `hardwareH264`/`hardwareH265`
  profiles to software encoding. Default now `true`, read via `object(forKey:)`.
- **#475 caption was false.** It claimed "forced off for every job" while the override lived in ONE
  of **seven** `EncodingJobConfig` construction sites. Now centralised in
  `Sources/MeedyaConverter/Services/HardwareAccelerationPreference.swift` and applied at all seven
  app paths (incl. `FFmpegPreviewView`, because that view shows the command that WILL run). CLI and
  HTTP API deliberately excluded, and the caption now says so.
- **#281 menu-bar sync only worked while the main window existed** — useless in menu-bar-only mode,
  the exact scenario the feature is for. Settings scene now carries the same sync.
- **#281 "Open Main Window" matched ANY titled window**, so opening Settings from the status menu
  broke it. Now matches the main window by `WindowGroup` identifier.
- **#322 shared `errorMessage`** with the file-import alert — a dismissed import error lingered as red
  text in the Concatenate section, implying a join failed that never ran. Dedicated state now.
- **#331 `displayString(for:)` (orchestrator's own bug)** still rendered bindings `binding(for:)`
  rejects, so a corrupt entry showed a bare `⌘` — reintroducing the drift the API exists to remove.

#### Latent crash found and fixed

`KeyEquivalent(Character(binding.key))` **traps** on an empty or multi-character key, and `key` is
decoded from `UserDefaults` JSON — a crash from data the app itself persisted.
`ShortcutBinding.keyEquivalent` is now failable.

#### Two more false comments found (the recurring theme)

- `ScriptingBridge.swift` claimed a non-blocking fix "would require restructuring as an
  `NSScriptCommand` subclass… out of scope". **Verified wrong** against the installed SDK header.
- The replacement comment then implied the suspend/resume path was live. It is not: the `.sdef` has
  **no** `<cocoa>` mappings and nothing registers `ScriptingBridge.shared`, so OSA cannot dispatch
  until **#302**. A precondition note now says so.
- **#288 needed no engine code at all.** `SceneDetector.swift` diff is empty — builder and parser
  already existed and already matched ffmpeg's `metadata=print` format. It was only ever missing a caller.

### 🔨 Batch C — RUNNING (workflow `wa54ybaqj` / `wf_0a1094ac-2ba`)

**#286 is deliberately gated behind a Fable go/no-go plan before any code is written.** `startQueue()`
is ~470 lines with singular state throughout (`activeJobState`, `engine.queue.currentJob`,
`activityIndicator.startTracking`, one sleep-prevention token, per-job log association) and
pause/resume/cancel semantics that are undefined for N jobs. Tests **cannot** run here and CI cannot
exercise a real multi-job encode either, so the planner was explicitly told that `do-not-proceed` or
`proceed-reduced-scope` are acceptable answers and not to recommend the ambitious option to be
helpful. If it says stop, we stop and report that to the user.

**#329** runs in parallel (disjoint files): make the A/B capture → persist → compare loop real, so
`ComparisonLibraryView.entries` — which today has **no writer anywhere** — stops being a permanently
empty screen.

Both are followed by sequential Fable adversarial review, with the #286 reviewer told that a real race
or lost-update window is a **blocker**.

### 🔨 Batch A — IMPLEMENTED, build clean, reviews in progress (NOT yet committed)

Workflow `wk2po9vjp` (`wf_22ba6021-5a0`). Four Sonnet implementers on disjoint files, then sequential
Fable adversarial reviews. `swift build` shows **0 real errors** (only the 16 `#Preview` macro errors
+ their `emit-module` wrapper, which are the CommandLineTools-no-Xcode artefact).

| Issue | Outcome |
|---|---|
| **#322** | Start button runs `buildDemuxerConcatArguments` through a real `FFmpegProcessController` and writes a joined file, existence-checked before reporting success. Crossfade (`buildFilterConcatArguments`, still 0 callers) left **visibly disabled with an honest label** rather than silently inert. |
| **#288** | `detectScenes()` now spawns ffmpeg, drains progress, reads the metadata file and parses real timestamps. Orchestrator verified the pairing end-to-end: the 3-arg `buildDetectionArguments` emits `metadata=print:file=<path>`, and `parseSceneOutput` pairs `pts_time:` with `lavfi.scene_score=` — matching ffmpeg's actual output format. **`SceneDetector.swift` was NOT modified** (git diff empty), so both builder and parser pre-existed; nothing fabricated. "Apply to Job" is honestly disabled with a stated reason because `EncodingJobConfig` genuinely has no chapters field. |
| **#451** | `DispatchSemaphore` + 60 s wait replaced with Cocoa Scripting's `NSScriptCommand.current()` / `suspendExecution()` / `resumeExecution(withResult:)`. The timeout outcome is preserved via a structured TaskGroup race. **The file's own existing comment — claiming this "would require restructuring as an NSScriptCommand subclass… out of scope" — was verified WRONG against the real SDK header.** Another false comment found. |
| **#331** | Toolbar Import/Encode shortcuts now resolve through `shortcutManager.binding(for:)` with factory fallbacks. |

**Orchestrator's own follow-up work on #331** (the implementer stopped at the two toolbar sites):
- **Tooltips were still hard-coded** (`"(Cmd+O)"`), so rebinding would leave the help text advertising
  a dead key. Now derived via a new `KeyboardShortcutManager.displayString(for:)`.
- **Latent crash fixed:** `KeyEquivalent(Character(binding.key))` **traps** on an empty or
  multi-character `key`, and `key` is decoded from `UserDefaults` JSON — i.e. a crash from data the
  app itself persisted. `ShortcutBinding.keyEquivalent` is now failable and `binding(for:)` degrades
  to the caller's fallback.
- **Duplicate key tables consolidated.** The runtime switch (`makeKeyboardShortcut`) and the editor's
  display switch (`KeyboardShortcutsView.shortcutDisplayString`) were separate copies in different
  files that had to be kept in lockstep by hand. Both now derive from one `ShortcutBinding.namedKeys`
  table.

**Review findings acted on so far:**
- *(#322, minor — real)* `errorMessage` was shared with the file-import alert, so a dismissed import
  error lingered as red text in the Concatenate section, implying a failed join that never ran.
  Fixed with a dedicated `concatErrorMessage`.
- *(#331, minor — real, and it was MY bug)* `displayString(for:)` still rendered a binding that
  `binding(for:)` rejects, so a corrupt persisted binding would show e.g. a bare `⌘` in the tooltip —
  reintroducing the very drift the API exists to remove. Both methods now agree on usability.
- *(#331, noted)* `MeedyaConverterApp.swift:112`'s File-menu "Import Media Files…" still hardcodes
  ⌘O — assigned to Batch B, which owns that file.

### 🔨 Batch B — RUNNING (workflow `w1g6hq1rp` / `wf_37984245-d28`)

Sequential, because these all share files: **B1** #277 failure-path hooks + #475
`useHardwareAcceleration` kill switch (`AppViewModel.swift`, `SettingsView.swift`) → **B2** #356
non-profile URL routing + #281 menu-bar controller + #331 navigation commands
(`MeedyaConverterApp.swift`, `URLSchemeHandler.swift`, `MenuBarController.swift`). Then sequential
Fable review of both diffs.

**Design decision recorded for #475:** the global toggle becomes a **kill switch**, not a duplicate of
the per-profile `EncodingProfile.useHardwareEncoding` (which is real and already reaches the argument
builder at `EncodingProfile.swift:303`). ON = today's behaviour, profile decides. OFF = force software.
The override must sit **after** the conditional-rules block in the enqueue path, so a rule-selected
profile cannot silently defeat a global kill switch.

**Still queued:** Batch C (#286 bounded-concurrency queue, #329 A/B comparison — Opus), then the full
issue re-sweep, docs sweep, `.claude/` refresh and round-2 proposals.

### 🗳️ RANKED NEW-WORK PROPOSALS — awaiting user selection (Fable, code-cited)

Produced by the final sequential Fable pass over the reconciliation + a spot-audit of the 361 closed
issues. Every `why` cites a real code fact. Ranks 1-4 spot-verified by the orchestrator.

| # | Size/Risk | Proposal | Issue |
|---|---|---|---|
| 1 | XS/low | Fire post-encode hooks on the failure path so runOnFailure actions can actually run | 277 |
| 2 | XS/low | Route non-profile meedyaconverter:// URLs into the already-written URLSchemeHandler | 356 |
| 3 | XS/low | Wire useHardwareAcceleration into encode arguments (or delete the toggle) | 475 |
| 4 | XS/low | Reopen 11 closed-in-error issues: shipped-as-done features that are orphaned code with zero callers | new |
| 5 | S/low | Populate estimatedSourceDuration at enqueue so 3 of 7 queue-optimizer strategies stop being no-ops | 326 |
| 6 | S/low | Give ConcatenationView a Start action that actually joins files | 322 |
| 7 | S/low | Apply saved keyboard shortcuts — derive live bindings from KeyboardShortcutManager | 331 |
| 8 | S/low | Instantiate MenuBarController at app start, gated on the showMenuBarStatus toggle | 281 |
| 9 | M/low | Execute scene detection: run the built ffmpeg args and populate detectedScenes | 288 |
| 10 | S/medium | Rescope #451 to the one remaining seam: eliminate ScriptingBridge's 60-second semaphore block | 451 |
| 11 | S/medium | Activate AppleScript/JXA: register OSA keys and configure ScriptingBridge.shared at launch | 302 |
| 12 | M/medium | Vector conversion screens: wire input picker + Convert action, or hide both nav entries | 473 |
| 13 | M/low | Periodic checkpointing during healthy encodes (crash-safe resume data) | 468 |
| 14 | M/medium | Team profiles: implement the local-vs-remote conflict diff and add TeamProfileManager tests | 482 |
| 15 | M/medium | Apply watermarks for real: persist WatermarkConfig on the profile and inject the filter at encode | 298 |
| 16 | M/medium | Multi-output encoding executes: run tee or enqueue per-output sequential jobs | 335 |
| 17 | L/high | Strategic: bounded-concurrency queue — replace the sequential startQueue loop with a TaskGroup sized by ParallelEncoder | 286 |
| 18 | L/medium | Strategic: A/B comparison capture → persist → compare loop (with real SSIM/PSNR) | 329 |

**Detail** (files + acceptance criteria are in `<session scratchpad>/proposals.json` and in the workflow journal for run `wf_2db8de65-437`):

**1. Fire post-encode hooks on the failure path so runOnFailure actions can actually run** — `XS`/low risk · issue 277  
  PostEncodeActionChain supports runOnFailure (Sources/ConverterEngine/Encoding/PostEncodeActions.swift:280) and the Hooks tab lets users configure failure actions, but the queue's failure branch (Sources/MeedyaConverter/ViewModels/AppViewModel.swift:1400-1432) never invokes the chain — only the success handler at AppViewModel.swift:1332-1337 does. Every failure-triggered webhook/script a user configures silently never fires.  
  *Files:* Sources/MeedyaConverter/ViewModels/AppViewModel.swift (failure branch ~1400-1432); Sources/ConverterEngine/Encoding/PostEncodeActions.swift (read-only)

**2. Route non-profile meedyaconverter:// URLs into the already-written URLSchemeHandler** — `XS`/low risk · issue 356  
  The scheme is registered (Sources/MeedyaConverter/Resources/Info.plist:41-50) and .onOpenURL is live (MeedyaConverterApp.swift:101), but the handler only recognises profile-share URLs (MeedyaConverterApp.swift:202-233) and silently drops everything else. URLSchemeHandler.handleURL (Sources/MeedyaConverter/Services/URLSchemeHandler.swift:131, actions at :22-42) implements encode/probe/open fully and has zero callers — the feature is one call away from working.  
  *Files:* Sources/MeedyaConverter/MeedyaConverterApp.swift (~101, 202-233); Sources/MeedyaConverter/Services/URLSchemeHandler.swift

**3. Wire useHardwareAcceleration into encode arguments (or delete the toggle)** — `XS`/low risk · issue 475  
  The Settings toggle useHardwareAcceleration is read nowhere outside its declaration and Toggle (SettingsView.swift:189, 202 — repo-wide grep confirms zero other readers). It is the last of #475's eight dead toggles; flipping it changes nothing about encoding, a straight lie to the user.  
  *Files:* Sources/MeedyaConverter/Views/SettingsView.swift:189,202; Sources/MeedyaConverter/ViewModels/AppViewModel.swift (enqueue/arg construction)

**4. Reopen 11 closed-in-error issues: shipped-as-done features that are orphaned code with zero callers** — `XS`/low risk · issue new  
  Spot-audit of the 361 closed issues found 11 whose capability never executes: #343 SlateGeneratorView+SlateGenerator (zero references anywhere outside their own files), #63/#59 StreamingEnhancements.swift (sprites + HLS AES — zero refs outside own file), #323 VideoStabilizer (zero callers), #324 DeinterlaceConfig (zero callers), #257 ToolUpdateChecker (referenced only from Tests/ConverterEngineTests/ConverterEngineTests+Pipelines.swift), #285 DraggableFileView (zero callers; SourceFileView.swift:132 handles drop-in only), #280 MiniPlayerWindow (zero callers), #330 SettingsUndoManager (zero cal  
  *Files:* GitHub bookkeeping + evidence comments; code files as cited per issue

**5. Populate estimatedSourceDuration at enqueue so 3 of 7 queue-optimizer strategies stop being no-ops** — `S`/low risk · issue 326  
  QueueOptimizerView genuinely reorders the live queue (QueueOptimizerView.swift:230 → EncodingQueue.reorder, EncodingJob.swift:384), but shortestFirst/longestFirst/estimatedTime read EncodingJobConfig.estimatedSourceDuration (SmartQueueOptimizer.swift:192-206) which nothing ever sets — grep for '.estimatedSourceDuration =' returns zero — so the stable sort silently leaves order unchanged. The duration is already known from the probe step; one assignment at enqueue activates three strategies.  
  *Files:* Sources/MeedyaConverter/ViewModels/AppViewModel.swift (enqueue path ~822); Sources/ConverterEngine/Encoding/EncodingJob.swift:128 (priority default, optional follow-up)

**6. Give ConcatenationView a Start action that actually joins files** — `S`/low risk · issue 322  
  The dedicated join screen has reorder, method picker, crossfade slider and live compatibility warnings (ConcatenationView.swift:377) but its only buttons are OK/Browse/Add Files (:109/:292/:340) — no Concatenate action and zero process invocation, so it can never produce output. The demuxer argument builder already works and is executed elsewhere (VideoConcatenator.buildDemuxerConcatArguments run from VideoTrimmerView.swift:746), so the execution pattern exists to copy.  
  *Files:* Sources/MeedyaConverter/Views/ConcatenationView.swift; Sources/ConverterEngine/Utilities/VideoConcatenator.swift (read-only); VideoTrimmerView.swift:746 (pattern)

**7. Apply saved keyboard shortcuts — derive live bindings from KeyboardShortcutManager** — `S`/low risk · issue 331  
  KeyboardShortcutManager persists bindings and detects conflicts (KeyboardShortcutManager.swift:118-125, 199-216) with a working editor, but binding(for:) (:186-191) has zero callers; the only live shortcuts are hardcoded Cmd+O and Cmd+Return (ContentView.swift:196/208). Remapping in Settings changes nothing — a settings screen that lies.  
  *Files:* Sources/MeedyaConverter/Views/ContentView.swift:196,208; Sources/MeedyaConverter/Services/KeyboardShortcutManager.swift:131-160,186-191

**8. Instantiate MenuBarController at app start, gated on the showMenuBarStatus toggle** — `S`/low risk · issue 281  
  MenuBarController is a complete NSStatusItem implementation (status item MenuBarController.swift:108-124, menu :165-222, Dock toggle :238-243) that is never constructed — grep for 'MenuBarController(' returns nothing — and the SettingsView showMenuBarStatus toggle (SettingsView.swift:152/171) is itself unread. One wiring fixes two user-visible lies: a documented menu-bar feature that never appears and a toggle that does nothing.  
  *Files:* Sources/MeedyaConverter/MeedyaConverterApp.swift; Sources/MeedyaConverter/Components/MenuBarController.swift; Sources/MeedyaConverter/Views/SettingsView.swift:152,171

**9. Execute scene detection: run the built ffmpeg args and populate detectedScenes** — `M`/low risk · issue 288  
  detectScenes() (SceneDetectorView.swift:381-403) builds arguments via SceneDetector.buildDetectionArguments (SceneDetector.swift:216-256), logs a line, and never spawns a process; detectedScenes is only populated by manual markers (:405-421), and applyChaptersToJob (:465-471) only logs. The downstream half is already real — OGM/XML/FFmetadata generation (SceneDetector.swift:448-524) and NSSavePanel export (:429-463) work — so wiring detection completes an almost-finished feature.  
  *Files:* Sources/MeedyaConverter/Views/SceneDetectorView.swift:381-403,465-471; Sources/ConverterEngine/FFmpeg/SceneDetector.swift

**10. Rescope #451 to the one remaining seam: eliminate ScriptingBridge's 60-second semaphore block** — `S`/medium risk · issue 451  
  All other #451 sites are remediated (TeamProfileView.swift:273-313 uses the safe Task pattern; BurnSettingsView/ImageConversionView have zero remaining nonisolated(unsafe)/DispatchSemaphore), but DispatchSemaphore(value: 0) at ScriptingBridge.swift:304 with a 60s wait at :333 still blocks the calling thread — the issue's named worst offender and its third acceptance criterion.  
  *Files:* Sources/MeedyaConverter/Scripting/ScriptingBridge.swift:304,333

**11. Activate AppleScript/JXA: register OSA keys and configure ScriptingBridge.shared at launch** — `S`/medium risk · issue 302  
  The .sdef is bundled (Package.swift:404) and ScriptingBridge implements encode/probe/listProfiles/queueStatus (ScriptingBridge.swift:198/274/345/364), but .shared.engine/.queue/.profileStore are never assigned anywhere and Info.plist lacks NSAppleScriptEnabled/OSAScriptingDefinition, so macOS has no route to dispatch to the class — every command would return 'not configured' even if it could.  
  *Files:* Sources/MeedyaConverter/Resources/Info.plist; Sources/MeedyaConverter/MeedyaConverterApp.swift; Sources/MeedyaConverter/Scripting/ScriptingBridge.swift

**12. Vector conversion screens: wire input picker + Convert action, or hide both nav entries** — `M`/medium risk · issue 473  
  VectorConversionView and ProResVectorView are reachable (SidebarView.swift:71-72; ContentView.swift:109/:111) yet contain no fileImporter/NSOpenPanel, no Convert action and no Process() — users land on settings-only forms that cannot convert anything. RasterVectorConverter has zero callers outside its own file; ProResToVectorConverter's only external use is a size-estimate helper (ProResVectorView.swift:321-330).  
  *Files:* Sources/MeedyaConverter/Views/VectorConversionView.swift; Sources/MeedyaConverter/Views/ProResVectorView.swift; Sources/ConverterEngine/FFmpeg/RasterVectorConverter.swift; SidebarView.swift:71-72

**13. Periodic checkpointing during healthy encodes (crash-safe resume data)** — `M`/low risk · issue 468  
  saveCheckpoint now fires on failure (AppViewModel.swift:1399) and cancel (:1533), but nothing writes during a healthy encode, so a crash or force-quit mid-encode leaves no checkpoint — the exact scenario resumability exists for. ResumableJobsView is reachable (ContentView.swift:93) and re-queues honestly (ResumableJobsView.swift:165-190), so the missing piece is just the periodic writer.  
  *Files:* Sources/MeedyaConverter/ViewModels/AppViewModel.swift (progress handler in startQueue); Sources/ConverterEngine (CheckpointManager)

**14. Team profiles: implement the local-vs-remote conflict diff and add TeamProfileManager tests** — `M`/medium risk · issue 482  
  The fabricated-success push is fixed (real URLSession + 2xx check, TeamProfileManager.swift:188), but conflictedProfiles is only ever assigned [] (TeamProfileView.swift:64 and :354) — no diff logic exists anywhere, so the Conflicts section (TeamProfileView.swift:191-211) can never render — and zero tests under Tests/ reference TeamProfileManager or pushProfiles.  
  *Files:* Sources/MeedyaConverter/Services/TeamProfileManager.swift; Sources/MeedyaConverter/Views/TeamProfileView.swift:64,191-211,354; Tests/ (new file)

**15. Apply watermarks for real: persist WatermarkConfig on the profile and inject the filter at encode** — `M`/medium risk · issue 298  
  WatermarkOverlay builds runnable argument arrays (buildVideoWatermarkArguments WatermarkOverlay.swift:204, buildImageWatermarkArguments :247) but the view only calls the filter-string builders for a read-only preview (WatermarkView.swift:194-196); the runnable builders have zero callers and EncodingProfile has no watermark field — a reachable configuration screen whose output is never used.  
  *Files:* Sources/ConverterEngine/Models/EncodingProfile.swift (new field + codable migration); Sources/ConverterEngine/FFmpeg/WatermarkOverlay.swift; Sources/MeedyaConverter/Views/WatermarkView.swift; argument-construction path i

**16. Multi-output encoding executes: run tee or enqueue per-output sequential jobs** — `M`/medium risk · issue 335  
  MultiOutputEncoder builds a correct tee-muxer set (buildTeeArguments MultiOutputEncoder.swift:108), sequential per-output arrays (:162) and a real canUseTee check (:207), but MultiOutputView calls them only to render a command preview (argumentsText, MultiOutputView.swift:199) — the file has no Start button and no process reference, so the screen never produces output.  
  *Files:* Sources/MeedyaConverter/Views/MultiOutputView.swift; Sources/ConverterEngine/Encoding/MultiOutputEncoder.swift

**17. Strategic: bounded-concurrency queue — replace the sequential startQueue loop with a TaskGroup sized by ParallelEncoder** — `L`/high risk · issue 286  
  AppViewModel.startQueue() (AppViewModel.swift:1053) awaits one job at a time by construction; ParallelEncoder's real concurrency/resource maths (determineMaxConcurrent ParallelEncoder.swift:129, partitionJobs :159) is called only from ParallelEncodingView, whose activeJobs state (:90) is never fed from the live queue — the parallel dashboard's slider and gauges are pure decoration. This is the single most tester-visible performance feature in the backlog, with the hard math already written and unit-tested.  
  *Files:* Sources/MeedyaConverter/ViewModels/AppViewModel.swift:1053+ (queue loop, completion/failure handlers, stats collector); Sources/ConverterEngine/Encoding/ParallelEncoder.swift; Sources/MeedyaConverter/Views/ParallelEncodi

**18. Strategic: A/B comparison capture → persist → compare loop (with real SSIM/PSNR)** — `L`/medium risk · issue 329  
  ComparisonCapture/FrameComparisonExtractor build correct capture and SSIM/PSNR/VMAF arguments (ComparisonCapture.swift:232-250) but their only external reference is a comment; ComparisonView is never instantiated and its frames array (:33) never assigned; ComparisonLibraryView is reachable (ContentView.swift:156-157) but entries (:27) has no writer anywhere — a permanently empty screen shipped to testers. QualityMetricsView proves the execution pattern (real process runs) to reuse.  
  *Files:* Sources/ConverterEngine/Utilities/ComparisonCapture.swift; Sources/MeedyaConverter/Views/ComparisonView.swift; Sources/MeedyaConverter/Views/ComparisonLibraryView.swift; new ComparisonEntry persistence store

**Orchestrator spot-verification of the top items (all held):**
- **#1** — the post-encode chain is invoked only in the success branch (`AppViewModel.swift:~1304`); the failure branch (`:1393-1410`) writes a checkpoint, tracks analytics, logs and notifies but **never calls the chain**, so `runOnFailure` actions cannot run.
- **#2** — `URLSchemeHandler` has **zero references outside its own file**; `onOpenURL` handles only profile-share links inline.
- **#4** — `SlateGenerator`, `VideoStabilizer`, `DeinterlaceConfig` and `ToolUpdateChecker` each have **0** references outside their own file, yet their issues are CLOSED.

### Work landed this session (all on `wip/alpha-consolidation`, all pushed)

| Commit | What |
|---|---|
| `4c42111` | **#496** CI trigger — `'wip/**'` added to `build.yml` `push.branches`. **Issue CLOSED.** |
| `a239e5f` | handoff: session start state |
| `8f74e0d` | handoff: verified findings |
| `1887353` | **#497-F** `/serve` in the CLI OpenAPI spec + `Resources/Help/cli-reference.md` |
| `75fd2ad` | **#497-C/D/E** Architecture.md / FEATURES.md / PROJECT_STATUS.md / Home.md / FAQ.md / both migration docs |
| `6baf46a` | **#493** inline metadata search throws instead of faking `[]`; SEARCH-666 quality guidance corrected |
| `a8fb62a` | **#497-A/B** HTTP API spec + `docs/api/README.md` + **swagger-ui banner** — stop calling working endpoints fabricated. **Issue #497 CLOSED.** |

**CI:** every push now triggers `Build & Test (macOS)` on this branch (that was the point of #496).
`75fd2ad` green; later pushes in flight. `swift build --target ConverterEngine` verified clean locally
before each Swift commit; `swiftc -parse` used on the new test file (no local XCTest — CI is the test gate).

### Issue sweep — reconciliation pass 1 of 2 APPLIED (#147-#346, 45 issues)

Fable reconciled all 45 open issues in slices 1-3 against the code. Outcome:
**21 partially-done · 13 inert-fabricated · 11 not-started · 0 to close.**
25 needed no change; **20 evidence-cited comments were posted** to
#163 #178 #205 #275 #277 #278 #281 #283 #286 #288 #294 #298 #302 #320 #322 #326 #329 #331 #335 #346.

Quality is high — the pass corrected the *issue bodies* where they were wrong, not just their status.
Four claims were independently spot-verified by the orchestrator before/after posting and all held:
- **#163** — the issue asks for `buildInvalidationXML`; no such method exists. The real one is
  `buildInvalidationBody` (`ExtendedCloudProviders.swift:35`). Confirmed by grep.
- **#281** — `MenuBarController` is complete (NSStatusItem, menu, Dock toggle) but is **never
  instantiated**; the only other mentions are two comments in `ControlCenterModule.swift`. Confirmed.
- **#286** — `AppViewModel.startQueue()` is sequential by construction, per its own doc comment at
  `AppViewModel.swift:1049`. Confirmed.
- **#302** — the AppleScript `.sdef` really is bundled (`Package.swift:404`). Confirmed.

One posted comment was **patched before sending**: #205's text described
`SuiteCoreMetadataAdapter.searchViaInline` as returning `[]` — true when the audit ran, fixed since in
`6baf46a`. It now describes the throw, and says the lookup capability itself is still absent.

Every comment carries a footer marking it as a W1 code-first reconciliation.

### Issue sweep — reconciliation pass 2 APPLIED (#353-#495, 44 issues) — SWEEP COMPLETE

**16 partially-done · 15 not-started · 6 inert-fabricated · 3 obsolete · 3 fully-done · 1 done-on-branch.**
**27 comments posted**; **3 issues CLOSED**, each independently re-verified by the orchestrator first:

- **#390** (ITMS-90236 ICNS) — `scripts/generate-app-icns.sh:102` maps `icon_1024x1024.png` to
  `icon_512x512@2x.png`, the exact slot the rejection names, then runs `iconutil`. Invoked by
  `release.yml:380` and `testflight.yml:230`, and `testflight.yml:317` **fails the build** if the
  `.icns` is missing. Verified.
- **#448** (placeholder UIs) — all five checklist items verified executing: DualDynamicHDR
  (`DualDynamicHDRView.swift:538` → executor → `HDR10PlusToolWrapper.runAsync` → real `Process()` at
  `:330`), BitrateHeatmap (`:475 try await backend.runFFprobe(... timeout: 300)`), AnimatedImage
  (the `"<source>"` placeholder is gone repo-wide; real `FFmpegProcessController`), EncodingGraphs
  (`currentStatistics` computed from `statisticsStore.allStatistics`), CloudSync (`:362`
  `viewModel.engine.profileStore.profiles` → `manager.uploadProfiles`).
  ⚠️ **A caveat comment was posted BEFORE closing**, because the title is broader than the checklist:
  Watermark (#298), Pipeline editor (#278), Keyboard shortcuts (#331), Scene detect (#288),
  Comparison (#329) and Vector (#473) are all still reachable-but-inert, and `MetadataEditorView` /
  `APIServerView` / `SlateGeneratorView` are still orphaned. The close must not be read as
  "no placeholder UIs remain".
- **#471** (IntAppsAPI) — `RemoteFeatureGateProvider` is a live `AppViewModel` property (`:300`),
  refreshed at launch from `MeedyaConverterApp.swift`. Verified.

**Rescope-not-close** (comment posted, title deliberately left alone so issue identity is stable):
**#451** (only `ScriptingBridge.swift:304`'s `DispatchSemaphore` + 60 s wait at `:333` remains),
**#468** (checkpoints write on fail/cancel only — no periodic write, and Resume re-queues from 0%),
**#475** (7 of 8 toggles now wired; only `useHardwareAcceleration` is still read nowhere).

**#494** left for the user — the GPL disc-tools licensing decision. `ToolBundleManifest` still carries
**zero** GPL entries (MIT/MPL-2.0/BSD-2-Clause/LGPL-2.1 only), and no decision document exists.

Two comments were **patched before posting** because the audit's snapshot had been overtaken by this
session's own commits: #205 (`searchViaInline` now throws, per `6baf46a`) and #477 (the stale doc
mentions were fixed in `75fd2ad`).

**Issue count: 89 open → 86 open.** (#496 and #497 were opened and closed within the session.)

### NEW verified defects found this session, not previously tracked as such

- **#331 keyboard shortcuts are a no-op.** `KeyboardShortcutManager.binding(for:)`
  (`Services/KeyboardShortcutManager.swift:186`) — the only method converting a saved binding into a
  SwiftUI `KeyboardShortcut` — has **zero callers**. Settings rebinds 7 actions
  (`navigate.source/output/queue/dashboard/settings`, `encode.start`, `file.import`), detects
  conflicts and persists to `UserDefaults`, while all **34** real shortcuts stay hardcoded — e.g.
  `MeedyaConverterApp.swift:112` pins ⌘O regardless of `file.import`. Contained fix.
- **#298 watermark never applied.** `WatermarkView` is a live sidebar destination ("Add watermark
  overlay") that renders only an "FFmpeg Filter Preview" text box.
  `buildVideoWatermarkArguments` / `buildImageWatermarkArguments` have **zero callers**.
- **#278 pipeline editor discards its work.** `OutputSettingsView.swift:83` presents
  `PipelineEditorView()` with no `onSave`.


### MusicBrainz Nov-30 — Fable verdict (pass 1 complete, primary-source-backed)

**Nothing in the Meedya suite breaks on 30 November 2026.** Per-ticket:
- **SEARCH-444** (area/url `relation-list`) — no. No repo searches `area`/`url`.
- **SEARCH-642** (drop cdstub/tag `id`) — no. The string `cdstub` appears in no source file in any repo;
  suite-core's `MbTag` reads only `name`/`count`.
- **SEARCH-666** (quality names replace numeric) — no. No repo emits a `quality:` clause or reads a
  `quality` property.
- **SEARCH-752** (`target` removed) — no. MeedyaConverter parses no MusicBrainz JSON at all; suite-core's
  structs have no `relations`/`target`; **MeedyaDL** reads `target` only as a *legacy fallback* on
  lookup/browse responses (never search), preferring `target-type` — already correct.
- **SEARCH-764** (Solr 10) — mirror owners only; no repo runs a mirror or any Solr config.

**Decision taken: Option B.** Keep MeedyaConverter builders-only; do not build an inline Swift MusicBrainz
client. Reasons, all evidence-backed: (1) `docs/MeedyaSuite-core-integration.md:28` plans to **remove** the
inline clients in favour of suite-core, so a new Swift client is built-to-be-deleted duplication of the Rust
provider that already exists; (2) the SUITE_CORE path is aspirational on both ends — `SuiteCoreMetadataAdapter`
calls `MeedyaCore.metadataSearch` but MeedyaSuite-core's `bindings/swift` contains only a README, so
"just flip `SUITE_CORE=1`" would not produce a working lookup; (3) Option A is ~5-7 files / 1000+ LOC for a
capability Nov 30 does not threaten. **A real end-to-end lookup is therefore NEW WORK and goes on the ranked
proposals list for the user to choose — it is not smuggled in under a "don't break on Nov 30" directive.**

**Existing hardening confirmed CORRECT** on inspection in both repos: backslash escaped before quote
(`MetadataLookup.swift:363-365`; suite-core `lucene.rs` `quote_phrase`), phrase-quoting correctly leaves other
Lucene specials literal, the percent-encode set correctly strips `&+=?#/;:@$` and space from
`.urlQueryAllowed`, and the base URL is single-sourced.

### ⚠️ CROSS-REPO ITEMS THE USER MUST DECIDE OR DO (we are NOT touching those repos)

1. **MeedyaSuite-core: the hardening is on an unmerged branch only.** `97ba626` and `a7354d3` are verified
   **not** ancestors of `main`. `main`'s provider still builds queries by **raw interpolation** — i.e. the
   real Lucene-injection bugs are what ships from `main` today. Everything Nov-30-relevant lives on
   `feature/work-in-progress`. **Merge it before 30 November**, or `main` keeps the bugs and gains no
   forward-compat test.
2. **MeedyaDL has uncommitted work at risk.** Branch `alpha` holds a staged rename
   (`musicbrainz_service.rs` → `musicbrainz_service/mod.rs`) plus **two untracked files**
   (`relations.rs`, `search.rs`). Untracked files are one `git clean` from gone.
3. Both sibling repos are being edited by **concurrent sessions**; treat line-number citations as
   time-sensitive and re-run `git status` before touching either.

### Verified findings — orchestrator's own greps (independent of the agents, all re-checkable)

**The entire metadata-LOOKUP subsystem is dead code.** Not "partially wired" — dead:
- `Sources/ConverterEngine/Metadata/` contains **no** `URLSession` / `URLRequest` / `JSONDecoder` at all.
  Every provider (TMDB, TVDB, MusicBrainz, Discogs, FanArt, OpenSubtitles, OMDb) is a URL **builder** only.
- `MusicBrainzClient` — zero production callers; referenced only from
  `Tests/ConverterEngineTests/ConverterEngineTests+CloudAndMetadataLookup.swift`.
- `AutoTagger` / `AutoTagConfig` — **zero references outside `Sources/ConverterEngine/FFmpeg/AutoTagger.swift`**.
- `MetadataEditorView` — orphaned (self-references only; no `NavigationItem` case, no `ContentView` arm).
- The app's only metadata surface is `NavigationItem.metadataTags` →
  `MetadataTagEditorView` (`ContentView.swift:119`), which **does** work (#467, `0f1dc0f`) but offers **no
  lookup affordance whatsoever** — no "search", "fetch", "MusicBrainz" or "TMDB" string in the file.

⇒ Nothing in MeedyaConverter can break on 30 November, because nothing calls MusicBrainz. The Nov-30
work here is therefore *correctness-of-the-builders + honesty-of-the-docs*, not a migration. Building a
real lookup client is NEW WORK and belongs in the ranked proposals for the user to choose, not smuggled
in under a "don't break on Nov 30" directive.

**Two false capability claims in shipped docs (fix in the docs pass):**
- `docs/Home.md:92` — "MusicBrainz, TMDB, TVDB, Discogs, FanArt.tv integration". There is no integration.
- `docs/FAQ.md:205` — "(optional, when you request metadata from MusicBrainz, TMDB, etc.)". You cannot.

**`docs/Architecture.md` is the worst-affected doc.** It presents as live architecture:
- **7 modules deleted in the orphan sweep** — `EncodingReport` (lines 74, 114, 123), `HDRPolicyEngine`
  (115, 209), `MetadataPassthrough` (74 "MetaPassthru", 122), `MetadataTagger` (122), `PQToHLGPipeline`
  (115), `SmartCropIntegration` (114), `SubtitleConverter` (116).
- **6 modules that exist but have ZERO references outside their own file** — `ColorSpaceConverter`,
  `HLGToDolbyVision`, `CodecMetadataPreserver`, `StreamingEnhancements`, `ForensicWatermark`,
  `ContentAnalyzer`. Plus `AIUpscaler`, reachable only from the dead `FFmpegBackend`/`FFmpegBackendFactory`
  scaffold (#477).

**`FEATURES.md`'s dead-code table is stale in both directions:**
- 5 rows describe files that no longer exist (`MultiStreamSelector`, `EncodingReport`,
  `ColourSpaceConverter`, `HDRPolicyEngine`, `SmartCropIntegration`) as "exists but unwired".
- 5 rows still say a feature does not work when the 2026-08-04 wave fixed it: #467 (`0f1dc0f`),
  #355 (`1773763`), #277 (`3ee5072`), #469 (`27b42dd`), #468 (`444bde1`).

**API docs:** `docs/api/meedya-convert-api.yaml` has paths for encode/probe/profiles/batch/manifest/validate
but **no `/serve`**, though `ServeCommand` shipped in `1773763` and is registered at
`Sources/meedya-convert/MeedyaConvert.swift:21-29`. `Resources/Help/cli-reference.md` never mentions
`serve` either. Both specs parse clean as OpenAPI 3.1.0; `meedya-http-api.yaml`'s five paths **do** match
`APIServer.swift:458-466`. All 12 help `.md` files are registered in `HelpView.swift`'s `HelpTopicRegistry`.

**Cross-repo:** MeedyaSuite-core's `fix/musicbrainz-lucene-hardening` and
`claude/branch-audit-musicbrainz-migration-l5h8zh` **no longer exist on the remote**. Per the GitHub API the
repo now has `main`, `alpha`, `beta`, `feature/work-in-progress`. All the MusicBrainz commits are reachable
from `feature/work-in-progress` (13 ahead of `main`, pushed) — consolidated, not lost. That consolidation
was done by a **concurrent session** (commits authored 21:45–21:55 during this session), so **MeedyaSuite-core
is read-only from here**. Its local checkout was left on `feature/work-in-progress` by that other session;
do not "restore" it.

### Decisions surfaced to the user (per W8 — asked upfront, work continues meanwhile)
1. **MusicBrainz scope.** Verified against code: **every** metadata provider in MeedyaConverter is
   URL-builders only. `Sources/ConverterEngine/Metadata/` contains **zero** `URLSession` use, no response
   parsing, and `MusicBrainzClient` has **no production callers** (tests only). So nothing can break on
   Nov 30 — and equally, MusicBrainz lookup does not work today.
   **Option A (recommended):** build it end-to-end (rate-limited client + lenient decoding + reachable
   UI/CLI entry), Nov-30-safe by construction. **Option B:** builders-only + honest docs, confine the
   Nov-30 work to MeedyaSuite-core (which does make real requests).
2. **#494 GPL disc tools** — bundle cdrdao/ddrescue/wodim in Direct builds vs PATH-detect vs native
   reimplementation. Licensing call; gates #492/#495 *packaging* only, not code.
3. **Ranked new-work list** — to be presented from the Fable proposals pass; user picks.

---

## 🟢 Current session — 2026-09-01 (MusicBrainz Nov-30-2026 search-upgrade readiness + disc-imaging issue + plugin/standing-tasks)

**User directive:** ahead of MusicBrainz's reported Nov 30 2026 search upgrade,
ensure no functionality is lost/broken (autonomously). Plus: file a disc-backup-
imaging feature issue; refresh standing tasks; adopt the dev-team plugin.
Analysis/planning via **sequential Fable** agents; implementation via **Sonnet**.

**MusicBrainz Nov-30-2026 — VERIFIED SAFE (no migration required).** The
announcement (Solr 9→10; breaking tickets SEARCH-444/642/666/752/764) was
assessed against every MusicBrainz call in both repos. We use only
recording/release **search** (fields `recording`/`release`/`artist`) plus
`recording/<mbid>` and `discid` **lookups** (MeedyaConverter — no HTTP, no
parsing) and `recording`/`work` search (MeedyaSuite-core). We never query
`area`/`url`/`cdstub`/`tag`, never use the `quality:` field, never read a
relationship `target` property, and are not a Solr mirror; suite-core serde is
lenient (no `deny_unknown_fields`, all `Option`) so additive fields are safe.
Tracked in #493. **ENV NOTE:** the announcement is UNREACHABLE from this egress
environment (HTTP 403 on all metabrainz.org hosts) — content was supplied by
the user; validate against beta.musicbrainz.org if egress is ever opened.

**Work landed this session:**
- **MeedyaConverter `wip/alpha-consolidation`** (pushed; now 4 ahead of `alpha`,
  0 behind — clean unmerged work for a future wip→alpha PR):
  - `bbb3c05` — `.claude/standing_tasks.md` W3/W4/W8 refreshed (ALL analysis +
    planning → sequential Fable; implementation → Sonnet; dev-team plugin URL +
    scope; surface questions upfront).
  - `45f2706` — MusicBrainz builder hardening: Lucene escaping + phrase-quoting
    + safe percent-encoding + centralised base URL + tests (#493 Part A).
  - `46c1dfb` — "verified-safe" docs (CHANGELOG + `MusicBrainzClient` /
    `AudioCDReader` doc comments) for the Nov-30 change (#493 Part B).
- **MeedyaSuite-core branch `fix/musicbrainz-lucene-hardening`** (PUSHED, no PR
  per user; separate MIT/Rust repo attached with push access this session):
  - `a7354d3` — Lucene hardening port (shared `lucene.rs`; phrase-quote
    recording/artistname; escape isrc/iswc normalised).
  - `2d847b0` — reqwest 30s timeouts; populate `ProviderResult.musicbrainz_id`;
    `release:`/`date:` clauses from album/year (#493 robustness follow-ups).
  - `bc13f21` — populate `ProviderResult.genre` from MB genres/tags (#73).
  - `cargo build/test/clippy --all-features` green (138 tests).

**Issues:**
- **#492** — cross-platform disc-backup imaging (Audio CD/mixed-mode/eCD/CD+G;
  BIN/CUE + NRG + subchannel-carrying formats; ISRC/CD-Text/indexes/pre-emphasis).
  Feature is NOT built (orphaned scaffold, umbrella #476); reconciled the wrongly-
  "completed" #238/#143/#118/#108/#135 per W1. QUEUED (not implemented).
- **#493** — MusicBrainz: Part A (hardening) done+pushed; Part B (Nov-30 migration)
  verified safe / not required; Part C (suite-core) done on branch.
- **MeedyaSuite-core #73** (genre — implemented on branch, closes on merge),
  **#74** (deferred robustness: rate-limiter wiring + earliest-dated release).

**Tooling:** dev-team plugin cloned + registered
(github.com/MWBMPartners/dev-team-plugin).

---

## 🟡 Current session — 2026-08-04 (project-state reconciliation + new-work proposals + docs)

**User directive (this session):** full sweep of ALL GitHub Issues (open + closed) reconciled
against the ACTUAL codebase (no assumptions); refresh all `.claude/` memory/context + this handoff;
propose ranked new-work for the alpha cycle; thorough docs update (`.md` + in-app help + OpenAPI +
Swagger UI); codify the workflow directive as repo-wide standing tasks. NO PR stacking — all commits
to `wip/alpha-consolidation`.

**State at session start:**
- Branch `wip/alpha-consolidation` @ `2f58fc3` (PR #480 metadata-passthrough merged in). Tree clean.
- **PR #472** (draft, `wip/alpha-consolidation` → `alpha`) — ALL 6 checks GREEN: Build & Test (macOS),
  CodeQL, Analyze Swift, Review Dependencies, actionlint, GitHub Actions pin hygiene. 244 commits,
  mergeable_state `clean`. Still DRAFT (do not merge — work ongoing).
- **98 open issues** (was 42 at 2026-07-18; grew because the completeness audit reopened ~28
  closed-in-error issues + filed #473–#477).

**Progress this session (update as you go):**
- [x] Codified the workflow directive as repo-wide standing tasks → `.claude/standing_tasks.md`
      new "Workflow & Processing Standing Tasks" section (W1–W9). (commit `4a28e32`)
- [x] Fable-5 sequential deep-analysis agent: reconciled open issues vs current code + produced
      ranked new-work proposals. Register captured below.
- [x] Applied per-issue GitHub updates (17 comments) from the register — evidence-cited, honest that
      DONE items stay open until #472 merges.
- [x] Refreshed `.claude/project_brief.md` (branch, 98 issues, honesty status).
- [x] Thorough docs sweep — README/PROJECT_STATUS/CHANGELOG/FEATURES reconciled to the honest map
      (commit `f0bee18`). Docs agent grep-found NEW reachable-but-inert defects: **SceneDetectorView
      never launches Process (#288)**, **PipelineEditorView has no onSave / PipelineExecutor 0 callers
      (#278)** — commented on both. Also confirmed dead: thumbnail sprites, HLS AES-128/DRM, AccurateRip,
      multi-stream selector, encoding reports, ColourSpaceConverter. **OpenAPI reconciliation still owed**
      (do at end after code settles).
- [x] Presented ranked new-work proposals → **user chose "Whole ranked set #1–12", in ranked order,
      autonomously, per-task commits + per-issue updates. PAUSE on #12 (resumable-jobs delete-vs-minimal).**
- [x] **Quick wins #1–4 DONE + pushed** (all diffs reviewed for compile+runtime correctness):
      `ef2d8ca` #466 CLI codec/container honesty (copy→passthrough, reject unknown) ·
      `4e99dcf` #448 QueueOptimizer.reorder applied to live queue ·
      `685ff8e` #474 SmartCrop Apply-to-Job → pendingManualCropFilter merged at enqueue ·
      `a770ea3` #481 Help menu → openWindow(id:"help"). Issues #466/#448/#474/#481 updated.
- [x] **M-tier batch 1 DONE + pushed** (`b75aba4`, all 4 files reviewed compile-correct):
      **#475** wired `autoScrollLog`, `defaultProfileName`, `customFFmpeg/ffprobePath`, `confirmBeforeEncoding`
      (Queue tab Start only); left unwired w/ reasons: `useHardwareAcceleration` (per-profile), `showMenuBarStatus`
      (MenuBarController never instantiated → deeper orphan #477), `accurateRip.*` (orphaned engine #477).
      **#470** ETAPredictor wired (predictETA supersede + recordEncode + lastKnownInputDuration; cold-start→linear).
      Issues #475/#470 updated.
- [~] **CI:** HEAD `b75aba4` pushed; Build & Test (macOS) in progress (actionlint/deps/pin green).
      Earlier batch (`a770ea3` quick wins) already confirmed Build & Test GREEN.
- [~] **Fabrication-audit Workflow `wom8m9da9` RUNNING** (read-only, 9 Sonnet finders + Fable synth) — exhaustive
      code-first seam sweep for NEW fabricated-capability defects beyond those already catalogued. Apply its
      register (issue updates + new fixes/issues) when it lands. **Hold impl until it finishes** (keeps its reads clean).
- [x] **Exhaustive fabrication-audit Workflow `wom8m9da9` COMPLETE** (10 agents, 2.2M tokens) — **59 deduped
      seams** with grep evidence, mapped to issues. Full register archived in the workflow journal; key NEW
      HIGH-impact findings below. **GitHub bookkeeping DONE:** filed **#482** (team-push fake success), **#483** (heatmap blank
      PNG), **#484** (batch exits 0 on fail), **#485** (per-stream subtitle ignored), **#486** (PQ/HDR10 signalling),
      **#487** (import drops subtitleTonemap), **#488** (bg-removal save panel), **#489** (CLI profiles blind to
      imports), **#490** (ManifestCommand inert opts), **#491** (share links unconsumable) + 25 comments on existing.
      **In-flight:** M2 engine-fix agent → row8=#486, row9=#487, row3=#484, row7=#485.

### Audit register — HIGH-impact NEW seams (2026-08-04, verified vs code)
- **row 8 — PQ/HDR10 colour signalling never applied** (`FFmpegArgumentBuilder.buildPQPreservationArguments`
  unwired; `.hlg` sibling IS wired at EncodingJob.swift:198-201). REAL HDR bug. → M2 fixing.
- **row 9 — profile import drops `subtitleTonemap`** (EncodingProfile.swift:981-1026 + ProfileSharing.swift:91-132).
  Silent data loss. → M2 fixing.
- **row 3 — `batch --job-file` exits 0 on failure** (BatchCommand.swift:168-205; sibling runDirectoryBatch throws).
  → M2 fixing.
- **row 7 — per-stream subtitle overrides ignored** by `toArgumentBuilder`. → M2 fixing.
- row 1 — TeamProfile `.httpServer` push reports success, sends nothing; row 2 — BitrateHeatmap "Export Image"
  writes a blank PNG; row 4 — NormalizationSettings "Measure Levels" no-op (#292); row 5 — PostEncodeActionChain
  never invoked (#277); row 6 — outputMode/OutputPathResolver mirror-folder no-op (#275); rows 10/11/12-14/18 —
  bg-removal save panel, CLI ProfilesCommand blind to imports, ManifestCommand inert options, unconsumable share links.
- MED mapped to existing: #353,#286,#331,#340,#329,#377,#473,#281,#468,#333,#346,#241.
- **row 24 — checkpoint/resume unwired** (follow-up to #468).

### DECISIONS TO SURFACE (present, don't block — continue other work)
1. **Orphan-sweep (rows 28-59): ~6,000 lines of zero-caller engine code** — delete-or-wire. Several files carry
   FALSE "live call site" comments (PQToHLGPipeline, RasterVectorConverter, FFmpegBackend/Factory). Recommendation:
   DELETE the pure-dead duplicates/false-comment ones (SmartCropIntegration dup, ColorSpaceConverter US-spelled dup,
   EncodingBackend scaffold, PQToHLGPipeline), correct false prose; LEAVE the issue-tracked feature stubs
   (#324/#352/#350/#338/#257/#323/#285/#241/#346/#446). Needs user OK on deletions.
2. **#468 resumable jobs** — delete-vs-honest-minimal (already flagged).

- [x] **M2 engine-correctness batch DONE + pushed** (`75f2de0` #486, `aa0d66e` #484, `9b92932` #485+#487):
      #486 PQ/HDR10 signalling **+ latent HLG-clobber bug** (extraArguments overwrite reorder — HLG preservation
      was silently broken too); #484 batch --job-file non-zero exit on failure; #485 per-stream subtitle overrides
      (new FFmpegArgumentBuilder hook); #487 subtitleTonemap preserved on profile import (+new test). Issues updated.
      All symbols verified vs real code (CaseIterable, ExitCodes.encodingFailed, SubtitleStreamOverride, .dolbyVision).
- [x] **Agent A DONE (`3ee5072`):** #277 post-encode hooks (persist chain + invoke on completion + watchFolder
      postAction via side table; failure-path runOnFailure left out, noted), #275 outputMode (OutputPathResolver
      .resolveOutputDirectory extracted + used in enqueue). Verified vs real APIs. Issues updated.
- [x] **Agent B DONE (`8da5c9f`/`bb9e818`):** #482 team-push real PUT (stop faking success; conflictedProfiles
      r25 still open), #483 BitrateHeatmap real ImageRenderer export. Verified. Issues updated.
- [~] **CI:** HEAD `3ee5072` (B+A) Build & Test in progress. Prior batches all green.
- [x] **Agent C DONE (`3fe0538`/`54e530d`):** #489 CLI profiles/validate resolve against store; #490 ManifestCommand
      rejects --hdr / unknown codecs / custom-without-ladder. Verified. Issues updated.
- [x] **Agent D DONE (`0f1dc0f`/`8183a83`):** #467 MetadataTagEditorView real Write-Tags execution; #292
      NormalizationSettings measureLevels real ffmpeg. Verified. Issues updated.
- [x] **Agent E DONE (`27b42dd`/`4f9c012`):** #469 conditional rules apply-at-enqueue + surfaced view, #488
      bg-removal chosen output dir. Verified. Issues updated. Batch CI (`4f9c012`) Build & Test + CodeQL GREEN.
- [x] **Docs finalization DONE (`b81b546`):** CHANGELOG + README + PROJECT_STATUS + OpenAPI CLI spec +
      cli-reference.md reconciled to the fix wave (grounded in the 20 fix commits; YAML validated). Fixed a stale
      "conditional rules not wired" note.
- [x] **✅ AUTONOMOUS QUEUE COMPLETE (2026-08-04).** 21 issues fixed + full state reconciliation + honesty docs +
      exhaustive 59-seam audit + standing tasks W1–W9, all on `wip/alpha-consolidation`. PR #472 still DRAFT
      (do NOT merge). Fix commits: ef2d8ca #466 · 4e99dcf #448 · 685ff8e #474 · a770ea3 #481 · b75aba4 #475/#470 ·
      75f2de0 #486 · aa0d66e #484 · 9b92932 #485/#487 · 8da5c9f #482 · bb9e818 #483 · 3ee5072 #277/#275 ·
      3fe0538 #489 · 54e530d #490 · 0f1dc0f #467 · 8183a83 #292 · 27b42dd #469 · 4f9c012 #488 · b81b546 docs.
      Remaining = the 4 user DECISIONS below + lower-priority OPEN issues tracked in GitHub with evidence:
      #288, #278, #446, #482(r25 conflicts UI), #329, #333, #340, #353, #286, #331, #281, #241, #324, #352,
      #350, #338, #257, #323, #285.

### DECISIONS — USER DECIDED 2026-08-04, ALL 4 IMPLEMENTED ✅ — AUTONOMOUS QUEUE COMPLETE
> #355 serve (`1773763`), #491 URL-import+scheme (`3147c8d`), #468 honest-minimal resumable (`444bde1`),
> orphan-sweep batches 1+2 (`af83104`+`7f59196`, Build & Test GREEN). Only remainder = the documented
> kept-for-safety orphan follow-up + long-horizon backlog issues. Nothing else queued.
1. **Orphan-sweep** → IN PROGRESS. Fable delete-list DONE (verified; both ColorSpace spellings + their chains
   are production-dead). Orchestrator independently grep-confirmed. Execution in CI-gated batches:
   - **Batch 1 DONE+pushed (`af83104`):** deleted AudioMixer.swift, ClosedCaptionHandler.swift, SubtitleOCR.swift
     (0 refs in Sources AND Tests — no test trims needed).
   - **Batch 2 DONE+pushed (`7f59196`) — Build & Test macOS GREEN:** deleted 14 clearly-dead whole files
     (SubtitleConverter, Extended*×4, EncodingReport, MediaInfoIntegration, MetadataPassthrough, MetadataTagger,
     MultiStreamSelector, SmartCropIntegration, HDRPolicyEngine, ColourSpaceConverter, PQToHLGPipeline) + trimmed
     9 mixed-scope test files + fixed 3 false "live" comments. Independently verified: deleted-type grep=0 in
     Sources+Tests, no deleted file extended a live type / defined a called free func, test files brace-balanced.
     **Total sweep: 17 files / ~4,500 lines. #477 commented, left OPEN for the kept-for-safety remainder + the
     3D/disc/DCP/app-service clusters (not in this pass).**
   - **EXCLUDED for safety (kept + documented for a future pass):** `ColorSpaceConverter.swift` (US — its
     ToneMapAlgorithm name-collides with the live nested `FFmpegArgumentBuilder.ToneMapAlgorithm`),
     `Backend/EncodingBackend.swift` (EncodingJob name-collision risk), `Models/FeatureGate.swift` + the
     `EncodingEngine.featureGate` removal (Feature/ProductTier collision + engine edits), and the surgical
     in-live-file cuts (generateDolbyVisionRPU, AudioProcessor ReplayGain branch, MediaServerConfigStore,
     MiniPlayerView, StorageAnalyzer.estimateSavings). All are harmless dead code; removing them is deferred
     to avoid a blind build break. **KEEP per issue-tracking:** ExtendedCloudProviders (#163-173/#459),
     RasterVectorConverter (#473, comment fixed), AudioProcessor two-pass measurement branch (#292).
2. **#468 resumable** → **HONEST-MINIMAL** (checkpoint on cancel/fail, surface view, relabel Resume→Re-queue).
   Sonnet RUNNING (`a4863e…`). Files: AppViewModel/ResumableJobsView/ContentView/SidebarView.
3. **#355 API serve** → **ADD** `meedya-convert serve` subcommand. Sonnet RUNNING (`a44800…`). New ServeCommand.swift + MeedyaConvert.swift.
4. **#491 share links** → **WIRE** `meedyaconverter://profile/` onOpenURL import route. Sonnet RUNNING (`a14770…`). MeedyaConverterApp/URLSchemeHandler.
   (Each: orchestrator reviews diff → commit → push → CI-gate → update issue. Then final docs/CHANGELOG top-up + wrap-up.)

### Reconciliation register (verified vs code @ `2f58fc3`, 2026-08-04)

**DONE-ON-BRANCH (implemented + wired; closes on PR #472 merge):**
#459 cloud-upload execution (`CloudUploadExecutor`, real URLSession legs + scp; caller
`CloudStorageView`/`PostEncodeActions`) · #284 unified stats (`EncodingStatisticsStore` sole source,
collector in queue loop, persists on success+fail) · #348 email (`sendCompletionEmail`→curl) · #296
webhook (`WebhookSender` POST) · #268 watch-folder enqueue+encode · #334 recent files · #279
scheduled encoding (`onJobReady`→`startQueue`) · #471 IntAppsAPI (dormant/fail-safe) · overwrite +
delete-source toggles (part of #475).

**PARTIAL:** #448 (many views wired; still orphaned: MetadataEditorView, ResumableJobsView,
APIServerView, ConditionalRulesView, SlateGeneratorView, ComparisonView; still inert-but-reachable:
QueueOptimizer.applyOptimisation fabricates success, MetadataTagEditor display-only, Concatenation no
execute, MultiOutput display-only, Watermark config unused) · #475 (2 fixed, ~7 keys still write-only)
· #476 (burn real+reachable; rip/author no entry) · #355 (server real+tested, no nav/CLI entry) ·
#277 (chain engine real; not persisted, not invoked on completion, postAction ignored) · #451 (30
`Task.detached` + 6 `nonisolated(unsafe)` sites, mostly documented-safe).

**STILL-OPEN:** #467 (MetadataTagEditor never executes; MetadataEditorView orphaned) · #468 (no
checkpoint writer; view orphaned; "resume" restarts at 0) · #469 (rules never read at encode) · #470
(ETAPredictor 0 callers; naive inline ETA at AppViewModel:952) · #473 (no executor / no source flow) ·
#474 (`applyCropToJob()` empty) · #466 (CLI advertises `copy`/codecs that silently fall back) · #477
(dead clusters: 3D/Spatial, disc readers, DCP/ForensicWatermark/VVC/TrueHD/HLGToDolbyVision, AI/audio,
ColourSpaceConverter dup, + app-service orphans HandoffManager/URLSchemeHandler/etc.).

### Ranked new-work proposals (Fable, for user decision — NOT yet started)

1. CLI reject unknown codec/container + support `copy` (#466) — **S**
2. QueueOptimizer actually apply reorder (#448) — **S**
3. SmartCrop "Apply to Job" (#474) — **S**
4. Fix broken Help menu (Cmd+? no-op; `openHelpWindow` opens a URL scheme with no handler) — **S**
5. Honor/remove remaining dead Settings keys (#475) — **M** (each S)
6. Execute metadata tag writes (#467) — **M**
7. Persist + fire post-encode hooks, honor watch-folder postAction (#277) — **M**
8. Entry point for the real API server (#355/#448) — **S–M**
9. Wire ETAPredictor into queue ETA (#470) — **S–M**
10. Apply conditional rules at enqueue (#469) — **M**
11. Resumable-jobs honesty decision: delete vs honest-minimal (#468) — **M**
12. Orphaned app-service sweep: wire-or-delete (#477) — **M**

**Note:** local clones of the 3 consolidated branches still exist on disk (harmless); their REMOTE
counterparts are already deleted (origin has only alpha/beta/main/wip-alpha-consolidation).

---

## ⚠️ Read this first — branch model (as of 2026-07-22)

- **`wip/alpha-consolidation`** is THE single work-in-progress branch. All work commits here.
  It will eventually be merged into **`alpha`** via ONE pull request (deliberately **no PR stacking**).
- `main` = trunk, contains all completed work. `alpha`/`beta` = live pre-release channel branches
  wired to `.github/workflows/beta-alpha.yml` (**never delete; a push to them mints a public pre-release**).
- **Consolidated + verified obsolete (2026-07-22):** `claude/branch-audit-consolidate-g87lr4`,
  `autopilot/2026-06-30-clean`, `consolidate/autopilot-2026-07-18`. Content-level verification confirmed
  zero loss (audit doc cherry-picked byte-identical; the two autopilot branches are strict ancestors of main).
  **Deletion is pending a manual step** — this environment's git proxy refuses ref deletions and the GitHub
  MCP has no delete-branch tool, so they must be deleted in the GitHub UI.
- **Forecast for the eventual `wip/alpha-consolidation` → `alpha` PR:** exactly 2 conflicts, both resolve
  **wip-side**: `.github/workflows/dependency-review.yml` and `.github/workflows/lint.yml`.

---

## Where we are

- Code is **feature-complete for v0.1.0**; the GA *release ritual* (#428) is still pending.
- The project runs a **dev-team / autopilot** convention: state in `.dev-team/autopilot.json`,
  custom subagents in `.claude/agents/` (`deep-architect`, `quick-edits`), context in `.claude/`.
- **Orchestration model (per user standing instructions):** Fable 5 (sequential, not parallel)
  for all analysis / deep planning — fall back to Opus only if Fable is unavailable, then retry
  Fable next time. Implementation via **Sonnet / Haiku** (Opus only if truly necessary).
  Efficient credit/token use; GIRFT (get it right first time). No local macOS build available —
  CI (`Build & Test (macOS)`) is the correctness gate for all Swift changes.

## Merged to `main` this session (2026-07-21)

| PR | Summary |
|----|---------|
| #430, #443 | Branch consolidation: autopilot 2026-07-18 batch + Dependabot bumps + actionlint |
| #454 | GA honesty fixes — real trim #444, real QC #445, SFTP probe #447, disabled fake upload #446, hid Perceptual #449 |
| #455 | Swift 6 concurrency audit #451 (ScriptingBridge 60s block deferred) + doc-honesty #453 |
| #456 | Wired BitrateHeatmap / CloudSync / EncodingGraphs to real engine (#448 partial) |
| #439 | Dependabot: actions/checkout → 7.0.1 |
| #457 | SFTP post-encode action → real scp upload (#450); cloud part honestly gated |
| #458 | Split 12k-line ConverterEngineTests monolith into 20 per-domain files (#452) |

Also: **#436 → `alpha`** (actionlint workflow) — merged, minting an `alpha` pre-release.

## Per-task protocol (follow for every task)

1. **Issue** — ensure a GitHub issue exists; **create** it, or **reopen** if it was closed in error.
2. **Implement** — Sonnet/Haiku on a branch → PR → `Build & Test (macOS)` green → merge.
3. **Update the issue** — comment progress and/or close on completion.
4. **Update this HANDOFF.md** — move the task to the log below with its outcome, bump `main @ <sha>`, commit.

## Active program — 2026-07-21 autonomous dev-team cycle

Directive: implement the cloud-upload execution gap (file issue + fix), **#449** perceptual-hash
properly (per original spec), **#448 remainder** (DualDynamicHDR + EncodingStatisticsCollector
pipeline wiring); run a full open+closed GitHub issue review (Fable) → roadmap; loop for new
tweaks/enhancements/features. Bundle work for efficiency.

## Task log (most recent first)

- **[done]** Fable DISCOVER/STRATEGIZE pass (2026-07-22) — enumerated all 419 issues (50 open / 369
  closed); produced the 7-bundle roadmap below. Key finding: ~11 CLOSED issues are **closed-in-error**
  (feature never executes in current code): cloud upload #161–175/#347, YouTube/Vimeo #294,
  DualDynamicHDR #370, GIF/APNG #321, Slate #343, metadata-tag write #320, comparison #329,
  CSV #363, dashboard stats #284, QC #344.

## Roadmap / next steps — 7 bundles (execute in order; each = its own issue(s) + PR + CI + issue-update + handoff-update)

- **Bundle 1 — Cloud-upload execution layer** (committed). Shared `CloudUploadExecutor` (URLSession
  upload, real status/retry/progress); wire Dropbox/GDrive/OneDrive (token-paste v1), YouTube/Vimeo
  (#446), S3 SigV4 signer, `PostEncodeActions.uploadCloud` (#450). NEW umbrella issue. **1f full OAuth
  PKCE = HUMAN-BLOCKED** (needs user OAuth client IDs) — do token-paste v1 only.
- **Bundle 2 — #449 perceptual hash** (committed). New `PerceptualHasher` (AVAssetImageGenerator frame
  sample → 32×32 gray → DCT → 64-bit pHash → Hamming grouping); un-hide the Perceptual option. CI-testable.
- **Bundle 3 — #448 remainder** (committed). 3a DualDynamicHDR executor (dovi_tool/hdr10plus_tool via
  existing runAsync); 3b wire `EncodingStatisticsCollector` into `AppViewModel` queue runner (#284);
  3c CSV export (#363); 3d AnimatedImage real execution (#321).
- **Bundle 4 — Placeholder sweep round 3.** Slate (#343), MetadataTag write (#320), Comparison (#329),
  PluginManager handoff (spot-check first). SmartCrop/MediaBrowser exposure done as part of roadmap
  item #1 (2026-07-28, see below) — their nav entries are live and `MediaBrowserView`'s import path
  is real; remaining Bundle 4 items are still open.
- **Bundle 5 — QC residual detectors (#445).** levelCompliance (reuse ebur128), corruptFrames (ffmpeg
  null decode scan), formatConformance (ffprobe vs spec); audioSync stays gated on #421/#422.
- **Bundle 6 — Test coverage + CI.** Tests for #450 SFTP code, stats store, pHash, HDR executor; #437 actionlint.
- **Bundle 7 — Issue hygiene (continuous).** Close #447 (fix merged); evidence-comment + reopen the
  closed-in-error set as each bundle adopts it; backfill labels/milestones on #444–#453; refresh docs.

**Human blockers (do NOT schedule):** OAuth client IDs (1f), real cloud/YouTube accounts + dovi/hdr10plus
media for E2E (rc soak), G-015 SHA-pin timing, gate-ledger #419–#427, release cut G-010/G-013.

## Standing tasks note

- Added **standing task #14 — monitor GitHub PR security checks** (CodeQL/code-scanning, Dependency Review,
  secret scanning, `security-check` pin-hygiene, OpenSSF Scorecard) to `.claude/standing_tasks.md`. Applies to
  every PR, every session: a green macOS build is necessary but not sufficient — security checks must pass too.

## Current work-in-flight

- **[done 2026-07-22]** Bundle 1 core (#459 / #450) — cloud-upload execution: `CloudUploadExecutor`
  (real URLSession upload, 2xx-only, retry/backoff, byte progress, OneDrive chunked session) +
  Dropbox/GDrive/OneDrive real upload + `PostEncodeActions.uploadCloud` + 21 URLProtocol-mock tests.
  **PR #460 merged (`a902cb6`).**
- **[done 2026-07-22]** Bundle 1b (#459) — **S3 SigV4** signer (`AWSV4Signer`, AWS test-vector-verified) +
  real signed S3 PUT via `CloudUploadExecutor`. **PR #463 merged (`4af2bae`).** Cloud remaining: YouTube/Vimeo
  (OAuth-blocked, #446), S3 multipart >5 GiB TODO.
- **[done 2026-07-22]** Bundle 2 (#449) — perceptual hash: `PerceptualHasher` + un-hid Perceptual + 24 tests.
  **PR #461 merged.** #449 closed.
- **[PR #462 — CI re-running on fix `e4ac19d`]** Bundle 3 (#448 remainder) — DualDynamicHDR executor (#370),
  `EncodingStatisticsCollector` pipeline (#284), CSV export (#363), AnimatedImage (#321). Closes those 4 on merge.
- **[done 2026-07-28]** Roadmap item #3 — statistics unification (#284, #363), on `wip/alpha-consolidation`.
  `EncodingStatisticsStore` (the real per-job pipeline fed from `AppViewModel.startQueue()`) is now the ONE
  source of truth for both the Dashboard and the CSV/JSON export view — no more parallel, always-zero
  `StatisticsTracker` singleton. Changes:
  - `EncodingStatistics` gained three optional fields (`profileName`, `containerFormat`, `succeeded`;
    `nil` = legacy, treated as success) plus matching CSV columns; `EncodingStatisticsCollector` gained
    `markFailed()` so the failure path (previously statistics-silent) now persists too.
  - `EncodingStatisticsStore.exportAsJSON`/`exportAsCSV` gained optional `startDate`/`endDate` filtering.
  - `EncodingStats.init(aggregating:)` (in `AggregateStatistics.swift`) derives Dashboard aggregates from
    `EncodingStatisticsStore.allStatistics` on demand — replacing `StatisticsTracker` entirely (**deleted**,
    it persisted its own `statistics.json` but its only write path, `recordEncode`, had zero callers, so the
    Dashboard always read zeros).
  - `DashboardView` and `StatisticsExportView` now both read live from `EncodingStatisticsStore`.
    `StatisticsExportView` no longer builds `EncodingStats()`/`history: []` inline and reports fake export
    success — it writes the store's real CSV/JSON bytes. Its column-picker UI was removed (the store's
    export always emits the full real record) along with its unused `AppViewModel` environment dependency.
  - `Sources/ConverterEngine/Utilities/StatisticsExporter.swift` (`StatisticsExporter` + `ExportColumn`)
    **deleted** — sole consumer was `StatisticsExportView`, zero test references.
    `ETAPredictor`/`EncodeHistoryEntry` (separate file, separate concern) kept as-is, tracked by #470.
  - New/extended tests: `EncodingStatsAggregationTests.swift` (new), `EncodingStatisticsStoreTests.swift`
    (`markFailed`/`markComplete`, new-field round trip, legacy-decode pin), `EncodingStatisticsCSVExportTests.swift`
    (date-window CSV/JSON export). No data migration needed — `statistics.json` could only ever have been
    written by the zero-caller `recordEncode`, so there was nothing real to migrate.
- **[done 2026-07-28]** Roadmap item #1 — expose the safe orphaned views, on `wip/alpha-consolidation`
  (re #448, re #363, re #284, re #348). 16 fully-implemented views had no navigation entry; 6 stay
  hidden because their backends are fabricated/dead (tracked separately in #355, #343, #329, #467,
  #468, #469 — `APIServerView`, `MetadataEditorView`, `SlateGeneratorView`, `ComparisonView`,
  `ResumableJobsView`, `ConditionalRulesView` — **no enum cases / nav entries added for these**). The
  other 10 are now reachable:
  - **7 new sidebar destinations** (`NavigationItem` cases in `AppViewModel.swift` + `ContentView`
    detail-switch arms, both exhaustive switches updated): Media Browser, Encoding Graphs, Statistics
    Export, Dual Dynamic HDR, Smart Crop, Background Removal, Voice Isolation.
  - **Sidebar restructure** (`SidebarView.swift`): Workflow gains Media Browser; Monitor gains
    Encoding Graphs + Statistics Export; Tools gains Dual Dynamic HDR; new **"Images & Audio"**
    section holds Images, Animated Image, Vector Conversion, ProRes to Vector, Smart Crop, Background
    Removal, Voice Isolation (moved Images/Animated Image out of Tools). **Pre-existing bug fixed**:
    `vectorConversion` and `proresVector` already had enum cases + a `ContentView` switch arm but
    appeared in NO sidebar section — unreachable via the UI despite being fully wired. Now live in
    Images & Audio.
  - **2 embedded (non-sidebar) exposures** in `OutputSettingsView.swift` — these take init params so
    aren't sidebar destinations: `ProfileSuggestionView` banner inside "Encoding Profile"
    (`.id(file.id)` resets its `@State` suggestions when the selected file changes), and a
    `QualityPreviewView` sheet behind a new "Quality Preview..." button next to "Preview FFmpeg
    Command...".
  - **`MediaBrowserView.importSelectedFiles()` fixed** — was a documented no-op ("Queue integration
    would be handled by the parent"). Now calls `viewModel.importFiles(urls)` +
    `viewModel.selectedNavItem = .source`, mirroring `ContentView`'s proven drop-import path. Required
    before exposing the view at all, per plan — otherwise it'd be another fabricated surface.
  - **Part E shipped (#348), not skipped.** `EmailSettingsView` was orphaned AND its
    `emailOnComplete`/`emailOnFailure` toggles had zero consumers, so both had to land together
    (ship-both-or-neither). Added Settings → Services → "Email" tab; extracted
    `EmailSettingsView.loadSMTPConfig() -> SMTPConfig?` (and made `loadPasswordFromKeychain()`
    `static`) so it's callable without a live view instance; wired
    `AppViewModel.sendCompletionEmail(...)` into both the encode-success and encode-failure branches
    of `startQueue()`, next to the existing `sendNotification` calls, gated on
    `UserDefaults.standard.bool(forKey: "emailOnComplete"/"emailOnFailure")`. The blocking `curl`
    `Process` transport — the same one already proven inside
    `EmailSettingsView.sendTestEmail()` — runs in `Task.detached`, capturing only the prepared
    `Sendable` `String`/`[String]` values (subject/body/curl-args), never a `@MainActor self`.
  - Compile-uncertain spots for CI to confirm (no local macOS build available): the
    `ProfileSuggestionView(sourceFile:profiles:onSelectProfile:)` / `QualityPreviewView(sourceFile:
    profile:)` memberwise-init argument labels — verified by inspection against their `let`
    properties and cross-checked against the same `@Environment` + `let`-params pattern already
    proven by `StreamMetadataEditorView(mediaFile:)` elsewhere in `OutputSettingsView.swift`; and the
    `Task.detached` `Sendable`-capture shape in `sendCompletionEmail`.
- **[done 2026-07-28]** Roadmap item #2 — chunked/resumable Dropbox + Google Drive uploads (re #459),
  on `wip/alpha-consolidation`. `CloudUploadExecutor.uploadToCloudStorage` previously sent Dropbox and
  Google Drive as ONE whole-file request — Dropbox's `/2/files/upload` caps at 150 MB
  (`DropboxUploader.singleUploadMaxBytes`) and Google Drive's `uploadType=media` is documented for
  small files only (`GoogleDriveUploader.simpleUploadMaxBytes`, 5 MB) — so real media output routinely
  failed the upload feature outright. Mirrors the existing OneDrive `uploadInSessionChunks` shape
  (create/start request → `FileHandle` chunk loop → per-chunk `executeWithRetry` → final-response
  parse), reusing the previously-unused `DropboxUploader`/`GoogleDriveUploader` URL and size/chunk-size
  constants in `CloudProviders.swift`. Changes:
  - New builders in `CloudStorageUploader.swift` — `buildDropboxSessionStartRequest`,
    `buildDropboxSessionAppendRequest`, `buildDropboxSessionFinishRequest`,
    `buildGoogleDriveResumableInitRequest` — all via `JSONSerialization`, NOT the existing unused
    `DropboxUploader.buildSessionStartHeaders`/`buildSessionFinishHeaders` or
    `GoogleDriveUploader.buildUploadMetadata` (left untouched as existing public API): those build JSON
    by string interpolation (breaks on a filename containing a `"`), and `buildSessionFinishHeaders`
    hardcoded `"mode":"add"` where the simple upload path uses `"overwrite"` — the new
    `buildDropboxSessionFinishRequest` matches the simple path's `"overwrite"`.
  - `CloudUploadExecutor.executeWithRetry` gained a private `additionalSuccessStatusCodes: Set<Int> = []`
    parameter (existing call sites unaffected) — required because Google Drive's resumable-upload
    protocol answers **`308 Resume Incomplete`** for every non-final chunk as its real, documented
    success response, not `2xx`. New `uploadInDropboxSessionChunks(fileURL:config:chunkSize:progress:)`
    and `uploadInGoogleDriveResumableChunks(fileURL:initiateRequest:chunkSize:progress:)` on
    `CloudUploadExecutor`; `uploadToCloudStorage` now routes Dropbox above 150 MB and Google Drive above
    5 MB into these, mirroring the existing OneDrive (4 MB) branch — both existing callers
    (`CloudStorageView.performUpload`, `PostEncodeActions.uploadViaCloud`) needed no changes since
    routing is centralised there.
  - The 308-accept-set is scoped to non-final chunks ONLY: the final chunk always uses the plain
    `executeWithRetry` (no additional success codes), so a 308 on the final chunk — meaning the server
    is still missing bytes — fails honestly as `.httpError(308, …)` rather than ever being read as
    success.
  - **Known limitation (Dropbox), same semantics already accepted for the OneDrive path**: a chunk-level
    retry re-sends the identical cursor offset (the append request is built once, before `offset`
    advances, and reused verbatim across retry attempts). If the original request actually succeeded
    server-side and only its response was lost, the retried append lands at an offset the server has
    already moved past, and Dropbox answers `409 incorrect_offset` — surfaced honestly as
    `.httpError(409, …)`, never silently absorbed or retried into a fabricated success. A caller hitting
    this must restart the whole upload.
  - New tests: `Tests/ConverterEngineTests/CloudChunkedUploadTests.swift` (9 scenarios — small-file
    routing for both providers, large-file session/resumable routing, session-start / initiate
    failure-fast paths, append-offset and finish-cursor correctness, mid-chunk-retry same-offset
    pinning, the 308 non-final-vs-final accept-set boundary) plus 4 new request-builder tests appended
    to `CloudUploadExecutorTests.swift`'s existing "(d) Provider request-builder correctness" section.
  - Compile-uncertain for CI (no local macOS build available): the nested-heterogeneous-dictionary
    `Dropbox-API-Arg` JSON bodies (`cursor`/`commit`) are built as separate, explicitly-typed
    `[String: Any]` `let`s before assembly, specifically to sidestep Swift's "heterogeneous collection
    literal could only be inferred to '[String : Any]'" diagnostic on an inline nested literal; and the
    `HTTPURLResponse.value(forHTTPHeaderField:)` read of the Google Drive initiate response's `Location`
    header, which depends on `MockURLProtocol`/`URLSession` correctly propagating response headers
    through the mocked `URLProtocol` loading system in the new tests.
  - Next queued: roadmap item #9 (`PostEncodeActionChain` tests), then item #10 (ScriptingBridge 60s
    semaphore, deferred from #451).
- **[done 2026-07-28]** Roadmap items #9, #10, #8 (engine-layer batch), on `wip/alpha-consolidation`.
  **Numbering note**: the "item #10" description in the previous log entry above (ScriptingBridge 60s
  semaphore) turned out to be superseded — the actual task brief for #10 in this batch was "wire or
  descope FTP/rsync (re #174)"; the ScriptingBridge semaphore item is not yet scheduled (added to the
  queue below).
  - **#9 — `PostEncodeActionChain` test coverage (re #450).** Was at ZERO tests. New
    `Tests/ConverterEngineTests/PostEncodeActionsTests.swift`: `ActionError.errorDescription` for all 4
    cases; missing-`sftpProfileID`/`cloudProfileID` config resolution throws a real
    `ActionError.missingConfig` through the public `execute(inputURL:outputURL:success:)` API (never
    silently succeeds); chain ordering/skip/error-aggregation (disabled actions skipped, `runOnFailure`
    respected on both success and failure, first error surfaces even when a later action also fails);
    `substituteVariables` placeholder substitution; `PostEncodeActionType`/`PostEncodeAction`/
    `PostEncodeActionChain` Codable round trips. **One seam added, `@testable`-only**:
    `PostEncodeActionChain.execute(inputURL:outputURL:success:actionExecutor:)` — an internal overload
    the public 3-arg `execute` always calls with `actionExecutor: nil`, so production behaviour is
    unchanged; it lets tests inject a fake per-action dispatch instead of spawning real
    `scp`/`curl`/`osascript`/`zsh` processes or hitting the network. Also bumped
    `substituteVariables(in:inputURL:outputURL:profile:status:)` from `private` to internal (still
    unreachable outside the module without `@testable`) so its pure string-substitution logic has a
    direct test instead of only being observable through a real shell/notification process.
    **Correction to the task brief**: `execute`'s real, documented behaviour is "continue past a failing
    action, surface the first error" — NOT abort-on-first-failure as the brief assumed. Tests pin the
    real behaviour (`test_execute_runsEveryEnabledActionInOrder_andDoesNotAbortOnFailure`) rather than
    asserting the assumed one; production runtime behaviour was left untouched (changing it wasn't asked
    for and the brief itself says "WITHOUT changing public behaviour").
  - **#10 — FTP/rsync (re #174): DESCOPED, not wired.** `SFTPUploader.buildFTPUploadArguments`/
    `writeFTPCredentialsConfig`/`buildRsyncArguments` are real, correct, already-tested argument
    builders that are simply never called from any execution path — only `scp` (via
    `upload(localPath:config:)`) runs. Evaluated wiring them in: `SFTPServerConfig` (the one config type
    `PostEncodeActionChain`/`SFTPSettingsView`/`SFTPProfileStore` all share) has **no transfer-protocol
    selector field**, so dispatching between scp/rsync/ftp per profile requires adding one — which
    ripples into both the `Codable` migration story (mirroring the `id` field's backward-compatible
    decode) and `SFTPSettingsView`'s form, neither of which this no-local-build session could validate
    end to end. `FTPServerConfig` compounds this: it's a structurally different type with no `id`, no
    profile-store persistence, and no UI path to ever construct one. Chose the honest minimum per the
    task brief's own explicit fallback: added a type-level "Execution status" doc comment on
    `SFTPUploader` plus a `// TODO(#174)` on each of the three unwired builders, so nothing looks
    functional that isn't. Added 2 new tests strengthening `buildRsyncArguments`' auth-branch coverage
    (`.keyFile` escaping, `.password` `BatchMode=no`) in
    `ConverterEngineTests+CloudAndMetadataLookup.swift`, next to the pre-existing scp/rsync/FTP
    argument-building tests (which already covered the basics).
  - **#8 — two more QC detectors (re #445).** Implemented `corruptFrames` and `levelCompliance` for
    real in `QualityChecker.swift`, keeping its pure/process-free architecture: new
    `buildCorruptFrameDetectionArgs(inputPath:)` (`ffmpeg -v error -i <input> -f null -`) +
    `parseCorruptFrameOutput(_:)` (one `.failed` `QCResult` per non-blank `-v error` stderr line, a
    single `.passed` result when stderr is empty); new `buildLevelComplianceArgs(inputPath:)` (delegates
    to the existing, tested `LoudnessReporter.buildAnalysisArguments(inputPath:)` byte-for-byte) +
    `parseLevelComplianceOutput(_:standard:)` (thin adapter over the existing, tested
    `LoudnessReporter.parseAnalysisOutput`/`checkCompliance` — real EBU R128/ebur128 pass/fail, never a
    second loudness-math implementation) + a `normalizationStandard(forLoudnessStandard:)` helper
    mapping `QCProfile.loudnessStandard`'s free-form label to a `NormalizationStandard` (defaults to
    `.ebur128`). `runAllChecks` now skips both checks (added to the same "requires FFmpeg, resolved by
    the caller" `continue` case as `blackFrames`/`silenceDetection`) instead of returning
    `.notImplemented` for them. Wired real execution into `QualityCheckView.runQualityChecks()` with two
    new blocks mirroring the existing black-frame/silence `FFmpegProcessController` flow exactly (same
    cancellation handling, same error-message chaining). `audioSync` and `formatConformance` stay
    `.notImplemented` — `audioSync` is genuinely gated on #421/#422. New
    `Tests/ConverterEngineTests/QualityCheckerTests.swift` (QualityChecker had zero prior coverage):
    arg-builder assertions, parser tests against representative `-v error` decode-error lines
    (hand-written — no `ffmpeg`/corrupt-fixture available in this environment to capture a real one) and
    real `loudnorm` JSON shapes (compliant/non-compliant/unparsable), the
    `normalizationStandard(forLoudnessStandard:)` mapping, and `runAllChecks` regression guards for both
    the newly-real checks (now omitted, not stubbed) and the still-stub checks (still `.notImplemented`).
  - Compile-uncertain for CI (no local macOS build available): the `PostEncodeActionChain` seam overload
    resolves correctly against the public 3-arg `execute` (labelled-parameter overload, verified by
    inspection, not by compiling); `QualityCheckView`'s two new `FFmpegProcessController` blocks follow
    the exact structural shape of the pre-existing black-frame/silence blocks in the same function, so
    risk is low but unverified locally.
  - Next queued: #6 (APIServer honesty), #11 (email-on-completion — already wired per the #348 log entry
    above, needs verification not implementation), #7 (S3 UI surface + multipart >5 GiB), #15, #13, #14,
    #16, #12 (none of these have been scoped/read yet this session), plus the still-unscheduled
    ScriptingBridge 60s semaphore fix deferred from #451 (previously mislabelled "#10" above).
- **[done 2026-07-28]** Roadmap items #6, #11, #15, on `wip/alpha-consolidation`.

  **#6 — Make `APIServer` honest (re #355).** Added `EncodingEngine` initialiser injection
  (`APIServer(port:apiKey:engine:)`, default `EncodingEngine()` so `APIServerView` keeps compiling) and a
  `startTime: Date?` captured in `start()` (cleared in `stop()`). Per-endpoint outcome:
  | Endpoint | Before | Now | Notes |
  |---|---|---|---|
  | `GET /profiles` | 4 hardcoded fake profiles | **REAL** — `engine.profileStore.allProfiles()` (built-in + user-created) | New lock-protected `EncodingProfileStore.allProfiles()`; existing unsynchronised `profiles` property read left alone for its `@MainActor`-only UI call sites |
  | `GET /status` | hardcoded `"1.0.0"` / `"active"` | **REAL** — `AppInfo.Version.displayString` / `uptimeSeconds` computed from `startTime` | |
  | `GET /queue` | always empty | **REAL** — `engine.queue.jobsSnapshot()` | New lock-protected `EncodingQueue.jobsSnapshot()`, same rationale as `allProfiles()` |
  | `POST /encode` | invented `jobId`, never enqueued | **REAL** — validates input exists + profile resolves, then genuinely calls `engine.queue.addJob(_:)`; `jobId` in the response is the real job's UUID | Honestly disclosed via a `note` field: encoding only starts once something drives the queue (today only `AppViewModel.startQueue()` on `@MainActor`, which `ConverterEngine` has no reference to and must not reach into) — this mirrors the GUI's own "Add to Queue" vs "Start Queue" split, not a new limitation |
  | `POST /probe` | `FileManager.fileExists()` only | **REAL** — calls `try await engine.probe(url:)` (real FFprobe) | Deliberately does **not** call `engine.configure()` itself: `EncodingEngine.ffmpegInfo`/`ffprobeInfo` are unsynchronised `var`s that `configure()` writes to, and `AppViewModel.startQueue()` already calls `configure()` on `@MainActor` — having `APIServer` call it too from its own background dispatch queue would be a genuine concurrent-write race, exactly the cross-actor risk this task said not to take on blind. If the engine hasn't been configured by whoever owns it, this returns `503` with the real error instead of guessing. No endpoint needed a `501` — all five got a real (or honestly-failing) implementation |

  `routeRequest`/`handleConnection` became `async` (bridged via a plain `Task` in the `NWConnection` receive
  callback, not a blocking semaphore — see the #13 ScriptingBridge item below for why that pattern is
  avoided) solely so `POST /probe` can `await` the real probe. The five handler methods + `routeRequest`
  moved from `private` to `internal` (still not `public`) purely so `@testable import` can reach them for
  tests, mirroring the `PostEncodeActionChain.actionExecutor` precedent. New
  `Tests/ConverterEngineTests/APIServerTests.swift` (20 tests): JSON-shape assertions for all five
  endpoints against a real injected `EncodingEngine`, `routeRequest` auth/routing (401/404/204), and
  regression pins against the old fake values (`"1.0.0"`, the four fake profile names, always-empty queue).
  Deliberately never calls `profileStore.addProfile`/`deleteProfile` in tests — `EncodingEngine` has no
  injection point for a temp `EncodingProfileStore` directory, so that would persist a write to the real
  test-runner's `~/Library/Application Support/MeedyaConverter/Profiles/`; read-only assertions against the
  always-present built-ins are used instead. `APIServerView`/`APIServerViewModel` gained a matching
  `engine: EncodingEngine = EncodingEngine()` init parameter (still unused by anything — the view has no
  navigation entry) so a future caller can hand it `AppViewModel.engine` and get the real, shared
  profiles/queue instead of a disconnected standalone engine. **`APIServerView` is now honest end-to-end
  and could be exposed in navigation — not done here, per the task brief, tracked separately.**

  **#11 — Verify the email-on-completion wiring (re #348): already correct, nothing changed.** Read
  `AppViewModel.sendCompletionEmail`/`EmailSettingsView` end-to-end: `emailOnComplete`/`emailOnFailure`
  are read via `UserDefaults.standard.bool(forKey:)` using the exact same string keys
  `EmailSettingsView`'s `@AppStorage("emailOnComplete")`/`@AppStorage("emailOnFailure")` toggles write;
  `loadSMTPConfig()` reads the same `UserDefaults` keys as its own `@AppStorage` SMTP fields
  (`emailSMTPHost`/`Port`/`Username`/`UseTLS`/`emailFromAddress`/`emailToAddresses`), plus the password via
  `loadPasswordFromKeychain()`, which shares the exact `keychainService`
  (`"Ltd.MWBMpartners.MeedyaConverter.smtp"`) / `keychainAccount` (`"smtpPassword"`) constants
  `savePasswordToKeychain()` writes with — one Keychain item, read and written by the same two `static`
  constants. A missing/incomplete config makes `loadSMTPConfig()` return `nil`, which
  `sendCompletionEmail` guards on and returns early: no crash, no fabricated "sent" message (nothing logs
  or displays a success indicator for the email path at all — silent-but-safe, matching
  `sendNotification`'s existing fire-and-forget style; the `curl` `Process` failure path is caught and
  dropped the same way). No mismatch found. Added
  `Tests/ConverterEngineTests/EmailNotifierTests.swift` (13 tests, `import ConverterEngine`, no
  `@testable` — the tested surface is fully `public`) covering the parts of the feature that actually live
  in `ConverterEngine` and are therefore testable: MIME header/boundary construction, `curl` argument
  construction (scheme selection, one `--mail-rcpt` per recipient, credentials, stdin-piped upload — a
  regression guard confirms the raw email body is never interpolated into argv), and
  `formatJobCompletionEmail`'s HTML (including that file names / error messages are HTML-escaped). The
  `AppViewModel`/`EmailSettingsView` wiring itself has no reachable test target — `MeedyaConvertTests`
  depends on `ConverterEngine`, not the `MeedyaConverter` executable target, because Swift forbids
  importing a module containing `@main` into a test target — so that half was verified by inspection only.

  **#15 — `MediaEncryption`: DELETED (re #451-style cleanup), not streamed.** Grepped for every symbol it
  defines (`MediaEncryption`, `EncryptionConfig`, `EncryptionMode`, `EncryptionError`, `encryptFile`,
  `buildHLSEncryptionArguments`, `buildKeyInfoFile`) across `Sources/` and `Tests/`: zero references
  anywhere outside the file itself, confirming the task brief's "ZERO callers" claim. It's also a genuine
  duplicate: `Sources/ConverterEngine/FFmpeg/StreamingEnhancements.swift` already has a separate, unrelated
  `HLSEncryption` type covering the same ground (AES-128 key generation, `-hls_key_info_file` key-info-file
  construction) — also with no production call site, but at least exercised by one existing test
  (`HLSEncryption.generateKey()` in `ConverterEngineTests+Manifest.swift`), unlike `MediaEncryption` which
  had none. Deleted `Sources/ConverterEngine/Utilities/MediaEncryption.swift` outright rather than
  rewriting its `Data(contentsOf:)` full-file-read to stream — there is nothing calling it to preserve,
  and `HLSEncryption` is the type any future HLS-encryption work should extend instead of resurrecting a
  second, parallel implementation. `EncryptionError` had no naming collision with `HLSEncryptionError`, so
  no follow-on renames were needed elsewhere.

  **Compile-uncertain for CI (no local macOS build available):** `routeRequest`/`handleProbe` becoming
  `async` and being driven from a plain (non-detached) `Task` inside the `NWConnection.receive` completion
  closure — this assumes `NWConnection` is `Sendable`-compatible for capture in a `@Sendable` `Task`
  closure in this SDK, which the pre-existing code already implied by capturing `connection` in the
  nested `.contentProcessed` completion closure, but wasn't independently verified by compiling;
  `APIServerTests.test_handleStatus_afterStart_reportsRealPositiveUptime` binds a real loopback
  `NWListener` on port 58484 during `swift test --parallel` — the first test in the suite to open an
  actual socket (existing tests only construct/mock, never bind); and the `EncodingProfile`/`AudioCodec`/
  `VideoCodec`/`ContainerFormat` rawValue literals asserted in `APIServerTests` (`"h264"`, `"aac"`,
  `"mp4"`) and profile names (`"Web Standard"`, `"ProRes HQ"`) were checked by reading
  `EncodingProfile.swift`/`AudioCodec.swift`/`VideoCodec.swift`/`ContainerFormat.swift` directly, not by
  compiling.
  - Next queued: #7 (S3 UI surface + multipart >5 GiB), #13 (ScriptingBridge 60s semaphore — needs an
    `NSScriptCommand` refactor), #14 (concurrency audit remainder), #16 (cloud-provider triage — needs
    human input), #12 (accessibility pass).
- **[done 2026-07-28]** Roadmap items #7, #14, on `wip/alpha-consolidation`.

  **#7 — S3 real user surface + multipart (re #459, re #162).** Before this, `AWSV4Signer` +
  `S3Uploader.buildSignedUploadRequest` + `CloudUploadExecutor.uploadToS3` were unit-tested but had
  ZERO production callers — `CloudStorageProvider` had no `.s3` case, so a user could never actually
  pick S3 in the UI. Now user-reachable end to end:
  - `CloudStorageProvider` gained a `.s3` case, handled in every exhaustive switch it touches
    (`CloudStorageUploader.authURL` — now returns `URL?`, `nil` for `.s3`, rather than
    force-unwrapping; `CloudStorageProfileStore.apiKeyProvider(for:)` → `.awsS3`;
    `CloudUploadExecutor.uploadToCloudStorage`; `CloudStorageView`'s `providerIcon`/
    `providerDisplayName`). New `CloudStorageProvider.usesOAuth` flag (`false` only for `.s3`) gates
    which credential form `CloudStorageView.authSection` shows.
  - **Config/credential path** — `CloudStorageConfig` gained `secretAccessKey`/`bucket`/`region`/
    `endpoint` (all optional, `Codable`-backward-compatible with every pre-existing saved
    Dropbox/OneDrive/Google-Drive profile on disk — confirmed by a legacy-JSON decode test).
    `accessToken` does double duty as the AWS Access Key ID for `.s3` (documented on the field) so the
    existing "secret lives in `@State`, redacted before `UserDefaults`, restored from the Keychain"
    machinery needed no new chokepoint. Secrets go through the SAME `APIKeyManager` (provider
    `.awsS3`) every other provider already uses — access key ID → `StoredAPIKey.apiKey`, secret
    access key → `StoredAPIKey.secretKey` (the exact pair `S3Uploader.loadCredential` already read) —
    never `UserDefaults`, never `PostEncodeAction.config` (only the `cloudProfileID` reference, exactly
    like every other provider). `CloudStorageView` gets an S3-specific "AWS Credentials" section
    (Access Key ID / Secret Access Key (`SecureField`) / Bucket / Region / optional custom Endpoint)
    in place of the OAuth form.
  - **Multipart status: fully implemented, not stubbed**, gated behind `S3Uploader
    .shouldUseMultipart(fileSize:)`'s existing 100 MB threshold (which also covers the mandatory
    >5 GiB case, since 5 GiB > 100 MB). New `CloudUploadExecutor.uploadS3Multipart` drives a real
    `CreateMultipartUpload` → per-part signed `UploadPart` PUTs (each independently signed via
    `AWSV4Signer`, mirroring `uploadInDropboxSessionChunks`/`uploadInGoogleDriveResumableChunks`) →
    `CompleteMultipartUpload` with a real XML body (`PartNumber`+`ETag` per part, built by new
    `S3Uploader.buildCompleteMultipartXML`) → `AbortMultipartUpload` as best-effort cleanup on ANY
    failure once a real `UploadId` exists — the abort's own outcome never masks the original error
    (verified by a dedicated test). New `S3XMLElementExtractor` (a minimal `XMLParser`-based helper,
    not regex/substring matching) parses `UploadId`/`Location`/`ETag` out of S3's XML responses.
  - **Tests** (`Tests/ConverterEngineTests/S3MultipartUploadTests.swift`, new file, ~20 tests, plus 6
    more appended to `ConverterEngineTests+CloudAndMetadataLookup.swift`): small-file → single signed
    PUT (exactly one request); missing-credential-fields → throws before sending anything; large file
    (sparse-file trick) → routes to `CreateMultipartUpload` (fails fast on a mocked 403, no parts
    attempted); full multipart sequence with correct sequential `partNumber`s + shared `uploadId` and
    a byte-exact `CompleteMultipartUpload` XML body built from the real per-part `ETag` response
    headers; mid-part failure → `AbortMultipartUpload` called with the right `uploadId`, original
    `.httpError` never masked; `CreateMultipartUpload` failure → no abort attempted (no real
    `UploadId` to abort); every new request builder's method/URL/query/headers and
    nil-on-incomplete-credential behaviour; `CloudStorageProvider`/`CloudStorageProfileStore`/
    `CloudStorageConfig` unit tests (`usesOAuth`, `authURL` nil, `apiKeyProvider` mapping, `Codable`
    round trip, legacy-JSON backward compatibility).
  - Compile-uncertain for CI (no local macOS build available): the `XMLParserDelegate` method
    signatures on `S3XMLElementExtractor.ElementTextCollector` (verified by inspection against
    Foundation's documented overlay signatures, not by compiling); the `AWSV4Signer
    .canonicalQueryString(queryItems:)` reuse for both the literal request `URL` and the SigV4
    signature in the four new multipart request builders (same pattern `buildSignedUploadRequest`
    already uses for `canonicalURI(path:)`, but not independently compiled here); and
    `CloudStorageView`'s new `authSection`/credentials-form `@ViewBuilder` branching compiling as a
    single `some View` return type across the `if selectedProvider.usesOAuth { ... } else { ... }`
    split.

  **#14 — Swift 6 concurrency audit remainder (re #451).** Re-checked every `Task.detached`/
  `nonisolated(unsafe)` site in `BurnSettingsView`, `QualityMetricsView`, `TeamProfileView`,
  `CloudSyncView`, and `PostEncodeActions` against the genuine bug class (a `@MainActor` class `self`
  captured into `Task.detached` and mutated back via `MainActor.run`). Per-file finding — **all five
  were already correct-as-is; zero behaviour/scheduling changes made**, only doc comments recording
  the re-audit (so a future pass doesn't have to redo this analysis):

  | File | Sites checked | Verdict | Why |
  |---|---|---|---|
  | `BurnSettingsView` | `detectDrives()`, `startBurn()`, `eraseDisc()`, `ejectDisc()` | correct-as-is | First 3 already fixed by the #451 pass (`9deee21`): plain `Task {}` inherits the `View`'s main-actor isolation, inner `Task.detached` is `Sendable`-only capture/return, never `self`. `ejectDisc()` is a bare `Task.detached` capturing no `self`/state at all. |
  | `QualityMetricsView` (`QualityMetricsViewModel`, `@MainActor` class) | `runAnalysis()`'s 2 `Task.detached` blocks; `nonisolated(unsafe) analysisTask`/`currentController` | correct-as-is | `runAnalysis()` uses plain `Task { [weak self] }` (already fixed for #434, `2d8cde3`); only `locateFFmpeg()`/`probeLibvmafAvailable` are detached, `Sendable`-only. The `nonisolated(unsafe)` vars are the documented deinit-cancellation exception (mirrors `StoreManager.transactionListenerTask`), not the bug class. |
  | `TeamProfileView` | `pushProfiles()`, `pullProfiles()` | correct-as-is | Already fixed by #451 (`5f9f2d6`) — identical shape to `BurnSettingsView`. |
  | `CloudSyncView` | `performUpload()`, `performDownload()` | correct-as-is | `async` methods invoked via plain `Task { await ... }` from the view (main-actor isolated); only `CloudProfileSync`'s blocking I/O is detached, `Sendable`-only capture. |
  | `PostEncodeActions` (`PostEncodeActionChain`, a plain `Sendable` struct — not a `@MainActor` class) | `uploadViaSFTP`'s and `sendMacOSNotification`'s `Task.detached` | correct-as-is | No main-actor state to race on in the first place; `uploadViaSFTP`'s detached block is `Sendable`-only capture/return, `sendMacOSNotification`'s is bare fire-and-forget with no capture at all. |

  Out of scope per the task brief: the `ScriptingBridge` 60s semaphore (needs an `NSScriptCommand`
  refactor — tracked separately as roadmap #13).

  - Next queued: #13 (`ScriptingBridge` `NSScriptCommand` refactor), #16 (cloud-provider triage — needs
    human input), #12 (accessibility pass), then the closing phase (issue sweep, docs/OpenAPI refresh,
    new proposals).
- **[done 2026-07-28]** Completeness-audit cluster — "configured but never executed" (persisted setting,
  zero readers), on `wip/alpha-consolidation`, `899abd7` → `bc7fa4f`. Seven fixes, one commit each, all
  landing in `AppViewModel.startQueue()`/`enqueueSelectedFile()`/`init()` unless noted:
  1. **#279 — scheduled jobs never started.** `scheduler.onJobReady` called `addJob` and logged
     "Scheduled job started" but nothing called `startQueue()`. Now starts the queue if not already
     running; log message reflects which branch actually happened ("started" vs "added to running
     queue").
  2. **#268 — watch folders discarded every detection.** `WatchFolderView`'s `monitor.start(config:) { _
     in /* handled by app coordinator */ }` dropped every file; no coordinator existed. New
     `AppViewModel.enqueueWatchFolderFile(_:config:)` resolves the profile by name (falling back to Web
     Standard with a logged warning — `WatchFolderConfig`'s own default `profileName`, `"webStandard"`,
     doesn't match any built-in profile's display name, so this is the *common* case for a fresh watch
     folder, not an edge case), builds the output path via the existing `FileStabilityChecker.outputPath`
     helper (not `FilenameTemplate` — avoids an extra async probe per detected file; does not honour the
     Source tab's `filenameTemplate`/`overwriteExisting` settings for the same reason), adds the job, and
     starts the queue if needed. The view's callback hops onto the main actor
     (`Task { @MainActor in viewModel.enqueueWatchFolderFile(...) } }`) since `WatchFolderMonitor` fires
     `onNewFile` from its own background `monitorQueue` — same shape `DropHandler.extractURLs`'s
     completion handlers already use elsewhere (`ContentView`'s drop handling). **Still open, found but
     NOT fixed this session**: `WatchFolderConfig.postAction` (`.moveToCompleted`/`.deleteSource`) is
     itself another "configured but never executed" toggle — nothing consumes it after a watch-folder
     encode completes. Not in this session's assigned list; flagging for the backlog.
  3. **#296 — webhooks never fired on real events.** `WebhookSettingsView` persisted `webhookURL` +
     three trigger toggles + presets/custom headers; the only production `WebhookSender.send` call was
     the Test button. Extracted `WebhookSettingsView.loadWebhookConfig()` (static, mirrors
     `EmailSettingsView.loadSMTPConfig()`; the view's own `buildConfig()` now delegates to it — also
     tightens an edge case: the static version explicitly rejects an empty URL string before calling
     `URL(string:)`, which the original `buildConfig()` didn't). New
     `AppViewModel.sendWebhookNotification(...)` wired into the same three points
     `sendCompletionEmail` already covers (per-job success, per-job failure, end-of-queue); queue-finished
     has no single "job" so the summary counts stand in for the job fields and `status` reflects whether
     any job failed. Delivery runs in a plain (non-detached) `Task` — `WebhookSender.send` is already
     non-blocking `async`/`URLSession`, so a slow retry (`WebhookConfig.retryDelaySeconds`) never stalls
     the queue loop; failures are logged, never thrown.
  4. **#348 — queue-finished email never sent.** `EmailSettingsView.emailOnQueueFinished` had no reader
     (its siblings `emailOnComplete`/`emailOnFailure` were already wired). Added the third
     `sendCompletionEmail` call at end-of-queue, same summary-stand-in shape as the webhook leg above.
  5. **#295 / #203 — media-server auto-scan never triggered.** `MediaServerSettingsView.mediaServerAutoScan`
     had no reader. Extracted `MediaServerSettingsView.loadMediaServerConfig()` (static, same
     `loadSMTPConfig()` mirror; `currentConfig` now delegates to it). New
     `AppViewModel.triggerMediaServerAutoScan()` fires the same `MediaServerIntegration.triggerLibraryScan`
     the manual "Trigger Library Scan Now" button uses. Fires from the **per-job success path**, not
     queue-end — the toggle's own label is "Auto-scan after successful encode," and that wording was
     taken literally rather than choosing queue-end for convenience.
  6. **#334 — Recent Files could never populate.** `RecentFilesManager.addRecent(_:)` had exactly one
     caller — `RecentFilesView`'s own re-import action — a circularity that meant the list could never
     grow from a normal import. Added an `AppViewModel`-owned `RecentFilesManager` instance, called from
     `importFiles(_:)` for each successfully probed file. `RecentFilesView` keeps its own separate
     manager instance (unchanged), but both read/write the same on-disk JSON store and the view is torn
     down/recreated (reloading from disk) every time the user navigates to Recent Files, so no shared
     live instance is needed.
  7. **NEW-issue items (no GitHub issue filed yet) — `SettingsView.overwriteExisting` /
     `.deleteSourceAfterEncode`, both persisted, both read by nothing.**
     - `overwriteExisting`: added `FilenameTemplate.resolveOutputURL(..., overwriteExisting:)`, a small
       pure helper (genuinely unit-testable — see below) that delegates to the existing
       `resolveWithCollisionHandling` when `false` (today's auto-rename-on-collision behaviour,
       unchanged) and returns the plain resolved path when `true` (FFmpeg, invoked with `-y` for every
       job already, then overwrites it in place). Wired into `enqueueSelectedFile()`.
     - `deleteSourceAfterEncode`: judged safe to implement (not disabled) with conservative guards — new
       `AppViewModel.deleteSourceFileIfSafe(job:)`, called ONLY from the `.completed` success path in
       `startQueue()` (never reachable from the failure/cancel `catch` branch), additionally requiring
       the output file to exist and be non-empty and to have a different path from the input before
       deleting anything; every outcome (deleted / skipped-why / failed-why) is logged; deletion failures
       are caught, never thrown.
  - **Tests**: `Tests/ConverterEngineTests/FilenameTemplateResolveOutputURLTests.swift` (new, 4 tests) —
    the one piece of pure, public `ConverterEngine` logic this cluster introduced
    (`FilenameTemplate.resolveOutputURL`). Everything else is `AppViewModel`/View wiring in the
    `MeedyaConverter` executable target, which — like `meedya-convert` — cannot be `@testable import`ed
    (Swift forbids importing a module containing `@main` into a test target), so that half was verified
    by inspection only, same constraint every previous audit-cluster entry in this log has hit.
  - **Compile-uncertain for CI (no local macOS build available):** the `@Sendable` closure passed to
    `WatchFolderMonitor.start(config:onNewFile:)` capturing `viewModel` (a `@MainActor`, non-`Sendable`
    class) directly, used only inside a nested `Task { @MainActor in }` — verified by inspection against
    the identical, already-shipped shape `ContentView.swift`'s `DropHandler.extractURLs` completion
    closures use (also `@Sendable ([URL]) -> Void`, also capturing `viewModel` directly), not by
    compiling.
  - **Remaining audit backlog (large items, not touched this session)** — same categories the completeness
    audit that produced this task's brief flagged: #286 parallel encoding, #205 metadata lookup, disc
    ripping tracker, #353 plugins, #278 pipelines (note: `PostEncodeActionsView`/`PostEncodeActionChain`,
    issue #277, is a *separate* "configured but never executed"-shaped post-encode-hooks feature from
    this session's #296 webhook fix — its own `.webhook` action type is explicitly unsupported per
    `PostEncodeActionsTests.swift`; not touched here), #320/#322/#335/#298/#288 build-only views, #302
    AppleScript plist, #331 shortcuts, #281 menu bar, #359/#360 widget, #275 output modes
    (`AppViewModel.outputMode`/`OutputPathResolver` — also unused by `enqueueSelectedFile()`, which still
    resolves output paths via `FilenameTemplate` only; not touched by the `overwriteExisting` fix above),
    #345 team HTTP sync. Also newly noted: `WatchFolderConfig.postAction` (see #268 above).

## Decisions / blockers needing the user

- **#446** VideoUpload real YouTube/Vimeo upload — needs the user to register OAuth apps + supply credentials.
- (others appended as they arise)
