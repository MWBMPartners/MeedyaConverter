// ============================================================================
// MeedyaConverter — SettingsView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - AppearanceMode

/// The user's preferred appearance mode.
enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    /// Convert to SwiftUI ColorScheme for the preferredColorScheme modifier.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - SettingsView

/// The application preferences window, accessible via Cmd+Comma.
///
/// Organised into tabs: General, Encoding, Paths, and About.
struct SettingsView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Body

    var body: some View {
        TabView {
            // -- Appearance & Behaviour ------------------------------------
            TabSection("Appearance") {
                Tab("General", systemImage: "gearshape") {
                    GeneralSettingsTab()
                }

                Tab("Theme", systemImage: "paintpalette") {
                    ThemeSettingsView()
                }

                Tab("Shortcuts", systemImage: "keyboard") {
                    KeyboardShortcutsView()
                        .environment(viewModel.shortcutManager)
                }
            }

            // -- Encoding & Processing -------------------------------------
            TabSection("Encoding") {
                Tab("Encoding", systemImage: "film.stack") {
                    EncodingSettingsTab()
                }

                Tab("Paths", systemImage: "folder") {
                    PathSettingsTab()
                }

                Tab("Watch Folder", systemImage: "eye") {
                    WatchFolderView()
                }

                Tab("Hooks", systemImage: "bolt.horizontal") {
                    PostEncodeActionsView()
                }
            }

            // -- Integration & Services ------------------------------------
            TabSection("Services") {
                Tab("Notifications", systemImage: "bell") {
                    NotificationSettingsTab()
                }

                Tab("Webhooks", systemImage: "globe") {
                    WebhookSettingsView()
                }

                Tab("Media Server", systemImage: "server.rack") {
                    MediaServerSettingsView()
                }

                Tab("Analytics", systemImage: "chart.bar") {
                    AnalyticsSettingsView()
                }

                Tab("Plugins", systemImage: "puzzlepiece") {
                    PluginManagerView()
                }
            }

            // -- Account & Info --------------------------------------------
            TabSection("Account") {
                Tab("Subscription", systemImage: "creditcard") {
                    SubscriptionSettingsTab()
                }

                Tab("Updates", systemImage: "arrow.triangle.2.circlepath") {
                    UpdateSettingsTab()
                }

                Tab("About", systemImage: "info.circle") {
                    AboutTab()
                }
            }
        }
        .frame(width: 600, height: 450)
    }
}

// MARK: - GeneralSettingsTab

/// General application settings: appearance, behaviour.
struct GeneralSettingsTab: View {
    @Environment(AppViewModel.self) private var viewModel
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("confirmBeforeEncoding") private var confirmBeforeEncoding = false
    @AppStorage("showMenuBarStatus") private var showMenuBarStatus = true
    @AppStorage("autoScrollLog") private var autoScrollLog = true

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Application theme")
            }

            Section("Behaviour") {
                Toggle("Confirm before starting encoding", isOn: $confirmBeforeEncoding)
                    .accessibilityLabel("Show confirmation dialog before encoding starts")

                Toggle("Show status in menu bar", isOn: $showMenuBarStatus)
                    .accessibilityLabel("Show encoding status in the menu bar")

                Toggle("Auto-scroll activity log", isOn: $autoScrollLog)
                    .accessibilityLabel("Automatically scroll to newest log entries")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - EncodingSettingsTab

/// Encoding-related settings: default profile, hardware acceleration, concurrency.
struct EncodingSettingsTab: View {
    @Environment(AppViewModel.self) private var viewModel
    @AppStorage("defaultProfileName") private var defaultProfileName = "Web Standard"
    @AppStorage("useHardwareAcceleration") private var useHardwareAcceleration = false
    @AppStorage("overwriteExisting") private var overwriteExisting = false
    @AppStorage("deleteSourceAfterEncode") private var deleteSourceAfterEncode = false

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default Profile", selection: $defaultProfileName) {
                    ForEach(viewModel.engine.profileStore.profiles) { profile in
                        Text(profile.name).tag(profile.name)
                    }
                }

                Toggle("Prefer hardware acceleration", isOn: $useHardwareAcceleration)
                    .accessibilityLabel("Use VideoToolbox hardware encoding when available")
            }

            Section("File Handling") {
                Toggle("Overwrite existing output files", isOn: $overwriteExisting)
                    .accessibilityLabel("Overwrite files that already exist at the output path")

                Toggle("Delete source after successful encode", isOn: $deleteSourceAfterEncode)
                    .foregroundStyle(deleteSourceAfterEncode ? .red : .primary)
                    .accessibilityLabel("Delete the source file after encoding completes successfully")

                if deleteSourceAfterEncode {
                    Text("Source files will be permanently deleted after encoding. This cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Encoding")
    }
}

