# ❓ Frequently Asked Questions

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## General

### What is MeedyaConverter?

MeedyaConverter is a professional media conversion application that converts audio/video files between formats, prepares content for adaptive streaming (HLS/MPEG-DASH), and supports direct upload to cloud services. It is designed as a modern, more capable alternative to HandBrake.

### How is MeedyaConverter different from HandBrake?

Key differences include:

- **Video passthrough** — copy video without re-encoding (HandBrake always re-encodes)
- **Subtitle passthrough** — preserve original subtitle formats (HandBrake converts to SRT)
- **Multiple video streams** — handle files with multiple video tracks
- **Adaptive streaming** — built-in HLS and MPEG-DASH preparation
- **Audio normalization** — EBU R128 and ReplayGain support
- **Cloud upload** — direct upload to Dropbox, Google Drive, OneDrive, Amazon S3 (and S3-compatible endpoints such as Backblaze B2, Cloudflare R2, or DigitalOcean Spaces), or SFTP

### Is MeedyaConverter free?

MeedyaConverter is a proprietary product by MWBM Partners Ltd. Licensing details will be announced closer to release.

### What platforms are supported?

- **macOS** (Apple Silicon only) — primary platform
- **Windows** (x86, x64, ARM) — planned
- **Linux** (x86, x64, ARM, Raspberry Pi) — planned

---

## Encoding

### Can I convert audio files without video?

Yes. MeedyaConverter fully supports audio-only files. Simply import an audio file and choose your output format.

### Does MeedyaConverter preserve HDR?

Yes. MeedyaConverter preserves HDR10, HDR10+, HLG, and Dolby Vision metadata when the output format and codec support it. It can also automatically create Dolby Vision from HDR10+ sources.

### What is passthrough mode?

Passthrough copies a stream (video, audio, or subtitles) directly to the output file without re-encoding. This is much faster and preserves original quality, but the output container must support the codec.

### Can I encode multiple files at once?

Yes. Add multiple files to the job queue and MeedyaConverter will process them sequentially (or in parallel, depending on your settings).

### What does "Tag files automatically while converting" do?

It is an opt-in switch in Settings › Metadata. When it is on, every file
converted from the queue (including watch folders and scheduled jobs) and
from AppleScript is looked up on its way through the encoder — films on TMDB,
music on MusicBrainz — and any tag it is missing (title, year, genre, artist,
and so on) is added. It never renames the file, never embeds artwork, and
never replaces a tag the file already has. See "Privacy" below for exactly
what is sent, and Settings › Metadata for the full set of captions.

---

## Adaptive Streaming

### What is adaptive streaming?

Adaptive Bitrate (ABR) streaming encodes your video at multiple quality levels. Players like VideoJS or Shaka automatically switch between qualities based on the viewer's bandwidth, providing the best possible experience.

### Does MeedyaConverter create both HLS and MPEG-DASH?

Yes. You can generate HLS (.m3u8), MPEG-DASH (.mpd), or both from a single source file.

### Can I add encryption to my streams?

Not yet. AES-128 HLS encryption exists in the engine as a configuration
type with no UI and no call site outside its own unit tests — there is no
way to turn it on from the app today. Treat this as a roadmap item, not a
shipped feature.

---

## Privacy

### Does MeedyaConverter access the internet for metadata?

Only in two cases, and both are about looking up a title, never about
sending your files:

- **You click "Look Up…"** in the Metadata Tag Editor. A music file's
  search terms (title/artist) go to `musicbrainz.org`; a video file's title
  and year go to `api.themoviedb.org`, using the TMDB key you saved in
  Settings › Metadata. With no key saved, the film lookup sends nothing.
- **Automatic tagging is switched on** (Settings › Metadata › "Tag files
  automatically while converting" — **off by default**). Each file
  converted from the queue, a watch folder, a scheduled job, or AppleScript
  is looked up the same way, without you clicking anything: a video's title
  (and year, if known) to TMDB, a music file's title and artist to
  MusicBrainz. With no TMDB key saved, nothing is sent for a film. This
  never adds more than about 30 seconds to a conversion, and a slow or
  failed lookup never makes the conversion fail — it just runs without the
  extra tags, and the Activity Log says why.

Encoding pipelines and the `meedya-convert` command-line tool never look
anything up, whichever switch is on.

### Will auto-tagging overwrite my tags?

No. It only ever adds a tag the file is missing. A tag the file already has
is kept, file names are never changed, and an existing `.nfo` file is never
overwritten.

---

## Troubleshooting

See the [Troubleshooting Guide](troubleshooting.md) for common issues and solutions.
