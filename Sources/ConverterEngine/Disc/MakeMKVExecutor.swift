// ============================================================================
// MeedyaConverter — MakeMKVExecutor (Issue #503, slice 3)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// FILE OVERVIEW
// -------------
// Slice 3 of the optional, opt-in MakeMKV backend (#503): the EXECUTOR that
// actually runs `makemkvcon` — `info` (enumerate a disc) and `mkv` (rip titles,
// streaming live progress) — behind the slice-2 consent gate.
//
// CONSENT IS REQUIRED AT THE BOUNDARY: `MakeMKVExecutor` cannot be constructed
// without a `MakeMKVConsent` (un-constructable except via slice 2) AND a resolved
// binary path. The executor reads NO `UserDefaults` (that is the store's job); the
// call site resolves consent + path from slice 2 and hands them in. It changes NO
// policy — it only calls `MakeMKVBackend.build*Arguments` + `parse*`, never the
// copy-protection refuse-gate (#492); MakeMKV stays the separate, user-gated path.
//
// TESTABILITY: the subprocess is behind the injectable `MakeMKVLineStreaming` seam,
// so the orchestration (arg building, line parsing, progress/exit mapping,
// cancellation, consent) is unit-tested with a mock that feeds canned robot-mode
// lines — NO real subprocess in CI. The production `MakeMKVProcessRunner` mirrors
// `ExternalToolRunner`/`DiscImagingController` (Pipe.readabilityHandler line-buffer
// under NSLock, terminationHandler→continuation, SIGCONT+terminate on cancel) and,
// like them, is exercised against a real process only on the manual hardware matrix.
//
// MakeMKV's robot output (`-r`, `--progress=-same`) — messages AND progress AND
// diagnostics — is on STDOUT, so this reads stdout (unlike ExternalToolRunner, which
// captures stderr). Failure snippets come from the last human-readable `MSG:` text.
// ============================================================================

import Foundation

// MARK: - Errors

/// Executor-level errors, modelled on `DiscImagingError` / `ExternalToolError`.
public enum MakeMKVExecutorError: LocalizedError, Sendable, Equatable {
    /// No consent object was supplied (only reachable via the throwing factory;
    /// the designated init requires a non-optional `MakeMKVConsent`).
    case notConsented
    /// `Process.run()` threw — makemkvcon could not be launched.
    case launchFailed(binaryPath: String, reason: String)
    /// makemkvcon exited non-zero. `snippet` is the last human-readable `MSG:`
    /// text seen on stdout (MakeMKV reports errors as MSG records, not on stderr).
    case processFailure(exitCode: Int32, snippet: String)

    public var errorDescription: String? {
        switch self {
        case .notConsented:
            return "MakeMKV was invoked without user consent."
        case .launchFailed(let path, let reason):
            return "Failed to launch makemkvcon at '\(path)': \(reason)"
        case .processFailure(let code, let snippet):
            return "makemkvcon exited with code \(code): \(snippet.prefix(500))"
        }
    }
}

// MARK: - Rip events

/// One typed event from a streaming `rip`, mapping robot-mode records onto
/// slice-1 value models. Emission order follows stdout order.
public enum MakeMKVRipEvent: Sendable, Equatable {
    /// A `PRGC:`/`PRGT:`/`PRGV:` record.
    case progress(MakeMKVProgressEvent)
    /// A `MSG:` record.
    case message(MakeMKVMessage)
}

// MARK: - Line-streaming seam

/// Seam: "launch this binary, stream its STDOUT lines, complete with an exit
/// code." Distinct from `ExternalToolRunning` because MakeMKV's machine-readable
/// output (including errors) is on STDOUT and must be delivered line by line as it
/// arrives (rip streams progress), not buffered to the end.
///
/// `onStdoutLine` is called once per complete stdout line (newline stripped; any
/// trailing "\r" is left for `MakeMKVBackend`'s parsers to remove). It is
/// `@Sendable` because the production impl calls it from a `Pipe.readabilityHandler`
/// running on an arbitrary reader thread.
public protocol MakeMKVLineStreaming: Sendable {
    func run(
        binaryPath: String,
        arguments: [String],
        onStdoutLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32
}

// MARK: - Line assembler (pure, testable)

/// Incrementally reassembles stdout lines from raw pipe chunks. Pure and
/// launch-free, so it is unit-tested directly with no `Process`. Splitting is on
/// the byte `0x0A` (never by decoding whole chunks), because a UTF-8 multibyte
/// character (e.g. a disc name) can straddle two pipe reads and `0x0A` never
/// occurs inside a multibyte UTF-8 sequence. Not thread-safe by itself — the
/// production box owns one instance and guards it with a lock.
public struct MakeMKVLineAssembler: Sendable {
    private var pending: [UInt8] = []

