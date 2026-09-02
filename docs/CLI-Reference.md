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
| `serve` | Run the REST API server for headless/remote encoding control |

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
| `--tonemap-algorithm <alg>` | | String | Tone map algorithm (hable, reinhard, mobius, bt2390, clip) | hable |
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
- `--tonemap-algorithm` is not validated: any string is accepted, and a value that isn't `hable`, `reinhard`, `mobius`, `bt2390`, or `clip` silently falls back to `hable` with no warning. Note that the CLI's own `--help` text still advertises `linear` instead of `clip` — passing `linear` does not match any algorithm and falls back to `hable` the same way.
- `--crf` and `--audio-channels` are not range-checked by `encode` itself — any integer is accepted and forwarded to FFmpeg as-is. Use `meedya-convert validate` to catch an out-of-range CRF (outside 0-63).

### encode Examples

```bash
# Basic H.265 encode
meedya-convert encode -i input.mkv -o output.mp4 --video-codec h265 --crf 20

# Use a built-in profile
meedya-convert encode -i input.mkv -o output.mp4 --profile "Web High Quality"

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
meedya-convert encode -i input.mkv -o output.mp4 --profile "Web High Quality" --json
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
meedya-convert profiles --show "Web High Quality"

# Export a profile to a file
meedya-convert profiles --export "Web High Quality" --export-file my_profile.json

# Export to stdout (pipe to another tool)
meedya-convert profiles --export "Web High Quality" | jq .

# Import a profile
meedya-convert profiles --import my_profile.json

# Validate a profile for iOS compatibility
meedya-convert profiles --validate "Web High Quality" --platform iOS --json
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

Job files are JSON arrays of `EncodingJobConfig` objects — the CLI/engine's **full internal job struct**, not a simplified input/output/profile-name triple. Decoded with a plain `JSONDecoder()` and no custom strategies, so every non-`Optional` stored property must be present, even ones with a friendly default in Swift's `init` (an `init` default does not make a field optional in JSON), and `profile` must be a **complete** `EncodingProfile` object, not just `{ "name": "..." }`. `inputURL`/`outputURL` are `file://` URLs, not plain paths, and `createdAt` is a raw number — seconds since the Swift reference date (2001-01-01T00:00:00Z) — not an ISO 8601 string.

The easiest way to get a valid `profile` object is `meedya-convert profiles --export "<name>"`, which prints a complete, correctly-shaped `EncodingProfile`. A minimal but genuinely decodable job file looks like this:

```json
[
  {
    "id": "b2e6d1b0-0c1e-4a5f-9c3d-9e1a2b3c4d5e",
    "inputURL": "file:///path/to/video1.mkv",
    "outputURL": "file:///path/to/video1.mp4",
    "profile": {
      "id": "3f6d9b3a-1b1a-4b1a-9b1a-1b1a4b1a9b1a",
      "name": "Web High Quality",
      "description": "",
      "category": "custom",
      "isBuiltIn": false,
      "videoCodec": "h265",
      "videoCRF": 20,
      "videoPassthrough": false,
      "useHardwareEncoding": false,
      "encodingPasses": 1,
      "preserveHDR": false,
      "toneMapToSDR": false,
      "convertPQToHLG": false,
      "useHlgTools": false,
      "convertPQToDVHLG": false,
      "audioCodec": "aac",
      "audioPassthrough": false,
      "applyPeakLimiter": false,
      "subtitlePassthrough": false,
      "containerFormat": "mkv"
    },
    "mapAllStreams": false,
    "outputMetadata": {},
    "streamMetadata": {},
    "extraArguments": [],
    "subtitleStreamActions": [],
    "createdAt": 0,
    "priority": 0
  }
]
```

`videoCodec`, `videoCRF`, `audioCodec`, and `containerFormat` above are the fields worth changing per job; `id` values just need to be unique UUIDs. See [`docs/api/meedya-convert-api.yaml`](api/meedya-convert-api.yaml)'s `EncodingJobConfig` and `EncodingProfile` schemas for the complete field list, including the optional HDR-metadata and stream-selection fields not shown here.

### batch Examples

```bash
# Encode all media files in a directory
meedya-convert batch --dir /videos --profile "Web High Quality" --output /encoded

# Include only MKV and AVI files, scan recursively
meedya-convert batch --dir /videos --profile "Quick Convert" \
  --extension mkv,avi --recursive

# Run a batch job file
meedya-convert batch --job-file jobs.json

# JSON output with overwrite
meedya-convert batch --dir /videos --profile "Web High Quality" --json -y
```

### Shell Loop Alternative

