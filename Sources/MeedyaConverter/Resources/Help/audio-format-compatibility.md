# 🔊 Audio Format Conversion Compatibility

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overview

Not all audio formats can be converted to/from each other without limitations. This guide documents what conversions are possible, which lose information, and which are not meaningful.

> **What's actually implemented today vs. reference material.** This guide
> covers the whole spatial-audio format landscape, but MeedyaConverter's
> shipped audio path only covers **channel-based** conversion: re-encoding,
> channel remapping, algorithmic downmix, DSD→PCM decode via FFmpeg's
> `dsd_lsbf` decoder (PCM→DSD is not possible at all — FFmpeg has no DSD
> encoder, and `AudioCodec.ffmpegEncoder` returns `nil` for `.dsd`
> accordingly), and MQA unfold. Everything involving **object-based** formats (Atmos, MPEG-H,
> IAMF, …), **ambisonics** decode/encode/order-conversion, **binaural**
> rendering, **matrix encoding** embed/preserve/decode, and **virtual
> surround upmixing** is described below as general format-engineering
> reference — the engine type these sections were written against
> (`SpatialAudioConverter`, `MatrixEncodingPreserver`, `SurroundUpmixer`)
> has zero call sites anywhere in the app, and no view exposes any of this
> as a setting. Sections below repeat this caveat inline where the false
> "MeedyaConverter does X" framing was strongest, but treat every ⚠️/✅ cell
> that isn't plain channel-based re-encoding, remapping, or downmix the
> same way.

---

## Format Categories

Audio formats fall into distinct categories that determine conversion possibilities:

| Category | Description | Examples |
| -------- | ----------- | ------- |
| **Channel-based** | Audio assigned to fixed speaker positions | Stereo, 5.1, 7.1, 22.2 |
| **Object-based** | Audio as positioned objects in 3D space | Dolby Atmos, MPEG-H, 360 Reality Audio, Eclipsa/IAMF |
| **Scene-based (Ambisonics)** | Audio as a spherical sound field | FOA (4ch), HOA (9ch, 16ch, 25ch+) |
| **Matrix-encoded** | Surround info encoded in stereo phase | Dolby Pro Logic II, DTS Neo:6 |
| **Binaural** | 3D audio rendered for headphones (2ch) | Apple Spatial Audio, headphone renders |
| **1-bit (DSD)** | Delta-sigma modulation (not PCM) | DSD64, DSD128, DSD256, DSD512 |

---

## Conversion Compatibility Matrix

### Legend

- ✅ Full conversion (lossless or near-lossless)
- ⚠️ Conversion possible with limitations (see notes)
- ❌ Not possible or not meaningful

### Channel-Based ↔ Channel-Based

| From → To | Same Layout | Different Layout | Higher Count | Lower Count |
| --------- | ----------- | ---------------- | ------------ | ----------- |
| PCM, FLAC, ALAC, WAV | ✅ Lossless transcode | ✅ Channel remapping | ⚠️ Upmix (algorithmic) | ⚠️ Downmix (see matrix options) |
| AAC, MP3, Opus, Vorbis | ✅ Re-encode | ✅ Re-encode + remap | ⚠️ Upmix | ⚠️ Downmix |
| AC-3, E-AC-3, DTS | ✅ Re-encode | ✅ Re-encode + remap | ⚠️ Upmix | ⚠️ Downmix |

**Notes:**

- Downmixing from 5.1/7.1 to stereo can embed matrix encoding metadata (Pro Logic II, Dolby Surround) so AVR systems can unfold surround — see [Encoding Guide](encoding-guide.md)
- Upmixing (e.g., stereo → 5.1) is algorithmic and cannot recreate discrete surround content that was never there
- When downmixing, MeedyaConverter's audio channel analysis may detect that content is already effectively stereo in a surround container

### Object-Based → Other Formats

| From | To Channel-Based | To Other Object | To Ambisonics | To Binaural |
| ---- | ---------------- | --------------- | ------------- | ----------- |
| **Dolby Atmos** | ⚠️ Render to bed channels (loses objects) | ⚠️ Partial (format-specific metadata) | ⚠️ Render to HOA (loses precision) | ⚠️ Binaural render (headphone only) |
| **MPEG-H 3D** | ⚠️ Render to channels | ⚠️ Limited | ⚠️ Render to HOA | ⚠️ Binaural render |
| **360 Reality Audio** | ⚠️ Render to channels | ⚠️ Via MPEG-H | ⚠️ Render to HOA | ✅ Primary use case |
| **Eclipsa/IAMF** | ⚠️ Render to channels | ⚠️ Limited | ⚠️ Render to HOA | ⚠️ Binaural render |
| **ASAF** | ⚠️ Render to channels | ⚠️ Limited | ⚠️ Render to HOA | ⚠️ Binaural render |
| **Auro-3D** | ⚠️ Drop height channels | ⚠️ Limited | ⚠️ Encode to HOA | ⚠️ Binaural render |

