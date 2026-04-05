// ============================================================================
// MeedyaConverter — EncodingScheduler
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ScheduledJob

/// A scheduled encoding job that fires at a specified time, optionally repeating.
///
/// Scheduled jobs are persisted to a JSON file in the application's
/// `Application Support` directory so they survive app restarts.
public struct ScheduledJob: Identifiable, Codable, Sendable {

    // MARK: - Properties

    /// Unique identifier for this scheduled job.
    public let id: UUID

    /// The date and time at which this job should start encoding.
    public var scheduledTime: Date

    /// Optional repeat interval in seconds.
    ///
    /// Common values:
    /// - `nil` — one-time job (no repeat).
    /// - `86_400` — daily.
    /// - `604_800` — weekly.
    public var repeatInterval: TimeInterval?

    /// The encoding job configuration to execute when the scheduled time arrives.
    public var jobConfig: EncodingJobConfig

    /// Whether this scheduled job is active. Disabled jobs remain in the list
    /// but do not fire until re-enabled.
    public var isEnabled: Bool

    // MARK: - Initialiser

    /// Create a new scheduled job.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - scheduledTime: When the job should fire.
    ///   - repeatInterval: Optional repeat interval in seconds (nil = one-time).
    ///   - jobConfig: The encoding job configuration.
    ///   - isEnabled: Whether the job is active.
    public init(
        id: UUID = UUID(),
        scheduledTime: Date,
        repeatInterval: TimeInterval? = nil,
        jobConfig: EncodingJobConfig,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.scheduledTime = scheduledTime
        self.repeatInterval = repeatInterval
        self.jobConfig = jobConfig
        self.isEnabled = isEnabled
    }
}

// MARK: - RepeatInterval

/// Well-known repeat intervals for the schedule picker UI.
public enum RepeatInterval: String, CaseIterable, Sendable {

    /// No repeat — the job fires once and is removed.
    case never = "Never"

    /// Repeat every 24 hours.
    case daily = "Daily"

    /// Repeat every 7 days.
    case weekly = "Weekly"

    /// The interval in seconds, or `nil` for one-time jobs.
    public var timeInterval: TimeInterval? {
        switch self {
        case .never:  return nil
        case .daily:  return 86_400
        case .weekly: return 604_800
        }
    }

    /// Create from a raw `TimeInterval?` value.
    public init(from interval: TimeInterval?) {
        switch interval {
        case 86_400:  self = .daily
        case 604_800: self = .weekly
        default:      self = .never
        }
    }
}

// MARK: - EncodingScheduler

/// Manages scheduled encoding jobs, firing callbacks when a job's
/// scheduled time arrives.
///
/// The scheduler persists its job list to a JSON file in the app's
/// `Application Support` directory. It uses `DispatchSourceTimer` for
/// precise wake-up scheduling and calls `ProcessInfo.beginActivity()`
/// to prevent the system from sleeping while a schedule is pending.
///
/// ## Thread Safety
/// This class is `@unchecked Sendable` and uses `NSLock` internally
/// for thread-safe access to mutable state.
public final class EncodingScheduler: @unchecked Sendable {

    // MARK: - Properties

    /// Callback invoked on the main queue when a scheduled job's time arrives.
    /// The caller should enqueue the job config into the encoding engine.
    public var onJobReady: ((EncodingJobConfig) -> Void)?

    /// The list of currently scheduled jobs (read-only snapshot).
    public var scheduledJobs: [ScheduledJob] {
        lock.lock()
        defer { lock.unlock() }
        return Array(jobs.values)
            .sorted { $0.scheduledTime < $1.scheduledTime }
    }

    // MARK: - Private State

    /// All scheduled jobs keyed by ID.
    private var jobs: [UUID: ScheduledJob] = [:]

    /// Active timers keyed by job ID.
    private var timers: [UUID: DispatchSourceTimer] = [:]

    /// System activity token to prevent sleep while schedules are pending.
    private var activityToken: NSObjectProtocol?

    /// Lock for thread-safe access to mutable state.
    private let lock = NSLock()

    /// File manager for persistence operations.
    private let fileManager = FileManager.default

    /// The dispatch queue on which timers fire.
    private let timerQueue = DispatchQueue(
        label: "com.mwbmpartners.meedyaconverter.scheduler",
        qos: .utility
    )

    // MARK: - Persistence Path

    /// The URL of the JSON file where scheduled jobs are persisted.
    private var persistenceURL: URL {
        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("MeedyaConverter", isDirectory: true)

        // Ensure the directory exists
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)

