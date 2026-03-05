#!/bin/bash
# Claude Model Router v2.0 - Uninstallation Script

echo ""
echo "+---------------------------------------------------------+"
echo "|  Claude Model Router v2.0 - Uninstallation              |"
echo "+---------------------------------------------------------+"
echo ""

read -p "  Uninstall the Model Router hook? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "  Cancelled."
    exit 0
fi

PLUGIN_DIR="$HOME/.claude/plugins/model-router"
SETTINGS="$HOME/.claude/settings.json"

# Preserve logs if requested
if [ -d "$PLUGIN_DIR/logs" ]; then
    read -p "  Keep cost logs? (Y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        BACKUP_DIR="$HOME/.claude/model-router-logs-backup-$(date +%s)"
        cp -r "$PLUGIN_DIR/logs" "$BACKUP_DIR"
        echo "  Logs backed up to: $BACKUP_DIR"
    fi
fi

# Remove plugin directory
if [ -d "$PLUGIN_DIR" ]; then
    rm -rf "$PLUGIN_DIR"
    echo "  Plugin files removed."
else
    echo "  Plugin directory not found."
fi

# Remove hook from settings.json
if [ -f "$SETTINGS" ] && grep -q "model_router.py" "$SETTINGS" 2>/dev/null; then
    echo ""
    echo "  NOTE: Please remove the UserPromptSubmit hook entry from:"
    echo "  $SETTINGS"
    echo ""
    echo "  Look for and remove the block containing 'model_router.py'"
fi

echo ""
echo "  Uninstallation complete."
echo ""
