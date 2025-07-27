<!--
  File: adaptix/core/README.md
  Purpose: Describes the core engine of Adaptix, including encoding logic and reusable platform-independent components.
  Role: Forms the foundation of all encoding, normalization, subtitle, manifest, and encryption logic shared across all interfaces (macOS app, CLI, and future Windows GUI).
  (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
  Version: 1.0.0
-->

# 📁 adaptix/core/

This folder contains the **core logic** and **encoding engine** for Adaptix.
It is platform-independent and shared between the SwiftUI macOS app, CLI tool, and (eventually) the Windows app frontend.

## 📦 Responsibilities

- 🎬 **FFmpegController.swift** – Responsible for orchestrating FFmpeg jobs, options parsing, and progress monitoring  
- 🧠 **EncodingProfile.swift** – Defines reusable encoding presets and user-defined ladders  
- 📄 **ManifestGenerator.swift** – Builds adaptive HLS `.m3u8` and MPEG-DASH `.mpd` manifests  
- 🎧 **AudioProcessor.swift** – Handles normalization, downmixing, watermarking, and pass-through logic  
- 🖼️ **SubtitleManager.swift** – Subtitle format detection, parsing, external/embedded muxing  
- 🔐 **EncryptionHandler.swift** – AES-128 and optional DRM stub integration  
- 🧪 **TestMediaUtils.swift** – Tools for analyzing input media and preparing encoding suggestions  

## 🔄 Shared Across

- ✅ macOS SwiftUI frontend (Xcode)  
- ✅ CLI Swift tool (cross-platform)  
- 🧪 Future Windows GUI (Visual Studio, planned)  

## 🧱 Architecture

All core modules are Swift-based and adhere to MVVM where applicable.  
Shared classes will be exposed via Swift packages for easy reuse across platforms.

## 🔐 Licensing

(C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.

---

_This module is essential to all Adaptix features. Please document new additions thoroughly and ensure reusability._