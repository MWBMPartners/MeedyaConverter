<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Plan — MakeMKV GUI rip flow (#503 slice 4b)

**Status:** design complete (2026-09-20), implementation next.
**Owner decision:** the owner chose the **GUI rip flow** as the #503 entry point
(over a CLI-first option), so this is the entry point for the engine built in
slices 1–3.

## Grounding facts (verified in-repo, with evidence)

| Fact | Evidence |
|---|---|
| App code is a **library target** `MeedyaConverterCore` (path `Sources/MeedyaConverter`), unit-tested via `@testable import MeedyaConverterCore` in `Tests/MeedyaConverterCoreTests` | `Package.swift:383-415`, `:439-443` |
| House observation pattern is **`@MainActor @Observable final class`** (not Combine) | `AppViewModel.swift:301-302`; `QualityMetricsView.swift:79-81` |
| Views own a VM as `@State private var viewModel = X()`, tear down in `.onDisappear`, cancel again in `deinit` via `nonisolated(unsafe)` | `QualityMetricsView.swift:406, :451-453, :119-126, :385-388` |
| Tools views drain streams with `for await` + `Task.isCancelled` checks | `StabilizationView.swift:336-352` |
| **No app code consumes an `AsyncThrowingStream` yet** — only engine tests do | `MakeMKVExecutorTests.swift:153` |
| Sidebar: `NavigationItem` enum + **two exhaustive switches**, an `unavailable` set gated `#if APP_STORE`, `SidebarView` `isAvailable` guard, `ContentView` exhaustive switch | `AppViewModel.swift:19-292, :184-191`; `SidebarView.swift:49-80`; `ContentView.swift:89-197` |
| Disc features hidden in App Store builds via `#if APP_STORE` (not `DIRECT`) | `docs/decisions/0001-gpl-disc-tools.md:189-199` |
| Settings has **no** tab-selection binding; opened via `@Environment(\.openSettings)` | `SettingsView.swift:43-146`; `MeedyaConverterApp.swift:103` |
| `MakeMKVTitle` already exposes `duration` ("1:57:21"), `sizeText` ("26.5 GB"), `chapterCount`, `sizeBytes` | `MakeMKVBackend.swift:215-227` |
| `MakeMKVTitleSelector` is only `.all` or `.index(Int)` — **no multi-index** | `MakeMKVBackend.swift:71-84` |

## Key decisions

- **D1 — Use a view model, not `@State` in the struct.** Both are house patterns, but
  a `@MainActor @Observable` VM makes the whole scan→select→rip flow testable from
  `MeedyaConverterCoreTests` with a mock `MakeMKVLineStreaming`. With `@State` in the
  view, none of it is testable.
- **D2 — Pure helpers live in the engine** (`MakeMKVRipPlanning.swift`), next to
  `MakeMKVProgressEvent.totalFraction`, reusable by a future CLI, and covered by
  `ConverterEngineTests` which already has robot-mode fixtures.
- **D3 — Sequential per-title runs.** The selector is `.all | .index(Int)`, so a subset
  = N sequential `rip` calls with aggregated progress. If every listed title is
  selected, use one `.all` run. Caveat: `.all` honours MakeMKV's default
  `--minlength` (120s) exactly as `info` did, so the sets should agree; if the
  hardware matrix disagrees, drop the `.all` optimisation (one line).
- **D4 — "Open Settings" button only.** Deep-linking to the MakeMKV tab needs
  `TabView(selection:)` + a `value:` on all ~20 tabs — an unproven construct here.
  Keep it a separate, revertible follow-up. Never a dead button either way.
- **D5 — Navigating away cancels a rip.** `ContentView` recreates the detail view on
  navigation, so the `@State` VM is released and `.onDisappear`/`deinit` cancel.
  Same as Stabilization/Vector today; the UI says so.
- **D6 — Re-check the gate before every action** (on appear, on any of the three
  `MakeMKVConsentStore.Keys` changing, and at the start of `scan()`/`rip()`), building
  a fresh `MakeMKVExecutor` per action so consent can never be stale.

**No policy change / no bundling.** The new code touches only
`MakeMKVExecutor`/`MakeMKVGate`/`MakeMKVConsentStore`/`MakeMKVBackend`. It never
references `DiscProtectionDetector`, `DiscImagingController` or `ToolBundleManifest`.

## Files

**New**
1. `Sources/ConverterEngine/Disc/MakeMKVRipPlanning.swift` — pure, public:
   - `MakeMKVRipProgressTracker` — folds `MakeMKVRipEvent`s into
     `overallCaption` / `currentCaption` / `overallFraction` / `currentFraction` /
     `lastMessage`. A `nil` fraction (max ≤ 0) keeps the previous value.
   - `MakeMKVTitleSummary(title:)` — display strings: `displayName`
     (`name ?? sourceFileName ?? "Title N"`), `durationText`, `sizeText`
     (passthrough, else `ByteCountFormatter`), `chaptersText`, `streamsText`.
   - `MakeMKVRipPlanning.defaultSelection(for:)` — main feature = greatest
     `durationSeconds`, tie → greatest `sizeBytes`, tie → lowest index. A lone title is
     always selected. Empty when 2+ titles and none has a parseable duration (never guess).
   - `.selectors(forSelected:allTitleIndices:)` — `[]` / `[.all]` / ascending `.index`es.
   - `.aggregateFraction(completedRuns:totalRuns:currentRunFraction:)` — clamped 0…1.
   - `.failureSummary(for:)` — plain-English text per `MakeMKVExecutorError` case
     (pinned verbatim by tests); `CancellationError` → "The rip was cancelled."
2. `Sources/MeedyaConverter/ViewModels/MakeMKVRipViewModel.swift` —
   `@MainActor @Observable final class`; injected `runner` / `readinessProvider` /
   `consentProvider` so tests need no real process or `UserDefaults`.
3. `Sources/MeedyaConverter/Views/MakeMKVRipView.swift` — gated state
   (`ContentUnavailableView` + "Open Settings…" + "Check Again"), then a `Form`:
   Source → Titles → Destination → Run → Outcome → Messages.

**Edit**
4. `AppViewModel.swift` — add `case makemkvRip = "MakeMKV Rip"`, add it to the
   `#if APP_STORE` `unavailable` set, and add an arm to **both** exhaustive switches
   (`systemImage` → `"opticaldisc.fill"`, `accessibilityLabel`).
5. `SidebarView.swift` — `if NavigationItem.makemkvRip.isAvailable { sidebarLabel(for:) }`.
6. `ContentView.swift` — `case .makemkvRip: MakeMKVRipView()`.

**Tests**
7. `Tests/ConverterEngineTests/MakeMKVRipPlanningTests.swift` — tracker folding,
   default selection, selectors, aggregate clamping, summary formatting, failure text.
8. `Tests/MeedyaConverterCoreTests/MakeMKVRipViewModelTests.swift` — `@MainActor`
   XCTestCase, mock runner (copy the pattern from `MakeMKVExecutorTests.swift:22-60`,
   extended with per-call scripts). Covers: gate closed → **zero** runner calls;
   source mapping; scan success/failure/cancel; rip guards; `.all` vs subset arg
   building; sequential multi-run ordering; failure/cancel outcomes; gate flipping
   mid-session; message cap.
9. `Tests/MeedyaConverterCoreTests/NavigationItemAvailabilityTests.swift` — add the
   `makemkvRip` availability test mirroring the existing one.

## Why the streaming consumer compiles under Swift 6

1. The VM is `@MainActor`; `Task { [weak self] … }` created from a main-actor method
   **inherits** that isolation, so property writes inside `rip()` need no `MainActor.run`.
2. `MakeMKVExecutor` is a `Sendable` struct; its `info`/`rip` are non-isolated async, so
   process I/O runs off the main actor.
3. `MakeMKVRipEvent` is `Sendable`, so the stream is; the iterator is created and
   consumed in the same main-actor task and never crosses an isolation boundary.
   `for try await` here is the exact loop the engine tests already compile.
4. Cancellation is three-point (inside the loop, `catch is CancellationError`, and after),
   lifted from `StabilizationView.swift:343-348`. Cancelling fires the stream's
   `onTermination` → producer `task.cancel()` → `box.terminate()`.
5. `deinit` is non-isolated and touches only `nonisolated(unsafe)` task vars.

## Compile traps (ranked) — use the proven alternative

1. **Missing a `NavigationItem` switch arm** — three exhaustive switches plus the
   `unavailable` set; do all four edits together. (Omission is a compile error: the safety net.)
2. **`deinit` touching main-actor state** → `@ObservationIgnored nonisolated(unsafe) private var`.
3. **Capturing `self`/`UserDefaults` in `Task.detached`** → copy the `@Sendable` provider
   to a local `let`; reference `.standard` only *inside* closures.
4. **`for await` on a throwing stream** → must be `for try await`, with
   `catch is CancellationError` **before** the generic catch.
5. **Making `MakeMKVTitle: Identifiable` in the app module** → use `ForEach(…, id: \.index)`.
6. **`if case`/`switch` with `let` bindings inside a `@ViewBuilder`** → expose
   `ripProgress: RipProgress?` / `isScanning` on the VM and use `if let`.
7. **`ContentUnavailableView`** → use the `{ label } description: { } actions: { }` form.
8. **`Toggle` label-closure / `Section` header-footer closures** → `Toggle(title, isOn: Binding(get:set:))`, `Section("title")`.
9. **`ProgressView(value:)` with an optional** → unwrap first.
10. **`.onChange(of:)` one-parameter closure** → deprecated; use the two- or zero-parameter form.
11. **Mock runner must be `final class … @unchecked Sendable` with `NSLock`** (the protocol is `Sendable`).
12. **Switch-expression syntax** (`case .x: "text"`) is not used in this repo → write `return`.
13. **`UTType.diskImage`** is unproven → leave `allowedContentTypes` unset on the ISO picker.
14. **`Tab(…, value:)` / `TabView(selection:)`** → out of scope for this slice (see D4).

## Hardware-matrix caveats (cannot be settled without a drive)

- PRGV semantics: `current` = current operation, `total` = whole job, `max` = 65536.
  If `total` resets per title on an `.all` run, the aggregate still holds (one run).
- `.all` vs `--minlength` — see D3; one-line fallback.
- macOS device path form is `dev:/dev/rdiskN`.
- Stream type names ("Video"/"Audio"/"Subtitles") may be localised by MakeMKV;
  `streamsText` is cosmetic and degrades gracefully — match on the numeric `code`
  (6201/6202) if that proves to be a problem.
- MakeMKV can exit non-zero *after* writing some files, so the failure copy says
  "stopped with an error" and the cancelled copy notes partial files remain.

## Optional follow-ups (NOT in 4b)

- Settings deep-link to the MakeMKV tab (all-or-nothing `TabView(selection:)` change).
- A "Find drives" button via `info(source: .disc(9999))` → `MakeMKVDiscInfo.drives`.
- Hoist the VM into `AppViewModel` so a rip survives navigation.
