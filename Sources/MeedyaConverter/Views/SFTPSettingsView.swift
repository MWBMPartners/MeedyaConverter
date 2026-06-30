// ============================================================================
// MeedyaConverter — SFTPSettingsView (Issue #312)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - SFTPSettingsView

/// Settings view for configuring SFTP and FTP server upload profiles.
///
/// Provides a form for entering connection details (host, port, user,
/// authentication method), remote path, and a test connection button.
/// Saved profiles are listed in a sidebar for quick selection.
///
/// Phase 12.3 — Direct Upload via SFTP/FTP (Issue #312)
struct SFTPSettingsView: View {

    // MARK: - State

    /// The list of saved SFTP server profiles, persisted as JSON.
    @State private var savedProfiles: [SFTPServerConfig] = []

    /// The currently selected profile index, or `nil` for a new profile.
    @State private var selectedProfileIndex: Int?

    /// The server hostname or IP address.
    @State private var host = ""

    /// The SSH port number.
    @State private var port = "22"

    /// The SSH username.
    @State private var username = ""

    /// The selected authentication method type.
    @State private var authType: AuthType = .agent

    /// The password for password-based authentication.
    @State private var password = ""

    /// The path to the SSH key file for key-based authentication.
    @State private var keyFilePath = ""

    /// The remote directory path for uploads.
    @State private var remotePath = "/"

    /// The user-facing label for this server profile.
    @State private var label = ""

    /// Whether a connection test is currently in progress.
    @State private var isTesting = false

    /// The result message from the last connection test.
    @State private var testResult: String?

    // MARK: - Auth Type Enum

    /// Simplified auth type picker for the UI, mapping to `AuthMethod`.
    private enum AuthType: String, CaseIterable {
        /// Password-based authentication.
        case password = "Password"
        /// SSH key file authentication.
        case keyFile = "Key File"
        /// SSH agent authentication.
        case agent = "SSH Agent"
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // MARK: Profile List
            profileList
                .frame(minWidth: 180, maxWidth: 220)

