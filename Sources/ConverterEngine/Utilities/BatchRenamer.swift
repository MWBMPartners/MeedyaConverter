// ============================================================================
// MeedyaConverter — BatchRenamer (Issue #332)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - RenameRule

/// A single find-and-replace rule for batch renaming operations.
///
/// Rules can be plain text or regex-based, and optionally case-sensitive.
/// Multiple rules are applied sequentially to each filename.
///
/// Phase 14 — Batch Rename Tool (Issue #332)
public struct RenameRule: Codable, Sendable, Hashable {

    /// The pattern to search for in the filename.
    public var findPattern: String

    /// The replacement string. Supports regex capture group references
    /// (e.g. `$1`, `$2`) when `isRegex` is `true`.
    public var replaceWith: String

    /// Whether `findPattern` should be treated as a regular expression.
    public var isRegex: Bool

    /// Whether the match should be case-sensitive.
    public var caseSensitive: Bool

    /// Creates a new rename rule.
    ///
    /// - Parameters:
    ///   - findPattern: The text or regex pattern to find.
    ///   - replaceWith: The replacement string.
    ///   - isRegex: `true` to treat `findPattern` as a regex.
    ///   - caseSensitive: `true` for case-sensitive matching.
    public init(
        findPattern: String,
        replaceWith: String,
        isRegex: Bool = false,
        caseSensitive: Bool = true
    ) {
        self.findPattern = findPattern
        self.replaceWith = replaceWith
        self.isRegex = isRegex
        self.caseSensitive = caseSensitive
    }
}

// MARK: - RenamePreview

/// A preview of a single file rename showing the before and after names.
///
/// Used by the UI to display a live preview table before the user
/// commits to applying the rename operation.
///
/// Phase 14 — Batch Rename Tool (Issue #332)
public struct RenamePreview: Identifiable, Sendable, Hashable {

    /// Unique identifier for this preview entry.
    public let id: UUID

    /// The original filename (without directory path).
    public let originalName: String

    /// The new filename after applying rename rules.
    public let newName: String

    /// Whether the filename actually changed. `false` when no rules matched.
    public let changed: Bool

    /// Creates a new rename preview.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - originalName: The original filename.
    ///   - newName: The renamed filename.
    ///   - changed: Whether the name differs from the original.
    public init(
        id: UUID = UUID(),
        originalName: String,
        newName: String,
        changed: Bool
    ) {
        self.id = id
        self.originalName = originalName
        self.newName = newName
        self.changed = changed
    }
}

// MARK: - BatchRenamer

/// Applies rename rules to collections of files with preview support.
///
/// All methods are static and pure — `preview` returns what *would* happen,
/// and `apply` performs the actual filesystem rename. This separation allows
/// the UI to show a live preview before committing changes.
///
/// Phase 14 — Batch Rename Tool (Issue #332)
public struct BatchRenamer: Sendable {

    // MARK: - Preview

    /// Generates a preview of rename operations without modifying the filesystem.
    ///
    /// Applies all rules sequentially to each file's name (stem only, preserving
    /// the extension) and returns a preview showing old and new names.
    ///
    /// - Parameters:
    ///   - files: URLs of the files to rename.
    ///   - rules: Ordered list of rename rules to apply.
    /// - Returns: An array of `RenamePreview` entries, one per file.
    public static func preview(
        files: [URL],
        rules: [RenameRule]
    ) -> [RenamePreview] {
        return files.map { url in
            let originalName = url.lastPathComponent
            let ext = url.pathExtension
            var stem = url.deletingPathExtension().lastPathComponent

            for rule in rules {
                stem = applyRule(rule, to: stem)
            }

            let newName = ext.isEmpty ? stem : "\(stem).\(ext)"
            return RenamePreview(
                originalName: originalName,
                newName: newName,
                changed: originalName != newName
            )
        }
    }

    // MARK: - Apply

