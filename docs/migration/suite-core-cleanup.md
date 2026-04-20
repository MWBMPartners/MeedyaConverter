<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaSuite-core Cleanup Checklist (Issue #374)

This document tracks the redundant-code removal that will happen once
MeedyaSuite-core is stable and the `SUITE_CORE` build flag is the default
configuration. Until then, the inline providers remain as the fallback path
and must not be deleted.

## Blocking prerequisites

- [ ] MeedyaSuite-core publishes a versioned Swift Package tag at
      `MWBMPartners/MeedyaSuite-core`
- [ ] CI resolves the dependency successfully with `SUITE_CORE=1`
- [ ] Smoke test `SuiteCoreSmokeTest.ping()` returns a non-empty version
      string on macOS CI
- [ ] `SUITE_CORE=1` flag flipped to default-on in `Package.swift` and CI
      build matrix

## Files to remove (after prerequisites met)

### `Sources/ConverterEngine/Metadata/MetadataProviders.swift`

Remove:

- [ ] `TheTVDBClient` struct — URL builders, login body, header builders,
      search/series/episodes endpoint helpers. Replaced by
      `SuiteCoreMetadataAdapter.search(source: .tvdb, query:)`.

Keep:

- [ ] Any future MeedyaConverter-specific presentation logic not covered by
      suite-core's unified provider system.

### `Sources/ConverterEngine/Metadata/MetadataLookup.swift`

Remove:

- [ ] `MetadataSource` enum if suite-core publishes the equivalent type
      — else keep as a thin typealias to the suite-core provider identifier.
- [ ] Per-provider URL helpers (`baseURL`) now handled by the Rust provider
      registry.

Keep:

- [ ] `MediaLookupType`, `MetadataSearchQuery`, `MetadataResult` — UI-facing
      value types that remain the stable public contract.

### `Sources/ConverterEngine/ConverterEngine.swift`

Remove:

- [ ] Any direct TheTVDB API calls (there are none currently — confirm via
      `grep -r TheTVDBClient Sources/` returning only the file above).

### Tests

- [ ] Migrate `TheTVDBClient` URL builder tests to assert against the
      `SuiteCoreMetadataAdapter.buildSuiteCoreRequestBody` payload format
      instead. Roughly 5 tests in `ConverterEngineTests.swift` to update.

## Safe-to-keep (do NOT remove under any circumstance)

- `Sources/MeedyaConverter/Views/MetadataEditorView.swift` — app-specific UI
- `Sources/MeedyaConverter/Views/MetadataTagEditorView.swift` — app-specific UI
- `Sources/ConverterEngine/FFmpeg/MetadataTagger.swift` — FFmpeg
  metadata-writing logic; unrelated to provider lookup
- `Sources/ConverterEngine/FFmpeg/MetadataPassthrough.swift` — stream
  metadata passthrough; unrelated to provider lookup

## Acceptance criteria (from #374)

- [ ] No duplicated provider logic remains in MeedyaConverter
- [ ] TheTVDB-specific API client code fully removed
- [ ] Locally-defined metadata lookup enums removed (using meedya-core types
      instead)
- [ ] Duplicated tag handling/normalization code removed
- [ ] `MetadataEditorView.swift` and `MetadataTagEditorView.swift` remain
      intact
- [ ] All existing functionality continues to work through meedya-core
      delegation
- [ ] No compiler warnings from unused/dead code related to old provider
      implementations
- [ ] Test coverage maintained or improved after cleanup
