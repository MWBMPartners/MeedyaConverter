// File: adaptix/core/FFmpegController.swift
// Purpose: Orchestrates all FFmpeg media processing tasks including video/audio/subtitle encoding, splitting, batching, pausing/resuming jobs, and monitoring progress.
// Role: Central engine for all encoding operations; interacts with EncodingProfile and ManifestGenerator
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

/// A singleton controller that manages FFmpeg encoding tasks in Adaptix.
/// Handles encoding of video/audio separately, job pausing/resuming, progress updates, and batch workflows.
class FFmpegController: ObservableObject {

    /// Represents the current encoding task (if any).
    @Published var currentTask: Process?
    
    /// Stores log or output messages from FFmpeg.
    @Published var ffmpegLog: [String] = []

    /// Starts a new FFmpeg encoding task with the provided arguments.
    /// - Parameter arguments: Command-line arguments to pass to FFmpeg.
    /// - Returns: Bool indicating if task started successfully.
    func startEncoding(arguments: [String]) -> Bool {
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/ffmpeg" // 🧠 Update for user’s installed FFmpeg path if needed
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let output = String(data: handle.availableData, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.ffmpegLog.append(output)
            }
        }

        do {
            try task.run()
            self.currentTask = task
            return true
        } catch {
            print("❌ FFmpeg launch failed: \(error)")
            return false
        }
    }

    /// Stops the current FFmpeg task (if running).
    func stopEncoding() {
        currentTask?.terminate()
        currentTask = nil
    }

    /// Pauses the FFmpeg task by sending a SIGSTOP signal (macOS/Linux only).
    func pauseEncoding() {
        guard let pid = currentTask?.processIdentifier else { return }
        kill(pid, SIGSTOP)
    }

    /// Resumes the paused FFmpeg task by sending a SIGCONT signal (macOS/Linux only).
    func resumeEncoding() {
        guard let pid = currentTask?.processIdentifier else { return }
        kill(pid, SIGCONT)
    }

    /// Check if the current task is still active.
    var isEncoding: Bool {
        return currentTask?.isRunning ?? false
    }

    /// Convenience function to build argument list from a shell string.
    func arguments(from command: String) -> [String] {
        return command.components(separatedBy: " ").filter { !$0.isEmpty }
    }
}

// 📚 See: https://ffmpeg.org/ffmpeg.html for command syntax reference
// 📚 See: https://developer.apple.com/documentation/foundation/process