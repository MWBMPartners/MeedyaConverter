// ============================================================================
// MeedyaConverter — StoreManager (StoreKit 2 Integration)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// `StoreManager` is the application's interface to the App Store via
// StoreKit 2. It handles:
//
//   - Loading product metadata (pricing, descriptions) from App Store Connect
//   - Processing purchases and restoring previous transactions
//   - Listening for transaction updates (renewals, revocations, refunds)
//   - Computing the user's current `MonetizationTier` from active purchases
//   - Syncing the entitlement level to `FeatureGateManager`
//
// The manager is `@MainActor @Observable` for direct SwiftUI binding.
// All StoreKit operations use the async/await API introduced in StoreKit 2.
//
// Phase 15 — Monetization / Licensing (Issue #309)
// ---------------------------------------------------------------------------

#if canImport(StoreKit)
import StoreKit
#endif
import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - StoreManager
// ---------------------------------------------------------------------------
/// Manages App Store product loading, purchasing, and entitlement tracking.
///
/// `StoreManager` is injected into the SwiftUI environment and provides
/// observable state for the paywall and settings views.
///
/// ### Lifecycle
/// 1. Call `loadProducts()` during app startup to fetch product metadata
/// 2. Call `listenForTransactions()` to start the background listener
/// 3. The UI reads `products`, `purchasedProductIDs`, and `currentTier`
/// 4. Purchases flow through `purchase(_:)` and update state automatically
///
/// ### Thread Safety
/// All public state is `@MainActor`-isolated. StoreKit 2 operations are
/// async and run on cooperative threads; results are dispatched back to
/// the main actor before updating observable properties.
// ---------------------------------------------------------------------------
@MainActor @Observable
final class StoreManager {

    // MARK: - Observable State

    #if canImport(StoreKit)
    /// Products loaded from the App Store, ordered by tier then period.
    var products: [Product] = []
    #endif

    /// The set of product IDs the user has actively purchased.
    ///
    /// Updated after every transaction verification. Includes both
    /// one-time purchases and active subscriptions.
    var purchasedProductIDs: Set<String> = []

    /// The user's current monetization tier, computed from purchases.
    ///
    /// This is the single source of truth for the UI — views bind to
    /// this property to show/hide gated features and upgrade prompts.
    var currentTier: MonetizationTier {
        // Pro takes priority over Plus
        if purchasedProductIDs.contains(ProductCatalog.proMonthly.id)
            || purchasedProductIDs.contains(ProductCatalog.proAnnual.id) {
            return .pro
        }
        if purchasedProductIDs.contains(ProductCatalog.plusLifetime.id) {
            return .plus
        }
        return .free
    }

    /// Whether products are currently being loaded from the App Store.
    var isLoadingProducts: Bool = false

    /// Whether a purchase is currently in progress.
    var isPurchasing: Bool = false

    /// The last error message from a StoreKit operation.
    var lastError: String?

    // MARK: - Private

    /// Background task handle for the transaction listener.
    @ObservationIgnored
    nonisolated(unsafe) private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Initialiser

    init() {}

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Product Loading

    /// Load product metadata from the App Store.
    ///
    /// Fetches `Product` objects for all identifiers in `ProductCatalog`.
    /// Products are sorted by tier (Plus before Pro) then by period
    /// (lifetime, monthly, annual).
    ///
    /// This method is safe to call multiple times — subsequent calls
    /// refresh the product list with current pricing.
    func loadProducts() async {
        #if canImport(StoreKit)
        isLoadingProducts = true
        lastError = nil

        do {
            let storeProducts = try await Product.products(
                for: ProductCatalog.productIdentifiers
            )

            // Sort by catalog order (Plus lifetime, Pro monthly, Pro annual)
            let catalogOrder = ProductCatalog.allProducts.map(\.id)
            products = storeProducts.sorted { a, b in
                let indexA = catalogOrder.firstIndex(of: a.id) ?? Int.max
                let indexB = catalogOrder.firstIndex(of: b.id) ?? Int.max
                return indexA < indexB
            }
        } catch {
            lastError = "Failed to load products: \(error.localizedDescription)"
        }

        isLoadingProducts = false
        #endif
    }

    // MARK: - Purchasing

