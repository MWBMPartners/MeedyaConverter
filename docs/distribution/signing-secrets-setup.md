<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# GitHub signing & notarization secrets — setup guide (Direct distribution)

> **STATUS (verified 2026-09-02): already set up.** All six required `APPLE_*`
> secrets exist as **organization** secrets on `MWBMPartners` and are accessible
> to this repository (they appear under "Organization secrets" on the repo's
> Actions secrets page, which GitHub only shows when the repo is within the
> secret's access policy). So `release.yml` will resolve them and **you do not
> need to add any repository secrets.** The org also holds `ASC_API_KEY` /
> `ASC_ISSUER_ID` / `ASC_KEY_ID` (an App Store Connect API key — a more robust
> notarization path we could switch to later; release.yml uses the Apple-ID
> path today). The steps below are a **reference for rotating/renewing** these
> credentials, not initial setup. The only value-level risks left (an expired
> Developer ID cert or a revoked app-specific password) surface at the actual
> sign/notarize step on the first tagged run.

`release.yml` builds, **Developer ID-signs, notarizes, and staples** the Direct
`.app` + DMG entirely on a GitHub-hosted macOS runner — **no local machine is
needed**. It only requires six secrets. Until all six are present (and the cert
is a *Developer ID Application* cert), a precheck job fails the run before any
macOS minute or signing step.

## Yes — GitHub does the whole build

The macOS runner ships Xcode + `codesign` + `notarytool`. On a `v*` tag push the
workflow: builds a universal binary → assembles the `.app` → imports your cert
into a temporary keychain → signs (hardened runtime) → notarizes via
`notarytool` → staples → builds + signs + notarizes the DMG → publishes a
GitHub Release. You supply the credentials as secrets; Apple's servers do the
notarization; the runner does everything else.

## The six secrets

| Secret | What it is |
| --- | --- |
| `APPLE_CERTIFICATE` | base64 of your **Developer ID Application** cert exported as a `.p12` (cert **+** private key) |
| `APPLE_CERTIFICATE_PASSWORD` | the password you set when exporting that `.p12` |
| `APPLE_SIGNING_IDENTITY` | the cert's full name, e.g. `Developer ID Application: MWBM Partners Ltd (ABCDE12345)` |
| `APPLE_ID` | the Apple ID email of an account in the team (Account Holder / Admin / App Manager) |
| `APPLE_PASSWORD` | an **app-specific password** for that Apple ID (NOT the account password) |
| `APPLE_TEAM_ID` | your 10-character Apple **Team ID** |

### Repository vs organization secrets

GitHub resolves `${{ secrets.NAME }}` from **both** the repo's own secrets **and
any organization secrets the repo has access to** — same name, no code change.
So:

- If `APPLE_ID`, `APPLE_TEAM_ID` (and possibly `APPLE_PASSWORD`) already exist as
  **org secrets** granted to this repo, you're done for those — **do not
  duplicate them at repo level**.
- The **certificate** secrets (`APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`)
  and `APPLE_SIGNING_IDENTITY` are usually per-repo (tied to the specific cert
  you use for this app), so add those as **Repository secrets** unless you keep a
  shared org Developer ID cert.
- Check what's already inherited: **repo → Settings → Secrets and variables →
  Actions** lists "Organization secrets" (inherited) separately from "Repository
  secrets". Only add what's missing.

## Step 1 — Team ID (`APPLE_TEAM_ID`)

1. Sign in at <https://developer.apple.com/account>.
2. Click **Membership details**. The **Team ID** is the 10-character code (e.g.
   `ABCDE12345`). Copy it.

## Step 2 — Developer ID Application certificate (→ `.p12`)

You need a **Developer ID Application** cert (the family used for
outside-the-App-Store notarized apps — *not* "Apple Distribution" or "Mac
Installer"). Only the **Account Holder** can create Developer ID certs.

**Easiest (Xcode on a Mac):**
1. Xcode → **Settings → Accounts** → select your Apple ID → **Manage
   Certificates…**
2. Click **+** → **Developer ID Application** → it's created and installed into
   your login keychain.

**Or via the portal + CSR:**
1. On a Mac open **Keychain Access → Certificate Assistant → Request a
   Certificate From a Certificate Authority**; enter your email, choose **Saved
   to disk**, save the `.certSigningRequest`.
2. <https://developer.apple.com/account/resources/certificates> → **+** →
   **Developer ID Application** → upload the CSR → **Download** the `.cer`.
3. Double-click the `.cer` to import it into Keychain Access.

**Export the `.p12` (cert + private key):**
1. In **Keychain Access → My Certificates**, find **Developer ID Application:
   … (TEAMID)**, expand it so you can see the private key underneath.
2. Select **both** the certificate and its private key → right-click →
   **Export 2 items…** → **Personal Information Exchange (.p12)**.
3. Set a strong password → this becomes **`APPLE_CERTIFICATE_PASSWORD`**.
4. Base64-encode it (macOS):
   ```bash
   base64 -i DeveloperID_Application.p12 | pbcopy
   ```
   The clipboard now holds **`APPLE_CERTIFICATE`**.

**Get the exact identity string (`APPLE_SIGNING_IDENTITY`):**
```bash
security find-identity -v -p codesigning
```
Copy the quoted name verbatim, e.g. `Developer ID Application: MWBM Partners Ltd (ABCDE12345)`.
It **must** contain the literal substring `Developer ID Application` — the
precheck rejects any other cert family.

## Step 3 — Apple ID + app-specific password (notarization)

`notarytool` authenticates with your Apple ID + an **app-specific password**
(never your real password):
1. Sign in at <https://appleid.apple.com> → **Sign-In and Security → App-Specific
   Passwords** → **+** → label it e.g. `MeedyaConverter notarization` →
   **Create**.
2. Copy the generated `xxxx-xxxx-xxxx-xxxx` value → **`APPLE_PASSWORD`**.
3. **`APPLE_ID`** = the Apple ID email of that account. It must be in the same
   team as the Team ID and have accepted the current Apple Developer agreements.

> Alternative (more robust for CI, future hardening): an **App Store Connect API
> key** (Issuer ID + Key ID + `.p8`). `release.yml` currently uses the Apple
> ID + app-specific-password path, so stick with that for now; switching to an
> API key is a small workflow change we can do later.

## Step 4 — Add the secrets to GitHub

Repo → **Settings → Secrets and variables → Actions → New repository secret**,
for each of the six (skip any already inherited from the org):

- `APPLE_CERTIFICATE` — paste the base64 blob from Step 2.
- `APPLE_CERTIFICATE_PASSWORD` — the `.p12` password.
- `APPLE_SIGNING_IDENTITY` — the full `Developer ID Application: … (TEAMID)` string.
- `APPLE_ID` — the Apple ID email.
- `APPLE_PASSWORD` — the app-specific password.
- `APPLE_TEAM_ID` — the 10-char Team ID.

## Step 5 — Verify

You can't see secret values after saving, but the workflow's **precheck job**
(runs first, on Ubuntu, in ~seconds) asserts all six are set and that
`APPLE_SIGNING_IDENTITY` is a Developer ID Application cert. If a secret is
missing or the wrong cert family, it fails fast with an actionable message
before any signing runs.

A wrong *value* (expired cert, revoked app-specific password) only fails later,
at the import/notarize step — watch the first run to green and re-run with
`gh run rerun <id>` after any fix (there is no `workflow_dispatch`; a re-tag or
`gh run rerun` re-triggers).

## Notes

- Notarization for a brand-new team's first submission can take longer than
  usual; the timeouts were raised for this.
- The CLI tarball is signed but **not** notarized in this build (disclosed in the
  release notes); notarizing it is a small follow-up once the first signed run
  succeeds.
