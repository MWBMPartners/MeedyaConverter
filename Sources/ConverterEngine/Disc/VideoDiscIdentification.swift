// ============================================================================
// MeedyaConverter — Video disc identification run (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The video counterpart of `MusicDiscIdentification`. Given what MakeMKV
// found on a DVD or Blu-ray, work out what the disc is and contribute it to
// MeedyaDB:
//
//     makemkvcon info  →  VideoDiscIdentifier.identify(info:discType:...)
//     (MakeMKVExecutor)           (this file)
//
// Reading the disc is deliberately NOT part of this type — that needs the
// consent-gated MakeMKV backend and real hardware. Everything here runs on an
// already-parsed `MakeMKVDiscInfo`, so it is unit-testable with no disc, no
// MakeMKV and no MeedyaDB.
//
// HOW THIS DIFFERS FROM THE MUSIC PATH, and why the code looks less certain:
//
//   * A music CD's track layout is a near-fingerprint, so MusicBrainz gives
//     an EXACT hit. A video disc has no such thing. Identification here is a
//     RANKED GUESS scored against the disc's own content (running time,
//     chapter count, languages) by `DiscIdentifier.rank`, and the result
//     carries confidence scores precisely because it can be wrong.
//   * MusicBrainz needs no API key, so the music path can look a disc up by
//     itself. The video providers (TMDB, TheTVDB, IMDb…) are all keyed and
//     not yet wired up, so candidates are passed IN by the caller. With none,
//     this still does something useful: it contributes the disc's structure,
//     so MeedyaDB learns the disc exists even when nobody can name it.
//
// The contribute half is the shared `MeedyaDBContributor`, so the failure
// posture is identical to the music path and decided in one place. The only
// error `identify` throws is `CancellationError`.
// ============================================================================

import Foundation

// MARK: - The whole run's result

/// Everything one video identification run learned. As with the music path,
/// nothing is thrown away on a partial failure.
/// Not `Equatable`: it carries `ScoredDiscMatch`, whose `MetadataResult`
/// candidate is `Codable, Sendable` but not `Equatable`. Tests assert on the
/// individual fields rather than on whole-value equality.
public struct VideoDiscIdentificationResult: Sendable {

    /// What the disc itself told us — running time, chapters, languages,
    /// label. Computed offline from the MakeMKV scan, and always present.
    public var signals: DiscSignals

    /// Candidate identities, best first, each with the score that put it
    /// there. Empty when the caller supplied no candidates to rank.
    ///
    /// Unlike the music path's exact TOC hit, these are GUESSES: several
    /// entries are competing theories about what the disc is, not different
    /// pressings of the same thing.
    public var ranked: [ScoredDiscMatch]

    /// Exactly what a contribution was built from. Kept even when nothing was
    /// sent, so a caller can show what one would contain. Not the wire
    /// payload: in `.anonymous` mode the publisher strips `labelText` first.
    public var submission: MeedyaDBDiscSubmissionInputs?

    /// Why looking candidates up failed, when a provider was configured and
    /// tried. `nil` when none was configured, or when it succeeded —
    /// including a success that found nothing.
    public var lookupFailure: String?

    public var contribution: MeedyaDBContribution

    public init(
        signals: DiscSignals,
        ranked: [ScoredDiscMatch] = [],
        lookupFailure: String? = nil,
        submission: MeedyaDBDiscSubmissionInputs? = nil,
        contribution: MeedyaDBContribution
    ) {
        self.signals = signals
        self.ranked = ranked
        self.lookupFailure = lookupFailure
        self.submission = submission
        self.contribution = contribution
    }

    /// The single best guess, or `nil` when there was nothing to rank.
    public var bestMatch: ScoredDiscMatch? { ranked.first }

    /// Whether anything was identified at all. Deliberately NOT a claim that
    /// the top guess is right — see `isConfident`.
    public var hasCandidates: Bool { !ranked.isEmpty }

    /// A one-line plain-English summary, suitable for a CLI line or a status
    /// label. Says how sure it is, because a ranked guess presented as fact
    /// is how a disc ends up filed under the wrong film.
    public var summary: String {
        guard let best = bestMatch else {
            if signals.titleDurationsSeconds.isEmpty {
                return "This disc has no readable titles, so there is nothing to identify."
            }
            if let failure = lookupFailure {
                return "Couldn't check with the film database: \(failure)"
            }
            return "Nothing to compare this disc against yet, so it hasn't been named."
        }
        let title = best.candidate.title
        let percent = Int((best.score.confidence * 100).rounded())
        if ranked.count == 1 {
            return "Best guess: \(title) (\(percent)% confident)."
        }
        return "Best guess: \(title) (\(percent)% confident), ahead of \(ranked.count - 1) other possibilit\(ranked.count == 2 ? "y" : "ies")."
    }
}

