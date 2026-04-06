// ============================================================================
// MeedyaConverter — DropHandler (Issue #366)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers

// MARK: - DropHandler

/// Reusable drag-and-drop file handler for extracting URLs from
/// `NSItemProvider` arrays.
///
/// Centralises the `NSItemProvider` → `URL` parsing logic so that
/// individual views do not need to duplicate it.
///
/// Phase 12 — Universal Drag-and-Drop Support (Issue #366)
struct DropHandler {

    // MARK: - URL Extraction

    /// Extracts file URLs from an array of drop providers.
    ///
    /// Each provider is checked for `URL` load capability. Results are
    /// collected asynchronously and delivered on the main queue via the
    /// completion handler.
    ///
    /// - Parameters:
    ///   - providers: The `NSItemProvider` instances from the drop event.
    ///   - completion: Called on the main queue with the resolved URLs.
    static func extractURLs(
        from providers: [NSItemProvider],
        completion: @escaping @Sendable ([URL]) -> Void
    ) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { urls.append(url) }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { completion(urls) }
    }
}
