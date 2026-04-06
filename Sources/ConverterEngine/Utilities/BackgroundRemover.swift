// ============================================================================
// MeedyaConverter — BackgroundRemover (Issue #300)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import Vision
import CoreImage
import CoreGraphics
import AppKit

// MARK: - BackgroundRemovalQuality

/// Processing quality level for background removal.
///
/// Higher quality levels produce better segmentation masks but require
/// more processing time. The quality level maps directly to the Vision
/// framework's ``VNGeneratePersonSegmentationRequest.QualityLevel``.
///
/// Phase 11 — Background Removal (Issue #300)
public enum BackgroundRemovalQuality: String, Codable, Sendable, CaseIterable {

    /// Fast processing with lower mask quality.
    /// Suitable for batch operations or previews.
    case fast

    /// Balanced trade-off between speed and quality.
    /// Good for most use cases.
    case balanced

    /// Highest quality segmentation mask.
    /// Best for final output where edge precision matters.
    case accurate
}

// MARK: - BackgroundRemovalConfig

/// Configuration for background removal operations.
///
/// Controls the quality/speed trade-off, output format, and optional
/// replacement colour for the removed background region.
///
/// Phase 11 — Background Removal (Issue #300)
public struct BackgroundRemovalConfig: Codable, Sendable {

    /// The segmentation quality level.
    public var qualityLevel: BackgroundRemovalQuality

    /// The output image format.
    /// Uses the existing ``ImageFormat`` enum from ``ImageConverter``.
    /// Only ``.png``, ``.jpeg``, and ``.tiff`` are meaningful for background
    /// removal output.
    public var outputFormat: ImageFormat

    /// Optional hex colour string (e.g. ``"#00FF00"``) to fill the removed
    /// background area. When `nil`, the background is made transparent
    /// (PNG/TIFF only; JPEG defaults to white).
    public var replaceColor: String?

    /// Creates a new background removal configuration.
    ///
    /// - Parameters:
    ///   - qualityLevel: Segmentation quality (default: `.balanced`).
    ///   - outputFormat: Output image format (default: `.png`).
    ///   - replaceColor: Optional hex colour to replace background, or `nil` for transparent.
    public init(
        qualityLevel: BackgroundRemovalQuality = .balanced,
        outputFormat: ImageFormat = .png,
        replaceColor: String? = nil
    ) {
        self.qualityLevel = qualityLevel
        self.outputFormat = outputFormat
        self.replaceColor = replaceColor
    }
}

// MARK: - BackgroundRemovalError

/// Errors that can occur during background removal operations.
///
/// Phase 11 — Background Removal (Issue #300)
public enum BackgroundRemovalError: LocalizedError, Sendable {

    /// The input image could not be loaded or decoded.
    case imageLoadFailed(path: String)

    /// Vision person segmentation request failed.
    case segmentationFailed(underlying: String)

    /// The output image could not be written to disk.
    case outputWriteFailed(path: String)

    /// The specified output format does not support the requested operation.
    case unsupportedFormat(details: String)

    public var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let path):
            return "Failed to load image: \(path)"
        case .segmentationFailed(let underlying):
            return "Person segmentation failed: \(underlying)"
        case .outputWriteFailed(let path):
            return "Failed to write output image: \(path)"
        case .unsupportedFormat(let details):
            return "Unsupported format: \(details)"
        }
    }
}

// MARK: - BackgroundRemover

/// Removes backgrounds from images using Apple Vision's person segmentation.
///
/// Uses ``VNGeneratePersonSegmentationRequest`` (macOS 15+) to generate
/// a high-quality segmentation mask, then composites the foreground
/// subject over a transparent or solid-colour background.
///
/// Supports single-image processing, batch operations, and configurable
/// quality levels.
///
/// Usage:
/// ```swift
/// let config = BackgroundRemovalConfig(qualityLevel: .accurate, outputFormat: .png)
/// try await BackgroundRemover.removeBackground(
///     inputURL: sourceURL,
///     outputURL: destURL,
///     config: config
/// )
/// ```
///
/// Phase 11 — Background Removal (Issue #300)
public struct BackgroundRemover: Sendable {

    // MARK: - Public API

    /// Removes the background from an image and writes the result to disk.
    ///
    /// - Parameters:
    ///   - inputURL: File URL of the source image.
    ///   - outputURL: File URL for the processed output.
    ///   - config: Background removal configuration.
    /// - Throws: ``BackgroundRemovalError`` if processing fails.
    public static func removeBackground(
        inputURL: URL,
        outputURL: URL,
        config: BackgroundRemovalConfig
    ) async throws {
        let imageData = try await processImage(inputURL: inputURL, config: config)

        do {
            try imageData.write(to: outputURL)
        } catch {
            throw BackgroundRemovalError.outputWriteFailed(path: outputURL.path)
        }
    }

