# 🖼️ Vector Conversion

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overview

MeedyaConverter includes two Tools-sidebar surfaces for turning raster
content into editable, scalable SVG:

- **Vector Conversion** — trace a single raster image into an SVG (the
  first frame only, even for an animated source format like GIF/APNG/WebP —
  animated raster → animated SVG is not implemented).
- **ProRes to Vector** — extract frames from an alpha-carrying ProRes 4444
  clip and assemble them into an animated SVG, for motion-graphics/VFX
  assets that need to become a scalable, editable vector asset.

Both share the same underlying tracing engine and configuration editor, so
options behave identically wherever they appear. Added in **issue #376**
(raster↔vector engine) and **issue #377** (ProRes↔vector engine); surfaced
in the GUI in **issue #402** (Vector Conversion view) and **issue #404**
(ProRes to Vector view) as part of the #381 UI-gap closure.

> **Status:** these tools run for real in **Direct builds only** — hidden in
> the App Store build, because the App Sandbox cannot spawn a subprocess and
> potrace (below) is GPL. The actual pipeline is: an ffmpeg pre-pass
> normalises the source raster into the one format the chosen tracer can
> read, then **potrace** or **vtracer** traces it to SVG (ProRes adds a frame
> dump before, and a SMIL animation assembly after). There is no
> `meedya-convert` CLI subcommand for vector/image conversion yet (bulk image
> conversion is tracked separately as the future Phase 17). Settings persist
> across launches via `@AppStorage`; a few of the options below are **not
> applied** by the executor — see "Notes" for the exact list.

---

## Vector Conversion (raster → SVG)

**Tools → Vector Conversion**

### Source

**Choose Image…** opens a file picker accepting any of the 30+ raster
formats the engine recognises:

| Group | Formats |
| ----- | ------- |
| Common | BMP, JPEG, GIF, PNG, TIFF, WebP, AVIF, HEIC, HEIF |
| Modern | JPEG XL (JXL), JPEG 2000 (JP2), Animated PNG (APNG) |
| Professional | PSD, EXR, HDR, DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2, PEF |
| Legacy | TGA, PCX, ICO, DDS |
| Netpbm | PBM, PGM, PPM, PAM |

The format is detected from the file's extension and shown next to the file
name; an unrecognised extension disables Convert. Output is fixed at
**SVG 2.0**.

### Editability presets

Picking a preset auto-fills **Tracing mode** and **Colour count** (except
`Custom`, which keeps your manual values):

| Preset | Tracing mode | Colour count |
| ------ | ------------ | ------------ |
| Logo / Icon | Outline | 8 |
| Illustration (default) | Colour Quantisation | 32 |
| Photorealistic | Photorealistic | 256 |
| Technical Diagram | Outline | 4 |
| Hand-drawn Sketch | Colour Quantisation | 16 |
| Custom | — (manual) | — (manual) |

### Tracing modes

| Mode | Tool used | Best for |
| ---- | --------- | -------- |
| Outline | potrace | Logos/icons — a single outline curve per region |
| Colour Quantisation | vtracer | Illustrations — quantises to N colours and traces each plane |
| Monochrome | potrace | Line art — single-channel black/white trace |
| Photorealistic | vtracer | Photographs — colour raster stippling; produces large files |

The **Colour count** stepper (2–256) only applies to Colour Quantisation and
Photorealistic modes — it's disabled for Outline and Monochrome.

### Alpha strategy

| Strategy | Behaviour |
| -------- | --------- |
| Clip-path with opacity (default) | `clip-path` for fully-transparent regions, `fill-opacity` for semi-transparent ones |
| Flatten against background | Composites onto a solid background colour — use when the target renderer can't honour transparency |
| Discard alpha | Drops the alpha channel entirely |