```bash
for f in /videos/*.mkv; do
  meedya-convert encode -i "$f" -o "${f%.mkv}.mp4" --profile "Web High Quality" -y
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
| `--hdr` | | Flag | Preserve HDR in output variants — **not implemented; this flag is rejected outright**, see Validation Rules below | false |
| `--pixel-format <fmt>` | | String | Pixel format (yuv420p, yuv420p10le) | -- |
| `--hardware` | | Flag | Use hardware encoder | false |
| `--dry-run` | | Flag | Show FFmpeg commands without executing | false |
| `--quiet` | | Flag | Suppress progress output | false |
| `--json` | | Flag | Output result as JSON | false |
| `--yes` | `-y` | Flag | Overwrite existing output | false |

### manifest Validation Rules

- `--format` must be one of `hls`, `dash`, or `cmaf`.
- `--hdr` is rejected outright — passing it throws a validation error before FFmpeg is even located. There is no HDR colour signalling (mastering-display/MaxCLL side data, 10-bit pixel format) in the manifest encode path, unlike the main `encode` pipeline; accepting the flag would silently do nothing, so it fails loudly instead.
- An unrecognised `--video-codec` or `--audio-codec` is rejected with a list of accepted values, mirroring `encode`'s codec flags. There is no `copy`/passthrough concept for `manifest` — every variant is always re-encoded.
- `--variants custom` requires `--ladder-file`; a typo other than the literal word `custom` still silently falls through to the default ladder with no error.

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

# H.265 HLS with hardware encoding (do NOT pass --hdr — it is rejected;
# see manifest Validation Rules above)
meedya-convert manifest -i hdr_source.mkv -o /output/hls \
  --video-codec h265 --hardware
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
meedya-convert validate --profile "Web High Quality"

# Validate for iOS compatibility
meedya-convert validate --profile "Web High Quality" --platform iOS

# Validate a profile file with strict mode
meedya-convert validate --profile-file custom.json --strict

# Validate a manifest config
meedya-convert validate --manifest streaming_config.json --json
```

---

## `serve`

Run the REST API server for headless/remote encoding control, exposing the HTTP endpoints documented in [`docs/api/meedya-http-api.yaml`](api/meedya-http-api.yaml) — `POST /encode`, `POST /probe`, `GET /status`, `GET /queue`, and `GET /profiles` — backed by a real encoding engine.

### serve Usage

```text
meedya-convert serve [--port <n>] [--api-key <key>]
```

### serve Options

| Option | Type | Description | Default |
| ------ | ---- | ----------- | ------- |
| `--port <n>` | Integer | TCP port to listen on (1-65535) | 8484 |
| `--api-key <key>` | String | Bearer token clients must send as `Authorization: Bearer <key>` | Random one-time key, printed to stderr |

### serve Validation Rules

- `--port` must be between 1 and 65535.
- `--api-key`, if supplied, cannot be empty or whitespace-only.

### Authentication

Authentication is mandatory — `APIServer` has no unauthenticated mode. Every request must carry a matching `Authorization: Bearer <api-key>` header, or it is rejected with HTTP 401. If `--api-key` is omitted, `serve` generates a random one-time key and prints it to stderr at startup; it is **not shown again**, so save it immediately.

### Binding

The listener accepts connections on **all interfaces**. `APIServer` has no `--host`/bind-address option, so there is no way to restrict it to loopback from the CLI — do not expose the port to an untrusted network.

### Known Limitation — Queue Runner

`POST /encode` enqueues jobs onto the real encoding queue but does not start the queue runner, and `serve` does not start one either — jobs sit in `queued` status until something else drives the queue (in the desktop app, that's the "Start Queue" button). This mirrors the desktop app's "Add to Queue" without "Start Queue".

### serve Exit Codes

`serve` does not return under normal operation — once the listener binds, the process sleeps indefinitely and only exits on SIGINT (Ctrl+C).

| Code | Meaning |
| ---- | ------- |
| 1 | The listener failed to bind (e.g. the port is already in use) |
| 2 | Invalid `--port` (outside 1-65535) or an empty `--api-key` |
| 130 | Interrupted by signal (SIGINT / Ctrl+C) |

### serve Examples

```bash
# Start with an auto-generated API key (printed to stderr — save it)
meedya-convert serve

# Start on a custom port with an explicit API key
meedya-convert serve --port 9000 --api-key "$(openssl rand -hex 16)"

# Call the running server — see docs/api/meedya-http-api.yaml for the full HTTP API
curl -H "Authorization: Bearer <api-key>" http://localhost:8484/status
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
  "profile": "Web High Quality"
}
```

---

## Environment Variables

`meedya-convert` does not currently read any environment variables for configuration — there is no `FFMPEG_PATH`/`FFPROBE_PATH` override, no `MEEDYA_PROFILES_DIR`/`MEEDYA_TEMP_DIR`, and no `NO_COLOR` support (the CLI's terminal output has no ANSI colour codes to begin with, so there is nothing to disable).

Instead:

- **FFmpeg/FFprobe location** is auto-discovered by `FFmpegBundleManager`, in order: the app bundle's `Contents/Helpers`, legacy `Resources/Tools` and `Resources` paths, the running executable's own directory, then `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `/usr/bin`, and `/bin`. Every CLI command constructs its `EncodingEngine()` and calls `configure()` with no path arguments, so there is currently no CLI flag or environment variable to point it at a binary outside this search list.
- **Encoding profiles** are stored at `~/Library/Application Support/MeedyaConverter/Profiles/user_profiles.json` on macOS (`EncodingProfileStore`'s default `storageDirectory`), not configurable from the CLI.
- **Temporary files** (e.g. `DualDynamicHDRPipeline`'s intermediate files, `ProfileSharing`'s export staging) use `FileManager.default.temporaryDirectory` — the OS-standard per-user temp directory — not a custom location.
