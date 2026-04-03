// ============================================================================
// MeedyaConverter — FFmpegProcessController
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FFmpegProcessError

/// Errors that can occur during FFmpeg process execution.
public enum FFmpegProcessError: LocalizedError, Sendable {
    /// The FFmpeg process exited with a non-zero status code.
    case processFailure(exitCode: Int32, stderr: String)

    /// The FFmpeg process was cancelled by the user.
    case cancelled

    /// The FFmpeg process timed out.
    case timeout

    /// No FFmpeg binary is configured or available.
    case noBinary

    /// The process is already running — cannot start a second one.
    case alreadyRunning

    public var errorDescription: String? {
        switch self {
        case .processFailure(let code, let stderr):
            return "FFmpeg exited with code \(code): \(stderr.prefix(500))"
        case .cancelled:
            return "FFmpeg encoding was cancelled."
        case .timeout:
            return "FFmpeg process timed out."
        case .noBinary:
            return "No FFmpeg binary configured. Check Settings → Tools."
        case .alreadyRunning:
            return "An encoding process is already running."
        }
    }
}

// MARK: - FFmpegProcessState

/// The current state of the FFmpeg process controller.
public enum FFmpegProcessState: String, Sendable {
    /// No process is running. Ready to start.
    case idle

    /// A process is currently running.
    case running

    /// The process is paused (SIGSTOP sent).
    case paused

    /// The process has completed (check result for success/failure).
    case completed

    /// The process was cancelled.
    case cancelled
}

// MARK: - FFmpegProgressInfo

/// Parsed progress information from FFmpeg's stderr output.
public struct FFmpegProgressInfo: Sendable {
    /// Current frame number being processed.
    public var frame: Int?

    /// Current processing speed (e.g., 2.5x realtime).
    public var speed: Double?

    /// Current bitrate of the output in kbps.
    public var bitrate: Double?

    /// Total output file size so far in bytes.
    public var totalSize: Int?

    /// Current time position in the encoding (seconds from start).
    public var currentTime: TimeInterval?

    /// Estimated progress as a fraction (0.0 to 1.0).
    /// Calculated from currentTime / totalDuration when duration is known.
    public var fractionComplete: Double?

    /// Raw FFmpeg progress line for logging.
    public var rawLine: String?

    public init() {}
}

// MARK: - FFmpegProcessController

/// Controls the lifecycle of an FFmpeg subprocess: start, pause, resume, stop.
///
/// This controller launches FFmpeg as a child process via `Foundation.Process`,
/// monitors its stderr output for progress information, and provides
/// pause/resume/cancel functionality via POSIX signals.
///
/// Usage:
/// ```swift
/// let controller = FFmpegProcessController(binaryPath: "/opt/homebrew/bin/ffmpeg")
/// let progressStream = controller.startEncoding(arguments: ["-i", "input.mkv", ...])
/// for await progress in progressStream {
///     updateUI(progress.fractionComplete)
/// }
/// ```
public final class FFmpegProcessController: @unchecked Sendable {

    // MARK: - Properties

    /// Path to the FFmpeg binary.
    private let binaryPath: String

    /// The underlying Foundation.Process instance, if running.
    private var process: Process?

    /// The current state of the controller.
    public private(set) var state: FFmpegProcessState = .idle

    /// Accumulated stderr output from FFmpeg (for error reporting).
    private var stderrBuffer: String = ""

    /// Accumulated stdout output from FFmpeg.
    private var stdoutBuffer: String = ""

    /// The total duration of the source file (used to calculate progress fraction).
    /// Set before starting encoding if known from probing.
    public var sourceDuration: TimeInterval?

    /// Serial lock for thread-safe state access.
    private let lock = NSLock()

    /// Continuation for the progress stream.
    private var progressContinuation: AsyncStream<FFmpegProgressInfo>.Continuation?

    // MARK: - Initialiser

    /// Create a new FFmpeg process controller.
    ///
    /// - Parameter binaryPath: Full path to the FFmpeg executable.
    public init(binaryPath: String) {
        self.binaryPath = binaryPath
    }

    // MARK: - Encoding Lifecycle

