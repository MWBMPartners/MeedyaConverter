<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Codec Reference

Comprehensive reference for all video and audio codecs supported by MeedyaConverter, including recommended settings, CRF ranges, and container compatibility.

---

## Video Codecs

### Consumer / Streaming Codecs

| Codec | FFmpeg Encoder | HDR | HW Accel | Lossless | Recommended CRF | Notes |
|-------|---------------|-----|----------|----------|-----------------|-------|
| **H.264 / AVC** | `libx264` | No | VT, NVENC, QSV, AMF, VA-API | No | 18-23 | Maximum compatibility. Default for web. |
| **H.265 / HEVC** | `libx265` | Yes (HDR10, HDR10+, HLG, DV) | VT, NVENC, QSV, AMF, VA-API | No | 18-24 | Primary 4K/HDR codec. ~40% smaller than H.264. |
| **H.266 / VVC** | `libvvenc` | Yes | None (experimental) | No | 24-32 | Next-gen. ~30-50% more efficient than HEVC. Experimental. |
| **AV1** | `libsvtav1` / `libaom-av1` | Yes (HDR10, HDR10+, HLG) | VT (M3+), NVENC (RTX 40+), QSV (Arc), AMF (RX 7000+) | No | 20-35 (svtav1) | Best open-source compression. Slower to encode. |
| **VP9** | `libvpx-vp9` | Yes (HDR10, HLG) | None | No | 20-35 | YouTube standard. WebM container. |
| **VP8** | `libvpx` | No | None | No | — (bitrate only) | Legacy. Predecessor to VP9. |
| **AV2** | — | TBD | None | TBD | — | Future. No production encoder yet. |

### Multiview / 3D Codecs

| Codec | FFmpeg Encoder | HDR | HW Accel | Notes |
|-------|---------------|-----|----------|-------|
| **MV-HEVC** | `hevc_videotoolbox` | Yes | VT (Apple Silicon) | Apple Vision Pro, Meta Quest spatial video. |
| **MV-H264** | `libx264` (stereo profile) | No | Limited | Stereoscopic 3D. Left/right eye encoding. |

### Professional / Intermediate Codecs

| Codec | FFmpeg Encoder | Lossless | Quality Tiers | Recommended Use |
|-------|---------------|----------|---------------|-----------------|
| **ProRes** | `prores_ks` / `prores_videotoolbox` | ProRes 4444 XQ | Proxy, LT, Standard, HQ, 4444, 4444 XQ | Professional editing, colour grading, mastering. |
| **DNxHR** | `dnxhd` | DNxHR 444 | LB, SQ, HQ, HQX, 444 | Avid editing workflows. |
| **CineForm** | `cfhd` | Yes | Low, Medium, High, FilmScan, FilmScan2 | GoPro/editing intermediate. |

### Archival / Broadcast Codecs

| Codec | FFmpeg Encoder | Lossless | Notes |
|-------|---------------|----------|-------|
| **FFV1** | `ffv1` | Yes | Archival standard (Library of Congress, national archives). |
| **JPEG 2000** | `libopenjpeg` | Both | Digital Cinema Packages (DCP). |
| **MPEG-2** | `mpeg2video` | No | DVD, broadcast TV. Legacy. |
| **MPEG-4 Part 2** | `mpeg4` | No | Legacy. Predecessor to H.264. |
| **VC-1 / WMV** | Decode only | No | Blu-ray, Windows Media. Decode/passthrough only. |
| **Theora** | `libtheora` | No | Open-source. OGG container. Legacy. |

### CRF Guidelines

CRF (Constant Rate Factor) controls quality. **Lower = better quality, larger file.**

| Quality Level | H.264 CRF | H.265 CRF | AV1 CRF (svtav1) | VP9 CRF |
|--------------|-----------|-----------|-------------------|---------|
| Visually lossless | 15-17 | 15-18 | 15-20 | 15-20 |
| High quality | 18-20 | 18-22 | 20-28 | 20-28 |
| Balanced | 21-23 | 22-26 | 28-35 | 28-35 |
| Small file | 24-28 | 26-32 | 35-45 | 35-45 |
| Low quality | 29+ | 33+ | 46+ | 46+ |

---

## Audio Codecs

### Lossy Codecs

| Codec | FFmpeg Encoder | Max Channels | Recommended Bitrate | Containers |
|-------|---------------|-------------|---------------------|------------|
| **AAC-LC** | `aac` / `libfdk_aac` | 7.1 | 128k (stereo), 384k (5.1) | MP4, MKV, MOV, M4A, TS |
| **HE-AAC v1** | `libfdk_aac` | 7.1 | 48-96k (stereo) | MP4, MKV, M4A, TS |
| **HE-AAC v2** | `libfdk_aac` | Stereo | 32-48k (stereo) | MP4, MKV, M4A |
| **xHE-AAC** | `libfdk_aac` | 7.1 | 24-128k | MP4, M4A |
| **MP3** | `libmp3lame` | Stereo | 128-320k | MP3, MKV, AVI |
| **MP2** | `mp2` | Stereo | 192-384k | TS, MPG |
| **Opus** | `libopus` | 7.1 | 64k (stereo), 256k (5.1) | WebM, MKV, OGG |
| **Vorbis** | `libvorbis` | 7.1 | 128-256k (stereo) | WebM, MKV, OGG |
| **Speex** | `libspeex` | Mono/Stereo | 8-44k | OGG |
| **WMA** | Decode only | 7.1 | — | AVI, WMV |

