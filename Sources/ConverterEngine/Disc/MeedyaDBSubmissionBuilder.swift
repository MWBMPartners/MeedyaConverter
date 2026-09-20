// ============================================================================
// MeedyaConverter — MeedyaDBSubmissionBuilder (Issues #502 / #503)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// FILE OVERVIEW
// -------------
// The missing join between "we have identified a disc" and "send it to MeedyaDB".
//
// `MeedyaDBPublisher` could already POST a submission, and both the music path
// (`MusicBrainzDiscLookupService`) and the video path (`MakeMKVIdentification` →
// `DiscIdentifier.rank`) could already identify a disc — but nothing turned one
// into the other, so nothing was ever actually submitted. This builder does that,
// for BOTH kinds of disc:
//
//   • **Music (Audio CD)** — the strongest case. A CD's table of contents yields a
//     MusicBrainz **Disc ID**, a near-unique fingerprint, so the lookup is an exact
//     hit rather than a best guess. The disc goes up carrying its Disc ID and TOC
//     fingerprint; each matching release becomes a candidate carrying its
//     MusicBrainz release id.
//   • **Video (DVD / Blu-ray)** — identified by content (runtime, title, year) via
//     MakeMKV, so the result is a ranked best guess. Each ranked candidate carries
//     its provider id (TMDB / TheTVDB / …) and the scorer's confidence.
//
// PURE: builds values only — no disc, drive, network or subprocess. Privacy is
// unchanged and still enforced downstream: `MeedyaDBPublisher.buildSubmission`
// drops `labelText` in `.anonymous` mode (the default), and publishing stays off
// unless the user has configured and enabled it.
// ============================================================================

import Foundation

// MARK: - Submission inputs

/// Everything needed for one `MeedyaDBPublisher.submit(...)` call.
public struct MeedyaDBDiscSubmissionInputs: Sendable, Equatable {
    public var disc: MeedyaDBDisc
    public var identifiers: [MeedyaDBIdentifier]
    public var candidates: [MeedyaDBCandidate]

    public init(
        disc: MeedyaDBDisc,
        identifiers: [MeedyaDBIdentifier] = [],
        candidates: [MeedyaDBCandidate] = []
    ) {
        self.disc = disc
        self.identifiers = identifiers
        self.candidates = candidates
    }
}

// MARK: - MeedyaDBSubmissionBuilder

/// Maps an identified disc onto a MeedyaDB submission.
public enum MeedyaDBSubmissionBuilder {

    /// Identifier type for a disc's own MusicBrainz Disc ID.
    public static let musicBrainzDiscIDType = "musicbrainz-discid"
    /// Identifier type for a matched MusicBrainz release.
    public static let musicBrainzReleaseIDType = "musicbrainz-release"
    /// Source label recorded alongside MusicBrainz identifiers.
    public static let musicBrainzSource = "musicbrainz"

    // MARK: Music discs

    /// Build a submission for an Audio CD from its table of contents and the
    /// releases its Disc ID matched.
    ///
    /// The disc itself carries the Disc ID and the TOC fingerprint, so MeedyaDB can
    /// de-duplicate it against the same disc submitted by anyone else. Several
    /// pressings can legitimately share one TOC, so when the lookup returns more
    /// than one release the confidence is split evenly across them rather than
    /// pretending to a single answer.
    ///
    /// - Parameters:
    ///   - toc: the disc's table of contents.
    ///   - matches: releases returned by the MusicBrainz Disc ID lookup.
    ///   - labelText: the disc's printed label, if known. Only ever transmitted in
    ///     opt-in `.full` mode — the publisher drops it otherwise.
    public static func audioCD(
        toc: DiscTableOfContents,
        matches: [MusicBrainzDiscMatch] = [],
        labelText: String? = nil
    ) -> MeedyaDBDiscSubmissionInputs {
        // Prefer an ID the TOC already carries (e.g. supplied by the drive or a
        // future libdiscid path); otherwise compute it ourselves.
        let storedID = toc.musicBrainzDiscId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let discID = (storedID?.isEmpty == false ? storedID : nil) ?? MusicBrainzDiscID.compute(for: toc)

        let audioTrackCount = toc.tracks.filter { !$0.isData }.count

        let disc = MeedyaDBDisc(
            discType: DiscType.audioCd.rawValue,
            tocFingerprint: MusicBrainzDiscLookupService.musicBrainzTOCString(for: toc),
            musicBrainzDiscId: discID,
            trackCount: audioTrackCount > 0 ? audioTrackCount : nil,
            labelText: labelText
        )

        var identifiers: [MeedyaDBIdentifier] = []
        if let discID {
            identifiers.append(MeedyaDBIdentifier(
                idType: musicBrainzDiscIDType,
                idValue: discID,
                source: musicBrainzSource
            ))
        }

        // An exact TOC hit, shared between however many pressings came back.
        let confidence: Double? = matches.isEmpty ? nil : 1.0 / Double(matches.count)
        let candidates = matches.map { match in
            MeedyaDBCandidate(
                title: match.title,
                artist: match.artist,
                year: match.year,
                identifiers: [MeedyaDBIdentifier(
                    idType: musicBrainzReleaseIDType,
                    idValue: match.id,
                    source: musicBrainzSource
                )],
                confidence: confidence
            )
        }

        return MeedyaDBDiscSubmissionInputs(disc: disc, identifiers: identifiers, candidates: candidates)
    }

    // MARK: Video discs

    /// Build a submission for a video disc read by MakeMKV, with the candidates
    /// that `DiscIdentifier.rank(signals:candidates:)` scored.
    ///
    /// Video discs have no audio TOC, so there is no Disc ID; the disc goes up with
    /// its type, title count and (in `.full` mode only) its label, and each ranked
    /// candidate carries its provider id and the scorer's confidence.
    public static func videoDisc(
        info: MakeMKVDiscInfo,
        discType: DiscType,
        ranked: [ScoredDiscMatch] = [],
        labelText: String? = nil
    ) -> MeedyaDBDiscSubmissionInputs {
        let disc = MeedyaDBDisc(
            discType: discType.rawValue,
            tocFingerprint: nil,
            musicBrainzDiscId: nil,
            trackCount: info.titles.isEmpty ? nil : info.titles.count,
            labelText: labelText ?? info.volumeName ?? info.discName
        )

        let candidates = ranked.map { scored in
            MeedyaDBCandidate(
                title: scored.candidate.title,
                artist: scored.candidate.artist,
                year: scored.candidate.year,
                identifiers: [MeedyaDBIdentifier(
                    idType: scored.candidate.source.rawValue,
                    idValue: scored.candidate.externalId,
                    source: scored.candidate.source.rawValue
                )],
                confidence: scored.score.confidence
            )
        }

        return MeedyaDBDiscSubmissionInputs(disc: disc, identifiers: [], candidates: candidates)
    }
}
