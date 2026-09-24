// ============================================================================
// MeedyaConverter — MakeMKVExecutorTests (Issue #503, slice 3)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Exercises the MakeMKV executor's orchestration against a MOCK line-streaming
// seam — NO real subprocess in CI. Covers arg building + path threading, info
// parsing, streamed rip events + ordering, exit-code/launch/cancellation error
// mapping, the consent factory, and the pure line assembler. Public API only;
// no @testable import. The mock sits ABOVE the production MakeMKVProcessRunner, so
// these tests cannot see faults in its own pipe and process handling (Codex round 1
// found two there, F4 and F5). MakeMKVProcessRunnerTests covers the runner itself
// against /bin/sh; a real makemkvcon is exercised only on the manual hardware matrix.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// MARK: - Mock seam

private final class MockMakeMKVRunner: MakeMKVLineStreaming, @unchecked Sendable {
    struct Call: Sendable {
        let binaryPath: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.withLock { _calls } }

    private let scriptedLines: [String]
    private let exitCode: Int32
    private let launchError: MakeMKVExecutorError?
    private let throwCancellation: Bool

    init(
        lines: [String] = [],
        exitCode: Int32 = 0,
        launchError: MakeMKVExecutorError? = nil,
        throwCancellation: Bool = false
    ) {
        self.scriptedLines = lines
        self.exitCode = exitCode
        self.launchError = launchError
        self.throwCancellation = throwCancellation
    }

    func run(
        binaryPath: String,
        arguments: [String],
        onStdoutLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        lock.withLock { _calls.append(Call(binaryPath: binaryPath, arguments: arguments)) }
        if let launchError { throw launchError }
        for line in scriptedLines { onStdoutLine(line) }
        if throwCancellation { throw CancellationError() }
        return exitCode
    }
}

final class MakeMKVExecutorTests: XCTestCase {

    private let binaryPath = "/usr/local/bin/makemkvcon"

    private func makeExecutor(_ runner: MakeMKVLineStreaming) -> MakeMKVExecutor {
        MakeMKVExecutor(
            consent: .userAcknowledged("I accept"),
            binaryPath: binaryPath,
            runner: runner
        )
    }

    private let sampleInfoLines: [String] = [
        "TCOUNT:2",
        #"CINFO:2,0,"Big Movie, Special Edition""#,
        #"CINFO:32,0,"BIG_MOVIE""#,
        #"TINFO:0,2,0,"Big Movie, Special Edition""#,
        #"TINFO:0,9,0,"1:57:21""#,
        #"SINFO:0,0,1,6201,"Video""#,
        #"SINFO:0,0,6,0,"MPEG-4 AVC""#,
        #"TINFO:1,9,0,"0:04:12""#,
    ]

    // MARK: - info

