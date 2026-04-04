// ============================================================================
// MeedyaConverter — SceneDetector
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - SceneChange

/// A detected scene change in a video.
public struct SceneChange: Codable, Sendable {
    /// Timestamp of the scene change in seconds.
    public var timestamp: TimeInterval

    /// Scene change confidence score (0.0–1.0).
    public var score: Double

    /// Frame number where the scene change occurs.
    public var frameNumber: Int?

    public init(timestamp: TimeInterval, score: Double, frameNumber: Int? = nil) {
        self.timestamp = timestamp
        self.score = score
        self.frameNumber = frameNumber
    }

    /// Formatted timestamp string (HH:MM:SS.mmm).
    public var formattedTimestamp: String {
        let hours = Int(timestamp) / 3600
        let minutes = (Int(timestamp) % 3600) / 60
        let seconds = Int(timestamp) % 60
        let millis = Int((timestamp.truncatingRemainder(dividingBy: 1.0)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }
}

// MARK: - Chapter

/// A chapter marker for a media file.
public struct Chapter: Codable, Sendable {
    /// Chapter title.
    public var title: String

    /// Start timestamp in seconds.
    public var startTime: TimeInterval

    /// End timestamp in seconds (nil if last chapter, extends to end of file).
    public var endTime: TimeInterval?

    public init(title: String, startTime: TimeInterval, endTime: TimeInterval? = nil) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Formatted start time (HH:MM:SS).
    public var formattedStartTime: String {
        let hours = Int(startTime) / 3600
        let minutes = (Int(startTime) % 3600) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - ChapterGenerationStrategy

/// Strategy for generating chapters from scene changes.
public enum ChapterGenerationStrategy: String, Codable, Sendable {
    /// Create a chapter at every detected scene change (filtered by minimum duration).
    case everyScene = "every_scene"

    /// Create chapters at fixed intervals (e.g., every 5 minutes).
    case fixedInterval = "fixed_interval"

    /// Only create chapters at high-confidence scene changes.
    case keyScenes = "key_scenes"

    /// Combine fixed intervals with significant scene changes.
    case combined = "combined"
}

// MARK: - SceneDetectionResult

/// The result of scene detection analysis.
public struct SceneDetectionResult: Sendable {
    /// All detected scene changes.
    public let sceneChanges: [SceneChange]

    /// The detection threshold used.
    public let threshold: Double

    /// Total video duration in seconds.
    public let duration: TimeInterval

    /// Number of detected scenes.
    public var sceneCount: Int { sceneChanges.count }

    /// Average scene duration in seconds.
    public var averageSceneDuration: TimeInterval {
        guard sceneCount > 0, duration > 0 else { return 0 }
        return duration / Double(sceneCount + 1)
    }
}

// MARK: - SceneDetector

/// Detects scene changes in video files using FFmpeg's scene detection filter
/// and generates chapter markers from detected boundaries.
///
/// Supports configurable sensitivity, minimum chapter duration, and multiple
/// chapter generation strategies.
///
/// Phase 7.13
public struct SceneDetector: Sendable {

    /// Build FFmpeg arguments for scene detection.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the video file.
    ///   - threshold: Scene change sensitivity (0.0–1.0). Lower = more sensitive.
    ///     Default 0.3 is good for most content.
    /// - Returns: FFmpeg argument array.
    public static func buildDetectionArguments(
        inputPath: String,
        threshold: Double = 0.3
    ) -> [String] {
        return [
            "-i", inputPath,
            "-vf", "select='gt(scene,\(String(format: "%.2f", threshold)))',showinfo",
            "-vsync", "vfr",
            "-f", "null",
            "-hide_banner",
            "-"
        ]
    }

    /// Parse scene change timestamps from FFmpeg showinfo output.
    ///
    /// FFmpeg outputs lines like:
    /// `[Parsed_showinfo_1 @ 0x...] n:  42 pts: 123456 pts_time:5.123 ...`
    public static func parseSceneChanges(from output: String, threshold: Double = 0.3) -> [SceneChange] {
        var changes: [SceneChange] = []

        let lines = output.split(separator: "\n")
        for line in lines {
            guard line.contains("showinfo") && line.contains("pts_time:") else { continue }
            let str = String(line)

            // Extract pts_time
            guard let ptsRange = str.range(of: "pts_time:") else { continue }
            let afterPts = str[ptsRange.upperBound...]
            let timeStr = afterPts.prefix(while: { $0.isNumber || $0 == "." || $0 == "-" })
            guard let timestamp = Double(timeStr) else { continue }

            // Extract frame number (n: N)
            var frameNumber: Int?
            if let nRange = str.range(of: "n:") {
                let afterN = str[nRange.upperBound...].drop(while: { $0 == " " })
                let nStr = afterN.prefix(while: { $0.isNumber })
                frameNumber = Int(nStr)
            }

            changes.append(SceneChange(
                timestamp: timestamp,
                score: threshold, // Scene passed the threshold
                frameNumber: frameNumber
            ))
        }

        return changes.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Chapter Generation

    /// Generate chapters from scene detection results.
    ///
    /// - Parameters:
    ///   - sceneChanges: Detected scene changes.
    ///   - duration: Total video duration in seconds.
    ///   - strategy: Chapter generation strategy.
    ///   - minimumDuration: Minimum chapter duration in seconds (to avoid micro-chapters).
    ///   - fixedInterval: Interval in seconds for fixed-interval strategy.
    ///   - titlePrefix: Prefix for auto-generated chapter titles.
    /// - Returns: Array of chapters.
    public static func generateChapters(
        from sceneChanges: [SceneChange],
        duration: TimeInterval,
        strategy: ChapterGenerationStrategy = .everyScene,
        minimumDuration: TimeInterval = 30.0,
        fixedInterval: TimeInterval = 300.0,
        titlePrefix: String = "Chapter"
    ) -> [Chapter] {
        switch strategy {
        case .everyScene:
            return chaptersFromScenes(
                sceneChanges, duration: duration,
                minimumDuration: minimumDuration, titlePrefix: titlePrefix
            )
        case .fixedInterval:
            return chaptersAtFixedInterval(
                duration: duration, interval: fixedInterval, titlePrefix: titlePrefix
            )
        case .keyScenes:
            // Only use scenes with highest scores (top 50%)
            let sorted = sceneChanges.sorted { $0.score > $1.score }
            let keyScenes = Array(sorted.prefix(max(1, sorted.count / 2)))
                .sorted { $0.timestamp < $1.timestamp }
            return chaptersFromScenes(
                keyScenes, duration: duration,
                minimumDuration: minimumDuration, titlePrefix: titlePrefix
            )
        case .combined:
            return combinedChapters(
                sceneChanges: sceneChanges, duration: duration,
                interval: fixedInterval, minimumDuration: minimumDuration,
                titlePrefix: titlePrefix
            )
        }
    }

    /// Generate FFmetadata chapter format for embedding in containers.
    ///
    /// Output format:
    /// ```
    /// ;FFMETADATA1
    /// [CHAPTER]
    /// TIMEBASE=1/1000
    /// START=0
    /// END=5123
    /// title=Chapter 1
    /// ```
    public static func generateFFmetadata(chapters: [Chapter], duration: TimeInterval) -> String {
        var output = ";FFMETADATA1\n"

        for (index, chapter) in chapters.enumerated() {
            let startMs = Int(chapter.startTime * 1000)
            let endMs: Int
            if let end = chapter.endTime {
                endMs = Int(end * 1000)
            } else if index + 1 < chapters.count {
                endMs = Int(chapters[index + 1].startTime * 1000)
            } else {
                endMs = Int(duration * 1000)
            }

            output += "\n[CHAPTER]\n"
            output += "TIMEBASE=1/1000\n"
            output += "START=\(startMs)\n"
            output += "END=\(endMs)\n"
            output += "title=\(chapter.title)\n"
        }

        return output
    }

    /// Generate OGG-style chapter list.
    ///
    /// Format: `CHAPTER01=00:00:00.000\nCHAPTER01NAME=Chapter 1\n`
    public static func generateOGGChapters(chapters: [Chapter]) -> String {
        var output = ""
        for (index, chapter) in chapters.enumerated() {
            let num = String(format: "%02d", index + 1)
            output += "CHAPTER\(num)=\(chapter.formattedStartTime).000\n"
            output += "CHAPTER\(num)NAME=\(chapter.title)\n"
        }
        return output
    }

    // MARK: - Private Helpers

    private static func chaptersFromScenes(
        _ scenes: [SceneChange],
        duration: TimeInterval,
        minimumDuration: TimeInterval,
        titlePrefix: String
    ) -> [Chapter] {
        var chapters: [Chapter] = []

        // Always start with a chapter at 0
        chapters.append(Chapter(title: "\(titlePrefix) 1", startTime: 0))

        var lastChapterTime: TimeInterval = 0
        var chapterIndex = 2

        for scene in scenes {
            // Skip scenes too close to the previous chapter
            guard scene.timestamp - lastChapterTime >= minimumDuration else { continue }
            // Skip scenes too close to the end
            guard duration - scene.timestamp >= minimumDuration else { continue }

            chapters.append(Chapter(
                title: "\(titlePrefix) \(chapterIndex)",
                startTime: scene.timestamp
            ))
            lastChapterTime = scene.timestamp
            chapterIndex += 1
        }

        // Set end times
        for i in 0..<chapters.count {
            if i + 1 < chapters.count {
                chapters[i].endTime = chapters[i + 1].startTime
            } else {
                chapters[i].endTime = duration
            }
        }

        return chapters
    }

    private static func chaptersAtFixedInterval(
        duration: TimeInterval,
        interval: TimeInterval,
        titlePrefix: String
    ) -> [Chapter] {
        var chapters: [Chapter] = []
        var time: TimeInterval = 0
        var index = 1

        while time < duration {
            let endTime = min(time + interval, duration)
            chapters.append(Chapter(
                title: "\(titlePrefix) \(index)",
                startTime: time,
                endTime: endTime
            ))
            time += interval
            index += 1
        }

        return chapters
    }

    private static func combinedChapters(
        sceneChanges: [SceneChange],
        duration: TimeInterval,
        interval: TimeInterval,
        minimumDuration: TimeInterval,
        titlePrefix: String
    ) -> [Chapter] {
        // Start with fixed interval chapters
        var timestamps: Set<TimeInterval> = [0]

        // Add fixed interval points
        var t = interval
        while t < duration {
            timestamps.insert(t)
            t += interval
        }

        // Add significant scene changes (snap to nearest if close to an interval)
        for scene in sceneChanges {
            let nearestInterval = timestamps.min(by: { abs($0 - scene.timestamp) < abs($1 - scene.timestamp) })
            if let nearest = nearestInterval, abs(nearest - scene.timestamp) < minimumDuration {
                // Close to an existing chapter — replace with scene boundary
                timestamps.remove(nearest)
            }
            timestamps.insert(scene.timestamp)
        }

        // Sort and create chapters
        let sorted = timestamps.sorted()
        var chapters: [Chapter] = []

        for (index, time) in sorted.enumerated() {
            let endTime = index + 1 < sorted.count ? sorted[index + 1] : duration
            // Skip micro-chapters
            guard endTime - time >= minimumDuration || index == 0 else { continue }
            chapters.append(Chapter(
                title: "\(titlePrefix) \(chapters.count + 1)",
                startTime: time,
                endTime: endTime
            ))
        }

        return chapters
    }
}
