<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# CLI Reference

`meedya-convert` is the headless command-line interface for MeedyaConverter. It is designed for CI/CD pipelines, batch processing, shell scripting, and remote encoding over SSH.

---

## Synopsis

```text
meedya-convert <subcommand> [options]
```

## Subcommands

| Command | Description |
| ------- | ----------- |
| `encode` | Transcode a single media file |
| `probe` | Inspect media file properties |
| `profiles` | List, show, export, import, or validate encoding profiles |
| `batch` | Encode multiple files from a directory or JSON job file |
| `manifest` | Generate HLS/DASH/CMAF adaptive streaming manifests |
| `validate` | Validate encoding profiles, manifests, and platform compatibility |

---

## `encode`

Transcode a media file using a named profile or custom settings.

### encode Usage

```text
meedya-convert encode --input <path> [--output <path>] [options]
```

If `--output` is omitted, the output file is placed in the same directory as the input with a `_converted` suffix and an extension matching the selected profile or container.

### encode Options

| Option | Short | Type | Description | Default |
| ------ | ----- | ---- | ----------- | ------- |
| `--input <path>` | `-i` | String | Input file path (required) | -- |
| `--output <path>` | `-o` | String | Output file path | Auto-generated |
| `--profile <name>` | `-p` | String | Encoding profile name or ID | -- |
| `--video-codec <codec>` | | String | Video codec (h264, h265, av1, prores, vp9, copy) | -- |
| `--crf <value>` | | Integer | Constant Rate Factor (quality, 0-63) | -- |
| `--video-bitrate <rate>` | | String | Target video bitrate (e.g., 5000k, 10M) | -- |
| `--preset <name>` | | String | Encoder preset (ultrafast..veryslow) | -- |
| `--resolution <WxH>` | | String | Output resolution (e.g., 1920x1080) | Source |
| `--video-passthrough` | | Flag | Copy video without re-encoding | false |
| `--audio-codec <codec>` | | String | Audio codec (aac, ac3, eac3, flac, opus, copy) | -- |
| `--audio-bitrate <rate>` | | String | Target audio bitrate (e.g., 128k, 256k) | -- |
| `--audio-channels <n>` | | Integer | Audio channel count (1, 2, 6, 8) | -- |
| `--audio-passthrough` | | Flag | Copy audio without re-encoding | false |
| `--subtitle-passthrough` | | Flag | Copy subtitle streams | false |
| `--no-subtitles` | | Flag | Exclude all subtitle streams | false |
| `--container <format>` | | String | Output container (mkv, mp4, webm, mov, ts) | Auto |
| `--tonemap` | | Flag | Enable HDR-to-SDR tone mapping | false |
| `--tonemap-algorithm <alg>` | | String | Tone map algorithm (hable, reinhard, mobius, bt2390, linear) | hable |
| `--pq-to-hlg` | | Flag | Convert PQ (HDR10) to HLG | false |
| `--pq-to-dv-hlg` | | Flag | Convert PQ to Dolby Vision Profile 8.4 + HLG | false |
| `--no-copy-metadata` | | Flag | Do not copy source metadata | false |
| `--no-copy-chapters` | | Flag | Do not copy chapter markers | false |
| `--video-stream <index>` | | Integer | Video stream index to encode | First |
| `--audio-stream <index>` | | Integer | Audio stream index to encode | First |
| `--subtitle-stream <index>` | | Integer | Subtitle stream index to include | -- |
| `--map-all` | | Flag | Map all streams from source | false |
| `--hardware` | | Flag | Use hardware encoder if available | false |
| `--quiet` | | Flag | Suppress progress output | false |
| `--json` | | Flag | Output progress and result as JSON | false |
| `--yes` | `-y` | Flag | Overwrite output without prompting | false |

### encode Validation Rules

- `--video-codec` and `--video-passthrough` are mutually exclusive.
- `--audio-codec` and `--audio-passthrough` are mutually exclusive.
- `--tonemap` and `--pq-to-hlg` are mutually exclusive.

### encode Examples

