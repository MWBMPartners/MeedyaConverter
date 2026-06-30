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

(empty at Phase 0 completion — purple-team Cycle 13+ populates)

| ID | Severity | Surface | Status | Cycle | Notes |
|----|----------|---------|--------|-------|-------|
| _none yet_ | — | — | — | — | — |

## Active compromise log

(empty — never been triggered; would set the autopilot to BLOCKED
and stop scheduling if it did)

## Phase 0 exit

Phase 0 is doc-only — no behavioural changes, no commits beyond this
file. The next SECURE iteration (Cycle 13) begins the
red→validate→blue→verify purple-team rotation against the threats
above, in roughly the order listed (T1 first because it has the
largest blast radius if found real).
