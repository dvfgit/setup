#!/usr/bin/env bash
# Install this Claude Code setup into ~/.claude.
#
#   ./install.sh              link config, commands, templates and skills
#   ./install.sh --with-mcp   also register the general MCP servers at user scope
#   ./install.sh --dry-run    print what would happen, change nothing
#
# Skills, commands, templates, CLAUDE.md and statusline.sh are symlinked, so a `git pull`
# here updates them in place. settings.json is copied (Claude Code rewrites it), and only
# when none exists yet. Anything already in the way is moved to ~/.claude/backups first.
# Skills that live only in ~/.claude/skills (e.g. client-specific ones) are left alone.
#
# CLAUDE_DIR overrides the target, for a dry run against a scratch directory:
#   CLAUDE_DIR=/tmp/claude-test ./install.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/claude"
DEST="${CLAUDE_DIR:-$HOME/.claude}"
BACKUP="$DEST/backups/setup-install-$(date +%Y%m%d-%H%M%S)"
WITH_MCP=0
DRY=0

for arg in "$@"; do
  case "$arg" in
    --with-mcp) WITH_MCP=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

run() { if [ "$DRY" = 1 ]; then echo "  would: $*"; else "$@"; fi; }

# Link $1 (repo path) to $2 (target path), backing up whatever is there unless it is
# already the right link.
link() {
  local from="$1" to="$2"
  if [ -L "$to" ] && [ "$(readlink "$to")" = "$from" ]; then
    echo "  ok      ${to#$DEST/}"
    return
  fi
  if [ -e "$to" ] || [ -L "$to" ]; then
    run mkdir -p "$BACKUP/$(dirname "${to#$DEST/}")"
    run mv "$to" "$BACKUP/${to#$DEST/}"
    echo "  backup  ${to#$DEST/} -> ${BACKUP#$DEST/}"
  fi
  run ln -s "$from" "$to"
  echo "  link    ${to#$DEST/}"
}

echo "Installing into $DEST"
run mkdir -p "$DEST/skills" "$DEST/commands" "$DEST/templates"

link "$SRC/CLAUDE.md" "$DEST/CLAUDE.md"
link "$SRC/statusline.sh" "$DEST/statusline.sh"
for f in "$SRC"/commands/*; do link "$f" "$DEST/commands/$(basename "$f")"; done
for f in "$SRC"/templates/*; do link "$f" "$DEST/templates/$(basename "$f")"; done
for d in "$SRC"/skills/*/; do d="${d%/}"; link "$d" "$DEST/skills/$(basename "$d")"; done

if [ -e "$DEST/settings.json" ]; then
  echo "  keep    settings.json (exists; compare with: diff $DEST/settings.json $SRC/settings.json)"
else
  run cp "$SRC/settings.json" "$DEST/settings.json"
  echo "  copy    settings.json"
fi

if [ "$WITH_MCP" = 1 ]; then
  if ! command -v claude >/dev/null; then
    echo "  skip    MCP servers: the claude CLI is not on PATH" >&2
  else
    echo "Registering MCP servers at user scope"
    claude mcp get context7 >/dev/null 2>&1 \
      && echo "  ok      context7" \
      || run claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp@latest
    claude mcp get playwright >/dev/null 2>&1 \
      && echo "  ok      playwright" \
      || run claude mcp add --scope user playwright -- npx -y @playwright/mcp@latest --browser chromium
  fi
fi

missing=()
for bin in jq gh ffmpeg git node; do command -v "$bin" >/dev/null || missing+=("$bin"); done
if [ "${#missing[@]}" -gt 0 ]; then
  echo
  echo "Missing tools some skills rely on: ${missing[*]}"
  echo "  brew install ${missing[*]/node/node pnpm}"
fi

echo
echo "Done. Start a new Claude Code session to pick up the skills."
