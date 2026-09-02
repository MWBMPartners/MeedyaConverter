// ============================================================================
// MeedyaConverter — DiscImagingController
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - DiscImagingError

/// Process- and pipeline-level errors for `DiscImagingController`, modelled on
/// `FFmpegProcessError.processFailure(exitCode:stderr:)`.
public enum DiscImagingError: LocalizedError, Sendable {
    /// `cdrdao` exited with a non-zero status.
    case processFailure(exitCode: Int32, stderr: String)

    /// The read was cancelled by the user.
    case cancelled

    /// The `cdrdao` binary could not be located or launched.
    case noBinary

    /// A read is already running — a second cannot be started.
    case alreadyRunning

    /// The disc is copy-protected and a raw copy would be non-functional.
    /// Raised by the DRM gate BEFORE any output file is created, so no broken
    /// artifact is ever emitted and nothing is decrypted.
    case protectedDisc(DiscProtectionType, reason: String)

    /// Post-read verification failed — the image's byte count or checksum did
    /// not match the expectation derived from the disc's TOC.
    case verificationFailed(reason: String)

    /// The `.toc` output path already exists. cdrdao refuses to overwrite an
    /// existing toc-file, so this is surfaced as a typed error rather than a
    /// raw non-zero exit; the caller clears the file (or passes `--overwrite`)
    /// and retries.
    case outputExists(path: String)

    public var errorDescription: String? {
        switch self {
        case .processFailure(let code, let stderr):
            return "cdrdao exited with code \(code): \(stderr.prefix(500))"
        case .cancelled:
            return "The disc read was cancelled."
        case .noBinary:
            return "No cdrdao binary was found. Install cdrdao or specify its location."
        case .alreadyRunning:
            return "A disc read is already running."
        case .protectedDisc(_, let reason):
            return reason
        case .verificationFailed(let reason):
            return "Image verification failed: \(reason)"
        case .outputExists(let path):
            return "Output file already exists: \(path). cdrdao will not overwrite it."
        }
    }
}

// MARK: - ImageVerification

/// The result of post-image verification: an exact byte-count check against
/// the TOC-derived expectation, plus a recorded SHA-256 for the sidecar log.
public struct ImageVerification: Codable, Sendable, Equatable {
    /// Actual size of the written `.bin`.
    public let byteCount: Int64

    /// Size the `.bin` should have, from `RawCDReadPlanner.expectedBinByteCount`.
    public let expectedByteCount: Int64

    /// Lowercase hex SHA-256 of the `.bin`, or `nil` when checksumming was
    /// skipped or unavailable.
    public let sha256Hex: String?

    /// Whether the actual size matches the expectation exactly.
    public var sizeMatches: Bool { byteCount == expectedByteCount }

    public init(byteCount: Int64, expectedByteCount: Int64, sha256Hex: String?) {
        self.byteCount = byteCount
        self.expectedByteCount = expectedByteCount
        self.sha256Hex = sha256Hex
    }
}

// MARK: - DiscImagingController

/// The Audio CD imaging executor: it drives a `cdrdao` subprocess to read a
/// physical disc into a faithful BIN/CUE image, then verifies it.
///
/// It is modelled line-for-line on `FFmpegProcessController`: an
/// `@unchecked Sendable final class` guarding its mutable state with an
/// `NSLock`, launching `Foundation.Process` with `Pipe` `readabilityHandler`s,
/// surfacing progress through an `AsyncStream`, and completing via the
/// process's `terminationHandler` (never a blocking `waitUntilExit` on a
/// cooperative thread). Cancellation sends `SIGCONT` then `terminate()`, and
/// the stderr capture buffer is capped, exactly as in the FFmpeg controller.
///
/// On top of that shared skeleton it adds the pieces specific to disc imaging:
/// the DRM gate that runs *first* (issue #492 detect-and-warn), a `.bin`
/// size-polling task that derives byte-level progress cdrdao does not print,
/// subchannel sidecar splitting through the reused `SubchannelCodec`, `.cue`
/// emission through the reused `CueSheetWriter`, and byte-count + SHA-256
/// verification.
///
/// ## Hardware boundary (honest capability)
///
/// `readTableOfContents(...)` and `startImaging(...)` launch a real `cdrdao`
/// against a real optical device. There is no simulated read, no canned TOC,
/// and no stub that returns fabricated data: where hardware or the tool is
/// absent these methods throw honestly (`noBinary`, `processFailure`). They are
/// compile-checked in CI and hardware-verified on the manual matrix
/// (macOS-Direct + Linux, per #495). `finalizeImage(...)` does only local file
/// I/O (splitting, CUE emission, checksum) and no device access.
public final class DiscImagingController: @unchecked Sendable {

