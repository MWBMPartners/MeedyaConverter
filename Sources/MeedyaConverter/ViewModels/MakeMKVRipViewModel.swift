// ============================================================================
// MeedyaConverter — MakeMKVRipViewModel (Issue #503, slice 4b)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The view model behind the MakeMKV GUI rip flow (`MakeMKVRipView`): scan a
// disc/device/ISO for its titles via `MakeMKVExecutor.info`, let the user
// pick which titles to rip, then run `MakeMKVExecutor.rip` — sequentially,
// one call per selected title, unless every listed title is selected, in
// which case a single `.all` run is used instead (D3 in the design plan).
//
// The gate (may we run MakeMKV at all?) is re-checked before every action —
// on appear, whenever any of the three `MakeMKVConsentStore.Keys` changes,
// and again at the start of `scan()`/`rip()` — by building a brand-new
// `MakeMKVExecutor` each time, so consent can never go stale mid-session
// (D6). `MakeMKVExecutor.make(readiness:consent:runner:)` itself refuses to
// touch `runner` at all when the gate is closed, so a gated action makes
// zero calls into the injected seam — see `MakeMKVRipViewModelTests`.
//
// `runner`/`readinessProvider`/`consentProvider` are injected so tests need
// no real subprocess and no real `UserDefaults` — mirrors
// `QualityMetricsViewModel`'s seams and `MakeMKVExecutorTests`'s mock.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - MakeMKVRipViewModel

@MainActor
@Observable
final class MakeMKVRipViewModel {

    // MARK: - Injected seams

    // `let` (immutable), so `@Observable` never instruments these — no
    // `@ObservationIgnored` needed, unlike the `var` task handles below.
    private let runner: any MakeMKVLineStreaming
    private let readinessProvider: @Sendable () -> MakeMKVReadiness
    private let consentProvider: @Sendable () -> MakeMKVConsent?

    init(
        runner: any MakeMKVLineStreaming = MakeMKVProcessRunner(),
        readinessProvider: @escaping @Sendable () -> MakeMKVReadiness = { MakeMKVGate.readiness(in: .standard) },
        consentProvider: @escaping @Sendable () -> MakeMKVConsent? = { MakeMKVConsentStore.consent(in: .standard) }
    ) {
        self.runner = runner
        self.readinessProvider = readinessProvider
        self.consentProvider = consentProvider
    }

    // MARK: - Gate

    /// The latest verdict on whether MakeMKV can be used at all. `nil` only
    /// before the first `refreshGate()` call (the view shows a spinner then).
    private(set) var readiness: MakeMKVReadiness?

    /// Re-checks the gate from the injected providers. Called on the view's
    /// `onAppear`, whenever any of the three `MakeMKVConsentStore.Keys`
    /// changes, and again at the start of `scan()`/`rip()` (D6) — never
    /// cached across an action.
    func refreshGate() {
        readiness = readinessProvider()
    }

    /// A plain-English explanation of why MakeMKV isn't ready, for the
    /// gated `ContentUnavailableView`. Meaningful only while `readiness` is
    /// not `.ready`.
    var gateDescription: String {
        switch readiness {
        case .notEnabled(let reason), .notInstalled(let reason):
            return reason
        case .ready, .none:
            return "Checking MakeMKV status\u{2026}"
        }
    }

    /// The outcome of `gatedExecutor()`. Not `Result<MakeMKVExecutor, String>`
    /// — `Result`'s failure type must conform to `Error`, and a plain
    /// display `String` deliberately doesn't (it is already-formatted user
    /// text, not a thrown error).
    private enum GateOutcome {
        case ready(MakeMKVExecutor)
        case blocked(String)
    }

