// File: examples/thumbnail_generation.swift
// Purpose: Complete examples for thumbnail generation in Adaptix
// Usage: swift thumbnail_generation.swift
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.

import Foundation

// MARK: - Example 1: Basic Thumbnail Generation

func example1_basicUsage() {
    print("📸 Example 1: Basic Thumbnail Generation\n")

    let mediaProber = MediaProber()
    let thumbnailGenerator = ThumbnailGenerator(mediaProber: mediaProber)

    let inputPath = "/path/to/video.mp4"
    let outputDirectory = "/path/to/output/thumbnails"

    do {
        // Generate thumbnails with standard preset
        let (spriteSheets, vttPath) = try thumbnailGenerator.generateThumbnailsAuto(
            inputPath: inputPath,
            outputDirectory: outputDirectory,
            preset: .standard
        )

        print("✅ Success!")
        print("   Generated \(spriteSheets.count) sprite sheet(s)")
        print("   WebVTT file: \(vttPath)")

        // Display sprite sheet details
        for (index, sheet) in spriteSheets.enumerated() {
            print("\n   Sprite Sheet \(index + 1):")
            print("   - File: \(sheet.filePath)")
            print("   - Thumbnails: \(sheet.thumbnailCount)")
            print("   - Time range: \(sheet.startTime)s - \(sheet.endTime)s")
            print("   - Grid: \(sheet.gridSize.columns)x\(sheet.gridSize.rows)")
        }

    } catch {
        print("❌ Error: \(error)")
    }
}

// MARK: - Example 2: Custom Configuration

func example2_customConfiguration() {
    print("\n📸 Example 2: Custom Thumbnail Configuration\n")

    let mediaProber = MediaProber()
    let thumbnailGenerator = ThumbnailGenerator(mediaProber: mediaProber)

    // Create custom configuration
    let customConfig = ThumbnailConfig(
        interval: 3.0,              // Thumbnail every 3 seconds
        width: 200,                 // 200px wide
        height: 113,                // 113px high (16:9 ratio)
        columns: 4,                 // 4 columns
        rows: 3,                    // 3 rows (12 thumbnails per sheet)
        quality: .high,             // High quality
        format: .jpeg,              // JPEG format
        preserveAspectRatio: true   // Maintain aspect ratio
    )

    let inputPath = "/path/to/video.mp4"
    let outputDirectory = "/path/to/output/custom_thumbnails"

    do {
        // Validate configuration before using
        try customConfig.validate()
        print("✅ Configuration is valid")

        // Estimate storage size
        let mediaInfo = try mediaProber.probe(inputPath)
        let estimatedSize = customConfig.estimatedStorageSize(for: mediaInfo.duration)
        let sizeMB = Double(estimatedSize) / 1_048_576
        print("📦 Estimated storage: \(String(format: "%.2f", sizeMB)) MB")

        // Generate thumbnails
        let (spriteSheets, vttPath) = try thumbnailGenerator.generateThumbnails(
            inputPath: inputPath,
            outputDirectory: outputDirectory,
            config: customConfig
        )

        print("\n✅ Custom thumbnails generated!")
        print("   Sprite sheets: \(spriteSheets.count)")
        print("   WebVTT: \(vttPath)")

    } catch {
        print("❌ Error: \(error)")
    }
}

// MARK: - Example 3: All Presets Comparison

func example3_comparePresets() {
    print("\n📸 Example 3: Compare All Presets\n")

    let mediaProber = MediaProber()
    let thumbnailGenerator = ThumbnailGenerator(mediaProber: mediaProber)

    let inputPath = "/path/to/video.mp4"
    let baseOutputDir = "/path/to/output/presets"

    let presets: [ThumbnailPreset] = [.fast, .standard, .detailed, .maximum]

    for preset in presets {
        let presetName = String(describing: preset)
        print("🔧 Testing preset: \(presetName)")

        let outputDir = "\(baseOutputDir)/\(presetName)"

        do {
            let startTime = Date()

            let (spriteSheets, vttPath) = try thumbnailGenerator.generateThumbnailsAuto(
                inputPath: inputPath,
                outputDirectory: outputDir,
                preset: preset
            )

            let duration = Date().timeIntervalSince(startTime)

            // Calculate total size
            var totalSize: Int64 = 0
            for sheet in spriteSheets {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: sheet.filePath),
                   let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
            let sizeMB = Double(totalSize) / 1_048_576

            print("   ✅ Complete in \(String(format: "%.1f", duration))s")
            print("   📊 Sprites: \(spriteSheets.count), Size: \(String(format: "%.2f", sizeMB)) MB")

        } catch {
            print("   ❌ Error: \(error)")
        }
    }
}

