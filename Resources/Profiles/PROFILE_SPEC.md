# 🎛️ MeedyaConverter — Encoding Profile Specification

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.
>
> This document defines the built-in encoding profiles with optimised quality parameters.

---

## Profile Naming Convention

```text
{Resolution}_{HDR/SDR}_{Codec}_{Mode}_{HW}
```

Example: `4K_HDR_H265_VBR_SW` = 4K UHD HDR, H.265, VBR, Software encoded

---

## Video Profiles — CRF/QP Values (VBR Mode, File-Based Encoding)

VBR is preferred for file-based encoding. Lower CRF = higher quality, larger files.

### H.264 (x264 Software / Hardware)

| Resolution | HDR | CRF (SW) | QP (HW) | Max Bitrate | Notes |
| ---------- | --- | -------- | ------- | ----------- | ----- |
| 8K UHD | SDR | 17 | 20 | 120 Mbps | H.264 not recommended for 8K |
| 4K UHD | SDR | 18 | 21 | 60 Mbps | |
| 1440p | SDR | 19 | 22 | 30 Mbps | |
| 1080p | SDR | 20 | 23 | 15 Mbps | Most common target |
| 720p | SDR | 21 | 24 | 8 Mbps | |
| 640p | SDR | 22 | 25 | 5 Mbps | |
| 576p | SDR | 23 | 26 | 3.5 Mbps | PAL DVD resolution |
| 480p | SDR | 23 | 26 | 2.5 Mbps | NTSC DVD resolution |
| 360p | SDR | 25 | 28 | 1.5 Mbps | Mobile/low bandwidth |
| 240p | SDR | 27 | 30 | 0.8 Mbps | |
| 120p | SDR | 30 | 33 | 0.4 Mbps | Thumbnail/preview |

> H.264 does not support HDR metadata. HDR sources should use H.265/AV1.

### H.265/HEVC (x265 Software / Hardware)

| Resolution | HDR | CRF (SW) | QP (HW) | Max Bitrate | Notes |
| ---------- | --- | -------- | ------- | ----------- | ----- |
| 8K UHD | HDR | 18 | 21 | 80 Mbps | Preserve HDR10/DV metadata |
| 8K UHD | SDR | 19 | 22 | 70 Mbps | |
| 4K UHD | HDR | 20 | 23 | 40 Mbps | Primary HDR target |
| 4K UHD | SDR | 21 | 24 | 30 Mbps | |
| 1440p | HDR | 21 | 24 | 20 Mbps | |
| 1440p | SDR | 22 | 25 | 15 Mbps | |
| 1080p | HDR | 22 | 25 | 12 Mbps | |
| 1080p | SDR | 23 | 26 | 8 Mbps | |
| 720p | HDR | 23 | 26 | 6 Mbps | |
| 720p | SDR | 24 | 27 | 4 Mbps | |
| 640p | SDR | 25 | 28 | 3 Mbps | |
| 576p | SDR | 26 | 29 | 2 Mbps | |
| 480p | SDR | 26 | 29 | 1.5 Mbps | |
| 360p | SDR | 28 | 31 | 0.8 Mbps | |
| 240p | SDR | 30 | 33 | 0.5 Mbps | |
| 120p | SDR | 33 | 36 | 0.2 Mbps | |

### AV1 (libaom/SVT-AV1 Software / Hardware)

| Resolution | HDR | CRF (SW) | QP (HW) | Max Bitrate | Notes |
| ---------- | --- | -------- | ------- | ----------- | ----- |
| 8K UHD | HDR | 22 | 25 | 60 Mbps | Best efficiency at high res |
| 8K UHD | SDR | 23 | 26 | 50 Mbps | |
| 4K UHD | HDR | 24 | 27 | 30 Mbps | |
| 4K UHD | SDR | 26 | 29 | 20 Mbps | |
| 1440p | HDR | 26 | 29 | 15 Mbps | |
| 1440p | SDR | 28 | 31 | 10 Mbps | |
| 1080p | HDR | 28 | 31 | 8 Mbps | |
| 1080p | SDR | 30 | 33 | 5 Mbps | |
| 720p | HDR | 30 | 33 | 4 Mbps | |
| 720p | SDR | 32 | 35 | 2.5 Mbps | |
| 640p | SDR | 34 | 37 | 1.8 Mbps | |
| 576p | SDR | 35 | 38 | 1.2 Mbps | |
| 480p | SDR | 36 | 39 | 1 Mbps | |
| 360p | SDR | 38 | 41 | 0.5 Mbps | |
| 240p | SDR | 40 | 43 | 0.3 Mbps | |
| 120p | SDR | 45 | 48 | 0.1 Mbps | |

