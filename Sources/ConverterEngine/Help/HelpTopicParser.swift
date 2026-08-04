// ============================================================================
// MeedyaConverter — HelpTopicParser
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - HelpDocument

/// A parsed help document.
///
/// Produced by ``HelpTopicParser/parse(_:)`` from the raw Markdown of a
/// bundled help file. The parser is deliberately AppKit-/SwiftUI-free (pure
/// Foundation) so it lives in `ConverterEngine` and can be unit-tested — the
/// GUI executable target cannot be imported by a test target.
public struct HelpDocument: Equatable, Sendable {

    /// The document title: the text of the first level-1 (`# `) heading, with
    /// the leading marker stripped and surrounding whitespace trimmed.
    ///
    /// Empty when the source contains no level-1 heading.
    public let title: String

    /// The document body, split into sections on each level-2 (`## `) heading.
    ///
    /// Content that appears after the title but before the first `## ` heading
    /// (a preamble) is returned as a leading section with an empty ``HelpSection/heading``.
    /// Sections whose body is entirely whitespace are omitted.
    public let sections: [HelpSection]

    public init(title: String, sections: [HelpSection]) {
        self.title = title
        self.sections = sections
    }
}

// MARK: - HelpSection

/// A single section of a ``HelpDocument``.
public struct HelpSection: Equatable, Sendable {

    /// The section heading — the text following the `## ` marker, trimmed.
    ///
    /// Empty for a preamble section (content before the first `## `).
    public let heading: String

    /// The raw Markdown body of the section, trimmed of leading and trailing
    /// blank lines. The section heading line itself is not included.
    public let body: String

    /// `true` when the body contains a Markdown pipe table.
    ///
    /// A table is detected by a delimiter row (e.g. `| --- | :--: |`) or a
    /// pipe-led row, outside any fenced code block.
    public let containsTable: Bool

    /// `true` when the body contains a fenced code block (```` ``` ```` or `~~~`).
    public let containsCodeBlock: Bool

    /// Whether this section should be rendered in a monospaced, verbatim style.
    ///
    /// `AttributedString(markdown:)` cannot render pipe tables and mangles
    /// fenced code, so the view falls back to monospaced text for these
    /// sections to keep table- and code-heavy topics readable.
    public var requiresMonospace: Bool { containsTable || containsCodeBlock }

    public init(heading: String, body: String, containsTable: Bool, containsCodeBlock: Bool) {
        self.heading = heading
        self.body = body
        self.containsTable = containsTable
        self.containsCodeBlock = containsCodeBlock
    }
}

// MARK: - HelpTopicParser

/// A pure, Foundation-only parser for the bundled Markdown help topics.
///
/// The parser recognises a small, well-defined subset of Markdown sufficient
/// for the in-app help renderer:
///
/// - **Title** — the first line beginning with `# ` (a level-1 ATX heading).
/// - **Sections** — the document is split on each line beginning with `## `
///   (a level-2 ATX heading); the heading text names the section.
/// - **Tables / code fences** — each section is flagged when it contains a
///   pipe table or a fenced code block so the renderer can switch to a
///   monospaced, verbatim style (``HelpSection/requiresMonospace``).
///
/// The parser never throws and never fails: malformed or heading-less input
/// simply yields an empty ``HelpDocument/title`` and whatever sections could
/// be recovered.
public enum HelpTopicParser {

    /// Parse the raw Markdown of a help topic into a ``HelpDocument``.
    ///
    /// - Parameter markdown: The full UTF-8 text of a help Markdown file.
    /// - Returns: The parsed document. Line endings are normalised (`\r\n`
    ///   and `\r` are treated as `\n`).
    public static func parse(_ markdown: String) -> HelpDocument {
        let normalised = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalised.components(separatedBy: "\n")

        var title = ""
        var titleFound = false

        // Accumulator for the section currently being built.
        var currentHeading = ""
        var currentBody: [String] = []
        var sections: [HelpSection] = []

        func flushCurrentSection() {
            let body = trimBlankEdges(currentBody)
            // Drop sections that are entirely empty (e.g. an absent preamble).
            if !body.isEmpty || !currentHeading.isEmpty {
                sections.append(makeSection(heading: currentHeading, body: body))
            }
            currentHeading = ""
            currentBody = []
        }

        for line in lines {
            if !titleFound, isLevel1Heading(line) {
                title = headingText(line, markerLength: 1)
                titleFound = true
                continue
            }
            if isLevel2Heading(line) {
                flushCurrentSection()
                currentHeading = headingText(line, markerLength: 2)
                continue
            }
            currentBody.append(line)
        }
        flushCurrentSection()

        return HelpDocument(title: title, sections: sections)
    }

    // MARK: - Section construction

    private static func makeSection(heading: String, body: String) -> HelpSection {
        let bodyLines = body.components(separatedBy: "\n")
        var insideFence = false
        var containsTable = false
        var containsCodeBlock = false

        for rawLine in bodyLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                containsCodeBlock = true
                insideFence.toggle()
                continue
            }
            // Only look for table rows outside fenced code so that a `|` in a
            // shell example is not misread as a table.
            if !insideFence, isTableRow(trimmed) {
                containsTable = true
            }
        }

        return HelpSection(
            heading: heading,
            body: body,
            containsTable: containsTable,
            containsCodeBlock: containsCodeBlock
        )
    }

    // MARK: - Heading helpers

    /// A level-1 ATX heading: `# ` at the very start of the line.
    private static func isLevel1Heading(_ line: String) -> Bool {
        line.hasPrefix("# ")
    }

    /// A level-2 ATX heading: `## ` at the very start of the line.
    private static func isLevel2Heading(_ line: String) -> Bool {
        line.hasPrefix("## ")
    }

    /// The heading text with its `#` marker(s) and surrounding whitespace removed.
    private static func headingText(_ line: String, markerLength: Int) -> String {
        let stripped = line.dropFirst(markerLength)
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Table detection

    /// Whether a trimmed line looks like a Markdown pipe-table row.
    ///
    /// Matches either a pipe-led row (`| a | b |`) or a delimiter row made up
    /// only of pipes, dashes, colons and spaces with at least one pipe and one
    /// dash (`| --- | :--: |` or `---|---`).
    private static func isTableRow(_ trimmed: String) -> Bool {
        guard trimmed.contains("|") else { return false }
        if trimmed.hasPrefix("|") { return true }
        // Borderless delimiter row, e.g. "---|---".
        let delimiterCharacters = Set("|-: ")
        let hasDash = trimmed.contains("-")
        let onlyDelimiters = trimmed.allSatisfy { delimiterCharacters.contains($0) }
        return hasDash && onlyDelimiters
    }

    // MARK: - Whitespace helpers

    /// Join `lines` with newlines and trim leading/trailing blank lines while
    /// preserving interior blank lines (paragraph breaks).
    private static func trimBlankEdges(_ lines: [String]) -> String {
        var start = 0
        var end = lines.count
        while start < end, lines[start].trimmingCharacters(in: .whitespaces).isEmpty {
            start += 1
        }
        while end > start, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            end -= 1
        }
        guard start < end else { return "" }
        return lines[start..<end].joined(separator: "\n")
    }
}
