#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash scripts/install-base-hlds.sh /path/to/steamcmd.sh /path/to/hlds"
  exit 2
}

[[ $# -eq 2 ]] || usage

STEAMCMD_INPUT="$1"
HLDS_DIR="$2"

if command -v "$STEAMCMD_INPUT" >/dev/null 2>&1; then
  STEAMCMD="$(command -v "$STEAMCMD_INPUT")"
elif [[ -x "$STEAMCMD_INPUT" ]]; then
  STEAMCMD="$STEAMCMD_INPUT"
else
  echo "ERROR: SteamCMD executable not found: $STEAMCMD_INPUT" >&2
  exit 1
fi

mkdir -p "$HLDS_DIR"
HLDS_DIR="$(cd "$HLDS_DIR" && pwd)"

echo "[1/2] Downloading the Counter-Strike 1.6 dedicated-server base files..."
echo "      These files are required by ReHLDS; the ReHLDS engine is installed separately."

"$STEAMCMD" \
  +force_install_dir "$HLDS_DIR" \
  +login anonymous \
  +app_set_config 90 mod cstrike \
  +app_update 90 -beta steam_legacy validate \
  +quit

[[ -f "$HLDS_DIR/hlds_run" ]] || {
  echo "ERROR: hlds_run was not found after SteamCMD completed." >&2
  exit 1
}
[[ -f "$HLDS_DIR/engine_i486.so" ]] || {
  echo "ERROR: Base engine_i486.so was not found after SteamCMD completed." >&2
  exit 1
}
[[ -f "$HLDS_DIR/cstrike/liblist.gam" ]] || {
  echo "ERROR: Counter-Strike game files are missing (cstrike/liblist.gam)." >&2
  exit 1
}

echo "[2/2] Base server files are ready at: $HLDS_DIR"
echo "Next: run scripts/install-rehlds.sh to replace the engine with ReHLDS."
