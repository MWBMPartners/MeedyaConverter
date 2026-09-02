# AppleScript & JavaScript for Automation (JXA)

MeedyaConverter is scriptable, so you can drive encoding from AppleScript, from
JavaScript for Automation (JXA), or from the command line via `osascript`. The
same scripting dictionary powers all three — open it in **Script Editor →
File → Open Dictionary… → MeedyaConverter** to browse the commands with
auto-completion.

The app must be running to receive scripting commands (launch it first, or let
the Apple Event launch it).

## Commands

| Command | Parameters | Returns |
| --- | --- | --- |
| `encode` | direct: input path · `using profile`: profile name · `to`: output path | the queued job's UUID, or an `ERROR:` string |
| `probe` | direct: media path | metadata JSON, or an `ERROR:` string |
| `list profiles` | — | newline-separated profile names |

`encode` returns immediately with the job's identifier; the encode runs in the
same queue as the GUI. Watch progress in the app's Queue view.

## AppleScript examples

Encode a file with the built-in "Web Standard" profile:

```applescript
tell application "MeedyaConverter"
    set jobID to encode "/Users/me/Movies/clip.mov" ¬
        using profile "Web Standard" ¬
        to "/Users/me/Movies/clip.mp4"
    return jobID
end tell
```

Probe a file and log its metadata:

```applescript
tell application "MeedyaConverter"
    set info to probe "/Users/me/Movies/clip.mov"
end tell
log info
```

Batch-encode a folder, one job per file:

```applescript
set inputFolder to POSIX path of (choose folder)
tell application "System Events"
    set theFiles to every file of folder inputFolder
end tell
tell application "MeedyaConverter"
    repeat with f in theFiles
        set inPath to inputFolder & (name of f)
        set outPath to inPath & ".mp4"
        encode inPath using profile "Web Standard" to outPath
    end repeat
end tell
```

List the available profiles:

```applescript
tell application "MeedyaConverter" to list profiles
```

## JavaScript for Automation (JXA)

JXA support comes for free from the same dictionary:

```javascript
const app = Application("MeedyaConverter");
const jobID = app.encode("/Users/me/Movies/clip.mov", {
    usingProfile: "Web Standard",
    to: "/Users/me/Movies/clip.mp4"
});
console.log(jobID);

const info = app.probe("/Users/me/Movies/clip.mov");
const profiles = app.listProfiles();
```

Run a JXA snippet from the shell:

```bash
osascript -l JavaScript -e 'Application("MeedyaConverter").listProfiles()'
```

## From the shell with `osascript`

```bash
osascript -e 'tell application "MeedyaConverter" to list profiles'
osascript -e 'tell application "MeedyaConverter" to probe "/Users/me/clip.mov"'
```

## Error handling

Every command returns a plain string. Failures come back as a single line
prefixed with `ERROR:` (for example, an unknown profile name or a missing
input file) rather than raising an Apple Event error, so a script can branch on
the reply:

```applescript
tell application "MeedyaConverter"
    set result to encode "/does/not/exist.mov" using profile "Web Standard" to "/tmp/out.mp4"
end tell
if result starts with "ERROR:" then
    display dialog result
end if
```

*See also: [cli-reference.md](cli-reference.md) for the headless
`meedya-convert` tool, and [getting-started.md](getting-started.md).*
