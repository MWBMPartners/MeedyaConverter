// ============================================================================
// MeedyaConverter — LicenseEntryView (Direct Distribution License Key)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// `LicenseEntryView` provides the UI for entering and managing license keys
// in direct-distribution builds (non-App Store). Users who purchase through
// Stripe receive a license key in MC-XXXX-XXXX-XXXX-XXXX format, which
// they enter here to unlock Plus or Pro features.
//
// The view displays:
//   - A text field for entering the license key
//   - An "Activate" button that validates and stores the key
//   - Current license status (tier, activation date, expiry)
//   - A "Deactivate" button to remove the key from the Keychain
//   - A link to the purchase page for users without a key
//
// Phase 15 — Monetization / Licensing (Issue #310)
// ---------------------------------------------------------------------------

import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - LicenseEntryView
// ---------------------------------------------------------------------------
/// License key entry and management interface for direct-distribution builds.
///
/// This view is shown in the Subscription settings tab as an alternative
/// to App Store purchases. It handles the complete license lifecycle:
/// entry, validation, activation, status display, and deactivation.
///
/// The view reads from and writes to the macOS Keychain via
/// `LicenseKeyValidator`, ensuring keys persist across app reinstalls.
// ---------------------------------------------------------------------------
struct LicenseEntryView: View {

    // MARK: - State

    /// The license key text entered by the user.
    @State private var keyInput: String = ""

    /// The currently activated license (loaded from Keychain on appear).
    @State private var activeLicense: LicenseKey?

    /// Whether an activation or deactivation operation is in progress.
    @State private var isProcessing: Bool = false

    /// Error message from the last failed operation.
    @State private var errorMessage: String?

    /// Success message after activation.
    @State private var successMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Label("License Key", systemImage: "key")
                .font(.headline)

            if let license = activeLicense {
                // Active license display
                activeLicenseCard(license)
            } else {
                // Key entry form
                keyEntryForm
            }

            // Purchase link
            purchaseLink

            // Messages
            messageDisplay
        }
        .onAppear {
            loadActiveLicense()
        }
    }

    // MARK: - Active License Card

    /// Displays the currently activated license with status and deactivate button.
    private func activeLicenseCard(_ license: LicenseKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tier badge
            HStack(spacing: 8) {
                Image(systemName: license.tier.systemImage)
                    .foregroundStyle(tierColor(license.tier))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(license.tier.displayName) License")
                        .font(.headline)
                    Text(license.isValid ? "Active" : "Expired")
                        .font(.caption)
                        .foregroundStyle(license.isValid ? .green : .red)
                }

                Spacer()

                // Status indicator
                Circle()
                    .fill(license.isValid ? .green : .red)
                    .frame(width: 8, height: 8)
            }

            Divider()

            // License details
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Key") {
                    Text(maskedKey(license.key))
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Activated") {
                    Text(license.activatedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let expiry = license.expiresAt {
                    LabeledContent("Expires") {
                        Text(expiry, style: .date)
                            .font(.caption)
                            .foregroundStyle(license.isExpired ? .red : .secondary)
                    }
                } else {
                    LabeledContent("Expires") {
                        Text("Never (Lifetime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Machine") {
                    Text(license.machineId.prefix(8) + "...")
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Deactivate button
            HStack {
                Spacer()
                Button(role: .destructive) {
                    deactivateLicense()
                } label: {
                    Label("Deactivate License", systemImage: "xmark.circle")
                }
                .disabled(isProcessing)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Key Entry Form

    /// The license key input field and activate button.
    private var keyEntryForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter your license key to unlock Plus or Pro features.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(
                    "MC-XXXX-XXXX-XXXX-XXXX",
                    text: $keyInput
                )
                .textFieldStyle(.roundedBorder)
                .monospaced()
                .disableAutocorrection(true)
                .onChange(of: keyInput) { _, newValue in
                    // Auto-format: uppercase and limit length
                    let filtered = newValue.uppercased()
                    if filtered != newValue {
                        keyInput = filtered
                    }
                    // Clear messages on edit
                    errorMessage = nil
                    successMessage = nil
                }
                .accessibilityLabel("License key input")

                Button {
                    activateLicense()
                } label: {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Activate")
                    }
                }
                .disabled(keyInput.isEmpty || isProcessing)
                .keyboardShortcut(.defaultAction)
            }

            // Format hint
            Text("Format: MC-XXXX-XXXX-XXXX-XXXX")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Purchase Link

    /// Link to the purchase page for users who need a key.
    private var purchaseLink: some View {
        HStack(spacing: 4) {
            Text("Don't have a license key?")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link("Purchase one", destination: URL(string: "https://meedya.app/purchase")!)
                .font(.caption)
        }
    }

    // MARK: - Messages

    /// Error and success message display.
    @ViewBuilder
    private var messageDisplay: some View {
        if let error = errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }

        if let success = successMessage {
            Label(success, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    // MARK: - Actions

    /// Validate and activate the entered license key.
    private func activateLicense() {
        isProcessing = true
        errorMessage = nil
        successMessage = nil

        do {
            let license = try LicenseKeyValidator.activate(key: keyInput)
            activeLicense = license
            keyInput = ""
            successMessage = "\(license.tier.displayName) license activated successfully."

            // Sync to FeatureGateManager
            let level = license.entitlementLevel
            FeatureGateManager.shared.provider = LicenseKeyGateProvider(level: level)
            Task {
                await FeatureGateManager.shared.refreshEntitlementLevel()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    /// Deactivate the current license and clear the Keychain.
    private func deactivateLicense() {
        isProcessing = true
        errorMessage = nil
        successMessage = nil

        do {
            try LicenseKeyValidator.deactivate()
            activeLicense = nil
            successMessage = "License deactivated."

            // Reset to free tier
            FeatureGateManager.shared.provider = FreeGateProvider()
            FeatureGateManager.shared.clearCache()
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    /// Load the active license from the Keychain on view appear.
    private func loadActiveLicense() {
        activeLicense = LicenseKeyValidator.loadActiveLicense()
    }

    // MARK: - Helpers

    /// Mask the middle segments of a license key for display.
    ///
    /// Shows: MC-PXXX-****-****-XXXC
    private func maskedKey(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 5 else { return key }
        return "\(parts[0])-\(parts[1])-****-****-\(parts[4])"
    }

    /// Color for the tier badge.
    private func tierColor(_ tier: MonetizationTier) -> Color {
        switch tier {
        case .free: return .secondary
        case .plus: return .blue
        case .pro:  return .orange
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - LicenseKeyGateProvider
// ---------------------------------------------------------------------------
/// A `FeatureGateProvider` backed by a validated license key.
///
/// Created by `LicenseEntryView` when a key is activated and installed
/// into `FeatureGateManager.shared.provider`.
// ---------------------------------------------------------------------------
struct LicenseKeyGateProvider: FeatureGateProvider, Sendable {

    /// The entitlement level granted by the license key.
    let level: EntitlementLevel

    func entitlementLevel() async -> EntitlementLevel {
        level
    }

    func isEntitled(to feature: GatedFeature) -> Bool {
        level >= feature.requiredTier
    }
}
