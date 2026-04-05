<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Getting Started

This guide walks you through installing MeedyaConverter and performing your first encode.

---

## Installation

### Direct Download (Recommended)

Download the latest release from the [GitHub Releases](https://github.com/MWBMPartners/MeedyaConverter/releases) page. The `.dmg` disk image contains the MeedyaConverter app and an optional CLI installer.

1. Open the `.dmg` file.
2. Drag **MeedyaConverter.app** to your Applications folder.
3. (Optional) Run the CLI installer to add `meedya-convert` to your PATH.

Direct builds include Sparkle auto-update support — the app will notify you when updates are available.

### Homebrew (Planned)

Homebrew installation is planned for a future release:

```bash
brew install --cask meedyaconverter
```

### Mac App Store

MeedyaConverter will also be available on the Mac App Store. The App Store version uses AVFoundation and FFmpegKit instead of a system FFmpeg binary, and does not include Sparkle auto-updates (updates are managed by the App Store).

### Building from Source

See [Building from Source](Building-from-Source) for instructions on compiling MeedyaConverter yourself, including conditional build flags for Sparkle and StoreKit.

---

## Prerequisites

### FFmpeg

MeedyaConverter (direct distribution) requires FFmpeg to be installed on your system. The app searches for FFmpeg in the following locations:

1. Bundled FFmpeg (included in the app bundle for direct builds).
2. Homebrew: `/opt/homebrew/bin/ffmpeg` (Apple Silicon) or `/usr/local/bin/ffmpeg` (Intel).
3. System PATH.

To install FFmpeg via Homebrew:

```bash
brew install ffmpeg
```

For full codec support (including non-free encoders), use:

```bash
brew install ffmpeg --with-fdk-aac
```

The App Store version does not require a separate FFmpeg installation.

### Optional External Tools

| Tool | Purpose | Required For |
| ---- | ------- | ------------ |
| `dovi_tool` | Dolby Vision RPU extraction and injection | Dolby Vision workflows |
| `hlg-tools` | High-quality PQ-to-HLG conversion | HDR format conversion |
| `MediaInfo` | Extended media analysis | Enhanced probing (optional) |

These tools are detected automatically if present on the system PATH or in Homebrew locations.

---

## First Encode Walkthrough

### Using the GUI

1. **Launch** MeedyaConverter from your Applications folder.
2. **Import** a media file by dragging it onto the app window or using File > Open.
3. **Inspect** the source — the Stream Inspector shows all video, audio, and subtitle tracks with their properties.
4. **Configure** output settings:
   - Choose an encoding profile (e.g., "H.265 High Quality") or customise settings.
   - Select which streams to include, re-encode, or passthrough.
   - Set the output container format.
   - Optionally preview the FFmpeg command that will be generated.
5. **Set output location** — choose where to save the encoded file.
6. **Start encoding** — click the Encode button. Progress is shown in real time with bitrate, speed, and ETA.

### Using the CLI

```bash
# Probe a file to see its streams
meedya-convert probe --input video.mkv

# Encode with a built-in profile
meedya-convert encode --input video.mkv --output video.mp4 --profile "H.265 High Quality"

# Encode with custom settings
meedya-convert encode --input video.mkv --output video.mp4 \
  --video-codec h265 --crf 20 --preset medium \
  --audio-codec aac --audio-bitrate 256k

# List available profiles
meedya-convert profiles --list

# Validate a profile for a specific platform
meedya-convert validate --profile "H.265 High Quality" --platform iOS
```

---

## Basic Workflow

The general workflow for any encode follows three steps:

```text
Import  ->  Configure  ->  Encode
```

1. **Import:** Add one or more source files. MeedyaConverter probes each file to detect streams, codecs, resolution, HDR metadata, and more.

2. **Configure:** Choose what to do with each stream:
   - **Re-encode** — transcode to a different codec with specified quality settings.
   - **Passthrough** — copy the stream without re-encoding (lossless, fast).
   - **Exclude** — drop the stream from the output.

3. **Encode:** The encoding engine builds FFmpeg arguments, launches the transcode, and monitors progress. Completed jobs appear in the queue with a summary report.

---

## What's Next

- [User Guide](User-Guide) — Detailed encoding settings, HDR workflows, pipelines, scheduling, and all features.
- [CLI Reference](CLI-Reference) — Full command documentation for `meedya-convert`.
- [Codec Reference](Codec-Reference) — Supported codecs and recommended settings.
