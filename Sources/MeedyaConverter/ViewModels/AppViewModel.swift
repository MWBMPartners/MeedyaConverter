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
///
/// Organised into logical sections: Workflow (encoding pipeline),
/// Monitor (queue, log, dashboard, performance), Tools (editing,
/// analysis, batch operations), and Distribution (upload, cloud).
enum NavigationItem: String, CaseIterable, Identifiable {

    // -- Workflow ----------------------------------------------------------

    /// Source file import and metadata display.
    case source = "Source"

    /// Media library browser — browse and import from a media library.
    case mediaBrowser = "Media Browser"

    /// Stream inspector — display all streams with metadata.
    case streams = "Streams"

    /// Output settings — container, codec, quality selection.
    case output = "Output"

    // -- Monitor -----------------------------------------------------------

    /// Encoding queue — job list with progress.
    case queue = "Queue"

    /// Activity log — structured app events and FFmpeg output.
    case log = "Log"

    /// Aggregate encoding statistics dashboard.
    case dashboard = "Dashboard"

    /// Per-job encoding graphs (FPS, bitrate, speed over time).
    case encodingGraphs = "Encoding Graphs"

    /// Export encoding statistics history as CSV or JSON.
    case statisticsExport = "Statistics Export"

    /// Live CPU / memory / disk resource monitor.
    case resourceMonitor = "Resource Monitor"

    // -- Tools -------------------------------------------------------------

    /// Image conversion — batch image format conversion.
    case images = "Images"

    /// Raster → vector (SVG) conversion. Issues #376 engine / #381 / #402 UI.
    case vectorConversion = "Vector Conversion"

    /// ProRes → animated SVG conversion. Issues #377 engine / #381 / #404 UI.
    case proresVector = "ProRes to Vector"

    /// Disc burning — write to physical optical media.
    case burn = "Burn"

    /// Video trimming, splitting, and snipping.
    case trimEdit = "Trim / Edit"

    /// Analysis hub — scene detection, bitrate heatmap, quality check,
    /// quality metrics, loudness report, audio waveform.
    case analyze = "Analyze"

    /// Metadata tag editor for source and output files.
    case metadataTags = "Metadata"

    /// Batch rename output files using templates.
    case batchRename = "Batch Rename"

    /// Concatenation — join multiple media files.
    case concatenation = "Concatenate"

    /// Watermark overlay editor.
    case watermark = "Watermark"

    /// Multi-output encoding — one source to many outputs.
    case multiOutput = "Multi-Output"

    /// Dual dynamic HDR conversion (Dolby Vision + HDR10+).
    case dualDynamicHDR = "Dual Dynamic HDR"

    /// Visual FFmpeg filter graph editor.
    case filterGraph = "Filter Graph"

    /// EDL (Edit Decision List) editor for import/export.
    case edlEditor = "EDL Editor"

    /// Animated image (GIF / APNG / WebP) creation.
    case animatedImage = "Animated Image"

    /// Smart crop — subject detection and intelligent cropping.
    case smartCrop = "Smart Crop"

    /// Background removal for images.
    case backgroundRemoval = "Background Removal"

    /// Voice isolation from audio/video sources.
    case voiceIsolation = "Voice Isolation"

    /// Duplicate file finder across media library.
    case duplicateFinder = "Duplicate Finder"

    /// Parallel encoding — multi-job concurrency settings.
    case parallelEncoding = "Parallel Encoding"

    /// Queue optimizer — reorder and optimise the queue.
    case queueOptimizer = "Queue Optimizer"

    /// Benchmark — hardware encoding performance test.
    case benchmark = "Benchmark"

    /// Storage analysis — disk usage by output files.
    case storageAnalysis = "Storage Analysis"

    /// Comparison library — saved before/after comparisons.
    case comparisonLibrary = "Comparisons"

    /// Recently opened source files.
    case recentFiles = "Recent Files"

    // -- Distribution ------------------------------------------------------

    /// Video upload to platforms (YouTube, Vimeo, etc.).
    case videoUpload = "Upload"

    /// Cloud storage integration (S3, GCS, etc.).
    case cloudStorage = "Cloud Storage"

    /// SFTP upload configuration.
    case sftp = "SFTP"

    /// Podcast RSS feed generation.
    case podcastFeed = "Podcast Feed"

    /// Team profile sharing and collaboration.
    case teamProfile = "Team Profile"

    /// Cloud sync of settings and profiles.
    case cloudSync = "Cloud Sync"

    var id: String { rawValue }

