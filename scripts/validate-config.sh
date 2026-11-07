#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-config/server.cfg.example}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

[[ -f "$CONFIG_FILE" ]] || fail "Config file not found: $CONFIG_FILE"

# Strip // comments and blank lines before checking required directives.
active_config="$(sed 's,//.*$,,' "$CONFIG_FILE" | sed '/^[[:space:]]*$/d')"

grep -Eiq '^[[:space:]]*sv_lan[[:space:]]+0([[:space:]]|$)' <<<"$active_config" \
  || fail "Expected sv_lan 0 for an Internet server."

grep -Eiq '^[[:space:]]*hostname[[:space:]]+".+"' <<<"$active_config" \
  || fail "A non-empty quoted hostname is required."

# maxplayers is passed to HLDS at launch, not placed in server.cfg.
if grep -Eiq '^[[:space:]]*maxplayers[[:space:]]+' "$CONFIG_FILE"; then
  fail "Move maxplayers to the HLDS startup arguments (for example +maxplayers 32)."
fi

# Reject accidentally committed inline RCON credentials.
if grep -Eiq '^[[:space:]]*rcon_password[[:space:]]+' "$CONFIG_FILE"; then
  fail "Do not store an RCON password in the tracked example config."
fi

printf 'Configuration looks structurally valid: %s\n' "$CONFIG_FILE"
