// ============================================================================
// MeedyaConverter — DiscProtectionDetector
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DiscProtectionType

/// The copy-protection taxonomy required by issue #492's detect-and-warn
/// policy. MeedyaConverter *classifies* protection from public markers so it
/// can refuse to emit a broken artifact; it never circumvents protection.
public enum DiscProtectionType: String, Codable, Sendable, CaseIterable {
    /// No copy protection detected — a raw copy is functional.
    case none = "none"

    /// DVD Content Scramble System.
    case css = "css"

    /// Advanced Access Content System (Blu-ray / HD DVD generation 1).
    case aacs = "aacs"

    /// BD+ security virtual machine (Blu-ray).
    case bdPlus = "bd_plus"

    /// AACS 2.0 (Ultra HD Blu-ray).
    case aacs2 = "aacs2"

    /// A protection-shaped structure that does not match a known scheme
    /// (e.g. a copy-control audio disc with an unreadable extra data session,
    /// or an AACS directory on a disc typed as a plain DVD).
    case unknownStructural = "unknown_structural"
}

// MARK: - DiscProtectionMarkers

/// The PUBLIC-metadata snapshot the detector classifies from.
///
/// Every field here is public disc metadata a caller can gather from a mounted
/// volume listing and the drive/OS-reported disc structure. None of it is key
/// material, and the detector performs no I/O, so by construction it cannot
/// touch keys — it reads only what is already visible without any
/// authentication or decryption.
public struct DiscProtectionMarkers: Codable, Sendable, Equatable {
    /// The disc's type, as already classified elsewhere.
    public var discType: DiscType

    /// Top-level file/directory names of the mounted volume (e.g. `VIDEO_TS`,
    /// `AACS`, `BDSVM`, `BDMV`). Compared case-insensitively.
    public var rootEntryNames: [String]

    /// The copyright-protection-system-type flag from the DVD disc structure
    /// as reported by the drive/OS. This is public metadata (a single flag in
    /// the disc's copyright-management information), not a key.
    public var dvdCopyrightFlagSet: Bool

    /// Version field parsed from the AACS directory's public MKB (Media Key
    /// Block) header, when a caller has it; `nil` otherwise. The MKB header is
    /// public; the media keys inside it are not, and are never read here.
    public var aacsMKBVersionHint: Int?

    /// Whether an audio disc carries an additional data session the OS could
    /// not identify — the structural signature of a copy-control CD that is
    /// not Red Book compliant.
    public var hasUnreadableDataSession: Bool

    public init(
        discType: DiscType,
        rootEntryNames: [String] = [],
        dvdCopyrightFlagSet: Bool = false,
        aacsMKBVersionHint: Int? = nil,
        hasUnreadableDataSession: Bool = false
    ) {
        self.discType = discType
        self.rootEntryNames = rootEntryNames
        self.dvdCopyrightFlagSet = dvdCopyrightFlagSet
        self.aacsMKBVersionHint = aacsMKBVersionHint
        self.hasUnreadableDataSession = hasUnreadableDataSession
    }
}

// MARK: - DiscImagingPolicy

/// The action the imaging flow must take for a given protection type.
public enum DiscImagingPolicy: Sendable, Equatable {
    /// A raw copy is functional — proceed with imaging.
    case proceed

    /// A raw copy would be non-functional; refuse with a user-facing,
    /// British-English reason that also states MeedyaConverter never
    /// circumvents copy protection.
    case refuse(reason: String)
}

// MARK: - DiscProtectionDetector

/// Pure classification of public protection markers, plus the policy mapping
/// that gates imaging.
///
/// The detector is the code home of the issue #492 DRM policy: raw imaging
/// only, never circumvention. It reads public metadata to decide whether a raw
/// copy would even be usable, and — through `policy(for:)` — refuses when it
/// would not, so the flow neither emits a broken artifact nor ever decrypts.
/// For the Audio CD P1 target, a Red Book disc classifies as `.none` and the
/// gate passes; the full taxonomy nonetheless lives here now, unit-tested
/// against synthetic CSS/AACS/BD+/AACS 2 fixtures, so the policy is in code
/// rather than prose.
public struct DiscProtectionDetector: Sendable {

