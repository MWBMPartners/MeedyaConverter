// ============================================================================
// MeedyaConverter — RecentFilesManager
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Manages the recent files list and pinned favourites for MeedyaConverter.
//
// Features:
//   - Recent files list with a maximum of 20 entries (FIFO eviction).
//   - Pinned favourites with no limit, manually managed by the user.
//   - Persistence to a JSON file in the app's Application Support directory.
//   - Security-scoped bookmark support for sandboxed apps, ensuring files
//     remain accessible across app launches even outside the sandbox.
//   - Automatic pruning of entries whose files no longer exist on disk.
//
// ### Data Model
// Each entry is a ``RecentFileEntry`` containing the file URL, display name,
// last-opened timestamp, pin status, file size, and an optional
// security-scoped bookmark for sandbox persistence.
//
// ### Persistence
// Data is stored as JSON at:
//   `~/Library/Application Support/MeedyaConverter/recent_files.json`
//
// Phase 11 — Recent Files and Pinned Favorites (Issue #334)
// ---------------------------------------------------------------------------

import Foundation

// MARK: - RecentFileEntry

/// A single entry in the recent files or pinned favourites list.
///
/// Stores the file URL, metadata for display, and an optional security-scoped
/// bookmark for sandbox persistence. Conforms to `Codable` for JSON storage
/// and `Identifiable` for SwiftUI list rendering.
struct RecentFileEntry: Identifiable, Codable, Sendable {

    // MARK: - Properties

    /// Unique identifier for this entry.
    let id: UUID

    /// The file URL. When loaded from a security-scoped bookmark, this URL
    /// may need `startAccessingSecurityScopedResource()` before use.
    var url: URL

    /// The file's display name (last path component at time of recording).
    let fileName: String

    /// Timestamp of the most recent open/import of this file.
    var lastOpened: Date

    /// Whether the user has pinned this file as a favourite.
    var isPinned: Bool

    /// The file size in bytes at the time of recording, or `nil` if unavailable.
    let fileSize: Int64?

    /// Security-scoped bookmark data for sandbox persistence.
    ///
    /// Created via `URL.bookmarkData(options: .withSecurityScope)`. When the
    /// app is relaunched, this bookmark is resolved to restore file access
    /// without requiring the user to re-select the file.
    var bookmarkData: Data?

    // MARK: - Initialiser

