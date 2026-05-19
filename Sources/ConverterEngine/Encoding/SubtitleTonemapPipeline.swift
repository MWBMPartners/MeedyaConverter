// ============================================================================
// MeedyaConverter — SubtitleTonemapPipeline
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pre-processing pipeline that, given an HDR source file and a per-profile
// `SubtitleTonemapConfig`, extracts each candidate subtitle stream via
// FFmpeg, runs `subtitle_tonemap` against the extracted file, and returns
// the resulting tone-mapped files for the encoding pipeline to use.
//
// This file lives between `SubtitleTonemapWrapper` (which knows how to
// invoke a single tone-map run) and `EncodingEngine` (which orchestrates
// the encode). It is intentionally a standalone enum with static methods
// rather than an extension of `EncodingEngine` so it can be unit-tested
// without standing up an entire engine instance.
//
// Call-site integration in `EncodingEngine.encode(...)` is the follow-up
// to this commit (see #369). The remaining piece of work is teaching
// `FFmpegArgumentBuilder` to consume the returned `[TonemappedSubtitle]`
// as additional `-i` inputs with the right `-map` overrides so the
// tone-mapped subtitles replace the original ones in the output.
//
// GitHub Issues: #369 (engine binary + this pipeline) / #381 / #396
// (profile field + UI binding shipped earlier in the cycle).
// ============================================================================

import Foundation

// MARK: - SubtitleTonemapPipeline

/// Namespace for the subtitle tone-mapping pre-processing pipeline.
public enum SubtitleTonemapPipeline {

    // -----------------------------------------------------------------
    // MARK: - Result type
    // -----------------------------------------------------------------

    /// A single tone-mapped subtitle output, ready to substitute back
    /// into the main encode.
    public struct TonemappedSubtitle: Sendable, Hashable {

        /// The stream index this subtitle occupied in the source file.
        /// The encoding pipeline uses this to know which original
        /// subtitle stream to suppress when remapping.
        public let streamIndex: Int

        /// The original codec name reported by the probe (e.g.
        /// `"hdmv_pgs_subtitle"`, `"ass"`). Kept on the result so the
        /// encoding pipeline can pick the right codec for the output
        /// container when remapping.
        public let codecName: String

        /// The on-disk path of the tone-mapped subtitle file. Lives
        /// inside the job's temp directory; the caller is responsible
        /// for cleanup once the encode completes.
        public let tonemappedFile: URL

