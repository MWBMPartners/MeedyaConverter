// ============================================================================
// MeedyaConverter — TeamProfileManager conflict tests (#482)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards the conflict diff that makes the Team Profiles "Conflicts" section
/// renderable (#482) — it was previously always empty.
final class TeamProfileConflictTests: XCTestCase {

    private let manager = TeamProfileManager()

    /// Same id, differing content (via `description`) — the profile is Hashable,
    /// so the comparison is over the whole value.
    private func profile(_ id: UUID, name: String, version: String) -> EncodingProfile {
        EncodingProfile(id: id, name: name, description: version)
    }

    /// A remote profile sharing an id with a local one but differing is a conflict.
    func test_detectConflicts_flagsDifferingSameId() {
        let id = UUID()
        let local = [profile(id, name: "Web", version: "v1")]
        let remote = [profile(id, name: "Web", version: "v2")]
        XCTAssertEqual(manager.detectConflicts(local: local, remote: remote).map(\.id), [id])
    }

    /// Identical content (same id, same values) is NOT a conflict.
    func test_detectConflicts_identicalIsNotAConflict() {
        let id = UUID()
        let same = profile(id, name: "Web", version: "v1")
        XCTAssertTrue(manager.detectConflicts(local: [same], remote: [same]).isEmpty)
    }

    /// A remote profile with a brand-new id is an addition, not a conflict.
    func test_detectConflicts_newRemoteIsNotAConflict() {
        let local = [profile(UUID(), name: "Web", version: "v1")]
        let remote = [profile(UUID(), name: "Archive", version: "v1")]
        XCTAssertTrue(manager.detectConflicts(local: local, remote: remote).isEmpty)
    }

    /// Only the conflicting subset is returned, preserving remote order.
    func test_detectConflicts_returnsOnlyConflictingSubset() {
        let shared = UUID()
        let local = [profile(shared, name: "A", version: "v1"), profile(UUID(), name: "B", version: "v1")]
        let remote = [
            profile(UUID(), name: "C", version: "v1"),   // new — not a conflict
            profile(shared, name: "A", version: "v2"),   // conflict
        ]
        XCTAssertEqual(manager.detectConflicts(local: local, remote: remote).map(\.id), [shared])
    }
}
