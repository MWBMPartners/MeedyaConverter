// ============================================================================
// MeedyaConverter — PerceptualHasher (Issue #449)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import CoreGraphics
import AVFoundation

// MARK: - FrameSampling

/// Seam between "get representative frames out of a media file" and the pure
/// hashing math in `PerceptualHasher` below.
///
/// Keeping this as a protocol means:
/// 1. The pure DCT/hash/compare math can be unit-tested with zero media
///    decode at all (synthetic pixel buffers only — see
///    `PerceptualHasherTests`).
/// 2. A future sampler (e.g. an ffmpeg-based frame extractor, once the
///    #373 `SuiteCore` bindings land) can substitute for
///    `AVAssetFrameSampler` without touching the hashing/grouping code.
///
/// Phase 11 — Duplicate File Detection (Issue #449)
public protocol FrameSampling: Sendable {

    /// Returns up to `count` representative frames from the asset at `url`,
    /// spread across its duration.
    ///
    /// Never throws. Returns an empty array for anything that can't be
    /// decoded — a missing file, a non-media file, a zero/invalid duration,
    /// a corrupt stream. Callers are expected to log and skip rather than
    /// treat an empty result as an exceptional condition (see
    /// `DuplicateDetector`'s perceptual-match path).
    func sampleFrames(from url: URL, count: Int) async -> [CGImage]
}

// MARK: - AVAssetFrameSampler

/// Default `FrameSampling` implementation, built on `AVAssetImageGenerator`.
///
/// Samples frames at fixed percentages of the asset duration (see
/// `PerceptualHasher.samplePositions(count:)`) rather than fixed timestamps,
/// so the same relative frames are compared regardless of clip length.
///
/// ## Concurrency
/// `AVAssetImageGenerator.copyCGImage(at:actualTime:)` is a synchronous,
/// thread-blocking decode call — unlike `AVAsynchronousKeyValueLoading`'s
/// `load(.duration)` (used below exactly as `DuplicateDetector
/// .findBySimilarDuration` already does), it must never run directly on the
/// calling actor, since this sampler is invoked from UI code
/// (`DuplicateFinderView.performScan()`) whose enclosing `Task` inherits the
/// main actor.
///
/// The frame-grab loop therefore runs inside a single `Task.detached`,
/// mirroring the established blocking-work pattern used throughout the app
/// (`ImageConversionView.startConversion`, `BurnSettingsView`,
/// `ThumbnailCache.loadThumbnail`): only `Sendable` values cross the
/// boundary — `URL` and `[Double]` offsets going in, `[CGImage]` coming out
/// (`CGImage` is `@unchecked Sendable` in CoreGraphics — an immutable,
/// thread-safe bitmap type since macOS 10.9). `AVAsset` /
/// `AVAssetImageGenerator` instances are never captured across the
/// boundary — because `AVAsset`'s Sendability is not guaranteed by the SDK,
/// a fresh asset/generator pair is constructed *inside* the detached task
/// instead of being built outside and captured in.
///
/// Phase 11 — Duplicate File Detection (Issue #449)
public struct AVAssetFrameSampler: FrameSampling {

    public init() {}

    public func sampleFrames(from url: URL, count: Int) async -> [CGImage] {
        guard count > 0 else { return [] }

        // Non-blocking, structured-concurrency duration probe. Runs
        // directly on the calling task — AVAsset property loading is
        // implemented as genuine async I/O, not a blocking call, so it
        // does not need `Task.detached`.
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else {
            return []
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return [] }

        let offsets = PerceptualHasher.samplePositions(count: count).map { durationSeconds * $0 }

        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            var images: [CGImage] = []
            images.reserveCapacity(offsets.count)
            for offset in offsets {
                let time = CMTime(seconds: offset, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    images.append(cgImage)
                }
            }
            return images
        }.value
    }
}

// MARK: - FileHashVector

/// A file's perceptual-hash fingerprint: one 64-bit pHash per sampled frame,
/// in sample-position order (see `PerceptualHasher.samplePositions(count:)`).
///
/// Phase 11 — Duplicate File Detection (Issue #449)
public struct FileHashVector: Sendable {

    /// The file this fingerprint belongs to.
    public let url: URL

    /// One pHash per successfully decoded/hashed sampled frame. May be
    /// shorter than the requested frame count if some frames failed to
    /// decode; never fabricated to compensate.
    public let hashes: [UInt64]

    public init(url: URL, hashes: [UInt64]) {
        self.url = url
        self.hashes = hashes
    }
}

