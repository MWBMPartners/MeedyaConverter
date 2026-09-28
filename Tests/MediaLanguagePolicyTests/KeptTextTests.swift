// ============================================================================
// MeedyaConverter — MediaLanguagePolicyTests / KeptTextTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// LANG-026: a malformed value is kept, not dropped — and the text it keeps is
// the value AFTER LANG-001 step 1's trim (settled in core revision 6). So
// `" en_US "` keeps `en_US`, and a value of nothing but space, tab, line feed
// and carriage return keeps the empty text. The shared cases only give a
// malformed value's answer (null), never its kept text, so this file holds
// the check. Before revision 6 the Swift code kept the UNtrimmed text for a
// value of only whitespace.
// ============================================================================

import Foundation
import XCTest
@testable import MediaLanguagePolicy

final class KeptTextTests: XCTestCase {

    private func canonicaliser() throws -> LanguageTagCanonicaliser {
        try MediaLanguagePolicy.shared.get().canonicaliser
    }

    func test_malformedValueKeepsItsTextAfterTheTrim() throws {
        let tag = try canonicaliser().canonicalise(" en_US \t")
        XCTAssertTrue(tag.isMalformed)
        XCTAssertEqual(tag.text, "en_US")
    }

    func test_valueOfOnlyWhitespaceKeepsTheEmptyText() throws {
        for value in ["", " ", "\t", " \t\n\r "] {
            let tag = try canonicaliser().canonicalise(value)
            XCTAssertTrue(tag.isMalformed, value.debugDescription)
            XCTAssertEqual(tag.text, "", value.debugDescription)
        }
    }

    /// Only those four characters are trimmed: a no-break space stays part
    /// of the value (canon-43's point), and so of the kept text.
    func test_otherSpacesAreKept() throws {
        let tag = try canonicaliser().canonicalise("\u{00A0}en")
        XCTAssertTrue(tag.isMalformed)
        XCTAssertEqual(tag.text, "\u{00A0}en")
    }
}
