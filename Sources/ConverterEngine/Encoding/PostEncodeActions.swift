// ============================================================================
// MeedyaConverter — PostEncodeActions (Issue #277)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - PostEncodeActionType

/// The type of action to execute after an encoding job completes.
///
/// Actions run in the order they appear in a `PostEncodeActionChain`.
/// All cases execute for real — `.uploadSFTP` (Issue #450) and
/// `.uploadCloud` (Issue #459) both perform a genuine, authenticated
/// transfer and only report success when the destination actually
/// accepted the bytes; see their doc comments for the execution path
/// each one uses.
public enum PostEncodeActionType: String, Codable, Sendable, CaseIterable {
    /// Move the source file to the macOS Trash.
    case moveSourceToTrash

    /// Reveal the output file in Finder.
    case openInFinder

    /// Execute a shell command with variable substitution.
    ///
    /// Supported variables: `{input}`, `{output}`, `{profile}`, `{status}`.
    case runShellScript

    /// Send a webhook POST request (delegates to `WebhookSender`).
    case webhook

    /// Upload the output file via SFTP/`scp`, using a server profile saved
    /// in `SFTPSettingsView` and looked up through `SFTPProfileStore`
    /// (Issue #450). See `PostEncodeAction.config` for the expected key.
    case uploadSFTP

    /// Upload the output file to a saved cloud storage configuration
    /// (Dropbox / Google Drive / OneDrive), using a profile saved in
    /// `CloudStorageView` and looked up through
    /// `CloudStorageProfileStore` (Issue #459 — mirrors the
    /// `.uploadSFTP` wiring shipped for Issue #450). See
    /// `PostEncodeAction.config` for the expected key. S3/YouTube/Vimeo
    /// and full OAuth PKCE remain out of scope for this action; see
    /// `CloudUploadExecutor`'s doc comment for what token-based
    /// providers it actually executes.
    case uploadCloud

    /// Send a macOS notification with a custom message.
    case sendNotification
}

// MARK: - PostEncodeAction

/// A single post-encode action with its configuration and enable state.
///
/// Each action has a `type`, a human-readable `name`, and a `config`
/// dictionary that holds type-specific settings (e.g. shell script path,
/// webhook URL, notification message).
///
/// The `runOnFailure` flag determines whether this action should still
/// execute when the encoding job has failed.
public struct PostEncodeAction: Identifiable, Codable, Sendable {

    // MARK: - Properties

    /// Unique identifier for this action.
    public let id: UUID

    /// The type of post-encode action.
    public var type: PostEncodeActionType

    /// A human-readable name for this action (editable by the user).
    public var name: String

    /// Type-specific configuration key-value pairs.
    ///
    /// Expected keys by type:
    /// - `.runShellScript`: `"script"` — the shell command to execute.
    /// - `.webhook`: `"url"` — the webhook endpoint URL.
    /// - `.sendNotification`: `"message"` — the notification body text.
    /// - `.sendNotification`: `"title"` — optional notification title.
    /// - `.uploadSFTP`: `"sftpProfileID"` — the `UUID` string of a saved
    ///   `SFTPServerConfig` profile (see `SFTPSettingsView` /
    ///   `SFTPProfileStore`). No credentials are ever stored here —
    ///   only a reference to a profile whose secret lives in the
    ///   Keychain via `SFTPCredentialStore`.
    /// - `.uploadCloud`: `"cloudProfileID"` — the `UUID` string of a
    ///   saved `CloudStorageConfig` (see `CloudStorageView` /
    ///   `CloudStorageProfileStore`). As with `.uploadSFTP`, no
    ///   credential is ever stored here — only a reference to a
    ///   configuration whose OAuth token lives in the Keychain via
    ///   `APIKeyManager`.
    public var config: [String: String]

    /// Whether this action is enabled. Disabled actions are skipped.
    public var isEnabled: Bool

    /// Whether this action should also run when the encoding job fails.
    ///
    /// Useful for failure notifications or cleanup tasks.
    public var runOnFailure: Bool

    // MARK: - Initialiser

    /// Create a new post-encode action.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - type: The action type.
    ///   - name: A human-readable name.
    ///   - config: Type-specific configuration dictionary.
    ///   - isEnabled: Whether the action is active (defaults to `true`).
    ///   - runOnFailure: Whether to run on job failure (defaults to `false`).
    public init(
        id: UUID = UUID(),
        type: PostEncodeActionType,
        name: String,
        config: [String: String] = [:],
        isEnabled: Bool = true,
        runOnFailure: Bool = false
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.config = config
        self.isEnabled = isEnabled
        self.runOnFailure = runOnFailure
    }
}

