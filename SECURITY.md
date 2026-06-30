<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — Security Posture

> This is the **dev-team-autopilot SECURE-phase working document** —
> the security-side equivalent of [`PROJECT.md`](PROJECT.md) +
> [`FEATURES.md`](FEATURES.md). It captures attack surface, trust
> boundaries, scanner coverage, threat model, and findings register
> for the autopilot's per-cycle SECURE work.
>
> **For end-user security disclosures** (vulnerability reporting,
> supported versions, response timeline) see
> [`.github/SECURITY.md`](.github/SECURITY.md) — the file GitHub
> auto-surfaces on the repo's Security tab. That is the disclosure
> policy; this is the operating document.

## Phase 0 status — established Cycle 12

This document was first written as the doc-only output of SECURE
Phase 0 (autopilot cycle 12, commit on autopilot/2026-06-30). It
captures the baseline before any purple-team finding has been
filed. Subsequent SECURE cycles populate the Findings Register
below as scanner leads + manual review surface concrete issues.

## Product context

MeedyaConverter is a macOS desktop video / audio converter shipped via
two distribution paths:

- **Direct distribution** — Developer ID-signed and notarised `.dmg`
  hosted on GitHub Releases. Runs with Hardened Runtime, NOT
  sandboxed. This is the primary security focus of v0.1.0.
- **App Store Lite** — sandboxed `.app` distributed through TestFlight
  / Mac App Store. Same codebase compiled with `APP_STORE=1`, which
  swaps the Process-based FFmpeg backend for the in-process FFmpegKit
  backend (Cycle 7 scaffold) and tightens entitlements via
  `MeedyaConverter-AppStore.entitlements`. Deferred ship for v0.1.0
  per the autopilot mission scope.

Both paths share the same source code and same security threat model;
the App Store path has a tighter sandbox boundary that mitigates
several classes of risk by construction.

## Attack surface map

Inventory at Cycle 12 setup (counts via `grep -rln Sources/`):

