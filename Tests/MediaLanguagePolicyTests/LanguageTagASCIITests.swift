// ============================================================================
// MeedyaConverter — MediaLanguagePolicyTests / LanguageTagASCIITests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// A BCP 47 tag is ASCII only (RFC 5646), and tags are compared with ASCII
// case rules. The canonicaliser used to lower-case with Swift's Unicode rules
// before looking a value up in the grandfathered table; Unicode turns the
// Kelvin sign (U+212A) into a plain `k`, so `i-\u{212A}lingon` matched
// `i-klingon` and came out as the language `tlh`. Found by the independent
// review of the language policy work. The shared conformance cases have no
// non-ASCII grandfathered case, so this file holds the check.
// ============================================================================

import Foundation
import XCTest
@testable import MediaLanguagePolicy

final class LanguageTagASCIITests: XCTestCase {

    private func canonicaliser() throws -> LanguageTagCanonicaliser {
        switch MediaLanguagePolicy.shared {
        case .success(let policy): return policy.canonicaliser
        case .failure(let error): throw error
        }
    }

    /// The review's case: the Kelvin sign is not a `k`.
    func test_nonASCIILookAlikeIsMalformedNotGrandfathered() throws {
        let tag = try canonicaliser().canonicalise("i-\u{212A}lingon")
        XCTAssertEqual(tag.kind, .malformed)
        XCTAssertNil(tag.canonical)
        XCTAssertEqual(tag.text, "i-\u{212A}lingon", "the text is kept, never repaired (LANG-026)")
    }

    /// Any non-ASCII character makes a value malformed — including ones
    /// whose Unicode lower case is ASCII (the Kelvin sign; the dotted
    /// capital I, which lower-cases to `i` plus a combining dot).
    func test_anyNonASCIIIsMalformed() throws {
        for value in ["\u{212A}o", "en-\u{212A}", "\u{0130}-default", "ｅｎ", "de-ÄT"] {
            XCTAssertEqual(try canonicaliser().canonicalise(value).kind, .malformed, value)
        }
    }

    /// The plain ASCII spellings still work, in any case.
    func test_ASCIIGrandfatheredStillWork() throws {
        XCTAssertEqual(try canonicaliser().canonicalise("i-klingon").canonical, "tlh")
        XCTAssertEqual(try canonicaliser().canonicalise("I-KLINGON").canonical, "tlh")
        XCTAssertEqual(try canonicaliser().canonicalise("EN-gb").canonical, "en-GB")
    }
}
