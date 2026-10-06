---
name: playwright-debug
description: Diagnose and repair a broken or hanging Playwright browser install, especially `playwright install` appearing to hang forever, "Executable doesn't exist at ...", or E2E specs that cannot run locally. Use when Playwright browsers fail to install, a version bump makes E2E unrunnable, or you are about to declare an E2E test unverifiable. Triggers on "/playwright-debug", "playwright install hangs", "playwright browser missing", "chromium build not installed", "can't run e2e locally".
---

# Playwright install debug

`playwright install` that never finishes is almost never a network problem. This skill
goes straight to the real cause and repairs the install by hand.

Written from a session where two wrong diagnoses cost over an hour and nearly shipped an
unverified E2E spec. Every command here was run end to end on macOS against Playwright
1.58.0.

## Law: an unrunnable E2E test is not a shippable one

If you are here because a spec "can't be verified locally", fix the install and run it.
Do not put the test in a PR with a caveat that CI will be its first execution. That is a
skipped gate wearing a disclosure, and it costs a CI cycle plus a reviewer's attention on
untested code. If the install genuinely cannot be repaired, drop the test from the PR and
record it as follow-up — never ship it unrun.

## 1. Get the ground truth in one command

**`--dry-run` prints the expected install path and the real download URL.** Start here
every time; it replaces guessing entirely.

```
pnpm --dir <dir> exec playwright install --dry-run <browser>
```

```
Chrome Headless Shell 145.0.7632.6 (playwright chromium-headless-shell v1208)
  Install location:    ~/Library/Caches/ms-playwright/chromium_headless_shell-1208
  Download url:        https://cdn.playwright.dev/chrome-for-testing-public/145.0.7632.6/mac-arm64/chrome-headless-shell-mac-arm64.zip
```

Then compare against what is actually on disk:

```
ls ~/Library/Caches/ms-playwright/
```

A populated install has an inner platform directory **plus two marker files**:

```
chromium_headless_shell-1237/
├── chrome-headless-shell-mac-arm64/   # the real payload, ~190 MB
├── DEPENDENCIES_VALIDATED             # empty marker
└── INSTALLATION_COMPLETE              # empty marker
```

Missing markers or an inner directory holding only `ABOUT` and `LICENSE` mean a previous
install died mid-extract. Delete that directory before retrying anything.

### The version-bump trap

A Playwright upgrade pins a **new browser revision**. A cache full of 1200/1237/1243 does
nothing for a Playwright that wants **1208** — E2E is silently unrunnable for everyone on
the machine until someone installs that exact build. Check the revision in `--dry-run`
against `ls`, not just "chromium is installed".

## 2. Diagnose: download or extract?

Redirect to a file — piping to `tail`/`head` can itself stall the installer's progress
rendering and make a working install look hung:

```
DEBUG=pw:install pnpm --dir <dir> exec playwright install <browser> > /tmp/pw.log 2>&1
```

Read `/tmp/pw.log`:

- `SUCCESS downloading ...` then `extracting archive` → **extract is the problem.** Go to §3.
  On a machine with endpoint security (CrowdStrike Falcon and similar), extraction is
  scanned file by file; observed writing ~1.5 MB in 55 minutes at near-zero CPU while the
  91 MB download took ~5 seconds.
- Stalls before `response status code: 200` → genuine network or proxy issue. Check
  `env | grep -i proxy` and whether the `Download url` from §1 is reachable.

**Do not hand-build a CDN URL to test reachability.** `chrome-headless-shell` comes from
`cdn.playwright.dev/chrome-for-testing-public/<version>/...`, while other artifacts use
`/dbazure/download/playwright/builds/<name>/<rev>/...`. A guessed URL returns `400
GatewayExceptionResponse`, which looks exactly like an outage and is not one. Use the URL
`--dry-run` printed.

**Never kill an install mid-extract** — it leaves a half-written directory that makes the
next attempt fail differently.

## 3. Repair: extract it yourself

Native `unzip` does in seconds what the installer's extractor wedges on.

```
URL='<Download url from --dry-run>'
D='<Install location from --dry-run>'

curl -sSL -o /tmp/pw-browser.zip "$URL"
rm -rf "$D" && mkdir -p "$D"
unzip -q -o /tmp/pw-browser.zip -d "$D"

touch "$D/INSTALLATION_COMPLETE" "$D/DEPENDENCIES_VALIDATED"
```

Then make it runnable. The binary name differs per browser, so find it rather than
assuming:

```
BIN=$(find "$D" -maxdepth 2 -type f -perm -111 ! -name "*.dylib" ! -name "*.so" | head -1)
chmod +x "$BIN"
xattr -dr com.apple.quarantine "$D"      # macOS only; silently fine if unneeded
"$BIN" --version                          # must print a version, e.g. Google Chrome for Testing 145.0.7632.6
```

If `--version` prints, the install is good. Skipping the markers is the usual reason
Playwright re-downloads a browser that is already on disk.

Browser cache root by platform (only the macOS path is verified here):

| Platform | Root |
| --- | --- |
| macOS | `~/Library/Caches/ms-playwright` |
| Linux | `~/.cache/ms-playwright` |
| Windows | `%USERPROFILE%\AppData\Local\ms-playwright` |

`PLAYWRIGHT_BROWSERS_PATH` overrides the root when set — check it before concluding a
browser is missing.

## 4. Prove the repair with the real suite

Run the spec that sent you here, scoped — never the whole suite:

```
pnpm --dir <dir> test:e2e <path/to/one.spec.ts>
```

In a git worktree, binaries need the `exec` form; `pnpm --dir <wt> playwright ...` fails
with `EACCES ... spawn <wt>`.

**Then prove the test is worth having.** A passing E2E proves the harness works, not that
the test guards anything. Neutralize the behaviour under test, re-run, and confirm it
fails:

```
# edit the one line that implements the feature, then:
pnpm --dir <dir> test:e2e <path/to/one.spec.ts>     # expect failures
# restore the line, re-run, expect green
```

Tests that pass in both states are tautologies. Restore the file and confirm green before
moving on.

## Known traps

| Symptom | Cause / fix |
| --- | --- |
| `playwright install` runs for tens of minutes with ~0% CPU | Extract wedged under endpoint scanning. §3 |
| `Executable doesn't exist at .../chromium_headless_shell-<rev>/...` | That exact revision isn't installed; a Playwright bump changed it. §1 |
| Install "completes" but the browser is still missing | Marker files absent, or the process was killed mid-extract leaving `ABOUT`/`LICENSE` only |
| A hand-built CDN URL returns `400 GatewayExceptionResponse` | Wrong URL shape, not an outage. Use `--dry-run`'s URL |
| An authenticated `curl` of an artifact URL 200s but the install still fails | Reachability was never the problem; re-read the log for `extracting archive` |
| `EACCES ... spawn <worktree>` | Use `pnpm --dir <wt> exec <binary>`, not `pnpm --dir <wt> <binary>` |
| Install appears to hang only when its output is piped | Redirect to a file instead of piping to `tail`/`head` |
