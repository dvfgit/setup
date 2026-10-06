# Machine-level working notes

Facts about *this machine* and this toolchain, verified in use. Repo-specific commands live
in each repo's own `.claude/rules/lane-profile.local.md`, not here.

## Heavy file operations and machine load

If this machine runs endpoint security that scans every written file, ordinary operations turn
into apparent hangs, and the symptoms never look like scanning:

- **A large checkout or package install can drive load into the tens or hundreds for minutes
  afterwards.** Browser automation then times out injecting scripts and vitest workers fail to
  spawn. The tell is a huge load average with almost nothing in `ps -r` — blocked processes,
  not busy ones. Wait for it to decay; retrying deepens it.
- **Check `uptime` before anything heavy** (install, suite, dev server, browser-driving
  subagent). If load is far above the core count, wait instead of adding to it.

Either way:

- **Never create a throwaway worktree with a full checkout.** `git worktree add --no-checkout`
  when you only need a branch ref — e.g. an orphan assets branch. `git reset` clears the index
  instantly and leaves the files untracked, which is usually all that is needed.

## Playwright: `install` hangs in the *extract* step, never the download

Seen on a machine with endpoint security. The archive downloads at ~20 MB/s and then extraction crawls (~1.5 MB in 55 minutes). Use
`/playwright-debug` — it has the tested repair. The short version: `playwright install
--dry-run <browser>` prints the real install path and download URL, then `curl` + native
`unzip` + `touch INSTALLATION_COMPLETE DEPENDENCIES_VALIDATED` + `chmod +x` + `xattr -dr
com.apple.quarantine`.

Do not hand-build a Playwright CDN URL to test reachability — `chrome-headless-shell` lives
under `/chrome-for-testing-public/<version>/`, not `/builds/chromium/<rev>/`, so a guessed
URL 400s and impersonates an outage. Do not kill an install mid-extract; it leaves a
half-written directory that must be deleted before retrying.

## pnpm in a git worktree

Binaries need the `exec` form or they fail with `EACCES ... spawn <worktree>`:

```
pnpm --dir <worktree> exec vitest run <paths>
pnpm --dir <worktree> exec knip
```

Package *scripts* work with the bare form (`pnpm --dir <wt> typecheck`). A repo profile that
says `test <paths>` does not survive the `--dir` hop.

## Never `cd`; the working directory resets between calls

`cd <dir> && …` prefixed onto commands is the single largest source of permission prompts,
because the checker cannot resolve the target inside a compound command. Use `git -C <dir>`,
`pnpm --dir <dir>`, and absolute paths. A single `cd` up front does not stick — the harness
resets cwd after each call.

## Run tests, lint and typecheck as separate commands

Chaining them starves the vitest workers: the typechecker is still saturating the CPU when
the workers try to spawn, and the run collects zero tests.

## Verifying a URL on a private GitHub repo

An anonymous `curl` of `github.com/<org>/<repo>/raw/<sha>/...` returns 404 even when the file
is there. Verify with `gh api "repos/<org>/<repo>/contents/<path>?ref=<sha>"` instead. Use the
`github.com/.../raw/...` form in markdown (never `raw.githubusercontent.com`, which renders as
a broken image on private repos).

## Browser automation

Prefer `find` + element refs over raw coordinates — the window resizes between captures and a
stray click can open unrelated UI. After a code change the dev server recompiles, so a page
can look empty for 15-30s; wait and re-check before concluding anything is broken.

Exported GIFs have silently failed to land on disk mid-session. **Verify the file exists
before relying on it**; `computer` with `save_to_disk: true` returns a real path and is the
reliable fallback, and `ffmpeg` is available to assemble stills into a GIF.
