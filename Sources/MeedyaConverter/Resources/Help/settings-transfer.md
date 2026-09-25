# 📤 Settings: Import & Export

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## What this is for

**Settings › Import & Export** moves your preferences, your connection
details and your own encoding profiles from one Mac to another — or just
keeps a backup you can bring back to this same Mac later. It never asks you
to re-build anything by hand: it writes one JSON file, and reading that file
back on the other Mac sets everything up the same way.

The same feature is also available from the command line, as
`meedya-convert settings export` and `meedya-convert settings import` — see
[CLI Reference](cli-reference.md). Both the app and the command line call the
exact same underlying code, so a file made by one always works with the
other, and neither one will ever show you a different answer about what a
given file does.

---

## What travels, and what never does

Exporting writes 106 settings and your own encoding profiles, sorted into
four groups you can tick individually — plus a fifth, off by default, for
settings tied to this particular Mac (see below).

A password, an API key, a token, a webhook address, or a hook is **never**
written to the file, whatever you tick. This isn't done by scanning the file
afterwards and removing anything that looks sensitive — it's the other way
round: only settings that have been individually decided as safe to export
are ever written in the first place. Anything not on that list — including
anything added by a future version that nobody has reviewed yet — is left
out automatically, which is the safe direction for a mistake to fail in.

Specifically, none of the following ever appears in an exported file:

- **Passwords and API keys** — your TMDB key, your MeedyaDB key, your media
  server's key or token, your SMTP password, and any cloud storage token or
  secret. These stay in the Keychain and are never read out of it by this
  feature — not even to check they're correct, only to check that
  *something* is saved (see "Still needs a key", below).
- **SFTP server passwords.** If an SFTP server's password was ever saved to
  the settings file directly by an older version of MeedyaConverter (rather
  than being moved to the Keychain, which is what happens automatically the
  first time you open the SFTP screen), the exporter blanks it out before
  writing, regardless.
- **Cloud storage tokens.** Access tokens, refresh tokens, and secret access
  keys for S3-compatible storage are all blanked out the same way.
- **The webhook address, and any custom headers you've set for it.** For the
  Slack and Discord webhook presets, the address itself works like a
  password — anyone who has it can post to your channel — so it's treated as
  one. Custom headers are free text, and people put `Authorization` tokens
  in them, so the whole thing is left out.
- **Hooks** — anything configured in Settings › Hooks to run after an
  encode. A hook can run a shell script, call a web address, or move a file
  to the Trash, so a settings file must never be able to plant one on
  another Mac. Hooks are simply not part of this feature yet; you set them
  up again, by hand, on each Mac.
- **Consents given on this particular Mac** — the MakeMKV terms
  acknowledgement, the render farm's "allow unencrypted connections"
  opt-in, and whether you've agreed to send anonymous usage data. These are
  all yes/no decisions that only make sense made in person, on the Mac
  where they apply.
- **Anything that could unlock a paid tier**, or that identifies this
  particular installation (a cached licence level, an anonymous analytics
  ID).
- **Any address that carries a user name or password inside it** — for
  example a git remote written as `https://token@github.com/…`. Addresses
  like this are refused the same way a password would be, both when writing
  the file and when reading one back in.

Every one of these has a reason recorded against it, and Settings › Import &
Export shows the full list under **"What's never included"**, generated
directly from that same table of decisions — so it can never quietly go out
of date.

---

## The four groups, and "This Mac only"

- **General and appearance** — theme, notifications, keyboard shortcuts,
  the update channel.
- **Encoding and output** — the default profile, what happens to files
  before and after converting, the filename template, conditional rules,
  saved pipelines, vector conversion options, Audio CD options, and
  automatic tagging.
- **Your encoding profiles** — the profiles you made yourself. The built-in
  profiles are never included, because every copy of MeedyaConverter already
  has them.
- **Connections to other services** — server addresses, ports, user names
  and on/off switches for email, media servers, webhooks, MeedyaDB, the
  render farm, SFTP, cloud storage and team profiles. As above, the
  passwords, keys, tokens and webhook address that go *with* these
  connections are never included.

