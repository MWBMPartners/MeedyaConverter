// ============================================================================
// MeedyaConverter — Music disc identification run (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The missing link between the pieces that already existed but that nothing
// ever called: given a disc's table of contents, compute its identity, ask
// MusicBrainz who it is, and contribute what we learned to MeedyaDB.
//
//     read the TOC  →  MusicDiscIdentifier.identify(toc:)  →  a result
//     (DiscImagingController,         (this file)              you can show
//      cdrdao read-toc)                                        or print
//
// Reading the disc is deliberately NOT part of this type: that needs real
// hardware and belongs to `DiscImagingController`. Everything here is driven
// by an already-read `DiscTableOfContents` and two injected seams, so the
// whole flow is unit-testable with no disc, no network and no MeedyaDB.
//
// FAILURE POSTURE — this is the important design decision. A music CD's
// track layout is a near-fingerprint, so the disc IDs we compute locally are
// valuable on their own, even when the lookup or the upload fails. So:
//
//   * a MusicBrainz lookup failure does NOT throw and does NOT abandon the
//     run — the IDs are kept, `lookupFailure` records what went wrong, and
//     the contribution still goes ahead (MeedyaDB learning about a disc that
//     MusicBrainz has never heard of is exactly the interesting case);
//   * a MeedyaDB failure does NOT throw either — it is recorded in
//     `contribution` so a caller can show it without a `do/catch`;
//   * MeedyaDB being switched off or not yet configured is NOT a failure at
//     all. It is `.notAttempted`, because the wiring deliberately landed
//     before the server did (owner decision: "build wiring now, deploy
//     later"), and a normal user with no MeedyaDB account must never see an
//     error for it.
//
// The ONLY error `identify` throws is `CancellationError`.
// ============================================================================

import Foundation

// MARK: - What happened with MeedyaDB

/// The outcome of the contribute-to-MeedyaDB half of a run. Deliberately
/// separates "we didn't try" from "we tried and it failed": the first is a
/// normal, silent state for anyone without a MeedyaDB account, and must not
/// be reported as an error.
public enum MeedyaDBContribution: Sendable, Equatable {
    /// No submission was sent, and that is fine — publishing is off, not
    /// configured yet, not asked for, or there was nothing worth sending.
    case notAttempted(reason: String)
    /// Sent and accepted; carries MeedyaDB's own IDs for the disc.
    case succeeded(MeedyaDBIngestResult)
    /// Sent and rejected, or the network failed.
    case failed(reason: String)

    /// True only for `.succeeded` — use this rather than matching by hand.
    public var didSubmit: Bool {
        if case .succeeded = self { return true }
        return false
    }

    /// The plain-English explanation, whatever the case. `nil` for a success.
    public var reason: String? {
        switch self {
        case .notAttempted(let reason), .failed(let reason):
            return reason
        case .succeeded:
            return nil
        }
    }
}

// MARK: - The disc's own identity (computed locally, no network)

/// What a disc's table of contents says about itself, before anyone else is
/// asked. All of it is derived offline and deterministically.
public struct MusicDiscIdentity: Sendable, Equatable {

    /// The MusicBrainz-compatible Disc ID, covering the **music portion**
    /// only. This is the value MusicBrainz recognises and MeedyaDB keys on.
    /// `nil` when the disc has no audio tracks, or when its table of contents
    /// is too damaged to measure.
    ///
    /// Prefers an ID the TOC already carries over computing a fresh one —
    /// the same preference `MeedyaDBSubmissionBuilder.audioCD` applies, and
    /// they MUST agree: otherwise we would show the user one ID and send
    /// MeedyaDB a different one.
    public var musicDiscID: String?

    /// The same calculation over the **whole physical disc**, including any
    /// data session. Identical to `musicDiscID` on an ordinary audio CD;
    /// different on an Enhanced/CD-Extra disc, where it is the finer key.
    public var wholeDiscID: String?

    /// How the music session's lead-out was established — reported by the
    /// drive, derived from where the data track starts, or simply the whole
    /// disc because there is only one session. Worth surfacing: the derived
    /// case is the one that has never been checked against real hardware.
    public var leadOutSource: MusicBrainzDiscID.LeadOutSource?

    /// The `+`-joined TOC string used for the MusicBrainz lookup and stored
    /// by MeedyaDB as the disc's fingerprint.
    public var tocFingerprint: String?

    /// How many audio (non-data) tracks the disc carries.
    public var audioTrackCount: Int

    public init(
        musicDiscID: String? = nil,
        wholeDiscID: String? = nil,
        leadOutSource: MusicBrainzDiscID.LeadOutSource? = nil,
        tocFingerprint: String? = nil,
        audioTrackCount: Int = 0
    ) {
        self.musicDiscID = musicDiscID
        self.wholeDiscID = wholeDiscID
        self.leadOutSource = leadOutSource
        self.tocFingerprint = tocFingerprint
        self.audioTrackCount = audioTrackCount
    }

