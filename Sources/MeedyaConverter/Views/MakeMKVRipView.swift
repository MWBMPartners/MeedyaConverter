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
import Combine
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

    // Re-check the MeedyaDB verdict whenever its settings change, so turning
    // contributing on in Settings takes effect without leaving this screen.
    //
    // ⚠️ `.onAppear` ALONE IS NOT ENOUGH. Settings is a separate window on
    // macOS: this screen never disappears while someone changes a setting
    // there, so `.onAppear` does not fire again and the notice above the
    // Identify button goes stale. It would then say contributing is off
    // while the run — which correctly re-reads the setting — contributes,
    // or promise a contribution that was just switched off. Either way the
    // screen and the run disagree, which is the exact failure this whole
    // feature is built to avoid. `DiscIdentifyView` already does this.
    @AppStorage(MeedyaDBConfigStore.Keys.enabled)
    private var meedyaDBEnabled: Bool = false
    @AppStorage(MeedyaDBConfigStore.Keys.baseURL)
    private var meedyaDBBaseURL: String = ""

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
        .onAppear {
            viewModel.refreshGate()
            // Re-read rather than cache: switching MeedyaDB on in Settings
            // must take effect without relaunching.
            viewModel.refreshMeedyaDBReadiness()
        }
        .onChange(of: makemkvEnabled) { viewModel.refreshGate() }
        .onChange(of: makemkvAcknowledgement) { viewModel.refreshGate() }
        .onChange(of: makemkvBinaryPath) { viewModel.refreshGate() }
        .onChange(of: meedyaDBEnabled) { viewModel.refreshMeedyaDBReadiness() }
        .onChange(of: meedyaDBBaseURL) { viewModel.refreshMeedyaDBReadiness() }
        // `@AppStorage` above only covers the two settings that live in
        // `UserDefaults`. The API key lives in the Keychain instead (see
        // `MeedyaDBAccess.swift`'s file header), so adding, changing or
        // removing it fires no `.onChange` here, and this screen's notice
        // would go stale until something else redrew it. `APIKeyManager`
        // posts this notification on every write — the same fix already
        // applied to `SettingsView` and `MeedyaDBSettingsTab`, and to
        // `DiscIdentifyView` alongside this (Codex round-1 review, finding
        // F10).
        .onReceive(
            NotificationCenter.default.publisher(for: APIKeyManager.didChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            viewModel.refreshMeedyaDBReadiness()
        }
        .onDisappear {
            viewModel.cancelRip()
            viewModel.cancelScan()
            viewModel.cancelIdentify()
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
            identifySection
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
            case .discFolder:
                HStack {
                    TextField("Disc folder", text: $viewModel.folderPath, prompt: Text("Choose a folder\u{2026}"))
                    Button("Choose\u{2026}") { chooseDiscFolder() }
                }
                Text(
                    "Choose the folder that CONTAINS the VIDEO_TS or BDMV folder, not "
                    + "VIDEO_TS/BDMV itself. These files are already decrypted \u{2014} "
                    + "nothing is unlocked here."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // While a scan runs this reads "Scanning…" and is disabled; the
            // way to stop it is the Cancel button in the Titles section's
            // progress row just below, mirroring where the rip's Cancel sits.
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

            // MAJOR-3: a disabled button always says why it is disabled.
            if let reason = viewModel.scanBlockedReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                // MAJOR-2: a scan of a Blu-ray can run for minutes. Without
                // this Cancel the only way out is to navigate away, which
                // throws the whole screen (and any result) away — the same
                // "never a dead end" rule the gated view follows.
                HStack {
                    ProgressView().controlSize(.small)
                    Text(viewModel.isCancellingScan
                         ? "Cancelling the scan\u{2026}"
                         : "Scanning disc\u{2026} this can take a few minutes on a Blu-ray.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel) { viewModel.cancelScan() }
                        .disabled(viewModel.isCancellingScan)
                        .accessibilityLabel("Cancel the disc scan")
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

    // MARK: - Identify

    /// Naming the disc from what the scan found. Separate from ripping on
    /// purpose: knowing what a disc IS is useful whether or not it is about
    /// to be ripped, and contributing it helps the next person identify the
    /// same disc.
    @ViewBuilder
    private var identifySection: some View {
        Section("Identify This Disc") {
            if viewModel.discInfo == nil {
                Text("Scan the disc first. Identifying searches TMDB for films using the disc's name, then compares each result's running time with the main feature. TV series aren't searched yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                discTypePicker
                identifyControls
                if let result = viewModel.identifyResult {
                    identifyOutcome(result)
                }
                if let error = viewModel.identifyErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    /// The disc type, pre-filled from MakeMKV's own type string but always
    /// the user's to change. The caption says where the value came from,
    /// because a silently pre-filled field is one people don't check.
    private var discTypePicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker("Disc Type", selection: Binding(
                get: { viewModel.selectedDiscType },
                set: { viewModel.selectedDiscType = $0 }
            )) {
                Text("Choose\u{2026}").tag(DiscType?.none)
                ForEach(MakeMKVRipViewModel.identifiableDiscTypes, id: \.self) { type in
                    Text(type.displayName).tag(DiscType?.some(type))
                }
            }
            .disabled(viewModel.isIdentifying)

            Text(discTypeCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var discTypeCaption: String {
        if let suggested = viewModel.suggestedDiscType {
            return "MakeMKV reported this as a \(suggested.displayName). Change it if that's wrong."
        }
        return "MakeMKV didn't say what kind of disc this is, so please choose."
    }

    @ViewBuilder
    private var identifyControls: some View {
        if viewModel.isIdentifying {
            HStack {
                ProgressView().controlSize(.small)
                Text(viewModel.isCancellingIdentify
                     ? "Cancelling\u{2026}"
                     : "Identifying the disc\u{2026}")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { viewModel.cancelIdentify() }
                    .disabled(viewModel.isCancellingIdentify)
                    .accessibilityLabel("Cancel identifying the disc")
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button("Identify Disc") { viewModel.identify() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canIdentify)

                if let reason = viewModel.identifyBlockedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                contributionNotice
            }
        }
    }

    /// What this run WILL do about contributing, said before it runs. The
    /// view model derives the actual behaviour from the same value, so this
    /// can never promise something the run doesn't do.
    ///
    /// Delegates to `MakeMKVRipViewModel.showsContributionPromise`, which
    /// combines what THAT run promised, frozen at its start
    /// (`runWillContribute`), with the LIVE setting (`willContribute`) while
    /// an identify run is in progress (fallback review round 2, finding 2) —
    /// see its doc comment. Kept as a computed property here only so the
    /// view's body stays readable.
    private var showsWillContribute: Bool {
        viewModel.showsContributionPromise
    }

    @ViewBuilder
    private var contributionNotice: some View {
        if showsWillContribute {
            Text("This disc will also be contributed to MeedyaDB.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let reason = viewModel.meedyaDBReadiness?.reason {
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The result. `summary` deliberately states its own confidence — a
    /// ranked guess presented as fact is how a disc ends up filed under the
    /// wrong film — so it is shown as written rather than reworded here.
    private func identifyOutcome(_ result: VideoDiscIdentificationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.summary)
                .font(.callout)
            contributionOutcome(result.contribution)
        }
    }

    @ViewBuilder
    private func contributionOutcome(_ contribution: MeedyaDBContribution) -> some View {
        switch contribution {
        case .succeeded:
            Label("Contributed to MeedyaDB.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .notAttempted(let reason):
            // Not an error: this is the normal state for anyone who hasn't
            // set MeedyaDB up, and must not be dressed as a failure.
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Label("Couldn't contribute to MeedyaDB: \(reason)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
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
                        Text(viewModel.isCancellingRip
                             ? "Cancelling the rip\u{2026}"
                             : (viewModel.ripProgress?.runLabel ?? "Ripping\u{2026}"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", role: .cancel) { viewModel.cancelRip() }
                            .disabled(viewModel.isCancellingRip)
                            .accessibilityLabel("Cancel the rip")
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

                // MAJOR-3: say why, rather than presenting a dead button.
                if let reason = viewModel.ripBlockedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    /// Picks the PARENT of a `VIDEO_TS`/`BDMV` folder, which is what
    /// `makemkvcon` expects. If the user picks `VIDEO_TS` itself — the
    /// obvious mistake — step up to its parent rather than handing MakeMKV a
    /// path it will reject with an unhelpful message.
    private func chooseDiscFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Disc Folder"
        panel.message = "Choose the folder that contains VIDEO_TS or BDMV."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let name = url.lastPathComponent.uppercased()
        let resolved = (name == "VIDEO_TS" || name == "BDMV") ? url.deletingLastPathComponent() : url
        viewModel.folderPath = resolved.path
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
