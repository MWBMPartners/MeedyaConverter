// ============================================================================
// MeedyaConverter — Feature Gating System (Monetization)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// This file defines the entitlement and feature gating architecture for the
// MeedyaConverter monetization system. It provides:
//
//   - `EntitlementLevel` — the three-tier access model (Free, Plus, Pro)
//   - `GatedFeature` — an exhaustive enumeration of all gatable features
//     with their tier assignments
//   - `FeatureGateProvider` — the protocol that concrete providers implement
//     to determine the user's current entitlement
//   - `FeatureGateManager` — the singleton manager that mediates all feature
//     access checks throughout the application
//
// Phase 15 — Monetization / Licensing (Issue #307)
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - EntitlementLevel
// ---------------------------------------------------------------------------
/// Represents the three-tier access model for MeedyaConverter.
///
/// Entitlement levels are hierarchical: a higher level always includes all
/// features from lower levels. The `Comparable` conformance encodes this
/// ordering so that a simple `>=` check suffices for access decisions.
///
/// | Level | Audience           | Revenue Model                     |
/// |-------|--------------------|-----------------------------------|
/// | free  | Everyone           | No payment required               |
/// | plus  | Enthusiasts        | One-time purchase (lifetime)      |
/// | pro   | Professionals      | Monthly or annual subscription    |
// ---------------------------------------------------------------------------
public enum EntitlementLevel: String, Codable, Sendable, Comparable {

    /// Free tier — core encoding features available to all users at no cost.
    /// Includes basic encoding, built-in profiles, video passthrough, CLI
    /// access, and the activity log.
    case free

    /// Plus tier — expanded features for enthusiasts via a one-time purchase.
    /// Includes per-stream encoding, custom profiles, disc burning, image
    /// conversion, cloud upload, parallel encoding, watch folders, encoding
    /// pipelines, post-encode actions, scheduled encoding, and advanced
    /// metadata editing.
    case plus

    /// Pro tier — the full professional suite via monthly or annual subscription.
    /// Includes all Plus features plus AI upscaling, AI HDR enhancement,
    /// AI voice isolation, AI audio translation, AI smart crop, VMAF scoring,
    /// bitrate heatmap, scene detection, and priority support.
    case pro

    // MARK: Comparable

    /// The numeric rank used for hierarchical comparison.
    /// Higher rank grants access to more features.
    private var rank: Int {
        switch self {
        case .free:  return 0
        case .plus:  return 1
        case .pro:   return 2
        }
    }

