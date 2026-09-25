<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Round 2: FALLBACK review by Claude Fable 5.1 (not Codex), 2026-09-25

**Why a fallback:** Codex was the intended reviewer. It started round 2 at 04:40 and
ran out of usage allowance mid-review ("try again at 9:41 AM"), with no findings. Per
the fallback rule, the same brief was run by **Fable 5.1**, a different model from the
Sonnet/Opus that built and checked the fixes, as a fresh read-only agent with no
memory of building them. **Codex still owes round 2** over the same range, plus
whatever fixes this review triggers.

**Range:** `codex-r2-base..codex-r2-end` = `cd6b5a4..d3553cc`, the round-1 fixes. The
brief is `codex-2026-09-25-r2-brief.txt`, lightly adapted for a non-Codex reviewer.

**Each finding was checked against the code by the orchestrator (Opus) before any
fix.** Findings 1-4 were confirmed directly: the attempt order at
`TMDBDiscCandidates.swift:331-353`; `showsWillContribute` at
`DiscIdentifyView.swift:212-214`; `identified = result.isIdentified` at
`DiscCommand.swift:759`; and `CdrdaoTocParser.swift` has zero mentions of "session".
Finding 5 was accepted on reading.

## Verdicts per round-1 finding

| R1 | Status |
|---|---|
| F1 privacy recheck | COMPLETE, plus a NEW minor problem (finding 2) |
| F2 APIKeyManager lost update | COMPLETE |
| F3 rip from an unscanned source | COMPLETE |
| F4 pre-launch cancel lost | COMPLETE |
| F5 tail of output dropped | COMPLETE |
| F6 fuzzy shown/submitted as exact | COMPLETE, except the CLI JSON `identified` (finding 4) |
| F7 Enhanced CD wording | COMPLETE, plus a NEW minor wording problem (finding 3) |
| F8 title numbers stripped | **INCOMPLETE** (finding 1) |
| F9 backslash escaping | COMPLETE |
| F10 key change not refreshing | COMPLETE |
| F11 over-claimed identification | COMPLETE |

## Findings

1. **MAJOR: the F8 fallback chain relaxes the title before trying the plain title.**
   - **Where:** `TMDBDiscCandidates.swift` around lines 342-353. The attempts run as:
     title + year filter → "title year" as text → **title with its trailing number
     dropped** → plain title with no filter. The loop stops at the first non-empty
     result. The comments describe the order 1, 2, 4, 3.
   - **Scenario:** `HALLOWEEN_5_1990` (the film is from 1989; the disc carries the DVD
     year).
     - (1) and (2) miss.
     - (3) "HALLOWEEN" returns the whole franchise, and only the top 5 get a running
       time; Halloween 5 isn't among them.
     - So a wrong film is named, and (4) "HALLOWEEN 5", which would have found it,
       never runs.
   - **Made worse by:** the test `test_provider_dropsATrailingNumberOnlyAsALastResort`
     pins the wrong order under a name that says the opposite.
   - **Fix:** try the plain title before the number-dropped title, and update that
     test's expected call order.
2. **MINOR: the frozen on-screen promise over-promises in the switch-OFF direction.**
   - **Where:** `showsWillContribute` in `DiscIdentifyView.swift` (around lines 212-214)
     and `MakeMKVRipView.swift` (around lines 379-381). During a run it shows the frozen
     `runWillContribute`, so a mid-run switch-OFF keeps showing "This disc will also be
     contributed" until the run ends, when the result then says nothing was sent.
   - **Fix:** during a run, show `runWillContribute && willContribute`.
3. **MINOR: the F7 text promises a whole-disc ID from a saved `.toc` "that records a
   second session".**
   - **Where:** `Help/disc-tools.md` (around lines 71-73), `docs/Disc-Tools.md` (around
     lines 91-93), the API YAML (the same paragraph), and the comment in
     `MusicBrainzDiscID.swift` (around lines 63-66).
   - **Why it's wrong:** the cdrdao `.toc` format has no session table, and
     `CdrdaoTocParser` has no session handling at all. So step 1 (`reportedSession`)
     can never fire from a file. Only the *estimated* step 2 can, and only for a
     hand-built `.toc` that lists a data track after the audio.
   - **Honest version:** "a hand-built `.toc` that lists the data track after the music
     produces an *estimated* whole-disc ID; no session table can be read from a file
     today."
4. **MINOR: F6 left the CLI JSON `identified` true for a fuzzy guess.**
   - **Where:** `DiscCommand.swift` around lines 719 and 759, which set
     `identified = result.isIdentified` (true whenever there are any matches).
   - **Why it matters:** a script keyed on `identified` files a guess as fact.
   - **Fix:** make `identified` mean an exact match, or rename/document it.
5. **MINOR: one F4 test is vacuous on a slow machine.**
   - **Which test:** `MakeMKVProcessRunnerTests.swift`
     `test_launchGate_cancelDuringLaunch_waitsForTheLaunchThenStops` (around lines
     128-148).
   - **Why it's weak:** it relies on a `DispatchQueue.global().async` cancel landing
     within a 100 ms sleep inside the launch. If it lands later, the recorded events
     are identical, so a regression that dropped the lock would still pass.
   - **Fix:** force the overlap deterministically. The launch closure blocks on a
     semaphore that the cancelling thread signals before calling `requestCancel`.

TOTAL: 5 findings (1 MAJOR, 4 MINOR).
