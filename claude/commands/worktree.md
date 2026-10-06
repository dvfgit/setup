# WORKTREE Task

## Task Objective

Create an isolated git worktree for parallel feature development — with its own branch, symlinked tooling, and installed dependencies — in a single command.

**Arguments:** `$ARGUMENTS` (required — the branch name, e.g. `feat/mik-700-my-feature` or `mik-700`)

---

## Task Instructions

1. **Validate arguments:**

   Check that `$ARGUMENTS` is not empty. If it is empty, print an error and stop:

   ```
   ❌ Error: branch name is required.
   Usage: /worktree <branch-name>
   Example: /worktree feat/mik-700-my-feature
   ```

2. **Derive names and paths:**

   - Strip any `feat/`, `feature/`, `fix/`, `chore/`, `refactor/`, or `docs/` prefix from `$ARGUMENTS` to get `<short-name>`.
   - Set `<branch-name>` = `$ARGUMENTS` (full value, unchanged).
   - Capture the repo root and project name:

     ```bash
     REPO_ROOT=$(git rev-parse --show-toplevel)
     PROJECT_NAME=$(basename "$REPO_ROOT")
     ```

   - Resolve the worktree base directory:

     ```bash
     WORKSPACE_DIR=$(dirname "$REPO_ROOT")
     if [ -d "$WORKSPACE_DIR/worktrees" ]; then
       WORKTREES_BASE="$WORKSPACE_DIR/worktrees"
     else
       WORKTREES_BASE="$HOME/.cursor/worktrees/$PROJECT_NAME"
     fi
     ```

   - Set `<worktree-path>` = `$WORKTREES_BASE/<short-name>`

3. **Check for conflicts:**

   Run:
   ```bash
   git worktree list
   ```

   If `<worktree-path>` already appears in the list, print an error and stop:

   ```
   ❌ Error: worktree already exists at $WORKTREES_BASE/<short-name>
   Remove it first with: git worktree remove $WORKTREES_BASE/<short-name>
   ```

4. **Create the git worktree:**

   First check whether the remote branch already exists:

   ```bash
   mkdir -p "$WORKTREES_BASE"
   git fetch origin <branch-name> 2>/dev/null || true
   ```

   - If `origin/<branch-name>` exists after the fetch, create the worktree tracking it:

     ```bash
     git worktree add "$WORKTREES_BASE/<short-name>" -b <branch-name> origin/<branch-name>
     git -C "$WORKTREES_BASE/<short-name>" branch --set-upstream-to=origin/<branch-name> <branch-name>
     ```

   - Otherwise, create a fresh local branch from HEAD:

     ```bash
     git worktree add "$WORKTREES_BASE/<short-name>" -b <branch-name>
     ```

   You can detect which case applies by checking `git rev-parse --verify origin/<branch-name>` after the fetch — exit code 0 means the remote ref exists.

5. **Symlink shared tooling directories:**

   `.claude/` and `.cursor/` are gitignored and absent from fresh worktrees. Symlink them so all worktrees share the same up-to-date config.

   Note: symlink only **subdirectories**, never `.claude/` as a whole — some repos commit or generate `.claude/settings.json`, and replacing the directory would shadow it. But do not assume `.claude/` exists: where the whole directory is gitignored it is absent from a fresh worktree, so `mkdir -p` it first or every `ln` fails with "No such file or directory".

   ```bash
   WT="$WORKTREES_BASE/<short-name>"
   mkdir -p "$WT/.claude"
   for dir in commands rules agents skills memory; do
     src="$REPO_ROOT/.claude/$dir"
     [ -e "$src" ] && ln -sfn "$src" "$WT/.claude/$dir"
   done

   ln -sfn "$REPO_ROOT/.cursor" "$WT/.cursor"
   ```

   `skills` matters as much as `commands`: without it a repo's skill router cannot resolve its slash-skills inside the worktree. Dirs absent from the repo root are simply skipped.

