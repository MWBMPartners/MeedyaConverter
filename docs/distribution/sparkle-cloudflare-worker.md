<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Sparkle B + Cloudflare Worker — activation guide

This guide walks the maintainer through standing up the **Sparkle 2
auto-update** path for the v0.2.0 Direct build, including the
`update.mwbm.io` Cloudflare Worker that proxies GitHub Releases as
a stable signed appcast feed.

**Scope**: this is for the **Direct distribution** (`Ltd.MWBMpartners.MeedyaConverter`)
build only. The App Store Lite build uses the Mac App Store updates
mechanism and never loads Sparkle.

**Status at time of writing**:

- ✅ Sparkle SPM dependency wired into `Package.swift` (commit `ec28625`),
  gated on the `DIRECT=1` environment flag.
- ✅ `AppUpdateChecker` already dispatches `.sparkle` when the framework
  is linked + the bundle is Direct.
- ⏳ Cloudflare Worker code, EdDSA keypair, `update.mwbm.io` DNS, and
  release.yml signing wiring — this guide.

## Architecture

```text
                 ┌──────────────────────────────────────┐
   user's app    │  MeedyaConverter (Direct, DIRECT=1)  │
   ────────────► │       SPUUpdater(SUFeedURL: ...) ────┼──┐
                 └──────────────────────────────────────┘  │
                                                           │  HTTPS
                                                           ▼
                              ┌────────────────────────────────────┐
                              │ https://update.mwbm.io/             │
                              │   meedyaconverter/appcast.xml       │
                              │                                     │
                              │   Cloudflare Worker                 │
                              │   ─────────────────                 │
                              │   1. Fetch latest non-prerelease    │
                              │      GitHub release                 │
                              │   2. Emit RSS appcast with .dmg     │
                              │      enclosure + sparkle:edSignature│
                              │   3. Cache 5 minutes                │
                              └────────────────┬───────────────────┘
                                               │  GitHub Releases API
                                               ▼
                          ┌────────────────────────────────────────┐
                          │  github.com/MWBMPartners/MeedyaConverter│
                          │    /releases/latest                    │
                          │                                        │
                          │  Assets:                               │
                          │    MeedyaConverter-v0.2.0.dmg          │
                          │    MeedyaConverter-v0.2.0.dmg.sig (EdDSA)│
                          │    appcast.xml (optional, also published) │
                          └────────────────────────────────────────┘
```

The Worker exists for a single load-bearing reason: **the `SUFeedURL`
key in the app's Info.plist is baked into the signed binary and cannot
be changed for installed copies later**. So we must point it at a
domain we control (`update.mwbm.io`) from day one — not at
`api.github.com` or `raw.githubusercontent.com`, even though those
would technically work. If GitHub ever changes their URL structure or
we need to migrate hosting, the Worker lets us redirect transparently.

## 1. Generate the EdDSA keypair

Sparkle 2 requires every release to be signed with an EdDSA (Ed25519)
private key; the app verifies signatures with the matching public key
baked into Info.plist as `SUPublicEDKey`.

1. Download or check out the Sparkle source tree (any tag from `2.6.0`
   onwards is fine for the key-gen tool):

   ```bash
   git clone --depth 1 --branch 2.6.0 https://github.com/sparkle-project/Sparkle.git /tmp/sparkle
   cd /tmp/sparkle
   ```

2. Build the `generate_keys` tool:

   ```bash
   make release
   ```

   (Or follow whatever the Sparkle README says for the version you
   checked out — the tool moves around occasionally.)

3. Generate the keypair:

   ```bash
   ./bin/generate_keys
   ```

   This produces:
   - A **public key** (~44 base64 chars), printed to stdout.
   - A **private key**, stored in your macOS Keychain under the
     account `ed25519` and printed to stdout for one-time capture.

4. **Capture both immediately**:
   - **Public key**: copy and paste into the project's secrets manager
     (1Password / Bitwarden / Apple Notes encrypted folder) AND into
     the `Info.plist`'s `SUPublicEDKey` (step 3 below).
   - **Private key**: paste into your secrets manager AND into the
     `SPARKLE_ED_PRIVATE_KEY` GitHub Actions secret (step 2).

   The private key never leaves the maintainer's secrets store and the
   GitHub secret. **It is NEVER committed to the repository.**

