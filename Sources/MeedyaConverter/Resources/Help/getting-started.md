# 🚀 Getting Started with MeedyaConverter

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## What is MeedyaConverter?

MeedyaConverter is a professional media conversion tool that lets you convert audio and video files between formats, prepare content for adaptive streaming (HLS/MPEG-DASH), and upload to cloud services — all from a modern, easy-to-use interface.

---

## Installation

### macOS

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/MWBMPartners/MeedyaConverter/releases)
2. Open the `.dmg` and drag MeedyaConverter to your Applications folder
3. Launch MeedyaConverter from Applications
4. On first launch, macOS may ask you to confirm — click "Open"

> FFmpeg and other required tools are bundled with the application. No additional downloads are needed.

### CLI Installation

The CLI tool can be used alongside or independently of the GUI application:

```bash
# After installing the macOS app, the CLI is available at:
/Applications/MeedyaConverter.app/Contents/MacOS/meedya-convert

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

## App Behaviour

A few app-wide conveniences beyond the core convert workflow:

### The Queue Is One File at a Time by Default

Add several files and MeedyaConverter queues them, but by default it
encodes them **sequentially**, one at a time. Plus-tier licences (and
above) can raise this in **Performance → Parallel Encoding** in the
sidebar; Free installs are held to 1 no matter how the slider is set.
Turning it up doesn't change what any single encode does — it only lets
more than one run at once — and this is a new, alpha-quality setting, so
treat higher values as experimental rather than production-proven.

### Keyboard Shortcuts

The default shortcuts (⌘1–⌘5 to jump between sections, ⌘O to import,
⌘↩ to add the current file to the queue) can be reassigned in
**Settings → Shortcuts**. The editor flags it if two actions end up
sharing the same combination.

### Menu Bar Mode

**Settings → General → Show status in menu bar** adds a MeedyaConverter
icon to the menu bar showing queue status, with a quick-encode action
using your last-used profile.

### Deep Links (`meedyaconverter://`)

MeedyaConverter registers the `meedyaconverter://` URL scheme so other
apps, Shortcuts, and scripts can trigger it:

- `meedyaconverter://encode?file=/path/to/video.mov&profile=Web%20Standard` — start an encode
- `meedyaconverter://probe?file=/path/to/video.mov` — probe a file
- `meedyaconverter://open?view=queue` — bring a specific view to the front

---

## Next Steps

- 📖 [Encoding Guide](encoding-guide.md) — Detailed encoding settings reference
- 📡 [Adaptive Streaming Guide](adaptive-streaming.md) — HLS and MPEG-DASH preparation
- 💻 [CLI Reference](cli-reference.md) — Command-line interface documentation
- ❓ [FAQ](faq.md) — Frequently asked questions
- 🔧 [Troubleshooting](troubleshooting.md) — Common issues and solutions
