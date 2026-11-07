#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-config/server.cfg.example}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

[[ -f "$CONFIG_FILE" ]] || fail "Config file not found: $CONFIG_FILE"

# Remove comments and blank lines before checking expected baseline settings.
active_config="$(sed 's,//.*$,,' "$CONFIG_FILE" | sed '/^[[:space:]]*$/d')"

grep -Eiq '^[[:space:]]*sv_lan[[:space:]]+0([[:space:]]|$)' <<<"$active_config" \
  || fail "Expected sv_lan 0 for an Internet server."

grep -Eiq '^[[:space:]]*maxplayers[[:space:]]+(20|21|22|23|24|25|26|27|28|29|30|31|32)([[:space:]]|$)' <<<"$active_config" \
  || fail "Expected maxplayers between 20 and 32."

grep -Eiq '^[[:space:]]*hostname[[:space:]]+".+"' <<<"$active_config" \
  || fail "A non-empty quoted hostname is required."

# Reject accidentally committed inline RCON credentials.
if grep -Eiq '^[[:space:]]*rcon_password[[:space:]]+' "$CONFIG_FILE"; then
  fail "Do not store an RCON password in the tracked example config."
fi

printf 'Configuration looks structurally valid: %s\n' "$CONFIG_FILE"
