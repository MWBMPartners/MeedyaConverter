<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Plan: #508, auto-tagging during an encode

**Status: PLANNED, not built.** An Opus deep-plan run (read-only) on 2026-09-24/25,
against `cd6b5a4`. Line numbers are as of that commit, so re-check them by text before
editing, because the Codex round-1 fixes land first. Decisions taken on the
recommended defaults are listed at the end; the owner can override any of them.

## The short version

- **Where the lookup runs.** Inside `EncodingEngine.encode(job:onProgress:)`
  (`Sources/ConverterEngine/Encoding/EncodingEngine.swift:210`):
  - after the source probe (≈246) and `validateCodecContainerCompatibility` (≈250);
  - before the Dolby Vision pass (≈263);
  - merged right after `var enrichedJob = job` (≈299).
- **How the setting reaches it.** The engine is given an `AutoTagSettingsSource` when
  it's built. It reads the setting at the start of each job, so a change applies from
  the next job.
- **How the tags reach FFmpeg.** Looked-up tags are merged into
  `enrichedJob.outputMetadata`, which the builder's existing private
  `buildMetadataArguments()` already emits. **`FFmpegArgumentBuilder` does not
  change.**
- **No config changes.** `EncodingJobConfig` also does not change, so none of its
  22 construction sites (13 in Sources, 9 in Tests) needs editing.
- **Only missing tags are added.** The job's own `outputMetadata` wins, then the
  source file's non-blank tags (carried by `-map_metadata 0`). Looked-up tags only
  fill keys that both lack.
- **Renaming: a separate follow-up issue.** Reasons below. Writing the NFO is
  included.

## Why the lookup runs there (and what was rejected)

**Why here.**
- **It needs the probe result.** That gives film-vs-music via
  `looksLikeVideoContent` (NOT `hasVideo`, since cover art reads as video), the file
  duration for scoring, and the existing tags for the "missing only" rule.
- **No wasted calls.** A job that fails validation costs no network call.
- **Stopping is cheap.** Stop costs nothing, because FFmpeg hasn't started.
- **One rule covers every path.** Every job the app engine runs gets the same
  behaviour: the queue, watch folders, the scheduler, re-queued jobs, API-server
  jobs run by the app, and AppleScript.
- **Off the main thread.** `EncodingEngine` is a plain class, so `encode` runs on
  background threads. `AppViewModel.runJob` waits on `engine.encode`, which frees
  the main thread.

**Rejected alternatives.**
- **Enqueue time.** Reads the setting too early, stalls enqueue, needs repeating at
  every enqueue site (the "one of seven" bug class), and puts tags into Codable
  config.
- **`AppViewModel.runJob`.** Needs a second probe, and the wiring can only be tested
  through the whole queue.
- **A new `EncodingJobConfig` field.** Codable across batch JSON and the API, 22
  sites, and the key must never live there.
- **Appending `AutoTagger.buildMetadataArguments` output to `extraArguments`.** It
  comes after the builder's own `-metadata`, so FFmpeg's last value wins and
  overwrites the job's tags. It also uses a different set of keys.

## New types (all in `ConverterEngine`)

