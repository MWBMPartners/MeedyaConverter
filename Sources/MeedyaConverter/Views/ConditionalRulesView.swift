// ============================================================================
// MeedyaConverter — ConditionalRulesView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides the UI for managing conditional encoding rules:
//
//   - List of rules with drag-to-reorder priority ordering.
//   - Inline enable/disable toggle per rule.
//   - Rule editor sheet: condition builder with dropdowns for
//     field/operator/value, profile selector, add/remove conditions.
//   - "Test Rules" button to show which rule matches the currently
//     selected file.
//   - All conditions within a rule use AND logic.
//
// Rules are persisted via `@AppStorage` as JSON. The rule engine
// (`RuleEngine`) evaluates rules at encode time to auto-select profiles.
//
// Phase 11 — Conditional Encoding Rules (Issue #276)
// ---------------------------------------------------------------------------

import SwiftUI
import ConverterEngine

// MARK: - ConditionalRulesView

/// Manages conditional encoding rules that auto-select profiles based
/// on source file properties.
struct ConditionalRulesView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The list of conditional rules, persisted as JSON in UserDefaults.
    @State private var rules: [ConditionalRule] = []

    /// The rule currently being edited in the sheet. Nil when the editor
    /// is closed.
    @State private var editingRule: ConditionalRule?

    /// Whether the rule editor sheet is presented.
    @State private var showEditor = false

    /// Whether the currently editing rule is new (not yet in the list).
    @State private var isNewRule = false

    /// The result message from the "Test Rules" action.
    @State private var testResultMessage: String?

    /// Whether the test result alert is shown.
    @State private var showTestResult = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conditional Encoding Rules")
                        .font(.headline)
                    Text("Rules are evaluated in priority order. The first matching rule determines the encoding profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Test Rules button
                Button {
                    testRules()
                } label: {
                    Label("Test Rules", systemImage: "play.circle")
                }
                .help("Test which rule matches the currently selected file")
                .disabled(viewModel.selectedFile == nil)

                // Add Rule button
                Button {
                    addNewRule()
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            // Rules List
            if rules.isEmpty {
                ContentUnavailableView {
                    Label("No Rules", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Add conditional rules to automatically select encoding profiles based on source file properties.")
                } actions: {
                    Button("Add Rule") {
                        addNewRule()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(rules) { rule in
                        ruleRow(rule)
                    }
                    .onMove(perform: moveRules)
                    .onDelete(perform: deleteRules)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onAppear {
            loadRules()
        }
        .sheet(isPresented: $showEditor) {
            if let rule = editingRule {
                RuleEditorView(
                    rule: rule,
                    isNew: isNewRule,
                    profiles: viewModel.engine.profileStore.profiles,
                    onSave: { savedRule in
                        saveRule(savedRule)
                        showEditor = false
                    },
                    onCancel: {
                        showEditor = false
                    }
                )
            }
        }
        .alert(
            "Rule Test Result",
            isPresented: $showTestResult
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testResultMessage ?? "No result")
        }
        .accessibilityLabel("Conditional encoding rules manager")
    }

    // MARK: - Rule Row

    /// A single row in the rules list showing name, conditions summary,
    /// profile, and enable toggle.
    @ViewBuilder
    private func ruleRow(_ rule: ConditionalRule) -> some View {
        HStack(spacing: 12) {
            // Priority badge
            Text("\(rule.priority)")
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(rule.isEnabled ? Color.accentColor : Color.secondary.opacity(0.3))
                )
                .foregroundStyle(.white)

            // Rule info
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .fontWeight(.medium)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)

                Text(conditionsSummary(rule.conditions))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Target profile name
            if let profile = viewModel.engine.profileStore.profile(id: rule.profileId) {
                Text(profile.name)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }

            // Enable/disable toggle
            Toggle("Enabled", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                        rules[index].isEnabled = newValue
                        persistRules()
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            // Edit button
            Button {
                editingRule = rule
                isNewRule = false
                showEditor = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit this rule")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.name), priority \(rule.priority), \(rule.isEnabled ? "enabled" : "disabled")")
    }

    // MARK: - Actions

    /// Creates a new blank rule and opens the editor.
    private func addNewRule() {
        let nextPriority = (rules.map(\.priority).max() ?? -1) + 1
        let defaultProfileId = viewModel.engine.profileStore.profiles.first?.id ?? UUID()
        let newRule = ConditionalRule(
            name: "New Rule",
            conditions: [],
            profileId: defaultProfileId,
            priority: nextPriority
        )
        editingRule = newRule
        isNewRule = true
        showEditor = true
    }

    /// Saves a rule (add or update) and persists to disk.
    private func saveRule(_ rule: ConditionalRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persistRules()
    }

    /// Reorders rules by drag gesture.
    private func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        // Re-assign priorities based on new order
        for (index, _) in rules.enumerated() {
            rules[index].priority = index
        }
        persistRules()
    }

    /// Deletes rules at the given offsets.
    private func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        persistRules()
    }

    /// Tests which rule matches the currently selected file.
    private func testRules() {
        guard let file = viewModel.selectedFile else {
            testResultMessage = "No file is selected. Select a source file to test rules against."
            showTestResult = true
            return
        }

        if let profile = RuleEngine.evaluateRules(
            rules,
            for: file,
            profileStore: viewModel.engine.profileStore
        ) {
            // Find the matching rule for the message
            let matchingRule = rules
                .filter(\.isEnabled)
                .sorted { $0.priority < $1.priority }
                .first { rule in
                    rule.conditions.allSatisfy { RuleEngine.evaluateCondition($0, for: file) }
                }
            testResultMessage = "Rule \"\(matchingRule?.name ?? "Unknown")\" matched.\nProfile: \(profile.name)"
        } else {
            testResultMessage = "No rules matched the selected file \"\(file.fileName)\"."
        }
        showTestResult = true
    }

    // MARK: - Persistence

    /// Loads rules from UserDefaults JSON.
    private func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: "conditionalRules") else {
            return
        }
        do {
            let decoder = JSONDecoder()
            rules = try decoder.decode([ConditionalRule].self, from: data)
            rules.sort { $0.priority < $1.priority }
        } catch {
            // Corrupt data — start fresh
            rules = []
        }
    }

    /// Persists rules to UserDefaults as JSON.
    private func persistRules() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(rules)
            UserDefaults.standard.set(data, forKey: "conditionalRules")
        } catch {
            // Encoding failure is non-fatal
        }
    }

    // MARK: - Helpers

    /// Builds a summary string of a rule's conditions for display.
    private func conditionsSummary(_ conditions: [RuleCondition]) -> String {
        guard !conditions.isEmpty else { return "No conditions (always matches)" }
        let descriptions = conditions.map(\.displayDescription)
        return descriptions.joined(separator: " AND ")
    }
}

