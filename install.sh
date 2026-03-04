#!/bin/bash
# Claude Slack Notifier - Installer

set -e

PLUGIN_DIR="$HOME/.claude/plugins/claude-slack-notifier"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Claude Slack Notifier..."

# Create plugin directory
mkdir -p "$PLUGIN_DIR"

# Copy plugin files
cp -r "$SCRIPT_DIR"/* "$PLUGIN_DIR/"

# Make scripts executable
chmod +x "$PLUGIN_DIR/hooks/notify.sh"
chmod +x "$PLUGIN_DIR/hooks/check-setup.sh"
chmod +x "$PLUGIN_DIR/lib/detect-mode.sh"
chmod +x "$PLUGIN_DIR/lib/route-file.sh"
chmod +x "$PLUGIN_DIR/install.sh"
chmod +x "$PLUGIN_DIR/uninstall.sh"
chmod +x "$PLUGIN_DIR/setup-oauth.sh"
chmod +x "$PLUGIN_DIR/setup-oauth.py"

echo ""
echo "Claude Slack Notifier installed successfully!"
echo ""
echo "Next step — run setup (browser-based, ~1 minute):"
echo ""
echo "    ${PLUGIN_DIR}/setup-oauth.sh"
echo ""
echo "You will be prompted to generate one Slack config token (30s),"
echo "then your browser opens for a single-click authorization."
echo ""
echo "Or use the manual setup wizard in Claude Code: /slack-notifier-setup"
