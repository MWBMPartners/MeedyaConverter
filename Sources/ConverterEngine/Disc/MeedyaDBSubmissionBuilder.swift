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
//
// NOTE: this closes the *mapping* gap, not the wiring. Nothing in `Sources/` calls
// this builder yet — the disc flows still have no production caller, which is the
// standing "builder exists but is unwired" gap recorded in the handoff.
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

    /// Whether this submission carries anything MeedyaDB could actually match or
    /// de-duplicate on. A submission without any of these is a bare disc type and a
    /// track count — a row nobody can ever merge — so callers should skip it rather
    /// than contribute noise.
    public var hasUsableIdentity: Bool {
        disc.musicBrainzDiscId != nil
            || disc.tocFingerprint != nil
            || !identifiers.isEmpty
            || !candidates.isEmpty
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
    /// Identifier type for the whole-disc ID (music **and** any data session).
    /// Deliberately not named `musicbrainz-…`: MusicBrainz never produces this
    /// value, so labelling it as theirs would be wrong.
    public static let fullDiscIDType = "fulldisc-discid"
    /// Source label for values this app computes itself.
    public static let selfComputedSource = "meedyaconverter"

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
    /// Note on `confidence`: here it is a share of certainty split across mutually
    /// exclusive pressings (1/N of an *exact* hit), whereas the video path sends the
    /// scorer's absolute 0–1 belief. A heavily repressed album can therefore give
    /// every candidate a small number despite being identified perfectly — the
    /// disc-level Disc ID identifier is what carries the certainty in that case, so
    /// nothing is lost. Consumers should read candidate confidence as "which of
    /// these", not "how sure are we it is this disc".
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
        // Also contribute the whole-disc ID when it differs — i.e. on an Enhanced
        // CD, where the music-only ID is what MusicBrainz matches but the whole-disc
        // ID distinguishes this pressing from another with different bonus content.
        // On a plain audio CD the two are identical and this adds nothing, so it is
        // skipped rather than duplicated.
        if let wholeDiscID = MusicBrainzDiscID.computeWholeDisc(for: toc), wholeDiscID != discID {
            identifiers.append(MeedyaDBIdentifier(
                idType: fullDiscIDType,
                idValue: wholeDiscID,
                source: selfComputedSource
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
            tocFingerprint: structuralFingerprint(for: info),
            musicBrainzDiscId: nil,
            trackCount: info.titles.isEmpty ? nil : info.titles.count,
            labelText: firstNonBlank(labelText, info.volumeName, info.discName)
        )

        let candidates = ranked.map { scored in
            let provider = scored.candidate.source
            // Only genuine identity providers become identifiers. FanArt.tv and
            // OpenSubtitles supply artwork/subtitles, not identity, so an id from
            // them must not enter the identifier vocabulary.
            let identifiers: [MeedyaDBIdentifier]
            if let idType = identifierType(for: provider), !scored.candidate.externalId.isEmpty {
                identifiers = [MeedyaDBIdentifier(
                    idType: idType,
                    idValue: scored.candidate.externalId,
                    source: provider.rawValue
                )]
            } else {
                identifiers = []
            }
            return MeedyaDBCandidate(
                title: scored.candidate.title,
                artist: scored.candidate.artist,
                year: scored.candidate.year,
                identifiers: identifiers,
                confidence: scored.score.confidence
            )
        }

        return MeedyaDBDiscSubmissionInputs(disc: disc, identifiers: [], candidates: candidates)
    }

    // MARK: Helpers

    /// A structural fingerprint for a video disc: its title layout (how many titles
    /// and how long each is). Video discs have no audio TOC, so without this a
    /// submission in the default anonymous mode would be just a disc type and a
    /// count — nothing MeedyaDB could ever de-duplicate on, meaning every user
    /// submitting the same pressing would create a new unmergeable row.
    ///
    /// Durations only: no personal or library-specific data, so it stays safe to
    /// send anonymously.
    static func structuralFingerprint(for info: MakeMKVDiscInfo) -> String? {
        let durations = info.titles.compactMap { $0.durationSeconds }.sorted(by: >)
        guard !durations.isEmpty else { return nil }
        return "mkv:\(durations.count):" + durations.map(String.init).joined(separator: ",")
    }

    /// The MeedyaDB identifier type for a metadata provider, or `nil` when the
    /// provider does not supply identity. Type names match the vocabulary seeded in
    /// the MeedyaDB repo's `schema.sql`.
    static func identifierType(for source: MetadataSource) -> String? {
        switch source {
        case .tmdb: return "tmdb"
        case .tvdb: return "tvdb"
        case .omdb: return "imdb"            // OMDb's external id is an IMDb id
        case .musicBrainz: return musicBrainzReleaseIDType
        case .discogs: return "discogs-release"
        case .fanArtTV, .openSubtitles: return nil
        }
    }

    /// The first value that is neither nil nor blank. MakeMKV can report an empty
    /// volume name, and a plain `??` chain would send `""` as the label rather than
    /// falling through to the disc name.
    static func firstNonBlank(_ candidates: String?...) -> String? {
        for candidate in candidates {
            if let value = candidate {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
