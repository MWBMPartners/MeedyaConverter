# 💻 CLI Reference

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overview

MeedyaConverter includes a full-featured command-line interface (CLI) for automation, scripting, and headless operation. The CLI provides access to all core encoding features.

> The CLI tool will be implemented in Phase 6. This document serves as a preview of the planned command structure.

---

## Usage

```bash
meedya-cli <command> [options]
```

## Commands

### `encode` — Encode Media Files

```bash
meedya-cli encode <input> [options]

# Examples:
meedya-cli encode input.mkv --output output.mp4 --profile "Web Standard"
meedya-cli encode input.mkv --video-codec h265 --audio-codec aac --crf 22
meedya-cli encode input.wav --audio-codec flac --output output.flac
```

### `probe` — Inspect Media Files

```bash
meedya-cli probe <input> [--json]

# Examples:
meedya-cli probe input.mkv
meedya-cli probe input.mkv --json
```

### `profile` — Manage Encoding Profiles

```bash
meedya-cli profile list
meedya-cli profile show <name>
meedya-cli profile export <name> --output profile.json
meedya-cli profile import profile.json
```

### `manifest` — Generate Streaming Manifests

```bash
meedya-cli manifest <input-dir> [options]

# Examples:
meedya-cli manifest ./encoded/ --format hls --output ./streaming/
meedya-cli manifest ./encoded/ --format dash --output ./streaming/
meedya-cli manifest ./encoded/ --format both --encrypt --key-url https://keys.example.com/
```

### `validate` — Validate Manifest Files

```bash
meedya-cli validate <manifest-file>

# Examples:
meedya-cli validate master.m3u8
meedya-cli validate stream.mpd
```

---

## Global Options

| Option | Description |
| ------ | ----------- |
| `--help`, `-h` | Show help information |
| `--version`, `-v` | Show version |
| `--verbose` | Verbose output |
| `--quiet` | Suppress non-error output |
| `--json` | Output in JSON format (for scripting) |
| `--config <file>` | Use configuration file |
| `--log-file <path>` | Write logs to file |

---

## JSON Job Files

For complex encoding workflows, pass a JSON job definition:

```bash
meedya-cli encode --job job.json
```

```json
{
  "input": "source.mkv",
  "output": "output/",
  "profile": "Apple HLS",
  "streams": [
    { "type": "video", "index": 0, "codec": "h265", "crf": 22 },
    { "type": "audio", "index": 0, "codec": "aac", "bitrate": "128k" },
    { "type": "audio", "index": 1, "codec": "aac", "bitrate": "128k" },
    { "type": "subtitle", "index": 0, "mode": "passthrough" }
  ]
}
```

---

## Exit Codes

| Code | Meaning |
| ---- | ------- |
| `0` | Success |
| `1` | General error |
| `2` | Invalid arguments |
| `3` | Input file not found |
| `4` | Output write error |
| `5` | Encoding failed |
| `6` | FFmpeg not found |

---

*Full CLI documentation will be generated as commands are implemented in Phase 6.*
