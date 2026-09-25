// ============================================================================
// MeedyaConverter — FFmpegProbeWatchdogTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// Regression tests for the watchdog timeout + bounded read +
/// graceful-then-forceful termination introduced in Cycle 19 to
/// close SECURITY.md F-007.
///
/// **Why these tests use shell scripts as fake ffprobe**: a real
/// ffprobe will not (consistently) hang in a way we can reproduce
/// across CI runners. We hand `FFmpegProbe` a path to a small
/// shell script that simulates the failure modes — a sleep that
/// ignores SIGTERM (the timeout case), a stderr flood (the buffer-
/// cap case), and a trivial echo (the happy path that must not
/// regress). The `runFFprobe(arguments:)` method is `internal` so
/// `@testable import` reaches it directly without the
/// `analyze(url:)` wrapper's file-exists pre-check.
///
/// Wall-clock budgets are deliberately loose (5-second ceilings
/// for 1-second watchdog firings) to absorb scheduler jitter on
/// loaded CI runners. The tests assert "the watchdog fires
/// promptly" and "the right error is thrown" — not exact timing.
final class FFmpegProbeWatchdogTests: XCTestCase {

    // MARK: - Fixture helpers

    /// Write `contents` to a UUID-named temp file and chmod 0755.
    /// Caller is responsible for removing the file.
    private func writeFixtureScript(_ contents: String, file: StaticString = #file, line: UInt = #line) throws -> String {
        let path = NSTemporaryDirectory() + "ffmpegprobe-fixture-\(UUID().uuidString).sh"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private var fixturesToCleanUp: [String] = []

    override func tearDown() {
        for path in fixturesToCleanUp {
            try? FileManager.default.removeItem(atPath: path)
        }
        fixturesToCleanUp.removeAll()
        super.tearDown()
    }

    private func makeFixture(_ contents: String) throws -> String {
        let path = try writeFixtureScript(contents)
        fixturesToCleanUp.append(path)
        return path
    }

    // MARK: - Happy path: a trivial fast script returns its stdout

    func test_runFFprobe_normalQuickProcess_returnsStdoutData() throws {
        let script = """
        #!/bin/sh
        printf 'ok\\n'
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 5.0,
            byteCap: 1_000_000
        )

        let data = try probe.runFFprobe(arguments: [])
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(str, "ok\n")
    }

    func test_runFFprobe_normalQuickProcess_doesNotConsumeUnboundedTime() throws {
        let script = """
        #!/bin/sh
        printf 'ok\\n'
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 10.0,
            byteCap: 1_000_000
        )

        let start = ProcessInfo.processInfo.systemUptime
        _ = try probe.runFFprobe(arguments: [])
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        XCTAssertLessThan(elapsed, 2.0, "Trivial script should finish quickly (got \(elapsed)s)")
    }

    // MARK: - Watchdog timeout

    func test_runFFprobe_processIgnoringSigterm_throwsTimeout() throws {
        // Trap SIGTERM ⇒ ignore it. The watchdog's terminate()
        // won't kill the script directly, but Foundation's
        // Process will follow up with interrupt() (SIGINT) which
        // we do NOT trap, and the kernel reaps the process.
        let script = """
        #!/bin/sh
        trap '' TERM
        sleep 30
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 1.0,
            byteCap: 1_000_000
        )

        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try probe.runFFprobe(arguments: [])) { error in
            guard case FFmpegProbeError.timeout(let seconds) = error else {
                return XCTFail("Expected .timeout, got \(error)")
            }
            XCTAssertEqual(seconds, 1.0, accuracy: 0.001)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        // 1s SIGTERM watchdog + 3s SIGKILL escalation grace +
        // ~1s drainer setup/teardown. CI jitter ceiling 7s.
        // The contract being verified is "the watchdog escalates
        // promptly even when the subprocess traps SIGTERM" —
        // exact timing is OS/scheduler dependent.
        XCTAssertLessThan(
            elapsed,
            7.0,
            "Watchdog should escalate SIGTERM → SIGKILL within ~7s wall-clock of the deadline (got \(elapsed)s)"
        )
    }

    func test_runFFprobe_quickProcess_doesNotTriggerTimeout() throws {
        // A script that finishes well under the watchdog deadline
        // must not throw .timeout even on a loaded runner.
        let script = """
        #!/bin/sh
        printf 'ok\\n'
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 5.0,
            byteCap: 1_000_000
        )