> AV1 CRF scale differs from x264/x265. Higher CRF values produce equivalent quality.

### H.266/VVC (vvenc Software — when available)

| Resolution | HDR | CRF (SW) | Max Bitrate | Notes |
| ---------- | --- | -------- | ----------- | ----- |
| 8K UHD | HDR | 24 | 50 Mbps | ~30% more efficient than HEVC |
| 4K UHD | HDR | 26 | 25 Mbps | |
| 4K UHD | SDR | 28 | 18 Mbps | |
| 1080p | HDR | 30 | 6 Mbps | |
| 1080p | SDR | 32 | 4 Mbps | |
| 720p | SDR | 34 | 2 Mbps | |

> H.266/VVC encoder maturity is limited. Values are estimated based on VVC efficiency vs HEVC. Adjust as encoders mature.

### AV2 (future — no production encoder yet)

> AV2 is still in research at the Alliance for Open Media. No CRF values can be specified until an encoder exists. Placeholder profiles will be created when an encoder becomes available. Expected ~30% improvement over AV1.

### Theora (software only — no hardware acceleration exists)

| Resolution | CRF Equivalent (quality) | Max Bitrate | Notes |
| ---------- | ------------------------ | ----------- | ----- |
| 1080p | 7 (0-10 scale) | 8 Mbps | Theora maxes at ~1080p practically |
| 720p | 6 | 4 Mbps | |
| 480p | 5 | 1.5 Mbps | |
| 360p | 4 | 0.8 Mbps | |

> Theora uses a 0-10 quality scale (not CRF). No hardware encoding exists for Theora on any platform.

---

## Video Profiles — CVBR Mode (Adaptive Streaming: HLS/MPEG-DASH)

For adaptive streaming, Constrained VBR (CVBR) is preferred for predictable bandwidth and smooth quality switching. Both target and max bitrate are specified.

### H.265/HEVC ABR Ladder (Recommended for HLS/DASH)

| Resolution | HDR | Target Bitrate | Max Bitrate | Buffer Size | Keyframe Interval |
| ---------- | --- | -------------- | ----------- | ----------- | ----------------- |
| 4K UHD | HDR | 16 Mbps | 24 Mbps | 32 Mbps | 2s (GOP) |
| 4K UHD | SDR | 12 Mbps | 18 Mbps | 24 Mbps | 2s |
| 1440p | SDR | 8 Mbps | 12 Mbps | 16 Mbps | 2s |
| 1080p | HDR | 6 Mbps | 9 Mbps | 12 Mbps | 2s |
| 1080p | SDR | 4.5 Mbps | 6.75 Mbps | 9 Mbps | 2s |
| 720p | SDR | 2.5 Mbps | 3.75 Mbps | 5 Mbps | 2s |
| 480p | SDR | 1 Mbps | 1.5 Mbps | 2 Mbps | 2s |
| 360p | SDR | 0.5 Mbps | 0.75 Mbps | 1 Mbps | 2s |

### H.264/AVC ABR Ladder

| Resolution | Target Bitrate | Max Bitrate | Buffer Size |
| ---------- | -------------- | ----------- | ----------- |
| 1080p | 6 Mbps | 9 Mbps | 12 Mbps |
| 720p | 3.5 Mbps | 5.25 Mbps | 7 Mbps |
| 480p | 1.5 Mbps | 2.25 Mbps | 3 Mbps |
| 360p | 0.7 Mbps | 1.05 Mbps | 1.4 Mbps |
| 240p | 0.4 Mbps | 0.6 Mbps | 0.8 Mbps |

