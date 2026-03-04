# Personal Slack App Setup Guide

Set up Claude Code Slack Notifier using your own personal Slack app. This method uses an Incoming Webhook and requires no workspace admin approval.

## Prerequisites

- A Slack workspace where you can create apps
- Claude Code installed and working
- The claude-slack-notifier plugin installed (see [README](../README.md#installation))

## Step-by-Step Setup

### Step 1: Create a Slack App

1. Go to [https://api.slack.com/apps](https://api.slack.com/apps)
2. Click **"Create New App"**
3. Select **"From scratch"**
4. Enter the following:
   - **App Name**: `Claude Code Notifier` (or any name you like)
   - **Workspace**: Select your Slack workspace
5. Click **"Create App"**

### Step 2: Enable Incoming Webhooks

1. In the left sidebar, click **"Incoming Webhooks"**
2. Toggle **"Activate Incoming Webhooks"** to **On**
3. Scroll down and click **"Add New Webhook to Workspace"**
4. Choose the channel where you want notifications (e.g., `#claude-notifications` or a DM to yourself)
5. Click **"Allow"**

### Step 3: Copy the Webhook URL

After authorizing, you'll see a new webhook URL that looks like:

```
https://hooks.slack.com/services/<WORKSPACE_ID>/<BOT_ID>/<TOKEN>
```

Copy this URL. You'll need it in the next step.

### Step 4: Run the Setup Wizard

Inside Claude Code, run:

```
/slack-notifier-setup
```

When prompted:
1. Select **"Personal (webhook)"** mode
2. Paste your webhook URL when asked
3. Optionally configure quiet hours and deduplication settings

### Step 5: Verify Your Config

The wizard creates a config file at `~/.claude/slack-notifier.conf`. Verify it looks correct:

```bash
cat ~/.claude/slack-notifier.conf
```

You should see something like:

```bash
SLACK_MODE="personal"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"
SLACK_DEDUPE_SECONDS=30
```

### Step 6: Test the Integration

Send a test notification to verify everything works:

```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Claude Code Slack Notifier is working!"}' \
  "$(grep SLACK_WEBHOOK_URL ~/.claude/slack-notifier.conf | cut -d'"' -f2)"
```

You should see the message appear in your chosen Slack channel.

Now start a Claude Code session and give it a task. When Claude finishes, you should receive a notification in Slack.

## Updating Your Webhook URL

If you need to change your webhook URL (e.g., you regenerated it or want to send to a different channel):

**Option A: Run the wizard again**

```
/slack-notifier-setup
```

**Option B: Edit the config file directly**

```bash
# Open in your editor
nano ~/.claude/slack-notifier.conf

# Or replace the URL with sed
sed -i '' 's|SLACK_WEBHOOK_URL=".*"|SLACK_WEBHOOK_URL="YOUR_NEW_URL"|' ~/.claude/slack-notifier.conf
```

## Troubleshooting

### "No notifications received"

1. **Check the log file** for errors:
   ```bash
   cat /tmp/claude-slack-notifier.log
   ```

2. **Test the webhook directly**:
   ```bash
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"test"}' \
     "YOUR_WEBHOOK_URL"
   ```
   If this returns `ok`, the webhook is working. If not, the URL may be invalid.

3. **Verify the config file exists**:
   ```bash
   ls -la ~/.claude/slack-notifier.conf
   ```

### "Webhook URL expired or invalid"

Slack webhook URLs don't expire, but they can be revoked if:
- The Slack app is deleted
- The webhook is manually removed from the app settings
- The workspace admin uninstalled your app

To fix: Go back to [https://api.slack.com/apps](https://api.slack.com/apps), select your app, go to **Incoming Webhooks**, and create a new webhook.

### "Messages going to the wrong channel"

The channel is tied to the webhook URL itself. Each webhook posts to a specific channel. To change channels:

1. Go to your Slack app settings → **Incoming Webhooks**
2. Click **"Add New Webhook to Workspace"**
3. Select the new channel
4. Copy the new webhook URL
5. Update your config with the new URL

### "curl: command not found"

`curl` is required and comes pre-installed on macOS and most Linux distributions. If missing:

```bash
# macOS (via Homebrew)
brew install curl

# Ubuntu/Debian
sudo apt-get install curl

# Fedora/RHEL
sudo dnf install curl
```

## Security Notes

- Your webhook URL is stored locally in `~/.claude/slack-notifier.conf`
- The URL is a secret: anyone with it can post to your channel
- The `.gitignore` in this project excludes `slack-notifier.conf` to prevent accidental commits
- Never share your webhook URL in public repositories or chat messages