// MARK: - PathSettingsTab

/// Path configuration: FFmpeg location, output directory, temp directory.
struct PathSettingsTab: View {
    @Environment(AppViewModel.self) private var viewModel
    @AppStorage("customFFmpegPath") private var customFFmpegPath = ""
    @AppStorage("customFFprobePath") private var customFFprobePath = ""

    var body: some View {
        @Bindable var vm = viewModel

        Form {
            Section("Output") {
                HStack {
                    LabeledContent("Default Output Directory") {
                        Text(viewModel.outputDirectory?.path ?? "Not set")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Choose...") {
                        chooseOutputDirectory()
                    }
                }
            }

            Section("FFmpeg") {
                HStack {
                    TextField("FFmpeg Path", text: $customFFmpegPath,
                              prompt: Text("Auto-detect"))
                    Button("Browse...") {
                        if let path = browseBinary() {
                            customFFmpegPath = path
                        }
                    }
                }
                .accessibilityLabel("Custom FFmpeg binary path")

                HStack {
                    TextField("FFprobe Path", text: $customFFprobePath,
                              prompt: Text("Auto-detect"))
                    Button("Browse...") {
                        if let path = browseBinary() {
                            customFFprobePath = path
                        }
                    }
                }
                .accessibilityLabel("Custom FFprobe binary path")

                // Show detected version
                if let info = viewModel.engine.ffmpegInfo {
                    LabeledContent("Detected FFmpeg", value: info.path)
                }
                if let info = viewModel.engine.ffprobeInfo {
                    LabeledContent("Detected FFprobe", value: info.path)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Paths")
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Default Output Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        if let current = viewModel.outputDirectory {
            panel.directoryURL = current
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.outputDirectory = url
    }

    private func browseBinary() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Select Binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}

// MARK: - NotificationSettingsTab

/// Notification preferences for job completion events.
struct NotificationSettingsTab: View {
    @AppStorage("notifyOnCompletion") private var notifyOnCompletion = true
    @AppStorage("notifyOnFailure") private var notifyOnFailure = true
    @AppStorage("notifyOnQueueFinished") private var notifyOnQueueFinished = true
    @AppStorage("playSoundOnCompletion") private var playSoundOnCompletion = false

    var body: some View {
        Form {
            Section("macOS Notifications") {
                Toggle("Notify when a job completes", isOn: $notifyOnCompletion)
                Toggle("Notify when a job fails", isOn: $notifyOnFailure)
                Toggle("Notify when the queue finishes", isOn: $notifyOnQueueFinished)
            }

            Section("Sound") {
                Toggle("Play sound on completion", isOn: $playSoundOnCompletion)
            }

            Section {
                Button("Open System Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
    }
}

// MARK: - AboutTab

/// About screen showing app version, engine version, and credits.
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App icon placeholder
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(AppInfo.Application.name)
                .font(.title)
                .fontWeight(.bold)

            Text(AppInfo.Application.synopsis)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Version info
            VStack(spacing: 4) {
                Text("App Version \(AppInfo.Version.displayString)")
                    .font(.caption)
                    .monospacedDigit()
                Text("Engine \(ConverterEngine.version)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(maxWidth: 200)

            // Copyright
            Text(AppInfo.Copyright.statement)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AppInfo.Copyright.rightsStatement)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            // Links
            HStack(spacing: 20) {
                Link("Website", destination: URL(string: AppInfo.Application.websiteURL)!)
                    .font(.caption)
                Link("Privacy Policy", destination: URL(string: "https://meedya.app/privacy")!)
                    .font(.caption)
                Link("Licenses", destination: URL(string: "https://meedya.app/licenses")!)
                    .font(.caption)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - UpdateSettingsTab

/// Update settings: Sparkle auto-check configuration and manual update check.
///
/// In direct distribution builds (non-App Store), this integrates with Sparkle 2
/// for auto-update checking. In App Store builds, it shows that updates are
/// managed by the Mac App Store.
///
/// Phase 9 — Update Checker (Issue #94)
struct UpdateSettingsTab: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        let updateChecker = viewModel.updateChecker

        Form {
            if updateChecker.isSparkleAvailable {
                Section("Automatic Updates") {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updateChecker.automaticallyChecksForUpdates },
                        set: { updateChecker.automaticallyChecksForUpdates = $0 }
                    ))
                    .accessibilityLabel("Enable automatic update checking on launch")

                    if let lastCheck = updateChecker.lastUpdateCheckDate {
                        LabeledContent("Last checked") {
                            Text(lastCheck, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Manual Check") {
                    HStack {
                        Button {
                            updateChecker.checkForUpdates()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(!updateChecker.canCheckForUpdates || updateChecker.isCheckingForUpdates)

                        Spacer()

                        if updateChecker.isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Text(updateChecker.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("Updates are verified using EdDSA (Ed25519) code signatures before installation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Updates") {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                            .foregroundStyle(.secondary)
                        Text("Updates are managed by the Mac App Store.")
                            .foregroundStyle(.secondary)
                    }

                    Button("Open App Store Updates") {
                        if let url = URL(string: "macappstore://showUpdatesPage") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Updates")
    }
}

// MARK: - SubscriptionSettingsTab

/// Subscription management tab showing the current tier, upgrade options,
/// and license key entry for direct-distribution builds.
///
/// Phase 15 — Monetization / Licensing (Issues #309, #310, #311)
struct SubscriptionSettingsTab: View {
    @Environment(StoreManager.self) private var storeManager

    /// Whether the paywall sheet is presented.
    @State private var showPaywall: Bool = false

    var body: some View {
        Form {
            // Current tier section
            Section("Current Plan") {
                HStack(spacing: 12) {
                    Image(systemName: storeManager.currentTier.systemImage)
                        .font(.title2)
                        .foregroundStyle(tierColor(storeManager.currentTier))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("MeedyaConverter \(storeManager.currentTier.displayName)")
                            .font(.headline)
                        Text(storeManager.currentTier.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if storeManager.currentTier != .pro {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Upgrade", systemImage: "arrow.up.circle")
                    }
                }
            }

            // Entitled features summary
            Section("Your Features") {
                let entitled = FeatureGateManager.shared.entitledFeatures
                if entitled.isEmpty {
                    Text("No features available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entitled, id: \.self) { feature in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(feature.displayName)
                                .font(.caption)
                        }
                    }
                }
            }

            // License key section (for direct distribution)
            Section("License Key") {
                LicenseEntryView()
            }

            // Subscription management
            Section("Manage") {
                Button("Restore Purchases") {
                    Task {
                        await storeManager.restorePurchases()
                    }
                }
                .font(.caption)

                Link(
                    "Manage App Store Subscriptions",
                    destination: URL(string: "https://apps.apple.com/account/subscriptions")!
                )
                .font(.caption)

                Link(
                    "Purchase License Key (Direct)",
                    destination: URL(string: "https://meedya.app/purchase")!
                )
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Subscription")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    /// Color for the current tier badge.
    private func tierColor(_ tier: MonetizationTier) -> Color {
        switch tier {
        case .free: return .secondary
        case .plus: return .blue
        case .pro:  return .orange
        }
    }
}
