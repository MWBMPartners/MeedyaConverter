# 💻 CLI Reference

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overview

MeedyaConverter ships a full-featured command-line tool, **`meedya-convert`**,
for automation, scripting, CI/CD pipelines, and headless operation. It is
built with [Swift Argument Parser](https://github.com/apple/swift-argument-parser)
and shares the same `ConverterEngine` core as the SwiftUI app, so anything you
can do in the GUI has a scriptable equivalent here.

The CLI is distributed as a separate signed + notarised tarball alongside the
`.dmg` on the [GitHub Releases](https://github.com/MWBMPartners/MeedyaConverter/releases)
page.

For the complete machine-readable specification (every option, JSON schema,
and exit code) see [`docs/api/meedya-convert-api.yaml`](../docs/api/meedya-convert-api.yaml) —
this document is the human-readable companion to that spec.

---

## Usage

```bash
meedya-convert <subcommand> [options]
meedya-convert --help
meedya-convert --version
```

The six subcommands are: `encode`, `probe`, `profiles`, `batch`, `manifest`,
and `validate`. Every subcommand also accepts `--help` for its own usage text.

---

## Commands

### `encode` — Transcode a Media File

```bash
meedya-convert encode --input <path> [--output <path>] [options]

# Examples:
meedya-convert encode --input input.mkv --output output.mp4 --profile "Web Standard"
meedya-convert encode --input input.mkv --video-codec h265 --audio-codec aac --crf 22
meedya-convert encode --input input.wav --audio-codec flac --output output.flac
meedya-convert encode -i input.mov --video-passthrough --audio-codec aac --output out.mp4
```

If `--output` is omitted, the output is written next to the input with a
`_converted` suffix and an extension matching the resolved profile/container.

| Option | Description |
| ------ | ----------- |
| `--input`, `-i` (required) | Path to the input media file. Must exist. |
| `--output`, `-o` | Output file path. |
| `--profile`, `-p` | Name/ID of a built-in or custom encoding profile. Flags below override the profile's settings. |
| `--video-codec` | `h264`, `h265`, `av1`, `prores`, `vp9`, `copy` |
| `--crf` | Constant Rate Factor (lower = higher quality). |
| `--video-bitrate` | Target video bitrate, e.g. `5000k`, `10M`. |
| `--preset` | Encoder speed/quality preset: `ultrafast` … `veryslow`. |
| `--resolution` | Output resolution, e.g. `1920x1080`. |
| `--video-passthrough` | Copy the video stream (no re-encode). Cannot combine with `--video-codec`. |
| `--audio-codec` | `aac`, `ac3`, `eac3`, `flac`, `opus`, `copy` |
| `--audio-bitrate` | Target audio bitrate, e.g. `128k`, `256k`, `640k`. |
| `--audio-channels` | `1`, `2`, `6` (5.1), `8` (7.1). |
| `--audio-passthrough` | Copy the audio stream. Cannot combine with `--audio-codec`. |
| `--subtitle-passthrough` | Copy subtitle streams. |
| `--no-subtitles` | Exclude all subtitle streams. |
| `--container` | `mkv`, `mp4`, `webm`, `mov`, `ts` |
| `--tonemap` | Enable HDR→SDR tone mapping. Mutually exclusive with `--pq-to-hlg`. |
| `--tonemap-algorithm` | `hable`, `reinhard`, `mobius`, `bt2390`, `linear` (used with `--tonemap`). |
| `--pq-to-hlg` | Convert PQ (HDR10) to HLG. Mutually exclusive with `--tonemap`. |
| `--pq-to-dv-hlg` | Convert PQ to Dolby Vision Profile 8.4 + HLG combined output. |
| `--no-copy-metadata` | Do not copy source metadata to the output. |
| `--no-copy-chapters` | Do not copy chapter markers to the output. |
| `--video-stream` | Video stream index to encode (default: first). |
| `--audio-stream` | Audio stream index to encode (default: first). |
| `--subtitle-stream` | Subtitle stream index to include. |
| `--map-all` | Map all streams from the source. |
| `--hardware` | Use a hardware encoder (VideoToolbox) if available. |
| `--quiet` | Suppress progress output. |
| `--json` | Emit progress and the final result as JSON. |
| `--yes`, `-y` | Overwrite an existing output file without prompting. |

**Exit codes:** `0` success · `4` encoding failed · `5` output write error (exists without `--yes`).

---

### `probe` — Inspect a Media File

```bash
meedya-convert probe --input <path> [--format text|json] [options]

# Examples:
meedya-convert probe --input input.mkv
meedya-convert probe --input input.mkv --format json
meedya-convert probe -i input.mkv --streams-only
meedya-convert probe -i input.mkv --hdr
```

| Option | Description |
| ------ | ----------- |
| `--input`, `-i` (required) | Path to the media file to inspect. |
| `--format`, `-f` | `text` (default) or `json`. |
| `--streams-only` | Show only stream information (skip file-level details and metadata). |
| `--hdr` | Show detailed HDR metadata (primaries, transfer characteristics, MaxCLL/MaxFALL, mastering display luminance). |

`--format json` prints the engine's full `MediaFile` model — see the
`MediaFile` schema in `docs/api/meedya-convert-api.yaml` for the exact shape.

**Exit codes:** `0` success · `4` probe failed (FFprobe error or unreadable file).

---

### `profiles` — List, Show, Export, Import, and Validate Profiles

Unlike the other subcommands, `profiles` is driven entirely by flags — there
is no `list`/`show` sub-subcommand. With no flags at all it lists every
built-in profile (same as `--list`).

```bash
meedya-convert profiles [--list] [--show <name>] [--export <name>]
                         [--import <file>] [--validate <name>]
                         [--platform <name>] [--json]

# Examples:
meedya-convert profiles --list
meedya-convert profiles --show "Web Standard"
meedya-convert profiles --export "Web Standard" --export-file profile.json
meedya-convert profiles --import profile.json
meedya-convert profiles --validate "Web Standard" --platform plex
```

| Option | Description |
| ------ | ----------- |
| `--list` | List all built-in profiles, grouped by category (default action). |
| `--show <name>` | Print the full settings for a named profile. |
| `--export <name>` | Export a named profile to JSON (stdout unless `--export-file` is set). |
| `--export-file <path>` | Output file for `--export`. |
| `--import <file>` | Import a profile from a JSON file. |
| `--validate <name>` | Check a named profile for codec/container compatibility issues. |
| `--platform <name>` | Target platform for `--validate`'s compatibility check (see [validate](#validate--validate-profiles-manifests-and-platform-compatibility) below for the platform list). |
| `--json` | Output as JSON instead of human-readable text. |

**Exit codes:** `0` success · `2` invalid arguments (profile not found).

---

### `batch` — Encode Multiple Files

Two mutually-exclusive modes: **directory mode** (`--dir`, requires
`--profile`) scans a folder for media files and encodes each with the same
profile; **job-file mode** (`--job-file`) encodes an arbitrary JSON array of
per-file jobs, each with its own profile and options.

```bash
meedya-convert batch --dir <path> --profile <name> [--output <dir>] [options]
meedya-convert batch --job-file <path> [options]

# Examples:
meedya-convert batch --dir ./videos --profile "Web Standard" --output ./encoded
meedya-convert batch --dir ./videos --profile "Web Standard" --recursive --extension mkv,mp4
meedya-convert batch --job-file jobs.json --json
```

| Option | Description |
| ------ | ----------- |
| `--dir` | Directory to scan for input files. Mutually exclusive with `--job-file`. |
| `--job-file` | Path to a JSON job file (array of job objects — see below). Mutually exclusive with `--dir`. |
| `--profile`, `-p` | Encoding profile name. Required with `--dir`. |
| `--output`, `-o` | Output directory. Defaults to an `encoded/` subdirectory inside `--dir`. |
| `--extension` | Comma-separated extensions to include when scanning. Default: `mkv,mp4,avi,mov,webm,ts,m4v,flv,wmv,mpg`. |
| `--recursive` | Recursively scan subdirectories. |
| `--quiet` | Suppress progress output. |
| `--json` | Output the batch summary as JSON (`total`/`completed`/`failed`/`skipped`). |
| `--yes`, `-y` | Overwrite existing output files without prompting. |

**Exit codes:** `0` all jobs succeeded · `4` one or more jobs failed.

---

### `manifest` — Generate Adaptive Streaming Manifests

Encodes a source file into multiple quality variants and writes the
corresponding HLS, MPEG-DASH, or CMAF (both) manifest.

```bash
meedya-convert manifest --input <path> --output <dir> [--format hls|dash|cmaf] [options]

# Examples:
meedya-convert manifest --input input.mkv --output ./streaming --format hls
meedya-convert manifest --input input.mkv --output ./streaming --format dash --variants 4k
meedya-convert manifest --input input.mkv --output ./streaming --format cmaf --dry-run
```

| Option | Description |
| ------ | ----------- |
| `--input`, `-i` (required) | Path to the source media file. |
| `--output`, `-o` (required) | Output directory for manifest + segment files. |
| `--format`, `-f` | `hls` (default), `dash`, or `cmaf` (writes both). |
| `--video-codec` | `h264` (default), `h265`, `av1`, applied to every variant. |
| `--audio-codec` | `aac` (default), `ac3`, `eac3`, `opus`. |
| `--preset` | Encoder preset. Default `medium`. |
| `--segment-duration` | Segment duration in seconds. Default `6.0`. |
| `--keyframe-interval` | Keyframe interval in seconds (GOP alignment). Default `2.0`. |
| `--variants` | `default` (≤1080p) or `4k`/`uhd` (includes 2160p). Default `default`. |
| `--ladder-file` | Path to a JSON `StreamingVariant[]` array — overrides `--variants` with a custom ladder. |
| `--hdr` | Preserve HDR metadata in output variants. |
| `--pixel-format` | e.g. `yuv420p`, `yuv420p10le`. |
| `--hardware` | Use a hardware encoder if available. |
| `--dry-run` | Print the FFmpeg commands that would run, without executing them. |
| `--quiet` | Suppress progress output. |
| `--json` | Output the result as JSON. |
| `--yes`, `-y` | Overwrite existing output without prompting. |

**Exit codes:** `0` success · `1` general error (e.g. FFmpeg unavailable) · `2` invalid arguments.

---

### `validate` — Validate Profiles, Manifests, and Platform Compatibility

Checks encoding profiles and manifest configurations without performing an
encode. At least one of `--profile`, `--profile-file`, or `--manifest` is
required.

```bash
meedya-convert validate --profile <name> [--platform <name>] [--strict] [--json]
meedya-convert validate --profile-file <path> [--platform <name>] [--strict] [--json]
meedya-convert validate --manifest <path> [--json]

# Examples:
meedya-convert validate --profile "Web Standard" --platform plex
meedya-convert validate --profile-file profile.json --strict
meedya-convert validate --manifest ladder.json --json
```

| Option | Description |
| ------ | ----------- |
| `--profile` | Validate a named built-in profile. |
| `--profile-file` | Validate a profile from a JSON file on disk. |
| `--manifest` | Validate a manifest configuration JSON file (variant ladder, bitrate ordering, codec compatibility). |
| `--platform` | `macOS`, `iOS`, `tvOS`, `windows`, `android`, `chromecast`, `webBrowser`, `plex`, `jellyfin`, `roku`, `fireTV` |
| `--strict` | Treat warnings as errors — any warning produces a non-zero exit. |
| `--json` | Output `{ valid, errors[], warnings[] }` as JSON. |

Checks performed include: codec/container compatibility, conflicting HDR
settings (`toneMapToSDR` + `preserveHDR`, `toneMapToSDR` + `convertPQToHLG`),
HDR codec support, CRF range (0–63), hardware-encoder-with-CRF mismatches, and
bitrate/CRF conflicts.

**Exit codes:** `0` valid (warnings allowed unless `--strict`) · `6` validation failed (errors, or warnings under `--strict`).

---

## JSON Job Files (`batch --job-file`)

A job file is a JSON array of job objects. Each `profile` field is a **full
`EncodingProfile` object** — the same shape `profiles --export` produces, so
the easiest way to build one by hand is to export a built-in profile and
edit it:

```bash
meedya-convert profiles --export "Apple HLS" --export-file profile.json
```

```json
[
  {
    "inputURL": "file:///Users/you/Movies/source.mkv",
    "outputURL": "file:///Users/you/Movies/output/source.mp4",
    "profile": { "...": "full EncodingProfile object, e.g. from profiles --export" },
    "videoStreamIndex": 0,
    "audioStreamIndex": 0,
    "subtitleStreamIndex": null,
    "mapAllStreams": false,
    "extraArguments": []
  }
]
```

---

## Exit Codes

| Code | Meaning |
| ---- | ------- |
| `0` | Success |
| `1` | General error |
| `2` | Invalid arguments / usage error |
| `3` | Input file not found or unreadable |
| `4` | Encoding (or probe) failed — FFmpeg/FFprobe returned an error |
| `5` | Output write error (file exists without `--yes`, permissions, disk full) |
| `6` | Validation failed (profile or manifest validation errors, or warnings under `--strict`) |
| `130` | Interrupted by signal (SIGINT / Ctrl+C) |

These match `docs/api/meedya-convert-api.yaml`'s `ExitCodes` schema exactly —
scripts and CI pipelines can branch on them without parsing stderr text.

---

*See also: [encoding-guide.md](encoding-guide.md), [adaptive-streaming.md](adaptive-streaming.md),
[vector-conversion.md](vector-conversion.md).*
