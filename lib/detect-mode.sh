#!/bin/bash
# lib/detect-mode.sh - Detect Slack app mode (personal webhook vs shared bot)
# Usage: source this file to set SLACK_MODE variable

# Source config if not already loaded
CONFIG_FILE="${HOME}/.claude/slack-notifier.conf"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# Detect mode based on available credentials
# Use :- default to handle unset variables when sourced under set -u
if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  # Both set: shared (bot) takes priority
  SLACK_MODE="shared"
elif [ -n "${SLACK_BOT_TOKEN:-}" ]; then
  SLACK_MODE="shared"
elif [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  SLACK_MODE="personal"
else
  SLACK_MODE=""
fi

export SLACK_MODE
