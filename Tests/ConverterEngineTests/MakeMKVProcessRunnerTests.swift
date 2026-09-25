// ============================================================================
// MeedyaConverter — MakeMKVProcessRunnerTests (Issue #503, Codex round 1 F4 + F5)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Tests for the PRODUCTION MakeMKV runner's own pipe and process handling.
//
// Why a separate file: MakeMKVExecutorTests drives the executor through a mock
// `MakeMKVLineStreaming`, which sits ABOVE the production runner. Both faults fixed
// here lived BELOW that mock, so no mock-based test could ever have caught them:
//   F4 — a cancel that arrived before launch was lost, and the process ran anyway.
//   F5 — output still in the pipe when the process exited was thrown away.
//
// What is covered, and how:
//   - `MakeMKVLaunchGate` directly (no process at all).
//   - `MakeMKVOutputLatch` on a real `Pipe()` with no subprocess, so the order of
//     "process exited" and "last bytes written" can be forced, not left to timing.
//   - `MakeMKVProcessRunner` end to end against `/bin/sh`, which exists on the
//     macos-15 CI runners. A real `makemkvcon` is still exercised only on the
//     manual hardware matrix.
//
// Needs `@testable import` because the gate and the latch are `internal`.
// `swift test` cannot run on the maintainer's machine (no XCTest there), so CI
// (`swift test --parallel`) is the only place these run under real XCTest. Every
// temp path is unique per test, so parallel runs cannot collide, and any file a
// test creates is removed afterwards.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class MakeMKVProcessRunnerTests: XCTestCase {

    // MARK: - Helpers (nested, so their names cannot clash with other test files)

    /// Lock-protected record of what a latch or runner delivered, and of how many
    /// lines had arrived at the moment each completion came in.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        private var completions: [(result: Result<Int32, Error>, linesSoFar: Int)] = []
        private var events: [String] = []

        func line(_ text: String) { lock.withLock { lines.append(text) } }
        func complete(_ result: Result<Int32, Error>) {
            lock.withLock { completions.append((result, lines.count)) }
        }
        func event(_ name: String) { lock.withLock { events.append(name) } }

        var allLines: [String] { lock.withLock { lines } }
        var completionCount: Int { lock.withLock { completions.count } }
        var firstCompletion: (result: Result<Int32, Error>, linesSoFar: Int)? {
            lock.withLock { completions.first }
        }
        var allEvents: [String] { lock.withLock { events } }
    }

    /// A temp path no other test (or parallel test process) will use.
    private func uniqueTempPath(_ suffix: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MakeMKVProcessRunnerTests-\(UUID().uuidString)-\(suffix)")
            .path
    }

    /// Waits, without blocking a thread, until `condition` holds or `timeout` passes.
    /// Returns whether the condition was met.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }

    /// About 40 KB of MakeMKV-shaped robot lines (650 of them), the size of a
    /// `makemkvcon info` transcript that the old runner routinely cut short.
    private func burstLines() -> [String] {
        (0..<650).map { #"TINFO:\#($0),2,0,"Title \#($0), padded out to make a forty KB burst""# }
    }

    // MARK: - Launch gate (F4)

    func test_launchGate_cancelBeforeLaunch_refusesTheLaunch() throws {
        let gate = MakeMKVLaunchGate()
        var stopCalls = 0
        gate.requestCancel(stopIfLaunched: { stopCalls += 1 })

        var launched = false
        let result = try gate.launchUnlessCancelled { launched = true }

        XCTAssertFalse(result, "a launch after a cancel must be refused")
        XCTAssertFalse(launched, "the launch step must not even be called")
        XCTAssertEqual(stopCalls, 0, "nothing was launched, so there is nothing to stop")
    }

    func test_launchGate_cancelAfterLaunch_stopsTheProcess() throws {
        let gate = MakeMKVLaunchGate()
        var launches = 0
        let result = try gate.launchUnlessCancelled { launches += 1 }
        XCTAssertTrue(result)

        var stopCalls = 0
        gate.requestCancel(stopIfLaunched: { stopCalls += 1 })

        XCTAssertEqual(launches, 1)
        XCTAssertEqual(stopCalls, 1, "a cancel after a successful launch must stop the process")
    }

    func test_launchGate_failedLaunch_rethrowsAndIsNotStoppedLater() {
        struct LaunchBoom: Error {}
        let gate = MakeMKVLaunchGate()
        XCTAssertThrowsError(try gate.launchUnlessCancelled { throw LaunchBoom() }) { error in
            XCTAssertTrue(error is LaunchBoom)
        }
        var stopCalls = 0
        gate.requestCancel(stopIfLaunched: { stopCalls += 1 })
        XCTAssertEqual(stopCalls, 0, "a launch that threw started nothing, so there is nothing to stop")
    }

    /// A cancel from another thread while the launch is under way must wait for the
    /// launch to finish and then stop the process. If the gate let go of its lock
    /// between the check and the launch, the cancel would see "not launched yet",
    /// stop nothing, and the process would run on: the F4 race.
    ///
    /// DETERMINISTIC OVERLAP (fallback review round 2, finding 5): the previous
    /// version of this test gave the cancelling thread a 100 ms `Thread.sleep`
    /// inside the launch closure to land in. That is not long enough on a slow
    /// or busy machine — and worse, it doesn't need to be, for the WRONG
    /// reason: `launched` is set to `true` BEFORE the gate ever releases its
    /// lock (inside the same `lock.withLock` block that ran `launch()`), so a
    /// cancel that arrives after the sleep ends, once `launch()` has already
    /// returned, would see `launched == true` even if `requestCancel` had lost
    /// its own locking entirely. The recorded events would then be identical
    /// to the genuinely-correct case, and the test would pass for the wrong
    /// reason — exactly the vacuous failure mode the finding describes.
    ///
    /// Fixed with two semaphores instead of a sleep: the launch closure
    /// signals `launchStarted`, then BLOCKS on `cancelIsCalling`. The
    /// cancelling thread waits for `launchStarted`, signals `cancelIsCalling`
    /// as the very last thing it does before making the (possibly blocking)
    /// call — there is no more precise, non-invasive way to observe "is about
    /// to call `requestCancel`" than that — and only then calls
    /// `gate.requestCancel`. This forces the call to happen no later than the
    /// instant the launch closure is allowed to resume and finish, so
    /// `launch()` can never have already returned when `requestCancel` runs.
    /// No wall-clock races, and no captured `var` mutated from a `@Sendable`
    /// closure — every recorded event goes through the lock-protected
    /// `Recorder` above.
    func test_launchGate_cancelDuringLaunch_waitsForTheLaunchThenStops() throws {
        let gate = MakeMKVLaunchGate()
        let recorder = Recorder()
        let launchStarted = DispatchSemaphore(value: 0)
        let cancelIsCalling = DispatchSemaphore(value: 0)
        let cancelReturned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            launchStarted.wait()
            cancelIsCalling.signal()
            gate.requestCancel(stopIfLaunched: { recorder.event("stop") })
            recorder.event("cancel-returned")
            cancelReturned.signal()
        }

        let launched = try gate.launchUnlessCancelled {
            recorder.event("launch-start")
            launchStarted.signal()
            // Block until the cancelling thread has committed to calling
            // `requestCancel`, so the launch cannot finish (and the gate's
            // lock cannot be released) before that call has begun. The
            // timeout is only a safety net against a genuinely hung test,
            // never something the assertion below depends on.
            XCTAssertEqual(
                cancelIsCalling.wait(timeout: .now() + 5), .success,
                "the cancelling thread never reached requestCancel"
            )
            recorder.event("launch-end")
        }

        XCTAssertTrue(launched)
        XCTAssertEqual(cancelReturned.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(
            recorder.allEvents, ["launch-start", "launch-end", "stop", "cancel-returned"],
            "requestCancel must not see the process as launched — and so must not call stop — until launch() has actually finished"
        )
    }

    // MARK: - Output latch (F5), on a real Pipe with no subprocess

    /// The deterministic form of F5: "the process has exited" is signalled BEFORE the
    /// last 40 KB (and an unterminated final line) is even written. The old runner
    /// finished at the exit signal and dropped all of it.
    func test_outputLatch_outputWrittenAfterTheExitSignalIsStillDelivered() async throws {
        let recorder = Recorder()
        let latch = MakeMKVOutputLatch(
            eofGracePeriod: 30,
            onLine: { recorder.line($0) },
            onComplete: { recorder.complete($0) }
        )
        let pipe = Pipe()
        latch.startReading(pipe.fileHandleForReading)
        let writer = pipe.fileHandleForWriting

        try writer.write(contentsOf: Data("FIRST\n".utf8))
        latch.processDidExit(status: 0)

        let burst = burstLines()
        let tail = Data((burst.joined(separator: "\n") + "\nLAST").utf8)
        XCTAssertGreaterThanOrEqual(tail.count, 40_000)
        try writer.write(contentsOf: tail)
        try writer.close()

        let finished = await waitUntil(timeout: 10) { recorder.completionCount > 0 }
        XCTAssertTrue(finished, "the latch never finished")

        let expected = ["FIRST"] + burst + ["LAST"]
        let got = recorder.allLines
        XCTAssertEqual(got.count, expected.count)
        XCTAssertTrue(got == expected, "lines lost or out of order")
        let completion = try XCTUnwrap(recorder.firstCompletion)
        XCTAssertEqual(completion.linesSoFar, expected.count,
                       "every line, including LAST, must arrive BEFORE the completion")
        XCTAssertEqual(try completion.result.get(), 0)
        XCTAssertEqual(recorder.completionCount, 1)
    }

    /// End-of-file first, exit second: the latch must wait for the exit status, then
    /// pass on the unterminated last line and finish.
    func test_outputLatch_endOfFileBeforeExit_waitsForTheExitStatus() async throws {
        let recorder = Recorder()
        let latch = MakeMKVOutputLatch(
            eofGracePeriod: 30,
            onLine: { recorder.line($0) },
            onComplete: { recorder.complete($0) }
        )
        let pipe = Pipe()
        latch.startReading(pipe.fileHandleForReading)
        try pipe.fileHandleForWriting.write(contentsOf: Data("a\nb".utf8))
        try pipe.fileHandleForWriting.close()

        let gotA = await waitUntil(timeout: 5) { recorder.allLines == ["a"] }
        XCTAssertTrue(gotA)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(recorder.completionCount, 0, "must not finish before the exit status is known")

        latch.processDidExit(status: 3)
        let finished = await waitUntil(timeout: 5) { recorder.completionCount > 0 }
        XCTAssertTrue(finished)
        XCTAssertEqual(recorder.allLines, ["a", "b"])
        XCTAssertEqual(try recorder.firstCompletion?.result.get(), 3)
    }

    /// Exit with the write end still open (as when a child process inherited stdout
    /// and outlives its parent): the latch must finish after its time limit rather
    /// than hang, keeping what it has read plus the last partial line.
    func test_outputLatch_exitWithoutEndOfFile_finishesAfterTheTimeLimit() async throws {
        let recorder = Recorder()
        let latch = MakeMKVOutputLatch(
            eofGracePeriod: 0.3,
            onLine: { recorder.line($0) },
            onComplete: { recorder.complete($0) }
        )
        let pipe = Pipe()
        latch.startReading(pipe.fileHandleForReading)
        try pipe.fileHandleForWriting.write(contentsOf: Data("one\npartial".utf8))
        let gotOne = await waitUntil(timeout: 5) { recorder.allLines == ["one"] }
        XCTAssertTrue(gotOne)

        let exitedAt = Date()
        latch.processDidExit(status: 7)
        let finished = await waitUntil(timeout: 5) { recorder.completionCount > 0 }
        let waited = Date().timeIntervalSince(exitedAt)

        XCTAssertTrue(finished, "the latch hung waiting for an end-of-file that never came")
        XCTAssertGreaterThanOrEqual(waited, 0.25, "finished before the time limit")
        XCTAssertEqual(recorder.allLines, ["one", "partial"])
        XCTAssertEqual(try recorder.firstCompletion?.result.get(), 7)
        try pipe.fileHandleForWriting.close()
    }

    /// Launch failed or was refused: finish at once (end-of-file will never come,
    /// because this process still holds the write end), and never finish twice.
    func test_outputLatch_finishWithoutProcess_finishesAtOnceAndOnlyOnce() async throws {
        let recorder = Recorder()
        let latch = MakeMKVOutputLatch(
            eofGracePeriod: 0.1,
            onLine: { recorder.line($0) },
            onComplete: { recorder.complete($0) }
        )
        let pipe = Pipe()
        latch.startReading(pipe.fileHandleForReading)

        latch.finishWithoutProcess(throwing: CancellationError())
        XCTAssertEqual(recorder.completionCount, 1, "must finish straight away, not wait for end-of-file")

        // Late signals from every direction must not finish it a second time.
        latch.processDidExit(status: 0)
        latch.finishWithoutProcess(throwing: CancellationError())
        try pipe.fileHandleForWriting.write(contentsOf: Data("late\n".utf8))
        try pipe.fileHandleForWriting.close()
        try await Task.sleep(nanoseconds: 300_000_000) // well past the 0.1 s time limit

        XCTAssertEqual(recorder.completionCount, 1)
        XCTAssertTrue(recorder.allLines.isEmpty)
        guard case .failure(let error)? = recorder.firstCompletion?.result else {
            return XCTFail("expected a failure completion")
        }
        XCTAssertTrue(error is CancellationError)
    }

    // MARK: - Production runner against /bin/sh

    /// F4 through the public API: a task that is ALREADY cancelled when it calls
    /// `run` must not start the process at all. The old runner threw
    /// CancellationError too, but only after launching and running the script, so
    /// the marker file is what tells the two apart.
    func test_runner_alreadyCancelledTask_neverLaunchesTheProcess() async throws {
        let marker = uniqueTempPath("marker")
        defer { try? FileManager.default.removeItem(atPath: marker) }

        let task = Task { () async throws -> Int32 in
            // Parked until cancelled, so `run` is entered by an already-cancelled task.
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            return try await MakeMKVProcessRunner().run(
                binaryPath: "/bin/sh",
                arguments: ["-c", #"touch "$1""#, "sh", marker]
            ) { _ in }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                       "the process was launched even though the task was already cancelled")
    }

    func test_runner_cancelWhileRunning_stopsTheProcess() async throws {
        let recorder = Recorder()
        let task = Task { () async throws -> Int32 in
            // `exec` so the shell BECOMES the sleep: SIGTERM then ends the very process
            // that holds the pipe, and end-of-file follows at once.
            try await MakeMKVProcessRunner().run(
                binaryPath: "/bin/sh",
                arguments: ["-c", "echo started; exec sleep 30"]
            ) { recorder.line($0) }
        }
        let started = await waitUntil(timeout: 10) { recorder.allLines.contains("started") }
        XCTAssertTrue(started)

        let cancelledAt = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 5, "the running process was not stopped")
    }

    /// F5 against a real process: `cat` writes a 40 KB burst ending in an
    /// unterminated line and exits at once. Every run must deliver every line, in
    /// order. Measured on the maintainer's Mac with this exact shape: the old runner
    /// lost lines in 66 of 300 runs (about 613 of 651 lines each time), the new one
    /// in 0 of 300. So 30 runs would catch a return of the old behaviour almost
    /// every time there. (A 20 ms pause before the burst made the old loss RARER on
    /// that Mac, 1 in 400 runs, which is why there is no pause.) CI machines may
    /// hit the race at a different rate; this is a regression net, while the Pipe
    /// test above is the deterministic proof.
    func test_runner_deliversEveryLineOfABurstWrittenJustBeforeExit() async throws {
        let fixture = uniqueTempPath("burst.txt")
        defer { try? FileManager.default.removeItem(atPath: fixture) }
        let expected = burstLines() + ["TAIL-WITHOUT-NEWLINE"]
        let payload = expected.joined(separator: "\n")
        XCTAssertGreaterThanOrEqual(payload.utf8.count, 40_000)
        try payload.write(toFile: fixture, atomically: true, encoding: .utf8)

        let runner = MakeMKVProcessRunner()
        for run in 1...30 {
            let recorder = Recorder()
            let status = try await runner.run(
                binaryPath: "/bin/sh",
                arguments: ["-c", #"cat "$1""#, "sh", fixture]
            ) { recorder.line($0) }
            XCTAssertEqual(status, 0)
            let got = recorder.allLines
            if got != expected {
                let common = min(got.count, expected.count)
                let firstDifference = (0..<common).first { got[$0] != expected[$0] } ?? common
                XCTFail("run \(run): got \(got.count) of \(expected.count) lines; first difference at line \(firstDifference)")
                break
            }
        }
    }

    /// A child process that inherits stdout and outlives the parent keeps the pipe
    /// open, so end-of-file does not come until the child exits. The runner must give
    /// up waiting after its time limit (shortened here) and return the parent's real
    /// exit status and output. Whether makemkvcon ever does this is unverified.
    func test_runner_childKeepsStdoutOpen_finishesAfterTheTimeLimit() async throws {
        let recorder = Recorder()
        let startedAt = Date()
        let status = try await MakeMKVProcessRunner(eofGracePeriod: 0.5).run(
            binaryPath: "/bin/sh",
            arguments: ["-c", "sleep 5 & echo parent-done"]
        ) { recorder.line($0) }
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status, 0)
        XCTAssertEqual(recorder.allLines, ["parent-done"])
        XCTAssertLessThan(elapsed, 4, "waited for the child instead of giving up after the time limit")
    }

    /// A failed launch must throw `.launchFailed` straight away. It must not wait
    /// for an end-of-file that will never come (this process still holds the
    /// pipe's write end after a failed launch).
    func test_runner_launchFailure_throwsLaunchFailedPromptly() async {
        let missing = uniqueTempPath("no-such-makemkvcon")
        let startedAt = Date()
        do {
            _ = try await MakeMKVProcessRunner().run(binaryPath: missing, arguments: []) { _ in }
            XCTFail("expected a launch failure")
        } catch MakeMKVExecutorError.launchFailed(let path, _) {
            XCTAssertEqual(path, missing)
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    func test_runner_nonZeroExit_returnsTheStatusAndEveryLine() async throws {
        let recorder = Recorder()
        let status = try await MakeMKVProcessRunner().run(
            binaryPath: "/bin/sh",
            arguments: ["-c", #"printf 'MSG:1,0,0,"a","a"\nno-newline'; exit 3"#]
        ) { recorder.line($0) }
        XCTAssertEqual(status, 3)
        XCTAssertEqual(recorder.allLines, [#"MSG:1,0,0,"a","a""#, "no-newline"])
    }
}
