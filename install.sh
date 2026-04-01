#!/bin/bash
# Claude Sentinel v3.0 - Installation Script
# The full Claude Code discipline layer.
#
# Usage:
#   ./install.sh                  # Install routing + Claude Code hooks
#   ./install.sh --git-hooks      # Also install git hooks (global or per-repo)
#   ./install.sh --force          # Auto-merge into existing settings.json
#   ./install.sh --update         # Update existing install, preserve config
#   ./install.sh --all            # Everything: routing + Claude hooks + git hooks

set -e

VERSION="5.0.0"
PLUGIN_DIR="$HOME/.claude/plugins/sentinel"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Parse flags ---
FLAG_GIT_HOOKS=0
FLAG_FORCE=0
FLAG_UPDATE=0
FLAG_ALL=0

for arg in "$@"; do
  case "$arg" in
    --git-hooks) FLAG_GIT_HOOKS=1 ;;
    --force)     FLAG_FORCE=1 ;;
    --update)    FLAG_UPDATE=1 ;;
    --all)       FLAG_ALL=1; FLAG_GIT_HOOKS=1; FLAG_FORCE=1 ;;
  esac
done

echo ""
echo "+---------------------------------------------------------+"
echo "|  Claude Sentinel v${VERSION} - Installation              |"
echo "+---------------------------------------------------------+"
echo ""

# --- Pre-flight ---

if ! command -v python3 &> /dev/null; then
  echo "  ERROR: Python 3 is required."
  exit 1
fi
echo "  Python 3: $(python3 --version 2>&1)"

if command -v claude &> /dev/null; then
  echo "  Claude Code: found"
else
  echo "  Claude Code: not in PATH (hook will activate when available)"
fi

echo ""

# --- Check for existing install ---

INSTALLED_VERSION=""
if [ -f "$PLUGIN_DIR/plugin.json" ]; then
  INSTALLED_VERSION=$(python3 -c "import json; print(json.load(open('$PLUGIN_DIR/plugin.json')).get('version','unknown'))" 2>/dev/null || echo "unknown")
  echo "  Existing install: v${INSTALLED_VERSION}"

  if [ "$FLAG_UPDATE" -eq 1 ]; then
    echo "  Mode: update (preserving config files)"
  else
    echo "  Mode: fresh install (config will be reset)"
  fi
else
  echo "  No existing install found."
fi
echo ""

# --- Install plugin files ---

echo "  Installing core files..."
mkdir -p "$PLUGIN_DIR"/{hooks,config,logs,agents,commands}

# Core hooks (always overwrite)
cp "$SCRIPT_DIR/plugin/hooks/sentinel.py" "$PLUGIN_DIR/hooks/"
cp "$SCRIPT_DIR/plugin/hooks/cost_report.py" "$PLUGIN_DIR/hooks/"
cp "$SCRIPT_DIR/plugin/hooks/pre_tool_use.sh" "$PLUGIN_DIR/hooks/"
cp "$SCRIPT_DIR/plugin/hooks/post_tool_use.sh" "$PLUGIN_DIR/hooks/"
cp "$SCRIPT_DIR/plugin/hooks/stop_hook.sh" "$PLUGIN_DIR/hooks/"
cp "$SCRIPT_DIR/plugin/plugin.json" "$PLUGIN_DIR/"

chmod +x "$PLUGIN_DIR/hooks/"*.py "$PLUGIN_DIR/hooks/"*.sh

# Config files — preserve on update, overwrite on fresh install
if [ "$FLAG_UPDATE" -eq 1 ]; then
  # Only copy if file doesn't exist
  [ ! -f "$PLUGIN_DIR/config/patterns.json" ] && cp "$SCRIPT_DIR/plugin/config/patterns.json" "$PLUGIN_DIR/config/"
  [ ! -f "$PLUGIN_DIR/config/budget.json" ] && cp "$SCRIPT_DIR/plugin/config/budget.json" "$PLUGIN_DIR/config/"
else
  cp "$SCRIPT_DIR/plugin/config/patterns.json" "$PLUGIN_DIR/config/"
  [ ! -f "$PLUGIN_DIR/config/budget.json" ] && cp "$SCRIPT_DIR/plugin/config/budget.json" "$PLUGIN_DIR/config/"
fi