    #if canImport(StoreKit)
    /// Purchase a product through the App Store.
    ///
    /// Presents the App Store payment sheet and waits for the transaction
    /// to complete. On success, the purchased product ID is added to
    /// `purchasedProductIDs` and the `FeatureGateManager` is updated.
    ///
    /// - Parameter product: The `Product` to purchase.
    /// - Returns: The verified `Transaction`, or `nil` if the user cancelled.
    /// - Throws: `StoreKit.StoreKitError` or verification errors.
    @discardableResult
    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        isPurchasing = true
        lastError = nil

        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verificationResult):
            let transaction = try checkVerified(verificationResult)
            await transaction.finish()
            await updatePurchasedProducts()
            syncEntitlement()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            // Transaction requires approval (e.g., Ask to Buy)
            lastError = "Purchase is pending approval."
            return nil

        @unknown default:
            lastError = "An unknown purchase result occurred."
            return nil
        }
    }
    #endif

    // MARK: - Restore Purchases

    /// Restore previous purchases from the App Store.
    ///
    /// Syncs the user's transaction history and updates `purchasedProductIDs`.
    /// This is triggered by the "Restore Purchases" button in the paywall
    /// and settings views.
    func restorePurchases() async {
        #if canImport(StoreKit)
        lastError = nil

        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            syncEntitlement()
        } catch {
            lastError = "Failed to restore purchases: \(error.localizedDescription)"
        }
        #endif
    }

    // MARK: - Transaction Listener

    /// Start listening for transaction updates in the background.
    ///
    /// Handles subscription renewals, revocations, refunds, and other
    /// transaction state changes that occur while the app is running.
    ///
    /// Call this once during app startup. The listener runs for the
    /// lifetime of the `StoreManager` instance.
    func listenForTransactions() {
        #if canImport(StoreKit)
        transactionListenerTask?.cancel()
        transactionListenerTask = Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }

                do {
                    let transaction = try await MainActor.run {
                        try self.checkVerified(result)
                    }
                    await transaction.finish()
                    _ = await MainActor.run {
                        Task {
                            await self.updatePurchasedProducts()
                            self.syncEntitlement()
                        }
                    }
                } catch {
                    // Verification failed — ignore this transaction
                }
            }
        }
        #endif
    }

    // MARK: - Private Helpers

    #if canImport(StoreKit)
    /// Verify a StoreKit transaction result.
    ///
    /// StoreKit 2 automatically verifies transactions using the device's
    /// on-device verification. This method extracts the verified payload
    /// or throws if verification failed.
    ///
    /// - Parameter result: The `VerificationResult` from StoreKit.
    /// - Returns: The verified `Transaction`.
    /// - Throws: `StoreKitError` if verification fails.
    private func checkVerified(_ result: VerificationResult<StoreKit.Transaction>) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw error
        }
    }
    #endif

    /// Update the set of purchased product IDs from current entitlements.
    ///
    /// Iterates through all current entitlements (verified transactions)
    /// and collects product IDs for active purchases and subscriptions.
    private func updatePurchasedProducts() async {
        #if canImport(StoreKit)
        var purchased = Set<String>()

        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                // Only include active transactions (not revoked/expired)
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            }
        }

        purchasedProductIDs = purchased
        #endif
    }

    /// Sync the current tier to `FeatureGateManager`.
    ///
    /// Creates a `StoreKitGateProvider` with the current tier's entitlement
    /// level and installs it as the active provider. Also refreshes the
    /// manager's cached level for offline access.
    private func syncEntitlement() {
        let level = currentTier.entitlementLevel
        FeatureGateManager.shared.provider = StoreKitGateProvider(level: level)

        Task {
            await FeatureGateManager.shared.refreshEntitlementLevel()
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - StoreKitGateProvider
// ---------------------------------------------------------------------------
/// A `FeatureGateProvider` backed by a StoreKit-derived entitlement level.
///
/// Created by `StoreManager` each time the purchase state changes and
/// installed into `FeatureGateManager.shared.provider`.
// ---------------------------------------------------------------------------
struct StoreKitGateProvider: FeatureGateProvider, Sendable {

    /// The entitlement level determined from StoreKit transactions.
    let level: EntitlementLevel

    /// Returns the StoreKit-derived entitlement level.
    func entitlementLevel() async -> EntitlementLevel {
        level
    }

    /// Check whether the StoreKit-derived level meets the feature's requirement.
    func isEntitled(to feature: GatedFeature) -> Bool {
        level >= feature.requiredTier
    }
}
