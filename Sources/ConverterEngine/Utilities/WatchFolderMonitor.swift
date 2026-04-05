// ============================================================================
// MeedyaConverter — WatchFolderMonitor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides a file-system watch folder (hot folder) monitor that automatically
// detects new media files dropped into a designated directory and triggers
// encoding via a caller-supplied callback.
//
// Features:
//   - DispatchSource-based directory monitoring for low-overhead file events.
//   - Configurable file-extension filter via the existing WatchFolderConfig.
//   - Optional recursive monitoring of subdirectories.
//   - 2-second debounce to ensure files are fully written before triggering.
//   - Tracks already-processed files to prevent duplicate triggers.
//   - Multiple watch folder support using WatchFolderConfig from
//     WatchFolderManager.swift.
//   - Thread-safe design with `@unchecked Sendable` and internal locking.
//
// Phase 11 — Watch Folder / Hot Folder Auto-Encoding (Issue #268)
// ---------------------------------------------------------------------------

import Foundation

// MARK: - WatchFolderLogEntry

/// An entry in the watch folder activity log.
///
/// Records each file that was detected and the outcome of the encoding attempt.
public struct WatchFolderLogEntry: Identifiable, Codable, Sendable {

    /// Unique identifier for this log entry.
    public let id: UUID

    /// The file that was detected.
    public var filePath: URL

    /// The watch folder config ID that triggered this entry.
    public var configId: String

    /// Timestamp when the file was detected.
    public var detectedAt: Date

    /// Current status of processing.
    public var status: WatchFolderFileStatus

    /// Optional error message if processing failed.
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        filePath: URL,
        configId: String,
        detectedAt: Date = Date(),
        status: WatchFolderFileStatus = .detected,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.configId = configId
        self.detectedAt = detectedAt
        self.status = status
        self.errorMessage = errorMessage
    }
}

// MARK: - WatchFolderFileStatus

/// Processing status for a file detected by the watch folder monitor.
public enum WatchFolderFileStatus: String, Codable, Sendable {
    /// File was detected but encoding has not started.
    case detected
    /// File is waiting for the debounce period to elapse.
    case waiting
    /// Encoding is in progress.
    case encoding
    /// Encoding completed successfully.
    case completed
    /// Encoding failed.
    case failed
    /// File was skipped (wrong extension, already processed, etc.).
    case skipped
}

// MARK: - WatchFolderMonitor

/// Monitors one or more directories for new media files and triggers
/// encoding callbacks when qualifying files appear.
///
/// Uses `DispatchSource.makeFileSystemObjectSource` for efficient,
/// kernel-level directory change notifications. A 2-second debounce
/// ensures files are fully written before triggering.
///
/// This class works with ``WatchFolderConfig`` from `WatchFolderManager.swift`
/// for configuration, and uses ``WatchFolderStore`` for persistence.
///
/// ### Thread Safety
/// All mutable state is protected by an `NSLock`. The class is marked
/// `@unchecked Sendable` because it manually synchronises access.
public final class WatchFolderMonitor: @unchecked Sendable {

    // MARK: - Types

    /// Callback invoked when a new file is detected and ready for encoding.
    public typealias NewFileHandler = @Sendable (URL) -> Void

    // MARK: - Properties

    /// Lock protecting all mutable state.
    private let lock = NSLock()

    /// Active dispatch sources keyed by config ID.
    private var sources: [String: DispatchSourceFileSystemObject] = [:]

    /// File descriptors for monitored directories, keyed by config ID.
    private var fileDescriptors: [String: Int32] = [:]

    /// Set of file paths that have already been processed, keyed by config ID.
    private var processedFiles: [String: Set<String>] = [:]

    /// Pending debounce work items keyed by file path.
    private var debounceTimers: [String: DispatchWorkItem] = [:]

    /// The queue on which file-system events are delivered.
    private let monitorQueue = DispatchQueue(
        label: "com.mwbm.meedyaconverter.watchfolder.monitor",
        qos: .utility
    )

    /// Activity log entries.
    private var _logEntries: [WatchFolderLogEntry] = []

