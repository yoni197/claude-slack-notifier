---
description: "Set up Slack notifications"
---

# Slack Notifier Setup

Connects Claude Code to Slack so you receive a DM whenever Claude needs permission, finishes a task, or is waiting for input.

## Step 1 — Get a config token

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Scroll to **Your App Configuration Tokens** → **Generate Token**
3. Copy the token (starts with `xoxe-1-...`)

## Step 2 — Run setup

```bash
${CLAUDE_PLUGIN_ROOT}/setup-oauth.sh --config-token xoxe-1-...
```

Click **Allow** in the browser that opens. Done — notifications will appear as a DM from **Claude Code Notifier**.

> Future re-runs (token expired, new workspace): `${CLAUDE_PLUGIN_ROOT}/setup-oauth.sh --yes`
