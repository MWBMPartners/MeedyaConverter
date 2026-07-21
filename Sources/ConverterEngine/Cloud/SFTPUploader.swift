// ============================================================================
// MeedyaConverter — SFTPUploader (Issue #312)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - AuthMethod

/// Authentication method for SFTP/SSH connections.
///
/// Supports password-based auth, SSH key file, or the local SSH agent.
///
/// Phase 12.3 — Direct Upload via SFTP/FTP (Issue #312)
public enum AuthMethod: Codable, Sendable, Hashable {

    /// Password-based authentication.
    ///
    /// - Parameter password: The plaintext password. In production this
    ///   should be retrieved from the Keychain rather than stored directly.
    case password(String)

    /// Public-key authentication using a key file on disk.
    ///
    /// - Parameter path: Absolute path to the private key file
    ///   (e.g. `~/.ssh/id_ed25519`).
    case keyFile(String)

    /// Delegate authentication to the running SSH agent (`ssh-agent`).
    case agent
}

// MARK: - SFTPServerConfig

/// Configuration for an SFTP (SSH-based) server connection.
///
/// Stores all parameters needed to build `scp`, `sftp`, or `rsync`
/// command-line invocations for uploading encoded output files to a
/// remote server.
///
/// Phase 12.3 — Direct Upload via SFTP/FTP (Issue #312)
public struct SFTPServerConfig: Codable, Sendable, Hashable {

    /// Stable identifier for this profile. Generated fresh by the
    /// default init and preserved across load/save cycles so the
    /// `SFTPCredentialStore` Keychain entry stays addressable.
    ///
    /// Added in Cycle 17 alongside the F-005 fix that lifts the
    /// `AuthMethod.password(String)` plaintext out of UserDefaults
    /// and into the Keychain. The Codable decoder generates a fresh
    /// UUID when this field is absent from JSON (legacy
    /// `sftpProfiles` blobs predate the field) so the migration
    /// path can succeed without manual intervention.
    public var id: UUID

    /// The remote hostname or IP address.
    public var host: String

    /// The SSH port number (default 22).
    public var port: Int

    /// The SSH username for authentication.
    public var username: String

    /// The authentication method (password, key file, or SSH agent).
    public var authMethod: AuthMethod

    /// The remote directory path where files will be uploaded.
    public var remotePath: String

    /// A user-facing label for this saved server profile.
    public var label: String

    /// Creates a new SFTP server configuration.
    ///
    /// - Parameters:
    ///   - id: Profile UUID (defaults to a fresh `UUID()`).
    ///   - host: Remote hostname or IP.
    ///   - port: SSH port (default 22).
    ///   - username: SSH username.
    ///   - authMethod: How to authenticate.
    ///   - remotePath: Remote directory for uploads.
    ///   - label: Display label for this profile.
    public init(
        id: UUID = UUID(),
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod,
        remotePath: String,
        label: String
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.remotePath = remotePath
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case id, host, port, username, authMethod, remotePath, label
    }

    /// Backward-compatible decoder: legacy `sftpProfiles` blobs
    /// written before Cycle 17 lack the `id` field. We assign a
    /// fresh UUID in that case so the migration path in
    /// `SFTPSettingsView.loadProfiles` can deposit the plaintext
    /// password to the Keychain keyed by the newly-minted id and
    /// then rewrite the plist without it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decode(Int.self, forKey: .port)
        self.username = try container.decode(String.self, forKey: .username)
        self.authMethod = try container.decode(AuthMethod.self, forKey: .authMethod)
        self.remotePath = try container.decode(String.self, forKey: .remotePath)
        self.label = try container.decode(String.self, forKey: .label)
    }
}

// MARK: - FTPServerConfig

/// Configuration for an FTP/FTPS server connection.
///
/// Uses `curl` under the hood with `ftp://` or `ftps://` scheme
/// to upload files to a traditional FTP server.
///
/// Phase 12.3 — Direct Upload via SFTP/FTP (Issue #312)
public struct FTPServerConfig: Codable, Sendable, Hashable {

