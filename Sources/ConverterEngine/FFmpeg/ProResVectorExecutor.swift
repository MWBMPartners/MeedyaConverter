// ============================================================================
// MeedyaConverter — ProResVectorExecutor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Wires `ProResToVectorConverter`'s pure argument builders to a real
// pipeline: ffmpeg frame dump → per-frame trace (via `RasterVectorExecutor
// .traceOne`, shared with the still-image executor) → SMIL animated-SVG
// assembly. Only `AnimationMethod.smil` is implemented — the GUI picker
// offers no other choice (see `ProResVectorView`); `assembleAnimatedSVG`
// throws for every other method so a direct API caller gets the same honest
// answer the UI enforces.
//
// Honest boundary: no CI job runs potrace, vtracer, or ffmpeg — this executor
// is exercised in CI only against `MockExternalToolRunner`
// (`VectorExecutorTests.swift`). Real tool behaviour, and the ffmpeg filter
// graphs' actual output, are verified on the manual matrix only.
//
// GitHub Issue #473 — potrace/vtracer executor.
// ============================================================================

import Foundation

// MARK: - ProResVectorProgress

/// Progress reported during a ProRes → animated SVG conversion.
public struct ProResVectorProgress: Sendable {
    public enum Stage: Sendable, Equatable {
        case extractingFrames
        case tracing(frame: Int, of: Int)
        case assembling
    }

    public let stage: Stage

    /// Overall progress, 0...1: extraction is 0–0.15, per-frame tracing is
    /// 0.15–0.95, and SMIL assembly is 0.95–1. Approximate — extraction and
    /// assembly durations vary with clip length and frame count — but always
    /// monotonically non-decreasing across one `convert` call.
    public let fraction: Double

    public init(stage: Stage, fraction: Double) {
        self.stage = stage
        self.fraction = fraction
    }
}

// MARK: - ProResVectorExecutor

public enum ProResVectorExecutor: Sendable {