# Agents and commands
cp "$SCRIPT_DIR/agents/router-advisor.md" "$PLUGIN_DIR/agents/"
cp "$SCRIPT_DIR/commands/cost-report.md" "$PLUGIN_DIR/commands/"
cp "$SCRIPT_DIR/commands/budget-check.md" "$PLUGIN_DIR/commands/"

echo "  Core files installed."

# --- Wire Claude Code settings.json ---

echo ""
echo "  Configuring Claude Code hooks..."

HOOKS_JSON='{
  "UserPromptSubmit": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "python3 ~/.claude/plugins/sentinel/hooks/sentinel.py"
        }
      ]
    }
  ],
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.claude/plugins/sentinel/hooks/pre_tool_use.sh"
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Write|Edit|Bash|Agent|Read|Glob|Grep",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.claude/plugins/sentinel/hooks/post_tool_use.sh"
        }
      ]
    }
  ],
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.claude/plugins/sentinel/hooks/stop_hook.sh"
        }
      ]
    }
  ]
}'

if [ ! -f "$SETTINGS" ]; then
  echo "$HOOKS_JSON" | python3 -c "
import sys, json
hooks = json.load(sys.stdin)
settings = {'hooks': hooks}
with open('$SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
print('  Created settings.json with all hooks.')
"
elif [ "$FLAG_FORCE" -eq 1 ]; then
  # Validate existing JSON first
  if ! python3 -c "import json; json.load(open('$SETTINGS'))" 2>/dev/null; then
    echo "  ERROR: Existing settings.json is malformed. Fix it manually first."
    echo "  Path: $SETTINGS"
    exit 1
  fi

  cp "$SETTINGS" "$SETTINGS.backup.$(date +%s)"
  echo "  Backup created."

  echo "$HOOKS_JSON" | python3 -c "
import sys, json

hooks_new = json.load(sys.stdin)
settings_path = '$SETTINGS'

with open(settings_path) as f:
    settings = json.load(f)

if 'hooks' not in settings:
    settings['hooks'] = {}

# Merge each hook type
for hook_type, hook_entries in hooks_new.items():
    if hook_type not in settings['hooks']:
        settings['hooks'][hook_type] = hook_entries
    else:
        # Check if sentinel is already present
        existing = json.dumps(settings['hooks'][hook_type])
        for entry in hook_entries:
            marker = json.dumps(entry)
            # Simple check: if the command isn't already present, add it
            cmd = entry.get('hooks', [{}])[0].get('command', '')
            if cmd and cmd not in existing:
                settings['hooks'][hook_type].append(entry)

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print('  Hooks merged into settings.json.')
"
else
  # Check what's missing
  MISSING=""
  grep -q "sentinel.py" "$SETTINGS" 2>/dev/null || MISSING="$MISSING UserPromptSubmit"
  grep -q "pre_tool_use.sh" "$SETTINGS" 2>/dev/null || MISSING="$MISSING PreToolUse"
  grep -q "post_tool_use.sh" "$SETTINGS" 2>/dev/null || MISSING="$MISSING PostToolUse"
  grep -q "stop_hook.sh" "$SETTINGS" 2>/dev/null || MISSING="$MISSING Stop"

  if [ -n "$MISSING" ]; then
    echo "  settings.json exists but is missing hooks:$MISSING"
    echo ""
    echo "  Run with --force to auto-merge, or add manually."
    echo "  See README for the full hooks JSON block."
  else
    echo "  All hooks already present in settings.json."
  fi
fi

# --- Git hooks ---

if [ "$FLAG_GIT_HOOKS" -eq 1 ]; then
  echo ""
  echo "  Installing git hooks..."

  # Copy git hooks to plugin directory
  cp "$SCRIPT_DIR/git-hooks/prepare-commit-msg" "$PLUGIN_DIR/hooks/"
  cp "$SCRIPT_DIR/git-hooks/commit-msg" "$PLUGIN_DIR/hooks/"
  cp "$SCRIPT_DIR/git-hooks/pre-push" "$PLUGIN_DIR/hooks/"
  chmod +x "$PLUGIN_DIR/hooks/prepare-commit-msg" "$PLUGIN_DIR/hooks/commit-msg" "$PLUGIN_DIR/hooks/pre-push"

  echo ""
  echo "  How would you like to install git hooks?"
  echo ""
  echo "  1) Global (all repos) — sets git config --global core.hooksPath"
  echo "  2) Current repo only — symlinks into .git/hooks/"
  echo "  3) Skip — I'll set it up myself"
  echo ""
  read -p "  Choice [1/2/3]: " HOOK_CHOICE

  case "$HOOK_CHOICE" in
    1)
      GIT_HOOKS_DIR="$PLUGIN_DIR/git-hooks"
      mkdir -p "$GIT_HOOKS_DIR"
      cp "$SCRIPT_DIR/git-hooks/"* "$GIT_HOOKS_DIR/"
      chmod +x "$GIT_HOOKS_DIR/"*
      git config --global core.hooksPath "$GIT_HOOKS_DIR"
      echo "  Global git hooks installed."
      echo "  core.hooksPath = $GIT_HOOKS_DIR"
      ;;
    2)
      if [ -d ".git" ]; then
        for hook in prepare-commit-msg commit-msg pre-push; do
          ln -sf "$PLUGIN_DIR/hooks/$hook" ".git/hooks/$hook"
        done
        echo "  Git hooks symlinked into current repo."
      else
        echo "  ERROR: Not in a git repository. cd into one first."
      fi
      ;;
    3)
      echo "  Skipped. To install later:"
      echo "    Global: git config --global core.hooksPath $PLUGIN_DIR/git-hooks"
      echo "    Per-repo: ln -sf $PLUGIN_DIR/hooks/commit-msg .git/hooks/commit-msg"
      ;;
  esac
