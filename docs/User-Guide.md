<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# User Guide

This guide covers the key features and settings available in MeedyaConverter.

---

## Encoding Profiles

### Built-in Profiles

MeedyaConverter ships with 24 built-in profiles covering quick-start, streaming, disc-authoring, and archival workflows — run `meedya-convert profiles --list` (or `--show <name>` for full detail) to see all of them. A representative sample:

| Profile | Video | Audio | Use Case |
| ------- | ----- | ----- | -------- |
| Quick Convert | H.264, CRF 23, fast | AAC 128k | Quick previews, maximum speed |
| Web Standard | H.264, CRF 20, medium | AAC 160k | Maximum-compatibility web playback |
| Web High Quality | H.265, CRF 22, medium | AAC 192k | Better quality, smaller files than Web Standard |
| 4K HDR Master | H.265, CRF 18, slow, HDR preserved | E-AC-3 7.1, 640k | High-quality HDR archive |
| Web Next-Gen | AV1 (SVT-AV1 preset 6), CRF 30 | Opus 128k | Best compression for modern browsers |
| ProRes HQ | Apple ProRes HQ | PCM | Professional mastering |
| Remux to MKV | Passthrough (copy) | Passthrough (copy) | Remux — change container only |

### Custom Profiles

You can create custom profiles with full control over:

- Video codec, CRF/bitrate, preset/speed, pixel format, resolution, and crop.
- Audio codec, bitrate/quality, sample rate, channel layout.
- Per-stream settings (different settings for each audio or subtitle track).
- Container format and metadata.

Profiles are saved as JSON files and can be exported, imported, and shared.

### Profile Sharing

Profiles can be exported to JSON and shared with other users or across machines. Use `meedya-convert profiles --export <name>` to export a profile to a file, or `--import <file>` to import one.

### Smart Profile Suggestions

MeedyaConverter analyses your source file and suggests optimal encoding profiles based on:

- Source resolution, codec, and bitrate.
- HDR format (HDR10, HLG, Dolby Vision).
- Target use case (streaming, archival, editing).

The Profile Suggestion view in the GUI presents ranked recommendations with estimated file sizes and quality comparisons.

---

## Video Settings

### Codec Selection

Choose from 16+ video codecs. The most commonly used are:

- **H.264** — Maximum compatibility. No HDR support.
- **H.265** — Best balance of quality and size. Full HDR support.
- **AV1** — Best compression efficiency. Growing hardware support.
- **ProRes** — Professional intermediate. Ideal for editing workflows.

### Quality Control

- **CRF (Constant Rate Factor)** — Quality-based encoding. Lower values = higher quality, larger files. Recommended ranges vary by codec (see [Codec Reference](Codec-Reference)).
- **Bitrate** — Target a specific file size. Available as CBR, VBR, or constrained VBR.
- **Two-pass** — Analyse the video first to distribute bits more efficiently. Slower but more accurate bitrate targeting.

### Presets

Presets control the speed/quality trade-off of the encoder:

- **ultrafast / superfast / veryfast / faster / fast** — Quick encodes, larger files.
- **medium** — Default balance.
- **slow / slower / veryslow** — Slower encodes, better compression.

### Resolution and Crop

- Scale to a target resolution (e.g., 1920x1080, 3840x2160).
- Automatic black bar detection and cropping via FFmpeg's `cropdetect`.
- Smart crop integration with content-aware framing.
- Custom crop rectangles.

---

## Audio Settings

### Audio Codec Selection

Choose from 30+ audio codecs, including:

- **AAC** (LC, HE, HE-v2, xHE) — Universal lossy codec.
- **AC-3 / E-AC-3** — Dolby surround for Blu-ray and streaming.
- **FLAC / ALAC** — Lossless compression.
- **Opus** — Modern, excellent quality at all bitrates.
- **PCM** — Uncompressed (for professional workflows).
- **DTS / DTS-HD / DTS:X** — DTS surround family (passthrough for HD/X).
- **TrueHD** — Dolby lossless (Blu-ray).

