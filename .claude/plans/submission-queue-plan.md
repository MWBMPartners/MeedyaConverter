<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

> **Status: BUILDING (commits 1-5 built locally on `build/505-queue`; owner answers to section 9 recorded there, and a revision for them is being planned).** Originally: Opus deep-plan (read-only), 2026-09-25, against `b0de681`. Re-check line numbers by text before editing.

# #505 plan: a saved "waiting list" for MeedyaDB contributions

This is a read-only plan. Nothing was edited or committed. Suggested home once building starts: `.claude/plans/submission-queue-plan.md`.

**What I read.** Issue #505 in full. Issue #506 and its one comment ("implemented on the working branch, CI run 36132731028 passed"). `.claude/HANDOFF.md` (the current-state block and "#505, the parts that need care", lines 1401–1423). `.claude/local-test-harness.md`. All the code cited below, at `b0de681` on `wip/alpha-consolidation`.

**What I checked on the MeedyaDB server** (its `wip/bootstrap` branch, via `gh api`, before the rate limit hit):
- `docs/api-schema-design.md` §3/§4 says `disc_ingest` accepts an optional `Idempotency-Key` header. That header lets a server spot a repeat of the same request.
- `includes/api_envelope.php` answers a database outage with HTTP 503 and `Retry-After: 5`.
- `includes/api_keys.php` answers a rate limit with HTTP 429 and `Retry-After: 60`.
- `api.php` has no `Idempotency-Key` handling. The contract promises it; the server doesn't do it yet.
- The server does de-duplicate discs itself: it updates the existing row when the same `tocFingerprint` (plus `musicBrainzDiscId`) arrives again.

---

## 0. The short version

- **What is saved.** When a MeedyaDB contribution fails for a temporary reason (no connection, HTTP 5xx, HTTP 429), the app saves the exact, already-cleaned JSON it tried to send. Cleaned means the label is already removed in anonymous mode. The file lives in Application Support.
- **Who decides.** `MeedyaDBContributor` makes the decision, using one table. Permanent failures are never saved: 401/403, other 400-range errors, a bad address, or a reply that couldn't be read.
- **Who sends later.** One sender (a Swift actor) retries while the app is open. It waits longer after each failure, up to a 24-hour maximum. After 10 tries an item "stops trying" and waits for the user.
- **What it rechecks before every send:**
  - Contributions switched off → everything saved is deleted.
  - Mode narrowed from full to anonymous → the label is removed permanently, before sending.
  - Different server → the item is held and never sent anywhere else.
- **UI.** Settings › MeedyaDB shows the list. Each item can be viewed, retried or deleted.
- **Export/import.** It travels as a new #506 group, `submissionQueue`, off by default. Import checks every item, narrows it to the importing Mac's mode, and says in plain words that the items "will be sent as you, under your API key". Keys never travel.
- **The CLI** never saves or sends failed contributions.

---

## 1. The waiting-list model

### 1a. Where the code is today (and what has to change)
- **The request body isn't reproducible.** `MeedyaDBPublisher.buildRequest` (`MeedyaDBPublisher.swift:256–271`) encodes with a plain `JSONEncoder()` (line 269), so key order isn't fixed. It sends no `Idempotency-Key`.
- **The model can't be read back.** `MeedyaDBSubmission`, `MeedyaDBDisc`, `MeedyaDBIdentifier` and `MeedyaDBCandidate` are `Encodable` only (lines 64–141).
- **The one place labels are removed** is `buildSubmission` (lines 235–251).
- **`submit` does everything at once** (lines 278–322): it builds the body internally and sends it. So today nobody outside the publisher ever holds the exact body that was sent.
- **Status mapping in `submit`:**
  - 401 and 403 both become `.unauthorized` (line 314).
  - 429 becomes `.rateLimited` (line 316).
  - Every other non-2xx becomes `.httpStatus` with up to 200 characters of the server's reply (lines 318–320).
  - A 2xx reply that can't be decoded becomes `.malformedResponse` (lines 309–312), even though the server probably accepted it.

**Fix: one canonical body, and a separate send step** (commit 1):
- Add `Decodable` to the four model types, and `Codable` to `MeedyaDBSubmissionMode`.
- Add `public static func wireBody(for: MeedyaDBSubmission) throws -> Data`, using an encoder with `[.sortedKeys, .withoutEscapingSlashes]`. The same value always gives the same bytes.
- `buildRequest(for:idempotencyKey: String? = nil)` uses `wireBody` and sets the `Idempotency-Key` header when given. The new parameter has a default, so existing code still compiles.
- Add `public func send(_ body: MeedyaDBSubmission, idempotencyKey: String) async throws -> MeedyaDBIngestResult`, containing today's guards and status mapping.
- `submit(...)` becomes "build, then send with a fresh UUID". Its behaviour doesn't change.
- Add `public var destination: String?`: the normalised server address (trimmed, no trailing "/", scheme and host lower-cased).

### 1b. One entry — `QueuedSubmission`
New file `Sources/ConverterEngine/Submissions/SubmissionQueueModels.swift`. It is built to allow more services later.

| Field | Meaning | Exported? |
|---|---|---|
| `id: UUID` | the entry's identity | yes |
| `payload: SubmissionPayload` | `enum { case meedyaDB(MeedyaDBQueuedPayload) }`. Its `provider` is derived from the case. | yes |
| `MeedyaDBQueuedPayload.mode` | the mode the body was built under | yes |
| `MeedyaDBQueuedPayload.body: MeedyaDBSubmission` | the **already-cleaned** body. Its failable init refuses `mode == .anonymous` with a `labelText`, and a `body.submission` that disagrees with `mode`. So the type **cannot hold an uncleaned anonymous body**. | yes |
| `destination: String` | the normalised server the entry was saved for | yes |
| `idempotencyKey: String` (UUID) | the same key on every try of the same body | yes |
| `createdAt: Date`, `importedAt: Date?` | when it was saved; set when it arrived by import | yes / no (set by the importing Mac) |
| `state: .pending \| .stopped(reason)` | "stopped" means stopped trying. Reasons: `.tooManyAttempts`, `.rejected(httpStatus)`. | no |
| `attemptCount: Int` | starts at 1, because the first live try already failed | no |
| `lastAttemptAt: Date?`, `nextAttemptAt: Date` | used for the schedule and shown in the UI | no |
| `lastProblem: SubmissionProblem?` | `.noConnection`, `.serverError(status)`, `.rateLimited`. **Never the server's reply text:** a badly behaved server can echo request headers, which include the API key. | no |

Two values are computed, never stored or exported:
- **`dedupKey`** (the key used to spot duplicates) = `"meedyaDB|\(destination)|\(discType)|\(musicBrainzDiscId ?? tocFingerprint ?? sha256(canonical body without the label))"`. CryptoKit is already used in the engine (`MusicBrainzDiscID.swift`).
- **`displaySummary`**, e.g. "Audio CD · Nirvana — Nevermind" or "DVD · 12 titles".