    /// Convert a ProRes clip to an animated SVG: extract frames with ffmpeg,
    /// trace each with potrace/vtracer, assemble a SMIL animated SVG.
    ///
    /// - Parameters:
    ///   - sourceWidth/sourceHeight: The source video's pixel dimensions
    ///     (from its primary video stream) — used for the assembled SVG's
    ///     `viewBox`.
    /// - Returns: The number of frames processed.
    /// - Throws: `.invalidConfiguration` if `config.animation` is not
    ///   `.smil` (the only implemented method — the GUI picker never offers
    ///   another), `.tracingToolNotFound` if the required tracer was not
    ///   resolved, `.toolFailed` if ffmpeg or the tracer exits non-zero,
    ///   `.operationFailed` if extraction yields no frames or a frame
    ///   produces no SVG body.
    public static func convert(
        inputURL: URL,
        outputURL: URL,
        sourceWidth: Int,
        sourceHeight: Int,
        config: ProResToVectorConfig,
        tools: VectorToolPaths,
        runner: any ExternalToolRunning,
        progress: (@Sendable (ProResVectorProgress) -> Void)? = nil
    ) async throws -> Int {
        guard config.animation == .smil else {
            throw RasterVectorError.invalidConfiguration(
                "Only SMIL animation is implemented in this build")
        }

        // Resolve the tracer once, before extracting a single frame, so a
        // missing tool fails immediately rather than after minutes of
        // ffmpeg work. A monochrome alpha matte is traced with potrace
        // regardless of the tracing-mode picker — a matte is monochrome by
        // definition.
        let tool = config.alphaHandling == .alphaMatteOnly
            ? "potrace"
            : RasterVectorConverter.preferredTracingTool(for: config.tracing.tracingMode)
        guard tools.path(for: tool) != nil else {
            throw RasterVectorError.tracingToolNotFound(tool)
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-prores-vector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        progress?(ProResVectorProgress(stage: .extractingFrames, fraction: 0.0))

        let framePattern = workDirectory.appendingPathComponent("frame_%06d.png").path
        let extractionArguments = ProResToVectorConverter.buildFrameExtractionArguments(
            inputPath: inputURL.path, framePatternPath: framePattern, config: config)
        let extractionResult = try await runner.run(binaryPath: tools.ffmpeg, arguments: extractionArguments)
        guard extractionResult.exitCode == 0 else {
            throw RasterVectorError.toolFailed(
                tool: "ffmpeg", exitCode: extractionResult.exitCode, stderr: extractionResult.stderr)
        }

        try Task.checkCancellation()

        let frameFiles = try FileManager.default
            .contentsOfDirectory(at: workDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("frame_") && $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !frameFiles.isEmpty else {
            throw RasterVectorError.operationFailed("ffmpeg extracted no frames")
        }

        // The per-frame tracing config: PNG input (what ffmpeg just wrote)
        // and an alpha strategy derived from the ProRes alpha handling.
        var tracingConfig = config.tracing
        tracingConfig.inputFormat = .png
        switch config.alphaHandling {
        case .preservePerFrame: tracingConfig.alpha = .clipPathWithOpacity
        case .flatten: tracingConfig.alpha = .flatten
        case .alphaMatteOnly: tracingConfig.alpha = .discard
        }

        var frameBodies: [String] = []
        frameBodies.reserveCapacity(frameFiles.count)
        for (index, frameURL) in frameFiles.enumerated() {
            try Task.checkCancellation()

            let frameOutputURL = workDirectory.appendingPathComponent("frame_\(index).svg")
            try await RasterVectorExecutor.traceOne(
                inputPath: frameURL.path,
                outputPath: frameOutputURL.path,
                config: tracingConfig,
                tool: tool,
                tools: tools,
                runner: runner,
                workDirectory: workDirectory
            )
            guard FileManager.default.fileExists(atPath: frameOutputURL.path) else {
                throw RasterVectorError.operationFailed("frame \(index) produced no output file")
            }
            let frameSVG = try String(contentsOf: frameOutputURL, encoding: .utf8)
            guard let body = SVGFragmentExtractor.body(of: frameSVG) else {
                throw RasterVectorError.operationFailed("frame \(index) produced no SVG body")
            }
            frameBodies.append(body)

            let fraction = 0.15 + 0.80 * Double(index + 1) / Double(frameFiles.count)
            progress?(ProResVectorProgress(
                stage: .tracing(frame: index + 1, of: frameFiles.count), fraction: fraction))
        }

        progress?(ProResVectorProgress(stage: .assembling, fraction: 0.95))
        let assembled = try assembleAnimatedSVG(
            frameBodies: frameBodies,
            widthPixels: sourceWidth,
            heightPixels: sourceHeight,
            frameRate: config.frameRate.doubleValue,
            method: config.animation
        )
        try assembled.write(to: outputURL, atomically: true, encoding: .utf8)
        progress?(ProResVectorProgress(stage: .assembling, fraction: 1.0))

        return frameFiles.count
    }

    /// Pure assembly (tested without any tool installed): SVG root + one
    /// SMIL-timed `<g>` wrapper per frame body + frame/SVG closing tags.
    /// Frame bodies from potrace carry their own
    /// `<g transform="translate(0,H) scale(0.1,-0.1)">` in pt units — with
    /// `-r 72` (`RasterVectorConverter.buildPotraceArguments`) 1 pt = 1 px,
    /// so they land correctly inside the pixel `viewBox` here.
    ///
    /// - Throws: `.invalidConfiguration` if `method` is not `.smil` — the
    ///   only assembly this build implements.
    public static func assembleAnimatedSVG(
        frameBodies: [String],
        widthPixels: Int,
        heightPixels: Int,
        frameRate: Double,
        method: AnimationMethod
    ) throws -> String {
        guard method == .smil else {
            throw RasterVectorError.invalidConfiguration(
                "Only SMIL animation is implemented in this build")
        }

        var svg = ProResToVectorConverter.buildSVGAnimationRoot(
            widthPixels: widthPixels,
            heightPixels: heightPixels,
            frameCount: frameBodies.count,
            frameRate: frameRate,
            method: method
        )
        svg += "\n"
        for (index, body) in frameBodies.enumerated() {
            svg += ProResToVectorConverter.buildSMILFrameWrapper(
                frameIndex: index, frameCount: frameBodies.count, frameRate: frameRate)
            svg += body
            svg += ProResToVectorConverter.frameClosingTag
        }
        svg += ProResToVectorConverter.svgClosingTag
        return svg
    }
}