// MARK: - PerceptualHasher

/// Pure perceptual-hash (pHash) math: grayscale reduction, a hand-rolled 2D
/// DCT, hash extraction, Hamming-distance comparison, and duplicate
/// grouping.
///
/// Every function below the frame-sampling seam is a **pure function** —
/// no I/O, no media decode, no `AVFoundation`, no randomness — so it can be
/// exercised directly in CI with synthetic pixel buffers (see
/// `PerceptualHasherTests`), independent of whether the host is macOS.
///
/// ## Algorithm
/// 1. A `CGImage` frame is downsampled to a 32×32 grayscale luma buffer
///    (`grayscale32(from:)`).
/// 2. A 2D DCT-II is applied to the 32×32 buffer (`dct2D(_:)`).
/// 3. The top-left 8×8 block of low-frequency coefficients is taken.
/// 4. The median of the 63 AC coefficients (the block excluding the DC
///    term, which is typically far larger than every AC coefficient and
///    would otherwise skew the threshold) is computed.
/// 5. All 64 coefficients — DC included — are compared against that
///    median to produce a 64-bit hash (`pHash(fromGray32:)`). This mirrors
///    the widely-used Krawetz/"pHash.org" DCT hash construction.
/// 6. Two frames are compared with `hammingDistance(_:_:)`; two files are
///    compared with `meanHammingDistance(_:_:)` across their aligned
///    per-frame hash vectors; a batch of files is clustered into duplicate
///    groups with `groupByDistance(_:threshold:)`.
///
/// Phase 11 — Duplicate File Detection (Issue #449)
public struct PerceptualHasher: Sendable {

    // MARK: - Tunables

    /// Default number of frames sampled per file.
    public static let defaultFrameCount = 5

    /// Default maximum mean Hamming distance (out of 64 possible bits) for
    /// two files to be considered duplicates. Lower is stricter.
    public static let defaultDistanceThreshold = 10

    /// Side length (in pixels) of the grayscale buffer each frame is
    /// reduced to before hashing.
    public static let frameSide = 32

    /// Side length (in coefficients) of the low-frequency DCT block used
    /// to build the hash. `blockSide * blockSide` must equal 64 to produce
    /// a `UInt64` hash.
    public static let blockSide = 8

    // MARK: - Sample Positions (pure)