    /// Applies rename rules to files on disk and returns the new URLs.
    ///
    /// Files are renamed in place (same directory). If a rename would
    /// create a collision with an existing file, a numeric suffix is
    /// appended (e.g. `_1`, `_2`).
    ///
    /// - Parameters:
    ///   - files: URLs of the files to rename.
    ///   - rules: Ordered list of rename rules to apply.
    /// - Returns: An array of new file URLs after renaming.
    /// - Throws: `CocoaError` if a file rename fails.
    public static func apply(
        files: [URL],
        rules: [RenameRule]
    ) throws -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        for url in files {
            let directory = url.deletingLastPathComponent()
            let ext = url.pathExtension
            var stem = url.deletingPathExtension().lastPathComponent

            for rule in rules {
                stem = applyRule(rule, to: stem)
            }

            let baseName = ext.isEmpty ? stem : "\(stem).\(ext)"
            var newURL = directory.appendingPathComponent(baseName)

            // Handle filename collisions by appending a numeric suffix.
            var counter = 1
            while fm.fileExists(atPath: newURL.path) && newURL != url {
                let suffixed = ext.isEmpty
                    ? "\(stem)_\(counter)"
                    : "\(stem)_\(counter).\(ext)"
                newURL = directory.appendingPathComponent(suffixed)
                counter += 1
            }

            if newURL != url {
                try fm.moveItem(at: url, to: newURL)
            }
            results.append(newURL)
        }

        return results
    }

    // MARK: - Sequential Naming

    /// Generates sequential filenames from a template pattern.
    ///
    /// The template uses `#` characters as placeholders for the sequence
    /// number, zero-padded to match the placeholder width. For example,
    /// `"Episode_###"` produces `"Episode_001"`, `"Episode_002"`, etc.
    ///
    /// - Parameters:
    ///   - files: URLs of the files to rename.
    ///   - template: The naming template with `#` placeholders.
    ///   - startNumber: The first number in the sequence (default 1).
    /// - Returns: An array of `RenamePreview` entries.
    public static func buildSequentialNames(
        files: [URL],
        template: String,
        startNumber: Int = 1
    ) -> [RenamePreview] {
        // Count the number of '#' characters for zero-padding width.
        let hashCount = template.filter { $0 == "#" }.count
        let padWidth = max(hashCount, 1)

        return files.enumerated().map { index, url in
            let originalName = url.lastPathComponent
            let ext = url.pathExtension
            let number = startNumber + index
            let paddedNumber = String(format: "%0\(padWidth)d", number)

            // Replace all '#' sequences with the padded number.
            let stem = template.replacingOccurrences(
                of: String(repeating: "#", count: hashCount),
                with: paddedNumber
            )

            let newName = ext.isEmpty ? stem : "\(stem).\(ext)"
            return RenamePreview(
                originalName: originalName,
                newName: newName,
                changed: originalName != newName
            )
        }
    }

    // MARK: - Private Helpers

    /// Applies a single rename rule to a filename stem.
    ///
    /// - Parameters:
    ///   - rule: The rename rule to apply.
    ///   - stem: The filename stem (without extension).
    /// - Returns: The modified stem after applying the rule.
    private static func applyRule(_ rule: RenameRule, to stem: String) -> String {
        if rule.isRegex {
            // Regex-based replacement
            var options: NSRegularExpression.Options = []
            if !rule.caseSensitive {
                options.insert(.caseInsensitive)
            }
            guard let regex = try? NSRegularExpression(
                pattern: rule.findPattern,
                options: options
            ) else {
                return stem
            }
            let range = NSRange(stem.startIndex..., in: stem)
            return regex.stringByReplacingMatches(
                in: stem,
                range: range,
                withTemplate: rule.replaceWith
            )
        } else {
            // Plain text replacement
            if rule.caseSensitive {
                return stem.replacingOccurrences(
                    of: rule.findPattern,
                    with: rule.replaceWith
                )
            } else {
                return stem.replacingOccurrences(
                    of: rule.findPattern,
                    with: rule.replaceWith,
                    options: .caseInsensitive
                )
            }
        }
    }
}
