#!/usr/bin/env bash
set -euo pipefail

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "$EUID" -eq 0 ]] || fail "Run this provisioning script as root (for example: sudo bash scripts/provision-ubuntu-host.sh)."

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_USER="${CS16_SERVER_USER:-cs16}"
SERVER_DIR="${CS16_SERVER_DIR:-/opt/cs16}"
STEAMCMD_DIR="${CS16_STEAMCMD_DIR:-/opt/steamcmd}"
STEAMWORKS_DIR="${CS16_STEAMWORKS_DIR:-/opt/steamworks-redist}"
REHLDS_VERSION="${REHLDS_VERSION:-3.15.0.896}"

for cmd in apt-get curl tar runuser file find install systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Required command is missing: $cmd"
done

if [[ ! -r /etc/os-release ]]; then fail "Cannot identify the Linux distribution."; fi
. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) fail "This script supports Ubuntu and Debian hosts only (found: ${ID:-unknown})." ;;
esac

echo "[1/8] Installing Linux x86 and 32-bit runtime dependencies..."
dpkg --add-architecture i386
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl gpg unzip file openssl \
  lib32gcc-s1 lib32stdc++6 lib32z1 libc6:i386 libstdc++6:i386

if ! id "$SERVER_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "/home/$SERVER_USER" \
    --shell /usr/sbin/nologin "$SERVER_USER"
fi
SERVER_HOME="$(getent passwd "$SERVER_USER" | cut -d: -f6)"
[[ -n "$SERVER_HOME" && -d "$SERVER_HOME" ]] || fail "Could not determine home directory for $SERVER_USER."

mkdir -p "$SERVER_DIR" "$STEAMCMD_DIR" "$STEAMWORKS_DIR"
chown -R "$SERVER_USER:$SERVER_USER" "$SERVER_DIR" "$STEAMCMD_DIR" "$STEAMWORKS_DIR"

echo "[2/8] Downloading SteamCMD..."
if [[ ! -x "$STEAMCMD_DIR/steamcmd.sh" ]]; then
  curl --fail --location --retry 3 \
    https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    -o "$STEAMCMD_DIR/steamcmd_linux.tar.gz"
  tar -xzf "$STEAMCMD_DIR/steamcmd_linux.tar.gz" -C "$STEAMCMD_DIR"
  chown -R "$SERVER_USER:$SERVER_USER" "$STEAMCMD_DIR"
fi
[[ -x "$STEAMCMD_DIR/steamcmd.sh" ]] || fail "SteamCMD installation did not produce steamcmd.sh."

echo "[3/8] Installing CS 1.6 base server files (SteamCMD app 90)..."
runuser -u "$SERVER_USER" -- bash "$REPO_ROOT/scripts/install-base-hlds.sh" \
  "$STEAMCMD_DIR/steamcmd.sh" "$SERVER_DIR"

echo "[4/8] Installing the official Steamworks Linux runtime (app 1007)..."
runuser -u "$SERVER_USER" -- "$STEAMCMD_DIR/steamcmd.sh" \
  +force_install_dir "$STEAMWORKS_DIR" +login anonymous +app_update 1007 validate +quit

echo "[5/8] Linking the 32-bit Steam client runtime..."
STEAMCLIENT=""
while IFS= read -r candidate; do
  [[ -n "$candidate" ]] || continue
  DESCRIPTION="$(file -b "$candidate" || true)"
  if [[ "$DESCRIPTION" == *"ELF 32-bit"* ]]; then
    STEAMCLIENT="$candidate"
    break
  fi
done < <(find "$STEAMWORKS_DIR" "$STEAMCMD_DIR" "$SERVER_DIR" -type f -name steamclient.so -print 2>/dev/null)

[[ -n "$STEAMCLIENT" ]] || fail "No 32-bit steamclient.so found in the installed Steamworks runtime."
mkdir -p "$SERVER_HOME/.steam/sdk32"
ln -sfn "$STEAMCLIENT" "$SERVER_HOME/.steam/sdk32/steamclient.so"
chown -R "$SERVER_USER:$SERVER_USER" "$SERVER_HOME/.steam"
file "$SERVER_HOME/.steam/sdk32/steamclient.so"

echo "[6/8] Installing signed ReHLDS and ReUnion compatibility layer..."
runuser -u "$SERVER_USER" -- env REHLDS_VERSION="$REHLDS_VERSION" \
  bash "$REPO_ROOT/scripts/install-rehlds.sh" "$SERVER_DIR"
runuser -u "$SERVER_USER" -- bash "$REPO_ROOT/scripts/install-reunion.sh" "$SERVER_DIR"

if [[ ! -f "$SERVER_DIR/cstrike/server.cfg" ]]; then
  install -m 0640 "$REPO_ROOT/config/server.cfg.example" "$SERVER_DIR/cstrike/server.cfg"
fi

echo "[7/8] Installing systemd launcher and service..."
install -m 0755 "$REPO_ROOT/deploy/start-cs16-rehlds.sh" /usr/local/bin/cs16-rehlds-start
install -m 0644 "$REPO_ROOT/deploy/cs16-rehlds.service" /etc/systemd/system/cs16-rehlds.service
if [[ ! -f /etc/default/cs16-rehlds ]]; then
  install -m 0600 "$REPO_ROOT/deploy/cs16-rehlds.env.example" /etc/default/cs16-rehlds
fi
chown -R "$SERVER_USER:$SERVER_USER" "$SERVER_DIR"
systemctl daemon-reload
systemctl enable --now cs16-rehlds.service

echo "[8/8] ReHLDS host provisioned."
systemctl --no-pager --full status cs16-rehlds.service || true
cat <<EOF

Next:
  1. Install/claim the Playit agent once: sudo bash scripts/install-playit-agent.sh
  2. Run 'sudo playit setup' on this host to claim the agent to your Playit account.
  3. In the Playit dashboard create a UDP tunnel to 127.0.0.1:27015.
  4. Enable the Playit service: sudo systemctl enable --now playit
  5. Share the public hostname and port assigned by Playit.

Service management:
  sudo systemctl status cs16-rehlds
  sudo journalctl -u cs16-rehlds -f
  sudo systemctl restart cs16-rehlds

The initial server slot count is 20. Increase CS16_SLOTS in /etc/default/cs16-rehlds
only after real client and network tests; maximum configured value is 32.
EOF
