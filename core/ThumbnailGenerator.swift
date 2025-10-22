// File: adaptix/core/ThumbnailGenerator.swift
// Purpose: Generates thumbnail sprite sheets and WebVTT tracks for video preview scrubbing.
// Role: Creates preview thumbnails for adaptive streaming players (Video.js, Shaka Player, JW Player, etc.)
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

// MARK: - Thumbnail Configuration

/// Configuration for thumbnail generation
struct ThumbnailConfig: Codable {
    let interval: Double            // Seconds between thumbnails (e.g., 5.0)
    let width: Int                  // Thumbnail width in pixels
    let height: Int                 // Thumbnail height in pixels
    let columns: Int                // Number of columns in sprite sheet
    let rows: Int                   // Number of rows in sprite sheet
    let quality: ThumbnailQuality   // JPEG quality
    let format: ThumbnailFormat     // Output format
    let preserveAspectRatio: Bool   // Maintain video aspect ratio

    enum ThumbnailQuality: Int, Codable {
        case low = 60
        case medium = 75
        case high = 85
        case maximum = 95
    }

    enum ThumbnailFormat: String, Codable {
        case jpeg = "mjpeg"
        case png = "png"
        case webp = "webp"

        var fileExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .webp: return "webp"
            }
        }
    }

    /// Calculates total thumbnails per sprite sheet
    var thumbnailsPerSheet: Int {
        return columns * rows
    }

    /// Calculates sprite sheet dimensions
    var spriteSheetSize: (width: Int, height: Int) {
        return (width: width * columns, height: height * rows)
    }
}

/// Represents a generated thumbnail sprite sheet
struct ThumbnailSpriteSheet: Codable {
    let filePath: String
    let sheetIndex: Int
    let thumbnailCount: Int
    let startTime: Double
    let endTime: Double
    let gridSize: (columns: Int, rows: Int)
}

/// Represents a single thumbnail in the sprite sheet
struct ThumbnailMetadata: Codable {
    let timestamp: Double
    let sheetIndex: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

// MARK: - Thumbnail Generator

class ThumbnailGenerator {

    private let mediaProber: MediaProber
    private let ffmpegController: FFmpegController

    init(mediaProber: MediaProber, ffmpegController: FFmpegController = .shared) {
        self.mediaProber = mediaProber
        self.ffmpegController = ffmpegController
    }

    // MARK: - Main Generation Methods

    /// Generates thumbnail sprite sheets and WebVTT track for a video
    /// - Parameters:
    ///   - inputPath: Path to input video file
    ///   - outputDirectory: Directory to save thumbnails and VTT file
    ///   - config: Thumbnail generation configuration
    /// - Returns: Array of generated sprite sheets and path to VTT file
    /// - Throws: Thumbnail generation errors
    func generateThumbnails(inputPath: String,
                          outputDirectory: String,
                          config: ThumbnailConfig) throws -> (spriteSheets: [ThumbnailSpriteSheet], vttPath: String) {

        // 1. Probe video to get duration
        let mediaInfo = try mediaProber.probe(inputPath)

        guard let videoStream = mediaInfo.videoStreams.first else {
            throw ThumbnailError.noVideoStream
        }

        let duration = mediaInfo.duration

        // 2. Calculate total number of thumbnails needed
        let totalThumbnails = Int(ceil(duration / config.interval))
        let totalSheets = Int(ceil(Double(totalThumbnails) / Double(config.thumbnailsPerSheet)))

        print("📸 Generating \(totalThumbnails) thumbnails across \(totalSheets) sprite sheet(s)")

        // 3. Create output directory
        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )

        // 4. Generate thumbnails and sprite sheets
        var spriteSheets: [ThumbnailSpriteSheet] = []
        var allThumbnails: [ThumbnailMetadata] = []

        for sheetIndex in 0..<totalSheets {
            let (sheet, thumbnails) = try generateSpriteSheet(
                inputPath: inputPath,
                outputDirectory: outputDirectory,
                config: config,
                sheetIndex: sheetIndex,
                duration: duration
            )

            spriteSheets.append(sheet)
            allThumbnails.append(contentsOf: thumbnails)
        }

