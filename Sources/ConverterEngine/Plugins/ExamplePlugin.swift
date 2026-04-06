// ============================================================================
// MeedyaConverter — TimestampMetadataPlugin (Issue #353)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// A sample plugin that demonstrates the ``MeedyaPlugin`` protocol by adding
// a watermark timestamp to the output file's metadata. This serves as both
// a functional example and a template for third-party plugin developers.
//
// The plugin injects `-metadata comment="Encoded by MeedyaConverter on
// {date}"` into the FFmpeg argument list via ``additionalArguments()``.
//
// Phase 15 — Plugin System for Custom Processing (Issue #353)
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - TimestampMetadataPlugin
// ---------------------------------------------------------------------------
/// A sample plugin that adds a timestamp watermark to output file metadata.
///
/// When enabled, this plugin appends a `-metadata` flag to the FFmpeg
/// command line that sets the `comment` field to include the encoding date
/// and application name. This is useful for provenance tracking — knowing
/// when and with what tool a file was encoded.
///
/// ### Usage
/// Register the plugin with the ``PluginManager``:
/// ```swift
/// let manager = PluginManager()
/// manager.register(TimestampMetadataPlugin())
/// ```
///
/// ### Output
/// The resulting file will contain metadata similar to:
/// ```
/// comment: Encoded by MeedyaConverter on 2026-04-05 at 14:30:00 UTC
/// ```
public struct TimestampMetadataPlugin: MeedyaPlugin {

    // MARK: - Identity

    /// Unique identifier for this plugin.
    public let id: String = "Ltd.MWBMpartners.MeedyaConverter.plugin.timestamp-metadata"

    /// Human-readable name displayed in the Plugin Manager UI.
    public let name: String = "Timestamp Metadata"

    /// Semantic version string.
    public let version: String = "1.0.0"

    /// Short description of the plugin's functionality.
    public let description: String = "Adds a timestamp watermark to the output file's metadata comment field, recording when the file was encoded."

    // MARK: - Initialiser

    /// Creates a new timestamp metadata plugin instance.
    public init() {}

    // MARK: - Pipeline Hooks

    /// Returns additional FFmpeg arguments that embed a timestamp in the
    /// output file's metadata.
    ///
    /// The generated arguments are:
    /// ```
    /// -metadata comment="Encoded by MeedyaConverter on {date}"
    /// ```
    ///
    /// - Returns: An array containing the `-metadata` flag and its value.
    public func additionalArguments() -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH:mm:ss 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestamp = formatter.string(from: Date())

        return [
            "-metadata",
            "comment=Encoded by MeedyaConverter on \(timestamp)"
        ]
    }

    /// Post-process hook: logs that the timestamp metadata was applied.
    ///
    /// This is a no-op beyond the default since the actual work is done
    /// via ``additionalArguments()``. Override is provided as a
    /// demonstration of the post-process hook pattern.
    ///
    /// - Parameters:
    ///   - outputURL: The encoded output file URL.
    ///   - config: The encoding job configuration that was used.
    public func postProcess(outputURL: URL, config: EncodingJobConfig) async throws {
        // In a production plugin, you might verify the metadata was
        // correctly written by probing the output file here.
    }
}