    // MARK: - Properties

    /// Full path to the located `cdrdao` binary.
    private let cdrdaoPath: String

    /// The underlying process, when running.
    private var process: Process?

    /// The controller's lifecycle state — the reused `FFmpegProcessState` enum
    /// (idle / running / paused / completed / cancelled), same semantics.
    public private(set) var state: FFmpegProcessState = .idle

    /// Accumulated stderr (capped) for error reporting.
    private var stderrBuffer = ""

    /// Soft cap on the stderr buffer (10 MiB), mirroring the FFmpeg controller.
    private let maxBufferBytes = 10 * 1024 * 1024

    /// Running error count parsed from cdrdao's stderr.
    private var errorCount = 0

    /// The track cdrdao last reported reading, for advisory progress.
    private var currentTrack: Int?

    /// Total sectors estimated from cdrdao's lead-in TOC table rows, used to
    /// size the progress bar for the size-polling task.
    private var estimatedTotalSectors = 0

    /// Whether the in-flight read captured subchannel data (2448-byte sectors).
    private var pollingIncludesSubchannel = false

    /// The `.bin` path being polled for size.
    private var pollingBinPath = ""

    /// Serial lock for thread-safe state access.
    private let lock = NSLock()

    /// The active progress stream's continuation.
    private var progressContinuation: AsyncStream<ImagingProgress>.Continuation?

    /// The `.bin` size-polling task, cancelled on termination/stop.
    private var pollingTask: Task<Void, Never>?

    // MARK: - Initialiser

    /// Create a controller that will launch the `cdrdao` binary at the given
    /// path (typically resolved by `BundledToolLocator`).
    public init(cdrdaoPath: String) {
        self.cdrdaoPath = cdrdaoPath
    }

    // MARK: - Phase 1: read-toc

    /// Read the disc's table of contents (`cdrdao read-toc`) and parse the
    /// written `.toc` into a `DiscTableOfContents`.
    ///
    /// Completion is driven by the process's `terminationHandler` bridged to a
    /// `CheckedContinuation`; there is no blocking wait. On a non-zero exit the
    /// captured stderr is surfaced as `DiscImagingError.processFailure`.
    ///
    /// - Parameters:
    ///   - device: cdrdao `--device` string.
    ///   - driver: Optional `--driver` value.
    ///   - session: Optional session number.
    ///   - fastToc: When `true`, adds `--fast-toc`.
    ///   - tocPath: Output `.toc` path.
    /// - Returns: The parsed table of contents.
    /// - Throws: `DiscImagingError` on launch/exit failure, or
    ///   `ImagingError.malformedCdrdaoToc` if the written `.toc` cannot be
    ///   parsed. **Launches cdrdao — hardware-verified on the manual matrix.**
    public func readTableOfContents(
        device: String,
        driver: String? = nil,
        session: Int? = nil,
        fastToc: Bool = false,
        tocPath: String
    ) async throws -> DiscTableOfContents {
        let datafileName = URL(fileURLWithPath: tocPath)
            .deletingPathExtension()
            .appendingPathExtension("bin")
            .lastPathComponent
        let arguments = RawCDReadPlanner.buildReadTocArguments(
            device: device,
            driver: driver,
            session: session,
            fastToc: fastToc,
            datafileName: datafileName,
            tocPath: tocPath
        )

        let exitStatus = try await runToCompletion(arguments: arguments)
        if exitStatus != 0 {
            throw DiscImagingError.processFailure(exitCode: exitStatus, stderr: errorOutput)
        }

        let tocText = try String(contentsOfFile: tocPath, encoding: .utf8)
        return try CdrdaoTocParser.parse(tocText)
    }