    /// The remote hostname or IP address.
    public var host: String

    /// The FTP port number (default 21).
    public var port: Int

    /// The FTP username.
    public var username: String

    /// The FTP password.
    public var password: String

    /// Whether to use TLS (FTPS) for the connection.
    public var useTLS: Bool

    /// The remote directory path where files will be uploaded.
    public var remotePath: String

    /// A user-facing label for this saved server profile.
    public var label: String

    /// Creates a new FTP server configuration.
    ///
    /// - Parameters:
    ///   - host: Remote hostname or IP.
    ///   - port: FTP port (default 21).
    ///   - username: FTP username.
    ///   - password: FTP password.
    ///   - useTLS: Whether to use FTPS.
    ///   - remotePath: Remote directory for uploads.
    ///   - label: Display label for this profile.
    public init(
        host: String,
        port: Int = 21,
        username: String,
        password: String,
        useTLS: Bool = false,
        remotePath: String,
        label: String
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useTLS = useTLS
        self.remotePath = remotePath
        self.label = label
    }
}

// MARK: - SFTPUploader

/// Builds command-line arguments for SFTP, SCP, FTP, and rsync uploads.
///
/// This struct does not execute commands directly — it constructs argument
/// arrays that can be passed to `Process` or the shell execution layer.
/// This keeps the uploader testable and avoids side effects in the engine.
///
/// Phase 12.3 — Direct Upload via SFTP/FTP (Issue #312)
public struct SFTPUploader: Sendable {

    // MARK: - SCP Upload

    /// Builds `scp` command-line arguments for uploading a file via SSH.
    ///
    /// The resulting arguments can be passed to `/usr/bin/scp`.
    ///
    /// - Parameters:
    ///   - localPath: Absolute path to the local file to upload.
    ///   - config: The SFTP server configuration.
    /// - Returns: An array of command-line arguments for `scp`.
    public static func buildSCPArguments(
        localPath: String,
        config: SFTPServerConfig
    ) -> [String] {
        var args: [String] = []

        // Port specification
        args.append(contentsOf: ["-P", "\(config.port)"])

        // Authentication method
        switch config.authMethod {
        case .password:
            // scp does not support inline passwords; sshpass or expect
            // is required. We add -o BatchMode=no to allow password prompt.
            args.append(contentsOf: ["-o", "BatchMode=no"])
        case .keyFile(let path):
            args.append(contentsOf: ["-i", path])
        case .agent:
            // SSH agent is used by default; no extra flags needed.
            break
        }

        // Disable strict host key checking for automated uploads.
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=accept-new"])

        // Source file
        args.append(localPath)

        // Destination: user@host:remotePath
        let remoteDest = "\(config.username)@\(config.host):\(config.remotePath)"
        args.append(remoteDest)

        return args
    }

    // MARK: - FTP Upload

    // -------------------------------------------------------------------------
    // Why credentials live in a config file rather than `-u user:pass`
    // -------------------------------------------------------------------------
    //
    // Audit follow-up for issue #380 (security + memory audit).
    //
    // curl's `-u user:password` form places the credentials directly on the
    // command line. Any local user on the host can read process arguments via
    // `ps aux` (or /proc/<pid>/cmdline on Linux), so FTP credentials would be
    // visible for the lifetime of the upload — including in logs that capture
    // process listings. We therefore split credential handling into a separate
    // file step:
    //
    //   1. `writeFTPCredentialsConfig(config:)` writes a *short-lived* config
    //      file with mode `0600` containing a single `user = "..."` directive.
    //      The 0600 perms restrict reads to the file owner, and the file lives
    //      in `FileManager.default.temporaryDirectory` so it is process-scoped.
    //   2. `buildFTPUploadArguments(..., credentialsConfigPath:)` consumes that
    //      path via curl's `-K <path>`. curl reads the config in-process; the
    //      credentials never appear in argv.
    //
    // The caller is responsible for removing the config file once the upload
    // completes (or fails). A `defer { try? FileManager.default.removeItem(at:
    // configURL) }` immediately after the `writeFTPCredentialsConfig` call site
    // is the recommended pattern.

