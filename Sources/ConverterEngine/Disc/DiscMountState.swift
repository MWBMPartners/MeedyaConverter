// ============================================================================
// MeedyaConverter — Disc mount state (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// macOS mounts an inserted disc automatically, and `cdrdao` cannot open the
// raw device while the system holds it. Reading a disc from the app
// therefore fails with a "device busy" style error until the medium is
// unmounted. This file is the honest handling of that:
//
//   * `DiscBusyDetector` — pure: does this error text mean "something else
//     has the drive", as opposed to a real read failure?
//   * `DiscUnmounter` — runs `diskutil unmountDisk` through an injected
//     seam, so the decision to unmount is testable without a drive.
//
// ⚠️ UNMOUNTING IS NEVER AUTOMATIC. It takes the disc away from Finder and
// from anything else reading it, so it happens only when the user presses a
// button that says so (owner decision, 2026-09-21). Nothing here is called
// on a timer, on appear, or as a silent retry.
//
// `RawCDReadPlanner.buildMacOSUnmountArguments` has existed as a pure builder
// with a note that wiring it needs the cdrdao `--device` → `diskutil` node
// mapping, which could not be verified without hardware. That mapping is not
// needed in this direction: the app is handed a device path by the user (or
// by `drutil`), and `diskNode(forRawDeviceNode:)` below simply undoes the
// well-defined `/dev/diskN` → `/dev/rdiskN` transformation that
// `DriveListingParser.rawDeviceNode(forDiskNode:)` applies. Nothing is
// guessed; a path that is not in that form is returned untouched and
// `diskutil` is left to reject it with its own message.
// ============================================================================

import Foundation

// MARK: - DiscBusyDetector

/// Decides whether a failure means "the drive is held by something else"
/// rather than "this disc could not be read". Pure and case-insensitive.
public enum DiscBusyDetector {

    /// Fragments that macOS, cdrdao and the BSD layer use for a drive that
    /// something else has claimed. Deliberately conservative: a false
    /// positive here offers an unmount that will not help, which is merely
    /// annoying, while a false negative leaves the user stuck with an error
    /// they cannot act on.
    static let busyFragments = [
        "resource busy",
        "device busy",
        "device or resource busy",
        "is busy",
        "cannot open the device",
        "could not open device",
        "unable to open device",
        "permission denied",
        "failed to open device",
        "in use by another",
    ]

    /// Whether `message` looks like a held-drive failure.
    public static func looksBusy(_ message: String) -> Bool {
        let haystack = message.lowercased()
        return busyFragments.contains { haystack.contains($0) }
    }

    /// Whether `error` looks like a held-drive failure. Reads the `stderr`
    /// of a `DiscImagingError.processFailure` when that is what it is, and
    /// otherwise falls back to the error's own description.
    public static func looksBusy(_ error: any Error) -> Bool {
        if let imaging = error as? DiscImagingError,
           case .processFailure(_, let stderr) = imaging {
            return looksBusy(stderr)
        }
        return looksBusy(error.localizedDescription)
    }
}

// MARK: - Device node mapping

extension DriveListingParser {

    /// The inverse of `rawDeviceNode(forDiskNode:)`: `/dev/rdisk2` →
    /// `/dev/disk2`. Anything not in that form is returned unchanged, so a
    /// path this does not understand is passed through for `diskutil` to
    /// reject with its own message rather than being mangled into a
    /// different device.
    public static func diskNode(forRawDeviceNode rawNode: String) -> String {
        let prefix = "/dev/rdisk"
        guard rawNode.hasPrefix(prefix) else { return rawNode }
        return "/dev/disk" + rawNode.dropFirst(prefix.count)
    }
}

// MARK: - DiscUnmounter

/// The result of asking macOS to release a disc.
public enum DiscUnmountOutcome: Sendable, Equatable {
    /// The medium was released; a read can be retried.
    case unmounted
    /// `diskutil` refused, or could not be run. `reason` is shown to the user.
    case failed(reason: String)

    public var didUnmount: Bool {
        if case .unmounted = self { return true }
        return false
    }
}

/// Runs `diskutil unmountDisk` for a device the user asked to free up.
///
/// Only ever called from an explicit user action — see this file's header.
public struct DiscUnmounter: Sendable {

    /// `diskutil` is a system tool at a fixed location; it is not discovered
    /// through `BundledToolLocator` because we never ship or bundle it.
    /// Named `default…` so it never shadows the instance property below.
    public static let defaultDiskutilPath = "/usr/sbin/diskutil"

    private let runner: any ExternalToolRunning
    private let diskutilPath: String

    public init(
        runner: any ExternalToolRunning = ExternalToolRunner(),
        diskutilPath: String = DiscUnmounter.defaultDiskutilPath
    ) {
        self.runner = runner
        self.diskutilPath = diskutilPath
    }

    /// Ask macOS to unmount the medium in `devicePath`.
    ///
    /// - Parameter devicePath: either form — `/dev/rdisk2` (what cdrdao
    ///   wants) or `/dev/disk2` (what `diskutil` wants). It is normalised.
    /// - Throws: `CancellationError` only; every other outcome is a
    ///   `DiscUnmountOutcome`, so a caller can show it without a `do`/`catch`.
    public func unmount(devicePath: String) async throws -> DiscUnmountOutcome {
        let trimmed = devicePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failed(reason: "No drive was given, so there was nothing to release.")
        }

        let diskNode = DriveListingParser.diskNode(forRawDeviceNode: trimmed)
        let command = RawCDReadPlanner.buildMacOSUnmountArguments(diskNode: diskNode)

        do {
            let result = try await runner.run(binaryPath: diskutilPath, arguments: command.arguments)
            guard result.exitCode == 0 else {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failed(
                    reason: detail.isEmpty
                        ? "macOS would not release \(diskNode) (diskutil exited with code \(result.exitCode))."
                        : "macOS would not release \(diskNode): \(detail)"
                )
            }
            return .unmounted
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failed(reason: "Could not run diskutil: \(error.localizedDescription)")
        }
    }
}
