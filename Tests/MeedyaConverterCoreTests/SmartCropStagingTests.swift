// ============================================================================
// MeedyaConverter — SmartCropStagingTests (Issue #299)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `SmartCropView.applyCropToJob()` stages a computed crop on
// `AppViewModel.pendingManualCropFilter`; `enqueueSelectedFile()` is the
// consumer. These tests drive a real `AppViewModel` (as
// `SettingsUndoManagerTests` already does) through the staging → enqueue →
// job-config path, exercising precedence over auto-crop, composition with a
// staged Filter Graph, and the video-passthrough drop guard added alongside
// this feature. `SmartCropView.activeArea(from:...)` — the pure helper that
// decides whether the auto-detected black-bar area applies to the file being
// analysed — is tested directly.
// ---------------------------------------------------------------------------

import XCTest
import SwiftUI
@testable import MeedyaConverterCore
import ConverterEngine

@MainActor
final class SmartCropStagingTests: XCTestCase {

    // MARK: - Fixtures

    private func makeFile() -> MediaFile {
        MediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/smartcrop-test.mp4"),
            streams: [MediaStream(streamIndex: 0, streamType: .video, codecName: "h264", width: 1920, height: 1080)],
            duration: 60)
    }

    // MARK: - enqueueSelectedFile() staging

    func test_enqueue_consumesPendingSmartCropIntoVideoFilterChain() {
        let vm = AppViewModel()
        vm.selectedFile = makeFile()
        vm.selectedProfile = EncodingProfile(name: "t", videoCodec: .h264)
        vm.pendingManualCropFilter = "crop=606:1080:656:0"

        vm.enqueueSelectedFile()

        let config = vm.engine.queue.jobs.last?.config
        XCTAssertEqual(config?.videoFilterChain, "crop=606:1080:656:0")
        XCTAssertNil(vm.pendingManualCropFilter)
    }

    func test_enqueue_smartCropWinsOverAutoCrop() {
        let vm = AppViewModel()
        vm.selectedFile = makeFile()
        vm.selectedProfile = EncodingProfile(name: "t", videoCodec: .h264)
        vm.autoCropEnabled = true
        vm.detectedCrop = CropDetectionResult(
            recommendedCrop: CropRect(width: 1920, height: 800, x: 0, y: 140),
            detectedCrops: [],
            confidence: 1.0,
            sourceWidth: 1920, sourceHeight: 1080)
        vm.pendingManualCropFilter = "crop=606:1080:656:0"

        vm.enqueueSelectedFile()

        let config = vm.engine.queue.jobs.last?.config
        XCTAssertEqual(config?.videoFilterChain, "crop=606:1080:656:0")
    }

    func test_enqueue_smartCropComposesBeforeStagedFilterGraph() {
        let vm = AppViewModel()
        vm.selectedFile = makeFile()
        vm.selectedProfile = EncodingProfile(name: "t", videoCodec: .h264)
        vm.pendingManualCropFilter = "crop=606:1080:656:0"
        vm.pendingFilterGraphVideo = "eq=contrast=1.1"

        vm.enqueueSelectedFile()

        let config = vm.engine.queue.jobs.last?.config
        XCTAssertEqual(config?.videoFilterChain, "crop=606:1080:656:0,eq=contrast=1.1")
    }

    func test_enqueue_dropsCropForVideoPassthroughProfile() {
        let vm = AppViewModel()
        vm.selectedFile = makeFile()
        vm.selectedProfile = EncodingProfile(name: "copy", videoCodec: .h264, videoPassthrough: true)
        vm.pendingManualCropFilter = "crop=606:1080:656:0"

        vm.enqueueSelectedFile()

        let config = vm.engine.queue.jobs.last?.config
        XCTAssertNil(config?.videoFilterChain)
        XCTAssertNil(vm.pendingManualCropFilter)
        let warning = vm.logEntries.first {
            $0.level == .warning && $0.message.hasPrefix("Crop discarded")
        }
        XCTAssertNotNil(warning)
    }

    // MARK: - SmartCropView.activeArea

    func test_activeArea_requiresAutoCropWillCropAndMatchingDimensions() {
        let detected = CropDetectionResult(
            recommendedCrop: CropRect(width: 1920, height: 800, x: 0, y: 140),
            detectedCrops: [],
            confidence: 1.0,
            sourceWidth: 1920, sourceHeight: 1080)

        // Auto-crop off.
        XCTAssertNil(SmartCropView.activeArea(
            from: detected, autoCropEnabled: false, sourceWidth: 1920, sourceHeight: 1080))

        // Detection that would not actually crop anything.
        let notCropping = CropDetectionResult(
            recommendedCrop: CropRect(width: 1920, height: 1080, x: 0, y: 0),
            detectedCrops: [],
            confidence: 1.0,
            sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertNil(SmartCropView.activeArea(
            from: notCropping, autoCropEnabled: true, sourceWidth: 1920, sourceHeight: 1080))

        // Detection measured against different source dimensions.
        let mismatched = CropDetectionResult(
            recommendedCrop: CropRect(width: 1200, height: 720, x: 0, y: 0),
            detectedCrops: [],
            confidence: 1.0,
            sourceWidth: 1280, sourceHeight: 720)
        XCTAssertNil(SmartCropView.activeArea(
            from: mismatched, autoCropEnabled: true, sourceWidth: 1920, sourceHeight: 1080))

        // Matching, cropping detection with auto-crop on: the rect is used.
        XCTAssertEqual(
            SmartCropView.activeArea(from: detected, autoCropEnabled: true, sourceWidth: 1920, sourceHeight: 1080),
            detected.recommendedCrop)
    }
}