6. **Configure environment (free-port `.envrc`/`.env`):**

   Clone the repo's env config into the worktree and assign a **free port**, so each worktree can run its own dev server without colliding. Skip if the worktree already has an env file.

   ```bash
   WT="$WORKTREES_BASE/<short-name>"
   # 6a. Pick the canonical env template from the repo root (first match wins)
   ENV_SRC=""
   for f in .envrc .env.local .env .env.example .env.sample; do
     [ -f "$REPO_ROOT/$f" ] && { ENV_SRC="$f"; break; }
   done

   if [ -z "$ENV_SRC" ]; then
     echo "ℹ️  No env template in repo root — skipping env config."
   elif [ -e "$WT/$ENV_SRC" ]; then
     echo "ℹ️  $ENV_SRC already present in the worktree — leaving as-is."
   else
     # 6b. Free port: skip the repo's base port (reserved for the main checkout), any port a
     #     sibling worktree's MANAGED env file ($ENV_SRC only — not committed .env.test/.env.e2e
     #     fixtures), and anything currently LISTENing.
     base=$(grep -oE 'localhost:[0-9]+|PORT=[0-9]+' "$REPO_ROOT/$ENV_SRC" | grep -oE '[0-9]+' | head -1)
     base=${base:-3000}
     claimed=$( { echo "$base"; find "$WORKTREES_BASE" -maxdepth 2 -name "$ENV_SRC" 2>/dev/null \
               | xargs grep -hoE 'PORT=[0-9]+' 2>/dev/null | grep -oE '[0-9]+'; } | sort -u )
     port=$base
     while lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || printf '%s\n' "$claimed" | grep -qx "$port"; do
       port=$((port+1))
     done
     # 6c. Copy template; retarget the port (PORT + any localhost:<port> URL); keep file:./ DB paths relative
     tmp=$(mktemp)
     sed -E "s#localhost:[0-9]+#localhost:$port#g" "$REPO_ROOT/$ENV_SRC" \
       | sed -E "s#^(export )?PORT=[0-9]+#\1PORT=$port#" > "$tmp"
     grep -qE '^(export )?PORT=' "$tmp" || { [ "$ENV_SRC" = .envrc ] && echo "export PORT=$port" >> "$tmp" || echo "PORT=$port" >> "$tmp"; }
     mv "$tmp" "$WT/$ENV_SRC"
     echo "✅ $ENV_SRC written with PORT=$port"
     # 6d. direnv .envrc → allow it (user's own repo) so it's ready to source
     [ "$ENV_SRC" = .envrc ] && command -v direnv >/dev/null 2>&1 && (cd "$WT" && direnv allow) && echo "✅ direnv allowed"
   fi
   ```

   - `DATABASE_URL=file:./…` stays a **relative** path so each worktree resolves its own DB under its own directory — do not absolutize it.
   - The free-port scan skips both live (LISTENing) ports and ports already claimed by sibling worktrees' env files, so concurrent worktrees never collide.

7. **Install dependencies:**

   Auto-detect the package manager from lock files in the repo root:

   - `pnpm-lock.yaml` → `pnpm install`
   - `yarn.lock` → `yarn install`
   - `bun.lockb` → `bun install`
   - `package-lock.json` → `npm install`
   - No lock file → print a warning and skip

   Run the detected install command from the worktree directory.

