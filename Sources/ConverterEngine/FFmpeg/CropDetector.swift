// ============================================================================
// MeedyaConverter — CropDetector
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - CropRect

/// A crop rectangle detected by FFmpeg's cropdetect filter.
public struct CropRect: Codable, Sendable, Equatable {
    /// Width of the cropped area in pixels.
    public let width: Int
    /// Height of the cropped area in pixels.
    public let height: Int
    /// X offset from the left edge in pixels.
    public let x: Int
    /// Y offset from the top edge in pixels.
    public let y: Int

    public init(width: Int, height: Int, x: Int, y: Int) {
        self.width = width
        self.height = height
        self.x = x
        self.y = y
    }

    /// The FFmpeg crop filter string (e.g., "crop=1920:800:0:140").
    public var filterString: String {
        "crop=\(width):\(height):\(x):\(y)"
    }

    /// Human-readable description of the crop.
    public var displayString: String {
        "\(width)x\(height)+\(x)+\(y)"
    }

    /// Whether the crop actually removes any pixels from the given source dimensions.
    public func isCropping(sourceWidth: Int, sourceHeight: Int) -> Bool {
        width < sourceWidth || height < sourceHeight
    }

    /// Aspect ratio of the cropped area.
    public var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }
}

// MARK: - CropDetectionResult

/// The result of an automatic crop detection analysis.
public struct CropDetectionResult: Sendable {
    /// The recommended crop rectangle (most common detection).
    public let recommendedCrop: CropRect

    /// All detected crop values during the analysis (for preview/validation).
    public let detectedCrops: [CropRect]

    /// Confidence level (0.0–1.0) based on consistency of detections.
    public let confidence: Double

    /// The source video dimensions.
    public let sourceWidth: Int
    public let sourceHeight: Int

    /// Memberwise initializer.
    public init(
        recommendedCrop: CropRect,
        detectedCrops: [CropRect],
        confidence: Double,
        sourceWidth: Int,
        sourceHeight: Int
    ) {
        self.recommendedCrop = recommendedCrop
        self.detectedCrops = detectedCrops
        self.confidence = confidence
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
    }

