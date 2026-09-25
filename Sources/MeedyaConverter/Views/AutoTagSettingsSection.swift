// ============================================================================
// MeedyaConverter — AutoTagSettingsSection (Issue #508, commit 9/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The Settings switch that finally lets someone turn auto-tagging on.
//
// Commits 1-8 of #508 built the whole machine — the readiness gate, the
// lookup runner, the encode-time hook inside `EncodingEngine`, and the wire
// from `AppViewModel`'s real engine to that machine — but until THIS commit
// nothing ever wrote `AutoTagSettingsStore.Keys.enabled` to `UserDefaults`.
// `UserDefaults.bool(forKey:)` answers `false` for a key nobody has written,
// so every real encode has been silently skipping the lookup the whole time,
// however complete the plumbing underneath it was. This file is the one
// piece that lets a person actually reach that plumbing.
//
// ⚠️ THE STATUS LINE MUST NEVER INVENT ITS OWN WORDING. It calls
// `AutoTagGate.readiness(in:hasTMDBKey:)` — the EXACT SAME function
// `AutoTagSettingsSource.currentRequest()` (the one a real job asks) agrees
// with — so this screen and a real encode can never quietly drift apart
// about whether auto-tagging is off, limited, or ready. See that type's own
// doc comment in `AutoTagSettings.swift`, and `MeedyaDBSettingsTab`'s status
// section for the same shape of check on a different feature.
//
// Inserted with one line into `MetadataSettingsTab`'s `Form`, directly below
// `providerKeysSection` — so the TMDB key field and this toggle sit on the
// same screen a person would naturally check together, and so `hasTMDBKey`
// (already kept fresh there on appear, after Save/Remove, and on
// `APIKeyManager.didChangeNotification`) needs no second copy of that
// refresh logic here.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - AutoTagSettingsSection

/// The "Tag files automatically while converting" section of the Metadata
/// settings tab: the master switch, the Kodi `.nfo` switch, and an honest
/// status line.
struct AutoTagSettingsSection: View {

    /// Whether a TMDB key is currently saved. Read by the caller
    /// (`MetadataSettingsTab.hasTMDBKey`), not here — this view has no
    /// `APIKeyManager` of its own, so it can never go stale independently
    /// of the tab that already keeps this fresh.
    let hasTMDBKey: Bool

    // MARK: Stored settings (engine-owned key spelling)
    //
    // `AutoTagSettingsStore.Keys` is the single source of truth both this
    // view and `EncodingEngine`'s per-job read agree on — using the
    // constants, never a string literal, is what keeps the two from ever
    // silently drifting onto different key spellings (the same reason
    // `MeedyaDBSettingsTab` reads `MeedyaDBConfigStore.Keys` above).

    /// The master switch. Off by default — `AutoTagSettingsStore.swift`'s
    /// own header explains why: this feature changes embedded tags, and
    /// issue #508 is explicit that must be opt-in.
    @AppStorage(AutoTagSettingsStore.Keys.enabled)
    private var enabled: Bool = false

    /// Whether an identified film should also get a Kodi `.nfo` sidecar.
    /// Meaningless while `enabled` is false — the toggle below is disabled
    /// in that state, and the writer never runs unless a lookup already
    /// succeeded, either way.
    @AppStorage(AutoTagSettingsStore.Keys.writeNFO)
    private var writeNFO: Bool = false

    // MARK: Body

