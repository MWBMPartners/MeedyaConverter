// ============================================================================
// MeedyaConverter — DiscIdentifyView (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Identify a music disc in the app: read its table of contents from a drive
// or from a `.toc` file saved earlier, show what it is, and — only when
// MeedyaDB is switched on in Settings — contribute it.
//
// Two deliberate behaviours:
//
//   * When macOS is holding the drive, this does NOT quietly unmount it.
//     Unmounting takes the disc away from Finder and from anything else
//     reading it, so the screen explains what happened and offers a button
//     (owner decision, 2026-09-21).
//   * The screen always says whether a contribution will be sent, BEFORE the
//     run rather than after, so nothing is uploaded that the user did not
//     expect. With MeedyaDB off it says identification still works fine.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - DiscIdentifyView

struct DiscIdentifyView: View {

    @State private var viewModel = DiscIdentifyViewModel()

    // Re-check the MeedyaDB verdict whenever its settings change, so turning
    // contributing on in Settings takes effect without leaving this screen.
    @AppStorage(MeedyaDBConfigStore.Keys.enabled)
    private var meedyaDBEnabled: Bool = false
    @AppStorage(MeedyaDBConfigStore.Keys.baseURL)
    private var meedyaDBBaseURL: String = ""

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Form {
            sourceSection
            runSection
            busySection
            contributionSection
            resultSection
        }
        .formStyle(.grouped)
        .navigationTitle("Identify Disc")
        .onAppear { viewModel.refreshMeedyaDBReadiness() }
        .onChange(of: meedyaDBEnabled) { viewModel.refreshMeedyaDBReadiness() }
        .onChange(of: meedyaDBBaseURL) { viewModel.refreshMeedyaDBReadiness() }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Source

    @ViewBuilder
    private var sourceSection: some View {
        Section("Disc") {
            Picker("Read from", selection: $viewModel.sourceKind) {
                ForEach(DiscIdentifyViewModel.SourceKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }

            switch viewModel.sourceKind {
            case .drive:
                TextField("Drive", text: $viewModel.devicePath, prompt: Text("/dev/rdisk2"))
                Text(
                    "The drive holding the disc, usually /dev/rdisk2. Disk Utility shows "
                    + "it as \"disk2\" \u{2014} add the \"r\" in front of \"disk\"."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            case .tocFile:
                HStack {
                    TextField("Table of contents", text: $viewModel.tocFilePath, prompt: Text("Choose a .toc file\u{2026}"))
                    Button("Choose\u{2026}") { chooseTOCFile() }
                }
                Text("A .toc file saved by an earlier read. Needs no disc and no drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Run

    @ViewBuilder
    private var runSection: some View {
        Section {
            if viewModel.isWorking || viewModel.isUnmounting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(viewModel.isCancelling
                         ? "Cancelling\u{2026}"
                         : (viewModel.statusMessage ?? "Working\u{2026}"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Also during the unmount: diskutil can block for a long
                    // time on a process that refuses to release the disc.
                    Button("Cancel", role: .cancel) { viewModel.cancel() }
                        .disabled(viewModel.isCancelling)
                }
            } else {
                Button {
                    viewModel.identify()
                } label: {
                    Label("Identify Disc", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStart)

                if let reason = viewModel.startBlockedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.errorMessage, viewModel.busyDevicePath == nil {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - The drive is held by something else

    @ViewBuilder
    private var busySection: some View {
        if let device = viewModel.busyDevicePath {
            Section("The drive is in use") {
                Label(
                    viewModel.errorMessage
                        ?? "This drive can't be opened right now.",
                    systemImage: "lock.circle"
                )
                .foregroundStyle(.orange)
                .font(.callout)

                Text(
                    "Usually this is because macOS mounts a disc as soon as you put it "
                    + "in, and it has to let go before the disc can be read properly. "
                    + "Releasing it closes the disc in Finder and in any other app using "
                    + "it \u{2014} the disc stays in the drive, and you can eject it as "
                    + "usual afterwards.\n\nIf releasing it doesn't help, this account "
                    + "may not be allowed to read the drive directly."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button {
                    viewModel.unmountAndRetry()
                } label: {
                    Label("Release \(device) and Try Again", systemImage: "eject")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isUnmounting || viewModel.isWorking)
                .accessibilityLabel("Release the drive and try identifying the disc again")
            }
        }
    }

    // MARK: - Will anything be sent?

    @ViewBuilder
    private var contributionSection: some View {
        Section("MeedyaDB") {
            if viewModel.willContribute {
                Label(
                    "This disc will also be contributed to MeedyaDB.",
                    systemImage: "arrow.up.circle"
                )
                .foregroundStyle(.green)
                .font(.callout)
            } else {
                Label(
                    viewModel.meedyaDBReadiness?.reason
                        ?? "Nothing will be sent to MeedyaDB.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
                .font(.callout)

                Text("Identifying works perfectly well without this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Settings\u{2026}") { openSettings() }
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultSection: some View {
        if let result = viewModel.result {
            Section("What this disc is") {
                Text(result.summary)
                    .font(.headline)
                    .textSelection(.enabled)

                ForEach(result.matches, id: \.id) { match in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(matchLine(for: match))
                            .textSelection(.enabled)
                        Text("MusicBrainz release \(match.id)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let failure = result.lookupFailure {
                    Label(failure, systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("This disc's fingerprint") {
                if let music = result.identity.musicDiscID {
                    LabeledContent("Disc ID", value: music)
                }
                if result.identity.isEnhancedCD, let whole = result.identity.wholeDiscID {
                    LabeledContent("Whole-disc ID", value: whole)
                    Text(
                        "This is an Enhanced CD \u{2014} it carries computer files as well as "
                        + "music. MusicBrainz is asked about the music; both are recorded."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                LabeledContent("Audio tracks", value: String(result.identity.audioTrackCount))
            }

            Section("Contribution") {
                switch result.contribution {
                case .succeeded(let ingest):
                    Label(
                        ingest.matched
                            ? "Sent to MeedyaDB and matched to a release it already knew."
                            : "Sent to MeedyaDB and recorded as a disc it hadn't seen before.",
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.green)
                    .font(.callout)
                case .notAttempted(let reason):
                    Label(reason, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                case .failed(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
        }
    }

    private func matchLine(for match: MusicBrainzDiscMatch) -> String {
        var line = match.title
        if let artist = match.artist { line += " \u{2014} \(artist)" }
        var details: [String] = []
        if let year = match.year { details.append(String(year)) }
        if let country = match.country { details.append(country) }
        if let tracks = match.trackCount { details.append("\(tracks) tracks") }
        if !details.isEmpty { line += " (\(details.joined(separator: ", ")))" }
        return line
    }

    // MARK: - File picker

    private func chooseTOCFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Table of Contents"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.tocFilePath = url.path
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Identify Disc") {
    DiscIdentifyView()
        .frame(width: 700, height: 700)
}
#endif