        // 5. Generate WebVTT file
        let vttPath = "\(outputDirectory)/thumbnails.vtt"
        try generateWebVTT(
            thumbnails: allThumbnails,
            spriteSheets: spriteSheets,
            outputPath: vttPath,
            config: config
        )

        print("✅ Thumbnail generation complete!")
        print("📁 Sprite sheets: \(spriteSheets.count)")
        print("📄 WebVTT: \(vttPath)")

        return (spriteSheets: spriteSheets, vttPath: vttPath)
    }

    // MARK: - Sprite Sheet Generation

    /// Generates a single sprite sheet
    private func generateSpriteSheet(inputPath: String,
                                    outputDirectory: String,
                                    config: ThumbnailConfig,
                                    sheetIndex: Int,
                                    duration: Double) throws -> (ThumbnailSpriteSheet, [ThumbnailMetadata]) {

        let startThumbnail = sheetIndex * config.thumbnailsPerSheet
        let endThumbnail = min(startThumbnail + config.thumbnailsPerSheet, Int(ceil(duration / config.interval)))
        let thumbnailCount = endThumbnail - startThumbnail

        let startTime = Double(startThumbnail) * config.interval
        let endTime = Double(endThumbnail) * config.interval

        // Create temporary directory for individual thumbnails
        let tempDir = "\(outputDirectory)/temp_\(sheetIndex)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        // Extract individual thumbnails using FFmpeg
        try extractIndividualThumbnails(
            inputPath: inputPath,
            outputDirectory: tempDir,
            config: config,
            startIndex: startThumbnail,
            count: thumbnailCount
        )

        // Combine thumbnails into sprite sheet
        let spriteSheetPath = "\(outputDirectory)/thumbnails_\(sheetIndex).\(config.format.fileExtension)"
        try combineThumbnailsIntoSpriteSheet(
            thumbnailDirectory: tempDir,
            outputPath: spriteSheetPath,
            config: config,
            thumbnailCount: thumbnailCount
        )

        // Clean up temporary thumbnails
        try? FileManager.default.removeItem(atPath: tempDir)

        // Generate metadata for each thumbnail
        var thumbnails: [ThumbnailMetadata] = []
        for i in 0..<thumbnailCount {
            let timestamp = startTime + (Double(i) * config.interval)
            let row = i / config.columns
            let col = i % config.columns

            thumbnails.append(ThumbnailMetadata(
                timestamp: timestamp,
                sheetIndex: sheetIndex,
                x: col * config.width,
                y: row * config.height,
                width: config.width,
                height: config.height
            ))
        }

        let spriteSheet = ThumbnailSpriteSheet(
            filePath: spriteSheetPath,
            sheetIndex: sheetIndex,
            thumbnailCount: thumbnailCount,
            startTime: startTime,
            endTime: endTime,
            gridSize: (columns: config.columns, rows: config.rows)
        )

        return (spriteSheet, thumbnails)
    }

    /// Extracts individual thumbnails from video using FFmpeg
    private func extractIndividualThumbnails(inputPath: String,
                                           outputDirectory: String,
                                           config: ThumbnailConfig,
                                           startIndex: Int,
                                           count: Int) throws {

        let outputPattern = "\(outputDirectory)/thumb_%04d.\(config.format.fileExtension)"

        var args: [String] = [
            "-i", inputPath,
            "-vf", buildThumbnailFilter(config: config, startIndex: startIndex, count: count),
            "-q:v", "\(config.quality.rawValue)",
            "-frames:v", "\(count)",
            outputPattern
        ]

        // Execute FFmpeg
        let job = EncodingJob(
            inputPath: inputPath,
            outputPath: outputPattern,
            arguments: args
        )

        ffmpegController.addJob(job)

        // Wait for completion
        waitForJobCompletion(job: job)
    }

