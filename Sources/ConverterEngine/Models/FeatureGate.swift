// ============================================================================
// MeedyaConverter — Feature Gating System
// Copyright © 2026–2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ProductTier

/// The product tier levels that determine which features are available.
///
/// Features can be gated behind tiers to support a freemium business model.
/// The tier definitions and pricing are decided separately — this is the
/// architecture only.
public enum ProductTier: String, Codable, Sendable, Comparable {
    /// Free tier — core conversion features available to all users.
    /// Includes: basic encoding, common codecs, file import/export.
    case free

    /// Pro tier — professional features for power users.
    /// Includes: advanced audio processing, adaptive streaming, batch automation.
    case pro

    /// Studio tier — specialist/premium features.
    /// Includes: disc ripping/authoring, AI features, forensic watermarking, DCP.
    case studio

    /// The numeric rank used for tier comparison.
    /// Higher rank = more features available.
    private var rank: Int {
        switch self {
        case .free: return 0
        case .pro: return 1
        case .studio: return 2
        }
    }

    /// Compare tiers by rank. Higher tiers include all lower tier features.
    public static func < (lhs: ProductTier, rhs: ProductTier) -> Bool {
        return lhs.rank < rhs.rank
    }
}

// MARK: - Feature

/// Identifies a specific feature that can be gated behind a product tier.
///
/// Each feature has a minimum required tier. Features at the `free` tier
/// are always available. Features at `pro` or `studio` tiers are only
/// available when the user's active tier meets or exceeds the requirement.
public struct Feature: Hashable, Sendable {
    /// A unique string identifier for this feature (e.g., "virtual_upmix").
    public let identifier: String

    /// Human-readable display name for this feature (e.g., "Virtual Surround Upmixing").
    public let displayName: String

    /// The minimum product tier required to access this feature.
    public let requiredTier: ProductTier

    /// A short description of why this feature is gated (shown in upgrade prompts).
    public let upgradeDescription: String?

    public init(
        identifier: String,
        displayName: String,
        requiredTier: ProductTier,
        upgradeDescription: String? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.requiredTier = requiredTier
        self.upgradeDescription = upgradeDescription
    }
}

// MARK: - FeatureGate

/// Protocol for checking whether features are available at the current product tier.
///
/// The default implementation (`DefaultFeatureGate`) unlocks all features
/// (equivalent to Studio tier). When a monetisation strategy is implemented,
/// a concrete gate can check the user's purchase status, subscription, or
/// license key.
///
/// Usage:
/// ```swift
/// let gate = DefaultFeatureGate()
/// if gate.isAvailable(.virtualUpmix) {
///     // Show upmix controls
/// } else {
///     // Show upgrade prompt
/// }
/// ```
public protocol FeatureGateProtocol: Sendable {
    /// Check whether a specific feature is available at the current tier.
    func isAvailable(_ feature: Feature) -> Bool

    /// Get the current active product tier.
    var currentTier: ProductTier { get }

    /// Get the tier required for a specific feature.
    func requiredTier(for feature: Feature) -> ProductTier
}

// MARK: - DefaultFeatureGate

/// Default feature gate that unlocks ALL features (Studio tier).
///
/// This is used during development and in builds where no monetisation
/// is active. All feature checks return `true`.
///
/// When monetisation is implemented, replace this with a gate that
/// checks the user's actual purchase/subscription status.
public final class DefaultFeatureGate: FeatureGateProtocol, @unchecked Sendable {
    /// The current active tier. Defaults to `.studio` (all features unlocked).
    public private(set) var currentTier: ProductTier

    /// Create a gate with a specific tier (default: `.studio` = all unlocked).
    public init(tier: ProductTier = .studio) {
        self.currentTier = tier
    }

    /// Check whether a feature is available at the current tier.
    /// A feature is available if the current tier is >= the feature's required tier.
    public func isAvailable(_ feature: Feature) -> Bool {
        return currentTier >= feature.requiredTier
    }

    /// Get the minimum tier required for a specific feature.
    public func requiredTier(for feature: Feature) -> ProductTier {
        return feature.requiredTier
    }

    /// Update the active tier (e.g., after a purchase or subscription change).
    public func setTier(_ tier: ProductTier) {
        self.currentTier = tier
    }
}

// MARK: - Well-Known Features

