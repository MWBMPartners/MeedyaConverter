# Thumbnail Generation Guide

Complete guide to generating video preview thumbnails with Adaptix.

---

## Overview

The ThumbnailGenerator creates sprite sheets and WebVTT tracks for video preview scrubbing, compatible with:
- **Video.js**
- **Shaka Player**
- **JW Player**
- **Plyr**
- **Custom HTML5 players**

---

## Quick Start

### Basic Usage

```swift
import Foundation

// Initialize
let mediaProber = MediaProber()
let thumbnailGenerator = ThumbnailGenerator(mediaProber: mediaProber)

// Generate thumbnails with default settings
let (spriteSheets, vttPath) = try thumbnailGenerator.generateThumbnailsAuto(
    inputPath: "/path/to/video.mp4",
    outputDirectory: "/path/to/output/thumbnails",
    preset: .standard
)

print("✅ Generated \(spriteSheets.count) sprite sheets")
print("📄 WebVTT file: \(vttPath)")
```

---

## Configuration Options

### Presets

Four built-in presets for common use cases:

#### 1. Fast Preset
- **Interval**: 10 seconds
- **Size**: 120x68 pixels
- **Grid**: 5x5 (25 thumbnails per sheet)
- **Quality**: Medium (75%)
- **Best for**: Quick preview, bandwidth-limited scenarios

```swift
let (sprites, vtt) = try thumbnailGenerator.generateThumbnailsAuto(
    inputPath: inputPath,
    outputDirectory: outputDir,
    preset: .fast
)
```

#### 2. Standard Preset (Default)
- **Interval**: 5 seconds
- **Size**: 160x90 pixels
- **Grid**: 5x5 (25 thumbnails per sheet)
- **Quality**: High (85%)
- **Best for**: Most use cases, good balance

```swift
let (sprites, vtt) = try thumbnailGenerator.generateThumbnailsAuto(
    inputPath: inputPath,
    outputDirectory: outputDir,
    preset: .standard
)
```

#### 3. Detailed Preset
- **Interval**: 2 seconds
- **Size**: 160x90 pixels
- **Grid**: 10x10 (100 thumbnails per sheet)
- **Quality**: High (85%)
- **Best for**: Detailed navigation, shorter videos

```swift
let (sprites, vtt) = try thumbnailGenerator.generateThumbnailsAuto(
    inputPath: inputPath,
    outputDirectory: outputDir,
    preset: .detailed
)
```

#### 4. Maximum Preset
- **Interval**: 1 second
- **Size**: 240x135 pixels
- **Grid**: 10x10 (100 thumbnails per sheet)
- **Quality**: Maximum (95%)
- **Best for**: High-end applications, premium content

```swift
let (sprites, vtt) = try thumbnailGenerator.generateThumbnailsAuto(
    inputPath: inputPath,
    outputDirectory: outputDir,
    preset: .maximum
)
```

---

## Custom Configuration

### Create Custom Settings

```swift
let customConfig = ThumbnailConfig(
    interval: 3.0,              // Thumbnail every 3 seconds
    width: 200,                 // 200px wide
    height: 113,                // 113px high (16:9 ratio)
    columns: 5,                 // 5 columns
    rows: 4,                    // 4 rows (20 thumbnails per sheet)
    quality: .high,             // High quality (85%)
    format: .jpeg,              // JPEG format
    preserveAspectRatio: true   // Maintain video aspect ratio
)

let (sprites, vtt) = try thumbnailGenerator.generateThumbnails(
    inputPath: inputPath,
    outputDirectory: outputDir,
    config: customConfig
)
```

### Configuration Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `interval` | Double | Seconds between thumbnails (0.5 - 60.0) |
| `width` | Int | Thumbnail width in pixels (80 - 400) |
| `height` | Int | Thumbnail height in pixels (45 - 225) |
| `columns` | Int | Number of columns in sprite (1 - 20) |
| `rows` | Int | Number of rows in sprite (1 - 20) |
| `quality` | ThumbnailQuality | `.low`, `.medium`, `.high`, `.maximum` |
| `format` | ThumbnailFormat | `.jpeg`, `.png`, `.webp` |
| `preserveAspectRatio` | Bool | Maintain original aspect ratio |

---

## Output Files

### Generated Files Structure

```
output/
├── thumbnails_0.jpg          # First sprite sheet
├── thumbnails_1.jpg          # Second sprite sheet (if needed)
├── thumbnails_2.jpg          # Third sprite sheet (if needed)
└── thumbnails.vtt            # WebVTT track file
```

### Sprite Sheet Example

Each sprite sheet contains a grid of thumbnails:

```
┌────────┬────────┬────────┬────────┬────────┐
│ 00:00  │ 00:05  │ 00:10  │ 00:15  │ 00:20  │
├────────┼────────┼────────┼────────┼────────┤
│ 00:25  │ 00:30  │ 00:35  │ 00:40  │ 00:45  │
├────────┼────────┼────────┼────────┼────────┤
│ 00:50  │ 00:55  │ 01:00  │ 01:05  │ 01:10  │
├────────┼────────┼────────┼────────┼────────┤
│ 01:15  │ 01:20  │ 01:25  │ 01:30  │ 01:35  │
├────────┼────────┼────────┼────────┼────────┤
│ 01:40  │ 01:45  │ 01:50  │ 01:55  │ 02:00  │
└────────┴────────┴────────┴────────┴────────┘
```

