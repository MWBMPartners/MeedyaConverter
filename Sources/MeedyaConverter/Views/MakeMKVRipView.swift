// ============================================================================
// MeedyaConverter — MakeMKVRipView (Issue #503, slice 4b)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The GUI rip flow for the optional, opt-in MakeMKV backend (#503): scan a
// disc/device/disc image for its titles, choose which ones to rip, then run
// the rip with live progress. Gated behind `MakeMKVSettingsTab`'s opt-in
// toggle + terms acknowledgement (`MakeMKVConsentStore`) — when that gate is
// closed this NEVER shows a dead button, it explains why and offers "Open
// Settings…" and "Check Again" (D4/D6 in the design plan).
//
// Navigating away tears down this view's `@State` view model, which cancels
// any in-flight scan/rip in `.onDisappear` (belt-and-braces again in
// `deinit`) — the same contract `StabilizationView`/`QualityMetricsView`
// already give their in-flight work.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - MakeMKVRipView

struct MakeMKVRipView: View {

    // MARK: - State

    @State private var viewModel = MakeMKVRipViewModel()

    // MARK: - Gate keys (shared with MakeMKVSettingsTab — D6: re-check on any change)

    @AppStorage(MakeMKVConsentStore.Keys.enabled)
    private var makemkvEnabled: Bool = false
    @AppStorage(MakeMKVConsentStore.Keys.termsAcknowledgement)
    private var makemkvAcknowledgement: String = ""
    @AppStorage(MakeMKVConsentStore.Keys.binaryPath)
    private var makemkvBinaryPath: String = ""

    // MARK: - Environment

    /// D4 — deep-linking straight to the MakeMKV settings tab needs
    /// `TabView(selection:)` on every settings tab, which is out of scope
    /// for this slice; this opens the Settings window itself, exactly as
    /// the app's own Settings menu command does.
    @Environment(\.openSettings) private var openSettings

    // MARK: - Body

