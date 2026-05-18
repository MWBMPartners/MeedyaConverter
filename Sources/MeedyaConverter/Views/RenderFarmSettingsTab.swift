// ============================================================================
// MeedyaConverter — RenderFarmSettingsTab
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// SwiftUI surface for `RenderFarmClient.Configuration` + the manually-added
// agent registry. Persists every user-facing preference via `@AppStorage`
// under the `renderFarm.` namespace.
//
// Engine wiring caveat (#346 transport):
//   The engine-side transport implementation in #346 has not fully landed —
//   only the agent registry, configuration types, and InsecureTransportOverride
//   token are stable. This tab therefore stores agents as a UserDefaults-
//   backed JSON list rather than tying to a live `RenderFarmClient` instance.
//   When #346 completes, the consumer reads these AppStorage keys to
//   construct its Configuration + initial agent registry.
//
// Bonjour-discovered agents are NOT present yet — discovery is part of
// the gated #346 work. The agent list shows the manual-entry workflow
// alone; the empty state explains this.
//
// GitHub Issues: #346 engine (RenderFarmClient) / #380 (InsecureTransportOverride)
//                / #381 / #406 UI.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - RenderFarmSettingsTab

struct RenderFarmSettingsTab: View {

    // -----------------------------------------------------------------
    // MARK: - Persisted state
    // -----------------------------------------------------------------

    /// Whether the user has enabled insecure (plain HTTP) transports.
    /// When `true`, the engine consumer constructs an
    /// `InsecureTransportOverride` from `insecureAcknowledgement`.
    @AppStorage("renderFarm.allowInsecureTransports") private var allowInsecureTransports: Bool = false

    /// Required acknowledgement string passed to
    /// `InsecureTransportOverride.developmentOnly(acknowledgement:)`.
    /// Empty when `allowInsecureTransports` is false; required when it
    /// is true.
    @AppStorage("renderFarm.insecureAcknowledgement") private var insecureAcknowledgement: String = ""

    /// Bonjour-discovery interval in seconds. Default matches
    /// `RenderFarmClient.Configuration.init`'s default of 30s.
    @AppStorage("renderFarm.discoveryIntervalSeconds") private var discoveryIntervalSeconds: Double = 30.0

    /// Chunk upload size in MiB. Persisted as the user-facing value
    /// (1/4/16/64) rather than raw bytes; converted to bytes when
    /// the consumer constructs the engine Configuration.
    @AppStorage("renderFarm.chunkSizeMiB") private var chunkSizeMiB: Int = 4

    /// JSON-encoded `[RenderFarmAgentInfo]` for the manually-added agent
    /// registry. Stored as `Data` rather than a String because the
    /// AppStorage `Data` initialiser is more direct than wrapping JSON
    /// in a String. An empty `Data()` decodes to `[]` via our binding.
    @AppStorage("renderFarm.agentsJSON") private var agentsJSON: Data = Data()

    // -----------------------------------------------------------------
    // MARK: - View state
    // -----------------------------------------------------------------

    /// Controls the visibility of the Add-Agent modal sheet.
    @State private var showAddAgentSheet: Bool = false

    // -----------------------------------------------------------------
    // MARK: - Computed bindings
    // -----------------------------------------------------------------

    /// Decodes / re-encodes the JSON-backed agent list. On any decode
    /// failure (corrupt blob, future schema) we surface an empty list
    /// so the UI never crashes — the user can re-add agents manually.
    private var agents: [RenderFarmAgentInfo] {
        guard !agentsJSON.isEmpty,
              let decoded = try? JSONDecoder().decode(
                [RenderFarmAgentInfo].self, from: agentsJSON)
        else {
            return []
        }
        return decoded
    }

    /// Available chunk-size choices, in MiB. Matches the four options
    /// listed in the #381 acceptance criteria.
    private static let chunkSizeChoicesMiB: [Int] = [1, 4, 16, 64]

    // -----------------------------------------------------------------
    // MARK: - Body
    // -----------------------------------------------------------------

