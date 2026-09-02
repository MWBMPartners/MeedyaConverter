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

    /// A manager over a unique temp dir, plus a REAL input file inside it.
    /// `listResumableCheckpoints()` deliberately filters out checkpoints whose
    /// source file no longer exists (you can't resume an encode of a file that
    /// is gone), so the tests must point at an input that actually exists.
    private func tempContext() -> (CheckpointManager, URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-ckpt-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let input = dir.appendingPathComponent("in.mov")
        FileManager.default.createFile(atPath: input.path, contents: Data([0x00]))
        return (CheckpointManager(storageDirectory: dir), dir, input)
    }

    private func checkpoint(_ id: UUID, fraction: Double, input: URL) -> EncodingCheckpoint {
        EncodingCheckpoint(
            jobId: id,
            inputURL: input,
            outputURL: URL(fileURLWithPath: "/tmp/out.mp4"),
            profileSnapshot: .webStandard,
            lastGoodTimestamp: fraction * 100,
            progressFraction: fraction
        )
    }

    func test_saveLoadRoundTrip() throws {
        let (mgr, dir, input) = tempContext()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try mgr.saveCheckpoint(checkpoint(id, fraction: 0.25, input: input))
        let loaded = mgr.loadCheckpoint(for: id)
        XCTAssertEqual(loaded?.jobId, id)
        XCTAssertEqual(loaded?.progressFraction, 0.25)
    }

    /// A later save for the same job overwrites the earlier one — this is what
    /// makes periodic (every-5%) checkpointing cheap and correct.
    func test_saveOverwritesSameJob() throws {
        let (mgr, dir, input) = tempContext()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try mgr.saveCheckpoint(checkpoint(id, fraction: 0.10, input: input))
        try mgr.saveCheckpoint(checkpoint(id, fraction: 0.55, input: input))
        XCTAssertEqual(mgr.loadCheckpoint(for: id)?.progressFraction, 0.55)
        XCTAssertEqual(mgr.listResumableCheckpoints().count, 1, "same job must not duplicate")
    }

    /// Deleting a completed job's checkpoint stops it being listed as resumable.
    func test_deleteRemovesFromResumable() throws {
        let (mgr, dir, input) = tempContext()
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = UUID(), remove = UUID()
        try mgr.saveCheckpoint(checkpoint(keep, fraction: 0.3, input: input))
        try mgr.saveCheckpoint(checkpoint(remove, fraction: 0.4, input: input))
        mgr.deleteCheckpoint(for: remove)
        let ids = Set(mgr.listResumableCheckpoints().map(\.jobId))
        XCTAssertTrue(ids.contains(keep))
        XCTAssertFalse(ids.contains(remove))
    }
}
