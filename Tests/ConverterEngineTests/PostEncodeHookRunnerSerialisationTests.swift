// ============================================================================
// MeedyaConverter — PostEncodeHookRunner serialisation tests (#361 follow-up)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Regression tests for the reentrant-actor defect class.
///
/// `PostEncodeHookRunner` promises that post-encode action chains run "strictly
/// one at a time" even when several jobs finish together. An earlier version
/// tried to achieve that with actor isolation alone — which does NOT serialise,
/// because Swift actors are reentrant: an isolated method whose whole body is
/// one `await` releases the actor and lets a second call in. These tests pin the
/// real guarantee (tail-task chaining), so a future refactor that reintroduces
/// the reentrancy bug fails CI.
final class PostEncodeHookRunnerSerialisationTests: XCTestCase {

    /// Collects execution spans and flags any overlap.
    private actor Ledger {
        private var active = 0
        private(set) var sawOverlap = false
        private(set) var order: [String] = []

        func enter(_ id: String) {
            active += 1
            if active > 1 { sawOverlap = true }
            order.append(id)
        }
        func leave() { active -= 1 }
    }

    private func oneActionChain() -> PostEncodeActionChain {
        PostEncodeActionChain(actions: [
            PostEncodeAction(type: .openInFinder, name: "t", isEnabled: true)
        ])
    }

    /// Concurrently-fired chains must execute one at a time (no overlap) and in
    /// the order they were enqueued (FIFO). A non-serialising runner would let
    /// the deliberately-staggered sleeps interleave.
    func test_concurrentRuns_serialiseInFifoOrder() async {
        let runner = PostEncodeHookRunner()
        let ledger = Ledger()

        // Later-enqueued chains sleep LESS, so if execution were concurrent the
        // completion order would invert; serialisation forces A, B, C.
        let delays: [(String, UInt64)] = [("A", 40_000_000), ("B", 20_000_000), ("C", 5_000_000)]
        for (id, delay) in delays {
            await runner.run(
                chain: oneActionChain(),
                inputURL: URL(fileURLWithPath: "/tmp/in.mov"),
                outputURL: URL(fileURLWithPath: "/tmp/out.mp4"),
                success: true,
                actionExecutor: { _, _ in
                    await ledger.enter(id)
                    try? await Task.sleep(nanoseconds: delay)
                    await ledger.leave()
                }
            )
        }

        await runner.drain()

        let overlapped = await ledger.sawOverlap
        let order = await ledger.order
        XCTAssertFalse(overlapped, "chains overlapped — the runner is not serialising (reentrant-actor bug)")
        XCTAssertEqual(order, ["A", "B", "C"], "chains did not run in FIFO order: \(order)")
    }

    /// drain() must wait for every enqueued chain to finish.
    func test_drain_waitsForAll() async {
        let runner = PostEncodeHookRunner()
        let ledger = Ledger()
        for id in ["x", "y", "z"] {
            await runner.run(
                chain: oneActionChain(),
                inputURL: URL(fileURLWithPath: "/tmp/in.mov"),
                outputURL: URL(fileURLWithPath: "/tmp/out.mp4"),
                success: true,
                actionExecutor: { _, _ in
                    try? await Task.sleep(nanoseconds: 5_000_000)
                    await ledger.enter(id)
                    await ledger.leave()
                }
            )
        }
        await runner.drain()
        let count = await ledger.order.count
        XCTAssertEqual(count, 3, "drain() returned before all chains finished")
    }
}
