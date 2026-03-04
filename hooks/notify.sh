#!/bin/bash
# hooks/notify.sh - Claude Code -> Slack notification hook
# Called by Claude Code on Notification, PermissionRequest, and Stop events
# Receives JSON payload on stdin

set -euo pipefail

# --- Setup -------------------------------------------------------------------
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_FILE="/tmp/claude-slack-notifier.log"
DEDUP_FILE="/tmp/claude-slack-notifier-last.txt"
CONFIG_FILE="${HOME}/.claude/slack-notifier.conf"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log "Hook triggered: CLAUDE_HOOK_EVENT=${CLAUDE_HOOK_EVENT:-unknown}"

# --- Load Config --------------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# Defaults
SLACK_DEDUPE_SECONDS="${SLACK_DEDUPE_SECONDS:-30}"
SLACK_QUIET_HOURS_START="${SLACK_QUIET_HOURS_START:-}"
SLACK_QUIET_HOURS_END="${SLACK_QUIET_HOURS_END:-}"

# --- Detect Mode --------------------------------------------------------------
# shellcheck source=../lib/detect-mode.sh
source "${PLUGIN_ROOT}/lib/detect-mode.sh"

if [ -z "$SLACK_MODE" ]; then
  log "No Slack credentials configured. Run /slack-notifier-setup to configure."
  exit 0
fi

# --- Read Hook Payload --------------------------------------------------------
PAYLOAD=""
if [ -t 0 ]; then
  PAYLOAD="{}"
else
  PAYLOAD=$(cat)
fi

log "Payload: $PAYLOAD"

# Read event name from JSON payload (CLAUDE_HOOK_EVENT env var is not reliably set)
HOOK_EVENT=$(echo "$PAYLOAD" | grep -o '"hook_event_name":"[^"]*"' | head -1 | sed 's/"hook_event_name":"//;s/"$//')
HOOK_EVENT="${HOOK_EVENT:-${CLAUDE_HOOK_EVENT:-Notification}}"

# --- Parse rich fields with python3 ------------------------------------------
# python3 is pre-installed on macOS; gracefully fall back to empty strings

_py() {
  echo "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    $1
except Exception:
    print('')
" 2>/dev/null || echo ""
}