    /// Re-checks the gate (D6 — always the first thing `scan()`/`rip()` do)
    /// and, if open, builds a fresh executor. Returns the plain-English
    /// reason to show the user when it isn't. `MakeMKVExecutor.make` never
    /// touches `runner` unless the gate is open, and this returns before
    /// that call at all when `readiness.isReady` is false, so a closed gate
    /// guarantees zero calls into the injected seam.
    private func gatedExecutor() -> GateOutcome {
        refreshGate()
        guard let currentReadiness = readiness, currentReadiness.isReady else {
            return .blocked(gateDescription)
        }
        do {
            let executor = try MakeMKVExecutor.make(
                readiness: currentReadiness,
                consent: consentProvider(),
                runner: runner
            )
            return .ready(executor)
        } catch {
            return .blocked(MakeMKVRipPlanning.failureSummary(for: error))
        }
    }

    // MARK: - Source

    /// The kind of source the user is pointing at — every case
    /// `MakeMKVSource` offers.
    enum SourceKind: String, CaseIterable, Identifiable {
        case opticalDrive = "Optical Drive"
        case devicePath = "Device Path"
        case discImage = "Disc Image (ISO)"
        /// A folder of already-decrypted disc files — the parent of a
        /// `VIDEO_TS` or `BDMV` directory. Nothing is unlocked here: the
        /// files have already been decrypted by whatever produced them.
        case discFolder = "Disc Folder (VIDEO_TS / BDMV)"
        var id: String { rawValue }
    }

    var sourceKind: SourceKind = .opticalDrive
    /// MakeMKV numbers drives from 0; text (not Int) so the field can be
    /// empty/invalid without crashing, caught by `resolvedSource == nil`.
    var discIndexText: String = "0"
    var devicePath: String = ""
    var isoPath: String = ""
    var folderPath: String = ""

    /// The current fields resolved to an engine `MakeMKVSource`, or `nil`
    /// when they don't describe one yet (blank path, non-numeric drive
    /// number) — never guessed at.
    var resolvedSource: MakeMKVSource? {
        switch sourceKind {
        case .opticalDrive:
            let trimmed = discIndexText.trimmingCharacters(in: .whitespaces)
            guard let index = Int(trimmed), index >= 0 else { return nil }
            return .disc(index)
        case .devicePath:
            let trimmed = devicePath.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : .device(trimmed)
        case .discImage:
            let trimmed = isoPath.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : .iso(trimmed)
        case .discFolder:
            let trimmed = folderPath.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : .file(trimmed)
        }
    }

    // MARK: - Scan / Titles

    private(set) var isScanning = false
    /// True between `cancelScan()` and the scan task actually finishing.
    /// `makemkvcon info` can take a while to notice and exit, and because
    /// `cancelScan()` deliberately clears no state (see its doc comment),
    /// without this the Cancel button would look inert for that whole time.
    private(set) var isCancellingScan = false
    private(set) var discInfo: MakeMKVDiscInfo?
    private(set) var titleSummaries: [Int: MakeMKVTitleSummary] = [:]
    private(set) var scanErrorMessage: String?

    /// The user's selected title indices — pre-filled by
    /// `MakeMKVRipPlanning.defaultSelection` after a scan, then editable.
    var selectedTitleIndices: Set<Int> = []

    /// The scanned titles, sorted by index — safe to `ForEach(…, id: \.index)`
    /// without conforming `MakeMKVTitle` to `Identifiable` in this module.
    var orderedTitles: [MakeMKVTitle] {
        (discInfo?.titles ?? []).sorted { $0.index < $1.index }
    }

    var canScan: Bool {
        !isScanning && !isRipping && resolvedSource != nil
    }

    /// Why the Scan button is disabled, in plain English, or `nil` when it
    /// is enabled — a disabled button must never leave the user guessing.
    /// `nil` while scanning too: the button already reads "Scanning…", so a
    /// caption saying the same thing would just be noise.
    var scanBlockedReason: String? {
        if isScanning { return nil }
        if isRipping { return "A rip is in progress. Wait for it to finish before scanning." }
        guard resolvedSource == nil else { return nil }
        switch sourceKind {
        case .opticalDrive:
            return "Enter the drive number to scan \u{2014} 0 is the first drive."
        case .devicePath:
            return "Enter the device path of the drive to scan."
        case .discImage:
            return "Choose a disc image file to scan."
        case .discFolder:
            return "Choose the folder that contains VIDEO_TS or BDMV."
        }
    }

