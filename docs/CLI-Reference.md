<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# CLI Reference

`meedya-convert` is the headless command-line interface for MeedyaConverter. It is designed for CI/CD pipelines, batch processing, shell scripting, and remote encoding over SSH.

---

## Synopsis

```
meedya-convert <subcommand> [options]
```

## Subcommands

| Command | Description |
|---------|-------------|
| `encode` | Transcode media files |
| `probe` | Inspect media file properties |
| `batch` | Process multiple files from a job file |
| `profiles` | List, show, or manage encoding profiles |
| `manifest` | Generate HLS/DASH streaming manifests |
| `validate` | Validate encoding settings without running |

---

## `encode`

Transcode a media file using specified settings or a named profile.

### Usage

```
meedya-convert encode --input <path> --output <path> [options]
```

### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--input <path>` | `-i` | Input file path (required) | — |
| `--output <path>` | `-o` | Output file path (required) | — |
| `--profile <name>` | `-p` | Encoding profile name | — |
| `--video-codec <codec>` | `-v` | Video codec (h264, h265, av1, prores, etc.) | h265 |
| `--audio-codec <codec>` | `-a` | Audio codec (aac, ac3, flac, opus, etc.) | aac |
| `--crf <value>` | | Constant Rate Factor (quality) | 22 |
| `--video-bitrate <rate>` | | Target video bitrate (e.g., 5M, 8000k) | — |
| `--audio-bitrate <rate>` | | Target audio bitrate (e.g., 128k, 256k) | 192k |
| `--preset <name>` | | Encoder preset (ultrafast..veryslow) | medium |
| `--resolution <WxH>` | | Output resolution (e.g., 1920x1080) | source |
| `--container <format>` | | Output container (mp4, mkv, mov, webm) | auto |
| `--passthrough-video` | | Copy video without re-encoding | false |
| `--passthrough-audio` | | Copy audio without re-encoding | false |
| `--two-pass` | | Enable two-pass encoding | false |
| `--hdr-mode <mode>` | | HDR handling: preserve, tonemap, convert | preserve |
| `--tonemap <algorithm>` | | Tone-map algorithm (hable, reinhard, mobius, bt2390) | hable |
| `--crop <W:H:X:Y>` | | Crop rectangle | — |
| `--crop-detect` | | Auto-detect and crop black bars | false |
| `--overwrite` | `-y` | Overwrite output without prompting | false |
| `--quiet` | `-q` | Suppress progress output | false |
| `--json-progress` | | Emit progress as JSON lines (for scripts) | false |

### Examples

```bash
# Basic H.265 encode
meedya-convert encode -i input.mkv -o output.mp4 --video-codec h265 --crf 20

# Use a built-in profile
meedya-convert encode -i input.mkv -o output.mp4 --profile "H.265 High Quality"

# Passthrough video, re-encode audio to AAC
meedya-convert encode -i input.mkv -o output.mp4 --passthrough-video --audio-codec aac --audio-bitrate 256k

# Two-pass AV1 with target bitrate
meedya-convert encode -i input.mkv -o output.webm --video-codec av1 --video-bitrate 4M --two-pass

# HDR to SDR tone mapping
meedya-convert encode -i hdr_input.mkv -o sdr_output.mp4 --video-codec h264 --hdr-mode tonemap --tonemap hable

# Remux MKV to MP4 (all streams passthrough)
meedya-convert encode -i input.mkv -o output.mp4 --passthrough-video --passthrough-audio
```

---

## `probe`

Inspect a media file and display stream information, metadata, and technical details.

### Usage

```
meedya-convert probe --input <path> [options]
```

### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--input <path>` | `-i` | Input file path (required) | — |
| `--format <type>` | `-f` | Output format: text, json, yaml | text |
| `--streams` | | Show stream details only | false |
| `--metadata` | | Show metadata only | false |
| `--chapters` | | Show chapter list only | false |

### Examples

```bash
# Human-readable probe
meedya-convert probe -i video.mkv

# JSON output for scripting
meedya-convert probe -i video.mkv --format json

# Pipe probe output to jq
meedya-convert probe -i video.mkv -f json | jq '.streams[] | select(.codec_type == "video")'
```

---

## `batch`

Process multiple files using a job definition file.

### Usage

```
meedya-convert batch --job-file <path> [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--job-file <path>` | Path to job definition file (JSON/YAML) | — |
| `--parallel <count>` | Number of concurrent encodes | 1 |
| `--continue-on-error` | Skip failed jobs instead of aborting | false |
| `--dry-run` | Validate jobs without encoding | false |

### Job File Format

Job files are JSON arrays of encode tasks:

```json
[
  {
    "input": "/path/to/video1.mkv",
    "output": "/path/to/video1.mp4",
    "profile": "H.265 High Quality"
  },
  {
    "input": "/path/to/video2.mkv",
    "output": "/path/to/video2.mp4",
    "video_codec": "h265",
    "crf": 20,
    "audio_codec": "aac",
    "audio_bitrate": "256k"
  }
]
```

### Examples

```bash
# Run a batch job file
meedya-convert batch --job-file jobs.json

# Parallel encoding with 4 concurrent jobs
meedya-convert batch --job-file jobs.json --parallel 4

# Dry run to validate settings
meedya-convert batch --job-file jobs.json --dry-run
```

---

## `profiles`

List, inspect, and manage encoding profiles.

### Usage

```
meedya-convert profiles <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `list` | List all available profiles |
| `show <name>` | Show details of a specific profile |
| `export <name> --output <path>` | Export a profile to JSON |
| `import --input <path>` | Import a profile from JSON |

### Examples

```bash
# List all profiles
meedya-convert profiles list

# Show profile details
meedya-convert profiles show "H.265 High Quality"

# Export a profile
meedya-convert profiles export "H.265 High Quality" --output my_profile.json
```

---

## `manifest`

Generate streaming manifests (HLS/DASH) from encoded variants.

### Usage

```
meedya-convert manifest --type <hls|dash> --input <directory> --output <path>
```

---

## `validate`

Check that encoding settings are valid without performing an encode. Useful for testing profiles and CI validation.

### Usage

```
meedya-convert validate --input <path> --profile <name>
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments or options |
| 3 | Input file not found or unreadable |
| 4 | Output path not writable |
| 5 | FFmpeg not found |
| 6 | Unsupported codec/container combination |
| 7 | Encoding failed (FFmpeg error) |
| 8 | Job file parse error |
| 9 | Partial batch failure (some jobs failed) |

---

## Batch Scripting

### Shell Loop

```bash
for f in /videos/*.mkv; do
  meedya-convert encode -i "$f" -o "${f%.mkv}.mp4" --profile "H.265 Balanced" -y
done
```

### JSON Progress for Automation

Use `--json-progress` to parse progress from another program:

```bash
meedya-convert encode -i input.mkv -o output.mp4 --json-progress 2>&1 | while read -r line; do
  echo "$line" | jq -r '.percent'
done
```

Each JSON progress line contains:

```json
{
  "percent": 45.2,
  "fps": 120.5,
  "speed": "2.4x",
  "bitrate": "5234k",
  "time": "00:12:34.56",
  "eta": "00:15:12",
  "size": "1.2G"
}
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `FFMPEG_PATH` | Override FFmpeg binary location |
| `FFPROBE_PATH` | Override FFprobe binary location |
| `MEEDYA_PROFILES_DIR` | Custom directory for encoding profiles |
| `MEEDYA_TEMP_DIR` | Custom temp directory for intermediate files |
| `NO_COLOR` | Disable coloured output (respects the NO_COLOR convention) |
