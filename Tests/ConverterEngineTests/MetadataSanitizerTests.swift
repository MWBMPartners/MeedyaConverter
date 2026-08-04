// ============================================================================
// MeedyaConverter — MetadataSanitizerTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// Regression tests for `MetadataSanitizer`. Anchors T5
/// (malicious-metadata defence) per SECURITY.md finding F-006.
final class MetadataSanitizerTests: XCTestCase {

    // MARK: - Identity

    func test_sanitize_emptyString_returnsEmpty() {
        XCTAssertEqual(MetadataSanitizer.sanitize(""), "")
    }

    func test_sanitize_plainAscii_unchanged() {
        XCTAssertEqual(
            MetadataSanitizer.sanitize("My Holiday Video"),
            "My Holiday Video"
        )
    }

    func test_sanitize_unicodeBmp_unchanged() {
        XCTAssertEqual(
            MetadataSanitizer.sanitize("夏休みの動画 — 2026"),
            "夏休みの動画 — 2026"
        )
    }

    func test_sanitize_emoji_unchanged() {
        XCTAssertEqual(
            MetadataSanitizer.sanitize("Summer 🏖️ 2026 🎬"),
            "Summer 🏖️ 2026 🎬"
        )
    }

    func test_sanitize_isIdempotent() {
        let inputs = [
            "plain",
            "with\0nul",
            "vt100 \u{001B}[31m red \u{001B}[0m reset",
            "bidi \u{202E}flipped\u{202C}",
            "tab\there\nnewline\rcarriage"
        ]
        for input in inputs {
            let once = MetadataSanitizer.sanitize(input)
            let twice = MetadataSanitizer.sanitize(once)
            XCTAssertEqual(once, twice, "Not idempotent for '\(input)'")
        }
    }

    // MARK: - NUL stripping

    func test_sanitize_embeddedNul_removed() {
        XCTAssertEqual(
            MetadataSanitizer.sanitize("before\0after"),
            "beforeafter"
        )
    }

    func test_sanitize_multipleNuls_allRemoved() {
        XCTAssertEqual(
            MetadataSanitizer.sanitize("\0\0NUL\0\0BURST\0\0"),
            "NULBURST"
        )
    }

    // MARK: - C0 control codes (with TAB/LF/CR preserved)

    func test_sanitize_bell_removed() {
        // 0x07 BEL
        XCTAssertEqual(
            MetadataSanitizer.sanitize("ding\u{0007}dong"),
            "dingdong"
        )
    }

    func test_sanitize_backspace_removed() {
        // 0x08 BS — the "Trojan Source" precursor; an
        // attacker could use this to hide visible characters.
        XCTAssertEqual(
            MetadataSanitizer.sanitize("apparent\u{0008}h\u{0008}h\u{0008}rest"),
            "apparenthhrest"
        )
    }

    func test_sanitize_tab_preserved() {
        XCTAssertEqual(
            MetadataSanitizer.sanitize("col1\tcol2"),
            "col1\tcol2"
        )
    }

    func test_sanitize_lf_preserved() {
        XCTAssertEqual(
            MetadataSanitizer.sanitize("line1\nline2"),
            "line1\nline2"
        )
    }

    func test_sanitize_cr_preserved() {
        XCTAssertEqual(
            MetadataSanitizer.sanitize("line1\rline2"),
            "line1\rline2"
        )
    }

    func test_sanitize_crlf_preserved() {
        XCTAssertEqual(
            MetadataSanitizer.sanitize("line1\r\nline2"),
            "line1\r\nline2"
        )
    }

    func test_sanitize_verticalTab_removed() {
        // 0x0B VT
        XCTAssertEqual(
            MetadataSanitizer.sanitize("a\u{000B}b"),
            "ab"
        )
    }

    func test_sanitize_formFeed_removed() {
        // 0x0C FF
        XCTAssertEqual(
            MetadataSanitizer.sanitize("a\u{000C}b"),
            "ab"
        )
    }

    func test_sanitize_escape_removed() {
        // 0x1B ESC — the leading byte of every ANSI / VT100
        // escape sequence. Stripping it neutralises the whole
        // family (`[31m` etc.).
        XCTAssertEqual(
            MetadataSanitizer.sanitize("\u{001B}[31mRED\u{001B}[0m"),
            "[31mRED[0m"
        )
    }

    func test_sanitize_del_removed() {
        // 0x7F DEL
        XCTAssertEqual(
            MetadataSanitizer.sanitize("a\u{007F}b"),
            "ab"
        )
    }

    // MARK: - Bidirectional override (Trojan Source family)

    func test_sanitize_rightToLeftOverride_removed() {
        // U+202E RLO — the classic Trojan Source trick. A
        // filename like `innocent\u{202E}cod.exe` displays as
        // `innocenttxe.doc` in most renderers.
        let attacker = "innocent\u{202E}txt.exe"
        let sanitised = MetadataSanitizer.sanitize(attacker)
        XCTAssertFalse(sanitised.unicodeScalars.contains { $0.value == 0x202E })
        XCTAssertEqual(sanitised, "innocenttxt.exe")
    }

