// ============================================================================
// MeedyaConverter — AutoTagJobEvent (Issue #508, commits 6-7/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// What `EncodingEngine` says about a job's auto-tag lookup (and, from commit
// 7, its Kodi `.nfo` write) while it runs, published on
// `EncodingEngine.autoTagEvents`.
//
// DELIBERATELY MINIMAL. This is data only: which job, which file, and what
// happened. It carries NO user-facing wording. Turning an event into an
// Activity Log line is #508 commit 8 (`AutoTagWording`, together with the
// app-side task that reads `autoTagEvents` and writes the log). Until that
// commit lands, nothing in the app reads these events at all; the engine
// publishes them into a small buffer that simply drops the oldest when
// nobody is listening (see `EncodingEngine.autoTagEvents`).
//
// No API key can travel in an event. The only text an event carries is the
// file name, the lookup report and (from commit 7) the NFO outcome's path or
// plain-English failure reason — never a URL, so never a key. Every failure
// reason a lookup report carries has already been through the TMDB key
// redaction (`AutoTagRunner.failed`). `AutoTagEncodeDeliveryTests` checks the
// key appears in no event.
// ============================================================================

import Foundation

// MARK: - AutoTagJobEvent

/// One thing that happened during a job's auto-tag lookup.
public struct AutoTagJobEvent: Sendable {

    /// What happened.
    public enum Kind: Sendable {
        /// A request is about to be sent to this service. Published only when
        /// that is true: a lookup that is skipped (no TMDB key, a TV episode,
        /// a music file with no artist, no running time, …) sends nothing and
        /// publishes no `.lookingUp`, only a `.lookup` saying why it was
        /// skipped. With auto-tagging switched off (or no settings source
        /// given to the engine), a job publishes no events at all.
        case lookingUp(MetadataSource)

        /// The lookup is over and the encode is carrying on — with the
        /// report's `metadataToAdd` merged into the job's output tags when
        /// the outcome is `.applied`, and with nothing added otherwise.
        ///
        /// Carries the whole report rather than just its `outcome`: the
        /// planned success wording ("Tagged from TMDB: … Added: … Kept the
        /// file's own: …") needs the provider and both tag lists, which the
        /// outcome alone does not hold. `report.outcome` is the outcome.
        ///
        /// NOT published when the user stops the job during the lookup: the
        /// encode throws `CancellationError` instead, and the job's own
        /// "cancelled" handling is what reports that.
        case lookup(AutoTagLookupReport)

        /// The auto-tag lookup identified a film and this job's resolved
        /// config said to also save a Kodi `.nfo` sidecar
        /// (`AutoTagConfig.writeNFO`): what `AutoTagNFOWriter.write` did
        /// about it (#508 commit 7). See that type's own doc comment for the
        /// three rules it follows — never overwrite, the output must exist
        /// first, never throw.
        ///
        /// Published at most once per job, and only when a `.lookup` event
        /// with a non-`nil` `report.identifiedFilm` came before it. Never
        /// published for music: `identifiedFilm` is always `nil` there (see
        /// that property's own doc comment), so the engine never has a film
        /// to pass to the writer for a song. Also never published when
        /// `AutoTagConfig.writeNFO` is off, or when a stop was requested for
        /// this job by the time the encode reaches this step — see
        /// `EncodingEngine.encode`'s own doc comment for why that last case
        /// is a deliberate silent skip, not a `.failed` outcome.
        case nfo(AutoTagNFOOutcome)
    }

    /// The `EncodingJobConfig.id` of the job this is about. With several
    /// jobs running at once (#286) events from different jobs interleave,
    /// so this is how a reader tells them apart.
    public let jobID: UUID

    /// The source file's name (not its full path), for a log line.
    public let fileName: String

    /// What happened.
    public let kind: Kind

    public init(jobID: UUID, fileName: String, kind: Kind) {
        self.jobID = jobID
        self.fileName = fileName
        self.kind = kind
    }
}
