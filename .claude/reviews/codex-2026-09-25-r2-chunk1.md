<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Codex review, round 2, chunk 1: privacy (2026-09-25)

Reviewer: Codex (`codex exec -c model="gpt-6-astra" -s read-only`), read-only.

**Why chunks.** Round 2 over the whole range ran out of Codex's allowance
three times while Codex was still exploring. Each chunk now pastes the exact
diff into the prompt and asks for an answer in one go.

**Chunk 1a**
- **Covers:** F1 recheck, #507 and fallback fix #2.
- **Commits:** `52a4a3e`, `d602cf0`, `6057d8e`, `4269b36` (Sources and Tests,
  12 lines of context).
- **Run:** 14:44–14:45, 50.7k tokens.

**Chunk 1b**
- **Covers:** the F2 key store.
- **Commit:** `75a37bd`.
- **Run:** 14:46–14:49, 27.8k tokens.

The two prompts' instruction headers are reproduced at the end of this file.
The diffs themselves were not saved, since `git show -U12 <commits> -- Sources
Tests` regenerates them.

Findings are below, verbatim, followed by the orchestrator's verdicts after
checking each one against the code.

## Chunk 1a: findings (verbatim)

1. **MINOR — Contribution notice ignores configuration replacement.** `DiscIdentifyViewModel.swift:172` and `MakeMKVRipViewModel.swift:765` check only whether the current configuration is ready, whereas the upload requires it to equal the captured configuration. Start identification with valid settings, then change the server to another valid address or replace the API key before submission. Both booleans remain true, so the screen continues saying “This disc will also be contributed,” but `recheck` withdraws the upload. The notice must also account for configuration equality.

Round-1 finding 1: **COMPLETE** — configuration equality includes the key; narrowing preserves anonymous mode and strips the label.

Round-1 finding 10: **COMPLETE** — both views now refresh on credential-change notifications.

Fallback finding: **COMPLETE** for the reported switch-off scenario; the separate configuration-replacement defect remains above.

Tests were inspected, not run. The upload tests inspect request bodies; no parallel-test race was identified in the supplied changes.

TOTAL: 1 findings.

## Chunk 1b: findings (verbatim)

1. **MAJOR — Concurrent managers can still erase each other’s keys.** `Sources/ConverterEngine/Cloud/APIKeyManager.swift:471` — The lock belongs to each instance; it does not protect the shared index across instances. A and B can both reload the same index, append different providers, then save. Whichever saves last removes the other’s record. The same race remains between processes sharing the file. The new tests exercise only sequential writes.

2. **MAJOR — A failed reload still permits overwriting the index with stale data.** `Sources/ConverterEngine/Cloud/APIKeyManager.swift:471` — `reloadLocked()` returns without reporting read/decode failure, and `storeKey()` proceeds to save its cached array. For example, B starts empty, A saves TMDB, then the index becomes unreadable while its directory remains writable. B’s reload fails, but its atomic replacement can succeed, saving only MeedyaDB and dropping TMDB. Preserving memory on failure does not protect the file; mutations must stop when the current index cannot be read reliably.

3. **MINOR — The notification tests’ timeout cannot catch the deadlock they describe.** `Tests/ConverterEngineTests/APIKeyManagerIndexConsistencyTests.swift:310` and `:332` — Both mutations run synchronously before `wait(for:timeout:)`. With `queue: nil`, the observer also runs synchronously. If posting moves inside the lock, the observer’s lookup deadlocks before execution reaches the timeout, hanging the test worker instead of producing a bounded failure.

Round-1 finding 2: **INCOMPLETE** — Sequential successful writes are fixed; concurrent writes and failed reloads can still lose records.

TOTAL: 3 findings.

## Verdicts (orchestrator, Opus; checked against the code)

- **1a #1 (MINOR): REAL.** During a run, `showsContributionPromise` checked
  only that MeedyaDB is still ready. The run's `recheck`, however, withdraws
  on ANY difference from the captured configuration. So changing mid-run to
  another valid server or key kept the notice promising a contribution that
  would not happen.
  - **Fixed** in both view models: the notice also requires the live config
    to equal the run's captured `runConfig`.
  - **Tests:** one per screen changes the server, then the key, mid-run, and
    asserts both the notice and the wire (zero requests, the withdrawn
    reason).
  - **Also corrected:** the `runWillContribute` doc comments still said the
    view reads it directly during a run. Since `4269b36` it reads
    `showsContributionPromise`.
