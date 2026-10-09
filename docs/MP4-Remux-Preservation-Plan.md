<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Multi-source MP4 remux and preservation plan

Status: generic development requirements and technical findings, updated 2026-10-09. This is a core MeedyaConverter use case: assemble selected versions of a film and selected audio tracks into one MP4, without re-encoding, while retaining timing, codec features, stereo interpretation and useful library metadata. Subler-style tagging and track relationship editing are part of the intended planning scope.

This document records observed tool behaviour and proposed acceptance criteria without identifying any converted media, filenames or source locations. It does not assert that these capabilities are implemented in MeedyaConverter. Successful structural and sampled checks are distinguished from unresolved findings. Playback compatibility, full-file payload equality and exhaustive HDR10+ validation require additional testing.

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

Observed signalling patterns, suitable for synthetic regression fixtures:

| Track | Source interpretation | Output signalling observed |
| --- | --- | --- |
| VR/MV-HEVC | Matroska `block_lr`; ffprobe called it frame alternate; decoded codec views 0/1 identified left/right | No `st3d`; Apple `vexu/eyes/stri` value 3 present |
| Side-by-side | Packed side-by-side, left first | `st3d` mode 2, inverted 0; `vexu/eyes/stri` value 3 present |

Matroska's “both eye images packed in one block, left eye first” representation must not automatically be described as temporal frame alternation. The demuxer's Stereo3D label is not proof of the encoded layout. Inspect codec views and source metadata together.

FFmpeg warned that frame-alternate Stereo3D was unsupported for `st3d`. That warning did not mean all stereo information disappeared: the output contained `vexu`. The inspected `stri` value indicated left/right views present and no reversal. It does not, by itself, establish every codec-layer-to-eye association or complete Apple playback compatibility.

MOV is not a universal escape hatch for Matroska stereo modes. The tested MP4 already carried Apple stereo extensions. Preserve native signalling where supported, translate only when the semantics match, and retain original details in the source manifest. Never label MV-HEVC as side-by-side merely to obtain an `st3d` box.

Validate `st3d`, `vexu`, HEVC configuration and multiview dependencies directly in the container/bitstream. ffprobe alone can omit boxes or return an unspecified layout while view-presence metadata exists. Missing expected layered sample entries or dependency signalling requires investigation before claiming a target spatial-video profile. Test on actual target players/devices.

## HDR, Dolby Vision and codec configuration

The 4K inputs were HEVC Main 10, BT.2020 primaries, PQ transfer and BT.2020 non-constant matrix. Probing showed Dolby Vision profile 8, level 6, RPU present, enhancement layer absent, base layer present and compatibility ID 1. One input also exposed mastering display and content-light metadata. The completed 4K merge matched the compared stream properties and sampled compressed packets. This does not establish exhaustive preservation of dynamic metadata throughout every frame.

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

The experiment found duplicate canonical tags when existing `mdta` fields and new iTunes fields overlapped: ffprobe reported `Example Title;Example Title`. Resolve namespaces and precedence deliberately. The local repair retained overlapping original values under `source_` keys and wrote one canonical conventional value. Production should use a structured metadata model with idempotent writes, rather than depend on a reader's concatenation rules.

`-movflags +use_metadata_tags` affected cover handling in this workflow: a mapped attached picture was not retained as expected. Cover art was then inserted as `covr`, retaining its compressed image bytes. Artwork is not an alternative playable video track; order/count verification should treat it separately. Test MIME type, image bytes, dimensions, multiple-cover policy and readback.

Global movie tags do not replace per-track titles/languages/dispositions. Preserve those independently. Choose one chapter source explicitly, retain chapter timestamps/titles and report chapter differences between editions. A chapter data track is not an unintended subtitle selection.

## Execution, caching and recovery

Reading several large inputs and writing an output concurrently on the same storage volume can be slow. Byte-for-byte staging to a separate device can improve remux throughput, but introduces copy time and temporary storage. The full pipeline cost matters more than FFmpeg's instantaneous speed.

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
5. Structured metadata mapping, original XML/archive fields, artwork and chapter policy; native track relationships and alternate-group editing.
6. Transactional execution, reusable staging/cache, recovery and reproducible command exports.
7. Cross-container integration fixtures and target-player testing, followed by UI completion reporting.

## Primary technical references

