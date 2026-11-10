#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash scripts/install-reunion.sh /path/to/hlds"
  exit 2
}
[[ $# -eq 1 ]] || usage

HLDS_DIR="$1"
METAMOD_VERSION="${METAMOD_VERSION:-1.3.0.149}"
REUNION_VERSION="${REUNION_VERSION:-0.2.0.25}"
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "$HLDS_DIR/cstrike" ]] || fail "Missing cstrike directory: $HLDS_DIR/cstrike"
[[ -f "$HLDS_DIR/engine_i486.so" ]] || fail "ReHLDS engine is missing. Install ReHLDS first."
[[ -f "$HLDS_DIR/cstrike/liblist.gam" ]] || fail "Missing cstrike/liblist.gam"

for cmd in curl unzip find install sed grep openssl; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Required command is missing: $cmd"
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/metamod" "$WORK_DIR/reunion"

METAMOD_ARCHIVE="metamod-bin-${METAMOD_VERSION}.zip"
REUNION_ARCHIVE="reunion-${REUNION_VERSION}.zip"

echo "[1/5] Downloading pinned Metamod-R ${METAMOD_VERSION}..."
curl --fail --location --retry 3 \
  "https://github.com/rehlds/Metamod-R/releases/download/${METAMOD_VERSION}/${METAMOD_ARCHIVE}" \
  -o "$WORK_DIR/$METAMOD_ARCHIVE"
unzip -q "$WORK_DIR/$METAMOD_ARCHIVE" -d "$WORK_DIR/metamod"

echo "[2/5] Downloading pinned ReUnion ${REUNION_VERSION}..."
curl --fail --location --retry 3 \
  "https://github.com/rehlds/ReUnion/releases/download/${REUNION_VERSION}/${REUNION_ARCHIVE}" \
  -o "$WORK_DIR/$REUNION_ARCHIVE"
unzip -q "$WORK_DIR/$REUNION_ARCHIVE" -d "$WORK_DIR/reunion"

METAMOD_BIN="$(find "$WORK_DIR/metamod" -type f -name metamod_i386.so -print -quit)"
REUNION_BIN="$(find "$WORK_DIR/reunion" -type f -name reunion_mm_i386.so -print -quit)"
REUNION_CFG="$(find "$WORK_DIR/reunion" -type f -name reunion.cfg -print -quit)"

[[ -n "$METAMOD_BIN" ]] || fail "metamod_i386.so was not found in the official release archive."
[[ -n "$REUNION_BIN" ]] || fail "reunion_mm_i386.so was not found in the official release archive."
[[ -n "$REUNION_CFG" ]] || fail "reunion.cfg was not found in the official release archive."

echo "[3/5] Installing the Linux 32-bit plugins..."
GAME_DIR="$HLDS_DIR/cstrike"
mkdir -p "$GAME_DIR/addons/metamod" "$GAME_DIR/addons/reunion"
install -m 0755 "$METAMOD_BIN" "$GAME_DIR/addons/metamod/metamod_i386.so"
install -m 0755 "$REUNION_BIN" "$GAME_DIR/addons/reunion/reunion_mm_i386.so"

# ReUnion 0.2.0.25 reads reunion.cfg from the game directory or server root.
# Keep the runtime config at cstrike/reunion.cfg, not inside addons/reunion/.
REUNION_CONFIG="$GAME_DIR/reunion.cfg"
if [[ ! -f "$REUNION_CONFIG" ]]; then
  install -m 0644 "$REUNION_CFG" "$REUNION_CONFIG"
fi

echo "[4/5] Configuring Metamod-R and ReUnion..."
PLUGINS_INI="$GAME_DIR/addons/metamod/plugins.ini"
mkdir -p "$(dirname "$PLUGINS_INI")"
PLUGIN_LINE="linux addons/reunion/reunion_mm_i386.so"
if [[ ! -f "$PLUGINS_INI" ]]; then
  printf '%s\n' "$PLUGIN_LINE" > "$PLUGINS_INI"
elif ! grep -Fqx "$PLUGIN_LINE" "$PLUGINS_INI"; then
  TMP_PLUGINS="$(mktemp)"
  { printf '%s\n' "$PLUGIN_LINE"; cat "$PLUGINS_INI"; } > "$TMP_PLUGINS"
  install -m 0644 "$TMP_PLUGINS" "$PLUGINS_INI"
  rm -f "$TMP_PLUGINS"
fi

