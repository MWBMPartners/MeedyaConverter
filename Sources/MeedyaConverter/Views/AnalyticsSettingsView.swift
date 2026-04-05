// ============================================================================
// MeedyaConverter — AnalyticsSettingsView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - AnalyticsSettingsView

/// Settings view for the opt-in analytics system.
///
/// Provides full transparency and user control:
/// - Toggle to enable/disable analytics collection.
/// - Clear explanation of what IS and IS NOT collected.
/// - "View Collected Data" to inspect all queued events as JSON.
/// - "Delete All Data" with confirmation for GDPR right to erasure.
/// - Displays the anonymous installation ID for reference.
///
/// Phase 12 — Analytics Integration (Issue #183)
struct AnalyticsSettingsView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// Whether the "View Collected Data" sheet is presented.
    @State private var showDataSheet = false

    /// Whether the delete confirmation alert is presented.
    @State private var showDeleteConfirmation = false

    // MARK: - Body

    var body: some View {
        Form {
            // MARK: Enable / Disable
            Section("Analytics Collection") {
                Toggle("Help improve MeedyaConverter by sharing anonymous usage data",
                       isOn: Binding(
                           get: { viewModel.analytics.isEnabled },
                           set: { viewModel.analytics.setEnabled($0) }
                       ))
                .accessibilityLabel("Enable anonymous analytics collection")

                Text("""
                    When enabled, MeedyaConverter collects anonymous usage \
                    statistics such as which codecs and containers are used, \
                    encode durations (short/medium/long), and feature usage. \
                    This data helps us prioritise improvements.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // MARK: What We Collect
            Section("What IS Collected") {
                VStack(alignment: .leading, spacing: 4) {
                    bulletPoint("Codec and container format selections")
                    bulletPoint("Encode duration category (short/medium/long)")
                    bulletPoint("Built-in profile names used")
                    bulletPoint("Feature usage (e.g. HDR tone mapping, crop detection)")
                    bulletPoint("App launch count")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("What is NEVER Collected") {
                VStack(alignment: .leading, spacing: 4) {
                    bulletPoint("File names or file paths", negative: true)
                    bulletPoint("Personal information (name, email, account)", negative: true)
                    bulletPoint("IP addresses", negative: true)
                    bulletPoint("File contents or media data", negative: true)
                    bulletPoint("Custom profile names", negative: true)
                    bulletPoint("System username or hardware identifiers", negative: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // MARK: Data Management
            Section("Your Data") {
                LabeledContent("Anonymous ID") {
                    Text(viewModel.analytics.anonymousId.uuidString)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityLabel("Your anonymous analytics identifier")

                LabeledContent("Queued Events") {
                    Text("\(viewModel.analytics.queuedEventCount)")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("View Collected Data") {
                        showDataSheet = true
                    }
                    .accessibilityLabel("View all collected analytics data as JSON")

                    Spacer()

                    Button("Delete All Data", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .accessibilityLabel("Permanently delete all collected analytics data")
                }
            }

            // MARK: Privacy Policy
            Section {
                Link(destination: URL(string: "https://meedya.app/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Analytics")

        // MARK: - View Data Sheet
        .sheet(isPresented: $showDataSheet) {
            CollectedDataSheet(analyticsEngine: viewModel.analytics)
        }

        // MARK: - Delete Confirmation
        .alert("Delete All Analytics Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.analytics.deleteAllData()
            }
        } message: {
            Text("""
                This will permanently delete all collected analytics data \
                and generate a new anonymous ID. This action cannot be undone.
                """)
        }
    }

    // MARK: - Helpers

    /// A styled bullet point for the collection lists.
    @ViewBuilder
    private func bulletPoint(_ text: String, negative: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: negative ? "xmark.circle" : "checkmark.circle")
                .foregroundStyle(negative ? .red : .green)
                .font(.caption2)
            Text(text)
        }
    }
}

// MARK: - CollectedDataSheet

/// A sheet displaying all collected analytics events as formatted JSON.
///
/// Allows the user to inspect exactly what data has been recorded,
/// fulfilling the transparency requirement.
struct CollectedDataSheet: View {

    // MARK: - Properties

    let analyticsEngine: AnalyticsEngine

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Collected Analytics Data")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // JSON content
            ScrollView {
                Text(analyticsEngine.exportCollectedDataString())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 500, height: 400)
    }
}
