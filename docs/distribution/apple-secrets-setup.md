<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Apple Developer secrets — setup guide for the Direct release pipeline

This guide walks the project maintainer through populating the six
`APPLE_*` GitHub Actions secrets that `.github/workflows/release.yml`
requires for the **Direct distribution** signed-and-notarised DMG path.

The procedure uses the **GitHub web UI** throughout — `gh secret set`
is deliberately avoided so secret values never enter shell history or
clipboard for longer than necessary.

## Before you start

You'll need:

- **Apple Developer Program** membership for MWBM Partners Ltd (this is
  the paid programme; not the free developer account).
- **macOS** with the Keychain Access app — used to import the cert and
  export the .p12.
- **Admin access** to <https://github.com/MWBMPartners/MeedyaConverter>.
  Org-level secret access requires org-admin permissions.

The release pipeline's fail-fast precheck job (added in commit
`5634d28`) will refuse to run any signing step if any of these are
empty or if `APPLE_SIGNING_IDENTITY` doesn't contain the correct cert
family, so you'll get a clear error if anything is misconfigured.

## The six secrets

Set each one via:
**Repository → Settings → Secrets and variables → Actions → New repository secret**

| # | Secret name | What it is |
|---|-------------|-----|
| 1 | `APPLE_CERTIFICATE` | Base64-encoded `.p12` export of the Developer ID Application cert + private key |
| 2 | `APPLE_CERTIFICATE_PASSWORD` | The password you set when exporting the .p12 |
| 3 | `APPLE_SIGNING_IDENTITY` | Literal common-name string from the cert — must contain `Developer ID Application` |
| 4 | `APPLE_ID` | Apple ID email used for App Store Connect (notarisation needs this) |
| 5 | `APPLE_PASSWORD` | App-specific password generated for `notarytool` |
| 6 | `APPLE_TEAM_ID` | 10-character team identifier (`XXXXXXXXXX`) |

### 1. `APPLE_CERTIFICATE`

1. Sign in at <https://developer.apple.com/account/>.
2. **Certificates, Identifiers & Profiles** → **Certificates** → **+**.
3. Choose **Developer ID Application**. Follow the on-screen
   instructions to generate a Certificate Signing Request (CSR) in
   Keychain Access (`Keychain Access → Certificate Assistant → Request
   a Certificate from a Certificate Authority`), upload it, and
   download the resulting `.cer`.
4. Double-click the downloaded `.cer` to import it into your
   **login** keychain. It should now appear as **"Developer ID
   Application: MWBM Partners Ltd (TEAMID)"** with a disclosure
   triangle that reveals the matching private key.
