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
// lines (MakeMKVExecutorTests). That mock sits ABOVE the production runner, so it
// cannot see any fault in the runner's own pipe and process handling. The runner is
// therefore tested separately (MakeMKVProcessRunnerTests): its two moving parts,
// `MakeMKVLaunchGate` and `MakeMKVOutputLatch`, on their own against a real `Pipe`
// with no subprocess, and `MakeMKVProcessRunner` as a whole against `/bin/sh`.
// How it behaves with a real `makemkvcon` and a real disc is still checked only on
// the manual hardware matrix.
//
// WHY THE RUNNER NO LONGER COPIES ExternalToolRunner: this runner was first written
// to mirror `ExternalToolRunner` / `DiscImagingController` (a readabilityHandler line
// buffer, the process's terminationHandler resuming the caller, SIGCONT + terminate on
// cancel). That pattern has two faults. Both were raised by the Codex round-1 review
// (findings F4 and F5, issue #503) and both were proven by running the code:
//   1. A cancel that arrived before the launch was lost. The cancel handler saw "not
//      running yet" and did nothing, and the process was then launched anyway and ran
//      to the end. For `rip`, that meant the screen said "cancelled" while MakeMKV
//      carried on writing files.
//   2. The end of the output was dropped. At exit, the old code unhooked the pipe
//      reader and finished straight away, so anything still sitting in the pipe was
//      never read. In the review's reproduction (a pause, then a 41 KB burst of
//      MakeMKV-style title lines, then exit), 241 of 400 runs lost about 693 of
//      1,161 lines, so a scan that reported success silently had titles missing.
//      A rerun on the maintainer's Mac (`cat` of a 41 KB file) lost lines in 66 of
//      300 runs; the fixed runner lost none in either.
// The fixes are described on `MakeMKVLaunchGate` and `MakeMKVOutputLatch` below.
// `ExternalToolRunner` still has BOTH faults, and `DiscImagingController` unhooks its
// stderr reader at exit in the same way; they are left for a separate issue rather
// than changed here.
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
        // A cheap early exit if the cancel came before we even started. This is NOT
        // the real protection: a cancel can still arrive after this line and before
        // the process is launched, and it is the production runner's launch gate
        // (`MakeMKVLaunchGate`) that covers that window. This check only means a
        // custom runner that ignores cancellation is not even called.
        try Task.checkCancellation()
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
                    // Early exit if the consumer already went away before this task
                    // got going. As in `info`, the runner's launch gate is the real
                    // protection; this only spares calling the runner at all.
                    try Task.checkCancellation()
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
            // When the consumer stops listening (breaks the loop, or its own task is
            // cancelled), cancel the run. With the production runner this either
            // stops the launch from happening at all or sends makemkvcon SIGTERM.
            // WHAT THIS CANNOT DO: `onTermination` cannot wait, so the consumer is
            // told the stream has ended BEFORE makemkvcon has actually exited. How
            // quickly makemkvcon honours SIGTERM, and whether it leaves a partial
            // .mkv behind, is unverified (hardware matrix).
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

/// Production `MakeMKVLineStreaming`: launches a real `makemkvcon`, streams its
/// stdout lines, and completes with the exit code.
///
/// Stateless, so plain `Sendable`. Everything that belongs to one run lives in a
/// fresh `MakeMKVProcessBox` (the process, its pipe and the launch gate) and a fresh
/// `MakeMKVOutputLatch` (the line reader and the "finish exactly once" logic).
///
/// How one run fits together:
/// 1. The pipe reader and the termination handler are installed BEFORE launch.
///    Foundation calls the termination handler on its own thread as soon as the
///    process exits, which can be before the launching code has moved on.
/// 2. The launch goes through the gate, so if a cancel has already been asked for,
///    the process is never started.
/// 3. Only the latch resumes the caller, and only once: when the process has exited
///    AND every byte of its output has been read, or straight away if the process
///    never started.
///
/// Tested against `/bin/sh` in MakeMKVProcessRunnerTests. Against a real
/// `makemkvcon` it is checked only on the manual hardware matrix.
public final class MakeMKVProcessRunner: MakeMKVLineStreaming, Sendable {

    /// How long to keep waiting for the end of the output after makemkvcon has
    /// exited (see `MakeMKVOutputLatch`). Always the 5 s default in the app.
    let eofGracePeriod: TimeInterval

    public init() {
        self.eofGracePeriod = MakeMKVOutputLatch.defaultEOFGracePeriod
    }

    /// For tests only: a shorter time limit, so the "a child process kept stdout
    /// open" case can be run against a real process without a 5 s wait.
    init(eofGracePeriod: TimeInterval) {
        self.eofGracePeriod = eofGracePeriod
    }

