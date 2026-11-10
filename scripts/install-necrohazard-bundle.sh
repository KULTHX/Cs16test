#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <hlds-dir> <bundle-url> <sha256-url>" >&2
  exit 2
fi

HLDS_DIR="$1"
BUNDLE_URL="$2"
SHA_URL="$3"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# zstd is present on current GitHub-hosted runners; install it if the image changes.
if ! command -v zstd >/dev/null 2>&1; then
  command -v sudo >/dev/null 2>&1 || { echo "ERROR: zstd is missing and sudo is unavailable" >&2; exit 1; }
  sudo apt-get install -y zstd
fi
for cmd in curl tar zstd sha256sum grep install awk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: required command is missing: $cmd" >&2; exit 1; }
done
[[ -d "$HLDS_DIR/cstrike" ]] || { echo "ERROR: missing cstrike directory: $HLDS_DIR/cstrike" >&2; exit 1; }

BUNDLE="$WORK_DIR/necrohazard-mod-bundle.tar.zst"
CHECKSUM="$WORK_DIR/necrohazard-mod-bundle.tar.zst.sha256"
curl --fail --location --retry 3 "$BUNDLE_URL" -o "$BUNDLE"
curl --fail --location --retry 3 "$SHA_URL" -o "$CHECKSUM"
EXPECTED="$(awk 'NF { print $1; exit }' "$CHECKSUM")"
[[ "$EXPECTED" =~ ^[[:xdigit:]]{64}$ ]] || { echo "ERROR: invalid SHA-256 manifest" >&2; exit 1; }
ACTUAL="$(sha256sum "$BUNDLE" | awk '{print $1}')"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo "ERROR: bundle checksum mismatch" >&2; exit 1; }
zstd -t "$BUNDLE"
tar --zstd -tf "$BUNDLE" > "$WORK_DIR/archive.list"
if ! awk '
  /^\// { bad=1 }
  {
    n=split($0, part, "/")
    for (i=1; i<=n; i++) if (part[i] == "..") bad=1
  }
  END { exit bad ? 1 : 0 }
' "$WORK_DIR/archive.list"; then
  echo "ERROR: archive contains an absolute or parent-traversal path" >&2
  exit 1
fi
if grep -Eq '(^|/)(server\.cfg|liblist\.gam|reunion\.cfg|hlds_run|engine_i486\.so)$|(^|/)addons/(metamod|reunion)/' "$WORK_DIR/archive.list"; then
  echo "ERROR: bundle attempts to replace protected engine, server, Metamod, or ReUnion files" >&2
  exit 1
fi

tar --zstd -xf "$BUNDLE" -C "$HLDS_DIR"

# The bundle intentionally excludes Metamod-R, ReUnion, liblist.gam, and server.cfg.
# Keep those components from the existing signed runtime and load the new AMXX/YaPB files.
META_PLUGINS="$HLDS_DIR/cstrike/addons/metamod/plugins.ini"
mkdir -p "$(dirname "$META_PLUGINS")"
touch "$META_PLUGINS"
# ReAPI is an AMX Mod X module, not a Metamod plugin. Loading its AMXX module
# from Metamod as well causes a duplicate-plugin ERROR during server startup.
sed -i -E '/reapi_amxx_i386\.so/Id' "$META_PLUGINS"
for line in \
  'linux addons/amxmodx/dlls/amxmodx_mm_i386.so' \
  'linux addons/yapb/bin/yapb.so'; do
  grep -Fqx "$line" "$META_PLUGINS" || printf '%s\n' "$line" >> "$META_PLUGINS"
done
if grep -Eiq 'reapi_amxx_i386\.so' "$META_PLUGINS"; then
  echo "ERROR: ReAPI must not be registered as a Metamod plugin." >&2
  exit 1
fi
# YaPB writes its path matrix here on first launch; ensure the directory exists.
mkdir -p "$HLDS_DIR/cstrike/addons/yapb/data/train"

[[ -f "$HLDS_DIR/cstrike/addons/amxmodx/dlls/amxmodx_mm_i386.so" ]] \
  || { echo "ERROR: AMX Mod X Metamod binary is missing after overlay" >&2; exit 1; }
[[ -f "$HLDS_DIR/cstrike/addons/amxmodx/plugins/lasermine.amxx" ]] \
  || { echo "ERROR: LaserMine plugin is missing after overlay" >&2; exit 1; }
[[ -f "$HLDS_DIR/cstrike/addons/amxmodx/configs/plugins.ini" ]] \
  || { echo "ERROR: AMX Mod X plugins.ini is missing after overlay" >&2; exit 1; }

echo "NECROHAZARD bundle verified and installed: $ACTUAL"
