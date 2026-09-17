// ============================================================================
// MeedyaConverter — MakeMKVBackendTests (Issue #503)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pure, CI-safe coverage for the *optional, opt-in* MakeMKV backend (slice 1):
// argument builders, robot-mode field splitting, and info/progress/message
// parsing — all against canned text. NOTHING here launches makemkvcon, locates
// a binary, enables the feature, or touches a device; slice 1 is pure by design.
//
// It also pins the invariant that matters most for #503's acceptance criteria:
// slice 1 changes NO policy, so MeedyaConverter's copy-protection refuse-gate
// (`DiscProtectionDetector`, #492) still refuses protected discs. Public API
// only; no `@testable import`.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class MakeMKVBackendTests: XCTestCase {

    // MARK: - Argument builders (info)

    func test_buildInfoArguments_minimalDefaults() {
        let args = MakeMKVBackend.buildInfoArguments(source: .disc(0))
        XCTAssertEqual(args, ["-r", "info", "disc:0"])
    }

    func test_buildInfoArguments_allOptionsInOrder() {
        let args = MakeMKVBackend.buildInfoArguments(
            source: .disc(0),
            noScan: true,
            minLengthSeconds: 60,
            cacheSizeMB: 1024
        )
        // Global options MUST precede the `info` command, and `info`'s source
        // MUST be last.
        XCTAssertEqual(args, ["-r", "--noscan", "--cache=1024", "--minlength=60", "info", "disc:0"])
    }

    func test_buildInfoArguments_nonRobotAndDeviceSource() {
        let args = MakeMKVBackend.buildInfoArguments(source: .device("/dev/sr0"), robotMode: false)
        XCTAssertEqual(args, ["info", "dev:/dev/sr0"])
    }

    // MARK: - Argument builders (mkv / rip)

    func test_buildRipArguments_defaultsAllTitles() {
        let args = MakeMKVBackend.buildRipArguments(
            source: .disc(0),
            titles: .all,
            destinationDirectory: "/out"
        )
        XCTAssertEqual(args, ["-r", "--progress=-same", "mkv", "disc:0", "all", "/out"])
    }

    func test_buildRipArguments_singleTitleFileSourceNoProgress() {
        let args = MakeMKVBackend.buildRipArguments(
            source: .file("/x/BDMV"),
            titles: .index(3),
            destinationDirectory: "/out",
            noScan: true,
            minLengthSeconds: 120,
            cacheSizeMB: 512,
            showProgress: false
        )
        XCTAssertEqual(
            args,
            ["-r", "--noscan", "--cache=512", "--minlength=120", "mkv", "file:/x/BDMV", "3", "/out"]
        )
        // The destination directory must always be the final positional argument.
        XCTAssertEqual(args.last, "/out")
    }

    // MARK: - Argument builders (backup)

    func test_buildBackupArguments_decryptByDefault() {
        let args = MakeMKVBackend.buildBackupArguments(source: .disc(0), destinationDirectory: "/bk")
        XCTAssertEqual(args, ["-r", "--progress=-same", "backup", "--decrypt", "disc:0", "/bk"])
    }

    func test_buildBackupArguments_withoutDecrypt() {
        let args = MakeMKVBackend.buildBackupArguments(
            source: .iso("/img.iso"),
            destinationDirectory: "/bk",
            decrypt: false,
            showProgress: false
        )
        XCTAssertEqual(args, ["-r", "backup", "iso:/img.iso", "/bk"])
    }

    // MARK: - Robot-field splitting

    func test_parseRobotFields_quotedCommasAndEscapedQuotes() {
        XCTAssertEqual(
            MakeMKVBackend.parseRobotFields(#""a""b",5,"c,d""#),
            [#"a"b"#, "5", "c,d"]
        )
    }

    func test_parseRobotFields_emptyAndBlankFields() {
        XCTAssertEqual(MakeMKVBackend.parseRobotFields(""), [""])
        XCTAssertEqual(MakeMKVBackend.parseRobotFields("1,,3"), ["1", "", "3"])
        XCTAssertEqual(MakeMKVBackend.parseRobotFields(#"1,"",3"#), ["1", "", "3"])
    }

    // MARK: - Info parsing (round-trip on a realistic transcript)

    private let sampleInfo = """
    DRV:0,2,999,12,"BD-RE MATSHITA BD-MLT UJ-260","Big Movie","/dev/rdisk2"
    DRV:1,256,999,0,"","",""
    MSG:1005,0,1,"MakeMKV v1.17.7 started","%1 started","v1.17.7"
    TCOUNT:2
    CINFO:1,6209,"Blu-ray disc"
    CINFO:2,0,"Big Movie, Special Edition"
    CINFO:32,0,"BIG_MOVIE"
    TINFO:0,2,0,"Big Movie, Special Edition"
    TINFO:0,8,0,"12"
    TINFO:0,9,0,"1:57:21"
    TINFO:0,10,0,"26.5 GB"
    TINFO:0,11,0,"28468910080"
    TINFO:0,16,0,"00800.mpls"
    SINFO:0,0,1,6201,"Video"
    SINFO:0,0,6,0,"MPEG-4 AVC"
    SINFO:0,1,1,6202,"Audio"
    SINFO:0,1,3,0,"eng"
    SINFO:0,1,6,0,"DTS-HD MA"
    TINFO:1,9,0,"0:04:12"
    """

    func test_parseInfo_discAndTitleAttributes() {
        let info = MakeMKVBackend.parseInfo(sampleInfo)

        XCTAssertEqual(info.expectedTitleCount, 2)
        XCTAssertEqual(info.discName, "Big Movie, Special Edition") // comma inside quotes survives
        XCTAssertEqual(info.volumeName, "BIG_MOVIE")

        XCTAssertEqual(info.titles.count, 2)
        let first = info.titles[0]
        XCTAssertEqual(first.index, 0)
        XCTAssertEqual(first.name, "Big Movie, Special Edition")
        XCTAssertEqual(first.chapterCount, 12)
        XCTAssertEqual(first.duration, "1:57:21")
        XCTAssertEqual(first.durationSeconds, 7041) // 1*3600 + 57*60 + 21
        XCTAssertEqual(first.sizeText, "26.5 GB")
        XCTAssertEqual(first.sizeBytes, 28_468_910_080)
        XCTAssertEqual(first.sourceFileName, "00800.mpls")

        let second = info.titles[1]
        XCTAssertEqual(second.index, 1)
        XCTAssertEqual(second.durationSeconds, 252) // 4*60 + 12
    }

    func test_parseInfo_streamsSortedWithConvenienceAccessors() {
        let info = MakeMKVBackend.parseInfo(sampleInfo)
        let streams = info.titles[0].streams
        XCTAssertEqual(streams.count, 2)
        XCTAssertEqual(streams[0].index, 0)
        XCTAssertEqual(streams[0].typeName, "Video")
        XCTAssertEqual(streams[0].codecShort, "MPEG-4 AVC")
        XCTAssertEqual(streams[1].typeName, "Audio")
        XCTAssertEqual(streams[1].languageCode, "eng")
        XCTAssertEqual(streams[1].codecShort, "DTS-HD MA")
    }

    func test_parseInfo_drives() {
        let info = MakeMKVBackend.parseInfo(sampleInfo)
        XCTAssertEqual(info.drives.count, 2)
        XCTAssertEqual(info.drives[0].index, 0)
        XCTAssertEqual(info.drives[0].driveName, "BD-RE MATSHITA BD-MLT UJ-260")
        XCTAssertEqual(info.drives[0].discName, "Big Movie")
        XCTAssertEqual(info.drives[0].devicePath, "/dev/rdisk2")
        XCTAssertTrue(info.drives[0].hasDisc)
        XCTAssertFalse(info.drives[1].hasDisc)
    }

    func test_parseInfo_unknownAttributeIdPreservedNotDropped() {
        // id 9999 is not named in MakeMKVAttributeID; it must still be kept raw.
        let info = MakeMKVBackend.parseInfo("TINFO:0,9999,0,\"custom\"")
        XCTAssertEqual(info.titles.count, 1)
        XCTAssertEqual(info.titles[0].attributes.first?.id, 9999)
        XCTAssertEqual(info.titles[0].attributes.first?.value, "custom")
        XCTAssertNil(info.titles[0].attributes.first?.attribute) // unrecognised → nil name
    }

    func test_parseInfo_malformedLinesSkippedGracefully() {
        let info = MakeMKVBackend.parseInfo("garbage without a colon\nTCOUNT:notanumber\nTINFO:0,2,0,\"Only Title\"")
        XCTAssertNil(info.expectedTitleCount) // "notanumber" is ignored
        XCTAssertEqual(info.titles.count, 1)
        XCTAssertEqual(info.titles[0].name, "Only Title")
    }

    // MARK: - Progress parsing

    func test_parseProgressLine_values() {
        let event = MakeMKVBackend.parseProgressLine("PRGV:16384,32768,65536")
        XCTAssertEqual(event, .values(current: 16384, total: 32768, max: 65536))
        XCTAssertEqual(event?.totalFraction, 0.5)
        XCTAssertEqual(event?.currentFraction, 0.25)
    }

    func test_parseProgressLine_captions() {
        XCTAssertEqual(
            MakeMKVBackend.parseProgressLine(#"PRGC:5018,0,"Analyzing seamless segments""#),
            .currentTitle(code: 5018, id: 0, name: "Analyzing seamless segments")
        )
        XCTAssertEqual(
            MakeMKVBackend.parseProgressLine(#"PRGT:5017,0,"Saving all titles to MKV files""#),
            .totalTitle(code: 5017, id: 0, name: "Saving all titles to MKV files")
        )
    }

    func test_parseProgressLine_ignoresNonProgress() {
        XCTAssertNil(MakeMKVBackend.parseProgressLine("MSG:1,0,0,\"hi\",\"hi\""))
        XCTAssertNil(MakeMKVBackend.parseProgressLine("no colon here"))
    }

    func test_progressEvent_zeroMaxHasNoFraction() {
        XCTAssertNil(MakeMKVProgressEvent.values(current: 1, total: 1, max: 0).totalFraction)
    }

    func test_parseProgressLine_toleratesTrailingCarriageReturn() {
        // A caller that hand-splits streamed stdout on "\n" alone keeps the "\r";
        // it must not defeat the final-field Int parse.
        XCTAssertEqual(
            MakeMKVBackend.parseProgressLine("PRGV:16384,32768,65536\r"),
            .values(current: 16384, total: 32768, max: 65536)
        )
    }

    // MARK: - Message parsing

    func test_parseMessageLine_withParameters() {
        let message = MakeMKVBackend.parseMessageLine(#"MSG:3007,0,1,"Using direct disc access mode","Using %1 mode","direct disc access""#)
        XCTAssertEqual(message?.code, 3007)
        XCTAssertEqual(message?.flags, 0)
        XCTAssertEqual(message?.text, "Using direct disc access mode")
        XCTAssertEqual(message?.rawFormat, "Using %1 mode")
        XCTAssertEqual(message?.parameters, ["direct disc access"])
    }

    func test_parseMessageLine_ignoresNonMessage() {
        XCTAssertNil(MakeMKVBackend.parseMessageLine("PRGV:1,2,3"))
    }

    // MARK: - Duration helper

    func test_parseDuration_variants() {
        XCTAssertEqual(MakeMKVBackend.parseDuration("1:57:21"), 7041)
        XCTAssertEqual(MakeMKVBackend.parseDuration("0:04:12"), 252)
        XCTAssertEqual(MakeMKVBackend.parseDuration("57:21"), 3441)
        XCTAssertNil(MakeMKVBackend.parseDuration("abc"))
        XCTAssertNil(MakeMKVBackend.parseDuration("1:2:3:4"))
        XCTAssertNil(MakeMKVBackend.parseDuration(""))
    }

    // MARK: - INVARIANT: slice 1 changes no policy — DRM gate still refuses

    func test_drmRefuseGate_unchangedForProtectedDiscs() {
        // The MakeMKV backend is pure and never consults the detector, so the
        // shared refuse-gate must be exactly as before: every protected class is
        // refused, and the reason still states we never circumvent protection.
        let protectedTypes: [DiscProtectionType] = [.css, .aacs, .bdPlus, .aacs2, .unknownStructural]
        for type in protectedTypes {
            guard case .refuse(let reason) = DiscProtectionDetector.policy(for: type) else {
                XCTFail("protected type \(type) must be refused by the imaging gate")
                continue
            }
            XCTAssertTrue(
                reason.contains("never circumvents"),
                "refusal reason should still state we never circumvent protection, got: \(reason)"
            )
        }
    }

    func test_drmGate_proceedsForUnprotectedDisc() {
        guard case .proceed = DiscProtectionDetector.policy(for: .none) else {
            return XCTFail("an unprotected disc should still be allowed to proceed")
        }
    }
}