5. In Keychain Access, **select both the cert and its private key**,
   then `File → Export Items…` → save as `meedyaconverter.p12` and
   set a strong export password (you'll need it for secret 2).
6. Base64-encode the .p12 in Terminal:

   ```bash
   base64 -i meedyaconverter.p12 | pbcopy
   ```

   That copies the base64 to your clipboard.

7. In the GitHub web UI:
   - **Name**: `APPLE_CERTIFICATE`
   - **Value**: paste from clipboard
   - Click **Add secret**.
8. Securely delete the local `meedyaconverter.p12` once GitHub has
   stored the secret (the base64 in GitHub is the authoritative
   copy). The .cer can stay imported in your Keychain for local
   signing.

### 2. `APPLE_CERTIFICATE_PASSWORD`

The password you set when exporting the .p12 in step 5 above.

- **Name**: `APPLE_CERTIFICATE_PASSWORD`
- **Value**: that password
- Click **Add secret**.

### 3. `APPLE_SIGNING_IDENTITY`

The literal cert common-name string. Find the exact value with:

```bash
security find-identity -v -p codesigning
```

Look for the line containing `Developer ID Application`. The string
between the quotes is what you paste — typically formatted as
`Developer ID Application: MWBM Partners Ltd (XXXXXXXXXX)` where
`XXXXXXXXXX` is the 10-character team ID.

- **Name**: `APPLE_SIGNING_IDENTITY`
- **Value**: the full quoted string (without surrounding quotes)
- Click **Add secret**.

**The precheck job asserts this contains the literal substring
`Developer ID Application`** — if you paste the App Distribution
(App Store) or Mac Installer cert here by mistake, the release will
fail in ~1 ubuntu-minute rather than ~30 macos-minutes deep into
notarisation.

### 4. `APPLE_ID`

Your Apple ID email — the one signed in at developer.apple.com.

- **Name**: `APPLE_ID`
- **Value**: e.g. `lance@mwmail.me`
- Click **Add secret**.

### 5. `APPLE_PASSWORD`

A **per-app-specific password**, NOT your Apple ID password.

1. Sign in at <https://appleid.apple.com/account/manage>.
2. **Sign-In and Security** → **App-Specific Passwords** → **+** (or
   "Generate Password" — wording varies by Apple ID region).
3. Label it something like `MeedyaConverter Direct release notarytool`.
4. Apple generates a `xxxx-xxxx-xxxx-xxxx` string. Copy it now —
   Apple won't show it again.
5. In the GitHub web UI:
   - **Name**: `APPLE_PASSWORD`
   - **Value**: paste the `xxxx-xxxx-xxxx-xxxx` string
   - Click **Add secret**.

**Rotate** this app-specific password whenever a maintainer leaves
the team or you suspect compromise. Revoking it at appleid.apple.com
invalidates it immediately; regenerate and update the secret to
restore the workflow.

### 6. `APPLE_TEAM_ID`

The 10-character team identifier.

1. Sign in at <https://developer.apple.com/account/>.
2. **Membership** → look for **Team ID** (top of the page).
3. Copy the 10-character alphanumeric string.

- **Name**: `APPLE_TEAM_ID`
- **Value**: paste the 10-character ID
- Click **Add secret**.

## Verification

After all six secrets are set, run a dry-run of the release pipeline
to confirm the precheck passes:

1. Go to **Actions** → **Production Release** → **Run workflow**.
2. Pick the `autopilot/2026-06-30` (or whichever release-ready
   branch).
3. Watch the **precheck-secrets** job. All six asserts should print:

   ```text
     ✓ APPLE_CERTIFICATE is populated
     ✓ APPLE_CERTIFICATE_PASSWORD is populated
     ✓ APPLE_SIGNING_IDENTITY is populated
     ✓ APPLE_ID is populated
     ✓ APPLE_PASSWORD is populated
     ✓ APPLE_TEAM_ID is populated
     ✓ APPLE_SIGNING_IDENTITY contains 'Developer ID Application'

   All Apple-secrets prechecks passed. Release job will proceed.
   ```

If any line shows `::error::`, fix that secret and re-run.

> **Note**: the production-release workflow only fires on `v*` tag
> pushes, not on `workflow_dispatch` by default. To dry-run without
> cutting a real tag, see the "End-to-end dry-run" entry in
> issue #428.

## Optional: alternative auth via App Store Connect API key

If you prefer `notarytool` to use an ASC API key instead of the
Apple ID + app-specific password pair (recommended for unattended
automation; doesn't expire on Apple ID password change), see the
testflight.yml workflow which already wires the equivalent
`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_API_KEY` secrets. The release
pipeline can be migrated to the same auth model in a follow-up PR
— see the should-do list under issue #428.

## Why no `gh secret set`?

The maintainer's standing preference is to use the GitHub web UI for
secret entry rather than `gh secret set`. The reasons:

1. **No shell history**: the value never enters the local terminal's
   command history, even temporarily.
2. **Visual confirmation**: the GitHub UI shows a green "Secret added"
   toast confirming the value was stored, with no ambiguity about
   whether the command succeeded.
3. **Cross-device consistency**: the web UI is the same on every
   machine; the gh CLI's behaviour can drift between hosts.

If the team's preference changes later, the equivalent CLI for each
secret is in the standing-task notes — none of the secret values ever
need to enter a Bash command line, so the CLI route would also use
`gh secret set FOO` (no `--body`) which prompts for the value
interactively and reads from stdin.
