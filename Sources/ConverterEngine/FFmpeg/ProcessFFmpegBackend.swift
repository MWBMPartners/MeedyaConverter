// ============================================================================
// MeedyaConverter — ProcessFFmpegBackend (Direct distribution)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - ProcessFFmpegBackend
// ---------------------------------------------------------------------------

/// The `FFmpegBackend` implementation that launches the bundled `ffmpeg`
/// and `ffprobe` binaries via `Foundation.Process`. This is the **Direct
/// distribution** path — the App Sandbox forbids `Process` launches, so
/// `FFmpegKitBackend` is used in App Store Lite builds instead.
///
/// Binary path resolution is delegated to `FFmpegBundleManager`, which
/// looks at (in order): the user-specified override from Settings, the
/// bundled `Contents/Helpers/ffmpeg` (where `scripts/bundle-ffmpeg.sh`
/// stages binaries at release time), legacy `Resources/Tools` fallback
/// paths, and finally Homebrew / MacPorts paths for developer-machine
/// builds.
///
/// Streaming-encode progress comes from `FFmpegProcessController`, which
/// parses ffmpeg's `-progress pipe:1` lines into `FFmpegProgressInfo`
/// values; this backend adapts that `AsyncStream` into the protocol's
/// `AsyncThrowingStream`. One-shot invocations launch a fresh `Process`
/// directly with stdout/stderr capture.
///
/// Thread-safety: the wrapped `FFmpegProcessController` is itself
/// `@unchecked Sendable`; this backend marks itself the same way and
/// serialises access to its `currentController` field via an `NSLock`.
public final class ProcessFFmpegBackend: FFmpegBackend, @unchecked Sendable {

    // MARK: - State

    /// Resolves the ffmpeg / ffprobe binary path at call time.
    private let bundleManager: FFmpegBundleManager

    /// Lock guarding `currentController`.
    private let controllerLock = NSLock()

    /// The streaming-encode controller in flight, if any. Held so
    /// `cancelCurrent()` can stop it.
    private var currentController: FFmpegProcessController?

    // MARK: - Init

    /// - Parameter bundleManager: Custom binary resolver. The default
    ///   instance uses no user-overrides and walks the standard search
    ///   path (bundled helpers → Homebrew → MacPorts → system).
    public init(bundleManager: FFmpegBundleManager = FFmpegBundleManager()) {
        self.bundleManager = bundleManager
    }

    // MARK: - Streaming encode

    public func runEncode(
        arguments: [String],
        sourceDuration: TimeInterval?
    ) -> AsyncThrowingStream<FFmpegProgressInfo, Error> {
        AsyncThrowingStream { continuation in
            // Resolve the ffmpeg binary. A missing binary terminates the
            // stream immediately rather than letting the consumer hang.
            let binaryPath: String
            do {
                binaryPath = try bundleManager.locateFFmpeg().path
            } catch {
                continuation.finish(throwing: FFmpegBackendError.noBinary)
                return
            }

            // Refuse a second concurrent invocation. The Process backend
            // is single-cursor by design — the host queue is supposed
            // to serialise jobs through one backend instance per worker.
            controllerLock.lock()
            if currentController != nil {
                controllerLock.unlock()
                continuation.finish(throwing: FFmpegBackendError.alreadyRunning)
                return
            }
            let controller = FFmpegProcessController(binaryPath: binaryPath)
            controller.sourceDuration = sourceDuration
            self.currentController = controller
            controllerLock.unlock()

            // Drive the controller in a detached task so the stream can
            // yield values as they arrive. The controller's
            // `startEncoding` throws synchronously if the spawn fails;
            // catch and route that into the throwing stream.
            let task = Task {
                let progressStream: AsyncStream<FFmpegProgressInfo>
                do {
                    progressStream = try controller.startEncoding(arguments: arguments)
                } catch let err as FFmpegProcessError {
                    continuation.finish(throwing: Self.translate(err))
                    self.clearCurrentController()
                    return
                } catch {
                    continuation.finish(throwing: error)
                    self.clearCurrentController()
                    return
                }

                for await info in progressStream {
                    continuation.yield(info)
                }

                // The stream ended. Consult the controller's exit-code
                // field for the source of truth on success vs failure.
                // `exitCode == 0` is the only success path; anything
                // else (including `nil` because the controller was
                // killed by `stopEncoding`) is an error.
                switch controller.exitCode {
                case 0:
                    continuation.finish()
                case let code?:
                    continuation.finish(throwing: FFmpegBackendError.nonZeroExit(
                        exitCode: code,
                        stderr: controller.errorOutput
                    ))
                case nil:
                    // No exit code means the controller was stopped before
                    // ffmpeg reported its status — treat as cancellation.
                    continuation.finish(throwing: FFmpegBackendError.cancelled)
                }

                self.clearCurrentController()
            }

            // Tear down ONLY on real consumer cancellation.
            //
            // `onTermination` fires for BOTH `.finished` and `.cancelled`.
            // On `.finished` the encode already completed and the task
            // above has run (or is running) `clearCurrentController()` —
            // calling `cancelCurrent()` here would re-read
            // `currentController` at some later moment and could SIGTERM a
            // *different* encode that a reused backend instance has since
            // started (the classic use-after-handoff race). So we act
            // only on `.cancelled`, and we stop THIS encode's specific
            // `controller` directly rather than whatever is "current" now.
            continuation.onTermination = { @Sendable reason in
                guard case .cancelled = reason else { return }
                task.cancel()
                controller.stopEncoding()
            }
        }
    }

