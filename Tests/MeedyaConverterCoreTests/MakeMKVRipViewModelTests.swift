// ============================================================================
// MeedyaConverter — MakeMKVRipViewModelTests (Issue #503, slice 4b)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Exercises the MakeMKV GUI rip flow's view model against a MOCK line-
// streaming seam and mock gate providers — NO real subprocess, NO real
// `UserDefaults`, in CI. Covers: a closed gate making zero runner calls; the
// source-kind → `MakeMKVSource` mapping; scan success/failure/cancellation;
// rip guards (also zero runner calls); `.all` vs a subset's per-title
// arguments; sequential multi-run ordering; rip failure/cancellation
// outcome text; the gate being re-read (not cached) across calls; and the
// message cap.
//
// The mock runner carries its own `NSLock`-guarded state per instance (no
// shared globals) and every destination path is a fresh UUID string, so
// this file is safe under `swift test --parallel`, and every test `await`s
// the `Task` `scan()`/`rip()` hand back rather than sleeping or polling.
// ============================================================================

import XCTest
import ConverterEngine
@testable import MeedyaConverterCore

@MainActor
final class MakeMKVRipViewModelTests: XCTestCase {

    // MARK: - Mock line-streaming seam (per-instance state, NSLock)

    private final class MockMakeMKVRunner: MakeMKVLineStreaming, @unchecked Sendable {
        struct Script: Sendable {
            var lines: [String] = []
            var exitCode: Int32 = 0
            var throwError: (any Error & Sendable)?
        }
        struct Call: Sendable, Equatable {
            let binaryPath: String
            let arguments: [String]
        }

        private let lock = NSLock()
        private let scripts: [Script]
        private var callCount = 0
        private var recordedCalls: [Call] = []

        /// One script per expected call, in order. A call beyond the last
        /// scripted one (shouldn't happen in these tests) reuses the last.
        init(scripts: [Script]) {
            self.scripts = scripts
        }

        var invocationCount: Int { lock.withLock { callCount } }
        var calls: [Call] { lock.withLock { recordedCalls } }

        func run(
            binaryPath: String,
            arguments: [String],
            onStdoutLine: @escaping @Sendable (String) -> Void
        ) async throws -> Int32 {
            let script: Script = lock.withLock {
                recordedCalls.append(Call(binaryPath: binaryPath, arguments: arguments))
                let index = scripts.isEmpty ? -1 : min(callCount, scripts.count - 1)
                callCount += 1
                return index >= 0 ? scripts[index] : Script()
            }
            for line in script.lines { onStdoutLine(line) }
            if let throwError = script.throwError { throw throwError }
            return script.exitCode
        }
    }

    // MARK: - Blocking mock runner (for REAL cancellation / mid-flight tests)

    /// Behaves like `MockMakeMKVRunner` for the first `blockingFromCall`
    /// calls, then emits that call's lines and **suspends indefinitely**
    /// until the task is cancelled — the only way to observe the view model
    /// while work is genuinely in flight. `waitUntilCallStarted()` lets a
    /// test reach that point deterministically, with no sleeping or polling.
    private final class BlockingMakeMKVRunner: MakeMKVLineStreaming, @unchecked Sendable {
        private let lock = NSLock()
        private let scripts: [MockMakeMKVRunner.Script]
        private let blockingFromCall: Int
        private var callCount = 0
        private var blocked: CheckedContinuation<Void, any Error>?
        private var wasCancelled = false
        private var didReachBlockingCall = false
        private var startWaiters: [CheckedContinuation<Void, Never>] = []

        init(blockingFromCall: Int, scripts: [MockMakeMKVRunner.Script]) {
            self.blockingFromCall = blockingFromCall
            self.scripts = scripts
        }

        var invocationCount: Int { lock.withLock { callCount } }

        /// Suspends until the blocking call has been entered and is parked.
        func waitUntilCallStarted() async {
            await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
                let alreadyStarted: Bool = lock.withLock {
                    if didReachBlockingCall { return true }
                    startWaiters.append(waiter)
                    return false
                }
                if alreadyStarted { waiter.resume() }
            }
        }

