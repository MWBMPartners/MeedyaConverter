// ============================================================================
// MeedyaConverter — DiscIdentifyViewModel (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The view model behind the in-app disc identification screen: read a music
// disc's table of contents (from a drive, or from a `.toc` file saved
// earlier), work out what the disc is, and — only when the user has switched
// it on — contribute it to MeedyaDB.
//
// Every collaborator is injected, so the whole flow is unit-tested with no
// drive, no network and no MeedyaDB. Mirrors `MakeMKVRipViewModel`'s seams.
//
// TWO THINGS THIS SCREEN MUST GET RIGHT, both learned the hard way on the
// rip screen:
//
//   1. `cancel()` ONLY cancels. Clearing the busy flag, the task handle or
//      the message here as well as in the task's own tail lets a stale run
//      land on top of whatever started next. Leaving `isWorking` true until
//      the task tidies up also closes the re-entry window for free.
//   2. A disabled button always says why. `startBlockedReason` names the
//      next step rather than leaving a dead control on screen.
//
// AND THE macOS-SPECIFIC ONE: the system mounts an inserted disc, and cdrdao
// cannot open the drive while it does. When a read fails that way the screen
// does NOT silently unmount — it says what happened and offers a button
// (owner decision, 2026-09-21), because unmounting takes the disc away from
// Finder and from anything else reading it.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - DiscIdentifyViewModel

@MainActor
@Observable
final class DiscIdentifyViewModel {

    // MARK: - Injected seams

    private let identifier: MusicDiscIdentifier
    private let unmounter: DiscUnmounter
    /// Reads a table of contents from a real drive. Returns the TOC or
    /// throws — the same contract `DiscImagingController` has.
    private let tocReader: @Sendable (_ devicePath: String) async throws -> DiscTableOfContents
    /// Reads a `.toc` file's text. Injected so tests need no filesystem.
    private let tocFileReader: @Sendable (_ path: String) throws -> String
    private let meedyaDBReadinessProvider: @Sendable () -> MeedyaDBReadiness

    init(
        identifier: MusicDiscIdentifier = MusicDiscIdentifier(),
        unmounter: DiscUnmounter = DiscUnmounter(),
        tocReader: @escaping @Sendable (String) async throws -> DiscTableOfContents = { devicePath in
            // Inlined rather than referencing a static on this @MainActor
            // class: such a static is itself MainActor-isolated, which a
            // default argument evaluated at the call site cannot rely on.
            let cdrdao = try BundledToolLocator(toolName: "cdrdao", userOverridePath: nil).locate()
            let scratch = NSTemporaryDirectory() + "meedya-identify-\(UUID().uuidString).toc"
            defer {
                try? FileManager.default.removeItem(atPath: scratch)
                // cdrdao writes a .bin datafile beside the .toc even for read-toc.
                try? FileManager.default.removeItem(
                    atPath: (scratch as NSString).deletingPathExtension + ".bin"
                )
            }
            let controller = DiscImagingController(cdrdaoPath: cdrdao)
            return try await controller.readTableOfContents(device: devicePath, tocPath: scratch)
        },
        tocFileReader: @escaping @Sendable (String) throws -> String = { try String(contentsOfFile: $0, encoding: .utf8) },
        meedyaDBReadinessProvider: @escaping @Sendable () -> MeedyaDBReadiness = {
            MeedyaDBGate.readiness(in: .standard, apiKey: APIKeyManager().key(for: .meedyaDB)?.apiKey)
        }
    ) {
        self.identifier = identifier
        self.unmounter = unmounter
        self.tocReader = tocReader
        self.tocFileReader = tocFileReader
        self.meedyaDBReadinessProvider = meedyaDBReadinessProvider
    }

    // MARK: - Source

    enum SourceKind: String, CaseIterable, Identifiable {
        case drive = "Disc in a Drive"
        case tocFile = "Saved Table of Contents"
        var id: String { rawValue }
    }

    var sourceKind: SourceKind = .drive
    var devicePath: String = ""
    var tocFilePath: String = ""