**Key limitation:** Converting FROM object-based formats to channel-based requires **rendering** — the objects are positioned into fixed speaker channels. This is a lossy, irreversible process. The original object positions and metadata are lost.

### Channel-Based → Object-Based

| From | To Atmos | To MPEG-H | To IAMF | Notes |
| ---- | -------- | --------- | ------- | ----- |
| Any channel-based | ⚠️ Bed-only (no objects) | ⚠️ Channels as fixed positions | ⚠️ Channels as fixed positions | Cannot create objects from channels |

**Key limitation:** You cannot meaningfully create object-based audio from channel-based sources. The result is a "bed-only" mix with channels mapped to fixed positions — no dynamic objects.

### Ambisonics Conversions

| From | To Channel-Based | To Object-Based | To Other Ambisonics | To Binaural |
| ---- | ---------------- | --------------- | ------------------- | ----------- |
| **FOA (1st order, 4ch)** | ✅ Decode to any layout | ⚠️ Limited precision | ✅ Can upsample to HOA (limited) | ✅ Binaural decode |
| **HOA (higher order)** | ✅ Decode to any layout | ⚠️ Better precision than FOA | ✅ Order conversion | ✅ Binaural decode |

**Ambisonics is the most flexible spatial format for conversion** — it can be decoded to any speaker layout (stereo, 5.1, 7.1, 22.2, etc.) and rendered binaurally.

### DSD ↔ PCM

| From | To | Quality | Notes |
| ---- | -- | ------- | ----- |
| DSD → PCM | ✅ Decimation filter | High quality | Standard conversion; choose target sample rate (88.2/176.4/352.8 kHz recommended) |
| PCM → DSD | ❌ Not available | — | FFmpeg has no DSD encoder, and MeedyaConverter's codec model reflects that (`AudioCodec.ffmpegEncoder` returns `nil` for `.dsd`) — there is no encode path to offer here, technically-possible-but-controversial arguments aside |
| DSD → Lossy (AAC, MP3) | ⚠️ Via PCM intermediate | Acceptable | DSD → PCM → lossy encode |

### Matrix-Encoded Stereo

| From | To Discrete Surround | Notes |
| ---- | -------------------- | ----- |
| Dolby Surround / Pro Logic II | ⚠️ Decode to 5.1 | Requires compatible decoder; result is not identical to original discrete mix |
| DTS Neo:6 | ⚠️ Decode to 5.1/6.1 | Decoder-side process |
| Circle Surround | ⚠️ Decode to 5.1 | Requires SRS decoder |

**Key insight:** Matrix decoding recovers an approximation of the surround mix, not the original discrete channels. Quality depends on the matrix encoding method and decoder.

### MQA

| From | To | Notes |
| ---- | -- | ----- |
| MQA → PCM | ✅ Unfold/render | First unfold (16→24 bit) is software; full unfold needs MQA-compatible DAC |
| PCM → MQA | ❌ Proprietary encoder | MQA encoding requires Meridian license |
| MQA → Lossy | ⚠️ Via PCM | Loses MQA authentication chain |

---

## Immersive Format Interoperability Summary

| | Atmos | MPEG-H | 360RA | IAMF | ASAF | Ambisonics | Auro-3D | NHK 22.2 |
| - | ----- | ------ | ----- | ---- | ---- | ---------- | ------- | -------- |
| **Atmos** | — | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ Render |
| **MPEG-H** | ⚠️ | — | ✅ Base | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ Render |
| **360RA** | ⚠️ | ✅ Base | — | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ Render |
| **IAMF** | ⚠️ | ⚠️ | ⚠️ | — | ⚠️ | ⚠️ | ⚠️ | ⚠️ Render |
| **Ambisonics** | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ✅ Order conv | ⚠️ | ✅ Decode |

> ⚠️ = Conversion possible but loses spatial precision, object metadata, or requires rendering to an intermediate format. No object-to-object conversion is truly lossless across different proprietary ecosystems.

---

