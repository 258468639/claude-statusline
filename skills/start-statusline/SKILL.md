---
name: start-statusline
description: >
  Manage Claude Code statusline configuration. Use this skill when the user wants to
  start, restart, enable, or disable the statusline. Also use when the status bar
  disappears or shows incorrect information. Handles settings.json repair and
  statusline script management.
license: MIT
metadata:
  skill-author: custom
  skills-version: 1.0.0
  trigger-keywords: >
    启动 statusline, 重启 statusline, statusline 消失, statusline 不见了,
    statusline 出问题了, 启用状态栏, 关闭状态栏,
    start statusline, restart statusline, enable statusline, disable statusline,
    statusline broken, statusline missing
  run-in: sandbox
---

# start-statusline

## What This Skill Does

Manages the Claude Code statusline by:
1. Checking whether `statusLine` is present and correctly configured in `~/.claude/settings.json`
2. Repairing the config if missing or corrupted
3. Providing commands to enable / disable the statusline

## Key Paths

- **Settings**: `~/.claude/settings.json`
- **Script**: `~/.config/claude-statusline/statusline.sh`
- **Cache**: `~/.cache/claude-statusline/`

## How to Use

### 1. Check statusLine config

Read `~/.claude/settings.json` and check for the `statusLine` key:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/zengk-work/.config/claude-statusline/statusline.sh"
  }
}
```

If `statusLine` is `null`, missing, or not an object, it needs to be repaired.

### 2. Repair config (if missing)

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq --arg cmd "/Users/zengk-work/.config/claude-statusline/statusline.sh" \
  '. + {statusLine: {type: "command", command: $cmd}}' \
  ~/.claude/settings.json > /tmp/settings_fixed.json && \
mv /tmp/settings_fixed.json ~/.claude/settings.json
```

This merges the `statusLine` object into settings without touching other keys.

### 3. Enable statusline (force)

```bash
jq --arg cmd "/Users/zengk-work/.config/claude-statusline/statusline.sh" \
  '. + {statusLine: {type: "command", command: $cmd}}' \
  ~/.claude/settings.json > /tmp/settings_fixed.json && \
mv /tmp/settings_fixed.json ~/.claude/settings.json
```

### 4. Disable statusline

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq 'delpaths([["statusLine"]])' ~/.claude/settings.json > /tmp/settings_disabled.json && \
mv /tmp/settings_disabled.json ~/.claude/settings.json
```

### 5. Verify script exists

```bash
ls -la ~/.config/claude-statusline/statusline.sh
```

If the script does not exist, the user needs to reinstall it:
```bash
curl -fsSL https://raw.githubusercontent.com/258468639/claude-statusline/main/install.sh | bash
```

## Execution Steps

### Step 1: Diagnose

1. Read `~/.claude/settings.json` and check `statusLine` key
2. Check if `~/.config/claude-statusline/statusline.sh` exists and is executable
3. Report what is found

### Step 2: Repair if needed

- If `statusLine` is null/missing: merge it back using the jq command above
- If script missing: instruct user to run the install command
- If script not executable: run `chmod +x ~/.config/claude-statusline/statusline.sh`

### Step 3: Confirm

After repair, tell the user to send a message in Claude Code — the statusline should appear immediately. No restart of Claude Code is needed.

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Statusline gone | `statusLine` was nullified | Repair settings.json |
| Statusline gone | Script deleted | Reinstall via curl |
| Shows old model | Cache is stale | Cache auto-updates on next render |
| Script error | Missing deps | Check `jq`, `bc`, `git` are installed |

## Notes

- The statusline is invoked by Claude Code automatically on every message — no separate process needed
- Changing `settings.json` takes effect immediately (no restart required)
- `install.sh` can overwrite `statusLine` config, so always verify after running it
