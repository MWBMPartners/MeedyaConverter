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
            // Workflow section — the main encoding pipeline steps
            Section("Workflow") {
                ForEach([NavigationItem.source, .streams, .output]) { item in
                    sidebarLabel(for: item)
                }
            }

            // Monitor section — queue and logging
            Section("Monitor") {
                sidebarLabel(for: .queue)
                    .badge(viewModel.engine.queue.totalCount)

                sidebarLabel(for: .log)
                    .badge(viewModel.logEntries.count)
            }

            // Tools section — disc burning and image conversion
            Section("Tools") {
                sidebarLabel(for: .images)
                sidebarLabel(for: .burn)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
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