5. Delete the Keychain entry once you've stored the private key
   securely in your manager — leaving it in Keychain means anyone
   with access to your unlocked Mac could extract it.

   ```bash
   security delete-generic-password -a ed25519 -s "https://sparkle-project.org"
   ```

## 2. Store `SPARKLE_ED_PRIVATE_KEY` as a GitHub secret

Via **Repository → Settings → Secrets and variables → Actions → New repository secret**:

- **Name**: `SPARKLE_ED_PRIVATE_KEY`
- **Value**: the full private key (base64 + any line breaks; usually a
  single line)
- Click **Add secret**.

The `release.yml` `sign_update` step (added in a follow-up cycle) will
use this to sign each release's `.dmg`.

## 3. Configure the app's Info.plist

Edit `Sources/MeedyaConverter/Resources/Info.plist` and add (or
uncomment, if a future cycle stubs these):

```xml
<key>SUFeedURL</key>
<string>https://update.mwbm.io/meedyaconverter/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>PASTE_YOUR_BASE64_PUBLIC_KEY_HERE</string>

<key>SUEnableAutomaticChecks</key>
<true/>

<key>SUScheduledCheckInterval</key>
<integer>86400</integer>

<key>SUAllowsAutomaticUpdates</key>
<false/>
```

The last two are conservative defaults: check once per day, but never
install without explicit user consent.

**Once the Info.plist values are committed and a release is signed
with the matching `release.yml`, the values cannot change for already-
installed copies.** Re-check the public key and the feed URL before
the first signed `v0.2.0` cuts.

## 4. Stand up the Cloudflare Worker

The Worker code lives under `infra/cloudflare-worker/` (scaffolded in
a future cycle). Until then, this is the deployment process:

### 4a. Cloudflare API token

1. Sign in at <https://dash.cloudflare.com/profile/api-tokens>.
2. Click **Create Token** → use the **"Edit Cloudflare Workers"** template.
3. Restrict the **Account Resources** to the MWBM Partners Ltd account
   (`e56a7dc0eaf24a365831e47388641a36`).
4. **Account Settings: Read** + **Workers Scripts: Edit** + **Workers
   Routes: Edit** is the minimum scope.
5. Generate, copy the token.
6. In the GitHub web UI, add as repo secret `CLOUDFLARE_API_TOKEN`.

### 4b. Worker deployment

```bash
cd infra/cloudflare-worker
npm install
npx wrangler login        # one-time, or use CLOUDFLARE_API_TOKEN env var
npx wrangler deploy
```

The `wrangler.toml` in the directory pins:

- `name = "meedyaconverter-appcast"`
- `account_id = "e56a7dc0eaf24a365831e47388641a36"`  (MWBM Partners Ltd)
- `compatibility_date = "2026-05-01"` (or later)

### 4c. DNS for `update.mwbm.io`

1. In the Cloudflare dashboard for `mwbm.io` → **DNS** → **Records** → **Add record**:
   - Type: `CNAME`
   - Name: `update`
   - Target: any of the Workers placeholder records will do; the
     Workers route binding (next step) is what actually serves the
     request.
   - Proxy status: **Proxied** (orange cloud)
   - TTL: Auto

2. **Workers Routes** → **Add route**:
   - Zone: `mwbm.io`
   - Route: `update.mwbm.io/meedyaconverter/*`
   - Worker: `meedyaconverter-appcast`

### 4d. Verify the Worker

```bash
curl -i https://update.mwbm.io/meedyaconverter/appcast.xml
```

Should return:

- HTTP 200
- `Content-Type: application/xml; charset=utf-8`
- A valid `<rss>` document with at least one `<item>` describing the
  latest non-prerelease GitHub release, including a `<enclosure>` tag
  with the `.dmg` URL and a `sparkle:edSignature` attribute.

