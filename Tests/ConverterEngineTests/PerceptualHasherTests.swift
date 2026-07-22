// ============================================================================
// MeedyaConverter — PerceptualHasherTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// Regression tests for `PerceptualHasher` — the pure DCT/pHash/compare/
/// group math behind Issue #449's perceptual duplicate matching.
///
/// Every test here works on synthetic, hand-constructed pixel buffers or
/// raw `UInt64` hash values. None of them touch `CGImage`, `AVFoundation`,
/// or any file on disk — they exercise exactly the pure boundary the
/// design calls out: `pHash(fromGray32:)`, `dct2D(_:)`,
/// `hammingDistance(_:_:)`, `meanHammingDistance(_:_:)`,
/// `groupByDistance(_:threshold:)`, and `samplePositions(count:)`.
///
/// Numeric expectations for the DCT-derived tests (gradient-vs-inverted,
/// perturbation robustness, constant-matrix DC concentration) were
/// cross-checked against an independent Python re-implementation of the
/// exact same algorithm before being written here, then given generous
/// safety margins to absorb any last-bit differences between platform
/// `cos()` implementations — so the assertions check qualitative
/// properties ("large", "small", "near zero") rather than brittle exact
/// values, except where the two sides are byte-for-byte identical inputs
/// (which must always produce byte-for-byte identical output on any
/// platform) or hand-picked integer bit patterns (which involve no
/// floating-point math at all).
final class PerceptualHasherTests: XCTestCase {

    // MARK: - Synthetic Buffer Builders

    private let side = PerceptualHasher.frameSide // 32

