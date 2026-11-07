#!/usr/bin/env bash
set -euo pipefail

SERVER_DIR="${CS16_SERVER_DIR:-/opt/cs16}"
STEAMCMD_DIR="${CS16_STEAMCMD_DIR:-/opt/steamcmd}"
PORT="${CS16_PORT:-27015}"
SLOTS="${CS16_SLOTS:-20}"
MAP="${CS16_MAP:-de_dust2}"

[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "Invalid CS16_PORT: $PORT" >&2; exit 2; }
[[ "$SLOTS" =~ ^([1-9]|[12][0-9]|3[0-2])$ ]] || {
  echo "CS16_SLOTS must be between 1 and 32." >&2
  exit 2
}
[[ "$MAP" =~ ^[A-Za-z0-9_/-]+$ ]] || { echo "Invalid CS16_MAP." >&2; exit 2; }
[[ -x "$SERVER_DIR/hlds_run" ]] || { echo "Missing $SERVER_DIR/hlds_run" >&2; exit 1; }

export LD_LIBRARY_PATH="$HOME/.steam/sdk32:$STEAMCMD_DIR/linux32:${LD_LIBRARY_PATH:-}"
cd "$SERVER_DIR"

exec ./hlds_run -norestart -game cstrike -console -ip 0.0.0.0 \
  -port "$PORT" +maxplayers "$SLOTS" +map "$MAP"
