// ============================================================================
// MeedyaConverter — ProfileTrackOrderTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The language policy's stored track order (TRACK-050/060) is on by default
// for every new output, and can be switched off per profile, per job, and
// from the command line (`--keep-track-order`). Added after the independent
// review of the language policy work (item 7): it could not be switched off
// anywhere a person could reach.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

final class ProfileTrackOrderTests: XCTestCase {

    /// Video, then English audio, then the Japanese ORIGINAL audio: the
    /// policy's order puts the original first (`0:2` before `0:1`); with the
    /// order off, each kind of track keeps the source's order.
    private let sources = [
        MediaStream(streamIndex: 0, streamType: .video, disposition: StreamDisposition()),
        MediaStream(streamIndex: 1, streamType: .audio, language: "en", disposition: StreamDisposition()),
        MediaStream(streamIndex: 2, streamType: .audio, language: "ja", disposition: StreamDisposition(isOriginal: true))
    ]

    private func maps(_ profile: EncodingProfile, jobOrder: Bool? = nil) -> [String] {
        var job = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/in.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/out.mkv"),
            profile: profile
        )
        job.sourceStreams = sources
        job.orderTracksCanonically = jobOrder
        let args = job.buildArguments()
        return zip(args, args.dropFirst()).filter { $0.0 == "-map" }.map(\.1)
    }

    func test_onByDefault() {
        XCTAssertNil(EncodingProfile.remuxToMKV.orderTracksCanonically)
        XCTAssertEqual(maps(.remuxToMKV), ["0:0", "0:2", "0:1"])
    }

    func test_profileCanSwitchItOff() {
        var profile = EncodingProfile.remuxToMKV
        profile.orderTracksCanonically = false
        XCTAssertEqual(maps(profile), ["0:0", "0:1", "0:2"], "the source's order")
    }

    /// The job's own choice wins over the profile's, both ways.
    func test_jobOverridesTheProfile() {
        XCTAssertEqual(maps(.remuxToMKV, jobOrder: false), ["0:0", "0:1", "0:2"], "--keep-track-order")
        var off = EncodingProfile.remuxToMKV
        off.orderTracksCanonically = false
        XCTAssertEqual(maps(off, jobOrder: true), ["0:0", "0:2", "0:1"])
    }

    /// A profile saved before the setting existed has no key for it, and is
    /// read as ON; one saved with it off stays off.
    func test_savedProfilesDecode() throws {
        var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EncodingProfile.remuxToMKV)) as? [String: Any] ?? [:]
        saved.removeValue(forKey: "orderTracksCanonically")
        let old = try JSONDecoder().decode(EncodingProfile.self, from: JSONSerialization.data(withJSONObject: saved))
        XCTAssertNil(old.orderTracksCanonically)
        XCTAssertEqual(maps(old), ["0:0", "0:2", "0:1"], "an older profile orders tracks")

        var off = EncodingProfile.remuxToMKV
        off.orderTracksCanonically = false
        let reread = try JSONDecoder().decode(EncodingProfile.self, from: JSONEncoder().encode(off))
        XCTAssertEqual(reread.orderTracksCanonically, false)
    }

    /// Importing a shared profile keeps the setting (the import rebuilds a
    /// profile field by field).
    func test_profileImportKeepsTheSetting() throws {
        var off = EncodingProfile.remuxToMKV
        off.orderTracksCanonically = false
        let imported = try ProfileSharing.importFromJSON(JSONEncoder().encode(off))
        XCTAssertEqual(imported.orderTracksCanonically, false)
    }

    /// A job saved before the job-level setting existed still loads.
    func test_olderSavedJobStillDecodes() throws {
        let job = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/in.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/out.mkv"),
            profile: .remuxToMKV
        )
        var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any] ?? [:]
        saved.removeValue(forKey: "orderTracksCanonically")
        let old = try JSONDecoder().decode(EncodingJobConfig.self, from: JSONSerialization.data(withJSONObject: saved))
        XCTAssertNil(old.orderTracksCanonically)
    }
}
