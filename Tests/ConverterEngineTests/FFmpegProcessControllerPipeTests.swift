// ============================================================================
// MeedyaConverter — FFmpegProcessControllerPipeTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pins one fix, made when CI went red on 2a948bf (#508). Once FFmpeg has
// exited, `FFmpegProcessController`'s two pipe handlers stop. They used to
// stay set and be called over and over at end-of-file. That burned CPU at
// default priority, and in the engine it ran right through the next job's
// probe. See the comment above the handlers in `FFmpegProcessController`.
//
// HOW IT IS OBSERVED. The handlers are private, so this watches the one thing
// the spinning costs: CPU time. A fake FFmpeg (a shell script) writes a line
// to each pipe and exits. The test waits for the progress stream to finish,
// keeps the controller alive, and measures this process's own CPU time over
// one idle second. Keeping the controller alive matters. It is what makes a
// handler that was never stopped keep spinning for the whole measurement,
// instead of only until the controller happens to be freed. Before the fix
// this was measured at about 0.9 s of CPU per idle second (1.75 s in 2 s,
// with two handlers spinning). With the fix it is close to zero.
//
// WHAT THIS CANNOT DO. CPU time is counted for the whole process, so another
// test's leftover busy thread in the same process would be counted too. The
// 0.3 s limit leaves room for ordinary background noise. On a heavily loaded
// machine, a spinning handler gets less CPU itself, so a regression could
// measure under the limit and slip through. That can only hide a fault; it
// cannot make a correct controller fail.
//
// Public API only (`import ConverterEngine`, no `@testable`).
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class FFmpegProcessControllerPipeTests: XCTestCase {

    /// This process's CPU time so far, every thread, user plus system, in
    /// seconds. Child processes are not included (that would be
    /// `RUSAGE_CHILDREN`), so the fake FFmpeg's own run does not count.
    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    func test_afterFFmpegExits_itsPipeHandlersStop_insteadOfSpinningAtEndOfFile() async throws {
        // One line on each pipe, so both handlers genuinely read data before
        // they reach end-of-file.
        let path = NSTemporaryDirectory() + "ffmpeg-controller-pipes-\(UUID().uuidString).sh"
        let script = """
        #!/bin/sh
        printf 'a log line\\n' >&2
        printf 'progress=end\\n'
        exit 0
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = FFmpegProcessController(binaryPath: path)
        let progress = try controller.startEncoding(arguments: [])
        for await _ in progress {}
        XCTAssertEqual(controller.exitCode, 0, "precondition: the fake FFmpeg ran and exited cleanly")

        // Both pipes reach end-of-file when FFmpeg exits, so a handler that
        // was never stopped starts spinning within milliseconds. 300 ms is
        // plenty of time for that before the measured second begins.
        try await Task.sleep(for: .milliseconds(300))
        let before = Self.processCPUSeconds()
        try await Task.sleep(for: .seconds(1))
        let used = Self.processCPUSeconds() - before
        // Kept alive to here on purpose. See the file header.
        withExtendedLifetime(controller) {}

        XCTAssertLessThan(
            used, 0.3,
            "the process used \(used) s of CPU in one idle second after FFmpeg exited; "
                + "the controller's pipe handlers are still being called at end-of-file"
        )
    }
}
