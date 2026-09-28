// ============================================================================
// MeedyaConverter — MediaLanguagePolicy (module entry point)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The Swift implementation of the shared language policy MWBM-MEDIA-LANG
// 1.0.0 — `docs/standards/media-language-bcp47-policy.md` in this repository,
// an exact copy of the master in MWBMPartners/MeedyaSuite-core. The policy
// is normative; this code follows it and is held to every one of its
// conformance cases (Tests/MediaLanguagePolicyTests).
//
// This module depends on NOTHING but Foundation, so it builds and its tests
// run on Linux too, and so it can move to a shared package when MeedyaPlayer
// or MeedyaSubtitler has code (policy §9).
//
// The jobs are kept apart, one file each, as policy §9 asks:
//   LanguageTag.swift               tag parsing and canonical form (LANG-001)
//   LanguageReading.swift           old codes and OS locales (LANG-002, -004)
//   LanguageNames.swift             localised names, autonyms; ISO 639-2
//                                   codes for writing (UI-010, NAME-010,
//                                   TRACK-070)
//   TrackRoles.swift                roles and role order (TRACK-010, -050)
//   CanonicalLanguageOrder.swift    stored order (Part A)
//   PresentationLanguageOrder.swift menu order and labels (Part B)
//   LanguageMatcher.swift           preference matching (MATCH)
//   AutomaticTrackSelection.swift   automatic selection (AUTO)
//   SidecarFileName.swift           sidecar file names (TEXT-030)
// ============================================================================

import Foundation

/// Every job of the language policy, wired to one copy of the reference data.
public struct MediaLanguagePolicy: Sendable {

    /// LANG-001: canonical form.
    public let canonicaliser: LanguageTagCanonicaliser
    /// LANG-002: values read from files and other systems.
    public let reader: LegacyLanguageReader
    /// LANG-004: operating-system locale names.
    public let posixLocales: POSIXLocaleConverter
    /// TRACK-070: ISO 639-2 codes for old three-letter fields.
    public let iso6392: ISO6392Writer
    /// Part A: stored order.
    public let canonicalOrder: CanonicalLanguageOrder
    /// Part B: menu order.
    public let presentationOrder: PresentationLanguageOrder
    /// MATCH-010 to MATCH-040.
    public let matcher: LanguageMatcher
    /// AUTO-010 to AUTO-040.
    public let selector: AutomaticTrackSelector
    /// TEXT-030.
    public let sidecarNames: SidecarFileName

    /// Builds every job on `data`.
    public init(data: LanguageReferenceData) {
        let canonicaliser = LanguageTagCanonicaliser(data: data)
        self.canonicaliser = canonicaliser
        reader = LegacyLanguageReader(canonicaliser: canonicaliser)
        posixLocales = POSIXLocaleConverter(canonicaliser: canonicaliser)
        iso6392 = ISO6392Writer(canonicaliser: canonicaliser)
        canonicalOrder = CanonicalLanguageOrder(canonicaliser: canonicaliser)
        presentationOrder = PresentationLanguageOrder(canonicaliser: canonicaliser)
        matcher = LanguageMatcher(canonicaliser: canonicaliser)
        selector = AutomaticTrackSelector(canonicaliser: canonicaliser)
        sidecarNames = SidecarFileName(reader: reader)
    }

    /// The policy on the bundled reference data, loaded once per process.
    /// A failure (the resource bundle missing — a packaging mistake) is
    /// returned, never a crash, so a caller can keep raw text rather than
    /// guess (LANG-002, COMPAT-040).
    public static let shared: Result<MediaLanguagePolicy, LanguageReferenceDataError> =
        LanguageReferenceData.bundled.map(MediaLanguagePolicy.init(data:))
}
