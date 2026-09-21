<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Disc tools

What MeedyaConverter can do with physical discs: **copy them**, **work out
what is on them**, and — optionally — **share what it worked out**.

Everything on this page is **Direct distribution only**. The App Store version
runs in a sandbox with no raw access to optical drives, so the disc tools are
either hidden or will tell you honestly that they cannot reach the drive.

---

## 1. What MeedyaConverter will and will not do

This matters more than any feature list, so it comes first.

**MeedyaConverter does not break copy protection.** When it meets a protected
disc it says so and stops. It does not decrypt, and it will not be persuaded
to. That applies to every disc path in the app with exactly one exception,
described in [MakeMKV](#3-makemkv-optional-off-by-default) below, which is
off until you turn it on and which hands the job to software you install
yourself.

**Nothing is sent anywhere unless you ask.** Identifying a disc is entirely
offline apart from one lookup (see below). Contributing to MeedyaDB is off
until you switch it on, and even then it sends only the disc's identity — never
your files, your library, or anything about you.

---

## 2. Identifying a disc

**Where:** *Identify Disc* in the sidebar, or `meedya-convert disc identify`.

A music CD's track layout is very nearly a fingerprint: the exact lengths of
the tracks, measured to a 75th of a second, almost never repeat across
different albums. MeedyaConverter turns that layout into an identifier and
asks [MusicBrainz](https://musicbrainz.org) which release it belongs to. The
answer is usually exact rather than a guess.

### Reading from a drive

Put the disc in, choose **Disc in a Drive**, and give the drive — typically
`/dev/rdisk2`. Disk Utility will tell you the number if you are not sure.

**If it says the drive is in use:** macOS mounts a disc the moment you insert
it, and it has to let go before the disc can be read properly. The screen
offers a **Release … and Try Again** button. Pressing it closes the disc in
Finder and in any other app using it — the disc stays in the drive, and you
can eject it normally afterwards. MeedyaConverter never does this on its own,
because taking a disc away from another app without asking is rude at best.

### Reading a saved table of contents

Choose **Saved Table of Contents** and pick a `.toc` file from an earlier
read. This needs no disc and no drive at all, which makes it handy for
checking a disc you have already read, or on a machine with no optical drive.

Produce one with:

```
meedya-convert disc toc --device /dev/rdisk2 -o my-disc.toc
```

### What you get

| Line | What it means |
| ---- | ------------- |
| **Disc ID** | The identifier MusicBrainz recognises, covering the music on the disc. |
| **Whole-disc ID** | Only shown for an Enhanced CD (see below). Covers the whole disc including its computer files. |
| **Audio tracks** | How many music tracks the disc carries. |

An **Enhanced CD** (sometimes CD-Extra) has music *and* a data session with
computer files on it. MusicBrainz measures only the music, so that is what
MeedyaConverter asks about — but it records both identifiers, so the disc can
be both *matched* against other copies and *told apart* from a pressing with
different bonus content.

If MusicBrainz has never seen the disc, that is a perfectly good answer and
not an error. The identifiers are still worked out, and are still worth
contributing — a disc nobody has catalogued is exactly the one worth adding.

### From the command line

```bash
# Identify the disc in a drive
meedya-convert disc identify --device /dev/rdisk2

# Identify a saved table of contents, as JSON for scripting
meedya-convert disc identify --toc my-disc.toc --format json

# Work out the identifiers and contact nothing at all
meedya-convert disc identify --toc my-disc.toc --offline
```

`--offline` is genuinely offline: no lookup, no upload, nothing leaves the
machine.

---

## 3. MakeMKV (optional, off by default)

**Where:** *MakeMKV Rip* in the sidebar. Settings → MakeMKV to switch it on.

[MakeMKV](https://www.makemkv.com) is **separate software you install
yourself**. MeedyaConverter does not include it, does not install it, and
cannot use it until you have both installed it and switched this on.

### Why it is a special case

Every other disc path in MeedyaConverter refuses protected discs. MakeMKV
unlocks them. That is the whole reason it is a separate, off-by-default
choice with its own terms box rather than just another feature: turning it on
is you deciding to use different software with different rules, and taking
responsibility for MakeMKV's own licence terms and for the copyright law where
you live.

MeedyaConverter never bundles MakeMKV, never ships a key for it, and never
decrypts anything itself. It runs the copy you installed, as a separate
program.

### Turning it on

1. Install MakeMKV yourself.
2. Settings → **MakeMKV** → turn on **Enable MakeMKV disc ripping**.
3. Type your acknowledgement in the terms box. It stays unavailable until
   this is filled in — a tick box alone is too easy to click past.
4. Leave the location field blank unless MakeMKV is somewhere unusual, in
   which case point it at `makemkvcon`.

The **Status** section tells you plainly whether MakeMKV was found.

### Ripping

Choose a source, scan it, tick the titles you want, choose where to save, and
rip. Sources:

| Source | What it is |
| ------ | ---------- |
| **Optical Drive** | A drive by MakeMKV's own number, starting at 0. |
| **Device Path** | A raw device node, e.g. `/dev/rdisk2`. |
| **Disc Image (ISO)** | A `.iso` file. |
| **Disc Folder** | A folder *containing* a `VIDEO_TS` or `BDMV` folder — files that have already been decrypted by whatever produced them. |

Titles are ripped one at a time, with progress for each. Scanning a Blu-ray
can take several minutes; both the scan and the rip can be cancelled, and
leaving the screen cancels anything in progress.

**Ripped files are simply saved.** They are not added to the queue and not
identified automatically — what happens to them next is up to you.

---

## 4. Contributing to MeedyaDB

**Where:** Settings → MeedyaDB.

MeedyaDB is a shared database of media and the links between them. When you
switch this on, a disc you identify can be sent to it so that others can
recognise the same disc.

**It is off by default, and identifying discs works perfectly well without
it.** Nothing about the feature is degraded if you never turn it on.

### What is sent

| Setting | What leaves your machine |
| ------- | ------------------------ |
| **Just the disc's identity** (default) | The disc's identifiers, its track layout, and how many tracks it has. |
| **Identity and the disc's label** | The above, plus the text printed on the disc. |

Neither option ever sends your file paths, your library, your settings, or
anything identifying you. The second option is worth a moment's thought for a
home-made disc, where the label may be something you wrote yourself.

### The API key

Your MeedyaDB key is stored in the **macOS Keychain**, not in
MeedyaConverter's settings file. Once saved it is never shown again — you can
replace it or remove it, but not read it back. This is deliberate: the app's
settings file is ordinary readable text, and a key with write access to a
shared database does not belong in one.

From the command line the key comes from the `MEEDYADB_API_KEY` environment
variable and is never accepted as an argument, because command-line arguments
are visible to anyone else on the machine:

```bash
export MEEDYADB_API_KEY='mdk_live_…'
meedya-convert disc identify --device /dev/rdisk2 \
    --submit --meedyadb-url https://your-meedyadb-server
```

Contributing from the command line is opt-in on **every run** (`--submit`)
rather than a stored setting, and the command exits with an error if you asked
to contribute and nothing was actually sent.

---

## 5. Third-party tools

MeedyaConverter runs these as **separate programs**, not as linked libraries,
which is what keeps their licences compatible with the app's own proprietary
code.

| Tool | Licence | Used for | Bundled? |
| ---- | ------- | -------- | -------- |
| cdrdao | GPL 2 | Reading a CD's table of contents; audio CD imaging | Yes (Direct builds) |
| libcdio / cdparanoia | GPL | Optical disc reading | Yes (Direct builds) |
| libdvdread / libdvdnav | GPL 2 | DVD reading | Yes (Direct builds) |
| libbluray | LGPL 2.1 | Blu-ray reading | Yes (Direct builds) |
| **MakeMKV** | **Proprietary** | **Optional DVD/Blu-ray title extraction** | **No — you install it yourself** |

MakeMKV is proprietary, is not redistributable, and uses a rotating free beta
key for some features. That is why it is the one tool on this list you have to
supply, and why MeedyaConverter asks you to acknowledge its terms before it
will run it.

MusicBrainz lookups need no account and no key. MeedyaConverter identifies
itself in its requests and keeps to MusicBrainz's rate limits.
