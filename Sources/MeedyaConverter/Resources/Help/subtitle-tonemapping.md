# 🎨 Subtitle Tone-Mapping

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Why tone-map subtitles?

When you convert an HDR master to SDR (HDR10 → Rec.709, Dolby Vision →
SDR, HLG → SDR), the **video** is tone-mapped but burned-in subtitles
typically are not. The result: PGS or ASS subtitles designed for
1000-nit HDR peak appear as washed-out grey on a 100-nit SDR display.

MeedyaConverter integrates [subtitle_tonemap](https://github.com/quietvoid/subtitle_tonemap)
— the same author as dovi_tool and hdr10plus_tool — to tone-map subtitle
colour values so they remain legible and correctly coloured after the
video's HDR→SDR conversion.

Added in **issue #369**.

## Supported formats

| Format | Ext. | Tone-mappable |
|--------|------|---------------|
| PGS (HDMV) | `.sup` | ✅ — PGS carries 8-bit indexed colour palettes |
| VobSub | `.sub` + `.idx` | ✅ |
| ASS / SSA | `.ass`, `.ssa` | ✅ — in-text colour tags tone-mapped |
| SubRip | `.srt` | ❌ — plain text, no colour |
| WebVTT | `.vtt` | ❌ — plain text |
| TTML | `.ttml` | ❌ — plain text |

## When to enable

- **Automatic**: When MeedyaConverter detects HDR source video + SDR
  output + subtitle burn-in requested, the tone-mapper is applied
  automatically using the detected HDR profile.
- **Manual**: For non-burn-in workflows (soft-subbed output where the
  subtitles and video remain separate streams), enable the toggle in
  **Output Settings → Subtitles → Tone-map for SDR target**.

## HDR source profiles

| Profile | CLI flag |
|---------|----------|
| HDR10 (PQ) | `--hdr10` |
| HDR10+ | `--hdr10plus` |
| Dolby Vision | `--dolby-vision` |
| HLG | `--hlg` |

The profile is detected from the source video's HDR metadata when
possible; override via the profile picker in subtitle settings.

## Target luminance

Default is 100 nits (standard SDR reference). Acceptable range:
50–203 nits. Higher targets preserve more dynamic range but may push
highlight subtitles above typical SDR display peak.

## Alpha handling

PGS subtitles carry full alpha per pixel. The "Preserve alpha" toggle
(default on) keeps semi-transparent regions during tone-mapping.
Disable only if your target player does not honour alpha on burned-in
subtitles.
