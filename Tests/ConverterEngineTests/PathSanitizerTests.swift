// ============================================================================
// MeedyaConverter — PathSanitizerTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// Regression tests for `PathSanitizer` + the `URL.isContained(within:)`
/// extension. Anchors T2 path-traversal protection per
/// `SECURITY.md` finding F-002 so a future refactor cannot silently
/// re-introduce the vector.
final class PathSanitizerTests: XCTestCase {

    // MARK: - sanitizeFilenameComponent

    func test_sanitize_emptyString_returnsPlaceholder() {
        XCTAssertEqual(PathSanitizer.sanitizeFilenameComponent(""), "unnamed")
    }

    func test_sanitize_bareDot_returnsPlaceholder() {
        XCTAssertEqual(PathSanitizer.sanitizeFilenameComponent("."), "unnamed")
    }

    func test_sanitize_bareDoubleDot_collapsesToSafePlaceholder() {
        // ".." → "__" (after the `..` → `__` rule), then the trailing
        // underscores survive. Importantly the result is not ".." so
        // appendingPathComponent cannot escape the parent.
        let result = PathSanitizer.sanitizeFilenameComponent("..")
        XCTAssertNotEqual(result, "..")
        XCTAssertFalse(result.contains(".."))
    }

    func test_sanitize_pathSeparators_stripped() {
        XCTAssertEqual(
            PathSanitizer.sanitizeFilenameComponent("foo/bar"),
            "foo_bar"
        )
        XCTAssertEqual(
            PathSanitizer.sanitizeFilenameComponent("foo\\bar"),
            "foo_bar"
        )
    }

    func test_sanitize_parentTraversal_collapsedToSafeMarker() {
        XCTAssertEqual(
            PathSanitizer.sanitizeFilenameComponent("../etc/passwd"),
            "___etc_passwd"
        )
    }

    func test_sanitize_nulByte_removed() {
        XCTAssertEqual(
            PathSanitizer.sanitizeFilenameComponent("foo\0bar"),
            "foobar"
        )
    }

    func test_sanitize_trailingDotsAndWhitespace_stripped() {
        XCTAssertEqual(
            PathSanitizer.sanitizeFilenameComponent("video.mp4."),
            "video.mp4"
        )
        XCTAssertEqual(
            PathSanitizer.sanitizeFilenameComponent("video.mp4 "),
            "video.mp4"
        )
        // Leading whitespace also stripped.
        XCTAssertEqual(
            PathSanitizer.sanitizeFilenameComponent("  video.mp4"),
            "video.mp4"
        )
    }

    func test_sanitize_normalFilename_unchanged() {
        XCTAssertEqual(
            PathSanitizer.sanitizeFilenameComponent("My Holiday Video.mov"),
            "My Holiday Video.mov"
        )
    }

    func test_sanitize_isIdempotent() {
        let inputs = [
            "../../etc/passwd",
            "foo/bar\\baz\0qux",
            "  ..hidden..  ",
            "normal.mp4"
        ]
        for input in inputs {
            let once = PathSanitizer.sanitizeFilenameComponent(input)
            let twice = PathSanitizer.sanitizeFilenameComponent(once)
            XCTAssertEqual(once, twice, "Sanitisation is not idempotent for '\(input)'")
        }
    }

    func test_sanitize_appendingPathComponent_cannotEscapeParent() {
        // The load-bearing assertion: after sanitisation, the result
        // never escapes its parent directory via appendingPathComponent.
        let parent = URL(fileURLWithPath: "/private/tmp/safe-zone")
        let attackerInputs = [
            "../../etc/passwd",
            "..\\..\\Windows\\System32",
            "/etc/passwd",
            "../"
        ]
        for input in attackerInputs {
            let sanitised = PathSanitizer.sanitizeFilenameComponent(input)
            let resolved = parent.appendingPathComponent(sanitised).standardized
            XCTAssertTrue(
                resolved.isContained(within: parent),
                "Sanitised input '\(input)' → '\(sanitised)' escaped to \(resolved.path)"
            )
        }
    }

    // MARK: - URL.isContained(within:)

    func test_isContained_sameURL_true() {
        let url = URL(fileURLWithPath: "/private/tmp/a")
        XCTAssertTrue(url.isContained(within: url))
    }

    func test_isContained_descendant_true() {
        let parent = URL(fileURLWithPath: "/private/tmp")
        let child = URL(fileURLWithPath: "/private/tmp/a/b/c.txt")
        XCTAssertTrue(child.isContained(within: parent))
    }

    func test_isContained_siblingPrefixCollision_false() {
        // /private/tmp-attack starts with /private/tmp but is NOT a
        // descendant of /private/tmp — the containment check must
        // anchor on the path-separator boundary, not raw string prefix.
        let parent = URL(fileURLWithPath: "/private/tmp")
        let sibling = URL(fileURLWithPath: "/private/tmp-attack/payload")
        XCTAssertFalse(sibling.isContained(within: parent))
    }

    func test_isContained_pathTraversalRejected_false() {
        let parent = URL(fileURLWithPath: "/private/tmp/safe")
        let traversal = URL(fileURLWithPath: "/private/tmp/safe/../../../etc/passwd")
        XCTAssertFalse(traversal.isContained(within: parent))
    }

    func test_isContained_unrelatedURL_false() {
        let parent = URL(fileURLWithPath: "/Users/me/Movies")
        let unrelated = URL(fileURLWithPath: "/etc/passwd")
        XCTAssertFalse(unrelated.isContained(within: parent))
    }
}
