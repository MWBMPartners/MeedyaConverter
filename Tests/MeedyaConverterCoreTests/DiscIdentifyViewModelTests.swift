// ============================================================================
// MeedyaConverter — DiscIdentifyViewModelTests (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Exercises the in-app identification flow against injected seams — no drive,
// no network, no MeedyaDB, no filesystem.
//
// The emphasis is on the behaviours that are easy to get subtly wrong:
//
//   * a held drive offers the UNMOUNT remedy, a real read failure does not;
//   * unmounting NEVER happens on its own — only from the explicit action;
//   * cancel() only cancels, so a stale run cannot clobber a newer one;
//   * the screen says whether it will contribute BEFORE the run, never
//     contributes when MeedyaDB isn't ready, and — the regression that
//     prompted these — ACTUALLY contributes when it says it will, with the
//     submission mode the user chose.
//
// Every seam is per-instance, so this is safe under `swift test --parallel`.
// ============================================================================

import XCTest
import ConverterEngine
@testable import MeedyaConverterCore

@MainActor
final class DiscIdentifyViewModelTests: XCTestCase {

    // MARK: - Seams

    /// A tool runner for the unmount seam, recording what it was asked to do.
    private final class StubToolRunner: ExternalToolRunning, @unchecked Sendable {
        private let lock = NSLock()
        private let exitCode: Int32
        private var count = 0

        init(exitCode: Int32 = 0) { self.exitCode = exitCode }
        var callCount: Int { lock.withLock { count } }

        func run(binaryPath: String, arguments: [String]) async throws -> ExternalToolResult {
            lock.withLock { count += 1 }
            return ExternalToolResult(exitCode: exitCode, stderr: exitCode == 0 ? "" : "refused")
        }
    }

    /// Counts how many times the drive was read, and what it returned.
    ///
    /// Optionally parks on an `AsyncGate` before returning, so a test can
    /// change MeedyaDB's settings WHILE a run is in flight — reading the
    /// disc happens before `MeedyaDBContributor.contribute`'s `recheck`, so
    /// parking here reliably puts the test's edit before that recheck runs.
    private final class TOCReaderBox: @unchecked Sendable {
        private let lock = NSLock()
        private var attempts = 0
        private let outcomes: [Result<DiscTableOfContents, any Error>]
        private let gate: AsyncGate?

        /// One outcome per expected read, in order; the last repeats.
        init(_ outcomes: [Result<DiscTableOfContents, any Error>], gate: AsyncGate? = nil) {
            self.outcomes = outcomes
            self.gate = gate
        }

        var readCount: Int { lock.withLock { attempts } }

        func next() async throws -> DiscTableOfContents {
            await gate?.wait()
            let outcome: Result<DiscTableOfContents, any Error> = lock.withLock {
                let index = min(attempts, outcomes.count - 1)
                attempts += 1
                return outcomes[index]
            }
            return try outcome.get()
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
    /// the run had actually reached `wait()`, silently turning the whole
    /// scenario into a no-op that happens to pass.
    private final class AsyncGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var hasParked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var parkObservers: [CheckedContinuation<Void, Never>] = []

        /// Called by the code under test. Blocks until `open()` is called,
        /// or returns immediately if `open()` already was.
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

        /// Called by the TEST. Blocks until something has actually called
        /// `wait()` and is parked.
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

        /// Releases every waiter parked so far; any later `wait()` returns
        /// immediately.
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
    /// (`meedyaDBReadinessProvider`/`submissionModeProvider`), so a test can
    /// flip readiness or the submission mode WHILE a run is reading it —
    /// proving the mid-run `recheck` in `MeedyaDBContributor.contribute`
    /// actually re-reads live state rather than a snapshot. `NSLock`, never
    /// raw lock/unlock, for the same `swift test --parallel` reason as above.
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

    // MARK: - Fixtures

    private func audioCD() -> DiscTableOfContents {
        DiscTableOfContents(
            tracks: [
                DiscTrack(number: 1, startSector: 0, sectorCount: 18_000),
                DiscTrack(number: 2, startSector: 18_000, sectorCount: 21_000),
            ],
            leadOutSector: 55_500
        )
    }

    private func busyError() -> any Error {
        DiscImagingError.processFailure(exitCode: 1, stderr: "Cannot open the device: Resource busy")
    }

    private func mediumError() -> any Error {
        DiscImagingError.processFailure(exitCode: 1, stderr: "Read of track 2 failed: medium error")
    }

    private func makeViewModel(
        toc: TOCReaderBox,
        unmountRunner: StubToolRunner = StubToolRunner(),
        meedyaDBReady: Bool = false,
        publishClient: PublishStubHTTPClient? = nil,
        submissionMode: MeedyaDBSubmissionMode = .anonymous,
        // When present, BOTH providers below read live from this box instead
        // of the fixed `meedyaDBReady`/`submissionMode` values — this is what
        // lets an F1 test change readiness or mode WHILE a run is in flight,
        // through the SAME two seams `startRun` captures at the beginning and
        // the `recheck` closure reads again immediately before the network
        // call.
        settingsBox: MeedyaDBSettingsBox? = nil
    ) -> DiscIdentifyViewModel {
        let readiness: MeedyaDBReadiness = meedyaDBReady
            ? .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true))
            : .off(reason: MeedyaDBGate.offReason)
        let publisherClient = publishClient ?? PublishStubHTTPClient()