8. **Verify MCP availability (cannot be auto-approved — verify and report):**

   `.mcp.json` is typically **gitignored and generated** (e.g. by rulesync from `.rulesync/mcp.json`), so a fresh worktree may not have it. Even when present, Claude Code approves project MCP servers **per absolute path**, and a worktree is a new path — so its servers are unapproved by default and their tools are silently absent.

   There is **no non-interactive way to pre-approve** project MCP servers for a new directory: no CLI flag, no env var, and a committed `.claude/settings.json` is *ignored* in an untrusted folder. Only **user-scope** `~/.claude/settings.json` applies to untrusted folders. So this step verifies and reports; it must not try to write approval state.

   This step runs **after** Step 7 by design: generating `.mcp.json` needs the repo's own toolchain, and on most repos `install`'s `postinstall` already regenerates it — attempting it against an empty `node_modules` just fails.

   ```bash
   WT="$WORKTREES_BASE/<short-name>"
   # 8a. Give the worktree a .mcp.json. COPY the repo root's first — do not regenerate when a
   #     copy will do. `.mcp.json` is gitignored, so it is always absent from a fresh worktree,
   #     and on most repos `install`'s postinstall does NOT produce it (e.g. a
   #     postinstall of `prisma generate && setup-repo`, which never runs rulesync).
   #
   #     Copy rather than generate because a generator like `rulesync generate` writes ALL its
   #     agent outputs — .claude/rules, .claude/skills, .claude/commands, .cursor — and Step 5
   #     just symlinked those directories to the main checkout. Running it inside the worktree
   #     therefore writes THROUGH those symlinks and mutates the main repo. So when there is
   #     no .mcp.json to copy, run the generator AT THE REPO ROOT instead — that is where those
   #     outputs belong — and copy the result. Never `pnpm dlx`/`npx` a generator: that pins a
   #     version the repo did not choose; use the repo’s own script.
   #
   #     Copying is safe when the file carries no absolute paths — check once per repo. Server
   #     entries using a relative project path (e.g. serena's `--project .`) resolve per-worktree
   #     correctly, which is exactly what you want.
   if [ ! -f "$WT/.mcp.json" ]; then
     if [ -f "$REPO_ROOT/.mcp.json" ]; then
       cp "$REPO_ROOT/.mcp.json" "$WT/.mcp.json" && echo "✅ .mcp.json copied from the repo root"
     elif [ -f "$REPO_ROOT/.rulesync/mcp.json" ]; then
       # Nothing to copy — generate it at the REPO ROOT (never in the worktree; see above),
       # via the repo’s own script so the version the repo pinned is the one that runs.
       RS=""
       [ -f "$REPO_ROOT/pnpm-lock.yaml" ]    && RS="pnpm rulesync"
       [ -f "$REPO_ROOT/yarn.lock" ]         && RS="yarn rulesync"
       [ -f "$REPO_ROOT/bun.lockb" ]         && RS="bun run rulesync"
       [ -f "$REPO_ROOT/package-lock.json" ] && RS="npm run rulesync"
       if [ -z "$RS" ] || ! grep -q '"rulesync"' "$REPO_ROOT/package.json" 2>/dev/null; then
         echo "⚠️  .rulesync/mcp.json exists but no 'rulesync' script + lock file at the repo root — generate it manually."
       elif [ ! -d "$REPO_ROOT/node_modules" ]; then
         echo "⚠️  repo root not installed — install there, then: (cd \"$REPO_ROOT\" && $RS)"
       elif ( cd "$REPO_ROOT" && $RS ) >/dev/null 2>&1 && [ -f "$REPO_ROOT/.mcp.json" ]; then
         cp "$REPO_ROOT/.mcp.json" "$WT/.mcp.json" && echo "✅ .mcp.json generated at the repo root ($RS) and copied"
       else
         echo "⚠️  '$RS' failed at the repo root — run it manually: (cd \"$REPO_ROOT\" && $RS)"
       fi
     fi
   fi
   # 8b. Report whether user-scope settings will auto-approve them
   python3 - "$WT" <<'EOF'
import json, os, sys
wt = sys.argv[1]
mcp = os.path.join(wt, ".mcp.json")
if not os.path.exists(mcp):
    print("ℹ️  MCP: no .mcp.json in the worktree — no project MCP servers to approve.")
    raise SystemExit
names = sorted(json.load(open(mcp)).get("mcpServers", {}))
s = os.path.expanduser("~/.claude/settings.json")
u = json.load(open(s)) if os.path.exists(s) else {}
allowed = set(u.get("enabledMcpjsonServers") or [])
if u.get("enableAllProjectMcpServers"):
    print(f"✅ MCP: {len(names)} server(s) auto-approved via user-scope enableAllProjectMcpServers.")
elif allowed.issuperset(names):
    print(f"✅ MCP: {len(names)} server(s) auto-approved via user-scope enabledMcpjsonServers.")
else:
    missing = [n for n in names if n not in allowed]
    print(f"⚠️  MCP: {', '.join(missing)} NOT pre-approved — their tools will be MISSING here.")
    print("    Fix once, for all future worktrees, in ~/.claude/settings.json:")
    print(f'      "enabledMcpjsonServers": {json.dumps(names)}')
    print("    Or approve just this worktree: run /mcp and accept the trust prompt.")
EOF
   ```

   - The worktree's freshly generated `.mcp.json` can declare **more** servers than the main checkout's, whose `.mcp.json` may be stale from an older install. Report the diff — a newly added server is exactly the one missing from `enabledMcpjsonServers`, and it is missing in the main checkout too, just not yet visible there.
   - Generating at the repo root is a **write to the main checkout**: `rulesync generate` rewrites every agent output (`.claude/rules`, `.claude/skills`, `.claude/commands`, `.cursor`, `AGENTS.md`), and with `"delete": true` in `rulesync.jsonc` it also drops outputs no longer backed by a file under `.rulesync/` — hand-edits to those generated directories do not survive it. All of it is gitignored, so `git status` stays clean either way.
