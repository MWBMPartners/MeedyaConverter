// ============================================================================
// MeedyaConverter — MeedyaDB settings tab (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Where someone switches on contributing identified discs to MeedyaDB, and
// tells the app where the server is. Same shape as `MakeMKVSettingsTab`: a
// master toggle gating the subordinate sections, engine-owned `Keys`
// constants rather than string literals in the view, and an honest Status
// section recomputed on appear and on every change — never a dead control.
//
// ⚠️ THE API KEY IS NEVER SHOWN AND NEVER STORED IN SETTINGS.
// `@AppStorage` writes to `UserDefaults`, which is a plain-text plist in the
// user's Library. The key goes to the system Keychain through
// `APIKeyManager` (provider `.meedyaDB`). It is never put in a plain
// `TextField` and never echoed back on screen — once saved, the only things
// offered are "replace it" and "remove it".
//
// Precisely: the key is not kept in a property of its own, but `readiness`
// does hold a `MeedyaDBPublisherConfig` containing it for the view's
// lifetime, because that is what the verdict is computed from. Nothing
// renders, logs or copies it from there. Worth knowing rather than glossing:
// "never in memory" would be a comfortable thing to write and untrue.
// ============================================================================

import SwiftUI
import Combine
import ConverterEngine

// MARK: - MeedyaDBSettingsTab

struct MeedyaDBSettingsTab: View {

    // MARK: Stored settings (engine-owned key spelling — see MeedyaDBConfigStore.Keys)

    @AppStorage(MeedyaDBConfigStore.Keys.enabled)
    private var enabled: Bool = false
    @AppStorage(MeedyaDBConfigStore.Keys.baseURL)
    private var baseURL: String = ""
    @AppStorage(MeedyaDBConfigStore.Keys.submissionMode)
    private var submissionMode: String = "anonymous"

    // MARK: View state

    /// Not `@Observable`, so it never drives a redraw on its own — every
    /// change here goes through `refresh()`, which sets the state below.
    @State private var keyManager = APIKeyManager()

    /// What the user is typing into the secure field. Cleared the moment it
    /// is saved, so a pending key never lingers in memory longer than needed.
    @State private var pendingKey: String = ""

    /// Whether a key exists — NOT the key itself.
    @State private var hasStoredKey = false

    /// Why the last Save/Replace/Remove changed nothing, in plain English;
    /// nil after one that worked. The Status section below reports on
    /// readiness, not on the last button press, so without this a refused
    /// save (`APIKeyStoreError` — the list of saved keys could not be read
    /// safely) would have looked exactly like a successful one. The error
    /// wording names no key and no file.
    @State private var keyError: String?

    @State private var readiness: MeedyaDBReadiness?

    // MARK: Body

