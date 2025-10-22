// File: adaptix/core/FFmpegController.swift
// Purpose: Orchestrates all FFmpeg media processing tasks including video/audio/subtitle encoding, splitting, batching, pausing/resuming jobs, and monitoring progress.
// Role: Central engine for all encoding operations; interacts with EncodingProfile and ManifestGenerator
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation
import Combine

// MARK: - Encoding Job

/// Represents a single encoding job
struct EncodingJob: Identifiable, Codable {
    let id: UUID
    let inputPath: String
    let outputPath: String
    let arguments: [String]
    let profile: EncodingProfile?
    var status: JobStatus
    var progress: Double
    var startTime: Date?
    var endTime: Date?
    var error: String?

    enum JobStatus: String, Codable {
        case pending
        case running
        case paused
        case completed
        case failed
        case cancelled
    }

    init(id: UUID = UUID(),
         inputPath: String,
         outputPath: String,
         arguments: [String],
         profile: EncodingProfile? = nil) {
        self.id = id
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.arguments = arguments
        self.profile = profile
        self.status = .pending
        self.progress = 0.0
    }

    var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
}

// MARK: - Progress Information

struct EncodingProgress {
    var frame: Int = 0
    var fps: Double = 0.0
    var bitrate: String = "0kbits/s"
    var totalSize: String = "0kB"
    var outTimeMs: Int64 = 0
    var speed: String = "0x"
    var progress: Double = 0.0
    var currentTime: TimeInterval = 0.0
    var totalDuration: TimeInterval = 0.0

    var percentage: Int {
        return Int(progress * 100)
    }

    var estimatedTimeRemaining: TimeInterval? {
        guard progress > 0, speed != "0x" else { return nil }
        let speedValue = Double(speed.replacingOccurrences(of: "x", with: "")) ?? 0
        guard speedValue > 0 else { return nil }

        let elapsed = currentTime
        let total = totalDuration
        let remaining = (total - elapsed) / speedValue
        return remaining
    }
}

// MARK: - FFmpeg Controller

/// A singleton controller that manages FFmpeg encoding tasks in Adaptix.
/// Handles encoding of video/audio separately, job pausing/resuming, progress updates, and batch workflows.
class FFmpegController: ObservableObject {

    static let shared = FFmpegController()

    // MARK: - Published Properties

    @Published var currentJob: EncodingJob?
    @Published var jobQueue: [EncodingJob] = []
    @Published var completedJobs: [EncodingJob] = []
    @Published var currentProgress: EncodingProgress = EncodingProgress()
    @Published var ffmpegLog: [String] = []
    @Published var isProcessing: Bool = false

    // MARK: - Private Properties

    private var currentTask: Process?
    private var ffmpegPath: String?
    private var ffprobePath: String?
    private var cancellables = Set<AnyCancellable>()
    private let processingQueue = DispatchQueue(label: "com.adaptix.encoding", qos: .userInitiated)

    // MARK: - Initialization

    init() {
        detectFFmpegPaths()
    }

    // MARK: - FFmpeg Detection

    /// Detects FFmpeg and FFprobe installations on the system
    private func detectFFmpegPaths() {
        // Try common installation paths
        let commonPaths = [
            "/opt/homebrew/bin/ffmpeg",           // Homebrew (Apple Silicon)
            "/usr/local/bin/ffmpeg",              // Homebrew (Intel Mac) / Linux
            "/usr/bin/ffmpeg",                    // Linux system install
            "/opt/local/bin/ffmpeg",              // MacPorts
            "C:\\ffmpeg\\bin\\ffmpeg.exe",        // Windows common path
            "C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe"
        ]

        // First try 'which ffmpeg'
        if let whichPath = try? runCommand("/usr/bin/which", arguments: ["ffmpeg"]),
           !whichPath.isEmpty {
            ffmpegPath = whichPath.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Try common paths
            for path in commonPaths {
                if FileManager.default.fileExists(atPath: path) {
                    ffmpegPath = path
                    break
                }
            }
        }

        // Same for ffprobe
        if let whichPath = try? runCommand("/usr/bin/which", arguments: ["ffprobe"]),
           !whichPath.isEmpty {
            ffprobePath = whichPath.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let probePaths = commonPaths.map { $0.replacingOccurrences(of: "ffmpeg", with: "ffprobe") }
            for path in probePaths {
                if FileManager.default.fileExists(atPath: path) {
                    ffprobePath = path
                    break
                }
            }
        }

        print("🔍 FFmpeg path: \(ffmpegPath ?? "not found")")
        print("🔍 FFprobe path: \(ffprobePath ?? "not found")")
    }

