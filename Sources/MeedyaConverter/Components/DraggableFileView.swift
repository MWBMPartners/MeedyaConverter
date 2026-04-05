// ============================================================================
// MeedyaConverter — DraggableFileView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides drag-out support from the MeedyaConverter app to Finder and other
// applications. When an encoding job completes, the output file row becomes
// draggable — the user can drag it directly to a Finder window, Desktop,
// Mail attachment well, or any other drop target that accepts file URLs.
//
// ### Components
//   - `DraggableFileModifier` — A `ViewModifier` that attaches `.onDrag`
//     with an `NSItemProvider` wrapping the output file URL as `NSURL`.
//   - `View.draggableFile(_:)` — Convenience extension for easy application.
//   - `DraggableFilePreview` — A lightweight drag preview showing the file
//     icon and name.
//
// ### Usage in JobQueueView
// Apply the `.draggableFile(job.config.outputURL)` modifier to completed
// job rows. The modifier is a no-op when the URL is `nil` or the file
// does not exist on disk.
//
// Phase 11 — Drag-Out from App to Finder (Issue #285)
// ---------------------------------------------------------------------------

import SwiftUI
import UniformTypeIdentifiers

// MARK: - DraggableFileModifier

/// A view modifier that makes a view draggable as a file URL.
///
/// Attaches an `.onDrag` handler that creates an `NSItemProvider` with the
/// file URL registered as `NSURL`. The drag preview shows the file's system
/// icon and display name for clear visual feedback.
///
/// The modifier is inert (no drag behaviour) when:
/// - The provided URL is `nil`.
/// - The file does not exist at the URL's path.
///
/// - Note: Uses `NSItemProvider(object:)` with `NSURL` which automatically
///   registers the URL for the `public.file-url` UTType, ensuring broad
///   compatibility with Finder, Mail, and other AppKit/UIKit drop targets.
struct DraggableFileModifier: ViewModifier {

    // MARK: - Properties

    /// The file URL to provide as drag data. `nil` disables dragging.
    let fileURL: URL?

    // MARK: - Body

    func body(content: Content) -> some View {
        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
            content
                .onDrag {
                    NSItemProvider(object: url as NSURL)
                } preview: {
                    DraggableFilePreview(url: url)
                }
        } else {
            content
        }
    }
}

// MARK: - DraggableFilePreview

/// A lightweight drag preview displaying the file icon and name.
///
/// Shown during drag operations to give the user clear feedback about
/// which file is being dragged. Uses `NSWorkspace.shared.icon(forFile:)`
/// for the system-native file icon.
struct DraggableFilePreview: View {

    // MARK: - Properties

    /// The file URL whose icon and name to display.
    let url: URL

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // System file icon
            Image(nsImage: fileIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            // File name
            Text(url.lastPathComponent)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - File Icon

    /// The system icon for the file at the given URL.
    ///
    /// Falls back to a generic document icon if the file does not exist
    /// or the workspace cannot determine the icon.
    private var fileIcon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - View Extension

extension View {

    /// Makes this view draggable as a file to Finder and other apps.
    ///
    /// When the user starts a drag gesture on the modified view, an
    /// `NSItemProvider` with the file URL is created. The drag preview
    /// shows the file's system icon and display name.
    ///
    /// The modifier is a no-op when:
    /// - `url` is `nil`.
    /// - The file does not exist on disk.
    ///
    /// ### Example
    /// ```swift
    /// JobRow(job: job)
    ///     .draggableFile(job.config.outputURL)
    /// ```
    ///
    /// - Parameter url: The file URL to provide as drag data, or `nil`
    ///   to disable dragging.
    /// - Returns: A view that can be dragged as a file.
    func draggableFile(_ url: URL?) -> some View {
        modifier(DraggableFileModifier(fileURL: url))
    }
}
