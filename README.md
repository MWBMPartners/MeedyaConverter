# 🎬 MeedyaConverter

> **A modern, cross-platform media conversion toolkit with adaptive streaming support**
>
> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-blue)
![Swift](https://img.shields.io/badge/Swift-6.3-orange)
![Release](https://img.shields.io/badge/Release-v0.1.0--rc.3-brightgreen)
![License](https://img.shields.io/badge/License-Proprietary-red)

> 📦 **Current release:** `v0.1.0-rc.3` — signed (Developer ID) and notarised
> DMG + CLI tarball available on the
> [GitHub Releases page](https://github.com/MWBMPartners/MeedyaConverter/releases).
> The `v0.1.0` GA tag will follow once the rc smoke-test is signed off.

---

## 🚀 What is MeedyaConverter?

MeedyaConverter is a professional-grade media conversion application for
website owners, podcasters, archivists, and video professionals who need to
prepare audio and video content for on-demand streaming and long-term
storage. Think of it as a **modern alternative to HandBrake** — with
significantly expanded capabilities.

The macOS Direct-distribution build is **feature-complete** for the v0.1.0
release: full SwiftUI app with 35+ views, a complete `meedya-convert` CLI,
HDR pipelines (HDR10 / HDR10+ / HLG / Dolby Vision), HLS and MPEG-DASH
packaging, audio normalisation, subtitle conversion, watch folders, scene
detection, quality metrics, cloud upload to 12+ providers, and forensic
watermarking — all driven by the cross-platform `ConverterEngine` core.

See [PROJECT_STATUS.md](PROJECT_STATUS.md) for the comprehensive,
phase-by-phase feature inventory; the table below is the headline list.

### ✨ Key Features

| Feature | Description |
| ------- | ----------- |
| 🎞️ **Video/Audio/Subtitle Passthrough** | Copy streams without re-encoding — HandBrake forces re-encoding |
| 📡 **HLS & MPEG-DASH Preparation** | Multi-bitrate adaptive streaming from a single source file |
| 🎨 **HDR Preservation** | HDR10, HDR10+, HLG, and Dolby Vision support |
| 🔄 **HDR10+ → Dolby Vision** | Automatic Dolby Vision creation from HDR10+ content |
| 🎵 **Audio Normalisation** | EBU R128, ReplayGain, and peak limiting |
| 📝 **Full Subtitle Support** | SRT, TTML, WebVTT, SSA/ASS, CC608/CC708, DVB-SUB, SAMI, LRC |
| 🔐 **DRM & Encryption** | AES-128 encryption for HLS with key management |
| ☁️ **Cloud Upload** | Direct upload to S3, Azure, Cloudflare Stream, and 10+ providers |
| 🖼️ **Thumbnail Sprites** | Auto-generate preview scrubbing sprites for video players |
| 🔏 **Forensic Watermarking** | Invisible watermark embedding for content protection |
| 🎥 **3D / Stereoscopic** | MV-HEVC (Apple Vision Pro spatial) and MV-H264 multiview encoding |
| 🏷️ **Media Metadata Lookup** | Auto-tag via MusicBrainz, TMDB, TVDB, IMDB, MeedyaDB, Discogs |
| 📊 **Quality Metrics** | VMAF, SSIM, PSNR objective quality scoring |
| 👁️ **A/B Comparison** | Side-by-side source vs encoded viewer |
| 📂 **Watch Folders** | Monitor folders for new files, auto-encode |
| 🔍 **Scene Detection** | Auto-chaptering from scene boundaries |
| 🔎 **AI Upscaling** | Resolution enhancement via Real-ESRGAN |
| 💻 **CLI Mode** | Full command-line interface for automation and scripting |
| 💿 **Optical Disc Ripping** *(v1.1+)* | 22 disc types: Audio CD, SACD, DVD, DVD Audio, Blu-ray, UHD BD, and more |
| 💽 **Disc Authoring & Burning** *(v1.2+)* | Create disc images and burn to physical media for all supported disc types |
| 🖼️ **Image Conversion** *(v3.0+)* | Bulk image format conversion |

> Items tagged with a release marker (e.g. *(v1.1+)*) have scaffolding
> shipped in v0.1.0 but are not yet wired through the UI. The full release
> breakdown lives in [PROJECT_STATUS.md](PROJECT_STATUS.md).

---

## 📥 Install — Direct download

The recommended way to install MeedyaConverter on macOS is the signed and
notarised DMG from the GitHub Releases page. The DMG is signed with
MWBM Partners Ltd's Developer ID certificate and stapled with an Apple
notarisation ticket, so Gatekeeper will accept it without a network call.

### 1. Download

1. Open the
   [Releases page](https://github.com/MWBMPartners/MeedyaConverter/releases/latest).
2. Under **Assets**, download the asset named
   `MeedyaConverter-<version>.dmg` (e.g. `MeedyaConverter-0.1.0-rc.3.dmg`).
3. *Optional but recommended:* also download the matching
   `.dmg.sha256` checksum file alongside it.

### 2. Verify the download *(optional)*

```bash
# From your Downloads folder
cd ~/Downloads
shasum -a 256 -c MeedyaConverter-0.1.0-rc.3.dmg.sha256
```

You should see `MeedyaConverter-0.1.0-rc.3.dmg: OK`.

### 3. Mount and install

1. Double-click the `.dmg` to mount it. A Finder window will open
   showing the **MeedyaConverter** app icon and a shortcut to
   **/Applications**.
2. **Drag** `MeedyaConverter.app` onto the Applications shortcut.
3. **Eject** the mounted disk image (right-click in the sidebar → Eject)
   and move the `.dmg` file to the Trash — you don't need it any more.

### 4. First launch (Gatekeeper)

The app is signed and notarised, so on most systems a plain double-click
will work. If macOS shows a warning (e.g. on older systems, or if the app
was downloaded with a browser that didn't preserve the quarantine
attribute correctly):

1. Open Finder → **Applications**.
2. **Right-click** (or Control-click) `MeedyaConverter.app` and choose
   **Open**.
3. In the dialog that appears, click **Open** again.

You only need to do this once. Subsequent launches behave like any other
app.

### 5. Verify the signature *(optional)*

If you want to confirm that the installed app is genuine and unmodified,
run these two commands in Terminal:

```bash
# Verifies the embedded code signature and the full bundle hash chain
codesign --verify --deep --strict /Applications/MeedyaConverter.app

# Asks Gatekeeper to evaluate the app as if it had just been downloaded
spctl --assess --type execute --verbose /Applications/MeedyaConverter.app
```

A healthy install produces:

```text
# codesign exits silently with status 0 on success.

/Applications/MeedyaConverter.app: accepted
source=Notarized Developer ID
```

If either command reports anything other than the above, **do not run the
app** — re-download the DMG from the official Releases page and verify the
SHA-256 checksum before trying again.

### 6. Updates

- **v0.1.0:** updates are **manual** — keep an eye on the
  [Releases page](https://github.com/MWBMPartners/MeedyaConverter/releases)
  or **Watch** the repo to be notified. Download the new DMG and drag it
  into Applications, replacing the existing copy.
- **v0.2.0 and later:** in-app updates via Sparkle 2 are planned. The app
  will check on launch, prompt you when a new version is available, and
  apply the update with signature and notarisation verification before
  installing.

---

## 🖥️ System requirements

| Requirement | Minimum | Recommended |
| ----------- | ------- | ----------- |
| **macOS** | 15.0 Sequoia | 15.4 or later |
| **Architecture** | Apple Silicon (M1 / M2 / M3 / M4) | Apple Silicon |
| **Universal binary** | Yes — `arm64` + `x86_64` ship in the same DMG | — |
| **RAM** | 8 GB | 16 GB for 4K SDR, **32 GB** for 4K HDR / Dolby Vision work |
| **Free disk space** | 2 GB for the app + bundled tools | 50 GB+ scratch for 4K HDR encodes |
| **Network** | Required only for cloud upload, metadata lookup, AI upscaling | — |

> Intel Macs are supported by the Universal binary, but Apple Silicon is
> significantly faster for HEVC / AV1 / VideoToolbox encodes and is the
> primary test target. Older macOS releases (Sonoma 14 and earlier) are
> not supported because of SwiftUI features the app relies on.

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

> Supports physical discs, disc images (ISO, BIN/CUE, MDF/MDS, NRG, IMG), extracted disc structures (VIDEO\_TS, BDMV), and bit-for-bit disc cloning. Optical disc ripping ships in v1.1+; authoring and burning in v1.2+.

---

## 🖥️ Platform Support

| Platform | Architecture | UI Framework | v0.1.0 Status |
| -------- | ----------- | ----------- | ------------- |
| **macOS** | Apple Silicon (M1+) and Intel (Universal) | Swift 6.3 / SwiftUI | 🔴 Primary — ships |
| **CLI** | macOS | Swift ArgumentParser | 🔴 Primary — ships |
| **Windows** | x86, x64, ARM | WinUI 3 | 🟡 Planned (v2.0) |
| **Linux** | x86, x64, ARM, ARMv7, ARM64 | GTK4 | 🟢 Planned (v2.0) |

---

## 🛠️ Tech Stack

| Component | Technology |
| --------- | --------- |
| Language | Swift 6.3 |
| macOS UI | SwiftUI |
| Media Engine | Hybrid — FFmpeg subprocess (Direct distribution) + AVFoundation/FFmpegKit (App Store) |
| HDR Tools | dovi_tool, DDVT (bundled) |
| Package Manager | Swift Package Manager |
| CI/CD | GitHub Actions |
| Auto-Update | Sparkle 2 (Direct distribution, v0.2.0+); Apple-managed (App Store) |

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
| **Phase 0** | Project Setup & Architecture | ✅ Complete | — |
| **Phase 1** | Core Engine Foundation | ✅ Complete | Alpha 0.1 |
| **Phase 2** | macOS SwiftUI Application (MVP) | ✅ Complete | Alpha 0.1 |
| **Phase 3** | Essential Encoding & Passthrough | ✅ Complete | Alpha 0.2 |
| **Phase 4** | CLI Tool | ✅ Complete | Alpha 0.2 |
| **Phase 5** | Subtitles & Core Audio Processing | ✅ Complete | Beta 0.5 |
| **Phase 6** | Adaptive Streaming (HLS/MPEG-DASH) | ✅ Complete | Beta 0.5 |
| **Phase 7** | Extended Formats & Spatial Audio | ✅ Complete | Beta 0.7 |
| **Phase 8** | Advanced Audio Processing | ✅ Complete | Beta 0.7 |
| **Phase 9** | Professional Features | ✅ Complete | RC 0.9 |
| **Phase 10** | Optical Disc Ripping (22 disc types) | ✅ Complete | v1.1+ |
| **Phase 11** | Disc Image Creation & Burning | ✅ Complete | v1.2+ |
| **Phase 12** | Cloud Integration & Uploads | ✅ Complete | v1.3+ |
| **Phase 13** | Platform Expansion — Windows | ⏳ Planned | v2.0 |
| **Phase 14** | Platform Expansion — Linux | ⏳ Planned | v2.0 |
| **Phase 15** | Media Metadata Lookup | ✅ Complete | v1.5+ |
| **Phase 16** | Polish & Distribution | 🚧 Ongoing (release execution pending, #428) | Ongoing |
| **Phase 17** | Image Conversion (future version) | ✅ Complete | v3.0+ |
| **Phase 18** | AI-Powered Features (wishlist) | 🔮 Wishlist | TBD |

> 📌 See [Project_Plan.md](Project_Plan.md) for the detailed milestone breakdown.
> 📊 See [PROJECT_STATUS.md](PROJECT_STATUS.md) for current progress and the per-phase task tables.

---

## 🛠️ Build from source

> 👋 **Most users should install the signed DMG instead** — see
> [Install — Direct download](#-install--direct-download) above. The
> instructions below are for developers who want to build, modify, or
> contribute to MeedyaConverter.

### Prerequisites

- **macOS 15+** (Sequoia or later)
- **Xcode 16.3+** (with Swift 6.3)
- **FFmpeg** for development — bundled at release time, but for a local
  source build you can install via Homebrew: `brew install ffmpeg`

### Building

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

# Build for App Store (FFmpegKit instead of subprocess FFmpeg)
APP_STORE=1 swift build -c release

# (advanced) Link the Sparkle framework for v0.2.0 auto-update work.
# NOTE: this is NOT how the shipped v0.1.0 Direct DMG is built — the
# release pipeline uses the plain `swift build -c release` above and
# ships the GitHub-Releases update poller (Option A). DIRECT=1 links
# Sparkle and selects the Sparkle update UI, which is non-functional
# until the appcast + EdDSA key land in v0.2.0 (see SECURITY.md F-003).
DIRECT=1 swift build -c release
```

More detail — including how to bundle FFmpeg, sign, notarise, and produce
a DMG — lives in [docs/Building-from-Source.md](docs/Building-from-Source.md)
and [docs/LOCAL_BUILD.md](docs/LOCAL_BUILD.md).

### Branch strategy

| Branch | Purpose | Release Type |
| ------ | ------- | ------------ |
| `main` | Stable releases (protected) | Production (tagged `vX.Y.Z`) |
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

If you discover a security vulnerability, **please do not open a public
GitHub issue**. See [.github/SECURITY.md](.github/SECURITY.md) for the
responsible-disclosure process and the contact email. We acknowledge
reports within 48 hours and aim to ship fixes within 30 days.

---

## 🤝 Contributing

MeedyaConverter is a proprietary project maintained by MWBM Partners Ltd, but
external contributions are welcomed under the terms documented in
[`CONTRIBUTING.md`](CONTRIBUTING.md) — covering licensing posture (you retain
copyright; MWBM gets a perpetual sublicensable licence), code style, branch
strategy, PR process, and the dev environment. Please also read
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) (Contributor Covenant v2.1, applied
across the MeedyaSuite family).

For bug reports, feature requests, and reproducible test cases:
[GitHub Issues](https://github.com/MWBMPartners/MeedyaConverter/issues).

For security issues, please don't open a public issue — follow the disclosure
process in [`.github/SECURITY.md`](.github/SECURITY.md).

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

See [LICENSE](LICENSE) for the full text. This software is the proprietary
product of MWBM Partners Ltd. Unauthorized copying, distribution,
modification, or use of this software is strictly prohibited without prior
written permission.

### Third-Party Licenses

MeedyaConverter bundles or uses the following open-source components, each under their own respective licenses:

| Component | License | Usage |
| --------- | ------- | ----- |
| FFmpeg | LGPL 2.1 / GPL 2+ | Subprocess (Direct distribution) or FFmpegKit LGPL (App Store) |
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

## 📧 Contact

MWBM Partners Ltd — GitHub: [@MWBMPartners](https://github.com/MWBMPartners)

---

Built with ❤️ by MWBM Partners Ltd
