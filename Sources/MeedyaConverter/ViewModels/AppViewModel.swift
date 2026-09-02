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

    /// Resumable jobs — interrupted (cancelled/failed) encodes that saved
    /// a checkpoint and can be re-queued. Honest-minimal: re-queuing
    /// restarts the job from 0%, it does not seek-resume mid-file.
    case resumableJobs = "Resumable Jobs"

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

    case stabilization = "Stabilization"

    /// Watermark overlay editor.
    case watermark = "Watermark"

    /// Multi-output encoding — one source to many outputs.
    case multiOutput = "Multi-Output"

    /// Conditional encoding rules — auto-select a profile based on
    /// source file properties. Phase 11 (Issue #276).
    case conditionalRules = "Conditional Rules"

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

    /// Features whose UI exists but whose engine-side execution is not yet
    /// wired: `RasterVectorConverter`/`ProResToVectorConverter` are
    /// argument-builders only, and the tracing tools they need (potrace /
    /// vtracer / rsvg-convert) are GPL and not yet bundled, with no process
    /// runner. Hidden from the sidebar and not selectable until that wiring
    /// lands, so a user can't open a settings-only form that can never convert
    /// (Issue #473). Re-list them here — nowhere else — to bring them back.
    static let unavailable: Set<NavigationItem> = [.vectorConversion, .proresVector]

    /// Whether this item is currently reachable (see `unavailable`).
    var isAvailable: Bool { !NavigationItem.unavailable.contains(self) }

    /// SF Symbol name for sidebar icon.
    var systemImage: String {
        switch self {
        case .source:            return "doc.badge.plus"
        case .mediaBrowser:      return "rectangle.stack.badge.play"
        case .streams:           return "list.bullet.rectangle"
        case .output:            return "gearshape.2"
        case .queue:             return "list.number"
        case .resumableJobs:     return "arrow.clockwise.circle"
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
        case .stabilization:     return "hand.raised.slash"
        case .watermark:         return "text.below.photo"
        case .multiOutput:       return "arrow.triangle.branch"
        case .conditionalRules:  return "switch.2"
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
        case .resumableJobs:     return "View interrupted jobs that can be re-queued"
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
        case .stabilization:     return "Stabilise shaky video (vid.stab)"
        case .watermark:         return "Add watermark overlay"
        case .multiOutput:       return "Encode to multiple outputs"
        case .conditionalRules:  return "Manage conditional encoding rules"
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
    ///
    /// Snaps back to `.source` if something selects a currently-unavailable
    /// item (Issue #473) — the sidebar already hides those, this guards the
    /// programmatic paths. Setting `.source` (which is available) re-enters
    /// `didSet` but makes no further change, so there is no recursion.
    var selectedNavItem: NavigationItem? = .source {
        didSet {
            if let item = selectedNavItem, !item.isAvailable {
                selectedNavItem = .source
            }
        }
    }

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

    /// A manually-computed Smart Crop filter string, set by
    /// `SmartCropView.applyCropToJob()` (Issue #474).
    ///
    /// Mirrors `detectedCrop` above but comes from the standalone Smart
    /// Crop tool rather than automatic source-file crop detection. When
    /// present, it takes precedence over `detectedCrop`/`autoCropEnabled`
    /// and is merged into `videoFilterChain` at enqueue exactly like the
    /// auto-crop path, then cleared so it does not silently keep applying
    /// to unrelated future jobs.
    var pendingManualCropFilter: String?

    /// A scene-detected FFmetadata chapters file staged by `SceneDetectorView`
    /// (Issue #288), consumed by the next `enqueueSelectedFile()` — which sets
    /// it on the job's `externalChaptersFile` so the chapters are embedded into
    /// the encode — then cleared so it does not silently attach to unrelated
    /// future jobs. Mirrors `pendingManualCropFilter`.
    var pendingChaptersFile: URL?

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

    // MARK: - Completion Serialisation (Issue #286)

    /// Serialises statistics writes across concurrently finishing jobs.
    ///
    /// `EncodingStatisticsStore` does a load-append-atomic-rewrite of one
    /// JSON file and its lock only guards a single instance, so two jobs
    /// completing together used to lose one of the two entries. Every write
    /// in `runJob(_:)` goes through this one actor instead.
    let statisticsRecorder = EncodingStatisticsRecorder()

    /// Serialises post-encode action chains across concurrently finishing
    /// jobs, so a user's shell scripts and uploads still run one at a time
    /// no matter how many encodes are in flight. The serialisation comes
    /// from the runner chaining executions, not from actor isolation —
    /// actors are reentrant and would not have provided it.
    let postEncodeHookRunner = PostEncodeHookRunner()

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

    // MARK: - ETA Prediction (Issue #470)

    /// History-weighted ETA predictor for the encoding queue. Persists
    /// completed-encode history to disk (Application Support) and is
    /// `@unchecked Sendable` with its own internal `NSLock`, so it is
    /// safe to call from anywhere — here it is only ever touched from
    /// this `@MainActor` view model, in `startQueue()`.
    let etaPredictor = ETAPredictor()

    // MARK: - Initialiser

    init() {
        // Custom FFmpeg/FFprobe binary paths (#475 —
        // `SettingsView.PathSettingsTab`'s "FFmpeg Path"/"FFprobe Path"
        // fields were persisted but never read). `EncodingEngine` already
        // threads these straight through to `FFmpegBundleManager`, which
        // tries the override before falling back to its bundled/Homebrew/
        // PATH search order (see `FFmpegBundleManager.locateFFmpeg()`) —
        // the only missing piece was passing them in here. An empty
        // string (the fields' unset default, shown as an "Auto-detect"
        // placeholder) means "no override", not a literal empty path.
        let customFFmpegPath = UserDefaults.standard.string(forKey: "customFFmpegPath")
        let customFFprobePath = UserDefaults.standard.string(forKey: "customFFprobePath")
        let engine = EncodingEngine(
            ffmpegPath: (customFFmpegPath?.isEmpty == false) ? customFFmpegPath : nil,
            ffprobePath: (customFFprobePath?.isEmpty == false) ? customFFprobePath : nil
        )
        self.engine = engine

        // Wire the AppleScript/JXA bridge to the live engine (#302). The
        // `.sdef` verbs dispatch through the NSScriptCommand subclasses in
        // ScriptingCommands.swift to `ScriptingBridge.shared`, which is inert
        // until these references are set — this is that "set during application
        // launch" step. Uses the local `engine` (not `self.engine`) so it does
        // not read `self` before two-phase init completes.
        ScriptingBridge.shared.engine = engine
        ScriptingBridge.shared.queue = engine.queue
        ScriptingBridge.shared.profileStore = engine.profileStore

        self.updateChecker = AppUpdateChecker()
        self.storeManager = StoreManager()

        // Default profile (#475 — `SettingsView.EncodingSettingsTab`'s
        // "Default Profile" picker was persisted but never read, so every
        // launch silently reset back to Web Standard). Read via
        // `UserDefaults` directly rather than `@AppStorage` since this is
        // a non-View init; resolved against the local `engine` (not
        // `self.engine`, per the two-phase-init note on `featureGate`
        // below) so a stale or unrecognised name never crashes — it just
        // falls back to Web Standard exactly like the old hardcoded default.
        if let storedProfileName = UserDefaults.standard.string(forKey: "defaultProfileName"),
           !storedProfileName.isEmpty,
           let resolvedProfile = engine.profileStore.profile(named: storedProfileName) {
            self.selectedProfile = resolvedProfile
        } else {
            self.selectedProfile = .webStandard
        }

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
        // happened to open Queue and press Start. The queue runner's
        // `claimNextPendingJob()` picks up newly-added jobs automatically
        // once it is running, so if the queue is already going we only need to
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

        // Observe the notification-action posts from NotificationActionHandler
        // (Issue #361). The handler is a UNUserNotificationCenter delegate that
        // decouples from this view model by posting NotificationCenter events;
        // nothing listened for them, so its Start Next / View Log / Retry
        // actions were inert. Wired here.
        setupNotificationActionObservers()
    }

    /// Wires the three decoupled notification-action posts to real behaviour
    /// (Issue #361). Registered on `.main` and hopped onto the main actor,
    /// since this type is `@MainActor`.
    private func setupNotificationActionObservers() {
        let centre = NotificationCenter.default

        centre.addObserver(forName: .notificationActionEncodeNext, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.appendLog(.info, "Notification action: starting the next queued job")
                Task { await self.startQueue() }
            }
        }

        centre.addObserver(forName: .notificationActionViewLog, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.selectedNavItem = .log
            }
        }

        centre.addObserver(forName: .notificationActionRetry, object: nil, queue: .main) { [weak self] note in
            let inputURL = note.userInfo?[NotificationActionHandler.inputPathKey] as? URL
            MainActor.assumeIsolated {
                guard let self, let inputURL else { return }
                self.appendLog(.info, "Notification action: retrying \(inputURL.lastPathComponent)")
                Task {
                    await self.importFiles([inputURL])
                    // Ensure the retried file is the selected one, then enqueue
                    // it — importFiles only auto-selects when nothing is chosen.
                    if let imported = self.sourceFiles.last(where: { $0.fileURL == inputURL }) {
                        self.selectedFile = imported
                    }
                    self.enqueueSelectedFile()
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
        //
        // Issue #275: `outputMode` (bound to the "Folder Structure"
        // picker in `OutputSettingsView`) previously had zero readers,
        // so "Mirror source folder structure" silently produced flat
        // output. `OutputPathResolver.resolveOutputDirectory` now picks
        // the actual destination *directory* according to `outputMode`
        // — composed with, not replacing, the `FilenameTemplate`-based
        // naming/overwrite logic below, which still owns the filename.
        // For `.flatten` (the default) and `.custom` (template-only;
        // see `OutputPathResolver`'s doc comment) it returns
        // `outputDir` unchanged, so behaviour for every mode except
        // `.mirror` is exactly what it was before this call existed.
        let outputDir = outputDirectory ?? FileManager.default.temporaryDirectory
        let resolvedOutputDir = OutputPathResolver.resolveOutputDirectory(
            inputURL: file.fileURL,
            baseInputDir: outputMode == .mirror ? commonSourceDirectory() : nil,
            outputDir: outputDir,
            mode: outputMode
        )

        // Apply conditional encoding rules (Issue #469): rules were
        // persisted by `ConditionalRulesView` (same "conditionalRules"
        // UserDefaults JSON blob, decoded identically here) but never
        // evaluated anywhere in the encode path. `RuleEngine.evaluateRules`
        // returns the `EncodingProfile` of the first enabled rule (in
        // priority order) whose conditions all match `file`, or `nil` if
        // none match. A match overrides the profile used for *this job
        // only* — `selectedProfile` itself (and the Output Settings picker
        // bound to it) is left untouched, so this cannot surprise the user
        // by silently changing their manual selection for the next file.
        // No rules persisted / none enabled / none matching all fall
        // through to `selectedProfile` unchanged, exactly as before this
        // feature existed.
        var effectiveProfile = selectedProfile
        if let rulesData = UserDefaults.standard.data(forKey: "conditionalRules"),
           let rules = try? JSONDecoder().decode([ConditionalRule].self, from: rulesData),
           !rules.isEmpty,
           let matchedProfile = RuleEngine.evaluateRules(
               rules, for: file, profileStore: engine.profileStore
           ) {
            effectiveProfile = matchedProfile
            appendLog(.info, "Conditional rule matched: using profile \"\(matchedProfile.name)\"", category: .encoding)
        }

        // Global hardware-acceleration kill switch (Issue #475).
        // `SettingsView.useHardwareAcceleration` (the "Prefer hardware
        // acceleration" toggle) was declared and rendered but had no
        // reader anywhere — flipping it changed nothing. Per-profile
        // hardware selection (`EncodingProfile.useHardwareEncoding`,
        // wired at `EncodingProfile.swift:303` into
        // `FFmpegArgumentBuilder`, with dedicated `hardwareH264`/
        // `hardwareH265` profiles) is real and already works, so this
        // setting is deliberately NOT made a duplicate of it. It is a
        // one-directional override: ON leaves the profile's own choice
        // untouched; OFF forces software encoding regardless of what the
        // profile wants. Applied *after* the conditional-rules block
        // above (Issue #469), so a rule cannot silently defeat a global
        // switch the user has turned off — that would be a worse lie
        // than the dead toggle it replaces. The decision itself lives in
        // `HardwareAccelerationPreference` so that every enqueue path in
        // the app applies it identically; honouring it here alone would
        // have left the setting false everywhere else.
        if HardwareAccelerationPreference.apply(to: &effectiveProfile) {
            appendLog(.info, "Hardware acceleration disabled globally — forcing software encoding for \"\(effectiveProfile.name)\"", category: .encoding)
        }

        let outputExtension = effectiveProfile.containerFormat.fileExtensions.first ?? "mkv"
        let templateString = UserDefaults.standard.string(forKey: "filenameTemplate") ?? "{title}_converted"
        let template = FilenameTemplate(template: templateString)
        let overwriteExisting = UserDefaults.standard.bool(forKey: "overwriteExisting")
        let outputURL = template.resolveOutputURL(
            sourceFile: file,
            profile: effectiveProfile,
            outputDirectory: resolvedOutputDir,
            fileExtension: outputExtension,
            overwriteExisting: overwriteExisting
        )

        // Apply a manually-selected Smart Crop filter (Issue #474) if one is
        // pending, otherwise fall back to auto-crop if enabled and a crop
        // was detected.
        var cropFilter: String? = nil
        if let manualCrop = pendingManualCropFilter {
            cropFilter = manualCrop
            appendLog(.info, "Smart Crop: applying manually selected crop (\(manualCrop))")
            pendingManualCropFilter = nil
        } else if autoCropEnabled, let crop = detectedCrop, crop.willCrop {
            cropFilter = crop.recommendedCrop.filterString
            appendLog(.info, "Auto-crop: \(crop.recommendedCrop.displayString) (\(String(format: "%.1f", crop.cropPercentage))% removed)")
        }

        var config = EncodingJobConfig(
            inputURL: file.fileURL,
            outputURL: outputURL,
            profile: effectiveProfile,
            videoStreamIndex: selectedVideoStreamIndex,
            audioStreamIndex: selectedAudioStreamIndex,
            subtitleStreamIndex: selectedSubtitleStreamIndex,
            mapAllStreams: mapAllStreams,
            streamMetadata: streamMetadataOverrides,
            videoFilterChain: cropFilter
        )
        // Feed the queue optimiser's duration-based strategies (#326). The
        // source was already probed on import, so `file.duration` is the real
        // media length; without this the shortest/longest/estimated-time
        // strategies had nothing to sort by and silently left the order
        // unchanged.
        config.estimatedSourceDuration = file.duration

        // Embed scene-detected chapters if one was staged (#288), then clear it
        // so it does not attach to a later, unrelated job.
        if let chapters = pendingChaptersFile {
            config.externalChaptersFile = chapters
            appendLog(.info, "Embedding chapters from \(chapters.lastPathComponent)", category: .encoding)
            pendingChaptersFile = nil
        }

        engine.queue.addJob(config)
        appendLog(.info, "Queued: \(file.fileName) with profile \"\(effectiveProfile.name)\"")

        // Switch to queue view
        selectedNavItem = .queue
    }

    /// Enqueue every enabled output of a multi-output configuration as its
    /// own full-fidelity queue job (Issue #335).
    ///
    /// `MultiOutputView` previously only *previewed* the FFmpeg arguments built
    /// by `MultiOutputEncoder` — nothing executed them, so "encode to multiple
    /// formats" produced no files. Rather than run those simplified,
    /// codec-and-CRF-only argument arrays (which ignore the profile's filters,
    /// HDR/tone-mapping, watermark, subtitles and metadata), this enqueues one
    /// ordinary `EncodingJobConfig` per enabled output through the real queue.
    /// Each output is therefore a full-fidelity encode with its own progress
    /// and success/failure status, and the bounded-concurrency runner (#286)
    /// can run them in parallel — satisfying the "independent progress per
    /// output" and "per-output success/failure" criteria without a bespoke
    /// sub-job model.
    ///
    /// The global hardware-acceleration kill switch (#475) is honoured per
    /// output, exactly as `enqueueSelectedFile()` does. Source-tab stream
    /// selection and conditional rules are deliberately NOT applied here: each
    /// output's profile is an explicit per-output choice in this view.
    ///
    /// Single-pass tee muxing (the shared-decode optimisation) is a separate,
    /// larger change to the job/backend model and is not done here; these are
    /// independent encodes.
    ///
    /// - Parameter config: The multi-output configuration.
    /// - Returns: The number of jobs enqueued (0 if nothing was enabled).
    @discardableResult
    func enqueueMultiOutput(_ config: MultiOutputConfig) -> Int {
        let enabled = config.outputs.filter(\.enabled)
        guard !enabled.isEmpty else { return 0 }

        for spec in enabled {
            var profile = spec.profile
            if HardwareAccelerationPreference.apply(to: &profile) {
                appendLog(.info, "Hardware acceleration disabled globally — forcing software encoding for \"\(profile.name)\"", category: .encoding)
            }
            let jobConfig = EncodingJobConfig(
                inputURL: config.sourceURL,
                outputURL: spec.outputURL,
                profile: profile
            )
            engine.queue.addJob(jobConfig)
        }

        appendLog(.info, "Multi-output: queued \(enabled.count) output\(enabled.count == 1 ? "" : "s") for \(config.sourceURL.lastPathComponent)")
        selectedNavItem = .queue
        return enabled.count
    }

    // MARK: - Encoding Pipelines (Issue #278)

    /// User-saved encoding pipelines, persisted as JSON in `UserDefaults`.
    /// Loaded once here in the property's default so it does not depend on
    /// `init`'s two-phase ordering. Built-in templates live on
    /// `EncodingPipeline.builtInTemplates` and are not stored here.
    var savedPipelines: [EncodingPipeline] = {
        guard let data = UserDefaults.standard.data(forKey: "savedPipelines"),
              let decoded = try? JSONDecoder().decode([EncodingPipeline].self, from: data)
        else { return [] }
        return decoded
    }()

    /// Persist (insert or replace by id) a pipeline from the editor. Wired to
    /// `PipelineEditorView`'s Save, whose `onSave` was previously nil — so a
    /// saved pipeline used to vanish on dismiss (#278).
    func savePipeline(_ pipeline: EncodingPipeline) {
        savedPipelines.removeAll { $0.id == pipeline.id }
        savedPipelines.append(pipeline)
        if let data = try? JSONEncoder().encode(savedPipelines) {
            UserDefaults.standard.set(data, forKey: "savedPipelines")
        }
        appendLog(.info, "Saved pipeline \"\(pipeline.name)\" (\(pipeline.steps.count) steps)")
    }

    /// Delete a saved pipeline by id.
    func deletePipeline(_ id: UUID) {
        savedPipelines.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(savedPipelines) {
            UserDefaults.standard.set(data, forKey: "savedPipelines")
        }
    }

    /// Run a pipeline against a source file via `EncodingPipelineExecutor`
    /// (Issue #278) — the wiring that makes the editor produce actual files
    /// instead of only previewing arguments. Step outputs land alongside the
    /// source; superseded intermediates are cleaned on success (honouring the
    /// pipeline's `cleanIntermediateFiles`). Progress and the final outcome are
    /// written to the app log, so the caller switches to the Log view.
    ///
    /// The `onProgress` callback is `@Sendable` and may resume off the main
    /// actor; each log write hops back via `Task { @MainActor in }`, the same
    /// pattern `startQueue()` uses around its progress callback. `self` is a
    /// `@MainActor` (hence `Sendable`) type, so capturing it is allowed.
    func runPipeline(_ pipeline: EncodingPipeline, sourceURL: URL) {
        let outputDir = sourceURL.deletingLastPathComponent().path
        selectedNavItem = .log
        appendLog(.info, "Pipeline \"\(pipeline.name)\" started on \(sourceURL.lastPathComponent)", category: .encoding)

        // Strong, Sendable (@MainActor) reference so the @Sendable onProgress
        // closure captures a `let`, not a re-weakened `self` — the latter trips
        // Swift's concurrent-capture check. The Task isn't retained, so this
        // strong ref is released when the run finishes.
        let vm = self
        Task {
            let executor = EncodingPipelineExecutor()
            do {
                let result = try await executor.execute(
                    pipeline: pipeline,
                    sourcePath: sourceURL.path,
                    outputDir: outputDir,
                    onProgress: { _, step in
                        Task { @MainActor in
                            vm.appendLog(
                                .info,
                                "Pipeline step \(step.stepNumber): \(step.step.name) — \(step.step.type.displayName)",
                                category: .encoding
                            )
                        }
                    }
                )
                await MainActor.run {
                    vm.appendLog(
                        .info,
                        "Pipeline \"\(pipeline.name)\" complete — \(result.deliverables.count) file(s) produced, \(result.cleanedIntermediates.count) intermediate(s) cleaned",
                        category: .encoding
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    vm.appendLog(.warning, "Pipeline \"\(pipeline.name)\" cancelled", category: .encoding)
                }
            } catch {
                await MainActor.run {
                    vm.appendLog(.error, "Pipeline \"\(pipeline.name)\" failed: \(error.localizedDescription)", category: .encoding)
                }
            }
        }
    }

    /// The deepest common ancestor directory across every currently
    /// imported source file, used as `OutputPathResolver`'s
    /// `baseInputDir` for `.mirror` mode (Issue #275).
    ///
    /// The app imports individual files one at a time (no folder-tree
    /// import, no stored "project root" — see `importFiles(_:)`), so
    /// there is no authoritative root to mirror against. The common
    /// ancestor of everything in `sourceFiles` is the closest available
    /// proxy: files picked from sibling subfolders (e.g.
    /// `.../ProjectA/clip1.mov`, `.../ProjectB/clip2.mov`) end up
    /// mirrored under `ProjectA/`, `ProjectB/` in the output directory —
    /// which is what "Mirror source folder structure" promises. When
    /// only one file is imported, its own parent directory IS the
    /// common ancestor, so `OutputPathResolver` computes an empty
    /// relative path and mirror mode is equivalent to flatten for that
    /// file — there is no sub-structure to preserve for a single file
    /// considered in isolation.
    ///
    /// - Returns: The common ancestor directory URL, or `nil` if no
    ///   source files are imported.
    private func commonSourceDirectory() -> URL? {
        let directories = sourceFiles.map { $0.fileURL.deletingLastPathComponent() }
        guard let first = directories.first else { return nil }
        guard directories.count > 1 else { return first }

        var commonComponents = first.pathComponents
        for directory in directories.dropFirst() {
            let components = directory.pathComponents
            var matched = 0
            while matched < commonComponents.count,
                  matched < components.count,
                  commonComponents[matched] == components[matched] {
                matched += 1
            }
            if matched < commonComponents.count {
                commonComponents.removeLast(commonComponents.count - matched)
            }
            if commonComponents.isEmpty { return nil }
        }

        var result = URL(fileURLWithPath: commonComponents[0])
        for component in commonComponents.dropFirst() {
            result.appendPathComponent(component)
        }
        return result
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
    func enqueueWatchFolderFile(_ url: URL, config: WatchFolderConfig) async {
        // Resolve the configured profile by name. `WatchFolderConfig`'s
        // own default (`profileName: "webStandard"`, set by `addNewConfig()`
        // in `WatchFolderView`) does not match any built-in profile's
        // display name ("Web Standard") under `profileStore.profile(named:)`'s
        // case-insensitive-exact match — so falling back to Web Standard
        // with a warning (rather than silently dropping the file) is the
        // common case, not just a defensive edge case.
        var profile: EncodingProfile
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

        // Conditional rules on the AUTOMATION path (#469 follow-up). The manual
        // enqueue evaluates the user's conditional-rule set against the probed
        // source; the watch-folder path — where per-file rules matter MOST,
        // since nobody is watching — did not, so a "if 4K, use the 4K profile"
        // rule silently never fired for auto-imported files. The rules match on
        // probed metadata (resolution/codec/HDR/duration/…), so we probe first.
        // A probe failure is not fatal: it just means rules cannot be evaluated,
        // so we proceed with the folder's configured profile rather than
        // dropping the file.
        var probedDuration: TimeInterval?
        if let rulesData = UserDefaults.standard.data(forKey: "conditionalRules"),
           let rules = try? JSONDecoder().decode([ConditionalRule].self, from: rulesData),
           !rules.isEmpty {
            do {
                let probed = try await engine.probe(url: url)
                probedDuration = probed.duration
                if let matched = RuleEngine.evaluateRules(
                    rules, for: probed, profileStore: engine.profileStore
                ) {
                    profile = matched
                    appendLog(
                        .info,
                        "Watch folder \"\(config.name)\": conditional rule matched — using profile \"\(matched.name)\".",
                        category: .encoding
                    )
                }
            } catch {
                appendLog(
                    .warning,
                    "Watch folder \"\(config.name)\": could not probe \(url.lastPathComponent) for conditional rules (\(error.localizedDescription)) — using \"\(profile.name)\".",
                    category: .encoding
                )
            }
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

        // Honour the global hardware-acceleration kill switch (#475) so
        // this path behaves like every other job the app enqueues.
        let effectiveProfile = HardwareAccelerationPreference.applying(to: profile)
        var jobConfig = EncodingJobConfig(inputURL: url, outputURL: outputURL, profile: effectiveProfile)
        // If we probed for rule evaluation, reuse the duration for the queue
        // optimiser (#326) rather than leaving it unknown.
        jobConfig.estimatedSourceDuration = probedDuration
        engine.queue.addJob(jobConfig)

        // Record the watch-folder association so `startQueue()`'s
        // completion handler can apply `config.postAction` once this
        // job finishes (Issue #277).
        watchFolderJobs[jobConfig.id] = config

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

    /// Maps the ID of an `EncodingJobConfig` that originated from a watch
    /// folder to the `WatchFolderConfig` that enqueued it (Issue #277).
    ///
    /// `EncodingJobConfig` itself carries no notion of "came from a watch
    /// folder" — it's a widely-shared model used by every enqueue path
    /// (`enqueueSelectedFile()`, multi-output, batch rename, etc.), so
    /// widening it for this one caller would be a much broader change
    /// than this fix needs. This side table is populated by
    /// `enqueueWatchFolderFile(_:config:)` and consulted (then cleared)
    /// by `startQueue()`'s completion handler, which needs the original
    /// `WatchFolderConfig.postAction` to know whether to move or delete
    /// the source file after a successful encode.
    private var watchFolderJobs: [UUID: WatchFolderConfig] = [:]

    // MARK: - Queue Processing

    /// Whether the queue is currently processing jobs sequentially.
    var isQueueRunning = false

    /// Every job currently in flight, in claim order (Issue #286).
    ///
    /// Maintained exclusively by `startQueue()`'s runner, on the
    /// `@MainActor`: appended on claim, pruned when a job leaves
    /// `.encoding`/`.paused`. Stored (not computed) so `@Observable`
    /// tracks it and the UI updates as slots fill and drain.
    ///
    /// With the default concurrency of 1 this holds at most one element,
    /// which is exactly what `activeJobState` used to be.
    var activeJobStates: [EncodingJobState] = []

    /// The first in-flight job, for UI that can only show one.
    ///
    /// Kept as a computed property so every existing reader
    /// (`TouchBarProvider`, `JobQueueView`) compiles and behaves unchanged.
    /// New code that must cover concurrent encodes should read
    /// `activeJobStates` instead.
    var activeJobState: EncodingJobState? { activeJobStates.first }

    /// Start processing the encoding queue.
    ///
    /// Claims queued jobs and runs them through `runJob(_:)`, keeping up to
    /// `currentConcurrencyWidth()` of them in flight at a time, until no
    /// queued jobs remain or the queue is stopped.
    ///
    /// That width defaults to **1**, which makes this a strictly sequential
    /// claim -> run -> await -> claim loop — the behaviour this method had
    /// before Issue #286, reproduced by construction rather than by
    /// promise. Values above 1 additionally require the `.parallelEncoding`
    /// entitlement.
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

        // ------------------------------------------------------------------
        // Bounded-concurrency runner (Issue #286)
        // ------------------------------------------------------------------
        // Replaces the former `while ... nextPendingJob()` loop. The width
        // is re-read on every top-up from `resolveConcurrency`, so dragging
        // the Max Concurrent Jobs slider takes effect as slots free up
        // without restarting the queue.
        //
        // At width 1 — the default, and what every unentitled install is
        // clamped to — the group holds at most one child task and the
        // sequence is claim -> run -> await -> claim: exactly the old loop,
        // with the same single registered controller, the same pause/cancel
        // target, and the same completion ordering.
        //
        // Queue-scoped concerns deliberately stay OUT of `runJob(_:)`: the
        // sleep-prevention activity token, the activity indicator's
        // lifecycle, `EncodingQueue.currentJob`, and the queue-finished
        // summary/notification/email/webhook below. Moving any of them into
        // the per-job body would fire them once per job.
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0

            while true {
                while isQueueRunning,
                      inFlight < currentConcurrencyWidth(),
                      let jobState = engine.queue.claimNextPendingJob() {
                    activeJobStates.append(jobState)
                    // One representative job for consumers that can only
                    // express a single "current" job (AppleScript's
                    // `queueStatus`, the Touch Bar). Re-pointed at another
                    // in-flight job as jobs finish; nil only when the queue
                    // drains.
                    engine.queue.currentJob = activeJobStates.first
                    if !activityIndicator.isTracking {
                        activityIndicator.beginQueueTracking(
                            fileName: jobState.config.inputURL.lastPathComponent
                        )
                    }
                    refreshAggregateActivityIndicator()

                    inFlight += 1
                    // `self` is an implicitly-`Sendable` `@MainActor` type
                    // and `runJob(_:)` is `@MainActor`, so this plain
                    // `@Sendable` child task hops straight back onto the
                    // main actor to run the job — no `nonisolated(unsafe)`
                    // and no unchecked conformance anywhere. (Spelling the
                    // closure `{ @MainActor in ... }` instead trips a
                    // region-based-isolation checker crash in this Swift.)
                    group.addTask {
                        await self.runJob(jobState)
                    }
                }

                if inFlight == 0 { break }

                await group.next()
                inFlight -= 1
                pruneFinishedActiveJobs()
            }
        }

        // The group has drained, so by definition nothing is in flight.
        // Clearing explicitly rather than relying on the last prune keeps a
        // job left `.paused` by `cancelCurrentJob()` from lingering in the
        // Queue view's progress maths after the queue has stopped.
        activeJobStates.removeAll()
        engine.queue.currentJob = nil

        // Deactivate system-level progress indicators (Issue #182). Queue
        // level, not job level: the first job to finish used to tear the
        // menu bar item and dock tile down while later jobs were still
        // encoding.
        activityIndicator.stopTracking()

        ProcessInfo.processInfo.endActivity(activity)
        isQueueRunning = false

        let summary = "\(engine.queue.completedCount) completed, \(engine.queue.failedCount) failed"
        appendLog(.info, "Queue finished — \(summary)")

        var queueUserInfo: [String: Any] = [:]
        if let dir = outputDirectory?.path {
            queueUserInfo[NotificationActionHandler.outputDirectoryKey] = dir
        }
        sendNotification(
            title: "Queue Finished",
            body: summary,
            settingKey: "notifyOnQueueFinished",
            // Only offer "Open Output Folder" when there is a folder to open.
            category: outputDirectory != nil ? NotificationActionHandler.queueCompleteCategory : nil,
            userInfo: queueUserInfo
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


    /// Encode one claimed job to completion, then run every per-job
    /// completion side effect for it (Issue #286).
    ///
    /// Extracted verbatim from `startQueue()`'s former `while` loop body so
    /// that several jobs can be in flight at once. Everything here is
    /// parameterised solely on `jobState` — it never reads
    /// `activeJobState`/`activeJobStates`, never touches
    /// `EncodingQueue.currentJob`, never starts or stops the activity
    /// indicator, and never begins or ends the sleep-prevention activity.
    /// Those are all queue-scoped and stay in `startQueue()`.
    ///
    /// ### Isolation
    /// Deliberately `@MainActor`, and it must stay that way. Every mutation
    /// it makes to view-model state — `watchFolderJobs`, the log buffer, the
    /// analytics engine, `etaPredictor` — is `@MainActor`-isolated with no
    /// other synchronisation, so completion handling running off the main
    /// actor would corrupt it. This costs nothing: the awaits inside
    /// (`engine.encode`, the statistics recorder) release the main actor for
    /// their entire duration, which is where all the time goes.
    ///
    /// The two genuinely shared side effects are serialised by actors rather
    /// than by the queue's old one-at-a-time shape:
    /// `statisticsRecorder.record(_:)` (load-append-rewrite of one JSON
    /// file) and `postEncodeHookRunner.run(...)` (the user's own scripts and
    /// uploads, which may not be reentrant).
    @MainActor
    private func runJob(_ jobState: EncodingJobState) async {
        // `status` was already flipped to `.encoding` by
        // `claimNextPendingJob()` — atomically, under the queue's lock,
        // so two slots cannot claim the same job (Issue #286).
        jobState.startedAt = Date()

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

                    // Periodic crash-safe checkpoint (#468). Previously a
                    // checkpoint was written only on failure/cancel, so a crash
                    // or force-quit MID-encode — the exact scenario resumable
                    // jobs exist for — left nothing to resume. Write one every
                    // ~5% of progress (throttled so it does not thrash the disk
                    // on every ffmpeg tick), off the main actor. Cleaned up on
                    // success below. `CheckpointManager` and `EncodingCheckpoint`
                    // are Sendable, so the detached write is race-free.
                    let fraction = progressInfo.fractionComplete ?? 0
                    if fraction - jobState.lastCheckpointFraction >= 0.05 {
                        jobState.lastCheckpointFraction = fraction
                        let checkpoint = EncodingCheckpoint(
                            jobId: jobState.config.id,
                            inputURL: jobState.config.inputURL,
                            outputURL: jobState.config.outputURL,
                            profileSnapshot: jobState.config.profile,
                            lastGoodTimestamp: progressInfo.currentTime
                                ?? (fraction * (jobState.lastKnownInputDuration ?? 0)),
                            progressFraction: fraction
                        )
                        Task.detached { try? CheckpointManager().saveCheckpoint(checkpoint) }
                    }

                    // Calculate ETA (Issue #470). Default to the naive
                    // linear extrapolation from observed progress
                    // (unchanged formula — this is also the fallback
                    // for a cold `ETAPredictor` with no matching
                    // history), then supersede it with
                    // `ETAPredictor.predictETA`'s history-weighted
                    // estimate whenever it has matching data for this
                    // codec/preset/resolution/hw-accel combination.
                    // `progressInfo.currentTime` and `fraction` are
                    // both derived by FFmpegProcessController from the
                    // same known source duration, so `currentTime /
                    // fraction` recovers that duration exactly —
                    // stashed on `jobState` so the completion branch
                    // below can feed it back into `recordEncode`.
                    if let fraction = progressInfo.fractionComplete, fraction > 0,
                       let startedAt = jobState.startedAt {
                        let elapsed = Date().timeIntervalSince(startedAt)
                        let totalEstimated = elapsed / fraction
                        jobState.eta = totalEstimated - elapsed

                        if let currentTime = progressInfo.currentTime, currentTime > 0 {
                            let inputDuration = currentTime / fraction
                            jobState.lastKnownInputDuration = inputDuration

                            if let prediction = self?.etaPredictor.predictETA(
                                codec: jobState.config.profile.videoCodec?.rawValue ?? "passthrough",
                                preset: jobState.config.profile.videoPreset ?? "default",
                                resolution: AppViewModel.etaResolutionLabel(for: jobState.config.profile),
                                inputDuration: inputDuration,
                                hwAccel: jobState.config.profile.useHardwareEncoding
                            ) {
                                jobState.eta = max(0, prediction.estimate - elapsed)
                            }
                        }
                    }

                    // Update system-level activity indicators (Issue
                    // #182). Aggregated across every in-flight job
                    // rather than pushed straight from this one
                    // (Issue #286): with two jobs encoding, each
                    // pushing its own fraction made the dock ring and
                    // menu bar flicker between them.
                    self?.refreshAggregateActivityIndicator()

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

            // A successfully-completed job leaves no resumable checkpoint —
            // remove any periodic ones written during the encode (#468).
            let completedJobID = jobState.config.id
            Task.detached { CheckpointManager().deleteCheckpoint(for: completedJobID) }
            jobState.status = .completed
            jobState.progress = 1.0
            jobState.completedAt = Date()

            let elapsed = jobState.elapsedTime.map { formatDuration($0) } ?? "unknown"
            appendLog(.info, "Completed: \(jobState.config.inputURL.lastPathComponent) in \(elapsed)",
                      category: .encoding, jobID: jobState.config.id)

            // Record this encode for ETAPredictor (Issue #470) so
            // future jobs with a similar codec/preset/resolution/
            // hw-accel combination get a history-weighted estimate
            // instead of only the naive in-job linear one.
            // `lastKnownInputDuration` is only set once a progress
            // tick reports a `currentTime`; a job that fails before
            // its first tick (or one FFmpeg reports no progress for)
            // simply isn't recorded, same as it wouldn't have had a
            // meaningful speed factor anyway.
            if let inputDuration = jobState.lastKnownInputDuration,
               let encodeDuration = jobState.elapsedTime, encodeDuration > 0 {
                etaPredictor.recordEncode(EncodeHistoryEntry(
                    codec: jobState.config.profile.videoCodec?.rawValue ?? "passthrough",
                    preset: jobState.config.profile.videoPreset ?? "default",
                    resolution: AppViewModel.etaResolutionLabel(for: jobState.config.profile),
                    inputDuration: inputDuration,
                    encodeDuration: encodeDuration,
                    hardwareAccelerated: jobState.config.profile.useHardwareEncoding
                ))
            }

            // Finalise and persist this job's statistics (Issue #284).
            // `EncodingStatisticsStore` reads/writes its JSON history
            // file synchronously in `init()`/`addStatistics(_:)`, so that
            // disk I/O must not block this `@MainActor`-isolated method.
            // It goes through `statisticsRecorder`, an actor: the await
            // releases the main actor for the write, and — the reason the
            // actor exists (Issue #286) — the load-append-rewrite is
            // serialised against any other job finishing at the same
            // moment, which a fresh store per write was not. Only the
            // `Sendable` `EncodingStatistics` snapshot crosses the
            // isolation boundary, never `self`/`jobState`.
            if let outputSize = fileSizeInBytes(atPath: jobState.config.outputURL.path) {
                statsCollector.setOutputFileSize(outputSize)
            }
            statsCollector.markComplete()
            let finalStatistics = statsCollector.currentStatistics
            await statisticsRecorder.record(finalStatistics)

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
                settingKey: "notifyOnCompletion",
                category: NotificationActionHandler.encodeCompleteCategory,
                userInfo: [NotificationActionHandler.outputPathKey: jobState.config.outputURL.path]
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

            // Post-encode action hooks (Issue #277). The chain engine
            // itself (`PostEncodeActionChain.execute`) is real —
            // scp/cloud/scripts/trash/notify all genuinely execute —
            // but `PostEncodeActionsView` previously only invoked it
            // from its own dry-run Test button, never from a real
            // job. Loaded fresh from `UserDefaults` on every
            // completion (mirrors `sendCompletionEmail`'s /
            // `sendWebhookNotification`'s own config-loading pattern
            // above), so an edit made mid-queue in Settings takes
            // effect starting with the very next job.
            let postEncodeChain = PostEncodeActionsView.loadPersistedChain()
            if postEncodeChain.actions.contains(where: \.isEnabled) {
                let inputURL = jobState.config.inputURL
                let outputURL = jobState.config.outputURL

                // `PostEncodeActionChain` is a plain `Sendable`
                // struct with no `@MainActor` state to race on (see
                // its own concurrency doc comment in
                // PostEncodeActions.swift), and `execute` already
                // hops to `@MainActor` itself internally only where
                // it must (`.openInFinder`/`.sendNotification`) —
                // everything else, including `.runShellScript`'s
                // blocking `Process.waitUntilExit()`, runs off the
                // main actor by design.
                //
                // Execution is routed through `postEncodeHookRunner`,
                // which chains each run behind the previous one so they
                // execute strictly one at a time even when several jobs
                // finish together (Issue #286). Note that being an actor
                // is NOT what provides that — actors are reentrant, so an
                // isolated method whose whole body is one `await` gives no
                // mutual exclusion at all. See the type's own doc comment.
                // The reason serialisation is wanted here: the
                // chain engine is reentrant-safe, but a user's own
                // shell scripts and uploads — written against a queue
                // that only ever ran one job — may not be. The task
                // captures only `Sendable` values (the runner, the
                // chain, the two `URL`s) and is deliberately never
                // awaited, so a slow hook delays later hooks but never
                // the encoding queue. Failures are silently dropped,
                // matching `sendCompletionEmail`'s own fire-and-forget
                // behaviour — never surfaced as a job failure, since
                // the encode itself already succeeded.
                Task { [postEncodeHookRunner] in
                    await postEncodeHookRunner.run(
                        chain: postEncodeChain,
                        inputURL: inputURL,
                        outputURL: outputURL,
                        success: true
                    )
                }
            }

            // Watch-folder post-action (Issue #277).
            // `WatchFolderConfig.postAction` (the move/delete-after-
            // encode picker in `WatchFolderView`) was persisted but
            // never read back. `watchFolderJobs` only has an entry
            // for jobs enqueued via `enqueueWatchFolderFile(_:config:)`
            // — every other job (manual enqueue, multi-output, etc.)
            // leaves this a no-op. `removeValue` both looks up and
            // clears the association so it never leaks.
            if let watchFolderConfig = watchFolderJobs.removeValue(forKey: jobState.config.id) {
                applyWatchFolderPostAction(watchFolderConfig, sourceURL: jobState.config.inputURL)
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

            // Clear any watch-folder association without applying its
            // `postAction` (Issue #277) — `PostProcessingAction` only
            // ever fires after a *successful* encode (see its own doc
            // comment); a failed job's source file should stay put
            // for the user to retry or inspect. Still removed here so
            // the side table never leaks an entry for a job that will
            // never reach the success path.
            watchFolderJobs.removeValue(forKey: jobState.config.id)

            // Persist failed-job statistics so the Dashboard success rate is real (Issue #284).
            statsCollector.markFailed()
            let failedStatistics = statsCollector.currentStatistics
            await statisticsRecorder.record(failedStatistics)

            // Save a resume checkpoint (honest-minimal resumable jobs)
            // so ResumableJobsView has real interrupted-job data to
            // list. NOTE this is "honest-minimal": there is no seek-
            // resume yet — ResumableJobsView.resumeCheckpoint(_:)
            // re-queues the job from scratch (0%), it does not resume
            // mid-file. `lastGoodTimestamp` is recorded here for a
            // future true seek-resume but isn't consumed by anything
            // yet. Best-effort like the other persistence above —
            // failures are silently dropped rather than surfaced as a
            // second error on top of the encode failure itself.
            let failureCheckpoint = EncodingCheckpoint(
                jobId: jobState.config.id,
                inputURL: jobState.config.inputURL,
                outputURL: jobState.config.outputURL,
                profileSnapshot: jobState.config.profile,
                lastGoodTimestamp: jobState.progress * (jobState.lastKnownInputDuration ?? 0),
                progressFraction: jobState.progress
            )
            try? CheckpointManager().saveCheckpoint(failureCheckpoint)

            // Track encode failure (Issue #183)
            analytics.track(.encodeFailed)

            appendLog(.error, "Failed: \(jobState.config.inputURL.lastPathComponent) — \(error.localizedDescription)",
                      category: .encoding, jobID: jobState.config.id)

            sendNotification(
                title: "Encoding Failed",
                body: "\(jobState.config.inputURL.lastPathComponent): \(error.localizedDescription)",
                settingKey: "notifyOnFailure",
                category: NotificationActionHandler.encodeFailedCategory,
                userInfo: [NotificationActionHandler.inputPathKey: jobState.config.inputURL.path]
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

            // Post-encode action hooks — failure path (Issue #277).
            // The success branch above already wires
            // `PostEncodeActionChain.execute` for successful jobs;
            // `PostEncodeAction.runOnFailure` exists specifically so
            // actions (failure notifications, cleanup scripts, etc.)
            // can also run when the job fails, but nothing ever
            // called `execute` on this path, so those actions were
            // dead. Mirrors the success branch exactly: the same
            // fresh-`UserDefaults` load via
            // `PostEncodeActionsView.loadPersistedChain()` (an edit
            // made mid-queue in Settings takes effect from the very
            // next job), the same enabled-actions guard,
            // `execute`'s own `isEnabled`/`runOnFailure` filtering
            // inside the chain, and the same fire-and-forget `Task`
            // through `postEncodeHookRunner` (which serialises by
            // chaining, not by actor isolation — see its doc comment)
            // with a `Sendable`-only capture list, for the reasons
            // documented on the success-branch call above. Failures are silently
            // dropped, same as there: a hook that itself throws must
            // never surface as a second, unrelated error on top of
            // the encode failure already being handled here. Only
            // `success: false` differs from the success-branch call,
            // which is what `execute` uses to skip any action that
            // lacks `runOnFailure`.
            let postEncodeFailureChain = PostEncodeActionsView.loadPersistedChain()
            if postEncodeFailureChain.actions.contains(where: \.isEnabled) {
                let inputURL = jobState.config.inputURL
                let outputURL = jobState.config.outputURL
                Task { [postEncodeHookRunner] in
                    await postEncodeHookRunner.run(
                        chain: postEncodeFailureChain,
                        inputURL: inputURL,
                        outputURL: outputURL,
                        success: false
                    )
                }
            }
        }
    }

    /// The number of jobs that may encode simultaneously right now
    /// (Issue #286).
    ///
    /// Re-read on every slot top-up, so the Max Concurrent Jobs slider
    /// applies mid-queue. Absent key, zero, or a negative value all mean 1
    /// — the sequential behaviour the queue had before this existed — and
    /// an install without the `.parallelEncoding` entitlement is clamped to
    /// 1 unconditionally. See `ParallelEncoder.resolveConcurrency`.
    private func currentConcurrencyWidth() -> Int {
        ParallelEncoder.resolveConcurrency(
            requested: UserDefaults.standard.integer(
                forKey: ParallelEncoder.maxConcurrentJobsDefaultsKey
            ),
            entitled: FeatureGateManager.shared.isEntitled(to: .parallelEncoding)
        )
    }

    /// Drop finished jobs from `activeJobStates` and re-point
    /// `EncodingQueue.currentJob` at a job that is still running.
    private func pruneFinishedActiveJobs() {
        activeJobStates.removeAll { $0.status != .encoding && $0.status != .paused }
        engine.queue.currentJob = activeJobStates.first
        refreshAggregateActivityIndicator()
    }

    /// Push a single aggregate progress reading to the menu bar and dock
    /// indicators, covering every job currently in flight (Issue #286).
    ///
    /// `EncodingActivityIndicator` is one per-app indicator; there is no
    /// honest way to show N jobs in one ring, so it shows the mean of their
    /// fractions, the summed speed (throughput really is additive), and
    /// either the single file's name or a "N files" count. With one job in
    /// flight this is identical to the old per-job push.
    func refreshAggregateActivityIndicator() {
        let active = activeJobStates
        guard !active.isEmpty else { return }

        let meanProgress = active.reduce(0.0) { $0 + $1.progress } / Double(active.count)
        let speeds = active.compactMap(\.speed)
        let combinedSpeed = speeds.isEmpty ? nil : speeds.reduce(0, +)
        let label = active.count == 1
            ? active[0].config.inputURL.lastPathComponent
            : "\(active.count) files"

        // ETA: the queue is not done until its slowest in-flight job is, so
        // the longest remaining time is the honest figure to show. Bitrate:
        // summed, because that is the combined write rate the user's disk
        // actually sees. With one job — the default width — both reduce to
        // that job's own values, which is exactly what the popover showed
        // before the runner took over driving this indicator.
        let longestETA = active.compactMap(\.eta).max()
        let bitrates = active.compactMap(\.currentBitrate)
        let combinedBitrate = bitrates.isEmpty ? nil : bitrates.reduce(0, +)

        activityIndicator.updateProgress(
            fraction: meanProgress,
            speed: combinedSpeed,
            fileName: label,
            eta: longestETA,
            bitrate: combinedBitrate
        )
    }

    /// Stop claiming new jobs; the queue drains once the jobs already in
    /// flight finish.
    func stopQueue() {
        isQueueRunning = false
        appendLog(.info, "Queue stopping after current job")
    }

    /// Pause every job currently encoding.
    ///
    /// Explicitly queue-wide (Issue #286). "The current job" stopped being
    /// well-defined once more than one job could be in flight, so rather
    /// than pausing an arbitrary one, `engine.pauseEncoding()` signals every
    /// registered FFmpeg process and every in-flight job state is marked
    /// `.paused`. With the default concurrency of 1 this is identical to
    /// the previous single-job behaviour, which is why `JobQueueView` and
    /// `TouchBarProvider` still call it unchanged.
    func pauseCurrentJob() {
        engine.pauseEncoding()
        for jobState in activeJobStates where jobState.status == .encoding {
            jobState.status = .paused
        }
        appendLog(.info, "Encoding paused")
    }

    /// Resume every paused job. Queue-wide, mirroring `pauseCurrentJob()`.
    func resumeCurrentJob() {
        engine.resumeEncoding()
        for jobState in activeJobStates where jobState.status == .paused {
            jobState.status = .encoding
        }
        appendLog(.info, "Encoding resumed")
    }

    /// Cancel every job currently encoding and stop the queue.
    ///
    /// Queue-wide (Issue #286): every registered FFmpeg process is stopped,
    /// every in-flight job is marked `.cancelled`, and a resume checkpoint
    /// is written for each one — previously only a single checkpoint was
    /// written while `engine.stopEncoding()` could kill a different job
    /// than the one being marked.
    func cancelCurrentJob() {
        engine.stopEncoding()

        // Snapshot first: `runJob(_:)`'s catch block will start finishing
        // these jobs as their `encode()` calls throw, and the runner prunes
        // them out of `activeJobStates` as it observes them finish.
        let cancelled = activeJobStates

        for jobState in cancelled {
            jobState.status = .cancelled
            jobState.completedAt = Date()
        }

        activityIndicator.stopTracking()
        isQueueRunning = false
        appendLog(.warning, "Encoding cancelled")

        // Save a resume checkpoint per cancelled job (honest-minimal
        // resumable jobs) — see the matching save in `runJob(_:)`'s failure
        // branch for the "re-queues from 0, does not seek-resume" caveat.
        // That catch block may also fire once `engine.stopEncoding()` makes
        // the in-flight `encode()` throw — that's fine, it just overwrites
        // the same per-job checkpoint file with an equivalent snapshot.
        for jobState in cancelled {
            let cancelCheckpoint = EncodingCheckpoint(
                jobId: jobState.config.id,
                inputURL: jobState.config.inputURL,
                outputURL: jobState.config.outputURL,
                profileSnapshot: jobState.config.profile,
                lastGoodTimestamp: jobState.progress * (jobState.lastKnownInputDuration ?? 0),
                progressFraction: jobState.progress
            )
            try? CheckpointManager().saveCheckpoint(cancelCheckpoint)
        }
    }

    // MARK: - Notifications

    /// Send a macOS notification if the corresponding setting is enabled.
    private func sendNotification(
        title: String,
        body: String,
        settingKey: String,
        category: String? = nil,
        userInfo: [String: Any] = [:]
    ) {
        let enabled = UserDefaults.standard.bool(forKey: settingKey)
        // Default to true if key hasn't been set
        let isEnabled = UserDefaults.standard.object(forKey: settingKey) == nil ? true : enabled

        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UserDefaults.standard.bool(forKey: "playSoundOnCompletion")
            ? .default : nil
        // Stamp the category (Issue #361) so the registered action buttons
        // (Open in Finder / Start Next, View Log / Retry, Open Output Folder)
        // appear, and carry the paths those actions operate on. Without this
        // the notifications were plain banners and NotificationActionHandler —
        // a complete delegate — had nothing to route.
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo

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

        Task { @MainActor [weak self] in
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

        Task { @MainActor [weak self] in
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

    /// Apply a watch folder's configured `postAction` to a source file
    /// after its encode completes successfully (Issue #277).
    ///
    /// `WatchFolderConfig.postAction` (`WatchFolderView`'s picker) was
    /// persisted but had no reader — this is the wiring, called from
    /// `startQueue()`'s success path only, for jobs `watchFolderJobs`
    /// identifies as having come from a watch folder. Best-effort: a
    /// failure is logged, never thrown — the encode itself already
    /// succeeded, so a clean-up failure shouldn't retroactively mark it
    /// otherwise.
    ///
    /// - Parameters:
    ///   - config: The watch folder configuration that produced this job.
    ///   - sourceURL: The source file to move, delete, or leave in place.
    private func applyWatchFolderPostAction(_ config: WatchFolderConfig, sourceURL: URL) {
        switch config.postAction {
        case .leaveInPlace:
            break

        case .deleteSource:
            do {
                try FileManager.default.removeItem(at: sourceURL)
                appendLog(
                    .info,
                    "Watch folder \"\(config.name)\": deleted source \(sourceURL.lastPathComponent) after encode.",
                    category: .encoding
                )
            } catch {
                appendLog(
                    .warning,
                    "Watch folder \"\(config.name)\": failed to delete source \(sourceURL.lastPathComponent) — \(error.localizedDescription)",
                    category: .encoding
                )
            }

        case .moveToCompleted:
            // Sibling to the `output` subfolder `effectiveOutputPath`
            // defaults to when `outputPath` isn't set — "a completed
            // subfolder" per `PostProcessingAction.moveToCompleted`'s
            // own doc comment, so it lives under the watched directory
            // itself rather than under the (possibly quite different)
            // output directory.
            let completedDir = URL(fileURLWithPath: config.watchPath).appendingPathComponent("completed")
            let destination = completedDir.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: completedDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: sourceURL, to: destination)
                appendLog(
                    .info,
                    "Watch folder \"\(config.name)\": moved source \(sourceURL.lastPathComponent) to completed/.",
                    category: .encoding
                )
            } catch {
                appendLog(
                    .warning,
                    "Watch folder \"\(config.name)\": failed to move source \(sourceURL.lastPathComponent) to completed/ — \(error.localizedDescription)",
                    category: .encoding
                )
            }
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

    /// Formats a profile's output resolution as an `ETAPredictor` matching
    /// key (e.g. "1920x1080") — Issue #470. Falls back to "source" when
    /// the profile doesn't override resolution (`outputWidth`/
    /// `outputHeight` nil means "match source"). This label only needs to
    /// be *consistent* between the `recordEncode` and `predictETA` call
    /// sites in `startQueue()`, not pixel-exact, since it is just one of
    /// several fields `ETAPredictor` matches history entries on.
    ///
    /// `static` (rather than an instance method) so it can be called from
    /// inside the `[weak self]` progress closure in `startQueue()` without
    /// needing a second, separate `self` unwrap.
    private static func etaResolutionLabel(for profile: EncodingProfile) -> String {
        guard let width = profile.outputWidth, let height = profile.outputHeight else {
            return "source"
        }
        return "\(width)x\(height)"
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
