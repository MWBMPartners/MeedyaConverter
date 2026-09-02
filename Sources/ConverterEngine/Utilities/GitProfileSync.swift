// ============================================================================
// MeedyaConverter — GitProfileSync (Issue #345)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `TeamProfileManager`'s `.gitRepository` sync method (Issue #345) used to
// treat "Repository URL" as a plain folder path — `pushProfiles`/
// `pullProfiles` just read/wrote `team_profiles.json` at that path with no
// git involved at all. This file is the real git transport it was missing.
//
// `GitProfileSync` deals only in `Data`, not `EncodingProfile` — the manager
// keeps ownership of JSON encode/decode so the git path stays byte-identical
// to the iCloud-shared-folder path. It clones/fetches a disposable working
// copy under a per-remote cache directory, force-checks-out the tracked
// branch to the remote tip (so a stale local commit from a previously
// failed push is discarded on the next sync, not silently kept), writes
// `team_profiles.json`, and commits + pushes only when something actually
// changed.
//
// No authentication is invented: git inherits the calling user's own
// environment (`~/.gitconfig` credential helpers, SSH agent, keychain
// helper). The only environment changes made are `GIT_TERMINAL_PROMPT=0` +
// a closed stdin (so a credential-less remote fails fast instead of
// hanging on a prompt nothing can answer) and prepending the Homebrew/
// local git install directories to `PATH` (a GUI process's inherited PATH
// doesn't include them, and `/usr/bin/git` under that restricted PATH is
// the xcode-select shim, not a real git).
//
// `GitRunning` is the seam — mirroring `DualDynamicHDRStepRunning`'s
// injectable-protocol pattern over dovi_tool/hdr10plus_tool/ffmpeg — so
// `GitProfileSyncTests` can exercise the full clone/fetch/checkout/commit/
// push sequencing with a mock and no real git binary or network access.
// ---------------------------------------------------------------------------

import Foundation
import CryptoKit

// MARK: - GitCommandResult

/// The raw result of running one git subcommand.
///
/// `stdout`/`stderr` are UTF-8 decoded and trimmed of leading/trailing
/// whitespace; every command `GitProfileSync` issues passes `--quiet`, so
/// `stderr` in practice stays well under the 64 KB a pipe can buffer
/// without the reading side needing to drain it concurrently.
public struct GitCommandResult: Sendable, Equatable {

    /// The process's exit code (`Process.terminationStatus`).
    public let exitCode: Int32

    /// Captured, trimmed standard output.
    public let stdout: String

    /// Captured, trimmed standard error.
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

// MARK: - GitRunning

/// Abstraction over "run one git subcommand", so `GitProfileSync` can be
/// unit-tested with a mock — no real git binary, no network access —
/// mirroring `DualDynamicHDRStepRunning`'s seam over dovi_tool/
/// hdr10plus_tool/ffmpeg in `DualDynamicHDRPipelineExecutor`.
///
/// `ProcessGitRunner` (below) is the real, production conformer; tests
/// substitute their own.
public protocol GitRunning: Sendable {

    /// Runs `git <arguments>` with `workingDirectory` as the process's
    /// current directory.
    ///
    /// - Throws: Only if the process itself could not be launched (e.g. the
    ///   located binary vanished between resolution and launch). A
    ///   non-zero git exit code is **not** an error here — it comes back in
    ///   `GitCommandResult.exitCode`; `GitProfileSync.git(_:in:allowedExitCodes:)`
    ///   is what decides which exit codes a given command accepts.
    func run(_ arguments: [String], in workingDirectory: URL) async throws -> GitCommandResult
}

// MARK: - ProcessGitRunner

/// The real `GitRunning` implementation: spawns an actual `git` process.
public struct ProcessGitRunner: GitRunning {

    /// Candidate git binary locations, checked in this order.
    ///
    /// Deliberately excludes `/usr/bin/git`: a GUI-launched app inherits
    /// `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, and under that restricted PATH
    /// `/usr/bin/git` is the xcode-select shim — when the Command Line
    /// Tools aren't installed it exits 1 and pops an installer dialog
    /// instead of running git at all. Homebrew's git is checked first so
    /// the same `~/.gitconfig` a Terminal `git` would read (credential
    /// helpers, aliases) is honoured; ordering exists only to skip the
    /// shim, since every candidate here reads the same config file.
    public static let searchPaths: [String] = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
    ]

