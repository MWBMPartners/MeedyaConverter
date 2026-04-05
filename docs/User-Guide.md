<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# User Guide

This guide covers the key features and settings available in MeedyaConverter.

---

## Encoding Profiles

### Built-in Profiles

MeedyaConverter ships with built-in profiles for common workflows:

| Profile | Video | Audio | Use Case |
|---------|-------|-------|----------|
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
- Custom crop rectangles.

---

## Audio Settings

### Codec Selection

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
- Audio normalization (EBU R128, ReplayGain).

---

## HDR Handling

MeedyaConverter supports comprehensive HDR workflows.

### HDR Formats

| Format | Metadata Type | Supported Operations |
|--------|--------------|---------------------|
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

The Stream Inspector in the GUI shows all available tracks with their properties, and you can configure each one individually.

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
|-----------|----------|-------|-------|-----------|
| **MP4** | Playback, streaming, web | H.264, H.265, AV1 | AAC, AC-3, E-AC-3 | MOV text (limited) |
| **MKV** | Archival, multi-track | All codecs | All codecs | All formats (SRT, ASS, PGS, etc.) |
| **MOV** | Apple/Pro editing | ProRes, H.264, H.265 | AAC, ALAC, PCM | MOV text |
| **WebM** | Web delivery | VP9, AV1 | Opus, Vorbis | WebVTT |
| **TS** | Broadcast, IPTV | H.264, H.265, MPEG-2 | AAC, AC-3, MP2 | DVB-SUB, Teletext |
| **MXF** | Professional broadcast | JPEG 2000, DNxHR, ProRes | PCM | — |

MeedyaConverter validates codec/container compatibility and warns when a combination is unsupported.

---

## Streaming Preparation (HLS / DASH)

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

### Common Streaming Workflow

1. Import your source file.
2. Define quality variants (e.g., 1080p at 5 Mbps, 720p at 3 Mbps, 480p at 1.5 Mbps).
3. Choose HLS, DASH, or both.
4. Encode — MeedyaConverter generates all variants and manifests in one pass.

---

## Next Steps

- [CLI Reference](CLI-Reference) — Automate encoding from the command line.
- [Codec Reference](Codec-Reference) — Detailed settings for every supported codec.
- [Troubleshooting](Troubleshooting) — Solutions for common issues.