    /// SF Symbol name for sidebar icon.
    var systemImage: String {
        switch self {
        case .source:            return "doc.badge.plus"
        case .mediaBrowser:      return "rectangle.stack.badge.play"
        case .streams:           return "list.bullet.rectangle"
        case .output:            return "gearshape.2"
        case .queue:             return "list.number"
        case .log:               return "text.page"
        case .dashboard:         return "chart.bar.xaxis"
        case .encodingGraphs:    return "chart.xyaxis.line"
        case .statisticsExport:  return "square.and.arrow.up.on.square"
        case .resourceMonitor:   return "gauge.with.dots.needle.33percent"
        case .images:            return "photo.on.rectangle.angled"
        case .vectorConversion:  return "scribble.variable"
        case .proresVector:      return "film.fill"
        case .burn:              return "opticaldisc"
        case .trimEdit:          return "scissors"
        case .analyze:           return "waveform.and.magnifyingglass"
        case .metadataTags:      return "tag"
        case .batchRename:       return "pencil.and.list.clipboard"
        case .concatenation:     return "link"
        case .watermark:         return "text.below.photo"
        case .multiOutput:       return "arrow.triangle.branch"
        case .dualDynamicHDR:    return "sparkles.tv"
        case .filterGraph:       return "flowchart"
        case .edlEditor:         return "list.clipboard"
        case .animatedImage:     return "photo.stack"
        case .smartCrop:         return "crop"
        case .backgroundRemoval: return "person.and.background.dotted"
        case .voiceIsolation:    return "waveform.badge.mic"
        case .duplicateFinder:   return "doc.on.doc"
        case .parallelEncoding:  return "cpu"
        case .queueOptimizer:    return "arrow.up.arrow.down"
        case .benchmark:         return "speedometer"
        case .storageAnalysis:   return "internaldrive"
        case .comparisonLibrary: return "square.split.2x1"
        case .recentFiles:       return "clock.arrow.circlepath"
        case .videoUpload:       return "icloud.and.arrow.up"
        case .cloudStorage:      return "cloud"
        case .sftp:              return "network"
        case .podcastFeed:       return "antenna.radiowaves.left.and.right"
        case .teamProfile:       return "person.2"
        case .cloudSync:         return "arrow.triangle.2.circlepath.icloud"
        }
    }