    var body: some View {
        Section("Tag files automatically while converting") {
            Toggle("Look each file up and add the tags it's missing", isOn: $enabled)
                .accessibilityLabel("Automatically look up and tag files while converting")

            Text(
                "Films are looked up on TMDB and music on MusicBrainz. When this is on, "
                + "each file's title (and year, if known) is sent to them."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(
                "Only tags the file doesn't already have are added. Tags already in the "
                + "file are never replaced."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(
                "If a lookup fails, takes too long, or isn't confident of the match, the "
                + "file is still converted, just without the extra tags. The Activity Log "
                + "says what happened to each file."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("File names are never changed. TV episodes aren't looked up yet.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Scope, checked against the code rather than copied blind from
            // the plan: `AppViewModel.init` builds exactly ONE
            // `EncodingEngine` with an `AutoTagSettingsSource`, and that same
            // engine backs the queue, `enqueueWatchFolderFile`, the
            // scheduler's `onJobReady`, and `ScriptingBridge.shared.engine`
            // (wired in the same `init`) — so all four real paths share this
            // one setting. `EncodingPipelineExecutor` runs `ffmpeg`/
            // `ffprobe` directly and never calls `EncodingEngine.encode`, and
            // every `meedya-convert` subcommand builds its own standalone
            // `EncodingEngine()` with no settings source — so both sentences
            // below are still true today.
            Text(
                "Applies to conversions from the queue (including watch folders and "
                + "scheduled jobs) and from AppleScript. Encoding pipelines and the "
                + "meedya-convert command-line tool don't tag files."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Some formats, such as MP4, keep only the common tags.")
                .font(.caption)
                .foregroundStyle(.secondary)

            statusLine

            Toggle(
                "Also save a Kodi .nfo file next to each identified film",
                isOn: $writeNFO
            )
            .disabled(!enabled)
            .accessibilityLabel("Also save a Kodi NFO file next to each identified film")
            // VoiceOver users tabbing onto a disabled control hear "dimmed"
            // automatically; this hint says WHY, matching the visible
            // caption right below it.
            .accessibilityHint(
                enabled ? "" : "Turn on automatic tagging above to use this."
            )

            Text("An existing .nfo file is never overwritten.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status line

    /// One line, read straight off `AutoTagGate.readiness` — never a
    /// hand-written guess at what state the feature is in.
    @ViewBuilder
    private var statusLine: some View {
        let readiness = Self.readiness(hasTMDBKey: hasTMDBKey)
        let text = Self.statusText(for: readiness)
        Label(text, systemImage: Self.statusIcon(for: readiness))
            .font(.caption)
            .foregroundStyle(Self.statusColor(for: readiness))
            // `Label` already reads its text to VoiceOver by default, but
            // this is spelled out explicitly (matching the task's own
            // accessibility ask) rather than relying on that default.
            .accessibilityLabel(text)
    }

    // MARK: - Testable pieces
    //
    // SwiftUI views can't be unit-tested in this codebase (no view-inspection
    // library — see `.claude/local-test-harness.md`). These four `static`
    // functions are what `body` above actually calls, factored out so
    // `AutoTagAppWiringTests` can call them directly and prove the status
    // line's wording is `AutoTagGate`'s own, not a copy that could drift.

    /// The readiness verdict for `hasTMDBKey`, read from `defaults` — a thin
    /// pass-through to `AutoTagGate.readiness(in:hasTMDBKey:)`, the SAME
    /// function `AutoTagSettingsSource.currentRequest()` (a real job's own
    /// read) agrees with. `defaults` defaults to `.standard` — the store
    /// `@AppStorage` above implicitly reads and writes — but a test may pass
    /// its own isolated suite instead, so this can be exercised without ever
    /// touching the developer's real defaults.
    static func readiness(
        in defaults: UserDefaults = .standard,
        hasTMDBKey: Bool
    ) -> AutoTagReadiness {
        AutoTagGate.readiness(in: defaults, hasTMDBKey: hasTMDBKey)
    }

    /// The status line's exact text: `readiness.reason`, or
    /// `AutoTagGate.readyReason` for the one case (`.ready`) where `reason`
    /// is `nil` because nothing needs explaining.
    static func statusText(for readiness: AutoTagReadiness) -> String {
        readiness.reason ?? AutoTagGate.readyReason
    }

    /// SF Symbol for `readiness`, matching `MeedyaDBSettingsTab`'s own
    /// status section: neutral info for the default "off" state, a warning
    /// triangle for "on but limited", a checkmark for "ready".
    static func statusIcon(for readiness: AutoTagReadiness) -> String {
        switch readiness {
        case .off: return "info.circle"
        case .limited: return "exclamationmark.triangle"
        case .ready: return "checkmark.circle"
        }
    }

    /// Colour for `readiness`, same mapping as `statusIcon(for:)`.
    static func statusColor(for readiness: AutoTagReadiness) -> Color {
        switch readiness {
        case .off: return .secondary
        case .limited: return .orange
        case .ready: return .green
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Auto-Tag Settings — off") {
    Form { AutoTagSettingsSection(hasTMDBKey: false) }
        .formStyle(.grouped)
        .frame(width: 600, height: 500)
}

#Preview("Auto-Tag Settings — has TMDB key") {
    Form { AutoTagSettingsSection(hasTMDBKey: true) }
        .formStyle(.grouped)
        .frame(width: 600, height: 500)
}
#endif