### AV1 ABR Ladder

| Resolution | HDR | Target Bitrate | Max Bitrate | Buffer Size |
| ---------- | --- | -------------- | ----------- | ----------- |
| 4K UHD | HDR | 10 Mbps | 15 Mbps | 20 Mbps |
| 4K UHD | SDR | 8 Mbps | 12 Mbps | 16 Mbps |
| 1080p | SDR | 3 Mbps | 4.5 Mbps | 6 Mbps |
| 720p | SDR | 1.5 Mbps | 2.25 Mbps | 3 Mbps |
| 480p | SDR | 0.7 Mbps | 1.05 Mbps | 1.4 Mbps |
| 360p | SDR | 0.35 Mbps | 0.5 Mbps | 0.7 Mbps |

---

## Audio Profiles — Bitrate by Codec and Channel Layout

VBR is preferred where the codec supports it. Frequency and channel arrangement default to matching source.

### Lossy Codecs

| Codec | Mono | Stereo | 5.1 | 7.1 | VBR Support | Notes |
| ----- | ---- | ------ | --- | --- | ----------- | ----- |
| **MP3** | 96 kbps | 192 kbps | N/A | N/A | ✅ VBR (V2) | Max stereo; LAME VBR quality 2 |
| **MP3 HD** | 128 kbps | 256 kbps | N/A | N/A | ⚠️ Limited | Lossless extension on top of MP3 |
| **MP3surround** | N/A | 192 kbps (stereo core) | 320 kbps | N/A | ⚠️ Limited | Backward-compatible surround |
| **OGG Vorbis** | 96 kbps | 192 kbps | 384 kbps | 512 kbps | ✅ VBR (q6) | Quality 6 default |
| **AAC-LC** | 96 kbps | 160 kbps | 384 kbps | 512 kbps | ✅ VBR | Most compatible |
| **HE-AAC (v1)** | 48 kbps | 80 kbps | 192 kbps | 256 kbps | ✅ VBR | SBR; best at low bitrates |
| **HE-AACv2** | 32 kbps | 48 kbps | N/A | N/A | ✅ VBR | SBR+PS; stereo only |
| **xHE-AAC (USAC)** | 24 kbps | 48 kbps | 128 kbps | 192 kbps | ✅ VBR | Best quality at very low bitrate |
| **Dolby Digital (AC-3)** | 96 kbps | 192 kbps | 448 kbps | N/A | ❌ CBR only | Max 5.1; 640 kbps max total |
| **Dolby Digital EX** | N/A | N/A | 448 kbps | N/A | ❌ CBR only | 6.1 matrix in 5.1 |
| **Dolby Digital Plus (E-AC-3)** | 96 kbps | 192 kbps | 384 kbps | 640 kbps | ❌ CBR only | Up to 7.1; more efficient than AC-3 |
| **Dolby AC-4** | — | — | — | — | — | ❌ FFmpeg cannot encode AC-4 — decode/passthrough only |
| **DTS** | 96 kbps | 192 kbps | 768 kbps | N/A | ❌ CBR only | DTS core; max 1536 kbps |
| **DTS ES** | N/A | N/A | 768 kbps | N/A | ❌ CBR only | 6.1 matrix/discrete |
| **Circle Surround** | N/A | 192 kbps (stereo carrier) | N/A | N/A | — | ❌ No FFmpeg encoder — matrix metadata in stereo signal |
| **Eclipsa (IAMF)** | 64 kbps | 128 kbps | 256 kbps | 384 kbps | ✅ VBR | Object-based; via libiamf |
| **Opus** | 64 kbps | 128 kbps | 256 kbps | 384 kbps | ✅ VBR | Best open-source lossy codec |

### Audio Bitrate for Adaptive Streaming (CVBR)

For HLS/DASH, use constrained bitrates for bandwidth predictability:

