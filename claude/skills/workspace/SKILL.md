---
name: workspace
description: >-
  Create a workspace directory for a repository — `<repo>-workspace/` holding the
  cloned repo plus a sibling `worktrees/` directory that the /worktree command
  targets. Use when the user wants to set up a new repo locally in the standard
  workspace layout. Accepts a clone URL, or a bare repo name resolved against a
  GitHub org mapped to the current directory tree in ~/.claude/workspace-orgs.
  Triggers on "/workspace
  <repo-url>", "/workspace <repo-name>", "set up a workspace for <repo>", "clone
  <url> into a workspace".
---

# Workspace

Set up a repository in the standard workspace layout:

```
<parent>/
└── <repo-name>-workspace/
    ├── <repo-name>/      ← the clone (default branch)
    └── worktrees/        ← empty; /worktree adds branches here
```

The `worktrees/` sibling is what makes `/worktree <branch>` place worktrees next
to the checkout instead of under `~/.cursor/worktrees/`, so always create it —
even empty.

**Arguments:** `$ARGUMENTS` — the repository (required), optionally followed by
flags:

- `--into <dir>` — parent directory for the workspace (default: the current
  working directory)
- `--name <name>` — override the derived workspace/clone name
- `--no-install` — skip dependency installation

The repository may be given as a full clone URL, or — when working inside a
directory tree mapped to a GitHub org — as a bare repo name (`/workspace my-api`).
See step 1.

## Steps

### 1. Resolve the repository argument

If there is no repository argument at all, print and stop:

```
❌ Error: repository is required.
Usage: /workspace <repo-url|repo-name> [--into <dir>] [--name <name>] [--no-install]
Example: /workspace https://github.com/<org>/<repo>
```

**If the argument is a URL**, use it verbatim. Accept any form git accepts:
`https://host/org/repo(.git)`, `git@host:org/repo(.git)`,
`ssh://git@host/org/repo(.git)`. Treat it as a URL if it contains `://` or
matches `<user>@<host>:<path>`.

**If the argument is a bare name** (no scheme, no host — e.g. `my-api`),
resolve it against a GitHub org, but *only* when the working directory is inside
a tree mapped to one in `~/.claude/workspace-orgs`. That file is local to each
machine and never committed; one mapping per line, `<directory> <github-org>`:

```
# ~/.claude/workspace-orgs
~/Projects/clients/acme   acme-inc
```

Pick the longest directory that contains `$PWD`:

```bash
ORG=""; BEST=0
while read -r dir org; do
  case "$dir" in ''|\#*) continue ;; esac
  dir="${dir/#\~/$HOME}"
  case "$PWD/" in "$dir"/*) [ ${#dir} -gt $BEST ] && ORG="$org" && BEST=${#dir} ;; esac
done < "$HOME/.claude/workspace-orgs" 2>/dev/null
```

If `ORG` is empty, print the usage error above and stop. Outside a mapped tree
there is no org to resolve against, and guessing one risks cloning an unrelated
public repo that happens to share the name.

Otherwise look the name up in `$ORG` — exact match first:

```bash
gh repo list "$ORG" --limit 1000 --json name,url \
  | jq -r --arg n "$ARG" '.[] | select((.name|ascii_downcase) == ($n|ascii_downcase)) | .url'
```

If that returns nothing, retry as a substring match
(`select(.name|ascii_downcase|contains($n|ascii_downcase))`). Then:

| Matches   | Action                                                            |
| --------- | ----------------------------------------------------------------- |
| exactly 1 | use that URL, and name the resolution in the step 7 summary       |
| 0         | stop: `❌ No repo matching "<name>" in <org>` + suggest `gh repo list <org>` |
| 2 or more | stop, print the candidate names, ask which one                     |

Never pick from an ambiguous match. Cloning the wrong private repo looks like
success, and unwinding it (delete the workspace, re-run, re-install) costs far
more than one question.

`gh repo list` needs an authenticated `gh` (`gh auth login`); if it errors,
report that rather than falling back to a guessed URL.

### 2. Derive names and paths

```bash
URL="<the url>"
PARENT="${INTO:-$PWD}"                      # --into, else cwd
SLUG="${URL%/}"; REPO_NAME=$(basename "${SLUG%.git}")   # strip trailing / then .git
REPO_NAME="${NAME:-$REPO_NAME}"             # --name override
REPO_NAME=$(printf '%s' "$REPO_NAME" | tr '[:upper:]' '[:lower:]')   # always lowercase
WORKSPACE="$PARENT/${REPO_NAME}-workspace"
```

Never derive the name from anything but the URL's last path segment (minus
`.git`) unless `--name` was passed — the directory name is how the user finds
the workspace later. This holds for bare-name input too: derive from the URL
step 1 resolved to, not from what the user typed.

**Always lowercase both the workspace directory and the clone directory**, even
when the repo's canonical casing is mixed (`acme/MyApi` →
`myapi-workspace/myapi`), and even for a `--name` override. Every workspace
in the tree is lowercase, and macOS's case-insensitive filesystem makes a
later case-only rename a two-step `mv` that also breaks pnpm's `.bin` shims
(they hard-code the absolute path), forcing a reinstall.

### 3. Check for conflicts

Stop rather than clobber or merge into an existing tree:

```bash
[ -e "$WORKSPACE" ] && echo "❌ $WORKSPACE already exists — remove it or pass --name" && exit 1
```

