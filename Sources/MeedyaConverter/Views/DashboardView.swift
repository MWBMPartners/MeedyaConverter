// ============================================================================
// MeedyaConverter — DashboardView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Displays aggregate encoding statistics in a dashboard layout:
//
//   - Overview cards: total encodes, success rate, storage saved, time spent.
//   - Codec usage pie chart (SwiftUI Charts).
//   - Profile usage bar chart (SwiftUI Charts).
//   - Container format distribution bar chart.
//   - "Reset Statistics" button with confirmation alert.
//
// The view reads from `StatisticsTracker.shared` and refreshes on appear.
//
// Phase 11 — Dashboard View (Issue #284)
// ---------------------------------------------------------------------------

import SwiftUI
import Charts
import ConverterEngine

// MARK: - DashboardView

/// A dashboard view that presents aggregate encoding statistics
/// with summary cards and distribution charts.
struct DashboardView: View {

    // MARK: - State

    /// The current snapshot of aggregate statistics.
    @State private var stats = EncodingStats()

    /// Whether the reset confirmation alert is shown.
    @State private var showResetConfirmation = false

    /// The statistics tracker instance.
    private let tracker = StatisticsTracker.shared

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text("Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 4)

                // Overview Cards
                overviewCardsSection

                // Charts
                if stats.totalEncodes > 0 {
                    chartsSection
                }

                // Reset Button
                resetSection
            }
            .padding(24)
        }
        .onAppear {
            refreshStats()
        }
        .accessibilityLabel("Encoding statistics dashboard")
    }

    // MARK: - Overview Cards

    /// Four summary cards showing key aggregate metrics.
    @ViewBuilder
    private var overviewCardsSection: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ],
            spacing: 16
        ) {
            StatCard(
                title: "Total Encodes",
                value: "\(stats.totalEncodes)",
                systemImage: "film.stack",
                color: .blue
            )

            StatCard(
                title: "Success Rate",
                value: successRateString,
                systemImage: "checkmark.circle",
                color: successRateColor
            )

            StatCard(
                title: "Storage Saved",
                value: formattedStorageSaved,
                systemImage: "externaldrive",
                color: .purple
            )

            StatCard(
                title: "Time Spent",
                value: formattedTotalTime,
                systemImage: "clock",
                color: .orange
            )
        }
    }

    // MARK: - Charts Section

    @ViewBuilder
    private var chartsSection: some View {
        HStack(alignment: .top, spacing: 20) {
            // Codec usage pie chart
            if !stats.codecUsage.isEmpty {
                chartCard(title: "Codec Usage") {
                    codecPieChart
                }
            }

            // Profile usage bar chart
            if !stats.profileUsage.isEmpty {
                chartCard(title: "Profile Usage") {
                    profileBarChart
                }
            }

            // Container distribution bar chart
            if !stats.containerUsage.isEmpty {
                chartCard(title: "Container Formats") {
                    containerBarChart
                }
            }
        }
    }

    // MARK: - Codec Pie Chart

    @ViewBuilder
    private var codecPieChart: some View {
        let entries = sortedEntries(stats.codecUsage)
        Chart(entries, id: \.key) { entry in
            SectorMark(
                angle: .value("Count", entry.value),
                innerRadius: .ratio(0.5),
                angularInset: 1
            )
            .foregroundStyle(by: .value("Codec", entry.key))
            .annotation(position: .overlay) {
                if entry.value > 0 {
                    Text("\(entry.value)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 8)
        .frame(height: 220)
        .accessibilityLabel("Codec usage distribution chart")
    }

    // MARK: - Profile Bar Chart

    @ViewBuilder
    private var profileBarChart: some View {
        let entries = sortedEntries(stats.profileUsage)
        Chart(entries, id: \.key) { entry in
            BarMark(
                x: .value("Count", entry.value),
                y: .value("Profile", entry.key)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .annotation(position: .trailing) {
                Text("\(entry.value)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: max(CGFloat(entries.count) * 32, 100))
        .accessibilityLabel("Profile usage distribution chart")
    }

    // MARK: - Container Bar Chart

    @ViewBuilder
    private var containerBarChart: some View {
        let entries = sortedEntries(stats.containerUsage)
        Chart(entries, id: \.key) { entry in
            BarMark(
                x: .value("Count", entry.value),
                y: .value("Container", entry.key)
            )
            .foregroundStyle(Color.green.gradient)
            .annotation(position: .trailing) {
                Text("\(entry.value)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: max(CGFloat(entries.count) * 32, 100))
        .accessibilityLabel("Container format distribution chart")
    }

    // MARK: - Reset Section

    @ViewBuilder
    private var resetSection: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset Statistics", systemImage: "arrow.counterclockwise")
            }
            .alert(
                "Reset All Statistics?",
                isPresented: $showResetConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    tracker.resetStats()
                    refreshStats()
                }
            } message: {
                Text("This will permanently delete all encoding statistics. This action cannot be undone.")
            }
        }
    }

    // MARK: - Helpers

    /// Refreshes the stats snapshot from the tracker.
    private func refreshStats() {
        stats = tracker.currentStats()
    }

    /// Wraps chart content in a titled card.
    private func chartCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Sorts dictionary entries by value descending for chart display.
    private func sortedEntries(_ dict: [String: Int]) -> [(key: String, value: Int)] {
        dict.sorted { $0.value > $1.value }
    }

    /// Formatted success rate percentage string.
    private var successRateString: String {
        guard stats.totalEncodes > 0 else { return "--" }
        return String(format: "%.1f%%", stats.successRate * 100)
    }

    /// Colour for success rate card based on percentage.
    private var successRateColor: Color {
        if stats.totalEncodes == 0 { return .secondary }
        if stats.successRate >= 0.95 { return .green }
        if stats.successRate >= 0.75 { return .yellow }
        return .red
    }

    /// Formatted storage saved string using ByteCountFormatter.
    private var formattedStorageSaved: String {
        guard stats.totalEncodes > 0 else { return "--" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: stats.storageSaved)
    }

    /// Formatted total encoding time string.
    private var formattedTotalTime: String {
        guard stats.totalEncodes > 0 else { return "--" }
        let total = Int(stats.totalEncodingTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        let seconds = total % 60
        return "\(minutes)m \(seconds)s"
    }
}

// MARK: - StatCard

/// A single summary statistic card with icon, title, and value.
private struct StatCard: View {
    /// The label above the value.
    let title: String

    /// The formatted metric value.
    let value: String

    /// SF Symbol name for the card icon.
    let systemImage: String

    /// Accent colour for the icon.
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