### WebVTT Format

The generated `thumbnails.vtt` file:

```webvtt
WEBVTT

00:00:00.000 --> 00:00:05.000
thumbnails_0.jpg#xywh=0,0,160,90

00:00:05.000 --> 00:00:10.000
thumbnails_0.jpg#xywh=160,0,160,90

00:00:10.000 --> 00:00:15.000
thumbnails_0.jpg#xywh=320,0,160,90

...
```

---

## Player Integration

### Video.js

```html
<video id="my-video" class="video-js">
  <source src="video.mp4" type="video/mp4">
  <track kind="metadata" src="thumbnails.vtt">
</video>

<script>
var player = videojs('my-video');
</script>
```

### Shaka Player

```javascript
const player = new shaka.Player(video);
player.configure({
  ui: {
    enableThumbnails: true
  }
});

// Add thumbnail track
player.addTextTrack(
  'thumbnails.vtt',
  'en',
  'metadata',
  'image/jpeg'
);
```

### JW Player

```javascript
jwplayer("myElement").setup({
  file: "video.mp4",
  tracks: [{
    file: "thumbnails.vtt",
    kind: "thumbnails"
  }]
});
```

### Custom HTML5 Player

```javascript
const video = document.getElementById('video');
const progressBar = document.getElementById('progress-bar');
const thumbnailPreview = document.getElementById('thumbnail-preview');

// Load VTT file
const track = video.addTextTrack('metadata', 'thumbnails');
track.mode = 'hidden';

fetch('thumbnails.vtt')
  .then(response => response.text())
  .then(vtt => {
    // Parse VTT and show thumbnails on hover
    progressBar.addEventListener('mousemove', (e) => {
      const time = getTimeFromMousePosition(e);
      const thumbnail = getThumbnailForTime(time, vtt);
      showThumbnail(thumbnailPreview, thumbnail);
    });
  });
```

---

## Advanced Usage

### Batch Processing

Generate thumbnails for multiple videos:

```swift
let inputVideos = [
    "/path/to/video1.mp4",
    "/path/to/video2.mp4",
    "/path/to/video3.mp4"
]

let results = try thumbnailGenerator.batchGenerateThumbnails(
    inputPaths: inputVideos,
    outputDirectory: "/path/to/output",
    config: customConfig
)

for (input, sprites, vtt) in results {
    print("✅ \(input)")
    print("   Sprites: \(sprites.count)")
    print("   VTT: \(vtt)")
}
```

### Estimate Storage Requirements

```swift
let config = ThumbnailPreset.configuration(for: .standard)
let mediaInfo = try mediaProber.probe(inputPath)

let estimatedSize = config.estimatedStorageSize(for: mediaInfo.duration)
let sizeMB = Double(estimatedSize) / 1_048_576

print("Estimated storage: \(sizeMB) MB")
```

### Validate Configuration

```swift
let config = ThumbnailConfig(...)

do {
    try config.validate()
    print("✅ Configuration is valid")
} catch {
    print("❌ Invalid configuration: \(error)")
}
```

---

## Integration with Encoding Workflow

### Generate Thumbnails After Encoding

```swift
class AdaptixWorkflow {
    let ffmpegController = FFmpegController.shared
    let mediaProber = MediaProber()
    let thumbnailGenerator: ThumbnailGenerator

    init() {
        self.thumbnailGenerator = ThumbnailGenerator(
            mediaProber: mediaProber,
            ffmpegController: ffmpegController
        )
    }

    func processVideo(inputPath: String, outputDirectory: String) async throws {
        // 1. Encode video to multiple bitrates
        let profile = DefaultProfiles.appleHLS()
        // ... encoding logic ...

        // 2. Generate thumbnails
        print("📸 Generating thumbnails...")
        let (sprites, vtt) = try thumbnailGenerator.generateThumbnailsAuto(
            inputPath: inputPath,
            outputDirectory: "\(outputDirectory)/thumbnails",
            preset: .standard
        )

        // 3. Generate manifest with thumbnail track
        let manifestGenerator = ManifestGenerator()
        // ... manifest generation with thumbnail reference ...

        print("✅ Complete!")
    }
}
```

### Add Thumbnail Track to HLS Manifest

```swift
// After generating thumbnails, add to HLS manifest
let thumbnailStream = MediaStreamDescriptor(
    type: "subtitles",
    codec: "webvtt",
    language: nil,
    uri: "thumbnails/thumbnails.vtt",
    resolution: nil,
    bitrate: 0,
    frameRate: nil,
    channels: nil,
    segmentDuration: nil
)

// Include in manifest generation
try manifestGenerator.generateHLSManifest(
    streams: videoStreams + audioStreams + [thumbnailStream],
    outputPath: "\(outputDirectory)/master.m3u8"
)
```

---

## Performance Considerations

