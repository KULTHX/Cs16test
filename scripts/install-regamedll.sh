#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <hlds-dir>" >&2
  exit 2
fi

HLDS_DIR="$1"
VERSION="${REGAMEDLL_VERSION:-5.30.0.814}"
EXPECTED_SHA256="457f5c96a4d10280fcad47f106cbd5be86363a47df1ccab91c514e9d1bc6fd18"
ARCHIVE="regamedll-bin-${VERSION}.zip"
URL="https://github.com/rehlds/ReGameDLL_CS/releases/download/${VERSION}/${ARCHIVE}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() { echo "ERROR: $*" >&2; exit 1; }
for cmd in curl unzip sha256sum install file grep; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Required command is missing: $cmd"
done

[[ -d "$HLDS_DIR/cstrike" ]] || fail "Missing cstrike directory: $HLDS_DIR/cstrike"
[[ -f "$HLDS_DIR/cstrike/liblist.gam" ]] || fail "Missing cstrike/liblist.gam"
grep -Eq '^[[:space:]]*gamedll_linux[[:space:]]+"addons/metamod/metamod_i386\.so"' \
  "$HLDS_DIR/cstrike/liblist.gam" \
  || fail "Metamod-R must remain the Linux loader in liblist.gam."

ZIP="$WORK_DIR/$ARCHIVE"
echo "Downloading official ReGameDLL_CS $VERSION..."
curl --fail --location --retry 3 "$URL" -o "$ZIP"
echo "$EXPECTED_SHA256  $ZIP" | sha256sum --check --status \
  || fail "ReGameDLL archive SHA-256 mismatch."
unzip -tq "$ZIP"
unzip -q "$ZIP" -d "$WORK_DIR/unpacked"

SOURCE="$WORK_DIR/unpacked/bin/linux32/cstrike"
[[ -s "$SOURCE/dlls/cs.so" ]] || fail "Official Linux GameDLL bin/linux32/cstrike/dlls/cs.so is missing."
[[ -s "$SOURCE/delta.lst" ]] || fail "Official ReGameDLL delta.lst is missing."
DESCRIPTION="$(file -b "$SOURCE/dlls/cs.so")"
[[ "$DESCRIPTION" == *"ELF 32-bit"* ]] || fail "Downloaded cs.so is not a Linux 32-bit ELF binary."

TARGET="$HLDS_DIR/cstrike"
mkdir -p "$TARGET/dlls"
if [[ -s "$TARGET/dlls/cs.so" ]]; then
  cp -p "$TARGET/dlls/cs.so" "$WORK_DIR/cs.so.before-regamedll"
  echo "Saved original GameDLL inside temporary runner workspace."
fi
install -m 0755 "$SOURCE/dlls/cs.so" "$TARGET/dlls/cs.so"
install -m 0644 "$SOURCE/delta.lst" "$TARGET/delta.lst"

# Do not seed game.cfg/game_init.cfg defaults: NECROHAZARD owns its gameplay CVars.
# Existing mod-specific copies, if any, are left untouched.
for cfg in game.cfg game_init.cfg; do
  if [[ -s "$TARGET/$cfg" ]]; then
    echo "Preserving existing cstrike/$cfg"
  fi
done

[[ -s "$TARGET/dlls/cs.so" ]] || fail "ReGameDLL GameDLL was not installed."
grep -Eq '^[[:space:]]*gamedll_linux[[:space:]]+"addons/metamod/metamod_i386\.so"' \
  "$TARGET/liblist.gam" || fail "ReGameDLL install changed the Metamod loader."
echo "Installed official ReGameDLL_CS $VERSION: $TARGET/dlls/cs.so"
