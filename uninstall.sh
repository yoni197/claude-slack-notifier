#!/bin/bash
# Claude Slack Notifier - Uninstaller

PLUGIN_DIR="$HOME/.claude/plugins/claude-slack-notifier"
CONFIG_FILE="$HOME/.claude/slack-notifier.conf"

echo "Uninstalling Claude Slack Notifier..."

if [ -d "$PLUGIN_DIR" ]; then
  rm -rf "$PLUGIN_DIR"
  echo "✅ Plugin directory removed: $PLUGIN_DIR"
else
  echo "Plugin directory not found: $PLUGIN_DIR"
fi

echo ""
read -p "Remove config file (~/.claude/slack-notifier.conf)? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  rm -f "$CONFIG_FILE"
  echo "✅ Config file removed"
else
  echo "Config file kept: $CONFIG_FILE"
fi

echo ""
echo "✅ Claude Slack Notifier uninstalled."
