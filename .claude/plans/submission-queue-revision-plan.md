<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

> **Status: REVISION PLAN (read-only, Opus, 2026-09-25)** for #505, written after the owner answered section 9 of `.claude/plans/submission-queue-plan.md`. It is built on `build/505-queue` at `e1384e0` (commits 1–5). It adds commits 5a–5g on top, then lists what changes in the original commits 6–10. Line numbers are from `e1384e0`; find the code by its text before editing it.

# #505 revision: applying the owner's answers to the code already built

## 0. The short version

- **New entry state: "not tied to a server yet".** `QueuedSubmission.destination` stops being a `String` and becomes an enum, `SubmissionDestination`, with two cases: `.server(address)` and `.notTiedYet`.
  - An entry is tied when contributing is on and a complete server address is saved.
  - Once tied, it stays tied for good. The types enforce this, not a convention.
- **Keeping a disc before MeedyaDB is set up.** When readiness is `.incomplete`, a disc run keeps the disc on the list without sending anything.
  - It is tied to the address saved at that moment. If there is no usable address, it stays untied.
  - Nothing goes out during that run, even if setup is finished mid-run.
- **The off rule.** Only the ACT of switching off deletes: the Settings switch (after a warning with the count) or a settings import that turns contributing off.
  - `reconcile` and the sender never delete because contributing is off. While off they only pause.
  - The store refuses NEW live saves while off. It checks this under its own lock, which makes the act of switching off race-free.
- **No count limit.** The per-entry 16 KB body check stays. If an export would go over 10 MB, it refuses and says why (commit 8).
- **Configurable schedule.** Three new settings: first wait (minutes), longest wait (hours) and tries before stopping (0 = never).
  - The wait ladder is today's ladder, scaled from the first wait and capped at the longest.
  - The store's moving "clamp to now + 24 h" is replaced by a saved repair in the sender. That also fixes a latent bug (§4d).
- **Three fixes found while planning:**
  - An address that isn't a complete web address no longer counts as "ready" (5a).
  - The store will never write a file it couldn't read back (5b).
  - `update` can only change bookkeeping fields, so it can never re-point or widen an entry (5e).

---

## 1. What the built code does today that the answers change

| Built behaviour | Where (at `e1384e0`) | Owner answer | Change |
|---|---|---|---|
| `reconcile` with `enabled == false` deletes everything | `SubmissionQueueStore.swift` 527–535 | Off rule | Narrow only; never delete (5c) |
| Sender deletes everything when readiness is `.off`, when `enabled` is false mid-round, and loops just to delete | `SubmissionQueueSender.swift` 428–430, 455–460, 505–509, 673–679, 804–807 | Off rule | Pause; never delete (5c) |
| `start()` "with contributing switched off, that deletes everything" | Sender 726–752 | Off rule | Reconcile (narrow and tie) only (5c, 5e) |
| `destination: String`; enqueue refuses a blank one | Models 522; Store 829–831; Schema 208–217 | Q2 | `SubmissionDestination` (5e) |
| `.incomplete` → `requested = false` → `.notAttempted` | `DiscIdentifyViewModel.swift` 280–315; `MakeMKVRipViewModel.swift` 865–894 | Q2 | A keep plan (5f engine, 6 app) |
| 200-entry cap, `.refusedFull`, `listFullNote`, schema `maxItems: 200` | Store 136–160, 389–391; `MeedyaDBAccess.swift` 335–338, 627–628; Schema 104–115 | Q1 | Removed (5d) |
| Fixed ladder, fixed 24 h cap, fixed 10 tries, contributor's fixed 60 s | `SubmissionRetrySchedule.swift`; Sender 612, 646–651; `MeedyaDBAccess.swift` 620 | Q9 | Configurable (5g) |
| Store clamps `nextAttemptAt` to now + 24 h **in memory on every read** | Store 130, 632–638 | Q9 (and a bug) | Replaced by a saved repair in the sender (5g) |

**Version-1 schema changed in place.** Nothing in this worktree has been pushed or released, and no production code creates a store before commit 6. So `SubmissionQueueFile.currentVersion` stays 1. The only files in the old shape are in test temp folders. Say this in the 5e commit message.

---

## 2. The new model

### 2a. `SubmissionDestination` (5e)

```swift
public enum SubmissionDestination: Sendable, Equatable {
    case server(String)   // a normalised address; permanent once set
    case notTiedYet       // tied later to the first complete address saved while contributing is on
    public init(normalisedAddress: String?)          // nil → .notTiedYet
    public func isTied(to address: String?) -> Bool  // false for .notTiedYet, and false when address is nil
}
```

**Why an enum and not `String?`.** In Swift, `nil == nil` is `true`. The sender compares an entry's destination with `current.destination`, and with `sendingTo`, which are both `String?` (Sender 510, 700, 818, 834). If the field were optional, an untied entry would "match" whenever no address is set. So every comparison goes through `isTied(to:)`, which is false for a nil address, and no code compares the raw values.

**JSON shape.** It follows the file's own convention for `state` and `lastProblem`:
- `{ "kind": "server", "address": "https://db.example" }`
- `{ "kind": "notTiedYet" }`

It is hand-written `Codable`. It can't be a string-or-null, because the test checker (`SettingsSchemaMiniValidator`) only accepts ONE type name per property.

Decoding refuses:
- `server` with no address, or a blank one;
- `notTiedYet` that carries an address.

Either refusal makes the file unreadable, so it is set aside, which is the existing rule.

**Permanence, built into the types:**
- `QueuedSubmission.destination` becomes `public private(set) var`.
- The only way to change it is `mutating func tie(to address: String) -> Bool`. That works only on `.notTiedYet` and returns `false` otherwise.
- `SubmissionQueueStore.update` accepts a change only to the bookkeeping fields: `state`, `attemptCount`, `lastAttemptAt`, `nextAttemptAt`, `lastProblem`. Any other difference returns `false` and writes nothing.
  - This also closes a hole found while planning: today an `update` closure could swap in a full-mode payload over an anonymous one, which would widen what is sent.
- Only `reconcile` ties entries.

**`enqueue` checks (store `refusalReason`):**
- `.server(a)` must be non-blank and already normalised, meaning `MeedyaDBPublisher.normalisedDestination(for: a) == a`. This is what makes a plain-text comparison reliable.
- `.notTiedYet` is allowed.

**`dedupKey`:** `meedyaDB|<destination>|<discType>|<identity>`.
- `<destination>` is the address for `.server`.
- For `.notTiedYet` it is the fixed token `(not tied yet)`. That can never equal a normalised address, because a normalised address always has a scheme and a host.
- Two untied saves of the same disc replace each other, as today.
- When an untied entry is tied, its key changes and may collide with an entry already tied to that server (§2c).

### 2b. When an entry gets tied, and why then

**The rule, in plain words:** an entry is tied to the complete server address saved at the moment it's kept. If none is saved, it is tied to the first complete address saved afterwards while contributing is on. After that it goes only to that server.

