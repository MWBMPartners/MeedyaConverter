// ============================================================================
// MeedyaConverter — SettingsCategory (Issue #506 commit 4)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// The groups a settings file is divided into. When someone exports or
// imports their settings, they tick the groups they want; each exportable
// setting in `SettingsKeyRegistry` belongs to exactly one of these groups.
//
// The raw values ("general", "encoding", …) are written into the settings
// file itself as the names of its sections, so they must never be renamed.
// A renamed group would make every file written by an older version look
// like it contained a group this version does not know.
//
// Owner decisions applied here (from `.claude/plans/settings-export-import-plan.md`,
// §9, all accepted):
//   - encoding profiles are their own group (question 7);
//   - "This Mac only" is OFF by default, on export as well as import
//     (question 3), and carries a warning explaining why.
//
// This file only describes the groups. Nothing reads or writes a settings
// file yet: that is a later commit of #506.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsCategory

/// A group of settings that can be exported and imported together.
public enum SettingsCategory: String, Codable, CaseIterable, Sendable {

    /// Appearance, notifications, keyboard shortcuts, the update channel and
    /// general behaviour.
    case general

    /// How files are converted: the default profile, file handling, the
    /// filename template, conditional rules, saved pipelines, vector
    /// conversion options, Audio CD options and automatic tagging.
    case encoding

    /// The encoding profiles the person made themselves. This group is not
    /// made of settings keys at all: it is the profiles file
    /// (`Profiles/user_profiles.json`), see `SettingsKeyRegistry.fileStores`.
    case encodingProfiles

    /// Addresses, ports, user names and on/off options for other services.
    /// Never passwords, keys, tokens or webhook addresses: those are marked
    /// "never" in the registry and simply have no way into this group.
    case connections

    /// Settings that describe the Mac they were made on: where tools are
    /// installed, and the CD drive's model and read offset.
    case thisMac

    // MARK: Wording shown to people

    /// A short title for the tick box.
    public var displayName: String {
        switch self {
        case .general:          return "General and appearance"
        case .encoding:         return "Encoding and output"
        case .encodingProfiles: return "Your encoding profiles"
        case .connections:      return "Connections to other services"
        case .thisMac:          return "This Mac only"
        }
    }

    /// One or two plain sentences saying what the group contains.
    public var explanation: String {
        switch self {
        case .general:
            return "Theme, notifications, keyboard shortcuts, the update channel, "
                + "and how the app behaves."
        case .encoding:
            return "Default profile, what happens to files before and after "
                + "converting, the filename template, conditional rules, saved "
                + "pipelines, vector conversion options, Audio CD options and "
                + "automatic tagging."
        case .encodingProfiles:
            return "The encoding profiles you made. The built-in profiles are "
                + "never included, because every copy of MeedyaConverter already "
                + "has them."
        case .connections:
            return "Server addresses, ports, user names and options for email, "
                + "media servers, webhooks, MeedyaDB, the render farm, SFTP, "
                + "cloud storage and team profiles. Passwords, keys, tokens and "
                + "webhook addresses are never included: you enter those again "
                + "on the other Mac."
        case .thisMac:
            return "Where FFmpeg and other tools are installed on this Mac, and "
                + "your CD drive's model and read offset."
        }
    }

    /// Whether the tick box starts ticked. Only "This Mac only" starts
    /// unticked (owner decision: off by default on export and import).
    public var includedByDefault: Bool {
        switch self {
        case .thisMac:
            return false
        case .general, .encoding, .encodingProfiles, .connections:
            return true
        }
    }

    /// A caution shown next to the tick box, or `nil` when none is needed.
    public var warning: String? {
        switch self {
        case .thisMac:
            return "These describe the Mac the file came from: where FFmpeg and "
                + "other tools are installed, and your CD drive's model and read "
                + "offset. Only include them if this Mac has the same tools in "
                + "the same places and the same CD drive. A wrong read offset "
                + "makes good CD rips fail their AccurateRip check."
        case .general, .encoding, .encodingProfiles, .connections:
            return nil
        }
    }
}
