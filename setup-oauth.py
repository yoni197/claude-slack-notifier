#!/usr/bin/env python3
"""
setup-oauth.py — Claude Slack Notifier: automated Slack setup

Flow:
  1. Open api.slack.com/apps in browser — user generates a config token (30s, one time)
  2. apps.manifest.create  → creates the Slack app, returns client_id + client_secret
  3. Local HTTP server + browser OAuth → user clicks Allow (one click)
  4. Exchange code locally → get bot token + authed user ID
  5. conversations.open    → open a DM channel between the bot and the user
  6. Write ~/.claude/slack-notifier.conf (mode 600)

Messages arrive as a DM from "Claude Code" in Slack's Apps sidebar — no channel needed.
No Cloudflare. No wrangler. No hosted server. Only python3 (pre-installed on macOS).
"""

import http.server
import json
import os
import secrets
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────
HOME          = Path.home()
CONFIG_FILE   = HOME / ".claude" / "slack-notifier.conf"
TOKEN_FILE    = HOME / ".claude" / "slack-notifier-tokens.json"
PLUGIN_ROOT   = Path(__file__).parent

APP_NAME      = "Claude Code Notifier"
APP_DESC      = "Claude Code lifecycle notifications — permission prompts, task complete, errors"

# ── HTML pages ────────────────────────────────────────────────────────────────
SUCCESS_HTML = b"""<!DOCTYPE html>
<html>
<head>
  <title>Claude Slack Notifier \xe2\x80\x94 Connected</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
           text-align: center; padding: 60px; background: #f8f9fa; margin: 0; }
    h1   { color: #28a745; font-size: 2em; margin-bottom: 16px; }
    p    { color: #555; font-size: 1.1em; line-height: 1.6; }
  </style>
</head>
<body>
  <h1>&#10003; Connected to Slack</h1>
  <p>Claude Code will now notify you when tasks complete,<br>
     permissions are needed, or input is required.</p>
  <p style="margin-top:32px; color:#aaa; font-size:0.9em">
    You can close this window and return to your terminal.
  </p>
</body>
</html>"""

ERROR_HTML = b"""<!DOCTYPE html>
<html>
<head><title>Setup Error \xe2\x80\x94 Claude Slack Notifier</title>
<style>body{font-family:-apple-system,sans-serif;text-align:center;padding:60px;background:#f8f9fa}
h1{color:#dc3545}p{color:#555}code{background:#eee;padding:2px 6px;border-radius:3px}</style>
</head>
<body>
  <h1>Authorization Failed</h1>
  <p>Check your terminal for details.</p>
  <p>Run <code>python3 setup-oauth.py</code> again to retry.</p>
</body>
</html>"""

# ── Token helpers ─────────────────────────────────────────────────────────────
def load_tokens() -> dict:
    if TOKEN_FILE.exists():
        try:
            with open(TOKEN_FILE) as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_tokens(tokens: dict) -> None:
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(TOKEN_FILE, "w") as f:
        json.dump(tokens, f, indent=2)
    os.chmod(TOKEN_FILE, 0o600)


