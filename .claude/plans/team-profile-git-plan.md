<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Implementation Plan — Real git for Team Profile "Git Repository" sync (#345)

> **Status: PLANNED, not yet implemented.** Produced by a sequential Fable 5.1
> deep-planning agent (2026-09-02); the git command sequence was empirically
> verified against a local bare repo (git 2.50.1) — empty-remote clone, branch
> creation, no-change detection, non-fast-forward rejection, recovery, and
> fail-fast on missing credentials were all observed. Every command below
> prescribes only exit codes that were seen. Implement via Sonnet, gate with the
> compile filter, push, and **watch CI to green** (`swift test` is CI-only here).

## Files

| Action | Path |
|---|---|
| **Create** | `Sources/ConverterEngine/Utilities/GitProfileSync.swift` — `GitRunning` protocol, `GitCommandResult`, `ProcessGitRunner`, `GitProfileSync` |
| **Modify** | `Sources/ConverterEngine/Utilities/TeamProfileManager.swift` — repository fields, `.gitRepository` branches, errors, injectable runner, `pullProfiles` → `async` |
| **Modify** | `Sources/MeedyaConverter/Views/TeamProfileView.swift` — remote + branch fields, footer, `await` on pull, stale comment |
| **Create** | `Tests/ConverterEngineTests/GitProfileSyncTests.swift` — mock runner, sequence/path/failure tests, manager round-trip |
| **Modify** | `CHANGELOG.md` — one line under `## [Unreleased]` → `### Added` (after the existing #482 line, ~L40) |

Reference patterns (read, not modified): `DualDynamicHDRPipelineExecutor.swift:69-75`
(injectable `…Running: Sendable` protocol) and `DualDynamicHDRPipelineExecutorTests.swift:35-78`
(lock-guarded mock, `import ConverterEngine` without `@testable`);
`DoviToolWrapper.swift:393-422` (`Process` + `withCheckedThrowingContinuation`);
`DuplicateDetector.swift:9,83` (`import CryptoKit` / SHA256 already in ConverterEngine).

## Current behaviour (verified against code, not comments)

`TeamProfileManager.swift`
- `SyncMethod` = `.iCloudSharedFolder`, `.gitRepository`, `.httpServer`.
- `TeamProfileRepository` — `serverURL: URL?`, `sharedFolderPath: URL?`, `syncMethod`, `lastSync`.
- Both push/pull serialize the **whole `[EncodingProfile]` array into one file `team_profiles.json`**
  (encoder is `.prettyPrinted, .sortedKeys`, ISO-8601 dates). The git path must reuse this exact serialization.
- `isConfigured` groups `.gitRepository` with `.httpServer` on `serverURL != nil`.
- `pushProfiles(_:to:) async throws` `.gitRepository` branch: `repoURL.appendingPathComponent("team_profiles.json")`
  then `data.write(...)` — a **loose file write, no git**. For `https://…` and `git@host:…` it throws.
  The doc claiming "for Git it writes to the repository working tree" is **false**.
- `pullProfiles(from:) throws` is **synchronous**; `.gitRepository` does `Data(contentsOf: <url>/team_profiles.json)` → throws for real remotes.
- `detectConflicts(local:remote:)` / `resolveConflicts` machinery exists and is reused unchanged.
- `TeamProfileError` — `.noSharedFolder`, `.noServerURL`, `.decodingFailed`, `.httpError` (not `Equatable`).
- `TeamProfileRepository`/`TeamProfileManager` constructed **only** in `TeamProfileView.swift` and
  `TeamProfileConflictTests.swift` → adding fields needs no migration.

`TeamProfileView.swift`
- State: `syncMethod`, `serverURLString`, `sharedFolderPath` — no branch, not persisted.
- Git + http share one `TextField` bound to `serverURLString`.
- `buildRepository()` → `serverURL: URL(string: serverURLString)`.
- Pull uses `Task.detached { return try mgr.pullProfiles(from: repository) }` (sync) — becomes `try await`.
- Already feeds pulled profiles through `detectConflicts(local:remote:)` — so git only needs to return real remote profiles.
- `resolveAllConflicts()` computes `merged` and **discards it** (pre-existing bug — Risk 5).

Environment facts shaping the design
- App Store build is sandboxed (`app-sandbox` + `network.client`); Direct build is hardened-runtime only.
  A sandboxed child git cannot reach `~/.ssh` or `~/.gitconfig` → private-repo auth impossible there.
- GUI apps launch with `PATH=/usr/bin:/bin:/usr/sbin:/sbin`; `/usr/bin/git` is the xcode-select **shim**
  (exit 1 + install dialog when CLT absent). Real binaries: `/opt/homebrew/bin/git`, `/usr/local/bin/git`,
  `/Library/Developer/CommandLineTools/usr/bin/git`, `/Applications/Xcode.app/Contents/Developer/usr/bin/git`.
- Verified (git 2.50.1, local bare repo): `clone --quiet` of an empty remote → exit 0;
  `rev-parse --verify --quiet refs/remotes/origin/main` → 1 absent / 0 present;
  `checkout --quiet --force -B main [ref]` works on unborn HEAD and replaces a dirty tree;
  `diff --cached --quiet -- file` → 1 with staged changes / 0 without; `config --get user.email` → 1 when unset;
  `push --quiet origin main` creates the branch, exits 1 "(fetch first)" on non-fast-forward;
  with `GIT_TERMINAL_PROMPT=0` and stdin closed, an https clone needing creds fails in <1s (exit 128), never hangs.

## Design

- **Seam.** `protocol GitRunning: Sendable { func run(_ arguments: [String], in workingDirectory: URL) async throws -> GitCommandResult }`.
  `ProcessGitRunner` is the real conformer; tests inject `MockGitRunner`. `GitProfileSync` holds all sequencing.
- **Data contract.** `GitProfileSync` deals in `Data` not profiles: `push(_ data:, message:) -> PushOutcome`, `pull() -> Data?`.
  `TeamProfileManager` keeps encode/decode ownership → byte-identical serialization to the shared-folder path.
- **Command sequence** (all `--quiet`; `origin/<branch>` referenced explicitly):
  - *ensure working copy*: `<wd>/.git` exists → nothing (`didClone=false`); else remove stale `<wd>`, create cache root,
    `git clone --quiet -- <remote> <wd>` in the cache root (`didClone=true`).
  - *pull*: `[fetch --quiet --prune origin]` (skipped right after clone) → `rev-parse --verify --quiet refs/remotes/origin/<branch>`;
    exit 1 → remote has no profiles yet → return `nil`; exit 0 → `checkout --quiet --force -B <branch> refs/remotes/origin/<branch>` → read `<wd>/team_profiles.json` (nil if absent).
  - *push*: same fetch/rev-parse; remote branch absent → `checkout --quiet --force -B <branch>` (creates from unborn/current HEAD);
    else forced checkout to remote tip. Then write file atomically → `add -- team_profiles.json` →
    `diff --cached --quiet -- team_profiles.json` (exit 0 → `.nothingToPush`) → `config --get user.email`
    (exit 1 → prepend `-c user.name=MeedyaConverter -c user.email=meedyaconverter@local`) →
    `-c commit.gpgsign=false commit --quiet -m <message>` → `push --quiet origin <branch>` → `.pushed`.
  - Forced checkout makes the cache a **disposable mirror**: the app's `EncodingProfileStore` is source of truth;
    a stale local commit from a failed push is discarded next sync; non-fast-forward reject surfaces as an error whose retry re-syncs and re-commits (file-level last-writer-wins, same as shared-folder + history).
- **Auth.** None invented. Git inherits the user's env (`~/.gitconfig` helpers, `git-credential-osxkeychain`, SSH agent).
  Safeguards: `GIT_TERMINAL_PROMPT=0` + `standardInput = FileHandle.nullDevice`; prepend `/opt/homebrew/bin:/usr/local/bin` to PATH so helpers resolve from a GUI process. `GIT_SSH_COMMAND`/`core.sshCommand` deliberately not overridden.
- **Working directory.** `~/Library/Application Support/MeedyaConverter/TeamProfiles/GitCache/<slug>-<sha256(remote)[0..<12]>/`
  (`slug` = last `/`- or `:`-separated component minus `.git`, `[A-Za-z0-9._-]` only, ≤40 chars, `"repo"` if empty).
  Keying by hash → distinct remotes never share a cache; stable across launches (incremental fetches).
- **Errors.** Three new `TeamProfileError` cases: `.noGitRemote`, `.gitNotFound`, `.gitCommandFailed(command:exitCode:stderr:)`;
  any disallowed exit code throws `gitCommandFailed` carrying git's own stderr. View already shows `error.localizedDescription` in red.
- **Sandbox.** `GitProfileSync.isRunningInAppSandbox(environment:)` (checks `APP_SANDBOX_CONTAINER_ID`) drives an orange footer warning in the App Store build.

## Exact code

The full annotated source for `GitProfileSync.swift` (GitCommandResult / GitRunning /
ProcessGitRunner with `searchPaths`, `locate`, `gitEnvironment`, `run`; GitProfileSync
with `pull`/`push`/`ensureWorkingCopy`/`checkoutRemoteBranch`/`git` helper +
`defaultCacheRoot`/`cacheDirectoryName`/`workingDirectory`/`isRunningInAppSandbox`) is in the
session transcript (task a39f0a9bb6ab0d9fa). Key invariants when re-deriving:
- `ProcessGitRunner.searchPaths` MUST NOT contain `/usr/bin/git` (the shim).
- `run` drains stdout to EOF **before** `waitUntilExit` (pipe-buffer deadlock guard); every command is `--quiet` so stderr stays under 64 KB.
- `gitEnvironment` sets `GIT_TERMINAL_PROMPT=0` and prepends Homebrew/local bin dirs without duplicating.
- `git(_:in:allowedExitCodes:)` throws `.gitCommandFailed` for any exit code outside the allowed set; the "command" label is the first arg that is neither a flag nor a `-c key=value`.
- The push identity fallback only prepends `-c user.name/email` when `config --get user.email` exits non-zero.

## TeamProfileManager changes
- Add `gitRemote: String?` (String, not URL — scp-style has no scheme) and `gitBranch: String?` to `TeamProfileRepository` + init.
- Add injectable `gitRunner: (any GitRunning)?` (nil → `ProcessGitRunner.locate()` at sync time) and `gitCacheRoot: URL?` to the manager init.
- Split `isConfigured` `.gitRepository` case → `!(repo.gitRemote ?? "").trimmed.isEmpty`.
- Private `makeGitSync(for:)` factory (throws `.noGitRemote` on empty remote; resolves runner + cache root).
- Fix the false push doc (drop "writes to the repository working tree"); `.gitRepository` push branch → `try makeGitSync(...).push(data, message: "Update team profiles (N profile(s))")`.
- Make `pullProfiles(from:) async throws`; `.gitRepository` pull → `try makeGitSync(...).pull()`; `guard let data else { return [] }` so a remote with no branch/file yields `[]` not an error. Both `_repository` updates carry the two new fields.
- Add the three `TeamProfileError` cases + descriptions.

## TeamProfileView changes
- `@AppStorage("teamProfiles.gitRemote") private var gitRemote = ""` and `@AppStorage("teamProfiles.gitBranch") private var gitBranch = "main"` (persist so the remote isn't retyped; leaves the other fields' pre-existing non-persistence alone).
- Split the combined case into a Repository `TextField` (placeholder shows https/scp/local) + a Branch `TextField`.
- Footer: git → explain commit-to-branch + user's own credentials + never stores tokens; add an orange App-Sandbox warning gated on `GitProfileSync.isRunningInAppSandbox()`. Else → the existing generic text.
- `buildRepository()` passes `gitRemote`/`gitBranch` (nil when empty).
- Rewrite the two stale comments (the "genuinely blocking synchronous file I/O" clause and the pull-doc) to describe awaited git subprocesses.
- Pull: `let pulled = try await Task.detached { let mgr = TeamProfileManager(repository: repository); return try await mgr.pullProfiles(from: repository) }.value`.

## Tests (`GitProfileSyncTests.swift`, `import ConverterEngine`, no git binary / no network)
`MockGitRunner` (lock-guarded, `@unchecked Sendable`): records `[Call]`, exit code + stderr per subcommand, optional `onCheckout` to materialise files. Fixture: temp dir in setUp/tearDown; `wd = tempDir/wd`; `remote = "git@github.com:acme/profiles.git"`; helpers `makeSync`, `simulateExistingClone()`.
Cases (18): cacheDirectoryName slug+hash stability/safety; workingDirectory under cache root; fresh-cache pull clones-then-checks-out-without-fetch; existing-cache pull fetches; stale-dir-without-.git removed before clone; remote-branch-absent pull returns nil + no checkout; custom branch in ref + checkout (+ blank branch → "main"); push writes→add→commit→push in order; no-staged-changes → `.nothingToPush`; no-identity → fallback identity args; remote-branch-absent push creates branch with no start-point; git-nonzero → `.gitCommandFailed` with stderr + stops sequence (+ fetch-fail variant); ProcessGitRunner.locate preference + `.gitNotFound` + no `/usr/bin/git`; gitEnvironment prompt-off + PATH prepend/no-dup; isRunningInAppSandbox; **manager round-trip** (push then pull through injected runner round-trips profiles + feeds detectConflicts); missing-remote → `.noGitRemote` + no calls; remote-without-profiles → `[]`.

## Gates
```
swift build --target ConverterEngine
swift build 2>&1 | grep "error:" | grep -v "PreviewsMacros\|Preview(_:body:)\|emit-module"   # must print nothing
swiftc -parse Tests/ConverterEngineTests/GitProfileSyncTests.swift
```
Then push to `wip/alpha-consolidation` and **watch CI to green**.

Manual E2E (no network/auth): `git init --bare /tmp/team.git`, enter it as Repository + `main`, Push (creates branch),
edit a profile, Push again, Pull; then `git clone /tmp/team.git /tmp/other`, change a profile's `description`, commit, push,
Pull in app → Conflicts section lists it. Cache lands in `…/TeamProfiles/GitCache/team-<12hex>/`.

## Risks
1. **App Store build cannot authenticate** (sandbox has no `~/.ssh`/`~/.gitconfig`) — public HTTPS pull works; private/push fail; orange footer discloses. Don't claim App Store parity.
2. **No cancellation/timeout** — a stalled network holds `isSyncing` until git's own timeouts (prompts can't hang it). Follow-up: `withTaskCancellationHandler` + `process.terminate()`.
3. **Pipe buffer** — stdout drained before wait; stderr relies on `--quiet`. Keep `--quiet` on any added command.
4. **Last-writer-wins on push** — push never merges; identical semantic to shared-folder + history + conflict-on-next-pull.
5. **Pre-existing: "Resolve All" persists nothing** (`resolveAllConflicts()` discards `merged`, all methods). Out of scope; one-line fix `addProfile`/`updateProfile` (both at `EncodingProfile.swift:940,948`). Flag in the PR, don't silently widen.
6. **`pullProfiles` becomes `async`** — only caller is the view (already in `Task.detached`); CLI doesn't use it. One `await`.
7. **`-c commit.gpgsign=false`** overrides user's global signing for these data commits (avoids pinentry stalls). Drop if the team wants signed data commits.
8. **`git init --bare` HEAD → `master`** — clone prints a benign "nonexistent ref" once branch is `main`; harmless (every checkout targets the explicit ref).
9. **Homebrew git first** — reads the same `~/.gitconfig` as Apple git; ordering only avoids the shim.
10. **False-comment hygiene** (this repo's recurring defect) — rewrite the three stale claims touched; apply the "does this hold at every call site?" test to every new doc comment.