    var body: some View {
        Form {
            insecureTransportSection
            discoverySection
            chunkSizeSection
            agentsSection
        }
        .formStyle(.grouped)
        .navigationTitle("Render Farm")
        .sheet(isPresented: $showAddAgentSheet) {
            AddRenderFarmAgentSheet { newAgent in
                appendAgent(newAgent)
            }
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Sections
    // -----------------------------------------------------------------

    @ViewBuilder
    private var insecureTransportSection: some View {
        Section("Transport security") {
            Toggle(
                "Allow insecure transports (plain HTTP)",
                isOn: $allowInsecureTransports
            )
            .accessibilityLabel(
                "Allow plain HTTP submissions; not recommended"
            )

            if allowInsecureTransports {
                // The engine's InsecureTransportOverride requires an
                // acknowledgement string. We collect it here so the
                // consumer can construct
                //   .developmentOnly(acknowledgement: ...)
                // without bouncing back to the UI.
                TextField(
                    "Acknowledgement",
                    text: $insecureAcknowledgement,
                    prompt: Text("e.g. 'local loopback, no real credentials'")
                )
                .accessibilityLabel(
                    "Acknowledgement string recorded with every insecure "
                    + "submission for audit purposes"
                )

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(
                        "Plain HTTP exposes job payloads and credentials "
                        + "to anyone on the network path. Enable only on "
                        + "trusted loopback or isolated development networks."
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var discoverySection: some View {
        Section("Bonjour discovery") {
            Stepper(
                value: $discoveryIntervalSeconds,
                in: 5...300,
                step: 5
            ) {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Text("\(Int(discoveryIntervalSeconds)) s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel(
                "Bonjour discovery refresh interval in seconds"
            )

            Text(
                "Bonjour discovery itself is not active yet (gated on "
                + "issue #346). The interval will apply once the "
                + "transport implementation lands."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chunkSizeSection: some View {
        Section("Source uploads") {
            Picker("Chunk size", selection: $chunkSizeMiB) {
                ForEach(Self.chunkSizeChoicesMiB, id: \.self) { size in
                    Text("\(size) MiB").tag(size)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(
                "Chunk size for source uploads to render-farm agents"
            )

            Text(
                "Smaller chunks resume faster after transient network "
                + "failures; larger chunks are more efficient on stable "
                + "links."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var agentsSection: some View {
        Section {
            if agents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No agents configured.")
                        .font(.subheadline)
                    Text(
                        "Bonjour-discovered agents will appear here once "
                        + "the transport implementation in #346 lands. "
                        + "In the meantime, you can add agents manually."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else {
                ForEach(agents) { agent in
                    AgentRow(agent: agent) {
                        removeAgent(id: agent.id)
                    }
                }
            }

            Button {
                showAddAgentSheet = true
            } label: {
                Label("Add agent…", systemImage: "plus.circle")
            }
            .accessibilityLabel("Add a render-farm agent manually")
        } header: {
            HStack {
                Text("Agents")
                Spacer()
                Text("\(agents.count) configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Agent registry mutations
    // -----------------------------------------------------------------

    /// Append a new agent to the JSON-backed registry. Persists via
    /// the `agentsJSON` AppStorage key. Idempotent: if an agent with
    /// the same `(host, port)` pair is already registered we replace
    /// it rather than producing a duplicate, matching the engine's
    /// `RenderFarmClient.register(agent:)` semantics.
    private func appendAgent(_ agent: RenderFarmAgentInfo) {
        var list = agents
        list.removeAll { $0.host == agent.host && $0.port == agent.port }
        list.append(agent)
        persist(list)
    }

    /// Remove an agent by id. No-op if the id is not in the list.
    private func removeAgent(id: UUID) {
        let list = agents.filter { $0.id != id }
        persist(list)
    }

    /// Encode and write the agent list back to AppStorage.
    /// On encode failure we leave the previous value in place — the
    /// alternative (silently clearing) would be far worse for the user.
    private func persist(_ list: [RenderFarmAgentInfo]) {
        guard let encoded = try? JSONEncoder().encode(list) else { return }
        agentsJSON = encoded
    }
}

// MARK: - AgentRow

/// One row in the agents list. Renders the display name, endpoint,
/// transport hint, and a discovered/manual badge. Tap the trash button
/// to remove a manually-added agent; Bonjour-discovered rows hide the
/// trash button because the engine owns their lifecycle.
private struct AgentRow: View {

    let agent: RenderFarmAgentInfo
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.displayName).font(.subheadline.bold())
                    Text(agent.discovered ? "Discovered" : "Manual")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            (agent.discovered ? Color.green : Color.blue)
                                .opacity(0.15)
                        )
                        .foregroundStyle(agent.discovered ? .green : .blue)
                        .clipShape(Capsule())
                }
                Text(agent.endpoint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let sshUser = agent.sshUsername, !sshUser.isEmpty {
                    Text("SSH user: \(sshUser)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !agent.discovered {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove agent \(agent.displayName)")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AddRenderFarmAgentSheet

/// Modal sheet for adding a render-farm agent by hand. Validates that
/// at least a host is provided before allowing Save; everything else
/// (port, SSH username, display name) falls back to reasonable defaults.
private struct AddRenderFarmAgentSheet: View {

    /// Callback invoked when the user taps Save. The parent appends
    /// the agent to the JSON-backed registry.
    let onSave: (RenderFarmAgentInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var host: String = ""
    @State private var port: Int = 2229
    @State private var sshUsername: String = ""

    /// The Save button is disabled until the form has the minimum
    /// information needed to construct a sensible `RenderFarmAgentInfo`.
    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Agent") {
                TextField(
                    "Display name",
                    text: $displayName,
                    prompt: Text("e.g. studio-tower")
                )
                .accessibilityLabel("Display name for the agent")

                TextField(
                    "Host",
                    text: $host,
                    prompt: Text("hostname or IP")
                )
                .accessibilityLabel("Agent hostname or IP address")
                .textContentType(.URL)

                Stepper(
                    value: $port,
                    in: 1...65_535,
                    step: 1
                ) {
                    HStack {
                        Text("Port")
                        Spacer()
                        Text("\(port)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("Agent TCP port; default 2229")
            }

            Section("SSH (optional)") {
                TextField(
                    "Username",
                    text: $sshUsername,
                    prompt: Text("for transport = SSH")
                )
                .accessibilityLabel("SSH username used for SSH transport")
                .textContentType(.username)

                Text(
                    "Required only when the agent is reached over SSH "
                    + "tunnels. Leave empty for TLS or plain HTTP."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Add Agent")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let agent = RenderFarmAgentInfo(
                        displayName: displayName.isEmpty
                            ? host : displayName,
                        host: host.trimmingCharacters(in: .whitespaces),
                        port: port,
                        sshUsername: sshUsername.isEmpty ? nil : sshUsername,
                        discovered: false
                    )
                    onSave(agent)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }
}