    /// Short description for accessibility labels.
    var accessibilityLabel: String {
        switch self {
        case .source:            return "Import source media files"
        case .mediaBrowser:      return "Browse and import media library"
        case .streams:           return "Inspect media streams"
        case .output:            return "Configure output settings"
        case .queue:             return "View encoding queue"
        case .log:               return "View activity log"
        case .dashboard:         return "View encoding statistics dashboard"
        case .encodingGraphs:    return "View per-job encoding graphs"
        case .statisticsExport:  return "Export encoding statistics"
        case .resourceMonitor:   return "Monitor system resources"
        case .images:            return "Convert images"
        case .vectorConversion:  return "Convert raster images to vector SVG"
        case .proresVector:      return "Convert ProRes 4444 video to animated SVG"
        case .burn:              return "Burn disc"
        case .trimEdit:          return "Trim and edit video"
        case .analyze:           return "Analyse media files"
        case .metadataTags:      return "Edit metadata tags"
        case .batchRename:       return "Batch rename output files"
        case .concatenation:     return "Join media files together"
        case .watermark:         return "Add watermark overlay"
        case .multiOutput:       return "Encode to multiple outputs"
        case .dualDynamicHDR:    return "Convert dual dynamic HDR formats"
        case .filterGraph:       return "Edit FFmpeg filter graph"
        case .edlEditor:         return "Edit decision list editor"
        case .animatedImage:     return "Create animated images"
        case .smartCrop:         return "Detect subjects and crop intelligently"
        case .backgroundRemoval: return "Remove image backgrounds"
        case .voiceIsolation:    return "Isolate voice from audio"
        case .duplicateFinder:   return "Find duplicate media files"
        case .parallelEncoding:  return "Configure parallel encoding"
        case .queueOptimizer:    return "Optimise encoding queue"
        case .benchmark:         return "Run encoding benchmark"
        case .storageAnalysis:   return "Analyse storage usage"
        case .comparisonLibrary: return "View saved comparisons"
        case .recentFiles:       return "View recently opened files"
        case .videoUpload:       return "Upload video to platforms"
        case .cloudStorage:      return "Manage cloud storage"
        case .sftp:              return "Configure SFTP upload"
        case .podcastFeed:       return "Generate podcast RSS feed"
        case .teamProfile:       return "Manage team profiles"
        case .cloudSync:         return "Sync settings via cloud"
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

    // MARK: - Update Checker (Phase 9 / Issue #94)

    /// Application update checker (Sparkle 2 for direct builds, no-op for App Store).
    let updateChecker: AppUpdateChecker

    // MARK: - Store Manager (Phase 15 / Issue #309)

    /// StoreKit 2 manager for in-app purchases and subscription tracking.
    let storeManager: StoreManager

    // MARK: - Remote Feature Gate (Roadmap #5 / intAppsAPI)

    /// Remote feature-flag provider backing the `video-upload` gate below.
    /// Wraps intAppsAPI when credentials are configured (Keychain or
    /// `MEEDYACONVERTER_INTAPPSAPI_*` env vars); completely dormant
    /// otherwise — see `RemoteFeatureGateProvider`'s doc comment for the
    /// dormancy + fail-safe contract.
    let remoteFeatureGate: RemoteFeatureGateProvider

    /// Whether the Video Upload feature (`VideoUploadView` + its sidebar
    /// entry) is exposed, per the remote `video-upload` flag.
    ///
    /// Initialised synchronously in `init()` from whatever
    /// `remoteFeatureGate` already has cached (a persisted cache from a
    /// previous run, or the compiled-in fail-safe default of `false`) —
    /// the sidebar renders correctly on the very first frame without
    /// blocking launch on a network round trip.
    /// `refreshRemoteFeatureFlags()` updates this after a fetch attempt.
    var isVideoUploadEnabled: Bool

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

    /// How output files are organised relative to the output directory.
    /// Defaults to `.flatten` (all files in the output directory).
    var outputMode: OutputMode = .flatten

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

    // MARK: - Mini Player (Issue #280)

    /// Floating mini player controller for compact encoding progress display.
    let miniPlayer = MiniPlayerController()

    // MARK: - Keyboard Shortcuts (Issue #331)

    /// Manager for user-assignable keyboard shortcuts.
    let shortcutManager = KeyboardShortcutManager()

    // MARK: - Activity Indicators (Issue #182)

    /// System-level encoding activity indicator (menu bar + dock tile).
    let activityIndicator = EncodingActivityIndicator()

    // MARK: - Analytics (Phase 12 / Issue #183)

    /// Privacy-respecting, opt-in analytics engine.
    /// Disabled by default — no data collected until the user enables it.
    let analytics = AnalyticsEngine()

    // MARK: - Encoding Scheduler (Issue #279)

    /// Manages scheduled encoding jobs that fire at user-specified times.
    let scheduler = EncodingScheduler()

    // MARK: - Audio Waveform (Issue #289)

    /// Waveform data for the currently selected audio stream.
    var currentWaveformData: WaveformData?

    /// Whether waveform analysis is currently in progress.
    var isAnalysingWaveform: Bool = false

    /// Selected audio channel for waveform display (0-based).
    var selectedWaveformChannel: Int = 0

    // MARK: - Pipeline (Issue #278)

    /// Whether the pipeline editor sheet is presented.
    var showPipelineEditor: Bool = false

    /// Whether the schedule view sheet is presented.
    var showScheduleView: Bool = false

    // MARK: - Activity Log

    /// Log entries for the unified activity log.
    var logEntries: [LogEntry] = []

    // MARK: - Recent Files (Issue #334)

    /// Tracks recently imported files for the Recent Files sidebar view.
    ///
    /// `RecentFilesView` holds its own separate `RecentFilesManager`
    /// instance too — both read/write the same on-disk JSON store
    /// (`~/Library/Application Support/MeedyaConverter/recent_files.json`),
    /// so an entry recorded here (from `importFiles`) becomes visible the
    /// next time the user navigates to Recent Files: `ContentView`'s
    /// switch-based routing tears down and recreates `RecentFilesView`
    /// (and its `@State` manager, which reloads from disk in `init()`) on
    /// every navigation, so this doesn't need to be the same live
    /// instance to be picked up.
    let recentFilesManager = RecentFilesManager()

    // MARK: - Initialiser

    init() {
        self.engine = EncodingEngine()
        self.updateChecker = AppUpdateChecker()
        self.storeManager = StoreManager()
        self.selectedProfile = .webStandard

        // Remote feature gate (#5): seed synchronously from whatever is
        // already cached (persisted cache or the compiled-in default) so
        // the sidebar/VideoUploadView render correctly on the first
        // frame. `refreshRemoteFeatureFlags()` is kicked off later from
        // `MeedyaConverterApp`'s `.onAppear`, alongside the StoreKit
        // product load — see that file for the "plain Task {} inside a
        // @MainActor SwiftUI closure" pattern this mirrors.
        // Assigned from a local (rather than reading `self.remoteFeatureGate`
        // back out) so this doesn't trip Swift's two-phase-init rule —
        // `self` can't be read from until every stored property has been
        // assigned, and this class has many more below this point.
        let featureGate = RemoteFeatureGateProvider()
        self.remoteFeatureGate = featureGate
        self.isVideoUploadEnabled = featureGate.isVideoUploadEnabled

        // Set default output directory to user's Movies folder
        if let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            self.outputDirectory = moviesDir
        }

        // Track app launch (no-op if analytics is disabled)
        analytics.track(.appLaunch)

        // Wire up the encoding scheduler callback (Issue #279, re #279).
        //
        // Previously this only called `addJob(config)` and logged
        // "Scheduled job started" — but nothing ever called `startQueue()`,
        // so a scheduled job just sat in `.queued` state until a human
        // happened to open Queue and press Start. `nextPendingJob()` picks
        // up newly-added jobs automatically once the queue loop is
        // running, so if the queue is already going we only need to
        // enqueue; otherwise we start it — mirroring the
        // `Task { await viewModel.startQueue() }` pattern
        // `JobQueueView`'s Start Queue button already uses. The log
        // message is made truthful either way instead of always claiming
        // "started".
        scheduler.onJobReady = { [weak self] config in
            guard let self else { return }
            Task { @MainActor in
                self.engine.queue.addJob(config)
                if self.isQueueRunning {
                    self.appendLog(.info, "Scheduled job added to running queue: \(config.inputURL.lastPathComponent)")
                } else {
                    self.appendLog(.info, "Scheduled job started: \(config.inputURL.lastPathComponent)")
                    await self.startQueue()
                }
            }
        }
    }

    // MARK: - Remote Feature Gate (Roadmap #5 / intAppsAPI)

    /// Refreshes the `video-upload` remote flag from intAppsAPI and
    /// updates the observable `isVideoUploadEnabled`/sidebar state.
    ///
    /// Safe to call unconditionally on every launch (wired from
    /// `MeedyaConverterApp`'s `.onAppear`, alongside the StoreKit product
    /// load) — a no-op when intAppsAPI is not configured (dormant), and
    /// never throws or surfaces an error to the UI when the API is
    /// unreachable (fail-safe: `remoteFeatureGate.refreshFlags()` keeps
    /// whatever was already cached/compiled-in on failure).
    ///
    /// If the flag comes back disabled while the user is currently
    /// looking at Video Upload (e.g. a maintainer flips the flag off
    /// mid-session), navigates back to Source rather than leaving the
    /// user stranded on a view whose sidebar entry just disappeared.
    func refreshRemoteFeatureFlags() async {
        await remoteFeatureGate.refreshFlags()
        isVideoUploadEnabled = remoteFeatureGate.isVideoUploadEnabled

        if !isVideoUploadEnabled && selectedNavItem == .videoUpload {
            selectedNavItem = .source
        }
    }

    // MARK: - Audio Waveform Analysis (Issue #289)

    /// Analyse the currently selected file's audio and generate waveform data.
    ///
    /// Uses FFmpeg to extract raw PCM data, then parses it into
    /// ``WaveformData`` for display in ``AudioWaveformView``.
    func analyseAudioWaveform() async {
        guard let file = selectedFile else { return }
        isAnalysingWaveform = true
        currentWaveformData = nil

        let inputPath = file.fileURL.path
        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir.appendingPathComponent("meedya_waveform_\(file.id.uuidString).raw").path

        let args = AudioWaveformGenerator.buildWaveformArguments(
            inputPath: inputPath,
            outputPath: outputPath
        )

        do {
            // Run FFmpeg to extract PCM data
            try await engine.runFFmpeg(arguments: args, onProgress: { _ in })

            // Parse the raw PCM into waveform data
            let duration = file.duration ?? 0
            if let data = AudioWaveformGenerator.parseWaveformData(
                from: outputPath,
                duration: duration,
                channels: file.audioStreams.first?.channelLayout?.channelCount ?? 1
            ) {
                currentWaveformData = data
                appendLog(.info, "Waveform analysis complete for \(file.fileName)")
            } else {
                appendLog(.warning, "Failed to parse waveform data for \(file.fileName)")
            }

            // Clean up temp file
            try? FileManager.default.removeItem(atPath: outputPath)
        } catch {
            appendLog(.error, "Waveform analysis failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        isAnalysingWaveform = false
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

                // Record in Recent Files (Issue #334). `addRecent(_:)`
                // previously had exactly one caller — RecentFilesView's
                // own re-import action — so the list could never actually
                // populate from a normal import. Only recorded on a
                // successful probe, matching the `sourceFiles.append`
                // above.
                recentFilesManager.addRecent(mediaFile.fileURL)
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

        // Determine output URL using filename template (Issue #272),
        // honouring the "Overwrite existing output files" setting
        // (SettingsView.overwriteExisting — previously persisted but
        // never read). `false` (the default) keeps the pre-existing
        // auto-rename-on-collision behaviour via
        // `resolveWithCollisionHandling`; `true` reuses the resolved path
        // even if a file is already there, which FFmpeg (invoked with
        // `-y` for every job) then overwrites in place.
        let outputDir = outputDirectory ?? FileManager.default.temporaryDirectory
        let outputExtension = selectedProfile.containerFormat.fileExtensions.first ?? "mkv"
        let templateString = UserDefaults.standard.string(forKey: "filenameTemplate") ?? "{title}_converted"
        let template = FilenameTemplate(template: templateString)
        let overwriteExisting = UserDefaults.standard.bool(forKey: "overwriteExisting")
        let outputURL = template.resolveOutputURL(
            sourceFile: file,
            profile: selectedProfile,
            outputDirectory: outputDir,
            fileExtension: outputExtension,
            overwriteExisting: overwriteExisting
        )

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

    // MARK: - Watch Folder Auto-Encoding (Issue #268)

    /// Enqueue a file detected by a watch folder monitor and start the
    /// queue if it isn't already running.
    ///
    /// `WatchFolderView` previously passed `WatchFolderMonitor.start` a
    /// callback that discarded every detection (`{ _ in
    /// /* Encoding trigger handled by app coordinator. */ }`) — no such
    /// coordinator existed, so watch folders never actually encoded
    /// anything. This is the wiring: build an `EncodingJobConfig` (same
    /// shape `enqueueSelectedFile()` builds above) from the detected file
    /// and the watch folder's own config, add it to the queue, then start
    /// the queue if needed — mirroring the scheduler's `onJobReady`
    /// wiring above.
    ///
    /// Uses `FileStabilityChecker.outputPath(for:config:outputExtension:)`
    /// — the existing purpose-built helper for watch-folder output paths
    /// (already handles the `recursive` subdirectory-mirroring case and
    /// filename sanitisation) — rather than `FilenameTemplate`, since
    /// building a `MediaFile` here would require an extra async probe of
    /// every detected file before it could even be queued. Does not honour
    /// the Source tab's `filenameTemplate`/`overwriteExisting` settings for
    /// the same reason; watch folders have always had their own separate
    /// output-path convention.
    ///
    /// - Parameters:
    ///   - url: The detected file's URL.
    ///   - config: The watch folder configuration that detected it.
    func enqueueWatchFolderFile(_ url: URL, config: WatchFolderConfig) {
        // Resolve the configured profile by name. `WatchFolderConfig`'s
        // own default (`profileName: "webStandard"`, set by `addNewConfig()`
        // in `WatchFolderView`) does not match any built-in profile's
        // display name ("Web Standard") under `profileStore.profile(named:)`'s
        // case-insensitive-exact match — so falling back to Web Standard
        // with a warning (rather than silently dropping the file) is the
        // common case, not just a defensive edge case.
        let profile: EncodingProfile
        if let resolved = engine.profileStore.profile(named: config.profileName) {
            profile = resolved
        } else {
            appendLog(
                .warning,
                "Watch folder \"\(config.name)\": profile \"\(config.profileName)\" not found — using Web Standard.",
                category: .encoding
            )
            profile = .webStandard
        }

        let outputExtension = profile.containerFormat.fileExtensions.first ?? "mp4"
        let outputPath = FileStabilityChecker.outputPath(
            for: url.path,
            config: config,
            outputExtension: outputExtension
        )
        let outputURL = URL(fileURLWithPath: outputPath)

        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let jobConfig = EncodingJobConfig(inputURL: url, outputURL: outputURL, profile: profile)
        engine.queue.addJob(jobConfig)
        appendLog(
            .info,
            "Watch folder \"\(config.name)\" queued: \(url.lastPathComponent) with profile \"\(profile.name)\"",
            category: .encoding,
            jobID: jobConfig.id
        )

        if isQueueRunning {
            appendLog(.info, "Added to running queue.", category: .encoding, jobID: jobConfig.id)
        } else {
            Task { await startQueue() }
        }
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

            // Activate system-level progress indicators (Issue #182)
            activityIndicator.startTracking(jobState: jobState)

            appendLog(.info, "Encoding: \(jobState.config.inputURL.lastPathComponent)",
                      category: .encoding, jobID: jobState.config.id)

            // Track encode start — codec and container only, never file names (Issue #183)
            var encodeProps: [String: String] = [
                "container": jobState.config.profile.containerFormat.rawValue
            ]
            if let codec = jobState.config.profile.videoCodec {
                encodeProps["codec"] = codec.rawValue
            }
            analytics.track(.encodeStart, properties: encodeProps)

            // Track profile usage for built-in profiles only (Issue #183)
            let builtInProfileNames: Set<String> = [
                "Web Standard", "Archive", "Quick Convert", "Apple ProRes",
                "HDR Passthrough", "Audio Only"
            ]
            if builtInProfileNames.contains(jobState.config.profile.name) {
                analytics.track(.profileUsed, properties: ["profile": jobState.config.profile.name])
            }

            // Per-job encoding statistics collector (Issue #284, re #448).
            // EncodingStatisticsCollector already existed in ConverterEngine
            // but was referenced nowhere in the pipeline, so
            // EncodingGraphsView (wired in #448) was always empty. This is
            // the insertion point: create one collector per job, feed it
            // from the existing `progressInfo` closure below, and persist
            // it via `EncodingStatisticsStore` on completion.
            let statsCollector = EncodingStatisticsCollector(
                jobID: jobState.config.id,
                jobName: jobState.config.inputURL.lastPathComponent
            )
            statsCollector.setInputMetadata(
                fileSize: fileSizeInBytes(atPath: jobState.config.inputURL.path),
                duration: nil,
                videoCodec: jobState.config.profile.videoCodec?.rawValue,
                audioCodec: jobState.config.profile.audioCodec?.rawValue,
                profileName: jobState.config.profile.name,
                containerFormat: jobState.config.profile.containerFormat.fileExtensions.first ?? "mkv"
            )

            do {
                try await engine.encode(job: jobState.config) { progressInfo in
                    Task { @MainActor [weak self] in
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

                        // Update system-level activity indicators (Issue #182)
                        self?.activityIndicator.updateProgress(
                            fraction: jobState.progress,
                            speed: jobState.speed,
                            fileName: jobState.config.inputURL.lastPathComponent
                        )

                        // Log raw FFmpeg output
                        if let raw = progressInfo.rawLine, !raw.isEmpty {
                            self?.appendLog(.debug, raw, source: .ffmpeg,
                                            category: .progress, rawOutput: raw,
                                            jobID: jobState.config.id)
                        }

                        // Record a statistics data point (Issue #284).
                        // `FFmpegProgressInfo` has no `fps` field, so it is
                        // recovered from FFmpeg's own raw "fps=" line via
                        // `EncodingStatisticsCollector.fps(fromRawProgressLine:)`
                        // rather than changing `FFmpegProcessController`'s
                        // parser. `recordProgress` self-throttles to its
                        // configured sample interval, so calling it on
                        // every tick here is intentional, not wasteful.
                        statsCollector.recordProgress(
                            fps: EncodingStatisticsCollector.fps(fromRawProgressLine: progressInfo.rawLine),
                            bitrate: progressInfo.bitrate,
                            encodedSeconds: progressInfo.currentTime ?? 0,
                            frameNumber: progressInfo.frame ?? 0,
                            outputSizeBytes: progressInfo.totalSize.map { Int64($0) },
                            speed: progressInfo.speed
                        )
                    }
                }

                jobState.status = .completed
                jobState.progress = 1.0
                jobState.completedAt = Date()

                let elapsed = jobState.elapsedTime.map { formatDuration($0) } ?? "unknown"
                appendLog(.info, "Completed: \(jobState.config.inputURL.lastPathComponent) in \(elapsed)",
                          category: .encoding, jobID: jobState.config.id)

                // Finalise and persist this job's statistics (Issue #284).
                // `EncodingStatisticsStore` reads/writes its JSON history
                // file synchronously in `init()`/`addStatistics(_:)`, so —
                // mirroring `EncodingGraphsView`'s own handling of the same
                // store — that disk I/O runs via `Task.detached` rather
                // than blocking this `@MainActor`-isolated method. Only the
                // `Sendable` `EncodingStatistics` snapshot crosses into the
                // detached task, never `self`/`jobState`.
                if let outputSize = fileSizeInBytes(atPath: jobState.config.outputURL.path) {
                    statsCollector.setOutputFileSize(outputSize)
                }
                statsCollector.markComplete()
                let finalStatistics = statsCollector.currentStatistics
                await Task.detached {
                    EncodingStatisticsStore().addStatistics(finalStatistics)
                }.value

                // Track encode completion with duration category (Issue #183)
                let durationCategory: String
                if let duration = jobState.elapsedTime {
                    if duration < 60 { durationCategory = "short" }
                    else if duration < 600 { durationCategory = "medium" }
                    else { durationCategory = "long" }
                } else {
                    durationCategory = "unknown"
                }
                analytics.track(.encodeComplete, properties: ["duration": durationCategory])

                sendNotification(
                    title: "Encoding Complete",
                    body: "\(jobState.config.inputURL.lastPathComponent) finished in \(elapsed)",
                    settingKey: "notifyOnCompletion"
                )

                let outputSizeBytes = fileSizeInBytes(atPath: jobState.config.outputURL.path)
                let outputSizeLabel = outputSizeBytes
                    .map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "unknown"
                sendCompletionEmail(
                    settingKey: "emailOnComplete",
                    fileName: jobState.config.inputURL.lastPathComponent,
                    profile: jobState.config.profile.name,
                    duration: elapsed,
                    outputSize: outputSizeLabel,
                    success: true
                )

                sendWebhookNotification(
                    settingKey: "webhookOnComplete",
                    event: "encode_complete",
                    status: "success",
                    fileName: jobState.config.inputURL.lastPathComponent,
                    profile: jobState.config.profile.name,
                    durationSeconds: jobState.elapsedTime ?? 0,
                    outputSizeBytes: outputSizeBytes ?? 0
                )

                // Media server auto-scan (Issue #295 / #203). The setting's
                // own label is "Auto-scan after successful encode" (not
                // "at queue end"), so this fires per successful job here,
                // matching the wording exactly.
                if UserDefaults.standard.bool(forKey: "mediaServerAutoScan") {
                    triggerMediaServerAutoScan()
                }

                // Delete source file after successful encode, if enabled
                // (SettingsView.deleteSourceAfterEncode — previously
                // persisted but never read). Deliberately last in this
                // success block: every other completion action above has
                // already had its chance to read `jobState.config` before
                // anything gets deleted.
                if UserDefaults.standard.bool(forKey: "deleteSourceAfterEncode") {
                    deleteSourceFileIfSafe(job: jobState.config)
                }

            } catch {
                jobState.status = .failed
                jobState.errorMessage = error.localizedDescription
                jobState.completedAt = Date()

                // Persist failed-job statistics so the Dashboard success rate is real (Issue #284).
                statsCollector.markFailed()
                let failedStatistics = statsCollector.currentStatistics
                await Task.detached { EncodingStatisticsStore().addStatistics(failedStatistics) }.value

                // Track encode failure (Issue #183)
                analytics.track(.encodeFailed)

                appendLog(.error, "Failed: \(jobState.config.inputURL.lastPathComponent) — \(error.localizedDescription)",
                          category: .encoding, jobID: jobState.config.id)

                sendNotification(
                    title: "Encoding Failed",
                    body: "\(jobState.config.inputURL.lastPathComponent): \(error.localizedDescription)",
                    settingKey: "notifyOnFailure"
                )

                sendCompletionEmail(
                    settingKey: "emailOnFailure",
                    fileName: jobState.config.inputURL.lastPathComponent,
                    profile: jobState.config.profile.name,
                    duration: jobState.elapsedTime.map { formatDuration($0) } ?? "unknown",
                    outputSize: "—",
                    success: false,
                    errorMessage: error.localizedDescription
                )

                sendWebhookNotification(
                    settingKey: "webhookOnFailure",
                    event: "encode_failed",
                    status: "failure",
                    fileName: jobState.config.inputURL.lastPathComponent,
                    profile: jobState.config.profile.name,
                    durationSeconds: jobState.elapsedTime ?? 0,
                    outputSizeBytes: 0,
                    errorMessage: error.localizedDescription
                )
            }

            // Deactivate system-level progress indicators (Issue #182)
            activityIndicator.stopTracking()

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

        // Queue-finished email (Issue #348). `emailOnQueueFinished`
        // (EmailSettingsView's third trigger toggle, alongside
        // emailOnComplete/emailOnFailure which are already wired above)
        // had no reader. Reuses the same job-completion email template as
        // the per-job paths: there is no single "job" for a whole-queue
        // event, so the summary counts stand in for profile/size, and
        // `success` reflects whether any job actually failed rather than
        // always claiming success.
        sendCompletionEmail(
            settingKey: "emailOnQueueFinished",
            fileName: "Encoding Queue",
            profile: summary,
            duration: "—",
            outputSize: "—",
            success: engine.queue.failedCount == 0,
            errorMessage: engine.queue.failedCount > 0
                ? "\(engine.queue.failedCount) job(s) failed — see the Queue view for details."
                : nil
        )

        // Queue-finished webhook leg (Issue #296). There is no single
        // "job" for a whole-queue event, so `WebhookJobInfo.fileName`
        // carries the summary text and `status` reflects whether any job
        // failed, rather than always claiming success.
        sendWebhookNotification(
            settingKey: "webhookOnQueueFinished",
            event: "queue_complete",
            status: engine.queue.failedCount == 0 ? "success" : "failure",
            fileName: "Encoding Queue: \(summary)",
            profile: "-",
            durationSeconds: 0,
            outputSizeBytes: 0
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
        activityIndicator.stopTracking()
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

    // MARK: - Completion Email (Issue #348)

    /// Send a completion-email notification if the corresponding setting
    /// is enabled and a valid SMTP configuration exists.
    ///
    /// `emailOnComplete` / `emailOnFailure` (`EmailSettingsView`'s
    /// trigger toggles) previously had zero consumers — this is the
    /// wiring. Config loading and email/curl-argument construction happen
    /// here on the `@MainActor`; the blocking `curl` subprocess itself —
    /// the same transport already proven in
    /// `EmailSettingsView.sendTestEmail()` — runs in a `Task.detached`
    /// that captures only the prepared `Sendable` `String`/`[String]`
    /// values, never `self`. Best-effort: failures are silently dropped,
    /// matching `sendNotification`'s own fire-and-forget behaviour.
    private func sendCompletionEmail(
        settingKey: String,
        fileName: String,
        profile: String,
        duration: String,
        outputSize: String,
        success: Bool,
        errorMessage: String? = nil
    ) {
        guard UserDefaults.standard.bool(forKey: settingKey) else { return }
        guard let config = EmailSettingsView.loadSMTPConfig() else { return }

        let (subject, body) = EmailNotifier.formatJobCompletionEmail(
            fileName: fileName,
            profile: profile,
            duration: duration,
            outputSize: outputSize,
            success: success,
            errorMessage: errorMessage
        )
        let rawEmail = EmailNotifier.buildNotificationEmail(subject: subject, body: body, config: config)
        let curlArgs = EmailNotifier.sendViaProcess(email: rawEmail, config: config)

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = curlArgs

            let inputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                if let emailData = rawEmail.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(emailData)
                }
                inputPipe.fileHandleForWriting.closeFile()
                process.waitUntilExit()
            } catch {
                // Completion emails are a convenience, not load-bearing —
                // dropped silently here, same as `sendNotification` never
                // surfacing `UNUserNotificationCenter` errors.
            }
        }
    }

    // MARK: - Webhook Notifications (Issue #296)

    /// Send a webhook notification if the corresponding trigger event is
    /// enabled and a valid webhook configuration is persisted.
    ///
    /// `webhookOnComplete` / `webhookOnFailure` / `webhookOnQueueFinished`
    /// (`WebhookSettingsView`'s trigger toggles) previously had zero
    /// consumers — the only production `WebhookSender.send` call was the
    /// settings view's own Test button. This is the wiring, mirroring
    /// `sendCompletionEmail` immediately above: config loading happens
    /// here on the `@MainActor`, and the network request runs in an
    /// unstructured `Task { }` — not `Task.detached`, unlike the email
    /// path's blocking `curl` subprocess above, `WebhookSender.send` is
    /// already a non-blocking `async` `URLSession` call, so there's no
    /// thread to free up by detaching — so a slow or retrying webhook
    /// (`WebhookConfig.retryDelaySeconds`) never blocks the queue loop.
    /// Failures are logged, never thrown or surfaced as a job failure.
    private func sendWebhookNotification(
        settingKey: String,
        event: String,
        status: String,
        fileName: String,
        profile: String,
        durationSeconds: Double,
        outputSizeBytes: Int64,
        errorMessage: String? = nil
    ) {
        guard UserDefaults.standard.bool(forKey: settingKey) else { return }
        guard let config = WebhookSettingsView.loadWebhookConfig() else { return }

        let job = WebhookJobInfo(
            fileName: fileName,
            profile: profile,
            durationSeconds: durationSeconds,
            outputSizeBytes: outputSizeBytes
        )
        let payload = WebhookPayload.now(event: event, job: job, status: status, errorMessage: errorMessage)

        Task { [weak self] in
            do {
                try await WebhookSender.send(payload: payload, config: config)
            } catch {
                self?.appendLog(.warning, "Webhook delivery failed: \(error.localizedDescription)", category: .general)
            }
        }
    }

    // MARK: - Media Server Auto-Scan (Issue #295 / #203)

    /// Trigger a media-server library scan after a successful encode, if
    /// a usable server configuration is persisted.
    ///
    /// `mediaServerAutoScan` (`MediaServerSettingsView`'s toggle) had no
    /// reader — this is the wiring, called from the per-job success path
    /// in `startQueue()`. Fires the same
    /// `MediaServerIntegration.triggerLibraryScan` call the settings
    /// view's manual "Trigger Library Scan Now" button uses. Fire-and-
    /// forget in an unstructured `Task { }` (network call, non-blocking —
    /// same reasoning as `sendWebhookNotification` above): failures are
    /// logged, never surfaced as an error on the (already-succeeded)
    /// encoding job.
    private func triggerMediaServerAutoScan() {
        guard let config = MediaServerSettingsView.loadMediaServerConfig() else { return }

        Task { [weak self] in
            do {
                try await MediaServerIntegration.triggerLibraryScan(config: config)
                self?.appendLog(.info, "Media server library scan triggered.", category: .encoding)
            } catch {
                self?.appendLog(.warning, "Media server auto-scan failed: \(error.localizedDescription)", category: .encoding)
            }
        }
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

    /// The size, in bytes, of the file at `path`, or `nil` if it cannot be
    /// determined (missing file, unreadable attributes, etc.). Used by the
    /// queue runner's `EncodingStatisticsCollector` wiring (Issue #284) —
    /// `nil` is passed straight through rather than fabricating `0`, so an
    /// unreadable file size stays honestly absent from the stored stats.
    private func fileSizeInBytes(atPath path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        if let size = attributes[.size] as? Int64 {
            return size
        }
        if let size = attributes[.size] as? UInt64, size <= UInt64(Int64.max) {
            return Int64(size)
        }
        return nil
    }

    /// Delete the source file for a completed job, if — and only if — it
    /// is safe to do so (SettingsView.deleteSourceAfterEncode, Issue #7
    /// completeness audit).
    ///
    /// This is a data-destructive operation, so it is deliberately
    /// conservative:
    ///   - Only ever called from the `.completed` success path in
    ///     `startQueue()` — never on failure or cancellation (those hit
    ///     the `catch` block, which never calls this).
    ///   - The output file must exist and be non-empty, so a crashed or
    ///     truncated encode never takes the source down with it.
    ///   - Input and output paths must differ, in case an
    ///     `overwriteExisting` configuration ever made them identical.
    /// Deletion failures are logged, never thrown — this is best-effort
    /// clean-up, not something that should ever fail an already-completed
    /// job.
    ///
    /// - Parameter job: The completed job's configuration.
    private func deleteSourceFileIfSafe(job: EncodingJobConfig) {
        guard job.inputURL.path != job.outputURL.path else {
            appendLog(
                .warning,
                "Skipped deleting source: input and output paths are identical (\(job.inputURL.path))",
                category: .encoding, jobID: job.id
            )
            return
        }

        guard let outputSize = fileSizeInBytes(atPath: job.outputURL.path), outputSize > 0 else {
            appendLog(
                .warning,
                "Skipped deleting source: output file missing or empty at \(job.outputURL.path)",
                category: .encoding, jobID: job.id
            )
            return
        }

        do {
            try FileManager.default.removeItem(at: job.inputURL)
            appendLog(
                .info,
                "Deleted source file after successful encode: \(job.inputURL.lastPathComponent)",
                category: .encoding, jobID: job.id
            )
        } catch {
            appendLog(
                .warning,
                "Failed to delete source file \(job.inputURL.lastPathComponent): \(error.localizedDescription)",
                category: .encoding, jobID: job.id
            )
        }
    }

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
