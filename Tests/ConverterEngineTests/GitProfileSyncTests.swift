// ============================================================================
// MeedyaConverter — GitProfileSyncTests (Issue #345)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Pure, CI-runnable tests for `GitProfileSync` and `ProcessGitRunner` — no
// real git binary is ever invoked and no network access is required. A
// `MockGitRunner` (conforming to the public `GitRunning` protocol) stands in
// for `ProcessGitRunner`, so the clone/fetch/rev-parse/checkout/commit/push
// command sequencing, exit-code handling, and cache-directory naming can all
// be exercised deterministically.
//
// The mock never touches git or the network, but `GitProfileSync` itself
// still performs *real* filesystem I/O (writing/reading `team_profiles.json`
// under a temp cache root) — mirroring what a real `git checkout` would
// leave behind is the mock's job wherever that matters, matching
// `MockDualDynamicHDRStepRunner`'s "materialise what a real tool would have
// left behind" approach in `DualDynamicHDRPipelineExecutorTests`.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

// MARK: - MockGitRunner

/// Records every `run(_:in:)` call and returns a configurable exit
/// code/stdout/stderr per subcommand (looked up the same way
/// `GitProfileSync.commandLabel(for:)` labels a command internally: the
/// first argument that is neither a flag nor a `-c key=value` pair).
/// Unconfigured subcommands default to a successful `(0, "", "")`.
final class MockGitRunner: GitRunning, @unchecked Sendable {

    struct Call: Equatable {
        let arguments: [String]
        let workingDirectory: URL
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    /// Exit code/stdout/stderr to return for a given subcommand label.
    var responses: [String: (exitCode: Int32, stdout: String, stderr: String)] = [:]

    /// Invoked whenever a `checkout` command runs (after `responses` would
    /// be consulted), so tests can populate the working directory with the
    /// files a real checkout would have brought in.
    var onCheckout: ((URL) -> Void)?

    var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    func run(_ arguments: [String], in workingDirectory: URL) async throws -> GitCommandResult {
        lock.withLock {
            recordedCalls.append(Call(arguments: arguments, workingDirectory: workingDirectory))
        }

        let label = Self.commandLabel(for: arguments)
        if label == "checkout" {
            // A real `git checkout` guarantees the working directory exists
            // and holds whatever the target ref contains. This mock never
            // touches the filesystem on its own, so materialise the
            // directory here — `onCheckout` (if set) can then write files
            // into it, and `GitProfileSync`'s own subsequent plain
            // read/write calls behave exactly as they would after a real
            // checkout.
            try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            onCheckout?(workingDirectory)
        }

        let response = responses[label] ?? (exitCode: Int32(0), stdout: "", stderr: "")
        return GitCommandResult(exitCode: response.exitCode, stdout: response.stdout, stderr: response.stderr)
    }