    /// Path to the persisted configuration file in Application Support.
    private var configFilePath: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("MeedyaConverter")
        return appSupport.appendingPathComponent("WatchFolderMonitorConfigs.json")
    }

    /// Whether any watch folder is currently being monitored.
    public var isMonitoring: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !sources.isEmpty
    }

    /// Current activity log entries.
    public var logEntries: [WatchFolderLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _logEntries
    }

    // MARK: - Shared Instance

    /// Shared singleton monitor instance.
    public static let shared = WatchFolderMonitor()

    // MARK: - Initialiser

    public init() {}

    // MARK: - Public Methods

    /// Starts monitoring a directory for new files.
    ///
    /// Opens a file descriptor on the watch directory and attaches a
    /// `DispatchSource` that fires when directory contents change.
    /// Each detected file is debounced for 2 seconds before the callback
    /// is invoked, giving the writing process time to finish.
    ///
    /// - Parameters:
    ///   - config: The watch folder configuration to monitor (from WatchFolderManager).
    ///   - onNewFile: Closure called with the URL of each new file.
    public func start(config: WatchFolderConfig, onNewFile: @escaping NewFileHandler) {
        let configId = config.id

        lock.lock()

        // Stop existing source for this config if any.
        if let existing = sources[configId] {
            existing.cancel()
            sources.removeValue(forKey: configId)
        }
        if let fd = fileDescriptors[configId] {
            close(fd)
            fileDescriptors.removeValue(forKey: configId)
        }

        // Initialise processed-files set for this config.
        if processedFiles[configId] == nil {
            processedFiles[configId] = Set<String>()
        }

        lock.unlock()

        let path = config.watchPath
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: monitorQueue
        )

        source.setEventHandler { [weak self] in
            self?.handleDirectoryChange(config: config, onNewFile: onNewFile)
        }

        source.setCancelHandler {
            close(fd)
        }

        lock.lock()
        sources[configId] = source
        fileDescriptors[configId] = fd
        lock.unlock()

        source.resume()

        // Perform an initial scan to pick up files already present.
        monitorQueue.async { [weak self] in
            self?.handleDirectoryChange(config: config, onNewFile: onNewFile)
        }
    }

    /// Stops monitoring a specific watch folder.
    ///
    /// - Parameter configId: The configuration ID to stop monitoring.
    public func stop(configId: String) {
        lock.lock()
        if let source = sources.removeValue(forKey: configId) {
            source.cancel()
        }
        fileDescriptors.removeValue(forKey: configId)
        lock.unlock()
    }

    /// Stops monitoring all watch folders.
    public func stop() {
        lock.lock()
        for (_, source) in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
        lock.unlock()
    }

    /// Clears the activity log.
    public func clearLog() {
        lock.lock()
        _logEntries.removeAll()
        lock.unlock()
    }

    // MARK: - Persistence

    /// Saves watch folder configurations to disk using ``WatchFolderStore``.
    ///
    /// - Parameter configs: The array of configurations to persist.
    /// - Throws: An error if encoding or writing fails.
    public func saveConfigs(_ configs: [WatchFolderConfig]) throws {
        let directory = configFilePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try WatchFolderStore.encode(configs: configs)
        try data.write(to: configFilePath, options: .atomicWrite)
    }

    /// Loads watch folder configurations from disk.
    ///
    /// - Returns: The array of persisted configurations, or an empty array
    ///   if no configuration file exists.
    public func loadConfigs() -> [WatchFolderConfig] {
        guard FileManager.default.fileExists(atPath: configFilePath.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: configFilePath)
            return try WatchFolderStore.decode(from: data)
        } catch {
            return []
        }
    }

    // MARK: - Private Helpers

    /// Scans the watched directory for new files and triggers debounced
    /// callbacks for any that pass the extension filter.
    ///
    /// Uses the existing ``WatchFolderConfig/shouldProcess(filename:)``
    /// method for filtering.
    ///
    /// - Parameters:
    ///   - config: The watch folder configuration.
    ///   - onNewFile: Callback for each qualifying new file.
    private func handleDirectoryChange(
        config: WatchFolderConfig,
        onNewFile: @escaping NewFileHandler
    ) {
        let fm = FileManager.default
        let watchURL = URL(fileURLWithPath: config.watchPath)

        // Build enumeration options.
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if !config.recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        guard let enumerator = fm.enumerator(
            at: watchURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options
        ) else { return }

        let configId = config.id

        for case let fileURL as URL in enumerator {
            // Check it is a regular file.
            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
            guard let resourceValues = try? fileURL.resourceValues(
                forKeys: resourceKeys
            ), resourceValues.isRegularFile == true else {
                continue
            }

            // Use the existing shouldProcess filter.
            let filename = fileURL.lastPathComponent
            guard config.shouldProcess(filename: filename) else {
                continue
            }

            let filePath = fileURL.path

            // Skip already-processed files.
            lock.lock()
            let alreadyProcessed = processedFiles[configId]?.contains(filePath) ?? false
            lock.unlock()

            if alreadyProcessed { continue }

            // Cancel any existing debounce for this file.
            lock.lock()
            debounceTimers[filePath]?.cancel()

            // Create debounced work item (2-second delay).
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }

                self.lock.lock()
                self.processedFiles[configId]?.insert(filePath)
                self._logEntries.append(WatchFolderLogEntry(
                    filePath: fileURL,
                    configId: configId,
                    status: .encoding
                ))
                self.lock.unlock()

                onNewFile(fileURL)
            }

            debounceTimers[filePath] = workItem
            lock.unlock()

            monitorQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }
    }
}