// MARK: - Example 4: Batch Processing

func example4_batchProcessing() {
    print("\n📸 Example 4: Batch Thumbnail Generation\n")

    let mediaProber = MediaProber()
    let thumbnailGenerator = ThumbnailGenerator(mediaProber: mediaProber)

    let inputVideos = [
        "/path/to/video1.mp4",
        "/path/to/video2.mp4",
        "/path/to/video3.mp4"
    ]

    let outputDirectory = "/path/to/output/batch"
    let config = ThumbnailPreset.configuration(for: .standard)

    do {
        print("Processing \(inputVideos.count) videos...\n")

        let results = try thumbnailGenerator.batchGenerateThumbnails(
            inputPaths: inputVideos,
            outputDirectory: outputDirectory,
            config: config
        )

        print("\n✅ Batch processing complete!\n")

        for (index, result) in results.enumerated() {
            let videoName = URL(fileURLWithPath: result.input).lastPathComponent
            print("Video \(index + 1): \(videoName)")
            print("  - Sprites: \(result.spriteSheets.count)")
            print("  - VTT: \(URL(fileURLWithPath: result.vttPath).lastPathComponent)")
        }

    } catch {
        print("❌ Error: \(error)")
    }
}

// MARK: - Example 5: Integration with Encoding Workflow

func example5_encodingWorkflow() {
    print("\n📸 Example 5: Complete Encoding + Thumbnails Workflow\n")

    let ffmpegController = FFmpegController.shared
    let mediaProber = MediaProber()
    let thumbnailGenerator = ThumbnailGenerator(
        mediaProber: mediaProber,
        ffmpegController: ffmpegController
    )
    let manifestGenerator = ManifestGenerator()

    let inputPath = "/path/to/video.mp4"
    let outputDirectory = "/path/to/output/complete"

    do {
        // 1. Analyze input
        print("🔍 Analyzing input video...")
        let mediaInfo = try mediaProber.probe(inputPath)
        print("   Duration: \(mediaInfo.duration)s")
        print("   Video: \(mediaInfo.videoStreams.count) stream(s)")
        print("   Audio: \(mediaInfo.audioStreams.count) stream(s)")

        // 2. Select encoding profile
        print("\n⚙️  Using Apple HLS profile...")
        let profile = DefaultProfiles.appleHLS()

        // 3. Encode video (simplified)
        print("\n🎬 Encoding video...")
        // ... (encoding logic would go here) ...

        // 4. Generate thumbnails
        print("\n📸 Generating thumbnails...")
        let (spriteSheets, vttPath) = try thumbnailGenerator.generateThumbnailsAuto(
            inputPath: inputPath,
            outputDirectory: "\(outputDirectory)/thumbnails",
            preset: .standard
        )

        print("   ✅ Generated \(spriteSheets.count) sprite sheets")

        // 5. Generate manifest with thumbnail track
        print("\n📄 Generating HLS manifest...")
        var streams: [MediaStreamDescriptor] = []

        // Add video streams (example)
        streams.append(MediaStreamDescriptor(
            type: "video",
            codec: "h264",
            language: nil,
            uri: "video_1080p.m3u8",
            resolution: "1920x1080",
            bitrate: 4500,
            frameRate: 30.0,
            channels: nil,
            segmentDuration: 6.0
        ))

        // Add audio streams (example)
        streams.append(MediaStreamDescriptor(
            type: "audio",
            codec: "aac",
            language: "en",
            uri: "audio_en_192k.m3u8",
            resolution: nil,
            bitrate: 192,
            frameRate: nil,
            channels: 2,
            segmentDuration: 6.0
        ))

        try manifestGenerator.generateHLSManifest(
            streams: streams,
            outputPath: "\(outputDirectory)/master.m3u8"
        )

        print("\n✅ Complete workflow finished!")
        print("   📁 Output: \(outputDirectory)")
        print("   📄 Manifest: master.m3u8")
        print("   🖼️  Thumbnails: thumbnails/thumbnails.vtt")

    } catch {
        print("❌ Error: \(error)")
    }
}