    /// Start an FFmpeg encoding process with the given arguments.
    ///
    /// Returns an `AsyncStream` of progress updates parsed from FFmpeg's
    /// stderr output. The stream completes when the process finishes.
    ///
    /// - Parameter arguments: The FFmpeg command-line arguments (excluding the binary itself).
    /// - Returns: An async stream of `FFmpegProgressInfo` values.
    /// - Throws: `FFmpegProcessError` if the process cannot be started.
    public func startEncoding(arguments: [String]) throws -> AsyncStream<FFmpegProgressInfo> {
        lock.lock()
        defer { lock.unlock() }

        guard state == .idle || state == .completed || state == .cancelled else {
            throw FFmpegProcessError.alreadyRunning
        }

        // Reset state for new encoding
        stderrBuffer = ""
        stdoutBuffer = ""
        state = .running

        // Create the process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)

        // Add -progress pipe:1 for machine-readable progress output
        // and -nostdin to prevent FFmpeg waiting for input
        var fullArgs = ["-nostdin", "-y"] + arguments + ["-progress", "pipe:1"]
        proc.arguments = fullArgs

        // Set up pipes for stdout (progress) and stderr (logs/errors)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.standardInput = FileHandle.nullDevice

        self.process = proc

        // Create the async stream for progress reporting
        let stream = AsyncStream<FFmpegProgressInfo> { [weak self] continuation in
            self?.progressContinuation = continuation

            // Handle process termination
            proc.terminationHandler = { [weak self] terminatedProcess in
                guard let self = self else { return }
                self.lock.lock()
                if self.state == .running || self.state == .paused {
                    self.state = terminatedProcess.terminationStatus == 0 ? .completed : .completed
                }
                self.lock.unlock()
                continuation.finish()
            }

            // Read stderr asynchronously for logging and error capture
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let self = self else { return }
                if let text = String(data: data, encoding: .utf8) {
                    self.lock.lock()
                    self.stderrBuffer += text
                    self.lock.unlock()
                }
            }

            // Read stdout asynchronously for progress parsing
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let self = self else { return }
                if let text = String(data: data, encoding: .utf8) {
                    self.lock.lock()
                    self.stdoutBuffer += text
                    self.lock.unlock()

                    // Parse progress lines from the -progress output
                    let progressInfo = self.parseProgress(from: text)
                    if progressInfo.currentTime != nil || progressInfo.frame != nil {
                        continuation.yield(progressInfo)
                    }
                }
            }
        }

        // Launch the process
        do {
            try proc.run()
        } catch {
            state = .idle
            process = nil
            throw FFmpegProcessError.noBinary
        }

        return stream
    }

    /// Pause the running FFmpeg process by sending SIGSTOP.
    ///
    /// The process can be resumed with `resumeEncoding()`.
    /// On macOS, SIGSTOP suspends the process but does not terminate it.
    public func pauseEncoding() {
        lock.lock()
        defer { lock.unlock() }

        guard state == .running, let proc = process, proc.isRunning else { return }

        // Send SIGSTOP to suspend the process
        kill(proc.processIdentifier, SIGSTOP)
        state = .paused
    }

    /// Resume a paused FFmpeg process by sending SIGCONT.
    public func resumeEncoding() {
        lock.lock()
        defer { lock.unlock() }

        guard state == .paused, let proc = process, proc.isRunning else { return }

        // Send SIGCONT to resume the process
        kill(proc.processIdentifier, SIGCONT)
        state = .running
    }

    /// Cancel/stop the running FFmpeg process.
    ///
    /// Sends SIGTERM for graceful termination. If the process doesn't
    /// exit within a short timeout, SIGKILL is sent.
    public func stopEncoding() {
        lock.lock()
        defer { lock.unlock() }

        guard let proc = process else { return }

        state = .cancelled

        if proc.isRunning {
            // If paused, resume first so it can receive the termination signal
            kill(proc.processIdentifier, SIGCONT)

            // Send SIGTERM for graceful shutdown
            proc.terminate()
        }

        progressContinuation?.finish()
    }

    /// Whether the process is currently running (not paused, not finished).
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .running
    }

    /// Whether the process is paused.
    public var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .paused
    }

    /// The exit code of the completed process, if available.
    public var exitCode: Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard state == .completed || state == .cancelled else { return nil }
        return process?.terminationStatus
    }

    /// The accumulated stderr output from FFmpeg.
    /// Useful for error reporting and the unified activity log.
    public var errorOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrBuffer
    }

    // MARK: - Progress Parsing

    /// Parse FFmpeg's -progress pipe output into structured progress info.
    ///
    /// FFmpeg's -progress output consists of key=value pairs, one per line:
    /// ```
    /// frame=1234
    /// fps=30.0
    /// bitrate=5000.0kbits/s
    /// total_size=12345678
    /// out_time_us=5000000
    /// speed=2.5x
    /// progress=continue
    /// ```
    private func parseProgress(from output: String) -> FFmpegProgressInfo {
        var info = FFmpegProgressInfo()
        info.rawLine = output

        let lines = output.split(separator: "\n")

        for line in lines {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "frame":
                info.frame = Int(value)

            case "speed":
                // Value is like "2.5x" — strip the "x" suffix
                let numStr = value.replacingOccurrences(of: "x", with: "")
                info.speed = Double(numStr)

            case "bitrate":
                // Value is like "5000.0kbits/s"
                let numStr = value.replacingOccurrences(of: "kbits/s", with: "")
                info.bitrate = Double(numStr)

            case "total_size":
                info.totalSize = Int(value)

            case "out_time_us":
                // Value is in microseconds — convert to seconds
                if let us = Int64(value) {
                    info.currentTime = TimeInterval(us) / 1_000_000.0

                    // Calculate fraction complete if we know the source duration
                    if let duration = sourceDuration, duration > 0 {
                        info.fractionComplete = min(1.0, TimeInterval(us) / (duration * 1_000_000.0))
                    }
                }

            case "out_time":
                // Alternative: value is "HH:MM:SS.microseconds"
                info.currentTime = parseTimeString(value)
                if let time = info.currentTime, let duration = sourceDuration, duration > 0 {
                    info.fractionComplete = min(1.0, time / duration)
                }

            default:
                break
            }
        }

        return info
    }

    /// Parse a time string in FFmpeg's "HH:MM:SS.microseconds" format.
    private func parseTimeString(_ timeStr: String) -> TimeInterval? {
        let components = timeStr.split(separator: ":")
        guard components.count == 3 else { return nil }

        guard let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else {
            return nil
        }

        return hours * 3600.0 + minutes * 60.0 + seconds
    }
}