    public func run(
        binaryPath: String,
        arguments: [String],
        onStdoutLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let box = MakeMKVProcessBox(binaryPath: binaryPath, arguments: arguments)
        let eofGracePeriod = self.eofGracePeriod

        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                // The latch is the ONLY thing that resumes `continuation`, and it does
                // so exactly once, however the run ends. Nothing else here touches it.
                let latch = MakeMKVOutputLatch(
                    eofGracePeriod: eofGracePeriod,
                    onLine: onStdoutLine
                ) { result in
                    continuation.resume(with: result)
                }
                latch.startReading(box.stdoutPipe.fileHandleForReading)

                // This handler only records the exit status. It must NOT unhook the
                // reader or finish the run itself: when the process exits, the pipe
                // can still hold output the reader has not reached yet (that was
                // fault F5). The latch finishes once the reader has also reached the
                // end of the output.
                box.process.terminationHandler = { terminated in
                    latch.processDidExit(status: terminated.terminationStatus)
                }

                do {
                    let launched = try box.launchUnlessCancelled()
                    if !launched {
                        // Cancelled before launch. With no process there is no
                        // termination handler call and no end-of-file (this process
                        // still holds the pipe's write end), so finish right now.
                        latch.finishWithoutProcess(throwing: CancellationError())
                    }
                } catch {
                    // Launch failed. The same applies: nothing else would finish it.
                    latch.finishWithoutProcess(throwing: MakeMKVExecutorError.launchFailed(
                        binaryPath: binaryPath, reason: error.localizedDescription))
                }
            }
        } onCancel: {
            // Can run on any thread. If the task was ALREADY cancelled when this run
            // began, Swift calls this straight away, before the block above has
            // launched anything. The gate records the cancel either way, so the
            // launch above is refused, or the running process is stopped.
            box.terminate()
        }

        // A cancelled Task must surface as cancelled even if the process finished
        // naturally the instant cancellation raced in.
        if Task.isCancelled { throw CancellationError() }
        return exitCode
    }
}

// MARK: - Launch gate (fault F4)

/// Makes "has a cancel been asked for?" and "start the process" one step that
/// cannot be split, so a cancel is never lost, however it is timed.
///
/// THE FAULT IT FIXES (Codex round 1, finding F4): the old runner's cancel handler
/// only stopped the process if it was already running. A cancel that came before
/// the launch found nothing running, recorded nothing, and the process was then
/// launched anyway and ran to the end. That includes the ordinary case of a task
/// that is already cancelled when the run begins, because Swift then calls the
/// cancel handler immediately, before anything has launched. Proven: an
/// already-cancelled task ran `/bin/sh -c 'echo launched; sleep 2; echo finished'`
/// to the end (both lines, 2.2 s) and only then threw CancellationError.
///
/// THE RULES:
/// - `requestCancel` ALWAYS records the cancel, whether or not anything has launched,
///   and stops the process only if one has launched.
/// - `launchUnlessCancelled` holds the lock across both the check and the launch. A
///   cancel from another thread therefore lands either wholly before (the launch is
///   refused) or wholly after (the process starts, then is stopped at once). It
///   cannot slip in between the check and the launch.
///
/// WHY HOLDING A LOCK ACROSS `Process.run()` IS SAFE: `run()` does not call the
/// termination handler or the pipe reader on the launching thread, and does not wait
/// for them. Foundation calls them later, on its own threads. Checked on this
/// project's Mac: 0 of 300 termination-handler calls ran on the launching thread, and
/// holding a lock across `run()` that the termination handler also wanted did not
/// deadlock in 100 tries. On top of that, neither handler ever takes THIS lock, so
/// they could not deadlock against it even if Foundation behaved differently.
///
/// WHAT IT CANNOT DO: if the cancel arrives while `Process.run()` is under way, the
/// process does start, and is sent SIGTERM straight after; a launch cannot be undone.
/// Nor can the gate make the process act on SIGTERM.
///
/// `internal`, not private, so MakeMKVProcessRunnerTests can drive it directly.
final class MakeMKVLaunchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelRequested = false
    private var launched = false

    init() {}

    /// Runs `launch` only if no cancel has been requested, with the lock held
    /// throughout.
    ///
    /// - Returns: `true` if `launch` ran and returned normally; `false` if a cancel
    ///   had already been requested, in which case `launch` was NOT called.
    /// - Throws: whatever `launch` throws. The gate then does not count the process as
    ///   launched, so a later cancel will not try to stop it.
    func launchUnlessCancelled(_ launch: () throws -> Void) throws -> Bool {
        try lock.withLock {
            guard !cancelRequested else { return false }
            try launch()
            launched = true
            return true
        }
    }

    /// Records the cancel, always. Then, only if a launch has already succeeded,
    /// calls `stop`, with the lock held so it cannot overlap a launch in progress.
    func requestCancel(stopIfLaunched stop: () -> Void) {
        lock.withLock {
            cancelRequested = true
            if launched { stop() }
        }
    }
}