How this reads the owner's answer:
- "Set up" means *saved*. It is not "reachable" and not "key added too". This follows from the owner's other sentence: an item saved when only the key was missing is tied to the address already entered. So an address alone is enough to tie.
- An address that isn't a complete web address counts as no address (see 5a). The owner's "tied to that address" can't apply to something that isn't one.

**Why tie when the address is saved, and not at the first send:**
- Tying must happen BEFORE anything is sent. Otherwise an untied entry could be sent to server A (for example, a request that timed out after the body went out) and later to server B. That breaks "only to that one".
- Tying when the address is saved is deterministic, testable, and shows in the list straight away ("Tied to https://…").

**A hazard this creates, and its fix (commit 6, required):**
- Today the Settings server field is `TextField(text: $baseURL)` bound to `@AppStorage` (`MeedyaDBSettingsTab.swift` 40, 115–119). It writes on EVERY keystroke.
- `https://d` already normalises. So a sender loop check or round that lands while someone is typing would tie every untied entry to `https://d` for good.
- **Fix:** the server field edits a draft and writes to `UserDefaults` only on Return, when the field loses focus, or when the tab disappears.
- This must be in the same commit that first starts the runtime (commit 6). Otherwise tying is reachable in production while the field still writes per keystroke. (Commits 4–7 land together anyway.)

**What this cannot prevent:** a user who saves a mistyped address ties the untied entries to the typo. That is the owner's rule ("then only to that one"). The mitigation is a caption by the field when untied entries exist, plus Delete on each row.

### 2c. `reconcile(meedyaDB:)` (5c, 5e)

In order:
1. **Narrow** every entry, whether tied, held, untied or paused, when the mode is narrower. This is unchanged, except that it now also runs while contributing is off: it sends nothing and keeps less on disk.
2. **Tie**, only when `settings.enabled` is true AND `settings.destination` is non-nil AND that value is already normalised. Every `.notTiedYet` entry gets `tie(to:)`. A non-normalised value ties nothing, so the check fails safe.
3. **Merge duplicates created by tying.** Entries that now share a `dedupKey` are reduced to the one with the latest `createdAt` (on a tie, the later in the file). This is the same "newer replaces older" rule `enqueue` already applies. The count goes in `mergedDuplicates`.
4. **Count** `held` (tied to a different server) and `notTiedYet`.

It writes only when something changed.

`ReconcileReport` loses `removedBecauseOff` and `otherFilesRemovedBecauseOff`, and gains `tied`, `mergedDuplicates` and `notTiedYet`.

**The "held" rule is unchanged for tied entries.** An untied entry is not "held". It is "waiting for a server to be saved".

**What reconcile cannot do:** tie an entry while contributing is off. It also never deletes because contributing is off.

### 2d. Keeping a disc while `.incomplete` (5f engine, commit 6 app)

**The contributor (`MeedyaDBContributor.contribute`).** It gains one defaulted parameter, and the same parameter is passed through `MusicDiscIdentifier.identify` and `VideoDiscIdentifier.identify`:

```swift
public struct MeedyaDBKeepUntilSetUp: Sendable, Equatable {
    public let destination: SubmissionDestination   // captured when the run started
}
func contribute(_:requested:mode:declinedBecause:recheck:keepUntilSetUp: MeedyaDBKeepUntilSetUp? = nil)
```

- `requested == true` → the plan is ignored and the live send path runs as today. A test pins this.
- `requested == false`, AND a plan, AND a store, AND a `recheck` → the **keep path**.
  - It is a separate private function that is never given the publisher, so it cannot send. That is structural.
  - Steps:
    1. Guard `hasUsableIdentity`.
    2. `Task.checkCancellation()`.
    3. `recheck()` runs once, right before saving; there is no network call to be "before". `nil` → `.notAttempted(reason: notKeptSettingsChangedReason)`.
    4. Build the body with `buildSubmission(… mode: narrower(capturedMode, liveMode))`, then `MeedyaDBQueuedPayload`.
    5. Create the entry:
       - `destination = plan.destination`, `state .pending`
       - `attemptCount 0`, because nothing was tried
       - `lastAttemptAt nil`, `lastProblem nil`, because no try failed and the list must not suggest one did
       - `nextAttemptAt = savedAt`, so it is due as soon as it can be sent
       - a new UUID `idempotencyKey`
    6. `enqueue`:
       - `.added` or `.replacedEarlier` → `.queued(reason: (declinedBecause ?? generic) + queuedUntilSetUpEnding(for: destination))`
       - `.refusedContributingOff` → `.notAttempted(notKeptSettingsChangedReason)`
       - `.refusedInvalid` or `.unavailable` → `.notAttempted(declined + " " + couldNotKeepPrefix + why)`. It is not `.failed`, because nothing was sent.
- Otherwise: `.notAttempted(declinedBecause ?? notRequestedReason)`, exactly as #507 does today.

**Wording (public constants, pinned by tests):**
- `queuedUntilSetUpEnding(for: .server(a))` = `" This disc is kept, and will be sent to \(a) once MeedyaDB is set up, while MeedyaConverter is open. You can see or delete it in Settings › MeedyaDB."`
- `queuedUntilSetUpEnding(for: .notTiedYet)` = `" This disc is kept, and will be sent to the first MeedyaDB server address you save in Settings, and only to that one, while MeedyaConverter is open. You can see or delete it in Settings › MeedyaDB."`
- `notKeptSettingsChangedReason` = `"MeedyaDB settings changed while this disc was being identified, so it wasn't kept to send later."`

For example: "Contributing is on, but MeedyaDB has no API key yet. Add one in Settings. This disc is kept, and will be sent to https://db.example once MeedyaDB is set up, while MeedyaConverter is open. You can see or delete it in Settings › MeedyaDB."

**The two view models (commit 6).** Today they compute `config = readiness.config`, `contribute = config != nil`, and a `recheck` that withdraws unless the live config EQUALS the captured one (`DiscIdentifyViewModel.swift` 306–315; `MakeMKVRipViewModel.swift` 885–894).
- `.ready`: unchanged (live send, and keep-for-later on a temporary failure).
- `.off`: unchanged. No plan is passed, so nothing is kept, whatever happens mid-run.
- `.incomplete`, with a store injected (always in production, `nil` in tests unless a test passes one):
  - Read `queueSettingsProvider()`, a new seam defaulting to `MeedyaDBQueueSettings.current(in: .standard)` (5a). It is cheap and never touches the Keychain.
  - Build a plan only if that read also says `enabled` (both reads must agree, which fails safe).
  - `destination = SubmissionDestination(normalisedAddress: settings.destination)`.
  - The **recheck for this run**: `{ let live = queueSettingsProvider(); guard live.enabled, SubmissionDestination(normalisedAddress: live.destination) == captured else { return nil }; return modeProvider() }`.
  - So "recheck" here means: still switched on, and the address is exactly what it was at the start. It is the F1 "any change withdraws" rule, applied to the only settings that matter when nothing is sent live.
  - A key being added or removed mid-run does not withdraw. The key doesn't change what is kept or where it goes.
