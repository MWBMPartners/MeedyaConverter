// ============================================================================
// MeedyaConverter — Product Catalog (App Store Product Definitions)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// This file defines the product catalog for MeedyaConverter's in-app
// purchases and subscriptions. It maps App Store product identifiers to
// entitlement levels and provides structured data for the paywall UI.
//
// Product structure:
//   - Plus (lifetime) — one-time purchase, unlocks Plus features forever
//   - Pro Monthly     — recurring subscription, unlocks all features
//   - Pro Annual      — recurring subscription at a discounted annual rate
//
// Phase 15 — Monetization / Licensing (Issue #308)
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - ProductTier (Monetization)
// ---------------------------------------------------------------------------
/// The purchasable product tiers offered to users.
///
/// Each tier corresponds to an `EntitlementLevel` and carries display
/// metadata for the paywall and settings UI. The `.free` tier exists
/// as a reference point but has no associated App Store product.
///
/// Note: This type is distinct from the legacy `ProductTier` in
/// `Models/FeatureGate.swift` (which uses free/pro/studio). This
/// version reflects the final three-tier monetization model.
// ---------------------------------------------------------------------------
public enum MonetizationTier: String, Codable, Sendable, CaseIterable {

    /// Free tier — no purchase required.
    case free

    /// Plus tier — one-time lifetime purchase.
    case plus

    /// Pro tier — monthly or annual subscription.
    case pro

    // MARK: Display