    /// Builds FFmpeg filter for thumbnail extraction
    private func buildThumbnailFilter(config: ThumbnailConfig, startIndex: Int, count: Int) -> String {
        var filter = "select='not(mod(n\\,\(Int(config.interval * 30))))'"  // Assuming 30fps
        filter += ",scale=\(config.width):\(config.height)"

        if config.preserveAspectRatio {
            filter += ":force_original_aspect_ratio=decrease"
        }

        filter += ",setpts=N/TB"

        return filter
    }

    /// Combines individual thumbnails into a sprite sheet using FFmpeg
    private func combineThumbnailsIntoSpriteSheet(thumbnailDirectory: String,
                                                 outputPath: String,
                                                 config: ThumbnailConfig,
                                                 thumbnailCount: Int) throws {

        // Use FFmpeg tile filter to create sprite sheet
        let inputPattern = "\(thumbnailDirectory)/thumb_%04d.\(config.format.fileExtension)"

        let tileFilter = "tile=\(config.columns)x\(config.rows)"

        let args: [String] = [
            "-i", inputPattern,
            "-filter_complex", tileFilter,
            "-frames:v", "1",
            "-q:v", "\(config.quality.rawValue)",
            outputPath
        ]

        let job = EncodingJob(
            inputPath: inputPattern,
            outputPath: outputPath,
            arguments: args
        )

        ffmpegController.addJob(job)
        waitForJobCompletion(job: job)
    }

    // MARK: - WebVTT Generation

    /// Generates WebVTT thumbnail track file
    private func generateWebVTT(thumbnails: [ThumbnailMetadata],
                              spriteSheets: [ThumbnailSpriteSheet],
                              outputPath: String,
                              config: ThumbnailConfig) throws {

        var vtt = "WEBVTT\n\n"

        for thumbnail in thumbnails {
            let startTime = formatTimestamp(thumbnail.timestamp)
            let endTime = formatTimestamp(thumbnail.timestamp + config.interval)

            let spriteSheet = spriteSheets[thumbnail.sheetIndex]
            let spriteSheetFilename = URL(fileURLWithPath: spriteSheet.filePath).lastPathComponent

            vtt += "\(startTime) --> \(endTime)\n"
            vtt += "\(spriteSheetFilename)#xywh=\(thumbnail.x),\(thumbnail.y),\(thumbnail.width),\(thumbnail.height)\n\n"
        }

        try vtt.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    /// Formats timestamp for WebVTT (HH:MM:SS.mmm)
    private func formatTimestamp(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, milliseconds)
    }

    // MARK: - Utility Methods

    /// Waits for a job to complete
    private func waitForJobCompletion(job: EncodingJob) {
        while ffmpegController.currentJob?.id == job.id ||
              ffmpegController.jobQueue.contains(where: { $0.id == job.id }) {
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Check if job completed successfully
        if let completedJob = ffmpegController.completedJobs.first(where: { $0.id == job.id }),
           completedJob.status == .failed {
            print("⚠️ Thumbnail extraction job failed: \(completedJob.error ?? "Unknown error")")
        }
    }

    /// Generates thumbnails with automatic configuration
    func generateThumbnailsAuto(inputPath: String,
                               outputDirectory: String,
                               preset: ThumbnailPreset = .standard) throws -> (spriteSheets: [ThumbnailSpriteSheet], vttPath: String) {

        let config = ThumbnailPreset.configuration(for: preset)
        return try generateThumbnails(
            inputPath: inputPath,
            outputDirectory: outputDirectory,
            config: config
        )
    }
}

// MARK: - Thumbnail Presets

enum ThumbnailPreset {
    case fast       // Quick preview, lower quality
    case standard   // Balanced quality and performance
    case detailed   // More thumbnails, higher quality
    case maximum    // Highest quality, most thumbnails

