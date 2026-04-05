// ============================================================================
// MeedyaConverter — TouchBarProvider
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - TouchBarProvider

/// Provides Touch Bar controls for MeedyaConverter's main window.
///
/// Displays context-sensitive controls depending on whether an encoding
/// job is currently active:
///   - **Idle:** Profile quick-select picker and "Encode" button.
///   - **Active:** Pause/Resume, Stop buttons, progress percentage,
///     encoding speed, and the current file name.
///
/// Touch Bar modifiers are silently ignored on Macs without a Touch Bar,
/// so no runtime availability checks are required.
///
/// ### References
/// - GitHub Issue #181 — Touch Bar Support
struct TouchBarProvider: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isQueueRunning, let jobState = viewModel.activeJobState {
                activeTouchBar(jobState: jobState)
            } else {
                idleTouchBar
            }
        }
    }

    // MARK: - Idle Touch Bar

    /// Touch Bar content when no encoding is active.
    ///
    /// Shows a profile picker for quick selection and an "Encode" action
    /// button to enqueue the currently selected file.
    @ViewBuilder
    private var idleTouchBar: some View {
        @Bindable var vm = viewModel

        // Profile quick-select picker
        Picker(
            "Profile",
            selection: $vm.selectedProfile
        ) {
            ForEach(EncodingProfile.builtInProfiles) { profile in
                Text(profile.name)
                    .tag(profile)
            }
        }
        .pickerStyle(.automatic)
        .accessibilityLabel("Select encoding profile")

        // Encode button — enqueue the selected file
        Button {
            viewModel.enqueueSelectedFile()
        } label: {
            Label("Encode", systemImage: "play.fill")
        }
        .disabled(viewModel.selectedFile == nil)
        .accessibilityLabel("Add selected file to encoding queue")
    }

    // MARK: - Active Touch Bar

    /// Touch Bar content during an active encoding job.
    ///
    /// Displays the file name, progress percentage with speed, and
    /// Pause/Resume + Stop controls.
    ///
    /// - Parameter jobState: The currently encoding job's state.
    @ViewBuilder
    private func activeTouchBar(jobState: EncodingJobState) -> some View {
        // File name of current encoding job
        Text(jobState.config.inputURL.lastPathComponent)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityLabel("Currently encoding \(jobState.config.inputURL.lastPathComponent)")

        // Progress and speed display
        Text(progressText(for: jobState))
            .font(.caption)
            .monospacedDigit()
            .accessibilityLabel("Encoding progress: \(Int(jobState.progress * 100)) percent")

        // Pause / Resume toggle
        Button {
            if jobState.status == .paused {
                viewModel.resumeCurrentJob()
            } else {
                viewModel.pauseCurrentJob()
            }
        } label: {
            if jobState.status == .paused {
                Label("Resume", systemImage: "play.fill")
            } else {
                Label("Pause", systemImage: "pause.fill")
            }
        }
        .accessibilityLabel(jobState.status == .paused ? "Resume encoding" : "Pause encoding")

        // Stop button — cancels current job and stops the queue
        Button {
            viewModel.cancelCurrentJob()
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .accessibilityLabel("Stop encoding and cancel current job")
    }

    // MARK: - Helpers

    /// Formats progress percentage and speed into a compact display string.
    ///
    /// - Parameter jobState: The current encoding job state.
    /// - Returns: A string such as "45% • 2.3x" or "45%" if speed is unavailable.
    private func progressText(for jobState: EncodingJobState) -> String {
        let pct = Int(jobState.progress * 100)
        if let speed = jobState.speed {
            return "\(pct)% • \(String(format: "%.1fx", speed))"
        }
        return "\(pct)%"
    }
}
