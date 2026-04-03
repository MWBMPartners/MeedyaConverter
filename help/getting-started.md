# 🚀 Getting Started with MeedyaConverter

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## What is MeedyaConverter?

MeedyaConverter is a professional media conversion tool that lets you convert audio and video files between formats, prepare content for adaptive streaming (HLS/MPEG-DASH), and upload to cloud services — all from a modern, easy-to-use interface.

---

## Installation

### macOS

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/MWBM-Partners-Ltd/MeedyaConverter/releases)
2. Open the `.dmg` and drag MeedyaConverter to your Applications folder
3. Launch MeedyaConverter from Applications
4. On first launch, macOS may ask you to confirm — click "Open"

> FFmpeg and other required tools are bundled with the application. No additional downloads are needed.

### CLI Installation

The CLI tool can be used alongside or independently of the GUI application:

```bash
# After installing the macOS app, the CLI is available at:
/Applications/MeedyaConverter.app/Contents/MacOS/meedya-cli

# Or add to your PATH:
export PATH="$PATH:/Applications/MeedyaConverter.app/Contents/MacOS"
```

---

## Quick Start

### 1. Import a Source File

- Drag and drop a media file onto the MeedyaConverter window, or
- Click **File → Open** and select your source file
- MeedyaConverter will analyze the file and display all streams (video, audio, subtitles)

### 2. Choose Output Settings

- Select an **output container** (MP4, MKV, MOV, WebM, etc.)
- Choose encoding settings for each stream, or select **Passthrough** to copy without re-encoding
- Alternatively, select a **preset profile** for common scenarios

### 3. Start Encoding

- Click **Start** to begin the encoding process
- Monitor progress in real-time with the progress bar and log viewer
- You'll receive a notification when encoding is complete

---

## Preset Profiles

MeedyaConverter includes built-in profiles for common use cases:

| Profile | Description |
| ------- | ----------- |
| **Web Standard (H.264/AAC)** | Widely compatible MP4 for web playback |
| **High Quality (H.265/AAC)** | Smaller files with excellent quality |
| **Apple HLS Streaming** | Multi-bitrate HLS for Apple devices |
| **MPEG-DASH Streaming** | Multi-bitrate DASH for cross-platform |
| **Audio Only (AAC)** | Extract and encode audio to AAC |
| **Archive (MKV/FLAC)** | Lossless audio with video passthrough |

---

## Next Steps

- 📖 [Encoding Guide](encoding-guide.md) — Detailed encoding settings reference
- 📡 [Adaptive Streaming Guide](adaptive-streaming.md) — HLS and MPEG-DASH preparation
- 💻 [CLI Reference](cli-reference.md) — Command-line interface documentation
- ❓ [FAQ](faq.md) — Frequently asked questions
- 🔧 [Troubleshooting](troubleshooting.md) — Common issues and solutions