// MARK: - Output latch (fault F5)

/// Reads the process's stdout pipe right to the end, hands over each complete line in
/// order, and finishes the run exactly once.
///
/// THE FAULT IT FIXES (Codex round 1, finding F5): the old termination handler
/// unhooked the pipe reader, passed on the partial line it already held, and finished
/// at once. Its comment presented that order ("detach the reader first, then flush")
/// as the safe one; that order WAS the bug. A process having exited does not mean its
/// output has been read: the last burst can still be sitting in the pipe, and
/// unhooking the reader throws it away. In the review's reproduction, with
/// MakeMKV-shaped output, 241 of 400 runs lost about 693 of 1,161 lines, and `info`
/// then parsed the shortened text as a success, so titles were silently missing.
///
/// THE DESIGN: the run finishes only when BOTH of these have happened, in either
/// order:
///   - the process has exited (`processDidExit`, called by the termination handler,
///     which now does nothing else), and
///   - the reader has reached end-of-file, that is, it read an empty chunk. That
///     happens only once every copy of the pipe's write end is closed and every byte
///     has been read. The reader unhooks itself then, and only then.
/// Whichever of the two comes second passes on the last unterminated line and
/// finishes.
///
/// TWO WAYS TO FINISH WITHOUT END-OF-FILE:
///   - `finishWithoutProcess`: the launch failed or was refused. This finishes at
///     once, because end-of-file would never come: this process still holds the
///     pipe's write end. (Foundation closes the parent's copy only after a
///     SUCCESSFUL launch. Checked on this project's Mac: after a failed launch the
///     write end is still open.)
///   - A time limit after exit (`eofGracePeriod`, 5 s by default). If makemkvcon
///     started a child process that inherited its stdout and outlived it, end-of-file
///     would not come until that child exited, and the run would hang. Whether
///     makemkvcon ever does this is UNVERIFIED; the limit is there so that the answer
///     does not matter. When it fires, the reader is unhooked, the lines already read
///     plus the last partial line are kept, and the run finishes with the real exit
///     status. Anything written after that point is not read.
///
/// ORDER AND UTF-8: lines are cut at the byte 0x0A by `MakeMKVLineAssembler`, so a
/// multibyte character split across two reads is joined back together. Lines are
/// handed to `onLine` while this latch's lock is held. That is deliberate: it is what
/// keeps every line ahead of the last partial line and of the finish on every path,
/// including the time-limit path, where the finishing thread is not the reader's.
/// The cost: `onLine` must be quick and must never call back into this latch. The
/// executor's callbacks only append to a list or yield into an `AsyncThrowingStream`.
///
/// EXACTLY ONCE: `onComplete` is called only by the code that changes `finished` from
/// false to true under the lock, and it is called after the lock is released.
///
/// THE PIPE'S WRITE END: this code does NOT close the parent's copy of the write end
/// after launch, because Foundation already does (checked on this project's Mac).
/// Closing it a second time could close an unrelated file that has since been given
/// the same descriptor number.
///
/// `internal`, not private, so MakeMKVProcessRunnerTests can drive it on a bare
/// `Pipe`, with no subprocess.
final class MakeMKVOutputLatch: @unchecked Sendable {

    /// How long to keep waiting for end-of-file after the process has exited.
    static let defaultEOFGracePeriod: TimeInterval = 5

    private let lock = NSLock()
    private var assembler = MakeMKVLineAssembler()
    private var exitStatus: Int32?
    private var readerReachedEOF = false
    private var finished = false
    /// Kept only so the time-limit and no-process paths can unhook the reader.
    /// (The reader's own closure holds this latch, and this holds the handle; the
    /// loop is broken whenever the reader is unhooked, which every finish path does.)
    private var readHandle: FileHandle?

    private let eofGracePeriod: TimeInterval
    private let onLine: @Sendable (String) -> Void
    private let onComplete: @Sendable (Result<Int32, Error>) -> Void

    init(
        eofGracePeriod: TimeInterval = MakeMKVOutputLatch.defaultEOFGracePeriod,
        onLine: @escaping @Sendable (String) -> Void,
        onComplete: @escaping @Sendable (Result<Int32, Error>) -> Void
    ) {
        self.eofGracePeriod = eofGracePeriod
        self.onLine = onLine
        self.onComplete = onComplete
    }