## Matrix Encoding Format Support by Output Codec

> **Not implemented.** `MatrixEncodingPreserver` exists in the engine but has
> zero references anywhere else — not even from `FFmpegArgumentBuilder`'s own
> downmix path — and no setting exposes it. The tables below describe what
> matrix encoding embedding *would* look like format-by-format if this
> shipped; treat them as reference material on the format landscape, not as
> a description of what MeedyaConverter currently does. Today, downmixing to
> stereo does not embed or preserve any matrix-encoding flag.

When downmixing to stereo, embedding matrix encoding metadata is possible in these output formats:

| Matrix Method | AC-3 | E-AC-3 | AAC | PCM/WAV | FLAC | ALAC | MP3 | Opus |
| ------------- | ---- | ------ | --- | ------- | ---- | ---- | --- | ---- |
| Dolby Surround | ✅ `dsurmod` | ✅ | ✅ `matrix_mixdown` | ⚠️ Container tag | ⚠️ Container tag | ⚠️ Container tag | ⚠️ Container tag | ❌ |
| Dolby Pro Logic II | ✅ `dsurmod` | ✅ | ✅ `matrix_mixdown` | ⚠️ Container tag | ⚠️ Container tag | ⚠️ Container tag | ⚠️ Container tag | ❌ |
| Dolby Digital EX | ✅ `dsurexmod` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| DTS ES Matrix | DTS only | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

> ⚠️ Container tag = matrix encoding applied to the audio signal, with the flag set at the container level (e.g., MKV/MP4 metadata) rather than in the codec bitstream. Not all players read container-level matrix flags.

---

## Matrix Encoding Preservation on Transcode

> **Not implemented** — see the note above. The table below shows what
> preservation would look like source-to-target if `MatrixEncodingPreserver`
> were wired up; no version of MeedyaConverter has shipped this yet, so
> there is no "Setting" to enable.

If this shipped, converting between formats that both support matrix
encoding would preserve the matrix metadata, so AVR systems could still
unfold surround from the transcoded output:

| Source Format | Source Flag | Target Format | Target Flag | Preserved? |
| ------------- | ---------- | ------------- | ----------- | ---------- |
| AC-3 | `dsurmod` (Pro Logic II) | AAC | `matrix_mixdown_idx` | ✅ Yes |
| AC-3 | `dsurmod` | FLAC | Container tag | ✅ Yes |
| AC-3 | `dsurexmod` (Digital EX) | AC-3 | `dsurexmod` | ✅ Yes |
| DTS | ES Matrix flag | DTS | ES Matrix flag | ✅ Yes |
| AAC | `matrix_mixdown_idx` | AC-3 | `dsurmod` | ✅ Yes |
| PCM (container tag) | Pro Logic II | AAC | `matrix_mixdown_idx` | ✅ Yes |

> Where the target format doesn't support the specific matrix flag at codec level, falling back to container-level metadata tagging would be the plan.

---

## MP3 Extensions

| Extension | Description | Compatibility |
| --------- | ----------- | ------------- |
| **MP3surround** | Fraunhofer MPEG Surround — adds 5.1 surround to standard MP3 via backward-compatible extension. Non-surround players decode stereo, surround-capable players unfold to 5.1 | Backward-compatible with standard MP3 players |
| **mp3PRO** | Thomson/Fraunhofer — adds SBR (Spectral Band Replication) for better quality at low bitrates. Similar technology to HE-AAC | Backward-compatible (SBR ignored by legacy decoders) |
| **mp3HD** | Fraunhofer — adds lossless extension to MP3. Legacy players decode lossy core, compatible players get lossless | Backward-compatible |

---

## IMAX Enhanced Audio

IMAX Enhanced uses **DTS:X IMAX** — a specific DTS:X profile with IMAX-tuned mastering and metadata.

> **Not implemented.** `AudioCodec` has an `imaxEnhanced` case purely as a
> display label ("IMAX Enhanced (DTS:X)") for a stream's reported codec —
> there is no bitstream inspection that detects the profile, no logic that
> preserves it specifically during passthrough, and no video-track
> IMAX-mastering detection anywhere in the engine.

---

## Virtual Surround Upmixing

> **Not implemented.** `SurroundUpmixer` builds the FFmpeg filter arguments
> described below but has zero callers anywhere else in the app, and no
> upmix control exists in any view. Everything from here to "Recommendations"
> below is a description of the upmixing landscape this module was written
> against, not a shipped MeedyaConverter feature — there is currently no way
> to upmix stereo/mono to multichannel surround from the app.

