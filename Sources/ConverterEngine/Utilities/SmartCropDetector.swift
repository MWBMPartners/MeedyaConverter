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

/// Vision-framework subject detection for Smart Crop (Issue #299).
///
/// `detectSubjects(imageURL:)` runs face detection
/// (`VNDetectFaceRectanglesRequest`) and attention-based saliency
/// (`VNGenerateAttentionBasedSaliencyImageRequest`) on one image and returns
/// every hit as a `SubjectDetectionResult` in Vision's normalised,
/// bottom-left-origin coordinates, sorted by confidence. `SmartCropVideoAnalyzer`
/// calls it once per sampled video frame (through the `SubjectDetecting`
/// seam) and turns the per-frame results into a crop rectangle; this type
/// does no crop geometry itself.
public struct SmartCropDetector: Sendable, SubjectDetecting {

    public init() {}

    // MARK: - Subject Detection

    /// Detects subjects in the image at the given URL using Vision framework.
    ///
    /// Runs face detection, then attention-based saliency, and merges the
    /// results into a single array of ``SubjectDetectionResult``.
    ///
    /// - Parameter imageURL: File URL of the image to analyse.
    /// - Returns: An array of detected subjects sorted by confidence (descending).
    public func detectSubjects(imageURL: URL) async -> [SubjectDetectionResult] {
        var results: [SubjectDetectionResult] = []

        // Face detection
        let faceResults = await Self.detectFaces(imageURL: imageURL)
        results.append(contentsOf: faceResults)

        // Saliency detection
        let saliencyResults = await Self.detectSaliency(imageURL: imageURL)
        results.append(contentsOf: saliencyResults)

        // Sort by confidence descending
        return results.sorted { $0.confidence > $1.confidence }
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
}