    // MARK: - Phase 2: read-cd (imaging)

    /// Image the disc (`cdrdao read-cd --read-raw`), returning an
    /// `AsyncStream` of `ImagingProgress`.
    ///
    /// The DRM gate runs FIRST: `DiscProtectionDetector.detect(markers:)` then
    /// `policy(for:)`. A `.refuse` result throws
    /// `DiscImagingError.protectedDisc` before any file is created, so a
    /// protected disc never yields a broken artifact and nothing is ever
    /// decrypted. If the `.toc` output already exists it throws
    /// `.outputExists` (cdrdao will not overwrite it).
    ///
    /// Progress is fed by (a) cdrdao's stderr through
    /// `CdrdaoProgressParser.parseCdrdaoProgress` (advisory track/error
    /// events, and the lead-in TOC table that sizes the bar) and (b) a task
    /// polling the `.bin` file size every 500 ms. The stream finishes when the
    /// process terminates.
    ///
    /// - Parameters:
    ///   - config: The read configuration.
    ///   - markers: Public protection markers for the DRM gate.
    /// - Returns: An async stream of progress updates.
    /// - Throws: `DiscImagingError.protectedDisc`, `.outputExists`,
    ///   `.alreadyRunning`, or `.noBinary`.
    ///   **Launches cdrdao — hardware-verified on the manual matrix.**
    public func startImaging(
        config: RawCDImagingConfig,
        markers: DiscProtectionMarkers
    ) throws -> AsyncStream<ImagingProgress> {
        // 1. DRM gate — FIRST, before any file is touched.
        let protection = DiscProtectionDetector.detect(markers: markers)
        if case .refuse(let reason) = DiscProtectionDetector.policy(for: protection) {
            throw DiscImagingError.protectedDisc(protection, reason: reason)
        }

        lock.lock()

        guard state == .idle || state == .completed || state == .cancelled else {
            lock.unlock()
            throw DiscImagingError.alreadyRunning
        }

        // 2. cdrdao refuses an existing toc-file — surface it as a typed error.
        if FileManager.default.fileExists(atPath: config.tocPath) {
            lock.unlock()
            throw DiscImagingError.outputExists(path: config.tocPath)
        }

        // Reset per-run state.
        stderrBuffer = ""
        errorCount = 0
        currentTrack = nil
        estimatedTotalSectors = 0
        pollingIncludesSubchannel = config.captureSubchannel
        pollingBinPath = config.binPath
        state = .running

        let arguments = RawCDReadPlanner.buildReadCdArguments(config: config)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cdrdaoPath)
        proc.arguments = arguments

        let stderrPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = stderrPipe
        proc.standardInput = FileHandle.nullDevice
        self.process = proc

        let stream = AsyncStream<ImagingProgress> { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            self.progressContinuation = continuation

            proc.terminationHandler = { [weak self] terminated in
                guard let self else { return }
                // Detach the stderr reader first: its closure retains the pipe,
                // and a read racing the process teardown is exactly the leak /
                // late-callback the FFmpeg controller guards against.
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                self.lock.lock()
                if self.state == .running || self.state == .paused {
                    self.state = .completed
                }
                let task = self.pollingTask
                self.pollingTask = nil
                self.lock.unlock()
                task?.cancel()
                _ = terminated
                continuation.finish()
            }

            // stderr: parse advisory events and cap the buffer.
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let self, let text = String(data: data, encoding: .utf8) else { return }
                self.ingestStderr(text)
            }

