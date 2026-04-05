<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Frequently Asked Questions

---

## General

### What is MeedyaConverter?

MeedyaConverter is a professional-grade media transcoding application for macOS. It provides both a SwiftUI GUI and a CLI tool (`meedya-convert`) for encoding, transcoding, and remuxing video and audio files. It supports 16+ video codecs, 30+ audio codecs, HDR workflows, adaptive streaming, and more.

### Is MeedyaConverter free?

MeedyaConverter uses a feature-gating system with three tiers: Free, Pro, and Studio. The free tier provides core encoding functionality. Pro and Studio tiers unlock advanced features such as batch processing, cloud uploads, and professional codec support. Pricing details will be announced closer to release.

### What platforms are supported?

Currently macOS 15+ (Sequoia). Windows and Linux support is planned for v2.0.

### Is MeedyaConverter open source?

No. MeedyaConverter is proprietary software developed by MWBM Partners Ltd. The source code is not publicly available.

---

## Formats and Codecs

### Which video codec should I use?

| Goal | Recommended Codec |
|------|-------------------|
| Maximum compatibility | H.264 |
| Best quality/size balance | H.265 (HEVC) |
| Smallest possible file | AV1 |
| Professional editing | ProRes |
| Archival / lossless | FFV1 |
| Web delivery | H.264 or AV1 |

### Which audio codec should I use?

| Goal | Recommended Codec |
|------|-------------------|
| Maximum compatibility | AAC-LC |
| Surround sound (Blu-ray) | AC-3 or E-AC-3 |
| Lossless archival | FLAC |
| Best quality at low bitrates | Opus |
| Apple ecosystem | AAC-LC or ALAC |

### Can MeedyaConverter handle HDR content?

Yes. MeedyaConverter supports HDR10, HDR10+, HLG, and Dolby Vision. It can:

- **Preserve** HDR metadata when encoding to HDR-capable codecs (H.265, AV1, VP9).
- **Tone-map** HDR to SDR using multiple algorithms (Hable, Reinhard, Mobius, BT.2390).
- **Convert** between HDR formats (PQ to HLG, HLG to Dolby Vision).

### What containers should I use?

- **MP4** for general playback and streaming (most compatible).
- **MKV** for archival or when you need multiple audio/subtitle tracks.
- **MOV** for professional editing with Apple tools.
- **WebM** for web delivery with VP9 or AV1.

### Can I just change the container without re-encoding?

Yes. Use passthrough mode (remux) to copy all streams to a new container without any quality loss. This is extremely fast since no encoding occurs.

---

## Quality and Performance

### What CRF value should I use?

CRF (Constant Rate Factor) controls quality. Lower = better quality, larger file. The "right" value depends on the codec:

- **H.264:** 18-23 (18 = high quality, 23 = default/balanced).
- **H.265:** 18-24 (similar quality to H.264 at higher CRF values).
- **AV1:** 20-35 (CRF scale differs from H.264/H.265).

CRF 18 for H.264/H.265 is generally considered "visually lossless" for most content.

### How can I make encoding faster?

1. Use hardware encoding (VideoToolbox on macOS, NVENC on NVIDIA GPUs).
2. Use a faster preset (`fast` or `veryfast` instead of `slow`).
3. Use H.264 or H.265 instead of AV1 (AV1 is much slower to encode).
4. Reduce output resolution if the source is higher than needed.

### Does hardware encoding reduce quality?

Hardware encoders (VideoToolbox, NVENC) are generally slightly lower quality than software encoders (libx264, libx265) at the same bitrate. However, the speed improvement (3-10x) often outweighs the small quality difference. For critical quality work, use software encoding with a slower preset.

### Can I encode multiple files at once?

Yes. The encoding queue supports multiple concurrent jobs (configurable concurrency limit). In the CLI, use `meedya-convert batch` with the `--parallel` flag.

---

## Distribution and App Store

### What is the difference between Direct and App Store versions?

| Feature | Direct (DMG) | App Store |
|---------|-------------|-----------|
| FFmpeg backend | System FFmpeg (subprocess) | FFmpegKit (embedded XCFramework) |
| Auto-updates | Sparkle 2 | Apple-managed |
| Sandbox | Optional | Required |
| File access | Unrestricted | User-selected + bookmarks |
| Price | Same | Same (Apple takes 30% commission) |

Both versions use the same ConverterEngine and provide identical encoding capabilities.

### Why does the App Store version need file access permissions?

Apple requires App Store apps to run in a sandbox. MeedyaConverter needs access to your media files for encoding. It uses three tiers of access:

1. **User-selected** — files you choose via the Open dialog or drag-and-drop.
2. **Security-scoped bookmarks** — remembers previously accessed locations.
3. **Full Disk Access** — optional, for accessing files anywhere on the system.

### Will there be an iOS/iPadOS version?

Not currently planned. MeedyaConverter relies on FFmpeg, which requires macOS-level process management. An iOS version would require a fundamentally different architecture.

---

## Privacy and Analytics

### Does MeedyaConverter collect any data?

No. MeedyaConverter does not collect analytics, telemetry, or usage data. All encoding happens locally on your machine. No data is sent to MWBM Partners or any third party.

### Does MeedyaConverter access the internet?

Only for:

- **Auto-update checks** (Sparkle, direct distribution only).
- **Cloud uploads** (only when you explicitly configure and trigger an upload to your own cloud storage).
- **Metadata lookup** (optional, when you request metadata from MusicBrainz, TMDB, etc.).

MeedyaConverter never sends your media files, encoding settings, or usage patterns to any server.

### Does MeedyaConverter include DRM?

MeedyaConverter does not include or circumvent DRM. It encodes and transcodes unprotected media files. Protected content (DRM-wrapped files) cannot be processed.

---

## Disc Ripping

### Can MeedyaConverter rip CDs, DVDs, and Blu-rays?

Disc ripping support is planned for v1.1+ (Phase 10). It will support 22 disc types including Audio CD, DVD, Blu-ray, UHD Blu-ray, SACD, and more. AccurateRip verification is included for audio disc ripping.

### Can MeedyaConverter bypass copy protection?

MeedyaConverter does not include DRM circumvention tools. The legality of circumventing disc copy protection (CSS, AACS) varies by jurisdiction. Users are responsible for complying with local laws.

---

## Troubleshooting

### Where are log files stored?

- **GUI:** View logs in the Log panel within the app.
- **CLI:** Log output is printed to stderr. Redirect with `2> logfile.txt`.
- **Crash logs:** `~/Library/Logs/DiagnosticReports/`.

### How do I report a bug?

Open an issue on the [GitHub Issues](https://github.com/MWBMPartners/MeedyaConverter/issues) page. Include your macOS version, MeedyaConverter version, FFmpeg version, steps to reproduce, and relevant log output.

### Where can I get more help?

- [Troubleshooting Guide](Troubleshooting) — Common issues and solutions.
- [GitHub Issues](https://github.com/MWBMPartners/MeedyaConverter/issues) — Bug reports and feature requests.
- [Wiki Home](Home) — Full documentation index.