- **`Metadata/AutoTagSettings.swift`:**
  - `AutoTagSettingsStore`, with keys `autotag.enabled` and `autotag.writeNFO`
    (both Bool; absent means off). `config(in:)` fixes everything else:
    - sources `[.filename, .existingMetadata, .tmdb, .musicBrainz]`
    - `renameOutput` false
    - `embedArtwork` false
  - `AutoTagReadiness`: `.off(reason)`, `.limited(config, reason)` (on, but films
    skipped because there's no TMDB key), `.ready(config)`.
  - `AutoTagGate.readiness(in:hasTMDBKey:)`, with its wording as named constants.
  - `AutoTagRequest`: config, an optional `TMDBLookupService` (nil means films are
    skipped, never a failure), `MusicBrainzLookupService`, and a deadline.
  - `AutoTagSettingsSource`: `suiteName` (nil means `.standard`),
    `tmdbKeyProvider`, the http client, a MusicBrainz throttle and a deadline
    (default 30 s). Provides `readsStandardDefaults` and `currentRequest()`, which
    reads NOW and returns nil when off.
- **`Metadata/AutoTagMerge.swift`:** `additions(existing:jobTags:applying:)`.
  - Build `[MediaTag]` from the non-blank source tags plus the job's tags.
  - Run `TMDBTagMapping.applying(result, to:, includeIdentifiers: true)` (or
    `MusicBrainzTagMapping.applying`) over them.
  - Keep ONLY the rows it APPENDED. Rows it replaced are the keys that must not be
    overwritten, and this handles aliases (date/year, description/synopsis,
    track/tracknumber) and capitalisation.
  - Returns `(added, keptExisting)`.
- **`Metadata/AutoTagRunner.swift`:**
  - `AutoTagPlan`: `.film(query)` / `.music(query)` / `.skip(reason)`.
  - `AutoTagOutcome`: applied, matchedNothingToAdd, belowThreshold, ambiguous,
    noMatch, skipped, failed (with the reason redacted).
  - `AutoTagLookupReport`.
  - `AutoTagRunner.plan(for:)` (pure) and
    `run(request:source:jobTags:shouldStop:)`, which throws only
    `CancellationError`.
- **`Metadata/AutoTagNFOWriter.swift`:**
  - Uses `AutoTagger.generateNFOPath` and `MediaServerTagging.buildKodiMovieNFO`.
  - Writes with `.withoutOverwriting` (an existing `.nfo` is left alone).
  - Writes only if the output exists.
- **`Metadata/AutoTagWording.swift`:** the `AutoTagJobEvent` log messages, pinned
  by tests.

## How `run` works

- **Choosing film or music.**
  - Film = `looksLikeVideoContent`.
  - A file name matching `FilenameParser`'s TV pattern is skipped ("TV episodes
    aren't looked up yet").
  - Music = `hasAudio && !looksLikeVideoContent`, never `isAudioOnly` (which says
    no to an MP3 with art).
  - An empty probe is a skip.
- **Order.** `AutoTagger.determineLookupOrder` sets it.
  - `.filename` and `.existingMetadata` only seed the search.
  - `.tvdb`, `.discogs` and `.audioFingerprint` are "not connected yet", which is a
    separate reason from "no key".
  - TMDB with no key makes zero requests.
- **Film scoring.**
  - `searchMovies(title:year:language:)`; an empty year-filtered search retries
    without the year.
  - `withRuntimes(limit: min(maxResults, 5))`.
  - `DiscIdentifier.rank` with `DiscSignals(discType: .dataDisc, mainFeatureDurationSeconds: file.duration, seedTitle:, seedYear:)`.
    `rank` reads only those; a test pins that `discType` is ignored.
  - The score is copied into `confidence`, then `AutoTagger.meetsThreshold` (0.7).
  - **Ambiguity rule:** if the top two are different films, both at or above the
    threshold and within 0.05 of each other, nothing is applied.
- **Music (a later slice).**
  - `searchRecordings`, then `MusicBrainzTagMapping.ranked(… fileDurationSeconds:)`.
  - Confidence is `score/100`, but 0 when the recording has no length or the length
    differs by more than max(5 s, 3%).
  - An artist is required (a tag, or an "Artist – Title" file name).
- **Deadline and stop.** A task group races the lookup, `Task.sleep(for: deadline)`
  and a 0.25 s `shouldStop()` poll. The first to finish wins; the others are
  cancelled.
- **Redaction.** Every failure reason passes through
  `TMDBLookupService.redacting(_:key:)` as well.

## Changes to existing files

- **`EncodingEngine.swift`**
  - `init(…, autoTagSettings: AutoTagSettingsSource? = nil)`, appended LAST so all 9
    construction sites still compile.
  - `autoTagEvents: AsyncStream<AutoTagJobEvent>` (bufferingNewest 64).
  - A lock-protected stop registry (`inFlightJobIDs`, `stopRequestedJobIDs`):
    - `stopEncoding()` marks every job in flight;
    - `stopEncoding(jobID:)` marks only that job;
    - with nothing in flight it is still a no-op, which is what
      `ParallelEncodingConcurrencyTests.swift:297-313` requires.
  - In `encode`: register the job id (with a `defer`), read `currentRequest()` once,
    run the lookup, then `enrichedJob.outputMetadata.merge(additions) { job, _ in job }`.
    Throw `CancellationError` if a stop was requested. Write the NFO at the very end
    (after the DV-HLG block, ≈606).
- **`AutoTagger.swift`**
  - Make `AutoTagConfig` `Equatable`.
  - `embedArtwork` defaults to **false** (nothing embeds).
  - Mark `renameOutput`, `namingTemplate` and `embedArtwork` as "not acted on yet".
  - **Remove `buildMetadataArguments(result:config:)`**: zero callers, ignores
    `config`, wrong keys.
  - Warn on `buildArtworkArguments` that it is a remux-only fragment
    (`-map 0 -map 1 -c copy`) and must never go into an encode.
  - Rewrite the doc comment so it describes what actually runs.
- **`FFmpegProbe.swift:146`**: move `format_tags=` into `static let formatTagKeys` and
  widen it (`year, description, synopsis, director, tmdb_id, album_artist,
  tracknumber, disc`, plus the MusicBrainz ids). Otherwise "never overwrite" is blind
  to them. Confirm with a real ffprobe that `-show_entries format_tags=` narrows the
  output.
- **`MetadataLookup.swift:84`**: `MetadataSearchQuery` becomes `Equatable`.
- **App**
  - `AppViewModel.init` (≈576) passes
    `AutoTagSettingsSource(tmdbKeyProvider: { APIKeyManager().key(for: .tmdb)?.apiKey })`.
  - A main-actor task reads `engine.autoTagEvents` and calls
    `appendLog(…, category: .metadata, jobID:)`.
  - `runJob`'s catch (≈1985) gets a `catch is CancellationError` branch, so the job
    stays Cancelled.
- **UI**
  - A new `Sources/MeedyaConverter/Views/AutoTagSettingsSection.swift`, inserted with
    ONE line after `providerKeysSection` in `MetadataSettingsTab`
    (`SettingsView.swift:322`), passing `hasTMDBKey`.
  - `@AppStorage(AutoTagSettingsStore.Keys.enabled)` uses the constant, not a
    string.
  - The status line comes from `AutoTagGate.readiness`, the SAME function the run
    uses.
  - `FFmpegPreviewView.swift:148-163` gets the caption "Automatic tagging is on: tags
    found when the job runs are added to this command."

## Proposed wording

**Settings.**
- Section title: "Tag files automatically while converting".
- Toggle: "Look each file up and add the tags it's missing".
- Caption lines:
  - "Films are looked up on TMDB and music on MusicBrainz. When this is on, each
    file's title (and year, if known) is sent to them." (The music half is added
    only once the music slice lands.)
  - "Only tags the file doesn't already have are added. Tags already in the file are
    never replaced."
  - "If a lookup fails, takes too long, or isn't confident of the match, the file is
    still converted, just without the extra tags. The Activity Log says what
    happened to each file."
  - "File names are never changed. TV episodes aren't looked up yet."
  - "Applies to conversions from the queue (including watch folders and scheduled
    jobs) and from AppleScript. Encoding pipelines and the meedya-convert
    command-line tool don't tag files."
  - "Some formats, such as MP4, keep only the common tags."