If the response is HTTP 502 with body `Upstream GitHub API unreachable`,
the Worker is up but GitHub is down or rate-limited; retry in a
moment.

## 5. Wire `sign_update` into release.yml

Once the keypair is generated and the secret is set, the `release.yml`
needs to sign each DMG and upload the signature as a release asset.
This is added in a follow-up cycle; for reference the rough shape:

```yaml
- name: Sign the DMG with Sparkle's EdDSA key
  env:
    SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
  run: |
    # sign_update is bundled with Sparkle 2.6+; install via Homebrew
    # or vendor the binary into the runner
    brew install --cask sparkle
    sig=$(echo -n "$SPARKLE_ED_PRIVATE_KEY" | \
          /Applications/Sparkle.app/Contents/MacOS/sign_update \
          "$DMG_PATH" -p /dev/stdin)
    echo "$sig" > "${DMG_PATH}.sig"

- name: Upload DMG + signature to GitHub Release
  run: |
    gh release upload "$TAG" "$DMG_PATH" "${DMG_PATH}.sig"
```

The Worker reads `${DMG_PATH}.sig` (or the `.dmg.signature` asset, in
some Sparkle conventions) and inlines the value as the
`sparkle:edSignature` attribute on the enclosure.

## 6. Activate Sparkle in the DIRECT build

The release pipeline must set `DIRECT=1` so `swift build` resolves
the Sparkle SPM dependency. Add to the `release.yml` build step:

```yaml
- name: Build release artifact (DIRECT)
  env:
    DIRECT: "1"
  run: |
    swift build --configuration release --product MeedyaConverter
```

The `Package.swift` is already wired to gate the Sparkle dependency
on this flag (commit `ec28625`); `AppUpdateChecker` already dispatches
`.sparkle` when both the framework is linked AND the bundle ID is
Direct (commit `41f4994`).

## 7. End-to-end test

1. Cut a test tag — e.g. `v0.2.0-rc.1`.
2. Confirm `release.yml` produces a signed DMG with an accompanying
   `.dmg.sig` file uploaded to the GitHub Release.
3. Wait ≤ 5 min for the Worker cache to refresh.
4. Open the previously-installed app (e.g. v0.1.0 or v0.2.0-rc.0).
5. **Settings → Updates → Check for Updates** — should show
   "Update available: v0.2.0-rc.1" and offer to install.
6. Click **Install Update**. Sparkle verifies the EdDSA signature
   before installing; a mismatched / unsigned binary is rejected.

If any step fails, check the autopilot's standing task #3 (lint loop)
and #4 (security loop) outputs for that release tag's run.

## Rotating the EdDSA keypair

You only need to rotate if you suspect the private key has been
compromised. Rotation forces every installed user to manually re-
download the next release (Sparkle refuses to install a binary
signed with a key that doesn't match the one in their installed
app's Info.plist).

When in doubt: don't rotate unless you must. If you must:

1. Generate a new keypair (step 1).
2. Update `SPARKLE_ED_PRIVATE_KEY` GitHub secret (step 2).
3. Bake the new public key into `Info.plist` `SUPublicEDKey`.
4. Cut a new release.
5. Communicate to existing users via the GitHub Release page that
   they'll need to download the new DMG manually (their in-app
   updater will not be able to verify the new release).

## References

- Sparkle docs: <https://sparkle-project.org/documentation/>
- Sparkle 2 publishing checklist: <https://sparkle-project.org/documentation/publishing/>
- Cloudflare Workers docs: <https://developers.cloudflare.com/workers/>
- `wrangler` CLI: <https://developers.cloudflare.com/workers/wrangler/>
- The release pipeline this guide configures: `.github/workflows/release.yml`
- The Package.swift Sparkle gate: see commit `ec28625`
- The runtime dispatcher: `Sources/MeedyaConverter/Services/AppUpdateChecker.swift`
  + `Sources/MeedyaConverter/Services/GitHubReleaseChecker.swift`
  (Sparkle Option A / GitHub-Releases-poller fallback for v0.1.0)
- Tracking issues: #416 (update.mwbm.io endpoint), #428 (release umbrella)