        return appSupport.appendingPathComponent("scheduled_jobs.json")
    }

    // MARK: - Initialiser

    /// Create a new encoding scheduler and load any persisted jobs.
    public init() {
        loadFromDisk()
        startAllTimers()
        updateActivityAssertion()
    }

    // MARK: - Public API

    /// Schedule a new job or update an existing one.
    ///
    /// - Parameter job: The scheduled job to add or update.
    public func schedule(_ job: ScheduledJob) {
        lock.lock()
        // Cancel any existing timer for this job
        cancelTimer(for: job.id)
        jobs[job.id] = job
        lock.unlock()

        if job.isEnabled {
            startTimer(for: job)
        }

        saveToDisk()
        updateActivityAssertion()
    }

    /// Cancel and remove a scheduled job.
    ///
    /// - Parameter id: The unique identifier of the job to cancel.
    public func cancelSchedule(id: UUID) {
        lock.lock()
        cancelTimer(for: id)
        jobs.removeValue(forKey: id)
        lock.unlock()

        saveToDisk()
        updateActivityAssertion()
    }

    /// Return a sorted list of all scheduled jobs.
    ///
    /// - Returns: Array of ``ScheduledJob`` sorted by scheduled time (earliest first).
    public func listScheduled() -> [ScheduledJob] {
        return scheduledJobs
    }

    /// Toggle the enabled state of a scheduled job.
    ///
    /// - Parameters:
    ///   - id: The job to toggle.
    ///   - enabled: The new enabled state.
    public func setEnabled(id: UUID, enabled: Bool) {
        lock.lock()
        guard var job = jobs[id] else {
            lock.unlock()
            return
        }
        job.isEnabled = enabled
        jobs[id] = job

        if enabled {
            lock.unlock()
            startTimer(for: job)
        } else {
            cancelTimer(for: id)
            lock.unlock()
        }

        saveToDisk()
        updateActivityAssertion()
    }

    // MARK: - Timer Management

    /// Start a dispatch timer for a specific job.
    private func startTimer(for job: ScheduledJob) {
        let now = Date()
        let fireDate = job.scheduledTime

        // If the scheduled time is in the past and this is a one-time job, fire immediately
        let delay: TimeInterval
        if fireDate <= now {
            delay = 0
        } else {
            delay = fireDate.timeIntervalSince(now)
        }

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.jobFired(id: job.id)
        }

        lock.lock()
        timers[job.id] = timer
        lock.unlock()

        timer.resume()
    }

    /// Cancel a timer for a specific job (caller must hold the lock or call within locked context).
    private func cancelTimer(for id: UUID) {
        if let timer = timers.removeValue(forKey: id) {
            timer.cancel()
        }
    }

    /// Start timers for all enabled jobs (used after loading from disk).
    private func startAllTimers() {
        lock.lock()
        let enabledJobs = jobs.values.filter { $0.isEnabled }
        lock.unlock()

        for job in enabledJobs {
            startTimer(for: job)
        }
    }

    /// Called when a scheduled job's timer fires.
    private func jobFired(id: UUID) {
        lock.lock()
        guard let job = jobs[id] else {
            lock.unlock()
            return
        }

        if let repeatInterval = job.repeatInterval {
            // Reschedule for the next occurrence
            var nextJob = job
            nextJob.scheduledTime = job.scheduledTime.addingTimeInterval(repeatInterval)
            // If the next time is still in the past, advance to the future
            while nextJob.scheduledTime <= Date() {
                nextJob.scheduledTime = nextJob.scheduledTime.addingTimeInterval(repeatInterval)
            }
            jobs[id] = nextJob
            lock.unlock()

            startTimer(for: nextJob)
            saveToDisk()
        } else {
            // One-time job: remove it
            cancelTimer(for: id)
            jobs.removeValue(forKey: id)
            lock.unlock()

            saveToDisk()
            updateActivityAssertion()
        }

        // Fire the callback on the main queue
        let config = job.jobConfig
        DispatchQueue.main.async { [weak self] in
            self?.onJobReady?(config)
        }
    }

    // MARK: - Power Management

    /// Maintain a system activity assertion while any schedules are pending.
    ///
    /// This prevents the system from entering aggressive sleep when the user
    /// has jobs scheduled to run unattended.
    private func updateActivityAssertion() {
        lock.lock()
        let hasEnabledJobs = jobs.values.contains { $0.isEnabled }
        lock.unlock()

        if hasEnabledJobs && activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "MeedyaConverter has scheduled encoding jobs pending."
            )
        } else if !hasEnabledJobs, let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    // MARK: - Persistence

    /// Save the current job list to disk as JSON.
    private func saveToDisk() {
        lock.lock()
        let allJobs = Array(jobs.values)
        lock.unlock()

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(allJobs)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // Persistence failure is non-fatal; log but do not crash.
            #if DEBUG
            print("[EncodingScheduler] Failed to save scheduled jobs: \(error)")
            #endif
        }
    }

    /// Load scheduled jobs from disk.
    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: persistenceURL.path) else { return }

        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedJobs = try decoder.decode([ScheduledJob].self, from: data)

            lock.lock()
            jobs = Dictionary(uniqueKeysWithValues: loadedJobs.map { ($0.id, $0) })
            lock.unlock()
        } catch {
            #if DEBUG
            print("[EncodingScheduler] Failed to load scheduled jobs: \(error)")
            #endif
        }
    }
}
