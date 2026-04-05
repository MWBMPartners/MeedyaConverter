// ============================================================================
// MeedyaConverter — PaywallView (Feature Comparison & Purchase)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// `PaywallView` presents the feature comparison table and purchase options
// when a user accesses a gated feature or navigates to the subscription
// settings. It displays:
//
//   - A three-column comparison grid (Free vs Plus vs Pro)
//   - Purchase buttons with live pricing from StoreKit
//   - "Restore Purchases" for recovering previous transactions
//   - Subscription management link to the App Store
//   - The user's current tier badge
//
// Phase 15 — Monetization / Licensing (Issue #309)
// ---------------------------------------------------------------------------

#if canImport(StoreKit)
import StoreKit
#endif
import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - PaywallView
// ---------------------------------------------------------------------------
/// The paywall screen showing feature tiers and purchase options.
///
/// Presented as a sheet when the user accesses a gated feature or taps
/// "Upgrade" in the settings. Can also be shown standalone from the
/// subscription settings tab.
///
/// The view adapts its layout based on whether StoreKit products have
/// been loaded. While loading, a progress indicator is shown in place
/// of the purchase buttons.
// ---------------------------------------------------------------------------
struct PaywallView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var storeManager

    // MARK: - State

    /// The feature that triggered the paywall (nil if opened from settings).
    var triggeringFeature: GatedFeature?

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                paywallHeader

                // Triggering feature callout (if applicable)
                if let feature = triggeringFeature {
                    featureCallout(feature)
                }

                // Feature comparison table
                featureComparisonTable

                Divider()

                // Purchase buttons
                purchaseSection

                // Restore & manage
                footerActions
            }
            .padding(24)
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 650)
        .task {
            await storeManager.loadProducts()
        }
    }

    // MARK: - Header

    /// The paywall header with title and current tier badge.
    private var paywallHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 40))
                .foregroundStyle(.linearGradient(
                    colors: [.orange, .yellow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .accessibilityHidden(true)

            Text("Upgrade MeedyaConverter")
                .font(.title)
                .fontWeight(.bold)

            Text("Unlock powerful features for professional media conversion")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Current tier badge
            HStack(spacing: 4) {
                Image(systemName: storeManager.currentTier.systemImage)
                Text("Current plan: \(storeManager.currentTier.displayName)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
        }
    }

    // MARK: - Feature Callout

    /// A callout banner for the feature that triggered the paywall.
    private func featureCallout(_ feature: GatedFeature) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(feature.displayName) requires \(feature.requiredTier.displayName)")
                    .font(.headline)
                Text(feature.featureDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Feature Comparison Table

    /// The three-column feature comparison grid.
    private var featureComparisonTable: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack {
                Text("Feature")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fontWeight(.semibold)

                tierHeader("Free", systemImage: "person", color: .secondary)
                tierHeader("Plus", systemImage: "star", color: .blue)
                tierHeader("Pro", systemImage: "crown", color: .orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary)

            // Feature rows
            ForEach(TierComparison.allComparisons, id: \.featureName) { comparison in
                featureRow(comparison)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    /// A single tier column header.
    private func tierHeader(_ name: String, systemImage: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(name)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .frame(width: 60)
    }

    /// A single row in the feature comparison table.
    private func featureRow(_ comparison: TierComparison) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(comparison.featureName)
                    .font(.caption)
                Text(comparison.featureDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            checkMark(comparison.freeIncluded)
                .frame(width: 60)
            checkMark(comparison.plusIncluded)
                .frame(width: 60)
            checkMark(comparison.proIncluded)
                .frame(width: 60)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// A checkmark or dash icon for tier inclusion.
    private func checkMark(_ included: Bool) -> some View {
        Image(systemName: included ? "checkmark.circle.fill" : "minus.circle")
            .foregroundStyle(included ? .green : .gray.opacity(0.2))
            .font(.caption)
    }

    // MARK: - Purchase Section

    /// Purchase buttons with live pricing from StoreKit.
    private var purchaseSection: some View {
        VStack(spacing: 12) {
            #if canImport(StoreKit)
            if storeManager.isLoadingProducts {
                ProgressView("Loading prices...")
                    .padding()
            } else if storeManager.products.isEmpty {
                Text("Products are not available at this time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(storeManager.products) { product in
                    purchaseButton(for: product)
                }
            }
            #else
            Text("In-app purchases are not available in this build.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif

            // Error display
            if let error = storeManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    #if canImport(StoreKit)
    /// A purchase button for a single product.
    private func purchaseButton(for product: Product) -> some View {
        let definition = ProductCatalog.product(for: product.id)
        let tierName = definition?.tier.displayName ?? "Unknown"
        let periodLabel = definition?.periodLabel ?? ""
        let isPro = definition?.tier == .pro

        return Button {
            Task {
                do {
                    try await storeManager.purchase(product)
                } catch {
                    // Error is captured in storeManager.lastError
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tierName) \(periodLabel)")
                        .fontWeight(.semibold)
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(product.displayPrice)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isPro ? Color.orange : Color.blue, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(storeManager.isPurchasing)
    }
    #endif

    // MARK: - Footer Actions

    /// Restore purchases and subscription management links.
    private var footerActions: some View {
        VStack(spacing: 8) {
            Button("Restore Purchases") {
                Task {
                    await storeManager.restorePurchases()
                }
            }
            .font(.caption)
            .disabled(storeManager.isPurchasing)

            #if canImport(StoreKit)
            if storeManager.currentTier != .free {
                Link(
                    "Manage Subscription",
                    destination: URL(string: "https://apps.apple.com/account/subscriptions")!
                )
                .font(.caption)
            }
            #endif

            Text("Purchases are processed by the App Store. Subscriptions renew automatically unless cancelled.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }
}