// MARK: - PostEncodeActionChain

/// An ordered chain of post-encode actions to execute sequentially.
///
/// Actions run in array order. Each action's `isEnabled` and `runOnFailure`
/// flags are respected: disabled actions are skipped, and actions without
/// `runOnFailure` are skipped when the encoding job failed.
///
/// Variable substitution is applied to shell commands and notification
/// messages before execution. Supported variables:
/// - `{input}` — the source file path.
/// - `{output}` — the output file path.
/// - `{profile}` — the encoding profile name.
/// - `{status}` — the job outcome (`success` or `failure`).
///
/// Phase 17 — Post-Encode Hooks (Issue #277)
public struct PostEncodeActionChain: Codable, Sendable {

    // MARK: - Properties

    /// The ordered list of actions to execute.
    public var actions: [PostEncodeAction]

    // MARK: - Initialiser

    /// Create a new action chain.
    ///
    /// - Parameter actions: The ordered list of post-encode actions.
    public init(actions: [PostEncodeAction] = []) {
        self.actions = actions
    }

    // MARK: - Errors

    /// Errors that can occur during action chain execution.
    public enum ActionError: LocalizedError, Sendable {
        /// A shell script exited with a non-zero status code.
        case shellScriptFailed(exitCode: Int32, output: String)
        /// The action type is not yet implemented.
        case unsupportedAction(PostEncodeActionType)
        /// A required configuration key is missing.
        case missingConfig(key: String, actionName: String)
        /// A configured upload (SFTP/cloud) genuinely failed. Carries the
        /// real error the uploader reported — never a fabricated one.
        case uploadFailed(actionName: String, message: String)

        public var errorDescription: String? {
            switch self {
            case .shellScriptFailed(let code, let output):
                return "Shell script exited with code \(code): \(output)"
            case .unsupportedAction(let type):
                return "Action type '\(type.rawValue)' is not yet supported."
            case .missingConfig(let key, let name):
                return "Action '\(name)' is missing required config key '\(key)'."
            case .uploadFailed(let name, let message):
                return "Action '\(name)' upload failed: \(message)"
            }
        }
    }

    // MARK: - Execution

