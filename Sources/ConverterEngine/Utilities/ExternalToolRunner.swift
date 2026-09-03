// ============================================================================
// MeedyaConverter — ExternalToolRunner
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// A minimal "run this binary with these arguments to completion" seam for
// tools that print no machine-readable progress. potrace and vtracer emit
// nothing usable on stdout/stderr while working — unlike `ffmpeg`/`cdrdao`,
// which `FFmpegProcessController`/`DiscImagingController` drive through an
// `AsyncStream` of parsed progress events, there is no stream to parse here,
// only a final exit status and whatever stderr the tool wrote on failure.
//
// `ExternalToolRunner` is the production implementation; `ExternalToolRunning`
// is the seam `RasterVectorExecutor`/`ProResVectorExecutor` are tested
// against with a mock (see `VectorExecutorTests.MockExternalToolRunner`) — no
// CI job ever runs a real potrace/vtracer process, so this file's behaviour
// against a REAL subprocess is verified only on the manual matrix (macOS
// Direct DMG, both arches).
//
// Process lifecycle mirrors `DiscImagingController.runToCompletion`/
// `prepareProcess`: `NSLock` use is confined to synchronous helpers (Swift 6
// forbids `lock()`/`unlock()` in an async context), the process is awaited
// through its `terminationHandler` bridged to a continuation (never a
// blocking `waitUntilExit` on a cooperative thread), and cancellation sends
// `SIGCONT` (in case the process was suspended) then `terminate()` — same as
// `DiscImagingController.stopImaging()`. The addition here is
// `withTaskCancellationHandler`, since this seam has no long-lived controller
// object with its own public `stop()` — the caller's `Task` cancellation IS
// the cancel signal.
// ============================================================================

import Foundation

// MARK: - ExternalToolResult

/// The outcome of running an external tool to completion.
public struct ExternalToolResult: Sendable {
    /// The process's exit status.
    public let exitCode: Int32

    /// Captured stderr (capped — see `ProcessBox.maxBufferBytes`).
    public let stderr: String

    public init(exitCode: Int32, stderr: String) {
        self.exitCode = exitCode
        self.stderr = stderr
    }
}

// MARK: - ExternalToolError

public enum ExternalToolError: LocalizedError, Sendable {
    /// `Process.run()` threw — the binary could not be launched at all
    /// (missing, not executable, or a sandbox/permission denial).
    case launchFailed(binaryPath: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let binaryPath, let reason):
            return "Failed to launch '\(binaryPath)': \(reason)"
        }
    }
}

// MARK: - ExternalToolRunning

/// Seam: "run this binary with these arguments to completion". The tracers
/// print no machine-readable progress, so there is no stream — just an exit
/// status and captured stderr. `ExternalToolRunner` is production; tests
/// inject a mock.
public protocol ExternalToolRunning: Sendable {
    func run(binaryPath: String, arguments: [String]) async throws -> ExternalToolResult
}

// MARK: - ExternalToolRunner

public final class ExternalToolRunner: ExternalToolRunning, Sendable {
    public init() {}

    public func run(binaryPath: String, arguments: [String]) async throws -> ExternalToolResult {
        let box = ProcessBox()
        let (proc, stderrPipe) = box.prepare(binaryPath: binaryPath, arguments: arguments)

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            box.appendStderr(text)
        }

        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                proc.terminationHandler = { terminated in
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: terminated.terminationStatus)
                }
                do {
                    try proc.run()
                } catch {
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ExternalToolError.launchFailed(
                        binaryPath: binaryPath, reason: error.localizedDescription))
                }
            }
        } onCancel: {
            box.terminate()
        }

        // The continuation may have resumed with a "successful" exit right as
        // cancellation raced in (the process finished naturally the instant
        // `onCancel` fired); a cancelled Task must still surface as
        // cancelled, never as a false success.
        if Task.isCancelled { throw CancellationError() }
        return ExternalToolResult(exitCode: exitCode, stderr: box.stderrText)
    }
}

// MARK: - ProcessBox

/// Owns the live `Process` and its captured stderr buffer. `NSLock` use is
/// confined to these synchronous methods — never called from an async
/// context — mirroring `DiscImagingController.prepareProcess`.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stderrBuffer = ""
    private let maxBufferBytes = 10 * 1024 * 1024

    /// Build the `Process` and its stderr pipe. Standard output and input
    /// are the null device — potrace/vtracer need neither, and leaving
    /// stdout unconnected risks blocking the tool if it ever writes there.
    func prepare(binaryPath: String, arguments: [String]) -> (Process, Pipe) {
        lock.lock()
        defer { lock.unlock() }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = arguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        self.process = proc
        return (proc, stderrPipe)
    }

    /// Append captured stderr text, trimming to `maxBufferBytes`.
    func appendStderr(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        stderrBuffer += text
        trimBufferIfNeeded(&stderrBuffer)
    }

    /// The accumulated (capped) stderr output.
    var stderrText: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrBuffer
    }

    /// Cancel the running process: `SIGCONT` (in case it was suspended) then
    /// `terminate()`, mirroring `DiscImagingController.stopImaging()`.
    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        guard let proc = process, proc.isRunning else { return }
        kill(proc.processIdentifier, SIGCONT)
        proc.terminate()
    }

    /// Trim a buffer back to `maxBufferBytes` by dropping oldest lines.
    /// Copied from `DiscImagingController`/`FFmpegProcessController` — no
    /// shared base type exists to hang one common helper off.
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
}
