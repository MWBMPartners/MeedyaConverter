// ============================================================================
// MeedyaConverter — RasterVectorExecutor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Wires `RasterVectorConverter`'s pure argument builders to a real potrace/
// vtracer process via `ExternalToolRunning`. Every trace goes through two
// subprocess steps:
//
//   1. An ffmpeg pre-pass (`RasterVectorConverter.buildPrePassArguments`)
//      that normalises the source raster (any of the ~30 formats the engine
//      recognises) into the one intermediate format the chosen tracer can
//      actually read — potrace reads only PBM/PGM/PPM/BMP, never PNG.
//   2. The tracer itself (potrace or vtracer), producing the output SVG.
//
// `traceOne` is the shared step both this executor and `ProResVectorExecutor`
// use for a single frame; `ProResVectorExecutor` calls it once per extracted
// frame and stitches the results into an animated SVG.
//
// Honest boundary: no CI job runs potrace, vtracer, or ffmpeg-on-an-image —
// this executor is exercised in CI only against `MockExternalToolRunner`
// (`VectorExecutorTests.swift`). Real tool behaviour is verified on the
// manual matrix (macOS Direct DMG, both arches) only.
//
// GitHub Issue #473 — potrace/vtracer executor.
// ============================================================================

import Foundation

// MARK: - VectorToolPaths

/// Resolved filesystem paths for the tools a vector conversion needs.
/// Assembled by the caller (the SwiftUI views, via `BundledToolLocator` and
/// the FFmpeg bundle manager) — this executor never does its own discovery.
public struct VectorToolPaths: Sendable {
    public var ffmpeg: String
    public var potrace: String?
    public var vtracer: String?

    public init(ffmpeg: String, potrace: String? = nil, vtracer: String? = nil) {
        self.ffmpeg = ffmpeg
        self.potrace = potrace
        self.vtracer = vtracer
    }

    /// The resolved path for `tool` (`"potrace"`/`"vtracer"`), or nil when
    /// that tool was not found.
    public func path(for tool: String) -> String? {
        switch tool {
        case "potrace": return potrace
        case "vtracer": return vtracer
        default: return nil
        }
    }
}

// MARK: - RasterVectorExecutor

public enum RasterVectorExecutor: Sendable {

    /// Trace one raster into `outputURL` (SVG).
    ///
    /// - Throws: `RasterVectorError` — `.invalidConfiguration` if `config`
    ///   fails `RasterVectorConverter.validate`, `.tracingToolNotFound` if
    ///   the tool `config.tracingMode` needs was not resolved, `.toolFailed`
    ///   if either subprocess exits non-zero, `.outputMissing` if the tracer
    ///   reported success but wrote nothing.
    public static func convert(
        inputURL: URL,
        outputURL: URL,
        config: RasterToVectorConfig,
        tools: VectorToolPaths,
        runner: any ExternalToolRunning
    ) async throws {
        if let error = RasterVectorConverter.validate(config) {
            throw error
        }
        let tool = RasterVectorConverter.preferredTracingTool(for: config.tracingMode)
        guard tools.path(for: tool) != nil else {
            throw RasterVectorError.tracingToolNotFound(tool)
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-vector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        try await traceOne(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            config: config,
            tool: tool,
            tools: tools,
            runner: runner,
            workDirectory: workDirectory
        )

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw RasterVectorError.outputMissing(outputURL.path)
        }
    }

    /// Trace a single raster file: ffmpeg pre-pass → tracer. Shared with
    /// `ProResVectorExecutor`, which calls this once per extracted frame.
    ///
    /// - Parameter workDirectory: Scratch directory for the intermediate
    ///   file; the caller owns its lifetime (created/removed around the
    ///   call, or per-frame for ProRes).
    static func traceOne(
        inputPath: String,
        outputPath: String,
        config: RasterToVectorConfig,
        tool: String,
        tools: VectorToolPaths,
        runner: any ExternalToolRunning,
        workDirectory: URL
    ) async throws {
        guard let toolPath = tools.path(for: tool) else {
            throw RasterVectorError.tracingToolNotFound(tool)
        }

        let intermediateExtension = tool == "potrace" ? "bmp" : "png"
        let intermediatePath = workDirectory
            .appendingPathComponent("frame.\(intermediateExtension)")
            .path

        let prePassArguments = RasterVectorConverter.buildPrePassArguments(
            inputPath: inputPath, intermediatePath: intermediatePath, config: config, tool: tool
        )
        let prePassResult = try await runner.run(binaryPath: tools.ffmpeg, arguments: prePassArguments)
        guard prePassResult.exitCode == 0 else {
            throw RasterVectorError.toolFailed(
                tool: "ffmpeg", exitCode: prePassResult.exitCode, stderr: prePassResult.stderr)
        }

        try Task.checkCancellation()

        let traceArguments = tool == "potrace"
            ? RasterVectorConverter.buildPotraceArguments(
                inputPath: intermediatePath, outputPath: outputPath, config: config)
            : RasterVectorConverter.buildVTracerArguments(
                inputPath: intermediatePath, outputPath: outputPath, config: config)
        let traceResult = try await runner.run(binaryPath: toolPath, arguments: traceArguments)
        guard traceResult.exitCode == 0 else {
            throw RasterVectorError.toolFailed(
                tool: tool, exitCode: traceResult.exitCode, stderr: traceResult.stderr)
        }
    }
}

// MARK: - SVGFragmentExtractor

/// Pure: extracts the inner content of an SVG document — everything between
/// the opening `<svg …>` tag and the final `</svg>` — so `ProResVectorExecutor`
/// can lift one frame's traced shapes into a shared animated-SVG root without
/// nesting a whole second `<svg>` document inside each frame's `<g>` wrapper.
public enum SVGFragmentExtractor {

    /// - Returns: The trimmed inner content, `""` if the root element is
    ///   self-closing (`<svg .../>`, i.e. an empty trace), or `nil` if the
    ///   input has no `<svg` opening tag or no matching `</svg>` closing tag.
    ///   Handles both the XML prolog/DOCTYPE/`<metadata>` preamble potrace
    ///   emits and the bare `<svg>` root vtracer emits.
    public static func body(of svg: String) -> String? {
        guard let svgTagRange = svg.range(of: "<svg") else { return nil }
        guard let closeAngle = svg.range(of: ">", range: svgTagRange.upperBound..<svg.endIndex) else {
            return nil
        }
        let charBeforeClose = svg.index(before: closeAngle.lowerBound)
        if svg[charBeforeClose] == "/" {
            return ""
        }
        guard let lastClose = svg.range(of: "</svg>", options: .backwards) else { return nil }
        guard closeAngle.upperBound <= lastClose.lowerBound else { return nil }
        return String(svg[closeAngle.upperBound..<lastClose.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
