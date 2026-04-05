// ============================================================================
// MeedyaConverter — PostEncodeActionsView (Issue #277)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - PostEncodeActionsView

/// A view for managing post-encode actions (hooks) that run after each job.
///
/// Displays an ordered list of configured actions with enable/disable toggles,
/// an "Add Action" button with a type picker, per-action configuration fields,
/// drag-to-reorder support, and a dry-run test button.
///
/// Phase 17 — Post-Encode Hooks (Issue #277)
struct PostEncodeActionsView: View {

    // MARK: - State

    /// The ordered chain of post-encode actions.
    @State private var actionChain = PostEncodeActionChain()

    /// Whether the add-action sheet is presented.
    @State private var showAddSheet = false

    /// The selected action type for the add-action sheet.
    @State private var selectedType: PostEncodeActionType = .openInFinder

    /// Feedback message displayed after a test run.
    @State private var testFeedback: String?

    /// Whether a test action is currently running.
    @State private var isTesting = false

    // MARK: - Body

    var body: some View {
        Form {
            // MARK: Actions List
            Section("Post-Encode Actions") {
                if actionChain.actions.isEmpty {
                    ContentUnavailableView(
                        "No Actions Configured",
                        systemImage: "bolt.slash",
                        description: Text("Add actions to run automatically after encoding completes.")
                    )
                } else {
                    List {
                        ForEach($actionChain.actions) { $action in
                            PostEncodeActionRow(action: $action) {
                                removeAction(id: action.id)
                            }
                        }
                        .onMove(perform: moveActions)
                    }
                    .frame(minHeight: 120)
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Action", systemImage: "plus.circle")
                }
                .accessibilityLabel("Add a new post-encode action")
            }

            // MARK: Test
            Section("Testing") {
                HStack {
                    Button {
                        testActions()
                    } label: {
                        Label("Test Actions (Dry Run)", systemImage: "play.circle")
                    }
                    .disabled(actionChain.actions.isEmpty || isTesting)
                    .accessibilityLabel("Run all enabled actions as a dry run test")

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let feedback = testFeedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(feedback.contains("Error") ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Post-Encode Actions")
        .sheet(isPresented: $showAddSheet) {
            AddActionSheet(
                selectedType: $selectedType,
                onAdd: { addAction(type: selectedType) }
            )
        }
    }

    // MARK: - Actions

    /// Add a new action of the specified type with a default name and config.
    ///
    /// - Parameter type: The post-encode action type to add.
    private func addAction(type: PostEncodeActionType) {
        let name: String
        let config: [String: String]

        switch type {
        case .moveSourceToTrash:
            name = "Move Source to Trash"
            config = [:]
        case .openInFinder:
            name = "Reveal in Finder"
            config = [:]
        case .runShellScript:
            name = "Run Shell Script"
            config = ["script": ""]
        case .webhook:
            name = "Send Webhook"
            config = ["url": ""]
        case .uploadSFTP:
            name = "Upload via SFTP"
            config = [:]
        case .uploadCloud:
            name = "Upload to Cloud"
            config = [:]
        case .sendNotification:
            name = "Send Notification"
            config = ["title": "MeedyaConverter", "message": "Encoding of {input} completed with status: {status}"]
        }

        let action = PostEncodeAction(
            type: type,
            name: name,
            config: config
        )
        actionChain.actions.append(action)
    }

    /// Remove an action by its unique identifier.
    ///
    /// - Parameter id: The UUID of the action to remove.
    private func removeAction(id: UUID) {
        actionChain.actions.removeAll { $0.id == id }
    }

    /// Reorder actions via drag-and-drop.
    ///
    /// - Parameters:
    ///   - source: The indices of the items being moved.
    ///   - destination: The target index.
    private func moveActions(from source: IndexSet, to destination: Int) {
        actionChain.actions.move(fromOffsets: source, toOffset: destination)
    }

    /// Execute a dry-run test of all enabled actions.
    ///
    /// Uses placeholder URLs so no actual files are affected.
    private func testActions() {
        isTesting = true
        testFeedback = nil

        Task {
            do {
                let testInput = URL(fileURLWithPath: "/tmp/test_input.mp4")
                let testOutput = URL(fileURLWithPath: "/tmp/test_output.mp4")
                try await actionChain.execute(
                    inputURL: testInput,
                    outputURL: testOutput,
                    success: true
                )
                await MainActor.run {
                    testFeedback = "All actions completed successfully."
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testFeedback = "Error: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - PostEncodeActionRow

/// A single row in the post-encode actions list showing action details
/// with enable toggle, configuration fields, and a delete button.
struct PostEncodeActionRow: View {

    // MARK: - Properties

    /// Binding to the action being displayed and edited.
    @Binding var action: PostEncodeAction

    /// Closure called when the user requests deletion of this action.
    var onDelete: () -> Void

    /// Whether the configuration disclosure group is expanded.
    @State private var isExpanded = false

    // MARK: - Body

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            configFields
        } label: {
            HStack {
                Toggle("", isOn: $action.isEnabled)
                    .labelsHidden()
                    .accessibilityLabel("Enable \(action.name)")

                Image(systemName: iconForType(action.type))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: $action.name)
                        .textFieldStyle(.plain)
                        .fontWeight(.medium)

                    Text(action.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(action.name)")
            }
        }
    }

    // MARK: - Configuration Fields

    /// Type-specific configuration fields displayed when the row is expanded.
    @ViewBuilder
    private var configFields: some View {
        switch action.type {
        case .runShellScript:
            TextField(
                "Shell Command",
                text: Binding(
                    get: { action.config["script"] ?? "" },
                    set: { action.config["script"] = $0 }
                ),
                prompt: Text("e.g. /usr/local/bin/notify {status}")
            )
            .accessibilityLabel("Shell command to execute")

            Text("Variables: {input}, {output}, {profile}, {status}")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .webhook:
            TextField(
                "Webhook URL",
                text: Binding(
                    get: { action.config["url"] ?? "" },
                    set: { action.config["url"] = $0 }
                ),
                prompt: Text("https://example.com/webhook")
            )
            .accessibilityLabel("Webhook endpoint URL")

        case .sendNotification:
            TextField(
                "Title",
                text: Binding(
                    get: { action.config["title"] ?? "MeedyaConverter" },
                    set: { action.config["title"] = $0 }
                )
            )
            .accessibilityLabel("Notification title")

            TextField(
                "Message",
                text: Binding(
                    get: { action.config["message"] ?? "" },
                    set: { action.config["message"] = $0 }
                ),
                prompt: Text("Encoding of {input} completed.")
            )
            .accessibilityLabel("Notification message body")

            Text("Variables: {input}, {output}, {profile}, {status}")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .moveSourceToTrash, .openInFinder:
            Text("No additional configuration required.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .uploadSFTP, .uploadCloud:
            Text("This action type is not yet available.")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        // "Run on failure" toggle — common to all action types.
        Toggle("Run on failure", isOn: $action.runOnFailure)
            .font(.caption)
            .accessibilityLabel("Execute this action even when the encode fails")
    }

    // MARK: - Helpers

    /// Return an SF Symbol name for the given action type.
    ///
    /// - Parameter type: The post-encode action type.
    /// - Returns: An SF Symbol name string.
    private func iconForType(_ type: PostEncodeActionType) -> String {
        switch type {
        case .moveSourceToTrash: return "trash"
        case .openInFinder: return "folder"
        case .runShellScript: return "terminal"
        case .webhook: return "globe"
        case .uploadSFTP: return "arrow.up.to.line"
        case .uploadCloud: return "icloud.and.arrow.up"
        case .sendNotification: return "bell"
        }
    }
}

// MARK: - AddActionSheet

/// A sheet for selecting the type of post-encode action to add.
struct AddActionSheet: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    /// The selected action type.
    @Binding var selectedType: PostEncodeActionType

    /// Closure called when the user confirms the selection.
    var onAdd: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Post-Encode Action")
                .font(.headline)

            Picker("Action Type", selection: $selectedType) {
                ForEach(PostEncodeActionType.allCases, id: \.self) { type in
                    Text(displayName(for: type)).tag(type)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel("Select the type of action to add")

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    onAdd()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }

    // MARK: - Helpers

    /// Return a human-readable display name for an action type.
    ///
    /// - Parameter type: The post-encode action type.
    /// - Returns: A formatted display name string.
    private func displayName(for type: PostEncodeActionType) -> String {
        switch type {
        case .moveSourceToTrash: return "Move Source to Trash"
        case .openInFinder: return "Reveal in Finder"
        case .runShellScript: return "Run Shell Script"
        case .webhook: return "Send Webhook"
        case .uploadSFTP: return "Upload via SFTP (Future)"
        case .uploadCloud: return "Upload to Cloud (Future)"
        case .sendNotification: return "Send Notification"
        }
    }
}
