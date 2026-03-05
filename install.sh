#!/bin/bash
# Claude Model Router v2.0 - Installation Script
# Installs the hook, agents, commands, and wires up settings.json

set -e

echo ""
echo "+---------------------------------------------------------+"
echo "|  Claude Model Router v2.0 - Installation                |"
echo "+---------------------------------------------------------+"
echo ""

# --- Pre-flight checks ---

if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is required but not installed."
    exit 1
fi
echo "  Python 3 found: $(python3 --version 2>&1)"

if ! command -v claude &> /dev/null; then
    echo "  WARNING: Claude Code CLI not found in PATH."
    echo "  The hook will be installed but may not activate until Claude Code is available."
fi

# --- Paths ---

PLUGIN_DIR="$HOME/.claude/plugins/model-router"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  Source:  $SCRIPT_DIR"
echo "  Target:  $PLUGIN_DIR"
echo ""

# --- Install plugin files ---

echo "  Installing plugin files..."
mkdir -p "$PLUGIN_DIR"/{hooks,config,logs}

cp "$SCRIPT_DIR/plugin/hooks/model_router.py" "$PLUGIN_DIR/hooks/"
cp "$SCRIPT_DIR/plugin/hooks/cost_report.py" "$PLUGIN_DIR/hooks/"
cp "$SCRIPT_DIR/plugin/config/patterns.json" "$PLUGIN_DIR/config/"
cp "$SCRIPT_DIR/plugin/plugin.json" "$PLUGIN_DIR/"

# Only copy budget.json if it doesn't exist (preserve user config)
if [ ! -f "$PLUGIN_DIR/config/budget.json" ]; then
    cp "$SCRIPT_DIR/plugin/config/budget.json" "$PLUGIN_DIR/config/"
fi

chmod +x "$PLUGIN_DIR/hooks/model_router.py"
chmod +x "$PLUGIN_DIR/hooks/cost_report.py"

echo "  Plugin files installed."

# --- Install agents (optional, into project .claude/agents/) ---

echo ""
echo "  Installing agents and commands..."
mkdir -p "$PLUGIN_DIR/agents"
mkdir -p "$PLUGIN_DIR/commands"

cp "$SCRIPT_DIR/agents/router-advisor.md" "$PLUGIN_DIR/agents/"
cp "$SCRIPT_DIR/commands/cost-report.md" "$PLUGIN_DIR/commands/"
cp "$SCRIPT_DIR/commands/budget-check.md" "$PLUGIN_DIR/commands/"

echo "  Agents and commands installed."

# --- Wire up settings.json ---

echo ""
echo "  Configuring Claude Code hooks..."

if [ ! -f "$SETTINGS" ]; then
    # Fresh install - create settings with hook
    cat > "$SETTINGS" << 'SETTINGS_EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/plugins/model-router/hooks/model_router.py"
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
    echo "  Created settings.json with hook."
else
    # Settings exists - check if hook is already present
    if grep -q "model_router.py" "$SETTINGS" 2>/dev/null; then
        echo "  Hook already present in settings.json."
    else
        echo ""
        echo "  NOTE: settings.json already exists."
        echo "  Add this to your ~/.claude/settings.json hooks section:"
        echo ""
        echo '  "hooks": {'
        echo '    "UserPromptSubmit": ['
        echo '      {'
        echo '        "hooks": ['
        echo '          {'
        echo '            "type": "command",'
        echo '            "command": "python3 ~/.claude/plugins/model-router/hooks/model_router.py"'
        echo '          }'
        echo '        ]'
        echo '      }'
        echo '    ]'
        echo '  }'
        echo ""
        echo "  Or run with --force to auto-merge (backs up existing settings first)."
        echo ""

        if [[ "$1" == "--force" ]]; then
            cp "$SETTINGS" "$SETTINGS.backup.$(date +%s)"
            echo "  Backup created. Merging hook into settings..."

            # Use python to merge the hook into existing settings
            python3 << 'MERGE_EOF'
import json

settings_path = "$HOME/.claude/settings.json".replace("$HOME", __import__('os').path.expanduser("~"))

with open(settings_path) as f:
    settings = json.load(f)

hook_entry = {
    "hooks": [
        {
            "type": "command",
            "command": "python3 ~/.claude/plugins/model-router/hooks/model_router.py"
        }
    ]
}

if 'hooks' not in settings:
    settings['hooks'] = {}

if 'UserPromptSubmit' not in settings['hooks']:
    settings['hooks']['UserPromptSubmit'] = []

# Check if already present
existing = settings['hooks']['UserPromptSubmit']
already = any('model_router.py' in str(h) for h in existing)

if not already:
    settings['hooks']['UserPromptSubmit'].append(hook_entry)

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print("  Hook merged into settings.json.")
MERGE_EOF
        fi
    fi
fi

# --- Test ---

echo ""
echo "  Testing hook..."
RESULT=$(echo '{"prompt":"Show me the README"}' | python3 "$PLUGIN_DIR/hooks/model_router.py" 2>&1)
if [ $? -eq 0 ]; then
    echo "  Hook is working. Sample output:"
    echo "$RESULT" | head -15
else
    echo "  WARNING: Hook test returned non-zero. Check the installation."
fi

# --- Summary ---

echo ""
echo "+---------------------------------------------------------+"
echo "|  Installation Complete                                   |"
echo "+---------------------------------------------------------+"
echo ""
echo "  Installed:"
echo "    Hook:     $PLUGIN_DIR/hooks/model_router.py"
echo "    Tracker:  $PLUGIN_DIR/hooks/cost_report.py"
echo "    Patterns: $PLUGIN_DIR/config/patterns.json"
echo "    Budget:   $PLUGIN_DIR/config/budget.json"
echo "    Agents:   $PLUGIN_DIR/agents/"
echo "    Commands: $PLUGIN_DIR/commands/"
echo "    Logs:     $PLUGIN_DIR/logs/cost_log.csv"
echo ""
echo "  Quick start:"
echo "    1. Wire the hook (see above if settings.json wasn't auto-configured)"
echo "    2. Start Claude Code and submit a prompt"
echo "    3. See model recommendations appear before each response"
echo "    4. Run: python3 $PLUGIN_DIR/hooks/cost_report.py --week"
echo ""
echo "  To use agents/commands in a project, symlink them:"
echo "    mkdir -p .claude/agents .claude/commands"
echo "    ln -s $PLUGIN_DIR/agents/router-advisor.md .claude/agents/"
echo "    ln -s $PLUGIN_DIR/commands/cost-report.md .claude/commands/"
echo "    ln -s $PLUGIN_DIR/commands/budget-check.md .claude/commands/"
echo ""
echo "  Customize:"
echo "    Patterns: $PLUGIN_DIR/config/patterns.json"
echo "    Budget:   $PLUGIN_DIR/config/budget.json"
echo ""