    /// Compare entitlement levels by rank.
    /// A higher entitlement level includes all features from lower levels.
    public static func < (lhs: EntitlementLevel, rhs: EntitlementLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    // MARK: Display

    /// Human-readable display name for the entitlement level.
    public var displayName: String {
        switch self {
        case .free:  return "Free"
        case .plus:  return "Plus"
        case .pro:   return "Pro"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - GatedFeature
// ---------------------------------------------------------------------------
/// An exhaustive enumeration of all features that can be gated behind an
/// entitlement level.
///
/// Each case maps to a specific capability within MeedyaConverter. The
/// `requiredTier` computed property defines the minimum `EntitlementLevel`
/// needed to access the feature. Features at the `.free` tier are always
/// available to all users.
///
/// The tier assignments are:
///
/// **Free** — basicEncoding, builtInProfiles, videoPassthrough, cli, activityLog
///
/// **Plus** — perStreamEncoding, customProfiles, discBurning, imageConversion,
/// cloudUpload, parallelEncoding, watchFolder, encodingPipelines,
/// postEncodeActions, scheduledEncoding, advancedMetadata
///
/// **Pro** — aiUpscaling, aiHDREnhancement, aiVoiceIsolation,
/// aiAudioTranslation, aiSmartCrop, vmafScoring, bitrateHeatmap,
/// sceneDetection, prioritySupport
// ---------------------------------------------------------------------------
public enum GatedFeature: String, Codable, Sendable, CaseIterable {

    // MARK: Free Tier Features

    /// Basic video/audio encoding with common codecs and presets.
    case basicEncoding

    /// Access to the built-in encoding profiles (Web Standard, Archive, etc.).
    case builtInProfiles

    /// Stream passthrough (copy without re-encoding).
    case videoPassthrough

    /// Command-line interface via `meedya-convert`.
    case cli

    /// Unified activity log for monitoring encoding operations.
    case activityLog

    // MARK: Plus Tier Features

    /// Per-stream encoding configuration (individual codec/quality per stream).
    case perStreamEncoding

    /// Create, edit, import, and export custom encoding profiles.
    case customProfiles

    /// Burn encoded content to optical disc media.
    case discBurning

    /// Batch image format conversion (HEIF, JPEG, PNG, WebP, TIFF, etc.).
    case imageConversion

    /// Upload encoded files to cloud storage (S3, Azure, Cloudflare, etc.).
    case cloudUpload

    /// Encode multiple jobs simultaneously using parallel workers.
    case parallelEncoding

    /// Monitor folders for new files and auto-encode on arrival.
    case watchFolder

    /// Multi-step encoding pipelines with branching and conditional logic.
    case encodingPipelines

    /// Actions triggered after encoding completes (move, rename, notify, etc.).
    case postEncodeActions

    /// Schedule encoding jobs to run at specific dates and times.
    case scheduledEncoding

    /// Advanced metadata editing beyond basic tags (chapter marks, etc.).
    case advancedMetadata

    // MARK: Pro Tier Features

    /// AI-powered video upscaling (2x, 4x resolution enhancement).
    case aiUpscaling

    /// AI-powered HDR enhancement and tone mapping.
    case aiHDREnhancement

    /// AI-powered voice isolation from background audio.
    case aiVoiceIsolation

    /// AI-powered audio translation and dubbing.
    case aiAudioTranslation

    /// AI-powered smart cropping with subject detection.
    case aiSmartCrop

    /// VMAF (Video Multi-Method Assessment Fusion) quality scoring.
    case vmafScoring

    /// Per-frame bitrate heatmap visualisation.
    case bitrateHeatmap

    /// Automatic scene boundary detection and splitting.
    case sceneDetection

    /// Priority email and chat support from the development team.
    case prioritySupport

    // MARK: Tier Assignment

    /// The minimum entitlement level required to access this feature.
    ///
    /// Used by `FeatureGateManager` and UI code to determine whether a
    /// feature should be enabled or shown behind a paywall prompt.
    public var requiredTier: EntitlementLevel {
        switch self {
        // Free tier — always available
        case .basicEncoding, .builtInProfiles, .videoPassthrough,
             .cli, .activityLog:
            return .free

        // Plus tier — one-time purchase
        case .perStreamEncoding, .customProfiles, .discBurning,
             .imageConversion, .cloudUpload, .parallelEncoding,
             .watchFolder, .encodingPipelines, .postEncodeActions,
             .scheduledEncoding, .advancedMetadata:
            return .plus

        // Pro tier — subscription
        case .aiUpscaling, .aiHDREnhancement, .aiVoiceIsolation,
             .aiAudioTranslation, .aiSmartCrop, .vmafScoring,
             .bitrateHeatmap, .sceneDetection, .prioritySupport:
            return .pro
        }
    }

    // MARK: Display

    /// Human-readable display name for this feature.
    public var displayName: String {
        switch self {
        case .basicEncoding:      return "Basic Encoding"
        case .builtInProfiles:    return "Built-in Profiles"
        case .videoPassthrough:   return "Video Passthrough"
        case .cli:                return "Command Line Interface"
        case .activityLog:        return "Activity Log"
        case .perStreamEncoding:  return "Per-Stream Encoding"
        case .customProfiles:     return "Custom Profiles"
        case .discBurning:        return "Disc Burning"
        case .imageConversion:    return "Image Conversion"
        case .cloudUpload:        return "Cloud Upload"
        case .parallelEncoding:   return "Parallel Encoding"
        case .watchFolder:        return "Watch Folder"
        case .encodingPipelines:  return "Encoding Pipelines"
        case .postEncodeActions:  return "Post-Encode Actions"
        case .scheduledEncoding:  return "Scheduled Encoding"
        case .advancedMetadata:   return "Advanced Metadata"
        case .aiUpscaling:        return "AI Upscaling"
        case .aiHDREnhancement:   return "AI HDR Enhancement"
        case .aiVoiceIsolation:   return "AI Voice Isolation"
        case .aiAudioTranslation: return "AI Audio Translation"
        case .aiSmartCrop:        return "AI Smart Crop"
        case .vmafScoring:        return "VMAF Scoring"
        case .bitrateHeatmap:     return "Bitrate Heatmap"
        case .sceneDetection:     return "Scene Detection"
        case .prioritySupport:    return "Priority Support"
        }
    }

    /// Short description of what the feature provides, suitable for
    /// paywall comparison tables and upgrade prompts.
    public var featureDescription: String {
        switch self {
        case .basicEncoding:      return "Encode video and audio with common codecs"
        case .builtInProfiles:    return "Use pre-configured encoding presets"
        case .videoPassthrough:   return "Copy streams without re-encoding"
        case .cli:                return "Headless encoding via meedya-convert"
        case .activityLog:        return "Monitor encoding progress and events"
        case .perStreamEncoding:  return "Configure codec and quality per stream"
        case .customProfiles:     return "Create and manage your own profiles"
        case .discBurning:        return "Burn to DVD, Blu-ray, and other media"
        case .imageConversion:    return "Convert between image formats in batch"
        case .cloudUpload:        return "Upload to S3, Azure, Cloudflare, and more"
        case .parallelEncoding:   return "Encode multiple files simultaneously"
        case .watchFolder:        return "Auto-encode new files in watched folders"
        case .encodingPipelines:  return "Build multi-step encoding workflows"
        case .postEncodeActions:  return "Run actions after encoding completes"
        case .scheduledEncoding:  return "Schedule encodes for specific times"
        case .advancedMetadata:   return "Edit chapters, tags, and artwork"
        case .aiUpscaling:        return "Upscale video resolution with AI"
        case .aiHDREnhancement:   return "Enhance SDR to HDR with AI"
        case .aiVoiceIsolation:   return "Isolate vocals from background audio"
        case .aiAudioTranslation: return "Translate and dub audio with AI"
        case .aiSmartCrop:        return "Smart crop with subject detection"
        case .vmafScoring:        return "Measure perceptual video quality"
        case .bitrateHeatmap:     return "Visualise per-frame bitrate distribution"
        case .sceneDetection:     return "Detect and split at scene boundaries"
        case .prioritySupport:    return "Priority access to support channels"
        }
    }

    // MARK: Tier Grouping

    /// All features available at the free tier.
    public static var freeFeatures: [GatedFeature] {
        allCases.filter { $0.requiredTier == .free }
    }

    /// All features that require at least the plus tier.
    public static var plusFeatures: [GatedFeature] {
        allCases.filter { $0.requiredTier == .plus }
    }

    /// All features that require the pro tier.
    public static var proFeatures: [GatedFeature] {
        allCases.filter { $0.requiredTier == .pro }
    }
}

// ---------------------------------------------------------------------------
// MARK: - FeatureGateProvider
// ---------------------------------------------------------------------------
/// Protocol that concrete entitlement providers must implement.
///
/// A provider encapsulates the logic for determining the user's current
/// entitlement level — whether from StoreKit purchases, a license key,
/// RevenueCat, or any other source.
///
/// Conforming types must be `Sendable` so they can be safely referenced
/// from any actor or concurrent context.
///
/// Implementations:
///   - `FreeGateProvider` — always returns `.free` (default)
///   - `RevenueCatGateProvider` — wraps RevenueCat SDK (placeholder)
///   - Custom providers via `StoreManager` for StoreKit 2 integration
// ---------------------------------------------------------------------------
public protocol FeatureGateProvider: Sendable {

    /// Determine the user's current entitlement level.
    ///
    /// This method is async because some providers need to query a remote
    /// service (e.g., RevenueCat, server-side license validation) to
    /// determine the user's tier.
    ///
    /// - Returns: The user's current `EntitlementLevel`.
    func entitlementLevel() async -> EntitlementLevel

    /// Check whether the user is entitled to a specific feature.
    ///
    /// The default implementation compares the feature's required tier
    /// against the provider's cached entitlement level. Providers may
    /// override this for more granular entitlement logic (e.g., individual
    /// feature add-ons).
    ///
    /// - Parameter feature: The feature to check access for.
    /// - Returns: `true` if the user can access the feature.
    func isEntitled(to feature: GatedFeature) -> Bool
}

// ---------------------------------------------------------------------------
// MARK: - FeatureGateManager
// ---------------------------------------------------------------------------
/// Singleton manager that mediates all feature access checks.
///
/// `FeatureGateManager` holds a reference to the active `FeatureGateProvider`
/// and provides convenience methods for checking entitlements. It also
/// caches the last-known entitlement level in `UserDefaults` for offline
/// access, with a configurable expiry window.
///
/// Usage:
/// ```swift
/// // Check if a feature is available
/// if FeatureGateManager.shared.isEntitled(to: .parallelEncoding) {
///     // Enable parallel encoding UI
/// }
///
/// // Swap provider at runtime (e.g., after StoreKit sync)
/// FeatureGateManager.shared.provider = myStoreKitProvider
/// ```
///
/// ### Thread Safety
/// The manager is `@unchecked Sendable` because its mutable state (`provider`
/// and cached level) is protected by an `NSLock`. All public methods are
/// safe to call from any thread.
// ---------------------------------------------------------------------------
public final class FeatureGateManager: @unchecked Sendable {

    // MARK: Singleton

    /// The shared singleton instance used throughout the application.
    public static let shared = FeatureGateManager()

    // MARK: Configuration

    /// The active entitlement provider.
    ///
    /// Defaults to `FreeGateProvider()` (all users start at the free tier).
    /// Swap this at runtime to integrate with StoreKit, RevenueCat, or
    /// license key validation.
    public var provider: FeatureGateProvider {
        get { lock.withLock { _provider } }
        set { lock.withLock { _provider = newValue } }
    }

    // MARK: Private State

    /// The backing storage for the provider, protected by `lock`.
    private var _provider: FeatureGateProvider

    /// The cached entitlement level for offline access.
    private var _cachedLevel: EntitlementLevel?

    /// Thread-safety lock for mutable state.
    private let lock = NSLock()

    // MARK: Cache Keys

    /// UserDefaults key for the cached entitlement level raw value.
    private static let cachedLevelKey = "Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel"

    /// UserDefaults key for the cache expiry timestamp.
    private static let cacheExpiryKey = "Ltd.MWBMpartners.MeedyaConverter.entitlementCacheExpiry"

    /// How long the cached entitlement level remains valid (24 hours).
    private static let cacheValidityInterval: TimeInterval = 24 * 60 * 60

    // MARK: Initialiser

    /// Create a new manager with the default free-tier provider.
    ///
    /// This initialiser is private to enforce singleton usage via `shared`.
    private init() {
        _provider = FreeGateProvider()

        // Restore cached level from UserDefaults if not expired
        if let rawValue = UserDefaults.standard.string(forKey: Self.cachedLevelKey),
           let level = EntitlementLevel(rawValue: rawValue),
           let expiry = UserDefaults.standard.object(forKey: Self.cacheExpiryKey) as? Date,
           expiry > Date() {
            _cachedLevel = level
        }
    }

    // MARK: Entitlement Checks

    /// Check whether the user is entitled to a specific gated feature.
    ///
    /// This method first checks the provider directly. If the provider's
    /// `isEntitled(to:)` method is synchronous (as most are), the result
    /// is returned immediately. The cached level is used as a fallback
    /// when offline.
    ///
    /// - Parameter feature: The feature to check access for.
    /// - Returns: `true` if the user can access the feature.
    public func isEntitled(to feature: GatedFeature) -> Bool {
        let providerCopy = lock.withLock { _provider }
        if providerCopy.isEntitled(to: feature) {
            return true
        }

        // Fallback to cached level for offline scenarios
        if let cached = lock.withLock({ _cachedLevel }) {
            return cached >= feature.requiredTier
        }

        // If no cache and provider says no, feature is not available
        return false
    }

    /// Get the user's current entitlement level.
    ///
    /// Returns the cached level if available and not expired, otherwise
    /// falls back to `.free`.
    ///
    /// For an up-to-date level that queries the provider asynchronously,
    /// use `refreshEntitlementLevel()`.
    ///
    /// - Returns: The current `EntitlementLevel`.
    public func currentLevel() -> EntitlementLevel {
        lock.withLock {
            _cachedLevel ?? .free
        }
    }

    /// Refresh the entitlement level from the active provider.
    ///
    /// Queries the provider asynchronously, updates the cached level,
    /// and persists it to UserDefaults for offline access.
    ///
    /// - Returns: The refreshed `EntitlementLevel`.
    @discardableResult
    public func refreshEntitlementLevel() async -> EntitlementLevel {
        let providerCopy = lock.withLock { _provider }
        let level = await providerCopy.entitlementLevel()

        lock.withLock {
            _cachedLevel = level
        }

        // Persist to UserDefaults with expiry
        UserDefaults.standard.set(level.rawValue, forKey: Self.cachedLevelKey)
        UserDefaults.standard.set(
            Date().addingTimeInterval(Self.cacheValidityInterval),
            forKey: Self.cacheExpiryKey
        )

        return level
    }

    /// Clear the cached entitlement level.
    ///
    /// Call this when the user signs out, deactivates their license, or
    /// when you need to force a fresh check from the provider.
    public func clearCache() {
        lock.withLock {
            _cachedLevel = nil
        }
        UserDefaults.standard.removeObject(forKey: Self.cachedLevelKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheExpiryKey)
    }

    /// All features the user is currently entitled to.
    ///
    /// Useful for populating feature comparison tables and "what you get"
    /// lists in the paywall UI.
    public var entitledFeatures: [GatedFeature] {
        GatedFeature.allCases.filter { isEntitled(to: $0) }
    }

    /// All features the user is NOT entitled to.
    ///
    /// Useful for showing upgrade prompts and "unlock with Plus/Pro" badges.
    public var lockedFeatures: [GatedFeature] {
        GatedFeature.allCases.filter { !isEntitled(to: $0) }
    }
}