    @ObservationIgnored
    nonisolated(unsafe) private var scanTask: Task<Void, Never>?

    /// Scans the current source for its titles. Synchronous entry point
    /// (mirrors `QualityMetricsViewModel.runAnalysis()`) so a `Button`
    /// action needs no `Task { }` wrapper; the returned task is also handed
    /// back so tests can `await` it deterministically instead of polling.
    @discardableResult
    func scan() -> Task<Void, Never>? {
        // Guard first, then clear — same reason as in `rip()`.
        guard !isScanning, !isRipping else { return nil }

        scanErrorMessage = nil
        // Also drop the previous rip's banner: leaving "Rip complete…" on
        // screen while a new scan runs describes work that is no longer
        // what the screen is doing.
        outcomeMessage = nil
        outcomeIsError = false

        let executor: MakeMKVExecutor
        switch gatedExecutor() {
        case .blocked(let message):
            scanErrorMessage = message
            return nil
        case .ready(let value):
            executor = value
        }

        guard let source = resolvedSource else {
            scanErrorMessage = "Enter a disc number, device path or disc image path first."
            return nil
        }

        isScanning = true
        isCancellingScan = false
        discInfo = nil
        titleSummaries = [:]
        selectedTitleIndices = []

        // Unwrap `self` first: `await self?.x()` makes the closure return `()?`, so
        // the task would be a `Task<()?, Never>` and not match `Task<Void, Never>`.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performScan(source: source, executor: executor)
        }
        scanTask = task
        return task
    }

    private func performScan(source: MakeMKVSource, executor: MakeMKVExecutor) async {
        do {
            let info = try await executor.info(source: source)
            discInfo = info
            titleSummaries = Dictionary(
                uniqueKeysWithValues: info.titles.map { ($0.index, MakeMKVTitleSummary(title: $0)) }
            )
            selectedTitleIndices = MakeMKVRipPlanning.defaultSelection(for: info.titles)
        } catch is CancellationError {
            // Scanning never writes a destination file, unlike a rip, so
            // this deliberately does NOT reuse `failureSummary`'s
            // rip-worded "The rip was cancelled." text.
            scanErrorMessage = "The scan was cancelled."
        } catch {
            scanErrorMessage = MakeMKVRipPlanning.failureSummary(for: error)
        }
        isScanning = false
        isCancellingScan = false
        scanTask = nil
    }

    /// Cancels an in-progress scan. Like `cancelRip()`, this ONLY cancels —
    /// cleanup (`isScanning`, `scanTask`, the "cancelled" message) happens
    /// inside `performScan` once it notices, in its `catch is CancellationError`
    /// branch. Clearing that state here too would let a cancelled task's tail
    /// land *after* a newer scan has already started and clobber it: the
    /// newer scan's `isScanning`/`scanTask` would be wiped and its error
    /// message overwritten by the old run's.
    func cancelScan() {
        guard scanTask != nil, isScanning else { return }
        isCancellingScan = true
        scanTask?.cancel()
    }

    // MARK: - Destination

    var destinationPath: String = ""

    // MARK: - Run

    private(set) var isRipping = false
    /// True between `cancelRip()` and the rip task actually finishing —
    /// the rip's counterpart to `isCancellingScan`, for the same reason:
    /// MakeMKV only notices cancellation between events.
    private(set) var isCancellingRip = false
    private(set) var ripProgress: RipProgress?
    private(set) var outcomeMessage: String?
    private(set) var outcomeIsError = false
    private(set) var messages: [String] = []

    private static let messageCap = 200

    /// Steady display state for the rip in progress — flattened to plain,
    /// non-optional-where-possible fields so the view reads it with `if let`
    /// rather than switching on `MakeMKVRipEvent`/`MakeMKVProgressEvent`.
    struct RipProgress: Equatable {
        var overallCaption: String?
        var currentCaption: String?
        var overallFraction: Double
        var currentFraction: Double?
        var runLabel: String
    }

    var canRip: Bool {
        !isScanning && !isRipping && !selectedTitleIndices.isEmpty
            && !destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Why the Rip button is disabled, in plain English, or `nil` when it is
    /// enabled. `nil` while ripping: the progress row replaces the button
    /// entirely, so there is no disabled control left to explain. When more
    /// than one thing is missing this names the first step, not all of them.
    var ripBlockedReason: String? {
        if isRipping { return nil }
        if isScanning { return "Scanning the disc. The rip can start once the scan finishes." }
        if selectedTitleIndices.isEmpty {
            return orderedTitles.isEmpty
                ? "Scan the disc first, then choose which titles to rip."
                : "Select at least one title to rip."
        }
        if destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a destination folder to save the ripped titles in."
        }
        return nil
    }

    @ObservationIgnored
    nonisolated(unsafe) private var ripTask: Task<Void, Never>?

    /// Starts ripping the selected titles. Synchronous entry point (see
    /// `scan()`'s doc comment); returns the task so tests can `await` it.
    /// Every guard below runs BEFORE any executor is built, so a rejected
    /// call (gate closed, nothing selected, no destination) makes zero
    /// calls into the injected runner.
    @discardableResult
    func rip() -> Task<Void, Never>? {
        // The already-running guard comes FIRST: clearing above it would let
        // a second press wipe the live progress and message log of the rip
        // that is still running, then return `nil` having changed nothing else.
        guard !isScanning, !isRipping else { return nil }

        outcomeMessage = nil
        outcomeIsError = false
        messages = []
        ripProgress = nil
        // And the mirror of the clear in `scan()`: a leftover scan error
        // is not about the rip the user just started.
        scanErrorMessage = nil

        let executor: MakeMKVExecutor
        switch gatedExecutor() {
        case .blocked(let message):
            return fail(message)
        case .ready(let value):
            executor = value
        }

        guard let source = resolvedSource else {
            return fail("Enter a disc number, device path or disc image path first.")
        }
        let destination = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else {
            return fail("Choose a destination folder before starting a rip.")
        }
        guard !selectedTitleIndices.isEmpty else {
            return fail("Select at least one title to rip.")
        }

        let allIndices = orderedTitles.map(\.index)
        let selectors = MakeMKVRipPlanning.selectors(forSelected: selectedTitleIndices, allTitleIndices: allIndices)
        guard !selectors.isEmpty else {
            return fail("Select at least one title to rip.")
        }

        let titleCount = selectedTitleIndices.count
        isRipping = true
        isCancellingRip = false
        // As above: unwrap before awaiting, or the task's type becomes `Task<()?, Never>`.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeRip(
                source: source, destination: destination, executor: executor,
                selectors: selectors, titleCount: titleCount)
        }
        ripTask = task
        return task
    }

    /// Records an outcome error and returns `nil` — the common shape every
    /// pre-flight guard in `rip()` uses.
    private func fail(_ message: String) -> Task<Void, Never>? {
        outcomeMessage = message
        outcomeIsError = true
        return nil
    }

    private func executeRip(
        source: MakeMKVSource,
        destination: String,
        executor: MakeMKVExecutor,
        selectors: [MakeMKVTitleSelector],
        titleCount: Int
    ) async {
        let totalRuns = selectors.count
        var completedRuns = 0
        var didFail = false

        runLoop: for selector in selectors {
            if Task.isCancelled { break runLoop }

            var tracker = MakeMKVRipProgressTracker()
            ripProgress = RipProgress(
                overallCaption: nil,
                currentCaption: nil,
                overallFraction: MakeMKVRipPlanning.aggregateFraction(
                    completedRuns: completedRuns, totalRuns: totalRuns, currentRunFraction: nil),
                currentFraction: nil,
                runLabel: runLabel(index: completedRuns, total: totalRuns)
            )

            do {
                for try await event in executor.rip(source: source, titles: selector, destinationDirectory: destination) {
                    // Point 1 of 3 — noticed between already-buffered events.
                    if Task.isCancelled { break runLoop }

                    tracker.record(event)
                    if case .message(let message) = event {
                        appendMessage(message.text)
                    }
                    ripProgress = RipProgress(
                        overallCaption: tracker.overallCaption,
                        currentCaption: tracker.currentCaption,
                        overallFraction: MakeMKVRipPlanning.aggregateFraction(
                            completedRuns: completedRuns, totalRuns: totalRuns,
                            currentRunFraction: tracker.overallFraction),
                        currentFraction: tracker.currentFraction,
                        runLabel: runLabel(index: completedRuns, total: totalRuns)
                    )
                }
            } catch is CancellationError {
                // Point 2 of 3 — cancellation surfaced as a thrown error.
                outcomeMessage = ripFailureMessage(for: CancellationError())
                outcomeIsError = true
                didFail = true
                break runLoop
            } catch {
                outcomeMessage = ripFailureMessage(for: error)
                outcomeIsError = true
                didFail = true
                break runLoop
            }

            // Point 3 of 3 — the stream can end normally (no error thrown)
            // when cancellation unblocked `next()` rather than failing it.
            if Task.isCancelled {
                outcomeMessage = ripFailureMessage(for: CancellationError())
                outcomeIsError = true
                didFail = true
                break runLoop
            }

            completedRuns += 1
        }

        if !didFail {
            if completedRuns == totalRuns {
                // `titleCount`, not `completedRuns`/`totalRuns`: the `.all`
                // optimisation can rip several titles in a single run, and
                // the message must count titles, not runs.
                outcomeMessage = titleCount == 1
                    ? "Rip complete. The title was saved to \(destination)."
                    : "Rip complete. \(titleCount) titles were saved to \(destination)."
                outcomeIsError = false
            } else {
                outcomeMessage = ripFailureMessage(for: CancellationError())
                outcomeIsError = true
            }
        }

        ripProgress = nil
        isRipping = false
        isCancellingRip = false
        ripTask = nil
    }

    /// `MakeMKVRipPlanning.failureSummary` stays silent about partial output
    /// files (it's shared with the scan path, which never writes any) —
    /// this appends the caveat that IS true here: MakeMKV can exit non-zero,
    /// or be cancelled, after already having written some titles to disk.
    private func ripFailureMessage(for error: Error) -> String {
        MakeMKVRipPlanning.failureSummary(for: error) + " Any files already written remain in the destination folder."
    }

    private func runLabel(index: Int, total: Int) -> String {
        total <= 1 ? "Ripping\u{2026}" : "Ripping title \(index + 1) of \(total)\u{2026}"
    }

    private func appendMessage(_ text: String) {
        messages.append(text)
        if messages.count > Self.messageCap {
            messages.removeFirst(messages.count - Self.messageCap)
        }
    }

    /// Cancels an in-progress rip. Cleanup (state, outcome text) happens
    /// inside the running task itself once it notices the cancellation —
    /// see the three cancellation points in `executeRip`.
    func cancelRip() {
        guard ripTask != nil, isRipping else { return }
        isCancellingRip = true
        ripTask?.cancel()
    }

    // MARK: - Deinit

    /// Non-isolated (as `deinit` always is, even for a `@MainActor` class)
    /// and touches only the `nonisolated(unsafe)` task vars — mirrors
    /// `QualityMetricsViewModel.deinit`. This is the belt-and-braces
    /// cancellation path for D5 (navigating away cancels a rip); the
    /// primary path is the view's `.onDisappear` calling `cancelRip()`/
    /// `cancelScan()` directly.
    deinit {
        scanTask?.cancel()
        ripTask?.cancel()
    }
}
