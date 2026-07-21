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

    // MARK: - F-008 helpers (T6 — AppleScript surface hardening)

    /// Soft cap on the length of any incoming AppleScript string
    /// argument. AppleScript can pass extremely long literals — a
    /// crafted attacker script could push a multi-megabyte profile
    /// name through `encode` and force the error-path to render it
    /// back. The 4 KB cap is generous for legitimate use (longest
    /// profile name we ship is ~30 characters; longest filename a
    /// macOS user can save is 255 bytes per component, ~4 KB for
    /// the full path) and tight enough to stop blob-pasting.
    /// Per SECURITY.md F-008.
    nonisolated fileprivate static let maxArgumentLength = 4096

    /// Format an `ERROR:` reply that interpolates user-supplied
    /// strings safely. The interpolated values pass through
    /// `MetadataSanitizer.sanitizeSingleLine` so an AppleScript
    /// caller can't inject NUL bytes, ANSI/VT100 escape sequences,
    /// bidirectional-override codepoints, C1 controls, Unicode
    /// line/paragraph separators, **or raw TAB/LF/CR** into our
    /// reply and forge fake output in the caller's log or terminal.
    ///
    /// The single-line variant is deliberate: an `ERROR:` reply is
    /// one logical line, and the plain `sanitize` helper RETAINS
    /// LF/CR (they're legitimate in multi-line media comment tags).
    /// Reusing `sanitize` here would leave a newline-injection
    /// vector — a profile name like `"bogus\nERROR: overwrote X"`
    /// would produce a forged second `ERROR:` line for a caller
    /// that logs the reply line-by-line. Per SECURITY.md F-008.
    nonisolated fileprivate static func formatError(_ message: String) -> String {
        return "ERROR: " + MetadataSanitizer.sanitizeSingleLine(message)
    }

    /// Reject an over-length argument with a clear ERROR reply.
    /// Returns nil when the argument is within bounds (caller may
    /// proceed). Per SECURITY.md F-008.
    nonisolated fileprivate static func enforceLengthCap(
        _ value: String,
        label: String
    ) -> String? {
        guard value.count > maxArgumentLength else { return nil }
        return formatError(
            "AppleScript argument '\(label)' exceeds the \(maxArgumentLength)-character cap."
        )
    }

    // MARK: - Synchronous probe/async bridge (Issue #451)

    /// Thread-safe box carrying the probe reply string from the detached
    /// probing task back to the semaphore-waiting caller in `probe(file:)`.
    ///
    /// `probe(file:)` must return a `String` synchronously: it is invoked
    /// directly by Cocoa's Open Scripting Architecture as a "direct
    /// parameter" command (see `MeedyaConverter.sdef`, which declares no
    /// `<cocoa class="...">` override for `probe`), so OSA dispatches it
    /// on the main thread via ordinary message send and expects an
    /// immediate reply. There is no async/completion-handler
    /// accommodation for that dispatch style — a genuinely non-blocking
    /// version of this command would require restructuring `probe` as an
    /// `NSScriptCommand` subclass using `suspendExecution()` /
    /// `resumeExecutionWithResult(_:)`, a materially larger architecture
    /// change that is out of scope here. A `DispatchSemaphore` therefore
    /// still bridges the synchronous return to the async `FFmpegProbe`
    /// call, and the call still blocks the calling (main) thread for up
    /// to the same 60-second cap as before — unchanged behaviour.
    ///
    /// What actually changes for Issue #451 is *how* the result crosses
    /// that bridge. The previous implementation captured a
    /// `nonisolated(unsafe) var` local variable by reference into a
    /// `Task.detached` closure and mutated it there — a shape Swift 6
    /// flags as risking a data race, because the compiler has no way to
    /// see that the semaphore establishes a happens-before edge between
    /// the write and the later read. `ProbeResultBox` replaces the bare
    /// local var with an explicitly `Sendable` reference type — an
    /// `NSLock`-protected box, the same pattern already proven safe by
    /// `FFmpegProbe.ProbeRunState` in this codebase — so no
    /// isolation-unsafe capture crosses the `Task.detached` boundary.
    private final class ProbeResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: String

        init(_ initial: String) {
            self._value = initial
        }

        var value: String {
            lock.withLock { _value }
        }

        func setValue(_ newValue: String) {
            lock.withLock { _value = newValue }
        }
    }

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
        // F-008 length caps — fail fast before any work happens.
        if let err = Self.enforceLengthCap(file, label: "file") { return err }
        if let err = Self.enforceLengthCap(profile, label: "profile") { return err }
        if let err = Self.enforceLengthCap(output, label: "output") { return err }

        guard let engine = engine else {
            return Self.formatError("Encoding engine is not configured.")
        }

        guard let profileStore = profileStore else {
            return Self.formatError("Profile store is not available.")
        }

        // Validate input file exists
        let inputURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            return Self.formatError("Input file not found: \(file)")
        }

        // Look up the encoding profile by name
        guard let encodingProfile = profileStore.profile(named: profile) else {
            let available = profileStore.profiles.map(\.name).joined(separator: ", ")
            return Self.formatError(
                "Profile '\(profile)' not found. Available: \(available)"
            )
        }

        // Build the job configuration.
        //
        // T2 path-traversal defence (SECURITY.md finding F-002): the
        // `output` string arrives directly from the AppleScript caller
        // and could be a relative path containing `..` segments. Reject
        // any output URL that doesn't standardise to a path within the
        // user's home directory after **lexical** `..`-collapsing
        // (`URL.isContained(within:)` uses `.standardized`; it does
        // NOT resolve symbolic links — that's a documented, accepted
        // trade-off, since a symlink escape would require the attacker
        // to already have write access inside the user's home to plant
        // the link). This is the narrow allowlist — the AppleScript
        // bridge is intended for automation of conversion *within* the
        // user's own files, not as a tool for writing to arbitrary
        // system locations.
        let outputURL = URL(fileURLWithPath: output)
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        guard outputURL.isContained(within: homeURL) else {
            return Self.formatError(
                "Output path is not within the user's home directory. Path traversal segments (e.g. '..') are not permitted via the AppleScript bridge: \(output)"
            )
        }
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
        // F-008 length cap.
        if let err = Self.enforceLengthCap(file, label: "file") { return err }

        guard let engine = engine else {
            return Self.formatError("Encoding engine is not configured.")
        }

        let fileURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Self.formatError("File not found: \(file)")
        }

        // Probing is async but AppleScript expects a synchronous return.
        // We use FFmpegProbe directly via a synchronous Process invocation
        // on a background queue, bridging back with a semaphore. The
        // FFmpegProbe type is Sendable, so it can safely cross isolation.
        guard let ffprobePath = engine.ffprobeInfo?.path else {
            return Self.formatError("FFprobe not configured. Call configure() first.")
        }

        // Run the probe synchronously using Process (FFmpegProbe.analyzeSync).
        // Since FFmpegProbe's analyze(url:) is async, we invoke it from a
        // detached task and collect the result via `ProbeResultBox`
        // (Issue #451) — a thread-safe Sendable box, never a captured
        // mutable local var — so the write-then-signal / wait-then-read
        // handoff below is provably safe to the Swift 6 concurrency
        // checker, not just safe in practice.
        let resultBox = ProbeResultBox(Self.formatError("Probe did not complete."))
        let prober = FFmpegProbe(ffprobePath: ffprobePath)
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            do {
                let mediaFile = try await prober.analyze(url: fileURL)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(mediaFile)
                resultBox.setValue(
                    String(data: data, encoding: .utf8) ?? Self.formatError("Failed to encode JSON.")
                )
            } catch {
                // F-008: sanitise the localizedDescription before
                // returning. Foundation can include filesystem paths
                // (the resolved ffprobe binary location, the input
                // file path with its on-disk encoding) in error
                // messages; passing them through the sanitiser
                // strips any embedded control codes that would
                // otherwise allow log forgery from the AppleScript
                // caller's perspective.
                resultBox.setValue(Self.formatError("Probe failed — \(error.localizedDescription)"))
            }
            semaphore.signal()
        }

        // Wait with a generous timeout (media probing can take a few seconds
        // for large files on slow storage). Note: this blocks the main thread,
        // which is acceptable for AppleScript's synchronous calling convention
        // (see `ProbeResultBox` above for why this handoff can no longer race).
        let timeout = semaphore.wait(timeout: .now() + 60)
        if timeout == .timedOut {
            return Self.formatError("Probe timed out after 60 seconds.")
        }

        return resultBox.value
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
            // F-008: sanitise the filename before publishing — a
            // malicious media filename containing VT100 escape
            // sequences would otherwise reach the AppleScript
            // caller's queue-monitor and forge fake terminal
            // output if the caller logs the response.
            currentDict["fileName"] = MetadataSanitizer.sanitize(
                current.config.inputURL.lastPathComponent
            )
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
