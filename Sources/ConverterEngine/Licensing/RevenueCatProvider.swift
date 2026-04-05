// ============================================================================
// MeedyaConverter — RevenueCat Provider (Placeholder)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// This file provides a placeholder `FeatureGateProvider` implementation
// that will wrap the RevenueCat SDK when it is added as a dependency.
//
// RevenueCat provides server-side receipt validation, subscription status
// tracking, cross-platform entitlement management, and analytics — all
// of which complement StoreKit 2 by offloading server infrastructure.
//
// Until RevenueCat is integrated as a package dependency:
//   - The `#if canImport(RevenueCat)` blocks remain inactive
//   - The provider falls back to local entitlement checks (Keychain or
//     UserDefaults cache) when RevenueCat is not available
//   - All public API is defined and documented so that integration is
//     a matter of uncommenting and configuring
//
// Phase 15 — Monetization / Licensing (Issue #311)
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - RevenueCat Import
// ---------------------------------------------------------------------------
// Conditional import: only active when RevenueCat is added to Package.swift
// as a dependency. This allows the file to compile in all build configurations
// without requiring the SDK.
// ---------------------------------------------------------------------------
#if canImport(RevenueCat)
import RevenueCat
#endif

// ---------------------------------------------------------------------------
// MARK: - RevenueCatGateProvider
// ---------------------------------------------------------------------------
/// Entitlement provider that wraps the RevenueCat SDK for server-side
/// subscription and purchase management.
///
/// When the RevenueCat SDK is not available (the common case during
/// development and in App Store builds that use StoreKit directly), this
/// provider falls back to a local entitlement check using the cached
/// level in `FeatureGateManager` or the Keychain license key.
///
/// ### RevenueCat Entitlement Mapping
/// RevenueCat entitlement identifiers are mapped to `EntitlementLevel`:
///
/// | RevenueCat Entitlement ID | EntitlementLevel |
/// |---------------------------|------------------|
/// | `plus`                    | `.plus`          |
/// | `pro`                     | `.pro`           |
///
/// ### Configuration
/// Call `configure(apiKey:)` during app startup (e.g., in the `App.init`):
/// ```swift
/// let provider = RevenueCatGateProvider()
/// provider.configure(apiKey: "appl_your_api_key_here")
/// FeatureGateManager.shared.provider = provider
/// ```
///
/// ### Thread Safety
/// The provider is `@unchecked Sendable` because its mutable state
/// (`isConfigured`, `cachedLevel`) is protected by an `NSLock`.
// ---------------------------------------------------------------------------
public final class RevenueCatGateProvider: FeatureGateProvider, @unchecked Sendable {

    // MARK: Private State

    /// Whether `configure(apiKey:)` has been called successfully.
    private var isConfigured: Bool = false

    /// Locally cached entitlement level, updated after RevenueCat sync.
    private var cachedLevel: EntitlementLevel = .free

    /// Thread-safety lock for mutable state.
    private let lock = NSLock()

    // MARK: RevenueCat Entitlement IDs

    /// The RevenueCat entitlement identifier for Plus tier access.
    private static let plusEntitlementID = "plus"

    /// The RevenueCat entitlement identifier for Pro tier access.
    private static let proEntitlementID = "pro"

    // MARK: Initialiser

    /// Create a new RevenueCat provider.
    ///
    /// The provider starts unconfigured and at the free tier. Call
    /// `configure(apiKey:)` to initialise the RevenueCat SDK.
    public init() {}

    // MARK: Configuration

    /// Configure the RevenueCat SDK with the provided API key.
    ///
    /// This should be called once during app startup, before any
    /// entitlement checks are performed. When RevenueCat is not
    /// available, this method is a no-op that logs a warning.
    ///
    /// - Parameter apiKey: The RevenueCat public API key from the
    ///   RevenueCat dashboard (starts with `appl_` for Apple platforms).
    public func configure(apiKey: String) {
        #if canImport(RevenueCat)
        // Configure the RevenueCat SDK
        Purchases.configure(
            with: .init(withAPIKey: apiKey)
                .with(entitlementVerificationMode: .informational)
        )

        lock.withLock {
            isConfigured = true
        }

        // Perform initial sync
        Task {
            _ = await entitlementLevel()
        }
        #else
        // RevenueCat is not available — attempt local fallback
        lock.withLock {
            isConfigured = false
        }

        // Check Keychain for an activated license key
        if let license = LicenseKeyValidator.loadActiveLicense(), license.isValid {
            lock.withLock {
                cachedLevel = license.entitlementLevel
            }
        }
        #endif
    }

    // MARK: FeatureGateProvider

    /// Determine the user's entitlement level from RevenueCat.
    ///
    /// When RevenueCat is available and configured, this queries the
    /// current customer info and maps active entitlements to the
    /// appropriate `EntitlementLevel`.
    ///
    /// When RevenueCat is not available, falls back to:
    /// 1. The locally cached level
    /// 2. A Keychain license key check
    /// 3. `.free` as the ultimate fallback
    ///
    /// - Returns: The user's current `EntitlementLevel`.
    public func entitlementLevel() async -> EntitlementLevel {
        #if canImport(RevenueCat)
        guard lock.withLock({ isConfigured }) else {
            return localFallbackLevel()
        }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let level = mapEntitlements(customerInfo.entitlements)

            lock.withLock {
                cachedLevel = level
            }

            return level
        } catch {
            // Network error — return cached level
            return lock.withLock { cachedLevel }
        }
        #else
        return localFallbackLevel()
        #endif
    }

    /// Check whether the user is entitled to a specific feature.
    ///
    /// Uses the cached entitlement level for synchronous access.
    /// Call `entitlementLevel()` periodically (or listen for RevenueCat
    /// customer info updates) to keep the cache fresh.
    ///
    /// - Parameter feature: The feature to check.
    /// - Returns: `true` if the cached level meets the feature's requirement.
    public func isEntitled(to feature: GatedFeature) -> Bool {
        let level = lock.withLock { cachedLevel }
        return level >= feature.requiredTier
    }

    // MARK: Private — Entitlement Mapping

    #if canImport(RevenueCat)
    /// Map RevenueCat entitlements to the highest applicable `EntitlementLevel`.
    ///
    /// Pro supersedes Plus — if both are active, Pro is returned.
    ///
    /// - Parameter entitlements: The entitlement info from RevenueCat.
    /// - Returns: The highest `EntitlementLevel` the user is entitled to.
    private func mapEntitlements(_ entitlements: EntitlementInfos) -> EntitlementLevel {
        if entitlements[Self.proEntitlementID]?.isActive == true {
            return .pro
        }
        if entitlements[Self.plusEntitlementID]?.isActive == true {
            return .plus
        }
        return .free
    }
    #endif

    // MARK: Private — Local Fallback

    /// Determine entitlement level using local-only checks.
    ///
    /// Falls back to Keychain license key, then cached level, then `.free`.
    private func localFallbackLevel() -> EntitlementLevel {
        // Check Keychain for an activated license key
        if let license = LicenseKeyValidator.loadActiveLicense(),
           license.isValid {
            let level = license.entitlementLevel
            lock.withLock {
                cachedLevel = level
            }
            return level
        }

        // Return whatever is cached (defaults to .free)
        return lock.withLock { cachedLevel }
    }
}
