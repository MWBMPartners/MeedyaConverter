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
        // Multi-file drops complete on arbitrary background queues,
        // so the per-provider completion handlers can run concurrently.
        // Mutating a captured ``var`` array from inside @Sendable
        // closures is a Swift 6 data race. We funnel every append
        // through a serial queue so the final array is well-defined.
        //
        // We also use ``DispatchQueue.sync(execute:)`` rather than
        // ``async`` so the append is ordered-before the matching
        // ``group.leave()`` — that means by the time ``group.notify``
        // fires on the main queue, every append has already published
        // its write to the collector.
        //
        // Reference: Issue #428 (Swift 6 data-race audit).
        let collector = URLCollector()
        let group = DispatchGroup()

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { collector.append(url) }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion(collector.snapshot())
        }
    }
}

// MARK: - URLCollector

/// Serial-queue-backed `[URL]` collector for thread-safe accumulation
/// from concurrent `NSItemProvider` completion handlers.
///
/// Marked `final` and `@unchecked Sendable` because all internal
/// mutation is funnelled through the private serial dispatch queue —
/// the queue is the synchronisation primitive that justifies the
/// `Sendable` conformance.
private final class URLCollector: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.mwbmpartners.MeedyaConverter.DropHandler.collector"
    )
    private var urls: [URL] = []

    /// Thread-safe append from any queue.
    func append(_ url: URL) {
        queue.sync { urls.append(url) }
    }

    /// Returns a snapshot of the collected URLs. Safe to call only
    /// after every contributing completion handler has returned
    /// (typically from inside a `DispatchGroup.notify` block).
    func snapshot() -> [URL] {
        queue.sync { urls }
    }
}
