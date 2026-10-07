<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Multi-source MP4 remux and preservation plan

Status: development requirements and findings from the 2026-10-06 Tangled remux workflow. This is a core MeedyaConverter use case: assemble selected versions of a film and selected audio tracks into one MP4, without re-encoding, while retaining timing, codec features, stereo interpretation and useful library metadata.

This document records observed behaviour and proposed acceptance criteria. It does not assert that these capabilities are implemented in MeedyaConverter. The initial two-video remux was completed and checked; the additional 4K and combined jobs were still in progress when these notes were drafted. Playback compatibility was not tested.

## Development context

Use `wip/alpha-consolidation` as the MeedyaConverter integration base, per the project's current working-branch instruction. The inspected snapshot was `185f0319e2918624b221201662e713cd65f08848`. The related MeedyaSuite-core work uses `feature/work-in-progress`. Older documentation referring to `main` or `alpha` does not supersede these working-branch instructions.

Keep reusable timing analysis, codec/container capability models, metadata representation and verification in shared engine/Core components where appropriate. MeedyaConverter provides track selection, preview, job planning and understandable results. Consult [the integration plan](MeedyaSuite-core-integration.md); verify actual bindings and live call sites before implementing against dormant preservation helpers.

## The workflow to support

The user selects particular streams from several MKV/MP4 sources, in an explicit output order. Sources may repeat in the selection list. A representative combined file contains three distinct 4K video versions, an MV-HEVC stereoscopic video, a side-by-side stereoscopic video, then the chosen source's complete audio collection. Subtitles are deliberately excluded for later muxing with Subler. Cover art and movie metadata are retained separately.

Treat this as track assembly, not concatenation of films end-to-end. Multiple video tracks are alternatives within one presentation; they may have different timestamps, durations and edits. Do not silently align, trim or stretch them just because they share a title.

Requirements:

- An ordered list of source/stream references, independent of the number of unique input files.
- Separate controls for video, audio, subtitles, chapters, artwork and attachments.
- Visible codec, language, title, default/forced dispositions, stereo layout, HDR/Dolby Vision details and timing for each track.
- Explicit metadata and chapter authority when sources disagree.
- A preservation report listing copied properties, translated properties, unsupported properties and intentional exclusions.
- Export the exact executable argument list, post-processing steps, tool versions and verification results.

FFmpeg stream indexes are zero-based. A GUI's “Video Stream ID 1” may mean the first video rather than the container's actual track ID. Resolve this using probing; never assume Matroska track numbers, MP4 track IDs and FFmpeg indexes are interchangeable. Chapter data and cover art can change apparent track numbering.

## Lossless has several dimensions

`-c copy` copies compressed media without re-encoding. It does not guarantee identical files, identical container metadata, unchanged effective playback timing or support by every player. Define and report these separately:

1. Encoded payload preservation, allowing necessary container framing transformations.
2. Codec configuration and feature preservation.
3. Presentation timing, sample trims and offsets.
4. Track/container metadata and stereo interpretation.
5. Target-player compatibility, tested independently.

Never silently transcode an unsupported selected stream. Offer an explicit alternative or stop with a concrete explanation. Preserve an archival source manifest for properties that cannot be represented in the target container; this does not substitute for functional playback signalling.

## TrueHD and other audio

The tested FFmpeg build (`N-127222-g151814650f-20261006`, libavformat 63.8) successfully copied Dolby TrueHD into MP4 using `-strict experimental`. The output used an `mlpa` sample entry. Treat this as a tested muxer capability, with compatibility restrictions, rather than inferring universal support from HandBrake or the MP4 filename.

The source collection also included E-AC-3, AC-3, DTS-HD, ALAC and AAC. Compare codec/profile, sample rate, channel count/layout, bit depth when available, language, titles and dispositions. Preserve Atmos/DTS extensions in their encoded payloads and relevant configuration; a codec name or channel count alone does not prove their survival. Do not create a lossy fallback track without user selection.

Capability checks should be specific to the installed tool build, chosen container and codec. A successful short mux is useful preflight evidence, but cannot guarantee that every packet in the full job will mux or decode.

## Timing: timestamps, leading skips, offsets and stretch

The completed 3D remux demonstrated that `-copyts` alone was insufficient. Packet timestamps survived, but some source leading-sample skips were not represented correctly by the output MP4 edit lists. AAC tracks needed 2,048 samples of leading trim; some AC-3/E-AC-3 tracks needed 256. These are observations from these files, not codec-wide constants.

One AAC track had a 24 ms source start offset, smaller than its approximately 42.667 ms leading trim at 48 kHz. Correct preservation required both an empty edit representing the delay and a media edit representing the skip. A single clamped start value lost information. Repairs changed the container edit lists, not audio samples. The repaired file matched the expected starts and sampled compressed audio payloads.

Model separately:

- PTS/DTS, time bases, initial timestamp and duration.
- Encoder priming, codec delay, skip-sample side data, discard padding and final trimming.
- MP4 movie/media time scales and complete edit-list sequences.
- User or source offset/stretch, including already-applied timestamp scaling.

