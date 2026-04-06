// ============================================================================
// MeedyaConverter — SmartCropDetector (Issue #299)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import Vision
import CoreImage

// MARK: - SubjectType

/// Classification of a detected subject within a video frame or image.
///
/// Determines how the crop algorithm prioritises and weights detected
/// regions when calculating the optimal crop rectangle.
///
/// Phase 11 — Smart Crop / Subject Detection (Issue #299)
public enum SubjectType: String, Sendable, CaseIterable {

    /// A human face detected via ``VNDetectFaceRectanglesRequest``.
    case face

    /// A full human body detected via person segmentation.
    case person

    /// A visually salient region detected via attention-based saliency.
    case saliency

    /// An unclassified or generic subject.
    case unknown
}

// MARK: - SubjectDetectionResult

/// A single detected subject within an image, including its bounding box,
/// detection confidence, and classification.
///
/// Bounding boxes use Vision's normalised coordinate system where the
/// origin is at the bottom-left and values range from 0.0 to 1.0.
///
/// Phase 11 — Smart Crop / Subject Detection (Issue #299)
public struct SubjectDetectionResult: Sendable {

    /// The normalised bounding box of the detected subject.
    /// Origin at bottom-left, values in [0, 1].
    public let boundingBox: CGRect

    /// Detection confidence score in [0, 1].
    /// Higher values indicate stronger certainty.
    public let confidence: Double

    /// The type of subject detected.
    public let subjectType: SubjectType

    /// Creates a new subject detection result.
    ///
    /// - Parameters:
    ///   - boundingBox: Normalised bounding box (Vision coordinates).
    ///   - confidence: Confidence score (0.0–1.0).
    ///   - subjectType: Classification of the detected subject.
    public init(boundingBox: CGRect, confidence: Double, subjectType: SubjectType) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.subjectType = subjectType
    }
}

// MARK: - SmartCropDetector

/// Detects subjects in images using Apple Vision framework and calculates
/// optimal crop rectangles that keep subjects properly framed.
///
/// Combines face detection (``VNDetectFaceRectanglesRequest``) with
/// attention-based saliency (``VNGenerateAttentionBasedSaliencyImageRequest``)
/// to produce a comprehensive subject map. The crop calculator then
/// determines the best crop rectangle for a given target aspect ratio,
/// optionally applying rule-of-thirds positioning.
///
/// Usage:
/// ```swift
/// let subjects = await SmartCropDetector.detectSubjects(imageURL: frameURL)
/// let cropRect = SmartCropDetector.calculateCropRect(
///     subjects: subjects,
///     targetAspectRatio: 16.0 / 9.0,
///     imageSize: CGSize(width: 3840, height: 2160)
/// )
/// let filter = SmartCropDetector.buildCropFilter(cropRect: cropRect)
/// ```
///
/// Phase 11 — Smart Crop / Subject Detection (Issue #299)
public struct SmartCropDetector: Sendable {

    // MARK: - Subject Detection

    /// Detects subjects in the image at the given URL using Vision framework.
    ///
    /// Runs face detection and attention-based saliency analysis in parallel,
    /// then merges the results into a single array of ``SubjectDetectionResult``.
    ///
    /// - Parameter imageURL: File URL of the image to analyse.
    /// - Returns: An array of detected subjects sorted by confidence (descending).
    public static func detectSubjects(imageURL: URL) async -> [SubjectDetectionResult] {
        var results: [SubjectDetectionResult] = []

        // Face detection
        let faceResults = await detectFaces(imageURL: imageURL)
        results.append(contentsOf: faceResults)

        // Saliency detection
        let saliencyResults = await detectSaliency(imageURL: imageURL)
        results.append(contentsOf: saliencyResults)

        // Sort by confidence descending
        return results.sorted { $0.confidence > $1.confidence }
    }

