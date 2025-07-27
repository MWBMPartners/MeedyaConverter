<!--
  File: PROJECT_PROGRESS.md
  Purpose: Tracks milestone-based progress of the Adaptix project
  Role: Central taskboard and tracker used to monitor implementation across modules and platforms

  (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
  Version: 1.0.0
-->


✅ Adaptix Project Milestones & Progress Tracker

This file outlines and tracks all development milestones for the Adaptix media encoding toolkit.
It follows a modular roadmap approach with inline ✅ / 🚧 / ⏳ indicators.

⸻

🧱 MILESTONE 0: Planning & Infrastructure ✅
	•	Name selected: Adaptix
	•	Branding + logo (PNG + SVG)
	•	Project monorepo structure established
	•	Commenting and file header standards defined
	•	Swift + SwiftUI (6.2+) with MVVM architecture
	•	Liquid Glass UI design adoption for macOS
	•	Markdown header syntax and emoji guidelines

📘 MILESTONE 1: Documentation Core ✅
	•	/README.md (root) written
	•	/core/README.md created
	•	/PROJECT_PROGRESS.md live tracking

🧠 MILESTONE 2: Core Logic Foundation 🚧
	•	FFmpegController.swift: Shared FFmpeg-based job runner
	•	EncodingProfile.swift: Presets (video/audio/subtitles/bitrates)
	•	ManifestGenerator.swift: HLS + MPEG-DASH generation
	•	AudioProcessor.swift: Normalization (ReplayGain/R128), downmixing, passthrough, watermarking
	•	SubtitleManager.swift: SSA/ASS, CC608/708/709, TTML, WebVTT
	•	EncryptionHandler.swift: AES-128 support, future DRM hooks
	•	TestMediaUtils.swift: Input probing, auto ladder suggest

🖥️ MILESTONE 3: macOS SwiftUI GUI 🚧
	•	Project Xcode scaffold w/ Liquid Glass UI starter
	•	UI for batch import & preview
	•	Profile selection or creation wizard
	•	Batch encoding progress view w/ pause/resume
	•	Watermark configuration UI
	•	Output manager w/ VideoJS embed generator

🧪 MILESTONE 4: CLI Tooling (Swift) ⏳
	•	Command-line wrapper using same core logic
	•	JSON config loader + batch launcher
	•	Test output validator

🪟 MILESTONE 5: Windows GUI Scaffold ⏳
	•	File structure placeholder
	•	Shared Swift logic integration via CLI or bridge layer
	•	(Planned) C#/WPF or Avalonia-based UI later

🌍 MILESTONE 6: Advanced Feature Integrations ⏳
	•	Dolby Vision/HDR10+/HLG parsing and retention
	•	3D/Spatial video & audio support (Dolby Atmos, DTS:X, MPEG-H, Ambisonics, etc)
	•	ReplayGain + EBU R128 audio normalization
	•	FFmpeg AES-128 encryption key manager
	•	CEA-608/708/709 + TTML full subtitle mux/demux

📦 MILESTONE 7: Shipping Profiles + Export Handling ⏳
	•	Default encoding profiles (streaming tiers)
	•	Optional bundled presets for archival, mezzanine, etc.
	•	Support for passthrough video/audio modes

⸻

Last updated: 2025-07-27

Feel free to mark any component or file complete with a ✅ or open a new sub-milestone below each section.