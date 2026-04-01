#!/bin/bash
# Claude Sentinel v3.0 - Uninstallation Script

echo ""
echo "+---------------------------------------------------------+"
echo "|  Claude Sentinel v3.0 - Uninstallation              |"
echo "+---------------------------------------------------------+"
echo ""

read -p "  Uninstall the Sentinel? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "  Cancelled."
  exit 0
fi

PLUGIN_DIR="$HOME/.claude/plugins/sentinel"

# Preserve logs
if [ -d "$PLUGIN_DIR/logs" ]; then
  read -p "  Keep cost/session logs? (Y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    BACKUP_DIR="$HOME/.claude/sentinel-logs-backup-$(date +%s)"
    cp -r "$PLUGIN_DIR/logs" "$BACKUP_DIR"
    echo "  Logs backed up to: $BACKUP_DIR"
  fi
fi

# Remove global git hooks if set
CURRENT_HOOKS_PATH=$(git config --global core.hooksPath 2>/dev/null || echo "")
if echo "$CURRENT_HOOKS_PATH" | grep -q "sentinel"; then
  git config --global --unset core.hooksPath
  echo "  Global git hooks path removed."
fi

# Remove plugin directory
if [ -d "$PLUGIN_DIR" ]; then
  rm -rf "$PLUGIN_DIR"
  echo "  Plugin files removed."
fi

echo ""
echo "  NOTE: Please remove the hooks entries from:"
echo "  ~/.claude/settings.json"
echo ""
echo "  Look for and remove blocks containing:"
echo "    sentinel.py"
echo "    pre_tool_use.sh"
echo "    post_tool_use.sh"
echo "    stop_hook.sh"
echo ""
echo "  Uninstallation complete."
echo ""
