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
//   * the screen says whether it will contribute BEFORE the run, and never
//     contributes when MeedyaDB isn't ready.
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
    private final class TOCReaderBox: @unchecked Sendable {
        private let lock = NSLock()
        private var attempts = 0
        private let outcomes: [Result<DiscTableOfContents, any Error>]

        /// One outcome per expected read, in order; the last repeats.
        init(_ outcomes: [Result<DiscTableOfContents, any Error>]) {
            self.outcomes = outcomes
        }

        var readCount: Int { lock.withLock { attempts } }

        func next() throws -> DiscTableOfContents {
            let outcome: Result<DiscTableOfContents, any Error> = lock.withLock {
                let index = min(attempts, outcomes.count - 1)
                attempts += 1
                return outcomes[index]
            }
            return try outcome.get()
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
        meedyaDBReady: Bool = false
    ) -> DiscIdentifyViewModel {
        let readiness: MeedyaDBReadiness = meedyaDBReady
            ? .ready(MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true))
            : .off(reason: MeedyaDBGate.offReason)

        return DiscIdentifyViewModel(
            identifier: MusicDiscIdentifier(
                lookupService: MusicBrainzDiscLookupService(
                    httpClient: OfflineStubHTTPClient(),
                    throttle: MusicBrainzRequestThrottle(minimumInterval: .zero)
                )
            ),
            unmounter: DiscUnmounter(runner: unmountRunner, diskutilPath: "/usr/sbin/diskutil"),
            tocReader: { _ in try toc.next() },
            tocFileReader: { _ in "" },
            meedyaDBReadinessProvider: { readiness }
        )
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
            identifier: MusicDiscIdentifier(),
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

    func test_meedyaDBReady_saysItWillContribute() {
        let vm = makeViewModel(toc: TOCReaderBox([.success(audioCD())]), meedyaDBReady: true)
        vm.refreshMeedyaDBReadiness()
        XCTAssertTrue(vm.willContribute)
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