    public init() {}

    /// Append newly read bytes; return every complete line (without the "\n").
    /// A trailing partial line is retained across calls.
    public mutating func take(_ data: Data) -> [String] {
        pending.append(contentsOf: data)
        var lines: [String] = []
        var start = 0
        let newline = UInt8(ascii: "\n")
        var index = 0
        while index < pending.count {
            if pending[index] == newline {
                lines.append(String(decoding: pending[start..<index], as: UTF8.self))
                start = index + 1
            }
            index += 1
        }
        if start > 0 { pending.removeFirst(start) }
        return lines
    }

    /// The final unterminated line at EOF, if any (nil when empty).
    public mutating func flush() -> String? {
        guard !pending.isEmpty else { return nil }
        let remainder = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return remainder.isEmpty ? nil : remainder
    }
}

// MARK: - MakeMKVExecutor

/// Runs `makemkvcon` behind the slice-2 consent gate. Stateless value type: each
/// call spins up a fresh run through the injected `MakeMKVLineStreaming`.
public struct MakeMKVExecutor: Sendable {

    private let consent: MakeMKVConsent
    private let binaryPath: String
    private let runner: any MakeMKVLineStreaming

    /// The user's acknowledgement text, surfaced in logs so it is always visible
    /// WHY the MakeMKV path was permitted.
    public var acknowledgement: String { consent.acknowledgement }

    /// Designated initialiser — the compile-time consent gate. A caller cannot
    /// construct the executor without a `MakeMKVConsent` (un-constructable except
    /// via the slice-2 store) AND a resolved binary path. Reads no `UserDefaults`.
    public init(
        consent: MakeMKVConsent,
        binaryPath: String,
        runner: any MakeMKVLineStreaming = MakeMKVProcessRunner()
    ) {
        self.consent = consent
        self.binaryPath = binaryPath
        self.runner = runner
    }

    /// Convenience factory mapping slice-2 output into the executor's error space;
    /// this is where the runtime `.notConsented` case lives.
    public static func make(
        readiness: MakeMKVReadiness,
        consent: MakeMKVConsent?,
        runner: any MakeMKVLineStreaming = MakeMKVProcessRunner()
    ) throws -> MakeMKVExecutor {
        guard let consent else { throw MakeMKVExecutorError.notConsented }
        switch readiness {
        case .ready(let path):
            return MakeMKVExecutor(consent: consent, binaryPath: path, runner: runner)
        case .notEnabled:
            throw MakeMKVExecutorError.notConsented
        case .notInstalled(let reason):
            throw MakeMKVExecutorError.launchFailed(binaryPath: "makemkvcon", reason: reason)
        }
    }

    // MARK: info — run to completion, capture stdout, parse the whole transcript

    /// Enumerate a disc's titles/streams. Runs `makemkvcon info <source>`, buffers
    /// its robot output, and parses it. Throws `.processFailure` on a non-zero exit
    /// and rethrows `CancellationError` when cancelled.
    public func info(
        source: MakeMKVSource,
        noScan: Bool = false,
        minLengthSeconds: Int? = nil,
        cacheSizeMB: Int? = nil
    ) async throws -> MakeMKVDiscInfo {
        let arguments = MakeMKVBackend.buildInfoArguments(
            source: source,
            noScan: noScan,
            minLengthSeconds: minLengthSeconds,
            cacheSizeMB: cacheSizeMB
        )
        let collector = InfoCollector()
        let exitCode = try await runner.run(
            binaryPath: binaryPath,
            arguments: arguments
        ) { line in
            collector.append(line)
        }
        if Task.isCancelled { throw CancellationError() }
        if exitCode != 0 {
            throw MakeMKVExecutorError.processFailure(exitCode: exitCode, snippet: collector.snippet())
        }
        return MakeMKVBackend.parseInfo(collector.joined())
    }

    // MARK: rip — stream typed progress/message events