    var body: some View {
        Group {
            if let readiness = viewModel.readiness {
                switch readiness {
                case .ready:
                    mainForm
                case .notEnabled, .notInstalled:
                    gatedView
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("MakeMKV Rip")
        .onAppear { viewModel.refreshGate() }
        .onChange(of: makemkvEnabled) { viewModel.refreshGate() }
        .onChange(of: makemkvAcknowledgement) { viewModel.refreshGate() }
        .onChange(of: makemkvBinaryPath) { viewModel.refreshGate() }
        .onDisappear {
            viewModel.cancelRip()
            viewModel.cancelScan()
        }
    }

    // MARK: - Gated state

    /// Shown whenever MakeMKV isn't ready — never a dead end: always offers
    /// a way to fix it (Settings) and a way to re-check without leaving.
    private var gatedView: some View {
        ContentUnavailableView {
            Label("MakeMKV Isn't Ready", systemImage: "opticaldisc.fill")
        } description: {
            Text(viewModel.gateDescription)
        } actions: {
            Button("Open Settings\u{2026}") { openSettings() }
                .buttonStyle(.borderedProminent)
            Button("Check Again") { viewModel.refreshGate() }
        }
        .accessibilityLabel("MakeMKV is not ready. \(viewModel.gateDescription)")
    }

    // MARK: - Main form

    private var mainForm: some View {
        Form {
            sourceSection
            titlesSection
            destinationSection
            runSection
            outcomeSection
            messagesSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Source

    @ViewBuilder
    private var sourceSection: some View {
        Section("Source") {
            Picker("Read from", selection: $viewModel.sourceKind) {
                ForEach(MakeMKVRipViewModel.SourceKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }

            switch viewModel.sourceKind {
            case .opticalDrive:
                TextField("Drive number", text: $viewModel.discIndexText, prompt: Text("0"))
                Text("MakeMKV numbers optical drives starting at 0. If you're not sure, try 0 first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .devicePath:
                TextField("Device path", text: $viewModel.devicePath, prompt: Text("/dev/rdisk2"))
            case .discImage:
                HStack {
                    TextField("Disc image", text: $viewModel.isoPath, prompt: Text("Choose a .iso file\u{2026}"))
                    Button("Choose\u{2026}") { chooseISO() }
                }
            }

            Button {
                viewModel.scan()
            } label: {
                Label(
                    viewModel.isScanning ? "Scanning\u{2026}" : "Scan Disc",
                    systemImage: viewModel.isScanning ? "hourglass" : "magnifyingglass"
                )
            }
            .disabled(!viewModel.canScan)
            .accessibilityLabel(viewModel.isScanning ? "Scanning disc" : "Scan disc for titles")

            if let scanError = viewModel.scanErrorMessage {
                Label(scanError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        }
    }

    // MARK: - Titles

    @ViewBuilder
    private var titlesSection: some View {
        Section("Titles") {
            if viewModel.isScanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Scanning disc\u{2026}").foregroundStyle(.secondary)
                }
            } else if viewModel.orderedTitles.isEmpty {
                Text("Scan the disc to see its titles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.orderedTitles, id: \.index) { title in
                    titleRow(for: title)
                }
            }
        }
    }

    /// One title's row: a plain string-title `Toggle` (never a
    /// label-closure `Toggle`) plus an optional streams caption underneath.
    private func titleRow(for title: MakeMKVTitle) -> some View {
        let summary = viewModel.titleSummaries[title.index]
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(titleLine(for: title, summary: summary), isOn: Binding(
                get: { viewModel.selectedTitleIndices.contains(title.index) },
                set: { isOn in
                    if isOn {
                        viewModel.selectedTitleIndices.insert(title.index)
                    } else {
                        viewModel.selectedTitleIndices.remove(title.index)
                    }
                }
            ))
            .disabled(viewModel.isRipping)

            if let streams = summary?.streamsText {
                Text(streams)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
    }

    private func titleLine(for title: MakeMKVTitle, summary: MakeMKVTitleSummary?) -> String {
        guard let summary else { return "Title \(title.index + 1)" }
        let details = [summary.durationText, summary.sizeText, summary.chaptersText]
            .compactMap { $0 }
            .joined(separator: ", ")
        return details.isEmpty ? summary.displayName : "\(summary.displayName) — \(details)"
    }

    // MARK: - Destination

    @ViewBuilder
    private var destinationSection: some View {
        Section("Destination") {
            HStack {
                TextField("Destination folder", text: $viewModel.destinationPath, prompt: Text("Choose a folder\u{2026}"))
                Button("Choose\u{2026}") { chooseDestination() }
            }
            Text("MakeMKV saves one .mkv file per selected title in this folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Run

    @ViewBuilder
    private var runSection: some View {
        Section {
            if viewModel.isRipping {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(viewModel.ripProgress?.runLabel ?? "Ripping\u{2026}")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", role: .cancel) { viewModel.cancelRip() }
                    }
                    if let progress = viewModel.ripProgress {
                        ProgressView(value: progress.overallFraction)
                        if let caption = progress.currentCaption {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Button {
                    viewModel.rip()
                } label: {
                    Label("Rip Selected Titles", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canRip)
                .accessibilityLabel("Rip the selected titles to the destination folder")
            }

            Text("Titles are ripped one at a time. Leaving this screen cancels a rip in progress.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Outcome

    @ViewBuilder
    private var outcomeSection: some View {
        if let outcome = viewModel.outcomeMessage {
            Section {
                Label(outcome, systemImage: viewModel.outcomeIsError ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(viewModel.outcomeIsError ? .red : .green)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messagesSection: some View {
        if !viewModel.messages.isEmpty {
            Section("Messages") {
                ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { _, message in
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - File pickers

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Destination Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.destinationPath = url.path
    }

    private func chooseISO() {
        let panel = NSOpenPanel()
        panel.title = "Choose Disc Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // `allowedContentTypes` deliberately left unset — UTType.diskImage
        // is unproven in this codebase (see MakeMKVSettingsTab.browseBinary()
        // for the same shape on the makemkvcon path picker).
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.isoPath = url.path
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MakeMKV Rip") {
    MakeMKVRipView()
        .frame(width: 700, height: 700)
}
#endif