// MARK: - Example 6: Player Integration Configs

func example6_playerIntegration() {
    print("\n📸 Example 6: Generate Player Integration Configs\n")

    let mediaProber = MediaProber()
    let thumbnailGenerator = ThumbnailGenerator(mediaProber: mediaProber)

    let inputPath = "/path/to/video.mp4"
    let outputDirectory = "/path/to/output/player_integration"

    do {
        let (spriteSheets, vttPath) = try thumbnailGenerator.generateThumbnailsAuto(
            inputPath: inputPath,
            outputDirectory: outputDirectory,
            preset: .standard
        )

        // Generate Video.js config
        print("📺 Video.js Configuration:")
        let videojsConfig = thumbnailGenerator.generateVideoJSConfig(
            spriteSheets: spriteSheets,
            vttPath: vttPath
        )
        if let jsonData = try? JSONSerialization.data(withJSONObject: videojsConfig, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }

        // Generate Shaka Player config
        print("\n📺 Shaka Player Configuration:")
        let shakaConfig = thumbnailGenerator.generateShakaConfig(
            spriteSheets: spriteSheets,
            vttPath: vttPath
        )
        if let jsonData = try? JSONSerialization.data(withJSONObject: shakaConfig, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }

        // Generate JW Player config
        print("\n📺 JW Player Configuration:")
        let jwConfig = thumbnailGenerator.generateJWPlayerConfig(
            spriteSheets: spriteSheets,
            vttPath: vttPath
        )
        if let jsonData = try? JSONSerialization.data(withJSONObject: jwConfig, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }

    } catch {
        print("❌ Error: \(error)")
    }
}

// MARK: - Example 7: Different Formats Comparison

func example7_formatComparison() {
    print("\n📸 Example 7: Compare Image Formats\n")

    let mediaProber = MediaProber()
    let thumbnailGenerator = ThumbnailGenerator(mediaProber: mediaProber)

    let inputPath = "/path/to/video.mp4"
    let baseOutputDir = "/path/to/output/formats"

    let formats: [(ThumbnailConfig.ThumbnailFormat, String)] = [
        (.jpeg, "JPEG"),
        (.png, "PNG"),
        (.webp, "WebP")
    ]

    for (format, name) in formats {
        print("🖼️  Testing format: \(name)")

        let config = ThumbnailConfig(
            interval: 5.0,
            width: 160,
            height: 90,
            columns: 5,
            rows: 5,
            quality: .high,
            format: format,
            preserveAspectRatio: true
        )

        let outputDir = "\(baseOutputDir)/\(name.lowercased())"

        do {
            let (spriteSheets, _) = try thumbnailGenerator.generateThumbnails(
                inputPath: inputPath,
                outputDirectory: outputDir,
                config: config
            )

            // Calculate total size
            var totalSize: Int64 = 0
            for sheet in spriteSheets {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: sheet.filePath),
                   let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
            let sizeMB = Double(totalSize) / 1_048_576

            print("   ✅ Size: \(String(format: "%.2f", sizeMB)) MB")

        } catch {
            print("   ❌ Error: \(error)")
        }
    }
}

// MARK: - Main Execution

print("""
╔═══════════════════════════════════════════════════════╗
║        Adaptix Thumbnail Generation Examples          ║
║                                                       ║
║  Demonstrates various thumbnail generation            ║
║  scenarios and configurations                         ║
╚═══════════════════════════════════════════════════════╝
""")

// Uncomment the examples you want to run:

// example1_basicUsage()
// example2_customConfiguration()
// example3_comparePresets()
// example4_batchProcessing()
// example5_encodingWorkflow()
// example6_playerIntegration()
// example7_formatComparison()

print("\n✨ Examples complete!")