    /// Sets custom FFmpeg path
    func setFFmpegPath(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            print("❌ FFmpeg not found at: \(path)")
            return
        }
        ffmpegPath = path
        print("✅ FFmpeg path set to: \(path)")
    }

    /// Validates FFmpeg installation
    func validateFFmpegInstallation() -> Bool {
        guard let path = ffmpegPath else {
            return false
        }

        do {
            let output = try runCommand(path, arguments: ["-version"])
            return output.contains("ffmpeg version")
        } catch {
            return false
        }
    }

    // MARK: - Job Management

    /// Adds a job to the encoding queue
    func addJob(_ job: EncodingJob) {
        jobQueue.append(job)
        if !isProcessing {
            processNextJob()
        }
    }

    /// Adds multiple jobs to the queue
    func addJobs(_ jobs: [EncodingJob]) {
        jobQueue.append(contentsOf: jobs)
        if !isProcessing {
            processNextJob()
        }
    }

    /// Cancels a specific job
    func cancelJob(id: UUID) {
        if currentJob?.id == id {
            stopEncoding()
        } else {
            jobQueue.removeAll { $0.id == id }
        }
    }

    /// Cancels all jobs
    func cancelAllJobs() {
        stopEncoding()
        jobQueue.removeAll()
    }

    /// Processes the next job in the queue
    private func processNextJob() {
        guard !jobQueue.isEmpty, currentJob == nil else {
            isProcessing = false
            return
        }

        isProcessing = true
        var job = jobQueue.removeFirst()
        job.status = .running
        job.startTime = Date()
        currentJob = job

        processingQueue.async { [weak self] in
            self?.executeJob(job)
        }
    }

    // MARK: - Encoding Execution

    /// Executes an encoding job
    private func executeJob(_ job: EncodingJob) {
        guard let ffmpegPath = ffmpegPath else {
            DispatchQueue.main.async {
                var failedJob = job
                failedJob.status = .failed
                failedJob.error = "FFmpeg not found"
                failedJob.endTime = Date()
                self.completedJobs.append(failedJob)
                self.currentJob = nil
                self.processNextJob()
            }
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpegPath)
        task.arguments = job.arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        // Parse FFmpeg output for progress
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                self?.parseFFmpegOutput(output, for: job)
            }
        }

        do {
            try task.run()
            currentTask = task

            // Wait for completion
            task.waitUntilExit()

            DispatchQueue.main.async {
                var completedJob = job
                completedJob.endTime = Date()

                if task.terminationStatus == 0 {
                    completedJob.status = .completed
                    completedJob.progress = 1.0
                } else {
                    completedJob.status = .failed
                    completedJob.error = "FFmpeg exited with code \(task.terminationStatus)"
                }

                self.completedJobs.append(completedJob)
                self.currentJob = nil
                self.currentTask = nil
                self.processNextJob()
            }

        } catch {
            DispatchQueue.main.async {
                var failedJob = job
                failedJob.status = .failed
                failedJob.error = error.localizedDescription
                failedJob.endTime = Date()
                self.completedJobs.append(failedJob)
                self.currentJob = nil
                self.currentTask = nil
                self.processNextJob()
            }
        }
    }

    /// Parses FFmpeg output to extract progress information
    private func parseFFmpegOutput(_ output: String, for job: EncodingJob) {
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Add to log
            DispatchQueue.main.async {
                self.ffmpegLog.append(line)
            }

            // Parse duration from input file info
            if line.contains("Duration:") {
                if let duration = parseDuration(from: line) {
                    DispatchQueue.main.async {
                        self.currentProgress.totalDuration = duration
                    }
                }
            }

            // Parse progress information
            if line.contains("frame=") || line.contains("time=") {
                let progress = parseProgressLine(line)
                DispatchQueue.main.async {
                    self.currentProgress = progress

                    // Update job progress
                    if var currentJob = self.currentJob,
                       currentJob.id == job.id {
                        currentJob.progress = progress.progress
                        self.currentJob = currentJob
                    }
                }
            }
        }
    }

    /// Parses duration from FFmpeg output
    private func parseDuration(from line: String) -> TimeInterval? {
        // Example: Duration: 00:05:24.13, start: 0.000000, bitrate: 2340 kb/s
        guard let range = line.range(of: "Duration: ") else { return nil }
        let durationStr = String(line[range.upperBound...])
        let components = durationStr.components(separatedBy: ",")[0]
        return timeStringToSeconds(components)
    }

    /// Parses progress line from FFmpeg output
    private func parseProgressLine(_ line: String) -> EncodingProgress {
        var progress = currentProgress

        // frame=  123 fps= 45 q=28.0 size=    1234kB time=00:00:12.34 bitrate=1000.0kbits/s speed=2.34x
        let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        for component in components {
            if component.hasPrefix("frame=") {
                progress.frame = Int(component.replacingOccurrences(of: "frame=", with: "")) ?? 0
            } else if component.hasPrefix("fps=") {
                progress.fps = Double(component.replacingOccurrences(of: "fps=", with: "")) ?? 0
            } else if component.hasPrefix("size=") {
                progress.totalSize = component.replacingOccurrences(of: "size=", with: "")
            } else if component.hasPrefix("time=") {
                let timeStr = component.replacingOccurrences(of: "time=", with: "")
                progress.currentTime = timeStringToSeconds(timeStr) ?? 0
            } else if component.hasPrefix("bitrate=") {
                progress.bitrate = component.replacingOccurrences(of: "bitrate=", with: "")
            } else if component.hasPrefix("speed=") {
                progress.speed = component.replacingOccurrences(of: "speed=", with: "")
            }
        }

        // Calculate progress percentage
        if progress.totalDuration > 0 {
            progress.progress = min(progress.currentTime / progress.totalDuration, 1.0)
        }

        return progress
    }

    /// Converts time string (HH:MM:SS.mmm) to seconds
    private func timeStringToSeconds(_ timeStr: String) -> TimeInterval? {
        let components = timeStr.components(separatedBy: ":")
        guard components.count == 3 else { return nil }

        let hours = Double(components[0]) ?? 0
        let minutes = Double(components[1]) ?? 0
        let seconds = Double(components[2]) ?? 0

        return hours * 3600 + minutes * 60 + seconds
    }

    // MARK: - Encoding Control

    /// Starts encoding with the provided arguments
    func startEncoding(arguments: [String]) -> Bool {
        let job = EncodingJob(
            inputPath: extractInputPath(from: arguments),
            outputPath: extractOutputPath(from: arguments),
            arguments: arguments
        )
        addJob(job)
        return true
    }

    /// Stops the current encoding task
    func stopEncoding() {
        currentTask?.terminate()
        currentTask = nil

        if var job = currentJob {
            job.status = .cancelled
            job.endTime = Date()
            completedJobs.append(job)
            currentJob = nil
        }

        processNextJob()
    }

    /// Pauses the current encoding task (Unix-like systems only)
    func pauseEncoding() {
        guard let pid = currentTask?.processIdentifier else { return }
        kill(pid, SIGSTOP)

        if var job = currentJob {
            job.status = .paused
            currentJob = job
        }
    }

    /// Resumes the paused encoding task (Unix-like systems only)
    func resumeEncoding() {
        guard let pid = currentTask?.processIdentifier else { return }
        kill(pid, SIGCONT)

        if var job = currentJob {
            job.status = .running
            currentJob = job
        }
    }

    /// Check if currently encoding
    var isEncoding: Bool {
        return currentTask?.isRunning ?? false
    }

    // MARK: - Utility

    /// Extracts input path from arguments
    private func extractInputPath(from arguments: [String]) -> String {
        if let index = arguments.firstIndex(of: "-i"),
           index + 1 < arguments.count {
            return arguments[index + 1]
        }
        return "unknown"
    }

    /// Extracts output path from arguments
    private func extractOutputPath(from arguments: [String]) -> String {
        return arguments.last ?? "unknown"
    }

    /// Runs a command and returns output
    private func runCommand(_ path: String, arguments: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Convenience function to build argument list from a shell string
    func arguments(from command: String) -> [String] {
        return command.components(separatedBy: " ").filter { !$0.isEmpty }
    }

    /// Clears completed jobs
    func clearCompletedJobs() {
        completedJobs.removeAll()
    }

    /// Clears all logs
    func clearLogs() {
        ffmpegLog.removeAll()
    }
}

// 📚 See: https://ffmpeg.org/ffmpeg.html for command syntax reference
// 📚 See: https://developer.apple.com/documentation/foundation/process
