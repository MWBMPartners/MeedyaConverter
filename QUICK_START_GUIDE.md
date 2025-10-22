# Adaptix Quick Start Guide

**For Developers:** How to integrate the core modules into your UI

---

## 🚀 Basic Usage

### 1. Initialize Controllers

```swift
import Foundation

// Initialize the main controllers
let ffmpegController = FFmpegController.shared
let mediaProber = MediaProber()
let audioProcessor = AudioProcessor(mediaProber: mediaProber)
let subtitleManager = SubtitleManager(mediaProber: mediaProber)
let manifestGenerator = ManifestGenerator()
let encryptionHandler = EncryptionHandler(outputDirectory: "/path/to/output")
```

### 2. Analyze Input Media

```swift
// Probe the input file
let inputPath = "/path/to/input/video.mp4"

do {
    let mediaInfo = try mediaProber.probe(inputPath)

    print("Duration: \(mediaInfo.duration) seconds")
    print("Video streams: \(mediaInfo.videoStreams.count)")
    print("Audio streams: \(mediaInfo.audioStreams.count)")
    print("Subtitle streams: \(mediaInfo.subtitleStreams.count)")

    // Check for HDR
    if let hdr = mediaInfo.videoStreams.first?.hdrMetadata {
        print("HDR Type: \(hdr.type)")
    }

    // Get suggested bitrate ladder
    let bitrates = mediaProber.suggestBitrateLadder(for: mediaInfo)
    print("Suggested bitrates: \(bitrates)")

} catch {
    print("Error probing media: \(error)")
}
```

### 3. Select or Create Encoding Profile

```swift
// Use a default profile
let profile = DefaultProfiles.appleHLS()

// Or create custom profile
let customProfile = EncodingProfile(
    id: UUID(),
    name: "Custom Profile",
    description: "My custom encoding profile",
    videoSettings: VideoSettings(
        codec: "h264",
        bitrateLadder: [4500, 3000, 2000, 1000],
        crf: 23,
        maxBitrate: 5000,
        retainHDR: false,
        watermark: nil,
        multipass: true
    ),
    audioSettings: AudioSettings(
        codec: "aac",
        bitrates: [192, 128, 64],
        normalization: true,
        replayGain: false,
        downmixToStereo: false
    ),
    subtitleSettings: SubtitleSettings(
        supportedFormats: ["webvtt"],
        embedCEA608: false
    ),
    outputFormat: "mp4",
    splitAudioVideo: true,
    encryption: nil,
    profile: nil
)
```

### 4. Build FFmpeg Arguments

```swift
let outputPath = "/path/to/output"

// Build video encoding arguments
let videoArgs = FFmpegArgumentBuilder.buildVideoArguments(from: customProfile)

// Build audio encoding arguments
let audioArgs = FFmpegArgumentBuilder.buildAudioArguments(from: customProfile)

// Or use AudioProcessor for multi-track
let audioConfigs = AudioProcessor.createStreamingPresets(
    language: "en",
    outputDirectory: outputPath
)
```

### 5. Create Encoding Jobs

```swift
// Create a video encoding job
let videoJob = EncodingJob(
    inputPath: inputPath,
    outputPath: "\(outputPath)/video_1080p.mp4",
    arguments: videoArgs,
    profile: customProfile
)

// Add job to queue
ffmpegController.addJob(videoJob)

// Or create batch jobs for all audio tracks
let audioJobs = try audioProcessor.createBatchJobs(
    inputPath: inputPath,
    outputConfigs: audioConfigs,
    outputDirectory: outputPath
)

ffmpegController.addJobs(audioJobs)
```

### 6. Monitor Progress

```swift
// Subscribe to progress updates
ffmpegController.$currentProgress
    .sink { progress in
        print("Progress: \(progress.percentage)%")
        print("FPS: \(progress.fps)")
        print("Bitrate: \(progress.bitrate)")
        print("Speed: \(progress.speed)")

        if let eta = progress.estimatedTimeRemaining {
            print("ETA: \(eta) seconds")
        }
    }
    .store(in: &cancellables)

// Monitor job status
ffmpegController.$currentJob
    .sink { job in
        if let job = job {
            print("Current job: \(job.inputPath)")
            print("Status: \(job.status)")
            print("Progress: \(job.progress * 100)%")
        }
    }
    .store(in: &cancellables)
```

### 7. Generate Manifests

```swift
// After encoding completes, generate HLS manifest
let streams: [MediaStreamDescriptor] = [
    MediaStreamDescriptor(
        type: "video",
        codec: "h264",
        language: nil,
        uri: "video_1080p.m3u8",
        resolution: "1920x1080",
        bitrate: 4500,
        frameRate: 30.0,
        channels: nil,
        segmentDuration: 6.0
    ),
    MediaStreamDescriptor(
        type: "audio",
        codec: "aac",
        language: "en",
        uri: "audio_en_192k.m3u8",
        resolution: nil,
        bitrate: 192,
        frameRate: nil,
        channels: 2,
        segmentDuration: 6.0
    )
]

try manifestGenerator.generateHLSManifest(
    streams: streams,
    outputPath: "\(outputPath)/master.m3u8"
)

// Generate DASH manifest
try manifestGenerator.generateDASHManifest(
    streams: streams,
    outputPath: "\(outputPath)/manifest.mpd",
    duration: 120.0 // duration in seconds
)
```