    /// Whether cropping would actually change the output dimensions.
    public var willCrop: Bool {
        recommendedCrop.isCropping(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    /// Percentage of pixels that would be removed by cropping.
    public var cropPercentage: Double {
        let sourcePixels = Double(sourceWidth * sourceHeight)
        let croppedPixels = Double(recommendedCrop.width * recommendedCrop.height)
        guard sourcePixels > 0 else { return 0 }
        return (1.0 - croppedPixels / sourcePixels) * 100
    }

    /// A human-readable summary of the crop detection.
    public var summary: String {
        if willCrop {
            return "\(recommendedCrop.displayString) (removes \(String(format: "%.1f", cropPercentage))% black bars, confidence \(String(format: "%.0f", confidence * 100))%)"
        } else {
            return "No black bars detected"
        }
    }
}

// MARK: - CropDetector

/// Detects black bars (letterboxing, pillarboxing, postage-stamp) in video files
/// using FFmpeg's `cropdetect` filter.
///
/// Analyses a sample of frames across the video duration and determines the
/// most consistent crop rectangle. Supports configurable threshold, number
/// of sample points, and round values.
///
/// Usage:
/// ```swift
/// let detector = CropDetector(ffmpegPath: "/usr/local/bin/ffmpeg")
/// let result = try await detector.detect(url: videoURL, sourceWidth: 1920, sourceHeight: 1080)
/// if result.willCrop {
///     print("Crop filter: \(result.recommendedCrop.filterString)")
/// }
/// ```
public final class CropDetector: @unchecked Sendable {

    // MARK: - Properties

    /// Path to the FFmpeg binary.
    private let ffmpegPath: String

    /// The black level threshold for cropdetect (0–255). Lower = stricter.
    /// Default 24 works well for most content; increase for noisy blacks.
    public var threshold: Int = 24

    /// Number of sample points across the video duration to analyse.
    /// More samples = more accurate but slower. Default 10 is a good balance.
    public var sampleCount: Int = 10

    /// Round crop values to this multiple (2 = even dimensions for codec compatibility).
    public var round: Int = 2

    /// How many frames to analyse at each sample point.
    public var framesPerSample: Int = 5

    // MARK: - Initialiser

    /// Create a crop detector.
    ///
    /// - Parameter ffmpegPath: Path to the FFmpeg binary.
    public init(ffmpegPath: String) {
        self.ffmpegPath = ffmpegPath
    }

    // MARK: - Detection

    /// Detect black bars in a video file.
    ///
    /// Samples frames at evenly spaced intervals across the video and runs
    /// FFmpeg's cropdetect filter. Returns the most consistent crop rectangle.
    ///
    /// - Parameters:
    ///   - url: The video file URL.
    ///   - duration: The video duration in seconds. If nil, samples at fixed offsets.
    ///   - sourceWidth: The video's original width in pixels.
    ///   - sourceHeight: The video's original height in pixels.
    /// - Returns: The crop detection result.
    /// - Throws: If FFmpeg fails to analyse the file.
    public func detect(
        url: URL,
        duration: TimeInterval? = nil,
        sourceWidth: Int,
        sourceHeight: Int
    ) async throws -> CropDetectionResult {
        // Calculate sample timestamps evenly distributed across the video
        let timestamps = sampleTimestamps(duration: duration)

        // Run cropdetect at each sample point
        var allCrops: [CropRect] = []

        for timestamp in timestamps {
            let crops = try await runCropDetect(url: url, seekTo: timestamp)
            allCrops.append(contentsOf: crops)
        }

        // Find the most common crop (mode)
        let recommended = mostCommonCrop(from: allCrops, sourceWidth: sourceWidth, sourceHeight: sourceHeight)

        // Calculate confidence based on how consistent the detections were
        let matchCount = allCrops.filter { $0 == recommended }.count
        let confidence = allCrops.isEmpty ? 0.0 : Double(matchCount) / Double(allCrops.count)

        return CropDetectionResult(
            recommendedCrop: recommended,
            detectedCrops: allCrops,
            confidence: confidence,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
    }

    // MARK: - Private

    /// Generate evenly-spaced sample timestamps across the video duration.
    private func sampleTimestamps(duration: TimeInterval?) -> [TimeInterval] {
        guard let dur = duration, dur > 0 else {
            // No duration known — sample at fixed offsets (skip first/last 5%)
            return stride(from: 10.0, through: 120.0, by: 15.0).map { $0 }
        }

        // Skip the first and last 5% to avoid intros/credits with different framing
        let start = dur * 0.05
        let end = dur * 0.95
        let effectiveDuration = end - start

        guard effectiveDuration > 0, sampleCount > 0 else { return [dur / 2] }

        let step = effectiveDuration / Double(sampleCount)
        return (0..<sampleCount).map { start + Double($0) * step }
    }

    /// Run cropdetect at a specific timestamp and parse the output.
    private func runCropDetect(url: URL, seekTo: TimeInterval) async throws -> [CropRect] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-ss", String(format: "%.2f", seekTo),
            "-i", url.path,
            "-vframes", "\(framesPerSample)",
            "-vf", "cropdetect=limit=\(threshold):round=\(round):reset=1",
            "-f", "null",
            "-hide_banner",
            "-"
        ]

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()

                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                let crops = Self.parseCropDetectOutput(output)
                continuation.resume(returning: crops)
            }
        }
    }

    /// Parse cropdetect output lines for crop values.
    ///
    /// FFmpeg outputs lines like:
    /// `[Parsed_cropdetect_0 @ 0x...] x1:0 x2:1919 y1:140 y2:939 w:1920 h:800 x:0 y:140 pts:12345 ...`
    public static func parseCropDetectOutput(_ output: String) -> [CropRect] {
        let lines = output.split(separator: "\n")
        var crops: [CropRect] = []

        for line in lines {
            guard line.contains("cropdetect") else { continue }
            guard let crop = parseCropLine(String(line)) else { continue }
            crops.append(crop)
        }

        return crops
    }

    /// Parse a single cropdetect output line.
    private static func parseCropLine(_ line: String) -> CropRect? {
        // Extract w:N h:N x:N y:N from the line
        func extractInt(key: String) -> Int? {
            guard let range = line.range(of: "\(key):") else { return nil }
            let afterKey = line[range.upperBound...]
            let digits = afterKey.prefix(while: { $0.isNumber || $0 == "-" })
            return Int(digits)
        }

        guard let w = extractInt(key: "w"),
              let h = extractInt(key: "h"),
              let x = extractInt(key: "x"),
              let y = extractInt(key: "y"),
              w > 0, h > 0 else {
            return nil
        }

        return CropRect(width: w, height: h, x: x, y: y)
    }

    /// Find the most commonly detected crop rectangle.
    private func mostCommonCrop(
        from crops: [CropRect],
        sourceWidth: Int,
        sourceHeight: Int
    ) -> CropRect {
        guard !crops.isEmpty else {
            // No crops detected — return full frame (no cropping)
            return CropRect(width: sourceWidth, height: sourceHeight, x: 0, y: 0)
        }

        // Count occurrences of each unique crop
        var counts: [CropRect: Int] = [:]
        for crop in crops {
            counts[crop, default: 0] += 1
        }

        // Return the most common
        return counts.max(by: { $0.value < $1.value })?.key
            ?? CropRect(width: sourceWidth, height: sourceHeight, x: 0, y: 0)
    }
}

// MARK: - CropRect Hashable

extension CropRect: Hashable {}
