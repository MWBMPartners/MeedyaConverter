# 🎬 MeedyaConverter

> **A modern, cross-platform media conversion toolkit with adaptive streaming support**
>
> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-blue)
![Swift](https://img.shields.io/badge/Swift-6.3-orange)
![License](https://img.shields.io/badge/License-Proprietary-red)

---

## 🚀 What is MeedyaConverter?

MeedyaConverter is a professional-grade media conversion application designed for website owners and media professionals who need to prepare audio and video content for on-demand streaming. Think of it as a **modern alternative to HandBrake** — with significantly expanded capabilities.

### ✨ Key Features

| Feature | Description |
| ------- | ----------- |
| 🎞️ **Video/Audio/Subtitle Passthrough** | Copy streams without re-encoding — HandBrake forces re-encoding |
| 📡 **HLS & MPEG-DASH Preparation** | Multi-bitrate adaptive streaming from a single source file |
| 🎨 **HDR Preservation** | HDR10, HDR10+, HLG, and Dolby Vision support |
| 🔄 **HDR10+ → Dolby Vision** | Automatic Dolby Vision creation from HDR10+ content |
| 🎵 **Audio Normalization** | EBU R128, ReplayGain, and peak limiting |
| 📝 **Full Subtitle Support** | SRT, TTML, WebVTT, SSA/ASS, CC608/CC708, DVB-SUB, SAMI, LRC |
| 🔐 **DRM & Encryption** | AES-128 encryption for HLS with key management |
| ☁️ **Cloud Upload** | Direct upload to S3, Azure, Cloudflare Stream, and 10+ providers |
| 🖼️ **Thumbnail Sprites** | Auto-generate preview scrubbing sprites for video players |
| 🔏 **Forensic Watermarking** | Invisible watermark embedding for content protection |
| 🎥 **3D / Stereoscopic** | MV-HEVC (Apple Vision Pro spatial) and MV-H264 multiview encoding |
| 💿 **Optical Disc Ripping** | 22 disc types: Audio CD, SACD, DVD, DVD Audio, Blu-ray, UHD BD, and more — disc, image, or folder |
| 💽 **Disc Authoring & Burning** | Create disc images and burn to physical media for all supported disc types |
| 🖥️ **Cross-Platform** | macOS (primary), Windows, Linux including Raspberry Pi |
| 🏷️ **Media Metadata Lookup** | Auto-tag via MusicBrainz, TMDB, TVDB, IMDB, MeedyaDB, Discogs |
| 📊 **Quality Metrics** | VMAF, SSIM, PSNR objective quality scoring |
| 👁️ **A/B Comparison** | Side-by-side source vs encoded viewer |
| 📂 **Watch Folders** | Monitor folders for new files, auto-encode |
| 🔍 **Scene Detection** | Auto-chaptering from scene boundaries |
| 🔎 **AI Upscaling** | Resolution enhancement via Real-ESRGAN |
| 🖼️ **Image Conversion** | Bulk image format conversion (future version) |
| 💻 **CLI Mode** | Full command-line interface for automation and scripting |

---

## 🏗️ Architecture

MeedyaConverter uses a **modular architecture** with a shared cross-platform core:

```text
┌──────────────────────────────────────────────┐
│           Platform-Specific UIs              │
│  macOS (SwiftUI) │ Windows (WinUI) │ Linux   │
├──────────────────────────────────────────────┤
│             meedya-convert                   │
│         (Command-Line Interface)             │
├──────────────────────────────────────────────┤
│            ConverterEngine                   │
│  Encoding Backend (hybrid)  │ Manifest │ HDR  │
│  Encoding Profiles │ Audio  │ Subs     │ Cloud│
└──────────────────────────────────────────────┘
```

- **ConverterEngine** — Cross-platform Swift package with all encoding, analysis, and processing logic
- **meedya-convert** — Command-line tool built on ConverterEngine
- **MeedyaConverter** — Native SwiftUI macOS application (primary platform)

> Internal target names are deliberately distinct from the Meedya product family (MeedyaDL, MeedyaManager, MeedyaDB) to avoid confusion.

---

## 📋 Supported Formats

### 📦 Output Containers

MP4, M4V, M4A, M4B, M4P, MKV, MKA, MKS, MK3D, MOV, WebM, HLS (.m3u8), MPEG-DASH (.mpd), MXF, AVI, FLV, MPEG-TS (.ts), MPEG-PS (.mpg), 3GP/3G2, OGG/OGM, DCP, AIFF, CAF, W64, RF64

### 🎥 Video Codecs

H.264/AVC, H.265/HEVC, MV-HEVC, MV-H264, AV1, VP8, VP9, ProRes, MPEG-2, MPEG-4, DNxHR, Theora, FFV1, CineForm, VC-1/WMV, JPEG 2000

### 🔊 Audio Codecs

AAC (LC, HE-AAC, HE-AACv2), Dolby Digital (AC-3, E-AC-3, TrueHD, Atmos, AC-4, MAT), DTS (Core, DTS-HD, DTS:X), PCM, MP3, MP2, FLAC, ALAC, Opus, Vorbis, DSD (DFF/DSF), WavPack, AIFF, MQA (decode), Musepack, APE, TTA, WMA (decode), ATRAC (decode), Speex

### 🎧 Spatial & Immersive Audio

Dolby Atmos, Eclipsa Audio (IAMF), MPEG-H 3D Audio, 360 Reality Audio, ASAF (Apple Spatial Audio), Ambisonics (FOA/HOA), Auro-3D, NHK 22.2, AC-4 A-JOC

### 📝 Subtitles & Captions

SRT, TTML, WebVTT, SSA/ASS, SAMI, LRC (Enhanced & Walaoke), CC608, CEA-708 (EIA-708), DVB-SUB, PGS (Blu-ray), VobSub (DVD), EBU STL, SCC, MCC, EBU Teletext / DVB Teletext — including OCR conversion from bitmap to text formats

### 💿 Optical Disc Formats (Ripping, Authoring & Cloning)

Audio CD, SACD, Hybrid SACD, SHM-SACD, SHM-CD, Blu-spec CD, HDCD, DTS CD, CD-MIDI, CD+G, Mixed Mode CD, Enhanced CD (eCD/CD+), CDV, DualDisc, Video CD, Super Video CD, DVD-Video, DVD Audio, HD DVD, Blu-ray, Blu-ray 3D, Ultra HD Blu-ray

> Supports physical discs, disc images (ISO, BIN/CUE, MDF/MDS, NRG, IMG), extracted disc structures (VIDEO\_TS, BDMV), and bit-for-bit disc cloning.

---

## 🖥️ Platform Support

| Platform | Architecture | UI Framework | Priority |
| -------- | ----------- | ----------- | -------- |
| **macOS** | Apple Silicon (M1+) | Swift 6.3 / SwiftUI | 🔴 Primary |
| **Windows** | x86, x64, ARM | WinUI 3 | 🟡 Secondary |
| **Linux** | x86, x64, ARM, ARMv7, ARM64 | GTK4 | 🟢 Tertiary |
| **CLI** | All platforms | Swift ArgumentParser | 🔴 Primary |

---

## 🛠️ Tech Stack

| Component | Technology |
| --------- | --------- |
| Language | Swift 6.3 |
| macOS UI | SwiftUI |
| Media Engine | Hybrid — FFmpeg subprocess (direct) + AVFoundation/FFmpegKit (App Store) |
| HDR Tools | dovi_tool, DDVT (bundled) |
| Package Manager | Swift Package Manager |
| CI/CD | GitHub Actions |
| Auto-Update | Sparkle 2 (direct distribution); Apple-managed (App Store) |

---

## 📁 Repository Structure

```text
MeedyaConverter/
├── Sources/
│   ├── ConverterEngine/     # Cross-platform core engine
│   ├── meedya-convert/      # Command-line interface
│   └── MeedyaConverter/     # macOS SwiftUI application
├── Tests/                   # Unit & integration tests
├── Resources/               # Built-in profiles & help content
├── Tools/                   # Bundled third-party executables
├── help/                    # User documentation (Markdown)
├── branding/                # Brand assets (logos, icons)
├── docs/                    # Extended documentation
├── .github/                 # CI/CD workflows & issue templates
├── .claude/                 # Claude AI development context
├── Project_Plan.md          # Detailed project plan & milestones
├── PROJECT_STATUS.md        # Current development status
└── CHANGELOG.md             # Version history & changes
```

---

## 🗺️ Roadmap

| Phase | Description | Status | Release |
| ----- | ----------- | ------ | ------- |
| **Phase 0** | Project Setup & Architecture | 🚧 In Progress | — |
| **Phase 1** | Core Engine Foundation | ⏳ Planned | Alpha 0.1 |
| **Phase 2** | macOS SwiftUI Application (MVP) | ⏳ Planned | Alpha 0.1 |
| **Phase 3** | Essential Encoding & Passthrough | ⏳ Planned | Alpha 0.2 |
| **Phase 4** | CLI Tool | ⏳ Planned | Alpha 0.2 |
| **Phase 5** | Subtitles & Core Audio Processing | ⏳ Planned | Beta 0.5 |
| **Phase 6** | Adaptive Streaming (HLS/MPEG-DASH) | ⏳ Planned | Beta 0.5 |
| **Phase 7** | Extended Formats & Spatial Audio | ⏳ Planned | Beta 0.7 |
| **Phase 8** | Advanced Audio Processing | ⏳ Planned | Beta 0.7 |
| **Phase 9** | Professional Features | ⏳ Planned | RC 0.9 |
| **Phase 10** | Optical Disc Ripping (22 disc types) | ⏳ Planned | v1.1+ |
| **Phase 11** | Disc Image Creation & Burning | ⏳ Planned | v1.2+ |
| **Phase 12** | Cloud Integration & Uploads | ⏳ Planned | v1.3+ |
| **Phase 13** | Platform Expansion — Windows | ⏳ Planned | v2.0 |
| **Phase 14** | Platform Expansion — Linux | ⏳ Planned | v2.0 |
| **Phase 15** | Media Metadata Lookup | ⏳ Planned | v1.5+ |
| **Phase 16** | Polish & Distribution | ⏳ Ongoing | Ongoing |
| **Phase 17** | Image Conversion (future version) | ⏳ Planned | v3.0+ |
| **Phase 18** | AI-Powered Features (wishlist) | 🔮 Wishlist | TBD |

> 📌 See [Project_Plan.md](Project_Plan.md) for detailed milestone breakdown.
> 📊 See [PROJECT_STATUS.md](PROJECT_STATUS.md) for current progress.

---

## 🚀 Getting Started

> ⚠️ MeedyaConverter is currently in early development (Phase 0). Build instructions will be refined as the core engine matures.

### Prerequisites

- **macOS 15+** (Sequoia or later)
- **Xcode 16.3+** (with Swift 6.3)
- **FFmpeg** (bundled with app, or install via Homebrew for development: `brew install ffmpeg`)

### Building from Source

```bash
# Clone the repository
git clone https://github.com/MWBMPartners/MeedyaConverter.git
cd MeedyaConverter

# Build all targets
swift build

# Run tests
swift test

# Build release configuration
swift build -c release
```

### Branch Strategy

| Branch | Purpose | Release Type |
| ------ | ------- | ------------ |
| `main` | Stable releases | Production (tagged `vX.Y.Z`) |
| `beta` | Beta testing | Pre-release (`vX.Y.Z-beta.N`) |
| `alpha` | Early development | Pre-release (`vX.Y.Z-alpha.N`) |

---

## 📖 Documentation

| Resource | Description |
| -------- | ----------- |
| 📋 [Project Plan](Project_Plan.md) | Milestones, architecture, and tech stack |
| 📊 [Project Status](PROJECT_STATUS.md) | Current development progress |
| 📝 [Changelog](CHANGELOG.md) | Version history and changes |
| 📚 [Help Documentation](help/) | User guides, FAQ, troubleshooting |
| 🔧 [CLI Reference](help/cli-reference.md) | Command-line usage |
| 🔊 [Audio Format Compatibility](help/audio-format-compatibility.md) | Conversion matrix — what converts to what |
| 📖 [GitHub Wiki](https://github.com/MWBMPartners/MeedyaConverter/wiki) | Architecture, API docs, dev guide |
| 🔒 [Security Policy](.github/SECURITY.md) | Vulnerability reporting |

---

## 🔒 Security

See our [Security Policy](.github/SECURITY.md) for information on reporting vulnerabilities. We take security seriously and respond to reports promptly.

---

## 🧩 Part of the Meedya Family

MeedyaConverter is part of the **Meedya product suite** by MWBM Partners Ltd:

| Product | Description | Repository |
| ------- | ----------- | ---------- |
| **MeedyaConverter** | Media conversion & streaming preparation | This repo |
| **MeedyaDL** | Media downloader | [MWBMPartners/MeedyaDL](https://github.com/MWBMPartners/MeedyaDL) |
| **MeedyaManager** | Media library management | [MWBMPartners/MeedyaManager](https://github.com/MWBMPartners/MeedyaManager) |
| **MeedyaDB** | Media database | [MWBMPartners/MeedyaDB](https://github.com/MWBMPartners/MeedyaDB) |

---

## 📜 License

**Proprietary** — Copyright © 2026 MWBM Partners Ltd. All rights reserved.

This software is the proprietary product of MWBM Partners Ltd. Unauthorized copying, distribution, modification, or use of this software is strictly prohibited without prior written permission.

### Third-Party Licenses

MeedyaConverter bundles or uses the following open-source components, each under their own respective licenses:

| Component | License | Usage |
| --------- | ------- | ----- |
| FFmpeg | LGPL 2.1 / GPL 2+ | Subprocess (direct) or FFmpegKit LGPL (App Store) |
| dovi\_tool | MIT | Dolby Vision RPU manipulation |
| DDVT | MIT | HDR10+ to Dolby Vision conversion |
| MP4Box (GPAC) | LGPL 2.1 | MP4/DASH tooling |
| Tesseract OCR | Apache 2.0 | Bitmap subtitle OCR |
| libcdio / cdparanoia | GPL | Optical disc reading |
| libdvdread / libdvdnav | GPL 2 | DVD reading |
| libbluray | LGPL 2.1 | Blu-ray reading |
| libmediainfo | BSD-2-Clause | Detailed media file analysis |

> GPL tools are invoked as subprocesses (not linked), maintaining license compatibility with the proprietary application code.

---

## 🤝 Contributing

MeedyaConverter is currently a private project by MWBM Partners Ltd. Contribution guidelines will be published if/when the project opens to external contributors.

---

## 📧 Contact

MWBM Partners Ltd — GitHub: [@MWBMPartners](https://github.com/MWBMPartners)

---

Built with ❤️ by MWBM Partners Ltd