        public init(streamIndex: Int, codecName: String, tonemappedFile: URL) {
            self.streamIndex = streamIndex
            self.codecName = codecName
            self.tonemappedFile = tonemappedFile
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Codec → extension mapping
    // -----------------------------------------------------------------

    /// File extension (and FFmpeg muxer name) for a given subtitle
    /// codec, when `subtitle_tonemap` can operate on that codec.
    ///
    /// Returns `nil` for codecs that `subtitle_tonemap` does not yet
    /// support — those streams will pass through unchanged. We
    /// deliberately exclude `dvd_subtitle` / `vobsub` until the
    /// pipeline learns to keep the companion `.idx` file alongside the
    /// `.sub` payload; for now those streams are skipped rather than
    /// risk producing a `.sub` that no demuxer can index.
    public static func subtitleFileExtension(forCodec codec: String) -> String? {
        switch codec.lowercased() {
        case "hdmv_pgs_subtitle", "pgs":
            // PGS / Blu-ray subtitles — the most common HDR subtitle
            // carrier on modern remuxes.
            return "sup"
        case "ass", "ssa":
            // SubStation Alpha — Anime / fan-sub formats, often
            // shipped with HDR-coloured fonts.
            return "ass"
        default:
            return nil
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Candidate-stream selection (pure)
    // -----------------------------------------------------------------

    /// Returns the subtitle streams in `sourceInfo` that should be
    /// tone-mapped, given the profile's config and the availability of
    /// the `subtitle_tonemap` binary.
    ///
    /// The function is *pure* — it does no I/O — so it can be unit-
    /// tested cheaply. The four short-circuit cases (no config, no
    /// HDR, wrapper unavailable, no supported codec) cover the
    /// expected real-world distribution of inputs:
    ///
    ///   * SDR sources never trigger tone-mapping.
    ///   * Sources with no subtitles trivially produce an empty list.
    ///   * `subtitle_tonemap` is shipped in the tool bundle but may be
    ///     missing on a developer machine that hasn't run
    ///     `scripts/bundle-ffmpeg.sh` yet — silently degrade in that
    ///     case rather than failing the encode.
    ///
    /// - Parameters:
    ///   - sourceInfo: The probed source file.
    ///   - config: The profile's `subtitleTonemap` setting — `nil`
    ///     when the user has not opted in.
    ///   - wrapperAvailable: Whether `SubtitleTonemapWrapper.isAvailable`
    ///     returned `true` for this host.
    /// - Returns: The candidate streams, preserving source order.
    public static func candidateStreams(
        in sourceInfo: MediaFile,
        config: SubtitleTonemapConfig?,
        wrapperAvailable: Bool
    ) -> [MediaStream] {

        // Short-circuit 1 — user did not opt in.
        guard config != nil else { return [] }

        // Short-circuit 2 — no point tone-mapping subtitles from an
        // SDR source. The wrapper exists for the case where the video
        // has HDR colours that the subtitle was authored against.
        guard sourceInfo.hasHDR else { return [] }

        // Short-circuit 3 — binary unavailable; the encoding pipeline
        // will skip tone-mapping and the subtitles pass through.
        guard wrapperAvailable else { return [] }

        // Filter to supported codecs. Streams with codecs we cannot
        // tone-map yet (DVD/VobSub, DVB subs, etc.) drop out here
        // rather than reaching the subprocess stage.
        return sourceInfo.subtitleStreams.filter { stream in
            guard let codec = stream.codecName else { return false }
            return subtitleFileExtension(forCodec: codec) != nil
        }
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg argument builder for stream extraction
    // -----------------------------------------------------------------

    /// FFmpeg argument list that extracts a single subtitle stream
    /// from `inputPath` to a standalone file at `outputPath` in the
    /// muxer format that `subtitle_tonemap` expects.
    ///
    /// `-c:s copy` keeps the original codec payload bit-for-bit; the
    /// `-f` muxer matches the extension produced by
    /// `subtitleFileExtension(forCodec:)`.
    public static func ffmpegExtractionArguments(
        inputPath: String,
        outputPath: String,
        streamIndex: Int,
        outputFormat: String
    ) -> [String] {
        [
            "-y",
            "-i", inputPath,
            "-map", "0:\(streamIndex)",
            "-c:s", "copy",
            "-f", outputFormat,
            outputPath,
        ]
    }

    // -----------------------------------------------------------------
    // MARK: - Full pipeline
    // -----------------------------------------------------------------

    /// Runs the full pre-processing pipeline: extract each candidate
    /// subtitle stream via FFmpeg, then tone-map each via the supplied
    /// wrapper. Per-stream failures are *logged but not fatal* — one
    /// broken subtitle should not cause an otherwise-good encode to
    /// fail.
    ///
    /// The `runFFmpeg` closure is dependency-injected so the call
    /// site (`EncodingEngine.encode`) can route extraction through its
    /// existing `runFFmpegPass` helper (which already understands
    /// progress reporting, signal handling, and stderr capture).
    /// Tests pass an in-memory stub.
    ///
    /// - Parameters:
    ///   - source: The source media URL.
    ///   - sourceInfo: The probed source metadata.
    ///   - config: The profile's tone-map config. `nil` short-circuits
    ///     the whole pipeline and returns an empty result.
    ///   - wrapper: The `SubtitleTonemapWrapper` to invoke. Tests can
    ///     subclass / mock; production passes the engine's instance.
    ///   - tempDir: A writable directory the pipeline uses for both
    ///     the extracted and tone-mapped intermediates. The caller
    ///     owns the directory and its lifecycle.
    ///   - runFFmpeg: Dependency-injected FFmpeg invocation.
    /// - Returns: One `TonemappedSubtitle` per successfully processed
    ///   stream. May be shorter than the candidate-stream list if
    ///   individual streams hit errors.
    public static func run(
        source: URL,
        sourceInfo: MediaFile,
        config: SubtitleTonemapConfig?,
        wrapper: SubtitleTonemapWrapper,
        tempDir: URL,
        runFFmpeg: @Sendable (_ args: [String]) async throws -> Void
    ) async -> [TonemappedSubtitle] {

        let candidates = candidateStreams(
            in: sourceInfo,
            config: config,
            wrapperAvailable: wrapper.isAvailable
        )
        guard let config else { return [] }
        if candidates.isEmpty { return [] }

        var results: [TonemappedSubtitle] = []
        results.reserveCapacity(candidates.count)

        for stream in candidates {
            guard let codec = stream.codecName,
                  let ext = subtitleFileExtension(forCodec: codec)
            else { continue }

            let extractedURL = tempDir.appendingPathComponent(
                "subtitle-\(stream.streamIndex)-source.\(ext)"
            )
            let tonemappedURL = tempDir.appendingPathComponent(
                "subtitle-\(stream.streamIndex)-tonemapped.\(ext)"
            )

            // 1. Extract via FFmpeg. A failure here means the stream
            //    cannot be processed — log and move on.
            do {
                try await runFFmpeg(
                    ffmpegExtractionArguments(
                        inputPath: source.path,
                        outputPath: extractedURL.path,
                        streamIndex: stream.streamIndex,
                        outputFormat: ext
                    )
                )
            } catch {
                print("Warning: subtitle stream \(stream.streamIndex) "
                      + "extraction failed (#369 pipeline): "
                      + "\(error.localizedDescription)")
                continue
            }

            // 2. Tone-map via the wrapper.
            do {
                try await wrapper.toneMap(
                    inputPath: extractedURL.path,
                    outputPath: tonemappedURL.path,
                    config: config
                )
            } catch {
                print("Warning: subtitle_tonemap failed for stream "
                      + "\(stream.streamIndex) (#369 pipeline): "
                      + "\(error.localizedDescription)")
                // Clean up the extracted file before continuing.
                try? FileManager.default.removeItem(at: extractedURL)
                continue
            }

            // 3. Record the success. We deliberately leave the
            //    extracted intermediate in place — it lives in the
            //    job's temp dir, which `TempFileManager.cleanupJob`
            //    will remove wholesale after the encode finishes.
            results.append(
                TonemappedSubtitle(
                    streamIndex: stream.streamIndex,
                    codecName: codec,
                    tonemappedFile: tonemappedURL
                )
            )
        }

        return results
    }
}
