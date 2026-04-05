<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# User Guide

This guide covers the key features and settings available in MeedyaConverter.

---

## Encoding Profiles

### Built-in Profiles

MeedyaConverter ships with built-in profiles for common workflows:

| Profile | Video | Audio | Use Case |
| ------- | ----- | ----- | -------- |
| H.264 Fast | H.264, CRF 23, fast | AAC 128k | Quick previews, web upload |
| H.264 High Quality | H.264, CRF 18, slow | AAC 256k | High-quality archival |
| H.265 Balanced | H.265, CRF 22, medium | AAC 192k | Good quality/size balance |
| H.265 High Quality | H.265, CRF 18, slow | AAC 256k | 4K/HDR content |
| AV1 Efficient | AV1, CRF 28, 6 | Opus 128k | Maximum compression |
| ProRes HQ | ProRes 422 HQ | PCM | Professional editing |
| Passthrough | Copy all | Copy all | Remux (change container only) |

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

When encoding multiple files (batch mode or pipelines), filename templates let you control the output naming pattern. Available variables include:

- `{name}` — Original filename without extension.
- `{ext}` — Profile-determined extension.
- `{profile}` — Profile name.
- `{resolution}` — Output resolution (e.g., 1080p).
- `{codec}` — Video codec name.
- `{date}` — Current date.
- `{index}` — Sequential index in batch.

Example: `{name}_{profile}_{resolution}.{ext}` produces `movie_H265HQ_1080p.mkv`.

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
4. Optionally run VMAF/SSIM quality metrics on the comparison.

This feature extracts frames using the Frame Comparison Extractor and displays them in a split-screen view.

---

## Passthrough and Remux

**Passthrough** copies a stream without re-encoding. This is:

- **Lossless** — no quality degradation.
- **Fast** — limited only by disk I/O speed.
- **Useful for** changing containers (e.g., MKV to MP4), adding/removing tracks, or editing metadata.

To remux an entire file (all streams passthrough), use the "Passthrough" profile or select "Copy" for every stream.

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

- Multiple quality variants (adaptive bitrate ladder).
- Audio and subtitle variant streams.
- fMP4 or MPEG-TS segment format.
- Encryption (AES-128, SAMPLE-AES).
- Master playlist generation.

### MPEG-DASH

Generate DASH manifests (MPD) with:

- Multiple adaptation sets.
- On-demand or live profiles.
- Segment timeline or segment template.
- CENC encryption.

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

Encoding pipelines chain multiple encoding steps into a single automated workflow. Each step in a pipeline can have its own profile, filters, and output settings.

Example pipeline:

1. **Step 1:** Encode source to H.265 4K master.
2. **Step 2:** Downscale master to 1080p H.264 for web delivery.
3. **Step 3:** Extract audio to FLAC for archival.
4. **Step 4:** Generate HLS manifest from the web delivery encode.

Pipelines are defined in the Pipeline Editor view and can be saved, shared, and triggered manually or on a schedule.

---

## Scheduled Encoding

Schedule encoding jobs to run at specific times or on a recurring basis:

- **One-time:** Encode at a specified date and time (e.g., overnight for long encodes).
- **Recurring:** Encode on a cron-like schedule (e.g., every night at 2 AM).
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

MeedyaConverter can detect scene changes in video content:

- **Chapter generation:** Automatically create chapter markers at scene boundaries.
- **Keyframe placement:** Align keyframes with scene changes for better seeking and streaming segment alignment.
- **Segment splitting:** Split a video into individual scenes for separate processing.

Scene detection uses FFmpeg's `scdet` filter with configurable sensitivity thresholds. Results are displayed in the Scene Detector view.

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

Metrics are computed via FFmpeg's `libvmaf` filter and displayed in the Encoding Graphs view.

---

## Content-Aware Encoding

The Content Analyser examines source media to optimise encoding decisions:

- **Complexity analysis:** Detect high-motion and static segments to adjust quality allocation.
- **Grain/noise detection:** Identify noisy footage that benefits from denoising before encoding.
- **Crop recommendation:** Detect letterboxing and pillarboxing for optimal cropping.

---

## AI Upscaling (Experimental)

Upscale lower-resolution content using AI-based super-resolution:

- Scale 720p to 1080p or 1080p to 4K with improved detail.
- Multiple model options with quality/speed trade-offs.

This feature is experimental and requires compatible hardware. It is implemented in the AI Upscaler module.

---

## Next Steps

- [CLI Reference](CLI-Reference) — Automate encoding from the command line.
- [Codec Reference](Codec-Reference) — Detailed settings for every supported codec.
- [Troubleshooting](Troubleshooting) — Solutions for common issues.