    /// Decode selected titles to `.mkv` in `destinationDirectory`, streaming
    /// progress/message events as they arrive. The stream finishes normally on a
    /// zero exit, or finishes throwing `.processFailure` / `.launchFailed` /
    /// `CancellationError`. Breaking the `for await` loop cancels the run.
    public func rip(
        source: MakeMKVSource,
        titles: MakeMKVTitleSelector,
        destinationDirectory: String,
        minLengthSeconds: Int? = nil,
        cacheSizeMB: Int? = nil
    ) -> AsyncThrowingStream<MakeMKVRipEvent, Error> {
        let arguments = MakeMKVBackend.buildRipArguments(
            source: source,
            titles: titles,
            destinationDirectory: destinationDirectory,
            minLengthSeconds: minLengthSeconds,
            cacheSizeMB: cacheSizeMB
        )
        let binaryPath = self.binaryPath
        let runner = self.runner

        return AsyncThrowingStream { continuation in
            let lastMessage = LastMessageBox()
            let task = Task {
                do {
                    let exitCode = try await runner.run(
                        binaryPath: binaryPath,
                        arguments: arguments
                    ) { line in
                        if let event = MakeMKVBackend.parseProgressLine(line) {
                            continuation.yield(.progress(event))
                        } else if let message = MakeMKVBackend.parseMessageLine(line) {
                            lastMessage.record(message.text)
                            continuation.yield(.message(message))
                        }
                        // unknown/malformed lines are silently ignored
                    }
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                    } else if exitCode != 0 {
                        continuation.finish(throwing: MakeMKVExecutorError.processFailure(
                            exitCode: exitCode, snippet: lastMessage.text))
                    } else {
                        continuation.finish()
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

// MARK: - Private lock boxes (keep @Sendable callbacks off mutable captures)

/// Records the most recent `MSG:` text for a failure snippet. `NSLock` used only
/// in synchronous methods, mirroring `ExternalToolRunner.ProcessBox`.
private final class LastMessageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ""
    func record(_ text: String) { lock.lock(); last = text; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return last }
}

/// Collects `info` stdout lines for one-shot parsing at completion.
private final class InfoCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }

    func joined() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    /// The last `MSG:` text among collected lines, else the last few raw lines.
    func snippet() -> String {
        lock.lock(); let copy = lines; lock.unlock()
        for line in copy.reversed() {
            if let message = MakeMKVBackend.parseMessageLine(line) { return message.text }
        }
        return copy.suffix(5).joined(separator: "\n")
    }
}

// MARK: - Production runner

/// Production `MakeMKVLineStreaming`: launches a real `makemkvcon`, streams stdout
/// lines, and completes with the exit code. Stateless (like `ExternalToolRunner`),
/// so plain `Sendable`; the live process + line buffer live in `MakeMKVProcessBox`.
/// Verified against a real subprocess only on the manual hardware matrix.
public final class MakeMKVProcessRunner: MakeMKVLineStreaming, Sendable {
    public init() {}

    public func run(
        binaryPath: String,
        arguments: [String],
        onStdoutLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let box = MakeMKVProcessBox()
        let (proc, stdoutPipe) = box.prepare(binaryPath: binaryPath, arguments: arguments)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in box.appendStdoutAndExtractLines(data) {
                onStdoutLine(line)
            }
        }

        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                proc.terminationHandler = { terminated in
                    // Detach the reader FIRST, then flush the final partial line,
                    // then resume — mirrors DiscImagingController's teardown order.
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    if let remainder = box.flushStdoutRemainder() {
                        onStdoutLine(remainder)
                    }
                    continuation.resume(returning: terminated.terminationStatus)
                }
                do {
                    try proc.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: MakeMKVExecutorError.launchFailed(
                        binaryPath: binaryPath, reason: error.localizedDescription))
                }
            }
        } onCancel: {
            box.terminate()
        }

        // A cancelled Task must surface as cancelled even if the process finished
        // naturally the instant cancellation raced in — as in ExternalToolRunner.
        if Task.isCancelled { throw CancellationError() }
        return exitCode
    }
}

// MARK: - Process box

/// Owns the live `Process` and the line assembler. `NSLock` use is confined to
/// these synchronous methods — never an async context — mirroring
/// `ExternalToolRunner.ProcessBox` / `DiscImagingController.prepareProcess`.
private final class MakeMKVProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var assembler = MakeMKVLineAssembler()

    /// Build the `Process` reading robot output from STDOUT (unlike
    /// `ExternalToolRunner`, which reads stderr). stderr/stdin are the null device.
    func prepare(binaryPath: String, arguments: [String]) -> (Process, Pipe) {
        lock.lock()
        defer { lock.unlock() }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = arguments
        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        self.process = proc
        return (proc, stdoutPipe)
    }

    func appendStdoutAndExtractLines(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return assembler.take(data)
    }

    func flushStdoutRemainder() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return assembler.flush()
    }

    /// Cancel the process: `SIGCONT` (in case suspended) then `terminate()`.
    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        guard let proc = process, proc.isRunning else { return }
        kill(proc.processIdentifier, SIGCONT)
        proc.terminate()
    }
}
