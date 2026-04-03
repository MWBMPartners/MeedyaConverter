# ❓ Frequently Asked Questions

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## General

### What is MeedyaConverter?

MeedyaConverter is a professional media conversion application that converts audio/video files between formats, prepares content for adaptive streaming (HLS/MPEG-DASH), and supports direct upload to cloud services. It is designed as a modern, more capable alternative to HandBrake.

### How is MeedyaConverter different from HandBrake?

Key differences include:

- **Video passthrough** — copy video without re-encoding (HandBrake always re-encodes)
- **Subtitle passthrough** — preserve original subtitle formats (HandBrake converts to SRT)
- **Multiple video streams** — handle files with multiple video tracks
- **Adaptive streaming** — built-in HLS and MPEG-DASH preparation
- **Audio normalization** — EBU R128 and ReplayGain support
- **Cloud upload** — direct upload to 12+ cloud providers
- **Forensic watermarking** — invisible content protection

### Is MeedyaConverter free?

MeedyaConverter is a proprietary product by MWBM Partners Ltd. Licensing details will be announced closer to release.

### What platforms are supported?

- **macOS** (Apple Silicon and Intel) — primary platform
- **Windows** (x86, x64, ARM) — planned
- **Linux** (x86, x64, ARM, Raspberry Pi) — planned

---

## Encoding

### Can I convert audio files without video?

Yes. MeedyaConverter fully supports audio-only files. Simply import an audio file and choose your output format.

### Does MeedyaConverter preserve HDR?

Yes. MeedyaConverter preserves HDR10, HDR10+, HLG, and Dolby Vision metadata when the output format and codec support it. It can also automatically create Dolby Vision from HDR10+ sources.

### What is passthrough mode?

Passthrough copies a stream (video, audio, or subtitles) directly to the output file without re-encoding. This is much faster and preserves original quality, but the output container must support the codec.

### Can I encode multiple files at once?

Yes. Add multiple files to the job queue and MeedyaConverter will process them sequentially (or in parallel, depending on your settings).

---

## Adaptive Streaming

### What is adaptive streaming?

Adaptive Bitrate (ABR) streaming encodes your video at multiple quality levels. Players like VideoJS or Shaka automatically switch between qualities based on the viewer's bandwidth, providing the best possible experience.

### Does MeedyaConverter create both HLS and MPEG-DASH?

Yes. You can generate HLS (.m3u8), MPEG-DASH (.mpd), or both from a single source file.

### Can I add encryption to my streams?

Yes. MeedyaConverter supports AES-128 encryption for HLS content with integrated key generation and management.

---

## Troubleshooting

See the [Troubleshooting Guide](troubleshooting.md) for common issues and solutions.
