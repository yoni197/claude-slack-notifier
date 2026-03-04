#!/bin/bash
# setup-oauth.sh — thin wrapper around setup-oauth.py
set -euo pipefail
python3 "$(dirname "${BASH_SOURCE[0]}")/setup-oauth.py" "$@"