    // MARK: - One-shot ffmpeg / ffprobe

    public func runFFmpegOneShot(
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> FFmpegOneShotResult {
        let info = try bundleManager.locateFFmpeg()
        return try await runOneShot(binaryPath: info.path, arguments: arguments, timeout: timeout)
    }

    public func runFFprobe(
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> FFmpegOneShotResult {
        let info = try bundleManager.locateFFprobe()
        return try await runOneShot(binaryPath: info.path, arguments: arguments, timeout: timeout)
    }

    /// Shared one-shot runner used by both `runFFmpegOneShot` and
    /// `runFFprobe`. Launches the binary, collects stdout/stderr fully,
    /// and returns the captured `FFmpegOneShotResult`. The `timeout` is
    /// enforced by a child `Task` that terminates the process if it
    /// exceeds the cap; pass `nil` to disable.
    private func runOneShot(
        binaryPath: String,
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> FFmpegOneShotResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<FFmpegOneShotResult, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBox = OutputBox()
            let stderrBox = OutputBox()
            let resumeGuard = ResumeOnce()

            // Full, race-free capture (F-011 review, finding #1). Read
            // each pipe to EOF on its OWN background queue via
            // `readDataToEndOfFile()`, which returns every byte up to the
            // write-end close. This fixes the previous
            // readabilityHandler-then-nil approach, which cancelled the
            // pipe's dispatch source in `terminationHandler` and could
            // drop a final data burst that the handler had not yet
            // dequeued (intermittent truncated stdout / JSON on larger
            // outputs). Two separate queues avoid the classic
            // Process pipe-buffer deadlock (a full stderr blocking
            // stdout writes, or vice-versa).
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let fh = stdoutPipe.fileHandleForReading
                stdoutBox.append(fh.readDataToEndOfFile())
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let fh = stderrPipe.fileHandleForReading
                stderrBox.append(fh.readDataToEndOfFile())
                group.leave()
            }

            process.terminationHandler = { proc in
                let exitCode = proc.terminationStatus
                // Resume only AFTER both drainers have reached EOF, so we
                // never read a partially-filled buffer.
                group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                    let stdout = stdoutBox.string()
                    let stderr = stderrBox.string()
                    resumeGuard.run {
                        if exitCode == 0 {
                            continuation.resume(returning: FFmpegOneShotResult(
                                exitCode: exitCode,
                                stdout: stdout,
                                stderr: stderr
                            ))
                        } else {
                            continuation.resume(throwing: FFmpegBackendError.nonZeroExit(
                                exitCode: exitCode,
                                stderr: stderr
                            ))
                        }
                    }
                }
            }

            // Optional timeout enforcement.
            if let timeout, timeout > 0 {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if process.isRunning {
                        process.terminate()
                    }
                }
            }

            do {
                try process.run()
            } catch {
                // Spawn failed: the terminationHandler will never fire, so
                // resume here. The idle drainer tasks unblock (EOF) when
                // the local Pipes deallocate after this closure returns.
                resumeGuard.run { continuation.resume(throwing: error) }
            }
        }
    }

    // MARK: - Cancel

    public func cancelCurrent() async {
        // Use withLock so the lock/unlock pair is async-safe — bare
        // `NSLock.lock()` / `.unlock()` calls are unavailable from
        // async contexts under Swift 6 strict concurrency.
        let controller = controllerLock.withLock { currentController }
        controller?.stopEncoding()
    }

    // MARK: - Helpers

    /// Clears `currentController` under the lock. Called from the
    /// encode task's completion path so a subsequent invocation can
    /// proceed.
    private func clearCurrentController() {
        controllerLock.lock()
        currentController = nil
        controllerLock.unlock()
    }

    /// Bridges `FFmpegProcessError` (from `FFmpegProcessController`)
    /// to the protocol's `FFmpegBackendError` cases.
    private static func translate(_ error: FFmpegProcessError) -> FFmpegBackendError {
        switch error {
        case .processFailure(let code, let stderr):
            return .nonZeroExit(exitCode: code, stderr: stderr)
        case .cancelled:
            return .cancelled
        case .timeout:
            return .timeout
        case .noBinary:
            return .noBinary
        case .alreadyRunning:
            return .alreadyRunning
        }
    }
}

// MARK: - OutputBox

/// Tiny thread-safe `Data` accumulator used by `runOneShot`'s
/// stdout/stderr capture. The `Pipe` readability handler may fire on
/// any background queue; the `NSLock` ensures appends are serialised.
///
/// No buffer cap here because one-shot invocations are short-lived
/// (sub-minute) and capped via `runOneShot`'s `timeout`. The streaming
/// encode path uses `FFmpegProcessController`'s own trimming logic
/// which IS capped.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
    }

    func string() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
}

// MARK: - ResumeOnce

/// Guarantees a `CheckedContinuation` is resumed exactly once, even
/// though the resume can be reached from two mutually-exclusive-in-
/// principle paths (the drain-then-notify completion, and the
/// `process.run()` failure catch). Resuming a continuation twice is a
/// hard crash, so the guard is cheap insurance around a concurrency
/// boundary.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        body()
    }
}
