// ============================================================================
// MeedyaConverter — ComparisonLibraryManager (Issue #329)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Persists ``ComparisonEntry`` records captured by ``ComparisonLibraryView``
// so the A/B comparison library survives an app relaunch.
//
// Mirrors ``RecentFilesManager``'s persistence convention exactly: JSON on
// disk in the app's Application Support directory, loaded once at `init`
// and rewritten atomically after every mutation.
//
// ### Persistence
// Data is stored as JSON at:
//   `~/Library/Application Support/MeedyaConverter/comparison_library.json`
//
// Phase 13 — Issue #329
// ---------------------------------------------------------------------------

import Foundation
import ConverterEngine

// MARK: - ComparisonLibraryManager

/// Manages the persisted library of captured comparison entries.
///
/// - Note: All public API is `@MainActor` to ensure safe SwiftUI integration
///   via the `@Observable` macro, matching ``RecentFilesManager``.
@MainActor @Observable
final class ComparisonLibraryManager {

    // MARK: - Constants

    /// File name for the JSON persistence file.
    private static let persistenceFileName = "comparison_library.json"

    // MARK: - Observable State

    /// All persisted comparison entries, most recently captured first.
    var entries: [ComparisonEntry] = []

    // MARK: - Initialiser

    /// Create a new manager and load persisted entries from disk.
    init() {
        loadFromDisk()
    }

    // MARK: - Mutation

    /// Add a newly captured entry to the library and persist it.
    ///
    /// Inserted at the front so the most recent capture appears first.
    func add(_ entry: ComparisonEntry) {
        entries.insert(entry, at: 0)
        saveToDisk()
    }

    /// Remove an entry from the library and its captured frame file on disk.
    ///
    /// - Parameter entry: The entry to remove.
    func remove(_ entry: ComparisonEntry) {
        entries.removeAll { $0.id == entry.id }
        // Best-effort cleanup of the persisted frame PNG. Not fatal if it
        // fails or the file is already gone.
        try? FileManager.default.removeItem(atPath: entry.framePath)
        saveToDisk()
    }

    // MARK: - Persistence

    /// The URL of the JSON persistence file in Application Support.
    private var persistenceURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDirectory = appSupport.appendingPathComponent("MeedyaConverter")

        // Ensure the directory exists.
        try? FileManager.default.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )

        return appDirectory.appendingPathComponent(Self.persistenceFileName)
    }

    /// The directory where captured comparison frame PNGs are stored so
    /// they survive relaunch alongside the JSON entries that reference them.
    static var framesDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = appSupport
            .appendingPathComponent("MeedyaConverter")
            .appendingPathComponent("ComparisonFrames")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    /// Save the current entries to the JSON file.
    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(entries)
            try jsonData.write(to: persistenceURL, options: .atomic)
        } catch {
            // Log but do not crash — persistence is best-effort, matching
            // RecentFilesManager's behaviour.
            #if DEBUG
            print("[ComparisonLibraryManager] Failed to save: \(error.localizedDescription)")
            #endif
        }
    }

    /// Load persisted entries from the JSON file.
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }

        do {
            let jsonData = try Data(contentsOf: persistenceURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([ComparisonEntry].self, from: jsonData)
        } catch {
            #if DEBUG
            print("[ComparisonLibraryManager] Failed to load: \(error.localizedDescription)")
            #endif
        }
    }
}
