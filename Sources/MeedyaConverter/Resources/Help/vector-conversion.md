# 🖼️ Vector Conversion

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overview

MeedyaConverter includes two Tools-sidebar surfaces for turning raster
content into editable, scalable SVG:

- **Vector Conversion** — trace a single raster image (or an animated
  raster like GIF/APNG/WebP) into an SVG.
- **ProRes to Vector** — extract frames from an alpha-carrying ProRes 4444
  clip and assemble them into an animated SVG, for motion-graphics/VFX
  assets that need to become a scalable, editable vector asset.

Both share the same underlying tracing engine and configuration editor, so
options behave identically wherever they appear. Added in **issue #376**
(raster↔vector engine) and **issue #377** (ProRes↔vector engine); surfaced
in the GUI in **issue #402** (Vector Conversion view) and **issue #404**
(ProRes to Vector view) as part of the #381 UI-gap closure.

> **Status:** both views are GUI-only today — there is no `meedya-convert`
> CLI subcommand for vector/image conversion yet (bulk image conversion is
> tracked separately as the future Phase 17). The settings you configure
> here persist across launches; they describe the exact tracing pipeline
> the engine will run.

---

## Vector Conversion (raster → SVG)

**Tools → Vector Conversion**

### Input formats

Any of the 30+ raster formats the engine recognises, grouped in the
picker as:

| Group | Formats |
| ----- | ------- |
| Common | BMP, JPEG, GIF, PNG, TIFF, WebP, AVIF, HEIC, HEIF |
| Modern | JPEG XL (JXL), JPEG 2000 (JP2), Animated PNG (APNG) |
| Professional | PSD, EXR, HDR, DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2, PEF |
| Legacy | TGA, PCX, ICO, DDS |
| Netpbm | PBM, PGM, PPM, PAM |

GIF, APNG, and WebP are treated as **animated** — selecting one of these
reveals the Animation section (see below).

Output is fixed at **SVG 2.0**.

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

### Animation (animated inputs only)

Shown only when the input format is animated (GIF/APNG/WebP):

| Method | Description |
| ------ | ----------- |
| SMIL (default) | SVG `<animate>` / `<animateTransform>` / `<animateMotion>` |
| CSS @keyframes | CSS `@keyframes` + `animation-delay` |
| Hybrid | SMIL path morphing combined with CSS timing |
| Static frame sequence | Exports per-frame PNGs + a frame list — no animation |

### Other options

- **Preserve EXIF / IPTC / XMP metadata** (default on) — copies source
  metadata into the SVG's `<metadata>` block.
- **OCR text regions** (default off) — detects text regions and emits them
  as SVG `<text>` elements instead of traced paths.
- **Curve simplification** (0.0–10.0, default 2.0) — tolerance for curve
  simplification; `0` preserves every point, `10` smooths aggressively.

---

## ProRes to Vector

**Tools → ProRes to Vector**

Converts an alpha-carrying ProRes clip into an animated SVG via:
`ProRes 4444 → per-frame PNG extraction (alpha preserved) → per-frame
tracing (same engine as Vector Conversion) → animated SVG assembly`.
Standard 4:2:2 ProRes variants have no alpha and aren't in scope here — use
the regular encoding pipeline for those.

### Source

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
| Preserve per-frame (clip-paths) (default) | Converts pre-multiplied → straight alpha, emitting per-frame clip-paths |
| Alpha matte only (monochrome) | Extracts the alpha matte as a monochrome animated SVG — useful for compositing workflows |
| Flatten against background | Composites against a background colour, dropping alpha |

### Tracing

Embeds the same Preset / Tracing / Alpha / Other sections documented above
under [Vector Conversion](#vector-conversion-raster--svg) — the per-frame
tracing settings can legitimately differ from your stand-alone Vector
Conversion preferences, since they're stored separately. The input format
for per-frame tracing is always PNG (the extracted frames), so there's no
separate Animation section here — that's controlled by the outer **Animation**
section below.

### Animation

The outer SVG's animation method — the same four options as Vector
Conversion's Animation section (SMIL, CSS @keyframes, Hybrid, Static frame
sequence), applied to the assembled multi-frame SVG rather than a single
traced image.

### Assembly

- **Shape persistence** (default on) — tracks shape identity across frames
  for consistent SVG element IDs (needed for clean CSS/SMIL animation of the
  same shape over time).
- **Keyframe extraction** (default on) — only re-traces frames with
  significant visual change, animating between keyframes rather than
  re-tracing every single frame.

### Output-size warning

A warning banner appears when your chosen frame rate, frame stride, and
time range would produce more than about ten seconds' worth of traced
frames, or whenever **Photorealistic** tracing is selected (which is
always heavy regardless of duration):

> **Output size may be large.** These settings can produce very large SVG
> files. Consider increasing the frame stride, narrowing the time range,
> or switching to a non-photorealistic tracing mode.

---

## Notes

- Both tools persist their settings per-view via `@AppStorage` (namespaced
  `vectorConversion.*` and `proresVector.*`), so your preferences survive
  app relaunches independently of each other.
- Tracing is performed by external tools (`potrace`, `vtracer`) selected
  automatically based on the tracing mode; SVG→raster rendering (for
  preview) uses `rsvg-convert`.

---

*See also: [cli-reference.md](cli-reference.md), [encoding-guide.md](encoding-guide.md).*