- **1b #1 (MAJOR): REAL, but narrower than stated.**
  - **In the app: real.** The lock is per instance, while several
    `APIKeyManager` instances live at once, and `markUsed` rewrites the whole
    index file. Scenario: a lookup's `markUsed` in one instance interleaves
    with a key being saved in Settings in another, and the key is lost.
  - **Across processes: not reachable today.** The command-line tool never
    constructs an `APIKeyManager`; it calls only the static, read-only
    `hasStoredKey`.
  - **A false comment too:** `storeKey`'s doc says "nothing else in this
    process can write in the gap", which the per-instance lock does not
    deliver.
- **1b #2 (MAJOR): REAL.** When the index file exists but can't be read or
  decoded, `reloadLocked` deliberately keeps the in-memory copy ("TRAP 2").
  `storeKey`, `removeKey` and `markUsed` then rewrite the WHOLE file from that
  stale copy, which can drop keys another instance saved, or overwrite a file
  written by a newer version.
- **1b #3 (MINOR): REAL.** The mutation and a `queue: nil` observer both run
  synchronously before `wait(for:timeout:)`. A planted post-inside-the-lock
  regression would therefore hang the test process instead of failing it.

## The prompt headers used

### Chunk 1a

```text
You are reviewing ONE small area of code changes in this Swift repository (MeedyaConverter, a macOS media converter). You are read-only: do not edit any file.

IMPORTANT, because your usage allowance is small: THE DIFF YOU NEED IS PASTED BELOW, with 12 lines of context around every change. Review from the pasted diff. Do NOT run git log, git diff, or search the repository. Only if a specific question genuinely cannot be answered from the diff, you may read at most these files, and only the lines you need:
  Sources/ConverterEngine/Disc/MeedyaDBAccess.swift
  Sources/ConverterEngine/Disc/MeedyaDBPublisher.swift
  Sources/MeedyaConverter/ViewModels/DiscIdentifyViewModel.swift
  Sources/MeedyaConverter/ViewModels/MakeMKVRipViewModel.swift
Answer in one go.

## What this area is

This is ROUND 2 of your own review. In round 1 you found these (verbatim):

1. BLOCKER — Privacy settings can be revoked before an upload, yet the upload still happens. DiscIdentifyViewModel.swift:228 captures the enabled configuration and submission mode before reading the disc. Start identification with publishing enabled and `full`, then disable publishing or select anonymous while reading or looking up the disc. The later upload still uses the captured configuration and sends the label. The video identification path has the same issue at MakeMKVRipViewModel.swift:702.

10. MINOR — Adding a key can leave "nothing will be sent" displayed immediately before a contribution. DiscIdentifyView.swift:51 observes the enabled switch and server address, but not credential changes. Open identification with publishing enabled and a URL but no key; save only the key in Settings. The notice remains "not configured," while Identify rereads the key and contributes. The MakeMKV screen has the same missing refresh.

Claude fixed them in commit 52a4a3e (also closing issue #507: a half-set-up MeedyaDB used to say "wasn't requested"), plus two test-only fixes for CI (d602cf0, 6057d8e). A fallback reviewer (a different Claude model, used while you were out of allowance) then found one more problem, which was fixed in 4269b36:

  MINOR: the frozen on-screen promise over-promises in the switch-OFF direction. During a run the screen shows the frozen `runWillContribute`, so a mid-run switch-OFF keeps showing "This disc will also be contributed" until the run ends, when the result then says nothing was sent. Fix: during a run, show `runWillContribute && willContribute`.

The intended design of the fix:
- `MeedyaDBContributor.contribute(_:requested:mode:declinedBecause:recheck:)` takes an optional `recheck` closure, called right before the network send. It returns nil (withdraw: send nothing) when the current MeedyaDB configuration differs from the one captured at the start, otherwise the current submission mode. The mode actually sent is the NARROWER of the captured and current modes (`MeedyaDBSubmissionMode.narrower`), so a mid-run change can only ever reduce what is sent, never widen it.
- A request already handed to the network cannot be recalled. That is a stated limit, not a defect.
- The screens freeze "will this run contribute?" at the start of a run (`runWillContribute`), and after 4269b36 AND it with the live value.

## Look hardest at
1. Can a mid-run change ever WIDEN what is sent (anonymous → full, or off → on)? Can the disc's label text leak on any path?
2. Is the equality check on the configuration sound? Does it compare the API key? Is there any way for recheck to report "unchanged" when the server, key or enabled switch has changed?
3. Where do the closures read UserDefaults or the Keychain from? Is any of that unsafe on the thread it runs on (the closure is @Sendable and called from engine code)?
4. Does any on-screen promise ("This disc will also be contributed", "nothing will be sent", the #507 reasons) ever say something the run then does not do, in either direction?
5. The new and changed tests. Does any assert the promise rather than what is actually sent over the wire? Would any flake under `swift test --parallel`?
6. Anything else that is wrong or would go wrong. Report only real defects, not style.

## Output
A numbered list of findings, most severe first, each marked BLOCKER / MAJOR / MINOR, with file:line, what goes wrong, and a concrete scenario that triggers it. Then a verdict for round-1 finding 1, round-1 finding 10, and the fallback's finding: COMPLETE, INCOMPLETE, or NEW PROBLEM. Then one line: TOTAL: n findings.

## The diff (commits 52a4a3e, d602cf0, 6057d8e, 4269b36; Sources and Tests only)

```

