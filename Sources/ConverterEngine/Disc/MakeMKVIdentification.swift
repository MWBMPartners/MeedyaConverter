// ============================================================================
// MeedyaConverter — MakeMKVIdentification (Issue #503, slice 4a)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The bridge from a MakeMKV `info` result (#503) to the content-based
// disc-identification engine (#502): it turns a `MakeMKVDiscInfo` into the
// `DiscSignals` fingerprint that `DiscIdentifier.rank(signals:candidates:)` scores.
//
// This is the "feed ripped/read titles into disc identification" half of #503's
// slice 4. It is PURE: it reads the parsed MakeMKV values and returns a value — no
// disc, drive, network, or subprocess — and it changes no policy. The disc's kind
// (`DiscType`) is supplied by the caller, which knows what it inserted; MakeMKV's
// own type strings are localised free text and are not relied on here.
// ============================================================================

import Foundation

// MARK: - MakeMKVIdentification

/// Maps MakeMKV disc metadata onto the #502 identification model.
public enum MakeMKVIdentification {

    /// Build `DiscSignals` from a MakeMKV `info` result.
    ///
    /// The "main feature" is the longest title (by known duration). Its running
    /// time, chapter count, and audio/subtitle languages become the primary
    /// signals; every title's duration is kept as a structure hint. The disc's
    /// volume/disc name seeds the lookup title unless the caller overrides it.
    ///
    /// - Parameters:
    ///   - info: the parsed `makemkvcon info` result.
    ///   - discType: the disc's kind, known to the caller.
    ///   - seedTitle: an optional title hint to seed the lookup query; when `nil`
    ///     the main title's name, else the disc/volume name, is used.
    public static func discSignals(
        from info: MakeMKVDiscInfo,
        discType: DiscType,
        seedTitle: String? = nil
    ) -> DiscSignals {
        // Titles that report a usable duration, paired with it in seconds.
        let timed: [(title: MakeMKVTitle, seconds: Int)] = info.titles.compactMap { title in
            guard let seconds = title.durationSeconds, seconds > 0 else { return nil }
            return (title: title, seconds: seconds)
        }
        let mainFeature = timed.max(by: { $0.seconds < $1.seconds })?.title
        let allDurations = timed.map { TimeInterval($0.seconds) }

        let mainDuration = mainFeature?.durationSeconds.map { TimeInterval($0) }
        let chapterCount = mainFeature?.chapterCount.flatMap { $0 > 0 ? $0 : nil }

        let audioLanguages = languages(in: mainFeature, ofType: "Audio")
        let subtitleLanguages = languages(in: mainFeature, ofType: "Subtitles")

        let label = firstNonBlank(info.volumeName, info.discName)
        // Audio discs are music; leave video hints to the query builder (#502).
        let hint: MediaLookupType? = discType.hasAudio ? .music : nil

        let resolvedSeed = firstNonBlank(
            seedTitle, mainFeature?.name, info.discName, info.volumeName, info.titles.first?.name
        )

        return DiscSignals(
            discType: discType,
            label: label,
            mediaTypeHint: hint,
            mainFeatureDurationSeconds: mainDuration,
            titleDurationsSeconds: allDurations,
            chapterCount: chapterCount,
            subtitleLanguages: subtitleLanguages,
            audioLanguages: audioLanguages,
            seedTitle: resolvedSeed
        )
    }

    // MARK: Helpers

    /// The distinct language codes of a title's streams of a given MakeMKV type
    /// name ("Audio" / "Subtitles"), in first-seen order.
    private static func languages(in title: MakeMKVTitle?, ofType typeName: String) -> [String] {
        guard let title else { return [] }
        var seen = Set<String>()
        var ordered: [String] = []
        for stream in title.streams where stream.typeName == typeName {
            guard let code = stream.languageCode, !code.isEmpty, seen.insert(code).inserted else { continue }
            ordered.append(code)
        }
        return ordered
    }

    /// The first argument that is non-nil and not blank after trimming, else nil.
    private static func firstNonBlank(_ candidates: String?...) -> String? {
        for candidate in candidates {
            if let value = candidate {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
