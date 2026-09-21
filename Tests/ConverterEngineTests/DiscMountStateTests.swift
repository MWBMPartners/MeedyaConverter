// ============================================================================
// MeedyaConverter — DiscMountStateTests (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Covers busy-drive detection and the unmount call. No drive is touched: the
// tool runner is a mock, so `diskutil` is never launched in CI.
//
// The point of these tests is that the app offers the RIGHT remedy. Calling a
// real read failure "busy" sends the user off to unmount a drive that was
// never the problem; missing a genuine busy leaves them stuck with an error
// they cannot act on.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// Uniquely named so it never collides with the other stubs in this module.
private final class UnmountStubToolRunner: ExternalToolRunning, @unchecked Sendable {
    struct Call: Sendable, Equatable {
        let binaryPath: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private let result: Result<ExternalToolResult, any Error>
    private var recorded: [Call] = []

    init(exitCode: Int32, stderr: String = "") {
        self.result = .success(ExternalToolResult(exitCode: exitCode, stderr: stderr))
    }
    init(throwing error: any Error) {
        self.result = .failure(error)
    }

    var calls: [Call] { lock.withLock { recorded } }

    func run(binaryPath: String, arguments: [String]) async throws -> ExternalToolResult {
        lock.withLock { recorded.append(Call(binaryPath: binaryPath, arguments: arguments)) }
        return try result.get()
    }
}

final class DiscMountStateTests: XCTestCase {

    // MARK: - Busy detection

    func test_looksBusy_recognisesTheWaysMacOSSaysTheDriveIsHeld() {
        let held = [
            "cdrdao: Cannot open the device /dev/rdisk2: Resource busy",
            "Error: Device or resource busy",
            "unable to open device",
            "could not open device '/dev/rdisk4'",
            "open failed: Permission denied",
            "The drive is busy",
            "Device in use by another process",
        ]
        for message in held {
            XCTAssertTrue(
                DiscBusyDetector.looksBusy(message),
                "\"\(message)\" should offer the user an unmount"
            )
        }
    }

    func test_looksBusy_doesNotClaimBusyForARealReadFailure() {
        let notHeld = [
            "cdrdao: Read of track 3 failed: medium error",
            "No disc in drive",
            "Unsupported disc format",
            "toc file is corrupt",
            "",
        ]
        for message in notHeld {
            XCTAssertFalse(
                DiscBusyDetector.looksBusy(message),
                "\"\(message)\" is a real failure — offering an unmount would send the user the wrong way"
            )
        }
    }

    func test_looksBusy_isCaseInsensitive() {
        XCTAssertTrue(DiscBusyDetector.looksBusy("RESOURCE BUSY"))
        XCTAssertTrue(DiscBusyDetector.looksBusy("Resource Busy"))
    }

    func test_looksBusy_readsTheStderrOfAProcessFailure() {
        let busy = DiscImagingError.processFailure(exitCode: 1, stderr: "Cannot open the device: Resource busy")
        let notBusy = DiscImagingError.processFailure(exitCode: 1, stderr: "medium error on track 4")

        XCTAssertTrue(DiscBusyDetector.looksBusy(busy))
        XCTAssertFalse(DiscBusyDetector.looksBusy(notBusy))
    }

    func test_looksBusy_fallsBackToTheDescriptionForOtherErrors() {
        XCTAssertFalse(DiscBusyDetector.looksBusy(DiscImagingError.noBinary))
    }

    // MARK: - Device node mapping

    func test_diskNode_undoesTheRawDeviceTransformation() {
        XCTAssertEqual(DriveListingParser.diskNode(forRawDeviceNode: "/dev/rdisk2"), "/dev/disk2")
        XCTAssertEqual(DriveListingParser.diskNode(forRawDeviceNode: "/dev/rdisk10"), "/dev/disk10")
    }

    func test_diskNode_roundTripsWithRawDeviceNode() {
        for node in ["/dev/disk0", "/dev/disk3", "/dev/disk12"] {
            let raw = DriveListingParser.rawDeviceNode(forDiskNode: node)
            XCTAssertEqual(DriveListingParser.diskNode(forRawDeviceNode: raw), node)
        }
    }