| Surface | Locations | Count | Trust boundary |
|---------|-----------|-------|-----------------|
| **FFmpeg subprocess invocation** | `Sources/ConverterEngine/FFmpeg/*` + GUI views | ~17 `Process()` × ~30 argument-construction sites | OS process boundary; ffmpeg parses untrusted media |
| **`ffprobe` JSON parse** | `FFmpegProbe.swift` | 1 | JSON over stdout pipe; ffprobe parses untrusted media |
| **Network — GitHub Releases poller** | `Sources/MeedyaConverter/Services/GitHubReleaseChecker.swift` | 1 endpoint | TLS to `api.github.com`; Bundle.main → URLRequest header |
| **Network — Sparkle EdDSA appcast** (v0.2.0+ scaffold) | `Sources/MeedyaConverter/Updates/*` (scaffolded, not active in v0.1.0) | 0 active | TLS to `update.mwbm.io` Cloudflare Worker; EdDSA-verified payload |
| **Network — cloud uploaders** | `Sources/ConverterEngine/Cloud/*` (S3, GCS, Backblaze B2) | ~10 endpoints | TLS to provider APIs; user-supplied OAuth tokens |
| **Network — SMTP** | `EmailNotifier.swift` / `EmailSettingsView.swift:297-336` | 1 invocation | curl pipe with credentials via stdin (NOT argv) |
| **Network — SFTP / FTP** | `SFTPUploader.swift:253-319` (`writeFTPCredentialsConfig`) | 1 invocation | curl with credentials via mode-0600 UUID-named tempfile (NOT argv) |
| **Keychain (writes / reads)** | `Cloud/APIKeyManager.swift` (v1→v2 migration L517-559 per #380) | 3 surfaces | `kSecAttrService` items; no plaintext on disk post-migration |
| **AppleScript / Automator bridge** | `Sources/MeedyaConverter/Scripting/{MeedyaConverter.sdef,ScriptingBridge.swift}` | 1 bridge | scripting events from any AppleScript-capable client |
| **Filesystem — drag-and-drop import** | `Components/DropHandler.swift` (Cycle 1 fixed Swift 6 data race) | 1 handler | `NSItemProvider` URLs from any source app |
| **Filesystem — open / save panels** | various Views/* | many | user-driven |
| **Filesystem — bundled binary execution** | `FFmpegBundleManager.swift` (resolves `Contents/Helpers/ffmpeg` first) | 1 resolver | bundled signed binaries; user's PATH only as fallback |
| **Subtitle / SDH / SDI parsers** | `Sources/ConverterEngine/Subtitles/*` (planned for Phase 8 — out of v0.1.0 scope) | 0 | future surface |
| **URL schemes** | Info.plist `CFBundleURLSchemes` | **0 registered** | no inbound URL trigger; cross-app handoff with MeedyaSubtitler is future Phase 8 work |

## Trust boundaries

In order from most-trusted to least:

1. **Compile-time bundled assets** — code in `Sources/`, the .icns
   from `scripts/generate-app-icns.sh`, the bundled ffmpeg under
   `Contents/Helpers/` once `bundle-ffmpeg.sh` runs in CI. Signed by
   us, validated by Apple notarisation.
2. **GitHub Actions secrets** — the 7 secrets in
   `docs/distribution/apple-secrets-setup.md`. Stored at repo / org
   level by the project owner; never echoed by workflow steps; auto-
   masked by GitHub if accidentally surfaced.
3. **Keychain-stored user secrets** — API keys for cloud providers,
   OAuth tokens. Migrated from plaintext per issue #380.
4. **User-supplied media files (input)** — untrusted but processed
   through ffmpeg which has its own hardening; we never parse media
   structures ourselves.
5. **GitHub Releases API responses** — TLS-protected; we parse JSON
   into a fixed Codable schema (`GitHubRelease` in
   `GitHubReleaseChecker.swift`) that ignores unknown fields, so a
   malicious API response cannot inject extra behaviour beyond the
   fields we read.
6. **Sparkle appcast** (v0.2.0) — TLS + EdDSA-signed payload;
   Sparkle 2 verifies signature before installing. The scaffold in
   `Sources/MeedyaConverter/Updates/` exists for v0.2.0 activation,
   not yet linked into v0.1.0 builds.
7. **AppleScript callers** — local user-process boundary. macOS's
   `NSAppleScript` permission gate must approve, but once approved
   any local process can drive us.
8. **Drag-and-drop sources** — any local app that supplies `URL`-
   capable `NSItemProvider`s.
9. **Cloud provider responses** (S3, GCS, B2) — TLS + provider auth.

## Scanner coverage ledger

Active in CI as of Cycle 12 setup:

| Scanner | Workflow | Trigger | Severity floor |
|---------|----------|---------|-----------------|
| **CodeQL** | `.github/workflows/codeql.yml` | push + PR to main/beta/alpha + weekly Mon 06:00 UTC | security-extended query suite; SARIF uploaded |
| **Dependency Review** | `.github/workflows/dependency-review.yml` | every PR | high-severity + license allow-list |
| **GitHub native** | repo-level — Dependabot alerts + secret scanning + push protection | per-push / continuous | Dependabot security updates auto-enabled |

Gaps (deliberate, with reasoning):

- **No gitleaks CLI scan** — the user's global CLAUDE.md flagged this
  as a should-do but it hasn't yet been wired into a workflow. GitHub
  native secret-scanning + push-protection covers the highest-value
  cases (active provider patterns) but the gitleaks CLI catches
  historical-secret patterns that GitHub's commit-time check
  doesn't. Cycle 13+ candidate.
- **No Snyk / Trivy / Grype** — Dependency Review handles SCA for
  the SPM dependency graph. No container layer to scan.
- **No fuzzing of FFmpeg arg construction** — this is the largest
  attack surface (30 sites) but ffmpeg itself is hardened against
  malicious media. The arg construction is what we own; manual review
  per Cycle 13 will look for command-injection vectors. A future
  property-test fuzzer is a should-do candidate.

## Threat model (Cycle 12 baseline)

Threats ordered by `severity × likelihood`:

### T1. Command injection via crafted filename → ffmpeg arg construction

**Most likely Critical/High** if it lands. A maliciously-named input
file (e.g. `"; rm -rf ~ #.mkv`) flowing into one of the 30 arg-
construction sites where the filename concatenates into a shell
fragment would let a local attacker execute arbitrary code with the
user's privileges.

**Mitigation already in place**: Cycle 7 pre-commit security review
confirmed all `process.arguments = [...]` use array-form (no shell
interpretation). Cycle 13 will spot-check a sample of the 30 sites
to confirm none have regressed to string-interpolated invocation.

### T2. Path traversal / overwrite on output filename

Less severe — a malicious output filename ("`../../etc/passwd`") could
let a user overwrite arbitrary files they own. Limited blast radius
because the user authorised the output path via the save panel.

### T3. Sparkle update tampering (v0.2.0+)

Currently inactive for v0.1.0 (Cycle 3's `GitHubReleaseChecker` does
no automatic install — it only opens the .dmg URL in a browser).
Becomes load-bearing for v0.2.0 when Sparkle activates. Mitigation:
EdDSA signature verification before install (Cycle 6
`sparkle-cloudflare-worker.md` keypair-generation flow). A
compromised Cloudflare Worker without the EdDSA private key cannot
serve a malicious update.

### T4. Cloud-credential exfiltration

OAuth tokens in Keychain. Mitigated by Apple's Keychain item ACL
+ the `kSecAttrService` partitioning. The post-#380 migration removed
plaintext fallbacks. Subsequent SECURE cycles will verify no plaintext
write paths remain.

### T5. Drag-and-drop URL hijack

A malicious app could supply a URL pointer to a file the user didn't
intend to convert. Low impact (user sees the file in the queue
before processing) but worth confirming the post-Cycle-1 fix to
`DropHandler.swift` (URLCollector) doesn't introduce new symbolic-
link following or path-traversal issues.

### T6. AppleScript bridge surface

Once Cycle 2's `.sdef` ships in the bundle (it does now), any local
AppleScript-capable process can drive MeedyaConverter — within
whatever the user granted via macOS's Automation permission gate.
Cycle 13+ will inspect `ScriptingBridge.swift` for: filesystem
operations performed without confirming user intent, command
execution via NSAppleEventDescriptor that bypasses normal sandboxing.

### T7. Active-compromise indicators

**Rule (per autopilot doctrine + global CLAUDE.md)**: if any cycle
surfaces evidence the live system is already compromised — a
live-exploited backdoor, an exfiltration path that appears already
used, signed binaries on Releases that don't match a build the team
authorised — set the loop's `blocked` state to `is:true`, `reason:
"active-compromise indicator"`, **do not auto-fix** (auto-patching
destroys forensic evidence), and surface for incident response.

## Multi-role fixtures (for purple-team)

Test users / contexts that purple-team agents should rotate through
in Cycle 13+:

- **Unprivileged local user** — default macOS user with no admin;
  what most consumers run as.
- **Admin local user** — elevated; covers blast-radius escalation
  paths.
- **AppleScript-only client** — drives the bridge but has no
  GUI access; sees only what the .sdef advertises.
- **Network observer** — passive watcher of outbound traffic;
  verifies what data leaves the device and whether anything
  unexpected appears.

## Findings register

| ID | Severity | Surface | Status | Cycle | Notes |
|----|----------|---------|--------|-------|-------|
| F-001 | N/A (no finding) | T1 — FFmpeg argument construction (15 files, ~30 sites) | swept clean | 13 | Audited every `Process` invocation under `Sources/` that builds an argument list for ffmpeg / ffprobe / cdrecord / growisofs / dovi_tool / hdr10plus_tool / hlg-tools / subtitle_tonemap. **Zero string-interpolation patterns into argument elements** (`grep -rE 'process\.arguments\s*=.*\\\(' Sources/` returns no hits). **Zero `/bin/sh -c` or `/bin/bash -c` invocations.** All call sites use array-form `[String]` arguments throughout. Executable lookups go via `URL(fileURLWithPath: "/usr/bin/env")` with the tool name as the first array element (e.g. `["cdrecord"] + args`); `env` does not interpret shell metacharacters either — it just PATH-resolves the literal name and `execve`s with the remaining args as `argv[]`. The `executable` variable in `BurnSettingsView.swift:516`/`:558` is one of two compile-time literals (`"cdrecord"` / `"growisofs"`) chosen by the user's disc-format selection — not attacker-controllable. **The 2026-06 vidstabdetect filter fix (Cycle 1, commit ae01d3f) is the only historical regression of this class** and is closed. No further work proposed for this threat in v0.1.0. A regression-grep script (`scripts/security-check-ffmpeg-args.sh`) is queued as a should-do for a later POLISH cycle so a future refactor cannot silently re-introduce a string-interpolation pattern. |
| F-002 | Medium | T2 — `ScriptingBridge.swift:127` AppleScript bridge accepted arbitrary `output` string as URL with no validation | fixed | 14 | RED audit found ~20 sites where `URL.appendingPathComponent(component)` is called with a `component` derived (directly or via `URL.lastPathComponent`) from user input. **Most are not directly exploitable**: `URL.lastPathComponent` doesn't expose path separators, and Foundation's filesystem APIs cannot create a file literally named `..`. **The narrow real vector was `ScriptingBridge.swift:127`** — `URL(fileURLWithPath: output)` where `output` came directly from an AppleScript caller as a raw string with no normalisation. A malicious script could pass `"../../../etc/passwd"` and (subject to the user's filesystem permissions) overwrite arbitrary files outside the user's intended output area. **Fix landed in commit on autopilot/2026-06-30**: new `Sources/ConverterEngine/Utilities/PathSanitizer.swift` with two complementary helpers — `PathSanitizer.sanitizeFilenameComponent(_:)` (silently strips `/`, `\`, `..`, NUL, leading whitespace, trailing whitespace+dots from filename components, with `unnamed` placeholder for empty/dot-only results), and `URL.isContained(within:)` extension (string-only `.standardized`-based descendant check, with documented decision to NOT resolve symlinks because macOS's `/private/tmp` ↔ `/tmp` redirection produces inconsistent results between existing and non-existing paths). The ScriptingBridge.encode method now rejects any output URL not contained within the user's home directory, returning a clear `ERROR:` string the AppleScript caller can surface. **Regression coverage**: new `Tests/ConverterEngineTests/PathSanitizerTests.swift` with 15 tests covering empty/dot/separator/traversal inputs, idempotence, the load-bearing "sanitised input cannot escape parent" assertion, and the containment check including the prefix-collision case (`/private/tmp` ≠ `/private/tmp-attack/`). All pass. **POLISH-tier follow-up**: ~17 other `appendingPathComponent` call sites (`MultiOutputView`, `BackgroundRemovalView`, `Intents/ConvertMediaIntent`, etc.) could be defensively migrated to the sanitiser even though they aren't directly exploitable, just to close the door on a future regression where `URL.lastPathComponent` semantics change or someone passes a raw string. Queued for a POLISH cycle, not blocking v0.1.0. |
| F-003 | Low | T3 — `GitHubReleaseChecker.dmgAsset` opened the `browser_download_url` from a release's `.dmg` asset with no host validation, where a future API-response change / community fork / malicious release-edit could redirect the user's browser via `NSWorkspace.shared.open(_:)` in `SettingsView.swift:783` to an attacker URL | fixed | 15 | RED audit of the v0.1.0 update surface confirmed: (a) `releasesEndpoint` enforces HTTPS (`https://api.github.com/repos/.../releases/latest`, hard-coded). (b) `GitHubReleaseChecker.swift` correctly rejects pre-release and draft releases. (c) The User-Agent header carries the running app's version (no identifying info beyond what the GitHub access log would record anyway). **(d) The only structural gap**: `GitHubRelease.dmgAsset` returned the first asset whose filename ended in `.dmg`, with no check that `browser_download_url.host` was on a github-served host. `SettingsView`'s "Download DMG" button at line 783 hands the URL to `NSWorkspace.shared.open(_:)` — a non-github host would redirect the user's browser to wherever the JSON specified. **Sparkle B scaffolding was NOT yet landed** (the originally-proposed `Sources/MeedyaConverter/Updates/` directory does not exist; only the GitHub-Releases-poller from Cycle 3 is active), so the Sparkle EdDSA chain is not yet a concern — that becomes T3's main load-bearing surface in v0.2.0 when Sparkle activates. **Fix landed**: `GitHubRelease.dmgAsset` now requires the asset's host to be `github.com` or `objects.githubusercontent.com` (case-insensitive per RFC 3986). Non-matching hosts cause `dmgAsset` to return `nil`, which the SettingsView already handles by showing the htmlUrl release-page link instead. **Regression coverage**: new `Tests/MeedyaConvertTests/GitHubReleaseCheckerTests.swift` with 6 tests covering both allowlist hosts accepted, attacker-controlled host rejected, case-insensitive host match, and the ordering edge cases (first-acceptable wins; an attacker-host asset appearing before a legitimate one doesn't shadow it). The test target mirrors the `GitHubRelease` struct shape because the MeedyaConverter target is `@main` and can't be linked into the test binary. All pass. **Sparkle B activation gates** (not addressed this cycle, queued as user-side prerequisites for v0.2.0 ship): EdDSA keypair generation, `SPARKLE_ED_PRIVATE_KEY` GitHub secret, `SUFeedURL` + `SUPublicEDKey` baked into Info.plist (load-bearing — these values cannot change for installed copies once shipped), Cloudflare Worker deployment per `docs/distribution/sparkle-cloudflare-worker.md`, DNS for `update.mwbm.io`. These are surfaced in the gate-ledger as `awaiting-user`. |
| F-004 | Medium | T4 — Three Keychain write sites all used accessibility values without the `ThisDeviceOnly` qualifier, making the items eligible for iCloud Keychain sync and Time Machine backup inclusion: (1) `APIKeyManager.swift:690` used `kSecAttrAccessibleAfterFirstUnlock` with a comment incorrectly claiming iCloud isolation; (2) `EmailSettingsView.swift:367` set NO accessibility attribute (defaults to `WhenUnlocked` without `ThisDeviceOnly`); (3) `LicenseKeyValidator.swift:350` used `kSecAttrAccessibleWhenUnlocked` | fixed | 16 | RED audit of T4 (cloud-credential exfiltration) confirmed: (a) `Sources/MeedyaConverter/Views/EmailSettingsView.swift:297-336` SMTP creds are correctly piped via stdin to curl (NOT argv), so they never appear in `ps`/argv. (b) `Sources/ConverterEngine/Cloud/SFTPUploader.swift:253-319` `writeFTPCredentialsConfig` correctly writes to a UUID-named 0600 tempfile with `createFile + posixPermissions: 0o600` BEFORE the credential is written, and re-asserts 0600 after — the file is never world-readable even momentarily. (c) No `UserDefaults.standard.set` call writes a credential field (15 hits, all settings/UX state: theme, language, keyboard shortcuts, analytics-anonymous-id, etc. — none contain api keys, tokens, or passwords). **Three real findings** at the Keychain accessibility layer: the prior values protected the items from being read while the device was locked, but left them eligible to sync via iCloud Keychain to other Macs on the same Apple ID, and to be included in Keychain backups (encrypted, but exfiltratable from a stolen Time Machine archive with the user's password). For per-machine cloud API tokens, SMTP passwords, and licence keys, that is the wrong policy — the user expects each device's credentials to stay on that device. **Fix landed** in commit on autopilot/2026-06-30: all three sites now use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, with inline comments explaining the two protections (gated on currently-unlocked, suppresses iCloud sync + backup inclusion) and pointing back to this finding. **Migration note**: existing Keychain items written before this fix retain their old accessibility until the user next saves a credential through the UI (which triggers the delete-then-add overwrite). A one-shot migration pass on first launch is queued as a POLISH-cycle follow-up; for v0.1.0 users it is a non-issue because they have not yet shipped, and for the rare upgrade case the impact is upper-bounded by the user re-entering credentials normally over time. **No regression tests** because the system Keychain's accessibility semantics cannot be portably unit-tested (it requires a Mac with Apple-ID-attached iCloud and Time Machine to observe the sync/backup behaviour); the existing 21 security-related tests still pass. The fix is anchored by code-review and the inline comments at each site. |
| F-005 | **HIGH** | T4 — `SFTPSettingsView.persistProfiles()` calls `JSONEncoder().encode(savedProfiles)` then `UserDefaults.standard.set(data, forKey: "sftpProfiles")` where each `SFTPServerConfig.authMethod` is an enum with a `.password(String)` case carrying the plaintext SSH password. The encoded JSON — including the plaintext password — lands in `~/Library/Preferences/com.mwbm.MeedyaConverter.plist`, a file that is NOT encrypted, IS included in Time Machine backups, IS readable by any process the user runs (`defaults read com.mwbm.MeedyaConverter sftpProfiles` dumps it), and IS included in iCloud backups if the user has the Desktop+Documents iCloud option on | fixed | 17 | **Fix landed in commit on autopilot/2026-06-30**. (1) **New helper module** `Sources/ConverterEngine/Cloud/SFTPCredentialStore.swift` exposes `save/read/delete(forProfileID:)` against a Keychain `kSecClassGenericPassword` partition at `service = "com.mwbm.MeedyaConverter.sftp"`, `account = <profile UUID>`, with the `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility set by F-004 (so SFTP credentials never sync via iCloud Keychain or appear in Time Machine archives). A `serviceOverride` static is exposed for test hermetics; production callers use the default service. (2) **`SFTPServerConfig` gained an `id: UUID` field** with a backward-compatible Codable decoder that mints a fresh UUID when the legacy `sftpProfiles` JSON lacks the field — this is what makes the migration path addressable. (3) **`SFTPSettingsView.persistProfiles()` now redacts** every `.password(pw)` (where `pw` is non-empty) by writing `pw` to the credential store, then encoding a copy with `.password("")` to UserDefaults — the bytes that touch the plist no longer contain user secrets. **`SFTPSettingsView.loadProfiles()` does two things**: (a) for an already-redacted profile (`.password("")` in JSON), it reads the credential from Keychain and reinjects it for in-memory use; (b) for a *legacy* profile (non-empty `.password(pw)` in JSON), it lifts the plaintext into the Keychain under the freshly-minted UUID, then immediately calls `persistProfiles()` to scrub the plaintext from the plist on the same launch. (4) **`deleteProfile(at:)` now cascades** to `SFTPCredentialStore.delete(forProfileID:)` so a removed profile's credential is wiped instead of orphaned in the Keychain. **Regression tests** in new `Tests/ConverterEngineTests/SFTPCredentialStoreTests.swift` — 12 tests, all passing — cover Keychain save/read/idempotent-overwrite/per-profile-isolation/delete/delete-idempotent/UTF-8-special-chars round-trip, plus the F-005 contract tests: legacy JSON without `id` decodes with a fresh UUID, modern JSON with `id` preserves it, redacted-profile encoding round-trips an empty password string, the encoded JSON bytes do not literally contain the would-be plaintext, and an end-to-end migration flow lifts a synthetic legacy plaintext into Keychain. **Tests use a per-test `serviceOverride` (UUID-suffixed)** so they cannot touch the production Keychain partition; `tearDown` drains everything under the override. **FTPServerConfig was checked**: `FTPServerConfig.password: String` at `Sources/ConverterEngine/Cloud/SFTPUploader.swift:109` IS exposed by the model but is **not currently persisted from any UI** — no FTP settings view writes `ftpProfiles` to `UserDefaults`. So the FTP equivalent of this fix is not load-bearing for v0.1.0. Queued as a POLISH-tier defensive copy if/when an FTP settings UI is added. |
| F-006 | Low | T5 — `FFmpegProbe.parseProbeOutput` and `FFmpegProbe.parseStream` / `parseChapter` stringified arbitrary JSON tag values (`metadata[key] = "\(value)"`, `let title = tags["title"] as? String`) without filtering NUL bytes, ANSI/VT100 escape sequences, or Unicode bidirectional-override codepoints. A crafted media file could embed these into `title` / `artist` / `comment` / per-stream tags / chapter titles; they then flowed unchanged into the SwiftUI metadata panel, the conversion logs, the CLI JSON output, and the AppleScript bridge result strings, allowing terminal forgery / log forgery / Trojan-Source filename swaps | fixed | 18 | RED audit of T5 (malicious-metadata defence). The realistic attacker assumption is "user has imported a crafted media file" — the user has not yet been compromised, but the moment that file's metadata renders inside MeedyaConverter's UI, terminal, log, or AppleScript bridge, embedded control characters become an attack surface. Specifically: NUL bytes terminate C-string filename APIs; ANSI / VT100 escape sequences re-colour text / move the cursor / clear the screen (forgery via log/terminal); other C0 control codes re-position the cursor or delete previously-rendered characters; bidirectional-override codepoints (`U+202A`–`U+202E`, `U+2066`–`U+2069`) flip text rendering direction — the "Trojan Source" attack. **Fix landed**: new `Sources/ConverterEngine/Utilities/MetadataSanitizer.swift` provides a pure `sanitize(_ raw: String) -> String` that removes NUL, ASCII C0 controls (except TAB/LF/CR — kept for legitimate multi-line `comment` / `lyrics` tags), DEL, and all bidirectional-override codepoints. The helper is idempotent and length-neutral for legitimate input. `FFmpegProbe` calls it at four chokepoints: format-level metadata key + value (line ~190), per-stream `language` + `title` (line ~265), and per-chapter `title` + chapter metadata key + value (line ~408). Single-point-of-application means every downstream renderer (SwiftUI metadata panel, AppleScript bridge result, conversion logs, CLI JSON output) is defended without per-callsite knowledge of the rule. **Regression coverage**: new `Tests/ConverterEngineTests/MetadataSanitizerTests.swift` — 20 tests, all passing — covering empty / plain ASCII / Unicode BMP / emoji preservation (legitimate input is untouched); NUL stripping (single + multiple); C0 control stripping (BEL, BS, VT, FF, ESC, DEL) with TAB/LF/CR/CRLF preserved; bidirectional-override stripping (single `U+202E` RLO + the full set of nine codepoints); idempotence; and a combined attacker-payload test that exercises NUL + ANSI + bidi simultaneously. |
| F-007 | Medium | T5 — `FFmpegProbe.runFFprobe` calls `process.waitUntilExit()` with no watchdog timeout; a malicious media file that triggers a ffprobe hang or stream-stall would block the calling Task indefinitely without the user being able to cancel from the UI | fixed | 19 | **Fix landed in commit on autopilot/2026-06-30**. `FFmpegProbe` now exposes two configurable parameters (`timeoutSeconds: Double = 60.0`, `byteCap: Int = 10 MB`) via the public init — defaults are tight enough to bound a real attack while being three orders of magnitude above what a normal probe emits. The `runFFprobe` body restructured to three layered protections: (1) **Watchdog timer** — `DispatchSourceTimer` armed at `timeoutSeconds` calls `process.terminate()` (SIGTERM) and sets a timeout flag. (2) **SIGKILL escalation timer** — a second `DispatchSourceTimer` armed at `timeoutSeconds + 3.0s` invokes the POSIX `kill(pid, SIGKILL)` syscall directly (Foundation's `Process` API doesn't expose SIGKILL; SIGKILL cannot be trapped or ignored, so the kernel reaps the process immediately and `waitUntilExit()` returns). This is what makes the watchdog actually reliable against a `trap '' TERM` subprocess. (3) **Independent pipe drainers** — stdout and stderr are each drained by a background DispatchQueue task in chunks via `FileHandle.availableData`, appending into a lock-protected shared `Data`. On exceeding `byteCap` per stream, the drainer terminates the process and records which stream tripped first. This both prevents OOM from a stderr flood AND avoids the classic Process pipe-buffer deadlock (without an independent stderr drainer a 64 KB stderr flood blocks ffprobe's next write, indirectly causing the watchdog to fire). All shared state is in a single `ProbeRunState` class protected by `NSLock.withLock`. New `FFmpegProbeError.timeout(seconds:)` + `.bufferLimitExceeded(stream:byteCap:)` cases give callers a distinguishable signal. Result-classification order is buffer-cap-first then timeout-second (buffer cap is the more specific signal when both fire). **Regression coverage**: new `Tests/ConverterEngineTests/FFmpegProbeWatchdogTests.swift` — 10 tests, all passing — covering happy path (trivial echo script returns stdout; no false-positive timeout), watchdog timeout (a `trap '' TERM; sleep 30` script with a 1s timeout terminates within ~7s wall-clock vs. the full 30s before this fix), buffer cap (stdout flood + stderr flood both trip the configured cap and identify the correct stream), preserved error classification (non-zero exit → `.probeFailed`; empty stdout → `.invalidOutput`; missing binary → `.ffprobeNotAvailable`), and backward compatibility (`FFmpegProbe(ffprobePath:)` without explicit timeout/byteCap still compiles for the four existing callers). Wall-clock budgets in the timeout test are deliberately loose (7s ceiling for a 1s+3s escalation) to absorb CI jitter; the contract being verified is "escalates promptly under SIGTERM trapping", not exact timing. |

| F-008 | Low | T6 — `ScriptingBridge` AppleScript surface: input arguments to `encode` / `probe` had no length cap (so a malicious script could pass a multi-megabyte profile name that would flow into the error path); reply strings interpolated user-controlled values (`profile`, `file`, `output`, `error.localizedDescription`) into `ERROR:` lines without sanitisation, so the same NUL / ANSI-VT100 / bidi-override forgery vectors that F-006 closed on FFmpegProbe output were still open via the bridge's reply channel; `queueStatus` returned `inputURL.lastPathComponent` unsanitised. Parallel issue in `ConvertMediaIntent.swift` (Shortcuts surface): `inputFile.filename` was appended to a temp directory URL via `appendingPathComponent` without going through PathSanitizer | fixed | 20 | RED audit of every `@objc` method on `ScriptingBridge` (`encode`, `probe`, `listProfiles`, `queueStatus`, `version`), the `.sdef` command declarations, and the parallel `ConvertMediaIntent.perform()` Shortcuts entry point. **Findings**: (1) no length cap on `encode`'s `file` / `profile` / `output` or `probe`'s `file`; (2) error replies interpolated user-controlled strings unsanitised — VT100 escape sequences in a profile name (`ProfileX\u{001B}[31mFAKE-ERROR\u{001B}[0m`) would forge fake red-text errors in the AppleScript caller's log; (3) bidirectional-override codepoints in a filename would survive the bridge reply; (4) `queueStatus`'s `fileName` field copied `lastPathComponent` raw; (5) `ConvertMediaIntent` used `inputFile.filename` directly in `appendingPathComponent`, vulnerable to a future Shortcuts host (or a non-Apple intent caller) that supplies a `..`-containing filename. **Severity Low** because AppleScript / Shortcuts automation already requires the user to grant Automation permission to the calling app, so the realistic attacker is a malicious automation script the user has explicitly authorised — they cannot reach this surface from a cold web exploit. **Fix landed**: new fileprivate helpers on `ScriptingBridge`: `maxArgumentLength = 4096`, `formatError(_:)` (prepends `ERROR: ` and runs the message through `MetadataSanitizer.sanitize`), `enforceLengthCap(_:label:)` (returns nil under the cap, returns a sanitised ERROR reply over it). Helpers marked `nonisolated` so they can be called from `Task.detached` blocks (e.g. inside `probe`). Every `@objc` method's argument validation now starts with length-cap checks; every `return "ERROR: ..."` site goes through `formatError`. `queueStatus`'s `fileName` value runs through `MetadataSanitizer.sanitize`. `ConvertMediaIntent.perform()` now sanitises `inputFile.filename` through `PathSanitizer.sanitizeFilenameComponent` before appending to the temp directory URL. **Regression coverage**: new `Tests/MeedyaConvertTests/ScriptingBridgeF008Tests.swift` — 9 tests, all passing — covering the `formatError` contract (ERROR prefix + control-code stripping + bidi-override stripping + NUL stripping) and the `enforceLengthCap` contract (under-limit nil, at-limit nil, over-limit ERROR reply, sanitised label interpolation), plus a kitchen-sink "combined attacker payload" assertion. The test target mirrors the helper shape (rather than @testable importing the @main MeedyaConverter target which can't link into a test binary) so the contract is anchored even though we cannot exercise the real `@objc` dispatch path without a full app instance. |

## Active compromise log

(empty — never been triggered; would set the autopilot to BLOCKED
and stop scheduling if it did)

## Phase 0 exit

Phase 0 is doc-only — no behavioural changes, no commits beyond this
file. The next SECURE iteration (Cycle 13) begins the
red→validate→blue→verify purple-team rotation against the threats
above, in roughly the order listed (T1 first because it has the
largest blast radius if found real).