### 8. Optional: Add Encryption

```swift
// Generate encryption key
let key = encryptionHandler.createEncryptionKey(expirationDays: 30)

// Create key info file for HLS
let keyURI = "https://your-server.com/keys/key_\(key.id).key"
let keyInfoPath = try encryptionHandler.generateHLSKeyInfo(
    key: key,
    keyURI: keyURI
)

// Add encryption args to FFmpeg command
let encryptionArgs = encryptionHandler.generateFFmpegEncryptionArgs(
    keyInfoPath: keyInfoPath,
    segmentDuration: 6
)

// Append to your video encoding arguments
var encryptedArgs = videoArgs + encryptionArgs
```

---

## 🎛️ Complete Example: Encode Video with Multiple Audio Tracks

```swift
import Foundation
import Combine

class EncodingWorkflow {
    let ffmpegController = FFmpegController.shared
    let mediaProber = MediaProber()
    let audioProcessor: AudioProcessor
    let manifestGenerator = ManifestGenerator()
    var cancellables = Set<AnyCancellable>()

    init() {
        self.audioProcessor = AudioProcessor(mediaProber: mediaProber)
    }

    func encodeVideo(inputPath: String, outputDirectory: String) async throws {
        // 1. Analyze input
        let mediaInfo = try mediaProber.probe(inputPath)
        print("Found \(mediaInfo.videoStreams.count) video streams")
        print("Found \(mediaInfo.audioStreams.count) audio streams")

        // 2. Select profile
        let profile = DefaultProfiles.appleHLS()

        // 3. Create output directory
        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )

        // 4. Encode video streams
        var streamDescriptors: [MediaStreamDescriptor] = []

        for (index, bitrate) in profile.videoSettings!.bitrateLadder.enumerated() {
            let resolution = calculateResolution(for: bitrate)
            let outputPath = "\(outputDirectory)/video_\(bitrate)k.mp4"

            let videoJob = EncodingJob(
                inputPath: inputPath,
                outputPath: outputPath,
                arguments: buildVideoArgs(
                    input: inputPath,
                    bitrate: bitrate,
                    resolution: resolution,
                    output: outputPath
                ),
                profile: profile
            )

            ffmpegController.addJob(videoJob)

            streamDescriptors.append(MediaStreamDescriptor(
                type: "video",
                codec: profile.videoSettings!.codec,
                language: nil,
                uri: "video_\(bitrate)k.m3u8",
                resolution: resolution,
                bitrate: bitrate,
                frameRate: 30.0,
                channels: nil,
                segmentDuration: 6.0
            ))
        }

        // 5. Encode audio streams
        for (index, audioStream) in mediaInfo.audioStreams.enumerated() {
            let language = audioStream.language ?? "und"

            for bitrate in profile.audioSettings!.bitrates {
                let outputPath = "\(outputDirectory)/audio_\(index)_\(language)_\(bitrate)k.m4a"

                let audioConfig = AudioEncodingConfig(
                    codec: .aac,
                    bitrate: bitrate,
                    sampleRate: 48000,
                    channels: 2,
                    channelLayout: "stereo",
                    language: language,
                    normalization: NormalizationConfig(
                        enabled: true,
                        standard: .ebu128,
                        targetLevel: -23.0,
                        truePeak: -2.0
                    ),
                    outputPath: outputPath
                )

                let audioArgs = audioProcessor.buildFFmpegArguments(
                    inputPath: inputPath,
                    streamIndex: audioStream.index,
                    config: audioConfig,
                    outputPath: outputPath
                )

                let audioJob = EncodingJob(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    arguments: audioArgs
                )

                ffmpegController.addJob(audioJob)

                streamDescriptors.append(MediaStreamDescriptor(
                    type: "audio",
                    codec: "aac",
                    language: language,
                    uri: "audio_\(index)_\(language)_\(bitrate)k.m3u8",
                    resolution: nil,
                    bitrate: bitrate,
                    frameRate: nil,
                    channels: 2,
                    segmentDuration: 6.0
                ))
            }
        }

        // 6. Wait for all jobs to complete
        await waitForCompletion()

        // 7. Generate manifests
        try manifestGenerator.generateHLSManifest(
            streams: streamDescriptors,
            outputPath: "\(outputDirectory)/master.m3u8"
        )

        try manifestGenerator.generateDASHManifest(
            streams: streamDescriptors,
            outputPath: "\(outputDirectory)/manifest.mpd",
            duration: mediaInfo.duration
        )

        print("✅ Encoding complete!")
        print("📁 Output: \(outputDirectory)")
    }

    private func waitForCompletion() async {
        // Wait until all jobs are done
        await withCheckedContinuation { continuation in
            ffmpegController.$isProcessing
                .sink { isProcessing in
                    if !isProcessing {
                        continuation.resume()
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func buildVideoArgs(input: String, bitrate: Int, resolution: String, output: String) -> [String] {
        return [
            "-i", input,
            "-c:v", "libx264",
            "-b:v", "\(bitrate)k",
            "-s", resolution,
            "-preset", "medium",
            "-g", "48",
            "-keyint_min", "48",
            "-sc_threshold", "0",
            output
        ]
    }

    private func calculateResolution(for bitrate: Int) -> String {
        switch bitrate {
        case 8000...: return "1920x1080"
        case 4500...: return "1920x1080"
        case 3000...: return "1280x720"
        case 2000...: return "1280x720"
        case 1000...: return "854x480"
        case 500...: return "640x360"
        default: return "426x240"
        }
    }
}

// Usage
let workflow = EncodingWorkflow()
try await workflow.encodeVideo(
    inputPath: "/path/to/input.mp4",
    outputDirectory: "/path/to/output"
)
```