    /// Calculates the optimal crop rectangle that keeps all detected subjects
    /// visible within the specified aspect ratio.
    ///
    /// The algorithm:
    /// 1. Computes the bounding box that encloses all subject regions.
    /// 2. Expands the bounding box to match the target aspect ratio.
    /// 3. Centres the crop on the subject centroid.
    /// 4. Clamps the rectangle to the image bounds.
    ///
    /// - Parameters:
    ///   - subjects: Detected subjects (normalised coordinates).
    ///   - targetAspectRatio: Desired width/height ratio (e.g. 16/9 = 1.778).
    ///   - imageSize: The pixel dimensions of the source image.
    /// - Returns: A crop rectangle in pixel coordinates.
    public static func calculateCropRect(
        subjects: [SubjectDetectionResult],
        targetAspectRatio: Double,
        imageSize: CGSize
    ) -> CGRect {
        guard !subjects.isEmpty else {
            // No subjects — centre crop the full image
            return centredCropRect(
                targetAspectRatio: targetAspectRatio,
                imageSize: imageSize,
                centre: CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
            )
        }

        // Convert normalised bounding boxes to pixel coordinates
        // Vision uses bottom-left origin; we convert to top-left for FFmpeg
        let pixelBoxes = subjects.map { result -> CGRect in
            let x = result.boundingBox.origin.x * imageSize.width
            let y = (1.0 - result.boundingBox.origin.y - result.boundingBox.height) * imageSize.height
            let w = result.boundingBox.width * imageSize.width
            let h = result.boundingBox.height * imageSize.height
            return CGRect(x: x, y: y, width: w, height: h)
        }

        // Compute the union of all subject bounding boxes
        var unionRect = pixelBoxes[0]
        for box in pixelBoxes.dropFirst() {
            unionRect = unionRect.union(box)
        }

        // Centroid of the union rectangle
        let centreX = unionRect.midX
        let centreY = unionRect.midY

        return centredCropRect(
            targetAspectRatio: targetAspectRatio,
            imageSize: imageSize,
            centre: CGPoint(x: centreX, y: centreY),
            minWidth: unionRect.width,
            minHeight: unionRect.height
        )
    }

    /// Generates an FFmpeg crop filter string from a pixel-coordinate crop rectangle.
    ///
    /// Output format matches FFmpeg's ``crop`` filter syntax:
    /// ``crop=w:h:x:y``
    ///
    /// - Parameter cropRect: The crop rectangle in pixel coordinates.
    /// - Returns: An FFmpeg crop filter string.
    public static func buildCropFilter(cropRect: CGRect) -> String {
        let w = Int(cropRect.width)
        let h = Int(cropRect.height)
        let x = Int(cropRect.origin.x)
        let y = Int(cropRect.origin.y)
        return "crop=\(w):\(h):\(x):\(y)"
    }

    /// Applies rule-of-thirds positioning to place the subject at a
    /// visually pleasing intersection point rather than dead centre.
    ///
    /// The subject centre is shifted towards the nearest rule-of-thirds
    /// intersection (1/3 or 2/3 of the crop dimensions).
    ///
    /// - Parameters:
    ///   - subjectCenter: The subject's centre point in pixel coordinates.
    ///   - imageSize: Full image dimensions.
    ///   - cropSize: The crop rectangle dimensions.
    /// - Returns: A crop rectangle positioned using rule-of-thirds.
    public static func applyRuleOfThirds(
        subjectCenter: CGPoint,
        imageSize: CGSize,
        cropSize: CGSize
    ) -> CGRect {
        // Find the nearest rule-of-thirds intersection
        let thirdPoints: [(CGFloat, CGFloat)] = [
            (1.0 / 3.0, 1.0 / 3.0),
            (2.0 / 3.0, 1.0 / 3.0),
            (1.0 / 3.0, 2.0 / 3.0),
            (2.0 / 3.0, 2.0 / 3.0)
        ]

        // Choose the intersection closest to the subject
        var bestOffset = CGPoint.zero
        var bestDist = Double.infinity
        for (tx, ty) in thirdPoints {
            // Where the subject would be in the crop if placed at this third
            let cropOriginX = subjectCenter.x - tx * cropSize.width
            let cropOriginY = subjectCenter.y - ty * cropSize.height
            // Distance from the subject to the thirds point in the crop
            let dx = subjectCenter.x - (cropOriginX + tx * cropSize.width)
            let dy = subjectCenter.y - (cropOriginY + ty * cropSize.height)
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                bestOffset = CGPoint(x: cropOriginX, y: cropOriginY)
            }
        }

