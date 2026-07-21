# Container & Codec Compatibility

> Copyright 2026 MWBM Partners Ltd. All rights reserved.

---

## Overview

Not every video or audio codec can be placed in every container format. This guide shows which codec/container combinations MeedyaConverter supports for **output** (encoding and muxing). MeedyaConverter can **decode** virtually any format, but the output must use a compatible combination.

If you select an incompatible combination, MeedyaConverter will warn you before encoding starts.

---

## Video Codec Compatibility

| Container | H.264 | H.265 | H.266 | AV1 | VP8 | VP9 | ProRes | DNxHR | MPEG-2 | MPEG-4 | FFV1 | Theora | JPEG 2000 |
|-----------|-------|-------|-------|-----|-----|-----|--------|-------|--------|--------|------|--------|-----------|
| **MP4**   |   Y   |   Y   |   Y   |  Y  |     |  Y  |        |       |   Y    |   Y    |      |        |           |
| **M4V**   |   Y   |   Y   |   Y   |  Y  |     |  Y  |        |       |   Y    |   Y    |      |        |           |
| **MKV**   |   Y   |   Y   |   Y   |  Y  |  Y  |  Y  |   Y    |   Y   |   Y    |   Y    |  Y   |   Y    |     Y     |
| **MOV**   |   Y   |   Y   |       |  Y  |     |     |   Y    |   Y   |   Y    |   Y    |      |        |     Y     |
| **WebM**  |       |       |       |  Y  |  Y  |  Y  |        |       |        |        |      |        |           |
| **TS**    |   Y   |   Y   |       |  Y  |     |     |        |       |   Y    |        |      |        |           |
| **MPG**   |       |       |       |     |     |     |        |       |   Y    |   Y    |      |        |           |
| **MXF**   |   Y   |   Y   |       |     |     |     |   Y    |   Y   |   Y    |        |      |        |     Y     |
| **AVI**   |   Y   |   Y   |       |     |     |     |        |   Y   |   Y    |   Y    |  Y   |        |           |
| **FLV**   |   Y   |   Y   |       |     |  Y  |     |        |       |        |        |      |        |           |
| **3GP**   |   Y   |       |       |     |     |     |        |       |        |   Y    |      |        |           |
| **OGG**   |       |       |       |     |  Y  |     |        |       |        |        |      |   Y    |           |

**Y** = Supported

---

## Audio Codec Compatibility

| Container | AAC-LC | HE-AAC | AC-3 | E-AC-3 | TrueHD | DTS | ALAC | Opus | Vorbis | FLAC | PCM | MP3 | MP2 |
|-----------|--------|--------|------|--------|--------|-----|------|------|--------|------|-----|-----|-----|
| **MP4**   |   Y    |   Y    |  Y   |   Y    | Y [1]  |     |  Y   |  Y   |        |  Y   |     |  Y  |     |
| **MKV**   |   Y    |   Y    |  Y   |   Y    |   Y    |  Y  |  Y   |  Y   |   Y    |  Y   |  Y  |  Y  |  Y  |
| **MOV**   |   Y    |   Y    |  Y   |   Y    |        |     |  Y   |  Y   |        |  Y   |  Y  |  Y  |     |
| **WebM**  |        |        |      |        |        |     |      |  Y   |   Y    |      |     |     |     |
| **TS**    |   Y    |   Y    |  Y   |   Y    |        |  Y  |      |  Y   |        |      |     |  Y  |  Y  |
| **MPG**   |        |        |  Y   |        |        |  Y  |      |      |        |      |  Y  |     |  Y  |
| **MXF**   |   Y    |        |  Y   |   Y    |        |     |      |      |        |      |  Y  |     |     |
| **AVI**   |   Y    |        |  Y   |        |        |  Y  |      |      |        |      |  Y  |  Y  |     |
| **FLV**   |   Y    |        |      |        |        |     |      |      |        |      |     |  Y  |     |
| **3GP**   |   Y    |   Y    |      |        |        |     |      |      |        |      |     |     |     |
| **OGG**   |        |        |      |        |        |     |      |  Y   |   Y    |  Y   |     |     |     |
| **AIFF**  |        |        |      |        |        |     |      |      |        |      |  Y  |     |     |
| **CAF**   |   Y    |        |      |        |        |     |  Y   |  Y   |        |  Y   |  Y  |     |     |

