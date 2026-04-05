// ============================================================================
// MeedyaConverter — AppViewModel
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UserNotifications
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
@MainActor @Observable
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

    // MARK: - Stream Selection (Phase 3.4–3.5)

    /// Selected video stream index (nil = default/first).
    var selectedVideoStreamIndex: Int?

    /// Selected audio stream index (nil = default/first).
    var selectedAudioStreamIndex: Int?

    /// Selected subtitle stream index (nil = none).
    var selectedSubtitleStreamIndex: Int?

    /// Whether to map all streams from the source to the output.
    var mapAllStreams: Bool = false

    // MARK: - Stream Metadata (Phase 3.6)

    /// Per-stream metadata overrides from the StreamMetadataEditorView.
    /// Keyed by FFmpeg stream specifier (e.g. "s:v:0"), value is tag dict.
    var streamMetadataOverrides: [String: [String: String]] = [:]

    // MARK: - Crop Detection (Phase 3.14)

    /// Whether automatic crop detection is enabled for new encodes.
    var autoCropEnabled: Bool = true

    /// The detected crop result for the currently selected file.
    var detectedCrop: CropDetectionResult?

    /// Whether crop detection is currently running.
    var isDetectingCrop: Bool = false

    // MARK: - Hardware Encoding (Phase 3.10)

    /// Discovered hardware encoders on this system.
    var availableHardwareEncoders: [HardwareEncoderInfo] = []

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

    // MARK: - Crop Detection (Phase 3.14)

    /// Run automatic black bar crop detection on the selected file.
    func detectCropForSelectedFile() async {
        guard let file = selectedFile else { return }
        isDetectingCrop = true
        detectedCrop = nil

        do {
            try engine.configure()
            let result = try await engine.detectCrop(for: file)
            detectedCrop = result

            if let result = result, result.willCrop {
                appendLog(.info, "Crop detected: \(result.summary)", category: .filter)
            } else {
                appendLog(.info, "No black bars detected in \(file.fileName)", category: .filter)
            }
        } catch {
            appendLog(.warning, "Crop detection failed: \(error.localizedDescription)", category: .filter)
        }

        isDetectingCrop = false
    }

    // MARK: - Hardware Detection (Phase 3.10)

    /// Detect available hardware encoders and cache the results.
    func detectHardwareEncoders() {
        do {
            try engine.configure()
        } catch {
            appendLog(.warning, "Cannot detect hardware encoders: \(error.localizedDescription)")
            return
        }

        let encoders = engine.detectHardwareEncoders()
        availableHardwareEncoders = encoders

        if encoders.isEmpty {
            appendLog(.info, "No hardware encoders detected", category: .encoding)
        } else {
            let names = encoders.map(\.displayName).joined(separator: ", ")
            appendLog(.info, "Hardware encoders available: \(names)", category: .encoding)
        }
    }

    // MARK: - HDR Auto-Trigger (Phase 3.9c)

    /// Check if the current profile settings are HDR-incompatible with an HDR source
    /// and auto-enable tone mapping if needed.
    ///
    /// Triggers when: source has HDR + profile uses BT.709/8-bit/H.264 or non-HDR codec
    /// and video passthrough is off and preserveHDR is off and tone mapping isn't already on.
    func autoTriggerToneMapping() {
        guard let file = selectedFile, file.hasHDR else { return }
        guard !selectedProfile.videoPassthrough else { return }
        guard !selectedProfile.preserveHDR else { return }
        guard !selectedProfile.toneMapToSDR else { return } // Already enabled

        // Check if output settings are HDR-incompatible
        let codecIncompatible = selectedProfile.videoCodec.map { !$0.supportsHDR } ?? false
        let pixelFormatIs8Bit = selectedProfile.pixelFormat == "yuv420p" || selectedProfile.pixelFormat == "yuv422p"
        let containerIncompatible = !selectedProfile.containerFormat.supportsHDR

        if codecIncompatible || pixelFormatIs8Bit || containerIncompatible {
            selectedProfile.toneMapToSDR = true
            if selectedProfile.toneMapAlgorithm == nil {
                selectedProfile.toneMapAlgorithm = "hable"
            }
            appendLog(.info, "HDR source detected with HDR-incompatible output settings — tone mapping auto-enabled", category: .encoding)
        }
    }

    // MARK: - PQ → HLG Auto-Trigger (Issue #254)

    /// Check if the selected PQ → HLG profile matches a PQ source and log accordingly.
    ///
    /// Auto-enables PQ→HLG conversion when the selected profile is the "PQ → HLG" preset
    /// and the source has PQ transfer, or when the user has manually enabled it.
    func logPQToHLGStatus() {
        guard let file = selectedFile, file.hasPQ else { return }
        guard selectedProfile.convertPQToHLG else { return }
        guard !selectedProfile.videoPassthrough else { return }

        if engine.isHlgToolsAvailable && selectedProfile.useHlgTools {
            appendLog(.info, "PQ→HLG: Using hlg-tools for higher quality conversion", category: .hdr)
        } else if engine.isHlgToolsAvailable && !selectedProfile.useHlgTools {
            appendLog(.info, "PQ→HLG: hlg-tools available but FFmpeg zscale forced by user", category: .hdr)
        } else {
            appendLog(.info, "PQ→HLG: Using FFmpeg zscale filter (install hlg-tools for higher quality)", category: .hdr)
        }

        // Log DV+HLG combined pipeline status (Issue #255)
        if selectedProfile.convertPQToDVHLG {
            if engine.doviTool.isAvailable
                && selectedProfile.containerFormat.supportsDolbyVision
                && selectedProfile.videoCodec == .h265 {
                appendLog(.info, "PQ→DV+HLG: Will generate Dolby Vision Profile 8.4 RPU for three-tier compatibility (DV→HLG→SDR)", category: .hdr)
            } else if !engine.doviTool.isAvailable {
                appendLog(.warning, "PQ→DV+HLG: dovi_tool not available — will produce HLG-only output", category: .hdr)
            } else {
                appendLog(.warning, "PQ→DV+HLG: Container or codec does not support Dolby Vision — will produce HLG-only output", category: .hdr)
            }
        }
    }

    // MARK: - Encoding

    /// Create an encoding job for the selected file with current settings and add to queue.
    func enqueueSelectedFile() {
        guard let file = selectedFile else { return }

        // Auto-trigger tone mapping if HDR source with incompatible output (Phase 3.9c)
        autoTriggerToneMapping()

        // Log PQ → HLG conversion status (Issue #254)
        logPQToHLGStatus()

        // Determine output URL
        let outputDir = outputDirectory ?? FileManager.default.temporaryDirectory
        let outputExtension = selectedProfile.containerFormat.fileExtensions.first ?? "mkv"
        let baseName = file.fileURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDir
            .appendingPathComponent("\(baseName)_converted")
            .appendingPathExtension(outputExtension)

        // Apply auto-crop filter if enabled and a crop was detected
        var cropFilter: String? = nil
        if autoCropEnabled, let crop = detectedCrop, crop.willCrop {
            cropFilter = crop.recommendedCrop.filterString
            appendLog(.info, "Auto-crop: \(crop.recommendedCrop.displayString) (\(String(format: "%.1f", crop.cropPercentage))% removed)")
        }

        let config = EncodingJobConfig(
            inputURL: file.fileURL,
            outputURL: outputURL,
            profile: selectedProfile,
            videoStreamIndex: selectedVideoStreamIndex,
            audioStreamIndex: selectedAudioStreamIndex,
            subtitleStreamIndex: selectedSubtitleStreamIndex,
            mapAllStreams: mapAllStreams,
            streamMetadata: streamMetadataOverrides,
            videoFilterChain: cropFilter
        )

        engine.queue.addJob(config)
        appendLog(.info, "Queued: \(file.fileName) with profile \"\(selectedProfile.name)\"")

        // Switch to queue view
        selectedNavItem = .queue
    }

    // MARK: - Queue Processing

    /// Whether the queue is currently processing jobs sequentially.
    var isQueueRunning = false

    /// The currently encoding job state (for UI binding).
    var activeJobState: EncodingJobState?

    /// Start processing the encoding queue sequentially.
    ///
    /// Picks the next queued job, encodes it, then moves to the next
    /// until no queued jobs remain or the queue is stopped.
    func startQueue() async {
        guard !isQueueRunning else { return }
        isQueueRunning = true

        // Ensure engine is configured
        do {
            try engine.configure()
        } catch {
            appendLog(.error, "Engine configuration failed: \(error.localizedDescription)")
            isQueueRunning = false
            return
        }

        appendLog(.info, "Queue started")

        // Prevent system sleep during encoding
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "MeedyaConverter is encoding media"
        )

        while isQueueRunning, let jobState = engine.queue.nextPendingJob() {
            activeJobState = jobState
            jobState.status = .encoding
            jobState.startedAt = Date()
            engine.queue.currentJob = jobState

            appendLog(.info, "Encoding: \(jobState.config.inputURL.lastPathComponent)",
                      category: .encoding, jobID: jobState.config.id)

            do {
                try await engine.encode(job: jobState.config) { [self] progressInfo in
                    Task { @MainActor in
                        jobState.progress = progressInfo.fractionComplete ?? 0
                        jobState.speed = progressInfo.speed
                        jobState.currentBitrate = progressInfo.bitrate
                        jobState.currentFrame = progressInfo.frame

                        // Calculate ETA from speed and remaining fraction
                        if let fraction = progressInfo.fractionComplete, fraction > 0,
                           let startedAt = jobState.startedAt {
                            let elapsed = Date().timeIntervalSince(startedAt)
                            let totalEstimated = elapsed / fraction
                            jobState.eta = totalEstimated - elapsed
                        }

                        // Log raw FFmpeg output
                        if let raw = progressInfo.rawLine, !raw.isEmpty {
                            self.appendLog(.debug, raw, source: .ffmpeg,
                                           category: .progress, rawOutput: raw,
                                           jobID: jobState.config.id)
                        }
                    }
                }

                jobState.status = .completed
                jobState.progress = 1.0
                jobState.completedAt = Date()

                let elapsed = jobState.elapsedTime.map { formatDuration($0) } ?? "unknown"
                appendLog(.info, "Completed: \(jobState.config.inputURL.lastPathComponent) in \(elapsed)",
                          category: .encoding, jobID: jobState.config.id)

                sendNotification(
                    title: "Encoding Complete",
                    body: "\(jobState.config.inputURL.lastPathComponent) finished in \(elapsed)",
                    settingKey: "notifyOnCompletion"
                )

            } catch {
                jobState.status = .failed
                jobState.errorMessage = error.localizedDescription
                jobState.completedAt = Date()

                appendLog(.error, "Failed: \(jobState.config.inputURL.lastPathComponent) — \(error.localizedDescription)",
                          category: .encoding, jobID: jobState.config.id)

                sendNotification(
                    title: "Encoding Failed",
                    body: "\(jobState.config.inputURL.lastPathComponent): \(error.localizedDescription)",
                    settingKey: "notifyOnFailure"
                )
            }

            engine.queue.currentJob = nil
            activeJobState = nil
        }

        ProcessInfo.processInfo.endActivity(activity)
        isQueueRunning = false

        let summary = "\(engine.queue.completedCount) completed, \(engine.queue.failedCount) failed"
        appendLog(.info, "Queue finished — \(summary)")

        sendNotification(
            title: "Queue Finished",
            body: summary,
            settingKey: "notifyOnQueueFinished"
        )
    }

    /// Stop the queue after the current job finishes.
    func stopQueue() {
        isQueueRunning = false
        appendLog(.info, "Queue stopping after current job")
    }

    /// Pause the currently encoding job.
    func pauseCurrentJob() {
        engine.pauseEncoding()
        activeJobState?.status = .paused
        appendLog(.info, "Encoding paused")
    }

    /// Resume the currently paused job.
    func resumeCurrentJob() {
        engine.resumeEncoding()
        activeJobState?.status = .encoding
        appendLog(.info, "Encoding resumed")
    }

    /// Cancel the currently encoding job and stop the queue.
    func cancelCurrentJob() {
        engine.stopEncoding()
        activeJobState?.status = .cancelled
        activeJobState?.completedAt = Date()
        isQueueRunning = false
        appendLog(.warning, "Encoding cancelled")
    }

    // MARK: - Notifications

    /// Send a macOS notification if the corresponding setting is enabled.
    private func sendNotification(title: String, body: String, settingKey: String) {
        let enabled = UserDefaults.standard.bool(forKey: settingKey)
        // Default to true if key hasn't been set
        let isEnabled = UserDefaults.standard.object(forKey: settingKey) == nil ? true : enabled

        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UserDefaults.standard.bool(forKey: "playSoundOnCompletion")
            ? .default : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Logging

    /// Append a log entry to the activity log.
    func appendLog(
        _ level: LogEntry.Level,
        _ message: String,
        source: LogEntry.Source = .app,
        category: LogEntry.Category = .general,
        rawOutput: String? = nil,
        details: [String: String]? = nil,
        jobID: UUID? = nil
    ) {
        let entry = LogEntry(
            level: level,
            message: message,
            source: source,
            category: category,
            rawOutput: rawOutput,
            details: details,
            jobID: jobID
        )
        logEntries.append(entry)
    }

    /// Export all log entries as JSON data.
    func exportLogAsJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(logEntries)
    }

    /// Export all log entries as plain text.
    func exportLogAsText() -> String {
        let formatter = ISO8601DateFormatter()
        return logEntries.map { entry in
            let ts = formatter.string(from: entry.timestamp)
            return "[\(ts)] [\(entry.level.rawValue)] [\(entry.source.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Format a time interval as a human-readable duration.
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - LogEntry

/// A single entry in the unified activity log.
///
/// Combines structured application events and raw FFmpeg/tool output
/// into a single filterable log stream per issue #249.
struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: Level
    let source: Source
    let category: Category
    let message: String
    /// Raw subprocess output line (for FFmpeg/tool entries).
    let rawOutput: String?
    /// Structured key-value details for app events.
    let details: [String: String]?
    /// The job ID this entry relates to (nil for app-level events).
    let jobID: UUID?

    init(
        level: Level,
        message: String,
        source: Source = .app,
        category: Category = .general,
        rawOutput: String? = nil,
        details: [String: String]? = nil,
        jobID: UUID? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.source = source
        self.category = category
        self.message = message
        self.rawOutput = rawOutput
        self.details = details
        self.jobID = jobID
    }

    // MARK: - Level

    enum Level: String, Codable, CaseIterable {
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

    // MARK: - Source

    /// The origin of this log entry.
    enum Source: String, Codable, CaseIterable {
        /// Structured application event.
        case app
        /// Raw FFmpeg stderr output.
        case ffmpeg
        /// MediaInfo analysis output.
        case mediainfo
        /// dovi_tool output.
        case doviTool = "dovi_tool"
        /// hlg-tools output (PQ → HLG conversion).
        case hlgTools = "hlg_tools"
        /// System-level event (temp files, disk space).
        case system
    }

    // MARK: - Category

    /// Logical category for filtering.
    enum Category: String, Codable, CaseIterable {
        case general
        case encoding
        case settings
        case stream
        case filter
        case audio
        case hdr
        case metadata
        case tempFiles = "temp_files"
        case progress

        var displayName: String {
            switch self {
            case .general: return "General"
            case .encoding: return "Encoding"
            case .settings: return "Settings"
            case .stream: return "Stream"
            case .filter: return "Filter"
            case .audio: return "Audio"
            case .hdr: return "HDR"
            case .metadata: return "Metadata"
            case .tempFiles: return "Temp Files"
            case .progress: return "Progress"
            }
        }
    }
}