### Chunk 1b

```text
You are reviewing ONE small area of code changes in this Swift repository (MeedyaConverter, a macOS media converter). You are read-only: do not edit any file.

IMPORTANT, because your usage allowance is small: THE DIFF YOU NEED IS PASTED BELOW, with 12 lines of context around every change. Review from the pasted diff. Do NOT run git log, git diff, or search the repository. Only if a specific question genuinely cannot be answered from the diff, you may read at most this file, and only the lines you need:
  Sources/ConverterEngine/Cloud/APIKeyManager.swift
Answer in one go.

## What this area is

This is ROUND 2 of your own review. In round 1 you found (verbatim):

2. MAJOR — Saving one provider's key can make another provider's key disappear. MeedyaDBSettingsTab.swift:48 and SettingsView.swift:309 retain separate `APIKeyManager` instances. Each loads the shared index once and rewrites its entire cached index on mutation. Visit both tabs, save a TMDB key, then save a MeedyaDB key through the older instance: the latter can overwrite the index without the TMDB entry. Subsequent lookups cannot find that credential.

(Round-1 finding 10, a screen not refreshing when a key is added, was partly fixed here too, by a change notification.)

Claude fixed it in commit 75a37bd: `APIKeyManager` now re-reads the shared index file and the Keychain before every read and every write, under its lock, and posts `didChangeNotification` after unlocking so other screens refresh.

## Look hardest at
1. Is any lock left held on an early return or a thrown error?
2. Is there any path where a reload can WIPE keys that exist (for example a failed or partial read treated as "no keys", then written back)?
3. Does the legacy-migration branch re-run on every reload, and if so, can that do harm?
4. Performance: every lookup now reads the index file and Keychain items. Is it called in a hot path (a SwiftUI body, a per-frame or per-item loop) in a way that matters?
5. Is the notification posted after unlocking on every path, and can an observer that calls back into the manager deadlock?
6. Two processes (the app and the command-line tool) sharing the same index: can they still lose each other's keys?
7. The new tests: do any assert the promise rather than the delivery? Do any touch the real Keychain services or the real index file of the user's machine, or flake under `swift test --parallel`?
8. Anything else that is wrong or would go wrong. Report only real defects, not style.

## Output
A numbered list of findings, most severe first, each marked BLOCKER / MAJOR / MINOR, with file:line, what goes wrong, and a concrete scenario that triggers it. Then a verdict for round-1 finding 2: COMPLETE, INCOMPLETE, or NEW PROBLEM. Then one line: TOTAL: n findings.

## The diff (commit 75a37bd; Sources and Tests only)

```
