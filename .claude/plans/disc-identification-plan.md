<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Plan — Content-based disc identification (issue #502, slice 1)

> Deep plan authored 2026-09-17. Fable was out of usage credits (HTTP 429) on two
> retries, so this run fell back to **Opus** per standing rule W3; retry Fable next
> planning run. Plain English, UK spelling.

## What we are building and why

Bring the good idea from the MakeMKV Claude skill `threadgill-dev/dvd-autorip-skill`
(see issue #502) into MeedyaConverter: **work out what a disc actually is from its
own content** — running time, chapter layout, subtitle/audio languages, disc label —
and produce a **ranked list of likely matches**, instead of trusting a fuzzy
title/year guess. This is the skill's core cleverness, and it is the piece our own
code is missing (metadata lookup is only partly wired — #205 — and the disc readers
are orphaned — #476).

## Hard boundaries (what makes this slice safe)

- **No MakeMKV, no decryption, nothing that unlocks copy protection.** The product
  deliberately refuses protected discs (`DiscImagingController` DRM gate +
  `DiscProtectionDetector`, #492). Adopting MakeMKV is a separate, user-gated legal
  decision — explicitly OUT OF SCOPE here.
- **Offline-capable, no live-model dependency.** Slice 1 is pure, deterministic
  logic: it takes signals we already have and a list of candidate matches, and ranks
  them. No network, no optical hardware, no orphaned readers, no AI in the loop.
- **Reuses existing types**, so nothing is duplicated:
  - Candidate type: `MetadataResult` (`Metadata/MetadataLookup.swift:133`) already
    carries `title`, `year`, `runtimeMinutes`, `season`, `episode`, `confidence`.
  - Query type: `MetadataSearchQuery` (`MetadataLookup.swift:84`) + `MediaLookupType`.
  - Disc signals come from `DiscInfo` / `DiscTitle` (`Disc/DiscModels.swift:81/253`).
  - Duration-proximity ranking mirrors `MusicBrainzTagMapping.ranked(...)`
    (`Metadata/MusicBrainzTagMapping.swift:54`).

## Design (slice 1)

New file: `Sources/ConverterEngine/Disc/DiscIdentification.swift`.

- `struct DiscSignals: Sendable, Equatable` — the content fingerprint:
  `discType`, `label`, `mediaTypeHint?`, `mainFeatureDurationSeconds?`,
  `titleDurationsSeconds`, `chapterCount?`, `subtitleLanguages`, `audioLanguages`,
  `seedTitle?`, `seedYear?`. Plus a pure factory
  `DiscSignals.from(discInfo:titles:seedFilename:)` that pulls the main feature
  (the `isMainFeature` title, else the longest), its chapter count and stream
  languages, and seeds `title`/`year` from the disc label or, failing that, from
  `FilenameParser.parse(...)`.
- `struct DiscIdentityScore: Sendable, Equatable` — transparent breakdown:
  `runtimeScore?`, `titleScore?`, `yearScore?`, `confidence` (0–1), `reason` (plain
  English). Missing signals are skipped, not penalised.
- `struct ScoredDiscMatch: Sendable` — `candidate: MetadataResult` + `score`.
- `enum DiscIdentifier` — pure static functions:
  - `rank(signals:candidates:) -> [ScoredDiscMatch]` — scores each candidate on
    running-time closeness (strongest, weight 0.5), title-text similarity (0.35),
    and year match (0.15), combines only the components that are present, and sorts
    by confidence then smallest running-time gap then stable order.
  - `buildQuery(from:) -> MetadataSearchQuery` — turn signals into a search query for
    whatever provider is used later.
  - private helpers: `normalise(_:)`, `tokenJaccard(_:_:)` (drops the articles
    the/a/an so "The Matrix" matches "Matrix").

## Test plan (`Tests/ConverterEngineTests/DiscIdentificationTests.swift`, XCTest)

- Ranking puts the exact running-time + title match first; a wrong-length candidate
  sinks.
- Year is the tie-break when running time and title tie.
- Title similarity: articles ignored; unrelated titles score low.
- Missing signals (no runtime / no year) are skipped, not treated as zero.
- Empty candidate list → empty result; all-unknown signals → stable original order,
  confidence 0.
- `DiscSignals.from(...)` picks the main feature, its chapters and languages, and
  seeds title/year from the label and from a filename.
- `buildQuery(from:)` maps an audio disc to a music query and a video disc to a
  movie query, carrying the seed year.

## Acceptance criteria

- [ ] `DiscIdentification.swift` compiles under `swift build --target ConverterEngine`.
- [ ] Pure, deterministic, `Sendable`; no network / hardware / decryption / model.
- [ ] Ranking is transparent (per-component breakdown + plain-English reason).
- [ ] Reuses `MetadataResult` / `MetadataSearchQuery` / `DiscInfo` / `DiscTitle`.
- [ ] Unit tests cover ranking order, tie-breaks, missing signals, edge cases,
      the `from(...)` factory and `buildQuery`.
- [ ] Independent review clean; CI green on `wip/alpha-consolidation`.

## Out of scope / later slices (noted so scope stays honest)

- **MakeMKV / any decryption** — user-gated legal decision (issue #502).
- **Provider adapters that fetch real candidates:** a MusicBrainz *disc* lookup for
  audio CDs (we have track durations), and the keyed video providers (TMDB/TheTVDB),
  which currently only build URLs and need an API-key UI (#205).
- **Wiring the orphaned readers + a real subtitle-text extraction pipeline** to
  produce `DiscSignals` from a physical disc (#476).
- **`AutoTagger` consumption + UI** to show ranked matches and apply one.
- **An optional AI-assisted refinement hook** (kept clearly separate from the
  deterministic core when it lands).

## Risks / GIRFT checks

- Local gate is `swift build --target ConverterEngine`; `swift test`/SwiftLint can't
  run here (no Xcode) — CI is the test gate. Whole-package build fails only on
  `#Preview` macros (environment, not code).
- Avoid float flakiness in tests: assert ordering and use accuracy-based equality for
  any exact score.
- Guard against divide-by-zero in the running-time score (tolerance floored; duration
  guarded `> 0`).