        // Clamp to image bounds
        let x = max(0, min(bestOffset.x, imageSize.width - cropSize.width))
        let y = max(0, min(bestOffset.y, imageSize.height - cropSize.height))
        return CGRect(x: x, y: y, width: cropSize.width, height: cropSize.height)
    }

    // MARK: - Private Helpers

    /// Detects faces using Vision's face detection request.
    ///
    /// - Parameter imageURL: Image file URL.
    /// - Returns: Subject detection results for each detected face.
    private static func detectFaces(imageURL: URL) async -> [SubjectDetectionResult] {
        var results: [SubjectDetectionResult] = []

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(url: imageURL, options: [:])

        do {
            try handler.perform([request])
            if let observations = request.results {
                for face in observations {
                    results.append(SubjectDetectionResult(
                        boundingBox: face.boundingBox,
                        confidence: Double(face.confidence),
                        subjectType: .face
                    ))
                }
            }
        } catch {
            // Face detection failed — return empty results
        }

        return results
    }

    /// Detects salient regions using attention-based saliency analysis.
    ///
    /// - Parameter imageURL: Image file URL.
    /// - Returns: Subject detection results for each salient region.
    private static func detectSaliency(imageURL: URL) async -> [SubjectDetectionResult] {
        var results: [SubjectDetectionResult] = []

        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(url: imageURL, options: [:])

        do {
            try handler.perform([request])
            if let observations = request.results {
                for observation in observations {
                    if let salientObjects = observation.salientObjects {
                        for obj in salientObjects {
                            results.append(SubjectDetectionResult(
                                boundingBox: obj.boundingBox,
                                confidence: Double(obj.confidence),
                                subjectType: .saliency
                            ))
                        }
                    }
                }
            }
        } catch {
            // Saliency detection failed — return empty results
        }

        return results
    }

    /// Computes a crop rectangle centred on a given point that matches
    /// the target aspect ratio, ensuring it fits within image bounds.
    ///
    /// - Parameters:
    ///   - targetAspectRatio: Desired width/height ratio.
    ///   - imageSize: Full image pixel dimensions.
    ///   - centre: Centre point for the crop.
    ///   - minWidth: Minimum crop width to ensure subjects are included.
    ///   - minHeight: Minimum crop height to ensure subjects are included.
    /// - Returns: A crop rectangle in pixel coordinates.
    private static func centredCropRect(
        targetAspectRatio: Double,
        imageSize: CGSize,
        centre: CGPoint,
        minWidth: CGFloat = 0,
        minHeight: CGFloat = 0
    ) -> CGRect {
        let imgW = imageSize.width
        let imgH = imageSize.height
        let ratio = CGFloat(targetAspectRatio)

        // Start with full image and constrain to aspect ratio
        var cropW: CGFloat
        var cropH: CGFloat

        if imgW / imgH > ratio {
            // Image is wider than target — constrain width
            cropH = imgH
            cropW = cropH * ratio
        } else {
            // Image is taller than target — constrain height
            cropW = imgW
            cropH = cropW / ratio
        }

        // Ensure minimum dimensions to contain all subjects
        if cropW < minWidth {
            cropW = min(minWidth * 1.2, imgW)
            cropH = cropW / ratio
        }
        if cropH < minHeight {
            cropH = min(minHeight * 1.2, imgH)
            cropW = cropH * ratio
        }

        // Clamp to image bounds
        cropW = min(cropW, imgW)
        cropH = min(cropH, imgH)

        // Centre on the given point, clamped to image edges
        let x = max(0, min(centre.x - cropW / 2, imgW - cropW))
        let y = max(0, min(centre.y - cropH / 2, imgH - cropH))

        return CGRect(x: x, y: y, width: cropW, height: cropH)
    }
}
