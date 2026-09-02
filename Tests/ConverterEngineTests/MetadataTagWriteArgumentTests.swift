// ============================================================================
// MeedyaConverter — MetadataTagEditor write-argument tests (#320)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards the metadata write arguments (#320). Two real bugs were fixed here:
/// a metadata-only write had no `-c copy` (so ffmpeg re-encoded the whole file
/// to change a tag), and an artwork write mapped ONLY the cover (`-map 1:v:0`),
/// dropping the source audio/video — the output was just the still image.
final class MetadataTagWriteArgumentTests: XCTestCase {

    private func hasPair(_ args: [String], _ f: String, _ v: String) -> Bool {
        for i in args.indices.dropLast() where args[i] == f && args[i + 1] == v { return true }
        return false
    }

    func test_metadataOnly_copiesSourceAndSetsTags_noExtraInput() {
        let args = MetadataTagEditor.buildWriteArguments(
            tags: [MediaTag(key: "title", value: "Hi"), MediaTag(key: "artist", value: "MWBM")],
            artworkPath: nil)
        XCTAssertTrue(hasPair(args, "-map", "0"), "must map all source streams: \(args)")
        XCTAssertTrue(hasPair(args, "-c", "copy"), "must copy, not re-encode: \(args)")
        XCTAssertTrue(hasPair(args, "-metadata", "title=Hi"), "\(args)")
        XCTAssertTrue(hasPair(args, "-metadata", "artist=MWBM"), "\(args)")
        XCTAssertFalse(args.contains("-i"), "no second input for a metadata-only write: \(args)")
        XCTAssertFalse(hasPair(args, "-map", "1:v:0"))
    }

    func test_withArtwork_keepsSourceStreamsAndAddsCover_inputFirst() {
        let args = MetadataTagEditor.buildWriteArguments(
            tags: [MediaTag(key: "title", value: "Hi")],
            artworkPath: "/art.jpg")
        // Source streams kept (-map 0) AND the cover mapped (-map 1:v:0).
        XCTAssertTrue(hasPair(args, "-map", "0"), "source streams must survive: \(args)")
        XCTAssertTrue(hasPair(args, "-map", "1:v:0"), "cover must be mapped: \(args)")
        XCTAssertTrue(hasPair(args, "-disposition:v:1", "attached_pic"), "\(args)")
        XCTAssertTrue(hasPair(args, "-c", "copy"), "\(args)")
        // The artwork input is emitted BEFORE the output options (unambiguous
        // input indexing: source=0, artwork=1).
        let iIndex = args.firstIndex(of: "-i")
        let mapIndex = args.firstIndex(of: "-map")
        XCTAssertNotNil(iIndex); XCTAssertNotNil(mapIndex)
        XCTAssertTrue(iIndex! < mapIndex!, "artwork -i must precede -map: \(args)")
        XCTAssertTrue(hasPair(args, "-i", "/art.jpg"), "\(args)")
    }

    func test_emptyAndWhitespaceTagsAreSkipped() {
        let args = MetadataTagEditor.buildWriteArguments(
            tags: [MediaTag(key: "", value: "x"), MediaTag(key: "k", value: "")],
            artworkPath: nil)
        XCTAssertFalse(args.contains { $0.hasPrefix("=") || $0.hasSuffix("=") }, "\(args)")
        // Only the map/copy scaffold, no -metadata entries.
        XCTAssertFalse(args.contains("-metadata"), "\(args)")
    }

    func test_artworkEmbedArguments_isMappingOnly_noInput() {
        let art = MetadataTagEditor.buildArtworkEmbedArguments()
        XCTAssertFalse(art.contains("-i"), "the -i is owned by buildWriteArguments now: \(art)")
        XCTAssertTrue(hasPair(art, "-map", "1:v:0"))
        XCTAssertTrue(hasPair(art, "-disposition:v:1", "attached_pic"))
    }
}