```bash
# Basic H.265 encode
meedya-convert encode -i input.mkv -o output.mp4 --video-codec h265 --crf 20

# Use a built-in profile
meedya-convert encode -i input.mkv -o output.mp4 --profile "H.265 High Quality"

# Passthrough video, re-encode audio to AAC
meedya-convert encode -i input.mkv -o output.mp4 \
  --video-passthrough --audio-codec aac --audio-bitrate 256k

# HDR to SDR tone mapping
meedya-convert encode -i hdr_input.mkv -o sdr_output.mp4 \
  --video-codec h264 --tonemap --tonemap-algorithm hable

# Remux MKV to MP4 (all streams passthrough)
meedya-convert encode -i input.mkv -o output.mp4 \
  --video-passthrough --audio-passthrough

# Hardware-accelerated encode with overwrite
meedya-convert encode -i input.mkv -o output.mp4 \
  --video-codec h265 --crf 22 --hardware -y

# PQ to HLG conversion
meedya-convert encode -i hdr10_input.mkv -o hlg_output.mkv \
  --video-codec h265 --pq-to-hlg

# JSON progress output for scripting
meedya-convert encode -i input.mkv -o output.mp4 --profile "H.265 Balanced" --json
```

---

## `probe`

Inspect a media file and display stream information, metadata, and technical details.

### probe Usage

```text
meedya-convert probe --input <path> [options]
```

### probe Options

| Option | Short | Type | Description | Default |
| ------ | ----- | ---- | ----------- | ------- |
| `--input <path>` | `-i` | String | Input file path (required) | -- |
| `--format <type>` | `-f` | String | Output format: text, json | text |
| `--streams-only` | | Flag | Show only stream information | false |
| `--hdr` | | Flag | Show detailed HDR metadata | false |

### probe Output (Text Mode)

Text mode displays:

- File name, path, size, duration, overall bitrate, container format.
- HDR format detection (Dolby Vision, HDR10/PQ, HLG).
- Chapter count.
- Video streams with codec, resolution, frame rate, bitrate, HDR flags.
- Audio streams with codec, channel layout, sample rate, bitrate, language.
- Subtitle streams with format, language, forced/default flags.
- Metadata key-value pairs.

With `--hdr`, video streams additionally show colour primaries, transfer characteristics, matrix coefficients, MaxCLL, MaxFALL, and mastering display luminance.

### probe Examples

```bash
# Human-readable probe
meedya-convert probe -i video.mkv

# JSON output for scripting
meedya-convert probe -i video.mkv --format json

# Pipe probe output to jq
meedya-convert probe -i video.mkv -f json | jq '.streams'

# Streams only with HDR details
meedya-convert probe -i hdr_video.mkv --streams-only --hdr
```

---

## `profiles`

List, inspect, export, import, and validate encoding profiles.

### profiles Usage

```text
meedya-convert profiles [options]
```

### profiles Options

| Option | Type | Description | Default |
| ------ | ---- | ----------- | ------- |
| `--list` | Flag | List all available profiles (default action) | false |
| `--show <name>` | String | Show details of a named profile | -- |
| `--export <name>` | String | Export a profile to JSON | -- |
| `--export-file <path>` | String | Output file for export (default: stdout) | -- |
| `--import <file>` | String | Import a profile from a JSON file | -- |
| `--validate <name>` | String | Validate a profile for compatibility | -- |
| `--platform <name>` | String | Target platform for validation | -- |
| `--json` | Flag | Output as JSON | false |

### Platform Values

When using `--platform` with `--validate`, the following platforms are supported:

`macOS`, `iOS`, `tvOS`, `windows`, `android`, `chromecast`, `webBrowser`, `plex`, `jellyfin`, `roku`, `fireTV`.

### profiles Examples

```bash
# List all profiles
meedya-convert profiles --list

# Show profile details
meedya-convert profiles --show "H.265 High Quality"

# Export a profile to a file
meedya-convert profiles --export "H.265 High Quality" --export-file my_profile.json

# Export to stdout (pipe to another tool)
meedya-convert profiles --export "H.265 High Quality" | jq .

# Import a profile
meedya-convert profiles --import my_profile.json

# Validate a profile for iOS compatibility
meedya-convert profiles --validate "H.265 High Quality" --platform iOS --json
```

---

