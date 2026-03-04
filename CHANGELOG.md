# Changelog

All notable changes to Claude Slack Notifier will be documented here.

## [1.0.0] - 2026-03-03

### Added
- Phase 1: Core notification hook for `Notification` and `Stop` Claude Code events
- Permission needed alerts (🔐 amber #e8a838)
- Idle/waiting for input notifications (💬 blue #0ea5e9)
- Task complete notifications (✅ green #28a745)
- Error alerts (❌ red #dc3545)
- Git context in notifications (project name + branch)
- Phase 2: Dual Slack app mode support
  - Personal app mode (Incoming Webhook — no admin required)
  - Shared workspace app mode (Bot API with chat:write)
  - Auto-detection based on available env vars
  - `/slack-notifier-setup` wizard for both modes
  - Quiet hours support
  - Deduplication (suppress repeats within N seconds)
- Phase 3: File type routing
  - Extension-based routing for 15+ file types
  - Wildcard `*` fallback for unknown/unmatched types
  - Generic handler with text-decode attempt
- Phase 4: OAuth automated setup via Slack Manifest API
  - `setup-oauth.py` — full automated flow, no Cloudflare needed
  - One-time config token paste → browser click Allow → done
  - Refresh token stored for fully automatic future setups
