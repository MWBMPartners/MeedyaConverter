# 🔧 Troubleshooting

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Common Issues

### MeedyaConverter won't open on macOS

**Symptom:** "MeedyaConverter is damaged and can't be opened" or similar Gatekeeper message.

**Solution:**

1. Ensure you downloaded MeedyaConverter from an official source
2. Right-click the app and select "Open" (bypasses first-launch warning)
3. If the issue persists, check System Settings → Privacy & Security for an "Allow" button

### FFmpeg not found

**Symptom:** Error message "FFmpeg binary not found" when starting an encode.

**Solution:**
FFmpeg should be bundled with the application. If this error appears:

1. Try reinstalling MeedyaConverter
2. For development builds, install FFmpeg via Homebrew: `brew install ffmpeg`
3. Check Settings → Tools to verify the FFmpeg path

### Encoding fails immediately

**Symptom:** Encoding starts but fails within seconds.

**Possible causes:**

- **Unsupported codec combination** — not all codecs work with all containers. Check the log for details
- **Corrupted source file** — try probing the file first to check for errors
- **Insufficient disk space** — ensure enough space for the output file
- **Permission denied** — check that MeedyaConverter has write access to the output directory

### Output file has no audio/video

**Symptom:** The output file is created but is missing streams.

**Solution:**

- Check that the desired streams are selected in the stream list
- Verify the output container supports the selected codecs
- Review the encoding log for warnings about skipped streams

### HDR metadata is lost

**Symptom:** Output file plays in SDR despite source being HDR.

**Solution:**

- Ensure "Preserve HDR" is enabled in the encoding profile
- Use H.265/HEVC or AV1 codec (H.264 does not support HDR metadata)
- Use MP4 or MKV container (WebM has limited HDR support)
- Check that the source file actually contains HDR metadata (use the probe feature)

### HLS/DASH manifest errors

**Symptom:** Generated manifest files fail validation or don't play in a player.

**Solution:**

- Use the built-in manifest validator to check for issues
- Ensure all segment files are in the correct output directory
- Verify the base URL/path configuration in your streaming setup
- Check that keyframe intervals are consistent across all variants

---

## Getting Help

If your issue isn't listed here:

1. Check the [FAQ](faq.md) for common questions
2. Review the encoding log (View → Show Log) for detailed error information
3. Report issues at the project's GitHub repository

---

## Diagnostic Information

When reporting issues, please include:

- MeedyaConverter version (Help → About)
- Operating system and version
- FFmpeg version (shown in Settings → Tools)
- The encoding log (View → Show Log → Export)
- Source file format details (use the Probe feature)
