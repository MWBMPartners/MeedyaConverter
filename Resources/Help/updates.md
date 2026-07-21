# Updates

How MeedyaConverter checks for and applies updates depends on how you
installed it.

## Direct download (v0.1.0)

If you installed MeedyaConverter from a `.dmg` file downloaded from
[GitHub Releases](https://github.com/MWBMPartners/MeedyaConverter/releases)
(or from `mwmail.me`), you are running the **Direct distribution build**.

For v0.1.0 the Direct build uses a **manual update flow**:

1. Open **Settings → Updates**.
2. Click **Check GitHub for Updates**. MeedyaConverter polls the
   GitHub Releases API for the latest published release and compares
   it with the version you are running.
3. If a newer version is available, the page shows a banner with
   **Download DMG** and **View Release Notes** buttons. Both open in
   your browser.
4. Download the new DMG, mount it, and drag MeedyaConverter to your
   Applications folder over the existing copy. macOS will keep your
   user settings (they live in `~/Library/Application Support/` and
   `~/Library/Preferences/`, not in the app bundle).

The check is cached for one hour so repeated clicks won't hammer the
GitHub API.

### Verifying the downloaded DMG

Every Direct DMG is signed with a Developer ID Application certificate
and notarised by Apple. After downloading, you can verify it from
Terminal:

```
spctl --assess --type execute --verbose=4 \
    /Volumes/MeedyaConverter/MeedyaConverter.app
```

A trustworthy DMG returns `accepted source=Notarized Developer ID`. If
you see anything else, **do not install it** — re-download from
[GitHub Releases](https://github.com/MWBMPartners/MeedyaConverter/releases)
or contact us via the
[issue tracker](https://github.com/MWBMPartners/MeedyaConverter/issues).

To check the signing identity:

```
codesign -dv --verbose=4 /Applications/MeedyaConverter.app
```

Look for `Authority=Developer ID Application: MWBM Partners Ltd`.

### What's coming in v0.2.0

In v0.2.0 the Direct build will switch to **Sparkle**, the same auto-
update framework used by most well-known Mac apps. With Sparkle:

- MeedyaConverter will check for updates automatically on launch
  (configurable in Settings).
- New versions will install in-app — no manual DMG download required.
- Update binaries will be cryptographically verified with an EdDSA
  (Ed25519) signature before installation, so a tampered or
  malicious update cannot be installed even if it was hosted on a
  compromised server.

The Sparkle infrastructure is being prepared in
[issue #416](https://github.com/MWBMPartners/MeedyaConverter/issues/416)
(a Cloudflare Worker that proxies `update.mwbm.io` to GitHub Releases
so that the update URL baked into the app binary points at a stable
endpoint we control).

## Mac App Store (future)

If you installed MeedyaConverter from the Mac App Store ("MeedyaConverter
Lite"), updates are handled natively by the App Store. Open the
**App Store** app → **Updates** to see and install them. The Settings
→ Updates tab in MeedyaConverter Lite links to that page for
convenience.

The App Store version is currently in preparation and is not yet
available. See
[issue #178](https://github.com/MWBMPartners/MeedyaConverter/issues/178)
for status.

## I'm seeing "Couldn't check"

The GitHub poller can't reach the API. Common causes:

- **Not connected to the internet.** Reconnect and try again.
- **GitHub rate limit reached.** The public API allows 60 requests per
  hour per IP address. If you've been clicking a lot, wait an hour.
- **GitHub outage.** Rare, but check
  [githubstatus.com](https://www.githubstatus.com/) if "GitHub is
  having issues" appears.

The status line under the button explains which case applies. If none
of these fit, please
[file an issue](https://github.com/MWBMPartners/MeedyaConverter/issues/new)
with the status text shown.
