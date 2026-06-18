#!/usr/bin/env bash
# claude-statusline installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/258468639/claude-statusline/main/install.sh | bash
#
# What it does:
#   1) Downloads statusline.sh to ~/.config/claude-statusline/statusline.sh
#   2) Writes statusLine config into ~/.claude/settings.json (merging, never overwriting)
#   3) Backs up the existing settings.json to settings.json.bak before any change
#
# Env vars:
#   CLAUDE_STATUS_REPO   override repo (default: 258468639/claude-statusline)
#   CLAUDE_STATUS_REF    git ref/branch (default: main)
#   CLAUDE_STATUS_DEST   install path for statusline.sh (default: ~/.config/claude-statusline/statusline.sh)

set -euo pipefail

REPO="${CLAUDE_STATUS_REPO:-258468639/claude-statusline}"
REF="${CLAUDE_STATUS_REF:-main}"
DEST="${CLAUDE_STATUS_DEST:-$HOME/.config/claude-statusline/statusline.sh}"
SETTINGS="$HOME/.claude/settings.json"
RAW_URL="https://raw.githubusercontent.com/$REPO/$REF/statusline.sh"

say()  { printf "\033[36m[claude-statusline]\033[0m %s\n" "$*"; }
err()  { printf "\033[31m[claude-statusline] error:\033[0m %s\n" "$*" >&2; }
warn() { printf "\033[33m[claude-statusline] warn:\033[0m %s\n" "$*" >&2; }

# 1. dependency check
need=""
for bin in jq curl; do
    command -v "$bin" >/dev/null 2>&1 || need="$need $bin"
done
if [ -n "$need" ]; then
    err "missing required dependencies:$need"
    err "install them via your package manager (brew/apt/etc) and retry"
    exit 1
fi
# soft deps used by the script at render time
for bin in bc git; do
    command -v "$bin" >/dev/null 2>&1 || warn "$bin not found — some fields will be missing at render time"
done

# 2. download
mkdir -p "$(dirname "$DEST")"
say "downloading $RAW_URL"
if ! curl -fsSL "$RAW_URL" -o "$DEST.tmp"; then
    err "download failed; check network or repo ref ($REPO@$REF)"
    rm -f "$DEST.tmp"
    exit 1
fi
mv "$DEST.tmp" "$DEST"
chmod +x "$DEST"
say "installed to $DEST"

# 3. wire up ~/.claude/settings.json
mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

# backup before modify
cp -p "$SETTINGS" "$SETTINGS.bak"
say "backed up existing settings to $SETTINGS.bak"

# merge using jq; preserves all existing keys
tmp=$(mktemp)
jq --arg cmd "$DEST" '. + {statusLine: {type: "command", command: $cmd}}' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"
say "updated $SETTINGS — statusLine now points to $DEST"

cat <<EOF

\033[32m✓ Done.\033[0m  Restart Claude Code (or open a new session) to see the status line.

Customize:
  Switch to English labels:    export CLAUDE_STATUSLINE_LANG=en
  Map model IDs to aliases:    edit ~/.config/claude-statusline/models.conf
                               (see examples/models.conf in the repo)

Uninstall:
  mv $SETTINGS.bak $SETTINGS
  rm $DEST
EOF