    func test_info_parsesTranscriptAndThreadsArgs() async throws {
        let mock = MockMakeMKVRunner(lines: sampleInfoLines, exitCode: 0)
        let info = try await makeExecutor(mock).info(source: .disc(0))

        XCTAssertEqual(info.expectedTitleCount, 2)
        XCTAssertEqual(info.titles.count, 2)
        XCTAssertEqual(info.discName, "Big Movie, Special Edition")
        XCTAssertEqual(info.titles[0].durationSeconds, 7041)
        XCTAssertEqual(info.titles[0].streams.first?.typeName, "Video")

        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.calls[0].binaryPath, binaryPath)
        XCTAssertEqual(mock.calls[0].arguments, MakeMKVBackend.buildInfoArguments(source: .disc(0)))
    }

    func test_info_nonZeroExitThrowsProcessFailureWithMsgSnippet() async {
        let mock = MockMakeMKVRunner(
            lines: [#"MSG:5010,0,0,"Failed to open disc","Failed to open disc""#],
            exitCode: 12
        )
        do {
            _ = try await makeExecutor(mock).info(source: .disc(0))
            XCTFail("expected a throw")
        } catch let MakeMKVExecutorError.processFailure(code, snippet) {
            XCTAssertEqual(code, 12)
            XCTAssertEqual(snippet, "Failed to open disc")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_info_launchFailureRethrows() async {
        let mock = MockMakeMKVRunner(launchError: .launchFailed(binaryPath: "/x", reason: "nope"))
        do {
            _ = try await makeExecutor(mock).info(source: .disc(0))
            XCTFail("expected a throw")
        } catch MakeMKVExecutorError.launchFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_info_propagatesCancellation() async {
        let mock = MockMakeMKVRunner(throwCancellation: true)
        do {
            _ = try await makeExecutor(mock).info(source: .disc(0))
            XCTFail("expected a throw")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - rip

    func test_rip_mapsAndOrdersEvents() async throws {
        let lines = [
            #"MSG:1000,0,0,"Opening disc","Opening disc""#,
            #"PRGT:5017,0,"Saving all titles""#,
            #"PRGC:5018,0,"Analyzing""#,
            "PRGV:16384,32768,65536",
        ]
        let mock = MockMakeMKVRunner(lines: lines, exitCode: 0)
        var events: [MakeMKVRipEvent] = []
        for try await event in makeExecutor(mock).rip(source: .disc(0), titles: .all, destinationDirectory: "/out") {
            events.append(event)
        }
        XCTAssertEqual(events.count, 4)
        guard case .message(let message) = events[0] else { return XCTFail("first event should be a message") }
        XCTAssertEqual(message.text, "Opening disc")
        XCTAssertEqual(events[1], .progress(.totalTitle(code: 5017, id: 0, name: "Saving all titles")))
        XCTAssertEqual(events[2], .progress(.currentTitle(code: 5018, id: 0, name: "Analyzing")))
        XCTAssertEqual(events[3], .progress(.values(current: 16384, total: 32768, max: 65536)))

        XCTAssertEqual(
            mock.calls[0].arguments,
            MakeMKVBackend.buildRipArguments(source: .disc(0), titles: .all, destinationDirectory: "/out")
        )
    }

    func test_rip_nonZeroExitFinishesWithProcessFailure() async {
        let lines = [
            "PRGV:1,2,65536",
            #"MSG:5003,0,0,"Disc read error","Disc read error""#,
        ]
        let mock = MockMakeMKVRunner(lines: lines, exitCode: 1)
        var events: [MakeMKVRipEvent] = []
        do {
            for try await event in makeExecutor(mock).rip(source: .disc(0), titles: .all, destinationDirectory: "/out") {
                events.append(event)
            }
            XCTFail("expected a throw")
        } catch let MakeMKVExecutorError.processFailure(code, snippet) {
            XCTAssertEqual(code, 1)
            XCTAssertEqual(snippet, "Disc read error")
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertEqual(events.count, 2, "both events should arrive before the failure")
    }

    func test_rip_launchFailureFinishesThrowing() async {
        let mock = MockMakeMKVRunner(launchError: .launchFailed(binaryPath: "/x", reason: "nope"))
        do {
            for try await _ in makeExecutor(mock).rip(source: .disc(0), titles: .all, destinationDirectory: "/out") {}
            XCTFail("expected a throw")
        } catch MakeMKVExecutorError.launchFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_rip_propagatesCancellation() async {
        let mock = MockMakeMKVRunner(throwCancellation: true)
        do {
            for try await _ in makeExecutor(mock).rip(source: .disc(0), titles: .all, destinationDirectory: "/out") {}
            XCTFail("expected a throw")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_rip_consumerBreakStopsIteration() async throws {
        let lines = ["PRGV:1,3,3", "PRGV:2,3,3", "PRGV:3,3,3"]
        let mock = MockMakeMKVRunner(lines: lines, exitCode: 0)
        var received = 0
        for try await _ in makeExecutor(mock).rip(source: .disc(0), titles: .all, destinationDirectory: "/out") {
            received += 1
            if received == 1 { break }
        }
        XCTAssertEqual(received, 1)
    }

    func test_rip_ignoresUnknownLines() async throws {
        let lines = ["garbage", "", "XYZ:1,2,3", "PRGV:1,2,3", #"MSG:1,0,0,"hi","hi""#]
        let mock = MockMakeMKVRunner(lines: lines, exitCode: 0)
        var events: [MakeMKVRipEvent] = []
        for try await event in makeExecutor(mock).rip(source: .disc(0), titles: .all, destinationDirectory: "/out") {
            events.append(event)
        }
        XCTAssertEqual(events.count, 2, "only the PRGV and MSG lines should produce events")
    }

    func test_rip_handlesTrailingCarriageReturn() async throws {
        let lines = ["PRGV:1,2,65536\r", "MSG:1,0,0,\"hi\",\"hi\"\r"]
        let mock = MockMakeMKVRunner(lines: lines, exitCode: 0)
        var events: [MakeMKVRipEvent] = []
        for try await event in makeExecutor(mock).rip(source: .disc(0), titles: .all, destinationDirectory: "/out") {
            events.append(event)
        }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], .progress(.values(current: 1, total: 2, max: 65536)))
    }

    // MARK: - Consent factory

    func test_make_nilConsentThrowsNotConsented() {
        XCTAssertThrowsError(
            try MakeMKVExecutor.make(readiness: .notEnabled(reason: "off"), consent: nil, runner: MockMakeMKVRunner())
        ) { error in
            XCTAssertEqual(error as? MakeMKVExecutorError, .notConsented)
        }
    }

    func test_make_notInstalledThrowsLaunchFailed() {
        XCTAssertThrowsError(
            try MakeMKVExecutor.make(
                readiness: .notInstalled(reason: "missing"),
                consent: .userAcknowledged("ok"),
                runner: MockMakeMKVRunner()
            )
        ) { error in
            guard let mkvError = error as? MakeMKVExecutorError,
                  case .launchFailed = mkvError else {
                return XCTFail("expected .launchFailed, got \(error)")
            }
        }
    }

    func test_make_readyBuildsExecutor() throws {
        let executor = try MakeMKVExecutor.make(
            readiness: .ready(binaryPath: "/bin/makemkvcon"),
            consent: .userAcknowledged("ok"),
            runner: MockMakeMKVRunner()
        )
        XCTAssertEqual(executor.acknowledgement, "ok")
    }

    // MARK: - Line assembler (pure)

    func test_lineAssembler_reassemblesAcrossChunks() {
        var assembler = MakeMKVLineAssembler()
        XCTAssertTrue(assembler.take(Data("MSG:1,".utf8)).isEmpty)
        XCTAssertEqual(assembler.take(Data("2\nPRGV:1,2,3\nMSG:".utf8)), ["MSG:1,2", "PRGV:1,2,3"])
        XCTAssertEqual(assembler.flush(), "MSG:")
        XCTAssertNil(assembler.flush())
    }

    func test_lineAssembler_utf8AcrossChunkBoundary() {
        var assembler = MakeMKVLineAssembler()
        var bytes = Array(#"CINFO:2,0,"Café""#.utf8)
        bytes.append(UInt8(ascii: "\n"))
        // Split inside the two-byte 'é' (0xC3 0xA9) so a naive per-chunk decode
        // would corrupt it; the byte-splitting assembler must rejoin it.
        let firstByteOfE = bytes.firstIndex(of: 0xC3)!
        let first = Data(bytes[..<(firstByteOfE + 1)])   // includes 0xC3, not 0xA9
        let second = Data(bytes[(firstByteOfE + 1)...])  // 0xA9 ... "\n"

        XCTAssertTrue(assembler.take(first).isEmpty, "no newline yet → no line")
        XCTAssertEqual(assembler.take(second), [#"CINFO:2,0,"Café""#])
    }
}
