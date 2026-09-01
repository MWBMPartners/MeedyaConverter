// ============================================================================
// MeedyaConverter — Bounded-concurrency queue tests (Issue #286)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Issue #286 replaced `AppViewModel.startQueue()`'s sequential `while` loop
// with a bounded-concurrency runner. The runner itself lives in the
// `MeedyaConverter` executable target, which an SPM test target cannot
// import (see the note above `MeedyaConvertTests` in Package.swift), and a
// real multi-job encode needs FFmpeg and real media — neither is available
// in CI. So these tests cover the seams in `ConverterEngine` that the
// runner's correctness actually rests on, all of which are pure logic or
// plain file I/O:
//
//   * `EncodingQueue.claimNextPendingJob()` — the atomic take-and-mark that
//     stops two concurrent slots being handed the same job. Previously the
//     runner called `nextPendingJob()` (a pure read) and marked the job
//     `.encoding` afterwards, which is safe only with a single puller.
//   * `ParallelEncoder.resolveConcurrency` — the clamping that makes the
//     alpha default sequential. The load-bearing assertion is that an
//     absent `UserDefaults` key (which reads back as 0) resolves to exactly
//     1, i.e. shipping this feature changes nothing until a user opts in.
//   * `EncodingStatisticsRecorder` — the actor that replaced the
//     construct-a-fresh-store-per-write pattern. Twenty concurrent records
//     must produce twenty entries; the old pattern lost entries because two
//     stores loaded the same baseline and the second rewrite clobbered the
//     first.
//   * `EncodingEngine`'s per-job process-controller registry, to the extent
//     it can be exercised without launching FFmpeg: an engine with nothing
//     in flight reports nothing in flight, and every control call — keyed or
//     not — is a safe no-op. Routing a *live* controller to the right job
//     cannot be asserted here without spawning a real process, so it is
//     deliberately not claimed.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class ParallelEncodingConcurrencyTests: XCTestCase {

    // MARK: - Fixtures

    private func makeConfig(_ name: String, priority: Int = 0) -> EncodingJobConfig {
        EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/\(name).mov"),
            outputURL: URL(fileURLWithPath: "/tmp/\(name).mp4"),
            profile: .webStandard,
            priority: priority
        )
    }

    // MARK: - EncodingQueue.claimNextPendingJob

    func test_claimNextPendingJob_marksTheClaimedJobEncoding() throws {
        let queue = EncodingQueue()
        queue.addJob(makeConfig("a"))

        let claimed = try XCTUnwrap(queue.claimNextPendingJob())

        XCTAssertEqual(claimed.status, .encoding,
                       "The claim must mark the job in the same step it hands it out.")
    }

    func test_claimNextPendingJob_neverHandsOutTheSameJobTwice() throws {
        let queue = EncodingQueue()
        queue.addJob(makeConfig("a"))
        queue.addJob(makeConfig("b"))

        let first = try XCTUnwrap(queue.claimNextPendingJob())
        let second = try XCTUnwrap(queue.claimNextPendingJob())

        XCTAssertNotEqual(first.config.id, second.config.id,
                          "Two slots topping up must receive two different jobs.")
        XCTAssertNil(queue.claimNextPendingJob(),
                     "Both jobs are claimed; a third claim has nothing left to take.")
    }

    func test_claimNextPendingJob_returnsNilForAnEmptyQueue() {
        XCTAssertNil(EncodingQueue().claimNextPendingJob())
    }

    func test_claimNextPendingJob_ignoresJobsThatAreNotQueued() {
        let queue = EncodingQueue()
        queue.addJob(makeConfig("a"))
        queue.cancelAllPending()

        XCTAssertNil(queue.claimNextPendingJob(),
                     "A cancelled job is not pending and must never be claimed.")
    }

    func test_claimNextPendingJob_respectsPriorityOrdering() throws {
        let queue = EncodingQueue()
        queue.addJob(makeConfig("low", priority: 0))
        queue.addJob(makeConfig("high", priority: 10))

        let claimed = try XCTUnwrap(queue.claimNextPendingJob())

        XCTAssertEqual(claimed.config.inputURL.lastPathComponent, "high.mov",
                       "Claiming must preserve the queue's existing priority order.")
    }

    func test_claimNextPendingJob_concurrentClaimsNeverDuplicateAJob() async {
        let queue = EncodingQueue()
        let jobCount = 25
        for index in 0..<jobCount {
            queue.addJob(makeConfig("job-\(index)"))
        }

        // Far more claimers than jobs, so most of them race for the last few.
        let claimedIDs = await withTaskGroup(of: UUID?.self) { group in
            for _ in 0..<(jobCount * 4) {
                group.addTask { queue.claimNextPendingJob()?.config.id }
            }
            var seen: [UUID] = []
            for await id in group {
                if let id { seen.append(id) }
            }
            return seen
        }

        XCTAssertEqual(claimedIDs.count, jobCount,
                       "Every job must be claimed exactly once — no more, no fewer.")
        XCTAssertEqual(Set(claimedIDs).count, jobCount,
                       "No job may be handed to two claimers.")
    }

    // MARK: - EncodingQueue.activeJobsSnapshot

    func test_activeJobsSnapshot_containsOnlyEncodingAndPausedJobs() throws {
        let queue = EncodingQueue()
        queue.addJob(makeConfig("running"))
        queue.addJob(makeConfig("paused"))
        queue.addJob(makeConfig("waiting"))

        let running = try XCTUnwrap(queue.claimNextPendingJob())
        let paused = try XCTUnwrap(queue.claimNextPendingJob())
        paused.status = .paused

        let names = Set(queue.activeJobsSnapshot().map(\.config.inputURL.lastPathComponent))

        XCTAssertEqual(names, ["running.mov", "paused.mov"])
        XCTAssertEqual(running.status, .encoding)
    }

    // MARK: - ParallelEncoder.resolveConcurrency

    func test_resolveConcurrency_absentUserDefaultsKeyMeansSequential() {
        // `UserDefaults.integer(forKey:)` returns 0 for an absent key. That
        // is the alpha default, and it must mean "one job at a time" —
        // exactly the behaviour the queue had before Issue #286.
        XCTAssertEqual(
            ParallelEncoder.resolveConcurrency(requested: 0, entitled: true, hardwareCeiling: 8),
            1
        )
    }

    func test_resolveConcurrency_zeroAndNegativeValuesClampToOne() {
        for requested in [-99, -1, 0, 1] {
            XCTAssertEqual(
                ParallelEncoder.resolveConcurrency(
                    requested: requested, entitled: true, hardwareCeiling: 8
                ),
                1,
                "requested \(requested) must resolve to 1"
            )
        }
    }

    func test_resolveConcurrency_unentitledAlwaysClampsToOne() {
        for requested in [1, 2, 8, 1_000] {
            XCTAssertEqual(
                ParallelEncoder.resolveConcurrency(
                    requested: requested, entitled: false, hardwareCeiling: 8
                ),
                1,
                "Without the Parallel Encoding entitlement, \(requested) must resolve to 1"
            )
        }
    }

    func test_resolveConcurrency_passesThroughValuesWithinTheHardwareCeiling() {
        XCTAssertEqual(
            ParallelEncoder.resolveConcurrency(requested: 3, entitled: true, hardwareCeiling: 4),
            3
        )
    }

    func test_resolveConcurrency_clampsToTwiceTheHardwareCeiling() {
        XCTAssertEqual(
            ParallelEncoder.resolveConcurrency(requested: 1_000, entitled: true, hardwareCeiling: 4),
            8
        )
    }

    func test_resolveConcurrency_neverReturnsLessThanOneEvenForAbsurdCeilings() {
        XCTAssertEqual(
            ParallelEncoder.resolveConcurrency(requested: 4, entitled: true, hardwareCeiling: 0),
            1
        )
        XCTAssertEqual(
            ParallelEncoder.resolveConcurrency(requested: 4, entitled: true, hardwareCeiling: -5),
            1
        )
    }

    func test_maxConcurrentJobsDefaultsKey_isTheKeyTheUIAndRunnerShare() {
        // Both `ParallelEncodingView`'s slider and the runner read this key.
        // Renaming it silently would strand every user's saved setting, so
        // the exact string is pinned here.
        XCTAssertEqual(ParallelEncoder.maxConcurrentJobsDefaultsKey, "parallelMaxConcurrentJobs")
    }

    // MARK: - EncodingStatisticsRecorder

    func test_recorder_losesNoEntriesUnderConcurrentWrites() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parallel-encoding-recorder-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let recorder = EncodingStatisticsRecorder(directory: tempDir)
        let writeCount = 20

        // Fired from a task group so the writes genuinely contend. The
        // pre-#286 code path — a fresh `EncodingStatisticsStore` per write,
        // each doing load-append-rewrite — drops entries here, because two
        // stores load the same baseline and the later rewrite wins.
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<writeCount {
                group.addTask {
                    await recorder.record(
                        EncodingStatistics(jobID: UUID(), jobName: "job-\(index)")
                    )
                }
            }
        }

        let persisted = await recorder.allStatistics()
        XCTAssertEqual(persisted.count, writeCount,
                       "Every concurrent record must survive; none may be clobbered.")
        XCTAssertEqual(
            Set(persisted.map(\.jobName)),
            Set((0..<writeCount).map { "job-\($0)" }),
            "Each write must be the specific entry it recorded, not a duplicate."
        )
    }

    func test_recorder_readsBackThroughAnIndependentStoreInstance() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parallel-encoding-recorder-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let jobID = UUID()
        let recorder = EncodingStatisticsRecorder(directory: tempDir)
        await recorder.record(EncodingStatistics(jobID: jobID, jobName: "persisted.mov"))

        // The Dashboard and Encoding Graphs views each build their own
        // store; the recorder must be writing the same file they read.
        let reader = EncodingStatisticsStore(directory: tempDir)
        let loaded = try XCTUnwrap(reader.statistics(forJob: jobID))
        XCTAssertEqual(loaded.jobName, "persisted.mov")
    }

    func test_recorder_seesHistoryClearedByAnotherStoreInstance() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parallel-encoding-recorder-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let recorder = EncodingStatisticsRecorder(directory: tempDir)
        await recorder.record(EncodingStatistics(jobID: UUID(), jobName: "before-clear"))

        // DashboardView clears history through its own store instance. A
        // recorder caching an in-memory history would resurrect the cleared
        // entries on its next write, so it deliberately re-reads per write.
        EncodingStatisticsStore(directory: tempDir).clearHistory()
        await recorder.record(EncodingStatistics(jobID: UUID(), jobName: "after-clear"))

        let persisted = await recorder.allStatistics()
        XCTAssertEqual(persisted.map(\.jobName), ["after-clear"])
    }

    // MARK: - EncodingEngine controller registry

    func test_engine_reportsNothingInFlightBeforeAnyEncodeStarts() {
        let engine = EncodingEngine()
        XCTAssertEqual(engine.activeControllerCount, 0)
        XCTAssertFalse(engine.isEncoding)
    }

    func test_engine_controlCallsAreNoOpsWhenNothingIsInFlight() {
        // Both the queue-wide and per-job forms must be safe to call when
        // no pass is registered — `cancelCurrentJob()` can race a job that
        // has just finished, which is precisely this situation.
        let engine = EncodingEngine()
        let unknownJobID = UUID()

        engine.pauseEncoding()
        engine.resumeEncoding()
        engine.stopEncoding()
        engine.pauseEncoding(jobID: unknownJobID)
        engine.resumeEncoding(jobID: unknownJobID)
        engine.stopEncoding(jobID: unknownJobID)

        XCTAssertEqual(engine.activeControllerCount, 0)
        XCTAssertFalse(engine.isEncoding)
    }
}