- Status line:
  - off: "Automatic tagging is off."
  - limited: "On, but films are skipped until you save a TMDB key above."
  - ready: "On."
- NFO toggle (disabled while the main toggle is off): "Also save a Kodi .nfo file next
  to each identified film". Caption: "An existing .nfo file is never overwritten."

## What happens in each case

| Case | What the encode does | What the Activity Log says | NFO |
|---|---|---|---|
| Off (default) | unchanged; zero requests | nothing | no |
| Film, no TMDB key | unchanged; zero requests | "…skipped: no TMDB key is saved (Settings › Metadata)." | no |
| TV name / music without artist / empty probe | unchanged | "…skipped: <reason>" | no |
| Unreachable, 401, 429, 5xx | unchanged, carries on | warning, with the reason redacted | no |
| Takes more than 30 s | unchanged | "TMDB didn't answer within 30 seconds…" | no |
| No results | unchanged | "TMDB found nothing for 'X (Y)'." | no |
| Below 0.7 | unchanged | "Best match 'X (1999)' was 52% certain; needs 70%. Not applied." | no |
| Ambiguous | unchanged | "Two films matched equally well… Not applied." | no |
| Success | missing tags added as `-metadata` | "Tagged from TMDB: … Added: … Kept the file's own: …" | if on |
| Stop pressed during the lookup | abandoned within ~0.25 s; FFmpeg never starts; job stays Cancelled | "Encoding cancelled" | no |