### 1c. The store — `SubmissionQueueStore`
New file `Sources/ConverterEngine/Submissions/SubmissionQueueStore.swift`.

- **Location:** `~/Library/Application Support/MeedyaConverter/SubmissionQueue/queue.json`. The App Store build puts it in its sandbox container automatically. There is a folder so the import commit can stage a file beside it (§6).
- **Format:** `{ "format": "meedyaconverter.submission-queue", "version": 1, "entries": [ … ] }`.
  - Pretty-printed, sorted keys, ISO-8601 dates (the `APIKeyManager.saveKeys` style, `APIKeyManager.swift:1046–1050`).
  - Written with `.atomic`: macOS writes a temporary file and swaps it in, so the file is never half-written.
  - File permissions 0600.
- **Schema:** `docs/schemas/submission-queue-v1.schema.json`, generated by `SubmissionQueueSchema`, with a drift test and a real-file validation test (commit 3).
- **Order of every change:** check → write → update memory, the `EncodingProfileStore.upsertUserProfiles` rule. Before every change and every read, it **re-reads the file** (the F2 lesson from `APIKeyManager`).
- **Cap:** 200 entries (stopped ones included), and at most 16 KB of encoded body per entry. When full, **new ones are refused, never the oldest dropped**, and the user is told.
  - Why 200 × 16 KB: the settings file limit is 10 MB (`SettingsDocument.maximumFileSize`, line 76). The worst case must still fit when exported.
- **De-duplication on enqueue:** the same `dedupKey` replaces the older entry (pending or stopped) with the newer one. The result is `.replacedEarlier`.
- **API sketch (all synchronous, using `NSLock`; the lock is never held across an `await`):**
  - `entries()`, `entry(id:)`, `enqueue(_:) -> EnqueueOutcome` (`.added`, `.replacedEarlier`, `.refusedFull(limit)`, `.refusedInvalid`, `.unavailable(reason)`).
  - `update(id:_:) -> Bool`: **updates only if the entry still exists, never inserts**. A send that finishes after the user deleted the item can't bring it back.
  - `remove(ids:)`, `removeAll(reason:)`, `retryStopped(ids:)`.
  - `reconcile(meedyaDB: MeedyaDBQueueSettings) -> ReconcileReport`.
  - `commitImport(_:alongside:)` (see §6).