    static func configuration(for preset: ThumbnailPreset) -> ThumbnailConfig {
        switch preset {
        case .fast:
            return ThumbnailConfig(
                interval: 10.0,
                width: 120,
                height: 68,
                columns: 5,
                rows: 5,
                quality: .medium,
                format: .jpeg,
                preserveAspectRatio: true
            )
        case .standard:
            return ThumbnailConfig(
                interval: 5.0,
                width: 160,
                height: 90,
                columns: 5,
                rows: 5,
                quality: .high,
                format: .jpeg,
                preserveAspectRatio: true
            )
        case .detailed:
            return ThumbnailConfig(
                interval: 2.0,
                width: 160,
                height: 90,
                columns: 10,
                rows: 10,
                quality: .high,
                format: .jpeg,
                preserveAspectRatio: true
            )
        case .maximum:
            return ThumbnailConfig(
                interval: 1.0,
                width: 240,
                height: 135,
                columns: 10,
                rows: 10,
                quality: .maximum,
                format: .jpeg,
                preserveAspectRatio: true
            )
        }
    }
}

// MARK: - Player Integration Helpers

extension ThumbnailGenerator {

    /// Generates Video.js compatible thumbnail configuration
    func generateVideoJSConfig(spriteSheets: [ThumbnailSpriteSheet],
                              vttPath: String) -> [String: Any] {
        return [
            "src": vttPath,
            "kind": "metadata",
            "label": "thumbnails"
        ]
    }

    /// Generates Shaka Player compatible thumbnail configuration
    func generateShakaConfig(spriteSheets: [ThumbnailSpriteSheet],
                           vttPath: String) -> [String: Any] {
        return [
            "thumbnails": [
                "uri": vttPath,
                "spriteSheets": spriteSheets.map { sheet in
                    [
                        "uri": URL(fileURLWithPath: sheet.filePath).lastPathComponent,
                        "width": sheet.gridSize.columns * 160,
                        "height": sheet.gridSize.rows * 90
                    ]
                }
            ]
        ]
    }

    /// Generates JW Player compatible thumbnail configuration
    func generateJWPlayerConfig(spriteSheets: [ThumbnailSpriteSheet],
                               vttPath: String) -> [String: Any] {
        return [
            "file": vttPath
        ]
    }
}

// MARK: - Errors

enum ThumbnailError: Error, LocalizedError {
    case noVideoStream
    case extractionFailed
    case spriteSheetCreationFailed
    case vttGenerationFailed
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .noVideoStream:
            return "No video stream found in input file"
        case .extractionFailed:
            return "Failed to extract thumbnails from video"
        case .spriteSheetCreationFailed:
            return "Failed to create thumbnail sprite sheet"
        case .vttGenerationFailed:
            return "Failed to generate WebVTT thumbnail track"
        case .invalidConfiguration:
            return "Invalid thumbnail configuration"
        }
    }
}

// MARK: - Batch Processing

extension ThumbnailGenerator {

    /// Generates thumbnails for multiple videos in batch
    func batchGenerateThumbnails(inputPaths: [String],
                                outputDirectory: String,
                                config: ThumbnailConfig) throws -> [(input: String, spriteSheets: [ThumbnailSpriteSheet], vttPath: String)] {

        var results: [(String, [ThumbnailSpriteSheet], String)] = []

        for inputPath in inputPaths {
            let videoName = URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent
            let videoOutputDir = "\(outputDirectory)/\(videoName)"

            let (spriteSheets, vttPath) = try generateThumbnails(
                inputPath: inputPath,
                outputDirectory: videoOutputDir,
                config: config
            )

            results.append((inputPath, spriteSheets, vttPath))
        }

        return results
    }
}

// MARK: - Validation

extension ThumbnailConfig {

    /// Validates the configuration
    func validate() throws {
        if interval <= 0 {
            throw ThumbnailError.invalidConfiguration
        }

        if width <= 0 || height <= 0 {
            throw ThumbnailError.invalidConfiguration
        }

        if columns <= 0 || rows <= 0 {
            throw ThumbnailError.invalidConfiguration
        }

        if columns * rows > 1000 {
            throw ThumbnailError.invalidConfiguration
        }
    }

    /// Returns estimated storage size for thumbnails
    func estimatedStorageSize(for duration: Double) -> Int64 {
        let totalThumbnails = Int(ceil(duration / interval))
        let bytesPerThumbnail = Int64(width * height) * Int64(quality.rawValue) / 10
        return Int64(totalThumbnails) * bytesPerThumbnail
    }
}