## Tests (each checks what was delivered)

**`Tests/ConverterEngineTests/AutoTagEncodeDeliveryTests.swift`.**
- The fake-binary pattern from `FFmpegProbeWatchdogTests`:
  - a fake `ffmpeg` records its argument list (NUL-separated). Note that `-progress
    pipe:1` comes AFTER the output path, so the fake must not treat the last argument
    as the output;
  - a fake `ffprobe` returns a 148-minute h264 with `title` = "My own title";
  - a 5 s guard on the event stream, so a missing event fails instead of hanging.
- Cases:
  - on + key → the arguments contain `date=2010`, `genre=…`, `description=…`,
    `tmdb_id=27205` and `-map_metadata 0`, and NOT `title=Inception`;
  - off → arguments identical to the baseline, zero requests;
  - the same engine, off then on → the second job is tagged (proves the setting is
    read per job);
  - no key → zero requests;
  - transport error → the encode succeeds, arguments identical to the baseline;
  - running time 90 vs 148 → below threshold;
  - the job's own `genre=Mine` wins;
  - hanging stub + `stopEncoding()` → `CancellationError` within 2 s, and FFmpeg
    never launched;
  - NFO on / off;
  - the key appears in no argument, event or wording string.

**Other test files.**
- `AutoTagRunnerTests.swift`: failure cases; an MP3 with art is never sent to TMDB;
  TV skip; the deadline; stop; ambiguity; `rank` ignores `discType`.
- `AutoTagMergeTests.swift`: includes `keysItMayWrite ⊆ FFmpegProbe.formatTagKeys`.
- `AutoTagSettingsTests.swift`: off by default; key spellings pinned; three states;
  the settings status and the run's skip reason agree.
- `AutoTagNFOTests.swift` and `AutoTagWordingTests.swift`.
- `Tests/MeedyaConverterCoreTests/AutoTagAppWiringTests.swift`:
  `AppViewModel().engine.autoTagSettings?.readsStandardDefaults == true`.
- Update `ConverterEngineTests+ToolingAndMetadata.swift:158-165` (`embedArtwork` is
  now false).

**Test rules.**
- A unique-UUID `UserDefaults` suite per test.
- Music tests use a fresh `MusicBrainzRequestThrottle(minimumInterval: .zero)`, never
  `.shared`.
- `lock.withLock {}` in async mocks.
- Private helper types with names unique to the module.

## Commits, in order (each compiles on its own)

1. **`AutoTagger` made honest.** Equatable, `embedArtwork` false, remove
   `buildMetadataArguments`, doc fixes. Sonnet/Haiku.
2. **Probe keys + merge.** `FFmpegProbe.formatTagKeys` widened, `AutoTagMerge` +
   tests. Sonnet.
