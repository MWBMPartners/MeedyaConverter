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
    ///   - host: Remote hostname or IP.
    ///   - port: SSH port (default 22).
    ///   - username: SSH username.
    ///   - authMethod: How to authenticate.
    ///   - remotePath: Remote directory for uploads.
    ///   - label: Display label for this profile.
    public init(
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod,
        remotePath: String,
        label: String
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.remotePath = remotePath
        self.label = label
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

    /// Builds `curl` command-line arguments for uploading a file via FTP.
    ///
    /// Uses curl's `ftp://` or `ftps://` scheme depending on the
    /// TLS setting in the configuration.
    ///
    /// - Parameters:
    ///   - localPath: Absolute path to the local file to upload.
    ///   - config: The FTP server configuration.
    /// - Returns: An array of command-line arguments for `curl`.
    public static func buildFTPUploadArguments(
        localPath: String,
        config: FTPServerConfig
    ) -> [String] {
        var args: [String] = []

        // Upload flag
        args.append(contentsOf: ["-T", localPath])

        // Credentials
        args.append(contentsOf: ["-u", "\(config.username):\(config.password)"])

        // Build the target URL
        let scheme = config.useTLS ? "ftps" : "ftp"
        let remotePath = config.remotePath.hasSuffix("/")
            ? config.remotePath
            : config.remotePath + "/"
        let filename = URL(fileURLWithPath: localPath).lastPathComponent
        let url = "\(scheme)://\(config.host):\(config.port)\(remotePath)\(filename)"
        args.append(url)

        // Create intermediate directories if needed
        args.append("--ftp-create-dirs")

        // TLS-specific options
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

        // Build the SSH command with port and auth options
        var sshCmd = "ssh -p \(config.port)"
        switch config.authMethod {
        case .password:
            sshCmd += " -o BatchMode=no"
        case .keyFile(let path):
            sshCmd += " -i \(path)"
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