---

## 🎨 UI Integration Tips

### SwiftUI Example

```swift
import SwiftUI

struct EncodingView: View {
    @StateObject var controller = FFmpegController.shared

    var body: some View {
        VStack {
            if let job = controller.currentJob {
                Text("Encoding: \(job.inputPath)")
                ProgressView(value: job.progress)
                Text("\(controller.currentProgress.percentage)%")
                Text("Speed: \(controller.currentProgress.speed)")
            }

            List(controller.jobQueue) { job in
                HStack {
                    Text(job.inputPath)
                    Spacer()
                    Text(job.status.rawValue)
                }
            }
        }
    }
}
```

### React Example (if using Electron/Tauri)

```typescript
import { useEffect, useState } from 'react';

function EncodingProgress() {
  const [progress, setProgress] = useState(0);
  const [currentJob, setCurrentJob] = useState(null);

  useEffect(() => {
    // Subscribe to backend progress updates
    window.api.onProgressUpdate((data) => {
      setProgress(data.percentage);
      setCurrentJob(data.job);
    });
  }, []);

  return (
    <div>
      {currentJob && (
        <>
          <h3>Encoding: {currentJob.inputPath}</h3>
          <progress value={progress} max={100} />
          <p>{progress}% - Speed: {currentJob.speed}</p>
        </>
      )}
    </div>
  );
}
```

---

## 🔧 Configuration

### FFmpeg Path

```swift
// Set custom FFmpeg path
ffmpegController.setFFmpegPath("/custom/path/to/ffmpeg")

// Validate installation
if ffmpegController.validateFFmpegInstallation() {
    print("✅ FFmpeg is properly installed")
} else {
    print("❌ FFmpeg not found or invalid")
}
```

### Profile Management

```swift
// Get all available profiles
let allProfiles = DefaultProfiles.allProfiles()

// Get profiles by category
let streamingProfiles = DefaultProfiles.profiles(for: .streaming)
let audioProfiles = DefaultProfiles.profiles(for: .audio)

// Validate profile
do {
    try profile.validate()
    print("✅ Profile is valid")
} catch {
    print("❌ Profile validation failed: \(error)")
}
```

---

## 📝 Error Handling

All modules use Swift error handling:

```swift
// Example error handling
do {
    let mediaInfo = try mediaProber.probe(inputPath)
    let jobs = try audioProcessor.createBatchJobs(
        inputPath: inputPath,
        outputConfigs: configs,
        outputDirectory: outputPath
    )
} catch ProbeError.fileNotFound(let path) {
    print("File not found: \(path)")
} catch AudioProcessingError.noAudioStreams {
    print("No audio streams in file")
} catch {
    print("Unexpected error: \(error)")
}
```

---

## 🧪 Testing

### Test with Sample Media

```swift
// Quick test with fast encoding
let testProfile = DefaultProfiles.fastTest()
let job = EncodingJob(
    inputPath: "test.mp4",
    outputPath: "test_output.mp4",
    arguments: FFmpegArgumentBuilder.buildVideoArguments(from: testProfile)
)

ffmpegController.addJob(job)
```

---

## 📚 Further Reading

- `IMPLEMENTATION_STATUS.md` - Full implementation status
- `core/README.md` - Core module documentation
- Individual Swift files - Detailed API documentation in comments

---

## 🆘 Common Issues

### FFmpeg Not Found
```swift
// Check FFmpeg installation
if !ffmpegController.validateFFmpegInstallation() {
    print("Please install FFmpeg:")
    print("macOS: brew install ffmpeg")
    print("Windows: Download from ffmpeg.org")
    print("Linux: sudo apt install ffmpeg")
}
```

### Job Stuck in Queue
```swift
// Check if processing
if !ffmpegController.isProcessing {
    print("Queue is not processing. Check FFmpeg installation.")
}

// View FFmpeg logs
for log in ffmpegController.ffmpegLog {
    print(log)
}
```

### Encoding Fails
```swift
// Check completed jobs for errors
for job in ffmpegController.completedJobs where job.status == .failed {
    print("Failed job: \(job.inputPath)")
    print("Error: \(job.error ?? "Unknown")")
}
```

---

**Ready to build the UI? All the core functionality is waiting for you!** 🚀