        return DiscIdentifyViewModel(
            // The factory mirrors production: the run's publisher is built
            // from the config in force, so a test can prove a ready run
            // actually reaches the wire rather than only promising to.
            identifierFactory: { config in
                let lookup = MusicBrainzDiscLookupService(
                    httpClient: OfflineStubHTTPClient(),
                    throttle: MusicBrainzRequestThrottle(minimumInterval: .zero)
                )
                guard let config else {
                    return MusicDiscIdentifier(lookupService: lookup)
                }
                return MusicDiscIdentifier(
                    lookupService: lookup,
                    publisher: MeedyaDBPublisher(config: config, httpClient: publisherClient)
                )
            },
            submissionModeProvider: { settingsBox?.mode ?? submissionMode },
            unmounter: DiscUnmounter(runner: unmountRunner, diskutilPath: "/usr/sbin/diskutil"),
            tocReader: { _ in try await toc.next() },
            tocFileReader: { _ in "" },
            meedyaDBReadinessProvider: { settingsBox?.readiness ?? readiness }
        )
    }

    /// Accepts a MeedyaDB submission and records the body that reached it.
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

    /// Always reports "nothing found" so a run finishes without a network.
    private final class OfflineStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
    }

    // MARK: - A held drive offers the right remedy

    func test_busyDrive_offersAnUnmountAndDoesNotUnmountByItself() async {
        let runner = StubToolRunner()
        let vm = makeViewModel(toc: TOCReaderBox([.failure(busyError())]), unmountRunner: runner)
        vm.sourceKind = .drive
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        XCTAssertEqual(vm.busyDevicePath, "/dev/rdisk2", "the screen must offer to release this drive")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(
            runner.callCount, 0,
            "unmounting must never happen on its own — it takes the disc away from Finder"
        )
        XCTAssertNil(vm.result)
        XCTAssertFalse(vm.isWorking)
    }

    func test_realReadFailure_doesNotOfferAnUnmount() async {
        let vm = makeViewModel(toc: TOCReaderBox([.failure(mediumError())]))
        vm.sourceKind = .drive
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        XCTAssertNil(
            vm.busyDevicePath,
            "a medium error is a real failure — offering an unmount sends the user the wrong way"
        )
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_tocFileFailureNeverOffersAnUnmount() async {
        // There is no drive to release when reading a saved file, whatever
        // the error text happens to say.
        let vm = DiscIdentifyViewModel(
            identifierFactory: { _ in MusicDiscIdentifier() },
            unmounter: DiscUnmounter(runner: StubToolRunner()),
            tocReader: { _ in throw CancellationError() },
            tocFileReader: { _ in throw DiscImagingError.processFailure(exitCode: 1, stderr: "Resource busy") },
            meedyaDBReadinessProvider: { .off(reason: MeedyaDBGate.offReason) }
        )
        vm.sourceKind = .tocFile
        vm.tocFilePath = "/tmp/saved.toc"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        XCTAssertNil(vm.busyDevicePath)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Unmount and retry

    func test_unmountAndRetry_releasesTheDriveThenIdentifiesAgain() async {
        let runner = StubToolRunner(exitCode: 0)
        // First read is blocked; the read after the unmount succeeds.
        let toc = TOCReaderBox([.failure(busyError()), .success(audioCD())])
        let vm = makeViewModel(toc: toc, unmountRunner: runner)
        vm.sourceKind = .drive
        vm.devicePath = "/dev/rdisk2"

        guard let first = vm.identify() else { return XCTFail("expected a task") }
        await first.value
        XCTAssertNotNil(vm.busyDevicePath, "precondition: the drive was reported busy")

        guard let retry = vm.unmountAndRetry() else { return XCTFail("expected an unmount task") }
        await retry.value

        XCTAssertEqual(runner.callCount, 1, "diskutil should be asked exactly once")
        XCTAssertEqual(toc.readCount, 2, "the disc must actually be re-read after being released")
        XCTAssertNil(vm.busyDevicePath, "the drive is no longer held")
        XCTAssertNotNil(vm.result, "the retry should have produced an identification")
        XCTAssertNil(vm.errorMessage)
    }

    func test_unmountFailure_isReportedAndDoesNotRetry() async {
        let runner = StubToolRunner(exitCode: 1)
        let toc = TOCReaderBox([.failure(busyError())])
        let vm = makeViewModel(toc: toc, unmountRunner: runner)
        vm.sourceKind = .drive
        vm.devicePath = "/dev/rdisk2"

        guard let first = vm.identify() else { return XCTFail("expected a task") }
        await first.value

        guard let retry = vm.unmountAndRetry() else { return XCTFail("expected an unmount task") }
        await retry.value

        XCTAssertEqual(toc.readCount, 1, "a failed release must not pretend to retry")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isUnmounting)
    }

    func test_unmountAndRetry_reReadsTheDriveThatFailed_notWhateverTheFormSaysNow() async {
        // Between the busy failure and pressing the button the user might
        // edit the field, or switch to the saved-file source. Releasing one
        // drive and then reading something else would be worse than useless.
        let runner = StubToolRunner(exitCode: 0)
        let toc = TOCReaderBox([.failure(busyError()), .success(audioCD())])
        let vm = makeViewModel(toc: toc, unmountRunner: runner)
        vm.sourceKind = .drive
        vm.devicePath = "/dev/rdisk2"

        guard let first = vm.identify() else { return XCTFail("expected a task") }
        await first.value
        XCTAssertEqual(vm.busyDevicePath, "/dev/rdisk2")

        // The user wanders off and changes the source before retrying.
        vm.sourceKind = .tocFile
        vm.tocFilePath = "/tmp/something-else.toc"

        guard let retry = vm.unmountAndRetry() else { return XCTFail("expected an unmount task") }
        await retry.value

        XCTAssertEqual(toc.readCount, 2, "the retry must re-read the DRIVE that was released")
        XCTAssertNotNil(vm.result)
        XCTAssertNil(vm.errorMessage)
    }

    func test_unmountAndRetry_isANoOpWhenNothingIsHeld() {
        let vm = makeViewModel(toc: TOCReaderBox([.success(audioCD())]))
        XCTAssertNil(vm.unmountAndRetry(), "nothing is being held, so there is nothing to release")
    }

    // MARK: - Success path

    func test_successfulRun_producesAResultAndNoError() async throws {
        let vm = makeViewModel(toc: TOCReaderBox([.success(audioCD())]))
        vm.sourceKind = .drive
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        let result = try XCTUnwrap(vm.result)
        XCTAssertNotNil(result.identity.musicDiscID, "the disc's own ID is computed offline")
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.statusMessage, "the status line must clear when the work finishes")
        XCTAssertFalse(vm.isWorking)
    }

    // MARK: - Contributing is announced up front, and honoured

    func test_meedyaDBOff_saysSoAndContributesNothing() async throws {
        let vm = makeViewModel(toc: TOCReaderBox([.success(audioCD())]), meedyaDBReady: false)
        vm.devicePath = "/dev/rdisk2"
        vm.refreshMeedyaDBReadiness()

        XCTAssertFalse(vm.willContribute, "the screen must not promise a contribution it cannot make")

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        let contribution = try XCTUnwrap(vm.result?.contribution)
        XCTAssertFalse(contribution.didSubmit)
    }

    func test_meedyaDBReady_actuallyContributesAndDoesNotJustPromiseTo() async throws {
        // The regression this exists for: the view model used to hold ONE
        // identifier built at construction with an empty, disabled publisher,
        // so a fully configured MeedyaDB produced the green "will be
        // contributed" line, then "publishing is turned off", and sent
        // nothing. Promising and not delivering is the one behaviour this
        // screen must not have.
        let publishClient = PublishStubHTTPClient()
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCD())]),
            meedyaDBReady: true,
            publishClient: publishClient
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        XCTAssertEqual(publishClient.callCount, 1, "a ready MeedyaDB must actually be reached")
        let contribution = try XCTUnwrap(vm.result?.contribution)
        XCTAssertTrue(contribution.didSubmit, "the promise on screen must be kept: \(contribution)")
    }

    func test_submissionMode_reachesTheWire() async throws {
        // The Settings picker was a dead control: the stored mode was read by
        // nothing, so "send the disc's label" silently did nothing.
        let publishClient = PublishStubHTTPClient()
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCD())]),
            meedyaDBReady: true,
            publishClient: publishClient,
            submissionMode: .full
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        let body = try XCTUnwrap(publishClient.lastBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["submission"] as? String, "full",
                       "the user's choice must reach the payload, not be assumed")
    }

    func test_anonymousIsTheDefaultOnTheWire() async throws {
        let publishClient = PublishStubHTTPClient()
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCD())]),
            meedyaDBReady: true,
            publishClient: publishClient
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        let body = try XCTUnwrap(publishClient.lastBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["submission"] as? String, "anonymous")
    }

    func test_meedyaDBReady_saysItWillContribute() {
        let vm = makeViewModel(toc: TOCReaderBox([.success(audioCD())]), meedyaDBReady: true)
        vm.refreshMeedyaDBReadiness()
        XCTAssertTrue(vm.willContribute)
    }

    // MARK: - #507: the after-the-run caption names the right reason

    /// Switched on but not finished being set up must name the missing
    /// piece, not the generic "wasn't requested" — that generic wording is
    /// what made this indistinguishable from `.off` before #507.
    func test_incompleteMeedyaDB_namesTheMissingPieceNotGenericWording() async throws {
        let box = MeedyaDBSettingsBox(readiness: .incomplete(reason: MeedyaDBGate.missingKeyReason), mode: .anonymous)
        let vm = makeViewModel(toc: TOCReaderBox([.success(audioCD())]), settingsBox: box)
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        XCTAssertEqual(
            vm.result?.contribution,
            .notAttempted(reason: MeedyaDBGate.missingKeyReason),
            "the specific missing-key reason must reach the result, not the generic wording"
        )
    }

    /// Genuinely off must keep saying so — #507's fix must not change this
    /// case's wording.
    func test_off_stillSaysWasntRequested() async throws {
        let box = MeedyaDBSettingsBox(readiness: .off(reason: MeedyaDBGate.offReason), mode: .anonymous)
        let vm = makeViewModel(toc: TOCReaderBox([.success(audioCD())]), settingsBox: box)
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await task.value

        XCTAssertEqual(
            vm.result?.contribution,
            .notAttempted(reason: MeedyaDBContributor.notRequestedReason)
        )
    }

    // MARK: - Mid-run: MeedyaDB settings changing while a run is in flight (F1)
    //
    // Each test parks the TOC read on an `AsyncGate`, changes the shared
    // `MeedyaDBSettingsBox` the view model's providers are reading from,
    // THEN releases the gate — so the change is guaranteed to land before
    // `MeedyaDBContributor.contribute`'s `recheck`, which runs immediately
    // before the network call, ever fires. Only requests whose address
    // contains `action=disc_ingest` count as an upload: `PublishStubHTTPClient`
    // is dedicated to the MeedyaDB publisher seam here (the MusicBrainz
    // lookup goes through a separate `OfflineStubHTTPClient`), so its
    // `callCount` already only reflects `disc_ingest` requests.

    private func readyReadiness(
        baseURL: String = "https://db.example",
        apiKey: String = "k"
    ) -> MeedyaDBReadiness {
        .ready(MeedyaDBPublisherConfig(baseURL: baseURL, apiKey: apiKey, enabled: true))
    }

    private func audioCDWithLabel(_ title: String) -> DiscTableOfContents {
        DiscTableOfContents(
            tracks: [
                DiscTrack(number: 1, startSector: 0, sectorCount: 18_000),
                DiscTrack(number: 2, startSector: 18_000, sectorCount: 21_000),
            ],
            leadOutSector: 55_500,
            cdText: CDTextInfo(albumTitle: title)
        )
    }

    /// (a) Switching contributing OFF mid-run withdraws the submission
    /// entirely and says so, rather than silently sending the old promise.
    func test_midRun_meedyaDBSwitchedOff_withdrawsAndReportsWhy() async throws {
        let publishClient = PublishStubHTTPClient()
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(readiness: readyReadiness(), mode: .anonymous)
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCD())], gate: gate),
            publishClient: publishClient,
            settingsBox: box
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await gate.waitUntilParked()
        box.readiness = .off(reason: MeedyaDBGate.offReason)
        gate.open()
        await task.value

        XCTAssertEqual(publishClient.callCount, 0, "switching off mid-run must withdraw the upload")
        XCTAssertEqual(
            vm.result?.contribution,
            .notAttempted(reason: MeedyaDBContributor.withdrawnReason)
        )
    }

    /// (b) Narrowing full → anonymous mid-run must actually narrow what
    /// reaches the wire, including stripping a label that was only ever
    /// going to be sent because `.full` was chosen when the run started.
    func test_midRun_fullNarrowedToAnonymous_sendsAnonymousAndDropsTheLabel() async throws {
        let publishClient = PublishStubHTTPClient()
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(readiness: readyReadiness(), mode: .full)
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCDWithLabel("My Private Disc Label"))], gate: gate),
            publishClient: publishClient,
            settingsBox: box
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
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
        let box = MeedyaDBSettingsBox(readiness: readyReadiness(), mode: .anonymous)
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCDWithLabel("My Private Disc Label"))], gate: gate),
            publishClient: publishClient,
            settingsBox: box
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
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

    /// (d) The server address changing mid-run is a config change like any
    /// other — the live config no longer equals the one this run captured,
    /// so it withdraws exactly as switching off does.
    func test_midRun_serverAddressChanged_withdraws() async throws {
        let publishClient = PublishStubHTTPClient()
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(readiness: readyReadiness(baseURL: "https://db.example"), mode: .anonymous)
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCD())], gate: gate),
            publishClient: publishClient,
            settingsBox: box
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await gate.waitUntilParked()
        box.readiness = readyReadiness(baseURL: "https://a-different-server.example")
        gate.open()
        await task.value

        XCTAssertEqual(publishClient.callCount, 0, "a changed server address must withdraw, not redirect")
        XCTAssertEqual(vm.result?.contribution, .notAttempted(reason: MeedyaDBContributor.withdrawnReason))
    }

    /// (e) The API key being removed mid-run must withdraw too — this
    /// exercises the OTHER branch of the equality check, where the live
    /// config disappears entirely (`.incomplete`) rather than merely
    /// differing (`.ready` with different fields, covered by (d)).
    func test_midRun_apiKeyRemoved_withdraws() async throws {
        let publishClient = PublishStubHTTPClient()
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(readiness: readyReadiness(), mode: .anonymous)
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCD())], gate: gate),
            publishClient: publishClient,
            settingsBox: box
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await gate.waitUntilParked()
        box.readiness = .incomplete(reason: MeedyaDBGate.missingKeyReason)
        gate.open()
        await task.value

        XCTAssertEqual(publishClient.callCount, 0, "a removed API key must withdraw the upload")
        XCTAssertEqual(vm.result?.contribution, .notAttempted(reason: MeedyaDBContributor.withdrawnReason))
    }

    /// (f) Nothing changing at all must still deliver — the recheck must not
    /// itself become a way to accidentally suppress a legitimate, unchanged
    /// contribution.
    func test_midRun_nothingChanged_stillContributes() async throws {
        let publishClient = PublishStubHTTPClient()
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(readiness: readyReadiness(), mode: .full)
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCD())], gate: gate),
            publishClient: publishClient,
            settingsBox: box
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await gate.waitUntilParked()
        gate.open()
        await task.value

        XCTAssertEqual(publishClient.callCount, 1, "an unchanged run must still actually contribute")
        let body = try XCTUnwrap(publishClient.lastBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["submission"] as? String, "full")
    }

    // MARK: - The on-screen notice during a run (`runWillContribute`)

    /// The regression #… F1's screen-wiring half exists for: without a
    /// frozen `runWillContribute`, turning contributing ON while a run that
    /// started without it is still going would flip the notice to promise a
    /// contribution that run has no way to make.
    func test_runWillContribute_reflectsWhatThisRunPromised_notLiveSettings() async throws {
        let gate = AsyncGate()
        let box = MeedyaDBSettingsBox(readiness: .off(reason: MeedyaDBGate.offReason), mode: .anonymous)
        let vm = makeViewModel(
            toc: TOCReaderBox([.success(audioCD())], gate: gate),
            settingsBox: box
        )
        vm.devicePath = "/dev/rdisk2"

        guard let task = vm.identify() else { return XCTFail("expected a task") }
        await gate.waitUntilParked()

        XCTAssertFalse(vm.runWillContribute, "this run started with contributing off")
        // The live setting flips ON while the run is still going...
        box.readiness = readyReadiness()
        // The screen re-reads settings only when told to — the view calls
        // `refreshMeedyaDBReadiness()` from its `.onChange`/`.onReceive`
        // handlers. The test must do the same, or `willContribute` still
        // shows the value read at run start (CI red on d602cf0: this
        // precondition failed because the refresh was missing).
        vm.refreshMeedyaDBReadiness()
        XCTAssertTrue(vm.willContribute, "precondition: the LIVE setting really did change")
        // ...but the frozen promise for the run already in progress must not
        // follow it, because that run's own `recheck` can only narrow or
        // withdraw, never add a contribution that was never asked for.
        XCTAssertFalse(vm.runWillContribute, "a run already in progress must not retroactively promise more")

        gate.open()
        await task.value

        XCTAssertFalse(
            vm.result?.contribution.didSubmit ?? true,
            "switching on mid-run cannot make an already-declined run start contributing"
        )
    }

    // MARK: - Guards and blocked reasons

    func test_everySourceKindExplainsWhatIsMissing() {
        let vm = makeViewModel(toc: TOCReaderBox([.success(audioCD())]))

        for kind in DiscIdentifyViewModel.SourceKind.allCases {
            vm.sourceKind = kind
            vm.devicePath = ""
            vm.tocFilePath = ""
            XCTAssertFalse(vm.canStart, "\(kind.rawValue) with nothing filled in must not start")
            XCTAssertNotNil(
                vm.startBlockedReason,
                "\(kind.rawValue) must say what is missing rather than leaving a dead button"
            )
        }
    }

    func test_identify_withNoDriveDoesNotStart() {
        let toc = TOCReaderBox([.success(audioCD())])
        let vm = makeViewModel(toc: toc)
        vm.sourceKind = .drive
        vm.devicePath = "   "

        XCTAssertNil(vm.identify())
        XCTAssertEqual(toc.readCount, 0, "a rejected start must not touch the drive")
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_cancel_withNothingRunningIsANoOp() {
        let vm = makeViewModel(toc: TOCReaderBox([.success(audioCD())]))
        vm.cancel()
        XCTAssertFalse(vm.isWorking)
        XCTAssertFalse(vm.isCancelling)
        XCTAssertNil(vm.errorMessage)
    }
}
