---
name: giff-it
description: Record a real screen GIF of a browser flow on macOS, including native UI that browser-side recorders cannot see (file pickers, window.prompt/alert/confirm, OS sheets, print dialogs). The browser tool drives the clicks while `screencapture` records the Chrome window, then ffmpeg trims idle time, blurs private content, adds a BEFORE/AFTER caption band that explains each step and the fix, and encodes a PR-ready GIF. Use for before/after PR evidence, ticket fix-summary media, lane verification, or any time a GIF must show what a user actually sees. Triggers on "/giff-it", "record a gif", "gif of the fix", "show the file picker opening", "the gif should show the dialog".
---

# giff-it

`gif_creator`, Playwright videos and `computer` screenshots all capture the **page**. A native file
chooser, a `window.prompt`, or an OS sheet is drawn by the browser or the OS, outside the page, so
those recorders show a page where nothing happened after the click. That is the wrong evidence
for exactly the bugs where the dialog *is* the behaviour. Two re-recordings of one fix came
from this: the Before never showed the URL prompt, and the After skipped the picker by feeding
a file straight into the input.

The fix is to record the **screen**. The browser tool clicks, `screencapture -v` records the
Chrome window's screen region, and ffmpeg turns the recording into a GIF.

**A GIF must explain itself.** A bare recording makes the reviewer reverse-engineer the fix from
the clicks, so every GIF this skill makes carries a caption band (step 4b). The band shows a
BEFORE or AFTER badge, the step number, and one line saying what is on screen. The last step
names the bug or the fix in words.

Every command below was run end to end on this machine (macOS, Retina, Chrome with the
claude-in-chrome extension).

## When not to use it

- The flow has no native UI, and page-only frames prove it: `gif_creator` is fine and cheaper.
- The target is a third-party app whose captures your project forbids posting. Record it
  **locally only**, to look at, and share a `/sketch-mockup` of the screen instead.

## 0 · Pre-flight

1. **Load.** Run `uptime`. Above ~20, wait; do not retry into it. Under load the browser tool
   times out injecting scripts and the recording stutters. Run a background wait loop instead of
   polling by hand:
   `for i in $(seq 1 115); do l=$(sysctl -n vm.loadavg | awk '{print int($2)}'); [ "$l" -lt 20 ] && exit 0; sleep 5; done`
2. **Screen-recording permission.** Run `screencapture -x <scratch>/probe.png`, then Read the
   PNG. If it is black or only shows the desktop, the terminal lacks Screen Recording permission.
   Ask the user to grant it; don't work around it.
3. **The right server on the right port.** For a Before, run the unfixed branch (a checkout of
   the base branch). For an After, run the fix branch. Check who owns the port first:
   `lsof -nP -iTCP:<port> -sTCP:LISTEN`. If another agent may run e2e against the same port,
   tell it the port is reserved, because Playwright's `reuseExistingServer` would test your
   server instead.
4. **Warm the route.** Run `curl -s -o /dev/null -w '%{http_code}' --max-time 240 <url>` so the
   first compile doesn't land inside the recording.

## 1 · Put the right tab in front

The recording captures whatever the screen shows. Two traps cost a take each:

- **The tool's tab is not necessarily the window's active tab.** The MCP tab group can sit in a
  window whose visible tab is something else (a tracker, GitHub). The recording then shows that
  tab, and a click that opens a native dialog does nothing in a background tab.