    /// Mirrors `GitProfileSync`'s private `commandLabel(for:)`: the first
    /// argument that isn't a flag or a `-c key=value` pair.
    static func commandLabel(for arguments: [String]) -> String {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument == "-c" {
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
}

// MARK: - GitProfileSyncTests

final class GitProfileSyncTests: XCTestCase {

    // MARK: - Fixtures

    private var tempDir: URL!
    private let remote = "git@github.com:acme/profiles.git"

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-profile-sync-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private func makeSync(branch: String = "main", runner: any GitRunning) -> GitProfileSync {
        GitProfileSync(remote: remote, branch: branch, runner: runner, cacheRoot: tempDir)
    }

    /// Pre-creates `<workingDirectory>/.git` so `GitProfileSync` treats the
    /// cache as an existing clone (no `clone` call — `fetch` instead).
    private func simulateExistingClone(for sync: GitProfileSync) throws {
        try FileManager.default.createDirectory(
            at: sync.workingDirectory.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
    }

    /// Writes a `team_profiles.json` as a real checkout would. Captures no
    /// `self` so it's safe to hand to `MockGitRunner.onCheckout` uncritically.
    private static func writeRemoteProfilesFile(at workingDirectory: URL, json: String = "[]") {
        FileManager.default.createFile(
            atPath: workingDirectory.appendingPathComponent("team_profiles.json").path,
            contents: Data(json.utf8)
        )
    }

    // MARK: - cacheDirectoryName / workingDirectory

    func test_cacheDirectoryName_isStableAndSlugIsSafe() {
        let remote = "git@github.com:acme/Team-Profiles.git"
        let name1 = GitProfileSync.cacheDirectoryName(forRemote: remote)
        let name2 = GitProfileSync.cacheDirectoryName(forRemote: remote)
        XCTAssertEqual(name1, name2, "The same remote must always map to the same cache directory name")
        XCTAssertTrue(name1.hasPrefix("Team-Profiles-"), "Slug is the last path/colon component minus .git")
        XCTAssertTrue(
            name1.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" },
            "Only [A-Za-z0-9._-] may appear in the cache directory name"
        )

        // Two distinct remotes never collide, even when the slug would be
        // empty after sanitisation — a bare hash is never reused as "repo"
        // for two different remotes because the hash differs too.
        let unsafeRemote = "https://example.com/weird path/???.git"
        let unsafeName = GitProfileSync.cacheDirectoryName(forRemote: unsafeRemote)
        XCTAssertNotEqual(unsafeName, name1)
        XCTAssertTrue(unsafeName.hasPrefix("repo-"), "An all-unsafe-character slug falls back to \"repo\"")
        XCTAssertTrue(unsafeName.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" })

        // The slug is capped at 40 characters; the full name is bounded by
        // 40 + "-" + 12 hex hash characters.
        let longRemote = "https://example.com/\(String(repeating: "a", count: 100)).git"
        let longName = GitProfileSync.cacheDirectoryName(forRemote: longRemote)
        XCTAssertLessThanOrEqual(longName.count, 40 + 1 + 12)
    }

    func test_workingDirectory_isUnderCacheRoot() {
        let cacheRoot = tempDir!
        let wd = GitProfileSync.workingDirectory(forRemote: remote, cacheRoot: cacheRoot)
        XCTAssertEqual(wd.deletingLastPathComponent().standardizedFileURL, cacheRoot.standardizedFileURL)
        XCTAssertEqual(wd.lastPathComponent, GitProfileSync.cacheDirectoryName(forRemote: remote))
    }

    // MARK: - Pull

    func test_pull_freshCache_clonesThenChecksOutWithoutFetch() async throws {
        let runner = MockGitRunner()
        runner.onCheckout = { wd in Self.writeRemoteProfilesFile(at: wd) }
        let sync = makeSync(runner: runner)

        let data = try await sync.pull()

        XCTAssertEqual(runner.calls.map { $0.arguments.first }, ["clone", "rev-parse", "checkout"])
        XCTAssertEqual(data, Data("[]".utf8))
    }

    func test_pull_existingCache_fetchesFirst() async throws {
        let runner = MockGitRunner()
        runner.onCheckout = { wd in Self.writeRemoteProfilesFile(at: wd) }
        let sync = makeSync(runner: runner)
        try simulateExistingClone(for: sync)

        _ = try await sync.pull()

        XCTAssertEqual(runner.calls.map { $0.arguments.first }, ["fetch", "rev-parse", "checkout"])
    }

    func test_pull_staleDirectoryWithoutGit_isRemovedBeforeClone() async throws {
        let runner = MockGitRunner()
        runner.onCheckout = { wd in Self.writeRemoteProfilesFile(at: wd) }
        let sync = makeSync(runner: runner)
        let wd = sync.workingDirectory
        try FileManager.default.createDirectory(at: wd, withIntermediateDirectories: true)
        let staleFile = wd.appendingPathComponent("stale.txt")
        try Data("stale".utf8).write(to: staleFile)

        _ = try await sync.pull()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: staleFile.path),
            "A stale directory lacking .git must be removed before cloning fresh"
        )
        XCTAssertEqual(runner.calls.first?.arguments.first, "clone")
    }

    func test_pull_remoteBranchAbsent_returnsNilWithoutCheckingOut() async throws {
        let runner = MockGitRunner()
        runner.responses["rev-parse"] = (exitCode: 1, stdout: "", stderr: "")
        let sync = makeSync(runner: runner)

        let data = try await sync.pull()

        XCTAssertNil(data)
        XCTAssertFalse(runner.calls.map { $0.arguments.first }.contains("checkout"))
    }

    func test_pull_customBranchAppearsInRefAndCheckout_blankBranchDefaultsToMain() async throws {
        let runner = MockGitRunner()
        runner.onCheckout = { wd in Self.writeRemoteProfilesFile(at: wd) }
        let sync = makeSync(branch: "develop", runner: runner)

        _ = try await sync.pull()

        let revParseArgs = runner.calls.first { $0.arguments.first == "rev-parse" }?.arguments ?? []
        XCTAssertTrue(revParseArgs.contains("refs/remotes/origin/develop"))
        let checkoutArgs = runner.calls.first { $0.arguments.first == "checkout" }?.arguments ?? []
        XCTAssertTrue(checkoutArgs.contains("develop"))
        XCTAssertTrue(checkoutArgs.contains("refs/remotes/origin/develop"))

        let blankBranchSync = GitProfileSync(
            remote: remote,
            branch: "   ",
            runner: MockGitRunner(),
            cacheRoot: tempDir
        )
        XCTAssertEqual(blankBranchSync.branch, "main")
    }

    // MARK: - Push

    func test_push_sequencesWriteAddCommitPushInOrder() async throws {
        let runner = MockGitRunner()
        runner.responses["diff"] = (exitCode: 1, stdout: "", stderr: "") // staged changes present
        let sync = makeSync(runner: runner)

        let outcome = try await sync.push(Data("[]".utf8), message: "Update team profiles (0 profile(s))")

        XCTAssertEqual(outcome, .pushed)
        XCTAssertEqual(
            runner.calls.map { MockGitRunner.commandLabel(for: $0.arguments) },
            ["clone", "rev-parse", "checkout", "add", "diff", "config", "commit", "push"]
        )

        let fileURL = sync.workingDirectory.appendingPathComponent("team_profiles.json")
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("[]".utf8))
    }

    func test_push_noStagedChanges_returnsNothingToPush() async throws {
        let runner = MockGitRunner()
        // Default "diff" exit code (0) simulates nothing staged.
        let sync = makeSync(runner: runner)

        let outcome = try await sync.push(Data("[]".utf8), message: "msg")

        XCTAssertEqual(outcome, .nothingToPush)
        XCTAssertFalse(runner.calls.map { $0.arguments.first }.contains("commit"))
        XCTAssertFalse(runner.calls.map { $0.arguments.first }.contains("push"))
    }

    func test_push_noIdentityConfigured_prependsFallbackIdentity() async throws {
        let runner = MockGitRunner()
        runner.responses["diff"] = (exitCode: 1, stdout: "", stderr: "")
        runner.responses["config"] = (exitCode: 1, stdout: "", stderr: "")
        let sync = makeSync(runner: runner)

        _ = try await sync.push(Data("[]".utf8), message: "msg")

        let commitCall = runner.calls.first { $0.arguments.contains("commit") }
        XCTAssertNotNil(commitCall)
        XCTAssertTrue(commitCall?.arguments.contains("user.name=MeedyaConverter") ?? false)
        XCTAssertTrue(commitCall?.arguments.contains("user.email=meedyaconverter@local") ?? false)
    }

    func test_push_remoteBranchAbsent_createsBranchWithNoStartPoint() async throws {
        let runner = MockGitRunner()
        runner.responses["rev-parse"] = (exitCode: 1, stdout: "", stderr: "")
        runner.responses["diff"] = (exitCode: 1, stdout: "", stderr: "")
        let sync = makeSync(runner: runner)

        let outcome = try await sync.push(Data("[]".utf8), message: "msg")

        XCTAssertEqual(outcome, .pushed)
        let checkoutCall = runner.calls.first { $0.arguments.first == "checkout" }
        XCTAssertEqual(checkoutCall?.arguments, ["checkout", "--quiet", "--force", "-B", "main"])
    }

    func test_push_gitCommandFails_throwsGitCommandFailedAndStopsSequence() async throws {
        let runner = MockGitRunner()
        runner.responses["add"] = (
            exitCode: 1,
            stdout: "",
            stderr: "fatal: pathspec 'team_profiles.json' did not match any files"
        )
        let sync = makeSync(runner: runner)

        do {
            _ = try await sync.push(Data("[]".utf8), message: "msg")
            XCTFail("Expected a thrown TeamProfileError.gitCommandFailed")
        } catch let TeamProfileError.gitCommandFailed(command, exitCode, stderr) {
            XCTAssertEqual(command, "add")
            XCTAssertEqual(exitCode, 1)
            XCTAssertTrue(stderr.contains("pathspec"))
        }

        XCTAssertEqual(
            runner.calls.map { $0.arguments.first ?? "" },
            ["clone", "rev-parse", "checkout", "add"],
            "No command after the failing one may run"
        )
    }

    func test_pull_fetchFails_throwsGitCommandFailedAndStopsSequence() async throws {
        let runner = MockGitRunner()
        let sync = makeSync(runner: runner)
        try simulateExistingClone(for: sync)
        runner.responses["fetch"] = (exitCode: 128, stdout: "", stderr: "fatal: could not read from remote repository")

        do {
            _ = try await sync.pull()
            XCTFail("Expected a thrown TeamProfileError.gitCommandFailed")
        } catch let TeamProfileError.gitCommandFailed(command, exitCode, stderr) {
            XCTAssertEqual(command, "fetch")
            XCTAssertEqual(exitCode, 128)
            XCTAssertTrue(stderr.contains("could not read"))
        }

        XCTAssertFalse(runner.calls.map { $0.arguments.first }.contains("rev-parse"))
    }

    // MARK: - ProcessGitRunner

    func test_processGitRunner_locate_prefersEarlierSearchPathAndExcludesUsrBinGit() throws {
        XCTAssertFalse(
            ProcessGitRunner.searchPaths.contains("/usr/bin/git"),
            "The xcode-select shim must never be a candidate"
        )

        let runner = try ProcessGitRunner.locate(
            isExecutable: { path in path == "/usr/local/bin/git" || path == "/opt/homebrew/bin/git" },
            environment: [:]
        )
        XCTAssertEqual(
            runner.gitPath,
            "/opt/homebrew/bin/git",
            "Homebrew's git must be preferred when both candidates are present"
        )

        XCTAssertThrowsError(try ProcessGitRunner.locate(isExecutable: { _ in false }, environment: [:])) { error in
            guard case TeamProfileError.gitNotFound = error else {
                XCTFail("Expected .gitNotFound, got \(error)")
                return
            }
        }

        // Even if a caller's predicate claims /usr/bin/git is executable,
        // it's never chosen — it's simply absent from searchPaths.
        let runnerIgnoringShim = try ProcessGitRunner.locate(
            isExecutable: { path in path == "/usr/bin/git" || path == "/usr/local/bin/git" },
            environment: [:]
        )
        XCTAssertEqual(runnerIgnoringShim.gitPath, "/usr/local/bin/git")
    }

    func test_gitEnvironment_disablesPromptAndPrependsPathWithoutDuplicating() {
        let base = ["PATH": "/usr/bin:/bin", "HOME": "/Users/test"]
        let env = ProcessGitRunner.gitEnvironment(base: base)

        XCTAssertEqual(env["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertEqual(env["PATH"], "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        XCTAssertEqual(env["HOME"], "/Users/test", "Unrelated environment entries must pass through untouched")

        // Re-deriving from an already-prepended PATH must not duplicate.
        let envAgain = ProcessGitRunner.gitEnvironment(base: env)
        XCTAssertEqual(envAgain["PATH"], env["PATH"])
    }

    // MARK: - Sandbox Detection

    func test_isRunningInAppSandbox_reflectsEnvironmentVariable() {
        XCTAssertTrue(
            GitProfileSync.isRunningInAppSandbox(environment: ["APP_SANDBOX_CONTAINER_ID": "com.example.app"])
        )
        XCTAssertFalse(GitProfileSync.isRunningInAppSandbox(environment: [:]))
    }

    // MARK: - TeamProfileManager Integration

    func test_manager_pushThenPullRoundTripsProfilesThroughInjectedRunner() async throws {
        let runner = MockGitRunner()
        runner.responses["diff"] = (exitCode: 1, stdout: "", stderr: "")
        let repository = TeamProfileRepository(gitRemote: remote, gitBranch: "main", syncMethod: .gitRepository)
        let manager = TeamProfileManager(repository: repository, gitRunner: runner, gitCacheRoot: tempDir)

        // Simulate an already-cloned cache so both push and pull reuse the
        // same on-disk working directory across the round trip.
        let wd = GitProfileSync.workingDirectory(forRemote: remote, cacheRoot: tempDir)
        try FileManager.default.createDirectory(at: wd.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let profile = EncodingProfile(name: "Web", description: "v1")
        try await manager.pushProfiles([profile], to: repository)

        let pulled = try await manager.pullProfiles(from: repository)

        XCTAssertEqual(pulled.map(\.id), [profile.id])
        XCTAssertEqual(pulled.first?.name, "Web")

        let conflicts = manager.detectConflicts(local: [profile], remote: pulled)
        XCTAssertTrue(conflicts.isEmpty, "Round-tripped data must be identical to what was pushed, not a conflict")
    }

    func test_manager_missingGitRemote_throwsNoGitRemoteWithoutAnyGitCalls() async throws {
        let runner = MockGitRunner()
        let repository = TeamProfileRepository(gitRemote: "   ", syncMethod: .gitRepository)
        let manager = TeamProfileManager(repository: repository, gitRunner: runner, gitCacheRoot: tempDir)

        do {
            try await manager.pushProfiles([], to: repository)
            XCTFail("Expected TeamProfileError.noGitRemote")
        } catch TeamProfileError.noGitRemote {
            // Expected.
        }

        XCTAssertTrue(runner.calls.isEmpty, "No git command should run when the remote is unconfigured")
    }

    func test_manager_pullFromRemoteWithoutProfiles_returnsEmptyArray() async throws {
        let runner = MockGitRunner()
        runner.responses["rev-parse"] = (exitCode: 1, stdout: "", stderr: "")
        let repository = TeamProfileRepository(gitRemote: remote, gitBranch: "main", syncMethod: .gitRepository)
        let manager = TeamProfileManager(repository: repository, gitRunner: runner, gitCacheRoot: tempDir)

        let pulled = try await manager.pullProfiles(from: repository)

        XCTAssertEqual(pulled, [])
    }
}
