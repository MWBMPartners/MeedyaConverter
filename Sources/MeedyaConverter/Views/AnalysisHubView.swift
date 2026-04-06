// ============================================================================
// MeedyaConverter — AnalysisHubView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Hub view that aggregates all analysis tools into a single tabbed interface.
// Each tab hosts a specialised analysis view:
//
//   - Scene Detection (SceneDetectorView)
//   - Bitrate Heatmap (BitrateHeatmapView)
//   - Quality Check (QualityCheckView)
//   - Quality Metrics (QualityMetricsView)
//   - Loudness Report (LoudnessReportView)
//   - Audio Waveform (AudioWaveformView)
//
// This view is reached from the sidebar "Analyze" navigation item and
// provides a single entry point for all media analysis functionality.
// ---------------------------------------------------------------------------

import SwiftUI

// MARK: - AnalysisHubView

/// A tabbed hub view that provides access to all media analysis tools.
///
/// Each tab presents a different analysis capability. The selected tab
/// is persisted across navigation so users return to their last-used
/// analysis tool.
struct AnalysisHubView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The currently selected analysis tab.
    @State private var selectedTab: AnalysisTab = .sceneDetection

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Scene Detection", systemImage: "film.stack", value: .sceneDetection) {
                SceneDetectorView()
            }

            Tab("Bitrate Heatmap", systemImage: "chart.bar.fill", value: .bitrateHeatmap) {
                BitrateHeatmapView()
            }

            Tab("Quality Check", systemImage: "checkmark.seal", value: .qualityCheck) {
                QualityCheckView()
            }

            Tab("Quality Metrics", systemImage: "chart.xyaxis.line", value: .qualityMetrics) {
                QualityMetricsView()
            }

            Tab("Loudness Report", systemImage: "speaker.wave.3", value: .loudnessReport) {
                LoudnessReportView()
            }

            Tab("Audio Waveform", systemImage: "waveform", value: .audioWaveform) {
                @Bindable var vm = viewModel
                AudioWaveformView(
                    waveformData: viewModel.currentWaveformData,
                    selectedChannel: $vm.selectedWaveformChannel,
                    isAnalysing: viewModel.isAnalysingWaveform,
                    onAnalyse: {
                        Task {
                            await viewModel.analyseAudioWaveform()
                        }
                    }
                )
            }
        }
        .navigationTitle("Analyze")
    }
}

// MARK: - AnalysisTab

/// The available analysis tabs within the analysis hub.
private enum AnalysisTab: String, Hashable {
    case sceneDetection
    case bitrateHeatmap
    case qualityCheck
    case qualityMetrics
    case loudnessReport
    case audioWaveform
}
