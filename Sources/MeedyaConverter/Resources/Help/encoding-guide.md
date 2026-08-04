# 🎬 Encoding Guide

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overview

This guide covers all encoding settings available in MeedyaConverter, including video codecs, audio codecs, container formats, and quality settings.

> This document will be expanded as features are implemented during development.

---

## Video Codecs

| Codec | Use Case | HDR Support | Hardware Accel |
| ----- | -------- | ----------- | -------------- |
| **H.264/AVC** | Maximum compatibility | No | Yes |
| **H.265/HEVC** | High quality, smaller files | Yes | Yes |
| **AV1** | Next-gen efficiency | Yes | Limited |
| **VP9** | WebM/web playback | Yes | Limited |
| **VP8** | Legacy WebM | No | No |
| **ProRes** | Professional editing | No | Yes (macOS) |
| **MPEG-2** | DVD/broadcast compatibility | No | No |
| **MPEG-4** | Legacy compatibility | No | No |
| **DNxHR** | Professional post-production | No | No |
| **Theora** | Open-source video | No | No |

## Audio Codecs

| Codec | Use Case | Channels | Lossless | Encode | Decode | Passthrough |
| ----- | -------- | -------- | -------- | ------ | ------ | ----------- |
| **AAC-LC** | Standard web/mobile | Up to 7.1 | No | ✅ | ✅ | ✅ |
| **HE-AAC / HE-AACv2** | Low bitrate streaming | Up to 5.1 | No | ✅ | ✅ | ✅ |
| **Dolby AC-3** | DVD/Blu-ray, streaming | 5.1 | No | ✅ | ✅ | ✅ |
| **Dolby E-AC-3** | Streaming, Blu-ray | Up to 7.1 | No | ✅ | ✅ | ✅ |
| **Dolby E-AC-3 + Atmos** | Streaming with spatial objects | 7.1.4 (objects) | No | ❌ Dolby tools | ✅ | ✅ |
| **Dolby TrueHD** | Blu-ray lossless | Up to 7.1 | Yes | ✅ FFmpeg `truehd` | ✅ | ✅ |
| **Dolby TrueHD + Atmos** | Blu-ray lossless + spatial | 7.1.4 (objects) | Yes | ❌ Dolby tools | ✅ | ✅ |
| **Dolby AC-4** | Next-gen broadcast/streaming | Up to 7.1.4 | No | ❌ Dolby tools | ⚠️ Limited | ✅ |
| **DTS** | DVD/Blu-ray | 5.1 | No | ✅ | ✅ | ✅ |
| **DTS-HD MA** | Blu-ray lossless | 7.1 | Yes | ❌ Proprietary | ✅ | ✅ |
| **DTS:X** | Blu-ray spatial | 7.1.4 (objects) | No | ❌ Proprietary | ✅ | ✅ |
| **MP3** | Legacy audio | Stereo | No | ✅ | ✅ | ✅ |
| **MP2** | Broadcast/DVD | Stereo | No | ✅ | ✅ | ✅ |
| **FLAC** | Lossless archival | Up to 7.1 | Yes | ✅ | ✅ | ✅ |
| **ALAC** | Apple lossless | Up to 7.1 | Yes | ✅ | ✅ | ✅ |
| **Opus** | Modern streaming | Up to 7.1 | No | ✅ | ✅ | ✅ |
| **Vorbis** | Open-source streaming | Up to 7.1 | No | ✅ | ✅ | ✅ |
| **PCM** | Uncompressed audio | Unlimited | Yes | ✅ | ✅ | ✅ |
| **DSD (DFF/DSF)** | SACD audio | Up to 5.1 | Yes (1-bit) | ⚠️ Via PCM | ✅ | ✅ |
| **WavPack** | Lossless + hybrid | Up to 7.1 | Yes | ✅ | ✅ | ✅ |
| **MQA** | High-res authenticated | Stereo | Hybrid | ❌ Proprietary | ✅ Unfold | ✅ |

> ❌ Dolby tools = requires Dolby's proprietary encoding tools (not available in FFmpeg)
> ❌ Proprietary = codec owner's proprietary encoder required

## Container Formats

| Container | Video | Audio | Subtitles | Streaming |
| --------- | ----- | ----- | --------- | --------- |
| **MP4** | Yes | Yes | Limited | HLS/DASH |
| **MKV** | Yes | Yes | Full | No |
| **MOV** | Yes | Yes | Limited | No |
| **WebM** | VP8/VP9/AV1 | Opus/Vorbis | WebVTT | DASH |
| **M4A** | No | Yes | No | No |
| **MKA** | No | Yes | No | No |

---

## Quality Settings

### Constant Rate Factor (CRF)

CRF provides consistent quality across the entire encode. Lower values = higher quality, larger files.

| CRF Range | Quality | Typical Use |
| --------- | ------- | ----------- |
| 0-15 | Visually lossless | Archival, mastering |
| 16-22 | High quality | Streaming, distribution |
| 23-28 | Good quality | Web, mobile |
| 29-35 | Low quality | Previews, thumbnails |

### Constant Bitrate (CBR) / Variable Bitrate (VBR)

For streaming, bitrate-based encoding ensures predictable file sizes and bandwidth requirements.

---

*This guide will be expanded with detailed settings as each codec is implemented.*