| Codec | Stereo Target | Stereo Max | 5.1 Target | 5.1 Max |
| ----- | ------------- | ---------- | ---------- | ------- |
| AAC-LC | 128 kbps | 160 kbps | 320 kbps | 384 kbps |
| HE-AAC | 64 kbps | 80 kbps | 160 kbps | 192 kbps |
| E-AC-3 | 160 kbps | 192 kbps | 320 kbps | 384 kbps |
| Opus | 96 kbps | 128 kbps | 192 kbps | 256 kbps |

---

## Hardware Encoder Availability by Platform

| Codec | macOS (VideoToolbox) | Windows (NVENC) | Windows (QSV) | Windows (AMF) | Linux (VAAPI) |
| ----- | -------------------- | --------------- | ------------- | ------------- | ------------- |
| H.264 | ✅ | ✅ | ✅ | ✅ | ✅ |
| H.265/HEVC | ✅ | ✅ | ✅ | ✅ | ✅ |
| AV1 | ✅ (M3+) | ✅ (RTX 40+) | ✅ (Arc) | ✅ (RX 7000+) | ✅ |
| H.266/VVC | ❌ Not yet | ❌ Not yet | ❌ Not yet | ❌ Not yet | ❌ Not yet |
| VP9 | ❌ | ❌ | ✅ | ❌ | ✅ |
| Theora | ❌ | ❌ | ❌ | ❌ | ❌ |
| AV2 | ❌ | ❌ | ❌ | ❌ | ❌ |

> Hardware encoder QP values are generally 2-3 points higher than software CRF for equivalent visual quality due to less sophisticated rate-distortion optimisation.

---

## Profile Categories (Pre-built)

### Quick Start Profiles

| Profile Name | Video | Audio | Container | Use Case |
| ------------ | ----- | ----- | --------- | -------- |
| Web Standard | H.264 CRF 20, 1080p | AAC 160k stereo | MP4 | Maximum compatibility |
| Web High Quality | H.265 CRF 22, 1080p | AAC 192k stereo | MP4 | Good quality, smaller files |
| Web Next-Gen | AV1 CRF 30, 1080p | Opus 128k stereo | WebM | Best efficiency |
| 4K HDR Master | H.265 CRF 18, 4K HDR | E-AC-3 640k 7.1 | MKV | High-quality archive |
| Audio Extract | Passthrough | FLAC lossless | MKA | Extract audio only |
| Quick Convert | H.264 CRF 23, match source | AAC 128k | MP4 | Fast, good enough |
| Archive Lossless | FFV1 lossless | FLAC lossless | MKV | Archival preservation |

### Streaming Profiles (CVBR for HLS/DASH)

| Profile Name | Ladder | Video | Audio | Encryption |
| ------------ | ------ | ----- | ----- | ---------- |
| Apple HLS Standard | 1080/720/480/360 | H.264 CVBR | AAC 128k/64k | AES-128 optional |
| Apple HLS Premium | 4K/1080/720/480/360 | H.265 CVBR | AAC 192k/128k/64k | AES-128 optional |
| MPEG-DASH Standard | 1080/720/480 | H.264 CVBR | AAC 128k | None |
| MPEG-DASH Premium | 4K/1080/720/480 | AV1 CVBR | Opus 128k | None |
| YouTube-like ABR | 4K/1440/1080/720/480/360/240 | H.264+H.265 | AAC 128k | None |

### Disc Authoring Profiles

| Profile Name | Video | Audio | Container |
| ------------ | ----- | ----- | --------- |
| DVD Standard | MPEG-2, 720x480/576 | AC-3 448k 5.1 | MPEG-PS |
| Blu-ray Standard | H.264, 1080p | DTS 768k 5.1 + AC-3 448k 5.1 | MPEG-TS |
| Blu-ray Premium | H.265, 4K HDR | TrueHD 7.1 + AC-3 448k 5.1 | MPEG-TS |

---

*All values are starting defaults optimised by community consensus and professional engineering standards. Users can adjust any parameter.*