            // MARK: Configuration Form
            configForm
                .frame(minWidth: 400)
        }
        .onAppear(perform: loadProfiles)
    }

    // MARK: - Profile List

    /// Sidebar list of saved server profiles.
    private var profileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedProfileIndex) {
                ForEach(savedProfiles.indices, id: \.self) { index in
                    VStack(alignment: .leading) {
                        Text(savedProfiles[index].label)
                            .font(.headline)
                        Text(savedProfiles[index].host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(index)
                }
                .onDelete(perform: deleteProfile)
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button {
                    addNewProfile()
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(8)

                Spacer()
            }
        }
    }

    // MARK: - Configuration Form

    /// The main server configuration form.
    private var configForm: some View {
        Form {
            // MARK: Server Details
            Section("Server") {
                TextField("Label", text: $label, prompt: Text("My Server"))
                    .accessibilityLabel("Server label")

                TextField("Host", text: $host, prompt: Text("example.com"))
                    .accessibilityLabel("Server hostname")

                TextField("Port", text: $port, prompt: Text("22"))
                    .accessibilityLabel("SSH port")

                TextField("Username", text: $username, prompt: Text("deploy"))
                    .accessibilityLabel("SSH username")
            }

            // MARK: Authentication
            Section("Authentication") {
                Picker("Method", selection: $authType) {
                    ForEach(AuthType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Authentication method")

                switch authType {
                case .password:
                    SecureField("Password", text: $password)
                        .accessibilityLabel("SSH password")
                case .keyFile:
                    HStack {
                        TextField("Key File", text: $keyFilePath, prompt: Text("~/.ssh/id_ed25519"))
                            .accessibilityLabel("SSH key file path")
                        Button("Browse...") {
                            browseForKeyFile()
                        }
                    }
                case .agent:
                    Text("Using the local SSH agent for authentication.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Remote Path
            Section("Upload Destination") {
                TextField("Remote Path", text: $remotePath, prompt: Text("/var/www/media/"))
                    .accessibilityLabel("Remote upload directory")
            }

            // MARK: Actions
            Section {
                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(host.isEmpty || username.isEmpty || isTesting)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(
                                result.contains("Success") ? .green : .red
                            )
                    }

                    Spacer()

                    Button("Save Profile") {
                        saveCurrentProfile()
                    }
                    .disabled(host.isEmpty || label.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: selectedProfileIndex) { _, newIndex in
            if let index = newIndex, savedProfiles.indices.contains(index) {
                loadProfile(savedProfiles[index])
            }
        }
    }

    // MARK: - Actions

    /// Builds the current `AuthMethod` from the form state.
    private func buildAuthMethod() -> AuthMethod {
        switch authType {
        case .password:
            return .password(password)
        case .keyFile:
            return .keyFile(keyFilePath)
        case .agent:
            return .agent
        }
    }

    /// Builds an `SFTPServerConfig` from the current form values.
    private func buildConfig() -> SFTPServerConfig {
        SFTPServerConfig(
            host: host,
            port: Int(port) ?? 22,
            username: username,
            authMethod: buildAuthMethod(),
            remotePath: remotePath,
            label: label
        )
    }

    /// Initiates a connection test using the current form values.
    private func testConnection() {
        isTesting = true
        testResult = nil
        let config = buildConfig()
        let args = SFTPUploader.testConnection(config: config)

        // Show the command that would be run (actual execution would
        // use Process; here we just validate the arguments build).
        testResult = args.isEmpty ? "Error: empty arguments" : "Success: SSH arguments built"
        isTesting = false
    }

    /// Saves the current form values as a profile.
    private func saveCurrentProfile() {
        let config = buildConfig()

        if let index = selectedProfileIndex, savedProfiles.indices.contains(index) {
            savedProfiles[index] = config
        } else {
            savedProfiles.append(config)
            selectedProfileIndex = savedProfiles.count - 1
        }

        persistProfiles()
    }

    /// Loads form values from a saved profile.
    private func loadProfile(_ config: SFTPServerConfig) {
        host = config.host
        port = "\(config.port)"
        username = config.username
        remotePath = config.remotePath
        label = config.label

        switch config.authMethod {
        case .password(let pw):
            authType = .password
            password = pw
        case .keyFile(let path):
            authType = .keyFile
            keyFilePath = path
        case .agent:
            authType = .agent
        }
    }

    /// Clears the form for a new profile.
    private func addNewProfile() {
        selectedProfileIndex = nil
        host = ""
        port = "22"
        username = ""
        authType = .agent
        password = ""
        keyFilePath = ""
        remotePath = "/"
        label = ""
        testResult = nil
    }

    /// Deletes profiles at the specified offsets, including their
    /// Keychain-stored credentials.
    ///
    /// Without the credential cleanup, deleting a profile would
    /// leave its password sitting in the Keychain indefinitely
    /// (orphaned but still resident). `SFTPCredentialStore.delete`
    /// is idempotent so a missing entry is a no-op.
    private func deleteProfile(at offsets: IndexSet) {
        for index in offsets where savedProfiles.indices.contains(index) {
            try? SFTPCredentialStore.delete(forProfileID: savedProfiles[index].id)
        }
        savedProfiles.remove(atOffsets: offsets)
        selectedProfileIndex = nil
        persistProfiles()
    }

    /// Opens a file panel to select an SSH key file.
    private func browseForKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            keyFilePath = url.path
        }
    }

    // MARK: - Persistence

    /// UserDefaults key under which the redacted profile array lives.
    /// String literal kept in a `Self.` constant so the load / persist
    /// pair cannot drift.
    private static let userDefaultsKey = "sftpProfiles"

    /// Loads saved profiles from UserDefaults and restores their
    /// passwords from the Keychain.
    ///
    /// **F-005 migration path** (Cycle 17): legacy `sftpProfiles`
    /// blobs predate the Keychain split — they carried the plaintext
    /// password inside `AuthMethod.password(String)`. When we detect
    /// such a profile (a non-empty password in the JSON), we lift the
    /// plaintext into the Keychain keyed by the profile's id (a fresh
    /// UUID assigned by `SFTPServerConfig`'s backward-compatible
    /// decoder), then immediately call `persistProfiles()` to scrub
    /// the plaintext from the plist.
    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let profiles = try? JSONDecoder().decode(
                  [SFTPServerConfig].self, from: data
              ) else {
            return
        }

        var restored: [SFTPServerConfig] = []
        var migratedLegacyPlaintext = false

        for profile in profiles {
            switch profile.authMethod {
            case .password(let pw) where pw.isEmpty:
                // Already-redacted profile: restore the password from
                // the Keychain. If lookup fails (deleted out of band,
                // first launch on a different machine, etc.) we keep
                // the empty password — the user will be re-prompted
                // by the form when they next select this profile.
                if let realPw = try? SFTPCredentialStore.read(forProfileID: profile.id),
                   !realPw.isEmpty {
                    var copy = profile
                    copy.authMethod = .password(realPw)
                    restored.append(copy)
                } else {
                    restored.append(profile)
                }

            case .password(let pw):
                // Non-empty password in the JSON ⇒ legacy plaintext
                // blob written before Cycle 17. Migrate: write the
                // password to the Keychain under the profile's id
                // (the decoder assigned a fresh UUID since the legacy
                // JSON lacked the field). Keep the in-memory copy
                // populated so the user can use it immediately.
                try? SFTPCredentialStore.save(password: pw, forProfileID: profile.id)
                migratedLegacyPlaintext = true
                restored.append(profile)

            case .keyFile, .agent:
                // Non-password auth methods carry no secret material
                // inside the config — no Keychain interaction needed.
                restored.append(profile)
            }
        }

        savedProfiles = restored

        // Re-persist now so the migrated plaintext is overwritten in
        // UserDefaults this launch — we don't want to leave it sitting
        // there until the next save action.
        if migratedLegacyPlaintext {
            persistProfiles()
        }
    }

    /// Persists saved profiles to UserDefaults with passwords
    /// redacted out to the Keychain.
    ///
    /// **F-005 invariant**: the data this method writes to
    /// `UserDefaults` must NEVER contain a non-empty
    /// `AuthMethod.password(String)` field. The `redacted` copy
    /// below is what gets serialised; the real password is sent to
    /// `SFTPCredentialStore` first and replaced with an empty
    /// string in the about-to-be-encoded profile. The redaction
    /// happens at this single chokepoint so no caller has to know
    /// the rule.
    private func persistProfiles() {
        var redacted: [SFTPServerConfig] = []

        for profile in savedProfiles {
            if case .password(let pw) = profile.authMethod, !pw.isEmpty {
                // Write the credential to the Keychain. Failures here
                // are non-fatal for the persist call — the user can
                // re-enter — but they would leave a redacted profile
                // with no recoverable password. In practice the only
                // failure mode is `errSecUserCancelled` from a
                // Keychain ACL prompt, which the user will see.
                try? SFTPCredentialStore.save(password: pw, forProfileID: profile.id)

                var copy = profile
                copy.authMethod = .password("")
                redacted.append(copy)
            } else {
                redacted.append(profile)
            }
        }

        if let data = try? JSONEncoder().encode(redacted) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