// MARK: - The runner

/// Runs the identify-and-contribute flow for a video disc.
public struct VideoDiscIdentifier: Sendable {

    private let contributor: MeedyaDBContributor
    private let candidateProvider: (@Sendable (DiscSignals) async throws -> [MetadataResult])?

    /// The default contributor quietly skips the upload (its config is empty
    /// and disabled), and the default candidate provider is absent, so
    /// `VideoDiscIdentifier()` is a usable production object that identifies
    /// structurally without sending or fetching anything.
    ///
    /// - Parameter candidateProvider: where possible identities come from when
    ///   the caller supplies none — `TMDBDiscCandidates.provider(service:)`
    ///   in production. Absent by default because every video provider needs
    ///   an API key, and a disc is still worth contributing on its structure
    ///   alone when there is none.
    public init(
        publisher: MeedyaDBPublisher = MeedyaDBPublisher(config: MeedyaDBPublisherConfig()),
        candidateProvider: (@Sendable (DiscSignals) async throws -> [MetadataResult])? = nil
    ) {
        self.contributor = MeedyaDBContributor(publisher: publisher)
        self.candidateProvider = candidateProvider
    }

    // MARK: Signals only (offline, no network at all)

    /// What the disc says about itself, computed from the MakeMKV scan. Pure:
    /// no network, no subprocess, no disc access.
    public static func signals(
        for info: MakeMKVDiscInfo,
        discType: DiscType,
        seedTitle: String? = nil
    ) -> DiscSignals {
        MakeMKVIdentification.discSignals(from: info, discType: discType, seedTitle: seedTitle)
    }

    // MARK: The full run

    /// Identify `info` against `candidates` and, when asked and able,
    /// contribute the disc to MeedyaDB.
    ///
    /// - Parameters:
    ///   - info: an already-parsed `makemkvcon info` result.
    ///   - discType: the disc's kind, known to the caller.
    ///   - candidates: possible identities from metadata providers. May be
    ///     empty — the disc's structure is still worth contributing.
    ///   - seedTitle: a title hint for the lookup query, when the caller has one.
    ///   - labelText: what is printed on the disc. Only ever leaves the
    ///     machine in `.full` mode.
    ///   - contribute: set false to identify only and send nothing.
    ///   - mode: `.anonymous` (the default) strips `labelText` before sending.
    ///   - declinedBecause: #507 — forwarded to `MeedyaDBContributor.contribute`.
    ///     The specific reason to report when `contribute` is `false`, if the
    ///     caller has one; `nil` falls back to the generic "wasn't requested".
    ///     Appended after the existing parameters, defaulting to `nil`, so no
    ///     existing call site needs to change.
    ///   - recheck: forwarded to `MeedyaDBContributor.contribute` — see its
    ///     doc comment. `nil` here (the default) for callers with no way to
    ///     re-read settings mid-run; the two GUI screens supply one.
    /// - Throws: `CancellationError`, and nothing else.
    public func identify(
        info: MakeMKVDiscInfo,
        discType: DiscType,
        candidates: [MetadataResult] = [],
        seedTitle: String? = nil,
        labelText: String? = nil,
        contribute: Bool = true,
        mode: MeedyaDBSubmissionMode = .anonymous,
        declinedBecause: String? = nil,
        recheck: (@Sendable () -> MeedyaDBSubmissionMode?)? = nil
    ) async throws -> VideoDiscIdentificationResult {

        let signals = Self.signals(for: info, discType: discType, seedTitle: seedTitle)

        // Candidates the caller supplied always win: they know more than a
        // volume-label search ever will. The provider is the fallback, and a
        // failure in it must NOT abandon the run — the disc's structure is
        // still worth contributing, exactly as a MusicBrainz outage does not
        // stop the music path. Cancellation still propagates.
        var candidates = candidates
        var lookupFailure: String?
        if candidates.isEmpty, let provider = candidateProvider {
            do {
                candidates = try await provider(signals)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lookupFailure = error.localizedDescription
            }
        }

        let ranked = DiscIdentifier.rank(signals: signals, candidates: candidates)

        let submission = MeedyaDBSubmissionBuilder.videoDisc(
            info: info,
            discType: discType,
            ranked: ranked,
            labelText: labelText
        )

        let contribution = try await contributor.contribute(
            submission,
            requested: contribute,
            mode: mode,
            declinedBecause: declinedBecause,
            recheck: recheck
        )

        return VideoDiscIdentificationResult(
            signals: signals,
            ranked: ranked,
            lookupFailure: lookupFailure,
            submission: submission,
            contribution: contribution
        )
    }
}
