#!/usr/bin/env bash
# ==============================================================================
# Script: probe-ssh-port.sh
# Purpose: Dynamically detects the active SSH port for cPanel servers and
#          populates ~/.ssh/known_hosts to prevent host key verification errors.
# Compatibility: POSIX bash, compatible with GitHub Actions ubuntu-latest runners.
# ==============================================================================

set -euo pipefail

HOST="${1:-${CPANEL_SSH_HOST:-}}"
CONFIGURED_PORT="${2:-${CPANEL_SSH_PORT:-}}"

if [ -z "$HOST" ]; then
  echo "❌ Error: Hostname or IP address must be provided." >&2
  echo "Usage: ./probe-ssh-port.sh <host> [preferred_port]" >&2
  exit 1
fi

mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/known_hosts
chmod 644 ~/.ssh/known_hosts

echo "🔍 Probing active SSH port for host: $HOST..."

# Candidate port list: user-configured port first, followed by standard ports
CANDIDATES=()
if [ -n "$CONFIGURED_PORT" ]; then
  CANDIDATES+=("$CONFIGURED_PORT")
fi
# Standard cPanel SSH ports: 22, 1219 (shared hosting standard), 2222 (alternative)
for p in 22 1219 2222; do
  if [ "$p" != "$CONFIGURED_PORT" ]; then
    CANDIDATES+=("$p")
  fi
done

SELECTED_PORT=""

for port in "${CANDIDATES[@]}"; do
  echo "  --> Testing port $port..."
  # Use ssh-keyscan with a 3-second timeout to check if an SSH daemon responds
  KEY_OUTPUT=$(ssh-keyscan -p "$port" -T 3 "$HOST" 2>/dev/null || true)
  
  if [ -n "$KEY_OUTPUT" ]; then
    echo "✅ Active SSH service detected on port $port!"
    echo "$KEY_OUTPUT" >> ~/.ssh/known_hosts
    SELECTED_PORT="$port"
    break
  fi
done

if [ -z "$SELECTED_PORT" ]; then
  echo "⚠️ Warning: Automated port probe could not reach SSH on tested ports (${CANDIDATES[*]})."
  echo "Defaulting to configured port (${CONFIGURED_PORT:-22}). Firewall or host key scan may be restricted."
  SELECTED_PORT="${CONFIGURED_PORT:-22}"
  # Attempt fallback keyscan on default port without timeout flag
  ssh-keyscan -p "$SELECTED_PORT" "$HOST" >> ~/.ssh/known_hosts 2>/dev/null || true
fi

echo "Selected SSH Port: $SELECTED_PORT"

# Export to GitHub Actions output if running inside GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "port=$SELECTED_PORT" >> "$GITHUB_OUTPUT"
fi
