// ============================================================================
// MeedyaConverter — MakeMKVRipPlanning (Issue #503, slice 4b)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// FILE OVERVIEW
// -------------
// Slice 4b of the optional, opt-in MakeMKV backend (#503): the pure helpers
// behind the GUI rip flow. This file does NOT launch anything, read
// `UserDefaults`, or touch the file system — it only folds already-parsed
// `MakeMKVRipEvent`s / `MakeMKVTitle`s into display-ready state and plain
// English text, so it is unit-tested directly (`MakeMKVRipPlanningTests`,
// alongside the robot-mode fixtures `MakeMKVBackendTests` already has) and
// reusable by a future CLI front-end, exactly like
// `MakeMKVProgressEvent.totalFraction` next to it.
//
// It changes NO policy: nothing here decides whether MakeMKV may run (that
// is `MakeMKVGate`/`MakeMKVConsentStore`) or executes it (`MakeMKVExecutor`).
// ============================================================================

import Foundation

// MARK: - MakeMKVRipProgressTracker

/// Folds a stream of `MakeMKVRipEvent`s into steady display state for one rip
/// run: a caption for the overall job, a caption for the step currently
/// running, a fraction for each, and the latest status message. Pure and
/// mutating, so a view model can feed it events one at a time as they arrive
/// from `MakeMKVExecutor.rip`.
///
/// A `PRGV:` record whose `max` is not positive (see
/// `MakeMKVProgressEvent.totalFraction`/`.currentFraction`) is ignored rather
/// than resetting the fraction to `nil` — the previously recorded value is
/// kept so the bar never jumps backwards to "unknown".
public struct MakeMKVRipProgressTracker: Sendable, Equatable {

    /// The overall-job caption from the most recent `PRGT:` event, if any.
    public private(set) var overallCaption: String?
    /// The current-step caption from the most recent `PRGC:` event, if any.
    public private(set) var currentCaption: String?
    /// The overall-job progress, 0…1. `nil` until the first usable `PRGV:`.
    public private(set) var overallFraction: Double?
    /// The current-step progress, 0…1. `nil` until the first usable `PRGV:`.
    public private(set) var currentFraction: Double?
    /// The text of the most recent `MSG:` message, if any.
    public private(set) var lastMessage: String?

    public init() {}

    /// Fold one event into the tracker's state.
    public mutating func record(_ event: MakeMKVRipEvent) {
        switch event {
        case .progress(let progress):
            switch progress {
            case .totalTitle(_, _, let name):
                overallCaption = name
            case .currentTitle(_, _, let name):
                currentCaption = name
            case .values:
                if let fraction = progress.totalFraction {
                    overallFraction = fraction
                }
                if let fraction = progress.currentFraction {
                    currentFraction = fraction
                }
            }
        case .message(let message):
            lastMessage = message.text
        }
    }
}

// MARK: - MakeMKVTitleSummary

/// Display-ready strings for one `MakeMKVTitle`, computed once so the rip
/// UI never has to re-derive them per render.
public struct MakeMKVTitleSummary: Sendable, Equatable {

    /// The title's own name, else its source object name, else "Title N"
    /// (1-based, so the very first title on a disc reads "Title 1").
    public let displayName: String
    /// The disc's own duration string (e.g. "1:57:21"), if reported.
    public let durationText: String?
    /// A human size string. Prefers MakeMKV's own "26.5 GB"-style text;
    /// falls back to formatting `sizeBytes` when only the exact byte count
    /// is available.
    public let sizeText: String?
    /// "N chapter(s)", if a chapter count was reported.
    public let chaptersText: String?
    /// A short "N Video, N Audio, N Subtitles"-style summary of the title's
    /// streams, grouped by MakeMKV's own type name and in first-seen order.
    /// `nil` when the title has no streams. Cosmetic — if MakeMKV ever
    /// localises these type names, the grouping still works (it does not
    /// hardcode the English words), it just prints the localised ones.
    public let streamsText: String?

    public init(title: MakeMKVTitle) {
        displayName = title.name ?? title.sourceFileName ?? "Title \(title.index + 1)"
        durationText = title.duration

        if let text = title.sizeText {
            sizeText = text
        } else if let bytes = title.sizeBytes {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            sizeText = formatter.string(fromByteCount: bytes)
        } else {
            sizeText = nil
        }

        if let count = title.chapterCount {
            chaptersText = count == 1 ? "1 chapter" : "\(count) chapters"
        } else {
            chaptersText = nil
        }

        streamsText = Self.streamsSummary(for: title)
    }

    private static func streamsSummary(for title: MakeMKVTitle) -> String? {
        guard !title.streams.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for stream in title.streams {
            let typeName = stream.typeName ?? "Other"
            if counts[typeName] == nil { order.append(typeName) }
            counts[typeName, default: 0] += 1
        }
        return order.map { "\(counts[$0] ?? 0) \($0)" }.joined(separator: ", ")
    }
}