    func test_sanitize_allBidiOverrides_removed() {
        // U+202A–U+202E + U+2066–U+2069: the full set of
        // direction-flip codepoints recognised by Unicode 16's
        // BIDI algorithm.
        let bidiCodepoints: [UnicodeScalar] = [
            UnicodeScalar(0x202A)!, UnicodeScalar(0x202B)!,
            UnicodeScalar(0x202C)!, UnicodeScalar(0x202D)!,
            UnicodeScalar(0x202E)!, UnicodeScalar(0x2066)!,
            UnicodeScalar(0x2067)!, UnicodeScalar(0x2068)!,
            UnicodeScalar(0x2069)!,
        ]
        var input = String()
        for s in bidiCodepoints {
            input.append("X")
            input.unicodeScalars.append(s)
        }
        input.append("X")

        let sanitised = MetadataSanitizer.sanitize(input)
        XCTAssertEqual(sanitised, "XXXXXXXXXX")
    }

    // MARK: - Combined attacker payloads

    func test_sanitize_combinedAttackerPayload_neutralised() {
        // The kind of "title" a malicious .mkv might carry:
        // NUL bytes to split the visible string, VT100 to
        // forge fake red error text, BIDI override to swap
        // the file extension.
        let attacker = "Inv\u{0000}oice\u{001B}[31m URGENT\u{001B}[0m \u{202E}fdp.exe"
        let sanitised = MetadataSanitizer.sanitize(attacker)
        XCTAssertFalse(sanitised.contains("\0"))
        XCTAssertFalse(sanitised.unicodeScalars.contains { $0.value == 0x001B })
        XCTAssertFalse(sanitised.unicodeScalars.contains { $0.value == 0x202E })
        // Visible text is preserved (minus the now-stripped controls).
        XCTAssertEqual(sanitised, "Invoice[31m URGENT[0m fdp.exe")
    }

    // MARK: - C1 controls + Unicode line/paragraph separators (review fix)

    func test_sanitize_nel_removed() {
        // U+0085 NEL — treated as a line break by many renderers.
        XCTAssertEqual(MetadataSanitizer.sanitize("a\u{0085}b"), "ab")
    }

    func test_sanitize_csi_removed() {
        // U+009B CSI — the 8-bit ANSI control-sequence introducer.
        XCTAssertEqual(MetadataSanitizer.sanitize("a\u{009B}31mb"), "a31mb")
    }

    func test_sanitize_allC1Controls_removed() {
        var input = "x"
        for cp in 0x80...0x9F {
            input.unicodeScalars.append(UnicodeScalar(cp)!)
            input.append("x")
        }
        let sanitised = MetadataSanitizer.sanitize(input)
        XCTAssertFalse(sanitised.unicodeScalars.contains { (0x80...0x9F).contains(Int($0.value)) })
        // 32 C1 codepoints stripped, 33 'x' preserved.
        XCTAssertEqual(sanitised, String(repeating: "x", count: 33))
    }

    func test_sanitize_lineSeparator_removed() {
        // U+2028 LS / U+2029 PS — hard line breaks in many renderers.
        XCTAssertEqual(MetadataSanitizer.sanitize("a\u{2028}b\u{2029}c"), "abc")
    }

    func test_sanitize_lineParagraphSeparator_forgeryNeutralised() {
        // The exact F-006 scenario the review flagged: a title that
        // uses U+2028 to forge a fake error line.
        let attacker = "Real Title\u{2028}ERROR: encode failed"
        let sanitised = MetadataSanitizer.sanitize(attacker)
        XCTAssertFalse(sanitised.unicodeScalars.contains { $0.value == 0x2028 })
        XCTAssertEqual(sanitised, "Real TitleERROR: encode failed")
    }

    func test_sanitize_stillKeepsLegitimateLineBreaks() {
        // LF/CR/TAB remain (multi-line comment tags are legitimate).
        XCTAssertEqual(MetadataSanitizer.sanitize("line1\nline2\r\tcol"), "line1\nline2\r\tcol")
    }

    // MARK: - sanitizeSingleLine (review fix — F-008 newline injection)

    func test_sanitizeSingleLine_collapsesNewlinesToSpace() {
        XCTAssertEqual(
            MetadataSanitizer.sanitizeSingleLine("bogus\nERROR: overwrote X"),
            "bogus ERROR: overwrote X"
        )
    }

    func test_sanitizeSingleLine_collapsesCRAndTab() {
        XCTAssertEqual(
            MetadataSanitizer.sanitizeSingleLine("a\r\nb\tc"),
            "a b c"
        )
    }

    func test_sanitizeSingleLine_coalescesRunsOfWhitespace() {
        XCTAssertEqual(
            MetadataSanitizer.sanitizeSingleLine("a\n\n\n   b"),
            "a b"
        )
    }

    func test_sanitizeSingleLine_stripsControlsLikeSanitize() {
        // Still strips everything sanitize() does.
        let out = MetadataSanitizer.sanitizeSingleLine("a\u{0000}\u{001B}\u{202E}\u{2028}b")
        XCTAssertEqual(out, "ab")
    }

    func test_sanitizeSingleLine_hasNoLineBreakScalars() {
        let out = MetadataSanitizer.sanitizeSingleLine("x\ny\rz\u{2028}w\u{0085}v")
        XCTAssertFalse(out.unicodeScalars.contains {
            [0x0A, 0x0D, 0x2028, 0x2029, 0x0085].contains(Int($0.value))
        })
    }
}