    /// Writes a temporary, owner-readable curl config file containing the
    /// FTP credentials for a single upload.
    ///
    /// The returned file:
    /// * lives in `FileManager.default.temporaryDirectory`
    /// * is created with POSIX mode `0600` (owner read/write only)
    /// * contains exactly one directive, `user = "<username>:<password>"`,
    ///   with embedded backslashes and double quotes escaped per curl's
    ///   config-file syntax (see `man curl`, “CONFIG FILE”)
    ///
    /// The caller MUST remove this file once the upload completes; the
    /// recommended pattern is a `defer` immediately after the call so that
    /// the credentials are wiped even if the upload throws.
    ///
    /// - Parameter config: The FTP server configuration whose username and
    ///   password should be written into the credentials file.
    /// - Returns: The absolute URL of the freshly-written credentials file.
    /// - Throws: Any filesystem error from creating the file, writing its
    ///   contents, or applying the `0600` permission mode.
    public static func writeFTPCredentialsConfig(
        config: FTPServerConfig
    ) throws -> URL {

        // ------------------------------------------------------------------
        // Choose a process-private path in the system temp directory.
        // A UUID-based filename avoids collisions across concurrent uploads
        // and ensures no information about the FTP host leaks into the
        // filename itself.
        // ------------------------------------------------------------------
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "ftp-credentials-\(UUID().uuidString).curlrc"
        let url = tempDir.appendingPathComponent(filename)

        // ------------------------------------------------------------------
        // Create the file with restrictive permissions BEFORE writing the
        // credentials. Doing it in this order guarantees the credentials
        // never exist on disk under world-readable perms — even briefly.
        // ------------------------------------------------------------------
        let created = FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw CocoaError(.fileWriteUnknown)
        }

        // ------------------------------------------------------------------
        // Escape the credential value for curl's config-file syntax.
        // Per `man curl`, a quoted value is parsed with `\\` → `\` and
        // `\"` → `"`. We therefore escape backslashes first (so we don't
        // double-escape the ones we are about to add) and then escape any
        // embedded double quotes.
        // ------------------------------------------------------------------
        let raw = "\(config.username):\(config.password)"
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let directive = "user = \"\(escaped)\"\n"

        // ------------------------------------------------------------------
        // Write the directive. We use `atomically: false` because the file
        // was just created with the correct permissions; an atomic write
        // would replace it via a rename and risk losing those perms on
        // platforms where the temp file inherits the umask instead.
        // ------------------------------------------------------------------
        guard let payload = directive.data(using: .utf8) else {
            // UTF-8 encoding of a String can only fail for invalid scalar
            // sequences, which `String` itself does not permit. The guard
            // exists to satisfy the compiler and document the invariant.
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try payload.write(to: url, options: [])

        // ------------------------------------------------------------------
        // Re-assert 0600 after writing. Some platforms (and some test
        // harnesses) reset permissions during `Data.write`; being explicit
        // here keeps the security guarantee uniform across environments.
        // ------------------------------------------------------------------
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )

        return url
    }

    /// Builds `curl` command-line arguments for uploading a file via FTP.
    ///
    /// Uses curl's `ftp://` or `ftps://` scheme depending on the
    /// TLS setting in the configuration.
    ///
    /// Credentials are NOT placed on the command line. The caller must
    /// first invoke `writeFTPCredentialsConfig(config:)` to obtain a
    /// short-lived `0600` config file, pass its path here, and remove the
    /// file once the upload finishes. See issue #380 for the audit
    /// rationale behind this two-step API.
    ///
    /// - Parameters:
    ///   - localPath: Absolute path to the local file to upload.
    ///   - config: The FTP server configuration (host, port, TLS, remote
    ///     path). The username and password fields of `config` are NOT
    ///     read by this method — they live in the credentials file.
    ///   - credentialsConfigPath: Absolute path to the curl config file
    ///     produced by `writeFTPCredentialsConfig(config:)`.
    /// - Returns: An array of command-line arguments for `curl`.
    public static func buildFTPUploadArguments(
        localPath: String,
        config: FTPServerConfig,
        credentialsConfigPath: String
    ) -> [String] {
        var args: [String] = []

        // ------------------------------------------------------------------
        // Read credentials from the config file via `-K`. This keeps the
        // username and password out of argv (and therefore out of `ps`,
        // /proc/<pid>/cmdline, and any process-listing log).
        // ------------------------------------------------------------------
        args.append(contentsOf: ["-K", credentialsConfigPath])

        // Upload flag — tells curl to PUT/STOR the named local file.
        args.append(contentsOf: ["-T", localPath])

        // ------------------------------------------------------------------
        // Build the target URL. We always include the explicit port so
        // that curl does not fall back to its default (21/990) when the
        // user has configured a non-standard listener.
        // ------------------------------------------------------------------
        let scheme = config.useTLS ? "ftps" : "ftp"
        let remotePath = config.remotePath.hasSuffix("/")
            ? config.remotePath
            : config.remotePath + "/"
        let filename = URL(fileURLWithPath: localPath).lastPathComponent
        let url = "\(scheme)://\(config.host):\(config.port)\(remotePath)\(filename)"
        args.append(url)

        // Create intermediate directories if needed.
        args.append("--ftp-create-dirs")

        // TLS-specific options: require TLS for the control connection
        // when the user has opted into FTPS.
        if config.useTLS {
            args.append("--ssl-reqd")
        }

        return args
    }

    // MARK: - Connection Test

    /// Builds SSH command-line arguments for testing an SFTP connection.
    ///
    /// Runs a lightweight `ssh` command that exits immediately,
    /// verifying that the host is reachable and credentials are valid.
    ///
    /// - Parameter config: The SFTP server configuration.
    /// - Returns: An array of command-line arguments for `ssh`.
    public static func testConnection(
        config: SFTPServerConfig
    ) -> [String] {
        var args: [String] = []

        // Port
        args.append(contentsOf: ["-p", "\(config.port)"])

        // Authentication method
        switch config.authMethod {
        case .password:
            args.append(contentsOf: ["-o", "BatchMode=no"])
        case .keyFile(let path):
            args.append(contentsOf: ["-i", path])
        case .agent:
            break
        }

        // Quick connection test options
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=accept-new"])
        args.append(contentsOf: ["-o", "ConnectTimeout=10"])

        // User@host
        args.append("\(config.username)@\(config.host)")

        // Run a harmless command and exit
        args.append("exit")

        return args
    }

    // MARK: - Rsync Upload

    /// Builds `rsync` command-line arguments for uploading via SSH.
    ///
    /// Rsync provides resume support, delta transfers, and progress
    /// reporting — ideal for large media files over unreliable connections.
    ///
    /// - Parameters:
    ///   - localPath: Absolute path to the local file or directory.
    ///   - config: The SFTP server configuration.
    /// - Returns: An array of command-line arguments for `rsync`.
    public static func buildRsyncArguments(
        localPath: String,
        config: SFTPServerConfig
    ) -> [String] {
        var args: [String] = []

        // Archive mode with progress and compression
        args.append(contentsOf: ["-avz", "--progress"])

        // Build the SSH command with port and auth options. Shell-escape
        // the key file path with single quotes so spaces/metacharacters
        // in the path cannot break the rsync -e arg or, worse, execute
        // arbitrary commands. The port is validated to be numeric by
        // SFTPServerConfig.init so direct interpolation is safe.
        var sshCmd = "ssh -p \(config.port)"
        switch config.authMethod {
        case .password:
            sshCmd += " -o BatchMode=no"
        case .keyFile(let path):
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            sshCmd += " -i '\(escaped)'"
        case .agent:
            break
        }
        sshCmd += " -o StrictHostKeyChecking=accept-new"
        args.append(contentsOf: ["-e", sshCmd])

        // Source
        args.append(localPath)

        // Destination
        let remoteDest = "\(config.username)@\(config.host):\(config.remotePath)"
        args.append(remoteDest)

        return args
    }
}