Use rational arithmetic and explicit units. Account for negative timestamps, B-frame reordering, empty edits and differing time scales. Do not double-apply a stretch that the demuxed timestamps already express. Preserve source timing by default; an alignment operation must be separately selected and previewed.

For deliberate synchronization use the shared timeline model `T_reference = offset + scale * T_source`. Frame-rate differences can be evidence, but cannot determine scale alone. Use multiple content anchors and confidence, support manual anchors and piecewise mapping for cut differences, and include audio/subtitle-only inputs that have no meaningful video FPS. The previously discussed 1001/1000 stretch belongs to this explicit alignment model, not an automatic remux heuristic.

Acceptance must compare effective presentation timing as well as first-packet timestamps. Inspect start, middle and end, cumulative duration, leading skips and end padding. A matching first timestamp can conceal drift or a lost trim.

## Stereoscopic and multiview preservation

Distinguish image layout, codec multiview structure, container signalling and player interpretation.

Observed in the completed output:

| Track | Source interpretation | Output signalling observed |
| --- | --- | --- |
| VR/MV-HEVC | Matroska `block_lr`; ffprobe called it frame alternate; decoded codec views 0/1 identified left/right | No `st3d`; Apple `vexu/eyes/stri` value 3 present |
| Side-by-side | Packed side-by-side, left first | `st3d` mode 2, inverted 0; `vexu/eyes/stri` value 3 present |

Matroska's “both eye images packed in one block, left eye first” representation must not automatically be described as temporal frame alternation. The demuxer's Stereo3D label is not proof of the encoded layout. Inspect codec views and source metadata together.

FFmpeg warned that frame-alternate Stereo3D was unsupported for `st3d`. That warning did not mean all stereo information disappeared: the output contained `vexu`. The inspected `stri` value indicated left/right views present and no reversal. It does not, by itself, establish every codec-layer-to-eye association or complete Apple playback compatibility.

MOV is not a universal escape hatch for Matroska stereo modes. The tested MP4 already carried Apple stereo extensions. Preserve native signalling where supported, translate only when the semantics match, and retain original details in the source manifest. Never label MV-HEVC as side-by-side merely to obtain an `st3d` box.

Validate `st3d`, `vexu`, HEVC configuration and multiview dependencies directly in the container/bitstream. ffprobe alone can omit boxes or return an unspecified layout while view-presence metadata exists. Missing expected layered sample entries or dependency signalling requires investigation before claiming a target spatial-video profile. Test on actual target players/devices.

## HDR, Dolby Vision and codec configuration

The 4K inputs were HEVC Main 10, BT.2020 primaries, PQ transfer and BT.2020 non-constant matrix. Probing showed Dolby Vision profile 8, level 6, RPU present, enhancement layer absent, base layer present and compatibility ID 1. One input also exposed mastering display and content-light metadata. These are input observations; the ongoing jobs still require output verification.

Preserve and verify:

- HEVC parameter sets, profile/level, bit depth, resolution, aspect ratio and sample entry semantics.
- Dolby Vision configuration and RPU data; do not assume `hvc1` or `dvhe` naming alone proves correctness.
- HDR10+ dynamic metadata in the actual bitstream and static mastering/content-light metadata where present.
- Color range/primaries/transfer/matrix and frame cadence without forcing a new frame rate.

Container side data and bitstream SEI may carry different pieces of HDR information. Probe both where necessary. Normalize equivalent rational values when comparing mastering metadata; textual formatting differences are not necessarily loss. Avoid unnecessary bitstream filters or forced codec tags; record any required conversion and verify its semantics.

## Kodi XML, MP4 tags and artwork

The 3D source contained an XML attachment with movie metadata. MP4 does not preserve that attachment automatically through ordinary track mapping. The workflow extracted its original bytes, embedded them as custom metadata and also produced conventional movie tags.

Proposed metadata policy:

- Preserve the complete original UTF-8 XML byte sequence as an archival field, with SHA-256 and source provenance.
- Map supported title, sort/original title, date/year, genre, outline/description, plot, cast, directors, writers, producers, studio and external IDs to appropriate interoperable fields.
- Support conventional iTunes-style tags and `iTunMOVI` cast/crew plist, plus clearly named custom fields such as `kodi_xml`, `kodi_xml_sha256`, `imdb_id` and `tmdb_id`.
- Preserve unknown fields without inventing values. Track mapped, omitted and conflicting fields explicitly.
- Retain an option to export Kodi NFO sidecars. Embedding Kodi XML in a custom MP4 tag is archival preservation; it does not establish that Kodi will ingest it as an NFO or populate its library from it.
- Parse XML without external entity/network resolution; enforce size limits and preserve original bytes separately from normalized parsing.

The experiment found duplicate canonical tags when existing `mdta` fields and new iTunes fields overlapped: ffprobe reported `Tangled;Tangled`. Resolve namespaces and precedence deliberately. The local repair retained overlapping original values under `source_` keys and wrote one canonical conventional value. Production should use a structured metadata model with idempotent writes, rather than depend on a reader's concatenation rules.

