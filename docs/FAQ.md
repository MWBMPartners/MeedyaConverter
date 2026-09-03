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
| Encoding pipelines¹ | -- | Yes | Yes |
| Scheduled encoding | -- | Yes | Yes |
| Watch folders | -- | Yes | Yes |
| Cloud uploads | -- | Yes | Yes |
| Media server notifications | -- | Yes | Yes |
| VMAF/SSIM quality metrics | -- | -- | Yes |
| DCP creation³ | -- | -- | Yes |
| AI upscaling² | -- | -- | Yes |

Exact tier assignments may change before release.

¹ Entitlement-gated, but not yet functional for anyone at any tier — see "What is an encoding pipeline?" below.
² Entitlement-gated, but not yet reachable from any UI or CLI at any tier — the upscaling engine exists in `ConverterEngine` with no caller. See the User Guide's AI Upscaling section.
³ Entitlement-gated, but not yet reachable from any UI or CLI at any tier — `DCPGenerator` exists in `ConverterEngine` with no caller.

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

You can always queue multiple files — whether more than one is *encoding at the same time* depends on which tool you use:

- **GUI:** the encoding queue can run more than one job at once, but only when the **Parallel Encoding** entitlement is active and the Max Concurrent Jobs setting is raised above its default of 1. Without both, the queue is strictly sequential — one job encodes at a time.
- **CLI:** `meedya-convert batch` (with `--dir` or `--job-file`) is a convenience for encoding many files or jobs in a single invocation, not concurrent encoding — both modes process every file/job strictly one after another. There is currently no CLI flag for concurrent batch encoding; run several `meedya-convert encode`/`batch` processes in parallel yourself (e.g. with `xargs -P` or `&` background jobs) if you want that.

### Can I estimate file size before encoding?

Yes. MeedyaConverter provides file size estimation based on target bitrate, CRF quality prediction, source duration, and stream count. This is available in the GUI before starting an encode.

---

## Pipelines, Scheduling, and Automation

### What is an encoding pipeline?

A pipeline is a sequence of steps (encode, extract thumbnail, generate preview GIF, extract audio, probe/verify) that you assemble in the Pipeline Editor. **It's a builder only today, not an automated workflow** — nothing in the app currently executes a saved pipeline, and the editor's Save action has no handler wired up, so a pipeline you build is discarded when you close the editor. See the User Guide's [Encoding Pipelines](User-Guide#encoding-pipelines) section for the details.

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

- **Auto-update checks** — Sparkle, plus GitHub Releases and, when the integrated-apps API is configured, remote update channels and feature flags (`AppUpdateChecker`, `GitHubReleaseChecker`, `IntAppsAPIClient`).
- **Cloud uploads** (only when you explicitly configure and trigger an upload to your own cloud storage).
- **Webhooks and media-server notifications** (only when you configure them as post-encode actions).
- **Subscription verification** (StoreKit/RevenueCat for purchase validation).

- **MusicBrainz metadata lookup**, but only when *you* click "Look Up…" in the
  Metadata Tag Editor: it sends your search terms (title/artist) to
  `musicbrainz.org` to fetch candidate tags. The keyed providers (TMDB, TheTVDB,
  Discogs, …) are still not wired, so they make no requests.

MeedyaConverter never sends your media *files*, encoding settings, or usage
patterns to any server; the MusicBrainz lookup sends only the search text you
enter, on demand.

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