    /// The resolved git binary's absolute path.
    public let gitPath: String

    /// The environment `run` launches git with — see `gitEnvironment(base:)`.
    private let environment: [String: String]

    private init(gitPath: String, environment: [String: String]) {
        self.gitPath = gitPath
        self.environment = environment
    }

    /// Locates a real git binary from `searchPaths`, in order.
    ///
    /// - Parameters:
    ///   - isExecutable: Predicate used to test each candidate path;
    ///     defaults to a real filesystem check. Overridable so tests can
    ///     exercise preference ordering and the not-found path without
    ///     depending on what's actually installed on the test machine.
    ///   - environment: The base environment to derive `gitEnvironment(base:)`
    ///     from; defaults to the current process's environment.
    /// - Returns: A `ProcessGitRunner` bound to the first candidate for
    ///   which `isExecutable` returns `true`.
    /// - Throws: `TeamProfileError.gitNotFound` if none of `searchPaths`
    ///   is executable.
    public static func locate(
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ProcessGitRunner {
        guard let path = searchPaths.first(where: isExecutable) else {
            throw TeamProfileError.gitNotFound
        }
        return ProcessGitRunner(gitPath: path, environment: gitEnvironment(base: environment))
    }

    /// Computes the environment a git child process is launched with.
    ///
    /// Starts from `base` (so credential helpers, SSH agent, keychain
    /// integration — anything the user's own shell environment provides —
    /// still resolve), then:
    ///   - sets `GIT_TERMINAL_PROMPT=0`, so git never blocks waiting on a
    ///     password/passphrase prompt nothing can answer (paired with
    ///     `run`'s closed stdin, a credential-less remote fails fast
    ///     instead of hanging);
    ///   - prepends `/opt/homebrew/bin` and `/usr/local/bin` to `PATH`
    ///     without duplicating segments already present, so credential
    ///     helpers those git installs configure (e.g.
    ///     `git-credential-osxkeychain`) resolve even under a GUI
    ///     process's restricted inherited `PATH`.
    ///
    /// `GIT_SSH_COMMAND`/`core.sshCommand` are deliberately left untouched —
    /// no SSH transport is invented here.
    public static func gitEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env["GIT_TERMINAL_PROMPT"] = "0"

        let extraPathDirs = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existingComponents = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        let newDirs = extraPathDirs.filter { !existingComponents.contains($0) }
        if !newDirs.isEmpty {
            env["PATH"] = (newDirs + existingComponents).joined(separator: ":")
        }
        return env
    }

    public func run(_ arguments: [String], in workingDirectory: URL) async throws -> GitCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: gitPath)
                    process.arguments = arguments
                    process.currentDirectoryURL = workingDirectory
                    process.environment = environment
                    process.standardInput = FileHandle.nullDevice

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    try process.run()

                    // Drain stdout to EOF *before* waitUntilExit: every
                    // command below passes --quiet so stderr stays small,
                    // but stdout is read here as it's produced. Waiting
                    // first risks the classic pipe-buffer deadlock — the
                    // child blocks writing once a pipe's kernel buffer
                    // fills, and nothing is reading it yet.
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    process.waitUntilExit()

                    let result = GitCommandResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: stdoutData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - PushOutcome

/// The outcome of `GitProfileSync.push(_:message:)`.
public enum PushOutcome: Sendable, Equatable {

    /// A commit was created and `git push` completed.
    case pushed

    /// The working tree already matched the pushed `Data` exactly — nothing
    /// was staged, so no commit or push was attempted.
    case nothingToPush
}

// MARK: - GitProfileSync