    /// Start reading `handle`. Call this before the process is launched.
    func startReading(_ handle: FileHandle) {
        lock.withLock { readHandle = handle }
        handle.readabilityHandler = { [self] readable in
            // `availableData` comes back empty only at end-of-file.
            readerDidRead(readable.availableData, from: readable)
        }
    }

    /// Record that the process has exited. The termination handler calls this and
    /// nothing else. Finishes now if the reader has already reached end-of-file;
    /// otherwise starts the time limit.
    func processDidExit(status: Int32) {
        var completion: Result<Int32, Error>?
        var startTimeLimit = false
        lock.withLock {
            guard !finished, exitStatus == nil else { return }
            exitStatus = status
            if readerReachedEOF {
                completion = finishLocked(.success(status))
            } else {
                startTimeLimit = true
            }
        }
        if let completion { onComplete(completion) }
        if startTimeLimit {
            // In the usual case end-of-file arrives milliseconds later and this finds
            // the run already finished and does nothing. It keeps the latch alive for
            // the length of the limit, which is harmless.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + eofGracePeriod) { [self] in
                eofWaitExpired()
            }
        }
    }

    /// Finish at once, with `error`, because the process was never started (the
    /// launch failed or was refused). Any later call is ignored.
    func finishWithoutProcess(throwing error: Error) {
        var handleToUnhook: FileHandle?
        let didFinish: Bool = lock.withLock {
            guard !finished else { return false }
            finished = true
            handleToUnhook = readHandle
            readHandle = nil
            return true
        }
        handleToUnhook?.readabilityHandler = nil
        if didFinish { onComplete(.failure(error)) }
    }

    // MARK: Private

    private func readerDidRead(_ data: Data, from handle: FileHandle) {
        var completion: Result<Int32, Error>?
        var unhook = false
        lock.withLock {
            if finished {
                unhook = true
                return
            }
            if data.isEmpty {
                // End-of-file: every byte has been read.
                readerReachedEOF = true
                readHandle = nil
                unhook = true
                if let status = exitStatus { completion = finishLocked(.success(status)) }
            } else {
                for line in assembler.take(data) { onLine(line) }
            }
        }
        // Unhooked outside this latch's lock. Setting `readabilityHandler` goes
        // through Foundation's own locking, and never nesting that inside ours rules
        // out any lock-order problem between the two.
        if unhook { handle.readabilityHandler = nil }
        if let completion { onComplete(completion) }
    }

    private func eofWaitExpired() {
        var completion: Result<Int32, Error>?
        var handleToUnhook: FileHandle?
        lock.withLock {
            guard !finished, let status = exitStatus else { return }
            handleToUnhook = readHandle
            readHandle = nil
            completion = finishLocked(.success(status))
        }
        handleToUnhook?.readabilityHandler = nil
        if let completion { onComplete(completion) }
    }

    /// The caller must hold `lock`. Marks the run finished and passes on the last
    /// unterminated line, if any, so it arrives before `onComplete` is called.
    private func finishLocked(_ result: Result<Int32, Error>) -> Result<Int32, Error> {
        finished = true
        if let remainder = assembler.flush() { onLine(remainder) }
        return result
    }
}

// MARK: - Process box

/// Everything that belongs to one run of makemkvcon: the `Process`, its stdout
/// `Pipe` and the launch gate. The process and pipe are created once, in `init`, and
/// never replaced, so they need no lock of their own. The calls that start and stop
/// the process (`run`, `isRunning`, `terminate`) are all made under the gate's lock,
/// so they never overlap.
private final class MakeMKVProcessBox: @unchecked Sendable {
    let process: Process
    let stdoutPipe: Pipe
    private let gate = MakeMKVLaunchGate()

    /// MakeMKV's robot output (messages, progress and diagnostics) is on STDOUT, so
    /// that is the pipe (unlike `ExternalToolRunner`, which reads stderr). stderr and
    /// stdin are the null device.
    init(binaryPath: String, arguments: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        self.process = proc
        self.stdoutPipe = pipe
    }

    /// Launch, unless a cancel has already been asked for. See `MakeMKVLaunchGate`.
    func launchUnlessCancelled() throws -> Bool {
        try gate.launchUnlessCancelled { try process.run() }
    }

    /// Cancel. ALWAYS recorded, so a launch that has not happened yet is refused. If
    /// the process is running: SIGCONT first (a stopped process does not act on
    /// SIGTERM until it is resumed), then `terminate()`, which sends SIGTERM.
    func terminate() {
        gate.requestCancel(stopIfLaunched: {
            guard process.isRunning else { return }
            kill(process.processIdentifier, SIGCONT)
            process.terminate()
        })
    }
}
