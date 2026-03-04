#!/bin/bash
# hooks/check-setup.sh — First-run setup reminder
# Runs on SessionStart. Shows a one-time prompt if Slack isn't configured yet.

CONFIG_FILE="${HOME}/.claude/slack-notifier.conf"

if [ ! -f "$CONFIG_FILE" ]; then
  echo ""
  echo "┌─────────────────────────────────────────────────────┐"
  echo "│  Claude Slack Notifier: Setup required              │"
  echo "│                                                     │"
  echo "│  Run once to connect your Slack workspace:          │"
  echo "│                                                     │"
  echo "│    ${CLAUDE_PLUGIN_ROOT}/setup-oauth.sh             │"
  echo "│                                                     │"
  echo "│  Takes ~1 minute. No config files to edit.          │"
  echo "└─────────────────────────────────────────────────────┘"
  echo ""
fi
