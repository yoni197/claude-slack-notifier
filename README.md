# Claude Code Slack Notifier

> Get Slack notifications when Claude Code needs your attention — no more staring at the terminal.

Sends a Slack message when Claude Code:
- 🔐 Needs permission to use a tool
- 💬 Is idle and waiting for your input
- ✅ Finishes a task
- ❌ Hits an error

Notifications arrive as a **DM from "Claude Code Notifier"** in Slack's Apps sidebar — private to you, no channel required.

---


https://github.com/user-attachments/assets/c0102087-f966-4637-abd0-59f289965b0c


---

## Install

**Step 1 — Add the marketplace (one time):**

```bash
claude plugin marketplace add yoni197/claude-slack-notifier
```

**Step 2 — Install the plugin:**

```bash
claude plugin install claude-slack-notifier@claude-slack-notifier
```

**Step 3 — Restart Claude Code**, then run setup:

```bash
${CLAUDE_PLUGIN_ROOT}/setup-oauth.sh --config-token <your-token>
```

> On first start after installing, Claude Code will print the exact path for `${CLAUDE_PLUGIN_ROOT}`.

---

## Setup

`setup-oauth.sh` is fully automated — no config files to edit.

**First time (one token required):**

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Scroll down to **Your App Configuration Tokens** → click **Generate Token** next to your workspace
3. Copy the token (starts with `xoxe-1-...`) and run:

```bash
${CLAUDE_PLUGIN_ROOT}/setup-oauth.sh --config-token xoxe-1-...
```

4. Browser opens Slack authorization — click **Allow**
5. Done. Config saved to `~/.claude/slack-notifier.conf`

> **About the token expiry:** This token is only used right now to create your Slack app. It is not stored and not used for sending notifications. Even if it shows "Expires in 9 hours" in your Slack dashboard, your notifications will keep working indefinitely — they run off the bot token obtained in step 4.

**Subsequent runs** are fully automatic (refresh token stored locally):

```bash
${CLAUDE_PLUGIN_ROOT}/setup-oauth.sh --yes
```

---

## What you'll receive

```
✅ Task complete
No additional details
📁 my-project · branch: feat/auth-fix
```

```
🔐 Permission needed
Claude needs your permission to use Bash
📁 my-project · branch: main
```

---

## Configuration

Config lives at `~/.claude/slack-notifier.conf` (auto-created by setup):

```bash
SLACK_MODE="shared"
SLACK_BOT_TOKEN="xoxb-..."
SLACK_CHANNEL="D0123456789"        # DM channel ID, set automatically by setup

SLACK_DEDUPE_SECONDS=30            # suppress duplicate notifications within N seconds
# SLACK_QUIET_HOURS_START="22:00"  # optional: no notifications at night
# SLACK_QUIET_HOURS_END="08:00"
```

---

## Troubleshooting

**Not receiving notifications?**

```bash
# Check logs
cat /tmp/claude-slack-notifier.log

# Send a test manually
printf '{"hook_event_name":"Stop"}' \
  | CLAUDE_PLUGIN_ROOT=~/.claude/plugins/cache/claude-slack-notifier/claude-slack-notifier/1.0.0 \
    ~/.claude/plugins/cache/claude-slack-notifier/claude-slack-notifier/1.0.0/hooks/notify.sh
```

**Re-run setup (e.g. token expired):**

```bash
${CLAUDE_PLUGIN_ROOT}/setup-oauth.sh --yes
```

**Reset everything:**

```bash
rm -f ~/.claude/slack-notifier.conf ~/.claude/slack-notifier-tokens.json
${CLAUDE_PLUGIN_ROOT}/setup-oauth.sh --config-token xoxe-1-...
```

---

## How it works

```text
Claude Code session
       │
       ▼  (Notification / Stop event fires)
hooks/notify.sh
       │
       ├── reads hook_event_name from JSON payload
       ├── classifies: permission / idle / task_complete / error
       │
       └── POST https://slack.com/api/chat.postMessage
               → DM channel between bot and you
```

Hooks registered: `Notification`, `Stop`, `SessionStart`

---

## Enable / Disable / Uninstall

**Disable for the current workspace only:**

```bash
claude plugin disable claude-slack-notifier@claude-slack-notifier --scope local
```

**Re-enable:**

```bash
claude plugin enable claude-slack-notifier@claude-slack-notifier
```

**Disable globally (all sessions):**

```bash
claude plugin disable claude-slack-notifier@claude-slack-notifier --scope user
```

**Uninstall completely:**

```bash
claude plugin uninstall claude-slack-notifier@claude-slack-notifier
rm -f ~/.claude/slack-notifier.conf ~/.claude/slack-notifier-tokens.json
```

> Uninstalling removes the hooks. Your Slack app continues to exist but will no longer receive messages.

---

## License

MIT