    /// Processes an image and returns the result as image data with
    /// the background removed (or replaced).
    ///
    /// - Parameters:
    ///   - inputURL: File URL of the source image.
    ///   - config: Background removal configuration.
    /// - Returns: Image data in the format specified by `config.outputFormat`.
    /// - Throws: ``BackgroundRemovalError`` if processing fails.
    public static func processImage(
        inputURL: URL,
        config: BackgroundRemovalConfig
    ) async throws -> Data {
        // Load the source image
        guard let ciImage = CIImage(contentsOf: inputURL) else {
            throw BackgroundRemovalError.imageLoadFailed(path: inputURL.path)
        }

        // Generate segmentation mask
        let maskImage = try await generateSegmentationMask(
            imageURL: inputURL,
            qualityLevel: config.qualityLevel
        )

        // Composite foreground over background
        let composited = compositeImage(
            original: ciImage,
            mask: maskImage,
            replaceColor: config.replaceColor
        )

        // Render to the requested format
        let context = CIContext()
        let outputData: Data?

        let colorSpace = ciImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!

        switch config.outputFormat {
        case .png:
            outputData = context.pngRepresentation(of: composited, format: .RGBA8, colorSpace: colorSpace)
        case .tiff:
            outputData = context.tiffRepresentation(of: composited, format: .RGBA8, colorSpace: colorSpace)
        default:
            // JPEG and all other formats — no alpha channel support
            outputData = context.jpegRepresentation(of: composited, colorSpace: colorSpace)
        }

        guard let data = outputData else {
            throw BackgroundRemovalError.unsupportedFormat(
                details: "Failed to render output in \(config.outputFormat.rawValue) format"
            )
        }

        return data
    }

    /// Removes backgrounds from multiple images in batch.
    ///
    /// Processes each input image sequentially and writes the results
    /// to the specified output directory using the original file name
    /// with the appropriate output format extension.
    ///
    /// - Parameters:
    ///   - inputURLs: Array of source image file URLs.
    ///   - outputDir: Directory URL for the processed output files.
    ///   - config: Background removal configuration applied to all images.
    /// - Returns: Array of output file URLs that were successfully written.
    /// - Throws: ``BackgroundRemovalError`` if any image fails to process.
    public static func batchRemoveBackgrounds(
        inputURLs: [URL],
        outputDir: URL,
        config: BackgroundRemovalConfig
    ) async throws -> [URL] {
        // Ensure output directory exists
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var outputURLs: [URL] = []
        let ext = config.outputFormat.fileExtension

        for inputURL in inputURLs {
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let outputURL = outputDir.appendingPathComponent("\(baseName).\(ext)")

            try await removeBackground(inputURL: inputURL, outputURL: outputURL, config: config)
            outputURLs.append(outputURL)
        }

        return outputURLs
    }

    // MARK: - Private Helpers

    /// Generates a person segmentation mask using Vision framework.
    ///
    /// - Parameters:
    ///   - imageURL: Source image URL.
    ///   - qualityLevel: Desired segmentation quality.
    /// - Returns: A ``CIImage`` representing the segmentation mask.
    /// - Throws: ``BackgroundRemovalError`` if segmentation fails.
    private static func generateSegmentationMask(
        imageURL: URL,
        qualityLevel: BackgroundRemovalQuality
    ) async throws -> CIImage {
        let request = VNGeneratePersonSegmentationRequest()

        switch qualityLevel {
        case .fast:
            request.qualityLevel = .fast
        case .balanced:
            request.qualityLevel = .balanced
        case .accurate:
            request.qualityLevel = .accurate
        }

        let handler = VNImageRequestHandler(url: imageURL, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw BackgroundRemovalError.segmentationFailed(underlying: error.localizedDescription)
        }

        guard let result = request.results?.first,
              let maskBuffer = result.pixelBuffer as CVPixelBuffer? else {
            throw BackgroundRemovalError.segmentationFailed(
                underlying: "No segmentation results produced"
            )
        }

        return CIImage(cvPixelBuffer: maskBuffer)
    }

    /// Composites the original image over a background using the segmentation mask.
    ///
    /// - Parameters:
    ///   - original: The source image.
    ///   - mask: The segmentation mask (white = foreground, black = background).
    ///   - replaceColor: Optional hex colour for the background, or `nil` for transparent.
    /// - Returns: The composited ``CIImage``.
    private static func compositeImage(
        original: CIImage,
        mask: CIImage,
        replaceColor: String?
    ) -> CIImage {
        // Scale mask to match original image dimensions
        let scaleX = original.extent.width / mask.extent.width
        let scaleY = original.extent.height / mask.extent.height
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Create background image
        let background: CIImage
        if let hex = replaceColor {
            let color = CIColor(hexString: hex)
            background = CIImage(color: color).cropped(to: original.extent)
        } else {
            // Transparent background
            background = CIImage(color: CIColor.clear).cropped(to: original.extent)
        }

        // Blend using the mask
        let blended = original.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: scaledMask
        ])

        return blended
    }
}

// MARK: - CIColor Extension

/// Convenience initialiser for creating ``CIColor`` from a hex string.
extension CIColor {

    /// Creates a ``CIColor`` from a hex colour string.
    ///
    /// Supports formats: ``"#RRGGBB"``, ``"#RRGGBBAA"``, ``"RRGGBB"``.
    ///
    /// - Parameter hexString: The hex colour string.
    convenience init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }

        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)

        let r, g, b, a: CGFloat
        if hex.count == 8 {
            r = CGFloat((rgbValue >> 24) & 0xFF) / 255.0
            g = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
            b = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
            a = CGFloat(rgbValue & 0xFF) / 255.0
        } else {
            r = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
            g = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
            b = CGFloat(rgbValue & 0xFF) / 255.0
            a = 1.0
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