/// Catalogue of all gated features with their tier requirements.
///
/// During development, all features default to `.free` (available to everyone).
/// Tier assignments can be adjusted when monetisation decisions are made.
extension Feature {

    // MARK: Free Tier Features

    /// Basic video/audio encoding with common codecs.
    public static let basicEncoding = Feature(
        identifier: "basic_encoding",
        displayName: "Basic Encoding",
        requiredTier: .free
    )

    /// Stream passthrough (copy without re-encoding).
    public static let passthrough = Feature(
        identifier: "passthrough",
        displayName: "Stream Passthrough",
        requiredTier: .free
    )

    /// Media file probing and inspection.
    public static let mediaProbe = Feature(
        identifier: "media_probe",
        displayName: "Media Inspection",
        requiredTier: .free
    )

    /// Encoding profile management.
    public static let profileManagement = Feature(
        identifier: "profile_management",
        displayName: "Encoding Profiles",
        requiredTier: .free
    )

    // MARK: Pro Tier Features

    /// HDR preservation and format conversion (HDR10, HDR10+, DV, HLG).
    public static let hdrProcessing = Feature(
        identifier: "hdr_processing",
        displayName: "HDR Processing",
        requiredTier: .pro,
        upgradeDescription: "Preserve and convert HDR formats including Dolby Vision"
    )

    /// HLS/MPEG-DASH adaptive streaming preparation.
    public static let adaptiveStreaming = Feature(
        identifier: "adaptive_streaming",
        displayName: "Adaptive Streaming (HLS/DASH)",
        requiredTier: .pro,
        upgradeDescription: "Create multi-bitrate streaming content with manifests"
    )

    /// Audio normalization (EBU R128, ReplayGain).
    public static let audioNormalization = Feature(
        identifier: "audio_normalization",
        displayName: "Audio Normalization",
        requiredTier: .pro,
        upgradeDescription: "EBU R128 loudness normalization and ReplayGain"
    )

    /// Virtual surround upmixing.
    public static let virtualUpmix = Feature(
        identifier: "virtual_upmix",
        displayName: "Virtual Surround Upmixing",
        requiredTier: .pro,
        upgradeDescription: "Algorithmically upmix stereo to 5.1/7.1 surround"
    )

    /// Audio channel content analysis.
    public static let channelAnalysis = Feature(
        identifier: "channel_analysis",
        displayName: "Audio Channel Analysis",
        requiredTier: .pro,
        upgradeDescription: "Detect actual channel content vs declared configuration"
    )

    /// Watch folder / batch automation.
    public static let watchFolders = Feature(
        identifier: "watch_folders",
        displayName: "Watch Folder Automation",
        requiredTier: .pro,
        upgradeDescription: "Monitor folders for new files and auto-encode"
    )

    /// Cloud upload to storage providers.
    public static let cloudUpload = Feature(
        identifier: "cloud_upload",
        displayName: "Cloud Upload",
        requiredTier: .pro,
        upgradeDescription: "Upload to S3, Azure, Cloudflare Stream, and more"
    )

    // MARK: Studio Tier Features

    /// Optical disc ripping.
    public static let discRipping = Feature(
        identifier: "disc_ripping",
        displayName: "Optical Disc Ripping",
        requiredTier: .studio,
        upgradeDescription: "Rip Audio CD, DVD, Blu-ray, and 19 more disc types"
    )

    /// Disc image creation and burning.
    public static let discAuthoring = Feature(
        identifier: "disc_authoring",
        displayName: "Disc Authoring & Burning",
        requiredTier: .studio,
        upgradeDescription: "Create disc images and burn to physical media"
    )

    /// Forensic watermarking.
    public static let forensicWatermark = Feature(
        identifier: "forensic_watermark",
        displayName: "Forensic Watermarking",
        requiredTier: .studio,
        upgradeDescription: "Embed invisible watermarks for content protection"
    )

    /// DCP (Digital Cinema Package) creation.
    public static let dcpCreation = Feature(
        identifier: "dcp_creation",
        displayName: "DCP Creation",
        requiredTier: .studio,
        upgradeDescription: "Create Digital Cinema Packages for theatrical distribution"
    )

    /// AI-powered features (captioning, translation, upscaling, HDR enhancement).
    public static let aiFeatures = Feature(
        identifier: "ai_features",
        displayName: "AI-Powered Features",
        requiredTier: .studio,
        upgradeDescription: "AI captioning, translation, upscaling, and HDR enhancement"
    )
}