    /// Returns `count` fractional positions (each in `(0, 1)`) spread
    /// across a clip's duration, evenly spaced between 10% and 90%.
    ///
    /// For the default `count` of 5 this yields exactly
    /// `[0.10, 0.30, 0.50, 0.70, 0.90]`. Avoiding the very start/end of the
    /// clip sidesteps black frames, fade-ins/outs, and title cards that
    /// would otherwise dominate the hash of an entire file.
    ///
    /// - Parameter count: Number of positions to generate.
    /// - Returns: Fractional offsets in ascending order; empty if
    ///   `count <= 0`.
    public static func samplePositions(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [0.5] }
        let step = 0.8 / Double(count - 1)
        return (0..<count).map { 0.1 + Double($0) * step }
    }

    // MARK: - Grayscale Reduction (impure — CoreGraphics only, no AVFoundation)

    /// Downsamples a `CGImage` to a `frameSide` × `frameSide` (32×32)
    /// 8-bit grayscale luma buffer, row-major, top-to-bottom.
    ///
    /// This step touches `CoreGraphics` but never `AVFoundation`, so while
    /// it is not a *pure* function (it depends on platform bitmap
    /// rendering), it needs no media decode and is not exercised by the
    /// unit tests — `pHash(fromGray32:)` below is the tested, pure
    /// boundary.
    ///
    /// - Parameter cgImage: The source frame.
    /// - Returns: `frameSide * frameSide` grayscale bytes, or `nil` if the
    ///   image is degenerate or the bitmap context could not be created.
    public static func grayscale32(from cgImage: CGImage) -> [UInt8]? {
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }

        let side = frameSide
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        guard let rawData = context.data else { return nil }
        let buffer = rawData.bindMemory(to: UInt8.self, capacity: side * side)
        return Array(UnsafeBufferPointer(start: buffer, count: side * side))
    }

    // MARK: - Discrete Cosine Transform (pure)

    /// Applies a 2D DCT-II to a square matrix via two passes of the 1D
    /// DCT-II (rows, then columns) — the standard separable-transform
    /// construction, and the only way a 32×32 DCT stays cheap
    /// (`O(2·N³)` instead of a naive `O(N⁴)`).
    ///
    /// No normalisation constants are applied (i.e. this is not an
    /// orthonormal DCT) — `pHash(fromGray32:)` only ever compares
    /// coefficients against each other's median, so a consistent scale
    /// factor is irrelevant to the result.
    ///
    /// For a **constant** input matrix, the DCT-II basis functions are
    /// exactly orthogonal to the constant (DC) function for every
    /// non-zero frequency, so every coefficient except `[0][0]` is exactly
    /// (up to floating-point rounding) zero — all the energy concentrates
    /// in the DC term. `PerceptualHasherTests` asserts exactly this.
    ///
    /// - Parameter matrix: A square (`N` × `N`) matrix of samples.
    /// - Returns: The `N` × `N` matrix of DCT-II coefficients, in the same
    ///   row/column layout (low frequencies toward `[0][0]`). Returns the
    ///   input unchanged if it is empty or not square.
    static func dct2D(_ matrix: [[Double]]) -> [[Double]] {
        let n = matrix.count
        guard n > 0, matrix.allSatisfy({ $0.count == n }) else { return matrix }

        let rowsTransformed = matrix.map { dct1D($0) }

        var result = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for col in 0..<n {
            let column = (0..<n).map { rowsTransformed[$0][col] }
            let transformedColumn = dct1D(column)
            for row in 0..<n {
                result[row][col] = transformedColumn[row]
            }
        }
        return result
    }

    /// 1D DCT-II: `X_k = Σ_i x_i · cos( (π / N) · (i + 0.5) · k )`.
    private static func dct1D(_ input: [Double]) -> [Double] {
        let n = input.count
        guard n > 0 else { return [] }

        var output = [Double](repeating: 0, count: n)
        let scale = Double.pi / Double(n)
        for k in 0..<n {
            var sum = 0.0
            for i in 0..<n {
                sum += input[i] * cos(scale * (Double(i) + 0.5) * Double(k))
            }
            output[k] = sum
        }
        return output
    }

    // MARK: - Hash (pure — the primary CI-tested entry point)

    /// Computes a 64-bit perceptual hash from a raw 32×32 grayscale luma
    /// buffer.
    ///
    /// This is the pure entry point exercised directly by
    /// `PerceptualHasherTests` — it takes no `CGImage`, no `AVFoundation`
    /// type, nothing platform-specific: just 1,024 bytes in, one `UInt64`
    /// out, always the same output for the same input.
    ///
    /// - Parameter pixels: Exactly `frameSide * frameSide` (1,024)
    ///   grayscale bytes, row-major, top-to-bottom — as produced by
    ///   `grayscale32(from:)`.
    /// - Returns: A 64-bit hash; bit `i` corresponds to row-major position
    ///   `i` (`i / blockSide`, `i % blockSide`) of the low-frequency 8×8
    ///   DCT block, set when that coefficient exceeds the AC-coefficient
    ///   median.
    public static func pHash(fromGray32 pixels: [UInt8]) -> UInt64 {
        precondition(
            pixels.count == frameSide * frameSide,
            "pHash(fromGray32:) requires exactly \(frameSide * frameSide) bytes " +
            "(a \(frameSide)x\(frameSide) grayscale buffer); got \(pixels.count)."
        )

        var matrix = [[Double]](repeating: [Double](repeating: 0, count: frameSide), count: frameSide)
        for row in 0..<frameSide {
            for col in 0..<frameSide {
                matrix[row][col] = Double(pixels[row * frameSide + col])
            }
        }

        let frequencies = dct2D(matrix)

        // Top-left blockSide x blockSide block = the lowest-frequency
        // coefficients, row-major. Index 0 is the DC term.
        var block: [Double] = []
        block.reserveCapacity(blockSide * blockSide)
        for row in 0..<blockSide {
            for col in 0..<blockSide {
                block.append(frequencies[row][col])
            }
        }

        // Median of the AC coefficients only (DC excluded — it is
        // typically far larger than every AC coefficient and would
        // otherwise dominate/skew the threshold). All 64 coefficients,
        // DC included, are then compared against this threshold.
        let threshold = median(of: Array(block.dropFirst()))

        var hash: UInt64 = 0
        for (index, value) in block.enumerated() where value > threshold {
            hash |= (UInt64(1) << UInt64(index))
        }
        return hash
    }

    /// Sorted-array median (average of the two middle elements for an
    /// even count). Pure, deterministic, no randomness.
    private static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    // MARK: - Comparison (pure)

    /// Bit-level Hamming distance between two 64-bit hashes (0…64).
    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Mean Hamming distance between two files' per-frame hash vectors,
    /// aligned by sample position (index `i` in `a` is compared against
    /// index `i` in `b`, since both are produced from the same
    /// `samplePositions(count:)` fractions).
    ///
    /// Compares only the overlapping prefix (`min(a.count, b.count)`
    /// frames) — if a file has fewer successfully-decoded frames than its
    /// counterpart, the shorter vector's positions are compared and any
    /// tail is ignored, rather than fabricating hashes for missing frames.
    ///
    /// - Returns: Mean distance across the overlapping frames, or
    ///   `Double(UInt64.bitWidth)` (64 — the maximum possible distance) if
    ///   there is no overlap (either vector is empty), so files with no
    ///   comparable frames are never mistaken for a close match.
    public static func meanHammingDistance(_ a: [UInt64], _ b: [UInt64]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return Double(UInt64.bitWidth) }

        var total = 0
        for i in 0..<n {
            total += hammingDistance(a[i], b[i])
        }
        return Double(total) / Double(n)
    }

    // MARK: - Grouping (pure)

    /// Transitively clusters files whose mean Hamming distance is within
    /// `threshold`, using union-find so that A≈B and B≈C groups A, B, and
    /// C together even if A and C alone would fall just outside the
    /// threshold.
    ///
    /// - Parameters:
    ///   - vectors: One `FileHashVector` per candidate file. Vectors with
    ///     an empty `hashes` array (nothing decodable) are still accepted
    ///     but can never match anything (see `meanHammingDistance`'s
    ///     no-overlap fallback), so they are naturally excluded from every
    ///     result group.
    ///   - threshold: Maximum mean Hamming distance (out of 64) for two
    ///     files to be considered duplicates. Defaults to
    ///     `defaultDistanceThreshold`.
    /// - Returns: Groups of two or more file URLs, in first-seen order;
    ///   singletons are omitted. Deterministic for a given input order —
    ///   no dictionary/set iteration order is relied upon.
    public static func groupByDistance(
        _ vectors: [FileHashVector],
        threshold: Int = defaultDistanceThreshold
    ) -> [[URL]] {
        guard vectors.count > 1 else { return [] }

        var parent = Array(0..<vectors.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func union(_ a: Int, _ b: Int) {
            let rootA = find(a)
            let rootB = find(b)
            if rootA != rootB {
                parent[rootA] = rootB
            }
        }

        for i in 0..<vectors.count {
            for j in (i + 1)..<vectors.count {
                let distance = meanHammingDistance(vectors[i].hashes, vectors[j].hashes)
                if distance <= Double(threshold) {
                    union(i, j)
                }
            }
        }

        // Build groups in first-seen order rather than iterating a
        // Dictionary's `.values` (unspecified order) so results are
        // deterministic for a given input order.
        var rootToGroupIndex: [Int: Int] = [:]
        var groups: [[Int]] = []
        for i in 0..<vectors.count {
            let root = find(i)
            if let groupIndex = rootToGroupIndex[root] {
                groups[groupIndex].append(i)
            } else {
                rootToGroupIndex[root] = groups.count
                groups.append([i])
            }
        }

        return groups
            .filter { $0.count >= 2 }
            .map { indices in indices.map { vectors[$0].url } }
    }

    // MARK: - End-to-End Convenience (impure — media I/O via the sampler)

    /// Samples and hashes a single file: `sampler.sampleFrames` →
    /// `grayscale32(from:)` → `pHash(fromGray32:)`.
    ///
    /// Frames that fail to decode or fail grayscale conversion are simply
    /// omitted (never fabricated), so the returned array may be shorter
    /// than `frameCount` — or empty, if nothing decoded at all.
    ///
    /// - Parameters:
    ///   - url: The candidate file.
    ///   - sampler: The `FrameSampling` implementation to use. Defaults to
    ///     `AVAssetFrameSampler()`.
    ///   - frameCount: Number of frames to request. Defaults to
    ///     `defaultFrameCount`.
    /// - Returns: One pHash per successfully sampled+hashed frame, in
    ///   sample-position order.
    public static func hashFile(
        at url: URL,
        sampler: any FrameSampling = AVAssetFrameSampler(),
        frameCount: Int = defaultFrameCount
    ) async -> [UInt64] {
        let frames = await sampler.sampleFrames(from: url, count: frameCount)
        return frames.compactMap(grayscale32).map(pHash(fromGray32:))
    }
}
