# setup

My Claude Code setup: global instructions, settings, status line, commands and skills,
with an installer to put them on a new Mac.

Only general-purpose material lives here. Anything tied to a client or employer stays local
on the machine where that work happens. The installer links skills one by one, so local-only
skills in `~/.claude/skills` sit alongside these without conflict.

## What's inside

```
claude/
├── CLAUDE.md          global working notes (loaded in every session)
├── settings.json      effort, status line, read-only permission allowlist
├── statusline.sh      context-usage bar for the status line (needs jq)
├── commands/
│   └── worktree.md    /worktree: branch worktree with its own port, env and DB
├── templates/
│   └── export-to-html.txt
└── skills/
    ├── arch-map           interactive architecture dependency graph
    ├── babysit            keep a PR merge-ready: comments, conflicts, CI
    ├── export-html        save a conversation segment as styled HTML
    ├── extract-docs       web docs and videos into markdown
    ├── giff-it            screen-recorded GIFs that show native dialogs
    ├── lane-pr-comment    one concise PR review comment from a review/QA pass
    ├── lane-run           one ticket end to end in an isolated worktree lane
    ├── playwright-debug   repair a hanging or broken Playwright browser install
    ├── sketch-mockup      hand-drawn wireframe PNGs from a screenshot
    ├── stay-awake         keep the Mac awake for remote sessions
    └── workspace          clone a repo into <repo>-workspace/ with worktrees/
```

## New Mac

1. Install the basics:
   ```bash
   xcode-select --install
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew install git gh jq ffmpeg node pnpm
   brew install --cask google-chrome iterm2
   ```
2. Install Claude Code and sign in: `npm install -g @anthropic-ai/claude-code`, then run
   `claude` and log in. claude.ai connectors (Gmail, Drive, Slack, Docs) come back with the
   account.
3. Sign in to GitHub: `gh auth login`.
4. Clone and install:
   ```bash
   mkdir -p ~/Projects/personal
   git clone https://github.com/<you>/setup ~/Projects/personal/setup
   ~/Projects/personal/setup/install.sh --with-mcp
   ```
   Run with `--dry-run` first to see what it will do.
5. Optional integrations:
   - **iTerm2 status:** iTerm2 → Settings → enable the Claude Code integration. It installs
     its own hooks into `~/.claude/settings.json`.
   - **Claude in Chrome:** install the extension and sign in.
   - **Playwright browsers:** `npx playwright install chromium`. If it hangs, use
     `/playwright-debug`.
6. For `/workspace` short repo names, map directories to GitHub orgs in
   `~/.claude/workspace-orgs` (local only, not in this repo):
   ```
   ~/Projects/clients/acme   acme-inc
   ```

## Updating

Skills, commands, templates, `CLAUDE.md` and `statusline.sh` are symlinks into this repo, so
editing them in `~/.claude` edits the repo. Commit and push from here; `git pull` on the other
machine picks them up.

`settings.json` is a copy, because Claude Code writes to it. Copy changes over by hand.

## Not in this repo, on purpose

- Credentials, tokens, MCP environment values, `~/.claude.json`
- Session history, project memory, caches
- Client- or employer-specific skills, settings and instructions
