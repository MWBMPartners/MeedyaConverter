#
# File: adaptix/README.md
# Purpose: Root-level README describing the Adaptix project as a whole
# Role: Introduces the full-featured, cross-platform modular adaptive streaming toolkit.
#
# (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
# Version: 1.0.0

🎥 Adaptix

Adaptix is a modular, open-source, cross-platform media encoding and adaptive streaming toolkit focused on high-quality HLS and MPEG-DASH output. It prioritizes precision, flexibility, and support for next-generation media formats including:
	•	🎬 H.264, H.265/HEVC, AV1, VP9
	•	🎧 Dolby Atmos, DTS:X, MPEG-H 3D, FLAC, ALAC, OPUS
	•	📝 Advanced captioning (SSA/ASS, CEA-608, 708, WebVTT, TTML, and more)

⸻

🚀 Key Features
	•	📦 Modular architecture with shared Swift-based core
	•	🧠 Reusable encoding profile definitions
	•	🎛️ Multi-pass CRF/CQ encoding with max bitrate & HDR retention
	•	🔊 Audio normalization (ReplayGain / EBU R128) & watermarking
	•	🖼️ Subtitle parsing with formatting, fallback, and embedded muxing
	•	🔐 AES-128 encryption & DRM-ready architecture
	•	💡 VideoJS embed generator for all HLS/MPEG-DASH outputs
	•	⚙️ FFmpeg-based processing, with optional VideoToolbox/CoreAudio
	•	🧪 Native support for 3D/Spatial Audio & Video on supported platforms
	•	📤 Batch export, pause/resume encoding support

📁 Repository Structure

adaptix/
├── core/                  # Shared encoding logic, manifest builders, format handlers
├── macos/                 # SwiftUI Liquid Glass macOS frontend (Apple Silicon preferred)
├── windows/               # (Placeholder) for future Windows GUI version
├── cli/                   # Command-line encoder tool (cross-platform)
├── assets/                # Logos, UI icons, SVGs, watermarks
├── docs/                  # Project documentation
├── presets/               # Default shipping encoding profiles
├── tests/                 # Test media and encoding presets
├── README.md              # Project introduction (this file)
└── PROJECT_PROGRESS.md   # Milestone-based task tracker

📦 Packaging and Distribution

Adaptix will support GitHub-based releases for:
	•	✅ macOS Universal App (.dmg)
	•	✅ CLI build for macOS/Linux/Windows
	•	🧪 GitHub Actions-based test encodes and output comparisons

📖 Documentation

See docs/ for usage instructions, profile definitions, CLI syntax, and advanced options.

🛡️ Licensing

(C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.

Adaptix is licensed for internal and commercial encoding purposes under a permissive license to be determined (e.g., MIT or BSD-3-Clause).