`-movflags +use_metadata_tags` affected cover handling in this workflow: a mapped attached picture was not retained as expected. Cover art was then inserted as `covr`, retaining its compressed image bytes. Artwork is not an alternative playable video track; order/count verification should treat it separately. Test MIME type, image bytes, dimensions, multiple-cover policy and readback.

Global movie tags do not replace per-track titles/languages/dispositions. Preserve those independently. Choose one chapter source explicitly, retain chapter timestamps/titles and report chapter differences between editions. A chapter data track is not an unintended subtitle selection.

## Execution, caching and recovery

Reading three large inputs and writing the output concurrently on the same G: volume was slow. Byte-for-byte staging to a separate C: volume improved remux throughput in this session, but introduced substantial copy time and temporary storage. The full pipeline cost matters more than FFmpeg's instantaneous speed.

Plan I/O by physical device and available space, not merely drive letters. Bound concurrent jobs, estimate temporary plus output space, allow cancellation, and show staging/muxing/post-processing/verification as distinct stages. Do not describe FFmpeg's media timestamp progress as overall completion.

Validated intermediate outputs can avoid reading and remuxing the same streams again, provided source lineage, payload, timing and metadata are preserved. Cache identity should include source fingerprints, selection, tool build and preservation policy. Do not reuse an intermediate whose stereo or timing information was lost.

Write a temporary output and publish the final name after verification. Keep useful diagnostics on failure; never overwrite a source or existing completed file implicitly. Save actual argument arrays and escaped platform-specific command exports. A command export must include required metadata/timing post-processing, not just the FFmpeg step.

## Safe container updates

The session's small Python helpers edited a trailing `moov` box, with a backup and checks that media bytes and track atoms were unchanged for metadata insertion. This avoided copying tens of gigabytes just to add tags. It is a constrained experiment, not a general-purpose MP4 editor.

Production must validate the box tree, size widths, chunk offsets, track identities and edit-list time scales, and use a validated library or a transactional implementation. Never hardcode audio stream-to-track-ID arithmetic from one file. Fast-start files, fragmented MP4, extended-size boxes and non-trailing `moov` need explicit support or a safe rewrite path. Preserve recovery data and make repeated metadata writes idempotent. Timing repairs intentionally modify track edit lists, so their validation differs from a metadata-only invariant that all track boxes remain unchanged.

## Verification and completion criteria

Mux success is only the first gate. Produce a machine-readable report and an understandable summary:

1. Confirm selected track order and counts, exclusions, chapter source and artwork.
2. Compare codec/audio/video properties, tags and supported dispositions; report unsupported mappings.
3. Compare presentation timestamps, sample trims, offsets, duration and frame/sample counts where available.
4. Inspect stereo/HDR/Dolby Vision structures directly, and verify dynamic metadata where requested.
5. Compare encoded payloads using appropriate normalization for container framing. The completed 3D check matched the first eight audio packets across all 51 audio tracks; this is sampled evidence, not proof that every packet is identical.
6. Read back metadata independently: exact XML bytes/hash, canonical tags, complete cast/crew, IDs and artwork.
7. Test playback on selected targets. Distinguish muxable, structurally verified and player-tested states.

Use synthetic or licensed fixtures in the repository; do not commit the movie, its embedded artwork or private absolute source paths. Include delayed AAC with an offset smaller than priming, AC-3/E-AC-3 leading skips, existing MP4 edits, rational timestamp stretch, negative timestamps, multiple video alternatives, Matroska block stereo, SBS, MV-HEVC, HDR/DV, TrueHD, chapter data, covers and overlapping metadata namespaces. Include fragmented/fast-start refusal or safe-rewrite tests, cancellation and insufficient-space recovery.

## Suggested implementation sequence

1. Inventory and ordered assembly plan with complete source manifest and explicit preservation/alignment modes.
2. Build-specific capability checks and a command planner that never silently falls back to transcoding.
3. Shared timing representation and semantic verification, including priming/edit-list preservation.
4. Stereo/HDR/DV inspection and target-profile validation.
5. Structured metadata mapping, original XML/archive fields, artwork and chapter policy.
6. Transactional execution, reusable staging/cache, recovery and reproducible command exports.
7. Cross-container integration fixtures and target-player testing, followed by UI completion reporting.

## Primary technical references

- [FFmpeg documentation](https://ffmpeg.org/ffmpeg.html): stream selection, mapping, stream copy and timestamp options.
- [FFmpeg MOV/MP4 muxer documentation](https://ffmpeg.org/ffmpeg-formats.html#mov_002c-mp4_002c-ismv): muxer flags and metadata behaviour.
- [FFmpeg MOV muxer source](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/movenc.c): build-dependent TrueHD, stereo and metadata box writing; pin the source revision for reproducible investigations.
- [Matroska element specifications](https://www.matroska.org/technical/elements.html): track, stereo, timing and attachment semantics.
- [Kodi NFO documentation](https://kodi.wiki/view/NFO_files): library sidecar conventions; custom MP4 archival tags are a separate mechanism.

Re-check tool implementation and target-player behaviour when versions change. Preserve the distinction between observations from this workflow and requirements for future development.