Also confirm `$PARENT` exists and is a directory; if not, report it and stop
(do not create arbitrary parent trees).

### 4. Create the layout and clone

```bash
mkdir -p "$WORKSPACE/worktrees"
git clone "$URL" "$WORKSPACE/$REPO_NAME"
```

If the clone fails, **remove the workspace directory you just created** so a
retry starts clean, then report the git error verbatim. Common causes worth
naming in the report:

- private repo without credentials → `gh auth login`, or use the SSH URL
- host key / SSH agent issues → `ssh -T git@github.com` to check

### 5. Install dependencies (unless `--no-install`)

Detect the package manager from lock files in the clone and run install from
inside `$WORKSPACE/$REPO_NAME`:

| Lock file           | Command        |
| ------------------- | -------------- |
| `pnpm-lock.yaml`    | `pnpm install` |
| `yarn.lock`         | `yarn install` |
| `bun.lockb`         | `bun install`  |
| `package-lock.json` | `npm install`  |
| none                | skip, note it  |

If install fails, report the error but **keep going** — the workspace itself is
still valid and the user can install manually.

Do not run any other post-clone setup (no env files, no ports, no builds) —
that is `/worktree`'s job, per-branch. Step 6 is the one exception: it is
repo-level, not per-branch, and `/worktree` depends on it having run.

### 6. Generate agent config (rulesync)

Many repos gitignore `.mcp.json`, `.claude/`, and `.cursor/` and generate them
from a checked-in `.rulesync/` directory. A fresh clone therefore has **no MCP
servers at all** until the generator runs — the symptom is "the Linear/serena
tools just aren't there", with nothing in the config to explain it.

Run it only when the repo opts in (a `.rulesync/` directory **and** a `rulesync`
script in `package.json`), from inside the clone, using the repo's own pinned
version — never `pnpm dlx`/`npx`, which would run a version the repo did not
choose:

```bash
CLONE="$WORKSPACE/$REPO_NAME"
RS=""
[ -f "$CLONE/pnpm-lock.yaml" ]    && RS="pnpm rulesync"
[ -f "$CLONE/yarn.lock" ]         && RS="yarn rulesync"
[ -f "$CLONE/bun.lockb" ]         && RS="bun run rulesync"
[ -f "$CLONE/package-lock.json" ] && RS="npm run rulesync"

if [ ! -d "$CLONE/.rulesync" ]; then
  :   # repo does not use rulesync — nothing to do, say nothing
elif [ -z "$RS" ] || ! grep -q '"rulesync"' "$CLONE/package.json" 2>/dev/null; then
  echo "⚠️  .rulesync/ present but no 'rulesync' script + lock file — generate agent config manually."
elif [ ! -d "$CLONE/node_modules" ]; then
  echo "⚠️  not installed (--no-install or install failed) — run later: (cd \"$CLONE\" && $RS)"
elif ( cd "$CLONE" && $RS ); then
  echo "✅ agent config generated (.mcp.json, .claude/, .cursor/)"
else
  echo "⚠️  '$RS' failed — run it manually: (cd \"$CLONE\" && $RS)"
fi
```

This must run **after** step 5: the generator is a devDependency, so it needs
`node_modules`. With `--no-install`, or when install failed, report the command
and move on rather than trying to bootstrap the toolchain.

If `.mcp.json` was produced, name the servers it declares in the step 7 summary
and flag any that are **not** in `enabledMcpjsonServers` in user-scope
`~/.claude/settings.json` — those tools will be silently absent until approved.
Servers reached over `mcp-remote` (e.g. Linear) additionally need an interactive
OAuth login on first connect.

### 7. Print the summary

```
✅ Workspace ready!

Path:    <workspace>
Repo:    <workspace>/<repo-name>  (branch: <default-branch>)
Worktrees: <workspace>/worktrees  (empty)
Install: pnpm install ✅   ← or "skipped (no lock file)" / the failure
Agent config: rulesync ✅ — .mcp.json: linear-server, serena, …   ← omit if the repo has no .rulesync/
MCP:     ⚠️  <name> not in enabledMcpjsonServers — tools absent until approved   ← omit if all approved

Next:
  cd <workspace>/<repo-name>
  /worktree feat/my-branch     # lands in <workspace>/worktrees/my-branch
```

Report the actual default branch from the clone (`git -C "$WORKSPACE/$REPO_NAME"
branch --show-current`), not an assumed `main`.

If the argument was a bare name, add a line naming what it resolved to, so the
user can catch a wrong match immediately:

```
Resolved: my-api → https://github.com/acme-inc/my-api (private)
```

## Notes

- Idempotency: the skill refuses to touch an existing `*-workspace` directory.
  To re-clone, remove it first or pass `--name`.
- The clone stays on its default branch and should be treated as the
  integration checkout — feature work belongs in `worktrees/` via `/worktree`.
- `worktrees/` is deliberately created empty; `/worktree` detects it by looking
  for a `worktrees` directory beside the repo root.
- Step 6 exists because `.mcp.json` is a **generated, gitignored** artifact in
  many repos. Without it a fresh clone silently has zero MCP servers, and
  `/worktree` has nothing at the repo root to copy into new worktrees — so the
  gap propagates to every branch. Generating once, here, fixes both.
- Bare-name resolution is scoped to mapped directory trees on purpose. It is a
  convenience for orgs with a known layout, not a general "search GitHub for
  something like this" feature.