    /// Create a new recent file entry from a file URL.
    ///
    /// Automatically extracts the file name and size from the URL's resource
    /// values. Creates a security-scoped bookmark if running in a sandbox.
    ///
    /// - Parameters:
    ///   - url: The file URL to record.
    ///   - isPinned: Whether the entry should be pinned. Defaults to `false`.
    init(url: URL, isPinned: Bool = false) {
        self.id = UUID()
        self.url = url
        self.fileName = url.lastPathComponent
        self.lastOpened = Date()
        self.isPinned = isPinned

        // Extract file size
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        self.fileSize = resourceValues?.fileSize.map { Int64($0) }

        // Create security-scoped bookmark for sandbox persistence
        self.bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

// MARK: - RecentFilesManager

/// Manages recent files and pinned favourites with persistent storage.
///
/// Maintains a FIFO list of up to 20 recent files and an unlimited list
/// of user-pinned favourites. Data is persisted to a JSON file in the
/// app's Application Support directory.
///
/// - Note: All public API is `@MainActor` to ensure safe SwiftUI integration
///   via the `@Observable` macro.
@MainActor @Observable
final class RecentFilesManager {

    // MARK: - Constants

    /// Maximum number of entries in the recent files list (excluding pinned).
    private static let maxRecentCount = 20

    /// File name for the JSON persistence file.
    private static let persistenceFileName = "recent_files.json"

    // MARK: - Observable State

    /// The list of recently opened files, ordered by most recent first.
    /// Limited to ``maxRecentCount`` entries. Pinned files are not counted.
    var recentFiles: [RecentFileEntry] = []

    /// The list of user-pinned favourite files. No count limit.
    /// Ordered by most recently pinned first.
    var pinnedFiles: [RecentFileEntry] = []

    // MARK: - Initialiser

    /// Create a new manager and load persisted data from disk.
    init() {
        loadFromDisk()
    }

    // MARK: - Adding Recents

    /// Record a file as recently opened.
    ///
    /// If the file is already in the recent list, it is moved to the front
    /// and its `lastOpened` timestamp is updated. If the list exceeds
    /// ``maxRecentCount``, the oldest entry is removed.
    ///
    /// Pinned files are not affected — if the file is already pinned, only
    /// its `lastOpened` timestamp is updated in the pinned list.
    ///
    /// - Parameter url: The file URL that was opened or imported.
    func addRecent(_ url: URL) {
        // Update existing pinned entry's timestamp if present
        if let pinnedIndex = pinnedFiles.firstIndex(where: { $0.url == url }) {
            pinnedFiles[pinnedIndex].lastOpened = Date()
        }

        // Remove existing recent entry (will be re-added at the front)
        recentFiles.removeAll { $0.url == url }

        // Create new entry and insert at the front
        let entry = RecentFileEntry(url: url)
        recentFiles.insert(entry, at: 0)

        // Enforce maximum count
        if recentFiles.count > Self.maxRecentCount {
            recentFiles = Array(recentFiles.prefix(Self.maxRecentCount))
        }

        saveToDisk()
    }

    // MARK: - Pinning

    /// Pin a recent file entry as a favourite.
    ///
    /// Moves the entry from the recent list to the pinned list. If the
    /// entry is already pinned, this method is a no-op.
    ///
    /// - Parameter entry: The entry to pin.
    func pin(_ entry: RecentFileEntry) {
        // Skip if already pinned
        guard !pinnedFiles.contains(where: { $0.id == entry.id }) else { return }

        // Remove from recents
        recentFiles.removeAll { $0.id == entry.id }

        // Add to pinned with flag set
        var pinnedEntry = entry
        pinnedEntry.isPinned = true
        pinnedFiles.insert(pinnedEntry, at: 0)

        saveToDisk()
    }

    /// Unpin a favourite file entry, moving it back to the recent list.
    ///
    /// The entry is inserted at the front of the recent list. If the
    /// recent list exceeds the maximum count, the oldest entry is evicted.
    ///
    /// - Parameter entry: The entry to unpin.
    func unpin(_ entry: RecentFileEntry) {
        // Remove from pinned
        pinnedFiles.removeAll { $0.id == entry.id }

        // Add back to recents
        var recentEntry = entry
        recentEntry.isPinned = false
        recentFiles.insert(recentEntry, at: 0)

        // Enforce maximum count
        if recentFiles.count > Self.maxRecentCount {
            recentFiles = Array(recentFiles.prefix(Self.maxRecentCount))
        }

        saveToDisk()
    }

    // MARK: - Clearing

    /// Remove all entries from the recent files list.
    ///
    /// Pinned files are not affected. Call this when the user selects
    /// "Clear Recent Files" from the File menu or context menu.
    func clearRecents() {
        recentFiles.removeAll()
        saveToDisk()
    }

    /// Remove a specific entry from the recent or pinned list.
    ///
    /// - Parameter entry: The entry to remove.
    func remove(_ entry: RecentFileEntry) {
        recentFiles.removeAll { $0.id == entry.id }
        pinnedFiles.removeAll { $0.id == entry.id }
        saveToDisk()
    }

    // MARK: - Bookmark Resolution

    /// Resolve a security-scoped bookmark and return an accessible URL.
    ///
    /// For sandboxed apps, files outside the sandbox require security-scoped
    /// bookmarks to maintain access across app launches. This method resolves
    /// the bookmark and starts accessing the security-scoped resource.
    ///
    /// - Parameter entry: The entry whose bookmark to resolve.
    /// - Returns: An accessible file URL, or `nil` if the bookmark is stale
    ///   or the file no longer exists.
    func resolveBookmark(for entry: RecentFileEntry) -> URL? {
        guard let bookmarkData = entry.bookmarkData else {
            // No bookmark — check if the file is directly accessible
            return FileManager.default.isReadableFile(atPath: entry.url.path) ? entry.url : nil
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        // If the bookmark is stale, update it
        if isStale {
            if let index = recentFiles.firstIndex(where: { $0.id == entry.id }) {
                recentFiles[index].url = resolvedURL
                recentFiles[index].bookmarkData = try? resolvedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                saveToDisk()
            }
            if let index = pinnedFiles.firstIndex(where: { $0.id == entry.id }) {
                pinnedFiles[index].url = resolvedURL
                pinnedFiles[index].bookmarkData = try? resolvedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                saveToDisk()
            }
        }

        // Start accessing the security-scoped resource
        guard resolvedURL.startAccessingSecurityScopedResource() else {
            return nil
        }

        return resolvedURL
    }

    // MARK: - Persistence

    /// The URL of the JSON persistence file in Application Support.
    private var persistenceURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDirectory = appSupport.appendingPathComponent("MeedyaConverter")

        // Ensure the directory exists
        try? FileManager.default.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )

        return appDirectory.appendingPathComponent(Self.persistenceFileName)
    }

    /// Save the current state to the JSON file.
    private func saveToDisk() {
        let data = PersistenceData(
            recentFiles: recentFiles,
            pinnedFiles: pinnedFiles
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: persistenceURL, options: .atomic)
        } catch {
            // Log but do not crash — persistence is best-effort
            #if DEBUG
            print("[RecentFilesManager] Failed to save: \(error.localizedDescription)")
            #endif
        }
    }

    /// Load persisted state from the JSON file.
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }

        do {
            let jsonData = try Data(contentsOf: persistenceURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try decoder.decode(PersistenceData.self, from: jsonData)

            recentFiles = data.recentFiles
            pinnedFiles = data.pinnedFiles
        } catch {
            #if DEBUG
            print("[RecentFilesManager] Failed to load: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Persistence Data

/// Top-level structure for JSON serialisation of recent and pinned files.
private struct PersistenceData: Codable {
    let recentFiles: [RecentFileEntry]
    let pinnedFiles: [RecentFileEntry]
}