    /// Execute all enabled actions in the chain sequentially.
    ///
    /// Each action's `isEnabled` flag is checked first. Actions without
    /// `runOnFailure` are skipped when `success` is `false`.
    ///
    /// - Parameters:
    ///   - inputURL: The source file URL.
    ///   - outputURL: The output file URL.
    ///   - success: Whether the encoding job completed successfully.
    /// - Throws: The first error encountered during execution. Subsequent
    ///   actions are still attempted even if an earlier action fails.
    public func execute(inputURL: URL, outputURL: URL, success: Bool) async throws {
        var firstError: (any Error)?

        for action in actions {
            // Skip disabled actions.
            guard action.isEnabled else { continue }

            // Skip actions that should not run on failure.
            if !success && !action.runOnFailure { continue }

            do {
                try await executeAction(
                    action,
                    inputURL: inputURL,
                    outputURL: outputURL,
                    success: success
                )
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if let firstError { throw firstError }
    }

    // MARK: - Private Execution

    /// Execute a single post-encode action.
    ///
    /// - Parameters:
    ///   - action: The action to execute.
    ///   - inputURL: The source file URL.
    ///   - outputURL: The output file URL.
    ///   - success: Whether the encoding job succeeded.
    private func executeAction(
        _ action: PostEncodeAction,
        inputURL: URL,
        outputURL: URL,
        success: Bool
    ) async throws {
        let statusString = success ? "success" : "failure"

        switch action.type {
        case .moveSourceToTrash:
            try await moveToTrash(inputURL: inputURL)

        case .openInFinder:
            await revealInFinder(outputURL: outputURL)

        case .runShellScript:
            guard let script = action.config["script"], !script.isEmpty else {
                throw ActionError.missingConfig(key: "script", actionName: action.name)
            }
            let substituted = substituteVariables(
                in: script,
                inputURL: inputURL,
                outputURL: outputURL,
                profile: action.config["profile"] ?? "",
                status: statusString
            )
            try await runShellScript(substituted)

        case .webhook:
            guard let urlString = action.config["url"],
                  let url = URL(string: urlString) else {
                throw ActionError.missingConfig(key: "url", actionName: action.name)
            }
            let config = WebhookConfig.generic(url: url)
            let payload = WebhookPayload.now(
                event: success ? "encode_complete" : "encode_failed",
                job: WebhookJobInfo(
                    fileName: inputURL.lastPathComponent,
                    profile: action.config["profile"] ?? "Unknown",
                    durationSeconds: 0,
                    outputSizeBytes: 0
                ),
                status: statusString
            )
            try await WebhookSender.send(payload: payload, config: config)

        case .sendNotification:
            let message = action.config["message"] ?? "Encoding complete"
            let title = action.config["title"] ?? "MeedyaConverter"
            let substituted = substituteVariables(
                in: message,
                inputURL: inputURL,
                outputURL: outputURL,
                profile: action.config["profile"] ?? "",
                status: statusString
            )
            await sendMacOSNotification(title: title, body: substituted)

        case .uploadSFTP:
            try await uploadViaSFTP(action: action, outputURL: outputURL)

        case .uploadCloud:
            try await uploadViaCloud(action: action, outputURL: outputURL)
        }
    }

    // MARK: - Variable Substitution

    /// Replace placeholder variables in a string with actual values.
    ///
    /// Supported placeholders:
    /// - `{input}` — the source file path.
    /// - `{output}` — the output file path.
    /// - `{profile}` — the encoding profile name.
    /// - `{status}` — `success` or `failure`.
    ///
    /// - Parameters:
    ///   - string: The string containing placeholders.
    ///   - inputURL: The source file URL.
    ///   - outputURL: The output file URL.
    ///   - profile: The encoding profile name.
    ///   - status: The job outcome string.
    /// - Returns: The string with all placeholders replaced.
    private func substituteVariables(
        in string: String,
        inputURL: URL,
        outputURL: URL,
        profile: String,
        status: String
    ) -> String {
        string
            .replacingOccurrences(of: "{input}", with: inputURL.path)
            .replacingOccurrences(of: "{output}", with: outputURL.path)
            .replacingOccurrences(of: "{profile}", with: profile)
            .replacingOccurrences(of: "{status}", with: status)
    }

    // MARK: - Action Implementations

    /// Move the source file to the macOS Trash.
    ///
    /// Uses `FileManager.trashItem(at:resultingItemURL:)` which moves the
    /// file to the user's Trash folder rather than permanently deleting it.
    ///
    /// - Parameter inputURL: The source file URL.
    private func moveToTrash(inputURL: URL) async throws {
        try FileManager.default.trashItem(at: inputURL, resultingItemURL: nil)
    }

    /// Upload the encoded output file to a saved SFTP server profile via
    /// `scp`.
    ///
    /// Reuses the existing uploader plumbing end to end rather than
    /// inventing a parallel path:
    /// - `action.config["sftpProfileID"]` resolves to a profile through
    ///   `SFTPProfileStore.profile(withID:)`, which reads the exact same
    ///   `UserDefaults` blob `SFTPSettingsView` writes and restores the
    ///   password (if any) from the Keychain via `SFTPCredentialStore` —
    ///   no credential is ever stored inside `PostEncodeAction.config`.
    /// - `SFTPUploader.upload(localPath:config:)` builds argv with
    ///   `SFTPUploader.buildSCPArguments(localPath:config:)` (unchanged —
    ///   credentials never touch argv) and runs `scp`.
    ///
    /// Concurrency mirrors `SFTPSettingsView.probeConnection` (Issue
    /// #447): the blocking `scp`/`waitUntilExit()` work happens inside
    /// `Task.detached`, capturing and returning only `Sendable` values
    /// (`SFTPServerConfig` in, `SFTPUploadOutcome` out) — never `self`.
    ///
    /// - Parameters:
    ///   - action: The configured `.uploadSFTP` action.
    ///   - outputURL: The encoded output file to upload.
    /// - Throws: `ActionError.missingConfig` if no valid profile
    ///   reference is configured, or `ActionError.uploadFailed` with the
    ///   real `scp` error if the transfer fails.
    private func uploadViaSFTP(action: PostEncodeAction, outputURL: URL) async throws {
        guard let profileIDString = action.config["sftpProfileID"],
              let profileID = UUID(uuidString: profileIDString),
              let profile = SFTPProfileStore.profile(withID: profileID) else {
            throw ActionError.missingConfig(key: "sftpProfileID", actionName: action.name)
        }

        let localPath = outputURL.path
        let outcome = await Task.detached {
            SFTPUploader.upload(localPath: localPath, config: profile)
        }.value

        guard outcome.succeeded else {
            throw ActionError.uploadFailed(actionName: action.name, message: outcome.message)
        }
    }

    /// Upload the encoded output file to a saved cloud storage
    /// configuration (Dropbox / Google Drive / OneDrive), executing the
    /// transfer for real via `CloudUploadExecutor` (Issue #459).
    ///
    /// Reuses the same plumbing end to end that `CloudStorageView`
    /// uses, mirroring `uploadViaSFTP` above (Issue #450):
    /// - `action.config["cloudProfileID"]` resolves to a configuration
    ///   through `CloudStorageProfileStore.profile(withID:)`, which
    ///   reads the same `UserDefaults` blob `CloudStorageView` writes
    ///   and restores the access/refresh token from the Keychain via
    ///   `APIKeyManager` — no credential is ever stored inside
    ///   `PostEncodeAction.config`.
    /// - `CloudUploadExecutor.uploadToCloudStorage(fileURL:config:)`
    ///   picks the matching `CloudStorageUploader` request builder
    ///   (Dropbox / Google Drive / OneDrive, including OneDrive's
    ///   chunked upload-session path for files over 4 MB) and performs
    ///   the real, authenticated transfer.
    ///
    /// Unlike `uploadViaSFTP`'s `scp` invocation, the executor's work is
    /// genuinely `async` (no blocking `Process.waitUntilExit()`), so no
    /// `Task.detached` hop is needed here — `await`ing it directly
    /// never blocks a thread.
    ///
    /// - Parameters:
    ///   - action: The configured `.uploadCloud` action.
    ///   - outputURL: The encoded output file to upload.
    /// - Throws: `ActionError.missingConfig` if no valid profile
    ///   reference is configured, or `ActionError.uploadFailed` with
    ///   the real executor error (`CloudUploadExecutor.UploadError`'s
    ///   description — real HTTP status + body, or a real transport
    ///   failure) if the transfer fails.
    private func uploadViaCloud(action: PostEncodeAction, outputURL: URL) async throws {
        guard let profileIDString = action.config["cloudProfileID"],
              let profileID = UUID(uuidString: profileIDString),
              let profile = CloudStorageProfileStore.profile(withID: profileID) else {
            throw ActionError.missingConfig(key: "cloudProfileID", actionName: action.name)
        }

        guard !profile.accessToken.isEmpty else {
            throw ActionError.uploadFailed(
                actionName: action.name,
                message: "No access token is saved for \(profile.provider.rawValue). "
                    + "Paste an OAuth token in Cloud Storage settings and save the "
                    + "configuration first."
            )
        }

        let executor = CloudUploadExecutor()
        do {
            _ = try await executor.uploadToCloudStorage(fileURL: outputURL, config: profile)
        } catch {
            throw ActionError.uploadFailed(actionName: action.name, message: error.localizedDescription)
        }
    }

    /// Reveal the output file in Finder.
    ///
    /// - Parameter outputURL: The output file URL.
    @MainActor
    private func revealInFinder(outputURL: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        #endif
    }

    /// Execute a shell command via `/bin/zsh`.
    ///
    /// - Parameter command: The shell command to execute (variables already substituted).
    /// - Throws: `ActionError.shellScriptFailed` if the process exits with a non-zero code.
    private func runShellScript(_ command: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw ActionError.shellScriptFailed(
                exitCode: process.terminationStatus,
                output: output
            )
        }
    }

    /// Send a macOS user notification.
    ///
    /// Uses `NSUserNotificationCenter` for local delivery. The notification
    /// appears in the macOS Notification Centre.
    ///
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body text.
    /// Send a macOS user notification without blocking the main thread.
    ///
    /// The `osascript` process runs on a detached task so that `waitUntilExit()`
    /// does not stall the main actor's run-loop.
    @MainActor
    private func sendMacOSNotification(title: String, body: String) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e",
                "display notification \"\(body)\" with title \"\(title)\""
            ]
            try? process.run()
            process.waitUntilExit()
        }
    }
}