            // Size-polling task — the real source of byte-level progress.
            self.pollingTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard let self else { return }
                    guard let progress = self.currentProgressSnapshot() else { continue }
                    continuation.yield(progress)
                }
            }
        }

        do {
            try proc.run()
        } catch {
            state = .idle
            process = nil
            pollingTask?.cancel()
            pollingTask = nil
            lock.unlock()
            throw DiscImagingError.noBinary
        }

        lock.unlock()
        return stream
    }

    /// Cancel the running read: `SIGCONT` (in case it was paused) then
    /// `terminate()`, mirroring `FFmpegProcessController.stopEncoding()`. Leaves
    /// a partial `.bin` and a non-zero exit — verified on the hardware matrix.
    public func stopImaging() {
        lock.lock()
        defer { lock.unlock() }

        guard let proc = process else { return }
        state = .cancelled
        if proc.isRunning {
            kill(proc.processIdentifier, SIGCONT)
            proc.terminate()
        }
        pollingTask?.cancel()
        pollingTask = nil
        progressContinuation?.finish()
    }

    /// Whether a read is currently running.
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .running
    }

    /// The exit code of the finished process, if available.
    public var exitCode: Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard state == .completed || state == .cancelled else { return nil }
        guard let proc = process else { return nil }
        // `Process.terminationStatus` raises an ObjC exception if read while the
        // process is still running. After a cancel the state flips to
        // `.cancelled` before the OS has finished reaping the process, so guard
        // on the live `isRunning` rather than trusting the state alone.
        guard !proc.isRunning else { return nil }
        return proc.terminationStatus
    }

    /// The accumulated (capped) stderr output from cdrdao.
    public var errorOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrBuffer
    }

    // MARK: - Post-read pipeline

    /// Finalise a completed read into a verified BIN/CUE pair. Call this after
    /// the `startImaging` stream finishes with exit 0. This method performs
    /// only local file I/O — no device access.
    ///
    /// Steps:
    /// 1. when `captureSubchannel`, stream-split the 2448-byte raw capture into
    ///    a main-channel `.bin` and a `.sub` sidecar in bounded chunks
    ///    (multiples of 2448) via `SubchannelCodec.splitRawSectors`, never
    ///    loading the whole image into memory;
    /// 2. parse the read-cd `.toc` into a `DiscTableOfContents`, with
    ///    `hasSubchannel` set from the config;
    /// 3. write the `.cue` via the reused
    ///    `CueSheetWriter.write(toc:binaryFileName:)`;
    /// 4. verify: byte count vs `expectedBinByteCount` plus a streamed SHA-256,
    ///    producing an `ImageVerification`; a size mismatch throws
    ///    `DiscImagingError.verificationFailed`.
    ///
    /// - Parameter config: The read configuration whose paths and flags drive
    ///   finalisation.
    /// - Returns: The parsed TOC, the written `.cue` path, and the verification
    ///   result.
    /// - Throws: `DiscImagingError.verificationFailed`, `ImagingError`, or a
    ///   file I/O error.
    public func finalizeImage(
        config: RawCDImagingConfig
    ) async throws -> (toc: DiscTableOfContents, cuePath: String, verification: ImageVerification) {
        // 1. Split subchannel out of the raw capture, if any.
        if config.captureSubchannel {
            let subPath = URL(fileURLWithPath: config.binPath)
                .deletingPathExtension()
                .appendingPathExtension("sub")
                .path
            try Self.splitSubchannelSidecar(binPath: config.binPath, subPath: subPath)
        }

        // 2. Parse the read-cd .toc.
        let tocText = try String(contentsOfFile: config.tocPath, encoding: .utf8)
        var toc = try CdrdaoTocParser.parse(tocText)
        toc.hasSubchannel = config.captureSubchannel

        // 3. Write the .cue (reused serializer).
        let binURL = URL(fileURLWithPath: config.binPath)
        let names = BinCueImageWriter.pairedFileNames(baseName: config.binPath)
        let cuePath = binURL.deletingLastPathComponent().appendingPathComponent(names.cue).path
        let cueText = CueSheetWriter.write(toc: toc, binaryFileName: names.bin)
        try cueText.write(toFile: cuePath, atomically: true, encoding: .utf8)

        // 4. Verify. The final .bin is always main-channel (2352/sector),
        //    whether or not a subchannel capture was split out of it.
        let expected = RawCDReadPlanner.expectedBinByteCount(toc: toc, includeSubchannel: false)
        let actual = Self.fileSize(atPath: config.binPath)
        let sha = config.verifyAfterRead ? Self.sha256Hex(ofFileAtPath: config.binPath) : nil
        let verification = ImageVerification(
            byteCount: actual,
            expectedByteCount: expected,
            sha256Hex: sha
        )
        if config.verifyAfterRead, !verification.sizeMatches {
            throw DiscImagingError.verificationFailed(
                reason: "Image is \(actual) bytes but the TOC implies \(expected) bytes."
            )
        }

        return (toc, cuePath, verification)
    }

    // MARK: - Private: process lifecycle

    /// Launch cdrdao with the given arguments and await its exit status via the
    /// termination handler bridged to a continuation. Captures stderr for error
    /// reporting. No blocking wait.
    private func runToCompletion(arguments: [String]) async throws -> Int32 {
        // The locked setup lives in a synchronous helper because NSLock's
        // lock()/unlock() are unavailable from an async context under Swift 6.
        let (proc, stderrPipe) = try prepareProcess(arguments: arguments)

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self, let text = String(data: data, encoding: .utf8) else { return }
            self.ingestStderr(text)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            proc.terminationHandler = { [weak self] terminated in
                self?.markCompleted()
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: terminated.terminationStatus)
            }
            do {
                try proc.run()
            } catch {
                self.markLaunchFailed()
                continuation.resume(throwing: DiscImagingError.noBinary)
            }
        }
    }

    /// Synchronously validate state, reset buffers, and create the process.
    /// Extracted so its `NSLock` use stays out of an async context.
    private func prepareProcess(arguments: [String]) throws -> (Process, Pipe) {
        lock.lock()
        defer { lock.unlock() }
        guard state == .idle || state == .completed || state == .cancelled else {
            throw DiscImagingError.alreadyRunning
        }
        stderrBuffer = ""
        errorCount = 0
        state = .running

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cdrdaoPath)
        proc.arguments = arguments
        let stderrPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = stderrPipe
        proc.standardInput = FileHandle.nullDevice
        self.process = proc
        return (proc, stderrPipe)
    }

    /// Mark a running/paused read as completed. Lock-guarded, synchronous.
    private func markCompleted() {
        lock.lock()
        defer { lock.unlock() }
        if state == .running || state == .paused { state = .completed }
    }

    /// Roll back to idle after a failed launch. Lock-guarded, synchronous.
    private func markLaunchFailed() {
        lock.lock()
        defer { lock.unlock() }
        state = .idle
        process = nil
    }

    /// Append cdrdao stderr text to the capped buffer and fold in any advisory
    /// events (track, errors, lead-in TOC table sizing). Lock-guarded.
    private func ingestStderr(_ text: String) {
        lock.lock()
        stderrBuffer += text
        trimBufferIfNeeded(&stderrBuffer)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let event = CdrdaoProgressParser.parseCdrdaoProgress(line: String(line)) else { continue }
            switch event {
            case .tocTableRow(_, _, _, let lengthSectors):
                estimatedTotalSectors += max(0, lengthSectors)
            case .readingTrack(let number, _):
                currentTrack = number
            case .fatalError:
                errorCount += 1
            default:
                break
            }
        }
        lock.unlock()
    }

    /// Build an `ImagingProgress` snapshot from the current polled `.bin` size
    /// and the lock-guarded advisory state. Returns `nil` when there is nothing
    /// to report yet.
    private func currentProgressSnapshot() -> ImagingProgress? {
        lock.lock()
        let binPath = pollingBinPath
        let includesSub = pollingIncludesSubchannel
        let totalSectors = estimatedTotalSectors
        let errs = errorCount
        let track = currentTrack
        lock.unlock()

        guard !binPath.isEmpty else { return nil }
        let bytesOnDisk = Self.fileSize(atPath: binPath)
        let expected = RawCDReadPlanner.expectedBinByteCount(
            toc: DiscTableOfContents(leadOutSector: totalSectors),
            includeSubchannel: includesSub
        )
        return CdrdaoProgressParser.makeProgress(
            bytesOnDisk: bytesOnDisk,
            expectedTotalBytes: expected,
            currentTrack: track,
            errorCount: errs,
            bytesPerSecond: 0
        )
    }

    /// Trim a buffer back to `maxBufferBytes` by dropping oldest lines. Caller
    /// must hold `lock`. Mirrors `FFmpegProcessController.trimBufferIfNeeded`.
    private func trimBufferIfNeeded(_ buffer: inout String) {
        guard buffer.utf8.count > maxBufferBytes else { return }
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else {
            if let startIdx = buffer.index(
                buffer.endIndex, offsetBy: -maxBufferBytes, limitedBy: buffer.startIndex
            ) {
                buffer = String(buffer[startIdx...])
            }
            return
        }
        var trimmed = lines.dropFirst().joined(separator: "\n")
        while trimmed.utf8.count > maxBufferBytes {
            let remaining = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            guard remaining.count > 1 else { break }
            trimmed = remaining.dropFirst().joined(separator: "\n")
        }
        buffer = trimmed
    }

    // MARK: - Private: file helpers

    /// Stream-split a 2448-byte raw+subchannel datafile in place into a
    /// main-channel `.bin` and a `.sub` sidecar, in bounded chunks that are
    /// whole multiples of 2448 bytes so the whole image is never resident in
    /// memory. The main channel replaces the original datafile.
    private static func splitSubchannelSidecar(binPath: String, subPath: String) throws {
        let fm = FileManager.default
        let rawPath = binPath + ".rawcapture"
        // Move the raw capture aside so we can write the main channel back to
        // the canonical .bin path.
        if fm.fileExists(atPath: rawPath) { try fm.removeItem(atPath: rawPath) }
        try fm.moveItem(atPath: binPath, toPath: rawPath)
        fm.createFile(atPath: binPath, contents: nil)
        fm.createFile(atPath: subPath, contents: nil)

        let reader = try FileHandle(forReadingFrom: URL(fileURLWithPath: rawPath))
        defer { try? reader.close() }
        let mainWriter = try FileHandle(forWritingTo: URL(fileURLWithPath: binPath))
        defer { try? mainWriter.close() }
        let subWriter = try FileHandle(forWritingTo: URL(fileURLWithPath: subPath))
        defer { try? subWriter.close() }

        // 4096 sectors per chunk ≈ 10 MiB of raw+sub data.
        let chunkBytes = SubchannelCodec.rawSectorWithSubSize * 4096
        while true {
            let chunk = reader.readData(ofLength: chunkBytes)
            if chunk.isEmpty { break }
            let split = try SubchannelCodec.splitRawSectors(chunk, hasSubchannel: true)
            mainWriter.write(split.main)
            if let sub = split.subchannel { subWriter.write(sub) }
        }
        try? fm.removeItem(atPath: rawPath)
    }

    /// The size of the file at `path`, or 0 when it does not exist.
    private static func fileSize(atPath path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    /// Compute a lowercase hex SHA-256 of a file, streaming it so a large image
    /// is never fully resident. Uses CryptoKit where available (matching
    /// `DuplicateDetector`'s existing usage) and falls back to the
    /// `sha256sum`/`shasum` subprocess on platforms without it (per the #495
    /// Linux leg), reusing `DiscImager.buildChecksumArguments`. Returns `nil`
    /// on any failure.
    private static func sha256Hex(ofFileAtPath path: String) -> String? {
        #if canImport(CryptoKit)
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1_048_576) // 1 MiB
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        #else
        let (tool, arguments) = DiscImager.buildChecksumArguments(filePath: path, algorithm: "sha256")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        // `sha256sum`/`shasum` print "<hex>  <path>"; take the first field.
        return output.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init)
        #endif
    }
}