/// Real git transport for Team Profile's `.gitRepository` sync method.
///
/// Holds all command sequencing for one remote/branch pair. Deals in `Data`,
/// not `EncodingProfile` — `TeamProfileManager` owns JSON encode/decode, so
/// the git path serialises byte-identically to the iCloud-shared-folder
/// path (`team_profiles.json`, `.prettyPrinted, .sortedKeys`, ISO-8601).
public struct GitProfileSync: Sendable {

    /// The remote to clone/fetch/push. Any form `git clone` accepts:
    /// `https://…`, `git@host:owner/repo.git` (scp-style has no URL scheme,
    /// hence `String` not `URL`), or a local path.
    public let remote: String

    /// The branch team profiles live on. Blank input normalises to `"main"`.
    public let branch: String

    private let runner: any GitRunning
    private let cacheRoot: URL

    /// Creates a sync for `remote`/`branch`.
    ///
    /// - Parameters:
    ///   - remote: The git remote (see `remote` above).
    ///   - branch: The tracked branch; blank/whitespace-only normalises to
    ///     `"main"`.
    ///   - runner: The `GitRunning` transport. Production callers pass
    ///     `ProcessGitRunner.locate()`; tests inject a mock.
    ///   - cacheRoot: Root directory for this sync's disposable working
    ///     copy. Defaults to `defaultCacheRoot()`.
    public init(
        remote: String,
        branch: String,
        runner: any GitRunning,
        cacheRoot: URL = GitProfileSync.defaultCacheRoot()
    ) {
        self.remote = remote
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        self.branch = trimmedBranch.isEmpty ? "main" : trimmedBranch
        self.runner = runner
        self.cacheRoot = cacheRoot
    }

    /// This sync's disposable working copy, under `cacheRoot`.
    public var workingDirectory: URL {
        Self.workingDirectory(forRemote: remote, cacheRoot: cacheRoot)
    }

    // MARK: - Pull