### Dolby Family

| Codec | FFmpeg Encoder | Max Channels | Recommended Bitrate | Containers |
|-------|---------------|-------------|---------------------|------------|
| **AC-3** (Dolby Digital) | `ac3` | 5.1 | 384-640k | MP4, MKV, MOV, TS, AVI |
| **E-AC-3** (Dolby Digital Plus) | `eac3` | 7.1 | 256-1536k | MP4, MKV, TS |
| **TrueHD** (Dolby TrueHD) | `truehd` | 7.1 | Lossless | MKV, TS (Blu-ray) |
| **AC-4** | Decode/passthrough | 7.1.4 | — | MP4, TS |
| **Dolby MAT** | Passthrough | 7.1.4 | — | TS (HDMI transport) |

### DTS Family

| Codec | FFmpeg Encoder | Max Channels | Recommended Bitrate | Containers |
|-------|---------------|-------------|---------------------|------------|
| **DTS Core** | `dca` | 5.1 | 768-1536k | MKV, TS, AVI |
| **DTS-HD MA** | Decode/passthrough | 7.1 | Lossless | MKV |
| **DTS:X** | Decode/passthrough | Object-based | — | MKV |

### Lossless Codecs

| Codec | FFmpeg Encoder | Max Channels | Compression | Containers |
|-------|---------------|-------------|-------------|------------|
| **PCM** | Various (`pcm_s16le`, etc.) | Unlimited | None (uncompressed) | WAV, MKV, MOV, AVI |
| **FLAC** | `flac` | 7.1 | ~50-60% | FLAC, MKV, OGG |
| **ALAC** | `alac` | 7.1 | ~50-60% | M4A, MOV, MP4 |
| **WavPack** | `wavpack` | Unlimited | ~50-70% | WV, MKV |
| **TTA** | `tta` | Unlimited | ~50% | TTA, MKV |
| **APE** | Decode only | Stereo | ~45-55% | APE |

### High-Resolution / Specialist

| Codec | FFmpeg Support | Notes |
|-------|---------------|-------|
| **DSD** | Decode | SACD format. 1-bit delta-sigma. DFF/DSF files. |
| **MQA** | Decode (first unfold) | Meridian high-res. Proprietary encoding. |
| **Musepack** | Decode | Audiophile lossy. External encoder only. |
| **ATRAC** | Decode | Sony MiniDisc/PlayStation codec family. |

### Spatial / Immersive Audio

| Codec | FFmpeg Support | Notes |
|-------|---------------|-------|
| **IAMF / Eclipsa Audio** | Emerging | Google/AOM open immersive audio. |
| **MPEG-H 3D Audio** | Limited | Object-based broadcast spatial audio (ATSC 3.0). |
| **360 Reality Audio** | Decode/passthrough | Sony object-based spatial (MPEG-H based). |
| **ASAF** | Passthrough | Apple Spatial Audio Format. |
| **Ambisonics** | Encode/decode | Full-sphere spatial. FOA (4ch) to HOA (16+ch). |
| **Auro-3D** | Passthrough | Height-channel surround. |
| **NHK 22.2** | Channel mapping | 24-channel broadcast format. |

---

## Container Compatibility Matrix

| Container | H.264 | H.265 | AV1 | VP9 | ProRes | AAC | AC-3 | E-AC-3 | FLAC | Opus | DTS | TrueHD |
|-----------|-------|-------|-----|-----|--------|-----|------|--------|------|------|-----|--------|
| **MP4** | Yes | Yes | Yes | No | No | Yes | Yes | Yes | No | Yes* | No | No |
| **MKV** | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| **MOV** | Yes | Yes | No | No | Yes | Yes | Yes | No | Yes | No | No | No |
| **WebM** | No | No | Yes | Yes | No | No | No | No | No | Yes | No | No |
| **TS** | Yes | Yes | No | No | No | Yes | Yes | Yes | No | No | Yes | Yes |
| **MXF** | No | No | No | No | Yes | No | No | No | No | No | No | No |
| **AVI** | Yes | No | No | No | No | No | Yes | No | No | No | Yes | No |
| **OGG** | No | No | No | No | No | No | No | No | Yes | Yes | No | No |

*Opus in MP4 has limited player support.

MeedyaConverter validates these combinations and warns when an incompatible codec/container pairing is selected.
