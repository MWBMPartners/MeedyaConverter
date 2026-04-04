// ============================================================================
// MeedyaConverter — CLI Batch Command
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import ArgumentParser
import Foundation
import ConverterEngine

struct BatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Encode multiple files from a directory or JSON job file."
    )

    @Option(name: .customLong("dir"), help: "Directory containing input files to encode.")
    var inputDirectory: String?

    @Option(name: .customLong("job-file"), help: "Path to a JSON job file describing batch jobs.")
    var jobFile: String?

    @Option(name: [.short, .customLong("profile")], help: "Encoding profile name (used with --dir).")
    var profileName: String?

    @Option(name: [.short, .customLong("output")], help: "Output directory for encoded files.")
    var outputDirectory: String?

    @Option(name: .customLong("extension"), help: "File extensions to include (comma-separated, e.g., 'mkv,mp4,avi').")
    var fileExtensions: String?

    @Flag(name: .customLong("recursive"), help: "Recursively scan subdirectories.")
    var recursive = false

    @Flag(name: .customLong("quiet"), help: "Suppress progress output.")
    var quiet = false

    @Flag(name: .customLong("json"), help: "Output results as JSON.")
    var jsonOutput = false

    @Flag(name: [.short, .customLong("yes")], help: "Overwrite existing output files without prompting.")
    var overwrite = false

    func validate() throws {
        if inputDirectory == nil && jobFile == nil {
            throw ValidationError("Provide either --dir or --job-file.")
        }
        if inputDirectory != nil && jobFile != nil {
            throw ValidationError("Cannot use both --dir and --job-file.")
        }
        if inputDirectory != nil && profileName == nil {
            throw ValidationError("--profile is required when using --dir.")
        }
    }

    func run() async throws {
        if let dir = inputDirectory {
            try await runDirectoryBatch(dir)
        } else if let file = jobFile {
            try await runJobFileBatch(file)
        }
    }

    // MARK: - Directory Batch

    private func runDirectoryBatch(_ dir: String) async throws {
        let dirURL = URL(fileURLWithPath: dir)
        guard FileManager.default.fileExists(atPath: dirURL.path) else {
            throw ValidationError("Directory not found: \(dir)")
        }

        // Collect input files
        let extensions = fileExtensions?.split(separator: ",").map(String.init)
            ?? ["mkv", "mp4", "avi", "mov", "webm", "ts", "m4v", "flv", "wmv", "mpg"]

        let files = collectFiles(in: dirURL, extensions: extensions, recursive: recursive)

        guard !files.isEmpty else {
            printStderr("No media files found in \(dir)")
            return
        }

        if !quiet { printStderr("Found \(files.count) files to encode.") }

        let engine = EncodingEngine()
        try engine.configure()

        guard let profile = EncodingProfile.builtInProfiles.first(where: {
            $0.name.lowercased() == (profileName ?? "").lowercased()
        }) ?? engine.profileStore.profile(named: profileName ?? "") else {
            throw ValidationError("Profile not found: \(profileName ?? "")")
        }

        let outputDir = outputDirectory.map { URL(fileURLWithPath: $0) }
            ?? dirURL.appendingPathComponent("encoded")

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var results: [(file: String, status: String)] = []

        for (index, file) in files.enumerated() {
            let stem = file.deletingPathExtension().lastPathComponent
            let ext = profile.preferredExtension
            let outputURL = outputDir.appendingPathComponent("\(stem).\(ext)")

            if FileManager.default.fileExists(atPath: outputURL.path) && !overwrite {
                if !quiet { printStderr("Skipping \(file.lastPathComponent) (output exists)") }
                results.append((file: file.lastPathComponent, status: "skipped"))
                continue
            }

            if !quiet {
                printStderr("[\(index + 1)/\(files.count)] Encoding \(file.lastPathComponent)...")
            }

            let config = EncodingJobConfig(
                inputURL: file,
                outputURL: outputURL,
                profile: profile
            )

            do {
                try await engine.encode(job: config) { progress in
                    if !quiet && !jsonOutput {
                        let pct = Int((progress.fractionComplete ?? 0) * 100)
                        printStderr("\r  Progress: \(pct)%", terminator: "")
                    }
                }
                if !quiet { printStderr("") }
                results.append((file: file.lastPathComponent, status: "completed"))
            } catch {
                if !quiet { printStderr("\n  Failed: \(error.localizedDescription)") }
                results.append((file: file.lastPathComponent, status: "failed"))
            }
        }

        // Summary
        let completed = results.filter { $0.status == "completed" }.count
        let failed = results.filter { $0.status == "failed" }.count
        let skipped = results.filter { $0.status == "skipped" }.count

        if jsonOutput {
            let summary: [String: Any] = [
                "total": files.count,
                "completed": completed,
                "failed": failed,
                "skipped": skipped,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: summary, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            printStderr("\nBatch complete: \(completed) succeeded, \(failed) failed, \(skipped) skipped")
        }

        if failed > 0 {
            throw ExitCode(ExitCodes.encodingFailed.rawValue)
        }
    }

    // MARK: - Job File Batch

    private func runJobFileBatch(_ path: String) async throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("Job file not found: \(path)")
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let jobs = try decoder.decode([EncodingJobConfig].self, from: data)

        guard !jobs.isEmpty else {
            printStderr("No jobs found in \(path)")
            return
        }

        if !quiet { printStderr("Loaded \(jobs.count) jobs from \(url.lastPathComponent)") }

        let engine = EncodingEngine()
        try engine.configure()

        for (index, job) in jobs.enumerated() {
            if !quiet {
                printStderr("[\(index + 1)/\(jobs.count)] \(job.inputURL.lastPathComponent) → \(job.outputURL.lastPathComponent)")
            }

            do {
                try await engine.encode(job: job) { progress in
                    if !quiet && !jsonOutput {
                        let pct = Int((progress.fractionComplete ?? 0) * 100)
                        printStderr("\r  Progress: \(pct)%", terminator: "")
                    }
                }
                if !quiet { printStderr("") }
            } catch {
                printStderr("\n  Failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private func collectFiles(in dir: URL, extensions: [String], recursive: Bool) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []

        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: recursive ? [] : [.skipsSubdirectoryDescendants]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            if extensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL)
            }
        }

        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