    /// A smooth horizontal gradient (row-invariant, columns ramp 0→255).
    /// Deliberately *not* flat, so the DCT has real AC energy to hash.
    private func gradientBuffer() -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: side * side)
        for row in 0..<side {
            for col in 0..<side {
                buffer[row * side + col] = UInt8(col * 255 / (side - 1))
            }
        }
        return buffer
    }

    /// Photographic negative of a buffer (`255 - value` per pixel).
    private func invertedBuffer(_ buffer: [UInt8]) -> [UInt8] {
        buffer.map { 255 - $0 }
    }

    /// A busier deterministic pattern (varies in both row and column, no
    /// two adjacent rows identical) so single-pixel perturbations exercise
    /// realistic, non-degenerate DCT coefficients.
    private func texturedBuffer() -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: side * side)
        for row in 0..<side {
            for col in 0..<side {
                let value = (row * 37 + col * 59 + (row * col) % 23) % 256
                buffer[row * side + col] = UInt8(value)
            }
        }
        return buffer
    }

    /// An unrelated deterministic remap of another buffer's pixels (not a
    /// simple negation), used as a "definitely different image" fixture.
    private func unrelatedBuffer(from buffer: [UInt8]) -> [UInt8] {
        buffer.map { UInt8((Int($0) * 173 + 41) % 256) }
    }

    /// Returns a copy of `buffer` with `delta` added (clamped to
    /// `0...255`) at each of `indices` — a small, localised perturbation.
    private func perturbedBuffer(_ buffer: [UInt8], indices: [Int], delta: Int) -> [UInt8] {
        var copy = buffer
        for index in indices {
            let newValue = Int(copy[index]) + delta
            copy[index] = UInt8(max(0, min(255, newValue)))
        }
        return copy
    }

    // MARK: - pHash: Identity

    func test_pHash_identicalBuffers_zeroDistance() {
        let buffer = gradientBuffer()
        let hashA = PerceptualHasher.pHash(fromGray32: buffer)
        let hashB = PerceptualHasher.pHash(fromGray32: buffer)

        XCTAssertEqual(hashA, hashB, "Hashing the exact same buffer twice must be deterministic.")
        XCTAssertEqual(PerceptualHasher.hammingDistance(hashA, hashB), 0)
    }

    func test_pHash_isDeterministicAcrossRepeatedCalls() {
        let buffer = texturedBuffer()
        let hashes = (0..<5).map { _ in PerceptualHasher.pHash(fromGray32: buffer) }
        XCTAssertEqual(Set(hashes).count, 1, "pHash must be a pure function of its input.")
    }

    // MARK: - pHash: Large Distance for Genuinely Different Images

    func test_pHash_gradientVsInverted_largeDistance() {
        let gradient = gradientBuffer()
        let inverted = invertedBuffer(gradient)

        let hashGradient = PerceptualHasher.pHash(fromGray32: gradient)
        let hashInverted = PerceptualHasher.pHash(fromGray32: inverted)

        let distance = PerceptualHasher.hammingDistance(hashGradient, hashInverted)
        // A photographic negative flips the sign of every AC coefficient,
        // which flips nearly every thresholded bit — expect the distance
        // to sit far above the default duplicate threshold (10).
        XCTAssertGreaterThan(
            distance, 20,
            "A gradient and its photographic negative should hash to very different fingerprints."
        )
        XCTAssertGreaterThan(
            Double(distance), Double(PerceptualHasher.defaultDistanceThreshold),
            "Inverted images must not be grouped as duplicates under the default threshold."
        )
    }

    func test_pHash_unrelatedPatterns_largeDistance() {
        let textured = texturedBuffer()
        let unrelated = unrelatedBuffer(from: textured)

        let distance = PerceptualHasher.hammingDistance(
            PerceptualHasher.pHash(fromGray32: textured),
            PerceptualHasher.pHash(fromGray32: unrelated)
        )
        XCTAssertGreaterThan(distance, 15, "Unrelated images should not hash close together.")
    }

    // MARK: - pHash: Small Distance for Minor Perturbations

    func test_pHash_smallPerturbation_smallDistance() {
        let original = texturedBuffer()
        let perturbed = perturbedBuffer(original, indices: [0, 100, 500, 777, 1023], delta: 10)

        let distance = PerceptualHasher.hammingDistance(
            PerceptualHasher.pHash(fromGray32: original),
            PerceptualHasher.pHash(fromGray32: perturbed)
        )
        XCTAssertLessThanOrEqual(
            distance, PerceptualHasher.defaultDistanceThreshold,
            "A handful of small pixel-value tweaks should stay within the duplicate threshold."
        )
    }

    // MARK: - dct2D: Known Simple Pattern (Constant Buffer)

    func test_dct2D_constantMatrix_allEnergyConcentratesInDC() {
        let value = 7.0
        let matrix = [[Double]](repeating: [Double](repeating: value, count: side), count: side)

        let frequencies = PerceptualHasher.dct2D(matrix)

        // DC term: sum of `value` over every cell, since cos(0) == 1 for
        // every contributing term in both DCT passes.
        let expectedDC = value * Double(side * side)
        XCTAssertEqual(frequencies[0][0], expectedDC, accuracy: 1e-6)

        // Every AC (non-DC) coefficient must be ~0: the DCT-II basis
        // functions are exactly orthogonal to a constant signal.
        for row in 0..<side {
            for col in 0..<side where !(row == 0 && col == 0) {
                XCTAssertEqual(
                    frequencies[row][col], 0, accuracy: 1e-6,
                    "AC coefficient [\(row)][\(col)] should be ~0 for a constant input."
                )
            }
        }
    }

    func test_dct2D_emptyMatrix_returnsEmpty() {
        XCTAssertTrue(PerceptualHasher.dct2D([]).isEmpty)
    }

    func test_dct2D_nonSquareMatrix_returnsUnchanged() {
        // Row lengths (3, 2) don't match the row count (2) → not square;
        // the pure function must fail safe rather than crash or truncate.
        let jagged: [[Double]] = [[1, 2, 3], [4, 5]]
        let result = PerceptualHasher.dct2D(jagged)
        XCTAssertEqual(result.count, jagged.count)
        for (lhs, rhs) in zip(result, jagged) {
            XCTAssertEqual(lhs, rhs)
        }
    }

    // MARK: - hammingDistance

    func test_hammingDistance_identicalValues_zero() {
        for value: UInt64 in [0, .max, 0x0F0F_0F0F_0F0F_0F0F, 1] {
            XCTAssertEqual(PerceptualHasher.hammingDistance(value, value), 0)
        }
    }

    func test_hammingDistance_allBitsDiffer_sixtyFour() {
        XCTAssertEqual(PerceptualHasher.hammingDistance(0, .max), 64)
    }

    func test_hammingDistance_knownBitPattern() {
        // 0b1010 vs 0b0101 — all 4 low bits differ, nothing else set.
        XCTAssertEqual(PerceptualHasher.hammingDistance(0b1010, 0b0101), 4)
    }

    func test_hammingDistance_isSymmetric() {
        let a: UInt64 = 0x1234_5678_9ABC_DEF0
        let b: UInt64 = 0x0FED_CBA9_8765_4321
        XCTAssertEqual(
            PerceptualHasher.hammingDistance(a, b),
            PerceptualHasher.hammingDistance(b, a)
        )
    }

    // MARK: - meanHammingDistance

    func test_meanHammingDistance_alignedFrames_averagesPerFrameDistance() {
        let a: [UInt64] = [0, 0, 0]
        // Distances vs `a`: 1 bit, 2 bits, 3 bits set respectively.
        let b: [UInt64] = [0b1, 0b11, 0b111]

        XCTAssertEqual(PerceptualHasher.meanHammingDistance(a, b), 2.0, accuracy: 1e-9)
    }

    func test_meanHammingDistance_differingLengths_usesOverlapOnly() {
        let a: [UInt64] = [0, 0, 0, 0]
        let b: [UInt64] = [0xFF, 0] // only 2 frames

        // Only the first 2 entries of `a` are compared: distances 8 and 0.
        XCTAssertEqual(PerceptualHasher.meanHammingDistance(a, b), 4.0, accuracy: 1e-9)
    }

    func test_meanHammingDistance_noOverlap_returnsMaxDistance() {
        XCTAssertEqual(PerceptualHasher.meanHammingDistance([], [0, 0]), 64.0, accuracy: 1e-9)
        XCTAssertEqual(PerceptualHasher.meanHammingDistance([0], []), 64.0, accuracy: 1e-9)
        XCTAssertEqual(PerceptualHasher.meanHammingDistance([], []), 64.0, accuracy: 1e-9)
    }

    // MARK: - groupByDistance

    func test_groupByDistance_closeFilesGroupTogether_distantFileExcluded() {
        let fileA = URL(fileURLWithPath: "/tmp/a.mp4")
        let fileB = URL(fileURLWithPath: "/tmp/b.mp4")
        let fileC = URL(fileURLWithPath: "/tmp/c.mp4")

        let gradient = gradientBuffer()
        let closeHash = PerceptualHasher.pHash(fromGray32: gradient)
        let farHash = PerceptualHasher.pHash(fromGray32: unrelatedBuffer(from: gradient))

        let vectors = [
            FileHashVector(url: fileA, hashes: [closeHash]),
            FileHashVector(url: fileB, hashes: [closeHash]),
            FileHashVector(url: fileC, hashes: [farHash]),
        ]

        let groups = PerceptualHasher.groupByDistance(vectors, threshold: PerceptualHasher.defaultDistanceThreshold)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0]), Set([fileA, fileB]))
        XCTAssertFalse(groups.flatMap { $0 }.contains(fileC))
    }

    func test_groupByDistance_transitiveClustering_bridgesBeyondDirectThreshold() {
        let fileA = URL(fileURLWithPath: "/tmp/a.mp4")
        let fileB = URL(fileURLWithPath: "/tmp/b.mp4")
        let fileC = URL(fileURLWithPath: "/tmp/c.mp4")

        // Hand-picked bit patterns — no DCT/floating-point involved, so
        // the distances below are exact by construction:
        //   hashA = 0
        //   hashB = bits 0..7 set        → distance(A, B) = 8
        //   hashC = hashB ^ bits 8..16 set → distance(B, C) = 9
        // giving distance(A, C) = popcount(bits 0..16 set) = 17.
        let hashA: UInt64 = 0
        let hashB: UInt64 = 0x0000_0000_0000_00FF // bits 0-7
        let bits8Through16: UInt64 = 0x0000_0000_0001_FF00 // bits 8-16 (9 bits)
        let hashC: UInt64 = hashB ^ bits8Through16

        XCTAssertEqual(PerceptualHasher.hammingDistance(hashA, hashB), 8)
        XCTAssertEqual(PerceptualHasher.hammingDistance(hashB, hashC), 9)
        XCTAssertEqual(PerceptualHasher.hammingDistance(hashA, hashC), 17)

        let threshold = 10 // A-B and B-C are within threshold; A-C alone is not.
        let vectors = [
            FileHashVector(url: fileA, hashes: [hashA]),
            FileHashVector(url: fileB, hashes: [hashB]),
            FileHashVector(url: fileC, hashes: [hashC]),
        ]

        let groups = PerceptualHasher.groupByDistance(vectors, threshold: threshold)

        XCTAssertEqual(groups.count, 1, "A-B and B-C should transitively merge into a single group.")
        XCTAssertEqual(Set(groups[0]), Set([fileA, fileB, fileC]))
    }

    func test_groupByDistance_thresholdBoundary_lessThanOrEqualIncluded() {
        let fileA = URL(fileURLWithPath: "/tmp/a.mp4")
        let fileB = URL(fileURLWithPath: "/tmp/b.mp4")

        // Exactly 10 bits differ.
        let hashA: UInt64 = 0
        let hashB: UInt64 = 0x0000_0000_0000_03FF // 10 low bits set
        XCTAssertEqual(PerceptualHasher.hammingDistance(hashA, hashB), 10)

        let vectors = [
            FileHashVector(url: fileA, hashes: [hashA]),
            FileHashVector(url: fileB, hashes: [hashB]),
        ]

        let grouped = PerceptualHasher.groupByDistance(vectors, threshold: 10)
        XCTAssertEqual(grouped.count, 1, "A distance exactly equal to the threshold must still be grouped (<=).")

        let notGrouped = PerceptualHasher.groupByDistance(vectors, threshold: 9)
        XCTAssertTrue(notGrouped.isEmpty, "A distance one above the threshold must not be grouped.")
    }

    func test_groupByDistance_singleFile_returnsNoGroups() {
        let vectors = [FileHashVector(url: URL(fileURLWithPath: "/tmp/a.mp4"), hashes: [0])]
        XCTAssertTrue(PerceptualHasher.groupByDistance(vectors).isEmpty)
    }

    func test_groupByDistance_emptyInput_returnsNoGroups() {
        XCTAssertTrue(PerceptualHasher.groupByDistance([]).isEmpty)
    }

    func test_groupByDistance_filesWithNoHashes_neverGroup() {
        // A file with zero decoded frames (represented as an empty hash
        // vector, per DuplicateDetector's "skip, don't fabricate" contract)
        // must never be treated as matching anything, including another
        // equally-empty file.
        let fileA = URL(fileURLWithPath: "/tmp/a.mp4")
        let fileB = URL(fileURLWithPath: "/tmp/b.mp4")
        let vectors = [
            FileHashVector(url: fileA, hashes: []),
            FileHashVector(url: fileB, hashes: []),
        ]
        XCTAssertTrue(PerceptualHasher.groupByDistance(vectors).isEmpty)
    }

    // MARK: - samplePositions

    func test_samplePositions_defaultFive_matchesTenThroughNinetyPercentSpec() {
        let positions = PerceptualHasher.samplePositions(count: 5)
        let expected = [0.10, 0.30, 0.50, 0.70, 0.90]

        XCTAssertEqual(positions.count, expected.count)
        for (actual, wanted) in zip(positions, expected) {
            XCTAssertEqual(actual, wanted, accuracy: 1e-9)
        }
    }

    func test_samplePositions_countOne_returnsMidpoint() {
        XCTAssertEqual(PerceptualHasher.samplePositions(count: 1), [0.5])
    }

    func test_samplePositions_nonPositiveCount_returnsEmpty() {
        XCTAssertTrue(PerceptualHasher.samplePositions(count: 0).isEmpty)
        XCTAssertTrue(PerceptualHasher.samplePositions(count: -3).isEmpty)
    }

    func test_samplePositions_isStrictlyAscendingAndInBounds() {
        let positions = PerceptualHasher.samplePositions(count: 7)
        XCTAssertEqual(positions.count, 7)
        for position in positions {
            XCTAssertGreaterThan(position, 0)
            XCTAssertLessThan(position, 1)
        }
        for i in 1..<positions.count {
            XCTAssertGreaterThan(positions[i], positions[i - 1])
        }
    }
}
