// ============================================================================
// MeedyaConverter — AppViewModel
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - NavigationItem

/// Sidebar navigation items for the main app window.
enum NavigationItem: String, CaseIterable, Identifiable {
    /// Source file import and metadata display.
    case source = "Source"

    /// Stream inspector — display all streams with metadata.
    case streams = "Streams"

    /// Output settings — container, codec, quality selection.
    case output = "Output"

    /// Encoding queue — job list with progress.
    case queue = "Queue"

    /// Activity log — structured app events and FFmpeg output.
    case log = "Log"

    var id: String { rawValue }

    /// SF Symbol name for sidebar icon.
    var systemImage: String {
        switch self {
        case .source: return "doc.badge.plus"
        case .streams: return "list.bullet.rectangle"
        case .output: return "gearshape.2"
        case .queue: return "list.number"
        case .log: return "text.page"
        }
    }

    /// Short description for accessibility labels.
    var accessibilityLabel: String {
        switch self {
        case .source: return "Import source media files"
        case .streams: return "Inspect media streams"
        case .output: return "Configure output settings"
        case .queue: return "View encoding queue"
        case .log: return "View activity log"
        }
    }
}

// MARK: - AppViewModel

/// The main application state observable, coordinating the encoding engine,
/// imported media files, and UI state.
///
/// Injected into the SwiftUI environment at the `App` level so all views
/// can access shared state via `@Environment(AppViewModel.self)`.
@Observable
final class AppViewModel {

    // MARK: - Navigation State

    /// The currently selected sidebar item.
    var selectedNavItem: NavigationItem? = .source

    // MARK: - Engine

    /// The shared encoding engine instance.
    let engine: EncodingEngine

    // MARK: - Source Files

    /// The list of imported source media files awaiting configuration.
    var sourceFiles: [MediaFile] = []

    /// The currently selected source file for stream inspection and output settings.
    var selectedFile: MediaFile?

    /// Whether a file import/probe operation is in progress.
    var isProbing: Bool = false

    /// The last error message from a failed operation.
    var lastError: String?

    // MARK: - Output Settings

    /// The currently selected encoding profile for new jobs.
    var selectedProfile: EncodingProfile

    /// The output directory URL for encoded files.
    var outputDirectory: URL?

    // MARK: - Activity Log

    /// Log entries for the unified activity log.
    var logEntries: [LogEntry] = []

    // MARK: - Initialiser

    init() {
        self.engine = EncodingEngine()
        self.selectedProfile = .webStandard

        // Set default output directory to user's Movies folder
        if let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            self.outputDirectory = moviesDir
        }
    }

    // MARK: - File Import

    /// Import media files from URLs by probing each one.
    ///
    /// - Parameter urls: File URLs to import and analyse.
    func importFiles(_ urls: [URL]) async {
        isProbing = true
        lastError = nil

        // Ensure engine is configured
        do {
            try engine.configure()
        } catch {
            lastError = "Failed to configure engine: \(error.localizedDescription)"
            appendLog(.error, "Engine configuration failed: \(error.localizedDescription)")
            isProbing = false
            return
        }

        for url in urls {
            do {
                let mediaFile = try await engine.probe(url: url)
                sourceFiles.append(mediaFile)

                // Auto-select the first imported file
                if selectedFile == nil {
                    selectedFile = mediaFile
                }

                appendLog(.info, "Imported: \(mediaFile.fileName) — \(mediaFile.summaryString)")
            } catch {
                let message = "Failed to probe \(url.lastPathComponent): \(error.localizedDescription)"
                lastError = message
                appendLog(.error, message)
            }
        }

        isProbing = false
    }

    /// Remove a source file from the import list.
    func removeSourceFile(_ file: MediaFile) {
        sourceFiles.removeAll { $0.id == file.id }
        if selectedFile?.id == file.id {
            selectedFile = sourceFiles.first
        }
    }

    /// Remove all source files.
    func clearSourceFiles() {
        sourceFiles.removeAll()
        selectedFile = nil
    }

    // MARK: - Encoding

    /// Create an encoding job for the selected file with current settings and add to queue.
    func enqueueSelectedFile() {
        guard let file = selectedFile else { return }

        // Determine output URL
        let outputDir = outputDirectory ?? FileManager.default.temporaryDirectory
        let outputExtension = selectedProfile.containerFormat.fileExtensions.first ?? "mkv"
        let baseName = file.fileURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDir
            .appendingPathComponent("\(baseName)_converted")
            .appendingPathExtension(outputExtension)

        let config = EncodingJobConfig(
            inputURL: file.fileURL,
            outputURL: outputURL,
            profile: selectedProfile
        )

        engine.queue.addJob(config)
        appendLog(.info, "Queued: \(file.fileName) with profile \"\(selectedProfile.name)\"")

        // Switch to queue view
        selectedNavItem = .queue
    }

    // MARK: - Logging

    /// Append a log entry to the activity log.
    func appendLog(_ level: LogEntry.Level, _ message: String) {
        let entry = LogEntry(level: level, message: message)
        logEntries.append(entry)
    }
}

// MARK: - LogEntry

/// A single entry in the unified activity log.
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let level: Level
    let message: String

    enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"

        var color: Color {
            switch self {
            case .info: return .primary
            case .warning: return .orange
            case .error: return .red
            case .debug: return .secondary
            }
        }

        var systemImage: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .debug: return "ant"
            }
        }
    }
}
