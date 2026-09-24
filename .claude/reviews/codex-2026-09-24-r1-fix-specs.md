<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Codex round 1: fix specs for the findings not yet built

Written 2026-09-25 from three independent Opus read-only checks of
`codex-2026-09-24-r1.md`. **All 11 findings were confirmed real.** The findings
already handed to builders (F2+F10, F4+F5, F8, F9) carry their specs in their commit
messages. This file holds the specs for the rest, so they survive an interrupted
session. The short verdicts are in `.claude/HANDOFF.md`.

## F1 + #507 (+ the F10 screen wiring): one change to the shared contributor

**Problem.** Both screens read the MeedyaDB config and submission mode once, at run
start:
- `DiscIdentifyViewModel.swift:223-231`
- `MakeMKVRipViewModel.swift:701-705`

Nothing re-reads them before `publisher.submit`. So switching contributing off, or
moving from `full` to anonymous, mid-run does not stop the upload or the label.
Meanwhile the screen's notice re-reads live settings and says "turned off" while the
run uploads. `DiscIdentifyView.swift:18-20` ("nothing is uploaded that the user did not
expect") is false.

**How long the window is.**
- Music: the cdrdao TOC read plus one MusicBrainz request.
- Video: only the TMDB lookups, at most 7 (1–2 searches plus 5 detail fetches, 20 s
  timeout each).
- None at all with no TMDB key.

**Engine.**
- Give `MeedyaDBContributor.contribute(_:requested:mode:)` an optional
  `recheck: (@Sendable () -> MeedyaDBSubmissionMode?)? = nil`, called immediately
  before `publisher.submit`.
  - `nil` → `.notAttempted(reason: withdrawnReason)`. This is a new named reason, for
    example "MeedyaDB settings changed while this disc was being identified, so
    nothing was sent."
  - A mode → the contributor takes the NARROWER of the captured and current modes, so
    a faulty closure can never widen what is sent.
- Also add #507's `declinedBecause: String? = nil`, fed from a new
  `MeedyaDBReadiness.declinedReason`: the `.incomplete` reason, and `nil` for
  `.off`/`.ready`. "Off" keeps saying "wasn't requested", and the CLI is unchanged.
- Pass both through `MusicDiscIdentifier.identify` and `VideoDiscIdentifier.identify`
  as parameters that default to nothing.

**App.**
- Build the recheck from the providers already injected:
  - `guard let now = readinessNow().config, now == config else { return nil }; return modeNow()`
  - It compares for EQUALITY with the captured config, so switching off, changing the
    server, or removing/replacing the key all withdraw.
  - It lives in the app because the engine deliberately has no Keychain access
    (`MeedyaDBAccess.swift:15-22`).
- While a run is in progress, show a stored `runWillContribute` rather than the live
  settings. Otherwise switching ON mid-run shows "will be contributed" for a run that
  won't.
- F10 wiring: both views `.onReceive(APIKeyManager.didChangeNotification)` →
  `refreshMeedyaDBReadiness()`. The notification comes from the F2 change.

**Limit (write it in the comment).** Once a request has been handed to the network
layer, a later change can't recall it.

**Tests that prove delivery.** `PublishStubHTTPClient` records bodies. Count only
requests whose address contains `action=disc_ingest`, because the stub also counts
the MusicBrainz lookup.
- Music (`DiscIdentifyViewModelTests`): park the injected `tocReader` on a gate,
  change a lock-protected readiness/mode, then release:
  - (a) off mid-run → 0 uploads, withdrawn reason;
  - (b) full → anonymous → 1 upload, `"submission":"anonymous"`, no `labelText`
    (use a TOC with a CD-Text album title);
  - (c) anonymous → full → still anonymous;
  - (d) server changed → 0 uploads;
  - (e) key removed → 0 uploads;
  - (f) nothing changed → exactly 1 upload in full.
- Video (`MakeMKVRipViewModelTests`): at least a, b, c and f, with the candidate
  provider waiting on the gate.
- Engine (contributor): recheck nil / narrower / wider / absent.
- #507: incomplete → the specific reason; off → "wasn't requested"; the CLI
  (not requested) → "wasn't requested".

**Build:** Sonnet. Privacy and concurrency, so Opus verifies.

## F3: rip uses the last scan's titles with the current source

**Problem.**
- `MakeMKVRipViewModel.swift:441` resolves the source from the current fields, while
  the titles come from the last scan (452–453).
- `performScan` (319–343) discards the scanned source.
- `canRip` / `ripBlockedReason` (387–408) never compare them.
- `MakeMKVRipPlanning.selectors` returns `.all` when every title is selected.
- The source fields (`MakeMKVRipView.swift:137–159`) stay editable during a scan, and
  the "Read from" picker triggers it too.

**Fix.**
- Add `private(set) var scannedSource: MakeMKVSource?` (the type is already
  `Equatable`, `MakeMKVBackend.swift:49`). Clear it when a scan starts; set it on
  success.
- `rip()` refuses unless `resolvedSource == scannedSource`, and rips from
  `scannedSource`.
- `canRip` gets the same condition; `ripBlockedReason` says "The source has changed
  since the last scan. Scan again before ripping."
- Block rather than clear, so an undone typo keeps the selection.
- Update `test_blockedReasons_coverEveryDisabledStateOfTheirButton`.

**Known limit.** Swapping the physical disc in the same drive can't be detected this
way.

**Tests (`MockMakeMKVRunner`).**
- Scan drive 0, select all, set a destination, then `discIndexText = "1"` → `canRip`
  false with a reason, `rip()` returns nil, `runner.invocationCount == 1`.
- The same via `sourceKind = .discImage` + `isoPath`.
- Set it back to "0" → the rip runs with `buildRipArguments(source: .disc(0), titles: .all, …)`.

**Build:** Sonnet.

## F6: fuzzy music matches presented and submitted as exact

**Problem.**
- `MusicBrainzDiscLookup.swift:141` always sends `/discid/-?toc=…`, so the computed
  Disc ID is never used.
- `parseDiscLookup` (203–227) decodes only `releases`.
- MusicBrainz docs: an unknown disc ID plus `toc` triggers a fuzzy lookup (unless a CD
  stub is found, so use `cdstubs=no`), and "-" makes the ID ignored.
- Live check (Nevermind, the docs' example):
  - exact → a disc object (`id, offset-count, offsets, releases, sectors`) with 5
    releases;
  - fuzzy → `release-count, release-offset, releases` with 25, of which only 5 carry
    this disc's ID;
  - a fuzzy search with no match is HTTP 200 with an empty list.
- MeedyaDB's `handleDiscIngest` ignores candidate confidence and flattens candidate
  identifiers onto the disc.

**Fix.**
1. Request `/discid/<computed music Disc ID>?toc=<toc>&cdstubs=no&inc=artist-credits&fmt=json`.
   Keep the existing `inc` values if they differ; read the code.
2. Return the match kind with the matches. `.exact` ONLY when the top-level `id`
   equals the requested ID AND `offsets` is present; every other shape is `.fuzzy`
   (fail safe).
3. Only exact says "Identified as". Fuzzy says "Closest match: X. MusicBrainz doesn't
   know this exact disc, so this is a best guess from similar track lengths."
4. **D1 (owner decision; default applied):** on a fuzzy match, submit the Disc ID and
   TOC with NO candidates.
5. Add `matchKind` (`exact` / `fuzzy` / `none`) to the CLI JSON, and update
   `docs/api/meedya-convert-api.yaml`.
6. Correct the false comments and doc lines:
   - `MusicDiscIdentification.swift:169-172`
   - `MeedyaDBSubmissionBuilder.swift:18-21`, `:32-34` ("nothing calls this builder
     yet", which is stale) and `:172`
   - `VideoDiscIdentification.swift:22-23, 56`
   - `docs/Disc-Tools.md:44, 167`
   - `Help/disc-tools.md:37-38, 125`

**Tests.**
- The URL contains the real ID and `cdstubs=no`, and never `/discid/-`.
- Fixtures trimmed from the real response shapes:
  - exact → `.exact` with 5 releases;
  - fuzzy → `.fuzzy`;
  - an unrecognised shape → `.fuzzy`;
  - an exact shape with a different ID → `.fuzzy`.
- The whole run through the stub:
  - fuzzy → no "Identified as", no candidates sent, Disc ID still sent;
  - exact → "Identified as".
- A `DiscIdentifyViewModelTests` case shows the fuzzy wording on screen.
- Replace the existing `{"releases":[…]}` fixtures (`MusicDiscIdentificationTests.swift:111`,
  `MusicBrainzDiscLookupTests.swift`), which would now parse as fuzzy.

**Build:** Sonnet. Codex review after (shared data).

## F7 + F11: wording (do alongside the documentation sweep)

**F7 (what the Enhanced CD text says).**
- The CLI's `describe(.singleSession)` says "the end of the disc (there is only one
  session)". Change it to "the end of the session that was read (the first; any
  later session was not read)".
- Say that the drive reader reads only the first (music) session, so the whole-disc
  ID doesn't appear yet, while the Disc ID is still what MusicBrainz measures. Places:
  - `docs/Disc-Tools.md:75, 78-82`
  - `Help/disc-tools.md:60-64`
  - `docs/api/meedya-convert-api.yaml:1257-1260`
  - the comments at `MusicBrainzDiscID.swift:40-48` and `MusicDiscIdentification.swift:96-99`
- Correct #504 and its "case 1 needs no confirmation" comment.
- Follow-up issue: a macOS full-TOC reader (`DKIOCCDREADTOC`/`kCDTOCFormatTOC`, as in
  libdiscid `src/disc_darwin.c`). The descriptor parser can be unit-tested with
  constructed bytes.

**F11 (what the video identification text claims).**
- `MakeMKVRipView.swift:276` → "Scan the disc first. Identifying searches TMDB for
  films using the disc's name, then compares each result's running time with the
  main feature. TV series aren't searched yet."
- `docs/Disc-Tools.md:159-165` and `Help/disc-tools.md:117-122`:
  - "which film it is", not "what film or programme it is";
  - the method is running time plus name; chapter count and languages are read but
    not yet used; TV series are not searched.
- `Disc-Tools.md:167-170` and `Help:125-127`:
  - "A music CD usually does, when MusicBrainz knows that exact disc";
  - an example of 85% or below, plus "a film disc can currently reach at most 85%".
- Comments:
  - `VideoDiscIdentification.swift:22-30`: running time and name only. TMDB IS wired,
    for films.
  - `DiscIdentification.swift:8-10, 61-63`: chapters, languages and the TV hint are
    carried but not scored.
- `SettingsView.swift:460-461` under-claims. Add "…and to suggest which film a disc is
  on the MakeMKV Rip screen."
- `docs/FAQ.md:214-227` privacy:
  - identify sends text taken from the disc's name (plus any year in it) to
    api.themoviedb.org;
  - the "Disc identification" bullet must mention TMDB, not only MusicBrainz.

## Found alongside (raise as issues; don't fix quietly)

- **MeedyaDB (separate repo):**
  - `handleDiscIngest` (`api.php:137-196`) flattens candidate identifiers onto the disc
    and ignores confidence.
  - `resolveByIdentifier` (`includes/entities.php:114-125`) uses `LIMIT 1` with no
    entity-type filter or ordering.
- **`ExternalToolRunner`** has the same pre-launch cancel gap (F4) and lost-tail bug
  (F5) as the MakeMKV runner.
- **`README.md:121`** still says TMDB only builds URLs and disc-ID lookups are uncalled.
- **The CLI `disc identify --format json`** has no JSON Schema (a standing rule).
- **The ranker** compares titles against the raw seed including disc noise
  ("BIG_MOVIE_DISC_1" vs *Big Movie* scores 0.5).
- **MakeMKV line continuation:** a backslash at the end of a line continues the
  message. Message 3334 is dropped today. It follows on from F9.