## `batch`

Encode multiple files from a directory or JSON job file.

### batch Usage

```text
meedya-convert batch --dir <path> --profile <name> [options]
meedya-convert batch --job-file <path> [options]
```

### batch Options

| Option | Short | Type | Description | Default |
| ------ | ----- | ---- | ----------- | ------- |
| `--dir <path>` | | String | Directory containing input files | -- |
| `--job-file <path>` | | String | Path to JSON job file | -- |
| `--profile <name>` | `-p` | String | Encoding profile (required with --dir) | -- |
| `--output <dir>` | `-o` | String | Output directory | `<dir>/encoded/` |
| `--extension <list>` | | String | File extensions to include (comma-separated) | mkv,mp4,avi,mov,webm,ts,m4v,flv,wmv,mpg |
| `--recursive` | | Flag | Scan subdirectories recursively | false |
| `--quiet` | | Flag | Suppress progress output | false |
| `--json` | | Flag | Output results as JSON | false |
| `--yes` | `-y` | Flag | Overwrite existing output files | false |

### batch Validation Rules

- Either `--dir` or `--job-file` must be provided (not both).
- `--profile` is required when using `--dir`.

### Job File Format

Job files are JSON arrays of `EncodingJobConfig` objects:

```json
[
  {
    "inputURL": "/path/to/video1.mkv",
    "outputURL": "/path/to/video1.mp4",
    "profile": { "name": "H.265 High Quality" }
  },
  {
    "inputURL": "/path/to/video2.mkv",
    "outputURL": "/path/to/video2.mp4",
    "profile": { "name": "H.264 Fast" }
  }
]
```

### batch Examples

```bash
# Encode all media files in a directory
meedya-convert batch --dir /videos --profile "H.265 Balanced" --output /encoded

# Include only MKV and AVI files, scan recursively
meedya-convert batch --dir /videos --profile "H.264 Fast" \
  --extension mkv,avi --recursive

# Run a batch job file
meedya-convert batch --job-file jobs.json

# JSON output with overwrite
meedya-convert batch --dir /videos --profile "H.265 Balanced" --json -y
```

### Shell Loop Alternative

```bash
for f in /videos/*.mkv; do
  meedya-convert encode -i "$f" -o "${f%.mkv}.mp4" --profile "H.265 Balanced" -y
done
```

---

## `manifest`

Generate adaptive streaming manifests (HLS/DASH/CMAF) with multi-bitrate variants.

### manifest Usage

```text
meedya-convert manifest --input <path> --output <dir> [options]
```

### manifest Options

| Option | Short | Type | Description | Default |
| ------ | ----- | ---- | ----------- | ------- |
| `--input <path>` | `-i` | String | Source media file (required) | -- |
| `--output <dir>` | `-o` | String | Output directory (required) | -- |
| `--format <type>` | `-f` | String | Manifest format: hls, dash, cmaf | hls |
| `--video-codec <codec>` | | String | Video codec: h264, h265, av1 | h264 |
| `--audio-codec <codec>` | | String | Audio codec: aac, ac3, eac3, opus | aac |
| `--preset <name>` | | String | Encoder preset | medium |
| `--segment-duration <sec>` | | Double | Segment duration in seconds | 6.0 |
| `--keyframe-interval <sec>` | | Double | Keyframe interval in seconds | 2.0 |
| `--variants <preset>` | | String | Variant ladder: default, 4k, uhd | default |
| `--ladder-file <path>` | | String | Custom variant ladder JSON file | -- |
| `--hdr` | | Flag | Preserve HDR in output variants | false |
| `--pixel-format <fmt>` | | String | Pixel format (yuv420p, yuv420p10le) | -- |
| `--hardware` | | Flag | Use hardware encoder | false |
| `--dry-run` | | Flag | Show FFmpeg commands without executing | false |
| `--quiet` | | Flag | Suppress progress output | false |
| `--json` | | Flag | Output result as JSON | false |
| `--yes` | `-y` | Flag | Overwrite existing output | false |

### Variant Ladder File

Custom variant ladders are JSON arrays of `StreamingVariant` objects:

