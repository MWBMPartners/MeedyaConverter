<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Troubleshooting

Solutions for common issues encountered when using MeedyaConverter.

---

## FFmpeg Not Found

**Symptom:** The app displays "FFmpeg not found" or encoding fails immediately.

**Solutions:**

1. **Install FFmpeg via Homebrew:**
   ```bash
   brew install ffmpeg
   ```

2. **Verify FFmpeg is accessible:**
   ```bash
   which ffmpeg
   ffmpeg -version
   ```

3. **Check expected paths.** MeedyaConverter searches in this order:
   - App bundle (direct distribution builds).
   - `/opt/homebrew/bin/ffmpeg` (Apple Silicon Homebrew).
   - `/usr/local/bin/ffmpeg` (Intel Homebrew).
   - System PATH.

4. **Set a custom path** using the `FFMPEG_PATH` environment variable:
   ```bash
   export FFMPEG_PATH=/path/to/ffmpeg
   ```

5. **App Store version:** Does not require external FFmpeg (uses embedded FFmpegKit).

---

## Hardware Encoder Not Detected

**Symptom:** VideoToolbox, NVENC, or other hardware encoders are not available in the encoder list.

**Solutions:**

1. **VideoToolbox (macOS):**
   - Requires macOS 15+ and a supported GPU.
   - Apple Silicon supports H.264, H.265, and ProRes hardware encoding.
   - AV1 hardware encoding requires M3 or later.
   - Verify: `ffmpeg -encoders | grep videotoolbox`.

2. **NVENC (NVIDIA):**
   - Requires an NVIDIA GPU with NVENC support and appropriate drivers.
   - Not available on macOS (NVIDIA drivers discontinued on macOS).

3. **General:**
   - Ensure FFmpeg was compiled with the relevant hardware encoding libraries.
   - Run `ffmpeg -encoders` to see all available encoders.
   - MeedyaConverter's hardware encoder detector probes for supported encoders at startup.

---

## HDR Metadata Lost

**Symptom:** Output file is missing HDR10 metadata (MaxCLL, MaxFALL, mastering display) or plays back as SDR.

**Solutions:**

1. **Verify source has HDR metadata:**
   ```bash
   meedya-convert probe -i source.mkv -f json | grep -A5 "color"
   ```

2. **Use an HDR-capable output codec.** HDR metadata can only be preserved with:
   - H.265 (HEVC)
   - AV1
   - VP9

   If you encode to H.264, HDR is lost (tone mapping is applied automatically).

3. **Check container support.** MKV and MP4 both support HDR metadata. MOV has limited HDR metadata support.

4. **Dolby Vision metadata** requires `dovi_tool` to be installed for RPU extraction and injection.

5. **HDR10+ metadata** is preserved via JSON sidecar files. Ensure the output workflow includes the sidecar.

---

## Container Compatibility Warnings

**Symptom:** MeedyaConverter warns that a codec/container combination is unsupported.

**Common incompatible pairings:**

| Combination | Issue |
|-------------|-------|
| VP9 in MP4 | VP9 is not supported in MP4. Use WebM or MKV. |
| FLAC in MP4 | FLAC is not natively supported in MP4. Use MKV or FLAC container. |
| DTS in MP4 | DTS is not supported in MP4. Use MKV. |
| TrueHD in MP4 | TrueHD is not supported in MP4. Use MKV. |
| ProRes in MKV | Works but uncommon. MOV is the standard container for ProRes. |
| Opus in MP4 | Technically valid but many players cannot decode it. |

**Solution:** Change the output container to one that supports your chosen codec, or change the codec. The [Codec Reference](Codec-Reference) has a full compatibility matrix.

---

## Encoding Fails with FFmpeg Error

**Symptom:** Encoding starts but FFmpeg exits with an error.

**Diagnostic steps:**

