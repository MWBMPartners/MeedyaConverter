// ============================================================================
// MeedyaConverter — CheckpointManager tests (#468)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards the checkpoint persistence that periodic crash-safe checkpointing
/// (#468) relies on: save -> load -> delete round trips, and that a completed
/// job's checkpoint can be removed so it stops appearing as resumable.
final class CheckpointManagerTests: XCTestCase {

    private func tempManager() -> (CheckpointManager, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-ckpt-\(UUID().uuidString)")
        return (CheckpointManager(storageDirectory: dir), dir)
    }

    private func checkpoint(_ id: UUID, fraction: Double) -> EncodingCheckpoint {
        EncodingCheckpoint(
            jobId: id,
            inputURL: URL(fileURLWithPath: "/tmp/in.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/out.mp4"),
            profileSnapshot: .webStandard,
            lastGoodTimestamp: fraction * 100,
            progressFraction: fraction
        )
    }

    func test_saveLoadRoundTrip() throws {
        let (mgr, dir) = tempManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try mgr.saveCheckpoint(checkpoint(id, fraction: 0.25))
        let loaded = mgr.loadCheckpoint(for: id)
        XCTAssertEqual(loaded?.jobId, id)
        XCTAssertEqual(loaded?.progressFraction, 0.25)
    }

    /// A later save for the same job overwrites the earlier one — this is what
    /// makes periodic (every-5%) checkpointing cheap and correct.
    func test_saveOverwritesSameJob() throws {
        let (mgr, dir) = tempManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try mgr.saveCheckpoint(checkpoint(id, fraction: 0.10))
        try mgr.saveCheckpoint(checkpoint(id, fraction: 0.55))
        XCTAssertEqual(mgr.loadCheckpoint(for: id)?.progressFraction, 0.55)
        XCTAssertEqual(mgr.listResumableCheckpoints().count, 1, "same job must not duplicate")
    }

    /// Deleting a completed job's checkpoint stops it being listed as resumable.
    func test_deleteRemovesFromResumable() throws {
        let (mgr, dir) = tempManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = UUID(), remove = UUID()
        try mgr.saveCheckpoint(checkpoint(keep, fraction: 0.3))
        try mgr.saveCheckpoint(checkpoint(remove, fraction: 0.4))
        mgr.deleteCheckpoint(for: remove)
        let ids = Set(mgr.listResumableCheckpoints().map(\.jobId))
        XCTAssertTrue(ids.contains(keep))
        XCTAssertFalse(ids.contains(remove))
    }
}