SESSION_ID=$(_py "print(d.get('session_id',''))")
NOTIFICATION_TYPE=$(_py "print(d.get('notification_type',''))")
TOOL_NAME=$(_py "print(d.get('tool_name',''))")
TOOL_COMMAND=$(_py "
ti = d.get('tool_input') or {}
cmd = ti.get('command') or ti.get('file_path') or ti.get('url') or ti.get('query') or ''
print(str(cmd)[:80].replace(chr(10), ' ').strip())
")
TOOL_DESC=$(_py "
ti = d.get('tool_input') or {}
print((ti.get('description') or '')[:80].strip())
")
LAST_MSG=$(_py "
msg = (d.get('last_assistant_message') or '').strip()
msg = msg[:200].replace(chr(10), ' ')
print(msg)
")
PERMISSION_MODE=$(_py "print(d.get('permission_mode',''))")

log "Parsed: event=$HOOK_EVENT tool=$TOOL_NAME notification_type=$NOTIFICATION_TYPE session=$SESSION_ID"

# --- Determine Notification Type ----------------------------------------------
NOTIF_TYPE="notification"
MESSAGE=""

if [ "$HOOK_EVENT" = "PermissionRequest" ]; then
  if [ "$TOOL_NAME" = "AskUserQuestion" ] || [ "$TOOL_NAME" = "ExitPlanMode" ]; then
    # Interactive tools: notify as "waiting for input" not "permission needed"
    NOTIF_TYPE="idle"
    MESSAGE="Claude is asking for your input"
  else
    # Destructive/file tools: standard permission notification with tool details
    NOTIF_TYPE="permission"
    if [ -n "$TOOL_NAME" ] && [ -n "$TOOL_COMMAND" ]; then
      MESSAGE="Permission to use \`${TOOL_NAME}\`: \`${TOOL_COMMAND}\`"
    elif [ -n "$TOOL_NAME" ] && [ -n "$TOOL_DESC" ]; then
      MESSAGE="Permission to use \`${TOOL_NAME}\` — ${TOOL_DESC}"
    elif [ -n "$TOOL_NAME" ]; then
      MESSAGE="Permission to use \`${TOOL_NAME}\`"
    else
      MESSAGE="Claude needs your permission"
    fi
  fi

elif [ "$HOOK_EVENT" = "Stop" ]; then
  NOTIF_TYPE="task_complete"
  MESSAGE="$LAST_MSG"

elif [ "$HOOK_EVENT" = "Notification" ]; then
  # Use notification_type field if present (reliable via hooks.json matcher)
  case "$NOTIFICATION_TYPE" in
    "permission_prompt") NOTIF_TYPE="permission" ;;
    "idle_prompt"|"elicitation_dialog") NOTIF_TYPE="idle" ;;
    "auth_success") NOTIF_TYPE="task_complete" ;;
  esac
  # Extract human-readable message
  MESSAGE=$(echo "$PAYLOAD" | grep -o '"message":"[^"]*"' | head -1 | sed 's/"message":"//;s/"$//' || echo "")
  if [ -z "$MESSAGE" ]; then
    MESSAGE=$(echo "$PAYLOAD" | grep -o '"title":"[^"]*"' | head -1 | sed 's/"title":"//;s/"$//' || echo "")
  fi
  # Fallback text-based classification when notification_type is absent
  if [ "$NOTIF_TYPE" = "notification" ]; then
    if echo "$MESSAGE" | grep -qi "permission\|PermissionRequest\|approve"; then
      NOTIF_TYPE="permission"
    elif echo "$MESSAGE" | grep -qi "idle\|waiting\|input"; then
      NOTIF_TYPE="idle"
    elif echo "$MESSAGE" | grep -qi "error\|fail\|failed"; then
      NOTIF_TYPE="error"
    fi
  fi
fi

log "Notification type: $NOTIF_TYPE"

# --- Color & Emoji ------------------------------------------------------------
case "$NOTIF_TYPE" in
  permission)
    COLOR="#e8a838"
    EMOJI="🔐"
    TITLE="Permission needed"
    ;;
  idle)
    COLOR="#0ea5e9"
    EMOJI="💬"
    TITLE="Waiting for input"
    ;;
  task_complete)
    COLOR="#28a745"
    EMOJI="✅"
    TITLE="Task complete"
    ;;
  error)
    COLOR="#dc3545"
    EMOJI="❌"
    TITLE="Error"
    ;;
  *)
    COLOR="#0ea5e9"
    EMOJI="🔔"
    TITLE="Claude Code"
    ;;
esac

# --- Quiet Hours Check --------------------------------------------------------
if [ -n "$SLACK_QUIET_HOURS_START" ] && [ -n "$SLACK_QUIET_HOURS_END" ]; then
  CURRENT_TIME=$(date +%H:%M)
  # Simple string comparison for HH:MM format
  if [[ "$CURRENT_TIME" > "$SLACK_QUIET_HOURS_START" ]] || [[ "$CURRENT_TIME" < "$SLACK_QUIET_HOURS_END" ]]; then
    log "Quiet hours active ($SLACK_QUIET_HOURS_START-$SLACK_QUIET_HOURS_END), suppressing notification"
    exit 0
  fi
fi

# --- Deduplication ------------------------------------------------------------
NOTIF_HASH="${NOTIF_TYPE}:${MESSAGE}"
if [ -f "$DEDUP_FILE" ]; then
  LAST_ENTRY=$(cat "$DEDUP_FILE")
  LAST_HASH=$(echo "$LAST_ENTRY" | cut -d'|' -f1)
  LAST_TIME=$(echo "$LAST_ENTRY" | cut -d'|' -f2)
  NOW=$(date +%s)
  if [ "$LAST_HASH" = "$NOTIF_HASH" ] && [ $((NOW - LAST_TIME)) -lt "$SLACK_DEDUPE_SECONDS" ]; then
    log "Deduplicated: same notification within ${SLACK_DEDUPE_SECONDS}s"
    exit 0
  fi
