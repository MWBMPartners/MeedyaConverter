// ============================================================================
// MeedyaConverter — TrackLanguage
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The engine's one doorway to the shared language policy (MWBM-MEDIA-LANG,
// docs/standards/media-language-bcp47-policy.md — read it before changing
// anything about languages, tracks, roles or their order). The rules live in
// the MediaLanguagePolicy module; this file only connects them to the
// engine's own types (`MediaStream`, `StreamDisposition`):
//
//   * reading a language value found in a file (LANG-002);
//   * turning ffmpeg's dispositions into the policy's roles (TRACK-010/050).
//
// If the policy's reference data cannot be loaded (its resource bundle was
// not shipped — a packaging mistake) the engine does NOT guess: language
// values are kept exactly as the file gives them, and a warning is printed
// once. The release workflows fail the build before that can ship.
// ============================================================================

import Foundation
import MediaLanguagePolicy

/// Connects the engine to the language policy.
public enum TrackLanguage {

    /// The policy on its bundled data, or `nil` if the data is missing (see
    /// the file header). Loaded once; the warning is printed once.
    public static let policy: MediaLanguagePolicy? = {
        switch MediaLanguagePolicy.shared {
        case .success(let policy):
            return policy
        case .failure(let error):
            print("Warning: \(error) Track languages are kept exactly as each file gives them.")
            return nil
        }
    }()

    /// A language value read from a file.
    public struct Reading: Sendable, Equatable {
        /// The canonical BCP 47 tag, or `und` when the value was not
        /// recognised (never a guess).
        public let language: String
        /// The value as found, when it was not recognised; else `nil`.
        public let unrecognised: String?
    }

    /// Reads a language value found in a file or reported by a tool such as
    /// ffprobe (LANG-002): old three-letter codes (`eng`, `ger`), `XXX`,
    /// null padding, Matroska's `fre-ca`, or a real tag. An unrecognised
    /// value becomes `und`, with the original kept.
    ///
    /// Without the policy's data the value is returned unchanged (see the
    /// file header) — never replaced by a guess.
    public static func read(fileValue raw: String) -> Reading {
        guard let policy else {
            return Reading(language: raw, unrecognised: nil)
        }
        switch policy.reader.reading(raw) {
        case .tag(let tag):
            return Reading(language: tag, unrecognised: nil)
        case .unrecognised(let text):
            return Reading(language: "und", unrecognised: text)
        }
    }
}

// MARK: - Roles

extension StreamDisposition {

    /// The policy's roles (TRACK-010) for a stream of `type` with these
    /// dispositions — what ordering and selection work from.
    ///
    /// ffmpeg has no flag for an "alternate main mix", so no track is ever
    /// given that role here. `default`, `original` and `dub` are not roles
    /// (they are the default and original-language markers).
    public func policyRoles(for type: StreamType) -> [TrackRole] {
        var roles: [TrackRole] = []
        switch type {
        case .audio:
            if isComment { roles.append(.commentary) }
            // ffmpeg marks audio description `visual_impaired`; MP4's `kind`
            // "description" is read back as visual_impaired + descriptions
            // (checked with ffmpeg 9.0.1), so either flag means AD on audio.
            if isVisualImpaired || isDescriptions { roles.append(.audioDescription) }
            // Music-and-effects, karaoke, lyrics, hearing-impaired audio: roles
            // the policy's audio list does not name — "anything else".
            if isCleanEffects || isKaraoke || isLyrics || isHearingImpaired { roles.append(.other) }
        case .subtitle:
            if isHearingImpaired || isCaptions { roles.append(.sdh) }
            if isForced { roles.append(.forced) }
            if isComment { roles.append(.commentary) }
            // Text descriptions of the picture, lyrics, karaoke: not in the
            // subtitle list (full, SDH, forced, commentary) — "anything else".
            if isDescriptions || isLyrics || isKaraoke || isVisualImpaired { roles.append(.other) }
        case .video, .data, .attachment, .unknown:
            break
        }
        return roles
    }
}

extension MediaStream {

    /// The policy's track type for this stream (TRACK-060).
    public var policyTrackType: TrackType {
        switch streamType {
        case .video: return .video
        case .audio: return .audio
        case .subtitle: return .subtitle
        case .data, .attachment, .unknown: return .other
        }
    }

    /// The stream's roles in the policy's terms (TRACK-010), from its full
    /// dispositions — or, for a stream described before those were kept,
    /// from `isForced` alone.
    public var policyRoles: [TrackRole] {
        let disposition = disposition ?? StreamDisposition(isDefault: isDefault, isForced: isForced)
        return disposition.policyRoles(for: streamType)
    }

    /// Whether the file marks this stream as being in the original language
    /// (LANG-010; ffmpeg's `original`, Matroska's FlagOriginal).
    public var isOriginalLanguage: Bool {
        disposition?.isOriginal ?? false
    }
}
