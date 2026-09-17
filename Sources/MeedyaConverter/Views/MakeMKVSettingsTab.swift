// ============================================================================
// MeedyaConverter — MakeMKVSettingsTab
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The Settings surface for the OPTIONAL, OPT-IN MakeMKV disc-ripping backend
// (#503, slice 2b). It writes the three shared `MakeMKVConsentStore.Keys` via
// `@AppStorage`; the engine reads the same keys through `MakeMKVConsentStore` /
// `MakeMKVGate` to decide whether MakeMKV may be used and whether it is installed.
//
// Contract this UI upholds (see MakeMKVAccess.swift):
//   • OFF BY DEFAULT — the toggle starts off; nothing runs until the user turns
//     it on AND types a terms acknowledgement.
//   • HONEST — the Status section shows a real verdict (found at a path / not
//     installed / not yet acknowledged); there is never a dead "rip" button.
//   • NO BUNDLING — the user installs MakeMKV themselves; we only locate it.
// This surface changes no policy: the copy-protection refuse-gate (#492) still
// refuses protected discs on every non-MakeMKV path.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - MakeMKVSettingsTab

struct MakeMKVSettingsTab: View {

    // MARK: Persisted state (shared keys with the engine gate)

    @AppStorage(MakeMKVConsentStore.Keys.enabled)
    private var enabled: Bool = false

    @AppStorage(MakeMKVConsentStore.Keys.termsAcknowledgement)
    private var acknowledgement: String = ""

    @AppStorage(MakeMKVConsentStore.Keys.binaryPath)
    private var binaryPath: String = ""

    // MARK: View state

    /// The latest availability verdict, recomputed on appear and whenever an
    /// input changes. `nil` only for the brief moment before the first check.
    @State private var readiness: MakeMKVReadiness? = nil

    // MARK: Body

    var body: some View {
        Form {
            optInSection
            if enabled {
                acknowledgementSection
                locationSection
                statusSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("MakeMKV")
        .onAppear { refreshReadiness() }
        .onChange(of: enabled) { refreshReadiness() }
        .onChange(of: acknowledgement) { refreshReadiness() }
        .onChange(of: binaryPath) { refreshReadiness() }
    }

    // MARK: Sections

    @ViewBuilder
    private var optInSection: some View {
        Section("MakeMKV (optional)") {
            Toggle("Enable MakeMKV disc ripping", isOn: $enabled)
                .accessibilityLabel("Enable the optional MakeMKV disc-ripping backend")

            Text(
                "MakeMKV is separate software you install yourself. When enabled, "
                + "MeedyaConverter can use it to read DVDs and Blu-rays — including "
                + "copy-protected discs, which MakeMKV unlocks. MeedyaConverter never "
                + "bundles MakeMKV and never circumvents protection on its own; every "
                + "other part of the app still refuses protected discs."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var acknowledgementSection: some View {
        Section("Terms acknowledgement") {
            Text(
                "By enabling MakeMKV you confirm that you are responsible for "
                + "complying with MakeMKV's own licence terms and with the copyright "
                + "law where you live. MakeMKV stays unavailable until this box "
                + "contains your acknowledgement."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            TextField(
                "Acknowledgement",
                text: $acknowledgement,
                prompt: Text("e.g. 'I accept MakeMKV's terms and my local law'")
            )
            .accessibilityLabel("MakeMKV terms acknowledgement, required before use")
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        // Empty means "auto-detect" via BundledToolLocator (Contents/Helpers →
        // Homebrew/PATH), the same convention as the FFmpeg/vector fields.
        Section("MakeMKV location") {
            HStack {
                TextField(
                    "makemkvcon Path",
                    text: $binaryPath,
                    prompt: Text("Auto-detect")
                )
                Button("Browse...") {
                    if let path = browseBinary() {
                        binaryPath = path
                    }
                }
            }
            .accessibilityLabel("Custom makemkvcon binary path; leave blank to auto-detect")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            if let readiness {
                switch readiness {
                case .ready(let path):
                    Label("MakeMKV found", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    LabeledContent("Path", value: path)
                case .notInstalled(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                case .notEnabled:
                    // This section only renders when the toggle is on, so the
                    // only way to be "not enabled" here is a missing
                    // acknowledgement — say that, rather than the engine's
                    // generic "turn it on" reason.
                    Label(
                        "Enter your terms acknowledgement above to finish enabling MakeMKV.",
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
    }

    // MARK: Helpers

    private func refreshReadiness() {
        // @AppStorage writes to `.standard`, which is exactly what the engine
        // gate reads, so this verdict matches what a rip would actually see.
        readiness = MakeMKVGate.readiness(in: .standard)
    }

    private func browseBinary() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Locate makemkvcon"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
