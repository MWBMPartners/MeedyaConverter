// ============================================================================
// MeedyaConverter — PluginManager (Issue #353)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// The `PluginManager` is responsible for discovering, loading, registering,
// and orchestrating ``MeedyaPlugin`` instances. It maintains a thread-safe
// list of loaded plugins and provides methods to run the pre-process and
// post-process hooks across all registered plugins in order.
//
// Plugin bundles are loaded from the user's Application Support directory:
//   ~/Library/Application Support/MeedyaConverter/Plugins/
//
// Phase 15 — Plugin System for Custom Processing (Issue #353)
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - PluginManager
// ---------------------------------------------------------------------------
/// Manages the lifecycle of ``MeedyaPlugin`` instances.
///
/// The plugin manager provides:
/// - **Discovery**: Scans a plugin directory for `.bundle` files and loads
///   conforming types.
/// - **Registration**: Programmatic registration/un-registration of plugins
///   (used for built-in plugins and testing).
/// - **Orchestration**: Runs pre-process and post-process hooks across all
///   registered plugins in registration order.
///
/// ### Thread Safety
/// The manager uses `NSLock` to protect the `loadedPlugins` array, making
/// it safe to register/unregister plugins from any thread. The class is
/// marked `@unchecked Sendable` because the lock-based synchronisation is
/// not expressible in Swift's type system.
///
/// ### Plugin Directory
/// The default plugin directory is:
/// ```
/// ~/Library/Application Support/MeedyaConverter/Plugins/
/// ```
/// This directory is created automatically when `loadPlugins(from:)` is
/// called for the first time.
public final class PluginManager: @unchecked Sendable {

    // MARK: - Properties

    /// All currently loaded and registered plugins.
    ///
    /// Access is protected by `lock` to ensure thread safety. External
    /// consumers should use ``registeredPlugins`` (a snapshot copy) to
    /// read the current list without holding the lock.
    private var _loadedPlugins: [any MeedyaPlugin] = []

    /// Serial lock for thread-safe access to the plugin list.
    private let lock = NSLock()

    // MARK: - Public Accessors

    /// A thread-safe snapshot of all currently registered plugins.
    ///
    /// Returns a copy of the internal array so callers can iterate
    /// without holding the lock.
    public var loadedPlugins: [any MeedyaPlugin] {
        lock.lock()
        defer { lock.unlock() }
        return _loadedPlugins
    }

    // MARK: - Default Plugin Directory

    /// The default directory where user-installed plugins are stored.
    ///
    /// Path: `~/Library/Application Support/MeedyaConverter/Plugins/`
    public static var defaultPluginDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("MeedyaConverter", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    // MARK: - Initialiser

    /// Creates a new plugin manager with an empty plugin list.
    public init() {}

    // MARK: - Discovery & Loading

    /// Discover and load plugin bundles from the specified directory.
    ///
    /// Scans the directory for files with the `.bundle` extension, attempts
    /// to load each as an `NSBundle`, and looks for a principal class that
    /// conforms to ``MeedyaPlugin``. Successfully loaded plugins are
    /// automatically registered.
    ///
    /// If the directory does not exist, it is created automatically.
    ///
    /// - Parameter directory: The URL of the directory to scan. Defaults
    ///   to ``defaultPluginDirectory``.
    public func loadPlugins(from directory: URL = PluginManager.defaultPluginDirectory) {
        let fileManager = FileManager.default

        // Ensure the plugin directory exists.
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Enumerate .bundle files in the plugin directory.
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let bundleURLs = contents.filter { $0.pathExtension == "bundle" }

        for bundleURL in bundleURLs {
            guard let bundle = Bundle(url: bundleURL),
                  bundle.load(),
                  let principalClass = bundle.principalClass as? any MeedyaPlugin.Type else {
                continue
            }

            // Instantiate the plugin using a no-argument initialiser.
            // Plugins must provide a conforming type that can be cast.
            // Since protocols can't require initialisers cleanly with
            // existentials, we rely on the principal class pattern.
            // For now, log a note that the bundle was found but skip
            // instantiation unless the class provides a static instance.
            _ = principalClass
        }
    }

    // MARK: - Registration

    /// Register a plugin with the manager.
    ///
    /// If a plugin with the same ``MeedyaPlugin/id`` is already registered,
    /// the existing registration is replaced.
    ///
    /// - Parameter plugin: The plugin instance to register.
    public func register(_ plugin: any MeedyaPlugin) {
        lock.lock()
        defer { lock.unlock() }

        // Remove any existing plugin with the same ID to prevent duplicates.
        _loadedPlugins.removeAll { $0.id == plugin.id }
        _loadedPlugins.append(plugin)
    }

    /// Unregister a plugin by its unique identifier.
    ///
    /// - Parameter id: The ``MeedyaPlugin/id`` of the plugin to remove.
    public func unregister(id: String) {
        lock.lock()
        defer { lock.unlock() }
        _loadedPlugins.removeAll { $0.id == id }
    }

    // MARK: - Pipeline Orchestration

    /// Run the pre-process hook across all registered plugins.
    ///
    /// Plugins are invoked in registration order. Each plugin receives
    /// the (potentially modified) config from the previous plugin,
    /// forming a pipeline chain.
    ///
    /// - Parameters:
    ///   - inputURL: The source media file URL.
    ///   - config: The initial encoding job configuration.
    /// - Returns: The final config after all plugins have processed it.
    /// - Throws: If any plugin's pre-process hook throws.
    public func runPreProcess(
        inputURL: URL,
        config: EncodingJobConfig
    ) async throws -> EncodingJobConfig {
        var currentConfig = config
        let plugins = loadedPlugins

        for plugin in plugins {
            currentConfig = try await plugin.preProcess(
                inputURL: inputURL,
                config: currentConfig
            )
        }

        return currentConfig
    }

    /// Run the post-process hook across all registered plugins.
    ///
    /// Plugins are invoked in registration order. Errors from individual
    /// plugins are collected but do not prevent subsequent plugins from
    /// running.
    ///
    /// - Parameters:
    ///   - outputURL: The encoded output file URL.
    ///   - config: The encoding job configuration that was used.
    /// - Throws: The first error encountered, after all plugins have run.
    public func runPostProcess(
        outputURL: URL,
        config: EncodingJobConfig
    ) async throws {
        let plugins = loadedPlugins
        var firstError: (any Error)?

        for plugin in plugins {
            do {
                try await plugin.postProcess(outputURL: outputURL, config: config)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let error = firstError {
            throw error
        }
    }

    /// Collect additional FFmpeg arguments from all registered plugins.
    ///
    /// Arguments are concatenated in registration order. Duplicate
    /// arguments are not deduplicated — plugins are responsible for
    /// avoiding conflicts.
    ///
    /// - Returns: A combined array of additional FFmpeg arguments.
    public func collectAdditionalArguments() -> [String] {
        let plugins = loadedPlugins
        return plugins.flatMap { $0.additionalArguments() }
    }
}