- `.incomplete` with no store: unchanged (#507 `.notAttempted`).
- The factories build the identifier WITH the store even when `config == nil`, using a disabled publisher. Today they build `MusicDiscIdentifier()` with no store (`DiscIdentifyViewModel.swift` 64–67).

**How "never widen" is kept on the keep path:**
1. The mode is `narrower(captured, live)`.
2. The keep path has no publisher, so a run that started not set up can never turn into a live send, even if setup is finished mid-run.
3. A run that started `.off` gets no plan.
4. A captured `.server(a)` withdraws if the address changes. A captured `.notTiedYet` withdraws if an address appears mid-run. That is deliberately conservative and matches F1. The disc can simply be identified again.

**Screen promise (commit 6):**
- New `willKeepUntilSetUp` = readiness is `.incomplete` and a store is present.
- Frozen at run start: `runWillKeep` and `runKeepDestination`.
- `showsKeepPromise` = when idle, `willKeepUntilSetUp`; while running, `runWillKeep && liveEnabled && liveDestination == runKeepDestination`. This is the twin of `showsContributionPromise`.
- The disc screens add "This disc will be kept and sent once MeedyaDB is set up." under the #507 reason (`DiscIdentifyView.swift` 232–246 and the MakeMKV twin at 389).

### 2e. The sender with untied entries (5e)

- Due, held and status counting all use `isTied(to:)`.
- An untied entry is never due, never sent and never counted as held. `Status` gains `notTiedYet`.
- **Tying happens in more places than rounds.** An entry kept mid-run, an import, or an address written outside the app might otherwise wait forever, because rounds only run when something tied to the current server is due. So tying happens:
  - in `start()`;
  - at the top of every round (step 2);
  - in every loop check (`shouldRunRound`), BEFORE the "waiting for a person" check, whenever contributing is on, an address is saved and any untied entry exists. It calls `store.reconcile(current)`, which is cheap and writes only when something changes;
  - and from the app's `settingsChanged()` (commit 6).
- The per-entry check before a send stays: `entry.destination.isTied(to: current.destination) && entry.destination.isTied(to: sendingTo)`.

### 2f. Privacy guarantees (plan §3), rechecked

| # | Guarantee | Status |
|---|---|---|
| G1 | Only an already-cleaned body is kept; an anonymous body can't hold a label (type-enforced) | **Holds**, on both save paths |
| G2 | Nothing is kept without a recheck right before saving (structural) | **Holds**, extended to the keep path |
| G3 | A run that started with contributing off never keeps or sends | **Holds** |
| G4 | "Never save while off", enforced five ways | Layers 1–4 **hold**. Layer 5 (the sender deletes while off) is **REMOVED**. New layer: `enqueue` refuses while off, checked under the store's lock |
| G5 | "The on-disk list is always empty while off" | **NO LONGER TRUE.** Entries can exist while off after an import onto an off Mac (Q12), after switching off outside the app (`defaults write`, editing the plist), or after a switch-off purge whose write failed (reported). New guarantee: while off, nothing is sent, no disc run saves anything, and everything kept is visible and deletable in Settings |
| G6 | Switching off deletes everything | **Narrowed to the ACT:** the Settings switch after a warning, or an import that turns it off. Set-aside and newer-version files included |
| G7 | A narrower mode removes the label permanently before sending | **Holds**, and now also while off |
| G8 | A different server → held, never sent elsewhere, never auto-deleted | **Holds** for tied entries. **New:** untied entries go nowhere until tied; tying is permanent (type-enforced) |
| G9 | A replaced key keeps entries and sends with the new key | **Holds** |
| G10 | Key missing → nothing sent, entries kept | **Holds**; entries can now also be CREATED in this state (Q2) |
| G11 | No key, reply text or file path stored | **Holds**; untied entries don't even hold a server |
| G12 | The user can see and delete anything | **Holds and extended:** the list must be visible while off (commit 7) |
| G13 | The CLI never saves or sends | **Holds** |
| G14 | Stopped entries never exported | **Holds.** Untied pending entries ARE exported and tie on the importing Mac (commit 8 preview must say where) |
| G15 | A live send only goes out with a complete config | **Strengthened** by 5a |
| G16 | (new) A disc kept while not set up is never sent live by that run | **New**, structural |
| G17 | A request already handed to `URLSession` can't be recalled | Unchanged stated limit |
| G18 | "The worst case fits in an export" (the 200 × 16 KB cap) | **REMOVED.** Export refuses with a reason instead (commit 8) |

---

## 3. The off rule

### 3a. Who deletes

Deletion is always `SubmissionQueueStore.removeAll(reason: .contributionsOff)`. That still deletes set-aside unreadable copies and a newer-version file (accepted departure from commit 2). Its doc must say that only these two acts call it:

1. **The Settings switch (commit 6, not 7).**
   - Items can exist in production from commit 6, so the act must exist then.
   - The `Toggle` gets a custom `Binding`. Turning it ON writes at once. Turning it OFF calls `requestSwitchOff()`:
     - `let preview = store.removalPreview(for: .contributionsOff)` (a new store read that returns the `RemovalReport` `removeAll` WOULD produce, and changes nothing);
     - if the preview is empty, it does the act straight away;
     - otherwise it shows a `confirmationDialog`. The stored value stays `true` until the user confirms, so the toggle stays on.
   - On confirm: `SubmissionQueueRuntime.switchOffContributing(defaults: .standard)`:
     1. write `enabled = false`;
     2. THEN `store.removeAll(.contributionsOff)`;
     3. then an Activity Log line.
   - **Why this order.** `enqueue` checks `isContributingOn` under the store's lock (5c), and `removeAll` takes the same lock. Any live save either finishes before the purge (and is purged) or sees "off" and is refused. The reverse order leaves a window where a save could land after the purge and survive while off.
   - Cancel leaves contributing on. There is deliberately no "turn off but keep" choice: the owner's rule is that the act deletes.
2. **A settings import that turns contributing off (commit 8, §7).** This is Connections ticked, this Mac's `meedyadb.enabled` true before, and after apply either written `false` or removed in replace mode (`SettingsImporter.swift` 619–638 removes absent keys). The app sheet and the CLI's `settings import --apply` are both covered.

**Anything else that can turn it off?**
- A grep of `Sources/` finds only the Settings tab writing `meedyadb.enabled`. `DiscIdentifyView` and `MakeMKVRipView` only read it through `@AppStorage`.
- There is no "reset settings" feature (`removePersistentDomain` is not used in `Sources/`).
- Terminal `defaults write` or editing the plist is not an act the app can see. The entries stay kept and paused, and are visible. This is a stated limit, not a bug.
- **Builder report check:** every non-test write of `MeedyaDBConfigStore.Keys.enabled`, and every non-test `.contributionsOff`, must be in the Settings tab's binding, the runtime's `switchOffContributing`, or the importer.

### 3b. While merely off

- `reconcile`: narrows only. It never deletes and never ties.
- Sender:
  - A round with readiness `.off`, or settings `enabled == false`, sends nothing, deletes nothing, and ends `.pausedBecauseOff` (this replaces `.switchedOff`).
  - Off mid-round: the round ends before the next entry, and nothing is deleted.
  - `shouldRunRound` returns `false` while off. No more "a round to delete it".
  - "Try Now" while off returns `.pausedBecauseOff`.
  - `RoundReport.deletedBecauseOff` is removed. `Status` gains `contributingIsOn`.
- The store refuses live saves (`.refusedContributingOff`). `retryStopped`, `remove` and `update` still work.
- **At app launch while off:** `start()` narrows (and repairs far-future waits, §4d), deletes nothing and logs no deletion. The loop idles.
- **Switched back on:** the next loop check ties untied entries to the saved address (if there is one) and sends what's due. Commit 6 calls `settingsChanged()` (reconcile, then `wake()`) when the switch goes on.

### 3c. What the UI must say (commits 6 and 7; pinned constants in the view model)

- **Dialog title:** "Turn off contributing to MeedyaDB?"
- **Dialog message:** "The 3 contributions waiting to be sent will be deleted, and won't be sent." When the preview includes other files, add: " A damaged copy of the list that couldn't be read will be deleted too."
- **Dialog buttons:** "Turn Off and Delete" (destructive) and "Cancel".
- The count is bound to the live list, refreshed on `didChangeNotification`, so a disc saved while the dialog is open still gets counted.
- **Under the toggle, while on with entries:** "Turning this off deletes the 3 contributions waiting to be sent."
- **While off with entries** (a section OUTSIDE today's `if enabled` block, `MeedyaDBSettingsTab.swift` 65–70): "Contributing is off, so the 3 contributions below are kept but won't be sent. Switch contributing on to send them, or delete them." It shows the same list with Delete and Delete All. Try Now is disabled.
- **Activity Log, from the act only:** "Contributing to MeedyaDB was switched off, so 3 waiting contributions were deleted."

---

## 4. Configurable schedule (5g; UI in commit 7)

### 4a. Settings

All three are Int, read by the engine, and owned by `SubmissionRetrySchedule.Keys`, following the `MeedyaDBConfigStore.Keys` pattern.

| Key | Default | Bounds | Meaning |
|---|---|---|---|
| `meedyadb.retry.firstWaitMinutes` | 1 | 1…60 | Wait after the first failed try. The lower bound matches MeedyaDB's `Retry-After: 60` for HTTP 429. |
| `meedyadb.retry.longestWaitHours` | 24 | 1…168 (7 days) | The most any wait can be. Because first ≤ 60 min and longest ≥ 1 h, first ≤ longest always holds. |
| `meedyadb.retry.maximumTries` | 10 | 0…100 | Tries before an entry stops. **0 = never stop.** |

**Reading them:** `SubmissionRetrySchedule.current(in defaults: UserDefaults)`.
- It reads each value with `defaults.object(forKey:) as? Int`. Absent, or not an Int → the default. Then it clamps into bounds, following the `RenderFarmConfigurationLoader` pattern.
- **Do NOT use `integer(forKey:)`.** For a stored string it returns 0, which would silently mean "never stop". Test and planted fault F-g1 below cover this.

**Is "never stop" allowed?** Yes.
- The cost is small: the round-level pause means one request per round while the server is down, at most one per longest wait while the app is open.
- The entries stay visible, and rejected (4xx) entries still stop at once.
- Commit 7 must show it plainly ("Keeps trying until you delete it").

**Registry:**
- In 5g the three keys go in as `.never(.noScreenChangesIt, reason: "The Settings controls arrive in #505 commit 7; until then nothing lets you change it.")`. That follows the registry's own rule that only settings a user can change are exported, and mirrors the `fileStores` `.never` → `.allowed` flip.
- Commit 7 flips them to `.allowed(.connections, .int(bounds), label:…, location: "Settings › MeedyaDB")`. They travel in exports (Connections group) and need no warning.
- `SettingsKeyScanMap.symbols` gains `SubmissionRetrySchedule.swift|Keys.*` in 5g, and `MeedyaDBSettingsTab.swift|SubmissionRetrySchedule.Keys.*` in commit 7. Without them, `SettingsKeyCoverageTests` fails.

### 4b. The ladder

The step multipliers are exactly today's ratios. Each step is the one before it times the multiplier: ×5, ×3, ×4, ×3, then ×2 for every step after that. No step is ever longer than the longest wait:
- `baseWait(1) = first`
- `baseWait(k+1) = min(baseWait(k) × m(k), longest)`
- `m = [5, 3, 4, 3]`, then 2
- Stop the loop once it reaches `longest`, so an attempt count of 10,000 costs nothing.

Check against today's defaults (1 min, 24 h): 60, 300, 900, 3600, 10800, 21600, 43200, 86400, 86400 … — identical to today's `waits`.

In plain words: the default steps, scaled by (first wait ÷ 1 minute), doubling after the last default step, and never longer than the longest wait.

- **Spread:** `min(base × clamp(jitter, 0.9…1.1), longest)`. The cap is the CONFIGURED longest wait.
- **Stop rule:** `maximumTries == 0` → never; otherwise `attemptCount >= maximumTries`.
- **`plainDescription`** (engine, tested): for example, "Tries again after 1 min, then 5 min, 15 min, 1 h, 3 h, 6 h, 12 h, and then every 24 h. Stops after 10 tries (about 3 days, counting only time MeedyaConverter is open)." Commit 7 shows this text instead of any hard-coded sentence.

### 4c. Every place the fixed values are used today, and what reads the configured ones

| Place | Today | Becomes |
|---|---|---|
| `SubmissionRetrySchedule` (whole file) | a static enum: `waits`, `longestWait`, `firstWait`, `maximumFailedTries` | a struct with `.standard`, bounds, `current(in:)`, the derived ladder; `jitterFraction` and `randomJitter()` stay static |
| Sender 612 (round pause), 646–651 (`recordFailedTry`) | static calls | `schedule()`, a new init closure (default `{ .standard }`); the app passes `{ SubmissionRetrySchedule.current(in: .standard) }` |
| `MeedyaDBAccess.swift` 620 (contributor's first wait) | `SubmissionRetrySchedule.firstWait` | `retrySchedule().firstWait`, from a new `MeedyaDBContributor.init(retrySchedule:)` param (default `{ .standard }`), plumbed through all three identifier inits |
| Store 130 and 632–638 | in-memory clamp to now + 24 h | **removed** (§4d) |
| Schema 241 (`nextAttemptAt` text), Models 387 and 550, Sender 164, 565, 631, `MeedyaDBAccess.swift` 709 comments | "24 hours", "10th" | "the configured longest wait (24 h by default)", "the configured number (10 by default)" |
| `test_10_theWaitSchedule…`, `test_aFarFutureNextAttemptIsClampedWhenRead`, `test_9_…` | fixed | rewritten (5g tests) |

### 4d. The clock-jump clamp: a latent bug, and its replacement

**The bug.** Today `reloadLocked` clamps a far-future `nextAttemptAt` to `now() + 24 h` IN MEMORY on every read, and the store re-reads the file on every call.
- The target therefore moves forward with each read.
- A lone entry parked in the future (the clock jumped) never becomes due, until some OTHER write happens to save the clamped value.
- The loop just keeps sleeping.
- Only Try Now sends it.

**The replacement (5g).**
- The store reports exactly what the file says; the clamp is removed.
- The sender owns a **saved repair**: any pending entry whose `nextAttemptAt` is more than the configured longest wait from now is set, with `update`, to `now + longest`.
- This happens in `start()`, at the top of each round, and in each loop check. It writes only when needed.
- Once saved, the value is fixed, so it stops moving.
- It also handles a user SHORTENING the longest wait (for example, entries 6 days out get pulled in to 1 h).
- Stopped entries are ignored.

---

## 5. No count limit (5d; export in commit 8)

- **Store:**
  - `Limits` keeps only `maxBodyBytes` (16 KB). Its doc changes: the settings-file limit is now enforced at export (commit 8), not by a cap.
  - The cap branch (389–391) and `EnqueueOutcome.refusedFull` are removed.
- **Contributor:** the `.refusedFull` case (627–628) and `listFullNote` are removed.
- **Schema:**
  - `entries` loses `maxItems`, and its description says there is no limit on how many.
  - The committed `docs/schemas/submission-queue-v1.schema.json` is regenerated.
  - `SettingsSchemaMiniValidator` KEEPS `maxItems` support and its own ad hoc test. Only its header comment stops citing the list cap.
- **Tests:**
  - `test_aFullListRefusesNewEntriesAndKeepsTheOldest`, `test_aReplacementIsAllowedWhenTheListIsFull`, `test_fullList_isFailedWithTheWording_andNothingIsDropped`, `test_entriesBeyondTheStandardCapFailTheSchema` and the `listFullNote` line in `test_wording_isPinned` are replaced by tests proving there's no limit (5d below).
- **Commit 8 (export):**
  - In `SettingsExporter.makeExport`, after `SettingsDocument.makeData` and BEFORE the self-check (123–170), check `data.count > maximumFileSize`.
  - If it's too big, throw a new `SettingsExportError.fileWouldBeTooLarge(bytes:limit:waitingContributions:)`, with nothing written.
  - The wording names the group when it is ticked: "This settings file would be 12.4 MB, but a settings file can be at most 10 MB. Most of it is the 2,310 contributions waiting to be sent. Untick “Contributions waiting to be sent” to export everything else, or delete some of them in Settings › MeedyaDB first. Nothing was saved."
  - **Never trim entries to fit.**
  - Without this check the self-check would fail with the importer's confusing "This file is too large to be a settings file".
  - Make the limit injectable on the exporter (`maximumFileSize: Int = SettingsDocument.maximumFileSize`) so tests can use a small one. Also keep one test at the real size.
  - **Import:** the old "≤ 200 entries" and "combined ≤ cap" checks are dropped. The 10 MB file limit already bounds an import.

---

## 6. The new commits on top of `e1384e0`

Rules for every commit:
- Each commit compiles and its tests run on its own in the `.claude/local-test-harness.md` harness.
- Builder rules from the original plan §8 apply: whole-second dates; no captured `var` inside `@Sendable` closures (use lock-guarded classes); type-check test files for real; each planted fault is reverted and confirmed by checksum.
- 5a and 5f touch `MeedyaDBAccess.swift`, which Codex chunk 1 covers. Build in the worktree.
- **Commits 4, 5, 5a–5g, 6 and 7 must land together** before any PR.

### 5a — `feat(meedyadb): one shared address check; an address that isn't a complete web address isn't "set up" (#505, 5a)` — Sonnet builds, Opus reviews

**Why:**
- Commit 6 must build `MeedyaDBQueueSettings.destination` exactly as `MeedyaDBPublisher.destination` does, and there is no shared helper yet.
- `.ready` today only needs a non-blank address. So a `.ready` round can have `sendingTo == nil`, and a live send is tried against a URL that can't work.

**Changes:**
- `MeedyaDBPublisher.normalisedDestination(for baseURL: String) -> String?` (static). The instance `destination` (307–326) calls it.
- `MeedyaDBQueueSettings.current(in defaults: UserDefaults)` reads `isEnabled`, `normalisedDestination(baseURL)` and `submissionMode`. No Keychain.
- `MeedyaDBGate.readiness` (171–193): a non-blank address that doesn't normalise → `.incomplete`, with two new pinned reasons:
  - `invalidAddressReason`: "Contributing is on, but MeedyaDB's server address isn't a complete web address (it should look like https://db.example). Fix it in Settings."
  - `invalidAddressAndMissingKeyReason`: "…isn't a complete web address, and there's no API key yet. Fix both in Settings."
- The CLI doesn't use the gate, so it is unchanged.

**What it cannot do:** say whether a complete address is correct or reachable.

**Tests:**
- An address table: trailing "/", upper case, whitespace, `db.example`, `https://`, `http:/x`, `http://db.example:8080/path/` → static == instance.
- `current(in:)` with a suite: normalised destination, fail-safe mode.
- Readiness: `db.example` + key → `.incomplete(invalidAddressReason)`; `db.example` without a key → the combined reason; `https://db.example` + key → `.ready`, unchanged.

**Planted faults:**
- The instance keeps its own copy of the logic → the table test fails.
- The gate goes back to the non-blank check → the `db.example` test fails.

### 5b — `fix(engine): the waiting list never writes a file it couldn't read back (#505, 5b)` — Sonnet

**Why:** a carried-forward finding. `update` accepts any HTTP status, but reading the file refuses a status outside 100–599 and sets the WHOLE list aside. The sender guards against this; the store doesn't.

**Change:**
- `writeLocked` encodes, then runs `Self.decode` on those bytes. It refuses, throwing a fixed-wording error, unless the result is `.readable` with the same ids in the same order. Compare ids, not values, because dates lose sub-second precision.
- `enqueue` maps that error to `.refusedInvalid(reason: "it has a value this version couldn't read back, such as an HTTP status outside 100–599")`.
- `update`, `remove`, `retryStopped` and `reconcile` return their existing "nothing changed" results.
- The cost is one extra decode per write; say so.

**Tests:**
- `update` setting `.serverError(httpStatus: 999)` → `false`; the file is byte-identical; there is no `queue.unreadable-*` file; `entries()` still has everything.
- `enqueue` of a `.stopped(.rejected(httpStatus: 42))` entry → `.refusedInvalid`.

**Planted fault:** remove the re-decode → the next read sets the file aside → both tests fail.

### 5c — `feat(engine): only switching off deletes the waiting list; while off it just waits (#505, 5c)` — Opus

**Files:** `SubmissionQueueStore.swift`, `SubmissionQueueSender.swift`, `SubmissionQueueModels.swift` (the doc on `MeedyaDBQueueSettings.enabled`), `MeedyaDBAccess.swift` (contributor switch and header), and the tests and test support.

**Changes:**
- **Store:**
  - `init(directory:limits:now:isContributingOn:)`. The new closure is REQUIRED, with no default, so no caller can forget it.
  - `enqueue` calls it under the lock, after the read-only check and before anything else. False → the new `.refusedContributingOff`.
  - Its doc: it must be cheap and must never call back into the store. The app passes `{ MeedyaDBConfigStore.isEnabled(in: .standard) }` (a `UserDefaults` read); the CLI (commit 8) passes `{ false }`.
  - `commitImport` (commit 8) is deliberately NOT gated (Q12).
- **Store:** `reconcile` removes its off branch (527–535), and `ReconcileReport` drops the two off fields.
- **Store:** `removalPreview(for:)`. And `RemovalReason.contributionsOff`'s doc says "only the act of switching off (§3a)".
- **Sender:** everything in §3b.
  - Remove `deleteEverything`.
  - Rewrite the file header ("THE PRIVACY RECHECKS": off → pause) and the `start()` doc.
- **Contributor:** `.refusedContributingOff` → `.failed(sendFailure + " " + settingsChangedWhileSendingNote)`.

**What it cannot do:**
- Delete anything when contributing is turned off outside the app.
- Recall a send already on its way (the stated limit is unchanged).

**Tests** (each is a delivery test on real files):
1. `reconcile` while off, with a full-mode entry (sentinel label) and the mode narrowed to anonymous → the sentinel is gone from the file bytes, and the entry count is unchanged. With nothing to narrow → the file is byte-identical. (Replaces `test_reconcileWhenSwitchedOffRemovesEverything`.) **Planted F-c1:** restore the off branch → fails.
2. A newer-version file plus `reconcile` while off → the file is still there, byte-identical. (Replaces `…DeletesANewerVersionsFile`.)
3. `enqueue` with the gate false → `.refusedContributingOff`, and the file is absent or unchanged. **Planted F-c2:** skip the gate → fails.
4. **Race, deterministic.** A contributor with a 503 stub. Its second `recheck()` call itself performs the act: it sets the gate flag false, calls `store.removeAll(.contributionsOff)`, then returns `.full`.
   - Result: not `.queued`; the list is empty.
   - F-c2 also fails this test: the entry lands after the purge.
5. `removalPreview(.contributionsOff)` with 2 entries and a set-aside file, and separately a newer-version file → equals the `removeAll` report afterwards. **Planted F-c3:** the preview ignores set-aside files → fails.
6. Sender with readiness `.off` and 3 due entries → zero requests, `.pausedBecauseOff`, the file byte-identical. **Planted F-c4:** delete in the `.off` branch → fails.
7. Off between entry 1 and entry 2 (settings script) → entry 1 sent, entry 2 not sent and still in the file. (Replaces `test_14_switchedOffDuringTheRound…`.) **Planted F-c5:** delete per entry → fails.
8. Loop while off with 2 due entries: `start()`, then release the first sleep and 3 loop steps → `status.lastRoundAt == nil`, zero requests, the file byte-identical. **Planted F-c6:** `shouldRunRound` returns true when off with entries → fails.
9. `start()` while off → the file byte-identical.
10. Off, then on → the next round sends every kept entry. Paused really does mean "later".

### 5d — `feat(engine): no limit on how many contributions wait (#505, 5d)` — Sonnet

**Changes:** §5 (store, contributor, schema and regenerated JSON, validator comment).

**What it cannot do:** keep a list of any size inside a 10 MB settings file. That is commit 8's refusal.

**Tests:**
- 250 distinct `enqueue`s → all `.added`, and the file has 250.
- With 200 waiting, a 201st 503 → `.queued`, and the file has 201.
- A 1,000-entry file validates against the schema.
- The drift test (the committed file has no `maxItems`).

**Planted faults:**
- A cap of 200 comes back → the first two fail.
- Schema `maxItems: 200` → the schema test and the drift test fail.

**Builder measures and reports (not pass/fail):** the time for 500 `enqueue`s, and one forced round sending 500 entries against a 200-OK stub. See Risk 3.

### 5e — `feat(engine): a waiting contribution can wait for its server; tied for good once one is saved (#505, 5e)` — Opus

**Changes:** §2a, §2c and §2e.
- Models: `SubmissionDestination`, `tie(to:)`, `private(set)`, the `dedupKey` token.
- Store: `refusalReason`; `update` accepts bookkeeping changes only; `reconcile` ties and merges; the report fields.
- Sender: `isTied(to:)` everywhere; tying in the loop check; `Status.notTiedYet`; `RoundReport.tied` and `mergedDuplicates`.
- Contributor, ready path: `.server(d)`. `noDestinationDetail` stays: it is unreachable after 5a but kept as a defence.
- Schema: `$defs.submissionDestination`; the honest-limit `$comment` adds "address is present exactly when kind is server"; regenerate.
- Test support: fixtures default to `.server(Fixtures.destination)`, and `rawEntry` writes the object.

**What it cannot do:**
- Stop a user tying entries to a mistyped address (§2b).
- Tie anything while contributing is off.

**Tests:**
1. **The journey.**
   1. An untied entry; settings on, no address, `.incomplete` → round: zero requests, still untied.
   2. Address A saved (still `.incomplete`, no key) → round → the file shows `server/A`.
   3. A **new store object** (a restart) → still A.
   4. Settings B plus `ready(B)` → round: zero requests; held.
   5. Settings A plus `ready(A)` → round: exactly one request, to A's URL, with byte-identical body and the same key; the list is empty.
   - **Planted F-e1:** `reconcile` re-ties already-tied entries → the B round sends → fails.
   - **Planted F-e2:** tie only in memory → after the restart it's untied → fails.
2. Settings with no address and an untied entry → `status.notTiedYet == 1`, `waiting == 0`, and the loop runs no round. **Planted F-e3:** `isTied` written as Optional `==` → counted as waiting and a round runs → fails.
3. Off plus address A → `reconcile` leaves it untied. **Planted F-e4:** tie regardless of `enabled` → fails.
4. Disc D tied to A (created T1) plus disc D untied (T2 > T1) → `reconcile(A)` → one entry, T2's body, `mergedDuplicates == 1`. **Planted F-e5:** no merge → fails.
5. A settings destination that isn't normalised (`"HTTPS://DB.example/"`) → nothing tied. **Planted F-e6:** skip the normalisation check → fails.
6. An `update` closure that assigns a different destination, or a full-mode payload over an anonymous entry → `false`, file byte-identical, the sentinel never in the bytes. **Planted F-e7:** remove the bookkeeping-only check → fails.
7. `enqueue` refuses a non-normalised or blank `.server`. Decoding refuses a `server` with no address, and a `notTiedYet` with an address. The schema accepts both kinds; the old string shape fails the schema.
8. The loop ties by itself: an untied entry, settings on plus A plus `ready(A)`, the test never calls `reconcile`; `start()` and release the sleeps → one request. **Planted F-e8:** no tying in the loop check → zero requests → fails.
9. The same untied disc twice → `.replacedEarlier`; untied and tied keys differ.

### 5f — `feat(meedyadb): keep a disc even before MeedyaDB is set up (#505, 5f)` — Opus

**Changes:** §2d, engine half.
- `MeedyaDBKeepUntilSetUp`, `keepUntilSetUp:` on `contribute` and on both `identify` methods (defaulted, so the CLI is unchanged).
- The keep path as a separate function with no publisher.
- The wording constants.
- The contributor's header "posture" gains the keep bullet.

**What it cannot do:** decide on its own that a run is "not set up". The caller (commit 6) decides, from readiness.

**Tests:**
1. A **usable** publisher plus a recording stub, `requested: false` plus a plan → `.queued` (pinned); **stub request count 0**; the entry has `attemptCount 0`, `lastAttemptAt nil`, `lastProblem nil`, `nextAttemptAt == savedAt`, the plan's destination, and a UUID key. **Planted F-f1:** the keep path calls `publisher.send` → count 1 → fails.
2. Anonymous captured mode with a sentinel label → the sentinel is not in the file bytes. **Planted F-f2:** build the body in `.full` → fails.
3. Captured full, `recheck` returns anonymous → an anonymous body is kept.
4. `recheck` returns nil → `.notAttempted(notKeptSettingsChangedReason)`, no file. **Planted F-f3:** skip the recheck → fails.
5. No `recheck`, or no store → `.notAttempted(declinedBecause)`, word for word as #507, and no file.
6. The gate is off at save time → `.notAttempted(…)`, no file.
7. `requested: true` plus a plan → a live send (count 1); the plan is ignored.
8. The music identifier (both inits) and the video identifier pass the plan through.
9. The wording for both destinations is pinned.
10. End to end: keep (untied) → `reconcile(A)` → a sender round with `ready(A)` sends `wireBody(kept)` with the entry's key.

### 5g — `feat(engine): first wait, longest wait and tries before stopping are settings (#505, 5g)` — Opus

**Changes:** §4, in full.
- The schedule struct and derivation, `current(in:)`, `plainDescription`.
- The registry `.never` entries and scan-map entries.
- The sender's `schedule` closure and the saved far-future repair.
- The store clamp and `longestWait` removed.
- The contributor and identifiers' `retrySchedule`.
- The schema text; regenerate.

**What it cannot do:** change waits already scheduled for entries, except pulling in waits that are longer than a newly shortened longest wait.

**Tests:**
1. `.standard` ladder exactly `[60, 300, 900, 3600, 10800, 21600, 43200, 86400, 86400, 86400]`; stops at 10; the 3-day total is unchanged.
2. Exact ladders for (5 min, 6 h), (1 min, 168 h) and (60 min, 1 h).
3. `current(in:)`: absent → standard; out of range → clamped; a String or Bool stored for `maximumTries` → 10, not "never". **Planted F-g1:** use `integer(forKey:)` → fails.
4. Never stop: `shouldStop` false at 10,000, and `baseWait(10_000)` is fast and equals the longest wait.
5. The spread's cap follows the configured longest: (1 min, 2 h), `wait(after: 20, jitter: 1.1) == 7200`.
6. **Sender uses the configured schedule (delivery).** (5 min, 1 h, 3 tries), an always-503 stub, an entry with `attemptCount 0` → next tries at +300 then +1500, then stopped after the 3rd. **Planted F-g2:** the sender uses `.standard` → fails.
7. Never stop through the sender: 15 failures → still pending.
8. The round pause after the first failed round equals the configured first wait.
9. **Saved repair.** An entry 10 years out; `start()` → the raw file's `nextAttemptAt == now + longest`; advance past it and release the loop → one request.
   - **Planted F-g3:** repair only in memory → the file still says 10 years → fails.
   - **Planted F-g4:** no repair at all → never due → fails.
10. Longest wait shortened to 1 h → an entry 6 days out is repaired to +1 h.
11. The contributor honours the configured first wait (+600 s for 10 min).
12. `SettingsKeyCoverageTests` and `SettingsKeyRegistrySentinelTests` are green.

---

## 7. What changes in the original commits 6–10

**Commit 6 (app wiring): now Opus builds.** It now contains the act of switching off and the keep wiring, which both touch privacy.

**Runtime:**
- The store is built with `isContributingOn: { MeedyaDBConfigStore.isEnabled(in: .standard) }`.
- The sender gets `settings: { MeedyaDBQueueSettings.current(in: .standard) }` and `schedule: { SubmissionRetrySchedule.current(in: .standard) }`.
- `switchOffContributing()` (§3a). `settingsChanged()` = `reconcile(current)` + `wake()`.

**When to call wake and settingsChanged:**
- `wake()` on `APIKeyManager.didChangeNotification`. This carries forward: `.incomplete` stops the loop until `wake()`, a settings change, Try Now, or a relaunch.
- `settingsChanged()` on the server address being committed, on the switch going ON, and on the mode picker changing.

**Settings tab:**
- The confirmation dialog and custom toggle binding (moved here from commit 7).
- **The server field commits on Return, on focus loss, or when the tab disappears (§2b), never per keystroke.**
- A caption by the field when untied entries exist: "2 waiting contributions aren't tied to a server yet. The first address you save here (press Return) is where they'll be sent, and the only place they'll ever be sent."

**View models:**
- §2d: the `queueSettingsProvider` seam, the keep plan, the keep-path recheck, and the promise flags.
- The factories build the identifier with the store even when `config == nil`, and pass `retrySchedule`.
- Update the 7 existing test construction sites to pass `nil` or a temp store explicitly (unchanged instruction).

**Launch and logging:**
- **Nothing is deleted at launch.**
- Activity Log lines come only from the act, plus an optional "2 waiting contributions are now tied to https://…" from reconcile reports.

**Tests (delivery):**
- Each view model with `.incomplete` (no key; address `https://db.example`), a temp store and a recording stub → `.queued`; 1 entry tied to that address; **0 requests**.
- With both missing → the entry is untied.
- `.off` → no file.
- Switched off mid-run → nothing kept.
- The address changed mid-run → nothing kept.
- **The order of the act:** an observer on `didChangeNotification` asserts `enabled == false` at the moment the purge posts. **Planted fault:** purge before write → fails.
- The address draft doesn't write until `commitAddress()`.
- The dialog text is built from `removalPreview`.

**Commit 6b (network back):** unchanged. `wake()` while off is harmless (the round is `.pausedBecauseOff`).

**Commit 7 (Settings list):**
- The list renders **outside** `if enabled` whenever entries exist, with the §3c captions.
- Rows show "Not tied to a server yet — it will go to the first server address you save, and only there", "Waiting for https://old — won't be sent to the server set above", and a paused state while off.
- Try Now is disabled while off.
- A "Trying again" section with the three controls. They must show any stored in-range value faithfully and write only in-range values; "never" writes 0. It also shows `plainDescription`.
- Flip the three registry entries to `.allowed(.connections, .int(bounds))`, and add the tab's scan-map entries.
- No "N of 200" text anywhere.
- The "How it works" text is computed, never "about three days".
- The view model caches the list and refreshes it on the notification, never reading it in `body`. With no limit, this matters more (see the HANDOFF note on commit 2).

**Commit 8 (settings group):**
- **Effective off is no longer a problem.** Entries import PAUSED: pending, `attemptCount 0`, due now, `importedAt = now`, destination as in the file. `groupUnavailable` stays only for "no store was passed".
- **The act of switching off inside an import:**
  - The preview warns: "This import turns off contributing to MeedyaDB on this Mac. That deletes the 3 contributions waiting to be sent; they won't be sent."
  - In apply, phase 2 (the fallible writes, via `commitImport`) stages the new list as empty. That is all-or-nothing with the profiles write.
  - Phase 3 writes the settings.
  - Then a belt-and-braces `removeAll(.contributionsOff)` runs AFTER the settings write, which normally removes 0. Any failure there is reported, not thrown.
  - This order gives the same race argument as §3a.
  - If the import would turn contributing off and `submissionQueue == nil`, throw with nothing changed. The builder checks existing importer tests whose target domain has `meedyadb.enabled = true` (none were found by grep, but check).
- **The CLI** must pass the Direct build's store whenever **Connections** is ticked, not only when the queue group is. The CLI's store uses `isContributingOn: { false }`.
- **Untied entries** are exported and imported. The preview says where they'll go: "2 aren't tied to a server yet; they'll be sent to https://y, the server set here, and only there", or "to the first server set up here".
- **No count caps** on import; the export refuses over 10 MB (§5).
- `SettingsExportSchema` reuses `$defs.submissionDestination`.
- The three schedule settings travel in Connections automatically.

**Commit 9:** the preview's per-entry list shows "paused (contributing is off here)" and "not tied yet". The CLI is unchanged in shape.

**Commit 10 (docs):**
- SECURITY.md F-015: "the act of switching off deletes; while off nothing is sent or deleted; entries can be kept while off (listed cases)"; untied entries and permanent tying; no count limit and the export refusal; the configurable schedule; the store refuses live saves while off.
- The original plan's §0, §3, §4 and §9 are marked superseded by this revision.

---

## 8. Carried forward (still true after this revision)

- Commit 6 must call `wake()` on key changes, because `.incomplete` pauses the loop's attention until `wake()`.
- Commit 6 must build `MeedyaDBQueueSettings` through `current(in:)` (5a), never by hand.
- The store guarding statuses outside 100–599 is closed by 5b.
- Commits 4–7 (now 4, 5, 5a–5g, 6, 7) land together, because the `.queued` wording points at commit 7's list.

---

## 9. Risks

1. **Tying to a typo is permanent** (the owner's rule). Mitigated by commit-on-Return, the caption, and per-row Delete. The server-field behaviour changes for everyone. Mention it in commit 6's message, and commit on disappear so an edit is never lost.
2. **Items can linger while off, indefinitely** (off outside the app, imported while off). By design; they are always visible in Settings.
3. **Performance without a cap.**
   - Every store call re-reads and decodes the whole file.
   - A round calls `store.entry(id:)` per entry, and every send success rewrites the file. That is O(n²) work for n due entries.
   - Realistic lists are tens, but hundreds after a long outage are possible.
   - 5d measures it. If 500 entries take more than about 5 s, add a follow-up (Opus): re-read only when the file's inode, size or modification time changed. Atomic writes always replace the inode, so a change is never missed.
4. **The gate closure runs under the store's lock.** It must stay a `UserDefaults` read. A Keychain read there could hang the main thread.
5. **`retrySchedule` and `schedule` default to `.standard`.** Production must pass the configured providers; the commit 6 tests pin the wiring.
6. **`removeAll(.contributionsOff)` must only be called by the act.** This is a grep check in each builder report (§3a).
7. **Export can now fail for size.** The wording must be clear. Commit 9 may show an estimate before Save.
8. **Schema v1 is changed in place.** That is safe only because nothing has shipped or been pushed. Re-check before pushing.
9. **Codex overlap:** 5a and 5f edit `MeedyaDBAccess.swift`, and commit 6 edits both view models (chunk 1's files). Build in the worktree.
10. **Minor, existing behaviour:** a spread first retry can come 54 s after a 429 whose `Retry-After` is 60. Optionally, floor step 1 at the configured first wait.
11. **Deleted tests must be replaced, not just removed.** Every test listed as "replaced" above has a delivery test standing in its place.

## 10. Open questions (only those the answers don't settle)

**Q-A. An import that turns contributing OFF and also brings waiting entries.**
- The act of switching off deletes this Mac's list. Should the file's own entries then be imported, paused?
- **Recommended: no.** Skip them and report it ("won't be imported, because this import also turns contributing off, which deletes everything waiting"). After the act of switching off, the list is empty, which is the simplest rule to explain.
- It also keeps the belt-and-braces purge after the settings write from deleting what was just imported.

**Q-B. Importing entries tied to a server when this Mac has NO server set (and the import doesn't set one).**
- The original plan skipped entries for any server other than the effective one.
- **Recommended:** import them, held until that server is set up here. Skip only when a DIFFERENT server is set here.
- Reason: with no count limit and Q12's "keep them" answer, dropping entries the user chose to export loses data for no privacy gain. They can only ever go to the server they were tied to.

**OWNER ANSWERS to section 10 (25 Sept 2026, ~17:50). Final:**
- **Q-A: YES, import them PAUSED** (NOT the recommendation). An import that turns contributing off first performs the act of switching off, which deletes THIS Mac's list (set-aside and newer-version files included). THEN it adds the file's own entries, paused (contributing is now off, so nothing is sent until it's switched on). Commit 8 must order this exactly so. The belt-and-braces purge after the settings write must run BEFORE the file's entries are stored, never after, or it would delete them. The preview must say both things plainly: "This Mac's 3 waiting contributions will be deleted, because this import turns contributing off. The file's 5 will be kept, paused, and won't be sent until contributing is switched on."
- **Q-B: import them, HELD for that server** (as recommended). Skip only when a DIFFERENT server is set here.
- **Server field: save on Return or on leaving the field, with a caption by the field when untied entries exist** (as recommended; the section 2b fix).

### Critical Files for Implementation
- Sources/ConverterEngine/Submissions/SubmissionQueueStore.swift
- Sources/ConverterEngine/Submissions/SubmissionQueueSender.swift
- Sources/ConverterEngine/Submissions/SubmissionQueueModels.swift
- Sources/ConverterEngine/Disc/MeedyaDBAccess.swift
- Sources/ConverterEngine/Submissions/SubmissionRetrySchedule.swift
- (also) `.../Submissions/SubmissionQueueSchema.swift` and `docs/schemas/submission-queue-v1.schema.json`; `.../Disc/MeedyaDBPublisher.swift` (normaliser); `.../Disc/MusicDiscIdentification.swift`, `VideoDiscIdentification.swift`; `.../Settings/SettingsKeyRegistry.swift` plus `Tests/ConverterEngineTests/SettingsSourceKeyScanner.swift` (scan map); `Sources/MeedyaConverter/Views/MeedyaDBSettingsTab.swift`; `Sources/MeedyaConverter/ViewModels/DiscIdentifyViewModel.swift`, `MakeMKVRipViewModel.swift`; `.../Settings/SettingsImporter.swift`, `SettingsExporter.swift` (commit 8); `Tests/ConverterEngineTests/SubmissionQueueTestSupport.swift`.