3. **Settings.** `AutoTagSettings.swift` + tests. Sonnet.
4. **Runner, films.** Scoring, order, threshold, ambiguity, deadline/stop race +
   tests. **Opus.**
5. **Runner, music.** Sonnet with the rule spelled out; Opus verifies.
6. **Engine wiring.** `EncodingEngine` + delivery tests. **Opus** (it touches the
   #286 stop semantics).
7. **NFO.** Writer + engine hook + tests. Sonnet.
8. **App wiring.** Settings source, event → log, the cancellation branch,
   `AutoTagWording`, app test. Sonnet; Opus verifies.
9. **Settings UI.** `AutoTagSettingsSection` + one-line insertion + preview
   caption. Sonnet.
10. **Docs and issues.** FAQ privacy paragraph, Architecture, FEATURES, README,
    Home, `Help/faq.md`; follow-up issues; tick the #508 criteria. **The privacy
    wording must land in the same push as commit 9**, because `docs/FAQ.md:214-221`
    otherwise becomes false.

## Where the issue text doesn't match the code

1. `buildArtworkArguments` in an encode would BREAK it (`-c copy` turns a transcode
   into a copy). Artwork is a follow-up.
2. `meetsThreshold` alone would NEVER pass a TMDB result. `parseSearchResults` sets
   no confidence, so everything is 0.5 (`MetadataLookup.swift:218`), below 0.7.
   Real scoring (via `rank`) is required.
3. `buildMetadataArguments(result:config:)` should be removed, not wired up.
4. The builder's private `buildMetadataArguments()` uses `outputMetadata`, which no
   app path sets. The file's own tags travel by `-map_metadata 0`.
5. The probe reads only 8 format tags, so "never overwrite" is blind until it is
   widened.
6. The `AutoTagConfig` defaults leave out `.musicBrainz`, and set `embedArtwork`
   true with nothing behind it.
7. "Skip a provider with no key" is incomplete: TVDB, Discogs and fingerprinting
   can't run even WITH a key.
8. Stop during a lookup doesn't work today (`stopEncoding` only reaches running
   FFmpeg). Hence the stop registry.

## Renaming: a follow-up issue (not built here)

- `EncodingJobState.config` is `let`, and about ten post-encode readers use
  `jobState.config.outputURL` (stats, notifications, email, webhooks, hooks,
  delete-source, watch-folder, checkpoints). A renamed output would leave all of them
  pointing at a missing file.
- `generateOutputFilename` never calls `sanitiseFilename`, so a "/" in a title
  becomes a path. It also writes "(0)" when the year is unknown.
- It needs `FilenameTemplate.resolveOutputURL` for overwrite and collision handling.
- A preview means looking up before the job runs: a different design.

## Other follow-ups to open

- TV episodes.
- Artwork embedding.
- A CLI `--auto-tag` flag.
- Caching repeat lookups for multi-output.
- **`ScriptingBridge.swift:286-292` queues AND directly encodes the same job** (an
  existing double-run bug).
- `runJob` marks a killed-FFmpeg cancel as Failed (existing).
- The Settings › Metadata "Provider backend" picker (`metadataBackend`,
  `SettingsView.swift:291`) has NO reader, and `SuiteCoreMetadataAdapter` is never
  constructed outside tests. It needs its own #507-style issue.

## Risks

- A concurrency slot is held during the lookup (up to 30 s).
- The stop-registry change must keep the no-op tests passing.
- In the App Store sandbox, the NFO write may be refused (recorded; the encode is
  unaffected).
- Widening the probe shows more tag rows in the editor and in `meedya-convert probe`.

## Decisions taken on the planner's recommended defaults (owner may override)

1. Music acceptance: length within max(5 s, 3%), and an artist is required.
2. Ambiguity margin 0.05.
3. Lookup time limit 30 s.
4. Write IDs (`tmdb_id`, the MusicBrainz ids): on, matching the tag editor's
   default.
5. AppleScript encodes are tagged too (it follows from the design).
6. A file with no probed duration is never tagged (deliberately conservative).