    /// True when the disc carries a data session as well as music — an
    /// Enhanced CD / CD-Extra.
    ///
    /// Decided from the disc's STRUCTURE (which is what `leadOutSource`
    /// records), not by comparing the two ID strings. Comparing them would
    /// be wrong whenever the TOC carries a stored music ID: a stale or
    /// foreign tag would differ from our computed whole-disc ID and make an
    /// ordinary CD look Enhanced.
    public var isEnhancedCD: Bool {
        // Unwrap before the switch: bare `case .singleSession:` against an
        // Optional does not compile — it would need `case .singleSession?:`.
        guard let source = leadOutSource else { return false }
        switch source {
        case .reportedSession, .derivedFromDataTrack:
            return true
        case .singleSession:
            return false
        }
    }

    /// False when there is nothing here to identify — either no audio tracks
    /// at all, or audio tracks whose table of contents can't be measured.
    /// `hasUnreadableTableOfContents` tells the two apart.
    public var isUsable: Bool {
        musicDiscID != nil && audioTrackCount > 0
    }

    /// True when the disc HAS audio tracks but no identifier could be worked
    /// out from them — a truncated or malformed table of contents. Worth
    /// distinguishing: telling someone a disc "has no audio tracks" directly
    /// under a line reading "Audio tracks: 3" is a visible contradiction.
    public var hasUnreadableTableOfContents: Bool {
        audioTrackCount > 0 && musicDiscID == nil
    }
}

// MARK: - The whole run's result

/// Everything one identification run learned. Nothing here is thrown away on
/// a partial failure — see this file's header on the failure posture.
public struct MusicDiscIdentificationResult: Sendable, Equatable {

    /// The locally computed identity. Always present, even when every remote
    /// step failed.
    public var identity: MusicDiscIdentity

    /// Releases MusicBrainz says match this exact TOC. Because a CD's track
    /// layout is a near-fingerprint this is an exact hit, not a ranked guess
    /// — several entries mean several pressings of the same record, not
    /// competing theories about what the disc is.
    public var matches: [MusicBrainzDiscMatch]

    /// Why the MusicBrainz lookup failed, when it did. `nil` on success —
    /// including a successful lookup that simply found nothing.
    public var lookupFailure: String?

    /// The submission INPUTS — what a contribution was built from. Kept even
    /// when nothing was sent, so a caller can show the user what one would
    /// contain before they switch it on.
    ///
    /// Not the wire payload: in `.anonymous` mode the publisher strips
    /// `labelText` before sending, so these inputs can hold a label that
    /// never leaves the machine. Anything presenting this as "what was sent"
    /// must apply that same removal first.
    public var submission: MeedyaDBDiscSubmissionInputs?

    public var contribution: MeedyaDBContribution

    public init(
        identity: MusicDiscIdentity,
        matches: [MusicBrainzDiscMatch] = [],
        lookupFailure: String? = nil,
        submission: MeedyaDBDiscSubmissionInputs? = nil,
        contribution: MeedyaDBContribution
    ) {
        self.identity = identity
        self.matches = matches
        self.lookupFailure = lookupFailure
        self.submission = submission
        self.contribution = contribution
    }

    /// True when MusicBrainz recognised the disc.
    public var isIdentified: Bool { !matches.isEmpty }

    /// A one-line plain-English summary, suitable for a CLI line or a status
    /// label. Never mentions a MeedyaDB step the user didn't ask for.
    public var summary: String {
        guard identity.isUsable else {
            return identity.hasUnreadableTableOfContents
                ? "This disc's table of contents is incomplete, so it can't be identified."
                : "This disc has no audio tracks, so there is nothing to identify."
        }
        if let first = matches.first {
            let who = first.artist.map { "\($0) — " } ?? ""
            if matches.count == 1 {
                return "Identified as \(who)\(first.title)."
            }
            return "Identified as \(who)\(first.title), and \(matches.count - 1) other pressing\(matches.count == 2 ? "" : "s") of it."
        }
        if let failure = lookupFailure {
            return "Couldn't check with MusicBrainz: \(failure)"
        }
        return "MusicBrainz doesn't know this disc yet."
    }
}

// MARK: - The runner

/// Runs the identify-and-contribute flow for a music disc.
///
/// Both collaborators are injected and both have working defaults, so
/// `MusicDiscIdentifier()` is a usable production instance that looks the
/// disc up and quietly skips the contribution (the default MeedyaDB config
/// is empty and disabled).
public struct MusicDiscIdentifier: Sendable {

    private let lookupService: MusicBrainzDiscLookupService
    /// The contribute half is shared with the video path (`MeedyaDBContributor`)
    /// so the failure posture is decided in exactly one place and cannot drift
    /// between the two kinds of disc.
    private let contributor: MeedyaDBContributor

    public init(
        lookupService: MusicBrainzDiscLookupService = MusicBrainzDiscLookupService(),
        publisher: MeedyaDBPublisher = MeedyaDBPublisher(config: MeedyaDBPublisherConfig())
    ) {
        self.lookupService = lookupService
        self.contributor = MeedyaDBContributor(publisher: publisher)
    }