        XCTAssertNoThrow(try probe.runFFprobe(arguments: []))
    }

    // MARK: - Bounded read

    func test_runFFprobe_stderrFlood_throwsBufferLimitExceeded() throws {
        // 5 MB to stderr — well above the 100 KB test cap. The
        // drainer should hit the cap, terminate the process, and
        // the caller should see .bufferLimitExceeded(stream:
        // "stderr"). Using `dd` rather than `yes` because `yes`'s
        // output rate can starve other processes on CI.
        let script = """
        #!/bin/sh
        dd if=/dev/zero bs=1024 count=5000 2>/dev/null | base64 >&2
        printf 'ok\\n'
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 10.0,
            byteCap: 100_000
        )

        XCTAssertThrowsError(try probe.runFFprobe(arguments: [])) { error in
            guard case FFmpegProbeError.bufferLimitExceeded(let stream, let cap) = error else {
                return XCTFail("Expected .bufferLimitExceeded, got \(error)")
            }
            XCTAssertEqual(stream, "stderr")
            XCTAssertEqual(cap, 100_000)
        }
    }

    func test_runFFprobe_stdoutFlood_throwsBufferLimitExceeded() throws {
        // Symmetric test: same shape but the flood goes to
        // stdout. Used to be the readDataToEndOfFile() OOM
        // vector before Cycle 19.
        let script = """
        #!/bin/sh
        dd if=/dev/zero bs=1024 count=5000 2>/dev/null | base64
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 10.0,
            byteCap: 100_000
        )

        XCTAssertThrowsError(try probe.runFFprobe(arguments: [])) { error in
            guard case FFmpegProbeError.bufferLimitExceeded(let stream, _) = error else {
                return XCTFail("Expected .bufferLimitExceeded, got \(error)")
            }
            XCTAssertEqual(stream, "stdout")
        }
    }

    // MARK: - Exit-code surfacing still works

    func test_runFFprobe_nonzeroExitCode_throwsProbeFailed() throws {
        let script = """
        #!/bin/sh
        printf 'something went wrong\\n' >&2
        exit 3
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 5.0,
            byteCap: 1_000_000
        )

        XCTAssertThrowsError(try probe.runFFprobe(arguments: [])) { error in
            guard case FFmpegProbeError.probeFailed(let code, let stderr) = error else {
                return XCTFail("Expected .probeFailed, got \(error)")
            }
            XCTAssertEqual(code, 3)
            XCTAssertTrue(stderr.contains("something went wrong"))
        }
    }

    func test_runFFprobe_emptyStdout_throwsInvalidOutput() throws {
        let script = """
        #!/bin/sh
        :
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 5.0,
            byteCap: 1_000_000
        )

        XCTAssertThrowsError(try probe.runFFprobe(arguments: [])) { error in
            guard case FFmpegProbeError.invalidOutput = error else {
                return XCTFail("Expected .invalidOutput, got \(error)")
            }
        }
    }

    // MARK: - Output still arriving when FFprobe exits (CI red on 2a948bf, #508)

    /// FFprobe has exited but its output has not all been read yet: the
    /// probe must wait for end-of-file, not give up after a fixed wait.
    ///
    /// WHAT WENT WRONG. The probe used to wait 500 ms per drainer after
    /// FFprobe exited, then treat whatever had been read as the whole
    /// output. On a busy machine the drainer threads (low priority) can
    /// be that late collecting output FFprobe has already written, and
    /// good output then comes back as "FFprobe produced no output". That
    /// is the most likely reason CI went red on 2a948bf; see the comment
    /// at the wait in `FFmpegProbe.runFFprobe` for the evidence.
    ///
    /// WHY THIS SHAPE. From the probe's side, a late READER and a late
    /// WRITER look the same: FFprobe has exited, and end-of-file has not
    /// been read yet. A late reader needs a starved CPU, which a test
    /// cannot arrange reliably. A late writer can be arranged exactly.
    /// Here the script exits at once, and a background child that shares
    /// its stdout writes the answer 2 seconds later. That is longer than
    /// the old waits added together (2 × 500 ms), so before the fix this
    /// failed every time, with `.invalidOutput`.
    func test_runFFprobe_outputStillArrivingAfterExit_isWaitedFor_notThrownAway() throws {
        let script = """
        #!/bin/sh
        ( sleep 2; printf 'late but complete\\n' ) &
        exit 0
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 10.0,
            byteCap: 1_000_000
        )

        let data = try probe.runFFprobe(arguments: [])
        XCTAssertEqual(String(data: data, encoding: .utf8), "late but complete\n")
    }

    /// The other side of the same wait. When the pipe stays open past the
    /// watchdog's final deadline, the result is `.timeout`, never the
    /// fragment read so far.
    ///
    /// The script writes the start of a JSON answer and exits. A
    /// background `sleep` keeps its stdout open for 10 seconds, well past
    /// the deadline (0.5 s watchdog + 3 s SIGKILL grace). Before the
    /// fix, the fragment `{"streams":[` came back after about 1 second as
    /// if it were the whole output.
    func test_runFFprobe_pipeHeldOpenPastTheDeadline_throwsTimeout_neverAFragment() throws {
        let script = """
        #!/bin/sh
        printf '{"streams":['
        sleep 10 &
        exit 0
        """
        let path = try makeFixture(script)
        let probe = FFmpegProbe(
            ffprobePath: path,
            timeoutSeconds: 0.5,
            byteCap: 1_000_000
        )

        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try probe.runFFprobe(arguments: [])) { error in
            guard case FFmpegProbeError.timeout(let seconds) = error else {
                return XCTFail("Expected .timeout, got \(error)")
            }
            XCTAssertEqual(seconds, 0.5, accuracy: 0.001)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        // The wait ends at the deadline (about 3.5 s), not when the 10 s
        // `sleep` lets go of the pipe. Same loose 7 s CI ceiling as the
        // SIGTERM test above, and still well short of 10 s.
        XCTAssertLessThan(elapsed, 7.0, "the wait must end at the watchdog's deadline (got \(elapsed)s)")
    }

    // MARK: - Path that doesn't exist

    func test_runFFprobe_nonexistentBinary_throwsNotAvailable() throws {
        let probe = FFmpegProbe(
            ffprobePath: "/var/empty/definitely/not/a/binary/\(UUID().uuidString)",
            timeoutSeconds: 5.0,
            byteCap: 1_000_000
        )
        XCTAssertThrowsError(try probe.runFFprobe(arguments: [])) { error in
            guard case FFmpegProbeError.ffprobeNotAvailable = error else {
                return XCTFail("Expected .ffprobeNotAvailable, got \(error)")
            }
        }
    }

    // MARK: - Default initialiser still compiles

    func test_init_defaultParameters_compileAndPreserveBackwardCompat() {
        // Smoke test: callers from before Cycle 19 used
        // `FFmpegProbe(ffprobePath:)` without timeout / byteCap.
        // The defaulted params must keep that callsite working.
        _ = FFmpegProbe(ffprobePath: "/usr/local/bin/ffprobe")
    }
}