**Y** = Supported

### [1] TrueHD in MP4

Dolby TrueHD is **not** part of the official MP4 (ISOBMFF) specification, but is widely supported by major media players including Plex, Jellyfin, VLC, MPC-HC, and Infuse. MeedyaConverter allows TrueHD in MP4 with the following **mandatory rule**:

> **In MP4 containers only:** TrueHD must NOT be the default audio stream. A fully compatible audio codec (AAC, AC-3, or E-AC-3) must also be present and set as the default stream. This ensures all players can play the file — those that support TrueHD will select it, while others fall back to the compatible stream.

**This restriction applies only to MP4-family containers** (MP4, M4V, M4A, M4B). In all other containers where TrueHD is officially supported (MKV, etc.), TrueHD can be set as the default audio stream with no restrictions.

MeedyaConverter enforces this automatically when you include TrueHD in MP4 output.

---

## HDR & Dolby Vision Container Support

| Container | HDR10 | HDR10+ | HLG | Dolby Vision |
|-----------|-------|--------|-----|--------------|
| **MP4**   |   Y   |   Y    |  Y  |      Y       |
| **MKV**   |   Y   |   Y    |  Y  |      Y       |
| **MOV**   |   Y   |   Y    |  Y  |      Y       |
| **WebM**  |   Y   |        |  Y  |              |
| **TS**    |   Y   |        |  Y  |      Y       |
| **MXF**   |   Y   |        |  Y  |              |

HDR metadata is only meaningful when using a compatible video codec (H.265, AV1, VP9) and 10-bit pixel format.

---

## Chapter Support

| Container | Chapters | Chapter Titles | Chapter Languages |
|-----------|----------|----------------|-------------------|
| **MKV**   |    Y     |       Y        |         Y         |
| **MP4**   |    Y     |       Y        |         Y         |
| **M4V**   |    Y     |       Y        |         Y         |
| **M4B**   |    Y     |       Y        |         Y         |
| **MOV**   |    Y     |       Y        |         Y         |
| **OGG**   |    Y     |       Y        |                   |
| **WebM**  |          |                |                   |
| **TS**    |          |                |                   |
| **AVI**   |          |                |                   |

Chapters are copied from source to output by default (`-map_chapters 0`). If the target container doesn't support chapters, they are silently dropped.

---

## Subtitle Support

| Container | SRT/Text | ASS/SSA | WebVTT | PGS (Blu-ray) | DVB-SUB | VobSub |
|-----------|----------|---------|--------|----------------|---------|--------|
| **MKV**   |    Y     |    Y    |   Y    |       Y        |    Y    |   Y    |
| **MP4**   |    Y     |         |        |                |         |        |
| **MOV**   |    Y     |         |        |                |         |        |
| **TS**    |          |         |        |       Y        |    Y    |        |
| **WebM**  |          |         |   Y    |                |         |        |

MKV is the most flexible container for subtitles. When remuxing from MKV to MP4, only text-based subtitles (SRT) are compatible — image-based subtitles (PGS, VobSub) will be dropped unless converted.

---

## Recommendations

| Use Case | Recommended Container | Why |
|----------|-----------------------|-----|
| **Maximum compatibility** | MP4 | Plays everywhere: browsers, phones, TVs, game consoles |
| **Maximum flexibility** | MKV | Supports every codec, subtitle format, and chapter style |
| **Web delivery** | WebM or MP4 | WebM for modern browsers, MP4 for universal fallback |
| **Professional editing** | MOV | Native support in Final Cut Pro, DaVinci Resolve, Premiere |
| **Archival** | MKV | No codec restrictions, open format, full metadata support |
| **Streaming (HLS/DASH)** | MP4 (fragmented) | Required for adaptive bitrate streaming |
| **DVD/Blu-ray authoring** | MPEG-TS / MPEG-PS | Required by disc authoring specifications |
