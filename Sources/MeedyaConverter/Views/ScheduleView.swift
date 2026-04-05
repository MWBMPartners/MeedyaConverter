// ============================================================================
// MeedyaConverter — ScheduleView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - ScheduleView

/// Interface for scheduling encoding jobs to run at a specific time.
///
/// Provides a date/time picker, optional repeat interval, and a list
/// of all scheduled jobs with enable/disable toggles. Users can schedule
/// the current job configuration or manage existing scheduled entries.
struct ScheduleView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var scheduledTime: Date = Date().addingTimeInterval(3600)
    @State private var selectedRepeat: RepeatInterval = .never
    @State private var scheduledJobs: [ScheduledJob] = []
    @State private var showConfirmation = false

    // MARK: - Body

    var body: some View {
        Form {
            // Schedule configuration
            scheduleConfigSection

            // Scheduled jobs list
            scheduledJobsSection

            // Next scheduled job indicator
            nextJobSection
        }
        .formStyle(.grouped)
        .navigationTitle("Schedule Encoding")
        .frame(minWidth: 500, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            refreshJobList()
        }
        .alert("Job Scheduled", isPresented: $showConfirmation) {
            Button("OK") {}
        } message: {
            Text("The encoding job has been scheduled for \(scheduledTime.formatted(date: .abbreviated, time: .shortened)).")
        }
    }

    // MARK: - Schedule Configuration

    private var scheduleConfigSection: some View {
        Section("Schedule New Job") {
            DatePicker(
                "Start Time",
                selection: $scheduledTime,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)

            Picker("Repeat", selection: $selectedRepeat) {
                ForEach(RepeatInterval.allCases, id: \.self) { interval in
                    Text(interval.rawValue).tag(interval)
                }
            }
            .pickerStyle(.segmented)

            // Schedule button
            Button {
                scheduleCurrentJob()
            } label: {
                Label("Schedule Current Job", systemImage: "clock.badge.checkmark")
            }
            .disabled(viewModel.selectedFile == nil)
            .help(viewModel.selectedFile == nil
                  ? "Import and select a source file first."
                  : "Schedule the current encoding configuration to run at the selected time.")
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Scheduled Jobs List

    private var scheduledJobsSection: some View {
        Section("Scheduled Jobs (\(scheduledJobs.count))") {
            if scheduledJobs.isEmpty {
                ContentUnavailableView(
                    "No Scheduled Jobs",
                    systemImage: "clock",
                    description: Text("Schedule an encoding job to have it run automatically.")
                )
            } else {
                ForEach(scheduledJobs) { job in
                    scheduledJobRow(job)
                }
                .onDelete { offsets in
                    deleteJobs(at: offsets)
                }
            }
        }
    }

    // MARK: - Scheduled Job Row

    /// A single row displaying a scheduled job with time, status, and toggle.
    private func scheduledJobRow(_ job: ScheduledJob) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.jobConfig.inputURL.lastPathComponent)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // Scheduled time
                    Label(
                        job.scheduledTime.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // Repeat indicator
                    if let interval = job.repeatInterval {
                        let repeatLabel = RepeatInterval(from: interval)
                        Label(repeatLabel.rawValue, systemImage: "repeat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Profile name
                Text("Profile: \(job.jobConfig.profile.name)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Status indicator
            if job.scheduledTime <= Date() && job.repeatInterval == nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("This job has already fired.")
            } else {
                timeUntilLabel(job.scheduledTime)
            }

            // Enable/disable toggle
            Toggle("Enabled", isOn: Binding(
                get: { job.isEnabled },
                set: { enabled in
                    viewModel.scheduler.setEnabled(id: job.id, enabled: enabled)
                    refreshJobList()
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Next Job Section

    @ViewBuilder
    private var nextJobSection: some View {
        let enabledJobs = scheduledJobs.filter { $0.isEnabled && $0.scheduledTime > Date() }
        if let nextJob = enabledJobs.first {
            Section("Next Scheduled") {
                HStack {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(.accent)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(nextJob.jobConfig.inputURL.lastPathComponent)
                            .font(.headline)
                        Text(nextJob.scheduledTime.formatted(date: .complete, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    timeUntilLabel(nextJob.scheduledTime)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Time Until Label

    /// Display a human-readable countdown to the given date.
    private func timeUntilLabel(_ date: Date) -> some View {
        let interval = date.timeIntervalSinceNow
        let text: String
        if interval < 60 {
            text = "< 1 min"
        } else if interval < 3600 {
            text = "\(Int(interval / 60)) min"
        } else if interval < 86_400 {
            text = String(format: "%.1f hrs", interval / 3600)
        } else {
            text = String(format: "%.0f days", interval / 86_400)
        }

        return Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.accent.opacity(0.1))
            .foregroundStyle(.accent)
            .clipShape(Capsule())
    }

    // MARK: - Actions

    /// Schedule the current encoding job configuration.
    private func scheduleCurrentJob() {
        guard let file = viewModel.selectedFile,
              let outputDir = viewModel.outputDirectory else { return }

        let outputURL = outputDir.appendingPathComponent(
            file.fileName
        ).deletingPathExtension().appendingPathExtension("mkv")

        let config = EncodingJobConfig(
            inputURL: file.fileURL,
            outputURL: outputURL,
            profile: viewModel.selectedProfile
        )

        let job = ScheduledJob(
            scheduledTime: scheduledTime,
            repeatInterval: selectedRepeat.timeInterval,
            jobConfig: config
        )

        viewModel.scheduler.schedule(job)
        refreshJobList()
        showConfirmation = true
    }

    /// Delete scheduled jobs at the given offsets.
    private func deleteJobs(at offsets: IndexSet) {
        for offset in offsets {
            let job = scheduledJobs[offset]
            viewModel.scheduler.cancelSchedule(id: job.id)
        }
        refreshJobList()
    }

    /// Refresh the local job list from the scheduler.
    private func refreshJobList() {
        scheduledJobs = viewModel.scheduler.listScheduled()
    }
}
