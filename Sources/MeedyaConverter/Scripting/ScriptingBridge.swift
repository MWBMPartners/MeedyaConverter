// ============================================================================
// MeedyaConverter — ScriptingBridge (AppleScript / JXA Scripting Dictionary)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides AppleScript and JavaScript for Automation (JXA) support for
// MeedyaConverter. This class exposes core functionality via an Objective-C
// compatible interface that macOS's Open Scripting Architecture (OSA) can
// invoke through the application's scripting dictionary (.sdef file).
//
// Supported AppleScript commands:
//   - `encode file <path> using profile <name> to <output>`
//   - `probe file <path>`
//   - `list profiles`
//   - `queue status`
//   - `version`
//
// The accompanying MeedyaConverter.sdef file defines the scripting
// dictionary that maps AppleScript verbs to the @objc methods below.
//
// Phase 11 / Issue #302
// ---------------------------------------------------------------------------

import AppKit
import Foundation
import ConverterEngine

// MARK: - ScriptingBridge

/// Bridges AppleScript / JXA scripting commands to ConverterEngine.
///
/// This class is registered as the application's scripting handler via the
/// `NSApplication.shared.delegate` chain and the `.sdef` scripting dictionary.
/// All methods are `@objc` so OSA can dispatch to them via Objective-C messaging.
///
/// ### Thread Safety
/// All methods are `@MainActor` because scripting commands arrive on the main
/// thread through the NSApplication event loop. Encoding operations that must
/// run asynchronously are dispatched via `Task` and return a job ID immediately.
///
/// ### Usage from AppleScript
/// ```applescript
/// tell application "MeedyaConverter"
///     set jobID to encode "/Users/me/video.mov" using profile "Web Standard" to "/Users/me/output.mp4"
///     set info to probe "/Users/me/video.mov"
///     set profiles to list profiles
/// end tell
/// ```
///
/// ### Usage from JXA (JavaScript for Automation)
/// ```javascript
/// const app = Application("MeedyaConverter");
/// const jobID = app.encode("/Users/me/video.mov", {
///     usingProfile: "Web Standard",
///     to: "/Users/me/output.mp4"
/// });
/// const info = app.probe("/Users/me/video.mov");
/// ```
@MainActor
final class ScriptingBridge: NSObject {

    // MARK: - Properties

    /// Shared singleton instance for scripting dispatch.
    ///
    /// The application delegate or app initialisation code should set this
    /// up and wire it into the NSApplication scripting infrastructure.
    static let shared = ScriptingBridge()

    /// Reference to the encoding engine used for probing and encoding.
    ///
    /// Set during application launch once the engine is configured.
    /// When nil, scripting commands return an error string.
    var engine: EncodingEngine?

    /// Reference to the encoding queue for status queries.
    ///
    /// Set during application launch to the same queue used by the GUI.
    var queue: EncodingQueue?

    /// Reference to the profile store for listing available profiles.
    ///
    /// Set during application launch to the engine's profile store.
    var profileStore: EncodingProfileStore?

    // MARK: - Scripting Commands

    /// Start an encoding job and return its unique job identifier.
    ///
    /// This method returns immediately with a UUID string. The encoding
    /// runs asynchronously in the background. Use `queueStatus()` to
    /// monitor progress.
    ///
    /// - Parameters:
    ///   - file: Absolute POSIX path to the input media file.
    ///   - profile: Name of the encoding profile to use (e.g. "Web Standard").
    ///   - output: Absolute POSIX path for the encoded output file.
    /// - Returns: A UUID string identifying the queued job, or an error
    ///   message prefixed with "ERROR:" if the request cannot be fulfilled.
    @objc func encode(file: String, profile: String, output: String) -> String {
        guard let engine = engine else {
            return "ERROR: Encoding engine is not configured."
        }

        guard let profileStore = profileStore else {
            return "ERROR: Profile store is not available."
        }

        // Validate input file exists
        let inputURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            return "ERROR: Input file not found: \(file)"
        }

        // Look up the encoding profile by name
        guard let encodingProfile = profileStore.profile(named: profile) else {
            let available = profileStore.profiles.map(\.name).joined(separator: ", ")
            return "ERROR: Profile '\(profile)' not found. Available: \(available)"
        }

        // Build the job configuration
        let outputURL = URL(fileURLWithPath: output)
        let jobConfig = EncodingJobConfig(
            id: UUID(),
            inputURL: inputURL,
            outputURL: outputURL,
            profile: encodingProfile
        )

        // Add to the queue — encoding will start when the queue processes it
        let jobState = engine.queue.addJob(jobConfig)