### Bitrate and Quality

- Lossy codecs: specify bitrate (e.g., 128k, 256k, 640k) or VBR quality level.
- Lossless codecs: compression level only (no quality loss).
- Per-channel bitrate recommendations are shown in the UI.

### Channel Layout

- Preserve original layout (stereo, 5.1, 7.1, etc.).
- Downmix surround to stereo.
- Upmix stereo to surround (Pro Logic II, other matrix modes).
- Matrix encoding metadata preservation during transcoding.

### Audio Normalization

MeedyaConverter includes normalization presets for consistent loudness:

- **EBU R128** — European broadcast standard (-23 LUFS integrated, -1 dBTP true peak).
- **ReplayGain** — Album and track gain for music libraries.
- **Custom** — User-defined target loudness and true peak ceiling.

Normalization settings are accessible from the Normalization Settings view in the GUI and can be baked into encoding profiles.

### Audio Waveform Visualisation

The audio waveform view displays the amplitude envelope of each audio track, making it easy to identify silent passages, clipping, and loudness variations before encoding.

---

## HDR Handling

MeedyaConverter supports comprehensive HDR workflows.

### HDR Formats

| Format | Metadata Type | Supported Operations |
| ------ | ------------- | -------------------- |
| HDR10 | Static (MaxCLL/MaxFALL, mastering display) | Preserve, tone-map to SDR |
| HDR10+ | Dynamic (per-scene brightness) | Preserve, tone-map to SDR |
| HLG (Hybrid Log-Gamma) | Transfer function | Preserve, convert to PQ, tone-map |
| Dolby Vision | Dynamic RPU metadata | Preserve (Profile 5/7/8), extract/inject via dovi_tool |

### Preserve HDR

When encoding HDR content to an HDR-capable codec (H.265, AV1, VP9), MeedyaConverter preserves:

- Colour primaries (BT.2020).
- Transfer characteristics (PQ / HLG).
- MaxCLL and MaxFALL values.
- Mastering display colour volume.
- HDR10+ dynamic metadata (JSON sidecar).
- Dolby Vision RPU (via dovi_tool extract/inject).

### Tone Mapping (HDR to SDR)

When converting HDR to SDR (e.g., for H.264 output), MeedyaConverter applies tone mapping:

- **Hable** — Filmic curve, good highlight rolloff. Default.
- **Reinhard** — Simple and predictable.
- **Mobius** — Smooth transition, preserves low-light detail.
- **BT.2390** — ITU standard, broadcast-friendly.
- **Clip** — Hard clip (not recommended for most content).

The app automatically triggers tone mapping when HDR source is paired with an SDR-only codec or profile.

### PQ to HLG Conversion

Convert HDR10 (PQ) content to HLG for broadcast compatibility:

- Preferred pipeline: `hlg-tools` (higher quality, full colour volume).
- Fallback: FFmpeg `zscale` filter chain.

### Dolby Vision Workflows

- **Preserve:** Extract RPU with `dovi_tool`, encode base layer, re-inject RPU.
- **HLG to DV:** Auto-generate Dolby Vision Profile 8.4 from HLG source via `dovi_tool generate`.
- **DV to HLG to SDR:** Three-tier fallback for maximum compatibility.

---

## Per-Stream Encoding

MeedyaConverter allows you to configure each stream independently:

- Re-encode video track 1 to H.265 while passing through video track 2.
- Encode primary audio to AAC and secondary audio to AC-3.
- Include some subtitle tracks and exclude others.
- Apply different settings (bitrate, codec, filters) to each stream.

The Stream Inspector in the GUI shows all available tracks with their properties, and you can configure each one individually via the Per-Stream Settings view.

---

## Filename Templates

In the GUI's Output Settings, a filename template controls the output naming pattern for encodes queued from there. Available variables:

- `{title}` (or the older `{name}`) — Source filename without extension.
- `{container}` (or the older `{ext}`) — Output container format (e.g. `mkv`).
- `{profile}` — Encoding profile name, used verbatim (spaces and all).
- `{resolution}` — Output resolution (e.g., `1920x1080`).
- `{codec}` — Video codec name.
- `{width}` / `{height}` — Output width/height in pixels individually.
- `{fps}` — Output frame rate.
- `{channels}` — Audio channel count.
- `{date}` — Current date (`yyyy-MM-dd`), or `{date:FORMAT}` for a custom `DateFormatter` pattern (e.g. `{date:yyyyMMdd}`).

There is no `{index}`/sequential-batch-position variable, and `meedya-convert batch` (the CLI's own multi-file mode) does not use filename templates at all — it always names outputs `<stem>.<profile-extension>`.

Example: `{title}_{profile}_{resolution}.{container}` with the "Quick Convert" profile produces `movie_Quick Convert_1920x1080.mp4`.

---

## File Size Estimation

Before starting an encode, MeedyaConverter can estimate the output file size based on:

- Source duration and stream count.
- Target bitrate or CRF-based quality prediction.
- Audio and subtitle stream sizes.

This helps you plan disk space and choose appropriate quality settings.

---

## FFmpeg Command Preview

The FFmpeg Preview view shows the exact FFmpeg command line that will be generated for your current encoding configuration. This is useful for:

- Debugging encoding issues.
- Learning FFmpeg arguments.
- Copying commands for use in scripts or CI/CD pipelines.

The preview updates in real time as you change encoding settings.

---

## A/B Quality Preview

Compare encoding quality before committing to a full encode:

1. Select a representative frame or short segment from your source.
2. Encode it with two different profiles or settings.
3. View both results side by side in the Comparison view.
4. Optionally run SSIM/PSNR quality metrics on the comparison (for VMAF specifically, use the dedicated Quality Metrics view described below, which runs VMAF, SSIM, and PSNR as separate FFmpeg passes across a whole file).

This feature extracts frames using the Frame Comparison Extractor and displays them in a split-screen view.

---

## Passthrough and Remux

**Passthrough** copies a stream without re-encoding. This is:

- **Lossless** — no quality degradation.
- **Fast** — limited only by disk I/O speed.
- **Useful for** changing containers (e.g., MKV to MP4), adding/removing tracks, or editing metadata.

To remux an entire file (all streams passthrough), use the built-in "Remux to MKV" or "Remux to MP4" profile, or select "Copy" for every stream in a custom profile.

---

## Container Format Guide

| Container | Best For | Video | Audio | Subtitles |
| --------- | -------- | ----- | ----- | --------- |
| **MP4** | Playback, streaming, web | H.264, H.265, AV1 | AAC, AC-3, E-AC-3 | MOV text (limited) |
| **MKV** | Archival, multi-track | All codecs | All codecs | All formats (SRT, ASS, PGS, etc.) |
| **MOV** | Apple/Pro editing | ProRes, H.264, H.265 | AAC, ALAC, PCM | MOV text |
| **WebM** | Web delivery | VP9, AV1 | Opus, Vorbis | WebVTT |
| **TS** | Broadcast, IPTV | H.264, H.265, MPEG-2 | AAC, AC-3, MP2 | DVB-SUB, Teletext |
| **MXF** | Professional broadcast | JPEG 2000, DNxHR, ProRes | PCM | -- |

MeedyaConverter validates codec/container compatibility and warns when a combination is unsupported.

---

## Streaming Preparation (HLS / DASH / CMAF)

### HLS (HTTP Live Streaming)

Generate Apple-compatible HLS packages with:

- Multiple quality variants (adaptive bitrate ladder), each with its own video/audio bitrate and resolution.
- MPEG-TS segments for plain HLS; fMP4 segments when you choose CMAF instead (see below) — this is a consequence of the top-level format choice, not a separate per-format toggle.
- Master playlist (`#EXT-X-STREAM-INF`) generation, listing every variant's bandwidth, resolution, and codec string.

Each variant maps exactly one video track and one audio track from the source (`-map 0:v:0 -map 0:a:0`) — there is currently no multi-audio-track or subtitle variant-stream support in the manifest pipeline. **Segment encryption (AES-128, SAMPLE-AES) is not currently available**: `HLSEncryption` (`Sources/ConverterEngine/FFmpeg/StreamingEnhancements.swift`) implements AES-128-CBC key generation and key-file writing, but nothing in `ManifestGenerator`, `ManifestConfig`, or the `manifest` CLI command calls it — it has no callers anywhere in the codebase.

### MPEG-DASH

Generate DASH manifests (MPD) with:

- Two adaptation sets per manifest — one video, one audio — each listing every quality variant as a `<Representation>`.
- Segment template **and** timeline addressing together (`-use_template 1 -use_timeline 1`) — this is fixed, not a choice between the two.

The generated MPD is always `type="static"` (on-demand) — **there is no live/dynamic DASH profile support**. **CENC/DRM encryption is not currently available** the same way HLS encryption isn't: `DRMPreparation` (`Sources/ConverterEngine/Utilities/DRMPreparation.swift`) can build PSSH boxes, CPIX documents, and CENC FFmpeg arguments, but it has no callers — nothing wires it into manifest generation.

### CMAF (Common Media Application Format)

Generate both HLS and DASH manifests from a single set of CMAF-compliant segments. This reduces storage requirements for multi-protocol delivery.

### Common Streaming Workflow

1. Import your source file.
2. Define quality variants (e.g., 1080p at 5 Mbps, 720p at 3 Mbps, 480p at 1.5 Mbps).
3. Choose HLS, DASH, or CMAF.
4. Encode — MeedyaConverter generates all variants and manifests in one pass.

Use `meedya-convert manifest --dry-run` to preview the FFmpeg commands before encoding.

---

## Encoding Pipelines

The Pipeline Editor view lets you assemble a sequence of steps — Encode, Extract Thumbnail, Generate Preview GIF, Extract Audio, or Probe/Verify — each with its own profile or step-specific settings, reordered by drag.

**This is currently a builder only, not an automated workflow.** `PipelineExecutor` can build the FFmpeg arguments for a single step, but nothing in the app calls it — there is no "Run Pipeline" action anywhere. The editor's own Save button, as reached from Output Settings, has no save handler wired up, so a pipeline you build there is discarded the moment you close the sheet. Pipelines cannot currently be saved, shared, or triggered manually or on a schedule; Scheduled Encoding (below) schedules a single profile against a single file, not a saved pipeline.

---

## Scheduled Encoding

Schedule encoding jobs to run at specific times or on a recurring basis:

- **One-time:** Encode at a specified date and time (e.g., overnight for long encodes).
- **Recurring:** Repeat at a fixed **Daily** or **Weekly** interval from the scheduled time (e.g., every night at 2 AM) — this is a fixed interval, not an arbitrary cron expression.
- **Watch folder triggered:** Automatically encode files when they appear in a monitored directory.

The Schedule view shows upcoming and completed scheduled jobs with their status.

---

## Conditional Encoding Rules

Define rules that automatically apply encoding settings based on source file properties:

- **Resolution-based:** If source is 4K, use H.265 CRF 20; if 1080p, use H.264 CRF 18.
- **Codec-based:** If source is ProRes, passthrough video; otherwise re-encode.
- **HDR-based:** If source has Dolby Vision, preserve it; if HDR10, tone-map to SDR.
- **Duration-based:** If source is longer than 2 hours, use a faster preset.
- **File size-based:** If source is larger than 10 GB, use lower CRF.

Rules are evaluated in order and the first matching rule is applied. The Conditional Rules view in the GUI provides a visual rule editor.

---

## Post-Encode Actions

Automate tasks that run after an encode completes:

- **Move/rename** the output file to a final destination.
- **Delete** the source file (with confirmation).
- **Upload** to a cloud provider (S3, GCS, Azure, etc.).
- **Notify** a media server (Plex, Jellyfin, Emby) to scan for new content.
- **Send webhook** notification to an external service.
- **Run a shell script** for custom post-processing.

Post-encode actions are configured per-profile or per-job in the Post-Encode Actions view.

---

## Watch Folders

Monitor directories for new media files and automatically encode them:

1. Configure a watch folder with an input directory, output directory, and encoding profile.
2. MeedyaConverter monitors the directory for new files matching specified extensions.
3. New files are automatically queued for encoding with the configured profile.
4. Post-encode actions run after each file is processed.

Watch folders support recursive monitoring and file extension filters. The Watch Folder Manager handles multiple monitored directories simultaneously.

---

## Scene Detection

MeedyaConverter can detect scene changes in video content, using FFmpeg's scene-detection filter with a configurable sensitivity threshold. Results appear as a scene list with timestamps and confidence scores in the Scene Detector view, where you can also add or remove markers manually.

Detected scenes can be exported as a chapter file in OGM, Matroska (FFmetadata), or similar formats — this is the way to get scene markers into an encode today. **"Apply to Job" is permanently disabled**: `EncodingJobConfig`/`EncodingProfile` have no field for attaching external chapter metadata to a job, so use "Export Chapters" and inject the resulting file into your encoding pipeline manually (e.g. via FFmpeg's `-i chapters.txt -map_metadata 1`). There is no keyframe-alignment or automatic segment-splitting feature.

---

## Bitrate Heatmap

The Bitrate Heatmap view provides a visual representation of bitrate distribution across the timeline of a video:

- Identify segments with unusually high or low bitrate.
- Spot potential quality issues (compression artefacts in low-bitrate sections).
- Compare bitrate allocation between source and encoded output.
- Useful for validating CRF-based encodes and constrained VBR settings.

---

## Quality Metrics (VMAF / SSIM)

After encoding, compare the output quality against the source using industry-standard metrics:

- **VMAF** (Video Multimethod Assessment Fusion) — Netflix's perceptual quality metric. Scores 0-100.
- **SSIM** (Structural Similarity Index) — Measures structural similarity. 1.0 = identical.
- **PSNR** (Peak Signal-to-Noise Ratio) — Traditional quality metric in dB.

VMAF, SSIM, and PSNR are each computed as a separate FFmpeg pass and displayed in the Quality Metrics view (part of the Analysis Hub) — not the Encoding Graphs view, which covers encoding-history statistics instead.

---

## Content-Aware Encoding (Not Yet Reachable)

`ContentAnalyzer` (`Sources/ConverterEngine/FFmpeg/ContentAnalyzer.swift`) can build FFmpeg arguments for temporal/spatial complexity analysis, classify segments (static/medium/high complexity), and detect film grain — but **there is no view or menu item anywhere in the app that calls it**. Crop/letterbox detection is a separate, genuinely wired-up feature (FFmpeg's `cropdetect`, see [Resolution and Crop](#resolution-and-crop) above) — `ContentAnalyzer` itself has no cropping logic at all.

---

## AI Upscaling (Not Yet Reachable)

`AIUpscaler` (`Sources/ConverterEngine/FFmpeg/AIUpscaler.swift`) defines three Real-ESRGAN-based models (general-purpose, anime/animation, and a temporally-consistent video model) with configurable scale factors and tiling for AI-based super-resolution — but **there is no view, menu item, or CLI flag anywhere that calls it**. It is backend code only; it cannot currently be used from the app or `meedya-convert`.

---

## Next Steps

- [CLI Reference](CLI-Reference) — Automate encoding from the command line.
- [Codec Reference](Codec-Reference) — Detailed settings for every supported codec.
- [Troubleshooting](Troubleshooting) — Solutions for common issues.
