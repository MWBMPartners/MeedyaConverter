// ============================================================================
// MeedyaConverter — RecentFilesView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Displays the user's recent files and pinned favourites in a list view.
//
// Features:
//   - Pinned favourites section with star icons at the top.
//   - Recent files section with relative timestamps ("2 hours ago").
//   - Click to re-import a file into the current session.
//   - Context menu for pin/unpin, reveal in Finder, and remove.
//   - "Clear History" button in the toolbar.
//   - Empty state when no files have been opened.
//
// Can be presented as:
//   - A standalone view in the sidebar or navigation split.
//   - A sheet/popover from the File menu or toolbar.
//
// Phase 11 — Recent Files and Pinned Favorites (Issue #334)
// ---------------------------------------------------------------------------

import SwiftUI

// MARK: - RecentFilesView

/// Displays pinned favourites and recently opened files with re-import support.
///
/// The view reads from a ``RecentFilesManager`` instance injected through
/// the SwiftUI environment. Clicking an entry re-imports the file into the
/// current session via `AppViewModel.importFiles(_:)`.
struct RecentFilesView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The recent files manager providing data for this view.
    @State private var manager = RecentFilesManager()

    /// Whether the clear-history confirmation alert is presented.
    @State private var showClearConfirmation = false

    // MARK: - Body

    var body: some View {
        Group {
            if manager.pinnedFiles.isEmpty && manager.recentFiles.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .navigationTitle("Recent Files")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear History", systemImage: "trash") {
                    showClearConfirmation = true
                }
                .disabled(manager.recentFiles.isEmpty)
                .help("Clear recent files history (pinned files are preserved)")
            }
        }
        .alert("Clear Recent Files?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                manager.clearRecents()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all recent files from the list. Pinned favourites will not be affected.")
        }
    }

    // MARK: - Empty State

    /// Placeholder shown when no recent or pinned files exist.
    private var emptyState: some View {
        ContentUnavailableView(
            "No Recent Files",
            systemImage: "clock.arrow.circlepath",
            description: Text("Files you open or import will appear here for quick access.")
        )
    }

    // MARK: - File List

    /// The main list with pinned and recent sections.
    private var fileList: some View {
        List {
            // Pinned favourites
            if !manager.pinnedFiles.isEmpty {
                Section("Pinned Favourites") {
                    ForEach(manager.pinnedFiles) { entry in
                        RecentFileRow(entry: entry, isPinnedSection: true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                reimportFile(entry)
                            }
                            .contextMenu {
                                pinnedContextMenu(for: entry)
                            }
                    }
                }
            }

            // Recent files
            if !manager.recentFiles.isEmpty {
                Section("Recent") {
                    ForEach(manager.recentFiles) { entry in
                        RecentFileRow(entry: entry, isPinnedSection: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                reimportFile(entry)
                            }
                            .contextMenu {
                                recentContextMenu(for: entry)
                            }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Context Menus

    /// Context menu for pinned file entries.
    @ViewBuilder
    private func pinnedContextMenu(for entry: RecentFileEntry) -> some View {
        Button("Unpin", systemImage: "star.slash") {
            manager.unpin(entry)
        }

        Divider()

        Button("Reveal in Finder", systemImage: "folder") {
            revealInFinder(entry)
        }

        Button("Remove", systemImage: "trash", role: .destructive) {
            manager.remove(entry)
        }
    }

    /// Context menu for recent (non-pinned) file entries.
    @ViewBuilder
    private func recentContextMenu(for entry: RecentFileEntry) -> some View {
        Button("Pin as Favourite", systemImage: "star.fill") {
            manager.pin(entry)
        }

        Divider()

        Button("Reveal in Finder", systemImage: "folder") {
            revealInFinder(entry)
        }

        Button("Remove", systemImage: "trash", role: .destructive) {
            manager.remove(entry)
        }
    }

    // MARK: - Actions

    /// Re-import a file from the recent/pinned list into the current session.
    ///
    /// Resolves the security-scoped bookmark (if present) before importing.
    /// If the file no longer exists, the entry is removed and an error is logged.
    ///
    /// - Parameter entry: The recent file entry to re-import.
    private func reimportFile(_ entry: RecentFileEntry) {
        // Resolve bookmark for sandbox access
        let accessibleURL: URL
        if let resolved = manager.resolveBookmark(for: entry) {
            accessibleURL = resolved
        } else if FileManager.default.isReadableFile(atPath: entry.url.path) {
            accessibleURL = entry.url
        } else {
            // File no longer exists — remove the stale entry
            manager.remove(entry)
            viewModel.appendLog(.warning, "Recent file no longer exists: \(entry.fileName)")
            return
        }

        // Update the last-opened timestamp
        manager.addRecent(accessibleURL)

        // Import via AppViewModel
        Task {
            await viewModel.importFiles([accessibleURL])
        }
    }

    /// Reveal a file in Finder.
    ///
    /// - Parameter entry: The entry whose file to reveal.
    private func revealInFinder(_ entry: RecentFileEntry) {
        NSWorkspace.shared.selectFile(
            entry.url.path,
            inFileViewerRootedAtPath: entry.url.deletingLastPathComponent().path
        )
    }
}

// MARK: - RecentFileRow

/// A single row in the recent/pinned files list.
///
/// Displays the file icon, name, relative timestamp, and file size.
/// Pinned entries show a filled star icon; recent entries show a clock icon.
struct RecentFileRow: View {

    // MARK: - Properties

    /// The file entry to display.
    let entry: RecentFileEntry

    /// Whether this row is in the pinned section (affects icon styling).
    let isPinnedSection: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            Image(systemName: isPinnedSection ? "star.fill" : "clock")
                .foregroundStyle(isPinnedSection ? .yellow : .secondary)
                .font(.body)
                .frame(width: 20)

            // File icon from the system
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)

            // File details
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    // Relative timestamp
                    Text(entry.lastOpened, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // File size
                    if let size = entry.fileSize {
                        Text(formattedFileSize(size))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // File extension badge
            Text(entry.url.pathExtension.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.fileName), opened \(entry.lastOpened, style: .relative)")
    }

    // MARK: - Helpers

    /// Format a file size in bytes to a human-readable string.
    ///
    /// Uses `ByteCountFormatter` for locale-appropriate formatting
    /// (e.g., "1.2 GB", "350 MB", "12 KB").
    ///
    /// - Parameter bytes: The file size in bytes.
    /// - Returns: A formatted string.
    private func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
