// ============================================================================
// MeedyaConverter — PluginProtocol (Issue #353)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Defines the `MeedyaPlugin` protocol that all third-party and first-party
// plugins must conform to. Plugins hook into the encoding pipeline at two
// points: pre-process (before FFmpeg invocation) and post-process (after
// encoding completes). They may also supply additional FFmpeg arguments that
// are appended to the generated command line.
//
// The protocol requires `Sendable` conformance because plugins may be
// invoked from concurrent encoding tasks running on different threads.
//
// Phase 15 — Plugin System for Custom Processing (Issue #353)
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - MeedyaPlugin
// ---------------------------------------------------------------------------
/// A protocol that all MeedyaConverter plugins must conform to.
///
/// Plugins extend the encoding pipeline with custom pre-processing,
/// post-processing, and additional FFmpeg argument injection. Each plugin
/// is identified by a unique `id` string and exposes human-readable
/// metadata (`name`, `version`, `description`) for display in the
/// Plugin Manager UI.
///
/// ### Lifecycle
/// 1. The ``PluginManager`` discovers and loads plugin bundles from the
///    user's plugin directory.
/// 2. Before an encoding job starts, ``preProcess(inputURL:config:)`` is
///    called on every enabled plugin in registration order. Each plugin
///    may modify the ``EncodingJobConfig`` (e.g., change metadata, alter
///    output path, adjust profile settings).
/// 3. ``additionalArguments()`` is called to collect extra FFmpeg flags
///    that are appended after the engine's generated arguments.
/// 4. After encoding completes, ``postProcess(outputURL:config:)`` is
///    called on every enabled plugin (e.g., for tagging, uploading, or
///    notifying external systems).
///
/// ### Thread Safety
/// Conforming types must be `Sendable` because the encoding engine may
/// invoke plugin methods from background isolation contexts.
public protocol MeedyaPlugin: Sendable {

    // MARK: - Identity

    /// A unique, stable identifier for this plugin (e.g., reverse-DNS style).
    ///
    /// Used by the ``PluginManager`` to track registration, prevent
    /// duplicates, and persist enable/disable state.
    var id: String { get }

    /// The human-readable name displayed in the Plugin Manager UI.
    var name: String { get }

    /// The semantic version string for this plugin (e.g., "1.0.0").
    var version: String { get }

    /// A short description of what this plugin does, shown in the
    /// plugin detail pane.
    var description: String { get }

    // MARK: - Pipeline Hooks

    /// Called before encoding begins. Allows the plugin to inspect and
    /// modify the encoding job configuration.
    ///
    /// - Parameters:
    ///   - inputURL: The source media file URL.
    ///   - config: The current encoding job configuration.
    /// - Returns: A potentially modified ``EncodingJobConfig``.
    /// - Throws: If the plugin determines the job should not proceed.
    func preProcess(inputURL: URL, config: EncodingJobConfig) async throws -> EncodingJobConfig

    /// Called after encoding completes successfully. Allows the plugin
    /// to perform post-encoding actions such as metadata tagging,
    /// file relocation, or external notifications.
    ///
    /// - Parameters:
    ///   - outputURL: The encoded output file URL.
    ///   - config: The encoding job configuration that was used.
    /// - Throws: If post-processing fails (logged but does not fail the job).
    func postProcess(outputURL: URL, config: EncodingJobConfig) async throws

    /// Returns additional FFmpeg command-line arguments to append to the
    /// generated command.
    ///
    /// These arguments are added after all engine-generated flags but
    /// before the output path. Return an empty array if no additional
    /// arguments are needed.
    ///
    /// - Returns: An array of FFmpeg argument strings.
    func additionalArguments() -> [String]
}

// ---------------------------------------------------------------------------
// MARK: - Default Implementations
// ---------------------------------------------------------------------------
/// Default implementations provide sensible no-op behaviour so that plugins
/// only need to override the hooks they care about.
extension MeedyaPlugin {

    /// Default pre-process: returns the config unchanged.
    public func preProcess(inputURL: URL, config: EncodingJobConfig) async throws -> EncodingJobConfig {
        config
    }

    /// Default post-process: no-op.
    public func postProcess(outputURL: URL, config: EncodingJobConfig) async throws {
        // No-op by default.
    }

    /// Default additional arguments: none.
    public func additionalArguments() -> [String] {
        []
    }
}