- Do **not** edit `~/.claude.json` to fake approval — Claude Code owns that file and a running session will clobber the write.
   - Servers reached over `mcp-remote` (e.g. Linear) additionally need an interactive OAuth login on first connect, so they can never come up in a headless or cron run.

9. **Print setup summary:**

   Include a `Tracking:` line that reflects whether the branch has a remote upstream:

   - If the branch tracks `origin/<branch-name>`: `Tracking: origin/<branch-name> (remote)`
   - If the branch is local-only: `Tracking: (local only — no remote upstream)`

   ```
   ✅ Worktree ready!

   Branch:   <branch-name>
   Tracking: origin/<branch-name> (remote)   ← or "(local only — no remote upstream)"
   Path:     $WORKTREES_BASE/<short-name>
   Port:     <port>   ← assigned in Step 6 (PORT + localhost URLs retargeted); omit if no env template
   MCP:      <the ✅/⚠️/ℹ️ line from Step 8 — verbatim>

   To start dev:
     cd $WORKTREES_BASE/<short-name>
     direnv allow          # if the repo uses .envrc
     <your dev command>    # serves on the assigned port

   To clean up when done:
     git worktree remove $WORKTREES_BASE/<short-name>
     git branch -d <branch-name>
   ```

---

## Notes

- The worktree is branched from whatever HEAD the current session is on.
- `.claude/commands`, `.claude/rules`, `.claude/agents`, `.claude/memory`, and `.cursor` are symlinked — changes in the main repo are instantly reflected in all worktrees.
- Env config is cloned automatically from the repo's `.envrc`/`.env*` template with a free port assigned (Step 6); `DATABASE_URL` stays relative so each worktree gets its own DB.
- MCP servers are **verified, not approved** (Step 8). Claude Code keys MCP approval by absolute path, so every worktree starts unapproved and its MCP tools are silently absent — the usual symptom is "the Linear/serena tools just aren't there". The durable fix is `enabledMcpjsonServers` in **user-scope** `~/.claude/settings.json`; a committed `.claude/settings.json` does not work because a fresh worktree is an untrusted folder.
- If dependency installation fails, report the error but still print the summary so the worktree path and branch are visible.

## Optional: seeding the worktree DB

The worktree DB is **not** seeded by setup — on most stacks `install`/`postinstall` and the dev server only run client codegen (e.g. `prisma generate`), not a data seed. So a fresh worktree comes up with an empty/absent DB. Seed it explicitly when you need data:

- Run the project's seed/reset path (e.g. `pnpm prisma:reset`), **or** use your normal seeding flow (e.g. POST to the State API once the dev server is up).
- For *instant* data without a seed run, copy a pre-seeded DB file — but only off a worktree on the **same schema**, and re-run the schema push if this worktree later changes it:

  ```bash
  [ -f "$REPO_ROOT/prisma/dev.db" ] && cp "$REPO_ROOT/prisma/dev.db" "$WT/prisma/dev.db"
  ```