    /// Fetches `branch` from `remote` and returns the bytes of
    /// `team_profiles.json` at its tip.
    ///
    /// - Returns: `nil` if `branch` doesn't exist yet on `remote` (nobody
    ///   has pushed profiles there), or if the branch exists but the file
    ///   itself is absent from it. Neither case is an error — a brand-new
    ///   team repository with no profiles pushed yet is the expected
    ///   starting state.
    /// - Throws: `TeamProfileError.gitCommandFailed` if any git command
    ///   exits outside its allowed codes (e.g. the remote is unreachable,
    ///   or credentials are required and none are available).
    public func pull() async throws -> Data? {
        let wd = workingDirectory
        let didClone = try await ensureWorkingCopy(at: wd)

        if !didClone {
            _ = try await git(["fetch", "--quiet", "--prune", "origin"], in: wd, allowedExitCodes: [0])
        }

        let remoteRef = "refs/remotes/origin/\(branch)"
        let revParse = try await git(
            ["rev-parse", "--verify", "--quiet", remoteRef],
            in: wd,
            allowedExitCodes: [0, 1]
        )
        guard revParse.exitCode == 0 else {
            // Exit 1: the branch doesn't exist on the remote yet — no
            // profiles have been pushed there.
            return nil
        }

        try await checkoutRemoteBranch(at: wd)

        let fileURL = wd.appendingPathComponent("team_profiles.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    // MARK: - Push

    /// Writes `data` to `team_profiles.json` on `branch` at `remote`,
    /// committing and pushing only if that changes anything.
    ///
    /// The working copy is force-checked-out to the remote branch's tip
    /// first (or created fresh if the branch doesn't exist yet on the
    /// remote) — this cache is a disposable mirror, not a place local
    /// commits are expected to survive; the app's `EncodingProfileStore`
    /// (via the caller's serialised `profiles`) is the source of truth.
    ///
    /// - Parameters:
    ///   - data: The bytes to write to `team_profiles.json`.
    ///   - message: The commit message.
    /// - Returns: `.nothingToPush` if `data` already matches the branch tip
    ///   exactly (no commit or push attempted); `.pushed` once the commit
    ///   and `git push` both succeed.
    /// - Throws: `TeamProfileError.gitCommandFailed` if any git command
    ///   exits outside its allowed codes — including a non-fast-forward
    ///   push rejection (another machine pushed since this sync's last
    ///   fetch). Retrying re-syncs to the new tip and re-commits, the same
    ///   last-writer-wins semantics as the shared-folder sync path.
    public func push(_ data: Data, message: String) async throws -> PushOutcome {
        let wd = workingDirectory
        let didClone = try await ensureWorkingCopy(at: wd)

        if !didClone {
            _ = try await git(["fetch", "--quiet", "--prune", "origin"], in: wd, allowedExitCodes: [0])
        }

        let remoteRef = "refs/remotes/origin/\(branch)"
        let revParse = try await git(
            ["rev-parse", "--verify", "--quiet", remoteRef],
            in: wd,
            allowedExitCodes: [0, 1]
        )

        if revParse.exitCode == 0 {
            try await checkoutRemoteBranch(at: wd)
        } else {
            // The branch doesn't exist on the remote yet — create it from
            // the working copy's current (possibly unborn) HEAD.
            _ = try await git(
                ["checkout", "--quiet", "--force", "-B", branch],
                in: wd,
                allowedExitCodes: [0]
            )
        }

        let fileURL = wd.appendingPathComponent("team_profiles.json")
        try data.write(to: fileURL, options: .atomic)

        _ = try await git(["add", "--", "team_profiles.json"], in: wd, allowedExitCodes: [0])

        let diff = try await git(
            ["diff", "--cached", "--quiet", "--", "team_profiles.json"],
            in: wd,
            allowedExitCodes: [0, 1]
        )
        guard diff.exitCode != 0 else {
            // Exit 0: nothing staged — the write produced byte-identical
            // content to what's already committed.
            return .nothingToPush
        }

        var commitArguments: [String] = []
        let identity = try await git(["config", "--get", "user.email"], in: wd, allowedExitCodes: [0, 1])
        if identity.exitCode != 0 {
            // No user.email configured anywhere git would look (this repo,
            // global, or system config) — supply a throwaway identity so
            // the commit doesn't fail; this is a disposable cache commit,
            // not a change to the user's own git identity.
            commitArguments += [
                "-c", "user.name=MeedyaConverter",
                "-c", "user.email=meedyaconverter@local",
            ]
        }
        commitArguments += ["-c", "commit.gpgsign=false", "commit", "--quiet", "-m", message]
        _ = try await git(commitArguments, in: wd, allowedExitCodes: [0])

        _ = try await git(["push", "--quiet", "origin", branch], in: wd, allowedExitCodes: [0])

        return .pushed
    }

    // MARK: - Working Copy

    /// Ensures `<wd>/.git` exists, cloning `remote` into `wd` if not.
    ///
    /// - Returns: `true` if a fresh clone was just performed — the caller
    ///   should skip the immediate `fetch`, since a fresh clone already
    ///   reflects the remote's current state. `false` if an existing clone
    ///   was reused and needs an explicit `fetch` to pick up other
    ///   machines' pushes.
    @discardableResult
    private func ensureWorkingCopy(at wd: URL) async throws -> Bool {
        let gitDir = wd.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            return false
        }

        // `wd` may exist without `.git` inside it — a previous clone that
        // was interrupted, or a leftover non-git directory. Either way it
        // can't be reused; remove it before cloning fresh.
        if FileManager.default.fileExists(atPath: wd.path) {
            try FileManager.default.removeItem(at: wd)
        }
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        _ = try await git(
            ["clone", "--quiet", "--", remote, wd.path],
            in: cacheRoot,
            allowedExitCodes: [0]
        )
        return true
    }

    /// Force-checks-out `branch` to the tip of `origin/<branch>`, replacing
    /// whatever the working tree currently holds.
    ///
    /// This is what makes the cache a disposable mirror rather than a place
    /// local state survives: a stale local commit left behind by a
    /// previously failed push is discarded here on the very next sync.
    private func checkoutRemoteBranch(at wd: URL) async throws {
        _ = try await git(
            ["checkout", "--quiet", "--force", "-B", branch, "refs/remotes/origin/\(branch)"],
            in: wd,
            allowedExitCodes: [0]
        )
    }

    // MARK: - git Command Helper

    /// Runs one git command via `runner`, throwing
    /// `TeamProfileError.gitCommandFailed` (carrying git's own stderr) for
    /// any exit code outside `allowedExitCodes`.
    private func git(
        _ arguments: [String],
        in workingDirectory: URL,
        allowedExitCodes: Set<Int32>
    ) async throws -> GitCommandResult {
        let result = try await runner.run(arguments, in: workingDirectory)
        guard allowedExitCodes.contains(result.exitCode) else {
            throw TeamProfileError.gitCommandFailed(
                command: Self.commandLabel(for: arguments),
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    /// The "command" label used in a thrown `.gitCommandFailed` — the first
    /// element of `arguments` that is neither a flag (`-x`/`--x`) nor a
    /// `-c key=value` config override, so e.g. `["-c", "user.name=…", "-c",
    /// "commit.gpgsign=false", "commit", "--quiet", "-m", message]` labels
    /// itself `"commit"`, not `"-c"`.
    private static func commandLabel(for arguments: [String]) -> String {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument == "-c" {
                // Skip "-c" and its "key=value" companion together.
                index += 2
                continue
            }
            if argument.hasPrefix("-") {
                index += 1
                continue
            }
            return argument
        }
        return arguments.first ?? "git"
    }

    // MARK: - Cache Location

    /// Default cache root: `~/Library/Application Support/MeedyaConverter/TeamProfiles/GitCache/`.
    public static func defaultCacheRoot(fileManager: FileManager = .default) -> URL {
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        return appSupport
            .appendingPathComponent("MeedyaConverter", isDirectory: true)
            .appendingPathComponent("TeamProfiles", isDirectory: true)
            .appendingPathComponent("GitCache", isDirectory: true)
    }

    /// The per-remote cache directory name: a human-readable slug (the last
    /// `/`- or `:`-separated component of `remote`, minus a trailing
    /// `.git`, restricted to `[A-Za-z0-9._-]`, capped at 40 characters, or
    /// `"repo"` if that leaves nothing usable) plus a hyphen and the first
    /// 12 hex characters of SHA-256(`remote`).
    ///
    /// Keying by the remote's own hash — not just the slug — means two
    /// distinct remotes that happen to share a slug (e.g. two different
    /// hosts both named `profiles.git`) never collide on one cache
    /// directory; keying deterministically off `remote` (not e.g. a random
    /// UUID) means the same remote always maps back to the same cache
    /// across app launches, so `fetch` stays incremental instead of
    /// re-cloning every time.
    public static func cacheDirectoryName(forRemote remote: String) -> String {
        let digest = SHA256.hash(data: Data(remote.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        let shortHash = String(hex.prefix(12))

        let lastComponent = remote
            .split(whereSeparator: { $0 == "/" || $0 == ":" })
            .last
            .map(String.init) ?? ""
        let withoutGitSuffix = lastComponent.hasSuffix(".git")
            ? String(lastComponent.dropLast(4))
            : lastComponent

        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
        )
        var slug = String(withoutGitSuffix.unicodeScalars.filter { allowed.contains($0) })
        if slug.count > 40 {
            slug = String(slug.prefix(40))
        }
        if slug.isEmpty {
            slug = "repo"
        }

        return "\(slug)-\(shortHash)"
    }

    /// The disposable working-copy directory for `remote`, under `cacheRoot`.
    public static func workingDirectory(forRemote remote: String, cacheRoot: URL) -> URL {
        cacheRoot.appendingPathComponent(cacheDirectoryName(forRemote: remote), isDirectory: true)
    }

    // MARK: - Sandbox Detection

    /// Whether the current process is running inside the macOS App Sandbox.
    ///
    /// Checks for `APP_SANDBOX_CONTAINER_ID`, which launchd sets in a
    /// sandboxed process's environment. Drives an App-Store-build-only UI
    /// warning in `TeamProfileView` — a sandboxed child process cannot
    /// reach `~/.ssh` or `~/.gitconfig`, so private-repo authentication is
    /// not possible there; only public HTTPS remotes can be pulled.
    public static func isRunningInAppSandbox(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
