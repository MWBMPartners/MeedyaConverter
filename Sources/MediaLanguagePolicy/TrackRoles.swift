// ============================================================================
// MeedyaConverter — MediaLanguagePolicy / TrackRoles
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Job "role ordering" of policy §9: what a track is for, apart from its
// language (TRACK-010), and the order roles are placed in within one
// language group (TRACK-050).
//
// A track with no role is the main programme (audio) or the full subtitles.
// A track with several roles is PLACED by the one latest in its type's list
// (so a forced SDH subtitle is placed as forced), and a role the list does
// not know counts as "other" (revision 3 of the policy). Every ordering,
// menu and selection rule that talks about "role" means this placing role.
// ============================================================================

import Foundation

// MARK: - TrackType

/// The kind of track, for ordering (TRACK-060: video, then audio, then
/// subtitles, then anything else — never interleaved).
public enum TrackType: String, Sendable, Hashable, Codable, CaseIterable {
    case video
    case audio
    case subtitle
    case other

    /// The position of this type in stored order (TRACK-060).
    var storedOrder: Int {
        switch self {
        case .video: return 0
        case .audio: return 1
        case .subtitle: return 2
        case .other: return 3
        }
    }
}

// MARK: - TrackRole

/// A track's role (TRACK-010). Raw values are the words the policy's test
/// cases use.
///
/// `unrecognised` stands for a role word from elsewhere that the policy does
/// not define; it is placed as `other` (TRACK-050).
public enum TrackRole: Sendable, Hashable, Codable {
    case alternate
    case audioDescription
    case commentary
    case sdh
    case forced
    case other
    case unrecognised(String)

    /// Reads one of the policy's role words (`audio_description`, `sdh` …).
    /// Anything else is kept as `.unrecognised` and placed as other.
    public init(word: String) {
        switch word {
        case "alternate": self = .alternate
        case "audio_description": self = .audioDescription
        case "commentary": self = .commentary
        case "sdh": self = .sdh
        case "forced": self = .forced
        case "other": self = .other
        default: self = .unrecognised(word)
        }
    }

    /// The policy's word for this role.
    public var word: String {
        switch self {
        case .alternate: return "alternate"
        case .audioDescription: return "audio_description"
        case .commentary: return "commentary"
        case .sdh: return "sdh"
        case .forced: return "forced"
        case .other: return "other"
        case .unrecognised(let word): return word
        }
    }
}

// MARK: - Role order (TRACK-050)

/// Role ranks within one language group, for each track type (TRACK-050).
///
/// - Audio: main programme 0 → alternate 1 → audio description 2 →
///   commentary 3 → anything else 4.
/// - Subtitles: full 0 → SDH/captions 1 → forced 2 → commentary 3 →
///   anything else 4.
/// - Video and other types have no role order (everything ranks 0).
public enum TrackRoleOrder {

    /// The rank of one role for a track of `type`. A role that is not in
    /// the type's list (an audio role on a subtitle, an unrecognised word)
    /// ranks as "anything else".
    public static func rank(of role: TrackRole, for type: TrackType?) -> Int {
        switch type {
        case .audio:
            switch role {
            case .alternate: return 1
            case .audioDescription: return 2
            case .commentary: return 3
            default: return 4
            }
        case .subtitle:
            switch role {
            case .sdh: return 1
            case .forced: return 2
            case .commentary: return 3
            default: return 4
            }
        case .video, .other, .none:
            return 0
        }
    }

    /// The rank of the role a track is PLACED by: the latest of its roles
    /// in its type's list (TRACK-050), or 0 (main / full) with no roles.
    public static func placingRank(of roles: [TrackRole], for type: TrackType?) -> Int {
        roles.map { rank(of: $0, for: type) }.max() ?? 0
    }

    /// Roles sorted into TRACK-050 order for `type` (a stable sort, so roles
    /// of equal rank keep their given order) — the order labels list them in.
    public static func sorted(_ roles: [TrackRole], for type: TrackType?) -> [TrackRole] {
        LanguageTagCanonicaliser.stableSorted(roles) { rank(of: $0, for: type) < rank(of: $1, for: type) }
    }
}
