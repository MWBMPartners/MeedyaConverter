// ============================================================================
// MeedyaConverter — HelpTopicParserTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// Unit tests for `HelpTopicParser`, the pure Markdown parser that backs the
/// in-app HelpView. Covers title extraction, section splitting, table and
/// code-fence detection, and graceful handling of heading-less input.
final class HelpTopicParserTests: XCTestCase {

    // MARK: - Title extraction

    func test_parse_extractsFirstLevel1HeadingAsTitle() {
        let markdown = """
        # Getting Started

        Intro paragraph.

        ## First Section

        Body.
        """
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertEqual(doc.title, "Getting Started")
    }

    func test_parse_titleIgnoresLevel2Headings() {
        // A level-2 heading before any level-1 heading must not become the title.
        let markdown = """
        ## Not The Title

        Some text.

        # The Real Title

        More text.
        """
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertEqual(doc.title, "The Real Title")
    }

    func test_parse_titleTrimsWhitespaceAndPreservesEmoji() {
        let markdown = "#   🚀 Getting Started with MeedyaConverter   \n\nBody."
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertEqual(doc.title, "🚀 Getting Started with MeedyaConverter")
    }

    // MARK: - Section splitting

    func test_parse_splitsSectionsOnLevel2Headings() {
        let markdown = """
        # Title

        ## Alpha

        First body.

        ## Beta

        Second body.
        """
        let doc = HelpTopicParser.parse(markdown)
        let headings = doc.sections.map(\.heading)
        XCTAssertEqual(headings, ["Alpha", "Beta"])
        XCTAssertEqual(doc.sections[0].body, "First body.")
        XCTAssertEqual(doc.sections[1].body, "Second body.")
    }

    func test_parse_preambleBeforeFirstSectionHasEmptyHeading() {
        let markdown = """
        # Title

        Some preamble text before any section.

        ## Section One

        Body.
        """
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertEqual(doc.sections.first?.heading, "")
        XCTAssertEqual(doc.sections.first?.body, "Some preamble text before any section.")
        XCTAssertEqual(doc.sections.last?.heading, "Section One")
    }

    func test_parse_dropsWhitespaceOnlyPreamble() {
        // A document whose only content between title and first section is
        // blank lines should not produce an empty preamble section.
        let markdown = """
        # Title


        ## Only Section

        Body.
        """
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertEqual(doc.sections.count, 1)
        XCTAssertEqual(doc.sections[0].heading, "Only Section")
    }

    func test_parse_preservesInteriorBlankLinesInBody() {
        let markdown = """
        # Title

        ## Section

        Paragraph one.

        Paragraph two.
        """
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertEqual(doc.sections[0].body, "Paragraph one.\n\nParagraph two.")
    }

    // MARK: - Table detection

    func test_parse_flagsPipeLedTable() {
        let markdown = """
        # Title

        ## Profiles

        | Profile | Description |
        | ------- | ----------- |
        | Web | Compatible MP4 |
        """
        let doc = HelpTopicParser.parse(markdown)
        let section = doc.sections[0]
        XCTAssertTrue(section.containsTable)
        XCTAssertTrue(section.requiresMonospace)
    }

    func test_parse_flagsBorderlessDelimiterTable() {
        let markdown = """
        # Title

        ## Matrix

        Codec | Container
        ------|----------
        H.264 | MP4
        """
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertTrue(doc.sections[0].containsTable)
    }

    func test_parse_prosePipeIsNotFlaggedAsTable() {
        let markdown = """
        # Title

        ## Notes

        Use the pipe operator a | b in your shell to chain commands.
        """
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertFalse(doc.sections[0].containsTable)
        XCTAssertFalse(doc.sections[0].requiresMonospace)
    }

    // MARK: - Code-fence detection

    func test_parse_flagsFencedCodeBlock() {
        let markdown = """
        # Title

        ## Install

        Run this command:

        ```bash
        brew install ffmpeg
        ```
        """
        let doc = HelpTopicParser.parse(markdown)
        let section = doc.sections[0]
        XCTAssertTrue(section.containsCodeBlock)
        XCTAssertTrue(section.requiresMonospace)
    }

    func test_parse_pipeInsideCodeFenceIsNotATable() {
        // A `|` inside a fenced code block must not be misdetected as a table.
        let markdown = """
        # Title

        ## Pipe Example

        ```bash
        cat file | grep foo
        ```
        """
        let doc = HelpTopicParser.parse(markdown)
        let section = doc.sections[0]
        XCTAssertTrue(section.containsCodeBlock)
        XCTAssertFalse(section.containsTable)
    }

    func test_parse_sectionWithoutTableOrCodeIsNotMonospaced() {
        let markdown = """
        # Title

        ## Plain

        Just some **bold** prose and a [link](https://example.com).
        """
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertFalse(doc.sections[0].requiresMonospace)
    }

    // MARK: - Graceful handling of missing heading

    func test_parse_fileWithNoLevel1HeadingHasEmptyTitle() {
        let markdown = """
        This document has no top-level heading.

        ## Section

        Body content.
        """
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertEqual(doc.title, "")
        // Sections are still recovered.
        XCTAssertEqual(doc.sections.map(\.heading), ["", "Section"])
    }

    func test_parse_emptyStringYieldsEmptyDocument() {
        let doc = HelpTopicParser.parse("")
        XCTAssertEqual(doc.title, "")
        XCTAssertTrue(doc.sections.isEmpty)
    }

    func test_parse_normalisesCarriageReturnLineEndings() {
        let markdown = "# Title\r\n\r\n## Section\r\n\r\nBody with CRLF endings."
        let doc = HelpTopicParser.parse(markdown)
        XCTAssertEqual(doc.title, "Title")
        XCTAssertEqual(doc.sections.map(\.heading), ["Section"])
        XCTAssertEqual(doc.sections[0].body, "Body with CRLF endings.")
    }
}