// MARK: - SFTPUploadOutcome

/// The real outcome of an `scp` upload attempt.
///
/// Mirrors `SFTPSettingsView.ConnectionProbeResult` (Issue #447) one
/// layer down, in `ConverterEngine`, so callers such as
/// `PostEncodeActionChain` (Issue #450) get the same honest-failure
/// guarantee — success/failure/message are always what `scp` actually
/// reported, never fabricated.
public struct SFTPUploadOutcome: Sendable {
    /// Whether `scp` exited with status 0.
    public let succeeded: Bool

    /// A human-readable success confirmation, or the real error `scp`
    /// reported (its stderr output, or a process-launch failure
    /// description).
    public let message: String

    public init(succeeded: Bool, message: String) {
        self.succeeded = succeeded
        self.message = message
    }
}

// MARK: - SFTPUploader Execution

extension SFTPUploader {

    /// Uploads `localPath` to the server described by `config` via `scp`,
    /// blocking the calling thread until the transfer finishes or fails.
    ///
    /// This is a **blocking** call — the caller MUST run it off the
    /// main/calling actor (e.g. via `Task.detached`), exactly as
    /// `SFTPSettingsView.probeConnection(config:)` does for connection
    /// tests (Issue #447). It is marked `nonisolated` to document that it
    /// touches no actor-isolated state; hopping off-actor before invoking
    /// it remains the caller's responsibility.
    ///
    /// Credential handling reuses `buildSCPArguments(localPath:config:)`
    /// as-is — nothing new is added to argv, so key-file paths and
    /// hostnames are the only configuration data that ever appears in
    /// process arguments. A password-based profile is a documented
    /// exception: `-o BatchMode=yes` is prepended ahead of the builder's
    /// own `-o BatchMode=no` for `.password` configs so `scp` can never
    /// block on a password prompt with no controlling terminal to read it
    /// from. Per `ssh_config(5)`, the first value supplied for a given
    /// `-o` key wins, so the prepended flag takes precedence — the same
    /// technique `SFTPSettingsView.probeConnection` already uses and
    /// documents. A password-only profile therefore fails fast with
    /// `scp`'s real "Permission denied" error rather than hanging; that
    /// is a genuine SSH-protocol limitation (no non-interactive way to
    /// submit a plaintext password), not a fabricated failure. Key-file
    /// and SSH-agent authentication are unaffected and upload normally.
    ///
    /// - Parameters:
    ///   - localPath: Absolute path to the file to upload.
    ///   - config: The destination SFTP server configuration.
    /// - Returns: The real `scp` outcome — never a fabricated success.
    public nonisolated static func upload(
        localPath: String,
        config: SFTPServerConfig
    ) -> SFTPUploadOutcome {
        var args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=15"]
        args.append(contentsOf: buildSCPArguments(localPath: localPath, config: config))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return SFTPUploadOutcome(
                succeeded: false,
                message: "Could not launch scp: \(error.localizedDescription)"
            )
        }

        // Drain both pipes concurrently so a chatty remote (e.g. a login
        // banner/MOTD written to stdout) can't fill the pipe buffer and
        // deadlock `waitUntilExit()` — the same pitfall documented at
        // `SFTPSettingsView.probeConnection` and `FFmpegProbe.runFFprobe`.
        let ioState = SFTPUploadIOState()
        let stdoutDone = DispatchSemaphore(value: 0)
        let stderrDone = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async {
            ioState.stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
            stdoutDone.signal()
        }
        DispatchQueue.global(qos: .utility).async {
            ioState.stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
            stderrDone.signal()
        }

