// ============================================================================
// MeedyaConverter — ThumbnailCache
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import AppKit
import ImageIO

// MARK: - ThumbnailCache

/// Asynchronous thumbnail cache backed by `NSCache` for automatic memory-pressure eviction.
///
/// Uses `CGImageSource` with `kCGImageSourceThumbnailMaxPixelSize` to generate
/// efficiently downscaled thumbnails without loading full-resolution image data.
///
/// - Note: All public API is `@MainActor` to ensure safe SwiftUI integration.
///
/// Phase 17 — Image Conversion UI (Issue #229)
@MainActor @Observable
final class ThumbnailCache {

    // MARK: - Backing Store

    /// Cache keyed by `NSURL` so that `NSCache` can manage eviction automatically.
    /// The value wraps an `NSImage` thumbnail at the requested pixel size.
    private let cache = NSCache<NSURL, NSImage>()

    // MARK: - Initialiser

    init() {
        // Allow NSCache to evict freely under memory pressure; no hard count limit.
        cache.totalCostLimit = 100 * 1024 * 1024 // ~100 MB soft ceiling
    }

    // MARK: - Synchronous Lookup

    /// Returns a cached thumbnail for the given URL and size, or `nil` if not yet loaded.
    ///
    /// - Parameters:
    ///   - url: The source image file URL.
    ///   - size: The maximum pixel dimension (width or height) for the thumbnail.
    /// - Returns: The cached `NSImage` thumbnail, or `nil` if the cache has no entry.
    func thumbnail(for url: URL, size: CGFloat) -> NSImage? {
        let key = cacheKey(url: url, size: size)
        return cache.object(forKey: key)
    }

    // MARK: - Async Load

    /// Loads a thumbnail asynchronously, caches it, and returns the result.
    ///
    /// If the thumbnail is already cached, the cached version is returned immediately.
    /// Otherwise, a downscaled thumbnail is generated on a background thread using
    /// `CGImageSource` with `kCGImageSourceThumbnailMaxPixelSize`.
    ///
    /// - Parameters:
    ///   - url: The source image file URL.
    ///   - size: The maximum pixel dimension (width or height) for the thumbnail.
    /// - Returns: The generated `NSImage` thumbnail, or `nil` if the image could not be read.
    func loadThumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let key = cacheKey(url: url, size: size)

        // Return cached entry if available
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Generate thumbnail off the main thread
        let image = await Task.detached(priority: .utility) {
            Self.generateThumbnail(url: url, maxPixelSize: size)
        }.value

        if let image {
            let cost = image.tiffRepresentation?.count ?? 0
            cache.setObject(image, forKey: key, cost: cost)
        }

        return image
    }

    // MARK: - Preload

    /// Preloads thumbnails for a batch of URLs in the background.
    ///
    /// Already-cached entries are skipped. Use this after importing new images
    /// so thumbnails are warm before the user scrolls.
    ///
    /// - Parameters:
    ///   - urls: The image file URLs to preload.
    ///   - size: The maximum pixel dimension for each thumbnail.
    func preload(urls: [URL], size: CGFloat) {
        for url in urls {
            let key = cacheKey(url: url, size: size)
            guard cache.object(forKey: key) == nil else { continue }

            Task {
                _ = await self.loadThumbnail(for: url, size: size)
            }
        }
    }

    // MARK: - Clear

    /// Removes all cached thumbnails.
    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Private Helpers

    /// Builds a composite cache key from the URL and requested size so that
    /// different thumbnail sizes for the same file are stored independently.
    private func cacheKey(url: URL, size: CGFloat) -> NSURL {
        // Append the pixel size as a fragment to create a unique key per size
        let keyString = "\(url.absoluteString)#thumb_\(Int(size))"
        return NSURL(string: keyString) ?? (url as NSURL)
    }

    /// Generates a downscaled thumbnail using `CGImageSource`, which reads
    /// only the metadata and a minimal portion of pixel data needed for the
    /// requested size.
    ///
    /// - Parameters:
    ///   - url: The source image file URL.
    ///   - maxPixelSize: The maximum pixel dimension (width or height).
    /// - Returns: An `NSImage` of the thumbnail, or `nil` on failure.
    nonisolated private static func generateThumbnail(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true, // respect EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