There is no Animation section here even for an animated source format
(GIF/APNG/WebP) — `RasterVectorExecutor` traces the first frame only.
Animated raster → animated SVG is a follow-up (#376), not implemented.

### Curve simplification

Tolerance for curve simplification (0.0–10.0, default 2.0): `0` preserves
every point, `10` smooths aggressively. This is the only option below the
Alpha section — the "Preserve EXIF / IPTC / XMP metadata" and "OCR text
regions" toggles that used to appear here were removed: no bundled tool
implements either, so they never did anything.

---

## ProRes to Vector

**Tools → ProRes to Vector**

Converts an alpha-carrying ProRes clip into an animated SVG via:
`ProRes 4444 → per-frame PNG extraction (alpha preserved) → per-frame
tracing (same engine as Vector Conversion) → animated SVG assembly`.
Standard 4:2:2 ProRes variants have no alpha and aren't in scope here — use
the regular encoding pipeline for those.

### Source

The clip you selected in the **Source** tab (`viewModel.selectedFile`) is
the input; it needs a video stream with known width/height, or Convert stays
disabled with a reason. Alongside it:

| Option | Values |
| ------ | ------ |
| ProRes variant | ProRes 4444, ProRes 4444 XQ, ProRes 4444 (HDR) — the HDR variant is tone-mapped to SDR before tracing |
| Frame rate | 23.976, 24 (default), 25, 29.97, 30, 50, 59.94, 60 fps |
| Start time | 0–3600 s (0 = clip start) |
| End time | −1 to 3600 s (−1 = until end of clip) |
| Frame stride | 1–10 (process every Nth frame; `1` = every frame) |

### Alpha handling

| Option | Behaviour |
| ------ | --------- |
| Preserve per-frame (clip-paths) (default) | Converts pre-multiplied → straight alpha, keeping RGBA through tracing |
| Alpha matte only (monochrome) | Extracts the alpha matte as a monochrome animated SVG — always traced with potrace (a matte is monochrome by definition), regardless of the Tracing mode picker below |
| Flatten against background | Composites against a background colour, dropping alpha |

### Tracing

Embeds the same Preset / Tracing / Alpha sections documented above under
[Vector Conversion](#vector-conversion-raster--svg) — the per-frame tracing
settings can legitimately differ from your stand-alone Vector Conversion
preferences, since they're stored separately. The input format for per-frame
tracing is always PNG (the extracted frames), so there's no separate
Animation section here — that's controlled by the outer **Animation**
section below.

### Animation

Only **SMIL** is offered — it is the only method `ProResVectorExecutor`
implements. CSS @keyframes, Hybrid, and Static frame sequence are not
implemented in this build.

There is no Assembly section — the "Shape persistence" and "Keyframe
extraction" toggles that used to appear here were removed: `ProResVectorExecutor`
traces every frame independently and does not track shape identity or skip
unchanged frames, so neither toggle did anything.

### Output-size warning

A warning banner appears when your chosen frame rate, frame stride, and
time range would produce more than about ten seconds' worth of traced
frames, or whenever **Photorealistic** tracing is selected (which is
always heavy regardless of duration). It uses the real duration of the
file selected in the Source tab when one is chosen; otherwise it falls back
to a synthetic reference so the warning still means something before you've
picked a clip:

> **Output size may be large.** These settings can produce very large SVG
> files. Consider increasing the frame stride, narrowing the time range,
> or switching to a non-photorealistic tracing mode.

---

## Notes

- **Direct-only.** Both tools run only in the Direct `.dmg` build — hidden
  in the App Store build, because the App Sandbox cannot spawn a subprocess
  and potrace is GPL-2.0-or-later (bundled Direct-only per DR-0001; vtracer
  is MIT and ships in every distribution, but is inert without potrace's
  sibling being reachable too, since the nav item hides both together).
- Both tools persist their settings per-view via `@AppStorage` (namespaced
  `vectorConversion.*` and `proresVector.*`), so your preferences survive
  app relaunches independently of each other.
- Tracing is performed by real `potrace`/`vtracer` subprocesses, selected
  automatically based on the tracing mode (or forced to potrace for a ProRes
  alpha matte). Both are resolved via **Settings → Paths → Vector Tracing
  Tools**: a Direct build finds them bundled in `Contents/Helpers`; a
  dev/Homebrew build needs them on `PATH` or a path set there. Vector→raster
  rendering (e.g. for a live preview) is not implemented — no tool is
  bundled or invoked for that direction.
- Options that are **not applied** by either executor (kept only for
  JSON/AppStorage compatibility with existing profiles): "Preserve EXIF /
  IPTC / XMP metadata", "OCR text regions" (Vector Conversion's former
  "Other" section), and "Shape persistence" / "Keyframe extraction" (ProRes's
  former "Assembly" section). Animated raster → animated SVG and every
  ProRes animation method except SMIL are likewise not implemented.

---

*See also: [cli-reference.md](cli-reference.md), [encoding-guide.md](encoding-guide.md).*