fi
echo "${NOTIF_HASH}|$(date +%s)" > "$DEDUP_FILE"

# --- Context line -------------------------------------------------------------
PROJECT_DIR=$(basename "$PWD" 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

if [ -n "$GIT_BRANCH" ]; then
  CONTEXT_LINE="📁 \`${PROJECT_DIR}\` · branch: \`${GIT_BRANCH}\`"
else
  CONTEXT_LINE="📁 \`${PROJECT_DIR}\`"
fi
if [ -n "$SESSION_ID" ]; then
  CONTEXT_LINE="${CONTEXT_LINE} · 🖥️ session id: \`${SESSION_ID}\`"
fi
if [ -n "$PERMISSION_MODE" ] && [ "$PERMISSION_MODE" != "default" ]; then
  CONTEXT_LINE="${CONTEXT_LINE} · mode: \`${PERMISSION_MODE}\`"
fi

# --- Build Slack Payload ------------------------------------------------------
# Escape values for safe JSON string interpolation (handles quotes and backslashes)
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '
}

MESSAGE_DISPLAY=$(json_escape "${MESSAGE:-No additional details}")
CONTEXT_ESCAPED=$(json_escape "$CONTEXT_LINE")

BLOCKS=$(cat <<BLOCKS_EOF
[
  {
    "type": "section",
    "text": {
      "type": "mrkdwn",
      "text": "${EMOJI} *${TITLE}*\n${MESSAGE_DISPLAY}"
    }
  },
  {
    "type": "context",
    "elements": [
      {
        "type": "mrkdwn",
        "text": "${CONTEXT_ESCAPED}"
      }
    ]
  }
]
BLOCKS_EOF
)

# --- Send Notification --------------------------------------------------------
if [ "$SLACK_MODE" = "personal" ]; then
  # Personal mode: Incoming Webhook
  PAYLOAD_JSON=$(cat <<JSON_EOF
{
  "text": "${EMOJI} ${TITLE} — Claude Code",
  "attachments": [
    {
      "color": "${COLOR}",
      "blocks": ${BLOCKS}
    }
  ]
}
JSON_EOF
  )

  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD_JSON" \
    "$SLACK_WEBHOOK_URL" 2>/dev/null || echo "000")

  if [ "$RESPONSE" = "200" ]; then
    log "Notification sent successfully (webhook, type: $NOTIF_TYPE)"
  else
    log "Failed to send notification: HTTP $RESPONSE"
  fi

elif [ "$SLACK_MODE" = "shared" ]; then
  # Shared mode: Bot API
  CHANNEL="${SLACK_CHANNEL:-#claude-notifications}"
  PAYLOAD_JSON=$(cat <<JSON_EOF
{
  "channel": "${CHANNEL}",
  "text": "${EMOJI} ${TITLE} — Claude Code",
  "attachments": [
    {
      "color": "${COLOR}",
      "blocks": ${BLOCKS}
    }
  ]
}
JSON_EOF
  )

  # Use per-run tmpfile to avoid race conditions on multi-user systems
  API_RESPONSE_FILE=$(mktemp)
  RESPONSE=$(curl -s -o "$API_RESPONSE_FILE" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -d "$PAYLOAD_JSON" \
    "https://slack.com/api/chat.postMessage" 2>/dev/null || echo "000")

  if [ "$RESPONSE" = "200" ]; then
    API_OK=$(grep -o '"ok":true' "$API_RESPONSE_FILE" 2>/dev/null || echo "")
    if [ -n "$API_OK" ]; then
      log "Notification sent successfully (bot API, type: $NOTIF_TYPE)"
    else
      API_ERROR=$(grep -o '"error":"[^"]*"' "$API_RESPONSE_FILE" 2>/dev/null || echo "unknown")
      log "Slack API error: $API_ERROR"
    fi
  else
    log "Failed to send notification: HTTP $RESPONSE"
  fi
  rm -f "$API_RESPONSE_FILE"
fi