        process.waitUntilExit()
        stdoutDone.wait()
        stderrDone.wait()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: ioState.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = stderrText.isEmpty
                ? "scp exited with status \(process.terminationStatus)."
                : stderrText
            return SFTPUploadOutcome(succeeded: false, message: detail)
        }

        return SFTPUploadOutcome(
            succeeded: true,
            message: "Uploaded to \(config.username)@\(config.host):\(config.remotePath)"
        )
    }
}

// MARK: - SFTPUploadIOState

/// Holds the drained stdout/stderr bytes from `SFTPUploader.upload`'s
/// `scp` invocation.
///
/// `@unchecked Sendable`: the two background readers each own a
/// disjoint property (`stdout`/`stderr`) and `upload` only reads them
/// after waiting on the `DispatchSemaphore` each reader signals on
/// completion, so the semaphore hand-off — not the compiler —
/// establishes the happens-before relationship. Mirrors
/// `SFTPSettingsView.ProbeIOState`, which does the equivalent job for
/// the connection-test probe.
private final class SFTPUploadIOState: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()
}

// MARK: - SFTPProfileStore

/// Read-only access to the SFTP server profiles saved by
/// `SFTPSettingsView` (Issue #312), for consumers outside the app's
/// SwiftUI layer — e.g. `PostEncodeActionChain` (Issue #450), which runs
/// inside `ConverterEngine` and has no view to bind form state to.
///
/// This intentionally does not duplicate storage: it reads the exact
/// same `UserDefaults` blob and the exact same `SFTPCredentialStore`
/// Keychain entries that `SFTPSettingsView.loadProfiles()` /
/// `persistProfiles()` already own. There is a single source of truth
/// for "what SFTP servers has the user configured" — this type just
/// gives non-UI code a way to read it.
public enum SFTPProfileStore {

    /// `UserDefaults` key under which the redacted profile array lives.
    /// Shared with `SFTPSettingsView` so the storage key cannot drift
    /// between the write side (settings UI) and this read side.
    public static let userDefaultsKey = "sftpProfiles"

    /// Loads every saved SFTP profile, restoring each profile's
    /// plaintext password (if any) from the Keychain via
    /// `SFTPCredentialStore`.
    ///
    /// Read-only: unlike `SFTPSettingsView.loadProfiles()`, this never
    /// rewrites `UserDefaults` — the legacy-plaintext-blob migration
    /// (SECURITY.md F-005) remains the settings view's responsibility.
    /// A profile whose Keychain lookup fails (deleted out of band, no
    /// entry yet, etc.) is returned with its password left as stored
    /// (typically empty); callers should treat that as "credential
    /// unavailable" rather than assume it will authenticate.
    ///
    /// - Returns: The saved profiles, or an empty array if none are
    ///   saved or the stored JSON cannot be decoded.
    public static func loadProfiles() -> [SFTPServerConfig] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let profiles = try? JSONDecoder().decode(
                  [SFTPServerConfig].self, from: data
              ) else {
            return []
        }

        return profiles.map { profile in
            guard case .password(let storedPassword) = profile.authMethod,
                  storedPassword.isEmpty else {
                return profile
            }
            guard let realPassword = try? SFTPCredentialStore.read(forProfileID: profile.id),
                  !realPassword.isEmpty else {
                return profile
            }
            var copy = profile
            copy.authMethod = .password(realPassword)
            return copy
        }
    }

    /// Looks up a single saved profile by its stable `id`.
    ///
    /// - Parameter id: The profile's `SFTPServerConfig.id`.
    /// - Returns: The matching profile (with its password restored from
    ///   the Keychain when applicable), or `nil` if no profile with that
    ///   id is currently saved.
    public static func profile(withID id: UUID) -> SFTPServerConfig? {
        loadProfiles().first { $0.id == id }
    }
}
