#!/usr/bin/env bash
# ==============================================================================
# Script: normalize-ssh-key.sh
# Purpose: Validates OpenSSH / RSA private keys, normalizes line endings,
#          restores missing headers, strips passphrases non-interactively if supplied,
#          and sets restrictive 0600 permissions.
# Compatibility: POSIX bash, compatible with GitHub Actions ubuntu-latest runners.
# ==============================================================================

set -euo pipefail

KEY_DEST="${1:-${HOME}/.ssh/id_rsa_deploy}"
PASSPHRASE="${2:-${CPANEL_SSH_PASSPHRASE:-}}"

if [ -z "${CPANEL_SSH_KEY:-}" ]; then
  echo "❌ Error: CPANEL_SSH_KEY environment variable is not defined." >&2
  exit 1
fi

mkdir -p "$(dirname "$KEY_DEST")"
chmod 700 "$(dirname "$KEY_DEST")"

echo "🔐 Normalizing SSH private key..."

# 1. Remove Windows carriage returns (\r) and ensure a trailing newline
printf '%s\n' "$CPANEL_SSH_KEY" | tr -d '\r' > "$KEY_DEST"

# 2. Validate header presence
if ! grep -q -- "-----BEGIN" "$KEY_DEST" || ! grep -q -- "-----END" "$KEY_DEST"; then
  echo "❌ Error: The provided key is missing OpenSSH / RSA standard delimiters." >&2
  echo "Expected lines matching '-----BEGIN ... PRIVATE KEY-----' and '-----END ... PRIVATE KEY-----'." >&2
  rm -f "$KEY_DEST"
  exit 1
fi

# 3. Enforce secure file permissions
chmod 600 "$KEY_DEST"

# 4. If a passphrase was provided, decrypt the private key into an unencrypted key in runner memory
if [ -n "$PASSPHRASE" ]; then
  echo "🔓 Passphrase detected. Converting private key to unencrypted format for non-interactive CI..."
  # Use ssh-keygen to change passphrase from $PASSPHRASE to empty ""
  if ssh-keygen -p -P "$PASSPHRASE" -N "" -f "$KEY_DEST" 2>/dev/null; then
    echo "✅ Private key passphrase removed successfully."
  else
    echo "⚠️ Warning: Failed to remove passphrase with provided CPANEL_SSH_PASSPHRASE."
    echo "Proceeding with original key; if passphrase is valid, ssh-agent or ssh connection will be attempted."
  fi
fi

# 5. Validate that OpenSSH can parse the resulting key
if ssh-keygen -y -f "$KEY_DEST" >/dev/null 2>&1; then
  echo "✅ SSH private key is valid and ready for authentication."
else
  echo "❌ Error: OpenSSH cannot parse the private key. Key format may be invalid or passphrase incorrect." >&2
  rm -f "$KEY_DEST"
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "key_path=$KEY_DEST" >> "$GITHUB_OUTPUT"
fi