// MARK: - RuleEditorView

/// Sheet view for creating or editing a single conditional rule.
///
/// Provides fields for the rule name, condition builder with add/remove,
/// profile selector, and priority.
private struct RuleEditorView: View {

    // MARK: - Properties

    /// The rule being edited (mutated locally, committed on Save).
    @State private var rule: ConditionalRule

    /// Whether this is a new rule being created.
    let isNew: Bool

    /// Available encoding profiles for the profile picker.
    let profiles: [EncodingProfile]

    /// Callback invoked with the edited rule when the user taps Save.
    let onSave: (ConditionalRule) -> Void

    /// Callback invoked when the user taps Cancel.
    let onCancel: () -> Void

    // MARK: - Condition Builder State

    /// The type of condition being added.
    @State private var newConditionType: ConditionType = .resolution

    // MARK: - Initialiser

    init(
        rule: ConditionalRule,
        isNew: Bool,
        profiles: [EncodingProfile],
        onSave: @escaping (ConditionalRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._rule = State(initialValue: rule)
        self.isNew = isNew
        self.profiles = profiles
        self.onSave = onSave
        self.onCancel = onCancel
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(isNew ? "New Rule" : "Edit Rule")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                // Rule identity
                Section("Rule") {
                    TextField("Name", text: $rule.name)
                        .accessibilityLabel("Rule name")

                    Picker("Profile", selection: $rule.profileId) {
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .accessibilityLabel("Target encoding profile")

                    Stepper(
                        "Priority: \(rule.priority)",
                        value: $rule.priority,
                        in: 0...999
                    )
                    .accessibilityLabel("Rule priority, lower is evaluated first")

                    Toggle("Enabled", isOn: $rule.isEnabled)
                }

                // Conditions
                Section("Conditions (AND logic)") {
                    if rule.conditions.isEmpty {
                        Text("No conditions. This rule will match all files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(rule.conditions.enumerated()), id: \.element.id) { index, condition in
                        HStack {
                            Text(condition.displayDescription)
                                .font(.callout)

                            Spacer()

                            Button(role: .destructive) {
                                rule.conditions.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this condition")
                        }
                    }

                    // Add condition section
                    addConditionSection
                }
            }
            .formStyle(.grouped)

            Divider()

            // Action buttons
            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Save") {
                    onSave(rule)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 550, height: 550)
    }

    // MARK: - Add Condition Section

    /// UI for selecting and adding a new condition to the rule.
    @ViewBuilder
    private var addConditionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Add condition", selection: $newConditionType) {
                    ForEach(ConditionType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()

                Button {
                    addCondition(of: newConditionType)
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - Condition Creation

    /// Adds a default condition of the given type to the rule.
    ///
    /// Default values are chosen to be reasonable starting points
    /// that the user can then adjust.
    private func addCondition(of type: ConditionType) {
        let condition: RuleCondition
        switch type {
        case .resolution:
            condition = .resolution(op: .greaterOrEqual, width: 3840, height: 2160)
        case .codec:
            condition = .codec(is: .h264)
        case .hasHDR:
            condition = .hasHDR(true)
        case .duration:
            condition = .duration(op: .greaterThan, seconds: 3600)
        case .fileSize:
            condition = .fileSize(op: .greaterThan, bytes: 4_294_967_296) // 4 GB
        case .fileExtension:
            condition = .extension("mkv")
        case .channelCount:
            condition = .channelCount(op: .greaterThan, count: 2)
        }
        rule.conditions.append(condition)
    }
}

// MARK: - ConditionType

/// Enum for the condition type picker in the rule editor.
///
/// Maps to `RuleCondition` cases but is simpler (no associated values)
/// for use in a SwiftUI `Picker`.
private enum ConditionType: String, CaseIterable, Identifiable {
    case resolution
    case codec
    case hasHDR
    case duration
    case fileSize
    case fileExtension
    case channelCount

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .resolution: return "Resolution"
        case .codec: return "Video Codec"
        case .hasHDR: return "HDR"
        case .duration: return "Duration"
        case .fileSize: return "File Size"
        case .fileExtension: return "File Extension"
        case .channelCount: return "Audio Channels"
        }
    }
}