- **A background tab starves.** `javascript_tool` and `computer` time out on it ("renderer may
  be frozen") even when load is fine.

Find the window, activate the tab by URL, raise the window, and read its bounds:

```
osascript <<'EOF'
tell application "Google Chrome"
  repeat with w in windows
    set i to 0
    repeat with t in tabs of w
      set i to i + 1
      if URL of t contains "localhost:<port>" then
        set active tab index of w to i
        set index of w to 1
        activate
        return (id of w as string) & " " & (bounds of w as string)
      end if
    end repeat
  end repeat
end tell
EOF
```

`bounds` is `{left, top, right, bottom}` in **points**. The capture region is
`-R<left>,<top>,<right-left>,<bottom-top>`. Example: bounds `0, 121, 1512, 982` becomes
`-R0,121,1512,861`.

Before recording, confirm the page state with one `screencapture -x -R… still.png` and Read it.
Then navigate or reload to the starting state (toggles off, nothing typed) and get element refs
with `find`. Refs survive the recording; looking them up mid-take adds dead time.

## 2 · Record

Start the recording in the **background**, then drive the flow in the foreground:

```
osascript -e 'tell application "Google Chrome" to activate'; \
screencapture -v -V <seconds> -x -R<x>,<y>,<w>,<h> <scratch>/raw.mov
```

- `-V <seconds>` sets a fixed length. Budget ~1.5x the flow's steps, because each browser-tool
  call takes 1–4 s. For an early stop, `pkill -INT -f 'screencapture -v'` finalises the file
  (exit code 1 is normal).
- Drive with refs: `left_click ref`, then `scroll_to ref`, then `hover ref` (makes the cursor
  visible on the target), then `left_click ref`.
- **Make the dialog-opening click the last action.** A native JS dialog (`prompt`, `alert`,
  `confirm`) blocks the page, so that click's own tool call times out after 30 s. That is
  expected and means the dialog opened. Nothing else can be sent to the tab until it closes.
- **You cannot dismiss native dialogs.** `System Events` keystrokes are denied
  ("osascript is not allowed to send keystrokes"), and the browser tool cannot reach the
  dialog. When the take is done, ask the user to press **Cancel**. Say this up front, so the
  open dialog isn't a surprise.

## 3 · Find the timeline

Output is Retina pixels, twice the points: a `1512x861` region records at `3024x1722`, 120 fps.
Make a one-frame-per-second contact sheet and Read it to find the idle gaps and the frame
where the dialog appears:

```
mkdir -p <scratch>/f && ffmpeg -v error -i raw.mov -vf "fps=1,scale=480:-1" <scratch>/f/%02d.png
ffmpeg -v error -y -i <scratch>/f/%02d.png -vf tile=6x6 -frames:v 1 <scratch>/sheet.png
```

Tile N is second N-1. Expect an idle gap after each browser-tool round trip; cut it.

## 4 · Blur anything private

A file picker opens on a real folder (Downloads, Desktop) and shows real filenames. Blur the
file list, and the sidebar's user and custom-folder entries, **from the frame the dialog appears
in, not earlier**. Starting the blur even half a second early blurs the icon being clicked,
which is the point of the GIF. Get the region from a still of the open dialog, then multiply its
point coordinates by 2 for crop/overlay pixel coordinates.

Browser prompts (`localhost:3002 says / Image URL`) carry nothing private and need no blur.

## 4b · Caption: make the GIF explain the fix

This ffmpeg build has **no `drawtext`**: it was built without freetype, and the filter is
simply missing. So captions are rendered as PNG bands with headless Chrome, using the renderer
that ships with this skill, and overlaid in a strip **added below** the recording. The strip
never covers the UI being demonstrated.

```
~/.claude/skills/giff-it/render-caption.sh <out.png> 1456 110 <BADGE> '<color>' '<n>/<N>' '<main line>' '<sub line>'
```

- **Badge and colour:** `BEFORE` `#f0a04b` (amber) for the unfixed build, `AFTER` `#4cc38a`
  (green) for the fix. Keep the same step count and the same step-1 wording on both, so the
  pair reads as a side-by-side comparison.
- **Write three steps, in this shape:**
  1. **Context:** where you are and which build ("… on dev without the fix", "… with the fix
     (PR #N)").
  2. **What to notice:** the on-screen difference that matters ("Two image controls: the
     toolbar icon, plus a separate button" / "One image control: … the separate button is gone").
  3. **Verdict:** start with `Bug:` or `Fixed:` and state the behaviour in plain words, as a
     client would describe it ("Bug: the toolbar Insert image icon only asks for an Image URL").
- **Time each caption to the screen,** in **output** seconds, because captions are applied after
  the trim. The verdict caption starts on the frame the dialog or result appears, found with a
  0.1 s sheet: `ffmpeg -ss <t> -t 1 -i out.gif -vf "scale=480:-1,tile=5x2" …`. Captions that
  change before the screen does read as wrong.
- Keep each main line under ~70 characters at 1456 px. The renderer does not wrap it.

## 5 · Encode

One ffmpeg pass does the trim, blur, hold, caption band and encode. This template produced a
real captioned After. Drop the two blur lines and the `[fa]`/`[fb]` overlays when
there is nothing to hide.

```
ffmpeg -v error -y -i raw.mov -i c1.png -i c2.png -i c3.png -filter_complex "\
[0:v]split=3[base][a][b];\
[a]crop=<w1>:<h1>:<x1>:<y1>,boxblur=20:3[fa];\
[b]crop=<w2>:<h2>:<x2>:<y2>,boxblur=20:3[fb];\
[base][fa]overlay=<x1>:<y1>:enable='gte(t,<T>)'[t1];\
[t1][fb]overlay=<x2>:<y2>:enable='gte(t,<T>)',split=2[p1][p2];\
[p1]trim=0:<idle_start>,setpts=PTS-STARTPTS[s1];\
[p2]trim=<idle_end>:<end>,setpts=PTS-STARTPTS[s2];\
[s1][s2]concat=n=2:v=1,tpad=stop_mode=clone:stop_duration=3,fps=10,scale=1456:<H>:flags=lanczos,pad=1456:<H+110>:0:0:color=0x111317[v];\
[v][1:v]overlay=0:<H>:enable='lt(t,<c2_start>)'[v1];\
[v1][2:v]overlay=0:<H>:enable='between(t,<c2_start>,<c3_start>)'[v2];\
[v2][3:v]overlay=0:<H>:enable='gt(t,<c3_start>)',split[x][y];\
[x]palettegen=max_colors=128[pal];[y][pal]paletteuse=dither=bayer:bayer_scale=4" <TICKET>-<before|after>-<what>.gif
```

- `<H>` is the scaled recording height: `raw_height × 1456 / raw_width`, rounded (a
  `3024x1722` raw gives `829`). Pass it explicitly, because the caption overlays need the exact
  row where the band starts.
- `<T>` (blur) is in **raw** seconds, because the blur runs before the trim. `<c2_start>` and
  `<c3_start>` (captions) are in **output** seconds, because the captions run after it.
- `tpad … stop_duration=3` holds the final frame (the dialog) long enough to read.
- 10 fps, 1456 px wide and 128 colours give ~2–3 MB for ~20 s, which is fine for a GitHub embed.
- Name the file for the ticket and state: `ABC-123-after-picker.gif`.

## 6 · Verify before handing it over

- Read the **last frame**: `ffmpeg -v error -y -sseof -1 -i out.gif -frames:v 1 -update 1 last.png`.
- Read a one-frame-per-second sheet of the whole GIF, and check that each caption matches what
  is on screen while it shows. Then read a sheet of the seconds around the dialog's appearance,
  and check that the verdict caption lands with the dialog and no frame shows unblurred private
  content:
  `ffmpeg -v error -ss <t> -t 2 -i out.gif -vf "scale=480:-1,tile=5x4" -frames:v 1 sheet.png`.
- `ls -la` the GIF. Never report a GIF you haven't seen on disk.

## 7 · Publish (when it goes in a PR)

Evidence lives on an orphan `<branch>-assets` branch. **Never make it with a worktree
checkout.** `git worktree add` followed by `git checkout --orphan` writes and stages all ~13k
repo files. Endpoint security scans each one, and a lane stalled there for good. Build the
commit from objects instead: nothing touches the working tree or the real index.

```
R=<repo>; IDX=<scratch>/evidence.index; rm -f "$IDX"
# Appending to an existing assets branch? Seed the temp index with its tree first:
#   P=$(git -C $R rev-parse origin/<branch>-assets); GIT_INDEX_FILE=$IDX git -C $R read-tree $P
b=$(git -C $R hash-object -w <file.gif>)
GIT_INDEX_FILE=$IDX git -C $R update-index --add --cacheinfo 100644,$b,evidence/<file.gif>
c=$(git -C $R commit-tree $(GIT_INDEX_FILE=$IDX git -C $R write-tree) ${P:+-p $P} -m "evidence for <branch>")
git -C $R push origin $c:refs/heads/<branch>-assets
rm -f "$IDX"
```

Verify with `gh api "repos/<org>/<repo>/contents/evidence/<file.gif>?ref=$c"`, because an
anonymous curl 404s on a private repo. Embed with
`https://github.com/<org>/<repo>/raw/$c/evidence/<file.gif>` (never `raw.githubusercontent.com`).

## 8 · Clean up

- Stop any server you started, by port: `lsof -nP -tiTCP:<port> -sTCP:LISTEN | xargs -r kill`,
  then confirm the port is free.
- Tell anyone you reserved the port for that it's free.
- Close the tabs you opened (`tabs_close_mcp`), and remind the user about any dialog still open.