# ── Slack API ─────────────────────────────────────────────────────────────────
def slack_post(method: str, token: str, payload: dict) -> dict:
    """POST to a Slack API method with a JSON body. Raises on network error."""
    data = json.dumps(payload).encode()
    req  = urllib.request.Request(
        f"https://slack.com/api/{method}",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type":  "application/json; charset=utf-8",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def slack_post_form(url: str, params: dict) -> dict:
    """POST URL-encoded form data (used for OAuth token exchange)."""
    data = urllib.parse.urlencode(params).encode()
    req  = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


# ── Step 1: Config token ──────────────────────────────────────────────────────
def get_config_token(cli_token: str = "") -> str:
    """
    Return a valid Slack app configuration token.
    Priority: --config-token arg > stored refresh token > interactive prompt.
    """
    tokens = load_tokens()

    # Try to rotate with stored refresh token (fully automatic)
    if tokens.get("refresh_token"):
        try:
            resp = slack_post(
                "tooling.tokens.rotate",
                tokens["refresh_token"],
                {"refresh_token": tokens["refresh_token"]},
            )
            if resp.get("ok"):
                tokens["access_token"]  = resp["token"]
                tokens["refresh_token"] = resp["refresh_token"]
                save_tokens(tokens)
                print("  Config token refreshed automatically.")
                return tokens["access_token"]
        except Exception:
            pass  # Fall through

    # Use token passed via --config-token flag (no TTY needed)
    token = cli_token.strip()

    if not token:
        # Interactive fallback (requires TTY)
        print()
        print("  A Slack App Configuration Token is required (one time only).")
        print()
        print("  This token is ONLY used right now to create your Slack app.")
        print("  It is NOT stored and NOT used for sending notifications.")
        print("  Even if it expires, your notifications will keep working.")
        print()
        print("  Steps (~30 seconds):")
        print("    1. Go to https://api.slack.com/apps")
        print("    2. Scroll down to 'Your App Configuration Tokens'")
        print("    3. Click 'Generate Token' next to your workspace")
        print("    4. Copy the token (starts with xoxe-1-...)")
        print("    5. Re-run with: setup-oauth.sh --config-token <token>")
        print()
        try:
            webbrowser.open("https://api.slack.com/apps")
        except Exception:
            pass
        print("  No --config-token provided. Exiting.")
        sys.exit(1)

    if not token.startswith("xoxe"):
        print("\nWarning: token looks unexpected (should start with xoxe). Continuing anyway.")

    # Try to get a refresh token so future runs are fully automatic
    try:
        resp = slack_post(
            "tooling.tokens.rotate",
            token,
            {"refresh_token": token},
        )
        if resp.get("ok"):
            tokens["access_token"]  = resp["token"]
            tokens["refresh_token"] = resp["refresh_token"]
            save_tokens(tokens)
            print("  Refresh token saved — future setups will be fully automatic.")
            return tokens["access_token"]
    except Exception:
        pass

    # Store as-is (valid for ~12h, sufficient for setup)
    tokens["access_token"] = token
    save_tokens(tokens)
    return token


# ── Step 2: Create Slack app via manifest ─────────────────────────────────────
def create_app(config_token: str, port: int) -> tuple[str, str, str]:
    """
    Create a Slack app using the manifest API.
    Returns (client_id, client_secret, oauth_authorize_url).
    """
    manifest = {
        "display_information": {
            "name":        APP_NAME,
            "description": APP_DESC,
        },
        "features": {
            "bot_user": {
                "display_name": APP_NAME,
                "always_online": False,
            },
        },
        "oauth_config": {
            "redirect_urls": [f"http://localhost:{port}/callback"],
            "scopes": {
                "bot": ["chat:write", "im:write"],
            },
        },
        "settings": {
            "org_deploy_enabled":  False,
            "socket_mode_enabled": False,
        },
    }

    print("  Creating Slack app...", end=" ", flush=True)
    resp = slack_post("apps.manifest.create", config_token, {"manifest": manifest})

    if not resp.get("ok"):
        error = resp.get("error", "unknown")
        print(f"\n  Error: {error}")
        if error == "invalid_auth":
            print("  Your config token may have expired. Delete ~/.claude/slack-notifier-tokens.json and try again.")
        sys.exit(1)

    print("done")

    creds = resp["credentials"]
    return (
        creds["client_id"],
        creds["client_secret"],
        resp["oauth_authorize_url"],
    )


# ── Step 3: Find a free port ──────────────────────────────────────────────────
def find_free_port() -> int:
    for port in [8765, 8766, 8767, 8768, 8769]:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    # Let OS pick one
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# ── Step 4: Local OAuth flow ──────────────────────────────────────────────────
def run_oauth_flow(
    client_id: str,
    client_secret: str,
    oauth_authorize_url: str,
    port: int,
) -> tuple[str, str]:
    """
    Start a local HTTP server, open the browser to Slack OAuth,
    wait for the redirect, exchange the code, and return (bot_token, dm_channel_id).
    """
    state  = secrets.token_hex(16)
    # Append state to the URL returned by manifest.create
    sep    = "&" if "?" in oauth_authorize_url else "?"
    auth_url = f"{oauth_authorize_url}{sep}state={state}"

    result: dict = {}
    server_ready = threading.Event()

    class _Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)

            if parsed.path != "/callback":
                self.send_response(404)
                self.end_headers()
                return

            params     = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
            code       = params.get("code",  [""])[0]
            ret_state  = params.get("state", [""])[0]
            error      = params.get("error", [""])[0]

            if error:
                result["error"] = f"Slack returned error: {error}"
                self._send(400, ERROR_HTML)
            elif ret_state != state:
                result["error"] = "State mismatch — possible CSRF. Aborting."
                self._send(400, ERROR_HTML)
            elif not code:
                result["error"] = "No authorization code in callback."
                self._send(400, ERROR_HTML)
            else:
                try:
                    bot_token, dm_channel = _exchange_code(code, client_id, client_secret, port)
                    result["bot_token"]  = bot_token
                    result["dm_channel"] = dm_channel
                    self._send(200, SUCCESS_HTML)
                except Exception as exc:
                    result["error"] = str(exc)
                    self._send(500, ERROR_HTML)

            threading.Thread(target=self.server.shutdown, daemon=True).start()

        def _send(self, status: int, body: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass  # Suppress request logs

    # HTTPServer binds the socket in __init__, so it's ready immediately
    server = http.server.HTTPServer(("127.0.0.1", port), _Handler)

    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    print()
    print("  Opening Slack in your browser — click Allow to connect.")
    print()
    try:
        webbrowser.open(auth_url)
    except Exception:
        print(f"  Open this URL in your browser:\n  {auth_url}\n")

    # Wait up to 120s for the OAuth callback
    print("  Waiting for authorization", end="", flush=True)
    for i in range(120):
        if result:
            break
        time.sleep(1)
        if (i + 1) % 15 == 0:
            print(f" {i + 1}s", end="", flush=True)
    print()

    server.shutdown()

    if "error" in result:
        print(f"\n  Authorization failed: {result['error']}")
        sys.exit(1)

    if not result.get("bot_token"):
        print("\n  Timed out (120s). Run setup-oauth.py again.")
        sys.exit(1)

    return result["bot_token"], result["dm_channel"]


def _exchange_code(code: str, client_id: str, client_secret: str, port: int) -> tuple[str, str]:
    """Exchange OAuth code for a bot token, then open a DM channel with the installing user."""
    resp = slack_post_form(
        "https://slack.com/api/oauth.v2.access",
        {
            "client_id":     client_id,
            "client_secret": client_secret,
            "code":          code,
            "redirect_uri":  f"http://localhost:{port}/callback",
        },
    )

    if not resp.get("ok"):
        raise RuntimeError(f"OAuth exchange failed: {resp.get('error', 'unknown')}")

    bot_token = resp.get("access_token", "")
    user_id   = resp.get("authed_user", {}).get("id", "")

    if not bot_token:
        raise RuntimeError("No bot token in OAuth response — was chat:write scope granted?")
    if not user_id:
        raise RuntimeError("No authed_user.id in OAuth response")

    # Open a DM channel between the bot and the installing user.
    # Messages will appear under "Apps > Claude Code" in Slack's sidebar.
    dm_resp = slack_post("conversations.open", bot_token, {"users": user_id})
    if not dm_resp.get("ok"):
        raise RuntimeError(f"Could not open DM channel: {dm_resp.get('error', 'unknown')}")

    dm_channel = dm_resp["channel"]["id"]
    return bot_token, dm_channel


# ── Step 5: Write config ──────────────────────────────────────────────────────
def write_config(bot_token: str, dm_channel: str) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    content = f"""# Claude Slack Notifier Configuration
# Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}
# DO NOT COMMIT — contains your Slack bot token

SLACK_MODE="shared"
SLACK_BOT_TOKEN="{bot_token}"
SLACK_CHANNEL="{dm_channel}"
SLACK_DEDUPE_SECONDS=30
# Uncomment to suppress notifications outside work hours (24h format):
# SLACK_QUIET_HOURS_START="22:00"
# SLACK_QUIET_HOURS_END="08:00"
"""
    with open(CONFIG_FILE, "w") as f:
        f.write(content)
    os.chmod(CONFIG_FILE, 0o600)


# ── Step 6: Test notification ─────────────────────────────────────────────────
def send_test_notification() -> None:
    notify_sh = PLUGIN_ROOT / "hooks" / "notify.sh"
    if not (notify_sh.exists() and os.access(notify_sh, os.X_OK)):
        return
    try:
        subprocess.run(
            [str(notify_sh)],
            input=b'{"hook_event_name":"Stop","message":"Claude Code Notifier is connected. You will receive notifications here."}',
            env={
                **os.environ,
                "CLAUDE_PLUGIN_ROOT": str(PLUGIN_ROOT),
            },
            timeout=10,
            check=False,
        )
    except Exception:
        pass


# ── Main ──────────────────────────────────────────────────────────────────────
def main() -> None:
    yes = "--yes" in sys.argv or "-y" in sys.argv

    # --config-token TOKEN  (accepts --config-token=TOKEN or --config-token TOKEN)
    cli_token = ""
    for i, arg in enumerate(sys.argv):
        if arg.startswith("--config-token="):
            cli_token = arg.split("=", 1)[1]
        elif arg == "--config-token" and i + 1 < len(sys.argv):
            cli_token = sys.argv[i + 1]

    print()
    print("Claude Slack Notifier — Setup")
    print("=" * 40)

    if CONFIG_FILE.exists():
        if yes:
            print("\nConfig already exists. Re-running setup (--yes).")
        else:
            answer = input("\nConfig already exists. Re-run setup? [y/N] ").strip().lower()
            if answer != "y":
                print("Cancelled.")
                sys.exit(0)

    # 1. Config token (automatic if refresh token saved, else --config-token arg)
    print("\n[1/4] Config token")
    config_token = get_config_token(cli_token)

    # 2. Pick port, create Slack app
    print("\n[2/4] Creating Slack app")
    port = find_free_port()
    client_id, client_secret, oauth_url = create_app(config_token, port)

    # 3. OAuth: browser open → user clicks Allow → we get bot token + DM channel
    print("\n[3/4] Authorize with Slack")
    bot_token, dm_channel = run_oauth_flow(client_id, client_secret, oauth_url, port)

    # 4. Write config
    print("\n[4/4] Saving config")
    write_config(bot_token, dm_channel)
    print(f"  Saved: {CONFIG_FILE} (mode 600)")
    print(f"  Notifications will arrive as a DM from 'Claude Code' in Slack's Apps sidebar.")

    # Test notification
    print()
    print("  Sending test notification...", end=" ", flush=True)
    send_test_notification()
    print("check Slack!")

    print()
    print("Setup complete.")
    print()


if __name__ == "__main__":
    main()