    /// Human-readable display name for the tier.
    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro:  return "Pro"
        }
    }

    /// Marketing description of the tier's value proposition.
    public var description: String {
        switch self {
        case .free:
            return "Essential encoding tools for everyone. Convert media with common codecs, use built-in profiles, and monitor your work in the activity log."
        case .plus:
            return "Unlock the full toolkit with a one-time purchase. Per-stream encoding, custom profiles, disc burning, cloud upload, watch folders, pipelines, and more."
        case .pro:
            return "The complete professional suite. Everything in Plus, plus AI-powered upscaling, HDR enhancement, voice isolation, VMAF scoring, and priority support."
        }
    }

    /// The entitlement level this tier grants.
    public var entitlementLevel: EntitlementLevel {
        switch self {
        case .free: return .free
        case .plus: return .plus
        case .pro:  return .pro
        }
    }

    /// SF Symbol name for tier badge display.
    public var systemImage: String {
        switch self {
        case .free: return "person"
        case .plus: return "star"
        case .pro:  return "crown"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - ProductDefinition
// ---------------------------------------------------------------------------
/// A single purchasable product as defined in App Store Connect.
///
/// Each `ProductDefinition` maps an App Store product identifier to a
/// `MonetizationTier` and records whether it is a one-time purchase or a
/// recurring subscription. The `StoreManager` uses these definitions to
/// load products from StoreKit and map verified transactions back to
/// entitlement levels.
///
/// Product IDs follow the reverse-DNS convention:
///   `Ltd.MWBMpartners.MeedyaConverter.<tier>[.<period>]`
// ---------------------------------------------------------------------------
public struct ProductDefinition: Identifiable, Codable, Sendable {

    /// The App Store product identifier (must match App Store Connect exactly).
    public let id: String

    /// The monetization tier this product unlocks.
    public let tier: MonetizationTier

    /// Whether this product is a recurring subscription (`true`) or a
    /// one-time purchase (`false`).
    public let isSubscription: Bool

    /// The subscription period in months, if applicable.
    /// `nil` for one-time purchases, `1` for monthly, `12` for annual.
    public let periodMonths: Int?

    // MARK: Initialiser

    /// Create a new product definition.
    ///
    /// - Parameters:
    ///   - id: The App Store product identifier.
    ///   - tier: The tier this product unlocks.
    ///   - isSubscription: Whether this is a recurring subscription.
    ///   - periodMonths: Subscription period in months (nil for one-time).
    public init(id: String, tier: MonetizationTier, isSubscription: Bool, periodMonths: Int? = nil) {
        self.id = id
        self.tier = tier
        self.isSubscription = isSubscription
        self.periodMonths = periodMonths
    }

    // MARK: Display

    /// Human-readable label for the billing period.
    public var periodLabel: String {
        guard isSubscription, let months = periodMonths else {
            return "Lifetime"
        }
        switch months {
        case 1:  return "Monthly"
        case 12: return "Annual"
        default: return "Every \(months) months"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - ProductCatalog
// ---------------------------------------------------------------------------
/// The canonical catalog of all purchasable products.
///
/// This enum is never instantiated — it serves as a namespace for the
/// static product definitions and the `allProducts` collection.
///
/// When adding or removing products, update both the individual constants
/// and the `allProducts` array to keep them in sync.
// ---------------------------------------------------------------------------
public enum ProductCatalog {

    // MARK: Product Definitions

    /// Plus (Lifetime) — one-time purchase that unlocks all Plus features.
    ///
    /// This is the entry-level paid tier, designed for enthusiasts who
    /// want expanded features without a recurring commitment.
    public static let plusLifetime = ProductDefinition(
        id: "Ltd.MWBMpartners.MeedyaConverter.plus",
        tier: .plus,
        isSubscription: false,
        periodMonths: nil
    )

    /// Pro Monthly — recurring subscription unlocking all features.
    ///
    /// Billed monthly with no long-term commitment. Ideal for
    /// professionals with project-based needs.
    public static let proMonthly = ProductDefinition(
        id: "Ltd.MWBMpartners.MeedyaConverter.pro.monthly",
        tier: .pro,
        isSubscription: true,
        periodMonths: 1
    )

    /// Pro Annual — recurring subscription at a discounted annual rate.
    ///
    /// Best value for full-time professionals. Typically priced at
    /// approximately 2 months free compared to the monthly plan.
    public static let proAnnual = ProductDefinition(
        id: "Ltd.MWBMpartners.MeedyaConverter.pro.annual",
        tier: .pro,
        isSubscription: true,
        periodMonths: 12
    )

    // MARK: Collections

    /// All purchasable products, ordered by tier then period.
    ///
    /// Used by `StoreManager` to request products from the App Store
    /// and by `PaywallView` to display purchase options.
    public static let allProducts: [ProductDefinition] = [
        plusLifetime,
        proMonthly,
        proAnnual,
    ]

    /// The set of all product identifiers for StoreKit requests.
    public static var productIdentifiers: Set<String> {
        Set(allProducts.map(\.id))
    }

    /// Look up a product definition by its App Store identifier.
    ///
    /// - Parameter id: The product ID to look up.
    /// - Returns: The matching `ProductDefinition`, or `nil` if not found.
    public static func product(for id: String) -> ProductDefinition? {
        allProducts.first { $0.id == id }
    }

    /// Look up a product definition's tier by its App Store identifier.
    ///
    /// - Parameter id: The product ID to look up.
    /// - Returns: The `MonetizationTier` for the product, or `.free` if not found.
    public static func tier(for productID: String) -> MonetizationTier {
        product(for: productID)?.tier ?? .free
    }
}

// ---------------------------------------------------------------------------
// MARK: - TierComparison
// ---------------------------------------------------------------------------
/// Structured comparison data for the paywall feature table.
///
/// Each `TierComparison` entry describes a feature and its availability
/// across the three tiers, suitable for rendering a comparison grid.
///
/// Usage:
/// ```swift
/// let comparisons = TierComparison.allComparisons
/// for item in comparisons {
///     print("\(item.featureName): Free=\(item.freeIncluded) Plus=\(item.plusIncluded) Pro=\(item.proIncluded)")
/// }
/// ```
// ---------------------------------------------------------------------------
public struct TierComparison: Sendable {

    /// The human-readable feature name.
    public let featureName: String

    /// Short description of the feature.
    public let featureDescription: String

    /// Whether this feature is included in the Free tier.
    public let freeIncluded: Bool

    /// Whether this feature is included in the Plus tier.
    public let plusIncluded: Bool

    /// Whether this feature is included in the Pro tier.
    public let proIncluded: Bool

    // MARK: Initialiser

    /// Create a comparison entry from a `GatedFeature`.
    ///
    /// Availability is computed from the feature's `requiredTier`:
    /// - Free features are included in all tiers
    /// - Plus features are included in Plus and Pro
    /// - Pro features are included in Pro only
    public init(feature: GatedFeature) {
        self.featureName = feature.displayName
        self.featureDescription = feature.featureDescription
        self.freeIncluded = feature.requiredTier <= .free
        self.plusIncluded = feature.requiredTier <= .plus
        self.proIncluded = true // Pro includes everything
    }

    // MARK: Static Collections

    /// Comparison entries for all gated features, ordered by tier then name.
    ///
    /// Free features appear first, then Plus, then Pro. Within each tier
    /// group, features appear in their declaration order.
    public static var allComparisons: [TierComparison] {
        GatedFeature.allCases.map { TierComparison(feature: $0) }
    }
}
