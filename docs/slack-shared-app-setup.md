# Shared Workspace App Setup Guide

Set up Claude Code Slack Notifier as a shared workspace app so your entire team can receive notifications through a single Slack app installation.

## Who This Is For

This guide is for **Slack workspace admins** at companies or teams who want to:
- Provide Claude Code notifications to multiple developers
- Centralize notifications in shared channels
- Manage a single Slack app instead of per-developer webhooks

If you're an individual developer, the [Personal App Setup](slack-personal-app-setup.md) is simpler and doesn't require admin approval.

## Prerequisites

- **Slack workspace admin** access (or ability to request app installation)
- Claude Code installed on developer machines
- The claude-slack-notifier plugin installed (see [README](../README.md#installation))

## Admin Setup

### Step 1: Create the Slack App

1. Go to [https://api.slack.com/apps](https://api.slack.com/apps)
2. Click **"Create New App"**
3. Select **"From scratch"**
4. Enter the following:
   - **App Name**: `Claude Code Notifier`
   - **Workspace**: Select your workspace
5. Click **"Create App"**

### Step 2: Configure OAuth Scopes

1. In the left sidebar, click **"OAuth & Permissions"**
2. Scroll to **"Scopes"** → **"Bot Token Scopes"**
3. Add the following scopes:

| Scope | Purpose |
|---|---|
| `chat:write` | Send notification messages |
| `incoming-webhook` | Webhook fallback support |
| `commands` | Slash command support (future) |
| `files:read` | Read file context for notifications |
| `users:read` | Resolve user names for DM routing |

### Step 3: Install the App to Your Workspace

1. In the left sidebar, click **"Install App"**
2. Click **"Install to Workspace"**
3. Review the permissions and click **"Allow"**
4. Copy the **Bot User OAuth Token** (starts with `xoxb-`)

Keep this token secure. You'll distribute it to your team in a later step.

### Step 4: Create a Notification Channel

1. In Slack, create a channel for notifications (e.g., `#claude-notifications`)
2. Invite the bot to the channel:
   ```
   /invite @Claude Code Notifier
   ```
3. Note the channel name or ID for distribution to your team

### Step 5: Distribute the Bot Token to Your Team

Share the bot token with your developers using a secure method. Options:

**Option A: Environment variable (recommended)**

Have each developer add to their shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
export SLACK_BOT_TOKEN="xoxb-your-token-here"
```

**Option B: Shared secrets manager**

If your team uses a secrets manager (1Password, Vault, AWS Secrets Manager, etc.), store the token there and document how to retrieve it.

**Option C: Direct configuration**

Each developer runs `/slack-notifier-setup` and pastes the token when prompted.

## Per-Developer Setup

Each developer on your team needs to do the following:

### Step 1: Install the Plugin

```bash
git clone https://github.com/user/claude-slack-notifier ~/.claude/plugins/claude-slack-notifier
chmod +x ~/.claude/plugins/claude-slack-notifier/hooks/notify.sh
chmod +x ~/.claude/plugins/claude-slack-notifier/lib/*.sh
```

### Step 2: Run the Setup Wizard

Inside Claude Code, run:

```
/slack-notifier-setup
```

When prompted:
1. Select **"Shared (bot token)"** mode
2. Enter the bot token (or confirm it was detected from `$SLACK_BOT_TOKEN`)
3. Enter the notification channel (e.g., `#claude-notifications`)
4. Optionally configure quiet hours and deduplication

### Step 3: Verify Configuration

```bash
cat ~/.claude/slack-notifier.conf
```

Should show:

```bash
SLACK_MODE="shared"
SLACK_BOT_TOKEN="xoxb-..."
SLACK_CHANNEL="#claude-notifications"
SLACK_DEDUPE_SECONDS=30
```

### Step 4: Test

Start a Claude Code session and complete a task. A notification should appear in the shared channel.

## DM Notifications (Optional)

Instead of posting to a shared channel, developers can receive DMs from the bot. To configure:

1. Find the developer's Slack User ID:
   - Click on the user's profile in Slack
   - Click **"More"** → **"Copy member ID"**
2. Use the User ID as the channel in config:
   ```bash
   SLACK_CHANNEL="UXXXXXXXX"
   ```

The bot must have `users:read` scope and the user must have the app installed to receive DMs.

## Security Considerations

### Token Storage

- The bot token is stored in each developer's `~/.claude/slack-notifier.conf`
- The file should be readable only by the owner:
  ```bash
  chmod 600 ~/.claude/slack-notifier.conf
  ```
- The `.gitignore` in the plugin repo excludes config files

### Token Rotation

Rotate the bot token periodically:

1. Go to [https://api.slack.com/apps](https://api.slack.com/apps) → Your app → **"OAuth & Permissions"**
2. Click **"Rotate Token"** (if available) or reinstall the app
3. Distribute the new token to your team
4. Each developer updates their config:
   ```bash
   sed -i '' 's|SLACK_BOT_TOKEN=".*"|SLACK_BOT_TOKEN="xoxb-NEW-TOKEN"|' ~/.claude/slack-notifier.conf
   ```

### Revoking Access

**To revoke a single developer's access:**
- Delete their `~/.claude/slack-notifier.conf` file
- They will stop sending notifications immediately

**To revoke all access:**
1. Go to [https://api.slack.com/apps](https://api.slack.com/apps) → Your app
2. Click **"Basic Information"** → scroll to **"Delete App"**
3. Or go to **"Install App"** and click **"Revoke Tokens"**

**To remove the bot from a channel:**
```
/remove @Claude Code Notifier
```

## Troubleshooting

### "not_in_channel" error

The bot needs to be invited to the target channel:
```
/invite @Claude Code Notifier
```

### "invalid_auth" error

The bot token is incorrect or has been revoked. Verify the token:

```bash
curl -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
  https://slack.com/api/auth.test
```

If this returns `"ok": false`, the token is invalid. Get a new one from your Slack app settings.

### "channel_not_found" error

Verify the channel name includes the `#` prefix, or use the channel ID instead:
- Right-click the channel in Slack → **"View channel details"** → scroll to the bottom for the Channel ID

### Notifications not appearing for some team members

1. Verify each developer has a valid `~/.claude/slack-notifier.conf`
2. Check their individual logs: `cat /tmp/claude-slack-notifier.log`
3. Ensure the bot token in their config matches the current valid token