    var body: some View {
        Form {
            optInSection
            if enabled {
                serverSection
                apiKeySection
                privacySection
                statusSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("MeedyaDB")
        .onAppear { refresh() }
        .onChange(of: enabled) { refresh() }
        .onChange(of: baseURL) { refresh() }
        // `keyManager` is a long-lived `@State` instance, so it has no way
        // to notice on its own when ANOTHER `APIKeyManager` instance (e.g.
        // `CloudStorageView`'s, in the main window, or `MetadataSettingsTab`'s)
        // changes the MeedyaDB record. `didChangeNotification` is how a
        // manager announces its own writes; without this, "A key is
        // saved…" and the readiness verdict below it could go on showing
        // stale information until this tab happened to redraw for some
        // unrelated reason.
        .onReceive(
            NotificationCenter.default.publisher(for: APIKeyManager.didChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            refresh()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var optInSection: some View {
        Section("MeedyaDB (optional)") {
            Toggle("Contribute identified discs to MeedyaDB", isOn: $enabled)
                .accessibilityLabel("Contribute identified discs to the MeedyaDB shared database")

            Text(
                "MeedyaDB is a shared database of media and the links between them. "
                + "When this is on, a disc you identify can be sent to it so others "
                + "can recognise the same disc. Identifying a disc works perfectly "
                + "well with this off — nothing is sent, and nothing stops working."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        Section("Server") {
            TextField(
                "Server address",
                text: $baseURL,
                prompt: Text("https://your-meedyadb-server")
            )
            .accessibilityLabel("MeedyaDB server address")

            Text("The address of the MeedyaDB server you contribute to.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        Section("API key") {
            if hasStoredKey {
                Label("A key is saved in your Keychain", systemImage: "key.fill")
                    .foregroundStyle(.green)
                Text(
                    "For your safety the saved key is never shown again. You can "
                    + "replace it by entering a new one, or remove it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // SecureField, never TextField: the key must not be readable over
            // the user's shoulder or captured in a screen recording.
            SecureField(
                hasStoredKey ? "Replace the saved key" : "API key",
                text: $pendingKey,
                prompt: Text("mdk_live_\u{2026}")
            )
            .accessibilityLabel(hasStoredKey ? "Replace the saved MeedyaDB API key" : "MeedyaDB API key")

            HStack {
                Button(hasStoredKey ? "Replace Key" : "Save Key") { saveKey() }
                    .disabled(trimmedPendingKey.isEmpty)
                if hasStoredKey {
                    Button("Remove Key", role: .destructive) { removeKey() }
                }
            }

            if let keyError {
                Label(keyError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if trimmedPendingKey.isEmpty && !hasStoredKey {
                Text("Enter the key your MeedyaDB server issued you, then choose Save Key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Saved to your Keychain, never to the app's settings file.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        Section("What gets sent") {
            Picker("Send", selection: $submissionMode) {
                Text("Just the disc's identity").tag("anonymous")
                Text("Identity and the disc's label").tag("full")
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel("How much information to send to MeedyaDB")

            Text(
                "Just the disc's identity sends only its identifiers, its track "
                + "layout and how many tracks it has. It never includes your file "
                + "paths, your library, or anything about you."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if submissionMode == "full" {
                Label(
                    "This also sends the text printed on the disc, which on a "
                    + "home-made disc may be something you wrote yourself.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            if let readiness {
                switch readiness {
                case .ready:
                    Label("Ready to contribute", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                case .incomplete(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                case .off:
                    // This section only renders while the toggle is on, so
                    // reaching `.off` here would mean the stored setting and
                    // the toggle disagree — say that plainly rather than
                    // showing the engine's generic "turn it on" text.
                    Label(
                        "Contributing looks switched off. Try toggling it off and on again.",
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

    private var trimmedPendingKey: String {
        pendingKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Re-reads the on-disk key index and the Keychain — through
    /// `keyManager.key(for:)`, which itself now re-reads `api_keys.json`
    /// from disk before answering (Codex catch-up review finding 2)
    /// rather than trusting whatever `keyManager` last loaded — and
    /// recomputes the verdict. The key is held in a local for the length
    /// of this call only — never in view state.
    private func refresh() {
        let stored = keyManager.key(for: .meedyaDB)?.apiKey
        hasStoredKey = !(stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // @AppStorage writes to `.standard`, which is what the engine reads,
        // so this verdict is the one a real contribution would see.
        readiness = MeedyaDBGate.readiness(in: .standard, apiKey: stored)
    }

    private func saveKey() {
        let key = trimmedPendingKey
        guard !key.isEmpty else { return }
        do {
            try keyManager.storeKey(
                StoredAPIKey(provider: .meedyaDB, apiKey: key, label: "MeedyaDB")
            )
            pendingKey = ""
            keyError = nil
        } catch {
            // Refused, and nothing changed. The typed key stays in the
            // (secure) field so trying again is one click, not a retype.
            keyError = "The key was not saved. " + error.localizedDescription
        }
        refresh()
    }

    private func removeKey() {
        do {
            try keyManager.removeKey(provider: .meedyaDB, label: "MeedyaDB")
            // Also clear a key saved without our label, so "Remove" always
            // means removed rather than "removed the one I happened to name".
            try keyManager.removeKey(provider: .meedyaDB)
            pendingKey = ""
            keyError = nil
        } catch {
            // "did not finish" rather than "was not removed": the list could
            // in principle become unreadable between the two calls above, in
            // which case the labelled key IS gone. `refresh()` below shows
            // what is actually saved now.
            keyError = "Removing the key did not finish. " + error.localizedDescription
        }
        refresh()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MeedyaDB Settings") {
    MeedyaDBSettingsTab()
        .frame(width: 600, height: 450)
}
#endif