- **Notifications:** posts `didChangeNotification` **after unlocking**, exactly like `APIKeyManager.swift:313, 516–521`, because `NSLock` can't be re-entered.
- **Problem files:**
  - An unreadable file is renamed to `queue.unreadable-<date>.json`, never deleted. The store starts empty and `loadProblem` explains what happened.
  - A file written by a newer format version makes the store read-only (the #506 "newer format" stance).
- **Clock safety:** on load, `nextAttemptAt` is clamped to at most now + 24 h, in case the clock jumped.
- **The store never reads settings.** They are passed in as values, so its tests need no `UserDefaults` suite at all.

### 1d. Concurrency
- **One live store per app process:** `SubmissionQueueRuntime.shared.store` (app module, commit 6). Two instances rewriting one JSON file from stale memory is exactly the F2 bug. Re-reading before each change is the backstop.
- **The store is a lock-based `final class @unchecked Sendable`, not an actor.** `SettingsImporter.apply` and the exporter are synchronous (`SettingsImporter.swift:429`, `SettingsExporter.swift:123`), and SwiftUI reads counts synchronously. `EncodingProfileStore` (`EncodingProfile.swift:950–961`) is the model.
- **The sender is an `actor` with its own single-flight guard** (only one send-round runs at a time), via a stored `inFlight: Task<RoundReport, Never>?`. A second `runRound()` waits for the first. An actor alone does **not** prevent overlap once a method awaits: see the `PostEncodeHookRunner` lesson at `EncodingPersistenceActors.swift:119–136`.
- **Across processes:** the CLI never sends. The App Store and Direct builds have separate containers, so separate files.

---

## 2. The decision to save for later

### 2a. The table
It lives in **`MeedyaDBContributor`** as `public static func retryDisposition(for: MeedyaDBPublishError) -> MeedyaDBRetryDisposition`. It replaces the switch at `MeedyaDBAccess.swift:326–332`, and the sender uses the same function.

| Error (`MeedyaDBPublisher.swift:181–191`) | Result | Save now? | What the sender does with a saved item |
|---|---|---|---|
| `.disabled`, `.notConfigured` | `.notAttempted` | **No** | can't happen (readiness is checked first). Treated as "pause". |
| `.transport(_)` | `.retryLater` | **Yes** | try again later |
| `.httpStatus(500…599)` | `.retryLater` | **Yes** | try again later |
| `.rateLimited` (429) | `.retryLater` | **Yes** | try again later; the first wait is 60 s, matching the server's `Retry-After: 60` |
| `.httpStatus(408)` | `.retryLater` | **Yes** | the server timed out waiting for the request |
| `.unauthorized` (401/403) | `.fixSettings` | **No**; stays `.failed` with today's text | **pause the whole list**; no try counted; nothing deleted; "needs attention" |
| `.invalidURL` | `.fixSettings` | **No** | pause, as above |
| `.httpStatus` 400/404/409/413/422, other 4xx, 3xx | `.rejected` | **No** | this entry **stops trying** at once; the round continues |
| `.malformedResponse` (2xx that couldn't be read) | `.probablyDelivered` | **No**; stays `.failed` ("MeedyaDB may have received it") | remove the entry; log "accepted but unreadable reply; won't send again" |
| `CancellationError` | rethrown, as today | No | entry left exactly as it was; no try counted |

### 2b. Contributor flow (commit 4)
New parameter: `MeedyaDBContributor(publisher:submissionQueue: SubmissionQueueStore? = nil)`. It is also added, with a `nil` default, to both `MusicDiscIdentifier` inits (`MusicDiscIdentification.swift:291–309`) and to `VideoDiscIdentifier.init` (`VideoDiscIdentification.swift:147–153`). The CLI changes nothing.

Inside `contribute` (`MeedyaDBAccess.swift:292–336`):
1. The existing guards stay: `requested` (299), identity (302), and the F1 recheck and narrowing (306–314).
2. `let body = MeedyaDBPublisher.buildSubmission(... mode: modeToSend)`, then `let key = UUID().uuidString`, then `publisher.send(body, idempotencyKey: key)`.
3. On an error with disposition `.retryLater`:
   - **No queue, or no `recheck`** → `.failed` as today. Saving is only allowed when the caller gave a way to re-read settings, so the list can never hold data captured under settings that no longer apply. This rule is structural, not a convention.
   - Otherwise **call `recheck()` again, right before saving** (the settings may have changed during the up-to-20-second request, `timeoutInterval = 20`, line 265):
     - `nil` → **not saved**. Result: `.failed(reason: error + " MeedyaDB's settings changed while this disc was being sent, so it wasn't kept to send later.")`
     - A narrower mode → rebuild the body with `buildSubmission(... mode: narrower)` and use a new idempotency key.
   - `store.enqueue(entry)`:
     - `.added` or `.replacedEarlier` → **`.queued(reason:)`**
     - `.refusedFull` → `.failed(reason: error + " It wasn't kept to send later, because 200 contributions are already waiting. Retry or delete them in Settings › MeedyaDB.")`
     - `.unavailable` or `.refusedInvalid` → `.failed(... "couldn't be saved to send later: …")`

### 2c. New `MeedyaDBContribution.queued(reason: String)` case
Add it to `MusicDiscIdentification.swift:48–72`. `didSubmit` stays false; `reason` returns the text.

Wording, as named public constants on `MeedyaDBContributor` pinned by tests (the `withdrawnReason` pattern, line 232). The cause varies:
- no connection: "MeedyaDB couldn't be reached"
- 5xx: "MeedyaDB had a problem on its side (HTTP 503)"
- 429: "MeedyaDB asked for fewer requests for now"

…followed by: ", so this disc is waiting to be sent. MeedyaConverter tries again by itself while it's open. You can see or delete it in Settings › MeedyaDB."

Note the words "while it's open": there is no background helper. The claim must match that.

**Every exhaustive switch over `MeedyaDBContribution`** (grep of `Sources/` and `Tests/`):
- `MusicDiscIdentification.swift:64–71` (`reason`).
- `DiscIdentifyView.swift:295–313`: add a case with `Label(reason, systemImage: "clock.arrow.circlepath")` in secondary colour, not orange.
- `MakeMKVRipView.swift:409–424`: same styling.
- `DiscCommand.swift`:
  - 505–515 (exit code): `.queued` with `--submit` → the general-error exit, same as `.failed`. It can't actually happen, because the CLI passes no queue.
  - 648–659 (text): "MeedyaDB: waiting to be sent — …".
  - 774–787 (JSON): `Contribution(status: "queued", reason:)`.
  - `docs/api/meedya-convert-api.yaml` (~1376–1389): document "queued" as "never produced by the command line".
- **Tests:** none switch exhaustively over it. They use `if case`, `guard case` or `XCTAssertEqual`, so no test edits are forced.

---

## 3. Privacy

- **Why the cleaned body, not the inputs.** The inputs (`MeedyaDBDiscSubmissionInputs`, `MeedyaDBSubmissionBuilder.swift:49–74`) keep the label even in anonymous mode (`MusicDiscIdentificationResult.submission` doc, lines 206–214). If the inputs were saved and the user later switched to `full`, a label captured under "anonymous" would be sent. So:
  - no list API accepts `MeedyaDBDiscSubmissionInputs`;
  - the only door is a `MeedyaDBSubmission` that has already been through `buildSubmission`;
  - `MeedyaDBQueuedPayload`'s failable init refuses an anonymous body carrying a label.
- **"Never save while off", enforced five times:**
  1. The GUI passes `requested = (readiness.config != nil)` (`DiscIdentifyViewModel.swift:263–265`, `MakeMKVRipViewModel.swift:850–851`). Off means `.notAttempted` before any network call.
  2. The existing F1 recheck before sending.
  3. The **new recheck right before saving** (§2b).
  4. Saving requires a `recheck`, structurally.
  5. The sender, at the start of every round and at launch: if readiness is `.off`, `removeAll(.contributionsOff)`, including stopped items and any set-aside unreadable files.
  - On top of that, the Settings toggle deletes everything the moment it goes off (§5). The on-disk list is always empty while off.
- **The recheck before every send** (the F1 principle, adapted for data that waits days). Settings are read fresh for each entry, cheaply, without the Keychain:
  - `MeedyaDBConfigStore.isEnabled`, `baseURL` and `submissionMode` (`MeedyaDBAccess.swift:53–70`) are read per entry.
  - The full readiness (which reads the Keychain) is read once per round.
  - **Off** → delete everything and stop.
  - **Mode narrower than the entry's** → **clean it again and save it permanently before sending**: `buildSubmission(... mode: .anonymous)` on the stored body, with a new idempotency key. This is a one-way ratchet: switching back to `full` never brings a label back. It is the same "narrower" rule as F1 (`MeedyaDBSubmissionMode.narrower`, `MeedyaDBPublisher.swift:58–60`).
    - The Settings picker also triggers `reconcile` immediately, so labels leave the disk as soon as the user narrows.
    - Recommended over deleting (which loses the identity part the user still wants) and over "drop the label but keep `submission: full`" (which makes the body lie about itself).
  - **Server changed** → the entry is **held**: never sent, never deleted automatically, shown as "waiting for https://old.example; won't be sent to the server above". It resumes if the server is changed back. The user can delete it.
    - Why not withdraw (delete) as F1 does: the server field is `TextField(text: $baseURL)` bound to `@AppStorage` (`MeedyaDBSettingsTab.swift:40, 105–109`). It writes on **every keystroke**, so an eager withdraw would wipe the list as soon as one character was typed.
    - Holding gives the same privacy result as F1: nothing goes to a server the entry wasn't saved for.
  - **API key changed** → entries are **kept** and sent with the key saved *now*.
    - The key only proves who is sending. It doesn't change what is sent or where.
    - Tying entries to a key would mean storing a key or a hash of it in an exportable file.
    - The UI says so plainly. This is an owner question (§9).
  - **API key removed** (readiness `.incomplete`) → no sends; entries kept; status shows the #507 reason.
- **The user can delete anything:** one item, or "Delete All…" with a confirmation. The UI also shows exactly what each item will send (§5).
- **What's stored never contains:**
  - the API key (it is added as a request header at send time, `buildRequest` line 266);
  - server reply text;
  - file paths.

---

## 4. The sender — `SubmissionQueueSender`
New `actor`, file `Sources/ConverterEngine/Submissions/SubmissionQueueSender.swift` (commit 5).

- **What it's given:**
  - the store;
  - `readiness: @Sendable () -> MeedyaDBReadiness`;
  - `settings: @Sendable () -> MeedyaDBQueueSettings` (cheap, no Keychain);
  - an `httpClient`;
  - `now`, `jitter`, and `schedule`.
  - The engine has no Keychain access, by design (`MeedyaDBAccess.swift:15–22`). The app supplies these.
- **When rounds run:**
  - **At app launch:** `reconcile` immediately, then the first round 30 s later.
  - **On a slow timer:** the next wake time is the later of the break-time (see below) and the earliest `nextAttemptAt`. The loop sleeps in steps of up to 60 s and makes **no network call unless something is due**.
  - **"Try Now"** in Settings: `runRound(force: true)`, which ignores wait times for pending items.
  - **After a successful live contribution:** the server is evidently up, so `runtime.wake()` runs a round. Cheap and optional.
  - **When the network comes back:** recommended as an optional commit 6b using `NWPathMonitor`. It isn't used anywhere in `Sources/` today (grep).
- **One round:**
  1. Check readiness: `.off` → delete everything and stop; `.incomplete` → pause.
  2. `reconcile`.
  3. Take pending entries whose wait is over, oldest wait-time first.
  4. For each: **fetch it fresh from the store** → recheck settings (§3) → `MeedyaDBPublisher(config: current).send(body, idempotencyKey:)` → classify with `MeedyaDBContributor.retryDisposition`.
     - Success: remove it.
     - `.rejected`: stop that entry; continue.
     - `.retryLater`: `attemptCount += 1`, set the next wait or stop it, then **end the round**.
     - `.fixSettings`: end the round; status `.needsAttention` (cleared by a settings change, a key change via `APIKeyManager.didChangeNotification`, Try Now, or a relaunch).
     - `.probablyDelivered`: remove it and log.
- **Round-level pause.** After a round that ends with a temporary failure and no success, `pausedUntil = now + schedule[consecutiveFailedRounds]`. It resets on any success. While the server is down this costs **one request per round**, however long the list, and the rounds get further apart. Kept in memory only; a relaunch simply tries once.
- **Wait schedule** (waiting longer after each failure; ±10% randomness so many Macs don't retry at the same moment). After try k fails, the next try is in 1 min, 5 min, 15 min, 1 h, 3 h, 6 h, 12 h, then **24 h, the maximum**.
- **Stop-trying rule:**
  - An entry stops after its **10th** failed try (about 3 days of tries while the app is open), or at once on `.rejected`.
  - Stopped entries are never retried automatically. They stay visible, count toward the cap, are deleted when contributions go off, and aren't exported.
  - "Try Again" puts one back to pending with `attemptCount = 0`.
- **Cancellation.** The runtime keeps the loop's task and cancels it when the app quits. `sender.cancel()` cancels `inFlight`. A cancelled send leaves the entry untouched, via `update`-if-present.
- **Stated limit** (same as F1): a request already handed to URLSession can't be recalled. If the user switches off mid-send, that one send may still complete. The following `remove` or `update` does nothing, and nothing is brought back.
- **Never while off:** the readiness check at the start of every round and the per-entry settings check.
- **The CLI does not save or send failed contributions:**
  1. It is a one-shot process. Nothing survives to retry, and anything it saved would later be sent by the app under the app's settings, surprising the script's author.
  2. `--submit` promises a clear exit code (`DiscCommand.swift:499–515`). "Queued" is neither success nor failure, so the honest non-zero exit stays.
  3. Two programs writing one file is the F2 bug. The #506 CLI already refuses `--apply` while the app is open, for this reason (`SettingsCommand.swift:465–473`).
  4. The App Store build's list is in its sandbox, which the CLI can't reach (`SettingsCommand.swift:37–45`).
  - The CLI *does* export and import the list as a settings group (§6).
- **Where the loop is started: `MeedyaConverterApp`'s main-window `.onAppear`** (`MeedyaConverterApp.swift:140–158`, next to `refreshRemoteFeatureFlags`). `start()` does nothing after the first call.
  - **Not `AppViewModel.init`**: tests build `AppViewModel()` (`AutoTagAppWiringTests`). A developer Mac with MeedyaDB switched on and a real key would otherwise start a real sender inside `swift test` and send real data.

---

## 5. UI

- **Settings › MeedyaDB** (`MeedyaDBSettingsTab.swift`) gets a **"Waiting to be sent"** section inside the existing `if enabled` block (lines 63–69). It is backed by a new testable `SubmissionQueueViewModel` (app module, `@MainActor @Observable`) that refreshes on the store's `didChangeNotification`.
  - **Summary:** "3 contributions are waiting to be sent to MeedyaDB. Next try: about 14:05." / "Nothing is waiting to be sent." / "2 stopped trying — see below."
  - **Sender status:** "MeedyaDB couldn't be reached at 13:02." / "Paused: MeedyaDB rejected the API key. Replace it above. Nothing waiting has been deleted." / the #507 incomplete reason.
  - **How it works:** "MeedyaConverter only tries while it's open: soon at first, then less often. After about three days of trying it stops, and keeps the item here until you try again or delete it." That is exactly what's built; there's no "when you're back online" unless 6b ships.
  - **Each row** (behind a "Show what's waiting" disclosure):
    - kind and identity ("Audio CD · Nirvana — Nevermind", or the Disc ID if nothing matched);
    - "Queued 25 Sep 13:02 · tried 3 times · last: MeedyaDB had a problem on its side (HTTP 503)";
    - **"Sends: identity only"** or **"Sends: identity and the label ‘MY HOLIDAY 2009’"**;
    - "Imported from a settings file on 25 Sep" when relevant;
    - "Waiting for https://old.example — won't be sent to the server set above" for held entries;
    - Delete; "Try Again" on stopped entries;
    - a disclosure **"What will be sent"** showing the pretty-printed canonical body. Same content as the wire; only the whitespace differs, so don't call it "the exact bytes".
  - **Buttons:** "Try Now" and "Delete All…" (`confirmationDialog`: "Delete all 3 waiting contributions? They won't be sent.").
  - **Captions that make promises, each backed by code:**
    - Under the toggle, when the count is above zero: "Turning this off deletes the 3 contributions waiting to be sent." Backed by `.onChange(of: enabled)`, then `store.removeAll`.
    - Under the privacy picker, when an entry carries a label: "Choosing ‘Just the disc's identity’ also removes the label from the 2 waiting contributions that carry one." Backed by `.onChange(of: submissionMode)`, then `reconcile`.
    - Under the server field, when entries exist: "Waiting contributions are only ever sent to the server they were saved for."
    - Near the API key: "Waiting contributions are sent with whichever key is saved when they're retried."
    - `loadProblem` text, when a damaged file was set aside.
  - **Wording trap:** never put the words "Application Support" inside a Swift string literal. `SettingsSourceKeyScanner.findApplicationSupportLiterals` (lines 365–377) flags any quoted line containing them. Say "the app's own folder".
- **Disc screens:** the `.queued` line (§2c).
- **Activity Log** (`appendLog`, category `.metadata` as #508 uses):
  - "Sent 3 waiting contributions to MeedyaDB."
  - "A waiting contribution stopped trying: MeedyaDB refused it (HTTP 400)."
  - "Contributing was switched off, so 2 waiting contributions were deleted."

---

## 6. The #506 integration

- **New group:** `SettingsCategory.submissionQueue`. Its raw value is written into files, so it must never be renamed (`SettingsCategory.swift:15–18`).
  - `displayName`: "Contributions waiting to be sent".
  - `explanation`: "Discs this Mac identified but couldn't send to MeedyaDB yet, exactly as they would be sent. Only ones still waiting are included."
  - **`includedByDefault = false`** (the reasons are in §9, Q7).
  - `warning`. It is shown on both the export tab and the import sheet, so it's worded for both: "The file lists the discs waiting to be sent from this Mac, and any disc labels you chose to send with them. Whoever imports it can send them to MeedyaDB under their own API key. Your API key is never included."
  - A new `itemNoun` ("setting" / "profile" / "waiting contribution"). It replaces the two `category == .encodingProfiles ? "profile" : "setting"` copies (`SettingsExporter.swift:70`, `SettingsCLIReport.swift:286`).
- **Handler:** `SettingsSubmissionQueueSectionHandler`, added to the exhaustive switch at `SettingsSectionHandlers.swift:160–167`.
  - Section shape: `{ "entries": [ … ] }`, exported fields only (§1b).
  - `SettingsValidatedSection.Content` (lines 123–128) gains `.submissions([SubmissionImportItem])`.
  - The other switches that must change: `SettingsImportPlan.itemCount` (`SettingsImporter.swift:104–108`) and `changes(for:)` (568–639).
  - `SettingsExportSource` (lines 137–142) gains the pending entries.
  - Unknown fields at group or entry level are reported and ignored (room for later versions). Unknown fields **inside `body`** refuse the whole file.
- **Checks in `prepare`** (static; one bad entry refuses the whole file, matching #506):
  - `provider` known. An unknown provider (from a later version) is ignored and reported.
  - `mode` is one of anonymous or full, and **`body.submission == mode`**.
  - **anonymous with a `labelText` → refuse**.
  - Decodes as `MeedyaDBSubmission` and has a usable identity (the `hasUsableIdentity` rule, `MeedyaDBSubmissionBuilder.swift:68–73`).
  - Length and count limits: labels and titles ≤ 1,024 characters; ≤ 64 identifiers and ≤ 64 candidates; `confidence` between 0 and 1; body ≤ 16 KB; total entries ≤ 200.
  - `destination` is https or http and passes `SettingsAddressCheck` (no user name, password or query string).
  - Ids unique; `idempotencyKey` is a UUID.
  - **Credential scan:** any string anywhere in the group matching `(?i)mdk_(live|test)_` (MeedyaDB's key format per the server's schema doc) → refuse.
  - Refusal reasons follow the existing `SettingsImportError.invalidValue` wording; values are never echoed (`SettingsTransferErrors.swift:22–25`).
- **Preview and apply** (`changes(for:)`, computed **after** the other groups so it sees them):
  - **Effective MeedyaDB settings** = the file's `meedyadb.enabled`, `meedyadb.baseURL` and `meedyadb.submissionMode` when Connections is ticked (following its writes and removals in merge or replace mode); otherwise this Mac's own snapshot.
  - **Effective off** → the group has a problem and applying throws. New error: **`SettingsImportError.groupUnavailable(category:reason:)`**, worded "…can't be imported: contributing to MeedyaDB is turned off on this Mac, and nothing is kept while it's off. Untick it to import the rest. Nothing was changed." It needs a case in `errorDescription` and in `SettingsCommandSupport.exitCode` (`SettingsCommand.swift:225–242`, mapped to `.validationFailed`).
  - No effective server → the same kind of problem.
  - Entries for a **different server** → skipped and reported, never held.
  - **Narrowed** to the effective mode before storing (full → anonymous removes the label).
  - **Merge:** matched by `dedupKey`. The copy already waiting here wins ("already waiting here").
  - **Replace:** removes this Mac's pending entries. `replaceConfirmation` names them ("This removes 3 waiting contributions").
  - The combined list must be ≤ the cap, otherwise the group has a problem.
  - Imported entries arrive as `pending`, `attemptCount 0`, `nextAttemptAt = now`, `importedAt = now`.
- **Staying all-or-nothing.** Today profiles are "the only write that can fail" (`SettingsImporter.swift:463–487`); the list is a second one. Use **`store.commitImport(newEntries, alongside: { try profileStore.upsert/replace… })`**:
  - Inside the store's lock: write `queue.json.staged` (can fail, nothing changed) → run the profile write (can fail: delete the staged file and rethrow) → rename the staged file over `queue.json` (effectively never fails on one volume) → update memory → post the notification.
  - Settings are then written as today.
  - This needs no undo step, and the sender can't slip in between.
  - If the group isn't ticked, the profile write runs exactly as now.
- **Preview wording.** It goes in `preview.warnings`, shown by both the sheet's "Warnings" callout and the CLI's "Warnings:" list. Only when the group is ticked. Pinned as a constant:
  > "Importing these means MeedyaConverter will send them to MeedyaDB at https://db.example **as you, using the API key saved on this Mac**, the next time it can reach the server. They describe discs identified on the Mac that made this file. The file itself never contains an API key."
  
  Plus, when relevant: "2 include the text printed on the disc, but this Mac sends only the disc's identity, so that text is removed before they're kept." and "1 was waiting for a different server (https://x) and won't be imported."
- **Results and reports:**
  - `SettingsGroupPreview` and `SettingsImportResult` gain `submissionChanges: SettingsListChanges?` (`SettingsValueCodecs.swift:99–109`), used by `summary`, `changeCount`, the CLI's `addedUpdatedRemoved` (`SettingsCLIReport.swift:228–238`) and `SettingsImportReport.lines`.
  - Result line: "Added 2 waiting contributions. MeedyaConverter will send them to MeedyaDB as you, under your API key."
  - If no MeedyaDB key is saved here, the "still needed" list says "MeedyaDB key — the imported contributions wait until one is saved". That's a small addition to `SettingsCredentialNeeds.compute`, because `meedyaDBKey.relatedCategory` is only `.connections`.
- **Registry:** the `SettingsKeyRegistry.fileStores` entry `"SubmissionQueue/queue.json"` / `"SubmissionQueueStore.swift"`. It goes in as `.never(reason: "not exported yet (#505 commit 8)")` in commit 2, then flips to `.allowed(.submissionQueue)` in commit 8. The tripwire at `SettingsKeyCoverageTests.swift:268–281` requires one entry per file that uses `applicationSupportDirectory`.
- **Schema:**
  - `SettingsExportSchema.categorySectionSchema` (`SettingsExportSchema.swift:221–259`) turns its `if category == .encodingProfiles` into an **exhaustive `switch`**. The queue branch uses shared `$defs` from `SubmissionQueueSchema`.
  - `additionalProperties: false` at every level of `body`. **Leak safeguard 4:** an `apiKey` field anywhere fails the schema.
  - The honest-limits comment must say the "anonymous means no label" rule is enforced in code, not the schema: the mini checker has no `if/then` (`SettingsSchemaMiniValidator.swift:18–21`).
  - Regenerate `settings-export-v1.schema.json` and `settings-cli-report-v1.schema.json`, whose category enum comes from `allCases` (`SettingsCLIReportSchema.swift:204, 279`).
- **Exporter/importer injection:** `SettingsExporter` and `SettingsImporter` gain `submissionQueue: SubmissionQueueStore? = nil`, so the many existing test call sites keep compiling.
  - Export with `nil`: the group is left out, with an export note ("isn't available here"), and not listed as exported. Honest, never a false "0".
  - Import with `nil`: the group has a problem.
  - The app (`SettingsTransferTab.swift:64–85`, into `SettingsTransferViewModel.init` at 121–140) and the CLI **must** pass real stores.
  - `didApply` → `runtime.settingsChanged()` → `reconcile` and `wake`.
- **CLI:**
  - `SettingsIncludeOption` (`SettingsCommand.swift:94–96`) gains `submissionQueue = "submission-queue"`, and `--include` becomes repeatable (`[SettingsIncludeOption]`; the enum was built for this).
  - Warnings print for every ticked group that has one, not just `thisMac` (lines 325–327, 458–460).
  - Help text lists at lines 294 and 427.
  - Hidden `--queue-dir` option for tests; the #506 "app is running" guard covers the list too.
  - Store: `SubmissionQueueStore(directory:)`, the Direct build only, with the same App Store limit wording.

---

## 7. Tests (each proves delivery)

**Engine** (ConverterEngineTests; each file can run locally with the `.claude/local-test-harness.md` recipe, and needs a deliberate-fault check; results are reported as "ran locally in a harness"):

1. **Canonical body and header.**
   - `wireBody` gives identical bytes twice, with keys sorted.
   - `buildRequest` sets `Idempotency-Key`.
   - `submit` behaves unchanged. The existing `MeedyaDBPublisherTests` must stay green.
2. **Disposition table.** Every `MeedyaDBPublishError` case, plus statuses 400, 404, 408, 409, 413, 422, 500, 502, 503, 504 and 301, each map as in §2a.
3. **Temporary failure saves it; a later success sends the SAME bytes.**
   - The contributor's stub HTTP client (records bodies and headers) returns 503, giving `.queued`.
   - Then a **new** `SubmissionQueueStore` over the same folder (a simulated restart) plus the sender, with a stub returning 200 and `runRound(force:)`.
   - Assert the second body is byte-identical to the first, the `Idempotency-Key` headers match, and the store ends empty.
4. **401, 403, 400, 422, invalidURL and a 2xx with an unreadable reply are never saved:** result `.failed`, and the list file doesn't exist or has zero entries.
5. **Off never saves.**
   - `requested:false` gives `.notAttempted` and no file.
   - A publisher with `enabled:false` → `.disabled` → nothing saved.
   - A recheck returning full on its first call and `nil` on its second (a lock-guarded counter class, **not a captured `var`** — see the `d602cf0` lesson) → not saved.
   - A queue passed without a `recheck` → not saved.
6. **The cleaned body is what's stored.** Anonymous mode with input label "SENTINEL-…": read the list file's **bytes** and assert the sentinel never appears.
7. **Mode narrowed after saving never sends the label.** Saved under full; the settings provider then says anonymous; the round's body has no `labelText`, has `"submission":"anonymous"`, and the file no longer contains the label.
8. **Narrowing at save time** (the recheck returns anonymous) stores an anonymous body.
9. **Stop-trying after 10.** An always-503 stub, a fake clock moved past each wait and break; after the 10th failure the state is `.stopped(.tooManyAttempts)`, and one more round makes zero requests.
10. **Wait schedule values** (jitter fixed at 1.0) and the 24 h maximum.
11. **Round-level pause:** 3 due entries with a 503 server → **exactly one request** per round.
12. **401 during a round:** no try counted, `.needsAttention`, entries intact. **400:** that entry stops and the round continues to the next.
13. **Single-flight:** two concurrent `runRound()` calls against a slow, gated stub → requests not doubled.
14. **Cancellation mid-send:** entry unchanged. **Switched off mid-send:** after the send, the entry is not brought back.
15. **Different server:** the entry is held; zero requests; not deleted.
16. **Cap and de-duplication.**
    - Cap: limits injected at 3; the 4th contribution gives `.failed` with the "already waiting" wording, and the count stays 3.
    - De-dup: the same disc twice gives one entry, with the newer body.
17. **Store behaviour.**
    - Survives a restart (a new instance reads equal entries).
    - An unreadable file is set aside, not deleted, with `loadProblem` set.
    - A newer-format file makes the store read-only.
    - Two instances over one file keep both enqueues (re-read before each change).
    - The notification is posted after unlocking: a handler calling back into the store doesn't deadlock. Observers filter by `object`, the F10 lesson.
    - `update`-if-present.
18. **Schemas.**
    - Drift tests for `submission-queue-v1.schema.json` and the regenerated export and CLI-report schemas.
    - A real store file validates.
    - A real export including the queue group validates.
    - A hand-made entry with `apiKey` fails the schema.
19. **Settings integration** (reusing `SettingsTransferFixture`, which already names test settings suites by a path inside a created "Preferences" folder, with no `.plist` suffix — the macOS 15 CI rule):
    - **Round trip:** export the group → import on a second domain and store (on, same server) → equal body, key and destination; `pending`; `importedAt` set.
    - Off by default in `SettingsExporter.defaultCategories` and in `plan.defaultSelection`.
    - Export writes pending entries only; stopped entries produce a note.
    - **Refusals, each leaving the whole file refused and nothing changed:** anonymous with a label; `submission` not equal to `mode`; an `mdk_live_` string anywhere; an unknown field in `body`; > 200 entries.
    - **Preview wording:** `preview.warnings` contains the pinned "as you, using the API key saved on this Mac" sentence only when the group is ticked.
    - **Off on the importing Mac:** the group has a problem, apply throws `groupUnavailable`, and the settings and list files are byte-identical before and after.
    - Connections ticked and turning MeedyaDB on → allowed.
    - Full → anonymous narrowing on import.
    - Other-server entries are skipped and reported.
    - Merge by `dedupKey`; Replace confirmation wording.
    - **All-or-nothing:** a profile write forced to fail (a *file* where the profiles folder should be, as `SettingsRoundTripTests.swift:397–401` does) leaves the list file byte-identical.
    - **Tests that must be updated deliberately:**
      - `test_thisMacIsOffByDefaultAndEverythingElseIsOn` (`SettingsKeyRegistrySentinelTests.swift:201–208`): both `thisMac` and `submissionQueue` are off with a warning.
      - `test_encodingProfilesAreTheirOwnGroupAndTheOnlyFileThatTravels` (210–219): exactly two travelling files; `entries(in: .submissionQueue)` is empty.
      - `test_thisMacIsExcludedFromTheDefaultExport` (`SettingsExportNoSecretTests.swift:229–245`) stays green unchanged, which proves the new group is off by default.
    - **No-secret test:** a live try with publisher key `mdk_live_SENTINEL…` fails with 503 → saved → export every group → the sentinel is absent from the file bytes.

**App** (MeedyaConverterCoreTests; type-checked locally with the "A REAL local test-file type-check" recipe in HANDOFF, run by CI):

20. `DiscIdentifyViewModel` and `MakeMKVRipViewModel` with a temporary-folder store and a stub returning 503: `result.contribution` is `.queued`, and the store has 1 entry. With MeedyaDB off, 0 entries.
21. `SubmissionQueueViewModel`: the rows show the label text only for full-mode entries; delete, delete-all and try-again reach the store; the off toggle deletes everything.
22. `SettingsTransferViewModel`: the group appears unticked, and the preview warnings contain the pinned sentence.
23. **Wiring** (promise vs delivery): `SettingsTransferTab`, `MeedyaDBSettingsTab` and both view models' default factories use `SubmissionQueueRuntime.shared.store`, compared by identity without changing anything. `MeedyaConverterApp` starts the runtime.
    - Grep check, part of each builder's report: every `Sources/` reference to `SubmissionQueueSender` or `SubmissionQueueRuntime` outside its own file must include a **non-test** caller.

**CLI** (MeedyaConvertTests, CI):

24. `settings export --include submission-queue --queue-dir <tmp>` followed by `import --apply` does the round trip. The preview JSON has `warnings` containing the sentence.

---

## 8. Commits, in order (each compiles and passes on its own)

1. **`feat(meedyadb): one fixed request body, sent with an Idempotency-Key (#505, 1/10)`** — **Sonnet**.
   - `Codable` model types; `wireBody`; `send`; `buildRequest(idempotencyKey:)`; `destination`.
   - `MeedyaDBContributor.retryDisposition` (not yet used for saving).
   - Tests 1–2. No user-visible change.
2. **`feat(engine): a saved waiting list for contributions (#505, 2/10)`** — **Opus**.
   - Models, store, the MeedyaDB payload type with its failable cleaned-body init, and dedup.
   - The `fileStores` `.never` entry.
   - Tests 16–17. New files only, plus one registry line.
3. **`feat(schema): JSON Schema for the waiting-list file, checked by a test (#505, 3/10)`** — **Sonnet**.
   - `SubmissionQueueSchema`, the committed file, drift and validation tests.
4. **`feat(meedyadb): keep a contribution that couldn't be sent, and say so (#505, 4/10)`** — **Opus**.
   - The `.queued` case and **every switch listed in §2c**, including the CLI's three and the API yaml.
   - The contributor's save logic; the identifiers' `submissionQueue` parameter.
   - Tests 3 (save half), 4–6, 8.
5. **`feat(engine): send waiting contributions again, waiting longer each time (#505, 5/10)`** — **Opus**.
   - The sender, with the round-level pause and single-flight.
   - Tests 3 (send half), 7, 9–15.
6. **`feat(app): the disc screens keep what couldn't be sent, and the app sends it later (#505, 6/10)`** — **Sonnet builds; Opus checks.**
   - `SubmissionQueueRuntime` (app module).
   - Both view models gain `submissionQueue: SubmissionQueueStore? = SubmissionQueueRuntime.shared.store`. Their factories become `(config, queue)` and `(config, tmdb, queue)`.
   - **Update the 7 test construction sites** (2 in DiscIdentifyViewModelTests, 5 in MakeMKVRipViewModelTests) to pass `nil` or a temporary store **explicitly**, so no test ever touches `.shared`.
   - Start from `MeedyaConverterApp`; Activity Log lines; the MeedyaDB tab's switch-off purge and mode `reconcile`.
   - Tests 20, 23.
   - 6b (optional, **Sonnet**): `feat(app): try again as soon as the network comes back` — `NWPathMonitor` behind a small wrapper, tested with a fake.
7. **`feat(ui): see, retry and delete what's waiting, in Settings › MeedyaDB (#505, 7/10)`** — **Sonnet builds; Opus checks the wording against the code.** `SubmissionQueueViewModel` and the section; test 21.
8. **`feat(settings): the waiting list as its own group in a settings file (#505, 8/10)`** — **Opus.**
   - The group and its properties, the handler, the `Content` case, effective settings, merge and replace, the cap, narrowing, the "as you" warning, `groupUnavailable`, `commitImport`, the result and report fields, the "still needed" key line, the `fileStores` flip, the schema switch and **both regenerated schemas**.
   - **Also the one-line store injection in `SettingsTransferTab`/`ViewModel` and `SettingsCommand`.** The new toggle appears automatically via `ForEach(SettingsCategory.allCases)` (`SettingsTransferTab.swift:119`), so the store must be passed in the same commit, or the toggle would do nothing.
   - Tests 18–19. This is the largest commit, comparable to #506 5/9.
9. **`feat(ui,cli): the waiting list in Import & Export and meedya-convert settings (#505, 9/10)`** — **Sonnet builds; Opus checks.**
   - The preview sheet's per-entry list (add / already waiting / remove).
   - The CLI's repeatable `--include submission-queue`, warnings for every group, help text, `--queue-dir`, the API yaml.
   - Tests 22, 24.
10. **`docs: the waiting list — what's kept, for how long, and what never is (#505, 10/10)`** — **Sonnet.**
    - Help topics `disc-tools.md` and `settings-transfer.md`; `docs/FAQ.md` (privacy); `docs/Disc-Tools.md`.
    - **SECURITY.md F-015**: what is stored, that it holds no key, cleaned bodies, switch-off deletes, no reply text stored.
    - README, FEATURES, CHANGELOG, Home, Architecture.
    - The plan marked IMPLEMENTED, with a "where the build differed" section.

**Builder rules** (from HANDOFF):
- Never `git stash`; use a temporary commit.
- Never delete Keychain items by hand. These tests need no Keychain at all: settings come from closures and fake keys.
- No broad `pkill` or `killall`.
- Type-check test files for real; `-parse` is not enough. Grep for captured `var`s changed inside `@Sendable` closures.
- Rebuild the engine before every harness run.
- Watch CI by `headSha`, with a deadline (W16).
- A push cancels the CI run in progress, so batch pushes.

---

## 9. Risks, and questions for the owner (with my recommended answer)

**Risks:**
- **Tests touching real data:** a sender started outside the App scene, or a test relying on a default parameter, could read or send the real list. Mitigations are in §4 and commit 6.
- **Duplicates after a timeout:** the server may have saved the disc even though no reply arrived. The server updates by `tocFingerprint` today, but ignores `Idempotency-Key`. → **Raise a MeedyaDB issue** to honour it, plus `Retry-After` (a follow-up here).
- **Body key order changes:** harmless, because the server parses JSON; mentioned in the commit 1 message.
- **Settings import is no longer the only fallible write:** handled by `commitImport`. A rename failing on one volume is the remaining theoretical gap; say so in the code.
- **Scanner traps:** the words "Application Support" in string literals; mentioning `applicationSupportDirectory` in more than the one place per store file (full-line comments are stripped, trailing ones aren't: `SettingsSourceKeyScanner.swift:214–224`); duplicate file names across folders.
- **Promise vs delivery:** the UI's `.queued` branches can't be reached until commit 6. Land commits 4–6 together before any PR.
- **Live check is blocked:** MeedyaDB isn't hosted yet (HANDOFF queue row 8), so nothing can be tested end to end against a real server.

**Owner questions:**
1. **Cap:** 200 entries, refusing new ones when full (never silently dropping the oldest)? *Recommend yes.*
2. **Save when contributing is on but MeedyaDB isn't fully set up** (the issue said "probably yes")? *Recommend no in version 1.* With no server there is nowhere agreed to send to, it can grow indefinitely, and the handoff rule lists temporary failures only. Today's #507 "declined" wording stays.
3. **Mode narrowed after saving:** remove the label permanently before sending (recommended), withdraw the entry, or keep it full? *Remove it permanently.*
4. **Server changed:** hold and never send elsewhere (recommended), or delete automatically as F1 does? *Hold*, because the address field saves on every keystroke.
5. **API key changed:** keep the entries and send with the key saved now (recommended), or delete them? *Keep*, and say so in the UI.
6. **Switching off:** delete everything immediately, with the caption shown beforehand? *Recommend yes.* "Off means nothing is kept."
7. **Export off by default?** *Recommend yes.*
   - It is data waiting for a third party, not a preference.
   - A settings file travels by email, cloud folders and support tickets, and the list shows which discs someone owns, plus their own label text in full mode.
   - Importing means sending under someone else's key, which should be a deliberate tick.
   - It matches "This Mac only".
8. **CLI:** never saves or sends failed contributions, but can export and import the list with the app closed? *Recommend yes.* The alternative is app-only.
9. **Schedule:** 1 m → 24 h maximum, stop after 10 tries (about 3 days while the app is open)? *Recommend yes.*
10. **Retry when the network comes back (6b)?** *Recommend yes*, as a small separate commit.
11. **Stopped entries are not exported?** *Recommend yes.*
12. **Importing onto a Mac where contributing is off:** refuse the group rather than switch it on or hold? *Recommend refuse.*

**OWNER ANSWERS (25 Sept 2026, ~17:05). These override the recommendations above where they differ:**
- **Q1: NO LIMIT** on the number of waiting items. Keep the per-item size check. An export that would exceed the 10 MB settings-file limit refuses and says why.
- **Q2: YES**, save even when MeedyaDB isn't fully set up. An item saved with no server address yet is tied to the FIRST server set up afterwards, then only to that one.
- **Q3, Q4, Q5, Q7, Q8, Q10, Q11:** as recommended.
- **Q6 and the off rule:** deletion happens on the ACT of switching off (the Settings switch, or an import that turns it off), after the warning. While merely off, nothing is sent and nothing is deleted.
- **Q9:** the defaults are as recommended (1 min rising to 24 h; stop after 10 tries), but first wait, longest wait and tries-before-stopping are all CONFIGURABLE.
- **Q12:** an import onto a switched-off Mac keeps the items PAUSED until contributing is switched on (NOT refused).
- **Also found while building:** commits 4–7 (not 4–6) must land together. The `.queued` wording points at the Settings list that commit 7 builds.

---

## 10. Overlap and ordering with other work on the branch

- **Codex round 2 is still in progress in chunks.** Chunk 1, "privacy (F1 recheck `9d47730` + fixes)", covers exactly `MeedyaDBAccess.swift` and both disc view models. Those are the files commits 1, 4 and 6 change, and Codex reads whole files from the main working tree (HANDOFF lines 88–90).
  - Commits 2, 3 and 5 are new files only: build them any time.
  - Commits 1, 4 and 6: build them after chunk 1 has run, or in a worktree and cherry-pick afterwards.
  - Then aim a Codex chunk at #505 itself (privacy and the sender).
- **#506 follow-ups #524 (webhook secrets into the Keychain) and #525 (hooks in exports)** both edit `SettingsKeyRegistry`, the codecs and the **generated** `settings-export-v1.schema.json`. Don't build them at the same time as commit 8. Whichever lands second regenerates the schema.
- **#513** (a JSON Schema for the CLI's `disc identify`) must include the new `"queued"` status.
- **No clash:** #527 (`APIKeyManager`; #505 only calls `APIKeyManager().key(for:)` in providers), #528, #510, #508 (#505 starts from `MeedyaConverterApp`, not `AppViewModel.init`).
- **Ordering:** #505 is the last item in the owner's order (#507 → #508 → #506 → #505), before the W6 documentation sweep. Commit 10 should land before that sweep.
- **Stale worktree:** `.claude/worktrees/agent-aecc2da233ac2a105` (at `8a29ffa`, from #506) is out of date; don't reuse it.

### Critical Files for Implementation
- `Sources/ConverterEngine/Disc/MeedyaDBAccess.swift`
- `Sources/ConverterEngine/Disc/MeedyaDBPublisher.swift`
- `Sources/ConverterEngine/Settings/SettingsImporter.swift`
- `Sources/ConverterEngine/Settings/SettingsSectionHandlers.swift`
- `Sources/MeedyaConverter/Views/MeedyaDBSettingsTab.swift`
- (also) `Sources/ConverterEngine/Settings/SettingsCategory.swift`, `SettingsExportSchema.swift`, `SettingsKeyRegistry.swift` (fileStores 882–954), `Sources/ConverterEngine/Disc/MusicDiscIdentification.swift` (48–72), `Sources/MeedyaConverter/ViewModels/DiscIdentifyViewModel.swift`, `MakeMKVRipViewModel.swift`, `Sources/MeedyaConverter/MeedyaConverterApp.swift` (140–158), `Sources/meedya-convert/Commands/SettingsCommand.swift`, `DiscCommand.swift`.