### Optimization Tips

1. **Choose Appropriate Interval**
   - Longer intervals = fewer thumbnails = faster generation
   - Recommended: 5 seconds for most videos

2. **Grid Size**
   - Larger grids = fewer sprite sheets = better performance
   - Recommended: 5x5 (25 thumbnails) or 10x10 (100 thumbnails)

3. **Thumbnail Size**
   - Smaller thumbnails = faster generation + smaller files
   - Recommended: 160x90 for 16:9 content

4. **Quality**
   - Lower quality = smaller files + faster generation
   - Recommended: High (85%) for most cases

5. **Format**
   - JPEG: Best compression, smallest files
   - PNG: Lossless, larger files
   - WebP: Modern format, good compression (if supported)

### Performance Benchmarks

For a 1-hour 1080p video:

| Preset | Thumbnails | Sprites | Size | Generation Time |
|--------|-----------|---------|------|-----------------|
| Fast | 360 | 15 | ~5 MB | ~30 sec |
| Standard | 720 | 29 | ~12 MB | ~60 sec |
| Detailed | 1,800 | 18 | ~25 MB | ~120 sec |
| Maximum | 3,600 | 36 | ~80 MB | ~240 sec |

*Benchmarks on M1 MacBook Pro with 1080p H.264 source*

---

## Troubleshooting

### Common Issues

#### No Thumbnails Generated
```swift
// Check if video stream exists
let mediaInfo = try mediaProber.probe(inputPath)
if mediaInfo.videoStreams.isEmpty {
    print("❌ No video stream found")
}
```

#### Sprite Sheets Too Large
```swift
// Reduce grid size or thumbnail dimensions
let config = ThumbnailConfig(
    interval: 5.0,
    width: 120,      // Smaller width
    height: 68,      // Smaller height
    columns: 5,      // Keep grid size reasonable
    rows: 5,
    quality: .medium,
    format: .jpeg,
    preserveAspectRatio: true
)
```

#### Thumbnails Not Showing in Player
- Ensure WebVTT file is accessible via HTTP/HTTPS
- Check CORS headers on thumbnail files
- Verify sprite sheet paths in VTT are correct
- Ensure player supports thumbnail scrubbing

---

## Best Practices

### Recommended Settings by Video Length

| Video Length | Preset | Interval | Grid Size |
|-------------|--------|----------|-----------|
| < 5 min | Detailed | 2 sec | 10x10 |
| 5-30 min | Standard | 5 sec | 5x5 |
| 30-60 min | Standard | 5 sec | 10x10 |
| 1-2 hours | Fast | 10 sec | 10x10 |
| 2+ hours | Fast | 15 sec | 10x10 |

### CDN Deployment

1. Generate thumbnails locally
2. Upload sprite sheets and VTT to CDN
3. Update VTT paths to use CDN URLs
4. Enable caching headers for sprite sheets
5. Use WebP format if CDN supports it

---

## API Reference

### ThumbnailGenerator

```swift
class ThumbnailGenerator {
    init(mediaProber: MediaProber, ffmpegController: FFmpegController = .shared)

    // Generate thumbnails with custom config
    func generateThumbnails(
        inputPath: String,
        outputDirectory: String,
        config: ThumbnailConfig
    ) throws -> (spriteSheets: [ThumbnailSpriteSheet], vttPath: String)

    // Generate thumbnails with preset
    func generateThumbnailsAuto(
        inputPath: String,
        outputDirectory: String,
        preset: ThumbnailPreset = .standard
    ) throws -> (spriteSheets: [ThumbnailSpriteSheet], vttPath: String)

    // Batch generate for multiple videos
    func batchGenerateThumbnails(
        inputPaths: [String],
        outputDirectory: String,
        config: ThumbnailConfig
    ) throws -> [(input: String, spriteSheets: [ThumbnailSpriteSheet], vttPath: String)]

    // Player integration helpers
    func generateVideoJSConfig(spriteSheets: [ThumbnailSpriteSheet], vttPath: String) -> [String: Any]
    func generateShakaConfig(spriteSheets: [ThumbnailSpriteSheet], vttPath: String) -> [String: Any]
    func generateJWPlayerConfig(spriteSheets: [ThumbnailSpriteSheet], vttPath: String) -> [String: Any]
}
```

### ThumbnailConfig

```swift
struct ThumbnailConfig {
    let interval: Double
    let width: Int
    let height: Int
    let columns: Int
    let rows: Int
    let quality: ThumbnailQuality
    let format: ThumbnailFormat
    let preserveAspectRatio: Bool

    var thumbnailsPerSheet: Int { get }
    var spriteSheetSize: (width: Int, height: Int) { get }

    func validate() throws
    func estimatedStorageSize(for duration: Double) -> Int64
}
```

### ThumbnailPreset

```swift
enum ThumbnailPreset {
    case fast
    case standard
    case detailed
    case maximum

    static func configuration(for preset: ThumbnailPreset) -> ThumbnailConfig
}
```

---

## Examples

See `examples/thumbnail_generation.swift` for complete working examples.

---

**Questions?** Check the main documentation or open an issue on GitHub.