```json
[
  { "label": "1080p", "width": 1920, "height": 1080, "videoBitrate": 5000000 },
  { "label": "720p", "width": 1280, "height": 720, "videoBitrate": 3000000 },
  { "label": "480p", "width": 854, "height": 480, "videoBitrate": 1500000 },
  { "label": "360p", "width": 640, "height": 360, "videoBitrate": 800000 }
]
```

### manifest Examples

```bash
# Generate HLS with default variant ladder
meedya-convert manifest -i source.mkv -o /output/hls

# Generate DASH with H.265 and 4K ladder
meedya-convert manifest -i source.mkv -o /output/dash \
  --format dash --video-codec h265 --variants 4k

# CMAF (dual HLS + DASH) with custom ladder
meedya-convert manifest -i source.mkv -o /output/cmaf \
  --format cmaf --ladder-file my_ladder.json

# Dry run to preview FFmpeg commands
meedya-convert manifest -i source.mkv -o /output/hls --dry-run

# HDR-preserving HLS with hardware encoding
meedya-convert manifest -i hdr_source.mkv -o /output/hls \
  --video-codec h265 --hdr --hardware
```

---

## `validate`

Validate encoding profiles, manifest configurations, and platform compatibility without performing an encode.

### validate Usage

```text
meedya-convert validate --profile <name> [options]
meedya-convert validate --profile-file <path> [options]
meedya-convert validate --manifest <path> [options]
```

### validate Options

| Option | Type | Description | Default |
| ------ | ---- | ----------- | ------- |
| `--profile <name>` | String | Validate a named built-in profile | -- |
| `--profile-file <path>` | String | Validate a profile from a JSON file | -- |
| `--manifest <path>` | String | Validate a manifest config JSON file | -- |
| `--platform <name>` | String | Target platform for compatibility check | -- |
| `--json` | Flag | Output results as JSON | false |
| `--strict` | Flag | Treat warnings as errors (exit code 6) | false |

### validate Checks

The validate command checks for:

- **Codec/container compatibility** — video and audio codecs supported by the container format.
- **HDR setting conflicts** — mutually exclusive options (toneMapToSDR + convertPQToHLG).
- **HDR codec support** — preserveHDR with codecs that lack HDR support.
- **CRF range validity** — values outside 0-63.
- **Hardware encoding warnings** — CRF vs QP differences with hardware encoders.
- **Bitrate/CRF conflicts** — both set simultaneously.
- **Platform compatibility** — codec/format support on target platforms.
- **Manifest variant ladder** — duplicate resolutions, bitrate ordering, variant count.

### validate Examples

```bash
# Validate a profile
meedya-convert validate --profile "H.265 High Quality"

# Validate for iOS compatibility
meedya-convert validate --profile "H.265 High Quality" --platform iOS

# Validate a profile file with strict mode
meedya-convert validate --profile-file custom.json --strict

# Validate a manifest config
meedya-convert validate --manifest streaming_config.json --json
```

---

## Exit Codes

| Code | Meaning |
| ---- | ------- |
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments or options |
| 3 | Input file not found or unreadable |
| 4 | Encoding failed (FFmpeg error) |
| 5 | Output write error (permissions, disk full) |
| 6 | Validation failed |
| 130 | Interrupted by signal (SIGINT / Ctrl+C) |

---

## JSON Progress Output

When `encode --json` is active, progress events are emitted to stderr as JSON:

```json
{"progress":45}
```

The `progress` field is an integer percentage (0-100).

Upon completion, a JSON result object is printed to stdout:

```json
{
  "status": "completed",
  "input": "/path/to/input.mkv",
  "output": "/path/to/output.mp4",
  "elapsed_seconds": 234.5,
  "profile": "H.265 High Quality"
}
```

---

## Environment Variables

| Variable | Description |
| -------- | ----------- |
| `FFMPEG_PATH` | Override FFmpeg binary location |
| `FFPROBE_PATH` | Override FFprobe binary location |
| `MEEDYA_PROFILES_DIR` | Custom directory for encoding profiles |
| `MEEDYA_TEMP_DIR` | Custom temp directory for intermediate files |
| `NO_COLOR` | Disable coloured output (respects the NO_COLOR convention) |