        // Start processing the queue if not already running
        Task {
            try? await engine.encode(job: jobConfig)
        }

        return jobState.config.id.uuidString
    }

    /// Probe a media file and return its metadata as a JSON string.
    ///
    /// Uses FFprobe (via ConverterEngine) to analyse the file's streams,
    /// format, duration, codecs, and other technical metadata.
    ///
    /// - Parameter file: Absolute POSIX path to the media file.
    /// - Returns: A JSON string containing the file's media information,
    ///   or an error message prefixed with "ERROR:" if probing fails.
    @objc func probe(file: String) -> String {
        guard let engine = engine else {
            return "ERROR: Encoding engine is not configured."
        }

        let fileURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return "ERROR: File not found: \(file)"
        }

        // Probing is async but AppleScript expects a synchronous return.
        // We use FFmpegProbe directly via a synchronous Process invocation
        // on a background queue, bridging back with a semaphore. The
        // FFmpegProbe type is Sendable, so it can safely cross isolation.
        guard let ffprobePath = engine.ffprobeInfo?.path else {
            return "ERROR: FFprobe not configured. Call configure() first."
        }

        // Run the probe synchronously using Process (FFmpegProbe.analyzeSync).
        // Since FFmpegProbe's analyze(url:) is async, we invoke it from a
        // detached context and collect the result via a thread-safe box.
        nonisolated(unsafe) var probeResult = "ERROR: Probe did not complete."
        let prober = FFmpegProbe(ffprobePath: ffprobePath)
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            do {
                let mediaFile = try await prober.analyze(url: fileURL)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(mediaFile)
                probeResult = String(data: data, encoding: .utf8)
                    ?? "ERROR: Failed to encode JSON."
            } catch {
                probeResult = "ERROR: Probe failed — \(error.localizedDescription)"
            }
            semaphore.signal()
        }

        // Wait with a generous timeout (media probing can take a few seconds
        // for large files on slow storage). Note: this blocks the main thread,
        // which is acceptable for AppleScript's synchronous calling convention.
        let timeout = semaphore.wait(timeout: .now() + 60)
        if timeout == .timedOut {
            return "ERROR: Probe timed out after 60 seconds."
        }

        return probeResult
    }

    /// Return a list of all available encoding profile names.
    ///
    /// - Returns: An array of profile name strings, suitable for
    ///   presentation in an AppleScript `choose from list` dialog.
    @objc func listProfiles() -> [String] {
        guard let profileStore = profileStore else {
            return ["ERROR: Profile store is not available."]
        }

        return profileStore.profiles.map(\.name)
    }

    /// Return the current encoding queue status as a JSON string.
    ///
    /// The returned JSON includes:
    ///   - `totalJobs`: Total number of jobs in the queue.
    ///   - `completedJobs`: Number of completed jobs.
    ///   - `failedJobs`: Number of failed jobs.
    ///   - `currentJob`: Object with `id`, `fileName`, `progress`, `speed`,
    ///     `eta` for the active job (null if idle).
    ///   - `queuedJobs`: Number of jobs waiting.
    ///
    /// - Returns: A JSON string describing the queue state.
    @objc func queueStatus() -> String {
        guard let queue = queue else {
            return "{\"error\": \"Queue is not available.\"}"
        }

        var statusDict: [String: Any] = [:]
        let jobs = queue.jobs

        statusDict["totalJobs"] = jobs.count
        statusDict["completedJobs"] = jobs.filter { $0.status == .completed }.count
        statusDict["failedJobs"] = jobs.filter { $0.status == .failed }.count
        statusDict["queuedJobs"] = jobs.filter { $0.status == .queued }.count

        if let current = queue.currentJob {
            var currentDict: [String: Any] = [:]
            currentDict["id"] = current.config.id.uuidString
            currentDict["fileName"] = current.config.inputURL.lastPathComponent
            currentDict["progress"] = current.progress
            if let speed = current.speed {
                currentDict["speed"] = speed
            }
            if let eta = current.eta {
                currentDict["eta"] = eta
            }
            statusDict["currentJob"] = currentDict
        } else {
            statusDict["currentJob"] = nil as Any? as Any
        }

        // Serialise to JSON
        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: statusDict,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "{\"error\": \"Failed to serialise queue status.\"}"
        }

        return String(data: jsonData, encoding: .utf8) ?? "{\"error\": \"Encoding failed.\"}"
    }

    /// Return the application version string.
    ///
    /// - Returns: The semantic version string from `AppInfo.Version`
    ///   (e.g. "0.1.0-alpha").
    @objc func version() -> String {
        return AppInfo.Version.displayString
    }
}