- [FFmpeg documentation](https://ffmpeg.org/ffmpeg.html): stream selection, mapping, stream copy and timestamp options.
- [FFmpeg MOV/MP4 muxer documentation](https://ffmpeg.org/ffmpeg-formats.html#mov_002c-mp4_002c-ismv): muxer flags and metadata behaviour.
- [FFmpeg MOV muxer source](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/movenc.c): build-dependent TrueHD, stereo and metadata box writing; pin the source revision for reproducible investigations.
- [Matroska element specifications](https://www.matroska.org/technical/elements.html): track, stereo, timing and attachment semantics.
- [Kodi NFO documentation](https://kodi.wiki/view/NFO_files): library sidecar conventions; custom MP4 archival tags are a separate mechanism.

Re-check tool implementation and target-player behaviour when versions change. Preserve the distinction between observations from this workflow and requirements for future development.

## Generic evidence classes and verification limits

The technical observations should be reproduced with synthetic fixtures. They are not a claim that any particular user file has passed comprehensive verification.

| Scenario | Observed behaviour | Development implication |
| --- | --- | --- |
| Multi-video stereo assembly | Source offsets and leading audio skips required edit-list repairs; native stereo boxes could differ by layout | Validate timing semantics and actual stereo boxes separately from payload copying |
| Multiple 4K alternatives | Compared properties/configuration and sampled video/audio payloads could be retained | Extend checks to dynamic HDR data across the full timeline and real target players |
| Remux through a previously repaired intermediate | Another mux could lose leading trims; one source packet count could differ | Revalidate every pipeline edge; an intermediate's prior verification is not transferable proof |
| Native multitrack MKV to MP4 | Compared properties, declared counts, metadata and sampled packets could pass with disclosed native flag limitations | Native retention and archival preservation need separate statuses |
| Single-video MKV with timed-text conversion | Full mux could fail at trailer despite reaching the end; a header/timing repair enabled a validated retry | Preflight serialization, own process exit status, and distinguish subtitle conversion from stream copy |
| SBS video | `st3d` mode 2 plus Apple `vexu/eyes/stri` value 3 could be written | Inspect both families of boxes and keep left/right semantics explicit |
| Multiview/VR video | Apple `vexu/eyes/stri` value 3 could exist without `st3d` | Absence of one signalling family is not proof of absent stereo; test codec views and device compatibility |

Successful sampled checks do not resolve an earlier unresolved output, prove full-file equality or establish playback compatibility. Persist every output's own evidence and current failure/limitation state.

Metadata finalization can retain all JPEG/PNG attachment entries, including multiple covers, and embed source manifests globally and per track. Use each source's exact XML when present. If a source lacks XML, inherited metadata from an explicitly selected authority must be identified by provenance; it must not be presented as that source's attachment.

Do not commit movie media, embedded artwork, unredacted source manifests or private paths. Use synthetic fixture descriptions and sanitized diagnostic samples.

## Native flags, track properties and archival values

The user specifically requested forced, original and other track flags. An argument such as `-disposition original` is not proof that the target container wrote a corresponding flag.

For FFmpeg revision `151814650f`, the MP4 track-kind mapping in `libavformat/isom.c` includes hearing-impaired/captions, commentary, visual-impaired/descriptions, dub and forced-subtitle roles. It has no mapping for `original`. The session archived the complete original disposition dictionary, tags and side data in each track's metadata and a global source manifest, then checked supported native roles separately.

MP4 track enabled state and Matroska default-track preference are different semantics. With no source video marked default, this muxer enabled the first MP4 video; ffprobe exposed that as default. This difference was reported. Do not disable every video merely to make a boolean comparison pass, or equate an archived flag with a player-enforced flag.

Requirements:

- Represent original/default/forced/enabled/dub/commentary/accessibility properties separately, with native format semantics.
- Model language and extended BCP-47 language, names and alternate groups independently of movie tags.
- Keep original stream IDs, Matroska TrackUIDs, source time bases and unknown properties in the manifest, while assigning valid new MP4 track IDs.
- Display each property's status: natively retained, semantically translated, archived only, changed by selected policy or unsupported/unretained.
- Compare track title to MP4's `name`/handler representation as appropriate; a missing `title` key in ffprobe is not necessarily a missing track name.
- Reject impossible promises to retain every cross-container property literally. Present concrete losses/translation choices before execution.

The chosen manifest uses a distinct preservation namespace (`com.meedya.preservation`), separate from conventional iTunes metadata. Define and version its schema; include tool versions, source authority, selected tracks, repair decisions and hashes. Track-level preservation metadata must remain associated with the correct track after reorder/delete/import.

## Subtitles and the Subler handoff

Subtitle selection is per job: exclude all, retain supported formats directly, or explicitly convert selected tracks. Sources can contain many SubRip and PGS tracks, or only a single English SDH SubRip track. Conversion to MP4 `mov_text` must be explicitly selected while unrelated video/audio remains stream-copied.

SubRip is not directly stream-copyable into this MP4 muxer. Timed-text conversion must preserve cue text, timing, language and supported formatting/accessibility roles, with an explicit report of unsupported styling. TX3G/`mov_text` and WebVTT are distinct choices with different target-player support. Bitmap PGS/VobSub handling must state whether the backend supports muxing, requires OCR or cannot represent the stream; OCR is not lossless. Burn-in changes video and must never be an implicit fallback.

Timed text can contain empty gap samples, so MP4 sample counts need not equal source subtitle cue counts. Verify semantic cues rather than requiring identical packet counts across a conversion. Do not count a chapter text/data track as an accidentally retained subtitle.

Support adding subtitles to an already prepared MP4 without rebuilding unrelated video/audio unnecessarily. Preserve existing stereo/HDR/configuration boxes, edit lists, artwork, custom metadata and track-reference relationships during this later operation. Define an Apple/Subler handoff profile and round-trip tests; the session did not perform an actual Subler round trip.

## Subler-style fallback and track relationship editing

The user wants one integrated tool that performs the tagging, muxing and track-management work currently split between Windows CLI tools and Subler on macOS. Subler has no official Windows version. The reviewed Windows alternatives cover subsets: MetaX movie tagging, Mp3tag broad tag fields, MP4Forge muxing/track properties, and GPAC/MP4Box lower-level box/track operations. Their documentation did not establish complete GUI parity with Subler, particularly for fallback relationships and this workflow's TrueHD/multiview/custom-metadata combination. Treat this as a product requirement, not a blanket claim that every alternative lacks every related feature.

An audio fallback is a relationship to equivalent content in a more compatible format. Merely including TrueHD, E-AC-3, AAC or stereo tracks does not create that relationship. The outputs in this session did not explicitly configure Apple audio-fallback links.

Plan explicit first-class models and UI for:

- Audio fallback relationships, including the applicable `tref/fall` reference, verified against target documentation and parser behaviour.
- Alternate-group membership and enabled/default selection, separately from fallback.
- Audio-to-subtitle selection followers (`folw`), forced-subtitle associations (`forc` where applicable), chapter references and other supported track relationships.
- Language, edition, commentary/accessibility identity and content equivalence when choosing a fallback. The same language alone is insufficient to establish equivalence.
- Existing compatible tracks as fallback candidates; generating a new AAC/stereo fallback only under an explicit conversion choice.
- Preservation/remapping of references after track ID changes, reordering, replacement, import and removal.

Validate reference direction, type, target existence, media/content compatibility and documented constraints. Detect self-references, dangling targets and unsupported cycles. Do not assume every player follows Apple references or that a valid reference makes TrueHD playable. Display native relationship readback and target-player test status separately.

Apple's alternate-group guidance requires same-type group members and describes enabled-track selection. Implement this as a target profile, not an unqualified rule for every MP4 consumer. A fallback track should share the intended content timeline, including priming/trims/offsets; a structurally valid reference to misaligned audio is still a defective output.

GPAC documents generic `-ref`, grouping, enabled state, language, edit-list, tag and `vexu` operations. Investigate it as an engine capability alongside FFmpeg and metadata libraries, using pinned versions and preservation tests. A GUI wrapper need not expose every capability of its underlying tool. No tool should rewrite unfamiliar boxes without reporting the preservation outcome.

### Relationship direction and identity model

Use logical track identities in the job plan and resolve them to actual output track IDs only after the final selection/order is established. File-global tag strings are not a substitute for native track references.

| Logical source | Logical target | Native relationship | Intended meaning |
| --- | --- | --- | --- |
| Primary audio | Equivalent compatible audio | `tref/fall` where supported by the target profile | Use equivalent content in a supported format when the primary format is unavailable |
| Selected audio | Preferred subtitle track | `tref/folw` | Follow audio selection with the appropriate subtitle selection |
| Full/mixed subtitle track | Paired forced-only subtitle track | `tref/forc` | Identify the associated forced-only subset |
| Referencing media track | Chapter text track | `tref/chap` | Associate chapter information |

Confirm each backend's reference direction and target restrictions by writing and independently reading a synthetic fixture. In particular, `forc` is a relationship between subtitle tracks; it is distinct from an all-samples-forced display flag or individual forced-sample markers such as `frcd`. Apple's guidance also describes directing `folw` to a forced-only member when a subtitle pair is the preferred choice. [Forced-subtitle pairing](https://developer.apple.com/documentation/quicktime-file-format/referencing_a_related_forced_subtitle_track)

A proposed engine model contains `TrackNode` (logical ID, source identity, kind, language, content/edition identity and timeline), `RelationshipEdge` (type, source/target logical IDs, native representation, provenance and validation status), and `AlternateGroup` (same-purpose members, target-profile selection policy and enabled state). An audio conversion records its content derivation and alignment before it becomes an eligible fallback.

Apply ID mapping transactionally when writing. If a referenced track is removed, the user must choose a replacement or remove the relationship; never leave a dangling native reference. Reordering must not change relationship meaning. Preserve unknown references/boxes when their meaning and ID mapping can safely be retained; otherwise disclose the unresolved mapping instead of copying opaque bytes with stale IDs. Import relationships from existing MP4/MOV as well as creating new ones; archive their original representation in cross-container exports that cannot express them.

Acceptance includes a simulated unsupported-primary codec, same-language tracks from different editions, offset/priming mismatches, an explicitly created stereo fallback, mixed/full plus forced-only subtitle pairs, track deletion/replacement, changed track IDs and unknown references. Structural tests should read the native box graph independently; behavioural tests should verify actual target-player selection. Compatibility is a profile-specific result, not a consequence of merely writing `fall`.

## Trailer failure caused by incompatible codec-private wrappers

A full remux reached the end of media and then failed with `Error writing trailer: Invalid data found when processing input`. ffprobe could not read the resulting MP4 header (`invalid size 0 in stsd`). A four-second remux reproduced the failure, which should have been caught before the large job.

Inspection found two format-wrapper issues:

1. The TrueHD track used Matroska `A_QUICKTIME` with a 74-byte `mlpa` MP4 sample-entry wrapper in CodecPrivate. The MP4 muxer's TrueHD writer expected configuration derived from TrueHD access-unit/major-sync data, not that wrapper.
2. The ALAC CodecPrivate was 44 bytes: a valid 24-byte ALAC configuration plus a trailing 20-byte `btrt` box. The demuxer wrapped this into a 56-byte `alac` atom, rather than the normal 36-byte configuration atom.

A temporary copy was normalized: the TrueHD identifier became `A_TRUEHD`, the incompatible wrapper was removed, and its configuration was rebuilt from encoded data; ALAC retained its valid 24-byte configuration and removed the trailing wrapper box. This changed container headers, not the compressed audio. The original MKV remained untouched.

The experiment replaced shortened/removed EBML fields with same-total-length Void elements so existing offsets remained valid. That shortcut must not become a general repair algorithm. Production should use a validated Matroska parser/writer, handle variable-length sizes and unknown-size segments, recalculate affected CRCs when present, and verify seeking/cues and decoded configuration. Repairs must be codec-specific and evidence-based; never strip arbitrary extradata that might contain required Dolby/codec information.

After normalization, the short MP4 had a readable trailer and the expected TrueHD, ALAC and timed-text tracks. Other MKVs in this session already had native TrueHD and valid 24-byte ALAC private data, so the repair was not applied to them.

## ALAC lacing, timing reconstruction and first-packet loss

A normalized source still produced non-monotonic ALAC DTS warnings. Groups of laced packets lacked distinct demuxed timestamps. Decoding packet samples showed 4,096 samples per normal packet at 48 kHz and 1,912 samples in the final packet. The source declared 70,518 packets and a 43 ms start offset. These are fixture values, not ALAC-wide constants.

The retry assigned packet timestamps from cumulative encoded sample counts, retained the 2,064-sample initial offset, and used the shorter final duration. A `setts` bitstream filter changed timestamps/durations without re-encoding the ALAC payload. The short test had no non-monotonic DTS warnings; sampled payload hashes matched. The full retry then passed the implemented property/count/sample checks.

A separate remux through an intermediate had one fewer ALAC packet than its input. The refreshed jobs used `-copyinkf`, and their checked source-declared counts matched. Investigate first-packet/key-marking behaviour rather than assuming a missing packet is harmless. A later successful remux does not retroactively resolve an earlier packet-count discrepancy.

Development requirements:

- Detect repeated/non-monotonic DTS and distinguish timestamp quantization, lacing gaps, discontinuities and actual content edits.
- Obtain per-packet sample counts from validated codec parsing/decoding or trustworthy sample tables; handle variable-size final and intermediate packets.
- Preserve the initial offset and explicit stretch/discontinuity policy; sample-cadence reconstruction must not erase an intentional timing transform.
- Verify start, cumulative samples, last packet, effective end and packet counts before accepting a repair.
- Bound repair to the affected track; archive the exact original timing and repair expression.
- Never hardcode this session's frame length, last duration, packet count or stream index into production.

## Metadata, attachment and HDR details added by the later jobs

Sources can contain several covers, in mixed JPEG/PNG formats. Duplicate image content may be intentional and was not silently deduplicated. Preserve ordering, MIME type, source attachment ID/name, description and image bytes, and expose a user-selectable artwork policy. An XML attachment is migrated into metadata, not copied as an unsupported playable track. Retain raw unsupported attachments in an explicit archive/sidecar only under a selected policy.

In this session, FFmpeg image extraction wrote a cover file but continued scanning media rather than terminating as expected with the selected frame limit. MKVToolNix attachment extraction accessed the resources directly and avoided that unnecessary work. Use attachment-aware extraction rather than treating every attached image as an ordinary timed video stream.

The XML supplied complete cast entries, whereas some source movie tags contained truncated cast text. Prefer the explicitly selected authoritative complete metadata, retain conflicting originals in provenance, and never treat an ellipsis as a full cast list. Field-level source authority matters: original XML, source MP4 `iTunMOVI`, a lookup provider and user edits may carry complementary or conflicting values.

Support raw and interpreted creation timestamps, encoder/writing-application tags, track statistics, original identifiers and unknown fields. Some container-generated properties necessarily change during remuxing; archive originals and identify newly generated values rather than pretending they are identical. Statistic tags can be stale and are evidence to corroborate against actual sample tables, not an unconditional source of truth.

MP4 mastering-display fields have finite quantization. Later checks allowed their representational precision (coordinates at 1/50,000 and luminance at 1/10,000 where applicable), instead of rejecting every non-identical rational string. Preserve exact source values in provenance while comparing native values within the relevant field's encoding precision. Specify thresholds per field; do not hide substantial HDR changes behind a generic tolerance.

### Kodi-preserving metadata pipeline

Support Kodi NFO sidecars and MKV XML attachments as explicit metadata sources, alongside existing MP4 fields, lookup providers and manual edits. Keep raw-source preservation and normalized interoperability as parallel outputs. [Kodi movie NFO fields](https://kodi.wiki/view/NFO_files/Movies)

1. **Inventory and capture:** identify the selected metadata authority, XML root/schema context, declared encoding and original bytes. Capture attachment/sidecar identity and a checksum before parsing. Preserve existing MP4 namespaces and per-track metadata separately.
2. **Parse safely:** disable external entity/network resolution, bound document size/depth, preserve repeated elements, namespaces, attributes and unknown nodes. Do not silently discard a provider's IDs, rating scales/defaults or nested cast data.
3. **Normalize with provenance:** use typed values and ordered arrays for titles, plot/outline/tagline, release dates, genres, countries, studios, directors/writers/producers, cast names/roles/order/thumbnails, provider-specific unique IDs, ratings/votes, sets/collections, tags, editions, artwork and trailers. Record the source and user override for every canonical field. Retain Kodi user-state fields such as play count, last played, user rating and resume separately from descriptive movie metadata, with an explicit export policy.
4. **Write interoperable fields:** map supported values to conventional MP4/iTunes tags, `iTunMOVI` cast/crew plist and artwork, or suitable Matroska tags for that target. Track names/roles/languages belong at track level. Keep unavailable cast roles, alternate IDs, collections and other rich Kodi fields in the preservation model rather than flattening them destructively into one comma-separated string.
5. **Archive the raw XML:** embed the original bytes under a versioned, documented custom namespace together with encoding, format, checksum and source authority. UTF-8 text may be a text field; other encodings/binary resources need an explicitly typed binary or base64 representation with enough information for byte-exact reconstruction. Do not normalize whitespace, CRLF, ordering or an XML declaration in the original archival copy. Keep normalized XML, if generated, as a distinct artifact.
6. **Optionally export NFO:** generate a valid target-version Kodi NFO from the normalized model, or restore the original bytes under the selected round-trip policy. Follow Kodi's file naming/schema expectations. Custom embedded XML does not imply Kodi will read it from MP4. Native movie tags, embedded archival XML and an actual Kodi-consumed NFO are three different deliverables.
7. **Read back and report:** verify raw bytes/checksum, canonical values, provider-ID namespaces/default selection, full cast/crew ordering, cover bytes and native track metadata. Classify each field as mapped, archived, inherited, excluded or unsupported. A second write with unchanged inputs must not create duplicate tags, covers or metadata groups.

Preserve `<uniqueid>` provider types and default attributes rather than collapsing all IDs into an ambiguous `id`. Empty, absent and explicitly cleared fields require distinct merge semantics. When metadata changes, update the normalized source-of-truth and selected exported representations consistently; retain the immutable original snapshot and record changes instead of overwriting historical evidence.

Define import/export profiles for movie versus episodic metadata, including season/episode/show fields and appropriate NFO root elements. Validate the specific profile against the chosen Kodi version; do not copy movie fields mechanically into an episode document. Do not infer film/edition identity or relationships solely from filenames or matching titles.

Treat metadata and relationship editing as transactional operations on the same preservation model. A tag-only edit must leave audio/video configuration, stereo/HDR boxes, sample tables, edit lists, unknown metadata and native relationships intact. A track mutation must remap relationships and remove/update track-specific archived manifests appropriately. Test both directions: later subtitle insertion preserves movie XML/tags and native references, and later tagging preserves the subtitle/fallback graph.

## Job lifecycle and command-export lessons

The logs demonstrated that FFmpeg can emit `progress=end` after a failing trailer write. A completion detector based only on that string was insufficient. The engine must own the child process, obtain its exit status, validate the finalized container, finish metadata work, then run required verification. Only then may it show completed/verified or publish the final output name.

Use explicit job states: inventory, awaiting required choice, preflight, staging/normalization, muxing, finalizing, verifying, completed, failed, cancelled and completed-with-declared-limitations. Persist a job manifest and recoverable state across app restarts; a background process existing independently of the chat/UI is not a complete monitoring design. Stage progress, throughput and ETA must reflect the remaining pipeline; a 101-minute timestamp at 1x does not include copying or verification time.

Keep each queued job's failure state independent and define whether the queue continues after a failed item. Capture the actual exception and last useful tool diagnostics. Retries must preserve prior failed output separately, regenerate commands/provenance, and require successful preflight for the diagnosed failure. Do not silently convert or drop the troublesome codec to make a retry finish.

The CLI argument list grew large enough that embedding the complete source manifest as a command-line argument failed on Windows. Write bulky metadata through a file/API or post-processing stage, with explicit limits, rather than relying on shell/OS command-length limits. Pass argument arrays to child processes; export properly escaped PowerShell and POSIX commands for humans. Metadata containing apostrophes, Unicode, dollar signs or newlines must remain data, not executable shell text.

Python's platform-default encoding failed on Unicode JSON in this workflow. Use explicit UTF-8 for saved plans/reports and UTF-8-with-BOM-aware reading when importing PowerShell-produced files. Require reproducible commands to include staging/header normalization, timestamp filters, metadata insertion and verification, not just the final FFmpeg invocation.

Validate output paths before execution: escaped punctuation can make a filename look like a directory plus a hidden file. A matching source filename may exist in a nearby directory rather than the supplied location; source substitution must be disclosed and the requested output destination respected. Production should present candidate resolution explicitly when source identity is ambiguous and never silently pick a different edition. Preserve sources and existing completed files by default.

## Planning coverage and acceptance backlog

This matrix converts the complete discussion into development work. Existing code must be audited against these requirements; this document is not evidence that any row is already implemented.

| Area | Required behaviour | Minimum acceptance evidence |
| --- | --- | --- |
| Ordered multi-source assembly | Repeated sources, exact selected track order, independent movie/track metadata authority | Five-video plus 51-audio synthetic assembly; IDs and lineage remain correct |
| Stream-copy policy | Explicit copy/convert/exclude decision per stream; TrueHD and codec extensions retained where muxable | Build-specific codec matrix; no silent audio/video transcode or dropped stream |
| Header validation | Detect incompatible sample-entry wrappers and malformed private data before a large mux | Short fixture reproduces trailer failure; constrained repair passes and original source hash stays unchanged |
| Timing preservation | Priming, trims, offsets, rational stretch, edit sequences and end padding | Delayed AAC below priming; 256-sample skips; negative PTS; differing movie/media scales; original MP4 edits |
| Timestamp repair | Track-specific, justified reconstruction with variable sample counts and original offset | Laced ALAC fixture with repeated PTS, shorter last packet and declared stretch/discontinuity cases |
| Stereo/multiview | Correct source interpretation and native box/codec validation | SBS left/right ordering, `st3d=2`, `vexu/stri`, Matroska block stereo and actual multiview layer/view associations |
| HDR/Dolby Vision | Native configuration, static fields and dynamic payload validation | Profile 8 RPU case, static quantization, HDR10+ samples across the timeline, unsupported-profile reporting |
| Native flags and archival metadata | Semantically accurate roles/default/enabled state, complete unknown-property provenance | Native round trip plus archived `original`; no false native-preserved status |
| Subtitles | Explicit exclusion or authorized timed-text conversion and later MP4 insertion | SDH/forced, cue timings/text/styles, empty gap samples, bitmap/OCR distinction |
| Subler-style relationships | Fallback, alternates, followers, forced-subtitle and chapter relationships | Valid/remapped references, dangling/self/cyclic rejection as appropriate, equivalent synchronized content and player tests |
| Movie tagging | Comprehensive iTunes/custom metadata, authority/conflict resolution, raw Kodi XML | Complete cast/crew, IDs, exact XML hash, namespace collision and idempotent update tests |
| Artwork/attachments | Multiple JPEG/PNG entries, direct extraction, explicit unsupported-attachment policy | Byte hashes, MIME/dimensions/order, duplicate art, source IDs/names and no unnecessary full-media scan |
| Container editing | Transactional updates and preservation of unfamiliar boxes/references | Trailing/fast-start/fragmented/extended-size cases, offsets/CRC checks, rollback and no unintended media changes |
| Execution and recovery | Resource-aware queue, staging/cache, process-owned completion and useful retries | Exit failure despite `progress=end`, trailer failure, cancellation, disk pressure, restart and independent job failure |
| Verification/reporting | Separate sampled, exhaustive, semantic and player-tested evidence | Track/frame/sample counts, head/middle/tail checks, full-payload option and explicit limitations |
| Cross-platform experience | Integrated Windows/macOS workflow with transparent backend capabilities | Unicode/long-command cases, source/output ambiguity, equivalent metadata/relationship readback and Subler interoperability |

Prioritize the preservation model and verification gates before broadening the GUI. Add a track-relationship editor alongside tagging and assembly, backed by the shared timeline model. Create implementation issues with these acceptance criteria when scheduling work; do not substitute a long documentation list for an actionable backlog or claim that roadmap coverage implies delivery.

## Additional primary references

- [FFmpeg pinned MP4 role mapping](https://github.com/FFmpeg/FFmpeg/blob/151814650f/libavformat/isom.c) and [MOV/MP4 writer](https://github.com/FFmpeg/FFmpeg/blob/151814650f/libavformat/movenc.c): native disposition mapping and version-specific configuration writing.
- [FFmpeg bitstream filter documentation](https://ffmpeg.org/ffmpeg-bitstream-filters.html#setts): timestamp/duration transformations are distinct from payload re-encoding.
- [Subler official feature list](https://subler.org/): macOS muxing, subtitles, movie tagging and metadata lookup.
- [Apple audio fallback association](https://developer.apple.com/documentation/avfoundation/avassettrack/associationtype/audiofallback): compatible alternative audio relationship.
- [Apple alternate-group preparation](https://developer.apple.com/documentation/quicktime-file-format/preparing_sound_and_subtitle_alternate_groups_for_use_with_apple_devices): enabled state, same-type alternates and audio/subtitle follower relationships.
- [GPAC MP4Box general operations](https://wiki.gpac.io/MP4Box/mp4box-gen-opts/): generic track references, groups, roles, names, language, edits, iTunes tags and multiview extensions.
- [MP4Forge documented features](https://github.com/jessielw/MP4Forge), [Mp3tag field mappings](https://docs.mp3tag.de/mapping/) and [MetaX](https://www.danhinsley.com/metax/metax.html): Windows tools cover portions of the intended integrated workflow; documentation alone does not demonstrate full parity or preservation of these files.

## Exploration and expansion programme

These are proposed discovery workstreams, not implemented capabilities or fixed delivery commitments. Start with a preservation preview and a safe-editing contract, then prioritize edition-aware synchronization and incremental MP4 editing. Use the results to select backends and define implementation issues with measurable acceptance criteria.

### Foundation: preservation preview and safe-editing contract

Before execution, show each selected track, metadata field and relationship with its planned result: copied, converted, semantically translated, archived only, intentionally excluded, changed or unsupported. Explain the reason and target-profile implication; distinguish an untested assumption from a validated capability. Include storage needs, expensive rewrites and the chosen verification level.

Define an invariant set for edits to existing media: unrelated encoded payloads, codec configuration, stereo/HDR signalling, timing and relationships must survive. Tag-only changes must not silently alter track selection or timing. Subtitle insertion must preserve existing metadata and references. An operation that cannot meet the selected contract must expose a different plan before writing.

Discovery deliverable: a synthetic multi-track fixture, a proposed preservation-report schema and a mock preview covering unsupported native flags, authorized subtitle conversion, metadata conflicts and fallback relationships. Acceptance: every change is accounted for, the preview matches the actual report, and cancellation leaves the source intact.

### Priority 1: edition-aware synchronization

Explore matching audio and subtitles across different editions using multiple content anchors. Estimate offset and rational scale, detect cut differences/discontinuities, and propose piecewise mappings with confidence and uncertainty. Frame rate, matching titles and total duration are evidence rather than sufficient alignment rules.

Investigate audio fingerprints/correlation, scene or frame features, subtitle-text anchors and manual correction. Identify failures with silence, reordered scenes, repeated music, alternate dialogue, accessibility narration and missing sections. Share the timeline model in the engine/Core layer; keep discovery and user decisions visible in the UI.

Discovery deliverable: a bounded prototype on synthetic timelines containing constant delay, uniform drift, inserted/deleted segments and ambiguous anchors. Acceptance: measured alignment error at the beginning/middle/end, explicit unresolved intervals, editable anchors, and no timing modification without selecting the alignment plan. Report whether a chosen transform can be expressed through container timing or requires an explicit media conversion; never imply that arbitrary audio time stretching is always stream-copyable.

### Priority 2: incremental MP4 editing

Compare validated libraries/backends for tag, artwork, subtitle and relationship edits. Determine when reserved metadata space, a trailing movie box or other layout permits avoiding a full media rewrite, and when relocation, changed offsets, fragmentation or newly inserted samples makes a safe rewrite necessary.

Prototype a transactional editor with layout preflight, size/offset checks, a recovery journal or temporary output, and independently read-back invariants. Metadata-only edits and adding new media samples are different cost classes. A faster path is acceptable only if it satisfies the preservation contract.

Discovery deliverable: a capability matrix and benchmarks for representative synthetic layouts and file sizes. Acceptance: unchanged unrelated payload hashes and semantic properties, valid offsets/references, bounded temporary space, successful rollback after interruption, and accurate advance disclosure of a full rewrite.

### Further exploration workstreams

| Workstream | Exploration question | Concrete discovery output and acceptance |
| --- | --- | --- |
| Container/backend capability explorer | Which codec features, timing constructs, metadata and relationships can each pinned backend actually retain? | Versioned capability matrix with synthetic probes; distinguish supported, translated, archived, unsupported and untested; preview container-switch consequences |
| MP4 inspection and repair | Can complex boxes, edits and references be explained without requiring users to inspect hex? | Read-only inspector and reversible repair proposals; show evidence and affected invariants; refuse speculative repairs |
| Metadata round-trip tooling | Can Kodi NFO, MP4/iTunes/custom and Matroska metadata be reconciled without losing unknown values? | Typed model plus import/export fixtures; exact raw-source recovery, provenance/conflict UI, correct provider IDs, and idempotent writes |
| Track relationship editor | Can users understand and safely change fallback, alternate and subtitle associations? | Accessible visual graph plus table editor; inspect native readback, validate equivalence/alignment, and preserve meaning after reorder/replacement/removal |
| Target compatibility profiles and lab | What works in each chosen player/device/version, beyond structural validity? | Small licensed/synthetic fixtures and versioned results for Apple playback, Kodi/Plex and other selected targets; separate verified playback from documentation assumptions |
| Verification levels | What assurance can users choose at an acceptable cost? | Quick structural, sampled payload, exhaustive payload and semantic/playback levels; specify coverage, normalization, duration estimates and remaining uncertainty |
| Reproducible job bundles | Can another machine repeat or diagnose a job without exposing or embedding the source media? | Versioned plan with source fingerprints, mappings, commands, repairs, tool versions and reports; validate relocation and capability changes; configurable redaction |
| Reusable assembly recipes | Can repeated selection/tagging/fallback policies be reused safely across different inputs? | Parameterized recipes matched by inspected properties; preview ambiguous/missing matches; never bind solely to a previous stream index or filename |
| Temporary-file management | How can staging, caches and recovery data remain useful without consuming storage indefinitely? | Space estimates, job-owned cache manifests, retention rules and deliberate cleanup; preserve sources, active-job files and necessary rollback data |

The relationship graph is a view of the same engine model as the table/CLI, not a second source of truth. Accessibility and scriptability should accompany the visual design.

### Discovery gates and execution order

1. Audit live engine/GUI/CLI call sites and shared Core interfaces against the coverage matrix; identify dormant or duplicate code before selecting integration points.
2. Define the preservation contract, relationship identities, metadata provenance and verification-report schemas.
3. Build synthetic fixtures and reproduce relevant backend successes/failures; record pinned versions and comparison criteria.
4. Run bounded edition-alignment and incremental-editing prototypes independently, with explicit scope and resource budgets.
5. Review correctness, uncertainty, portability, performance and maintenance/licensing constraints before selecting a production backend.
6. Convert the results into implementation issues, milestones and regression tests; scope Windows/macOS parity explicitly rather than assuming shared APIs imply identical behaviour.
7. Deliver a narrow integrated workflow first: inspect, select, preview, execute, verify and edit later without losing previously preserved properties.

A prototype must not be shipped merely because one test file works. Each discovery output should include the question answered, fixture coverage, measured result, unresolved cases and a go/no-go recommendation. Any live-media operation remains subject to the selected copy/conversion and preservation policy.

## Native closed-caption preservation

Closed captions are a separate preservation requirement from text/image subtitle conversion. The requested “CC706” label must be resolved from inspected source signalling; do not invent a codec identifier or assume it means a particular standard. Common caption standards include CEA/EIA-608 and CEA/CTA-708. Record the detected standard, carriage, services/channels and evidence.

- Preserve both CEA/EIA-608 and CEA/CTA-708 closed captions by default when muxing/remuxing MKV to MP4 or MOV, whether embedded in video or carried as discrete streams. Retain both when they coexist, including 608 compatibility data inside 708 carriage. Exclude a caption track/service or standard only when the user explicitly selects it for exclusion; a general request to exclude subtitles is not authorization to remove either caption standard. Preserve the source standard and encoded caption data without conversion. Do not convert captions to SubRip/SRT, SSA/ASS, TTML, mov_text or other text formats, burn them into the image, upgrade 608 to 708, or downgrade 708 to 608 as a fallback. Any optional conversion workflow requires separate explicit authorization.
- Inspect both video-carried captions (for example registered user data/SEI where applicable) and discrete caption streams. A caption service may exist inside the video without a separate subtitle track; absence from the ordinary stream list is not evidence of absence.
- Copying video should retain its embedded caption payload, but validate the actual backend path, automatic bitstream filters and output. Do not remove SEI/user data indiscriminately: captions and other preservation-critical signalling can share those mechanisms.
- A request to exclude ordinary subtitles must retain closed captions by default. Selection operates on semantic caption/subtitle roles, not merely the backend's subtitle-stream classification. A discrete caption stream classified as a subtitle still requires an explicit preservation path.
- For discrete captions, investigate native MP4/MOV caption carriage and signalling, including c608/c708 sample entries where applicable. Backend support must be proven for the actual standard and carriage. Mapping a stream or assigning a codec tag alone does not establish valid packaging. Repackaging must preserve caption data and semantics without an intermediate text conversion.
- Preserve all detected services/channels, language and service descriptors, timing relative to the associated video, presentation commands, positioning, styling and accessibility information where carried. Retain required video associations when tracks are reordered or assembled from multiple sources.
- If the selected backend cannot preserve captions natively in the requested output, report that limitation before execution and offer a compatible native-preservation route. Do not silently discard, convert or declare successful full preservation. Archival sidecar/raw-payload export may be an additional recovery measure; it does not satisfy the requirement to keep usable captions in the MP4/MOV.
- Validate input/output caption payload and timing using a caption-aware parser across sufficient coverage, including later portions and every service. Container/sample checks and actual target-player caption rendering are separate evidence. Report partial scan coverage explicitly.

Acceptance fixtures must cover embedded 608, embedded 708 with multiple services and 608 compatibility data, discrete caption carriage, ordinary subtitles alongside captions, delayed caption appearance, track reordering, and unsupported backend cases. Run the caption acceptance matrix for both MP4 and MOV outputs. Verify that excluding ordinary subtitles leaves both caption standards intact, explicitly excluding one leaves the other intact, coexistence preserves both, all services retain commands/timing, no unwanted text track is created, and failure paths disclose unmet preservation requirements.

Technical reference points: [FFmpeg format documentation](https://www.ffmpeg.org/ffmpeg-formats.html) describes 608/708 raw-caption carriage and extraction; [FFmpeg ATSC A/53 parsing API](https://www.ffmpeg.org/doxygen/5.1/atsc__a53_8h.html) identifies encoded caption payload parsing. These are research starting points, not proof that every muxer/backend supports every native MP4 caption path.

## Configurable content-aware duplicate detection and preferred-track selection

Explore duplicate detection during multi-source assembly, with particular attention to audio, subtitles and closed captions. Compare media content independently of descriptive metadata, then separately determine whether omission is safe and which equivalent representation the user prefers. Similar content is not sufficient proof of redundancy.

### User controls and selection contract

Provide explicit modes: disabled/keep all selected tracks; detect and recommend only; and opt-in automatic consolidation of proven, safely interchangeable duplicates. Recommendation mode may assist selection, but must not remove tracks. Make preferred-track policies configurable, with per-job overrides, per-group decisions and protected/keep-both selections. Show the effective mode in the assembly preview and reproducible job plan; persist it without silently changing existing workflows.

Expose independently configurable equivalence thresholds and quality preferences. A user may prefer lossless audio, immersive features, a particular channel layout, compatibility, language/role, or a specific source. Display why a candidate ranks higher, the comparison method and coverage, evidence of equivalence, timing differences, retained metadata and relationships, and the reason each proposed omission is safe. Resolve ties deterministically using the configured source/track priority rather than an undocumented heuristic.

Existing explicit selection/order instructions take precedence unless the user authorizes consolidation for that job. Closed captions retain their stronger preservation rule: keep both CEA-608 and CEA-708 unless explicitly excluded. Enabling general audio/subtitle deduplication does not authorize caption removal or cross-standard collapse. A caption exclusion requires an explicit caption-specific choice identifying the affected track/service/standard; the preview must expose it.

### Comparison pipeline and evidence levels

1. Inspect characteristics to shortlist candidates: media type, duration, codec, channel/sample configuration, language and semantic role. Missing or inconsistent metadata is uncertainty, not grounds for ignoring otherwise plausible candidates. Codec, bitrate and titles alone never prove duplication.
2. Compare full encoded media payload and required codec configuration while ignoring irrelevant container packaging/descriptive metadata. Account for packetization differences; a naive hash of whole files or packet-boundary serialization is insufficient. Track timestamp/priming/edit information separately.
3. Where useful, compare complete decoded audio samples, subtitle events or native caption semantics using a documented, reproducible comparison representation. Decoder configuration, sample precision, channel ordering, trims and alignment must be recorded. Lossy normalization, downmixing or resampling can establish similarity but cannot prove original-signal identity. Decode/analyze for comparison without changing the selected output encoding.
4. Use fingerprints, correlation, aligned multi-window analysis or normalized text as candidate discovery for different encodings, volume changes or offsets. Sampling/fingerprints cannot prove full-track identity. Escalate candidates to complete comparison before claiming equivalence; report unresolved differences, coverage, thresholds and confidence.
5. Check semantic interchangeability on the output timeline independently of content. Equal content with different delays, stretches, edits, missing sections, service sets or video associations can serve different editions and must not be silently collapsed.

Keep evidence labels distinct: encoded identity, decoded identity, semantic equivalence, probable similarity and insufficient evidence. Exact-content matches can still have incompatible timing/roles. Automatic consolidation requires full comparison and all configured interchangeability checks; approximate matches remain recommendations pending an explicit user decision.

For subtitles compare event text, timing, overlaps, styling, positioning, forced cues and accessibility/SDH information. Normalized dialogue matching does not establish equality of presentation or completeness. For bitmap subtitles compare presentation and timing rather than treating OCR text as proof. For native captions compare services/channels, commands, timing, positioning, styling and accessibility semantics without converting retained output to a text subtitle format. Matching visible dialogue across CEA-608 and CEA-708 does not make either standard disposable.

### Ranking the best equivalent representation

Rank only within a proven equivalence group and compatible semantic role, using the user's policy. For audio consider lossless/lossy status, channel layout, object/immersive features, source lineage, effective fidelity, completeness, synchronization and evidence of clipping, corruption or missing content. Treat sample rate, bit depth and bitrate as characteristics rather than universal quality scores: upsampling, padding, transcoded lossless files and cross-codec bitrate differences can make nominally larger values misleading. A remux workflow must not transcode solely to manufacture a higher-ranked representation.

A stereo mix, surround mix, commentary, audio description, alternate-language recording or different immersive presentation may be a distinct intended option. Preserve these when equivalence is unproven. Retain a required compatibility fallback even when it reproduces the same programme as a higher-fidelity primary track. User preference for best quality does not override a declared playback profile or protected fallback requirement; expose conflicts for resolution.

For subtitles/captions consider completeness, correct alignment, preserved presentation and accessibility semantics, with configurable preferences. Forced-only, full dialogue, SDH and alternative caption services have distinct purposes. Neither a format name nor a greater cue count alone establishes superiority.

### Consolidation, provenance and relationships

Consolidate at planning time so omitted tracks are not needlessly muxed. Preserve survivor ordering according to the effective user selection policy, and assign stable identities independently of source/output indexes. Archive descriptive metadata and source provenance from every consolidated candidate; resolve conflicting language/role/flags through documented policy or review rather than silently merging contradictory values.

Redirect incoming fallback, alternate-group, subtitle-follower, forced-subtitle and video/edition associations to the survivor only when the relationship remains valid. Revalidate the graph, including dangling references, cycles where prohibited, incompatible roles and loss of required alternatives. Do not remove a track if a protected relationship cannot be preserved. Store each decision, evidence, policy version and source-to-survivor mapping in the job report. Support reversing the planned decision before execution; later restoration requires the original sources or an explicitly retained recovery copy.

### Discovery and acceptance gates

Prototype candidate indexing and cached content signatures before committing to a backend. Bind cache keys to source-content identity, selected track, parser/decoder versions and analysis configuration; invalidate on changes. Keep analysis local by default, cancellable and resource-bounded. Report scan costs/coverage and avoid treating interrupted or partial analysis as proof of equality.

Use synthetic/licensed fixtures covering identical payloads with different metadata/packaging, packetization differences, differing priming/offsets, duplicate lossless representations, re-encoded similar audio, stereo/surround and immersive distinctions, commentary sharing long music segments, silence/repeated sections, inserted/deleted scenes, subtitles with equal text but different timing/styles/SDH/forced cues, bitmap/OCR false matches, and both caption standards with multiple services. Include required fallback references, protected selections, conflicting metadata, cache invalidation and source reordering.

Acceptance must demonstrate that disabled/recommend-only modes never omit tracks; automatic mode requires complete equivalence and safe-role/timeline/relationship checks; configured ranking and ties are reproducible; caption exclusions require explicit caption-specific choices; uncertain matches remain reviewable; output survivors preserve original media and valid relationships; and every decision is explained in the preview/report. Benchmark time, memory and disk cost separately from correctness.

Reference: [FFmpeg streamhash](https://ffmpeg.org/ffmpeg-formats.html#streamhash) provides per-stream content hashing but ignores timestamps, so timeline equivalence needs separate verification. [Chromaprint](https://acoustid.org/chromaprint) is a candidate audio-fingerprinting technology to evaluate, not proof of complete soundtrack equivalence.