    /// Convenience for the common case: default lookup, MeedyaDB from a
    /// config, both sharing one HTTP seam.
    public init(
        meedyaDB config: MeedyaDBPublisherConfig,
        httpClient: any MetadataHTTPClient = URLSessionMetadataHTTPClient()
    ) {
        self.init(
            lookupService: MusicBrainzDiscLookupService(httpClient: httpClient),
            publisher: MeedyaDBPublisher(config: config, httpClient: httpClient)
        )
    }

    // MARK: Identity only (offline, no network at all)

    /// Everything the disc says about itself, computed locally. Pure: no
    /// network, no subprocess, no disc access. Safe to call on any TOC,
    /// including a malformed or empty one (every field just comes back nil).
    public static func identity(for toc: DiscTableOfContents) -> MusicDiscIdentity {
        // Same stored-ID preference as `MeedyaDBSubmissionBuilder.audioCD`,
        // deliberately duplicated rather than approximated: if these two ever
        // disagree we would print one ID and submit another.
        let stored = toc.musicBrainzDiscId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = (stored?.isEmpty == false ? stored : nil) ?? MusicBrainzDiscID.compute(for: toc)

        return MusicDiscIdentity(
            musicDiscID: preferred,
            wholeDiscID: MusicBrainzDiscID.computeWholeDisc(for: toc),
            leadOutSource: MusicBrainzDiscID.musicSessionLeadOutSector(for: toc)?.source,
            tocFingerprint: MusicBrainzDiscLookupService.musicBrainzTOCString(for: toc),
            audioTrackCount: toc.tracks.filter { !$0.isData }.count
        )
    }

    // MARK: The full run

    /// Identify `toc` and, when asked and able, contribute it to MeedyaDB.
    ///
    /// - Parameters:
    ///   - toc: an already-read table of contents.
    ///   - labelText: what is printed on the disc, if the caller knows it.
    ///     Only ever leaves the machine in `.full` mode.
    ///   - contribute: set false to identify only and send nothing.
    ///   - mode: `.anonymous` (the default) strips `labelText` before sending.
    /// - Returns: everything the run learned; partial failures are recorded
    ///   in the result rather than thrown.
    /// - Throws: `CancellationError`, and nothing else.
    public func identify(
        toc: DiscTableOfContents,
        labelText: String? = nil,
        contribute: Bool = true,
        mode: MeedyaDBSubmissionMode = .anonymous
    ) async throws -> MusicDiscIdentificationResult {

        let identity = Self.identity(for: toc)

        // A disc with no audio tracks has nothing for MusicBrainz to answer
        // and nothing worth sending. Short-circuit BEFORE the network so a
        // data-only disc never costs a request (the lookup would reject it
        // with `.emptyQuery` anyway).
        guard identity.isUsable else {
            return MusicDiscIdentificationResult(
                identity: identity,
                contribution: .notAttempted(
                    reason: identity.hasUnreadableTableOfContents
                        ? Self.unreadableTOCReason
                        : Self.noAudioReason
                )
            )
        }

        var matches: [MusicBrainzDiscMatch] = []
        var lookupFailure: String?
        do {
            matches = try await lookupService.lookup(disc: toc)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Deliberately keep going: the locally computed IDs are still
            // worth contributing, and a disc MusicBrainz can't tell us about
            // is precisely the one MeedyaDB most wants to hear about.
            lookupFailure = error.localizedDescription
        }

        let submission = MeedyaDBSubmissionBuilder.audioCD(
            toc: toc,
            matches: matches,
            labelText: labelText
        )

        let contribution = try await contributeIfPossible(
            submission,
            contribute: contribute,
            mode: mode
        )

        return MusicDiscIdentificationResult(
            identity: identity,
            matches: matches,
            lookupFailure: lookupFailure,
            submission: submission,
            contribution: contribution
        )
    }

    // MARK: - Contribution

    /// Delegates to the shared `MeedyaDBContributor` — see its doc comment
    /// for the failure posture. Kept as a named method so the call site in
    /// `identify` stays readable.
    private func contributeIfPossible(
        _ submission: MeedyaDBDiscSubmissionInputs,
        contribute: Bool,
        mode: MeedyaDBSubmissionMode
    ) async throws -> MeedyaDBContribution {
        try await contributor.contribute(submission, requested: contribute, mode: mode)
    }

    // MARK: - Plain-English reasons
    //
    // Public and named so a UI can recognise a specific "nothing was sent"
    // case without string-matching, and so tests pin the exact wording.
    // Treat an edit here as a user-facing copy change, not a refactor.

    public static let noAudioReason =
        "This disc has no audio tracks, so there is nothing to identify or contribute."
    public static let unreadableTOCReason =
        "This disc's table of contents is incomplete, so no identifier could be worked out from it."
    /// Forwarded from `MeedyaDBContributor`, which now owns the wording for
    /// both kinds of disc. Kept here so existing callers keep working and so
    /// the two can never say different things.
    public static let notRequestedReason = MeedyaDBContributor.notRequestedReason
    public static let noIdentityReason = MeedyaDBContributor.noIdentityReason
}
