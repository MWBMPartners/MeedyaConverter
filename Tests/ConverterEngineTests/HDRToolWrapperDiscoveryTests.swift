// ============================================================================
// MeedyaConverter — HDR tool wrapper discovery tests (#324/#370 follow-up)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards that DoviToolWrapper / HDR10PlusToolWrapper resolve their binary via
/// BundledToolLocator (which checks Contents/Helpers), honouring an explicit
/// override, and fall through for a non-existent override. Ordering itself is
/// covered by BundledToolLocator's own tests.
final class HDRToolWrapperDiscoveryTests: XCTestCase {

    private func tempExecutable(named name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdrtool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bin = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: bin.path,
            contents: Data("#!/bin/sh\nexit 0\n".utf8),
            attributes: [.posixPermissions: 0o755])
        return bin
    }

    func test_dovi_honoursExecutableOverride() throws {
        let bin = try tempExecutable(named: "dovi_tool")
        defer { try? FileManager.default.removeItem(at: bin.deletingLastPathComponent()) }
        XCTAssertEqual(DoviToolWrapper(binaryPath: bin.path).locateBinary(), bin.path)
    }

    func test_hdr10plus_honoursExecutableOverride() throws {
        let bin = try tempExecutable(named: "hdr10plus_tool")
        defer { try? FileManager.default.removeItem(at: bin.deletingLastPathComponent()) }
        XCTAssertEqual(HDR10PlusToolWrapper(binaryPath: bin.path).locateBinary(), bin.path)
    }

    func test_nonexistentOverrideFallsThrough() {
        XCTAssertNotEqual(DoviToolWrapper(binaryPath: "/nonexistent/dovi_tool").locateBinary(),
                          "/nonexistent/dovi_tool")
        XCTAssertNotEqual(HDR10PlusToolWrapper(binaryPath: "/nonexistent/hdr10plus_tool").locateBinary(),
                          "/nonexistent/hdr10plus_tool")
    }
}
