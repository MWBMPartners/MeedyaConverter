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
}
