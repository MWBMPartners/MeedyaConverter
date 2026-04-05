// ============================================================================
// MeedyaConverter — OutputPathResolver
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - OutputMode

/// Determines how output files are organised relative to the output directory.
///
/// - `.flatten`: All output files are placed directly in the output directory.
/// - `.mirror`: The input directory structure is preserved under the output directory.
/// - `.custom`: A template-based naming scheme is applied (reserved for future use).
public enum OutputMode: String, Codable, Sendable, CaseIterable {
    /// Place all output files flat in the output directory.
    case flatten

    /// Mirror the source directory hierarchy in the output directory.
    case mirror

    /// Apply a custom template-based path (reserved for future use).
    case custom

    /// Display name for the UI picker.
    public var displayName: String {
        switch self {
        case .flatten: return "Flatten (all in output folder)"
        case .mirror: return "Mirror source folder structure"
        case .custom: return "Custom template"
        }
    }
}

// MARK: - OutputPathResolver

/// Resolves the output file path for a given input file based on the
/// selected output mode.
///
/// Handles three modes: flatten (all in one directory), mirror (preserve
/// source directory hierarchy), and custom (template-based). Automatically
/// handles filename collisions by appending `_1`, `_2`, etc.
public struct OutputPathResolver: Sendable {

    // MARK: - Resolution

    /// Resolve the output file path for a given input.
    ///
    /// - Parameters:
    ///   - inputURL: The source media file URL.
    ///   - baseInputDir: The root input directory for mirror mode.
    ///     When `nil` in mirror mode, falls back to flatten behaviour.
    ///   - outputDir: The destination output directory.
    ///   - mode: The output organisation mode.
    ///   - template: An optional filename template for custom mode (unused in flatten/mirror).
    /// - Returns: The resolved output file URL with collision handling applied.
    public static func resolveOutputPath(
        inputURL: URL,
        baseInputDir: URL?,
        outputDir: URL,
        mode: OutputMode,
        template: FilenameTemplate?
    ) -> URL {
        let fileName = inputURL.lastPathComponent

        switch mode {
        case .flatten:
            let candidate = outputDir.appendingPathComponent(fileName)
            return resolveCollision(candidate)

        case .mirror:
            guard let baseDir = baseInputDir else {
                // No base directory — fall back to flatten
                let candidate = outputDir.appendingPathComponent(fileName)
                return resolveCollision(candidate)
            }

            // Calculate the relative path from the base input directory
            let inputDirPath = inputURL.deletingLastPathComponent().path
            let basePath = baseDir.path

            let relativePath: String
            if inputDirPath.hasPrefix(basePath) {
                var rel = String(inputDirPath.dropFirst(basePath.count))
                // Remove leading separator if present
                if rel.hasPrefix("/") {
                    rel = String(rel.dropFirst())
                }
                relativePath = rel
            } else {
                // Input is not under the base directory — fall back to flatten
                relativePath = ""
            }

            let targetDir: URL
            if relativePath.isEmpty {
                targetDir = outputDir
            } else {
                targetDir = outputDir.appendingPathComponent(relativePath)
            }

            // Create intermediate directories as needed
            try? FileManager.default.createDirectory(
                at: targetDir,
                withIntermediateDirectories: true
            )

            let candidate = targetDir.appendingPathComponent(fileName)
            return resolveCollision(candidate)

        case .custom:
            // Custom template mode — apply template if available, else flatten
            if let template {
                let resolvedName = template.resolve(for: inputURL)
                let candidate = outputDir.appendingPathComponent(resolvedName)

                // Create intermediate directories if the template includes path separators
                let parentDir = candidate.deletingLastPathComponent()
                try? FileManager.default.createDirectory(
                    at: parentDir,
                    withIntermediateDirectories: true
                )

                return resolveCollision(candidate)
            } else {
                let candidate = outputDir.appendingPathComponent(fileName)
                return resolveCollision(candidate)
            }
        }
    }

    // MARK: - Collision Handling

    /// Resolve filename collisions by appending `_1`, `_2`, etc.
    ///
    /// If the candidate URL does not conflict with an existing file, it is
    /// returned unchanged. Otherwise, suffixes are tried in ascending order.
    ///
    /// - Parameter candidate: The proposed output file URL.
    /// - Returns: A URL guaranteed not to collide with an existing file.
    private static func resolveCollision(_ candidate: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let directory = candidate.deletingLastPathComponent()
        let baseName = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension

        var counter = 1
        while true {
            let newName: String
            if ext.isEmpty {
                newName = "\(baseName)_\(counter)"
            } else {
                newName = "\(baseName)_\(counter).\(ext)"
            }

            let newURL = directory.appendingPathComponent(newName)
            if !fm.fileExists(atPath: newURL.path) {
                return newURL
            }
            counter += 1
        }
    }
}