    /// Classify a disc's protection from its public markers. First match wins,
    /// most specific first.
    ///
    /// - Parameter markers: The public-metadata snapshot.
    /// - Returns: The detected protection type.
    public static func detect(markers: DiscProtectionMarkers) -> DiscProtectionType {
        let roots = markers.rootEntryNames.map { $0.uppercased() }
        func hasRoot(_ name: String) -> Bool { roots.contains(name.uppercased()) }

        switch markers.discType {
        case .audioCd:
            // Plain Red Book Audio CDs — the entire P1 target — are
            // unprotected. A copy-control disc betrays itself as an audio disc
            // with an extra, unidentifiable data session.
            return markers.hasUnreadableDataSession ? .unknownStructural : .none

        case .dvdVideo, .dvdAudio:
            // An AACS directory on a DVD-typed disc is a protection-shaped
            // structure that does not fit CSS — classify it structural rather
            // than mis-label it.
            if hasRoot("AACS") { return .unknownStructural }
            // The copyright-protection-system-type field is public disc
            // structure; when set on a DVD it indicates CSS.
            return markers.dvdCopyrightFlagSet ? .css : .none

        case .uhdBluray:
            // UHD Blu-ray with AACS structure is AACS 2.0.
            if hasRoot("AACS") || (markers.aacsMKBVersionHint ?? 0) >= 2 {
                return .aacs2
            }
            // A BD+ VM directory is still the stricter classification.
            if hasRoot("BDSVM") { return .bdPlus }
            return .none

        case .bluray:
            // BD+ discs also carry AACS, but BD+ is the stricter, more
            // specific classification, so it is checked first.
            if hasRoot("BDSVM") { return .bdPlus }
            if hasRoot("AACS") { return .aacs }
            return .none

        default:
            // Any other disc type showing a protection-shaped directory is
            // classified structural; otherwise unprotected.
            if hasRoot("AACS") || hasRoot("BDSVM") { return .unknownStructural }
            return .none
        }
    }

    /// Map a protection type to the imaging policy.
    ///
    /// `.none` proceeds; every protected class refuses with a British-English
    /// explanation of why a raw copy would be non-functional and a statement
    /// that MeedyaConverter detects and warns but never circumvents protection.
    ///
    /// - Parameter protection: The detected protection type.
    /// - Returns: The policy the imaging flow must apply.
    public static func policy(for protection: DiscProtectionType) -> DiscImagingPolicy {
        let neverCircumvent =
            "MeedyaConverter detects and warns about copy protection but never circumvents it."
        switch protection {
        case .none:
            return .proceed
        case .css:
            return .refuse(reason:
                "This DVD is protected by CSS. A raw copy would contain scrambled "
                + "sectors that are unreadable without drive authentication, so the "
                + "image would not play. \(neverCircumvent)")
        case .aacs:
            return .refuse(reason:
                "This Blu-ray is protected by AACS. A raw image would be encrypted "
                + "and unplayable without licensed decryption. \(neverCircumvent)")
        case .bdPlus:
            return .refuse(reason:
                "This Blu-ray is protected by BD+ (and AACS). A raw image would be "
                + "encrypted and unplayable without licensed decryption. \(neverCircumvent)")
        case .aacs2:
            return .refuse(reason:
                "This Ultra HD Blu-ray is protected by AACS 2.0. A raw image would "
                + "be encrypted and unplayable without licensed decryption. \(neverCircumvent)")
        case .unknownStructural:
            return .refuse(reason:
                "This disc has a copy-protection-shaped structure that MeedyaConverter "
                + "cannot classify, so a raw copy is likely to be non-functional. "
                + "\(neverCircumvent)")
        }
    }
}
