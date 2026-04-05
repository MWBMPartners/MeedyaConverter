// ============================================================================
// MeedyaConverter — DuplicateDetector (Issue #290)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import CryptoKit
import AVFoundation

// MARK: - MatchType

/// The method used to determine whether two media files are duplicates.
///
/// Phase 11 — Duplicate File Detection (Issue #290)
public enum MatchType: String, Sendable, CaseIterable {

    /// SHA-256 hash of the first 64 KB combined with exact file size.
    case exactHash

    /// Files with identical byte sizes.
    case sameSize

    /// Files whose durations differ by at most 1 second.
    case similarDuration

    /// Perceptual fingerprint comparison (placeholder for future implementation).
    case perceptual
}

// MARK: - DuplicateGroup

/// A group of files identified as duplicates by a given `MatchType`.
///
/// Phase 11 — Duplicate File Detection (Issue #290)
public struct DuplicateGroup: Identifiable, Sendable {

    /// Unique identifier for this duplicate group.
    public let id: UUID

    /// The file URLs that are considered duplicates of one another.
    public let files: [URL]

    /// The detection method that produced this group.
    public let matchType: MatchType

    /// The file size in bytes (common to all files when `matchType` is `.sameSize`
    /// or `.exactHash`; representative size for other methods).
    public let fileSize: Int64

    /// Memberwise initialiser.
    public init(id: UUID = UUID(), files: [URL], matchType: MatchType, fileSize: Int64) {
        self.id = id
        self.files = files
        self.matchType = matchType
        self.fileSize = fileSize
    }
}

// MARK: - DuplicateDetector

/// Scans a collection of file URLs and returns groups of probable duplicates
/// according to the chosen `MatchType`.
///
/// Phase 11 — Duplicate File Detection (Issue #290)
public struct DuplicateDetector: Sendable {

    // MARK: - Quick Hash

    /// Computes a SHA-256 digest of the first 64 KB of the file at the given URL.
    ///
    /// Returns the hex-encoded hash string, or `nil` if the file cannot be read.
    ///
    /// - Parameter url: The file URL to hash.
    /// - Returns: A lowercase hex SHA-256 string, or `nil` on failure.
    public static func quickHash(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 65_536) // 64 KB
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Find Duplicates

    /// Scans the provided URLs and groups files identified as duplicates.
    ///
    /// - Parameters:
    ///   - urls: The file URLs to analyse.
    ///   - method: The matching algorithm to apply.
    /// - Returns: An array of `DuplicateGroup` instances, each containing two or more files.
    public static func findDuplicates(in urls: [URL], method: MatchType) async -> [DuplicateGroup] {
        switch method {
        case .exactHash:
            return findByExactHash(urls)
        case .sameSize:
            return findBySameSize(urls)
        case .similarDuration:
            return await findBySimilarDuration(urls)
        case .perceptual:
            // Perceptual hashing is a placeholder; returns empty for now.
            return []
        }
    }

    // MARK: - Private Helpers

    /// Groups files by SHA-256(first 64 KB) + file size.
    private static func findByExactHash(_ urls: [URL]) -> [DuplicateGroup] {
        var buckets: [String: [URL]] = [:]

        for url in urls {
            guard let size = fileSize(for: url),
                  let hash = quickHash(url: url) else { continue }
            let key = "\(hash)_\(size)"
            buckets[key, default: []].append(url)
        }

        return buckets.values.compactMap { files in
            guard files.count >= 2 else { return nil }
            let size = fileSize(for: files[0]) ?? 0
            return DuplicateGroup(files: files, matchType: .exactHash, fileSize: size)
        }
    }

    /// Groups files by exact byte size.
    private static func findBySameSize(_ urls: [URL]) -> [DuplicateGroup] {
        var buckets: [Int64: [URL]] = [:]

        for url in urls {
            guard let size = fileSize(for: url) else { continue }
            buckets[size, default: []].append(url)
        }

        return buckets.compactMap { size, files in
            guard files.count >= 2 else { return nil }
            return DuplicateGroup(files: files, matchType: .sameSize, fileSize: size)
        }
    }

    /// Groups files whose durations differ by at most 1 second.
    private static func findBySimilarDuration(_ urls: [URL]) async -> [DuplicateGroup] {
        struct Entry: Sendable {
            let url: URL
            let duration: Double
            let size: Int64
        }

        var entries: [Entry] = []
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration) else { continue }
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { continue }
            let size = fileSize(for: url) ?? 0
            entries.append(Entry(url: url, duration: seconds, size: size))
        }

        // Sort by duration then sweep for clusters within 1-second tolerance.
        let sorted = entries.sorted { $0.duration < $1.duration }
        var groups: [DuplicateGroup] = []
        var used = Set<Int>()

        for i in sorted.indices where !used.contains(i) {
            var cluster: [URL] = [sorted[i].url]
            for j in (i + 1)..<sorted.count {
                if sorted[j].duration - sorted[i].duration > 1.0 { break }
                if !used.contains(j) {
                    cluster.append(sorted[j].url)
                    used.insert(j)
                }
            }
            if cluster.count >= 2 {
                used.insert(i)
                groups.append(
                    DuplicateGroup(
                        files: cluster,
                        matchType: .similarDuration,
                        fileSize: sorted[i].size
                    )
                )
            }
        }

        return groups
    }

    /// Returns the file size in bytes for the given URL, or `nil` on failure.
    private static func fileSize(for url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return size
    }
}