// MARK: - MakeMKVRipPlanning

/// A pure namespace of rip-planning helpers: default title selection,
/// selector building for the `mkv` command, aggregate progress across
/// several sequential rip runs, and plain-English failure text.
public enum MakeMKVRipPlanning {

    // MARK: Default selection

    /// The "main feature" guess used to pre-check titles right after a scan:
    /// the title with the greatest `durationSeconds`, ties broken by the
    /// greatest `sizeBytes`, remaining ties broken by the lowest index.
    ///
    /// A lone title is always selected, regardless of whether its duration
    /// parsed. With two or more titles, this NEVER guesses at a title whose
    /// duration didn't parse: if none of them have a usable duration, the
    /// result is empty and the user picks manually.
    ///
    /// - Parameter titles: The disc's titles, in any order.
    /// - Returns: The set of selected title indices (0 or 1 members).
    public static func defaultSelection(for titles: [MakeMKVTitle]) -> Set<Int> {
        guard titles.count > 1 else {
            return Set(titles.map(\.index))
        }

        let candidates = titles.filter { $0.durationSeconds != nil }
        guard let first = candidates.first else { return [] }

        let best = candidates.dropFirst().reduce(first) { current, candidate in
            let currentDuration = current.durationSeconds ?? 0
            let candidateDuration = candidate.durationSeconds ?? 0
            if candidateDuration != currentDuration {
                return candidateDuration > currentDuration ? candidate : current
            }
            let currentSize = current.sizeBytes ?? 0
            let candidateSize = candidate.sizeBytes ?? 0
            if candidateSize != currentSize {
                return candidateSize > currentSize ? candidate : current
            }
            return candidate.index < current.index ? candidate : current
        }
        return [best.index]
    }

    // MARK: Selector building

    /// Turn a set of selected title indices into the `MakeMKVTitleSelector`
    /// run(s) needed to rip them:
    ///   - nothing selected → `[]` (nothing to run).
    ///   - every listed title selected → `[.all]` (one run).
    ///   - otherwise → one `.index` per selected title, ascending.
    ///
    /// - Parameters:
    ///   - selected: The user's selected title indices.
    ///   - allTitleIndices: Every title index the last scan listed.
    public static func selectors(
        forSelected selected: Set<Int>,
        allTitleIndices: [Int]
    ) -> [MakeMKVTitleSelector] {
        guard !selected.isEmpty else { return [] }
        if !allTitleIndices.isEmpty, Set(allTitleIndices) == selected {
            return [.all]
        }
        return selected.sorted().map { .index($0) }
    }

    // MARK: Aggregate progress

    /// The overall 0…1 fraction across a sequence of `totalRuns` sequential
    /// rip runs, given how many have already finished and the in-progress
    /// fraction of the current one. Clamped to 0…1 so a stray out-of-range
    /// input (e.g. `completedRuns > totalRuns`) can never show a nonsensical
    /// bar.
    ///
    /// - Parameters:
    ///   - completedRuns: How many runs have already finished.
    ///   - totalRuns: The total number of runs in this rip.
    ///   - currentRunFraction: The in-progress run's own 0…1 fraction, or
    ///     `nil` before its first progress event arrives.
    public static func aggregateFraction(
        completedRuns: Int,
        totalRuns: Int,
        currentRunFraction: Double?
    ) -> Double {
        guard totalRuns > 0 else { return 0 }
        let base = Double(completedRuns) / Double(totalRuns)
        let current = (currentRunFraction ?? 0) / Double(totalRuns)
        return min(1, max(0, base + current))
    }

    // MARK: Failure text

    /// Plain-English text for a failed or cancelled rip/scan, suitable for
    /// showing directly to a non-technical user. Text for each
    /// `MakeMKVExecutorError` case is pinned verbatim by
    /// `MakeMKVRipPlanningTests` — treat a change here as a user-facing
    /// copy change, not a refactor.
    ///
    /// Deliberately silent about partial output files: `info` (used while
    /// scanning) never writes any, so that caveat isn't true in every
    /// context this helper is used from. The rip flow, where it IS true,
    /// adds its own sentence about partial files on top of this text — see
    /// `MakeMKVRipViewModel`.
    public static func failureSummary(for error: Error) -> String {
        if error is CancellationError {
            return "The rip was cancelled."
        }
        if let executorError = error as? MakeMKVExecutorError {
            switch executorError {
            case .notConsented:
                return "MakeMKV is not turned on for this app yet. Turn it on and add your terms "
                    + "acknowledgement in Settings, then try again."
            case .launchFailed(let path, let reason):
                return "MakeMKV could not be started (\(path)): \(reason)"
            case .processFailure(let exitCode, let snippet):
                let detail = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty
                    ? "MakeMKV stopped with an error (code \(exitCode))."
                    : "MakeMKV stopped with an error: \(detail)."
            }
        }
        return "The rip failed: \(error.localizedDescription)"
    }
}