LIBLIST="$GAME_DIR/liblist.gam"
if ! grep -Eq '^[[:space:]]*gamedll_linux[[:space:]]+"addons/metamod/metamod_i386\.so"' "$LIBLIST"; then
  grep -Eq '^[[:space:]]*gamedll_linux[[:space:]]+' "$LIBLIST" \
    || fail "Could not find gamedll_linux in liblist.gam; refusing to rewrite it."
  BACKUP="$LIBLIST.before-metamod.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$LIBLIST" "$BACKUP"
  sed -i -E 's#^[[:space:]]*gamedll_linux[[:space:]]+.*$#gamedll_linux "addons/metamod/metamod_i386.so"#' "$LIBLIST"
  echo "Original liblist backup: $BACKUP"
fi

REUNION_CONFIG="$GAME_DIR/reunion.cfg"
if [[ -n "${REUNION_HASH_SALT:-}" ]]; then
  [[ "$REUNION_HASH_SALT" =~ ^[A-Za-z0-9_-]{32,}$ ]] \
    || fail "REUNION_HASH_SALT must contain at least 32 letters, digits, underscores, or hyphens."
  if grep -Eq '^[[:space:]]*SteamIdHashSalt[[:space:]]*=' "$REUNION_CONFIG"; then
    sed -i -E "s/^[[:space:]]*SteamIdHashSalt[[:space:]]*=.*/SteamIdHashSalt = $REUNION_HASH_SALT/" "$REUNION_CONFIG"
  else
    printf '\nSteamIdHashSalt = %s\n' "$REUNION_HASH_SALT" >> "$REUNION_CONFIG"
  fi
else
  if ! grep -Eq '^[[:space:]]*SteamIdHashSalt[[:space:]]*=[[:space:]]*[^[:space:]]+' "$REUNION_CONFIG"; then
    SALT="$(openssl rand -hex 32)"
    if grep -Eq '^[[:space:]]*SteamIdHashSalt[[:space:]]*=' "$REUNION_CONFIG"; then
      sed -i -E "s/^[[:space:]]*SteamIdHashSalt[[:space:]]*=.*/SteamIdHashSalt = $SALT/" "$REUNION_CONFIG"
    else
      printf '\nSteamIdHashSalt = %s\n' "$SALT" >> "$REUNION_CONFIG"
    fi
  fi
fi

# Permit legacy protocol 47/48 clients that do not provide a unique auth ID.
# Type 3 derives an identity from the remote IP; see docs for shared-NAT caveats.
sed -i -E \
  -e 's/^[[:space:]]*cid_NoSteam47[[:space:]]*=.*/cid_NoSteam47 = 3/' \
  -e 's/^[[:space:]]*cid_NoSteam48[[:space:]]*=.*/cid_NoSteam48 = 3/' \
  -e 's/^[[:space:]]*AuthVersion[[:space:]]*=.*/AuthVersion = 3/' \
  -e 's/^[[:space:]]*IDClientsLimit[[:space:]]*=.*/IDClientsLimit = 0/' \
  "$REUNION_CONFIG"

grep -Eq '^[[:space:]]*SteamIdHashSalt[[:space:]]*=[[:space:]]*[^[:space:]]+' "$REUNION_CONFIG" \
  || fail "ReUnion SteamIdHashSalt is empty; refusing to install an unusable config."
grep -Eq '^[[:space:]]*cid_NoSteam47[[:space:]]*=[[:space:]]*3([[:space:]]|$)' "$REUNION_CONFIG" \
  || fail "Could not configure protocol 47 client identity mapping."
grep -Eq '^[[:space:]]*cid_NoSteam48[[:space:]]*=[[:space:]]*3([[:space:]]|$)' "$REUNION_CONFIG" \
  || fail "Could not configure protocol 48 client identity mapping."

echo "[5/5] Installed Metamod-R ${METAMOD_VERSION} and ReUnion ${REUNION_VERSION}."
echo "At server startup, check the console with: meta list"
echo "Expected: Reunion should appear with status RUN."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MOD_BUNDLE_URL="https://github.com/KULTHX/Cs16test/releases/download/necrohazard-zp-20261110/necrohazard_mod_bundle_20261110T033000Z.tar.zst"
MOD_BUNDLE_SHA256_URL="https://github.com/KULTHX/Cs16test/releases/download/necrohazard-zp-20261110/necrohazard_mod_bundle_20261110T033000Z.tar.zst.sha256"

echo "[6/6] Installing the NECROHAZARD Zombie Plague bundle..."
bash "$SCRIPT_DIR/install-necrohazard-bundle.sh" "$HLDS_DIR" "$MOD_BUNDLE_URL" "$MOD_BUNDLE_SHA256_URL"
