# 💿 Disc Tools

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## What MeedyaConverter will and will not do

This matters more than any feature list, so it comes first.

**MeedyaConverter does not break copy protection.** When it meets a protected
disc it says so and stops. It does not decrypt, and it will not be persuaded
to. That applies to every disc feature with exactly one exception — MakeMKV,
described below — which is off until you turn it on and which hands the job to
software you install yourself.

**Nothing is sent anywhere unless you ask.** Identifying a disc is offline
apart from a single lookup. Contributing to MeedyaDB is off until you switch
it on, and even then it sends only the disc's identity — never your files,
your library, or anything about you.

All of this needs raw access to your optical drive, so it is available in the
Direct version only. The App Store version runs in a sandbox that cannot reach
the drive.

---

## Identifying a disc

Choose **Identify Disc** in the sidebar.

A music CD's track layout is very nearly a fingerprint: the exact lengths of
the tracks, measured to a 75th of a second, almost never repeat across
different albums. MeedyaConverter turns that layout into an identifier and
asks MusicBrainz which release it belongs to. The answer is usually exact
rather than a guess.

You can read either a disc in a drive, or a table-of-contents file saved from
an earlier read. The saved-file option needs no disc and no drive at all,
which is handy for checking something you have already read.

### If it says the drive is in use

macOS mounts a disc the moment you insert it, and it has to let go before the
disc can be read properly. The screen offers a **Release … and Try Again**
button. Pressing it closes the disc in Finder and in any other app using it —
the disc stays in the drive, and you can eject it normally afterwards.

MeedyaConverter never does this on its own. Taking a disc away from another
app without asking would be rude at best, and might interrupt something you
were in the middle of.

### What the results mean

**Disc ID** is the identifier MusicBrainz recognises, covering the music on
the disc.

**Whole-disc ID** appears only for an Enhanced CD — a disc with music *and* a
data session of computer files. MusicBrainz measures only the music, so that
is what MeedyaConverter asks about, but it records both. That lets the disc be
matched against other copies *and* told apart from a pressing with different
bonus content.

If MusicBrainz has never seen the disc, that is a perfectly good answer and
not an error. The identifiers are still worked out, and are still worth
contributing — a disc nobody has catalogued is exactly the one worth adding.

---

## MakeMKV

Choose **MakeMKV Rip** in the sidebar; switch it on under Settings → MakeMKV.

MakeMKV is **separate software you install yourself**. MeedyaConverter does
not include it, does not install it, and cannot use it until you have both
installed it and switched this on.

### Why it is a special case

Every other disc feature refuses protected discs. MakeMKV unlocks them. That
is the whole reason it is a separate, off-by-default choice with its own terms
box rather than just another feature: turning it on is you deciding to use
different software with different rules, and taking responsibility for
MakeMKV's own licence terms and for the copyright law where you live.

MeedyaConverter never bundles MakeMKV, never ships a key for it, and never
decrypts anything itself. It runs the copy you installed, as a separate
program.

### Turning it on

1. Install MakeMKV yourself.
2. Settings → MakeMKV → turn on **Enable MakeMKV disc ripping**.
3. Type your acknowledgement in the terms box. It stays unavailable until
   this is filled in — a tick box alone is too easy to click past.
4. Leave the location field blank unless MakeMKV is somewhere unusual.

The Status section tells you plainly whether MakeMKV was found.

### Ripping

Choose a source, scan it, tick the titles you want, choose where to save, and
rip. You can read from an optical drive, a device path, a disc image, or a
folder containing already-decrypted `VIDEO_TS` or `BDMV` files.

Titles are ripped one at a time, with progress for each. Scanning a Blu-ray
can take several minutes; both the scan and the rip can be cancelled, and
leaving the screen cancels anything in progress.

Ripped files are simply saved. They are not added to the queue and not
identified automatically — what happens to them next is up to you.

---

## Contributing to MeedyaDB

Settings → MeedyaDB.

MeedyaDB is a shared database of media and the links between them. When you
switch this on, a disc you identify can be sent to it so that others can
recognise the same disc.

It is **off by default**, and identifying discs works perfectly well without
it. Nothing about the feature is degraded if you never turn it on.

### What is sent

**Just the disc's identity** (the default) sends the disc's identifiers, its
track layout, and how many tracks it has.

**Identity and the disc's label** sends the above plus the text printed on the
disc. Worth a moment's thought for a home-made disc, where the label may be
something you wrote yourself.

Neither option ever sends your file paths, your library, your settings, or
anything identifying you.

### Your API key

Your MeedyaDB key is stored in the macOS Keychain, not in MeedyaConverter's
settings file. Once saved it is never shown again — you can replace it or
remove it, but not read it back.

This is deliberate. The app's settings file is ordinary readable text, and a
key with write access to a shared database does not belong in one.

---

## Third-party tools

MeedyaConverter runs these as separate programs rather than linking them in,
which is what keeps their licences compatible with the app's own code.

Included with the Direct version: **cdrdao** (GPL 2), **libcdio** and
**cdparanoia** (GPL), **libdvdread** and **libdvdnav** (GPL 2), and
**libbluray** (LGPL 2.1).

**MakeMKV is proprietary, is not redistributable, and is not included.** It
uses a rotating free beta key for some features. That is why it is the one
tool you have to supply yourself, and why MeedyaConverter asks you to
acknowledge its terms before it will run it.

MusicBrainz lookups need no account and no key. MeedyaConverter identifies
itself in its requests and keeps to MusicBrainz's rate limits.
