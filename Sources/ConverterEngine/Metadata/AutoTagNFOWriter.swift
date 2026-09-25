// ============================================================================
// MeedyaConverter — AutoTagNFOWriter (Issue #508, commit 7/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Writes a Kodi-compatible `.nfo` sidecar next to an encode's output, for a
// film the auto-tag lookup (#508 commits 4-6, `AutoTagRunner`) confidently
// identified. Pure glue: the XML text comes from `MediaServerTagging
// .buildKodiMovieNFO`, and the sidecar's path from `AutoTagger
// .generateNFOPath` — this file adds only the "is it safe to write right
// now, and what do we say if it isn't" decisions that neither of those two
// pure helpers makes on its own.
//
// Called from the very end of `EncodingEngine.encode(job:onProgress:)`, after
// every FFmpeg pass (including any Dolby Vision re-injection) has already
// finished, and only when that job's lookup identified a film AND the job's
// resolved config asked for an NFO (`AutoTagConfig.writeNFO`). Music never
// reaches this file at all: `AutoTagLookupReport.identifiedFilm` is always
// `nil` on the music path (see that property's own doc comment in
// `AutoTagRunner.swift`), so the engine has nothing to pass here for a song.
//
// THREE RULES, ALL DELIBERATE:
//
//   1. An existing `.nfo` is left COMPLETELY ALONE. Kodi, Plex and Jellyfin
//      all let a person hand-edit an NFO — fix a typo, add a poster path,
//      correct a title a scraper got wrong — and this feature must never
//      quietly discard that work. Checking "does it exist?" and then writing
//      would be a race: another job encoding to the same output name, or a
//      file dropped there between the check and the write, could land in the
//      gap. `Data.WritingOptions.withoutOverwriting` closes that race by
//      asking the filesystem to refuse the write ATOMICALLY when the path is
//      already taken, rather than this code checking first and writing
//      second.
//   2. The output must already exist. This is why the engine only calls this
//      writer at the very end of `encode`, once every pass has genuinely
//      finished: writing a `.nfo` that points at a file which was never
//      produced (an encode that failed partway, or one still in progress)
//      would be an orphaned sidecar describing nothing. `write` checks this
//      itself too, rather than trusting every future caller to get the
//      ordering right.
//   3. This can NEVER throw into an encode. A missing output, a read-only
//      folder, running out of disk space, anything else the filesystem
//      raises — every one becomes `.failed(reason:)`, a plain value for the
//      caller to report and move past. A tagging side-effect must not be
//      able to turn an otherwise-successful encode into a failed one.
// ============================================================================

import Foundation

// MARK: - AutoTagNFOOutcome

/// What happened when `AutoTagNFOWriter.write` was asked to save a sidecar.
public enum AutoTagNFOOutcome: Sendable, Equatable {
    /// The `.nfo` was written fresh, at this path.
    case written(path: String)

    /// A `.nfo` already existed at this path, so nothing here touched it —
    /// not even to read it. See this file's header, rule 1.
    case leftExisting(path: String)

    /// Nothing was written, for the plain-English `reason` given (the
    /// encode's output doesn't exist yet, or the filesystem refused the
    /// write for some other reason, such as a read-only folder or no space
    /// left).
    case failed(reason: String)
}

// MARK: - AutoTagNFOWriter

/// Saves the Kodi movie `.nfo` sidecar for an identified film, or explains
/// why it didn't. Stateless: every input arrives through the call.
public enum AutoTagNFOWriter {

    /// - Parameters:
    ///   - film: The film the auto-tag lookup identified
    ///     (`AutoTagLookupReport.identifiedFilm`). Callers only ever have one
    ///     of these to pass when a film really was identified, so this
    ///     writer has no "is this actually a film" check of its own — that
    ///     decision already happened in `AutoTagRunner`.
    ///   - outputURL: The encode's real output file. The sidecar is saved
    ///     next to it, sharing its name with the extension swapped for
    ///     `.nfo` (via `AutoTagger.generateNFOPath`).
    /// - Returns: What happened. Never throws — see this file's header,
    ///   rule 3.
    public static func write(film: MetadataResult, nextTo outputURL: URL) -> AutoTagNFOOutcome {
        // Rule 2: nowhere to sit "next to" until the output is real.
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return .failed(
                reason: "The encoded output file doesn't exist, so there is nowhere to save the .nfo next to it."
            )
        }

        let nfoPath = AutoTagger.generateNFOPath(outputPath: outputURL.path, mediaType: .movie)
        let xml = MediaServerTagging.buildKodiMovieNFO(result: film)

        // `buildKodiMovieNFO` only ever builds a `String` from literals and
        // interpolated `String`/`Int`/`Double` values, which always has a
        // UTF-8 encoding. This guard exists so a future change to that
        // function could only ever turn into a reported `.failed`, never a
        // crash here — not because this is expected to happen in practice.
        guard let data = xml.data(using: .utf8) else {
            return .failed(reason: "The .nfo text could not be encoded.")
        }

        do {
            // Rule 1: `.withoutOverwriting` refuses the write atomically if
            // `nfoPath` already exists, instead of this code checking
            // `fileExists` and then writing as two separate steps with a gap
            // a second writer could land in.
            try data.write(to: URL(fileURLWithPath: nfoPath), options: .withoutOverwriting)
            return .written(path: nfoPath)
        } catch let error as NSError where isFileAlreadyExists(error) {
            return .leftExisting(path: nfoPath)
        } catch {
            // Rule 3: whatever else the filesystem raised (no permission on
            // the folder, out of space, a read-only volume, …) is reported,
            // never thrown.
            return .failed(
                reason: "The .nfo file could not be written (\(type(of: error)): \(error.localizedDescription))."
            )
        }
    }

    /// Whether `error` is exactly the "the file already exists" failure
    /// `.withoutOverwriting` raises on Darwin — as opposed to, say, "no
    /// permission", which must be reported as `.failed` and must never be
    /// mistaken for an existing file that was correctly left alone.
    private static func isFileAlreadyExists(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError
    }
}