fi

# --- Test ---

echo ""
echo "  Testing routing hook..."
RESULT=$(echo '{"prompt":"Show me the README"}' | python3 "$PLUGIN_DIR/hooks/sentinel.py" 2>&1)
if [ $? -eq 0 ] && echo "$RESULT" | grep -q "Recommendation"; then
  echo "  Routing hook: OK"
else
  echo "  Routing hook: FAILED — check installation"
fi

# Test git hooks
if [ "$FLAG_GIT_HOOKS" -eq 1 ]; then
  echo "  Testing git hooks..."

  # Test commit-msg strips AI trailers
  TEMP_MSG=$(mktemp)
  echo "feat: test commit" > "$TEMP_MSG"
  echo "" >> "$TEMP_MSG"
  echo "Co-Authored-By: Claude Code <noreply@anthropic.com>" >> "$TEMP_MSG"

  bash "$PLUGIN_DIR/hooks/commit-msg" "$TEMP_MSG" 2>/dev/null
  if grep -qi "claude" "$TEMP_MSG" 2>/dev/null; then
    echo "  commit-msg strip: FAILED"
  else
    echo "  commit-msg strip: OK"
  fi

  # Test conventional commit enforcement
  echo "bad message no prefix" > "$TEMP_MSG"
  if bash "$PLUGIN_DIR/hooks/commit-msg" "$TEMP_MSG" 2>/dev/null; then
    echo "  conventional commit: FAILED (should have blocked)"
  else
    echo "  conventional commit: OK (blocked non-conventional)"
  fi

  rm -f "$TEMP_MSG"
fi

# --- Summary ---

echo ""
echo "+---------------------------------------------------------+"
echo "|  Installation Complete — v${VERSION}                        |"
echo "+---------------------------------------------------------+"
echo ""
echo "  Installed:"
echo "    Routing:     ~/.claude/plugins/sentinel/hooks/sentinel.py"
echo "    Cost track:  ~/.claude/plugins/sentinel/hooks/cost_report.py"
echo "    PreToolUse:  ~/.claude/plugins/sentinel/hooks/pre_tool_use.sh"
echo "    PostToolUse: ~/.claude/plugins/sentinel/hooks/post_tool_use.sh"
echo "    Stop:        ~/.claude/plugins/sentinel/hooks/stop_hook.sh"
if [ "$FLAG_GIT_HOOKS" -eq 1 ]; then
  echo "    Git hooks:   prepare-commit-msg, commit-msg, pre-push"
fi
echo ""
echo "  Commands:"
echo "    Cost report:  python3 $PLUGIN_DIR/hooks/cost_report.py --week"
echo "    Budget check: python3 $PLUGIN_DIR/hooks/cost_report.py --all --project"
echo ""
echo "  Config:"
echo "    Patterns: $PLUGIN_DIR/config/patterns.json"
echo "    Budget:   $PLUGIN_DIR/config/budget.json"
echo ""