A fifth group, **"This Mac only"**, is off by default on both export and
import, and shows a warning when you turn it on. It covers where FFmpeg and
other tools are installed on this Mac, and your CD drive's model and read
offset. Only include it if the other Mac genuinely has the same tools
installed in the same places, and the same CD drive — a wrong read offset
can make an otherwise good CD rip fail its AccurateRip check.

---

## Merge or replace

When you import a file, you choose how it's applied to your own settings:

- **Add to my settings (recommended).** Only the settings the file actually
  mentions are changed. Anything the file doesn't mention — including
  anything you've set up locally that the file simply doesn't know about,
  like a different SFTP server — stays exactly as it is. Lists (SFTP
  servers, cloud destinations, conditional rules, saved pipelines, encoding
  profiles) are merged item-by-item: an item the file shares with you
  updates yours, and any of your own items the file doesn't mention are
  left alone.
- **Replace my settings in the ticked groups.** Makes the groups you've
  ticked match the file exactly. A setting in one of those groups that the
  file doesn't have goes back to its default. A profile, SFTP server, cloud
  destination or rule in one of those groups that the file doesn't have is
  **removed**. Groups you haven't ticked, and anything marked "never" above,
  are not touched either way.

**Replace never applies immediately.** If it would remove or reset
something, you're shown exactly what — for example, "This removes 2
profiles and 1 SFTP server" — and applying it needs a separate, clearly
marked "Replace Anyway" button. Closing the preview, or pressing the
ordinary "Import" button again, changes nothing.

Whichever mode you choose, a password or key already saved on this Mac is
never touched, and a "never" setting — a password, a hook, a consent — can
never be planted by the file, no matter what it contains.

---

## The preview, before anything is written

Choosing a file to import never writes anything straight away. You first see
a preview of exactly what would happen:

- where the file came from, and when it was made;
- one row per group, with a count and how many items would actually change;
- a "Show details" list of the individual settings, profiles and list items
  that would change, added, or be removed;
- warnings for anything that needs a second look (for example, "Delete
  source after successful encode: ON");
- cross-checks — for example, if the file's default profile isn't one you
  have and isn't being imported either, the preview says which profile will
  be used instead;
- anything the file contains that this version of MeedyaConverter doesn't
  recognise, listed as "not imported", together with why.

Nothing is written until you press Import (and, for Replace, confirm it
separately). Closing the preview at any point leaves your settings exactly
as they were.

---

## "Still needs a key"

Because passwords and keys never travel in the file, importing one on a new
Mac will always leave some things still to enter by hand. Rather than stay
silent about this, the file records — by name only, never by value — which
of these you had set up on the Mac it came from: a TMDB key, a MeedyaDB key,
a media server key, an SMTP password, a webhook address (and its custom
headers), hooks, MakeMKV's acknowledgement, and the render farm's
unencrypted-connections opt-in.

After importing, you're shown exactly which of these still need entering on
this Mac, and precisely where — for example:

- "TMDB key: Settings › Metadata"
- "Media server key: Settings › Media Server"
- "SMTP password: Settings › Email"
- "Webhook address: Settings › Webhooks"
- "Hooks: Settings › Hooks"

This check never reads a real secret to work this out — it only asks the
Keychain "does something exist here?", which is why it can tell you a key is
missing without ever having looked at one.

---

## The Mac App Store limit

`meedya-convert settings export`/`import` on the command line always works
with the **Direct** build's settings. The Mac App Store version runs inside
a sandbox, and its settings — along with any keys it has saved — live
somewhere the command-line tool simply cannot see at all. That isn't a
missing feature to fix later; it's what the sandbox is for.

If you use the Mac App Store version of MeedyaConverter, use **Settings ›
Import & Export inside that app** instead — it reads and writes that app's
own settings directly, with no such limit.

---

## What takes effect straight away, and what needs a relaunch

Most imported settings take effect the moment you import them. A few —
where FFmpeg and other tools are installed, the app's theme, and the default
encoding profile among them — are only read once, when MeedyaConverter
starts up. Importing these still updates the file; you just won't see the
change until you next quit and reopen the app. The result screen always
lists exactly which settings fall into this second group, so nothing is
left silently half-applied.