    func test_diskNode_passesThroughAnythingItDoesNotUnderstand() {
        // Better to hand diskutil a path it rejects with its own message than
        // to mangle it into a DIFFERENT device and unmount the wrong disk.
        XCTAssertEqual(DriveListingParser.diskNode(forRawDeviceNode: "/dev/sr0"), "/dev/sr0")
        XCTAssertEqual(DriveListingParser.diskNode(forRawDeviceNode: "1"), "1")
        XCTAssertEqual(DriveListingParser.diskNode(forRawDeviceNode: ""), "")
    }

    // MARK: - Unmounting

    func test_unmount_callsDiskutilWithTheDiskNodeNotTheRawNode() async throws {
        let runner = UnmountStubToolRunner(exitCode: 0)
        let unmounter = DiscUnmounter(runner: runner, diskutilPath: "/usr/sbin/diskutil")

        let outcome = try await unmounter.unmount(devicePath: "/dev/rdisk2")

        XCTAssertEqual(outcome, .unmounted)
        XCTAssertTrue(outcome.didUnmount)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls.first?.binaryPath, "/usr/sbin/diskutil")
        XCTAssertEqual(
            runner.calls.first?.arguments,
            ["unmountDisk", "/dev/disk2"],
            "diskutil wants the buffered node, not cdrdao's raw one"
        )
    }

    func test_unmount_acceptsADiskNodeAlready() async throws {
        let runner = UnmountStubToolRunner(exitCode: 0)
        let unmounter = DiscUnmounter(runner: runner)

        _ = try await unmounter.unmount(devicePath: "  /dev/disk3  ")

        XCTAssertEqual(runner.calls.first?.arguments, ["unmountDisk", "/dev/disk3"])
    }

    func test_unmount_blankDeviceDoesNotLaunchAnything() async throws {
        let runner = UnmountStubToolRunner(exitCode: 0)
        let unmounter = DiscUnmounter(runner: runner)

        let outcome = try await unmounter.unmount(devicePath: "   ")

        XCTAssertEqual(runner.calls.count, 0, "nothing to unmount must not run diskutil")
        guard case .failed(let reason) = outcome else {
            return XCTFail("a blank device cannot be a success")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func test_unmount_nonZeroExitIsReportedWithDiskutilsOwnWords() async throws {
        let runner = UnmountStubToolRunner(
            exitCode: 1,
            stderr: "Unmount failed for /dev/disk2: dissenter"
        )
        let unmounter = DiscUnmounter(runner: runner)

        let outcome = try await unmounter.unmount(devicePath: "/dev/rdisk2")

        guard case .failed(let reason) = outcome else {
            return XCTFail("a non-zero exit is a failure")
        }
        XCTAssertTrue(reason.contains("dissenter"), "diskutil's own explanation is the useful part")
        XCTAssertTrue(reason.contains("/dev/disk2"))
    }

    func test_unmount_nonZeroExitWithNoStderrStillSaysSomethingUseful() async throws {
        let runner = UnmountStubToolRunner(exitCode: 1, stderr: "   ")
        let unmounter = DiscUnmounter(runner: runner)

        let outcome = try await unmounter.unmount(devicePath: "/dev/rdisk2")

        guard case .failed(let reason) = outcome else {
            return XCTFail("a non-zero exit is a failure")
        }
        XCTAssertTrue(reason.contains("/dev/disk2"))
        XCTAssertTrue(reason.contains("1"), "the exit code is all we have, so it must be shown")
    }

    func test_unmount_launchFailureIsReportedNotThrown() async throws {
        let runner = UnmountStubToolRunner(
            throwing: ExternalToolError.launchFailed(binaryPath: "/usr/sbin/diskutil", reason: "not found")
        )
        let unmounter = DiscUnmounter(runner: runner)

        let outcome = try await unmounter.unmount(devicePath: "/dev/rdisk2")

        guard case .failed(let reason) = outcome else {
            return XCTFail("a launch failure is a failure, not a success")
        }
        XCTAssertTrue(reason.contains("diskutil"))
    }

    func test_unmount_cancellationPropagates() async {
        let runner = UnmountStubToolRunner(throwing: CancellationError())
        let unmounter = DiscUnmounter(runner: runner)

        do {
            _ = try await unmounter.unmount(devicePath: "/dev/rdisk2")
            XCTFail("cancellation must propagate, not be folded into a failed outcome")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }
}
