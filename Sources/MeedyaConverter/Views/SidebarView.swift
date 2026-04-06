// ============================================================================
// MeedyaConverter — SidebarView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI

// MARK: - SidebarView

/// The sidebar navigation for the main application window.
///
/// Displays navigation items grouped by workflow stage. Each item
/// shows an icon, label, and optional badge count for queue/log items.
struct SidebarView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Body

    var body: some View {
        @Bindable var vm = viewModel

        List(selection: $vm.selectedNavItem) {
            // Workflow section — the main encoding pipeline steps.
            Section("Workflow") {
                sidebarLabel(for: .source)
                sidebarLabel(for: .streams)
                sidebarLabel(for: .output)
            }

            // Monitor section — queue, logging, dashboard, resources.
            Section("Monitor") {
                sidebarLabel(for: .queue)
                    .badge(viewModel.engine.queue.totalCount)
                sidebarLabel(for: .log)
                    .badge(viewModel.logEntries.count)
                sidebarLabel(for: .dashboard)
                sidebarLabel(for: .resourceMonitor)
            }

            // Tools section — editing, analysis, batch operations.
            Section("Tools") {
                sidebarLabel(for: .images)
                sidebarLabel(for: .burn)
                sidebarLabel(for: .trimEdit)
                sidebarLabel(for: .analyze)
                sidebarLabel(for: .metadataTags)
                sidebarLabel(for: .batchRename)
                sidebarLabel(for: .concatenation)
                sidebarLabel(for: .watermark)
                sidebarLabel(for: .multiOutput)
                sidebarLabel(for: .filterGraph)
                sidebarLabel(for: .edlEditor)
                sidebarLabel(for: .animatedImage)
                sidebarLabel(for: .duplicateFinder)
            }

            // Performance section — benchmarking, optimisation, storage.
            Section("Performance") {
                sidebarLabel(for: .parallelEncoding)
                sidebarLabel(for: .queueOptimizer)
                sidebarLabel(for: .benchmark)
                sidebarLabel(for: .storageAnalysis)
                sidebarLabel(for: .comparisonLibrary)
                sidebarLabel(for: .recentFiles)
            }

            // Distribution section — upload, cloud, sharing.
            Section("Distribution") {
                sidebarLabel(for: .videoUpload)
                sidebarLabel(for: .cloudStorage)
                sidebarLabel(for: .sftp)
                sidebarLabel(for: .podcastFeed)
                sidebarLabel(for: .teamProfile)
                sidebarLabel(for: .cloudSync)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        .accessibilityLabel("Navigation")
    }

    // MARK: - Sidebar Label

    /// A single sidebar navigation row with icon and label.
    private func sidebarLabel(for item: NavigationItem) -> some View {
        Label(item.rawValue, systemImage: item.systemImage)
            .tag(item)
            .accessibilityLabel(item.accessibilityLabel)
    }
}