        func run(
            binaryPath: String,
            arguments: [String],
            onStdoutLine: @escaping @Sendable (String) -> Void
        ) async throws -> Int32 {
            let (index, shouldBlock): (Int, Bool) = lock.withLock {
                let current = callCount
                callCount += 1
                return (current, current >= blockingFromCall)
            }
            let script = scripts.isEmpty
                ? MockMakeMKVRunner.Script()
                : scripts[min(index, scripts.count - 1)]
            for line in script.lines { onStdoutLine(line) }
            guard shouldBlock else {
                if let error = script.throwError { throw error }
                return script.exitCode
            }

            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    // Cancellation can arrive before we park, so re-check
                    // under the lock rather than parking forever.
                    let (cancelImmediately, waiters): (Bool, [CheckedContinuation<Void, Never>]) = lock.withLock {
                        let alreadyCancelled = wasCancelled
                        if !alreadyCancelled { blocked = continuation }
                        // Release the waiters on BOTH paths — a waiter left
                        // pending after an already-cancelled call would hang
                        // the test rather than fail it.
                        didReachBlockingCall = true
                        let pending = startWaiters
                        startWaiters = []
                        return (alreadyCancelled, pending)
                    }
                    for waiter in waiters { waiter.resume() }
                    if cancelImmediately {
                        continuation.resume(throwing: CancellationError())
                    }
                }
            } onCancel: {
                let parked: CheckedContinuation<Void, any Error>? = lock.withLock {
                    wasCancelled = true
                    let current = blocked
                    blocked = nil
                    return current
                }
                parked?.resume(throwing: CancellationError())
            }
            return script.exitCode
        }
    }

    // MARK: - Thread-safe mutable gate (for the "gate flips mid-session" test)

    private final class GateBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _readiness: MakeMKVReadiness
        private var _consent: MakeMKVConsent?

        init(readiness: MakeMKVReadiness, consent: MakeMKVConsent?) {
            _readiness = readiness
            _consent = consent
        }

        var readiness: MakeMKVReadiness {
            get { lock.withLock { _readiness } }
            set { lock.withLock { _readiness = newValue } }
        }
        var consent: MakeMKVConsent? {
            get { lock.withLock { _consent } }
            set { lock.withLock { _consent = newValue } }
        }
    }

    // MARK: - Fixtures

    /// A disc with one title with no duration at all — `defaultSelection`
    /// still auto-selects it (a lone title always is), so tests that only
    /// care about the rip step don't need to hand-pick a selection.
    private let singleTitleInfoLines: [String] = [
        "TCOUNT:1",
        #"TINFO:0,2,0,"Only Title""#,
    ]

    /// A disc with two titles of different durations, so
    /// `defaultSelection` has something to actually choose between.
    private let twoTitleInfoLines: [String] = [
        "TCOUNT:2",
        #"TINFO:0,2,0,"Feature""#,
        #"TINFO:0,9,0,"1:30:00""#,
        #"TINFO:0,11,0,"5000000000""#,
        #"TINFO:1,2,0,"Extra""#,
        #"TINFO:1,9,0,"0:05:00""#,
    ]

    private let threeTitleInfoLines: [String] = [
        "TCOUNT:3",
        #"TINFO:0,9,0,"0:10:00""#,
        #"TINFO:1,9,0,"0:20:00""#,
        #"TINFO:2,9,0,"0:30:00""#,
    ]

    private let ripLinesSuccess: [String] = [
        #"PRGT:5017,0,"Saving all titles""#,
        #"PRGC:5018,0,"Analyzing""#,
        "PRGV:65536,65536,65536",
        #"MSG:1000,0,0,"Done","Done""#,
    ]

    private func makeReadyViewModel(runner: MakeMKVLineStreaming) -> MakeMKVRipViewModel {
        MakeMKVRipViewModel(
            runner: runner,
            readinessProvider: { .ready(binaryPath: "/usr/local/bin/makemkvcon") },
            consentProvider: { .userAcknowledged("I accept") }
        )
    }

    /// A fresh, unique destination path per call — never a shared literal —
    /// so parallel tests can never collide, even though nothing here
    /// actually touches the filesystem (the mock runner never writes files).
    private func uniqueDestinationPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MakeMKVRipViewModelTests-\(UUID().uuidString)")
            .path
    }

    // MARK: - Gate closed → zero runner calls

    func test_scan_gateClosed_makesZeroRunnerCallsAndSurfacesReason() async {
        let runner = MockMakeMKVRunner(scripts: [])
        let vm = MakeMKVRipViewModel(
            runner: runner,
            readinessProvider: { .notEnabled(reason: "Turn MakeMKV on in Settings first.") },
            consentProvider: { nil }
        )
        vm.discIndexText = "0"

        let task = vm.scan()

        XCTAssertNil(task, "a closed gate must not even start a scan task")
        XCTAssertEqual(runner.invocationCount, 0)
        XCTAssertEqual(vm.scanErrorMessage, "Turn MakeMKV on in Settings first.")
        XCTAssertFalse(vm.isScanning)
    }

    func test_rip_gateClosed_makesZeroRunnerCallsAndSurfacesReason() async {
        let runner = MockMakeMKVRunner(scripts: [])
        let vm = MakeMKVRipViewModel(
            runner: runner,
            readinessProvider: { .notInstalled(reason: "makemkvcon was not found.") },
            consentProvider: { .userAcknowledged("ok") }
        )
        vm.sourceKind = .devicePath
        vm.devicePath = "/dev/rdisk2"
        vm.destinationPath = uniqueDestinationPath()
        vm.selectedTitleIndices = [0]

        let task = vm.rip()

        XCTAssertNil(task)
        XCTAssertEqual(runner.invocationCount, 0)
        XCTAssertEqual(vm.outcomeMessage, "makemkvcon was not found.")
        XCTAssertTrue(vm.outcomeIsError)
        XCTAssertFalse(vm.isRipping)
    }

    // MARK: - Source mapping

    func test_resolvedSource_mapsEachSourceKind() {
        let vm = makeReadyViewModel(runner: MockMakeMKVRunner(scripts: []))

        vm.sourceKind = .opticalDrive
        vm.discIndexText = "2"
        XCTAssertEqual(vm.resolvedSource, .disc(2))
        vm.discIndexText = "not a number"
        XCTAssertNil(vm.resolvedSource)
        vm.discIndexText = "-1"
        XCTAssertNil(vm.resolvedSource, "a negative drive number is never valid")

        vm.sourceKind = .devicePath
        vm.devicePath = "  /dev/rdisk3  "
        XCTAssertEqual(vm.resolvedSource, .device("/dev/rdisk3"))
        vm.devicePath = "   "
        XCTAssertNil(vm.resolvedSource)

        vm.sourceKind = .discImage
        vm.isoPath = "/Volumes/Movies/disc.iso"
        XCTAssertEqual(vm.resolvedSource, .iso("/Volumes/Movies/disc.iso"))
        vm.isoPath = ""
        XCTAssertNil(vm.resolvedSource)

        vm.sourceKind = .discFolder
        vm.folderPath = "  /Volumes/Movies/My Film  "
        XCTAssertEqual(vm.resolvedSource, .file("/Volumes/Movies/My Film"))
        vm.folderPath = "   "
        XCTAssertNil(vm.resolvedSource)
    }

    func test_everySourceKindResolvesAndExplainsItself() {
        // A new source kind must be wired into BOTH resolvedSource and
        // scanBlockedReason. Iterating allCases means adding a case without
        // wiring it up fails here rather than shipping a picker entry that
        // silently does nothing.
        let vm = makeReadyViewModel(runner: MockMakeMKVRunner(scripts: []))

        for kind in MakeMKVRipViewModel.SourceKind.allCases {
            vm.sourceKind = kind
            vm.discIndexText = ""
            vm.devicePath = ""
            vm.isoPath = ""
            vm.folderPath = ""

            XCTAssertNil(vm.resolvedSource, "\(kind.rawValue) with nothing filled in must not resolve")
            XCTAssertNotNil(
                vm.scanBlockedReason,
                "\(kind.rawValue) must explain what is missing rather than leaving a dead button"
            )
        }
    }

    // MARK: - Scan: success / failure / cancel

    func test_scan_success_populatesTitlesWithDefaultSelection() async {
        let runner = MockMakeMKVRunner(scripts: [.init(lines: twoTitleInfoLines, exitCode: 0)])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let task = vm.scan() else { return XCTFail("expected a scan task") }
        await task.value

        XCTAssertFalse(vm.isScanning)
        XCTAssertNil(vm.scanErrorMessage)
        XCTAssertEqual(vm.orderedTitles.map(\.index), [0, 1])
        XCTAssertEqual(vm.selectedTitleIndices, [0], "the longer title should be pre-selected")
        XCTAssertEqual(runner.invocationCount, 1)
        XCTAssertEqual(runner.calls.first?.arguments, MakeMKVBackend.buildInfoArguments(source: .disc(0)))
    }

    func test_scan_failure_setsPlainEnglishScanError() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: [#"MSG:5010,0,0,"Failed to open disc","Failed to open disc""#], exitCode: 12)
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let task = vm.scan() else { return XCTFail("expected a scan task") }
        await task.value

        XCTAssertFalse(vm.isScanning)
        XCTAssertTrue(vm.orderedTitles.isEmpty)
        XCTAssertEqual(vm.scanErrorMessage, "MakeMKV stopped with an error: Failed to open disc.")
    }

    func test_scan_cancellation_setsScanSpecificMessage() async {
        let runner = MockMakeMKVRunner(scripts: [.init(throwError: CancellationError())])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let task = vm.scan() else { return XCTFail("expected a scan task") }
        await task.value

        XCTAssertFalse(vm.isScanning)
        XCTAssertEqual(vm.scanErrorMessage, "The scan was cancelled.", "must say 'scan', not reuse the rip-worded text")
    }

    func test_cancelScan_withNothingRunningIsANoOp() {
        let vm = makeReadyViewModel(runner: MockMakeMKVRunner(scripts: []))
        vm.cancelScan()
        XCTAssertNil(vm.scanErrorMessage)
        XCTAssertFalse(vm.isScanning)
    }

    // MARK: - Rip guards (also zero runner calls)

    func test_rip_noSource_failsWithoutTouchingRunner() {
        let runner = MockMakeMKVRunner(scripts: [])
        let vm = makeReadyViewModel(runner: runner)
        vm.sourceKind = .devicePath
        vm.devicePath = ""
        vm.destinationPath = uniqueDestinationPath()
        vm.selectedTitleIndices = [0]

        let task = vm.rip()

        XCTAssertNil(task)
        XCTAssertEqual(runner.invocationCount, 0)
        XCTAssertEqual(vm.outcomeMessage, "Enter a disc number, device path or disc image path first.")
        XCTAssertTrue(vm.outcomeIsError)
    }

    func test_rip_noDestination_failsWithoutTouchingRunner() {
        let runner = MockMakeMKVRunner(scripts: [])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        vm.destinationPath = "   "
        vm.selectedTitleIndices = [0]

        let task = vm.rip()

        XCTAssertNil(task)
        XCTAssertEqual(runner.invocationCount, 0)
        XCTAssertEqual(vm.outcomeMessage, "Choose a destination folder before starting a rip.")
    }

    func test_rip_noTitlesSelected_failsWithoutTouchingRunner() {
        let runner = MockMakeMKVRunner(scripts: [])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        vm.destinationPath = uniqueDestinationPath()
        vm.selectedTitleIndices = []

        let task = vm.rip()

        XCTAssertNil(task)
        XCTAssertEqual(runner.invocationCount, 0)
        XCTAssertEqual(vm.outcomeMessage, "Select at least one title to rip.")
    }

    // MARK: - .all vs subset argument building

    func test_rip_everyListedTitleSelected_usesASingleAllRun() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: twoTitleInfoLines, exitCode: 0),
            .init(lines: ripLinesSuccess, exitCode: 0),
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value
        vm.selectedTitleIndices = Set(vm.orderedTitles.map(\.index))
        vm.destinationPath = uniqueDestinationPath()

        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task") }
        await ripTask.value

        XCTAssertEqual(runner.invocationCount, 2, "1 scan + 1 single .all rip run")
        XCTAssertEqual(
            runner.calls.last?.arguments,
            MakeMKVBackend.buildRipArguments(source: .disc(0), titles: .all, destinationDirectory: vm.destinationPath)
        )
        XCTAssertFalse(vm.outcomeIsError)
        XCTAssertEqual(vm.outcomeMessage, "Rip complete. 2 titles were saved to \(vm.destinationPath).")
        XCTAssertNil(vm.ripProgress, "progress state is cleared once the rip finishes")
    }

    func test_rip_oneOfSeveralTitlesSelected_usesThatTitlesIndexAndSingularWording() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: twoTitleInfoLines, exitCode: 0),
            .init(lines: ripLinesSuccess, exitCode: 0),
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value
        // Select only title 1 — a genuine SUBSET of the two scanned titles,
        // so this exercises `.index(_)`, not the `.all` optimisation (which
        // only applies when every listed title is selected).
        vm.selectedTitleIndices = [1]
        vm.destinationPath = uniqueDestinationPath()

        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task") }
        await ripTask.value

        XCTAssertEqual(
            runner.calls.last?.arguments,
            MakeMKVBackend.buildRipArguments(source: .disc(0), titles: .index(1), destinationDirectory: vm.destinationPath)
        )
        XCTAssertEqual(vm.outcomeMessage, "Rip complete. The title was saved to \(vm.destinationPath).")
    }

    // MARK: - Sequential multi-run ordering

    func test_rip_subsetOfThreeTitles_runsSequentiallyInAscendingIndexOrder() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: threeTitleInfoLines, exitCode: 0),
            .init(lines: ["PRGV:65536,65536,65536"], exitCode: 0),
            .init(lines: ["PRGV:65536,65536,65536"], exitCode: 0),
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value
        XCTAssertEqual(vm.orderedTitles.map(\.index), [0, 1, 2])

        vm.selectedTitleIndices = [2, 0] // deliberately out of order
        vm.destinationPath = uniqueDestinationPath()

        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task") }
        await ripTask.value

        XCTAssertEqual(runner.invocationCount, 3, "1 scan + 2 sequential rip runs")
        XCTAssertEqual(
            runner.calls.dropFirst().map(\.arguments),
            [
                MakeMKVBackend.buildRipArguments(source: .disc(0), titles: .index(0), destinationDirectory: vm.destinationPath),
                MakeMKVBackend.buildRipArguments(source: .disc(0), titles: .index(2), destinationDirectory: vm.destinationPath),
            ],
            "runs must happen in ascending title-index order, not selection order"
        )
        XCTAssertFalse(vm.outcomeIsError)
        XCTAssertEqual(vm.outcomeMessage, "Rip complete. 2 titles were saved to \(vm.destinationPath).")
    }

    // MARK: - Rip failure / cancellation outcomes

    func test_rip_failure_appendsThePartialFilesCaveat() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: singleTitleInfoLines, exitCode: 0),
            .init(lines: [#"MSG:5003,0,0,"Disc read error","Disc read error""#], exitCode: 1),
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value
        vm.destinationPath = uniqueDestinationPath()

        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task") }
        await ripTask.value

        XCTAssertTrue(vm.outcomeIsError)
        XCTAssertEqual(
            vm.outcomeMessage,
            "MakeMKV stopped with an error: Disc read error. Any files already written remain in the destination folder."
        )
        XCTAssertFalse(vm.isRipping)
        XCTAssertNil(vm.ripProgress)
    }

    func test_rip_cancellation_appendsThePartialFilesCaveat() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: singleTitleInfoLines, exitCode: 0),
            .init(throwError: CancellationError()),
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value
        vm.destinationPath = uniqueDestinationPath()

        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task") }
        await ripTask.value

        XCTAssertTrue(vm.outcomeIsError)
        XCTAssertEqual(
            vm.outcomeMessage,
            "The rip was cancelled. Any files already written remain in the destination folder."
        )
        XCTAssertFalse(vm.isRipping)
    }

    // MARK: - Gate re-read (never cached) across calls

    func test_gate_isReReadOnEachCallNotCachedFromConstruction() async {
        let gate = GateBox(readiness: .notEnabled(reason: "Turn MakeMKV on first."), consent: nil)
        let runner = MockMakeMKVRunner(scripts: [.init(lines: singleTitleInfoLines, exitCode: 0)])
        let vm = MakeMKVRipViewModel(
            runner: runner,
            readinessProvider: { gate.readiness },
            consentProvider: { gate.consent }
        )
        vm.discIndexText = "0"

        vm.refreshGate()
        XCTAssertEqual(vm.readiness, .notEnabled(reason: "Turn MakeMKV on first."))
        XCTAssertNil(vm.scan())
        XCTAssertEqual(runner.invocationCount, 0, "a closed gate must not touch the runner")
        XCTAssertEqual(vm.scanErrorMessage, "Turn MakeMKV on first.")

        // The user enables MakeMKV in Settings, e.g. from another window —
        // the SAME view model instance must see it on its next action.
        gate.readiness = .ready(binaryPath: "/usr/local/bin/makemkvcon")
        gate.consent = .userAcknowledged("I accept")

        guard let task = vm.scan() else { return XCTFail("expected a scan task now the gate is open") }
        await task.value

        XCTAssertEqual(runner.invocationCount, 1)
        XCTAssertNil(vm.scanErrorMessage)
        XCTAssertEqual(vm.orderedTitles.count, 1)
    }

    // MARK: - Message cap

    func test_rip_messagesAreCappedKeepingTheMostRecent() async {
        var lines: [String] = (0..<250).map { #"MSG:1,0,0,"Message \#($0)","Message \#($0)""# }
        lines.append("PRGV:65536,65536,65536")

        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: singleTitleInfoLines, exitCode: 0),
            .init(lines: lines, exitCode: 0),
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value
        vm.destinationPath = uniqueDestinationPath()

        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task") }
        await ripTask.value

        XCTAssertEqual(vm.messages.count, 200)
        XCTAssertEqual(vm.messages.first, "Message 50", "the oldest 50 of 250 messages should have been dropped")
        XCTAssertEqual(vm.messages.last, "Message 249")
    }

    // MARK: - Real (in-flight) cancellation

    func test_cancelScan_leavesAllCleanupToTheRunningTask() async {
        let runner = BlockingMakeMKVRunner(blockingFromCall: 0, scripts: [])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let task = vm.scan() else { return XCTFail("expected a scan task") }
        await runner.waitUntilCallStarted()

        XCTAssertTrue(vm.isScanning)
        XCTAssertFalse(vm.isCancellingScan)

        vm.cancelScan()

        // The heart of the fix: `cancelScan()` must ONLY cancel. If it also
        // cleared `isScanning`/`scanTask` and wrote the message itself, the
        // task's own tail would later land on top of whatever came next.
        XCTAssertTrue(vm.isScanning, "still scanning until the task itself winds down")
        XCTAssertTrue(vm.isCancellingScan, "the UI needs to show the cancel was heard")
        XCTAssertNil(vm.scanErrorMessage, "the message is the task's to write, not the canceller's")

        await task.value

        XCTAssertFalse(vm.isScanning)
        XCTAssertFalse(vm.isCancellingScan)
        XCTAssertEqual(vm.scanErrorMessage, "The scan was cancelled.")
    }

    func test_scan_whileScanning_isRejectedAndLeavesTheRunningScanAlone() async {
        let runner = BlockingMakeMKVRunner(blockingFromCall: 0, scripts: [])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let task = vm.scan() else { return XCTFail("expected a scan task") }
        await runner.waitUntilCallStarted()

        XCTAssertNil(vm.scan(), "a second scan must not start while one is running")
        XCTAssertEqual(runner.invocationCount, 1, "and must not reach the runner")
        XCTAssertTrue(vm.isScanning)

        vm.cancelScan()
        await task.value
    }

    func test_cancelRip_reportsCancellingWhileTheTaskWindsDown() async {
        let runner = BlockingMakeMKVRunner(
            blockingFromCall: 1,
            scripts: [.init(lines: singleTitleInfoLines, exitCode: 0), .init()]
        )
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value
        vm.destinationPath = uniqueDestinationPath()

        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task") }
        await runner.waitUntilCallStarted()

        XCTAssertTrue(vm.isRipping)
        XCTAssertFalse(vm.isCancellingRip)

        vm.cancelRip()
        XCTAssertTrue(vm.isRipping, "still ripping until the task notices")
        XCTAssertTrue(vm.isCancellingRip)

        await ripTask.value

        XCTAssertFalse(vm.isRipping)
        XCTAssertFalse(vm.isCancellingRip)
        XCTAssertTrue(vm.outcomeIsError)
        XCTAssertEqual(
            vm.outcomeMessage,
            "The rip was cancelled. Any files already written remain in the destination folder."
        )
    }

    func test_rip_whileRipping_isRejectedWithoutWipingTheLiveState() async {
        // Two titles out of three → two sequential runs. The first run
        // completes (populating messages/progress), the second blocks, so by
        // the time `waitUntilCallStarted()` returns there is genuine live
        // state on screen for a second press to wipe.
        let runner = BlockingMakeMKVRunner(
            blockingFromCall: 2,
            scripts: [
                .init(lines: threeTitleInfoLines, exitCode: 0),
                .init(lines: ripLinesSuccess, exitCode: 0),
                .init(),
            ]
        )
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value

        vm.selectedTitleIndices = [0, 1]
        vm.destinationPath = uniqueDestinationPath()

        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task") }
        await runner.waitUntilCallStarted()

        XCTAssertFalse(vm.messages.isEmpty, "the first run's messages should be on screen")
        let messagesBefore = vm.messages
        let progressBefore = vm.ripProgress

        XCTAssertNil(vm.rip(), "a second rip must not start while one is running")
        XCTAssertEqual(runner.invocationCount, 3, "scan + 2 rip runs — no extra call")
        XCTAssertEqual(vm.messages, messagesBefore, "a rejected press must not clear the live log")
        XCTAssertEqual(vm.ripProgress, progressBefore, "nor the live progress")

        vm.cancelRip()
        await ripTask.value
    }

    // MARK: - Disabled buttons always say why

    func test_scanBlockedReason_namesTheMissingPieceForEachSourceKind() {
        let vm = makeReadyViewModel(runner: MockMakeMKVRunner(scripts: []))

        vm.sourceKind = .opticalDrive
        vm.discIndexText = ""
        XCTAssertEqual(vm.scanBlockedReason, "Enter the drive number to scan \u{2014} 0 is the first drive.")

        vm.discIndexText = "0"
        XCTAssertNil(vm.scanBlockedReason, "nothing to explain once the button is enabled")
        XCTAssertTrue(vm.canScan)

        vm.sourceKind = .devicePath
        vm.devicePath = "   "
        XCTAssertEqual(vm.scanBlockedReason, "Enter the device path of the drive to scan.")

        vm.sourceKind = .discImage
        vm.isoPath = ""
        XCTAssertEqual(vm.scanBlockedReason, "Choose a disc image file to scan.")

        vm.sourceKind = .discFolder
        vm.folderPath = ""
        XCTAssertEqual(vm.scanBlockedReason, "Choose the folder that contains VIDEO_TS or BDMV.")
    }

    func test_ripBlockedReason_namesTheNextStepInOrder() async {
        let runner = MockMakeMKVRunner(scripts: [.init(lines: singleTitleInfoLines, exitCode: 0)])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        XCTAssertEqual(vm.ripBlockedReason, "Scan the disc first, then choose which titles to rip.")

        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value

        // The lone title is auto-selected, so the destination is next.
        XCTAssertEqual(vm.ripBlockedReason, "Choose a destination folder to save the ripped titles in.")

        vm.selectedTitleIndices = []
        XCTAssertEqual(
            vm.ripBlockedReason,
            "Select at least one title to rip.",
            "once titles are on screen the wording must stop telling the user to scan"
        )

        vm.selectedTitleIndices = [0]
        vm.destinationPath = uniqueDestinationPath()
        XCTAssertNil(vm.ripBlockedReason)
        XCTAssertTrue(vm.canRip)
    }

    func test_blockedReasons_coverEveryDisabledStateOfTheirButton() async {
        // The contract the view relies on: whenever the button is disabled
        // and still on screen, there is a reason to show. (While the work is
        // running the button is replaced by a progress row, so `nil` there
        // is correct, not a gap — asserted explicitly below.)
        let runner = BlockingMakeMKVRunner(blockingFromCall: 0, scripts: [])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        vm.destinationPath = uniqueDestinationPath()

        XCTAssertFalse(vm.canRip)
        XCTAssertNotNil(vm.ripBlockedReason)

        guard let task = vm.scan() else { return XCTFail("expected a scan task") }
        await runner.waitUntilCallStarted()

        XCTAssertFalse(vm.canScan)
        XCTAssertNil(vm.scanBlockedReason, "the button already reads 'Scanning…'")
        XCTAssertEqual(vm.ripBlockedReason, "Scanning the disc. The rip can start once the scan finishes.")

        vm.cancelScan()
        await task.value

        // F3 added a THIRD disabled state to this contract: everything else
        // about the form looks ready (titles picked, destination chosen),
        // but the source field has moved since the scan that produced those
        // titles. A fresh, non-blocking view model is used here because
        // reaching this state needs a scan that actually SUCCEEDS, unlike
        // the two states above.
        let sourceChangeRunner = MockMakeMKVRunner(scripts: [.init(lines: singleTitleInfoLines, exitCode: 0)])
        let sourceChangeVM = makeReadyViewModel(runner: sourceChangeRunner)
        sourceChangeVM.discIndexText = "0"
        guard let sourceScanTask = sourceChangeVM.scan() else { return XCTFail("expected a scan task") }
        await sourceScanTask.value
        sourceChangeVM.destinationPath = uniqueDestinationPath()
        XCTAssertTrue(sourceChangeVM.canRip, "precondition: enabled before the field is touched")

        sourceChangeVM.discIndexText = "1"
        XCTAssertFalse(sourceChangeVM.canRip)
        XCTAssertNotNil(sourceChangeVM.ripBlockedReason, "must still name a reason, not just go quiet")
    }

    // MARK: - F3: rip must refuse when the source has moved since the scan
    //
    // `rip()` used to resolve its source from whatever was CURRENTLY typed
    // into the source fields while the titles it ripped came from the LAST
    // scan. Nothing recorded which source that scan had actually read, and
    // nothing compared the two, so scanning drive 0 and then, before
    // pressing Rip, retyping the drive number to "1" silently ripped disc 1
    // using disc 0's title selection. These tests scan a MockMakeMKVRunner
    // (not the blocking one — the point here is that the scan actually
    // FINISHES and is still wrong to act on afterwards) and prove the rip
    // never reaches the runner once the fields disagree with the scan.

    func test_rip_blockedWhenSourceChangesAfterScan_andRunsOnceReverted() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: twoTitleInfoLines, exitCode: 0),
            .init(lines: ripLinesSuccess, exitCode: 0),
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value
        // Select every listed title — this is also what turns the rip into
        // the `.all` optimisation used below, which is exactly the shape
        // that hides a mismatch best: no title-count check to catch it.
        vm.selectedTitleIndices = Set(vm.orderedTitles.map(\.index))
        vm.destinationPath = uniqueDestinationPath()
        XCTAssertTrue(vm.canRip, "precondition: the form is otherwise complete")

        // The user edits the drive number after the scan, without pressing
        // Scan again.
        vm.discIndexText = "1"

        XCTAssertFalse(vm.canRip)
        XCTAssertEqual(
            vm.ripBlockedReason,
            "The source has changed since the last scan. Scan again before ripping."
        )
        XCTAssertNil(vm.rip(), "a mismatched source must start nothing")
        XCTAssertEqual(runner.invocationCount, 1, "only the scan happened — the rip must never reach the runner")
        XCTAssertEqual(vm.outcomeMessage, "The source has changed since the last scan. Scan again before ripping.")
        XCTAssertTrue(vm.outcomeIsError)

        // Undoing the edit — the whole point of BLOCKING rather than
        // clearing the selection — must let the same rip through unharmed.
        vm.discIndexText = "0"
        XCTAssertTrue(vm.canRip)
        XCTAssertNil(vm.ripBlockedReason)

        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task once the field is reverted") }
        await ripTask.value

        XCTAssertEqual(runner.invocationCount, 2, "1 scan + 1 rip, now that the source matches again")
        XCTAssertEqual(
            runner.calls.last?.arguments,
            MakeMKVBackend.buildRipArguments(source: .disc(0), titles: .all, destinationDirectory: vm.destinationPath)
        )
        XCTAssertFalse(vm.outcomeIsError)
    }

    func test_rip_blockedWhenSwitchingToDiscImageAfterScan() async {
        let runner = MockMakeMKVRunner(scripts: [.init(lines: twoTitleInfoLines, exitCode: 0)])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value
        vm.selectedTitleIndices = Set(vm.orderedTitles.map(\.index))
        vm.destinationPath = uniqueDestinationPath()
        XCTAssertTrue(vm.canRip, "precondition: the form is otherwise complete")

        // Switching source KIND entirely — not just editing the drive
        // number — must be caught the same way: `resolvedSource` now
        // describes a disc image, not the drive that was actually scanned.
        vm.sourceKind = .discImage
        vm.isoPath = "/Volumes/Movies/disc.iso"

        XCTAssertFalse(vm.canRip)
        XCTAssertEqual(
            vm.ripBlockedReason,
            "The source has changed since the last scan. Scan again before ripping."
        )
        XCTAssertNil(vm.rip())
        XCTAssertEqual(runner.invocationCount, 1, "only the scan happened — the rip must never reach the runner")
    }

    func test_scan_failure_leavesScannedSourceNilSoRipStaysBlocked() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: [#"MSG:5010,0,0,"Failed to open disc","Failed to open disc""#], exitCode: 12)
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"

        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task") }
        await scanTask.value

        XCTAssertNil(vm.scannedSource, "a failed scan must not record a source to trust")

        // Set the rest of the form by hand (as a real scan would have) to
        // isolate the source-mismatch guard from the separate "no titles
        // selected" guard that a failed scan would otherwise also trigger.
        vm.selectedTitleIndices = [0]
        vm.destinationPath = uniqueDestinationPath()

        XCTAssertFalse(vm.canRip)
        XCTAssertEqual(
            vm.ripBlockedReason,
            "The source has changed since the last scan. Scan again before ripping."
        )
        XCTAssertNil(vm.rip())
        XCTAssertEqual(runner.invocationCount, 1, "only the failed scan — the rip must never reach the runner")
    }

    // MARK: - Stale cross-operation banners

    func test_startingAScan_clearsAPreviousRipOutcome() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: singleTitleInfoLines, exitCode: 0),
            .init(lines: ripLinesSuccess, exitCode: 0),
            .init(lines: singleTitleInfoLines, exitCode: 0),
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        guard let firstScan = vm.scan() else { return XCTFail("expected a scan task") }
        await firstScan.value
        vm.destinationPath = uniqueDestinationPath()
        guard let ripTask = vm.rip() else { return XCTFail("expected a rip task") }
        await ripTask.value
        XCTAssertNotNil(vm.outcomeMessage)

        guard let secondScan = vm.scan() else { return XCTFail("expected a second scan task") }
        XCTAssertNil(vm.outcomeMessage, "a finished rip's banner must not hang over a new scan")
        await secondScan.value
    }

    /// After a FAILED scan, pressing Rip is refused with "scan again", and no
    /// rip is launched. The rip's own reason replaces the scan banner, as for
    /// every other refusal.
    ///
    /// This test used to assert the OPPOSITE: that the user could pick a title
    /// by hand after a failed scan and rip anyway. That premise is gone for two
    /// reasons (Codex round 1, finding 3, 2026-09-25):
    ///   * the real screen can't reach it — titles are only selectable as
    ///     toggles over a SUCCESSFUL scan's list, and starting a scan clears
    ///     any earlier selection, so the old test got there only by writing
    ///     `selectedTitleIndices` directly;
    ///   * a rip must now come from a source that was actually scanned, or it
    ///     can rip one disc with another disc's title numbers.
    /// It failed CI on 483877a, which is how the stale premise was found.
    func test_afterAFailedScan_ripIsRefusedAndReplacesTheScanBanner() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: [], exitCode: 1),
        ])
        let vm = makeReadyViewModel(runner: runner)
        vm.discIndexText = "0"
        guard let failedScan = vm.scan() else { return XCTFail("expected a scan task") }
        await failedScan.value
        XCTAssertNotNil(vm.scanErrorMessage, "the failed scan should have left a banner")
        XCTAssertNil(vm.scannedSource, "a failed scan records no scanned source")

        // Force the state the screen itself can't produce, to prove the
        // guard holds even if a future UI change made it reachable.
        vm.selectedTitleIndices = [0]
        vm.destinationPath = uniqueDestinationPath()

        XCTAssertNil(vm.rip(), "a rip must not start from a source that was never scanned")
        XCTAssertEqual(runner.invocationCount, 1, "only the failed scan ran; no rip was launched")
        XCTAssertNil(vm.scanErrorMessage, "the rip's own reason replaces the stale scan banner")
        XCTAssertEqual(
            vm.outcomeMessage,
            "The source has changed since the last scan. Scan again before ripping."
        )
    }

    // MARK: - Identify the disc (#502)

    /// A scan transcript carrying everything identification needs: MakeMKV's
    /// own disc type (CINFO:1), a volume name (CINFO:32) and title durations.
    private let identifiableInfoLines: [String] = [
        "TCOUNT:2",
        #"CINFO:1,0,"Blu-ray disc""#,
        #"CINFO:32,0,"BIG_MOVIE_DISC""#,
        #"TINFO:0,2,0,"Feature""#,
        #"TINFO:0,9,0,"1:30:00""#,
        #"TINFO:1,9,0,"0:05:00""#,
    ]

    /// The same disc, but with a type string MakeMKV localised into something
    /// unrecognisable — the case where the user must choose.
    private let unknownTypeInfoLines: [String] = [
        "TCOUNT:1",
        #"CINFO:1,0,"Some unfamiliar medium""#,
        #"TINFO:0,9,0,"1:30:00""#,
    ]

    /// Accepts a MeedyaDB submission and records the body that reached it.
    /// A copy of the identify screen's stub on purpose: these two screens
    /// must be provable independently.
    private final class PublishStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [Data] = []

        var callCount: Int { lock.withLock { bodies.count } }
        var lastBody: Data? { lock.withLock { bodies.last } }

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.withLock { bodies.append(request.httpBody ?? Data()) }
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://db.example")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"discPublicId":"disc_1","matched":false}"#.utf8), response)
        }
    }

    /// A one-shot gate an async test can park a stub on, then release once it
    /// has changed whatever shared state the test cares about. `NSLock`
    /// throughout, never raw `lock()`/`unlock()` — CI runs
    /// `swift test --parallel`, and Swift 6 refuses raw lock calls from an
    /// `async` context anyway.
    ///
    /// `waitUntilParked()` exists so the TEST never races the code under
    /// test: without it, a test could mutate state and call `open()` before
    /// the candidate provider had actually reached `wait()`, silently turning
    /// the whole scenario into a no-op that happens to pass.
    private final class AsyncGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var hasParked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var parkObservers: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumeNow = false
                var toWake: [CheckedContinuation<Void, Never>] = []
                lock.withLock {
                    if isOpen {
                        resumeNow = true
                    } else {
                        waiters.append(continuation)
                        hasParked = true
                        toWake = parkObservers
                        parkObservers = []
                    }
                }
                for observer in toWake { observer.resume() }
                if resumeNow { continuation.resume() }
            }
        }

        func waitUntilParked() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumeNow = false
                lock.withLock {
                    if hasParked {
                        resumeNow = true
                    } else {
                        parkObservers.append(continuation)
                    }
                }
                if resumeNow { continuation.resume() }
            }
        }

        func open() {
            let toResume: [CheckedContinuation<Void, Never>] = lock.withLock {
                isOpen = true
                let w = waiters
                waiters = []
                return w
            }
            for continuation in toResume { continuation.resume() }
        }
    }

    /// A lock-protected, mutable stand-in for the two live MeedyaDB providers
    /// (`meedyaDBReadinessProvider`/`submissionModeProvider`) — the video
    /// counterpart of `GateBox` above, for the same reason: a test needs to
    /// flip readiness or the submission mode WHILE an identify run is
    /// reading it, to prove the mid-run `recheck` in
    /// `MeedyaDBContributor.contribute` re-reads live state.
    private final class MeedyaDBSettingsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _readiness: MeedyaDBReadiness
        private var _mode: MeedyaDBSubmissionMode

        init(readiness: MeedyaDBReadiness, mode: MeedyaDBSubmissionMode) {
            self._readiness = readiness
            self._mode = mode
        }

        var readiness: MeedyaDBReadiness {
            get { lock.withLock { _readiness } }
            set { lock.withLock { _readiness = newValue } }
        }
        var mode: MeedyaDBSubmissionMode {
            get { lock.withLock { _mode } }
            set { lock.withLock { _mode = newValue } }
        }
    }

    private func makeIdentifyViewModel(
        runner: MockMakeMKVRunner,
        meedyaDBReady: Bool = false,
        publishClient: PublishStubHTTPClient? = nil,
        submissionMode: MeedyaDBSubmissionMode = .anonymous,
        candidateProvider: (@Sendable (DiscSignals) async throws -> [MetadataResult])? = nil,
        // When present, BOTH providers below read live from this box instead
        // of the fixed `meedyaDBReady`/`submissionMode` values — see
        // `DiscIdentifyViewModelTests`'s identical seam for why.
        settingsBox: MeedyaDBSettingsBox? = nil
    ) -> MakeMKVRipViewModel {
        let readiness: MeedyaDBReadiness = meedyaDBReady
            ? .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true))
            : .off(reason: MeedyaDBGate.offReason)
        let client = publishClient ?? PublishStubHTTPClient()

        return MakeMKVRipViewModel(
            runner: runner,
            readinessProvider: { .ready(binaryPath: "/usr/local/bin/makemkvcon") },
            consentProvider: { .userAcknowledged("I accept") },
            // Mirrors production: the run's publisher is built from the config
            // in force, so a test can prove a ready MeedyaDB is actually
            // REACHED rather than only promised.
            videoIdentifierFactory: { config, _ in
                guard let config else {
                    return VideoDiscIdentifier(candidateProvider: candidateProvider)
                }
                return VideoDiscIdentifier(
                    publisher: MeedyaDBPublisher(config: config, httpClient: client),
                    candidateProvider: candidateProvider
                )
            },
            submissionModeProvider: { settingsBox?.mode ?? submissionMode },
            meedyaDBReadinessProvider: { settingsBox?.readiness ?? readiness },
            // No TMDB key in CI, and none of these tests should ever want one.
            tmdbKeyProvider: { nil }
        )
    }

    /// Scan first — identification works from what the scan found.
    @discardableResult
    private func scanned(_ vm: MakeMKVRipViewModel) async -> MakeMKVRipViewModel {
        vm.discIndexText = "0"
        if let task = vm.scan() { await task.value }
        return vm
    }

    func test_scan_prefillsTheDiscTypeFromMakeMKVsOwnString() async {
        let vm = makeIdentifyViewModel(runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]))
        await scanned(vm)

        XCTAssertEqual(vm.suggestedDiscType, .bluray)
        XCTAssertEqual(vm.selectedDiscType, .bluray, "the picker should arrive pre-filled")
        XCTAssertNil(vm.identifyBlockedReason, "with a type and a scan, Identify should be ready")
    }

    /// A type string we can't read must leave the choice to the user rather
    /// than guessing. A wrong disc type reaches a shared database.
    func test_scan_withAnUnreadableType_asksTheUserRatherThanGuessing() async {
        let vm = makeIdentifyViewModel(runner: MockMakeMKVRunner(scripts: [.init(lines: unknownTypeInfoLines)]))
        await scanned(vm)

        XCTAssertNil(vm.suggestedDiscType)
        XCTAssertNil(vm.selectedDiscType)
        XCTAssertFalse(vm.canIdentify)
        XCTAssertEqual(vm.identifyBlockedReason, "Choose what kind of disc this is first.")
        XCTAssertNil(vm.identify(), "no disc type means no run at all")
    }

    func test_identify_beforeAnyScan_isBlockedAndStartsNothing() {
        let vm = makeIdentifyViewModel(runner: MockMakeMKVRunner(scripts: []))

        XCTAssertFalse(vm.canIdentify)
        XCTAssertEqual(vm.identifyBlockedReason, "Scan the disc first, then it can be identified.")
        XCTAssertNil(vm.identify())
    }

    /// F3 follow-on decision: identify uses `discInfo`, never the live
    /// source fields, so nothing about the DATA it would identify is wrong
    /// here — but the screen (and its "will also be contributed to
    /// MeedyaDB" notice) is still implying this is about whatever the
    /// source fields currently say, which is no longer the disc that was
    /// scanned. Blocking is the same honest choice as `rip()`'s, and a
    /// contribution can't be recalled once sent — see `canIdentify`'s doc
    /// comment for the full reasoning.
    func test_identify_blockedWhenSourceChangesAfterScan_andRunsOnceReverted() async {
        let vm = makeIdentifyViewModel(runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]))
        await scanned(vm)
        XCTAssertTrue(vm.canIdentify, "precondition: ready right after the scan")

        // The user edits the drive number after the scan, without pressing
        // Scan again.
        vm.discIndexText = "1"

        XCTAssertFalse(vm.canIdentify)
        XCTAssertEqual(
            vm.identifyBlockedReason,
            "The source has changed since the last scan. Scan again before identifying."
        )
        XCTAssertNil(vm.identify(), "a mismatched source must start nothing")
        XCTAssertEqual(
            vm.identifyErrorMessage,
            "The source has changed since the last scan. Scan again before identifying."
        )
        XCTAssertNil(vm.identifyResult)

        // Reverting the field must let identification through again — the
        // underlying `discInfo` was never touched by any of this.
        vm.discIndexText = "0"
        XCTAssertTrue(vm.canIdentify)
        XCTAssertNil(vm.identifyBlockedReason)

        guard let task = vm.identify() else { return XCTFail("expected an identify task once reverted") }
        await task.value

        XCTAssertNotNil(vm.identifyResult)
        XCTAssertNil(vm.identifyErrorMessage)
    }

    /// ⚠️ THE REGRESSION THAT MATTERS. The identify screen once held a single
    /// identifier built at construction with an empty, DISABLED publisher, so
    /// a fully configured MeedyaDB produced "this disc will also be
    /// contributed" and then sent nothing. This asserts on the BYTES that
    /// reached the wire, not on the promise.
    func test_identify_readyMeedyaDB_actuallyReachesTheWire() async throws {
        let publishClient = PublishStubHTTPClient()
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            meedyaDBReady: true,
            publishClient: publishClient
        )
        await scanned(vm)
        // What the view does on appear. Without it `willContribute` is simply
        // unread, and asserting on it would prove nothing.
        vm.refreshMeedyaDBReadiness()
        XCTAssertTrue(vm.willContribute, "the screen promises a contribution here")

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await task.value

        XCTAssertEqual(publishClient.callCount, 1, "a ready MeedyaDB must actually be reached")
        let contribution = try XCTUnwrap(vm.identifyResult?.contribution)
        XCTAssertTrue(contribution.didSubmit, "the promise on screen must be kept: \(contribution)")
    }

    func test_identify_submissionModeAndLabelReachTheWire() async throws {
        let publishClient = PublishStubHTTPClient()
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            meedyaDBReady: true,
            publishClient: publishClient,
            submissionMode: .full
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await task.value

        let body = try XCTUnwrap(publishClient.lastBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["submission"] as? String, "full",
                       "the user's choice must reach the payload, not be assumed")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertEqual(disc["labelText"] as? String, "BIG_MOVIE_DISC",
                       "full mode was chosen, so the label must actually be passed through")
        XCTAssertEqual(disc["discType"] as? String, DiscType.bluray.rawValue)
    }

    /// The default must under-send, never over-send.
    func test_identify_anonymousIsTheDefaultAndStripsTheLabel() async throws {
        let publishClient = PublishStubHTTPClient()
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            meedyaDBReady: true,
            publishClient: publishClient
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await task.value

        let body = try XCTUnwrap(publishClient.lastBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["submission"] as? String, "anonymous")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertNil(disc["labelText"], "anonymous mode must not send what is printed on the disc")
    }

    /// MeedyaDB switched off is the normal state for most people. It must
    /// still identify, must send nothing, and must not look like an error.
    func test_identify_withoutMeedyaDB_stillIdentifiesAndSendsNothing() async throws {
        let publishClient = PublishStubHTTPClient()
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            meedyaDBReady: false,
            publishClient: publishClient
        )
        await scanned(vm)
        vm.refreshMeedyaDBReadiness()
        XCTAssertFalse(vm.willContribute)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await task.value

        XCTAssertEqual(publishClient.callCount, 0, "nothing may be sent when contributing is off")
        let result = try XCTUnwrap(vm.identifyResult)
        XCTAssertFalse(result.contribution.didSubmit)
        XCTAssertNil(vm.identifyErrorMessage, "contributing being off is not an error")
        XCTAssertNotNil(result.signals.mainFeatureDurationSeconds, "the disc was still identified")
    }

    /// A film database being unreachable must not abandon the run: the disc's
    /// own structure is still worth contributing, exactly as a MusicBrainz
    /// outage does not stop the music path.
    func test_identify_lookupFailure_stillIdentifiesAndStillContributes() async throws {
        let publishClient = PublishStubHTTPClient()
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            meedyaDBReady: true,
            publishClient: publishClient,
            candidateProvider: { _ in throw URLError(.notConnectedToInternet) }
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await task.value

        let result = try XCTUnwrap(vm.identifyResult)
        XCTAssertNotNil(result.lookupFailure, "the failure should be recorded\u{2026}")
        XCTAssertNil(vm.identifyErrorMessage, "\u{2026}but not shown as the run failing")
        XCTAssertEqual(publishClient.callCount, 1, "the disc is still worth contributing")
    }

    // MARK: - #507: the after-the-run caption names the right reason

    /// Switched on but not finished being set up must name the missing
    /// piece, not the generic "wasn't requested" — the same fix as the
    /// identify screen's, proven independently here.
    func test_incompleteMeedyaDB_namesTheMissingPieceNotGenericWording() async throws {
        let box = MeedyaDBSettingsBox(readiness: .incomplete(reason: MeedyaDBGate.missingKeyReason), mode: .anonymous)
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await task.value

        XCTAssertEqual(
            vm.identifyResult?.contribution,
            .notAttempted(reason: MeedyaDBGate.missingKeyReason),
            "the specific missing-key reason must reach the result, not the generic wording"
        )
    }

    /// Genuinely off must keep saying so.
    func test_off_stillSaysWasntRequested() async throws {
        let box = MeedyaDBSettingsBox(readiness: .off(reason: MeedyaDBGate.offReason), mode: .anonymous)
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await task.value

        XCTAssertEqual(
            vm.identifyResult?.contribution,
            .notAttempted(reason: MeedyaDBContributor.notRequestedReason)
        )
    }

    // MARK: - Mid-run: MeedyaDB settings changing while an identify run is in flight (F1)
    //
    // Each test scans normally, then starts `identify()` with a candidate
    // provider parked on an `AsyncGate` — this is the video path's
    // equivalent of the music path parking its TOC read: after the disc's
    // own signals are ready, before `MeedyaDBContributor.contribute`'s
    // `recheck`, which runs immediately before the network call. Only
    // requests whose address contains `action=disc_ingest` count as an
    // upload; `PublishStubHTTPClient` is dedicated to that seam here, so its
    // `callCount` already reflects only those.

    /// (a) Switching contributing OFF mid-run withdraws the submission
    /// entirely and says so, rather than silently sending the old promise.
    func test_midRun_meedyaDBSwitchedOff_withdrawsAndReportsWhy() async throws {
        let publishClient = PublishStubHTTPClient()
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(
            readiness: .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true)),
            mode: .anonymous
        )
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            publishClient: publishClient,
            candidateProvider: { _ in await gate.wait(); return [] },
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await gate.waitUntilParked()
        box.readiness = .off(reason: MeedyaDBGate.offReason)
        gate.open()
        await task.value

        XCTAssertEqual(publishClient.callCount, 0, "switching off mid-run must withdraw the upload")
        XCTAssertEqual(
            vm.identifyResult?.contribution,
            .notAttempted(reason: MeedyaDBContributor.withdrawnReason)
        )
    }

    /// (b) Narrowing full → anonymous mid-run must actually narrow what
    /// reaches the wire, including stripping the label that was only ever
    /// going to be sent because `.full` was chosen when the run started.
    func test_midRun_fullNarrowedToAnonymous_sendsAnonymousAndDropsTheLabel() async throws {
        let publishClient = PublishStubHTTPClient()
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(
            readiness: .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true)),
            mode: .full
        )
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            publishClient: publishClient,
            candidateProvider: { _ in await gate.wait(); return [] },
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await gate.waitUntilParked()
        box.mode = .anonymous
        gate.open()
        await task.value

        XCTAssertEqual(publishClient.callCount, 1, "narrowing must still deliver the disc's identifiers")
        let body = try XCTUnwrap(publishClient.lastBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["submission"] as? String, "anonymous")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertNil(disc["labelText"], "the label must never reach the wire once narrowed to anonymous")
    }

    /// (c) The reverse direction must NOT widen: a run that started
    /// anonymous stays anonymous even if the live setting becomes full
    /// before the upload goes out.
    func test_midRun_anonymousWidenedToFull_staysAnonymous() async throws {
        let publishClient = PublishStubHTTPClient()
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(
            readiness: .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true)),
            mode: .anonymous
        )
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            publishClient: publishClient,
            candidateProvider: { _ in await gate.wait(); return [] },
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await gate.waitUntilParked()
        box.mode = .full
        gate.open()
        await task.value

        XCTAssertEqual(publishClient.callCount, 1)
        let body = try XCTUnwrap(publishClient.lastBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["submission"] as? String, "anonymous",
                       "a run that started anonymous must not be widened to full mid-run")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertNil(disc["labelText"])
    }

    /// (f) Nothing changing at all must still deliver — the recheck must not
    /// itself become a way to accidentally suppress a legitimate, unchanged
    /// contribution.
    func test_midRun_nothingChanged_stillContributes() async throws {
        let publishClient = PublishStubHTTPClient()
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(
            readiness: .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true)),
            mode: .full
        )
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            publishClient: publishClient,
            candidateProvider: { _ in await gate.wait(); return [] },
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await gate.waitUntilParked()
        gate.open()
        await task.value

        XCTAssertEqual(publishClient.callCount, 1, "an unchanged run must still actually contribute")
        let body = try XCTUnwrap(publishClient.lastBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["submission"] as? String, "full")
    }

    // MARK: - The on-screen notice during a run (`runWillContribute`)

    /// Without a frozen `runWillContribute`, turning contributing ON while an
    /// identify run that started without it is still going would flip the
    /// notice to promise a contribution that run has no way to make.
    func test_runWillContribute_reflectsWhatThisRunPromised_notLiveSettings() async throws {
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(readiness: .off(reason: MeedyaDBGate.offReason), mode: .anonymous)
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            candidateProvider: { _ in await gate.wait(); return [] },
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await gate.waitUntilParked()

        XCTAssertFalse(vm.runWillContribute, "this run started with contributing off")
        box.readiness = .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true))
        // The screen re-reads settings only when told to — the view calls
        // `refreshMeedyaDBReadiness()` from its `.onChange`/`.onReceive`
        // handlers. The test must do the same, or `willContribute` still
        // shows the value read at run start (CI red on d602cf0: this
        // precondition failed because the refresh was missing).
        vm.refreshMeedyaDBReadiness()
        XCTAssertTrue(vm.willContribute, "precondition: the LIVE setting really did change")
        XCTAssertFalse(vm.runWillContribute, "a run already in progress must not retroactively promise more")

        gate.open()
        await task.value

        XCTAssertFalse(
            vm.identifyResult?.contribution.didSubmit ?? true,
            "switching on mid-run cannot make an already-declined run start contributing"
        )
    }

    // MARK: - The on-screen notice during a run (`showsContributionPromise`)

    /// Fallback review round 2, finding 2: before this fix the on-screen
    /// notice read the FROZEN `runWillContribute` alone while an identify run
    /// was in progress, so switching contributing OFF mid-run kept it saying
    /// "will be contributed" right up until the run ended and then silently
    /// sent nothing (the contributor's own `recheck` narrows what actually
    /// goes, but the notice never followed). `showsContributionPromise` must
    /// combine the frozen and live values so a switch-OFF is reflected
    /// immediately.
    func test_showsContributionPromise_switchingOffMidRun_stopsPromisingAContribution() async throws {
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(
            readiness: .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true)),
            mode: .anonymous
        )
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            candidateProvider: { _ in await gate.wait(); return [] },
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await gate.waitUntilParked()

        XCTAssertTrue(vm.runWillContribute, "precondition: this run started with contributing on")
        XCTAssertTrue(
            vm.showsContributionPromise,
            "precondition: the notice should promise a contribution before the switch-off"
        )

        // The live setting flips OFF while the run is still going...
        box.readiness = .off(reason: MeedyaDBGate.offReason)
        // ...and the screen re-reads settings only when told to, exactly as
        // the view's `.onChange` handlers do.
        vm.refreshMeedyaDBReadiness()
        XCTAssertFalse(vm.willContribute, "precondition: the LIVE setting really did change")

        XCTAssertFalse(
            vm.showsContributionPromise,
            "a mid-run switch-OFF must stop the notice promising a contribution the recheck is about to withdraw"
        )

        gate.open()
        await task.value
    }

    /// The mirror case, for the direction `runWillContribute` alone already
    /// covers: a mid-run switch-ON must not make `showsContributionPromise`
    /// promise a contribution this run has no way to make.
    func test_showsContributionPromise_switchingOnMidRun_doesNotPromiseAContribution() async throws {
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(readiness: .off(reason: MeedyaDBGate.offReason), mode: .anonymous)
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            candidateProvider: { _ in await gate.wait(); return [] },
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await gate.waitUntilParked()

        XCTAssertFalse(vm.showsContributionPromise, "precondition: this run started with contributing off")

        box.readiness = .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true))
        vm.refreshMeedyaDBReadiness()
        XCTAssertTrue(vm.willContribute, "precondition: the LIVE setting really did change")

        XCTAssertFalse(
            vm.showsContributionPromise,
            "a mid-run switch-ON must not retroactively promise a contribution this run cannot make"
        )

        gate.open()
        await task.value
    }

    /// The ordinary case: readiness never changes, so the notice keeps
    /// promising exactly what the run is actually going to do, both during
    /// and after the run.
    func test_showsContributionPromise_readyThroughout_keepsPromisingAContribution() async throws {
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(
            readiness: .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true)),
            mode: .anonymous
        )
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            candidateProvider: { _ in await gate.wait(); return [] },
            settingsBox: box
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        await gate.waitUntilParked()

        XCTAssertTrue(
            vm.showsContributionPromise,
            "readiness never changed, so the notice should keep promising the contribution"
        )

        gate.open()
        await task.value

        XCTAssertTrue(
            vm.showsContributionPromise,
            "once the run ends, showsContributionPromise falls back to the live (still-ready) setting"
        )
    }

    /// Scanning a DIFFERENT disc must not leave the previous one's name on
    /// screen. Showing the wrong film is worse than showing nothing.
    func test_scan_clearsThePreviousDiscsIdentification() async {
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [
                .init(lines: identifiableInfoLines),
                .init(lines: unknownTypeInfoLines),
            ])
        )
        await scanned(vm)
        if let task = vm.identify() { await task.value }
        XCTAssertNotNil(vm.identifyResult, "precondition: the first disc was identified")

        // A second scan, of a different disc.
        if let task = vm.scan() { await task.value }

        XCTAssertNil(vm.identifyResult, "the previous disc's result must not survive")
        XCTAssertNil(vm.identifyErrorMessage)
        XCTAssertNil(vm.selectedDiscType, "and its disc type must not carry over either")
    }

    func test_cancelIdentify_reportsCancellationAndKeepsNoResult() async {
        let vm = makeIdentifyViewModel(
            runner: MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)]),
            candidateProvider: { _ in
                // Cancelled before it can finish; a cancelled task's sleep
                // throws immediately, so this needs no real waiting.
                try await Task.sleep(nanoseconds: 60 * NSEC_PER_SEC)
                return []
            }
        )
        await scanned(vm)

        guard let task = vm.identify() else { return XCTFail("expected an identify task") }
        XCTAssertTrue(vm.isIdentifying)
        vm.cancelIdentify()
        XCTAssertTrue(vm.isCancellingIdentify, "the button must not look inert while unwinding")
        await task.value

        XCTAssertFalse(vm.isIdentifying)
        XCTAssertFalse(vm.isCancellingIdentify)
        XCTAssertNil(vm.identifyResult)
        XCTAssertEqual(vm.identifyErrorMessage, "Identifying the disc was cancelled.")
    }

    /// Identification starts no subprocess: it works from the scan's result.
    /// If this ever regresses into launching MakeMKV again, a Blu-ray would
    /// be re-scanned for minutes just to be named.
    func test_identify_runsNoExtraMakeMKVCall() async {
        let runner = MockMakeMKVRunner(scripts: [.init(lines: identifiableInfoLines)])
        let vm = makeIdentifyViewModel(runner: runner)
        await scanned(vm)
        XCTAssertEqual(runner.invocationCount, 1, "precondition: just the scan")

        if let task = vm.identify() { await task.value }

        XCTAssertEqual(runner.invocationCount, 1, "identification must not touch the tool")
    }

    /// ⚠️ THE INTERLEAVE, not the sequence.
    ///
    /// `test_scan_clearsThePreviousDiscsIdentification` above only proves the
    /// SEQUENTIAL case — identify, wait for it, then scan. That is the easy
    /// half, and on its own it asserts the promise rather than the delivery.
    /// The dangerous case is a scan starting while an identification is still
    /// in flight: `scan()` clears the result, then the old run's tail writes
    /// the OLD disc's answer straight back, and the previous film's name ends
    /// up displayed under a different disc.
    ///
    /// Scanning and identifying therefore exclude each other, which closes it
    /// completely: an in-flight run always reaches its own tail before a new
    /// scan can begin, so everything it writes is written before `scan()`
    /// clears — and `scan()` clears it.
    func test_scan_cannotStartWhileIdentifying_soAStaleRunCannotLandOnTheNewDisc() async {
        let runner = MockMakeMKVRunner(scripts: [
            .init(lines: identifiableInfoLines),
            .init(lines: identifiableInfoLines),
        ])
        let vm = makeIdentifyViewModel(
            runner: runner,
            candidateProvider: { _ in
                // Parked: this run cannot finish on its own.
                try await Task.sleep(nanoseconds: 60 * NSEC_PER_SEC)
                return []
            }
        )
        await scanned(vm)

        guard let identifyTask = vm.identify() else { return XCTFail("expected an identify task") }
        XCTAssertTrue(vm.isIdentifying)

        // The whole point: the Scan button must be shut while this runs.
        XCTAssertFalse(vm.canScan, "scanning during an identification is what lets a stale run land")
        XCTAssertEqual(
            vm.scanBlockedReason,
            "This disc is being identified. Wait for that to finish, or cancel it, before scanning again."
        )
        XCTAssertNil(vm.scan(), "a scan must not even start while identifying")
        XCTAssertEqual(runner.invocationCount, 1, "and it must not reach the tool either")

        // Cancel, let the run reach its own tail, then scan for real.
        vm.cancelIdentify()
        await identifyTask.value
        XCTAssertEqual(vm.identifyErrorMessage, "Identifying the disc was cancelled.")

        guard let scanTask = vm.scan() else { return XCTFail("expected a scan task once identifying ended") }
        await scanTask.value

        // Nothing the cancelled run wrote may survive into the new disc.
        XCTAssertNil(vm.identifyErrorMessage, "the cancelled run's message must not hang over the new disc")
        XCTAssertNil(vm.identifyResult)
        XCTAssertEqual(runner.invocationCount, 2)
    }
}
