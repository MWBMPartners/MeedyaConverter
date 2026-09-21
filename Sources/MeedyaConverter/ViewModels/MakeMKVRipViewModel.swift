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

    /// Builds the video identifier for ONE run, from the MeedyaDB config and
    /// the TMDB key in force at that moment.
    ///
    /// ⚠️ A FACTORY, NOT A STORED IDENTIFIER, and the identify screen learned
    /// this the expensive way. A stored one is built once with whatever
    /// existed at construction — for the production default, an empty and
    /// DISABLED publisher — so the screen would say "this disc will also be
    /// contributed" and then report that publishing was off, having sent
    /// nothing. Being told nothing was wrong while nothing was sent is the
    /// one behaviour this must not have.
    private let videoIdentifierFactory: @Sendable (MeedyaDBPublisherConfig?, TMDBLookupService?) -> VideoDiscIdentifier
    /// How much to send, read fresh per run from the user's setting. Read per
    /// run rather than cached, so the Settings picker is never a dead control.
    private let submissionModeProvider: @Sendable () -> MeedyaDBSubmissionMode
    private let meedyaDBReadinessProvider: @Sendable () -> MeedyaDBReadiness
    /// The stored TMDB credential, or `nil`. Without one the disc is still
    /// identified from its own structure and still contributed — that is a
    /// normal state, not a failure.
    private let tmdbKeyProvider: @Sendable () -> String?

    init(
        runner: any MakeMKVLineStreaming = MakeMKVProcessRunner(),
        readinessProvider: @escaping @Sendable () -> MakeMKVReadiness = { MakeMKVGate.readiness(in: .standard) },
        consentProvider: @escaping @Sendable () -> MakeMKVConsent? = { MakeMKVConsentStore.consent(in: .standard) },
        videoIdentifierFactory: @escaping @Sendable (MeedyaDBPublisherConfig?, TMDBLookupService?) -> VideoDiscIdentifier = { config, service in
            let candidateProvider = service.map { TMDBDiscCandidates.provider(service: $0) }
            guard let config else {
                return VideoDiscIdentifier(candidateProvider: candidateProvider)
            }
            return VideoDiscIdentifier(
                publisher: MeedyaDBPublisher(config: config),
                candidateProvider: candidateProvider
            )
        },
        submissionModeProvider: @escaping @Sendable () -> MeedyaDBSubmissionMode = {
            MeedyaDBConfigStore.submissionMode(in: .standard)
        },
        meedyaDBReadinessProvider: @escaping @Sendable () -> MeedyaDBReadiness = {
            MeedyaDBGate.readiness(in: .standard, apiKey: APIKeyManager().key(for: .meedyaDB)?.apiKey)
        },
        tmdbKeyProvider: @escaping @Sendable () -> String? = {
            APIKeyManager().key(for: .tmdb)?.apiKey
        }
    ) {
        self.runner = runner
        self.readinessProvider = readinessProvider
        self.consentProvider = consentProvider
        self.videoIdentifierFactory = videoIdentifierFactory
        self.submissionModeProvider = submissionModeProvider
        self.meedyaDBReadinessProvider = meedyaDBReadinessProvider
        self.tmdbKeyProvider = tmdbKeyProvider
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
        !isScanning && !isRipping && !isIdentifying && resolvedSource != nil
    }

    /// Why the Scan button is disabled, in plain English, or `nil` when it
    /// is enabled — a disabled button must never leave the user guessing.
    /// `nil` while scanning too: the button already reads "Scanning…", so a
    /// caption saying the same thing would just be noise.
    var scanBlockedReason: String? {
        if isScanning { return nil }
        if isRipping { return "A rip is in progress. Wait for it to finish before scanning." }
        if isIdentifying {
            return "This disc is being identified. Wait for that to finish, or cancel it, before scanning again."
        }
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
        //
        // ⚠️ `!isIdentifying` IS LOAD-BEARING, NOT TIDINESS. Without it the
        // Scan button stays live during an identification that can take a
        // dozen TMDB requests, and this is what happens: `scan()` clears
        // `identifyResult`, then the OLD run's tail — which captured the old
        // `info` and disc type when it started — writes its result straight
        // back. The previous film's name and contribution outcome then sit
        // under a completely different disc. The cancelled-message path has
        // the same shape.
        //
        // Excluding the two closes it completely, and for a second-order
        // reason worth spelling out: an in-flight identification now always
        // reaches its own tail BEFORE a new scan can begin, so everything it
        // writes is written before `scan()` clears — and `scan()` clears it.
        // The same insight fixed `cancelScan()` earlier: the guard, not the
        // clearing, is what makes the race impossible.
        guard !isScanning, !isRipping, !isIdentifying else { return nil }

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
        // A previous disc's identification must not survive into this one.
        // Leaving the old name on screen while a different disc is scanned
        // is worse than showing nothing: it names the wrong film.
        identifyResult = nil
        identifyErrorMessage = nil
        selectedDiscType = nil

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
            // Pre-fill the disc type from MakeMKV's own type string. A
            // SUGGESTION only — it stays editable, and stays nil when MakeMKV
            // said nothing recognisable, which leaves the Identify button
            // blocked with a caption asking for it rather than guessing.
            selectedDiscType = MakeMKVIdentification.suggestedDiscType(from: info)
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

    // MARK: - Identify the disc (#502)

    // Identification needs NO MakeMKV executor and starts no subprocess: it
    // works entirely from the `discInfo` the scan already produced, plus an
    // optional TMDB lookup. It is therefore deliberately NOT put through
    // `gatedExecutor()` — the gate was already satisfied by the scan that
    // produced this data, and re-checking it here would refuse to name a
    // disc the user had already legitimately scanned.
    //
    // This lives on the rip screen rather than the Identify Disc screen
    // because a video disc's structure only exists once MakeMKV has scanned
    // it, and that scan can take minutes on a Blu-ray. Asking for a second
    // scan on another screen would be slower and would duplicate the consent
    // gate. Music is the other way round: it reads a table of contents with
    // cdrdao, needs no MakeMKV at all, and so has its own screen.

    /// The kinds of disc this screen can identify. Audio discs are absent on
    /// purpose: they are identified from a table of contents on the Identify
    /// Disc screen, which gets an exact MusicBrainz match rather than the
    /// ranked guess this path produces.
    static let identifiableDiscTypes: [DiscType] = [.dvdVideo, .bluray, .uhdBluray, .hdDvd, .vcd, .svcd]

    /// What kind of disc this is. Pre-filled from MakeMKV's own type string
    /// after a scan (see `MakeMKVIdentification.suggestedDiscType`) and freely
    /// changeable — the suggestion is never treated as fact, because the wrong
    /// disc type would go into a shared database and cannot be walked back.
    var selectedDiscType: DiscType?

    /// MakeMKV's suggestion for the current scan, for a caption explaining
    /// where the pre-filled value came from. `nil` when it had no opinion.
    var suggestedDiscType: DiscType? {
        discInfo.flatMap { MakeMKVIdentification.suggestedDiscType(from: $0) }
    }

    private(set) var isIdentifying = false
    /// True between `cancelIdentify()` and the task noticing — the same
    /// reason `isCancellingScan` exists: a TMDB request in flight can take a
    /// moment to unwind, and the button must not look inert meanwhile.
    private(set) var isCancellingIdentify = false
    private(set) var identifyResult: VideoDiscIdentificationResult?
    private(set) var identifyErrorMessage: String?

    /// Whether contributing is switched on and usable. Re-read rather than
    /// cached, so turning MeedyaDB on in Settings takes effect immediately.
    private(set) var meedyaDBReadiness: MeedyaDBReadiness?

    func refreshMeedyaDBReadiness() {
        meedyaDBReadiness = meedyaDBReadinessProvider()
    }

    /// Whether the next run will try to contribute.
    ///
    /// ⚠️ This is the PROMISE the screen makes, and `identify()` derives what
    /// it actually does from the very same provider, immediately before the
    /// run. They must never be computed from different things — a screen that
    /// promises a contribution and silently sends nothing is the specific
    /// failure this wiring exists to avoid.
    var willContribute: Bool {
        meedyaDBReadiness?.isReady == true
    }

    var canIdentify: Bool {
        !isScanning && !isIdentifying && discInfo != nil && selectedDiscType != nil
    }

    /// Why the Identify button is disabled, or `nil` when it is enabled. A
    /// disabled control must always name the next step.
    ///
    /// Note this does NOT block on `isRipping`: identification runs no tool
    /// and touches no file, so there is no reason to make someone wait out a
    /// rip that may take an hour.
    var identifyBlockedReason: String? {
        if isIdentifying { return nil }
        if isScanning { return "Wait for the scan to finish \u{2014} identifying uses what it finds." }
        if discInfo == nil { return "Scan the disc first, then it can be identified." }
        if selectedDiscType == nil { return "Choose what kind of disc this is first." }
        return nil
    }

    @ObservationIgnored
    nonisolated(unsafe) private var identifyTask: Task<Void, Never>?

    /// Identifies the scanned disc and, when MeedyaDB is on and configured,
    /// contributes it. Synchronous entry point like `scan()`/`rip()`; the
    /// task is returned so tests can await it rather than poll.
    @discardableResult
    func identify() -> Task<Void, Never>? {
        guard !isScanning, !isIdentifying else { return nil }
        guard let info = discInfo else {
            identifyErrorMessage = "Scan the disc first, then it can be identified."
            return nil
        }
        guard let discType = selectedDiscType else {
            identifyErrorMessage = "Choose what kind of disc this is first."
            return nil
        }

        identifyErrorMessage = nil
        identifyResult = nil

        // Everything the run depends on is resolved ONCE, here, and the
        // identifier is built from those same values. `contribute` is derived
        // from the config that was just read rather than from a separate
        // check, so what the screen promised and what it does cannot drift.
        refreshMeedyaDBReadiness()
        let config = meedyaDBReadiness?.config
        let contribute = config != nil
        let mode = submissionModeProvider()
        let identifier = videoIdentifierFactory(config, Self.tmdbService(from: tmdbKeyProvider()))

        isIdentifying = true
        isCancellingIdentify = false

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performIdentify(
                info: info,
                discType: discType,
                identifier: identifier,
                contribute: contribute,
                mode: mode
            )
        }
        identifyTask = task
        return task
    }

    private func performIdentify(
        info: MakeMKVDiscInfo,
        discType: DiscType,
        identifier: VideoDiscIdentifier,
        contribute: Bool,
        mode: MeedyaDBSubmissionMode
    ) async {
        // The label is taken from the signals rather than read off `info`
        // again, so what is sent can never disagree with what was ranked.
        // It only leaves the machine in `.full` mode — the publisher strips
        // it otherwise.
        let label = VideoDiscIdentifier.signals(for: info, discType: discType).label

        do {
            identifyResult = try await identifier.identify(
                info: info,
                discType: discType,
                labelText: label,
                contribute: contribute,
                mode: mode
            )
        } catch is CancellationError {
            identifyErrorMessage = "Identifying the disc was cancelled."
        } catch {
            identifyErrorMessage = error.localizedDescription
        }
        isIdentifying = false
        isCancellingIdentify = false
        identifyTask = nil
    }

    /// Cancels an in-progress identification. Like `cancelScan()`/`cancelRip()`,
    /// this ONLY cancels — every piece of cleanup happens in
    /// `performIdentify`'s own tail, so a cancelled run's ending can never
    /// land on top of a newer one and wipe its state.
    func cancelIdentify() {
        guard identifyTask != nil, isIdentifying else { return }
        isCancellingIdentify = true
        identifyTask?.cancel()
    }

    /// A TMDB service from a stored credential, or `nil` when there isn't
    /// one. Nil is an ordinary state, not an error: the disc is still
    /// identified from its own structure and still worth contributing.
    private static func tmdbService(from key: String?) -> TMDBLookupService? {
        guard let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return TMDBLookupService(apiKey: trimmed)
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
        identifyTask?.cancel()
    }
}
