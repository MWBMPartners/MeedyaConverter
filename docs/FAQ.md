<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Frequently Asked Questions

---

## General

### What is MeedyaConverter?

MeedyaConverter is a professional-grade media transcoding application for macOS. It provides both a SwiftUI GUI and a CLI tool (`meedya-convert`) for encoding, transcoding, and remuxing video and audio files. It supports 16+ video codecs, 30+ audio codecs, HDR workflows, adaptive streaming, encoding pipelines, scheduled encoding, and more.

### Is MeedyaConverter free?

MeedyaConverter uses a feature-gating system with three tiers: Free, Pro, and Studio. The free tier provides core encoding functionality. Pro and Studio tiers unlock advanced features such as batch processing, encoding pipelines, cloud uploads, professional codec support, and watch folders. Pricing details will be announced closer to release.

### What platforms are supported?

Currently macOS 15+ (Sequoia). Windows and Linux support is planned for v2.0.

### Is MeedyaConverter open source?

No. MeedyaConverter is proprietary software developed by MWBM Partners Ltd. The source code is not publicly available.

---

## Formats and Codecs

### Which video codec should I use?

| Goal | Recommended Codec |
| ---- | ----------------- |
| Maximum compatibility | H.264 |
| Best quality/size balance | H.265 (HEVC) |
| Smallest possible file | AV1 |
| Professional editing | ProRes |
| Archival / lossless | FFV1 |
| Web delivery | H.264 or AV1 |

### Which audio codec should I use?

| Goal | Recommended Codec |
| ---- | ----------------- |
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

## Subscriptions and Licensing

### What features are included in each tier?

| Feature | Free | Pro | Studio |
| ------- | ---- | --- | ------ |
| Single file encoding | Yes | Yes | Yes |
| Built-in profiles | Yes | Yes | Yes |
| Probe / inspect | Yes | Yes | Yes |
| Batch encoding | Limited | Yes | Yes |
| Custom profiles | -- | Yes | Yes |
| Encoding pipelines | -- | Yes | Yes |
| Scheduled encoding | -- | Yes | Yes |
| Watch folders | -- | Yes | Yes |
| Cloud uploads | -- | Yes | Yes |
| Media server notifications | -- | Yes | Yes |
| VMAF/SSIM quality metrics | -- | -- | Yes |
| DCP creation | -- | -- | Yes |
| AI upscaling | -- | -- | Yes |

Exact tier assignments may change before release.

### How do I restore a purchase?

In the GUI, go to the licensing/paywall view and select "Restore Purchases". This works for both App Store and RevenueCat-managed subscriptions.

### Can I use a license key instead of the App Store?

Yes. Direct distribution builds support license key activation via the License Entry view. License keys are validated by the `LicenseKeyValidator` module.

### Do subscriptions work across devices?

App Store subscriptions are tied to your Apple ID and work across all your macOS devices. RevenueCat-managed subscriptions can sync across devices if you sign in with the same account.

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

Yes. The encoding queue supports multiple concurrent jobs (configurable concurrency limit). In the CLI, use `meedya-convert batch` with the `--dir` or `--job-file` options.

### Can I estimate file size before encoding?

Yes. MeedyaConverter provides file size estimation based on target bitrate, CRF quality prediction, source duration, and stream count. This is available in the GUI before starting an encode.

---

## Pipelines, Scheduling, and Automation

### What is an encoding pipeline?

An encoding pipeline chains multiple encoding steps into a single automated workflow. For example, you could encode a source to a 4K master, then downscale to 1080p for web, extract audio to FLAC, and generate HLS manifests -- all in one pipeline.

### Can I schedule encodes for later?

Yes. The Schedule view lets you set one-time or recurring encode schedules. The app must be running (or set to launch at login) for scheduled encodes to execute.

### What are conditional rules?

Conditional rules automatically apply encoding settings based on source file properties. For example: "If source is 4K, use H.265 CRF 20; if 1080p, use H.264 CRF 18." Rules are evaluated in order and the first match is applied.

### What are post-encode actions?

Post-encode actions automate tasks that run after encoding completes: move files, upload to cloud storage, notify a media server, send a webhook, or run a shell script.

### How do watch folders work?

Watch folders monitor directories for new media files and automatically queue them for encoding with a configured profile. The Watch Folder Manager handles multiple directories simultaneously and supports recursive monitoring and file extension filters.

---

## Distribution and App Store

### What is the difference between Direct and App Store versions?

| Feature | Direct (DMG) | App Store |
| ------- | ------------ | --------- |
| FFmpeg backend | System FFmpeg (subprocess) | FFmpegKit (embedded XCFramework) |
| Auto-updates | Sparkle 2 | Apple-managed |
| Sandbox | Optional | Required |
| File access | Unrestricted | User-selected + bookmarks |
| Licensing | License keys | StoreKit / RevenueCat |
| Price | Same | Same (Apple takes 30% commission) |

Both versions use the same ConverterEngine and provide identical encoding capabilities.

### Why does the App Store version need file access permissions?

Apple requires App Store apps to run in a sandbox. MeedyaConverter needs access to your media files for encoding. It uses three tiers of access:

1. **User-selected** -- files you choose via the Open dialog or drag-and-drop.
2. **Security-scoped bookmarks** -- remembers previously accessed locations.
3. **Full Disk Access** -- optional, for accessing files anywhere on the system.

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
- **Subscription verification** (StoreKit/RevenueCat for purchase validation).

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

- [Troubleshooting Guide](Troubleshooting) -- Common issues and solutions.
- [GitHub Issues](https://github.com/MWBMPartners/MeedyaConverter/issues) -- Bug reports and feature requests.
- [Wiki Home](Home) -- Full documentation index.