    /// The trimmed device path, or `nil` when the field doesn't name one.
    var resolvedDevicePath: String? {
        let trimmed = devicePath.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    var resolvedTOCFilePath: String? {
        let trimmed = tocFilePath.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Contribution preference

    /// Whether contributing is switched on and usable. Re-read rather than
    /// cached, so turning MeedyaDB on in Settings takes effect immediately.
    private(set) var meedyaDBReadiness: MeedyaDBReadiness?

    func refreshMeedyaDBReadiness() {
        meedyaDBReadiness = meedyaDBReadinessProvider()
    }

    /// Whether this run will try to contribute. False whenever MeedyaDB
    /// isn't ready, so the screen never promises something it can't do.
    var willContribute: Bool {
        meedyaDBReadiness?.isReady == true
    }

    // MARK: - Running

    private(set) var isWorking = false
    private(set) var isCancelling = false
    private(set) var statusMessage: String?
    private(set) var result: MusicDiscIdentificationResult?
    private(set) var errorMessage: String?

    /// Set when a read failed because something else holds the drive. The
    /// view turns this into an explanation plus an "Unmount and Try Again"
    /// button — never an automatic unmount.
    private(set) var busyDevicePath: String?

    var canStart: Bool {
        guard !isWorking, !isUnmounting else { return false }
        switch sourceKind {
        case .drive: return resolvedDevicePath != nil
        case .tocFile: return resolvedTOCFilePath != nil
        }
    }

    /// Why the Identify button is disabled, or `nil` when it is enabled.
    /// `nil` while working too — the button already says so.
    var startBlockedReason: String? {
        if isWorking { return nil }
        if isUnmounting { return "Waiting for macOS to release the drive\u{2026}" }
        switch sourceKind {
        case .drive:
            return resolvedDevicePath == nil
                ? "Enter the drive to read, for example /dev/rdisk2."
                : nil
        case .tocFile:
            return resolvedTOCFilePath == nil
                ? "Choose a .toc file saved by a previous read."
                : nil
        }
    }

    @ObservationIgnored
    nonisolated(unsafe) private var work: Task<Void, Never>?

    /// Starts an identification run. Synchronous entry point so a `Button`
    /// needs no `Task { }`; the task is returned so tests can `await` it.
    @discardableResult
    func identify() -> Task<Void, Never>? {
        guard !isWorking, !isUnmounting else { return nil }

        errorMessage = nil
        busyDevicePath = nil
        result = nil
        refreshMeedyaDBReadiness()

        let source: Source
        switch sourceKind {
        case .drive:
            guard let device = resolvedDevicePath else {
                errorMessage = "Enter the drive to read first."
                return nil
            }
            source = .drive(device)
        case .tocFile:
            guard let path = resolvedTOCFilePath else {
                errorMessage = "Choose a .toc file first."
                return nil
            }
            source = .tocFile(path)
        }

        isWorking = true
        isCancelling = false
        statusMessage = source.startingMessage
        let contribute = willContribute

        // Unwrap self first: `await self?.run(...)` makes the closure return
        // `()?`, so the task would be `Task<()?, Never>` and not match.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRun(source: source, contribute: contribute)
        }
        work = task
        return task
    }

    private enum Source {
        case drive(String)
        case tocFile(String)

        var startingMessage: String {
            switch self {
            case .drive: return "Reading the disc\u{2026}"
            case .tocFile: return "Reading the saved table of contents\u{2026}"
            }
        }
    }

    private func performRun(source: Source, contribute: Bool) async {
        do {
            let toc = try await loadTOC(source)
            guard !Task.isCancelled else { throw CancellationError() }

            statusMessage = contribute
                ? "Identifying the disc and contributing it\u{2026}"
                : "Identifying the disc\u{2026}"

            let outcome = try await identifier.identify(toc: toc, contribute: contribute)
            result = outcome
            statusMessage = nil
        } catch is CancellationError {
            errorMessage = "Identification was cancelled."
        } catch {
            // A held drive is not a read failure — offer the remedy that
            // actually works rather than a generic error.
            if case .drive(let device) = source, DiscBusyDetector.looksBusy(error) {
                busyDevicePath = device
                errorMessage =
                    "Something else on your Mac is using this drive, so the disc can't be read yet."
            } else {
                errorMessage = error.localizedDescription
            }
            statusMessage = nil
        }
        isWorking = false
        isCancelling = false
        work = nil
    }

    private func loadTOC(_ source: Source) async throws -> DiscTableOfContents {
        switch source {
        case .drive(let device):
            return try await tocReader(device)
        case .tocFile(let path):
            let text = try tocFileReader(path)
            return try CdrdaoTocParser.parse(text)
        }
    }

    /// Cancels an in-progress run. ONLY cancels — cleanup happens inside the
    /// running task, so a stale run can never clobber a newer one.
    func cancel() {
        guard work != nil, isWorking else { return }
        isCancelling = true
        work?.cancel()
    }

    // MARK: - Unmount and retry

    private(set) var isUnmounting = false

    /// Asks macOS to release the drive, then identifies again. Only ever
    /// called from the button the user presses — never automatically.
    @discardableResult
    func unmountAndRetry() -> Task<Void, Never>? {
        guard !isWorking, !isUnmounting, let device = busyDevicePath else { return nil }

        isUnmounting = true
        statusMessage = "Asking macOS to release the drive\u{2026}"
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performUnmount(device: device)
        }
        work = task
        return task
    }

    private func performUnmount(device: String) async {
        do {
            let outcome = try await unmounter.unmount(devicePath: device)
            isUnmounting = false
            switch outcome {
            case .unmounted:
                busyDevicePath = nil
                statusMessage = nil
                work = nil
                // Await the retry from here so the task this method belongs
                // to covers the WHOLE operation — release then read. A caller
                // (or a test) that awaits `unmountAndRetry()` would otherwise
                // return while the re-read was still in flight, and have to
                // poll to find out when it finished.
                if let retry = identify() {
                    await retry.value
                }
            case .failed(let reason):
                statusMessage = nil
                errorMessage = reason
                work = nil
            }
        } catch is CancellationError {
            isUnmounting = false
            statusMessage = nil
            errorMessage = "Releasing the drive was cancelled."
            work = nil
        } catch {
            isUnmounting = false
            statusMessage = nil
            errorMessage = error.localizedDescription
            work = nil
        }
    }

    // MARK: - Deinit

    deinit {
        work?.cancel()
    }
}
