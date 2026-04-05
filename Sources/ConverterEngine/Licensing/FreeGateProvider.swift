// ============================================================================
// MeedyaConverter — FreeGateProvider (Default Entitlement Provider)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// The `FreeGateProvider` is the default entitlement provider used when no
// monetization backend is configured. It always returns `.free`, granting
// access only to the free-tier features.
//
// This provider is used:
//   - During development and testing
//   - As a fallback when StoreKit, RevenueCat, or license key validation
//     is not yet configured or fails
//   - In CI/CD environments where no purchase state exists
//
// Phase 15 — Monetization / Licensing (Issue #307)
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - FreeGateProvider
// ---------------------------------------------------------------------------
/// Default entitlement provider that always returns the free tier.
///
/// This is the zero-configuration baseline: when no purchase, subscription,
/// or license key has been validated, the user has access to the free-tier
/// feature set only.
///
/// ### Thread Safety
/// `FreeGateProvider` is fully `Sendable` — it holds no mutable state and
/// all methods return compile-time constants.
///
/// ### Usage
/// ```swift
/// let provider = FreeGateProvider()
/// let level = await provider.entitlementLevel() // .free
/// provider.isEntitled(to: .basicEncoding)       // true
/// provider.isEntitled(to: .parallelEncoding)    // false
/// ```
// ---------------------------------------------------------------------------
public struct FreeGateProvider: FeatureGateProvider, Sendable {

    // MARK: Initialiser

    /// Create a new free-tier provider.
    public init() {}

    // MARK: FeatureGateProvider

    /// Always returns `.free`.
    ///
    /// The free tier grants access to basic encoding, built-in profiles,
    /// video passthrough, the CLI, and the activity log.
    ///
    /// - Returns: `.free`
    public func entitlementLevel() async -> EntitlementLevel {
        .free
    }

    /// Check whether a feature is available at the free tier.
    ///
    /// Only features whose `requiredTier` is `.free` return `true`.
    ///
    /// - Parameter feature: The feature to check.
    /// - Returns: `true` if the feature is in the free tier.
    public func isEntitled(to feature: GatedFeature) -> Bool {
        feature.requiredTier == .free
    }
}