If this shipped, MeedyaConverter would algorithmically upmix stereo or mono audio to multichannel surround. Unlike matrix encoding (which embeds metadata for AVR decoding), this creates actual multichannel audio data — ensuring surround on any playback system, even those without built-in upmixing.

### Available Methods

| Method | Output | Quality | Best For |
| ------ | ------ | ------- | -------- |
| **FFmpeg Surround** (recommended) | 5.1 / 7.1 | Good | General-purpose; frequency-domain analysis separates stereo into directional components |
| **Pan Matrix** | Any layout | Basic | Simple duplication with attenuation coefficients |
| **Ambisonic Encode/Decode** | Any layout | Good | Flexible; encode stereo as positioned source, decode to target layout |
| **Haas Effect** | 5.1 / 7.1 | Good | Psychoacoustic spatial impression via delays and level differences |
| **Sofalizer (HRTF)** | Binaural 2ch | Excellent | 3D headphone rendering using SOFA HRTF files |

### Configurable Parameters

- Target layout (5.1, 7.1, custom)
- Upmix strength (subtle → aggressive)
- LFE crossover frequency (default 120Hz)
- Center channel extraction strength
- Surround delay (ms)
- Surround attenuation (dB)

### Matrix-Guided Surround Expansion

The design intent: when the source has matrix encoding metadata (Pro Logic II, DTS Neo:6, etc.), a "Matrix Decode" option would use the embedded surround information to create discrete multichannel audio, producing better results than blind algorithmic upmixing. None of this exists in the app today.

| Source Matrix | Decoded Output |
| ------------- | -------------- |
| Pro Logic II Cinema | Discrete 5.1 |
| Pro Logic II Music | 5.1 (adjustable center/surround blend) |
| Pro Logic IIx | 6.1 or 7.1 |
| Dolby Digital EX | 6.1 (rear center) |
| DTS ES Matrix | 6.1 |
| DTS Neo:6 Cinema/Music | 5.1 or 6.1 |

Decoded output would be encodable to native Dolby Digital 5.1, DTS 5.1, E-AC-3 7.1, etc. — again, describing intent, not a shipped option.

### Upmixed Output → Native Surround Codecs

Both virtual upmixing and matrix decode produce standard multichannel PCM, which can be encoded to:

| Channels | Available Codecs |
| -------- | ---------------- |
| 5.1 | Dolby Digital (AC-3), E-AC-3, DTS, AAC 5.1 |
| 6.1 | Dolby Digital EX, DTS ES |
| 7.1 | E-AC-3, DTS-HD, AAC 7.1 |

### Design Notes (Not Yet Built)

- **Upmixing would not be auto-enabled** — opt-in per audio track only
- **Mono sources** — upmix options would be hidden/disabled (no stereo image to analyse)
- **Matrix decode vs blind upmix** — matrix decode would be preferred when metadata exists

### When to Use Which Method

| Scenario | Use |
| -------- | --- |
| Source has Pro Logic II / DTS Neo:6 metadata | Matrix Decode (best quality) |
| Plain stereo, playback system has no upmixer | Virtual Upmix |
| Plain stereo, playback system has DTS Neural:X / Dolby Surround | Embed matrix metadata only (let the AVR upmix) |
| Encoding for streaming (unknown device) | Both: upmixed 5.1 track + stereo with matrix metadata |
| Headphone listening | Sofalizer binaural rendering |
| Mono source | No upmix available — channel routing only |

---

## Recommendations

| Scenario | Recommended Approach |
| -------- | -------------------- |
| Archive original quality | Passthrough or lossless (FLAC/ALAC/PCM) |
| Streaming delivery | AAC (stereo/5.1) or Opus (stereo) |
| Atmos content for streaming | Passthrough only — encoding *new* E-AC-3 JOC (Atmos) requires Dolby's proprietary tools, which FFmpeg does not provide; see [Encoding Guide](encoding-guide.md) |
| Disc authoring (DVD) | AC-3 5.1 or DTS |
| Disc authoring (Blu-ray) | DTS-HD MA, TrueHD, or LPCM |
| Downmix for maximum compatibility | Plain stereo — matrix-metadata embedding (Pro Logic II) is not implemented; see "Matrix Encoding Format Support" above |

---

*This guide is updated as new format support is added. See [Supported Formats](https://github.com/MWBMPartners/MeedyaConverter/wiki/Supported-Formats) for the complete codec list.*