1. **Check the log.** MeedyaConverter captures FFmpeg's stderr output. In the GUI, check the Log panel. For the CLI, run without `--quiet`.

2. **Common FFmpeg errors:**

   | Error | Cause | Fix |
   |-------|-------|-----|
   | `Encoder not found` | FFmpeg lacks the requested encoder | Install FFmpeg with full codec support |
   | `Invalid option` | Unsupported encoder option for this codec | Check codec-specific settings |
   | `Could not write header` | Codec/container incompatibility | Change container or codec |
   | `Bitrate too low/high` | Bitrate outside encoder limits | Adjust bitrate |
   | `No space left on device` | Disk full | Free disk space or change output path |

3. **Try a simpler encode** to isolate the issue:
   ```bash
   meedya-convert encode -i input.mkv -o test.mp4 --video-codec h264 --crf 23 --audio-codec aac
   ```

---

## Notarisation Failures (Direct Distribution)

**Symptom:** The app is blocked by macOS Gatekeeper ("Apple cannot check it for malicious software").

**For users:**

1. Right-click the app and select "Open" (bypasses Gatekeeper for the first launch).
2. Go to System Settings > Privacy & Security and click "Open Anyway".

**For developers building from source:**

1. Sign with a valid Developer ID certificate.
2. Submit the app for notarisation:
   ```bash
   xcrun notarytool submit MeedyaConverter.dmg --apple-id <email> --team-id <team> --password <app-specific-password>
   ```
3. Staple the notarisation ticket:
   ```bash
   xcrun stapler staple MeedyaConverter.dmg
   ```

---

## Slow Encoding Speed

**Symptom:** Encoding is much slower than expected.

**Solutions:**

1. **Use a faster preset.** Change from `slow`/`veryslow` to `medium` or `fast`. The quality difference is often negligible.

2. **Enable hardware encoding.** Use VideoToolbox (macOS) or NVENC (NVIDIA) for significantly faster encodes:
   - The speed improvement is typically 3-10x.
   - Quality may be slightly lower than software encoding at the same settings.

3. **Use AV1 only when needed.** AV1 software encoding (libaom, libsvtav1) is substantially slower than H.265. Use SVT-AV1 (`libsvtav1`) for better speed.

4. **Reduce resolution.** Encoding 4K is roughly 4x slower than 1080p.

5. **Check system load.** Other running processes can compete for CPU/GPU resources.

---

## App Sandbox File Access Issues (App Store)

**Symptom:** The app cannot read input files or write to the output location.

**Solutions:**

1. **Use the file picker.** The App Store version requires user-selected file access. Drag-and-drop and the Open dialog both grant access.

2. **Grant Full Disk Access** (if needed): System Settings > Privacy & Security > Full Disk Access > enable MeedyaConverter.

3. **Check output location.** The app may not have write access to all directories. Use a location within your home directory or a user-selected folder.

---

## Subtitle Rendering Issues

**Symptom:** Subtitles are missing, garbled, or incorrectly positioned in the output.

**Solutions:**

1. **Check subtitle format compatibility** with the output container:
   - MP4: limited subtitle support (MOV text only).
   - MKV: supports all subtitle formats (SRT, ASS, PGS, VobSub, etc.).
   - WebM: WebVTT only.

2. **Bitmap subtitles (PGS, VobSub) cannot be converted to text** without OCR. They can be:
   - Passed through to a compatible container (MKV).
   - Burned into the video (permanent, increases encode time).

3. **ASS/SSA styling** is preserved in MKV. When converting to SRT, styling is stripped.

---

## Getting Help

If your issue is not covered here:

1. Check the [FAQ](FAQ) for additional answers.
2. Search existing [GitHub Issues](https://github.com/MWBMPartners/MeedyaConverter/issues).
3. Open a new issue with:
   - MeedyaConverter version.
   - macOS version.
   - FFmpeg version (`ffmpeg -version`).
   - Steps to reproduce.
   - Relevant log output.
